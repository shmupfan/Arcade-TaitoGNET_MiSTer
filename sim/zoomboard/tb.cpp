// Board-level Verilator testbench for rtl/zoom/zoom_board.sv
// (docs/zoom_board_design.md 10): the real Zoom firmware runs on the
// MN10200 RTL with the board's program cache, work RAM, mailbox, bus
// decoder, time base and the ZSG-2 RTL, driven only by the main CPU's
// accesses as MAME made them, and is compared with MAME instruction by
// instruction and sample by sample.
//
//   tb <flashdir> <trace> [max_insns] [report_every]
//
// flashdir holds zoomprog and wave0..2 from tools/build_flash.py (MAME NVRAM
// layout, 16-bit words byte-swapped). trace is a file or a FIFO from
// tools/zoom/zoom_oracle.sh (format in tools/zoom/zoom_oracle.lua).
//
// What comes from MAME:
//   - main-CPU accesses to the Zoom ports (H lines) and the Zoom reset bit
//     (C lines), applied at the instruction boundary where they appear;
//   - the IRQ1 pin (TMS57002 EMPTY) from FC57, because the TMS57002 is a
//     black box here; IRQ0 comes from the board's own doorbell;
//   - the sample phase at each Zoom reset release, from the first timed
//     ZSG-2 access of the segment (MAME's local time is linear in the
//     MN10200's cycles, checked on the canary).
// What is checked:
//   - per instruction: PC, D0-D3, A0-A3, PSW, MDR, the previous
//     instruction's cycles, FC42 and FC50 (as sim/mn10200/tb.cpp);
//   - every MN10200 access to the ZSG-2, the TMS57002 port and the mailbox:
//     address, lanes, write data, and the data the board's devices return
//     on reads (MAME's B lines);
//   - for every ZSG-2 access, the sample position: the board's sample ticks
//     since the release equal floor(t x 32552) - (first sample - 1);
//   - every ZSG-2 output sample of a run segment against the TMS57002
//     serial inputs MAME logged for the same sample (S lines);
//   - host reads of the Zoom ports.
// Known MAME divergence accepted and counted (MN102_STRICT=1 refuses it):
// MULU NF (docs/mn10200_rtl.md 4.3).
//
// Env: ZB_PACE=1 pacer on; ZB_LAT=<clocks per 64-bit line> (default 10, one
// line at a time, as zoom_line32 on SDRAM channel 3); ZB_JIT=<clocks> random
// extra latency 0..JIT; ZB_OUTST=<n> lines outstanding (default 1).
#include "Vzoom_board.h"
#include "Vzoom_board___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <deque>
#include <map>

typedef __int128 i128;
static Vzoom_board *top;
#define R (top->rootp)

// ------------------------------------------------------------------ trace reader
struct TLine {
    uint32_t pc, d[4], a[4], psw, mdr;
    uint64_t tc;
    uint32_t fc57, fc50, fc42;
    std::string dis;
};
struct BusRec { char rw; uint32_t addr, data, mask; bool timed; i128 t; bool land; int lpc, lcnt; };
struct Ev { char kind; char rw; uint32_t addr, data, mask; i128 t; };   // H or C
static std::deque<BusRec> busq;
static std::deque<std::string> ahead;   // lines read ahead (phase lookahead)
static FILE *tf;
static uint64_t n_b = 0, n_h = 0, n_s = 0;

static bool raw_line(std::string &s) {
    if (!ahead.empty()) { s = ahead.front(); ahead.pop_front(); return true; }
    static char buf[1024];
    if (!fgets(buf, sizeof buf, tf)) return false;
    s = buf;
    return true;
}
static bool peek_line(size_t i, std::string &s) {
    static char buf[1024];
    while (ahead.size() <= i) {
        if (!fgets(buf, sizeof buf, tf)) return false;
        ahead.push_back(buf);
    }
    s = ahead[i];
    return true;
}
static i128 ttime(unsigned long long s, unsigned long long as) { return (i128)s * 1000000000000000000LL + as; }

static bool parse_t(const std::string &s, TLine &t) {
    unsigned long long tc;
    unsigned v[15];
    if (sscanf(s.c_str() + 2, "%x %x %x %x %x %x %x %x %x %x %x %llx %x %x %x",
               &v[0], &v[1], &v[2], &v[3], &v[4], &v[5], &v[6], &v[7], &v[8], &v[9], &v[10],
               &tc, &v[11], &v[12], &v[13]) != 15) return false;
    t.pc = v[0];
    for (int i = 0; i < 4; i++) { t.d[i] = v[1 + i]; t.a[i] = v[5 + i]; }
    t.psw = v[9]; t.mdr = v[10]; t.tc = tc;
    t.fc57 = v[11]; t.fc50 = v[12]; t.fc42 = v[13];
    t.dis = "?";
    return true;
}

// S lines: MAME's ZSG-2 outputs per sample, as TMS57002 inputs
static std::map<int64_t, std::vector<uint32_t>> s_mame, s_rtl;
static uint64_t s_cmp = 0, s_bad = 0;
static bool seg_run = false;            // the MN10200 runs (compare samples)
static int64_t kbase = 0;               // sample index of RTL tick 0 in this segment
static bool phase_ok = false;
static bool held = true;                // zoom_reset as last applied
static bool pending_assert = false;
static i128 seg_t0 = 0;                 // MAME time of totalcycles 0 in this segment
static char failmsg[600];
static bool fail = false;

static void s_compare(int64_t k) {
    auto a = s_mame.find(k), b = s_rtl.find(k);
    if (a == s_mame.end() || b == s_rtl.end()) return;
    s_cmp++;
    if (a->second != b->second) {
        s_bad++;
        if (!fail) {
            snprintf(failmsg, sizeof failmsg, "ZSG-2 output sample %lld: RTL %06x %06x %06x %06x, MAME %06x %06x %06x %06x",
                     (long long)k, b->second[0], b->second[1], b->second[2], b->second[3],
                     a->second[0], a->second[1], a->second[2], a->second[3]);
            fail = true;
        }
    }
    s_mame.erase(a);
    s_rtl.erase(b);
}

