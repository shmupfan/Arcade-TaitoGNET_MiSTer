-- GTE command hold time in CPU cycles (docs/cpu_rate_probe.md, "GTE clock ratio").
-- GTE clock period 10 ns; CPU clock period CPU_NS (20 = PSX_MiSTer's 2x, 16 = 1.6x).
-- STROBE 0: clk2xIndex exactly as psx_top.vhd:712-721 (valid only for CPU_NS = 20).
-- STROBE 1: clk2xIndex = '1' on the first GTE edge after each CPU edge (any ratio).
-- For each command, gte_cmdEna is driven for one CPU cycle from CPU edge P (as the
-- writeback stage does, cpu.vhd:2456-2458); the result is the number of CPU edges
-- from P to the first CPU edge that samples gte_busy = '0' (cpu.vhd:1857-1859),
-- i.e. the hold seen by an immediately following MFC2/CFC2/SWC2 or GTE command.
-- Each command is issued at all 5 CPU-edge phases of the CPU/GTE pattern.
library IEEE; use IEEE.std_logic_1164.all; use IEEE.numeric_std.all; use STD.textio.all;
entity tb_gte_busy_ratio is
   generic (CPU_NS : integer := 16; STROBE : integer := 1; TURBO_I : integer := 0; NM : integer := 0);   -- NM: gte NARROW_MUL
end entity;
architecture sim of tb_gte_busy_ratio is
   signal clk1x, clk2x : std_logic := '0';
   signal clk1xToggle, clk1xToggle2x, clk2xIndex : std_logic := '0';
   signal reset   : std_logic := '1';
   signal turbo   : std_logic;
   signal busy    : std_logic;
   signal cmdEna  : std_logic := '0';
   signal cmdData : unsigned(31 downto 0) := (others => '0');
   signal rd      : unsigned(31 downto 0);
   signal ssr     : std_logic_vector(31 downto 0);
   signal ssi, dbg : std_logic;
   type tarr is array(0 to 21) of integer;
   constant ops : tarr := (16#01#,16#06#,16#0C#,16#10#,16#11#,16#12#,16#13#,16#14#,16#16#,16#1B#,16#1C#,
                           16#1E#,16#20#,16#28#,16#29#,16#2A#,16#2D#,16#2E#,16#30#,16#3D#,16#3E#,16#3F#);
begin
   turbo <= '1' when TURBO_I = 1 else '0';

   -- both clocks start at t=0 in the same delta, so coincident edges sample pre-edge values
   process begin wait for 0 ns; loop clk2x <= '1'; wait for 5 ns; clk2x <= '0'; wait for 5 ns; end loop; end process;
   process begin wait for 0 ns; loop clk1x <= '1'; wait for (CPU_NS / 2) * 1 ns; clk1x <= '0'; wait for (CPU_NS / 2) * 1 ns; end loop; end process;

   gstrobe0 : if STROBE = 0 generate
      process(clk1x) begin if rising_edge(clk1x) then clk1xToggle <= not clk1xToggle; end if; end process;
      process(clk2x) begin
         if rising_edge(clk2x) then
            clk1xToggle2x <= clk1xToggle;
            clk2xIndex    <= '0';
            if (clk1xToggle2x = clk1xToggle) then clk2xIndex <= '1'; end if;
         end if;
      end process;
   end generate;

   gstrobe1 : if STROBE = 1 generate
      process
         variable t : integer;
      begin
         wait for 0 ns;
         loop
            wait until rising_edge(clk2x);
            t := now / 1 ns;
            -- next GTE edge (t + 10) is the first after a CPU edge in [t, t + 10)
            if ((t + CPU_NS - 1) / CPU_NS) * CPU_NS < t + 10 then clk2xIndex <= '1'; else clk2xIndex <= '0'; end if;
         end loop;
      end process;
   end generate;

   dut : entity work.gte generic map (NARROW_MUL => NM) port map (
      clk1x => clk1x, clk2x => clk2x, clk2xIndex => clk2xIndex, ce => '1', reset => reset,
      WIDESCREEN => "00", TURBO => turbo, gte_busy => busy, gte_readAddr => (others => '0'), gte_readData => rd, gte_readEna => '0',
      gte_writeAddr_in => (others => '0'), gte_writeData_in => (others => '0'), gte_writeEna_in => '0',
      gte_cmdData => cmdData, gte_cmdEna => cmdEna, loading_savestate => '0', SS_reset => '0', SS_DataWrite => (others => '0'),
      SS_Adr => (others => '0'), SS_wren => '0', SS_rden => '0', SS_DataRead => ssr, SS_idle => ssi, debug_firstGTE => dbg);

   process
      variable l : line;
      variable s : integer;
   begin
      for i in 0 to 9 loop wait until rising_edge(clk1x); end loop;
      reset <= '0';
      for i in 0 to 9 loop wait until rising_edge(clk1x); end loop;
      for k in 0 to 21 loop
         for ph in 0 to 4 loop
            loop wait until rising_edge(clk1x); exit when ((now / 1 ns) / CPU_NS) mod 5 = ph; end loop;
            cmdEna  <= '1';                                     -- edge P
            cmdData <= to_unsigned(ops(k), 32);
            s := 0;
            loop
               wait until rising_edge(clk1x);
               cmdEna <= '0';
               s := s + 1;
               exit when busy = '0';
            end loop;
            write(l, string'("op ")); write(l, ops(k)); write(l, string'(" phase ")); write(l, ph);
            write(l, string'(" hold ")); write(l, s); writeline(output, l);
            for i in 0 to 5 loop wait until rising_edge(clk1x); end loop;
         end loop;
      end loop;
      std.env.finish;
   end process;
end architecture;
