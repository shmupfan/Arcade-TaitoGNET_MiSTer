-- SIO0 for the ZN-2: the PS1 serial port driving the two CAT702 and the
-- znmcu, in place of PSX_MiSTer's joypad.vhd.
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
-- docs/zn2_layer_design.md 7.2. Register behaviour from MAME 0.288
-- src/devices/cpu/psx/sio.cpp (rank 5; no CXD8661R document), written as
-- hardware, on PSX_MiSTer's bus_pad port (offsets 0-F of 0x1F801040):
--   0 data    write: TX byte; TX ready and TX empty cleared; the bit timer
--                    restarts (sio_timer_adjust). read: RX byte (low 8
--                    bits); RX ready cleared; the RX byte becomes FFh
--   4 status  bit 0 TX ready, 1 RX ready, 2 TX empty, 4 overrun, 7 DSR,
--                    9 IRQ
--   8 mode (low half), control (high half): control bit 0 TX enable,
--                    4 IRQ acknowledge (not stored), 6 reset, 10/11/12
--                    TX/RX/DSR interrupt enables
--   C baud (high half)
-- Bit timing: one tick every prescaler x baud cycles of the 33.8688 MHz
-- clock (mode bits 1-0: 1 = x1, 2 = x16, 3 = x64, 0 = stopped), running
-- while a byte waits or is in progress. A tick starts a byte when none is in
-- progress, TX is enabled and a byte waits (TX ready and TX empty set), and
-- every tick of a byte sends and receives one bit, LSB first: bit_stb with
-- the TXD bit to the devices, RXD (the AND of the device outputs, zn.h 39)
-- shifted in in the same clock. That is MAME's order inside sio_tick (SCK
-- low, TXD, SCK high, sample). After 8 bits: RX ready (or overrun), RX/TX
-- interrupts if enabled.
-- PSX_MiSTer's joypad.vhd times a byte as baud x 8 cycles without the
-- prescaler (PS1, from hardware tests); which rule the CXD8661R follows is
-- open (needs-review). PS1_TIMING = 1 selects the joypad.vhd rule.
-- DSR: status bit 7 follows the line (low = set); a falling edge with the
-- DSR interrupt enabled raises IRQ (sio.cpp write_dsr).

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity zn_sio0 is
   generic
   (
      PS1_TIMING : integer := 0     -- 0 = MAME (prescaler x baud per bit), 1 = joypad.vhd (baud per bit)
   );
   port
   (
      clk1x        : in  std_logic;
      ce           : in  std_logic;
      reset        : in  std_logic;
      -- bit timer step: '1' = one count per clock (33.8688 MHz clk1x); with
      -- psx_top's CPU_CLK_SPLIT = 1 the clock is clk_cpu (50 MHz) and this is
      -- tick_accum's 33.8688 MHz-equivalent sys_tick (decision 1 in
      -- docs/r1_cpu_domain_design.md), so a bit keeps its 33.8688 MHz length
      sys_tick     : in  std_logic := '1';

      bus_addr     : in  unsigned(3 downto 0);
      bus_dataWrite: in  std_logic_vector(31 downto 0);
      bus_read     : in  std_logic;
      bus_write    : in  std_logic;
      bus_writeMask: in  std_logic_vector(3 downto 0);
      bus_dataRead : out std_logic_vector(31 downto 0) := (others => '0');

      irqRequest   : out std_logic;

      bit_stb      : out std_logic;   -- one clock per bit, to zn_cat702 and znmcu
      txd          : out std_logic;   -- TXD for that bit
      rxd          : in  std_logic;   -- AND of the device outputs, sampled with bit_stb
      dsr_n        : in  std_logic
   );
end entity;