// TMS57002 SO1 per sample, MAME and board, per run segment (index = sample
// - kbase). The board runs the program for sample k on the ZSG-2 output of
// k - 1 (design study 6.1), so the two are compared at offsets -2 to 2 and
// the best offset is reported.
static std::vector<uint64_t> so_mame, so_rtl;     // bit 63 = present
static uint64_t land_n = 0, land_ds[7], land_far = 0, land_in1 = 0;
static int64_t land_max = 0, land_sum = 0, first_land = -1;
struct LandOff { int64_t sync; int ds, pcb, pcm; uint32_t data; };
static std::vector<LandOff> land_off;          // landings not in MAME's sample, this segment
static uint64_t so_hits[5], so_n[5], so_nonzero = 0;
static void so_put(std::vector<uint64_t> &v, int64_t i, uint32_t l, uint32_t r) {
    if (i < 0 || i > 50000000) return;
    if ((size_t)i >= v.size()) v.resize(i + 1, 0);
    v[i] = (1ull << 63) | ((uint64_t)(l & 0xffffff) << 24) | (r & 0xffffff);
}
static void so_flush() {
    {
        // first difference at the offset where the board's SO1 is MAME's of the same sample + 1 (d = -1)
        int64_t first = -1, eq = 0;
        for (size_t i = 1; i < so_rtl.size() && (size_t)(i - 1) < so_mame.size(); i++) {
            uint64_t a = so_rtl[i], b = so_mame[i - 1];
            if (!(a >> 63) || !(b >> 63)) continue;
            if (a != b) { first = (int64_t)i; break; }
            eq++;
        }
        if (!so_rtl.empty())
            fprintf(stderr, "SO1 segment: %zu board samples, first difference at board sync %lld (%lld equal before it), first TMS57002 host byte at sync %lld\n",
                    so_rtl.size(), (long long)first, (long long)eq, (long long)first_land);
        // the landings in another sample than MAME's just before the first difference
        if (first >= 0) {
            int shown = 0;
            for (auto it = land_off.rbegin(); it != land_off.rend() && shown < 8; ++it) {
                if (it->sync > first) continue;
                fprintf(stderr, "  landing off by %d sample(s) at board sync %lld (board pc %d, MAME pc %d, byte %02x), %lld samples before the difference\n",
                        it->ds, (long long)it->sync, it->pcb, it->pcm, it->data, (long long)(first - it->sync));
                shown++;
            }
        }
        land_off.clear();
    }
    for (int d = -2; d <= 2; d++)
        for (size_t i = 0; i < so_rtl.size(); i++) {
            int64_t j = (int64_t)i + d;
            if (j < 0 || (size_t)j >= so_mame.size()) continue;
            uint64_t a = so_rtl[i], b = so_mame[j];
            if (!(a >> 63) || !(b >> 63)) continue;
            so_n[d + 2]++;
            if (a == b) so_hits[d + 2]++;
            if (d == 0 && (b & 0xffffffffffffull)) so_nonzero++;
        }
    so_mame.clear(); so_rtl.clear();
}

// Reads lines up to the next T line. B lines go to busq, S lines are
// compared, H and C lines are returned as events to apply before that T.
static bool read_next(TLine &t, std::vector<Ev> &evs) {
    std::string s;
    while (raw_line(s)) {
        const char *c = s.c_str();
        if (c[0] == 'T' && c[1] == ' ') {
            if (!parse_t(s, t)) { fprintf(stderr, "bad T line: %s", c); exit(2); }
            std::string d;
            if (peek_line(0, d) && d[0] != 'T' && d[0] != 'B' && d[0] != 'H' && d[0] != 'C' && d[0] != 'S') {
                ahead.pop_front();
                d.erase(d.find_last_not_of("\r\n") + 1);
                t.dis = d;
            }
            return true;
        }
        if (c[0] == 'B' && c[1] == ' ') {
            BusRec r{};
            unsigned a, d, m;
            unsigned long long ts, tas;
            int cnt;
            int n = sscanf(c + 2, "%c %x %x %x %llu %llu %d", &r.rw, &a, &d, &m, &ts, &tas, &cnt);
            if (n < 4) { fprintf(stderr, "bad B line: %s", c); exit(2); }
            r.addr = a; r.data = d; r.mask = m;
            if (n == 7) { r.timed = true; r.t = ttime(ts, tas); }
            const char *lp = strstr(c, " L ");
            if (lp && sscanf(lp + 3, "%d %d", &r.lpc, &r.lcnt) == 2) r.land = true;
            busq.push_back(r);
            n_b++;
            continue;
        }
        if ((c[0] == 'H' || c[0] == 'C') && c[1] == ' ') {
            Ev e{};
            e.kind = c[0];
            unsigned long long ts, tas;
            if (c[0] == 'H') {
                unsigned a, d, m;
                if (sscanf(c + 2, "%c %x %x %x %llu %llu", &e.rw, &a, &d, &m, &ts, &tas) != 6) { fprintf(stderr, "bad H line: %s", c); exit(2); }
                e.addr = a; e.data = d; e.mask = m;
                n_h++;
            } else {
                unsigned d;
                if (sscanf(c + 2, "%x %llu %llu", &d, &ts, &tas) != 3) { fprintf(stderr, "bad C line: %s", c); exit(2); }
                e.data = d;
            }
            e.t = ttime(ts, tas);
            evs.push_back(e);
            continue;
        }
        if (c[0] == 'S' && c[1] == ' ') {
            long long k;
            int cnt;
            unsigned v[6];
            int nf = sscanf(c + 2, "%lld %d %u %u %u %u %u %u", &k, &cnt, &v[0], &v[1], &v[2], &v[3], &v[4], &v[5]);
            if (nf != 6 && nf != 8) { fprintf(stderr, "bad S line: %s", c); exit(2); }
            n_s++;
            if (seg_run && phase_ok && k > kbase) {
                s_mame[k] = {v[0], v[1], v[2], v[3]};
                s_compare(k);
                if (nf == 8) so_put(so_mame, k - kbase, v[4], v[5]);
            }
            continue;
        }
    }
    return false;
}

