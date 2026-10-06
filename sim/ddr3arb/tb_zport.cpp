// gnet_ddr3_zport testbench: clk_1x Zoom side against a clk_2x arbiter model.
//
// The adapter holds one request in a skid register (m_ready from its own
// state), so the Zoom side's and the arbiter's acceptances happen in
// different cycles; data is checked against the Zoom side's own order.
// Zoom side (clk_1x, 33.8688 MHz): up to 8 open requests, m_line changes
// while a request waits (as zoom_memarb does when the program cache takes
// priority), the line is recorded on the accepting clk_1x edge; responses
// checked in order (data = hash(line)) and as one-clk_1x pulses. Arbiter side
// (clk_2x): z_ready random when z_req (combinational), answers in order after
// a random latency, back to back allowed. Zoom resets (zrst, clk_1x) in the
// middle of traffic: the Zoom side forgets its open requests, and no answer
// for a request from before the reset may arrive afterwards.
//
//   obj_zport/Vgnet_ddr3_zport <seed> <clk1x cycles>
#include "Vgnet_ddr3_zport.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <random>

static uint64_t hash64(uint64_t x) { x ^= x >> 33; x *= 0xff51afd7ed558ccdULL; x ^= x >> 33; x *= 0xc4ceb9fe1a85ec53ULL; x ^= x >> 33; return x; }

int main(int argc, char** argv) {
    unsigned seed = argc > 1 ? atoi(argv[1]) : 1;
    long n1 = argc > 2 ? atol(argv[2]) : 200000;
    std::mt19937 rng(seed);
    auto* t = new Vgnet_ddr3_zport;
    int errors = 0;
    auto err = [&](const char* m, long c) { if (errors++ < 10) printf("ERROR at clk_1x %ld: %s\n", c, m); };
    struct A { uint32_t line; long due; };
    std::deque<A> arb;              // arbiter: accepted, not yet answered
    std::deque<uint32_t> open;      // Zoom: accepted, not yet answered
    long answered = 0, accepted = 0, resets = 0, cyc2 = 0;
    long last_beat2 = -10;
    int rst_left = 0;
    t->clk1x = 0; t->clk2x = 0; t->m_req = 0; t->zrst = 0; t->z_ready = 0; t->z_rvalid = 0;
    t->eval();
    for (long c1 = 0; c1 < n1; c1++) {
        for (int h = 0; h < 2; h++) {           // two clk_2x cycles per clk_1x cycle
            bool edge1 = (h == 1);               // this clk_2x edge is also a clk_1x edge
            // arbiter model: ready for the request presented now
            t->eval();
            t->z_ready = t->z_req && (rng() % 3 != 0);
            t->eval();
            bool acc2 = t->z_req && t->z_ready;
            uint32_t acc_line = t->z_line;
            // clk_1x side samples at its edge
            bool acc1 = edge1 && t->m_req && t->m_ready;
            uint32_t z_side_line = t->m_line;
            bool rv1 = edge1 && t->m_rvalid;
            uint64_t rd1 = t->m_rdata;
            if (c1 > 2 && !edge1 && t->m_ready) err("m_ready outside a clk_1x edge cycle", c1);   // phase detector settles in 2 cycles
            // edges
            t->clk2x = 1; if (edge1) t->clk1x = 1; t->eval();
            cyc2++;
            if (acc2) { arb.push_back({acc_line, cyc2 + 3 + (long)(rng() % 40)}); }
            if (edge1) {
                if (acc1) { open.push_back(z_side_line); accepted++; }
                if (rv1) {
                    if (open.empty()) err("m_rvalid with no open request", c1);
                    else {
                        if (rd1 != hash64(open.front())) err("data for the wrong line", c1);
                        open.pop_front(); answered++;
                    }
                }
            }
            t->clk2x = 0; if (edge1) t->clk1x = 0; t->eval();
            // arbiter answers (inputs for the next clk_2x cycle)
            bool rv = !arb.empty() && arb.front().due <= cyc2 && rng() % 4 != 0;
            t->z_rvalid = rv;
            if (rv) { t->z_rdata = hash64(arb.front().line); arb.pop_front(); last_beat2 = cyc2; }
            t->eval();
            if (edge1) {
                // Zoom side updates after its edge
                if (rst_left) {
                    if (--rst_left == 0) t->zrst = 0;
                } else if (c1 > 1000 && rng() % 20000 == 0) {
                    t->zrst = 1; rst_left = 2 + rng() % 6; resets++;
                    open.clear(); t->m_req = 0;
                }
                if (!t->zrst) {
                    if (acc1) t->m_req = 0;
                    if (t->m_req && rng() % 3 == 0) t->m_line = rng() % 0x200000;   // priority change
                    if (!t->m_req && open.size() < 8 && rng() % 3 == 0) { t->m_req = 1; t->m_line = rng() % 0x200000; }
                }
                t->eval();
            }
        }
    }
    printf("clk_1x cycles %ld  accepted %ld  answered %ld  zoom resets %ld  still open %zu\n",
           n1, accepted, answered, resets, open.size());
    if (answered < accepted - 8 * (resets + 1) - 8) err("answers missing", n1);
    printf("%s (%d errors)\n", errors ? "FAIL" : "PASS", errors);
    delete t;
    return errors ? 1 : 0;
}
