-- Pulse synchroniser. Each source cycle with src_pulse = '1' gives exactly one
-- destination cycle with dst_pulse = '1'.
--
-- The source keeps a CNT_W-bit event counter in Gray code (cdc_tx_cnt); the
-- destination synchronises it, and while its own count differs it emits one
-- pulse per cycle and counts up. CNT_W = 1 is the classic toggle
-- synchroniser. Conditions for no lost and no duplicated pulse:
--   CNT_W = 1: consecutive source pulses at least one destination period
--              plus the synchroniser aperture apart (in practice: spacing
--              > 1.2 destination periods; the dot clock, C15, has 4 clk_vid
--              periods = 3.7 clk_cpu periods). Pulses closer than that merge.
--   CNT_W > 1: any pattern, as long as pulses not yet emitted never reach
--              2**CNT_W - 1. Bursts are queued and leave at one per
--              destination cycle, so the long-term rate must stay below the
--              destination clock rate. In-flight count is about
--              burst + (STAGES + 1) destination periods x source rate.
--
-- Latency (isolated pulse): dst_pulse is high in the cycle after destination
-- edge 2 counted from the source edge (edge 3 if the first stage resolves
-- late). dst_pulse is combinational from destination registers only.
--
-- Gray coding: a sample taken while the counter changes reads as the old or
-- the new count, never a third value.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cdc_pkg.all;

entity cdc_pulse is
   generic (
      CNT_W           : positive := 1;
      STAGES          : natural  := 2;
      SIM_META_WINDOW : time     := 0 ns;
      SIM_SEED        : positive := 1
   );
   port (
      src_clk   : in  std_logic;
      src_rst   : in  std_logic := '0';
      src_pulse : in  std_logic;
      dst_clk   : in  std_logic;
      dst_rst   : in  std_logic := '0';
      dst_pulse : out std_logic
   );
end entity;

architecture rtl of cdc_pulse is

   signal src_bin    : unsigned(CNT_W - 1 downto 0) := (others => '0');
   signal cdc_tx_cnt : std_logic_vector(CNT_W - 1 downto 0) := (others => '0');

   signal rx_cnt     : std_logic_vector(CNT_W - 1 downto 0);
   signal rx_bin     : unsigned(CNT_W - 1 downto 0);
   signal dst_bin    : unsigned(CNT_W - 1 downto 0) := (others => '0');
   signal pulse_i    : std_logic;

   attribute altera_attribute : string;
   attribute altera_attribute of cdc_tx_cnt : signal is CDC_ATTR_KEEP;

begin

   process (src_clk)
      variable nb : unsigned(CNT_W - 1 downto 0);
   begin
      if rising_edge(src_clk) then
         nb := src_bin;
         if src_pulse = '1' then
            nb := src_bin + 1;
         end if;
         src_bin <= nb;
         cdc_tx_cnt <= std_logic_vector(cdc_bin2gray(nb));
         if src_rst = '1' then
            src_bin    <= (others => '0');
            cdc_tx_cnt <= (others => '0');
         end if;
      end if;
   end process;

   u_sync : entity work.cdc_sync
      generic map (
         WIDTH           => CNT_W,
         STAGES          => STAGES,
         SIM_META_WINDOW => SIM_META_WINDOW,
         SIM_SEED        => SIM_SEED)
      port map (
         clk => dst_clk,
         rst => dst_rst,
         d   => cdc_tx_cnt,
         q   => rx_cnt);

   rx_bin  <= cdc_gray2bin(unsigned(rx_cnt));
   pulse_i <= '1' when rx_bin /= dst_bin else '0';

   process (dst_clk)
   begin
      if rising_edge(dst_clk) then
         if pulse_i = '1' then
            dst_bin <= dst_bin + 1;
         end if;
         if dst_rst = '1' then
            dst_bin <= (others => '0');
         end if;
      end if;
   end process;

   dst_pulse <= pulse_i;

end architecture;
