-- cdc_handshake bench: the source issues requests with random gaps and
-- 32-bit payloads; the device answers after 0 to DMAX destination cycles
-- (0 = dst_ack driven combinationally from dst_valid) with a payload derived
-- from the request number. Checks: every request seen once, in order, with
-- its data; every response returned with its data; latencies.

library ieee;
use ieee.std_logic_1164.all;
use work.cdc_tb_pkg.all;

entity tb_cdc_handshake is
   generic (
      PA     : natural  := P_50M;
      PB     : natural  := P_33M;
      SEED   : positive := 1;
      META   : natural  := 1;
      STAGES : natural  := 2;
      DMAX   : natural  := 4;
      NX      : natural  := 50000
   );
end entity;

architecture sim of tb_cdc_handshake is

   constant OFFA : natural := rnd_offset(SEED, 1, PA);
   constant OFFB : natural := rnd_offset(SEED, 2, PB);
   constant T0A  : time := tfs(OFFA);
   constant T0B  : time := tfs(OFFB);
   constant WIN  : time := meta_window(PA, PB, META);
   constant W    : positive := 32;

   signal clka, clkb : std_logic := '0';

   signal start, busy, done_s : std_logic := '0';
   signal req_d, rsp_q        : std_logic_vector(W - 1 downto 0) := (others => '0');
   signal valid, pending      : std_logic;
   signal ack, ack_reg, ack_now : std_logic := '0';
   signal req_q, rsp_d        : std_logic_vector(W - 1 downto 0) := (others => '0');

   type tarr is array (0 to 255) of time;
   type barr is array (0 to 255) of boolean;
   signal t_take : tarr := (others => 0 fs);
   signal t_ack  : tarr := (others => 0 fs);
   signal imm    : barr := (others => false);
   signal n_take : natural := 0;
   signal derrs  : natural := 0;
   signal n_dst  : natural := 0;
   signal lat_req_mn, lat_req_mx : integer := 0;
   signal finished : boolean := false;

