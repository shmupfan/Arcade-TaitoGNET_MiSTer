-- Crossing-level bench for rtl/gnet/cpu_split (docs/r1_cpu_domain_design.md,
-- section on R1 steps 4 and 5). Clocks: clk_cpu 20 ns and clk_cpu2x 10 ns
-- (aligned), clk1x 29.525699 ns and clk2x 14.762850 ns (aligned), the PS1
-- pair started at PHASE after the CPU pair. The CDC entities' metastability
-- model is on (SIM_META_WINDOW), so every synchroniser randomly resolves a
-- cycle late and the FIFO RAM model returns X near a write.
--
-- CPU side models, written after the RTL they stand for:
--   GPU master   memorymux BUSWRITE / BUSREADREQUEST / BUSREAD (stall, data
--                taken on the edge after the stall drops, data 0 otherwise)
--                and dma.vhd channel 2 (writeEna held while ce = '0', reads
--                consumed in a cycle with readEna and gpu_dmaRequest)
--   SPU master   memorymux EXT_WRITE (one-cycle strobe) and EXT_READ_NEXT /
--                EXT_READ (read held while the stall is high, data taken in
--                EXT_READ), dma.vhd channel 4 with the new readStall
--   ce           random pauses of 1 to 40 cycles anywhere
-- PS1 side models: gpu.vhd's bus and DMA behaviour (registered read data,
-- bus_stall while the VRAM read FIFO is empty, writes taken only with ce)
-- and spu.vhd's (register file, registered read data, show-ahead DMA FIFO).
-- Checks: every write arrives once, in order, with the right port and data
-- (GP0, GP1 and DMA words share one sequence); a GPUSTAT read returns the
-- number of writes issued before it (reads see all earlier writes); every
-- GPUREAD and DMA read returns the next VRAM word; every SPU read returns
-- the value last written to that register; SPU DMA words in order both
-- ways; the internal-bus read data is 0 outside the data cycle; interrupt
-- and dot clock pulses: none lost or added; reset pulses: SS_reset always
-- before reset, never in the same cycle; 33.8688 MHz tick count; zero fill:
-- 256 scratchpad and FILL words in address order, one RAM write in flight.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

entity tb_cpu_split is
   generic (
      PHASE  : time     := 7 ns;
      SEED   : positive := 1;
      N_OPS  : positive := 20000;
      WINDOW : time     := 9 ns;
      FILL   : positive := 4096;
      OUTTAG : string   := "run";
      MAXT   : time     := 200 ms    -- watchdog
   );
end entity;

