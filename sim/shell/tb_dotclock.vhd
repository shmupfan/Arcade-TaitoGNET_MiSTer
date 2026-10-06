-- DV1 integer pixel clock check of rtl/gpu_videoout_async.vhd at the G-NET
-- video modes (docs/m4_shell.md 2). The video out runs alone on its three
-- clocks (clk1x 33.8688, clk2x 67.7376, clkvid 53.693175 MHz) with the
-- GP1(06h)/(07h)/(08h) settings the six games write (MAME 0.288 oracle
-- logs): 240 lines, NTSC, not interlaced, widths 256 (BIOS), 320 (all
-- games), 512 and 640 (Ray Crisis). Per mode, over 3 frames after one
-- frame of settling, in clkvid clocks:
--   * interval between dot enables (ce) inside the active area, and over
--     the whole line (the line length 3413 is no multiple of the divider,
--     so one short interval per line falls at the line wrap, in blanking)
--   * dots per active line, and the offset of the first active dot from
--     the hsync rising edge (the same on every line = no line-to-line jitter)
--   * line length between hsync rising edges and lines per frame
--   * vsync edges that do not fall on an hsync rising edge
-- Prints one RESULT line per mode; stops with failure on a violation.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pGPU.all;

entity tb_dotclock is
end entity;

architecture sim of tb_dotclock is
   signal clk1x  : std_logic := '0';
   signal clk2x  : std_logic := '0';
   signal clkvid : std_logic := '0';
   signal reset  : std_logic := '1';

   signal settings : tvideoout_settings;
   signal reports  : tvideoout_reports;
   signal req2x    : tvideoout_request;
   signal reqvid   : tvideoout_request;
   signal raddr    : unsigned(10 downto 0);
   signal vout     : tvideoout_out;
   signal ss_in    : tvideoout_ss;
   signal ss_out   : tvideoout_ss;
   signal allowun  : std_logic;

   signal mode     : integer := 1;
   signal measure  : boolean := false;
   signal done     : boolean := false;
