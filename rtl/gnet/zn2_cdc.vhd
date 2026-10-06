-- Crossings of the ZN-2 board when it runs in the CPU group (psx_top
-- ZN2_BOARD = 1 with CPU_CLK_SPLIT = 1; docs/r1_cpu_domain_design.md,
-- section "ZN-2 layer in the CPU group").
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
-- zn2_board (gnet_fc, zn2_io, zn_sio0, CAT702, znmcu, EEPROM) runs on clk_cpu
-- with memorymux; zn2_cardmem stays on clk2x with the DDR3 arbiter; hps_io and
-- PSX.sv's loader stay on clk1x. Signal prefixes: c_ clk_cpu, p_ clk1x,
-- p2_ clk2x. Built only from rtl/gnet/cdc (cdc_tx_* sources, cdc.sdc).
--
--   inputs   P1, P2, SERVICE, SYSTEM, DSW, JP1, card present, key valid:
--            registered on clk1x, cdc_sync into clk_cpu (independent bits)
--   loader   CAT702 keys, card metadata, EEPROM words (PSX.sv zn_ld_*):
--            cdc_fifo 16 x 29 (M10K) from clk1x; the CPU side issues one
--            word every second cycle, the spacing zn2_board's byte split
--            needs (low byte with ld_wr, high byte in the next cycle).
--            p_ld_busy (clk1x, registered) is high while the write side
--            counts LD_BUSY_AT words or more; PSX.sv holds ioctl_wait on it,
--            so hps_io cannot overrun the FIFO whatever the HPS rate
--   C18      card memory port, gnet_ata (clk_cpu) to zn2_cardmem (clk2x):
--            cdc_handshake carrying we, address and write data, the read
--            word back. gnet_ata holds its request until the ack and drops
--            it in the next cycle; the CPU side answers with a one-cycle ack
--            and waits for the drop, the clk2x side replays the request to
--            zn2_cardmem with its own handshake (request held until cm_ack,
--            then waits until cm_ack falls: zn2_cardmem holds it two clk2x
--            cycles and then waits for the request to drop)
--   watchdog gnet_ctrl's one-cycle reset pulse, cdc_pulse to clk1x (PSX.sv
--            stretches it to 256 cycles)
--   coin     coin counters and lockouts, cdc_sync to clk1x
-- C19 (the card image download) is not a crossing here: the download comes
-- from hps_io on clk1x and zn2_cardmem runs on clk2x, both in the PS1 group,
-- as without the split.
--
-- Resets: none of the crossings is reset. The loader is written while the
-- downloads hold the core in reset, so its FIFO must not be; the card port
-- handshake would lose its toggle agreement if one side were reset alone.
-- Instead each side finishes what it started: the clk2x side always
-- completes a zn2_cardmem access, and the CPU side waits for the answer of a
-- request it has sent even when zn2_board's reset (c_board_rst) comes in
-- between, and then drops that answer instead of acknowledging it. All
-- registers start from their declared values at configuration.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cdc_pkg.all;

