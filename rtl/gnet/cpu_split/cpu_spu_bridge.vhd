-- SPU register bus and DMA channel 4 across the CPU / PS1 clock boundary
-- (docs/r1_cpu_domain_design.md, 50.000 MHz plan, crossings C8 to C11).
--
-- CPU side (c_*, clk_cpu): memorymux's external bus port for the SPU and the
-- DMA's SPU port.
--   * register write and DMA write: posted into one ordered command FIFO
--     (C8), one entry per ce cycle with the strobe, as spu.vhd counts them.
--   * register read (C9, Lee's decision 2: a plain stall handshake): while
--     memorymux holds bus_spu_read (state EXT_READ_NEXT) the read goes
--     through the same FIFO; c_bus_stall (combinational: read and no answer
--     yet) keeps memorymux in EXT_READ_NEXT (memorymux.vhd bus_spu_stall).
--     When the answer is here the stall drops, memorymux moves to EXT_READ on
--     its next ce edge and captures c_bus_dataRead there, as it captures
--     spu.vhd's registered bus_dataRead today.
--   * DMA read (C10): dma.vhd's channel 4 read is stalled through
--     DMA_SPU_readStall (new port, default '0') until a fetched halfword is
--     buffered; c_dma_readReq is the DMA's ungated "wants a halfword".
--   * spu_dmaRequest (C11): the SPU's level through two flip-flops, forced
--     low until the FIFO has been empty for QUIET_CYCLES CPU cycles.
-- PS1 side (p_*, clk1x): a proxy that replays each command for one clk1x
-- cycle with p_ce = '1' on spu.vhd's ports and returns read data (taken one
-- cycle after the read, where spu.vhd has registered it) through a
-- cdc_handshake. A DMA read pops the SPU's show-ahead FIFO in the issue
-- cycle and returns its head (0 when empty, spu.vhd's value today).
--
-- Both resets must be applied together (the top-level reset level).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cdc_pkg.all;

entity cpu_spu_bridge is
   generic (
      FIFO_AW         : positive := 6;
      QUIET_CYCLES    : positive := 8;
      RAM_STYLE       : string   := "M10K, no_rw_check";
      SIM_META_WINDOW : time     := 0 ns;
      SIM_SEED        : positive := 21
   );
   port (
      -- CPU side
      c_clk           : in  std_logic;
      c_rst           : in  std_logic;
      c_ce            : in  std_logic;
      c_bus_addr      : in  unsigned(9 downto 0);
      c_bus_dataWrite : in  std_logic_vector(15 downto 0);
      c_bus_read      : in  std_logic;
      c_bus_write     : in  std_logic;
      c_bus_dataRead  : out std_logic_vector(15 downto 0);
      c_bus_stall     : out std_logic;
      c_dma_writeEna  : in  std_logic;
      c_dma_write     : in  std_logic_vector(15 downto 0);
      c_dma_readReq   : in  std_logic;
      c_dma_readEna   : in  std_logic;
      c_dma_readStall : out std_logic;
      c_dma_read      : out std_logic_vector(15 downto 0);
      c_dmaRequest    : out std_logic;
      c_idle          : out std_logic;
      c_overflow      : out std_logic;
      -- PS1 side
      p_clk           : in  std_logic;
      p_rst           : in  std_logic;
      p_ce            : in  std_logic;
      p_bus_addr      : out unsigned(9 downto 0);
      p_bus_dataWrite : out std_logic_vector(15 downto 0);
      p_bus_read      : out std_logic;
      p_bus_write     : out std_logic;
      p_bus_dataRead  : in  std_logic_vector(15 downto 0);
      p_dma_writeEna  : out std_logic;
      p_dma_write     : out std_logic_vector(15 downto 0);
      p_dma_readEna   : out std_logic;
      p_dma_read      : in  std_logic_vector(15 downto 0);
      p_dmaRequest    : in  std_logic;
      p_idle          : out std_logic
   );
end entity;

architecture rtl of cpu_spu_bridge is

   constant OP_WR : std_logic_vector(1 downto 0) := "00";
   constant OP_RD : std_logic_vector(1 downto 0) := "01";
   constant OP_DW : std_logic_vector(1 downto 0) := "10";
   constant OP_DR : std_logic_vector(1 downto 0) := "11";

   constant CMD_W : natural := 2 + 10 + 16;
   constant RSP_W : natural := 1 + 16;     -- tag (1 = DMA fetch), data

   -- CPU side
   signal c_push_w    : std_logic;
   signal c_push_r    : std_logic;
   signal c_push_f    : std_logic;
   signal c_wr_en     : std_logic;
   signal c_cmd       : std_logic_vector(CMD_W - 1 downto 0);
   signal c_full      : std_logic;
   signal c_count     : std_logic_vector(FIFO_AW downto 0);
   signal rd_busy     : std_logic := '0';
   signal rd_pushed   : std_logic := '0';
   signal rd_ready    : std_logic := '0';
   signal rd_addr_l   : unsigned(9 downto 0) := (others => '0');
   signal rd_data_l   : std_logic_vector(15 downto 0) := (others => '0');
   signal fetch_pend  : std_logic := '0';
   signal dbuf_valid  : std_logic := '0';
   signal dbuf        : std_logic_vector(15 downto 0) := (others => '0');
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
   c_push_f <= '1' when c_dma_readReq = '1' and dbuf_valid = '0' and fetch_pend = '0' and rd_busy = '0'
                        and c_push_w = '0' and c_full = '0' else '0';
   c_wr_en  <= (c_push_w and not c_full) or c_push_r or c_push_f;

   c_cmd <= OP_WR & std_logic_vector(c_bus_addr) & c_bus_dataWrite when (c_ce = '1' and c_bus_write = '1') else
            OP_DW & "0000000000" & c_dma_write                    when (c_ce = '1' and c_dma_writeEna = '1') else
            OP_RD & std_logic_vector(rd_addr_l) & x"0000"         when (c_push_r = '1') else
            OP_DR & "0000000000" & x"0000";

   process (c_clk)
   begin
      if rising_edge(c_clk) then

         c_ovf_r <= '0';
         if (c_push_w = '1' and c_full = '1') or (c_ce = '1' and c_bus_write = '1' and c_dma_writeEna = '1') then
            c_ovf_r <= '1';
         end if;
         -- synthesis translate_off
         assert not (c_ce = '1' and c_bus_write = '1' and c_dma_writeEna = '1')
            report "cpu_spu_bridge: bus write and DMA write in one cycle" severity error;
         assert not (c_push_w = '1' and c_full = '1')
            report "cpu_spu_bridge: command FIFO overflow" severity error;
         -- synthesis translate_on

         -- start a register read when memorymux enters EXT_READ_NEXT
         if c_bus_read = '1' and rd_busy = '0' and rd_ready = '0' then
            rd_busy   <= '1';
            rd_pushed <= '0';
            rd_addr_l <= c_bus_addr;
         end if;
         if c_push_r = '1' then
            rd_pushed <= '1';
         end if;
         if c_push_f = '1' then
            fetch_pend <= '1';
         end if;

         if c_rsp_valid = '1' then
            if c_rsp(RSP_W - 1) = '0' then
               rd_data_l <= c_rsp(15 downto 0);
               rd_ready  <= '1';
               rd_busy   <= '0';
            else
               fetch_pend <= '0';
               dbuf       <= c_rsp(15 downto 0);
               dbuf_valid <= '1';
            end if;
         end if;

         if c_ce = '1' then
            -- memorymux leaves EXT_READ_NEXT on this edge (stall low)
            if c_bus_read = '1' and rd_ready = '1' then
               rd_ready <= '0';
            end if;
            -- the DMA takes the buffered halfword (readEna is gated by the stall)
            if c_dma_readEna = '1' then
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
            fetch_pend <= '0';
            dbuf_valid <= '0';
            quiet_cnt  <= QUIET_CYCLES;
            c_ovf_r    <= '0';
         end if;
      end if;
   end process;

   c_bus_stall     <= c_bus_read and not rd_ready;
   c_bus_dataRead  <= rd_data_l;
   c_dma_read      <= dbuf;
   c_dma_readStall <= not dbuf_valid;
   c_dmaRequest    <= '1' when (dreq_sync(0) = '1' and quiet_cnt = 0) else '0';
   c_idle          <= '1' when (unsigned(c_count) = 0 and rd_busy = '0' and rd_ready = '0' and fetch_pend = '0' and dbuf_valid = '0') else '0';
   c_overflow      <= c_ovf_r;

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
         wr_overflow  => open,
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

   p_issue <= '1' when pstate = PS_IDLE and p_empty = '0' and p_ce = '1' and p_rsp_start = '0' and
                       ((p_op = OP_WR or p_op = OP_DW) or p_rsp_busy = '0') else '0';

   p_bus_addr      <= unsigned(p_cmd(25 downto 16));
   p_bus_dataWrite <= p_cmd(15 downto 0);
   p_dma_write     <= p_cmd(15 downto 0);
   p_bus_write     <= p_issue when p_op = OP_WR else '0';
   p_bus_read      <= p_issue when p_op = OP_RD else '0';
   p_dma_writeEna  <= p_issue when p_op = OP_DW else '0';
   p_dma_readEna   <= p_issue when p_op = OP_DR else '0';

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
                     p_rsp_start <= '1';
                     p_rsp       <= "1" & p_dma_read;
                  end if;
               end if;

            when PS_RDWAIT =>
               -- spu.vhd registered bus_dataRead on the issue edge
               p_rsp_start <= '1';
               p_rsp       <= "0" & p_bus_dataRead;
               pstate      <= PS_IDLE;
         end case;

         if p_rst = '1' then
            pstate      <= PS_IDLE;
            p_rsp_start <= '0';
         end if;
      end if;
   end process;

   p_idle <= '1' when (p_empty = '1' and pstate = PS_IDLE and p_rsp_busy = '0' and p_rsp_start = '0') else '0';

end architecture;
