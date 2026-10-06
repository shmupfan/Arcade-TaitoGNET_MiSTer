-- Integration bench top (sim/zoomlink/build.sh): the main-CPU to Taito Zoom
-- path of GNET_Z1_ZOOM as psx_top (gzn2c, gzoom) and PSX.sv (GNET_ZOOM,
-- GNET_ZOOM_SDRAM) wire it, without the PS1 core:
--   zn_* bus (memorymux side, clk_cpu) -> zn2_board (ZOOM = 1, gnet_fc with
--   the control register) -> zm_* -> zoom_cdc -> zoom_board (clk1x, clk2x)
--   zoom_board m_* -> zoom_sdram_link -> zn2_ch3_arb port c -> ch3_* (the
--   SDRAM model in tb_zoomlink.cpp, clk_cpu); zn2_board's flash port on
--   port b, port a (downloads) idle.
-- GHDL synthesises this file and the VHDL below it to Verilog; gnet_fc and
-- zoom_board stay components and are bound to their SystemVerilog sources
-- by Verilator.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity zl_vtop is
   generic (
      TMS_MAME   : integer := 0;    -- zoom_board TMS_MAME: 1 = the TMS57002 set bit-exact with MAME 0.288
      TIMER_X    : integer := 0     -- zoom_board TIMER_EXACT: 1 = MAME's timer phase
   );
   port (
      clk_cpu    : in  std_logic;
      clk1x      : in  std_logic;
      clk2x      : in  std_logic;
      c_rst      : in  std_logic;   -- psx_top reset_intern (CPU group)
      p_rst      : in  std_logic;   -- psx_top reset_intern_p (clk1x)

      zn_req     : in  std_logic;
      zn_we      : in  std_logic;
      zn_addr    : in  std_logic_vector(23 downto 0);
      zn_be      : in  std_logic_vector(3 downto 0);
      zn_wdata   : in  std_logic_vector(31 downto 0);
      zn_ack     : out std_logic;
      zn_rdata   : out std_logic_vector(31 downto 0);

      ch3_req    : out std_logic;
      ch3_addr   : out std_logic_vector(26 downto 0);
      ch3_din    : out std_logic_vector(31 downto 0);
      ch3_rnw    : out std_logic;
      ch3_be     : out std_logic_vector(3 downto 0);
      ch3_ready  : in  std_logic;
      ch3_dout   : in  std_logic_vector(31 downto 0);

      aud_l      : out std_logic_vector(15 downto 0);
      aud_r      : out std_logic_vector(15 downto 0);
      flags      : out std_logic_vector(7 downto 0);
      zrst_p     : out std_logic;   -- control bit 4 as zoom_board sees it
      dbg_insn   : out std_logic;
      dbg_pc     : out std_logic_vector(23 downto 0);
      dbg_psw    : out std_logic_vector(15 downto 0);
      dbg_mdr    : out std_logic_vector(15 downto 0);
      dbg_regs   : out std_logic_vector(191 downto 0);
      m_req_o    : out std_logic;
      m_rvalid_o : out std_logic
   );
end entity;

