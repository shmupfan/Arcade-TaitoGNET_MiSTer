// Integration bench: main CPU to the Taito Zoom board through the G-NET
// core's path (sim/zoomlink/zl_vtop.vhd, docs/zoom_board_design.md 14).
//
//   tb_zoomlink <flashdir> <outdir> [run1_ms] [run2_ms]
//   tb_zoomlink <flashdir> <outdir> replay <hostlog> <t0_s> <t_end_s>
//
// flashdir: zoomprog and wave0..2 from tools/build_flash.py (game data,
// gitignored). outdir receives hev.log (every request that reaches
// zoom_board's host port and every change of its zoom_reset and reset, by
// clk_1x cycle; tb_zoomref replays it) and insn.bin (one 32-byte record per
// MN10200 instruction).
//
// Clocks (ps): clk_2x 14,764, clk_1x 29,528 (phase aligned, one PLL),
// clk_cpu 20,000 (50 MHz, offset 3,000 ps, unrelated). The main CPU is a
// memorymux-like bus master on clk_cpu (one request pulse, waits for the
// ack); SDRAM channel 3 is a model on clk_cpu (4 to 14 cycles, one access at
// a time, reads must carry byte enables 1111) holding the flash area at
// 0x1000000.
//
// Script:
//   1. resets (2 us), then 20 us
//   2. control register read: 0x10 (gnet_ctrl reset value, Zoom held)
//   3. mailbox self-test with the MN10200 held: 256 bytes written through
//      lanes 0 and 2 and read back
//   4. the games' release sequence: control 0xD8 (bit 4 set), the 256 bytes
//      cleared, control 0xD0 and 0xD8 (bit 3 clear and set), control 0xC8
//      (bit 4 clear: release)
//   5. run1_ms with no host traffic (default 30)
//   6. a command: mailbox bytes 0 to 7 written, doorbell (0x1FBA0000), then
//      the first 32 bytes polled every 200 us until run2_ms more (default 20)
// Checks: control read, self-test reads, the order of zoom_reset against the
// clearing writes and the release write, every host request arriving once
// with its fields, every MN10200 and host mailbox read against a shadow of
// both ports' writes, the doorbell reaching IRQ0, the SDRAM read byte
// enables, the board's flags.
//
// Replay (tools/zoom/zoom_hostlog.sh output): after the resets, every
// main-CPU access to the Zoom ports (H) and control write (C) of MAME's run
// from t0_s to t_end_s is issued at its MAME time relative to t0_s (later
// only if the bus is still busy), split into 16-bit bus steps as memorymux
// makes them. Compared with MAME: the data of every host read, and the
// MN10200's mailbox accesses (M lines after t0_s) in order: read or write,
// address, lanes and data. Steps 1 to 6 of the script are not run.
#include "Vzl_vtop.h"
#include "Vzl_vtop___024root.h"
#include "verilated.h"
#include <deque>

static Vzl_vtop *top;
static Vzl_vtop___024root *R;
#define ZB(x) R->zl_vtop__DOT__izoom_board__DOT__##x
#include "zl_common.h"

static const uint64_t H2 = 7382, H1 = 14764, HC = 10000, OFFC = 3000;
static uint64_t now = 0, c1 = 0, c2 = 0, cc = 0;
static FILE *hev, *ins, *sof;
static uint64_t so_n = 0, so_nz = 0;
static uint64_t errors = 0;
#define ERR(...) do { if (errors++ < 40) { fprintf(stderr, "ERROR at %.3f us: ", now / 1e6); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

