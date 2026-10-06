// Reference for the Zoom integration bench: zoom_board alone with the
// parameters of the core (CLK_H 4, PACE_CAP 1024, ZSG_INFL 4, TIMER_EXACT 0),
// its host port driven at the clk_1x cycles that tb_zoomlink logged
// (hev.log: every request, zoom_reset and reset change as zoom_board saw
// them through the crossings), and an ideal flash area memory (10 clk_1x per
// line, one at a time, as sim/zoomboard/tb.cpp). Writes its own insn.bin.
//
//   tb_zoomref <flashdir> <hev.log> <insn.bin out>
//
// The two instruction logs must be equal up to the first host request after
// the release: until then the only difference between the runs is the
// memory path (zoom_sdram_link, zn2_ch3_arb, the SDRAM model), which may
// change when an instruction runs in real time but not what it does.
#include "Vzoom_board.h"
#include "Vzoom_board___024root.h"
#include "verilated.h"
#include <deque>
#include <string>

static Vzoom_board *top;
static Vzoom_board___024root *R;
#define ZB(x) R->zoom_board__DOT__##x
#include "zl_common.h"

static const uint64_t H2 = 7382, H1 = 14764;

struct Ev { uint64_t c1; char k; unsigned v, we, be; uint32_t a, d; };

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 4) { fprintf(stderr, "usage: tb_zoomref <flashdir> <hev.log> <insn.bin>\n"); return 2; }
    if (!load_flash(argv[1])) return 2;
    FILE *h = fopen(argv[2], "r");
    FILE *ins = fopen(argv[3], "wb");
    // <insn.bin>.aud: the TMS57002 SO1 pair (int16 L, R) at every output FIFO
    // push; <insn.bin>.zsg: the four ZSG-2 sends (int16) of every pass
    FILE *aud = fopen((std::string(argv[3]) + ".aud").c_str(), "wb");
    FILE *zsg = fopen((std::string(argv[3]) + ".zsg").c_str(), "wb");
    if (!h || !ins) { perror("open"); return 2; }
    std::deque<Ev> evs;
    uint64_t end_c1 = 0;
    char ln[256];
    while (fgets(ln, sizeof ln, h)) {
        Ev e{};
        unsigned long long c;
        char k;
        if (sscanf(ln, "%llu %c", &c, &k) != 2) continue;
        e.c1 = c; e.k = k;
        if (k == 'H') sscanf(ln, "%*llu %*c %u %x %x %x", &e.we, &e.a, &e.be, &e.d);
        else if (k == 'Z' || k == 'R') sscanf(ln, "%*llu %*c %u", &e.v);
        else if (k == 'E') { end_c1 = c; continue; }
        evs.push_back(e);
    }
    fclose(h);

    top = new Vzoom_board;
    R = top->rootp;
    top->rst = 1; top->hrst = 1; top->zoom_reset = 1; top->pace_en = 1; top->dbg_hold = 0; top->prog_inval = 0;
    top->tb_pin1_ovr = 0; top->tb_pin1 = 0; top->tb_ld = 0; top->h_req = 0; top->m_ready = 1;
    top->clk = 0; top->clk2x = 0; top->hclk = 0;
    top->eval();
    std::deque<std::pair<uint64_t, uint32_t>> memq;   // due clk_1x cycle, line
    uint64_t c1 = 0, insns = 0, lines = 0, now = 0, n2 = 0, n1 = 0;
    bool l2 = false, l1 = false;
    while (c1 < end_c1) {
        uint64_t t = std::min(n2, n1);
        now = t;
        bool r2 = (t == n2 && !l2), r1 = (t == n1 && !l1);
        bool acc = false, rv = false;
        uint32_t acc_line = 0;
        if (r2 && top->dbg_insn) {
            Insn r;
            r.pc = top->dbg_pc; r.psw = top->dbg_psw; r.mdr = top->dbg_mdr;
            for (int i = 0; i < 6; i++) r.regs[i] = top->dbg_regs[i];
            fwrite(&r, sizeof r, 1, ins);
            insns++;
        }
        if (r1) {
            acc = top->m_req && top->m_ready; acc_line = top->m_line; rv = top->m_rvalid;
            if (ZB(zo_valid)) { uint16_t z4[4] = {(uint16_t)ZB(zo_s0), (uint16_t)ZB(zo_s1), (uint16_t)ZB(zo_s2), (uint16_t)ZB(zo_s3)}; fwrite(z4, 2, 4, zsg); }
            if (ZB(sync_q)) { uint16_t p[2] = {(uint16_t)ZB(so_l16), (uint16_t)ZB(so_r16)}; fwrite(p, 2, 2, aud); }
        }
        if (t == n2) { l2 = !l2; top->clk2x = l2; n2 += H2; }
        if (t == n1) { l1 = !l1; top->clk = l1; top->hclk = l1; n1 += H1; }
        top->eval();
        if (!r1) continue;
        c1++;
        // memory: one line at a time, 10 clk_1x
        if (rv) { memq.pop_front(); lines++; }
        if (acc) memq.push_back({c1 + 10, acc_line});
        top->m_ready = memq.empty();
        top->m_rvalid = 0;
        if (!memq.empty() && c1 >= memq.front().first) {
            uint64_t v = 0;
            uint32_t b = (memq.front().second << 3) & 0xffffff;
            for (int i = 7; i >= 0; i--) v = v << 8 | fa[b + i];
            top->m_rdata = v;
            top->m_rvalid = 1;
        }
        // host events of this cycle (logged as the value during cycle c1)
        top->h_req = 0;
        while (!evs.empty() && evs.front().c1 <= c1) {
            Ev e = evs.front(); evs.pop_front();
            if (e.k == 'R') { top->rst = e.v; top->hrst = e.v; }
            if (e.k == 'Z') top->zoom_reset = e.v;
            if (e.k == 'H') { top->h_req = 1; top->h_we = e.we; top->h_addr = e.a; top->h_be = e.be; top->h_wdata = e.d; }
        }
        top->eval();
    }
    fclose(ins); fclose(aud); fclose(zsg);
    printf("tb_zoomref: %llu clk_1x cycles, %llu instructions, %llu lines\n", (unsigned long long)c1,
           (unsigned long long)insns, (unsigned long long)lines);
    delete top;
    return 0;
}