architecture rtl of zl_vtop is

   component zoom_board is
   generic
   (
      CLK_H       : integer := 4;
      PACE_CAP    : integer := 1024;
      ZSG_INFL    : integer := 4;
      TIMER_EXACT : integer := 0;
      DEBUG       : integer := 0;
      TMS_MAME    : integer := 0
   );
   port
   (
      clk         : in  std_logic;
      clk2x       : in  std_logic;
      rst         : in  std_logic;
      hclk        : in  std_logic;
      hrst        : in  std_logic;
      zoom_reset  : in  std_logic;
      h_req       : in  std_logic;
      h_we        : in  std_logic;
      h_addr      : in  std_logic_vector(23 downto 0);
      h_be        : in  std_logic_vector(3 downto 0);
      h_wdata     : in  std_logic_vector(31 downto 0);
      h_ack       : out std_logic;
      h_rdata     : out std_logic_vector(31 downto 0);
      h_hit       : out std_logic;
      m_req       : out std_logic;
      m_line      : out std_logic_vector(20 downto 0);
      m_ready     : in  std_logic;
      m_rvalid    : in  std_logic;
      m_rdata     : in  std_logic_vector(63 downto 0);
      prog_inval  : in  std_logic;
      aud_tick    : out std_logic;
      aud_l       : out std_logic_vector(15 downto 0);
      aud_r       : out std_logic_vector(15 downto 0);
      pace_en     : in  std_logic;
      dbg_hold    : in  std_logic;
      dbg_bound   : out std_logic;
      dbg_insn    : out std_logic;
      dbg_pc      : out std_logic_vector(23 downto 0);
      dbg_psw     : out std_logic_vector(15 downto 0);
      dbg_mdr     : out std_logic_vector(15 downto 0);
      dbg_cycles  : out std_logic_vector(47 downto 0);
      dbg_regs    : out std_logic_vector(191 downto 0);
      tb_pin1_ovr : in  std_logic;
      tb_pin1     : in  std_logic;
      tb_ld       : in  std_logic;
      tb_ld_left  : in  std_logic_vector(8 downto 0);
      tb_ld_rem   : in  std_logic_vector(15 downto 0);
      dbg_flags   : out std_logic_vector(7 downto 0)
   );
   end component;

   signal c_zm_req, c_zm_we   : std_logic;
   signal c_zm_addr           : unsigned(23 downto 0);
   signal c_zm_be             : std_logic_vector(3 downto 0);
   signal c_zm_wdata          : std_logic_vector(31 downto 0);
   signal c_zm_ack            : std_logic;
   signal c_zm_rdata          : std_logic_vector(31 downto 0);
   signal c_zoom_reset        : std_logic;
   signal p_h_req, p_h_we     : std_logic;
   signal p_h_addr            : std_logic_vector(23 downto 0);
   signal p_h_be              : std_logic_vector(3 downto 0);
   signal p_h_wdata           : std_logic_vector(31 downto 0);
   signal p_h_ack, p_h_hit    : std_logic;
   signal p_h_rdata           : std_logic_vector(31 downto 0);
   signal p_zoom_reset        : std_logic;
   signal m_req, m_ready      : std_logic;
   signal m_rvalid            : std_logic;
   signal m_line              : std_logic_vector(20 downto 0);
   signal m_rdata             : std_logic_vector(63 downto 0);
   signal fl_req, fl_rnw, fl_ready : std_logic;
   signal fl_addr             : std_logic_vector(26 downto 0);
   signal fl_din              : std_logic_vector(31 downto 0);
   signal fl_be               : std_logic_vector(3 downto 0);
   signal z_req, z_ready      : std_logic;
   signal z_addr              : std_logic_vector(26 downto 0);
   signal sio_rd              : std_logic_vector(31 downto 0);

