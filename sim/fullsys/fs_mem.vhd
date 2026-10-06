-- Full-system simulation RAM shims (sim only, docs/fullsys_sim.md W4).
-- Same entity names and ports as the PSX_MiSTer RAM primitives. Each
-- architecture instantiates an unbound component, which GHDL synthesis
-- writes out as a parameterised Verilog instance; sim/fullsys/fs_mem.v
-- implements those modules for Verilator. GHDL cannot infer the
-- two-process dual-port RAMs of the originals ("multiple assignments").
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity dpram is
   generic (addr_width : integer := 8; data_width : integer := 8);
   port (
      clock_a   : in  std_logic;
      clken_a   : in  std_logic := '1';
      address_a : in  std_logic_vector(addr_width-1 downto 0);
      data_a    : in  std_logic_vector(data_width-1 downto 0);
      wren_a    : in  std_logic := '0';
      q_a       : out std_logic_vector(data_width-1 downto 0);
      clock_b   : in  std_logic;
      clken_b   : in  std_logic := '1';
      address_b : in  std_logic_vector(addr_width-1 downto 0);
      data_b    : in  std_logic_vector(data_width-1 downto 0) := (others => '0');
      wren_b    : in  std_logic := '0';
      q_b       : out std_logic_vector(data_width-1 downto 0));
end;
architecture shim of dpram is
   component fs_dpram is
      generic (AW : integer; DW : integer);
      port (clock_a, clken_a, wren_a : in std_logic; address_a : in std_logic_vector(AW-1 downto 0);
            data_a : in std_logic_vector(DW-1 downto 0); q_a : out std_logic_vector(DW-1 downto 0);
            clock_b, clken_b, wren_b : in std_logic; address_b : in std_logic_vector(AW-1 downto 0);
            data_b : in std_logic_vector(DW-1 downto 0); q_b : out std_logic_vector(DW-1 downto 0));
   end component;
begin
   u : fs_dpram generic map (AW => addr_width, DW => data_width)
      port map (clock_a, clken_a, wren_a, address_a, data_a, q_a, clock_b, clken_b, wren_b, address_b, data_b, q_b);
end;

library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity dpram_dif is
   generic (addr_width_a : integer := 8; data_width_a : integer := 8; addr_width_b : integer := 8; data_width_b : integer := 8);
   port (
      clock_a   : in  std_logic;
      clken_a   : in  std_logic := '1';
      address_a : in  std_logic_vector(addr_width_a-1 downto 0);
      data_a    : in  std_logic_vector(data_width_a-1 downto 0) := (others => '0');
      wren_a    : in  std_logic := '0';
      q_a       : out std_logic_vector(data_width_a-1 downto 0);
      clock_b   : in  std_logic;
      clken_b   : in  std_logic := '1';
      address_b : in  std_logic_vector(addr_width_b-1 downto 0) := (others => '0');
      data_b    : in  std_logic_vector(data_width_b-1 downto 0) := (others => '0');
      wren_b    : in  std_logic := '0';
      q_b       : out std_logic_vector(data_width_b-1 downto 0));
end;
architecture shim of dpram_dif is
   component fs_dpram_dif is
      generic (AWA : integer; DWA : integer; AWB : integer; DWB : integer);
      port (clock_a, clken_a, wren_a : in std_logic; address_a : in std_logic_vector(AWA-1 downto 0);
            data_a : in std_logic_vector(DWA-1 downto 0); q_a : out std_logic_vector(DWA-1 downto 0);
            clock_b, clken_b, wren_b : in std_logic; address_b : in std_logic_vector(AWB-1 downto 0);
            data_b : in std_logic_vector(DWB-1 downto 0); q_b : out std_logic_vector(DWB-1 downto 0));
   end component;
begin
   u : fs_dpram_dif generic map (AWA => addr_width_a, DWA => data_width_a, AWB => addr_width_b, DWB => data_width_b)
      port map (clock_a, clken_a, wren_a, address_a, data_a, q_a, clock_b, clken_b, wren_b, address_b, data_b, q_b);
end;

library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity RamMLAB is
   generic (width : natural; width_byteena : natural := 1; widthad : natural);
   port (
      inclock   : in  std_logic;
      wren      : in  std_logic;
      data      : in  std_logic_vector(width-1 downto 0);
      wraddress : in  std_logic_vector(widthad-1 downto 0);
      rdaddress : in  std_logic_vector(widthad-1 downto 0);
      q         : out std_logic_vector(width-1 downto 0));
