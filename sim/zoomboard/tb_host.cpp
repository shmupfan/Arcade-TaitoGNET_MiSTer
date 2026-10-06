// Directed test of rtl/zoom/zoom_host.sv with the mailbox (zoom_mbox.sv):
// the cases the game traces do not reach (MB87078 C0, C32, EN = 0,
// channel select, the MAME linear law, host mailbox reads, the doorbell).
//   tb_host <mame_gain 0|1>   (build: sim/zoomboard/build_host.sh)
#include "Vzoom_host_tb.h"
#include "verilated.h"
#include <cstdio>
#include <cmath>
#include <cstdlib>

static Vzoom_host_tb *t;
static int fails = 0, checks = 0;
static void tick() { t->clk = 1; t->eval(); t->clk = 0; t->eval(); }
static uint32_t acc(bool we, uint32_t addr, uint32_t be, uint32_t data) {
    t->h_req = 1; t->h_we = we; t->h_addr = addr; t->h_be = be; t->h_wdata = data;
    tick();
    t->h_req = 0;
    for (int i = 0; i < 5 && !t->h_ack; i++) tick();
    if (!t->h_ack) { printf("no ack %06x\n", addr); fails++; }
    uint32_t r = t->h_rdata;
    tick();
    return r;
}
static void expect(const char *what, uint32_t got, uint32_t want) {
    checks++;
    if (got != want) { printf("FAIL %s: %u, expected %u\n", what, got, want); fails++; }
}
static unsigned law(int d) { return (unsigned)std::lround(32768.0 * std::pow(10.0, -(63 - d) * 0.5 / 20.0)); }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int mame = argc > 1 ? atoi(argv[1]) : 0;
    t = new Vzoom_host_tb;
    t->hrst = 1; tick(); tick(); t->hrst = 0; tick();
    expect("reset L", t->gain_l, 32768);
    expect("reset R", t->gain_r, 32768);
    // the games' sequence: address 0x0404, data 0x3030 (nightrai, shikigam)
    acc(true, 0xB80000, 0xC, 0x04040000);
    acc(true, 0xB80000, 0x3, 0x00003030);
    acc(true, 0xB80000, 0xC, 0x05050000);
    acc(true, 0xB80000, 0x3, 0x00003636);
    if (!mame) {
        expect("ch0 0x30", t->gain_l, law(0x30));
        expect("ch1 0x36", t->gain_r, law(0x36));
        for (int d = 0; d < 64; d++) {
            acc(true, 0xB80000, 0xC, 0x00040000);       // ch0, EN
            acc(true, 0xB80000, 0x3, d);
            expect("law", t->gain_l, law(d));
        }
        acc(true, 0xB80000, 0xC, 0x00140000);           // ch0, EN, C32
        acc(true, 0xB80000, 0x3, 0x3F);
        expect("C32", t->gain_l, 823);
        acc(true, 0xB80000, 0xC, 0x000C0000);           // ch0, EN, C0
        acc(true, 0xB80000, 0x3, 0x00);
        expect("C0", t->gain_l, 32768);
        acc(true, 0xB80000, 0xC, 0x00010000);           // ch1, EN = 0
        acc(true, 0xB80000, 0x3, 0x3F);
        expect("EN=0", t->gain_r, 0);
        acc(true, 0xB80000, 0xC, 0x00060000);           // ch2, EN: no effect on L/R
        acc(true, 0xB80000, 0x3, 0x00);
        expect("ch2 L", t->gain_l, 32768);
        expect("ch2 R", t->gain_r, 0);
    } else {
        expect("mame L 0x30", t->gain_l, (32768 * 0x30 + 31) / 63);
        expect("mame R 0x36", t->gain_r, (32768 * 0x36 + 31) / 63);
        acc(true, 0xB80000, 0xC, 0x00060000);           // register 6: ignored
        acc(true, 0xB80000, 0x3, 0x0000);
        expect("mame reg 6", t->gain_l, (32768 * 0x30 + 31) / 63);
        t->zoom_release = 1; tick(); t->zoom_release = 0;   // register number back to 0
        acc(true, 0xB80000, 0x3, 0x0000);
        expect("mame after release", t->gain_l, (32768 * 0x30 + 31) / 63);
    }
    // mailbox: host lanes 0 and 2, Zoom side bytes
    acc(true, 0xBE0010, 0x5, 0x00AB00CD);
    expect("mbox host read", acc(false, 0xBE0010, 0xF, 0), 0x00AB00CD);
    expect("mbox host read lane 0", acc(false, 0xBE0010, 0x1, 0), 0x000000CD);
    t->z_a = 0x04; t->eval(); tick();
    expect("mbox zoom word 4", t->z_q, 0xABCD);
    t->z_we = 1; t->z_a = 0x7F; t->z_be = 2; t->z_wd = 0x5A00; tick(); t->z_we = 0; tick();
    expect("mbox host read 0x1FC lane 2", acc(false, 0xBE01FC, 0xF, 0), 0x005A0000);
    // status and unmapped bytes read 0; doorbell toggles
    expect("status", acc(false, 0xBC0000, 0xF, 0), 0);
    unsigned tg = t->irq_tog;
    acc(true, 0xBA0000, 0x3, 0);
    expect("doorbell", t->irq_tog, tg ^ 1);
    t->h_addr = 0xB70000; t->eval();
    expect("not decoded", t->h_hit, 0);
    printf("%d checks, %d failures (MAME_GAIN %d)\n", checks, fails, mame);
    return fails ? 1 : 0;
}
