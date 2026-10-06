-- Bench for rtl/gnet/zoom_cdc.vhd, rtl/gnet/zoom_sdram_link.vhd and
-- rtl/gnet/zn2_ch3_arb.vhd as psx_top and PSX.sv wire them for GNET_ZOOM
-- with GNET_ZOOM_SDRAM (docs/zoom_board_design.md 14):
--
--   H (clk_cpu)  zn2_board's zm_* port as memorymux drives it: a one-cycle
--                request, the next one after the ack. Phase 1 is the game's
--                reset release (control bit 4 set, the 256 mailbox bytes
--                cleared through lanes 0 and 2, bit 4 cleared); phase 2 is
--                N_H random accesses: mailbox reads and writes on every lane
--                mask the 16-bit bus produces, doorbell and volume writes,
--                status reads, and addresses zoom_board does not decode
--   R (clk1x)    stands in for zoom_board's host side: h_hit decoded as
--                zoom_host.sv, h_ack one to three cycles after h_req (two
--                for mailbox reads), dropped if the board reset comes in
--                between (zoom_host clears its pending read in reset). Every
--                request carries a sequence number in its data: write data
--                and read answers are functions of (address, sequence), so a
--                lost, repeated or reordered request fails the check
--   L (clk1x)    zoom_memarb's side of the line port: m_req and m_line held
--                until m_ready, N_L lines, data checked against the memory
--                model as {word at 8L + 4, word at 8L}
--   B (clk_cpu)  zn2_board's flash port on zn2_ch3_arb port b at the same
--                time: N_B reads of the U30 area, checked
--   ch3 model    one request at a time, fields checked stable until ready,
--                1 to 12 cycles, one ready in ten three cycles long; reads
--                with byte enables other than 1111 are errors and read A5h
--                in the masked lanes (read DQM on the real SDRAM)
--   Z2           p_zoom_reset is 1 from time 0 until the release, falls
--                only after every clearing write reached R, and follows
--                c_zoom_reset within 5 clk1x edges (source register, two
--                synchroniser stages, one late resolution, sampling edge)
-- RST_PER > 0 adds random resets (c_board_rst every about RST_PER host ops,
-- p_board_rst as often): the masters abandon what is open, and the checks
-- become: no ack or rvalid without an open request, no hang, read answers
-- either right or 0 (a request that met the board's reset).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.cdc_tb_pkg.all;

entity tb_zoom_cdc is
   generic (
      PA      : natural  := P_50M;     -- clk_cpu
      PB      : natural  := P_33M;     -- clk1x
      SEED    : positive := 1;
      META    : natural  := 1;
      N_H     : natural  := 4000;
      N_L     : natural  := 4000;
      N_B     : natural  := 2000;
      RST_PER : natural  := 0;
      OUTTAG  : string   := "run"
   );
end entity;

architecture sim of tb_zoom_cdc is

   constant OFFA : natural := rnd_offset(SEED, 1, PA);
   constant OFFB : natural := rnd_offset(SEED, 2, PB);
   constant WIN  : time := meta_window(PA, PB, META);
   constant FLASH_BASE : natural := 16#1000000#;

   signal clk_cpu, clk1x : std_logic := '0';
   signal c_rst, p_rst   : std_logic := '0';

   -- H
   signal zm_req, zm_we  : std_logic := '0';
   signal zm_addr        : unsigned(23 downto 0) := (others => '0');
   signal zm_be          : std_logic_vector(3 downto 0) := (others => '0');
   signal zm_wdata       : std_logic_vector(31 downto 0) := (others => '0');
   signal zm_ack         : std_logic;
   signal zm_rdata       : std_logic_vector(31 downto 0);
   signal zrst_c         : std_logic := '1';
   signal zrst_p         : std_logic;
   -- R
   signal h_req, h_we    : std_logic;
   signal h_addr         : std_logic_vector(23 downto 0);
   signal h_be           : std_logic_vector(3 downto 0);
   signal h_wdata        : std_logic_vector(31 downto 0);
   signal h_ack          : std_logic := '0';
   signal h_rdata        : std_logic_vector(31 downto 0) := (others => '0');
   signal h_hit          : std_logic;
   -- L
   signal m_req          : std_logic := '0';
   signal m_line         : std_logic_vector(20 downto 0) := (others => '0');
   signal m_ready, m_rvalid : std_logic;
   signal m_rdata        : std_logic_vector(63 downto 0);
   -- SDRAM side
   signal fl_req         : std_logic;
   signal fl_addr        : std_logic_vector(26 downto 0);
   signal fl_ready       : std_logic;
   signal b_req          : std_logic := '0';
   signal b_addr         : std_logic_vector(26 downto 0) := (others => '0');
   signal b_ready        : std_logic;
   signal c_req, c_rnw, c_ready : std_logic := '0';
   signal c_addr         : std_logic_vector(26 downto 0);
   signal c_din          : std_logic_vector(31 downto 0);
   signal c_be           : std_logic_vector(3 downto 0);
   signal c_dout         : std_logic_vector(31 downto 0) := (others => '0');

   -- bookkeeping between processes
   signal r_seq          : natural := 0;          -- requests R has taken
   signal r_clear_done   : natural := 0;          -- clearing writes R has seen
   signal h_open         : boolean := false;      -- H waits for an ack
   signal l_open         : boolean := false;      -- L waits for a line
   signal h_fin, l_fin, b_fin : boolean := false;
   signal released       : boolean := false;
   signal cnt_h, cnt_l, cnt_b, n_zero, n_ch3, n_long, n_rst : natural := 0;
   signal errs_h, errs_r, errs_l, errs_b, errs_z, errs_s, errs_v, errs_p : natural := 0;

   function mem_word(a : natural) return std_logic_vector is   -- a: byte address, multiple of 4
      variable x : unsigned(63 downto 0);
   begin
      x := to_unsigned((a / 4) mod 2**30, 32) * to_unsigned(1640531535, 32);
      return std_logic_vector(x(47 downto 16));
   end function;

   -- host data as a function of address and sequence number
   function hval(a : std_logic_vector(23 downto 0); seq : natural) return std_logic_vector is
   begin
      return payload(seq, 32, to_integer(unsigned(a(11 downto 0))));
   end function;

   function zoom_hit(a : std_logic_vector(23 downto 0)) return std_logic is
   begin
      if a(23 downto 2) = x"B8000" & "00" or a(23 downto 2) = x"BA000" & "00" or
         a(23 downto 2) = x"BC000" & "00" or a(23 downto 9) = x"BE0" & "000" then
         return '1';
      end if;
      return '0';
   end function;

begin

   clk_gen(clk_cpu, PA, OFFA);
   clk_gen(clk1x, PB, OFFB);

   dut : entity work.zoom_cdc
      generic map (SIM_META_WINDOW => WIN)
      port map (
         clk_cpu => clk_cpu, clk1x => clk1x, c_board_rst => c_rst, p_board_rst => p_rst,
         c_zm_req => zm_req, c_zm_we => zm_we, c_zm_addr => zm_addr, c_zm_be => zm_be, c_zm_wdata => zm_wdata,
         c_zm_ack => zm_ack, c_zm_rdata => zm_rdata,
         p_h_req => h_req, p_h_we => h_we, p_h_addr => h_addr, p_h_be => h_be, p_h_wdata => h_wdata,
         p_h_ack => h_ack, p_h_rdata => h_rdata, p_h_hit => h_hit,
         c_zoom_reset => zrst_c, p_zoom_reset => zrst_p);

   -- PSX.sv GNET_ZOOM_SDRAM: the temporary SDRAM path, reset by zoom_board's reset
   dut_l : entity work.zoom_sdram_link
      generic map (FLASH_BASE => FLASH_BASE, SIM_META_WINDOW => WIN)
      port map (
         clk_cpu => clk_cpu, clk1x => clk1x, p_board_rst => p_rst,
         p_m_req => m_req, p_m_line => m_line, p_m_ready => m_ready, p_m_rvalid => m_rvalid, p_m_rdata => m_rdata,
         c_fl_req => fl_req, c_fl_addr => fl_addr, c_fl_ready => fl_ready, c_fl_dout => c_dout);

   -- PSX.sv: port a idle here (downloads hold the core in reset), b the
   -- glue's flash port, c the Zoom with byte enables 1111
   arb : entity work.zn2_ch3_arb
      port map (
         clk => clk_cpu,
         a_req => '0', a_addr => (others => '0'), a_din => (others => '0'), a_rnw => '1', a_be => "1111", a_ready => open,
         b_req => b_req, b_addr => b_addr, b_din => (others => '0'), b_rnw => '1', b_be => "1111", b_ready => b_ready,
         c_req => fl_req, c_addr => fl_addr, c_din => (others => '0'), c_rnw => '1', c_be => "1111", c_ready => fl_ready,
         ch3_req => c_req, ch3_addr => c_addr, ch3_din => c_din, ch3_rnw => c_rnw, ch3_be => c_be,
         ch3_ready => c_ready);

   h_hit <= zoom_hit(h_addr);

   ------------------------------------------------------------ H: host master (clk_cpu)
   process
      variable rng : rng_t;
      variable e, nz, nr : natural := 0;
      variable seq : natural := 0;      -- requests that reach R
      variable k, n, kind : integer;
      variable a : std_logic_vector(23 downto 0);
      variable be : std_logic_vector(3 downto 0);
      variable we, hit, got, rstd : boolean;
      variable exp : std_logic_vector(31 downto 0);

      procedure host_access(a_v : std_logic_vector(23 downto 0); be_v : std_logic_vector(3 downto 0); we_v : boolean;
                        variable got_v : out boolean) is
         variable cnt : natural := 0;
      begin
         got_v := false;
         wait until rising_edge(clk_cpu);
         zm_addr  <= unsigned(a_v);
         zm_be    <= be_v;
         zm_we    <= '1' when we_v else '0';
         zm_wdata <= hval(a_v, seq) when we_v else x"DEADBEEF";
         zm_req   <= '1';
         h_open   <= true;
         wait until rising_edge(clk_cpu);
         zm_req   <= '0';
         loop
            if zm_ack = '1' then
               got_v := true;
               exit;
            end if;
            exit when c_rst = '1';                -- memorymux is reset with zn2_board
            wait until rising_edge(clk_cpu);
            cnt := cnt + 1;
            if cnt > 20000 then
               report "host access " & to_hstring(a_v) & " timed out" severity error;
               e := e + 1;
               exit;
            end if;
         end loop;
         h_open <= false;
      end procedure;
   begin
      rng.init(SEED * 3 + 1, 5);
      wait for 2 us;
      -- phase 1: the game's reset release (control |= 0x10, clear the
      -- mailbox, bit 4 cleared); bit 3 has no Zoom function in MAME
      zrst_c <= '1';
      for i in 0 to 127 loop
         for h in 0 to 1 loop
            a  := std_logic_vector(to_unsigned(16#BE0000# + 4 * i + 2 * h, 24));
            be := "0011" when h = 0 else "1100";
            host_access(a, be, true, got);
            seq := seq + 1;
         end loop;
      end loop;
      wait until rising_edge(clk_cpu);
      zrst_c   <= '0';
      released <= true;
      -- phase 2: random accesses
      for op in 1 to N_H loop
         for g in 1 to rng.int(0, 6) loop wait until rising_edge(clk_cpu); end loop;
         kind := rng.int(0, 9);
         k    := rng.int(0, 127);
         we   := rng.int(0, 1) = 1;
         case kind is
            when 0 to 4 =>                                      -- mailbox, 16-bit bus steps
               case rng.int(0, 3) is
                  when 0 => a := std_logic_vector(to_unsigned(16#BE0000# + 4 * k, 24)); be := "0011";
                  when 1 => a := std_logic_vector(to_unsigned(16#BE0000# + 4 * k + 2, 24)); be := "1100";
                  when 2 => a := std_logic_vector(to_unsigned(16#BE0000# + 4 * k, 24)); be := "0001";
                  when others => a := std_logic_vector(to_unsigned(16#BE0000# + 4 * k + 2, 24)); be := "0100";
               end case;
            when 5 => a := x"BA0000"; be := "0011"; we := true;  -- doorbell
            when 6 => a := x"BC0000"; be := "0011"; we := false; -- status
            when 7 => a := x"B80000"; be := "0011" when rng.int(0, 1) = 0 else "1100";   -- volume data / address
            when 8 => a := std_logic_vector(to_unsigned(16#BE0200# + 4 * k, 24)); be := "0011";  -- not decoded
            when others => a := std_logic_vector(to_unsigned(16#BA0004# + 4 * k, 24)); be := "1100";  -- not decoded
         end case;
         if be = "0000" then be := "0011"; end if;
         hit  := zoom_hit(a) = '1';
         rstd := false;
         host_access(a, be, we, got);
         if c_rst = '1' then
            -- abandoned; R may or may not have taken it: take R's count once
            -- the crossing is quiet again
            nr := nr + 1;
            for q in 1 to 200 loop wait until rising_edge(clk_cpu); end loop;
            seq := r_seq;
            next;
         end if;
         if hit then
            if not got then
               null;
            elsif not we then
               exp := hval(a, seq);
               if zm_rdata /= exp then
                  if zm_rdata = x"00000000" and RST_PER > 0 then
                     nz := nz + 1;                 -- met the board's reset: answered 0
                  else
                     report "host read " & to_hstring(a) & " seq " & integer'image(seq) & ": " & to_hstring(zm_rdata) &
                            ", expected " & to_hstring(exp) severity error;
                     e := e + 1;
                  end if;
               end if;
            end if;
            if RST_PER > 0 and r_seq /= seq + 1 then
               seq := r_seq;                       -- request dropped by a board reset on the clk1x side
            else
               seq := seq + 1;
            end if;
         elsif got and zm_rdata /= x"00000000" then
            report "undecoded address " & to_hstring(a) & " answered " & to_hstring(zm_rdata) severity error;
            e := e + 1;
         end if;
         cnt_h <= op;
         errs_h <= e;
         n_zero <= nz;
      end loop;
      h_fin <= true;
      wait;
   end process;

   -- an ack must find H waiting
   process (clk_cpu)
      variable e : natural := 0;
   begin
      if rising_edge(clk_cpu) then
         if zm_ack = '1' and not h_open then
            report "host ack with no request open" severity error;
            e := e + 1;
            errs_s <= e;
         end if;
      end if;
   end process;

   ------------------------------------------------------------ R: zoom_board's host side (clk1x)
   process
      variable rng : rng_t;
      variable seq, e, nclr : natural := 0;
      variable a : std_logic_vector(23 downto 0);
      variable we : std_logic;
      variable lat : integer;
      variable dropped : boolean;
   begin
      rng.init(SEED * 5 + 2, 7);
      loop
         wait until rising_edge(clk1x);
         if h_req = '1' then
            if h_hit = '0' or p_rst = '1' then
               report "h_req for an undecoded address or in reset" severity error;
               e := e + 1;
            end if;
            a  := h_addr;
            we := h_we;
            if we = '1' and h_wdata /= hval(a, seq) then
               report "R write " & to_hstring(a) & " seq " & integer'image(seq) & ": " & to_hstring(h_wdata) &
                      ", expected " & to_hstring(hval(a, seq)) severity error;
               e := e + 1;
            end if;
            if not released then
               nclr := nclr + 1;
               r_clear_done <= nclr;
            end if;
            if we = '0' and a(23 downto 16) = x"BE" then lat := 2; else lat := rng.int(1, 3); end if;
            dropped := false;
            for i in 1 to lat - 1 loop
               wait until rising_edge(clk1x);
               if h_req = '1' then
                  report "h_req while one is open" severity error;
                  e := e + 1;
               end if;
               if p_rst = '1' then dropped := true; end if;
            end loop;
            seq := seq + 1;
            r_seq <= seq;
            if not dropped then
               h_ack   <= '1';
               h_rdata <= hval(a, seq - 1) when we = '0' else (others => '0');
               wait until rising_edge(clk1x);
               h_ack   <= '0';
               h_rdata <= x"A5A5A5A5";
            end if;
            errs_r <= e;
         end if;
      end loop;
   end process;

   ------------------------------------------------------------ Z2: zoom reset level (clk1x)
   process (clk1x)
      variable e : natural := 0;
      variable lag : natural := 0;
      variable seen_rel : boolean := false;
   begin
      if rising_edge(clk1x) then
         if zrst_p = '0' and not seen_rel then
            seen_rel := true;
            if r_clear_done /= 256 then
               report "zoom reset released after " & integer'image(r_clear_done) & " of 256 clearing writes" severity error;
               e := e + 1;
            end if;
         end if;
         if zrst_p /= zrst_c then
            lag := lag + 1;
            if lag > 5 then
               report "p_zoom_reset more than 5 clk1x edges behind" severity error;
               e := e + 1;
               lag := 0;
            end if;
         else
            lag := 0;
         end if;
         errs_z <= e;
      end if;
   end process;

   process
   begin
      wait for 1 ns;
      if zrst_p /= '1' then
         report "p_zoom_reset not 1 at power-up" severity error;
         errs_p <= 1;
      end if;
      wait;
   end process;

   ------------------------------------------------------------ L: line port (clk1x)
   process
      variable rng : rng_t;
      variable e : natural := 0;
      variable ln, n : natural;
      variable exp : std_logic_vector(63 downto 0);
   begin
      rng.init(SEED * 7 + 3, 9);
      wait for 3 us;
      for i in 1 to N_L loop
         for g in 1 to rng.int(0, 8) loop wait until rising_edge(clk1x); end loop;
         wait until rising_edge(clk1x);
         if rng.int(0, 3) = 0 then
            ln := 16#40000# + rng.int(0, 16#FFFF#);     -- U27 area (0x200000 / 8)
         else
            ln := 16#80000# + rng.int(0, 16#BFFFF#);    -- wave area (0x400000 / 8 on)
         end if;
         m_line <= std_logic_vector(to_unsigned(ln, 21));
         m_req  <= '1';
         -- zoom_memarb: req and line held until an edge that sees m_ready
         loop
            wait until rising_edge(clk1x);
            exit when m_ready = '1';
         end loop;
         l_open <= true;
         m_req  <= '0';
         n := 0;
         loop
            exit when m_rvalid = '1';
            exit when p_rst = '1';
            wait until rising_edge(clk1x);
            n := n + 1;
            if n > 20000 then
               report "line " & integer'image(ln) & " timed out" severity error;
               e := e + 1;
               exit;
            end if;
         end loop;
         if m_rvalid = '1' then
            exp := mem_word(FLASH_BASE + 8 * ln + 4) & mem_word(FLASH_BASE + 8 * ln);
            if m_rdata /= exp then
               report "line " & integer'image(ln) & ": " & to_hstring(m_rdata) & ", expected " & to_hstring(exp) severity error;
               e := e + 1;
            end if;
         end if;
         l_open <= false;
         wait for 0 ns;
         cnt_l <= i;
         errs_l <= e;
      end loop;
      l_fin <= true;
      wait;
   end process;

   process (clk1x)
      variable e : natural := 0;
   begin
      if rising_edge(clk1x) then
         if m_rvalid = '1' and not l_open then
            report "rvalid with no line open" severity error;
            e := e + 1;
            errs_v <= e;
         end if;
      end if;
   end process;

   ------------------------------------------------------------ B: glue flash port (clk_cpu)
   process
      variable rng : rng_t;
      variable e, n : natural := 0;
      variable a : natural;
   begin
      rng.init(SEED * 11 + 4, 3);
      wait for 3 us;
      for i in 1 to N_B loop
         for g in 1 to rng.int(0, 30) loop wait until rising_edge(clk_cpu); end loop;
         wait until rising_edge(clk_cpu);
         a := FLASH_BASE + 4 * rng.int(0, 16#7FFFF#);
         b_addr <= std_logic_vector(to_unsigned(a, 27));
         b_req  <= '1';
         wait until rising_edge(clk_cpu);
         b_req  <= '0';
         n := 0;
         loop
            exit when b_ready = '1';
            wait until rising_edge(clk_cpu);
            n := n + 1;
            if n > 5000 then report "B read timed out" severity error; e := e + 1; exit; end if;
         end loop;
         if c_dout /= mem_word(a) then
            report "B read " & to_hstring(to_unsigned(a, 28)) & ": " & to_hstring(c_dout) severity error;
            e := e + 1;
         end if;
         cnt_b <= i;
         errs_b <= e;
      end loop;
      b_fin <= true;
      wait;
   end process;

   ------------------------------------------------------------ resets
   gr : if RST_PER > 0 generate
      process
         variable rng : rng_t;
         variable n : natural := 0;
      begin
         rng.init(SEED * 13 + 6, 11);
         wait until released;
         while not (h_fin and l_fin) loop
            for i in 1 to rng.int(RST_PER * 10, RST_PER * 40) loop wait until rising_edge(clk_cpu); end loop;
            if rng.int(0, 1) = 0 then
               wait until rising_edge(clk_cpu);
               c_rst <= '1';
               for i in 1 to rng.int(1, 6) loop wait until rising_edge(clk_cpu); end loop;
               c_rst <= '0';
            else
               wait until rising_edge(clk1x);
               p_rst <= '1';
               for i in 1 to rng.int(1, 6) loop wait until rising_edge(clk1x); end loop;
               p_rst <= '0';
            end if;
            n := n + 1;
            n_rst <= n;
         end loop;
         wait;
      end process;
   end generate;

   ------------------------------------------------------------ channel 3 model (clk_cpu)
   process
      variable rng  : rng_t;
      variable addr : std_logic_vector(26 downto 0);
      variable din  : std_logic_vector(31 downto 0);
      variable rnw  : std_logic;
      variable be   : std_logic_vector(3 downto 0);
      variable v    : std_logic_vector(31 downto 0);
      variable e, nc, nl : natural := 0;
   begin
      rng.init(SEED * 17 + 5, 13);
      loop
         wait until rising_edge(clk_cpu);
         exit when h_fin and l_fin and b_fin;
         if c_req = '1' then
            nc := nc + 1;
            addr := c_addr; din := c_din; rnw := c_rnw; be := c_be;
            for k in 1 to rng.int(1, 12) loop
               wait until rising_edge(clk_cpu);
               if c_req = '1' then report "ch3 request while one is open" severity error; e := e + 1; end if;
               if c_addr /= addr or c_rnw /= rnw or c_be /= be then
                  report "ch3 fields changed before ready" severity error; e := e + 1;
               end if;
            end loop;
            if rnw /= '1' then
               report "ch3 write from a read-only client" severity error; e := e + 1;
            end if;
            v := mem_word(to_integer(unsigned(addr(26 downto 2))) * 4);
            if be /= "1111" then
               report "ch3 read with byte enables " & to_string(be) & " (read DQM blanks lanes)" severity error;
               e := e + 1;
               for b in 0 to 3 loop
                  if be(b) = '0' then v(8 * b + 7 downto 8 * b) := x"A5"; end if;
               end loop;
            end if;
            c_dout  <= v;
            c_ready <= '1';
            wait until rising_edge(clk_cpu);
            if rng.int(0, 9) = 0 then
               nl := nl + 1;
               wait until rising_edge(clk_cpu);
               wait until rising_edge(clk_cpu);
            end if;
            c_ready <= '0';
         end if;
         n_ch3 <= nc; n_long <= nl;
      end loop;
      wait for 2 us;
      say("RESULT " & OUTTAG & " zoom_cdc+sdram_link PA=" & integer'image(PA) & " PB=" & integer'image(PB) &
          " SEED=" & integer'image(SEED) & " META=" & integer'image(META) & " RST_PER=" & integer'image(RST_PER) &
          " host " & integer'image(cnt_h + 256) & " zero_answers " & integer'image(n_zero) &
          " lines " & integer'image(cnt_l) & " glue_reads " & integer'image(cnt_b) &
          " ch3 " & integer'image(nc) & " long_ready " & integer'image(nl) & " resets " & integer'image(n_rst) &
          " errors " & integer'image(e + errs_h + errs_r + errs_l + errs_b + errs_z + errs_s + errs_v + errs_p));
      stop;
   end process;

end architecture;