end;
architecture shim of RamMLAB is
   component fs_rammlab is
      generic (DW : integer; AW : integer);
      port (clk, we : in std_logic; d : in std_logic_vector(DW-1 downto 0);
            wa, ra : in std_logic_vector(AW-1 downto 0); q : out std_logic_vector(DW-1 downto 0));
   end component;
begin
   u : fs_rammlab generic map (DW => width, AW => widthad) port map (inclock, wren, data, wraddress, rdaddress, q);
end;

library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity SyncRamDualByteEnable is
   generic (is_simu : std_logic; is_cyclone5 : std_logic := '0'; BYTE_WIDTH : natural := 8; ADDR_WIDTH : natural := 6; BYTES : natural := 4);
   port (
      clk       : in  std_logic;
      addr_a    : in  natural range 0 to 2**ADDR_WIDTH - 1;
      datain_a0 : in  std_logic_vector((BYTE_WIDTH-1) downto 0);
      datain_a1 : in  std_logic_vector((BYTE_WIDTH-1) downto 0);
      datain_a2 : in  std_logic_vector((BYTE_WIDTH-1) downto 0);
      datain_a3 : in  std_logic_vector((BYTE_WIDTH-1) downto 0);
      dataout_a : out std_logic_vector((BYTES*BYTE_WIDTH-1) downto 0);
      we_a      : in  std_logic := '1';
      be_a      : in  std_logic_vector(BYTES - 1 downto 0);
      addr_b    : in  natural range 0 to 2**ADDR_WIDTH - 1;
      datain_b0 : in  std_logic_vector((BYTE_WIDTH-1) downto 0);
      datain_b1 : in  std_logic_vector((BYTE_WIDTH-1) downto 0);
      datain_b2 : in  std_logic_vector((BYTE_WIDTH-1) downto 0);
      datain_b3 : in  std_logic_vector((BYTE_WIDTH-1) downto 0);
      dataout_b : out std_logic_vector((BYTES*BYTE_WIDTH-1) downto 0);
      we_b      : in  std_logic := '1';
      be_b      : in  std_logic_vector(BYTES - 1 downto 0));
end;
architecture shim of SyncRamDualByteEnable is
   component fs_ramdualbe is
      generic (BW : integer; AW : integer; NB : integer);
      port (clk : in std_logic;
            addr_a : in std_logic_vector(AW-1 downto 0); din_a : in std_logic_vector(4*BW-1 downto 0);
            dout_a : out std_logic_vector(NB*BW-1 downto 0); we_a : in std_logic; be_a : in std_logic_vector(NB-1 downto 0);
            addr_b : in std_logic_vector(AW-1 downto 0); din_b : in std_logic_vector(4*BW-1 downto 0);
            dout_b : out std_logic_vector(NB*BW-1 downto 0); we_b : in std_logic; be_b : in std_logic_vector(NB-1 downto 0));
   end component;
   signal aa, ab : std_logic_vector(ADDR_WIDTH-1 downto 0);
   signal da, db : std_logic_vector(4*BYTE_WIDTH-1 downto 0);
begin
   aa <= std_logic_vector(to_unsigned(addr_a, ADDR_WIDTH));
   ab <= std_logic_vector(to_unsigned(addr_b, ADDR_WIDTH));
   da <= datain_a3 & datain_a2 & datain_a1 & datain_a0;
   db <= datain_b3 & datain_b2 & datain_b1 & datain_b0;
   u : fs_ramdualbe generic map (BW => BYTE_WIDTH, AW => ADDR_WIDTH, NB => BYTES)
      port map (clk, aa, da, dataout_a, we_a, be_a, ab, db, dataout_b, we_b, be_b);
end;

library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity SyncRam is
   generic (DATA_WIDTH : natural := 8; ADDR_WIDTH : natural := 6);
   port (
      clk     : in  std_logic;
      addr    : in  natural range 0 to 2**ADDR_WIDTH - 1;
      datain  : in  std_logic_vector((DATA_WIDTH-1) downto 0);
      dataout : out std_logic_vector((DATA_WIDTH-1) downto 0);
      we      : in  std_logic := '1');
end;
architecture shim of SyncRam is
   component fs_syncram is
      generic (DW : integer; AW : integer);
      port (clk : in std_logic; addr : in std_logic_vector(AW-1 downto 0); din : in std_logic_vector(DW-1 downto 0);
            dout : out std_logic_vector(DW-1 downto 0); we : in std_logic);
   end component;
   signal a : std_logic_vector(ADDR_WIDTH-1 downto 0);
