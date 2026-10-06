-- Directed testbench for rtl/gnet/zn2_io.vhd (expected values from MAME
-- 0.288 zn.cpp / taitogn.cpp / at28c16.cpp and the ZN-2 map trace,
-- docs/zn2_layer_design.md 5 and 16).

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_zn2_io is
end entity;

architecture sim of tb_zn2_io is
   constant CLK_HZ   : integer := 1000000;   -- 1 cycle = 1 us, so WRITE_US = cycles
   signal clk        : std_logic := '0';
   signal reset      : std_logic := '1';
   signal req, we    : std_logic := '0';
   signal addr       : unsigned(23 downto 0) := (others => '0');
   signal be         : std_logic_vector(3 downto 0) := "0001";
   signal wdata      : std_logic_vector(31 downto 0) := (others => '0');
   signal ack, hit   : std_logic;
   signal rdata      : std_logic_vector(31 downto 0);
   signal p1, p2, sv, sy : std_logic_vector(7 downto 0) := x"FF";
   signal znsecsel, coin : std_logic_vector(7 downto 0);
   signal ee_addr    : unsigned(10 downto 0) := (others => '0');
   signal ee_we      : std_logic := '0';
   signal ee_wdata   : std_logic_vector(7 downto 0) := (others => '0');
   signal ee_rdata   : std_logic_vector(7 downto 0);
   signal ee_busy    : std_logic;
   signal nv_addr    : unsigned(9 downto 0) := (others => '0');
   signal nv_q       : std_logic_vector(15 downto 0);
   signal nv_wtog    : std_logic;
   signal finished   : boolean := false;
