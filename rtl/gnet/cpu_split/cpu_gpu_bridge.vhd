-- GPU register bus and DMA channel 2 across the CPU / PS1 clock boundary
-- (docs/r1_cpu_domain_design.md, 50.000 MHz plan, crossings C1 to C5).
--
-- CPU side (c_*, clk_cpu): the memorymux bus_gpu_* port and the DMA's GPU
-- port, with the timing gpu.vhd gives them today:
--   * bus write (GP0, GP1) and DMA write: posted into an ordered command FIFO
--     (one FIFO keeps GP0, GP1 and DMA words in order, C1).
--   * bus read (GPUREAD, GPUSTAT): c_bus_stall is set on the edge after the
--     read cycle, as gpu.vhd sets bus_stall; the read goes through the same
--     FIFO, so it reaches the GPU after every earlier write (C2). When the
--     answer is back, c_bus_stall drops and c_bus_dataRead holds the word for
--     one ce cycle, then 0 (the internal bus is an OR of all devices).
--   * DMA read (VRAM to CPU, C3): when the DMA wants a word (c_dma_readEna)
--     and none is buffered, one fetch goes through the FIFO; c_dmaRequest is
--     the buffer state while c_dma_readEna is high, so dma.vhd's readStall
--     holds the DMA until the word is here (the existing channel 2 stall).
--   * gpu_dmaRequest otherwise (C4): the GPU's level through two flip-flops,
--     forced low until the command FIFO has been empty for QUIET_CYCLES CPU
--     cycles, so a block does not start on a request computed before the
--     previous block's words reached the GPU.
-- PS1 side (p_*, clk1x): a proxy that replays each command for exactly one
-- clk1x cycle with p_ce = '1' on gpu.vhd's own bus and DMA ports, in the
-- form memorymux and dma.vhd drive them today, and returns read data
-- (waiting out gpu.vhd's bus_stall) through a cdc_handshake.
--
-- At most one read or fetch is outstanding; a bus read waits for a pending
-- fetch (and the reverse), which in practice never happens because the DMA
-- does not run while memorymux is busy.
--
-- Both resets must be applied together (the top-level reset level).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cdc_pkg.all;

entity cpu_gpu_bridge is
   generic (
      FIFO_AW         : positive := 5;
      QUIET_CYCLES    : positive := 8;
      RAM_STYLE       : string   := "M10K, no_rw_check";
      SIM_META_WINDOW : time     := 0 ns;
      SIM_SEED        : positive := 11
   );
   port (
      -- CPU side
      c_clk           : in  std_logic;
      c_rst           : in  std_logic;
      c_ce            : in  std_logic;
      c_bus_addr      : in  unsigned(3 downto 0);
      c_bus_dataWrite : in  std_logic_vector(31 downto 0);
      c_bus_read      : in  std_logic;
      c_bus_write     : in  std_logic;
      c_bus_dataRead  : out std_logic_vector(31 downto 0);
      c_bus_stall     : out std_logic;
      c_dma_writeEna  : in  std_logic;
      c_dma_write     : in  std_logic_vector(31 downto 0);
      c_dma_readEna   : in  std_logic;
      c_dma_read      : out std_logic_vector(31 downto 0);
      c_dmaRequest    : out std_logic;
      c_idle          : out std_logic;
      c_overflow      : out std_logic;
      -- PS1 side
      p_clk           : in  std_logic;
      p_rst           : in  std_logic;
      p_ce            : in  std_logic;
      p_bus_addr      : out unsigned(3 downto 0);
      p_bus_dataWrite : out std_logic_vector(31 downto 0);
      p_bus_read      : out std_logic;
      p_bus_write     : out std_logic;
      p_bus_dataRead  : in  std_logic_vector(31 downto 0);
      p_bus_stall     : in  std_logic;
      p_dma_writeEna  : out std_logic;
      p_dma_write     : out std_logic_vector(31 downto 0);
      p_dma_readEna   : out std_logic;
      p_dma_read      : in  std_logic_vector(31 downto 0);
      p_dmaRequest    : in  std_logic;
      p_idle          : out std_logic
   );
end entity;

architecture rtl of cpu_gpu_bridge is

   constant OP_WR : std_logic_vector(1 downto 0) := "00";  -- bus write
   constant OP_RD : std_logic_vector(1 downto 0) := "01";  -- bus read
   constant OP_DW : std_logic_vector(1 downto 0) := "10";  -- DMA write
   constant OP_DR : std_logic_vector(1 downto 0) := "11";  -- DMA read (fetch)

   constant CMD_W : natural := 2 + 4 + 32;
   constant RSP_W : natural := 2 + 32;      -- tag (1 = fetch), ok, data

   -- CPU side
   signal c_push_w    : std_logic;
   signal c_push_r    : std_logic;
   signal c_push_f    : std_logic;
   signal c_wr_en     : std_logic;
   signal c_cmd       : std_logic_vector(CMD_W - 1 downto 0);
   signal c_full      : std_logic;
   signal c_count     : std_logic_vector(FIFO_AW downto 0);
   signal c_ovf       : std_logic;
   signal rd_busy     : std_logic := '0';
   signal rd_pushed   : std_logic := '0';
   signal rd_ready    : std_logic := '0';
   signal rd_addr_l   : unsigned(3 downto 0) := (others => '0');
   signal rd_data_l   : std_logic_vector(31 downto 0) := (others => '0');
   signal stall_r     : std_logic := '0';
   signal data_r      : std_logic_vector(31 downto 0) := (others => '0');
   signal fetch_pend  : std_logic := '0';
   signal dbuf_valid  : std_logic := '0';
   signal dbuf        : std_logic_vector(31 downto 0) := (others => '0');
   signal quiet_cnt   : integer range 0 to QUIET_CYCLES := QUIET_CYCLES;
   signal dreq_sync   : std_logic_vector(0 downto 0);
   signal c_rsp_valid : std_logic;
   signal c_rsp       : std_logic_vector(RSP_W - 1 downto 0);
   signal c_ovf_r     : std_logic := '0';

   -- PS1 side
   type tpstate is (PS_IDLE, PS_RDWAIT);
   signal pstate      : tpstate := PS_IDLE;
   signal p_empty     : std_logic;
   signal p_cmd       : std_logic_vector(CMD_W - 1 downto 0);
   signal p_op        : std_logic_vector(1 downto 0);
   signal p_issue     : std_logic;
   signal p_rsp_start : std_logic := '0';
   signal p_rsp       : std_logic_vector(RSP_W - 1 downto 0) := (others => '0');
   signal p_rsp_busy  : std_logic;
   signal cdc_tx_dreq : std_logic := '0';

   attribute altera_attribute : string;
   attribute altera_attribute of cdc_tx_dreq : signal is CDC_ATTR_KEEP;

begin

   ------------------------------------------------------------- CPU side
   c_push_w <= c_ce and (c_bus_write or c_dma_writeEna);
   c_push_r <= '1' when rd_busy = '1' and rd_pushed = '0' and fetch_pend = '0' and c_push_w = '0' and c_full = '0' else '0';
   c_push_f <= '1' when c_ce = '1' and c_dma_readEna = '1' and dbuf_valid = '0' and fetch_pend = '0' and rd_busy = '0'
                        and c_push_w = '0' and c_full = '0' else '0';
   c_wr_en  <= (c_push_w and not c_full) or c_push_r or c_push_f;

   c_cmd <= OP_WR & std_logic_vector(c_bus_addr) & c_bus_dataWrite when (c_ce = '1' and c_bus_write = '1') else
            OP_DW & "0000" & c_dma_write                           when (c_ce = '1' and c_dma_writeEna = '1') else
            OP_RD & std_logic_vector(rd_addr_l) & x"00000000"      when (c_push_r = '1') else
            OP_DR & "0000" & x"00000000";

   process (c_clk)
   begin
      if rising_edge(c_clk) then

         c_ovf_r <= '0';
         if (c_push_w = '1' and c_full = '1') or (c_ce = '1' and c_bus_write = '1' and c_dma_writeEna = '1') then
            c_ovf_r <= '1';
         end if;
         -- synthesis translate_off
         assert not (c_ce = '1' and c_bus_write = '1' and c_dma_writeEna = '1')
            report "cpu_gpu_bridge: bus write and DMA write in one cycle" severity error;
         assert not (c_push_w = '1' and c_full = '1')
            report "cpu_gpu_bridge: command FIFO overflow" severity error;
         -- synthesis translate_on

         if c_push_r = '1' then
            rd_pushed <= '1';
         end if;
         if c_push_f = '1' then
            fetch_pend <= '1';
         end if;

         -- answer from the PS1 side
         if c_rsp_valid = '1' then
            if c_rsp(RSP_W - 1) = '0' then
               rd_data_l <= c_rsp(31 downto 0);
               rd_ready  <= '1';
            else
               fetch_pend <= '0';
               if c_rsp(RSP_W - 2) = '1' then
                  dbuf       <= c_rsp(31 downto 0);
                  dbuf_valid <= '1';
               end if;
            end if;
         end if;

         if c_ce = '1' then
            -- bus read, timed as gpu.vhd: stall from the edge after the read
            -- cycle; data for one ce cycle when the stall drops
            data_r <= (others => '0');
            if rd_ready = '1' then
               data_r   <= rd_data_l;
               stall_r  <= '0';
               rd_ready <= '0';
               rd_busy  <= '0';
            end if;
            if c_bus_read = '1' and rd_busy = '0' then
               rd_busy   <= '1';
               rd_pushed <= '0';
               rd_addr_l <= c_bus_addr;
               stall_r   <= '1';
            end if;
            -- DMA takes the buffered word in a cycle with readEna (readStall low)
            if c_dma_readEna = '1' and dbuf_valid = '1' then
               dbuf_valid <= '0';
            end if;
         end if;

         if c_wr_en = '1' or unsigned(c_count) /= 0 or rd_busy = '1' or fetch_pend = '1' then
            quiet_cnt <= QUIET_CYCLES;
         elsif quiet_cnt > 0 then
            quiet_cnt <= quiet_cnt - 1;
         end if;

         if c_rst = '1' then
            rd_busy    <= '0';
            rd_pushed  <= '0';
            rd_ready   <= '0';
            stall_r    <= '0';
            data_r     <= (others => '0');
            fetch_pend <= '0';
            dbuf_valid <= '0';
            quiet_cnt  <= QUIET_CYCLES;
            c_ovf_r    <= '0';
         end if;
      end if;
   end process;

   c_bus_stall    <= stall_r;
   c_bus_dataRead <= data_r;
   c_dma_read     <= dbuf;
   c_dmaRequest   <= dbuf_valid when (c_dma_readEna = '1') else
                     '1'        when (dreq_sync(0) = '1' and quiet_cnt = 0) else
                     '0';
   c_idle         <= '1' when (unsigned(c_count) = 0 and rd_busy = '0' and fetch_pend = '0' and dbuf_valid = '0') else '0';
   c_overflow     <= c_ovf_r;

   u_dreq : entity work.cdc_sync
      generic map (WIDTH => 1, SIM_META_WINDOW => SIM_META_WINDOW, SIM_SEED => SIM_SEED)
      port map (clk => c_clk, rst => c_rst, d(0) => cdc_tx_dreq, q => dreq_sync);

   u_cmd : entity work.cdc_fifo
      generic map (
         DATA_W          => CMD_W,
         ADDR_W          => FIFO_AW,
         FWFT            => true,
         RAM_STYLE       => RAM_STYLE,
         SIM_META_WINDOW => SIM_META_WINDOW,
         SIM_SEED        => SIM_SEED + 1)
      port map (
         wr_clk       => c_clk,
         wr_rst       => c_rst,
         wr_en        => c_wr_en,
         wr_data      => c_cmd,
         wr_full      => c_full,
         wr_count     => c_count,
         wr_overflow  => c_ovf,
         rd_clk       => p_clk,
         rd_rst       => p_rst,
         rd_en        => p_issue,
         rd_data      => p_cmd,
         rd_empty     => p_empty,
         rd_valid     => open,
         rd_count     => open,
         rd_underflow => open);

   u_rsp : entity work.cdc_handshake
      generic map (
         REQ_W           => RSP_W,
         RSP_W           => 1,
         SIM_META_WINDOW => SIM_META_WINDOW,
         SIM_SEED        => SIM_SEED + 2)
      port map (
         src_clk      => p_clk,
         src_rst      => p_rst,
         src_start    => p_rsp_start,
         src_req_data => p_rsp,
         src_busy     => p_rsp_busy,
         src_done     => open,
         src_rsp_data => open,
         dst_clk      => c_clk,
         dst_rst      => c_rst,
         dst_valid    => c_rsp_valid,
         dst_req_data => c_rsp,
         dst_pending  => open,
         dst_ack      => '1',
         dst_rsp_data => "0");

   -------------------------------------------------------------- PS1 side
   p_op <= p_cmd(CMD_W - 1 downto CMD_W - 2);

   -- one command per clk1x cycle with ce; reads and fetches also need the
   -- answer path free
   p_issue <= '1' when pstate = PS_IDLE and p_empty = '0' and p_ce = '1' and p_rsp_start = '0' and
                       ((p_op = OP_WR or p_op = OP_DW) or p_rsp_busy = '0') else '0';

   p_bus_addr      <= unsigned(p_cmd(35 downto 32));
   p_bus_dataWrite <= p_cmd(31 downto 0);
   p_dma_write     <= p_cmd(31 downto 0);
   p_bus_write     <= p_issue when p_op = OP_WR else '0';
   p_bus_read      <= p_issue when p_op = OP_RD else '0';
   p_dma_writeEna  <= p_issue when p_op = OP_DW else '0';
   p_dma_readEna   <= p_issue when (p_op = OP_DR and p_dmaRequest = '1') else '0';

   process (p_clk)
   begin
      if rising_edge(p_clk) then
         p_rsp_start <= '0';
         cdc_tx_dreq <= p_dmaRequest;

         case pstate is
            when PS_IDLE =>
               if p_issue = '1' then
                  if p_op = OP_RD then
                     pstate <= PS_RDWAIT;
                  elsif p_op = OP_DR then
                     -- the GPU pops its read FIFO on this edge; its head is the word
                     p_rsp_start <= '1';
                     p_rsp       <= "1" & p_dmaRequest & p_dma_read;
                  end if;
               end if;

            when PS_RDWAIT =>
               -- gpu.vhd registered bus_dataRead and bus_stall on the issue
               -- edge; with the stall it supplies the word when it drops
               if p_bus_stall = '0' then
                  p_rsp_start <= '1';
                  p_rsp       <= "01" & p_bus_dataRead;
                  pstate      <= PS_IDLE;
               end if;
         end case;

         if p_rst = '1' then
            pstate      <= PS_IDLE;
            p_rsp_start <= '0';
         end if;
      end if;
   end process;

   p_idle <= '1' when (p_empty = '1' and pstate = PS_IDLE and p_rsp_busy = '0' and p_rsp_start = '0') else '0';

end architecture;
