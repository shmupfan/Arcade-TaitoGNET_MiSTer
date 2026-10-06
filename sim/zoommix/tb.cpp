// zoom_mix bench (Verilator): every SFX level against a reference model
// (s * k + z * 65536) >> 16 with 16-bit saturation, k = 0.7/0.3/0.45/0.6/
// 0.9/1.2/1.5 in Q16 (level 7 = the default 0.7); extremes, then random
// pairs. Also the gain itself: a full-scale SPU sine with the Zoom at 0
// gives an output RMS of k times the input RMS.
#include "Vzoom_mix.h"
#include "verilated.h"
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <random>

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    auto *m = new Vzoom_mix;
    static const int K[8] = {45875, 19661, 29491, 39322, 58982, 78643, 98304, 45875};
    std::mt19937 rng(1);
    long errors = 0, n = 0, sat = 0;
    auto step = [&](int lvl, int s, int z) {
        m->spu_lvl = lvl; m->spu_l = (int16_t)s; m->spu_r = (int16_t)(-s - 1); m->zoom_l = (int16_t)z; m->zoom_r = (int16_t)z;
        for (int c = 0; c < 2; c++) { m->clk = 1; m->eval(); m->clk = 0; m->eval(); }   // k_spu then the sum
        auto ref = [&](int sv, int zv) { long long t = ((long long)sv * K[lvl] + (long long)zv * 65536) >> 16;
            if (t > 32767) { sat++; t = 32767; } if (t < -32768) { sat++; t = -32768; } return (int)t; };
        int el = ref(s, z), er = ref(-s - 1, z);
        n++;
        if ((int16_t)m->out_l != el || (int16_t)m->out_r != er) {
            if (errors++ < 10) printf("ERROR lvl %d s %d z %d: out %d %d, expected %d %d\n", lvl, s, z, (int16_t)m->out_l, (int16_t)m->out_r, el, er);
        }
    };
    const int ext[] = {-32768, -32767, -16384, -1, 0, 1, 16384, 32767};
    for (int lvl = 0; lvl < 8; lvl++) {
        for (int s : ext) for (int z : ext) step(lvl, s, z);
        for (int i = 0; i < 20000; i++) step(lvl, (int)(rng() % 65536) - 32768, (int)(rng() % 65536) - 32768);
    }
    printf("random and extreme pairs: %ld compared, %ld saturated in the reference, %ld errors\n", n, sat, errors);
    for (int lvl = 0; lvl < 7; lvl++) {
        double si = 0, so = 0;
        for (int i = 0; i < 48000; i++) {
            int s = (int)lround(20000 * sin(2 * M_PI * 1000 * i / 48000.0));
            m->spu_lvl = lvl; m->spu_l = s; m->spu_r = s; m->zoom_l = 0; m->zoom_r = 0;
            for (int c = 0; c < 2; c++) { m->clk = 1; m->eval(); m->clk = 0; m->eval(); }
            si += (double)s * s; so += (double)(int16_t)m->out_l * (int16_t)m->out_l;
        }
        printf("level %d: SPU sine gain %.4f (%.2f dB), expected %.4f\n", lvl, sqrt(so / si), 20 * log10(sqrt(so / si)), K[lvl] / 65536.0);
    }
    printf("RESULT zoom_mix %s\n", errors ? "FAIL" : "PASS");
    delete m;
    return errors ? 1 : 0;
}
