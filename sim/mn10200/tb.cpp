// Verilator testbench for rtl/zoom/mn10200.sv: runs the real Taito Zoom
// firmware (zoomprog flash image) and compares every instruction with a
// MAME 0.288 trace from tools/mn102/mn102_oracle.sh.
//
//   tb <zoomprog> <trace> [max_insns] [report_every]
//
// trace is a file or a FIFO fed by MAME (sim/mn10200/run_vs_mame.sh).
// zoomprog is the MAME NVRAM flash file (16-bit words byte-swapped).
// Per instruction it compares PC, D0-D3, A0-A3, PSW, MDR, the cycle count
// of the previous instruction (including interrupt entry) and the
// interrupt request registers FC42 (timers 0-3) and FC50 (IRQ pins).
// External inputs come from the MAME run, aligned by instruction index:
//   - IRQ pin levels from FC57 (P4) before each instruction;
//   - the IRQ0 doorbell pulse when MAME shows the IRQ0 request bit set and
//     the core does not;
//   - reads of ZSG-2 / TMS57002 / mailbox from the trace's B lines, in order;
//   - a reset of the CPU where MAME's trace restarts at 0x080000.
// External writes are checked against the B lines in order.
//
// Known MAME divergence, accepted and counted (unless --strict):
//   MULU NF. mn10200.cpp computes (uint16_t)a * (uint16_t)b in int, so the
//   compiler may assume the product is below 2^31 and NF is never set; the
//   MN102L manual p.79 sets NF from bit 31 of the 32-bit product, as the
//   core does. The testbench then copies MAME's PSW into the core and goes on.
#include "Vmn10200.h"
#include "Vmn10200___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <deque>

struct TLine {
    uint32_t pc, d[4], a[4], psw, mdr;
    uint64_t tc;
    uint32_t fc57, fc50, fc42;
    std::string dis;
};

struct BusRec { char rw; uint32_t addr, data, mask; };
static std::deque<BusRec> busq;
static uint64_t bus_total = 0;

static FILE *tf;
static char pushback[512];
static bool have_pushback = false;
static bool get_line(char *buf, size_t n) {
    if (have_pushback) { strcpy(buf, pushback); have_pushback = false; return true; }
    return fgets(buf, (int)n, tf) != nullptr;
}
// Reads the next T line. B lines met on the way belong to the previous
// instruction and go to busq. The disassembly line after the T line is kept.
static bool read_tline(TLine &t) {
    char buf[512];
    while (get_line(buf, sizeof buf)) {
        if (buf[0] == 'B' && buf[1] == ' ') {
            BusRec r;
            unsigned a, d, m;
            if (sscanf(buf + 2, "%c %x %x %x", &r.rw, &a, &d, &m) != 4) { fprintf(stderr, "bad bus line: %s", buf); exit(2); }
            r.addr = a; r.data = d; r.mask = m;
            busq.push_back(r);
            bus_total++;
            continue;
        }
        if (buf[0] != 'T' || buf[1] != ' ') continue;
        unsigned long long tc;
        unsigned v[15];
        if (sscanf(buf + 2, "%x %x %x %x %x %x %x %x %x %x %x %llx %x %x %x",
                   &v[0], &v[1], &v[2], &v[3], &v[4], &v[5], &v[6], &v[7], &v[8], &v[9], &v[10],
                   &tc, &v[11], &v[12], &v[13]) != 15) {
            fprintf(stderr, "bad trace line: %s", buf);
            exit(2);
        }
        t.pc = v[0];
        for (int i = 0; i < 4; i++) { t.d[i] = v[1 + i]; t.a[i] = v[5 + i]; }
        t.psw = v[9]; t.mdr = v[10]; t.tc = tc;
        t.fc57 = v[11]; t.fc50 = v[12]; t.fc42 = v[13];
        t.dis = "?";
        char dis[512];
        if (get_line(dis, sizeof dis)) {
            if (dis[0] == 'T' || dis[0] == 'B') {
                strcpy(pushback, dis);
                have_pushback = true;
            } else {
                dis[strcspn(dis, "\n")] = 0;
                t.dis = dis;
            }
        }
        return true;
    }
    return false;
}

static std::vector<uint8_t> flash(0x80000), ram(0x20000);
static Vmn10200 *top;
static uint64_t clocks = 0;
static bool ack_next = false;
static int bus_lat = 0;       // MN102_BUSLAT: extra clocks before each ack
static int lat_left = -1;
static uint64_t cyc_before_reset = 0;  // machine cycles retired before CPU resets (pacer report)
static bool fail = false;
static char failmsg[512];

static bool ext_dev(uint32_t a) {
    return (a >= 0x800000 && a <= 0x8007ff) || a == 0xc00000 || a == 0xc00001 ||
           (a >= 0xe00000 && a <= 0xe000ff);
}

