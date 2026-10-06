// Driver for tb_pausewd.sv: scenarios in seconds of clk_1x (33.8688 MHz).
#include "Vtb_pausewd.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>

static const double HZ = 33868800.0;
struct Ev { double t; const char *what; };

static int run(const char *name, double pause_at, double pause_len, bool osd, bool osd_nopause, double hang_at,
               double end_s, int want_resets, double want_reset_after = -1) {
    auto *m = new Vtb_pausewd;
    m->por = 1; m->pause_btn = 0; m->OSD_STATUS = 0; m->osd_nopause = osd_nopause; m->wd_off = 0; m->kick_en = 1;
    m->clk_1x = 0; m->eval();
    uint64_t n = (uint64_t)(end_s * HZ), c_pause = (uint64_t)(pause_at * HZ), c_resume = (uint64_t)((pause_at + pause_len) * HZ);
    int resets = 0, expiries = 0, masked = 0;
    double first_reset = -1, last_kick = -1, first_kick_after = -1, first_exp = -1, last_kick_before = -1;
    bool prev_reset = false;
    for (uint64_t c = 0; c < n; c++) {
        // inputs for this cycle
        if (osd) m->OSD_STATUS = (c >= c_pause && c < c_resume);
        else m->pause_btn = (c >= c_pause && c < c_pause + 1000) || (c >= c_resume && c < c_resume + 1000);
        m->kick_en = !(hang_at >= 0 && c >= (uint64_t)(hang_at * HZ));
        m->por = c < 64;
        m->clk_1x = 1; m->eval();
        m->clk_1x = 0; m->eval();
        if (m->wd_expiry && c > 1000) { expiries++; if (m->wd_masked) masked++; if (first_exp < 0) first_exp = c / HZ; }
        if (m->kick_o) { last_kick = c / HZ; if (c < c_pause) last_kick_before = c / HZ; if (c >= c_resume && first_kick_after < 0) first_kick_after = c / HZ; }
        bool r = m->reset_o;
        if (r && !prev_reset && c > 1000) { resets++; if (first_reset < 0) first_reset = c / HZ; }
        prev_reset = r;
    }
    bool ok = resets == want_resets && (want_reset_after < 0 || (first_reset >= want_reset_after - 0.05 && first_reset <= want_reset_after + 0.05));
    printf("%-52s pause %6.3f s at %4.1f s (%s): last kick before %.4f s, first expiry %.4f s; expiries %d (masked %d), resets %d%s%.3f s, first kick after resume %+.3f s  %s\n",
           name, pause_len, pause_at, osd ? "OSD" : "button", last_kick_before, first_exp, expiries, masked, resets, first_reset >= 0 ? " at " : " ",
           first_reset >= 0 ? first_reset : 0.0, first_kick_after >= 0 ? first_kick_after - (pause_at + pause_len) : -1.0,
           ok ? "PASS" : "FAIL");
    delete m;
    return ok ? 0 : 1;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int f = 0;
    // a running game: pauses longer than the 8 s period, then resumes
    f += run("button pause 10 s, game resumes kicking", 1.0, 10.0, false, false, -1, 16.0, 0);
    f += run("OSD pause 20 s (two expiries while paused)", 1.0, 20.0, true, false, -1, 26.0, 0);
    f += run("button pause 8.4 s (expiry while paused)", 1.0, 8.4, false, false, -1, 14.0, 0);
    f += run("button pause 7.9 s (no expiry while paused)", 1.0, 7.9, false, false, -1, 14.0, 0);
    // the last kick before the pause is at 0.9667 s, so the expiry falls at
    // 8.9667 s: 3.7 ms after this resume and before the game's first kick
    // (one frame later). Only the grace masks it (nograce fails here).
    f += run("button pause 7.963 s (expiry 3.7 ms after resume)", 1.0, 7.963, false, false, -1, 14.0, 0);
    // OSD open with "Pause when OSD is open" off: no pause, the game keeps kicking
    f += run("OSD open 10 s, pause-on-OSD off", 1.0, 10.0, true, true, -1, 14.0, 0);
    // controls: a game that hangs at the resume still resets, at the first
    // expiry after the grace (8.5 s after the resume). Expiries come every 8 s
    // from the last kick (1.0 s): 9, 17, 25 s; pause ends 11 s, grace ends 19.5 s
    f += run("control: hang at resume after 10 s pause -> reset at 25 s", 1.0, 10.0, false, false, 11.0, 27.0, 1, 25.0);
    // hang without any pause: reset 8 s after the last kick (about 1.0 s -> 9.0 s)
    f += run("control: no pause, hang at 1 s -> reset at 9 s", 100.0, 1.0, false, false, 1.0, 11.0, 1, 9.0);
    printf("RESULT tb_pausewd %s (%d failing)\n", f ? "FAIL" : "PASS", f);
    return f ? 1 : 0;
}