// ------------------------------------------------------------------ memory (flash area)
static std::vector<uint8_t> fa(16 << 20, 0xff);
static unsigned mem_lat = 10, mem_jit = 0, mem_outst = 1;
struct MemReq { uint64_t due; uint32_t line; };
static std::deque<MemReq> memq;
static uint64_t mem_lines = 0;
static uint32_t rng = 12345;
static unsigned rnd() { rng = rng * 1103515245u + 12345u; return (rng >> 16) & 0x7fff; }
static uint64_t mem_last_done = 0;

static bool load_flash(const char *dir) {
    struct { const char *n; uint32_t base; size_t len; } f[] = {
        { "zoomprog", 0x200000, 0x80000 }, { "wave0", 0x400000, 0x200000 },
        { "wave1", 0x600000, 0x200000 }, { "wave2", 0x800000, 0x200000 } };
    for (auto &x : f) {
        std::string p = std::string(dir) + "/" + x.n;
        FILE *h = fopen(p.c_str(), "rb");
        if (!h) { perror(p.c_str()); return false; }
        if (fread(&fa[x.base], 1, x.len, h) != x.len) { fprintf(stderr, "short %s\n", p.c_str()); return false; }
        fclose(h);
        for (size_t i = 0; i < x.len; i += 2) std::swap(fa[x.base + i], fa[x.base + i + 1]);  // NVRAM is byte-swapped
    }
    return true;
}

// ------------------------------------------------------------------ program cache model sweep
struct CacheModel {
    unsigned size, line, ways;
    std::vector<uint32_t> tag;
    std::vector<uint8_t> valid, lru;
    uint64_t miss = 0;
    CacheModel(unsigned s, unsigned l, unsigned w) : size(s), line(l), ways(w) {
        unsigned sets = s / l / w;
        tag.assign(sets * w, 0); valid.assign(sets * w, 0); lru.assign(sets, 0);
    }
    void inval() { std::fill(valid.begin(), valid.end(), 0); }
    void access(uint32_t a) {
        unsigned sets = size / line / ways;
        uint32_t ln = a / line, set = ln % sets, tg = ln / sets;
        for (unsigned w = 0; w < ways; w++)
            if (valid[set * ways + w] && tag[set * ways + w] == tg) { lru[set] = w; return; }
        miss++;
        unsigned w = ways == 1 ? 0 : (lru[set] ^ 1);
        tag[set * ways + w] = tg; valid[set * ways + w] = 1; lru[set] = w;
    }
};
static std::vector<CacheModel> cmodels;
static uint64_t prog_reads = 0;

// ------------------------------------------------------------------ clock and observation
static uint64_t syncs_seg = 0, empty_diff = 0, out_ticks = 0, out_under = 0;
static uint64_t clocks = 0, ticks_seg = 0, passes_seg = 0, pc_misses = 0, zrd_clocks = 0, credit_cap_clocks = 0;
static uint64_t chk_ext = 0, chk_zsg_t = 0, rd_zsg = 0, rd_mb = 0, chk_tms = 0;
static uint64_t max_pass = 0, hi_level = 0;
static bool pace = false;
#ifndef ZB_CLK_H
#define ZB_CLK_H 2
#endif
#ifndef ZB_CAP_DEFAULT
#define ZB_CAP_DEFAULT 64
#endif
static int clk_h = ZB_CLK_H;        // the build's CLK_H: clk = clk_1x x clk_h / 2 (sim/zoomboard/build.sh)
static int64_t win_lo = -1, win_hi = -1;
// CMEM update episodes: the last host byte (board sync/pc, MAME count/pc)
// before each update the board applies, and the sample MAME applies it in
// (the next CMEM read of SA after its last byte: same sample if the byte
// lands at or before the reading instruction's PC, else the next one)
static int64_t ep_b_sync = -1, ep_m_cnt = -1;
static int ep_b_pc = 0, ep_m_pc = 0;
static uint64_t ep_n = 0, ep_same = 0, ep_m_later = 0, ep_m_earlier = 0, ep_shown = 0;   // ZB_LANDWIN=lo,hi: log TMS57002 bytes and updates in these syncs
static uint64_t mc_steps = 0, run_clocks = 0, lag_hist[5];
static int max_lag = 0;
static int32_t cap_credit = 64 * 84672;

static unsigned mask_of(unsigned be) { return (be & 1 ? 0x00ff : 0) | (be & 2 ? 0xff00 : 0); }
static bool ext_dev(uint32_t a) {
    return (a >= 0x800000 && a <= 0x8007ff) || a == 0xc00000 || (a >= 0xe00000 && a <= 0xe000ff);
}

struct LandRec { int lcnt; int lpc; unsigned data; bool use; };
static std::deque<LandRec> landq;
// landing of a host byte at the TMS57002 (zoom_board th_wr, clk side):
// board (syncs since the release, DSP PC) against MAME (sample count, PC)
static void land_take() {
    if (landq.empty()) {
        if (!fail) { snprintf(failmsg, sizeof failmsg, "TMS57002 host byte delivered with no write in the queue"); fail = true; }
        return;
    }
    LandRec r = landq.front();
    landq.pop_front();
    if ((R->zoom_board__DOT__th_d & 0xff) != r.data && !fail) {
        snprintf(failmsg, sizeof failmsg, "TMS57002 host byte %02x delivered, written %02x", R->zoom_board__DOT__th_d & 0xff, r.data);
        fail = true;
    }
    if (!(r.use && seg_run && phase_ok)) return;
    int64_t ds = (int64_t)syncs_seg - r.lcnt;
    int dp = (int)R->zoom_board__DOT__tms_pc - r.lpc;
    int64_t slots = ds * 384 + dp;
    land_n++;
    if (ds >= -3 && ds <= 3) land_ds[ds + 3]++; else land_far++;
    if (slots >= -384 && slots <= 384) land_in1++;
    if (llabs(slots) > land_max) land_max = llabs(slots);
    land_sum += slots;
    if (first_land < 0) first_land = (int64_t)syncs_seg;
    ep_b_sync = (int64_t)syncs_seg; ep_b_pc = (int)R->zoom_board__DOT__tms_pc;
    ep_m_cnt = r.lcnt; ep_m_pc = r.lpc;
    if ((int64_t)syncs_seg >= win_lo && (int64_t)syncs_seg <= win_hi)
        fprintf(stderr, "LB board %lld pc %d | MAME %d pc %d | byte %02x pins %u\n", (long long)syncs_seg,
                (int)R->zoom_board__DOT__tms_pc, r.lcnt, r.lpc, r.data, (unsigned)R->zoom_board__DOT__pins_q);
    if (ds != 0) land_off.push_back({(int64_t)syncs_seg, (int)ds, (int)R->zoom_board__DOT__tms_pc, r.lpc, r.data});
}

