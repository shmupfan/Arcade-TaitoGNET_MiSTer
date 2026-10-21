-- MDEC equivalence bench (sim/mdec/run.sh): the reference MDEC (mdec_ref,
-- a renamed copy of rtl/mdec.vhd from a git revision) and the current
-- rtl/mdec.vhd decode the same command stream, each driven by its own DMA0
-- writer and DMA1 reader, clk1x 50 MHz and clk2x 100 MHz as in the G-NET
-- CPU group. Each instance writes its result words (out_<g>.txt) and every
-- IDCT result RAM write (idct_<g>.txt: buffer/block/index and the clipped
-- value) in order; run.sh compares the files. The instances may differ in
-- timing, so only the sequences are compared. STAGE is the current MDEC's
-- IDCT_REG_STAGE (1 = stage R, the release setting under CPU_CLK_SPLIT;
-- 0 = upstream).
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use STD.textio.all;

entity tb_mdec_equiv is
   generic
   (
      STIM   : string  := "test.stim";
      NOUT   : integer := 16;
      MAXCYC : integer := 4000000;
      STAGE  : integer := 1
   );
end entity;

architecture arch of tb_mdec_equiv is

   signal clk1x         : std_logic := '1';
   signal clk2x         : std_logic := '1';
   signal clk1xToggle   : std_logic := '0';
   signal clk1xToggle2x : std_logic := '0';
   signal clk2xIndex    : std_logic := '0';
   signal reset         : std_logic := '1';
   signal cyc           : integer := 0;

   type t_a4  is array(0 to 1) of unsigned(3 downto 0);
   type t_a32 is array(0 to 1) of std_logic_vector(31 downto 0);
   type t_int is array(0 to 1) of integer;
   signal bus_addr      : t_a4  := (others => (others => '0'));
   signal bus_dataWrite : t_a32 := (others => (others => '0'));
   signal bus_dataRead  : t_a32;
   signal bus_write     : std_logic_vector(0 to 1) := (others => '0');
   signal dma_write     : std_logic_vector(0 to 1) := (others => '0');
   signal dma_read      : std_logic_vector(0 to 1) := (others => '0');
   signal dma_writedata : t_a32 := (others => (others => '0'));
   signal dma_readdata  : t_a32;
   signal reqW          : std_logic_vector(0 to 1);
   signal reqR          : std_logic_vector(0 to 1);
   signal doneCyc       : t_int := (others => -1);
   signal nread         : t_int := (others => 0);

