// ZSG-2 chip-level replay against MAME (docs/zsg2_rtl.md 4).
//
//   tb <events.ev> <flashdir> [--bshift N] [--pace CLK] [--lat CLK] [--jitter]
//      [--max K] [--dump file]
//
// events.ev comes from tools/zsg2/zsg2_events.py; flashdir holds wave0..2
// as tools/build_flash.py writes them (16-bit words byte-swapped, MAME NVRAM
// layout). --bshift N: compare register 0xB reads with (MAME value >> N), so
// a 0.288 trace is checked against the 61c7940 rule (vol >> 3) with N = 3.
// --pace CLK: clocks per sample tick (default 1040.45 = 33.8688 MHz /
// 32,552 Hz); --lat CLK: memory latency (default 24); --jitter: random
// latency 8..63 and random mem_ready.
#include "Vzsg2.h"
#include "verilated.h"
static Vzsg2 *top;
static uint64_t clk_n = 0;
#ifdef ZSG2_COVER
#include "Vzsg2___024root.h"
// state numbers of zsg2.sv st_t
enum { C_KON3 = 11, C_STEP = 19, C_MISS = 20, C_DEC = 21, C_VOL = 24, C_WB0 = 29, C_STOP = 32 };
static long cv_adv, cv_loop, cv_stop, cv_emph, cv_cut0, cv_ramp, cv_miss, cv_kon, cv_kon0, cv_oor;
static void cover() {
    auto *r = top->rootp;
    unsigned st = r->zsg2__DOT__st;
    if (st == C_STEP && r->zsg2__DOT__adv) {
        cv_adv++;
        if (((r->zsg2__DOT__cur + 1) & 0x1ffff) >= (r->zsg2__DOT__rg1 >> 32 & 0xffff)) cv_loop++;
        if ((r->zsg2__DOT__nblk) >= 0x180000) cv_oor++;
    }
    if (st == C_STOP) cv_stop++;
    static int trace = getenv("ZSG2_TRACE") ? 1 : 0;
    if (trace && (st == C_STEP || st == C_MISS || (st == C_DEC && (r->zsg2__DOT__ki & 3) == 0)))
        printf("TR clk %llu st %u ch %u cur %x sp %x nblk %x need %x rtag %x blk32 %08x lbtag %x lbv %d\n",
               (unsigned long long)clk_n, st, r->zsg2__DOT__ch, r->zsg2__DOT__cur, r->zsg2__DOT__sp,
               r->zsg2__DOT__nblk, r->zsg2__DOT__need, r->zsg2__DOT__rtag, r->zsg2__DOT__blk32,
               (unsigned)(r->zsg2__DOT__lb_q[2] & 0x7fffff), (int)(r->zsg2__DOT__lbv >> r->zsg2__DOT__ch & 1));
    if (st == C_DEC && (r->zsg2__DOT__ki & 3) == 0 && r->zsg2__DOT__emph_rst) cv_emph++;
    if (st == C_VOL && r->zsg2__DOT__cutoff == 0) cv_cut0++;
    if (st == C_WB0 && r->zsg2__DOT__parity) cv_ramp++;
    if (st == C_MISS) cv_miss++;
    if (st == C_KON3) { cv_kon++; if (r->zsg2__DOT__cur == 0x1ffff) cv_kon0++; }
}
#endif
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <deque>
#include <string>
#include <vector>

static std::vector<uint32_t> wave;     // 32-bit blocks
static unsigned lat = 24;
static bool jitter = false;
struct MemReq { uint64_t due; uint32_t line; };
static std::deque<MemReq> memq;
static uint64_t mem_reqs = 0;
static uint32_t rng = 12345;
static unsigned rnd() { rng = rng * 1103515245u + 12345u; return (rng >> 16) & 0x7fff; }

struct Out { long k; int v[4]; };
static std::deque<long> pend_k;        // ticks issued, pass not finished
static std::deque<Out> rtl_out, mame_out;
static long cmp_n = 0, cmp_bad = 0, cmp_badv[4] = {0, 0, 0, 0};
static long first_bad = -1;
static int max_pass = 0;
static bool ever_late = false;
static long rst_outstanding = 0, rst_with_outstanding = 0;
static FILE *dumpf = nullptr;

