// Verilator replay testbench for rtl/zoom/tms57002.sv against a MAME 0.288
// trace from tools/tms57/tms57_trace.sh (format in tms57_trace.lua).
//
//   tb <tms57.log> [--quiet] [--max-diffs N] [--resync-periodic] [--freerun]
//
// Default: the testbench grants one slot at a time and syncs when the
// program is done, so every host input lands exactly where MAME's did.
// --freerun drives `step` from a 12.5 / 33.8688 MHz accumulator and `sync`
// every 384 steps (the G-NET time base) and holds the core (dbg_hold) at
// each host input's position until it is taken, with the time base stopped
// (MAME applies them in zero DSP time): this checks the slot credit, the
// sync split and the request paths at the real rate.
//
// The log is read whole. Every host byte and PLOAD / CLOAD change is applied
// at the sample and PC where MAME's DSP stood when the MN10200 made it.
// Samples: the testbench counts syncs as MAME's XBA does (one decrement per
// sync that is not blocked by PLOAD), so the XBA logged with each event gives
// its sample. Per sample, the serial inputs are MAME's (S lines) and the SO1
// pair latched at the sync is compared with what MAME streamed at that sync.
//
// Snapshots (Z blocks): "pload" loads the whole state before the first
// download. After each later PLOAD rise MAME restarts the program
// mid-sample at a point its scheduler sets (docs/tms57002_rtl.md, "replay
// method"), so samples from a PLOAD fall to the next "resync" snapshot are
// not compared; at "resync" the testbench reports the state differences
// and loads MAME's state. "periodic" snapshots are compared (and loaded
// with --resync-periodic). A jump in XBA (Zoom reset) also waits for the
// next resync.
#include "Vtms57002.h"
#include "Vtms57002___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <map>

static Vtms57002 *top;
static Vtms57002___024root *R;
static uint64_t clocks = 0;

static void tick() {
    top->clk = 0; top->eval();
    top->clk = 1; top->eval();
    clocks++;
}

struct Snap {
    std::string tag;
    double t = 0;
    uint32_t xba = 0, pc = 0;
    std::map<std::string, uint64_t> v;
    std::map<std::string, std::vector<uint32_t>> a;
    std::vector<uint32_t> pmem;
    std::vector<uint8_t> xram;
};

enum EvKind { EV_S, EV_H, EV_Z };
struct Ev {
    EvKind kind;
    uint32_t xba, pc;
    // S
    uint32_t si[4], so[4];
    // H
    char rw; uint32_t addr, data, mask;
    double t;
    int snap;  // index into snaps
};

static std::vector<Snap> snaps;
static std::vector<Ev> evs;

static void load_log(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) { perror(path); exit(2); }
    static char buf[1 << 16];
    Snap *cur = nullptr;
    while (fgets(buf, sizeof buf, f)) {
        if (buf[0] == 'S' && buf[1] == ' ') {
            Ev e{}; e.kind = EV_S;
            unsigned v[10];
            if (sscanf(buf + 2, "%x %x %x %x %x %x %x %x %x %x", &v[0], &v[1], &v[2], &v[3], &v[4], &v[5],
                       &v[6], &v[7], &v[8], &v[9]) != 10) continue;
            e.xba = v[0]; e.pc = v[1];
            for (int k = 0; k < 4; k++) { e.si[k] = v[2 + k]; e.so[k] = v[6 + k]; }
            evs.push_back(e);
        } else if (buf[0] == 'H' && buf[1] == ' ') {
            Ev e{}; e.kind = EV_H;
            char rw; unsigned a, d, m, x, p, sti, hidx;
            if (sscanf(buf + 2, "%lf %c %x %x %x %x %x %x %x", &e.t, &rw, &a, &d, &m, &x, &p, &sti, &hidx) != 9) continue;
            e.rw = rw; e.addr = a; e.data = d; e.mask = m; e.xba = x; e.pc = p;
            evs.push_back(e);
        } else if (buf[0] == 'Z' && buf[1] == ' ') {
            snaps.emplace_back();
            cur = &snaps.back();
            char tag[32]; unsigned x, p;
            sscanf(buf + 2, "%31s %lf %x %x", tag, &cur->t, &x, &p);
            cur->tag = tag; cur->xba = x; cur->pc = p;
            cur->xram.assign(0x10000, 0);
        } else if (cur && buf[0] == 'Z' && buf[1] == 'V') {
            char n[64]; unsigned long long v;
            sscanf(buf + 3, "%63s %llx", n, &v);
            cur->v[n] = v;
        } else if (cur && buf[0] == 'Z' && buf[1] == 'A') {
            char *s = buf + 3;
            char n[64]; int off;
            sscanf(s, "%63s%n", n, &off);
            s += off;
            std::vector<uint32_t> arr;
            char *end;
            for (;;) {
                unsigned long v = strtoul(s, &end, 16);
                if (end == s) break;
                arr.push_back((uint32_t)v);
                s = end;
            }
            cur->a[n] = arr;
        } else if (cur && buf[0] == 'Z' && buf[1] == 'P') {
            char *s = buf + 3, *end;
            for (;;) {
                unsigned long v = strtoul(s, &end, 16);
                if (end == s) break;
                cur->pmem.push_back((uint32_t)v);
                s = end;
            }
        } else if (cur && buf[0] == 'Z' && buf[1] == 'M') {
            unsigned a; char hex[200];
            if (sscanf(buf + 3, "%x %199s", &a, hex) == 2)
                for (int j = 0; j < 64 && hex[2 * j]; j++) {
                    unsigned b; sscanf(hex + 2 * j, "%2x", &b);
                    cur->xram[a + j] = (uint8_t)b;
                }
        } else if (cur && buf[0] == 'Z' && buf[1] == 'E') {
            Ev e{}; e.kind = EV_Z; e.xba = cur->xba; e.pc = cur->pc; e.snap = (int)snaps.size() - 1; e.t = cur->t;
            evs.push_back(e);
            cur = nullptr;
        }
    }
    fclose(f);
}