entity zn2_cdc is
   generic
   (
      SIM_META_WINDOW : time := 0 ns;
      LD_BUSY_AT      : natural := 12     -- loader FIFO words that raise p_ld_busy (of 16)
   );
   port
   (
      clk_cpu          : in  std_logic;
      clk1x            : in  std_logic;
      clk2x            : in  std_logic;

      c_board_rst      : in  std_logic;   -- zn2_board's reset (psx_top reset_intern, CPU group)

      -- board inputs: clk1x (PSX.sv) to clk_cpu
      p_in_p1          : in  std_logic_vector(7 downto 0);
      p_in_p2          : in  std_logic_vector(7 downto 0);
      p_in_service     : in  std_logic_vector(7 downto 0);
      p_in_system      : in  std_logic_vector(7 downto 0);
      p_dsw            : in  std_logic_vector(3 downto 0);
      p_jp1            : in  std_logic;
      p_card_present   : in  std_logic;
      p_key_valid      : in  std_logic;
      c_in_p1          : out std_logic_vector(7 downto 0);
      c_in_p2          : out std_logic_vector(7 downto 0);
      c_in_service     : out std_logic_vector(7 downto 0);
      c_in_system      : out std_logic_vector(7 downto 0);
      c_dsw            : out std_logic_vector(3 downto 0);
      c_jp1            : out std_logic;
      c_card_present   : out std_logic;
      c_key_valid      : out std_logic;

      -- loader: clk1x to clk_cpu
      p_ld_wr          : in  std_logic;
      p_ld_target      : in  std_logic_vector(1 downto 0);
      p_ld_addr        : in  unsigned(10 downto 0);
      p_ld_data        : in  std_logic_vector(15 downto 0);
      p_ld_overflow    : out std_logic;   -- a word arrived with the FIFO full (lost)
      p_ld_busy        : out std_logic;   -- hold the loader (ioctl_wait)
      c_ld_wr          : out std_logic;
      c_ld_target      : out std_logic_vector(1 downto 0);
      c_ld_addr        : out unsigned(10 downto 0);
      c_ld_data        : out std_logic_vector(15 downto 0);

      -- watchdog and coin: clk_cpu to clk1x
      c_wd_reset       : in  std_logic;
      p_wd_reset       : out std_logic;
      c_coin           : in  std_logic_vector(7 downto 0);
      p_coin           : out std_logic_vector(7 downto 0);

      -- card memory port (C18): gnet_ata side on clk_cpu
      c_cm_req         : in  std_logic;
      c_cm_we          : in  std_logic;
      c_cm_addr        : in  std_logic_vector(24 downto 0);
      c_cm_wdata       : in  std_logic_vector(15 downto 0);
      c_cm_ack         : out std_logic;
      c_cm_rdata       : out std_logic_vector(15 downto 0);
      -- zn2_cardmem side on clk2x
      p2_cm_req        : out std_logic;
      p2_cm_we         : out std_logic;
      p2_cm_addr       : out std_logic_vector(24 downto 0);
      p2_cm_wdata      : out std_logic_vector(15 downto 0);
      p2_cm_ack        : in  std_logic;
      p2_cm_rdata      : in  std_logic_vector(15 downto 0)
   );
end entity;

architecture rtl of zn2_cdc is

   -- crossing sources (cdc.sdc)
   signal cdc_tx_in     : std_logic_vector(35 downto 0) := (others => '1');
   signal cdc_tx_flags  : std_logic_vector(2 downto 0) := (others => '0');
   signal cdc_tx_coin   : std_logic_vector(7 downto 0) := (others => '0');
   attribute altera_attribute : string;
   attribute altera_attribute of cdc_tx_in    : signal is CDC_ATTR_KEEP;
   attribute altera_attribute of cdc_tx_flags : signal is CDC_ATTR_KEEP;
   attribute altera_attribute of cdc_tx_coin  : signal is CDC_ATTR_KEEP;

   signal in_s          : std_logic_vector(35 downto 0);
   signal flags_s       : std_logic_vector(2 downto 0);

   -- loader FIFO
   signal ld_wdata      : std_logic_vector(28 downto 0);
   signal ld_rdata      : std_logic_vector(28 downto 0);
   signal ld_empty      : std_logic;
   signal ld_wcount     : std_logic_vector(4 downto 0);
   signal ld_busy_r     : std_logic := '0';
   signal ld_pop        : std_logic;
   signal ld_wr_r       : std_logic := '0';
   signal ld_target_r   : std_logic_vector(1 downto 0) := (others => '0');
   signal ld_addr_r     : unsigned(10 downto 0) := (others => '0');
   signal ld_data_r     : std_logic_vector(15 downto 0) := (others => '0');

   -- card memory, CPU side
   type t_cstate is (C_IDLE, C_WAIT, C_HOLD);
   signal cs            : t_cstate := C_IDLE;
   signal c_stale       : std_logic := '0';
   signal c_start       : std_logic;
   signal c_req_data    : std_logic_vector(41 downto 0);
   signal c_busy        : std_logic;
   signal c_done        : std_logic;
   signal c_rsp         : std_logic_vector(15 downto 0);
   signal c_ack_r       : std_logic := '0';
   signal c_rdata_r     : std_logic_vector(15 downto 0) := (others => '0');

   -- card memory, clk2x side
   type t_pstate is (P_IDLE, P_REQ, P_DRAIN);
   signal ps            : t_pstate := P_IDLE;
   signal p_have        : std_logic := '0';
   signal p_valid       : std_logic;
   signal p_req_data    : std_logic_vector(41 downto 0);
   signal p_ack_r       : std_logic := '0';
   signal p_rsp_r       : std_logic_vector(15 downto 0) := (others => '0');
   signal p_req_r       : std_logic := '0';
   signal p_we_r        : std_logic := '0';
   signal p_addr_r      : std_logic_vector(24 downto 0) := (others => '0');
   signal p_wdata_r     : std_logic_vector(15 downto 0) := (others => '0');