begin

   clk1x <= not clk1x after 10 ns;
   clk2x <= not clk2x after 5 ns;

   -- clock index as rtl/psx_top.vhd
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         clk1xToggle <= not clk1xToggle;
         cyc         <= cyc + 1;
         if (cyc = 10) then
            reset <= '0';
         end if;
      end if;
   end process;

   process (clk2x)
   begin
      if rising_edge(clk2x) then
         clk1xToggle2x <= clk1xToggle;
         clk2xIndex    <= '0';
         if (clk1xToggle2x = clk1xToggle) then
            clk2xIndex <= '1';
         end if;
      end if;
   end process;

   gi : for g in 0 to 1 generate
   begin

      gref : if g = 0 generate
         signal idct_write  : std_logic;
         signal idct_target : unsigned(9 downto 0);
         signal idct_clip   : signed(7 downto 0);
      begin
         u : entity work.mdec_ref
         port map
         (
            clk1x => clk1x, clk2x => clk2x, clk2xIndex => clk2xIndex, ce => '1', reset => reset,
            bus_addr => bus_addr(g), bus_dataWrite => bus_dataWrite(g), bus_read => '0',
            bus_write => bus_write(g), bus_dataRead => bus_dataRead(g),
            dmaWriteRequest => reqW(g), dmaReadRequest => reqR(g),
            dma_write => dma_write(g), dma_writedata => dma_writedata(g),
            dma_read => dma_read(g), dma_readdata => dma_readdata(g),
            SS_reset => '0', SS_DataWrite => (others => '0'), SS_Adr => (others => '0'),
            SS_wren => '0', SS_rden => '0', SS_DataRead => open, SS_Idle => open
         );
         idct_write  <= <<signal u.idct_write : std_logic>>;
         idct_target <= <<signal u.idct_target : unsigned(9 downto 0)>>;
         idct_clip   <= <<signal u.idct_resultClip : signed(7 downto 0)>>;

         process (clk2x)
            file f      : text open write_mode is "idct_0.txt";
            variable l  : line;
         begin
            if rising_edge(clk2x) and idct_write = '1' then
               write(l, to_hstring(idct_target) & " " & to_hstring(idct_clip));
               writeline(f, l);
            end if;
         end process;
      end generate;

      gnew : if g = 1 generate
         signal idct_write  : std_logic;
         signal idct_target : unsigned(9 downto 0);
         signal idct_clip   : signed(7 downto 0);
      begin
         u : entity work.mdec
         generic map (IDCT_REG_STAGE => STAGE)
         port map
         (
            clk1x => clk1x, clk2x => clk2x, clk2xIndex => clk2xIndex, ce => '1', reset => reset,
            bus_addr => bus_addr(g), bus_dataWrite => bus_dataWrite(g), bus_read => '0',
            bus_write => bus_write(g), bus_dataRead => bus_dataRead(g),
            dmaWriteRequest => reqW(g), dmaReadRequest => reqR(g),
            dma_write => dma_write(g), dma_writedata => dma_writedata(g),
            dma_read => dma_read(g), dma_readdata => dma_readdata(g),
            SS_reset => '0', SS_DataWrite => (others => '0'), SS_Adr => (others => '0'),
            SS_wren => '0', SS_rden => '0', SS_DataRead => open, SS_Idle => open
         );
         idct_write  <= <<signal u.idct_write : std_logic>>;
         idct_target <= <<signal u.idct_target : unsigned(9 downto 0)>>;
         idct_clip   <= <<signal u.idct_resultClip : signed(7 downto 0)>>;

         process (clk2x)
            file f      : text open write_mode is "idct_1.txt";
            variable l  : line;
         begin
            if rising_edge(clk2x) and idct_write = '1' then
               write(l, to_hstring(idct_target) & " " & to_hstring(idct_clip));
               writeline(f, l);
            end if;
         end process;
      end generate;

      -- DMA0: control register (DMA in and out enabled), then the stream,
      -- one word per two clk1x cycles while the data-in request is set;
      -- "S n" waits for n result words (see gen_stim.py)
      process
         file f      : text;
         variable l  : line;
         variable ch : character;
         variable n  : integer;
         variable w  : std_logic_vector(31 downto 0);
      begin
         file_open(f, STIM, read_mode);
         wait until reset = '0';
         wait until rising_edge(clk1x);
         bus_addr(g)      <= x"4";
         bus_dataWrite(g) <= x"60000000";
         bus_write(g)     <= '1';
         wait until rising_edge(clk1x);
         bus_write(g)     <= '0';
         while not endfile(f) loop
            readline(f, l);
            read(l, ch);
            if (ch = 'S') then
               read(l, n);
               if (nread(g) < n) then
                  wait until nread(g) >= n;
               end if;
            else
               hread(l, w);
               wait until rising_edge(clk1x) and reqW(g) = '1';
               dma_write(g)     <= '1';
               dma_writedata(g) <= w;
               wait until rising_edge(clk1x);
               dma_write(g)     <= '0';
            end if;
         end loop;
         file_close(f);
         wait;
      end process;

      -- DMA1: one read per two clk1x cycles while the data-out request is
      -- set; the word is the one on dma_readdata during the read cycle
      process
         file f     : text;
         variable l : line;
         variable n : integer := 0;
      begin
         file_open(f, "out_" & integer'image(g) & ".txt", write_mode);
         while n < NOUT loop
            wait until rising_edge(clk1x) and reqR(g) = '1';
            dma_read(g) <= '1';
            wait until rising_edge(clk1x);
            write(l, to_hstring(dma_readdata(g)));
            writeline(f, l);
            dma_read(g) <= '0';
            n := n + 1;
            nread(g) <= n;
         end loop;
         file_close(f);
         doneCyc(g) <= cyc;
         wait;
      end process;

   end generate;

   process
   begin
      wait until rising_edge(clk1x) and ((doneCyc(0) >= 0 and doneCyc(1) >= 0) or cyc = MAXCYC);
      wait for 1 us;
      if (doneCyc(0) >= 0 and doneCyc(1) >= 0) then
         report "MDEC_EQUIV done: ref " & integer'image(doneCyc(0)) & " new " & integer'image(doneCyc(1)) &
                " clk1x cycles, " & integer'image(NOUT) & " words";
      else
         report "MDEC_EQUIV TIMEOUT: ref " & integer'image(doneCyc(0)) & " new " & integer'image(doneCyc(1));
      end if;
      std.env.finish;
   end process;

end architecture;
