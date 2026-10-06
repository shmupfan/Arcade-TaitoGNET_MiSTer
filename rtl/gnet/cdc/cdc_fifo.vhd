-- Dual-clock FIFO, 2**ADDR_W words of DATA_W bits, Gray-coded pointers
-- (ADDR_W + 1 bits) through cdc_sync. The memory is an inferred simple
-- dual-port RAM (write port on wr_clk, read address registered on rd_clk), so
-- Quartus can place it in M10K or MLAB: RAM_STYLE is passed as the ramstyle
-- attribute ("M10K, no_rw_check", "MLAB, no_rw_check", "logic", or the
-- default "no_rw_check", which leaves the choice to Quartus). The FIFO never
-- reads a word whose write is still in progress, so read-during-write
-- behaviour does not matter.
--
-- Write side: a word is stored on each wr_clk edge with wr_en = '1' and
-- wr_full = '0'; wr_en while full is ignored and flagged on wr_overflow for
-- one cycle. wr_count is the stored word count as the write side sees it
-- (never below the true count; it lags reads).
-- Read side, FWFT = true (first word fall through, show-ahead): rd_empty =
-- '0' means rd_data holds the oldest word; rd_en = '1' takes it.
-- Read side, FWFT = false: rd_en = '1' while rd_empty = '0' takes the oldest
-- word; it is on rd_data in the next cycle, marked by rd_valid, and only in
-- that cycle. Its slot is released to the write side one read cycle after
-- the pop, so an MLAB with a combinational read path cannot be overwritten
-- under the word while rd_valid is high. (FWFT needs no delay: the shown
-- word's slot stays allocated until it is popped.)
-- rd_en while empty is ignored and flagged on rd_underflow for one cycle.
-- rd_count is the word count as the read side sees it (never above the true
-- count; it lags writes). The capacity is exactly 2**ADDR_W words in both
-- modes.
--
-- Latency from the write edge (word written into an empty FIFO): FWFT
-- rd_empty falls after read edge STAGES + 1 (3, or 4 when a synchroniser
-- resolves late); normal mode after read edge STAGES (2 or 3), with the data
-- one edge after rd_en. A pop frees its slot for the write side after write
-- edge STAGES (2 or 3) from the read edge that publishes it (the pop edge in
-- FWFT mode, one read edge later in normal mode).
--
-- Both resets must be applied together, long enough to cover a cycle of the
-- slower clock, with neither side writing or reading.
--
-- Negative controls only: STAGES = 0 (no pointer synchroniser), NEG_BINARY
-- (binary pointers), NEG_EARLY_FREE (normal mode releases the slot on the
-- pop edge).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cdc_pkg.all;

entity cdc_fifo is
   generic (
      DATA_W          : positive := 32;
      ADDR_W          : positive := 4;
      FWFT            : boolean  := true;
      RAM_STYLE       : string   := "no_rw_check";
      STAGES          : natural  := 2;
      NEG_BINARY      : boolean  := false;
      NEG_EARLY_FREE  : boolean  := false;
      SIM_META_WINDOW : time     := 0 ns;
      SIM_SEED        : positive := 1
   );
   port (
      wr_clk       : in  std_logic;
      wr_rst       : in  std_logic := '0';
      wr_en        : in  std_logic;
      wr_data      : in  std_logic_vector(DATA_W - 1 downto 0);
      wr_full      : out std_logic;
      wr_count     : out std_logic_vector(ADDR_W downto 0);
      wr_overflow  : out std_logic;

      rd_clk       : in  std_logic;
      rd_rst       : in  std_logic := '0';
      rd_en        : in  std_logic;
      rd_data      : out std_logic_vector(DATA_W - 1 downto 0);
      rd_empty     : out std_logic;
      rd_valid     : out std_logic;
      rd_count     : out std_logic_vector(ADDR_W downto 0);
      rd_underflow : out std_logic
   );
end entity;

architecture rtl of cdc_fifo is

   constant DEPTH : natural := 2 ** ADDR_W;

   type ram_t is array (0 to DEPTH - 1) of std_logic_vector(DATA_W - 1 downto 0);
   signal ram : ram_t;
   attribute ramstyle : string;
   attribute ramstyle of ram : signal is RAM_STYLE;

   -- write domain
   signal wr_bin      : unsigned(ADDR_W downto 0) := (others => '0');
   signal cdc_tx_wptr : std_logic_vector(ADDR_W downto 0) := (others => '0');
   signal rptr_sync   : std_logic_vector(ADDR_W downto 0);
   signal rptr_bin    : unsigned(ADDR_W downto 0);
   signal wr_used     : unsigned(ADDR_W downto 0);
   signal full_i      : std_logic;
   signal wr_we       : std_logic;
   signal wr_ovf_r    : std_logic := '0';

   -- read domain
   signal fetch_bin   : unsigned(ADDR_W downto 0) := (others => '0');
   signal pop_bin     : unsigned(ADDR_W downto 0) := (others => '0');
   signal cdc_tx_rptr : std_logic_vector(ADDR_W downto 0) := (others => '0');
   signal wptr_sync   : std_logic_vector(ADDR_W downto 0);
   signal wptr_bin    : unsigned(ADDR_W downto 0);
   signal mem_has     : std_logic;
   signal dvalid      : std_logic := '0';
   signal raddr       : unsigned(ADDR_W - 1 downto 0) := (others => '0');
   signal q           : std_logic_vector(DATA_W - 1 downto 0);
   signal fetch       : std_logic;
   signal pop         : std_logic;
   signal rd_valid_r  : std_logic := '0';
   signal rd_unf_r    : std_logic := '0';

   attribute altera_attribute : string;
   attribute altera_attribute of cdc_tx_wptr : signal is CDC_ATTR_KEEP;
   attribute altera_attribute of cdc_tx_rptr : signal is CDC_ATTR_KEEP;

   -- synthesis translate_off
   type wtime_t is array (0 to DEPTH - 1) of time;
   signal sim_wtime : wtime_t := (others => -1 sec);
   signal sim_fetch_t : time := 0 fs;
   -- synthesis translate_on

   function enc(b : unsigned) return std_logic_vector is
   begin
      if NEG_BINARY then
         return std_logic_vector(b);
      end if;
      return std_logic_vector(cdc_bin2gray(b));
   end function;

   function dec(v : std_logic_vector) return unsigned is
   begin
      if NEG_BINARY then
         return unsigned(v);
      end if;
      return cdc_gray2bin(unsigned(v));
   end function;

begin

   ------------------------------------------------------------- write side
   rptr_bin <= dec(rptr_sync);
   wr_used  <= wr_bin - rptr_bin;
   full_i   <= wr_used(ADDR_W);  -- wr_used = DEPTH

   process (wr_clk)
      variable nb : unsigned(ADDR_W downto 0);
   begin
      if rising_edge(wr_clk) then
         nb := wr_bin;
         wr_ovf_r <= '0';
         if wr_en = '1' then
            if full_i = '0' then
               nb := wr_bin + 1;
            else
               wr_ovf_r <= '1';
            end if;
         end if;
         wr_bin      <= nb;
         cdc_tx_wptr <= enc(nb);
         if wr_rst = '1' then
            wr_bin      <= (others => '0');
            cdc_tx_wptr <= (others => '0');
            wr_ovf_r    <= '0';
         end if;
      end if;
   end process;

   wr_we <= wr_en and not full_i;

   -- RAM write port
   process (wr_clk)
   begin
      if rising_edge(wr_clk) then
         if wr_we = '1' then
            ram(to_integer(wr_bin(ADDR_W - 1 downto 0))) <= wr_data;
            -- synthesis translate_off
            -- simulation only: when each word was written (see the read port)
            sim_wtime(to_integer(wr_bin(ADDR_W - 1 downto 0))) <= now;
            -- synthesis translate_on
         end if;
      end if;
   end process;

   u_rsync : entity work.cdc_sync
      generic map (
         WIDTH           => ADDR_W + 1,
         STAGES          => STAGES,
         SIM_META_WINDOW => SIM_META_WINDOW,
         SIM_SEED        => SIM_SEED * 2 + 1)
      port map (
         clk => wr_clk,
         rst => wr_rst,
         d   => cdc_tx_rptr,
         q   => rptr_sync);

   wr_full     <= full_i;
   wr_count    <= std_logic_vector(wr_used);
   wr_overflow <= wr_ovf_r;

   -------------------------------------------------------------- read side
   u_wsync : entity work.cdc_sync
      generic map (
         WIDTH           => ADDR_W + 1,
         STAGES          => STAGES,
         SIM_META_WINDOW => SIM_META_WINDOW,
         SIM_SEED        => SIM_SEED * 2)
      port map (
         clk => rd_clk,
         rst => rd_rst,
         d   => cdc_tx_wptr,
         q   => wptr_sync);

   wptr_bin <= dec(wptr_sync);
   mem_has  <= '1' when wptr_bin /= fetch_bin else '0';

   g_fwft : if FWFT generate
      pop   <= rd_en and dvalid;
      fetch <= mem_has and (not dvalid or rd_en);
   end generate;
   g_norm : if not FWFT generate
      pop   <= rd_en and mem_has;
      fetch <= pop;
   end generate;

   -- RAM read port: the read address is registered on rd_clk (enabled by
   -- fetch) and the data is read from it combinationally. Both RAM types
   -- implement at least this (an MLAB read path is combinational after the
   -- address register), so the simulation also shows any write that lands
   -- in the slot being shown.
   process (rd_clk)
   begin
      if rising_edge(rd_clk) then
         if fetch = '1' then
            raddr <= fetch_bin(ADDR_W - 1 downto 0);
            -- synthesis translate_off
            sim_fetch_t <= now;
            -- synthesis translate_on
         end if;
      end if;
   end process;

   process (ram, raddr
            -- synthesis translate_off
            , sim_wtime, sim_fetch_t
            -- synthesis translate_on
            )
      -- synthesis translate_off
      variable poison : boolean := false;
      variable age    : time;
      -- synthesis translate_on
   begin
      q <= ram(to_integer(raddr));
      -- synthesis translate_off
      -- Simulation only. A fetch less than SIM_META_WINDOW after the write
      -- of its slot returns X until the next fetch (a read edge too close to
      -- the write: what an unsynchronised pointer risks). A write into the
      -- slot already shown makes q X for the window, then the new data
      -- (what a slot released too early risks).
      if SIM_META_WINDOW > 0 ns then
         age := now - sim_wtime(to_integer(raddr));
         if sim_fetch_t'event then
            poison := age < SIM_META_WINDOW;
         end if;
         if poison then
            q <= (others => 'X');
         elsif age < SIM_META_WINDOW then
            q <= (others => 'X'), ram(to_integer(raddr)) after SIM_META_WINDOW - age;
         end if;
      end if;
      -- synthesis translate_on
   end process;

   process (rd_clk)
      variable nf, np : unsigned(ADDR_W downto 0);
   begin
      if rising_edge(rd_clk) then
         nf := fetch_bin;
         np := pop_bin;
         if fetch = '1' then
            nf := fetch_bin + 1;
         end if;
         if pop = '1' then
            np := pop_bin + 1;
         end if;
         fetch_bin   <= nf;
         pop_bin     <= np;
         if FWFT or NEG_EARLY_FREE then
            cdc_tx_rptr <= enc(np);
         else
            cdc_tx_rptr <= enc(pop_bin);  -- one cycle late, see header
         end if;
         if fetch = '1' then
            dvalid <= '1';
         elsif pop = '1' then
            dvalid <= '0';
         end if;
         rd_valid_r <= pop;
         rd_unf_r   <= rd_en and not pop;
         if rd_rst = '1' then
            fetch_bin   <= (others => '0');
            pop_bin     <= (others => '0');
            cdc_tx_rptr <= (others => '0');
            dvalid      <= '0';
            rd_valid_r  <= '0';
            rd_unf_r    <= '0';
         end if;
      end if;
   end process;

   rd_data      <= q;
   rd_count     <= std_logic_vector(wptr_bin - pop_bin);
   rd_underflow <= rd_unf_r;

   g_fwft_o : if FWFT generate
      rd_empty <= not dvalid;
      rd_valid <= dvalid;
   end generate;
   g_norm_o : if not FWFT generate
      rd_empty <= not mem_has;
      rd_valid <= rd_valid_r;
   end generate;

end architecture;
