// Replay testbench for rtl/gnet/gnet_fc.sv against a MAME 0.288 glue trace
// (tools/mame/glue_trace.lua). Every main-CPU access is driven at its MAME
// time (cycle = t * CLK_HZ); every read is compared; at the end the flash
// storage is compared with MAME's NVRAM at exit and the card image with
// MAME's (optional).
//
//   tb_gnet_fc --trace glue.zst --card <set>.img --idnt <set>.idnt --cis <set>.cis
//              --key <set>.key --u30 flash.u30 [--warm <nvram dir>]
//              [--nvram <MAME nvram dir at exit>] [--card-out <img>]
//              [--card-ref <MAME card image at exit>] [--lat N] [--max-mis N]
//              [--t-end S]
// Game data never leaves sim/gnet/work/ (gitignored).
#include "Vgnet_fc.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <string>
#include <vector>
#include <map>

#ifndef CLK_HZ
#define CLK_HZ 33868800ull
#endif

static Vgnet_fc *top;
static uint64_t cyc = 0;
static std::vector<uint16_t> flash[5];
static const uint32_t FLASH_WORDS[5] = {1u << 20, 1u << 18, 1u << 20, 1u << 20, 1u << 20};
static std::vector<uint8_t> card;
static std::vector<char> card_dirty;   // per sector
static int lat = 2;
static int fm_cnt = -1, cm_cnt = -1;

static std::vector<uint8_t> readfile(const std::string &p) {
    std::vector<uint8_t> v;
    FILE *f = fopen(p.c_str(), "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", p.c_str()); exit(2); }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    v.resize(n); if (n && fread(v.data(), 1, n, f) != (size_t)n) exit(2); fclose(f);
    return v;
}

// memory port models: ack after `lat` cycles, data/write at ack
static void mem_service() {
    if (top->fmem_req && !top->fmem_ack) {
        if (fm_cnt < 0) fm_cnt = lat;
        if (fm_cnt == 0) {
            unsigned c = top->fmem_chip, a = top->fmem_addr & (FLASH_WORDS[c] - 1);
            if (top->fmem_we) flash[c][a] = top->fmem_wdata;
            else top->fmem_rdata = flash[c][a];
            top->fmem_ack = 1; fm_cnt = -1;
        } else fm_cnt--;
    } else top->fmem_ack = 0;
    if (top->cmem_req && !top->cmem_ack) {
        if (cm_cnt < 0) cm_cnt = lat;
        if (cm_cnt == 0) {
            uint64_t a = (uint64_t)top->cmem_addr * 2;
            if (a + 1 < card.size()) {
                if (top->cmem_we) {
                    card[a] = top->cmem_wdata & 0xff; card[a + 1] = top->cmem_wdata >> 8;
                    card_dirty[a / 512] = 1;
                } else top->cmem_rdata = card[a] | (card[a + 1] << 8);
            } else top->cmem_rdata = 0xffff;
            top->cmem_ack = 1; cm_cnt = -1;
        } else cm_cnt--;
    } else top->cmem_ack = 0;
}

static void tick() {
    top->clk = 0; top->eval();
    mem_service();
    top->clk = 1; top->eval();
    cyc++;
}

static void run_until(uint64_t c) { while (cyc < c) tick(); }

static uint64_t late_max = 0, late_sum = 0, n_acc = 0;
// one CPU access; returns read data
static uint32_t access(uint64_t when, bool we, uint32_t addr, uint32_t data, uint32_t mask) {
    run_until(when);
    if (cyc > when) { uint64_t l = cyc - when; late_sum += l; if (l > late_max) late_max = l; }
    n_acc++;
    uint8_t be = 0;
    for (int i = 0; i < 4; i++) if (mask & (0xffu << (8 * i))) be |= 1 << i;
    top->cpu_req = 1; top->cpu_we = we; top->cpu_addr = addr - 0x1f000000u;
    top->cpu_be = be; top->cpu_wdata = data;
    tick();
    top->cpu_req = 0;
    int guard = 0;
    while (!top->cpu_ack) { tick(); if (++guard > 1000000) { fprintf(stderr, "no ack at %08x\n", addr); exit(3); } }
    return top->cpu_rdata;
}

