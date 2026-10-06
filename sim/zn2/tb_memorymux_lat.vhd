-- ZN-2 expansion read latency per access (docs/r1_cpu_domain_design.md,
-- read overlap): memorymux with ZN2_MAP = 1, ZN2_READ_OVERLAP = OVERLAP, a
-- device that acknowledges every request after exactly LAT cycles
-- (mm_harness FIXED_LAT), Taito's COM_DELAY 0x2110 and the bus settings the
-- games program. Per row, in CPU (clk1x) cycles from the request strobe:
-- the first zn_req, and mem_done for an isolated access (20 idle cycles
-- before) and for back-to-back accesses (next request 2 cycles after
-- done, as in a copy loop). Every read is checked against the device data.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use STD.textio.all;

entity tb_memorymux_lat is
   generic
   (
      OVERLAP : integer := 0;
      LAT     : integer := 8;
      OUTFILE : string  := "lat.txt"
   );
end entity;

architecture sim of tb_memorymux_lat is
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
   signal lv, lwe       : std_logic;
   signal laddr         : unsigned(23 downto 0);
   signal lbe           : std_logic_vector(3 downto 0);
   signal ldata         : std_logic_vector(31 downto 0);
   signal peek          : unsigned(15 downto 0) := (others => '0');
   signal finished      : boolean := false;
   signal cyc           : integer := 0;
   signal first_lv      : integer := -1;
   signal arm           : boolean := false;
begin
   clk2x <= not clk2x after 5 ns when not finished;
   process (clk2x) begin if rising_edge(clk2x) then clk1x <= not clk1x; end if; end process;

   H : entity work.mm_harness generic map (VARIANT => 2, OVERLAP => OVERLAP, FIXED_LAT => LAT)
   port map (clk1x => clk1x, clk2x => clk2x, ce => ce, reset => reset,
      mem_in_request => req, mem_in_rnw => rnw, mem_in_isData => isData, mem_in_isCache => isCache,
      mem_in_addressInstr => addrD, mem_in_addressData => addrD, mem_in_reqsize => reqsize,
      mem_in_writeMask => wmask, mem_in_dataWrite => wdata,
      ex1_memctrl => ex1, ex2_memctrl => (others => '0'), ex3_memctrl => ex3, spu_memctrl => (others => '0'),
      cd_memctrl => (others => '0'), bios_memctrl => (others => '0'),
      com0_delay => x"0", com1_delay => x"1", com2_delay => x"1", com3_delay => x"2",
      mem_dataRead => rd, mem_done => done, mem_fifofull => full, isIdle => idle, obs => open,
      zn_log_valid => lv, zn_log_we => lwe, zn_log_addr => laddr, zn_log_be => lbe, zn_log_data => ldata,
      zn_dev_peek_addr => peek, zn_dev_peek => open);

   -- cycle counter; the device logs a request one cycle after zn_req
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         cyc <= cyc + 1;
         if not arm then
            first_lv <= -1;
         elsif lv = '1' and first_lv < 0 then
            first_lv <= cyc - 1;
         end if;
      end if;
   end process;

   process
      file f : text open write_mode is OUTFILE;
      variable l : line;
      variable errors : integer := 0;
      variable t0, t, tz : integer;
      variable r : std_logic_vector(31 downto 0);

      procedure tick(n : integer := 1) is
      begin
         for i in 1 to n loop wait until rising_edge(clk1x); end loop;
      end procedure;

      procedure setup(a : unsigned(31 downto 0); size : integer; write : boolean; data : std_logic_vector(31 downto 0)) is
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
      end procedure;

      -- one read; returns cycles to done and to the first zn_req
      procedure read1(a : unsigned(31 downto 0); size : integer; cyc_done, cyc_zn : out integer; data : out std_logic_vector(31 downto 0)) is
      begin
         setup(a, size, false, (others => '0'));
         arm <= true;
         req <= '1';
         t0 := cyc;
         tick;
         req <= '0';
         for i in 0 to 2000 loop
            exit when done = '1';
            tick;
         end loop;
         assert done = '1' report "read timeout" severity failure;
         cyc_done := cyc - t0 - 1;     -- cycles after the strobe edge until done is seen
         data := rd;
         tick;
         cyc_zn := first_lv - t0;
         arm <= false;
         tick;
      end procedure;

      procedure write1(a : unsigned(31 downto 0); size : integer; data : std_logic_vector(31 downto 0)) is
      begin
         setup(a, size, true, data);
         req <= '1'; tick; req <= '0';
         tick(200);
      end procedure;

      procedure row(name : string; a : unsigned(31 downto 0); size : integer; exp : std_logic_vector(31 downto 0)) is
         variable d_iso, z_iso, d_b2b, z_b2b, sum_b2b : integer;
         variable got : std_logic_vector(31 downto 0);
         variable m   : std_logic_vector(31 downto 0);
      begin
         case size is
            when 1 => m := x"000000FF";
            when 2 => m := x"0000FFFF";
            when others => m := x"FFFFFFFF";
         end case;
         tick(20);
         read1(a, size, d_iso, z_iso, got);
         if (got and m) /= (exp and m) then
            errors := errors + 1;
            report name & ": got " & to_hstring(got) & " expected " & to_hstring(exp) severity error;
         end if;
         sum_b2b := 0;
         for i in 0 to 7 loop
            read1(a, size, d_b2b, z_b2b, got);   -- read1 returns 2 cycles after done
            sum_b2b := sum_b2b + d_b2b;
            if (got and m) /= (exp and m) then errors := errors + 1; end if;
         end loop;
         write(l, string'("row ") & name & " overlap " & integer'image(OVERLAP) & " lat " & integer'image(LAT) &
               " req_to_znreq " & integer'image(z_iso) & " isolated " & integer'image(d_iso) &
               " back_to_back " & integer'image(sum_b2b / 8) & " last_b2b_req_to_znreq " & integer'image(z_b2b));
         writeline(f, l);
      end procedure;

   begin
      tick(10); reset <= '0'; tick(4);
      -- device contents through 16-bit writes
      ex1 <= to_unsigned(16#36BB#, 14); ex3 <= to_unsigned(16#36BB#, 14);
      -- (the device decodes zn_addr(15 downto 0) only: 0x1FB00000 and
      -- 0x1FA60000 are the same device bytes)
      write1(x"1F089C1C", 4, x"6A1218EC");
      write1(x"1FB00000", 4, x"0084004C");

      ex1 <= to_unsigned(16#36BB#, 14);
      row("flash_lhu_201736BB", x"1F089C1C", 2, x"000018EC");
      row("flash_lw_201736BB",  x"1F089C1C", 4, x"6A1218EC");
      ex1 <= to_unsigned(16#16BB#, 14);
      row("flash_lhu_201716BB", x"1F089C1E", 2, x"00006A12");
      ex3 <= to_unsigned(16#1EBB#, 14);
      row("ata_lhu_20151EBB",   x"1FB00000", 2, x"0000004C");
      ex3 <= to_unsigned(16#2EBB#, 14);
      row("ata_lbu_20152EBB",   x"1FB00000", 1, x"0000004C");
      row("ata_lhu_20152EBB",   x"1FB00000", 2, x"0000004C");
      ex3 <= to_unsigned(16#3022#, 14);
      row("snd_lw_20153022",    x"1FA60000", 4, x"0084004C");

      assert errors = 0 report "latency bench: data errors" severity failure;
      report "latency bench done, data errors 0";
      finished <= true;
      wait;
   end process;
end architecture;