begin

   izn2_board : entity work.zn2_board
   generic map (CLK_HZ => 50000000, FLASH_PRESET => 1, PS1_SIO => 0, SPU_STATUS => 0, ZOOM => 1)
   port map
   (
      clk1x => clk_cpu, ce => '1', reset => c_rst, sys_tick => '1',
      zn_req => zn_req, zn_we => zn_we, zn_addr => unsigned(zn_addr), zn_be => zn_be, zn_wdata => zn_wdata,
      zn_ack => zn_ack, zn_rdata => zn_rdata,
      sio_addr => (others => '0'), sio_dataWrite => (others => '0'), sio_read => '0', sio_write => '0',
      sio_writeMask => (others => '0'), sio_dataRead => sio_rd, sio_irq => open,
      in_p1 => x"FF", in_p2 => x"FF", in_service => x"FF", in_system => x"FF", dsw => x"F", jp1 => '0',
      card_present => '0', key_valid => '0', coin => open, wd_reset => open, zoom_reset => c_zoom_reset,
      ld_wr => '0', ld_target => "00", ld_addr => (others => '0'), ld_data => (others => '0'),
      fl_req => fl_req, fl_rnw => fl_rnw, fl_addr => fl_addr, fl_din => fl_din, fl_be => fl_be,
      fl_ready => fl_ready, fl_dout => ch3_dout,
      cm_req => open, cm_we => open, cm_addr => open, cm_wdata => open, cm_ack => '0', cm_rdata => (others => '0'),
      zm_req => c_zm_req, zm_we => c_zm_we, zm_addr => c_zm_addr, zm_be => c_zm_be, zm_wdata => c_zm_wdata,
      zm_ack => c_zm_ack, zm_rdata => c_zm_rdata
   );

   izoom_cdc : entity work.zoom_cdc
   port map
   (
      clk_cpu => clk_cpu, clk1x => clk1x, c_board_rst => c_rst, p_board_rst => p_rst,
      c_zm_req => c_zm_req, c_zm_we => c_zm_we, c_zm_addr => c_zm_addr, c_zm_be => c_zm_be, c_zm_wdata => c_zm_wdata,
      c_zm_ack => c_zm_ack, c_zm_rdata => c_zm_rdata,
      p_h_req => p_h_req, p_h_we => p_h_we, p_h_addr => p_h_addr, p_h_be => p_h_be, p_h_wdata => p_h_wdata,
      p_h_ack => p_h_ack, p_h_rdata => p_h_rdata, p_h_hit => p_h_hit,
      c_zoom_reset => c_zoom_reset, p_zoom_reset => p_zoom_reset
   );

   izoom_board : zoom_board
   generic map (CLK_H => 4, PACE_CAP => 1024, ZSG_INFL => 4, TIMER_EXACT => TIMER_X, DEBUG => 0, TMS_MAME => TMS_MAME)
   port map
   (
      clk => clk1x, clk2x => clk2x, rst => p_rst, hclk => clk1x, hrst => p_rst, zoom_reset => p_zoom_reset,
      h_req => p_h_req, h_we => p_h_we, h_addr => p_h_addr, h_be => p_h_be, h_wdata => p_h_wdata,
      h_ack => p_h_ack, h_rdata => p_h_rdata, h_hit => p_h_hit,
      m_req => m_req, m_line => m_line, m_ready => m_ready, m_rvalid => m_rvalid, m_rdata => m_rdata,
      prog_inval => '0', aud_tick => open, aud_l => aud_l, aud_r => aud_r, pace_en => '1', dbg_hold => '0',
      dbg_bound => open, dbg_insn => dbg_insn, dbg_pc => dbg_pc, dbg_psw => dbg_psw, dbg_mdr => dbg_mdr,
      dbg_cycles => open, dbg_regs => dbg_regs,
      tb_pin1_ovr => '0', tb_pin1 => '0', tb_ld => '0', tb_ld_left => (others => '0'), tb_ld_rem => (others => '0'),
      dbg_flags => flags
   );

   izoom_sdram : entity work.zoom_sdram_link
   port map
   (
      clk_cpu => clk_cpu, clk1x => clk1x, p_board_rst => p_rst,
      p_m_req => m_req, p_m_line => m_line, p_m_ready => m_ready, p_m_rvalid => m_rvalid, p_m_rdata => m_rdata,
      c_fl_req => z_req, c_fl_addr => z_addr, c_fl_ready => z_ready, c_fl_dout => ch3_dout
   );

   iarb : entity work.zn2_ch3_arb
   port map
   (
      clk => clk_cpu,
      a_req => '0', a_addr => (others => '0'), a_din => (others => '0'), a_rnw => '1', a_be => "1111", a_ready => open,
      b_req => fl_req, b_addr => fl_addr, b_din => fl_din, b_rnw => fl_rnw, b_be => fl_be, b_ready => fl_ready,
      c_req => z_req, c_addr => z_addr, c_din => (others => '0'), c_rnw => '1', c_be => "1111", c_ready => z_ready,
      ch3_req => ch3_req, ch3_addr => ch3_addr, ch3_din => ch3_din, ch3_rnw => ch3_rnw, ch3_be => ch3_be,
      ch3_ready => ch3_ready
   );

   zrst_p     <= p_zoom_reset;
   m_req_o    <= m_req;
   m_rvalid_o <= m_rvalid;

end architecture;
