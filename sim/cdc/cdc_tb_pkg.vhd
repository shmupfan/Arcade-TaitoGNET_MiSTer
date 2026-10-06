-- Shared helpers for the rtl/gnet/cdc benches: jitter-free clocks with a
-- random start phase, edge counting, latency statistics, text output.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

package cdc_tb_pkg is

   -- clock periods in fs (jitter-free; rising edges at offset + k x period)
   constant P_50M   : natural := 20000000;  -- 50.000 MHz
   constant P_100M  : natural := 10000000;  -- 100.000 MHz
   constant P_33M   : natural := 29525699;  -- 33.8688 MHz (29.5256992 ns)
   constant P_67M   : natural := 14762850;  -- 67.7376 MHz (14.7628496 ns)
   constant P_53M   : natural := 18624341;  -- 53.693175 MHz (18.6243408 ns)

   function tfs(n : natural) return time;
   function rnd_offset(seed, idx : positive; period_fs : natural) return natural;
   -- simulation synchroniser window: 0.9 x the shorter period, 0 when off
   function meta_window(pa_fs, pb_fs : natural; enable : natural) return time;

   procedure clk_gen(signal clk : out std_logic; period_fs, offset_fs : natural);

   -- number of rising edges t0 + k x period (k >= 0) in (ta, tb]
   function edges_in(ta, tb, t0 : time; period_fs : natural) return integer;

   type stat_t is record
      mn, mx : integer;
      n      : natural;
   end record;
   constant STAT_INIT : stat_t := (integer'high, integer'low, 0);
   procedure stat_add(variable s : inout stat_t; v : integer);
   function stat_str(s : stat_t) return string;

   type tstat_t is record
      mn, mx : time;
      n      : natural;
   end record;
   constant TSTAT_INIT : tstat_t := (1 sec, 0 fs, 0);
   procedure tstat_add(variable s : inout tstat_t; v : time);
   function ns_str(t : time) return string;
   function tstat_str(s : tstat_t) return string;

   procedure say(s : string);
   type rng_t is protected
      procedure init(a, b : positive);
      impure function uni return real;
      impure function int(lo, hi : integer) return integer;
   end protected;

   -- payload with a check field: value(seq) of width w
   function payload(seq : natural; w : positive; salt : natural) return std_logic_vector;

end package;

package body cdc_tb_pkg is

   function tfs(n : natural) return time is
   begin
      return n * 1 fs;
   end function;

   function rnd_offset(seed, idx : positive; period_fs : natural) return natural is
      variable s1 : positive := 1 + (seed mod 100000) * 7 + idx * 101;
      variable s2 : positive := 17 + (seed mod 100000) * 13 + idx * 37;
      variable u  : real;
   begin
      for i in 0 to 20 loop
         uniform(s1, s2, u);
      end loop;
      return 1000 + natural(floor(u * real(period_fs - 2000)));
   end function;

   function meta_window(pa_fs, pb_fs : natural; enable : natural) return time is
      variable p : natural := pa_fs;
   begin
      if enable = 0 then
         return 0 fs;
      end if;
      if pb_fs < p then
         p := pb_fs;
      end if;
      return (p / 10) * 9 * 1 fs;
   end function;

   procedure clk_gen(signal clk : out std_logic; period_fs, offset_fs : natural) is
      constant HI : time := (period_fs / 2) * 1 fs;
      constant LO : time := (period_fs - period_fs / 2) * 1 fs;
   begin
      clk <= '0';
      wait for offset_fs * 1 fs;
      loop
         clk <= '1';
         wait for HI;
         clk <= '0';
         wait for LO;
      end loop;
   end procedure;

   function edges_in(ta, tb, t0 : time; period_fs : natural) return integer is
      constant P : time := period_fs * 1 fs;
      variable ia, ib : integer;
   begin
      if ta < t0 then
         ia := -1;
      else
         ia := (ta - t0) / P;
      end if;
      if tb < t0 then
         ib := -1;
      else
         ib := (tb - t0) / P;
      end if;
      return ib - ia;
   end function;

   procedure stat_add(variable s : inout stat_t; v : integer) is
   begin
      if v < s.mn then s.mn := v; end if;
      if v > s.mx then s.mx := v; end if;
      s.n := s.n + 1;
   end procedure;

   function stat_str(s : stat_t) return string is
   begin
      if s.n = 0 then
         return "none";
      end if;
      return integer'image(s.mn) & ".." & integer'image(s.mx);
   end function;

   procedure tstat_add(variable s : inout tstat_t; v : time) is
   begin
      if v < s.mn then s.mn := v; end if;
      if v > s.mx then s.mx := v; end if;
      s.n := s.n + 1;
   end procedure;

   function ns_str(t : time) return string is
      variable ps : integer := t / 1 ps;
   begin
      return integer'image(ps / 1000) & "." & integer'image((ps mod 1000) / 100);
   end function;

   function tstat_str(s : tstat_t) return string is
   begin
      if s.n = 0 then
         return "none";
      end if;
      return ns_str(s.mn) & ".." & ns_str(s.mx);
   end function;

   procedure say(s : string) is
      variable l : line;
   begin
      write(l, s);
      writeline(output, l);
   end procedure;

   type rng_t is protected body
      variable s1 : positive := 1;
      variable s2 : positive := 1;
      procedure init(a, b : positive) is
      begin
         s1 := 1 + (a mod 100000) * 7919 + b;
         s2 := 1 + (a mod 100000) * 3571 + b * 101;
      end procedure;
      impure function uni return real is
         variable u : real;
      begin
         uniform(s1, s2, u);
         return u;
      end function;
      impure function int(lo, hi : integer) return integer is
         variable u : real;
      begin
         uniform(s1, s2, u);
         return lo + integer(floor(u * real(hi - lo + 1)));
      end function;
   end protected body;

   function payload(seq : natural; w : positive; salt : natural) return std_logic_vector is
      variable h  : unsigned(31 downto 0);
      variable sq : unsigned(30 downto 0) := to_unsigned(seq, 31);
      variable r  : std_logic_vector(w - 1 downto 0);
      variable x  : unsigned(63 downto 0);
   begin
      -- low half: seq; high half: a hash of seq (a torn word fails the check)
      x := to_unsigned(seq, 32) * to_unsigned(1640531535, 32);
      h := x(31 downto 0) xor to_unsigned(salt mod 2**30, 32) xor shift_right(x(63 downto 32), 3);
      for i in 0 to w - 1 loop
         if i < w / 2 and i < 31 then
            r(i) := sq(i);
         else
            r(i) := h((i * 7) mod 32) xor h((i * 3 + 5) mod 32);
         end if;
      end loop;
      return r;
   end function;

end package body;
