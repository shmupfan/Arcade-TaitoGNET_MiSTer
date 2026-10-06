-- Full-GTE equivalence check (docs/cpu_rate_probe.md, "GTE at 100 MHz").
-- Two gte instances, NARROW_MUL = NA (default 0, upstream) and NARROW_MUL = NB
-- (default 3), get the same random input sequence; every clk2x cycle the bench
-- compares the outputs (gte_busy, gte_readData, SS_DataRead, SS_idle,
-- debug_firstGTE) and 164 internal signals (every GTE register, the step
-- state, the MAC and divider outputs and accumulators) and stops at the first
-- difference.
-- Stimulus, in episodes of 500 to 4500 cycles with their own rates: register
-- writes (MTC2/CTC2 style, any of the 64 addresses, random and edge-case data,
-- also while a command runs), reads, commands (the 22 opcodes with random sf,
-- mx, v, cv, lm bits, sometimes an unknown opcode, back to back or while busy),
-- turbo on and off, widescreen modes, ce low for 1 to 12 cycles, resets, and
-- savestate loads.
-- The list of internal signals is generated from the gte.vhd declarations.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use STD.textio.all;
use work.pGTE.all;

entity tb_gte_equiv is
   generic
   (
      N    : integer := 1000000;   -- clk2x cycles
      SEED : integer := 1;
      NA   : integer := 0;
      NB   : integer := 3
   );
end entity;

architecture sim of tb_gte_equiv is
   signal clk1x, clk2x         : std_logic := '0';
   signal clk1xToggle          : std_logic := '0';
   signal clk1xToggle2x        : std_logic := '0';
   signal clk2xIndex           : std_logic := '0';
   signal ce                   : std_logic := '1';
   signal reset                : std_logic := '1';
   signal turbo                : std_logic := '0';
   signal lss                  : std_logic := '0';
   signal ss_wren              : std_logic := '0';
   signal ss_rden              : std_logic := '0';
   signal widescreen           : std_logic_vector(1 downto 0) := "00";
   signal readAddr             : unsigned(5 downto 0) := (others => '0');
   signal writeAddr            : unsigned(5 downto 0) := (others => '0');
   signal ssAdr                : unsigned(5 downto 0) := (others => '0');
   signal readEna              : std_logic := '0';
   signal writeEna             : std_logic := '0';
   signal cmdEna               : std_logic := '0';
   signal writeData            : unsigned(31 downto 0) := (others => '0');
   signal cmdData              : unsigned(31 downto 0) := (others => '0');
   signal ssData               : std_logic_vector(31 downto 0) := (others => '0');
   signal busyA, busyB         : std_logic;
   signal idleA, idleB         : std_logic;
   signal dbgA, dbgB           : std_logic;
   signal rdA, rdB             : unsigned(31 downto 0);
   signal ssrA, ssrB           : std_logic_vector(31 downto 0);
   signal done                 : boolean := false;
   signal cmdAtEdge            : unsigned(31 downto 0) := (others => '0');
   signal nCeLow, nReset, nSS  : integer := 0;
