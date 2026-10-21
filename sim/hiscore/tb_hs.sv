// High score save bench: rtl/gnet/gnet_hiscore.sv with rtl/gnet/hiscore.v,
// with and without GNET_HISCORE (docs/hiscore.md 5).
//
// Real RTL: sys/hps_io.sv; PSX.sv's own declarations, loader, save request,
// gnet_hiscore instance and channel 3 path (copied verbatim by gen_glue.py);
// rtl/gnet/cdc/cdc_handshake.vhd and rtl/gnet/zn2_ch3_arb.vhd (ghdl --synth
// to Verilog); gnet_hiscore.sv and hiscore.v.
// Models: Main_MiSTer's word handshake (fpga_spi with random HPS latency,
// arcade_nvm_load/save, MENU_SAVE_CHECK), sys_top's io_ack block and gp_out
// pipeline, PSX.sv's ioctl_wait branch for the G-NET indices, zn2_io's
// EEPROM copy, SDRAM channel 3 with random latency, zn2_board's flash port
// on arbiter port b with random reads, the DDR3 mirror stall at random,
// psx_top's pause (isPaused after a random wait for the subsystems to go
// idle), and the game: after each reset it clears its high score table and
// writes its defaults later (spuzbobl does both at 12.15 s and 14.76 s after
// a reset in MAME; scaled here to 3 ms and 8 ms), then changes scores when
// the bench says. The game RAM sits in the SDRAM model, so a reset or a
// reload keeps the old table there, as on the board.
//
// Checks on every channel 3 write while the game runs (none allowed) and
// outside the table (none allowed).
//
// Build: sim/hiscore/run.sh. HS defined = the GNET_HISCORE build.
// Plusargs: +out=<dir>, +quick (stop at the first failure).

`timescale 1ns/1ps
`define GNET_ZN2
`define GNET_SHELL
`define GNET_CPU50
`define GNET_LEAN
`define GNET_DDR3_ARB
`define GNET_DDR3_LOAD
`ifdef HS
`define GNET_HISCORE
`endif

module cdc_sync #(parameter WIDTH = 1, parameter STAGES = 2, parameter INIT = 0,
                  parameter SIM_META_WINDOW = 0, parameter SIM_SEED = 1)
                 (input clk, input rst, input [WIDTH-1:0] d, output logic [WIDTH-1:0] q);
    logic [WIDTH-1:0] s1 = '0;
    always @(posedge clk) begin s1 <= d; q <= s1; end
endmodule

module tb_hs;
    localparam int NVSIZE = 6144;
    localparam int TB     = 32'h28BF08;      // spuzbobl's table (hiscore.dat)
    localparam int TL     = 269;             // 0x10D
    localparam int T_CLEAR_US = 3000;        // game clears the table, after reset
    localparam int T_INIT_US  = 8000;        // game writes its defaults

    // ------------------------------------------------------------ clocks
    logic clk_1x = 0, clk_cpu = 0;
    always #14.7623 clk_1x = ~clk_1x;          // 33.8688 MHz
    initial begin #3.3; forever #10 clk_cpu = ~clk_cpu; end   // 50 MHz

    int errors = 0, checks = 0;
    bit stopped = 0;
    task automatic check(input string what, input bit ok);
        if (stopped) return;
        checks++;
        if (!ok) begin
            errors++; $display("FAIL %s", what);
            if ($test$plusargs("quick")) begin
                stopped = 1;
                $display("RESULT FAIL: stopped at the first failure (+quick), %0d checks", checks);
                $finish;
            end
        end
        else $display("ok   %s", what);
    endtask
    string out;

    // ------------------------------------------------------------ hps_io + sys_top
    wire [45:0] HPS_BUS;
    wire [35:0] EXT_BUS;
    assign EXT_BUS[32] = 1'b0;
    logic [31:0] gp_out = 0, gp_outd = 0, gp_outr = 0;
    always @(posedge clk_1x) begin gp_outr <= gp_outd; gp_outd <= gp_out; end
    wire io_clk = gp_outr[17], io_ss0 = gp_outr[18], io_ss1 = gp_outr[19], io_ss2 = gp_outr[20];
    wire io_fpga = ~io_ss1 & io_ss0;
    wire io_uio  = ~io_ss1 & io_ss2;
    logic io_ack = 0, rack = 0;
    wire io_strobe = ~rack & io_clk;
    wire io_wait   = HPS_BUS[37];
    always @(posedge clk_1x) begin
        if (~io_wait | io_strobe) begin
            rack   <= io_clk;
            io_ack <= rack;
        end
    end
    assign HPS_BUS[35] = io_fpga;
    assign HPS_BUS[34] = io_uio;
    assign HPS_BUS[33] = io_strobe;
    assign HPS_BUS[31:16] = gp_outr[15:0];
    assign HPS_BUS[45:38] = '0;

    wire        ioctl_download, ioctl_upload, ioctl_wr, ioctl_rd;
    wire [15:0] ioctl_index16;
    wire  [7:0] ioctl_index = ioctl_index16[7:0];
    wire [26:0] ioctl_addr;
    wire [15:0] ioctl_dout;
    reg         ioctl_wait = 0;
    reg         nv_upload_req = 1'b0;
    logic [15:0] nv_din = 0;
    logic OSD_STATUS = 0;

