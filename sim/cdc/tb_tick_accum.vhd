-- tick_accum bench on a 50.000 MHz clock. CE_MODE 0: ce always '1'; every
-- window of 15,625 consecutive cycles (all start positions) must hold
-- exactly 10,584 ticks, and ticks must be 1 or 2 cycles apart. CE_MODE 1:
-- random ce (about 70% high); the same count must hold over every 15,625
-- consecutive ce cycles, and no tick may follow a cycle with ce = '0'.

library ieee;
use ieee.std_logic_1164.all;
use work.cdc_tb_pkg.all;

entity tb_tick_accum is
   generic (
      SEED    : positive := 1;
      CE_MODE : natural  := 0;
      MODN    : positive := 15625;
      INC     : positive := 10584;
      WINDOWS : positive := 64      -- run length in units of MODN ce cycles
   );
end entity;

architecture sim of tb_tick_accum is

   signal clk  : std_logic := '0';
   signal rst  : std_logic := '1';
   signal ce   : std_logic := '0';
   signal tick : std_logic;

begin

   clk_gen(clk, P_50M, 1000);

   dut : entity work.tick_accum
      generic map (MODULUS => MODN, INCREMENT => INC)
      port map (clk => clk, rst => rst, ce => ce, tick => tick);

   process
      variable rng : rng_t;
      type bits_t is array (0 to MODN - 1) of natural range 0 to 1;
      variable ring : bits_t := (others => 0);
      variable k, total, inwin, errs, wins : natural := 0;
      variable last_tick : integer := -1;
      variable cyc : natural := 0;
      variable sp_min, sp_max : integer;
      variable prev_ce : std_logic := '0';
      variable t : natural;
   begin
      rng.init(SEED, 7);
      sp_min := integer'high;
      sp_max := 0;
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      rst <= '0';
      ce  <= '1';
      wait until rising_edge(clk);   -- first edge with ce = '1'
      prev_ce := '1';
      loop
         if CE_MODE = 1 then
            if rng.uni < 0.7 then ce <= '1'; else ce <= '0'; end if;
         end if;
         wait until rising_edge(clk);
         cyc := cyc + 1;
         -- tick seen now is the result of the previous edge
         if tick = '1' then t := 1; else t := 0; end if;
         if prev_ce = '0' and t = 1 then
            errs := errs + 1;
            say("ERROR tick after a cycle with ce = 0");
         end if;
         if prev_ce = '1' then
            -- sliding window over ce cycles
            inwin := inwin - ring(k mod MODN) + t;
            ring(k mod MODN) := t;
            k := k + 1;
            total := total + t;
            if k >= MODN then
               wins := wins + 1;
               if inwin /= INC then
                  errs := errs + 1;
                  if errs < 10 then
                     say("ERROR window ending at ce cycle " & integer'image(k) & " holds " & integer'image(inwin));
                  end if;
               end if;
            end if;
            if t = 1 then
               if last_tick >= 0 then
                  if k - last_tick < sp_min then sp_min := k - last_tick; end if;
                  if k - last_tick > sp_max then sp_max := k - last_tick; end if;
               end if;
               last_tick := k;
            end if;
         end if;
         prev_ce := ce;
         exit when k >= WINDOWS * MODN;
      end loop;
      if sp_min < 1 or sp_max > (MODN + INC - 1) / INC then
         errs := errs + 1;
         say("ERROR tick spacing outside 1 .. ceil(MODN / INC)");
      end if;
      say("RESULT tick_accum mod=" & integer'image(MODN) & " inc=" & integer'image(INC) &
          " ce_mode=" & integer'image(CE_MODE) & " seed=" & integer'image(SEED) &
          " ce_cycles=" & integer'image(k) & " clock_cycles=" & integer'image(cyc) &
          " ticks=" & integer'image(total) & " windows_checked=" & integer'image(wins) &
          " spacing_ce_cycles=" & integer'image(sp_min) & ".." & integer'image(sp_max) &
          " errors=" & integer'image(errs));
      std.env.finish;
   end process;

end architecture;
