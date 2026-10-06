-- Test harness around memorymux for sim/zn2 (docs/zn2_layer_design.md 16).
-- VARIANT 0: upstream memorymux (entity memorymux_up, extracted from main by
--            run_memorymux.sh), 1: this branch with ZN2_MAP = 0,
--            2: this branch with ZN2_MAP = 1 and a ZN bus device model,
--            ZN2_READ_OVERLAP = OVERLAP,
--            3: the previous ZN-2 memorymux (entity memorymux_prev, taken by
--            run_memorymux.sh from the revision in PREV_REF) with ZN2_MAP = 1
--            and the same device model.
-- Models: main RAM/BIOS (fixed latency, data a function of the address and
-- the last write), internal and external bus devices (registered read data
-- a function of the address), and for VARIANT 2 a 64 KB lane-addressed
-- device on the zn_* port with a pseudo-random acknowledge latency.
-- Every memorymux output is packed into obs for cycle-by-cycle comparison.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity mm_harness is
   generic
   (
      VARIANT : integer := 1;
      SEED    : integer := 1;
      OVERLAP : integer := 0;    -- VARIANT 2: memorymux ZN2_READ_OVERLAP
      FIXED_LAT : integer := 0   -- ZN device: 0 = pseudo-random latency 1 to 13, n > 0 = always n cycles
   );
   port
   (
      clk1x, clk2x, ce, reset : in std_logic;
      mem_in_request       : in  std_logic;
      mem_in_rnw           : in  std_logic;
      mem_in_isData        : in  std_logic;
      mem_in_isCache       : in  std_logic;
      mem_in_addressInstr  : in  unsigned(31 downto 0);
      mem_in_addressData   : in  unsigned(31 downto 0);
      mem_in_reqsize       : in  unsigned(1 downto 0);
      mem_in_writeMask     : in  std_logic_vector(3 downto 0);
      mem_in_dataWrite     : in  std_logic_vector(31 downto 0);
      ex1_memctrl, ex2_memctrl, ex3_memctrl, spu_memctrl, cd_memctrl, bios_memctrl : in unsigned(13 downto 0);
      com0_delay, com1_delay, com2_delay, com3_delay : in unsigned(3 downto 0);
      mem_dataRead         : out std_logic_vector(31 downto 0);
      mem_done             : out std_logic;
      mem_fifofull         : out std_logic;
      isIdle               : out std_logic;
      obs                  : out std_logic_vector(511 downto 0);
      -- obs with mem_dataRead and zn_addr cleared: what must stay equal when
      -- only the address of misdirected write steps differs
      obs_core             : out std_logic_vector(511 downto 0);
      -- ZN device log (VARIANT 2): every accepted request
      zn_log_valid         : out std_logic;
      zn_log_we            : out std_logic;
      zn_log_addr          : out unsigned(23 downto 0);
      zn_log_be            : out std_logic_vector(3 downto 0);
      zn_log_data          : out std_logic_vector(31 downto 0);
      zn_dev_peek_addr     : in  unsigned(15 downto 0);
      zn_dev_peek          : out std_logic_vector(7 downto 0)
   );
end entity;