static void service_bus() {
    // called after a rising edge: answer a pending request on the next edge
    if (ack_next) { top->bus_ack = 0; ack_next = false; return; }
    if (!(top->bus_rd || top->bus_wr)) { lat_left = -1; return; }
    if (lat_left < 0) lat_left = bus_lat;
    if (lat_left > 0) { lat_left--; return; }
    lat_left = -1;
    uint32_t a = top->bus_addr & 0xfffffe;
    unsigned be = top->bus_be;
    uint16_t mask = (be & 1 ? 0x00ff : 0) | (be & 2 ? 0xff00 : 0);
    uint16_t rd = 0;
    if (a >= 0x080000 && a < 0x100000) {
        uint32_t o = a - 0x080000;
        rd = flash[o] | flash[o + 1] << 8;
    } else if (a >= 0x400000 && a < 0x420000) {
        uint32_t o = a - 0x400000;
        if (top->bus_wr) {
            if (be & 1) ram[o] = top->bus_wdata & 0xff;
            if (be & 2) ram[o + 1] = top->bus_wdata >> 8;
        }
        rd = ram[o] | ram[o + 1] << 8;
    } else if (ext_dev(a)) {
        char rw = top->bus_wr ? 'W' : 'R';
        if (busq.empty()) {
            snprintf(failmsg, sizeof failmsg, "bus: core %c %06x, MAME made no further access", rw, a);
            fail = true;
        } else {
            BusRec r = busq.front();
            busq.pop_front();
            uint16_t wd = top->bus_wdata & mask;
            if (r.rw != rw || r.addr != a || r.mask != mask || (rw == 'W' && (r.data & mask) != wd)) {
                snprintf(failmsg, sizeof failmsg,
                         "bus: core %c %06x %04x %04x, MAME %c %06x %04x %04x",
                         rw, a, rw == 'W' ? wd : 0, mask, r.rw, r.addr, r.data, r.mask);
                fail = true;
            }
            rd = r.data;
        }
    }
    top->bus_rdata = rd;
    top->bus_ack = 1;
    ack_next = true;
}

static void tick() {
    top->clk = 0;
    top->eval();
    top->clk = 1;
    top->eval();
    clocks++;
    service_bus();
}

// periph internals (verilator --public-flat-rw)
static unsigned rtl_icr(int g) {
    auto *r = top->rootp;
    unsigned ir = r->mn10200__DOT__u_periph__DOT__icr_ir[g - 1];
    unsigned h = r->mn10200__DOT__u_periph__DOT__icr_h[g - 1];
    return (ir << 4) | (ir & h & 0xf);
}

