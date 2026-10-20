// gnet_ddr3_flcopy testbench (docs/i12_ddr3_load.md 6.1): the DDR3 flash
// copier behind the flash mirror on gnet_ddr3_arb's glue port.
//
// Clocks: clk2x 67.74 MHz (half period 7381 ps), clk1x = clk2x / 2 with
// aligned rising edges (one PLL, as PSX.sv), clk_cpu 50 MHz unrelated.
// DDRAM port model: pipelined reads (several in flight, beats in order after
// lat + 0..jit clk2x, idle gaps between beats), single-beat writes with byte
// enables, BUSY random (busy %) plus a 200-cycle BUSY run every 5,000 cycles.
// Main's DDR3 load is modelled by writing the source bytes into the model's
// DDR3 at 0x31000000 (qword 0x6200000) before start. Channel 3 model: every
// copier write (w_req) is recorded, answered with w_done after 3 to 20 clk1x
// (2% of them 200 to 600, so the buffer fills and the room check is used),
// and handed to the mirror on clk_cpu while its stall is low, as
// zn2_ch3_arb would. Core client: random 1 to 4 beat reads elsewhere in the
// window, data checked. Per copy it checks: ceil(len/4) writes, in order, at
// 0x1000000 + 4k, each equal to DDR3 byte 0x31000000 + 4k (bytes past len
// are what DDR3 held there); none after busy falls; at the end DDR3's flash
// area still equals the source (the mirror wrote the same bytes back); no
// mirror or owner FIFO overflow; every core read right.
//
//   obj_flcopy/Vtb_flcopy_top <seed> <busy %> <lat> <jit> [len ...]
#include "Vtb_flcopy_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <random>
#include <vector>

static const uint32_t WBASE = 0x6000000, WQ = 0x400000;   // model window: qwords 0x6000000.. (32 MB)
static const uint32_t FLQ = 0x6200000;                     // byte 0x31000000

