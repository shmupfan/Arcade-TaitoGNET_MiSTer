-- Vector synchroniser for quasi-static groups (configuration, run/pause
-- words): the vector always arrives whole. Whenever src_data differs from the
-- last value sent and no transfer is in flight, the value is sent through a
-- cdc_handshake; dst_data then holds it and dst_update is high for one cycle.
-- If src_data changes faster than one round trip, intermediate values are
-- skipped, but every value dst_data takes was held by the source, values
-- arrive in order, and the last value always arrives.
--
-- Latency: as cdc_handshake's request (dst_update high in the cycle after
-- destination edge STAGES + 1 from the source edge that sees the change);
-- the next change can leave about STAGES + 1 destination plus STAGES + 2
-- source cycles later.
--
-- Reset value of dst_data is all zeros; a src_data that differs from zero
-- after reset is sent at once. Both resets must be applied together.

library ieee;
use ieee.std_logic_1164.all;

entity cdc_bus_sync is
   generic (
      WIDTH           : positive := 8;
      STAGES          : natural  := 2;
      SIM_META_WINDOW : time     := 0 ns;
      SIM_SEED        : positive := 1
   );
   port (
      src_clk    : in  std_logic;
      src_rst    : in  std_logic := '0';
      src_data   : in  std_logic_vector(WIDTH - 1 downto 0);
      src_busy   : out std_logic;

      dst_clk    : in  std_logic;
      dst_rst    : in  std_logic := '0';
      dst_data   : out std_logic_vector(WIDTH - 1 downto 0);
      dst_update : out std_logic
   );
end entity;

architecture rtl of cdc_bus_sync is

   signal sent    : std_logic_vector(WIDTH - 1 downto 0) := (others => '0');
   signal busy    : std_logic;
   signal start   : std_logic;
   signal valid   : std_logic;

begin

   start <= '1' when busy = '0' and src_data /= sent else '0';

   process (src_clk)
   begin
      if rising_edge(src_clk) then
         if start = '1' then
            sent <= src_data;
         end if;
         if src_rst = '1' then
            sent <= (others => '0');
         end if;
      end if;
   end process;

   u_hs : entity work.cdc_handshake
      generic map (
         REQ_W           => WIDTH,
         RSP_W           => 1,
         STAGES          => STAGES,
         SIM_META_WINDOW => SIM_META_WINDOW,
         SIM_SEED        => SIM_SEED)
      port map (
         src_clk      => src_clk,
         src_rst      => src_rst,
         src_start    => start,
         src_req_data => src_data,
         src_busy     => busy,
         src_done     => open,
         src_rsp_data => open,
         dst_clk      => dst_clk,
         dst_rst      => dst_rst,
         dst_valid    => valid,
         dst_req_data => dst_data,
         dst_pending  => open,
         dst_ack      => valid,
         dst_rsp_data => "0");

   src_busy   <= busy;
   dst_update <= valid;

end architecture;
