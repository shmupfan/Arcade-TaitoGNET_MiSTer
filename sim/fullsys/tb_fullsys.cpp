// Full-system simulation harness (docs/fullsys_sim.md): PSX_MiSTer psx_top
// (GHDL netlist) with the real sdram.sv, in Verilator.
//
// Models in this file:
//  - SDRAM chip, 32 MB: commands on the falling controller clock (SDRAM_CLK =
//    ~clk3x), CAS latency 2, burst 2, DQML/DQMH = A11/A12 (as the R1 and
//    zn2 system benches). BIOS at byte 0x800000 (PSX.sv bios_download, slot 0),
//    optional flash.u30 at 0x1000000 with U27 and the wave flashes erased.
//  - DDR3 (Avalon, as sim/system/src/tb/ddrram_model.vhd): reads answer
//    BURSTCNT words after LAT clk2x cycles, single-beat writes with byte
//    enables, BUSY never set.
//  - Clocks: clk1x 33.8688 MHz, clk2x and clk3x at 2x and 3x with rising
//    edges aligned (one PLL), clkvid 53.693175 MHz (G-NET fixed video clock).
//    No logic uses a falling edge, so falling clocks are folded into the
//    next evaluation (6 evaluations per clk1x period plus clkvid).
// Outputs (in -out DIR): progress.log, gpu.log (every CPU write to GP0/GP1:
// "<us> GP<n> <hex>", microseconds truncated as in the zn2 system bench;
// "GPD" for DMA words, "GR0" for CPU reads of GPUREAD), frames/fNNNNN.ppm from
// the video output, vram_<ms>.bin (first 2 MB of DDR3) at the first vsync
// after every -vram_ms.
// Checkpoints (-ckpt_ms N, a build with VFLAGS=--savable): every N emulated
// ms the model (VerilatedSave), the harness models, both memories and the
// log lengths go to ckpt_<ms>.model/.harness in -out (the last two are
// kept). -restore <out>/ckpt_<ms> continues from one with the same other
// arguments; the logs are cut back to the checkpoint and appended to.
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <chrono>
#include <sys/stat.h>
#include "Vfs_top.h"
#include "verilated.h"
#ifdef FS_SAVABLE
#include "verilated_save.h"
#endif
#include <unistd.h>
#include "fs_defaults.h"

static double now_ps = 0;
static Vfs_top* top;

// ---------------------------------------------------------------- SDRAM chip
static uint16_t* sdram;                       // 16 M words, key = ba & row & col
struct SdramChip {
    uint32_t rows[4] = {0, 0, 0, 0};
    uint16_t q[5] = {0, 0, 0, 0, 0};
    bool qv[5] = {false, false, false, false, false};
    uint16_t dq_r = 0;
    // read DQM (DQML = A11, DQMH = A12 on MiSTer, sdram.sv:88): sampled at
    // every SDRAM clock, masks the read data two clocks later (latency 2);
    // a masked byte is not driven and reads as dqm_float (-dqm 1 enables)
    bool dqm_on = false; uint8_t mq[3] = {0, 0, 0}; uint16_t dqm_float = 0x5A5A; uint64_t nmasked = 0;
    // called at a falling clk3x edge with the pins the controller drove at the last rising edge
    void edge(uint8_t ncs, uint8_t nras, uint8_t ncas, uint8_t nwe, uint8_t ba, uint16_t a, uint16_t dqw) {
        for (int i = 0; i < 4; i++) { q[i] = q[i + 1]; qv[i] = qv[i + 1]; }
        qv[4] = false;
        mq[0] = mq[1]; mq[1] = mq[2]; mq[2] = (a >> 11) & 3;   // DQM of this clock (sampled with or without CS)
        if (!ncs) {
            if (!nras && ncas && nwe) rows[ba] = a & 0x1fff;                      // ACTIVE
            else if (nras && !ncas) {
                uint32_t key = ((uint32_t)ba << 22) | (rows[ba] << 9) | (a & 0x1ff);
                if (nwe) {                                                        // READ, burst 2
                    q[2] = sdram[key]; qv[2] = true;
                    q[3] = sdram[key ^ 1]; qv[3] = true;
                } else {                                                          // WRITE
                    uint16_t d = sdram[key];
                    if (!(a & 0x800)) d = (d & 0xff00) | (dqw & 0x00ff);
                    if (!(a & 0x1000)) d = (d & 0x00ff) | (dqw & 0xff00);
                    sdram[key] = d;
                }
            }
        }
        if (qv[0]) {
            uint16_t d = q[0];
            if (dqm_on && mq[0]) {
                if (mq[0] & 1) d = (d & 0xff00) | (dqm_float & 0x00ff);
                if (mq[0] & 2) d = (d & 0x00ff) | (dqm_float & 0xff00);
                nmasked++;
            }
            dq_r = d;                         // undriven bus keeps its last value
        }
    }
} chip;

// ---------------------------------------------------------------- DDR3
static uint64_t* ddr;                         // 256 MB, word = ADDR(27:3)
// Hardware-like timing (all off by default, then the model is the old fixed
// one): -ddr_lat N base read latency in clk2x (default 15), -ddr_jit J extra
// 0..J per read, -ddr_gap P percent chance of an idle clk2x between burst
// beats, -ddr_busy P percent chance per clk2x that BUSY (waitrequest) is high,
// when no command is accepted; -ddr_seed S for the generator.
static int DDR_LAT = 15, DDR_JIT = 0, DDR_GAP = 0, DDR_BUSYP = 0;
// BUSY while a read is in flight (Avalon waitrequest), so a command issued
// meanwhile is held, not lost: on for gnet_ddr3_arb builds, whose arbiter
// may issue while a read is outstanding; -ddr_hold 0|1 overrides
static int DDR_HOLD = -1;
static uint64_t ddr_rng = 0x9E3779B97F4A7C15ULL;
static uint32_t ddr_rand() { ddr_rng ^= ddr_rng << 13; ddr_rng ^= ddr_rng >> 7; ddr_rng ^= ddr_rng << 17; return (uint32_t)(ddr_rng >> 16); }
struct Ddr3 {
    int state = 0;                            // 0 idle, 1 latency, 2 burst
    uint32_t w = 0; int bc = 0, cnt = 0;
    uint64_t dout = 0; bool ready = false; bool busy = false;
    uint64_t nrd = 0, nwr = 0;
    // one clk2x rising edge; rd/we/... are the DUT outputs before the edge,
    // busy is the BUSY level the DUT saw in the cycle before the edge
    void edge(bool rd, bool we, uint32_t addr, int burst, uint64_t din, uint8_t be) {
        if (state == 0) {
            ready = false;
            if (busy) { }
            else if (rd) { w = (addr >> 3) & 0x1ffffff; bc = burst; cnt = DDR_LAT + (DDR_JIT ? (int)(ddr_rand() % (DDR_JIT + 1)) : 0); state = 1; nrd++; }
            else if (we) {
                uint32_t a = (addr >> 3) & 0x1ffffff;
                uint64_t v = ddr[a];
                for (int b = 0; b < 8; b++)
                    if (be & (1 << b)) v = (v & ~(0xffULL << (8 * b))) | (din & (0xffULL << (8 * b)));
                ddr[a] = v; nwr++;
            }
        } else if (state == 1) {
            if (--cnt <= 0) state = 2;
        }
        if (state == 2) {
            if (bc > 0) {
                if (DDR_GAP && (int)(ddr_rand() % 100) < DDR_GAP) ready = false;
                else { dout = ddr[w & 0x1ffffff]; ready = true; w++; bc--; }
            }
            else { ready = false; state = 0; }
        }
        busy = (DDR_HOLD > 0 && state != 0) || (DDR_BUSYP && state == 0 && (int)(ddr_rand() % 100) < DDR_BUSYP);
    }
} ddr3;

