-- G-NET hardware debug overlay, video side (docs/hw_debug_overlay.md).
--
-- Copyright (C) 2026 Lee Foot
--
-- This program is free software; you can redistribute it and/or modify it
-- under the terms of the GNU General Public License as published by the Free
-- Software Foundation; either version 2 of the License, or (at your option)
-- any later version. This program is distributed in the hope that it will be
-- useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
-- Public License for more details.
--
-- Draws the ten 32-bit words of rtl/gnet/zn_dbg_regs.vhd (plus, with
-- DR_ROW = 1, the DDR3 arbiter status word) as hex text: ten (eleven)
-- rows of 12 cells (2-letter label, space, 4 hex digits, space, 4 hex
-- digits), 8x8 cells with 5x7 glyphs, white on a black box, X0 dots right of
-- the start of the active line and Y0 lines below the first active line.
-- At 512 and 640 dots per line (hres_dbl = 1) each font pixel is two dots
-- wide. Pixel steps follow ce_pix only; no clock or pixel rate is added.
--
-- Clocks and crossings (rtl/gnet/cdc naming):
--   clk_cfg  the OSD status bit, registered into cdc_tx_en, cdc_sync into
--            clk_vid
--   clk_src  the capture block's clock: a cdc_handshake (source clk_vid,
--            destination clk_src) carries the word index out (src_idx, held)
--            and the word back (src_word, combinational from zn_dbg_regs,
--            registered in the handshake's cdc_tx_rsp). The video side asks
--            for words 0 to 9 in turn during vertical blanking and writes
--            each answer into a 16 x 32 RAM on clk_vid; a full refresh takes
--            ten round trips (about 2 us), so each frame shows the values of
--            its own vertical blanking.
--   clk_vid  counters, RAM read, font ROM and the mixer, all stepped by
--            ce_pix
--   clk_dr   (DR_ROW = 1 only) the DDR3 arbiter's clock (clk_2x): a second
--            cdc_handshake (source clk_vid, destination clk_dr) fetches
--            dr_word, the arbiter status word, in vertical blanking as the
--            other words, and shows it as an eleventh row "DR". Its answer
--            stays in the handshake's capture register (no RAM write port
--            is added). With DR_ROW = 0 nothing of it is built and the box
--            keeps its ten rows.
--
-- With the option off (en_v = 0) rgb_out is rgb_in for every pixel: the
-- mixer selects rgb_in whenever the registered show flag is 0, and show is
-- 0 while en_v is 0. During blanking (hb or vb) rgb_in is passed as well,
-- so blanking keeps its level.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.cdc_pkg.all;

entity zn_dbg_overlay is
   generic
   (
      X0              : integer  := 16;   -- text origin in font pixels from the active line start
      Y0              : integer  := 16;   -- text origin in lines from the first active line
      DR_ROW          : integer  := 0;    -- 1: eleventh row "DR" from dr_word (clk_dr)
      SIM_META_WINDOW : time     := 0 ns;
      SIM_SEED        : positive := 7
   );
   port
   (
      clk_cfg  : in  std_logic;
      cfg_en   : in  std_logic;                        -- OSD "Debug overlay" (clk_cfg)

      clk_src  : in  std_logic;
      src_idx  : out std_logic_vector(3 downto 0);     -- clk_src, to zn_dbg_regs rd_idx
      src_word : in  std_logic_vector(31 downto 0);    -- clk_src, from zn_dbg_regs rd_word

      clk_dr   : in  std_logic := '0';                  -- DR_ROW = 1: clock of dr_word
      dr_word  : in  std_logic_vector(31 downto 0) := (others => '0');   -- clk_dr

      clk_vid  : in  std_logic;
      ce_pix   : in  std_logic;
      hres_dbl : in  std_logic;                        -- 1: 512 or 640 dots per line
      hb       : in  std_logic;
      vb       : in  std_logic;
      rgb_in   : in  std_logic_vector(23 downto 0);
      rgb_out  : out std_logic_vector(23 downto 0)
   );
end entity;

