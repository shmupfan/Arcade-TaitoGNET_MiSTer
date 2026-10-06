-- Simulation-only stand-in for rtl/gnet/gnet_fc.sv in NVC: same generics and
-- ports, the real SystemVerilog runs in Verilator behind VHPIDIRECT
-- (gnet_fc_step.cpp). Generics must match the Verilator build
-- (sim/zn2/cosim/build_gnet_fc.sh); they are checked at the first edge.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity gnet_fc is
   generic
   (
      CLK_HZ       : integer := 33868800;
      FLASH_PRESET : integer := 1;
      WD_TIMEOUT_S : integer := 8
   );
   port
   (
      clk          : in  std_logic;
      rst          : in  std_logic;
      jp1          : in  std_logic;
      card_present : in  std_logic;
      cpu_req      : in  std_logic;
      cpu_we       : in  std_logic;
      cpu_addr     : in  std_logic_vector(23 downto 0);
      cpu_be       : in  std_logic_vector(3 downto 0);
      cpu_wdata    : in  std_logic_vector(31 downto 0);
      cpu_ack      : out std_logic := '0';
      cpu_rdata    : out std_logic_vector(31 downto 0) := (others => '0');
      cpu_hit      : out std_logic := '0';
      zoom_reset   : out std_logic := '1';
      wd_reset     : out std_logic := '0';
      fmem_req     : out std_logic := '0';
      fmem_we      : out std_logic := '0';
      fmem_chip    : out std_logic_vector(2 downto 0) := (others => '0');
      fmem_addr    : out std_logic_vector(20 downto 0) := (others => '0');
      fmem_wdata   : out std_logic_vector(15 downto 0) := (others => '0');
      fmem_ack     : in  std_logic;
      fmem_rdata   : in  std_logic_vector(15 downto 0);
      flash_busy   : out std_logic_vector(4 downto 0) := (others => '0');
      cmem_req     : out std_logic := '0';
      cmem_we      : out std_logic := '0';
      cmem_addr    : out std_logic_vector(24 downto 0) := (others => '0');
      cmem_wdata   : out std_logic_vector(15 downto 0) := (others => '0');
      cmem_ack     : in  std_logic;
      cmem_rdata   : in  std_logic_vector(15 downto 0);
      meta_we      : in  std_logic;
      meta_addr    : in  std_logic_vector(9 downto 0);
      meta_wdata   : in  std_logic_vector(7 downto 0);
      key_valid    : in  std_logic;
      dirty_set    : out std_logic := '0';
      dirty_hunk   : out std_logic_vector(13 downto 0) := (others => '0');
      dirty_raddr  : in  std_logic_vector(13 downto 0);
      dirty_rdata  : out std_logic := '0';
      dirty_clear  : in  std_logic;
      card_reset   : out std_logic := '1';
      win_mismatch : out std_logic := '0';
      -- debug taps (docs/hw_debug_overlay.md): not carried by the VHPIDIRECT
      -- step interface, held at their idle values in the cosimulation
      dbg_wd_kick  : out std_logic := '0';
      dbg_ctrl     : out std_logic_vector(7 downto 0) := x"10";
      dbg_sec_cmd  : out std_logic := '0'
   );
end entity;

architecture cosim of gnet_fc is

   type t_ivec is array (0 to 17) of integer;
   type t_ovec is array (0 to 19) of integer;

   procedure gnet_fc_step(i : t_ivec; o : out t_ovec);
   attribute foreign of gnet_fc_step : procedure is "VHPIDIRECT gnet_fc_step";
   procedure gnet_fc_step(i : t_ivec; o : out t_ovec) is
   begin
      report "gnet_fc_step: VHPIDIRECT library not loaded (nvc -r --load=libgnetfc.so)" severity failure;
   end procedure;

   function gnet_fc_clk_hz return integer;
   attribute foreign of gnet_fc_clk_hz : function is "VHPIDIRECT gnet_fc_clk_hz";
   function gnet_fc_clk_hz return integer is
   begin
      report "gnet_fc_clk_hz: VHPIDIRECT library not loaded" severity failure;
      return 0;
   end function;

   function b(x : std_logic) return integer is
   begin
      if x = '1' then return 1; else return 0; end if;
   end function;

   function u(x : std_logic_vector) return integer is
      variable v : std_logic_vector(x'length - 1 downto 0) := x;
   begin
      for k in v'range loop
         if v(k) /= '1' then v(k) := '0'; end if;   -- U/X from uninitialised drivers count as 0
      end loop;
      if x'length = 32 then
         return to_integer(signed(v));
      end if;
      return to_integer(unsigned(v));
   end function;

begin

   assert FLASH_PRESET = 1 and WD_TIMEOUT_S = 8
      report "gnet_fc cosim: the Verilator library is built for FLASH_PRESET 1, WD_TIMEOUT_S 8"
      severity failure;

   process (clk)
      variable i : t_ivec;
      variable o : t_ovec;
      variable checked : boolean := false;
   begin
      if rising_edge(clk) then
         if not checked then
            -- CLK_HZ is a build option of the library (GNET_FC_CLK_HZ in build_gnet_fc.sh)
            assert CLK_HZ = gnet_fc_clk_hz
               report "gnet_fc cosim: generic CLK_HZ " & integer'image(CLK_HZ) & ", library built for " &
                      integer'image(gnet_fc_clk_hz) severity failure;
            checked := true;
         end if;
         i := (b(rst), b(jp1), b(card_present), b(cpu_req), b(cpu_we), u(cpu_addr), u(cpu_be), u(cpu_wdata),
               b(fmem_ack), u(fmem_rdata), b(cmem_ack), u(cmem_rdata), b(meta_we), u(meta_addr), u(meta_wdata),
               b(key_valid), u(dirty_raddr), b(dirty_clear));
         gnet_fc_step(i, o);
         cpu_ack      <= '1' when o(0) /= 0 else '0';
         cpu_rdata    <= std_logic_vector(to_signed(o(1), 32));
         cpu_hit      <= '1' when o(2) /= 0 else '0';
         zoom_reset   <= '1' when o(3) /= 0 else '0';
         wd_reset     <= '1' when o(4) /= 0 else '0';
         fmem_req     <= '1' when o(5) /= 0 else '0';
         fmem_we      <= '1' when o(6) /= 0 else '0';
         fmem_chip    <= std_logic_vector(to_unsigned(o(7), 3));
         fmem_addr    <= std_logic_vector(to_unsigned(o(8), 21));
         fmem_wdata   <= std_logic_vector(to_unsigned(o(9), 16));
         flash_busy   <= std_logic_vector(to_unsigned(o(10), 5));
         cmem_req     <= '1' when o(11) /= 0 else '0';
         cmem_we      <= '1' when o(12) /= 0 else '0';
         cmem_addr    <= std_logic_vector(to_unsigned(o(13), 25));
         cmem_wdata   <= std_logic_vector(to_unsigned(o(14), 16));
         dirty_set    <= '1' when o(15) /= 0 else '0';
         dirty_hunk   <= std_logic_vector(to_unsigned(o(16), 14));
         dirty_rdata  <= '1' when o(17) /= 0 else '0';
         card_reset   <= '1' when o(18) /= 0 else '0';
         win_mismatch <= '1' when o(19) /= 0 else '0';
      end if;
   end process;

end architecture;