// ---------------------------------------------------------------- video
// frames.tsv, one row per frame (all frames), the format agreed with the
// MAME side (gnet-games tools/frame_hash.py), integer arithmetic throughout:
//   #frame t_s w h crc555 crc555_x1 ahash dhash luma
// t_s: emulated seconds at the frame's vblank start (power-on = 0).
// r5 g5 b5 = 8-bit channel >> 3; w555 = r5<<10 | g5<<5 | b5, 2 bytes LE.
// crc555: zlib CRC-32 over w555 row-major over w x h; crc555_x1 over columns
//   1..w-1 (MAME: 0..w-2; its snapshots start one VRAM column later, doc D3).
// Y = 299 r5 + 587 g5 + 114 b5 (0..31000). Cell (i, j) of an nx x ny grid:
//   x in [floor(i w/nx), floor((i+1) w/nx)), y likewise; C = floor(sum Y / area).
// ahash: 8x8, bit = 64 C > sum of the 64 C; dhash: 9x8, bit = C[j][i] < C[j][i+1];
//   row-major, first cell in bit 63. luma = sum Y / (w h) * 255 / 31000.
static uint32_t crc_tab[256];
static uint32_t crc32_upd(uint32_t c, const uint8_t* p, size_t n) {
    if (!crc_tab[1]) for (uint32_t i = 0; i < 256; i++) { uint32_t v = i; for (int k = 0; k < 8; k++) v = v & 1 ? 0xEDB88320u ^ (v >> 1) : v >> 1; crc_tab[i] = v; }
    c = ~c; for (size_t i = 0; i < n; i++) c = crc_tab[(c ^ p[i]) & 0xff] ^ (c >> 8); return ~c;
}
static uint64_t block_hash(const std::vector<uint32_t>& Y, int w, int h, int bx, int by, bool diff) {
    std::vector<uint64_t> m(bx * by);
    for (int j = 0; j < by; j++) for (int i = 0; i < bx; i++) {
        int x0 = (int)((int64_t)i * w / bx), x1 = (int)((int64_t)(i + 1) * w / bx), y0 = (int)((int64_t)j * h / by), y1 = (int)((int64_t)(j + 1) * h / by);
        uint64_t sum = 0; int64_t n = (int64_t)(x1 - x0) * (y1 - y0);
        for (int y = y0; y < y1; y++) for (int x = x0; x < x1; x++) sum += Y[(size_t)y * w + x];
        m[j * bx + i] = n > 0 ? sum / (uint64_t)n : 0;
    }
    uint64_t hsh = 0;
    if (!diff) { uint64_t S = 0; for (uint64_t v : m) S += v; for (uint64_t v : m) hsh = (hsh << 1) | (64 * v > S); }
    else for (int j = 0; j < by; j++) for (int i = 0; i < bx - 1; i++) hsh = (hsh << 1) | (m[j * bx + i] < m[j * bx + i + 1]);
    return hsh;
}
struct Video {
    std::string dir; int every = 1; long frames = 0; FILE* ftsv = nullptr; double t_ps = 0;
    std::vector<uint8_t> line, img; int lines = 0, width = 0;
    bool hb1 = true, vb1 = true;
    void sample(bool ce, bool hb, bool vb, uint8_t r, uint8_t g, uint8_t b) {
        if (ce && !hb && !vb) { line.push_back(r); line.push_back(g); line.push_back(b); }
        if (hb && !hb1 && !line.empty()) {
            int w = line.size() / 3;
            if (lines == 0) width = w;
            if (w == width) { img.insert(img.end(), line.begin(), line.end()); lines++; }
            line.clear();
        }
        if (vb && !vb1) {
            frames++;
            if (!ftsv) { ftsv = fopen((dir + "/frames.tsv").c_str(), "w"); if (ftsv) fprintf(ftsv, "#frame\tt_s\tw\th\tcrc555\tcrc555_x1\tahash\tdhash\tluma\n"); }
            if (ftsv) {
                int w = lines > 0 ? width : 0, h = lines;
                std::vector<uint32_t> Y((size_t)w * h); std::vector<uint8_t> row; uint32_t c0 = 0, c1 = 0; uint64_t ysum = 0;
                for (int y = 0; y < h; y++) {
                    row.clear();
                    for (int x = 0; x < w; x++) {
                        const uint8_t* q = &img[((size_t)y * w + x) * 3];
                        uint32_t r5 = q[0] >> 3, g5 = q[1] >> 3, b5 = q[2] >> 3;
                        uint16_t v = (uint16_t)(r5 << 10 | g5 << 5 | b5);
                        row.push_back(v & 0xff); row.push_back(v >> 8);
                        uint32_t yy = 299u * r5 + 587u * g5 + 114u * b5; Y[(size_t)y * w + x] = yy; ysum += yy;
                    }
                    c0 = crc32_upd(c0, row.data(), row.size());
                    if (w > 1) c1 = crc32_upd(c1, row.data() + 2, row.size() - 2);
                }
                fprintf(ftsv, "%ld\t%.6f\t%d\t%d\t%08x\t%08x\t%016llx\t%016llx\t%.2f\n", frames, t_ps / 1e12, w, h, c0, c1,
                        (unsigned long long)(w && h ? block_hash(Y, w, h, 8, 8, false) : 0), (unsigned long long)(w && h ? block_hash(Y, w, h, 9, 8, true) : 0),
                        w && h ? (double)ysum / ((double)w * h) * 255.0 / 31000.0 : 0.0);
                if (frames % 60 == 0) fflush(ftsv);
            }
            if (every > 0 && lines > 0 && frames % every == 0) {
                char fn[512]; snprintf(fn, sizeof fn, "%s/frames/f%05ld.ppm", dir.c_str(), frames);
                FILE* f = fopen(fn, "wb");
                if (f) { fprintf(f, "P6\n%d %d\n255\n", width, lines); fwrite(img.data(), 1, img.size(), f); fclose(f); }
            }
            img.clear(); lines = 0; line.clear();
        }
        hb1 = hb; vb1 = vb;
    }
} video;

// hex byte list, one per line (keys.hex, meta.hex from the zn2 prep.py layout)
static std::vector<uint8_t> read_hex(const char* fn) {
    std::vector<uint8_t> v; FILE* f = fopen(fn, "r");
    if (!f) { fprintf(stderr, "cannot open %s\n", fn); exit(1); }
    unsigned x; while (fscanf(f, "%x", &x) == 1) v.push_back(x); fclose(f); return v;
}