architecture arch of zn_sio0 is

   signal tx_data    : std_logic_vector(7 downto 0) := (others => '0');
   signal rx_data    : std_logic_vector(7 downto 0) := x"FF";
   signal tx_shift   : std_logic_vector(7 downto 0) := (others => '0');
   signal rx_shift   : std_logic_vector(7 downto 0) := (others => '0');
   signal tx_bits    : integer range 0 to 8 := 0;
   signal rx_bits    : integer range 0 to 8 := 0;
   signal st_txrdy   : std_logic := '1';
   signal st_rxrdy   : std_logic := '0';
   signal st_txempty : std_logic := '1';
   signal st_overrun : std_logic := '0';
   signal st_dsr     : std_logic := '0';
   signal st_irq     : std_logic := '0';
   signal mode       : std_logic_vector(15 downto 0) := (others => '0');
   signal ctrl       : std_logic_vector(15 downto 0) := (others => '0');
   signal baud       : std_logic_vector(15 downto 0) := (others => '0');

   signal period     : unsigned(23 downto 0);
   signal tcount     : unsigned(23 downto 0) := (others => '0');
   signal running    : std_logic := '0';
   signal dsr_n_1    : std_logic := '1';

   signal tick       : std_logic;
   signal start      : std_logic;
   signal sendbit    : std_logic;
   signal status     : std_logic_vector(15 downto 0);

