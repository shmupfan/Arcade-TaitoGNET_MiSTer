-- End-to-end bench for the debug overlay (docs/hw_debug_overlay.md):
-- zn_dbg_regs on a 50 MHz clock (clk_cpu), zn_dbg_overlay with its
-- cdc_handshake to a 53.693175 MHz video clock, the OSD bit on a
-- 33.8688 MHz clock, all asynchronous with random start phases and the
-- rtl/gnet/cdc metastability model on.
--
-- A video timing generator stands in for psx_mister plus PSX.sv's
-- video_aspect register: hb, vb and rgb_in change on ce_pix only, rgb_in is
-- a gradient and 0 in blanking. The bench samples rgb_out, hb and vb on
-- every ce_pix edge, as gamma_corr does.
--
-- Checks:
--   frames 0 and 1 (option off): rgb_out = rgb_in on every clk_vid edge
--   option on: rgb_out = rgb_in in blanking and outside the text box on
--   every ce_pix edge
--   the frame CAPTURE is written to OUTF (P3 PPM); check_frame.py decodes
--   the text and compares it with the values of this stimulus
--
-- DR = 1: the overlay's DR row (DR_ROW = 1) on an asynchronous
-- 67.7376 MHz clk_dr, whose dr_word changes from 0 to DR_VAL in frame 1
-- (check_frame.py --dr expects "DR 1010 01A3").

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use std.textio.all;

entity tb_zn_dbg_overlay is
   generic
   (
      HA      : integer := 320;   -- active dots
      HBL     : integer := 48;    -- blank dots
      VA      : integer := 240;   -- active lines
      VBL     : integer := 22;    -- blank lines
      DIV     : integer := 8;     -- clk_vid cycles per dot (8: 320 wide, 4: 640 wide)
      DBL     : integer := 0;     -- hres_dbl
      CAPTURE : integer := 3;     -- frame written to the PPM
      PH_SRC  : integer := 3;     -- start phases in ns
      PH_VID  : integer := 11;
      PH_CFG  : integer := 7;
      META    : integer := 9;     -- SIM_META_WINDOW in ns (0 = model off)
      DR      : integer := 0;     -- 1: DR row on clk_dr
      PH_DR   : integer := 5;
      OUTF    : string  := "frame.ppm"   -- written in the run directory
   );
end entity;

architecture sim of tb_zn_dbg_overlay is

   constant T_SRC : time := 20 ns;
   constant T_VID : time := 18624 ps;
   constant T_CFG : time := 29526 ps;
   constant X0    : integer := 16;
   constant Y0    : integer := 16;
   constant T_DR  : time := 14763 ps;
   constant DR_VAL : std_logic_vector(31 downto 0) := x"101001A3";   -- rot_ovf, mirror_ovf, hiwater 1A3h
   constant NROWS : integer := 10 + DR;

   signal clk_src, clk_vid, clk_cfg, clk_dr : std_logic := '0';
   signal dr_word    : std_logic_vector(31 downto 0) := (others => '0');
   signal done       : boolean := false;

   -- capture side
   signal core_reset : std_logic := '0';
   signal pc         : unsigned(31 downto 0) := x"BFC00000";
   signal dat_take   : std_logic := '0';
   signal dat_addr   : unsigned(31 downto 0) := (others => '0');
   signal wd_fire    : std_logic := '0';
   signal wd_kick    : std_logic := '0';
   signal ctrl       : std_logic_vector(7 downto 0) := x"10";
   signal sec_cmd    : std_logic := '0';
   signal rd_idx     : std_logic_vector(3 downto 0);
   signal rd_word    : std_logic_vector(31 downto 0);

   -- video side
   signal cfg_en     : std_logic := '0';
   signal ce_pix     : std_logic := '0';
   signal hb, vb     : std_logic := '1';
   signal rgb_in     : std_logic_vector(23 downto 0) := (others => '0');
   signal rgb_out    : std_logic_vector(23 downto 0);
   signal dbl_s      : std_logic;

   signal frame      : integer := 0;
   signal stim_done  : boolean := false;