static void do_reset(unsigned pins) {
    top->irq_pin = pins;
    top->rst = 1;
    for (int i = 0; i < 4; i++) tick();
    top->rst = 0;
    tick();
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) {
        fprintf(stderr, "usage: tb <zoomprog> <trace> [max_insns] [report_every]\n");
        return 2;
    }
    uint64_t maxn = argc > 3 ? strtoull(argv[3], 0, 0) : ~0ull;
    uint64_t every = argc > 4 ? strtoull(argv[4], 0, 0) : 1000000;
    FILE *f = fopen(argv[1], "rb");
    if (!f || fread(flash.data(), 1, flash.size(), f) != flash.size()) { perror(argv[1]); return 2; }
    fclose(f);
    for (size_t i = 0; i < flash.size(); i += 2) std::swap(flash[i], flash[i + 1]);  // NVRAM is byte-swapped
    tf = fopen(argv[2], "r");
    if (!tf) { perror(argv[2]); return 2; }
    top = new Vmn10200;
    // MN102_PACE=1: run with the real-time pacer (checks its rate)
    top->pace_en = getenv("MN102_PACE") ? 1 : 0;
    top->ext_go = 1;
    if (getenv("MN102_BUSLAT")) bus_lat = atoi(getenv("MN102_BUSLAT"));
    top->dbg_hold = 1;
    top->p0_in = 0xff; top->p1_in = 0xff; top->p2_in = 0xff; top->p3_in = 0xff;
    top->bus_ack = 0;

    TLine L, prev;
    std::deque<std::string> hist;
    if (!read_tline(L)) { fprintf(stderr, "empty trace\n"); return 2; }
    do_reset(L.fc57 >> 4);
    uint64_t k = 0, rtl_prev_cyc = 0, resets = 0, irq0_pulses = 0, mulu_nf = 0;
    bool strict = getenv("MN102_STRICT") != nullptr;
    bool no_icr = getenv("MN102_NO_ICR") != nullptr;
    bool have_prev = false;
    while (k < maxn) {
        // MAME restarted the CPU here (reset from the main CPU)
        bool is_reset = have_prev && L.pc == 0x080000 && L.psw == 0 && L.mdr == 0 &&
                        !(L.d[0] | L.d[1] | L.d[2] | L.d[3] | L.a[0] | L.a[1] | L.a[2] | L.a[3]);
        if (is_reset) {
            cyc_before_reset += top->dbg_cycles;
            do_reset(L.fc57 >> 4);
            resets++;
            have_prev = false;
        }
        // wait for the boundary
        int guard = 0;
        while (!top->dbg_bound) {
            tick();
            if (fail || ++guard > 100000) break;
        }
        if (fail) break;
        if (guard > 100000) { snprintf(failmsg, sizeof failmsg, "core stuck before boundary"); fail = true; break; }
        if (!busq.empty()) {
            BusRec &r = busq.front();
            snprintf(failmsg, sizeof failmsg, "bus: MAME %c %06x %04x %04x, the core made no such access",
                     r.rw, r.addr, r.data, r.mask);
            fail = true;
            break;
        }
        // pins for this boundary
        // a pin change needs one clock to reach the request latches before
        // the interrupt sample; unchanged pins cost no clock
        if (top->irq_pin != (L.fc57 >> 4)) {
            top->irq_pin = L.fc57 >> 4;
            tick();
            tick();     // PIPE = 1 registers the request once more
        }
        if ((L.fc50 & 0x10) && !(rtl_icr(8) & 0x10)) {
            unsigned p = top->irq_pin;
            top->irq_pin = p & ~1u;
            tick();
            top->irq_pin = p;
            tick();
            irq0_pulses++;
        }
        // run to the start of the next instruction
        top->dbg_hold = 0;
        guard = 0;
        while (!top->dbg_insn) {
            tick();
            if (fail || ++guard > 100000) break;
        }
        top->dbg_hold = 1;
        if (fail) break;
        if (guard > 100000) { snprintf(failmsg, sizeof failmsg, "core stuck after boundary"); fail = true; break; }
        // compare
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
                top->rootp->mn10200__DOT__u_core__DOT__psw = L.psw;
                // an interrupt taken right after the MULU stacked the core's PSW
                if (L.pc == 0x080008 && L.a[3] >= 0x400000 && L.a[3] < 0x420000)
                    ram[L.a[3] - 0x400000] &= ~0x02;
                mulu_nf++;
            } else {
                snprintf(why, sizeof why, "PSW %04x vs MAME %04x", top->dbg_psw, L.psw);
            }
        }
        if (!why[0] && top->dbg_mdr != L.mdr) snprintf(why, sizeof why, "MDR %04x vs MAME %04x", top->dbg_mdr, L.mdr);
        if (!why[0] && have_prev && (cyc - rtl_prev_cyc) != (L.tc - prev.tc))
            snprintf(why, sizeof why, "cycles of previous instruction %llu vs MAME %llu",
                     (unsigned long long)(cyc - rtl_prev_cyc), (unsigned long long)(L.tc - prev.tc));
        // MN102_NO_ICR=1: skip FC42/FC50 (timer phase differs with TIMER_EXACT = 0)
        if (!why[0] && !no_icr && rtl_icr(1) != (L.fc42 & 0xff)) snprintf(why, sizeof why, "FC42 %02x vs MAME %02x", rtl_icr(1), L.fc42);
        if (!why[0] && !no_icr && rtl_icr(8) != (L.fc50 & 0xff)) snprintf(why, sizeof why, "FC50 %02x vs MAME %02x", rtl_icr(8), L.fc50);
        char line[200];
        snprintf(line, sizeof line, "%10llu %06x %-28s", (unsigned long long)k, L.pc, L.dis.c_str());
        hist.push_back(line);
        if (hist.size() > 12) hist.pop_front();
        if (why[0]) {
            snprintf(failmsg, sizeof failmsg, "instruction %llu: %s", (unsigned long long)k, why);
            fail = true;
            break;
        }
        rtl_prev_cyc = cyc;
        prev = L;
        have_prev = true;
        k++;
        if (every && k % every == 0)
            fprintf(stderr, "%llu instructions match, %.2f clocks/instruction\n",
                    (unsigned long long)k, (double)clocks / k);
        if (!read_tline(L)) break;
    }
    printf("matched %llu instructions (%llu resets, %llu IRQ0 pulses, %llu bus records, %llu MULU NF accepted), %.2f clocks/instruction\n",
           (unsigned long long)k, (unsigned long long)resets, (unsigned long long)irq0_pulses, (unsigned long long)bus_total,
           (unsigned long long)mulu_nf,
           k ? (double)clocks / k : 0.0);
    if (top->pace_en)
        printf("pacer: %llu machine cycles in %llu clocks = %.6f MHz at 33.8688 MHz (target 6.250000)\n",
               (unsigned long long)(cyc_before_reset + top->dbg_cycles), (unsigned long long)clocks,
               33.8688 * (double)(cyc_before_reset + top->dbg_cycles) / (double)clocks);
    if (fail) {
        printf("FIRST DIVERGENCE: %s\n", failmsg);
        for (auto &h : hist) printf("  %s\n", h.c_str());
        printf("  MAME line: pc %06x d %06x %06x %06x %06x a %06x %06x %06x %06x psw %04x mdr %04x fc57 %02x fc50 %02x fc42 %02x\n",
               L.pc, L.d[0], L.d[1], L.d[2], L.d[3], L.a[0], L.a[1], L.a[2], L.a[3], L.psw, L.mdr, L.fc57, L.fc50, L.fc42);
        printf("  core     : pc %06x psw %04x mdr %04x fc50 %02x fc42 %02x\n",
               top->dbg_pc, top->dbg_psw, top->dbg_mdr, rtl_icr(8), rtl_icr(1));
        return 1;
    }
    return 0;
}