// ---------------------------------------------------------------------------
// Core control
// ---------------------------------------------------------------------------
static int slots_in_sample = 0;

static void settle() {
    for (int i = 0; i < 16; i++) {
        if (R->tms57002__DOT__ph == 0 && R->tms57002__DOT__credit == 0 && !R->tms57002__DOT__sync_req &&
            !R->tms57002__DOT__host_req && top->pload_n == R->tms57002__DOT__pload_q &&
            top->cload_n == R->tms57002__DOT__cload_q)
            return;
        tick();
    }
    fprintf(stderr, "core does not settle\n");
    exit(3);
}
static void slot() {
    top->step = 1; tick(); top->step = 0;
    settle();
    slots_in_sample++;
}
static bool running() { return !R->tms57002__DOT__halted && R->tms57002__DOT__pload_q; }
static void do_sync(const uint32_t si[4]) {
    top->si0_l = si[0]; top->si0_r = si[1]; top->si1_l = si[2]; top->si1_r = si[3];
    top->sync = 1; tick(); top->sync = 0;
    settle();
    slots_in_sample = 0;
}

// ---------------------------------------------------------------------------
// Snapshots
// ---------------------------------------------------------------------------
static const uint64_t M52 = (1ULL << 52) - 1;

static void load_snap(const Snap &s) {
    auto V = [&](const char *n) -> uint64_t {
        auto it = s.v.find(n);
        if (it == s.v.end()) { fprintf(stderr, "snapshot lacks %s\n", n); exit(2); }
        return it->second;
    };
    uint32_t sti = (uint32_t)V("sti");
    R->tms57002__DOT__st0 = V("st0") & 0xffffff;
    R->tms57002__DOT__st1 = V("st1") & 0xffffff;
    R->tms57002__DOT__pc = V("pc") & 0xff;
    R->tms57002__DOT__ca = V("ca") & 0xff;
    R->tms57002__DOT__id = V("id") & 0xff;
    R->tms57002__DOT__ba0 = V("ba0") & 0xff;
    R->tms57002__DOT__xba = V("xba") & 0x7ffff;
    R->tms57002__DOT__aacc = V("aacc") & 0xffffffff;
    R->tms57002__DOT__macc = V("macc") & M52;
    R->tms57002__DOT__mw = V("macc_write") & M52;
    R->tms57002__DOT__xrd = V("xrd") & 0xffffff;
    R->tms57002__DOT__sa = V("sa") & 0xff;
    R->tms57002__DOT__halted = (sti & 0x20) ? 1 : 0;
    R->tms57002__DOT__pload_q = (sti & 1) ? 0 : 1;
    R->tms57002__DOT__cload_q = (sti & 2) ? 0 : 1;
    top->pload_n = R->tms57002__DOT__pload_q;
    top->cload_n = R->tms57002__DOT__cload_q;
    R->tms57002__DOT__su = (sti >> 3) & 3;
    R->tms57002__DOT__expect_sa = (sti & 4) ? 0 : 1;
    R->tms57002__DOT__hidx = 0;
    R->tms57002__DOT__upd_active = (sti & 0x400) ? 1 : 0;
    if (sti & 0xc0) { fprintf(stderr, "snapshot with an external access running\n"); exit(2); }
    R->tms57002__DOT__xm_cnt = 0;
    R->tms57002__DOT__ir_valid = 0;
    R->tms57002__DOT__credit = 0;
    R->tms57002__DOT__sync_req = 0;
    R->tms57002__DOT__host_req = 0;
    R->tms57002__DOT__ph = 0;
    const auto &si = s.a.at("si"), &so = s.a.at("so"), &upd = s.a.at("update");
    for (int k = 0; k < 4; k++) R->tms57002__DOT__si[k] = si[k] & 0xffffff;
    R->tms57002__DOT__so2 = so[2] & 0xffffff;
    R->tms57002__DOT__so3 = so[3] & 0xffffff;
    unsigned head = V("update_counter_head") & 15, tail = V("update_counter_tail") & 15;
    for (int k = 0; k < 16; k++) R->tms57002__DOT__upd[k] = upd[k];
    R->tms57002__DOT__upd_head = head;
    R->tms57002__DOT__upd_tail = tail;
    R->tms57002__DOT__upd_cnt = (head - tail) & 15;
    const auto &cm = s.a.at("cmem"), &dm = s.a.at("dmem0");
    for (int i = 0; i < 256; i++) {
        R->tms57002__DOT__cmem[i] = cm[i];
        R->tms57002__DOT__dmem[i] = dm[i] & 0xffffff;
        R->tms57002__DOT__pmem[i] = s.pmem[i] & 0xffffff;
    }
    for (int i = 0; i < 0x8000; i++)
        R->tms57002__DOT__u_xram__DOT__mem[i] = (uint16_t)(s.xram[2 * i] << 8 | s.xram[2 * i + 1]);
    top->eval();
}

