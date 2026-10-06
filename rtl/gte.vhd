library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all; 
use STD.textio.all;

use work.pGTE.all;

entity gte is
   generic
   (
      NARROW_MUL           : integer := 0
   );
   port 
   (
      clk1x                : in  std_logic;
      clk2x                : in  std_logic;
      clk2xIndex           : in  std_logic;
      ce                   : in  std_logic;
      reset                : in  std_logic;
      
      WIDESCREEN           : in  std_logic_vector(1 downto 0);
      TURBO                : in  std_logic;
      
      gte_busy             : out std_logic;
      gte_readAddr         : in  unsigned(5 downto 0);
      gte_readData         : out unsigned(31 downto 0);
      gte_readEna          : in  std_logic;
      gte_writeAddr_in     : in  unsigned(5 downto 0);
      gte_writeData_in     : in  unsigned(31 downto 0);
      gte_writeEna_in      : in  std_logic; 
      gte_cmdData          : in  unsigned(31 downto 0);
      gte_cmdEna           : in  std_logic;
      
      loading_savestate    : in  std_logic;
      SS_reset             : in  std_logic;
      SS_DataWrite         : in  std_logic_vector(31 downto 0);
      SS_Adr               : in  unsigned(5 downto 0);
      SS_wren              : in  std_logic;
      SS_rden              : in  std_logic;
      SS_DataRead          : out std_logic_vector(31 downto 0);
      SS_idle              : out std_logic;
      
      debug_firstGTE       : out std_logic
   );
end entity;

