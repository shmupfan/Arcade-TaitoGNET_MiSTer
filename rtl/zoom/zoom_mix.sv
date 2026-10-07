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
module zoom_mix #(
    parameter int G_SPU  = 19661,       // 0.3
    parameter int G_ZOOM = 65536        // 1.0
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
        t = t >>> 16;
        if (t > 40'sd32767) mix = 16'sd32767;
        else if (t < -40'sd32768) mix = -16'sd32768;
        else mix = t[15:0];
    endfunction

    always_ff @(posedge clk) begin
        out_l <= mix(spu_l, zoom_l, k_spu);
        out_r <= mix(spu_r, zoom_r, k_spu);
    end
endmodule