architecture sim of mm_harness is

   signal ram_dataWrite   : std_logic_vector(31 downto 0);
   signal ram_dataRead    : std_logic_vector(31 downto 0) := (others => '0');
   signal ram_Adr         : std_logic_vector(24 downto 0);
   signal ram_be          : std_logic_vector(3 downto 0);
   signal ram_rnw, ram_ena, ram_cache : std_logic;
   signal ram_done        : std_logic := '0';
   signal reset_exe       : std_logic;
   signal mem_tagvalids   : std_logic_vector(3 downto 0);
   signal mem_dataRead_i  : std_logic_vector(31 downto 0);
   signal mem_done_i, mem_fifofull_i, isIdle_i : std_logic;

   signal bus_exp1_read   : std_logic;
   signal bus_exp1_dataRead : std_logic_vector(7 downto 0) := (others => '0');
   signal bus_memc_addr   : unsigned(5 downto 0);
   signal bus_memc_dataWrite : std_logic_vector(31 downto 0);
   signal bus_memc_read, bus_memc_write : std_logic;
   signal bus_memc_dataRead : std_logic_vector(31 downto 0) := (others => '0');
   signal bus_pad_addr, bus_sio_addr, bus_memc2_addr, bus_irq_addr, bus_cd_addr, bus_gpu_addr, bus_mdec_addr : unsigned(3 downto 0);
   signal bus_pad_dataWrite, bus_sio_dataWrite, bus_memc2_dataWrite, bus_irq_dataWrite, bus_dma_dataWrite, bus_tmr_dataWrite, bus_gpu_dataWrite, bus_mdec_dataWrite : std_logic_vector(31 downto 0);
   signal bus_pad_read, bus_pad_write, bus_sio_read, bus_sio_write, bus_memc2_read, bus_memc2_write, bus_irq_read, bus_irq_write : std_logic;
   signal bus_dma_read, bus_dma_write, bus_tmr_read, bus_tmr_write, bus_cd_read, bus_cd_write, bus_gpu_read, bus_gpu_write, bus_mdec_read, bus_mdec_write : std_logic;
   signal bus_pad_writeMask, bus_sio_writeMask : std_logic_vector(3 downto 0);
   signal bus_pad_dataRead, bus_sio_dataRead, bus_memc2_dataRead, bus_irq_dataRead, bus_dma_dataRead, bus_tmr_dataRead, bus_gpu_dataRead, bus_mdec_dataRead : std_logic_vector(31 downto 0) := (others => '0');
   signal bus_dma_addr    : unsigned(6 downto 0);
   signal bus_tmr_addr    : unsigned(5 downto 0);
   signal bus_cd_dataWrite : std_logic_vector(7 downto 0);
   signal bus_cd_dataRead : std_logic_vector(7 downto 0) := (others => '0');
   signal bus_spu_addr    : unsigned(9 downto 0);
   signal bus_spu_dataWrite : std_logic_vector(15 downto 0);
   signal bus_spu_read, bus_spu_write : std_logic;
   signal bus_spu_dataRead : std_logic_vector(15 downto 0) := (others => '0');
   signal bus_exp2_addr   : unsigned(12 downto 0);
   signal bus_exp2_dataWrite : std_logic_vector(7 downto 0);
   signal bus_exp2_read, bus_exp2_write : std_logic;
   signal bus_exp2_dataRead : std_logic_vector(7 downto 0) := (others => '0');
   signal bus_exp3_read   : std_logic;
   signal bus_exp3_dataRead : std_logic_vector(15 downto 0) := (others => '0');

   signal zn_req, zn_we   : std_logic := '0';
   signal zn_addr         : unsigned(23 downto 0) := (others => '0');
   signal zn_be           : std_logic_vector(3 downto 0) := (others => '0');
   signal zn_wdata        : std_logic_vector(31 downto 0) := (others => '0');
   signal zn_ack          : std_logic := '0';
   signal zn_rdata        : std_logic_vector(31 downto 0) := (others => '0');

   type t_dev is array(0 to 65535) of std_logic_vector(7 downto 0);
   signal dev : t_dev;

   function f32(a : unsigned; salt : integer) return std_logic_vector is
      variable x : unsigned(31 downto 0);
   begin
      x := resize(resize(a, 32) * unsigned'(x"9E3779B1"), 32) + to_unsigned(salt, 32);
      return std_logic_vector(x xor shift_right(x, 13));
   end function;

begin

   gup : if VARIANT = 0 generate
      i : entity work.memorymux_up
      port map (
         clk1x => clk1x, clk2x => clk2x, ce => ce, reset => reset,
         pauseNext => '0', isIdle => isIdle_i,
         loadExe => '0', exe_initial_pc => (others => '0'), exe_initial_gp => (others => '0'),
         exe_load_address => (others => '0'), exe_file_size => (others => '0'), exe_stackpointer => (others => '0'),
         reset_exe => reset_exe, fastboot => '0', PATCHSERIAL => '0', TURBO => '0', region_in => "00",
         ram_dataWrite => ram_dataWrite, ram_dataRead => ram_dataRead, ram_Adr => ram_Adr, ram_be => ram_be,
         ram_rnw => ram_rnw, ram_ena => ram_ena, ram_cache => ram_cache, ram_done => ram_done,
         mem_in_request => mem_in_request, mem_in_rnw => mem_in_rnw, mem_in_isData => mem_in_isData,
         mem_in_isCache => mem_in_isCache, mem_in_oldtagvalids => "0000",
         mem_in_addressInstr => mem_in_addressInstr, mem_in_addressData => mem_in_addressData,
         mem_in_reqsize => mem_in_reqsize, mem_in_writeMask => mem_in_writeMask, mem_in_dataWrite => mem_in_dataWrite,
         mem_dataRead => mem_dataRead_i, mem_done => mem_done_i, mem_fifofull => mem_fifofull_i, mem_tagvalids => mem_tagvalids,
         bios_memctrl => bios_memctrl, ex1_memctrl => ex1_memctrl, bus_exp1_read => bus_exp1_read, bus_exp1_dataRead => bus_exp1_dataRead,
         bus_memc_addr => bus_memc_addr, bus_memc_dataWrite => bus_memc_dataWrite, bus_memc_read => bus_memc_read, bus_memc_write => bus_memc_write, bus_memc_dataRead => bus_memc_dataRead,
         bus_pad_addr => bus_pad_addr, bus_pad_dataWrite => bus_pad_dataWrite, bus_pad_read => bus_pad_read, bus_pad_write => bus_pad_write, bus_pad_writeMask => bus_pad_writeMask, bus_pad_dataRead => bus_pad_dataRead,
         bus_sio_addr => bus_sio_addr, bus_sio_dataWrite => bus_sio_dataWrite, bus_sio_read => bus_sio_read, bus_sio_write => bus_sio_write, bus_sio_writeMask => bus_sio_writeMask, bus_sio_dataRead => bus_sio_dataRead,
         bus_memc2_addr => bus_memc2_addr, bus_memc2_dataWrite => bus_memc2_dataWrite, bus_memc2_read => bus_memc2_read, bus_memc2_write => bus_memc2_write, bus_memc2_dataRead => bus_memc2_dataRead,
         bus_irq_addr => bus_irq_addr, bus_irq_dataWrite => bus_irq_dataWrite, bus_irq_read => bus_irq_read, bus_irq_write => bus_irq_write, bus_irq_dataRead => bus_irq_dataRead,
         bus_dma_addr => bus_dma_addr, bus_dma_dataWrite => bus_dma_dataWrite, bus_dma_read => bus_dma_read, bus_dma_write => bus_dma_write, bus_dma_dataRead => bus_dma_dataRead,
         bus_tmr_addr => bus_tmr_addr, bus_tmr_dataWrite => bus_tmr_dataWrite, bus_tmr_read => bus_tmr_read, bus_tmr_write => bus_tmr_write, bus_tmr_dataRead => bus_tmr_dataRead,
         cd_memctrl => cd_memctrl, bus_cd_addr => bus_cd_addr, bus_cd_dataWrite => bus_cd_dataWrite, bus_cd_read => bus_cd_read, bus_cd_write => bus_cd_write, bus_cd_dataRead => bus_cd_dataRead,
         bus_gpu_addr => bus_gpu_addr, bus_gpu_dataWrite => bus_gpu_dataWrite, bus_gpu_read => bus_gpu_read, bus_gpu_write => bus_gpu_write, bus_gpu_dataRead => bus_gpu_dataRead, bus_gpu_stall => '0',
         bus_mdec_addr => bus_mdec_addr, bus_mdec_dataWrite => bus_mdec_dataWrite, bus_mdec_read => bus_mdec_read, bus_mdec_write => bus_mdec_write, bus_mdec_dataRead => bus_mdec_dataRead,
         spu_memctrl => spu_memctrl, bus_spu_addr => bus_spu_addr, bus_spu_dataWrite => bus_spu_dataWrite, bus_spu_read => bus_spu_read, bus_spu_write => bus_spu_write, bus_spu_dataRead => bus_spu_dataRead,
         ex2_memctrl => ex2_memctrl, bus_exp2_addr => bus_exp2_addr, bus_exp2_dataWrite => bus_exp2_dataWrite, bus_exp2_read => bus_exp2_read, bus_exp2_write => bus_exp2_write, bus_exp2_dataRead => bus_exp2_dataRead,
         ex3_memctrl => ex3_memctrl, bus_exp3_read => bus_exp3_read, bus_exp3_dataRead => bus_exp3_dataRead,
         com0_delay => com0_delay, com1_delay => com1_delay, com2_delay => com2_delay, com3_delay => com3_delay,
         loading_savestate => '0', SS_reset => '0', SS_DataWrite => (others => '0'), SS_Adr => (others => '0'),
         SS_wren_SDRam => '0', SS_rden_SDRam => '0'
      );
   end generate;

   gprev : if VARIANT = 3 generate
      i : entity work.memorymux_prev
      generic map (ZN2_MAP => 1)
      port map (
         clk1x => clk1x, clk2x => clk2x, ce => ce, reset => reset,
         pauseNext => '0', isIdle => isIdle_i,
         loadExe => '0', exe_initial_pc => (others => '0'), exe_initial_gp => (others => '0'),
         exe_load_address => (others => '0'), exe_file_size => (others => '0'), exe_stackpointer => (others => '0'),
         reset_exe => reset_exe, fastboot => '0', PATCHSERIAL => '0', TURBO => '0', region_in => "00",
         ram_dataWrite => ram_dataWrite, ram_dataRead => ram_dataRead, ram_Adr => ram_Adr, ram_be => ram_be,
         ram_rnw => ram_rnw, ram_ena => ram_ena, ram_cache => ram_cache, ram_done => ram_done,
         mem_in_request => mem_in_request, mem_in_rnw => mem_in_rnw, mem_in_isData => mem_in_isData,
         mem_in_isCache => mem_in_isCache, mem_in_oldtagvalids => "0000",
         mem_in_addressInstr => mem_in_addressInstr, mem_in_addressData => mem_in_addressData,
         mem_in_reqsize => mem_in_reqsize, mem_in_writeMask => mem_in_writeMask, mem_in_dataWrite => mem_in_dataWrite,
         mem_dataRead => mem_dataRead_i, mem_done => mem_done_i, mem_fifofull => mem_fifofull_i, mem_tagvalids => mem_tagvalids,
         bios_memctrl => bios_memctrl, ex1_memctrl => ex1_memctrl, bus_exp1_read => bus_exp1_read, bus_exp1_dataRead => bus_exp1_dataRead,
         bus_memc_addr => bus_memc_addr, bus_memc_dataWrite => bus_memc_dataWrite, bus_memc_read => bus_memc_read, bus_memc_write => bus_memc_write, bus_memc_dataRead => bus_memc_dataRead,
         bus_pad_addr => bus_pad_addr, bus_pad_dataWrite => bus_pad_dataWrite, bus_pad_read => bus_pad_read, bus_pad_write => bus_pad_write, bus_pad_writeMask => bus_pad_writeMask, bus_pad_dataRead => bus_pad_dataRead,
         bus_sio_addr => bus_sio_addr, bus_sio_dataWrite => bus_sio_dataWrite, bus_sio_read => bus_sio_read, bus_sio_write => bus_sio_write, bus_sio_writeMask => bus_sio_writeMask, bus_sio_dataRead => bus_sio_dataRead,
         bus_memc2_addr => bus_memc2_addr, bus_memc2_dataWrite => bus_memc2_dataWrite, bus_memc2_read => bus_memc2_read, bus_memc2_write => bus_memc2_write, bus_memc2_dataRead => bus_memc2_dataRead,
         bus_irq_addr => bus_irq_addr, bus_irq_dataWrite => bus_irq_dataWrite, bus_irq_read => bus_irq_read, bus_irq_write => bus_irq_write, bus_irq_dataRead => bus_irq_dataRead,
         bus_dma_addr => bus_dma_addr, bus_dma_dataWrite => bus_dma_dataWrite, bus_dma_read => bus_dma_read, bus_dma_write => bus_dma_write, bus_dma_dataRead => bus_dma_dataRead,
         bus_tmr_addr => bus_tmr_addr, bus_tmr_dataWrite => bus_tmr_dataWrite, bus_tmr_read => bus_tmr_read, bus_tmr_write => bus_tmr_write, bus_tmr_dataRead => bus_tmr_dataRead,
         cd_memctrl => cd_memctrl, bus_cd_addr => bus_cd_addr, bus_cd_dataWrite => bus_cd_dataWrite, bus_cd_read => bus_cd_read, bus_cd_write => bus_cd_write, bus_cd_dataRead => bus_cd_dataRead,
         bus_gpu_addr => bus_gpu_addr, bus_gpu_dataWrite => bus_gpu_dataWrite, bus_gpu_read => bus_gpu_read, bus_gpu_write => bus_gpu_write, bus_gpu_dataRead => bus_gpu_dataRead, bus_gpu_stall => '0',
         bus_mdec_addr => bus_mdec_addr, bus_mdec_dataWrite => bus_mdec_dataWrite, bus_mdec_read => bus_mdec_read, bus_mdec_write => bus_mdec_write, bus_mdec_dataRead => bus_mdec_dataRead,
         spu_memctrl => spu_memctrl, bus_spu_addr => bus_spu_addr, bus_spu_dataWrite => bus_spu_dataWrite, bus_spu_read => bus_spu_read, bus_spu_write => bus_spu_write, bus_spu_dataRead => bus_spu_dataRead,
         ex2_memctrl => ex2_memctrl, bus_exp2_addr => bus_exp2_addr, bus_exp2_dataWrite => bus_exp2_dataWrite, bus_exp2_read => bus_exp2_read, bus_exp2_write => bus_exp2_write, bus_exp2_dataRead => bus_exp2_dataRead,
         ex3_memctrl => ex3_memctrl, bus_exp3_read => bus_exp3_read, bus_exp3_dataRead => bus_exp3_dataRead,
         com0_delay => com0_delay, com1_delay => com1_delay, com2_delay => com2_delay, com3_delay => com3_delay,
         loading_savestate => '0', SS_reset => '0', SS_DataWrite => (others => '0'), SS_Adr => (others => '0'),
         SS_wren_SDRam => '0', SS_rden_SDRam => '0',
         zn_req => zn_req, zn_we => zn_we, zn_addr => zn_addr, zn_be => zn_be, zn_wdata => zn_wdata,
         zn_ack => zn_ack, zn_rdata => zn_rdata
      );
   end generate;

   gnew : if VARIANT = 1 or VARIANT = 2 generate
      i : entity work.memorymux
      generic map (ZN2_MAP => VARIANT - 1, ZN2_READ_OVERLAP => OVERLAP)
      port map (
         clk1x => clk1x, clk2x => clk2x, ce => ce, reset => reset,
         pauseNext => '0', isIdle => isIdle_i,
         loadExe => '0', exe_initial_pc => (others => '0'), exe_initial_gp => (others => '0'),
         exe_load_address => (others => '0'), exe_file_size => (others => '0'), exe_stackpointer => (others => '0'),
         reset_exe => reset_exe, fastboot => '0', PATCHSERIAL => '0', TURBO => '0', region_in => "00",
         ram_dataWrite => ram_dataWrite, ram_dataRead => ram_dataRead, ram_Adr => ram_Adr, ram_be => ram_be,
         ram_rnw => ram_rnw, ram_ena => ram_ena, ram_cache => ram_cache, ram_done => ram_done,
         mem_in_request => mem_in_request, mem_in_rnw => mem_in_rnw, mem_in_isData => mem_in_isData,
         mem_in_isCache => mem_in_isCache, mem_in_oldtagvalids => "0000",
         mem_in_addressInstr => mem_in_addressInstr, mem_in_addressData => mem_in_addressData,
         mem_in_reqsize => mem_in_reqsize, mem_in_writeMask => mem_in_writeMask, mem_in_dataWrite => mem_in_dataWrite,
         mem_dataRead => mem_dataRead_i, mem_done => mem_done_i, mem_fifofull => mem_fifofull_i, mem_tagvalids => mem_tagvalids,
         bios_memctrl => bios_memctrl, ex1_memctrl => ex1_memctrl, bus_exp1_read => bus_exp1_read, bus_exp1_dataRead => bus_exp1_dataRead,
         bus_memc_addr => bus_memc_addr, bus_memc_dataWrite => bus_memc_dataWrite, bus_memc_read => bus_memc_read, bus_memc_write => bus_memc_write, bus_memc_dataRead => bus_memc_dataRead,
         bus_pad_addr => bus_pad_addr, bus_pad_dataWrite => bus_pad_dataWrite, bus_pad_read => bus_pad_read, bus_pad_write => bus_pad_write, bus_pad_writeMask => bus_pad_writeMask, bus_pad_dataRead => bus_pad_dataRead,
         bus_sio_addr => bus_sio_addr, bus_sio_dataWrite => bus_sio_dataWrite, bus_sio_read => bus_sio_read, bus_sio_write => bus_sio_write, bus_sio_writeMask => bus_sio_writeMask, bus_sio_dataRead => bus_sio_dataRead,
         bus_memc2_addr => bus_memc2_addr, bus_memc2_dataWrite => bus_memc2_dataWrite, bus_memc2_read => bus_memc2_read, bus_memc2_write => bus_memc2_write, bus_memc2_dataRead => bus_memc2_dataRead,
         bus_irq_addr => bus_irq_addr, bus_irq_dataWrite => bus_irq_dataWrite, bus_irq_read => bus_irq_read, bus_irq_write => bus_irq_write, bus_irq_dataRead => bus_irq_dataRead,
         bus_dma_addr => bus_dma_addr, bus_dma_dataWrite => bus_dma_dataWrite, bus_dma_read => bus_dma_read, bus_dma_write => bus_dma_write, bus_dma_dataRead => bus_dma_dataRead,
         bus_tmr_addr => bus_tmr_addr, bus_tmr_dataWrite => bus_tmr_dataWrite, bus_tmr_read => bus_tmr_read, bus_tmr_write => bus_tmr_write, bus_tmr_dataRead => bus_tmr_dataRead,
         cd_memctrl => cd_memctrl, bus_cd_addr => bus_cd_addr, bus_cd_dataWrite => bus_cd_dataWrite, bus_cd_read => bus_cd_read, bus_cd_write => bus_cd_write, bus_cd_dataRead => bus_cd_dataRead,
         bus_gpu_addr => bus_gpu_addr, bus_gpu_dataWrite => bus_gpu_dataWrite, bus_gpu_read => bus_gpu_read, bus_gpu_write => bus_gpu_write, bus_gpu_dataRead => bus_gpu_dataRead, bus_gpu_stall => '0',
         bus_mdec_addr => bus_mdec_addr, bus_mdec_dataWrite => bus_mdec_dataWrite, bus_mdec_read => bus_mdec_read, bus_mdec_write => bus_mdec_write, bus_mdec_dataRead => bus_mdec_dataRead,
         spu_memctrl => spu_memctrl, bus_spu_addr => bus_spu_addr, bus_spu_dataWrite => bus_spu_dataWrite, bus_spu_read => bus_spu_read, bus_spu_write => bus_spu_write, bus_spu_dataRead => bus_spu_dataRead,
         ex2_memctrl => ex2_memctrl, bus_exp2_addr => bus_exp2_addr, bus_exp2_dataWrite => bus_exp2_dataWrite, bus_exp2_read => bus_exp2_read, bus_exp2_write => bus_exp2_write, bus_exp2_dataRead => bus_exp2_dataRead,
         ex3_memctrl => ex3_memctrl, bus_exp3_read => bus_exp3_read, bus_exp3_dataRead => bus_exp3_dataRead,
         com0_delay => com0_delay, com1_delay => com1_delay, com2_delay => com2_delay, com3_delay => com3_delay,
         loading_savestate => '0', SS_reset => '0', SS_DataWrite => (others => '0'), SS_Adr => (others => '0'),
         SS_wren_SDRam => '0', SS_rden_SDRam => '0',
         zn_req => zn_req, zn_we => zn_we, zn_addr => zn_addr, zn_be => zn_be, zn_wdata => zn_wdata,
         zn_ack => zn_ack, zn_rdata => zn_rdata
      );
   end generate;

   mem_dataRead <= mem_dataRead_i;
   mem_done     <= mem_done_i;
   mem_fifofull <= mem_fifofull_i;
   isIdle       <= isIdle_i;

   -- RAM/BIOS model: 3 cycles, data from the address and the last write
   process (clk1x)
      variable cnt     : integer := 0;
      variable lastw   : std_logic_vector(31 downto 0) := (others => '0');
      variable adr     : std_logic_vector(24 downto 0);
      variable rd      : std_logic;
   begin
      if rising_edge(clk1x) then
         ram_done <= '0';
         if (ram_ena = '1') then
            cnt := 3; adr := ram_Adr; rd := ram_rnw;
            if (ram_rnw = '0') then lastw := ram_dataWrite; end if;
         elsif (cnt > 0) then
            cnt := cnt - 1;
            if (cnt = 0) then
               ram_done     <= '1';
               ram_dataRead <= f32(unsigned(adr), 7) xor lastw;
            end if;
         end if;
      end if;
   end process;

   -- bus devices: registered read data, zero when not read (memorymux ORs them)
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         bus_memc_dataRead  <= (others => '0'); bus_pad_dataRead <= (others => '0'); bus_sio_dataRead <= (others => '0');
         bus_memc2_dataRead <= (others => '0'); bus_irq_dataRead <= (others => '0'); bus_dma_dataRead <= (others => '0');
         bus_tmr_dataRead   <= (others => '0'); bus_gpu_dataRead <= (others => '0'); bus_mdec_dataRead <= (others => '0');
         if (bus_memc_read  = '1') then bus_memc_dataRead  <= f32(bus_memc_addr, 1);  end if;
         if (bus_pad_read   = '1') then bus_pad_dataRead   <= f32(bus_pad_addr, 2);   end if;
         if (bus_sio_read   = '1') then bus_sio_dataRead   <= f32(bus_sio_addr, 3);   end if;
         if (bus_memc2_read = '1') then bus_memc2_dataRead <= f32(bus_memc2_addr, 4); end if;
         if (bus_irq_read   = '1') then bus_irq_dataRead   <= f32(bus_irq_addr, 5);   end if;
         if (bus_dma_read   = '1') then bus_dma_dataRead   <= f32(bus_dma_addr, 6);   end if;
         if (bus_tmr_read   = '1') then bus_tmr_dataRead   <= f32(bus_tmr_addr, 8);   end if;
         if (bus_gpu_read   = '1') then bus_gpu_dataRead   <= f32(bus_gpu_addr, 9);   end if;
         if (bus_mdec_read  = '1') then bus_mdec_dataRead  <= f32(bus_mdec_addr, 10); end if;
         if (bus_spu_read   = '1') then bus_spu_dataRead   <= f32(bus_spu_addr, 11)(15 downto 0); end if;
         if (bus_cd_read    = '1') then bus_cd_dataRead    <= f32(bus_cd_addr, 12)(7 downto 0); end if;
         if (bus_exp2_read  = '1') then bus_exp2_dataRead  <= f32(bus_exp2_addr, 13)(7 downto 0); end if;
         if (bus_exp1_read  = '1') then bus_exp1_dataRead  <= f32(to_unsigned(1, 4), 14)(7 downto 0); end if;
         if (bus_exp3_read  = '1') then bus_exp3_dataRead  <= f32(to_unsigned(1, 4), 15)(15 downto 0); end if;
      end if;
   end process;

   -- ZN bus device: 64 KB of bytes at zn_addr(15 downto 0) + lane, latency
   -- 1 to 13 cycles (LFSR); a request while busy is an error
   process (clk1x)
      variable lfsr    : unsigned(15 downto 0) := to_unsigned(16#ACE1# + SEED, 16);
      variable cnt     : integer := 0;
      variable busy    : boolean := false;
      variable q_we    : std_logic;
      variable q_addr  : unsigned(23 downto 0);
      variable q_be    : std_logic_vector(3 downto 0);
      variable q_data  : std_logic_vector(31 downto 0);
      variable a       : integer;
      variable r       : std_logic_vector(31 downto 0);
   begin
      if rising_edge(clk1x) then
         zn_ack       <= '0';
         zn_log_valid <= '0';
         if (zn_req = '1') then
            assert not busy report "zn_req while the device is busy" severity failure;
            busy := true;
            lfsr := lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
            cnt  := 1 + to_integer(lfsr(3 downto 0)) mod 13;
            if (FIXED_LAT > 0) then cnt := FIXED_LAT; end if;
            q_we := zn_we; q_addr := zn_addr; q_be := zn_be; q_data := zn_wdata;
            zn_log_valid <= '1'; zn_log_we <= zn_we; zn_log_addr <= zn_addr; zn_log_be <= zn_be; zn_log_data <= zn_wdata;
            assert zn_addr(1 downto 0) = "00" report "zn_addr not word aligned" severity failure;
            assert zn_be /= "0000" report "zn request without byte enables" severity failure;
         elsif busy then
            cnt := cnt - 1;
            if (cnt = 0) then
               busy := false;
               r := (others => '0');
               for b in 0 to 3 loop
                  a := to_integer(q_addr(15 downto 2)) * 4 + b;
                  if (q_be(b) = '1') then
                     if (q_we = '1') then
                        dev(a) <= q_data(8*b+7 downto 8*b);
                     else
                        r(8*b+7 downto 8*b) := dev(a);
                     end if;
                  end if;
               end loop;
               zn_rdata <= r;
               zn_ack   <= '1';
            end if;
         end if;
      end if;
   end process;

   zn_dev_peek <= dev(to_integer(zn_dev_peek_addr));

   process (all)
      variable v : std_logic_vector(511 downto 0);
      variable p, pr, pz : integer;
      procedure put(x : std_logic_vector) is
         variable t : std_logic_vector(x'length - 1 downto 0);
      begin
         t := x;
         v(p + x'length - 1 downto p) := t;
         p := p + x'length;
      end procedure;
      procedure put1(x : std_logic) is
      begin
         v(p) := x;
         p := p + 1;
      end procedure;
   begin
      v := (others => '0');
      p := 0;
      put(ram_dataWrite); put(ram_Adr); put(ram_be); put1(ram_rnw); put1(ram_ena); put1(ram_cache); put1(reset_exe);
      pr := p;
      put(mem_dataRead_i); put1(mem_done_i); put1(mem_fifofull_i); put(mem_tagvalids); put1(isIdle_i);
      put1(bus_exp1_read); put(std_logic_vector(bus_memc_addr)); put(bus_memc_dataWrite); put1(bus_memc_read); put1(bus_memc_write);
      put(std_logic_vector(bus_pad_addr)); put1(bus_pad_read); put1(bus_pad_write); put(bus_pad_writeMask); put(bus_pad_dataWrite);
      put(std_logic_vector(bus_sio_addr)); put1(bus_sio_read); put1(bus_sio_write); put(bus_sio_writeMask);
      put(std_logic_vector(bus_memc2_addr)); put1(bus_memc2_read); put1(bus_memc2_write);
      put(std_logic_vector(bus_irq_addr)); put1(bus_irq_read); put1(bus_irq_write);
      put(std_logic_vector(bus_dma_addr)); put1(bus_dma_read); put1(bus_dma_write);
      put(std_logic_vector(bus_tmr_addr)); put1(bus_tmr_read); put1(bus_tmr_write);
      put(std_logic_vector(bus_cd_addr)); put(bus_cd_dataWrite); put1(bus_cd_read); put1(bus_cd_write);
      put(std_logic_vector(bus_gpu_addr)); put1(bus_gpu_read); put1(bus_gpu_write);
      put(std_logic_vector(bus_mdec_addr)); put1(bus_mdec_read); put1(bus_mdec_write);
      put(std_logic_vector(bus_spu_addr)); put(bus_spu_dataWrite); put1(bus_spu_read); put1(bus_spu_write);
      put(std_logic_vector(bus_exp2_addr)); put(bus_exp2_dataWrite); put1(bus_exp2_read); put1(bus_exp2_write);
      put1(bus_exp3_read);
      put1(zn_req); put1(zn_we); pz := p; put(std_logic_vector(zn_addr)); put(zn_be); put(zn_wdata);
      obs <= v;
      v(pr + 31 downto pr) := (others => '0');
      v(pz + 23 downto pz) := (others => '0');
      obs_core <= v;
   end process;

end architecture;
