-- SIO0 replay with the ZN-2 serial subsystem in the CPU group: the same MAME
-- 0.288 SIO0 and znsecsel traffic as sim/zn2/tb_sio0_replay.vhd (vectors
-- from tools/gnet/sio0_vectors.py, in 33.8688 MHz cycles), but zn_sio0,
-- both zn_cat702 and znmcu run on a 50.000 MHz clock as in psx_top with
-- CPU_CLK_SPLIT = 1: zn_sio0 counts its bit timer on tick_accum's
-- 33.8688 MHz-equivalent sys_tick (decision 1 in
-- docs/r1_cpu_domain_design.md) and znmcu has CLK_HZ 50,000,000.
-- Each access is driven at the first 50 MHz edge at or after its MAME time
-- (event n at n x 29.5257 ns from the start, absolute, so retries do not
-- shift later events). A status read that differs is read again on up to
-- TOL further edges (default 5 x 20 ns, about the 3 cycles of 29.5 ns the
-- 33.8688 MHz replay allows); data and control reads must match at once.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use STD.textio.all;

entity tb_sio0_replay50 is
   generic
   (
      DIR      : string  := "work";
      VEC      : string  := "sio0.vec";
      DSW      : integer := 15;
      TOL      : integer := 5
   );
end entity;

architecture sim of tb_sio0_replay50 is
   constant T_CPU  : time := 20 ns;
   constant T_1X   : time := 29525699 fs;   -- 33.8688 MHz

   signal clk       : std_logic := '0';
   signal reset     : std_logic := '1';
   signal sys_tick  : std_logic;
   signal bus_addr  : unsigned(3 downto 0) := (others => '0');
   signal bus_wdata : std_logic_vector(31 downto 0) := (others => '0');
   signal bus_read, bus_write : std_logic := '0';
   signal bus_mask  : std_logic_vector(3 downto 0) := (others => '0');
   signal bus_rdata : std_logic_vector(31 downto 0);
   signal irq       : std_logic;
   signal bit_stb, txd, rxd, dsr_n : std_logic;
   signal out0, out1, outm : std_logic;
   signal znsecsel  : std_logic_vector(7 downto 0) := x"00";
   signal mcu_sel_n : std_logic;
   signal key_we    : std_logic_vector(1 downto 0) := "00";
   signal key_addr  : unsigned(2 downto 0) := (others => '0');
   signal key_data  : std_logic_vector(7 downto 0) := (others => '0');
   signal finished  : boolean := false;

   function hex(s : string) return std_logic_vector is
      variable v : std_logic_vector(4 * s'length - 1 downto 0);
      variable d : integer;
   begin
      for i in s'range loop
         case s(i) is
            when '0' to '9' => d := character'pos(s(i)) - character'pos('0');
            when 'a' to 'f' => d := character'pos(s(i)) - character'pos('a') + 10;
            when others     => d := 0;
         end case;
         v(4 * (s'high - i) + 3 downto 4 * (s'high - i)) := std_logic_vector(to_unsigned(d, 4));
      end loop;
      return v;
   end function;
begin
   clk <= not clk after T_CPU / 2 when not finished;   -- 50.000 MHz

   itick : entity work.tick_accum
   port map (clk => clk, rst => reset, ce => '1', tick => sys_tick);

   sio : entity work.zn_sio0 generic map (PS1_TIMING => 0)
   port map (clk1x => clk, ce => '1', reset => reset, sys_tick => sys_tick, bus_addr => bus_addr, bus_dataWrite => bus_wdata,
             bus_read => bus_read, bus_write => bus_write, bus_writeMask => bus_mask, bus_dataRead => bus_rdata,
             irqRequest => irq, bit_stb => bit_stb, txd => txd, rxd => rxd, dsr_n => dsr_n);

   c0 : entity work.zn_cat702
   port map (clk => clk, reset => reset, key_we => key_we(0), key_addr => key_addr, key_data => key_data,
             sel_n => znsecsel(2), bit_stb => bit_stb, txd => txd, dataout => out0);
   c1 : entity work.zn_cat702
   port map (clk => clk, reset => reset, key_we => key_we(1), key_addr => key_addr, key_data => key_data,
             sel_n => znsecsel(3), bit_stb => bit_stb, txd => txd, dataout => out1);

   mcu_sel_n <= '0' when (znsecsel and x"8C") = x"8C" else '1';
   mcu : entity work.znmcu
   generic map (CLK_HZ => 50000000)
   port map (clk => clk, reset => reset, sel_n => mcu_sel_n, analog_rd => znsecsel(4), trackball_rd => znsecsel(5),
             bit_stb => bit_stb, txd => outm, dsr_n => dsr_n, dsw => std_logic_vector(to_unsigned(DSW, 4)));

   rxd <= out0 and out1 and outm;

   process
      file fk, fv : text;
      variable l  : line;
      variable s2 : string(1 to 2);
      variable s1 : string(1 to 1);
      variable s4 : string(1 to 4);
      variable s8 : string(1 to 8);
      variable c  : character;
      variable op : character;
      variable cyc : integer;
      variable tgt : time;           -- MAME time of the current event
      variable t0  : time;
      variable b  : std_logic_vector(3 downto 0);
      variable m, d : std_logic_vector(31 downto 0);
      variable nr, nw, ns, nbad, nlate, ntol : integer := 0;
      variable ok : boolean;
      type t_hist is array(1 to 16) of integer;
      variable hist : t_hist := (others => 0);

      -- wait until the next edge is the first at or after tgt
      procedure wait_target is
      begin
         if now >= tgt then
            nlate := nlate + 1;
         else
            while now + T_CPU < tgt loop wait until rising_edge(clk); end loop;
         end if;
      end procedure;
   begin
      for k in 0 to 1 loop
         file_open(fk, DIR & "/key_" & integer'image(k) & ".hex", read_mode);
         for i in 0 to 7 loop
            readline(fk, l); read(l, s2);
            key_addr <= to_unsigned(i, 3); key_data <= hex(s2); key_we <= (others => '0'); key_we(k) <= '1';
            wait until rising_edge(clk);
         end loop;
         file_close(fk);
      end loop;
      key_we <= "00";
      wait until rising_edge(clk);
      reset <= '0';
      znsecsel <= x"0C";
      t0  := now;
      tgt := t0;

      file_open(fv, DIR & "/" & VEC, read_mode);
      while not endfile(fv) loop
         readline(fv, l);
         read(l, cyc);              -- 33.8688 MHz cycles since the previous event
         read(l, c); read(l, op);
         tgt := tgt + cyc * T_1X;
         if op = 'N' then
            null;
         elsif op = 'S' then
            read(l, c); read(l, s2);
            wait_target;
            znsecsel <= hex(s2);
            ns := ns + 1;
            wait until rising_edge(clk);
         else
            read(l, c); read(l, s1); read(l, c); read(l, s4); read(l, c); read(l, s8);
            wait_target;
            bus_addr <= unsigned(hex(s1));
            for i in 0 to 3 loop
               if s4(4 - i) = '1' then b(i) := '1'; else b(i) := '0'; end if;
            end loop;
            bus_mask <= b;
            d := hex(s8);
            bus_wdata <= d;
            if op = 'W' then
               bus_write <= '1'; nw := nw + 1;
               wait until rising_edge(clk);
               bus_write <= '0';
            else
               bus_read <= '1'; nr := nr + 1;
               wait until rising_edge(clk);
               bus_read <= '0';
               wait until falling_edge(clk);
               for i in 0 to 3 loop
                  if b(i) = '1' then m(8 * i + 7 downto 8 * i) := x"FF"; else m(8 * i + 7 downto 8 * i) := x"00"; end if;
               end loop;
               ok := (bus_rdata and m) = (d and m);
               if not ok and s1 = "4" then
                  for k in 1 to TOL loop
                     bus_read <= '1';
                     wait until rising_edge(clk);
                     bus_read <= '0';
                     wait until falling_edge(clk);
                     if (bus_rdata and m) = (d and m) then
                        ok := true;
                        ntol := ntol + 1;
                        hist(k) := hist(k) + 1;
                        exit;
                     end if;
                  end loop;
               end if;
               if not ok then
                  nbad := nbad + 1;
                  if nbad <= 12 then
                     report "read " & s1 & " be " & s4 & ": MAME " & s8 &
                            " RTL " & to_hstring(bus_rdata) & " at " & time'image(now - t0) severity error;
                  end if;
               end if;
            end if;
         end if;
      end loop;
      file_close(fv);
      report "SIO0 replay at 50 MHz with sys_tick: " & integer'image(nr) & " reads, " & integer'image(nw) & " writes, " &
             integer'image(ns) & " znsecsel writes, events issued late " & integer'image(nlate) &
             ", status reads matching within " & integer'image(TOL) & " cycles " & integer'image(ntol) &
             ", read mismatches " & integer'image(nbad);
      for k in 1 to TOL loop
         report "  late by " & integer'image(k) & " cycle(s): " & integer'image(hist(k));
      end loop;
      assert nbad = 0 report "SIO0 replay FAILED" severity failure;
      report "SIO0 replay PASSED";
      finished <= true;
      wait;
   end process;
end architecture;