#if FS_HAS_DL
// ---------------------------------------------------------------- MiSTer download
// One download per line of the -dl list, in MRA order: "<index> <part> ..."
// with parts "<file>", "fill:<count>:<hexbyte>", "hex:<bytes>". Emulates
// sys_top's HPS strobe/ack handshake (io_clk, rack, io_ack frozen while
// io_wait) and hps_io's fio_block (FIO_FILE_TX_DAT: address +2 except the
// first word, ioctl_dout, wr, then ioctl_wr one clock later), clocked by
// clk_sys = clk1x. The HPS program writes io_clk with the data, polls io_ack,
// writes io_clk low, polls io_ack low; -hps_w / -hps_r are its bus write and
// read times in clk1x cycles.
struct DlFile { int index; std::vector<uint8_t> data; std::string desc; };
static std::vector<DlFile> read_dl_list(const char* fn) {
    std::vector<DlFile> v; FILE* f = fopen(fn, "r");
    if (!f) { fprintf(stderr, "cannot open %s\n", fn); exit(1); }
    char line[4096];
    while (fgets(line, sizeof line, f)) {
        char* s = strtok(line, " \t\r\n");
        if (!s || s[0] == '#') continue;
        DlFile d; d.index = atoi(s);
        while ((s = strtok(nullptr, " \t\r\n"))) {
            std::string a = s; d.desc += a + " ";
            if (a.rfind("fill:", 0) == 0) {
                unsigned long n = strtoul(a.c_str() + 5, nullptr, 0); unsigned b = strtoul(strchr(a.c_str() + 5, ':') + 1, nullptr, 16);
                d.data.insert(d.data.end(), n, (uint8_t)b);
            } else if (a.rfind("hex:", 0) == 0) {
                for (size_t i = 4; i + 1 < a.size(); i += 2) d.data.push_back(strtoul(a.substr(i, 2).c_str(), nullptr, 16));
            } else {
                FILE* g = fopen(a.c_str(), "rb"); if (!g) { fprintf(stderr, "cannot open %s\n", a.c_str()); exit(1); }
                fseek(g, 0, SEEK_END); long n = ftell(g); fseek(g, 0, SEEK_SET);
                size_t o = d.data.size(); d.data.resize(o + n);
                if (fread(d.data.data() + o, 1, n, g) != (size_t)n) { fprintf(stderr, "short read %s\n", a.c_str()); exit(1); }
                fclose(g);
            }
        }
        if (d.data.size() & 1) d.data.push_back(0);
        v.push_back(d);
    }
    fclose(f);
    return v;
}
struct Hps {
    // sys_top
    bool gp_out_clk = 0, gpd_clk = 0, gpr_clk = 0; uint16_t gp_out_d = 0, gpd_d = 0, gpr_d = 0;
    bool rack = 0, io_ack = 0;
    // hps_io fio_block
    bool wr = 0, ioctl_wr = 0, skip_add = 0, download = 0; uint32_t addr = 0; uint16_t dout = 0, index = 0;
    // HPS program
    int file = -1; size_t word = 0; int st = 0; int cnt = 0; double t_next = 0; bool done = false;
    int hps_w = 2, hps_r = 2; double gap_ps = 1e9;
    // one clk1x edge; wait = ioctl_wait before the edge
    void edge(bool wait, double now, std::vector<DlFile>& files, FILE* log) {
        bool strobe = !rack && gpr_clk;
        // sys_top registers
        bool n_rack = rack, n_ack = io_ack;
        if (!wait || strobe) { n_rack = gpr_clk; n_ack = rack; }
        // hps_io registers
        bool n_ioctl_wr = wr, n_wr = false;
        if (strobe && download) {
            if (!skip_add) addr += 2;
            skip_add = false;
            dout = gpr_d; n_wr = true;
        }
        gpr_clk = gpd_clk; gpr_d = gpd_d; gpd_clk = gp_out_clk; gpd_d = gp_out_d;
        rack = n_rack; io_ack = n_ack; ioctl_wr = n_ioctl_wr; wr = n_wr;
        // HPS program
        if (done) return;
        if (cnt > 0) { cnt--; return; }
        switch (st) {
        case 0:   // between files
            if (now < t_next) return;
            if (++file >= (int)files.size()) { done = true; fprintf(log, "%.3f us downloads done\n", now / 1e6); fflush(log); return; }
            index = files[file].index; cnt = 4; st = 1;
            fprintf(log, "%.3f us download index %d, %zu bytes: %s\n", now / 1e6, index, files[file].data.size(), files[file].desc.c_str()); fflush(log);
            return;
        case 1:   // FIO_FILE_TX start
            download = true; addr = 0; skip_add = true; word = 0; cnt = 4; st = 2; return;
        case 2: { // word: io_clk high with the data
            auto& d = files[file].data;
            if (word * 2 >= d.size()) { st = 5; cnt = 4; return; }
            gp_out_d = d[word * 2] | d[word * 2 + 1] << 8; gp_out_clk = 1; cnt = hps_w; st = 3; return; }
        case 3:   // poll io_ack high
            if (io_ack) { gp_out_clk = 0; cnt = hps_w; st = 4; } else cnt = hps_r;
            return;
        case 4:   // poll io_ack low
            if (!io_ack) { word++; st = 2; } else cnt = hps_r;
            return;
        case 5:   // FIO_FILE_TX end
            if (download) addr += 2;
            download = false; st = 0; t_next = now + gap_ps;
            fprintf(log, "%.3f us download index %d end, %zu words\n", now / 1e6, index, word); fflush(log);
            return;
        }
    }
} hps;
#endif

#if FS_HAS_DL
// After the downloads: memory contents against the sources. Index 0 (BIOS)
// at SDRAM 0x800000, index 3 (flash images) at SDRAM 0x1000000, index 5
// (card) at DDR3 0x4000000; prints the first and the number of differing
// bytes per area.
static void check_downloads(std::vector<DlFile>& files, FILE* log) {
    for (auto& f : files) {
        const uint8_t* mem = nullptr; uint32_t base = 0; const char* where = "";
        if (f.index == 0) { mem = (const uint8_t*)sdram; base = 0x800000; where = "SDRAM"; }
        else if (f.index == 3) { mem = (const uint8_t*)sdram; base = 0x1000000; where = "SDRAM"; }
        else if (f.index == 5) { mem = (const uint8_t*)ddr; base = 0x4000000; where = "DDR3"; }
        else continue;
        size_t n = f.data.size(), bad = 0, first = (size_t)-1;
        for (size_t i = 0; i < n; i++) if (mem[base + i] != f.data[i]) { if (first == (size_t)-1) first = i; bad++; }
        if (bad) fprintf(log, "CHECK index %d (%s 0x%X, %zu bytes): %zu bytes differ, first at offset 0x%zX (memory %02X, file %02X)\n",
                         f.index, where, base, n, bad, first, mem[base + first], f.data[first]);
        else fprintf(log, "CHECK index %d (%s 0x%X, %zu bytes): identical\n", f.index, where, base, n);
    }
    fflush(log);
}
#endif

