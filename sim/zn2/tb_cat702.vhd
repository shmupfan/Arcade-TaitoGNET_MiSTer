-- Replay testbench for rtl/gnet/zn_cat702.vhd.
-- Reads key_<N>.hex (8 lines of hex bytes) and cat702_<N>.vec written by
-- tools/gnet/cat702_ref.py vectors from a MAME 0.288 oracle sec.log:
--   S <0|1>          select line (0 = selected)
--   B <tx> <rx>      one SIO0 byte: tx sent LSB first, rx = byte MAME's SIO0
--                    received from this chip
-- Each bit is one bit_stb clock with its TXD value; dataout is sampled in
-- that clock, as zn_sio0 does (MAME sio.cpp order: SCK low, TXD, SCK high,
-- sample). Fails on any mismatch.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use STD.textio.all;

entity tb_cat702 is
   generic
   (
      DIR : string  := "work";
      N   : integer := 0
   );
end entity;

architecture sim of tb_cat702 is
   signal clk      : std_logic := '0';
   signal reset    : std_logic := '1';
   signal key_we   : std_logic := '0';
   signal key_addr : unsigned(2 downto 0) := (others => '0');
   signal key_data : std_logic_vector(7 downto 0) := (others => '0');
   signal sel_n    : std_logic := '1';
   signal bit_stb  : std_logic := '0';
   signal txd      : std_logic := '1';
   signal dataout  : std_logic;
   signal done     : boolean := false;

   function hex2int(s : string) return integer is
      variable v : integer := 0;
      variable d : integer;
   begin
      for i in s'range loop
         case s(i) is
            when '0' to '9' => d := character'pos(s(i)) - character'pos('0');
            when 'a' to 'f' => d := character'pos(s(i)) - character'pos('a') + 10;
            when 'A' to 'F' => d := character'pos(s(i)) - character'pos('A') + 10;
            when others     => d := 0;
         end case;
         v := v * 16 + d;
      end loop;
      return v;
   end function;
begin

   clk <= not clk after 5 ns when not done;

   dut : entity work.zn_cat702
   port map (clk => clk, reset => reset, key_we => key_we, key_addr => key_addr,
             key_data => key_data, sel_n => sel_n, bit_stb => bit_stb, txd => txd, dataout => dataout);

   process
      file fk, fv     : text;
      variable l      : line;
      variable c      : character;
      variable s2     : string(1 to 2);
      variable tx, rx : integer;
      variable got    : std_logic_vector(7 downto 0);
      variable txv    : std_logic_vector(7 downto 0);
      variable nb, nbad, nsel : integer := 0;
      variable good   : boolean;
   begin
      file_open(fk, DIR & "/key_" & integer'image(N) & ".hex", read_mode);
      for i in 0 to 7 loop
         readline(fk, l);
         read(l, s2);
         wait until rising_edge(clk);
         key_we   <= '1';
         key_addr <= to_unsigned(i, 3);
         key_data <= std_logic_vector(to_unsigned(hex2int(s2), 8));
      end loop;
      file_close(fk);
      wait until rising_edge(clk);
      key_we <= '0';
      wait until rising_edge(clk);
      reset <= '0';
      wait until rising_edge(clk);

      file_open(fv, DIR & "/cat702_" & integer'image(N) & ".vec", read_mode);
      while not endfile(fv) loop
         readline(fv, l);
         read(l, c);
         if c = 'S' then
            read(l, c);  -- space
            read(l, c);
            if c = '0' then sel_n <= '0'; else sel_n <= '1'; end if;
            nsel := nsel + 1;
            wait until rising_edge(clk);
            wait until rising_edge(clk);
         elsif c = 'B' then
            read(l, c);
            read(l, s2); tx := hex2int(s2);
            read(l, c);
            read(l, s2); rx := hex2int(s2);
            txv := std_logic_vector(to_unsigned(tx, 8));
            for i in 0 to 7 loop
               txd     <= txv(i);
               bit_stb <= '1';
               wait until falling_edge(clk);
               got(i)  := dataout;
               wait until rising_edge(clk);
               bit_stb <= '0';
               if (i mod 3) = 0 then wait until rising_edge(clk); end if;   -- uneven bit spacing
            end loop;
            nb := nb + 1;
            if to_integer(unsigned(got)) /= rx then
               nbad := nbad + 1;
               if nbad <= 5 then
                  report "byte " & integer'image(nb) & ": tx " & integer'image(tx) &
                         " MAME " & integer'image(rx) & " RTL " & integer'image(to_integer(unsigned(got)));
               end if;
            end if;
         end if;
      end loop;
      file_close(fv);
      report "cat702_" & integer'image(N) & ": select edges " & integer'image(nsel) &
             ", bytes " & integer'image(nb) & ", mismatches " & integer'image(nbad);
      assert nbad = 0 report "CAT702 replay FAILED" severity failure;
      assert nb > 0 report "no bytes replayed" severity failure;
      report "CAT702 replay PASSED";
      done <= true;
      wait;
   end process;

end architecture;
