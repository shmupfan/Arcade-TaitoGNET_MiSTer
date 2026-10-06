// Shared parts of the Zoom integration benches (tb_zoomlink.cpp,
// tb_zoomref.cpp): flash images, instruction log, mailbox shadow.
// The including file defines ZB(x), the path of a zoom_board internal
// signal in its Verilator model, and R, the model's root pointer.
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <algorithm>
#include <string>
#include <vector>

// Flash area as the core holds it (docs/zn2_layer_design.md 13.4): U27 at
// 0x200000, U56/U55/U29 at 0x400000/0x600000/0x800000; little-endian 16-bit
// words. tools/build_flash.py writes MAME's NVRAM layout (byte-swapped
// words), as sim/zoomboard/tb.cpp reads it.
static std::vector<uint8_t> fa(0x1000000, 0xff);
static bool load_flash(const char *dir) {
    struct { const char *n; uint32_t base, len; } parts[] = {
        { "zoomprog", 0x200000, 0x80000 }, { "wave0", 0x400000, 0x200000 },
        { "wave1", 0x600000, 0x200000 }, { "wave2", 0x800000, 0x200000 } };
    for (auto &x : parts) {
        std::string p = std::string(dir) + "/" + x.n;
        FILE *h = fopen(p.c_str(), "rb");
        if (!h) { perror(p.c_str()); return false; }
        size_t n = fread(&fa[x.base], 1, x.len, h);
        fclose(h);
        if (n != x.len) { fprintf(stderr, "%s: %zu bytes\n", p.c_str(), n); return false; }
        for (size_t i = 0; i < x.len; i += 2) std::swap(fa[x.base + i], fa[x.base + i + 1]);
    }
    return true;
}

// One record per MN10200 instruction: pc, psw, mdr, D0-D3, A0-A3 (32 bytes)
struct Insn { uint32_t pc; uint16_t psw, mdr; uint32_t regs[6]; };

// Mailbox shadow: every write that reaches the RAM (host port A on clk1x,
// MN10200 port B on clk2x), with the time of each byte's last change, so a
// read that races a write is told apart from a wrong answer.
struct Shadow {
    uint8_t b[256];
    uint64_t t[256];
    uint64_t mn_reads = 0, mn_bad = 0, mn_race = 0, host_reads = 0, host_bad = 0, host_race = 0;
    uint64_t mn_writes = 0, host_writes = 0;
    Shadow() { memset(b, 0, sizeof b); memset(t, 0, sizeof t); }
    void wr(unsigned word, unsigned be, unsigned d, uint64_t now) {
        for (int l = 0; l < 2; l++)
            if (be >> l & 1) { unsigned i = word * 2 + l; if (b[i] != (uint8_t)(d >> (8 * l))) t[i] = now; b[i] = d >> (8 * l); }
    }
    // returns 0 ok, 1 race, 2 wrong
    int check(unsigned word, unsigned be, unsigned d, uint64_t now, uint64_t win) {
        int r = 0;
        for (int l = 0; l < 2; l++)
            if (be >> l & 1) {
                unsigned i = word * 2 + l;
                if (b[i] != (uint8_t)(d >> (8 * l))) r = std::max(r, now - t[i] <= win ? 1 : 2);
            }
        return r;
    }
};
