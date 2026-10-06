-- Bench for rtl/gnet/zn2_cdc.vhd with the real rtl/gnet/zn2_cardmem.vhd and
-- a DDR3 arbiter model (docs/r1_cpu_domain_design.md, "ZN-2 layer in the CPU
-- group"). Clocks: clk_cpu PA, clk1x PB, clk2x PB / 2, jitter-free, random
-- start phases (sim/cdc/cdc_tb_pkg.vhd); META = 1 turns on the
-- synchroniser model of rtl/gnet/cdc (window 0.9 x the shorter period).
--
--   C18     a gnet_ata model on clk_cpu: random reads and writes of 16-bit
--           card words (request held until the ack, dropped in the next
--           cycle, random gaps), checked against a shadow of the card; the
--           arbiter model grants after 0 to 6 clk2x cycles and answers reads
--           after 3 to 20 more. Random zn2_board resets (c_board_rst, 1 to 4
--           cycles) abandon the request in flight, as gnet_ata's reset does;
--           an abandoned write may or may not land, so the next read of that
--           word accepts either value. Errors: wrong data, an ack with no
--           request waiting, an op not finished within 4,000 cycles.
--   loader  words from clk1x in bursts (1 to 12 back to back) and with gaps
--           of 2 to 40 cycles; on clk_cpu every word must arrive once, in
--           order, with ld_wr never high in two consecutive cycles; no FIFO
--           overflow.
--   inputs  39 board input bits from clk1x, coin 8 bits from clk_cpu: a
--           value held for more than the synchroniser latency must arrive.
--   wd      watchdog pulses on clk_cpu at least 3 cycles apart: as many on
--           clk1x.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.cdc_tb_pkg.all;

entity tb_zn2_cdc is
   generic (
      PA     : natural  := P_50M;      -- clk_cpu
      PB     : natural  := P_33M;      -- clk1x (clk2x = PB / 2)
      SEED   : positive := 1;
      META   : natural  := 1;
      N_OPS  : natural  := 20000;      -- card port operations
      N_LD   : natural  := 20000;      -- loader words
      RST_PER : natural := 300;        -- one board reset per about this many ops (0 = none)
      -- loader: 0 = bursts and gaps (default); 1 = a word every clk1x cycle
      -- held off by p_ld_busy seen 2 cycles late (ioctl_wait through
      -- PSX.sv and hps_io); 2 = the same ignoring p_ld_busy (negative
      -- control: must overflow)
      LD_STRESS : natural := 0;
      OUTTAG : string   := "run"
   );
end entity;

architecture sim of tb_zn2_cdc is

   constant PB2  : natural := PB / 2;
   constant OFFA : natural := rnd_offset(SEED, 1, PA);
   constant OFFB : natural := rnd_offset(SEED, 2, PB);
   constant WIN  : time := meta_window(PA, PB2, META);
   constant TA   : time := PA * 1 fs;
   constant TB   : time := PB * 1 fs;

   constant NLINE : natural := 256;      -- card lines used (word addresses 0 .. 4 x NLINE - 1)
   constant BASE  : natural := 16#4000000#;

   signal clk_cpu, clk1x, clk2x : std_logic := '0';

   -- DUT
   signal board_rst : std_logic := '0';
   signal p_in      : std_logic_vector(38 downto 0) := (others => '1');
   signal c_in      : std_logic_vector(38 downto 0);
   signal c_in_p1, c_in_p2, c_in_service, c_in_system : std_logic_vector(7 downto 0);
   signal c_dsw     : std_logic_vector(3 downto 0);
   signal c_jp1, c_card_present, c_key_valid : std_logic;
   signal ld_wr     : std_logic := '0';
   signal ld_target : std_logic_vector(1 downto 0) := "00";
   signal ld_addr   : unsigned(10 downto 0) := (others => '0');
   signal ld_data   : std_logic_vector(15 downto 0) := (others => '0');
   signal ld_ovf    : std_logic;
   signal ld_busy   : std_logic;
   signal c_ld_wr   : std_logic;
   signal c_ld_target : std_logic_vector(1 downto 0);
   signal c_ld_addr : unsigned(10 downto 0);
   signal c_ld_data : std_logic_vector(15 downto 0);
   signal c_wd      : std_logic := '0';
   signal p_wd      : std_logic;
   signal c_coin    : std_logic_vector(7 downto 0) := (others => '0');
   signal p_coin    : std_logic_vector(7 downto 0);
   signal cm_req, cm_we : std_logic := '0';
   signal cm_addr   : std_logic_vector(24 downto 0) := (others => '0');
   signal cm_wdata  : std_logic_vector(15 downto 0) := (others => '0');
   signal cm_ack    : std_logic;
   signal cm_rdata  : std_logic_vector(15 downto 0);
   signal p2_req, p2_we, p2_ack : std_logic;
   signal p2_addr   : std_logic_vector(24 downto 0);
   signal p2_wdata, p2_rdata : std_logic_vector(15 downto 0);

   -- zn2_cardmem to the arbiter model
   signal m_request, m_we, m_rd, m_ack, m_ready : std_logic := '0';
   signal m_burst   : std_logic_vector(7 downto 0);
   signal m_addr    : std_logic_vector(27 downto 0);
   signal m_din, m_dout : std_logic_vector(63 downto 0) := (others => '0');
   signal m_be      : std_logic_vector(7 downto 0);

   -- results
   signal errs_cm, errs_ack, errs_ld, errs_ovf, errs_in, errs_coin : natural := 0;
   signal ops_done  : natural := 0;
   signal n_rst, n_abandon, n_either : natural := 0;
   signal ld_seen   : natural := 0;
   signal ld_held   : natural := 0;
   signal cm_finished, ld_finished, in_finished, wd_finished : boolean := false;
   signal wd_src, wd_dst : natural := 0;
   signal in_checks, coin_checks : natural := 0;
   signal waiting   : boolean := false;    -- gnet_ata model has a request out
   signal t_in, t_coin : time := 0 fs;     -- last change of p_in and c_coin (composite 'last_event is not usable here)

   function init_word(w : natural) return std_logic_vector is
   begin
      return std_logic_vector(to_unsigned((w * 40503 + 12345) mod 65536, 16));
   end function;

   function ld_word(i : natural) return std_logic_vector is
      -- target (2) & addr (11) & data (16) of loader word i
   begin
      return std_logic_vector(to_unsigned(i mod 3, 2)) & std_logic_vector(to_unsigned(i mod 2048, 11)) &
             std_logic_vector(to_unsigned((i * 7919 + 17) mod 65536, 16));
   end function;

begin

   clk_gen(clk_cpu, PA, OFFA);
   process
   begin
      clk1x <= '0'; clk2x <= '0';
      wait for OFFB * 1 fs;
      loop
         clk1x <= '1'; clk2x <= '1';
         wait for (PB2 / 2) * 1 fs;
         clk2x <= '0';
         wait for (PB2 - PB2 / 2) * 1 fs;
         clk2x <= '1'; clk1x <= '0';
         wait for (PB2 / 2) * 1 fs;
         clk2x <= '0';
         wait for (PB - PB2 - PB2 / 2) * 1 fs;
      end loop;
   end process;

   c_in <= c_in_p1 & c_in_p2 & c_in_service & c_in_system & c_dsw & c_jp1 & c_card_present & c_key_valid;

   dut : entity work.zn2_cdc
      generic map (SIM_META_WINDOW => WIN)
      port map (
         clk_cpu => clk_cpu, clk1x => clk1x, clk2x => clk2x, c_board_rst => board_rst,
         p_in_p1 => p_in(38 downto 31), p_in_p2 => p_in(30 downto 23), p_in_service => p_in(22 downto 15),
         p_in_system => p_in(14 downto 7), p_dsw => p_in(6 downto 3), p_jp1 => p_in(2),
         p_card_present => p_in(1), p_key_valid => p_in(0),
         c_in_p1 => c_in_p1, c_in_p2 => c_in_p2, c_in_service => c_in_service, c_in_system => c_in_system,
         c_dsw => c_dsw, c_jp1 => c_jp1, c_card_present => c_card_present, c_key_valid => c_key_valid,
         p_ld_wr => ld_wr, p_ld_target => ld_target, p_ld_addr => ld_addr, p_ld_data => ld_data,
         p_ld_overflow => ld_ovf, p_ld_busy => ld_busy, c_ld_wr => c_ld_wr, c_ld_target => c_ld_target, c_ld_addr => c_ld_addr,
         c_ld_data => c_ld_data,
         c_wd_reset => c_wd, p_wd_reset => p_wd, c_coin => c_coin, p_coin => p_coin,
         c_cm_req => cm_req, c_cm_we => cm_we, c_cm_addr => cm_addr, c_cm_wdata => cm_wdata,
         c_cm_ack => cm_ack, c_cm_rdata => cm_rdata,
         p2_cm_req => p2_req, p2_cm_we => p2_we, p2_cm_addr => p2_addr, p2_cm_wdata => p2_wdata,
         p2_cm_ack => p2_ack, p2_cm_rdata => p2_rdata);

   icm : entity work.zn2_cardmem
      port map (
         clk2x => clk2x, reset => '0',
         dl_wr => '0', dl_addr => (others => '0'), dl_data => (others => '0'), dl_busy => open,
         cm_req => p2_req, cm_we => p2_we, cm_addr => p2_addr, cm_wdata => p2_wdata,
         cm_ack => p2_ack, cm_rdata => p2_rdata,
         mem_request => m_request, mem_BURSTCNT => m_burst, mem_ADDR => m_addr, mem_DIN => m_din,
         mem_BE => m_be, mem_WE => m_we, mem_RD => m_rd, mem_ack => m_ack,
         mem_DOUT => m_dout, mem_DOUT_READY => m_ready);

   ------------------------------------------------------------ DDR3 arbiter model (clk2x)
   -- request held by the client; the grant (ack) takes the parameters, as
   -- psx_top's arbiter does; a read returns its word some cycles later
   process
      type t_mem is array (0 to NLINE - 1) of std_logic_vector(63 downto 0);
      variable mem : t_mem;
      variable rng : rng_t;
      variable ln  : integer;
      variable v   : std_logic_vector(63 downto 0);
   begin
      rng.init(SEED * 3 + 1, 7);
      for i in 0 to NLINE - 1 loop
         mem(i) := init_word(4 * i + 3) & init_word(4 * i + 2) & init_word(4 * i + 1) & init_word(4 * i);
      end loop;
      loop
         wait until rising_edge(clk2x);
         if m_request = '1' then
            for i in 1 to rng.int(0, 6) loop wait until rising_edge(clk2x); end loop;
            ln := (to_integer(unsigned(m_addr)) - BASE) / 8;
            assert ln >= 0 and ln < NLINE report "address out of range" severity failure;
            m_ack <= '1';
            if m_we = '1' then
               v := mem(ln);
               for b in 0 to 7 loop
                  if m_be(b) = '1' then v(8 * b + 7 downto 8 * b) := m_din(8 * b + 7 downto 8 * b); end if;
               end loop;
               mem(ln) := v;
               wait until rising_edge(clk2x);
               m_ack <= '0';
               -- the client drops the request in the cycle after the ack
               wait until rising_edge(clk2x);
            else
               wait until rising_edge(clk2x);
               m_ack <= '0';
               for i in 1 to rng.int(3, 20) loop wait until rising_edge(clk2x); end loop;
               m_dout  <= mem(ln);
               m_ready <= '1';
               wait until rising_edge(clk2x);
               m_ready <= '0';
               m_dout  <= (others => 'X');
               wait until rising_edge(clk2x);
            end if;
         end if;
      end loop;
   end process;

   ------------------------------------------------------------ gnet_ata model (clk_cpu)
   process
      type t_shadow is array (0 to 4 * NLINE - 1) of std_logic_vector(15 downto 0);
      type t_flag is array (0 to 4 * NLINE - 1) of boolean;
      variable shadow : t_shadow;
      variable unk    : t_flag := (others => false);
      variable alt    : t_shadow;      -- up to three abandoned writes per word may land
      variable alt2   : t_shadow;
      variable alt3   : t_shadow;
      variable nalt   : integer;
      variable rng    : rng_t;
      variable a, n   : integer;
      variable we     : boolean;
      variable d      : std_logic_vector(15 downto 0);
      variable abandoned : boolean;
      variable e      : natural := 0;
   begin
      rng.init(SEED * 5 + 3, 11);
      for i in 0 to 4 * NLINE - 1 loop shadow(i) := init_word(i); end loop;
      wait for 2 us;
      wait until rising_edge(clk_cpu);
      for op in 1 to N_OPS loop
         -- gnet_ata raises a request only while st_req is low, so the
         -- request is low for at least one cycle between two operations
         for i in 1 to rng.int(1, 7) loop wait until rising_edge(clk_cpu); end loop;
         while board_rst = '1' loop wait until rising_edge(clk_cpu); end loop;
         -- addresses: mostly near the last one (line buffer hits), some anywhere
         if rng.int(0, 3) = 0 then
            a := rng.int(0, 4 * NLINE - 1);
         else
            a := (a + rng.int(0, 5)) mod (4 * NLINE);
         end if;
         we := rng.int(0, 3) = 0;
         d  := std_logic_vector(to_unsigned(rng.int(0, 65535), 16));
         cm_req   <= '1';
         cm_we    <= '1' when we else '0';
         cm_addr  <= std_logic_vector(to_unsigned(a, 25));
         cm_wdata <= d;
         waiting  <= true;
         abandoned := false;
         n := 0;
         loop
            wait until rising_edge(clk_cpu);
            n := n + 1;
            if board_rst = '1' then
               abandoned := true;   -- gnet_ata's reset clears st_req
               exit;
            end if;
            exit when cm_ack = '1';
            if n > 4000 then
               report "card op " & integer'image(op) & " timed out" severity error;
               e := e + 1;
               exit;
            end if;
         end loop;
         cm_req  <= '0';
         waiting <= false;
         if abandoned then
            n_abandon <= n_abandon + 1;
            if we then
               if not unk(a) then
                  unk(a) := true;
                  alt(a) := d; alt2(a) := d; alt3(a) := d;
               else
                  alt3(a) := alt2(a); alt2(a) := alt(a); alt(a) := d;
               end if;
            end if;
         elsif we then
            shadow(a) := d;
            unk(a)    := false;
         else
            if unk(a) then
               if cm_rdata = shadow(a) or cm_rdata = alt(a) or cm_rdata = alt2(a) or cm_rdata = alt3(a) then
                  shadow(a) := cm_rdata;
                  unk(a)    := false;
                  n_either  <= n_either + 1;
               else
                  report "card read word " & integer'image(a) & ": " & to_hstring(cm_rdata) & ", expected " &
                         to_hstring(shadow(a)) & " or " & to_hstring(alt(a)) severity error;
                  e := e + 1;
               end if;
            elsif cm_rdata /= shadow(a) then
               report "card read word " & integer'image(a) & ": " & to_hstring(cm_rdata) & ", expected " &
                      to_hstring(shadow(a)) severity error;
               e := e + 1;
            end if;
         end if;
         ops_done <= op;
         errs_cm  <= e;
      end loop;
      cm_finished <= true;
      wait;
   end process;

   -- board resets
   process
      variable rng : rng_t;
   begin
      rng.init(SEED * 7 + 5, 13);
      if RST_PER = 0 then wait; end if;
      wait for 2 us;
      loop
         for i in 1 to rng.int(RST_PER * 5, RST_PER * 25) loop wait until rising_edge(clk_cpu); end loop;
         exit when cm_finished;
         board_rst <= '1';
         n_rst <= n_rst + 1;
         for i in 1 to rng.int(1, 4) loop wait until rising_edge(clk_cpu); end loop;
         board_rst <= '0';
      end loop;
      wait;
   end process;

   -- an ack must find a request waiting (registered view: the model sets
   -- waiting on the edge it raises cm_req and clears it on the ack edge)
   process (clk_cpu)
      variable e : natural := 0;
   begin
      if rising_edge(clk_cpu) then
         if cm_ack = '1' and not waiting then
            report "card ack with no request waiting" severity error;
            e := e + 1;
            errs_ack <= e;
         end if;
      end if;
   end process;

   ------------------------------------------------------------ loader
   process
      variable rng : rng_t;
      variable w   : std_logic_vector(28 downto 0);
      variable i   : natural := 0;
      variable b   : natural;
      variable b0, b1 : std_logic := '0';
      variable nheld : natural := 0;
   begin
      rng.init(SEED * 11 + 7, 17);
      wait for 3 us;
      while LD_STRESS > 0 and i < N_LD loop
         wait until rising_edge(clk1x);
         b1 := b0; b0 := ld_busy;
         if b1 = '0' or LD_STRESS = 2 then
            w := ld_word(i);
            ld_wr <= '1'; ld_target <= w(28 downto 27); ld_addr <= unsigned(w(26 downto 16)); ld_data <= w(15 downto 0);
            i := i + 1;
         else
            ld_wr <= '0';
            nheld := nheld + 1;
         end if;
      end loop;
      if LD_STRESS > 0 then
         wait until rising_edge(clk1x);
         ld_wr <= '0';
         ld_held <= nheld;
      end if;
      while i < N_LD loop
         wait until rising_edge(clk1x);
         if rng.int(0, 7) = 0 then
            b := rng.int(1, 12);                -- burst, one word per cycle
            for k in 1 to b loop
               exit when i >= N_LD;
               w := ld_word(i);
               ld_wr <= '1'; ld_target <= w(28 downto 27); ld_addr <= unsigned(w(26 downto 16)); ld_data <= w(15 downto 0);
               i := i + 1;
               wait until rising_edge(clk1x);
            end loop;
            ld_wr <= '0';
            for k in 1 to 40 loop wait until rising_edge(clk1x); end loop;
         else
            w := ld_word(i);
            ld_wr <= '1'; ld_target <= w(28 downto 27); ld_addr <= unsigned(w(26 downto 16)); ld_data <= w(15 downto 0);
            i := i + 1;
            wait until rising_edge(clk1x);
            ld_wr <= '0';
            for k in 1 to rng.int(1, 39) loop wait until rising_edge(clk1x); end loop;
         end if;
      end loop;
      ld_finished <= true;
      wait;
   end process;

   process (clk_cpu)
      variable n    : natural := 0;
      variable e    : natural := 0;
      variable prev : std_logic := '0';
      variable w    : std_logic_vector(28 downto 0);
   begin
      if rising_edge(clk_cpu) then
         if c_ld_wr = '1' then
            if prev = '1' then
               report "loader: ld_wr in two consecutive cycles" severity error;
               e := e + 1;
            end if;
            w := ld_word(n);
            if c_ld_target /= w(28 downto 27) or std_logic_vector(c_ld_addr) /= w(26 downto 16) or c_ld_data /= w(15 downto 0) then
               report "loader word " & integer'image(n) & " wrong" severity error;
               e := e + 1;
            end if;
            n := n + 1;
         end if;
         prev := c_ld_wr;
         ld_seen <= n;
         errs_ld <= e;
      end if;
   end process;

   process (clk1x)
   begin
      if rising_edge(clk1x) then
         if ld_ovf = '1' then
            report "loader FIFO overflow" severity error;
            errs_ovf <= errs_ovf + 1;
         end if;
      end if;
   end process;

   ------------------------------------------------------------ inputs and coin
   process
      variable rng : rng_t;
   begin
      rng.init(SEED * 13 + 9, 19);
      wait for 1 us;
      while not cm_finished loop
         wait until rising_edge(clk1x);
         for b in 0 to 38 loop
            if rng.int(0, 2) = 0 then p_in(b) <= not p_in(b); end if;
         end loop;
         t_in <= now;
         for k in 1 to rng.int(1, 30) loop wait until rising_edge(clk1x); end loop;
      end loop;
      in_finished <= true;
      wait;
   end process;

   process
      variable rng : rng_t;
   begin
      rng.init(SEED * 17 + 11, 23);
      wait for 1 us;
      while not cm_finished loop
         wait until rising_edge(clk_cpu);
         c_coin <= std_logic_vector(to_unsigned(rng.int(0, 255), 8));
         t_coin <= now;
         for k in 1 to rng.int(1, 40) loop wait until rising_edge(clk_cpu); end loop;
      end loop;
      wait;
   end process;

   -- a value held longer than the synchroniser (input register plus 3
   -- destination edges, plus one when a stage resolves late) must be visible
   process (clk_cpu)
      variable e, n : natural := 0;
   begin
      if rising_edge(clk_cpu) then
         if now - t_in > TB + 5 * TA and c_in /= p_in then
            report "inputs: " & to_hstring(c_in) & " for " & to_hstring(p_in) severity error;
            e := e + 1;
         elsif now - t_in > TB + 5 * TA then
            n := n + 1;
         end if;
         errs_in <= e; in_checks <= n;
      end if;
   end process;

   process (clk1x)
      variable e, n : natural := 0;
   begin
      if rising_edge(clk1x) then
         if now - t_coin > TA + 5 * TB and p_coin /= c_coin then
            report "coin: " & to_hstring(p_coin) & " for " & to_hstring(c_coin) severity error;
            e := e + 1;
         elsif now - t_coin > TA + 5 * TB then
            n := n + 1;
         end if;
         coin_checks <= n;
         errs_coin <= e;
      end if;
   end process;

   ------------------------------------------------------------ watchdog pulses
   process
      variable rng : rng_t;
      variable n   : natural := 0;
   begin
      rng.init(SEED * 19 + 13, 29);
      wait for 1 us;
      while not cm_finished loop
         wait until rising_edge(clk_cpu);
         c_wd <= '1';
         n := n + 1;
         wd_src <= n;
         wait until rising_edge(clk_cpu);
         c_wd <= '0';
         -- at least 3 source cycles apart and more than one clk1x period plus the window
         for k in 1 to rng.int(2, 40) + (PB + PA - 1) / PA loop wait until rising_edge(clk_cpu); end loop;
      end loop;
      wd_finished <= true;
      wait;
   end process;

   process (clk1x)
   begin
      if rising_edge(clk1x) then
         if p_wd = '1' then wd_dst <= wd_dst + 1; end if;
      end if;
   end process;

   ------------------------------------------------------------ end
   process
      variable total : natural;
   begin
      wait until cm_finished and ld_finished and in_finished and wd_finished;
      wait for 2 us;
      if wd_dst /= wd_src then
         report "watchdog: " & integer'image(wd_src) & " pulses sent, " & integer'image(wd_dst) & " seen" severity error;
      end if;
      if ld_seen /= N_LD then
         report "loader: " & integer'image(N_LD) & " words sent, " & integer'image(ld_seen) & " seen" severity error;
      end if;
      total := errs_cm + errs_ack + errs_ld + errs_ovf + errs_in + errs_coin;
      if wd_dst /= wd_src then total := total + 1; end if;
      if ld_seen /= N_LD then total := total + 1; end if;
      say("RESULT " & OUTTAG & " zn2_cdc PA=" & integer'image(PA) & " PB=" & integer'image(PB) & " SEED=" & integer'image(SEED) &
          " META=" & integer'image(META) & " card_ops " & integer'image(ops_done) & " resets " & integer'image(n_rst) &
          " abandoned " & integer'image(n_abandon) & " either " & integer'image(n_either) &
          " loader " & integer'image(ld_seen) & " held " & integer'image(ld_held) & " wd " & integer'image(wd_dst) & "/" & integer'image(wd_src) &
          " input_checks " & integer'image(in_checks) & " coin_checks " & integer'image(coin_checks) &
          " errors " & integer'image(total));
      stop;
   end process;

end architecture;
