// Pause against the MB3773 watchdog grace (docs/m4_shell.md 4): PSX.sv's
// own pause, reset and watchdog-mask text (work/pausewd_psx.svh from
// gen_pausewd.py) around gnet_ctrl (the MB3773 model, 8 s) on clk_1x. A
// game model kicks the watchdog (control bit 5 falling) once per frame
// while it runs: not paused, not in reset, and kick_en set by the C++
// driver (kick_en 0 = a hung game). gnet_ctrl's rst is the core reset, as
// zn2_board's. In GNET_CPU50 builds the model runs on clk_cpu with CLK_HZ
// 50 MHz and its expiry pulse crosses zn2_cdc into clk_1x; the period in
// real time is the same 8 s.
module tb_pausewd (
    input  logic        clk_1x,
    input  logic        pause_btn,
    input  logic        OSD_STATUS,
    input  logic        osd_nopause,   // status[64]: 1 = no pause while the OSD is open
    input  logic        wd_off,        // status[100]: watchdog Off
    input  logic        kick_en,
    input  logic        por,           // power-on reset (PSX.sv: RESET, pll lock, ...)
    output logic        reset_o,
    output logic        paused_o,
    output logic        wd_expiry,
    output logic        wd_masked,
    output logic        kick_o
);
    logic [127:0] status;
    always_comb begin
        status = '0;
        status[64] = osd_nopause;
        status[100] = wd_off;
    end
    reg paused = 0;
    reg [9:0] unpause = 0;
    reg status1_1;
    reg [20:0] aliveCnt = 0;
    reg heartbeat_1 = 0;
    reg hps_busy = 0;
    wire heartbeat = 1'b0;
    reg reset = 0;
    reg buttonpause_1 = 0;
    reg button_paused = 0;
    reg TURBO_MEM, TURBO_COMP, TURBO_CACHE, TURBO_CACHE50;
    wire zn_wd_reset;
    wire zn_wd_mask;
    reg [7:0] zn_wd_hold = 0;
    wire reset_or = por | (zn_wd_hold != 0);   // PSX.sv: RESET, buttons, downloads, pll lock, watchdog

`include "pausewd_psx.svh"

    // game: one kick per frame (564,480 clk_1x = 16.67 ms) while it runs
    logic [19:0] fcnt = 0;
    logic        op_req = 0;
    logic [15:0] op_wdata = 16'h00E8;
    logic        ph = 0;
    always_ff @(posedge clk_1x) begin
        op_req <= 1'b0;
        if (reset || paused || !kick_en) fcnt <= 0;
        else if (fcnt == 20'd564479) begin
            fcnt <= 0;
            op_req <= 1'b1;
            op_wdata <= ph ? 16'h00C8 : 16'h00E8;   // bit 5 1 -> 0 is the kick
            ph <= ~ph;
        end else fcnt <= fcnt + 1'd1;
    end
    logic op_ack, wd_kick;
    logic [15:0] op_rdata;
    logic [7:0] ctrl_q;
    gnet_ctrl #(.CLK_HZ(33868800), .WD_TIMEOUT_S(GNET_WD_TIMEOUT_S)) ctrl (
        .clk(clk_1x), .rst(reset), .op_req, .op_we(1'b1), .op_reg(2'd0), .op_hi(1'b0), .op_bmask(2'b01),
        .op_wdata, .op_ack, .op_rdata, .zoom_reset(), .zoom_release(), .bank_sel(), .wd_reset(zn_wd_reset),
        .wd_kick, .ctrl_q);
    assign reset_o = reset;
    assign paused_o = paused;
    assign wd_expiry = zn_wd_reset;
    assign wd_masked = zn_wd_reset & zn_wd_mask;
    assign kick_o = wd_kick;
endmodule
