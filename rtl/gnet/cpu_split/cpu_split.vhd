-- Crossing layer between the CPU group (clk_cpu, clk_cpu2x) and the PS1 group
-- (clk1x, clk2x) for psx_top's CPU_CLK_SPLIT = 1 (docs/r1_cpu_domain_design.md,
-- "Plan for exactly 50.000 MHz", P2 and P3, and the section on this step).
-- Instantiated only by psx_top when CPU_CLK_SPLIT = 1; every signal name
-- prefixed c_ is in the CPU group, p_ in the PS1 group (clk1x unless noted).
--
--   C1 to C5   cpu_gpu_bridge
--   C6         irq_GPU: rising edge on clk2x, cdc_pulse
--   C7         irq_VBLANK: level, cdc_sync
--   C8 to C11  cpu_spu_bridge
--   C12        irq_SPU: rising edge on clk1x, cdc_pulse
--   C13, C14   hblank_tmr, vblank_tmr: levels (gpu.vhd's clk1x copies), cdc_sync
--   C15        dotclock: rising edge of gpu.vhd's clk1x copy, cdc_pulse
--   C16        ce, pausing, pausingSS, cpuPaused, dmaOn, DMA_GPU_waiting to
--              the PS1 group; allowunpause and the GPU/SPU idle flags back
--   C17        top-level reset and pause into the CPU group, reset_exe out,
--              the engine's reset pulses in (cpu_reset_fill), the zero fill
--   C20        error flags both ways (debug overlay)
--   P3         tick_accum: 33.8688 MHz-equivalent sys_tick on clk_cpu
--   index      clk2xIndex and clk3xIndex for the GTE and the DMA FIFO,
--              generated from clk_cpu / clk_cpu2x as psx_top does from
--              clk1x / clk2x / clk3x
-- Not crossed here: quasi-static configuration from PSX.sv (false paths in
-- the revision SDC) and everything that only exists with HAS_CD, HAS_PADS,
-- HAS_CHEATS, HAS_MDEC or HAS_SAVESTATES = 1 (psx_top rejects those with
-- CPU_CLK_SPLIT = 1).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cdc_pkg.all;

entity cpu_split is
   generic (
      FASTSIM         : std_logic := '0';
      CLK_FAST_RATIO  : integer   := 2;
      FILL_RAM_WORDS  : positive  := 524288;  -- main RAM words zeroed at reset (2 MB)
      SIM_META_WINDOW : time      := 0 ns
   );
   port (
      clk_cpu              : in  std_logic;
      clk_cpu2x            : in  std_logic;
      clk1x                : in  std_logic;
      clk2x                : in  std_logic;

      -- top-level inputs (PSX.sv, clk_1x)
      reset_top            : in  std_logic;
      pause_top            : in  std_logic;
      loadExe_top          : in  std_logic;
      c_reset              : out std_logic;
      c_pause              : out std_logic;
      c_loadExe            : out std_logic;
      c_reset_in           : out std_logic;
      p_reset_top          : out std_logic;

      -- reset sequence
      c_reset_exe          : in  std_logic;
      p_reset_exe          : out std_logic;
      p_SS_reset           : in  std_logic;
      p_reset_intern       : in  std_logic;
      c_SS_reset           : out std_logic;
      c_reset_intern       : out std_logic;
      p_savestate_pause    : in  std_logic;
      c_savestate_pause    : out std_logic;
      p_loading_savestate  : in  std_logic;
      c_loading_savestate  : out std_logic;
      p_fill_req           : in  std_logic;   -- clk2x (engine state machine)
      p_fill_done          : out std_logic;
      c_SS_wren            : out std_logic_vector(16 downto 0);
      c_SS_Adr             : out unsigned(18 downto 0);
      c_SS_DataWrite       : out std_logic_vector(31 downto 0);
      c_ram_done           : in  std_logic;

      -- run state CPU -> PS1
      c_ce                 : in  std_logic;
      c_pausing            : in  std_logic;
      c_pausingSS          : in  std_logic;
      c_cpuPaused          : in  std_logic;
      c_dmaOn              : in  std_logic;
      c_DMA_GPU_waiting    : in  std_logic;
      c_cpu_idle           : in  std_logic;
      p_ce                 : out std_logic;
      p_pausing            : out std_logic;
      p_pausingSS          : out std_logic;
      p_cpuPaused          : out std_logic;
      p_dmaOn              : out std_logic;
      p_DMA_GPU_waiting    : out std_logic;
      p_cpu_idle           : out std_logic;
      -- PS1 -> CPU
      p_allowunpause       : in  std_logic;
      p_gpu_idle           : in  std_logic;
      p_spu_idle           : in  std_logic;
      c_allowunpause       : out std_logic;
      c_gpu_idle           : out std_logic;
      c_spu_idle           : out std_logic;

      -- errors (debug overlay)
      p_err                : in  std_logic_vector(6 downto 0);  -- LINE RECT POLY GPU MASK GPUFIFO SPUTIME
      c_err                : out std_logic_vector(6 downto 0);
      c_err_disp           : in  std_logic_vector(5 downto 0);  -- errorEna, errorCode, debugmodeOn
      p_err_disp           : out std_logic_vector(5 downto 0);

      -- video timing and interrupts
      p_hblank_tmr         : in  std_logic;
      p_vblank_tmr         : in  std_logic;
      p_dotclock           : in  std_logic;
      p_irq_VBLANK         : in  std_logic;
      p_irq_GPU            : in  std_logic;   -- clk2x
      p_irq_SPU            : in  std_logic;
      c_hblank_tmr         : out std_logic;
      c_vblank_tmr         : out std_logic;
      c_dotclock           : out std_logic;
      c_irq_VBLANK         : out std_logic;
      c_irq_GPU            : out std_logic;
      c_irq_SPU            : out std_logic;

      -- CPU group timing
      c_sys_tick           : out std_logic;
      c_clk2xIndex         : out std_logic;   -- clk_cpu2x
      c_clk3xIndex         : out std_logic;   -- clk_cpu2x

      -- GPU
      c_bus_gpu_addr       : in  unsigned(3 downto 0);
      c_bus_gpu_dataWrite  : in  std_logic_vector(31 downto 0);
      c_bus_gpu_read       : in  std_logic;
      c_bus_gpu_write      : in  std_logic;
      c_bus_gpu_dataRead   : out std_logic_vector(31 downto 0);
      c_bus_gpu_stall      : out std_logic;
      c_DMA_GPU_writeEna   : in  std_logic;
      c_DMA_GPU_write      : in  std_logic_vector(31 downto 0);
      c_DMA_GPU_readEna    : in  std_logic;
      c_DMA_GPU_read       : out std_logic_vector(31 downto 0);
      c_gpu_dmaRequest     : out std_logic;
      p_bus_gpu_addr       : out unsigned(3 downto 0);
      p_bus_gpu_dataWrite  : out std_logic_vector(31 downto 0);
      p_bus_gpu_read       : out std_logic;
      p_bus_gpu_write      : out std_logic;
      p_bus_gpu_dataRead   : in  std_logic_vector(31 downto 0);
      p_bus_gpu_stall      : in  std_logic;
      p_DMA_GPU_writeEna   : out std_logic;
      p_DMA_GPU_write      : out std_logic_vector(31 downto 0);
      p_DMA_GPU_readEna    : out std_logic;
      p_DMA_GPU_read       : in  std_logic_vector(31 downto 0);
      p_gpu_dmaRequest     : in  std_logic;

      -- SPU
      c_bus_spu_addr       : in  unsigned(9 downto 0);
      c_bus_spu_dataWrite  : in  std_logic_vector(15 downto 0);
      c_bus_spu_read       : in  std_logic;
      c_bus_spu_write      : in  std_logic;
      c_bus_spu_dataRead   : out std_logic_vector(15 downto 0);
      c_bus_spu_stall      : out std_logic;
      c_DMA_SPU_writeEna   : in  std_logic;
      c_DMA_SPU_write      : in  std_logic_vector(15 downto 0);
      c_DMA_SPU_readReq    : in  std_logic;
      c_DMA_SPU_readEna    : in  std_logic;
      c_DMA_SPU_readStall  : out std_logic;
      c_DMA_SPU_read       : out std_logic_vector(15 downto 0);
      c_spu_dmaRequest     : out std_logic;
      p_bus_spu_addr       : out unsigned(9 downto 0);
      p_bus_spu_dataWrite  : out std_logic_vector(15 downto 0);
      p_bus_spu_read       : out std_logic;
      p_bus_spu_write      : out std_logic;
      p_bus_spu_dataRead   : in  std_logic_vector(15 downto 0);
      p_DMA_SPU_writeEna   : out std_logic;
      p_DMA_SPU_write      : out std_logic_vector(15 downto 0);
      p_DMA_SPU_readEna    : out std_logic;
      p_DMA_SPU_read       : in  std_logic_vector(15 downto 0);
      p_spu_dmaRequest     : in  std_logic
   );
end entity;

architecture rtl of cpu_split is

   -- PS1-side registers whose outputs cross (cdc_tx_*, cdc.sdc)
   signal cdc_tx_top     : std_logic_vector(1 downto 0) := (others => '0');  -- reset, pause
   signal cdc_tx_p_lvl   : std_logic_vector(14 downto 0) := (others => '0');
   signal cdc_tx_c_lvl   : std_logic_vector(7 downto 0) := (others => '0');
   signal cdc_tx_disp    : std_logic_vector(5 downto 0) := (others => '0');
   signal cdc_tx_fillreq : std_logic := '0';   -- clk2x copy of the engine's toggle
   signal cdc_tx_filldone : std_logic := '0';  -- clk_cpu copy of the filler's toggle
   attribute altera_attribute : string;
   attribute altera_attribute of cdc_tx_top   : signal is CDC_ATTR_KEEP;
   attribute altera_attribute of cdc_tx_p_lvl : signal is CDC_ATTR_KEEP;
   attribute altera_attribute of cdc_tx_c_lvl : signal is CDC_ATTR_KEEP;
   attribute altera_attribute of cdc_tx_disp  : signal is CDC_ATTR_KEEP;
   attribute altera_attribute of cdc_tx_fillreq  : signal is CDC_ATTR_KEEP;
   attribute altera_attribute of cdc_tx_filldone : signal is CDC_ATTR_KEEP;

   signal top_s          : std_logic_vector(1 downto 0);
   signal p_lvl_s        : std_logic_vector(14 downto 0);
   signal c_lvl_s        : std_logic_vector(7 downto 0);
   signal fill_req_s     : std_logic_vector(0 downto 0);
   signal fill_done_t    : std_logic;
   signal fill_done_s    : std_logic_vector(0 downto 0);
   signal fill_busy      : std_logic;

   signal c_reset_i      : std_logic;
   signal c_reset_in_r   : std_logic := '0';
   signal ss_pulse_c     : std_logic;
   signal rst_pulse_c    : std_logic;
   signal ss_wr_scp      : std_logic;
   signal ss_wr_ram      : std_logic;
   signal c_reset_intern_i : std_logic;

   signal irq_gpu_d      : std_logic := '0';
   signal irq_gpu_edge   : std_logic;
   signal irq_spu_d      : std_logic := '0';
   signal irq_spu_edge   : std_logic;
   signal dot_d          : std_logic := '0';
   signal dot_edge       : std_logic;

   signal gpu_c_idle     : std_logic;
   signal gpu_p_idle     : std_logic;
   signal spu_c_idle     : std_logic;
   signal spu_p_idle     : std_logic;
   signal gpu_ovf        : std_logic;
   signal spu_ovf        : std_logic;

   -- CPU-group index generators
   signal tog_c          : std_logic := '0';
   signal tog_2          : std_logic := '0';
   signal tog_3          : std_logic := '0';
   signal tog_3_1        : std_logic := '0';
   signal idx2           : std_logic := '0';
   signal idx3           : std_logic := '0';

begin

   assert CLK_FAST_RATIO = 2 or CLK_FAST_RATIO = 3
      report "cpu_split: CLK_FAST_RATIO must be 2 or 3" severity failure;

   ------------------------------------------------------- top-level inputs
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         cdc_tx_top <= pause_top & reset_top;
      end if;
   end process;
   p_reset_top <= cdc_tx_top(0);

   u_top : entity work.cdc_sync
      generic map (WIDTH => 2, INIT => '1', SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 101)
      port map (clk => clk_cpu, d => cdc_tx_top, q => top_s);
   c_reset_i <= top_s(0);
   c_reset   <= c_reset_i;
   c_pause   <= top_s(1);

   u_loadexe : entity work.cdc_pulse
      generic map (CNT_W => 1, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 103)
      port map (src_clk => clk1x, src_pulse => loadExe_top, dst_clk => clk_cpu, dst_pulse => c_loadExe);

   -- psx_top's reset_in, CPU-side copy (clears pausing in the ce process)
   process (clk_cpu)
   begin
      if rising_edge(clk_cpu) then
         c_reset_in_r <= c_reset_i or c_reset_exe;
      end if;
   end process;
   c_reset_in <= c_reset_in_r;

   u_resetexe : entity work.cdc_pulse
      generic map (CNT_W => 1, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 105)
      port map (src_clk => clk_cpu, src_pulse => c_reset_exe, dst_clk => clk1x, dst_pulse => p_reset_exe);

   ------------------------------------------------------- reset sequence
   u_sspulse : entity work.cdc_pulse
      generic map (CNT_W => 2, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 107)
      port map (src_clk => clk1x, src_pulse => p_SS_reset, dst_clk => clk_cpu, dst_pulse => ss_pulse_c);

   u_rstpulse : entity work.cdc_pulse
      generic map (CNT_W => 2, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 109)
      port map (src_clk => clk1x, src_pulse => p_reset_intern, dst_clk => clk_cpu, dst_pulse => rst_pulse_c);

   -- the fill toggles cross from cdc_tx_* registers, so cdc.sdc bounds them
   -- (the engine's and the filler's own registers have other names)
   process (clk2x)
   begin
      if rising_edge(clk2x) then
         cdc_tx_fillreq <= p_fill_req;
      end if;
   end process;

   process (clk_cpu)
   begin
      if rising_edge(clk_cpu) then
         cdc_tx_filldone <= fill_done_t;
      end if;
   end process;

   u_fillreq : entity work.cdc_sync
      generic map (WIDTH => 1, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 111)
      port map (clk => clk_cpu, d(0) => cdc_tx_fillreq, q => fill_req_s);

   u_fill : entity work.cpu_reset_fill
      generic map (FASTSIM => FASTSIM, RAM_WORDS => FILL_RAM_WORDS)
      port map (
         clk          => clk_cpu,
         rst          => c_reset_i,
         ss_pulse     => ss_pulse_c,
         rst_pulse    => rst_pulse_c,
         SS_reset     => c_SS_reset,
         reset_intern => c_reset_intern_i,
         ce           => c_ce,
         fill_req     => fill_req_s(0),
         fill_done    => fill_done_t,
         ram_done     => c_ram_done,
         ss_wr_scp    => ss_wr_scp,
         ss_wr_ram    => ss_wr_ram,
         SS_Adr       => c_SS_Adr,
         SS_DataWrite => c_SS_DataWrite,
         busy         => fill_busy);
   c_reset_intern <= c_reset_intern_i;

   c_SS_wren <= ss_wr_ram & "000" & ss_wr_scp & "000000000000";

   u_filldone : entity work.cdc_sync
      generic map (WIDTH => 1, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 113)
      port map (clk => clk2x, d(0) => cdc_tx_filldone, q => fill_done_s);
   p_fill_done <= fill_done_s(0);

   ----------------------------------------------------------- levels
   -- PS1 -> CPU: registered on clk1x first, so every crossing starts at a
   -- register (some sources are combinational inside gpu.vhd and spu.vhd)
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         cdc_tx_p_lvl <= p_savestate_pause & p_loading_savestate & p_allowunpause &
                         (p_gpu_idle and gpu_p_idle) & (p_spu_idle and spu_p_idle) &
                         p_hblank_tmr & p_vblank_tmr & p_irq_VBLANK & p_err;
      end if;
   end process;

   u_p2c : entity work.cdc_sync
      generic map (WIDTH => 15, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 115)
      port map (clk => clk_cpu, d => cdc_tx_p_lvl, q => p_lvl_s);

   c_savestate_pause   <= p_lvl_s(14);
   c_loading_savestate <= p_lvl_s(13);
   c_allowunpause      <= p_lvl_s(12);
   c_gpu_idle          <= p_lvl_s(11) and gpu_c_idle;
   c_spu_idle          <= p_lvl_s(10) and spu_c_idle;
   c_hblank_tmr        <= p_lvl_s(9);
   c_vblank_tmr        <= p_lvl_s(8);
   c_irq_VBLANK        <= p_lvl_s(7);
   -- error flags only light the debug overlay (off in G-NET builds); a
   -- one-cycle error pulse can be missed. Bridge overflows count as GPUFIFO.
   c_err <= p_lvl_s(6 downto 2) & (p_lvl_s(1) or gpu_ovf or spu_ovf) & p_lvl_s(0);

   -- CPU -> PS1
   process (clk_cpu)
   begin
      if rising_edge(clk_cpu) then
         cdc_tx_c_lvl <= c_ce & c_pausing & c_pausingSS & c_cpuPaused & c_dmaOn & c_DMA_GPU_waiting &
                         (c_cpu_idle and not fill_busy) & '0';
         cdc_tx_disp  <= c_err_disp;
      end if;
   end process;

   u_c2p : entity work.cdc_sync
      generic map (WIDTH => 8, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 117)
      port map (clk => clk1x, d => cdc_tx_c_lvl, q => c_lvl_s);

   p_ce              <= c_lvl_s(7);
   p_pausing         <= c_lvl_s(6);
   p_pausingSS       <= c_lvl_s(5);
   p_cpuPaused       <= c_lvl_s(4);
   p_dmaOn           <= c_lvl_s(3);
   p_DMA_GPU_waiting <= c_lvl_s(2);
   p_cpu_idle        <= c_lvl_s(1) and gpu_p_idle and spu_p_idle;   -- CPU group idle, nothing queued for the GPU or SPU

   -- error display: changes rarely, must arrive whole
   u_disp : entity work.cdc_bus_sync
      generic map (WIDTH => 6, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 119)
      port map (src_clk => clk_cpu, src_data => cdc_tx_disp, dst_clk => clk1x, dst_data => p_err_disp, dst_update => open);

   ----------------------------------------------------------- pulses
   process (clk2x)
   begin
      if rising_edge(clk2x) then
         irq_gpu_d <= p_irq_GPU;
      end if;
   end process;
   irq_gpu_edge <= p_irq_GPU and not irq_gpu_d;

   u_irqgpu : entity work.cdc_pulse
      generic map (CNT_W => 2, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 121)
      port map (src_clk => clk2x, src_pulse => irq_gpu_edge, dst_clk => clk_cpu, dst_pulse => c_irq_GPU);

   process (clk1x)
   begin
      if rising_edge(clk1x) then
         irq_spu_d <= p_irq_SPU;
         dot_d     <= p_dotclock;
      end if;
   end process;
   irq_spu_edge <= p_irq_SPU and not irq_spu_d;
   dot_edge     <= p_dotclock and not dot_d;

   u_irqspu : entity work.cdc_pulse
      generic map (CNT_W => 2, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 123)
      port map (src_clk => clk1x, src_pulse => irq_spu_edge, dst_clk => clk_cpu, dst_pulse => c_irq_SPU);

   u_dot : entity work.cdc_pulse
      generic map (CNT_W => 2, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => 125)
      port map (src_clk => clk1x, src_pulse => dot_edge, dst_clk => clk_cpu, dst_pulse => c_dotclock);

   ----------------------------------------------------------- P3 tick
   u_tick : entity work.tick_accum
      port map (clk => clk_cpu, rst => c_reset_intern_i, ce => c_ce, tick => c_sys_tick);

   ----------------------------------------------------------- index generators
   -- as psx_top.vhd's clk2xIndex and clk3xIndex, on the CPU clocks
   process (clk_cpu)
   begin
      if rising_edge(clk_cpu) then
         tog_c <= not tog_c;
      end if;
   end process;

   process (clk_cpu2x)
   begin
      if rising_edge(clk_cpu2x) then
         tog_2 <= tog_c;
         idx2  <= '0';
         if tog_2 = tog_c then
            idx2 <= '1';
         end if;
         tog_3   <= tog_c;
         tog_3_1 <= tog_3;
         idx3    <= '0';
         if CLK_FAST_RATIO = 2 then
            if tog_3 = tog_c then
               idx3 <= '1';
            end if;
         elsif tog_3_1 = tog_c then
            idx3 <= '1';
         end if;
      end if;
   end process;
   c_clk2xIndex <= idx2;
   c_clk3xIndex <= idx3;

   ----------------------------------------------------------- bridges
   u_gpu : entity work.cpu_gpu_bridge
      generic map (SIM_META_WINDOW => SIM_META_WINDOW)
      port map (
         c_clk           => clk_cpu,
         c_rst           => c_reset_i,
         c_ce            => c_ce,
         c_bus_addr      => c_bus_gpu_addr,
         c_bus_dataWrite => c_bus_gpu_dataWrite,
         c_bus_read      => c_bus_gpu_read,
         c_bus_write     => c_bus_gpu_write,
         c_bus_dataRead  => c_bus_gpu_dataRead,
         c_bus_stall     => c_bus_gpu_stall,
         c_dma_writeEna  => c_DMA_GPU_writeEna,
         c_dma_write     => c_DMA_GPU_write,
         c_dma_readEna   => c_DMA_GPU_readEna,
         c_dma_read      => c_DMA_GPU_read,
         c_dmaRequest    => c_gpu_dmaRequest,
         c_idle          => gpu_c_idle,
         c_overflow      => gpu_ovf,
         p_clk           => clk1x,
         p_rst           => cdc_tx_top(0),
         p_ce            => c_lvl_s(7),
         p_bus_addr      => p_bus_gpu_addr,
         p_bus_dataWrite => p_bus_gpu_dataWrite,
         p_bus_read      => p_bus_gpu_read,
         p_bus_write     => p_bus_gpu_write,
         p_bus_dataRead  => p_bus_gpu_dataRead,
         p_bus_stall     => p_bus_gpu_stall,
         p_dma_writeEna  => p_DMA_GPU_writeEna,
         p_dma_write     => p_DMA_GPU_write,
         p_dma_readEna   => p_DMA_GPU_readEna,
         p_dma_read      => p_DMA_GPU_read,
         p_dmaRequest    => p_gpu_dmaRequest,
         p_idle          => gpu_p_idle);

   u_spu : entity work.cpu_spu_bridge
      generic map (SIM_META_WINDOW => SIM_META_WINDOW)
      port map (
         c_clk           => clk_cpu,
         c_rst           => c_reset_i,
         c_ce            => c_ce,
         c_bus_addr      => c_bus_spu_addr,
         c_bus_dataWrite => c_bus_spu_dataWrite,
         c_bus_read      => c_bus_spu_read,
         c_bus_write     => c_bus_spu_write,
         c_bus_dataRead  => c_bus_spu_dataRead,
         c_bus_stall     => c_bus_spu_stall,
         c_dma_writeEna  => c_DMA_SPU_writeEna,
         c_dma_write     => c_DMA_SPU_write,
         c_dma_readReq   => c_DMA_SPU_readReq,
         c_dma_readEna   => c_DMA_SPU_readEna,
         c_dma_readStall => c_DMA_SPU_readStall,
         c_dma_read      => c_DMA_SPU_read,
         c_dmaRequest    => c_spu_dmaRequest,
         c_idle          => spu_c_idle,
         c_overflow      => spu_ovf,
         p_clk           => clk1x,
         p_rst           => cdc_tx_top(0),
         p_ce            => c_lvl_s(7),
         p_bus_addr      => p_bus_spu_addr,
         p_bus_dataWrite => p_bus_spu_dataWrite,
         p_bus_read      => p_bus_spu_read,
         p_bus_write     => p_bus_spu_write,
         p_bus_dataRead  => p_bus_spu_dataRead,
         p_dma_writeEna  => p_DMA_SPU_writeEna,
         p_dma_write     => p_DMA_SPU_write,
         p_dma_readEna   => p_DMA_SPU_readEna,
         p_dma_read      => p_DMA_SPU_read,
         p_dmaRequest    => p_spu_dmaRequest,
         p_idle          => spu_p_idle);

end architecture;