static void load(const char* fn, uint32_t byte_addr, uint32_t max) {
    FILE* f = fopen(fn, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", fn); exit(1); }
    std::vector<uint8_t> b(max);
    size_t n = fread(b.data(), 1, max, f); fclose(f);
    for (size_t i = 0; i < n; i += 2) sdram[(byte_addr + i) / 2] = b[i] | (i + 1 < n ? b[i + 1] << 8 : 0xff00);
    fprintf(stderr, "loaded %s at 0x%x, %zu bytes\n", fn, byte_addr, n);
}

int main(int argc, char** argv) {
    const char* bios = nullptr; const char* u30 = nullptr; std::string out = ".";
    const char* flashf = nullptr;
    long ddrlog_max = 0;
    double trace_from = 1e300, trace_to = -1;   // -trace_from/-trace_to us: probes at every clk2x rise             // -ddrlog N: first N DDR3 requests to ddr.log
    // -iolog_from/-iolog_to us: CPU data accesses to 0x1F801000-0x1F802FFF
    // (I/O registers) to io.log: "<us> R|W <addr> <mask> <wdata> PC <pc> -> <rdata>",
    // sampled at mem_request and mem_done. A debugging aid only: back-to-back
    // requests before a done keep the last one, so the direction and data of a
    // line can belong to a neighbouring access; the rdata of W lines is stale.
    double iolog_from = 1e300, iolog_to = -1; FILE* fio = nullptr; bool iopend = false; char ioline[160];
    double ps1_phase_ps = 0;
    bool iolog_all = false;            // -iolog_all 1: io.log takes every CPU data access, not only I/O
    // -pctrace_from/-pctrace_to us: every new CPU PC to pc.log (CPU clock domain);
    // -ramdump_us T: the first 64 KB of main RAM to ram_<T>.bin at T
    double pctrace_from = 1e300, pctrace_to = -1, ramdump_ps = -1; FILE* fpc = nullptr; uint32_t lastpc = 0;
    bool wd_apply = false;             // -wd_apply 1: an MB3773 pulse resets the core (PSX.sv zn_wd_hold)
    double wd_release_ps = -1; bool wd1 = false; int nwd = 0;
    bool zn_on_cpu = false;            // ZN-2 board on clk_cpu (CPU_CLK_SPLIT = 1 trees with ZN2_BOARD)
    bool cpu_on_cpu = false;           // CPU group on clk_cpu (-cpu_mhz > 0)
    double cpu_mhz = 0;                // general scheduler only: CPU group clock   // whole 10 MB flash area (warm MRA index 3, make_game_zip --warm)
    const char* keys = nullptr; const char* meta = nullptr; const char* card = nullptr;
    double run_ms = 100, vram_ms = 0; int ppm_every = 1;
    // timing of the bench: base half step (clk1x = 12 steps), clkvid half
    // period, loader start and reset release (defaults: exact clocks; the
    // zn2 NVC bench uses -h_ps 2461 -vid_half_ps 9312 -reset_us 10 after
    // the loader, see docs/fullsys_sim.md)
    double ckpt_ms = 0; const char* restore = nullptr;
    const char* dl_list = nullptr; double pre_ms = 500; int garbage = 1;
    double h_ps = 1e12 / 33868800.0 / 12.0, vid_half_ps = 1e12 / 53693175.0 / 2.0, reset_after_ld_us = -1;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "-bios") bios = argv[++i];
        else if (a == "-u30") u30 = argv[++i];
        else if (a == "-flash") flashf = argv[++i];
        else if (a == "-keys") keys = argv[++i];
        else if (a == "-meta") meta = argv[++i];
        else if (a == "-card") card = argv[++i];
        else if (a == "-ms") run_ms = atof(argv[++i]);
        else if (a == "-out") out = argv[++i];
        else if (a == "-ppm") ppm_every = atoi(argv[++i]);
        else if (a == "-vram_ms") vram_ms = atof(argv[++i]);
        else if (a == "-h_ps") h_ps = atof(argv[++i]);
        else if (a == "-vid_half_ps") vid_half_ps = atof(argv[++i]);
        else if (a == "-reset_us") reset_after_ld_us = atof(argv[++i]);
        else if (a == "-ckpt_ms") ckpt_ms = atof(argv[++i]);
        else if (a == "-dqm") chip.dqm_on = atoi(argv[++i]) != 0;
        else if (a == "-cpu_mhz") cpu_mhz = atof(argv[++i]);
        else if (a == "-wd_apply") wd_apply = atoi(argv[++i]) != 0;
        else if (a == "-ps1_phase_ns") ps1_phase_ps = atof(argv[++i]) * 1e3;
        else if (a == "-pctrace_from") pctrace_from = atof(argv[++i]) * 1e6;
        else if (a == "-pctrace_to") pctrace_to = atof(argv[++i]) * 1e6;
        else if (a == "-ramdump_us") ramdump_ps = atof(argv[++i]) * 1e6;
        else if (a == "-iolog_all") iolog_all = atoi(argv[++i]) != 0;
        else if (a == "-ddr_lat") DDR_LAT = atoi(argv[++i]);
        else if (a == "-ddr_hold") DDR_HOLD = atoi(argv[++i]);
        else if (a == "-ddr_jit") DDR_JIT = atoi(argv[++i]);
        else if (a == "-ddr_gap") DDR_GAP = atoi(argv[++i]);
        else if (a == "-ddr_busy") DDR_BUSYP = atoi(argv[++i]);
        else if (a == "-ddr_seed") ddr_rng = strtoull(argv[++i], nullptr, 0) | 1;
        else if (a == "-ddrlog") ddrlog_max = atol(argv[++i]);
        else if (a == "-trace_from") trace_from = atof(argv[++i]) * 1e6;
        else if (a == "-iolog_from") iolog_from = atof(argv[++i]) * 1e6;
        else if (a == "-iolog_to") iolog_to = atof(argv[++i]) * 1e6;
        else if (a == "-trace_to") trace_to = atof(argv[++i]) * 1e6;
        else if (a == "-dqm_float") chip.dqm_float = strtoul(argv[++i], nullptr, 16);
#if FS_HAS_DL
        else if (a == "-dl") dl_list = argv[++i];
        else if (a == "-hps_w") hps.hps_w = atoi(argv[++i]);
        else if (a == "-hps_r") hps.hps_r = atoi(argv[++i]);
        else if (a == "-dl_gap_ms") hps.gap_ps = atof(argv[++i]) * 1e9;
        else if (a == "-pre_ms") pre_ms = atof(argv[++i]);
        else if (a == "-garbage") garbage = atoi(argv[++i]);
#endif
        else if (a == "-restore") restore = argv[++i];
        else if (a[0] == '+') {}
        else { fprintf(stderr, "unknown argument %s\n", a.c_str()); return 1; }
    }
#if FS_HAS_DL
    if (!dl_list) { fprintf(stderr, "this build needs -dl <list> (MiSTer download order)\n"); return 1; }
    if (!bios) bios = "";
#endif
    if (!bios) { fprintf(stderr, "usage: %s -bios bios.bin [-u30 u30.bin] [-ms N] [-out DIR] [-ppm K] [-vram_ms N]\n", argv[0]); return 1; }
    mkdir(out.c_str(), 0755); mkdir((out + "/frames").c_str(), 0755);
    video.dir = out; video.every = ppm_every;

    sdram = (uint16_t*)calloc(1 << 24, 2);
    ddr = (uint64_t*)calloc(1 << 25, 8);
#if FS_HAS_DL
    // power-up memory contents: what the previous core left, here a fixed
    // pseudo-random pattern (-garbage 0: zeros); nothing is preloaded
    std::vector<DlFile> dlf = read_dl_list(dl_list);
    if (garbage) {
        uint64_t x = 0x9E3779B97F4A7C15ULL;
        for (uint32_t i = 0; i < (1u << 24); i++) { x ^= x << 13; x ^= x >> 7; x ^= x << 17; sdram[i] = (uint16_t)x; }
        for (uint32_t i = 0; i < (1u << 25); i++) { x ^= x << 13; x ^= x >> 7; x ^= x << 17; ddr[i] = x; }
    }
    hps.t_next = pre_ms * 1e9;