static void check_access() {
    bool rd = R->zoom_board__DOT__bus_rd, wr = R->zoom_board__DOT__bus_wr;
    if (!(R->zoom_board__DOT__bus_ack && (rd || wr))) return;
    uint32_t a = R->zoom_board__DOT__bus_addr & 0xfffffe;
    unsigned mask = mask_of(R->zoom_board__DOT__bus_be);
    if (rd && a >= 0x080000 && a < 0x100000) {
        prog_reads++;
        for (auto &m : cmodels) m.access(a - 0x080000);
    }
    if (!ext_dev(a)) return;
    char rw = wr ? 'W' : 'R';
    uint16_t d = wr ? (R->zoom_board__DOT__bus_wdata & mask) : (R->zoom_board__DOT__bus_rdata & mask);
    if (busq.empty()) {
        if (!fail) { snprintf(failmsg, sizeof failmsg, "bus: board %c %06x %04x %04x, MAME made no further access", rw, a, d, mask); fail = true; }
        return;
    }
    BusRec r = busq.front();
    busq.pop_front();
    chk_ext++;
    if (r.rw != rw || r.addr != a || r.mask != mask || (r.data & mask) != d) {
        if (!fail) {
            snprintf(failmsg, sizeof failmsg, "bus: board %c %06x %04x %04x, MAME %c %06x %04x %04x",
                     rw, a, d, mask, r.rw, r.addr, r.data & mask, r.mask);
            fail = true;
        }
        return;
    }
    if (a >= 0x800000 && a <= 0x8007ff) { if (rd) rd_zsg++; }
    else if (a >= 0xe00000) { if (rd) rd_mb++; }
    else {
        chk_tms++;
        // the byte reaches the TMS57002 later, when the slot feeder delivers
        // it (zoom_board th_wr, I5): its landing is taken there (land_take)
        if (r.land) landq.push_back({r.lcnt, r.lpc, (unsigned)(r.data & 0xff), seg_run && phase_ok});
    }
    if (r.timed && phase_ok && seg_run) {
        int64_t k = (int64_t)((r.t * 32552) / (i128)1000000000000000000LL);
        chk_zsg_t++;
        static bool dbgz = getenv("ZB_DEBUGZ") != nullptr;
        if (dbgz)
            fprintf(stderr, "ZACC %c %06x k %lld ticks %llu left %u pre %u cyc %llu\n", rw, a, (long long)(k - kbase),
                    (unsigned long long)ticks_seg, R->zoom_board__DOT__u_tbase__DOT__left, R->zoom_board__DOT__u_tbase__DOT__pre,
                    (unsigned long long)top->dbg_cycles);
        if ((int64_t)ticks_seg != k - kbase && !fail) {
            snprintf(failmsg, sizeof failmsg, "ZSG-2 %c %06x at MAME sample %lld (segment sample %lld), board ticks %llu",
                     rw, a, (long long)k, (long long)(k - kbase), (unsigned long long)ticks_seg);
            fail = true;
        }
    }
}

