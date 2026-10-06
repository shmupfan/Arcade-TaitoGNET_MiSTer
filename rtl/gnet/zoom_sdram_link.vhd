-- Temporary SDRAM path for the Taito Zoom board's flash area reads (PSX.sv
-- macro GNET_ZOOM_SDRAM, first test revision GNET_Z1_ZOOM;
-- docs/zoom_board_design.md 14). The release path is the DDR3 arbiter
-- (macro GNET_DDR3_ARB, branch ddr3-arb-int), which takes the same zoom_m_*
-- wires; this block is only for builds where the flash area is in SDRAM
-- alone (MRA index 3 and gnet_fc's flash storage write SDRAM 0x1000000 to
-- 0x19FFFFF, docs/zn2_layer_design.md 13.4).
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
-- zoom_board's 64-bit line port (clk1x; program cache misses and ZSG-2 wave
-- fetches through zoom_memarb) to SDRAM channel 3, which runs on clk_cpu
-- with the CPU group (zn2_ch3_arb port c). Signal prefixes: c_ clk_cpu,
-- p_ clk1x. Built only from rtl/gnet/cdc (cdc_tx_* sources, cdc.sdc):
--   one cdc_handshake per line carrying the line number; on the CPU side two
--   32-bit reads (byte address FLASH_BASE + 8 x line, then + 4) and the 64
--   bits back as {word at + 4, word at + 0}, the layout zoom_board expects
--   (flash byte 8L in bits 7:0). One line at a time: p_m_ready is low while a
--   line is open. Reads always carry byte enables 1111 (PSX.sv ties port c's
--   byte enables): sdram.sv puts ~be[1:0] on DQMH:DQML with the READ command
--   and the chip masks read data two clocks later, so a partial mask would
--   blank lanes (commit 13b6e1d, docs/zn2_layer_design.md 18.5).
--
-- Resets: the crossing is not reset (as rtl/gnet/zn2_cdc.vhd). The CPU side
-- always completes both reads and answers; the clk1x side drops the answer
-- to a line requested before a zoom_board reset (p_board_rst), so
-- zoom_memarb never sees a response it did not ask for. All registers start
-- from their declared values at configuration.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity zoom_sdram_link is
   generic
   (
      FLASH_BASE      : integer := 16#1000000#;   -- SDRAM byte address of the flash area (U30 at 0)
      SIM_META_WINDOW : time := 0 ns
   );
   port
   (
      clk_cpu          : in  std_logic;
      clk1x            : in  std_logic;
      p_board_rst      : in  std_logic;   -- zoom_board's reset (clk1x)

      -- zoom_board m_* (clk1x)
      p_m_req          : in  std_logic;
      p_m_line         : in  std_logic_vector(20 downto 0);
      p_m_ready        : out std_logic;
      p_m_rvalid       : out std_logic;
      p_m_rdata        : out std_logic_vector(63 downto 0);

      -- zn2_ch3_arb port c (clk_cpu): request pulse, fields held until the
      -- next request, one ready pulse with the data
      c_fl_req         : out std_logic;
      c_fl_addr        : out std_logic_vector(26 downto 0);
      c_fl_ready       : in  std_logic;
      c_fl_dout        : in  std_logic_vector(31 downto 0)
   );
end entity;

architecture rtl of zoom_sdram_link is

   -- clk1x side
   signal l_busy        : std_logic;
   signal l_done        : std_logic;
   signal l_start       : std_logic;
   signal l_stale       : std_logic := '0';

   -- CPU side
   type t_fstate is (F_IDLE, F_W0, F_W1);
   signal fs            : t_fstate := F_IDLE;
   signal f_valid       : std_logic;
   signal f_line        : std_logic_vector(20 downto 0);
   signal f_lo          : std_logic_vector(31 downto 0) := (others => '0');
   signal f_rsp         : std_logic_vector(63 downto 0) := (others => '0');
   signal f_ack         : std_logic := '0';
   signal f_req_r       : std_logic := '0';
   signal f_addr_r      : unsigned(26 downto 0) := (others => '0');

   constant BASE        : unsigned(26 downto 0) := to_unsigned(FLASH_BASE, 27);

begin

   ---------------------------------------------------------------- clk1x side
   l_start    <= p_m_req and (not l_busy) and (not p_board_rst);
   p_m_ready  <= (not l_busy) and (not p_board_rst);
   p_m_rvalid <= l_done and (not l_stale);

   process (clk1x)
   begin
      if rising_edge(clk1x) then
         if (l_start = '1') then
            l_stale <= '0';
         elsif (l_busy = '1' and p_board_rst = '1') then
            l_stale <= '1';                      -- requested before this reset: answer dropped
         end if;
      end if;
   end process;

   u_line : entity work.cdc_handshake
      generic map (REQ_W => 21, RSP_W => 64, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 305)
      port map (
         src_clk      => clk1x,
         src_start    => l_start,
         src_req_data => p_m_line,
         src_busy     => l_busy,
         src_done     => l_done,
         src_rsp_data => p_m_rdata,
         dst_clk      => clk_cpu,
         dst_valid    => f_valid,
         dst_req_data => f_line,
         dst_pending  => open,
         dst_ack      => f_ack,
         dst_rsp_data => f_rsp);

   ---------------------------------------------------------------- CPU side
   process (clk_cpu)
   begin
      if rising_edge(clk_cpu) then
         f_req_r <= '0';
         f_ack   <= '0';
         case fs is
            when F_IDLE =>
               if (f_valid = '1') then
                  f_addr_r <= BASE + shift_left(resize(unsigned(f_line), 27), 3);
                  f_req_r  <= '1';
                  fs       <= F_W0;
               end if;

            when F_W0 =>
               if (c_fl_ready = '1') then
                  f_lo     <= c_fl_dout;
                  f_addr_r <= f_addr_r + 4;
                  f_req_r  <= '1';
                  fs       <= F_W1;
               end if;

            when F_W1 =>
               if (c_fl_ready = '1') then
                  f_rsp <= c_fl_dout & f_lo;
                  f_ack <= '1';
                  fs    <= F_IDLE;
               end if;
         end case;
      end if;
   end process;

   c_fl_req  <= f_req_r;
   c_fl_addr <= std_logic_vector(f_addr_r);

end architecture;
