-- Replay of MAME 0.288 ZN-2 register accesses into rtl/gnet/zn2_io.vhd
-- (vectors from tools/gnet/zn2io_vectors.py; inputs idle, as in the trace).
-- Every read is compared on its enabled lanes.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use STD.textio.all;

entity tb_zn2_io_replay is
   generic (DIR : string := "work");
end entity;

architecture sim of tb_zn2_io_replay is
   signal clk        : std_logic := '0';
   signal reset      : std_logic := '1';
   signal req, we    : std_logic := '0';
   signal addr       : unsigned(23 downto 0) := (others => '0');
   signal be         : std_logic_vector(3 downto 0) := "0001";
   signal wdata      : std_logic_vector(31 downto 0) := (others => '0');
   signal ack, hit   : std_logic;
   signal rdata      : std_logic_vector(31 downto 0);
   signal znsecsel, coin : std_logic_vector(7 downto 0);
   signal ee_addr    : unsigned(10 downto 0) := (others => '0');
   signal ee_we      : std_logic := '0';
   signal ee_wdata   : std_logic_vector(7 downto 0) := (others => '0');
   signal ee_rdata   : std_logic_vector(7 downto 0);
   signal ee_busy    : std_logic;
   signal finished   : boolean := false;

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
   clk <= not clk after 5 ns when not finished;

   dut : entity work.zn2_io
   port map (clk => clk, reset => reset, req => req, we => we, addr => addr, be => be, wdata => wdata,
             ack => ack, rdata => rdata, hit => hit, in_p1 => x"FF", in_p2 => x"FF", in_service => x"FF", in_system => x"FF",
             znsecsel => znsecsel, coin => coin, ee_addr => ee_addr, ee_we => ee_we, ee_wdata => ee_wdata,
             ee_rdata => ee_rdata, ee_busy => ee_busy);

   process
      file fe, fv : text;
      variable l  : line;
      variable c  : character;
      variable s2 : string(1 to 2);
      variable s6 : string(1 to 6);
      variable s4 : string(1 to 4);
      variable s8 : string(1 to 8);
      variable d, m : std_logic_vector(31 downto 0);
      variable b  : std_logic_vector(3 downto 0);
      variable nr, nw, nbad : integer := 0;
   begin
      file_open(fe, DIR & "/ee.hex", read_mode);
      for i in 0 to 2047 loop
         readline(fe, l); read(l, s2);
         ee_addr <= to_unsigned(i, 11); ee_wdata <= hex(s2); ee_we <= '1';
         wait until rising_edge(clk);
      end loop;
      file_close(fe);
      ee_we <= '0';
      wait until rising_edge(clk);
      reset <= '0';
      wait until rising_edge(clk);

      file_open(fv, DIR & "/zn2io.vec", read_mode);
      while not endfile(fv) loop
         readline(fv, l);
         read(l, c);
         read(l, s2(1)); read(l, s6); read(l, s2(1)); read(l, s4); read(l, s2(1)); read(l, s8);
         for i in 0 to 3 loop
            if s4(4 - i) = '1' then b(i) := '1'; else b(i) := '0'; end if;
         end loop;
         d := hex(s8);
         addr <= unsigned(hex(s6)(23 downto 0)); be <= b; wdata <= d;
         if c = 'W' then we <= '1'; nw := nw + 1; else we <= '0'; nr := nr + 1; end if;
         req <= '1';
         wait until rising_edge(clk);
         req <= '0';
         while ack /= '1' loop wait until rising_edge(clk); end loop;
         if c = 'R' then
            for i in 0 to 3 loop
               if b(i) = '1' then m(8 * i + 7 downto 8 * i) := x"FF"; else m(8 * i + 7 downto 8 * i) := x"00"; end if;
            end loop;
            if (rdata and m) /= (d and m) then
               nbad := nbad + 1;
               if nbad <= 5 then
                  report "read " & s6 & " be " & s4 & ": MAME " & s8 & " RTL " & to_hstring(rdata) severity error;
               end if;
            end if;
         end if;
         wait until rising_edge(clk);
      end loop;
      file_close(fv);
      report "zn2_io replay: " & integer'image(nr) & " reads, " & integer'image(nw) & " writes, mismatches " & integer'image(nbad);
      assert nbad = 0 report "zn2_io replay FAILED" severity failure;
      assert nr > 0 report "no reads replayed" severity failure;
      report "zn2_io replay PASSED";
      finished <= true;
      wait;
   end process;
end architecture;
