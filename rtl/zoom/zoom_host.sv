// Taito Zoom board: main-CPU side (docs/zoom_board_design.md 3.1).
//
// Addresses are offsets from 0x1F000000, the convention of gnet_fc and the
// zn bus (32-bit data, byte enables, req pulse, ack pulse with data):
//   B80000 lane 0-1  reg_data_w      (MAME taitogn.cpp:483, taito_zm.cpp:151-172)
//   B80000 lane 2-3  reg_address_w   (0x1FB80002, taitogn.cpp:484, taito_zm.cpp:174-177)
//   BA0000           sound_irq_w: IRQ0 doorbell to the MN10200 (taitogn.cpp:485,
//                    taito_zm.cpp:139-143: assert then clear)
//   BC0000           sound_irq_r: reads 0 (taito_zm.cpp:145-149)
//   BE0000-BE01FF    M66220FP mailbox, lanes 0 and 2 (taitogn.cpp:487)
// Other bytes of these words read 0 and ignore writes.
//
// The register port drives the output volume. Two laws (design study 2.4,
// PLAN.md R12):
//   MB87078 (MAME_GAIN = 0): the port is the MB87078 programming interface.
//     The address write is the DSEL-high word: D1:D0 channel, D2 EN, D3 C0,
//     D4 C32; the data write is the DSEL-low word GD5:GD0 and loads the
//     channel's latch with EN, C0, C32 (MB87078 data sheet Edition 2.0A,
//     pp.4 and 6). Gain: EN = 0 mute; C32 = 1 -32 dB; C0 = 1 0 dB; else
//     -(63 - GD) x 0.5 dB. Power-on: all channels 0 dB (code 111111100, p.4).
//     Channel 0 is taken as left and 1 as right (needs-review, Z10).
//   MAME (MAME_GAIN = 1): register 4 sets the left gain and 5 the right gain
//     to (data & 0x3F) / 63, linear; the register number resets to 0 at the
//     Zoom reset (taito_zm.cpp:73-79).
// Gains are unsigned Q1.15 (32768 = 0 dB).
module zoom_host #(
    parameter bit MAME_GAIN = 1'b0
) (
    input  logic        hclk,
    input  logic        hrst,
    input  logic        zoom_release,   // hclk pulse: control bit 4 fell
    input  logic        h_req,
    input  logic        h_we,
    input  logic [23:0] h_addr,
    input  logic [3:0]  h_be,
    input  logic [31:0] h_wdata,
    output logic        h_ack,
    output logic [31:0] h_rdata,
    output logic        h_hit,
    // mailbox port A
    output logic        mb_we,
    output logic [6:0]  mb_a,
    output logic [1:0]  mb_be,
    output logic [15:0] mb_wd,
    input  logic [15:0] mb_q,
    // to the Zoom side (hclk domain; zoom_board synchronises)
    output logic        irq_tog,        // toggles on each doorbell write
    output logic [15:0] gain_l,
    output logic [15:0] gain_r
);
    // ------------------------------------------------------------------ decode
    localparam logic [23:0] A_REG = 24'hB80000, A_IRQ = 24'hBA0000, A_STAT = 24'hBC0000, A_MBOX = 24'hBE0000;
    wire a_reg  = h_addr[23:2] == A_REG[23:2];
    wire a_irq  = h_addr[23:2] == A_IRQ[23:2];
    wire a_stat = h_addr[23:2] == A_STAT[23:2];
    wire a_mbox = h_addr[23:9] == A_MBOX[23:9];
    assign h_hit = a_reg || a_irq || a_stat || a_mbox;

    // ------------------------------------------------------------------ gain tables
    // MB87078: round(32768 x 10^(-(63 - d) x 0.5 / 20))
    function automatic logic [15:0] mb_law(input logic [5:0] d);
        case (d)
            6'd0: mb_law = 16'd872; 6'd1: mb_law = 16'd924; 6'd2: mb_law = 16'd978; 6'd3: mb_law = 16'd1036;
            6'd4: mb_law = 16'd1098; 6'd5: mb_law = 16'd1163; 6'd6: mb_law = 16'd1232; 6'd7: mb_law = 16'd1305;
            6'd8: mb_law = 16'd1382; 6'd9: mb_law = 16'd1464; 6'd10: mb_law = 16'd1550; 6'd11: mb_law = 16'd1642;
            6'd12: mb_law = 16'd1740; 6'd13: mb_law = 16'd1843; 6'd14: mb_law = 16'd1952; 6'd15: mb_law = 16'd2068;
            6'd16: mb_law = 16'd2190; 6'd17: mb_law = 16'd2320; 6'd18: mb_law = 16'd2457; 6'd19: mb_law = 16'd2603;
            6'd20: mb_law = 16'd2757; 6'd21: mb_law = 16'd2920; 6'd22: mb_law = 16'd3093; 6'd23: mb_law = 16'd3277;
            6'd24: mb_law = 16'd3471; 6'd25: mb_law = 16'd3677; 6'd26: mb_law = 16'd3894; 6'd27: mb_law = 16'd4125;
            6'd28: mb_law = 16'd4370; 6'd29: mb_law = 16'd4629; 6'd30: mb_law = 16'd4903; 6'd31: mb_law = 16'd5193;
            6'd32: mb_law = 16'd5501; 6'd33: mb_law = 16'd5827; 6'd34: mb_law = 16'd6172; 6'd35: mb_law = 16'd6538;
            6'd36: mb_law = 16'd6925; 6'd37: mb_law = 16'd7336; 6'd38: mb_law = 16'd7771; 6'd39: mb_law = 16'd8231;
            6'd40: mb_law = 16'd8719; 6'd41: mb_law = 16'd9235; 6'd42: mb_law = 16'd9783; 6'd43: mb_law = 16'd10362;
            6'd44: mb_law = 16'd10976; 6'd45: mb_law = 16'd11627; 6'd46: mb_law = 16'd12315; 6'd47: mb_law = 16'd13045;
            6'd48: mb_law = 16'd13818; 6'd49: mb_law = 16'd14637; 6'd50: mb_law = 16'd15504; 6'd51: mb_law = 16'd16423;
            6'd52: mb_law = 16'd17396; 6'd53: mb_law = 16'd18427; 6'd54: mb_law = 16'd19519; 6'd55: mb_law = 16'd20675;
            6'd56: mb_law = 16'd21900; 6'd57: mb_law = 16'd23198; 6'd58: mb_law = 16'd24573; 6'd59: mb_law = 16'd26029;
            6'd60: mb_law = 16'd27571; 6'd61: mb_law = 16'd29205; 6'd62: mb_law = 16'd30935; default: mb_law = 16'd32768;
        endcase
    endfunction
    // MAME: round(32768 x d / 63)
    function automatic logic [15:0] mame_law(input logic [5:0] d);
        logic [21:0] p, q;
        p = {1'b0, d, 15'd0} + 22'd31;
        q = p / 22'd63;
        mame_law = q[15:0];
    endfunction

    // ------------------------------------------------------------------ registers
    logic [4:0] mb_ctl;                         // {C32, C0, EN, DSC2, DSC1}
    logic [8:0] mb_ch [0:1];                    // channels 0, 1: {GD5:0, EN, C0, C32}
    logic [7:0] reg_addr;                       // MAME m_reg_address
    logic [15:0] mame_l, mame_r;

    function automatic logic [15:0] mb_gain(input logic [8:0] c);
        if (!c[2])     mb_gain = 16'd0;         // EN = 0: -infinity
        else if (c[0]) mb_gain = 16'd823;       // C32: -32 dB
        else if (c[1]) mb_gain = 16'd32768;     // C0: 0 dB
        else           mb_gain = mb_law(c[8:3]);
    endfunction

    wire h_wr_lo = h_req && h_we && (h_be[1:0] != 2'b00);
    wire h_wr_hi = h_req && h_we && (h_be[3:2] != 2'b00);

    always_ff @(posedge hclk) begin
        if (hrst) begin
            mb_ctl   <= 5'b00100;
            mb_ch[0] <= {6'h3F, 3'b100};
            mb_ch[1] <= {6'h3F, 3'b100};
            reg_addr <= 8'd0;
            mame_l   <= 16'd32768;
            mame_r   <= 16'd32768;
            irq_tog  <= 1'b0;
        end else begin
            if (zoom_release) reg_addr <= 8'd0;
            if (a_reg && h_wr_hi) begin
                // reg_address_w: data & 0xFF; MB87078 control word (DSEL high)
                reg_addr <= h_wdata[23:16];
                mb_ctl   <= h_wdata[20:16];
            end
            if (a_reg && h_wr_lo) begin
                // reg_data_w; MB87078 gain word (DSEL low)
                if (!mb_ctl[1]) mb_ch[mb_ctl[0]] <= {h_wdata[5:0], mb_ctl[2], mb_ctl[3], mb_ctl[4]};
                if (reg_addr == 8'h04) mame_l <= mame_law(h_wdata[5:0]);
                if (reg_addr == 8'h05) mame_r <= mame_law(h_wdata[5:0]);
            end
            if (a_irq && h_req && h_we) irq_tog <= ~irq_tog;
        end
    end
    assign gain_l = MAME_GAIN ? mame_l : mb_gain(mb_ch[0]);
    assign gain_r = MAME_GAIN ? mame_r : mb_gain(mb_ch[1]);

    // ------------------------------------------------------------------ mailbox and answers
    assign mb_we = h_req && h_we && a_mbox;
    assign mb_a  = h_addr[8:2];
    assign mb_be = {h_be[2], h_be[0]};
    assign mb_wd = {h_wdata[23:16], h_wdata[7:0]};

    logic       rd_mb;
    logic [1:0] rd_be;
    always_ff @(posedge hclk) begin
        h_ack <= 1'b0;
        rd_mb <= 1'b0;
        if (hrst) begin
            h_rdata <= '0;
        end else if (h_req && h_hit) begin
            if (a_mbox && !h_we) begin
                rd_mb <= 1'b1;                  // RAM output is valid next clock
                rd_be <= {h_be[2], h_be[0]};
            end else begin
                h_ack   <= 1'b1;
                h_rdata <= '0;
            end
        end else if (rd_mb) begin
            h_ack   <= 1'b1;
            h_rdata <= {8'h00, rd_be[1] ? mb_q[15:8] : 8'h00, 8'h00, rd_be[0] ? mb_q[7:0] : 8'h00};
        end
    end
endmodule
