library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 
use STD.textio.all;

use work.pGTE.all;

entity gte_mac123 is
   generic
   (
      -- 1 = G-NET timing option: every request gte.vhd makes is either two
      -- operands that fit 18 bits signed (16-bit registers, 8-bit colours) or
      -- a wide operand times 1, 10h, 1000h or 10000h. The product is then an
      -- 18x18 multiply or a shift, equal to the 32x32 multiply for those
      -- requests, and shorter in time. 0 = upstream 32x32 multiply.
      -- 2 = as 1, with the add done for both products in parallel and the
      -- select after the adders (moves the select out of the multiply path).
      -- 3 = G-NET 100 MHz option: gte.vhd presents the 18x18 operands (or the
      -- shifted wide operand) in MACmul in the cycle that writes the request;
      -- the product is registered then, so the trigger cycle only selects and
      -- adds (one adder, sign chosen by inverting an input). mul1/mul2 of
      -- MACreq are unused.
      NARROW_MUL     : integer := 0
   );
   port 
   (
      clk2x          : in  std_logic;
      MACreq         : in  tMAC123req;
      mac_result     : out signed(31 downto 0);
      mac_writeback  : out std_logic := '0';
      ir_result      : out signed(15 downto 0);
      ir_writeback   : out std_logic := '0';
      macLast        : out signed(44 downto 0);
      macShifted     : out signed(31 downto 0);
      flagMacUF      : out std_logic;
      flagMacOF      : out std_logic;
      flagIR         : out std_logic;
      MACmul         : in  tMAC123mul := MAC123mul_none
   );
end entity;

architecture arch of gte_mac123 is
   
   constant MINVAL      : signed(44 downto 0) := '1' & x"80000000000";
   constant MAXVAL      : signed(44 downto 0) := '0' & x"7FFFFFFFFFF";
   
   signal macResult_1   : signed(44 downto 0);
   
   signal checkOvf      : std_logic := '0';
   
   signal IRshift_1     : std_logic; 
   signal IRshiftFlag_1 : std_logic; 
   signal satIR_1       : std_logic; 
   signal satIRFlag_1   : std_logic; 

   -- NARROW_MUL = 3
   signal prodN3        : signed(35 downto 0);
   signal prodS3        : signed(44 downto 0);
   signal isShift3      : std_logic;

