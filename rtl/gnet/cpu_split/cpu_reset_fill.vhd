-- CPU-side part of the reset sequence when the CPU group has its own clock
-- (docs/r1_cpu_domain_design.md, 50.000 MHz plan, crossing C17; Lee's
-- decision 3: the reset zero fill of RAM and scratchpad is kept).
--
-- 1. Reset pulses. savestates.vhd (on clk1x/clk2x) issues SS_reset and then,
--    one clk1x cycle later, reset_out (each one clk1x cycle). Each arrives
--    here through its own pulse synchroniser; this block re-creates the
--    order on clk_cpu: c_SS_reset for one cycle, then c_reset_intern in a
--    later cycle, never in the same one (a reset pulse that arrives together
--    with or before its SS_reset is held back by one cycle).
-- 2. Zero fill. With CPU_FILL_EXT = 1 savestates.vhd skips save types 12
--    (scratchpad) and 16 (main RAM) and instead toggles fill_req and waits
--    for fill_done to follow. This block then writes zeros through the
--    modules' own savestate write ports, as the engine did: 256 scratchpad
--    words (cpu.vhd SS_wren_SCP), then 524,288 RAM words through memorymux
--    (SS_wren_SDRam, waits for ram_done after each word). Writes are issued
--    only while ce = '0' (memorymux accepts SS_wren_SDRam only then). With
--    FASTSIM = '1' the RAM part is skipped, as the engine skips type 16 in
--    simulation.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cpu_reset_fill is
   generic (
      FASTSIM   : std_logic := '0';
      SCP_WORDS : positive  := 256;
      RAM_WORDS : positive  := 524288
   );
   port (
      clk           : in  std_logic;
      rst           : in  std_logic;     -- top-level reset level (synchronised)
      ss_pulse      : in  std_logic;     -- engine SS_reset, synchronised pulse
      rst_pulse     : in  std_logic;     -- engine reset_out, synchronised pulse
      SS_reset      : out std_logic := '0';
      reset_intern  : out std_logic := '0';

      ce            : in  std_logic;
      fill_req      : in  std_logic;     -- toggle from the engine, synchronised
      fill_done     : out std_logic;     -- toggle back
      ram_done      : in  std_logic;
      ss_wr_scp     : out std_logic := '0';
      ss_wr_ram     : out std_logic := '0';
      SS_Adr        : out unsigned(18 downto 0) := (others => '0');
      SS_DataWrite  : out std_logic_vector(31 downto 0);
      busy          : out std_logic
   );
end entity;

architecture rtl of cpu_reset_fill is

   signal rst_pend : std_logic := '0';

   type tfstate is (F_IDLE, F_SCP, F_SCP_GAP, F_RAM, F_RAM_WAIT, F_DONE);
   signal fstate   : tfstate := F_IDLE;
   signal cnt      : unsigned(18 downto 0) := (others => '0');
   signal done_t   : std_logic := '0';

begin

   SS_DataWrite <= (others => '0');
   fill_done    <= done_t;
   busy         <= '0' when fstate = F_IDLE else '1';

   -- reset pulse ordering
   process (clk)
   begin
      if rising_edge(clk) then
         SS_reset     <= ss_pulse;
         reset_intern <= '0';
         if rst_pulse = '1' or rst_pend = '1' then
            if ss_pulse = '1' then
               rst_pend <= '1';            -- SS_reset goes out next cycle, reset after it
            else
               reset_intern <= '1';
               rst_pend     <= '0';
            end if;
         end if;
      end if;
   end process;

   -- zero fill
   process (clk)
   begin
      if rising_edge(clk) then
         ss_wr_scp <= '0';
         ss_wr_ram <= '0';

         case fstate is
            when F_IDLE =>
               cnt <= (others => '0');
               if fill_req /= done_t and ce = '0' then
                  fstate <= F_SCP;
               end if;

            when F_SCP =>
               ss_wr_scp <= '1';
               SS_Adr    <= cnt;
               fstate    <= F_SCP_GAP;

            when F_SCP_GAP =>
               if cnt = SCP_WORDS - 1 then
                  cnt <= (others => '0');
                  if FASTSIM = '1' then
                     fstate <= F_DONE;
                  else
                     fstate <= F_RAM;
                  end if;
               else
                  cnt    <= cnt + 1;
                  fstate <= F_SCP;
               end if;

            when F_RAM =>
               if ce = '0' then
                  ss_wr_ram <= '1';
                  SS_Adr    <= cnt;
                  fstate    <= F_RAM_WAIT;
               end if;

            when F_RAM_WAIT =>
               if ram_done = '1' then
                  if cnt = RAM_WORDS - 1 then
                     fstate <= F_DONE;
                  else
                     cnt    <= cnt + 1;
                     fstate <= F_RAM;
                  end if;
               end if;

            when F_DONE =>
               done_t <= fill_req;
               fstate <= F_IDLE;
         end case;

         if rst = '1' then
            -- abandon a fill and answer any pending request; the engine
            -- restarts its sequence after the reset
            fstate <= F_IDLE;
            done_t <= fill_req;
         end if;
      end if;
   end process;

end architecture;
