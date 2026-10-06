-- Synthesis-only check top for rtl/gnet/cdc (revision GNET_CDC_SYN, target
-- cdcsyn in tools/pc_build.sh): one instance per block in the sizes the
-- 50.000 MHz plan names (C1 16 x 34, C8 8 x 27, a 1024 x 32 read-back FIFO
-- like C3, the C2 handshake, a level group, two pulse synchronisers, the
-- tick accumulator). clk_a stands for clk_cpu, clk_b for clk_1x / clk_2x.
-- All ports are virtual pins. Not part of the core.

library ieee;
use ieee.std_logic_1164.all;

entity cdc_syn_top is
   port (
      clk_a, clk_b, rst_a, rst_b : in std_logic;

      c1_wr_en   : in  std_logic;
      c1_wr_data : in  std_logic_vector(33 downto 0);
      c1_full    : out std_logic;
      c1_rd_en   : in  std_logic;
      c1_rd_data : out std_logic_vector(33 downto 0);
      c1_empty   : out std_logic;

      c8_wr_en   : in  std_logic;
      c8_wr_data : in  std_logic_vector(26 downto 0);
      c8_full    : out std_logic;
      c8_rd_en   : in  std_logic;
      c8_rd_data : out std_logic_vector(26 downto 0);
      c8_empty   : out std_logic;

      c3_wr_en   : in  std_logic;
      c3_wr_data : in  std_logic_vector(31 downto 0);
      c3_full    : out std_logic;
      c3_rd_en   : in  std_logic;
      c3_rd_data : out std_logic_vector(31 downto 0);
      c3_empty   : out std_logic;

      hs_start   : in  std_logic;
      hs_req     : in  std_logic_vector(31 downto 0);
      hs_busy    : out std_logic;
      hs_done    : out std_logic;
      hs_rsp     : out std_logic_vector(31 downto 0);
      hs_valid   : out std_logic;
      hs_req_q   : out std_logic_vector(31 downto 0);
      hs_ack     : in  std_logic;
      hs_rsp_d   : in  std_logic_vector(31 downto 0);

      bus_d      : in  std_logic_vector(7 downto 0);
      bus_q      : out std_logic_vector(7 downto 0);
      bus_upd    : out std_logic;

      lvl_d      : in  std_logic_vector(3 downto 0);
      lvl_q      : out std_logic_vector(3 downto 0);

      p1_in      : in  std_logic;
      p1_out     : out std_logic;
      p4_in      : in  std_logic;
      p4_out     : out std_logic;

      tick_ce    : in  std_logic;
      tick       : out std_logic
   );
end entity;

architecture rtl of cdc_syn_top is
   signal lvl_r : std_logic_vector(3 downto 0);
begin

   u_c1 : entity work.cdc_fifo
      generic map (DATA_W => 34, ADDR_W => 4, FWFT => true, RAM_STYLE => "MLAB, no_rw_check")
      port map (wr_clk => clk_a, wr_rst => rst_a, wr_en => c1_wr_en, wr_data => c1_wr_data,
                wr_full => c1_full, wr_count => open, wr_overflow => open,
                rd_clk => clk_b, rd_rst => rst_b, rd_en => c1_rd_en, rd_data => c1_rd_data,
                rd_empty => c1_empty, rd_valid => open, rd_count => open, rd_underflow => open);

   u_c8 : entity work.cdc_fifo
      generic map (DATA_W => 27, ADDR_W => 3, FWFT => true, RAM_STYLE => "MLAB, no_rw_check")
      port map (wr_clk => clk_a, wr_rst => rst_a, wr_en => c8_wr_en, wr_data => c8_wr_data,
                wr_full => c8_full, wr_count => open, wr_overflow => open,
                rd_clk => clk_b, rd_rst => rst_b, rd_en => c8_rd_en, rd_data => c8_rd_data,
                rd_empty => c8_empty, rd_valid => open, rd_count => open, rd_underflow => open);

   u_c3 : entity work.cdc_fifo
      generic map (DATA_W => 32, ADDR_W => 10, FWFT => true, RAM_STYLE => "M10K, no_rw_check")
      port map (wr_clk => clk_b, wr_rst => rst_b, wr_en => c3_wr_en, wr_data => c3_wr_data,
                wr_full => c3_full, wr_count => open, wr_overflow => open,
                rd_clk => clk_a, rd_rst => rst_a, rd_en => c3_rd_en, rd_data => c3_rd_data,
                rd_empty => c3_empty, rd_valid => open, rd_count => open, rd_underflow => open);

   u_hs : entity work.cdc_handshake
      generic map (REQ_W => 32, RSP_W => 32)
      port map (src_clk => clk_a, src_rst => rst_a, src_start => hs_start, src_req_data => hs_req,
                src_busy => hs_busy, src_done => hs_done, src_rsp_data => hs_rsp,
                dst_clk => clk_b, dst_rst => rst_b, dst_valid => hs_valid, dst_req_data => hs_req_q,
                dst_pending => open, dst_ack => hs_ack, dst_rsp_data => hs_rsp_d);

   u_bus : entity work.cdc_bus_sync
      generic map (WIDTH => 8)
      port map (src_clk => clk_b, src_rst => rst_b, src_data => bus_d, src_busy => open,
                dst_clk => clk_a, dst_rst => rst_a, dst_data => bus_q, dst_update => bus_upd);

   -- level sources must be registers
   process (clk_b)
   begin
      if rising_edge(clk_b) then
         lvl_r <= lvl_d;
      end if;
   end process;

   u_lvl : entity work.cdc_sync
      generic map (WIDTH => 4)
      port map (clk => clk_a, d => lvl_r, q => lvl_q);

   u_p1 : entity work.cdc_pulse
      generic map (CNT_W => 1)
      port map (src_clk => clk_b, src_rst => rst_b, src_pulse => p1_in,
                dst_clk => clk_a, dst_rst => rst_a, dst_pulse => p1_out);

   u_p4 : entity work.cdc_pulse
      generic map (CNT_W => 4)
      port map (src_clk => clk_b, src_rst => rst_b, src_pulse => p4_in,
                dst_clk => clk_a, dst_rst => rst_a, dst_pulse => p4_out);

   u_tick : entity work.tick_accum
      port map (clk => clk_a, rst => rst_a, ce => tick_ce, tick => tick);

end architecture;
