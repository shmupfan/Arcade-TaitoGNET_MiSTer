-- cdc_fifo bench: random push and pop with rates that change in phases (so
-- the FIFO runs full and empty often), pushes attempted while full and pops
-- while empty, and quiet windows in which both sides stop. Checks: data and
-- order; wr_count never below and rd_count never above the true count;
-- full and empty consistent with the counts; overflow and underflow flags;
-- exact counts at the end of each quiet window. Latency: words written into
-- an empty FIFO, write edge to the read edge after which the word is
-- readable (FWFT: rd_empty low with the word on rd_data; normal mode:
-- rd_empty low).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cdc_tb_pkg.all;

entity tb_cdc_fifo is
   generic (
      PA         : natural  := P_50M;   -- write clock
      PB         : natural  := P_33M;   -- read clock
      SEED       : positive := 1;
      META       : natural  := 1;
      STAGES     : natural  := 2;
      FWFT       : natural  := 1;
      AW         : positive := 4;
      DW         : positive := 34;
      NEG_BINARY : natural  := 0;
      NEG_EARLY  : natural  := 0;
      NX          : natural  := 100000
   );
end entity;

architecture sim of tb_cdc_fifo is

   constant OFFA  : natural := rnd_offset(SEED, 1, PA);
   constant OFFB  : natural := rnd_offset(SEED, 2, PB);
   constant T0B   : time := tfs(OFFB);
   constant WIN   : time := meta_window(PA, PB, META);
   constant DEPTH : natural := 2 ** AW;
   constant QP    : time := 25 us;    -- quiet window period
   constant QL    : time := 1.5 us;   -- quiet window length

   signal clka, clkb : std_logic := '0';
   signal wr_en, rd_en : std_logic := '0';
   signal wr_data, rd_data : std_logic_vector(DW - 1 downto 0) := (others => '0');
   signal full, ovf, empty, rvalid, unf : std_logic;
   signal wcount, rcount : std_logic_vector(AW downto 0);

   type tarr is array (0 to 1023) of time;
   type barr is array (0 to 1023) of boolean;
   signal t_wr     : tarr := (others => 0 fs);
   signal into_mt  : barr := (others => false);
   signal pushed   : natural := 0;
   signal popped   : natural := 0;
   signal derrs    : natural := 0;
   signal rd_done  : boolean := false;
   signal lat_mn, lat_mx : integer := 0;
   signal c_empty, c_unf : natural := 0;

   function in_quiet(t : time) return boolean is
   begin
      return (t mod QP) < QL;
   end function;
   function quiet_end(t : time) return boolean is
   begin
      return (t mod QP) < QL and (t mod QP) > QL - 0.2 us;
   end function;

