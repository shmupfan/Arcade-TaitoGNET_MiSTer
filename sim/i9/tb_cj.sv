// Issue #9 bench: the card hunk journal (rtl/gnet/gnet_card_journal.sv) and
// the EEPROM NVRAM save, with and without GNET_CARD_JOURNAL.
//
// Real RTL: sys/hps_io.sv; PSX.sv's own loader, save request and journal
// instance (copied verbatim by gen_glue.py); gnet_card_journal.sv;
// rtl/gnet/zn2_cardmem.vhd (ghdl --synth to Verilog, CARD_JOURNAL = true);
// rtl/gnet/gnet_ata.sv on clk_cpu (the game's card writes).
// Models: Main_MiSTer's word handshake (fpga_spi with random HPS latency),
// sys_top's io_ack block and gp_out pipeline (copied), PSX.sv's ioctl_wait
// branch for the G-NET indices (copied), zn2_io's EEPROM copy (registered
// read), the zn2_board event source (copy of its process) behind a channel
// with independent random delays of 0 to 14 ns per bit (the cdc.sdc bound),
// a DDR3 arbiter port with random latency, cdc_sync as two flip-flops.
//
// Build: sim/i9/run.sh (CJ defined = journal build). Plusargs: +work=<dir>,
// +fold=<file> (journal build: a file saved by the build without journal).

`timescale 1ns/1ps
`ifndef GNET_ZN2
`define GNET_ZN2
`endif
`ifndef GNET_SHELL
`define GNET_SHELL
`endif
`ifdef CJ
`define GNET_CARD_JOURNAL
`endif

module cdc_sync #(parameter WIDTH = 1, parameter STAGES = 2, parameter INIT = 0,
                  parameter SIM_META_WINDOW = 0, parameter SIM_SEED = 1)
                 (input clk, input rst, input [WIDTH-1:0] d, output logic [WIDTH-1:0] q);
    logic [WIDTH-1:0] s1 = '0;
    always @(posedge clk) begin s1 <= d; q <= s1; end
endmodule

module tb_cj;
    localparam int NVSIZE = 268288;
    localparam int CARD   = 40960000;
    localparam logic [27:0] BASE = 28'h4000000;

    // ------------------------------------------------------------ clocks
    logic clk_1x = 0, clk_2x = 0, clk_cpu = 0;
    always #14.7623 clk_1x = ~clk_1x;          // 33.8688 MHz
    always #7.38115 clk_2x = ~clk_2x;          // 2 x clk_1x, same edges
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
    string work, out;

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
    wire [15:0] nv_din_w;
    logic [15:0] nv_din = 0;
    assign nv_din_w = nv_din;
    logic OSD_STATUS = 0;

`include "glue_decl.svh"

    hps_io #(.CONF_STR("TB;;"), .WIDE(1)) hps_io (
        .clk_sys(clk_1x), .HPS_BUS(HPS_BUS), .EXT_BUS(EXT_BUS),
        .ioctl_download(ioctl_download), .ioctl_index(ioctl_index16), .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
`ifdef GNET_CARD_JOURNAL
        .ioctl_wait(ioctl_wait | cj_wait),
