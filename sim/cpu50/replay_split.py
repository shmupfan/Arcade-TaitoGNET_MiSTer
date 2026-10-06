#!/usr/bin/env python3
"""Make tb_gpu_replay_split.vhd from sim/m1/tb_gpu_replay.vhd: the same
replay of a GPU command stream, but every GP0/GP1 write and DMA channel 2
word is issued on a 50.000 MHz CPU clock and reaches the GPU through
rtl/gnet/cpu_split/cpu_gpu_bridge (the R1 CPU_CLK_SPLIT crossing), with the
CDC metastability model on. The feeder keeps its logic (CPU write: one
write cycle; DMA word: only while gpu_dmaRequest is high), now on clk_cpu
against the bridge's CPU side; the GPU's bus and DMA ports are driven by the
bridge's PS1 side. Every edit is an exact substring with an asserted count.

    replay_split.py <sim/m1/tb_gpu_replay.vhd> <out.vhd>
"""
import sys


def main():
    src, dst = sys.argv[1], sys.argv[2]
    t = open(src).read()
    rules = [
        ("entity tb_gpu_replay is", "entity tb_gpu_replay_split is", 1),
        ("architecture arch of tb_gpu_replay is", "architecture arch of tb_gpu_replay_split is", 1),
        (".tb_gpu_replay.igpu.", ".tb_gpu_replay_split.igpu.", 7),
        ("      VIDCAP      : boolean := true    -- video output capture for the frames in DUMPS\n",
         "      VIDCAP      : boolean := true;   -- video output capture for the frames in DUMPS\n"
         "      CPU_PHASE   : time    := 3 ns;   -- clk_cpu start after clk1x\n"
         "      WINDOW      : time    := 9 ns    -- CDC metastability model (rtl/gnet/cdc)\n", 1),
        ("   signal clk1x, clk2x, clkvid : std_logic := '1';\n",
         "   signal clk1x, clk2x, clkvid : std_logic := '1';\n"
         "   signal clk_cpu, clk_cpu2x   : std_logic := '0';\n"
         "   signal cpu_run              : boolean := false;\n"
         "   -- PS1 side of the bridge (GPU ports)\n"
         "   signal p_bus_addr      : unsigned(3 downto 0);\n"
         "   signal p_bus_dataWrite : std_logic_vector(31 downto 0);\n"
         "   signal p_bus_read, p_bus_write : std_logic;\n"
         "   signal p_bus_dataRead  : std_logic_vector(31 downto 0);\n"
         "   signal p_bus_stall     : std_logic;\n"
         "   signal p_gpu_dmaRequest : std_logic;\n"
         "   signal p_DMA_writeEna, p_DMA_readEna : std_logic;\n"
         "   signal p_DMA_write, p_DMA_read : std_logic_vector(31 downto 0);\n"
         "   signal c_bus_dataRead  : std_logic_vector(31 downto 0);\n", 1),
        ("   clkvid <= not clkvid after TVID / 2 when not done;\n",
         "   clkvid <= not clkvid after TVID / 2 when not done;\n"
         "   -- CPU group clocks: 100 MHz and 50 MHz from it, phase-aligned\n"
         "   cpu_run   <= true after CPU_PHASE;\n"
         "   clk_cpu2x <= not clk_cpu2x after 5 ns when cpu_run and not done;\n"
         "   process (clk_cpu2x) begin\n"
         "      if rising_edge(clk_cpu2x) then clk_cpu <= not clk_cpu; end if;\n"
         "   end process;\n", 1),
        ("bus_addr => bus_addr, bus_dataWrite => bus_dataWrite, bus_read => '0',",
         "bus_addr => p_bus_addr, bus_dataWrite => p_bus_dataWrite, bus_read => p_bus_read,", 1),
        ("bus_write => bus_write, bus_dataRead => bus_dataRead, bus_stall => bus_stall,",
         "bus_write => p_bus_write, bus_dataRead => p_bus_dataRead, bus_stall => p_bus_stall,", 1),
        ("dmaOn => dmaOn, gpu_dmaRequest => gpu_dmaRequest, DMA_GPU_waiting => '0',",
         "dmaOn => dmaOn, gpu_dmaRequest => p_gpu_dmaRequest, DMA_GPU_waiting => '0',", 1),
        ("DMA_GPU_writeEna => DMA_GPU_writeEna, DMA_GPU_readEna => '0',",
         "DMA_GPU_writeEna => p_DMA_writeEna, DMA_GPU_readEna => p_DMA_readEna,", 1),
        ("DMA_GPU_write => DMA_GPU_write, DMA_GPU_read => open,",
         "DMA_GPU_write => p_DMA_write, DMA_GPU_read => p_DMA_read,", 1),
        ("   -- VRAM: 8 MB byte space",
         "   -- R1 crossing: feeder (clk_cpu) to GPU (clk1x)\n"
         "   ibridge : entity work.cpu_gpu_bridge\n"
         "   generic map (SIM_META_WINDOW => WINDOW)\n"
         "   port map (\n"
         "      c_clk => clk_cpu, c_rst => reset, c_ce => '1',\n"
         "      c_bus_addr => bus_addr, c_bus_dataWrite => bus_dataWrite, c_bus_read => '0', c_bus_write => bus_write,\n"
         "      c_bus_dataRead => c_bus_dataRead, c_bus_stall => bus_stall,\n"
         "      c_dma_writeEna => DMA_GPU_writeEna, c_dma_write => DMA_GPU_write, c_dma_readEna => '0',\n"
         "      c_dma_read => open, c_dmaRequest => gpu_dmaRequest, c_idle => open, c_overflow => open,\n"
         "      p_clk => clk1x, p_rst => reset, p_ce => '1',\n"
         "      p_bus_addr => p_bus_addr, p_bus_dataWrite => p_bus_dataWrite, p_bus_read => p_bus_read,\n"
         "      p_bus_write => p_bus_write, p_bus_dataRead => p_bus_dataRead, p_bus_stall => p_bus_stall,\n"
         "      p_dma_writeEna => p_DMA_writeEna, p_dma_write => p_DMA_write, p_dma_readEna => p_DMA_readEna,\n"
         "      p_dma_read => p_DMA_read, p_dmaRequest => p_gpu_dmaRequest, p_idle => open);\n\n"
         "   -- VRAM: 8 MB byte space", 1),
    ]
    for old, new, n in rules:
        c = t.count(old)
        assert c == n, f'expected {n} of {old!r}, found {c}'
        t = t.replace(old, new)
    # the feeder runs on the CPU clock
    i = t.index("   -- command feeder")
    j = t.index("   -- R23: GPU drawing time")
    feeder = t[i:j]
    n = feeder.count("rising_edge(clk1x)")
    assert n == 7, n
    feeder = feeder.replace("rising_edge(clk1x)", "rising_edge(clk_cpu)")
    t = t[:i] + feeder + t[j:]
    open(dst, 'w').write(t)


if __name__ == '__main__':
    main()
