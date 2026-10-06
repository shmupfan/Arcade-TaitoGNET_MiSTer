-- Equivalence check for gte_mac123 NARROW_MUL = 1, 2 or 3 (generic NM) against the upstream 32x32
-- multiply (NARROW_MUL = 0). For NM = 3 the operands of each request are also
-- presented on MACmul one clock before the request (as gte.vhd does), and
-- some requests are held for a clock with the operands not re-registered (as
-- MACreq is held while ce = 0). Requests are drawn from the operand forms gte.vhd
-- issues (see docs/cpu_rate_probe.md): two operands that fit 18 bits signed,
-- or a 32-bit operand times 1, 10h, 1000h or 10000h, with random add, sub,
-- swap, shift, saturation and accumulate flags. All outputs compared every
-- clock.
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use work.pGTE.all;

entity tb_mac_narrow is
   generic (N : integer := 2000000; NM : integer := 1);   -- NM: NARROW_MUL variant under test
end entity;

architecture sim of tb_mac_narrow is
   signal clk  : std_logic := '0';
   signal req  : tMAC123req;
   signal mul  : tMAC123mul := MAC123mul_none;
   type tOut is record
      mac_result : signed(31 downto 0); mac_wb : std_logic; ir_result : signed(15 downto 0); ir_wb : std_logic;
      macLast : signed(44 downto 0); macShifted : signed(31 downto 0); uf, ovf, flagIR : std_logic;
   end record;
   signal a, b : tOut;
   signal done : boolean := false;
begin
   clk <= not clk after 5 ns when not done;

   ia : entity work.gte_mac123 generic map (NARROW_MUL => 0) port map (clk, req, a.mac_result, a.mac_wb, a.ir_result, a.ir_wb, a.macLast, a.macShifted, a.uf, a.ovf, a.flagIR);
   ib : entity work.gte_mac123 generic map (NARROW_MUL => NM) port map (clk, req, b.mac_result, b.mac_wb, b.ir_result, b.ir_wb, b.macLast, b.macShifted, b.uf, b.ovf, b.flagIR, MACmul => mul);

   process
      variable s1, s2 : positive := 12345;
      variable r      : real;
      variable errs   : integer := 0;
      variable forms  : integer;
      impure function rnd(bits : integer) return signed is
         variable v : signed(bits - 1 downto 0);
      begin
         for i in 0 to bits - 1 loop
            uniform(s1, s2, r);
            if r < 0.5 then v(i) := '0'; else v(i) := '1'; end if;
         end loop;
         return v;
      end function;
      impure function bit1 return std_logic is
      begin
         uniform(s1, s2, r);
         if r < 0.5 then return '0'; else return '1'; end if;
      end function;
      impure function pick(k : integer) return integer is
      begin
         uniform(s1, s2, r);
         return integer(floor(r * real(k)));
      end function;
      constant P2 : tMAC123req := (to_signed(0, 32), to_signed(0, 32), to_signed(0, 45), '0', '0', '0', '0', '0', '0', '0', '0', '0', '0');
      variable q, qn  : tMAC123req;
      variable form   : integer;
      variable formN  : integer;
      variable holds  : integer := 0;
      procedure draw(q : out tMAC123req; f : out integer) is
         variable form : integer;
      begin
         q := P2;
         form := pick(6);
         f    := form;
         case form is
            when 0 => q.mul1 := resize(rnd(16), 32); q.mul2 := resize(rnd(16), 32);                  -- matrix x vector, IR x IR
            when 1 => q.mul1 := resize(rnd(16), 32); q.mul2 := signed(x"000000" & unsigned(rnd(8)));  -- IR x RGBC byte
            when 2 => q.mul1 := signed(x"000000" & unsigned(rnd(8))); q.mul2 := x"00010000";          -- colour x 10000h
            when 3 => q.mul1 := rnd(32); q.mul2 := x"00001000";                                       -- FC, BK, translate, MAC x 1000h
            when 4 => q.mul1 := rnd(32); q.mul2 := x"00000010";                                       -- mac_result x 10h
            when others => q.mul1 := rnd(32); q.mul2 := x"00000001";                                  -- MAC x 1
         end case;
         case pick(4) is
            when 0 => q.add := to_signed(0, 45);
            when 1 => q.add := resize(rnd(32), 33) & x"000";
            when 2 => q.add := rnd(45);
            when others => q.add := resize(rnd(20), 45);
         end case;
         q.sub := bit1; q.swap := bit1; q.saveShifted := bit1; q.useIR := bit1; q.IRshift := bit1;
         q.IRshiftFlag := bit1; q.satIR := bit1; q.satIRFlag := bit1; q.useResult := bit1;
         if pick(8) = 0 then q.trigger := '0'; else q.trigger := '1'; end if;
      end procedure;
      -- NARROW_MUL = 3 operands of request q (form f), registered by the unit when ena = '1'
      function mulOf(q : tMAC123req; f : integer; ena : std_logic) return tMAC123mul is
         variable m : tMAC123mul;
         variable k : integer;
      begin
         m := MAC123mul_none;
         m.ena := ena;
         if (f <= 1) then
            m.mul1 := q.mul1(17 downto 0);
            m.mul2 := q.mul2(17 downto 0);
         else
            case f is
               when 2      => k := 16;
               when 3      => k := 12;
               when 4      => k := 4;
               when others => k := 0;
            end case;
            m.isShift := '1';
            m.shifted := resize(shift_left(resize(q.mul1, 64), k), 45);
         end if;
         return m;
      end function;
   begin
      req <= P2;
      draw(qn, formN);
      mul <= mulOf(qn, formN, qn.trigger);
      wait until rising_edge(clk);
      for i in 1 to N loop
         q    := qn;
         form := formN;
         req  <= q;
         if (q.trigger = '1' and pick(16) = 0) then
            qn  := q;                                  -- held: same request again, operands not re-registered
            mul <= mulOf(qn, formN, '0');
            holds := holds + 1;
         else
            draw(qn, formN);
            mul <= mulOf(qn, formN, qn.trigger);
         end if;
         wait until rising_edge(clk);
         wait for 1 ns;
         if a /= b then
            errs := errs + 1;
            if errs <= 10 then
               report "MISMATCH at " & integer'image(i) & " mul1=" & to_hstring(q.mul1) & " mul2=" & to_hstring(q.mul2) &
                      " A=" & to_hstring(a.macLast) & "/" & to_hstring(a.mac_result) & " B=" & to_hstring(b.macLast) & "/" & to_hstring(b.mac_result);
            end if;
         end if;
      end loop;
      report "DONE NM=" & integer'image(NM) & " requests=" & integer'image(N) & " held=" & integer'image(holds) & " mismatches=" & integer'image(errs);
      done <= true;
      wait;
   end process;
end architecture;