begin

   ---------------------------------------------------------------- inputs
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         cdc_tx_in    <= p_in_p1 & p_in_p2 & p_in_service & p_in_system & p_dsw;
         cdc_tx_flags <= p_jp1 & p_card_present & p_key_valid;
      end if;
   end process;

   u_in : entity work.cdc_sync
      generic map (WIDTH => 36, INIT => '1', SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 201)
      port map (clk => clk_cpu, d => cdc_tx_in, q => in_s);

   u_flags : entity work.cdc_sync
      generic map (WIDTH => 3, INIT => '0', SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 203)
      port map (clk => clk_cpu, d => cdc_tx_flags, q => flags_s);

   c_in_p1        <= in_s(35 downto 28);
   c_in_p2        <= in_s(27 downto 20);
   c_in_service   <= in_s(19 downto 12);
   c_in_system    <= in_s(11 downto 4);
   c_dsw          <= in_s(3 downto 0);
   c_jp1          <= flags_s(2);
   c_card_present <= flags_s(1);
   c_key_valid    <= flags_s(0);

   ---------------------------------------------------------------- loader
   ld_wdata <= p_ld_target & std_logic_vector(p_ld_addr) & p_ld_data;

   u_ld : entity work.cdc_fifo
      generic map (DATA_W => 29, ADDR_W => 4, FWFT => true, RAM_STYLE => "M10K, no_rw_check",
                   SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 205)
      port map (
         wr_clk      => clk1x,
         wr_en       => p_ld_wr,
         wr_data     => ld_wdata,
         wr_full     => open,
         wr_count    => ld_wcount,
         wr_overflow => p_ld_overflow,
         rd_clk      => clk_cpu,
         rd_en       => ld_pop,
         rd_data     => ld_rdata,
         rd_empty    => ld_empty,
         rd_valid    => open,
         rd_count    => open,
         rd_underflow => open);

   process (clk1x)
   begin
      if rising_edge(clk1x) then
         if unsigned(ld_wcount) >= LD_BUSY_AT then
            ld_busy_r <= '1';
         else
            ld_busy_r <= '0';
         end if;
      end if;
   end process;
   p_ld_busy <= ld_busy_r;

   -- one word every second cycle at most
   ld_pop <= '1' when (ld_empty = '0' and ld_wr_r = '0') else '0';

   process (clk_cpu)
   begin
      if rising_edge(clk_cpu) then
         ld_wr_r <= ld_pop;
         if (ld_pop = '1') then
            ld_target_r <= ld_rdata(28 downto 27);
            ld_addr_r   <= unsigned(ld_rdata(26 downto 16));
            ld_data_r   <= ld_rdata(15 downto 0);
         end if;
      end if;
   end process;

   c_ld_wr     <= ld_wr_r;
   c_ld_target <= ld_target_r;
   c_ld_addr   <= ld_addr_r;
   c_ld_data   <= ld_data_r;

   ---------------------------------------------------------------- watchdog, coin
   u_wd : entity work.cdc_pulse
      generic map (CNT_W => 1, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 207)
      port map (src_clk => clk_cpu, src_pulse => c_wd_reset, dst_clk => clk1x, dst_pulse => p_wd_reset);

   process (clk_cpu)
   begin
      if rising_edge(clk_cpu) then
         cdc_tx_coin <= c_coin;
      end if;
   end process;

   u_coin : entity work.cdc_sync
      generic map (WIDTH => 8, INIT => '0', SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 209)
      port map (clk => clk1x, d => cdc_tx_coin, q => p_coin);

   ---------------------------------------------------------------- C18, CPU side
   c_start <= '1' when (cs = C_IDLE and c_cm_req = '1' and c_board_rst = '0' and c_busy = '0') else '0';

   process (clk_cpu)
   begin
      if rising_edge(clk_cpu) then
         c_ack_r <= '0';
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
                  if (c_stale = '0' and c_board_rst = '0') then
                     c_ack_r   <= '1';
                     c_rdata_r <= c_rsp;
                     cs        <= C_HOLD;
                  else
                     cs        <= C_IDLE;   -- answer to a request from before a reset: dropped
                  end if;
               end if;

            when C_HOLD =>
               -- gnet_ata drops its request in the cycle after the ack
               if (c_cm_req = '0' or c_board_rst = '1') then
                  cs <= C_IDLE;
               end if;
         end case;
      end if;
   end process;

   c_cm_ack   <= c_ack_r;
   c_cm_rdata <= c_rdata_r;

   c_req_data <= c_cm_we & c_cm_addr & c_cm_wdata;   -- a signal: Quartus 17 and expressions in port maps

   u_cm : entity work.cdc_handshake
      generic map (REQ_W => 42, RSP_W => 16, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 211)
      port map (
         src_clk      => clk_cpu,
         src_start    => c_start,
         src_req_data => c_req_data,
         src_busy     => c_busy,
         src_done     => c_done,
         src_rsp_data => c_rsp,
         dst_clk      => clk2x,
         dst_valid    => p_valid,
         dst_req_data => p_req_data,
         dst_pending  => open,
         dst_ack      => p_ack_r,
         dst_rsp_data => p_rsp_r);

   ---------------------------------------------------------------- C18, clk2x side
   process (clk2x)
   begin
      if rising_edge(clk2x) then
         p_ack_r <= '0';
         if (p_valid = '1') then
            p_have <= '1';
         end if;
         case ps is
            when P_IDLE =>
               if (p_have = '1') then
                  p_have    <= '0';
                  p_req_r   <= '1';
                  p_we_r    <= p_req_data(41);
                  p_addr_r  <= p_req_data(40 downto 16);
                  p_wdata_r <= p_req_data(15 downto 0);
                  ps        <= P_REQ;
               end if;

            when P_REQ =>
               if (p2_cm_ack = '1') then
                  p_req_r <= '0';
                  p_rsp_r <= p2_cm_rdata;
                  p_ack_r <= '1';
                  ps      <= P_DRAIN;
               end if;

            when P_DRAIN =>
               -- zn2_cardmem holds cm_ack for two clk2x cycles, then waits
               -- for the request to drop before it takes the next one
               if (p2_cm_ack = '0') then
                  ps <= P_IDLE;
               end if;
         end case;
      end if;
   end process;

   p2_cm_req   <= p_req_r;
   p2_cm_we    <= p_we_r;
   p2_cm_addr  <= p_addr_r;
   p2_cm_wdata <= p_wdata_r;

end architecture;