begin

   -- both clocks start at t = 0 in the same delta
   process begin wait for 0 ns; while not done loop clk2x <= '1'; wait for 5 ns;  clk2x <= '0'; wait for 5 ns;  end loop; wait; end process;
   process begin wait for 0 ns; while not done loop clk1x <= '1'; wait for 10 ns; clk1x <= '0'; wait for 10 ns; end loop; wait; end process;

   -- clk2xIndex as psx_top.vhd
   process (clk1x) begin if rising_edge(clk1x) then clk1xToggle <= not clk1xToggle; end if; end process;
   process (clk2x)
   begin
      if rising_edge(clk2x) then
         clk1xToggle2x <= clk1xToggle;
         clk2xIndex    <= '0';
         if (clk1xToggle2x = clk1xToggle) then clk2xIndex <= '1'; end if;
         cmdAtEdge     <= cmdData;
      end if;
   end process;

   ua : entity work.gte generic map (NARROW_MUL => NA) port map (
      clk1x => clk1x, clk2x => clk2x, clk2xIndex => clk2xIndex, ce => ce, reset => reset,
      WIDESCREEN => widescreen, TURBO => turbo, gte_busy => busyA, gte_readAddr => readAddr, gte_readData => rdA, gte_readEna => readEna,
      gte_writeAddr_in => writeAddr, gte_writeData_in => writeData, gte_writeEna_in => writeEna, gte_cmdData => cmdData, gte_cmdEna => cmdEna,
      loading_savestate => lss, SS_reset => '0', SS_DataWrite => ssData, SS_Adr => ssAdr, SS_wren => ss_wren, SS_rden => ss_rden,
      SS_DataRead => ssrA, SS_idle => idleA, debug_firstGTE => dbgA);

   ub : entity work.gte generic map (NARROW_MUL => NB) port map (
      clk1x => clk1x, clk2x => clk2x, clk2xIndex => clk2xIndex, ce => ce, reset => reset,
      WIDESCREEN => widescreen, TURBO => turbo, gte_busy => busyB, gte_readAddr => readAddr, gte_readData => rdB, gte_readEna => readEna,
      gte_writeAddr_in => writeAddr, gte_writeData_in => writeData, gte_writeEna_in => writeEna, gte_cmdData => cmdData, gte_cmdEna => cmdEna,
      loading_savestate => lss, SS_reset => '0', SS_DataWrite => ssData, SS_Adr => ssAdr, SS_wren => ss_wren, SS_rden => ss_rden,
      SS_DataRead => ssrB, SS_idle => idleB, debug_firstGTE => dbgB);

   -- stimulus, changed right after each clk2x edge
   stim : process
      variable s1, s2  : positive;
      variable r       : real;
      impure function rnd return real is
      begin
         uniform(s1, s2, r);
         return r;
      end function;
      impure function ri(k : integer) return integer is   -- 0 .. k - 1
      begin
         uniform(s1, s2, r);
         return integer(floor(r * real(k)));
      end function;
      impure function rbits(n : integer) return unsigned is
         variable v : unsigned(n - 1 downto 0);
      begin
         for i in 0 to n - 1 loop
            if rnd < 0.5 then v(i) := '0'; else v(i) := '1'; end if;
         end loop;
         return v;
      end function;
      impure function rhalf return unsigned is
         variable h : unsigned(15 downto 0);
      begin
         case ri(10) is
            when 0      => h := x"0000";
            when 1      => h := x"0001";
            when 2      => h := x"FFFF";
            when 3      => h := x"7FFF";
            when 4      => h := x"8000";
            when 5      => h := x"1000";
            when 6      => h := x"F000";
            when 7      => h := unsigned(resize(signed(rbits(1 + ri(13))), 16));
            when others => h := rbits(16);
         end case;
         return h;
      end function;
      impure function rval return unsigned is
         variable v : unsigned(31 downto 0);
      begin
         case ri(5) is
            when 0      => v := rbits(32);
            when 1      => v := unsigned(resize(signed(rbits(1 + ri(16))), 32));
            when 2      => v := rhalf & rhalf;
            when 3      => v := unsigned(resize(signed(rbits(1 + ri(32))), 32));
            when others => v := unsigned(resize(signed(rbits(1 + ri(16))), 16)) & unsigned(resize(signed(rbits(1 + ri(16))), 16));
         end case;
         return v;
      end function;
      type tops is array(0 to 21) of integer;
      constant ops : tops := (16#01#, 16#06#, 16#0C#, 16#10#, 16#11#, 16#12#, 16#13#, 16#14#, 16#16#, 16#1B#, 16#1C#,
                              16#1E#, 16#20#, 16#28#, 16#29#, 16#2A#, 16#2D#, 16#2E#, 16#30#, 16#3D#, 16#3E#, 16#3F#);
      variable pW, pR, pC, pCB, pCe, pRst, pSS : real := 0.0;
      variable ceLow, rstCnt, ssCnt, cmdHold    : integer := 0;
      variable epLeft                            : integer := 0;
      variable v                                 : unsigned(31 downto 0);
   begin
      s1 := 1 + SEED; s2 := 104729 + 31 * SEED;
      for i in 1 to 10 loop wait until rising_edge(clk2x); end loop;
      reset <= '0';
      for c in 1 to N loop
         wait until rising_edge(clk2x);
         if (epLeft = 0) then
            epLeft := 500 + ri(4000);
            pW   := 0.02 + 0.40 * rnd;
            pR   := 0.30 * rnd;
            pC   := 0.05 + 0.60 * rnd;
            pCB  := 0.03 * rnd;
            pCe  := 0.0; if (ri(3) = 0)  then pCe  := 0.05  * rnd; end if;
            pRst := 0.0; if (ri(6) = 0)  then pRst := 0.002 * rnd; end if;
            pSS  := 0.0; if (ri(8) = 0)  then pSS  := 0.002 * rnd; end if;
            if (ri(2) = 0) then turbo <= '0'; else turbo <= '1'; end if;
            if (ri(4) = 0) then widescreen <= std_logic_vector(rbits(2)); else widescreen <= "00"; end if;
         end if;
         epLeft := epLeft - 1;
         if (rnd < 0.0005) then turbo <= not turbo; end if;

         -- ce, reset, savestate load
         ce <= '1';
         if (ceLow > 0) then
            ce <= '0'; ceLow := ceLow - 1;
         elsif (rnd < pCe) then
            ce <= '0'; ceLow := ri(12); nCeLow <= nCeLow + 1;
         end if;
         reset <= '0';
         if (rstCnt > 0) then
            reset <= '1'; rstCnt := rstCnt - 1;
         elsif (rnd < pRst) then
            reset <= '1'; rstCnt := ri(8); nReset <= nReset + 1;
         end if;
         lss <= '0'; ss_wren <= '0';
         if (ssCnt > 0 or rnd < pSS) then
            if (ssCnt = 0) then ssCnt := 2 + ri(40); nSS <= nSS + 1; end if;
            ssCnt := ssCnt - 1;
            lss   <= '1';
            if (rnd < 0.5) then ss_wren <= '1'; end if;
            ssData <= std_logic_vector(rval);
         end if;
         ssAdr   <= rbits(6);
         ss_rden <= '0'; if (rnd < 0.1) then ss_rden <= '1'; end if;

         -- register writes and reads
         writeEna <= '0';
         if (rnd < pW) then
            writeEna  <= '1';
            writeAddr <= rbits(6);
            writeData <= rval;
         end if;
         readEna <= '0';
         if (rnd < pR) then
            readEna  <= '1';
            readAddr <= rbits(6);
         end if;

         -- commands, held for 1 or 2 clk2x cycles (the CPU holds one clk1x cycle)
         if (cmdHold > 0) then
            cmdHold := cmdHold - 1;
         else
            cmdEna <= '0';
            if ((busyA = '0' and rnd < pC) or rnd < pCB) then
               v := rbits(32);
               if (rnd < 0.97) then
                  v(5 downto 0) := to_unsigned(ops(ri(22)), 6);
               end if;
               cmdData <= v;
               cmdEna  <= '1';
               cmdHold := ri(2);
            end if;
         end if;
      end loop;
      wait until rising_edge(clk2x);
      done <= true;
      wait;
   end process;

   check : block
      alias a_gte_writeAddr is << signal .tb_gte_equiv.ua.gte_writeAddr : unsigned(5 downto 0) >>;
      alias b_gte_writeAddr is << signal .tb_gte_equiv.ub.gte_writeAddr : unsigned(5 downto 0) >>;
      alias a_gte_writeData is << signal .tb_gte_equiv.ua.gte_writeData : unsigned(31 downto 0) >>;
      alias b_gte_writeData is << signal .tb_gte_equiv.ub.gte_writeData : unsigned(31 downto 0) >>;
      alias a_gte_writeEna is << signal .tb_gte_equiv.ua.gte_writeEna : std_logic >>;
      alias b_gte_writeEna is << signal .tb_gte_equiv.ub.gte_writeEna : std_logic >>;
      alias a_REG_V0X is << signal .tb_gte_equiv.ua.REG_V0X : signed(15 downto 0) >>;
      alias b_REG_V0X is << signal .tb_gte_equiv.ub.REG_V0X : signed(15 downto 0) >>;
      alias a_REG_V0Y is << signal .tb_gte_equiv.ua.REG_V0Y : signed(15 downto 0) >>;
      alias b_REG_V0Y is << signal .tb_gte_equiv.ub.REG_V0Y : signed(15 downto 0) >>;
      alias a_REG_V0Z is << signal .tb_gte_equiv.ua.REG_V0Z : signed(15 downto 0) >>;
      alias b_REG_V0Z is << signal .tb_gte_equiv.ub.REG_V0Z : signed(15 downto 0) >>;
      alias a_REG_V1X is << signal .tb_gte_equiv.ua.REG_V1X : signed(15 downto 0) >>;
      alias b_REG_V1X is << signal .tb_gte_equiv.ub.REG_V1X : signed(15 downto 0) >>;
      alias a_REG_V1Y is << signal .tb_gte_equiv.ua.REG_V1Y : signed(15 downto 0) >>;
      alias b_REG_V1Y is << signal .tb_gte_equiv.ub.REG_V1Y : signed(15 downto 0) >>;
      alias a_REG_V1Z is << signal .tb_gte_equiv.ua.REG_V1Z : signed(15 downto 0) >>;
      alias b_REG_V1Z is << signal .tb_gte_equiv.ub.REG_V1Z : signed(15 downto 0) >>;
      alias a_REG_V2X is << signal .tb_gte_equiv.ua.REG_V2X : signed(15 downto 0) >>;
      alias b_REG_V2X is << signal .tb_gte_equiv.ub.REG_V2X : signed(15 downto 0) >>;
      alias a_REG_V2Y is << signal .tb_gte_equiv.ua.REG_V2Y : signed(15 downto 0) >>;
      alias b_REG_V2Y is << signal .tb_gte_equiv.ub.REG_V2Y : signed(15 downto 0) >>;
      alias a_REG_V2Z is << signal .tb_gte_equiv.ua.REG_V2Z : signed(15 downto 0) >>;
      alias b_REG_V2Z is << signal .tb_gte_equiv.ub.REG_V2Z : signed(15 downto 0) >>;
      alias a_REG_RGBC is << signal .tb_gte_equiv.ua.REG_RGBC : unsigned(31 downto 0) >>;
      alias b_REG_RGBC is << signal .tb_gte_equiv.ub.REG_RGBC : unsigned(31 downto 0) >>;
      alias a_REG_OTZ is << signal .tb_gte_equiv.ua.REG_OTZ : unsigned(15 downto 0) >>;
      alias b_REG_OTZ is << signal .tb_gte_equiv.ub.REG_OTZ : unsigned(15 downto 0) >>;
      alias a_REG_IR0 is << signal .tb_gte_equiv.ua.REG_IR0 : signed(15 downto 0) >>;
      alias b_REG_IR0 is << signal .tb_gte_equiv.ub.REG_IR0 : signed(15 downto 0) >>;
      alias a_REG_IR1 is << signal .tb_gte_equiv.ua.REG_IR1 : signed(15 downto 0) >>;
      alias b_REG_IR1 is << signal .tb_gte_equiv.ub.REG_IR1 : signed(15 downto 0) >>;
      alias a_REG_IR2 is << signal .tb_gte_equiv.ua.REG_IR2 : signed(15 downto 0) >>;
      alias b_REG_IR2 is << signal .tb_gte_equiv.ub.REG_IR2 : signed(15 downto 0) >>;
      alias a_REG_IR3 is << signal .tb_gte_equiv.ua.REG_IR3 : signed(15 downto 0) >>;
      alias b_REG_IR3 is << signal .tb_gte_equiv.ub.REG_IR3 : signed(15 downto 0) >>;
      alias a_REG_SX0 is << signal .tb_gte_equiv.ua.REG_SX0 : signed(15 downto 0) >>;
      alias b_REG_SX0 is << signal .tb_gte_equiv.ub.REG_SX0 : signed(15 downto 0) >>;
      alias a_REG_SY0 is << signal .tb_gte_equiv.ua.REG_SY0 : signed(15 downto 0) >>;
      alias b_REG_SY0 is << signal .tb_gte_equiv.ub.REG_SY0 : signed(15 downto 0) >>;
      alias a_REG_SX1 is << signal .tb_gte_equiv.ua.REG_SX1 : signed(15 downto 0) >>;
      alias b_REG_SX1 is << signal .tb_gte_equiv.ub.REG_SX1 : signed(15 downto 0) >>;
      alias a_REG_SY1 is << signal .tb_gte_equiv.ua.REG_SY1 : signed(15 downto 0) >>;
      alias b_REG_SY1 is << signal .tb_gte_equiv.ub.REG_SY1 : signed(15 downto 0) >>;
      alias a_REG_SX2 is << signal .tb_gte_equiv.ua.REG_SX2 : signed(15 downto 0) >>;
      alias b_REG_SX2 is << signal .tb_gte_equiv.ub.REG_SX2 : signed(15 downto 0) >>;
      alias a_REG_SY2 is << signal .tb_gte_equiv.ua.REG_SY2 : signed(15 downto 0) >>;
      alias b_REG_SY2 is << signal .tb_gte_equiv.ub.REG_SY2 : signed(15 downto 0) >>;
      alias a_REG_SZ0 is << signal .tb_gte_equiv.ua.REG_SZ0 : unsigned(15 downto 0) >>;
      alias b_REG_SZ0 is << signal .tb_gte_equiv.ub.REG_SZ0 : unsigned(15 downto 0) >>;
      alias a_REG_SZ1 is << signal .tb_gte_equiv.ua.REG_SZ1 : unsigned(15 downto 0) >>;
      alias b_REG_SZ1 is << signal .tb_gte_equiv.ub.REG_SZ1 : unsigned(15 downto 0) >>;
      alias a_REG_SZ2 is << signal .tb_gte_equiv.ua.REG_SZ2 : unsigned(15 downto 0) >>;
      alias b_REG_SZ2 is << signal .tb_gte_equiv.ub.REG_SZ2 : unsigned(15 downto 0) >>;
      alias a_REG_SZ3 is << signal .tb_gte_equiv.ua.REG_SZ3 : unsigned(15 downto 0) >>;
      alias b_REG_SZ3 is << signal .tb_gte_equiv.ub.REG_SZ3 : unsigned(15 downto 0) >>;
      alias a_REG_RGB0 is << signal .tb_gte_equiv.ua.REG_RGB0 : unsigned(31 downto 0) >>;
      alias b_REG_RGB0 is << signal .tb_gte_equiv.ub.REG_RGB0 : unsigned(31 downto 0) >>;
      alias a_REG_RGB1 is << signal .tb_gte_equiv.ua.REG_RGB1 : unsigned(31 downto 0) >>;
      alias b_REG_RGB1 is << signal .tb_gte_equiv.ub.REG_RGB1 : unsigned(31 downto 0) >>;
      alias a_REG_RGB2 is << signal .tb_gte_equiv.ua.REG_RGB2 : unsigned(31 downto 0) >>;
      alias b_REG_RGB2 is << signal .tb_gte_equiv.ub.REG_RGB2 : unsigned(31 downto 0) >>;
      alias a_REG_RES1 is << signal .tb_gte_equiv.ua.REG_RES1 : unsigned(31 downto 0) >>;
      alias b_REG_RES1 is << signal .tb_gte_equiv.ub.REG_RES1 : unsigned(31 downto 0) >>;
      alias a_REG_MAC0 is << signal .tb_gte_equiv.ua.REG_MAC0 : signed(31 downto 0) >>;
      alias b_REG_MAC0 is << signal .tb_gte_equiv.ub.REG_MAC0 : signed(31 downto 0) >>;
      alias a_REG_MAC1 is << signal .tb_gte_equiv.ua.REG_MAC1 : signed(31 downto 0) >>;
      alias b_REG_MAC1 is << signal .tb_gte_equiv.ub.REG_MAC1 : signed(31 downto 0) >>;
      alias a_REG_MAC2 is << signal .tb_gte_equiv.ua.REG_MAC2 : signed(31 downto 0) >>;
      alias b_REG_MAC2 is << signal .tb_gte_equiv.ub.REG_MAC2 : signed(31 downto 0) >>;
      alias a_REG_MAC3 is << signal .tb_gte_equiv.ua.REG_MAC3 : signed(31 downto 0) >>;
      alias b_REG_MAC3 is << signal .tb_gte_equiv.ub.REG_MAC3 : signed(31 downto 0) >>;
      alias a_REG_IRGB is << signal .tb_gte_equiv.ua.REG_IRGB : unsigned(14 downto 0) >>;
      alias b_REG_IRGB is << signal .tb_gte_equiv.ub.REG_IRGB : unsigned(14 downto 0) >>;
      alias a_REG_ORGB is << signal .tb_gte_equiv.ua.REG_ORGB : unsigned(14 downto 0) >>;
      alias b_REG_ORGB is << signal .tb_gte_equiv.ub.REG_ORGB : unsigned(14 downto 0) >>;
      alias a_REG_LZCS is << signal .tb_gte_equiv.ua.REG_LZCS : signed(31 downto 0) >>;
      alias b_REG_LZCS is << signal .tb_gte_equiv.ub.REG_LZCS : signed(31 downto 0) >>;
      alias a_REG_LZCR is << signal .tb_gte_equiv.ua.REG_LZCR : signed(31 downto 0) >>;
      alias b_REG_LZCR is << signal .tb_gte_equiv.ub.REG_LZCR : signed(31 downto 0) >>;
      alias a_REG_RT11 is << signal .tb_gte_equiv.ua.REG_RT11 : signed(15 downto 0) >>;
      alias b_REG_RT11 is << signal .tb_gte_equiv.ub.REG_RT11 : signed(15 downto 0) >>;
      alias a_REG_RT12 is << signal .tb_gte_equiv.ua.REG_RT12 : signed(15 downto 0) >>;
      alias b_REG_RT12 is << signal .tb_gte_equiv.ub.REG_RT12 : signed(15 downto 0) >>;
      alias a_REG_RT13 is << signal .tb_gte_equiv.ua.REG_RT13 : signed(15 downto 0) >>;
      alias b_REG_RT13 is << signal .tb_gte_equiv.ub.REG_RT13 : signed(15 downto 0) >>;
      alias a_REG_RT21 is << signal .tb_gte_equiv.ua.REG_RT21 : signed(15 downto 0) >>;
      alias b_REG_RT21 is << signal .tb_gte_equiv.ub.REG_RT21 : signed(15 downto 0) >>;
      alias a_REG_RT22 is << signal .tb_gte_equiv.ua.REG_RT22 : signed(15 downto 0) >>;
      alias b_REG_RT22 is << signal .tb_gte_equiv.ub.REG_RT22 : signed(15 downto 0) >>;
      alias a_REG_RT23 is << signal .tb_gte_equiv.ua.REG_RT23 : signed(15 downto 0) >>;
      alias b_REG_RT23 is << signal .tb_gte_equiv.ub.REG_RT23 : signed(15 downto 0) >>;
      alias a_REG_RT31 is << signal .tb_gte_equiv.ua.REG_RT31 : signed(15 downto 0) >>;
      alias b_REG_RT31 is << signal .tb_gte_equiv.ub.REG_RT31 : signed(15 downto 0) >>;
      alias a_REG_RT32 is << signal .tb_gte_equiv.ua.REG_RT32 : signed(15 downto 0) >>;
      alias b_REG_RT32 is << signal .tb_gte_equiv.ub.REG_RT32 : signed(15 downto 0) >>;
      alias a_REG_RT33 is << signal .tb_gte_equiv.ua.REG_RT33 : signed(15 downto 0) >>;
      alias b_REG_RT33 is << signal .tb_gte_equiv.ub.REG_RT33 : signed(15 downto 0) >>;
      alias a_REG_TR0 is << signal .tb_gte_equiv.ua.REG_TR0 : unsigned(31 downto 0) >>;
      alias b_REG_TR0 is << signal .tb_gte_equiv.ub.REG_TR0 : unsigned(31 downto 0) >>;
      alias a_REG_TR1 is << signal .tb_gte_equiv.ua.REG_TR1 : unsigned(31 downto 0) >>;
      alias b_REG_TR1 is << signal .tb_gte_equiv.ub.REG_TR1 : unsigned(31 downto 0) >>;
      alias a_REG_TR2 is << signal .tb_gte_equiv.ua.REG_TR2 : unsigned(31 downto 0) >>;
      alias b_REG_TR2 is << signal .tb_gte_equiv.ub.REG_TR2 : unsigned(31 downto 0) >>;
      alias a_REG_LL11 is << signal .tb_gte_equiv.ua.REG_LL11 : signed(15 downto 0) >>;
      alias b_REG_LL11 is << signal .tb_gte_equiv.ub.REG_LL11 : signed(15 downto 0) >>;
      alias a_REG_LL12 is << signal .tb_gte_equiv.ua.REG_LL12 : signed(15 downto 0) >>;
      alias b_REG_LL12 is << signal .tb_gte_equiv.ub.REG_LL12 : signed(15 downto 0) >>;
      alias a_REG_LL13 is << signal .tb_gte_equiv.ua.REG_LL13 : signed(15 downto 0) >>;
      alias b_REG_LL13 is << signal .tb_gte_equiv.ub.REG_LL13 : signed(15 downto 0) >>;
      alias a_REG_LL21 is << signal .tb_gte_equiv.ua.REG_LL21 : signed(15 downto 0) >>;
      alias b_REG_LL21 is << signal .tb_gte_equiv.ub.REG_LL21 : signed(15 downto 0) >>;
      alias a_REG_LL22 is << signal .tb_gte_equiv.ua.REG_LL22 : signed(15 downto 0) >>;
      alias b_REG_LL22 is << signal .tb_gte_equiv.ub.REG_LL22 : signed(15 downto 0) >>;
      alias a_REG_LL23 is << signal .tb_gte_equiv.ua.REG_LL23 : signed(15 downto 0) >>;
      alias b_REG_LL23 is << signal .tb_gte_equiv.ub.REG_LL23 : signed(15 downto 0) >>;
      alias a_REG_LL31 is << signal .tb_gte_equiv.ua.REG_LL31 : signed(15 downto 0) >>;
      alias b_REG_LL31 is << signal .tb_gte_equiv.ub.REG_LL31 : signed(15 downto 0) >>;
      alias a_REG_LL32 is << signal .tb_gte_equiv.ua.REG_LL32 : signed(15 downto 0) >>;
      alias b_REG_LL32 is << signal .tb_gte_equiv.ub.REG_LL32 : signed(15 downto 0) >>;
      alias a_REG_LL33 is << signal .tb_gte_equiv.ua.REG_LL33 : signed(15 downto 0) >>;
      alias b_REG_LL33 is << signal .tb_gte_equiv.ub.REG_LL33 : signed(15 downto 0) >>;
      alias a_REG_BK0 is << signal .tb_gte_equiv.ua.REG_BK0 : unsigned(31 downto 0) >>;
      alias b_REG_BK0 is << signal .tb_gte_equiv.ub.REG_BK0 : unsigned(31 downto 0) >>;
      alias a_REG_BK1 is << signal .tb_gte_equiv.ua.REG_BK1 : unsigned(31 downto 0) >>;
      alias b_REG_BK1 is << signal .tb_gte_equiv.ub.REG_BK1 : unsigned(31 downto 0) >>;
      alias a_REG_BK2 is << signal .tb_gte_equiv.ua.REG_BK2 : unsigned(31 downto 0) >>;
      alias b_REG_BK2 is << signal .tb_gte_equiv.ub.REG_BK2 : unsigned(31 downto 0) >>;
      alias a_REG_LC11 is << signal .tb_gte_equiv.ua.REG_LC11 : signed(15 downto 0) >>;
      alias b_REG_LC11 is << signal .tb_gte_equiv.ub.REG_LC11 : signed(15 downto 0) >>;
      alias a_REG_LC12 is << signal .tb_gte_equiv.ua.REG_LC12 : signed(15 downto 0) >>;
      alias b_REG_LC12 is << signal .tb_gte_equiv.ub.REG_LC12 : signed(15 downto 0) >>;
      alias a_REG_LC13 is << signal .tb_gte_equiv.ua.REG_LC13 : signed(15 downto 0) >>;
      alias b_REG_LC13 is << signal .tb_gte_equiv.ub.REG_LC13 : signed(15 downto 0) >>;
      alias a_REG_LC21 is << signal .tb_gte_equiv.ua.REG_LC21 : signed(15 downto 0) >>;
      alias b_REG_LC21 is << signal .tb_gte_equiv.ub.REG_LC21 : signed(15 downto 0) >>;
      alias a_REG_LC22 is << signal .tb_gte_equiv.ua.REG_LC22 : signed(15 downto 0) >>;
      alias b_REG_LC22 is << signal .tb_gte_equiv.ub.REG_LC22 : signed(15 downto 0) >>;
      alias a_REG_LC23 is << signal .tb_gte_equiv.ua.REG_LC23 : signed(15 downto 0) >>;
      alias b_REG_LC23 is << signal .tb_gte_equiv.ub.REG_LC23 : signed(15 downto 0) >>;
      alias a_REG_LC31 is << signal .tb_gte_equiv.ua.REG_LC31 : signed(15 downto 0) >>;
      alias b_REG_LC31 is << signal .tb_gte_equiv.ub.REG_LC31 : signed(15 downto 0) >>;
      alias a_REG_LC32 is << signal .tb_gte_equiv.ua.REG_LC32 : signed(15 downto 0) >>;
      alias b_REG_LC32 is << signal .tb_gte_equiv.ub.REG_LC32 : signed(15 downto 0) >>;
      alias a_REG_LC33 is << signal .tb_gte_equiv.ua.REG_LC33 : signed(15 downto 0) >>;
      alias b_REG_LC33 is << signal .tb_gte_equiv.ub.REG_LC33 : signed(15 downto 0) >>;
      alias a_REG_FC0 is << signal .tb_gte_equiv.ua.REG_FC0 : unsigned(31 downto 0) >>;
      alias b_REG_FC0 is << signal .tb_gte_equiv.ub.REG_FC0 : unsigned(31 downto 0) >>;
      alias a_REG_FC1 is << signal .tb_gte_equiv.ua.REG_FC1 : unsigned(31 downto 0) >>;
      alias b_REG_FC1 is << signal .tb_gte_equiv.ub.REG_FC1 : unsigned(31 downto 0) >>;
      alias a_REG_FC2 is << signal .tb_gte_equiv.ua.REG_FC2 : unsigned(31 downto 0) >>;
      alias b_REG_FC2 is << signal .tb_gte_equiv.ub.REG_FC2 : unsigned(31 downto 0) >>;
      alias a_REG_OFX is << signal .tb_gte_equiv.ua.REG_OFX : unsigned(31 downto 0) >>;
      alias b_REG_OFX is << signal .tb_gte_equiv.ub.REG_OFX : unsigned(31 downto 0) >>;
      alias a_REG_OFY is << signal .tb_gte_equiv.ua.REG_OFY : unsigned(31 downto 0) >>;
      alias b_REG_OFY is << signal .tb_gte_equiv.ub.REG_OFY : unsigned(31 downto 0) >>;
      alias a_REG_H is << signal .tb_gte_equiv.ua.REG_H : signed(15 downto 0) >>;
      alias b_REG_H is << signal .tb_gte_equiv.ub.REG_H : signed(15 downto 0) >>;
      alias a_REG_DQA is << signal .tb_gte_equiv.ua.REG_DQA : signed(15 downto 0) >>;
      alias b_REG_DQA is << signal .tb_gte_equiv.ub.REG_DQA : signed(15 downto 0) >>;
      alias a_REG_DQB is << signal .tb_gte_equiv.ua.REG_DQB : unsigned(31 downto 0) >>;
      alias b_REG_DQB is << signal .tb_gte_equiv.ub.REG_DQB : unsigned(31 downto 0) >>;
      alias a_REG_ZSF3 is << signal .tb_gte_equiv.ua.REG_ZSF3 : signed(15 downto 0) >>;
      alias b_REG_ZSF3 is << signal .tb_gte_equiv.ub.REG_ZSF3 : signed(15 downto 0) >>;
      alias a_REG_ZSF4 is << signal .tb_gte_equiv.ua.REG_ZSF4 : signed(15 downto 0) >>;
      alias b_REG_ZSF4 is << signal .tb_gte_equiv.ub.REG_ZSF4 : signed(15 downto 0) >>;
      alias a_REG_FLAG is << signal .tb_gte_equiv.ua.REG_FLAG : unsigned(31 downto 0) >>;
      alias b_REG_FLAG is << signal .tb_gte_equiv.ub.REG_FLAG : unsigned(31 downto 0) >>;
      alias a_IR1aspect is << signal .tb_gte_equiv.ua.IR1aspect : signed(16 downto 0) >>;
      alias b_IR1aspect is << signal .tb_gte_equiv.ub.IR1aspect : signed(16 downto 0) >>;
      alias a_IR1aspect_1 is << signal .tb_gte_equiv.ua.IR1aspect_1 : signed(16 downto 0) >>;
      alias b_IR1aspect_1 is << signal .tb_gte_equiv.ub.IR1aspect_1 : signed(16 downto 0) >>;
      alias a_IR1aspect_2 is << signal .tb_gte_equiv.ua.IR1aspect_2 : signed(16 downto 0) >>;
      alias b_IR1aspect_2 is << signal .tb_gte_equiv.ub.IR1aspect_2 : signed(16 downto 0) >>;
      alias a_calcStep is << signal .tb_gte_equiv.ua.calcStep : integer >>;
      alias b_calcStep is << signal .tb_gte_equiv.ub.calcStep : integer >>;
      alias a_batchCount is << signal .tb_gte_equiv.ua.batchCount : integer >>;
      alias b_batchCount is << signal .tb_gte_equiv.ub.batchCount : integer >>;
      alias a_turbomode is << signal .tb_gte_equiv.ua.turbomode : std_logic >>;
      alias b_turbomode is << signal .tb_gte_equiv.ub.turbomode : std_logic >>;
      alias a_cmdShift is << signal .tb_gte_equiv.ua.cmdShift : std_logic >>;
      alias b_cmdShift is << signal .tb_gte_equiv.ub.cmdShift : std_logic >>;
      alias a_cmdsatIR is << signal .tb_gte_equiv.ua.cmdsatIR : std_logic >>;
      alias b_cmdsatIR is << signal .tb_gte_equiv.ub.cmdsatIR : std_logic >>;
      alias a_cmdMM is << signal .tb_gte_equiv.ua.cmdMM : unsigned(1 downto 0) >>;
      alias b_cmdMM is << signal .tb_gte_equiv.ub.cmdMM : unsigned(1 downto 0) >>;
      alias a_cmdMV is << signal .tb_gte_equiv.ua.cmdMV : unsigned(1 downto 0) >>;
      alias b_cmdMV is << signal .tb_gte_equiv.ub.cmdMV : unsigned(1 downto 0) >>;
      alias a_cmdTV is << signal .tb_gte_equiv.ua.cmdTV : unsigned(1 downto 0) >>;
      alias b_cmdTV is << signal .tb_gte_equiv.ub.cmdTV : unsigned(1 downto 0) >>;
      alias a_calcColor is << signal .tb_gte_equiv.ua.calcColor : unsigned(23 downto 0) >>;
      alias b_calcColor is << signal .tb_gte_equiv.ub.calcColor : unsigned(23 downto 0) >>;
      alias a_pushRGBfromMAC is << signal .tb_gte_equiv.ua.pushRGBfromMAC : std_logic >>;
      alias b_pushRGBfromMAC is << signal .tb_gte_equiv.ub.pushRGBfromMAC : std_logic >>;
      alias a_setOTZ is << signal .tb_gte_equiv.ua.setOTZ : std_logic >>;
      alias b_setOTZ is << signal .tb_gte_equiv.ub.setOTZ : std_logic >>;
      alias a_pushSZandDivide is << signal .tb_gte_equiv.ua.pushSZandDivide : std_logic >>;
      alias b_pushSZandDivide is << signal .tb_gte_equiv.ub.pushSZandDivide : std_logic >>;
      alias a_pushSXY is << signal .tb_gte_equiv.ua.pushSXY : std_logic >>;
      alias b_pushSXY is << signal .tb_gte_equiv.ub.pushSXY : std_logic >>;
      alias a_REG_IR2_1 is << signal .tb_gte_equiv.ua.REG_IR2_1 : signed(15 downto 0) >>;
      alias b_REG_IR2_1 is << signal .tb_gte_equiv.ub.REG_IR2_1 : signed(15 downto 0) >>;
      alias a_REG_IR2_2 is << signal .tb_gte_equiv.ua.REG_IR2_2 : signed(15 downto 0) >>;
      alias b_REG_IR2_2 is << signal .tb_gte_equiv.ub.REG_IR2_2 : signed(15 downto 0) >>;
      alias a_matrix00 is << signal .tb_gte_equiv.ua.matrix00 : signed(15 downto 0) >>;
      alias b_matrix00 is << signal .tb_gte_equiv.ub.matrix00 : signed(15 downto 0) >>;
      alias a_matrix01 is << signal .tb_gte_equiv.ua.matrix01 : signed(15 downto 0) >>;
      alias b_matrix01 is << signal .tb_gte_equiv.ub.matrix01 : signed(15 downto 0) >>;
      alias a_matrix02 is << signal .tb_gte_equiv.ua.matrix02 : signed(15 downto 0) >>;
      alias b_matrix02 is << signal .tb_gte_equiv.ub.matrix02 : signed(15 downto 0) >>;
      alias a_matrix10 is << signal .tb_gte_equiv.ua.matrix10 : signed(15 downto 0) >>;
      alias b_matrix10 is << signal .tb_gte_equiv.ub.matrix10 : signed(15 downto 0) >>;
      alias a_matrix11 is << signal .tb_gte_equiv.ua.matrix11 : signed(15 downto 0) >>;
      alias b_matrix11 is << signal .tb_gte_equiv.ub.matrix11 : signed(15 downto 0) >>;
      alias a_matrix12 is << signal .tb_gte_equiv.ua.matrix12 : signed(15 downto 0) >>;
      alias b_matrix12 is << signal .tb_gte_equiv.ub.matrix12 : signed(15 downto 0) >>;
      alias a_matrix20 is << signal .tb_gte_equiv.ua.matrix20 : signed(15 downto 0) >>;
      alias b_matrix20 is << signal .tb_gte_equiv.ub.matrix20 : signed(15 downto 0) >>;
      alias a_matrix21 is << signal .tb_gte_equiv.ua.matrix21 : signed(15 downto 0) >>;
      alias b_matrix21 is << signal .tb_gte_equiv.ub.matrix21 : signed(15 downto 0) >>;
      alias a_matrix22 is << signal .tb_gte_equiv.ua.matrix22 : signed(15 downto 0) >>;
      alias b_matrix22 is << signal .tb_gte_equiv.ub.matrix22 : signed(15 downto 0) >>;
      alias a_vector0 is << signal .tb_gte_equiv.ua.vector0 : signed(15 downto 0) >>;
      alias b_vector0 is << signal .tb_gte_equiv.ub.vector0 : signed(15 downto 0) >>;
      alias a_vector1 is << signal .tb_gte_equiv.ua.vector1 : signed(15 downto 0) >>;
      alias b_vector1 is << signal .tb_gte_equiv.ub.vector1 : signed(15 downto 0) >>;
      alias a_vector2 is << signal .tb_gte_equiv.ua.vector2 : signed(15 downto 0) >>;
      alias b_vector2 is << signal .tb_gte_equiv.ub.vector2 : signed(15 downto 0) >>;
      alias a_translate0 is << signal .tb_gte_equiv.ua.translate0 : signed(31 downto 0) >>;
      alias b_translate0 is << signal .tb_gte_equiv.ub.translate0 : signed(31 downto 0) >>;
      alias a_translate1 is << signal .tb_gte_equiv.ua.translate1 : signed(31 downto 0) >>;
      alias b_translate1 is << signal .tb_gte_equiv.ub.translate1 : signed(31 downto 0) >>;
      alias a_translate2 is << signal .tb_gte_equiv.ua.translate2 : signed(31 downto 0) >>;
      alias b_translate2 is << signal .tb_gte_equiv.ub.translate2 : signed(31 downto 0) >>;
      alias a_shiftvalue is << signal .tb_gte_equiv.ua.shiftvalue : signed(31 downto 0) >>;
      alias b_shiftvalue is << signal .tb_gte_equiv.ub.shiftvalue : signed(31 downto 0) >>;
      alias a_mac0_result is << signal .tb_gte_equiv.ua.mac0_result : signed(34 downto 0) >>;
      alias b_mac0_result is << signal .tb_gte_equiv.ub.mac0_result : signed(34 downto 0) >>;
      alias a_mac0_writeback is << signal .tb_gte_equiv.ua.mac0_writeback : std_logic >>;
      alias b_mac0_writeback is << signal .tb_gte_equiv.ub.mac0_writeback : std_logic >>;
      alias a_ir0_result is << signal .tb_gte_equiv.ua.ir0_result : signed(15 downto 0) >>;
      alias b_ir0_result is << signal .tb_gte_equiv.ub.ir0_result : signed(15 downto 0) >>;
      alias a_ir0_writeback is << signal .tb_gte_equiv.ua.ir0_writeback : std_logic >>;
      alias b_ir0_writeback is << signal .tb_gte_equiv.ub.ir0_writeback : std_logic >>;
      alias a_mac0Last is << signal .tb_gte_equiv.ua.mac0Last : signed(34 downto 0) >>;
      alias b_mac0Last is << signal .tb_gte_equiv.ub.mac0Last : signed(34 downto 0) >>;
      alias a_flagMac0UF is << signal .tb_gte_equiv.ua.flagMac0UF : std_logic >>;
      alias b_flagMac0UF is << signal .tb_gte_equiv.ub.flagMac0UF : std_logic >>;
      alias a_flagMac0OF is << signal .tb_gte_equiv.ua.flagMac0OF : std_logic >>;
      alias b_flagMac0OF is << signal .tb_gte_equiv.ub.flagMac0OF : std_logic >>;
      alias a_flagIR0 is << signal .tb_gte_equiv.ua.flagIR0 : std_logic >>;
      alias b_flagIR0 is << signal .tb_gte_equiv.ub.flagIR0 : std_logic >>;
      alias a_mac1_result is << signal .tb_gte_equiv.ua.mac1_result : signed(31 downto 0) >>;
      alias b_mac1_result is << signal .tb_gte_equiv.ub.mac1_result : signed(31 downto 0) >>;
      alias a_mac1_writeback is << signal .tb_gte_equiv.ua.mac1_writeback : std_logic >>;
      alias b_mac1_writeback is << signal .tb_gte_equiv.ub.mac1_writeback : std_logic >>;
      alias a_ir1_result is << signal .tb_gte_equiv.ua.ir1_result : signed(15 downto 0) >>;
      alias b_ir1_result is << signal .tb_gte_equiv.ub.ir1_result : signed(15 downto 0) >>;
      alias a_ir1_writeback is << signal .tb_gte_equiv.ua.ir1_writeback : std_logic >>;
      alias b_ir1_writeback is << signal .tb_gte_equiv.ub.ir1_writeback : std_logic >>;
      alias a_mac1Last is << signal .tb_gte_equiv.ua.mac1Last : signed(44 downto 0) >>;
      alias b_mac1Last is << signal .tb_gte_equiv.ub.mac1Last : signed(44 downto 0) >>;
      alias a_flagMac1UF is << signal .tb_gte_equiv.ua.flagMac1UF : std_logic >>;
      alias b_flagMac1UF is << signal .tb_gte_equiv.ub.flagMac1UF : std_logic >>;
      alias a_flagMac1OF is << signal .tb_gte_equiv.ua.flagMac1OF : std_logic >>;
      alias b_flagMac1OF is << signal .tb_gte_equiv.ub.flagMac1OF : std_logic >>;
      alias a_flagIR1 is << signal .tb_gte_equiv.ua.flagIR1 : std_logic >>;
      alias b_flagIR1 is << signal .tb_gte_equiv.ub.flagIR1 : std_logic >>;
      alias a_mac2_result is << signal .tb_gte_equiv.ua.mac2_result : signed(31 downto 0) >>;
      alias b_mac2_result is << signal .tb_gte_equiv.ub.mac2_result : signed(31 downto 0) >>;
      alias a_mac2_writeback is << signal .tb_gte_equiv.ua.mac2_writeback : std_logic >>;
      alias b_mac2_writeback is << signal .tb_gte_equiv.ub.mac2_writeback : std_logic >>;
      alias a_ir2_result is << signal .tb_gte_equiv.ua.ir2_result : signed(15 downto 0) >>;
      alias b_ir2_result is << signal .tb_gte_equiv.ub.ir2_result : signed(15 downto 0) >>;
      alias a_ir2_writeback is << signal .tb_gte_equiv.ua.ir2_writeback : std_logic >>;
      alias b_ir2_writeback is << signal .tb_gte_equiv.ub.ir2_writeback : std_logic >>;
      alias a_mac2Last is << signal .tb_gte_equiv.ua.mac2Last : signed(44 downto 0) >>;
      alias b_mac2Last is << signal .tb_gte_equiv.ub.mac2Last : signed(44 downto 0) >>;
      alias a_flagMac2UF is << signal .tb_gte_equiv.ua.flagMac2UF : std_logic >>;
      alias b_flagMac2UF is << signal .tb_gte_equiv.ub.flagMac2UF : std_logic >>;
      alias a_flagMac2OF is << signal .tb_gte_equiv.ua.flagMac2OF : std_logic >>;
      alias b_flagMac2OF is << signal .tb_gte_equiv.ub.flagMac2OF : std_logic >>;
      alias a_flagIR2 is << signal .tb_gte_equiv.ua.flagIR2 : std_logic >>;
      alias b_flagIR2 is << signal .tb_gte_equiv.ub.flagIR2 : std_logic >>;
      alias a_mac3_result is << signal .tb_gte_equiv.ua.mac3_result : signed(31 downto 0) >>;
      alias b_mac3_result is << signal .tb_gte_equiv.ub.mac3_result : signed(31 downto 0) >>;
      alias a_mac3_writeback is << signal .tb_gte_equiv.ua.mac3_writeback : std_logic >>;
      alias b_mac3_writeback is << signal .tb_gte_equiv.ub.mac3_writeback : std_logic >>;
      alias a_ir3_result is << signal .tb_gte_equiv.ua.ir3_result : signed(15 downto 0) >>;
      alias b_ir3_result is << signal .tb_gte_equiv.ub.ir3_result : signed(15 downto 0) >>;
      alias a_ir3_writeback is << signal .tb_gte_equiv.ua.ir3_writeback : std_logic >>;
      alias b_ir3_writeback is << signal .tb_gte_equiv.ub.ir3_writeback : std_logic >>;
      alias a_mac3Last is << signal .tb_gte_equiv.ua.mac3Last : signed(44 downto 0) >>;
      alias b_mac3Last is << signal .tb_gte_equiv.ub.mac3Last : signed(44 downto 0) >>;
      alias a_mac3Shifted is << signal .tb_gte_equiv.ua.mac3Shifted : signed(31 downto 0) >>;
      alias b_mac3Shifted is << signal .tb_gte_equiv.ub.mac3Shifted : signed(31 downto 0) >>;
      alias a_flagMac3UF is << signal .tb_gte_equiv.ua.flagMac3UF : std_logic >>;
      alias b_flagMac3UF is << signal .tb_gte_equiv.ub.flagMac3UF : std_logic >>;
      alias a_flagMac3OF is << signal .tb_gte_equiv.ua.flagMac3OF : std_logic >>;
      alias b_flagMac3OF is << signal .tb_gte_equiv.ub.flagMac3OF : std_logic >>;
      alias a_flagIR3 is << signal .tb_gte_equiv.ua.flagIR3 : std_logic >>;
      alias b_flagIR3 is << signal .tb_gte_equiv.ub.flagIR3 : std_logic >>;
      alias a_div_trigger is << signal .tb_gte_equiv.ua.div_trigger : std_logic >>;
      alias b_div_trigger is << signal .tb_gte_equiv.ub.div_trigger : std_logic >>;
      alias a_div_lhs is << signal .tb_gte_equiv.ua.div_lhs : unsigned(15 downto 0) >>;
      alias b_div_lhs is << signal .tb_gte_equiv.ub.div_lhs : unsigned(15 downto 0) >>;
      alias a_div_rhs is << signal .tb_gte_equiv.ua.div_rhs : unsigned(15 downto 0) >>;
      alias b_div_rhs is << signal .tb_gte_equiv.ub.div_rhs : unsigned(15 downto 0) >>;
      alias a_div_result is << signal .tb_gte_equiv.ua.div_result : unsigned(16 downto 0) >>;
      alias b_div_result is << signal .tb_gte_equiv.ub.div_result : unsigned(16 downto 0) >>;
      alias a_div_Error is << signal .tb_gte_equiv.ua.div_Error : std_logic >>;
      alias b_div_Error is << signal .tb_gte_equiv.ub.div_Error : std_logic >>;
      alias a_debugCnt is << signal .tb_gte_equiv.ua.debugCnt : unsigned(31 downto 0) >>;
      alias b_debugCnt is << signal .tb_gte_equiv.ub.debugCnt : unsigned(31 downto 0) >>;
      alias a_SSreadAddr is << signal .tb_gte_equiv.ua.SSreadAddr : unsigned(5 downto 0) >>;
      alias b_SSreadAddr is << signal .tb_gte_equiv.ub.SSreadAddr : unsigned(5 downto 0) >>;
      alias a_SSrden is << signal .tb_gte_equiv.ua.SSrden : std_logic >>;
      alias b_SSrden is << signal .tb_gte_equiv.ub.SSrden : std_logic >>;
      alias a_SS_readData is << signal .tb_gte_equiv.ua.SS_readData : std_logic_vector(31 downto 0) >>;
      alias b_SS_readData is << signal .tb_gte_equiv.ub.SS_readData : std_logic_vector(31 downto 0) >>;
      alias a_igte_mac0_mac0Result_1 is << signal .tb_gte_equiv.ua.igte_mac0.mac0Result_1 : signed(34 downto 0) >>;
      alias b_igte_mac0_mac0Result_1 is << signal .tb_gte_equiv.ub.igte_mac0.mac0Result_1 : signed(34 downto 0) >>;
      alias a_igte_mac1_macResult_1 is << signal .tb_gte_equiv.ua.igte_mac1.macResult_1 : signed(44 downto 0) >>;
      alias b_igte_mac1_macResult_1 is << signal .tb_gte_equiv.ub.igte_mac1.macResult_1 : signed(44 downto 0) >>;
      alias a_igte_mac2_macResult_1 is << signal .tb_gte_equiv.ua.igte_mac2.macResult_1 : signed(44 downto 0) >>;
      alias b_igte_mac2_macResult_1 is << signal .tb_gte_equiv.ub.igte_mac2.macResult_1 : signed(44 downto 0) >>;
      alias a_igte_mac3_macResult_1 is << signal .tb_gte_equiv.ua.igte_mac3.macResult_1 : signed(44 downto 0) >>;
      alias b_igte_mac3_macResult_1 is << signal .tb_gte_equiv.ub.igte_mac3.macResult_1 : signed(44 downto 0) >>;
   begin
      process
         variable cyc      : integer := 0;
         variable errs     : integer := 0;
         variable lastCnt  : unsigned(31 downto 0) := (others => '0');
         type tcount is array(0 to 63, 0 to 1) of integer;
         variable cnt      : tcount := (others => (others => 0));
         variable l        : line;
         variable tot      : integer;
         procedure mism(name : string; a, b : string) is
         begin
            errs := errs + 1;
            if (errs <= 20) then
               report "MISMATCH at clk2x cycle " & integer'image(cyc) & " (" & time'image(now) & "): " & name & " A=" & a & " B=" & b severity warning;
            end if;
         end procedure;
      begin
         loop
            wait until falling_edge(clk2x);
            cyc := cyc + 1;
            if (busyA /= busyB) then mism("gte_busy", std_logic'image(busyA), std_logic'image(busyB)); end if;
            if (std_logic_vector(rdA) /= std_logic_vector(rdB)) then mism("gte_readData", to_hstring(rdA), to_hstring(rdB)); end if;
            if (ssrA /= ssrB)   then mism("SS_DataRead", to_hstring(ssrA), to_hstring(ssrB)); end if;
            if (idleA /= idleB) then mism("SS_idle", std_logic'image(idleA), std_logic'image(idleB)); end if;
            if (dbgA /= dbgB)   then mism("debug_firstGTE", std_logic'image(dbgA), std_logic'image(dbgB)); end if;
            if (std_logic_vector(a_gte_writeAddr) /= std_logic_vector(b_gte_writeAddr)) then mism("gte_writeAddr", to_hstring(a_gte_writeAddr), to_hstring(b_gte_writeAddr)); end if;
            if (std_logic_vector(a_gte_writeData) /= std_logic_vector(b_gte_writeData)) then mism("gte_writeData", to_hstring(a_gte_writeData), to_hstring(b_gte_writeData)); end if;
            if (a_gte_writeEna /= b_gte_writeEna) then mism("gte_writeEna", std_logic'image(a_gte_writeEna), std_logic'image(b_gte_writeEna)); end if;
            if (std_logic_vector(a_REG_V0X) /= std_logic_vector(b_REG_V0X)) then mism("REG_V0X", to_hstring(a_REG_V0X), to_hstring(b_REG_V0X)); end if;
            if (std_logic_vector(a_REG_V0Y) /= std_logic_vector(b_REG_V0Y)) then mism("REG_V0Y", to_hstring(a_REG_V0Y), to_hstring(b_REG_V0Y)); end if;
            if (std_logic_vector(a_REG_V0Z) /= std_logic_vector(b_REG_V0Z)) then mism("REG_V0Z", to_hstring(a_REG_V0Z), to_hstring(b_REG_V0Z)); end if;
            if (std_logic_vector(a_REG_V1X) /= std_logic_vector(b_REG_V1X)) then mism("REG_V1X", to_hstring(a_REG_V1X), to_hstring(b_REG_V1X)); end if;
            if (std_logic_vector(a_REG_V1Y) /= std_logic_vector(b_REG_V1Y)) then mism("REG_V1Y", to_hstring(a_REG_V1Y), to_hstring(b_REG_V1Y)); end if;
            if (std_logic_vector(a_REG_V1Z) /= std_logic_vector(b_REG_V1Z)) then mism("REG_V1Z", to_hstring(a_REG_V1Z), to_hstring(b_REG_V1Z)); end if;
            if (std_logic_vector(a_REG_V2X) /= std_logic_vector(b_REG_V2X)) then mism("REG_V2X", to_hstring(a_REG_V2X), to_hstring(b_REG_V2X)); end if;
            if (std_logic_vector(a_REG_V2Y) /= std_logic_vector(b_REG_V2Y)) then mism("REG_V2Y", to_hstring(a_REG_V2Y), to_hstring(b_REG_V2Y)); end if;
            if (std_logic_vector(a_REG_V2Z) /= std_logic_vector(b_REG_V2Z)) then mism("REG_V2Z", to_hstring(a_REG_V2Z), to_hstring(b_REG_V2Z)); end if;
            if (std_logic_vector(a_REG_RGBC) /= std_logic_vector(b_REG_RGBC)) then mism("REG_RGBC", to_hstring(a_REG_RGBC), to_hstring(b_REG_RGBC)); end if;
            if (std_logic_vector(a_REG_OTZ) /= std_logic_vector(b_REG_OTZ)) then mism("REG_OTZ", to_hstring(a_REG_OTZ), to_hstring(b_REG_OTZ)); end if;
            if (std_logic_vector(a_REG_IR0) /= std_logic_vector(b_REG_IR0)) then mism("REG_IR0", to_hstring(a_REG_IR0), to_hstring(b_REG_IR0)); end if;
            if (std_logic_vector(a_REG_IR1) /= std_logic_vector(b_REG_IR1)) then mism("REG_IR1", to_hstring(a_REG_IR1), to_hstring(b_REG_IR1)); end if;
            if (std_logic_vector(a_REG_IR2) /= std_logic_vector(b_REG_IR2)) then mism("REG_IR2", to_hstring(a_REG_IR2), to_hstring(b_REG_IR2)); end if;
            if (std_logic_vector(a_REG_IR3) /= std_logic_vector(b_REG_IR3)) then mism("REG_IR3", to_hstring(a_REG_IR3), to_hstring(b_REG_IR3)); end if;
            if (std_logic_vector(a_REG_SX0) /= std_logic_vector(b_REG_SX0)) then mism("REG_SX0", to_hstring(a_REG_SX0), to_hstring(b_REG_SX0)); end if;
            if (std_logic_vector(a_REG_SY0) /= std_logic_vector(b_REG_SY0)) then mism("REG_SY0", to_hstring(a_REG_SY0), to_hstring(b_REG_SY0)); end if;
            if (std_logic_vector(a_REG_SX1) /= std_logic_vector(b_REG_SX1)) then mism("REG_SX1", to_hstring(a_REG_SX1), to_hstring(b_REG_SX1)); end if;
            if (std_logic_vector(a_REG_SY1) /= std_logic_vector(b_REG_SY1)) then mism("REG_SY1", to_hstring(a_REG_SY1), to_hstring(b_REG_SY1)); end if;
            if (std_logic_vector(a_REG_SX2) /= std_logic_vector(b_REG_SX2)) then mism("REG_SX2", to_hstring(a_REG_SX2), to_hstring(b_REG_SX2)); end if;
            if (std_logic_vector(a_REG_SY2) /= std_logic_vector(b_REG_SY2)) then mism("REG_SY2", to_hstring(a_REG_SY2), to_hstring(b_REG_SY2)); end if;
            if (std_logic_vector(a_REG_SZ0) /= std_logic_vector(b_REG_SZ0)) then mism("REG_SZ0", to_hstring(a_REG_SZ0), to_hstring(b_REG_SZ0)); end if;
            if (std_logic_vector(a_REG_SZ1) /= std_logic_vector(b_REG_SZ1)) then mism("REG_SZ1", to_hstring(a_REG_SZ1), to_hstring(b_REG_SZ1)); end if;
            if (std_logic_vector(a_REG_SZ2) /= std_logic_vector(b_REG_SZ2)) then mism("REG_SZ2", to_hstring(a_REG_SZ2), to_hstring(b_REG_SZ2)); end if;
            if (std_logic_vector(a_REG_SZ3) /= std_logic_vector(b_REG_SZ3)) then mism("REG_SZ3", to_hstring(a_REG_SZ3), to_hstring(b_REG_SZ3)); end if;
            if (std_logic_vector(a_REG_RGB0) /= std_logic_vector(b_REG_RGB0)) then mism("REG_RGB0", to_hstring(a_REG_RGB0), to_hstring(b_REG_RGB0)); end if;
            if (std_logic_vector(a_REG_RGB1) /= std_logic_vector(b_REG_RGB1)) then mism("REG_RGB1", to_hstring(a_REG_RGB1), to_hstring(b_REG_RGB1)); end if;
            if (std_logic_vector(a_REG_RGB2) /= std_logic_vector(b_REG_RGB2)) then mism("REG_RGB2", to_hstring(a_REG_RGB2), to_hstring(b_REG_RGB2)); end if;
            if (std_logic_vector(a_REG_RES1) /= std_logic_vector(b_REG_RES1)) then mism("REG_RES1", to_hstring(a_REG_RES1), to_hstring(b_REG_RES1)); end if;
            if (std_logic_vector(a_REG_MAC0) /= std_logic_vector(b_REG_MAC0)) then mism("REG_MAC0", to_hstring(a_REG_MAC0), to_hstring(b_REG_MAC0)); end if;
            if (std_logic_vector(a_REG_MAC1) /= std_logic_vector(b_REG_MAC1)) then mism("REG_MAC1", to_hstring(a_REG_MAC1), to_hstring(b_REG_MAC1)); end if;
            if (std_logic_vector(a_REG_MAC2) /= std_logic_vector(b_REG_MAC2)) then mism("REG_MAC2", to_hstring(a_REG_MAC2), to_hstring(b_REG_MAC2)); end if;
            if (std_logic_vector(a_REG_MAC3) /= std_logic_vector(b_REG_MAC3)) then mism("REG_MAC3", to_hstring(a_REG_MAC3), to_hstring(b_REG_MAC3)); end if;
            if (std_logic_vector(a_REG_IRGB) /= std_logic_vector(b_REG_IRGB)) then mism("REG_IRGB", to_hstring(a_REG_IRGB), to_hstring(b_REG_IRGB)); end if;
            if (std_logic_vector(a_REG_ORGB) /= std_logic_vector(b_REG_ORGB)) then mism("REG_ORGB", to_hstring(a_REG_ORGB), to_hstring(b_REG_ORGB)); end if;
            if (std_logic_vector(a_REG_LZCS) /= std_logic_vector(b_REG_LZCS)) then mism("REG_LZCS", to_hstring(a_REG_LZCS), to_hstring(b_REG_LZCS)); end if;
            if (std_logic_vector(a_REG_LZCR) /= std_logic_vector(b_REG_LZCR)) then mism("REG_LZCR", to_hstring(a_REG_LZCR), to_hstring(b_REG_LZCR)); end if;
            if (std_logic_vector(a_REG_RT11) /= std_logic_vector(b_REG_RT11)) then mism("REG_RT11", to_hstring(a_REG_RT11), to_hstring(b_REG_RT11)); end if;
            if (std_logic_vector(a_REG_RT12) /= std_logic_vector(b_REG_RT12)) then mism("REG_RT12", to_hstring(a_REG_RT12), to_hstring(b_REG_RT12)); end if;
            if (std_logic_vector(a_REG_RT13) /= std_logic_vector(b_REG_RT13)) then mism("REG_RT13", to_hstring(a_REG_RT13), to_hstring(b_REG_RT13)); end if;
            if (std_logic_vector(a_REG_RT21) /= std_logic_vector(b_REG_RT21)) then mism("REG_RT21", to_hstring(a_REG_RT21), to_hstring(b_REG_RT21)); end if;
            if (std_logic_vector(a_REG_RT22) /= std_logic_vector(b_REG_RT22)) then mism("REG_RT22", to_hstring(a_REG_RT22), to_hstring(b_REG_RT22)); end if;
            if (std_logic_vector(a_REG_RT23) /= std_logic_vector(b_REG_RT23)) then mism("REG_RT23", to_hstring(a_REG_RT23), to_hstring(b_REG_RT23)); end if;
            if (std_logic_vector(a_REG_RT31) /= std_logic_vector(b_REG_RT31)) then mism("REG_RT31", to_hstring(a_REG_RT31), to_hstring(b_REG_RT31)); end if;
            if (std_logic_vector(a_REG_RT32) /= std_logic_vector(b_REG_RT32)) then mism("REG_RT32", to_hstring(a_REG_RT32), to_hstring(b_REG_RT32)); end if;
            if (std_logic_vector(a_REG_RT33) /= std_logic_vector(b_REG_RT33)) then mism("REG_RT33", to_hstring(a_REG_RT33), to_hstring(b_REG_RT33)); end if;
            if (std_logic_vector(a_REG_TR0) /= std_logic_vector(b_REG_TR0)) then mism("REG_TR0", to_hstring(a_REG_TR0), to_hstring(b_REG_TR0)); end if;
            if (std_logic_vector(a_REG_TR1) /= std_logic_vector(b_REG_TR1)) then mism("REG_TR1", to_hstring(a_REG_TR1), to_hstring(b_REG_TR1)); end if;
            if (std_logic_vector(a_REG_TR2) /= std_logic_vector(b_REG_TR2)) then mism("REG_TR2", to_hstring(a_REG_TR2), to_hstring(b_REG_TR2)); end if;
            if (std_logic_vector(a_REG_LL11) /= std_logic_vector(b_REG_LL11)) then mism("REG_LL11", to_hstring(a_REG_LL11), to_hstring(b_REG_LL11)); end if;
            if (std_logic_vector(a_REG_LL12) /= std_logic_vector(b_REG_LL12)) then mism("REG_LL12", to_hstring(a_REG_LL12), to_hstring(b_REG_LL12)); end if;
            if (std_logic_vector(a_REG_LL13) /= std_logic_vector(b_REG_LL13)) then mism("REG_LL13", to_hstring(a_REG_LL13), to_hstring(b_REG_LL13)); end if;
            if (std_logic_vector(a_REG_LL21) /= std_logic_vector(b_REG_LL21)) then mism("REG_LL21", to_hstring(a_REG_LL21), to_hstring(b_REG_LL21)); end if;
            if (std_logic_vector(a_REG_LL22) /= std_logic_vector(b_REG_LL22)) then mism("REG_LL22", to_hstring(a_REG_LL22), to_hstring(b_REG_LL22)); end if;
            if (std_logic_vector(a_REG_LL23) /= std_logic_vector(b_REG_LL23)) then mism("REG_LL23", to_hstring(a_REG_LL23), to_hstring(b_REG_LL23)); end if;
            if (std_logic_vector(a_REG_LL31) /= std_logic_vector(b_REG_LL31)) then mism("REG_LL31", to_hstring(a_REG_LL31), to_hstring(b_REG_LL31)); end if;
            if (std_logic_vector(a_REG_LL32) /= std_logic_vector(b_REG_LL32)) then mism("REG_LL32", to_hstring(a_REG_LL32), to_hstring(b_REG_LL32)); end if;
            if (std_logic_vector(a_REG_LL33) /= std_logic_vector(b_REG_LL33)) then mism("REG_LL33", to_hstring(a_REG_LL33), to_hstring(b_REG_LL33)); end if;
            if (std_logic_vector(a_REG_BK0) /= std_logic_vector(b_REG_BK0)) then mism("REG_BK0", to_hstring(a_REG_BK0), to_hstring(b_REG_BK0)); end if;
            if (std_logic_vector(a_REG_BK1) /= std_logic_vector(b_REG_BK1)) then mism("REG_BK1", to_hstring(a_REG_BK1), to_hstring(b_REG_BK1)); end if;
            if (std_logic_vector(a_REG_BK2) /= std_logic_vector(b_REG_BK2)) then mism("REG_BK2", to_hstring(a_REG_BK2), to_hstring(b_REG_BK2)); end if;
            if (std_logic_vector(a_REG_LC11) /= std_logic_vector(b_REG_LC11)) then mism("REG_LC11", to_hstring(a_REG_LC11), to_hstring(b_REG_LC11)); end if;
            if (std_logic_vector(a_REG_LC12) /= std_logic_vector(b_REG_LC12)) then mism("REG_LC12", to_hstring(a_REG_LC12), to_hstring(b_REG_LC12)); end if;
            if (std_logic_vector(a_REG_LC13) /= std_logic_vector(b_REG_LC13)) then mism("REG_LC13", to_hstring(a_REG_LC13), to_hstring(b_REG_LC13)); end if;
            if (std_logic_vector(a_REG_LC21) /= std_logic_vector(b_REG_LC21)) then mism("REG_LC21", to_hstring(a_REG_LC21), to_hstring(b_REG_LC21)); end if;
            if (std_logic_vector(a_REG_LC22) /= std_logic_vector(b_REG_LC22)) then mism("REG_LC22", to_hstring(a_REG_LC22), to_hstring(b_REG_LC22)); end if;
            if (std_logic_vector(a_REG_LC23) /= std_logic_vector(b_REG_LC23)) then mism("REG_LC23", to_hstring(a_REG_LC23), to_hstring(b_REG_LC23)); end if;
            if (std_logic_vector(a_REG_LC31) /= std_logic_vector(b_REG_LC31)) then mism("REG_LC31", to_hstring(a_REG_LC31), to_hstring(b_REG_LC31)); end if;
            if (std_logic_vector(a_REG_LC32) /= std_logic_vector(b_REG_LC32)) then mism("REG_LC32", to_hstring(a_REG_LC32), to_hstring(b_REG_LC32)); end if;
            if (std_logic_vector(a_REG_LC33) /= std_logic_vector(b_REG_LC33)) then mism("REG_LC33", to_hstring(a_REG_LC33), to_hstring(b_REG_LC33)); end if;
            if (std_logic_vector(a_REG_FC0) /= std_logic_vector(b_REG_FC0)) then mism("REG_FC0", to_hstring(a_REG_FC0), to_hstring(b_REG_FC0)); end if;
            if (std_logic_vector(a_REG_FC1) /= std_logic_vector(b_REG_FC1)) then mism("REG_FC1", to_hstring(a_REG_FC1), to_hstring(b_REG_FC1)); end if;
            if (std_logic_vector(a_REG_FC2) /= std_logic_vector(b_REG_FC2)) then mism("REG_FC2", to_hstring(a_REG_FC2), to_hstring(b_REG_FC2)); end if;
            if (std_logic_vector(a_REG_OFX) /= std_logic_vector(b_REG_OFX)) then mism("REG_OFX", to_hstring(a_REG_OFX), to_hstring(b_REG_OFX)); end if;
            if (std_logic_vector(a_REG_OFY) /= std_logic_vector(b_REG_OFY)) then mism("REG_OFY", to_hstring(a_REG_OFY), to_hstring(b_REG_OFY)); end if;
            if (std_logic_vector(a_REG_H) /= std_logic_vector(b_REG_H)) then mism("REG_H", to_hstring(a_REG_H), to_hstring(b_REG_H)); end if;
            if (std_logic_vector(a_REG_DQA) /= std_logic_vector(b_REG_DQA)) then mism("REG_DQA", to_hstring(a_REG_DQA), to_hstring(b_REG_DQA)); end if;
            if (std_logic_vector(a_REG_DQB) /= std_logic_vector(b_REG_DQB)) then mism("REG_DQB", to_hstring(a_REG_DQB), to_hstring(b_REG_DQB)); end if;
            if (std_logic_vector(a_REG_ZSF3) /= std_logic_vector(b_REG_ZSF3)) then mism("REG_ZSF3", to_hstring(a_REG_ZSF3), to_hstring(b_REG_ZSF3)); end if;
            if (std_logic_vector(a_REG_ZSF4) /= std_logic_vector(b_REG_ZSF4)) then mism("REG_ZSF4", to_hstring(a_REG_ZSF4), to_hstring(b_REG_ZSF4)); end if;
            if (std_logic_vector(a_REG_FLAG) /= std_logic_vector(b_REG_FLAG)) then mism("REG_FLAG", to_hstring(a_REG_FLAG), to_hstring(b_REG_FLAG)); end if;
            if (std_logic_vector(a_IR1aspect) /= std_logic_vector(b_IR1aspect)) then mism("IR1aspect", to_hstring(a_IR1aspect), to_hstring(b_IR1aspect)); end if;
            if (std_logic_vector(a_IR1aspect_1) /= std_logic_vector(b_IR1aspect_1)) then mism("IR1aspect_1", to_hstring(a_IR1aspect_1), to_hstring(b_IR1aspect_1)); end if;
            if (std_logic_vector(a_IR1aspect_2) /= std_logic_vector(b_IR1aspect_2)) then mism("IR1aspect_2", to_hstring(a_IR1aspect_2), to_hstring(b_IR1aspect_2)); end if;
            if (a_calcStep /= b_calcStep) then mism("calcStep", integer'image(a_calcStep), integer'image(b_calcStep)); end if;
            if (a_batchCount /= b_batchCount) then mism("batchCount", integer'image(a_batchCount), integer'image(b_batchCount)); end if;
            if (a_turbomode /= b_turbomode) then mism("turbomode", std_logic'image(a_turbomode), std_logic'image(b_turbomode)); end if;
            if (a_cmdShift /= b_cmdShift) then mism("cmdShift", std_logic'image(a_cmdShift), std_logic'image(b_cmdShift)); end if;
            if (a_cmdsatIR /= b_cmdsatIR) then mism("cmdsatIR", std_logic'image(a_cmdsatIR), std_logic'image(b_cmdsatIR)); end if;
            if (std_logic_vector(a_cmdMM) /= std_logic_vector(b_cmdMM)) then mism("cmdMM", to_hstring(a_cmdMM), to_hstring(b_cmdMM)); end if;
            if (std_logic_vector(a_cmdMV) /= std_logic_vector(b_cmdMV)) then mism("cmdMV", to_hstring(a_cmdMV), to_hstring(b_cmdMV)); end if;
            if (std_logic_vector(a_cmdTV) /= std_logic_vector(b_cmdTV)) then mism("cmdTV", to_hstring(a_cmdTV), to_hstring(b_cmdTV)); end if;
            if (std_logic_vector(a_calcColor) /= std_logic_vector(b_calcColor)) then mism("calcColor", to_hstring(a_calcColor), to_hstring(b_calcColor)); end if;
            if (a_pushRGBfromMAC /= b_pushRGBfromMAC) then mism("pushRGBfromMAC", std_logic'image(a_pushRGBfromMAC), std_logic'image(b_pushRGBfromMAC)); end if;
            if (a_setOTZ /= b_setOTZ) then mism("setOTZ", std_logic'image(a_setOTZ), std_logic'image(b_setOTZ)); end if;
            if (a_pushSZandDivide /= b_pushSZandDivide) then mism("pushSZandDivide", std_logic'image(a_pushSZandDivide), std_logic'image(b_pushSZandDivide)); end if;
            if (a_pushSXY /= b_pushSXY) then mism("pushSXY", std_logic'image(a_pushSXY), std_logic'image(b_pushSXY)); end if;
            if (std_logic_vector(a_REG_IR2_1) /= std_logic_vector(b_REG_IR2_1)) then mism("REG_IR2_1", to_hstring(a_REG_IR2_1), to_hstring(b_REG_IR2_1)); end if;
            if (std_logic_vector(a_REG_IR2_2) /= std_logic_vector(b_REG_IR2_2)) then mism("REG_IR2_2", to_hstring(a_REG_IR2_2), to_hstring(b_REG_IR2_2)); end if;
            if (std_logic_vector(a_matrix00) /= std_logic_vector(b_matrix00)) then mism("matrix00", to_hstring(a_matrix00), to_hstring(b_matrix00)); end if;
            if (std_logic_vector(a_matrix01) /= std_logic_vector(b_matrix01)) then mism("matrix01", to_hstring(a_matrix01), to_hstring(b_matrix01)); end if;
            if (std_logic_vector(a_matrix02) /= std_logic_vector(b_matrix02)) then mism("matrix02", to_hstring(a_matrix02), to_hstring(b_matrix02)); end if;
            if (std_logic_vector(a_matrix10) /= std_logic_vector(b_matrix10)) then mism("matrix10", to_hstring(a_matrix10), to_hstring(b_matrix10)); end if;
            if (std_logic_vector(a_matrix11) /= std_logic_vector(b_matrix11)) then mism("matrix11", to_hstring(a_matrix11), to_hstring(b_matrix11)); end if;
            if (std_logic_vector(a_matrix12) /= std_logic_vector(b_matrix12)) then mism("matrix12", to_hstring(a_matrix12), to_hstring(b_matrix12)); end if;
            if (std_logic_vector(a_matrix20) /= std_logic_vector(b_matrix20)) then mism("matrix20", to_hstring(a_matrix20), to_hstring(b_matrix20)); end if;
            if (std_logic_vector(a_matrix21) /= std_logic_vector(b_matrix21)) then mism("matrix21", to_hstring(a_matrix21), to_hstring(b_matrix21)); end if;
            if (std_logic_vector(a_matrix22) /= std_logic_vector(b_matrix22)) then mism("matrix22", to_hstring(a_matrix22), to_hstring(b_matrix22)); end if;
            if (std_logic_vector(a_vector0) /= std_logic_vector(b_vector0)) then mism("vector0", to_hstring(a_vector0), to_hstring(b_vector0)); end if;
            if (std_logic_vector(a_vector1) /= std_logic_vector(b_vector1)) then mism("vector1", to_hstring(a_vector1), to_hstring(b_vector1)); end if;
            if (std_logic_vector(a_vector2) /= std_logic_vector(b_vector2)) then mism("vector2", to_hstring(a_vector2), to_hstring(b_vector2)); end if;
            if (std_logic_vector(a_translate0) /= std_logic_vector(b_translate0)) then mism("translate0", to_hstring(a_translate0), to_hstring(b_translate0)); end if;
            if (std_logic_vector(a_translate1) /= std_logic_vector(b_translate1)) then mism("translate1", to_hstring(a_translate1), to_hstring(b_translate1)); end if;
            if (std_logic_vector(a_translate2) /= std_logic_vector(b_translate2)) then mism("translate2", to_hstring(a_translate2), to_hstring(b_translate2)); end if;
            if (std_logic_vector(a_shiftvalue) /= std_logic_vector(b_shiftvalue)) then mism("shiftvalue", to_hstring(a_shiftvalue), to_hstring(b_shiftvalue)); end if;
            if (std_logic_vector(a_mac0_result) /= std_logic_vector(b_mac0_result)) then mism("mac0_result", to_hstring(a_mac0_result), to_hstring(b_mac0_result)); end if;
            if (a_mac0_writeback /= b_mac0_writeback) then mism("mac0_writeback", std_logic'image(a_mac0_writeback), std_logic'image(b_mac0_writeback)); end if;
            if (std_logic_vector(a_ir0_result) /= std_logic_vector(b_ir0_result)) then mism("ir0_result", to_hstring(a_ir0_result), to_hstring(b_ir0_result)); end if;
            if (a_ir0_writeback /= b_ir0_writeback) then mism("ir0_writeback", std_logic'image(a_ir0_writeback), std_logic'image(b_ir0_writeback)); end if;
            if (std_logic_vector(a_mac0Last) /= std_logic_vector(b_mac0Last)) then mism("mac0Last", to_hstring(a_mac0Last), to_hstring(b_mac0Last)); end if;
            if (a_flagMac0UF /= b_flagMac0UF) then mism("flagMac0UF", std_logic'image(a_flagMac0UF), std_logic'image(b_flagMac0UF)); end if;
            if (a_flagMac0OF /= b_flagMac0OF) then mism("flagMac0OF", std_logic'image(a_flagMac0OF), std_logic'image(b_flagMac0OF)); end if;
            if (a_flagIR0 /= b_flagIR0) then mism("flagIR0", std_logic'image(a_flagIR0), std_logic'image(b_flagIR0)); end if;
            if (std_logic_vector(a_mac1_result) /= std_logic_vector(b_mac1_result)) then mism("mac1_result", to_hstring(a_mac1_result), to_hstring(b_mac1_result)); end if;
            if (a_mac1_writeback /= b_mac1_writeback) then mism("mac1_writeback", std_logic'image(a_mac1_writeback), std_logic'image(b_mac1_writeback)); end if;
            if (std_logic_vector(a_ir1_result) /= std_logic_vector(b_ir1_result)) then mism("ir1_result", to_hstring(a_ir1_result), to_hstring(b_ir1_result)); end if;
            if (a_ir1_writeback /= b_ir1_writeback) then mism("ir1_writeback", std_logic'image(a_ir1_writeback), std_logic'image(b_ir1_writeback)); end if;
            if (std_logic_vector(a_mac1Last) /= std_logic_vector(b_mac1Last)) then mism("mac1Last", to_hstring(a_mac1Last), to_hstring(b_mac1Last)); end if;
            if (a_flagMac1UF /= b_flagMac1UF) then mism("flagMac1UF", std_logic'image(a_flagMac1UF), std_logic'image(b_flagMac1UF)); end if;
            if (a_flagMac1OF /= b_flagMac1OF) then mism("flagMac1OF", std_logic'image(a_flagMac1OF), std_logic'image(b_flagMac1OF)); end if;
            if (a_flagIR1 /= b_flagIR1) then mism("flagIR1", std_logic'image(a_flagIR1), std_logic'image(b_flagIR1)); end if;
            if (std_logic_vector(a_mac2_result) /= std_logic_vector(b_mac2_result)) then mism("mac2_result", to_hstring(a_mac2_result), to_hstring(b_mac2_result)); end if;
            if (a_mac2_writeback /= b_mac2_writeback) then mism("mac2_writeback", std_logic'image(a_mac2_writeback), std_logic'image(b_mac2_writeback)); end if;
            if (std_logic_vector(a_ir2_result) /= std_logic_vector(b_ir2_result)) then mism("ir2_result", to_hstring(a_ir2_result), to_hstring(b_ir2_result)); end if;
            if (a_ir2_writeback /= b_ir2_writeback) then mism("ir2_writeback", std_logic'image(a_ir2_writeback), std_logic'image(b_ir2_writeback)); end if;
            if (std_logic_vector(a_mac2Last) /= std_logic_vector(b_mac2Last)) then mism("mac2Last", to_hstring(a_mac2Last), to_hstring(b_mac2Last)); end if;
            if (a_flagMac2UF /= b_flagMac2UF) then mism("flagMac2UF", std_logic'image(a_flagMac2UF), std_logic'image(b_flagMac2UF)); end if;
            if (a_flagMac2OF /= b_flagMac2OF) then mism("flagMac2OF", std_logic'image(a_flagMac2OF), std_logic'image(b_flagMac2OF)); end if;
            if (a_flagIR2 /= b_flagIR2) then mism("flagIR2", std_logic'image(a_flagIR2), std_logic'image(b_flagIR2)); end if;
            if (std_logic_vector(a_mac3_result) /= std_logic_vector(b_mac3_result)) then mism("mac3_result", to_hstring(a_mac3_result), to_hstring(b_mac3_result)); end if;
            if (a_mac3_writeback /= b_mac3_writeback) then mism("mac3_writeback", std_logic'image(a_mac3_writeback), std_logic'image(b_mac3_writeback)); end if;
            if (std_logic_vector(a_ir3_result) /= std_logic_vector(b_ir3_result)) then mism("ir3_result", to_hstring(a_ir3_result), to_hstring(b_ir3_result)); end if;
            if (a_ir3_writeback /= b_ir3_writeback) then mism("ir3_writeback", std_logic'image(a_ir3_writeback), std_logic'image(b_ir3_writeback)); end if;
            if (std_logic_vector(a_mac3Last) /= std_logic_vector(b_mac3Last)) then mism("mac3Last", to_hstring(a_mac3Last), to_hstring(b_mac3Last)); end if;
            if (std_logic_vector(a_mac3Shifted) /= std_logic_vector(b_mac3Shifted)) then mism("mac3Shifted", to_hstring(a_mac3Shifted), to_hstring(b_mac3Shifted)); end if;
            if (a_flagMac3UF /= b_flagMac3UF) then mism("flagMac3UF", std_logic'image(a_flagMac3UF), std_logic'image(b_flagMac3UF)); end if;
            if (a_flagMac3OF /= b_flagMac3OF) then mism("flagMac3OF", std_logic'image(a_flagMac3OF), std_logic'image(b_flagMac3OF)); end if;
            if (a_flagIR3 /= b_flagIR3) then mism("flagIR3", std_logic'image(a_flagIR3), std_logic'image(b_flagIR3)); end if;
            if (a_div_trigger /= b_div_trigger) then mism("div_trigger", std_logic'image(a_div_trigger), std_logic'image(b_div_trigger)); end if;
            if (std_logic_vector(a_div_lhs) /= std_logic_vector(b_div_lhs)) then mism("div_lhs", to_hstring(a_div_lhs), to_hstring(b_div_lhs)); end if;
            if (std_logic_vector(a_div_rhs) /= std_logic_vector(b_div_rhs)) then mism("div_rhs", to_hstring(a_div_rhs), to_hstring(b_div_rhs)); end if;
            if (std_logic_vector(a_div_result) /= std_logic_vector(b_div_result)) then mism("div_result", to_hstring(a_div_result), to_hstring(b_div_result)); end if;
            if (a_div_Error /= b_div_Error) then mism("div_Error", std_logic'image(a_div_Error), std_logic'image(b_div_Error)); end if;
            if (std_logic_vector(a_debugCnt) /= std_logic_vector(b_debugCnt)) then mism("debugCnt", to_hstring(a_debugCnt), to_hstring(b_debugCnt)); end if;
            if (std_logic_vector(a_SSreadAddr) /= std_logic_vector(b_SSreadAddr)) then mism("SSreadAddr", to_hstring(a_SSreadAddr), to_hstring(b_SSreadAddr)); end if;
            if (a_SSrden /= b_SSrden) then mism("SSrden", std_logic'image(a_SSrden), std_logic'image(b_SSrden)); end if;
            if (a_SS_readData /= b_SS_readData) then mism("SS_readData", to_hstring(a_SS_readData), to_hstring(b_SS_readData)); end if;
            if (std_logic_vector(a_igte_mac0_mac0Result_1) /= std_logic_vector(b_igte_mac0_mac0Result_1)) then mism("igte_mac0.mac0Result_1", to_hstring(a_igte_mac0_mac0Result_1), to_hstring(b_igte_mac0_mac0Result_1)); end if;
            if (std_logic_vector(a_igte_mac1_macResult_1) /= std_logic_vector(b_igte_mac1_macResult_1)) then mism("igte_mac1.macResult_1", to_hstring(a_igte_mac1_macResult_1), to_hstring(b_igte_mac1_macResult_1)); end if;
            if (std_logic_vector(a_igte_mac2_macResult_1) /= std_logic_vector(b_igte_mac2_macResult_1)) then mism("igte_mac2.macResult_1", to_hstring(a_igte_mac2_macResult_1), to_hstring(b_igte_mac2_macResult_1)); end if;
            if (std_logic_vector(a_igte_mac3_macResult_1) /= std_logic_vector(b_igte_mac3_macResult_1)) then mism("igte_mac3.macResult_1", to_hstring(a_igte_mac3_macResult_1), to_hstring(b_igte_mac3_macResult_1)); end if;
            -- coverage: commands taken (debugCnt counts every command the IDLE state takes)
            if (a_debugCnt /= lastCnt and not is_x(std_logic_vector(a_debugCnt))) then
               if (a_turbomode = '1') then
                  cnt(to_integer(cmdAtEdge(5 downto 0)), 1) := cnt(to_integer(cmdAtEdge(5 downto 0)), 1) + 1;
               else
                  cnt(to_integer(cmdAtEdge(5 downto 0)), 0) := cnt(to_integer(cmdAtEdge(5 downto 0)), 0) + 1;
               end if;
               lastCnt := a_debugCnt;
            end if;
            if (errs > 0 or done) then
               tot := 0;
               write(l, string'("commands taken (opcode: turbo off/on):"));
               for i in 0 to 63 loop
                  if (cnt(i, 0) + cnt(i, 1) > 0) then
                     write(l, string'(" ") & to_hstring(to_unsigned(i, 8)) & ":" & integer'image(cnt(i, 0)) & "/" & integer'image(cnt(i, 1)));
                     tot := tot + cnt(i, 0) + cnt(i, 1);
                  end if;
               end loop;
               writeline(output, l);
               write(l, string'("DONE NA=") & integer'image(NA) & " NB=" & integer'image(NB) & " SEED=" & integer'image(SEED) &
                        " clk2x_cycles=" & integer'image(cyc) & " commands=" & integer'image(tot) &
                        " ce_low_events=" & integer'image(nCeLow) & " resets=" & integer'image(nReset) & " savestate_loads=" & integer'image(nSS) &
                        " mismatches=" & integer'image(errs));
               writeline(output, l);
               std.env.finish;
            end if;
         end loop;
      end process;
   end block;

end architecture;