#else
    for (uint32_t i = 0x1000000 / 2; i < 0x1a00000 / 2; i++) sdram[i] = 0xffff;   // erased flash chips
    load(bios, 0x800000, 0x80000);
    if (u30) load(u30, 0x1000000, 0x200000);
    if (flashf) load(flashf, 0x1000000, 0xA00000);
#if FS_HAS_DDR3ARB
    // gnet_ddr3_mirror would have copied the flash area into DDR3 (byte
    // 0x30000000 + SDRAM address) while the MRA downloaded it; the model
    // window holds DDR3 byte 0x30000000 at 0, so the flash goes to 0x1000000
    if (flashf) {
        FILE* f = fopen(flashf, "rb"); std::vector<uint8_t> b(0xA00000);
        size_t n = f ? fread(b.data(), 1, b.size(), f) : 0; if (f) fclose(f);
        for (size_t i = 0; i + 8 <= n; i += 8) { uint64_t v; memcpy(&v, &b[i], 8); ddr[(0x1000000 + i) >> 3] = v; }
        fprintf(stderr, "flash mirror at DDR3 0x31000000 (model 0x1000000), %zu bytes\n", n);
    }
    if (DDR_HOLD < 0) DDR_HOLD = 1;
#endif
    if (DDR_HOLD < 0) DDR_HOLD = 0;
#endif
    // ZN-2 loader stream: keys (target 0, 16 bytes), card metadata (target 1,
    // 1024 bytes), as words: lo byte then hi byte (sim/zn2/system tb)
    struct LdWord { int target; int addr; int data; };
    std::vector<LdWord> ld;
    if (keys) { auto k = read_hex(keys); for (size_t i = 0; i + 1 < k.size() && i < 16; i += 2) ld.push_back({0, (int)i, k[i] | k[i + 1] << 8}); }
    if (meta) { auto m = read_hex(meta); for (size_t i = 0; i + 1 < m.size() && i < 1024; i += 2) ld.push_back({1, (int)i, m[i] | m[i + 1] << 8}); }
    if (card) {
        FILE* f = fopen(card, "rb"); if (!f) { fprintf(stderr, "cannot open %s\n", card); return 1; }
        size_t n = fread((uint8_t*)ddr + 0x4000000, 1, 40960000, f); fclose(f);
        fprintf(stderr, "card image at DDR3 0x4000000, %zu bytes\n", n);
    }
    size_t ld_i = 0; int ld_phase = 0;

    VerilatedContext* ctx = new VerilatedContext;
    ctx->commandArgs(argc, argv);
    top = new Vfs_top{ctx};
    fs_set_defaults(top);
    top->clk1x = top->clk2x = top->clk3x = 1; top->clkvid = 0;
#if FS_HAS_DL
    top->RESET = 1; top->sdram_init = 1;
    top->ioctl_download = 0; top->ioctl_wr = 0; top->ioctl_index = 0; top->ioctl_addr = 0; top->ioctl_dout = 0;
#else
    top->reset = 1; top->sdram_init = 1;
#endif
    top->ddr3_BUSY = 0; top->ddr3_DOUT_READY = 0; top->ddr3_DOUT = 0;
#if !FS_HAS_ZN2
    top->ch3_req = 0;
#endif
    top->eval();

    const char* lmode = restore ? "a" : "w";
    FILE* fprog = nullptr; FILE* fgpu = nullptr;
    FILE* fddr = nullptr; long nddrlog = 0;
#if FS_HAS_ZN2
    // every ZN-2 expansion bus access (zn_* in psx_top), as the zn2 bench's zn.log:
    // "<us> <we> 1F<addr> <be> <wdata> -> <rdata>"
    FILE* fzn = nullptr;
    bool zpend = false; char zline[128]; uint64_t nzn = 0;
#endif
    const double H = h_ps;
    const double PV = 2 * vid_half_ps;
    double ld_done_ps = -1;
    double t_vid_rise = PV / 2, t_vid_fall = PV;   // clkvid starts low
    double t_reset = -1;                      // reset release time, set when the loader is done
    uint64_t k = 0;                           // base step index (H)
    uint64_t ngpu = 0, nevals = 0; bool gpurd_pend = false;
    bool dl_checked = false; double dl_check_ps = 0;
    double next_prog = 100e6, next_vram = vram_ms > 0 ? vram_ms * 1e9 : 1e300;
    bool vram_pending = false; int vs1 = 0;
    const double end_ps = run_ms * 1e9;
    auto wall0 = std::chrono::steady_clock::now();
    bool reset_done = false;
    double next_ckpt = ckpt_ms > 0 ? ckpt_ms * 1e9 : 1e300;
    std::vector<std::string> ckpts;

    // every piece of harness state, in one order for save and restore
    auto state_io = [&](FILE* f, bool save) {
        auto io = [&](void* q, size_t n) {
            if (save) fwrite(q, 1, n, f);
            else if (fread(q, 1, n, f) != n) { fprintf(stderr, "checkpoint truncated\n"); exit(1); }
        };
#define IO(x) io(&(x), sizeof(x))
        IO(now_ps); IO(k); IO(t_vid_rise); IO(t_vid_fall); IO(t_reset); IO(ld_done_ps); IO(ngpu); IO(nevals);
        IO(gpurd_pend); IO(next_prog); IO(next_vram); IO(vram_pending); IO(vs1); IO(reset_done); IO(ld_i);
        IO(ld_phase); IO(next_ckpt);
#if FS_HAS_ZN2
        IO(zpend); IO(zline); IO(nzn);
#endif
        IO(chip); IO(ddr3);
        IO(video.frames); IO(video.lines); IO(video.width); IO(video.hb1); IO(video.vb1);
        for (std::vector<uint8_t>* v : {&video.line, &video.img}) {
            uint64_t n = v->size(); IO(n); if (!save) v->resize(n); io(v->data(), n);
        }
        io(sdram, (size_t)2 << 24);
        io(ddr, (size_t)8 << 25);
#undef IO
    };
    const char* lognames[3] = {"progress.log", "gpu.log", "zn.log"};
    auto checkpoint = [&]() {
        FILE* logs[3] = {fprog, fgpu, nullptr};
#if FS_HAS_ZN2
        logs[2] = fzn;
#endif
        long len[3] = {0, 0, 0};
        for (int i = 0; i < 3; i++) if (logs[i]) { fflush(logs[i]); len[i] = ftell(logs[i]); }
        char base[600]; snprintf(base, sizeof base, "%s/ckpt_%.0f", out.c_str(), now_ps / 1e9);
        std::string hn = std::string(base) + ".harness", mn = std::string(base) + ".model";
        FILE* f = fopen((hn + ".tmp").c_str(), "wb");
        if (!f) { fprintf(stderr, "cannot write %s\n", hn.c_str()); return; }
        double wall = std::chrono::duration<double>(std::chrono::steady_clock::now() - wall0).count();
        uint32_t magic = 0x46534b31;   // "FSK1"
        fwrite(&magic, 4, 1, f); fwrite(&wall, sizeof wall, 1, f); fwrite(len, sizeof len, 1, f);
        state_io(f, true);
        fclose(f);
#ifdef FS_SAVABLE
        { VerilatedSave os; os.open((mn + ".tmp").c_str()); os << *top; os.close(); }
        rename((mn + ".tmp").c_str(), mn.c_str());
#endif
        rename((hn + ".tmp").c_str(), hn.c_str());
        fprintf(fprog, "%.0f us checkpoint %s\n", now_ps / 1e6, base); fflush(fprog);
        ckpts.push_back(base);
        while (ckpts.size() > 2) {
            unlink((ckpts.front() + ".harness").c_str()); unlink((ckpts.front() + ".model").c_str());
            ckpts.erase(ckpts.begin());
        }
    };
    if (restore) {
        std::string hn = std::string(restore) + ".harness";
        FILE* f = fopen(hn.c_str(), "rb");
        if (!f) { fprintf(stderr, "cannot open %s\n", hn.c_str()); return 1; }
        uint32_t magic = 0; double wall = 0; long len[3];
        if (fread(&magic, 4, 1, f) != 1 || magic != 0x46534b31) { fprintf(stderr, "%s is not a checkpoint\n", hn.c_str()); return 1; }
        if (fread(&wall, sizeof wall, 1, f) != 1 || fread(len, sizeof len, 1, f) != 1) { fprintf(stderr, "checkpoint truncated\n"); return 1; }
        state_io(f, false);
        fclose(f);
#ifdef FS_SAVABLE
        { VerilatedRestore os; os.open((std::string(restore) + ".model").c_str()); os >> *top; os.close(); }
#else
        fprintf(stderr, "this build cannot restore a model (rebuild with VFLAGS=--savable)\n"); return 1;
#endif
        for (int i = 0; i < 3; i++) truncate((out + "/" + lognames[i]).c_str(), len[i]);
        wall0 -= std::chrono::duration_cast<std::chrono::steady_clock::duration>(std::chrono::duration<double>(wall));
        fprintf(stderr, "restored %s at %.1f ms\n", restore, now_ps / 1e9);
        // the checkpoint schedule follows this run's -ckpt_ms, not the
        // restored one (with -ckpt_ms 0 a restored next_ckpt would fire on
        // every pass)
        next_ckpt = ckpt_ms > 0 ? (std::floor(now_ps / (ckpt_ms * 1e9)) + 1) * ckpt_ms * 1e9 : 1e300;
    }
    fprog = fopen((out + "/progress.log").c_str(), lmode);
    fgpu = fopen((out + "/gpu.log").c_str(), lmode);
    if (ddrlog_max > 0) fddr = fopen((out + "/ddr.log").c_str(), lmode);
