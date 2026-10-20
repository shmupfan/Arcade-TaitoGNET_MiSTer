-- Issue #11 (Scandoubler Fx): trace of rtl/gpu_videoout_async.vhd's video
-- out at one G-NET mode, for sim/shell/tb_sd_trace.sv. Same clocks and
-- GP1 settings as tb_dotclock.vhd (MODE 0 to 5: 256, 320, 512, 640 dots
-- 240p; 640 and 512 dots 480i). Fixed VBlank is off, as in every G-NET
-- build (PSX.sv: fixedVBlank = GNET_OPT(..., 1'b0)).
--
-- One line per dot enable (ce) after one frame of settling, for FRAMES
-- frames: "<clocks since the previous ce> <hsync> <vsync> <hblank>
-- <vblank>". Everything after the video out (sync keeper, CRT position at
-- 0, PSX.sv's video_aspect, arcade_video) samples these four signals on ce
-- only, so this record is exact for them.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.pGPU.all;

entity tb_vtrace is
   generic (MODE : integer := 1; FRAMES : integer := 4; OUTFILE : string := "vtrace.txt");
end entity;

architecture sim of tb_vtrace is
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

   signal record_on : boolean := false;
   signal done      : boolean := false;
begin
   clk1x  <= not clk1x  after 14.7625 ns when not done;
   clk2x  <= not clk2x  after  7.3813 ns when not done;
   clkvid <= not clkvid after  9.3121 ns when not done;   -- 53.693175 MHz

   ss_in <= (interlacedDisplayField => '0', nextHCount => x"001", vpos => (others => '0'),
             vdisp => (others => '0'), inVsync => '0', activeLineLSB => '0',
             GPUSTAT_InterlaceField => '1', GPUSTAT_DrawingOddline => '0');

   process
   begin
      settings <= (GPUSTAT_VerRes => '0', GPUSTAT_PalVideoMode => '0', GPUSTAT_VertInterlace => '0',
                   GPUSTAT_HorRes2 => '0', GPUSTAT_HorRes1 => "01", GPUSTAT_ColorDepth24 => '0',
                   GPUSTAT_DisplayDisable => '0', vramRange => (others => '0'),
                   hDisplayRange => x"C58258", vDisplayRange => x"40010",
                   pal60 => '0', syncInterlace => '0', rotate180 => '0', fixedVBlank => '0',
                   vCrop => "00", hCrop => '0', dither24 => '0', render24 => '0');
      case MODE is
         when 0 => settings.GPUSTAT_HorRes1 <= "00"; settings.hDisplayRange <= x"C40240";   -- 08000000, 06C40240
         when 1 => settings.GPUSTAT_HorRes1 <= "01"; settings.hDisplayRange <= x"C58258";   -- 08000001, 06C58258
         when 2 => settings.GPUSTAT_HorRes1 <= "10"; settings.hDisplayRange <= x"C67267";   -- 08000002, 06C67267
         when 3 => settings.GPUSTAT_HorRes1 <= "11"; settings.hDisplayRange <= x"C6C26C";   -- 08000003, 06C6C26C
         when 4 => settings.GPUSTAT_HorRes1 <= "11"; settings.hDisplayRange <= x"C6C26C";   -- 08000027, 640x480i
                   settings.GPUSTAT_VerRes <= '1'; settings.GPUSTAT_VertInterlace <= '1';
         when others => settings.GPUSTAT_HorRes1 <= "10"; settings.hDisplayRange <= x"C67267";   -- 08000026, 512x480i
                   settings.GPUSTAT_VerRes <= '1'; settings.GPUSTAT_VertInterlace <= '1';
      end case;
      wait;
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
      wait for FRAME;
      record_on <= true;
      wait for FRAMES * FRAME;
      record_on <= false;
      wait for 1 us;
      done <= true;
      wait;
   end process;

   rec : process (clkvid)
      file f        : text open write_mode is OUTFILE;
      variable l    : line;
      variable last : integer := -1;
      variable n    : integer := 0;
      function b(s : std_logic) return character is
      begin
         if s = '1' then return '1'; else return '0'; end if;
      end function;
   begin
      if rising_edge(clkvid) then
         n := n + 1;
         if record_on and vout.ce = '1' then
            if last < 0 then
               write(l, integer'(0));
            else
               write(l, n - last);
            end if;
            write(l, ' ');
            write(l, b(vout.hsync)); write(l, ' ');
            write(l, b(vout.vsync)); write(l, ' ');
            write(l, b(vout.hblank)); write(l, ' ');
            write(l, b(vout.vblank));
            writeline(f, l);
            last := n;
         end if;
      end if;
   end process;
end architecture;