begin

   clk_gen(clka, PA, OFFA);
   clk_gen(clkb, PB, OFFB);

   dut : entity work.cdc_fifo
      generic map (DATA_W => DW, ADDR_W => AW, FWFT => FWFT = 1, STAGES => STAGES,
                   NEG_BINARY => NEG_BINARY = 1, NEG_EARLY_FREE => NEG_EARLY = 1, SIM_META_WINDOW => WIN, SIM_SEED => SEED)
      port map (
         wr_clk => clka, wr_en => wr_en, wr_data => wr_data, wr_full => full,
         wr_count => wcount, wr_overflow => ovf,
         rd_clk => clkb, rd_en => rd_en, rd_data => rd_data, rd_empty => empty,
         rd_valid => rvalid, rd_count => rcount, rd_underflow => unf);

   wr : process
      variable rng : rng_t;
      variable p : real := 0.5;
      variable ph : integer := 0;
      variable n : natural := 0;
      variable errs : natural := 0;
      variable exp_ovf : std_logic := '0';
      variable c_full, c_ovf, maxc, qchk : natural := 0;
      variable wc : natural;
      variable occ : integer;
   begin
      rng.init(SEED, 7);
      wait until rising_edge(clka) and now > 2 us;
      loop
         wait until rising_edge(clka);
         wc  := to_integer(unsigned(wcount));
         occ := n - popped;
         -- write-side invariants (pre-edge values)
         if wc < occ or wc > DEPTH or (full = '1') /= (wc = DEPTH) or ovf /= exp_ovf then
            errs := errs + 1;
            if errs < 10 then
               say("ERROR write side: wr_count " & integer'image(wc) & " true " & integer'image(occ) &
                   " full " & std_logic'image(full) & " at " & time'image(now));
            end if;
         end if;
         if full = '1' then c_full := c_full + 1; end if;
         if wc > maxc then maxc := wc; end if;
         exp_ovf := wr_en and full;
         if wr_en = '1' and full = '1' then c_ovf := c_ovf + 1; end if;
         -- push taken at this edge?
         if wr_en = '1' and full = '0' then
            t_wr(n mod 1024)    <= now;
            into_mt(n mod 1024) <= (occ = 0);
            n := n + 1;
            pushed <= n;
         end if;
         if quiet_end(now) and n < NX then
            qchk := qchk + 1;
            if wc /= occ then
               errs := errs + 1;
               if errs < 10 then
                  say("ERROR write count after quiet window " & integer'image(wc) & " true " & integer'image(occ));
               end if;
            end if;
         end if;
         exit when n >= NX;
         -- next cycle
         ph := ph - 1;
         if ph <= 0 then
            ph := rng.int(20, 400);
            case rng.int(0, 4) is
               when 0 => p := 0.05;
               when 1 => p := 0.3;
               when 2 => p := 0.6;
               when 3 => p := 0.9;
               when others => p := 1.0;
            end case;
         end if;
         wr_data <= payload(n, DW, 4);
         if in_quiet(now + tfs(PA)) then
            wr_en <= '0';
         elsif rng.uni < p then
            wr_en <= '1';
         else
            wr_en <= '0';
         end if;
      end loop;
      wr_en <= '0';
      wait until rd_done;
      wait for 5 * tfs(PB);
      say("RESULT fifo PA=" & integer'image(PA) & " PB=" & integer'image(PB) &
          " seed=" & integer'image(SEED) & " meta=" & integer'image(META) &
          " fwft=" & integer'image(FWFT) & " depth=" & integer'image(DEPTH) &
          " stages=" & integer'image(STAGES) & " neg_binary=" & integer'image(NEG_BINARY) & " neg_early=" & integer'image(NEG_EARLY) &
          " n=" & integer'image(NX) & " popped=" & integer'image(popped) &
          " errors=" & integer'image(errs + derrs) &
          " lat_rd_edges=" & integer'image(lat_mn) & ".." & integer'image(lat_mx) &
          " full_cycles=" & integer'image(c_full) & " overflow_attempts=" & integer'image(c_ovf) &
          " empty_cycles=" & integer'image(c_empty) & " underflow_attempts=" & integer'image(c_unf) &
          " max_wr_count=" & integer'image(maxc) & " quiet_checks=" & integer'image(qchk));
      std.env.finish;
   end process;

   rd : process
      variable rng : rng_t;
      variable p : real := 0.5;
      variable ph : integer := 0;
      variable m : natural := 0;       -- words taken
      variable chk : natural := 0;     -- words whose data was checked
      variable pend : boolean := false; -- normal mode: data due this edge
      variable errs : natural := 0;
      variable exp_unf : std_logic := '0';
      variable rc : natural;
      variable occ : integer;
      variable lat : stat_t := STAT_INIT;
      variable latd : natural := 0;    -- latency measured up to this word
      variable l : integer;
      variable ce, cu : natural := 0;
      variable idle : natural := 0;
   begin
      rng.init(SEED, 14);
      loop
         wait until rising_edge(clkb);
         rc  := to_integer(unsigned(rcount));
         occ := pushed - m;
         -- read-side invariants
         if rc > occ or rc < 0 or unf /= exp_unf then
            errs := errs + 1;
            if errs < 10 then
               say("ERROR read side: rd_count " & integer'image(rc) & " true " & integer'image(occ) &
                   " at " & time'image(now));
            end if;
         end if;
         if FWFT = 1 then
            if empty = '0' and rc < 1 then
               errs := errs + 1;
            end if;
         elsif (empty = '1') /= (rc = 0) then
            errs := errs + 1;
         end if;
         if empty = '1' then ce := ce + 1; end if;
         exp_unf := rd_en and empty;
         if rd_en = '1' and empty = '1' then cu := cu + 1; end if;
         -- normal mode: data of the previous pop
         if FWFT = 0 then
            if pend then
               if rvalid /= '1' or rd_data /= payload(chk, DW, 4) then
                  errs := errs + 1;
                  if errs < 10 then
                     say("ERROR read data, word " & integer'image(chk) & " at " & time'image(now));
                  end if;
               end if;
               chk := chk + 1;
            elsif rvalid = '1' then
               errs := errs + 1;
            end if;
         end if;
         -- latency: head word written into an empty FIFO, first edge it is readable
         if empty = '0' and latd <= m and m < pushed then
            if into_mt(m mod 1024) then
               l := edges_in(t_wr(m mod 1024), now - tfs(PB), T0B, PB);
               stat_add(lat, l);
            end if;
            latd := m + 1;
         end if;
         pend := false;
         -- pop at this edge?
         if rd_en = '1' and empty = '0' then
            if FWFT = 1 then
               if rd_data /= payload(m, DW, 4) then
                  errs := errs + 1;
                  if errs < 10 then
                     say("ERROR read data, word " & integer'image(m) & " at " & time'image(now));
                  end if;
               end if;
               chk := chk + 1;
            else
               pend := true;
            end if;
            m := m + 1;
            popped <= m;
         end if;
         if quiet_end(now) and m < NX then
            if rc /= occ then
               errs := errs + 1;
               if errs < 10 then
                  say("ERROR read count after quiet window " & integer'image(rc) & " true " & integer'image(occ));
               end if;
            end if;
         end if;
         derrs   <= errs;
         lat_mn  <= lat.mn;
         lat_mx  <= lat.mx;
         c_empty <= ce;
         c_unf   <= cu;
         if m >= NX and not pend then
            idle := idle + 1;
         end if;
         exit when idle > 4;
         ph := ph - 1;
         if ph <= 0 then
            ph := rng.int(20, 400);
            case rng.int(0, 4) is
               when 0 => p := 0.05;
               when 1 => p := 0.3;
               when 2 => p := 0.6;
               when 3 => p := 0.9;
               when others => p := 1.0;
            end case;
         end if;
         if in_quiet(now + tfs(PB)) or m >= NX then
            rd_en <= '0';
         elsif rng.uni < p then
            rd_en <= '1';
         else
            rd_en <= '0';
         end if;
      end loop;
      rd_done <= true;
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
      say("RESULT fifo PA=" & integer'image(PA) & " PB=" & integer'image(PB) &
          " seed=" & integer'image(SEED) & " TIMEOUT errors=1");
      std.env.finish;
   end process;

end architecture;
