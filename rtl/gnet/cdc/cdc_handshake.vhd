-- Request/acknowledge handshake with data in both directions (two-phase:
-- one toggle per request, one per acknowledge). For register reads and
-- writes across the boundary (C2, C9, C10, C18, C19).
--
-- Source side: src_start = '1' while src_busy = '0' launches a request with
-- src_req_data (ignored while busy). src_busy stays high until the response
-- is captured; src_done is high for one cycle with src_rsp_data valid (held
-- until the next src_done).
-- Destination side: dst_valid is high for one cycle with dst_req_data (held
-- until the next dst_valid); dst_pending stays high until the device answers
-- with dst_ack = '1' and dst_rsp_data in the same cycle (dst_ack may be
-- driven combinationally from dst_valid; it is ignored while dst_pending is
-- low).
--
-- Data integrity: cdc_tx_req and cdc_tx_rsp are written on the same edge as
-- the toggle they belong to and do not change until the other side has
-- answered; the other side samples them (cdc_rx_hold) only after the toggle
-- has passed STAGES synchroniser flip-flops. Constrain cdc_tx_* to cdc_rx_*
-- with cdc.sdc.
--
-- Latency: dst_valid high in the cycle after destination edge STAGES + 1
-- (3, or 4 when the first stage resolves late) from the source edge that
-- takes src_start; src_done high in the cycle after source edge STAGES + 1
-- from the destination edge that takes dst_ack.
--
-- Both resets must be applied together (the toggles restart at 0).

library ieee;
use ieee.std_logic_1164.all;
use work.cdc_pkg.all;

entity cdc_handshake is
   generic (
      REQ_W           : positive := 32;
      RSP_W           : positive := 32;
      STAGES          : natural  := 2;
      SIM_META_WINDOW : time     := 0 ns;
      SIM_SEED        : positive := 1
   );
   port (
      src_clk      : in  std_logic;
      src_rst      : in  std_logic := '0';
      src_start    : in  std_logic;
      src_req_data : in  std_logic_vector(REQ_W - 1 downto 0);
      src_busy     : out std_logic;
      src_done     : out std_logic;
      src_rsp_data : out std_logic_vector(RSP_W - 1 downto 0);

      dst_clk      : in  std_logic;
      dst_rst      : in  std_logic := '0';
      dst_valid    : out std_logic;
      dst_req_data : out std_logic_vector(REQ_W - 1 downto 0);
      dst_pending  : out std_logic;
      dst_ack      : in  std_logic;
      dst_rsp_data : in  std_logic_vector(RSP_W - 1 downto 0)
   );
end entity;

architecture rtl of cdc_handshake is

   -- source domain
   signal cdc_tx_req_tgl : std_logic := '0';
   signal cdc_tx_req     : std_logic_vector(REQ_W - 1 downto 0) := (others => '0');
   signal src_busy_r     : std_logic := '0';
   signal src_done_r     : std_logic := '0';
   signal ack_sync       : std_logic_vector(0 downto 0);
   signal src_cap        : std_logic;

   -- destination domain
   signal cdc_tx_ack_tgl : std_logic := '0';
   signal cdc_tx_rsp     : std_logic_vector(RSP_W - 1 downto 0) := (others => '0');
   signal req_sync       : std_logic_vector(0 downto 0);
   signal dst_seen       : std_logic := '0';
   signal dst_valid_r    : std_logic := '0';
   signal dst_pending_r  : std_logic := '0';
   signal dst_cap        : std_logic;

   attribute altera_attribute : string;
   attribute altera_attribute of cdc_tx_req_tgl : signal is CDC_ATTR_KEEP;
   attribute altera_attribute of cdc_tx_req     : signal is CDC_ATTR_KEEP;
   attribute altera_attribute of cdc_tx_ack_tgl : signal is CDC_ATTR_KEEP;
   attribute altera_attribute of cdc_tx_rsp     : signal is CDC_ATTR_KEEP;

begin

   ---------------------------------------------------------------- source
   -- response present: the synchronised acknowledge toggle has caught up
   src_cap <= '1' when src_busy_r = '1' and ack_sync(0) = cdc_tx_req_tgl else '0';

   process (src_clk)
   begin
      if rising_edge(src_clk) then
         src_done_r <= '0';
         if src_busy_r = '0' then
            if src_start = '1' then
               cdc_tx_req     <= src_req_data;
               cdc_tx_req_tgl <= not cdc_tx_req_tgl;
               src_busy_r     <= '1';
            end if;
         elsif src_cap = '1' then
            src_busy_r <= '0';
            src_done_r <= '1';
         end if;
         if src_rst = '1' then
            cdc_tx_req_tgl <= '0';
            src_busy_r     <= '0';
            src_done_r     <= '0';
         end if;
      end if;
   end process;

   u_ack_sync : entity work.cdc_sync
      generic map (
         WIDTH           => 1,
         STAGES          => STAGES,
         SIM_META_WINDOW => SIM_META_WINDOW,
         SIM_SEED        => SIM_SEED * 2 + 1)
      port map (
         clk  => src_clk,
         rst  => src_rst,
         d(0) => cdc_tx_ack_tgl,
         q    => ack_sync);

   u_rsp_cap : entity work.cdc_capture
      generic map (
         WIDTH           => RSP_W,
         SIM_META_WINDOW => SIM_META_WINDOW,
         SIM_SEED        => SIM_SEED * 2 + 1)
      port map (
         clk => src_clk,
         rst => src_rst,
         en  => src_cap,
         d   => cdc_tx_rsp,
         q   => src_rsp_data);

   src_busy <= src_busy_r;
   src_done <= src_done_r;

   ----------------------------------------------------------- destination
   dst_cap <= '1' when req_sync(0) /= dst_seen else '0';

   u_req_sync : entity work.cdc_sync
      generic map (
         WIDTH           => 1,
         STAGES          => STAGES,
         SIM_META_WINDOW => SIM_META_WINDOW,
         SIM_SEED        => SIM_SEED * 2)
      port map (
         clk  => dst_clk,
         rst  => dst_rst,
         d(0) => cdc_tx_req_tgl,
         q    => req_sync);

   u_req_cap : entity work.cdc_capture
      generic map (
         WIDTH           => REQ_W,
         SIM_META_WINDOW => SIM_META_WINDOW,
         SIM_SEED        => SIM_SEED * 2)
      port map (
         clk => dst_clk,
         rst => dst_rst,
         en  => dst_cap,
         d   => cdc_tx_req,
         q   => dst_req_data);

   process (dst_clk)
   begin
      if rising_edge(dst_clk) then
         dst_valid_r <= '0';
         if dst_cap = '1' then
            dst_seen      <= req_sync(0);
            dst_valid_r   <= '1';
            dst_pending_r <= '1';
         elsif dst_pending_r = '1' and dst_ack = '1' then
            cdc_tx_rsp     <= dst_rsp_data;
            cdc_tx_ack_tgl <= dst_seen;
            dst_pending_r  <= '0';
         end if;
         if dst_rst = '1' then
            dst_seen       <= '0';
            dst_valid_r    <= '0';
            dst_pending_r  <= '0';
            cdc_tx_ack_tgl <= '0';
         end if;
      end if;
   end process;

   dst_valid   <= dst_valid_r;
   dst_pending <= dst_pending_r;

end architecture;
