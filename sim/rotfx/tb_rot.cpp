// Rotation with the scandoubler Fx through gnet_ddr3_arb (rot_top.sv).
//
//   tb_rot width=<256|320|512|640> fx=<0..7> [sd=0|1] [frames=6] [busy=10]
//          [lat=14] [jit=8] [core=1] [seed=1] [ccw=1]
//
// clk_vid 53.693175 MHz (G-NET fixed video PLL), clk_2x 67.7376 MHz,
// unrelated phases. The video source is G-NET's raster as the core's
// video_aspect register gives it: 3,413 clk_vid per line, 263 lines, one dot
// every 10/8/5/4 clk_vid for 256/320/512/640 dots, 240 active lines, sync
// and blanking changing on the dot enable only. The DDRAM model and the
// GPU-like core client follow sim/ddr3arb/tb.cpp and sim/zoomddr3/tb_zd3.cpp.
// Every rotation write screen_rotate makes is recorded; at the end (after the
// FIFO drains) each written pixel must hold its last value in the model
// (dropped or reordered writes show as wrong pixels). IMAGE: one whole frame
// of screen_rotate's input stream (after the 4th VS) compared with the
// source raster, allowing 2x line and 2x pixel replication and up to 2
// leading lines. stall_us=<n> holds BUSY once in frame 4 (stress).
// Build with sim/rotfx/build.sh <0|1> (rot_top FEED; 1 = the
// pre-scandoubler feed PSX.sv uses); nice -n 15.
#include "Vrot_top.h"
#include "verilated.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <map>
#include <random>
#include <string>
#include <unordered_map>

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

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    std::map<std::string, long> kv = {{"width", 320}, {"fx", 0}, {"sd", 0}, {"frames", 6}, {"busy", 10}, {"lat", 14}, {"jit", 8},
                                      {"core", 1}, {"seed", 1}, {"ccw", 1}, {"stall_us", 0}};
    for (int i = 1; i < argc; i++) {
        std::string s = argv[i];
        auto e = s.find('=');
        if (e == std::string::npos || !kv.count(s.substr(0, e))) continue;
        kv[s.substr(0, e)] = atol(s.c_str() + e + 1);
    }
    const int W = kv["width"], DIV = W == 256 ? 10 : W == 320 ? 8 : W == 512 ? 5 : 4;
    const int busy_pct = kv["busy"], lat_base = kv["lat"], lat_jit = kv["jit"];
    std::mt19937 rng(kv["seed"]);
    auto *t = new Vrot_top;
    t->fx = kv["fx"]; t->forced_sd = kv["sd"]; t->rot_en = 1; t->rot_ccw = kv["ccw"];
    t->arb_rst = 1;
    t->clk_vid = 0; t->clk2x = 0; t->eval();
    Mem mem;
    long errors = 0;
    auto err = [&](const char *m) { if (errors++ < 10) printf("ERROR: %s\n", m); };

    // DDRAM model
    struct Rd { uint32_t a; int len, beat; long first; };
    std::deque<Rd> q; long last_beat = -1; int wb_left = 0; uint32_t wb_addr = 0;
    // core client
    enum { CI, CRD, CWR } c_st = CI; int c_len = 0, c_got = 0; long c_reads = 0;
    // video
    const int HT = 3413, VT = 263, HA0 = 650, VA0 = 16, VA = 240;
    int hc = 0, vc = 0, frame = 0, divc = 0;
    long vid = 0, c2 = 0;
    long fbv = 0;
    // observation
    std::unordered_map<uint32_t, uint32_t> expect;   // byte address -> pixel
    long rot_writes = 0, de_ce = 0, frame_writes = 0;
    std::vector<long> writes_per_frame;
    const long frames = kv["frames"];
    std::vector<std::vector<uint32_t>> cap; int vsr = 0; bool cap_on = false;
    std::vector<int> vs_frame;   // source frame at each VS rise

    uint64_t n_vid = 0, n_2x = 5000;
    const uint64_t HV = 9312, H2 = 7382;   // half periods in ps
    bool lv = false, l2 = false;
    bool done = false;
    long drain = 0;
    while (!done) {
        uint64_t now = std::min(n_vid, n_2x);
        bool rv = (now == n_vid && !lv), r2 = (now == n_2x && !l2);
        // ---- pre-edge samples
        bool w_we = false; uint32_t w_a = 0; uint64_t w_d = 0; int w_be = 0;
        if (rv && t->ce_out) {
            // the rotation input stream: capture the frame after the 4th VS rise
            static bool old_vs = false, old_de = false;
            bool v = t->vs_out, d = t->de_out;
            if (v && !old_vs) { vsr++; if (vsr == 5) { cap.clear(); cap_on = true; } else if (vsr == 6) cap_on = false; }
            if (cap_on) {
                if (d) { if (!old_de) cap.emplace_back(); cap.back().push_back((uint32_t)t->rgb_out); }
            }
            old_vs = v; old_de = d;
        }
        if (rv) {
            w_we = t->rot_we; w_a = t->rot_addr; w_d = t->rot_din; w_be = t->rot_be;
            if (t->ce_out && t->de_out) de_ce++;
        }
        bool d_cmd = false, d_busy = false, d_beat = false, c_dr = false, c_acc = false;
        if (r2) {
            d_cmd = t->ddr_rd || t->ddr_we; d_busy = t->ddr_busy; d_beat = t->ddr_dout_ready;
            c_dr = t->c_dout_ready; c_acc = (t->c_rd || t->c_we) && !t->c_busy;
            if (d_cmd && !d_busy) {
                if (t->ddr_rd) {
                    int L = lat_base + (int)(rng() % (lat_jit + 1));
                    q.push_back({(uint32_t)t->ddr_addr, t->ddr_burstcnt, 0, c2 + L});
                } else {
                    uint32_t a;
                    if (wb_left) { a = ++wb_addr; wb_left--; }
                    else { a = t->ddr_addr; if (t->ddr_burstcnt > 1) { wb_left = t->ddr_burstcnt - 1; wb_addr = a; } }
                    mem.wr(a, t->ddr_din, t->ddr_be);
                }
            }
            if (d_beat) { Rd &h = q.front(); if (++h.beat == h.len) q.pop_front(); last_beat = c2; }
            if (t->own_ovf) err("owner FIFO overflow");
        }
        if (w_we) {
            rot_writes++; frame_writes++;
            uint32_t byte = w_a * 8 + ((w_be & 0xF0) ? 4 : 0);
            expect[byte] = (w_be & 0xF0) ? (uint32_t)(w_d >> 32) : (uint32_t)w_d;
        }
        // ---- edges
        if (now == n_vid) { lv = !lv; t->clk_vid = lv; n_vid += HV; }
        if (now == n_2x) { l2 = !l2; t->clk2x = l2; n_2x += H2; }
        t->eval();
        // ---- post-edge inputs
        if (rv) {
            vid++;
            if (frame < frames) {
                // dot enable and the raster registered on it
                t->ce_pix = 0;
                if (++divc == DIV) {
                    divc = 0;
                    t->ce_pix = 1;
                    bool ha = hc >= HA0 && hc < HA0 + W * DIV, va = vc >= VA0 && vc < VA0 + VA;
                    t->hs = hc < 250; t->vs = vc < 3;
                    t->hb = !ha; t->vb = !va;
                    int x = (hc - HA0) / DIV, y = vc - VA0;
                    t->rgb = (ha && va) ? (uint32_t)(hash64(((uint64_t)frame << 32) | ((uint64_t)y << 16) | x) & 0xFFFFFF) : 0;
                }
                if (++hc == HT) {
                    hc = 0;
                    if (++vc == VT) { vc = 0; frame++; writes_per_frame.push_back(frame_writes); frame_writes = 0; }
                }
            } else {
                t->ce_pix = 0;
                if (++drain > 200000) done = true;
            }
            // scaler vblank: 1 ms high every 16.683 ms
            fbv = (fbv + 1) % 895800;
            t->fb_vbl = fbv < 53693;
        }
        if (r2) {
            c2++;
            if (c2 == 20) t->arb_rst = 0;
            if (c_dr) { if (++c_got == c_len) { c_st = CI; c_reads++; } }
            if (c_acc) { if (c_st == CWR) c_st = CI; t->c_rd = 0; t->c_we = 0; }
            if (kv["core"] && c_st == CI && !t->c_rd && !t->c_we && c2 > 30 && frame < frames) {
                int r = rng() % 100;
                if (r < 45) {
                    static const int lens[4] = {1, 4, 80, 128};
                    c_len = lens[rng() % 4]; c_got = 0;
                    t->c_rd = 1; t->c_addr = 0x6000000 + ((rng() % 0x40000) & ~127u); t->c_burstcnt = c_len; c_st = CRD;
                } else if (r < 90) {
                    t->c_we = 1; t->c_addr = 0x6000000 + (rng() % 0x40000); t->c_din = ((uint64_t)rng() << 32) | rng();
                    t->c_be = 0xFF; t->c_burstcnt = 1; c_st = CWR;
                }
            }
            // optional: BUSY held stall_us once, from the middle of frame 4's active area
            static long st_from = -1;
            if (st_from < 0 && frame == 4 && vc == 120) st_from = c2;
            bool st = st_from >= 0 && c2 < st_from + (long)(kv["stall_us"] * 67.7376);
            t->ddr_busy = (int)(rng() % 100) < busy_pct || (c2 % 3000) < 20 || st;
            bool rdy = false;
            if (!q.empty()) {
                Rd &h = q.front();
                long e = std::max(h.first, h.beat == 0 ? last_beat + 1 : 0L);
                if (h.beat > 0) e = last_beat + 1;
                if (e <= c2) { rdy = true; t->ddr_dout = mem.rd(h.a + h.beat); }
            }
            t->ddr_dout_ready = rdy;
        }
        if (rv || r2) t->eval();
    }
    // image check of the captured frame against the source (source frames 2..6)
    {
        size_t L = cap.size(), Wc = L ? cap[0].size() : 0;

        int ry = (L >= 480) ? 2 : 1, rx = (Wc >= (size_t)(2 * W)) ? 2 : 1;
        long best = -1; int bf = -1, bdy = 0;
        const size_t WX = (size_t)W * rx;
        for (int f = 2; f <= 6; f++) for (int dy = 0; dy <= 2; dy++) {
            long eq = 0;
            for (size_t y = dy; y < L; y++) for (size_t x = 0; x < cap[y].size() && x < WX; x++) {
                uint32_t sv = (uint32_t)(hash64(((uint64_t)f << 32) | ((uint64_t)((y - dy) / ry) << 16) | (x / rx)) & 0xFFFFFF);
                if (cap[y][x] == sv) eq++;
            }
            if (eq > best) { best = eq; bf = f; bdy = dy; }
        }
        long cmp_tot = 0; for (size_t y = bdy; y < L; y++) cmp_tot += std::min(cap[y].size(), WX);
        std::map<size_t, int> lh; for (auto &l : cap) lh[l.size()]++;
        printf("IMAGE lines %zu, widths:", L); for (auto &e : lh) printf(" %zu x%d", e.first, e.second);
        printf("; source frame %d, %d leading line(s); %ld of %ld pixels (first %zu per line) equal the source (%dx%d)\n",
               bf, bdy, best, cmp_tot, WX, rx, ry);
    }
    long wrong = 0;
    uint64_t csum = 0;
    for (auto &e : expect) csum ^= hash64(((uint64_t)e.first << 32) | e.second);
    for (auto &e : expect) {
        uint64_t q64 = mem.rd(e.first >> 3);
        uint32_t got = (e.first & 4) ? (uint32_t)(q64 >> 32) : (uint32_t)q64;
        if (got != e.second) wrong++;
    }
    long maxw = 0;
    for (size_t i = 2; i < writes_per_frame.size(); i++) maxw = std::max(maxw, writes_per_frame[i]);
    printf("RESULT width %d fx %ld sd %ld busy %d lat %d+%d stall %ld us: rotation writes %ld (max per frame %ld, %.1f M/s over the frame), pixels %zu, "
           "wrong %ld; FIFO high-water %d of 512, rot_ovf %d, own_ovf %d; FB %ux%u en %d; core reads %ld; errors %ld; image checksum %016llx\n",
           W, kv["fx"], kv["sd"], busy_pct, lat_base, lat_jit, kv["stall_us"], rot_writes, maxw, maxw * 59.83 / 1e6, expect.size(), wrong, (int)t->rot_hiwater, (int)t->rot_ovf,
           (int)t->own_ovf, t->fb_width, t->fb_height, (int)t->fb_en, c_reads, errors, (unsigned long long)csum);
    delete t;
    return 0;
}
