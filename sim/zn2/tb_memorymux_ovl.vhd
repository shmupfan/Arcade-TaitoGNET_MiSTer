-- ZN2_READ_OVERLAP transaction check (docs/r1_cpu_domain_design.md, read
-- overlap): the previous ZN-2 memorymux (mm_harness VARIANT 3) and this one
-- with ZN2_READ_OVERLAP = OVERLAP (VARIANT 2) get the same pseudo-random
-- accesses, one at a time (each waits until both have finished it), with
-- the same device model and latency sequence. Checked: the data of every
-- read, and the sequence of requests the device sees (write enable, word
-- address, byte enables, write data). Timing may differ, nothing else.
-- Stimulus: expansion 1 and 3 (the ZN-2 ranges) at Taito's bus settings
-- and at random ones, random COM delays, random sizes, some RAM accesses
-- between, ce gaps during stalled reads. After an expansion write the
-- bench waits until all its steps are out: the previous memorymux takes a
-- posted write's later steps from the CPU's current address (the bug the
-- posted-write address fix removes, docs/r1_cpu_domain_design.md; the
-- prev bench counts it).

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_memorymux_ovl is
   generic
   (
      N       : integer := 20000;
      SEED    : integer := 1;
      OVERLAP : integer := 1
   );
end entity;

architecture sim of tb_memorymux_ovl is
   signal clk1x, clk2x  : std_logic := '0';
   signal ce            : std_logic := '1';
   signal reset         : std_logic := '1';
   signal req, rnw, isData, isCache : std_logic := '0';
   signal addrD         : unsigned(31 downto 0) := (others => '0');
   signal reqsize       : unsigned(1 downto 0) := "10";
   signal wmask         : std_logic_vector(3 downto 0) := "1111";
   signal wdata         : std_logic_vector(31 downto 0) := (others => '0');
   signal ex1, ex3      : unsigned(13 downto 0) := (others => '0');
   signal c0, c1, c2, c3 : unsigned(3 downto 0) := (others => '0');
   signal rdA, rdB      : std_logic_vector(31 downto 0);
   signal doneA, doneB, fullA, fullB, idleA, idleB : std_logic;
   signal lvA, lweA, lvB, lweB : std_logic;
   signal laA, laB      : unsigned(23 downto 0);
   signal lbA, lbB      : std_logic_vector(3 downto 0);
   signal ldA, ldB      : std_logic_vector(31 downto 0);
   signal peek          : unsigned(15 downto 0) := (others => '0');
   signal finished      : boolean := false;
   signal stop_log      : boolean := false;
   signal log_errors    : integer := 0;
   signal log_count     : integer := 0;
