-- Phase-accumulator tick generator (docs/r1_cpu_domain_design.md, P3): on
-- clk_cpu at 50.000 MHz it gives 33.8688 MHz-equivalent ticks for the root
-- counters and SIO0. Each cycle with ce = '1' adds INCREMENT modulo MODULUS;
-- tick is '1' in the cycle after each wrap. With the defaults (10584 /
-- 15625) every 15,625 consecutive ce cycles hold exactly 10,584 ticks, and
-- ticks are 1 or 2 cycles apart (INCREMENT >= MODULUS / 2). tick is '0'
-- while ce = '0'. Not a crossing; it lives in rtl/gnet/cdc with the
-- crossing blocks because it replaces one.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cdc_pkg.all;

entity tick_accum is
   generic (
      MODULUS   : positive := 15625;
      INCREMENT : positive := 10584
   );
   port (
      clk  : in  std_logic;
      rst  : in  std_logic;
      ce   : in  std_logic;
      tick : out std_logic
   );
end entity;

architecture rtl of tick_accum is

   constant ACC_W : natural := cdc_clog2(MODULUS);

   signal acc    : unsigned(ACC_W - 1 downto 0) := (others => '0');
   signal tick_r : std_logic := '0';

begin

   assert INCREMENT <= MODULUS
      report "tick_accum: INCREMENT must not exceed MODULUS" severity failure;

   process (clk)
      variable s : unsigned(ACC_W downto 0);
   begin
      if rising_edge(clk) then
         tick_r <= '0';
         if ce = '1' then
            s := resize(acc, ACC_W + 1) + INCREMENT;
            if s >= MODULUS then
               acc    <= resize(s - MODULUS, ACC_W);
               tick_r <= '1';
            else
               acc <= resize(s, ACC_W);
            end if;
         end if;
         if rst = '1' then
            acc    <= (others => '0');
            tick_r <= '0';
         end if;
      end if;
   end process;

   tick <= tick_r;

end architecture;