// ------------------------------------------------------------------ SDRAM model (clk_cpu)
static uint64_t rnd_s = 88172645463325252ull;
static uint32_t rnd() { rnd_s ^= rnd_s << 13; rnd_s ^= rnd_s >> 7; rnd_s ^= rnd_s << 17; return (uint32_t)rnd_s; }
static int sd_left = -1;
static uint32_t sd_addr, sd_din; static bool sd_rnw; static unsigned sd_be;
static uint64_t sd_reads = 0, sd_zoom = 0, sd_bad_be = 0;
static void sdram_post() {
    top->ch3_ready = 0;
    if (top->ch3_req) {
        if (sd_left >= 0) ERR("ch3 request while one is open");
        sd_addr = top->ch3_addr; sd_rnw = top->ch3_rnw; sd_be = top->ch3_be; sd_din = top->ch3_din;
        sd_left = 4 + rnd() % 11;
    } else if (sd_left > 0) {
        if (top->ch3_addr != sd_addr || top->ch3_rnw != sd_rnw || top->ch3_be != sd_be) ERR("ch3 fields changed before ready");
        sd_left--;
    } else if (sd_left == 0) {
        uint32_t a = sd_addr & ~3u, v = 0;
        if (sd_rnw) {
            sd_reads++;
            if (a >= 0x1200000 && a < 0x1a00000) sd_zoom++;
            if (sd_be != 0xf) { sd_bad_be++; ERR("ch3 read %07x with byte enables %x (read DQM)", a, sd_be); }
            if (a >= 0x1000000 && a < 0x2000000)
                for (int i = 3; i >= 0; i--) v = v << 8 | fa[a - 0x1000000 + i];
            top->ch3_dout = v;
        } else ERR("ch3 write %07x in a bench with no flash programming", a);
        top->ch3_ready = 1;
        sd_left = -1;
    }
}

// ------------------------------------------------------------------ host (main CPU) script
struct Op { bool we; uint32_t addr; unsigned be; uint32_t d; int chk; uint64_t wait_ps; const char *mark; uint64_t at = 0; uint32_t exp = 0; };
enum { C_NONE, C_CTRL10, C_SELF, C_SHADOW, C_MAME };
static uint64_t mame_rd = 0, mame_rd_bad = 0;
static std::deque<Op> ops;
static int bus_state = 0;               // 0 idle, 1 waiting for the ack
static Op cur;
static uint64_t bus_wait_until = 0, host_ops = 0, host_lat_max = 0, host_lat_sum = 0, req_c = 0;
static Shadow sh;
static uint8_t self_pat[256];
static std::deque<Op> sent;             // requests that must reach zoom_board, in order
static uint64_t t_release_wr = 0, t_release_seen = 0, t_doorbell = 0, t_irq0 = 0, clear_done_at = 0;
static bool release_written = false, doorbell_written = false;
static uint64_t c_rst_until = 2000000, p_rst_c1 = 68;   // 2 us; p_rst for the first 68 clk_1x cycles

static bool zoom_addr(uint32_t a) {
    return (a >> 2) == (0xB80000 >> 2) || (a >> 2) == (0xBA0000 >> 2) || (a >> 2) == (0xBC0000 >> 2) || (a >> 9) == (0xBE0000 >> 9);
}

