// Panasonic MN10200 (MN1020012A) for the Taito Zoom sound board: CPU core,
// internal peripherals and the real-time pacer (docs/mn10200_design.md 5.2).
//
// Clock: any clock above about 25 MHz with this design (the G-NET core uses
// clk_1x, 33.8688 MHz). The pacer keeps the virtual machine-cycle domain
// (6.25 MHz = OSCI 12.5 MHz / 2) locked to real time: it adds
// PACE_ADD per clock and subtracts PACE_SUB per machine cycle; the CPU
// starts an instruction only while the credit is positive. With the
// defaults 15,625 / 84,672 = 6,250,000 / 33,868,800 exactly.
module mn10200 #(
    parameter FORM_HEX  = "rtl/zoom/mn10200_form.hex",
    parameter CTL_HEX   = "rtl/zoom/mn10200_ctl.hex",
    parameter PACE_ADD  = 15625,
    parameter PACE_SUB  = 84672,
    parameter PACE_CAP  = 64,           // machine cycles of credit at most
    parameter DEBUG     = 1,            // 0: drop the debug cycle counter
    parameter RF_MLAB   = 1,            // register file in MLAB
    parameter TIMER_EXACT = 0,          // 0: shared prescalers as on the chip, 1: MAME timer phase (mn10200_periph.sv)
    parameter PIPE      = 0             // 1: registers for a 67.7 MHz clock (mn10200_core.sv)
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        pace_en,        // 0: run as fast as the bus allows (simulation)
    input  logic        ext_go,         // 0: start no instruction (Zoom board: TMS57002 slots behind; tie 1)
    // external bus
    output logic [23:0] bus_addr,
    output logic        bus_rd,
    output logic        bus_wr,
    output logic [1:0]  bus_be,
    output logic [15:0] bus_wdata,
    input  logic [15:0] bus_rdata,
    input  logic        bus_ack,
    // pins
    input  logic [3:0]  irq_pin,        // IRQ0-3 (1 = high); Zoom: IRQ0 main CPU doorbell, IRQ1 TMS57002 FIFO
    input  logic [7:0]  p0_in,
    input  logic [7:0]  p1_in,
    input  logic [7:0]  p2_in,
    input  logic [7:0]  p3_in,
    output logic [7:0]  p0_out,
    output logic [7:0]  p1_out,         // Zoom: TMS57002 PLOAD (bit 0) / CLOAD (bit 1)
    output logic [7:0]  p2_out,
    output logic [7:0]  p3_out,
    output logic [3:0]  p_wr,
    // Zoom board time base: one machine cycle stepped, and the cycles of the
    // instruction whose external access is on the bus (docs/zoom_board_design.md 6.2)
    output logic        mc_step,
    output logic [4:0]  acc_cyc,
    output logic [4:0]  io_cyc,         // acc_cyc of the last internal register write (held): a port
                                        // write lands at the end of its instruction too
    // debug / trace port
    input  logic        dbg_hold,
    output logic        dbg_bound,
    output logic        dbg_insn,
    output logic [23:0] dbg_pc,
    output logic [15:0] dbg_psw,
    output logic [15:0] dbg_mdr,
    output logic [47:0] dbg_cycles,
    output logic [191:0] dbg_regs
);
    logic        io_rd, io_wr;
    logic [9:0]  io_addr;
    logic [1:0]  io_be;
    logic [15:0] io_wdata, io_rdata;
    logic        irq_cand, nmi_req, pirq_set, irq_take, ill, retire, tmr_busy, cyc_step, go;
    logic [2:0]  irq_level, psw_im;
    logic [3:0]  irq_group, irq_take_group;
    logic [4:0]  retire_cyc;
    logic [7:0]  cpum;

    mn10200_core #(.FORM_HEX(FORM_HEX), .CTL_HEX(CTL_HEX), .DEBUG(DEBUG), .RF_MLAB(RF_MLAB), .PIPE(PIPE)) u_core (
        .clk, .rst,
        .bus_addr, .bus_rd, .bus_wr, .bus_be, .bus_wdata, .bus_rdata, .bus_ack,
        .io_rd, .io_wr, .io_addr, .io_be, .io_wdata, .io_rdata,
        .irq_cand, .irq_level, .irq_group, .nmi_req, .pirq_set, .psw_im,
        .irq_take, .irq_take_group, .ill,
        .retire, .retire_cyc, .tmr_busy, .go, .hold(dbg_hold), .acc_cyc,
        .dbg_bound, .dbg_insn, .dbg_pc, .dbg_psw, .dbg_mdr, .dbg_cycles, .dbg_regs);

    mn10200_periph #(.TIMER_EXACT(TIMER_EXACT)) u_periph (
        .clk, .rst,
        .io_rd, .io_wr, .io_addr, .io_be, .io_wdata, .io_rdata,
        .psw_im, .irq_cand, .irq_level, .irq_group, .nmi_req, .pirq_set,
        .irq_take, .irq_take_group, .ill,
        .retire, .retire_cyc, .tmr_busy, .cyc_step,
        .irq_pin, .p0_in, .p1_in, .p2_in, .p3_in,
        .p0_out, .p1_out, .p2_out, .p3_out, .p_wr, .cpum);

    // pacer
    // 32 bits: caps up to 4,096 cycles at clk_2x (169,344 per cycle) fit
    localparam logic signed [31:0] P_ADD = PACE_ADD;
    localparam logic signed [31:0] P_SUB = PACE_SUB;
    localparam logic signed [31:0] P_CAP = PACE_CAP * PACE_SUB;
    logic signed [31:0] credit, credit_n;
    always_comb begin
        credit_n = credit + (cyc_step ? (P_ADD - P_SUB) : P_ADD);   // one adder, constant operand
        if (credit_n > P_CAP) credit_n = P_CAP;
    end
    always_ff @(posedge clk) begin
        if (rst) credit <= 32'sd0;
        else credit <= credit_n;
    end
    assign go = (!pace_en || (credit > 0)) && ext_go;
    assign mc_step = cyc_step;
    always_ff @(posedge clk) if (io_wr) io_cyc <= acc_cyc;
endmodule