`else
        .ioctl_wait(ioctl_wait),
`endif
        .ioctl_upload(ioctl_upload), .ioctl_upload_req(nv_upload_req), .ioctl_upload_index(8'd6),
`ifdef GNET_CARD_JOURNAL
        .ioctl_din(cj_din),
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
    reg        zn_ld_wr = 0;
    reg  [1:0] zn_ld_target;
    reg [10:0] zn_ld_addr;
    reg [15:0] zn_ld_data;
    reg        zn_card_loaded = 0;
    reg        zn_card_dl_wr = 0;
    reg [25:0] zn_card_dl_addr;
    reg [15:0] zn_card_dl_data;
    reg        zn_card_wait = 0;
    wire       zn_card_dl_busy;
    wire       zn_ld_busy = 1'b0;
    reg  [7:0] zn_sw0;

`include "glue_loader.svh"

    // PSX.sv's ioctl_wait for the G-NET indices (the always block that also
    // serves the BIOS and flash paths; only these branches apply here)
    always @(posedge clk_1x) begin
        if (card_download) ioctl_wait <= zn_card_wait;
`ifdef GNET_CARD_JOURNAL
        else if (ee_download) ioctl_wait <= zn_ld_busy | zn_card_wait;
        else if (keys_download | meta_download) ioctl_wait <= zn_ld_busy;
`else
        else if (keys_download | meta_download | ee_download) ioctl_wait <= zn_ld_busy;
`endif
        else ioctl_wait <= 0;
    end

    // EEPROM (zn2_io): loader writes (word = two bytes), CPU writes on
    // clk_cpu toggling the write toggle, copy read registered on clk_1x
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

    // ------------------------------------------------------------ card memory
    logic [63:0] ddr [8388608];                // card at BASE, qword index
    logic        mem_request, mem_WE, mem_RD;
    logic [27:0] mem_ADDR;
    logic [63:0] mem_DIN;
    logic  [7:0] mem_BE, mem_BURSTCNT;
    logic        mem_ack = 0, mem_DOUT_READY = 0;
    logic [63:0] mem_DOUT = 0;
    logic        cm_ack;
    logic [15:0] cm_rdata;
    realtime     t_last_mwrite = 0;
    int          mem_writes = 0;

`ifdef GNET_CARD_JOURNAL
    zn2_cardmem cardmem (.clk2x(clk_2x), .reset(1'b0),
        .dl_wr(zn_card_dl_wr), .dl_addr(zn_card_dl_addr), .dl_data(zn_card_dl_data), .dl_busy(zn_card_dl_busy),
        .cm_req(1'b0), .cm_we(1'b0), .cm_addr(25'd0), .cm_wdata(16'd0), .cm_ack(cm_ack), .cm_rdata(cm_rdata),
        .ul_req(cj_rd_req), .ul_line(cj_rd_line), .ul_ack(cj_rd_ack), .ul_data(cj_rd_data),
        .mem_request(mem_request), .mem_BURSTCNT(mem_BURSTCNT), .mem_ADDR(mem_ADDR), .mem_DIN(mem_DIN),
        .mem_BE(mem_BE), .mem_WE(mem_WE), .mem_RD(mem_RD), .mem_ack(mem_ack), .mem_DOUT(mem_DOUT),
        .mem_DOUT_READY(mem_DOUT_READY));
`else
    zn2_cardmem cardmem (.clk2x(clk_2x), .reset(1'b0),
        .dl_wr(zn_card_dl_wr), .dl_addr(zn_card_dl_addr), .dl_data(zn_card_dl_data), .dl_busy(zn_card_dl_busy),
        .cm_req(1'b0), .cm_we(1'b0), .cm_addr(25'd0), .cm_wdata(16'd0), .cm_ack(cm_ack), .cm_rdata(cm_rdata),
        .ul_req(1'b0), .ul_line(23'd0), .ul_ack(), .ul_data(),
        .mem_request(mem_request), .mem_BURSTCNT(mem_BURSTCNT), .mem_ADDR(mem_ADDR), .mem_DIN(mem_DIN),
        .mem_BE(mem_BE), .mem_WE(mem_WE), .mem_RD(mem_RD), .mem_ack(mem_ack), .mem_DOUT(mem_DOUT),
        .mem_DOUT_READY(mem_DOUT_READY));
`endif

    // DDR3 arbiter port: random latency to the acknowledge and to the data
    int dlat_max = 40;
    typedef enum {D_IDLE, D_ACK, D_DATA, D_DONE} dst_t;
    dst_t ds = D_IDLE;
    int   dcnt = 0;
    always @(posedge clk_2x) begin
        mem_ack        <= 0;
        mem_DOUT_READY <= 0;
        case (ds)
            D_IDLE: if (mem_request) begin dcnt <= $urandom_range(0, dlat_max); ds <= D_ACK; end
            D_ACK: if (dcnt > 0) dcnt <= dcnt - 1;
                   else begin
                       automatic int i = int'((mem_ADDR - BASE) >> 3);
                       mem_ack <= 1;
                       if (mem_WE) begin
                           for (int b = 0; b < 8; b++) if (mem_BE[b]) ddr[i][8*b +: 8] = mem_DIN[8*b +: 8];
                           t_last_mwrite = $realtime;
                           mem_writes++;
                           ds <= D_DONE;
                       end else begin
                           dcnt <= $urandom_range(0, dlat_max);
                           ds <= D_DATA;
                       end
                   end
            D_DATA: if (dcnt > 0) dcnt <= dcnt - 1;
                    else begin
                        mem_DOUT <= ddr[int'((mem_ADDR - BASE) >> 3)];
                        mem_DOUT_READY <= 1;
                        ds <= D_DONE;
                    end
            D_DONE: if (!mem_request) ds <= D_IDLE;
        endcase
    end

    // ------------------------------------------------------------ game side: gnet_ata on clk_cpu
    logic ata_rst = 1, attr_req = 0, attr_we = 0, attr_ack; logic [19:0] attr_waddr = 0; logic [15:0] attr_wdata = 0, attr_rdata;
    logic tf_req = 0, tf_we = 0, tf_ack; logic [15:0] tf_off = 0, tf_wdata = 0, tf_rdata; logic [1:0] tf_bmask = 0;
    logic meta_we = 0; logic [9:0] meta_addr = 0; logic [7:0] meta_wdata = 0;
    logic st_req, st_we, st_ack = 0; logic [24:0] st_addr; logic [15:0] st_wdata, st_rdata = 0;
    logic dirty_set, dirty_rdata, dbg_sec_cmd; logic [13:0] dirty_hunk;
    gnet_ata #(.CLK_HZ(50_000_000)) ata (
        .clk(clk_cpu), .rst(ata_rst), .card_reset(1'b0), .attr_req, .attr_we, .attr_waddr, .attr_wdata, .attr_ack, .attr_rdata,
        .tf_req, .tf_we, .tf_off, .tf_bmask, .tf_wdata, .tf_ack, .tf_rdata,
        .meta_we, .meta_addr, .meta_wdata, .key_valid(1'b1),
        .st_req, .st_we, .st_addr, .st_wdata, .st_ack, .st_rdata,
        .dirty_set, .dirty_hunk, .dirty_raddr(14'd0), .dirty_rdata, .dirty_clear(1'b0), .dbg_sec_cmd);
    // storage: the same card memory (the release path to it, zn2_cdc and
    // zn2_cardmem's gnet_ata port, is unchanged by the journal)
    always @(posedge clk_cpu) begin
        st_ack <= 0;
        if (st_req && !st_ack) begin
            st_ack <= 1;
            if (st_we) ddr[st_addr[24:2]][16*st_addr[1:0] +: 16] = st_wdata;
            else st_rdata <= ddr[st_addr[24:2]][16*st_addr[1:0] +: 16];
        end
    end

    // zn2_board's event source (copy of its process), plus an injector for
    // the crossing stress test
    logic inj_set = 0; logic [13:0] inj_hunk = 0;
    logic cdc_tx_cjtog = 0; logic [13:0] cdc_tx_cjhunk = 0;
    always @(posedge clk_cpu) begin
        if (dirty_set | inj_set) begin
            cdc_tx_cjtog  <= ~cdc_tx_cjtog;
            cdc_tx_cjhunk <= inj_set ? inj_hunk : dirty_hunk;
        end
    end
    // routing to the journal: each bit delayed by 0 to 14 ns on its own
    logic ch_tog = 0; logic [13:0] ch_hunk = 0;
    always @(cdc_tx_cjtog) begin
        automatic logic v = cdc_tx_cjtog;
        fork begin #($urandom_range(0, 14000) * 1ps); ch_tog = v; end join_none
    end
    for (genvar g = 0; g < 14; g++) begin : skew
        always @(cdc_tx_cjhunk[g]) begin
            automatic logic v = cdc_tx_cjhunk[g];
            fork begin #($urandom_range(0, 14000) * 1ps); ch_hunk[g] = v; end join_none
        end
    end
`ifdef GNET_CARD_JOURNAL
    assign cj_tog  = ch_tog;
    assign cj_hunk = ch_hunk;
`endif

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
    task automatic set_tx(input logic [7:0] mode, input int addr);
        logic [15:0] r; en_fpga(1); spi(16'h53, r); spi({8'h00, mode}, r);
        if (mode != 0 && addr != 0) begin spi(addr[15:0], r); spi(addr[31:16], r); end
        en_fpga(0);
    endtask
    logic [7:0] fb [NVSIZE];                   // file buffer (Main's nvram buffer)
    task automatic nvm_load(input int size);   // arcade_nvm_load
        logic [15:0] r;
        set_index(6); set_tx(8'hff, 0);
        en_fpga(1); spi(16'h54, r);
        for (int k = 0; k < size; k += 2) spi({fb[k + 1], fb[k]}, r);
        en_fpga(0);
        set_tx(8'h00, 0);
    endtask
    task automatic nvm_save(input int size);   // arcade_nvm_save
        logic [15:0] r;
        set_index(6); set_tx(8'haa, 0);
        en_fpga(1); spi(16'h54, r);
        for (int k = 0; k < size; k += 2) begin spi(16'h0000, r); fb[k] = r[7:0]; fb[k + 1] = r[15:8]; end
        en_fpga(0);
        set_tx(8'h00, 0);
    endtask
    task automatic chk_upload(output logic [15:0] r);   // UIO_CHK_UPLOAD
        en_io(1); spi(16'h3C, r); en_io(0);
    endtask
    // OSD main menu opens: MENU_SAVE_CHECK; returns 1 if Main saved
    task automatic osd_open(input int size, output bit saved);
        logic [15:0] r;
        OSD_STATUS = 1;
        #2us;
        chk_upload(r);
        saved = (r == 16'h0601);
        if (saved) nvm_save(size);
        #2us;
        OSD_STATUS = 0;
        #2us;
    endtask
    // card image load with the DDR3 path (issue #12): Main copies, the core
    // sees index 5 with the length
    logic [7:0] img [CARD];
    task automatic load_img(input string f);
        int fd, n;
        fd = $fopen(f, "rb");
        if (fd == 0) $fatal(1, "cannot open %s", f);
        n = $fread(img, fd);
        $fclose(fd);
        if (n != CARD) $fatal(1, "%s: %0d bytes", f, n);
    endtask
    task automatic img_to_ddr();
        for (int i = 0; i < CARD / 8; i++)
            ddr[i] = {img[8*i+7], img[8*i+6], img[8*i+5], img[8*i+4], img[8*i+3], img[8*i+2], img[8*i+1], img[8*i]};
    endtask
    task automatic card_load(input string f);
        set_index(5); set_tx(8'hff, CARD);
        load_img(f); img_to_ddr();
        set_tx(8'h00, 0);
        wlog_n = 0;
    endtask
    // the game's writes since the last card load (for the expected image)
    int wlog_n = 0; int wlog_lba [256]; logic [7:0] wlog_d [256][512];
    function automatic bit ddr_is_img_plus_log();   // ddr == img with wlog applied
        for (int k = 0; k < wlog_n; k++)
            for (int b = 0; b < 512; b++) img[wlog_lba[k] * 512 + b] = wlog_d[k][b];
        for (int i = 0; i < CARD / 8; i++)
            if (ddr[i] != {img[8*i+7], img[8*i+6], img[8*i+5], img[8*i+4], img[8*i+3], img[8*i+2], img[8*i+1], img[8*i]}) begin
                $display("     first difference at card byte %0d", 8 * i);
                return 0;
            end
        return 1;
    endfunction

    // gnet_ata host side (as sim/gnet_ata/tb_ata_t2.sv)
    logic [7:0] KEY [5] = '{8'h12, 8'h34, 8'h56, 8'h78, 8'h9a};   // arbitrary test key, as tb_ata_t2
    task automatic meta(input int a, input logic [7:0] d);
        @(posedge clk_cpu); meta_we <= 1; meta_addr <= 10'(a); meta_wdata <= d;
        @(posedge clk_cpu); meta_we <= 0;
    endtask
    task automatic tf(input logic we, input int off, input logic [1:0] bm, input logic [15:0] d, output logic [15:0] q);
        @(posedge clk_cpu); tf_req <= 1; tf_we <= we; tf_off <= 16'(off); tf_bmask <= bm; tf_wdata <= d;
        @(posedge clk_cpu); tf_req <= 0;
        while (!tf_ack) @(posedge clk_cpu);
        q = tf_rdata;
    endtask
    task automatic wr(input int r, input logic [7:0] v);
        logic [15:0] q;
        if (r[0]) tf(1, r - 1, 2'b10, {v, 8'h00}, q); else tf(1, r, 2'b01, {8'h00, v}, q);
    endtask
    task automatic rd(input int r, output logic [7:0] v);
        logic [15:0] q;
        if (r[0]) begin tf(0, r - 1, 2'b10, 0, q); v = q[15:8]; end
        else      begin tf(0, r,     2'b01, 0, q); v = q[7:0];  end
    endtask
    task automatic aw(input int a, input logic [15:0] d);
        @(posedge clk_cpu); attr_req <= 1; attr_we <= 1; attr_waddr <= 20'(a); attr_wdata <= d;
        @(posedge clk_cpu); attr_req <= 0;
        while (!attr_ack) @(posedge clk_cpu);
    endtask
    task automatic ata_init();
        logic [7:0] s;
        for (int i = 0; i < 1024; i++) meta(i, 8'h00);
        meta(8'h78, 8'(80000)); meta(8'h79, 8'(80000 >> 8)); meta(8'h7a, 8'(80000 >> 16));
        for (int i = 0; i < 5; i++) meta(10'h300 + i, KEY[i]);
        repeat (4) @(posedge clk_cpu); ata_rst <= 0;
        do rd(7, s); while (s[7]);
        for (int i = 0; i < 5; i++) aw(16'h280 + i, {8'h00, KEY[i]});
        for (int i = 5; i < 9; i++) aw(16'h280 + i, 16'h0000);
    endtask
    logic [7:0] sec [512];
    task automatic game_write(input int lba);   // WRITE SECTORS of sec[] at lba
        logic [7:0] s; logic [15:0] q;
        wr(6, 8'hE0 | 8'((lba >> 24) & 15)); wr(5, 8'(lba >> 16)); wr(4, 8'(lba >> 8)); wr(3, 8'(lba)); wr(2, 8'd1);
        wr(7, 8'h30);
        do rd(7, s); while (!s[3]);
        for (int w = 0; w < 256; w++) tf(1, 0, 2'b11, {sec[2*w+1], sec[2*w]}, q);
        do rd(7, s); while (s[7]);
        #5us;   // the event reaches the journal within about 2.2 us (crossing and list search)
        wlog_lba[wlog_n] = lba;
        for (int b = 0; b < 512; b++) wlog_d[wlog_n][b] = sec[b];
        wlog_n++;
    endtask
    task automatic game_writes_file(input string f);   // records: LBA (4 bytes LE) + 512 bytes
        int fd, c, lba;
        fd = $fopen(f, "rb");
        if (fd == 0) $fatal(1, "cannot open %s", f);
        forever begin
            c = $fgetc(fd);
            if (c < 0) break;
            lba = c | ($fgetc(fd) << 8) | ($fgetc(fd) << 16) | ($fgetc(fd) << 24);
            for (int b = 0; b < 512; b++) sec[b] = 8'($fgetc(fd));
            game_write(lba);
        end
        $fclose(fd);
    endtask
    task automatic game_write_pattern(input int lba, input int tag);
        for (int b = 0; b < 512; b++) sec[b] = 8'((b * 7 + tag * 13 + 1) & 255);
        game_write(lba);
    endtask

    // ------------------------------------------------------------ file helpers
    task automatic save_hex(input string f, input int size);
        int fd = $fopen(f, "w");
        for (int k = 0; k < size; k++) $fwrite(fd, "%02x\n", fb[k]);
        $fclose(fd);
    endtask
    task automatic read_hex(input string f, input int size);
        for (int k = 0; k < NVSIZE; k++) fb[k] = 0;
        $readmemh(f, fb, 0, size - 1);
    endtask
    function automatic bit fb_ee_at(input int base, input logic [7:0] exp [2048]);
        for (int k = 0; k < 2048; k++) if (fb[base + k] !== exp[k]) return 0;
        return 1;
    endfunction
    function automatic bit fb_zero(input int a, input int b);
        for (int k = a; k < b; k++) if (fb[k] !== 8'h00) return 0;
        return 1;
    endfunction
    function automatic int dir_hunk(input int e);   // -1 if entry e is empty
        int o = 2048 + 8 * e;
        if (fb[o] == 8'h47 && fb[o+1] == 8'h4E && fb[o+2] == 8'h43 && fb[o+3] == 8'h4A &&
            {fb[o+5], fb[o+4]} == ~{fb[o+7], fb[o+6]}) return {fb[o+5], fb[o+4]};
        return -1;
    endfunction
    // slot e equals the card image (img, with the write log applied) at hunk h
    function automatic bit slot_is_card(input int e, input int h);
        for (int k = 0; k < 4096; k++) if (fb[4096 + 4096 * e + k] !== img[h * 4096 + k]) return 0;
        return 1;
    endfunction
    function automatic bit ee_is(input logic [7:0] exp [2048]);
        for (int k = 0; k < 2048; k++) if (ee[k] !== exp[k]) return 0;
        return 1;
    endfunction

    // timing of the index 6 download against the core's reset release
    realtime t_ee_fall = 0;
    always @(negedge ee_download) t_ee_fall = $realtime;

    // ------------------------------------------------------------ test
    logic [7:0] ee_rc [2048], ee_ff [2048], ee_x [2048];
    initial begin
        bit saved; logic [15:0] r; int fd, n;
        if (!$value$plusargs("work=%s", work)) work = "work";
        if (!$value$plusargs("out=%s", out)) out = work;
        for (int k = 0; k < 2048; k++) begin ee[k] <= 8'hFF; ee_ff[k] = 8'hFF; end
        fd = $fopen({work, "/ee_gobyrc.bin"}, "rb"); n = $fread(ee_rc, fd); $fclose(fd);
        for (int i = 0; i < 8388608; i++) ddr[i] = 0;
        repeat (20) @(posedge clk_1x);

        // ================================================= P1 Go By RC, MRA size 2048 (both builds)
        $display("-- P1 Go By RC EEPROM, 2 KB MRA");
        for (int k = 0; k < NVSIZE; k++) fb[k] = 0;
        for (int k = 0; k < 2048; k++) fb[k] = ee_rc[k];
        nvm_load(2048);
        check("P1 EEPROM loaded from the 2 KB file", ee_is(ee_rc));
        // calibration rewrites EEPROM 478h-487h
        for (int a = 'h478; a <= 'h487; a++) begin cpu_ee_write(a, 8'(a * 5)); ee_rc[a] = 8'(a * 5); end
        #5us;
        osd_open(2048, saved);
        check("P1 OSD open after an EEPROM write: Main saves (request 0601h)", saved);
        check("P1 saved 2 KB file equals the EEPROM", fb_ee_at(0, ee_rc));
        save_hex({out, "/out_p1.hex"}, 2048);
        osd_open(2048, saved);
        check("P1 OSD open with nothing changed: no request", !saved);

`ifndef CJ
        // ================================================= P3 old RBF with a journal MRA
        $display("-- P3 RBF without the journal, journal-size MRA");
        for (int k = 0; k < 2048; k++) ee_x[k] = 8'(k * 3 + 1);
        for (int k = 0; k < NVSIZE; k++) fb[k] = 0;
        for (int k = 0; k < 2048; k++) begin fb[k] = ee_x[k]; fb[266240 + k] = ee_x[k]; end
        // two directory entries and slot data, as the journal writes them
        for (int e = 0; e < 2; e++) begin
            automatic int h = 100 + 7 * e;
            fb[2048 + 8*e] = 8'h47; fb[2049 + 8*e] = 8'h4E; fb[2050 + 8*e] = 8'h43; fb[2051 + 8*e] = 8'h4A;
            fb[2052 + 8*e] = 8'(h); fb[2053 + 8*e] = 8'(h >> 8); fb[2054 + 8*e] = ~8'(h); fb[2055 + 8*e] = ~8'(h >> 8);
            for (int k = 0; k < 4096; k++) fb[4096 + 4096*e + k] = 8'(k + e);
        end
        save_hex({out, "/syn_journal.hex"}, NVSIZE);
        n = mem_writes;
        nvm_load(NVSIZE);
        check("P3 old RBF: EEPROM ends as the file's EEPROM (mirror written last)", ee_is(ee_x));
        check("P3 old RBF: no card memory write", mem_writes == n);
        cpu_ee_write(5, 8'h55); ee_x[5] = 8'h55;
        #5us;
        osd_open(NVSIZE, saved);
        check("P3 old RBF: saves on request", saved);
        begin
            automatic bit rep = 1;
            for (int c = 0; c < NVSIZE / 2048; c++) if (!fb_ee_at(2048 * c, ee_x)) rep = 0;
            check("P3 old RBF: the saved file is the EEPROM repeated", rep);
        end
        save_hex({out, "/out_old.hex"}, NVSIZE);
`else
        // ================================================= P2 Go By RC, journal MRA
        $display("-- P2 Go By RC, 268,288-byte MRA");
        for (int k = 0; k < NVSIZE; k++) fb[k] = 0;
        for (int k = 0; k < 2048; k++) fb[k] = ee_rc[k];
        nvm_load(NVSIZE);                       // the 2 KB .nvm, zero padded by Main
        check("P2 old 2 KB file: EEPROM loaded", ee_is(ee_rc));
        check("P2 old 2 KB file: journal empty", card_journal.count == 0);
        nvm_save(NVSIZE);                       // OSD "Save settings"
        check("P2 saved file: EEPROM at 0", fb_ee_at(0, ee_rc));
        check("P2 saved file: EEPROM mirror at 266240", fb_ee_at(266240, ee_rc));
        check("P2 saved file: directory, padding and slots all zero", fb_zero(2048, 266240));

        // ================================================= P3 file saved by an RBF without the journal
        begin
            string fold;
            if ($value$plusargs("fold=%s", fold)) begin
                $display("-- P3 journal RBF loads a file saved by an RBF without it");
                read_hex(fold, NVSIZE);
                for (int k = 0; k < 2048; k++) ee_x[k] = fb[k];
                card_load({work, "/card_orig.bin"});
                n = mem_writes;
                nvm_load(NVSIZE);
                check("P3 old file: EEPROM loaded", ee_is(ee_x));
                check("P3 old file: directory rejected, journal empty", card_journal.count == 0);
                check("P3 old file: no card memory write", mem_writes == n);
                begin
                    string fsyn;
                    if (!$value$plusargs("fsyn=%s", fsyn)) fsyn = {work, "/syn_journal.hex"};
                    read_hex(fsyn, NVSIZE);
                end
                nvm_load(NVSIZE);
                check("P3 synthetic journal: 2 entries", card_journal.count == 2);
                begin
                    automatic bit ok = 1;
                    for (int e = 0; e < 2; e++) for (int k = 0; k < 4096; k += 8)
                        if (ddr[(100 + 7*e) * 512 + k/8] != {8'(k+7+e), 8'(k+6+e), 8'(k+5+e), 8'(k+4+e), 8'(k+3+e), 8'(k+2+e), 8'(k+1+e), 8'(k+e)}) ok = 0;
                    check("P3 synthetic journal: slots replayed at hunks 100 and 107", ok);
                end
            end
        end

        // ================================================= P4 Psyvariar session: the game's writes are saved
        $display("-- P4 Psyvariar: play, settings save, OSD");
        for (int k = 0; k < 2048; k++) ee[k] <= 8'hFF;   // power-up erase, no .nvm yet
        card_load({work, "/card_orig.bin"});
        ata_init();
        game_writes_file({work, "/writes1.bin"});
        #5us;
        osd_open(NVSIZE, saved);
        check("P4 OSD open after card writes: Main saves", saved);
        save_hex({out, "/out_f1.hex"}, NVSIZE);
        load_img({work, "/card_gc2.bin"});
        begin
            automatic int exp_h [5] = '{6069, 8, 6079, 6083, 6078};
            automatic bit ok = 1;
            for (int e = 0; e < 5; e++) if (dir_hunk(e) != exp_h[e]) ok = 0;
            for (int e = 5; e < 64; e++) if (dir_hunk(e) != -1) ok = 0;
            check("P4 directory: hunks 6069, 8, 6079, 6083, 6078 in write order, rest empty", ok);
            ok = 1;
            for (int e = 0; e < 5; e++) if (!slot_is_card(e, exp_h[e])) ok = 0;
            check("P4 slots equal MAME's card after the session (card_gc2)", ok);
            check("P4 unused slots zero", fb_zero(4096 + 5 * 4096, 266240));
            check("P4 EEPROM and mirror (all FFh)", fb_ee_at(0, ee_ff) && fb_ee_at(266240, ee_ff));
        end

        // ================================================= P5 reload: journal replayed before reset release
        $display("-- P5 reload Psyvariar with the saved file");
        card_load({work, "/card_orig.bin"});
        check("P5 fresh card image is the zip's (differs from card_gc2)", ddr[48629 * 64 + 6][7:0] == 8'h00);
        read_hex({out, "/out_f1.hex"}, NVSIZE);
        n = mem_writes;
        nvm_load(NVSIZE);
        check("P5 journal: 5 entries", card_journal.count == 5);
        check("P5 card writes from the journal: 5 hunks x 512 lines", mem_writes - n == 5 * 512);
        check("P5 last card write before the core's reset is released (index 6 download end)", t_last_mwrite < t_ee_fall);
        check("P5 loader idle at the end of the download", !zn_card_dl_busy && !zn_card_wait);
        wlog_n = 0;
        load_img({work, "/card_gc2.bin"});
        check("P5 whole card equals MAME's card after the session (40,960,000 bytes)", ddr_is_img_plus_log());
        check("P5 INVERT byte (sector 48629, byte 48) is 01h", ddr[(48629 * 512 + 48) / 8][7:0] == 8'h01);
        osd_open(NVSIZE, saved);
        check("P6 OSD open after a reload with no change: no request", !saved);

        // ================================================= P7 INVERT OFF, save, reload
        $display("-- P7 INVERT OFF");
        load_img({work, "/card_orig.bin"});
        wlog_n = 0;
        game_writes_file({work, "/writes_off.bin"});
        osd_open(NVSIZE, saved);
        check("P7 saves", saved);
        save_hex({out, "/out_f2.hex"}, NVSIZE);
        check("P7 directory still 5 entries (rewritten hunks not added twice)", dir_hunk(4) == 6078 && dir_hunk(5) == -1);
        card_load({work, "/card_orig.bin"});
        nvm_load(NVSIZE);
        load_img({work, "/card_off.bin"});
        check("P7 reload: whole card equals the INVERT OFF card", ddr_is_img_plus_log());

        // ================================================= P8 a write during the upload asks again
        $display("-- P8 card write during an upload");
        load_img({work, "/card_off.bin"});
        wlog_n = 0;
        game_write_pattern(70000, 1);
        OSD_STATUS = 1; #2us;
        chk_upload(r);
        check("P8 request after a write", r == 16'h0601);
        fork
            nvm_save(NVSIZE);
            begin
                wait (ioctl_upload && ioctl_addr > 27'd60000);
                game_write_pattern(71000, 2);
                check("P8 the second write finished during the upload", ioctl_upload == 1);
            end
        join
        OSD_STATUS = 0; #2us;
        check("P8 card_dirty set again by the write during the upload", card_journal.card_dirty == 1);
        check("P8 first file: 6 entries (snapshot at the upload start)", dir_hunk(5) == 70000 / 8 && dir_hunk(6) == -1);
        osd_open(NVSIZE, saved);
        check("P8 next OSD open saves again", saved);
        check("P8 second file: 7 entries", dir_hunk(6) == 71000 / 8 && dir_hunk(7) == -1);
        save_hex({out, "/out_f4.hex"}, NVSIZE);
        card_load({work, "/card_orig.bin"});
        nvm_load(NVSIZE);
        load_img({work, "/card_off.bin"});
        wlog_n = 0;
        begin   // expected: card_off plus the two pattern sectors
            for (int b = 0; b < 512; b++) begin
                img[70000 * 512 + b] = 8'((b * 7 + 1 * 13 + 1) & 255);
                img[71000 * 512 + b] = 8'((b * 7 + 2 * 13 + 1) & 255);
            end
            check("P8 reload: whole card equals the expected card", ddr_is_img_plus_log());
        end

        // ================================================= P9 64 hunks, then 65
        $display("-- P9 64 hunks, then overflow");
        // img = expected so far (card_off + 2 sectors); log continues from here
        wlog_n = 0;
        for (int j = 0; j < 57; j++) game_write_pattern(1000 + 8 * 17 * j, 10 + j);   // 57 new hunks, 64 in all
        osd_open(NVSIZE, saved);
        check("P9 64 hunks: 64 directory entries", dir_hunk(63) != -1);
        save_hex({out, "/out_f5.hex"}, NVSIZE);
        card_load({work, "/card_orig.bin"});
        nvm_load(NVSIZE);
        check("P9 reload: journal 64 entries", card_journal.count == 64 && !card_journal.overflow);
        load_img({work, "/card_off.bin"});
        for (int b = 0; b < 512; b++) begin
            img[70000 * 512 + b] = 8'((b * 7 + 1 * 13 + 1) & 255);
            img[71000 * 512 + b] = 8'((b * 7 + 2 * 13 + 1) & 255);
        end
        for (int j = 0; j < 57; j++) for (int b = 0; b < 512; b++) img[(1000 + 8 * 17 * j) * 512 + b] = 8'((b * 7 + (10 + j) * 13 + 1) & 255);
        wlog_n = 0;
        check("P9 reload: whole card equals the expected card (64 hunks)", ddr_is_img_plus_log());
        game_write_pattern(79000, 99);                    // hunk 65
        check("P9 65th hunk: overflow", card_journal.overflow == 1);
        osd_open(NVSIZE, saved);
        check("P9 overflow: Main still saves", saved);
        check("P9 overflow: directory empty, slots zero", fb_zero(2048, 266240));
        check("P9 overflow: EEPROM and mirror kept", fb_ee_at(0, ee_ff) && fb_ee_at(266240, ee_ff));
        card_load({work, "/card_orig.bin"});
        nvm_load(NVSIZE);
        load_img({work, "/card_orig.bin"});
        check("P9 overflow file reload: the zip's card, unchanged", ddr_is_img_plus_log() && card_journal.count == 0);

        // ================================================= P11 a new card without a .nvm empties the list
        $display("-- P11 new card image without a .nvm");
        game_write_pattern(500, 3);
        card_load({work, "/card_orig.bin"});              // no index 6 follows
        nvm_save(NVSIZE);                                 // "Save settings"
        check("P11 directory empty after a card load without a file", fb_zero(2048, 266240));

        // ================================================= P10 crossing stress
        $display("-- P10 crossing: 2,000 events, 40 hunks, random gaps and skew");
        card_load({work, "/card_orig.bin"});
        begin
            int seen [$]; bit ok;
            for (int k = 0; k < 2000; k++) begin
                automatic int h = (k < 40) ? (k * 97 + 11) % 16384 : (($urandom_range(0, 39)) * 97 + 11) % 16384;
                bit dup = 0;
                foreach (seen[s]) if (seen[s] == h) dup = 1;
                if (!dup) seen.push_back(h);
                #($urandom_range(2000, 20000) * 1ns);
                @(posedge clk_cpu); inj_set <= 1; inj_hunk <= 14'(h);
                @(posedge clk_cpu); inj_set <= 0;
            end
            #10us;
            ok = (card_journal.count == seen.size()) && !card_journal.overflow;
            foreach (seen[s]) if (card_journal.list[s] != 14'(seen[s])) ok = 0;
            check($sformatf("P10 list = the %0d distinct hunks in first-seen order", seen.size()), ok);
            check("P10 card_dirty set", card_journal.card_dirty == 1);
        end
`endif

        $display("RESULT %s: %0d checks, %0d failed", errors ? "FAIL" : "PASS", checks, errors);
        $finish;
    end
endmodule