static void host_post() {
    top->zn_req = 0;
    if (now < c_rst_until) { top->c_rst = 1; return; }
    top->c_rst = 0;
    if (bus_state == 1) {
        if (top->zn_ack) {
            uint64_t lat = cc - req_c;
            host_lat_max = std::max(host_lat_max, lat); host_lat_sum += lat; host_ops++;
            uint32_t r = top->zn_rdata;
            if (!cur.we) {
                if (cur.chk == C_CTRL10 && (r & 0xff) != 0x10) ERR("control read %02x, expected 10", r & 0xff);
                if (cur.chk == C_SELF || cur.chk == C_SHADOW) {
                    unsigned w = (cur.addr >> 2) & 0x7f, lane = cur.be & 3 ? 0 : 1;
                    unsigned d = lane ? (r >> 16) & 0xff : r & 0xff;
                    if (cur.chk == C_SELF && d != self_pat[w * 2 + lane]) ERR("self-test byte %u: %02x, expected %02x", w * 2 + lane, d, self_pat[w * 2 + lane]);
                    if (cur.chk == C_SHADOW || cur.chk == C_MAME) {
                        sh.host_reads++;
                        int c = sh.check(w, 1u << lane, d << (8 * lane), now, 2000000);
                        if (c == 1) sh.host_race++;
                        if (c == 2) { sh.host_bad++; ERR("host mailbox read byte %u: %02x, shadow %02x", w * 2 + lane, d, sh.b[w * 2 + lane]); }
                    }
                }
            }
            if (cur.chk == C_MAME && !cur.we) {
                uint32_t m = 0;
                for (int l = 0; l < 4; l++) if (cur.be >> l & 1) m |= 0xffu << (8 * l);
                mame_rd++;
                if ((r & m) != (cur.exp & m)) { mame_rd_bad++; ERR("host read %06x be %x: %08x, MAME %08x", cur.addr, cur.be, r & m, cur.exp & m); }
            }
            if (cur.mark && !strcmp(cur.mark, "release")) { release_written = true; t_release_wr = now; }
            if (cur.mark && !strcmp(cur.mark, "doorbell")) { doorbell_written = true; t_doorbell = now; }
            if (cur.mark && !strcmp(cur.mark, "cleared")) clear_done_at = now;
            bus_state = 0;
            bus_wait_until = now + cur.wait_ps;
        } else if (cc - req_c > 5000) { ERR("host access %06x: no ack", cur.addr); bus_state = 0; }
        return;
    }
    if (now < bus_wait_until || ops.empty() || now < ops.front().at) return;
    cur = ops.front(); ops.pop_front();
    if (cur.addr == 0xFFFFFF) { bus_wait_until = now + cur.wait_ps; return; }   // pause
    top->zn_req = 1; top->zn_we = cur.we; top->zn_addr = cur.addr; top->zn_be = cur.be; top->zn_wdata = cur.d;
    if (zoom_addr(cur.addr)) sent.push_back(cur);
    bus_state = 1; req_c = cc;
}

static void wr8(uint32_t a, unsigned be, uint32_t d, const char *mark = nullptr, uint64_t w = 0) { ops.push_back({true, a, be, d, C_NONE, w, mark}); }
static void rd(uint32_t a, unsigned be, int chk) { ops.push_back({false, a, be, 0, chk, 0, nullptr}); }
static void pause_us(double us) { ops.push_back({false, 0xFFFFFF, 0, 0, C_NONE, (uint64_t)(us * 1e6), nullptr}); }
static void mbox_wr(unsigned byte, unsigned v, const char *mark = nullptr) {
    unsigned w = byte >> 1;
    if (byte & 1) wr8(0xBE0002 + 4 * w, 0xC, v << 16, mark); else wr8(0xBE0000 + 4 * w, 0x3, v, mark);
}
static void mbox_rd(unsigned byte, int chk) {
    unsigned w = byte >> 1;
    if (byte & 1) rd(0xBE0002 + 4 * w, 0xC, chk); else rd(0xBE0000 + 4 * w, 0x3, chk);
}

// ------------------------------------------------------------------ zoom side observation
static uint64_t insns = 0, insns_before_release = 0, mn_mb_rd = 0, mn_mb_wr = 0;
static uint64_t lines = 0, aud_nz = 0, irq0_pulses = 0;
static FILE *aud = nullptr;   // aud.bin: the TMS57002 SO1 pair at every output FIFO push (virtual time order)
static FILE *mbx = nullptr;   // mbx.log: MN10200 mailbox accesses and host acks, in order (sim/zoomddr3/cmp_runs.py)
static uint8_t last_zrst = 2, last_prst = 2;
static uint64_t sent_bad = 0, sent_ok = 0;
struct MAcc { char rw; uint32_t a; unsigned be; unsigned d; uint64_t t; };
static std::vector<MAcc> mn_acc, mame_acc;

