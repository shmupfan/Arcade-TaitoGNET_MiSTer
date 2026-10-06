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

entity tb_gpu_replay is
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
      VIDCAP      : boolean := true    -- video output capture for the frames in DUMPS
   );
end entity;

architecture arch of tb_gpu_replay is

   constant T1X  : time := 29524 ps;    -- 33.8688 MHz
   constant T2X  : time := 14762 ps;    -- 67.7376 MHz
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

   signal dump_req  : std_logic := '0';
   signal dump_ack  : std_logic := '0';
   signal dump_name : string(1 to 32) := (others => ' ');
   signal dump_len  : integer := 0;
   signal done      : boolean := false;

   signal video_ce_s, video_hblank_s, video_vblank_s : std_logic;

   -- feeder progress for GTIME: frame of the word being presented, word count
   signal feed_frame : integer := -1;
   signal feed_count : integer := 0;
   signal feed_done  : boolean := false;
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
   generic map (VRAM_Y_BITS => VRAM_Y_BITS)
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
      errorLINE => open, errorRECT => open, errorPOLY => open, errorGPU => open,
      errorMASK => open, errorFIFO => open,
      bus_addr => bus_addr, bus_dataWrite => bus_dataWrite, bus_read => '0',
      bus_write => bus_write, bus_dataRead => bus_dataRead, bus_stall => bus_stall,
      dmaOn => dmaOn, gpu_dmaRequest => gpu_dmaRequest, DMA_GPU_waiting => '0',
      DMA_GPU_writeEna => DMA_GPU_writeEna, DMA_GPU_readEna => '0',
      DMA_GPU_write => DMA_GPU_write, DMA_GPU_read => open,
      irq_VBLANK => irq_VBLANK, irq_GPU => open,
      vram_pause => '0', vram_paused => open,
      vram_BUSY => vram_BUSY, vram_DOUT => vram_DOUT, vram_DOUT_READY => vram_DOUT_READY,
      vram_BURSTCNT => vram_BURSTCNT, vram_ADDR => vram_ADDR, vram_DIN => vram_DIN,
      vram_BE => vram_BE, vram_WE => vram_WE, vram_RD => vram_RD,
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
   -- 64-bit bursts, one-cycle read latency, writes complete in one cycle.
   process
      type mem_t is array (0 to 1048575) of std_logic_vector(63 downto 0);
      variable mem : mem_t := (others => (others => '0'));
      variable a, n : integer;
      file f : text;
      type bin_file is file of character;
      file fb : bin_file;
      variable w : std_logic_vector(63 downto 0);
      variable ch : character;
      variable loaded : boolean := false;
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
      wait until rising_edge(clk2x);
      if vram_RD = '1' then
         a := to_integer(unsigned(vram_ADDR(22 downto 3)));
         n := to_integer(unsigned(vram_BURSTCNT));
         for i in 1 to VRAM_RD_LAT loop wait until rising_edge(clk2x); end loop;
         wait until rising_edge(clk2x);
         for i in 0 to n - 1 loop
            vram_DOUT <= mem((a + i) mod 1048576);
            vram_DOUT_READY <= '1';
            wait until rising_edge(clk2x);
         end loop;
         vram_DOUT_READY <= '0';
      end if;
      if vram_WE = '1' then
         a := to_integer(unsigned(vram_ADDR(22 downto 3)));
         w := mem(a);
         for b in 0 to 7 loop
            if vram_BE(b) = '1' then w(b * 8 + 7 downto b * 8) := vram_DIN(b * 8 + 7 downto b * 8); end if;
         end loop;
         mem(a) := w;
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
   begin
      reset <= '1';
      for i in 1 to 64 loop wait until rising_edge(clk1x); end loop;
      reset <= '0';
      file_open(fs, infile, STREAM, read_mode);
      assert fs = OPEN_OK report "cannot open " & STREAM severity failure;
      while not endfile(infile) loop
         readline(infile, il);
         hread(il, k); read(il, sp); hread(il, fr); read(il, sp); hread(il, d);
         while vblank_count < to_integer(unsigned(fr)) loop
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

   -- R23: GPU drawing time per stream frame and per vblank interval (GTIME)
   gtimer : if GTIME generate
      alias g_proc_idle     is << signal .tb_gpu_replay.igpu.proc_idle     : std_logic >>;
      alias g_fifoIn_Empty  is << signal .tb_gpu_replay.igpu.fifoIn_Empty  : std_logic >>;
      alias g_fifoIn_Wr     is << signal .tb_gpu_replay.igpu.fifoIn_Wr     : std_logic >>;
      alias g_fifoIn_Valid  is << signal .tb_gpu_replay.igpu.fifoIn_Valid  : std_logic >>;
      alias g_fifoOut_idle  is << signal .tb_gpu_replay.igpu.fifoOut_idle  : std_logic >>;
      alias g_pipeline_busy is << signal .tb_gpu_replay.igpu.pipeline_busy : std_logic >>;
      alias g_pixelWrite    is << signal .tb_gpu_replay.igpu.pixelWrite    : std_logic >>;
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

end architecture;
