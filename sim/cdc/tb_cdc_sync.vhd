-- cdc_sync bench: a source register toggles a level after random holds of at
-- least one destination period plus the window; every change must appear at
-- q once, in order, with bounded latency.

library ieee;
use ieee.std_logic_1164.all;
use work.cdc_tb_pkg.all;

entity tb_cdc_sync is
   generic (
      PA     : natural  := P_50M;   -- source period, fs
      PB     : natural  := P_33M;   -- destination period, fs
      SEED   : positive := 1;
      META   : natural  := 1;
      STAGES : natural  := 2;
      NX      : natural  := 50000
   );
end entity;

architecture sim of tb_cdc_sync is

   constant OFFA : natural := rnd_offset(SEED, 1, PA);
   constant OFFB : natural := rnd_offset(SEED, 2, PB);
   constant T0A  : time := tfs(OFFA);
   constant T0B  : time := tfs(OFFB);
   constant WIN  : time := meta_window(PA, PB, META);

   signal clka, clkb : std_logic := '0';
   signal lvl        : std_logic := '0';
   signal q          : std_logic_vector(0 downto 0);

   type tarr is array (0 to 4095) of time;
   signal t_chg  : tarr := (others => 0 fs);
   signal n_sent : natural := 0;
   signal n_seen : natural := 0;
   signal errors : natural := 0;

begin

   clk_gen(clka, PA, OFFA);
   clk_gen(clkb, PB, OFFB);

   dut : entity work.cdc_sync
      generic map (WIDTH => 1, STAGES => STAGES, SIM_META_WINDOW => WIN, SIM_SEED => SEED)
      port map (clk => clkb, d(0) => lvl, q => q);

   src : process
      variable rng : rng_t;
      variable hold, hmin : integer;
      variable n : natural := 0;
   begin
      rng.init(SEED, 7);
      -- a level must be held at least one destination period plus the window
      hmin := (PB + WIN / 1 fs) / PA + 1;
      wait until rising_edge(clka) and now > 1 us;
      while n < NX loop
         hold := rng.int(hmin, hmin + 12);
         for i in 1 to hold loop
            wait until rising_edge(clka);
         end loop;
         lvl <= not lvl;
         t_chg(n mod 4096) <= now;
         n := n + 1;
         n_sent <= n;
      end loop;
      wait for 20 * tfs(PB) + 20 * tfs(PA);
      if n_seen /= NX then
         say("ERROR count: sent " & integer'image(NX) & " seen " & integer'image(n_seen));
      end if;
      wait for 1 ns;
      std.env.finish;
   end process;

   mon : process
      variable lat  : stat_t := STAT_INIT;
      variable tl   : tstat_t := TSTAT_INIT;
      variable m    : natural := 0;
      variable l    : integer;
      variable errs : natural := 0;
      variable exp  : std_logic := '0';
   begin
      loop
         wait on q, n_sent for 50 us;
         if q'event and now > 1 us then
            exp := not exp;
            if q(0) /= exp or m >= n_sent then
               errs := errs + 1;
               say("ERROR unexpected change at " & time'image(now));
            else
               l := edges_in(t_chg(m mod 4096), now, T0B, PB);
               stat_add(lat, l);
               tstat_add(tl, now - t_chg(m mod 4096));
               if l > STAGES + 1 or l < STAGES then
                  errs := errs + 1;
                  say("ERROR latency " & integer'image(l) & " at " & time'image(now));
               end if;
            end if;
            m := m + 1;
            n_seen <= m;
         end if;
         if n_sent = NX and m = NX then
            wait for 10 * tfs(PB);
            say("RESULT sync PA=" & integer'image(PA) & " PB=" & integer'image(PB) &
                " seed=" & integer'image(SEED) & " meta=" & integer'image(META) &
                " stages=" & integer'image(STAGES) & " n=" & integer'image(m) &
                " errors=" & integer'image(errs) &
                " lat_edges=" & stat_str(lat) & " lat_ns=" & tstat_str(tl));
            wait;
         end if;
      end loop;
   end process;

   -- watchdog: a wedged run still ends with a RESULT line
   wd : process
      variable pm : natural := PA;
   begin
      if PB > pm then
         pm := PB;
      end if;
      wait for (NX * 200) * tfs(pm) + 100 us;
      say("RESULT sync PA=" & integer'image(PA) & " PB=" & integer'image(PB) &
          " seed=" & integer'image(SEED) & " TIMEOUT errors=1");
      std.env.finish;
   end process;

end architecture;
