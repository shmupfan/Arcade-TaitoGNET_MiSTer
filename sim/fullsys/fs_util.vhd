-- Full-system simulation helpers (sim only, docs/fullsys_sim.md).
library ieee;
use ieee.std_logic_1164.all;
package fs_util is
   -- integer abs: GHDL synthesis has no "abs" on integer (W3)
   function fs_iabs(x : integer) return integer;
end package;
package body fs_util is
   function fs_iabs(x : integer) return integer is
   begin
      if x < 0 then return -x; else return x; end if;
   end function;
end package body;
