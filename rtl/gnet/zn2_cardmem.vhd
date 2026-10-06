-- PC card image in DDR3 for the G-NET glue (docs/zn2_layer_design.md 13.4).
--
-- Copyright (C) 2026 Lee Foot
--
-- This program is free software; you can redistribute it and/or modify it
-- under the terms of the GNU General Public License as published by the Free
-- Software Foundation; either version 2 of the License, or (at your option)
-- any later version. This program is distributed in the hope that it will be
-- useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
-- Public License for more details.
--
-- One client of psx_top's DDR3 arbiter (clk2x). Card byte offset b lives at
-- DDR3 byte BASE + b (BASE = 64 MB). Two users:
--   * loader (clk1x, from PSX.sv): 16-bit words in ascending order; four are
--     collected into one 64-bit write; dl_busy holds ioctl_wait
--   * gnet_ata storage port (clk1x, request held until ack): 16-bit word
--     reads served from a one-line (8-byte) buffer, a miss reads the line
--     (burst 1); 16-bit writes go to DDR3 with byte enables and update the
--     buffered line
-- Arbiter handshake as memcard.vhd: request held; for a write it drops at
-- ack; for a read it drops when the data word arrives (DOUT_READY).
-- clk1x and clk2x come from one PLL, clk2x = 2 x clk1x: a level held for two
-- clk2x cycles is seen by exactly one clk1x edge.

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity zn2_cardmem is
   generic
   (
      BASE : unsigned(27 downto 0) := x"4000000"
   );
   port
   (
      clk2x        : in  std_logic;
      reset        : in  std_logic;

      -- loader (clk1x pulse, byte address even)
      dl_wr        : in  std_logic;
      dl_addr      : in  unsigned(25 downto 0);
      dl_data      : in  std_logic_vector(15 downto 0);
      dl_busy      : out std_logic := '0';

      -- gnet_ata storage (word address)
      cm_req       : in  std_logic;
      cm_we        : in  std_logic;
      cm_addr      : in  std_logic_vector(24 downto 0);
      cm_wdata     : in  std_logic_vector(15 downto 0);
      cm_ack       : out std_logic := '0';
      cm_rdata     : out std_logic_vector(15 downto 0) := (others => '0');

      -- DDR3 arbiter client
      mem_request  : out std_logic := '0';
      mem_BURSTCNT : out std_logic_vector(7 downto 0) := x"01";
      mem_ADDR     : out std_logic_vector(27 downto 0) := (others => '0');
      mem_DIN      : out std_logic_vector(63 downto 0) := (others => '0');
      mem_BE       : out std_logic_vector(7 downto 0) := (others => '0');
      mem_WE       : out std_logic := '0';
      mem_RD       : out std_logic := '0';
      mem_ack      : in  std_logic;
      mem_DOUT     : in  std_logic_vector(63 downto 0);
      mem_DOUT_READY : in std_logic
   );
end entity;

architecture arch of zn2_cardmem is

   type t_state is (IDLE, DL_WAIT, RD_WAITACK, RD_WAITDATA, WR_WAIT, ACK1, ACK2, HOLD);
   signal state     : t_state := IDLE;

   signal dl_wr_1   : std_logic := '0';
   signal dl_line   : std_logic_vector(63 downto 0) := (others => '0');
   signal dl_cnt    : unsigned(1 downto 0) := (others => '0');
   signal dl_go     : std_logic := '0';
   signal dl_waddr  : unsigned(25 downto 0) := (others => '0');

   signal line      : std_logic_vector(63 downto 0) := (others => '0');
   signal line_tag  : unsigned(22 downto 0) := (others => '0');   -- card byte address(25:3)
   signal line_ok   : std_logic := '0';

   signal c_tag     : unsigned(22 downto 0);
   signal c_lane    : integer range 0 to 3;

   -- 16-bit lane select written as a case: Quartus 17 cannot elaborate a
   -- slice whose bounds depend on a signal inside a function (error 10779)
   function lanes(d : std_logic_vector(63 downto 0); l : integer range 0 to 3) return std_logic_vector is
      variable r : std_logic_vector(15 downto 0);
   begin
      case l is
         when 0      => r := d(15 downto 0);
         when 1      => r := d(31 downto 16);
         when 2      => r := d(47 downto 32);
         when others => r := d(63 downto 48);
      end case;
      return r;
   end function;

