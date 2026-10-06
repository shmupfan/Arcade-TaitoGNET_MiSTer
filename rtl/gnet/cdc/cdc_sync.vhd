-- Level synchroniser: WIDTH independent bits, each through STAGES flip-flops
-- in the destination clock (two by default). Use it for single-bit levels and
-- for groups whose bits are independent (each bit may arrive one cycle
-- before or after the others). For a vector that must arrive whole, use
-- cdc_bus_sync. The source must drive d from a register (cdc_tx_* naming).
--
-- Latency: the output changes on destination edge 2 after the source edge
-- (edge 3 if the first stage resolves late), STAGES in general.
--
-- STAGES = 0 bypasses the synchroniser; it exists only for the negative
-- control benches and must not be used in the design.

library ieee;
use ieee.std_logic_1164.all;
use work.cdc_pkg.all;

entity cdc_sync is
   generic (
      WIDTH           : positive  := 1;
      STAGES          : natural   := 2;
      INIT            : std_logic := '0';
      SIM_META_WINDOW : time      := 0 ns;  -- simulation only, see cdc_pkg
      SIM_SEED        : positive  := 1
   );
   port (
      clk : in  std_logic;
      rst : in  std_logic := '0';           -- synchronous, to INIT
      d   : in  std_logic_vector(WIDTH - 1 downto 0);
      q   : out std_logic_vector(WIDTH - 1 downto 0)
   );
end entity;

architecture rtl of cdc_sync is

   type chain_t is array (natural range <>) of std_logic_vector(WIDTH - 1 downto 0);

   signal cdc_rx_s1 : std_logic_vector(WIDTH - 1 downto 0) := (others => INIT);
   signal cdc_rx_sn : chain_t(2 to cdc_imax(STAGES, 2)) := (others => (others => INIT));

   attribute altera_attribute : string;
   attribute altera_attribute of cdc_rx_s1 : signal is CDC_ATTR_SYNC;
   attribute altera_attribute of cdc_rx_sn : signal is CDC_ATTR_SYNC;
   attribute preserve : boolean;
   attribute preserve of cdc_rx_s1 : signal is true;
   attribute preserve of cdc_rx_sn : signal is true;

begin

   g_bypass : if STAGES = 0 generate
      q <= d;
   end generate;

   g_sync : if STAGES > 0 generate

      g_bit : for i in 0 to WIDTH - 1 generate
         process (clk)
            -- synthesis translate_off
            variable s1, s2 : positive;
            variable init_done : boolean := false;
            variable r : std_logic;
            -- synthesis translate_on
         begin
            if rising_edge(clk) then
               cdc_rx_s1(i) <= d(i);
               -- synthesis translate_off
               if SIM_META_WINDOW > 0 ns and d(i)'last_event < SIM_META_WINDOW then
                  if not init_done then
                     cdc_sim_seed(SIM_SEED, i, s1, s2);
                     init_done := true;
                  end if;
                  cdc_sim_pick(d(i), d(i)'last_value, s1, s2, r);
                  cdc_rx_s1(i) <= r;
               end if;
               -- synthesis translate_on
               if rst = '1' then
                  cdc_rx_s1(i) <= INIT;
               end if;
            end if;
         end process;
      end generate;

      g_chain : if STAGES >= 2 generate
         process (clk)
         begin
            if rising_edge(clk) then
               cdc_rx_sn(2) <= cdc_rx_s1;
               for k in 3 to STAGES loop
                  cdc_rx_sn(k) <= cdc_rx_sn(k - 1);
               end loop;
               if rst = '1' then
                  cdc_rx_sn <= (others => (others => INIT));
               end if;
            end if;
         end process;
      end generate;

      g_q1 : if STAGES = 1 generate
         q <= cdc_rx_s1;
      end generate;
      g_qn : if STAGES >= 2 generate
         q <= cdc_rx_sn(STAGES);
      end generate;

   end generate;

end architecture;