begin

   period <= resize(unsigned(baud), 24)                        when (PS1_TIMING = 1) else
             resize(unsigned(baud), 24)                        when (mode(1 downto 0) = "01") else
             shift_left(resize(unsigned(baud), 24), 4)         when (mode(1 downto 0) = "10") else
             shift_left(resize(unsigned(baud), 24), 6)         when (mode(1 downto 0) = "11") else
             (others => '0');

   -- this clock is a tick; does it start a byte, does it carry a bit
   tick    <= '1' when (ce = '1' and sys_tick = '1' and running = '1' and tcount <= 1 and period /= 0) else '0';
   start   <= '1' when (tick = '1' and tx_bits = 0 and ctrl(0) = '1' and st_txempty = '0') else '0';
   sendbit <= '1' when (start = '1' or (tick = '1' and tx_bits /= 0)) else '0';

   bit_stb <= sendbit;
   txd     <= tx_data(0) when (start = '1') else tx_shift(0) when (sendbit = '1') else '1';

   status <= "000000" & st_irq & '0' & st_dsr & "00" & st_overrun & '0' & st_txempty & st_rxrdy & st_txrdy;
   irqRequest <= st_irq;

   process (clk1x)
      variable c   : std_logic_vector(15 downto 0);
      variable rxs : std_logic_vector(7 downto 0);
      variable rxb : integer range 0 to 8;
      variable txb : integer range 0 to 8;
      variable txe : std_logic;
   begin
      if rising_edge(clk1x) then

         if (reset = '1') then
            tx_data    <= (others => '0');
            rx_data    <= x"FF";
            tx_bits    <= 0;
            rx_bits    <= 0;
            st_txrdy   <= '1';
            st_rxrdy   <= '0';
            st_txempty <= '1';
            st_overrun <= '0';
            st_dsr     <= '0';
            st_irq     <= '0';
            mode       <= (others => '0');
            ctrl       <= (others => '0');
            baud       <= (others => '0');
            running    <= '0';
            dsr_n_1    <= '1';
         elsif (ce = '1') then

            bus_dataRead <= (others => '0');

            -- DSR line (sio.cpp write_dsr)
            dsr_n_1 <= dsr_n;
            if (dsr_n = '1') then
               st_dsr <= '0';
            elsif (dsr_n_1 = '1' and st_dsr = '0') then
               st_dsr <= '1';
               if (ctrl(12) = '1') then
                  st_irq <= '1';
               end if;
            end if;

            -- bit timer
            if (running = '1') then
               if (tick = '1') then
                  tcount <= period;
               elsif (tcount > 1 and sys_tick = '1') then
                  tcount <= tcount - 1;
               end if;
            end if;

            -- one tick (sio_tick)
            txb := tx_bits; rxb := rx_bits; rxs := rx_shift; txe := st_txempty;
            if (start = '1') then
               txb := 8; rxb := 8; rxs := (others => '0');
               txe := '1';
               st_txempty <= '1';
               st_txrdy   <= '1';
               tx_shift   <= tx_data;
            end if;
            if (sendbit = '1') then
               if (start = '1') then
                  tx_shift <= '0' & tx_data(7 downto 1);
               else
                  tx_shift <= '0' & tx_shift(7 downto 1);
               end if;
               txb := txb - 1;
               if (txb = 0 and ctrl(10) = '1') then
                  st_irq <= '1';
               end if;
            end if;
            if (tick = '1' and rxb /= 0) then
               rxs := rxd & rxs(7 downto 1);
               rxb := rxb - 1;
               if (rxb = 0) then
                  if (st_rxrdy = '1') then
                     st_overrun <= '1';
                  else
                     rx_data  <= rxs;
                     st_rxrdy <= '1';
                  end if;
                  if (ctrl(11) = '1') then
                     st_irq <= '1';
                  end if;
               end if;
            end if;
            tx_bits  <= txb;
            rx_bits  <= rxb;
            rx_shift <= rxs;
            if (tick = '1' and txb = 0 and txe = '1') then
               running <= '0';   -- sio_timer_adjust: nothing left to send
            end if;

            -- bus read
            if (bus_read = '1') then
               -- Decoded on bus_addr(3 downto 1): memorymux only rotates bytes
               -- within a halfword, so a halfword read at offset 2/6/A/E must be
               -- answered in bits 15:0 (as joypad.vhd and sio.vhd do). Before
               -- this, lhu 0x1F80104A returned MODE instead of CTRL and the
               -- game's read-modify-write cleared TXEN (Shikigami stall, found
               -- in the fullsys-sim Verilator run, 2026-10-05).
               case to_integer(bus_addr(3 downto 1)) is
                  when 0 | 1 =>   -- data; offset 2 is the upper half (0) of the same dword
                     if (bus_addr(1) = '0') then
                        bus_dataRead <= x"000000" & rx_data;
                     else
                        bus_dataRead <= x"00000000";
                     end if;
                     st_rxrdy     <= '0';
                     rx_data      <= x"FF";
                  when 2 =>
                     bus_dataRead <= x"0000" & status;
                  when 3 =>
                     bus_dataRead <= x"00000000";
                  when 4 =>
                     bus_dataRead <= ctrl & mode;
                  when 5 =>
                     bus_dataRead <= x"0000" & ctrl;
                  when 6 =>
                     bus_dataRead <= baud & x"0000";
                  when others =>
                     bus_dataRead <= x"0000" & baud;
               end case;
            end if;

            -- bus write
            if (bus_write = '1') then
               case to_integer(bus_addr(3 downto 2)) is
                  when 0 =>
                     if (bus_writeMask(0) = '1') then
                        tx_data    <= bus_dataWrite(7 downto 0);
                        st_txrdy   <= '0';
                        st_txempty <= '0';
                        -- the timer restarts: the next tick is one period away
                        running    <= '1';
                        tcount     <= period - 1;
                     end if;
                  when 2 =>
                     if (bus_writeMask(1 downto 0) /= "00") then
                        mode <= bus_dataWrite(15 downto 0);
                     end if;
                     if (bus_writeMask(3 downto 2) /= "00") then
                        c := bus_dataWrite(31 downto 16);
                        ctrl <= c;
                        if (c(6) = '1') then          -- reset
                           st_txempty <= '1';
                           st_txrdy   <= '1';
                           st_rxrdy   <= '0';
                           st_overrun <= '0';
                           st_irq     <= '0';
                           tx_bits    <= 0;
                           rx_bits    <= 0;
                        end if;
                        if (c(4) = '1') then          -- acknowledge
                           st_irq  <= '0';
                           ctrl(4) <= '0';
                        end if;
                     end if;
                  when others =>
                     if (bus_writeMask(3 downto 2) /= "00") then
                        baud <= bus_dataWrite(31 downto 16);
                     end if;
               end case;
            end if;

         end if;
      end if;
   end process;

end architecture;
