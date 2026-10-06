-- ZN I/O MCU (NEC uPD78081, ROM not dumped): behavioural model on SIO0.
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
-- The MCU ROM is NO_DUMP (taitogn.cpp 1023-1024, R16), so this follows the
-- behaviour of MAME 0.288 src/mame/sony/znmcu.cpp (rank 5), written as
-- hardware (docs/zn2_layer_design.md 7):
--   select falling : byte and bit counters 0; 50 us later DSR goes low for
--                    5 us; at that first pulse the reply is built: byte 0 =
--                    (data byte count << 4) | DSW, count 8 with the analog
--                    flag (8 analog channels follow), 6 with the trackball
--                    flag (deltas, 0 here: no trackball), else 1 (00h)
--   SCK falling    : while selected, TXD = bit n of the current byte (0
--                    past the last byte), LSB first; after bit 7 the byte
--                    counter advances and, if more bytes follow, DSR pulses
--                    again 50 us later
--   select rising  : TXD and DSR high, timer stopped
-- Interface as zn_cat702.vhd: one bit_stb clock per bit from zn_sio0; txd
-- is the bit for the current position (sampled by the SIO in that clock),
-- 1 while deselected.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity znmcu is
   generic
   (
      CLK_HZ       : integer := 33868800
   );
   port
   (
      clk          : in  std_logic;
      reset        : in  std_logic;

      sel_n        : in  std_logic;   -- 0 = selected ((znsecsel and 8Ch) = 8Ch)
      analog_rd    : in  std_logic;   -- znsecsel bit 4
      trackball_rd : in  std_logic;   -- znsecsel bit 5
      bit_stb      : in  std_logic;
      txd          : out std_logic;
      dsr_n        : out std_logic := '1';

      dsw          : in  std_logic_vector(3 downto 0);
      analog0      : in  std_logic_vector(7 downto 0) := x"FF";  -- channels 0 to 7
      analog1      : in  std_logic_vector(7 downto 0) := x"FF";
      analog2      : in  std_logic_vector(7 downto 0) := x"FF";
      analog3      : in  std_logic_vector(7 downto 0) := x"FF";
      analog4      : in  std_logic_vector(7 downto 0) := x"FF";
      analog5      : in  std_logic_vector(7 downto 0) := x"FF";
      analog6      : in  std_logic_vector(7 downto 0) := x"FF";
      analog7      : in  std_logic_vector(7 downto 0) := x"FF"
   );
end entity;

architecture arch of znmcu is

   constant T50 : integer := CLK_HZ / 20000;    -- 50 us
   constant T5  : integer := CLK_HZ / 200000;   -- 5 us

   type t_send is array(0 to 8) of std_logic_vector(7 downto 0);
   signal send     : t_send := (others => (others => '0'));
   signal nbytes   : integer range 0 to 8 := 0;
   signal byte_i   : integer range 0 to 15 := 0;
   signal bit_i    : integer range 0 to 7 := 0;
   signal timer    : integer range 0 to T50 := 0;
   signal phase    : std_logic := '0';   -- 0: next expiry pulls DSR low, 1: releases it
   signal sel_n_1  : std_logic := '1';
   signal cur      : std_logic_vector(7 downto 0);

begin

   cur <= send(byte_i) when (byte_i <= nbytes and byte_i <= 8) else x"00";
   txd <= '1' when (sel_n = '1' or sel_n_1 = '1') else cur(bit_i);

   process (clk)
      variable n : integer range 0 to 8;
   begin
      if rising_edge(clk) then
         sel_n_1 <= sel_n;

         if (reset = '1') then
            dsr_n  <= '1';
            timer  <= 0;
            byte_i <= 0;
            bit_i  <= 0;
         elsif (sel_n = '0' and sel_n_1 = '1') then
            byte_i <= 0;
            bit_i  <= 0;
            timer  <= T50;
            phase  <= '0';
         elsif (sel_n = '1' and sel_n_1 = '0') then
            dsr_n  <= '1';
            timer  <= 0;
         else
            if (timer > 1) then
               timer <= timer - 1;
            elsif (timer = 1) then
               timer <= 0;
               if (phase = '0') then
                  dsr_n <= '0';
                  if (byte_i = 0) then
                     if (analog_rd = '1') then n := 8; elsif (trackball_rd = '1') then n := 6; else n := 1; end if;
                     nbytes  <= n;
                     send(0) <= std_logic_vector(to_unsigned(n, 4)) & dsw;
                     if (analog_rd = '1') then
                        send(1) <= analog0; send(2) <= analog1; send(3) <= analog2; send(4) <= analog3;
                        send(5) <= analog4; send(6) <= analog5; send(7) <= analog6; send(8) <= analog7;
                     elsif (trackball_rd = '1') then
                        send(1 to 6) <= (others => x"00");
                     end if;
                  end if;
                  timer <= T5;
                  phase <= '1';
               else
                  dsr_n <= '1';
               end if;
            end if;

            if (sel_n = '0' and bit_stb = '1') then
               if (bit_i = 7) then
                  bit_i <= 0;
                  if (byte_i < nbytes) then
                     timer <= T50;
                     phase <= '0';
                  end if;
                  if (byte_i < 15) then
                     byte_i <= byte_i + 1;
                  end if;
               else
                  bit_i <= bit_i + 1;
               end if;
            end if;
         end if;
      end if;
   end process;

end architecture;