begin
   clk2x <= not clk2x after 5 ns when not finished;
   process (clk2x) begin if rising_edge(clk2x) then clk1x <= not clk1x; end if; end process;

   A : entity work.mm_harness generic map (VARIANT => 3, SEED => SEED)
   port map (clk1x => clk1x, clk2x => clk2x, ce => ce, reset => reset,
      mem_in_request => req, mem_in_rnw => rnw, mem_in_isData => isData, mem_in_isCache => isCache,
      mem_in_addressInstr => addrD, mem_in_addressData => addrD, mem_in_reqsize => reqsize,
      mem_in_writeMask => wmask, mem_in_dataWrite => wdata,
      ex1_memctrl => ex1, ex2_memctrl => (others => '0'), ex3_memctrl => ex3, spu_memctrl => (others => '0'),
      cd_memctrl => (others => '0'), bios_memctrl => (others => '0'),
      com0_delay => c0, com1_delay => c1, com2_delay => c2, com3_delay => c3,
      mem_dataRead => rdA, mem_done => doneA, mem_fifofull => fullA, isIdle => idleA, obs => open,
      zn_log_valid => lvA, zn_log_we => lweA, zn_log_addr => laA, zn_log_be => lbA, zn_log_data => ldA,
      zn_dev_peek_addr => peek, zn_dev_peek => open);

   B : entity work.mm_harness generic map (VARIANT => 2, SEED => SEED, OVERLAP => OVERLAP)
   port map (clk1x => clk1x, clk2x => clk2x, ce => ce, reset => reset,
      mem_in_request => req, mem_in_rnw => rnw, mem_in_isData => isData, mem_in_isCache => isCache,
      mem_in_addressInstr => addrD, mem_in_addressData => addrD, mem_in_reqsize => reqsize,
      mem_in_writeMask => wmask, mem_in_dataWrite => wdata,
      ex1_memctrl => ex1, ex2_memctrl => (others => '0'), ex3_memctrl => ex3, spu_memctrl => (others => '0'),
      cd_memctrl => (others => '0'), bios_memctrl => (others => '0'),
      com0_delay => c0, com1_delay => c1, com2_delay => c2, com3_delay => c3,
      mem_dataRead => rdB, mem_done => doneB, mem_fifofull => fullB, isIdle => idleB, obs => open,
      zn_log_valid => lvB, zn_log_we => lweB, zn_log_addr => laB, zn_log_be => lbB, zn_log_data => ldB,
      zn_dev_peek_addr => peek, zn_dev_peek => open);

   -- device request sequences: A's and B's i-th requests must be equal
   process (clk1x)
      type t_q is array(0 to 4095) of std_logic_vector(60 downto 0);
      variable qa, qb : t_q;
      variable na, nb, nc, errs : integer := 0;
   begin
      if rising_edge(clk1x) then
         if lvA = '1' then qa(na mod 4096) := lweA & lbA & std_logic_vector(laA) & ldA; na := na + 1; end if;
         if lvB = '1' then qb(nb mod 4096) := lweB & lbB & std_logic_vector(laB) & ldB; nb := nb + 1; end if;
         while nc < na and nc < nb loop
            -- read requests carry no data: compare their data field only for writes
            if qa(nc mod 4096)(60) = '1' then
               if qa(nc mod 4096) /= qb(nc mod 4096) then errs := errs + 1; end if;
            elsif qa(nc mod 4096)(60 downto 32) /= qb(nc mod 4096)(60 downto 32) then
               errs := errs + 1;
            end if;
            if errs > 0 and errs < 5 and qa(nc mod 4096)(60 downto 32) /= qb(nc mod 4096)(60 downto 32) then
               report "request " & integer'image(nc) & " A " & to_hstring(qa(nc mod 4096)) & " B " & to_hstring(qb(nc mod 4096)) severity warning;
            end if;
            nc := nc + 1;
         end loop;
         assert abs(na - nb) < 4000 report "request logs drifted apart" severity failure;
         log_errors <= errs;
         log_count  <= nc;
         if stop_log and na /= nb then
            report "request counts differ: A " & integer'image(na) & " B " & integer'image(nb) severity error;
         end if;
      end if;
   end process;

   process
      variable lfsr : unsigned(31 downto 0) := to_unsigned(16#2468ACE# + SEED * 7919, 32);
      impure function rnd(m : integer) return integer is
      begin
         for i in 0 to 7 loop
            lfsr := lfsr(30 downto 0) & (lfsr(31) xor lfsr(21) xor lfsr(1) xor lfsr(0));
         end loop;
         return to_integer(lfsr(30 downto 8)) mod m;
      end function;
      type t_cfg is array(0 to 5) of integer;
      constant TAITO : t_cfg := (16#24FF#, 16#16BB#, 16#36BB#, 16#2EBB#, 16#1EBB#, 16#3022#);
      variable region, sz, off, t : integer;
      variable a : unsigned(31 downto 0);
      variable gotA, gotB : boolean;
      variable dA, dB : std_logic_vector(31 downto 0);
      variable errors, nreads, nwrites, nzn : integer := 0;
      variable cyclesA, cyclesB : integer := 0;
      variable gaps : boolean;
   begin
      for i in 0 to 9 loop wait until rising_edge(clk1x); end loop;
      reset <= '0';
      c0 <= x"0"; c1 <= x"1"; c2 <= x"1"; c3 <= x"2";            -- Taito's COM_DELAY 0x2110
      ex1 <= to_unsigned(16#36BB#, 14); ex3 <= to_unsigned(16#1EBB#, 14);
      for i in 0 to 3 loop wait until rising_edge(clk1x); end loop;
      for k in 1 to N loop
         if rnd(40) = 0 then
            if rnd(4) = 0 then
               ex1 <= to_unsigned(rnd(16384), 14); ex3 <= to_unsigned(rnd(16384), 14);
               c0 <= to_unsigned(rnd(16), 4); c1 <= to_unsigned(rnd(16), 4); c2 <= to_unsigned(rnd(16), 4); c3 <= to_unsigned(rnd(16), 4);
            else
               ex1 <= to_unsigned(TAITO(rnd(6)), 14); ex3 <= to_unsigned(TAITO(rnd(6)), 14);
               c0 <= x"0"; c1 <= x"1"; c2 <= x"1"; c3 <= x"2";
            end if;
         end if;
         region := rnd(8);
         case region is
            when 0 | 1  => a := to_unsigned(16#1F000000# + rnd(16#10000#), 32);   -- exp1 (flash window)
            when 2 | 3  => a := to_unsigned(16#1FB00000# + rnd(16#100#), 32);     -- exp3: ATA / RF5C296
            when 4      => a := to_unsigned(16#1FA60000# + rnd(16#10#), 32);      -- exp3: sound status
            when 5      => a := to_unsigned(16#1FA00000# + rnd(16#200000#), 32);  -- whole ZN-2 exp3 range
            when 6      => a := to_unsigned(16#1FB40000# + rnd(16#40#), 32);      -- control area
            when others => a := to_unsigned(rnd(16#200000#), 32);                 -- RAM
         end case;
         if rnd(3) = 1 then a(31) := '1'; elsif rnd(3) = 2 then a(31 downto 29) := "101"; end if;
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
         isCache <= '0'; isData <= '1';
         if rnd(2) = 0 then rnw <= '1'; else rnw <= '0'; end if;
         addrD <= a;
         gaps := rnd(8) = 0;
         req <= '1';
         wait until rising_edge(clk1x);
         req <= '0';
         if rnw = '1' then
            nreads := nreads + 1;
            gotA := false; gotB := false; t := 0;
            while not (gotA and gotB) loop
               if doneA = '1' and not gotA then gotA := true; dA := rdA; cyclesA := cyclesA + t; end if;
               if doneB = '1' and not gotB then gotB := true; dB := rdB; cyclesB := cyclesB + t; end if;
               exit when gotA and gotB;
               -- ce gaps while stalled (both see the same ce)
               if gaps and t mod 3 = 1 then ce <= '0'; else ce <= '1'; end if;
               wait until rising_edge(clk1x);
               t := t + 1;
               assert t < 20000 report "read timeout at access " & integer'image(k) severity failure;
            end loop;
            ce <= '1';
            if dA /= dB then
               errors := errors + 1;
               if errors < 10 then
                  report "read " & integer'image(k) & " at " & to_hstring(a) & " size " & integer'image(sz) &
                         ": A " & to_hstring(dA) & " B " & to_hstring(dB) severity error;
               end if;
            end if;
         else
            nwrites := nwrites + 1;
            wait until rising_edge(clk1x);
            while fullA = '1' or fullB = '1' loop wait until rising_edge(clk1x); end loop;
            -- the reference takes a posted write's later steps from the
            -- current CPU address (fixed since, see the doc): let every step of
            -- an expansion write reach the device before the address moves
            if region /= 7 then
               for i in 0 to 299 loop wait until rising_edge(clk1x); end loop;
            end if;
         end if;
         -- let both finish (posted writes, recovery) before the next access
         t := 0;
         while not (idleA = '1' and idleB = '1') loop
            wait until rising_edge(clk1x);
            t := t + 1;
            assert t < 20000 report "idle timeout at access " & integer'image(k) severity failure;
         end loop;
         for i in 0 to rnd(3) loop wait until rising_edge(clk1x); end loop;
      end loop;
      for i in 0 to 400 loop wait until rising_edge(clk1x); end loop;
      stop_log <= true;
      wait until rising_edge(clk1x);
      wait until rising_edge(clk1x);
      report "overlap transaction check (OVERLAP=" & integer'image(OVERLAP) & "): " & integer'image(nreads) & " reads, " &
             integer'image(nwrites) & " writes, " & integer'image(log_count) & " device requests compared, read data errors " &
             integer'image(errors) & ", request sequence errors " & integer'image(log_errors) &
             ", read wait cycles A " & integer'image(cyclesA) & " B " & integer'image(cyclesB);
      assert errors = 0 and log_errors = 0 report "overlap transaction check FAILED" severity failure;
      report "overlap transaction check PASSED";
      finished <= true;
      wait;
   end process;
end architecture;