static void p_pre() {                   // clk_1x: the cycle about to end
    if (top->p_rst != last_prst) { fprintf(hev, "%llu R %u\n", (unsigned long long)c1, top->p_rst); last_prst = top->p_rst; }
    if (top->zrst_p != last_zrst) {
        fprintf(hev, "%llu Z %u\n", (unsigned long long)c1, top->zrst_p);
        if (last_zrst == 1 && top->zrst_p == 0) {
            t_release_seen = now;
            if (!release_written && !t_release_wr) ERR("zoom_reset fell before the release write was acknowledged");
            if (!clear_done_at) ERR("zoom_reset fell before the mailbox was cleared");
        }
        last_zrst = top->zrst_p;
    }
    if (R->zl_vtop__DOT__p_h_req) {
        unsigned we = R->zl_vtop__DOT__p_h_we, be = R->zl_vtop__DOT__p_h_be;
        uint32_t a = R->zl_vtop__DOT__p_h_addr, d = R->zl_vtop__DOT__p_h_wdata;
        fprintf(hev, "%llu H %u %06x %x %08x\n", (unsigned long long)c1, we, a, be, d);
        if (sent.empty()) { sent_bad++; ERR("zoom_board got a host request nobody sent: %06x", a); }
        else {
            Op o = sent.front(); sent.pop_front();
            if (o.we != (bool)we || o.addr != a || o.be != be || (we && o.d != d)) {
                sent_bad++; ERR("host request %06x be %x we %u d %08x arrived as %06x be %x we %u d %08x", o.addr, o.be, o.we, o.d, a, be, we, d);
            } else sent_ok++;
        }
    }
    if (ZB(mbh_we)) { sh.wr(ZB(mbh_a), ZB(mbh_be), ZB(mbh_wd), now); sh.host_writes++; }
    if (mbx && ZB(h_ack)) fprintf(mbx, "A %08x\n", ZB(h_rdata));
    if (top->m_rvalid_o) lines++;
    if (aud && ZB(sync_q)) { uint16_t p[2] = {(uint16_t)ZB(so_l16), (uint16_t)ZB(so_r16)}; fwrite(p, 2, 2, aud); }
    // TMS57002 SO1 pair at each SYNC after the release (so.bin, 2 x int32:
    // the 24-bit registers sign-extended), for compare_so.py against MAME
    if (ZB(sync_q) && t_release_seen) {
        int32_t v[2] = { (int32_t)(ZB(so_l) << 8) >> 8, (int32_t)(ZB(so_r) << 8) >> 8 };
        fwrite(v, sizeof v, 1, sof);
        so_n++;
        if (v[0] || v[1]) so_nz++;
    }
    if (top->aud_l || top->aud_r) aud_nz++;
}

