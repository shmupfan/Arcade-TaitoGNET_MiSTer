-- Simulation wrapper (docs/fullsys_sim.md, docs/i12_ddr3_load.md): PSX.sv's
-- channel 3 download crossing, cdc_handshake #(.REQ_W(64), .RSP_W(32)),
-- as an entity without generics, so convert.sh can synthesise it as an
-- extra top (EXTRA_TOPS) for the release download-path top (FS_DL with
-- FS_DDR3ARB, fs_psxdl_full.svh).
library IEEE;
use IEEE.std_logic_1164.all;

entity fs_ch3_cdc is
   port (
      src_clk      : in  std_logic;
      src_start    : in  std_logic;
      src_req_data : in  std_logic_vector(63 downto 0);
      src_done     : out std_logic;
      src_rsp_data : out std_logic_vector(31 downto 0);
      dst_clk      : in  std_logic;
      dst_valid    : out std_logic;
      dst_req_data : out std_logic_vector(63 downto 0);
      dst_ack      : in  std_logic;
      dst_rsp_data : in  std_logic_vector(31 downto 0)
   );
end entity;

architecture arch of fs_ch3_cdc is
begin
   u : entity work.cdc_handshake
      generic map (REQ_W => 64, RSP_W => 32)
      port map (
         src_clk => src_clk, src_rst => '0', src_start => src_start, src_req_data => src_req_data,
         src_busy => open, src_done => src_done, src_rsp_data => src_rsp_data,
         dst_clk => dst_clk, dst_rst => '0', dst_valid => dst_valid, dst_req_data => dst_req_data,
         dst_pending => open, dst_ack => dst_ack, dst_rsp_data => dst_rsp_data);
end architecture;