// One tick is one clock of the MN10200 side: clk (CLK_H 2) or clk2x
// (CLK_H 4, where every other tick is also a clk edge: sedge). clk-side
// signals are observed and the memory model runs only at clk edges.
static bool f_mid = false;              // CLK_H 4: the next tick is a clk2x edge in mid clk cycle
static bool last_sedge = true;
static uint64_t s_clocks = 0;
static void tick() {
    bool sedge = clk_h == 2 || !f_mid;
    last_sedge = sedge;
    // pre-edge: memory handshake and the access the core completes at this edge
    bool acc = sedge && top->m_req && top->m_ready;
    uint32_t acc_line = top->m_line;
    bool rv = sedge && top->m_rvalid;
    check_access();
    if (sedge && R->zoom_board__DOT__u_out__DOT__tick && !held && seg_run) {
        out_ticks++;
        if (R->zoom_board__DOT__u_out__DOT__started && R->zoom_board__DOT__u_out__DOT__level == 0) {
            out_under++;
            if (out_under <= 40) {
                int32_t c = (int32_t)R->zoom_board__DOT__u_cpu__DOT__credit;
                fprintf(stderr, "UNDER at clock %llu (seg sample %llu): lag %d cycles, feeder sa %u sb %u sp %u, pc %06x\n",
                        (unsigned long long)clocks, (unsigned long long)syncs_seg, c / (42336 * clk_h),
                        (unsigned)R->zoom_board__DOT__u_feed__DOT__sa, (unsigned)R->zoom_board__DOT__u_feed__DOT__sb,
                        (unsigned)R->zoom_board__DOT__u_feed__DOT__sp, top->dbg_pc);
            }
        }
    }
    if (R->zoom_board__DOT__z_rd) zrd_clocks++;
    if (clk_h != 2) {
        // CLK_H 4: clk2x every tick, clk rises on aligned ticks, falls on mid ticks
        if (!f_mid) { top->clk = 1; top->hclk = 1; }
        else        { top->clk = 0; top->hclk = 0; }
        top->clk2x = 1; top->eval();
        top->clk2x = 0; top->eval();
        f_mid = !f_mid;
    } else {
        top->clk = 1; top->clk2x = 1; top->hclk = 1; top->eval();
        top->clk2x = 0; top->eval();
        top->clk = 0; top->hclk = 0; top->clk2x = 1; top->eval();
        top->clk2x = 0; top->eval();
    }
    clocks++;
    if (!held) run_clocks++;
    if (!sedge) goto fside;
    s_clocks++;
    // post-edge: memory model (clk side)
    if (rv) memq.pop_front();
    if (acc) {
        uint64_t start = std::max<uint64_t>(s_clocks, mem_last_done);
        uint64_t due = start + mem_lat + (mem_jit ? rnd() % (mem_jit + 1) : 0);
        mem_last_done = mem_outst == 1 ? due : s_clocks;
        memq.push_back({due, acc_line});
        mem_lines++;
    }
    top->m_ready = memq.size() < mem_outst;
    if (!memq.empty() && s_clocks >= memq.front().due) {
        uint64_t v = 0;
        uint32_t b = (memq.front().line << 3) & 0xffffff;
        for (int i = 7; i >= 0; i--) v = v << 8 | fa[b + i];
        top->m_rdata = v;
        top->m_rvalid = 1;
    } else top->m_rvalid = 0;
    // observation, clk side
    if (R->zoom_board__DOT__th_wr) land_take();
    if (seg_run && phase_ok && R->zoom_board__DOT__u_tms__DOT__ph == 2 && R->zoom_board__DOT__u_tms__DOT__upd_take && ep_b_sync >= 0) {
        int rpc = (int)R->zoom_board__DOT__tms_pc;
        int64_t m_apply = ep_m_pc <= rpc ? ep_m_cnt : ep_m_cnt + 1;
        int64_t b_apply = (int64_t)syncs_seg;
        ep_n++;
        if (m_apply == b_apply) ep_same++;
        else {
            if (m_apply > b_apply) ep_m_later++; else ep_m_earlier++;
            if (ep_shown++ < 20)
                fprintf(stderr, "EP update sa %d read pc %d: board applies in %lld (last byte sync %lld pc %d), MAME in %lld (last byte count %lld pc %d)\n",
                        (int)R->zoom_board__DOT__u_tms__DOT__sa, rpc, (long long)b_apply, (long long)ep_b_sync, ep_b_pc,
                        (long long)m_apply, (long long)ep_m_cnt, ep_m_pc);
        }
        ep_b_sync = -1;
    }
    if (win_lo >= 0 && seg_run && (int64_t)syncs_seg >= win_lo && (int64_t)syncs_seg <= win_hi) {
        static uint8_t pp1 = 0;
        uint8_t p1 = R->zoom_board__DOT__pins_q & 3;
        if (p1 != pp1) fprintf(stderr, "P1 board %lld pc %d pload_n/cload_n %u%u\n", (long long)syncs_seg,
                               (int)R->zoom_board__DOT__tms_pc, p1 & 1, (p1 >> 1) & 1);
        pp1 = p1;
        if (R->zoom_board__DOT__u_tms__DOT__ph == 2 && R->zoom_board__DOT__u_tms__DOT__upd_take)
            fprintf(stderr, "UT board %lld pc %d sa %d\n", (long long)syncs_seg, (int)R->zoom_board__DOT__tms_pc,
                    (int)R->zoom_board__DOT__u_tms__DOT__sa);
    }
    if (R->zoom_board__DOT__sync_q && seg_run && phase_ok) {
        syncs_seg++;
        so_put(so_rtl, (int64_t)syncs_seg, R->zoom_board__DOT__so_l, R->zoom_board__DOT__so_r);
    }
    if (R->zoom_board__DOT__zo_valid) {
        passes_seg++;
        if (R->zoom_board__DOT__pass_clocks > max_pass && seg_run) max_pass = R->zoom_board__DOT__pass_clocks;
        if (seg_run && phase_ok) {
            int64_t k = kbase + (int64_t)passes_seg;
            s_rtl[k] = {R->zoom_board__DOT__zo_si0, R->zoom_board__DOT__zo_si1, R->zoom_board__DOT__zo_si2, R->zoom_board__DOT__zo_si3};
            s_compare(k);
        }
    }
fside:
    // observation, MN10200 side
    if (R->zoom_board__DOT__sample_tick) ticks_seg++;
    if (R->zoom_board__DOT__pc_miss) pc_misses++;
    if (R->zoom_board__DOT__mc_step && !held) mc_steps++;
    if (pace) {
        int32_t c = (int32_t)R->zoom_board__DOT__u_cpu__DOT__credit;
        int lag = c / (42336 * clk_h);          // machine cycles behind real time
        if (lag > max_lag) max_lag = lag;
        static bool laglog = getenv("ZB_LAGLOG") != nullptr;
        static bool over = false;
        if (laglog && !over && lag >= 64) fprintf(stderr, "LAG>=64 at clock %llu pc %06x misses %llu zrd %llu\n",
                                                  (unsigned long long)clocks, top->dbg_pc, (unsigned long long)pc_misses, (unsigned long long)zrd_clocks);
        if (laglog && over && lag < 16) fprintf(stderr, "LAG<16 at clock %llu pc %06x misses %llu\n", (unsigned long long)clocks, top->dbg_pc, (unsigned long long)pc_misses);
        over = lag >= 64 ? true : (lag < 16 ? false : over);
        for (int b = 0; b < 5; b++) if (lag >= (16 << b)) lag_hist[b]++;
        if (c >= cap_credit) credit_cap_clocks++;
    }
}

static unsigned rtl_icr(int g) {
    unsigned ir = R->zoom_board__DOT__u_cpu__DOT__u_periph__DOT__icr_ir[g - 1];
    unsigned h = R->zoom_board__DOT__u_cpu__DOT__u_periph__DOT__icr_h[g - 1];
    return (ir << 4) | (ir & h & 0xf);
}

// ------------------------------------------------------------------ host side
static uint64_t host_rd_bad = 0;
static void host_access(const Ev &e) {
    top->h_req = 1;
    top->h_we = e.rw == 'W';
    top->h_addr = (e.addr - 0x1f000000) & 0xffffff;
    top->h_be = ((e.mask & 0xff) ? 1 : 0) | ((e.mask & 0xff00) ? 2 : 0) | ((e.mask & 0xff0000) ? 4 : 0) | ((e.mask & 0xff000000) ? 8 : 0);
    top->h_wdata = e.data;
    bool hit = false;
    top->eval();
    hit = top->h_hit;
    do tick(); while (!last_sedge);
    top->h_req = 0;
    int g = 0;
    while (!top->h_ack && ++g < 20) tick();
    if (!hit || g >= 20) {
        if (!fail) { snprintf(failmsg, sizeof failmsg, "host %c %08x: %s", e.rw, e.addr, hit ? "no ack" : "not decoded"); fail = true; }
        return;
    }
    if (e.rw == 'R' && (top->h_rdata & e.mask) != (e.data & e.mask)) {
        host_rd_bad++;
        if (!fail) { snprintf(failmsg, sizeof failmsg, "host R %08x: board %08x, MAME %08x (mask %08x)", e.addr, top->h_rdata, e.data, e.mask); fail = true; }
    }
}