begin

   dbl_s <= '1' when DBL = 1 else '0';

   clk_src <= not clk_src after T_SRC / 2 when not done;
   clk_cfg <= not clk_cfg after T_CFG / 2 when not done;
   process
   begin
      wait for PH_DR * 1 ns;
      while not done loop
         clk_dr <= '1';
         wait for T_DR / 2;
         clk_dr <= '0';
         wait for T_DR / 2;
      end loop;
      wait;
   end process;
   -- dr_word on clk_dr: 0 until frame 1, then DR_VAL
   process (clk_dr)
   begin
      if rising_edge(clk_dr) then
         if frame >= 1 then
            dr_word <= DR_VAL;
         end if;
      end if;
   end process;
   process
   begin
      wait for PH_VID * 1 ns;
      while not done loop
         clk_vid <= '1';
         wait for T_VID / 2;
         clk_vid <= '0';
         wait for T_VID / 2;
      end loop;
      wait;
   end process;

   ---------------------------------------------------------------- DUT
   regs : entity work.zn_dbg_regs
      generic map (CLK_HZ => 50000000)
      port map
      (
         clk        => clk_src,
         core_reset => core_reset,
         pc         => pc,
         dat_take   => dat_take,
         dat_addr   => dat_addr,
         wd_fire    => wd_fire,
         wd_kick    => wd_kick,
         ctrl       => ctrl,
         sec_cmd    => sec_cmd,
         rd_idx     => rd_idx,
         rd_word    => rd_word
      );

   ovl : entity work.zn_dbg_overlay
      generic map (X0 => X0, Y0 => Y0, DR_ROW => DR, SIM_META_WINDOW => META * 1 ns)
      port map
      (
         clk_cfg  => clk_cfg,
         cfg_en   => cfg_en,
         clk_src  => clk_src,
         src_idx  => rd_idx,
         src_word => rd_word,
         clk_dr   => clk_dr,
         dr_word  => dr_word,
         clk_vid  => clk_vid,
         ce_pix   => ce_pix,
         hres_dbl => dbl_s,
         hb       => hb,
         vb       => vb,
         rgb_in   => rgb_in,
         rgb_out  => rgb_out
      );

   ---------------------------------------------------------------- capture-side stimulus (clk_src)
   stim : process
      procedure tick(n : natural := 1) is
      begin
         for i in 1 to n loop
            wait until rising_edge(clk_src);
         end loop;
      end procedure;
      procedure pulse(signal s : out std_logic) is
      begin
         s <= '1';
         tick;
         s <= '0';
      end procedure;
      procedure access_data(a : unsigned(31 downto 0)) is
      begin
         dat_addr <= a;
         dat_take <= '1';
         tick;
         dat_take <= '0';
      end procedure;
      procedure reset_burst(n : natural) is
      begin
         for i in 1 to n loop
            pulse(core_reset);
            tick(15);
         end loop;
      end procedure;
   begin
      wait for PH_SRC * 1 ns;
      tick(50);
      reset_burst(3);                 -- power-on reset: other
      pc <= x"80012ABC";
      access_data(x"1F801044");
      access_data(x"80040000");
      ctrl <= x"E8";
      for i in 1 to 5 loop
         pulse(sec_cmd);
         tick(3);
      end loop;
      tick(150000);                   -- 3 ms: the power-on burst has ended
      pulse(wd_fire);                 -- snapshot: 80012ABC, 80040000, 1044, ms 3
      tick(100);
      reset_burst(4);                 -- watchdog reset
      pc <= x"8003F00C";
      access_data(x"BF801814");
      access_data(x"80123456");
      stim_done <= true;
      wait;
   end process;

   ---------------------------------------------------------------- video timing (clk_vid)
   video : process (clk_vid)
      variable div_c : integer := 0;
      variable hc    : integer := 0;
      variable vc    : integer := 0;
      variable r, g  : integer;
   begin
      if rising_edge(clk_vid) then
         ce_pix <= '0';
         if div_c = DIV - 1 then
            div_c := 0;
            ce_pix <= '1';
         else
            div_c := div_c + 1;
         end if;
         if ce_pix = '1' then
            -- the values for this dot (registered on ce like video_aspect)
            if hc < HA and vc < VA then
               hb <= '0';
               vb <= '0';
               r := (hc * 255) / HA;
               g := (vc * 255) / VA;
               rgb_in <= std_logic_vector(to_unsigned(64, 8)) & std_logic_vector(to_unsigned(g, 8)) & std_logic_vector(to_unsigned(r, 8));
            else
               hb <= '1' when hc >= HA else '0';
               vb <= '1' when vc >= VA else '0';
               rgb_in <= (others => '0');
            end if;
            if hc = HA + HBL - 1 then
               hc := 0;
               if vc = VA + VBL - 1 then
                  vc := 0;
                  frame <= frame + 1;
               else
                  vc := vc + 1;
               end if;
            else
               hc := hc + 1;
            end if;
         end if;
      end if;
   end process;

   -- option on from frame 2
   process (frame)
   begin
      if frame = 2 then
         cfg_en <= '1';
      end if;
   end process;

   ---------------------------------------------------------------- checks and capture
   check : process (clk_vid)
      file     f       : text;
      variable l       : line;
      variable opened  : boolean := false;
      variable x, y    : integer := 0;
      variable off_cmp : natural := 0;
      variable off_bad : natural := 0;
      variable on_cmp  : natural := 0;
      variable on_bad  : natural := 0;
      variable changed : natural := 0;
      variable xs, ys  : integer;
      variable in_box  : boolean;
      variable sc      : integer;
   begin
      if rising_edge(clk_vid) then
         -- option off: identical on every clk_vid edge
         if frame < 2 then
            off_cmp := off_cmp + 1;
            if rgb_out /= rgb_in then
               off_bad := off_bad + 1;
            end if;
         end if;

         if ce_pix = '1' and frame >= 3 and frame <= CAPTURE then
            -- raster position of the sampled dot from hb/vb
            if hb = '0' and vb = '0' then
               -- outside the box (with the 3-dot pipeline shift) the video passes
               sc := 1;
               if DBL = 1 then
                  sc := 2;
               end if;
               in_box := (x >= sc * (X0 - 2) and x < sc * (X0 + 98) + 3 + sc and
                          y >= Y0 - 2 and y < Y0 + 8 * NROWS + 2);
               on_cmp := on_cmp + 1;
               if rgb_out /= rgb_in then
                  changed := changed + 1;
                  if not in_box then
                     on_bad := on_bad + 1;
                  end if;
               end if;
               if frame = CAPTURE then
                  if not opened then
                     file_open(f, OUTF, write_mode);
                     write(l, string'("P3"));
                     writeline(f, l);
                     write(l, integer'image(HA) & " " & integer'image(VA));
                     writeline(f, l);
                     write(l, string'("255"));
                     writeline(f, l);
                     opened := true;
                  end if;
                  write(l, integer'image(to_integer(unsigned(rgb_out(7 downto 0)))) & " " &
                           integer'image(to_integer(unsigned(rgb_out(15 downto 8)))) & " " &
                           integer'image(to_integer(unsigned(rgb_out(23 downto 16)))));
                  writeline(f, l);
               end if;
               x := x + 1;
            else
               on_cmp := on_cmp + 1;
               if rgb_out /= rgb_in then
                  on_bad := on_bad + 1;
               end if;
               if hb = '1' and x > 0 then
                  x := 0;
                  y := y + 1;
               end if;
               if vb = '1' then
                  x := 0;
                  y := 0;
               end if;
            end if;
         end if;

         if frame = CAPTURE + 1 and not done then
            file_close(f);
            report "off: " & integer'image(off_cmp) & " clk_vid edges compared, " & integer'image(off_bad) & " differ";
            report "on: " & integer'image(on_cmp) & " dots compared, " & integer'image(changed) & " changed by the overlay, " &
                   integer'image(on_bad) & " changed outside the box or in blanking";
            if off_bad /= 0 or on_bad /= 0 or changed = 0 or not stim_done then
               report "tb_zn_dbg_overlay FAILED" severity failure;
            end if;
            report "tb_zn_dbg_overlay: PASS (" & OUTF & " written)";
            done <= true;
         end if;
      end if;
   end process;

end architecture;
