-- Modified for the Taito G-NET core (Lee Foot, 2026). This file is part of
-- PSX_MiSTer (github.com/MiSTer-devel/PSX_MiSTer), base commit cd17b5a, and
-- keeps PSX_MiSTer's licence (LICENSE, docs/licensing.md).
-- Changes: record types tMAC0mul and tMAC123mul for gte.vhd's NARROW_MUL = 3
-- mode (the GTE at 100 MHz with the CPU on its own clock,
-- docs/r1_cpu_domain_design.md); unused at NARROW_MUL 0 (upstream).
-- G-NET commits: 92ae3a6 (2026-10-05) GTE_NARROW_MUL=3, GTE at 100 MHz.
-- Every change is marked "G-NET:" below. Full list: PROVENANCE.md.
--
library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;     

package pGTE is

   type tMAC0req is record
      mul1        : signed(16 downto 0);
      mul2        : signed(17 downto 0);
      add         : signed(31 downto 0);
      sub         : std_logic;
      swap        : std_logic;
      useIR       : std_logic;
      IRshift     : std_logic;
      checkOvf    : std_logic;
      useResult   : std_logic; 
      trigger     : std_logic; 
   end record;
   
   type tMAC123req is record
      mul1        : signed(31 downto 0);
      mul2        : signed(31 downto 0);
      add         : signed(44 downto 0);
      sub         : std_logic;
      swap        : std_logic;
      saveShifted : std_logic;
      useIR       : std_logic;
      IRshift     : std_logic;
      IRshiftFlag : std_logic;
      satIR       : std_logic;
      satIRFlag   : std_logic;
      useResult   : std_logic; 
      trigger     : std_logic; 
   end record;
  
   -- G-NET: NARROW_MUL = 3, operands of the request being written, presented
   -- in the cycle that writes it; the MAC units register the product (and the
   -- shifted wide operand) when ena = '1'. mul1/mul2 of the request record are
   -- then unused.
   type tMAC0mul is record
      mul1        : signed(16 downto 0);
      mul2        : signed(17 downto 0);
      ena         : std_logic;
   end record;

   type tMAC123mul is record
      mul1        : signed(17 downto 0);    -- 18 x 18 product
      mul2        : signed(17 downto 0);
      shifted     : signed(44 downto 0);    -- or a wide operand times 1, 10h, 1000h or 10000h, already shifted
      isShift     : std_logic;
      ena         : std_logic;
   end record;

   constant MAC0mul_none   : tMAC0mul   := ((others => '0'), (others => '0'), '0');
   constant MAC123mul_none : tMAC123mul := ((others => '0'), (others => '0'), (others => '0'), '0', '0');

end package;