// ------------------------------------------------------------------ phase at a Zoom reset release
// MAME's local time on the MN10200 is t0 + C x 160 ns (C = totalcycles), and
// an access lands at the totalcycles of the next T line. Sample k is passed
// when C >= C_k = ceil((k x 6,250,000 + Phi) / 32552), Phi = -floor(32552 t0 / 160 ns).
static int64_t floordiv(i128 a, i128 b) { i128 q = a / b; if ((a % b != 0) && ((a < 0) != (b < 0))) q--; return (int64_t)q; }
static bool find_phase(uint64_t c_first, unsigned &left, unsigned &rem) {
    // c_first: totalcycles of the first instruction after the release (the
    // T line the main loop holds); the lines after it are read ahead
    std::string s;
    bool have_first = true;
    i128 tB = 0;
    bool have_b = false;
    for (size_t i = 0;; i++) {
        if (!peek_line(i, s)) return false;
        if (s[0] == 'C' && s[1] == ' ') {
            unsigned d; unsigned long long a, b;
            sscanf(s.c_str() + 2, "%x %llu %llu", &d, &a, &b);
            if (d & 0x10) return false;             // held again before any ZSG-2 access
        }
        if (s[0] == 'T' && s[1] == ' ') {
            TLine t;
            parse_t(s, t);
            if (have_b) {
                i128 t0 = tB - (i128)t.tc * 160000000000LL;
                seg_t0 = t0;
                i128 t1 = t0 + (i128)c_first * 160000000000LL;
                int64_t k1 = floordiv(t1 * 32552, (i128)1000000000000000000LL) + 1;
                int64_t phi = -floordiv(t0 * 32552, (i128)160000000000LL);
                i128 K = (i128)k1 * 6250000 + phi;
                int64_t ck = floordiv(K - 1, 32552) + 1;
                left = (unsigned)(ck - (int64_t)c_first);
                rem = (unsigned)((K - 1) - (i128)floordiv(K - 1, 32552) * 32552);
                kbase = k1 - 1;
                fprintf(stderr, "phase: C_first %llu, first sample %lld, left %u, rem %u\n",
                        (unsigned long long)c_first, (long long)k1, left, rem);
                return left >= 1 && left <= 193;
            }
        }
        if (s[0] == 'B' && s[1] == ' ' && have_first && !have_b) {
            char rw; unsigned a, d, m; unsigned long long ts, tas; int cnt;
            if (sscanf(s.c_str() + 2, "%c %x %x %x %llu %llu %d", &rw, &a, &d, &m, &ts, &tas, &cnt) == 7) {
                tB = ttime(ts, tas);
                have_b = true;
            }
        }
    }
}

