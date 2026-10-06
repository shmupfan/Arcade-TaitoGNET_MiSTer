-- Bench for rtl/gnet/zn2_ch3_arb.vhd as PSX.sv wires it with GNET_ZN2 and
-- GNET_CPU50: the downloads (BIOS, flash images) from clk1x through the
-- channel 3 cdc_handshake, zn2_board's flash port on clk_cpu, one sdram.sv
-- channel 3 model on clk_cpu (docs/r1_cpu_domain_design.md, "ZN-2 layer in
-- the CPU group").
--
--   A (clk1x)   download writes as PSX.sv makes them: a one-cycle
--               ramdownload_wr into the handshake, the next word after
--               src_done (ioctl_wait), gaps of 1 to 20 cycles
--   B (clk_cpu) zn2_board's flash adapter: a one-cycle fl_req with the
--               fields held, reads with all byte enables, 16-bit writes on
--               one lane, the next request after fl_ready; reads checked
--               against a shadow of B's area
--   ch3 model   takes a one-cycle ch3_req, checks that the fields stay
--               unchanged until ch3_ready (sdram.sv copies them on every
--               fast edge), answers after 1 to 12 cycles with a one-cycle
--               ready (one in ten three cycles long, which the arbiter's
--               idle cycle must absorb), fails a request that comes while
--               one is open
-- At the end A's area must hold every downloaded word.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.cdc_tb_pkg.all;

entity tb_zn2_ch3_arb is
   generic (
      PA     : natural  := P_50M;     -- clk_cpu
      PB     : natural  := P_33M;     -- clk1x
      SEED   : positive := 1;
      META   : natural  := 1;
      N_A    : natural  := 4000;
      N_B    : natural  := 20000;
      OUTTAG : string   := "run"
   );
end entity;

architecture sim of tb_zn2_ch3_arb is

   constant OFFA : natural := rnd_offset(SEED, 1, PA);
   constant OFFB : natural := rnd_offset(SEED, 2, PB);
   constant WIN  : time := meta_window(PA, PB, META);
   constant A_BASE : natural := 16#0800000#;
   constant B_BASE : natural := 16#1000000#;
   constant NB     : natural := 256;

   signal clk_cpu, clk1x : std_logic := '0';

   signal a_start  : std_logic := '0';
   signal a_reqd   : std_logic_vector(63 downto 0) := (others => '0');
   signal a_done   : std_logic;
   signal h_req, h_ack, h_rnw : std_logic;
   signal h_addr   : std_logic_vector(26 downto 0);
   signal h_din    : std_logic_vector(31 downto 0);
   signal h_be     : std_logic_vector(3 downto 0);
   signal h_data   : std_logic_vector(63 downto 0);

   signal b_req    : std_logic := '0';
   signal b_rnw    : std_logic := '1';
   signal b_addr   : std_logic_vector(26 downto 0) := (others => '0');
   signal b_din    : std_logic_vector(31 downto 0) := (others => '0');
   signal b_be     : std_logic_vector(3 downto 0) := (others => '0');
   signal b_ready  : std_logic;

   signal c_req, c_rnw, c_ready : std_logic := '0';
   signal c_addr   : std_logic_vector(26 downto 0);
   signal c_din    : std_logic_vector(31 downto 0);
   signal c_be     : std_logic_vector(3 downto 0);
   signal c_dout   : std_logic_vector(31 downto 0) := (others => '0');

   signal b_waiting : boolean := false;
   signal a_finished, b_finished : boolean := false;
   signal errs_a, errs_b, errs_m, errs_r : natural := 0;
   signal cnt_a, cnt_b, n_ch3, n_long : natural := 0;

   type t_amem is array (0 to N_A - 1) of std_logic_vector(31 downto 0);
   type t_bmem is array (0 to NB - 1) of std_logic_vector(31 downto 0);

   function a_word(i : natural) return std_logic_vector is
   begin
      return std_logic_vector(to_unsigned((i * 26543) mod 65536, 16)) & std_logic_vector(to_unsigned((i * 40503 + 7) mod 65536, 16));
   end function;

   function b_init(i : natural) return std_logic_vector is
   begin
      return std_logic_vector(to_unsigned((i * 977 + 3) mod 65536, 16)) & std_logic_vector(to_unsigned((i * 3571 + 11) mod 65536, 16));
   end function;

begin

   clk_gen(clk_cpu, PA, OFFA);
   clk_gen(clk1x, PB, OFFB);

   -- PSX.sv: cdc_handshake #(.REQ_W(64), .RSP_W(32)) ch3_cdc
   uh : entity work.cdc_handshake
      generic map (REQ_W => 64, RSP_W => 32, SIM_META_WINDOW => WIN, SIM_SEED => SEED)
      port map (
         src_clk => clk1x, src_start => a_start, src_req_data => a_reqd,
         src_busy => open, src_done => a_done, src_rsp_data => open,
         dst_clk => clk_cpu, dst_valid => h_req, dst_req_data => h_data,
         dst_pending => open, dst_ack => h_ack, dst_rsp_data => c_dout);
   h_addr <= h_data(63 downto 37);
   h_din  <= h_data(36 downto 5);
   h_rnw  <= h_data(4);
   h_be   <= h_data(3 downto 0);

   dut : entity work.zn2_ch3_arb
      port map (
         clk => clk_cpu,
         a_req => h_req, a_addr => h_addr, a_din => h_din, a_rnw => h_rnw, a_be => h_be, a_ready => h_ack,
         b_req => b_req, b_addr => b_addr, b_din => b_din, b_rnw => b_rnw, b_be => b_be, b_ready => b_ready,
         ch3_req => c_req, ch3_addr => c_addr, ch3_din => c_din, ch3_rnw => c_rnw, ch3_be => c_be,
         ch3_ready => c_ready);

   ------------------------------------------------------------ A: downloads (clk1x)
   process
      variable rng : rng_t;
      variable n   : natural;
      variable ea  : natural := 0;
   begin
      rng.init(SEED * 3 + 1, 5);
      wait for 1 us;
      for i in 0 to N_A - 1 loop
         wait until rising_edge(clk1x);
         a_reqd  <= std_logic_vector(to_unsigned(A_BASE + 4 * i, 27)) & a_word(i) & '0' & "1111";
         a_start <= '1';
         wait until rising_edge(clk1x);
         a_start <= '0';
         n := 0;
         loop
            exit when a_done = '1';
            wait until rising_edge(clk1x);
            n := n + 1;
            if n > 5000 then
               report "download word " & integer'image(i) & " timed out" severity error;
               ea := ea + 1;
               errs_a <= ea;
               exit;
            end if;
         end loop;
         cnt_a <= i + 1;
         for k in 1 to rng.int(1, 20) loop wait until rising_edge(clk1x); end loop;
      end loop;
      a_finished <= true;
      wait;
   end process;

   ------------------------------------------------------------ B: flash port (clk_cpu)
   process
      variable rng : rng_t;
      variable sh  : t_bmem;
      variable k, n : integer;
      variable wr, hi : boolean;
      variable d16 : std_logic_vector(15 downto 0);
      variable e   : natural := 0;
   begin
      rng.init(SEED * 7 + 3, 9);
      for i in 0 to NB - 1 loop sh(i) := b_init(i); end loop;
      wait for 1 us;
      for op in 1 to N_B loop
         for g in 1 to rng.int(0, 5) loop wait until rising_edge(clk_cpu); end loop;
         wait until rising_edge(clk_cpu);
         k   := rng.int(0, NB - 1);
         wr  := rng.int(0, 3) = 0;
         hi  := rng.int(0, 1) = 1;
         d16 := std_logic_vector(to_unsigned(rng.int(0, 65535), 16));
         b_addr <= std_logic_vector(to_unsigned(B_BASE + 4 * k, 27));
         b_din  <= d16 & d16;
         if wr then
            b_rnw <= '0';
            b_be  <= "1100" when hi else "0011";
         else
            b_rnw <= '1';
            b_be  <= "1111";
         end if;
         b_req <= '1';
         b_waiting <= true;
         wait until rising_edge(clk_cpu);
         b_req <= '0';
         n := 0;
         loop
            exit when b_ready = '1';
            wait until rising_edge(clk_cpu);
            n := n + 1;
            if n > 5000 then
               report "B op timed out" severity error;
               e := e + 1;
               exit;
            end if;
         end loop;
         b_waiting <= false;
         if wr then
            if hi then sh(k)(31 downto 16) := d16; else sh(k)(15 downto 0) := d16; end if;
         elsif c_dout /= sh(k) then
            report "B read " & integer'image(k) & ": " & to_hstring(c_dout) & ", expected " & to_hstring(sh(k)) severity error;
            e := e + 1;
         end if;
         cnt_b <= op;
         errs_b <= e;
      end loop;
      b_finished <= true;
      wait;
   end process;

   -- a B ready must find B waiting
   process (clk_cpu)
      variable e : natural := 0;
   begin
      if rising_edge(clk_cpu) then
         if b_ready = '1' and not b_waiting then
            report "B ready with no B request open" severity error;
            e := e + 1;
            errs_r <= e;
         end if;
      end if;
   end process;

   ------------------------------------------------------------ channel 3 model (clk_cpu)
   process
      variable rng  : rng_t;
      variable am   : t_amem := (others => (others => 'U'));
      variable bm   : t_bmem;
      variable addr : std_logic_vector(26 downto 0);
      variable din  : std_logic_vector(31 downto 0);
      variable rnw  : std_logic;
      variable be   : std_logic_vector(3 downto 0);
      variable a, idx : integer;
      variable v    : std_logic_vector(31 downto 0);
      variable e    : natural := 0;
      variable nc, nl : natural := 0;
      variable bad  : natural := 0;
   begin
      rng.init(SEED * 11 + 5, 13);
      for i in 0 to NB - 1 loop bm(i) := b_init(i); end loop;
      loop
         wait until rising_edge(clk_cpu);
         if a_finished and b_finished then
            exit;
         end if;
         if c_req = '1' then
            nc := nc + 1;
            addr := c_addr; din := c_din; rnw := c_rnw; be := c_be;
            for k in 1 to rng.int(1, 12) loop
               wait until rising_edge(clk_cpu);
               if c_req = '1' then
                  report "ch3 request while one is open" severity error; e := e + 1;
               end if;
               if c_addr /= addr or c_din /= din or c_rnw /= rnw or c_be /= be then
                  report "ch3 fields changed before ready" severity error; e := e + 1;
               end if;
            end loop;
            a := to_integer(unsigned(addr));
            if a >= B_BASE and a < B_BASE + 4 * NB then
               idx := (a - B_BASE) / 4;
               if rnw = '1' then
                  c_dout <= bm(idx);
               else
                  v := bm(idx);
                  for b in 0 to 3 loop
                     if be(b) = '1' then v(8 * b + 7 downto 8 * b) := din(8 * b + 7 downto 8 * b); end if;
                  end loop;
                  bm(idx) := v;
               end if;
            elsif a >= A_BASE and a < A_BASE + 4 * N_A and rnw = '0' and be = "1111" then
               am((a - A_BASE) / 4) := din;
            else
               report "ch3 request outside both areas or not a download write" severity error; e := e + 1;
            end if;
            c_ready <= '1';
            wait until rising_edge(clk_cpu);
            if rng.int(0, 9) = 0 then
               nl := nl + 1;
               wait until rising_edge(clk_cpu);   -- ready three cycles long
               wait until rising_edge(clk_cpu);
            end if;
            c_ready <= '0';
         end if;
         n_ch3 <= nc; n_long <= nl; errs_m <= e;
      end loop;
      for i in 0 to N_A - 1 loop
         if am(i) /= a_word(i) then
            bad := bad + 1;
         end if;
      end loop;
      if bad > 0 then
         report integer'image(bad) & " downloaded words missing or wrong" severity error;
      end if;
      errs_m <= e + bad;
      n_ch3 <= nc; n_long <= nl;
      wait for 1 us;
      say("RESULT " & OUTTAG & " zn2_ch3_arb PA=" & integer'image(PA) & " PB=" & integer'image(PB) &
          " SEED=" & integer'image(SEED) & " META=" & integer'image(META) &
          " downloads " & integer'image(cnt_a) & " flash_ops " & integer'image(cnt_b) & " ch3 " & integer'image(nc) &
          " long_ready " & integer'image(nl) & " errors " & integer'image(e + bad + errs_a + errs_b + errs_r));
      stop;
   end process;

end architecture;