architecture arch of zn_dbg_overlay is

   constant COLS   : integer := 12;
   constant NWORDS : integer := 10;               -- words fetched from clk_src
   constant ROWS   : integer := NWORDS + DR_ROW;  -- rows drawn
   constant TW     : integer := COLS * 8;
   constant TH     : integer := ROWS * 8;
   constant SPACE  : unsigned(4 downto 0) := to_unsigned(16, 5);

   -- tools/gnet/dbg_font.py: codes 0-15 hex digits, 16 space, 17-24 P I O M S W R X
   type font_t is array (0 to 255) of std_logic_vector(7 downto 0);
   constant FONT : font_t :=
   (
      x"38", x"44", x"4C", x"54", x"64", x"44", x"38", x"00",   --  0 '0'
      x"10", x"30", x"10", x"10", x"10", x"10", x"38", x"00",   --  1 '1'
      x"38", x"44", x"04", x"08", x"10", x"20", x"7C", x"00",   --  2 '2'
      x"7C", x"08", x"10", x"08", x"04", x"44", x"38", x"00",   --  3 '3'
      x"08", x"18", x"28", x"48", x"7C", x"08", x"08", x"00",   --  4 '4'
      x"7C", x"40", x"78", x"04", x"04", x"44", x"38", x"00",   --  5 '5'
      x"18", x"20", x"40", x"78", x"44", x"44", x"38", x"00",   --  6 '6'
      x"7C", x"04", x"08", x"10", x"20", x"20", x"20", x"00",   --  7 '7'
      x"38", x"44", x"44", x"38", x"44", x"44", x"38", x"00",   --  8 '8'
      x"38", x"44", x"44", x"3C", x"04", x"08", x"30", x"00",   --  9 '9'
      x"38", x"44", x"44", x"7C", x"44", x"44", x"44", x"00",   -- 10 'A'
      x"78", x"44", x"44", x"78", x"44", x"44", x"78", x"00",   -- 11 'B'
      x"38", x"44", x"40", x"40", x"40", x"44", x"38", x"00",   -- 12 'C'
      x"70", x"48", x"44", x"44", x"44", x"48", x"70", x"00",   -- 13 'D'
      x"7C", x"40", x"40", x"78", x"40", x"40", x"7C", x"00",   -- 14 'E'
      x"7C", x"40", x"40", x"78", x"40", x"40", x"40", x"00",   -- 15 'F'
      x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",   -- 16 ' '
      x"78", x"44", x"44", x"78", x"40", x"40", x"40", x"00",   -- 17 'P'
      x"38", x"10", x"10", x"10", x"10", x"10", x"38", x"00",   -- 18 'I'
      x"38", x"44", x"44", x"44", x"44", x"44", x"38", x"00",   -- 19 'O'
      x"44", x"6C", x"54", x"54", x"44", x"44", x"44", x"00",   -- 20 'M'
      x"3C", x"40", x"40", x"38", x"04", x"04", x"78", x"00",   -- 21 'S'
      x"44", x"44", x"44", x"54", x"54", x"54", x"28", x"00",   -- 22 'W'
      x"78", x"44", x"44", x"78", x"50", x"48", x"44", x"00",   -- 23 'R'
      x"44", x"44", x"28", x"10", x"28", x"44", x"44", x"00",   -- 24 'X'
      x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",   -- 25 unused
      x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",   -- 26 unused
      x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",   -- 27 unused
      x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",   -- 28 unused
      x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",   -- 29 unused
      x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00",   -- 30 unused
      x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00"    -- 31 unused
   );

   -- labels, two codes per row: PC DA IO MS WD RS XP XD XI XM (DR)
   type label_t is array (0 to 15) of unsigned(9 downto 0);
   constant LABELS : label_t :=
   (
      0      => to_unsigned(17 * 32 + 12, 10),   -- P C
      1      => to_unsigned(13 * 32 + 10, 10),   -- D A
      2      => to_unsigned(18 * 32 + 19, 10),   -- I O
      3      => to_unsigned(20 * 32 + 21, 10),   -- M S
      4      => to_unsigned(22 * 32 + 13, 10),   -- W D
      5      => to_unsigned(23 * 32 + 21, 10),   -- R S
      6      => to_unsigned(24 * 32 + 17, 10),   -- X P
      7      => to_unsigned(24 * 32 + 13, 10),   -- X D
      8      => to_unsigned(24 * 32 + 18, 10),   -- X I
      9      => to_unsigned(24 * 32 + 20, 10),   -- X M
      10     => to_unsigned(13 * 32 + 23, 10),   -- D R (drawn with DR_ROW = 1 only)
      others => to_unsigned(16 * 32 + 16, 10)
   );

   -- configuration
   signal cdc_tx_en  : std_logic := '0';
   signal en_v       : std_logic_vector(0 downto 0);

   attribute altera_attribute : string;
   attribute altera_attribute of cdc_tx_en : signal is CDC_ATTR_KEEP;

   -- word fetch
   signal hs_start   : std_logic;
   signal hs_busy    : std_logic;
   signal hs_done    : std_logic;
   signal hs_rsp     : std_logic_vector(31 downto 0);
   signal fetch_idx  : unsigned(3 downto 0) := (others => '0');

   type words_t is array (0 to 15) of std_logic_vector(31 downto 0);
   signal words      : words_t := (others => (others => '0'));
   signal rd_row     : unsigned(3 downto 0);
   signal q          : std_logic_vector(31 downto 0);
   signal q_ram      : std_logic_vector(31 downto 0) := (others => '0');

   -- DR row (DR_ROW = 1)
   signal dr_rsp     : std_logic_vector(31 downto 0) := (others => '0');
   signal dr_sel     : std_logic := '0';

   -- raster position
   signal hcnt       : unsigned(10 downto 0) := (others => '0');
   signal vcnt       : unsigned(9 downto 0)  := (others => '0');
   signal hb_d       : std_logic := '1';

   signal x          : unsigned(10 downto 0);
   signal y          : unsigned(9 downto 0);
   signal rx         : unsigned(10 downto 0);
   signal ry         : unsigned(9 downto 0);
   signal in_text    : std_logic;
   signal in_box     : std_logic;

   -- pipeline (ce_pix)
   signal col1       : unsigned(3 downto 0) := (others => '0');
   signal row1       : unsigned(3 downto 0) := (others => '0');
   signal gx1, gy1   : unsigned(2 downto 0) := (others => '0');
   signal text1      : std_logic := '0';
   signal box1       : std_logic := '0';
   signal code       : unsigned(4 downto 0);
   signal font_q     : std_logic_vector(7 downto 0) := (others => '0');
   signal gx2        : unsigned(2 downto 0) := (others => '0');
   signal text2      : std_logic := '0';
   signal box2       : std_logic := '0';
   signal show       : std_logic := '0';
   signal pix        : std_logic := '0';

