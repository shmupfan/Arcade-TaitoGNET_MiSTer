-- G-NET hardware debug overlay, capture side (docs/hw_debug_overlay.md).
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
-- Runs on the clock of the CPU and zn2_board (clk1x, or clk_cpu with
-- CPU_CLK_SPLIT = 1). Every register here has a power-up value and no reset
-- input: the core reset (which the watchdog drives) is only observed, so
-- the counters and the watchdog snapshot survive it.
--
-- Read port: rd_word is a combinational mux of the registers by rd_idx, for
-- the destination side of a cdc_handshake (zn_dbg_overlay) that holds rd_idx
-- and captures rd_word into its cdc_tx_rsp register.
--
-- Words (also the overlay rows):
--   0 PC  CPU fetch PC (cpu.vhd PC register)
--   1 DA  address of the last CPU data access sent to memorymux (loads and
--         stores; the scratchpad stays inside the CPU and is not seen)
--   2 IO  31:24 control register 0x1FB40000, 23:16 watchdog expiries since
--         power-on (saturating), 15:0 low half of the last data address in
--         0x1F80xxxx (any segment)
--   3 MS  ms since the core reset was last released
--   4 WD  31:16 ms since the last watchdog kick (CK falling edge, core reset
--         or expiry, the events that reload gnet_ctrl's counter), 15:0 the
--         largest value of 31:16 since power-on
--   5 RS  31:24 resets caused by the watchdog, 23:16 other resets (both
--         saturating), 15:0 ATA READ/WRITE SECTORS commands taken (wraps)
--   6 XP  snapshot at the last watchdog expiry: PC
--   7 XD  snapshot: last data address
--   8 XI  snapshot: 31:16 ms since the last kick, 15:0 low half of the last
--         0x1F80xxxx address
--   9 XM  snapshot: ms since the core reset was released
--   other words read 0
--
-- Reset events: core_reset is a pulse train (savestates.vhd reset_out, one
-- pulse per release, retried every 1023 clk2x cycles until the CPU pauses),
-- so a rising edge counts as a new reset only after 2 ms ticks without
-- core_reset. A reset counts as a watchdog reset when an expiry came less
-- than 100 ms before it. Expiries with the OSD watchdog option Off reset
-- nothing and are counted in word 2 only.
--
-- The ms tick: an accumulator adds 1000 per clock modulo CLK_HZ, so the
-- tick rate is exact for 33.8688 MHz as well as for 50 MHz.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity zn_dbg_regs is
   generic
   (
      CLK_HZ     : integer := 33868800;
      WD_WIN_MS  : integer := 100;   -- expiry to reset window for the watchdog count
      GAP_TICKS  : integer := 2      -- ms ticks without core_reset that end a reset burst
   );
   port
   (
      clk        : in  std_logic;
      core_reset : in  std_logic;                       -- observed only
      pc         : in  unsigned(31 downto 0);
      dat_take   : in  std_logic;                       -- ce and mem_request and mem_isData
      dat_addr   : in  unsigned(31 downto 0);
      wd_fire    : in  std_logic;                       -- pulse: gnet_ctrl wd_reset
      wd_kick    : in  std_logic;                       -- pulse: gnet_ctrl wd_kick
      ctrl       : in  std_logic_vector(7 downto 0);    -- gnet_ctrl control register
      sec_cmd    : in  std_logic;                       -- pulse: gnet_ata READ/WRITE SECTORS
      rd_idx     : in  std_logic_vector(3 downto 0);
      rd_word    : out std_logic_vector(31 downto 0)
   );
end entity;

architecture arch of zn_dbg_regs is

   signal acc        : unsigned(26 downto 0) := (others => '0');   -- 0 to CLK_HZ - 1 (CLK_HZ < 2**26)
   signal tick       : std_logic := '0';

   signal da_q       : unsigned(31 downto 0) := (others => '0');
   signal io_q       : unsigned(15 downto 0) := (others => '0');
   signal ms_rst     : unsigned(31 downto 0) := (others => '0');
   signal nk         : unsigned(15 downto 0) := (others => '0');
   signal nk_max     : unsigned(15 downto 0) := (others => '0');
   signal wdx        : unsigned(7 downto 0)  := (others => '0');
   signal ata        : unsigned(15 downto 0) := (others => '0');
   signal rst_wd     : unsigned(7 downto 0)  := (others => '0');
   signal rst_oth    : unsigned(7 downto 0)  := (others => '0');

   signal s_pc       : unsigned(31 downto 0) := (others => '0');
   signal s_da       : unsigned(31 downto 0) := (others => '0');
   signal s_io       : unsigned(15 downto 0) := (others => '0');
   signal s_ms       : unsigned(31 downto 0) := (others => '0');
   signal s_nk       : unsigned(15 downto 0) := (others => '0');

   signal rst_d      : std_logic := '0';
   signal in_burst   : std_logic := '0';
   signal quiet      : integer range 0 to GAP_TICKS := 0;
   signal wd_flag    : std_logic := '0';
   signal wd_win     : integer range 0 to WD_WIN_MS := 0;

begin

   assert CLK_HZ >= 1000 and CLK_HZ < 2**26 report "zn_dbg_regs: CLK_HZ out of range" severity failure;

   process (clk)
      variable sum : unsigned(26 downto 0);
   begin
      if rising_edge(clk) then

         -- ms tick: acc + 1000 modulo CLK_HZ
         sum  := acc + to_unsigned(1000, 27);
         tick <= '0';
         if (sum >= to_unsigned(CLK_HZ, 27)) then
            acc  <= sum - to_unsigned(CLK_HZ, 27);
            tick <= '1';
         else
            acc  <= sum;
         end if;

         -- last data address, last 0x1F80xxxx address
         if (dat_take = '1') then
            da_q <= dat_addr;
            if (dat_addr(28 downto 16) = "1111110000000") then   -- 0x1F80 without the segment bits
               io_q <= dat_addr(15 downto 0);
            end if;
         end if;

         -- ms since the core reset was released
         if (core_reset = '1') then
            ms_rst <= (others => '0');
         elsif (tick = '1') then
            ms_rst <= ms_rst + 1;
         end if;

         -- ms since the watchdog counter was last reloaded (kick, reset, expiry)
         if (core_reset = '1' or wd_kick = '1' or wd_fire = '1') then
            nk <= (others => '0');
         elsif (tick = '1' and nk /= x"FFFF") then
            nk <= nk + 1;
         end if;
         if (nk > nk_max) then
            nk_max <= nk;
         end if;

         -- ATA sector commands
         if (sec_cmd = '1') then
            ata <= ata + 1;
         end if;

         -- watchdog expiry: snapshot and count
         if (wd_fire = '1') then
            s_pc <= pc;
            s_da <= da_q;
            s_io <= io_q;
            s_ms <= ms_rst;
            s_nk <= nk;
            if (wdx /= x"FF") then
               wdx <= wdx + 1;
            end if;
         end if;

         -- watchdog expiry to reset window
         if (wd_fire = '1') then
            wd_flag <= '1';
            wd_win  <= 0;
         elsif (wd_flag = '1' and tick = '1') then
            if (wd_win = WD_WIN_MS - 1) then
               wd_flag <= '0';
            else
               wd_win <= wd_win + 1;
            end if;
         end if;

         -- reset events: rising edge of core_reset outside a burst
         rst_d <= core_reset;
         if (core_reset = '1') then
            in_burst <= '1';
            quiet    <= 0;
            if (rst_d = '0' and in_burst = '0') then
               if (wd_flag = '1') then
                  if (rst_wd /= x"FF") then
                     rst_wd <= rst_wd + 1;
                  end if;
                  wd_flag <= '0';
               else
                  if (rst_oth /= x"FF") then
                     rst_oth <= rst_oth + 1;
                  end if;
               end if;
            end if;
         elsif (in_burst = '1' and tick = '1') then
            if (quiet = GAP_TICKS - 1) then
               in_burst <= '0';
            else
               quiet <= quiet + 1;
            end if;
         end if;

      end if;
   end process;

   process (rd_idx, pc, da_q, io_q, ctrl, wdx, ms_rst, nk, nk_max, rst_wd, rst_oth, ata, s_pc, s_da, s_io, s_ms, s_nk)
   begin
      case (rd_idx) is
         when x"0"   => rd_word <= std_logic_vector(pc);
         when x"1"   => rd_word <= std_logic_vector(da_q);
         when x"2"   => rd_word <= ctrl & std_logic_vector(wdx) & std_logic_vector(io_q);
         when x"3"   => rd_word <= std_logic_vector(ms_rst);
         when x"4"   => rd_word <= std_logic_vector(nk) & std_logic_vector(nk_max);
         when x"5"   => rd_word <= std_logic_vector(rst_wd) & std_logic_vector(rst_oth) & std_logic_vector(ata);
         when x"6"   => rd_word <= std_logic_vector(s_pc);
         when x"7"   => rd_word <= std_logic_vector(s_da);
         when x"8"   => rd_word <= std_logic_vector(s_nk) & std_logic_vector(s_io);
         when x"9"   => rd_word <= std_logic_vector(s_ms);
         when others => rd_word <= (others => '0');
      end case;
   end process;

end architecture;
