-- Directed testbench: memorymux with ZN2_MAP = 1 against a lane-addressed
-- device on the zn_* port with random acknowledge latency (mm_harness).
-- Bus configurations are the values the G-NET BIOS and games program
-- (MAME 0.288 trace, docs/zn2_layer_design.md 5):
--   exp1 0x001724FF  8-bit, auto-increment       (BIOS reading U30 bytes)
--   exp1 0x201716BB  16-bit, no auto-increment   (flash window reads)
--   exp1 0x201736BB  16-bit, auto-increment      (flash window)
--   exp3 0x20152EBB  8-bit, auto-increment       (RF5C296 and ATA registers)
--   exp3 0x201536BB  16-bit, auto-increment      (control, mailbox)
--   exp3 0x20153022  16-bit, auto-increment      (0x1FA60000 32-bit reads)
-- Checks: the requests the device sees (word address, byte enables), the
-- data the CPU gets back, and the device contents after writes.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_memorymux_zn is
   generic (SEED : integer := 1; OVERLAP : integer := 0);   -- OVERLAP: memorymux ZN2_READ_OVERLAP
end entity;

architecture sim of tb_memorymux_zn is
   signal clk1x, clk2x  : std_logic := '0';
   signal ce            : std_logic := '1';
   signal reset         : std_logic := '1';
   signal req, rnw, isData, isCache : std_logic := '0';
   signal addrD         : unsigned(31 downto 0) := (others => '0');
   signal reqsize       : unsigned(1 downto 0) := "10";
   signal wmask         : std_logic_vector(3 downto 0) := "1111";
   signal wdata         : std_logic_vector(31 downto 0) := (others => '0');
   signal ex1, ex3      : unsigned(13 downto 0) := (others => '0');
   signal rd            : std_logic_vector(31 downto 0);
   signal done, full, idle : std_logic;
   signal obs           : std_logic_vector(511 downto 0);
   signal lv, lwe       : std_logic;
   signal laddr         : unsigned(23 downto 0);
   signal lbe           : std_logic_vector(3 downto 0);
   signal ldata         : std_logic_vector(31 downto 0);
   signal peek_a        : unsigned(15 downto 0) := (others => '0');
   signal peek          : std_logic_vector(7 downto 0);
   signal finished      : boolean := false;

   type t_log is array(0 to 63) of std_logic_vector(31 downto 0);
   signal log_a         : t_log;
   signal log_n         : integer := 0;
   signal log_clear     : std_logic := '0';