architecture arch of gte is
   
   -- input
   signal gte_writeAddr : unsigned(5 downto 0);
   signal gte_writeData : unsigned(31 downto 0);
   signal gte_writeEna  : std_logic;

   -- GTE data regs
   signal REG_V0X  : signed(15 downto 0);
   signal REG_V0Y  : signed(15 downto 0);
   signal REG_V0Z  : signed(15 downto 0);
   signal REG_V1X  : signed(15 downto 0);
   signal REG_V1Y  : signed(15 downto 0);
   signal REG_V1Z  : signed(15 downto 0);
   signal REG_V2X  : signed(15 downto 0);
   signal REG_V2Y  : signed(15 downto 0);
   signal REG_V2Z  : signed(15 downto 0);
   signal REG_RGBC : unsigned(31 downto 0);
   signal REG_OTZ  : unsigned(15 downto 0);
   signal REG_IR0  : signed(15 downto 0);
   signal REG_IR1  : signed(15 downto 0);
   signal REG_IR2  : signed(15 downto 0);
   signal REG_IR3  : signed(15 downto 0);
   signal REG_SX0  : signed(15 downto 0);
   signal REG_SY0  : signed(15 downto 0);
   signal REG_SX1  : signed(15 downto 0);
   signal REG_SY1  : signed(15 downto 0);
   signal REG_SX2  : signed(15 downto 0);
   signal REG_SY2  : signed(15 downto 0);
   signal REG_SZ0  : unsigned(15 downto 0);
   signal REG_SZ1  : unsigned(15 downto 0);
   signal REG_SZ2  : unsigned(15 downto 0);
   signal REG_SZ3  : unsigned(15 downto 0);
   signal REG_RGB0 : unsigned(31 downto 0);
   signal REG_RGB1 : unsigned(31 downto 0);
   signal REG_RGB2 : unsigned(31 downto 0);
   signal REG_RES1 : unsigned(31 downto 0);
   signal REG_MAC0 : signed(31 downto 0);
   signal REG_MAC1 : signed(31 downto 0);
   signal REG_MAC2 : signed(31 downto 0);
   signal REG_MAC3 : signed(31 downto 0);
   signal REG_IRGB : unsigned(14 downto 0);
   signal REG_ORGB : unsigned(14 downto 0);
   signal REG_LZCS : signed(31 downto 0);
   signal REG_LZCR : signed(31 downto 0);
   
   -- GTE control regs
   signal REG_RT11  : signed(15 downto 0);
   signal REG_RT12  : signed(15 downto 0);
   signal REG_RT13  : signed(15 downto 0);
   signal REG_RT21  : signed(15 downto 0);
   signal REG_RT22  : signed(15 downto 0);
   signal REG_RT23  : signed(15 downto 0);
   signal REG_RT31  : signed(15 downto 0);
   signal REG_RT32  : signed(15 downto 0);
   signal REG_RT33  : signed(15 downto 0);
   signal REG_TR0   : unsigned(31 downto 0);
   signal REG_TR1   : unsigned(31 downto 0);
   signal REG_TR2   : unsigned(31 downto 0);
   signal REG_LL11  : signed(15 downto 0);
   signal REG_LL12  : signed(15 downto 0);
   signal REG_LL13  : signed(15 downto 0);
   signal REG_LL21  : signed(15 downto 0);
   signal REG_LL22  : signed(15 downto 0);
   signal REG_LL23  : signed(15 downto 0);
   signal REG_LL31  : signed(15 downto 0);
   signal REG_LL32  : signed(15 downto 0);
   signal REG_LL33  : signed(15 downto 0);
   signal REG_BK0   : unsigned(31 downto 0);
   signal REG_BK1   : unsigned(31 downto 0);
   signal REG_BK2   : unsigned(31 downto 0);
   signal REG_LC11  : signed(15 downto 0);
   signal REG_LC12  : signed(15 downto 0);
   signal REG_LC13  : signed(15 downto 0);
   signal REG_LC21  : signed(15 downto 0);
   signal REG_LC22  : signed(15 downto 0);
   signal REG_LC23  : signed(15 downto 0);
   signal REG_LC31  : signed(15 downto 0);
   signal REG_LC32  : signed(15 downto 0);
   signal REG_LC33  : signed(15 downto 0);
   signal REG_FC0   : unsigned(31 downto 0);
   signal REG_FC1   : unsigned(31 downto 0);
   signal REG_FC2   : unsigned(31 downto 0);
   signal REG_OFX   : unsigned(31 downto 0);
   signal REG_OFY   : unsigned(31 downto 0);
   signal REG_H     : signed(15 downto 0);
   signal REG_DQA   : signed(15 downto 0);
   signal REG_DQB   : unsigned(31 downto 0);
   signal REG_ZSF3  : signed(15 downto 0);
   signal REG_ZSF4  : signed(15 downto 0);
   signal REG_FLAG  : unsigned(31 downto 0);
   
   -- widescreen
   signal IR1aspect     : signed(16 downto 0);
   signal IR1aspect_1   : signed(16 downto 0);
   signal IR1aspect_2   : signed(16 downto 0);
  
   -- calculation
   type tstate is
   (
      IDLE,
      CALC_RTPS,
      CALC_NCLIP,
      CALC_OP,
      CALC_DPCS,
      CALC_INTPL,
      CALC_MVMVA,
      CALC_NCDS,
      CALC_CDP,
      CALC_NCDT,
      CALC_NCCS,
      CALC_CC,
      CALC_NCS,
      CALC_NCT,
      CALC_SQR,
      CALC_DPCL,
      CALC_DPCT,
      CALC_AVSZ3,
      CALC_AVSZ4,
      CALC_RTPT,
      CALC_GPF,
      CALC_GPL,
      CALC_NCCT
   );
   signal state : tstate := IDLE;
   
   signal calcStep         : integer range 0 to 63;
   signal batchCount       : integer range 0 to 2;
   signal turbomode        : std_logic := '0';      
         
   signal cmdShift         : std_logic;
   signal cmdsatIR         : std_logic;
   signal cmdMM            : unsigned(1 downto 0);
   signal cmdMV            : unsigned(1 downto 0);
   signal cmdTV            : unsigned(1 downto 0);
   
   signal calcColor        : unsigned(23 downto 0);
   signal pushRGBfromMAC   : std_logic := '0';
   signal setOTZ           : std_logic := '0';
   signal pushSZandDivide  : std_logic := '0';
   signal pushSXY          : std_logic := '0';
   
   signal REG_IR2_1        : signed(15 downto 0);
   signal REG_IR2_2        : signed(15 downto 0);
   
   signal matrix00         : signed(15 downto 0);
   signal matrix01         : signed(15 downto 0);
   signal matrix02         : signed(15 downto 0);
   signal matrix10         : signed(15 downto 0);
   signal matrix11         : signed(15 downto 0);
   signal matrix12         : signed(15 downto 0);
   signal matrix20         : signed(15 downto 0);
   signal matrix21         : signed(15 downto 0);
   signal matrix22         : signed(15 downto 0);
            
   signal vector0          : signed(15 downto 0);
   signal vector1          : signed(15 downto 0);
   signal vector2          : signed(15 downto 0);
         
   signal translate0       : signed(31 downto 0);
   signal translate1       : signed(31 downto 0);
   signal translate2       : signed(31 downto 0);
         
   signal shiftvalue       : signed(31 downto 0);
   
   -- MACs
   signal MAC0req          : tMAC0req;
   signal mac0_result      : signed(34 downto 0);
   signal mac0_writeback   : std_logic;
   signal ir0_result       : signed(15 downto 0);
   signal ir0_writeback    : std_logic;
   signal mac0Last         : signed(34 downto 0);
   signal flagMac0UF       : std_logic;
   signal flagMac0OF       : std_logic;
   signal flagIR0          : std_logic;
   
   signal MAC1req          : tMAC123req;
   signal mac1_result      : signed(31 downto 0);
   signal mac1_writeback   : std_logic;
   signal ir1_result       : signed(15 downto 0);
   signal ir1_writeback    : std_logic;
   signal mac1Last         : signed(44 downto 0);
   signal flagMac1UF       : std_logic;
   signal flagMac1OF       : std_logic;
   signal flagIR1          : std_logic;
   
   signal MAC2req          : tMAC123req;
   signal mac2_result      : signed(31 downto 0);
   signal mac2_writeback   : std_logic;
   signal ir2_result       : signed(15 downto 0);
   signal ir2_writeback    : std_logic;
   signal mac2Last         : signed(44 downto 0);
   signal flagMac2UF       : std_logic;
   signal flagMac2OF       : std_logic;
   signal flagIR2          : std_logic;
   
   signal MAC3req          : tMAC123req;
   signal mac3_result      : signed(31 downto 0);
   signal mac3_writeback   : std_logic;
   signal ir3_result       : signed(15 downto 0);
   signal ir3_writeback    : std_logic;
   signal mac3Last         : signed(44 downto 0);
   signal mac3Shifted      : signed(31 downto 0);
   signal flagMac3UF       : std_logic;
   signal flagMac3OF       : std_logic;
   signal flagIR3          : std_logic;
   
   -- divide
   signal div_trigger      : std_logic;
   signal div_lhs          : unsigned(15 downto 0);
   signal div_rhs          : unsigned(15 downto 0);
   signal div_result       : unsigned(16 downto 0);
   signal div_Error        : std_logic;
  
   -- debug
   signal debugCnt         : unsigned(31 downto 0);
   
   -- savestates
   signal SSreadAddr       : unsigned(5 downto 0);
   signal SSrden           : std_logic;
   signal SS_readData      : std_logic_vector(31 downto 0);
  
   --##############################################################
   -- NARROW_MUL = 3 (G-NET, GTE at 100 MHz): the MAC requests of each step are
   -- decoded one step early into req3 (operand selects, one-hot). In the
   -- request cycle the selected operands go straight into the multipliers,
   -- whose products are registered in the MAC units, so the trigger cycle only
   -- adds. Same requests, same steps, same results (sim/gte_equiv).
   --##############################################################
   type tReq3 is record
      t                                                               : std_logic;  -- MAC1-3 request
      aRT1, aRT2, aRT3, aOP0, aOP1, aIR, aM0, aM1, aM2                : std_logic;  -- 18 x 18 operand 1
      aLL1, aLL2, aLL3, aLC1, aLC2, aLC3                              : std_logic;
      bV0X, bV0Y, bV0Z, bV1X, bV1Y, bV1Z, bV2X, bV2Y, bV2Z            : std_logic;  -- 18 x 18 operand 2
      bOP0, bOP1, bIR0, bIR1, bIR2, bIR3, bVec0, bVec1, bVec2, bRGBC  : std_logic;
      bIRi                                                            : std_logic;
      sh, wCol, wFC, wIR, wTR, wBK, wRes, wMAC                        : std_logic;  -- wide operand times 2^k
      k0, k4, k12, k16, kGPL                                          : std_logic;
      addTR, addLast                                                  : std_logic;
      sub, swap, svSh, useIR, IRs, IRsF, sat, satF, r2, uRes          : std_logic;  -- svSh, IRs, IRsF: cmdShift; sat, satF: cmdsatIR
      t0                                                              : std_logic;  -- MAC0 request
      a0Asp, a0Asp1, a0Asp2, a0IR2, a0IR2_1, a0IR2_2, a0DQA           : std_logic;
      a0SX0, a0SX1, a0SX2, a0SZ0, a0SZ1, a0SZ2, a0SZ3                 : std_logic;
      b0Div, b0SY0, b0SY1, b0SY2, b0ZSF3, b0ZSF4                      : std_logic;
      add0OFX, add0OFY, add0DQB, sub0, useIR0, IRs0, cOvf0, uRes0     : std_logic;
      xA, xT, lp                                                      : std_logic;  -- step: exit, exit if turbo, next vertex (or exit if turbo after the last)
   end record;
   constant REQ3_NONE : tReq3 := (others => '0');

   signal req3             : tReq3 := REQ3_NONE;
   signal procEna3         : std_logic;
   signal MAC0req3         : tMAC0req;
   signal MAC1req3         : tMAC123req;
   signal MAC2req3         : tMAC123req;
   signal MAC3req3         : tMAC123req;
   signal MAC0mul3         : tMAC0mul   := MAC0mul_none;
   signal MAC1mul3         : tMAC123mul := MAC123mul_none;
   signal MAC2mul3         : tMAC123mul := MAC123mul_none;
   signal MAC3mul3         : tMAC123mul := MAC123mul_none;
   signal MAC0req_u        : tMAC0req;
   signal MAC1req_u        : tMAC123req;
   signal MAC2req_u        : tMAC123req;
   signal MAC3req_u        : tMAC123req;

   function divRetime(n : integer) return integer is
   begin
      if (n = 3) then return 1; end if;
      return 0;
   end function;

   procedure r3cmd(r : inout tReq3) is   -- svSh, IRs, IRsF = cmdShift, useIR = 1, satIR, satIRF = cmdsatIR
   begin
      r.svSh := '1'; r.useIR := '1'; r.IRs := '1'; r.IRsF := '1'; r.sat := '1'; r.satF := '1';
   end procedure;

   procedure r3RT(r : inout tReq3; j, v : integer) is   -- RTPS/RTPT: RTj1..3 x V(v)
   begin
      r.t := '1';
      case (j) is
         when 1      => r.aRT1 := '1'; r.addTR := '1';
         when 2      => r.aRT2 := '1'; r.uRes  := '1';
         when others => r.aRT3 := '1'; r.uRes  := '1'; r.r2 := '1'; r3cmd(r);
      end case;
      case (v * 3 + j) is
         when 1      => r.bV0X := '1';
         when 2      => r.bV0Y := '1';
         when 3      => r.bV0Z := '1';
         when 4      => r.bV1X := '1';
         when 5      => r.bV1Y := '1';
         when 6      => r.bV1Z := '1';
         when 7      => r.bV2X := '1';
         when 8      => r.bV2Y := '1';
         when others => r.bV2Z := '1';
      end case;
   end procedure;

   procedure r3shift(r : inout tReq3) is   -- wide operand times 1000h, no flags
   begin
      r.t := '1'; r.sh := '1'; r.k12 := '1';
   end procedure;

   procedure r3FC(r : inout tReq3) is   -- FC x 1000h, p - a, InterpolateColor
   begin
      r3shift(r); r.wFC := '1';
      r.sub := '1'; r.swap := '1'; r.svSh := '1'; r.useIR := '1'; r.IRs := '1'; r.IRsF := '1'; r.uRes := '1';
   end procedure;

   procedure r3IR0(r : inout tReq3; last : boolean; uRes : std_logic) is   -- IR x IR0 (+ macLast)
   begin
      r.t := '1'; r.aIR := '1'; r.bIR0 := '1'; r3cmd(r); r.uRes := uRes;
      if (last) then r.addLast := '1'; end if;
   end procedure;

   procedure r3LL(r : inout tReq3; j : integer) is   -- LLj1..3 x vector(j - 1)
   begin
      r.t := '1';
      case (j) is
         when 1      => r.aLL1 := '1'; r.bVec0 := '1';
         when 2      => r.aLL2 := '1'; r.bVec1 := '1'; r.uRes := '1';
         when others => r.aLL3 := '1'; r.bVec2 := '1'; r.uRes := '1'; r3cmd(r);
      end case;
   end procedure;

   procedure r3LC(r : inout tReq3; j : integer) is   -- LCj1..3 x IRj
   begin
      r.t := '1'; r.uRes := '1';
      case (j) is
         when 1      => r.aLC1 := '1'; r.bIR1 := '1';
         when 2      => r.aLC2 := '1'; r.bIR2 := '1';
         when others => r.aLC3 := '1'; r.bIR3 := '1'; r3cmd(r);
      end case;
   end procedure;

   procedure r3P(r : inout tReq3) is   -- IR x RGBC byte
   begin
      r.t := '1'; r.aIR := '1'; r.bRGBC := '1';
   end procedure;

   procedure r3S(r : inout tReq3; cmd : boolean) is   -- mac_result x 10h
   begin
      r.t := '1'; r.sh := '1'; r.k4 := '1'; r.wRes := '1';
      if (cmd) then r3cmd(r); end if;
   end procedure;

   procedure r30(r : inout tReq3; uRes, cOvf : std_logic) is   -- MAC0 request, add 0
   begin
      r.t0 := '1'; r.uRes0 := uRes; r.cOvf0 := cOvf;
   end procedure;

   -- requests of state st at calcStep s (exactly the MACreq assignments of the case statement);
   -- every row call has constant arguments, so this is a plain decode of st and s
   function req3At(st : tstate; s : integer; tv : unsigned(1 downto 0)) return tReq3 is
      variable r : tReq3;
   begin
      r := REQ3_NONE;
      case (st) is
         when CALC_RTPS =>
            case (s) is
               when 0         => r3RT(r, 1, 0);
               when 1         => r3RT(r, 2, 0);
               when 2         => r3RT(r, 3, 0);
               when 12        => r30(r, '0', '1'); r.a0Asp := '1'; r.b0Div := '1'; r.add0OFX := '1';
               when 13        => r30(r, '0', '1'); r.a0IR2 := '1'; r.b0Div := '1'; r.add0OFY := '1';
               when 15        => r30(r, '0', '1'); r.a0DQA := '1'; r.b0Div := '1'; r.add0DQB := '1'; r.useIR0 := '1'; r.IRs0 := '1';
               when others    => null;
            end case;

         when CALC_RTPT =>
            case (s) is
               when 0         => r3RT(r, 1, 0);
               when 1         => r3RT(r, 2, 0);
               when 2         => r3RT(r, 3, 0);
               when 3         => r3RT(r, 1, 1);
               when 4         => r3RT(r, 2, 1);
               when 5         => r3RT(r, 3, 1);
               when 6         => r3RT(r, 1, 2);
               when 7         => r3RT(r, 2, 2);
               when 8         => r3RT(r, 3, 2);
               when 12        => r30(r, '0', '1'); r.a0Asp1  := '1'; r.b0Div := '1'; r.add0OFX := '1';
               when 13        => r30(r, '0', '1'); r.a0IR2_1 := '1'; r.b0Div := '1'; r.add0OFY := '1';
               when 15        => r30(r, '0', '1'); r.a0Asp2  := '1'; r.b0Div := '1'; r.add0OFX := '1';
               when 16        => r30(r, '0', '1'); r.a0IR2_2 := '1'; r.b0Div := '1'; r.add0OFY := '1';
               when 18        => r30(r, '0', '1'); r.a0Asp   := '1'; r.b0Div := '1'; r.add0OFX := '1';
               when 19        => r30(r, '0', '1'); r.a0IR2   := '1'; r.b0Div := '1'; r.add0OFY := '1';
               when 21        => r30(r, '0', '1'); r.a0DQA   := '1'; r.b0Div := '1'; r.add0DQB := '1'; r.useIR0 := '1'; r.IRs0 := '1';
               when others    => null;
            end case;

         when CALC_NCLIP =>
            case (s) is
               when 0         => r30(r, '0', '0'); r.a0SX0 := '1'; r.b0SY1 := '1';
               when 1         => r30(r, '1', '0'); r.a0SX1 := '1'; r.b0SY2 := '1';
               when 2         => r30(r, '1', '0'); r.a0SX2 := '1'; r.b0SY0 := '1';
               when 3         => r30(r, '1', '0'); r.a0SX0 := '1'; r.b0SY2 := '1'; r.sub0 := '1';
               when 4         => r30(r, '1', '0'); r.a0SX1 := '1'; r.b0SY0 := '1'; r.sub0 := '1';
               when 5         => r30(r, '1', '1'); r.a0SX2 := '1'; r.b0SY1 := '1'; r.sub0 := '1';
               when others    => null;
            end case;

         when CALC_OP =>
            case (s) is
               when 0         => r.t := '1'; r.aOP0 := '1'; r.bOP0 := '1';
               when 1         => r.t := '1'; r.aOP1 := '1'; r.bOP1 := '1'; r.sub := '1'; r3cmd(r); r.uRes := '1';
               when others    => null;
            end case;

         when CALC_DPCS | CALC_DPCT =>
            case (s) is
               when 0         => r.t := '1'; r.sh := '1'; r.k16 := '1'; r.wCol := '1';
               when 1         => r3FC(r);
               when 4         => r3IR0(r, true, '0');
               when others    => null;
            end case;

         when CALC_INTPL =>
            case (s) is
               when 0         => r3shift(r); r.wIR := '1';
               when 1         => r3FC(r);
               when 4         => r3IR0(r, true, '0');
               when others    => null;
            end case;

         when CALC_MVMVA =>
            case (s) is
               when 1         => r3shift(r); r.wTR := '1';
               when 2         =>
                  r.t := '1'; r.aM0 := '1'; r.bVec0 := '1'; r.uRes := '1';
                  if (tv = "10") then r.useIR := '1'; r.IRs := '1'; r.IRsF := '1'; end if;
               when 3         =>
                  r.t := '1'; r.aM1 := '1'; r.bVec1 := '1';
                  if (tv /= "10") then r.uRes := '1'; end if;
               when 4         => r.t := '1'; r.aM2 := '1'; r.bVec2 := '1'; r3cmd(r); r.uRes := '1';
               when others    => null;
            end case;

         when CALC_NCDS | CALC_NCDT =>
            case (s) is
               when 1         => r3LL(r, 1);
               when 2         => r3LL(r, 2);
               when 3         => r3LL(r, 3);
               when 4         => r3shift(r); r.wBK := '1';
               when 6         => r3LC(r, 1);
               when 7         => r3LC(r, 2);
               when 8         => r3LC(r, 3);
               when 11        => r3P(r);
               when 13        => r3S(r, false);
               when 14        => r3FC(r);
               when 17        => r3IR0(r, true, '0');
               when others    => null;
            end case;

         when CALC_CDP =>
            case (s) is
               when 0         => r3shift(r); r.wBK := '1';
               when 1         => r3LC(r, 1);
               when 2         => r3LC(r, 2);
               when 3         => r3LC(r, 3);
               when 6         => r3P(r);
               when 8         => r3S(r, false);
               when 9         => r3FC(r);
               when 12        => r3IR0(r, true, '0');
               when others    => null;
            end case;

         when CALC_NCCS | CALC_NCCT =>
            case (s) is
               when 1         => r3LL(r, 1);
               when 2         => r3LL(r, 2);
               when 3         => r3LL(r, 3);
               when 4         => r3shift(r); r.wBK := '1';
               when 6         => r3LC(r, 1);
               when 7         => r3LC(r, 2);
               when 8         => r3LC(r, 3);
               when 11        => r3P(r);
               when 13        => r3S(r, true);
               when others    => null;
            end case;

         when CALC_CC =>
            case (s) is
               when 0         => r3shift(r); r.wBK := '1';
               when 1         => r3LC(r, 1);
               when 2         => r3LC(r, 2);
               when 3         => r3LC(r, 3);
               when 6         => r3P(r);
               when 8         => r3S(r, true);
               when others    => null;
            end case;

         when CALC_NCS | CALC_NCT =>
            case (s) is
               when 1         => r3LL(r, 1);
               when 2         => r3LL(r, 2);
               when 3         => r3LL(r, 3);
               when 4         => r3shift(r); r.wBK := '1';
               when 6         => r3LC(r, 1);
               when 7         => r3LC(r, 2);
               when 8         => r3LC(r, 3);
               when others    => null;
            end case;

         when CALC_SQR =>
            if (s = 0) then r.t := '1'; r.aIR := '1'; r.bIRi := '1'; r3cmd(r); end if;

         when CALC_DPCL =>
            case (s) is
               when 0         => r3P(r);
               when 2         => r3S(r, false);
               when 3         => r3FC(r);
               when 6         => r3IR0(r, true, '0');
               when others    => null;
            end case;

         when CALC_AVSZ3 =>
            case (s) is
               when 0         => r30(r, '0', '1'); r.a0SZ1 := '1'; r.b0ZSF3 := '1';
               when 1         => r30(r, '1', '1'); r.a0SZ2 := '1'; r.b0ZSF3 := '1';
               when 2         => r30(r, '1', '1'); r.a0SZ3 := '1'; r.b0ZSF3 := '1';
               when others    => null;
            end case;

         when CALC_AVSZ4 =>
            case (s) is
               when 0         => r30(r, '0', '1'); r.a0SZ0 := '1'; r.b0ZSF4 := '1';
               when 1         => r30(r, '1', '1'); r.a0SZ1 := '1'; r.b0ZSF4 := '1';
               when 2         => r30(r, '1', '1'); r.a0SZ2 := '1'; r.b0ZSF4 := '1';
               when 3         => r30(r, '1', '1'); r.a0SZ3 := '1'; r.b0ZSF4 := '1';
               when others    => null;
            end case;

         when CALC_GPF =>
            if (s = 0) then r3IR0(r, false, '0'); end if;

         when CALC_GPL =>
            case (s) is
               when 1         => r.t := '1'; r.sh := '1'; r.kGPL := '1'; r.wMAC := '1';
               when 2         => r3IR0(r, false, '1');
               when others    => null;
            end case;

         when others => null;
      end case;

      case (st) is
         when CALC_RTPS             => if (s = 17) then r.xT := '1'; end if; if (s = 25) then r.xA := '1'; end if;
         when CALC_RTPT             => if (s = 23) then r.xT := '1'; end if; if (s = 41) then r.xA := '1'; end if;
         when CALC_NCLIP            => if (s =  7) then r.xT := '1'; end if; if (s = 11) then r.xA := '1'; end if;
         when CALC_OP               => if (s =  3) then r.xT := '1'; end if; if (s =  7) then r.xA := '1'; end if;
         when CALC_DPCS             => if (s =  8) then r.xT := '1'; end if; if (s = 10) then r.xA := '1'; end if;
         when CALC_DPCT             => if (s =  8) then r.lp := '1'; end if; if (s = 10) then r.xA := '1'; end if;
         when CALC_INTPL            => if (s =  8) then r.xT := '1'; end if; if (s = 10) then r.xA := '1'; end if;
         when CALC_MVMVA            => if (s =  6) then r.xT := '1'; end if; if (s = 10) then r.xA := '1'; end if;
         when CALC_NCDS             => if (s = 21) then r.xT := '1'; end if; if (s = 33 or s = 39) then r.xA := '1'; end if;
         when CALC_NCDT             => if (s = 21) then r.lp := '1'; end if; if (s = 39) then r.xA := '1'; end if;
         when CALC_CDP              => if (s = 16) then r.xT := '1'; end if; if (s = 20) then r.xA := '1'; end if;
         when CALC_NCCS             => if (s = 17) then r.xT := '1'; end if; if (s = 29 or s = 37) then r.xA := '1'; end if;
         when CALC_NCCT             => if (s = 17) then r.lp := '1'; end if; if (s = 37) then r.xA := '1'; end if;
         when CALC_CC               => if (s = 12) then r.xT := '1'; end if; if (s = 16) then r.xA := '1'; end if;
         when CALC_NCS              => if (s = 12) then r.xT := '1'; end if; if (s = 22 or s = 28) then r.xA := '1'; end if;
         when CALC_NCT              => if (s = 12) then r.lp := '1'; end if; if (s = 28) then r.xA := '1'; end if;
         when CALC_SQR              => if (s =  2) then r.xT := '1'; end if; if (s =  5) then r.xA := '1'; end if;
         when CALC_DPCL             => if (s = 10) then r.xA := '1'; end if;
         when CALC_AVSZ3            => if (s =  5) then r.xA := '1'; end if;
         when CALC_AVSZ4            => if (s =  7) then r.xA := '1'; end if;
         when CALC_GPF              => if (s =  4) then r.xA := '1'; end if;
         when CALC_GPL              => if (s =  5) then r.xA := '1'; end if;
         when IDLE                  => null;
      end case;
      return r;
   end function;

   function opState3(op : unsigned(5 downto 0)) return tstate is
   begin
      case (to_integer(op)) is
         when 16#01# => return CALC_RTPS;
         when 16#06# => return CALC_NCLIP;
         when 16#0C# => return CALC_OP;
         when 16#10# => return CALC_DPCS;
         when 16#11# => return CALC_INTPL;
         when 16#12# => return CALC_MVMVA;
         when 16#13# => return CALC_NCDS;
         when 16#14# => return CALC_CDP;
         when 16#16# => return CALC_NCDT;
         when 16#1B# => return CALC_NCCS;
         when 16#1C# => return CALC_CC;
         when 16#1E# => return CALC_NCS;
         when 16#20# => return CALC_NCT;
         when 16#28# => return CALC_SQR;
         when 16#29# => return CALC_DPCL;
         when 16#2A# => return CALC_DPCT;
         when 16#2D# => return CALC_AVSZ3;
         when 16#2E# => return CALC_AVSZ4;
         when 16#30# => return CALC_RTPT;
         when 16#3D# => return CALC_GPF;
         when 16#3E# => return CALC_GPL;
         when 16#3F# => return CALC_NCCT;
         when others => return IDLE;
      end case;
   end function;

   -- operand muxes (AND-OR from the one-hot selects)
   function s18(s : std_logic; v : signed) return signed is
      variable r : signed(17 downto 0) := (others => '0');
   begin
      if (s = '1') then r := resize(v, 18); end if;
      return r;
   end function;

   function s32(s : std_logic; v : signed) return signed is
      variable r : signed(31 downto 0) := (others => '0');
   begin
      if (s = '1') then r := resize(v, 32); end if;
      return r;
   end function;

   function s45(s : std_logic; v : signed) return signed is
      variable r : signed(44 downto 0) := (others => '0');
   begin
      if (s = '1') then r := resize(v, 45); end if;
      return r;
   end function;

   function mulA3(r : tReq3; rt1, rt2, rt3, op0, op1, ir, m0, m1, m2, ll1, ll2, ll3, lc1, lc2, lc3 : signed(15 downto 0)) return signed is
   begin
      return s18(r.aRT1, rt1) or s18(r.aRT2, rt2) or s18(r.aRT3, rt3) or s18(r.aOP0, op0) or s18(r.aOP1, op1) or
             s18(r.aIR, ir)   or s18(r.aM0, m0)   or s18(r.aM1, m1)   or s18(r.aM2, m2)   or
             s18(r.aLL1, ll1) or s18(r.aLL2, ll2) or s18(r.aLL3, ll3) or s18(r.aLC1, lc1) or s18(r.aLC2, lc2) or s18(r.aLC3, lc3);
   end function;

   function mulB3(r : tReq3; v0x, v0y, v0z, v1x, v1y, v1z, v2x, v2y, v2z, op0, op1, ir0, ir1, ir2, ir3, vec0, vec1, vec2, iri : signed(15 downto 0); rgb : unsigned(7 downto 0)) return signed is
   begin
      return s18(r.bV0X, v0x)   or s18(r.bV0Y, v0y)   or s18(r.bV0Z, v0z)   or s18(r.bV1X, v1x) or s18(r.bV1Y, v1y) or s18(r.bV1Z, v1z) or
             s18(r.bV2X, v2x)   or s18(r.bV2Y, v2y)   or s18(r.bV2Z, v2z)   or s18(r.bOP0, op0) or s18(r.bOP1, op1) or
             s18(r.bIR0, ir0)   or s18(r.bIR1, ir1)   or s18(r.bIR2, ir2)   or s18(r.bIR3, ir3) or
             s18(r.bVec0, vec0) or s18(r.bVec1, vec1) or s18(r.bVec2, vec2) or s18(r.bIRi, iri) or s18(r.bRGBC, signed('0' & rgb));
   end function;

   function shift3(r : tReq3; col : unsigned(7 downto 0); fc, tr, bk, res, mac : signed(31 downto 0); ir : signed(15 downto 0); gpl1000 : std_logic) return signed is
      variable w : signed(31 downto 0);
   begin
      w := s32(r.wCol, signed('0' & col)) or s32(r.wFC, fc) or s32(r.wIR, ir) or s32(r.wTR, tr) or s32(r.wBK, bk) or s32(r.wRes, res) or s32(r.wMAC, mac);
      -- as gte_mac123 NARROW_MUL = 1: resize(mul1 * mul2, 45) for mul2 = 2^k
      return s45(r.k0 or (r.kGPL and not gpl1000), resize(resize(w, 64), 45)) or
             s45(r.k4,                             resize(shift_left(resize(w, 64), 4), 45)) or
             s45(r.k12 or (r.kGPL and gpl1000),    resize(shift_left(resize(w, 64), 12), 45)) or
             s45(r.k16,                            resize(shift_left(resize(w, 64), 16), 45));
   end function;

   function add3(r : tReq3; tr : unsigned(31 downto 0); last : signed(44 downto 0)) return signed is
   begin
      return s45(r.addTR, resize(signed(tr), 33) & x"000") or s45(r.addLast, last);
   end function;