static uint64_t releases = 0;
static void settle() {
    // let the core reach its boundary (finish the current instruction)
    if (held) return;
    int g = 0;
    while (!top->dbg_bound && !fail && ++g < 200000) tick();
}
// The IRQ0 doorbell, like the reset, goes through MAME's synchronised
// set_input_line (taito_zm.cpp:139-143): MAME's MN10200 sees it at the first
// instruction that starts at or after the write's time on its own clock,
// not where the H line sits in the stream. Doorbell writes wait in dbq.
static std::deque<Ev> dbq;
static uint64_t doorbells = 0;
static void apply_event(const Ev &e, uint64_t c_first) {
    if (e.kind == 'H' && e.rw == 'W' && (e.addr & ~3u) == 0x1fba0000 && !held && phase_ok) { dbq.push_back(e); return; }
    if (e.kind == 'H') { settle(); host_access(e); return; }
    // MAME applies the reset line through a synchronised input
    // (set_input_line), so it takes effect at the write's time on the
    // MN10200's own clock: the MN10200 may run on after the C line until it
    // reaches that time. The assert is therefore kept pending and applied
    // just before the release (no MN10200 instruction runs in between).
    bool b4 = (e.data >> 4) & 1;
    if (b4) { if (!held) pending_assert = true; return; }
    if (!held && !pending_assert) return;
    settle();
    if (pending_assert) {
        pending_assert = false;
        top->zoom_reset = 1;
        for (int i = 0; i < 8; i++) tick();
        held = true;
        seg_run = false;
        s_mame.clear(); s_rtl.clear();
    }
    {
        unsigned left = 192, rem = 0;
        phase_ok = find_phase(c_first, left, rem);
        if (!phase_ok) fprintf(stderr, "release %llu: no ZSG-2 access before the next reset, sample checks off\n", (unsigned long long)releases);
        top->tb_ld = 1;
        top->tb_ld_left = left;
        top->tb_ld_rem = rem;
        top->zoom_reset = 0;
        int g = 0;
        // the time base stays loaded until the CPU leaves reset
        do { tick(); } while ((R->zoom_board__DOT__cpu_rst) && ++g < 5000);
        top->tb_ld = 0;
        held = false;
        seg_run = true;
        so_flush();
        first_land = -1;
        ticks_seg = 0;
        passes_seg = 0;
        syncs_seg = 0;
        s_mame.clear(); s_rtl.clear();
        for (auto &m : cmodels) m.inval();
        releases++;
    }
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) { fprintf(stderr, "usage: tb <flashdir> <trace> [max_insns] [report_every]\n"); return 2; }
    uint64_t maxn = argc > 3 ? strtoull(argv[3], 0, 0) : ~0ull;
    uint64_t every = argc > 4 ? strtoull(argv[4], 0, 0) : 10000000;
    if (!load_flash(argv[1])) return 2;
    tf = fopen(argv[2], "r");
    if (!tf) { perror(argv[2]); return 2; }

    mem_lat = 10;                             // clk_1x clocks per 64-bit line (SDRAM channel 3)
    if (getenv("ZB_LAT")) mem_lat = atoi(getenv("ZB_LAT"));
    if (getenv("ZB_JIT")) mem_jit = atoi(getenv("ZB_JIT"));
    if (getenv("ZB_OUTST")) mem_outst = atoi(getenv("ZB_OUTST"));
    pace = getenv("ZB_PACE") != nullptr;
    cap_credit = (getenv("ZB_CAP") ? atoi(getenv("ZB_CAP")) : ZB_CAP_DEFAULT) * 42336 * clk_h;
    if (getenv("ZB_LANDWIN")) sscanf(getenv("ZB_LANDWIN"), "%lld,%lld", (long long *)&win_lo, (long long *)&win_hi);
    bool strict = getenv("MN102_STRICT") != nullptr;
    for (unsigned s : {2048u, 4096u, 8192u, 16384u, 32768u})
        for (unsigned l : {8u, 16u, 32u}) cmodels.emplace_back(s, l, 1);
    cmodels.emplace_back(8192, 16, 2);
    cmodels.emplace_back(16384, 16, 2);

    top = new Vzoom_board;
    top->pace_en = pace;
    top->dbg_hold = 1;
    top->zoom_reset = 1;
    top->prog_inval = 0;
    top->tb_pin1_ovr = 1;
    top->tb_pin1 = 1;
    top->m_ready = 1;
    top->rst = 1; top->hrst = 1;
    for (int i = 0; i < 8; i++) tick();
    top->rst = 0; top->hrst = 0;
    for (int i = 0; i < 600; i++) tick();     // cache sweep at power-up

    TLine L, prev;
    std::vector<Ev> evs;
    std::deque<std::string> hist;
    if (!read_next(L, evs)) { fprintf(stderr, "empty trace\n"); return 2; }
    uint64_t k = 0, rtl_prev_cyc = 0, mulu_nf = 0;
    bool have_prev = false;
    while (k < maxn && !fail) {
        // finish the previous instruction (its accesses are checked on the way)
        settle();
        if (fail) break;
        if (!held && !busq.empty()) {
            BusRec &r = busq.front();
            snprintf(failmsg, sizeof failmsg, "bus: MAME %c %06x %04x %04x, the board made no such access", r.rw, r.addr, r.data, r.mask);
            fail = true;
            break;
        }
        uint64_t rel0 = releases;
        for (auto &e : evs) { apply_event(e, L.tc); if (fail) break; }
        evs.clear();
        if (fail) break;
        if (releases != rel0) { have_prev = false; dbq.clear(); }
        while (!dbq.empty() && seg_t0 + (i128)L.tc * 160000000000LL >= dbq.front().t) {
            host_access(dbq.front());
            dbq.pop_front();
            doorbells++;
            for (int i = 0; i < 8; i++) tick();       // synchroniser and the IRQ0 pulse
        }
        if (held) {
            snprintf(failmsg, sizeof failmsg, "MAME runs the MN10200 (pc %06x) while the board holds it in reset", L.pc);
            fail = true;
            break;
        }
        int g = 0;
        while (!top->dbg_bound && ++g < 200000 && !fail) tick();
        if (fail) break;
        if (g >= 200000) { snprintf(failmsg, sizeof failmsg, "core stuck before boundary"); fail = true; break; }
        unsigned p1 = (L.fc57 >> 5) & 1;
        if (R->zoom_board__DOT__tms_empty != p1) empty_diff++;
        if (top->tb_pin1 != p1) { top->tb_pin1 = p1; tick(); tick(); }   // pin, request latch, registered request (PIPE)
        top->dbg_hold = 0;
        g = 0;
        while (!top->dbg_insn && ++g < 200000 && !fail) tick();
        top->dbg_hold = 1;
        if (fail) break;
        if (g >= 200000) { snprintf(failmsg, sizeof failmsg, "core stuck after boundary"); fail = true; break; }
        uint32_t r[8];
        for (int i = 0; i < 8; i++) {
            const uint32_t *w = top->dbg_regs.data();
            int bit = i * 24;
            uint64_t lo = w[bit / 32] | (uint64_t)w[bit / 32 + 1 < 6 ? bit / 32 + 1 : 5] << 32;
            r[i] = (lo >> (bit % 32)) & 0xffffff;
        }
        uint64_t cyc = top->dbg_cycles;
        char why[256] = "";
        if (top->dbg_pc != L.pc) snprintf(why, sizeof why, "PC %06x vs MAME %06x", top->dbg_pc, L.pc);
        for (int i = 0; i < 4 && !why[0]; i++) {
            if (r[i] != L.d[i]) snprintf(why, sizeof why, "D%d %06x vs MAME %06x", i, r[i], L.d[i]);
            else if (r[4 + i] != L.a[i]) snprintf(why, sizeof why, "A%d %06x vs MAME %06x", i, r[4 + i], L.a[i]);
        }
        if (!why[0] && top->dbg_psw != L.psw) {
            if (!strict && have_prev && prev.dis.find(": mulu ") != std::string::npos &&
                (top->dbg_psw ^ L.psw) == 0x0002 && (top->dbg_psw & 0x0002)) {
                R->zoom_board__DOT__u_cpu__DOT__u_core__DOT__psw = L.psw;
                // an interrupt taken right after the MULU stacked the core's PSW
                if (L.pc == 0x080008 && L.a[3] >= 0x400000 && L.a[3] < 0x420000) {
                    // work RAM word holding the stacked PSW (byte at A3, low lane)
                    uint32_t wa = ((L.a[3] - 0x400000) >> 1) & 0x3fff;
                    auto &m = R->zoom_board__DOT__u_wram__DOT__mem[wa];
                    m &= ~0x0002u;
                }
                mulu_nf++;
            } else snprintf(why, sizeof why, "PSW %04x vs MAME %04x", top->dbg_psw, L.psw);
        }
        if (!why[0] && top->dbg_mdr != L.mdr) snprintf(why, sizeof why, "MDR %04x vs MAME %04x", top->dbg_mdr, L.mdr);
        if (!why[0] && have_prev && (cyc - rtl_prev_cyc) != (L.tc - prev.tc))
            snprintf(why, sizeof why, "cycles of previous instruction %llu vs MAME %llu",
                     (unsigned long long)(cyc - rtl_prev_cyc), (unsigned long long)(L.tc - prev.tc));
        if (!why[0] && rtl_icr(1) != (L.fc42 & 0xff)) snprintf(why, sizeof why, "FC42 %02x vs MAME %02x", rtl_icr(1), L.fc42);
        if (!why[0] && rtl_icr(8) != (L.fc50 & 0xff)) snprintf(why, sizeof why, "FC50 %02x vs MAME %02x", rtl_icr(8), L.fc50);
        char line[200];
        snprintf(line, sizeof line, "%10llu %06x %-28s", (unsigned long long)k, L.pc, L.dis.c_str());
        hist.push_back(line);
        if (hist.size() > 12) hist.pop_front();
        if (why[0]) { snprintf(failmsg, sizeof failmsg, "instruction %llu: %s", (unsigned long long)k, why); fail = true; break; }
        rtl_prev_cyc = cyc;
        prev = L;
        have_prev = true;
        k++;
        if (every && k % every == 0)
            fprintf(stderr, "%llu instructions, %llu samples equal, %.2f clocks/instruction, %llu cache misses\n",
                    (unsigned long long)k, (unsigned long long)s_cmp, (double)clocks / k, (unsigned long long)pc_misses);
        if (!read_next(L, evs)) break;
    }
    printf("instructions equal: %llu (%llu releases, %llu MULU NF accepted)\n",
           (unsigned long long)k, (unsigned long long)releases, (unsigned long long)mulu_nf);
    printf("trace lines: B %llu, H %llu, S %llu; doorbells timed %llu\n", (unsigned long long)n_b, (unsigned long long)n_h, (unsigned long long)n_s, (unsigned long long)doorbells);
    printf("external accesses equal: %llu (ZSG-2 reads %llu, mailbox reads %llu, TMS57002 writes %llu); ZSG-2 sample positions equal: %llu\n",
           (unsigned long long)chk_ext, (unsigned long long)rd_zsg, (unsigned long long)rd_mb, (unsigned long long)chk_tms,
           (unsigned long long)chk_zsg_t);
    printf("ZSG-2 output samples equal: %llu, different: %llu, unmatched at end: MAME %zu, board %zu; longest pass %llu clocks\n",
           (unsigned long long)(s_cmp - s_bad), (unsigned long long)s_bad, s_mame.size(), s_rtl.size(), (unsigned long long)max_pass);
    printf("clocks %llu, %.2f per instruction; program reads %llu, cache misses %llu (%.3f per 1000 instructions); memory lines %llu; ZSG-2 read wait clocks %llu\n",
           (unsigned long long)clocks, k ? (double)clocks / k : 0.0, (unsigned long long)prog_reads,
           (unsigned long long)pc_misses, k ? 1000.0 * pc_misses / k : 0.0, (unsigned long long)mem_lines, (unsigned long long)zrd_clocks);
    printf("cache models (size/line/ways: misses per 1000 instructions):");
    for (auto &m : cmodels) printf(" %u/%u/%u:%.3f", m.size, m.line, m.ways, k ? 1000.0 * m.miss / k : 0.0);
    printf("\n");
    so_flush();
    printf("TMS57002 SO1 against MAME (board sample k vs MAME k + d), equal / compared for d = -2..2:");
    for (int d = 0; d < 5; d++) printf(" %llu/%llu", (unsigned long long)so_hits[d], (unsigned long long)so_n[d]);
    printf("; MAME nonzero %llu; instruction starts where the board's EMPTY differs from MAME's IRQ1 pin: %llu\n",
           (unsigned long long)so_nonzero, (unsigned long long)empty_diff);
    printf("TMS57002 host bytes: %llu landings compared; board minus MAME in samples -3..3: %llu %llu %llu %llu %llu %llu %llu, further %llu; within one sample (384 slots) %llu; max %lld slots, mean %.1f slots\n",
           (unsigned long long)land_n, (unsigned long long)land_ds[0], (unsigned long long)land_ds[1], (unsigned long long)land_ds[2],
           (unsigned long long)land_ds[3], (unsigned long long)land_ds[4], (unsigned long long)land_ds[5], (unsigned long long)land_ds[6],
           (unsigned long long)land_far, (unsigned long long)land_in1, (long long)land_max, land_n ? (double)land_sum / land_n : 0.0);
    printf("TMS57002 CMEM updates: %llu applied; in MAME's sample %llu, MAME later %llu, MAME earlier %llu\n",
           (unsigned long long)ep_n, (unsigned long long)ep_same, (unsigned long long)ep_m_later, (unsigned long long)ep_m_earlier);
    printf("board flags %02x (arb_ovf sync_ovf zsg2_late zsg2_overrun wram_hi unmapped tms_rd out_under)\n", top->dbg_flags);
    printf("output stage: %llu real-time ticks while running, %llu with the FIFO empty (sample repeated), overflow flag %u\n",
           (unsigned long long)out_ticks, (unsigned long long)out_under, (unsigned)R->zoom_board__DOT__f_over);
    printf("virtual time: %llu machine cycles in %llu clocks while running = %.4f MHz at %.4f MHz (target 6.2500)\n",
           (unsigned long long)mc_steps, (unsigned long long)run_clocks, run_clocks ? 16.9344 * clk_h * mc_steps / run_clocks : 0.0,
           16.9344 * clk_h);
    if (pace) printf("pacer (cap %d cycles): clocks at the cap %llu (%.4f%%); max lag %d cycles; clocks with lag >= 16/32/64/128/256: %llu %llu %llu %llu %llu\n",
                     cap_credit / (42336 * clk_h), (unsigned long long)credit_cap_clocks, clocks ? 100.0 * credit_cap_clocks / clocks : 0.0, max_lag,
                     (unsigned long long)lag_hist[0], (unsigned long long)lag_hist[1], (unsigned long long)lag_hist[2],
                     (unsigned long long)lag_hist[3], (unsigned long long)lag_hist[4]);
    if (fail) {
        printf("FIRST DIVERGENCE: %s\n", failmsg);
        for (auto &h : hist) printf("  %s\n", h.c_str());
        printf("  MAME line: pc %06x d %06x %06x %06x %06x a %06x %06x %06x %06x psw %04x mdr %04x fc57 %02x fc50 %02x fc42 %02x\n",
               L.pc, L.d[0], L.d[1], L.d[2], L.d[3], L.a[0], L.a[1], L.a[2], L.a[3], L.psw, L.mdr, L.fc57, L.fc50, L.fc42);
        return 1;
    }
    return 0;
}