begin
   clk2x <= not clk2x after 5 ns when not finished;
   process (clk2x) begin if rising_edge(clk2x) then clk1x <= not clk1x; end if; end process;

   H : entity work.mm_harness generic map (VARIANT => 2, SEED => SEED, OVERLAP => OVERLAP)
   port map (clk1x => clk1x, clk2x => clk2x, ce => ce, reset => reset,
      mem_in_request => req, mem_in_rnw => rnw, mem_in_isData => isData, mem_in_isCache => isCache,
      mem_in_addressInstr => addrD, mem_in_addressData => addrD, mem_in_reqsize => reqsize,
      mem_in_writeMask => wmask, mem_in_dataWrite => wdata,
      ex1_memctrl => ex1, ex2_memctrl => (others => '0'), ex3_memctrl => ex3, spu_memctrl => (others => '0'),
      cd_memctrl => (others => '0'), bios_memctrl => (others => '0'),
      com0_delay => x"5", com1_delay => x"2", com2_delay => x"2", com3_delay => x"1",
      mem_dataRead => rd, mem_done => done, mem_fifofull => full, isIdle => idle, obs => obs,
      zn_log_valid => lv, zn_log_we => lwe, zn_log_addr => laddr, zn_log_be => lbe, zn_log_data => ldata,
      zn_dev_peek_addr => peek_a, zn_dev_peek => peek);

   -- request log: we & be & addr (24 bits) per request
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         if log_clear = '1' then
            log_n <= 0;
         elsif lv = '1' then
            log_a(log_n) <= "000" & lwe & lbe & std_logic_vector(laddr);
            log_n <= log_n + 1;
         end if;
      end if;
   end process;

   process
      variable errors : integer := 0;

      procedure tick(n : integer := 1) is
      begin
         for i in 1 to n loop wait until rising_edge(clk1x); end loop;
      end procedure;

      procedure bus_access(a : unsigned(31 downto 0); size : integer; write : boolean;
                        data : std_logic_vector(31 downto 0); result : out std_logic_vector(31 downto 0)) is
         variable off : integer;
      begin
         addrD <= a; isData <= '1'; isCache <= '0';
         off := to_integer(a(1 downto 0));
         case size is
            when 1 => reqsize <= "00"; wmask <= (others => '0'); wmask(off) <= '1';
            when 2 => reqsize <= "01"; if off = 0 then wmask <= "0011"; else wmask <= "1100"; end if;
            when others => reqsize <= "10"; wmask <= "1111";
         end case;
         wdata <= data;
         if write then rnw <= '0'; else rnw <= '1'; end if;
         req <= '1';
         tick;
         req <= '0';
         result := (others => '0');
         if not write then
            for t in 0 to 2000 loop
               exit when done = '1';
               tick;
            end loop;
            assert done = '1' report "read timeout" severity failure;
            result := rd;
         else
            -- let the posted write reach the device
            tick(200);
         end if;
      end procedure;

      procedure check(name : string; got, exp : std_logic_vector) is
      begin
         if got /= exp then
            errors := errors + 1;
            report name & ": got " & to_hstring(got) & " expected " & to_hstring(exp) severity error;
         end if;
      end procedure;

      procedure check_log(name : string; idx : integer; we : std_logic; be : std_logic_vector(3 downto 0); addr : integer) is
         variable e : std_logic_vector(31 downto 0);
      begin
         e := "000" & we & be & std_logic_vector(to_unsigned(addr, 24));
         if idx >= log_n then
            errors := errors + 1;
            report name & ": request " & integer'image(idx) & " missing (" & integer'image(log_n) & " logged)" severity error;
         elsif log_a(idx) /= e then
            errors := errors + 1;
            report name & ": request " & integer'image(idx) & " = " & to_hstring(log_a(idx)) & " expected " & to_hstring(e) severity error;
         end if;
      end procedure;

      procedure clear_log is
      begin
         log_clear <= '1'; tick; log_clear <= '0'; tick;
      end procedure;

      procedure peek_byte(a : integer; exp : std_logic_vector(7 downto 0); name : string) is
      begin
         peek_a <= to_unsigned(a mod 65536, 16); tick(2);
         check(name, peek, exp);
      end procedure;

      variable r : std_logic_vector(31 downto 0);
      constant Z : std_logic_vector(31 downto 0) := (others => '0');
   begin
      tick(10); reset <= '0'; tick(4);

      -- 1a. exp3 16-bit with auto-increment: halfword and byte writes,
      --     including an odd byte, then reads back
      ex3 <= to_unsigned(16#36BB#, 14); ex1 <= to_unsigned(16#16BB#, 14);
      clear_log;
      bus_access(x"1FB40100", 1, true, x"000000A5", r);   -- byte at even address
      bus_access(x"1FB40101", 1, true, x"00005A00", r);   -- byte at odd address
      bus_access(x"1FB40104", 2, true, x"00001234", r);   -- halfword lane 0
      bus_access(x"1FB40106", 2, true, x"ABCD0000", r);   -- halfword lane 1
      check_log("exp3 sb even", 0, '1', "0001", 16#B40100#);
      check_log("exp3 sb odd",  1, '1', "0010", 16#B40100#);
      check_log("exp3 sh lo",   2, '1', "0011", 16#B40104#);
      check_log("exp3 sh hi",   3, '1', "1100", 16#B40104#);
      peek_byte(16#0100#, x"A5", "dev 100"); peek_byte(16#0101#, x"5A", "dev 101");
      peek_byte(16#0104#, x"34", "dev 104"); peek_byte(16#0105#, x"12", "dev 105");
      peek_byte(16#0106#, x"CD", "dev 106"); peek_byte(16#0107#, x"AB", "dev 107");
      clear_log;
      bus_access(x"1FB40101", 1, false, Z, r); check("exp3 lbu odd", r(7 downto 0), x"5A");
      bus_access(x"1FB40106", 2, false, Z, r); check("exp3 lhu hi", r(15 downto 0), x"ABCD");
      bus_access(x"1FB40104", 4, false, Z, r); check("exp3 lw autoinc", r, x"ABCD1234");
      check_log("exp3 lbu odd req", 0, '0', "0011", 16#B40100#);
      check_log("exp3 lhu hi req",  1, '0', "1100", 16#B40104#);
      check_log("exp3 lw step0",    2, '0', "0011", 16#B40104#);
      check_log("exp3 lw step1",    3, '0', "1100", 16#B40104#);

      -- 1b. exp3 8-bit with auto-increment (RF5C296: ExCA index 0x3E0 and
      --     data 0x3E1, ATA registers): every byte is its own request
      ex3 <= to_unsigned(16#2EBB#, 14);
      clear_log;
      bus_access(x"1FB003E0", 1, true, x"00000003", r);
      bus_access(x"1FB003E1", 1, true, x"00004000", r);
      bus_access(x"1FB00004", 2, true, x"00007788", r);   -- halfword on an 8-bit bus: two bytes
      check_log("exp3 8bit idx",  0, '1', "0001", 16#B003E0#);
      check_log("exp3 8bit data", 1, '1', "0010", 16#B003E0#);
      check_log("exp3 8bit sh b0", 2, '1', "0001", 16#B00004#);
      check_log("exp3 8bit sh b1", 3, '1', "0010", 16#B00004#);
      peek_byte(16#03E0#, x"03", "dev 3E0"); peek_byte(16#03E1#, x"40", "dev 3E1");
      peek_byte(16#0004#, x"88", "dev 004"); peek_byte(16#0005#, x"77", "dev 005");
      clear_log;
      bus_access(x"1FB003E1", 1, false, Z, r); check("exp3 8bit lbu odd", r(7 downto 0), x"40");
      bus_access(x"1FB00004", 2, false, Z, r); check("exp3 8bit lhu", r(15 downto 0), x"7788");
      check_log("exp3 8bit lbu req", 0, '0', "0010", 16#B003E0#);
      check_log("exp3 8bit lhu b0",  1, '0', "0001", 16#B00004#);
      check_log("exp3 8bit lhu b1",  2, '0', "0010", 16#B00004#);

      -- 2. exp3 0x1FA60000 32-bit read (config 0x3022): two lanes
      ex3 <= to_unsigned(16#3022#, 14);
      bus_access(x"1FA60000", 4, true, x"00080000", r);   -- seed lane 1 via a word write (16-bit steps)
      clear_log;
      bus_access(x"1FA60000", 4, false, Z, r);
      check("1fa60000 lw", r, x"00080000");
      check_log("1fa60000 step0", 0, '0', "0011", 16#A60000#);
      check_log("1fa60000 step1", 1, '0', "1100", 16#A60000#);

      -- 3. exp1 16-bit without auto-increment: halfword accesses (what the
      --    BIOS does), and the 32-bit case the PS1 bus model gives: both
      --    steps at the first halfword address
      ex1 <= to_unsigned(16#16BB#, 14);
      bus_access(x"1F010000", 2, true, x"00001111", r);
      bus_access(x"1F010002", 2, true, x"22220000", r);
      clear_log;
      bus_access(x"1F010000", 2, false, Z, r); check("exp1 lhu lo", r(15 downto 0), x"1111");
      bus_access(x"1F010002", 2, false, Z, r); check("exp1 lhu hi", r(15 downto 0), x"2222");
      bus_access(x"1F010000", 4, false, Z, r); check("exp1 lw no autoinc", r, x"11111111");
      check_log("exp1 lw step0", 2, '0', "0011", 16#010000#);
      check_log("exp1 lw step1", 3, '0', "0011", 16#010000#);

      -- 4. exp1 8-bit with auto-increment (BIOS reading the U30 header):
      --    every byte address returns its own byte
      ex1 <= to_unsigned(16#36BB#, 14);
      bus_access(x"1F000204", 4, true, x"6563694C", r);   -- "Lice", 16-bit with auto-increment
      ex1 <= to_unsigned(16#24FF#, 14);
      clear_log;
      bus_access(x"1F000204", 1, false, Z, r); check("exp1 8bit b0", r(7 downto 0), x"4C");
      bus_access(x"1F000205", 1, false, Z, r); check("exp1 8bit b1", r(7 downto 0), x"69");
      bus_access(x"1F000206", 1, false, Z, r); check("exp1 8bit b2", r(7 downto 0), x"63");
      bus_access(x"1F000207", 1, false, Z, r); check("exp1 8bit b3", r(7 downto 0), x"65");
      check_log("exp1 8bit req0", 0, '0', "0001", 16#000204#);
      check_log("exp1 8bit req1", 1, '0', "0010", 16#000204#);
      check_log("exp1 8bit req2", 2, '0', "0100", 16#000204#);
      check_log("exp1 8bit req3", 3, '0', "1000", 16#000204#);
      clear_log;
      bus_access(x"1F000204", 4, false, Z, r); check("exp1 8bit lw", r, x"6563694C");
      for i in 0 to 3 loop
         check_log("exp1 8bit lw step", i, '0', std_logic_vector(shift_left(to_unsigned(1, 4), i)), 16#000204#);
      end loop;
      bus_access(x"1F000206", 2, false, Z, r); check("exp1 8bit lhu", r(15 downto 0), x"6563");

      -- 5. KSEG1 view and the top of the ZN range
      ex3 <= to_unsigned(16#36BB#, 14);
      bus_access(x"BFBE0100", 2, true, x"0000C3C3", r);
      bus_access(x"BFBE0100", 2, false, Z, r); check("kseg1 mailbox", r(15 downto 0), x"C3C3");

      -- 5b. a posted 32-bit write on the 16-bit bus followed at once by a
      --     RAM read: both steps must reach the write's own address (before
      --     the posted-write address fix the second step went to the RAM
      --     read's address)
      ex3 <= to_unsigned(16#36BB#, 14);
      clear_log;
      addrD <= x"1FB40110"; isData <= '1'; reqsize <= "10"; wmask <= "1111"; wdata <= x"C0DE1234"; rnw <= '0';
      req <= '1'; tick; req <= '0';
      tick(2);
      bus_access(x"80012344", 4, false, Z, r);
      tick(200);
      check_log("posted sw step0", 0, '1', "0011", 16#B40110#);
      check_log("posted sw step1", 1, '1', "1100", 16#B40110#);
      peek_byte(16#0110#, x"34", "dev 110"); peek_byte(16#0113#, x"C0", "dev 113");

      -- 6. ce gaps during a stalled read
      ex3 <= to_unsigned(16#36BB#, 14);
      addrD <= x"1FB40104"; isData <= '1'; reqsize <= "10"; wmask <= "1111"; rnw <= '1';
      req <= '1'; tick; req <= '0';
      for t in 0 to 2000 loop
         exit when done = '1';
         if t mod 3 = 0 then ce <= '0'; else ce <= '1'; end if;
         tick;
      end loop;
      ce <= '1';
      check("ce gaps lw", rd, x"ABCD1234");

      tick(20);
      report "memorymux ZN2_MAP=1 (ZN2_READ_OVERLAP=" & integer'image(OVERLAP) & ") directed tests: " & integer'image(errors) & " errors";
      assert errors = 0 report "ZN-2 bus tests FAILED" severity failure;
      report "ZN-2 bus tests PASSED";
      finished <= true;
      wait;
   end process;
end architecture;