architecture sim of tb_cpu_split is

   constant T_CPU : time := 20 ns;
   constant T_1X  : time := 29525699 fs;

   signal clk_cpu, clk_cpu2x, clk1x, clk2x : std_logic := '0';
   signal done_all : boolean := false;

   -- top level
   signal reset_top, pause_top, loadExe_top : std_logic := '0';
   signal c_reset, c_pause, c_loadExe, c_reset_in : std_logic;
   signal c_reset_exe, p_reset_exe : std_logic := '0';
   signal p_SS_reset, p_reset_intern : std_logic := '0';
   signal c_SS_reset, c_reset_intern : std_logic;
   signal p_savestate_pause, p_loading_savestate : std_logic := '0';
   signal c_savestate_pause, c_loading_savestate : std_logic;
   signal p_fill_req : std_logic := '0';
   signal p_fill_done : std_logic;
   signal c_SS_wren : std_logic_vector(16 downto 0);
   signal c_SS_Adr  : unsigned(18 downto 0);
   signal c_SS_DataWrite : std_logic_vector(31 downto 0);
   signal c_ram_done : std_logic := '0';
   signal c_ce : std_logic := '1';
   signal c_pausing, c_pausingSS, c_cpuPaused, c_dmaOn, c_DMA_GPU_waiting, c_cpu_idle : std_logic := '0';
   signal p_ce, p_pausing, p_pausingSS, p_cpuPaused, p_dmaOn, p_DMA_GPU_waiting, p_cpu_idle : std_logic;
   signal p_allowunpause, p_gpu_idle, p_spu_idle : std_logic := '1';
   signal c_allowunpause, c_gpu_idle, c_spu_idle : std_logic;
   signal p_err : std_logic_vector(6 downto 0) := (others => '0');
   signal c_err : std_logic_vector(6 downto 0);
   signal c_err_disp : std_logic_vector(5 downto 0) := (others => '0');
   signal p_err_disp : std_logic_vector(5 downto 0);
   signal p_hblank_tmr, p_vblank_tmr, p_dotclock, p_irq_VBLANK, p_irq_GPU, p_irq_SPU : std_logic := '0';
   signal c_hblank_tmr, c_vblank_tmr, c_dotclock, c_irq_VBLANK, c_irq_GPU, c_irq_SPU : std_logic;
   signal c_sys_tick, c_clk2xIndex, c_clk3xIndex : std_logic;

   -- GPU
   signal m_gpu_addr : unsigned(3 downto 0) := (others => '0');
   signal m_gpu_data : std_logic_vector(31 downto 0) := (others => '0');
   signal m_gpu_read, m_gpu_write : std_logic := '0';
   signal c_bus_gpu_dataRead : std_logic_vector(31 downto 0);
   signal c_bus_gpu_stall : std_logic;
   signal m_dgpu_wena : std_logic := '0';
   signal m_dgpu_wdata : std_logic_vector(31 downto 0) := (others => '0');
   signal m_dgpu_rena : std_logic := '0';
   signal c_DMA_GPU_read : std_logic_vector(31 downto 0);
   signal c_gpu_dmaRequest : std_logic;
   signal p_bus_gpu_addr : unsigned(3 downto 0);
   signal p_bus_gpu_dataWrite : std_logic_vector(31 downto 0);
   signal p_bus_gpu_read, p_bus_gpu_write : std_logic;
   signal g_dataRead : std_logic_vector(31 downto 0) := (others => '0');
   signal g_stall : std_logic := '0';
   signal p_DMA_GPU_writeEna : std_logic;
   signal p_DMA_GPU_write : std_logic_vector(31 downto 0);
   signal p_DMA_GPU_readEna : std_logic;
   signal g_vseq : unsigned(31 downto 0) := x"10000000";
   signal g_avail : integer := 0;
   signal g_dmaRequest : std_logic;

   -- SPU
   signal m_spu_addr : unsigned(9 downto 0) := (others => '0');
   signal m_spu_data : std_logic_vector(15 downto 0) := (others => '0');
   signal m_spu_read, m_spu_write : std_logic := '0';
   signal c_bus_spu_dataRead : std_logic_vector(15 downto 0);
   signal c_bus_spu_stall : std_logic;
   signal m_dspu_wena : std_logic := '0';
   signal m_dspu_wdata : std_logic_vector(15 downto 0) := (others => '0');
   signal m_dspu_req : std_logic := '0';
   signal m_dspu_rena : std_logic;
   signal c_DMA_SPU_readStall : std_logic;
   signal c_DMA_SPU_read : std_logic_vector(15 downto 0);
   signal c_spu_dmaRequest : std_logic;
   signal p_bus_spu_addr : unsigned(9 downto 0);
   signal p_bus_spu_dataWrite : std_logic_vector(15 downto 0);
   signal p_bus_spu_read, p_bus_spu_write : std_logic;
   signal s_dataRead : std_logic_vector(15 downto 0) := (others => '0');
   signal p_DMA_SPU_writeEna : std_logic;
   signal p_DMA_SPU_write : std_logic_vector(15 downto 0);
   signal p_DMA_SPU_readEna : std_logic;
   signal s_dseq : unsigned(15 downto 0) := x"4000";
   signal s_dmaRequest : std_logic := '0';

   -- bookkeeping
   signal gpu_done, spu_done, pulses_stop, rst_stop : boolean := false;
   signal fill_phase : boolean := false;
   signal hold, gm_idle, sm_idle : boolean := false;
   signal err_gm, err_gp, err_sm, err_sp, err_pl, err_rs, err_fl, err_ck : natural := 0;

   signal n_irqgpu_src, n_irqspu_src, n_dot_src : natural := 0;
   signal n_irqgpu_dst, n_irqspu_dst, n_dot_dst : natural := 0;
   signal n_ss_src, n_rst_src, n_ss_dst, n_rst_dst : natural := 0;
   signal n_gpu_reads, n_gpu_writes, n_gpu_dmaw, n_gpu_dmar : natural := 0;
   signal n_spu_reads, n_spu_writes, n_spu_dmaw, n_spu_dmar : natural := 0;
   signal gpu_rd_lat_min, gpu_rd_lat_max, spu_rd_lat_min, spu_rd_lat_max : natural := 0;
   signal n_scp, n_ram : natural := 0;
   signal ticks_window : natural := 0;

   procedure rnd(variable s1, s2 : inout positive; lo, hi : integer; variable r : out integer) is
      variable u : real;
   begin
      uniform(s1, s2, u);
      r := lo + integer(trunc(u * real(hi - lo + 1)));
      if r > hi then r := hi; end if;
   end procedure;

