-- ZN-2 board registers on expansion 3 (and the silent Taito Zoom stub).
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
-- docs/zn2_layer_design.md 5, 7, 8 and 12. Port: the zn_* bus of memorymux
-- (ZN2_MAP = 1), word address as an offset from 0x1F000000, byte enables per
-- lane. Map (MAME 0.288 zn.cpp maincpu_program_map 146-164 and
-- zn2_maincpu_program_map 166-173, taitogn.cpp 473-488):
--   A00000 P1, A00100 P2, A00200 SERVICE, A00300 SYSTEM (8-bit, lane 0;
--          active low; writes ignored: the BIOS writes 1-7 and 0Fh to
--          A00000 during POST, MAME ignores them, needs-review)
--   A10000 P3, A10100 P4 (unused on G-NET: FFh)
--   A10200 board configuration (BOARDCFG; MAME 69h = 4 MB RAM, 2 MB VRAM,
--          512 KB SPU RAM, revision 1)
--   A10300 znsecsel (R/W): bit 2 CAT702 #1 select, bit 3 CAT702 #2 select
--          (both active low), bit 4 znmcu analog, bit 5 znmcu trackball,
--          znmcu selected while (value and 8Ch) = 8Ch
--   A20000 coin (R/W): counters and lockouts, out to the shell
--   A40000 reads 0; A51C00-A51DFF reads 0; A60000 bit 3 (MAME's "work
--          around for mismatched CPU and SPU clock", R2: the real register is
--          unknown). The games' SPU register read routine does a dummy read
--          at A51C00 + register offset, polls A60000 until bit 3 is set (up to
--          100 tries, then "SPU:T/O [ReadStatusFlag Error]"), then reads the
--          SPU register itself (MAME trace, main docs/r1_cpu_domain_design.md
--          Measurement 1). SPU_STATUS = 0: bit 3 toggles on every read of the
--          low half, starting at 1 (MAME); 1: bit 3 always 1 (enough for
--          raycris and psyvaria per that trace, one poll per SPU read)
--   AF0000-AF07FF AT28C16 EEPROM, byte per address: a write starts a
--          self-timed byte write (WRITE_US); reads during it return the last
--          written byte with bit 7 inverted (DATA polling, AT28C16 datasheet
--          doc0540 p2; MAME at28c16.cpp 184-190 inverts the same bit); writes
--          during it are ignored. MAME skips writes of the value already
--          stored (at28c16.cpp 172); the datasheet does not, nor does this
--          model.
--   B20000-B20007 reads FFFFh (zn.cpp unknown_r)
--   Taito Zoom stub (no Zoom in the silent build): B80000-B80003 register
--          writes ignored, BA0000 write ignored, BC0000 reads 0 (as
--          taito_zm.cpp sound_irq_r), BE0000-BE01FF M66220FP mailbox, 256 x 8
--          on lanes 0 and 2 (taitogn.cpp 487, umask 00FF00FFh), read/write.
-- Other addresses: writes ignored, reads 0. hit tells the bus top which
-- addresses this block answers.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity zn2_io is
   generic
   (
      CLK_HZ     : integer := 33868800;
      WRITE_US   : integer := 200;
      BOARDCFG   : std_logic_vector(7 downto 0) := x"69";
      SPU_STATUS : integer := 0
   );
   port
   (
      clk          : in  std_logic;
      reset        : in  std_logic;

      req          : in  std_logic;
      we           : in  std_logic;
      addr         : in  unsigned(23 downto 0);
      be           : in  std_logic_vector(3 downto 0);
      wdata        : in  std_logic_vector(31 downto 0);
      ack          : out std_logic := '0';
      rdata        : out std_logic_vector(31 downto 0) := (others => '0');
      hit          : out std_logic;

      -- inputs, active low (zn.cpp INPUT_PORTS in taitogn.cpp 798-857)
      in_p1        : in  std_logic_vector(7 downto 0);
      in_p2        : in  std_logic_vector(7 downto 0);
      in_service   : in  std_logic_vector(7 downto 0);
      in_system    : in  std_logic_vector(7 downto 0);

      znsecsel     : out std_logic_vector(7 downto 0) := (others => '0');
      coin         : out std_logic_vector(7 downto 0) := (others => '0');

      -- EEPROM contents for the shell (NVRAM load and save), second port
      ee_addr      : in  unsigned(10 downto 0);
      ee_we        : in  std_logic;
      ee_wdata     : in  std_logic_vector(7 downto 0);
      ee_rdata     : out std_logic_vector(7 downto 0);
      ee_busy      : out std_logic;

      -- NVRAM save (shell, docs/m4_shell.md 4): a copy of the EEPROM written
      -- together with it by both ports, read on nv_clk (the hps_io clock) as
      -- 16-bit words, low byte = even address. nv_wtog toggles on every CPU
      -- write (a register named for rtl/gnet/cdc/cdc.sdc; the reader puts it
      -- through cdc_sync). Unconnected, the copy is removed in synthesis.
      nv_clk       : in  std_logic := '0';
      nv_addr      : in  unsigned(9 downto 0) := (others => '0');
      nv_q         : out std_logic_vector(15 downto 0);
      nv_wtog      : out std_logic
   );