begin
   a <= std_logic_vector(to_unsigned(addr, ADDR_WIDTH));
   u : fs_syncram generic map (DW => DATA_WIDTH, AW => ADDR_WIDTH) port map (clk, a, datain, dataout, we);
end;

library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity SyncRamDual is
   generic (DATA_WIDTH : natural := 8; ADDR_WIDTH : natural := 6);
   port (
      clk       : in  std_logic;
      addr_a    : in  natural range 0 to 2**ADDR_WIDTH - 1;
      datain_a  : in  std_logic_vector((DATA_WIDTH-1) downto 0);
      dataout_a : out std_logic_vector((DATA_WIDTH-1) downto 0);
      we_a      : in  std_logic := '1';
      re_a      : in  std_logic := '1';
      addr_b    : in  natural range 0 to 2**ADDR_WIDTH - 1;
      datain_b  : in  std_logic_vector((DATA_WIDTH-1) downto 0);
      dataout_b : out std_logic_vector((DATA_WIDTH-1) downto 0);
      we_b      : in  std_logic := '1';
      re_b      : in  std_logic := '1');
end;
architecture shim of SyncRamDual is
   component fs_syncramdual is
      generic (DW : integer; AW : integer; N : integer);
      port (clk : in std_logic;
            addr_a : in std_logic_vector(AW-1 downto 0); din_a : in std_logic_vector(DW-1 downto 0);
            dout_a : out std_logic_vector(DW-1 downto 0); we_a, re_a : in std_logic;
            addr_b : in std_logic_vector(AW-1 downto 0); din_b : in std_logic_vector(DW-1 downto 0);
            dout_b : out std_logic_vector(DW-1 downto 0); we_b, re_b : in std_logic);
   end component;
   signal aa, ab : std_logic_vector(ADDR_WIDTH-1 downto 0);
begin
   aa <= std_logic_vector(to_unsigned(addr_a, ADDR_WIDTH));
   ab <= std_logic_vector(to_unsigned(addr_b, ADDR_WIDTH));
   u : fs_syncramdual generic map (DW => DATA_WIDTH, AW => ADDR_WIDTH, N => 2**ADDR_WIDTH)
      port map (clk, aa, datain_a, dataout_a, we_a, re_a, ab, datain_b, dataout_b, we_b, re_b);
end;

library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all; use ieee.math_real.all;
entity SyncRamDualNotPow2 is
   generic (DATA_WIDTH : natural; DATA_COUNT : natural);
   port (
      clk       : in  std_logic;
      addr_a    : in  natural range 0 to DATA_COUNT - 1;
      datain_a  : in  std_logic_vector((DATA_WIDTH-1) downto 0);
      dataout_a : out std_logic_vector((DATA_WIDTH-1) downto 0);
      we_a      : in  std_logic := '1';
      re_a      : in  std_logic := '1';
      addr_b    : in  natural range 0 to DATA_COUNT - 1;
      datain_b  : in  std_logic_vector((DATA_WIDTH-1) downto 0);
      dataout_b : out std_logic_vector((DATA_WIDTH-1) downto 0);
      we_b      : in  std_logic := '1';
      re_b      : in  std_logic := '1');
end;
architecture shim of SyncRamDualNotPow2 is
   constant AW : integer := integer(ceil(log2(real(DATA_COUNT))));
   component fs_syncramdual is
      generic (DW : integer; AW : integer; N : integer);
      port (clk : in std_logic;
            addr_a : in std_logic_vector(AW-1 downto 0); din_a : in std_logic_vector(DW-1 downto 0);
            dout_a : out std_logic_vector(DW-1 downto 0); we_a, re_a : in std_logic;
            addr_b : in std_logic_vector(AW-1 downto 0); din_b : in std_logic_vector(DW-1 downto 0);
            dout_b : out std_logic_vector(DW-1 downto 0); we_b, re_b : in std_logic);
   end component;
   signal aa, ab : std_logic_vector(AW-1 downto 0);
begin
   aa <= std_logic_vector(to_unsigned(addr_a, AW));
   ab <= std_logic_vector(to_unsigned(addr_b, AW));
   u : fs_syncramdual generic map (DW => DATA_WIDTH, AW => AW, N => DATA_COUNT)
      port map (clk, aa, datain_a, dataout_a, we_a, re_a, ab, datain_b, dataout_b, we_b, re_b);
end;