begin

   clk_gen(clka, PA, OFFA);
   clk_gen(clkb, PB, OFFB);

   dut : entity work.cdc_handshake
      generic map (REQ_W => W, RSP_W => W, STAGES => STAGES, SIM_META_WINDOW => WIN, SIM_SEED => SEED)
      port map (
         src_clk => clka, src_start => start, src_req_data => req_d,
         src_busy => busy, src_done => done_s, src_rsp_data => rsp_q,
         dst_clk => clkb, dst_valid => valid, dst_req_data => req_q,
         dst_pending => pending, dst_ack => ack, dst_rsp_data => rsp_d);

   ack <= (valid and ack_now) or ack_reg;

   src : process
      variable rng : rng_t;
      variable seq, got : natural := 0;
      variable gap : integer := 0;
      variable errs : natural := 0;
      variable rt, ar : stat_t := STAT_INIT;
      variable rtn : tstat_t := TSTAT_INIT;
      variable l : integer;
      variable tu : time;
   begin
      rng.init(SEED, 7);
      wait until rising_edge(clka) and now > 1 us;
      req_d <= payload(0, W, 1);
      start <= '1';
      loop
         wait until rising_edge(clka);
         -- request taken at this edge?
         if start = '1' and busy = '0' then
            t_take(seq mod 256) <= now;
            seq := seq + 1;
            n_take <= seq;
            start <= '0';
            gap := rng.int(0, 3);
            if rng.uni < 0.2 then
               gap := rng.int(4, 40);
            end if;
         end if;
         -- response
         if done_s = '1' then
            tu := now - tfs(PA);
            if rsp_q /= payload(got, W, 2) then
               errs := errs + 1;
               if errs < 10 then
                  say("ERROR response data, request " & integer'image(got));
               end if;
            end if;
            l := edges_in(t_ack(got mod 256), tu, T0A, PA);
            stat_add(ar, l);
            if l < STAGES + 1 or l > STAGES + 2 then
               errs := errs + 1;
               if errs < 10 then
                  say("ERROR ack latency " & integer'image(l));
               end if;
            end if;
            if imm(got mod 256) then
               stat_add(rt, edges_in(t_take(got mod 256), tu, T0A, PA));
               tstat_add(rtn, tu - t_take(got mod 256));
            end if;
            got := got + 1;
         end if;
         if busy = '1' and done_s = '1' then
            errs := errs + 1;
            say("ERROR busy and done together");
         end if;
         exit when got = NX;
         -- next request
         if start = '0' and seq = got and seq < NX then
            if gap > 0 then
               gap := gap - 1;
            else
               req_d <= payload(seq, W, 1);
               start <= '1';
            end if;
         end if;
      end loop;
      wait for 10 * tfs(PB);
      if n_dst /= NX then
         errs := errs + 1;
         say("ERROR destination saw " & integer'image(n_dst));
      end if;
      say("RESULT handshake PA=" & integer'image(PA) & " PB=" & integer'image(PB) &
          " seed=" & integer'image(SEED) & " meta=" & integer'image(META) &
          " stages=" & integer'image(STAGES) & " n=" & integer'image(got) &
          " errors=" & integer'image(errs + derrs) &
          " req_lat_dst_edges=" & integer'image(lat_req_mn) & ".." & integer'image(lat_req_mx) &
          " ack_lat_src_edges=" & stat_str(ar) &
          " roundtrip0_src_edges=" & stat_str(rt) & " roundtrip0_ns=" & tstat_str(rtn));
      std.env.finish;
   end process;

   dst : process
      variable rng : rng_t;
      variable m : natural := 0;
      variable d : integer := -1;
      variable errs : natural := 0;
      variable lr : stat_t := STAT_INIT;
      variable l : integer;
      variable want_imm : boolean;
   begin
      rng.init(SEED, 14);
      want_imm := rng.uni < 0.4;
      ack_now <= '1' when want_imm else '0';
      rsp_d <= payload(0, W, 2);
      loop
         wait until rising_edge(clkb);
         ack_reg <= '0';
         if valid = '1' then
            if req_q /= payload(m, W, 1) or m >= n_take then
               errs := errs + 1;
               if errs < 10 then
                  say("ERROR request data at destination, request " & integer'image(m));
               end if;
            end if;
            if pending /= '1' then
               errs := errs + 1;
            end if;
            l := edges_in(t_take(m mod 256), now - tfs(PB), T0B, PB);
            stat_add(lr, l);
            if l < STAGES + 1 or l > STAGES + 2 then
               errs := errs + 1;
               if errs < 10 then
                  say("ERROR request latency " & integer'image(l));
               end if;
            end if;
            lat_req_mn <= lr.mn;
            lat_req_mx <= lr.mx;
            imm(m mod 256) <= want_imm;
            if want_imm then
               -- ack was sampled at this edge
               t_ack(m mod 256) <= now;
               m := m + 1;
               n_dst <= m;
               want_imm := rng.uni < 0.4;
               ack_now <= '1' when want_imm else '0';
               rsp_d <= payload(m, W, 2);
            else
               d := rng.int(1, DMAX);
            end if;
         elsif ack_reg = '1' then
            -- delayed ack was sampled at this edge
            t_ack(m mod 256) <= now;
            m := m + 1;
            n_dst <= m;
            want_imm := rng.uni < 0.4;
            ack_now <= '1' when want_imm else '0';
            rsp_d <= payload(m, W, 2);
         elsif d > 0 then
            d := d - 1;
            if d = 0 then
               ack_reg <= '1';
               d := -1;
            end if;
         end if;
         derrs <= errs;
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
      say("RESULT handshake PA=" & integer'image(PA) & " PB=" & integer'image(PB) &
          " seed=" & integer'image(SEED) & " TIMEOUT errors=1");
      std.env.finish;
   end process;

end architecture;