static void compare() {
    while (!rtl_out.empty() && !mame_out.empty()) {
        Out a = rtl_out.front(), b = mame_out.front();
        if (a.k < b.k) { rtl_out.pop_front(); continue; }
        if (b.k < a.k) { mame_out.pop_front(); continue; }
        rtl_out.pop_front(); mame_out.pop_front();
        cmp_n++;
        bool bad = false;
        for (int i = 0; i < 4; i++) if (a.v[i] != b.v[i]) { bad = true; cmp_badv[i]++; }
        if (dumpf) fprintf(dumpf, "%ld %d %d %d %d %d %d %d %d\n", a.k, a.v[0], a.v[1], a.v[2], a.v[3], b.v[0], b.v[1], b.v[2], b.v[3]);
        if (bad) {
            if (cmp_bad < 20)
                printf("OUT k=%ld rtl %d %d %d %d mame %d %d %d %d\n", a.k, a.v[0], a.v[1], a.v[2], a.v[3], b.v[0], b.v[1], b.v[2], b.v[3]);
            if (first_bad < 0) first_bad = a.k;
            cmp_bad++;
        }
    }
}

static void step() {
    // memory model: drive inputs for this cycle
    top->mem_rvalid = 0;
    if (!memq.empty() && memq.front().due <= clk_n) {
        uint32_t l = memq.front().line;
        memq.pop_front();
        uint64_t lo = 2 * (uint64_t)l < wave.size() ? wave[2 * l] : 0;
        uint64_t hi = 2 * (uint64_t)l + 1 < wave.size() ? wave[2 * l + 1] : 0;
        top->mem_rdata = lo | (hi << 32);
        top->mem_rvalid = 1;
    }
    top->mem_ready = jitter ? (rnd() & 3) != 0 : 1;
    top->clk = 0; top->eval();
    bool accept = top->mem_req && top->mem_ready;
    uint32_t line = top->mem_addr;
    top->clk = 1; top->eval();
    clk_n++;
#ifdef ZSG2_COVER
    cover();
#endif
    if (accept) {
        unsigned l = jitter ? 8 + (rnd() % 56) : lat;
        uint64_t due = clk_n + l;
        if (!memq.empty() && memq.back().due > due) due = memq.back().due;   // in order
        memq.push_back({due, line});
        mem_reqs++;
    }
    if (top->dbg_late) ever_late = true;
    if (top->out_valid) {
        Out o;
        o.k = pend_k.front(); pend_k.pop_front();
        o.v[0] = (int16_t)top->out_send0; o.v[1] = (int16_t)top->out_send1;
        o.v[2] = (int16_t)top->out_send2; o.v[3] = (int16_t)top->out_send3;
        rtl_out.push_back(o);
        if ((int)top->dbg_pass_clocks > max_pass) max_pass = top->dbg_pass_clocks;
        compare();
    }
}

