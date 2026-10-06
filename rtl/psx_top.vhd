library IEEE;
use IEEE.std_logic_1164.all;  
use IEEE.numeric_std.all;     

library MEM;
use work.pexport.all;
use work.pJoypad.all;

entity psx_top is
   generic
   (
      is_simu               : std_logic := '0';
      -- G-NET trim switches: 1 = upstream block present (default), 0 = removed
      -- and its outputs tied to idle. See docs/f0_budget.md.
      HAS_CD                : integer := 1;
      HAS_PADS              : integer := 1;
      HAS_SAVESTATES        : integer := 1;
      HAS_CHEATS            : integer := 1;
      HAS_MDEC              : integer := 1;
      VRAM_Y_BITS           : integer := 9;   -- 9 = PS1 1 MB VRAM, 10 = ZN-2 2 MB (gpu.vhd)
      GTE_NARROW_MUL        : integer := 0;   -- 1, 2 = 18x18 GTE multipliers plus shifts (gte_mac123.vhd); 3 = GTE at 100 MHz (gte.vhd)
      CLK_FAST_RATIO        : integer := 3;   -- clk3x edges per clk1x cycle: 3 = upstream, 2 = CPU domain at 2:1 (clk3xIndex, sdram.sv)
      -- R1 (docs/r1_cpu_domain_design.md): 0 = upstream clocking, every block on
      -- clk1x/clk2x/clk3x. 1 = CPU group (cpu, gte, memorymux, memctrl, dma,
      -- irq, timer, sio, exp2) on clk_cpu/clk_cpu2x/clk_cpu3x, crossings to the
      -- GPU, SPU and reset sequencer in rtl/gnet/cpu_split (needs the G-NET
      -- trims HAS_CD, HAS_PADS, HAS_SAVESTATES, HAS_CHEATS, HAS_MDEC = 0 and
      -- CLK_FAST_RATIO = 2)
      CPU_CLK_SPLIT         : integer := 0;
      -- G-NET: 1 = ZN-2 board and G-NET FC PCB (rtl/gnet/zn2_board.vhd) on
      -- the expansion bus and SIO0, card image client on DDR3; needs
      -- HAS_PADS = 0. 0 = PS1 (upstream). docs/zn2_layer_design.md 13
      ZN2_BOARD             : integer := 0;
      ZN2_FLASH_PRESET      : integer := 1;   -- gnet_flash timing: 1 = MAME, 2 = 28F160S3 2.7 V, 3 = 28F160S5 (FC PCB part)
      ZN2_PS1_SIO           : integer := 0;   -- zn_sio0: 0 = MAME bit timing, 1 = joypad.vhd rule
      ZN2_SPU_STATUS        : integer := 0;   -- zn2_io 0x1FA60000: 0 = MAME toggle, 1 = bit 3 set
      ZN2_WD_TIMEOUT_S      : integer := 8;   -- MB3773 watchdog period in seconds (zn2_board, gnet_ctrl.sv)
      -- G-NET: 1 = Taito Zoom sound board (rtl/zoom/zoom_board.sv) on clk1x
      -- and clk2x, crossings in rtl/gnet/zoom_cdc.vhd; needs ZN2_BOARD = 1
      -- and CPU_CLK_SPLIT = 1. docs/zoom_board_design.md 14
      ZOOM_BOARD            : integer := 0;
      ZOOM_INFL             : integer := 4;   -- ZSG-2 wave reads outstanding: 4, or 8 behind the DDR3 arbiter
      ZN2_READ_OVERLAP      : integer := 0    -- memorymux: 1 = a ZN-2 read step's request overlaps its read delay (docs/r1_cpu_domain_design.md)
   );
   port 
   (
      clk1x                 : in  std_logic;  
      clk2x                 : in  std_logic;   
      clk3x                 : in  std_logic;   
      clkvid                : in  std_logic;   
      -- CPU group clocks: with CPU_CLK_SPLIT = 0 connect the same signals as
      -- clk1x, clk2x and clk3x; with 1 the CPU PLL's 50 MHz (clk_cpu) and
      -- 100 MHz (clk_cpu2x and clk_cpu3x)
      clk_cpu               : in  std_logic;
      clk_cpu2x             : in  std_logic;
      clk_cpu3x             : in  std_logic;
      reset                 : in  std_logic; 
      isPaused              : out std_logic;
      -- commands 
      pause                 : in  std_logic;
      hps_busy              : in  std_logic;
      loadExe               : in  std_logic;
      exe_initial_pc        : in  unsigned(31 downto 0);
      exe_initial_gp        : in  unsigned(31 downto 0);
      exe_load_address      : in  unsigned(31 downto 0);
      exe_file_size         : in  unsigned(31 downto 0);
      exe_stackpointer      : in  unsigned(31 downto 0);
      fastboot              : in  std_logic;
      ram8mb                : in  std_logic;
      TURBO_MEM             : in  std_logic;
      TURBO_COMP            : in  std_logic;
      TURBO_CACHE           : in  std_logic;
      TURBO_CACHE50         : in  std_logic;
      REPRODUCIBLEGPUTIMING : in  std_logic;
      INSTANTSEEK           : in  std_logic;
      FORCECDSPEED          : in  std_logic_vector(2 downto 0);
      LIMITREADSPEED        : in  std_logic;
      IGNORECDDMATIMING     : in  std_logic;
      ditherOff             : in  std_logic;
      interlaced480pHack    : in  std_logic;
      showGunCrosshairs     : in  std_logic;
      enableNeGconRumble    : in  std_logic;
      fpscountOn            : in  std_logic;
      cdslowOn              : in  std_logic;
      testSeek              : in  std_logic;
      pauseOnCDSlow         : in  std_logic;
      errorOn               : in  std_logic;
      LBAOn                 : in  std_logic;
      PATCHSERIAL           : in  std_logic;
      noTexture             : in  std_logic;
      textureFilter         : in  std_logic_vector(1 downto 0);
      textureFilterStrength : in  std_logic_vector(1 downto 0);
      textureFilter2DOff    : in  std_logic;
      dither24              : in  std_logic;
      render24              : in  std_logic;
      drawSlow              : in  std_logic;
      syncVideoOut          : in  std_logic;
      syncInterlace         : in  std_logic;
      rotate180             : in  std_logic;
      fixedVBlank           : in  std_logic;
      vCrop                 : in  std_logic_vector(1 downto 0);
      hCrop                 : in  std_logic;
      SPUon                 : in  std_logic;
      SPUIRQTrigger         : in  std_logic;
      SPUSDRAM              : in  std_logic;
      REVERBOFF             : in  std_logic;
      REPRODUCIBLESPUDMA    : in  std_logic;
      WIDESCREEN            : in  std_logic_vector(1 downto 0);
	  oldGPU                : in  std_logic;
      -- RAM/BIOS interface  
      biosregion            : in  std_logic_vector(1 downto 0);      
      ram_refresh           : out std_logic;
      ram_dataWrite         : out std_logic_vector(31 downto 0);
      ram_dataRead32        : in  std_logic_vector(31 downto 0);
      ram_Adr               : out std_logic_vector(24 downto 0);
      ram_cntDMA            : out std_logic_vector(1 downto 0);
      ram_be                : out std_logic_vector(3 downto 0) := (others => '0');
      ram_rnw               : out std_logic;
      ram_ena               : out std_logic;
      ram_dma               : out std_logic;
      ram_cache             : out std_logic;
      ram_done              : in  std_logic;
      ram_dmafifo_adr       : out std_logic_vector(22 downto 0);
      ram_dmafifo_data      : out std_logic_vector(31 downto 0);
      ram_dmafifo_empty     : out std_logic;
      ram_dmafifo_read      : in  std_logic;
      cache_wr              : in  std_logic_vector(3 downto 0);
      cache_data            : in  std_logic_vector(31 downto 0);
      cache_addr            : in  std_logic_vector(7 downto 0);
      dma_wr                : in  std_logic;
      dma_reqprocessed      : in  std_logic;
      dma_data              : in  std_logic_vector(31 downto 0);
      -- vram/savestate interface
      ddr3_BUSY             : in  std_logic;                    
      ddr3_DOUT             : in  std_logic_vector(63 downto 0);
      ddr3_DOUT_READY       : in  std_logic;
      ddr3_BURSTCNT         : out std_logic_vector(7 downto 0) := (others => '0'); 
      ddr3_ADDR             : out std_logic_vector(27 downto 0) := (others => '0');                       
      ddr3_DIN              : out std_logic_vector(63 downto 0) := (others => '0');
      ddr3_BE               : out std_logic_vector(7 downto 0) := (others => '0'); 
      ddr3_WE               : out std_logic := '0';
      ddr3_RD               : out std_logic := '0'; 
      -- cd
      region                : in  std_logic_vector(1 downto 0);
      region_out            : out std_logic_vector(1 downto 0);
      hasCD                 : in  std_logic;
      fastCD                : in  std_logic;
      LIDopen               : in  std_logic;
      trackinfo_data        : in  std_logic_vector(31 downto 0);
      trackinfo_addr        : in  std_logic_vector(8 downto 0);
      trackinfo_write       : in  std_logic;
      resetFromCD           : out std_logic;
      cd_hps_req            : out std_logic := '0';
      cd_hps_lba            : out std_logic_vector(31 downto 0);
      cd_hps_lba_sim        : out std_logic_vector(31 downto 0);
      cd_hps_ack            : in  std_logic;
      cd_hps_write          : in  std_logic;
      cd_hps_data           : in  std_logic_vector(15 downto 0);
      -- spuram
      spuram_dataWrite      : out std_logic_vector(31 downto 0);
      spuram_Adr            : out std_logic_vector(18 downto 0);
      spuram_be             : out std_logic_vector(3 downto 0);
      spuram_rnw            : out std_logic;
      spuram_ena            : out std_logic;
      spuram_dataRead       : in  std_logic_vector(31 downto 0);
      spuram_done           : in  std_logic;
      -- memcard
      memcard_changed       : out std_logic;
      saving_memcard        : out std_logic;
      memcard1_load         : in  std_logic;
      memcard2_load         : in  std_logic;
      memcard_save          : in  std_logic;
      memcard1_mounted      : in  std_logic;
      memcard1_available    : in  std_logic;
      memcard1_rd           : out std_logic := '0';
      memcard1_wr           : out std_logic := '0';
      memcard1_lba          : out std_logic_vector(6 downto 0);
      memcard1_ack          : in  std_logic;
      memcard1_write        : in  std_logic;
      memcard1_addr         : in  std_logic_vector(8 downto 0);
      memcard1_dataIn       : in  std_logic_vector(15 downto 0);
      memcard1_dataOut      : out std_logic_vector(15 downto 0);
      memcard2_mounted      : in  std_logic;               
      memcard2_available    : in  std_logic;               
      memcard2_rd           : out std_logic := '0';
      memcard2_wr           : out std_logic := '0';
      memcard2_lba          : out std_logic_vector(6 downto 0);
      memcard2_ack          : in  std_logic;
      memcard2_write        : in  std_logic;
      memcard2_addr         : in  std_logic_vector(8 downto 0);
      memcard2_dataIn       : in  std_logic_vector(15 downto 0);
      memcard2_dataOut      : out std_logic_vector(15 downto 0);
      -- video
      videoout_on           : in  std_logic;
      isPal                 : in  std_logic;
      pal60                 : in  std_logic;
      hsync                 : out std_logic;
      vsync                 : out std_logic;
      hblank                : out std_logic;
      vblank                : out std_logic;
      DisplayWidth          : out unsigned(10 downto 0);
      DisplayHeight         : out unsigned( 9 downto 0);
      DisplayOffsetX        : out unsigned( 9 downto 0);
      DisplayOffsetY        : out unsigned( 8 downto 0);
      video_ce              : out std_logic;
      video_interlace       : out std_logic;
      video_r               : out std_logic_vector(7 downto 0);
      video_g               : out std_logic_vector(7 downto 0);
      video_b               : out std_logic_vector(7 downto 0);
      video_isPal           : out std_logic;
      video_fbmode          : out std_logic;
      video_fb24            : out std_logic;
      video_hResMode        : out std_logic_vector(2 downto 0);
      video_frameindex      : out std_logic_vector(3 downto 0);

      DSAltSwitchMode       : in  std_logic;
      joypad1               : in  joypad_t;
      joypad2               : in  joypad_t;
      joypad3               : in  joypad_t;
      joypad4               : in  joypad_t;
      multitap              : in  std_logic;
      multitapDigital       : in  std_logic;
      multitapAnalog        : in  std_logic;
      neGconRumble          : in  std_logic;
      joypad1_rumble        : out std_logic_vector(15 downto 0);
      joypad2_rumble        : out std_logic_vector(15 downto 0);
      joypad3_rumble        : out std_logic_vector(15 downto 0);
      joypad4_rumble        : out std_logic_vector(15 downto 0);
      padMode               : out std_logic_vector(1 downto 0);

      MouseEvent            : in  std_logic;
      MouseLeft             : in  std_logic;
      MouseRight            : in  std_logic;
      MouseX                : in  signed(8 downto 0);
      MouseY                : in  signed(8 downto 0);
      --snac
      snacPort1             : in  std_logic;
      snacPort2             : in  std_logic;
      irq10Snac             : in  std_logic;
      actionNextSnac        : in  std_logic;
      receiveValidSnac      : in  std_logic;
      ackSnac               : in  std_logic;
      snacMC                : in  std_logic;
      receiveBufferSnac	    : in  std_logic_vector(7 downto 0);
      transmitValueSnac     : out std_logic_vector(7 downto 0);		
      selectedPort1Snac     : out std_logic;
      selectedPort2Snac     : out std_logic;
      clk9Snac              : out std_logic;
      beginTransferSnac     : out std_logic;

      -- sound                            
      sound_out_left        : out std_logic_vector(15 downto 0) := (others => '0');
      sound_out_right       : out std_logic_vector(15 downto 0) := (others => '0');
       -- savestates
      increaseSSHeaderCount : in  std_logic;
      save_state            : in  std_logic;
      load_state            : in  std_logic;
      savestate_number      : in  integer range 0 to 3;
      state_loaded          : out std_logic;
      validSStates          : out std_logic_vector(3 downto 0);
      rewind_on             : in  std_logic;
      rewind_active         : in  std_logic;
      -- cheats
      cheat_clear           : in  std_logic;
      cheats_enabled        : in  std_logic;
      cheat_on              : in  std_logic;
      cheat_in              : in  std_logic_vector(127 downto 0);
      cheats_active         : out std_logic := '0';

      Cheats_BusAddr        : buffer std_logic_vector(20 downto 0);
      Cheats_BusRnW         : out    std_logic;
      Cheats_BusByteEnable  : out    std_logic_vector(3 downto 0);
      Cheats_BusWriteData   : out    std_logic_vector(31 downto 0);
      Cheats_Bus_ena        : out    std_logic := '0';
      Cheats_BusReadData    : in     std_logic_vector(31 downto 0);
      Cheats_BusDone        : in     std_logic;
      
      -- G-NET (ZN2_BOARD = 1 only; defaults keep the upstream instantiation)
      zn_in_p1              : in  std_logic_vector(7 downto 0) := x"FF";
      zn_in_p2              : in  std_logic_vector(7 downto 0) := x"FF";
      zn_in_service         : in  std_logic_vector(7 downto 0) := x"FF";
      zn_in_system          : in  std_logic_vector(7 downto 0) := x"FF";
      zn_dsw                : in  std_logic_vector(3 downto 0) := x"F";
      zn_jp1                : in  std_logic := '0';
      zn_card_present       : in  std_logic := '0';
      zn_key_valid          : in  std_logic := '0';
      zn_coin               : out std_logic_vector(7 downto 0);
      zn_wd_reset           : out std_logic;
      zn_ld_wr              : in  std_logic := '0';
      zn_ld_target          : in  std_logic_vector(1 downto 0) := "00";
      zn_ld_addr            : in  unsigned(10 downto 0) := (others => '0');
      zn_ld_data            : in  std_logic_vector(15 downto 0) := (others => '0');
      zn_ld_busy            : out std_logic;   -- hold the loader (ioctl_wait); CPU_CLK_SPLIT = 1 only
      zn_card_dl_wr         : in  std_logic := '0';
      zn_card_dl_addr       : in  unsigned(25 downto 0) := (others => '0');
      zn_card_dl_data       : in  std_logic_vector(15 downto 0) := (others => '0');
      zn_card_dl_busy       : out std_logic;
      -- flash storage port: clk1x, or clk_cpu with CPU_CLK_SPLIT = 1 (the
      -- SDRAM controller's clk_base); every other zn_* port is on clk1x
      zn_fl_req             : out std_logic;
      zn_fl_rnw             : out std_logic;
      zn_fl_addr            : out std_logic_vector(26 downto 0);
      zn_fl_din             : out std_logic_vector(31 downto 0);
      zn_fl_be              : out std_logic_vector(3 downto 0);
      zn_fl_ready           : in  std_logic := '0';
      zn_fl_dout            : in  std_logic_vector(31 downto 0) := (others => '0');
      -- debug overlay (docs/hw_debug_overlay.md), on clk_cpu: word index in,
      -- word out (combinational from rtl/gnet/zn_dbg_regs.vhd)
      zn_dbg_idx            : in  std_logic_vector(3 downto 0) := (others => '0');
      zn_dbg_word           : out std_logic_vector(31 downto 0);
      -- NVRAM save (docs/m4_shell.md 4): EEPROM copy read on zn_nv_clk
      -- (hps_io's clock); zn_nv_wtog toggles on CPU writes (zn2_board's clock)
      zn_nv_clk             : in  std_logic := '0';
      zn_nv_addr            : in  unsigned(9 downto 0) := (others => '0');
      zn_nv_q               : out std_logic_vector(15 downto 0);
      zn_nv_wtog            : out std_logic;
      -- Taito Zoom (ZOOM_BOARD = 1), all on clk1x: zoom_board's flash area
      -- line port as it is (zoom_memarb m_*: req and line held until an edge
      -- with ready, rvalid one cycle per line in order, up to 8 open; line =
      -- flash area byte offset / 8, flash byte 8L in rdata bits 7:0), for
      -- the DDR3 arbiter or the temporary SDRAM path in PSX.sv; audio
      -- (16-bit signed, volume applied, held per sample); board flags
      -- (zoom_board dbg_flags)
      zoom_m_req            : out std_logic;
      zoom_m_line           : out std_logic_vector(20 downto 0);
      zoom_m_ready          : in  std_logic := '0';
      zoom_m_rvalid         : in  std_logic := '0';
      zoom_m_rdata          : in  std_logic_vector(63 downto 0) := (others => '0');
      zoom_rst              : out std_logic;   -- zoom_board's reset (reset_intern_p, clk1x), for the memory side
      zoom_aud_l            : out std_logic_vector(15 downto 0);
      zoom_aud_r            : out std_logic_vector(15 downto 0);
      zoom_flags            : out std_logic_vector(7 downto 0);
      -- '1' holds the Zoom board's MN10200 at its next instruction boundary
      -- (zoom_board dbg_hold): its time base then stops, so the ZSG-2, the
      -- TMS57002 and the output stage stop too (the output repeats its last
      -- sample). PSX.sv drives it with the core pause (clk1x level, taken on
      -- clk2x, same PLL).
      zoom_hold             : in  std_logic := '0'
   );
end entity;

architecture arch of psx_top is

   signal reset_in               : std_logic := '0';
   signal reset_intern           : std_logic := '0';
   signal reset_exe              : std_logic;
   
   signal ce                     : std_logic := '0';
   signal clk1xToggle            : std_logic := '0';
   signal clk1xToggle2X          : std_logic := '0';
   signal clk2xIndex             : std_logic := '0';

   signal clk1xToggle3X          : std_logic := '0';
   signal clk1xToggle3X_1        : std_logic := '0';
   signal clk3xIndex             : std_logic := '0';
   
   signal Pause_Idle             : std_logic;
   signal pausing                : std_logic := '0';
   signal pausingSS              : std_logic := '0';
   signal allowunpause           : std_logic;
   
   signal pauseCD                : std_logic;
   signal Pause_idle_cd          : std_logic;
   
   -- ddr3 arbiter
   type tddr3State is
   (
      ARBITERIDLE,
      WAITGPUPAUSED,
      REQUEST,
      WAITDONE
   );
   signal ddr3state              : tddr3State := ARBITERIDLE;
   
   signal arbiter_active         : std_logic := '0';
   
   signal memDDR3card1_acknext   : std_logic := '0';
   signal memDDR3card2_acknext   : std_logic := '0';
   signal memHPScard1_acknext    : std_logic := '0';
   signal memHPScard2_acknext    : std_logic := '0';
   signal memSPU_acknext         : std_logic := '0';
   
   signal arbiter_BURSTCNT       : std_logic_vector(7 downto 0) := (others => '0'); 
   signal arbiter_ADDR           : std_logic_vector(27 downto 0) := (others => '0');                       
   signal arbiter_DIN            : std_logic_vector(63 downto 0) := (others => '0');
   signal arbiter_BE             : std_logic_vector(7 downto 0) := (others => '0'); 
   signal arbiter_WE             : std_logic := '0';
   signal arbiter_RD             : std_logic := '0';
   
   signal memDDR3card1_request   : std_logic;
   signal memDDR3card1_ack       : std_logic := '0';
   signal memDDR3card1_BURSTCNT  : std_logic_vector(7 downto 0) := (others => '0'); 
   signal memDDR3card1_ADDR      : std_logic_vector(19 downto 0) := (others => '0');                       
   signal memDDR3card1_DIN       : std_logic_vector(63 downto 0) := (others => '0');
   signal memDDR3card1_BE        : std_logic_vector(7 downto 0) := (others => '0'); 
   signal memDDR3card1_WE        : std_logic := '0';
   signal memDDR3card1_RD        : std_logic := '0';
   
   signal memDDR3card2_request   : std_logic;
   signal memDDR3card2_ack       : std_logic := '0';
   signal memDDR3card2_BURSTCNT  : std_logic_vector(7 downto 0) := (others => '0'); 
   signal memDDR3card2_ADDR      : std_logic_vector(19 downto 0) := (others => '0');                       
   signal memDDR3card2_DIN       : std_logic_vector(63 downto 0) := (others => '0');
   signal memDDR3card2_BE        : std_logic_vector(7 downto 0) := (others => '0'); 
   signal memDDR3card2_WE        : std_logic := '0';
   signal memDDR3card2_RD        : std_logic := '0';
   
   signal memSPU_request         : std_logic;
   -- G-NET card image client (ZN2_BOARD = 1)
   signal memZN_request          : std_logic;
   signal memZN_ack              : std_logic := '0';
   signal memZN_acknext          : std_logic := '0';
   signal memZN_BURSTCNT         : std_logic_vector(7 downto 0) := (others => '0'); 
   signal memZN_ADDR             : std_logic_vector(27 downto 0) := (others => '0');                       
   signal memZN_DIN              : std_logic_vector(63 downto 0) := (others => '0');
   signal memZN_BE               : std_logic_vector(7 downto 0) := (others => '0'); 
   signal memZN_WE               : std_logic := '0';
   signal memZN_RD               : std_logic := '0';
   -- G-NET expansion bus (memorymux ZN2_MAP)
   signal zn_req                 : std_logic;
   signal zn_we                  : std_logic;
   signal zn_addr                : unsigned(23 downto 0);
   signal zn_be                  : std_logic_vector(3 downto 0);
   signal zn_wdata               : std_logic_vector(31 downto 0);
   signal zn_ack                 : std_logic;
   signal zn_rdata               : std_logic_vector(31 downto 0);
   signal zn_cm_req              : std_logic;
   signal zn_cm_we               : std_logic;
   signal zn_cm_addr             : std_logic_vector(24 downto 0);
   signal zn_cm_wdata            : std_logic_vector(15 downto 0);
   signal zn_cm_ack              : std_logic;
   signal zn_cm_rdata            : std_logic_vector(15 downto 0);
   -- debug overlay taps (CPU group clock)
   signal zn_dbg_wd              : std_logic;
   signal zn_dbg_kick            : std_logic;
   signal zn_dbg_ctrl            : std_logic_vector(7 downto 0);
   signal zn_dbg_sec             : std_logic;
   signal cpu_debug_pc           : unsigned(31 downto 0);
   signal memSPU_ack             : std_logic := '0';
   signal memSPU_BURSTCNT        : std_logic_vector(7 downto 0) := (others => '0'); 
   signal memSPU_ADDR            : std_logic_vector(19 downto 0) := (others => '0');                       
   signal memSPU_DIN             : std_logic_vector(63 downto 0) := (others => '0');
   signal memSPU_BE              : std_logic_vector(7 downto 0) := (others => '0'); 
   signal memSPU_WE              : std_logic := '0';
   signal memSPU_RD              : std_logic := '0';

   -- Busses
   signal bios_memctrl           : unsigned(13 downto 0);
   
   signal ex1_memctrl            : unsigned(13 downto 0);
   --signal bus_exp1_addr          : unsigned(22 downto 0); 
   --signal bus_exp1_dataWrite     : std_logic_vector(31 downto 0);
   signal bus_exp1_read          : std_logic;
   --signal bus_exp1_write         : std_logic;
   signal bus_exp1_dataRead      : std_logic_vector(7 downto 0);
   
   signal bus_memc_addr          : unsigned(5 downto 0); 
   signal bus_memc_dataWrite     : std_logic_vector(31 downto 0);
   signal bus_memc_read          : std_logic;
   signal bus_memc_write         : std_logic;
   signal bus_memc_dataRead      : std_logic_vector(31 downto 0);
   
   signal bus_pad_addr           : unsigned(3 downto 0); 
   signal bus_pad_dataWrite      : std_logic_vector(31 downto 0);
   signal bus_pad_read           : std_logic;
   signal bus_pad_write          : std_logic;
   signal bus_pad_writeMask      : std_logic_vector(3 downto 0);
   signal bus_pad_dataRead       : std_logic_vector(31 downto 0);   
   
   signal bus_sio_addr           : unsigned(3 downto 0); 
   signal bus_sio_dataWrite      : std_logic_vector(31 downto 0);
   signal bus_sio_read           : std_logic;
   signal bus_sio_write          : std_logic;
   signal bus_sio_writeMask      : std_logic_vector(3 downto 0);
   signal bus_sio_dataRead       : std_logic_vector(31 downto 0);
   
   signal bus_memc2_addr         : unsigned(3 downto 0); 
   signal bus_memc2_dataWrite    : std_logic_vector(31 downto 0);
   signal bus_memc2_read         : std_logic;
   signal bus_memc2_write        : std_logic;
   signal bus_memc2_dataRead     : std_logic_vector(31 downto 0);
   
   signal bus_irq_addr           : unsigned(3 downto 0); 
   signal bus_irq_dataWrite      : std_logic_vector(31 downto 0);
   signal bus_irq_read           : std_logic;
   signal bus_irq_write          : std_logic;
   signal bus_irq_dataRead       : std_logic_vector(31 downto 0);   
   
   signal bus_dma_addr           : unsigned(6 downto 0); 
   signal bus_dma_dataWrite      : std_logic_vector(31 downto 0);
   signal bus_dma_read           : std_logic;
   signal bus_dma_write          : std_logic;
   signal bus_dma_dataRead       : std_logic_vector(31 downto 0);
   
   signal bus_tmr_addr           : unsigned(5 downto 0); 
   signal bus_tmr_dataWrite      : std_logic_vector(31 downto 0);
   signal bus_tmr_read           : std_logic;
   signal bus_tmr_write          : std_logic;
   signal bus_tmr_dataRead       : std_logic_vector(31 downto 0);
   
   signal cd_memctrl             : unsigned(13 downto 0);
   signal bus_cd_addr            : unsigned(3 downto 0); 
   signal bus_cd_dataWrite       : std_logic_vector(7 downto 0);
   signal bus_cd_read            : std_logic;
   signal bus_cd_write           : std_logic;
   signal bus_cd_dataRead        : std_logic_vector(7 downto 0);
   
   signal bus_gpu_addr           : unsigned(3 downto 0); 
   signal bus_gpu_dataWrite      : std_logic_vector(31 downto 0);
   signal bus_gpu_read           : std_logic;
   signal bus_gpu_write          : std_logic;
   signal bus_gpu_dataRead       : std_logic_vector(31 downto 0);
   signal bus_gpu_stall          : std_logic;
   
   signal bus_mdec_addr          : unsigned(3 downto 0); 
   signal bus_mdec_dataWrite     : std_logic_vector(31 downto 0);
   signal bus_mdec_read          : std_logic;
   signal bus_mdec_write         : std_logic;
   signal bus_mdec_dataRead      : std_logic_vector(31 downto 0);
   
   signal spu_memctrl            : unsigned(13 downto 0);
   signal bus_spu_addr           : unsigned(9 downto 0); 
   signal bus_spu_dataWrite      : std_logic_vector(15 downto 0);
   signal bus_spu_read           : std_logic;
   signal bus_spu_write          : std_logic;
   signal bus_spu_dataRead       : std_logic_vector(15 downto 0);
   
   signal ex2_memctrl            : unsigned(13 downto 0);
   signal bus_exp2_addr          : unsigned(12 downto 0); 
   signal bus_exp2_dataWrite     : std_logic_vector(7 downto 0);
   signal bus_exp2_read          : std_logic;
   signal bus_exp2_write         : std_logic;
   signal bus_exp2_dataRead      : std_logic_vector(7 downto 0);  
   
   signal ex3_memctrl            : unsigned(13 downto 0);
   --signal bus_exp3_dataWrite     : std_logic_vector(7 downto 0);
   signal bus_exp3_read          : std_logic;
   --signal bus_exp3_write         : std_logic;
   signal bus_exp3_dataRead      : std_logic_vector(15 downto 0);
   
   signal com0_delay             : unsigned(3 downto 0);
   signal com1_delay             : unsigned(3 downto 0);
   signal com2_delay             : unsigned(3 downto 0);
   signal com3_delay             : unsigned(3 downto 0);
   
   signal dma_spu_timing_on      : std_logic;
   signal dma_spu_timing_value   : unsigned(3 downto 0);
   
   -- Memory mux
   signal memMuxIdle             : std_logic;
   
   signal mem_request            : std_logic;
   signal mem_rnw                : std_logic; 
   signal mem_isData             : std_logic; 
   signal mem_isCache            : std_logic; 
   signal mem_oldtagvalids       : std_logic_vector(3 downto 0);
   signal mem_addressInstr       : unsigned(31 downto 0); 
   signal mem_addressData        : unsigned(31 downto 0); 
   signal mem_reqsize            : unsigned(1 downto 0); 
   signal mem_writeMask          : std_logic_vector(3 downto 0);
   signal mem_dataWrite          : std_logic_vector(31 downto 0); 
   signal mem_dataRead           : std_logic_vector(31 downto 0); 
   signal mem_done               : std_logic;
   signal mem_fifofull           : std_logic;
   signal mem_tagvalids          : std_logic_vector(3 downto 0);
   
   signal ram_next_cpu           : std_logic;
   
   signal ram_cpu_dataWrite      : std_logic_vector(31 downto 0);
   signal ram_cpu_Adr            : std_logic_vector(24 downto 0);
   signal ram_cpu_be             : std_logic_vector(3 downto 0);
   signal ram_cpu_rnw            : std_logic;
   signal ram_cpu_ena            : std_logic;
   signal ram_cpu_cache          : std_logic;
   signal ram_cpu_done           : std_logic;
   
   -- gpu
   signal vblank_tmr             : std_logic;
   signal hblank_tmr             : std_logic;
   signal dotclock               : std_logic;
   
   signal vram_pause             : std_logic; 
   signal vram_paused            : std_logic; 
   signal vram_BURSTCNT          : std_logic_vector(7 downto 0) := (others => '0'); 
   signal vram_ADDR              : std_logic_vector(27 downto 0) := (others => '0');                       
   signal vram_DIN               : std_logic_vector(63 downto 0) := (others => '0');
   signal vram_BE                : std_logic_vector(7 downto 0) := (others => '0'); 
   signal vram_WE                : std_logic := '0';
   signal vram_RD                : std_logic := '0'; 
   
   -- irq
   signal irqRequest             : std_logic;
   signal irq_VBLANK             : std_logic;
   signal irq_GPU                : std_logic;
   signal irq_CDROM              : std_logic;
   signal irq_DMA                : std_logic;
   signal irq_TIMER0             : std_logic;
   signal irq_TIMER1             : std_logic;
   signal irq_TIMER2             : std_logic;
   signal irq_PAD                : std_logic;
   signal irq_SIO                : std_logic;
   signal irq_SPU                : std_logic;
   signal irq_LIGHTPEN           : std_logic;
   
   -- dma
   signal cpuPaused              : std_logic := '0';
   signal dmaOn                  : std_logic;
   signal dmaRequest             : std_logic;
   signal dmaStallCPU            : std_logic;
   signal canDMA                 : std_logic;
   signal ignoreDMACDTiming      : std_logic;
   
   signal ram_dma_Adr            : std_logic_vector(22 downto 0);
   signal ram_dma_ena            : std_logic;
   
   signal dma_cache_Adr          : std_logic_vector(20 downto 0);
   signal dma_cache_data         : std_logic_vector(31 downto 0);
   signal dma_cache_write        : std_logic;
   
   signal gpu_dmaRequest         : std_logic;
   signal DMA_GPU_waiting        : std_logic;
   signal DMA_GPU_writeEna       : std_logic;
   signal DMA_GPU_readEna        : std_logic;
   signal DMA_GPU_write          : std_logic_vector(31 downto 0);
   signal DMA_GPU_read           : std_logic_vector(31 downto 0);
   
   signal mdec_dmaWriteRequest   : std_logic;
   signal mdec_dmaReadRequest    : std_logic;
   signal DMA_MDEC_writeEna      : std_logic := '0';
   signal DMA_MDEC_readEna       : std_logic := '0';
   signal DMA_MDEC_write         : std_logic_vector(31 downto 0);
   signal DMA_MDEC_read          : std_logic_vector(31 downto 0);
   
   signal DMA_CD_readEna         : std_logic;
   signal DMA_CD_read            : std_logic_vector(7 downto 0);
   
   signal spu_dmaRequest         : std_logic;
   signal DMA_SPU_writeEna       : std_logic := '0';
   signal DMA_SPU_readEna        : std_logic := '0';
   signal DMA_SPU_write          : std_logic_vector(15 downto 0);
   signal DMA_SPU_read           : std_logic_vector(15 downto 0);
   
   -- SPU
   signal spu_tick               : std_logic;
   signal cd_left                : signed(15 downto 0);
   signal cd_right               : signed(15 downto 0);
   
   -- cpu
   signal ce_intern              : std_logic := '0';
   signal stallNext              : std_logic;
   
   -- GTE
   signal gte_busy               : std_logic;
   signal gte_readEna            : std_logic;
   signal gte_readAddr           : unsigned(5 downto 0);
   signal gte_readData           : unsigned(31 downto 0);
   signal gte_writeAddr          : unsigned(5 downto 0);
   signal gte_writeData          : unsigned(31 downto 0);
   signal gte_writeEna           : std_logic; 
   signal gte_cmdData            : unsigned(31 downto 0);
   signal gte_cmdEna             : std_logic; 

   -- overlay + error codes
   signal cdSlow                 : std_logic;
   signal cdslowEna              : std_logic;
   signal errorEna               : std_logic;
   signal errorCode              : unsigned(3 downto 0) := (others => '0');
   signal LBAdisplay             : unsigned(19 downto 0);
   
   signal errorCD                : std_logic;
   signal errorCPU               : std_logic;
   signal errorCPU2              : std_logic;
   signal errorLINE              : std_logic;
   signal errorRECT              : std_logic;
   signal errorPOLY              : std_logic;
   signal errorGPU               : std_logic;
   signal errorMASK              : std_logic;
   signal errorCHOP              : std_logic;
   signal errorGPUFIFO           : std_logic;
   signal errorSPUTIME           : std_logic;
   signal errorDMACPU            : std_logic;
   signal errorDMAFIFO           : std_logic;
   signal errorTimer             : std_logic;
   signal errorBuswidth          : std_logic;
   
   signal debugmodeOn            : std_logic;

   signal Gun1CrosshairOn        : std_logic;
   signal Gun2CrosshairOn        : std_logic;
   signal Gun1X                  : unsigned(7 downto 0);
   signal Gun1Y                  : unsigned(7 downto 0);
   signal Gun2X                  : unsigned(7 downto 0);
   signal Gun2Y                  : unsigned(7 downto 0);
   signal Gun1Y_scanlines        : unsigned(8 downto 0);
   signal Gun2Y_scanlines        : unsigned(8 downto 0);
   signal Gun1AimOffscreen       : std_logic;
   signal Gun2AimOffscreen       : std_logic;   
   signal Gun1offscreen          : std_logic;
   signal Gun2offscreen          : std_logic;
   signal Gun1IRQ10              : std_logic;
   signal Gun2IRQ10              : std_logic;
   signal JustifierIrqEnable     : std_logic_vector(1 downto 0);

   -- memcard
   signal memcard1_pause         : std_logic;
   signal memcard2_pause         : std_logic;
   
   signal MemCard_changePending1 : std_logic;
   signal MemCard_changePending2 : std_logic;   
   
   signal MemCard_saving_memcard1: std_logic;
   signal MemCard_saving_memcard2: std_logic;
   
   signal memHPScard1_request    : std_logic;
   signal memHPScard1_ack        : std_logic := '0';
   signal memHPScard1_BURSTCNT   : std_logic_vector(7 downto 0) := (others => '0'); 
   signal memHPScard1_ADDR       : std_logic_vector(19 downto 0) := (others => '0');                       
   signal memHPScard1_DIN        : std_logic_vector(63 downto 0) := (others => '0');
   signal memHPScard1_BE         : std_logic_vector(7 downto 0) := (others => '0'); 
   signal memHPScard1_WE         : std_logic := '0';
   signal memHPScard1_RD         : std_logic := '0';
                                 
   signal memHPScard2_request    : std_logic;
   signal memHPScard2_ack        : std_logic := '0';
   signal memHPScard2_BURSTCNT   : std_logic_vector(7 downto 0) := (others => '0'); 
   signal memHPScard2_ADDR       : std_logic_vector(19 downto 0) := (others => '0');                       
   signal memHPScard2_DIN        : std_logic_vector(63 downto 0) := (others => '0');
   signal memHPScard2_BE         : std_logic_vector(7 downto 0) := (others => '0'); 
   signal memHPScard2_WE         : std_logic := '0';
   signal memHPScard2_RD         : std_logic := '0';

   -- savestates
   signal loading_savestate      : std_logic;
   signal savestate_pause        : std_logic;
   signal ddr3_savestate         : std_logic;
   
   signal SS_reset               : std_logic;
   
   signal savestate_savestate    : std_logic; 
   signal savestate_loadstate    : std_logic; 
   signal savestate_address      : integer; 
   signal savestate_busy         : std_logic; 
   
   signal SS_DataWrite           : std_logic_vector(31 downto 0);
   signal SS_Adr                 : unsigned(18 downto 0);
   signal SS_wren                : std_logic_vector(16 downto 0);
   signal SS_rden                : std_logic_vector(16 downto 0);
   signal SS_wren_eng            : std_logic_vector(16 downto 0);
   signal SS_rden_eng            : std_logic_vector(16 downto 0);
   signal SS_DataRead_CPU        : std_logic_vector(31 downto 0);
   signal SS_DataRead_GPU        : std_logic_vector(31 downto 0);
   signal SS_DataRead_GPUTiming  : std_logic_vector(31 downto 0);
   signal SS_DataRead_DMA        : std_logic_vector(31 downto 0);
   signal SS_DataRead_GTE        : std_logic_vector(31 downto 0);
   signal SS_DataRead_JOYPAD     : std_logic_vector(31 downto 0);
   signal SS_DataRead_MDEC       : std_logic_vector(31 downto 0);
   signal SS_DataRead_MEMORY     : std_logic_vector(31 downto 0);
   signal SS_DataRead_TIMER      : std_logic_vector(31 downto 0);
   signal SS_DataRead_SOUND      : std_logic_vector(31 downto 0);
   signal SS_DataRead_IRQ        : std_logic_vector(31 downto 0);
   signal SS_DataRead_SIO        : std_logic_vector(31 downto 0);
   signal SS_DataRead_SCP        : std_logic_vector(31 downto 0);
   signal SS_DataRead_CD         : std_logic_vector(31 downto 0);
   
   signal ss_ram_BUSY            : std_logic;                    
   signal ss_ram_DOUT            : std_logic_vector(63 downto 0);
   signal ss_ram_DOUT_READY      : std_logic;
   signal ss_ram_BURSTCNT        : std_logic_vector(7 downto 0) := (others => '0'); 
   signal ss_ram_ADDR            : std_logic_vector(25 downto 0) := (others => '0');                       
   signal ss_ram_DIN             : std_logic_vector(63 downto 0) := (others => '0');
   signal ss_ram_BE              : std_logic_vector(7 downto 0) := (others => '0'); 
   signal ss_ram_WE              : std_logic := '0';
   signal ss_ram_RD              : std_logic := '0'; 
   
   signal SS_SPURAM_dataWrite    : std_logic_vector(15 downto 0);
   signal SS_SPURAM_Adr          : std_logic_vector(18 downto 0);
   signal SS_SPURAM_request      : std_logic;
   signal SS_SPURAM_rnw          : std_logic;
   signal SS_SPURAM_dataRead     : std_logic_vector(15 downto 0);
   signal SS_SPURAM_done         : std_logic;
   
   signal SS_Idle                : std_logic; 
   signal SS_Idle_gpu            : std_logic; 
   signal SS_Idle_mdec           : std_logic; 
   signal SS_Idle_cd             : std_logic; 
   signal SS_Idle_spu            : std_logic; 
   signal SS_idle_pad            : std_logic; 
   signal SS_idle_irq            : std_logic; 
   signal SS_idle_cpu            : std_logic; 
   signal SS_idle_gte            : std_logic; 
   signal SS_idle_dma            : std_logic; 

-- synthesis translate_off
   -- export
   signal cpu_done               : std_logic; 
   signal new_export             : std_logic; 
   signal cpu_export             : cpu_export_type;
   signal export_8               : std_logic_vector(7 downto 0);
   signal export_16              : std_logic_vector(15 downto 0);
   signal export_32              : std_logic_vector(31 downto 0);
   signal export_irq             : unsigned(15 downto 0);
   signal export_gtm             : unsigned(11 downto 0);
   signal export_line            : unsigned(11 downto 0);
   signal export_gpus            : unsigned(31 downto 0);
   signal export_gobj            : unsigned(15 downto 0);
   signal export_t_current0      : unsigned(15 downto 0);
   signal export_t_current1      : unsigned(15 downto 0);
   signal export_t_current2      : unsigned(15 downto 0);
-- synthesis translate_on
   
   signal debug_firstGTE         : std_logic;
   
   -- CPU_CLK_SPLIT: PS1-group (_p) copies of signals that cross, CPU-group
   -- copies (_c) of top-level inputs; with CPU_CLK_SPLIT = 0 plain copies
   signal reset_c                : std_logic;
   signal pause_c                : std_logic;
   signal loadExe_c              : std_logic;
   signal reset_in_c             : std_logic;
   signal reset_exe_p            : std_logic;
   signal clk2xIndex_c           : std_logic;
   signal clk3xIndex_c           : std_logic;
   signal sys_tick               : std_logic;
   signal ce_p                   : std_logic;
   signal pausing_p              : std_logic;
   signal pausingSS_p            : std_logic;
   signal cpuPaused_p            : std_logic;
   signal dmaOn_p                : std_logic;
   signal reset_intern_p         : std_logic;
   signal SS_reset_p             : std_logic;
   signal loading_savestate_p    : std_logic;
   signal savestate_pause_p      : std_logic;
   signal allowunpause_p         : std_logic;
   signal SS_Idle_gpu_p          : std_logic;
   signal SS_idle_spu_p          : std_logic;
   signal SS_idle_p              : std_logic;
   signal SS_DataWrite_p         : std_logic_vector(31 downto 0);
   signal SS_Adr_p               : unsigned(18 downto 0);
   signal SS_wren_p              : std_logic_vector(16 downto 0);
   signal ram_done_p             : std_logic;
   signal ram_cpu_done_p         : std_logic;
   signal ram_dataRead32_p       : std_logic_vector(31 downto 0);
   signal ext_fill_req           : std_logic;
   signal ext_fill_done          : std_logic;
   signal errorEna_p             : std_logic;
   signal errorCode_p            : unsigned(3 downto 0);
   signal debugmodeOn_p          : std_logic;
   signal errorLINE_p            : std_logic;
   signal errorRECT_p            : std_logic;
   signal errorPOLY_p            : std_logic;
   signal errorGPU_p             : std_logic;
   signal errorMASK_p            : std_logic;
   signal errorGPUFIFO_p         : std_logic;
   signal errorSPUTIME_p         : std_logic;
   signal bus_gpu_addr_p         : unsigned(3 downto 0);
   signal bus_gpu_dataWrite_p    : std_logic_vector(31 downto 0);
   signal bus_gpu_read_p         : std_logic;
   signal bus_gpu_write_p        : std_logic;
   signal bus_gpu_dataRead_p     : std_logic_vector(31 downto 0);
   signal bus_gpu_stall_p        : std_logic;
   signal gpu_dmaRequest_p       : std_logic;
   signal DMA_GPU_waiting_p      : std_logic;
   signal DMA_GPU_writeEna_p     : std_logic;
   signal DMA_GPU_readEna_p      : std_logic;
   signal DMA_GPU_write_p        : std_logic_vector(31 downto 0);
   signal DMA_GPU_read_p         : std_logic_vector(31 downto 0);
   signal irq_VBLANK_p           : std_logic;
   signal irq_GPU_p              : std_logic;
   signal irq_SPU_p              : std_logic;
   signal hblank_tmr_p           : std_logic;
   signal vblank_tmr_p           : std_logic;
   signal dotclock_p             : std_logic;
   signal bus_spu_addr_p         : unsigned(9 downto 0);
   signal bus_spu_dataWrite_p    : std_logic_vector(15 downto 0);
   signal bus_spu_read_p         : std_logic;
   signal bus_spu_write_p        : std_logic;
   signal bus_spu_dataRead_p     : std_logic_vector(15 downto 0);
   signal bus_spu_stall          : std_logic;
   signal spu_dmaRequest_p       : std_logic;
   signal DMA_SPU_writeEna_p     : std_logic;
   signal DMA_SPU_readEna_p      : std_logic;
   signal DMA_SPU_write_p        : std_logic_vector(15 downto 0);
   signal DMA_SPU_read_p         : std_logic_vector(15 downto 0);
   signal DMA_SPU_readStall      : std_logic;
   signal DMA_SPU_readReq        : std_logic;

begin 
   
   -- reset
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         reset_in <= reset or reset_exe_p;
      end if;
   end process;
   

   -- clock index
   process (clk1x)
   begin
      if rising_edge(clk1x) then
         clk1xToggle <= not clk1xToggle;
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
   
   -- clk3xIndex: '1' on the first clk3x edge after each clk1x edge (DMA FIFO
   -- write strobe, dma.vhd). The compare depth depends on the clock ratio:
   -- the copy two clk3x cycles old at 3:1 (upstream), one cycle old at 2:1.
   assert CLK_FAST_RATIO = 2 or CLK_FAST_RATIO = 3 report "psx_top: CLK_FAST_RATIO must be 2 or 3" severity failure;

   process (clk3x)
   begin
      if rising_edge(clk3x) then
         clk1xToggle3x   <= clk1xToggle;
         clk1xToggle3X_1 <= clk1xToggle3X;
         clk3xIndex    <= '0';
         if (CLK_FAST_RATIO = 2) then
            if (clk1xToggle3X = clk1xToggle) then
               clk3xIndex <= '1';
            end if;
         elsif (clk1xToggle3X_1 = clk1xToggle) then
            clk3xIndex <= '1';
         end if;
      end if;
   end process;

   -- busses
   process (clk_cpu)
   begin
      if rising_edge(clk_cpu) then
      
         bus_exp1_dataRead <= (others => '0');
         if (bus_exp1_read = '1') then
            bus_exp1_dataRead <= (others => '1');
         end if;
      
         bus_exp3_dataRead <= (others => '0');
         if (bus_exp3_read = '1') then
            bus_exp3_dataRead <= (others => '1');
         end if;
      
      end if;
   end process;
 
   SS_idle    <= SS_Idle_gpu and SS_Idle_mdec and SS_Idle_cd and SS_idle_spu and SS_idle_pad and SS_idle_irq and SS_idle_cpu and SS_idle_gte and SS_idle_dma;
   
   Pause_Idle <= SS_Idle_gpu and SS_Idle_mdec and Pause_idle_cd and SS_idle_spu and SS_idle_pad and SS_idle_irq and SS_idle_cpu and SS_idle_gte and SS_idle_dma; 
   
   -- ce generation
   canDMA <= memMuxIdle;
   
   isPaused <= pausing;
   
   process (clk_cpu)
   begin
      if rising_edge(clk_cpu) then
      
         if (reset_c = '1' or pausing = '1') then
         
            ce        <= '0';
            if (reset_intern = '1') then
               cpuPaused <= '0';
            end if;
            
            if (pause_c = '1') then
               pausing   <= '1';
            end if;
            
            if (pause_c = '0' and savestate_pause = '0' and memcard1_pause = '0' and memcard2_pause = '0' and pauseCD = '0' and allowunpause = '1') then
               pausing   <= '0';
               pausingSS <= '0';
            end if;
            
            if (savestate_pause = '1' and pausingSS = '0' and allowunpause = '1') then -- must go out of pause for savestate if not in a saveable state
               pausing <= '0';
            end if;
         
         else
      
            ce        <= '1';
         
            if (reset_intern = '1') then
               cpuPaused <= '0';
            else
         
               -- switch to pause when CD data fetch is slow
               if ((pauseCD = '1') and cpuPaused = '0' and dmaRequest = '0' and canDMA = '1' and stallNext = '0' and Pause_Idle = '1') then
                  pausing   <= '1';
                  ce        <= '0';
               -- switch to pause/savestate pausing
               elsif ((pause_c = '1' or savestate_pause = '1' or memcard1_pause = '1' or memcard2_pause = '1') and cpuPaused = '0' and dmaRequest = '0' and canDMA = '1' and stallNext = '0' and SS_idle = '1') then
                  pausing   <= '1';
                  pausingSS <= '1';
                  ce        <= '0';
               elsif ((cpuPaused = '1' and dmaOn = '1') or (dmaRequest = '1' and canDMA = '1')) then -- switch to dma
                  cpuPaused <= '1';
               elsif (dmaOn = '0') then -- switch to CPU
                  cpuPaused <= '0';
               end if;
               
            end if;
            
         end if;   
         
         if (reset_in_c = '1') then
            pausing   <= '0';
            pausingSS <= '0';
         end if;
         
      end if;
   end process;
   
   -- error codes
   process (clk_cpu)
   begin
      if rising_edge(clk_cpu) then
         if (reset_intern = '1') then
            errorEna  <= '0';
            errorCode <= x"0";
         else
         
            if (errorEna = '0') then
               if (errorCD       = '1') then errorEna  <= '1'; errorCode <= x"1"; end if;
               if (errorCPU      = '1') then errorEna  <= '1'; errorCode <= x"2"; end if;
               if (errorGPU      = '1') then errorEna  <= '1'; errorCode <= x"3"; end if;
               if (errorMASK     = '1') then errorEna  <= '1'; errorCode <= x"7"; end if;
               if (errorCHOP     = '1') then errorEna  <= '1'; errorCode <= x"8"; end if;
               if (errorGPUFIFO  = '1') then errorEna  <= '1'; errorCode <= x"9"; end if;
               if (errorSPUTIME  = '1') then errorEna  <= '1'; errorCode <= x"A"; end if;
               if (errorDMACPU   = '1') then errorEna  <= '1'; errorCode <= x"B"; end if;
               if (errorDMAFIFO  = '1') then errorEna  <= '1'; errorCode <= x"C"; end if;
               if (errorCPU2     = '1') then errorEna  <= '1'; errorCode <= x"D"; end if;
               if (errorTimer    = '1') then errorEna  <= '1'; errorCode <= x"E"; end if;
               if (errorBuswidth = '1') then errorEna  <= '1'; errorCode <= x"F"; end if;
            end if;
            
            if (errorEna = '0' or errorCode = x"3") then
               if (errorLINE = '1') then errorEna  <= '1'; errorCode <= x"4"; end if;
               if (errorRECT = '1') then errorEna  <= '1'; errorCode <= x"5"; end if;
               if (errorPOLY = '1') then errorEna  <= '1'; errorCode <= x"6"; end if;
            end if;
            
         end if;
         
         debugmodeOn <= '0';
         if (REPRODUCIBLEGPUTIMING = '1') then debugmodeOn <= '1'; end if;
         if (noTexture             = '1') then debugmodeOn <= '1'; end if;
         if (SPUon                 = '0') then debugmodeOn <= '1'; end if;
         if (REVERBOFF             = '1') then debugmodeOn <= '1'; end if;
         if (REPRODUCIBLESPUDMA    = '1') then debugmodeOn <= '1'; end if;
         if (PATCHSERIAL           = '1') then debugmodeOn <= '1'; end if;
         
      end if;
   end process;
   
   -- DDR3 arbiter
   process (clk2x)
   begin
      if rising_edge(clk2x) then
      
         memDDR3card1_ack    <= '0';
         memDDR3card2_ack    <= '0';         
         memHPScard1_ack     <= '0';
         memHPScard2_ack     <= '0';
         memSPU_ack          <= '0';
         memZN_ack           <= '0';
      
         if (reset_intern_p = '1') then
            arbiter_active    <= '0';
            vram_pause        <= '0';
            ddr3state         <= ARBITERIDLE;
            
            memDDR3card1_acknext  <= '0';
            memDDR3card2_acknext  <= '0';            
            memHPScard1_acknext   <= '0';
            memHPScard2_acknext   <= '0';
            memSPU_acknext        <= '0';
            memZN_acknext         <= '0';
         else
         
            case (ddr3state) is
            
               when ARBITERIDLE =>
                  memDDR3card1_acknext  <= '0';
                  memDDR3card2_acknext  <= '0';                  
                  memHPScard1_acknext   <= '0';
                  memHPScard2_acknext   <= '0';
                  memSPU_acknext        <= '0';
                  memZN_acknext         <= '0';
                  if (memDDR3card1_request = '1' or memDDR3card2_request = '1' or memHPScard1_request = '1' or memHPScard2_request = '1' or memSPU_request = '1' or memZN_request = '1') then
                     vram_pause <= '1';
                     ddr3state  <= WAITGPUPAUSED;
                  end if;
                  
               when WAITGPUPAUSED =>
                  if (vram_paused = '1' and ddr3_savestate = '0') then
                     ddr3state      <= REQUEST; 
                     arbiter_active <= '1';
                     if (memDDR3card1_request = '1') then
                        memDDR3card1_acknext <= '1';
                        arbiter_BURSTCNT     <= memDDR3card1_BURSTCNT;
                        arbiter_ADDR         <= x"01" & memDDR3card1_ADDR;    
                        arbiter_DIN          <= memDDR3card1_DIN;     
                        arbiter_BE           <= memDDR3card1_BE;      
                        arbiter_WE           <= memDDR3card1_WE;      
                        arbiter_RD           <= memDDR3card1_RD;
                     elsif (memDDR3card2_request = '1') then
                        memDDR3card2_acknext <= '1';
                        arbiter_BURSTCNT     <= memDDR3card2_BURSTCNT;
                        arbiter_ADDR         <= x"02" & memDDR3card2_ADDR;    
                        arbiter_DIN          <= memDDR3card2_DIN;     
                        arbiter_BE           <= memDDR3card2_BE;      
                        arbiter_WE           <= memDDR3card2_WE;      
                        arbiter_RD           <= memDDR3card2_RD;
                     elsif (memHPScard1_request = '1') then
                        memHPScard1_acknext <= '1';
                        arbiter_BURSTCNT     <= memHPScard1_BURSTCNT;
                        arbiter_ADDR         <= x"01" & memHPScard1_ADDR;    
                        arbiter_DIN          <= memHPScard1_DIN;     
                        arbiter_BE           <= memHPScard1_BE;      
                        arbiter_WE           <= memHPScard1_WE;      
                        arbiter_RD           <= memHPScard1_RD;
                     elsif (memHPScard2_request = '1') then
                        memHPScard2_acknext <= '1';
                        arbiter_BURSTCNT     <= memHPScard2_BURSTCNT;
                        arbiter_ADDR         <= x"02" & memHPScard2_ADDR;    
                        arbiter_DIN          <= memHPScard2_DIN;     
                        arbiter_BE           <= memHPScard2_BE;      
                        arbiter_WE           <= memHPScard2_WE;      
                        arbiter_RD           <= memHPScard2_RD;
                     elsif (memSPU_request = '1') then
                        memSPU_acknext       <= '1';
                        arbiter_BURSTCNT     <= memSPU_BURSTCNT;
                        arbiter_ADDR         <= x"03" & memSPU_ADDR;    
                        arbiter_DIN          <= memSPU_DIN;     
                        arbiter_BE           <= memSPU_BE;      
                        arbiter_WE           <= memSPU_WE;      
                        arbiter_RD           <= memSPU_RD;
                     elsif (memZN_request = '1') then
                        memZN_acknext        <= '1';
                        arbiter_BURSTCNT     <= memZN_BURSTCNT;
                        arbiter_ADDR         <= memZN_ADDR;    
                        arbiter_DIN          <= memZN_DIN;     
                        arbiter_BE           <= memZN_BE;      
                        arbiter_WE           <= memZN_WE;      
                        arbiter_RD           <= memZN_RD;
                     end if;
                  end if;
               
               when REQUEST =>
                  if (ddr3_BUSY = '0') then
                     ddr3state  <= WAITDONE; 
                     arbiter_WE <= '0';     
                     arbiter_RD <= '0';
                     if (memDDR3card1_acknext = '1') then memDDR3card1_ack <= '1'; end if;
                     if (memDDR3card2_acknext = '1') then memDDR3card2_ack <= '1'; end if;                    
                     if (memHPScard1_acknext  = '1') then memHPScard1_ack <= '1';  end if;
                     if (memHPScard2_acknext  = '1') then memHPScard2_ack <= '1';  end if;
                     if (memSPU_acknext       = '1') then memSPU_ack <= '1';       end if;
                     if (memZN_acknext        = '1') then memZN_ack <= '1';        end if;
                  end if;
               
               when WAITDONE =>
                  if (
                      (memDDR3card1_request and memDDR3card1_acknext) = '0' and 
                      (memDDR3card2_request and memDDR3card2_acknext) = '0' and 
                      (memHPScard1_request  and memHPScard1_acknext ) = '0' and 
                      (memHPScard2_request  and memHPScard2_acknext ) = '0' and
                      (memSPU_request       and memSPU_acknext      ) = '0' and
                      (memZN_request        and memZN_acknext       ) = '0'
                     ) then
                     ddr3state      <= ARBITERIDLE;
                     arbiter_active <= '0';
                     vram_pause     <= '0';
                  end if;
               
            end case;
         end if;
      end if;
   end process;
   
   
   imemctrl : entity work.memctrl
   port map
   (
      clk1x                => clk_cpu,
      ce                   => ce,   
      reset                => reset_intern,

      bus_addr             => bus_memc_addr,     
      bus_dataWrite        => bus_memc_dataWrite,
      bus_read             => bus_memc_read,     
      bus_write            => bus_memc_write,    
      bus_dataRead         => bus_memc_dataRead,      
      
      bus2_addr            => bus_memc2_addr,     
      bus2_dataWrite       => bus_memc2_dataWrite,
      bus2_read            => bus_memc2_read,     
      bus2_write           => bus_memc2_write,    
      bus2_dataRead        => bus_memc2_dataRead,
      
      errorBuswidth        => errorBuswidth,
      
      spu_memctrl          => spu_memctrl, 
      cd_memctrl           => cd_memctrl, 
      bios_memctrl         => bios_memctrl, 
      ex1_memctrl          => ex1_memctrl, 
      ex2_memctrl          => ex2_memctrl, 
      ex3_memctrl          => ex3_memctrl, 
      
      com0_delay           => com0_delay,
      com1_delay           => com1_delay,
      com2_delay           => com2_delay,
      com3_delay           => com3_delay,
      
      dma_spu_timing_on    => dma_spu_timing_on,   
      dma_spu_timing_value => dma_spu_timing_value,
      
      loading_savestate    => loading_savestate,
      SS_reset             => SS_reset,
      SS_DataWrite         => SS_DataWrite,
      SS_Adr               => SS_Adr(4 downto 0),      
      SS_wren              => SS_wren(7),     
      SS_rden              => SS_rden(7),     
      SS_DataRead          => SS_DataRead_MEMORY      
   );

   -- Gun coordinate mapping is toplevel so that the gun's
   -- coordinates can be passed to both joypad
   -- and GPU (for crosshair overlays)
   Gun1X <= to_unsigned(to_integer(joypad1.Analog1X + 128), 8);
   Gun2X <= to_unsigned(to_integer(joypad2.Analog1X + 128), 8);

   Gun1Y <= to_unsigned(to_integer(joypad1.Analog1Y + 128), 8);
   Gun2Y <= to_unsigned(to_integer(joypad2.Analog1Y + 128), 8);

   Gun1AimOffscreen <= '1' when Gun1X = x"00" or Gun1X = x"FF" or Gun1Y = x"00" or Gun1Y = x"FF" else '0';
   Gun2AimOffscreen <= '1' when Gun2X = x"00" or Gun2X = x"FF" or Gun2Y = x"00" or Gun2Y = x"FF" else '0';

   Gun1offscreen <= '1' when (Gun1AimOffscreen = '1' or joypad1.KeyTriangle = '1') else '0';
   Gun2offscreen <= '1' when (Gun2AimOffscreen = '1' or joypad2.KeyTriangle = '1') else '0';

   Gun1CrosshairOn <= '1' when
                      showGunCrosshairs = '1' and
                      (joypad1.PadPortGunCon = '1' or joypad1.PadPortJustif = '1') and
                      Gun1AimOffscreen = '0'
                   else '0';
   Gun2CrosshairOn <= '1' when
                      showGunCrosshairs = '1' and
                      (joypad2.PadPortGunCon = '1' or joypad2.PadPortJustif = '1') and
                      Gun2AimOffscreen = '0'
                   else '0';

   -- Map the gun's Y coordinate to 240 scanlines
   Gun1Y_scanlines <= resize(Gun1Y, 9) - resize(Gun1Y(7 downto 4), 9); -- Gun1Y * 240 / 256
   Gun2Y_scanlines <= resize(Gun2Y, 9) - resize(Gun2Y(7 downto 4), 9); -- Gun1Y * 240 / 256

   gjoypad : if HAS_PADS = 1 generate
   begin
   ijoypad: entity work.joypad
   port map 
   (
      clk1x                => clk1x,
      clk2x                => clk2x,
      clk2xIndex           => clk2xIndex,
      ce                   => ce,   
      reset                => reset_intern,

      isPal                => isPal, -- passed through for GunCon
      
      DSAltSwitchMode      => DSAltSwitchMode,
      joypad1              => joypad1,
      joypad2              => joypad2,
      joypad3              => joypad3,
      joypad4              => joypad4,
      multitap             => multitap,
      multitapDigital      => multitapDigital,
      multitapAnalog       => multitapAnalog,
			neGconRumble         => neGconRumble,
      joypad1_rumble       => joypad1_rumble,
      joypad2_rumble       => joypad2_rumble,
      joypad3_rumble       => joypad3_rumble,
      joypad4_rumble       => joypad4_rumble,
      padMode              => padMode,

      memcard1_available   => memcard1_available,
      memcard2_available   => memcard2_available,
      
      irqRequest           => irq_PAD,
      
      MouseEvent           => MouseEvent,
      MouseLeft            => MouseLeft,
      MouseRight           => MouseRight,
      MouseX               => MouseX,
      MouseY               => MouseY,
      Gun1X                => Gun1X,
      Gun2X                => Gun2X,
      Gun1Y_scanlines      => Gun1Y_scanlines,
      Gun2Y_scanlines      => Gun2Y_scanlines,
      Gun1AimOffscreen     => Gun1AimOffscreen,
      Gun2AimOffscreen     => Gun2AimOffscreen,
      JustifierIrqEnable   => JustifierIrqEnable,
      
      snacPort1_in         => snacport1,
      snacPort2_in         => snacport2,      
      selectedPort1Snac    => selectedPort1Snac,
      selectedPort2Snac    => selectedPort2Snac,
      transmitValueSnac    => transmitValueSnac,
      clk9Snac             => clk9Snac,
      receiveBufferSnac	   => receiveBufferSnac,
      beginTransferSnac    => beginTransferSnac,
      actionNextSnac       => actionNextSnac,
      receiveValidSnac     => receiveValidSnac,
      ackSnac              => ackSnac,
      snacMC               => snacMC,
      
      mem1_request         => memDDR3card1_request,   
      mem1_BURSTCNT        => memDDR3card1_BURSTCNT,  
      mem1_ADDR            => memDDR3card1_ADDR,      
      mem1_DIN             => memDDR3card1_DIN,       
      mem1_BE              => memDDR3card1_BE,        
      mem1_WE              => memDDR3card1_WE,        
      mem1_RD              => memDDR3card1_RD,       
      mem1_ack             => memDDR3card1_ack,       
      
      mem2_request         => memDDR3card2_request,   
      mem2_BURSTCNT        => memDDR3card2_BURSTCNT,  
      mem2_ADDR            => memDDR3card2_ADDR,      
      mem2_DIN             => memDDR3card2_DIN,       
      mem2_BE              => memDDR3card2_BE,        
      mem2_WE              => memDDR3card2_WE,        
      mem2_RD              => memDDR3card2_RD,       
      mem2_ack             => memDDR3card2_ack,  
      
      mem_DOUT             => ddr3_DOUT,      
      mem_DOUT_READY       => ddr3_DOUT_READY,
      
      bus_addr             => bus_pad_addr,     
      bus_dataWrite        => bus_pad_dataWrite,
      bus_read             => bus_pad_read,     
      bus_write            => bus_pad_write,    
      bus_writeMask        => bus_pad_writeMask,   
      bus_dataRead         => bus_pad_dataRead,
      
      SS_reset             => SS_reset,
      SS_DataWrite         => SS_DataWrite,
      SS_Adr               => SS_Adr(2 downto 0),      
      SS_wren              => SS_wren(5),     
      SS_rden              => SS_rden(5),     
      SS_DataRead          => SS_DataRead_JOYPAD,
      SS_idle              => SS_idle_pad
   );
   end generate;
   gnopadbus : if HAS_PADS = 0 and ZN2_BOARD = 0 generate
   begin
      irq_PAD              <= '0';
      bus_pad_dataRead     <= (others => '0');
   end generate;

   gnojoypad : if HAS_PADS = 0 generate
   begin
      joypad1_rumble       <= (others => '0');
      joypad2_rumble       <= (others => '0');
      joypad3_rumble       <= (others => '0');
      joypad4_rumble       <= (others => '0');
      padMode              <= (others => '0');
      JustifierIrqEnable   <= (others => '0');
      selectedPort1Snac    <= '0';
      selectedPort2Snac    <= '0';
      transmitValueSnac    <= (others => '0');
      clk9Snac             <= '0';
      beginTransferSnac    <= '0';
      memDDR3card1_request <= '0';
      memDDR3card2_request <= '0';
      SS_DataRead_JOYPAD   <= (others => '0');
      SS_idle_pad          <= '1';
   end generate;
   
   gcheats : if HAS_CHEATS = 1 generate
   begin
   icheats : entity work.cheats
   port map
   (
      clk1x          => clk1x,
      ce             => ce,
      reset          => reset_intern,

      dmaOn          => dmaOn,

      cheat_clear    => cheat_clear,
      cheats_enabled => cheats_enabled,
      cheat_on       => cheat_on,
      cheat_in       => cheat_in,
      cheats_active  => cheats_active,

      vsync          => IRQ_VBlank,

      --bus_ena_in     => mem_bus_ena,

      BusAddr        => Cheats_BusAddr,
      BusRnW         => Cheats_BusRnW,
      BusByteEnable  => Cheats_BusByteEnable,
      BusWriteData   => Cheats_BusWriteData,
      Bus_ena        => Cheats_Bus_ena,
      BusReadData    => Cheats_BusReadData,
      BusDone        => Cheats_BusDone
   );
   end generate;
   gnocheats : if HAS_CHEATS = 0 generate
   begin
      Cheats_BusAddr       <= (others => '0');
      Cheats_BusRnW        <= '1';
      Cheats_BusByteEnable <= (others => '0');
      Cheats_BusWriteData  <= (others => '0');
   end generate;

   isio : entity work.sio
   port map
   (
      clk1x                => clk_cpu,
      ce                   => ce,   
      reset                => reset_intern,
      
      bus_addr             => bus_sio_addr,     
      bus_dataWrite        => bus_sio_dataWrite,
      bus_read             => bus_sio_read,     
      bus_write            => bus_sio_write,    
      bus_writeMask        => bus_sio_writeMask,
      bus_dataRead         => bus_sio_dataRead,
      
      loading_savestate    => loading_savestate,
      SS_reset             => SS_reset,
      SS_DataWrite         => SS_DataWrite,
      SS_Adr               => SS_Adr(2 downto 0),      
      SS_wren              => SS_wren(11),     
      SS_rden              => SS_rden(11),     
      SS_DataRead          => SS_DataRead_SIO
   );
   
   irq_SIO       <= '0'; -- todo
   irq_LIGHTPEN  <= '1' when
                    (irq10Snac = '1' and snacport1 = '1') or
                    (irq10Snac = '1' and snacport2 = '1') or
                    (Gun1IRQ10 = '1' and joypad1.PadPortJustif = '1' and JustifierIrqEnable(0) = '1') or
                    (Gun2IRQ10 = '1' and joypad2.PadPortJustif = '1' and JustifierIrqEnable(1) = '1')
                 else '0';

   iirq : entity work.irq
   port map
   (
      clk1x                => clk_cpu,
      ce                   => ce,   
      reset                => reset_intern,
      
      irq_VBLANK           => irq_VBLANK,
      irq_GPU              => irq_GPU,     
      irq_CDROM            => irq_CDROM,   
      irq_DMA              => irq_DMA,     
      irq_TIMER0           => irq_TIMER0,  
      irq_TIMER1           => irq_TIMER1,  
      irq_TIMER2           => irq_TIMER2,  
      irq_PAD              => irq_PAD,     
      irq_SIO              => irq_SIO,     
      irq_SPU              => irq_SPU,     
      irq_LIGHTPEN         => irq_LIGHTPEN,
      
      bus_addr             => bus_irq_addr,     
      bus_dataWrite        => bus_irq_dataWrite,
      bus_read             => bus_irq_read,     
      bus_write            => bus_irq_write,    
      bus_dataRead         => bus_irq_dataRead,
      
      irqRequest           => irqRequest,

-- synthesis translate_off
      export_irq           => export_irq,
-- synthesis translate_on
      
      SS_reset             => SS_reset,
      SS_DataWrite         => SS_DataWrite,
      SS_Adr               => SS_Adr(0 downto 0),      
      SS_wren              => SS_wren(10),     
      SS_rden              => SS_rden(10),     
      SS_DataRead          => SS_DataRead_IRQ,
      SS_idle              => SS_idle_irq
   );
   
   ignoreDMACDTiming <= '1' when (TURBO_MEM = '1' or IGNORECDDMATIMING = '1' or unsigned(FORCECDSPEED) >= 3) else '0';
   
   idma : entity work.dma
   port map
   (
      clk1x                => clk_cpu,
      clk3x                => clk_cpu3x,
      clk3xIndex           => clk3xIndex_c,
      ce                   => ce,   
      reset                => reset_intern,
      
      errorCHOP            => errorCHOP, 
      errorDMACPU          => errorDMACPU, 
      errorDMAFIFO         => errorDMAFIFO, 
      
      TURBO                => TURBO_COMP,
      TURBO_CACHE          => TURBO_CACHE,
      ram8mb               => ram8mb,
      ignoreCDTiming       => ignoreDMACDTiming,
      
      canDMA               => canDMA,
      cpuPaused            => cpuPaused,
      dmaRequest           => dmaRequest,
      dmaStallCPU          => dmaStallCPU,
      dmaOn                => dmaOn,
      irqOut               => irq_DMA,
      
      ram_Adr              => ram_dma_Adr,  
      ram_cnt              => ram_cntDMA,  
      ram_ena              => ram_dma_ena,
      
      dma_wr               => dma_wr, 
      dma_reqprocessed     => dma_reqprocessed,      
      dma_data             => dma_data,
      
      ram_dmafifo_adr      => ram_dmafifo_adr, 
      ram_dmafifo_data     => ram_dmafifo_data,
      ram_dmafifo_empty    => ram_dmafifo_empty,
      ram_dmafifo_read     => ram_dmafifo_read, 

      dma_cache_Adr        => dma_cache_Adr,  
      dma_cache_data       => dma_cache_data, 
      dma_cache_write      => dma_cache_write,      
      
      gpu_dmaRequest       => gpu_dmaRequest,  
      DMA_GPU_waiting      => DMA_GPU_waiting,
      DMA_GPU_writeEna     => DMA_GPU_writeEna,
      DMA_GPU_readEna      => DMA_GPU_readEna, 
      DMA_GPU_write        => DMA_GPU_write,   
      DMA_GPU_read         => DMA_GPU_read,   
      
      mdec_dmaWriteRequest => mdec_dmaWriteRequest,
      mdec_dmaReadRequest  => mdec_dmaReadRequest, 
      DMA_MDEC_writeEna    => DMA_MDEC_writeEna,   
      DMA_MDEC_readEna     => DMA_MDEC_readEna,    
      DMA_MDEC_write       => DMA_MDEC_write,      
      DMA_MDEC_read        => DMA_MDEC_read,   

      cd_memctrl           => cd_memctrl,
      com0_delay           => com0_delay,
      DMA_CD_readEna       => DMA_CD_readEna,
      DMA_CD_read          => DMA_CD_read,   
      
      spu_timing_on        => dma_spu_timing_on,   
      spu_timing_value     => dma_spu_timing_value,
      spu_dmaRequest       => spu_dmaRequest, 
      DMA_SPU_writeEna     => DMA_SPU_writeEna,   
      DMA_SPU_readEna      => DMA_SPU_readEna,    
      DMA_SPU_write        => DMA_SPU_write,    
      DMA_SPU_read         => DMA_SPU_read,
      DMA_SPU_readStall    => DMA_SPU_readStall,
      DMA_SPU_readReq      => DMA_SPU_readReq,
      
      bus_addr             => bus_dma_addr,     
      bus_dataWrite        => bus_dma_dataWrite,
      bus_read             => bus_dma_read,     
      bus_write            => bus_dma_write,    
      bus_dataRead         => bus_dma_dataRead,
      
      loading_savestate    => loading_savestate,
      SS_reset             => SS_reset,
      SS_DataWrite         => SS_DataWrite,
      SS_Adr               => SS_Adr(5 downto 0),      
      SS_wren              => SS_wren(3),     
      SS_rden              => SS_rden(3),     
      SS_DataRead          => SS_DataRead_DMA,
      SS_idle              => SS_idle_dma
   );
   
   ram_refresh   <= reset_intern;
   
   ram_dataWrite <=                                                ram_cpu_dataWrite;
   ram_be        <=                                                ram_cpu_be;       
   ram_rnw       <= '1'                when (cpuPaused = '1') else ram_cpu_rnw;      
   ram_ena       <= ram_dma_ena        when (cpuPaused = '1') else ram_cpu_ena;      
   ram_dma       <= '1'                when (cpuPaused = '1') else '0';      
   ram_cache     <= '0'                when (cpuPaused = '1') else ram_cpu_cache;    
   
   ram_Adr       <=   "00" & ram_dma_Adr(22 downto 0) when (cpuPaused = '1' and ram8mb = '1') else 
                    "0000" & ram_dma_Adr(20 downto 0) when (cpuPaused = '1' and ram8mb = '0') else 
                    ram_cpu_Adr(24 downto 23) &        ram_cpu_Adr(22 downto 0) when (ram8mb = '1') else
                    ram_cpu_Adr(24 downto 23) & "00" & ram_cpu_Adr(20 downto 0);
   
   process (clk_cpu)
   begin
      if rising_edge(clk_cpu) then
      
         if (ram_ena = '1') then
            ram_next_cpu <= '0';
            if (cpuPaused = '0') then
               ram_next_cpu <= '1';
            end if;
         end if;
      
      end if;
   end process;
   
   ram_cpu_done <= ram_done and ram_next_cpu;
   
   itimer : entity work.timer
   port map
   (
      clk1x                => clk_cpu,
      ce                   => ce,   
      reset                => reset_intern,
      sys_tick             => sys_tick,
      
      error                => errorTimer,
      
      dotclock             => dotclock,
      hblank               => hblank_tmr,
      vblank               => vblank_tmr,
      
      irqRequest0          => irq_TIMER0,
      irqRequest1          => irq_TIMER1,
      irqRequest2          => irq_TIMER2,
      
      bus_addr             => bus_tmr_addr,     
      bus_dataWrite        => bus_tmr_dataWrite,
      bus_read             => bus_tmr_read,     
      bus_write            => bus_tmr_write,       
      bus_dataRead         => bus_tmr_dataRead,
      
-- synthesis translate_off
      export_t_current0    => export_t_current0,
      export_t_current1    => export_t_current1,
      export_t_current2    => export_t_current2,
-- synthesis translate_on
      
      loading_savestate    => loading_savestate,
      SS_reset             => SS_reset,
      SS_DataWrite         => SS_DataWrite,
      SS_Adr               => SS_Adr(3 downto 0),      
      SS_wren              => SS_wren(8),     
      SS_rden              => SS_rden(8),     
      SS_DataRead          => SS_DataRead_TIMER
   );
   
   gcd : if HAS_CD = 1 generate
   begin
   icd_top : entity work.cd_top
   port map
   (
      clk1x                => clk1x,
      ce                   => ce,   
      reset                => reset_intern,
     
      INSTANTSEEK          => INSTANTSEEK,
      FORCECDSPEED         => FORCECDSPEED,
      LIMITREADSPEED       => LIMITREADSPEED,
      hasCD                => hasCD,
      fastCD               => fastCD,
      testSeek             => testSeek,
      pauseOnCDSlow        => pauseOnCDSlow,
      LIDopen              => LIDopen,
      region               => region,
      region_out           => region_out,	  
      
      pauseCD              => pauseCD,
      Pause_idle_cd        => Pause_idle_cd,
      cdSlow               => cdSlow,
      error                => errorCD,
      LBAdisplay           => LBAdisplay,
          
      irqOut               => irq_CDROM,
      
      spu_tick             => spu_tick,
      cd_left              => cd_left,
      cd_right             => cd_right,
      
      mdec_idle            => SS_Idle_mdec,
                            
      bus_addr             => bus_cd_addr,     
      bus_dataWrite        => bus_cd_dataWrite,
      bus_read             => bus_cd_read,     
      bus_write            => bus_cd_write,     
      bus_dataRead         => bus_cd_dataRead,
                            
      dma_read             => DMA_CD_readEna,
      dma_readdata         => DMA_CD_read,
      
      cd_hps_req           => cd_hps_req,  
      cd_hps_lba           => cd_hps_lba,
      cd_hps_lba_sim       => cd_hps_lba_sim,
      cd_hps_ack           => cd_hps_ack,
      cd_hps_write         => cd_hps_write,
      cd_hps_data          => cd_hps_data, 
      
      trackinfo_data       => trackinfo_data,
      trackinfo_addr       => trackinfo_addr, 
      trackinfo_write      => trackinfo_write,
      resetFromCD          => resetFromCD,
      
      SS_reset             => SS_reset,
      SS_DataWrite         => SS_DataWrite,
      SS_Adr               => SS_Adr(13 downto 0),      
      SS_wren              => SS_wren(13),     
      SS_rden              => SS_rden(13),     
      SS_DataRead          => SS_DataRead_CD,
      SS_Idle              => SS_Idle_cd
   );
   end generate;
   gnocd : if HAS_CD = 0 generate
   begin
      region_out           <= region;
      pauseCD              <= '0';
      Pause_idle_cd        <= '1';
      cdSlow               <= '0';
      errorCD              <= '0';
      LBAdisplay           <= (others => '0');
      irq_CDROM            <= '0';
      cd_left              <= (others => '0');
      cd_right             <= (others => '0');
      bus_cd_dataRead      <= (others => '0');
      DMA_CD_read          <= (others => '0');
      cd_hps_lba           <= (others => '0');
      cd_hps_lba_sim       <= (others => '0');
      resetFromCD          <= '0';
      SS_DataRead_CD       <= (others => '0');
      SS_Idle_cd           <= '1';
   end generate;

   cdslowEna <= cdSlow and cdslowOn;

   igpu : entity work.gpu
   generic map (VRAM_Y_BITS => VRAM_Y_BITS)
   port map
   (
      clk1x                => clk1x,
      clk2x                => clk2x,
      clk2xIndex           => clk2xIndex,
      clkvid               => clkvid,
      ce                   => ce_p,   
      reset                => reset_intern_p,
      
      allowunpause         => allowunpause_p,
      savestate_busy       => savestate_busy,
      system_paused        => pausing_p,
      
      ditherOff            => ditherOff,
      interlaced480pHack   => interlaced480pHack,
      REPRODUCIBLEGPUTIMING=> REPRODUCIBLEGPUTIMING,
      videoout_on          => videoout_on,
      isPal                => isPal,
      pal60                => pal60,
      fpscountOn           => fpscountOn,
      noTexture            => noTexture,
      textureFilter        => textureFilter,
      textureFilterStrength=> textureFilterStrength,
      textureFilter2DOff   => textureFilter2DOff,
      dither24             => dither24,
      render24             => render24,
      drawSlow             => drawSlow,
      debugmodeOn          => debugmodeOn_p,
      syncVideoOut         => syncVideoOut,
      syncInterlace        => syncInterlace,
      rotate180            => rotate180,
      fixedVBlank          => fixedVBlank,
      vCrop                => vCrop,   
      hCrop                => hCrop,   
      
	  oldGPU               => oldGPU,
	  
      Gun1CrosshairOn      => Gun1CrosshairOn,
      Gun1X                => Gun1X,
      Gun1Y_scanlines      => Gun1Y_scanlines,
      Gun1offscreen        => Gun1offscreen,
      Gun1IRQ10            => Gun1IRQ10,

      Gun2CrosshairOn      => Gun2CrosshairOn,
      Gun2X                => Gun2X,
      Gun2Y_scanlines      => Gun2Y_scanlines,
      Gun2offscreen        => Gun2offscreen,
      Gun2IRQ10            => Gun2IRQ10,

      cdSlow               => cdslowEna,
      
      errorOn              => errorOn,  
      errorEna             => errorEna_p, 
      errorCode            => errorCode_p,
      
      LBAOn                => LBAOn,
      LBAdisplay           => LBAdisplay,
      
      errorLINE            => errorLINE_p,
      errorRECT            => errorRECT_p,
      errorPOLY            => errorPOLY_p,
      errorGPU             => errorGPU_p, 
      errorMASK            => errorMASK_p, 
      errorFIFO            => errorGPUFIFO_p,
      
      bus_addr             => bus_gpu_addr_p,     
      bus_dataWrite        => bus_gpu_dataWrite_p,
      bus_read             => bus_gpu_read_p,     
      bus_write            => bus_gpu_write_p,    
      bus_dataRead         => bus_gpu_dataRead_p, 
      bus_stall            => bus_gpu_stall_p, 
      
      dmaOn                => dmaOn_p,
      gpu_dmaRequest       => gpu_dmaRequest_p,  
      DMA_GPU_waiting      => DMA_GPU_waiting_p,
      DMA_GPU_writeEna     => DMA_GPU_writeEna_p,
      DMA_GPU_readEna      => DMA_GPU_readEna_p, 
      DMA_GPU_write        => DMA_GPU_write_p,   
      DMA_GPU_read         => DMA_GPU_read_p,  
      
      irq_VBLANK           => irq_VBLANK_p,
      irq_GPU              => irq_GPU_p,
      
      vram_pause           => vram_pause, 
      vram_paused          => vram_paused,
      vram_BUSY            => ddr3_BUSY,       
      vram_DOUT            => ddr3_DOUT,       
      vram_DOUT_READY      => ddr3_DOUT_READY,
      vram_BURSTCNT        => vram_BURSTCNT,  
      vram_ADDR            => vram_ADDR,      
      vram_DIN             => vram_DIN,       
      vram_BE              => vram_BE,        
      vram_WE              => vram_WE,        
      vram_RD              => vram_RD, 

      hblank_tmr           => hblank_tmr_p,
      vblank_tmr           => vblank_tmr_p,
      dotclock             => dotclock_p,
      
      video_hsync          => hsync, 
      video_vsync          => vsync, 
      video_hblank         => hblank,
      video_vblank         => vblank,
      video_DisplayWidth   => DisplayWidth, 
      video_DisplayHeight  => DisplayHeight,
      video_DisplayOffsetX => DisplayOffsetX,
      video_DisplayOffsetY => DisplayOffsetY,
      video_ce             => video_ce,
      video_interlace      => video_interlace,
      video_r              => video_r, 
      video_g              => video_g, 
      video_b              => video_b, 
      video_isPal          => video_isPal, 
      video_fbmode         => video_fbmode, 
      video_fb24           => video_fb24, 
      video_hResMode       => video_hResMode, 
      video_frameindex     => video_frameindex,
      
-- synthesis translate_off
      export_gtm           => export_gtm,
      export_line          => export_line,
      export_gpus          => export_gpus,
      export_gobj          => export_gobj,
-- synthesis translate_on
      
      loading_savestate    => loading_savestate_p,
      SS_reset             => SS_reset_p,
      SS_DataWrite         => SS_DataWrite_p,
      SS_Adr               => SS_Adr_p(2 downto 0),
      SS_wren_GPU          => SS_wren_p(1),     
      SS_wren_Timing       => SS_wren_p(2),      
      SS_rden_GPU          => SS_rden(1),     
      SS_rden_Timing       => SS_rden(2),
      SS_DataRead_GPU      => SS_DataRead_GPU,
      SS_DataRead_Timing   => SS_DataRead_GPUTiming,
      SS_Idle              => SS_Idle_gpu_p
   );
   
   gmdec : if HAS_MDEC = 1 generate
   begin
   imdec : entity work.mdec
   port map
   (
      clk1x                => clk1x,     
      clk2x                => clk2x,    
      clk2xIndex           => clk2xIndex,
      ce                   => ce,        
      reset                => reset_intern,     
      
      bus_addr             => bus_mdec_addr,     
      bus_dataWrite        => bus_mdec_dataWrite,
      bus_read             => bus_mdec_read,     
      bus_write            => bus_mdec_write,    
      bus_dataRead         => bus_mdec_dataRead, 
      
      dmaWriteRequest      => mdec_dmaWriteRequest,
      dmaReadRequest       => mdec_dmaReadRequest, 
      dma_write            => DMA_MDEC_writeEna,   
      dma_writedata        => DMA_MDEC_write,    
      dma_read             => DMA_MDEC_readEna,      
      dma_readdata         => DMA_MDEC_read,

      SS_reset             => SS_reset,
      SS_DataWrite         => SS_DataWrite,
      SS_Adr               => SS_Adr(6 downto 0),      
      SS_wren              => SS_wren(6),     
      SS_rden              => SS_rden(6),     
      SS_DataRead          => SS_DataRead_MDEC,
      SS_Idle              => SS_Idle_mdec
   );
   end generate;
   gnomdec : if HAS_MDEC = 0 generate
   begin
      bus_mdec_dataRead    <= (others => '0');
      mdec_dmaWriteRequest <= '0';
      mdec_dmaReadRequest  <= '0';
      DMA_MDEC_read        <= (others => '0');
      SS_DataRead_MDEC     <= (others => '0');
      SS_Idle_mdec         <= '1';
   end generate;

   ispu : entity work.spu
   port map
   (
      clk1x                => clk1x,   
      clk2x                => clk2x,    
      clk2xIndex           => clk2xIndex,      
      ce                   => ce_p,        
      reset                => reset_intern_p,     
      
      SPUon                => SPUon,
      SPUIRQTrigger        => SPUIRQTrigger,
      useSDRAM             => SPUSDRAM,
      REPRODUCIBLESPUIRQ   => '1',
      REPRODUCIBLESPUDMA   => REPRODUCIBLESPUDMA,
      REVERBOFF            => REVERBOFF,
      
      cpuPaused            => cpuPaused_p,
      
      spu_tick             => spu_tick,
      cd_left              => cd_left,
      cd_right             => cd_right,
      
      irqOut               => irq_SPU_p,
      
      sound_timeout        => errorSPUTIME_p,
      
      sound_out_left       => sound_out_left, 
      sound_out_right      => sound_out_right,
      
      bus_addr             => bus_spu_addr_p,     
      bus_dataWrite        => bus_spu_dataWrite_p,
      bus_read             => bus_spu_read_p,     
      bus_write            => bus_spu_write_p,    
      bus_dataRead         => bus_spu_dataRead_p, 
      
      spu_dmaRequest       => spu_dmaRequest_p, 
      dma_read             => DMA_SPU_readEna_p,      
      dma_readdata         => DMA_SPU_read_p, 
      dma_write            => DMA_SPU_writeEna_p, 
      dma_writedata        => DMA_SPU_write_p,
          
      sdram_dataWrite      => spuram_dataWrite,
      sdram_dataRead       => spuram_dataRead, 
      sdram_Adr            => spuram_Adr,      
      sdram_be             => spuram_be,      
      sdram_rnw            => spuram_rnw,      
      sdram_ena            => spuram_ena,           
      sdram_done           => spuram_done,
      
      mem_request          => memSPU_request,  
      mem_BURSTCNT         => memSPU_BURSTCNT, 
      mem_ADDR             => memSPU_ADDR,     
      mem_DIN              => memSPU_DIN,      
      mem_BE               => memSPU_BE,       
      mem_WE               => memSPU_WE,       
      mem_RD               => memSPU_RD,       
      mem_ack              => memSPU_ack,      
      mem_DOUT             => ddr3_DOUT,      
      mem_DOUT_READY       => ddr3_DOUT_READY,
      
      SS_reset             => SS_reset_p,
      loading_savestate    => loading_savestate_p,
      SS_DataWrite         => SS_DataWrite_p,
      SS_Adr               => SS_Adr_p(8 downto 0),  
      SS_wren              => SS_wren_p(9),     
      SS_rden              => SS_rden(9),     
      SS_DataRead          => SS_DataRead_SOUND,
      SS_idle              => SS_idle_spu_p,
      
      SS_RAM_dataWrite     => SS_SPURAM_dataWrite,
      SS_RAM_Adr           => SS_SPURAM_Adr,      
      SS_RAM_request       => SS_SPURAM_request,  
      SS_RAM_rnw           => SS_SPURAM_rnw,      
      SS_RAM_dataRead      => SS_SPURAM_dataRead, 
      SS_RAM_done          => SS_SPURAM_done     
   );
   
   iexp2 : entity work.exp2
   port map
   (
      clk1x                => clk_cpu,
      ce                   => ce,   
      reset                => reset_intern,
      
      bus_addr             => bus_exp2_addr,     
      bus_dataWrite        => bus_exp2_dataWrite,
      bus_read             => bus_exp2_read,     
      bus_write            => bus_exp2_write,    
      bus_dataRead         => bus_exp2_dataRead
   );

   imemorymux : entity work.memorymux
   generic map
   (
      ZN2_MAP              => ZN2_BOARD,
      ZN2_READ_OVERLAP     => ZN2_READ_OVERLAP
   )
   port map
   (
      clk1x                => clk_cpu,
      clk2x                => clk_cpu2x,
      ce                   => ce,   
      reset                => reset_intern,
      
      pauseNext            => cpuPaused or (dmaRequest and canDMA),
      isIdle               => memMuxIdle,
         
      loadExe              => loadExe_c,
      exe_initial_pc       => exe_initial_pc,  
      exe_initial_gp       => exe_initial_gp,  
      exe_load_address     => exe_load_address,
      exe_file_size        => exe_file_size,   
      exe_stackpointer     => exe_stackpointer,
      reset_exe            => reset_exe,
      
      fastboot             => fastboot,
      TURBO                => TURBO_MEM,
      region_in            => biosregion,
      PATCHSERIAL          => PATCHSERIAL,
            
      ram_dataWrite        => ram_cpu_dataWrite,
      ram_dataRead         => ram_dataRead32,  
      ram_Adr              => ram_cpu_Adr,  
      ram_be               => ram_cpu_be,        
      ram_rnw              => ram_cpu_rnw,      
      ram_ena              => ram_cpu_ena,   
      ram_cache            => ram_cpu_cache,      
      ram_done             => ram_cpu_done,
      
      mem_in_request       => mem_request,  
      mem_in_rnw           => mem_rnw,      
      mem_in_isData        => mem_isData,      
      mem_in_isCache       => mem_isCache,      
      mem_in_oldtagvalids  => mem_oldtagvalids,  
      mem_in_addressInstr  => mem_addressInstr,  
      mem_in_addressData   => mem_addressData,  
      mem_in_reqsize       => mem_reqsize,  
      mem_in_writeMask     => mem_writeMask,
      mem_in_dataWrite     => mem_dataWrite,
      mem_dataRead         => mem_dataRead, 
      mem_done             => mem_done,
      mem_fifofull         => mem_fifofull,  
      mem_tagvalids        => mem_tagvalids,

      bios_memctrl         => bios_memctrl,

      ex1_memctrl          => ex1_memctrl,
      --bus_exp1_addr        => bus_exp1_addr,   
      --bus_exp1_dataWrite   => bus_exp1_dataWrite,
      bus_exp1_read        => bus_exp1_read,   
      --bus_exp1_write       => bus_exp1_write,  
      bus_exp1_dataRead    => bus_exp1_dataRead,
      
      bus_memc_addr        => bus_memc_addr,     
      bus_memc_dataWrite   => bus_memc_dataWrite,
      bus_memc_read        => bus_memc_read,     
      bus_memc_write       => bus_memc_write,    
      bus_memc_dataRead    => bus_memc_dataRead,   
      
      bus_pad_addr         => bus_pad_addr,     
      bus_pad_dataWrite    => bus_pad_dataWrite,
      bus_pad_read         => bus_pad_read,     
      bus_pad_write        => bus_pad_write,    
      bus_pad_writeMask    => bus_pad_writeMask,
      bus_pad_dataRead     => bus_pad_dataRead,       
      
      bus_sio_addr         => bus_sio_addr,     
      bus_sio_dataWrite    => bus_sio_dataWrite,
      bus_sio_read         => bus_sio_read,     
      bus_sio_write        => bus_sio_write,    
      bus_sio_writeMask    => bus_sio_writeMask,
      bus_sio_dataRead     => bus_sio_dataRead, 

      bus_memc2_addr       => bus_memc2_addr,     
      bus_memc2_dataWrite  => bus_memc2_dataWrite,
      bus_memc2_read       => bus_memc2_read,     
      bus_memc2_write      => bus_memc2_write,    
      bus_memc2_dataRead   => bus_memc2_dataRead, 

      bus_irq_addr         => bus_irq_addr,     
      bus_irq_dataWrite    => bus_irq_dataWrite,
      bus_irq_read         => bus_irq_read,     
      bus_irq_write        => bus_irq_write,    
      bus_irq_dataRead     => bus_irq_dataRead,       
      
      bus_dma_addr         => bus_dma_addr,     
      bus_dma_dataWrite    => bus_dma_dataWrite,
      bus_dma_read         => bus_dma_read,     
      bus_dma_write        => bus_dma_write,    
      bus_dma_dataRead     => bus_dma_dataRead,     

      bus_tmr_addr         => bus_tmr_addr,     
      bus_tmr_dataWrite    => bus_tmr_dataWrite,
      bus_tmr_read         => bus_tmr_read,     
      bus_tmr_write        => bus_tmr_write,    
      bus_tmr_dataRead     => bus_tmr_dataRead,  

      cd_memctrl           => cd_memctrl,
      bus_cd_addr          => bus_cd_addr,     
      bus_cd_dataWrite     => bus_cd_dataWrite,
      bus_cd_read          => bus_cd_read,     
      bus_cd_write         => bus_cd_write,    
      bus_cd_dataRead      => bus_cd_dataRead,      
      
      bus_gpu_addr         => bus_gpu_addr,     
      bus_gpu_dataWrite    => bus_gpu_dataWrite,
      bus_gpu_read         => bus_gpu_read,     
      bus_gpu_write        => bus_gpu_write,    
      bus_gpu_dataRead     => bus_gpu_dataRead,
      bus_gpu_stall        => bus_gpu_stall,
      
      bus_mdec_addr        => bus_mdec_addr,     
      bus_mdec_dataWrite   => bus_mdec_dataWrite,
      bus_mdec_read        => bus_mdec_read,     
      bus_mdec_write       => bus_mdec_write,    
      bus_mdec_dataRead    => bus_mdec_dataRead, 
      
      spu_memctrl          => spu_memctrl, 
      bus_spu_addr         => bus_spu_addr,     
      bus_spu_dataWrite    => bus_spu_dataWrite,
      bus_spu_read         => bus_spu_read,     
      bus_spu_write        => bus_spu_write,    
      bus_spu_dataRead     => bus_spu_dataRead, 
      bus_spu_stall        => bus_spu_stall,
      
      ex2_memctrl          => ex2_memctrl,
      bus_exp2_addr        => bus_exp2_addr,     
      bus_exp2_dataWrite   => bus_exp2_dataWrite,
      bus_exp2_read        => bus_exp2_read,     
      bus_exp2_write       => bus_exp2_write,    
      bus_exp2_dataRead    => bus_exp2_dataRead,
      
      ex3_memctrl          => ex3_memctrl,
      --bus_exp3_dataWrite   => bus_exp3_dataWrite,
      bus_exp3_read        => bus_exp3_read,     
      --bus_exp3_write       => bus_exp3_write,    
      bus_exp3_dataRead    => bus_exp3_dataRead, 
      
      com0_delay           => com0_delay,
      com1_delay           => com1_delay,
      com2_delay           => com2_delay,
      com3_delay           => com3_delay,
      
      loading_savestate    => loading_savestate,
      SS_reset             => SS_reset,
      SS_DataWrite         => SS_DataWrite,
      SS_Adr               => SS_Adr(18 downto 0),
      SS_wren_SDRam        => SS_wren(16),
      SS_rden_SDRam        => SS_rden(16),
      
      zn_req               => zn_req,
      zn_we                => zn_we,
      zn_addr              => zn_addr,
      zn_be                => zn_be,
      zn_wdata             => zn_wdata,
      zn_ack               => zn_ack,
      zn_rdata             => zn_rdata
   );
   
   icpu : entity work.cpu
   port map
   (
      clk1x             => clk_cpu,
      clk2x             => clk_cpu2x,
      clk3x             => clk_cpu3x,
      ce                => ce,   
      reset             => reset_intern,
      
      TURBO             => TURBO_COMP,
      TURBO_CACHE       => TURBO_CACHE,
      TURBO_CACHE50     => TURBO_CACHE50,
         
      irqRequest        => irqRequest,
      dmaStallCPU       => dmaStallCPU,
      cpuPaused         => cpuPaused,
      
      error             => errorCPU,
      error2            => errorCPU2,
         
      mem_request       => mem_request,  
      mem_rnw           => mem_rnw,      
      mem_isData        => mem_isData,      
      mem_isCache       => mem_isCache, 
      mem_oldtagvalids  => mem_oldtagvalids,      
      mem_addressInstr  => mem_addressInstr,  
      mem_addressData   => mem_addressData,  
      mem_reqsize       => mem_reqsize,  
      mem_writeMask     => mem_writeMask,
      mem_dataWrite     => mem_dataWrite,
      mem_dataRead      => mem_dataRead, 
      mem_done          => mem_done,
      mem_fifofull      => mem_fifofull,
      mem_tagvalids     => mem_tagvalids,
      
      cache_wr          => cache_wr,  
      cache_data        => cache_data,
      cache_addr        => cache_addr,
      
      stallNext         => stallNext,
      
      dma_cache_Adr     => dma_cache_Adr,  
      dma_cache_data    => dma_cache_data, 
      dma_cache_write   => dma_cache_write,  
      
      ram_dataRead      => ram_dataRead32,    
      ram_rnw           => ram_cpu_rnw,
      ram_done          => ram_cpu_done,
      
      gte_busy          => gte_busy, 
      gte_readEna       => gte_readEna,
      gte_readAddr      => gte_readAddr, 
      gte_readData      => gte_readData, 
      gte_writeAddr     => gte_writeAddr,
      gte_writeData     => gte_writeData,
      gte_writeEna      => gte_writeEna, 
      gte_cmdData       => gte_cmdData,  
      gte_cmdEna        => gte_cmdEna, 

      SS_reset          => SS_reset,
      SS_DataWrite      => SS_DataWrite,
      SS_Adr            => SS_Adr(7 downto 0),   
      SS_wren_CPU       => SS_wren(0),     
      SS_wren_SCP       => SS_wren(12),  
      SS_rden_CPU       => SS_rden(0),     
      SS_rden_SCP       => SS_rden(12),        
      SS_DataRead_CPU   => SS_DataRead_CPU,
      SS_DataRead_SCP   => SS_DataRead_SCP,
      SS_idle           => SS_idle_cpu,
      
-- synthesis translate_off
      cpu_done          => cpu_done,  
      cpu_export        => cpu_export,
-- synthesis translate_on
      
      debug_firstGTE    => debug_firstGTE,
      debug_pc          => cpu_debug_pc
   );
   
   igte : entity work.gte
   generic map (NARROW_MUL => GTE_NARROW_MUL)
   port map
   (
      clk1x                => clk_cpu,     
      clk2x                => clk_cpu2x,     
      clk2xIndex           => clk2xIndex_c,
      ce                   => ce,        
      reset                => reset_intern,     
      
      WIDESCREEN           => WIDESCREEN,
      TURBO                => TURBO_COMP,
      
      gte_busy             => gte_busy,     
      gte_readAddr         => gte_readAddr, 
      gte_readData         => gte_readData, 
      gte_readEna          => gte_readEna,
      gte_writeAddr_in     => gte_writeAddr,
      gte_writeData_in     => gte_writeData,
      gte_writeEna_in      => gte_writeEna, 
      gte_cmdData          => gte_cmdData,  
      gte_cmdEna           => gte_cmdEna,
      
      loading_savestate    => loading_savestate,
      SS_reset             => SS_reset,
      SS_DataWrite         => SS_DataWrite,
      SS_Adr               => SS_Adr(5 downto 0),
      SS_wren              => SS_wren(4),     
      SS_rden              => SS_rden(4),     
      SS_DataRead          => SS_DataRead_GTE,
      SS_idle              => SS_idle_gte,
      
      debug_firstGTE       => debug_firstGTE
   );
   
   ddr3_BURSTCNT <= ss_ram_BURSTCNT     when (ddr3_savestate = '1') else arbiter_BURSTCNT when (arbiter_active = '1') else  vram_BURSTCNT;  
   ddr3_ADDR     <= ss_ram_ADDR & "00"  when (ddr3_savestate = '1') else arbiter_ADDR     when (arbiter_active = '1') else  vram_ADDR;      
   ddr3_DIN      <= ss_ram_DIN          when (ddr3_savestate = '1') else arbiter_DIN      when (arbiter_active = '1') else  vram_DIN;       
   ddr3_BE       <= ss_ram_BE           when (ddr3_savestate = '1') else arbiter_BE       when (arbiter_active = '1') else  vram_BE;        
   ddr3_WE       <= ss_ram_WE           when (ddr3_savestate = '1') else arbiter_WE       when (arbiter_active = '1') else  vram_WE;        
   ddr3_RD       <= ss_ram_RD           when (ddr3_savestate = '1') else arbiter_RD       when (arbiter_active = '1') else  vram_RD;        
   
   memcard_changed <= MemCard_changePending1 or MemCard_changePending2;
   saving_memcard  <= MemCard_saving_memcard1 or MemCard_saving_memcard2;
   
   gmemcards : if HAS_PADS = 1 generate
   begin
   imemcard1 : entity work.memcard
   port map
   (
      clk2x                => clk2x, 
      ce                   => ce,    
      reset                => reset, 
      
      save                 => memcard_save,
      load                 => memcard1_load,
                            
      pause                => memcard1_pause,
      system_paused        => pausing,
                           
      mounted              => memcard1_mounted,
      anyChange            => memDDR3card1_WE,
      
      changePending        => MemCard_changePending1,
      saving_memcard       => MemCard_saving_memcard1,
                            
      mem_request          => memHPScard1_request, 
      mem_BURSTCNT         => memHPScard1_BURSTCNT,      
      mem_ADDR             => memHPScard1_ADDR,                     
      mem_DIN              => memHPScard1_DIN,    
      mem_BE               => memHPScard1_BE,      
      mem_WE               => memHPScard1_WE,      
      mem_RD               => memHPScard1_RD,   
      mem_ack              => memHPScard1_ack,   
      mem_DOUT             => ddr3_DOUT,      
      mem_DOUT_READY       => ddr3_DOUT_READY,
                           
      memcard_rd           => memcard1_rd,     
      memcard_wr           => memcard1_wr,     
      memcard_lba          => memcard1_lba,    
      memcard_ack          => memcard1_ack,    
      memcard_write        => memcard1_write,  
      memcard_addr         => memcard1_addr,   
      memcard_dataIn       => memcard1_dataIn, 
      memcard_dataOut      => memcard1_dataOut
   );
   
   imemcard2 : entity work.memcard
   port map
   (
      clk2x                => clk2x, 
      ce                   => ce,    
      reset                => reset, 
      
      save                 => memcard_save,
      load                 => memcard2_load,
                            
      pause                => memcard2_pause,
      system_paused        => pausing,
                           
      mounted              => memcard2_mounted,
      anyChange            => memDDR3card2_WE,
      
      changePending        => MemCard_changePending2,
      saving_memcard       => MemCard_saving_memcard2,
                            
      mem_request          => memHPScard2_request, 
      mem_BURSTCNT         => memHPScard2_BURSTCNT,      
      mem_ADDR             => memHPScard2_ADDR,                     
      mem_DIN              => memHPScard2_DIN,    
      mem_BE               => memHPScard2_BE,      
      mem_WE               => memHPScard2_WE,      
      mem_RD               => memHPScard2_RD,   
      mem_ack              => memHPScard2_ack,   
      mem_DOUT             => ddr3_DOUT,      
      mem_DOUT_READY       => ddr3_DOUT_READY,
                           
      memcard_rd           => memcard2_rd,     
      memcard_wr           => memcard2_wr,     
      memcard_lba          => memcard2_lba,    
      memcard_ack          => memcard2_ack,    
      memcard_write        => memcard2_write,  
      memcard_addr         => memcard2_addr,   
      memcard_dataIn       => memcard2_dataIn, 
      memcard_dataOut      => memcard2_dataOut
   );
   end generate;
   gnomemcards : if HAS_PADS = 0 generate
   begin
      MemCard_changePending1  <= '0';
      MemCard_changePending2  <= '0';
      MemCard_saving_memcard1 <= '0';
      MemCard_saving_memcard2 <= '0';
      memcard1_pause          <= '0';
      memcard2_pause          <= '0';
      memHPScard1_request     <= '0';
      memHPScard2_request     <= '0';
      memcard1_lba            <= (others => '0');
      memcard2_lba            <= (others => '0');
      memcard1_dataOut        <= (others => '0');
      memcard2_dataOut        <= (others => '0');
   end generate;
   
   isavestates : entity work.savestates
   generic map
   (
      FASTSIM                 => is_simu,
      Softmap_SaveState_ADDR  => 58720256,
      CPU_FILL_EXT            => CPU_CLK_SPLIT
   )
   port map
   (
      clk1x                   => clk1x,
      clk2x                   => clk2x,
      clk2xIndex              => clk2xIndex,
      ce                      => ce_p,
      reset_in                => reset_in,
      reset_out               => reset_intern_p,
      ss_reset                => SS_reset_p,
      
      hps_busy                => hps_busy,
      loadExe                 => loadExe,
           
      load_done               => state_loaded,
      validSStates            => validSStates,
            
      savestate_number        => savestate_number,
      increaseSSHeaderCount   => increaseSSHeaderCount,
      save                    => savestate_savestate,
      load                    => savestate_loadstate,
      savestate_address       => savestate_address,  
      savestate_busy          => savestate_busy,    

      SS_idle                 => SS_idle_p,
      system_paused           => pausingSS_p,
      savestate_pause         => savestate_pause_p,
      ddr3_savestate          => ddr3_savestate,
      
      useSPUSDRAM             => SPUSDRAM,
      
      SS_DataWrite            => SS_DataWrite_p,   
      SS_Adr                  => SS_Adr_p,         
      SS_wren                 => SS_wren_eng,       
      SS_rden                 => SS_rden_eng,       
      SS_DataRead_CPU         => SS_DataRead_CPU,
      SS_DataRead_GPU         => SS_DataRead_GPU,
      SS_DataRead_GPUTiming   => SS_DataRead_GPUTiming,
      SS_DataRead_DMA         => SS_DataRead_DMA,
      SS_DataRead_GTE         => SS_DataRead_GTE,
      SS_DataRead_JOYPAD      => SS_DataRead_JOYPAD,
      SS_DataRead_MDEC        => SS_DataRead_MDEC,
      SS_DataRead_MEMORY      => SS_DataRead_MEMORY,
      SS_DataRead_TIMER       => SS_DataRead_TIMER,
      SS_DataRead_SOUND       => SS_DataRead_SOUND,
      SS_DataRead_IRQ         => SS_DataRead_IRQ,
      SS_DataRead_SIO         => SS_DataRead_SIO,
      SS_DataRead_SCP         => SS_DataRead_SCP,
      SS_DataRead_CD          => SS_DataRead_CD,

      sdram_done              => ram_done_p,
      
      loading_savestate       => loading_savestate_p,
      saving_savestate        => open,
            
      ddr3_BUSY               => ddr3_BUSY,      
      ddr3_DOUT               => ddr3_DOUT,      
      ddr3_DOUT_READY         => ddr3_DOUT_READY,
      ddr3_BURSTCNT           => ss_ram_BURSTCNT,
      ddr3_ADDR               => ss_ram_ADDR,    
      ddr3_DIN                => ss_ram_DIN,     
      ddr3_BE                 => ss_ram_BE,      
      ddr3_WE                 => ss_ram_WE,      
      ddr3_RD                 => ss_ram_RD,

      ram_done                => ram_cpu_done_p,   
      ram_data                => ram_dataRead32_p,
      
      SS_SPURAM_dataWrite     => SS_SPURAM_dataWrite,
      SS_SPURAM_Adr           => SS_SPURAM_Adr,      
      SS_SPURAM_request       => SS_SPURAM_request,  
      SS_SPURAM_rnw           => SS_SPURAM_rnw,      
      SS_SPURAM_dataRead      => SS_SPURAM_dataRead, 
      SS_SPURAM_done          => SS_SPURAM_done,

      ext_fill_req            => ext_fill_req,
      ext_fill_done           => ext_fill_done
   );  

   -- HAS_SAVESTATES = 0: reset still runs through the savestate engine, but
   -- only types 12-16 (scratchpad, CD, SPU RAM, VRAM, SDRAM zero fill) are
   -- written in reset mode. Forcing the other write strobes and all read
   -- strobes to 0 lets each module's saved-state registers reduce to their
   -- SS_reset constants.
   SS_wren_p <= SS_wren_eng when HAS_SAVESTATES = 1 else SS_wren_eng and "11111000000000000";
   SS_rden <= SS_rden_eng when HAS_SAVESTATES = 1 else (others => '0');

   gstatemanager : if HAS_SAVESTATES = 1 generate
   begin
   istatemanager : entity work.statemanager
   generic map
   (
      Softmap_SaveState_ADDR   => 58720256,
      Softmap_Rewind_ADDR      => 33554432
   )
   port map
   (
      clk                 => clk2x,  
      ce                  => ce,  
      reset               => reset_in,
                         
      rewind_on           => rewind_on,    
      rewind_active       => rewind_active,
                        
      savestate_number    => savestate_number,
      save                => save_state,
      load                => load_state,
                       
      sleep_rewind        => open,
      vsync               => IRQ_VBlank,
      system_idle         => '1',
                 
      request_savestate   => savestate_savestate,
      request_loadstate   => savestate_loadstate,
      request_address     => savestate_address,  
      request_busy        => savestate_busy    
   );
   end generate;
   gnostatemanager : if HAS_SAVESTATES = 0 generate
   begin
      savestate_savestate  <= '0';
      savestate_loadstate  <= '0';
      savestate_address    <= 0;
   end generate;

   -- ############################################################
   -- R1 CPU_CLK_SPLIT (docs/r1_cpu_domain_design.md): wiring between the
   -- CPU group and the PS1 group (GPU, SPU, savestates engine, DDR3 arbiter)
   -- ############################################################
   gsplit0 : if CPU_CLK_SPLIT = 0 generate
   begin
      -- upstream: one clock group, the copies are plain wires
      reset_c              <= reset;
      pause_c              <= pause;
      loadExe_c            <= loadExe;
      reset_in_c           <= reset_in;
      reset_exe_p          <= reset_exe;
      clk2xIndex_c         <= clk2xIndex;
      clk3xIndex_c         <= clk3xIndex;
      sys_tick             <= '1';
      ce_p                 <= ce;
      pausing_p            <= pausing;
      pausingSS_p          <= pausingSS;
      cpuPaused_p          <= cpuPaused;
      dmaOn_p              <= dmaOn;
      reset_intern         <= reset_intern_p;
      SS_reset             <= SS_reset_p;
      loading_savestate    <= loading_savestate_p;
      savestate_pause      <= savestate_pause_p;
      allowunpause         <= allowunpause_p;
      SS_Idle_gpu          <= SS_Idle_gpu_p;
      SS_idle_spu          <= SS_idle_spu_p;
      SS_idle_p            <= SS_idle;
      SS_DataWrite         <= SS_DataWrite_p;
      SS_Adr               <= SS_Adr_p;
      SS_wren              <= SS_wren_p;
      ram_done_p           <= ram_done;
      ram_cpu_done_p       <= ram_cpu_done;
      ram_dataRead32_p     <= ram_dataRead32;
      ext_fill_done        <= '0';
      errorEna_p           <= errorEna;
      errorCode_p          <= errorCode;
      debugmodeOn_p        <= debugmodeOn;
      errorLINE            <= errorLINE_p;
      errorRECT            <= errorRECT_p;
      errorPOLY            <= errorPOLY_p;
      errorGPU             <= errorGPU_p;
      errorMASK            <= errorMASK_p;
      errorGPUFIFO         <= errorGPUFIFO_p;
      errorSPUTIME         <= errorSPUTIME_p;
      bus_gpu_addr_p       <= bus_gpu_addr;
      bus_gpu_dataWrite_p  <= bus_gpu_dataWrite;
      bus_gpu_read_p       <= bus_gpu_read;
      bus_gpu_write_p      <= bus_gpu_write;
      bus_gpu_dataRead     <= bus_gpu_dataRead_p;
      bus_gpu_stall        <= bus_gpu_stall_p;
      gpu_dmaRequest       <= gpu_dmaRequest_p;
      DMA_GPU_waiting_p    <= DMA_GPU_waiting;
      DMA_GPU_writeEna_p   <= DMA_GPU_writeEna;
      DMA_GPU_readEna_p    <= DMA_GPU_readEna;
      DMA_GPU_write_p      <= DMA_GPU_write;
      DMA_GPU_read         <= DMA_GPU_read_p;
      irq_VBLANK           <= irq_VBLANK_p;
      irq_GPU              <= irq_GPU_p;
      irq_SPU              <= irq_SPU_p;
      hblank_tmr           <= hblank_tmr_p;
      vblank_tmr           <= vblank_tmr_p;
      dotclock             <= dotclock_p;
      bus_spu_addr_p       <= bus_spu_addr;
      bus_spu_dataWrite_p  <= bus_spu_dataWrite;
      bus_spu_read_p       <= bus_spu_read;
      bus_spu_write_p      <= bus_spu_write;
      bus_spu_dataRead     <= bus_spu_dataRead_p;
      bus_spu_stall        <= '0';
      spu_dmaRequest       <= spu_dmaRequest_p;
      DMA_SPU_writeEna_p   <= DMA_SPU_writeEna;
      DMA_SPU_readEna_p    <= DMA_SPU_readEna;
      DMA_SPU_write_p      <= DMA_SPU_write;
      DMA_SPU_read         <= DMA_SPU_read_p;
      DMA_SPU_readStall    <= '0';
   end generate;

   gsplit1 : if CPU_CLK_SPLIT = 1 generate
      signal c_cpu_idle    : std_logic;
      signal p_cpu_idle    : std_logic;
      signal c_err         : std_logic_vector(6 downto 0);
      signal p_err_disp    : std_logic_vector(5 downto 0);
      signal p_err         : std_logic_vector(6 downto 0);
      signal c_err_disp    : std_logic_vector(5 downto 0);
      -- component, so builds without CPU_CLK_SPLIT need no rtl/gnet/cpu_split files
      component cpu_split is
      generic (
         FASTSIM         : std_logic := '0';
         CLK_FAST_RATIO  : integer   := 2;
         FILL_RAM_WORDS  : positive  := 524288;
         SIM_META_WINDOW : time      := 0 ns
      );
      port (
         clk_cpu              : in  std_logic;
         clk_cpu2x            : in  std_logic;
         clk1x                : in  std_logic;
         clk2x                : in  std_logic;
         reset_top            : in  std_logic;
         pause_top            : in  std_logic;
         loadExe_top          : in  std_logic;
         c_reset              : out std_logic;
         c_pause              : out std_logic;
         c_loadExe            : out std_logic;
         c_reset_in           : out std_logic;
         p_reset_top          : out std_logic;
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
         p_fill_req           : in  std_logic;
         p_fill_done          : out std_logic;
         c_SS_wren            : out std_logic_vector(16 downto 0);
         c_SS_Adr             : out unsigned(18 downto 0);
         c_SS_DataWrite       : out std_logic_vector(31 downto 0);
         c_ram_done           : in  std_logic;
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
         p_allowunpause       : in  std_logic;
         p_gpu_idle           : in  std_logic;
         p_spu_idle           : in  std_logic;
         c_allowunpause       : out std_logic;
         c_gpu_idle           : out std_logic;
         c_spu_idle           : out std_logic;
         p_err                : in  std_logic_vector(6 downto 0);
         c_err                : out std_logic_vector(6 downto 0);
         c_err_disp           : in  std_logic_vector(5 downto 0);
         p_err_disp           : out std_logic_vector(5 downto 0);
         p_hblank_tmr         : in  std_logic;
         p_vblank_tmr         : in  std_logic;
         p_dotclock           : in  std_logic;
         p_irq_VBLANK         : in  std_logic;
         p_irq_GPU            : in  std_logic;
         p_irq_SPU            : in  std_logic;
         c_hblank_tmr         : out std_logic;
         c_vblank_tmr         : out std_logic;
         c_dotclock           : out std_logic;
         c_irq_VBLANK         : out std_logic;
         c_irq_GPU            : out std_logic;
         c_irq_SPU            : out std_logic;
         c_sys_tick           : out std_logic;
         c_clk2xIndex         : out std_logic;
         c_clk3xIndex         : out std_logic;
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
      end component;
      signal c_SS_wren     : std_logic_vector(16 downto 0);
   begin
      assert HAS_CD = 0 and HAS_PADS = 0 and HAS_SAVESTATES = 0 and HAS_CHEATS = 0 and HAS_MDEC = 0
         report "psx_top: CPU_CLK_SPLIT = 1 needs HAS_CD, HAS_PADS, HAS_SAVESTATES, HAS_CHEATS and HAS_MDEC = 0" severity failure;
      assert CLK_FAST_RATIO = 2
         report "psx_top: CPU_CLK_SPLIT = 1 needs CLK_FAST_RATIO = 2 (SDRAM at 2x the CPU clock)" severity failure;

      c_cpu_idle <= SS_Idle_mdec and SS_Idle_cd and SS_idle_pad and SS_idle_irq and SS_idle_cpu and SS_idle_gte and SS_idle_dma;
      SS_idle_p  <= SS_Idle_gpu_p and SS_idle_spu_p and p_cpu_idle;

      -- the engine reads no CPU-group state with CPU_FILL_EXT = 1 (types 12 and 16 go to the CPU-side filler)
      ram_done_p       <= '0';
      ram_cpu_done_p   <= '0';
      ram_dataRead32_p <= (others => '0');

      SS_wren          <= c_SS_wren;

      errorLINE    <= c_err(6);
      errorRECT    <= c_err(5);
      errorPOLY    <= c_err(4);
      errorGPU     <= c_err(3);
      errorMASK    <= c_err(2);
      errorGPUFIFO <= c_err(1);
      errorSPUTIME <= c_err(0);
      p_err         <= errorLINE_p & errorRECT_p & errorPOLY_p & errorGPU_p & errorMASK_p & errorGPUFIFO_p & errorSPUTIME_p;
      c_err_disp    <= errorEna & std_logic_vector(errorCode) & debugmodeOn;
      errorEna_p    <= p_err_disp(5);
      errorCode_p   <= unsigned(p_err_disp(4 downto 1));
      debugmodeOn_p <= p_err_disp(0);

      icpu_split : cpu_split
      generic map
      (
         FASTSIM              => is_simu,
         CLK_FAST_RATIO       => CLK_FAST_RATIO
      )
      port map
      (
         clk_cpu              => clk_cpu,
         clk_cpu2x            => clk_cpu2x,
         clk1x                => clk1x,
         clk2x                => clk2x,

         reset_top            => reset,
         pause_top            => pause,
         loadExe_top          => loadExe,
         c_reset              => reset_c,
         c_pause              => pause_c,
         c_loadExe            => loadExe_c,
         c_reset_in           => reset_in_c,
         p_reset_top          => open,

         c_reset_exe          => reset_exe,
         p_reset_exe          => reset_exe_p,
         p_SS_reset           => SS_reset_p,
         p_reset_intern       => reset_intern_p,
         c_SS_reset           => SS_reset,
         c_reset_intern       => reset_intern,
         p_savestate_pause    => savestate_pause_p,
         c_savestate_pause    => savestate_pause,
         p_loading_savestate  => loading_savestate_p,
         c_loading_savestate  => loading_savestate,
         p_fill_req           => ext_fill_req,
         p_fill_done          => ext_fill_done,
         c_SS_wren            => c_SS_wren,
         c_SS_Adr             => SS_Adr,
         c_SS_DataWrite       => SS_DataWrite,
         c_ram_done           => ram_done,

         c_ce                 => ce,
         c_pausing            => pausing,
         c_pausingSS          => pausingSS,
         c_cpuPaused          => cpuPaused,
         c_dmaOn              => dmaOn,
         c_DMA_GPU_waiting    => DMA_GPU_waiting,
         c_cpu_idle           => c_cpu_idle,
         p_ce                 => ce_p,
         p_pausing            => pausing_p,
         p_pausingSS          => pausingSS_p,
         p_cpuPaused          => cpuPaused_p,
         p_dmaOn              => dmaOn_p,
         p_DMA_GPU_waiting    => DMA_GPU_waiting_p,
         p_cpu_idle           => p_cpu_idle,
         p_allowunpause       => allowunpause_p,
         p_gpu_idle           => SS_Idle_gpu_p,
         p_spu_idle           => SS_idle_spu_p,
         c_allowunpause       => allowunpause,
         c_gpu_idle           => SS_Idle_gpu,
         c_spu_idle           => SS_idle_spu,

         p_err                => p_err,
         c_err                => c_err,
         c_err_disp           => c_err_disp,
         p_err_disp           => p_err_disp,

         p_hblank_tmr         => hblank_tmr_p,
         p_vblank_tmr         => vblank_tmr_p,
         p_dotclock           => dotclock_p,
         p_irq_VBLANK         => irq_VBLANK_p,
         p_irq_GPU            => irq_GPU_p,
         p_irq_SPU            => irq_SPU_p,
         c_hblank_tmr         => hblank_tmr,
         c_vblank_tmr         => vblank_tmr,
         c_dotclock           => dotclock,
         c_irq_VBLANK         => irq_VBLANK,
         c_irq_GPU            => irq_GPU,
         c_irq_SPU            => irq_SPU,

         c_sys_tick           => sys_tick,
         c_clk2xIndex         => clk2xIndex_c,
         c_clk3xIndex         => clk3xIndex_c,

         c_bus_gpu_addr       => bus_gpu_addr,
         c_bus_gpu_dataWrite  => bus_gpu_dataWrite,
         c_bus_gpu_read       => bus_gpu_read,
         c_bus_gpu_write      => bus_gpu_write,
         c_bus_gpu_dataRead   => bus_gpu_dataRead,
         c_bus_gpu_stall      => bus_gpu_stall,
         c_DMA_GPU_writeEna   => DMA_GPU_writeEna,
         c_DMA_GPU_write      => DMA_GPU_write,
         c_DMA_GPU_readEna    => DMA_GPU_readEna,
         c_DMA_GPU_read       => DMA_GPU_read,
         c_gpu_dmaRequest     => gpu_dmaRequest,
         p_bus_gpu_addr       => bus_gpu_addr_p,
         p_bus_gpu_dataWrite  => bus_gpu_dataWrite_p,
         p_bus_gpu_read       => bus_gpu_read_p,
         p_bus_gpu_write      => bus_gpu_write_p,
         p_bus_gpu_dataRead   => bus_gpu_dataRead_p,
         p_bus_gpu_stall      => bus_gpu_stall_p,
         p_DMA_GPU_writeEna   => DMA_GPU_writeEna_p,
         p_DMA_GPU_write      => DMA_GPU_write_p,
         p_DMA_GPU_readEna    => DMA_GPU_readEna_p,
         p_DMA_GPU_read       => DMA_GPU_read_p,
         p_gpu_dmaRequest     => gpu_dmaRequest_p,

         c_bus_spu_addr       => bus_spu_addr,
         c_bus_spu_dataWrite  => bus_spu_dataWrite,
         c_bus_spu_read       => bus_spu_read,
         c_bus_spu_write      => bus_spu_write,
         c_bus_spu_dataRead   => bus_spu_dataRead,
         c_bus_spu_stall      => bus_spu_stall,
         c_DMA_SPU_writeEna   => DMA_SPU_writeEna,
         c_DMA_SPU_write      => DMA_SPU_write,
         c_DMA_SPU_readReq    => DMA_SPU_readReq,
         c_DMA_SPU_readEna    => DMA_SPU_readEna,
         c_DMA_SPU_readStall  => DMA_SPU_readStall,
         c_DMA_SPU_read       => DMA_SPU_read,
         c_spu_dmaRequest     => spu_dmaRequest,
         p_bus_spu_addr       => bus_spu_addr_p,
         p_bus_spu_dataWrite  => bus_spu_dataWrite_p,
         p_bus_spu_read       => bus_spu_read_p,
         p_bus_spu_write      => bus_spu_write_p,
         p_bus_spu_dataRead   => bus_spu_dataRead_p,
         p_DMA_SPU_writeEna   => DMA_SPU_writeEna_p,
         p_DMA_SPU_write      => DMA_SPU_write_p,
         p_DMA_SPU_readEna    => DMA_SPU_readEna_p,
         p_DMA_SPU_read       => DMA_SPU_read_p,
         p_spu_dmaRequest     => spu_dmaRequest_p
      );
   end generate;
   
   -- export
-- synthesis translate_off
   gexport : if is_simu = '1' generate
   begin
   
      new_export <= cpu_done; 
      
      iexport : entity work.export
      port map
      (
         clk               => clk_cpu,
         ce                => ce,
         reset             => reset_intern,
            
         new_export        => cpu_done,
         export_cpu        => cpu_export,
            
         export_irq        => export_irq,
            
         export_gtm        => export_gtm,
         export_line       => export_line,
         export_gpus       => export_gpus,
         export_gobj       => export_gobj,
         
         export_t_current0 => export_t_current0,
         export_t_current1 => export_t_current1,
         export_t_current2 => export_t_current2,
            
         export_8          => export_8,
         export_16         => export_16,
         export_32         => export_32
      );
   
   
   end generate;
-- synthesis translate_on
   
   -- ############################################################
   -- G-NET: ZN-2 board and FC PCB (docs/zn2_layer_design.md 13)
   -- ############################################################
   gzoomchk : if ZOOM_BOARD = 1 and (ZN2_BOARD = 0 or CPU_CLK_SPLIT = 0) generate
   begin
      assert false report "ZOOM_BOARD = 1 needs ZN2_BOARD = 1 and CPU_CLK_SPLIT = 1 (rtl/gnet/zoom_cdc.vhd)" severity failure;
   end generate;

   gnozoom : if not (ZOOM_BOARD = 1 and ZN2_BOARD = 1 and CPU_CLK_SPLIT = 1) generate
   begin
      zoom_m_req   <= '0';
      zoom_m_line  <= (others => '0');
      zoom_rst     <= '1';
      zoom_aud_l   <= (others => '0');
      zoom_aud_r   <= (others => '0');
      zoom_flags   <= (others => '0');
   end generate;

   gzn2 : if ZN2_BOARD = 1 and CPU_CLK_SPLIT = 0 generate
   begin
      assert HAS_PADS = 0 report "ZN2_BOARD = 1 needs HAS_PADS = 0 (SIO0 belongs to the ZN-2 devices)" severity failure;

      izn2_board : entity work.zn2_board
      generic map
      (
         CLK_HZ       => 33868800,
         FLASH_PRESET => ZN2_FLASH_PRESET,
         PS1_SIO      => ZN2_PS1_SIO,
         SPU_STATUS   => ZN2_SPU_STATUS,
         WD_TIMEOUT_S => ZN2_WD_TIMEOUT_S
      )
      port map
      (
         clk1x          => clk1x,
         ce             => ce,
         reset          => reset_intern,
         zn_req         => zn_req,
         zn_we          => zn_we,
         zn_addr        => zn_addr,
         zn_be          => zn_be,
         zn_wdata       => zn_wdata,
         zn_ack         => zn_ack,
         zn_rdata       => zn_rdata,
         sio_addr       => bus_pad_addr,
         sio_dataWrite  => bus_pad_dataWrite,
         sio_read       => bus_pad_read,
         sio_write      => bus_pad_write,
         sio_writeMask  => bus_pad_writeMask,
         sio_dataRead   => bus_pad_dataRead,
         sio_irq        => irq_PAD,
         in_p1          => zn_in_p1,
         in_p2          => zn_in_p2,
         in_service     => zn_in_service,
         in_system      => zn_in_system,
         dsw            => zn_dsw,
         jp1            => zn_jp1,
         card_present   => zn_card_present,
         key_valid      => zn_key_valid,
         coin           => zn_coin,
         wd_reset       => zn_dbg_wd,
         zoom_reset     => open,
         ld_wr          => zn_ld_wr,
         ld_target      => zn_ld_target,
         ld_addr        => zn_ld_addr,
         ld_data        => zn_ld_data,
         fl_req         => zn_fl_req,
         fl_rnw         => zn_fl_rnw,
         fl_addr        => zn_fl_addr,
         fl_din         => zn_fl_din,
         fl_be          => zn_fl_be,
         fl_ready       => zn_fl_ready,
         fl_dout        => zn_fl_dout,
         cm_req         => zn_cm_req,
         cm_we          => zn_cm_we,
         cm_addr        => zn_cm_addr,
         cm_wdata       => zn_cm_wdata,
         cm_ack         => zn_cm_ack,
         cm_rdata       => zn_cm_rdata,
         dbg_wd_kick    => zn_dbg_kick,
         dbg_ctrl       => zn_dbg_ctrl,
         dbg_sec_cmd    => zn_dbg_sec,
         nv_clk         => zn_nv_clk,
         nv_addr        => zn_nv_addr,
         nv_q           => zn_nv_q,
         nv_wtog        => zn_nv_wtog
      );

      zn_wd_reset <= zn_dbg_wd;

      izn2_cardmem : entity work.zn2_cardmem
      port map
      (
         clk2x          => clk2x,
         reset          => reset_intern,
         dl_wr          => zn_card_dl_wr,
         dl_addr        => zn_card_dl_addr,
         dl_data        => zn_card_dl_data,
         dl_busy        => zn_card_dl_busy,
         cm_req         => zn_cm_req,
         cm_we          => zn_cm_we,
         cm_addr        => zn_cm_addr,
         cm_wdata       => zn_cm_wdata,
         cm_ack         => zn_cm_ack,
         cm_rdata       => zn_cm_rdata,
         mem_request    => memZN_request,
         mem_BURSTCNT   => memZN_BURSTCNT,
         mem_ADDR       => memZN_ADDR,
         mem_DIN        => memZN_DIN,
         mem_BE         => memZN_BE,
         mem_WE         => memZN_WE,
         mem_RD         => memZN_RD,
         mem_ack        => memZN_ack,
         mem_DOUT       => ddr3_DOUT,
         mem_DOUT_READY => ddr3_DOUT_READY
      );
   end generate;

   -- With CPU_CLK_SPLIT = 1 (docs/r1_cpu_domain_design.md, "ZN-2 layer in
   -- the CPU group"): zn2_board joins memorymux in the CPU group (clk_cpu,
   -- CLK_HZ 50,000,000, ce, reset and sys_tick of the CPU group), so the
   -- expansion bus, SIO0 and IRQ7 stay synchronous, and its flash port is on
   -- the SDRAM controller's clk_base (clk_cpu, PSX.sv zn2_ch3_arb).
   -- zn2_cardmem stays on clk2x with the DDR3 arbiter. rtl/gnet/zn2_cdc
   -- carries the board inputs and the loader in from clk1x, the watchdog
   -- pulse and the coin outputs back, and the card memory port (C18) to
   -- clk2x and back.
   gzn2c : if ZN2_BOARD = 1 and CPU_CLK_SPLIT = 1 generate
      -- component, so builds without CPU_CLK_SPLIT need no rtl/gnet/zn2_cdc.vhd
      component zn2_cdc is
      generic
      (
         SIM_META_WINDOW : time := 0 ns
      );
      port
      (
         clk_cpu          : in  std_logic;
         clk1x            : in  std_logic;
         clk2x            : in  std_logic;
         c_board_rst      : in  std_logic;
         p_in_p1          : in  std_logic_vector(7 downto 0);
         p_in_p2          : in  std_logic_vector(7 downto 0);
         p_in_service     : in  std_logic_vector(7 downto 0);
         p_in_system      : in  std_logic_vector(7 downto 0);
         p_dsw            : in  std_logic_vector(3 downto 0);
         p_jp1            : in  std_logic;
         p_card_present   : in  std_logic;
         p_key_valid      : in  std_logic;
         c_in_p1          : out std_logic_vector(7 downto 0);
         c_in_p2          : out std_logic_vector(7 downto 0);
         c_in_service     : out std_logic_vector(7 downto 0);
         c_in_system      : out std_logic_vector(7 downto 0);
         c_dsw            : out std_logic_vector(3 downto 0);
         c_jp1            : out std_logic;
         c_card_present   : out std_logic;
         c_key_valid      : out std_logic;
         p_ld_wr          : in  std_logic;
         p_ld_target      : in  std_logic_vector(1 downto 0);
         p_ld_addr        : in  unsigned(10 downto 0);
         p_ld_data        : in  std_logic_vector(15 downto 0);
         p_ld_overflow    : out std_logic;
         p_ld_busy        : out std_logic;
         c_ld_wr          : out std_logic;
         c_ld_target      : out std_logic_vector(1 downto 0);
         c_ld_addr        : out unsigned(10 downto 0);
         c_ld_data        : out std_logic_vector(15 downto 0);
         c_wd_reset       : in  std_logic;
         p_wd_reset       : out std_logic;
         c_coin           : in  std_logic_vector(7 downto 0);
         p_coin           : out std_logic_vector(7 downto 0);
         c_cm_req         : in  std_logic;
         c_cm_we          : in  std_logic;
         c_cm_addr        : in  std_logic_vector(24 downto 0);
         c_cm_wdata       : in  std_logic_vector(15 downto 0);
         c_cm_ack         : out std_logic;
         c_cm_rdata       : out std_logic_vector(15 downto 0);
         p2_cm_req        : out std_logic;
         p2_cm_we         : out std_logic;
         p2_cm_addr       : out std_logic_vector(24 downto 0);
         p2_cm_wdata      : out std_logic_vector(15 downto 0);
         p2_cm_ack        : in  std_logic;
         p2_cm_rdata      : in  std_logic_vector(15 downto 0)
      );
      end component;

      signal c_in_p1, c_in_p2, c_in_service, c_in_system : std_logic_vector(7 downto 0);
      signal c_dsw                 : std_logic_vector(3 downto 0);
      signal c_jp1, c_card_present : std_logic;
      signal c_key_valid           : std_logic;
      signal c_ld_wr               : std_logic;
      signal c_ld_target           : std_logic_vector(1 downto 0);
      signal c_ld_addr             : unsigned(10 downto 0);
      signal c_ld_data             : std_logic_vector(15 downto 0);
      signal c_wd_reset            : std_logic;
      signal c_coin                : std_logic_vector(7 downto 0);
      signal c_cm_req, c_cm_we     : std_logic;
      signal c_cm_addr             : std_logic_vector(24 downto 0);
      signal c_cm_wdata            : std_logic_vector(15 downto 0);
      signal c_cm_ack              : std_logic;
      signal c_cm_rdata            : std_logic_vector(15 downto 0);
      -- Taito Zoom host port and reset (clk_cpu)
      signal c_zm_req, c_zm_we     : std_logic;
      signal c_zm_addr             : unsigned(23 downto 0);
      signal c_zm_be               : std_logic_vector(3 downto 0);
      signal c_zm_wdata            : std_logic_vector(31 downto 0);
      signal c_zm_ack              : std_logic;
      signal c_zm_rdata            : std_logic_vector(31 downto 0);
      signal c_zoom_reset          : std_logic;
   begin
      assert HAS_PADS = 0 report "ZN2_BOARD = 1 needs HAS_PADS = 0 (SIO0 belongs to the ZN-2 devices)" severity failure;

      izn2_board : entity work.zn2_board
      generic map
      (
         CLK_HZ       => 50000000,   -- clk_cpu from rtl/gnet/pll_cpu.v
         FLASH_PRESET => ZN2_FLASH_PRESET,
         PS1_SIO      => ZN2_PS1_SIO,
         SPU_STATUS   => ZN2_SPU_STATUS,
         WD_TIMEOUT_S => ZN2_WD_TIMEOUT_S,
         ZOOM         => ZOOM_BOARD
      )
      port map
      (
         clk1x          => clk_cpu,
         ce             => ce,
         reset          => reset_intern,
         sys_tick       => sys_tick,
         zn_req         => zn_req,
         zn_we          => zn_we,
         zn_addr        => zn_addr,
         zn_be          => zn_be,
         zn_wdata       => zn_wdata,
         zn_ack         => zn_ack,
         zn_rdata       => zn_rdata,
         sio_addr       => bus_pad_addr,
         sio_dataWrite  => bus_pad_dataWrite,
         sio_read       => bus_pad_read,
         sio_write      => bus_pad_write,
         sio_writeMask  => bus_pad_writeMask,
         sio_dataRead   => bus_pad_dataRead,
         sio_irq        => irq_PAD,
         in_p1          => c_in_p1,
         in_p2          => c_in_p2,
         in_service     => c_in_service,
         in_system      => c_in_system,
         dsw            => c_dsw,
         jp1            => c_jp1,
         card_present   => c_card_present,
         key_valid      => c_key_valid,
         coin           => c_coin,
         wd_reset       => c_wd_reset,
         zoom_reset     => c_zoom_reset,
         ld_wr          => c_ld_wr,
         ld_target      => c_ld_target,
         ld_addr        => c_ld_addr,
         ld_data        => c_ld_data,
         fl_req         => zn_fl_req,
         fl_rnw         => zn_fl_rnw,
         fl_addr        => zn_fl_addr,
         fl_din         => zn_fl_din,
         fl_be          => zn_fl_be,
         fl_ready       => zn_fl_ready,
         fl_dout        => zn_fl_dout,
         cm_req         => c_cm_req,
         cm_we          => c_cm_we,
         cm_addr        => c_cm_addr,
         cm_wdata       => c_cm_wdata,
         cm_ack         => c_cm_ack,
         cm_rdata       => c_cm_rdata,
         dbg_wd_kick    => zn_dbg_kick,
         dbg_ctrl       => zn_dbg_ctrl,
         dbg_sec_cmd    => zn_dbg_sec,
         nv_clk         => zn_nv_clk,
         nv_addr        => zn_nv_addr,
         nv_q           => zn_nv_q,
         nv_wtog        => zn_nv_wtog,
         zm_req         => c_zm_req,
         zm_we          => c_zm_we,
         zm_addr        => c_zm_addr,
         zm_be          => c_zm_be,
         zm_wdata       => c_zm_wdata,
         zm_ack         => c_zm_ack,
         zm_rdata       => c_zm_rdata
      );

      zn_dbg_wd <= c_wd_reset;

      izn2_cdc : zn2_cdc
      port map
      (
         clk_cpu          => clk_cpu,
         clk1x            => clk1x,
         clk2x            => clk2x,
         c_board_rst      => reset_intern,
         p_in_p1          => zn_in_p1,
         p_in_p2          => zn_in_p2,
         p_in_service     => zn_in_service,
         p_in_system      => zn_in_system,
         p_dsw            => zn_dsw,
         p_jp1            => zn_jp1,
         p_card_present   => zn_card_present,
         p_key_valid      => zn_key_valid,
         c_in_p1          => c_in_p1,
         c_in_p2          => c_in_p2,
         c_in_service     => c_in_service,
         c_in_system      => c_in_system,
         c_dsw            => c_dsw,
         c_jp1            => c_jp1,
         c_card_present   => c_card_present,
         c_key_valid      => c_key_valid,
         p_ld_wr          => zn_ld_wr,
         p_ld_target      => zn_ld_target,
         p_ld_addr        => zn_ld_addr,
         p_ld_data        => zn_ld_data,
         p_ld_overflow    => open,
         p_ld_busy        => zn_ld_busy,
         c_ld_wr          => c_ld_wr,
         c_ld_target      => c_ld_target,
         c_ld_addr        => c_ld_addr,
         c_ld_data        => c_ld_data,
         c_wd_reset       => c_wd_reset,
         p_wd_reset       => zn_wd_reset,
         c_coin           => c_coin,
         p_coin           => zn_coin,
         c_cm_req         => c_cm_req,
         c_cm_we          => c_cm_we,
         c_cm_addr        => c_cm_addr,
         c_cm_wdata       => c_cm_wdata,
         c_cm_ack         => c_cm_ack,
         c_cm_rdata       => c_cm_rdata,
         p2_cm_req        => zn_cm_req,
         p2_cm_we         => zn_cm_we,
         p2_cm_addr       => zn_cm_addr,
         p2_cm_wdata      => zn_cm_wdata,
         p2_cm_ack        => zn_cm_ack,
         p2_cm_rdata      => zn_cm_rdata
      );

      izn2_cardmem : entity work.zn2_cardmem
      port map
      (
         clk2x          => clk2x,
         reset          => reset_intern_p,
         dl_wr          => zn_card_dl_wr,
         dl_addr        => zn_card_dl_addr,
         dl_data        => zn_card_dl_data,
         dl_busy        => zn_card_dl_busy,
         cm_req         => zn_cm_req,
         cm_we          => zn_cm_we,
         cm_addr        => zn_cm_addr,
         cm_wdata       => zn_cm_wdata,
         cm_ack         => zn_cm_ack,
         cm_rdata       => zn_cm_rdata,
         mem_request    => memZN_request,
         mem_BURSTCNT   => memZN_BURSTCNT,
         mem_ADDR       => memZN_ADDR,
         mem_DIN        => memZN_DIN,
         mem_BE         => memZN_BE,
         mem_WE         => memZN_WE,
         mem_RD         => memZN_RD,
         mem_ack        => memZN_ack,
         mem_DOUT       => ddr3_DOUT,
         mem_DOUT_READY => ddr3_DOUT_READY
      );

      -- Taito Zoom (docs/zoom_board_design.md 14): the board runs on clk1x
      -- and clk2x (CLK_H 4: MN10200 side on clk2x) with its host side on
      -- clk1x; zoom_cdc carries the host port and control bit 4 from
      -- clk_cpu. Its flash area line port leaves on zoom_m_* (clk1x).
      gzoom : if ZOOM_BOARD = 1 generate
         -- components, so builds without the Zoom need none of its files
         component zoom_cdc is
         generic
         (
            SIM_META_WINDOW : time := 0 ns
         );
         port
         (
            clk_cpu          : in  std_logic;
            clk1x            : in  std_logic;
            c_board_rst      : in  std_logic;
            p_board_rst      : in  std_logic;
            c_zm_req         : in  std_logic;
            c_zm_we          : in  std_logic;
            c_zm_addr        : in  unsigned(23 downto 0);
            c_zm_be          : in  std_logic_vector(3 downto 0);
            c_zm_wdata       : in  std_logic_vector(31 downto 0);
            c_zm_ack         : out std_logic;
            c_zm_rdata       : out std_logic_vector(31 downto 0);
            p_h_req          : out std_logic;
            p_h_we           : out std_logic;
            p_h_addr         : out std_logic_vector(23 downto 0);
            p_h_be           : out std_logic_vector(3 downto 0);
            p_h_wdata        : out std_logic_vector(31 downto 0);
            p_h_ack          : in  std_logic;
            p_h_rdata        : in  std_logic_vector(31 downto 0);
            p_h_hit          : in  std_logic;
            c_zoom_reset     : in  std_logic;
            p_zoom_reset     : out std_logic
         );
         end component;

         -- rtl/zoom/zoom_board.sv (SystemVerilog); parameters not listed
         -- keep their defaults: the TMS57002 User's Guide behaviour
         -- (TMS_MAME 0), the MB87078 volume law (MAME_GAIN 0), the flash
         -- area layout of zn2_layer_design.md 13.4 (U27 at 0x200000, wave
         -- flashes from 0x400000), output at 25 MHz / 768
         component zoom_board is
         generic
         (
            CLK_H       : integer := 4;
            PACE_CAP    : integer := 1024;
            ZSG_INFL    : integer := 4;
            TIMER_EXACT : integer := 0;
            DEBUG       : integer := 0
         );
         port
         (
            clk         : in  std_logic;
            clk2x       : in  std_logic;
            rst         : in  std_logic;
            hclk        : in  std_logic;
            hrst        : in  std_logic;
            zoom_reset  : in  std_logic;
            h_req       : in  std_logic;
            h_we        : in  std_logic;
            h_addr      : in  std_logic_vector(23 downto 0);
            h_be        : in  std_logic_vector(3 downto 0);
            h_wdata     : in  std_logic_vector(31 downto 0);
            h_ack       : out std_logic;
            h_rdata     : out std_logic_vector(31 downto 0);
            h_hit       : out std_logic;
            m_req       : out std_logic;
            m_line      : out std_logic_vector(20 downto 0);
            m_ready     : in  std_logic;
            m_rvalid    : in  std_logic;
            m_rdata     : in  std_logic_vector(63 downto 0);
            prog_inval  : in  std_logic;
            aud_tick    : out std_logic;
            aud_l       : out std_logic_vector(15 downto 0);
            aud_r       : out std_logic_vector(15 downto 0);
            pace_en     : in  std_logic;
            dbg_hold    : in  std_logic;
            dbg_bound   : out std_logic;
            dbg_insn    : out std_logic;
            dbg_pc      : out std_logic_vector(23 downto 0);
            dbg_psw     : out std_logic_vector(15 downto 0);
            dbg_mdr     : out std_logic_vector(15 downto 0);
            dbg_cycles  : out std_logic_vector(47 downto 0);
            dbg_regs    : out std_logic_vector(191 downto 0);
            tb_pin1_ovr : in  std_logic;
            tb_pin1     : in  std_logic;
            tb_ld       : in  std_logic;
            tb_ld_left  : in  std_logic_vector(8 downto 0);
            tb_ld_rem   : in  std_logic_vector(15 downto 0);
            dbg_flags   : out std_logic_vector(7 downto 0)
         );
         end component;

         signal p_h_req, p_h_we       : std_logic;
         signal p_h_addr              : std_logic_vector(23 downto 0);
         signal p_h_be                : std_logic_vector(3 downto 0);
         signal p_h_wdata             : std_logic_vector(31 downto 0);
         signal p_h_ack, p_h_hit      : std_logic;
         signal p_h_rdata             : std_logic_vector(31 downto 0);
         signal p_zoom_reset          : std_logic;
      begin
         zoom_rst <= reset_intern_p;

         izoom_cdc : zoom_cdc
         port map
         (
            clk_cpu          => clk_cpu,
            clk1x            => clk1x,
            c_board_rst      => reset_intern,
            p_board_rst      => reset_intern_p,
            c_zm_req         => c_zm_req,
            c_zm_we          => c_zm_we,
            c_zm_addr        => c_zm_addr,
            c_zm_be          => c_zm_be,
            c_zm_wdata       => c_zm_wdata,
            c_zm_ack         => c_zm_ack,
            c_zm_rdata       => c_zm_rdata,
            p_h_req          => p_h_req,
            p_h_we           => p_h_we,
            p_h_addr         => p_h_addr,
            p_h_be           => p_h_be,
            p_h_wdata        => p_h_wdata,
            p_h_ack          => p_h_ack,
            p_h_rdata        => p_h_rdata,
            p_h_hit          => p_h_hit,
            c_zoom_reset     => c_zoom_reset,
            p_zoom_reset     => p_zoom_reset
         );

         izoom_board : zoom_board
         generic map (CLK_H => 4, PACE_CAP => 1024, ZSG_INFL => ZOOM_INFL, TIMER_EXACT => 0, DEBUG => 0)
         port map
         (
            clk         => clk1x,
            clk2x       => clk2x,
            rst         => reset_intern_p,
            hclk        => clk1x,
            hrst        => reset_intern_p,
            zoom_reset  => p_zoom_reset,
            h_req       => p_h_req,
            h_we        => p_h_we,
            h_addr      => p_h_addr,
            h_be        => p_h_be,
            h_wdata     => p_h_wdata,
            h_ack       => p_h_ack,
            h_rdata     => p_h_rdata,
            h_hit       => p_h_hit,
            m_req       => zoom_m_req,
            m_line      => zoom_m_line,
            m_ready     => zoom_m_ready,
            m_rvalid    => zoom_m_rvalid,
            m_rdata     => zoom_m_rdata,
            prog_inval  => '0',        -- no U27 write while the Zoom runs (zoom_board_design.md 3.4, I2)
            aud_tick    => open,
            aud_l       => zoom_aud_l,
            aud_r       => zoom_aud_r,
            pace_en     => '1',
            dbg_hold    => zoom_hold,      -- core pause (see the port)
            dbg_bound   => open,
            dbg_insn    => open,
            dbg_pc      => open,
            dbg_psw     => open,
            dbg_mdr     => open,
            dbg_cycles  => open,
            dbg_regs    => open,
            tb_pin1_ovr => '0',
            tb_pin1     => '0',
            tb_ld       => '0',
            tb_ld_left  => (others => '0'),
            tb_ld_rem   => (others => '0'),
            dbg_flags   => zoom_flags
         );
      end generate;

      gnozoom2 : if ZOOM_BOARD = 0 generate
      begin
         c_zm_ack   <= '0';
         c_zm_rdata <= (others => '0');
      end generate;
   end generate;

   -- the loader writes zn2_board directly without the split: never busy
   gldbusy0 : if not (ZN2_BOARD = 1 and CPU_CLK_SPLIT = 1) generate
   begin
      zn_ld_busy <= '0';
   end generate;

   -- Debug overlay capture (docs/hw_debug_overlay.md): on the clock of the
   -- CPU and zn2_board, no reset input (the counters and the watchdog
   -- snapshot survive the core reset). A component, so builds without the
   -- ZN-2 board need no rtl/gnet/zn_dbg_regs.vhd.
   gzndbg : if ZN2_BOARD = 1 generate
      component zn_dbg_regs is
      generic
      (
         CLK_HZ     : integer := 33868800;
         WD_WIN_MS  : integer := 100;
         GAP_TICKS  : integer := 2
      );
      port
      (
         clk        : in  std_logic;
         core_reset : in  std_logic;
         pc         : in  unsigned(31 downto 0);
         dat_take   : in  std_logic;
         dat_addr   : in  unsigned(31 downto 0);
         wd_fire    : in  std_logic;
         wd_kick    : in  std_logic;
         ctrl       : in  std_logic_vector(7 downto 0);
         sec_cmd    : in  std_logic;
         rd_idx     : in  std_logic_vector(3 downto 0);
         rd_word    : out std_logic_vector(31 downto 0)
      );
      end component;

      signal dbg_take : std_logic;
   begin
      dbg_take <= ce and mem_request and mem_isData;

      izn_dbg_regs : zn_dbg_regs
      generic map
      (
         CLK_HZ     => 33868800 + CPU_CLK_SPLIT * (50000000 - 33868800)
      )
      port map
      (
         clk        => clk_cpu,
         core_reset => reset_intern,
         pc         => cpu_debug_pc,
         dat_take   => dbg_take,
         dat_addr   => mem_addressData,
         wd_fire    => zn_dbg_wd,
         wd_kick    => zn_dbg_kick,
         ctrl       => zn_dbg_ctrl,
         sec_cmd    => zn_dbg_sec,
         rd_idx     => zn_dbg_idx,
         rd_word    => zn_dbg_word
      );
   end generate;

   gnozn2 : if ZN2_BOARD = 0 generate
   begin
      zn_dbg_word     <= (others => '0');
      zn_nv_q         <= (others => '0');
      zn_nv_wtog      <= '0';
      zn_ack          <= '0';
      zn_rdata        <= (others => '0');
      memZN_request   <= '0';
      zn_coin         <= (others => '0');
      zn_wd_reset     <= '0';
      zn_card_dl_busy <= '0';
      zn_fl_req       <= '0';
      zn_fl_rnw       <= '1';
      zn_fl_addr      <= (others => '0');
      zn_fl_din       <= (others => '0');
      zn_fl_be        <= (others => '0');
   end generate;
   
end architecture;