begin 

   flagMacUF <= '1' when (checkOvf = '1' and macResult_1 < MINVAL) else '0';
   flagMacOF <= '1' when (checkOvf = '1' and macResult_1 > MAXVAL) else '0';

   process (clk2x)
      variable macResult : signed(44 downto 0);
      variable addVal    : signed(44 downto 0);
      variable IRresult  : signed(31 downto 0);
      variable prodN     : signed(44 downto 0);
      variable prodS     : signed(44 downto 0);
      variable isShift   : boolean;
      variable opP       : signed(44 downto 0);
      variable opA       : signed(44 downto 0);
      variable sum46     : signed(45 downto 0);
      function addsub(p, a : signed(44 downto 0); sub, swap : std_logic) return signed is
      begin
         if (swap = '1' and sub = '1') then
            return p - a;
         elsif (sub = '1') then
            return a - p;
         else
            return a + p;
         end if;
      end function;
   begin
      if rising_edge(clk2x) then
      
         mac_writeback  <= '0';
         ir_writeback   <= '0';
         checkOvf       <= '0';
         
         if (NARROW_MUL = 3 and MACmul.ena = '1') then
            prodN3   <= MACmul.mul1 * MACmul.mul2;
            prodS3   <= MACmul.shifted;
            isShift3 <= MACmul.isShift;
         end if;
         
         if (MACreq.trigger = '1') then
            macLast   <= macResult_1;
         
            if (NARROW_MUL = 0) then
               macResult := resize(MACreq.mul1 * MACreq.mul2, 45);
            elsif (NARROW_MUL = 1) then
               case (MACreq.mul2) is
                  when x"00000001" => macResult := resize(resize(MACreq.mul1, 64), 45);
                  when x"00000010" => macResult := resize(shift_left(resize(MACreq.mul1, 64), 4), 45);
                  when x"00001000" => macResult := resize(shift_left(resize(MACreq.mul1, 64), 12), 45);
                  when x"00010000" => macResult := resize(shift_left(resize(MACreq.mul1, 64), 16), 45);
                  when others      => macResult := resize(MACreq.mul1(17 downto 0) * MACreq.mul2(17 downto 0), 45);
               end case;
            end if;
         
            addVal := MACreq.add;
            if (MACreq.useResult = '1') then
               addVal := resize(macResult_1(43 downto 0), 45);
            end if;
         
            if (NARROW_MUL = 3) then
               -- a + p, a - p = a + not p + 1, p - a = p + not a + 1: one adder
               if (isShift3 = '1') then
                  opP := prodS3;
               else
                  opP := resize(prodN3, 45);
               end if;
               opA := addVal;
               if (MACreq.sub = '1' and MACreq.swap = '0') then
                  opP := not opP;
               end if;
               if (MACreq.sub = '1' and MACreq.swap = '1') then
                  opA := not opA;
               end if;
               sum46     := (opA & '1') + (opP & MACreq.sub);
               macResult := sum46(45 downto 1);
            elsif (NARROW_MUL = 2) then
               isShift := true;
               case (MACreq.mul2) is
                  when x"00000001" => prodS := resize(resize(MACreq.mul1, 64), 45);
                  when x"00000010" => prodS := resize(shift_left(resize(MACreq.mul1, 64), 4), 45);
                  when x"00001000" => prodS := resize(shift_left(resize(MACreq.mul1, 64), 12), 45);
                  when x"00010000" => prodS := resize(shift_left(resize(MACreq.mul1, 64), 16), 45);
                  when others      => prodS := (others => '0'); isShift := false;
               end case;
               prodN := resize(MACreq.mul1(17 downto 0) * MACreq.mul2(17 downto 0), 45);
               if (isShift) then
                  macResult := addsub(prodS, addVal, MACreq.sub, MACreq.swap);
               else
                  macResult := addsub(prodN, addVal, MACreq.sub, MACreq.swap);
               end if;
            elsif (MACreq.swap = '1' and MACreq.sub = '1') then
               macResult := macResult - addVal;
            elsif (MACreq.sub = '1') then
               macResult := addVal - macResult;
            else
               macResult := addVal + macResult;
            end if;
            
            macResult_1   <= macResult(44 downto 0);
            
            if (MACreq.saveShifted = '1') then
               mac_result <= macResult(43 downto 12);
            else
               mac_result <= macResult(31 downto 0);
            end if;
            mac_writeback <= '1';
            
            macShifted <= macResult(43 downto 12);
            
            checkOvf <= '1';
            
            if (MACreq.useIR) then
               ir_writeback <= '1';
            end if;
            
            IRshift_1     <= MACreq.IRshift;  
            IRshiftFlag_1 <= MACreq.IRshiftFlag;  
            satIR_1       <= MACreq.satIR;    
            satIRFlag_1   <= MACreq.satIRFlag;
            
         end if;
         
      end if;
   end process;
   
   process (macResult_1, ir_writeback, IRshift_1, IRshiftFlag_1, satIR_1, satIRFlag_1)
      variable IRresult  : signed(31 downto 0);
   begin
   
      flagIR    <= '0';
      ir_result <= (others => '0');
      
      if (ir_writeback = '1') then
         -- result
         IRresult := macResult_1(31 downto 0);
         if (IRshift_1 = '1') then
            IRresult := macResult_1(43 downto 12);
         end if;
         
         ir_result    <= IRresult(15 downto 0);
         if (satIR_1 = '1' and IRresult < 0) then
            ir_result <= (others => '0');
         elsif (satIR_1 = '0' and IRresult < -32768) then
            ir_result <= x"8000";
         elsif (IRresult > 16#7FFF#) then
            ir_result <= x"7FFF";
         end if;
         
         -- flags
         IRresult := macResult_1(31 downto 0);
         if (IRshiftFlag_1 = '1') then
            IRresult := macResult_1(43 downto 12);
         end if;
         
         if (satIRFlag_1 = '1' and IRresult < 0) then
            flagIR <= '1';
         elsif (satIRFlag_1 = '0' and IRresult < -32768) then
            flagIR <= '1';
         elsif (IRresult > 16#7FFF#) then
            flagIR <= '1';
         end if;
      end if;
         
   end process;

end architecture;