begin

   ------------------------------------------------------------------ clocks
   clk_cpu2x <= not clk_cpu2x after T_CPU / 4 when not done_all;
   process (clk_cpu2x)
   begin
      if rising_edge(clk_cpu2x) then
         clk_cpu <= not clk_cpu;
      end if;
   end process;

   process
   begin
      wait for PHASE;
      while not done_all loop
         clk2x <= '1'; clk1x <= '1';
         wait for T_1X / 4;
         clk2x <= '0';
         wait for T_1X / 4;
         clk2x <= '1'; clk1x <= '0';
         wait for T_1X / 4;
         clk2x <= '0';
         wait for T_1X / 4;
      end loop;
      wait;
   end process;

   ------------------------------------------------------------------ DUT
   dut : entity work.cpu_split
      generic map (FASTSIM => '0', CLK_FAST_RATIO => 2, FILL_RAM_WORDS => FILL, SIM_META_WINDOW => WINDOW)
      port map (
         clk_cpu => clk_cpu, clk_cpu2x => clk_cpu2x, clk1x => clk1x, clk2x => clk2x,
         reset_top => reset_top, pause_top => pause_top, loadExe_top => loadExe_top,
         c_reset => c_reset, c_pause => c_pause, c_loadExe => c_loadExe, c_reset_in => c_reset_in, p_reset_top => open,
         c_reset_exe => c_reset_exe, p_reset_exe => p_reset_exe,
         p_SS_reset => p_SS_reset, p_reset_intern => p_reset_intern, c_SS_reset => c_SS_reset, c_reset_intern => c_reset_intern,
         p_savestate_pause => p_savestate_pause, c_savestate_pause => c_savestate_pause,
         p_loading_savestate => p_loading_savestate, c_loading_savestate => c_loading_savestate,
         p_fill_req => p_fill_req, p_fill_done => p_fill_done,
         c_SS_wren => c_SS_wren, c_SS_Adr => c_SS_Adr, c_SS_DataWrite => c_SS_DataWrite, c_ram_done => c_ram_done,
         c_ce => c_ce, c_pausing => c_pausing, c_pausingSS => c_pausingSS, c_cpuPaused => c_cpuPaused,
         c_dmaOn => c_dmaOn, c_DMA_GPU_waiting => c_DMA_GPU_waiting, c_cpu_idle => c_cpu_idle,
         p_ce => p_ce, p_pausing => p_pausing, p_pausingSS => p_pausingSS, p_cpuPaused => p_cpuPaused,
         p_dmaOn => p_dmaOn, p_DMA_GPU_waiting => p_DMA_GPU_waiting, p_cpu_idle => p_cpu_idle,
         p_allowunpause => p_allowunpause, p_gpu_idle => p_gpu_idle, p_spu_idle => p_spu_idle,
         c_allowunpause => c_allowunpause, c_gpu_idle => c_gpu_idle, c_spu_idle => c_spu_idle,
         p_err => p_err, c_err => c_err, c_err_disp => c_err_disp, p_err_disp => p_err_disp,
         p_hblank_tmr => p_hblank_tmr, p_vblank_tmr => p_vblank_tmr, p_dotclock => p_dotclock,
         p_irq_VBLANK => p_irq_VBLANK, p_irq_GPU => p_irq_GPU, p_irq_SPU => p_irq_SPU,
         c_hblank_tmr => c_hblank_tmr, c_vblank_tmr => c_vblank_tmr, c_dotclock => c_dotclock,
         c_irq_VBLANK => c_irq_VBLANK, c_irq_GPU => c_irq_GPU, c_irq_SPU => c_irq_SPU,
         c_sys_tick => c_sys_tick, c_clk2xIndex => c_clk2xIndex, c_clk3xIndex => c_clk3xIndex,
         c_bus_gpu_addr => m_gpu_addr, c_bus_gpu_dataWrite => m_gpu_data, c_bus_gpu_read => m_gpu_read,
         c_bus_gpu_write => m_gpu_write, c_bus_gpu_dataRead => c_bus_gpu_dataRead, c_bus_gpu_stall => c_bus_gpu_stall,
         c_DMA_GPU_writeEna => m_dgpu_wena, c_DMA_GPU_write => m_dgpu_wdata, c_DMA_GPU_readEna => m_dgpu_rena,
         c_DMA_GPU_read => c_DMA_GPU_read, c_gpu_dmaRequest => c_gpu_dmaRequest,
         p_bus_gpu_addr => p_bus_gpu_addr, p_bus_gpu_dataWrite => p_bus_gpu_dataWrite, p_bus_gpu_read => p_bus_gpu_read,
         p_bus_gpu_write => p_bus_gpu_write, p_bus_gpu_dataRead => g_dataRead, p_bus_gpu_stall => g_stall,
         p_DMA_GPU_writeEna => p_DMA_GPU_writeEna, p_DMA_GPU_write => p_DMA_GPU_write,
         p_DMA_GPU_readEna => p_DMA_GPU_readEna, p_DMA_GPU_read => std_logic_vector(g_vseq),
         p_gpu_dmaRequest => g_dmaRequest,
         c_bus_spu_addr => m_spu_addr, c_bus_spu_dataWrite => m_spu_data, c_bus_spu_read => m_spu_read,
         c_bus_spu_write => m_spu_write, c_bus_spu_dataRead => c_bus_spu_dataRead, c_bus_spu_stall => c_bus_spu_stall,
         c_DMA_SPU_writeEna => m_dspu_wena, c_DMA_SPU_write => m_dspu_wdata, c_DMA_SPU_readReq => m_dspu_req,
         c_DMA_SPU_readEna => m_dspu_rena, c_DMA_SPU_readStall => c_DMA_SPU_readStall, c_DMA_SPU_read => c_DMA_SPU_read,
         c_spu_dmaRequest => c_spu_dmaRequest,
         p_bus_spu_addr => p_bus_spu_addr, p_bus_spu_dataWrite => p_bus_spu_dataWrite, p_bus_spu_read => p_bus_spu_read,
         p_bus_spu_write => p_bus_spu_write, p_bus_spu_dataRead => s_dataRead,
         p_DMA_SPU_writeEna => p_DMA_SPU_writeEna, p_DMA_SPU_write => p_DMA_SPU_write,
         p_DMA_SPU_readEna => p_DMA_SPU_readEna, p_DMA_SPU_read => std_logic_vector(s_dseq),
         p_spu_dmaRequest => s_dmaRequest);

   g_dmaRequest <= '1' when g_avail > 0 else '0';
   -- dma.vhd: channel 4 read enable gated by the new stall input
   m_dspu_rena  <= m_dspu_req and not c_DMA_SPU_readStall;

   ------------------------------------------------------------------ reset and ce
   process
      variable s1, s2 : positive;
      variable r : integer;
   begin
      s1 := SEED * 7 + 1; s2 := SEED * 13 + 5;
      reset_top <= '1';
      wait for 400 ns;
      wait until rising_edge(clk1x);
      reset_top <= '0';
      -- ce pauses while traffic runs
      wait for 330 us;   -- after the tick window
      -- pause as psx_top's ce process does: only with the buses idle
      -- (memorymux idle, no DMA); posted words may still be in the FIFOs
      while not (gpu_done and spu_done) loop
         rnd(s1, s2, 50, 400, r);
         for i in 1 to r loop
            wait until rising_edge(clk_cpu);
         end loop;
         hold <= true;
         wait until rising_edge(clk_cpu) and gm_idle and sm_idle;
         wait until rising_edge(clk_cpu);
         c_ce <= '0';
         rnd(s1, s2, 1, 40, r);
         for i in 1 to r loop
            wait until rising_edge(clk_cpu);
         end loop;
         c_ce <= '1';
         hold <= false;
      end loop;
      if not fill_phase then
         wait until fill_phase;
      end if;
      wait until rising_edge(clk_cpu);
      c_ce <= '0';
      wait;
   end process;

   -- 33.8688 MHz tick: 10,584 ticks in the first 15,625 CPU cycles
   process
      variable n : natural := 0;
   begin
      wait until reset_top = '0';
      wait until rising_edge(clk_cpu);
      for i in 1 to 15625 loop
         wait until rising_edge(clk_cpu);
         if c_sys_tick = '1' then n := n + 1; end if;
      end loop;
      ticks_window <= n;
      wait;
   end process;

   -- index generators (psx_top semantics at 2:1): sampled at a clk_cpu2x edge
   -- that coincides with a rising clk_cpu edge both are 0, at the edge in
   -- the middle of the clk_cpu cycle both are 1
   process
      variable e : natural := 0;
   begin
      wait until reset_top = '0';
      wait for 1 us;
      while not done_all loop
         wait until rising_edge(clk_cpu2x);
         -- clk_cpu is generated from this edge, so here it still has its old value
         if clk_cpu = '0' and (c_clk2xIndex /= '0' or c_clk3xIndex /= '0') then e := e + 1; end if;
         if clk_cpu = '1' and (c_clk2xIndex /= '1' or c_clk3xIndex /= '1') then e := e + 1; end if;
         err_ck <= e;
      end loop;
      wait;
   end process;

   ------------------------------------------------------------------ GPU master (CPU side)
   process
      type tst is (IDLE, BUSWRITE, BUSREADREQ, BUSREAD, DMAW, DMAR);
      variable st : tst := IDLE;
      variable s1, s2 : positive;
      variable r, n, gap : integer := 0;
      variable serial : natural := 0;        -- writes issued (GP0, GP1, DMA)
      variable exp_seq : unsigned(31 downto 0) := x"10000000";
      variable exp_rd : std_logic_vector(31 downto 0);
      variable rd_addr0 : boolean;
      variable ops, e : natural := 0;
      variable t0 : time;
      variable lat, lmin, lmax : natural := 0;
      variable prev_idle : boolean := true;
      variable nr, nw, ndw, ndr : natural := 0;
   begin
      s1 := SEED * 31 + 3; s2 := SEED * 17 + 11;
      lmin := 1000000;
      wait until reset_top = '0';
      wait for 2 us;
      while ops < N_OPS or st /= IDLE loop
         wait until rising_edge(clk_cpu);
         if c_ce = '1' then
            -- the internal bus is an OR of all devices: 0 outside the data cycle
            if prev_idle and unsigned(c_bus_gpu_dataRead) /= 0 then
               e := e + 1;
               report "GPU: bus data not 0 outside a read" severity error;
            end if;
            prev_idle := (st /= BUSREAD);
            case st is
               when IDLE =>
                  if hold then
                     null;
                  elsif gap > 0 then
                     gap := gap - 1;
                  elsif ops < N_OPS then
                     ops := ops + 1;
                     rnd(s1, s2, 0, 99, r);
                     if r < 40 then
                        rnd(s1, s2, 0, 1, n);
                        m_gpu_write <= '1';
                        if n = 0 then
                           m_gpu_addr <= x"0";
                           m_gpu_data <= "00" & "000000" & std_logic_vector(to_unsigned(serial mod 2**24, 24));
                        else
                           m_gpu_addr <= x"4";
                           m_gpu_data <= "01" & "000000" & std_logic_vector(to_unsigned(serial mod 2**24, 24));
                        end if;
                        serial := serial + 1; nw := nw + 1;
                        st := BUSWRITE;
                     elsif r < 70 then
                        rnd(s1, s2, 0, 1, n);
                        m_gpu_read <= '1';
                        if n = 0 then
                           m_gpu_addr <= x"4";
                           rd_addr0 := false;
                           exp_rd := std_logic_vector(to_unsigned(serial, 32));
                        else
                           m_gpu_addr <= x"0";
                           rd_addr0 := true;
                           exp_rd := std_logic_vector(exp_seq);
                        end if;
                        t0 := now; nr := nr + 1;
                        st := BUSREADREQ;
                     elsif r < 85 then
                        -- a block starts on the GPU's request (sync mode)
                        rnd(s1, s2, 1, 64, n);
                        if c_gpu_dmaRequest = '0' then n := 0; ops := ops - 1; end if;
                        st := DMAW;
                     else
                        rnd(s1, s2, 1, 24, n);
                        m_dgpu_rena <= '1';
                        st := DMAR;
                     end if;
                     rnd(s1, s2, 0, 6, gap);
                  end if;

               when BUSWRITE =>
                  m_gpu_write <= '0';
                  st := IDLE;

               when BUSREADREQ =>
                  m_gpu_read <= '0';
                  st := BUSREAD;

               when BUSREAD =>
                  if c_bus_gpu_stall = '0' then
                     if c_bus_gpu_dataRead /= exp_rd then
                        e := e + 1;
                        report "GPU read: got " & to_hstring(c_bus_gpu_dataRead) & " expected " & to_hstring(exp_rd) severity error;
                     end if;
                     if rd_addr0 then exp_seq := exp_seq + 1; end if;
                     lat := (now - t0) / T_CPU;
                     if lat < lmin then lmin := lat; end if;
                     if lat > lmax then lmax := lat; end if;
                     st := IDLE;
                  end if;

               when DMAW =>
                  rnd(s1, s2, 0, 3, r);
                  if n > 0 then   -- one word per cycle (harder than dma.vhd's rate)
                     m_dgpu_wena  <= '1';
                     m_dgpu_wdata <= "10" & "000000" & std_logic_vector(to_unsigned(serial mod 2**24, 24));
                     serial := serial + 1; n := n - 1; ndw := ndw + 1;
                  else
                     m_dgpu_wena <= '0';
                     if n = 0 then st := IDLE; end if;
                  end if;

               when DMAR =>
                  -- dma.vhd consumes in a cycle with readEna and gpu_dmaRequest
                  if m_dgpu_rena = '1' and c_gpu_dmaRequest = '1' then
                     if c_DMA_GPU_read /= std_logic_vector(exp_seq) then
                        e := e + 1;
                        report "GPU DMA read: got " & to_hstring(c_DMA_GPU_read) & " expected " & to_hstring(exp_seq) severity error;
                     end if;
                     exp_seq := exp_seq + 1; n := n - 1; ndr := ndr + 1;
                  end if;
                  rnd(s1, s2, 0, 9, r);
                  if n = 0 then
                     m_dgpu_rena <= '0';
                     st := IDLE;
                  elsif r = 0 then
                     m_dgpu_rena <= '0';   -- output FIFO near full for a cycle
                  else
                     m_dgpu_rena <= '1';
                  end if;
            end case;
         end if;
         gm_idle <= (st = IDLE) and m_gpu_write = '0';
      end loop;
      gm_idle <= true;
      err_gm <= e;
      n_gpu_reads <= nr; n_gpu_writes <= nw; n_gpu_dmaw <= ndw; n_gpu_dmar <= ndr;
      gpu_rd_lat_min <= lmin; gpu_rd_lat_max <= lmax;
      for i in 1 to 200 loop wait until rising_edge(clk_cpu); end loop;
      gpu_done <= true;
      wait;
   end process;

   ------------------------------------------------------------------ GPU model (PS1 side)
   process (clk1x)
      variable rcv : natural := 0;
      variable e : natural := 0;
      variable s1 : positive := SEED * 3 + 7;
      variable s2 : positive := SEED * 5 + 9;
      variable r : integer;
      variable pend : boolean := false;
      variable nr : integer := 0;          -- not-ready cycles left (vram2cpu_Fifo_ready = '0')
      variable avail : integer := 0;
      variable vseq : unsigned(31 downto 0) := x"10000000";
      variable ty : std_logic_vector(1 downto 0);
   begin
      if rising_edge(clk1x) then
         -- VRAM read FIFO fills at random
         rnd(s1, s2, 0, 3, r);
         if r = 0 and avail < 40 then avail := avail + 1; end if;

         if (p_bus_gpu_write = '1' or p_DMA_GPU_writeEna = '1' or p_bus_gpu_read = '1' or p_DMA_GPU_readEna = '1') and p_ce /= '1' then
            e := e + 1;
            report "GPU side: command without ce" severity error;
         end if;
         if p_DMA_GPU_readEna = '1' then
            if avail = 0 then
               e := e + 1;
               report "GPU side: DMA read with empty FIFO" severity error;
            else
               avail := avail - 1; vseq := vseq + 1;
            end if;
         end if;
         if p_ce = '1' then
            g_dataRead <= (others => '0');
            if p_bus_gpu_write = '1' then
               if p_bus_gpu_addr = 0 then ty := "00"; elsif p_bus_gpu_addr = 4 then ty := "01"; else ty := "11"; end if;
               if p_bus_gpu_dataWrite /= ty & "000000" & std_logic_vector(to_unsigned(rcv mod 2**24, 24)) then
                  e := e + 1;
                  report "GPU side: write " & to_hstring(p_bus_gpu_dataWrite) & " at " & integer'image(rcv) severity error;
               end if;
               rcv := rcv + 1;
            end if;
            if p_DMA_GPU_writeEna = '1' then
               if p_DMA_GPU_write /= "10" & "000000" & std_logic_vector(to_unsigned(rcv mod 2**24, 24)) then
                  e := e + 1;
                  report "GPU side: DMA word " & to_hstring(p_DMA_GPU_write) & " at " & integer'image(rcv) severity error;
               end if;
               rcv := rcv + 1;
            end if;
            if p_bus_gpu_read = '1' then
               if p_bus_gpu_addr = 4 then
                  g_dataRead <= std_logic_vector(to_unsigned(rcv, 32));
               else
                  rnd(s1, s2, 0, 1, r);
                  if avail > 0 and r = 0 then
                     g_dataRead <= std_logic_vector(vseq);
                     vseq := vseq + 1; avail := avail - 1;
                  else
                     rnd(s1, s2, 1, 8, nr);
                     g_stall <= '1';
                     pend := true;
                  end if;
               end if;
            end if;
            if nr > 0 then nr := nr - 1; end if;
            if pend and g_stall = '1' and avail > 0 and nr = 0 then
               g_dataRead <= std_logic_vector(vseq);
               vseq := vseq + 1; avail := avail - 1;
               g_stall <= '0';
               pend := false;
            end if;
         end if;
         g_avail <= avail;
         g_vseq  <= vseq;
         err_gp  <= e;
      end if;
   end process;

   ------------------------------------------------------------------ SPU master (CPU side)
   process
      type tst is (IDLE, RD_NEXT, RD, DMAW, DMAR);
      type tregs is array (0 to 511) of std_logic_vector(15 downto 0);
      variable shadow : tregs := (others => (others => '0'));
      variable st : tst := IDLE;
      variable s1, s2 : positive;
      variable r, n, gap : integer := 0;
      variable a : integer;
      variable dw : unsigned(15 downto 0) := x"8000";
      variable dr : unsigned(15 downto 0) := x"4000";
      variable ops, e : natural := 0;
      variable t0 : time;
      variable lat, lmin, lmax : natural := 0;
      variable nr, nw, ndw, ndr : natural := 0;
   begin
      s1 := SEED * 41 + 3; s2 := SEED * 19 + 1;
      lmin := 1000000;
      wait until reset_top = '0';
      wait for 2 us;
      while ops < N_OPS or st /= IDLE loop
         wait until rising_edge(clk_cpu);
         m_spu_write <= '0';      -- memorymux ext_write_ena: cleared every cycle
         if c_ce = '1' then
            case st is
               when IDLE =>
                  if hold then
                     null;
                  elsif gap > 0 then
                     gap := gap - 1;
                  elsif ops < N_OPS then
                     ops := ops + 1;
                     rnd(s1, s2, 0, 99, r);
                     rnd(s1, s2, 0, 15, a);
                     a := a * 34 + 2;     -- 16 registers spread over the map
                     if r < 40 then
                        rnd(s1, s2, 0, 65535, n);
                        m_spu_write <= '1';
                        m_spu_addr  <= to_unsigned(a, 10);
                        m_spu_data  <= std_logic_vector(to_unsigned(n, 16));
                        shadow(a / 2) := std_logic_vector(to_unsigned(n, 16));
                        nw := nw + 1;
                     elsif r < 75 then
                        m_spu_addr <= to_unsigned(a, 10);
                        m_spu_read <= '1';
                        t0 := now; nr := nr + 1;
                        st := RD_NEXT;
                     elsif r < 90 then
                        -- a block starts on the SPU's request (sync mode, 16 words)
                        rnd(s1, s2, 1, 32, n);
                        if c_spu_dmaRequest = '0' then n := 0; ops := ops - 1; end if;
                        st := DMAW;
                     else
                        rnd(s1, s2, 1, 16, n);
                        m_dspu_req <= '1';
                        st := DMAR;
                     end if;
                     rnd(s1, s2, 2, 12, gap);
                  end if;

               when RD_NEXT =>
                  if c_bus_spu_stall = '0' then
                     m_spu_read <= '0';
                     st := RD;
                  end if;

               when RD =>
                  a := to_integer(m_spu_addr);
                  if c_bus_spu_dataRead /= shadow(a / 2) then
                     e := e + 1;
                     report "SPU read: got " & to_hstring(c_bus_spu_dataRead) & " expected " & to_hstring(shadow(a / 2)) severity error;
                  end if;
                  lat := (now - t0) / T_CPU;
                  if lat < lmin then lmin := lat; end if;
                  if lat > lmax then lmax := lat; end if;
                  st := IDLE;

               when DMAW =>
                  rnd(s1, s2, 0, 3, r);
                  if n > 0 and r > 0 then
                     m_dspu_wena  <= '1';
                     m_dspu_wdata <= std_logic_vector(dw);
                     dw := dw + 1; n := n - 1; ndw := ndw + 1;
                  else
                     m_dspu_wena <= '0';
                     if n = 0 then st := IDLE; end if;
                  end if;

               when DMAR =>
                  if m_dspu_rena = '1' then
                     if c_DMA_SPU_read /= std_logic_vector(dr) then
                        e := e + 1;
                        report "SPU DMA read: got " & to_hstring(c_DMA_SPU_read) & " expected " & to_hstring(dr) severity error;
                     end if;
                     dr := dr + 1; n := n - 1; ndr := ndr + 1;
                  end if;
                  if n = 0 then
                     m_dspu_req <= '0';
                     st := IDLE;
                  end if;
            end case;
         end if;
         sm_idle <= (st = IDLE);
      end loop;
      wait until rising_edge(clk_cpu);
      m_spu_write <= '0';
      sm_idle <= true;
      err_sm <= e;
      n_spu_reads <= nr; n_spu_writes <= nw; n_spu_dmaw <= ndw; n_spu_dmar <= ndr;
      spu_rd_lat_min <= lmin; spu_rd_lat_max <= lmax;
      for i in 1 to 200 loop wait until rising_edge(clk_cpu); end loop;
      spu_done <= true;
      wait;
   end process;

   ------------------------------------------------------------------ SPU model (PS1 side)
   process (clk1x)
      type tregs is array (0 to 511) of std_logic_vector(15 downto 0);
      variable regs : tregs := (others => (others => '0'));
      variable e : natural := 0;
      variable dw : unsigned(15 downto 0) := x"8000";
      variable dseq : unsigned(15 downto 0) := x"4000";
      variable s1 : positive := SEED * 11 + 2;
      variable s2 : positive := SEED * 23 + 4;
      variable r : integer;
   begin
      if rising_edge(clk1x) then
         rnd(s1, s2, 0, 7, r);
         if r = 0 then s_dmaRequest <= not s_dmaRequest; end if;
         if (p_bus_spu_write = '1' or p_DMA_SPU_writeEna = '1' or p_bus_spu_read = '1') and p_ce /= '1' then
            e := e + 1;
            report "SPU side: command without ce" severity error;
         end if;
         if p_DMA_SPU_readEna = '1' then
            dseq := dseq + 1;
         end if;
         if p_ce = '1' then
            if p_bus_spu_write = '1' then
               regs(to_integer(p_bus_spu_addr(9 downto 1))) := p_bus_spu_dataWrite;
            end if;
            if p_bus_spu_read = '1' then
               s_dataRead <= regs(to_integer(p_bus_spu_addr(9 downto 1)));
            end if;
            if p_DMA_SPU_writeEna = '1' then
               if p_DMA_SPU_write /= std_logic_vector(dw) then
                  e := e + 1;
                  report "SPU side: DMA halfword " & to_hstring(p_DMA_SPU_write) & " expected " & to_hstring(dw) severity error;
               end if;
               dw := dw + 1;
            end if;
         end if;
         s_dseq <= dseq;
         err_sp <= e;
      end if;
   end process;

   ------------------------------------------------------------------ pulses
   process (clk2x)
      variable s1 : positive := SEED * 29 + 1;
      variable s2 : positive := SEED * 37 + 3;
      variable cnt : integer := 10;
      variable hi : integer := 0;
      variable n : natural := 0;
   begin
      if rising_edge(clk2x) then
         p_irq_GPU <= '0';
         if hi > 0 then
            p_irq_GPU <= '1';
            hi := hi - 1;
         elsif not pulses_stop then
            if cnt > 0 then
               cnt := cnt - 1;
            else
               hi := 1; p_irq_GPU <= '1'; n := n + 1;     -- high for one clk1x period
               rnd(s1, s2, 4, 30, cnt);
            end if;
         end if;
         n_irqgpu_src <= n;
      end if;
   end process;

   process (clk1x)
      variable s1 : positive := SEED * 43 + 1;
      variable s2 : positive := SEED * 47 + 3;
      variable c1, c2 : integer := 5;
      variable n1, n2 : natural := 0;
   begin
      if rising_edge(clk1x) then
         p_irq_SPU  <= '0';
         p_dotclock <= '0';
         if not pulses_stop then
            if c1 > 0 then c1 := c1 - 1; else p_irq_SPU <= '1'; n1 := n1 + 1; rnd(s1, s2, 1, 12, c1); end if;
            if c2 > 0 then c2 := c2 - 1; else p_dotclock <= '1'; n2 := n2 + 1; rnd(s1, s2, 1, 4, c2); end if;
         end if;
         n_irqspu_src <= n1;
         n_dot_src    <= n2;
      end if;
   end process;

   process (clk_cpu)
      variable a, b, c : natural := 0;
   begin
      if rising_edge(clk_cpu) then
         if c_irq_GPU = '1' then a := a + 1; end if;
         if c_irq_SPU = '1' then b := b + 1; end if;
         if c_dotclock = '1' then c := c + 1; end if;
         n_irqgpu_dst <= a; n_irqspu_dst <= b; n_dot_dst <= c;
      end if;
   end process;

   ------------------------------------------------------------------ engine reset pulses
   process
      variable s1, s2 : positive;
      variable r : integer;
      variable nss, nrst : natural := 0;
   begin
      s1 := SEED * 53 + 1; s2 := SEED * 59 + 3;
      wait until reset_top = '0';
      wait for 340 us;
      while not rst_stop loop
         rnd(s1, s2, 100, 600, r);
         for i in 1 to r loop wait until rising_edge(clk1x); end loop;
         -- r = 0: reset alone; else SS_reset then reset one clk1x cycle later,
         -- as savestates.vhd issues them
         rnd(s1, s2, 0, 3, r);
         if r > 0 then
            p_SS_reset <= '1'; nss := nss + 1;
            wait until rising_edge(clk1x);
            p_SS_reset <= '0';
         end if;
         p_reset_intern <= '1'; nrst := nrst + 1;
         wait until rising_edge(clk1x);
         p_reset_intern <= '0';
         p_SS_reset <= '0';
         n_ss_src <= nss; n_rst_src <= nrst;
      end loop;
      wait;
   end process;

   process (clk_cpu)
      variable a, b, e : natural := 0;
      variable want_rst : boolean := false;
   begin
      if rising_edge(clk_cpu) then
         if c_SS_reset = '1' and c_reset_intern = '1' then
            e := e + 1; report "SS_reset and reset in one cycle" severity error;
         end if;
         if c_SS_reset = '1' then
            if want_rst then e := e + 1; report "second SS_reset before its reset" severity error; end if;
            want_rst := true; a := a + 1;
         end if;
         if c_reset_intern = '1' then
            want_rst := false; b := b + 1;
         end if;
         n_ss_dst <= a; n_rst_dst <= b; err_rs <= e;
      end if;
   end process;

   ------------------------------------------------------------------ zero fill
   process
      variable e : natural := 0;
      variable nscp, nram : natural := 0;
      variable inflight : boolean := false;
      variable s1, s2 : positive;
      variable r : integer;
   begin
      s1 := SEED * 61 + 1; s2 := SEED * 67 + 3;
      wait until gpu_done and spu_done;
      pulses_stop <= true;
      rst_stop    <= true;
      wait for 5 us;
      fill_phase <= true;
      wait for 1 us;
      wait until rising_edge(clk2x);
      p_fill_req <= not p_fill_req;
      loop
         wait until rising_edge(clk_cpu);
         c_ram_done <= '0';
         if c_SS_wren(12) = '1' then
            if c_SS_Adr /= nscp then e := e + 1; report "scratchpad fill address" severity error; end if;
            if c_SS_DataWrite /= x"00000000" then e := e + 1; end if;
            nscp := nscp + 1;
         end if;
         if c_SS_wren(16) = '1' then
            if inflight then e := e + 1; report "RAM fill: write while one is in flight" severity error; end if;
            if c_SS_Adr /= nram then e := e + 1; report "RAM fill address" severity error; end if;
            nram := nram + 1;
            inflight := true;
            rnd(s1, s2, 2, 6, r);
            for i in 1 to r loop wait until rising_edge(clk_cpu); end loop;
            c_ram_done <= '1';
            inflight := false;
         end if;
         if (c_SS_wren and "01110111111111111") /= "00000000000000000" then
            e := e + 1; report "fill: unexpected write strobe" severity error;
         end if;
         exit when p_fill_done = p_fill_req and nram > 0;
      end loop;
      n_scp <= nscp; n_ram <= nram; err_fl <= e;
      wait for 2 us;
      done_all <= true;
      wait;
   end process;

   process
   begin
      wait for MAXT;
      if not done_all then
         report OUTTAG & " TIMEOUT (watchdog): gpu_done " & boolean'image(gpu_done) & " spu_done " & boolean'image(spu_done) &
                " fill_phase " & boolean'image(fill_phase) & " gm_idle " & boolean'image(gm_idle) & " sm_idle " & boolean'image(sm_idle) &
                " hold " & boolean'image(hold) & " ce " & std_logic'image(c_ce) & " p_ce " & std_logic'image(p_ce) severity failure;
      end if;
      wait;
   end process;

   ------------------------------------------------------------------ report
   process
      variable l : line;
      variable total : natural;
   begin
      wait until done_all;
      total := err_gm + err_gp + err_sm + err_sp + err_rs + err_fl + err_ck;
      if n_irqgpu_src /= n_irqgpu_dst then total := total + 1; report "irq_GPU count" severity error; end if;
      if n_irqspu_src /= n_irqspu_dst then total := total + 1; report "irq_SPU count" severity error; end if;
      if n_dot_src /= n_dot_dst then total := total + 1; report "dotclock count" severity error; end if;
      if n_ss_src /= n_ss_dst or n_rst_src /= n_rst_dst then total := total + 1; report "reset pulse count" severity error; end if;
      if ticks_window /= 10584 then total := total + 1; report "tick count" severity error; end if;
      if n_scp /= 256 or n_ram /= FILL then total := total + 1; report "fill count" severity error; end if;
      write(l, OUTTAG & " phase " & time'image(PHASE) & " seed " & integer'image(SEED) & " window " & time'image(WINDOW));
      write(l, string'(" | gpu writes ") & integer'image(n_gpu_writes) & " reads " & integer'image(n_gpu_reads) &
               " dmaw " & integer'image(n_gpu_dmaw) & " dmar " & integer'image(n_gpu_dmar) &
               " read lat " & integer'image(gpu_rd_lat_min) & ".." & integer'image(gpu_rd_lat_max));
      write(l, string'(" | spu writes ") & integer'image(n_spu_writes) & " reads " & integer'image(n_spu_reads) &
               " dmaw " & integer'image(n_spu_dmaw) & " dmar " & integer'image(n_spu_dmar) &
               " read lat " & integer'image(spu_rd_lat_min) & ".." & integer'image(spu_rd_lat_max));
      write(l, string'(" | irq_gpu ") & integer'image(n_irqgpu_src) & "/" & integer'image(n_irqgpu_dst) &
               " irq_spu " & integer'image(n_irqspu_src) & "/" & integer'image(n_irqspu_dst) &
               " dot " & integer'image(n_dot_src) & "/" & integer'image(n_dot_dst) &
               " ss " & integer'image(n_ss_src) & "/" & integer'image(n_ss_dst) &
               " rst " & integer'image(n_rst_src) & "/" & integer'image(n_rst_dst) &
               " ticks " & integer'image(ticks_window) & " fill " & integer'image(n_scp) & "+" & integer'image(n_ram));
      write(l, string'(" | errors ") & integer'image(total));
      writeline(output, l);
      std.env.finish;
      wait;
   end process;

end architecture;