`include "glue_decl.svh"

    hps_io #(.CONF_STR("TB;;"), .WIDE(1)) hps_io (
        .clk_sys(clk_1x), .HPS_BUS(HPS_BUS), .EXT_BUS(EXT_BUS),
        .ioctl_download(ioctl_download), .ioctl_index(ioctl_index16), .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
`ifdef GNET_HISCORE
        .ioctl_wait(ioctl_wait | hs_io_wait),
`else
        .ioctl_wait(ioctl_wait),
`endif
        .ioctl_upload(ioctl_upload), .ioctl_upload_req(nv_upload_req), .ioctl_upload_index(8'd6),
`ifdef GNET_HISCORE
        .ioctl_din(hs_ul_sel ? hs_ul_din : nv_din),
`else
        .ioctl_din(nv_din),
`endif
        .ioctl_rd(ioctl_rd), .sd_buff_din('{16'h0}));

    // ------------------------------------------------------------ PSX.sv glue
    reg flash_download = 0, keys_download = 0, meta_download = 0, card_download = 0, ee_download = 0, dip_download = 0;
    always @(posedge clk_1x) begin
        keys_download  <= ioctl_download & (ioctl_index == 2);
        meta_download  <= ioctl_download & (ioctl_index == 4);
        card_download  <= ioctl_download & (ioctl_index == 5);
        ee_download    <= ioctl_download & (ioctl_index == 6);
        dip_download   <= ioctl_download & (ioctl_index == 254);
    end
    wire gnet_download = flash_download | keys_download | meta_download | card_download | ee_download;
    reg exe_download = 0, bios_download = 0;
    wire gnet_flash_dl = 1'b0;
    reg  ramdownload_wr = 0, ramdownload_rnw = 0, flc_busy = 0;
    reg [26:0] ramdownload_wraddr = 0;
    reg [31:0] ramdownload_wrdata = 0;
    wire [31:0] flc_rdata;
    wire sdramCh3_done;

    reg        zn_ld_wr = 0;
    reg  [1:0] zn_ld_target;
    reg [10:0] zn_ld_addr;
    reg [15:0] zn_ld_data;
    reg        zn_card_loaded = 0;
    reg        zn_card_dl_wr = 0;
    reg [25:0] zn_card_dl_addr;
    reg [15:0] zn_card_dl_data;
    reg        zn_card_wait = 0;
    wire       zn_card_dl_busy = 1'b0;
    wire       zn_ld_busy = 1'b0;
    reg  [7:0] zn_sw0;
`include "glue_loader.svh"

    // PSX.sv's ioctl_wait for the G-NET indices
    always @(posedge clk_1x) begin
        if (card_download) ioctl_wait <= zn_card_wait;
        else if (keys_download | meta_download | ee_download) ioctl_wait <= zn_ld_busy;
        else ioctl_wait <= 0;
    end

    // EEPROM (zn2_io): loader writes, CPU writes toggling the write toggle,
    // copy read registered on clk_1x
    logic [7:0] ee [2048];
    logic ee_tog = 0;
    always @(posedge clk_1x) begin
        if (zn_ld_wr && zn_ld_target == 2'd2) begin
            ee[{zn_ld_addr[10:1], 1'b0}] <= zn_ld_data[7:0];
            ee[{zn_ld_addr[10:1], 1'b1}] <= zn_ld_data[15:8];
        end
        nv_din <= {ee[{ioctl_addr[10:1], 1'b1}], ee[{ioctl_addr[10:1], 1'b0}]};
    end
    task automatic cpu_ee_write(input int a, input logic [7:0] v);
        @(posedge clk_cpu); ee[a] <= v; ee_tog <= ~ee_tog;
    endtask

`include "glue_req.svh"
    assign zn_nv_wtog = ee_tog;

    // core reset (PSX.sv: reset <= reset_or, which holds every G-NET download)
    // and pause (OSD open, pause on OSD on)
    logic tb_rst = 0;
    reg reset = 0, paused = 0;
    always @(posedge clk_1x) begin
        reset  <= tb_rst | gnet_download;
        paused <= OSD_STATUS;
    end
    wire isPaused;

`include "glue_inst.svh"

    // ------------------------------------------------------------ channel 3
    wire [26:0] ch3c_addr;
    wire [31:0] ch3c_din;
    wire        ch3c_rnw;
    wire  [3:0] ch3c_be;
    wire        ch3c_req;
    logic [31:0] ch3c_dout = 0;
    logic        ch3c_ready = 0;
    logic        gnet_ch3_stall = 0;
    logic        zn_fl_req = 0, zn_fl_rnw = 1;
    logic [26:0] zn_fl_addr = 0;
    logic [31:0] zn_fl_din = 0;
    logic  [3:0] zn_fl_be = 4'hF;
    wire         zn_fl_ready_c;
    wire  [31:0] zn_fl_dout;
`ifndef GNET_HISCORE
    wire hs_m_req = 1'b0;
`endif
`include "glue_ch3.svh"

    // SDRAM: main RAM at byte 0 (4 MB used); channel 3 with random latency
    logic [7:0] ram [8388608];
    bit   cpu_running;                         // the game's CPU runs (set by the psx model below)
    int   n_ch3_rd = 0, n_ch3_wr = 0, n_wr_running = 0, n_wr_outside = 0;
    realtime t_first_wr = 0, t_last_wr = 0;
    int   lat = 0; bit busy3 = 0;
    logic [26:0] a3; logic [31:0] d3; logic r3; logic [3:0] be3;
    always @(posedge clk_cpu) begin
        ch3c_ready <= 0;
        gnet_ch3_stall <= ($urandom_range(0, 15) == 0);
        if (ch3c_req && !busy3) begin
            busy3 <= 1; lat <= $urandom_range(4, 24);
            a3 <= ch3c_addr; d3 <= ch3c_din; r3 <= ch3c_rnw; be3 <= ch3c_be;
        end else if (busy3) begin
            if (lat > 0) lat <= lat - 1;
            else begin
                automatic int w = int'({a3[26:2], 2'b00});
                busy3 <= 0; ch3c_ready <= 1;
                if (r3) begin
                    ch3c_dout <= (w < 8388608) ? {ram[w+3], ram[w+2], ram[w+1], ram[w]} : 32'hA5A5A5A5;
                    if (w < 8388608) n_ch3_rd++;
                end else if (w < 8388608) begin
                    for (int b = 0; b < 4; b++) if (be3[b]) begin
                        ram[w + b] = d3[8*b +: 8];
                        if (w + b < TB || w + b >= TB + TL) n_wr_outside++;
                    end
                    n_ch3_wr++;
                    if (cpu_running) n_wr_running++;
                    if (t_first_wr == 0) t_first_wr = $realtime;
                    t_last_wr = $realtime;
                end
            end
        end
    end
    // zn2_board's flash port: random reads above main RAM (arbiter port b)
    always @(posedge clk_cpu) begin
        zn_fl_req <= 0;
        if (!zn_fl_req && $urandom_range(0, 200) == 0) begin
            zn_fl_req <= 1; zn_fl_rnw <= 1; zn_fl_addr <= 27'h1000000 + 27'($urandom_range(0, 65535) * 4);
        end
    end

    // ------------------------------------------------------------ psx_top pause and the game
    // pause (clk_1x level) reaches clk_cpu through two flip-flops; isPaused
    // rises after a random wait (the subsystems going idle), falls with the
    // pause; a reset drops it (psx_top reset_in clears pausing)
`ifdef GNET_HISCORE
    wire pause_core = paused | hs_pause;
`else
    wire pause_core = paused;
`endif
    logic pc1 = 0, pc2 = 0, rs1 = 0, rs2 = 0, pausing = 0;
    int   pwait = 0;
    int   pause_wait_max = 3000;             // clk_cpu clocks until the subsystems are idle
    always @(posedge clk_cpu) begin
        pc1 <= pause_core; pc2 <= pc1;
        rs1 <= reset; rs2 <= rs1;
        if (rs2) begin pausing <= 0; pwait <= 0; end
        else if (!pc2) begin pausing <= 0; pwait <= 0; end
        else if (!pausing) begin
            if (pwait == 0) pwait <= $urandom_range(1, pause_wait_max);
            else if (pwait == 1) pausing <= 1;
            else pwait <= pwait - 1;
        end
    end
    assign isPaused = pausing;
    assign cpu_running = !pausing && !rs2;

    // the game: a queue of byte writes done one per clk_cpu while it runs;
    // the boot after each reset clears and initialises the table
    logic [7:0] defaults [TL];
    int  wq_a [$]; logic [7:0] wq_d [$];
    realtime t_reset_rel = 0, t_clear = 0, t_init = 0;
    longint run_cycles = 0;                     // CPU cycles run since the reset
    bit cleared = 0, inited = 0;
    always @(posedge clk_cpu) begin
        if (rs2) begin
            run_cycles <= 0; cleared <= 0; inited <= 0;
            wq_a.delete(); wq_d.delete();
        end else if (cpu_running) begin
            run_cycles <= run_cycles + 1;
            if (!cleared && run_cycles == longint'(T_CLEAR_US) * 50) begin
                cleared <= 1; t_clear = $realtime;
                for (int i = 0; i < TL; i++) begin wq_a.push_back(TB + i); wq_d.push_back(8'h00); end
            end
            if (!inited && run_cycles == longint'(T_INIT_US) * 50) begin
                inited <= 1; t_init = $realtime;
                for (int i = 0; i < TL; i++) begin wq_a.push_back(TB + i); wq_d.push_back(defaults[i]); end
            end
            if (wq_a.size() > 0) begin
                ram[wq_a.pop_front()] = wq_d.pop_front();
            end
        end
    end
    task automatic game_score(input int off, input logic [7:0] v);   // the game changes one byte
        wq_a.push_back(TB + off); wq_d.push_back(v);
    endtask
    task automatic wait_game_idle();
        do @(posedge clk_cpu); while (wq_a.size() != 0);
    endtask
    function automatic bit table_is(input logic [7:0] exp [TL]);
        for (int i = 0; i < TL; i++) if (ram[TB + i] !== exp[i]) return 0;
        return 1;
    endfunction
    task automatic table_get(output logic [7:0] t [TL]);
        for (int i = 0; i < TL; i++) t[i] = ram[TB + i];
    endtask

    // ------------------------------------------------------------ Main_MiSTer model
    int hps_min = 20, hps_max = 300;           // ns per HPS bus access
    task automatic hd(); #($urandom_range(hps_min, hps_max) * 1ns); endtask
    task automatic gpo(input logic [31:0] v); hd(); gp_out = v; endtask
    task automatic spi(input logic [15:0] w, output logic [15:0] r);   // fpga_spi
        logic [31:0] g;
        g = (gp_out & ~32'h0002FFFF) | {16'h0, w};
        gpo(g); gpo(g | 32'h00020000);
        do hd(); while (!io_ack);
        gpo(g);
        do hd(); while (io_ack);
        r = HPS_BUS[15:0];
    endtask
    task automatic en_fpga(input bit on); gpo(on ? (gp_out | 32'h40000) : (gp_out & ~32'h40000)); endtask
    task automatic en_io(input bit on);   gpo(on ? (gp_out | 32'h100000) : (gp_out & ~32'h100000)); endtask
    task automatic set_index(input logic [7:0] idx);
        logic [15:0] r; en_fpga(1); spi(16'h55, r); spi({8'h00, idx}, r); en_fpga(0);
    endtask
    task automatic set_tx(input logic [7:0] mode);
        logic [15:0] r; en_fpga(1); spi(16'h53, r); spi({8'h00, mode}, r); en_fpga(0);
    endtask
    logic [7:0] fb [NVSIZE];                   // file buffer (Main's nvram buffer)
    task automatic tx(input logic [7:0] idx, input logic [7:0] d [], input int size);   // a <rom> or <nvram> download
        logic [15:0] r;
        set_index(idx); set_tx(8'hff);
        en_fpga(1); spi(16'h54, r);
        for (int k = 0; k < size; k += 2) spi({d[k + 1], d[k]}, r);
        en_fpga(0);
        set_tx(8'h00);
    endtask
    task automatic nvm_load(input int size);   // arcade_nvm_load
        logic [7:0] d []; d = new[size];
        for (int k = 0; k < size; k++) d[k] = fb[k];
        tx(6, d, size);
    endtask
    task automatic nvm_save(input int size);   // arcade_nvm_save
        logic [15:0] r;
        set_index(6); set_tx(8'haa);
        en_fpga(1); spi(16'h54, r);
        for (int k = 0; k < size; k += 2) begin spi(16'h0000, r); fb[k] = r[7:0]; fb[k + 1] = r[15:8]; end
        en_fpga(0);
        set_tx(8'h00);
    endtask
    task automatic chk_upload(output logic [15:0] r);   // UIO_CHK_UPLOAD
        en_io(1); spi(16'h3C, r); en_io(0);
    endtask
    realtime t_osd = 0;
`ifdef GNET_HISCORE
    // how long uploads were held at the high score area for a snapshot
    longint n_hold = 0; realtime t_ul_area = 0, t_ex_end = 0;
    always @(posedge clk_1x) begin
        if (hs_ul_sel && (hiscore_save.in_dump || hiscore_save.in_mrk) && hiscore_save.ex_busy) n_hold <= n_hold + 1;
        if (hs_ul_sel && hiscore_save.in_mrk && t_ul_area == 0) t_ul_area = $realtime;
    end
    always @(negedge hiscore_save.ex_busy) t_ex_end = $realtime;
`endif
    // the OSD main menu opens: MENU_SAVE_CHECK after check_us; saves if the
    // core asked (hps_io keeps a request until this check reads it)
    task automatic osd_open(input int size, input int check_us, input int stay_us, output bit saved);
        logic [15:0] r;
        OSD_STATUS = 1;
        t_osd = $realtime;
        #(check_us * 1us);
        chk_upload(r);
        saved = (r == 16'h0601);
        if (saved) nvm_save(size);
        #(stay_us * 1us);
        OSD_STATUS = 0;
        #20us;
    endtask
    // hiscore.dat config block as the MRA carries it (START_WAIT scaled to
    // 1 ms; the release MRA uses 1 s, docs/hiscore.md 4)
    logic [7:0] cfg [24] = '{8'h00, 8'h00, 8'h84, 8'h4A,  8'hFF, 8'hFF,  8'h00, 8'h02,  8'h00, 8'h02,
                             8'h00, 8'h01,  8'h00, 8'h0F,  8'h10,  8'h00,
                             8'h00, 8'h28, 8'hBF, 8'h08,  8'h01, 8'h0D,  8'h20,  8'h01};
    task automatic mra_load(input bit with_cfg, input int nv_size, input bit with_file);
        logic [7:0] d []; d = new[24];
        for (int k = 0; k < 24; k++) d[k] = cfg[k];
        tb_rst = 1;                            // Main: core in reset while it loads
        #5us;
        if (with_cfg) tx(8, d, 24);
        if (with_file) nvm_load(nv_size);
        #5us;
        tb_rst = 0;
        t_reset_rel = $realtime;
    endtask
    task automatic osd_reset();                // OSD Reset: no download
        tb_rst = 1; #5us; tb_rst = 0; t_reset_rel = $realtime;
    endtask

    // ------------------------------------------------------------ file checks
    function automatic bit fb_ee_at(input int base, input logic [7:0] exp [2048]);
        for (int k = 0; k < 2048; k++) if (fb[base + k] !== exp[k]) return 0;
        return 1;
    endfunction
    function automatic bit fb_zero(input int a, input int b);
        for (int k = a; k < b; k++) if (fb[k] !== 8'h00) return 0;
        return 1;
    endfunction
    function automatic bit fb_dump_is(input logic [7:0] exp [TL]);
        for (int k = 0; k < TL; k++) if (fb[2564 + k] !== exp[k]) return 0;
        return 1;
    endfunction
    function automatic bit fb_marker();
        return fb[2560] == 8'h47 && fb[2561] == 8'h4E && fb[2562] == 8'h48 && fb[2563] == 8'h53;
    endfunction
    function automatic bit ee_is(input logic [7:0] exp [2048]);
        for (int k = 0; k < 2048; k++) if (ee[k] !== exp[k]) return 0;
        return 1;
    endfunction
    task automatic save_hex(input string f, input int size);
        int fd = $fopen(f, "w");
        for (int k = 0; k < size; k++) $fwrite(fd, "%02x\n", fb[k]);
        $fclose(fd);
    endtask
    // the file as the build should write it: EEPROM, zero, marker, dump,
    // zero, EEPROM mirror
    function automatic bit fb_layout(input logic [7:0] eexp [2048], input logic [7:0] dexp [TL], input bit mrk);
        return fb_ee_at(0, eexp) && fb_zero(2048, 2560) && (mrk ? fb_marker() : fb_zero(2560, 2564)) &&
               fb_dump_is(dexp) && fb_zero(2564 + TL, 4096) && fb_ee_at(4096, eexp);
    endfunction

    // ------------------------------------------------------------ test
    logic [7:0] ee_a [2048], ee_b [2048];
    logic [7:0] tab1 [TL], tab2 [TL], tab3 [TL], stale [TL];
    realtime t_req_first = 0;
    always @(posedge clk_1x) if (nv_upload_req && t_req_first == 0) t_req_first = $realtime;
    initial begin
        bit saved; int w0, r0;
        if (!$value$plusargs("out=%s", out)) out = "work";
        for (int i = 0; i < TL; i++) defaults[i] = 8'((i * 37 + 11) ^ (i >> 3));
        defaults[0] = 8'h20; defaults[TL - 1] = 8'h01;   // hiscore.dat start and end
        for (int k = 0; k < 2048; k++) begin ee[k] <= 8'hFF; ee_a[k] = (k < 44) ? 8'(k * 7 + 3) : 8'hFF; end
        // SDRAM from an earlier core: random bytes
        for (int i = 0; i < 8388608; i += 4) begin
            automatic logic [31:0] v = $urandom;
            ram[i] = v[7:0]; ram[i+1] = v[15:8]; ram[i+2] = v[23:16]; ram[i+3] = v[31:24];
        end
        ram[TB] = 8'h5A;                       // not hiscore.dat's start value
        repeat (20) @(posedge clk_1x);

        // ================================================= A: a set without the block, 2 KB MRA (both builds)
        $display("-- A EEPROM-only MRA (no hiscore block), 2 KB");
        for (int k = 0; k < NVSIZE; k++) fb[k] = 0;
        for (int k = 0; k < 2048; k++) fb[k] = ee_a[k];
        mra_load(0, 2048, 1);
        check("A EEPROM loaded from the 2 KB file", ee_is(ee_a));
        #100us;
        cpu_ee_write(17, 8'h99); ee_a[17] = 8'h99;
        #5us;
        osd_open(2048, 2, 20, saved);
        check("A OSD open after an EEPROM write: Main saves", saved);
        check("A saved 2 KB file equals the EEPROM", fb_ee_at(0, ee_a));
        save_hex({out, "/out_a.hex"}, 2048);
        osd_open(2048, 2, 20, saved);
        check("A OSD open with nothing changed: no request", !saved);
        check("A no channel 3 traffic to main RAM", n_ch3_rd == 0 && n_ch3_wr == 0);

`ifdef GNET_HISCORE
        // a MRA load reprograms the FPGA, so a second scenario that starts
        // from a load runs in its own simulation (+old)
        if ($test$plusargs("old")) begin
            // ================================================= E: a 2 KB file from an older release
            $display("-- E spuzbobl MRA with a 2 KB file from an older release (zero padded by Main)");
            for (int k = 2048; k < NVSIZE; k++) fb[k] = 0;
            for (int k = 0; k < 2048; k++) fb[k] = ee_a[k];
            w0 = n_ch3_wr;
            mra_load(1, NVSIZE, 1);
            check("E no dump taken (no marker)", !hiscore_save.dump_loaded);
            wait (inited); wait_game_idle();
            #5000us;
            check("E nothing restored: the game's defaults stay", n_ch3_wr == w0 && table_is(defaults));
            game_score('h90, 8'h12); wait_game_idle();
            table_get(tab3);
            osd_open(NVSIZE, 2, 200, saved);
            if (!saved) osd_open(NVSIZE, 2, 200, saved);
            check("E a score after the old file: saved with the layout and marker", saved && fb_layout(ee_a, tab3, 1));
            // a file saved by an older RBF from a 6144-byte MRA: the EEPROM
            // repeated (its upload wraps on 2 KB)
            $display("-- E2 spuzbobl MRA with a file an older RBF saved (EEPROM repeated)");
            for (int k = 0; k < NVSIZE; k++) fb[k] = ee_a[k % 2048];
            w0 = n_ch3_wr;
            mra_load(1, NVSIZE, 1);
            check("E2 EEPROM loaded from the first 2 KB", ee_is(ee_a));
            check("E2 no dump taken (no marker)", !hiscore_save.dump_loaded);
            wait (inited); wait_game_idle();
            #5000us;
            check("E2 nothing restored", n_ch3_wr == w0);

        end else begin
        // ================================================= B: spuzbobl, first run (no .nvm yet)
        $display("-- B spuzbobl MRA (block + 6144-byte NVRAM), no .nvm file yet");
        mra_load(1, NVSIZE, 0);
        check("B the hiscore block is configured", hiscore_save.configured);
        #1000us;
        r0 = n_ch3_rd;
        check("B before the game's table: only polls (no writes)", n_ch3_wr == 0);
        osd_open(NVSIZE, 2, 200, saved);
        check("B OSD open before the game's table is there: no save request", !saved && !hiscore_save.dump_valid);
        wait (inited); wait_game_idle(); #4000us;
        check("B the game's defaults are in RAM", table_is(defaults));
        check("B the table counts as fresh after the clear and the defaults", hiscore_save.fresh);
        r0 = n_ch3_rd; #6000us;
        check("B fresh: polling stops", n_ch3_rd == r0);
        // the player sets a score in the second ranking
        game_score('h60, 8'h3C); game_score('h66, 8'h41); game_score('h67, 8'h42); game_score('h68, 8'h43);
        wait_game_idle();
        table_get(tab1);
        t_req_first = 0;
        osd_open(NVSIZE, 2, 200, saved);
        $display("     save request %0.1f us after the OSD opened", (t_req_first - t_osd) / 1000.0);
        if (!saved) begin
            $display("     request came after Main's check at 2 us; next OSD open saves it");
            osd_open(NVSIZE, 2, 200, saved);
        end
        check("B a score: saved by the first or second OSD open", saved);
        check("B file: EEPROM, zero, marker, dump = the table, zero, EEPROM mirror", fb_layout(ee_a, tab1, 1));
        save_hex({out, "/out_b.hex"}, NVSIZE);
        check("B no channel 3 write in B (nothing to restore)", n_ch3_wr == 0);
        osd_open(NVSIZE, 2, 200, saved);
        check("B OSD open with nothing changed: no request", !saved);
        // later scores that are never saved stay in SDRAM for the reload
        // (start and end bytes as hiscore.dat's: only the gate keeps a
        // restore out of this old table)
        game_score('h70, 8'h77); game_score('h71, 8'h99);
        wait_game_idle();
        table_get(stale);

        // ================================================= C: reload with the saved file; stale table in SDRAM
        $display("-- C reload: the file from B; the SDRAM still holds a later table");
        w0 = n_ch3_wr; t_first_wr = 0;
        mra_load(1, NVSIZE, 1);                // fb holds out_b
        check("C EEPROM loaded from the file", ee_is(ee_a));
        check("C dump accepted (marker)", hiscore_save.dump_loaded);
        wait (inited); wait_game_idle();
        #5000us;
        check("C restored after the game wrote its defaults, never before its clear",
              n_ch3_wr > w0 && t_first_wr > t_init);
        check("C RAM table equals the saved table", table_is(tab1));
        check("C no write while the game ran", n_wr_running == 0);
        check("C no write outside the table", n_wr_outside == 0);
        check("C writes: one per table byte", n_ch3_wr - w0 == TL);
        osd_open(NVSIZE, 2, 200, saved);
        check("C OSD open, table as restored: no request", !saved);
        // a new top score: the table's start byte is no longer hiscore.dat's
        game_score('h00, 8'h55); game_score('h01, 8'hC3); game_score('h06, 8'h5A); game_score('h20, 8'h11);
        wait_game_idle();
        table_get(tab2);
        osd_open(NVSIZE, 2, 200, saved);
        if (!saved) osd_open(NVSIZE, 2, 200, saved);
        check("C new top score saved", saved && fb_layout(ee_a, tab2, 1));
        save_hex({out, "/out_c.hex"}, NVSIZE);

        // ================================================= D: OSD reset (no reload): restore again
        $display("-- D OSD reset, no download");
        w0 = n_ch3_wr; t_first_wr = 0;
        osd_reset();
        wait (inited); wait_game_idle();
        #5000us;
        check("D restored again after the defaults", n_ch3_wr - w0 == TL && t_first_wr > t_init);
        check("D RAM table equals the last saved table (start byte not hiscore.dat's)", table_is(tab2));
        check("D no write while the game ran", n_wr_running == 0 && n_wr_outside == 0);

        // ================================================= F: EEPROM write and a score at the same OSD open
        $display("-- F EEPROM and a score change, one OSD open, Main checks at 2 us");
        cpu_ee_write(3, 8'h3E); ee_a[3] = 8'h3E;
        // a new top score: the dump's first word changes (read first by the upload)
        game_score('h00, 8'h21); game_score('h01, 8'h22); game_score('hA1, 8'h23); wait_game_idle();
        table_get(tab3);
        #5us;
        pause_wait_max = 150000;               // 3 ms until the core pauses: the upload reaches the dump first
        n_hold = 0; t_ul_area = 0;
        osd_open(NVSIZE, 2, 4000, saved);
        pause_wait_max = 3000;
        $display("     upload reached the high score area %0.1f us after the OSD opened, snapshot window closed at %0.1f us, held %0d clocks",
                 (t_ul_area - t_osd) / 1000.0, (t_ex_end - t_osd) / 1000.0, n_hold);
        check("F saved at once (the EEPROM's request)", saved);
        check("F the same save holds the new score (upload waited for the snapshot)", fb_layout(ee_a, tab3, 1));
        check("F no write while the game ran, none outside the table", n_wr_running == 0 && n_wr_outside == 0);
        osd_open(NVSIZE, 2, 200, saved);
        check("F next OSD open: no repeat save (the save in progress carried the snapshot)", !saved);
        end
`endif

        $display("RESULT %s: %0d checks, %0d failed", errors ? "FAIL" : "PASS", checks, errors);
        $finish;
    end
    initial begin #400ms; $display("RESULT FAIL: timeout"); $finish; end
endmodule