end entity;

architecture arch of zn2_io is

   constant WRITE_CYCLES : integer := CLK_HZ / 1000000 * WRITE_US + (CLK_HZ mod 1000000) * WRITE_US / 1000000;

   -- mailbox as 128 x 16: low byte = lane 0, high byte = lane 2 of a word
   -- two byte arrays (one per lane) so Quartus 17 infers RAM, not registers
   type t_mbox is array(0 to 127) of std_logic_vector(7 downto 0);
   signal mbox_lo   : t_mbox := (others => x"00");
   signal mbox_hi   : t_mbox := (others => x"00");

   signal ee_q      : std_logic_vector(7 downto 0);
   signal mb_q      : std_logic_vector(15 downto 0);
   signal ee_timer  : integer range 0 to WRITE_CYCLES := 0;
   signal ee_last   : std_logic_vector(7 downto 0) := (others => '0');
   signal spuhack   : std_logic := '0';

   -- pipeline: request latched, then RAM data available
   signal p_valid   : std_logic := '0';
   signal p_we      : std_logic;
   signal p_addr    : unsigned(23 downto 0);
   signal p_be      : std_logic_vector(3 downto 0);
   signal p_wdata   : std_logic_vector(31 downto 0);

   function lane_byte(be : std_logic_vector(3 downto 0)) return integer is
   begin
      if be(0) = '1' then return 0; elsif be(1) = '1' then return 1;
      elsif be(2) = '1' then return 2; else return 3; end if;
   end function;

   -- one CPU-side address per RAM (read and write share it, so each RAM
   -- is a simple or true dual-port block): the pending request while it is
   -- being answered, else the incoming one
   signal c_addr    : unsigned(23 downto 0);
   signal c_be      : std_logic_vector(3 downto 0);
   signal a_ee      : integer range 0 to 2047;
   signal a_mb      : integer range 0 to 127;
   signal ee_wr     : std_logic;
   signal ee_addr_a : std_logic_vector(10 downto 0);
   signal ee_data_a : std_logic_vector(7 downto 0);
   signal ee_addr_b : std_logic_vector(10 downto 0);
   signal mb_wr     : std_logic;

   -- NVRAM copy: two 1024 x 8 simple dual-port RAMs (even and odd bytes),
   -- written on clk, read on nv_clk
   type t_nv is array(0 to 1023) of std_logic_vector(7 downto 0);
   signal nv_lo        : t_nv;
   signal nv_hi        : t_nv;
   attribute ramstyle  : string;
   attribute ramstyle of nv_lo : signal is "M10K, no_rw_check";
   attribute ramstyle of nv_hi : signal is "M10K, no_rw_check";
   signal nv_we        : std_logic;
   signal nv_waddr     : std_logic_vector(10 downto 0);
   signal nv_wdata     : std_logic_vector(7 downto 0);
   signal cdc_tx_nvtog : std_logic := '0';

