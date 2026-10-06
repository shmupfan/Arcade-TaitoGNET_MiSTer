// Zoom flash reads through the DDR3 path of GNET_Z1FULL (zd3_top.sv):
// zoom_board -> gnet_ddr3_zport -> gnet_ddr3_arb -> DDRAM port model, the
// flash area put into DDR3 by gnet_ddr3_mirror from a channel 3 write
// stream of the flash image (clk_cpu, 50 MHz, unrelated).
//
//   tb_zd3 <flashdir> <hev.log> <outdir> [key=value ...]
//     busy=<%>    random DDRAM BUSY (default 10), plus a 20-cycle run every 3,000
//     lat=<n> jit=<n>   read latency base and jitter in clk_2x (default 14, 8)
//     core=<0|1>  background core traffic on the C port (default 1)
//     seed=<n>
//     wgap=<n>    channel 3 writes 1 to n clk_cpu apart (default 4)
//   Run from the repository root (the MN10200 decode ROMs are rtl/zoom/*.hex);
//   build with sim/zoomddr3/build.sh (env ZSG_INFL, default 8), compare runs
//   with sim/zoomddr3/cmp_runs.py. docs/zoom_board_design.md 14.12.
//     hold=<c1> holdlen=<c1>   zoom_hold from replay clk_1x cycle c1 for
//                 holdlen cycles; host events at or after c1 are delayed by
//                 holdlen (the main CPU is paused too)
//
// Phases: (1) zoom_board and zport in reset (p_rst), zoom_reset 1; every
// 32-bit word of the flash area (0x1000000-0x19FFFFF) written on the
// channel 3 stream (1 to 4 clk_cpu apart, held off by stall), then the DDR3
// model's copy compared with the image. (2) hev.log replayed from the next
// clk_1x cycle as tb_zoomref does: R (reset), Z (zoom_reset) and H (host
// requests) at their logged cycles.
// Checks: every m_rvalid answers the oldest open line with the image's data;
// none without an open line, none in reset; Avalon stability downstream;
// own_ovf, rot_ovf, mirror ovf; board flags except under; the mirror copy.
// Writes insn.bin (as tb_zoomlink), mbx.log (MN10200 mailbox accesses and
// host acks in order, as the scratch tb_zoomlink) and prints a summary.
#include "Vzd3_top.h"
#include "Vzd3_top___024root.h"
#include "verilated.h"
#include <deque>
#include <map>
#include <random>
#include <unordered_map>

static Vzd3_top *top;
static Vzd3_top___024root *R;
#define ZB(x) R->zd3_top__DOT__zb__DOT__##x
#include "../zoomlink/zl_common.h"

static const uint64_t H2 = 7382, H1 = 14764, HC = 10000, OFFC = 3000;
static uint64_t now = 0, c1 = 0, c2 = 0, cc = 0, errors = 0;
#define ERR(...) do { if (errors++ < 40) { fprintf(stderr, "ERROR at %.3f us (c1 %llu): ", now / 1e6, (unsigned long long)c1); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

static uint64_t hash64(uint64_t x) { x ^= x >> 33; x *= 0xff51afd7ed558ccdULL; x ^= x >> 33; x *= 0xc4ceb9fe1a85ec53ULL; x ^= x >> 33; return x; }
struct Mem {
    std::unordered_map<uint32_t, uint64_t> m;
    uint64_t rd(uint32_t a) const { auto it = m.find(a); return it == m.end() ? hash64(a) : it->second; }
    void wr(uint32_t a, uint64_t d, uint8_t be) {
        uint64_t v = rd(a);
        for (int b = 0; b < 8; b++) if (be >> b & 1) v = (v & ~(0xFFULL << (8 * b))) | (d & (0xFFULL << (8 * b)));
        m[a] = v;
    }
};