begin
   clk1x  <= not clk1x  after 14.7625 ns when not done;
   clk2x  <= not clk2x  after  7.3813 ns when not done;
   clkvid <= not clkvid after  9.3121 ns when not done;   -- 53.693175 MHz

   ss_in <= (interlacedDisplayField => '0', nextHCount => x"001", vpos => (others => '0'),
             vdisp => (others => '0'), inVsync => '0', activeLineLSB => '0',
             GPUSTAT_InterlaceField => '1', GPUSTAT_DrawingOddline => '0');

   process (mode)
   begin
      settings <= (GPUSTAT_VerRes => '0', GPUSTAT_PalVideoMode => '0', GPUSTAT_VertInterlace => '0',
                   GPUSTAT_HorRes2 => '0', GPUSTAT_HorRes1 => "01", GPUSTAT_ColorDepth24 => '0',
                   GPUSTAT_DisplayDisable => '0', vramRange => (others => '0'),
                   hDisplayRange => x"C58258", vDisplayRange => x"40010",
                   pal60 => '0', syncInterlace => '0', rotate180 => '0', fixedVBlank => '0',
                   vCrop => "00", hCrop => '0', dither24 => '0', render24 => '0');
      case mode is
         when 0 => settings.GPUSTAT_HorRes1 <= "00"; settings.hDisplayRange <= x"C40240";   -- 08000000, 06C40240
         when 1 => settings.GPUSTAT_HorRes1 <= "01"; settings.hDisplayRange <= x"C58258";   -- 08000001, 06C58258
         when 2 => settings.GPUSTAT_HorRes1 <= "10"; settings.hDisplayRange <= x"C67267";   -- 08000002, 06C67267
         when others => settings.GPUSTAT_HorRes1 <= "11"; settings.hDisplayRange <= x"C6C26C";   -- 08000003, 06C6C26C
      end case;
   end process;

   dut : entity work.gpu_videoout_async
   port map (
      clk1x => clk1x, clk2x => clk2x, clkvid => clkvid, ce_1x => '1',
      reset_1x => reset, softReset_1x => '0', savestate_pause_1x => '0', system_paused_1x => '0',
      allowunpause1x => allowun,
      videoout_settings_1x => settings, videoout_reports_1x => reports,
      videoout_request_2x => req2x, videoout_request_vid => reqvid,
      videoout_readAddr => raddr, videoout_pixelRead => x"7FFF", videoout_pixelRead2 => x"0000",
      overlay_data => (others => '0'), overlay_ena => '0',
      videoout_out => vout, videoout_ss_in => ss_in, videoout_ss_out => ss_out);

   stim : process
      constant FRAME : time := 16.72 ms;
   begin
      reset <= '1';
      wait for 2 us;
      reset <= '0';
      for m in 0 to 3 loop
         mode <= m;
         measure <= false;
         wait for FRAME;           -- settle: new divider, a full frame
         measure <= true;
         wait for 3 * FRAME;
         measure <= false;
         wait for 1 us;
      end loop;
      done <= true;
      wait;
   end process;

   mon : process (clkvid)
      variable n          : integer := 0;
      variable last_ce    : integer := -1;
      variable last_ce_act: boolean := false;
      variable act_min, act_max, all_min, all_max : integer;
      variable dots, dots_min, dots_max : integer;
      variable first_dot  : integer;
      variable ph_min, ph_max : integer;
      variable hs_q, vs_q : std_logic := '0';
      variable last_hs    : integer := -1;
      variable len_min, len_max : integer;
      variable lines, lines_frame_min, lines_frame_max : integer;
      variable vs_bad     : integer;
      variable meas_q     : boolean := false;
      variable hs_rise    : boolean;
      variable divs       : integer;
      variable lines_meas : integer;
      procedure clear is
      begin
         act_min := 9999; act_max := 0; all_min := 9999; all_max := 0;
         dots := 0; dots_min := 9999; dots_max := 0; first_dot := -1;
         ph_min := 9999; ph_max := -1; len_min := 9999; len_max := 0;
         lines := -1; lines_frame_min := 9999; lines_frame_max := 0; vs_bad := 0;
         last_ce := -1; last_hs := -1; lines_meas := 0;
      end procedure;
   begin
      if rising_edge(clkvid) then
         n := n + 1;
         if measure and not meas_q then
            clear;
         end if;
         hs_rise := (vout.hsync = '1' and hs_q = '0');
         if measure then
            -- dot enable intervals
            if vout.ce = '1' then
               if last_ce >= 0 then
                  all_min := minimum(all_min, n - last_ce);
                  all_max := maximum(all_max, n - last_ce);
                  if vout.hblank = '0' and last_ce_act then
                     act_min := minimum(act_min, n - last_ce);
                     act_max := maximum(act_max, n - last_ce);
                  end if;
               end if;
               last_ce := n;
               last_ce_act := (vout.hblank = '0');
               if vout.hblank = '0' then
                  if dots = 0 and last_hs >= 0 then first_dot := n - last_hs; end if;
                  dots := dots + 1;
               end if;
            end if;
            -- lines
            if hs_rise then
               if last_hs >= 0 then
                  len_min := minimum(len_min, n - last_hs);
                  len_max := maximum(len_max, n - last_hs);
               end if;
               if dots > 0 and first_dot >= 0 then
                  dots_min := minimum(dots_min, dots);
                  dots_max := maximum(dots_max, dots);
                  ph_min := minimum(ph_min, first_dot);
                  ph_max := maximum(ph_max, first_dot);
               end if;
               dots := 0;
               first_dot := -1;
               last_hs := n;
               if lines >= 0 then lines := lines + 1; end if;
               lines_meas := lines_meas + 1;
            end if;
            -- vsync edges on an hsync rising edge
            if vout.vsync /= vs_q then
               if not hs_rise then vs_bad := vs_bad + 1; end if;
               if vout.vsync = '1' then
                  if lines > 0 then
                     lines_frame_min := minimum(lines_frame_min, lines);
                     lines_frame_max := maximum(lines_frame_max, lines);
                  end if;
                  lines := 0;
               end if;
            end if;
         end if;
         if meas_q and not measure then
            case mode is
               when 0 => divs := 10;
               when 1 => divs := 8;
               when 2 => divs := 5;
               when others => divs := 4;
            end case;
            report "RESULT mode " & integer'image(mode) &
                   " width " & integer'image(to_integer(vout.DisplayWidth)) &
                   " div " & integer'image(divs) &
                   " ce_active " & integer'image(act_min) & ".." & integer'image(act_max) &
                   " ce_all " & integer'image(all_min) & ".." & integer'image(all_max) &
                   " dots/line " & integer'image(dots_min) & ".." & integer'image(dots_max) &
                   " first_dot_after_hs " & integer'image(ph_min) & ".." & integer'image(ph_max) &
                   " line " & integer'image(len_min) & ".." & integer'image(len_max) &
                   " lines/frame " & integer'image(lines_frame_min) & ".." & integer'image(lines_frame_max) &
                   " lines_measured " & integer'image(lines_meas) &
                   " vs_not_on_hs " & integer'image(vs_bad);
            assert act_min = divs and act_max = divs report "active dot period not constant" severity failure;
            assert ph_min = ph_max report "first dot phase differs between lines" severity failure;
            assert len_min = 3413 and len_max = 3413 report "line length" severity failure;
            assert vs_bad = 0 report "vsync edge off hsync" severity failure;
         end if;
         hs_q := vout.hsync;
         vs_q := vout.vsync;
         meas_q := measure;
      end if;
   end process;
end architecture;
