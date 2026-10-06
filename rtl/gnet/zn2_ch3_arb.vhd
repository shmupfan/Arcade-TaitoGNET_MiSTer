-- SDRAM channel 3 shared by up to three requesters on clk_cpu (PSX.sv, GNET_ZN2 with
-- GNET_CPU50; docs/r1_cpu_domain_design.md, section on the ZN-2 layer in the
-- CPU group).
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
--   a: the downloads (BIOS, flash images), from the clk_1x side through
--      PSX.sv's ch3 cdc_handshake (dst_valid pulse, data held until the next
--      dst_valid, answered by a_ready)
--   b: zn2_board's flash storage port (fl_req pulse, fields held until the
--      next request, answered by fl_ready)
--   c: the Taito Zoom board's flash area reads (rtl/gnet/zoom_cdc.vhd, two
--      32-bit reads per 64-bit line, byte enables 1111; same protocol as b).
--      Unused (c_req = '0') in builds without the Zoom.
-- All are pulse requesters that wait for their answer, so each has at most
-- one request open. One request goes to sdram.sv at a time: the fields are
-- registered and held until ch3_ready, which sdram.sv needs (it copies
-- ch3_addr and the others on every fast clock edge and uses the copy when it
-- serves the request). a wins when it waits; b and c take turns when both
-- wait (c_last: c was served last), so neither the glue's flash port nor the
-- Zoom can hold the other off. After each answer one idle
-- cycle passes before the next request is issued, so a ready that lasts up
-- to three cycles (sdram.sv gives one) never completes the next request.
-- clk is sdram.sv's clk_base (clk_cpu); everything here is synchronous.

library IEEE;
use IEEE.std_logic_1164.all;

entity zn2_ch3_arb is
   port
   (
      clk       : in  std_logic;
      -- '1': start no new request (gnet_ddr3_mirror FIFO nearly full);
      -- a request already issued completes
      stall     : in  std_logic := '0';

      a_req     : in  std_logic;
      a_addr    : in  std_logic_vector(26 downto 0);
      a_din     : in  std_logic_vector(31 downto 0);
      a_rnw     : in  std_logic;
      a_be      : in  std_logic_vector(3 downto 0);
      a_ready   : out std_logic := '0';

      b_req     : in  std_logic;
      b_addr    : in  std_logic_vector(26 downto 0);
      b_din     : in  std_logic_vector(31 downto 0);
      b_rnw     : in  std_logic;
      b_be      : in  std_logic_vector(3 downto 0);
      b_ready   : out std_logic := '0';

      c_req     : in  std_logic := '0';
      c_addr    : in  std_logic_vector(26 downto 0) := (others => '0');
      c_din     : in  std_logic_vector(31 downto 0) := (others => '0');
      c_rnw     : in  std_logic := '1';
      c_be      : in  std_logic_vector(3 downto 0) := (others => '1');
      c_ready   : out std_logic := '0';

      ch3_req   : out std_logic := '0';
      ch3_addr  : out std_logic_vector(26 downto 0) := (others => '0');
      ch3_din   : out std_logic_vector(31 downto 0) := (others => '0');
      ch3_rnw   : out std_logic := '1';
      ch3_be    : out std_logic_vector(3 downto 0) := (others => '0');
      ch3_ready : in  std_logic
   );
end entity;

architecture arch of zn2_ch3_arb is

   type t_state is (IDLE, BUSY_A, BUSY_B, BUSY_C, GAP);
   signal state  : t_state := IDLE;
   signal a_pend : std_logic := '0';
   signal b_pend : std_logic := '0';
   signal c_pend : std_logic := '0';
   signal c_last : std_logic := '1';

begin

   process (clk)
   begin
      if rising_edge(clk) then
         ch3_req <= '0';
         a_ready <= '0';
         b_ready <= '0';
         c_ready <= '0';

         if (a_req = '1') then a_pend <= '1'; end if;
         if (b_req = '1') then b_pend <= '1'; end if;
         if (c_req = '1') then c_pend <= '1'; end if;

         case state is
            when IDLE =>
               if (stall = '1') then
                  null;
               elsif (a_pend = '1') then
                  a_pend   <= '0';
                  ch3_addr <= a_addr;
                  ch3_din  <= a_din;
                  ch3_rnw  <= a_rnw;
                  ch3_be   <= a_be;
                  ch3_req  <= '1';
                  state    <= BUSY_A;
               elsif (b_pend = '1' and (c_pend = '0' or c_last = '1')) then
                  b_pend   <= '0';
                  c_last   <= '0';
                  ch3_addr <= b_addr;
                  ch3_din  <= b_din;
                  ch3_rnw  <= b_rnw;
                  ch3_be   <= b_be;
                  ch3_req  <= '1';
                  state    <= BUSY_B;
               elsif (c_pend = '1') then
                  c_pend   <= '0';
                  c_last   <= '1';
                  ch3_addr <= c_addr;
                  ch3_din  <= c_din;
                  ch3_rnw  <= c_rnw;
                  ch3_be   <= c_be;
                  ch3_req  <= '1';
                  state    <= BUSY_C;
               end if;

            when BUSY_A =>
               if (ch3_ready = '1') then
                  a_ready <= '1';
                  state   <= GAP;
               end if;

            when BUSY_B =>
               if (ch3_ready = '1') then
                  b_ready <= '1';
                  state   <= GAP;
               end if;

            when BUSY_C =>
               if (ch3_ready = '1') then
                  c_ready <= '1';
                  state   <= GAP;
               end if;

            when GAP =>
               state <= IDLE;
         end case;
      end if;
   end process;

end architecture;