struct Ev { uint64_t c1; char k; unsigned v, we, be; uint32_t a, d; };

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 4) { fprintf(stderr, "usage: tb_zd3 <flashdir> <hev.log> <outdir> [key=value ...]\n"); return 2; }
    std::map<std::string, long> kv = {{"busy", 10}, {"lat", 14}, {"jit", 8}, {"core", 1}, {"seed", 1}, {"hold", -1}, {"holdlen", 0}, {"wgap", 4}};
    for (int i = 4; i < argc; i++) {
        std::string s = argv[i];
        auto e = s.find('=');
        if (e == std::string::npos || !kv.count(s.substr(0, e))) { fprintf(stderr, "bad argument %s\n", argv[i]); return 2; }
        kv[s.substr(0, e)] = atol(s.c_str() + e + 1);
    }
    const int busy_pct = kv["busy"], lat_base = kv["lat"], lat_jit = kv["jit"];
    const bool core_on = kv["core"];
    const long hold_at = kv["hold"], hold_len = kv["holdlen"];
    std::mt19937 rng(kv["seed"]);
    if (!load_flash(argv[1])) return 2;

    std::deque<Ev> evs;
    uint64_t end_c1 = 0;
    {
        FILE *h = fopen(argv[2], "r");
        if (!h) { perror(argv[2]); return 2; }
        char ln[256];
        while (fgets(ln, sizeof ln, h)) {
            Ev e{};
            unsigned long long c;
            char k;
            if (sscanf(ln, "%llu %c", &c, &k) != 2) continue;
            e.c1 = c; e.k = k;
            if (k == 'H') sscanf(ln, "%*llu %*c %u %x %x %x", &e.we, &e.a, &e.be, &e.d);
            else if (k == 'Z' || k == 'R') sscanf(ln, "%*llu %*c %u", &e.v);
            else if (k == 'E') { end_c1 = c; continue; }
            if (hold_at >= 0 && (long)e.c1 >= hold_at) e.c1 += hold_len;
            evs.push_back(e);
        }
        fclose(h);
        if (hold_at >= 0) end_c1 += hold_len;
    }
    std::string od = argv[3];
    FILE *ins = fopen((od + "/insn.bin").c_str(), "wb");
    FILE *mbx = fopen((od + "/mbx.log").c_str(), "w");
    FILE *aud = fopen((od + "/aud.bin").c_str(), "wb");   // SO1 pair at every output FIFO push
    if (!ins || !mbx) { perror(argv[3]); return 2; }

    top = new Vzd3_top;
    R = top->rootp;
    top->p_rst = 1; top->arb_rst = 1; top->zoom_reset = 1; top->zoom_hold = 0;
    top->clk1x = 0; top->clk2x = 0; top->clk_cpu = 0;
    top->eval();

    Mem mem;
    // DDRAM port model state
    struct Rd { uint32_t a; int len, beat; long first; };
    std::deque<Rd> q;
    long last_beat = -1;
    int wb_left = 0; uint32_t wb_addr = 0;
    bool p_cmd = false, p_busy = false, p_rd = false; uint32_t p_addr = 0; int p_bc = 0; uint64_t p_din = 0; int p_be = 0;
    uint64_t ddr_reads = 0, ddr_writes = 0;
    // core client
    enum { CI, CRD, CWR } c_st = CI;
    uint32_t c_a = 0; int c_len = 0, c_got = 0; std::unordered_map<uint32_t, uint64_t> c_shadow;
    uint64_t c_reads = 0;
    // channel 3 stream
    const uint32_t FA_LO = 0x1000000, FA_HI = 0x1A00000;
    uint32_t w_next = FA_LO; int w_gap = 0; uint64_t w_sent = 0, w_stall_cycles = 0;
    bool fill_done = false; uint64_t fill_end_c1 = 0, fill_end_ns = 0, drain_wait = 0;
    uint64_t base_c1 = 0;                   // replay cycle 0
    bool replay = false;
    // Zoom lines
    std::deque<uint32_t> open_lines;
    uint64_t lines = 0, z_acc_n = 0, stray = 0, lat_sum = 0, lat_max = 0, wave_lines = 0, wave_lat_max = 0, first_wave_c1 = 0;
    std::deque<uint64_t> open_t;
    // observation
    uint64_t insns = 0, mn_mb = 0, acks = 0, aud_nz = 0;
    // hold observation
    long hold_c1 = -1;                      // bench c1 of hold start
    uint64_t insn_after_hold = 0, last_insn_c2_after_hold = 0, ticks_in_hold = 0, syncs_in_hold = 0, pushes_in_hold = 0,
             not_bound_in_hold = 0, bus_in_hold = 0, mc_in_hold = 0, lines_in_hold = 0;
    uint64_t hold_c2_start = 0, hold_c2_end = 0;
    std::map<uint32_t, uint64_t> hold_bus;   // bus address (bit 31 write, bit 30 ack) while settled in the hold
    int32_t credit_at_end = 0;
    // virtual time (machine cycles stepped) per window, sample ticks, out level
    uint64_t mc_total = 0, ticks_total = 0;
    std::vector<std::pair<uint64_t, uint64_t>> win;    // per 1 ms of replay time: (mc, ticks)
    uint64_t win_mc = 0, win_ticks = 0, win_start = 0;
    unsigned lvl_min_after = 99; uint64_t under_events_before = 0, under_events_after = 0, under_events_hold = 0;
    bool hold_on = false, hold_done = false;

    uint64_t n2 = 0, n1 = 0, nc = OFFC;
    bool l2 = false, l1 = false, lc = false;
    for (;;) {
        uint64_t t = std::min(n2, std::min(n1, nc));
        now = t;
        bool r2 = (t == n2 && !l2), r1 = (t == n1 && !l1), rc = (t == nc && !lc);
        // ------------------------------------------------ pre-edge samples
        bool z_acc = false, z_rv = false; uint32_t acc_line = 0; uint64_t rv_data = 0;
        if (r1) {
            z_acc = !top->p_rst && top->m_req && top->m_ready; acc_line = top->m_line;
            z_rv = top->m_rvalid; rv_data = top->m_rdata;
            if (ZB(h_ack)) { fprintf(mbx, "A %08x\n", ZB(h_rdata)); acks++; }
            if (top->aud_l || top->aud_r) aud_nz++;
            if (top->aud_tick && ZB(u_out__DOT__started)) {
                bool und = ZB(out_level) == 0;
                if (hold_c1 < 0) under_events_before += und;
                else if (hold_on) under_events_hold += und;
                else { under_events_after += und; lvl_min_after = std::min<unsigned>(lvl_min_after, ZB(out_level)); }
            }
        }
        bool d_cmd = false, d_busy = false, d_beat = false; uint64_t d_data = 0;
        bool c_dr = false, c_acc = false;
        if (r2) {
            if (top->dbg_insn) {
                Insn r;
                r.pc = top->dbg_pc; r.psw = top->dbg_psw; r.mdr = top->dbg_mdr;
                for (int i = 0; i < 6; i++) r.regs[i] = top->dbg_regs[i];
                fwrite(&r, sizeof r, 1, ins);
                insns++;
                if (hold_on) { insn_after_hold++; last_insn_c2_after_hold = c2 - hold_c2_start; }
            }
            uint32_t a = ZB(bus_addr);
            if ((a & 0xFFFF00) == 0xE00000) {
                if (ZB(mbz_we)) { fprintf(mbx, "M W %06x %x %04x\n", a & 0xfffffe, ZB(bus_be), ZB(bus_wdata)); mn_mb++; }
                if (ZB(bus_rd) && ZB(bus_ack)) { fprintf(mbx, "M R %06x %x %04x\n", a & 0xfffffe, ZB(bus_be), ZB(bus_rdata)); mn_mb++; }
            }
            if (ZB(mc_step)) { mc_total++; win_mc++; }
            if (hold_on && c2 - hold_c2_start > 400) {
                // settled: no instruction, no machine cycle, at the boundary
                if (!top->dbg_bound) not_bound_in_hold++;
                if (ZB(mc_step)) mc_in_hold++;
                if (ZB(bus_rd) || ZB(bus_wr)) {
                    bus_in_hold++;
                    hold_bus[{(uint32_t)ZB(bus_addr) | (ZB(bus_wr) ? 0x80000000u : 0) | (ZB(bus_ack) ? 0x40000000u : 0)}]++;
                }
                if (ZB(sample_tick)) ticks_in_hold++;
            }
            if (replay && ZB(sample_tick)) { ticks_total++; win_ticks++; }
            d_cmd = top->ddr_rd || top->ddr_we; d_busy = top->ddr_busy;
            d_beat = top->ddr_dout_ready; d_data = top->ddr_dout;
            c_dr = top->c_dout_ready; c_acc = (top->c_rd || top->c_we) && !top->c_busy;
            if (top->own_ovf) ERR("owner FIFO overflow");
            // Avalon stability
            if (p_cmd && p_busy) {
                if (!d_cmd || top->ddr_rd != p_rd || top->ddr_addr != p_addr || top->ddr_burstcnt != p_bc ||
                    (!p_rd && (top->ddr_din != p_din || top->ddr_be != p_be))) ERR("downstream command changed while BUSY");
            }
            p_cmd = d_cmd; p_busy = d_busy; p_rd = top->ddr_rd; p_addr = top->ddr_addr; p_bc = top->ddr_burstcnt; p_din = top->ddr_din; p_be = top->ddr_be;
            if (d_cmd && !d_busy) {
                if (top->ddr_rd) {
                    if (wb_left) ERR("read inside a write burst");
                    int L = lat_base + (int)(rng() % (lat_jit + 1));
                    q.push_back({(uint32_t)top->ddr_addr, top->ddr_burstcnt, 0, (long)c2 + L});
                    ddr_reads++;
                } else {
                    uint32_t a2;
                    if (wb_left) { a2 = ++wb_addr; wb_left--; }
                    else { a2 = top->ddr_addr; if (top->ddr_burstcnt > 1) { wb_left = top->ddr_burstcnt - 1; wb_addr = a2; } }
                    mem.wr(a2, top->ddr_din, top->ddr_be);
                    ddr_writes++;
                }
            }
            if (d_beat) { Rd &h = q.front(); if (++h.beat == h.len) q.pop_front(); last_beat = c2; }
        }
        bool w_stall = rc ? (bool)top->stall : false;
        bool tms_sync = r1 ? (bool)ZB(tms_sync) : false;
        bool push = r1 ? (bool)ZB(sync_q) : false;
        if (push) { uint16_t pa[2] = {(uint16_t)ZB(so_l16), (uint16_t)ZB(so_r16)}; fwrite(pa, 2, 2, aud); }
        if (r1 && hold_on && c1 - hold_c1 > 200) { syncs_in_hold += tms_sync; pushes_in_hold += push; }
        if (r1 && z_rv) {
            if (top->p_rst) ERR("m_rvalid in reset");
            if (open_lines.empty()) { stray++; ERR("m_rvalid with no open line"); }
            else {
                uint32_t b = (open_lines.front() << 3) & 0xffffff;
                uint64_t v = 0;
                for (int i = 7; i >= 0; i--) v = v << 8 | fa[b + i];
                if (rv_data != v) ERR("line %06x: %016llx, image %016llx", open_lines.front(), (unsigned long long)rv_data, (unsigned long long)v);
                uint64_t l = c1 - open_t.front();
                lat_sum += l; lat_max = std::max(lat_max, l);
                if (open_lines.front() >= 0x80000) {      // WAVE_BASE 0x400000 / 8: a ZSG-2 wave read
                    wave_lines++; wave_lat_max = std::max(wave_lat_max, l);
                    if (!first_wave_c1) first_wave_c1 = c1 - base_c1;
                }
                open_lines.pop_front(); open_t.pop_front();
                lines++;
                if (hold_on) lines_in_hold++;
            }
        }
        if (r1 && z_acc) { open_lines.push_back(acc_line); open_t.push_back(c1); z_acc_n++; }

        // ------------------------------------------------ clock edges
        if (t == n2) { l2 = !l2; top->clk2x = l2; n2 += H2; }
        if (t == n1) { l1 = !l1; top->clk1x = l1; n1 += H1; }
        if (t == nc) { lc = !lc; top->clk_cpu = lc; nc += HC; }
        top->eval();

        // ------------------------------------------------ post-edge inputs
        if (r2) {
            c2++;
            if (c2 == 20) top->arb_rst = 0;
            // core client
            if (c_dr) {
                if (++c_got == c_len) { c_st = CI; c_reads++; }
            }
            if (c_acc) { if (c_st == CWR) c_st = CI; top->c_rd = 0; top->c_we = 0; }
            if (core_on && c_st == CI && !top->c_rd && !top->c_we && c2 > 30) {
                int r = rng() % 100;
                if (r < 30) {
                    static const int lens[4] = {1, 4, 80, 128};
                    c_len = lens[rng() % 4]; c_got = 0;
                    c_a = 0x6000000 + ((rng() % 0x40000) & ~127u);
                    top->c_rd = 1; top->c_addr = c_a; top->c_burstcnt = c_len; c_st = CRD;
                } else if (r < 60) {
                    uint32_t a2 = 0x6000000 + (rng() % 0x40000);
                    uint64_t d = ((uint64_t)rng() << 32) | rng();
                    c_shadow[a2] = d;
                    top->c_we = 1; top->c_addr = a2; top->c_din = d; top->c_be = 0xFF; top->c_burstcnt = 1; c_st = CWR;
                }
            }
            // port outputs for the next cycle
            top->ddr_busy = (int)(rng() % 100) < busy_pct || (c2 % 3000) < 20;
            bool rdy = false;
            if (!q.empty()) {
                Rd &h = q.front();
                long e = std::max(h.first, h.beat == 0 ? last_beat + 1 : 0L);
                if (h.beat > 0) e = last_beat + 1;
                if (e <= (long)c2) { rdy = true; top->ddr_dout = mem.rd(h.a + h.beat); }
            }
            top->ddr_dout_ready = rdy;
        }
        if (rc) {
            cc++;
            top->w_req = 0;
            if (!fill_done && cc > 50) {
                if (w_stall) w_stall_cycles++;
                if (w_gap > 0) w_gap--;
                else if (!w_stall && w_next < FA_HI) {
                    uint32_t o = w_next - FA_LO, v = 0;
                    for (int i = 3; i >= 0; i--) v = v << 8 | fa[o + i];
                    top->w_req = 1; top->w_addr = w_next; top->w_din = v; top->w_be = 0xF;
                    w_next += 4; w_sent++;
                    w_gap = rng() % kv["wgap"];
                }
            }
        }
        if (r1) {
            c1++;
            if (!fill_done && w_next >= FA_HI) {
                // wait for the mirror and arbiter to drain, then compare
                if (++drain_wait == 2000) {
                    uint64_t bad = 0;
                    for (uint32_t o = 0; o < FA_HI - FA_LO; o += 8) {
                        uint64_t v = 0;
                        for (int i = 7; i >= 0; i--) v = v << 8 | fa[o + i];
                        if (mem.rd(0x6200000 + o / 8) != v) { if (bad++ < 5) ERR("DDR3 copy at offset %06x differs", o); }
                    }
                    fill_done = true; fill_end_c1 = c1; fill_end_ns = now / 1000;
                    base_c1 = c1; replay = true;
                    printf("fill: %llu channel 3 writes in %.3f ms, %llu clk_cpu cycles with stall, %llu DDR3 writes; DDR3 copy of 0x%x bytes: %llu qwords differ\n",
                           (unsigned long long)w_sent, now / 1e9, (unsigned long long)w_stall_cycles, (unsigned long long)ddr_writes,
                           FA_HI - FA_LO, (unsigned long long)bad);
                    fflush(stdout);
                }
            }
            if (replay) {
                uint64_t rc1 = c1 - base_c1;
                // hold window (replay cycles)
                if (hold_at >= 0 && !hold_on && !hold_done && (long)rc1 == hold_at) {
                    hold_on = true; hold_c1 = c1; hold_c2_start = c2; top->zoom_hold = 1;
                }
                if (hold_on && (long)rc1 == hold_at + hold_len) {
                    hold_on = false; hold_done = true; hold_c2_end = c2; top->zoom_hold = 0;
                    credit_at_end = (int32_t)ZB(u_cpu__DOT__credit);
                }
                if (rc1 - win_start >= 33869) {          // 1 ms windows
                    win.push_back({win_mc, win_ticks}); win_mc = 0; win_ticks = 0; win_start = rc1;
                }
                top->h_req = 0;
                while (!evs.empty() && evs.front().c1 <= rc1) {
                    Ev e = evs.front(); evs.pop_front();
                    if (e.k == 'R') {
                        top->p_rst = e.v;
                        if (e.v) { open_lines.clear(); open_t.clear(); }
                    }
                    if (e.k == 'Z') top->zoom_reset = e.v;
                    if (e.k == 'H') { top->h_req = 1; top->h_we = e.we; top->h_addr = e.a; top->h_be = e.be; top->h_wdata = e.d; }
                }
                if (rc1 >= end_c1) break;
            }
        }
        if (r1 || r2 || rc) top->eval();
        if (errors > 100) break;
    }
    fclose(ins); fclose(mbx); fclose(aud);
    printf("tb_zd3: %.3f ms simulated (replay %.3f ms), busy %d%%, latency %d+%d, core traffic %d\n", now / 1e9,
           (now / 1e3 - fill_end_ns) / 1e6, busy_pct, lat_base, lat_jit, (int)core_on);
    printf("zoom: %llu instructions, %llu lines (%llu accepted), latency mean %.1f max %llu clk_1x, stray rvalid %llu, mailbox: %llu MN10200 accesses, %llu host acks\n",
           (unsigned long long)insns, (unsigned long long)lines, (unsigned long long)z_acc_n, lines ? (double)lat_sum / lines : 0.0,
           (unsigned long long)lat_max, (unsigned long long)stray, (unsigned long long)mn_mb, (unsigned long long)acks);
    printf("zoom: wave lines (ZSG-2) %llu, latency max %llu clk_1x, first at replay cycle %llu (%.3f s)\n",
           (unsigned long long)wave_lines, (unsigned long long)wave_lat_max, (unsigned long long)first_wave_c1, first_wave_c1 / 33868800.0);
    printf("ddr3: %llu reads, %llu writes; core reads %llu; flags %02x, mirror ovf %d, rot_ovf %d, own_ovf %d, audio non-zero cycles %llu\n",
           (unsigned long long)ddr_reads, (unsigned long long)ddr_writes, (unsigned long long)c_reads, top->flags, top->mir_ovf,
           top->rot_ovf, top->own_ovf, (unsigned long long)aud_nz);
    if (hold_at >= 0) {
        printf("hold: %ld clk_1x (%.1f ms) from replay cycle %ld; instructions retired after the hold rose %llu (last at clk_2x %llu after), "
               "settled: not at boundary %llu, machine cycles %llu, bus cycles %llu, sample ticks %llu, TMS SYNC %llu, output pushes %llu, lines %llu\n",
               hold_len, hold_len / 33868.8, hold_at, (unsigned long long)insn_after_hold, (unsigned long long)last_insn_c2_after_hold,
               (unsigned long long)not_bound_in_hold, (unsigned long long)mc_in_hold, (unsigned long long)bus_in_hold,
               (unsigned long long)ticks_in_hold, (unsigned long long)syncs_in_hold, (unsigned long long)pushes_in_hold,
               (unsigned long long)lines_in_hold);
        for (auto &x : hold_bus)
            printf("  hold bus: %s %06x%s x%llu\n", x.first >> 31 ? "W" : "R", x.first & 0xffffff, (x.first >> 30 & 1) ? " ack" : "", (unsigned long long)x.second);
        printf("hold: pacer credit at release %d (cap %d); output underrun ticks: before %llu, during %llu, after %llu; lowest output FIFO level after %u\n",
               credit_at_end, 1024 * 42336 * 4, (unsigned long long)under_events_before, (unsigned long long)under_events_hold,
               (unsigned long long)under_events_after, lvl_min_after);
        // machine cycles and sample ticks per 1 ms window around the hold
        long hw = hold_at / 33869, he = (hold_at + hold_len) / 33869;
        for (long i = std::max(0L, hw - 2); i < (long)win.size() && i <= he + 6; i++)
            if (i <= hw + 1 || i >= he - 1)
                printf("  window %ld ms: machine cycles %llu, sample ticks %llu\n", i, (unsigned long long)win[i].first, (unsigned long long)win[i].second);
    }
    if (top->own_ovf) ERR("own_ovf");
    if (top->mir_ovf) ERR("mirror ovf");
    if (top->flags & 0xfe) ERR("board flags %02x", top->flags);
    printf("RESULT tb_zd3 errors %llu\n", (unsigned long long)errors);
    delete top;
    return errors ? 1 : 0;
}
