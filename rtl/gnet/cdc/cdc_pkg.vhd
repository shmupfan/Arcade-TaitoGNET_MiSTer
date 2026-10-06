-- CDC building blocks for the R1 CPU clock domain (docs/r1_cpu_domain_design.md,
-- "Plan for exactly 50.000 MHz", P2, and "CDC building blocks").
--
-- Naming convention used by every entity in rtl/gnet/cdc and by cdc.sdc:
--   cdc_tx_*   register in the source domain whose output crosses (Gray
--              pointers, toggles, held request and response data). Nothing
--              but a register drives a crossing.
--   cdc_rx_*   first register in the destination domain that samples a
--              crossing signal (synchroniser first stage cdc_rx_s1, data
--              capture cdc_rx_hold). Later synchroniser stages are cdc_rx_sn.
--
-- Simulation model (SIM_META_WINDOW > 0 ns, ignored by synthesis): when a
-- cdc_rx_* register samples an input bit that changed less than
-- SIM_META_WINDOW before the clock edge, the bit resolves at random to its
-- old or its new value, independently per bit. That is the "synchroniser
-- that randomly adds a cycle" of step 3, and it makes multi-bit skew visible
-- (a binary pointer or unsynchronised data then reads as a mix of old and new
-- bits). Benches set the window below the shorter clock period.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
-- synthesis translate_off
use ieee.math_real.all;
-- synthesis translate_on

package cdc_pkg is

   function cdc_bin2gray(b : unsigned) return unsigned;
   function cdc_gray2bin(g : unsigned) return unsigned;
   function cdc_clog2(n : positive) return natural;
   function cdc_imax(a, b : integer) return integer;

   -- Quartus register attributes (Intel's altera_std_synchronizer uses the
   -- same assignments for its chain).
   constant CDC_ATTR_SYNC : string :=
      "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS; -name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON";
   constant CDC_ATTR_KEEP : string :=
      "-name DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON";

   -- synthesis translate_off
   procedure cdc_sim_seed(base : positive; idx : natural; variable s1, s2 : out positive);
   procedure cdc_sim_pick(new_v, old_v : std_logic; variable s1, s2 : inout positive; variable r : out std_logic);
   -- synthesis translate_on

end package;

package body cdc_pkg is

   function cdc_bin2gray(b : unsigned) return unsigned is
   begin
      return b xor shift_right(b, 1);
   end function;

   function cdc_gray2bin(g : unsigned) return unsigned is
      variable b : unsigned(g'range);
   begin
      b(g'high) := g(g'high);
      for i in g'high - 1 downto g'low loop
         b(i) := b(i + 1) xor g(i);
      end loop;
      return b;
   end function;

   function cdc_clog2(n : positive) return natural is
      variable r : natural := 0;
      variable v : natural := 1;
   begin
      while v < n loop
         v := v * 2;
         r := r + 1;
      end loop;
      return r;
   end function;

   function cdc_imax(a, b : integer) return integer is
   begin
      if a > b then
         return a;
      end if;
      return b;
   end function;

   -- synthesis translate_off
   procedure cdc_sim_seed(base : positive; idx : natural; variable s1, s2 : out positive) is
   begin
      -- all terms stay below 2**31 for base < 100000 and idx < 10000
      s1 := 1 + (base mod 100000) * 7919 + (idx mod 10000) * 104729;
      s2 := 12345 + (base mod 100000) * 3571 + (idx mod 10000) * 7907;
   end procedure;

   procedure cdc_sim_pick(new_v, old_v : std_logic; variable s1, s2 : inout positive; variable r : out std_logic) is
      variable u : real;
   begin
      uniform(s1, s2, u);
      if u < 0.5 then
         r := old_v;
      else
         r := new_v;
      end if;
   end procedure;
   -- synthesis translate_on

end package body;