begin
   clk <= not clk after 500 ns when not finished;

   dut : entity work.zn2_io
   generic map (CLK_HZ => CLK_HZ, WRITE_US => 200)
   port map (clk => clk, reset => reset, req => req, we => we, addr => addr, be => be, wdata => wdata,
             ack => ack, rdata => rdata, hit => hit, in_p1 => p1, in_p2 => p2, in_service => sv, in_system => sy,
             znsecsel => znsecsel, coin => coin, ee_addr => ee_addr, ee_we => ee_we, ee_wdata => ee_wdata,
             ee_rdata => ee_rdata, ee_busy => ee_busy,
             nv_clk => clk, nv_addr => nv_addr, nv_q => nv_q, nv_wtog => nv_wtog);

   process
      variable errors : integer := 0;
      variable r      : std_logic_vector(31 downto 0);
      constant TAITO  : string := "TAITO_TG";

      procedure tick(n : integer := 1) is
      begin
         for i in 1 to n loop wait until rising_edge(clk); end loop;
      end procedure;

      procedure acc(a : integer; b : std_logic_vector(3 downto 0); w : boolean; d : std_logic_vector(31 downto 0);
                    res : out std_logic_vector(31 downto 0)) is
      begin
         addr <= to_unsigned(a, 24) and x"FFFFFC"; be <= b; wdata <= d;
         if w then we <= '1'; else we <= '0'; end if;
         req <= '1'; tick; req <= '0';
         for i in 0 to 20 loop
            exit when ack = '1';
            tick;
         end loop;
         assert ack = '1' report "no ack" severity failure;
         res := rdata;
         tick;
      end procedure;

      procedure check(name : string; got, exp : std_logic_vector) is
      begin
         if got /= exp then
            errors := errors + 1;
            report name & ": got " & to_hstring(got) & " expected " & to_hstring(exp) severity error;
         end if;
      end procedure;
   begin
      -- preload through the shell port: erased (FFh), then the header the
      -- game reads at 15.7 s in the Ray Crisis trace
      for i in 0 to 2047 loop
         ee_addr <= to_unsigned(i, 11); ee_wdata <= x"FF"; ee_we <= '1'; tick;
      end loop;
      for i in TAITO'range loop
         ee_addr <= to_unsigned(i - 1, 11); ee_wdata <= std_logic_vector(to_unsigned(character'pos(TAITO(i)), 8));
         ee_we <= '1'; tick;
      end loop;
      ee_we <= '0';
      tick(2); reset <= '0'; tick(2);

      -- board configuration (MAME and trace: 69h)
      acc(16#A10200#, "0001", false, x"00000000", r); check("boardcfg", r, x"00000069");
      -- inputs, active low
      p1 <= x"EF"; p2 <= x"FE"; sv <= x"FD"; sy <= x"EF"; tick;
      acc(16#A00000#, "0001", false, x"00000000", r); check("P1", r(7 downto 0), x"EF");
      acc(16#A00100#, "0001", false, x"00000000", r); check("P2", r(7 downto 0), x"FE");
      acc(16#A00200#, "0001", false, x"00000000", r); check("SERVICE", r(7 downto 0), x"FD");
      acc(16#A00300#, "0001", false, x"00000000", r); check("SYSTEM", r(7 downto 0), x"EF");
      acc(16#A10000#, "0001", false, x"00000000", r); check("P3", r(7 downto 0), x"FF");
      -- POST writes to A00000 are ignored
      acc(16#A00000#, "0001", true, x"00000007", r);
      acc(16#A00000#, "0001", false, x"00000000", r); check("P1 after POST write", r(7 downto 0), x"EF");
      -- znsecsel and coin
      acc(16#A10300#, "0001", true, x"00000088", r); check("znsecsel out", znsecsel, x"88");
      acc(16#A10300#, "0001", false, x"00000000", r); check("znsecsel read", r(7 downto 0), x"88");
      acc(16#A20000#, "0001", true, x"00000022", r); check("coin out", coin, x"22");
      acc(16#A20000#, "0001", false, x"00000000", r); check("coin read", r(7 downto 0), x"22");
      -- 0x1FA60000 toggles bit 3 per read of the low half (trace: 8, 0, 8)
      acc(16#A60000#, "0011", false, x"00000000", r); check("1fa60000 #1", r, x"00000008");
      acc(16#A60000#, "1100", false, x"00000000", r); check("1fa60002", r, x"00000000");
      acc(16#A60000#, "0011", false, x"00000000", r); check("1fa60000 #2", r, x"00000000");
      acc(16#A60000#, "0011", false, x"00000000", r); check("1fa60000 #3", r, x"00000008");
      -- every SPU read polls until bit 3 is set: never more than two reads
      for i in 0 to 9 loop
         acc(16#A51C00# + 4 * i, "0011", false, x"00000000", r);
         acc(16#A60000#, "0011", false, x"00000000", r);
         if r(3) = '0' then
            acc(16#A60000#, "0011", false, x"00000000", r);
         end if;
         check("spu poll", r(3 downto 3), "1");
      end loop;
      -- reads that return 0 or FFFFh
      acc(16#A51DAC#, "1100", false, x"00000000", r); check("1fa51dac", r, x"00000000");
      acc(16#A40000#, "0001", false, x"00000000", r); check("1fa40000", r, x"00000000");
      acc(16#B20000#, "0011", false, x"00000000", r); check("1fb20000", r, x"0000FFFF");
      -- hit decode
      addr <= x"A30000"; tick; check("hit A30000", (0 => hit), "0");
      addr <= x"A10300"; tick; check("hit A10300", (0 => hit), "1");
      addr <= x"B40000"; tick; check("hit B40000", (0 => hit), "0");
      addr <= x"BE0100"; tick; check("hit BE0100", (0 => hit), "1");
      -- EEPROM byte reads as the game does at 15.7 s (lanes 0 to 3)
      acc(16#AF0000#, "0001", false, x"00000000", r); check("ee 0", r, x"00000054");
      acc(16#AF0000#, "0010", false, x"00000000", r); check("ee 1", r, x"00004100");
      acc(16#AF0000#, "0100", false, x"00000000", r); check("ee 2", r, x"00490000");
      acc(16#AF0000#, "1000", false, x"00000000", r); check("ee 3", r, x"54000000");
      acc(16#AF0004#, "1000", false, x"00000000", r); check("ee 7", r, x"47000000");
      -- EEPROM write: DATA polling until the self-timed write ends
      acc(16#AF0010#, "0010", true, x"00003C00", r);         -- byte 0x11 = 3Ch
      check("ee busy", (0 => ee_busy), "1");
      acc(16#AF0010#, "0010", false, x"00000000", r); check("ee polling", r, x"0000BC00");
      acc(16#AF0014#, "0001", true, x"000000AA", r);         -- ignored while busy
      tick(200);
      check("ee idle", (0 => ee_busy), "0");
      acc(16#AF0010#, "0010", false, x"00000000", r); check("ee written", r, x"00003C00");
      acc(16#AF0014#, "0001", false, x"00000000", r); check("ee write while busy ignored", r, x"000000FF");
      ee_addr <= to_unsigned(16#11#, 11); tick(2); check("ee shell port", ee_rdata, x"3C");
      -- NVRAM copy (docs/m4_shell.md 4): 16-bit words, low byte = even address;
      -- the shell preload and the one accepted CPU write are in it, the
      -- write refused while busy is not; nv_wtog toggled once (CPU writes only)
      nv_addr <= to_unsigned(0, 10); tick(2);  check("nv word 0", nv_q, x"4154");   -- "TA"
      nv_addr <= to_unsigned(3, 10); tick(2);  check("nv word 3", nv_q, x"4754");   -- "TG"
      nv_addr <= to_unsigned(8, 10); tick(2);  check("nv word 8", nv_q, x"3CFF");   -- 10h FFh, 11h 3Ch
      nv_addr <= to_unsigned(10, 10); tick(2); check("nv word 10", nv_q, x"FFFF");  -- 14h refused
      nv_addr <= to_unsigned(1023, 10); tick(2); check("nv word 1023", nv_q, x"FFFF");
      check("nv write toggle", (0 => nv_wtog), "1");
      -- mailbox: bytes on lanes 0 and 2, 256 x 8
      acc(16#BE0000#, "0101", true, x"00220011", r);
      acc(16#BE01FC#, "0101", true, x"00FF00EE", r);
      acc(16#BE0000#, "1111", false, x"00000000", r); check("mbox 0/1", r, x"00220011");
      acc(16#BE01FC#, "0101", false, x"00000000", r); check("mbox fe/ff", r, x"00FF00EE");
      -- Zoom stub
      acc(16#BC0000#, "0011", false, x"00000000", r); check("zoom irq status", r, x"00000000");

      report "zn2_io directed tests: " & integer'image(errors) & " errors";
      assert errors = 0 report "zn2_io tests FAILED" severity failure;
      report "zn2_io tests PASSED";
      finished <= true;
      wait;
   end process;
end architecture;