static int max_diffs = 8;
// compare; returns number of differing items
static int compare_snap(const Snap &s, bool verbose) {
    int nd = 0;
    auto rep = [&](const char *what, uint64_t rtl, uint64_t mame) {
        if (rtl == mame) return;
        if (verbose && nd < max_diffs) printf("    %-12s rtl %llx mame %llx\n", what, (unsigned long long)rtl, (unsigned long long)mame);
        nd++;
    };
    auto V = [&](const char *n) { return s.v.at(n); };
    rep("st0", R->tms57002__DOT__st0, V("st0") & 0xffffff);
    rep("st1", R->tms57002__DOT__st1, V("st1") & 0xffffff);
    rep("pc", R->tms57002__DOT__pc, V("pc") & 0xff);
    rep("ca", R->tms57002__DOT__ca, V("ca") & 0xff);
    rep("id", R->tms57002__DOT__id, V("id") & 0xff);
    rep("ba0", R->tms57002__DOT__ba0, V("ba0") & 0xff);
    rep("xba", R->tms57002__DOT__xba, V("xba") & 0x7ffff);
    rep("aacc", R->tms57002__DOT__aacc, V("aacc") & 0xffffffff);
    rep("macc", R->tms57002__DOT__macc, V("macc") & M52);
    rep("macc_write", R->tms57002__DOT__mw, V("macc_write") & M52);
    rep("xrd", R->tms57002__DOT__xrd, V("xrd") & 0xffffff);
    rep("sa", R->tms57002__DOT__sa, V("sa") & 0xff);
    rep("so1_l", R->tms57002__DOT__so2, s.a.at("so")[2] & 0xffffff);
    rep("so1_r", R->tms57002__DOT__so3, s.a.at("so")[3] & 0xffffff);
    unsigned head = V("update_counter_head") & 15, tail = V("update_counter_tail") & 15;
    rep("upd_cnt", R->tms57002__DOT__upd_cnt, (head - tail) & 15);
    int dc = 0, dd = 0, dp = 0, dx = 0, first_x = -1;
    for (int i = 0; i < 256; i++) {
        if (R->tms57002__DOT__cmem[i] != s.a.at("cmem")[i]) {
            if (verbose && dc < 3) printf("    cmem[%02x]   rtl %08x mame %08x\n", i, R->tms57002__DOT__cmem[i], s.a.at("cmem")[i]);
            dc++;
        }
        if (R->tms57002__DOT__dmem[i] != (s.a.at("dmem0")[i] & 0xffffff)) {
            if (verbose && dd < 3) printf("    dmem0[%02x]  rtl %06x mame %06x\n", i, R->tms57002__DOT__dmem[i], s.a.at("dmem0")[i]);
            dd++;
        }
        if (R->tms57002__DOT__pmem[i] != (s.pmem[i] & 0xffffff)) dp++;
    }
    for (int i = 0; i < 0x8000; i++)
        if (R->tms57002__DOT__u_xram__DOT__mem[i] != (uint16_t)(s.xram[2 * i] << 8 | s.xram[2 * i + 1])) {
            if (first_x < 0) first_x = i;
            dx++;
        }
    if (verbose && (dc || dd || dp || dx))
        printf("    arrays: cmem %d, dmem0 %d, pmem %d, delay RAM %d words differ%s\n", dc, dd, dp, dx,
               first_x >= 0 ? (" (first " + std::to_string(first_x) + ")").c_str() : "");
    return nd + dc + dd + dp + dx;
}