begin

   -- word address w: card byte 2w; line = byte(25:3) = w(24:2), lane = w(1:0)
   c_tag  <= unsigned(cm_addr(24 downto 2));
   c_lane <= to_integer(unsigned(cm_addr(1 downto 0)));

   process (clk2x)
      variable be : std_logic_vector(7 downto 0);
   begin
      if rising_edge(clk2x) then

         dl_wr_1 <= dl_wr;

         -- loader: collect four words (a clk1x pulse spans two clk2x edges)
         if (dl_wr = '1' and dl_wr_1 = '0') then
            case dl_addr(2 downto 1) is   -- constant slices (Quartus 17 error 10779 on signal bounds)
               when "00"   => dl_line(15 downto 0)  <= dl_data;
               when "01"   => dl_line(31 downto 16) <= dl_data;
               when "10"   => dl_line(47 downto 32) <= dl_data;
               when others => dl_line(63 downto 48) <= dl_data;
            end case;
            if (dl_addr(2 downto 1) = "11") then
               dl_go    <= '1';
               dl_busy  <= '1';
               dl_waddr <= dl_addr;
            end if;
         end if;

         if (reset = '1') then
            state       <= IDLE;
            mem_request <= '0';
            cm_ack      <= '0';
            line_ok     <= '0';
         else
            case state is

               when IDLE =>
                  cm_ack <= '0';
                  if (dl_go = '1') then
                     dl_go        <= '0';
                     mem_request  <= '1';
                     mem_BURSTCNT <= x"01";
                     mem_ADDR     <= std_logic_vector(BASE + (dl_waddr(25 downto 3) & "000"));
                     mem_DIN      <= dl_line;
                     mem_BE       <= x"FF";
                     mem_WE       <= '1';
                     mem_RD       <= '0';
                     state        <= DL_WAIT;
                     -- a line the card port has buffered is replaced
                     if (line_ok = '1' and line_tag = dl_waddr(25 downto 3)) then
                        line_ok <= '0';
                     end if;
                  elsif (cm_req = '1') then
                     if (cm_we = '1') then
                        be := (others => '0');
                        case c_lane is
                           when 0      => be := be or x"03";
                           when 1      => be := be or x"0C";
                           when 2      => be := be or x"30";
                           when others => be := be or x"C0";
                        end case;
                        mem_request  <= '1';
                        mem_BURSTCNT <= x"01";
                        mem_ADDR     <= std_logic_vector(BASE + (c_tag & "000"));
                        mem_DIN      <= cm_wdata & cm_wdata & cm_wdata & cm_wdata;
                        mem_BE       <= be;
                        mem_WE       <= '1';
                        mem_RD       <= '0';
                        state        <= WR_WAIT;
                        if (line_ok = '1' and line_tag = c_tag) then
                           case c_lane is
                              when 0      => line(15 downto 0)  <= cm_wdata;
                              when 1      => line(31 downto 16) <= cm_wdata;
                              when 2      => line(47 downto 32) <= cm_wdata;
                              when others => line(63 downto 48) <= cm_wdata;
                           end case;
                        end if;
                     elsif (line_ok = '1' and line_tag = c_tag) then
                        cm_rdata <= lanes(line, c_lane);
                        cm_ack   <= '1';
                        state    <= ACK1;
                     else
                        mem_request  <= '1';
                        mem_BURSTCNT <= x"01";
                        mem_ADDR     <= std_logic_vector(BASE + (c_tag & "000"));
                        mem_BE       <= x"FF";
                        mem_WE       <= '0';
                        mem_RD       <= '1';
                        state        <= RD_WAITACK;
                     end if;
                  end if;

               when DL_WAIT =>
                  if (mem_ack = '1') then
                     mem_request <= '0';
                     dl_busy     <= '0';
                     state       <= IDLE;
                  end if;

               when RD_WAITACK =>
                  if (mem_ack = '1') then
                     state <= RD_WAITDATA;
                  end if;

               when RD_WAITDATA =>
                  if (mem_DOUT_READY = '1') then
                     mem_request <= '0';
                     line        <= mem_DOUT;
                     line_tag    <= c_tag;
                     line_ok     <= '1';
                     cm_rdata    <= lanes(mem_DOUT, c_lane);
                     cm_ack      <= '1';
                     state       <= ACK1;
                  end if;

               when WR_WAIT =>
                  if (mem_ack = '1') then
                     mem_request <= '0';
                     cm_ack      <= '1';
                     state       <= ACK1;
                  end if;

               -- ack held for two clk2x cycles: one clk1x edge
               when ACK1 =>
                  state <= ACK2;

               when ACK2 =>
                  cm_ack <= '0';
                  state  <= HOLD;

               when HOLD =>
                  if (cm_req = '0') then
                     state <= IDLE;
                  end if;

            end case;
         end if;
      end if;
   end process;

end architecture;
