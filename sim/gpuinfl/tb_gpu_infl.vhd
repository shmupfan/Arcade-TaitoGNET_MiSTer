-- DDR3 bandwidth study (docs/ddr3_bandwidth.md): sim/m1/tb_gpu_replay.vhd plus
-- a monitor on the GPU's VRAM port (BWMON). Same inputs.
-- M1: replay a MAME 0.288 GPU command stream through the PSX_MiSTer GPU.
-- Copyright (C) 2026 Lee Foot. GPL-2.0-or-later (docs/licensing.md).
-- Structure after PSX_MiSTer's sim/gpu/src/tb/tb.vhd (Robert Peip); written
-- for the current gpu entity (28-bit VRAM address) and NVC.
--
-- Input (generic STREAM): text, one GPU word per line, "KK FFFFFFFF WWWWWWWW"
-- in hex: KK = 00 CPU GP0, 01 CPU GP1, 02/03 DMA2 block/list word; FFFFFFFF =
-- MAME frame number; WWWWWWWW = data (tools/gpu_stream.py --text).
-- A record is sent once the GPU has produced that many vblanks, so MAME
-- frames line up with GPU frames. CPU writes go through the bus port and
-- wait out bus_stall; DMA words go through the DMA port only while the GPU
-- requests data, as the PSX DMA controller does.
-- Output: vram_<frame>.bin (raw 1 MB VRAM, 16-bit little-endian pixels) for
-- every frame listed in generic DUMPS (comma-separated decimal), and
-- frames.txt with one line per vblank: frame count, simulation time.
-- GTIME = true (R23 GPU drawing time, docs/gpu_draw_time.md) adds
-- frames_time.txt, one line per stream frame:
--   frame words start_ns end_ns span busy overrun vblank
-- start = first word of the frame presented to the GPU; end = first clk2x
-- edge after the frame's last word at which the GPU is idle (command FIFO
-- empty and no word in flight, no command in progress, pixel pipeline and
-- pixel write FIFO empty: the drawing part of gpu.vhd's SS_Idle condition
-- plus fifoIn_Wr/fifoIn_Valid, read through external names; nothing in rtl/
-- changed); span = end - start and busy = non-idle
-- edges in [start, end), both in clk2x cycles (67.7376 MHz); overrun = 1
-- when the next frame's first word came before the GPU went idle (end is
-- then that word's time); vblank = GPU vblanks seen at start. Also
-- vblank_busy.txt: per GPU vblank interval, vblank count, non-idle clk2x
-- edges, all clk2x edges. VIDCAP = false skips the video capture process.
-- VRAM_RD_LAT adds clk2x cycles of read latency to the VRAM model (default 0:
-- data one cycle after the request, as before).

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use STD.textio.all;
use IEEE.std_logic_textio.all;

library psx;

entity tb_gpu_infl is
   generic
   (
      STREAM   : string  := "stream.txt";
      DUMPS    : string  := "60";
      MAXFRAME : integer := 600;
      VRAM_Y_BITS : integer := 9;    -- 9 = PS1 1 MB, 10 = ZN-2 2 MB
      VRAM_INIT   : string  := "";    -- optional raw VRAM image loaded at start (seek)
      DITHER_OFF  : std_logic := '0';  -- '1' forces dithering off (MAME 0.288 does not dither)
      GTIME       : boolean := false;  -- write frames_time.txt and vblank_busy.txt (R23)
      VRAM_RD_LAT : integer := 0;      -- extra clk2x cycles before read data (R23 sensitivity)
      VIDCAP      : boolean := true;   -- video output capture for the frames in DUMPS
      LAT_TEX     : integer := -1;     -- read latency for texture misses (-1: VRAM_RD_LAT)
      LAT_CLUT    : integer := -1;     -- CLUT loads
      LAT_VID     : integer := -1;     -- video out line reads
      LAT_DST     : integer := -1;     -- poly/rect/line destination reads
      LAT_CPY     : integer := -1;     -- VRAM to VRAM and VRAM to CPU
      READ_INFL   : integer := 1;      -- gpu GPU_READ_INFL
      TEX_QW      : integer := 1;      -- gpu TEX_FETCH_QW
      TEX_ROWS    : integer := 1;      -- gpu TEX_FETCH_ROWS
      TEX_DELAY   : integer := 0;      -- gpu TEX_MISS_DELAY
      TEX_BIG     : integer := 0;      -- gpu TEX_CACHE_BIG
      SPX4        : integer := 0;      -- gpu TEX_SPX_COST4
      SPX8        : integer := 0;      -- gpu TEX_SPX_COST8
      SPX15       : integer := 0;      -- gpu TEX_SPX_COST15
      CLIPX       : integer := 0;      -- gpu POLY_CLIP_X
      -- GPU clock scale (docs/gpu_blend_timing.md 10): clk1x and clk2x run
      -- GSCALE times faster, the video clock (and so vblank) does not; give
      -- VRAM_RD_LAT in the faster cycles to keep the latency in ns
      GSCALE      : real := 1.0;
      PACED       : boolean := false;  -- release a stream frame at the first vblank after the GPU went idle (DrawSync, VSync)
      TEX_DIR     : integer := 0;      -- gpu TEX_FETCH_DIR
      ARB         : boolean := false;  -- GPU through a model of gnet_ddr3_arb's core path
      ROT         : boolean := false   -- with screen_rotate's writes at top priority (ARB only)
   );
end entity;