static void z_pre() {                   // clk_2x (the MN10200 side)
    if (top->dbg_insn) {
        Insn r;
        r.pc = top->dbg_pc; r.psw = top->dbg_psw; r.mdr = top->dbg_mdr;
        for (int i = 0; i < 6; i++) r.regs[i] = top->dbg_regs[i];
        fwrite(&r, sizeof r, 1, ins);
        insns++;
        if (!t_release_seen) insns_before_release++;
    }
    if (ZB(irq0_low) == 2) { irq0_pulses++; if (!t_irq0) t_irq0 = now; }
    uint32_t a = ZB(bus_addr);
    if ((a & 0xFFFF00) == 0xE00000) {
        if (ZB(mbz_we)) {
            sh.wr((a >> 1) & 0x7f, ZB(bus_be), ZB(bus_wdata), now); mn_mb_wr++; sh.mn_writes++;
            mn_acc.push_back({'W', a & 0xfffffe, ZB(bus_be), ZB(bus_wdata), now});
            if (mbx) fprintf(mbx, "M W %06x %x %04x\n", a & 0xfffffe, ZB(bus_be), ZB(bus_wdata));
        }
        if (ZB(bus_rd) && ZB(bus_ack)) {
            mn_acc.push_back({'R', a & 0xfffffe, ZB(bus_be), ZB(bus_rdata), now});
            if (mbx) fprintf(mbx, "M R %06x %x %04x\n", a & 0xfffffe, ZB(bus_be), ZB(bus_rdata));
            mn_mb_rd++; sh.mn_reads++;
            int c = sh.check((a >> 1) & 0x7f, ZB(bus_be), ZB(bus_rdata), now, 200000);
            if (c == 1) sh.mn_race++;
            if (c == 2) { sh.mn_bad++; ERR("MN10200 mailbox read %06x be %x: %04x, shadow %02x%02x", a, ZB(bus_be), ZB(bus_rdata), sh.b[(a & 0xfe) + 1], sh.b[a & 0xfe]); }
        }
    }
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) { fprintf(stderr, "usage: tb_zoomlink <flashdir> <outdir> [run1_ms] [run2_ms]\n"); return 2; }
    bool replay = argc > 6 && !strcmp(argv[3], "replay");
    double run1 = !replay && argc > 3 ? atof(argv[3]) : 30, run2 = !replay && argc > 4 ? atof(argv[4]) : 20;
    double t0 = replay ? atof(argv[5]) : 0, t_end = replay ? atof(argv[6]) : 0;
    const uint64_t BASE = 50000000;             // bench time of t0: 50 us, after the resets
    if (!load_flash(argv[1])) return 2;
    std::string od = argv[2];
    hev = fopen((od + "/hev.log").c_str(), "w");
    ins = fopen((od + "/insn.bin").c_str(), "wb");
    mbx = fopen((od + "/mbx.log").c_str(), "w");
    aud = fopen((od + "/aud.bin").c_str(), "wb");
    sof = fopen((od + "/so.bin").c_str(), "wb");
    if (!hev || !ins) { perror(argv[2]); return 2; }

    if (replay) {
        FILE *hl = fopen(argv[4], "r");
        if (!hl) { perror(argv[4]); return 2; }
        char ln[256];
        while (fgets(ln, sizeof ln, hl)) {
            char k, rw;
            unsigned long long sec, asec;
            unsigned o, d, m;
            double t;
            if (ln[0] == 'C' && sscanf(ln, "C %x %llu %llu", &d, &sec, &asec) == 3) {
                t = sec + asec * 1e-18;
                if (t < t0 || t > t_end) continue;
                Op op{true, 0xB40000, 0x1, d & 0xff, C_NONE, 0, nullptr};
                op.at = BASE + (uint64_t)((t - t0) * 1e12);
                if (!(d & 0x10) && !release_written) op.mark = "release";
                ops.push_back(op);
            } else if (sscanf(ln, "%c %c %x %x %x %llu %llu", &k, &rw, &o, &d, &m, &sec, &asec) == 7 && (k == 'H' || k == 'M')) {
                t = sec + asec * 1e-18;
                if (t < t0 || t > t_end) continue;
                if (k == 'M') {
                    unsigned be = (m & 0xff ? 1 : 0) | (m & 0xff00 ? 2 : 0);
                    mame_acc.push_back({rw, o, be, d, (uint64_t)((t - t0) * 1e12)});
                    continue;
                }
                for (int half = 0; half < 2; half++) {
                    uint32_t hm = (m >> (16 * half)) & 0xffff;
                    if (!hm) continue;
                    unsigned be = ((hm & 0xff) ? 1u : 0u) << (2 * half) | ((hm & 0xff00) ? 2u : 0u) << (2 * half);
                    Op op{rw == 'W', (o - 0x1F000000) & 0xFFFFFC, be, d, rw == 'R' ? C_MAME : C_NONE, 0, nullptr};
                    op.exp = d;
                    op.at = BASE + (uint64_t)((t - t0) * 1e12);
                    if ((o & 0xFFFFFFFCu) == 0x1FBA0000u && rw == 'W') op.mark = "doorbell";
                    if ((o & 0xFFFFFE00u) == 0x1FBE0000u && rw == 'W') op.mark = "cleared";
                    ops.push_back(op);
                }
            }
        }
        fclose(hl);
        // the release mark goes on the first control write with bit 4 clear only
        bool seen = false;
        for (auto &op : ops)
            if (op.mark && !strcmp(op.mark, "release")) { if (seen) op.mark = nullptr; seen = true; }
        // the end of the run: t_end
        Op endop{false, 0xFFFFFF, 0, 0, C_NONE, 0, nullptr};
        endop.at = BASE + (uint64_t)((t_end - t0) * 1e12);
        ops.push_back(endop);
        printf("replay: %zu bus steps from %s, %zu MN10200 mailbox accesses in MAME\n", ops.size() - 1, argv[4], mame_acc.size());
    } else {
    // script
    pause_us(20);
    rd(0xB40000, 0x1, C_CTRL10);
    for (unsigned i = 0; i < 256; i++) { self_pat[i] = (uint8_t)(i * 37 + 11); mbox_wr(i, self_pat[i]); }
    for (unsigned i = 0; i < 256; i++) mbox_rd(i, C_SELF);
    wr8(0xB40000, 0x1, 0xD8);                       // control |= 0x10 (already set)
    for (unsigned i = 0; i < 256; i++) mbox_wr(i, 0, i == 255 ? "cleared" : nullptr);
    wr8(0xB40000, 0x1, 0xD0);                       // bit 3 clear
    wr8(0xB40000, 0x1, 0xD8);                       // bit 3 set
    wr8(0xB40000, 0x1, 0xC8, "release");            // bit 4 clear: Zoom released
    pause_us(run1 * 1000);
    static const uint8_t cmd[8] = { 0x01, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00 };
    for (unsigned i = 0; i < 8; i++) mbox_wr(i, cmd[i]);
    wr8(0xBA0000, 0x3, 0, "doorbell");
    for (int k = 0; k < (int)(run2 * 5); k++) {
        for (unsigned i = 0; i < 32; i++) mbox_rd(i, C_SHADOW);
        pause_us(200);
    }
    }
    uint64_t script_ops = ops.size();

    top = new Vzl_vtop;
    R = top->rootp;
    top->c_rst = 1; top->p_rst = 1; top->clk_cpu = 0; top->clk1x = 0; top->clk2x = 0;
    top->eval();
    uint64_t n2 = 0, n1 = 0, nc = OFFC;   // next toggle times
    bool l2 = false, l1 = false, lc = false;
    uint64_t end_t = 0;
    while (!Verilated::gotFinish()) {
        uint64_t t = std::min(n2, std::min(n1, nc));
        now = t;
        bool r2 = (t == n2 && !l2), r1 = (t == n1 && !l1), rc = (t == nc && !lc);
        if (r1) p_pre();
        if (r2) z_pre();
        if (t == n2) { l2 = !l2; top->clk2x = l2; n2 += H2; }
        if (t == n1) { l1 = !l1; top->clk1x = l1; n1 += H1; }
        if (t == nc) { lc = !lc; top->clk_cpu = lc; nc += HC; }
        top->eval();
        if (r1) { c1++; top->p_rst = c1 < p_rst_c1; }
        if (r2) c2++;
        if (rc) { cc++; host_post(); sdram_post(); }
        if (r1 || rc) top->eval();
        if (ops.empty() && bus_state == 0 && !end_t) end_t = now;
        if (end_t && now >= end_t) break;
        if (errors > 200) break;
    }
    fprintf(hev, "%llu END\n", (unsigned long long)c1);
    fclose(hev); fclose(ins); fclose(mbx); fclose(aud); fclose(sof);

    printf("tb_zoomlink: %.3f ms simulated, clk_1x cycles %llu\n", now / 1e9, (unsigned long long)c1);
    printf("host: %llu script ops, %llu acknowledged, ack latency max %llu clk_cpu (mean %.1f); requests to zoom_board %llu as sent, %llu wrong, %zu missing\n",
           (unsigned long long)script_ops, (unsigned long long)host_ops, (unsigned long long)host_lat_max,
           host_ops ? (double)host_lat_sum / host_ops : 0.0, (unsigned long long)sent_ok, (unsigned long long)sent_bad, sent.size());
    printf("release: write acknowledged at %.3f us, zoom_board saw it at %.3f us; MN10200 instructions before release %llu, after %llu\n",
           t_release_wr / 1e6, t_release_seen / 1e6, (unsigned long long)insns_before_release, (unsigned long long)(insns - insns_before_release));
    printf("doorbell: written at %.3f us, IRQ0 pulse at %.3f us (%llu pulses)\n", t_doorbell / 1e6, t_irq0 / 1e6, (unsigned long long)irq0_pulses);
    printf("mailbox: host writes %llu, MN10200 writes %llu; MN10200 reads %llu (%llu wrong, %llu racing a write); host polled reads %llu (%llu wrong, %llu racing)\n",
           (unsigned long long)sh.host_writes, (unsigned long long)sh.mn_writes, (unsigned long long)sh.mn_reads,
           (unsigned long long)sh.mn_bad, (unsigned long long)sh.mn_race, (unsigned long long)sh.host_reads,
           (unsigned long long)sh.host_bad, (unsigned long long)sh.host_race);
    printf("memory: %llu lines to zoom_board, SDRAM reads %llu (%llu in the Zoom area), partial read byte enables %llu\n",
           (unsigned long long)lines, (unsigned long long)sd_reads, (unsigned long long)sd_zoom, (unsigned long long)sd_bad_be);
    printf("TMS57002 SO1: %llu samples after the release, %llu non-zero (so.bin)\n", (unsigned long long)so_n, (unsigned long long)so_nz);
    printf("audio: %llu clk_1x cycles with a non-zero sample; board flags %02x (arb_ovf sync_ovf late overrun wram_hi unmapped tms_rd under)\n",
           (unsigned long long)aud_nz, top->flags);
    if (replay) {
        // MN10200 mailbox accesses against MAME's, in order
        size_t n = std::min(mn_acc.size(), mame_acc.size()), eq = 0;
        for (; eq < n; eq++) {
            const MAcc &x = mn_acc[eq], &y = mame_acc[eq];
            unsigned mk = (x.be & 1 ? 0xff : 0) | (x.be & 2 ? 0xff00 : 0);
            if (x.rw != y.rw || x.a != y.a || x.be != y.be || (x.d & mk) != (y.d & mk)) break;
        }
        printf("replay: host reads %llu, %llu differ from MAME; MN10200 mailbox accesses: bench %zu, MAME %zu, equal in order %zu\n",
               (unsigned long long)mame_rd, (unsigned long long)mame_rd_bad, mn_acc.size(), mame_acc.size(), eq);
        if (eq < n) {
            const MAcc &x = mn_acc[eq], &y = mame_acc[eq];
            ERR("MN10200 mailbox access %zu: bench %c %06x be %x %04x, MAME %c %06x be %x %04x", eq, x.rw, x.a, x.be, x.d, y.rw, y.a, y.be, y.d);
        }
        if (mn_acc.size() != mame_acc.size()) ERR("MN10200 mailbox access count %zu, MAME %zu", mn_acc.size(), mame_acc.size());
        // timing against MAME, relative to t0 (bench: from BASE)
        for (size_t i = 0; i < n && i < 40; i++)
            if (i == 0 || mn_acc[i].rw != mn_acc[i - 1].rw || mn_acc[i].t - mn_acc[i - 1].t > 1000000000ull)
                printf("  access %zu %c %06x: bench %.6f s, MAME %.6f s after t0 (difference %+.1f us)\n", i, mn_acc[i].rw, mn_acc[i].a,
                       (mn_acc[i].t - BASE) / 1e12, mame_acc[i].t / 1e12, ((double)(mn_acc[i].t - BASE) - (double)mame_acc[i].t) / 1e6);
    }
    if (!t_release_seen) ERR("zoom_reset never fell");
    if (insns_before_release) ERR("the MN10200 ran before the release");
    if (doorbell_written && !t_irq0) ERR("doorbell without an IRQ0 pulse");
    if (!replay && t_irq0 && t_irq0 < t_doorbell - 2000000) ERR("IRQ0 before the doorbell");
    if (top->flags & 0xfe) ERR("board flags %02x", top->flags);
    printf("RESULT tb_zoomlink errors %llu\n", (unsigned long long)errors);
    delete top;
    return errors ? 1 : 0;
}
