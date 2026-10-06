-- R1 measurements 2 and 3: memory access latency of the PSX_MiSTer memory path
-- (rtl/memorymux.vhd + rtl/memctrl.vhd + rtl/sdram.sv through a mechanical
-- simulation copy, see sdram_sim_copy.py) with a simple SDRAM chip model, at a
-- clk_1x : SDRAM clock ratio of 3:1 (today) or 2:1. CLK_FAST_RATIO is the
-- request strobe selection of sdram.sv and psx_top.vhd (the RTL parameter,
-- independent of the clocks the bench makes with RATIO).
--
-- The CPU side is driven like cpu.vhd drives memorymux: a one-cycle
-- mem_in_request with address, size and mask. Latency is counted in clk_1x
-- (CPU) edges from the edge that samples the request to the edge that samples
-- mem_done = '1' (reads). Writes are posted by the CPU (cpu.vhd only stalls on
-- mem_fifofull), so for writes the testbench counts the edges until memorymux
-- reports isIdle again (occupancy).
--
-- The RAM glue copies psx_top.vhd:1380-1404 (cpuPaused mux between CPU and
-- DMA, address mapping with ram8mb = 0, ram_next_cpu) and PSX.sv:1303-1361
-- (read on ch1, write on ch2, ram_done = ch1_ready or ch2_ready, DMA FIFO).
--
-- DMA phase (DMA_N > 0, after the latency rows): the unmodified rtl/dma.vhd,
-- with its clk3xIndex from psx_top.vhd's generator (psx_top_index_copy.py),
-- runs an OTC (channel 6, RAM writes through the DMA output FIFO, the
-- clk3xIndex-gated write strobe at dma.vhd:979, and sdram.sv's dmafifo port),
-- the CPU reads the table back, then a GPU DMA (channel 2, RAM reads through
-- ch1 with ch1_dma) streams it out again. cpuPaused and canDMA follow
-- psx_top.vhd:768 and 813-816.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

package r1_mem_pkg is
   -- content of a never written 16-bit SDRAM word, by word address (bank, row, column)
   function fill(key : unsigned(23 downto 0)) return std_logic_vector;
end package;

package body r1_mem_pkg is
   function fill(key : unsigned(23 downto 0)) return std_logic_vector is
   begin
      return std_logic_vector(key(15 downto 0) xor (key(23 downto 16) & key(23 downto 16)) xor x"A5C3");
   end function;
end package body;

------------------------------------------------------------------------------
-- SDRAM chip: commands on the rising SDRAM_CLK edge (the falling controller
-- clock edge, SDRAM_CLK = ~clk), CAS latency 2, burst length 2 (the mode
-- sdram.sv loads, sdram.sv:94-99). Read data is driven for one SDRAM clock
-- from the second SDRAM edge after the READ, so the controller's rising edge
-- three cycles after the READ command samples the first word: the capture
-- point sdram.sv's data_ready_delay pipeline is built for (sdram.sv:262-285).
-- No analog timing: this checks cycles and protocol, not margins.
------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.r1_mem_pkg.all;

entity sdram_chip is
   port (
      clk   : in  std_logic;
      ncs   : in  std_logic;
      nras  : in  std_logic;
      ncas  : in  std_logic;
      nwe   : in  std_logic;
      ba    : in  std_logic_vector(1 downto 0);
      a     : in  std_logic_vector(12 downto 0);
      dq_w  : in  std_logic_vector(15 downto 0);
      dq_r  : out std_logic_vector(15 downto 0)
   );
end entity;

architecture sim of sdram_chip is
begin
   process (clk)
      type t_rows is array(0 to 3) of unsigned(12 downto 0);
      variable rows : t_rows := (others => (others => '0'));
      type t_q is array(0 to 4) of std_logic_vector(15 downto 0);
      variable q    : t_q := (others => (others => 'Z'));
      -- written words: direct-mapped on the low 16 key bits, full key stored
      type t_key is array(0 to 65535) of integer;
      type t_dat is array(0 to 65535) of std_logic_vector(15 downto 0);
      variable wkey : t_key := (others => -1);
      variable wdat : t_dat;
      variable key  : unsigned(23 downto 0);
      variable bank : integer;
      variable d    : std_logic_vector(15 downto 0);

      impure function rd(k : unsigned(23 downto 0)) return std_logic_vector is
         variable i : integer := to_integer(k(15 downto 0));
      begin
         if wkey(i) = to_integer(k) then return wdat(i); end if;
         return fill(k);
      end function;
   begin
      if falling_edge(clk) then
         for i in 0 to 3 loop q(i) := q(i + 1); end loop;
         q(4) := (others => 'Z');
         if ncs = '0' then
            bank := to_integer(unsigned(ba));
            if nras = '0' and ncas = '1' and nwe = '1' then          -- ACTIVE
               rows(bank) := unsigned(a);
            elsif nras = '1' and ncas = '0' then
               key := unsigned(ba) & rows(bank) & unsigned(a(8 downto 0));
               if nwe = '1' then                                       -- READ, burst 2
                  q(2) := rd(key);
                  key(0) := not key(0);
                  q(3) := rd(key);
               else                                                    -- WRITE, DQML = A11, DQMH = A12
                  d := rd(key);
                  if a(11) = '0' then d(7 downto 0)  := dq_w(7 downto 0);  end if;
                  if a(12) = '0' then d(15 downto 8) := dq_w(15 downto 8); end if;
                  wkey(to_integer(key(15 downto 0))) := to_integer(key);
                  wdat(to_integer(key(15 downto 0))) := d;
               end if;
            end if;
         end if;
         dq_r <= q(0);
      end if;
   end process;
end architecture;

------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;
use work.r1_mem_pkg.all;

entity tb_r1_mem is
   generic (
      RATIO   : integer := 3;          -- SDRAM clock edges per clk_1x period (3 today, 2 proposed)
      CLK_FAST_RATIO : integer := 3;   -- RTL strobe selection (sdram.sv parameter, psx_top.vhd generic)
      EARLY_READY : integer := 0;      -- sdram.sv EARLY_READY (2:1 only)
      ROWS    : integer := 1;          -- 0: skip the latency rows (DMA phase only)
      DMA_N   : integer := 2048;       -- words for the DMA phase, 0 = no DMA phase
      T_FAST  : time    := 9842 ps;    -- SDRAM clock period (101.6064 MHz)
      NREP    : integer := 400;        -- samples per row
      OUTFILE : string  := "mem_lat.txt";
      DEBUG   : integer := 0;         -- >0: report the first DEBUG RAM events after DBG_FROM
      DBG_FROM : time   := 0 ns
   );
end entity;

architecture sim of tb_r1_mem is

   component sdram is
      generic (CLK_FAST_RATIO : integer; EARLY_READY : integer := 0);
      port (
         init, clk, clk_base, SDRAM_EN : in std_logic;
         SDRAM_DQ    : out std_logic_vector(15 downto 0);
         SDRAM_DQ_IN : in  std_logic_vector(15 downto 0);
         idx_o       : out std_logic;
         SDRAM_A     : out std_logic_vector(12 downto 0);
         SDRAM_DQML, SDRAM_DQMH : out std_logic;
         SDRAM_BA    : out std_logic_vector(1 downto 0);
         SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_CKE, SDRAM_CLK : out std_logic;
         refreshForce : in std_logic;
         ram_idle     : out std_logic;
         ch1_addr : in std_logic_vector(26 downto 0);
         ch1_dout : out std_logic_vector(127 downto 0);
         ch1_dout32 : out std_logic_vector(31 downto 0);
         ch1_din  : in std_logic_vector(15 downto 0);
         ch1_req, ch1_rnw, ch1_dma : in std_logic;
         ch1_cntDMA : in std_logic_vector(1 downto 0);
         ch1_cache : in std_logic;
         ch1_ready : out std_logic;
         cache_wr : out std_logic_vector(3 downto 0);
         cache_data : out std_logic_vector(31 downto 0);
         cache_addr : out std_logic_vector(7 downto 0);
         dma_wr, dma_reqprocessed : out std_logic;
         dma_data : out std_logic_vector(31 downto 0);
         ch2_addr : in std_logic_vector(26 downto 0);
         ch2_dout : out std_logic_vector(31 downto 0);
         ch2_din  : in std_logic_vector(31 downto 0);
         ch2_req, ch2_rnw : in std_logic;
         ch2_be : in std_logic_vector(3 downto 0);
         ch2_ready : out std_logic;
         ch3_addr : in std_logic_vector(26 downto 0);
         ch3_dout : out std_logic_vector(31 downto 0);
         ch3_din  : in std_logic_vector(31 downto 0);
         ch3_req, ch3_rnw : in std_logic;
         ch3_be : in std_logic_vector(3 downto 0);
         ch3_ready : out std_logic;
         dmafifo_adr  : in std_logic_vector(26 downto 0);
         dmafifo_data : in std_logic_vector(31 downto 0);
         dmafifo_empty : in std_logic;
         dmafifo_read : out std_logic
      );
   end component;

   signal clk1x, clk3x       : std_logic := '0';
   signal reset              : std_logic := '1';
   signal sdram_init         : std_logic := '1';

   -- CPU side
   signal mem_in_request     : std_logic := '0';
   signal mem_in_rnw         : std_logic := '1';
   signal mem_in_isData      : std_logic := '1';
   signal mem_in_isCache     : std_logic := '0';
   signal mem_in_address     : unsigned(31 downto 0) := (others => '0');
   signal mem_in_reqsize     : unsigned(1 downto 0) := "10";
   signal mem_in_writeMask   : std_logic_vector(3 downto 0) := "1111";
   signal mem_in_dataWrite   : std_logic_vector(31 downto 0) := (others => '0');
   signal mem_dataRead       : std_logic_vector(31 downto 0);
   signal mem_done           : std_logic;
   signal mem_fifofull       : std_logic;
   signal mem_tagvalids      : std_logic_vector(3 downto 0);
   signal isIdle             : std_logic;

   -- memorymux to RAM
   signal ram_dataWrite      : std_logic_vector(31 downto 0);
   signal ram_dataRead       : std_logic_vector(31 downto 0);
   signal ram_Adr_cpu        : std_logic_vector(24 downto 0);
   signal ram_Adr            : std_logic_vector(24 downto 0);
   signal ram_be             : std_logic_vector(3 downto 0);
   signal ram_rnw            : std_logic;
   signal ram_ena            : std_logic;
   signal ram_cache          : std_logic;
   signal ram_done           : std_logic;
   signal ram_cpu_done       : std_logic;
   signal ram_next_cpu       : std_logic := '0';

   -- memctrl
   signal bus_memc_addr      : unsigned(5 downto 0);
   signal bus_memc_dataWrite : std_logic_vector(31 downto 0);
   signal bus_memc_read      : std_logic;
   signal bus_memc_write     : std_logic;
   signal bus_memc_dataRead  : std_logic_vector(31 downto 0);
   signal bus_memc2_addr     : unsigned(3 downto 0);
   signal bus_memc2_dataWrite: std_logic_vector(31 downto 0);
   signal bus_memc2_read     : std_logic;
   signal bus_memc2_write    : std_logic;
   signal bus_memc2_dataRead : std_logic_vector(31 downto 0);
   signal spu_memctrl, cd_memctrl, bios_memctrl, ex1_memctrl, ex2_memctrl, ex3_memctrl : unsigned(13 downto 0);
   signal com0_delay, com1_delay, com2_delay, com3_delay : unsigned(3 downto 0);

   -- SDRAM
   signal sd_dq_w, sd_dq_r   : std_logic_vector(15 downto 0);
   signal sd_a               : std_logic_vector(12 downto 0);
   signal sd_ba              : std_logic_vector(1 downto 0);
   signal sd_ncs, sd_nwe, sd_nras, sd_ncas : std_logic;
   signal ch1_ready, ch2_ready : std_logic;
   signal ch_addr            : std_logic_vector(26 downto 0);
   signal ch1_dout32         : std_logic_vector(31 downto 0);
   signal cache_wr           : std_logic_vector(3 downto 0);
   signal idx                : std_logic;

   -- DMA and the psx_top RAM mux
   signal cpuPaused          : std_logic := '0';
   signal canDMA             : std_logic;
   signal dmaRequest, dmaOn  : std_logic;
   signal dma_ram_Adr        : std_logic_vector(22 downto 0);
   signal dma_ram_cnt        : std_logic_vector(1 downto 0);
   signal dma_ram_ena        : std_logic;
   signal ram_rnw_m, ram_ena_m, ram_dma_m, ram_cache_m : std_logic;
   signal dma_wr, dma_reqprocessed : std_logic;
   signal dma_data           : std_logic_vector(31 downto 0);
   signal dmafifo_adr        : std_logic_vector(22 downto 0);
   signal dmafifo_data       : std_logic_vector(31 downto 0);
   signal dmafifo_empty      : std_logic;
   signal dmafifo_read       : std_logic;
   signal dbus_addr          : unsigned(6 downto 0) := (others => '0');
   signal dbus_data          : std_logic_vector(31 downto 0) := (others => '0');
   signal dbus_write         : std_logic := '0';
   signal gpu_dmaRequest     : std_logic := '0';
   signal DMA_GPU_writeEna   : std_logic;
   signal DMA_GPU_write      : std_logic_vector(31 downto 0);
   signal idx_top            : std_logic;

   -- observation
   signal last_cache_wr_t    : time := 0 ns;
   signal idx_count          : integer := 0;
   signal base_count         : integer := 0;
   signal last_ref_t         : time := -1 ms;
   signal ref_count          : integer := 0;
   signal refcoll_count      : integer := 0;
   signal idx_mismatch       : integer := 0;
   signal idx_top_count      : integer := 0;
   signal fifo_wr1x_count    : integer := 0;
   signal fifo_wr3x_count    : integer := 0;
   signal dmafifo_rd_count   : integer := 0;
   signal gpu_words          : integer := 0;
   signal gpu_errors         : integer := 0;
   signal gpu_check          : boolean := false;


begin

   -- clk_1x and the SDRAM clock from one generator, rising edges aligned
   -- every RATIO SDRAM periods (one PLL, phase 0, as pll_0002.v)
   process
      variable k : integer := 0;
   begin
      clk3x <= '1';
      if k mod (2 * RATIO) = 0 then clk1x <= '1'; elsif k mod (2 * RATIO) = RATIO then clk1x <= '0'; end if;
      wait for T_FAST / 2;
      k := k + 1;
      clk3x <= '0';
      if k mod (2 * RATIO) = 0 then clk1x <= '1'; elsif k mod (2 * RATIO) = RATIO then clk1x <= '0'; end if;
      wait for T_FAST / 2;
      k := k + 1;
   end process;

   imemorymux : entity work.memorymux
   port map (
      clk1x => clk1x, clk2x => clk3x, ce => '1', reset => reset,
      pauseNext => '0', isIdle => isIdle,
      loadExe => '0', exe_initial_pc => (others => '0'), exe_initial_gp => (others => '0'),
      exe_load_address => (others => '0'), exe_file_size => (others => '0'), exe_stackpointer => (others => '0'),
      reset_exe => open, fastboot => '0', PATCHSERIAL => '0', TURBO => '0', region_in => "00",
      ram_dataWrite => ram_dataWrite, ram_dataRead => ram_dataRead, ram_Adr => ram_Adr_cpu, ram_be => ram_be,
      ram_rnw => ram_rnw, ram_ena => ram_ena, ram_cache => ram_cache, ram_done => ram_cpu_done,
      mem_in_request => mem_in_request, mem_in_rnw => mem_in_rnw, mem_in_isData => mem_in_isData,
      mem_in_isCache => mem_in_isCache, mem_in_oldtagvalids => "0000",
      mem_in_addressInstr => mem_in_address, mem_in_addressData => mem_in_address,
      mem_in_reqsize => mem_in_reqsize, mem_in_writeMask => mem_in_writeMask, mem_in_dataWrite => mem_in_dataWrite,
      mem_dataRead => mem_dataRead, mem_done => mem_done, mem_fifofull => mem_fifofull, mem_tagvalids => mem_tagvalids,
      bios_memctrl => bios_memctrl, ex1_memctrl => ex1_memctrl,
      bus_exp1_read => open, bus_exp1_dataRead => x"5A",
      bus_memc_addr => bus_memc_addr, bus_memc_dataWrite => bus_memc_dataWrite, bus_memc_read => bus_memc_read,
      bus_memc_write => bus_memc_write, bus_memc_dataRead => bus_memc_dataRead,
      bus_pad_addr => open, bus_pad_dataWrite => open, bus_pad_read => open, bus_pad_write => open, bus_pad_writeMask => open, bus_pad_dataRead => (others => '0'),
      bus_sio_addr => open, bus_sio_dataWrite => open, bus_sio_read => open, bus_sio_write => open, bus_sio_writeMask => open, bus_sio_dataRead => (others => '0'),
      bus_memc2_addr => bus_memc2_addr, bus_memc2_dataWrite => bus_memc2_dataWrite, bus_memc2_read => bus_memc2_read,
      bus_memc2_write => bus_memc2_write, bus_memc2_dataRead => bus_memc2_dataRead,
      bus_irq_addr => open, bus_irq_dataWrite => open, bus_irq_read => open, bus_irq_write => open, bus_irq_dataRead => (others => '0'),
      bus_dma_addr => open, bus_dma_dataWrite => open, bus_dma_read => open, bus_dma_write => open, bus_dma_dataRead => (others => '0'),
      bus_tmr_addr => open, bus_tmr_dataWrite => open, bus_tmr_read => open, bus_tmr_write => open, bus_tmr_dataRead => (others => '0'),
      cd_memctrl => cd_memctrl, bus_cd_addr => open, bus_cd_dataWrite => open, bus_cd_read => open, bus_cd_write => open, bus_cd_dataRead => x"00",
      bus_gpu_addr => open, bus_gpu_dataWrite => open, bus_gpu_read => open, bus_gpu_write => open, bus_gpu_dataRead => (others => '0'), bus_gpu_stall => '0',
      bus_mdec_addr => open, bus_mdec_dataWrite => open, bus_mdec_read => open, bus_mdec_write => open, bus_mdec_dataRead => (others => '0'),
      spu_memctrl => spu_memctrl, bus_spu_addr => open, bus_spu_dataWrite => open, bus_spu_read => open, bus_spu_write => open, bus_spu_dataRead => x"1234",
      ex2_memctrl => ex2_memctrl, bus_exp2_addr => open, bus_exp2_dataWrite => open, bus_exp2_read => open, bus_exp2_write => open, bus_exp2_dataRead => x"00",
      ex3_memctrl => ex3_memctrl, bus_exp3_read => open, bus_exp3_dataRead => x"0000",
      com0_delay => com0_delay, com1_delay => com1_delay, com2_delay => com2_delay, com3_delay => com3_delay,
      loading_savestate => '0', SS_reset => '0', SS_DataWrite => (others => '0'), SS_Adr => (others => '0'),
      SS_wren_SDRam => '0', SS_rden_SDRam => '0'
   );

   imemctrl : entity work.memctrl
   port map (
      clk1x => clk1x, ce => '1', reset => reset,
      bus_addr => bus_memc_addr, bus_dataWrite => bus_memc_dataWrite, bus_read => bus_memc_read,
      bus_write => bus_memc_write, bus_dataRead => bus_memc_dataRead,
      bus2_addr => bus_memc2_addr, bus2_dataWrite => bus_memc2_dataWrite, bus2_read => bus_memc2_read,
      bus2_write => bus_memc2_write, bus2_dataRead => bus_memc2_dataRead,
      errorBuswidth => open,
      spu_memctrl => spu_memctrl, cd_memctrl => cd_memctrl, bios_memctrl => bios_memctrl,
      ex1_memctrl => ex1_memctrl, ex2_memctrl => ex2_memctrl, ex3_memctrl => ex3_memctrl,
      com0_delay => com0_delay, com1_delay => com1_delay, com2_delay => com2_delay, com3_delay => com3_delay,
      dma_spu_timing_on => open, dma_spu_timing_value => open,
      loading_savestate => '0', SS_reset => '0', SS_DataWrite => (others => '0'), SS_Adr => (others => '0'),
      SS_wren => '0', SS_rden => '0', SS_DataRead => open
   );

   -- psx_top.vhd:1380-1404 (ram8mb = '0')
   ram_rnw_m   <= '1'         when (cpuPaused = '1') else ram_rnw;
   ram_ena_m   <= dma_ram_ena when (cpuPaused = '1') else ram_ena;
   ram_dma_m   <= '1'         when (cpuPaused = '1') else '0';
   ram_cache_m <= '0'         when (cpuPaused = '1') else ram_cache;
   ram_Adr <= "0000" & dma_ram_Adr(20 downto 0) when (cpuPaused = '1') else
              ram_Adr_cpu(24 downto 23) & "00" & ram_Adr_cpu(20 downto 0);
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         if ram_ena_m = '1' then
            ram_next_cpu <= '0';
            if (cpuPaused = '0') then ram_next_cpu <= '1'; end if;
         end if;
      end if;
   end process;
   ram_cpu_done <= ram_done and ram_next_cpu;

   -- psx_top.vhd:768, 813-816 (ce = '1', no pause sources)
   canDMA <= isIdle;
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         if reset = '1' then
            cpuPaused <= '0';
         elsif ((cpuPaused = '1' and dmaOn = '1') or (dmaRequest = '1' and canDMA = '1')) then
            cpuPaused <= '1';
         elsif (dmaOn = '0') then
            cpuPaused <= '0';
         end if;
      end if;
   end process;

   iindex : entity work.clk3x_index_copy
   generic map (CLK_FAST_RATIO => CLK_FAST_RATIO)
   port map (clk1x => clk1x, clk3x => clk3x, clk3xIndex_o => idx_top);

   idma : entity work.dma
   port map (
      clk1x => clk1x, clk3x => clk3x, clk3xIndex => idx_top, ce => '1', reset => reset,
      errorCHOP => open, errorDMACPU => open, errorDMAFIFO => open,
      TURBO => '0', TURBO_CACHE => '0', ram8mb => '0', ignoreCDTiming => '0',
      canDMA => canDMA, cpuPaused => cpuPaused, dmaRequest => dmaRequest, dmaStallCPU => open,
      dmaOn => dmaOn, irqOut => open,
      ram_Adr => dma_ram_Adr, ram_cnt => dma_ram_cnt, ram_ena => dma_ram_ena,
      dma_wr => dma_wr, dma_reqprocessed => dma_reqprocessed, dma_data => dma_data,
      ram_dmafifo_adr => dmafifo_adr, ram_dmafifo_data => dmafifo_data,
      ram_dmafifo_empty => dmafifo_empty, ram_dmafifo_read => dmafifo_read,
      dma_cache_Adr => open, dma_cache_data => open, dma_cache_write => open,
      gpu_dmaRequest => gpu_dmaRequest, DMA_GPU_waiting => open,
      DMA_GPU_writeEna => DMA_GPU_writeEna, DMA_GPU_readEna => open,
      DMA_GPU_write => DMA_GPU_write, DMA_GPU_read => (others => '0'),
      mdec_dmaWriteRequest => '0', mdec_dmaReadRequest => '0',
      DMA_MDEC_writeEna => open, DMA_MDEC_readEna => open, DMA_MDEC_write => open, DMA_MDEC_read => (others => '0'),
      cd_memctrl => cd_memctrl, com0_delay => com0_delay, DMA_CD_readEna => open, DMA_CD_read => (others => '0'),
      spu_timing_on => '0', spu_timing_value => (others => '0'),
      spu_dmaRequest => '0', DMA_SPU_writeEna => open, DMA_SPU_readEna => open,
      DMA_SPU_write => open, DMA_SPU_read => (others => '0'),
      bus_addr => dbus_addr, bus_dataWrite => dbus_data, bus_read => '0', bus_write => dbus_write,
      bus_dataRead => open,
      loading_savestate => '0', SS_reset => '0', SS_DataWrite => (others => '0'), SS_Adr => (others => '0'),
      SS_wren => '0', SS_rden => '0', SS_DataRead => open, SS_idle => open
   );

   -- PSX.sv:1291, 1318-1337
   ch_addr      <= "00" & ram_Adr;
   ram_done     <= ch1_ready or ch2_ready;
   ram_dataRead <= ch1_dout32;

   isdram : sdram
   generic map (CLK_FAST_RATIO => CLK_FAST_RATIO, EARLY_READY => EARLY_READY)
   port map (
      init => sdram_init, clk => clk3x, clk_base => clk1x, SDRAM_EN => '1',
      SDRAM_DQ => sd_dq_w, SDRAM_DQ_IN => sd_dq_r, idx_o => idx,
      SDRAM_A => sd_a, SDRAM_DQML => open, SDRAM_DQMH => open, SDRAM_BA => sd_ba,
      SDRAM_nCS => sd_ncs, SDRAM_nWE => sd_nwe, SDRAM_nRAS => sd_nras, SDRAM_nCAS => sd_ncas,
      SDRAM_CKE => open, SDRAM_CLK => open,
      refreshForce => '0', ram_idle => open,
      ch1_addr => ch_addr, ch1_dout => open, ch1_dout32 => ch1_dout32, ch1_din => (others => '0'),
      ch1_req => ram_ena_m and ram_rnw_m, ch1_rnw => '1', ch1_dma => ram_dma_m, ch1_cntDMA => dma_ram_cnt,
      ch1_cache => ram_cache_m, ch1_ready => ch1_ready,
      cache_wr => cache_wr, cache_data => open, cache_addr => open,
      dma_wr => dma_wr, dma_reqprocessed => dma_reqprocessed, dma_data => dma_data,
      ch2_addr => ch_addr, ch2_dout => open, ch2_din => ram_dataWrite,
      ch2_req => ram_ena_m and not ram_rnw_m, ch2_rnw => '0', ch2_be => ram_be, ch2_ready => ch2_ready,
      ch3_addr => (others => '0'), ch3_dout => open, ch3_din => (others => '0'),
      ch3_req => '0', ch3_rnw => '1', ch3_be => "1111", ch3_ready => open,
      dmafifo_adr => "0000" & dmafifo_adr, dmafifo_data => dmafifo_data, dmafifo_empty => dmafifo_empty,
      dmafifo_read => dmafifo_read
   );

   ichip : entity work.sdram_chip
   port map (clk => clk3x, ncs => sd_ncs, nras => sd_nras, ncas => sd_ncas, nwe => sd_nwe,
             ba => sd_ba, a => sd_a, dq_w => sd_dq_w, dq_r => sd_dq_r);

   process (clk3x)
   begin
      if rising_edge(clk3x) then
         if cache_wr /= "0000" then last_cache_wr_t <= now; end if;
         if idx = '1' and reset = '0' then idx_count <= idx_count + 1; end if;
         if idx_top = '1' and reset = '0' then idx_top_count <= idx_top_count + 1; end if;
         if idx /= idx_top and reset = '0' then idx_mismatch <= idx_mismatch + 1; end if;
         -- AUTO REFRESH on the command lines
         if sd_nras = '0' and sd_ncas = '0' and sd_nwe = '1' and reset = '0' then
            last_ref_t <= now;
            ref_count  <= ref_count + 1;
         end if;
         if dmafifo_read = '1' then dmafifo_rd_count <= dmafifo_rd_count + 1; end if;
      end if;
   end process;
   process (clk1x)
   begin
      if rising_edge(clk1x) and reset = '0' then
         base_count <= base_count + 1;
         -- a RAM request presented in a clk_1x cycle in which the controller
         -- issued AUTO REFRESH (the case that lost a request in Measurement 3)
         if ram_ena_m = '1' and now - last_ref_t <= RATIO * T_FAST then
            refcoll_count <= refcoll_count + 1;
         end if;
      end if;
   end process;

   -- DMA FIFO strobes inside dma.vhd: words handed over on clk_1x (fifoOut_Wr)
   -- against words written into the clk_3x FIFO (fifoOut_Wr_3x, dma.vhd:979)
   process (clk3x)
      alias fifo_wr3x is <<signal .tb_r1_mem.idma.fifoOut_Wr_3x : std_logic>>;
   begin
      if rising_edge(clk3x) then
         if fifo_wr3x = '1' then fifo_wr3x_count <= fifo_wr3x_count + 1; end if;
      end if;
   end process;
   process (clk1x)
      alias fifo_wr is <<signal .tb_r1_mem.idma.fifoOut_Wr : std_logic>>;
      variable exp : unsigned(31 downto 0);
   begin
      if rising_edge(clk1x) then
         if fifo_wr = '1' then fifo_wr1x_count <= fifo_wr1x_count + 1; end if;
         -- GPU DMA: word k of the ordering table, read back in ascending order
         if gpu_check and DMA_GPU_writeEna = '1' then
            if gpu_words = 0 then exp := x"00FFFFFF"; else exp := to_unsigned(16#100000# + 4 * (gpu_words - 1), 32); end if;
            if DMA_GPU_write /= std_logic_vector(exp) then gpu_errors <= gpu_errors + 1; end if;
            gpu_words <= gpu_words + 1;
         end if;
      end if;
   end process;

   gdebug : if DEBUG > 0 generate
      process (clk3x)
         variable k : integer := 0;
      begin
         if rising_edge(clk3x) and reset = '0' and k < DEBUG and now >= DBG_FROM then
            if ram_ena = '1' or ch1_ready = '1' or ch2_ready = '1' or sd_ncs = '0' or mem_in_request = '1' then
               report "dbg ena=" & std_logic'image(ram_ena) & " rnw=" & std_logic'image(ram_rnw) &
                      " r1=" & std_logic'image(ch1_ready) & " r2=" & std_logic'image(ch2_ready) &
                      " idx=" & std_logic'image(idx) & " cmd=" & std_logic'image(sd_nras) & std_logic'image(sd_ncas) & std_logic'image(sd_nwe) &
                      " ncs=" & std_logic'image(sd_ncs) & " req=" & std_logic'image(mem_in_request) & " done=" & std_logic'image(mem_done) &
                      " idle=" & std_logic'image(isIdle) & " dq=" & to_hstring(sd_dq_r);
               k := k + 1;
            end if;
         end if;
      end process;
   end generate;

   ---------------------------------------------------------------------------
   -- CPU driver
   ---------------------------------------------------------------------------
   process
      file fo         : text open write_mode is OUTFILE;
      variable l      : line;
      variable seed1  : positive := 11;
      variable seed2  : positive := 4711;
      variable rnd    : real;
      variable n      : integer;
      variable t0     : time;
      variable lat    : integer;
      variable fill_lat : real;
      variable lost   : boolean := false;
      variable errors : integer := 0;
      constant T_BASE : time := RATIO * T_FAST;
      -- per-row statistics
      variable s_n, s_min, s_max, s_sum : integer;
      variable f_min, f_max, f_sum : real;
      type t_hist is array(0 to 63) of integer;
      variable hist : t_hist;

      procedure cyc(c : integer) is
      begin
         for i in 1 to c loop wait until rising_edge(clk1x); end loop;
      end procedure;

      procedure stat_reset is
      begin
         s_n := 0; s_min := 1000000; s_max := -1; s_sum := 0;
         f_min := 1.0e9; f_max := -1.0; f_sum := 0.0; hist := (others => 0);
      end procedure;

      procedure stat_add(v : integer) is
      begin
         s_n := s_n + 1; s_sum := s_sum + v;
         if v < s_min then s_min := v; end if;
         if v > s_max then s_max := v; end if;
         if v < 64 then hist(v) := hist(v) + 1; end if;
      end procedure;

      procedure stat_out(name : string; unit : string) is
      begin
         write(l, string'("row ") & name & " " & unit & " n " & integer'image(s_n));
         if s_n > 0 then
            write(l, string'(" min ") & integer'image(s_min) & " max " & integer'image(s_max) & " mean ");
            write(l, real(s_sum) / real(s_n), right, 0, 2);
            write(l, string'(" hist"));
            for i in 0 to 63 loop
               if hist(i) > 0 then write(l, string'(" ") & integer'image(i) & ":" & integer'image(hist(i))); end if;
            end loop;
         end if;
         writeline(fo, l);
         if f_max >= 0.0 then
            write(l, string'("row ") & name & " last_cache_word_cycles min ");
            write(l, f_min, right, 0, 2); write(l, string'(" max ")); write(l, f_max, right, 0, 2);
            write(l, string'(" mean ")); write(l, f_sum / real(s_n), right, 0, 2);
            writeline(fo, l);
         end if;
      end procedure;

      -- one CPU access; returns the latency in clk_1x edges, -1 if lost
      procedure cpu_access(addr : unsigned(31 downto 0); rnw, isData, isCache : std_logic;
                       size : unsigned(1 downto 0); mask : std_logic_vector(3 downto 0);
                       wdata : std_logic_vector(31 downto 0); variable lat : out integer) is
      begin
         mem_in_request   <= '1';
         mem_in_address   <= addr;
         mem_in_rnw       <= rnw;
         mem_in_isData    <= isData;
         mem_in_isCache   <= isCache;
         mem_in_reqsize   <= size;
         mem_in_writeMask <= mask;
         mem_in_dataWrite <= wdata;
         wait until rising_edge(clk1x);     -- this edge samples the request
         t0 := now;
         mem_in_request <= '0';
         n := 0;
         loop
            wait until rising_edge(clk1x);
            n := n + 1;
            if rnw = '1' and mem_done = '1' then exit; end if;
            if rnw = '0' and isIdle = '1' then exit; end if;
            if n > 2000 then
               lat := -1;
               return;
            end if;
         end loop;
         lat := n;
      end procedure;

      procedure wr32(addr : unsigned(31 downto 0); data : std_logic_vector(31 downto 0)) is
         variable lt : integer;
      begin
         cpu_access(addr, '0', '1', '0', "10", "1111", data, lt);
         if lt < 0 then lost := true; end if;
      end procedure;

      function expect32(addr : unsigned(31 downto 0)) return std_logic_vector is
         variable w : unsigned(23 downto 0);
         variable sd : unsigned(26 downto 0);
      begin
         -- RAM: memorymux ram_Adr = "00" & addr(22..2) & "00", glue keeps bits 20..0
         sd := (others => '0');
         sd(20 downto 0) := addr(20 downto 0);
         if addr(28 downto 20) = "111111100" then           -- BIOS 0x1FC00000: "01" & "00" & region & addr(18..0)
            sd := (others => '0');
            sd(23) := '1';
            sd(18 downto 0) := addr(18 downto 0);
         end if;
         w := sd(24 downto 1);
         return fill(w + 1) & fill(w);
      end function;

      variable gap : integer;
      variable a   : unsigned(31 downto 0);
      variable expv : std_logic_vector(31 downto 0);
      variable lt0, n_otc, n_gpu, otc_err : integer;

      -- one DMA register write on the DMA bus (bus_addr = address bits 6..0)
      procedure dma_reg(addr : integer; data : std_logic_vector(31 downto 0)) is
      begin
         dbus_addr  <= to_unsigned(addr, 7);
         dbus_data  <= data;
         dbus_write <= '1';
         wait until rising_edge(clk1x);
         dbus_write <= '0';
         cyc(2);
      end procedure;

      -- wait until a DMA has started and the CPU owns the bus again;
      -- clk_1x cycles from the call, -1 on timeout
      procedure dma_wait(variable c : out integer) is
         variable k : integer;
      begin
         c := -1;
         k := 0;
         while dmaOn = '0' loop
            wait until rising_edge(clk1x);
            k := k + 1;
            if k > 1000 then return; end if;
         end loop;
         while dmaOn = '1' or cpuPaused = '1' loop
            wait until rising_edge(clk1x);
            k := k + 1;
            if k > 400000 then return; end if;
         end loop;
         c := k;
      end procedure;

      -- run NREP reads of one kind with random gaps gmin..gmax in front
      procedure rows_read(name : string; base : unsigned(31 downto 0); stride : integer; span : integer;
                          isData, isCache : std_logic; size : unsigned(1 downto 0);
                          gmin, gmax : integer; check : boolean) is
         variable lt : integer;
      begin
         stat_reset;
         for r in 0 to NREP - 1 loop
            uniform(seed1, seed2, rnd);
            gap := gmin + integer(floor(rnd * real(gmax - gmin + 1)));
            if gap > 0 then cyc(gap); end if;
            uniform(seed1, seed2, rnd);
            a := base + to_unsigned((integer(floor(rnd * real(span))) * stride) mod 16#100000#, 32);
            cpu_access(a, '1', isData, isCache, size, "1111", x"00000000", lt);
            if lt < 0 then
               lost := true;
               write(l, string'("LOST row ") & name & " sample " & integer'image(r) & " at " & time'image(now));
               writeline(fo, l);
               return;
            end if;
            stat_add(lt);
            if check and size = "10" then
               expv := expect32(a);
               if mem_dataRead /= expv then errors := errors + 1; end if;
            end if;
            if isCache = '1' then
               cyc(12);
               fill_lat := real((last_cache_wr_t - t0) / (T_BASE / 100)) / 100.0;
               f_sum := f_sum + fill_lat;
               if fill_lat < f_min then f_min := fill_lat; end if;
               if fill_lat > f_max then f_max := fill_lat; end if;
            end if;
         end loop;
         stat_out(name, "read_to_mem_done");
      end procedure;

      -- a read immediately (gap g) after another access of the same kind; the second is measured
      procedure rows_pair(name : string; base : unsigned(31 downto 0); size : unsigned(1 downto 0); g : integer) is
         variable lt : integer;
      begin
         stat_reset;
         for r in 0 to NREP - 1 loop
            uniform(seed1, seed2, rnd);
            cyc(10 + integer(floor(rnd * 30.0)));
            a := base + to_unsigned(r * 64 mod 16#100000#, 32);
            cpu_access(a, '1', '1', '0', size, "1111", x"00000000", lt);
            if lt < 0 then lost := true; exit; end if;
            if g > 0 then cyc(g); end if;
            cpu_access(a + 4, '1', '1', '0', size, "1111", x"00000000", lt);
            if lt < 0 then
               lost := true;
               write(l, string'("LOST row ") & name & " sample " & integer'image(r) & " at " & time'image(now));
               writeline(fo, l);
               return;
            end if;
            stat_add(lt);
            if mem_dataRead /= expect32(a + 4) then errors := errors + 1; end if;
         end loop;
         stat_out(name, "read_to_mem_done");
      end procedure;

      function maxi(x, y : integer) return integer is
      begin
         if x > y then return x; end if;
         return y;
      end function;

      -- writes: occupancy until isIdle; then a read right after (latency of that read)
      procedure rows_write(name : string; base : unsigned(31 downto 0); stride : integer; span : integer; prime : integer) is
         variable lt, lt2 : integer;
         variable s2_n, s2_min, s2_max, s2_sum : integer;
         variable wdat : std_logic_vector(31 downto 0);
      begin
         stat_reset;
         s2_n := 0; s2_min := 100000; s2_max := -1; s2_sum := 0;
         for r in 0 to NREP - 1 loop
            uniform(seed1, seed2, rnd);
            cyc(10 + integer(floor(rnd * 30.0)));
            uniform(seed1, seed2, rnd);
            a := base + to_unsigned((integer(floor(rnd * real(span))) * stride) mod 16#100000#, 32);
            if prime = 1 then    -- open the page with a write to the same 1 KB page first
               cpu_access(a xor x"00000010", '0', '1', '0', "10", "1111", x"00000000", lt);
               if lt < 0 then lost := true; exit; end if;
            elsif prime = 2 then -- open another page with a write first
               cpu_access(a xor x"00000400", '0', '1', '0', "10", "1111", x"00000000", lt);
               if lt < 0 then lost := true; exit; end if;
            end if;
            -- r * 2654435 mod 2^30, in unsigned so that NREP above 808 does not overflow
            wdat := std_logic_vector(resize(to_unsigned(r, 32) * to_unsigned(2654435, 32), 32)) and x"3FFFFFFF";
            cpu_access(a, '0', '1', '0', "10", "1111", wdat, lt);
            if lt < 0 then
               lost := true;
               write(l, string'("LOST row ") & name & " write sample " & integer'image(r) & " at " & time'image(now));
               writeline(fo, l);
               return;
            end if;
            stat_add(lt);
            cpu_access(a, '1', '1', '0', "10", "1111", x"00000000", lt2);
            if lt2 < 0 then
               lost := true;
               write(l, string'("LOST row ") & name & " readback sample " & integer'image(r) & " at " & time'image(now));
               writeline(fo, l);
               return;
            end if;
            if mem_dataRead /= wdat then errors := errors + 1; end if;
            s2_n := s2_n + 1; s2_sum := s2_sum + lt2;
            if lt2 < s2_min then s2_min := lt2; end if;
            if lt2 > s2_max then s2_max := lt2; end if;
         end loop;
         stat_out(name, "write_to_idle");
         write(l, string'("row ") & name & " readback_after_write n " & integer'image(s2_n) & " min " & integer'image(s2_min) &
                  " max " & integer'image(s2_max) & " mean ");
         write(l, real(s2_sum) / real(maxi(s2_n, 1)), right, 0, 2);
         writeline(fo, l);
      end procedure;

   begin
      write(l, string'("ratio ") & integer'image(RATIO) & " t_fast " & time'image(T_FAST) & " nrep " & integer'image(NREP));
      writeline(fo, l);
      write(l, string'("clk_fast_ratio ") & integer'image(CLK_FAST_RATIO) & " early_ready " & integer'image(EARLY_READY) & " rows " & integer'image(ROWS) & " dma_n " & integer'image(DMA_N));
      writeline(fo, l);
      cyc(4);
      sdram_init <= '0';
      cyc(10);
      reset <= '0';
      -- SDRAM startup: 12100 SDRAM cycles plus the init sequence (sdram.sv:101, 310-341)
      cyc(13000 / RATIO + 200);

      -- G-NET game values from the MAME 0.288 trace (raycris, docs/r1_cpu_domain_design.md Measurement 1)
      wr32(x"1F801008", x"201716BB");   -- EXP1 delay/size (flash)
      wr32(x"1F801020", x"00000110");   -- COM delay (resting value)

      if ROWS > 0 then
         if not lost then rows_read("ram_lw_isolated", x"80010000", 4, 4096, '1', '0', "10", 8, 40, true); end if;
         if not lost then rows_pair("ram_lw_back_to_back_gap0", x"80020000", "10", 0); end if;
         if not lost then rows_pair("ram_lw_back_to_back_gap2", x"80020000", "10", 2); end if;
         if not lost then rows_read("ram_lbu_isolated", x"80010000", 1, 16384, '1', '0', "00", 8, 40, false); end if;
         if not lost then rows_read("ifetch_ram_cached_line", x"80030000", 16, 4096, '0', '1', "10", 2, 40, false); end if;
         if not lost then rows_read("ifetch_ram_uncached", x"A0040000", 4, 4096, '0', '0', "10", 2, 40, false); end if;
         if not lost then rows_read("ifetch_bios", x"BFC00000", 4, 16384, '0', '0', "10", 0, 10, false); end if;
         if not lost then rows_read("bios_lw", x"BFC00000", 4, 16384, '1', '0', "10", 2, 20, true); end if;
         if not lost then rows_read("bios_lh", x"BFC00000", 2, 16384, '1', '0', "01", 2, 20, false); end if;
         if not lost then rows_read("bios_lb", x"BFC00000", 1, 16384, '1', '0', "00", 2, 20, false); end if;
         if not lost then rows_write("ram_sw_after_read", x"80050000", 4, 4096, 0); end if;
         if not lost then rows_write("ram_sw_after_sw_same_page", x"80050000", 4, 4096, 1); end if;
         if not lost then rows_write("ram_sw_after_sw_other_page", x"80060000", 4, 4096, 2); end if;
         if not lost then rows_read("exp1_lw_201716bb", x"1F000000", 4, 4096, '1', '0', "10", 2, 20, false); end if;
         if not lost then rows_read("exp1_lh_201716bb", x"1F000000", 2, 4096, '1', '0', "01", 2, 20, false); end if;
         if not lost then rows_read("exp1_lb_201716bb", x"1F000000", 1, 4096, '1', '0', "00", 2, 20, false); end if;
         -- SPU register access as the games do it (SPU delay 0x20093127, COM 0x112 read / 0x117 write)
         if not lost then
            wr32(x"1F801014", x"20093127");
            wr32(x"1F801020", x"00000112");
            rows_read("spu_lh_20093127_com112", x"1F801C0C", 16, 24, '1', '0', "01", 2, 20, false);
         end if;
         if not lost then
            wr32(x"1F801014", x"00093184");
            wr32(x"1F801020", x"00000110");
            rows_read("spu_lh_00093184_com110", x"1F801C0C", 16, 24, '1', '0', "01", 2, 20, false);
         end if;
      end if;

      write(l, string'("data_errors ") & integer'image(errors));
      writeline(fo, l);
      write(l, string'("clk3xIndex_pulses ") & integer'image(idx_count) & " clk1x_cycles " & integer'image(base_count));
      writeline(fo, l);
      write(l, string'("refresh_commands ") & integer'image(ref_count) & " requests_in_a_refresh_cycle " & integer'image(refcoll_count));
      writeline(fo, l);

      -- DMA phase: OTC through the DMA output FIFO, CPU read-back, GPU DMA read
      if DMA_N > 0 and not lost then
         dma_reg(16#70#, x"0F654B21");                                                      -- DPCR: channels 6 and 2 on
         dma_reg(16#60#, std_logic_vector(to_unsigned(16#100000# + 4 * (DMA_N - 1), 32)));   -- MADR: top of the table
         dma_reg(16#64#, std_logic_vector(to_unsigned(DMA_N, 32)));                         -- BCR
         dma_reg(16#68#, x"11000002");                                                      -- CHCR: start, enable, decrement
         dma_wait(n_otc);
         cyc(50);
         write(l, string'("dma_otc words ") & integer'image(DMA_N) & " cycles " & integer'image(n_otc) &
                  " fifo_wr_clk1x " & integer'image(fifo_wr1x_count) & " fifo_wr_clk3x " & integer'image(fifo_wr3x_count) &
                  " sdram_dmafifo_reads " & integer'image(dmafifo_rd_count));
         writeline(fo, l);
         if n_otc < 0 then lost := true; end if;
         -- every word handed over once, written into the FIFO once, written to the SDRAM once
         otc_err := abs(fifo_wr1x_count - DMA_N) + abs(fifo_wr3x_count - DMA_N) + abs(dmafifo_rd_count - DMA_N);
         for i in 0 to DMA_N - 1 loop
            exit when lost;
            cpu_access(x"80100000" + to_unsigned(4 * i, 32), '1', '1', '0', "10", "1111", x"00000000", lt0);
            if lt0 < 0 then
               lost := true;
               write(l, string'("LOST dma_otc_readback word ") & integer'image(i) & " at " & time'image(now));
               writeline(fo, l);
               exit;
            end if;
            if i = 0 then expv := x"00FFFFFF"; else expv := std_logic_vector(to_unsigned(16#100000# + 4 * (i - 1), 32)); end if;
            if mem_dataRead /= expv then otc_err := otc_err + 1; end if;
         end loop;
         write(l, string'("dma_otc errors (word counts and CPU read-back) ") & integer'image(otc_err));
         writeline(fo, l);
         errors := errors + otc_err;
         if not lost then
            gpu_check      <= true;
            gpu_dmaRequest <= '1';
            dma_reg(16#20#, x"00100000");                                                   -- MADR: bottom of the table
            dma_reg(16#24#, std_logic_vector(to_unsigned(DMA_N, 32)));                      -- BCR
            dma_reg(16#28#, x"11000001");                                                   -- CHCR: start, enable, from RAM, increment
            dma_wait(n_gpu);
            gpu_dmaRequest <= '0';
            cyc(10);
            write(l, string'("dma_gpu words ") & integer'image(gpu_words) & " of " & integer'image(DMA_N) &
                     " cycles " & integer'image(n_gpu) & " errors " & integer'image(gpu_errors));
            writeline(fo, l);
            if n_gpu < 0 then lost := true; end if;
            errors := errors + gpu_errors + abs(gpu_words - DMA_N);
         end if;
         write(l, string'("clk3xIndex_pulses_psx_top ") & integer'image(idx_top_count) & " sdram_vs_psx_top_mismatches " & integer'image(idx_mismatch) &
                  " clk1x_cycles " & integer'image(base_count));
         writeline(fo, l);
         write(l, string'("refresh_commands_total ") & integer'image(ref_count) & " requests_in_a_refresh_cycle_total " & integer'image(refcoll_count));
         writeline(fo, l);
         write(l, string'("data_errors_total ") & integer'image(errors));
         writeline(fo, l);
      end if;
      if lost then write(l, string'("result LOST")); else write(l, string'("result COMPLETE")); end if;
      writeline(fo, l);
      file_close(fo);
      std.env.finish;
   end process;

end architecture;
