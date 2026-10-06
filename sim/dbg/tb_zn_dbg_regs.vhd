-- Unit bench for rtl/gnet/zn_dbg_regs.vhd (docs/hw_debug_overlay.md).
-- CLK_HZ is scaled down (33,868 Hz: 33.868 clocks per ms, the 33.8688 MHz
-- ratio) so ms-scale behaviour runs in a few thousand clocks. Every check
-- reads the registers through the rd_idx / rd_word port.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_zn_dbg_regs is
   generic (CLK_HZ : integer := 33868);
end entity;

architecture sim of tb_zn_dbg_regs is

   constant T : time := 10 ns;

   signal clk        : std_logic := '0';
   signal core_reset : std_logic := '0';
   signal pc         : unsigned(31 downto 0) := x"BFC00000";
   signal dat_take   : std_logic := '0';
   signal dat_addr   : unsigned(31 downto 0) := (others => '0');
   signal wd_fire    : std_logic := '0';
   signal wd_kick    : std_logic := '0';
   signal ctrl       : std_logic_vector(7 downto 0) := x"10";
   signal sec_cmd    : std_logic := '0';
   signal rd_idx     : std_logic_vector(3 downto 0) := x"0";
   signal rd_word    : std_logic_vector(31 downto 0);

   signal cycles     : natural := 0;
   signal done       : boolean := false;

   function hx(v : std_logic_vector) return string is
      constant digits : string(1 to 16) := "0123456789ABCDEF";
      variable s : string(1 to v'length / 4);
      variable n : integer;
      variable w : std_logic_vector(v'length - 1 downto 0) := v;
   begin
      for i in 0 to v'length / 4 - 1 loop
         n := to_integer(unsigned(w(v'length - 1 - 4 * i downto v'length - 4 - 4 * i)));
         s(i + 1) := digits(n + 1);
      end loop;
      return s;
   end function;

begin

   clk <= not clk after T / 2 when not done;

   process (clk)
   begin
      if rising_edge(clk) then
         cycles <= cycles + 1;
      end if;
   end process;

   dut : entity work.zn_dbg_regs
      generic map (CLK_HZ => CLK_HZ)
      port map
      (
         clk        => clk,
         core_reset => core_reset,
         pc         => pc,
         dat_take   => dat_take,
         dat_addr   => dat_addr,
         wd_fire    => wd_fire,
         wd_kick    => wd_kick,
         ctrl       => ctrl,
         sec_cmd    => sec_cmd,
         rd_idx     => rd_idx,
         rd_word    => rd_word
      );

   stim : process
      variable errors : natural := 0;
      variable checks : natural := 0;

      procedure tick(n : natural := 1) is
      begin
         for i in 1 to n loop
            wait until rising_edge(clk);
         end loop;
         wait for 1 ns;
      end procedure;

      -- clocks for ms milliseconds, rounded up
      function ms_cyc(ms : natural) return natural is
      begin
         return (ms * CLK_HZ + 999) / 1000;
      end function;

      procedure pulse(signal s : out std_logic) is
      begin
         s <= '1';
         tick;
         s <= '0';
      end procedure;

      procedure access_data(a : unsigned(31 downto 0)) is
      begin
         dat_addr <= a;
         dat_take <= '1';
         tick;
         dat_take <= '0';
      end procedure;

      procedure check_word(idx : natural; exp : std_logic_vector(31 downto 0); msg : string) is
      begin
         rd_idx <= std_logic_vector(to_unsigned(idx, 4));
         wait for 1 ns;
         checks := checks + 1;
         if rd_word /= exp then
            errors := errors + 1;
            report "FAIL " & msg & ": word " & integer'image(idx) & " = " & hx(rd_word) & ", expected " & hx(exp) severity error;
         end if;
      end procedure;

      -- range check on a 16-bit or 32-bit field
      procedure check_range(idx, hi, lo : natural; vmin, vmax : natural; msg : string) is
         variable v : natural;
      begin
         rd_idx <= std_logic_vector(to_unsigned(idx, 4));
         wait for 1 ns;
         v := to_integer(unsigned(rd_word(hi downto lo)));
         checks := checks + 1;
         if v < vmin or v > vmax then
            errors := errors + 1;
            report "FAIL " & msg & ": word " & integer'image(idx) & " bits " & integer'image(hi) & ":" & integer'image(lo) &
                   " = " & integer'image(v) & ", expected " & integer'image(vmin) & " to " & integer'image(vmax) severity error;
         end if;
      end procedure;

      -- one reset as the core makes it: a burst of single-cycle pulses
      procedure reset_burst(n : natural) is
      begin
         for i in 1 to n loop
            pulse(core_reset);
            tick(15);
         end loop;
      end procedure;

      variable ms_now : natural;

   begin
      tick(3);

      -------------------------------------------------- power-up values
      check_word(0, x"BFC00000", "live PC");
      check_word(1, x"00000000", "DA at power-up");
      check_word(2, x"10000000", "IO at power-up (ctrl 10h)");
      for i in 6 to 15 loop
         check_word(i, x"00000000", "snapshot / unused at power-up");
      end loop;

      -------------------------------------------------- ms tick exact over 3 s
      -- from power-up the accumulator starts at 0: after k clocks
      -- floor(k * 1000 / CLK_HZ) ticks (one more clock to register)
      while cycles < 3 * CLK_HZ + 1 loop
         tick;
      end loop;
      check_range(3, 31, 0, 3000, 3000, "ms after exactly 3 s from power-up");

      -------------------------------------------------- first reset (power-on): other
      reset_burst(3);
      check_word(5, x"00010000", "first reset counted as other, one per burst");
      check_range(3, 31, 0, 0, 1, "ms right after reset");
      tick(ms_cyc(250));
      check_range(3, 31, 0, 249, 251, "ms 250 ms after reset");

      -------------------------------------------------- data and I/O addresses
      access_data(x"1F801070");      -- I_STAT, KUSEG
      check_word(1, x"1F801070", "DA KUSEG I/O");
      check_word(2, x"10001070", "IO KUSEG");
      access_data(x"80012340");      -- RAM: DA only
      check_word(1, x"80012340", "DA RAM");
      check_word(2, x"10001070", "IO unchanged by RAM access");
      access_data(x"BF801814");      -- GPU, KSEG1
      check_word(2, x"10001814", "IO KSEG1");
      access_data(x"9F80104A");      -- JOY_CTRL, KSEG0
      check_word(2, x"1000104A", "IO KSEG0");
      access_data(x"1FA00000");      -- ZN-2 inputs: not 0x1F80
      check_word(1, x"1FA00000", "DA ZN-2 window");
      check_word(2, x"1000104A", "IO unchanged by 0x1FA00000");
      dat_addr <= x"1F801DAC";       -- address present without dat_take
      tick(3);
      check_word(1, x"1FA00000", "DA unchanged without dat_take");
      ctrl <= x"E8";
      wait for 1 ns;
      check_word(2, x"E800104A", "control register in 31:24");

      -------------------------------------------------- watchdog kicks
      -- no kick since the reset (250 ms plus the I/O section)
      check_range(4, 31, 16, 250, 252, "no-kick ms counts from the reset");
      -- the largest interval so far: power-up to the first reset (3 s)
      check_range(4, 15, 0, 3000, 3001, "max no-kick from power-up to the first reset");
      pulse(wd_kick);
      tick(ms_cyc(40));
      check_range(4, 31, 16, 39, 41, "no-kick ms 40 ms after a kick");
      pulse(wd_kick);
      check_range(4, 31, 16, 0, 0, "no-kick cleared by a kick");
      tick(ms_cyc(120));
      pulse(wd_kick);
      tick(ms_cyc(10));
      check_range(4, 31, 16, 9, 11, "no-kick 10 ms after the second kick");

      -------------------------------------------------- ATA sector commands
      for i in 1 to 5 loop
         pulse(sec_cmd);
         tick(2);
      end loop;
      check_word(5, x"00010005", "5 sector commands");

      -------------------------------------------------- watchdog expiry and its reset
      pc <= x"80012ABC";
      access_data(x"1F801044");      -- JOY_STAT
      access_data(x"80040000");
      tick(ms_cyc(500));
      rd_idx <= x"3";
      wait for 1 ns;
      ms_now := to_integer(unsigned(rd_word));
      pulse(wd_fire);
      -- the core reset follows a few us later (zn2_cdc, PSX.sv hold, reset sequencer)
      pc <= x"BFC00000";
      tick(200);
      reset_burst(4);
      check_word(6, x"80012ABC", "snapshot PC");
      check_word(7, x"80040000", "snapshot DA");
      check_range(8, 15, 0, 16#1044#, 16#1044#, "snapshot I/O address");
      check_range(8, 31, 16, 509, 511, "snapshot no-kick ms (10 + 500)");
      check_range(9, 31, 0, ms_now, ms_now + 1, "snapshot ms since reset");
      check_word(5, x"01010005", "reset after expiry counted as watchdog");
      check_range(2, 23, 16, 1, 1, "one watchdog expiry");
      check_range(3, 31, 0, 0, 1, "live ms restarted by the reset");
      check_range(4, 31, 16, 0, 1, "no-kick restarted by the expiry and reset");
      check_range(4, 15, 0, 3000, 3001, "max no-kick still the power-up interval");

      -------------------------------------------------- snapshot kept across later resets
      tick(ms_cyc(30));
      reset_burst(2);                 -- user reset, no expiry
      check_word(5, x"01020005", "user reset counted as other");
      check_word(6, x"80012ABC", "snapshot PC kept across a reset");
      check_word(7, x"80040000", "snapshot DA kept across a reset");

      -------------------------------------------------- expiry without a reset (OSD watchdog Off)
      pc <= x"80055550";
      tick(ms_cyc(20));
      pulse(wd_fire);
      check_word(6, x"80055550", "second snapshot PC");
      check_range(2, 23, 16, 2, 2, "two expiries");
      tick(ms_cyc(150));              -- longer than the 100 ms window
      reset_burst(1);
      check_word(5, x"01030005", "reset 150 ms after an expiry counted as other");

      -------------------------------------------------- bursts split by quiet time
      tick(ms_cyc(5));
      reset_burst(1);
      check_word(5, x"01040005", "separate reset after 5 ms quiet");

      -------------------------------------------------- a longer interval raises the max
      pulse(wd_kick);
      tick(ms_cyc(3500));
      check_range(4, 31, 16, 3499, 3501, "no-kick 3.5 s after a kick");
      check_range(4, 15, 0, 3499, 3501, "max follows the longer interval");
      pulse(wd_kick);
      check_range(4, 15, 0, 3499, 3501, "max kept after the kick");

      -------------------------------------------------- unused words
      for i in 10 to 15 loop
         check_word(i, x"00000000", "unused word");
      end loop;

      report "tb_zn_dbg_regs: " & integer'image(checks) & " checks, " & integer'image(errors) & " errors";
      if errors /= 0 then
         report "tb_zn_dbg_regs FAILED" severity failure;
      end if;
      done <= true;
      wait;
   end process;

end architecture;
