-- ZN-2 board plus G-NET FC PCB (silent build), attached to psx_top.
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
-- docs/zn2_layer_design.md 13. Contents:
--   * bus top: memorymux's zn_* port (expansion 1 and 3, ZN2_MAP = 1) to
--     gnet_fc (flash window, control3, RF5C296 / ATA, control, control2,
--     0x1FB70000) or zn2_io (inputs, board registers, EEPROM, Zoom stub);
--     anything else answers 0
--   * SIO0 (zn_sio0) with the two CAT702 and the znmcu, on the bus_pad port
--   * loader: 16-bit ioctl words split into bytes for the CAT702 keys, the
--     card metadata (IDNT, CIS, KEY) and the EEPROM
--   * EEPROM erase to FFh at power-up (MAME at28c16.cpp nvram_default)
--   * flash storage: gnet_fc's word port to a 32-bit SDRAM port (PSX.sv
--     ch3), U30 at 0x1000000, U27 0x1200000, U56 0x1400000, U55 0x1600000,
--     U29 0x1800000 (byte addresses; flash word n = SDRAM halfword at 2n)
--   * card storage: gnet_fc's word port passed out to zn2_cardmem (DDR3)
--   * Taito Zoom host port (ZOOM = 1): 0x1FB80000-0x1FB80003, 0x1FBA0000,
--     0x1FBC0000 and the mailbox 0x1FBE0000-0x1FBE01FF go out on the zm_*
--     port (request pulse, ack pulse with data, as zn_*) to rtl/gnet/zoom_cdc
--     and the Zoom board (docs/zoom_board_design.md 14); zn2_io keeps the
--     rest of those banks. ZOOM = 0 keeps zn2_io's silent stub for all of it.
-- Everything runs on one clock, the port named clk1x: clk1x at 33.8688 MHz,
-- or clk_cpu at 50 MHz when psx_top's CPU_CLK_SPLIT = 1 (then CLK_HZ =
-- 50,000,000 and sys_tick is the 33.8688 MHz-equivalent tick for the SIO0
-- bit timer). gnet_fc's, zn2_io's and znmcu's timers use CLK_HZ.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity zn2_board is
   generic
   (
      CLK_HZ       : integer := 33868800;
      FLASH_PRESET : integer := 1;   -- gnet_flash timing: 1 = MAME, 2 = 28F160S3 2.7 V, 3 = 28F160S5 (FC PCB part)
      PS1_SIO      : integer := 0;   -- zn_sio0 PS1_TIMING
      SPU_STATUS   : integer := 0;   -- zn2_io SPU_STATUS
      WD_TIMEOUT_S : integer := 8;   -- MB3773 period in seconds (gnet_ctrl.sv)
      ZOOM         : integer := 0    -- 1: Taito Zoom host port on zm_* (else zn2_io's stub)
   );
   port
   (
      clk1x          : in  std_logic;
      ce             : in  std_logic;
      reset          : in  std_logic;
      sys_tick       : in  std_logic := '1';   -- SIO0 bit timer step (zn_sio0)

      -- memorymux zn_* port
      zn_req         : in  std_logic;
      zn_we          : in  std_logic;
      zn_addr        : in  unsigned(23 downto 0);
      zn_be          : in  std_logic_vector(3 downto 0);
      zn_wdata       : in  std_logic_vector(31 downto 0);
      zn_ack         : out std_logic;
      zn_rdata       : out std_logic_vector(31 downto 0);

      -- SIO0 (bus_pad)
      sio_addr       : in  unsigned(3 downto 0);
      sio_dataWrite  : in  std_logic_vector(31 downto 0);
      sio_read       : in  std_logic;
      sio_write      : in  std_logic;
      sio_writeMask  : in  std_logic_vector(3 downto 0);
      sio_dataRead   : out std_logic_vector(31 downto 0);
      sio_irq        : out std_logic;

      -- board inputs and outputs
      in_p1          : in  std_logic_vector(7 downto 0);
      in_p2          : in  std_logic_vector(7 downto 0);
      in_service     : in  std_logic_vector(7 downto 0);
      in_system      : in  std_logic_vector(7 downto 0);
      dsw            : in  std_logic_vector(3 downto 0);
      jp1            : in  std_logic;
      card_present   : in  std_logic;
      key_valid      : in  std_logic;
      coin           : out std_logic_vector(7 downto 0);
      wd_reset       : out std_logic;
      zoom_reset     : out std_logic;

      -- loader: one 16-bit word at an even byte address
      ld_wr          : in  std_logic;
      ld_target      : in  std_logic_vector(1 downto 0);   -- 0 CAT702 keys, 1 card metadata, 2 EEPROM
      ld_addr        : in  unsigned(10 downto 0);
      ld_data        : in  std_logic_vector(15 downto 0);

      -- flash storage (32-bit SDRAM port: one req pulse, ready pulse)
      fl_req         : out std_logic := '0';
      fl_rnw         : out std_logic := '1';
      fl_addr        : out std_logic_vector(26 downto 0) := (others => '0');
      fl_din         : out std_logic_vector(31 downto 0) := (others => '0');
      fl_be          : out std_logic_vector(3 downto 0) := (others => '0');
      fl_ready       : in  std_logic;
      fl_dout        : in  std_logic_vector(31 downto 0);

      -- card storage (word port, request held until ack)
      cm_req         : out std_logic;
      cm_we          : out std_logic;
      cm_addr        : out std_logic_vector(24 downto 0);
      cm_wdata       : out std_logic_vector(15 downto 0);
      cm_ack         : in  std_logic;
      cm_rdata       : in  std_logic_vector(15 downto 0);

      -- debug taps for rtl/gnet/zn_dbg_regs.vhd (docs/hw_debug_overlay.md)
      dbg_wd_kick    : out std_logic;                      -- pulse: watchdog CK falling edge
      dbg_ctrl       : out std_logic_vector(7 downto 0);   -- control register 0x1FB40000
      dbg_sec_cmd    : out std_logic;                      -- pulse: ATA READ/WRITE SECTORS taken

      -- NVRAM save: EEPROM copy read on nv_clk (zn2_io, docs/m4_shell.md 4)
      nv_clk         : in  std_logic := '0';
      nv_addr        : in  unsigned(9 downto 0) := (others => '0');
      nv_q           : out std_logic_vector(15 downto 0);
      nv_wtog        : out std_logic;

      -- Taito Zoom host port (ZOOM = 1): zn_* conventions, request pulse,
      -- fields valid with it, one ack pulse with the read data
      zm_req         : out std_logic;
      zm_we          : out std_logic;
      zm_addr        : out unsigned(23 downto 0);
      zm_be          : out std_logic_vector(3 downto 0);
      zm_wdata       : out std_logic_vector(31 downto 0);
      zm_ack         : in  std_logic := '0';
      zm_rdata       : in  std_logic_vector(31 downto 0) := (others => '0')
   );
end entity;

architecture arch of zn2_board is

   component gnet_fc is
      generic
      (
         CLK_HZ       : integer := 33868800;
         FLASH_PRESET : integer := 1;
         WD_TIMEOUT_S : integer := 8   -- MB3773 period; see gnet_ctrl.sv
      );
      port
      (
         clk          : in  std_logic;
         rst          : in  std_logic;
         jp1          : in  std_logic;
         card_present : in  std_logic;
         cpu_req      : in  std_logic;
         cpu_we       : in  std_logic;
         cpu_addr     : in  std_logic_vector(23 downto 0);
         cpu_be       : in  std_logic_vector(3 downto 0);
         cpu_wdata    : in  std_logic_vector(31 downto 0);
         cpu_ack      : out std_logic;
         cpu_rdata    : out std_logic_vector(31 downto 0);
         cpu_hit      : out std_logic;
         zoom_reset   : out std_logic;
         wd_reset     : out std_logic;
         fmem_req     : out std_logic;
         fmem_we      : out std_logic;
         fmem_chip    : out std_logic_vector(2 downto 0);
         fmem_addr    : out std_logic_vector(20 downto 0);
         fmem_wdata   : out std_logic_vector(15 downto 0);
         fmem_ack     : in  std_logic;
         fmem_rdata   : in  std_logic_vector(15 downto 0);
         flash_busy   : out std_logic_vector(4 downto 0);
         cmem_req     : out std_logic;
         cmem_we      : out std_logic;
         cmem_addr    : out std_logic_vector(24 downto 0);
         cmem_wdata   : out std_logic_vector(15 downto 0);
         cmem_ack     : in  std_logic;
         cmem_rdata   : in  std_logic_vector(15 downto 0);
         meta_we      : in  std_logic;
         meta_addr    : in  std_logic_vector(9 downto 0);
         meta_wdata   : in  std_logic_vector(7 downto 0);
         key_valid    : in  std_logic;
         dirty_set    : out std_logic;
         dirty_hunk   : out std_logic_vector(13 downto 0);
         dirty_raddr  : in  std_logic_vector(13 downto 0);
         dirty_rdata  : out std_logic;
         dirty_clear  : in  std_logic;
         card_reset   : out std_logic;
         win_mismatch : out std_logic;
         dbg_wd_kick  : out std_logic;
         dbg_ctrl     : out std_logic_vector(7 downto 0);
         dbg_sec_cmd  : out std_logic
      );
   end component;

   -- bus top
   signal sel_fc, sel_io     : std_logic;
   signal sel_zm             : std_logic := '0';
   signal zm_hit             : std_logic;
   signal fc_req, io_req     : std_logic;
   signal fc_ack, io_ack     : std_logic;
   signal fc_rdata, io_rdata : std_logic_vector(31 downto 0);
   signal io_hit             : std_logic;
   signal none_ack           : std_logic := '0';

   -- SIO0 devices
   signal znsecsel           : std_logic_vector(7 downto 0);
   signal bit_stb, txd       : std_logic;
   signal out0, out1, outm   : std_logic;
   signal dsr_n, mcu_sel_n   : std_logic;
   signal rxd_all            : std_logic;

   -- loader byte split
   signal ld_pend            : std_logic := '0';
   signal ld_hi              : std_logic_vector(7 downto 0);
   signal ld_hi_addr         : unsigned(10 downto 0);
   signal ld_hi_tgt          : std_logic_vector(1 downto 0);
   signal b_we               : std_logic;
   signal b_addr             : unsigned(10 downto 0);
   signal b_data             : std_logic_vector(7 downto 0);
   signal b_tgt              : std_logic_vector(1 downto 0);
   signal key_we             : std_logic_vector(1 downto 0);
   signal meta_we            : std_logic;

   -- EEPROM power-up erase
   signal ee_init            : std_logic := '0';
   signal ee_init_addr       : unsigned(10 downto 0) := (others => '0');
   signal ee_addr            : unsigned(10 downto 0);
   signal ee_we              : std_logic;
   signal ee_wdata           : std_logic_vector(7 downto 0);
   signal ee_rdata           : std_logic_vector(7 downto 0);
   signal ee_busy            : std_logic;

   -- flash storage adapter
   type t_fstate is (F_IDLE, F_WAIT, F_HOLD);
   signal fstate             : t_fstate := F_IDLE;
   signal fmem_req, fmem_we  : std_logic;
   signal fmem_ack           : std_logic := '0';
   signal fmem_chip          : std_logic_vector(2 downto 0);
   signal fmem_addr          : std_logic_vector(20 downto 0);
   signal fmem_wdata         : std_logic_vector(15 downto 0);
   signal fmem_rdata         : std_logic_vector(15 downto 0) := (others => '0');
   signal f_lane             : std_logic := '0';

   function gnet_hit(a : unsigned(23 downto 0)) return std_logic is
   begin
      if (a < x"800000") or (a(23 downto 16) = x"B0") or
         (a(23 downto 2) = x"A3000" & "00") or (a(23 downto 2) = x"B4000" & "00") or
         (a(23 downto 2) = x"B6000" & "00") or (a(23 downto 2) = x"B7000" & "00") then
         return '1';
      end if;
      return '0';
   end function;

   -- Taito Zoom ports (taitogn.cpp 483-487; rtl/zoom/zoom_host.sv decodes the same)
   function zoom_hit(a : unsigned(23 downto 0)) return std_logic is
   begin
      if (a(23 downto 2) = x"B8000" & "00") or (a(23 downto 2) = x"BA000" & "00") or
         (a(23 downto 2) = x"BC000" & "00") or (a(23 downto 9) = x"BE0" & "000") then
         return '1';
      end if;
      return '0';
   end function;

begin

   ---------------------------------------------------------------- bus top
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         none_ack <= '0';
         if (reset = '1') then
            sel_fc <= '0';
            sel_io <= '0';
            sel_zm <= '0';
         elsif (zn_req = '1') then
            sel_fc <= gnet_hit(zn_addr);
            sel_zm <= zm_hit;
            sel_io <= (not gnet_hit(zn_addr)) and (not zm_hit) and io_hit;
            if (gnet_hit(zn_addr) = '0' and zm_hit = '0' and io_hit = '0') then
               none_ack <= '1';
            end if;
         end if;
      end if;
   end process;

   zm_hit   <= zoom_hit(zn_addr) when (ZOOM = 1) else '0';
   fc_req   <= zn_req and gnet_hit(zn_addr);
   io_req   <= zn_req and (not gnet_hit(zn_addr)) and (not zm_hit) and io_hit;
   zn_ack   <= (fc_ack and sel_fc) or (io_ack and sel_io) or (zm_ack and sel_zm) or none_ack;
   zn_rdata <= fc_rdata when (sel_fc = '1') else io_rdata when (sel_io = '1') else
               zm_rdata when (sel_zm = '1') else (others => '0');

   zm_req   <= zn_req and zm_hit;
   zm_we    <= zn_we;
   zm_addr  <= zn_addr;
   zm_be    <= zn_be;
   zm_wdata <= zn_wdata;

   ifc : gnet_fc
   generic map (CLK_HZ => CLK_HZ, FLASH_PRESET => FLASH_PRESET, WD_TIMEOUT_S => WD_TIMEOUT_S)
   port map
   (
      clk          => clk1x,
      rst          => reset,
      jp1          => jp1,
      card_present => card_present,
      cpu_req      => fc_req,
      cpu_we       => zn_we,
      cpu_addr     => std_logic_vector(zn_addr),
      cpu_be       => zn_be,
      cpu_wdata    => zn_wdata,
      cpu_ack      => fc_ack,
      cpu_rdata    => fc_rdata,
      cpu_hit      => open,
      zoom_reset   => zoom_reset,
      wd_reset     => wd_reset,
      fmem_req     => fmem_req,
      fmem_we      => fmem_we,
      fmem_chip    => fmem_chip,
      fmem_addr    => fmem_addr,
      fmem_wdata   => fmem_wdata,
      fmem_ack     => fmem_ack,
      fmem_rdata   => fmem_rdata,
      flash_busy   => open,
      cmem_req     => cm_req,
      cmem_we      => cm_we,
      cmem_addr    => cm_addr,
      cmem_wdata   => cm_wdata,
      cmem_ack     => cm_ack,
      cmem_rdata   => cm_rdata,
      meta_we      => meta_we,
      meta_addr    => std_logic_vector(b_addr(9 downto 0)),
      meta_wdata   => b_data,
      key_valid    => key_valid,
      dirty_set    => open,
      dirty_hunk   => open,
      dirty_raddr  => (others => '0'),
      dirty_rdata  => open,
      dirty_clear  => '0',
      card_reset   => open,
      win_mismatch => open,
      dbg_wd_kick  => dbg_wd_kick,
      dbg_ctrl     => dbg_ctrl,
      dbg_sec_cmd  => dbg_sec_cmd
   );

   iio : entity work.zn2_io
   generic map (CLK_HZ => CLK_HZ, SPU_STATUS => SPU_STATUS)
   port map
   (
      clk        => clk1x,
      reset      => reset,
      req        => io_req,
      we         => zn_we,
      addr       => zn_addr,
      be         => zn_be,
      wdata      => zn_wdata,
      ack        => io_ack,
      rdata      => io_rdata,
      hit        => io_hit,
      in_p1      => in_p1,
      in_p2      => in_p2,
      in_service => in_service,
      in_system  => in_system,
      znsecsel   => znsecsel,
      coin       => coin,
      ee_addr    => ee_addr,
      ee_we      => ee_we,
      ee_wdata   => ee_wdata,
      ee_rdata   => ee_rdata,
      ee_busy    => ee_busy,
      nv_clk     => nv_clk,
      nv_addr    => nv_addr,
      nv_q       => nv_q,
      nv_wtog    => nv_wtog
   );

   ---------------------------------------------------------------- SIO0
   isio : entity work.zn_sio0
   generic map (PS1_TIMING => PS1_SIO)
   port map
   (
      clk1x         => clk1x,
      ce            => ce,
      reset         => reset,
      sys_tick      => sys_tick,
      bus_addr      => sio_addr,
      bus_dataWrite => sio_dataWrite,
      bus_read      => sio_read,
      bus_write     => sio_write,
      bus_writeMask => sio_writeMask,
      bus_dataRead  => sio_dataRead,
      irqRequest    => sio_irq,
      bit_stb       => bit_stb,
      txd           => txd,
      rxd           => rxd_all,
      dsr_n         => dsr_n
   );

   rxd_all <= out0 and out1 and outm;   -- zn.h 39: RXD is the AND of the three outputs

   icat0 : entity work.zn_cat702
   port map (clk => clk1x, reset => reset, key_we => key_we(0), key_addr => b_addr(2 downto 0), key_data => b_data,
             sel_n => znsecsel(2), bit_stb => bit_stb, txd => txd, dataout => out0);
   icat1 : entity work.zn_cat702
   port map (clk => clk1x, reset => reset, key_we => key_we(1), key_addr => b_addr(2 downto 0), key_data => b_data,
             sel_n => znsecsel(3), bit_stb => bit_stb, txd => txd, dataout => out1);

   mcu_sel_n <= '0' when (znsecsel and x"8C") = x"8C" else '1';
   imcu : entity work.znmcu
   generic map (CLK_HZ => CLK_HZ)
   port map (clk => clk1x, reset => reset, sel_n => mcu_sel_n, analog_rd => znsecsel(4), trackball_rd => znsecsel(5),
             bit_stb => bit_stb, txd => outm, dsr_n => dsr_n, dsw => dsw);

   ---------------------------------------------------------------- loader
   -- low byte in the cycle of ld_wr, high byte in the next
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         ld_pend <= '0';
         if (ld_wr = '1') then
            ld_pend    <= '1';
            ld_hi      <= ld_data(15 downto 8);
            ld_hi_addr <= ld_addr + 1;
            ld_hi_tgt  <= ld_target;
         end if;
      end if;
   end process;

   b_we   <= ld_wr or ld_pend;
   b_addr <= ld_addr when (ld_wr = '1') else ld_hi_addr;
   b_data <= ld_data(7 downto 0) when (ld_wr = '1') else ld_hi;
   b_tgt  <= ld_target when (ld_wr = '1') else ld_hi_tgt;

   key_we(0) <= '1' when (b_we = '1' and b_tgt = "00" and b_addr(10 downto 3) = 0) else '0';
   key_we(1) <= '1' when (b_we = '1' and b_tgt = "00" and b_addr(10 downto 3) = 1) else '0';
   meta_we   <= '1' when (b_we = '1' and b_tgt = "01" and b_addr(10) = '0') else '0';

   -- EEPROM port B: erase at power-up, then the loader
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         if (ee_init = '0') then
            ee_init_addr <= ee_init_addr + 1;
            if (ee_init_addr = 2047) then
               ee_init <= '1';
            end if;
         end if;
      end if;
   end process;

   ee_addr  <= ee_init_addr when (ee_init = '0') else b_addr;
   ee_we    <= '1' when (ee_init = '0') or (b_we = '1' and b_tgt = "10") else '0';
   ee_wdata <= x"FF" when (ee_init = '0') else b_data;

   ---------------------------------------------------------------- flash storage
   process (clk1x)
      variable base : unsigned(26 downto 0);
   begin
      if rising_edge(clk1x) then
         fl_req   <= '0';
         fmem_ack <= '0';
         if (reset = '1' and fstate /= F_WAIT) then
            fstate <= F_IDLE;
         else
            case fstate is
               when F_IDLE =>
                  if (fmem_req = '1') then
                     case fmem_chip is
                        when "000"  => base := to_unsigned(16#1000000#, 27);
                        when "001"  => base := to_unsigned(16#1200000#, 27);
                        when "010"  => base := to_unsigned(16#1400000#, 27);
                        when "011"  => base := to_unsigned(16#1600000#, 27);
                        when others => base := to_unsigned(16#1800000#, 27);
                     end case;
                     fl_addr <= std_logic_vector(base + (unsigned(fmem_addr(20 downto 1)) & "00"));
                     f_lane  <= fmem_addr(0);
                     fl_rnw  <= not fmem_we;
                     fl_din  <= fmem_wdata & fmem_wdata;
                     -- reads with all byte enables: sdram.sv puts ~be[1:0] on
                     -- A12:A11 = DQMH:DQML for the READ (sdram.sv 88, 476, 490)
                     -- and the chip applies read DQM two clocks later to both
                     -- words of the burst, so a lane-1 read with be 1100 had
                     -- its data masked (undriven) on the board; the lane is
                     -- picked from f_lane. Writes keep the lane enables.
                     if (fmem_we = '0') then
                        fl_be <= "1111";
                     elsif (fmem_addr(0) = '1') then
                        fl_be <= "1100";
                     else
                        fl_be <= "0011";
                     end if;
                     fl_req  <= '1';
                     fstate  <= F_WAIT;
                  end if;
               when F_WAIT =>
                  if (fl_ready = '1') then
                     if (f_lane = '1') then fmem_rdata <= fl_dout(31 downto 16); else fmem_rdata <= fl_dout(15 downto 0); end if;
                     fmem_ack <= '1';
                     fstate   <= F_HOLD;
                  end if;
               when F_HOLD =>
                  -- gnet_flash drops its request when it sees the ack
                  if (fmem_req = '0') then
                     fstate <= F_IDLE;
                  end if;
            end case;
         end if;
      end if;
   end process;

end architecture;