begin

   hit <= '1' when (addr(23 downto 20) = x"A" and addr(23 downto 16) /= x"A3") or
                   (addr(23 downto 16) = x"B2") or
                   (addr(23 downto 16) = x"B8") or (addr(23 downto 16) = x"BA") or
                   (addr(23 downto 16) = x"BC") or (addr(23 downto 16) = x"BE") else '0';

   c_addr <= p_addr when p_valid = '1' else addr;
   c_be   <= p_be   when p_valid = '1' else be;
   -- byte address of the first enabled lane
   a_ee   <= to_integer(c_addr(10 downto 2)) * 4 + lane_byte(c_be);
   a_mb   <= to_integer(c_addr(8 downto 2));
   ee_wr  <= '1' when (p_valid = '1' and p_we = '1' and p_addr(23 downto 11) = x"AF0" & '0' and ee_timer = 0) else '0';
   mb_wr  <= '1' when (p_valid = '1' and p_we = '1' and p_addr(23 downto 9) = x"BE0" & "000") else '0';

   -- EEPROM: dpram (PSX_MiSTer rtl/dpram.vhd, M10K), port A CPU (address
   -- registered, write at answer time), port B shell (NVRAM load and save).
   -- Power-up contents are 0 in the block RAM; the shell loads the NVRAM
   -- image or FFh (erased) before releasing reset.
   ee_addr_a <= std_logic_vector(to_unsigned(a_ee, 11));
   ee_data_a <= p_wdata(7 downto 0)   when p_be(0) = '1' else
                p_wdata(15 downto 8)  when p_be(1) = '1' else
                p_wdata(23 downto 16) when p_be(2) = '1' else
                p_wdata(31 downto 24);   -- lowest enabled lane, as lane_byte
   ee_addr_b <= std_logic_vector(ee_addr);

   iee : entity work.dpram
   generic map (addr_width => 11, data_width => 8)
   port map
   (
      clock_a   => clk,
      address_a => ee_addr_a,
      data_a    => ee_data_a,
      wren_a    => ee_wr,
      q_a       => ee_q,
      clock_b   => clk,
      address_b => ee_addr_b,
      data_b    => ee_wdata,
      wren_b    => ee_we,
      q_b       => ee_rdata
   );

   -- NVRAM copy: port B (shell load, power-up erase) has priority; the CPU
   -- does not write while the shell loads (the core is held in reset)
   nv_we    <= ee_we or ee_wr;
   nv_waddr <= ee_addr_b when ee_we = '1' else ee_addr_a;
   nv_wdata <= ee_wdata  when ee_we = '1' else ee_data_a;

   process (clk)
   begin
      if rising_edge(clk) then
         if (nv_we = '1' and nv_waddr(0) = '0') then
            nv_lo(to_integer(unsigned(nv_waddr(10 downto 1)))) <= nv_wdata;
         end if;
         if (nv_we = '1' and nv_waddr(0) = '1') then
            nv_hi(to_integer(unsigned(nv_waddr(10 downto 1)))) <= nv_wdata;
         end if;
         if (ee_wr = '1') then
            cdc_tx_nvtog <= not cdc_tx_nvtog;
         end if;
      end if;
   end process;

   process (nv_clk)
   begin
      if rising_edge(nv_clk) then
         nv_q <= nv_hi(to_integer(nv_addr)) & nv_lo(to_integer(nv_addr));
      end if;
   end process;

   nv_wtog <= cdc_tx_nvtog;

   -- mailbox: one port with byte enables
   process (clk)
   begin
      if rising_edge(clk) then
         if (mb_wr = '1') then
            if (p_be(0) = '1') then mbox_lo(a_mb) <= p_wdata( 7 downto  0); end if;
            if (p_be(2) = '1') then mbox_hi(a_mb) <= p_wdata(23 downto 16); end if;
         end if;
         mb_q <= mbox_hi(a_mb) & mbox_lo(a_mb);
      end if;
   end process;

   ee_busy <= '1' when ee_timer /= 0 else '0';

   process (clk)
      variable r : std_logic_vector(31 downto 0);
   begin
      if rising_edge(clk) then
         ack     <= '0';
         p_valid <= '0';

         if (ee_timer > 0) then
            ee_timer <= ee_timer - 1;
         end if;

         if (reset = '1') then
            znsecsel <= (others => '0');
            coin     <= (others => '0');
            spuhack  <= '0';
            ee_timer <= 0;
         elsif (req = '1') then
            p_valid <= '1';
            p_we    <= we;
            p_addr  <= addr;
            p_be    <= be;
            p_wdata <= wdata;
         elsif (p_valid = '1') then
            ack <= '1';
            r   := (others => '0');
            if (p_we = '1') then
               if (p_addr(23 downto 2) = x"A1030" & "00" and p_be(0) = '1') then znsecsel <= p_wdata(7 downto 0); end if;
               if (p_addr(23 downto 2) = x"A2000" & "00" and p_be(0) = '1') then coin     <= p_wdata(7 downto 0); end if;
               if (p_addr(23 downto 11) = x"AF0" & '0' and ee_timer = 0) then
                  ee_timer <= WRITE_CYCLES;
                  ee_last  <= ee_data_a;   -- same lowest-enabled-lane byte (Quartus 17: no signal-bounded slice)
               end if;
            else
               case to_integer(p_addr(23 downto 2)) is
                  when 16#A00000# / 4 => r(7 downto 0) := in_p1;
                  when 16#A00100# / 4 => r(7 downto 0) := in_p2;
                  when 16#A00200# / 4 => r(7 downto 0) := in_service;
                  when 16#A00300# / 4 => r(7 downto 0) := in_system;
                  when 16#A10000# / 4 => r(7 downto 0) := x"FF";
                  when 16#A10100# / 4 => r(7 downto 0) := x"FF";
                  when 16#A10200# / 4 => r(7 downto 0) := BOARDCFG;
                  when 16#A10300# / 4 => r(7 downto 0) := znsecsel;
                  when 16#A20000# / 4 => r(7 downto 0) := coin;
                  when 16#A60000# / 4 =>
                     if (p_be(1 downto 0) /= "00") then
                        if (SPU_STATUS = 1) then
                           r(3) := '1';
                        else
                           r(3) := not spuhack;
                           spuhack <= not spuhack;
                        end if;
                     end if;
                  when 16#B20000# / 4 | 16#B20004# / 4 => r := x"FFFFFFFF";
                  when others =>
                     if (p_addr(23 downto 11) = x"AF0" & '0') then
                        if (ee_timer /= 0) then
                           r := (ee_last xor x"80") & (ee_last xor x"80") & (ee_last xor x"80") & (ee_last xor x"80");
                        else
                           r := ee_q & ee_q & ee_q & ee_q;
                        end if;
                     elsif (p_addr(23 downto 9) = x"BE0" & "000") then
                        r := x"00" & mb_q(15 downto 8) & x"00" & mb_q(7 downto 0);
                     end if;
               end case;
            end if;
            -- only the enabled lanes carry data
            for i in 0 to 3 loop
               if (p_be(i) = '0') then r(8 * i + 7 downto 8 * i) := x"00"; end if;
            end loop;
            rdata <= r;
         end if;
      end if;
   end process;

end architecture;