begin 

   gte_writeAddr <= SS_Adr                 when (loading_savestate = '1') else gte_writeAddr_in;
   gte_writeData <= unsigned(SS_DataWrite) when (loading_savestate = '1') else gte_writeData_in;
   gte_writeEna  <= SS_wren                when (loading_savestate = '1') else gte_writeEna_in; 
   
   process (clk2x)
      variable leadCountData : unsigned(31 downto 0);
      variable colorNewR     : unsigned(7 downto 0);
      variable colorNewG     : unsigned(7 downto 0);
      variable colorNewB     : unsigned(7 downto 0);
      variable v3_state      : tstate;
      variable v3_step       : integer range 0 to 64;
      variable v3_first      : tReq3;
      variable v3_next       : tReq3;
      variable v3_exit       : boolean;
      variable v3_loop       : boolean;
   begin
      if rising_edge(clk2x) then
      
         case (WIDESCREEN) is
            when "01"   => IR1aspect <= resize((resize(REG_IR1 & "000", 21)  + resize(REG_IR1 & "00", 21)  + resize(REG_IR1 & '0', 21) ) / 16, 17);   -- * (8 + 4 + 2) / 16 -> ~3:2
            when "10"   => IR1aspect <= resize((resize(REG_IR1 & "000", 21)  + resize(REG_IR1 & "00", 21)  + resize(REG_IR1      , 21) ) / 16, 17);   -- * (8 + 4 + 1) / 16 -> ~5:3
            when "11"   => IR1aspect <= resize((resize(REG_IR1 & "000", 21)  + resize(REG_IR1 & "00", 21)                              ) / 16, 17);   -- * (8 + 4)     / 16 -> 16:9
            when others => IR1aspect <= resize(REG_IR1, 17);
         end case;
      
         turbomode <= TURBO;
      
         if (reset = '1' and loading_savestate = '0') then
         
            state    <= IDLE;
         
            gte_busy <= '0';
            
            debugCnt <= (others => '0');

            REG_V0X  <= (others => '0');
            REG_V0Y  <= (others => '0');
            REG_V0Z  <= (others => '0');
            REG_V1X  <= (others => '0');
            REG_V1Y  <= (others => '0');
            REG_V1Z  <= (others => '0');
            REG_V2X  <= (others => '0');
            REG_V2Y  <= (others => '0');
            REG_V2Z  <= (others => '0');
            REG_RGBC <= (others => '0');
            REG_OTZ  <= (others => '0');
            REG_IR0  <= (others => '0');
            REG_IR1  <= (others => '0');
            REG_IR2  <= (others => '0');
            REG_IR3  <= (others => '0');
            REG_SX0  <= (others => '0');
            REG_SY0  <= (others => '0');
            REG_SX1  <= (others => '0');
            REG_SY1  <= (others => '0');
            REG_SX2  <= (others => '0');
            REG_SY2  <= (others => '0');
            REG_SZ0  <= (others => '0');
            REG_SZ1  <= (others => '0');
            REG_SZ2  <= (others => '0');
            REG_SZ3  <= (others => '0');
            REG_RGB0 <= (others => '0');
            REG_RGB1 <= (others => '0');
            REG_RGB2 <= (others => '0');
            REG_RES1 <= (others => '0');
            REG_MAC0 <= (others => '0');
            REG_MAC1 <= (others => '0');
            REG_MAC2 <= (others => '0');
            REG_MAC3 <= (others => '0');
            REG_IRGB <= (others => '0');
            REG_ORGB <= (others => '0');
            REG_LZCS <= (others => '0');
            REG_LZCR <= (others => '0');
            
            REG_RT11 <= (others => '0');
            REG_RT12 <= (others => '0');
            REG_RT13 <= (others => '0');
            REG_RT21 <= (others => '0');
            REG_RT22 <= (others => '0');
            REG_RT23 <= (others => '0');
            REG_RT31 <= (others => '0');
            REG_RT32 <= (others => '0');
            REG_RT33 <= (others => '0');
            REG_TR0  <= (others => '0');
            REG_TR1  <= (others => '0');
            REG_TR2  <= (others => '0');
            REG_LL11 <= (others => '0');
            REG_LL12 <= (others => '0');
            REG_LL13 <= (others => '0');
            REG_LL21 <= (others => '0');
            REG_LL22 <= (others => '0');
            REG_LL23 <= (others => '0');
            REG_LL31 <= (others => '0');
            REG_LL32 <= (others => '0');
            REG_LL33 <= (others => '0');
            REG_BK0  <= (others => '0');
            REG_BK1  <= (others => '0');
            REG_BK2  <= (others => '0');
            REG_LC11 <= (others => '0');
            REG_LC12 <= (others => '0');
            REG_LC13 <= (others => '0');
            REG_LC21 <= (others => '0');
            REG_LC22 <= (others => '0');
            REG_LC23 <= (others => '0');
            REG_LC31 <= (others => '0');
            REG_LC32 <= (others => '0');
            REG_LC33 <= (others => '0');
            REG_FC0  <= (others => '0');
            REG_FC1  <= (others => '0');
            REG_FC2  <= (others => '0');
            REG_OFX  <= (others => '0');
            REG_OFY  <= (others => '0');
            REG_H    <= (others => '0');
            REG_DQA  <= (others => '0');
            REG_DQB  <= (others => '0');
            REG_ZSF3 <= (others => '0');
            REG_ZSF4 <= (others => '0');
            REG_FLAG <= (others => '0');

            if (NARROW_MUL = 3) then
               req3 <= REQ3_NONE;
            end if;
            
         elsif (ce = '1' or loading_savestate = '1') then
         
            MAC0req.trigger <= '0';
            MAC1req.trigger <= '0';
            MAC2req.trigger <= '0';
            MAC3req.trigger <= '0';
            
            div_trigger     <= '0';
            pushRGBfromMAC  <= '0';
            setOTZ          <= '0';
            pushSZandDivide <= '0';
            pushSXY         <= '0';
            
            if (gte_readEna = '1') then
               case (to_integer(gte_readAddr)) is
                  when 00 => gte_readData <= unsigned(REG_V0Y & REG_V0X);
                  when 01 => gte_readData <= unsigned(resize(REG_V0Z, 32));
                  when 02 => gte_readData <= unsigned(REG_V1Y & REG_V1X);
                  when 03 => gte_readData <= unsigned(resize(REG_V1Z, 32));
                  when 04 => gte_readData <= unsigned(REG_V2Y & REG_V2X);
                  when 05 => gte_readData <= unsigned(resize(REG_V2Z, 32));
                  when 06 => gte_readData <= REG_RGBC;
                  when 07 => gte_readData <= x"0000" & REG_OTZ;
                  when 08 => gte_readData <= unsigned(resize(REG_IR0, 32));
                  when 09 => gte_readData <= unsigned(resize(REG_IR1, 32));
                  when 10 => gte_readData <= unsigned(resize(REG_IR2, 32));
                  when 11 => gte_readData <= unsigned(resize(REG_IR3, 32));
                  when 12 => gte_readData <= unsigned(REG_SY0 & REG_SX0);
                  when 13 => gte_readData <= unsigned(REG_SY1 & REG_SX1);
                  when 14 => gte_readData <= unsigned(REG_SY2 & REG_SX2);
                  when 15 => gte_readData <= unsigned(REG_SY2 & REG_SX2);
                  when 16 => gte_readData <= x"0000" & REG_SZ0;
                  when 17 => gte_readData <= x"0000" & REG_SZ1;
                  when 18 => gte_readData <= x"0000" & REG_SZ2;
                  when 19 => gte_readData <= x"0000" & REG_SZ3;
                  when 20 => gte_readData <= REG_RGB0;
                  when 21 => gte_readData <= REG_RGB1;
                  when 22 => gte_readData <= REG_RGB2;
                  when 23 => gte_readData <= REG_RES1;
                  when 24 => gte_readData <= unsigned(REG_MAC0);
                  when 25 => gte_readData <= unsigned(REG_MAC1);
                  when 26 => gte_readData <= unsigned(REG_MAC2);
                  when 27 => gte_readData <= unsigned(REG_MAC3);
                  when 28 | 29 => 
                     gte_readData(31 downto 15) <= (others => '0');
                     if (REG_IR1 < 0) then gte_readData( 4 downto  0) <= "00000"; elsif (REG_IR1(15 downto 7) > 31) then gte_readData( 4 downto  0) <= "11111"; else gte_readData( 4 downto  0) <= unsigned(REG_IR1(11 downto 7)); end if;
                     if (REG_IR2 < 0) then gte_readData( 9 downto  5) <= "00000"; elsif (REG_IR2(15 downto 7) > 31) then gte_readData( 9 downto  5) <= "11111"; else gte_readData( 9 downto  5) <= unsigned(REG_IR2(11 downto 7)); end if;
                     if (REG_IR3 < 0) then gte_readData(14 downto 10) <= "00000"; elsif (REG_IR3(15 downto 7) > 31) then gte_readData(14 downto 10) <= "11111"; else gte_readData(14 downto 10) <= unsigned(REG_IR3(11 downto 7)); end if;
   
                  when 30 => gte_readData <= unsigned(REG_LZCS);
                  when 31 => gte_readData <= unsigned(REG_LZCR);
                  when 32 => gte_readData <= unsigned(REG_RT12 & REG_RT11);
                  when 33 => gte_readData <= unsigned(REG_RT21 & REG_RT13);
                  when 34 => gte_readData <= unsigned(REG_RT23 & REG_RT22);
                  when 35 => gte_readData <= unsigned(REG_RT32 & REG_RT31);
                  when 36 => gte_readData <= unsigned(resize(REG_RT33, 32));
                  when 37 => gte_readData <= REG_TR0;
                  when 38 => gte_readData <= REG_TR1;
                  when 39 => gte_readData <= REG_TR2;
                  when 40 => gte_readData <= unsigned(REG_LL12 & REG_LL11);
                  when 41 => gte_readData <= unsigned(REG_LL21 & REG_LL13);
                  when 42 => gte_readData <= unsigned(REG_LL23 & REG_LL22);
                  when 43 => gte_readData <= unsigned(REG_LL32 & REG_LL31);
                  when 44 => gte_readData <= unsigned(resize(REG_LL33, 32));
                  when 45 => gte_readData <= REG_BK0;
                  when 46 => gte_readData <= REG_BK1;
                  when 47 => gte_readData <= REG_BK2;
                  when 48 => gte_readData <= unsigned(REG_LC12 & REG_LC11);
                  when 49 => gte_readData <= unsigned(REG_LC21 & REG_LC13);
                  when 50 => gte_readData <= unsigned(REG_LC23 & REG_LC22);
                  when 51 => gte_readData <= unsigned(REG_LC32 & REG_LC31);
                  when 52 => gte_readData <= unsigned(resize(REG_LC33, 32));
                  when 53 => gte_readData <= REG_FC0;
                  when 54 => gte_readData <= REG_FC1;
                  when 55 => gte_readData <= REG_FC2;
                  when 56 => gte_readData <= REG_OFX;
                  when 57 => gte_readData <= REG_OFY;
                  when 58 => gte_readData <= unsigned(resize(REG_H, 32));
                  when 59 => gte_readData <= unsigned(resize(REG_DQA, 32));
                  when 60 => gte_readData <= REG_DQB;
                  when 61 => gte_readData <= unsigned(resize(REG_ZSF3, 32));
                  when 62 => gte_readData <= unsigned(resize(REG_ZSF4, 32));
                  when 63 => gte_readData <= REG_FLAG;
                  when others => null;
               end case;
            end if;
         
            if (gte_writeEna = '1' and clk2xIndex = '1') then
            
               case (to_integer(gte_writeAddr)) is
                  when 00 => REG_V0X <= signed(gte_writeData(15 downto 0)); REG_V0Y <= signed(gte_writeData(31 downto 16));
                  when 01 => REG_V0Z <= signed(gte_writeData(15 downto 0));
                  when 02 => REG_V1X <= signed(gte_writeData(15 downto 0)); REG_V1Y <= signed(gte_writeData(31 downto 16));
                  when 03 => REG_V1Z <= signed(gte_writeData(15 downto 0));
                  when 04 => REG_V2X <= signed(gte_writeData(15 downto 0)); REG_V2Y <= signed(gte_writeData(31 downto 16));
                  when 05 => REG_V2Z <= signed(gte_writeData(15 downto 0));
                  when 06 => REG_RGBC <= gte_writeData;
                  when 07 => REG_OTZ  <= gte_writeData(15 downto 0);
                  when 08 => REG_IR0  <= signed(gte_writeData(15 downto 0));
                  when 09 => REG_IR1  <= signed(gte_writeData(15 downto 0));
                  when 10 => REG_IR2  <= signed(gte_writeData(15 downto 0));
                  when 11 => REG_IR3  <= signed(gte_writeData(15 downto 0));
                  when 12 => REG_SX0  <= signed(gte_writeData(15 downto 0)); REG_SY0 <= signed(gte_writeData(31 downto 16));
                  when 13 => REG_SX1  <= signed(gte_writeData(15 downto 0)); REG_SY1 <= signed(gte_writeData(31 downto 16));
                  when 14 => REG_SX2  <= signed(gte_writeData(15 downto 0)); REG_SY2 <= signed(gte_writeData(31 downto 16));
                  when 15 => 
                     if (loading_savestate = '0') then
                        REG_SX2  <= signed(gte_writeData(15 downto 0)); REG_SY2 <= signed(gte_writeData(31 downto 16));
                        REG_SX1  <= REG_SX2; REG_SY1 <= REG_SY2;
                        REG_SX0  <= REG_SX1; REG_SY0 <= REG_SY1;
                     end if;
                  when 16 => REG_SZ0  <= gte_writeData(15 downto 0);
                  when 17 => REG_SZ1  <= gte_writeData(15 downto 0);
                  when 18 => REG_SZ2  <= gte_writeData(15 downto 0);
                  when 19 => REG_SZ3  <= gte_writeData(15 downto 0);
                  when 20 => REG_RGB0 <= gte_writeData;
                  when 21 => REG_RGB1 <= gte_writeData;
                  when 22 => REG_RGB2 <= gte_writeData;
                  when 23 => REG_RES1 <= gte_writeData;
                  when 24 => REG_MAC0 <= signed(gte_writeData);
                  when 25 => REG_MAC1 <= signed(gte_writeData);
                  when 26 => REG_MAC2 <= signed(gte_writeData);
                  when 27 => REG_MAC3 <= signed(gte_writeData);
                  when 28 => 
                     REG_IRGB <= gte_writeData(14 downto 0);
                     if (loading_savestate = '0') then
                        REG_IR1  <= signed("0000" & gte_writeData( 4 downto  0) & "0000000");
                        REG_IR2  <= signed("0000" & gte_writeData( 9 downto  5) & "0000000");
                        REG_IR3  <= signed("0000" & gte_writeData(14 downto 10) & "0000000");
                     end if;
                  when 29 => -- read only
                  when 30 =>
                     REG_LZCS <= signed(gte_writeData);
                     leadCountData := gte_writeData;
                     if (gte_writeData(31) = '1') then
                        leadCountData := not gte_writeData;
                     end if;
                     REG_LZCR <= signed(to_unsigned(32, 32));
                     for i in 0 to 31 loop
                        if (leadCountData(i) = '1') then
                           REG_LZCR <= signed(to_unsigned(31 - i, 32));
                        end if;
                     end loop;
                     
                  when 31 => -- read only
                  when 32 => REG_RT11 <= signed(gte_writeData(15 downto 0)); REG_RT12 <= signed(gte_writeData(31 downto 16));
                  when 33 => REG_RT13 <= signed(gte_writeData(15 downto 0)); REG_RT21 <= signed(gte_writeData(31 downto 16));
                  when 34 => REG_RT22 <= signed(gte_writeData(15 downto 0)); REG_RT23 <= signed(gte_writeData(31 downto 16));
                  when 35 => REG_RT31 <= signed(gte_writeData(15 downto 0)); REG_RT32 <= signed(gte_writeData(31 downto 16));
                  when 36 => REG_RT33 <= signed(gte_writeData(15 downto 0));
                  when 37 => REG_TR0  <= gte_writeData;
                  when 38 => REG_TR1  <= gte_writeData;
                  when 39 => REG_TR2  <= gte_writeData;
                  when 40 => REG_LL11 <= signed(gte_writeData(15 downto 0)); REG_LL12 <= signed(gte_writeData(31 downto 16));
                  when 41 => REG_LL13 <= signed(gte_writeData(15 downto 0)); REG_LL21 <= signed(gte_writeData(31 downto 16));
                  when 42 => REG_LL22 <= signed(gte_writeData(15 downto 0)); REG_LL23 <= signed(gte_writeData(31 downto 16));
                  when 43 => REG_LL31 <= signed(gte_writeData(15 downto 0)); REG_LL32 <= signed(gte_writeData(31 downto 16));
                  when 44 => REG_LL33 <= signed(gte_writeData(15 downto 0));
                  when 45 => REG_BK0  <= gte_writeData;
                  when 46 => REG_BK1  <= gte_writeData;
                  when 47 => REG_BK2  <= gte_writeData;
                  when 48 => REG_LC11 <= signed(gte_writeData(15 downto 0)); REG_LC12 <= signed(gte_writeData(31 downto 16));
                  when 49 => REG_LC13 <= signed(gte_writeData(15 downto 0)); REG_LC21 <= signed(gte_writeData(31 downto 16));
                  when 50 => REG_LC22 <= signed(gte_writeData(15 downto 0)); REG_LC23 <= signed(gte_writeData(31 downto 16));
                  when 51 => REG_LC31 <= signed(gte_writeData(15 downto 0)); REG_LC32 <= signed(gte_writeData(31 downto 16));
                  when 52 => REG_LC33 <= signed(gte_writeData(15 downto 0));
                  when 53 => REG_FC0  <= gte_writeData;
                  when 54 => REG_FC1  <= gte_writeData;
                  when 55 => REG_FC2  <= gte_writeData;
                  when 56 => REG_OFX  <= gte_writeData;
                  when 57 => REG_OFY  <= gte_writeData;
                  when 58 => REG_H    <= signed(gte_writeData(15 downto 0));
                  when 59 => REG_DQA  <= signed(gte_writeData(15 downto 0));
                  when 60 => REG_DQB  <= gte_writeData;
                  when 61 => REG_ZSF3 <= signed(gte_writeData(15 downto 0));
                  when 62 => REG_ZSF4 <= signed(gte_writeData(15 downto 0));
                  when 63 => 
                     REG_FLAG(30 downto 12) <= gte_writeData(30 downto 12);
                     REG_FLAG(31) <= '0';
                     if ((gte_writeData(30 downto 12) and to_unsigned(16#7F87E#, 19)) > 0) then  -- bit 30..23 and 18..13
                        REG_FLAG(31) <= '1';
                     end if;
                  when others => null;
               end case;
            
            end if;
            
            -- calculation
            calcStep <= calcStep + 1; 
            
            debug_firstGTE <= '0';
            
            case (state) is
            
               when IDLE =>
                  calcStep   <= 0;
                  batchCount <= 0;
                  if (gte_cmdEna = '1' and clk2xIndex = '1') then
                     gte_busy <= '1';
                     REG_FLAG <= (others => '0');
                     cmdShift <= gte_cmdData(19);
                     cmdsatIR <= gte_cmdData(10);
                     cmdMM    <= gte_cmdData(18 downto 17);
                     cmdMV    <= gte_cmdData(16 downto 15);
                     cmdTV    <= gte_cmdData(14 downto 13);
                     case (to_integer(gte_cmdData(5 downto 0))) is
                        when 16#01# => state <= CALC_RTPS;
                        when 16#06# => state <= CALC_NCLIP; 
                        when 16#0C# => state <= CALC_OP; 
                        when 16#10# => state <= CALC_DPCS; calcColor <= REG_RGBC(23 downto 0);
                        when 16#11# => state <= CALC_INTPL;
                        when 16#12# => state <= CALC_MVMVA;
                        when 16#13# => state <= CALC_NCDS;
                        when 16#14# => state <= CALC_CDP;
                        when 16#16# => state <= CALC_NCDT;
                        when 16#1B# => state <= CALC_NCCS;
                        when 16#1C# => state <= CALC_CC;
                        when 16#1E# => state <= CALC_NCS;
                        when 16#20# => state <= CALC_NCT;
                        when 16#28# => state <= CALC_SQR;
                        when 16#29# => state <= CALC_DPCL;
                        when 16#2A# => state <= CALC_DPCT; calcColor <= REG_RGB0(23 downto 0);
                        when 16#2D# => state <= CALC_AVSZ3;
                        when 16#2E# => state <= CALC_AVSZ4;
                        when 16#30# => state <= CALC_RTPT;
                        when 16#3D# => state <= CALC_GPF;
                        when 16#3E# => state <= CALC_GPL;
                        when 16#3F# => state <= CALC_NCCT;                        
                        when others => gte_busy <= '0';
                     end case;
                     
                     debugCnt <= debugCnt + 1;
                     if (debugCnt = 0) then
                        debug_firstGTE <= '1';
                     end if;
                     
                  elsif (clk2xIndex = '0') then
                     gte_busy <= '0';
                  end if;
                  
               when CALC_RTPS =>
                  case (calcStep) is
                     --                     mul1                        mul2                  add                           sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 0 => MAC1req <= (resize(REG_RT11, 32), resize(REG_V0X, 32), resize(signed(REG_TR0), 33) & x"000", '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (resize(REG_RT21, 32), resize(REG_V0X, 32), resize(signed(REG_TR1), 33) & x"000", '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (resize(REG_RT31, 32), resize(REG_V0X, 32), resize(signed(REG_TR2), 33) & x"000", '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1');

                     when 1 => MAC1req <= (resize(REG_RT12, 32), resize(REG_V0Y, 32), to_signed(0, 45),                     '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC2req <= (resize(REG_RT22, 32), resize(REG_V0Y, 32), to_signed(0, 45),                     '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC3req <= (resize(REG_RT32, 32), resize(REG_V0Y, 32), to_signed(0, 45),                     '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                                                                                                                            
                     when 2 => MAC1req <= (resize(REG_RT13, 32), resize(REG_V0Z, 32), to_signed(0, 45),                     '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC2req <= (resize(REG_RT23, 32), resize(REG_V0Z, 32), to_signed(0, 45),                     '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC3req <= (resize(REG_RT33, 32), resize(REG_V0Z, 32), to_signed(0, 45),                     '0', '0', cmdShift, '1', cmdShift,      '1', cmdsatIR,      '0',  '1',  '1');

                     when 3 => pushSZandDivide <= '1';

                              --             mul1                       mul2                    add         sub  swap useIR IRs cOvf uRes trigger
                     when 12 => MAC0req <= (          IR1aspect, '0' & signed(div_result), signed(REG_OFX), '0', '0', '0', '0', '1', '0', '1'); 
                     when 13 => MAC0req <= (resize(REG_IR2, 17), '0' & signed(div_result), signed(REG_OFY), '0', '0', '0', '0', '1', '0', '1'); 
                     when 14 => pushSXY <= '1';
                     when 15 => MAC0req <= (resize(REG_DQA, 17), '0' & signed(div_result), signed(REG_DQB), '0', '0', '1', '1', '1', '0', '1');
                               
                     when 17 => if (turbomode = '1') then state <= IDLE; end if;
                     when 25 => state <= IDLE;
                     when others => null;
                  end case;
                  
               when CALC_RTPT =>
                  case (calcStep) is
                     --                     mul1                        mul2                  add                           sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                              -- first round
                     when 0 => MAC1req <= (resize(REG_RT11, 32), resize(REG_V0X, 32), resize(signed(REG_TR0), 33) & x"000", '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (resize(REG_RT21, 32), resize(REG_V0X, 32), resize(signed(REG_TR1), 33) & x"000", '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (resize(REG_RT31, 32), resize(REG_V0X, 32), resize(signed(REG_TR2), 33) & x"000", '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1');                           
                               
                     when 1 => MAC1req <= (resize(REG_RT12, 32), resize(REG_V0Y, 32), to_signed(0, 45),                     '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC2req <= (resize(REG_RT22, 32), resize(REG_V0Y, 32), to_signed(0, 45),                     '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC3req <= (resize(REG_RT32, 32), resize(REG_V0Y, 32), to_signed(0, 45),                     '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                                                                                                                            
                     when 2 => MAC1req <= (resize(REG_RT13, 32), resize(REG_V0Z, 32), to_signed(0, 45),                     '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC2req <= (resize(REG_RT23, 32), resize(REG_V0Z, 32), to_signed(0, 45),                     '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC3req <= (resize(REG_RT33, 32), resize(REG_V0Z, 32), to_signed(0, 45),                     '0', '0', cmdShift, '1', cmdShift,      '1', cmdsatIR,      '0',  '1',  '1');

                     when 3 => pushSZandDivide <= '1';
                               -- second round
                               MAC1req <= (resize(REG_RT11, 32), resize(REG_V1X, 32), resize(signed(REG_TR0), 33) & x"000", '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (resize(REG_RT21, 32), resize(REG_V1X, 32), resize(signed(REG_TR1), 33) & x"000", '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (resize(REG_RT31, 32), resize(REG_V1X, 32), resize(signed(REG_TR2), 33) & x"000", '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1');
                     
                     when 4 => MAC1req <= (resize(REG_RT12, 32), resize(REG_V1Y, 32), to_signed(0, 45),                     '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC2req <= (resize(REG_RT22, 32), resize(REG_V1Y, 32), to_signed(0, 45),                     '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC3req <= (resize(REG_RT32, 32), resize(REG_V1Y, 32), to_signed(0, 45),                     '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                                                                                                                            
                     when 5 => MAC1req <= (resize(REG_RT13, 32), resize(REG_V1Z, 32), to_signed(0, 45),                     '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC2req <= (resize(REG_RT23, 32), resize(REG_V1Z, 32), to_signed(0, 45),                     '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC3req <= (resize(REG_RT33, 32), resize(REG_V1Z, 32), to_signed(0, 45),                     '0', '0', cmdShift, '1', cmdShift,      '1', cmdsatIR,      '0',  '1',  '1');
                     when 6 => pushSZandDivide <= '1'; IR1aspect_1 <= IR1aspect; REG_IR2_1 <= REG_IR2;
                               -- third round
                               MAC1req <= (resize(REG_RT11, 32), resize(REG_V2X, 32), resize(signed(REG_TR0), 33) & x"000", '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (resize(REG_RT21, 32), resize(REG_V2X, 32), resize(signed(REG_TR1), 33) & x"000", '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (resize(REG_RT31, 32), resize(REG_V2X, 32), resize(signed(REG_TR2), 33) & x"000", '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1');
                     
                     when 7 => MAC1req <= (resize(REG_RT12, 32), resize(REG_V2Y, 32), to_signed(0, 45),                     '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC2req <= (resize(REG_RT22, 32), resize(REG_V2Y, 32), to_signed(0, 45),                     '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC3req <= (resize(REG_RT32, 32), resize(REG_V2Y, 32), to_signed(0, 45),                     '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                                                                                                                            
                     when 8 => MAC1req <= (resize(REG_RT13, 32), resize(REG_V2Z, 32), to_signed(0, 45),                     '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC2req <= (resize(REG_RT23, 32), resize(REG_V2Z, 32), to_signed(0, 45),                     '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC3req <= (resize(REG_RT33, 32), resize(REG_V2Z, 32), to_signed(0, 45),                     '0', '0', cmdShift, '1', cmdShift,      '1', cmdsatIR,      '0',  '1',  '1');
                     when 9 => pushSZandDivide <= '1'; IR1aspect_2 <= IR1aspect; REG_IR2_2 <= REG_IR2;

                              --             mul1                       mul2                    add         sub  swap useIR IRs cOvf uRes trigger
                              -- first round
                     when 12 => MAC0req <= (          IR1aspect_1, '0' & signed(div_result), signed(REG_OFX), '0', '0', '0', '0', '1', '0', '1'); 
                     when 13 => MAC0req <= (resize(REG_IR2_1, 17), '0' & signed(div_result), signed(REG_OFY), '0', '0', '0', '0', '1', '0', '1'); 
                     when 14 => pushSXY <= '1';
                     
                              -- second round
                     when 15 => MAC0req <= (          IR1aspect_2, '0' & signed(div_result), signed(REG_OFX), '0', '0', '0', '0', '1', '0', '1'); 
                     when 16 => MAC0req <= (resize(REG_IR2_2, 17), '0' & signed(div_result), signed(REG_OFY), '0', '0', '0', '0', '1', '0', '1'); 
                     when 17 => pushSXY <= '1';
                     
                              -- third round
                     when 18 => MAC0req <= (          IR1aspect, '0' & signed(div_result), signed(REG_OFX), '0', '0', '0', '0', '1', '0', '1'); 
                     when 19 => MAC0req <= (resize(REG_IR2, 17), '0' & signed(div_result), signed(REG_OFY), '0', '0', '0', '0', '1', '0', '1'); 
                     when 20 => pushSXY <= '1';
                     
                     -- only for third round
                     when 21 =>  MAC0req <= (resize(REG_DQA, 17), '0' & signed(div_result), signed(REG_DQB), '0', '0', '1', '1', '1', '0', '1');
                               
                     when 23 => if (turbomode = '1') then state <= IDLE; end if;
                     when 41 => state <= IDLE;
                     when others => null;
                  end case;
               
               when CALC_NCLIP =>
                  case (calcStep) is
                     --                                  mul1              mul2           add     sub  swap useIR IRs cOvf uRes trigger
                     when 0  => MAC0req <= (resize(REG_SX0, 17), resize(REG_SY1,18), x"00000000", '0', '0', '0', '0', '0', '0', '1'); 
                     when 1  => MAC0req <= (resize(REG_SX1, 17), resize(REG_SY2,18), x"00000000", '0', '0', '0', '0', '0', '1', '1'); 
                     when 2  => MAC0req <= (resize(REG_SX2, 17), resize(REG_SY0,18), x"00000000", '0', '0', '0', '0', '0', '1', '1'); 
                     when 3  => MAC0req <= (resize(REG_SX0, 17), resize(REG_SY2,18), x"00000000", '1', '0', '0', '0', '0', '1', '1'); 
                     when 4  => MAC0req <= (resize(REG_SX1, 17), resize(REG_SY0,18), x"00000000", '1', '0', '0', '0', '0', '1', '1'); 
                     when 5  => MAC0req <= (resize(REG_SX2, 17), resize(REG_SY1,18), x"00000000", '1', '0', '0', '0', '1', '1', '1'); 
                     when 7  => if (turbomode = '1') then state <= IDLE; end if;
                     when 11 => state <= IDLE;
                     when others => null;
                  end case;
                  
               when CALC_OP =>
                  case (calcStep) is
                     --                     mul1                        mul2                 add        sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 0 => MAC1req <= (resize(REG_RT22, 32), resize(REG_IR3, 32), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (resize(REG_RT33, 32), resize(REG_IR1, 32), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (resize(REG_RT11, 32), resize(REG_IR2, 32), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1');  
                                                                                                              
                     when 1 => MAC1req <= (resize(REG_RT33, 32), resize(REG_IR2, 32), to_signed(0, 45), '1', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC2req <= (resize(REG_RT11, 32), resize(REG_IR3, 32), to_signed(0, 45), '1', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC3req <= (resize(REG_RT22, 32), resize(REG_IR1, 32), to_signed(0, 45), '1', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1');
                     
                     when 3 => if (turbomode = '1') then state <= IDLE; end if;
                     when 7 => state <= IDLE;
                     when others => null;
                  end case;
                  
               when CALC_DPCS | CALC_DPCT =>
                  case (calcStep) is
                     --                     mul1                                            mul2                    add        sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 0 => MAC1req <= (signed(x"000000" & calcColor( 7 downto  0)), x"00010000",         to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (signed(x"000000" & calcColor(15 downto  8)), x"00010000",         to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (signed(x"000000" & calcColor(23 downto 16)), x"00010000",         to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1');  
                                                                                                              
                     when 1 => MAC1req <= (signed(REG_FC0),                             x"00001000",         to_signed(0, 45), '1', '1', cmdShift, '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1'); 
                               MAC2req <= (signed(REG_FC1),                             x"00001000",         to_signed(0, 45), '1', '1', cmdShift, '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1'); 
                               MAC3req <= (signed(REG_FC2),                             x"00001000",         to_signed(0, 45), '1', '1', cmdShift, '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1');
                     
                     when 4 => MAC1req <= (resize(REG_IR1, 32),                         resize(REG_IR0, 32), mac1Last,         '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1'); 
                               MAC2req <= (resize(REG_IR2, 32),                         resize(REG_IR0, 32), mac2Last,         '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1'); 
                               MAC3req <= (resize(REG_IR3, 32),                         resize(REG_IR0, 32), mac3Last,         '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1');
                     
                     when 5 => pushRGBfromMAC <= '1';
                    
                     when 8 => 
                        if (state = CALC_DPCS or batchCount = 2) then
                           if (turbomode = '1') then
                              state <= IDLE;
                           end if;
                        else
                           calcStep   <= 0;
                           batchCount <= batchCount + 1;
                           calcColor  <= REG_RGB0(23 downto 0);
                        end if;
                        
                     when 10 => state <= IDLE;
                     when others => null;
                  end case;               
                  
               when CALC_INTPL =>
                  case (calcStep) is
                     --                     mul1                    mul2                    add        sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 0 => MAC1req <= (resize(REG_IR1, 32), x"00001000",         to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (resize(REG_IR2, 32), x"00001000",         to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (resize(REG_IR3, 32), x"00001000",         to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1');  
                                                                                                              
                     when 1 => MAC1req <= (signed(REG_FC0),     x"00001000",         to_signed(0, 45), '1', '1', cmdShift, '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1'); 
                               MAC2req <= (signed(REG_FC1),     x"00001000",         to_signed(0, 45), '1', '1', cmdShift, '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1'); 
                               MAC3req <= (signed(REG_FC2),     x"00001000",         to_signed(0, 45), '1', '1', cmdShift, '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1');
                     
                     when 4 => MAC1req <= (resize(REG_IR1, 32), resize(REG_IR0, 32), mac1Last,         '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1'); 
                               MAC2req <= (resize(REG_IR2, 32), resize(REG_IR0, 32), mac2Last,         '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1'); 
                               MAC3req <= (resize(REG_IR3, 32), resize(REG_IR0, 32), mac3Last,         '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1');
                     
                     when 5 => pushRGBfromMAC <= '1';
                    
                     when 8 => if (turbomode = '1') then state <= IDLE; end if;
                     when 10 => state <= IDLE;
                     when others => null;
                  end case;
                  
               when CALC_MVMVA =>
                  case (calcStep) is
                     when 0 =>
                        case (cmdMM) is
                           when "00" => matrix00 <= REG_RT11; matrix01 <= REG_RT12; matrix02 <= REG_RT13;
                                        matrix10 <= REG_RT21; matrix11 <= REG_RT22; matrix12 <= REG_RT23;
                                        matrix20 <= REG_RT31; matrix21 <= REG_RT32; matrix22 <= REG_RT33;
                           when "01" => matrix00 <= REG_LL11; matrix01 <= REG_LL12; matrix02 <= REG_LL13;
                                        matrix10 <= REG_LL21; matrix11 <= REG_LL22; matrix12 <= REG_LL23;
                                        matrix20 <= REG_LL31; matrix21 <= REG_LL32; matrix22 <= REG_LL33;
                           when "10" => matrix00 <= REG_LC11; matrix01 <= REG_LC12; matrix02 <= REG_LC13;
                                        matrix10 <= REG_LC21; matrix11 <= REG_LC22; matrix12 <= REG_LC23;
                                        matrix20 <= REG_LC31; matrix21 <= REG_LC32; matrix22 <= REG_LC33;
                           when "11" => matrix00 <= to_signed(0, 16) - signed((x"0" & REG_RGBC(7 downto 0) & x"0")); 
                                        matrix01 <= signed(x"0" & REG_RGBC(7 downto 0) & x"0"); 
                                        matrix02 <= REG_IR0;
                                        matrix10 <= REG_RT13; matrix11 <= REG_RT13; matrix12 <= REG_RT13;
                                        matrix20 <= REG_RT22; matrix21 <= REG_RT22; matrix22 <= REG_RT22;
                           when others => null;
                        end case;
                        
                        case (cmdMV) is
                           when "00" => vector0 <= REG_V0X; vector1 <= REG_V0Y; vector2 <= REG_V0Z;
                           when "01" => vector0 <= REG_V1X; vector1 <= REG_V1Y; vector2 <= REG_V1Z;
                           when "10" => vector0 <= REG_V2X; vector1 <= REG_V2Y; vector2 <= REG_V2Z;
                           when "11" => vector0 <= REG_IR1; vector1 <= REG_IR2; vector2 <= REG_IR3;
                           when others => null;
                        end case;
                        
                        case (cmdTV) is
                           when "00" => translate0 <= signed(REG_TR0); translate1 <= signed(REG_TR1); translate2 <= signed(REG_TR2);
                           when "01" => translate0 <= signed(REG_BK0); translate1 <= signed(REG_BK1); translate2 <= signed(REG_BK2);
                           when "10" => translate0 <= signed(REG_FC0); translate1 <= signed(REG_FC1); translate2 <= signed(REG_FC2);
                           when "11" => translate0 <= x"00000000";     translate1 <= x"00000000";     translate2 <= x"00000000";
                           when others => null;
                        end case;
                     --                     mul1                    mul2                     add        sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 1 => MAC1req <= (translate0,           x"00001000",         to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (translate1,           x"00001000",         to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (translate2,           x"00001000",         to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1');  
                                                                 
                     when 2 =>                                   
                        if (cmdTV = "10") then -- buggy               
                               MAC1req <= (resize(matrix00, 32), resize(vector0, 32), to_signed(0, 45), '0', '0',      '0', '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1'); 
                               MAC2req <= (resize(matrix10, 32), resize(vector0, 32), to_signed(0, 45), '0', '0',      '0', '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1'); 
                               MAC3req <= (resize(matrix20, 32), resize(vector0, 32), to_signed(0, 45), '0', '0',      '0', '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1');
                        else
                               MAC1req <= (resize(matrix00, 32), resize(vector0, 32), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC2req <= (resize(matrix10, 32), resize(vector0, 32), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC3req <= (resize(matrix20, 32), resize(vector0, 32), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                        end if;
                               
                     when 3 => 
                        if (cmdTV = "10") then -- buggy
                               MAC1req <= (resize(matrix01, 32), resize(vector1, 32), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (resize(matrix11, 32), resize(vector1, 32), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (resize(matrix21, 32), resize(vector1, 32), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1');
                        else                                     
                               MAC1req <= (resize(matrix01, 32), resize(vector1, 32), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC2req <= (resize(matrix11, 32), resize(vector1, 32), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC3req <= (resize(matrix21, 32), resize(vector1, 32), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                        end if;                                  
                                                                 
                     when 4 => MAC1req <= (resize(matrix02, 32), resize(vector2, 32), to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1');
                               MAC2req <= (resize(matrix12, 32), resize(vector2, 32), to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1');
                               MAC3req <= (resize(matrix22, 32), resize(vector2, 32), to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1');
                    
                     when 6 => if (turbomode = '1') then state <= IDLE; end if;
                     when 10 => state <= IDLE;
                     when others => null;
                  end case;
               
               when CALC_NCDS | CALC_NCDT =>
                  case (calcStep) is
                     when 0 =>
                        case (batchCount) is
                           when 0 => vector0 <= REG_V0X; vector1 <= REG_V0Y; vector2 <= REG_V0Z;
                           when 1 => vector0 <= REG_V1X; vector1 <= REG_V1Y; vector2 <= REG_V1Z;
                           when 2 => vector0 <= REG_V2X; vector1 <= REG_V2Y; vector2 <= REG_V2Z;
                        end case;

                     --                     mul1                       mul2                                            add     sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 1 => MAC1req <= (resize(REG_LL11, 32), resize(vector0, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (resize(REG_LL21, 32), resize(vector0, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (resize(REG_LL31, 32), resize(vector0, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                                                                                             
                     when 2 => MAC1req <= (resize(REG_LL12, 32), resize(vector1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                               MAC2req <= (resize(REG_LL22, 32), resize(vector1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                               MAC3req <= (resize(REG_LL32, 32), resize(vector1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                                                                                                             
                     when 3 => MAC1req <= (resize(REG_LL13, 32), resize(vector2, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC2req <= (resize(REG_LL23, 32), resize(vector2, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC3req <= (resize(REG_LL33, 32), resize(vector2, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1');
                                                                                                             
                     --  mat mul with color matrix                                                           
                     when 4 => MAC1req <= (signed(REG_BK0),       x"00001000",                               to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (signed(REG_BK1),       x"00001000",                               to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (signed(REG_BK2),       x"00001000",                               to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                                                                                             
                     when 6 => MAC1req <= (resize(REG_LC11, 32), resize(REG_IR1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC2req <= (resize(REG_LC21, 32), resize(REG_IR1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC3req <= (resize(REG_LC31, 32), resize(REG_IR1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                                                                                                             
                     when 7 => MAC1req <= (resize(REG_LC12, 32), resize(REG_IR2, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                               MAC2req <= (resize(REG_LC22, 32), resize(REG_IR2, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                               MAC3req <= (resize(REG_LC32, 32), resize(REG_IR2, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                                                                                                             
                     when 8 => MAC1req <= (resize(REG_LC13, 32), resize(REG_IR3, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC2req <= (resize(REG_LC23, 32), resize(REG_IR3, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC3req <= (resize(REG_LC33, 32), resize(REG_IR3, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1');

                     -- prepare IR for InterpolateColor
                     when 11 => MAC1req <= (resize(REG_IR1, 32),  signed(x"000000" & REG_RGBC( 7 downto  0)), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                MAC2req <= (resize(REG_IR2, 32),  signed(x"000000" & REG_RGBC(15 downto  8)), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                MAC3req <= (resize(REG_IR3, 32),  signed(x"000000" & REG_RGBC(23 downto 16)), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 

                     when 13 => MAC1req <= (mac1_result,         x"00000010",                                to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                MAC2req <= (mac2_result,         x"00000010",                                to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                MAC3req <= (mac3_result,         x"00000010",                                to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1');

                     -- InterpolateColor
                     when 14 => MAC1req <= (signed(REG_FC0),     x"00001000",                                to_signed(0, 45), '1', '1', cmdShift, '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1'); 
                                MAC2req <= (signed(REG_FC1),     x"00001000",                                to_signed(0, 45), '1', '1', cmdShift, '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1'); 
                                MAC3req <= (signed(REG_FC2),     x"00001000",                                to_signed(0, 45), '1', '1', cmdShift, '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1');

                     when 17 => MAC1req <= (resize(REG_IR1, 32), resize(REG_IR0, 32),                        mac1Last,         '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1'); 
                                MAC2req <= (resize(REG_IR2, 32), resize(REG_IR0, 32),                        mac2Last,         '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1'); 
                                MAC3req <= (resize(REG_IR3, 32), resize(REG_IR0, 32),                        mac3Last,         '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1');

                     when 18 => pushRGBfromMAC <= '1';       
                     
                     when 21 => 
                        if (state = CALC_NCDS or batchCount = 2) then
                           if (turbomode = '1') then 
                              state <= IDLE; 
                           end if;
                        else
                           calcStep   <= 0;
                           batchCount <= batchCount + 1;
                        end if;
                     
                     when 33 => if (state = CALC_NCDS) then state <= IDLE; end if;
                     when 39 => state <= IDLE;   
                     when others => null;
                  end case;        

            when CALC_CDP =>
                  case (calcStep) is
                     --                     mul1                       mul2                                            add     sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger                                                                          
                     --  mat mul with color matrix                                                           
                     when 0 => MAC1req <= (signed(REG_BK0),       x"00001000",                               to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (signed(REG_BK1),       x"00001000",                               to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (signed(REG_BK2),       x"00001000",                               to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                                                                                             
                     when 1 => MAC1req <= (resize(REG_LC11, 32), resize(REG_IR1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC2req <= (resize(REG_LC21, 32), resize(REG_IR1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC3req <= (resize(REG_LC31, 32), resize(REG_IR1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                                                                                                             
                     when 2 => MAC1req <= (resize(REG_LC12, 32), resize(REG_IR2, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                               MAC2req <= (resize(REG_LC22, 32), resize(REG_IR2, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                               MAC3req <= (resize(REG_LC32, 32), resize(REG_IR2, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                                                                                                             
                     when 3 => MAC1req <= (resize(REG_LC13, 32), resize(REG_IR3, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC2req <= (resize(REG_LC23, 32), resize(REG_IR3, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC3req <= (resize(REG_LC33, 32), resize(REG_IR3, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1');

                     -- prepare IR for InterpolateColor
                     when 6 => MAC1req <= (resize(REG_IR1, 32),  signed(x"000000" & REG_RGBC( 7 downto  0)), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (resize(REG_IR2, 32),  signed(x"000000" & REG_RGBC(15 downto  8)), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (resize(REG_IR3, 32),  signed(x"000000" & REG_RGBC(23 downto 16)), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 

                     when 8 =>  MAC1req <= (mac1_result,         x"00000010",                                to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                MAC2req <= (mac2_result,         x"00000010",                                to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                MAC3req <= (mac3_result,         x"00000010",                                to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1');

                     -- InterpolateColor
                     when 9 =>  MAC1req <= (signed(REG_FC0),     x"00001000",                                to_signed(0, 45), '1', '1', cmdShift, '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1'); 
                                MAC2req <= (signed(REG_FC1),     x"00001000",                                to_signed(0, 45), '1', '1', cmdShift, '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1'); 
                                MAC3req <= (signed(REG_FC2),     x"00001000",                                to_signed(0, 45), '1', '1', cmdShift, '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1');

                     when 12 => MAC1req <= (resize(REG_IR1, 32), resize(REG_IR0, 32),                        mac1Last,         '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1'); 
                                MAC2req <= (resize(REG_IR2, 32), resize(REG_IR0, 32),                        mac2Last,         '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1'); 
                                MAC3req <= (resize(REG_IR3, 32), resize(REG_IR0, 32),                        mac3Last,         '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1');

                     when 13 => pushRGBfromMAC <= '1';
                               
                     when 16 => if (turbomode = '1') then state <= IDLE; end if;
                     when 20 => state <= IDLE;
                     when others => null;
                  end case;   

            when CALC_NCCS | CALC_NCCT =>
                  case (calcStep) is
                     when 0 =>
                        case (batchCount) is
                           when 0 => vector0 <= REG_V0X; vector1 <= REG_V0Y; vector2 <= REG_V0Z;
                           when 1 => vector0 <= REG_V1X; vector1 <= REG_V1Y; vector2 <= REG_V1Z;
                           when 2 => vector0 <= REG_V2X; vector1 <= REG_V2Y; vector2 <= REG_V2Z;
                        end case;

                     --                     mul1                       mul2                                            add     sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 1 => MAC1req <= (resize(REG_LL11, 32), resize(vector0, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (resize(REG_LL21, 32), resize(vector0, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (resize(REG_LL31, 32), resize(vector0, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                                                                                             
                     when 2 => MAC1req <= (resize(REG_LL12, 32), resize(vector1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                               MAC2req <= (resize(REG_LL22, 32), resize(vector1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                               MAC3req <= (resize(REG_LL32, 32), resize(vector1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                                                                                                             
                     when 3 => MAC1req <= (resize(REG_LL13, 32), resize(vector2, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC2req <= (resize(REG_LL23, 32), resize(vector2, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC3req <= (resize(REG_LL33, 32), resize(vector2, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1');
                                                                                                             
                     --  mat mul with color matrix                                                           
                     when 4 => MAC1req <= (signed(REG_BK0),       x"00001000",                               to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (signed(REG_BK1),       x"00001000",                               to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (signed(REG_BK2),       x"00001000",                               to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                                                                                             
                     when 6 => MAC1req <= (resize(REG_LC11, 32), resize(REG_IR1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC2req <= (resize(REG_LC21, 32), resize(REG_IR1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC3req <= (resize(REG_LC31, 32), resize(REG_IR1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                                                                                                             
                     when 7 => MAC1req <= (resize(REG_LC12, 32), resize(REG_IR2, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                               MAC2req <= (resize(REG_LC22, 32), resize(REG_IR2, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                               MAC3req <= (resize(REG_LC32, 32), resize(REG_IR2, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                                                                                                             
                     when 8 => MAC1req <= (resize(REG_LC13, 32), resize(REG_IR3, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC2req <= (resize(REG_LC23, 32), resize(REG_IR3, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC3req <= (resize(REG_LC33, 32), resize(REG_IR3, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1');

                     -- prepare IR for InterpolateColor
                     when 11 => MAC1req <= (resize(REG_IR1, 32), signed(x"000000" & REG_RGBC( 7 downto  0)), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                MAC2req <= (resize(REG_IR2, 32), signed(x"000000" & REG_RGBC(15 downto  8)), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                MAC3req <= (resize(REG_IR3, 32), signed(x"000000" & REG_RGBC(23 downto 16)), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 

                     when 13 => MAC1req <= (mac1_result,         x"00000010",                                to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1');
                                MAC2req <= (mac2_result,         x"00000010",                                to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1');
                                MAC3req <= (mac3_result,         x"00000010",                                to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1');

                     when 14 => pushRGBfromMAC <= '1';
                               
                     when 17 => 
                        if (state = CALC_NCCS or batchCount = 2) then
                           if (turbomode = '1') then 
                              state <= IDLE; 
                           end if;
                        else
                           calcStep   <= 0;
                           batchCount <= batchCount + 1;
                        end if;
                     
                     when 29 => if (state = CALC_NCCS) then state <= IDLE; end if;
                     when 37 => state <= IDLE;
                     when others => null;
                  end case;  
                  
               when CALC_CC =>
                  case (calcStep) is
                     --                     mul1                       mul2                                            add     sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger                                                                          
                     --  mat mul with color matrix                                                           
                     when 0 => MAC1req <= (signed(REG_BK0),       x"00001000",                               to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (signed(REG_BK1),       x"00001000",                               to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (signed(REG_BK2),       x"00001000",                               to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                                                                                             
                     when 1 => MAC1req <= (resize(REG_LC11, 32), resize(REG_IR1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC2req <= (resize(REG_LC21, 32), resize(REG_IR1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC3req <= (resize(REG_LC31, 32), resize(REG_IR1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                                                                                                             
                     when 2 => MAC1req <= (resize(REG_LC12, 32), resize(REG_IR2, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                               MAC2req <= (resize(REG_LC22, 32), resize(REG_IR2, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                               MAC3req <= (resize(REG_LC32, 32), resize(REG_IR2, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                                                                                                             
                     when 3 => MAC1req <= (resize(REG_LC13, 32), resize(REG_IR3, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC2req <= (resize(REG_LC23, 32), resize(REG_IR3, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC3req <= (resize(REG_LC33, 32), resize(REG_IR3, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1');

                     -- prepare IR for InterpolateColor
                     when 6 => MAC1req <= (resize(REG_IR1, 32),  signed(x"000000" & REG_RGBC( 7 downto  0)), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (resize(REG_IR2, 32),  signed(x"000000" & REG_RGBC(15 downto  8)), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (resize(REG_IR3, 32),  signed(x"000000" & REG_RGBC(23 downto 16)), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 

                     when 8 => MAC1req <= (mac1_result,          x"00000010",                                to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1');
                               MAC2req <= (mac2_result,          x"00000010",                                to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1');
                               MAC3req <= (mac3_result,          x"00000010",                                to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1');

                     when 9 => pushRGBfromMAC <= '1';
                               
                     when 12 => if (turbomode = '1') then state <= IDLE; end if;
                     when 16 => state <= IDLE;
                     when others => null;
                  end case; 

               when CALC_NCS | CALC_NCT =>
                  case (calcStep) is
                     when 0 =>
                        case (batchCount) is
                           when 0 => vector0 <= REG_V0X; vector1 <= REG_V0Y; vector2 <= REG_V0Z;
                           when 1 => vector0 <= REG_V1X; vector1 <= REG_V1Y; vector2 <= REG_V1Z;
                           when 2 => vector0 <= REG_V2X; vector1 <= REG_V2Y; vector2 <= REG_V2Z;
                        end case;

                     --                     mul1                       mul2                                            add     sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 1 => MAC1req <= (resize(REG_LL11, 32), resize(vector0, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (resize(REG_LL21, 32), resize(vector0, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (resize(REG_LL31, 32), resize(vector0, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                                                                                             
                     when 2 => MAC1req <= (resize(REG_LL12, 32), resize(vector1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                               MAC2req <= (resize(REG_LL22, 32), resize(vector1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                               MAC3req <= (resize(REG_LL32, 32), resize(vector1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                                                                                                             
                     when 3 => MAC1req <= (resize(REG_LL13, 32), resize(vector2, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC2req <= (resize(REG_LL23, 32), resize(vector2, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC3req <= (resize(REG_LL33, 32), resize(vector2, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1');
                                                                                                             
                     --  mat mul with color matrix                                                           
                     when 4 => MAC1req <= (signed(REG_BK0),       x"00001000",                               to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (signed(REG_BK1),       x"00001000",                               to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (signed(REG_BK2),       x"00001000",                               to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                                                                                             
                     when 6 => MAC1req <= (resize(REG_LC11, 32), resize(REG_IR1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC2req <= (resize(REG_LC21, 32), resize(REG_IR1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                               MAC3req <= (resize(REG_LC31, 32), resize(REG_IR1, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1'); 
                                                                                                             
                     when 7 => MAC1req <= (resize(REG_LC12, 32), resize(REG_IR2, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                               MAC2req <= (resize(REG_LC22, 32), resize(REG_IR2, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                               MAC3req <= (resize(REG_LC32, 32), resize(REG_IR2, 32),                        to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '1',  '1');
                                                                                                             
                     when 8 => MAC1req <= (resize(REG_LC13, 32), resize(REG_IR3, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC2req <= (resize(REG_LC23, 32), resize(REG_IR3, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC3req <= (resize(REG_LC33, 32), resize(REG_IR3, 32),                        to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1');

                     when 9 => pushRGBfromMAC <= '1';
                               
                     when 12 => 
                        if (state = CALC_NCS or batchCount = 2) then
                           if (turbomode = '1') then 
                              state <= IDLE; 
                           end if;
                        else
                           calcStep   <= 0;
                           batchCount <= batchCount + 1;
                        end if;
                     when 22 => if (state = CALC_NCS) then state <= IDLE; end if;
                     when 28 => state <= IDLE;
                     when others => null;
                  end case;                  
                  
               when CALC_SQR =>
                  case (calcStep) is
                     --                     mul1                       mul2                    add     sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 0 => MAC1req <= (resize(REG_IR1, 32), resize(REG_IR1, 32), to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1'); 
                               MAC2req <= (resize(REG_IR2, 32), resize(REG_IR2, 32), to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1'); 
                               MAC3req <= (resize(REG_IR3, 32), resize(REG_IR3, 32), to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1'); 
                     when 2 => if (turbomode = '1') then state <= IDLE; end if;
                     when 5 => state <= IDLE;
                     when others => null;
                  end case;
                  
               when CALC_DPCL =>
                  case (calcStep) is
                     --                     mul1                       mul2                                            add     sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     -- prepare IR for InterpolateColor
                     when 0  => MAC1req <= (resize(REG_IR1, 32), signed(x"000000" & REG_RGBC( 7 downto  0)), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                MAC2req <= (resize(REG_IR2, 32), signed(x"000000" & REG_RGBC(15 downto  8)), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                MAC3req <= (resize(REG_IR3, 32), signed(x"000000" & REG_RGBC(23 downto 16)), to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 

                     when 2  => MAC1req <= (mac1_result,         x"00000010",                                to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                MAC2req <= (mac2_result,         x"00000010",                                to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                                MAC3req <= (mac3_result,         x"00000010",                                to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1');

                     -- InterpolateColor
                     when 3  => MAC1req <= (signed(REG_FC0),     x"00001000",                                to_signed(0, 45), '1', '1', cmdShift, '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1'); 
                                MAC2req <= (signed(REG_FC1),     x"00001000",                                to_signed(0, 45), '1', '1', cmdShift, '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1'); 
                                MAC3req <= (signed(REG_FC2),     x"00001000",                                to_signed(0, 45), '1', '1', cmdShift, '1', cmdShift, cmdShift,      '0',      '0',  '1',  '1');

                     when 6  => MAC1req <= (resize(REG_IR1, 32), resize(REG_IR0, 32),                        mac1Last,         '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1'); 
                                MAC2req <= (resize(REG_IR2, 32), resize(REG_IR0, 32),                        mac2Last,         '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1'); 
                                MAC3req <= (resize(REG_IR3, 32), resize(REG_IR0, 32),                        mac3Last,         '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1');

                     when 7  => pushRGBfromMAC <= '1';
                     when 10 => state <= IDLE;
                     when others => null;
                  end case;

               when CALC_AVSZ3 =>
                  case (calcStep) is
                     --                     mul1                            mul2            add     sub  swap useIR IRs cOvf uRes trigger
                     when 0 => MAC0req <= ('0' & signed(REG_SZ1), resize(REG_ZSF3,18), x"00000000", '0', '0', '0', '0', '1', '0', '1'); 
                     when 1 => MAC0req <= ('0' & signed(REG_SZ2), resize(REG_ZSF3,18), x"00000000", '0', '0', '0', '0', '1', '1', '1'); 
                     when 2 => MAC0req <= ('0' & signed(REG_SZ3), resize(REG_ZSF3,18), x"00000000", '0', '0', '0', '0', '1', '1', '1'); 
                     when 3 => setOTZ <= '1';
                     when 5 => state <= IDLE;
                     when others => null;
                  end case;                  
               
               when CALC_AVSZ4 =>
                  case (calcStep) is
                     --                     mul1                            mul2            add     sub  swap useIR IRs cOvf uRes trigger
                     when 0 => MAC0req <= ('0' & signed(REG_SZ0), resize(REG_ZSF4,18), x"00000000", '0', '0', '0', '0', '1', '0', '1'); 
                     when 1 => MAC0req <= ('0' & signed(REG_SZ1), resize(REG_ZSF4,18), x"00000000", '0', '0', '0', '0', '1', '1', '1'); 
                     when 2 => MAC0req <= ('0' & signed(REG_SZ2), resize(REG_ZSF4,18), x"00000000", '0', '0', '0', '0', '1', '1', '1'); 
                     when 3 => MAC0req <= ('0' & signed(REG_SZ3), resize(REG_ZSF4,18), x"00000000", '0', '0', '0', '0', '1', '1', '1'); 
                     when 4 => setOTZ <= '1';
                     when 7 => state <= IDLE;
                     when others => null;
                  end case;  
            
               when CALC_GPF =>
                  case (calcStep) is
                     --                    mul1                       mul2                  add        sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 0 => MAC1req <= (resize(REG_IR1, 32), resize(REG_IR0, 32), to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1'); 
                               MAC2req <= (resize(REG_IR2, 32), resize(REG_IR0, 32), to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1'); 
                               MAC3req <= (resize(REG_IR3, 32), resize(REG_IR0, 32), to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '0',  '1');

                     when 1 => pushRGBfromMAC <= '1';
                     when 4 => state <= IDLE;
                     when others => null;
                  end case;
               
               when CALC_GPL =>
                  case (calcStep) is
                     when 0 =>
                        if (cmdShift = '1') then 
                           shiftvalue <= x"00001000";
                        else
                           shiftvalue <= x"00000001";
                        end if;
                     --                    mul1                      mul2                   add        sub  swap    svSh  useIR    IRs    IRsF        satIR     satIRF  uRes trigger
                     when 1 => MAC1req <= (REG_MAC1,            shiftvalue,          to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC2req <= (REG_MAC2,            shiftvalue,          to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                               MAC3req <= (REG_MAC3,            shiftvalue,          to_signed(0, 45), '0', '0',      '0', '0',      '0',      '0',      '0',      '0',  '0',  '1'); 
                     
                     when 2 => MAC1req <= (resize(REG_IR1, 32), resize(REG_IR0, 32), to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC2req <= (resize(REG_IR2, 32), resize(REG_IR0, 32), to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1'); 
                               MAC3req <= (resize(REG_IR3, 32), resize(REG_IR0, 32), to_signed(0, 45), '0', '0', cmdShift, '1', cmdShift, cmdShift, cmdsatIR, cmdsatIR,  '1',  '1');

                     when 3 => pushRGBfromMAC <= '1';
                     when 5 => state <= IDLE;
                     when others => null;
                  end case;
            
            end case;
            
            if (NARROW_MUL = 3) then
               -- this step's requests (req3 was decoded one step early); the
               -- operands go to the MAC units through MACxmul3 (see below)
               MAC0req3.trigger <= '0';
               MAC1req3.trigger <= '0';
               MAC2req3.trigger <= '0';
               MAC3req3.trigger <= '0';
               if (req3.t = '1') then
                  --             mul1              mul2              add                             sub       swap       svSh                   useIR       IRs                   IRsF                                 satIR                  satIRF                                    uRes       trigger
                  MAC1req3 <= (to_signed(0, 32), to_signed(0, 32), add3(req3, REG_TR0, mac1Last), req3.sub, req3.swap, req3.svSh and cmdShift, req3.useIR, req3.IRs and cmdShift, req3.IRsF and cmdShift,                req3.sat and cmdsatIR, req3.satF and cmdsatIR,                   req3.uRes, '1');
                  MAC2req3 <= (to_signed(0, 32), to_signed(0, 32), add3(req3, REG_TR1, mac2Last), req3.sub, req3.swap, req3.svSh and cmdShift, req3.useIR, req3.IRs and cmdShift, req3.IRsF and cmdShift,                req3.sat and cmdsatIR, req3.satF and cmdsatIR,                   req3.uRes, '1');
                  MAC3req3 <= (to_signed(0, 32), to_signed(0, 32), add3(req3, REG_TR2, mac3Last), req3.sub, req3.swap, req3.svSh and cmdShift, req3.useIR, req3.IRs and cmdShift, (req3.IRsF and cmdShift) or req3.r2, req3.sat and cmdsatIR, req3.satF and cmdsatIR and not req3.r2, req3.uRes, '1');
               end if;
               if (req3.t0 = '1') then
                  MAC0req3 <= (to_signed(0, 17), to_signed(0, 18),
                               s32(req3.add0OFX, signed(REG_OFX)) or s32(req3.add0OFY, signed(REG_OFY)) or s32(req3.add0DQB, signed(REG_DQB)),
                               req3.sub0, '0', req3.useIR0, req3.IRs0, req3.cOvf0, req3.uRes0, '1');
               end if;

               -- steps: exits and loops of the case statement above, from the
               -- flags decoded one step early; overrides its state, calcStep
               -- and batchCount assignments outside IDLE
               v3_exit  := req3.xA = '1' or (turbomode = '1' and (req3.xT = '1' or (req3.lp = '1' and batchCount = 2)));
               v3_loop  := req3.lp = '1' and batchCount /= 2;
               v3_state := state;
               if (v3_exit) then
                  v3_state := IDLE;
               end if;
               v3_step := calcStep + 1;
               if (v3_loop) then
                  v3_step := 0;
               end if;
               if (state /= IDLE) then
                  if (v3_loop) then
                     batchCount <= batchCount + 1;
                  else
                     batchCount <= batchCount;
                  end if;
                  state    <= v3_state;
                  calcStep <= v3_step;
               end if;
               -- first step of a new command and next step of the running one
               -- are decoded separately; state = IDLE only selects between them
               v3_first := req3At(opState3(gte_cmdData(5 downto 0)), 0, gte_cmdData(14 downto 13));
               if (gte_cmdEna = '0' or clk2xIndex = '0') then
                  v3_first := REQ3_NONE;
               end if;
               v3_next := req3At(state, v3_step, cmdTV);
               if (v3_exit) then
                  v3_next := REQ3_NONE;
               end if;
               if (state = IDLE) then
                  req3 <= v3_first;
               else
                  req3 <= v3_next;
               end if;
            end if;

            -- push RGB from MAC
            if (pushRGBfromMAC = '1') then
               if (mac1_result < 0) then
                  REG_FLAG(21) <= '1';
                  REG_RGB2(7 downto 0) <= (others => '0');
               elsif (unsigned(mac1_result(31 downto 4)) > 255) then
                  REG_FLAG(21) <= '1';
                  REG_RGB2(7 downto 0) <= (others => '1');
               else
                  REG_RGB2(7 downto 0) <= unsigned(mac1_result(11 downto 4));
               end if;
               
               if (mac2_result < 0) then
                  REG_FLAG(20) <= '1';
                  REG_RGB2(15 downto 8) <= (others => '0');
               elsif (unsigned(mac2_result(31 downto 4)) > 255) then
                  REG_FLAG(20) <= '1';
                  REG_RGB2(15 downto 8) <= (others => '1');
               else
                  REG_RGB2(15 downto 8) <= unsigned(mac2_result(11 downto 4));
               end if;
               
               if (mac3_result < 0) then
                  REG_FLAG(19) <= '1';
                  REG_RGB2(23 downto 16) <= (others => '0');
               elsif (unsigned(mac3_result(31 downto 4)) > 255) then
                  REG_FLAG(19) <= '1';
                  REG_RGB2(23 downto 16) <= (others => '1');
               else
                  REG_RGB2(23 downto 16) <= unsigned(mac3_result(11 downto 4));
               end if;
               
               REG_RGB2(31 downto 24) <= REG_RGBC(31 downto 24);
               REG_RGB0 <= REG_RGB1; REG_RGB1 <= REG_RGB2;
            
            end if;
            
            -- set OTZ
            if (setOTZ = '1') then
               if (mac0_result < 0) then
                  REG_OTZ <= (others => '0');
                  REG_FLAG(18) <= '1'; REG_FLAG(31) <= '1';
               elsif (mac0_result(34 downto 12) > 16#FFFF#) then
                  REG_OTZ <= (others => '1');
                  REG_FLAG(18) <= '1'; REG_FLAG(31) <= '1';
               else
                  REG_OTZ <= unsigned(mac0_result(27 downto 12));
               end if;
            end if;
            
            -- push sz and start divide
            if (pushSZandDivide = '1') then
               div_trigger <= '1';
               div_lhs     <= unsigned(REG_H);
               if (mac3Shifted < 0) then
                  REG_FLAG(18) <= '1'; REG_FLAG(31) <= '1';
                  REG_SZ3      <= x"0000";
                  div_rhs      <= x"0000";
               elsif (mac3Shifted > 16#FFFF#) then
                  REG_FLAG(18) <= '1'; REG_FLAG(31) <= '1';
                  REG_SZ3      <= x"FFFF";
                  div_rhs      <= x"FFFF";
               else
                  REG_SZ3      <= unsigned(mac3Shifted(15 downto 0));
                  div_rhs      <= unsigned(mac3Shifted(15 downto 0));
               end if;
               REG_SZ0 <= REG_SZ1; REG_SZ1 <= REG_SZ2; REG_SZ2 <= REG_SZ3;
            end if;
            
            -- push SXY
            if (pushSXY = '1') then
               if (mac0Last(34 downto 16) < -1024) then
                  REG_SX2 <= to_signed(-1024, 16);
                  REG_FLAG(14) <= '1'; REG_FLAG(31) <= '1';
               elsif (mac0Last(34 downto 16) > 1023) then
                  REG_SX2 <= to_signed(1023, 16);  
                  REG_FLAG(14) <= '1'; REG_FLAG(31) <= '1';                           
               else
                  REG_SX2 <= mac0Last(31 downto 16);  
               end if;   
               if (mac0_result(34 downto 16) < -1024) then
                  REG_SY2 <= to_signed(-1024, 16);
                  REG_FLAG(13) <= '1'; REG_FLAG(31) <= '1';
               elsif (mac0_result(34 downto 16) > 1023) then
                  REG_SY2 <= to_signed(1023, 16);   
                  REG_FLAG(13) <= '1'; REG_FLAG(31) <= '1';                           
               else
                  REG_SY2 <= mac0_result(31 downto 16);  
               end if; 
               REG_SX0 <= REG_SX1; REG_SX1 <= REG_SX2;
               REG_SY0 <= REG_SY1; REG_SY1 <= REG_SY2;
            end if;
            
            -- writebacks
            if (mac0_writeback = '1') then REG_MAC0 <= mac0_result(31 downto 0); end if;
            if (mac1_writeback = '1') then REG_MAC1 <= mac1_result; end if;
            if (mac2_writeback = '1') then REG_MAC2 <= mac2_result; end if;
            if (mac3_writeback = '1') then REG_MAC3 <= mac3_result; end if;            
            
            if (ir0_writeback = '1') then REG_IR0 <= ir0_result; end if;
            if (ir1_writeback = '1') then REG_IR1 <= ir1_result; end if;
            if (ir2_writeback = '1') then REG_IR2 <= ir2_result; end if;
            if (ir3_writeback = '1') then REG_IR3 <= ir3_result; end if;
            
            -- flags
            if (flagMac0UF = '1') then REG_FLAG(15) <= '1'; REG_FLAG(31) <= '1'; end if;
            if (flagMac0OF = '1') then REG_FLAG(16) <= '1'; REG_FLAG(31) <= '1'; end if;            
            
            if (flagMac1UF = '1') then REG_FLAG(27) <= '1'; REG_FLAG(31) <= '1'; end if;
            if (flagMac1OF = '1') then REG_FLAG(30) <= '1'; REG_FLAG(31) <= '1'; end if;
            
            if (flagMac2UF = '1') then REG_FLAG(26) <= '1'; REG_FLAG(31) <= '1'; end if;
            if (flagMac2OF = '1') then REG_FLAG(29) <= '1'; REG_FLAG(31) <= '1'; end if;
            
            if (flagMac3UF = '1') then REG_FLAG(25) <= '1'; REG_FLAG(31) <= '1'; end if;
            if (flagMac3OF = '1') then REG_FLAG(28) <= '1'; REG_FLAG(31) <= '1'; end if;
            
            if (flagIR0 = '1') then REG_FLAG(12) <= '1'; end if;
            if (flagIR1 = '1') then REG_FLAG(24) <= '1'; REG_FLAG(31) <= '1'; end if;
            if (flagIR2 = '1') then REG_FLAG(23) <= '1'; REG_FLAG(31) <= '1'; end if;
            if (flagIR3 = '1') then REG_FLAG(22) <= '1'; end if;
            
            if (div_Error = '1') then REG_FLAG(17) <= '1'; REG_FLAG(31) <= '1'; end if;
         
         end if;
         
      end if;
   end process;
   
   -- NARROW_MUL = 3: operands of the request being written, straight from the
   -- registers selected by req3 into the MAC units' multipliers
   g3mul : if NARROW_MUL = 3 generate
   begin
      procEna3 <= '1' when ((reset = '0' or loading_savestate = '1') and (ce = '1' or loading_savestate = '1')) else '0';

      MAC0mul3.mul1 <= resize(s18(req3.a0Asp,  IR1aspect)   or s18(req3.a0Asp1,  IR1aspect_1) or s18(req3.a0Asp2,  IR1aspect_2) or
                              s18(req3.a0IR2,  REG_IR2)     or s18(req3.a0IR2_1, REG_IR2_1)   or s18(req3.a0IR2_2, REG_IR2_2)   or s18(req3.a0DQA, REG_DQA) or
                              s18(req3.a0SX0,  REG_SX0)     or s18(req3.a0SX1,   REG_SX1)     or s18(req3.a0SX2,   REG_SX2)     or
                              s18(req3.a0SZ0,  signed('0' & REG_SZ0)) or s18(req3.a0SZ1, signed('0' & REG_SZ1)) or
                              s18(req3.a0SZ2,  signed('0' & REG_SZ2)) or s18(req3.a0SZ3, signed('0' & REG_SZ3)), 17);
      MAC0mul3.mul2 <= s18(req3.b0Div, signed('0' & div_result)) or s18(req3.b0SY0, REG_SY0) or s18(req3.b0SY1, REG_SY1) or s18(req3.b0SY2, REG_SY2) or
                       s18(req3.b0ZSF3, REG_ZSF3) or s18(req3.b0ZSF4, REG_ZSF4);
      MAC0mul3.ena  <= procEna3 and req3.t0;

      --                            RTx1      RTx2      RTx3      OP0       OP1       IR       matrix                        LL                            LC
      MAC1mul3.mul1    <= mulA3(req3, REG_RT11, REG_RT12, REG_RT13, REG_RT22, REG_RT33, REG_IR1, matrix00, matrix01, matrix02, REG_LL11, REG_LL12, REG_LL13, REG_LC11, REG_LC12, REG_LC13);
      MAC2mul3.mul1    <= mulA3(req3, REG_RT21, REG_RT22, REG_RT23, REG_RT33, REG_RT11, REG_IR2, matrix10, matrix11, matrix12, REG_LL21, REG_LL22, REG_LL23, REG_LC21, REG_LC22, REG_LC23);
      MAC3mul3.mul1    <= mulA3(req3, REG_RT31, REG_RT32, REG_RT33, REG_RT11, REG_RT22, REG_IR3, matrix20, matrix21, matrix22, REG_LL31, REG_LL32, REG_LL33, REG_LC31, REG_LC32, REG_LC33);
      --                            V0, V1, V2                                                                               OP0      OP1      IR0      IR1      IR2      IR3      vector                     IRi      RGBC byte
      MAC1mul3.mul2    <= mulB3(req3, REG_V0X, REG_V0Y, REG_V0Z, REG_V1X, REG_V1Y, REG_V1Z, REG_V2X, REG_V2Y, REG_V2Z, REG_IR3, REG_IR2, REG_IR0, REG_IR1, REG_IR2, REG_IR3, vector0, vector1, vector2, REG_IR1, REG_RGBC( 7 downto  0));
      MAC2mul3.mul2    <= mulB3(req3, REG_V0X, REG_V0Y, REG_V0Z, REG_V1X, REG_V1Y, REG_V1Z, REG_V2X, REG_V2Y, REG_V2Z, REG_IR1, REG_IR3, REG_IR0, REG_IR1, REG_IR2, REG_IR3, vector0, vector1, vector2, REG_IR2, REG_RGBC(15 downto  8));
      MAC3mul3.mul2    <= mulB3(req3, REG_V0X, REG_V0Y, REG_V0Z, REG_V1X, REG_V1Y, REG_V1Z, REG_V2X, REG_V2Y, REG_V2Z, REG_IR2, REG_IR1, REG_IR0, REG_IR1, REG_IR2, REG_IR3, vector0, vector1, vector2, REG_IR3, REG_RGBC(23 downto 16));
      --                             colour                     FC               translate   BK               mac_result   MAC       IR       GPL x 1000h
      MAC1mul3.shifted <= shift3(req3, calcColor( 7 downto  0), signed(REG_FC0), translate0, signed(REG_BK0), mac1_result, REG_MAC1, REG_IR1, shiftvalue(12));
      MAC2mul3.shifted <= shift3(req3, calcColor(15 downto  8), signed(REG_FC1), translate1, signed(REG_BK1), mac2_result, REG_MAC2, REG_IR2, shiftvalue(12));
      MAC3mul3.shifted <= shift3(req3, calcColor(23 downto 16), signed(REG_FC2), translate2, signed(REG_BK2), mac3_result, REG_MAC3, REG_IR3, shiftvalue(12));
      MAC1mul3.isShift <= req3.sh;
      MAC2mul3.isShift <= req3.sh;
      MAC3mul3.isShift <= req3.sh;
      MAC1mul3.ena     <= procEna3 and req3.t;
      MAC2mul3.ena     <= procEna3 and req3.t;
      MAC3mul3.ena     <= procEna3 and req3.t;
   end generate;

   MAC0req_u <= MAC0req3 when (NARROW_MUL = 3) else MAC0req;
   MAC1req_u <= MAC1req3 when (NARROW_MUL = 3) else MAC1req;
   MAC2req_u <= MAC2req3 when (NARROW_MUL = 3) else MAC2req;
   MAC3req_u <= MAC3req3 when (NARROW_MUL = 3) else MAC3req;

   -- processing units
   igte_mac0 : entity work.gte_mac0
   generic map (NARROW_MUL => NARROW_MUL)
   port map
   (
      clk2x          => clk2x,         
      MAC0req        => MAC0req_u,
      MACmul         => MAC0mul3,       
      mac0_result    => mac0_result,   
      mac0_writeback => mac0_writeback,
      ir_result      => ir0_result,   
      ir_writeback   => ir0_writeback,
      mac0Last       => mac0Last,
      flagMac0UF     => flagMac0UF,
      flagMac0OF     => flagMac0OF,
      flagIR         => flagIR0
   );
   
   igte_mac1 : entity work.gte_mac123
   generic map (NARROW_MUL => NARROW_MUL)
   port map
   (
      clk2x          => clk2x,         
      MACreq         => MAC1req_u,
      MACmul         => MAC1mul3,       
      mac_result     => mac1_result,   
      mac_writeback  => mac1_writeback,
      ir_result      => ir1_result,   
      ir_writeback   => ir1_writeback,
      macLast        => mac1Last,
      flagMacUF      => flagMac1UF,
      flagMacOF      => flagMac1OF,
      flagIR         => flagIR1
   );
   
   igte_mac2 : entity work.gte_mac123
   generic map (NARROW_MUL => NARROW_MUL)
   port map
   (
      clk2x          => clk2x,         
      MACreq         => MAC2req_u,
      MACmul         => MAC2mul3,       
      mac_result     => mac2_result,   
      mac_writeback  => mac2_writeback,
      ir_result      => ir2_result,   
      ir_writeback   => ir2_writeback,
      macLast        => mac2Last,
      flagMacUF      => flagMac2UF,
      flagMacOF      => flagMac2OF,
      flagIR         => flagIR2
   );
   
   igte_mac3 : entity work.gte_mac123
   generic map (NARROW_MUL => NARROW_MUL)
   port map
   (
      clk2x          => clk2x,         
      MACreq         => MAC3req_u,
      MACmul         => MAC3mul3,       
      mac_result     => mac3_result,   
      mac_writeback  => mac3_writeback,
      ir_result      => ir3_result,   
      ir_writeback   => ir3_writeback,
      macLast        => mac3Last,
      macShifted     => mac3Shifted,
      flagMacUF      => flagMac3UF,
      flagMacOF      => flagMac3OF,
      flagIR         => flagIR3
   );
   
   igte_UNRDivide : entity work.gte_UNRDivide
   generic map (RETIME => divRetime(NARROW_MUL))
   port map
   (
      clk2x          => clk2x,        
      trigger        => div_trigger,
      lhs            => div_lhs,    
      rhs            => div_rhs,    
      result         => div_result, 
      divError       => div_Error  
   );

--##############################################################
--############################### savestates
--##############################################################

   process (clk2x)
   begin
      if (rising_edge(clk2x)) then
      
         SSreadAddr <= SS_Adr;
      
         case (to_integer(SSreadAddr)) is
            when 00 => SS_readData <= std_logic_vector(REG_V0Y & REG_V0X);       
            when 01 => SS_readData <= std_logic_vector(resize(REG_V0Z, 32));     
            when 02 => SS_readData <= std_logic_vector(REG_V1Y & REG_V1X);       
            when 03 => SS_readData <= std_logic_vector(resize(REG_V1Z, 32));     
            when 04 => SS_readData <= std_logic_vector(REG_V2Y & REG_V2X);       
            when 05 => SS_readData <= std_logic_vector(resize(REG_V2Z, 32));     
            when 06 => SS_readData <= std_logic_vector(REG_RGBC);                
            when 07 => SS_readData <= std_logic_vector(x"0000" & REG_OTZ);       
            when 08 => SS_readData <= std_logic_vector(resize(REG_IR0, 32));     
            when 09 => SS_readData <= std_logic_vector(resize(REG_IR1, 32));     
            when 10 => SS_readData <= std_logic_vector(resize(REG_IR2, 32));     
            when 11 => SS_readData <= std_logic_vector(resize(REG_IR3, 32));     
            when 12 => SS_readData <= std_logic_vector(REG_SY0 & REG_SX0);       
            when 13 => SS_readData <= std_logic_vector(REG_SY1 & REG_SX1);       
            when 14 => SS_readData <= std_logic_vector(REG_SY2 & REG_SX2);       
            when 15 => SS_readData <= x"00000000";       
            when 16 => SS_readData <= std_logic_vector(x"0000" & REG_SZ0);       
            when 17 => SS_readData <= std_logic_vector(x"0000" & REG_SZ1);       
            when 18 => SS_readData <= std_logic_vector(x"0000" & REG_SZ2);       
            when 19 => SS_readData <= std_logic_vector(x"0000" & REG_SZ3);       
            when 20 => SS_readData <= std_logic_vector(REG_RGB0);                
            when 21 => SS_readData <= std_logic_vector(REG_RGB1);                
            when 22 => SS_readData <= std_logic_vector(REG_RGB2);                
            when 23 => SS_readData <= std_logic_vector(REG_RES1);                
            when 24 => SS_readData <= std_logic_vector(REG_MAC0);                
            when 25 => SS_readData <= std_logic_vector(REG_MAC1);                
            when 26 => SS_readData <= std_logic_vector(REG_MAC2);                
            when 27 => SS_readData <= std_logic_vector(REG_MAC3);                
            when 28 => SS_readData <= std_logic_vector(x"0000" & '0' & REG_IRGB);
            when 29 => SS_readData <= std_logic_vector(x"0000" & '0' & REG_ORGB);
            when 30 => SS_readData <= std_logic_vector(REG_LZCS);                
            when 31 => SS_readData <= std_logic_vector(REG_LZCR);                
            when 32 => SS_readData <= std_logic_vector(REG_RT12 & REG_RT11);     
            when 33 => SS_readData <= std_logic_vector(REG_RT21 & REG_RT13);     
            when 34 => SS_readData <= std_logic_vector(REG_RT23 & REG_RT22);     
            when 35 => SS_readData <= std_logic_vector(REG_RT32 & REG_RT31);     
            when 36 => SS_readData <= std_logic_vector(resize(REG_RT33, 32));    
            when 37 => SS_readData <= std_logic_vector(REG_TR0);                 
            when 38 => SS_readData <= std_logic_vector(REG_TR1);                 
            when 39 => SS_readData <= std_logic_vector(REG_TR2);                 
            when 40 => SS_readData <= std_logic_vector(REG_LL12 & REG_LL11);     
            when 41 => SS_readData <= std_logic_vector(REG_LL21 & REG_LL13);     
            when 42 => SS_readData <= std_logic_vector(REG_LL23 & REG_LL22);     
            when 43 => SS_readData <= std_logic_vector(REG_LL32 & REG_LL31);     
            when 44 => SS_readData <= std_logic_vector(resize(REG_LL33, 32));    
            when 45 => SS_readData <= std_logic_vector(REG_BK0);                 
            when 46 => SS_readData <= std_logic_vector(REG_BK1);                 
            when 47 => SS_readData <= std_logic_vector(REG_BK2);                 
            when 48 => SS_readData <= std_logic_vector(REG_LC12 & REG_LC11);     
            when 49 => SS_readData <= std_logic_vector(REG_LC21 & REG_LC13);     
            when 50 => SS_readData <= std_logic_vector(REG_LC23 & REG_LC22);     
            when 51 => SS_readData <= std_logic_vector(REG_LC32 & REG_LC31);     
            when 52 => SS_readData <= std_logic_vector(resize(REG_LC33, 32));    
            when 53 => SS_readData <= std_logic_vector(REG_FC0);                 
            when 54 => SS_readData <= std_logic_vector(REG_FC1);                 
            when 55 => SS_readData <= std_logic_vector(REG_FC2);                 
            when 56 => SS_readData <= std_logic_vector(REG_OFX);                 
            when 57 => SS_readData <= std_logic_vector(REG_OFY);                 
            when 58 => SS_readData <= std_logic_vector(resize(REG_H, 32));       
            when 59 => SS_readData <= std_logic_vector(resize(REG_DQA, 32));     
            when 60 => SS_readData <= std_logic_vector(REG_DQB);                 
            when 61 => SS_readData <= std_logic_vector(resize(REG_ZSF3, 32));    
            when 62 => SS_readData <= std_logic_vector(resize(REG_ZSF4, 32));    
            when 63 => SS_readData <= std_logic_vector(REG_FLAG);                
            when others => null;
         end case;

      end if;
   end process;

   process (clk1x)
   begin
      if (rising_edge(clk1x)) then
      
         SS_idle <= '0';
         if (gte_busy = '0' and gte_cmdEna = '0' and gte_readEna = '0' and gte_writeEna_in = '0') then
            SS_idle <= '1';
         end if;
         
         SSrden <= SS_rden;
         if (SSrden = '1') then
            SS_DataRead <= SS_readData;
         end if;
      
      end if;
   end process;
   
   -- synthesis translate_off

   -- NARROW_MUL = 3: the early decode must always equal the decode of the current step
   gcheck3 : if NARROW_MUL = 3 generate
   begin
      process (clk2x)
      begin
         if falling_edge(clk2x) then
            assert (req3 = req3At(state, calcStep, cmdTV)) report "gte: req3 differs from the current step's requests" severity failure;
         end if;
      end process;
   end generate;
   
   goutput : if 1 = 1 generate
      signal outputCount         : integer := 0;
   begin
   
      process
         file outfile            : text;
         variable f_status       : FILE_OPEN_STATUS;
         variable line_out       : line;
         variable regcheck       : integer range 0 to 3; 
         variable busy_1         : std_logic := '0'; 
         variable gte_writeEna_1 : std_logic := '0';
         variable gte_readEna_1  : std_logic := '0';
         variable gte_cmdEna_1   : std_logic := '0';
         
         variable outputCountNew : integer;
         
         variable var_V0X   : signed(15 downto 0)   := (others => '0');
         variable var_V0Y   : signed(15 downto 0)   := (others => '0');
         variable var_V0Z   : signed(15 downto 0)   := (others => '0');
         variable var_V1X   : signed(15 downto 0)   := (others => '0');
         variable var_V1Y   : signed(15 downto 0)   := (others => '0');
         variable var_V1Z   : signed(15 downto 0)   := (others => '0');
         variable var_V2X   : signed(15 downto 0)   := (others => '0');
         variable var_V2Y   : signed(15 downto 0)   := (others => '0');
         variable var_V2Z   : signed(15 downto 0)   := (others => '0');
         variable var_RGBC  : unsigned(31 downto 0) := (others => '0');
         variable var_OTZ   : unsigned(15 downto 0) := (others => '0');
         variable var_IR0   : signed(15 downto 0)   := (others => '0');
         variable var_IR1   : signed(15 downto 0)   := (others => '0');
         variable var_IR2   : signed(15 downto 0)   := (others => '0');
         variable var_IR3   : signed(15 downto 0)   := (others => '0');
         variable var_SX0   : signed(15 downto 0)   := (others => '0');
         variable var_SY0   : signed(15 downto 0)   := (others => '0');
         variable var_SX1   : signed(15 downto 0)   := (others => '0');
         variable var_SY1   : signed(15 downto 0)   := (others => '0');
         variable var_SX2   : signed(15 downto 0)   := (others => '0');
         variable var_SY2   : signed(15 downto 0)   := (others => '0');
         variable var_SZ0   : unsigned(15 downto 0) := (others => '0');
         variable var_SZ1   : unsigned(15 downto 0) := (others => '0');
         variable var_SZ2   : unsigned(15 downto 0) := (others => '0');
         variable var_SZ3   : unsigned(15 downto 0) := (others => '0');
         variable var_RGB0  : unsigned(31 downto 0) := (others => '0');
         variable var_RGB1  : unsigned(31 downto 0) := (others => '0');
         variable var_RGB2  : unsigned(31 downto 0) := (others => '0');
         variable var_RES1  : unsigned(31 downto 0) := (others => '0');
         variable var_MAC0  : signed(31 downto 0)   := (others => '0');
         variable var_MAC1  : signed(31 downto 0)   := (others => '0');
         variable var_MAC2  : signed(31 downto 0)   := (others => '0');
         variable var_MAC3  : signed(31 downto 0)   := (others => '0');
         variable var_IRGB  : unsigned(14 downto 0) := (others => '0');
         variable var_ORGB  : unsigned(14 downto 0) := (others => '0');
         variable var_LZCS  : signed(31 downto 0)   := (others => '0');
         variable var_LZCR  : signed(31 downto 0)   := (others => '0');
         variable var_RT11  : signed(15 downto 0)   := (others => '0');
         variable var_RT12  : signed(15 downto 0)   := (others => '0');
         variable var_RT13  : signed(15 downto 0)   := (others => '0');
         variable var_RT21  : signed(15 downto 0)   := (others => '0');
         variable var_RT22  : signed(15 downto 0)   := (others => '0');
         variable var_RT23  : signed(15 downto 0)   := (others => '0');
         variable var_RT31  : signed(15 downto 0)   := (others => '0');
         variable var_RT32  : signed(15 downto 0)   := (others => '0');
         variable var_RT33  : signed(15 downto 0)   := (others => '0');
         variable var_TR0   : unsigned(31 downto 0) := (others => '0');
         variable var_TR1   : unsigned(31 downto 0) := (others => '0');
         variable var_TR2   : unsigned(31 downto 0) := (others => '0');
         variable var_LL11  : signed(15 downto 0)   := (others => '0');
         variable var_LL12  : signed(15 downto 0)   := (others => '0');
         variable var_LL13  : signed(15 downto 0)   := (others => '0');
         variable var_LL21  : signed(15 downto 0)   := (others => '0');
         variable var_LL22  : signed(15 downto 0)   := (others => '0');
         variable var_LL23  : signed(15 downto 0)   := (others => '0');
         variable var_LL31  : signed(15 downto 0)   := (others => '0');
         variable var_LL32  : signed(15 downto 0)   := (others => '0');
         variable var_LL33  : signed(15 downto 0)   := (others => '0');
         variable var_BK0   : unsigned(31 downto 0) := (others => '0');
         variable var_BK1   : unsigned(31 downto 0) := (others => '0');
         variable var_BK2   : unsigned(31 downto 0) := (others => '0');
         variable var_LC11  : signed(15 downto 0)   := (others => '0');
         variable var_LC12  : signed(15 downto 0)   := (others => '0');
         variable var_LC13  : signed(15 downto 0)   := (others => '0');
         variable var_LC21  : signed(15 downto 0)   := (others => '0');
         variable var_LC22  : signed(15 downto 0)   := (others => '0');
         variable var_LC23  : signed(15 downto 0)   := (others => '0');
         variable var_LC31  : signed(15 downto 0)   := (others => '0');
         variable var_LC32  : signed(15 downto 0)   := (others => '0');
         variable var_LC33  : signed(15 downto 0)   := (others => '0');
         variable var_FC0   : unsigned(31 downto 0) := (others => '0');
         variable var_FC1   : unsigned(31 downto 0) := (others => '0');
         variable var_FC2   : unsigned(31 downto 0) := (others => '0');
         variable var_OFX   : unsigned(31 downto 0) := (others => '0');
         variable var_OFY   : unsigned(31 downto 0) := (others => '0');
         variable var_H     : signed(15 downto 0)   := (others => '0');
         variable var_DQA   : signed(15 downto 0)   := (others => '0');
         variable var_DQB   : unsigned(31 downto 0) := (others => '0');
         variable var_ZSF3  : signed(15 downto 0)   := (others => '0');
         variable var_ZSF4  : signed(15 downto 0)   := (others => '0');
         variable var_FLAG  : unsigned(31 downto 0) := (others => '0');
         
      begin
   
         file_open(f_status, outfile, "R:\\debug_gte_sim.txt", write_mode);
         file_close(outfile);
         
         file_open(f_status, outfile, "R:\\debug_gte_sim.txt", append_mode);
         
         while (true) loop
            
            wait until rising_edge(clk2x);
                        
            outputCountNew := outputCount;
                        
            regcheck := 0;
            
            if (gte_writeEna_1 = '1') then
               regcheck := 2;
            end if;
            
            if (gte_busy = '0' and busy_1 = '1') then
               regcheck := 3;
            end if;

            if (regcheck > 0) then
               if (var_V0X  /= REG_V0X or var_V0Y  /= REG_V0Y  ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("00 ")); write(line_out, to_hstring(std_logic_vector(REG_V0Y & REG_V0X)));        outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_V0X  := REG_V0X ; var_V0Y  := REG_V0Y ; end if;
               if (var_V0Z  /= REG_V0Z                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("01 ")); write(line_out, to_hstring(std_logic_vector(resize(REG_V0Z, 32))));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_V0Z  := REG_V0Z ; end if;
               if (var_V1X  /= REG_V1X or var_V1Y  /= REG_V1Y  ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("02 ")); write(line_out, to_hstring(std_logic_vector(REG_V1Y & REG_V1X)));        outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_V1X  := REG_V1X ; var_V1Y  := REG_V1Y ; end if;
               if (var_V1Z  /= REG_V1Z                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("03 ")); write(line_out, to_hstring(std_logic_vector(resize(REG_V1Z, 32))));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_V1Z  := REG_V1Z ; end if;
               if (var_V2X  /= REG_V2X or var_V2Y  /= REG_V2Y  ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("04 ")); write(line_out, to_hstring(std_logic_vector(REG_V2Y & REG_V2X)));        outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_V2X  := REG_V2X ; var_V2Y  := REG_V2Y ; end if;
               if (var_V2Z  /= REG_V2Z                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("05 ")); write(line_out, to_hstring(std_logic_vector(resize(REG_V2Z, 32))));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_V2Z  := REG_V2Z ; end if;
               if (var_RGBC /= REG_RGBC                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("06 ")); write(line_out, to_hstring(std_logic_vector(REG_RGBC)));                 outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_RGBC := REG_RGBC; end if;
               if (var_OTZ  /= REG_OTZ                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("07 ")); write(line_out, to_hstring(std_logic_vector(x"0000" & REG_OTZ)));        outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_OTZ  := REG_OTZ ; end if;
               if (var_IR0  /= REG_IR0                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("08 ")); write(line_out, to_hstring(std_logic_vector(resize(REG_IR0, 32))));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_IR0  := REG_IR0 ; end if;
               if (var_IR1  /= REG_IR1                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("09 ")); write(line_out, to_hstring(std_logic_vector(resize(REG_IR1, 32))));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_IR1  := REG_IR1 ; end if;
               if (var_IR2  /= REG_IR2                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("10 ")); write(line_out, to_hstring(std_logic_vector(resize(REG_IR2, 32))));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_IR2  := REG_IR2 ; end if;
               if (var_IR3  /= REG_IR3                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("11 ")); write(line_out, to_hstring(std_logic_vector(resize(REG_IR3, 32))));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_IR3  := REG_IR3 ; end if;
               if (var_SX0  /= REG_SX0 or var_SY0  /= REG_SY0  ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("12 ")); write(line_out, to_hstring(std_logic_vector(REG_SY0 & REG_SX0)));        outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_SX0  := REG_SX0 ; var_SY0  := REG_SY0 ; end if;
               if (var_SX1  /= REG_SX1 or var_SY1  /= REG_SY1  ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("13 ")); write(line_out, to_hstring(std_logic_vector(REG_SY1 & REG_SX1)));        outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_SX1  := REG_SX1 ; var_SY1  := REG_SY1 ; end if;
               if (var_SX2  /= REG_SX2 or var_SY2  /= REG_SY2  ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("14 ")); write(line_out, to_hstring(std_logic_vector(REG_SY2 & REG_SX2)));        outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_SX2  := REG_SX2 ; var_SY2  := REG_SY2 ; end if;
               if (var_SZ0  /= REG_SZ0                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("16 ")); write(line_out, to_hstring(std_logic_vector(x"0000" & REG_SZ0)));        outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_SZ0  := REG_SZ0 ; end if;
               if (var_SZ1  /= REG_SZ1                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("17 ")); write(line_out, to_hstring(std_logic_vector(x"0000" & REG_SZ1)));        outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_SZ1  := REG_SZ1 ; end if;
               if (var_SZ2  /= REG_SZ2                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("18 ")); write(line_out, to_hstring(std_logic_vector(x"0000" & REG_SZ2)));        outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_SZ2  := REG_SZ2 ; end if;
               if (var_SZ3  /= REG_SZ3                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("19 ")); write(line_out, to_hstring(std_logic_vector(x"0000" & REG_SZ3)));        outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_SZ3  := REG_SZ3 ; end if;
               if (var_RGB0 /= REG_RGB0                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("20 ")); write(line_out, to_hstring(std_logic_vector(REG_RGB0)));                 outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_RGB0 := REG_RGB0; end if;
               if (var_RGB1 /= REG_RGB1                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("21 ")); write(line_out, to_hstring(std_logic_vector(REG_RGB1)));                 outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_RGB1 := REG_RGB1; end if;
               if (var_RGB2 /= REG_RGB2                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("22 ")); write(line_out, to_hstring(std_logic_vector(REG_RGB2)));                 outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_RGB2 := REG_RGB2; end if;
               if (var_RES1 /= REG_RES1                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("23 ")); write(line_out, to_hstring(std_logic_vector(REG_RES1)));                 outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_RES1 := REG_RES1; end if;
               if (var_MAC0 /= REG_MAC0                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("24 ")); write(line_out, to_hstring(std_logic_vector(REG_MAC0)));                 outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_MAC0 := REG_MAC0; end if;
               if (var_MAC1 /= REG_MAC1                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("25 ")); write(line_out, to_hstring(std_logic_vector(REG_MAC1)));                 outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_MAC1 := REG_MAC1; end if;
               if (var_MAC2 /= REG_MAC2                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("26 ")); write(line_out, to_hstring(std_logic_vector(REG_MAC2)));                 outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_MAC2 := REG_MAC2; end if;
               if (var_MAC3 /= REG_MAC3                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("27 ")); write(line_out, to_hstring(std_logic_vector(REG_MAC3)));                 outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_MAC3 := REG_MAC3; end if;
               if (var_IRGB /= REG_IRGB                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("28 ")); write(line_out, to_hstring(std_logic_vector(x"0000" & '0' & REG_IRGB))); outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_IRGB := REG_IRGB; end if;
               if (var_ORGB /= REG_ORGB                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("29 ")); write(line_out, to_hstring(std_logic_vector(x"0000" & '0' & REG_ORGB))); outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_ORGB := REG_ORGB; end if;
               if (var_LZCS /= REG_LZCS                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("30 ")); write(line_out, to_hstring(std_logic_vector(REG_LZCS)));                 outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_LZCS := REG_LZCS; end if;
               if (var_LZCR /= REG_LZCR                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("31 ")); write(line_out, to_hstring(std_logic_vector(REG_LZCR)));                 outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_LZCR := REG_LZCR; end if;
               if (var_RT11 /= REG_RT11 or var_RT12 /= REG_RT12) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("32 ")); write(line_out, to_hstring(std_logic_vector(REG_RT12 & REG_RT11)));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_RT11 := REG_RT11; var_RT12 := REG_RT12; end if;
               if (var_RT13 /= REG_RT13 or var_RT21 /= REG_RT21) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("33 ")); write(line_out, to_hstring(std_logic_vector(REG_RT21 & REG_RT13)));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_RT13 := REG_RT13; var_RT21 := REG_RT21; end if;
               if (var_RT22 /= REG_RT22 or var_RT23 /= REG_RT23) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("34 ")); write(line_out, to_hstring(std_logic_vector(REG_RT23 & REG_RT22)));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_RT22 := REG_RT22; var_RT23 := REG_RT23; end if;
               if (var_RT31 /= REG_RT31 or var_RT32 /= REG_RT32) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("35 ")); write(line_out, to_hstring(std_logic_vector(REG_RT32 & REG_RT31)));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_RT31 := REG_RT31; var_RT32 := REG_RT32; end if;
               if (var_RT33 /= REG_RT33                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("36 ")); write(line_out, to_hstring(std_logic_vector(resize(REG_RT33, 32))));     outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_RT33 := REG_RT33; end if;
               if (var_TR0  /= REG_TR0                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("37 ")); write(line_out, to_hstring(std_logic_vector(REG_TR0)));                  outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_TR0  := REG_TR0 ; end if;
               if (var_TR1  /= REG_TR1                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("38 ")); write(line_out, to_hstring(std_logic_vector(REG_TR1)));                  outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_TR1  := REG_TR1 ; end if;
               if (var_TR2  /= REG_TR2                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("39 ")); write(line_out, to_hstring(std_logic_vector(REG_TR2)));                  outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_TR2  := REG_TR2 ; end if;
               if (var_LL11 /= REG_LL11 or var_LL12 /= REG_LL12) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("40 ")); write(line_out, to_hstring(std_logic_vector(REG_LL12 & REG_LL11)));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_LL11 := REG_LL11; var_LL12 := REG_LL12; end if;
               if (var_LL13 /= REG_LL13 or var_LL21 /= REG_LL21) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("41 ")); write(line_out, to_hstring(std_logic_vector(REG_LL21 & REG_LL13)));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_LL13 := REG_LL13; var_LL21 := REG_LL21; end if;
               if (var_LL22 /= REG_LL22 or var_LL23 /= REG_LL23) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("42 ")); write(line_out, to_hstring(std_logic_vector(REG_LL23 & REG_LL22)));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_LL22 := REG_LL22; var_LL23 := REG_LL23; end if;
               if (var_LL31 /= REG_LL31 or var_LL32 /= REG_LL32) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("43 ")); write(line_out, to_hstring(std_logic_vector(REG_LL32 & REG_LL31)));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_LL31 := REG_LL31; var_LL32 := REG_LL32; end if;
               if (var_LL33 /= REG_LL33                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("44 ")); write(line_out, to_hstring(std_logic_vector(resize(REG_LL33, 32))));     outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_LL33 := REG_LL33; end if;
               if (var_BK0  /= REG_BK0                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("45 ")); write(line_out, to_hstring(std_logic_vector(REG_BK0)));                  outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_BK0  := REG_BK0 ; end if;
               if (var_BK1  /= REG_BK1                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("46 ")); write(line_out, to_hstring(std_logic_vector(REG_BK1)));                  outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_BK1  := REG_BK1 ; end if;
               if (var_BK2  /= REG_BK2                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("47 ")); write(line_out, to_hstring(std_logic_vector(REG_BK2)));                  outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_BK2  := REG_BK2 ; end if;
               if (var_LC11 /= REG_LC11 or var_LC12 /= REG_LC12) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("48 ")); write(line_out, to_hstring(std_logic_vector(REG_LC12 & REG_LC11)));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_LC11 := REG_LC11; var_LC12 := REG_LC12; end if;
               if (var_LC13 /= REG_LC13 or var_LC21 /= REG_LC21) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("49 ")); write(line_out, to_hstring(std_logic_vector(REG_LC21 & REG_LC13)));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_LC13 := REG_LC13; var_LC21 := REG_LC21; end if;
               if (var_LC22 /= REG_LC22 or var_LC23 /= REG_LC23) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("50 ")); write(line_out, to_hstring(std_logic_vector(REG_LC23 & REG_LC22)));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_LC22 := REG_LC22; var_LC23 := REG_LC23; end if;
               if (var_LC31 /= REG_LC31 or var_LC32 /= REG_LC32) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("51 ")); write(line_out, to_hstring(std_logic_vector(REG_LC32 & REG_LC31)));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_LC31 := REG_LC31; var_LC32 := REG_LC32; end if;
               if (var_LC33 /= REG_LC33                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("52 ")); write(line_out, to_hstring(std_logic_vector(resize(REG_LC33, 32))));     outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_LC33 := REG_LC33; end if;
               if (var_FC0  /= REG_FC0                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("53 ")); write(line_out, to_hstring(std_logic_vector(REG_FC0)));                  outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_FC0  := REG_FC0 ; end if;
               if (var_FC1  /= REG_FC1                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("54 ")); write(line_out, to_hstring(std_logic_vector(REG_FC1)));                  outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_FC1  := REG_FC1 ; end if;
               if (var_FC2  /= REG_FC2                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("55 ")); write(line_out, to_hstring(std_logic_vector(REG_FC2)));                  outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_FC2  := REG_FC2 ; end if;
               if (var_OFX  /= REG_OFX                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("56 ")); write(line_out, to_hstring(std_logic_vector(REG_OFX)));                  outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_OFX  := REG_OFX ; end if;
               if (var_OFY  /= REG_OFY                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("57 ")); write(line_out, to_hstring(std_logic_vector(REG_OFY)));                  outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_OFY  := REG_OFY ; end if;
               if (var_H    /= REG_H                           ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("58 ")); write(line_out, to_hstring(std_logic_vector(resize(REG_H, 32))));        outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_H    := REG_H   ; end if;
               if (var_DQA  /= REG_DQA                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("59 ")); write(line_out, to_hstring(std_logic_vector(resize(REG_DQA, 32))));      outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_DQA  := REG_DQA ; end if;
               if (var_DQB  /= REG_DQB                         ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("60 ")); write(line_out, to_hstring(std_logic_vector(REG_DQB)));                  outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_DQB  := REG_DQB ; end if;
               if (var_ZSF3 /= REG_ZSF3                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("61 ")); write(line_out, to_hstring(std_logic_vector(resize(REG_ZSF3, 32))));     outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_ZSF3 := REG_ZSF3; end if;
               if (var_ZSF4 /= REG_ZSF4                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("62 ")); write(line_out, to_hstring(std_logic_vector(resize(REG_ZSF4, 32))));     outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_ZSF4 := REG_ZSF4; end if;
               if (var_FLAG /= REG_FLAG                        ) then if (regcheck = 2) then write(line_out, string'("WRITE REG: ")); end if; if (regcheck = 3) then write(line_out, string'("COMMAND REG: ")); end if; write(line_out, string'("63 ")); write(line_out, to_hstring(std_logic_vector(REG_FLAG)));                 outputCountNew := outputCountNew + 1; writeline(outfile, line_out); var_FLAG := REG_FLAG; end if;
            end if;
            
            if (gte_cmdEna_1 = '1') then
               write(line_out, string'("COMMAND: 00 ")); 
               write(line_out, to_hstring(gte_cmdData));
               writeline(outfile, line_out);
               outputCountNew := outputCountNew + 1;
            end if;
            
            if (gte_writeEna = '1' and clk2xIndex = '1') then
               write(line_out, string'("REG IN: "));
               if (gte_writeAddr < 10) then
                  write(line_out, string'("0"));
               end if;
               write(line_out, to_integer(gte_writeAddr));
               write(line_out, string'(" "));
               write(line_out, to_hstring(gte_writeData));
               writeline(outfile, line_out);
               outputCountNew := outputCountNew + 1;
            end if;
            
            if (gte_readEna_1 = '1') then
               write(line_out, string'("REG READ: "));
               if (gte_readAddr < 10) then
                  write(line_out, string'("0"));
               end if;
               write(line_out, to_integer(gte_readAddr));
               write(line_out, string'(" "));
               write(line_out, to_hstring(gte_readData));
               writeline(outfile, line_out);
               outputCountNew := outputCountNew + 1;
            end if;
            
            busy_1 := gte_busy;
            gte_writeEna_1 := gte_writeEna and clk2xIndex;
            gte_cmdEna_1   := gte_cmdEna and clk2xIndex;
            gte_readEna_1  := gte_readEna and clk2xIndex; 
            
            outputCount <= outputCountNew;
            
         end loop;
         
      end process;
   
   end generate goutput;
   
   -- synthesis translate_on

end architecture;