static bool load_wave(const char *dir) {
    wave.assign(0x180000, 0);
    for (int c = 0; c < 3; c++) {
        std::string p = std::string(dir) + "/wave" + std::to_string(c);
        FILE *f = fopen(p.c_str(), "rb");
        if (!f) { fprintf(stderr, "cannot open %s\n", p.c_str()); return false; }
        std::vector<uint8_t> b(0x200000);
        size_t n = fread(b.data(), 1, b.size(), f);
        fclose(f);
        if (n != b.size()) { fprintf(stderr, "short %s\n", p.c_str()); return false; }
        for (uint32_t w = 0; w < 0x80000; w++) {
            uint32_t i = 2 * w;   // 16-bit index of the low half
            uint32_t lo = (b[2 * i] << 8) | b[2 * i + 1];
            uint32_t hi = (b[2 * i + 2] << 8) | b[2 * i + 3];
            wave[c * 0x80000 + w] = lo | (hi << 16);
        }
    }
    return true;
}

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: tb <events> <flashdir> [opts]\n"); return 2; }
    unsigned bshift = 0;
    double pace = 33868800.0 / 32552.0;
    long maxk = -1;
    for (int i = 3; i < argc; i++) {
        if (!strcmp(argv[i], "--bshift")) bshift = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--pace")) pace = atof(argv[++i]);
        else if (!strcmp(argv[i], "--lat")) lat = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--jitter")) jitter = true;
        else if (!strcmp(argv[i], "--max")) maxk = atol(argv[++i]);
        else if (!strcmp(argv[i], "--dump")) dumpf = fopen(argv[++i], "w");
    }
    if (!load_wave(argv[2])) return 2;
    FILE *ev = fopen(argv[1], "r");
    if (!ev) { fprintf(stderr, "cannot open %s\n", argv[1]); return 2; }
    Verilated::commandArgs(argc, argv);
    top = new Vzsg2;
    top->rst = 1;
    for (int i = 0; i < 4; i++) step();
    top->rst = 0;

    long n_w = 0, n_r = 0, n_rbad = 0, n_rb = 0, n_rbbad = 0, n_t = 0, n_x = 0;
    long rbad_by_reg[17] = {0};
    double next_tick = clk_n;
    char line[256];
    long lastk = 0;
    while (fgets(line, sizeof line, ev)) {
        char c = line[0];
        if (c == 'X') {
            // let finished work drain, then reset (pending ticks are lost, as
            // in MAME the reset only clears state)
            while (!pend_k.empty()) step();
            if (!memq.empty() || top->mem_req) { rst_with_outstanding++; rst_outstanding += memq.size() + (top->mem_req ? 1 : 0); }
            top->rst = 1; step(); step(); top->rst = 0;
            n_x++;
        } else if (c == 'W' || c == 'R') {
            unsigned a, d;
            sscanf(line + 2, "%x %x", &a, &d);
            top->cpu_addr = a;
            if (c == 'W') { top->cpu_wdata = d; top->cpu_wr = 1; }
            else top->cpu_rd = 1;
            long guard = 0;
            while (true) {
                step();
                if (top->cpu_ack) break;
                if (++guard > 2000000) { printf("HANG on %s at clock %llu\n", line, (unsigned long long)clk_n); return 1; }
            }
            top->cpu_wr = 0; top->cpu_rd = 0;
            if (c == 'W') n_w++;
            else {
                n_r++;
                unsigned exp = d;
                bool regb = a < 0x300 && (a & 0xf) == 0xb;
                if (regb) { exp = d >> bshift; n_rb++; }
                if (top->cpu_rdata != exp) {
                    n_rbad++;
                    if (regb) n_rbbad++;
                    rbad_by_reg[a < 0x300 ? (a & 0xf) : 16]++;
                    if (n_rbad <= 20) printf("READ k=%ld addr %03x rtl %04x mame %04x (exp %04x)\n", lastk, a, top->cpu_rdata, d, exp);
                }
            }
        } else if (c == 'T') {
            long k = atol(line + 2);
            if (maxk >= 0 && k > maxk) break;
            // pace: wait for the tick time, never more than 2 passes pending
            while ((double)clk_n < next_tick || pend_k.size() >= 2) step();
            next_tick += pace;
            if (next_tick < clk_n) next_tick = clk_n;
            pend_k.push_back(k);
            top->sample_tick = 1; step(); top->sample_tick = 0;
            n_t++; lastk = k;
        } else if (c == 'O') {
            Out o;
            sscanf(line + 2, "%ld %d %d %d %d", &o.k, &o.v[0], &o.v[1], &o.v[2], &o.v[3]);
            mame_out.push_back(o);
            compare();
        }
    }
    while (!pend_k.empty()) step();
    compare();
    printf("ticks %ld resets %ld writes %ld reads %ld (reg B %ld)\n", n_t, n_x, n_w, n_r, n_rb);
    printf("read mismatches %ld (reg B %ld) by reg:", n_rbad, n_rbbad);
    for (int i = 0; i < 17; i++) if (rbad_by_reg[i]) printf(" %x:%ld", i, rbad_by_reg[i]);
    printf("\nsamples compared %ld, mismatching %ld (per output %ld %ld %ld %ld), first %ld\n",
           cmp_n, cmp_bad, cmp_badv[0], cmp_badv[1], cmp_badv[2], cmp_badv[3], first_bad);
    printf("clocks %llu, memory requests %llu, longest pass %d clocks, late %d, overrun %d\n",
           (unsigned long long)clk_n, (unsigned long long)mem_reqs, max_pass, (int)ever_late, top->dbg_overrun);
    printf("resets with memory requests outstanding %ld (%ld requests)\n", rst_with_outstanding, rst_outstanding);
#ifdef ZSG2_COVER
    printf("cover: advances %ld loops %ld stops %ld emphasis resets %ld cutoff0 %ld ramp steps %ld miss clocks %ld key-ons %ld (start 0: %ld) out-of-range blocks %ld\n",
           cv_adv, cv_loop, cv_stop, cv_emph, cv_cut0, cv_ramp, cv_miss, cv_kon, cv_kon0, cv_oor);
#endif
    if (dumpf) fclose(dumpf);
    delete top;
    return (cmp_bad || n_rbad) ? 1 : 0;
}
