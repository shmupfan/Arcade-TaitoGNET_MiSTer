-- cdc_pulse bench. MODE 0: single pulses spaced at least one destination
-- period plus the window apart (the toggle condition), up to 12 source
-- cycles more. MODE 1: bursts of 1 to BMAX back-to-back source pulses, then
-- a gap long enough to drain. Every source pulse must give exactly one
-- destination pulse.

library ieee;
use ieee.std_logic_1164.all;
use work.cdc_tb_pkg.all;

entity tb_cdc_pulse is
   generic (
      PA         : natural  := P_50M;
      PB         : natural  := P_33M;
      SEED       : positive := 1;
      META       : natural  := 1;
      STAGES     : natural  := 2;
      CNT_W      : positive := 1;
      MODE       : natural  := 0;
      BMAX       : positive := 8;
      NX          : natural  := 50000
   );
end entity;

architecture sim of tb_cdc_pulse is

   constant OFFA : natural := rnd_offset(SEED, 1, PA);
   constant OFFB : natural := rnd_offset(SEED, 2, PB);
   constant T0B  : time := tfs(OFFB);
   constant WIN  : time := meta_window(PA, PB, META);

   signal clka, clkb : std_logic := '0';
   signal spulse     : std_logic := '0';
   signal dpulse     : std_logic;

   type tarr is array (0 to 4095) of time;
   type barr is array (0 to 4095) of boolean;
   signal t_src  : tarr := (others => 0 fs);
   signal iso    : barr := (others => false);
   signal n_sent : natural := 0;
   signal n_seen : natural := 0;
   signal done   : boolean := false;

begin

   clk_gen(clka, PA, OFFA);
   clk_gen(clkb, PB, OFFB);

   dut : entity work.cdc_pulse
      generic map (CNT_W => CNT_W, STAGES => STAGES,
                   SIM_META_WINDOW => WIN, SIM_SEED => SEED)
      port map (src_clk => clka, src_pulse => spulse, dst_clk => clkb, dst_pulse => dpulse);

   src : process
      variable rng : rng_t;
      variable gap, smin, b : integer;
      variable n : natural := 0;
   begin
      rng.init(SEED, 7);
      smin := (PB + WIN / 1 fs) / PA + 1;
      wait until rising_edge(clka) and now > 1 us;
      while n < NX loop
         if MODE = 0 then
            b   := 1;
            gap := rng.int(smin, smin + 12) - 1;
         else
            b   := rng.int(1, BMAX);
            -- drain time: burst plus synchroniser, in destination periods
            gap := ((b + STAGES + 3) * PB) / PA + rng.int(0, 10);
         end if;
         for i in 1 to b loop
            -- the pulse is taken at the next source edge
            spulse <= '1';
            wait until rising_edge(clka);
            t_src(n mod 4096) <= now;
            iso(n mod 4096)   <= (MODE = 0) or (i = 1);
            n := n + 1;
            n_sent <= n;
            exit when n = NX;
         end loop;
         spulse <= '0';
         for i in 1 to gap loop
            wait until rising_edge(clka);
         end loop;
      end loop;
      spulse <= '0';
      wait for 40 * tfs(PB) + 40 * tfs(PA);
      done <= true;
      wait for 3 * tfs(PB);
      std.env.finish;
   end process;

   mon : process
      variable lat  : stat_t := STAT_INIT;
      variable tl   : tstat_t := TSTAT_INIT;
      variable m    : natural := 0;
      variable l    : integer;
      variable errs : natural := 0;
      variable tu   : time;
   begin
      loop
         wait until rising_edge(clkb) or done;
         exit when done;
         if dpulse = '1' then
            -- the pulse was output after the previous destination edge
            tu := now - tfs(PB);
            if m >= n_sent then
               errs := errs + 1;
               if errs < 10 then
                  say("ERROR extra pulse at " & time'image(now));
               end if;
            else
               if iso(m mod 4096) then
                  l := edges_in(t_src(m mod 4096), tu, T0B, PB);
                  stat_add(lat, l);
                  tstat_add(tl, tu - t_src(m mod 4096));
                  if MODE = 0 and (l > STAGES + 1 or l < STAGES) then
                     errs := errs + 1;
                     if errs < 10 then
                        say("ERROR latency " & integer'image(l) & " at " & time'image(now));
                     end if;
                  end if;
               end if;
            end if;
            m := m + 1;
            n_seen <= m;
         end if;
      end loop;
      if m /= NX then
         errs := errs + 1;
         say("ERROR count: sent " & integer'image(NX) & " received " & integer'image(m));
      end if;
      say("RESULT pulse PA=" & integer'image(PA) & " PB=" & integer'image(PB) &
          " seed=" & integer'image(SEED) & " meta=" & integer'image(META) &
          " cnt_w=" & integer'image(CNT_W) & " mode=" & integer'image(MODE) &
          " n=" & integer'image(NX) & " received=" & integer'image(m) &
          " errors=" & integer'image(errs) &
          " lat_edges=" & stat_str(lat) & " lat_ns=" & tstat_str(tl));
      wait;
   end process;

   -- watchdog: a wedged run still ends with a RESULT line
   wd : process
      variable pm : natural := PA;
   begin
      if PB > pm then
         pm := PB;
      end if;
      wait for (NX * 200) * tfs(pm) + 100 us;
      say("RESULT pulse PA=" & integer'image(PA) & " PB=" & integer'image(PB) &
          " seed=" & integer'image(SEED) & " TIMEOUT errors=1");
      std.env.finish;
   end process;

end architecture;