static const char *region(uint32_t a) {
    if (a >= 0x1f000000 && a < 0x1f800000) return "flash";
    if (a >= 0x1fb00000 && a < 0x1fb10000) return (a - 0x1fb00000) >= 0x3e0 ? "exca" : "ata";
    return "ctrl";
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    std::map<std::string, std::string> opt;
    for (int i = 1; i + 1 < argc; i += 2) opt[argv[i]] = argv[i + 1];
    if (opt.count("--lat")) lat = atoi(opt["--lat"].c_str());
    long max_mis = opt.count("--max-mis") ? atol(opt["--max-mis"].c_str()) : 40;
    double t_end = opt.count("--t-end") ? atof(opt["--t-end"].c_str()) : 1e9;

    // flash initial contents
    for (int c = 0; c < 5; c++) flash[c].assign(FLASH_WORDS[c], 0xffff);
    static const char *NV[5] = {"firm", "zoomprog", "wave0", "wave1", "wave2"};
    if (opt.count("--warm")) {
        for (int c = 0; c < 5; c++) {
            auto b = readfile(opt["--warm"] + "/" + NV[c]);
            for (uint32_t i = 0; i < FLASH_WORDS[c] && 2 * i + 1 < b.size(); i++) flash[c][i] = (b[2 * i] << 8) | b[2 * i + 1];
        }
    } else {
        auto u = readfile(opt["--u30"]);   // MAME region "firm": as_u16 little-endian
        for (uint32_t i = 0; i < FLASH_WORDS[0] && 2 * i + 1 < u.size(); i++) flash[0][i] = u[2 * i] | (u[2 * i + 1] << 8);
    }
    card = readfile(opt["--card"]);
    card_dirty.assign(card.size() / 512, 0);
    auto idnt = readfile(opt["--idnt"]), cis = readfile(opt["--cis"]), key = readfile(opt["--key"]);

    top = new Vgnet_fc;
    top->rst = 1; top->jp1 = 0; top->card_present = 1; top->cpu_req = 0; top->key_valid = key.size() == 5;
    top->dirty_clear = 0; top->dirty_raddr = 0;
    // load per-game data (meta port, byte address)
    auto meta = [&](unsigned a, uint8_t v) { top->meta_we = 1; top->meta_addr = a; top->meta_wdata = v; tick(); };
    for (unsigned i = 0; i < 512; i++) meta(i, i < idnt.size() ? idnt[i] : 0);
    for (unsigned i = 0; i < 256; i++) meta(0x200 + i, i < cis.size() ? cis[i] : 0xff);
    for (unsigned i = 0; i < 5; i++) meta(0x300 + i, i < key.size() ? key[i] : 0);
    top->meta_we = 0;
    for (int i = 0; i < 20000; i++) tick();   // reset; dirty map clear
    top->rst = 0;
    uint64_t c0 = cyc;

    std::string cmd = "zstd -dc '" + opt["--trace"] + "'";
    FILE *tf = popen(cmd.c_str(), "r");
    char hdr[25];
    if (fread(hdr, 1, 25, tf) != 25 || memcmp(hdr, "GNGT", 4)) { fprintf(stderr, "bad trace\n"); return 2; }
    printf("trace set %.16s jp1 %d\n", hdr + 8, hdr[24]);
    top->jp1 = hdr[24];

    long mis = 0, reads = 0, writes = 0, resets = 0;
    std::map<std::string, long> mis_by;
    uint8_t rec[33];
    double t_last = 0;
    while (fread(rec, 1, 33, tf) == 33) {
        uint8_t k = rec[0]; double t, tl; uint32_t a, d, m, n;
        memcpy(&t, rec + 1, 8); memcpy(&a, rec + 9, 4); memcpy(&d, rec + 13, 4);
        memcpy(&m, rec + 17, 4); memcpy(&n, rec + 21, 4); memcpy(&tl, rec + 25, 8);
        if (t > t_end) break;
        t_last = t;
        if (k == 3) break;
        if (k == 2) {
            if (t > 0.001) {   // machine reset after power-on (watchdog): reset the glue
                resets++;
                printf("reset at %.6f\n", t);
                top->rst = 1; for (int i = 0; i < 20; i++) tick(); top->rst = 0;
            }
            continue;
        }
        uint64_t w0 = c0 + (uint64_t)llround(t * CLK_HZ), w1 = c0 + (uint64_t)llround(tl * CLK_HZ);
        bool data_port = (a == 0x1fb00000) && (m & 0xffff);
        uint32_t reps = (k == 1 || data_port) ? n : (n > 1 ? 2 : 1);
        for (uint32_t i = 0; i < reps; i++) {
            uint64_t w = (reps > 1) ? w0 + (w1 - w0) * i / (reps - 1) : w0;
            uint32_t r = access(w, k == 1, a, d, m);
            if (k == 0) {
                reads++;
                if ((r & m) != (d & m)) {
                    mis++; mis_by[region(a)]++;
                    if (mis <= max_mis)
                        printf("MISMATCH t=%.9f (rep %u/%u) %s %08x mask %08x: rtl %08x mame %08x\n",
                               t, i + 1, reps, region(a), a, m, r & m, d & m);
                }
            } else writes++;
        }
    }
    pclose(tf);
    for (int i = 0; i < 2000; i++) tick();
    printf("replayed to t=%.6f: reads %ld writes %ld resets %ld accesses %lu; late max %lu cycles mean %.2f\n",
           t_last, reads, writes, resets, (unsigned long)n_acc, (unsigned long)late_max, n_acc ? (double)late_sum / n_acc : 0.0);
    printf("read mismatches %ld", mis);
    for (auto &p : mis_by) printf("  %s %ld", p.first.c_str(), p.second);
    printf("\n");

    int bad_chips = 0;
    if (opt.count("--nvram")) {
        for (int c = 0; c < 5; c++) {
            auto b = readfile(opt["--nvram"] + "/" + NV[c]);
            long diff = 0; long first = -1;
            for (uint32_t i = 0; i < FLASH_WORDS[c]; i++) {
                uint16_t mw = (b[2 * i] << 8) | b[2 * i + 1];
                if (mw != flash[c][i]) { if (first < 0) first = i; diff++; }
            }
            printf("flash %-8s words differing from MAME NVRAM: %ld%s", NV[c], diff, diff ? "" : "\n");
            if (diff) { printf(" (first at word %lx)\n", first); bad_chips++; }
        }
    }
    long dsec = 0;
    for (char x : card_dirty) dsec += x;
    printf("card sectors written: %ld\n", dsec);
    if (opt.count("--card-ref")) {
        auto ref = readfile(opt["--card-ref"]);
        long dif = 0;
        for (size_t s = 0; s < ref.size() / 512 && s < card.size() / 512; s++)
            if (memcmp(&ref[s * 512], &card[s * 512], 512)) dif++;
        printf("card sectors differing from MAME's card image: %ld\n", dif);
        if (dif) bad_chips++;
    }
    if (opt.count("--card-out")) {
        FILE *o = fopen(opt["--card-out"].c_str(), "wb"); fwrite(card.data(), 1, card.size(), o); fclose(o);
    }
    printf("RESULT %s\n", (mis == 0 && bad_chips == 0) ? "PASS" : "FAIL");
    delete top;
    return (mis == 0 && bad_chips == 0) ? 0 : 1;
}
