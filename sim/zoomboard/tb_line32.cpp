// Directed test of rtl/zoom/zoom_line32.sv against a model of SDRAM
// channel 3 that applies read DQM as real SDRAM does: sdram.sv drives
// ~be[1:0] onto DQMH/DQML with the READ command (sdram.sv:476), and with a
// read DQM latency of 2 a masked lane of the burst is not driven, so the
// model returns 0xA5 in every byte whose enable was 0. Simulation models of
// the SDRAM ignore read DQM; this one does not, so a partial read mask in
// the Zoom's wave or program path fails here.
//   tb_line32 [--selftest]   (build: sim/zoomboard/build_line32.sh)
// --selftest forces the model to use be = 0011 and must fail.
#include "Vzoom_line32.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <vector>

static Vzoom_line32 *t;
static void tick() { t->clk = 1; t->eval(); t->clk = 0; t->eval(); }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    bool selftest = argc > 1 && !strcmp(argv[1], "--selftest");
    std::vector<uint8_t> mem(1 << 24);
    uint32_t r = 1;
    for (auto &b : mem) { r = r * 1103515245u + 12345u; b = r >> 16; }
    t = new Vzoom_line32;
    t->rst = 1; tick(); tick(); t->rst = 0;
    int fails = 0, lines = 0, wait = 0;
    unsigned be_seen_bad = 0;
    for (int n = 0; n < 2000; n++) {
        r = r * 1103515245u + 12345u;
        uint32_t line = (r >> 8) & 0x1fffff;
        t->l_req = 1; t->l_line = line;
        t->eval();
        while (!t->l_ready) tick();
        tick();
        t->l_req = 0;
        int g = 0;
        while (!t->l_rvalid && ++g < 200) {
            t->eval();
            if (t->w_req && !t->w_ack) {
                if (t->w_we || t->w_be != 0xF) be_seen_bad++;
                unsigned be = selftest ? 0x3 : t->w_be;
                uint32_t a = (uint32_t)t->w_addr << 2, d = 0;
                for (int i = 0; i < 4; i++) d |= (uint32_t)((be >> i & 1) ? mem[a + i] : 0xA5) << (8 * i);
                for (int i = 0; i < 4 + (wait++ % 5); i++) tick();   // channel 3 latency, varied
                t->w_ack = 1; t->w_rdata = d; tick(); t->w_ack = 0;
            } else tick();
        }
        uint64_t want = 0;
        for (int i = 7; i >= 0; i--) want = want << 8 | mem[(line << 3) + i];
        if (!t->l_rvalid || t->l_rdata != want) {
            if (fails < 3) printf("line %06x: got %016llx want %016llx\n", line, (unsigned long long)t->l_rdata, (unsigned long long)want);
            fails++;
        }
        lines++;
        tick();
    }
    printf("%d lines, %d wrong, %u reads with partial byte enables or a write%s\n", lines, fails, be_seen_bad,
           selftest ? " (selftest: model forced to be = 0011, failures expected)" : "");
    return selftest ? (fails ? 0 : 1) : ((fails || be_seen_bad) ? 1 : 0);
}
