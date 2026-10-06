-- ZN CAT702 security chip (serial magic latch on SIO0), bit level.
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
-- Behaviour from the algorithm description and model in MAME 0.288
-- src/devices/machine/cat702.cpp (smf; no datasheet exists, evidence rank 5),
-- written as hardware: no code taken. docs/zn2_layer_design.md 6.
--   select falling : state = FCh, bit counter = 0
--   select rising  : output = 1
--   SCK falling    : if bit counter = 0, state = TF2(state) (fixed initial
--                    sbox); output = state(bit counter)
--   SCK rising     : if TXD = 0, state = sbox[bit counter](state); bit
--                    counter + 1 (mod 8)
-- sbox[0] is the 8-byte per-chip key (MAME regions cat702_1 = tt10.ic652,
-- cat702_2 = tt16.u17 for G-NET); sbox[n] is derived from sbox[n-1] by a
-- rotate with feedback, so the coefficients advance with the bit counter
-- instead of being stored for all eight bit positions.
-- Interface: the SIO0 (zn_sio0.vhd) gives one bit_stb pulse per bit with the
-- TXD value of that bit, and samples dataout in the same clock. dataout is
-- the bit the chip drives after the SCK falling edge of that bit (from the
-- current state); at bit_stb the state takes both edges' updates. This is
-- MAME's order inside one SIO tick (sio.cpp 125-189: SCK low, TXD, SCK high,
-- sample) with no extra clock of latency. Deselected, dataout is 1.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity zn_cat702 is
   port
   (
      clk          : in  std_logic;
      reset        : in  std_logic;

      key_we       : in  std_logic;
      key_addr     : in  unsigned(2 downto 0);
      key_data     : in  std_logic_vector(7 downto 0);

      sel_n        : in  std_logic;
      bit_stb      : in  std_logic;
      txd          : in  std_logic;
      dataout      : out std_logic
   );
end entity;

architecture arch of zn_cat702 is

   type t_sbox is array(0 to 7) of std_logic_vector(7 downto 0);
   constant INITIAL_SBOX : t_sbox := (x"FF", x"FE", x"FC", x"F8", x"F0", x"E0", x"C0", x"7F");

   signal key      : t_sbox := (others => (others => '1'));
   signal coef     : t_sbox := (others => (others => '1'));
   signal state    : std_logic_vector(7 downto 0) := (others => '0');
   signal bitcnt   : unsigned(2 downto 0) := (others => '0');
   signal sel_n_1  : std_logic := '1';
   signal s1       : std_logic_vector(7 downto 0);

   function apply(s : std_logic_vector(7 downto 0); b : t_sbox) return std_logic_vector is
      variable r : std_logic_vector(7 downto 0) := (others => '0');
   begin
      for i in 0 to 7 loop
         if (s(i) = '1') then
            r := r xor b(i);
         end if;
      end loop;
      return r;
   end function;

   -- sbox[n] from sbox[n-1] (cat702.cpp compute_sbox_coef)
   function advance(c : t_sbox) return t_sbox is
      variable n : t_sbox;
      variable r : std_logic_vector(7 downto 0);
   begin
      for b in 0 to 7 loop
         r    := c((b - 1) mod 8);
         n(b) := r(6 downto 0) & (r(7) xor r(6));
      end loop;
      n(7) := n(7) xor n(0);
      return n;
   end function;

begin

   -- state after the SCK falling edge of the current bit
   s1      <= apply(state, INITIAL_SBOX) when (bitcnt = 0) else state;
   dataout <= '1' when (sel_n = '1' or sel_n_1 = '1') else s1(to_integer(bitcnt));

   process (clk)
   begin
      if rising_edge(clk) then

         if (key_we = '1') then
            key(to_integer(key_addr)) <= key_data;
         end if;

         sel_n_1 <= sel_n;

         if (reset = '1') then
            state   <= (others => '0');
            bitcnt  <= (others => '0');
            coef    <= key;
         elsif (sel_n = '0' and sel_n_1 = '1') then
            state   <= x"FC";
            bitcnt  <= (others => '0');
            coef    <= key;
         elsif (sel_n = '0' and bit_stb = '1') then
            if (txd = '0') then
               state <= apply(s1, coef);
            else
               state <= s1;
            end if;
            bitcnt <= bitcnt + 1;
            if (bitcnt = 7) then
               coef <= key;
            else
               coef <= advance(coef);
            end if;
         end if;

      end if;
   end process;

end architecture;