// ---------------------------------------------------------------------------
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 2) { fprintf(stderr, "usage: tb <tms57.log> [--quiet] [--max-diffs N] [--resync-periodic] [--freerun]\n"); return 2; }
    bool quiet = false, resync_periodic = false, freerun = false;
    double last_t = 0;
    FILE *dump = nullptr;   // --dump <file>: per sync, CMEM 0-3 and 76-85, AACC, SO1 (debug)
    for (int i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "--quiet")) quiet = true;
        else if (!strcmp(argv[i], "--resync-periodic")) resync_periodic = true;
        else if (!strcmp(argv[i], "--freerun")) freerun = true;
        else if (!strcmp(argv[i], "--dump") && i + 1 < argc) dump = fopen(argv[++i], "w");
        else if (!strcmp(argv[i], "--max-diffs") && i + 1 < argc) max_diffs = atoi(argv[++i]);
    }
    load_log(argv[1]);
    printf("log: %zu events, %zu snapshots\n", evs.size(), snaps.size());

    top = new Vtms57002;
    R = top->rootp;
    top->rst = 1; top->pload_n = 1; top->cload_n = 1;
    for (int i = 0; i < 4; i++) tick();
    top->rst = 0; tick();

    bool started = false, compare = false;
    uint32_t xba = 0;                // the core's sample (MAME XBA convention)
    std::map<uint32_t, size_t> s_at; // xba -> index of its S event (built lazily, ahead)
    size_t s_scan = 0;
    uint64_t n_cmp = 0, n_l_bad = 0, n_r_bad = 0, n_16_bad = 0, n_excluded = 0, n_nos = 0, pos_bad = 0;
    uint64_t si_lsb = 0, n_s = 0, n_nonzero = 0;
    long first_bad = -1;
    int windows = 0;
    const uint32_t zero[4] = {0, 0, 0, 0};

    // the S event of sample x that lies ahead of event index i (MAME logs it after the sync)
    auto find_s = [&](uint32_t x, size_t from) -> const Ev * {
        for (size_t j = from > 512 ? from - 512 : 0; j < evs.size() && j < from + 4096; j++) {
            if (evs[j].kind == EV_S && evs[j].xba == x) return &evs[j];
            if (j > from && evs[j].kind == EV_S && ((x - evs[j].xba) & 0x7ffff) > 4 && ((x - evs[j].xba) & 0x7ffff) < 0x40000) break;
        }
        return nullptr;
    };
    (void)s_at; (void)s_scan;

    // compare the SO1 pair the core latched at the sync into sample nx
    auto after_sync = [&](uint32_t nx, const Ev *s, size_t ei) {
        if (dump) {
            fprintf(dump, "%x", nx);
            for (int k = 0; k < 4; k++) fprintf(dump, " %08x", R->tms57002__DOT__cmem[k]);
            for (int k = 76; k < 86; k++) fprintf(dump, " %08x", R->tms57002__DOT__cmem[k]);
            fprintf(dump, " %08x %06x %06x\n", R->tms57002__DOT__aacc, top->so1_l, top->so1_r);
        }
        if (s) {
            n_s++;
            for (int k = 0; k < 4; k++) if (s->si[k] & 0xff) { si_lsb++; break; }
        }
        if (!compare) { n_excluded++; return; }
        if (!s) { n_nos++; return; }
        if (s->pc >= 0x80) return;   // MAME's S line came after a DOMH
        n_cmp++;
        if ((s->so[2] | s->so[3]) & 0xffffff) n_nonzero++;
        bool bl = top->so1_l != (s->so[2] & 0xffffff), br = top->so1_r != (s->so[3] & 0xffffff);
        if (bl) n_l_bad++;
        if (br) n_r_bad++;
        if ((top->so1_l >> 8) != ((s->so[2] >> 8) & 0xffff) || (top->so1_r >> 8) != ((s->so[3] >> 8) & 0xffff)) n_16_bad++;
        if ((bl || br) && first_bad < 0) {
            first_bad = (long)ei;
            printf("first output mismatch at xba %x (near t %.6f): rtl L %06x R %06x, mame L %06x R %06x\n",
                   nx, last_t, top->so1_l, top->so1_r, s->so[2] & 0xffffff, s->so[3] & 0xffffff);
        }
    };

    // free-running time base (--freerun): a step every 12.5 / 33.8688 clocks,
    // a sync after every 384 steps, as the G-NET time base would drive it
    double acc = 0;
    int steps_in_sample = 0;
    uint64_t late = 0, sync_running = 0;
    // frozen: no time passes (MAME applied host inputs at one DSP position
    // in zero DSP time, its DSP being idle in the MN10200's timeslice)
    auto ftick = [&](size_t ei, bool frozen) {
        top->step = 0; top->sync = 0;
        if (frozen) {
        } else if (steps_in_sample >= 384) {
            uint32_t nx = (R->tms57002__DOT__xba - 1) & 0x7ffff;
            const Ev *s = find_s(nx, ei);
            const uint32_t *si = s ? s->si : zero;
            top->si0_l = si[0]; top->si0_r = si[1]; top->si1_l = si[2]; top->si1_r = si[3];
            top->sync = 1;
            steps_in_sample = 0;
            if (running()) {
                sync_running++;
                if (sync_running < 4) printf("sync while running: xba %x pc %x credit %d\n", R->tms57002__DOT__xba,
                                             R->tms57002__DOT__pc, R->tms57002__DOT__credit);
            }
        } else {
            acc += 12.5 / 33.8688;
            if (acc >= 1.0) { acc -= 1.0; top->step = 1; steps_in_sample++; }
        }
        uint32_t ox = R->tms57002__DOT__xba;
        tick();
        uint32_t nx = R->tms57002__DOT__xba;
        if (nx != ox) after_sync(nx, find_s(nx, ei), ei);
    };

    auto advance_free = [&](uint32_t tx, uint32_t tpc, size_t ei) {
        for (long guard = 0;; guard++) {
            uint32_t d = (R->tms57002__DOT__xba - tx) & 0x7ffff;
            if (d > 0x40000) { late++; break; }                   // the core is past the sample
            if (d == 0) {
                if (!running()) break;
                if (R->tms57002__DOT__pc == tpc && R->tms57002__DOT__ph != 2) { top->dbg_hold = 1; break; }
                if (R->tms57002__DOT__pc > tpc || (R->tms57002__DOT__pc == tpc && R->tms57002__DOT__ph == 2)) { late++; break; }
            }
            top->dbg_hold = 0;
            ftick(ei, false);
            if (guard > 400000000L) { fprintf(stderr, "cannot reach xba %x pc %x\n", tx, tpc); exit(4); }
        }
    };

    auto advance_to = [&](uint32_t tx, uint32_t tpc, size_t ei) {
        if (freerun) { advance_free(tx, tpc, ei); return; }
        // finish samples until the core's XBA equals tx, then run to tpc
        int guard = 0;
        while (R->tms57002__DOT__xba != tx) {
            while (running() && slots_in_sample < 384) slot();
            uint32_t nx = (R->tms57002__DOT__xba - 1) & 0x7ffff;
            const Ev *s = find_s(nx, ei);
            do_sync(s ? s->si : zero);
            if (R->tms57002__DOT__xba != nx) { fprintf(stderr, "sync blocked at xba %x\n", nx); break; }
            after_sync(nx, s, ei);
            if (++guard > 600000) { fprintf(stderr, "cannot reach xba %x\n", tx); exit(4); }
        }
        if (!running()) return;
        while (running() && R->tms57002__DOT__pc != tpc && slots_in_sample < 384) slot();
        if (R->tms57002__DOT__pc != tpc && compare) {
            pos_bad++;
            if (!quiet && pos_bad < 5) printf("position: event at xba %x pc %x, core pc %x\n", tx, tpc, R->tms57002__DOT__pc);
        }
    };

    // host inputs; in --freerun the core is held at the event's position
    // until the request is taken
    auto apply_wait = [&](size_t ei) {
        if (!freerun) { tick(); top->host_wr = 0; settle(); return; }
        for (int k = 0; k < 8; k++) {
            ftick(ei, true);
            top->host_wr = 0;
            if (!R->tms57002__DOT__host_req && top->pload_n == R->tms57002__DOT__pload_q &&
                top->cload_n == R->tms57002__DOT__cload_q) return;
        }
    };

    for (size_t i = 0; i < evs.size(); i++) {
        const Ev &e = evs[i];
        if (!started) {
            if (e.kind == EV_Z && snaps[e.snap].tag == "pload") {
                load_snap(snaps[e.snap]);
                started = true; compare = false;
                slots_in_sample = (int)e.pc;  // MAME runs NOPs from PC 0 after each sync
                printf("start: pload snapshot t %.6f xba %x pc %x\n", e.t, e.xba, e.pc);
            }
            continue;
        }
        // XBA jump: Zoom reset (the device reset sets XBA to 0); wait for a resync
        uint32_t dist = (R->tms57002__DOT__xba - e.xba) & 0x7ffff;
        if (dist > 65536 && e.kind != EV_Z) {
            if (compare && !quiet) printf("xba jump %x -> %x at t %.6f: waiting for a resync\n", R->tms57002__DOT__xba, e.xba, e.t);
            compare = false;
            // keep the core quiet until the resync
            R->tms57002__DOT__xba = e.xba; R->tms57002__DOT__halted = 1;
            continue;
        }
        if (e.kind == EV_Z) {
            const Snap &s = snaps[e.snap];
            if (dist <= 65536) advance_to(e.xba, e.pc, i);
            last_t = s.t;
            if (s.tag == "resync") {
                windows++;
                int nd = compare_snap(s, !quiet);
                printf("resync t %.6f xba %x: %d differences before loading%s\n", s.t, s.xba, nd, compare ? "" : " (download window)");
                load_snap(s);
                slots_in_sample = (int)s.pc;  // approximate: the core is idle
                steps_in_sample = 0;
                compare = true;
            } else if (s.tag == "periodic") {
                if (compare) {
                    int nd = compare_snap(s, !quiet);
                    printf("periodic t %.6f xba %x: %d differences\n", s.t, s.xba, nd);
                    if (resync_periodic && nd) load_snap(s);
                }
            }
            continue;
        }
        if (e.kind == EV_S) { advance_to(e.xba, e.pc, i); continue; }  // inputs are taken at the syncs
        // host event
        last_t = e.t;
        advance_to(e.xba, e.pc, i);
        if (e.rw != 'W') continue;
        if (e.addr == 0xfe64 && e.mask == 0x00ff) {
            uint32_t v = e.data & 0xff;
            if (!(v & 1) && top->pload_n) { compare = false; }  // download window starts
            top->pload_n = v & 1; top->cload_n = (v >> 1) & 1;
            apply_wait(i);
        } else if (e.addr == 0xc00000 && e.mask == 0x00ff) {
            top->host_din = e.data & 0xff; top->host_wr = 1;
            apply_wait(i);
        }
    }

    printf("samples compared %llu (excluded in download windows %llu, no MAME sample %llu), resync windows %d\n",
           (unsigned long long)n_cmp, (unsigned long long)n_excluded, (unsigned long long)n_nos, windows);
    printf("compared samples with a nonzero MAME output: %llu\n", (unsigned long long)n_nonzero);
    printf("SO1 24-bit mismatches: left %llu, right %llu; 16-bit (either side) %llu; position mismatches %llu\n",
           (unsigned long long)n_l_bad, (unsigned long long)n_r_bad, (unsigned long long)n_16_bad, (unsigned long long)pos_bad);
    printf("MAME samples with serial input bits 7-0 set: %llu of %llu\n", (unsigned long long)si_lsb, (unsigned long long)n_s);
    if (freerun) printf("free-running time base: %llu events reached late, %llu syncs while the program ran\n",
                        (unsigned long long)late, (unsigned long long)sync_running);
    printf("unsupported flag %d, clocks %llu\n", top->dbg_unsup, (unsigned long long)clocks);
    int rc = (n_l_bad || n_r_bad || pos_bad) ? 1 : 0;
    delete top;
    return rc;
}
