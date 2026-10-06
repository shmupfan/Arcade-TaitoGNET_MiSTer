-- Destination-side capture register for data that a handshake holds stable
-- (cdc_rx_hold). en must come from synchronised control in the destination
-- domain, so d has been stable for at least one destination period when it
-- is sampled. Internal building block of cdc_handshake.

library ieee;
use ieee.std_logic_1164.all;
use work.cdc_pkg.all;

entity cdc_capture is
   generic (
      WIDTH           : positive := 1;
      SIM_META_WINDOW : time     := 0 ns;  -- simulation only, see cdc_pkg
      SIM_SEED        : positive := 1
   );
   port (
      clk : in  std_logic;
      rst : in  std_logic := '0';
      en  : in  std_logic;
      d   : in  std_logic_vector(WIDTH - 1 downto 0);
      q   : out std_logic_vector(WIDTH - 1 downto 0)
   );
end entity;

architecture rtl of cdc_capture is

   signal cdc_rx_hold : std_logic_vector(WIDTH - 1 downto 0) := (others => '0');

   attribute altera_attribute : string;
   attribute altera_attribute of cdc_rx_hold : signal is CDC_ATTR_KEEP;
   attribute preserve : boolean;
   attribute preserve of cdc_rx_hold : signal is true;

begin

   g_bit : for i in 0 to WIDTH - 1 generate
      process (clk)
         -- synthesis translate_off
         variable s1, s2 : positive;
         variable init_done : boolean := false;
         variable r : std_logic;
         -- synthesis translate_on
      begin
         if rising_edge(clk) then
            if en = '1' then
               cdc_rx_hold(i) <= d(i);
               -- synthesis translate_off
               if SIM_META_WINDOW > 0 ns and d(i)'last_event < SIM_META_WINDOW then
                  if not init_done then
                     cdc_sim_seed(SIM_SEED, 5000 + i, s1, s2);
                     init_done := true;
                  end if;
                  cdc_sim_pick(d(i), d(i)'last_value, s1, s2, r);
                  cdc_rx_hold(i) <= r;
               end if;
               -- synthesis translate_on
            end if;
            if rst = '1' then
               cdc_rx_hold(i) <= '0';
            end if;
         end if;
      end process;
   end generate;

   q <= cdc_rx_hold;

end architecture;