architecture arch of tb_gpu_infl is

   constant T1X  : time := 29524 ps / GSCALE;    -- 33.8688 MHz x GSCALE
   constant T2X  : time := 14762 ps / GSCALE;    -- 67.7376 MHz x GSCALE
   constant TVID : time := 18624 ps;    -- 53.693175 MHz

   signal clk1x, clk2x, clkvid : std_logic := '1';
   signal clk2xIndex           : std_logic := '0';
   signal clk1xToggle, clk1xToggle2x : std_logic := '0';
   signal reset                : std_logic := '1';

   signal bus_addr      : unsigned(3 downto 0) := (others => '0');
   signal bus_dataWrite : std_logic_vector(31 downto 0) := (others => '0');
   signal bus_write     : std_logic := '0';
   signal bus_dataRead  : std_logic_vector(31 downto 0);
   signal bus_stall     : std_logic;

   signal dmaOn            : std_logic := '0';
   signal gpu_dmaRequest   : std_logic;
   signal DMA_GPU_writeEna : std_logic := '0';
   signal DMA_GPU_write    : std_logic_vector(31 downto 0) := (others => '0');

   signal irq_VBLANK : std_logic;
   signal vblank_count : integer := 0;

   signal vram_BUSY        : std_logic := '0';
   signal vram_DOUT        : std_logic_vector(63 downto 0) := (others => '0');
   signal vram_DOUT_READY  : std_logic := '0';
   signal vram_BURSTCNT    : std_logic_vector(7 downto 0);
   signal vram_ADDR        : std_logic_vector(27 downto 0);
   signal vram_DIN         : std_logic_vector(63 downto 0);
   signal vram_BE          : std_logic_vector(7 downto 0);
   signal vram_WE, vram_RD : std_logic;
   -- requester class of the GPU's current read (0 texture, 1 CLUT, 2 video,
   -- 3 destination, 4 copy/readback), taken from the GPU's request lines
   signal g_cls, m_cls     : integer range 0 to 4 := 0;
   -- GPU side of the port (the GPU's own vram_* signals); vram_* above are
   -- the memory side, the same signals without ARB
   signal g_BUSY           : std_logic := '0';
   signal g_BURSTCNT       : std_logic_vector(7 downto 0);
   signal g_ADDR           : std_logic_vector(27 downto 0);
   signal g_DIN            : std_logic_vector(63 downto 0);
   signal g_BE             : std_logic_vector(7 downto 0);
   signal g_WE, g_RD       : std_logic;

   signal dump_req  : std_logic := '0';
   signal dump_ack  : std_logic := '0';
   signal dump_name : string(1 to 32) := (others => ' ');
   signal dump_len  : integer := 0;
   signal done      : boolean := false;

   signal video_ce_s, video_hblank_s, video_vblank_s : std_logic;

   -- feeder progress for GTIME: frame of the word being presented, word count
   signal feed_frame : integer := -1;
   signal err_line, err_rect, err_poly : std_logic;
   signal feed_count : integer := 0;
   signal feed_done  : boolean := false;
   signal gpu_idle   : boolean := false;   -- drawing part of SS_Idle (as GTIME), for PACED and BRK
   signal rel_vb     : integer := 0;       -- vblank at which the current stream frame was released
   signal video_r_s, video_g_s, video_b_s : std_logic_vector(7 downto 0);

   function frame_listed(s : string; f : integer) return boolean is
      variable v : integer := 0;
      variable have : boolean := false;
   begin
      for i in s'range loop
         if s(i) >= '0' and s(i) <= '9' then
            v := v * 10 + character'pos(s(i)) - 48; have := true;
         else
            if have and v = f then return true; end if;
            v := 0; have := false;
         end if;
      end loop;
      return have and v = f;
   end function;

begin

   clk1x  <= not clk1x  after T1X / 2 when not done;
   clk2x  <= not clk2x  after T2X / 2 when not done;
   clkvid <= not clkvid after TVID / 2 when not done;

   -- clk2xIndex as in psx_top: '1' on the second clk2x cycle of each clk1x period
   process (clk1x) begin
      if rising_edge(clk1x) then clk1xToggle <= not clk1xToggle; end if;
   end process;
   process (clk2x) begin
      if rising_edge(clk2x) then
         clk1xToggle2x <= clk1xToggle;
         clk2xIndex    <= '0';
         if (clk1xToggle2x = clk1xToggle) then clk2xIndex <= '1'; end if;
      end if;
   end process;

   igpu : entity psx.gpu
   generic map (VRAM_Y_BITS => VRAM_Y_BITS, GPU_READ_INFL => READ_INFL, TEX_FETCH_QW => TEX_QW, TEX_FETCH_ROWS => TEX_ROWS,
                TEX_MISS_DELAY => TEX_DELAY, TEX_CACHE_BIG => TEX_BIG, TEX_SPX_COST4 => SPX4,
                TEX_SPX_COST8 => SPX8, TEX_SPX_COST15 => SPX15, POLY_CLIP_X => CLIPX,
                TEX_FETCH_DIR => TEX_DIR)
   port map
   (
      clk1x => clk1x, clk2x => clk2x, clk2xIndex => clk2xIndex, clkvid => clkvid,
      ce => '1', reset => reset, allowunpause => open,
      savestate_busy => '0', system_paused => '0',
      ditherOff => DITHER_OFF, interlaced480pHack => '0', REPRODUCIBLEGPUTIMING => '0',
      videoout_on => '1', isPal => '0', pal60 => '0', fpscountOn => '0',
      noTexture => '0', textureFilter => "00", textureFilterStrength => "00",
      textureFilter2DOff => '0', dither24 => '0', render24 => '0', drawSlow => '0',
      debugmodeOn => '0', syncVideoOut => '0', syncInterlace => '0', rotate180 => '0',
      fixedVBlank => '0', vCrop => "00", hCrop => '0', oldGPU => '0',
      Gun1CrosshairOn => '0', Gun1X => (others => '0'), Gun1Y_scanlines => (others => '0'),
      Gun1offscreen => '0', Gun1IRQ10 => open,
      Gun2CrosshairOn => '0', Gun2X => (others => '0'), Gun2Y_scanlines => (others => '0'),
      Gun2offscreen => '0', Gun2IRQ10 => open,
      cdSlow => '0', errorOn => '0', errorEna => '0', errorCode => (others => '0'),
      LBAOn => '0', LBAdisplay => (others => '0'),
      errorLINE => err_line, errorRECT => err_rect, errorPOLY => err_poly, errorGPU => open,
      errorMASK => open, errorFIFO => open,
      bus_addr => bus_addr, bus_dataWrite => bus_dataWrite, bus_read => '0',
      bus_write => bus_write, bus_dataRead => bus_dataRead, bus_stall => bus_stall,
      dmaOn => dmaOn, gpu_dmaRequest => gpu_dmaRequest, DMA_GPU_waiting => '0',
      DMA_GPU_writeEna => DMA_GPU_writeEna, DMA_GPU_readEna => '0',
      DMA_GPU_write => DMA_GPU_write, DMA_GPU_read => open,
      irq_VBLANK => irq_VBLANK, irq_GPU => open,
      vram_pause => '0', vram_paused => open,
      vram_BUSY => g_BUSY, vram_DOUT => vram_DOUT, vram_DOUT_READY => vram_DOUT_READY,
      vram_BURSTCNT => g_BURSTCNT, vram_ADDR => g_ADDR, vram_DIN => g_DIN,
      vram_BE => g_BE, vram_WE => g_WE, vram_RD => g_RD,
      hblank_tmr => open, vblank_tmr => open, dotclock => open,
      video_hsync => open, video_vsync => open, video_hblank => video_hblank_s, video_vblank => video_vblank_s,
      video_DisplayWidth => open, video_DisplayHeight => open,
      video_DisplayOffsetX => open, video_DisplayOffsetY => open,
      video_ce => video_ce_s, video_interlace => open,
      video_r => video_r_s, video_g => video_g_s, video_b => video_b_s,
      video_isPal => open, video_fbmode => open, video_fb24 => open,
      video_hResMode => open, video_frameindex => open,
      export_gtm => open, export_line => open, export_gpus => open, export_gobj => open,
      loading_savestate => '0', SS_reset => reset,
      SS_DataWrite => (others => '0'), SS_Adr => (others => '0'),
      SS_wren_GPU => '0', SS_wren_Timing => '0', SS_rden_GPU => '0', SS_rden_Timing => '0',
      SS_DataRead_GPU => open, SS_DataRead_Timing => open, SS_Idle => open
   );

   -- VRAM: 8 MB byte space (VRAM at 0, video-out frame buffers from 0x400000),
   -- 64-bit bursts, read latency VRAM_RD_LAT (or per class) plus one cycle,
   -- several reads in flight answered in order, writes complete in one cycle.
   process
      type mem_t is array (0 to 1048575) of std_logic_vector(63 downto 0);
      variable mem : mem_t := (others => (others => '0'));
      variable a, n : integer;
      file f : text;
      type bin_file is file of character;
      file fb : bin_file;
      variable w : std_logic_vector(63 downto 0);
      variable ch : character;
      variable lat : integer;
      variable loaded : boolean := false;
      type burst_t is array (0 to 127) of std_logic_vector(63 downto 0);
      type rq_d_t is array (0 to 15) of burst_t;
      type rq_i_t is array (0 to 15) of integer;
      variable qd : rq_d_t;
      variable qn, qdue : rq_i_t := (others => 0);
      variable qw, qr, qb, qcnt, cyc : integer := 0;
   begin
      if not loaded then
         loaded := true;
         if VRAM_INIT'length > 0 then
            file_open(fb, VRAM_INIT, read_mode);
            for i in 0 to 2**(VRAM_Y_BITS + 11) / 8 - 1 loop
               for b in 0 to 7 loop
                  read(fb, ch);
                  w(b * 8 + 7 downto b * 8) := std_logic_vector(to_unsigned(character'pos(ch), 8));
               end loop;
               mem(i) := w;
            end loop;
            file_close(fb);
            report "VRAM loaded from " & VRAM_INIT severity note;
         end if;
      end if;
      -- cycle model (GPU_READ_INFL work): a read is answered from a copy of
      -- its words taken when it is accepted, first beat driven lat + 1 edges
      -- later (the old blocking model's timing), beats in order; writes apply
      -- when accepted, also while reads are outstanding
      wait until rising_edge(clk2x);
      cyc := cyc + 1;
      if vram_RD = '1' then
         a := to_integer(unsigned(vram_ADDR(22 downto 3)));
         n := to_integer(unsigned(vram_BURSTCNT));
         lat := VRAM_RD_LAT;
         case m_cls is
            when 0 => if LAT_TEX  >= 0 then lat := LAT_TEX;  end if;
            when 1 => if LAT_CLUT >= 0 then lat := LAT_CLUT; end if;
            when 2 => if LAT_VID  >= 0 then lat := LAT_VID;  end if;
            when 3 => if LAT_DST  >= 0 then lat := LAT_DST;  end if;
            when others => if LAT_CPY >= 0 then lat := LAT_CPY; end if;
         end case;
         for i in 0 to n - 1 loop qd(qw)(i) := mem((a + i) mod 1048576); end loop;
         qn(qw) := n; qdue(qw) := cyc + lat + 1;
         qw := (qw + 1) mod 16; qcnt := qcnt + 1;
         assert qcnt <= 16 report "VRAM model read queue overflow" severity failure;
      end if;
      if vram_WE = '1' and vram_ADDR(27 downto 24) = x"0" then
         a := to_integer(unsigned(vram_ADDR(22 downto 3)));
         w := mem(a);
         for b in 0 to 7 loop
            if vram_BE(b) = '1' then w(b * 8 + 7 downto b * 8) := vram_DIN(b * 8 + 7 downto b * 8); end if;
         end loop;
         mem(a) := w;
      end if;
      vram_DOUT_READY <= '0';
      if qcnt > 0 and qdue(qr) <= cyc then
         vram_DOUT <= qd(qr)(qb);
         vram_DOUT_READY <= '1';
         qb := qb + 1;
         if qb = qn(qr) then qb := 0; qr := (qr + 1) mod 16; qcnt := qcnt - 1; end if;
      end if;
      if dump_req = '1' and dump_ack = '0' then
         file_open(fb, dump_name(1 to dump_len), write_mode);
         for i in 0 to 2**(VRAM_Y_BITS + 11) / 8 - 1 loop   -- 1 MB or 2 MB VRAM in 64-bit words
            w := mem(i);
            for b in 0 to 7 loop
               write(fb, character'val(to_integer(unsigned(w(b * 8 + 7 downto b * 8)))));
            end loop;
         end loop;
         file_close(fb);
         dump_ack <= '1';
      elsif dump_req = '0' then
         dump_ack <= '0';
      end if;
   end process;


   -- video output capture: every visible pixel (video_ce, outside blanking)
   -- of the frames listed in DUMPS is written to video_<frame>.ppm (P6), so
   -- the displayed image can be compared with MAME's snapshot of that frame
   process
      type line_t is array (0 to 1023) of std_logic_vector(23 downto 0);
      type frame_t is array (0 to 511) of line_t;
      variable fbuf  : frame_t;
      variable x, y, maxx : integer := 0;
      variable inline : boolean := false;
      variable prev_vb : std_logic := '1';
      type bin_file is file of character;
      file fo : bin_file;
      variable nm : line;
      variable hdr : line;
      variable fr : integer := 0;
   begin
      if not VIDCAP then wait; end if;
      wait until rising_edge(clkvid);
      if video_vblank_s = '1' and prev_vb = '0' then         -- end of a frame
         fr := fr + 1;
         if frame_listed(DUMPS, fr) and y > 0 and maxx > 0 then
            write(nm, string'("video_")); write(nm, fr); write(nm, string'(".ppm"));
            file_open(fo, nm.all, write_mode);
            write(hdr, string'("P6 ")); write(hdr, maxx); write(hdr, string'(" ")); write(hdr, y);
            write(hdr, string'(" 255"));
            for i in hdr'range loop write(fo, hdr(i)); end loop;
            write(fo, character'val(10));
            for yy in 0 to y - 1 loop
               for xx in 0 to maxx - 1 loop
                  for c in 2 downto 0 loop
                     write(fo, character'val(to_integer(unsigned(fbuf(yy)(xx)(c * 8 + 7 downto c * 8)))));
                  end loop;
               end loop;
            end loop;
            file_close(fo);
            deallocate(nm); deallocate(hdr);
         end if;
         y := 0; maxx := 0; x := 0; inline := false;
      end if;
      prev_vb := video_vblank_s;
      if video_vblank_s = '0' then
         if video_hblank_s = '0' then
            if video_ce_s = '1' and y < 512 and x < 1024 then
               fbuf(y)(x) := video_r_s & video_g_s & video_b_s;
               x := x + 1;
               inline := true;
            end if;
         elsif inline then
            if x > maxx then maxx := x; end if;
            x := 0; y := y + 1; inline := false;
         end if;
      end if;
   end process;

   -- vblank counter, frame log and VRAM dumps
   process
      file flog : text open write_mode is "frames.txt";
      variable l : line;
      variable nm : line;
   begin
      wait until rising_edge(irq_VBLANK);
      vblank_count <= vblank_count + 1;
      write(l, vblank_count + 1); write(l, string'(" ")); write(l, now); writeline(flog, l);
      if frame_listed(DUMPS, vblank_count + 1) then
         write(nm, string'("vram_")); write(nm, vblank_count + 1); write(nm, string'(".bin"));
         dump_len  <= nm'length;
         dump_name <= (others => ' ');
         dump_name(1 to nm'length) <= nm.all;
         deallocate(nm);
         dump_req <= '1';
         wait until dump_ack = '1';
         dump_req <= '0';
      end if;
      if vblank_count + 1 >= MAXFRAME then
         report "MAXFRAME reached" severity note;
         done <= true;
         wait;
      end if;
   end process;

   -- command feeder
   process
      file infile : text;
      variable fs : FILE_OPEN_STATUS;
      variable il : line;
      variable k : std_logic_vector(7 downto 0);
      variable fr, d : std_logic_vector(31 downto 0);
      variable sp : character;
      variable sent : integer := 0;
      variable p_fr, p_rel, p_vb, idle_n : integer := -1;
   begin
      reset <= '1';
      for i in 1 to 64 loop wait until rising_edge(clk1x); end loop;
      reset <= '0';
      file_open(fs, infile, STREAM, read_mode);
      assert fs = OPEN_OK report "cannot open " & STREAM severity failure;
      while not endfile(infile) loop
         readline(infile, il);
         hread(il, k); read(il, sp); hread(il, fr); read(il, sp); hread(il, d);
         if PACED and to_integer(unsigned(fr)) /= p_fr then
            -- PACED: the game's DrawSync(0), VSync(0) loop. Frame F waits until
            -- the GPU has finished every earlier word, then for the next vblank,
            -- and keeps MAME's spacing (F - previous F vblanks at least)
            if p_fr >= 0 then
               idle_n := 0;
               while idle_n < 8 loop
                  wait until rising_edge(clk1x);
                  if gpu_idle then idle_n := idle_n + 1; else idle_n := 0; end if;
               end loop;
               p_vb := vblank_count;
               while vblank_count = p_vb or vblank_count < p_rel + to_integer(unsigned(fr)) - p_fr loop
                  wait until rising_edge(clk1x);
               end loop;
            end if;
            p_fr := to_integer(unsigned(fr)); p_rel := vblank_count; rel_vb <= vblank_count;
         end if;
         while not PACED and vblank_count < to_integer(unsigned(fr)) loop
            wait until rising_edge(clk1x);
         end loop;
         feed_frame <= to_integer(unsigned(fr));
         feed_count <= sent + 1;
         if unsigned(k) <= 1 then                       -- CPU write to GP0/GP1
            dmaOn <= '0';
            bus_addr <= x"0" when unsigned(k) = 0 else x"4";
            bus_dataWrite <= d;
            bus_write <= '1';
            wait until rising_edge(clk1x);
            bus_write <= '0';
            wait until rising_edge(clk1x);
            while bus_stall = '1' loop wait until rising_edge(clk1x); end loop;
         else                                           -- DMA2 word
            dmaOn <= '1';
            while gpu_dmaRequest = '0' loop wait until rising_edge(clk1x); end loop;
            DMA_GPU_write <= d;
            DMA_GPU_writeEna <= '1';
            wait until rising_edge(clk1x);
            DMA_GPU_writeEna <= '0';
         end if;
         sent := sent + 1;
      end loop;
      file_close(infile);
      dmaOn <= '0';
      feed_done <= true;
      report "stream done, words " & integer'image(sent) severity note;
      wait;
   end process;

   -- GPU idle (the drawing part of gpu.vhd's SS_Idle, as GTIME below) for
   -- PACED and the per-frame breakdown
   gidle : block
      alias i_proc_idle     is << signal .tb_gpu_infl.igpu.proc_idle     : std_logic >>;
      alias i_fifoIn_Empty  is << signal .tb_gpu_infl.igpu.fifoIn_Empty  : std_logic >>;
      alias i_fifoIn_Wr     is << signal .tb_gpu_infl.igpu.fifoIn_Wr     : std_logic >>;
      alias i_fifoIn_Valid  is << signal .tb_gpu_infl.igpu.fifoIn_Valid  : std_logic >>;
      alias i_fifoOut_idle  is << signal .tb_gpu_infl.igpu.fifoOut_idle  : std_logic >>;
      alias i_pipeline_busy is << signal .tb_gpu_infl.igpu.pipeline_busy : std_logic >>;
      alias i_pixelWrite    is << signal .tb_gpu_infl.igpu.pixelWrite    : std_logic >>;
   begin
      gpu_idle <= i_proc_idle = '1' and i_fifoIn_Empty = '1' and i_fifoIn_Wr = '0' and i_fifoIn_Valid = '0'
                  and i_fifoOut_idle = '1' and i_pipeline_busy = '0' and i_pixelWrite = '0';
   end block;

   -- Per stream frame breakdown (docs/gpu_blend_timing.md): frames_brk.txt,
   -- one line per stream frame, written when the next frame's first word is
   -- presented (with PACED that is its release; the cycles between the
   -- frame's end and the next release are idle):
   --   frame rel_vblank cycles busy tex clut dst wfifo other misses
   --   dst_reads dst_beats tex_reads tex_beats wr_beats walk drawn
   --   then drawn pixels by class: poly flat, flat semi, gouraud, gouraud
   --   semi, textured, textured semi; rect plain, semi, textured, textured semi
   --   then spx_cycles spx_waits (TEX_SPX_COST stall cycles, also in tex, and
   --   their count)
   -- busy = non-idle clk2x; each busy cycle goes to one class, first match:
   -- tex = the pipeline's texture fill (texReqActive: request, data and
   -- TEX_MISS_DELAY wait); clut = a palette read outstanding or requested;
   -- dst = a destination line read (poly/rect/line, class 3) requested or
   -- outstanding; wfifo = pixel write FIFO near full (pixelStall); other =
   -- the rest (pixel walking, setup, fills, copies, CPU uploads, write
   -- drain). misses = texReqActive rising edges; walk = poly span steps
   -- (PROCPIXELS with the pipeline taking a pixel), drawn = pixels entering
   -- the pipeline from poly or rect (walk minus drawn = poly steps outside
   -- the drawing area).
   brk : process (clk2x)
      file fb : text open write_mode is "frames_brk.txt";
      alias b_tex   is << signal .tb_gpu_infl.igpu.igpu_pixelpipeline.texReqActive : std_logic >>;
      alias b_pre   is << signal .tb_gpu_infl.igpu.pipeline_reqVRAMEnable : std_logic >>;
      alias b_epoly is << signal .tb_gpu_infl.igpu.poly_reqVRAMEnable     : std_logic >>;
      alias b_erect is << signal .tb_gpu_infl.igpu.rect_reqVRAMEnable     : std_logic >>;
      alias b_eline is << signal .tb_gpu_infl.igpu.line_reqVRAMEnable     : std_logic >>;
      alias b_stall is << signal .tb_gpu_infl.igpu.pixelStall             : std_logic >>;
      alias b_pstl  is << signal .tb_gpu_infl.igpu.pipeline_stall         : std_logic >>;
      alias b_ple   is << signal .tb_gpu_infl.igpu.poly_vramLineEna       : std_logic >>;
      alias b_pnew  is << signal .tb_gpu_infl.igpu.poly_pipeline_new      : std_logic >>;
      alias b_rnew  is << signal .tb_gpu_infl.igpu.rect_pipeline_new      : std_logic >>;
      alias b_ptex  is << signal .tb_gpu_infl.igpu.poly_pipeline_texture     : std_logic >>;
      alias b_psemi is << signal .tb_gpu_infl.igpu.poly_pipeline_transparent : std_logic >>;
      alias b_rtex  is << signal .tb_gpu_infl.igpu.rect_pipeline_texture     : std_logic >>;
      alias b_rsemi is << signal .tb_gpu_infl.igpu.rect_pipeline_transparent : std_logic >>;
      alias b_shade is << signal .tb_gpu_infl.igpu.igpu_poly.rec_shading     : std_logic >>;
      alias b_spx   is << signal .tb_gpu_infl.igpu.igpu_pixelpipeline.spxStall : std_logic >>;
      variable cspx, mspx : integer := 0;
      variable pspx : std_logic := '0';
      type px_t is array (0 to 9) of integer;
      variable px : px_t := (others => 0);
      variable pk : integer;
      type q_t is array (0 to 15) of integer;
      variable qc, qn : q_t := (others => 0);
      variable qw, qr, qcnt : integer := 0;
      variable l : line;
      variable cur : integer := -1;
      variable cyc, bsy, ctex, cclut, cdst, cwf, coth, mis, dr, db, tr, tb, wb, wk, dn : integer := 0;
      variable ptex : std_logic := '0';
      variable hcls : integer;
   begin
      if rising_edge(clk2x) then
         if feed_frame /= cur then
            if cur >= 0 then
               write(l, cur); write(l, ' '); write(l, rel_vb); write(l, ' '); write(l, cyc); write(l, ' ');
               write(l, bsy); write(l, ' '); write(l, ctex); write(l, ' '); write(l, cclut); write(l, ' ');
               write(l, cdst); write(l, ' '); write(l, cwf); write(l, ' '); write(l, coth); write(l, ' ');
               write(l, mis); write(l, ' '); write(l, dr); write(l, ' '); write(l, db); write(l, ' ');
               write(l, tr); write(l, ' '); write(l, tb); write(l, ' '); write(l, wb); write(l, ' ');
               write(l, wk); write(l, ' '); write(l, dn);
               for i in 0 to 9 loop write(l, ' '); write(l, px(i)); end loop;
               write(l, ' '); write(l, cspx); write(l, ' '); write(l, mspx);
               writeline(fb, l); flush(fb);
            end if;
            cur := feed_frame;
            cyc := 0; bsy := 0; ctex := 0; cclut := 0; cdst := 0; cwf := 0; coth := 0; mis := 0;
            dr := 0; db := 0; tr := 0; tb := 0; wb := 0; wk := 0; dn := 0; px := (others => 0); cspx := 0; mspx := 0;
         end if;
         cyc := cyc + 1;
         -- outstanding reads by class, in order (the port answers in order)
         if vram_DOUT_READY = '1' and qcnt > 0 then
            qn(qr) := qn(qr) - 1;
            if qn(qr) = 0 then qr := (qr + 1) mod 16; qcnt := qcnt - 1; end if;
         end if;
         if g_RD = '1' and g_BUSY = '0' then
            qc(qw) := g_cls; qn(qw) := to_integer(unsigned(g_BURSTCNT)); qw := (qw + 1) mod 16; qcnt := qcnt + 1;
            if g_cls = 3 then dr := dr + 1; db := db + to_integer(unsigned(g_BURSTCNT)); end if;
            if g_cls = 0 then tr := tr + 1; tb := tb + to_integer(unsigned(g_BURSTCNT)); end if;
         end if;
         if g_WE = '1' and g_BUSY = '0' then wb := wb + 1; end if;
         hcls := -1;
         if qcnt > 0 then hcls := qc(qr); end if;
         if b_tex = '1' and ptex = '0' then mis := mis + 1; end if;
         if b_spx = '1' and pspx = '0' then mspx := mspx + 1; end if;
         pspx := b_spx;
         ptex := b_tex;
         if b_ple = '1' and b_pstl = '0' then wk := wk + 1; end if;
         if b_pnew = '1' or b_rnew = '1' then dn := dn + 1; end if;
         -- drawn pixels by class: poly flat, flat semi, gouraud, gouraud semi,
         -- textured, textured semi; rect plain, semi, textured, textured semi
         if b_pnew = '1' then
            if b_ptex = '1' then pk := 4; elsif b_shade = '1' then pk := 2; else pk := 0; end if;
            if b_psemi = '1' then pk := pk + 1; end if;
            px(pk) := px(pk) + 1;
         elsif b_rnew = '1' then
            pk := 6;
            if b_rtex = '1' then pk := 8; end if;
            if b_rsemi = '1' then pk := pk + 1; end if;
            px(pk) := px(pk) + 1;
         end if;
         if not gpu_idle then
            bsy := bsy + 1;
            if b_spx = '1' then cspx := cspx + 1; end if;
            if b_tex = '1' or b_spx = '1' then ctex := ctex + 1;
            elsif hcls = 1 or (b_pre = '1' and b_tex = '0') then cclut := cclut + 1;
            elsif hcls = 3 or b_epoly = '1' or b_erect = '1' or b_eline = '1' then cdst := cdst + 1;
            elsif b_stall = '1' then cwf := cwf + 1;
            else coth := coth + 1;
            end if;
         end if;
      end if;
   end process;

   -- R23: GPU drawing time per stream frame and per vblank interval (GTIME)
   gtimer : if GTIME generate
      alias g_proc_idle     is << signal .tb_gpu_infl.igpu.proc_idle     : std_logic >>;
      alias g_fifoIn_Empty  is << signal .tb_gpu_infl.igpu.fifoIn_Empty  : std_logic >>;
      alias g_fifoIn_Wr     is << signal .tb_gpu_infl.igpu.fifoIn_Wr     : std_logic >>;
      alias g_fifoIn_Valid  is << signal .tb_gpu_infl.igpu.fifoIn_Valid  : std_logic >>;
      alias g_fifoOut_idle  is << signal .tb_gpu_infl.igpu.fifoOut_idle  : std_logic >>;
      alias g_pipeline_busy is << signal .tb_gpu_infl.igpu.pipeline_busy : std_logic >>;
      alias g_pixelWrite    is << signal .tb_gpu_infl.igpu.pixelWrite    : std_logic >>;
   begin
      process
         file ft : text open write_mode is "frames_time.txt";
         file fv : text open write_mode is "vblank_busy.txt";
         variable l : line;
         variable idle : boolean;
         variable cur, words, last_count : integer := -1;
         variable active, ended, flushed : boolean := false;
         variable t_start, t_end : time := 0 ns;
         variable busy, busy_end, settle : integer := 0;
         variable vb_start, vb_prev : integer := 0;
         variable vb_busy, vb_all : integer := 0;
         variable prev_irq : std_logic := '0';
         procedure emit(ov : integer) is
         begin
            write(l, cur); write(l, string'(" ")); write(l, words); write(l, string'(" "));
            write(l, t_start / 1 ns); write(l, string'(" ")); write(l, t_end / 1 ns); write(l, string'(" "));
            write(l, (t_end - t_start) / T2X); write(l, string'(" ")); write(l, busy_end);
            write(l, string'(" ")); write(l, ov); write(l, string'(" ")); write(l, vb_start);
            writeline(ft, l);
         end procedure;
      begin
         wait until rising_edge(clk2x) or done;
         if done then                                -- MAXFRAME before the stream ended
            if active and not flushed then
               if not ended then t_end := now; busy_end := busy; emit(1); else emit(0); end if;
            end if;
            wait;
         end if;
         idle := g_proc_idle = '1' and g_fifoIn_Empty = '1' and g_fifoIn_Wr = '0' and g_fifoIn_Valid = '0'
                 and g_fifoOut_idle = '1' and g_pipeline_busy = '0' and g_pixelWrite = '0';
         -- per vblank interval
         vb_all := vb_all + 1;
         if not idle then vb_busy := vb_busy + 1; end if;
         if irq_VBLANK = '1' and prev_irq = '0' then
            vb_prev := vb_prev + 1;
            write(l, vb_prev); write(l, string'(" ")); write(l, vb_busy); write(l, string'(" ")); write(l, vb_all);
            writeline(fv, l);
            vb_busy := 0; vb_all := 0;
         end if;
         prev_irq := irq_VBLANK;
         -- per stream frame
         if feed_count /= last_count then           -- a word was presented
            last_count := feed_count;
            settle := 0;
            if feed_frame /= cur then
               if active then
                  if not ended then t_end := now; busy_end := busy; emit(1); else emit(0); end if;
               end if;
               cur := feed_frame; words := 0; active := true; t_start := now; busy := 0;
            end if;
            words := words + 1;
            ended := false;
         else
            settle := settle + 1;
         end if;
         if active and not ended then
            if not idle then busy := busy + 1; end if;
            if idle and settle >= 4 then             -- past the FIFO write latency of the last word
               ended := true; t_end := now; busy_end := busy;
            end if;
         end if;
         if active and ended and feed_done and not flushed then
            emit(0); flushed := true;
         end if;
      end process;
   end generate;

   -- Model of rtl/gnet/gnet_ddr3_arb.sv as the core sees it (branch
   -- ddr3-arb-int): a one-entry command register in front of the port; a
   -- client command is taken when the register is free or being accepted,
   -- and the client sees BUSY until then (c_busy = !sel_c). With ROT, a
   -- rotation write is due every 10 cycles in the first 3,200 cycles of
   -- each 4,306-cycle line, 240 lines of 263 (320 x 240 at the 320-pixel
   -- dot rate), and wins the register over the core, as rotation does in the
   -- arbiter. Rotation writes go to 0x24000000, which the memory model below
   -- does not store. Read data all belongs to the core (rotation never
   -- reads), so DOUT_READY passes through. The memory model never asserts
   -- BUSY, so the register is accepted in the cycle it is presented.
   garb : if ARB generate
      signal k_valid, k_rd : std_logic := '0';
      signal rot_q         : integer := 0;
      signal lpos          : integer := 0;
      signal lnum          : integer := 0;
   begin
      process (all)
         variable load, req_c, req_r : boolean;
      begin
         load  := true;      -- k_valid = 0 or accepted: the model never asserts BUSY
         req_r := ROT and rot_q > 0;
         req_c := g_RD = '1' or g_WE = '1';
         if load and req_c and not req_r then g_BUSY <= '0'; else g_BUSY <= '1'; end if;
      end process;
      process (clk2x)
         variable due : boolean;
      begin
         if rising_edge(clk2x) then
            due := ROT and lnum < 240 and lpos < 3200 and (lpos mod 10) = 9;
            if lpos = 4305 then
               lpos <= 0;
               if lnum = 262 then lnum <= 0; else lnum <= lnum + 1; end if;
            else
               lpos <= lpos + 1;
            end if;
            k_valid <= '0'; vram_RD <= '0'; vram_WE <= '0';
            if ROT and rot_q > 0 then
               k_valid <= '1'; vram_WE <= '1';
               vram_ADDR <= x"4000000";               -- outside the model's VRAM
               vram_BURSTCNT <= x"01"; vram_BE <= x"0F"; vram_DIN <= (others => '0');
               if due then rot_q <= rot_q; else rot_q <= rot_q - 1; end if;
            else
               if due then rot_q <= rot_q + 1; end if;
               if g_RD = '1' or g_WE = '1' then
                  k_valid <= '1'; vram_RD <= g_RD; vram_WE <= g_WE;
                  vram_ADDR <= g_ADDR; vram_BURSTCNT <= g_BURSTCNT;
                  vram_DIN <= g_DIN; vram_BE <= g_BE;
               end if;
            end if;
         end if;
      end process;
   end generate;
   gdirect : if not ARB generate
      g_BUSY <= vram_BUSY;
      vram_RD <= g_RD; vram_WE <= g_WE; vram_ADDR <= g_ADDR;
      vram_BURSTCNT <= g_BURSTCNT; vram_DIN <= g_DIN; vram_BE <= g_BE;
   end generate;

   gcls : block
      alias e_pipe is << signal .tb_gpu_infl.igpu.pipeline_reqVRAMEnable : std_logic >>;
      alias e_vid  is << signal .tb_gpu_infl.igpu.videoout_reqVRAMEnable : std_logic >>;
      alias e_poly is << signal .tb_gpu_infl.igpu.poly_reqVRAMEnable     : std_logic >>;
      alias e_rect is << signal .tb_gpu_infl.igpu.rect_reqVRAMEnable     : std_logic >>;
      alias e_line is << signal .tb_gpu_infl.igpu.line_reqVRAMEnable     : std_logic >>;
      alias s_pipe is << signal .tb_gpu_infl.igpu.pipeline_reqVRAMSize   : unsigned(10 downto 0) >>;
      alias t_req  is << signal .tb_gpu_infl.igpu.igpu_pixelpipeline.texReqActive : std_logic >>;
      signal cls_now : integer range 0 to 4;
   begin
      cls_now <= 2 when e_vid = '1' else
                 0 when e_pipe = '1' and t_req = '1' else
                 1 when e_pipe = '1' else
                 3 when (e_poly = '1' or e_rect = '1' or e_line = '1') else 4;
      -- the class is latched when the GPU's state machine issues the read
      -- (reqVRAMEnable is still up in that cycle)
      process (clk2x) begin
         if rising_edge(clk2x) then
            if g_RD = '0' then g_cls <= cls_now; end if;
         end if;
      end process;
   end block;
   m_cls <= g_cls;   -- with ARB the register stage delays RD by one cycle; the class is held

   -- BWMON, GPU side: the GPU's own port (g_*), so the time a command waits
   -- on BUSY counts. Per GPU vblank interval, ddr3_frames.txt:
   --   vblank cycles rd_cmd rd_beats wr_beats busy_cycles max_run
   --   max_beats_4306 max_beats_1024 max_beats_256 max_beats_64
   --   reads_texture reads_clut reads_video reads_destination reads_copy
   --   cycles_read_waiting_with_writes_queued
   -- A command is counted when accepted (RD or WE with BUSY low). busy_cycles
   -- counts cycles with a command presented (waiting or accepted) or read
   -- beats still owed to the GPU; max_run is the longest busy stretch;
   -- max_beats_N the most accepted beats in an aligned window of N cycles.
   bwmon : process
      type int_arr is array (0 to 3) of integer;
      constant WIN : int_arr := (4306, 1024, 256, 64);
      file fm : text open write_mode is "ddr3_frames.txt";
      variable l : line;
      variable cyc, rdc, rdb, wrb, bsy, run, mrun, owed, beats : integer := 0;
      type cls_arr is array (0 to 4) of integer;
      variable ccnt : cls_arr := (others => 0);
      variable wpend : integer := 0;     -- read outstanding while pixel writes wait in the FIFO
      alias f_empty is << signal .tb_gpu_infl.igpu.fifoOut_Empty : std_logic >>;
      variable wcnt, wpos, wmax : int_arr := (others => 0);
      variable vb : integer := 0;
      variable pirq : std_logic := '0';
   begin
      wait until rising_edge(clk2x) or done;
      if done then wait; end if;
      cyc := cyc + 1;
      beats := 0;
      if vram_DOUT_READY = '1' and owed > 0 then owed := owed - 1; end if;
      if g_RD = '1' and g_BUSY = '0' then
         rdc := rdc + 1;
         ccnt(g_cls) := ccnt(g_cls) + 1;
         beats := to_integer(unsigned(g_BURSTCNT));
         rdb := rdb + beats;
         owed := owed + beats;
      end if;
      if g_WE = '1' and g_BUSY = '0' then wrb := wrb + 1; beats := beats + 1; end if;
      if owed > 0 and f_empty = '0' then wpend := wpend + 1; end if;
      if g_RD = '1' or g_WE = '1' or owed > 0 then
         bsy := bsy + 1; run := run + 1;
         if run > mrun then mrun := run; end if;
      else
         run := 0;
      end if;
      for k in 0 to 3 loop
         wcnt(k) := wcnt(k) + beats;
         wpos(k) := wpos(k) + 1;
         if wpos(k) = WIN(k) then
            if wcnt(k) > wmax(k) then wmax(k) := wcnt(k); end if;
            wcnt(k) := 0; wpos(k) := 0;
         end if;
      end loop;
      if irq_VBLANK = '1' and pirq = '0' then
         vb := vb + 1;
         write(l, vb); write(l, ' '); write(l, cyc); write(l, ' ');
         write(l, rdc); write(l, ' '); write(l, rdb); write(l, ' ');
         write(l, wrb); write(l, ' '); write(l, bsy); write(l, ' '); write(l, mrun);
         for k in 0 to 3 loop write(l, ' '); write(l, wmax(k)); end loop;
         for k in 0 to 4 loop write(l, ' '); write(l, ccnt(k)); end loop;
         write(l, ' '); write(l, wpend);
         writeline(fm, l);
         flush(fm);
         cyc := 0; rdc := 0; rdb := 0; wrb := 0; bsy := 0; mrun := 0;
         wmax := (others => 0);
         ccnt := (others => 0); wpend := 0;
      end if;
      pirq := irq_VBLANK;
   end process;

   -- Drawing unit watchdogs (issue #10): gpu_line, gpu_rect and gpu_poly
   -- abandon a primitive when their `timeout` counter reaches 1,048,575
   -- clk2x and pulse `error`. Report every such abort, and every polygon or
   -- rectangle whose drawing took more than 262,144 clk2x (the unit's
   -- drawTiming counter, cycles out of IDLE after its last command word).
   process (clk2x)
      alias p_dt is << signal .tb_gpu_infl.igpu.igpu_poly.drawTiming : unsigned(31 downto 0) >>;
      alias r_dt is << signal .tb_gpu_infl.igpu.igpu_rect.drawTiming : unsigned(31 downto 0) >>;
      variable p_last, r_last : integer := 0;
      variable p_now, r_now : integer;
   begin
      if rising_edge(clk2x) then
         if err_poly = '1' then report "WATCHDOG poly abort, stream frame " & integer'image(feed_frame) severity note; end if;
         if err_rect = '1' then report "WATCHDOG rect abort, stream frame " & integer'image(feed_frame) severity note; end if;
         if err_line = '1' then report "WATCHDOG line abort, stream frame " & integer'image(feed_frame) severity note; end if;
         p_now := to_integer(p_dt(30 downto 0));
         r_now := to_integer(r_dt(30 downto 0));
         if p_now = 0 and p_last > 262144 then
            report "LONG poly " & integer'image(p_last) & " clk2x, stream frame " & integer'image(feed_frame) severity note;
         end if;
         if r_now = 0 and r_last > 262144 then
            report "LONG rect " & integer'image(r_last) & " clk2x, stream frame " & integer'image(feed_frame) severity note;
         end if;
         p_last := p_now; r_last := r_now;
      end if;
   end process;

   -- Texture cache misses (docs/gpu_speed_sianniv.md): texmiss.txt, one line
   -- per GPU vblank interval: vblank misses miss_cycles misses_poly
   -- misses_rect. misses = rising edges of the pipeline's texReqActive (one
   -- per miss event, whatever the fill size); miss_cycles = clk2x edges with
   -- texReqActive high (request, data and TEX_MISS_DELAY wait; the pipeline
   -- is stalled meanwhile); misses_poly / misses_rect = the misses that start
   -- while gpu_poly / gpu_rect is out of IDLE (drawTiming counting).
   texmon : process (clk2x)
      file ftm : text open write_mode is "texmiss.txt";
      alias t_act is << signal .tb_gpu_infl.igpu.igpu_pixelpipeline.texReqActive : std_logic >>;
      alias tp_dt is << signal .tb_gpu_infl.igpu.igpu_poly.drawTiming : unsigned(31 downto 0) >>;
      alias tr_dt is << signal .tb_gpu_infl.igpu.igpu_rect.drawTiming : unsigned(31 downto 0) >>;
      variable l : line;
      variable tm, tc, tmp, tmr, vbn : integer := 0;
      variable pa, pv : std_logic := '0';
   begin
      if rising_edge(clk2x) then
         if t_act = '1' then
            tc := tc + 1;
            if pa = '0' then
               tm := tm + 1;
               if tp_dt /= 0 then tmp := tmp + 1; end if;
               if tr_dt /= 0 then tmr := tmr + 1; end if;
            end if;
         end if;
         pa := t_act;
         if irq_VBLANK = '1' and pv = '0' then
            vbn := vbn + 1;
            write(l, vbn); write(l, ' '); write(l, tm); write(l, ' '); write(l, tc);
            write(l, ' '); write(l, tmp); write(l, ' '); write(l, tmr);
            writeline(ftm, l);
            flush(ftm);
            tm := 0; tc := 0; tmp := 0; tmr := 0;
         end if;
         pv := irq_VBLANK;
      end if;
   end process;

end architecture;