int main(int argc, char** argv) {
    unsigned seed = argc > 1 ? atoi(argv[1]) : 1;
    int busy_pct = argc > 2 ? atoi(argv[2]) : 20;
    int lat = argc > 3 ? atoi(argv[3]) : 14, jit = argc > 4 ? atoi(argv[4]) : 8;
    std::vector<uint32_t> lens;
    for (int i = 5; i < argc; i++) lens.push_back(strtoul(argv[i], nullptr, 0));
    if (lens.empty()) lens = {0x30000, 0x12345, 8, 5, 3, 0x40001};
    std::mt19937 rng(seed);
    std::vector<uint64_t> mem(WQ);
    for (auto& q : mem) q = ((uint64_t)rng() << 32) | rng();
    auto M = [&](uint32_t qa) -> uint64_t& { return mem[(qa - WBASE) % WQ]; };

    auto* t = new Vtb_flcopy_top;
    int errors = 0;
    auto err = [&](const char* m, long long c) { if (errors++ < 12) printf("ERROR at clk2x %lld: %s\n", c, m); };
    t->clk1x = t->clk2x = t->clk_cpu = 0; t->rst = 1; t->start = 0; t->w_done = 0; t->m_req = 0; t->c_rd = 0;
    t->ddr_busy = 0; t->ddr_dout_ready = 0; t->eval();

    // DDR model
    struct Rd { uint32_t a; int n; long long ready; };
    std::deque<Rd> rds;
    // channel 3 model
    struct Wr { uint32_t a; uint32_t d; };
    std::vector<Wr> writes;
    std::deque<Wr> mq;
    int done_wait = -1, done_hold = 0; bool done_pending = false;
    // core client
    struct Cr { uint32_t a; int n; };
    std::deque<Cr> cexp; bool c_hold = false; long long c_beats = 0;
    // jobs
    size_t job = 0; long long job_start = 0; bool started = false; std::vector<uint8_t> snap;
    int gapc = 0, mgap = 0;
    long long cyc2 = 0;
    long long tick = 0, tcpu = 10000; const long long H2 = 7381;
    long long busy_run = 0;
    long long total_writes = 0;
    long long quiet = 0, idle1 = 0;
    while (job < lens.size() || started || quiet < 20000) {
        long long t2 = tick * H2;
        bool cpu_first = tcpu < t2;
        if (cpu_first) {
            // clk_cpu edge
            bool rise = !t->clk_cpu;
            bool stall = t->m_stall;
            t->clk_cpu = rise; t->eval();
            if (rise) {
                t->m_req = 0;
                if (mgap) mgap--;
                else if (!mq.empty() && !stall) {
                    t->m_req = 1; t->m_addr = mq.front().a; t->m_din = mq.front().d; mq.pop_front(); mgap = 1;
                }
                t->eval();
            }
            tcpu += 10000;
            continue;
        }
        // clk2x edge (and clk1x on every second rising edge)
        tick++;
        bool r2 = !t->clk2x;
        bool r1 = r2 && ((cyc2 & 1) == 0);
        bool f1 = r2 && ((cyc2 & 1) == 1);
        // pre-edge samples
        t->eval();
        bool p_ddr_rd = t->ddr_rd, p_ddr_we = t->ddr_we; uint32_t p_addr = t->ddr_addr; int p_bc = t->ddr_burstcnt;
        uint64_t p_din = t->ddr_din; uint8_t p_be = t->ddr_be; bool p_busy = t->ddr_busy;
        bool p_c_busy = t->c_busy, p_cdr = t->c_dout_ready; uint64_t p_rdata = t->rdata;
        bool p_wreq = t->w_req; uint32_t p_waddr = t->w_addr, p_wdata = t->w_data; bool p_fbusy = t->busy;
        t->clk2x = r2;
        if (r1) t->clk1x = 1;
        if (f1) t->clk1x = 0;
        t->eval();
        if (!r2) continue;
        cyc2++;
        if (cyc2 == 20) { t->rst = 0; }
        if (getenv("FLC_DBG") && cyc2 % 20000 == 0) printf("dbg %lld job %zu started %d busy %d writes %zu mq %zu rds %zu idle1 %lld quiet %lld\n", cyc2, job, started, (int)t->busy, writes.size(), mq.size(), rds.size(), idle1, quiet);
        quiet = (!started && mq.empty() && job >= lens.size()) ? quiet + 1 : 0;
        // DDR model at the clk2x edge
        if (!p_busy && (p_ddr_rd || p_ddr_we)) {
            if (p_ddr_rd) rds.push_back({p_addr, p_bc, cyc2 + lat + (jit ? (long long)(rng() % (jit + 1)) : 0)});
            else {
                uint64_t& q = M(p_addr);
                for (int b = 0; b < 8; b++) if (p_be & (1 << b)) q = (q & ~(0xFFULL << (8 * b))) | (p_din & (0xFFULL << (8 * b)));
            }
        }
        t->ddr_dout_ready = 0;
        if (!rds.empty() && rds.front().ready <= cyc2 && rng() % 100 >= 10) {
            Rd& r = rds.front();
            t->ddr_dout = M(r.a); t->ddr_dout_ready = 1;
            r.a++; if (--r.n == 0) rds.pop_front();
        }
        if (busy_run) { busy_run--; t->ddr_busy = 1; }
        else if (cyc2 % 5000 == 0) { busy_run = 200; t->ddr_busy = 1; }
        else t->ddr_busy = (int)(rng() % 100) < busy_pct;
        // core client
        if (p_cdr) {
            if (cexp.empty()) err("core beat without a read", cyc2);
            else {
                if (p_rdata != M(cexp.front().a)) err("core read data", cyc2);
                cexp.front().a++; c_beats++;
                if (--cexp.front().n == 0) cexp.pop_front();
            }
        }
        if (c_hold) {
            if (!p_c_busy) { cexp.push_back({(uint32_t)t->c_addr, (int)t->c_burstcnt}); c_hold = false; t->c_rd = 0; }
        }
        if (!c_hold && job < lens.size() && rng() % 100 < 3) {
            t->c_rd = 1; t->c_addr = WBASE + rng() % 0x100000; t->c_burstcnt = 1 + rng() % 4; c_hold = true;
        }
        // clk1x side: channel 3 model and job control
        if (r1) {
            if (p_wreq) {
                if (!started) err("write while no copy runs", cyc2);
                writes.push_back({p_waddr, p_wdata}); mq.push_back({p_waddr, p_wdata}); total_writes++;
                if (done_pending) err("second write before done", cyc2);
                done_pending = true;
                done_wait = (rng() % 100 < 2) ? 200 + rng() % 400 : 3 + rng() % 18;
            }
            t->w_done = 0;
            if (done_pending && --done_wait <= 0) { t->w_done = 1; done_pending = false; }
            t->start = 0;
            idle1 = mq.empty() ? idle1 + 1 : 0;
            if (!started && job < lens.size() && cyc2 > 200 && idle1 > 3000) {
                uint32_t len = lens[job];
                // Main's memcpy of len source bytes to DDR3 0x31000000
                for (uint32_t i = 0; i < len; i++) {
                    uint64_t& q = M(FLQ + i / 8); int b = i % 8;
                    q = (q & ~(0xFFULL << (8 * b))) | ((uint64_t)(rng() & 0xFF) << (8 * b));
                }
                snap.resize(((len + 7) & ~7u) + 8);
                for (uint32_t i = 0; i < snap.size(); i++) snap[i] = (M(FLQ + i / 8) >> (8 * (i % 8))) & 0xFF;
                writes.clear();
                t->start = 1; t->len = len; started = true; job_start = cyc2;
            } else if (started && !p_fbusy && cyc2 > job_start + 8 && !done_pending) {
                uint32_t len = lens[job];
                uint32_t nw = (len + 3) / 4;
                if (len > 0xA00000) nw = 0x280000;
                if (writes.size() != nw) { char m[96]; snprintf(m, sizeof m, "copy of %u bytes: %zu writes, expected %u", len, writes.size(), nw); err(m, cyc2); }
                for (size_t k = 0; k < writes.size() && k < nw; k++) {
                    uint32_t e; memcpy(&e, &snap[4 * k], 4);
                    if (writes[k].a != 0x1000000 + 4 * k || writes[k].d != e) {
                        char m[128]; snprintf(m, sizeof m, "write %zu: %07X %08X, expected %07X %08X", k, writes[k].a, writes[k].d, (unsigned)(0x1000000 + 4 * k), e);
                        err(m, cyc2); break;
                    }
                }
                printf("copy %zu: %u bytes, %zu writes in %lld clk1x (%.2f clk1x per write)\n", job, len, writes.size(),
                       (cyc2 - job_start) / 2, writes.empty() ? 0.0 : (cyc2 - job_start) / 2.0 / writes.size());
                started = false; job++;
            } else if (started && cyc2 - job_start > 2LL * (700LL * ((lens[job] + 3) / 4) + 200000)) {
                err("copy timed out", cyc2); started = false; job++;
            }
        }
        t->eval();
    }
    if (!lens.empty()) {
        uint32_t len = lens.back(); size_t bad = 0;
        for (uint32_t i = 0; i < len; i++) if (((M(FLQ + i / 8) >> (8 * (i % 8))) & 0xFF) != snap[i]) bad++;
        if (bad) { char m[80]; snprintf(m, sizeof m, "DDR3 flash area: %zu bytes changed by the mirror write-back", bad); err(m, cyc2); }
    }
    if (t->mir_ovf) err("mirror FIFO overflow", cyc2);
    if (t->own_ovf) err("arbiter owner FIFO overflow", cyc2);
    printf("seed %u busy %d%% lat %d+%d: %zu copies, %lld channel 3 writes, %lld core beats checked, %d errors: %s\n",
           seed, busy_pct, lat, jit, lens.size(), total_writes, c_beats, errors, errors ? "FAIL" : "pass");
    delete t;
    return errors ? 1 : 0;
}
