// zoom_mix: G-NET audio mix of the PSX SPU and the Taito Zoom board (Taito
// G-NET core)
//
// Copyright (C) 2026 Lee Foot
// SPDX-License-Identifier: GPL-2.0-or-later
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation; either version 2 of the License, or (at your option)
// any later version. This program is distributed in the hope that it will be
// useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
// Public License for more details.
//
// Origin: written for this core (own implementation, no code copied from
//         other projects).
// Evidence: MAME 0.288 taitogn.cpp:441-448 (speaker routes 0.3 and 1.0),
//           spu.cpp, tms57002.cpp:933-936.
// Design: docs/zoom_board_design.md 7.3.
// Bench: sim/zoommix/.
//
// G-NET audio mix: PSX SPU and Taito Zoom (docs/zoom_board_design.md 7.3).
//
// MAME routes the SPU to the speaker at 0.3 and the Zoom at 1.0
// (taitogn.cpp:441-448); both streams are 16-bit full scale there (spu.cpp
// put_int(..., 32768); tms57002.cpp:933-936 puts so << 8 / 2^31, so the
// 16-bit SO1 word is full scale). The PCB balance is open (PLAN.md R13).
// MAME's 0.3 was set by ear in 2018 (before: SPU 0.35/0.45 against Zoom 0.5,
// a ratio of about 0.9), and MAME's spu.cpp ignores the SPU main volume
// (0x1F801D80/82, spureg.mvol_l/r stored, never applied), which the games set
// low (Ray Crisis 0x1125, Shikigami 0x0C99, Psyvariar 0x2FDF) and the core's
// spu.vhd applies. So the SPU gain is selectable (spu_lvl, the shell's OSD
// "SFX level"): 0 = G_SPU (0.3, MAME), 1 = 0.45, 2 = 0.6, 3 = 0.9 (the
// pre-2018 MAME ratio), 4 = 1.2, 5 = 1.5, 6 and 7 = G_SPU. Gains are
// unsigned Q16 (65536 = 1.0). Each input is held between its own sample
// ticks and the sum is formed every clock, saturated to 16 bits; MiSTer's
// audio_out resamples the result.
//
// Output level (2026-10-21): with the MAME gains alone the core played about
// 7 to 17 dB under the mister-core reference (-16.4 dBFS, 1 s RMS median),
// measured in full-system simulation on six sets (intros and attract, no
// peak above -9.9 dBFS). OUT_SHIFT = 15 (the default) doubles the whole mix
// (+6.02 dB), which keeps every SFX level ratio and left the loudest
// measured content (Psyvariar) peaking at -3.9 dBFS; 16 is the MAME scale.
module zoom_mix #(
    parameter int G_SPU  = 19661,       // 0.3
    parameter int G_ZOOM = 65536,       // 1.0
    parameter int OUT_SHIFT = 15        // 16: MAME scale; 15: +6.02 dB (see above)
) (
    input  logic               clk,
    input  logic        [2:0]  spu_lvl,
    input  logic signed [15:0] spu_l,
    input  logic signed [15:0] spu_r,
    input  logic signed [15:0] zoom_l,
    input  logic signed [15:0] zoom_r,
    output logic signed [15:0] out_l,
    output logic signed [15:0] out_r
);
    localparam logic signed [18:0] K_ZOOM = 19'(G_ZOOM);

    // SPU gain for the selected level, registered (quasi-static OSD setting)
    logic signed [18:0] k_spu = 19'(G_SPU);
    always_ff @(posedge clk) begin
        case (spu_lvl)
            3'd1:    k_spu <= 19'sd29491;   // 0.45
            3'd2:    k_spu <= 19'sd39322;   // 0.6
            3'd3:    k_spu <= 19'sd58982;   // 0.9
            3'd4:    k_spu <= 19'sd78643;   // 1.2
            3'd5:    k_spu <= 19'sd98304;   // 1.5
            default: k_spu <= 19'(G_SPU);   // 0.3
        endcase
    end

    function automatic logic signed [15:0] mix(input logic signed [15:0] s, input logic signed [15:0] z,
                                               input logic signed [18:0] k);
        logic signed [39:0] t;
        t = s * k + z * K_ZOOM;
        t = t >>> OUT_SHIFT;
        // limits as bit patterns: -16'sd32768 negates 32768, which does not fit
        // a signed 16-bit literal (Quartus 10259 constant value overflow)
        if (t > 40'sd32767) mix = 16'sh7FFF;
        else if (t < -40'sd32768) mix = 16'sh8000;
        else mix = t[15:0];
    endfunction

    always_ff @(posedge clk) begin
        out_l <= mix(spu_l, zoom_l, k_spu);
        out_r <= mix(spu_r, zoom_r, k_spu);
    end
endmodule
