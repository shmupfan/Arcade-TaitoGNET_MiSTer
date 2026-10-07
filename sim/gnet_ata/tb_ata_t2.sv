// Unit test of gnet_ata's Taito Type 2 card (MAME 0.288 taito_pccard2_device),
// the Taito CompactFlash card (taito_compact_flash_device) and a Type 1 regression: lock at power-on, FEh/FCh unlock with a right and
// a wrong key block, the Type 1 attribute unlock ignored on Type 2, and the
// card size from IDENTIFY words 60-61.
//   run: verilator --binary --timing -Wno-fatal sim/gnet_ata/tb_ata_t2.sv rtl/gnet/gnet_ata.sv --top-module tb_ata_t2
`timescale 1ns/1ps
module tb_ata_t2;
    logic clk = 0, rst = 1, card_reset = 0;
    always #5 clk = ~clk;

    logic attr_req = 0, attr_we = 0, attr_ack; logic [19:0] attr_waddr = 0; logic [15:0] attr_wdata = 0, attr_rdata;
    logic tf_req = 0, tf_we = 0, tf_ack; logic [15:0] tf_off = 0, tf_wdata = 0, tf_rdata; logic [1:0] tf_bmask = 0;
    logic meta_we = 0; logic [9:0] meta_addr = 0; logic [7:0] meta_wdata = 0; logic key_valid = 1;
    logic st_req, st_we, st_ack = 0; logic [24:0] st_addr; logic [15:0] st_wdata, st_rdata = 0;
    logic dirty_set, dirty_rdata, dbg_sec_cmd; logic [13:0] dirty_hunk;

    gnet_ata #(.CLK_HZ(100_000_000), .T_DETECT_NS(2000), .T_DIAG_NS(2000), .T_CMD_NS(100), .T_WRITE_NS(1000)) dut (
        .clk, .rst, .card_reset, .attr_req, .attr_we, .attr_waddr, .attr_wdata, .attr_ack, .attr_rdata,
        .tf_req, .tf_we, .tf_off, .tf_bmask, .tf_wdata, .tf_ack, .tf_rdata,
        .meta_we, .meta_addr, .meta_wdata, .key_valid,
        .st_req, .st_we, .st_addr, .st_wdata, .st_ack, .st_rdata,
        .dirty_set, .dirty_hunk, .dirty_raddr(14'd0), .dirty_rdata, .dirty_clear(1'b0), .dbg_sec_cmd);

    // storage: word = low 16 bits of the word address, one cycle later
    always @(posedge clk) begin
        st_ack <= st_req && !st_ack;
        st_rdata <= st_addr[15:0];
    end

    int errors = 0;
    task automatic check(input string what, input logic ok);
        if (!ok) begin errors++; $display("FAIL %s", what); end
        else $display("ok   %s", what);
    endtask

    // an arbitrary test key (not a game's card key)
    logic [7:0] KEY [5] = '{8'h12, 8'h34, 8'h56, 8'h78, 8'h9a};

    task automatic meta(input int a, input logic [7:0] d);
        @(posedge clk); meta_we <= 1; meta_addr <= 10'(a); meta_wdata <= d;
        @(posedge clk); meta_we <= 0;
    endtask
    task automatic load_meta(input logic [7:0] ctype, input int lba);
        for (int i = 0; i < 1024; i++) meta(i, 8'h00);
        meta(8'h78, 8'(lba)); meta(8'h79, 8'(lba >> 8)); meta(8'h7a, 8'(lba >> 16)); meta(8'h7b, 8'(lba >> 24));
        for (int i = 0; i < 5; i++) meta(10'h300 + i, KEY[i]);
        meta(10'h3f0, ctype);
    endtask
    task automatic tf(input logic we, input int off, input logic [1:0] bm, input logic [15:0] d, output logic [15:0] q);
        @(posedge clk); tf_req <= 1; tf_we <= we; tf_off <= 16'(off); tf_bmask <= bm; tf_wdata <= d;
        @(posedge clk); tf_req <= 0;
        while (!tf_ack) @(posedge clk);
        q = tf_rdata;
    endtask
    // byte register r (0-7): even on the low lane, odd on the high lane
    task automatic wr(input int r, input logic [7:0] v);
        logic [15:0] q;
        if (r[0]) tf(1, r - 1, 2'b10, {v, 8'h00}, q); else tf(1, r, 2'b01, {8'h00, v}, q);
    endtask
    task automatic rd(input int r, output logic [7:0] v);
        logic [15:0] q;
        if (r[0]) begin tf(0, r - 1, 2'b10, 0, q); v = q[15:8]; end
        else      begin tf(0, r,     2'b01, 0, q); v = q[7:0];  end
    endtask
    task automatic ar(input int a, output logic [15:0] q);
        @(posedge clk); attr_req <= 1; attr_we <= 0; attr_waddr <= 20'(a);
        @(posedge clk); attr_req <= 0;
        while (!attr_ack) @(posedge clk);
        q = attr_rdata;
    endtask
    task automatic aw(input int a, input logic [15:0] d);
        @(posedge clk); attr_req <= 1; attr_we <= 1; attr_waddr <= 20'(a); attr_wdata <= d;
        @(posedge clk); attr_req <= 0;
        while (!attr_ack) @(posedge clk);
    endtask
    task automatic wait_ready();
        logic [7:0] s;
        do rd(7, s); while (s[7]);
    endtask
    task automatic key_block(input logic bad);
        logic [15:0] q;
        for (int w = 0; w < 256; w++) begin
            logic [7:0] b0, b1;
            b0 = (2*w >= 2 && 2*w < 7) ? KEY[2*w - 2] : 8'h00;
            b1 = (2*w + 1 >= 2 && 2*w + 1 < 7) ? KEY[2*w - 1] : 8'h00;
            if (bad && w == 200) b0 = 8'h01;
            tf(1, 0, 2'b11, {b1, b0}, q);
        end
    endtask
    task automatic read_sector(input int lba, output logic [7:0] s, output logic [7:0] e);
        wr(6, 8'hE0 | 8'((lba >> 24) & 15)); wr(5, 8'(lba >> 16)); wr(4, 8'(lba >> 8)); wr(3, 8'(lba)); wr(2, 8'd1);
        wr(7, 8'h20);
        repeat (40) @(posedge clk);
        rd(7, s); rd(1, e);
    endtask

    initial begin
        logic [7:0] s, e, sc; logic [15:0] q;
        // ------------------------------------------------ Type 2
        load_meta(8'h02, 75392);
        repeat (4) @(posedge clk); rst <= 0;
        wait_ready();
        rd(7, s); check("T2 locked at power-on: DRDY clear", !s[6]);
        ar(16'h201, q); check("T2 attribute 201h reads FFFFh", q == 16'hffff);
        for (int i = 0; i < 5; i++) aw(16'h280 + i, {8'h00, KEY[i]});
        for (int i = 5; i < 9; i++) aw(16'h280 + i, 16'h0000);
        rd(7, s); check("T2 ignores the Type 1 attribute unlock", !s[6]);
        read_sector(0, s, e); check("T2 locked: READ SECTORS ends with ERR, DRDY clear", s[0] && !s[6] && e == 8'h00);
        wr(7, 8'hFE); rd(7, s); rd(2, sc);
        check("T2 FEh: DRDY, no ERR, sector count 1", s[6] && !s[0] && sc == 8'd1);
        wr(7, 8'hFC); rd(7, s); check("T2 FCh: DRQ", s[3] && !s[0]);
        key_block(1); rd(7, s); check("T2 wrong key block: ERR, DRQ clear", s[0] && !s[3]);
        read_sector(0, s, e); check("T2 still locked after a wrong key", s[0] && !s[6]);
        wr(7, 8'hFE); wr(7, 8'hFC); key_block(0); rd(7, s);
        check("T2 right key block: DRQ clear, no ERR, DRDY", !s[3] && !s[0] && s[6]);
        read_sector(1000, s, e); check("T2 unlocked: READ SECTORS gives DRQ", s[3] && !s[0]);
        for (int i = 0; i < 256; i++) begin tf(0, 0, 2'b11, 0, q); if (i == 3) check("T2 sector data from the card port", q == 16'(1000 * 256 + 3)); end
        read_sector(75391, s, e); check("T2 last sector (75391) reads", s[3] && !s[0]);
        for (int i = 0; i < 256; i++) tf(0, 0, 2'b11, 0, q);
        read_sector(75392, s, e); check("T2 sector 75392 (past IDENTIFY 60-61) ends with ERR 80h", s[0] && e == 8'h80);
        // ------------------------------------------------ Type 1 (type byte 0, size from IDENTIFY)
        rst <= 1; load_meta(8'h00, 80000); repeat (4) @(posedge clk); rst <= 0;
        wait_ready();
        ar(16'h201, q); check("T1 attribute 201h = 1 while locked", q == 16'h0001);
        wr(7, 8'hFE); rd(7, s); check("T1 FEh while locked: ERR", s[0]);
        for (int i = 0; i < 5; i++) aw(16'h280 + i, {8'h00, KEY[i]});
        for (int i = 5; i < 9; i++) aw(16'h280 + i, 16'h0000);
        ar(16'h201, q); check("T1 attribute unlock clears 201h", q == 16'h0000);
        read_sector(79999, s, e); check("T1 sector 79999 reads", s[3] && !s[0]);
        for (int i = 0; i < 256; i++) tf(0, 0, 2'b11, 0, q);
        read_sector(80000, s, e); check("T1 sector 80000 ends with ERR 80h", s[0] && e == 8'h80);
        wr(7, 8'hFE); rd(7, s); rd(1, e); check("T1 FEh unlocked: ERR ABRT (04h)", s[0] && e == 8'h04);
        // ------------------------------------------------ CompactFlash (type 03h, 64 MB)
        rst <= 1; load_meta(8'h03, 125440); repeat (4) @(posedge clk); rst <= 0;
        wait_ready();
        rd(7, s); check("CF locked at power-on: DRDY clear", !s[6]);
        ar(16'h201, q); check("CF attribute 201h reads FFFFh", q == 16'hffff);
        read_sector(0, s, e); check("CF locked: READ SECTORS gives status 11h (DSC, ERR), error 00h", s == 8'h11 && e == 8'h00);
        wr(1, KEY[0]); wr(2, KEY[1]); wr(3, KEY[2]); wr(4, KEY[3]); wr(5, 8'h00); wr(7, 8'h0F);
        rd(7, s); check("CF 0Fh wrong key: DRDY clear, no ERR", !s[6] && !s[0]);
        read_sector(0, s, e); check("CF still locked after a wrong key", s[0] && !s[6]);
        wr(1, KEY[0]); wr(2, KEY[1]); wr(3, KEY[2]); wr(4, KEY[3]); wr(5, KEY[4]); wr(6, 8'h03); wr(7, 8'h0F);
        rd(7, s); check("CF 0Fh right key (drive/head 03h, as the otenamhf BIOS): status 50h", s == 8'h50);
        read_sector(125439, s, e); check("CF last sector (125439) reads", s[3] && !s[0]);
        for (int i = 0; i < 256; i++) tf(0, 0, 2'b11, 0, q);
        read_sector(125440, s, e); check("CF sector 125440 ends with ERR 80h", s[0] && e == 8'h80);
        // ------------------------------------------------ 0Fh on a Type 1 card is an unknown command
        rst <= 1; load_meta(8'h00, 80000); repeat (4) @(posedge clk); rst <= 0;
        wait_ready();
        wr(1, KEY[0]); wr(2, KEY[1]); wr(3, KEY[2]); wr(4, KEY[3]); wr(5, KEY[4]); wr(7, 8'h0F);
        ar(16'h201, q); check("T1 0Fh with the key in the task file does not unlock", q == 16'h0001);
        $display("%0d failure(s)", errors);
        $finish;
    end
endmodule