begin

   assert X0 >= 2 and Y0 >= 2 report "zn_dbg_overlay: X0 and Y0 must be at least 2 (box border)" severity failure;

   ---------------------------------------------------------------- config
   process (clk_cfg)
   begin
      if rising_edge(clk_cfg) then
         cdc_tx_en <= cfg_en;
      end if;
   end process;

   u_en : entity work.cdc_sync
      generic map (WIDTH => 1, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => SIM_SEED)
      port map (clk => clk_vid, d(0) => cdc_tx_en, q => en_v);

   ---------------------------------------------------------------- fetch
   -- one request at a time; the cycle with src_done writes the answer and
   -- moves to the next index, whose request starts one cycle later.
   -- Requests start only in vertical blanking, so every frame shows one set
   -- of values (no digit changes between the lines of a glyph). Ten round
   -- trips take about 2 us of the about 1 ms of blanking; a request still in
   -- flight when blanking ends lands well before the first text line.
   hs_start <= vb and (not hs_busy) and (not hs_done);

   u_hs : entity work.cdc_handshake
      generic map (REQ_W => 4, RSP_W => 32, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => SIM_SEED + 1)
      port map
      (
         src_clk      => clk_vid,
         src_start    => hs_start,
         src_req_data => std_logic_vector(fetch_idx),
         src_busy     => hs_busy,
         src_done     => hs_done,
         src_rsp_data => hs_rsp,
         dst_clk      => clk_src,
         dst_valid    => open,
         dst_req_data => src_idx,
         dst_pending  => open,
         dst_ack      => '1',
         dst_rsp_data => src_word
      );

   -- word RAM: written by the fetch, read by text row; the row changes only
   -- between lines, so the one-clock read latency never reaches a pixel
   process (clk_vid)
   begin
      if rising_edge(clk_vid) then
         if (hs_done = '1') then
            words(to_integer(fetch_idx)) <= hs_rsp;
            if (fetch_idx = to_unsigned(NWORDS - 1, 4)) then
               fetch_idx <= (others => '0');
            else
               fetch_idx <= fetch_idx + 1;
            end if;
         end if;
         q_ram <= words(to_integer(rd_row));
         if (rd_row = to_unsigned(NWORDS, 4)) then
            dr_sel <= '1';
         else
            dr_sel <= '0';
         end if;
      end if;
   end process;

   q <= dr_rsp when (DR_ROW = 1 and dr_sel = '1') else q_ram;

   -- DR row: its own handshake into clk_dr, one word, asked again as soon
   -- as the previous answer is in, during vertical blanking only (as above)
   g_dr : if DR_ROW = 1 generate
      signal dr_start : std_logic;
      signal dr_busy  : std_logic;
      signal dr_done  : std_logic;
   begin
      dr_start <= vb and (not dr_busy) and (not dr_done);

      u_hs_dr : entity work.cdc_handshake
         generic map (REQ_W => 1, RSP_W => 32, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => SIM_SEED + 2)
         port map
         (
            src_clk      => clk_vid,
            src_start    => dr_start,
            src_req_data => "0",
            src_busy     => dr_busy,
            src_done     => dr_done,
            src_rsp_data => dr_rsp,
            dst_clk      => clk_dr,
            dst_valid    => open,
            dst_req_data => open,
            dst_pending  => open,
            dst_ack      => '1',
            dst_rsp_data => dr_word
         );
   end generate;

   ---------------------------------------------------------------- raster
   -- hcnt: dots since the active line started; vcnt: active lines since
   -- vertical blanking ended (incremented as each active line ends)
   process (clk_vid)
   begin
      if rising_edge(clk_vid) then
         if (ce_pix = '1') then
            hb_d <= hb;
            if (hb = '1') then
               hcnt <= (others => '0');
            elsif (hcnt /= to_unsigned(2047, 11)) then
               hcnt <= hcnt + 1;
            end if;
            if (vb = '1') then
               vcnt <= (others => '0');
            elsif (hb = '1' and hb_d = '0' and vcnt /= to_unsigned(1023, 10)) then
               vcnt <= vcnt + 1;
            end if;
         end if;
      end if;
   end process;

   x  <= ('0' & hcnt(10 downto 1)) when (hres_dbl = '1') else hcnt;
   y  <= vcnt;
   rx <= x - to_unsigned(X0, 11);
   ry <= y - to_unsigned(Y0, 10);

   in_text <= '1' when (x >= to_unsigned(X0, 11) and x < to_unsigned(X0 + TW, 11) and
                        y >= to_unsigned(Y0, 10) and y < to_unsigned(Y0 + TH, 10)) else '0';
   in_box  <= '1' when (x >= to_unsigned(X0 - 2, 11) and x < to_unsigned(X0 + TW + 2, 11) and
                        y >= to_unsigned(Y0 - 2, 10) and y < to_unsigned(Y0 + TH + 2, 10)) else '0';

   rd_row <= ry(6 downto 3);

   ---------------------------------------------------------------- text
   process (col1, row1, q)
      variable lab : unsigned(9 downto 0);
   begin
      lab := LABELS(to_integer(row1));
      case (to_integer(col1)) is
         when 0      => code <= lab(9 downto 5);
         when 1      => code <= lab(4 downto 0);
         when 3      => code <= unsigned('0' & q(31 downto 28));
         when 4      => code <= unsigned('0' & q(27 downto 24));
         when 5      => code <= unsigned('0' & q(23 downto 20));
         when 6      => code <= unsigned('0' & q(19 downto 16));
         when 8      => code <= unsigned('0' & q(15 downto 12));
         when 9      => code <= unsigned('0' & q(11 downto 8));
         when 10     => code <= unsigned('0' & q(7 downto 4));
         when 11     => code <= unsigned('0' & q(3 downto 0));
         when others => code <= SPACE;
      end case;
   end process;

   process (clk_vid)
   begin
      if rising_edge(clk_vid) then
         if (ce_pix = '1') then
            -- stage 1: cell and glyph position
            col1  <= rx(6 downto 3);
            row1  <= ry(6 downto 3);
            gx1   <= rx(2 downto 0);
            gy1   <= ry(2 downto 0);
            text1 <= in_text;
            box1  <= in_box;
            -- stage 2: glyph row
            font_q <= FONT(to_integer(code & gy1));
            gx2    <= gx1;
            text2  <= text1;
            box2   <= box1;
            -- stage 3: pixel
            show <= en_v(0) and box2;
            pix  <= text2 and font_q(7 - to_integer(gx2));
         end if;
      end if;
   end process;

   ---------------------------------------------------------------- mixer
   rgb_out <= (others => pix) when (show = '1' and hb = '0' and vb = '0') else rgb_in;

end architecture;
