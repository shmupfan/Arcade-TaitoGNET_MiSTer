-- Equivalence testbench: upstream memorymux (main) against this branch's
-- memorymux with ZN2_MAP = 0, same pseudo-random CPU stimulus, every output
-- compared every clock. Regions: RAM, BIOS (data and instruction fetch),
-- scratch internal registers, GPU/MDEC/DMA/timers/IRQ/SIO/pad, SPU, CD,
-- expansion 1, 2 and 3 (including the ZN-2 range 0x1FA00000-0x1FBFFFFF,
-- which ZN2_MAP = 0 must still treat as upstream does), random sizes,
-- byte masks, bus configurations and ce gaps while idle.
-- AVAR = 3, BVAR = 2: the previous ZN-2 memorymux against this one, both
-- with ZN2_MAP = 1 (zn_* port in the compared outputs, same device model);
-- with OVERLAP = 1 they must differ. With OVERLAP = 0 the only differences
-- allowed are those of the posted-write address fix: the word address of a
-- write request (the reference sends a posted write's later steps to the
-- CPU's next address) and, from there, read data of the device bytes that
-- write reached or missed. Every other output must be equal in every cycle
-- (obs_core), and the bench counts the misdirected write requests.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_memorymux_eq is
   generic
   (
      N    : integer := 20000;
      SEED : integer := 1;
      BVAR : integer := 1;    -- 2 = compare against ZN2_MAP = 1 (sensitivity check: must differ)
      AVAR : integer := 0;    -- 3 = reference is the previous ZN-2 memorymux (memorymux_prev)
      OVERLAP : integer := 0; -- B's ZN2_READ_OVERLAP (BVAR = 2)
      ALLOW_WADDR : integer := 0  -- 1: pass when only write request addresses and the read data they cause differ
   );
end entity;

architecture sim of tb_memorymux_eq is
   signal clk1x, clk2x  : std_logic := '0';
   signal ce            : std_logic := '1';
   signal reset         : std_logic := '1';
   signal req, rnw, isData, isCache : std_logic := '0';
   signal addrI, addrD  : unsigned(31 downto 0) := (others => '0');
   signal reqsize       : unsigned(1 downto 0) := "10";
   signal wmask         : std_logic_vector(3 downto 0) := "1111";
   signal wdata         : std_logic_vector(31 downto 0) := (others => '0');
   signal ex1, ex2, ex3, spu, cd, bios : unsigned(13 downto 0) := (others => '0');
   signal c0, c1, c2, c3 : unsigned(3 downto 0) := (others => '0');
   signal rdA, rdB      : std_logic_vector(31 downto 0);
   signal doneA, doneB, fullA, fullB, idleA, idleB : std_logic;
   signal obsA, obsB    : std_logic_vector(511 downto 0);
   signal coreA, coreB  : std_logic_vector(511 downto 0);
   signal lvA, lvB, lweA, lweB : std_logic;
   signal laA, laB      : unsigned(23 downto 0);
   signal lbA, lbB      : std_logic_vector(3 downto 0);
   signal ldA, ldB      : std_logic_vector(31 downto 0);
   signal mism_core     : integer := 0;
   signal wr_addr_diff, req_other_diff, rd_diff : integer := 0;
   signal finished      : boolean := false;
   signal mism          : integer := 0;
   signal peek          : unsigned(15 downto 0) := (others => '0');
begin
   clk2x <= not clk2x after 5 ns when not finished;
   process (clk2x) begin if rising_edge(clk2x) then clk1x <= not clk1x; end if; end process;

   A : entity work.mm_harness generic map (VARIANT => AVAR)
   port map (clk1x => clk1x, clk2x => clk2x, ce => ce, reset => reset,
      mem_in_request => req, mem_in_rnw => rnw, mem_in_isData => isData, mem_in_isCache => isCache,
      mem_in_addressInstr => addrI, mem_in_addressData => addrD, mem_in_reqsize => reqsize,
      mem_in_writeMask => wmask, mem_in_dataWrite => wdata,
      ex1_memctrl => ex1, ex2_memctrl => ex2, ex3_memctrl => ex3, spu_memctrl => spu, cd_memctrl => cd, bios_memctrl => bios,
      com0_delay => c0, com1_delay => c1, com2_delay => c2, com3_delay => c3,
      mem_dataRead => rdA, mem_done => doneA, mem_fifofull => fullA, isIdle => idleA, obs => obsA, obs_core => coreA,
      zn_log_valid => lvA, zn_log_we => lweA, zn_log_addr => laA, zn_log_be => lbA, zn_log_data => ldA,
      zn_dev_peek_addr => peek, zn_dev_peek => open);

   B : entity work.mm_harness generic map (VARIANT => BVAR, OVERLAP => OVERLAP)
   port map (clk1x => clk1x, clk2x => clk2x, ce => ce, reset => reset,
      mem_in_request => req, mem_in_rnw => rnw, mem_in_isData => isData, mem_in_isCache => isCache,
      mem_in_addressInstr => addrI, mem_in_addressData => addrD, mem_in_reqsize => reqsize,
      mem_in_writeMask => wmask, mem_in_dataWrite => wdata,
      ex1_memctrl => ex1, ex2_memctrl => ex2, ex3_memctrl => ex3, spu_memctrl => spu, cd_memctrl => cd, bios_memctrl => bios,
      com0_delay => c0, com1_delay => c1, com2_delay => c2, com3_delay => c3,
      mem_dataRead => rdB, mem_done => doneB, mem_fifofull => fullB, isIdle => idleB, obs => obsB, obs_core => coreB,
      zn_log_valid => lvB, zn_log_we => lweB, zn_log_addr => laB, zn_log_be => lbB, zn_log_data => ldB,
      zn_dev_peek_addr => peek, zn_dev_peek => open);

   -- compare every clk1x edge after reset
   process (clk1x)
   begin
      if rising_edge(clk1x) and reset = '0' then
         if obsA /= obsB then
            if mism < 5 then
               report "output mismatch at " & time'image(now) severity warning;
            end if;
            mism <= mism + 1;
         end if;
         if coreA /= coreB then
            mism_core <= mism_core + 1;
         end if;
         -- device requests (A and B issue them in the same cycles when the
         -- core outputs agree): write requests that differ in the address only
         if lvA = '1' and lvB = '1' then
            if lweA = '1' and lweB = '1' and lbA = lbB and ldA = ldB and laA /= laB then
               wr_addr_diff <= wr_addr_diff + 1;
               if wr_addr_diff < 3 then
                  report "write request address: reference " & to_hstring(laA) & " this " & to_hstring(laB) & " at " & time'image(now) severity note;
               end if;
            elsif lweA /= lweB or lbA /= lbB or laA /= laB or (lweA = '1' and ldA /= ldB) then
               req_other_diff <= req_other_diff + 1;
            end if;
         elsif lvA /= lvB then
            req_other_diff <= req_other_diff + 1;
         end if;
         if doneA = '1' and doneB = '1' and rdA /= rdB then
            rd_diff <= rd_diff + 1;
         end if;
      end if;
   end process;

   process
      variable lfsr : unsigned(31 downto 0) := to_unsigned(16#1234567# + SEED * 7919, 32);
      impure function rnd(m : integer) return integer is
      begin
         for i in 0 to 7 loop
            lfsr := lfsr(30 downto 0) & (lfsr(31) xor lfsr(21) xor lfsr(1) xor lfsr(0));
         end loop;
         return to_integer(lfsr(30 downto 8)) mod m;
      end function;
      variable region, sz, off : integer;
      variable a : unsigned(31 downto 0);
      variable nreads, nwrites, timeout : integer := 0;
      variable seg : unsigned(2 downto 0);
   begin
      for i in 0 to 9 loop wait until rising_edge(clk1x); end loop;
      reset <= '0';
      for i in 0 to 3 loop wait until rising_edge(clk1x); end loop;
      for k in 1 to N loop
         -- occasional bus configuration changes
         if rnd(50) = 0 then
            ex1 <= to_unsigned(rnd(16384), 14); ex2 <= to_unsigned(rnd(16384), 14); ex3 <= to_unsigned(rnd(16384), 14);
            spu <= to_unsigned(rnd(16384), 14); cd  <= to_unsigned(rnd(16384), 14); bios <= to_unsigned(rnd(16384), 14);
            c0 <= to_unsigned(rnd(16), 4); c1 <= to_unsigned(rnd(16), 4); c2 <= to_unsigned(rnd(16), 4); c3 <= to_unsigned(rnd(16), 4);
         end if;
         region := rnd(12);
         case region is
            when 0      => a := to_unsigned(rnd(16#800000#), 32);                   -- RAM
            when 1      => a := to_unsigned(16#1FC00000# + rnd(16#80000#), 32);     -- BIOS
            when 2      => a := to_unsigned(16#1F801000# + rnd(16#140#), 32);       -- memctrl .. timers
            when 3      => a := to_unsigned(16#1F801810# + rnd(16#20#), 32);        -- GPU, MDEC
            when 4      => a := to_unsigned(16#1F801C00# + rnd(16#200#), 32);       -- SPU
            when 5      => a := to_unsigned(16#1F801800# + rnd(4), 32);             -- CD
            when 6      => a := to_unsigned(16#1F000000# + rnd(16#800000#), 32);    -- exp1
            when 7      => a := to_unsigned(16#1F802000# + rnd(16#2000#), 32);      -- exp2
            when 8      => a := to_unsigned(16#1FA00000#, 32);                      -- exp3 (PS1)
            when 9      => a := to_unsigned(16#1FA00000# + rnd(16#200000#), 32);    -- ZN-2 range
            when 10     => a := to_unsigned(16#1FB40000# + rnd(16#40#), 32);        -- ZN-2 control area
            when others => a := to_unsigned(rnd(16#200000#), 32);                   -- RAM low
         end case;
         -- KUSEG, KSEG0 or KSEG1 view
         seg := to_unsigned(rnd(3), 3);
         if seg = 1 then a(31) := '1'; elsif seg = 2 then a(31 downto 29) := "101"; end if;
         sz := rnd(3);
         if sz = 0 then
            reqsize <= "00"; off := to_integer(a(1 downto 0));
            wmask <= (others => '0'); wmask(off) <= '1';
         elsif sz = 1 then
            reqsize <= "01"; a(0) := '0'; off := to_integer(a(1 downto 0));
            if off = 0 then wmask <= "0011"; else wmask <= "1100"; end if;
         else
            reqsize <= "10"; a(1 downto 0) := "00"; wmask <= "1111";
         end if;
         wdata <= std_logic_vector(to_unsigned(rnd(16#7FFFFF#), 24)) & std_logic_vector(to_unsigned(rnd(256), 8));
         isCache <= '0';
         if (region = 0 or region = 1 or region = 11) and rnd(4) = 0 then
            -- instruction fetch
            isData <= '0'; rnw <= '1'; a(1 downto 0) := "00"; reqsize <= "10";
            if region /= 1 and rnd(2) = 0 then isCache <= '1'; end if;
         else
            isData <= '1';
            if region = 1 then rnw <= '1'; else
               if rnd(2) = 0 then rnw <= '1'; else rnw <= '0'; end if;
            end if;
         end if;
         addrD <= a; addrI <= a;
         -- ce gaps (PSX_MiSTer lowers ce only when paused, and pauses only
         -- when memorymux is idle; a gap while a RAM handshake is pending
         -- would lose ram_done in upstream too)
         if rnd(10) = 0 and idleA = '1' then ce <= '0'; wait until rising_edge(clk1x); ce <= '1'; end if;
         req <= '1';
         wait until rising_edge(clk1x);
         req <= '0';
         if rnw = '1' then
            nreads := nreads + 1;
            timeout := 0;
            while doneA /= '1' loop
               wait until rising_edge(clk1x);
               timeout := timeout + 1;
               assert timeout < 10000 report "read timeout at request " & integer'image(k) & " addr " & to_hstring(addrD) &
                  " isData " & std_logic'image(isData) & " size " & to_hstring(reqsize) & " B done " & std_logic'image(doneB) severity failure;
            end loop;
            ce <= '1';
         else
            nwrites := nwrites + 1;
            wait until rising_edge(clk1x);
            while fullA = '1' loop wait until rising_edge(clk1x); end loop;
         end if;
      end loop;
      -- drain
      for i in 0 to 200 loop wait until rising_edge(clk1x); end loop;
      report "memorymux equivalence: " & integer'image(nreads) & " reads, " & integer'image(nwrites) &
             " writes, cycles with any output differing: " & integer'image(mism);
      report "  cycles with outputs other than read data and zn_addr differing: " & integer'image(mism_core) &
             "; write requests differing in the address only: " & integer'image(wr_addr_diff) &
             "; other request differences: " & integer'image(req_other_diff) &
             "; reads returning different data: " & integer'image(rd_diff);
      if ALLOW_WADDR = 0 then
         assert mism = 0 report "variant " & integer'image(BVAR) & " differs from reference variant " & integer'image(AVAR) severity failure;
      else
         assert mism_core = 0 and req_other_diff = 0
            report "differences beyond the posted-write address fix" severity failure;
      end if;
      report "memorymux equivalence PASSED";
      finished <= true;
      wait;
   end process;
end architecture;
