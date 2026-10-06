// gnet_ddr3_arb testbench: four clients against a DDRAM port model.
//
// Clocks: clk 67.7376 MHz (14,762 ps), rot_clk 53.693 MHz (18,624 ps).
// Port model: random BUSY (busy_pct), a 20-cycle BUSY run every 3,000
// cycles, read latency base + uniform 0..jit, in-order beats; memory is a
// map of qwords, unwritten qwords read as hash(address); writes apply
// at acceptance, write bursts take the next beats as address + i.
// Clients (disjoint regions, each checks its own read data):
//   C  GPU-like: one read in flight (1, 4, 80 or 128 beats) or a single
//      write, Avalon hold; reads back what it wrote
//   G  glue: 64-beat reads, 4-beat write bursts, reads back the bursts
//   Z  Zoom: up to 8 line reads in flight, random lines, in-order check
//   R  rotation: screen_rotate's pattern on rot_clk, 320 pixels per line of
//      427 rot_clk cycles at one per 8, 960-byte stride; at the end every
//      pixel's qword half must hold the last value written
// Checks: read data, Avalon stability of the downstream command while BUSY,
// no acknowledge in reset (the Zoom client already requests in reset),
// no owner FIFO overflow, rotation FIFO overflow only in the stall mode.
// Mode "stall" holds BUSY for 120 us once: the rotation FIFO (512) must
// overflow and set rot_ovf.
//
//   obj/Vgnet_ddr3_arb <seed> <cycles> <busy_pct> <lat_base> <lat_jit> [stall]
#include "Vgnet_ddr3_arb.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <random>
#include <string>
#include <unordered_map>
#include <vector>

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

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    unsigned seed = argc > 1 ? atoi(argv[1]) : 1;
    long cycles = argc > 2 ? atol(argv[2]) : 2000000;
    int busy_pct = argc > 3 ? atoi(argv[3]) : 10;
    int lat_base = argc > 4 ? atoi(argv[4]) : 14, lat_jit = argc > 5 ? atoi(argv[5]) : 8;
    bool stall = argc > 6 && std::string(argv[6]) == "stall";
    std::mt19937 rng(seed);
    auto* t = new Vgnet_ddr3_arb;
    Mem mem;
    int errors = 0;
    auto err = [&](const char* m, long c) { if (errors++ < 20) printf("ERROR at cycle %ld: %s\n", c, m); };

    // port model state
    struct Rd { uint32_t a; int len, beat; long first; };
    std::deque<Rd> q;
    long last_beat = -1;
    int wb_left = 0; uint32_t wb_addr = 0;
    // previous downstream command, for the stability check
    bool p_cmd = false, p_busy = false, p_rd = false; uint32_t p_addr = 0; int p_bc = 0; uint64_t p_din = 0; int p_be = 0;

    // client C (core)
    enum { CI, CRD, CWR } c_st = CI;
    uint32_t c_a = 0; int c_len = 0, c_got = 0; std::unordered_map<uint32_t, uint64_t> c_shadow;
    long c_reads = 0, c_lat_sum = 0, c_lat_max = 0, c_issue = 0;
    // client G (glue)
    enum { GI, GRD, GWR } g_st = GI;
    uint32_t g_a = 0; int g_len = 0, g_got = 0, g_beat = 0; long g_bursts = 0;
    std::unordered_map<uint32_t, uint64_t> g_shadow;
    // client Z (Zoom)
    std::deque<std::pair<uint32_t, long>> z_q;   // line, ready cycle
    long z_reads = 0, z_lat_max = 0, z_lat_sum = 0;
    const uint32_t ZQB = 0x6200000;
    // client R (rotation), rot_clk domain
    int r_div = 0, r_x = 0, r_hc = 0, r_y = 0; long r_writes = 0;
    std::unordered_map<uint32_t, uint32_t> r_expect;   // byte address -> pixel

    t->rst = 1; t->clk = 0; t->rot_clk = 0; t->eval();
    long cyc = 0;
    uint64_t now = 0, next_clk = 7381, next_rot = 9312;
    long stall_from = stall ? 300000 : -1, stall_to = stall ? 300000 + 8130 : -1;   // 120 us

    while (cyc < cycles + 200000) {
        bool run = cyc < cycles;
        if (next_rot <= next_clk) {
            now = next_rot; next_rot += 9312;
            if (!t->rot_clk) {
                // rising edge of rot_clk: the DUT samples the write set before
                t->rot_clk = 1; t->eval();
                bool we = false;
                if (cyc > 100 && run) {
                    // 320 active pixels at one per 8 clocks, line of 3,413 clocks
                    if (r_hc < 320 * 8 && (r_hc & 7) == 0) {
                        uint32_t byte = 0x24000000u + (uint32_t)r_x * 960u + (uint32_t)r_y * 4u;
                        uint32_t pix = (uint32_t)hash64(r_writes) & 0xFFFFFF;
                        t->rot_addr = byte >> 3;
                        t->rot_din = ((uint64_t)pix << 32) | pix;
                        t->rot_be = (byte & 4) ? 0xF0 : 0x0F;
                        we = true;
                        r_expect[byte] = pix;
                        r_writes++;
                        r_x = (r_x + 1) % 320;
                    }
                    if (++r_hc == 3413) { r_hc = 0; r_y = (r_y + 1) % 240; }
                }
                t->rot_we = we;
                t->eval();
            } else {
                t->rot_clk = 0; t->eval();
            }
            continue;
        }
        now = next_clk; next_clk += 7381;
        t->clk = !t->clk;
        if (!t->clk) { t->eval(); continue; }

        // ---------------- rising edge of clk: sample, then update
        bool busy = t->ddr_busy;
        bool cmd = t->ddr_rd || t->ddr_we;
        // Avalon: a command waiting on BUSY must not change
        if (p_cmd && p_busy) {
            if (!cmd || t->ddr_rd != p_rd || t->ddr_addr != p_addr || t->ddr_burstcnt != p_bc ||
                (!p_rd && (t->ddr_din != p_din || t->ddr_be != p_be))) err("downstream command changed while BUSY", cyc);
        }
        p_cmd = cmd; p_busy = busy; p_rd = t->ddr_rd; p_addr = t->ddr_addr; p_bc = t->ddr_burstcnt; p_din = t->ddr_din; p_be = t->ddr_be;
        if (cmd && !busy) {
            if (t->ddr_rd) {
                if (wb_left) err("read inside a write burst", cyc);
                int L = lat_base + (int)(rng() % (lat_jit + 1));
                q.push_back({(uint32_t)t->ddr_addr, t->ddr_burstcnt, 0, cyc + L});
            } else {
                uint32_t a;
                if (wb_left) { a = ++wb_addr; wb_left--; }
                else { a = t->ddr_addr; if (t->ddr_burstcnt > 1) { wb_left = t->ddr_burstcnt - 1; wb_addr = a; } }
                mem.wr(a, t->ddr_din, t->ddr_be);
            }
        }
        bool beat = t->ddr_dout_ready;
        uint64_t data = t->ddr_dout;
        // client inputs from the DUT for this edge
        bool c_dr = t->c_dout_ready, g_dr = t->g_dout_ready, z_rv = t->z_rvalid;
        bool c_acc = (t->c_rd || t->c_we) && !t->c_busy;
        bool g_acc = (t->g_rd || t->g_we) && !t->g_busy;
        bool z_acc = t->z_req && t->z_ready;
        if (beat) {
            Rd& h = q.front();
            if (++h.beat == h.len) q.pop_front();
            last_beat = cyc;
        }
        if (t->own_ovf) err("owner FIFO overflow", cyc);
        // in reset nothing may be acknowledged (Zoom requests arrive in reset)
        if (t->rst && (t->z_ready || !t->c_busy || !t->g_busy)) err("acknowledge in reset", cyc);

        t->eval();     // posedge evaluated with the current inputs
        cyc++;
        if (cyc == 20) t->rst = 0;

        // client C
        if (c_dr) {
            uint64_t want = c_shadow.count(c_a + c_got) ? c_shadow[c_a + c_got] : hash64(c_a + c_got);
            if (data != want) err("core read data", cyc);
            if (c_got == 0) { long l = cyc - c_issue; c_lat_sum += l; c_lat_max = std::max(c_lat_max, l); c_reads++; }
            if (++c_got == c_len) c_st = CI;
        }
        if (c_acc) {
            if (c_st == CWR) c_st = CI;
            else if (c_st == CRD) { c_issue = cyc; }
            t->c_rd = 0; t->c_we = 0;
        }
        if (c_st == CI && !t->c_rd && !t->c_we && run && cyc > 30) {
            int r = rng() % 100;
            if (r < 45) {                 // read
                static const int lens[4] = {1, 4, 80, 128};
                c_len = lens[rng() % 4]; c_got = 0;
                c_a = 0x6000000 + ((rng() % 0x40000) & ~127u);
                t->c_rd = 1; t->c_addr = c_a; t->c_burstcnt = c_len; c_st = CRD;
            } else if (r < 90) {          // single write
                uint32_t a = 0x6000000 + (rng() % 0x40000);
                uint64_t d = ((uint64_t)rng() << 32) | rng();
                c_shadow[a] = d;
                t->c_we = 1; t->c_addr = a; t->c_din = d; t->c_be = 0xFF; t->c_burstcnt = 1; c_st = CWR;
            }
        }
        // client G
        if (g_dr) {
            uint64_t want = g_shadow.count(g_a + g_got) ? g_shadow[g_a + g_got] : hash64(g_a + g_got);
            if (data != want) err("glue read data", cyc);
            if (++g_got == g_len) g_st = GI;
        }
        if (g_acc) {
            if (g_st == GWR) {
                g_shadow[g_a + g_beat] = t->g_din;
                if (++g_beat == 4) { g_st = GI; t->g_we = 0; }
                else { t->g_din = hash64(g_a * 7 + g_beat); }
            } else t->g_rd = 0;
            if (g_st != GWR) { t->g_we = 0; }
        }
        if (g_st == GI && !t->g_rd && !t->g_we && run && cyc > 30 && rng() % 400 == 0) {
            g_bursts++;
            if (rng() % 2) {
                // 64-beat read, from the card area or back from the burst area
                g_a = (rng() % 2 ? 0x6800000 + (rng() % 0x10000) : 0x6900000 + (rng() % 0x1000)) & ~63u;
                g_len = 64; g_got = 0;
                t->g_rd = 1; t->g_addr = g_a; t->g_burstcnt = 64; g_st = GRD;
            } else {
                g_a = 0x6900000 + ((rng() % 0x1000) & ~3u); g_beat = 0;
                t->g_we = 1; t->g_addr = g_a; t->g_burstcnt = 4; t->g_be = 0xFF; t->g_din = hash64(g_a * 7); g_st = GWR;
            }
        }
        // client Z
        if (z_rv) {
            if (z_q.empty()) err("Zoom rvalid with nothing outstanding", cyc);
            else {
                uint32_t line = z_q.front().first;
                if (data != hash64(ZQB + line)) err("Zoom read data", cyc);
                long l = cyc - z_q.front().second; z_lat_sum += l; z_lat_max = std::max(z_lat_max, l); z_reads++;
                z_q.pop_front();
            }
        }
        if (z_acc) { z_q.push_back({(uint32_t)t->z_line, cyc}); t->z_req = 0; }
        if (!t->z_req && run && z_q.size() < 8 && rng() % 60 == 0) {
            t->z_req = 1; t->z_line = 0x40000 + (rng() % 0xD0000);
        }

        // port outputs for the next cycle
        bool b = (int)(rng() % 100) < busy_pct || (cyc % 3000) < 20 || (cyc >= stall_from && cyc < stall_to);
        t->ddr_busy = b;
        bool rdy = false;
        if (!q.empty()) {
            Rd& h = q.front();
            long e = std::max(h.first, h.beat == 0 ? last_beat + 1 : 0L);
            if (h.beat > 0) e = last_beat + 1;
            if (e <= cyc) { rdy = true; t->ddr_dout = mem.rd(h.a + h.beat); }
        }
        t->ddr_dout_ready = rdy;
        t->eval();
    }

    // rotation: every pixel holds the last value written
    long r_bad = 0;
    for (auto& kv : r_expect) {
        uint32_t byte = kv.first;
        uint64_t q64 = mem.rd(byte >> 3);
        uint32_t got = (byte & 4) ? (uint32_t)(q64 >> 32) : (uint32_t)q64;
        if (got != kv.second) r_bad++;
    }
    if (!stall && r_bad) { char m[64]; snprintf(m, sizeof m, "%ld rotation pixels wrong", r_bad); err(m, cyc); }
    if (!stall && t->rot_ovf) err("rotation FIFO overflow", cyc);
    if (stall && !t->rot_ovf) err("stall mode: rot_ovf not set", cyc);
    printf("cycles %ld  core reads %ld (lat mean %.1f max %ld)  zoom reads %ld (lat mean %.1f max %ld)  glue ops %ld  rot writes %ld  rot hiwater %d  rot_ovf %d  rot pixels wrong %ld\n",
           cyc, c_reads, c_reads ? (double)c_lat_sum / c_reads : 0.0, c_lat_max, z_reads,
           z_reads ? (double)z_lat_sum / z_reads : 0.0, z_lat_max, g_bursts, r_writes, (int)t->rot_hiwater, (int)t->rot_ovf, r_bad);
    printf("%s (%d errors)\n", errors ? "FAIL" : "PASS", errors);
    delete t;
    return errors ? 1 : 0;
}
