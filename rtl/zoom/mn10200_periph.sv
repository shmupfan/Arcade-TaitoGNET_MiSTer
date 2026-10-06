// MN10200 (MN1020012A) internal peripherals at 0x00FC00-0x00FFFF, at the
// level the Taito Zoom firmware uses them (docs/mn10200_design.md 4 and
// 5.7): interrupt controller (groups 1-10, NMICR, IAGR, EXTMD with P4 pin
// readback), the ten 8-bit timers with prescalers 0/1 and cascading,
// ports 0-3, pull-up and serial control registers. Everything else reads 0
// and ignores writes, as MAME 0.288 mn10200.cpp io_control_r/w does for
// registers it does not decode.
//
// The register layout is the older MN10200 generation that MAME implements
// (design study 1 and 4.1; the MN102H manual describes a different map).
//
// Timing model (design study 5.7 and 6.2): the core retires each
// instruction's machine cycles on retire/retire_cyc; this block steps the
// timers one machine cycle per clock and holds tmr_busy until done. A timer
// expires (pb + 1) x (cur + 1) machine cycles after it was armed, as MAME's
// refresh_timer computes; arming by a mode write takes effect at the end of
// the writing instruction, which is where MAME's write lands in machine
// time (all cycle charges precede the access in mn10200.cpp).
module mn10200_periph #(
    // 1: MAME-exact timer phase: each armed timer expires
    //    (prescaler base + 1) x (cur + 1) machine cycles after arming, with
    //    its own prescale counter and the base latched at arming
    //    (mn10200.cpp refresh_timer). Needed for instruction-exact traces.
    // 0: shared prescalers as on the chip (MN102H manual, timer chapter):
    //    prescaler p counts machine cycles continuously and every armed
    //    timer on it counts its underflows. Same periods, the phase of the
    //    first period after arming differs by up to the prescaler base.
    parameter TIMER_EXACT = 1
) (
    input  logic        clk,
    input  logic        rst,
    // register access from the core
    input  logic        io_rd,
    input  logic        io_wr,
    input  logic [9:0]  io_addr,     // offset from 0xFC00
    input  logic [1:0]  io_be,
    input  logic [15:0] io_wdata,
    output logic [15:0] io_rdata,
    // interrupt interface
    input  logic [2:0]  psw_im,
    output logic        irq_cand,
    output logic [2:0]  irq_level,
    output logic [3:0]  irq_group,
    output logic        nmi_req,
    output logic        pirq_set,
    input  logic        irq_take,
    input  logic [3:0]  irq_take_group,
    input  logic        ill,
    // virtual machine cycles
    input  logic        retire,
    input  logic [4:0]  retire_cyc,
    output logic        tmr_busy,
    output logic        cyc_step,    // one machine cycle stepped (pacer)
    // pins
    input  logic [3:0]  irq_pin,     // P4 / IRQ0-IRQ3 levels (1 = high)
    input  logic [7:0]  p0_in,
    input  logic [7:0]  p1_in,
    input  logic [7:0]  p2_in,
    input  logic [7:0]  p3_in,
    output logic [7:0]  p0_out,      // out | ~dir, as MAME's write_port callbacks
    output logic [7:0]  p1_out,
    output logic [7:0]  p2_out,
    output logic [7:0]  p3_out,
    output logic [3:0]  p_wr,        // pulse per port output register write
    output logic [7:0]  cpum         // CPUM low byte (STOP/HALT request, open item O4)
);
    // ------------------------------------------------------------------ registers
    logic [7:0] nmicr;
    logic [3:0] iagr;
    logic [3:0] icr_ir [1:10];     // request bits (ICRL 7:4)
    logic [7:0] icr_h  [1:10];     // ICRH: level 6:4, enable 3:0
    logic [7:0] extmdl;
    logic [1:0] extmdh;
    logic [3:0] pin_q;
    logic [7:0] ser_l [0:1], ser_h [0:1];
    logic [7:0] ser_recv;
    logic [7:0] t_mode [0:9], t_base [0:9], t_cur [0:9];
    logic [7:0] p_mode [0:1], p_base [0:1], p_cur [0:1];
    logic [6:0] pplul;
    logic [5:0] ppluh;
    logic [7:0] pout [0:3], pdir [0:3];
    logic [6:0] p3md;

    // ------------------------------------------------------------------ interrupt priority
    // MAME check_irq: the lowest level number below PSW.IM wins, ties to
    // the lowest group (strict "<" while scanning groups 1 to 10).
    always_comb begin : prio
        logic [2:0] lv;
        logic [3:0] g;
        lv = psw_im;
        g = 4'd0;
        for (int k = 1; k <= 10; k++) begin
            if (|(icr_ir[k] & icr_h[k][3:0]) && (icr_h[k][6:4] < lv)) begin
                lv = icr_h[k][6:4];
                g = k[3:0];
            end
        end
        irq_cand = (g != 4'd0);
        irq_level = lv;
        irq_group = g;
    end
    assign nmi_req = (nmicr != 8'h0);

    // ------------------------------------------------------------------ register read
    // One decode per 16-bit word (offset bits 9:1), both byte lanes at once.
    // Values as MAME io_control_r; undecoded registers read 0.
    function automatic logic [15:0] rd_word(input logic [8:0] w);
        logic [15:0] r;
        r = 16'h0000;
        case (w)
            9'h007: r = {8'h00, 3'b000, iagr, 1'b0};               // FC0E IAGR: group << 1
            9'h020: r = {8'h00, nmicr};                             // FC40
            9'h02B: r = {pin_q, 2'b00, extmdh, extmdl};             // FC56/57: P4 pins in 7:4 of FC57
            9'h0C0: r = {ser_h[0], ser_l[0]};                       // FD80/81
            9'h0C1: r = {8'h10, ser_recv};                          // FD82 (post-increments) / FD83
            9'h0C8: r = {ser_h[1], ser_l[1]};                       // FD90/91
            9'h105: r = {p_cur[1], p_cur[0]};                       // FE0A/0B
            9'h10D: r = {p_base[1], p_base[0]};                     // FE1A/1B
            9'h115: r = {p_mode[1], p_mode[0]};                     // FE2A/2B
            9'h132: r = {8'h00, pout[1]};                           // FE64
            9'h1D8: r = {2'b00, ppluh, 1'b0, pplul};                // FFB0/B1
            9'h1E0: r = {8'h00, pout[0]};                           // FFC0
            9'h1E1: r = {pout[3], pout[2]};                         // FFC2/C3
            9'h1E8: r = {p1_in | pdir[1], p0_in | pdir[0]};         // FFD0/D1
            9'h1E9: r = {(p3_in & 8'h1F) | pdir[3], (p2_in & 8'h0F) | pdir[2]};
            9'h1F0: r = {pdir[1], pdir[0]};                         // FFE0/E1
            9'h1F1: r = {pdir[3], pdir[2]};                         // FFE2/E3
            9'h1F9: r = {1'b0, p3md, 8'h00};                        // FFF3
            default: begin
                if (w >= 9'h021 && w <= 9'h02A)                     // FC42-FC55 groups 1-10
                    r = {icr_h[w[4:0]], icr_ir[w[4:0]],
                         icr_ir[w[4:0]] & icr_h[w[4:0]][3:0]};
                else if (w >= 9'h100 && w <= 9'h104)                // FE00-FE09 timer counters
                    r = {t_cur[{w[2:0], 1'b1}], t_cur[{w[2:0], 1'b0}]};
                else if (w >= 9'h108 && w <= 9'h10C)                // FE10-FE19 timer bases
                    r = {t_base[{w[2:0], 1'b1}], t_base[{w[2:0], 1'b0}]};
                else if (w >= 9'h110 && w <= 9'h114)                // FE20-FE29 timer modes
                    r = {t_mode[{w[2:0], 1'b1}], t_mode[{w[2:0], 1'b0}]};
            end
        endcase
        return r;
    endfunction
    assign io_rdata = rd_word(io_addr[9:1]);

    // ------------------------------------------------------------------ timers
    // Per timer: armed (counting from a prescaler) and the cnt down counter;
    // TIMER_EXACT adds a prescale counter and the prescaler base latched at
    // arming (MAME fixes the period then). Shared mode runs the prescalers
    // in p_cur.
    logic [9:0] armed, arm_req, arm_go;
    logic [7:0] t_psc [0:9], t_cnt [0:9], t_pbl [0:9];
    logic [1:0] ptick;
    logic [5:0] pend;
    logic       pend_nz;                // pend != 0, kept with pend (shorter step path)
    wire        step = pend_nz;
    // t_cur == 0 and t_base == 0 kept as flags with the registers, so the
    // cascade chain below compares no counters
    logic [9:0] t_curz, t_basez;
    assign tmr_busy = step || (arm_go != 10'h0);
    assign cyc_step = step;

    logic [9:0] casc, own_exp, tick, in_evt, full;
    always_comb begin
        for (int k = 0; k < 2; k++) ptick[k] = step && p_mode[k][7] && p_cur[k] == 8'h0;
        for (int t = 0; t < 10; t++) begin
            casc[t] = (t_mode[t] & 8'h83) == 8'h81;
            own_exp[t] = step && armed[t] && !arm_req[t] && !arm_go[t] && t_cnt[t] == 8'h0
                         && (TIMER_EXACT ? (t_psc[t] == 8'h0) : ptick[t_mode[t][0]]);
        end
        // chain upwards: a cascaded timer is ticked when the one below
        // underflows (MAME timer_tick_simple)
        for (int t = 0; t < 10; t++) begin
            in_evt[t] = (t > 0) ? (casc[t] && tick[t-1]) : 1'b0;
            tick[t] = own_exp[t] || (in_evt[t] && t_curz[t]);
        end
        // does the chain above t fully underflow (MAME return value != 2)
        for (int t = 9; t >= 0; t--) begin
            if (t == 9) full[t] = 1'b1;
            else full[t] = !casc[t+1] || (t_curz[t+1] && full[t+1]);
        end
    end

    function automatic logic t_enabled(input int t);
        t_enabled = (t_mode[t][7] && t_mode[t][1]) && p_mode[t_mode[t][0]][7];
    endfunction

    // ------------------------------------------------------------------ sequential
    always_ff @(posedge clk) begin
        pirq_set <= 1'b0;
        p_wr <= 4'h0;
        if (rst) begin
            // MAME device_reset: CPUM = 0x8000, then 0 to every register
            nmicr <= 8'h0; iagr <= 4'h0;
            for (int k = 1; k <= 10; k++) begin icr_ir[k] <= 4'h0; icr_h[k] <= 8'h0; end
            // the reset loop's EXTMD = 0 write re-samples the pins as 'L' level
            icr_ir[8] <= ~irq_pin;
            extmdl <= 8'h0; extmdh <= 2'h0;
            pin_q <= irq_pin;
            for (int k = 0; k < 2; k++) begin
                ser_l[k] <= 8'h0; ser_h[k] <= 8'h0;
                p_mode[k] <= 8'h0; p_base[k] <= 8'h0; p_cur[k] <= 8'h0;
            end
            for (int t = 0; t < 10; t++) begin
                t_mode[t] <= 8'h0; t_base[t] <= 8'h0; t_cur[t] <= 8'h0;
                t_psc[t] <= 8'h0; t_cnt[t] <= 8'h0; t_pbl[t] <= 8'h0;
            end
            armed <= 10'h0; arm_req <= 10'h0; arm_go <= 10'h0;
            pend <= 6'd0;
            pend_nz <= 1'b0;
            t_curz <= 10'h3FF;
            t_basez <= 10'h3FF;
            pplul <= 7'h0; ppluh <= 6'h0; p3md <= 7'h0;
            for (int k = 0; k < 4; k++) begin pout[k] <= 8'h0; pdir[k] <= 8'h0; end
            cpum <= 8'h0;
        end else begin
            // ---------------------------------------------- pins (execute_set_input)
            pin_q <= irq_pin;
            for (int k = 0; k < 4; k++) begin
                // active on a change to the mode's level / edge:
                // 0 'L' level, 1 'H' level, 2 falling, 3 rising
                if (irq_pin[k] != pin_q[k]
                    && irq_pin[k] == ((extmdl[2*k +: 2] == 2'd1) || (extmdl[2*k +: 2] == 2'd3))) begin
                    icr_ir[8][k] <= 1'b1;
                    pirq_set <= 1'b1;
                end
            end

            // ---------------------------------------------- core events
            if (ill) nmicr[1] <= 1'b1;
            if (irq_take) iagr <= irq_take_group;

            // ---------------------------------------------- cycle stepping
            if (retire) begin
                pend <= pend + {1'b0, retire_cyc} - {5'd0, step};
                pend_nz <= (pend + {1'b0, retire_cyc} - {5'd0, step}) != 6'd0;
                arm_go <= arm_go | arm_req;
                arm_req <= 10'h0;
            end else if (step) begin
                pend <= pend - 6'd1;
                pend_nz <= pend != 6'd1;
            end
            if (!TIMER_EXACT) begin
                for (int k = 0; k < 2; k++)
                    if (step && p_mode[k][7]) p_cur[k] <= (p_cur[k] == 8'h0) ? p_base[k] : p_cur[k] - 8'd1;
            end
            for (int t = 0; t < 10; t++) begin
                if (step && armed[t] && !arm_req[t] && !arm_go[t]) begin
                    if (TIMER_EXACT) begin
                        if (t_psc[t] == 8'h0) begin
                            t_psc[t] <= t_pbl[t];
                            if (t_cnt[t] != 8'h0) t_cnt[t] <= t_cnt[t] - 8'd1;
                        end else begin
                            t_psc[t] <= t_psc[t] - 8'd1;
                        end
                    end else if (ptick[t_mode[t][0]] && t_cnt[t] != 8'h0) begin
                        t_cnt[t] <= t_cnt[t] - 8'd1;
                    end
                end
                if (tick[t]) begin
                    t_cur[t] <= full[t] ? t_base[t] : 8'hFF;
                    t_curz[t] <= full[t] && t_basez[t];
                    if (!casc[t+1 > 9 ? 9 : t+1] || t == 9) begin
                        icr_ir[1 + t/4][t%4] <= 1'b1;
                        pirq_set <= 1'b1;
                    end
                end else if (in_evt[t]) begin
                    t_cur[t] <= t_cur[t] - 8'd1;
                    t_curz[t] <= t_cur[t] == 8'd1;
                end
                if (own_exp[t]) begin
                    // re-arm with the new cur (MAME simple_timer_cb -> refresh_timer)
                    armed[t] <= t_enabled(t);
                    if (TIMER_EXACT) begin
                        t_pbl[t] <= p_base[t_mode[t][0]];
                        t_psc[t] <= p_base[t_mode[t][0]];
                    end
                    t_cnt[t] <= full[t] ? t_base[t] : 8'hFF;
                end
            end
            // deferred arming once the writing instruction's cycles are stepped
            if (!step && arm_go != 10'h0 && !retire) begin
                for (int t = 0; t < 10; t++) begin
                    if (arm_go[t]) begin
                        armed[t] <= t_enabled(t);
                        if (TIMER_EXACT) begin
                            t_pbl[t] <= p_base[t_mode[t][0]];
                            t_psc[t] <= p_base[t_mode[t][0]];
                        end
                        t_cnt[t] <= t_cur[t];
                    end
                end
                arm_go <= 10'h0;
            end

            // ---------------------------------------------- register reads with side effects
            if (io_rd && io_be[0] && io_addr == 10'h182) ser_recv <= ser_recv + 8'd1;

            // ---------------------------------------------- register writes (byte lanes)
            if (io_wr) begin
                for (int l = 0; l < 2; l++) begin
                    if (io_be[l]) begin : lane
                        logic [9:0] o;
                        logic [7:0] d;
                        o = {io_addr[9:1], l[0]};
                        d = io_wdata[8*l +: 8];
                        case (o)
                            10'h000: cpum <= d;
                            10'h040: nmicr <= nmicr & d;               // NMI acknowledge
                            10'h056: begin
                                extmdl <= d;
                                // check_ext_irq with the new mode
                                for (int k = 0; k < 4; k++)
                                    if ({1'b0, irq_pin[k]} == d[2*k +: 2]) icr_ir[8][k] <= 1'b1;
                                pirq_set <= 1'b1;
                            end
                            10'h057: extmdh <= d[1:0];
                            10'h180: ser_l[0] <= d;
                            10'h181: ser_h[0] <= d;
                            10'h190: ser_l[1] <= d;
                            10'h191: ser_h[1] <= d;
                            10'h21A: p_base[0] <= d;
                            10'h21B: p_base[1] <= d;
                            10'h22A, 10'h22B: begin
                                p_mode[o[0]] <= d & 8'hC0;
                                if (d[6]) p_cur[o[0]] <= p_base[o[0]];
                                arm_req <= 10'h3FF;                    // refresh_all_timers
                            end
                            10'h264: begin pout[1] <= d; p_wr[1] <= 1'b1; end
                            10'h3B0: pplul <= d[6:0];
                            10'h3B1: ppluh <= d[5:0];
                            10'h3C0: begin pout[0] <= d; p_wr[0] <= 1'b1; end
                            10'h3C2: begin pout[2] <= d & 8'h0F; p_wr[2] <= 1'b1; end
                            10'h3C3: begin pout[3] <= d & 8'h1F; p_wr[3] <= 1'b1; end
                            10'h3E0: pdir[0] <= d;
                            10'h3E1: pdir[1] <= d;
                            10'h3E2: pdir[2] <= d & 8'h0F;
                            10'h3E3: pdir[3] <= d & 8'h1F;
                            10'h3F3: p3md <= d[6:0];
                            default: begin
                                if (o >= 10'h042 && o <= 10'h055) begin
                                    if (!o[0]) begin
                                        icr_ir[o[5:1]] <= icr_ir[o[5:1]] & d[7:4];   // acknowledge
                                        if (o == 10'h050) begin
                                            // group 8: level-triggered pins stay requested
                                            for (int k = 0; k < 4; k++)
                                                if ({1'b0, irq_pin[k]} == extmdl[2*k +: 2]) icr_ir[8][k] <= 1'b1;
                                            pirq_set <= 1'b1;
                                        end
                                    end else begin
                                        icr_h[o[5:1]] <= d;
                                        pirq_set <= 1'b1;
                                    end
                                end else if (o >= 10'h210 && o <= 10'h219) begin
                                    t_base[o[3:0]] <= d;
                                    t_basez[o[3:0]] <= d == 8'h0;
                                end else if (o >= 10'h220 && o <= 10'h229) begin
                                    t_mode[o[3:0]] <= d & 8'hC3;
                                    if (d[6]) begin
                                        t_cur[o[3:0]] <= t_base[o[3:0]];
                                        t_curz[o[3:0]] <= t_basez[o[3:0]];
                                    end
                                    arm_req[o[3:0]] <= 1'b1;
                                end
                            end
                        endcase
                    end
                end
            end
        end
    end

    assign p0_out = pout[0] | ~pdir[0];
    assign p1_out = pout[1] | ~pdir[1];
    assign p2_out = pout[2] | (~pdir[2] & 8'h0F);
    assign p3_out = pout[3] | (~pdir[3] & 8'h1F);
endmodule
