-- Crossings between the CPU group (clk_cpu) and the Taito Zoom board, which
-- runs on the PS1 group's clk1x and clk2x (psx_top ZOOM_BOARD = 1 with
-- CPU_CLK_SPLIT = 1; docs/zoom_board_design.md 14).
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
-- Signal prefixes: c_ clk_cpu, p_ clk1x. Built only from rtl/gnet/cdc
-- (cdc_tx_* sources, cdc.sdc). The Zoom board itself has no path to
-- clk_cpu: its host side (hclk) is clk1x here, so zoom_board's mailbox RAM,
-- doorbell toggle and gain words stay inside the PS1 group (clk1x and clk2x
-- come from one PLL and are timed as synchronous clocks).
--
--   Z1  host port: zn2_board's zm_* (main CPU at 0x1FB80000, 0x1FBA0000,
--       0x1FBC0000, 0x1FBE0000-0x1FBE01FF) to zoom_board's h_*: one
--       cdc_handshake carrying we, address, byte enables and write data,
--       the 32-bit read word back. The CPU side keeps one request open (the
--       bus waits for zn_ack); the clk1x side gives zoom_board a one-cycle
--       h_req and returns its h_ack and h_rdata. Addresses zoom_board does
--       not decode, and requests that meet the board's reset, answer 0 on the
--       clk1x side so the bus never waits forever.
--   Z2  zoom reset: gnet_ctrl's control bit 4 (1 = Zoom held), registered
--       into cdc_tx_zrst and through cdc_sync (INIT 1, so the Zoom starts
--       held) to clk1x. zoom_board then synchronises it into its own clocks
--       (synchronous paths).
--   The flash area reads (zoom_board's m_* line port) are not here: they
--   leave psx_top on clk1x as zoom_m_* (docs/zoom_board_design.md 14) for
--   the DDR3 arbiter (macro GNET_DDR3_ARB) or, in the first test build, for
--   rtl/gnet/zoom_sdram_link.vhd (macro GNET_ZOOM_SDRAM).
--
-- Resets: no crossing is reset (as rtl/gnet/zn2_cdc.vhd). Each side finishes
-- what it started. The CPU side of Z1 drops the answer to a request sent
-- before zn2_board's reset (c_board_rst) and starts a request that arrives
-- while such an answer is still outstanding once it is in. All registers
-- start from their declared values at configuration.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cdc_pkg.all;

entity zoom_cdc is
   generic
   (
      SIM_META_WINDOW : time := 0 ns
   );
   port
   (
      clk_cpu          : in  std_logic;
      clk1x            : in  std_logic;

      c_board_rst      : in  std_logic;   -- zn2_board's reset (psx_top reset_intern, CPU group)
      p_board_rst      : in  std_logic;   -- zoom_board's reset (psx_top reset_intern_p, clk1x)

      -- Z1, CPU side (zn2_board zm_*)
      c_zm_req         : in  std_logic;
      c_zm_we          : in  std_logic;
      c_zm_addr        : in  unsigned(23 downto 0);
      c_zm_be          : in  std_logic_vector(3 downto 0);
      c_zm_wdata       : in  std_logic_vector(31 downto 0);
      c_zm_ack         : out std_logic;
      c_zm_rdata       : out std_logic_vector(31 downto 0);
      -- Z1, Zoom side (zoom_board h_*, hclk = clk1x)
      p_h_req          : out std_logic;
      p_h_we           : out std_logic;
      p_h_addr         : out std_logic_vector(23 downto 0);
      p_h_be           : out std_logic_vector(3 downto 0);
      p_h_wdata        : out std_logic_vector(31 downto 0);
      p_h_ack          : in  std_logic;
      p_h_rdata        : in  std_logic_vector(31 downto 0);
      p_h_hit          : in  std_logic;

      -- Z2
      c_zoom_reset     : in  std_logic;
      p_zoom_reset     : out std_logic
   );
end entity;

architecture rtl of zoom_cdc is

   -- Z2 crossing source (cdc.sdc)
   signal cdc_tx_zrst   : std_logic := '1';
   attribute altera_attribute : string;
   attribute altera_attribute of cdc_tx_zrst : signal is CDC_ATTR_KEEP;
   signal zrst_s        : std_logic_vector(0 downto 0);

   -- Z1, CPU side
   type t_cstate is (C_IDLE, C_WAIT);
   signal cs            : t_cstate := C_IDLE;
   signal c_pend        : std_logic := '0';
   signal c_pdata       : std_logic_vector(60 downto 0) := (others => '0');
   signal c_stale       : std_logic := '0';
   signal c_start       : std_logic;
   signal c_busy        : std_logic;
   signal c_done        : std_logic;
   signal c_rsp         : std_logic_vector(31 downto 0);
   signal c_ack_r       : std_logic := '0';
   signal c_rdata_r     : std_logic_vector(31 downto 0) := (others => '0');

   -- Z1, clk1x side
   signal p_valid       : std_logic;
   signal p_req_data    : std_logic_vector(60 downto 0);
   signal p_wait        : std_logic := '0';
   signal p_zero        : std_logic := '0';
   signal p_ack         : std_logic;
   signal p_rsp         : std_logic_vector(31 downto 0);

begin

   ---------------------------------------------------------------- Z2
   process (clk_cpu)
   begin
      if rising_edge(clk_cpu) then
         cdc_tx_zrst <= c_zoom_reset;
      end if;
   end process;

   u_zrst : entity work.cdc_sync
      generic map (WIDTH => 1, INIT => '1', SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 301)
      port map (clk => clk1x, d(0) => cdc_tx_zrst, q => zrst_s);

   p_zoom_reset <= zrst_s(0);

   ---------------------------------------------------------------- Z1, CPU side
   -- not in reset: a request still pending when zn2_board's reset comes is dropped with the bus
   c_start <= '1' when (cs = C_IDLE and c_pend = '1' and c_busy = '0' and c_board_rst = '0') else '0';

   process (clk_cpu)
   begin
      if rising_edge(clk_cpu) then
         c_ack_r <= '0';

         if (c_start = '1') then
            c_pend <= '0';
         end if;
         if (c_board_rst = '1') then
            c_pend <= '0';                       -- not sent yet: dropped with the bus
         elsif (c_zm_req = '1') then
            c_pend  <= '1';
            c_pdata <= c_zm_we & std_logic_vector(c_zm_addr) & c_zm_be & c_zm_wdata;
         end if;

         case cs is
            when C_IDLE =>
               if (c_start = '1') then
                  c_stale <= '0';
                  cs      <= C_WAIT;
               end if;

            when C_WAIT =>
               if (c_board_rst = '1') then
                  c_stale <= '1';
               end if;
               if (c_done = '1') then
                  cs <= C_IDLE;
                  if (c_stale = '0' and c_board_rst = '0') then
                     c_ack_r   <= '1';
                     c_rdata_r <= c_rsp;
                  end if;                        -- else: answer to a request from before a reset, dropped
               end if;
         end case;
      end if;
   end process;

   c_zm_ack   <= c_ack_r;
   c_zm_rdata <= c_rdata_r;

   u_host : entity work.cdc_handshake
      generic map (REQ_W => 61, RSP_W => 32, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 303)
      port map (
         src_clk      => clk_cpu,
         src_start    => c_start,
         src_req_data => c_pdata,
         src_busy     => c_busy,
         src_done     => c_done,
         src_rsp_data => c_rsp,
         dst_clk      => clk1x,
         dst_valid    => p_valid,
         dst_req_data => p_req_data,
         dst_pending  => open,
         dst_ack      => p_ack,
         dst_rsp_data => p_rsp);

   ---------------------------------------------------------------- Z1, clk1x side
   -- dst_req_data is held until the next dst_valid, so the h_* fields can be
   -- taken from it directly; h_hit is zoom_host's decode of p_h_addr.
   p_h_we    <= p_req_data(60);
   p_h_addr  <= p_req_data(59 downto 36);
   p_h_be    <= p_req_data(35 downto 32);
   p_h_wdata <= p_req_data(31 downto 0);
   p_h_req   <= p_valid and (not p_board_rst) and p_h_hit;

   process (clk1x)
   begin
      if rising_edge(clk1x) then
         p_zero <= '0';
         if (p_valid = '1') then
            if (p_board_rst = '1' or p_h_hit = '0') then
               p_zero <= '1';
            else
               p_wait <= '1';
            end if;
         elsif (p_wait = '1') then
            if (p_h_ack = '1') then
               p_wait <= '0';
            elsif (p_board_rst = '1') then
               p_wait <= '0';                    -- zoom_host drops a read in reset: answer 0
               p_zero <= '1';
            end if;
         end if;
      end if;
   end process;

   p_ack <= (p_wait and p_h_ack) or p_zero;
   p_rsp <= p_h_rdata when (p_wait = '1') else (others => '0');

end architecture;