#if FS_HAS_ZN2
    fzn = fopen((out + "/zn.log").c_str(), lmode);
#endif
    if (restore) fprintf(fprog, "%.0f us restored from %s\n", now_ps / 1e6, restore);

    // DUT outputs before an edge, for the memory models and the HPS model
    struct Pre { bool d_rd, d_we; uint32_t d_addr; int d_bc; uint64_t d_din; uint8_t d_be;
                 uint8_t s_ncs, s_nras, s_ncas, s_nwe, s_ba; uint16_t s_a, s_dq; bool io_wait; };
    auto sample = [&]() {
        Pre pp; pp.d_rd = top->ddr3_RD; pp.d_we = top->ddr3_WE; pp.d_addr = top->ddr3_ADDR; pp.d_bc = top->ddr3_BURSTCNT;
        pp.d_din = top->ddr3_DIN; pp.d_be = top->ddr3_BE; pp.s_ncs = top->sd_ncs; pp.s_nras = top->sd_nras;
        pp.s_ncas = top->sd_ncas; pp.s_nwe = top->sd_nwe; pp.s_ba = top->sd_ba; pp.s_a = top->sd_a; pp.s_dq = top->sd_dq_w;
#if FS_HAS_DL
        pp.io_wait = top->ioctl_wait;
#else
        pp.io_wait = false;
#endif
        return pp; };
    // level inputs that change at a time, not on an edge: applied before
    // the first clock edge at or after that time (as a VHDL "wait for")
    auto levels = [&](double tb) {
        if (tb >= 2e6) top->sdram_init = 0;
#if FS_HAS_DL
        if (!reset_done && tb >= 2e6) { top->RESET = 0; reset_done = true; fprintf(fprog, "%.3f us RESET released (framework)\n", now_ps / 1e6); }
#else
        if (!reset_done && t_reset >= 0 && tb >= t_reset) {
            top->reset = 0; reset_done = true; fprintf(fprog, "%.3f us reset released\n", now_ps / 1e6);
        }
#endif
    };
    auto on_sdram_fall = [&](const Pre& pp) {
        chip.edge(pp.s_ncs, pp.s_nras, pp.s_ncas, pp.s_nwe, pp.s_ba, pp.s_a, pp.s_dq); top->sd_dq_r = chip.dq_r; };
#if FS_HAS_ZOOM
    // zoom.log: MN10200-side mailbox writes and dbg_flags changes (clk2x, the
    // Zoom's clock): "<us> MBW <addr> <data>", "<us> FLAGS <hex>"
    FILE* fzoom = fopen((out + "/zoom.log").c_str(), "w"); uint8_t zflags1 = 0;
    // zoom_audio.raw: zoom_out's out_l, out_r as int16 LE stereo, one frame
    // per output tick (32,552.083 Hz, 25 MHz / 768, on clk1x)
    FILE* faud = fopen((out + "/zoom_audio.raw").c_str(), "wb"); uint64_t naud = 0;
    // zoom_so1.raw: the TMS57002 SO1 pair before the gain (zoom_out in_l/in_r,
    // SO1 >> 8 as int16 LE stereo), one frame per push (the DSP's sample sync),
    // the same form as the MAME capture for cmp_mame_audio.py
    FILE* fso1 = fopen((out + "/zoom_so1.raw").c_str(), "wb");
