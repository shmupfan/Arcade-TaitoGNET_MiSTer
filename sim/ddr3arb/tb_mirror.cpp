// gnet_ddr3_mirror testbench: channel 3 writes on clk_cpu (50 MHz) mirrored
// to an Avalon port on clk_2x (67.7376 MHz), unrelated clocks.
//
// Source: one-cycle write requests at most every 2 clk_cpu cycles, only while
// stall is low (as zn2_ch3_arb does with its stall input), 70% inside the
// flash area 0x1000000-0x19FFFFF, the rest outside (BIOS, main RAM, just past
// the end). Port: BUSY random (busy %) plus 300-cycle BUSY runs. Checks: every
// write inside the area arrives once, in order, as qword 0x6000000 + addr/8
// with the 32-bit word and its enables in the half given by address bit 2;
// nothing outside the area arrives; no overflow. Mode "nostall" ignores stall
// and must set ovf.
//
//   obj_mirror/Vgnet_ddr3_mirror <seed> <ns> <busy %> [nostall]
#include "Vgnet_ddr3_mirror.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <random>
#include <string>

struct W { uint32_t qaddr; uint64_t din; uint8_t be; };

int main(int argc, char** argv) {
    unsigned seed = argc > 1 ? atoi(argv[1]) : 1;
    long ns_end = argc > 2 ? atol(argv[2]) : 20000000;
    int busy_pct = argc > 3 ? atoi(argv[3]) : 30;
    bool nostall = argc > 4 && std::string(argv[4]) == "nostall";
    std::mt19937 rng(seed);
    auto* t = new Vgnet_ddr3_mirror;
    int errors = 0;
    auto err = [&](const char* m, long n) { if (errors++ < 10) printf("ERROR at %ld ns: %s\n", n, m); };
    std::deque<W> expect;
    long sent_in = 0, sent_out = 0, got = 0, stalled = 0;
    int gap = 0, busy_run = 0;
    t->clk_src = 0; t->clk2x = 0; t->w_req = 0; t->g_busy = 1; t->eval();
    // times in ps
    long long ts = 10000, t2 = 7381, now = 0;
    while (now < ns_end * 1000LL) {
        if (ts <= t2) {
            now = ts; ts += 10000;
            t->clk_src = !t->clk_src;
            t->eval();
            if (t->clk_src) {
                // after the rising edge: next request
                t->w_req = 0;
                if (gap) gap--;
                else if (!t->stall || nostall) {
                    if (rng() % 2) {
                        uint32_t a;
                        bool in = rng() % 10 < 7;
                        if (in) a = 0x1000000 + (rng() % 0xA00000);
                        else {
                            static const uint32_t outs[3] = {0x0800000, 0x0001000, 0x1A00000};
                            a = outs[rng() % 3] + (rng() % 0x10000);
                        }
                        a &= ~3u;
                        uint32_t d = rng();
                        uint8_t be = 1 + rng() % 15;
                        t->w_req = 1; t->w_addr = a; t->w_din = d; t->w_be = be;
                        if (in) {
                            uint32_t q = 0x6000000 + (a >> 3);
                            uint64_t din = ((uint64_t)d << 32) | d;
                            uint8_t be8 = (a & 4) ? (uint8_t)(be << 4) : be;
                            expect.push_back({q, din, be8}); sent_in++;
                        } else sent_out++;
                        gap = 1;
                    }
                } else stalled++;
                t->eval();
            }
            continue;
        }
        now = t2; t2 += 7381;
        t->clk2x = !t->clk2x;
        if (t->clk2x) {
            bool acc = t->g_we && !t->g_busy;
            W w{(uint32_t)t->g_addr, (uint64_t)t->g_din, (uint8_t)t->g_be};
            t->eval();
            if (acc && !nostall) {
                got++;
                if (expect.empty()) err("write that was not sent (outside the area?)", now / 1000);
                else {
                    W e = expect.front(); expect.pop_front();
                    if (e.qaddr != w.qaddr || e.be != w.be || ((e.din ^ w.din) & 0) ||
                        (((w.be & 0x0F) && (uint32_t)w.din != (uint32_t)e.din) || ((w.be & 0xF0) && (uint32_t)(w.din >> 32) != (uint32_t)(e.din >> 32))))
                        err("mirror write differs", now / 1000);
                }
            }
            if (busy_run) { busy_run--; t->g_busy = 1; }
            else if (rng() % 5000 == 0) { busy_run = 300; t->g_busy = 1; }
            else t->g_busy = (int)(rng() % 100) < busy_pct;
            t->eval();
        } else t->eval();
    }
    // drain
    for (int i = 0; i < 20000; i++) {
        t->clk2x = 1; bool acc = t->g_we && !t->g_busy; t->eval(); if (acc) { got++; if (!expect.empty()) expect.pop_front(); }
        t->g_busy = 0; t->clk2x = 0; t->eval();
        t->clk_src = !t->clk_src; t->w_req = 0; t->eval();
    }
    if (!nostall && !expect.empty()) err("writes lost", 0);
    if (!nostall && t->ovf) err("overflow with stall respected", 0);
    if (nostall && !t->ovf) err("nostall mode: ovf not set", 0);
    printf("sent inside %ld, outside %ld, arrived %ld, cycles with stall %ld, ovf %d\n",
           sent_in, sent_out, got, stalled, (int)t->ovf);
    printf("%s (%d errors)\n", errors ? "FAIL" : "PASS", errors);
    delete t;
    return errors ? 1 : 0;
}
