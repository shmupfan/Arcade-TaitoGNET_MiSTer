-- cdc_bus_sync bench: the source changes a 24-bit word (12-bit sequence plus
-- 12-bit check field) after holds of 1 to 3 cycles (faster than a round
-- trip, so values are skipped) or long holds. Checks: every destination value
-- is a whole source value (no torn word), sequence numbers only increase,
-- dst_data changes only with dst_update, and after each long hold the
-- destination holds the source value. Latency is measured from the source
-- edge where the entity takes a value.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cdc_tb_pkg.all;

entity tb_cdc_bus_sync is
   generic (
      PA     : natural  := P_50M;
      PB     : natural  := P_33M;
      SEED   : positive := 1;
      META   : natural  := 1;
      STAGES : natural  := 2;
      NX      : natural  := 50000
   );
end entity;

architecture sim of tb_cdc_bus_sync is

   constant OFFA : natural := rnd_offset(SEED, 1, PA);
   constant OFFB : natural := rnd_offset(SEED, 2, PB);
   constant T0B  : time := tfs(OFFB);
   constant WIN  : time := meta_window(PA, PB, META);
   constant W    : positive := 24;

   signal clka, clkb : std_logic := '0';
   signal sdata      : std_logic_vector(W - 1 downto 0) := (others => '0');
   signal busy       : std_logic;
   signal ddata      : std_logic_vector(W - 1 downto 0);
   signal upd        : std_logic;

   type tarr is array (0 to 4095) of time;
   signal t_take   : tarr := (others => 0 fs);
   signal cur_seq  : natural := 0;
   signal last_dst : integer := 0;
   signal n_upd    : natural := 0;
   signal derrs    : natural := 0;
   signal lat_mn, lat_mx : integer := 0;

begin

   clk_gen(clka, PA, OFFA);
   clk_gen(clkb, PB, OFFB);

   dut : entity work.cdc_bus_sync
      generic map (WIDTH => W, STAGES => STAGES, SIM_META_WINDOW => WIN, SIM_SEED => SEED)
      port map (src_clk => clka, src_data => sdata, src_busy => busy,
                dst_clk => clkb, dst_data => ddata, dst_update => upd);

   -- seq 0 is the reset value 0 (never sent); the source starts at seq 1
   src : process
      variable rng : rng_t;
      variable hold : integer;
      variable longh : boolean;
      variable errs : natural := 0;
      variable seq : natural := 0;
      variable long_min : integer;
   begin
      rng.init(SEED, 7);
      long_min := ((2 * STAGES + 6) * PB) / PA + 2 * STAGES + 8;
      wait until rising_edge(clka) and now > 1 us;
      while seq < NX loop
         seq := seq + 1;
         sdata   <= payload(seq, W, 3);
         cur_seq <= seq;
         longh := rng.uni < 0.3;
         if longh then
            hold := long_min + rng.int(0, 20);
         else
            hold := rng.int(1, 3);
         end if;
         for i in 1 to hold loop
            wait until rising_edge(clka);
         end loop;
         if longh and last_dst /= seq then
            errs := errs + 1;
            if errs < 10 then
               say("ERROR after a long hold the destination has " & integer'image(last_dst) &
                   ", source " & integer'image(seq));
            end if;
         end if;
      end loop;
      for i in 1 to long_min loop
         wait until rising_edge(clka);
      end loop;
      if last_dst /= seq then
         errs := errs + 1;
         say("ERROR final value not delivered");
      end if;
      say("RESULT bus_sync PA=" & integer'image(PA) & " PB=" & integer'image(PB) &
          " seed=" & integer'image(SEED) & " meta=" & integer'image(META) &
          " stages=" & integer'image(STAGES) & " changes=" & integer'image(NX) &
          " updates=" & integer'image(n_upd) &
          " errors=" & integer'image(errs + derrs) &
          " lat_dst_edges=" & integer'image(lat_mn) & ".." & integer'image(lat_mx));
      std.env.finish;
   end process;

   -- mirror of the entity's start condition, to time-stamp each value taken
   take : process
      variable sent : std_logic_vector(W - 1 downto 0) := (others => '0');
   begin
      wait until rising_edge(clka);
      if busy = '0' and sdata /= sent then
         t_take(cur_seq mod 4096) <= now;
         sent := sdata;
      end if;
   end process;

   dst : process
      variable last : natural := 0;
      variable s : natural;
      variable low : natural;
      variable errs : natural := 0;
      variable lat : stat_t := STAT_INIT;
      variable l : integer;
      variable n : natural := 0;
   begin
      wait until rising_edge(clkb);
      if upd = '1' then
         low := to_integer(unsigned(ddata(11 downto 0)));
         s := last + 1;
         while s mod 4096 /= low loop
            s := s + 1;
         end loop;
         if s > cur_seq or ddata /= payload(s, W, 3) then
            errs := errs + 1;
            if errs < 10 then
               say("ERROR destination value (torn or out of order) at " & time'image(now));
            end if;
         else
            l := edges_in(t_take(s mod 4096), now - tfs(PB), T0B, PB);
            stat_add(lat, l);
            if l < STAGES + 1 or l > STAGES + 2 then
               errs := errs + 1;
               if errs < 10 then
                  say("ERROR latency " & integer'image(l));
               end if;
            end if;
            last := s;
         end if;
         n := n + 1;
         n_upd    <= n;
         last_dst <= last;
         lat_mn   <= lat.mn;
         lat_mx   <= lat.mx;
      end if;
      derrs <= errs;
   end process;

   -- dst_data may change only together with dst_update
   chk : process
   begin
      wait on ddata;
      wait for 0 ns;
      assert upd = '1' report "dst_data changed without dst_update" severity error;
   end process;

   -- watchdog: a wedged run still ends with a RESULT line
   wd : process
      variable pm : natural := PA;
   begin
      if PB > pm then
         pm := PB;
      end if;
      wait for (NX * 200) * tfs(pm) + 100 us;
      say("RESULT bus_sync PA=" & integer'image(PA) & " PB=" & integer'image(PB) &
          " seed=" & integer'image(SEED) & " TIMEOUT errors=1");
      std.env.finish;
   end process;

end architecture;