#endif
    auto on_clk2x_rise = [&](const Pre& pp) {
#if FS_HAS_ZOOM
        if (top->dbg_zmbwe) fprintf(fzoom, "%.3f MBW %02X %04X\n", now_ps / 1e6, top->dbg_zmba, top->dbg_zmbwd);
        if (top->dbg_zmflags != zflags1) { zflags1 = top->dbg_zmflags; fprintf(fzoom, "%.3f FLAGS %02X\n", now_ps / 1e6, zflags1); fflush(fzoom); }
#endif
        if (now_ps >= trace_from && now_ps <= trace_to) {
            fprintf(fprog, "T %.4f c1 %d", now_ps / 1e6, top->clk1x); fs_print_probes(fprog, top); fprintf(fprog, "\n");
        }
            if (pp.d_rd && ddr3.state == 0 && ddr3.nrd < 8) fprintf(fprog, "%.3f us ddr3 rd addr %07X bc %d\n", now_ps / 1e6, pp.d_addr, pp.d_bc);
            if (fddr && ddr3.state == 0 && (pp.d_rd || pp.d_we) && nddrlog < ddrlog_max) {
                fprintf(fddr, "%.3f %s %07X %d %016llX %02X\n", now_ps / 1e6, pp.d_rd ? "R" : "W", pp.d_addr, pp.d_bc,
                        (unsigned long long)pp.d_din, pp.d_be);
                nddrlog++;
            }
            ddr3.edge(pp.d_rd, pp.d_we, pp.d_addr, pp.d_bc, pp.d_din, pp.d_be);
            top->ddr3_DOUT = ddr3.dout; top->ddr3_DOUT_READY = ddr3.ready; top->ddr3_BUSY = ddr3.busy;
    };
    // ZN-2 bus log and MB3773 requests, in the board's clock domain: clk1x,
    // or clk_cpu when the board sits in the CPU group (zn_on_cpu)
    auto zn_hooks = [&]() {
#if FS_HAS_ZN2
#if !FS_HAS_DL
        // watchdog reset requests after the core left reset (the output is
        // high at power-up while the board is still in reset)
        bool wd = top->zn_wd_reset;
        if (reset_done && wd && !wd1 && wd_release_ps < 0) {
            nwd++;
            fprintf(fprog, "%.0f us WATCHDOG RESET%s\n", now_ps / 1e6, wd_apply ? " (applied)" : "");
            if (wd_apply) { top->reset = 1; wd_release_ps = now_ps + 255 * 1e12 / 33868800.0; }
        }
        wd1 = wd;
#endif
        if (top->dbg_znreq) {
            zpend = true;
            snprintf(zline, sizeof zline, "%.3f %d 1F%06X %X %08X", now_ps / 1e6, top->dbg_znwe, top->dbg_znaddr, top->dbg_znbe, top->dbg_znwdata);
        }
        if (top->dbg_znack && zpend) { zpend = false; fprintf(fzn, "%s -> %08X\n", zline, top->dbg_znrdata); nzn++; }
#endif
    };
    // CPU I/O log, in the CPU's clock domain (clk1x, or clk_cpu when split)
    auto io_hooks = [&]() {
        if (now_ps >= pctrace_from && now_ps <= pctrace_to) {
            if (!fpc) fpc = fopen((out + "/pc.log").c_str(), "w");
            if (top->dbg_pc != lastpc) { lastpc = top->dbg_pc; fprintf(fpc, "%.4f %08X\n", now_ps / 1e6, lastpc); }
        }
        if (ramdump_ps >= 0 && now_ps >= ramdump_ps) {
            char fn[512]; snprintf(fn, sizeof fn, "%s/ram_%.0f.bin", out.c_str(), ramdump_ps / 1e6);
            FILE* f = fopen(fn, "wb"); if (f) { fwrite(&sdram[0], 2, 0x8000, f); fclose(f); }
            ramdump_ps = -1;
        }
        if (now_ps >= iolog_from && now_ps <= iolog_to) {
            if (!fio) fio = fopen((out + "/io.log").c_str(), "w");
            uint32_t a = top->dbg_cpuaddr & 0x1fffffff;
            if (top->dbg_cpureq && (iolog_all || (a >= 0x1f801000 && a < 0x1f803000))) {
                iopend = true;
                snprintf(ioline, sizeof ioline, "%.3f %s %08X %X %08X PC %08X", now_ps / 1e6, top->dbg_cpurnw ? "R" : "W", a,
                         top->dbg_cpumask, top->dbg_cpuwdata, top->dbg_pc);
            }
            if (top->dbg_cpudone && iopend) { iopend = false; fprintf(fio, "%s -> %08X\n", ioline, top->dbg_cpurdata); }
        }
    };
    auto on_clk1x_rise = [&](const Pre& pp) {
#if FS_HAS_ZOOM
        if (top->dbg_zmtick) { int16_t lr[2] = {(int16_t)top->dbg_zmoutl, (int16_t)top->dbg_zmoutr}; fwrite(lr, 2, 2, faud); if ((++naud & 4095) == 0) { fflush(faud); fflush(fso1); } }
        if (top->dbg_zmpush) { int16_t lr[2] = {(int16_t)top->dbg_zmso1l, (int16_t)top->dbg_zmso1r}; fwrite(lr, 2, 2, fso1); }
#endif
        if (!cpu_on_cpu) io_hooks();
#if FS_HAS_DL
            hps.edge(pp.io_wait, now_ps, dlf, fprog);
            top->ioctl_download = hps.download; top->ioctl_index = hps.index; top->ioctl_addr = hps.addr;
            top->ioctl_dout = hps.dout; top->ioctl_wr = hps.ioctl_wr;
            if (hps.done && !dl_checked && now_ps > dl_check_ps) {
                if (dl_check_ps == 0) dl_check_ps = now_ps + 50e6;   // let the last writes land
                else { check_downloads(dlf, fprog); dl_checked = true; }
            }
            static bool rs1 = false;
            if (top->dbg_reset != rs1) { fprintf(fprog, "%.3f us psx reset %d\n", now_ps / 1e6, top->dbg_reset); rs1 = top->dbg_reset; }
#endif
            if (!reset_done && t_reset < 0) {
#if FS_HAS_ZN2 && !FS_HAS_DL
                // after the SDRAM init: one loader word every 3 clk1x, then the card flags
                if (now_ps > 102e6 && ld_i < ld.size()) {
                    if (ld_phase == 0) { top->zn_ld_wr = 1; top->zn_ld_target = ld[ld_i].target; top->zn_ld_addr = ld[ld_i].addr; top->zn_ld_data = ld[ld_i].data; }
                    else if (ld_phase == 1) top->zn_ld_wr = 0;
                    if (++ld_phase == 3) { ld_phase = 0; ld_i++; }
                }
                if (now_ps > 102e6 && meta && ld_i >= ld.size()) { top->zn_card_present = 1; top->zn_key_valid = 1; }
#endif
                if (now_ps > 102e6 && ld_i >= ld.size()) {
                    ld_done_ps = now_ps;
                    t_reset = reset_after_ld_us < 0 ? (ld_done_ps > 130e6 ? ld_done_ps : 130e6) : ld_done_ps + reset_after_ld_us * 1e6;
                }
            }
#if FS_HAS_ZN2 && !FS_HAS_DL
            if (wd_release_ps >= 0 && now_ps >= wd_release_ps) {
                wd_release_ps = -1; top->reset = 0;
                fprintf(fprog, "%.3f us reset released (after watchdog)\n", now_ps / 1e6);
            }
#endif
            if (!zn_on_cpu) zn_hooks();
            if (top->dbg_gpu_write) {
                fprintf(fgpu, "%lld GP%d %08X\n", (long long)(now_ps / 1e6), (top->dbg_gpu_addr >> 2) & 1, top->dbg_gpu_data);
                ngpu++;
            }
            // CPU reads of GPUREAD: "<us> GR0 <hex>" (the data register is valid
            // one clk1x after the read; a stalled VRAM read may take longer)
            if (gpurd_pend) { fprintf(fgpu, "%lld GR0 %08X\n", (long long)(now_ps / 1e6), top->dbg_gpurdata); gpurd_pend = false; }
            if (top->dbg_gpurd && ((top->dbg_gpuaddr >> 2) & 3) == 0) gpurd_pend = true;
            if (top->dbg_dmagpu_we) { fprintf(fgpu, "%lld GPD %08X\n", (long long)(now_ps / 1e6), top->dbg_dmagpu_d); ngpu++; }
            int vs = top->vsync;
            if (vs && !vs1 && vram_pending) {
                char fn[512]; snprintf(fn, sizeof fn, "%s/vram_%.0f.bin", out.c_str(), next_vram / 1e9 - vram_ms);
                FILE* f = fopen(fn, "wb"); if (f) { fwrite(ddr, 8, 1 << 18, f); fclose(f); }
                vram_pending = false;
            }
            vs1 = vs;
            if (now_ps >= next_vram) { vram_pending = true; next_vram += vram_ms * 1e9; }
            if (now_ps >= next_prog) {
                double wall = std::chrono::duration<double>(std::chrono::steady_clock::now() - wall0).count();
                fprintf(fprog, "%.0f us frame %ld PC %08X gpu %llu ddr3 rd %llu wr %llu evals %llu wall %.1f s",
                        now_ps / 1e6, video.frames, top->dbg_pc, (unsigned long long)ngpu,
                        (unsigned long long)ddr3.nrd, (unsigned long long)ddr3.nwr, (unsigned long long)nevals, wall);
                fs_print_probes(fprog, top); fprintf(fprog, "\n");
                fflush(fprog); fflush(fgpu);
#if FS_HAS_ZN2
                fflush(fzn);
#endif
                next_prog += 100e6;
            }
    };
#if FS_HAS_CPUCLK
    if (cpu_mhz == 0) top->clk_cpu = top->clk_cpu2x = top->clk_cpu3x = 1;
    if (cpu_mhz == 0)
#endif
    while (now_ps < end_ps) {
        // next base event: k mod 12 in {0, 2, 4, 6, 8, 10}
        k += 2;
        double tb = k * H;
        // clkvid rising edges before this base event get their own evaluation
        while (t_vid_rise < tb) {
            now_ps = t_vid_rise;
            top->clkvid = 1; top->eval(); nevals++;
            { video.t_ps = now_ps; video.sample(top->video_ce, top->hblank, top->vblank, top->video_r, top->video_g, top->video_b); }
            t_vid_rise += PV;
        }
        if (t_vid_fall <= tb && t_vid_fall < t_vid_rise) { top->clkvid = 0; t_vid_fall += PV; }
        now_ps = tb;
        levels(tb);
        int ph = k % 12;
        bool r1 = ph == 0, r2 = ph == 0 || ph == 6, r3 = ph == 0 || ph == 4 || ph == 8;
        bool f3 = ph == 2 || ph == 6 || ph == 10;
        Pre pp = sample();
        if (r1) top->clk1x = 1;
        if (ph == 6) top->clk1x = 0;
        if (r2) top->clk2x = 1;
        if (ph == 2 || ph == 10) top->clk2x = 0;
        if (r3) top->clk3x = 1;
        if (f3) top->clk3x = 0;
#if FS_HAS_CPUCLK
        top->clk_cpu = top->clk1x; top->clk_cpu2x = top->clk2x; top->clk_cpu3x = top->clk3x;
#endif
        top->eval(); nevals++;
        if (f3) on_sdram_fall(pp);
        if (r2) on_clk2x_rise(pp);
        if (r1) on_clk1x_rise(pp);
        if (now_ps >= next_ckpt) { next_ckpt += ckpt_ms * 1e9; checkpoint(); }
    }
#if FS_HAS_CPUCLK
    else {
    // General clock scheduler (psx_top with clk_cpu/clk_cpu2x/clk_cpu3x,
    // branch r1-cpu50): every edge of every clock is evaluated, coincident
    // edges together. -cpu_mhz F: clk_cpu at F MHz, clk_cpu2x = clk_cpu3x
    // at 2F (pll_cpu.v, ideal clocks); -cpu_mhz 0 ties them to clk1x, clk2x,
    // clk3x (CPU_CLK_SPLIT = 0). The SDRAM chip follows the controller clock
    // (clk_cpu2x with -cpu_mhz > 0, as PSX.sv GNET_CPU50).
    // edge times as (count + 1) x half period: summing half periods drifts
    // by tenths of a ps within milliseconds and splits coincident edges
    struct Clk { double half; uint64_t n; int v; double off; double next() const { return off + (n + 1) * half; } };
    const double P1 = 1e12 / 33868800.0;
    // -ps1_phase_ns D: the PS1 clocks (clk1x/2x/3x) start D ns after the CPU
    // clocks (sim/zn2/system SPLIT = 1 uses PHASE 7 ns)
    Clk ck[5] = {{P1 / 2, 0, 1, ps1_phase_ps}, {P1 / 4, 0, 1, ps1_phase_ps}, {P1 / 6, 0, 1, ps1_phase_ps}, {PV / 2, 0, 0, 0}, {1, 0, 1, 0}};
    enum { C1, C2, C3, CV, CC };
    const bool split = cpu_mhz > 0;
    zn_on_cpu = split && FS_HAS_ZN2;
    cpu_on_cpu = split;
    if (split) ck[CC].half = 1e6 / cpu_mhz / 4;   // clk_cpu2x half period
    int cc_div = 0;                     // clk_cpu toggles every second clk_cpu2x edge
    top->clk_cpu = top->clk_cpu2x = top->clk_cpu3x = 1;
    while (now_ps < end_ps) {
        double T = 1e300;
        for (int i = 0; i < 5; i++) if ((i != CC || split) && ck[i].next() < T) T = ck[i].next();
        now_ps = T;
        levels(T);
        Pre pp = sample();
        bool rose[5] = {false, false, false, false, false}, fell[5] = {false, false, false, false, false};
        for (int i = 0; i < 5; i++) {
            if (i == CC && !split) continue;
            if (ck[i].next() - T < 0.01) {
                ck[i].v ^= 1; ck[i].n++;
                (ck[i].v ? rose : fell)[i] = true;
            }
        }
        top->clk1x = ck[C1].v; top->clk2x = ck[C2].v; top->clk3x = ck[C3].v; top->clkvid = ck[CV].v;
        bool cc_rose = false, cc2_fell = false;
        if (split) {
            if (rose[CC] || fell[CC]) {
                top->clk_cpu2x = top->clk_cpu3x = ck[CC].v;
                if (fell[CC]) cc2_fell = true;
                if (rose[CC]) { if (++cc_div == 2) cc_div = 0; top->clk_cpu = cc_div == 0 ? 1 : 0; cc_rose = cc_div == 0; }
            }
        } else {
            top->clk_cpu = top->clk1x; top->clk_cpu2x = top->clk2x; top->clk_cpu3x = top->clk3x;
        }
        top->eval(); nevals++;
        if (cc_rose && zn_on_cpu) zn_hooks();
        if (cc_rose && cpu_on_cpu) io_hooks();
        if (split ? cc2_fell : fell[C3]) on_sdram_fall(pp);
        if (rose[C2]) on_clk2x_rise(pp);
        if (rose[CV]) { video.t_ps = now_ps; video.sample(top->video_ce, top->hblank, top->vblank, top->video_r, top->video_g, top->video_b); }
        if (rose[C1]) on_clk1x_rise(pp);
        if (now_ps >= next_ckpt) { next_ckpt += ckpt_ms * 1e9; checkpoint(); }
    }
    }
#endif
    double wall = std::chrono::duration<double>(std::chrono::steady_clock::now() - wall0).count();
    fprintf(fprog, "done: %.1f ms emulated in %.1f s wall, %.3f ms/s, %ld frames, %.2f frames/min, %llu evals, %.2f us/eval\n",
            now_ps / 1e9, wall, now_ps / 1e9 / wall, video.frames, video.frames * 60.0 / wall,
            (unsigned long long)nevals, wall * 1e6 / nevals);
    if (chip.dqm_on) fprintf(fprog, "SDRAM reads with DQM-masked words: %llu\n", (unsigned long long)chip.nmasked);
    fclose(fprog); fclose(fgpu);
    fprintf(stderr, "done: %.1f ms emulated in %.1f s wall (%.3f ms/s), %ld frames, %llu GPU writes\n",
            now_ps / 1e9, wall, now_ps / 1e9 / wall, video.frames, (unsigned long long)ngpu);
    top->final();
    delete top;
    return 0;
}
