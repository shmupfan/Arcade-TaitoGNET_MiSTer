-- Equivalence bench for the sys/ascal.vhd o_vline change (docs/hdmi_timing.md F5).
--
-- Copyright (C) 2026 Lee Foot
-- SPDX-License-Identifier: GPL-2.0-or-later
--
-- Two scalers on the same stimulus: ascal_orig (sys/ascal.vhd at git HEAD,
-- entity renamed by run.sh) and ascal (the working tree). Each has its own
-- Avalon memory model. Every o_clk the video outputs are compared, every
-- avl_clk the Avalon requests and write data; any difference is counted.
-- SCEN: 0 progressive 240p style, 1 HPS framebuffer 16 bpp with a stride
-- that is not a multiple of 16 bytes, 2 interlaced input with bob
-- deinterlace, 3 interlaced input with weave.
-- The orig instance also logs, from its internals, the fewest o_clk cycles
-- between an o_vacpt change and the next read request (o_read_pre toggle)
-- with o_fload = 0.

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE std.textio.ALL;

ENTITY avl_mem IS
	PORT (
		clk           : IN  std_logic;
		read          : IN  std_logic;
		write         : IN  std_logic;
		address       : IN  std_logic_vector(27 DOWNTO 0);
		burstcount    : IN  std_logic_vector(7 DOWNTO 0);
		writedata     : IN  std_logic_vector(127 DOWNTO 0);
		readdata      : OUT std_logic_vector(127 DOWNTO 0);
		readdatavalid : OUT std_logic
		);
END ENTITY avl_mem;

ARCHITECTURE sim OF avl_mem IS
	CONSTANT NW : natural := 2**16;
	TYPE mem_t IS ARRAY (0 TO NW-1) OF std_logic_vector(127 DOWNTO 0);
	TYPE q_t IS ARRAY (0 TO 15) OF natural;
BEGIN
	PROCESS (clk)
		VARIABLE mem    : mem_t;
		VARIABLE valid  : bit_vector(0 TO NW-1) := (OTHERS => '0');
		VARIABLE wbase, wbeat : natural := 0;
		VARIABLE qa, qn, qt : q_t;
		VARIABLE qh, ql : natural := 0;  -- queue head (next out) and length
		VARIABLE beat, now_c : natural := 0;
		VARIABLE a, ix : natural;
		VARIABLE w : std_logic_vector(127 DOWNTO 0);
		IMPURE FUNCTION idx(wa : natural) RETURN natural IS
		BEGIN
			-- 16 K words per 8 MB buffer slot, four slots
			RETURN (wa MOD 2**14) + 2**14 * ((wa / 2**19) MOD 4);
		END FUNCTION;
	BEGIN
		IF rising_edge(clk) THEN
			now_c := now_c + 1;
			IF write = '1' THEN
				IF wbeat = 0 THEN
					wbase := to_integer(unsigned(address));
				END IF;
				ix := idx(wbase + wbeat);
				mem(ix) := writedata;
				valid(ix) := '1';
				wbeat := wbeat + 1;
				IF wbeat = to_integer(unsigned(burstcount)) THEN
					wbeat := 0;
				END IF;
			END IF;
			IF read = '1' THEN
				qa((qh + ql) MOD 16) := to_integer(unsigned(address));
				qn((qh + ql) MOD 16) := to_integer(unsigned(burstcount));
				qt((qh + ql) MOD 16) := now_c + 6;
				ql := ql + 1;
			END IF;
			readdatavalid <= '0';
			IF ql > 0 AND now_c >= qt(qh) THEN
				a := qa(qh) + beat;
				ix := idx(a);
				IF valid(ix) = '1' THEN
					w := mem(ix);
				ELSE
					-- never written (framebuffer area): a pattern of the address
					FOR i IN 0 TO 15 LOOP
						w(i*8+7 DOWNTO i*8) := std_logic_vector(to_unsigned((a * 37 + i * 11) MOD 256, 8));
					END LOOP;
				END IF;
				readdata <= w;
				readdatavalid <= '1';
				beat := beat + 1;
				IF beat = qn(qh) THEN
					beat := 0;
					qh := (qh + 1) MOD 16;
					ql := ql - 1;
				END IF;
			END IF;
		END IF;
	END PROCESS;
END ARCHITECTURE sim;

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE std.textio.ALL;

ENTITY tb IS
	GENERIC (
		SCEN   : natural := 0;
		FRAMES : natural := 12   -- output frames to run
		);
END ENTITY tb;

ARCHITECTURE sim OF tb IS
	SIGNAL i_clk, o_clk, avl_clk : std_logic := '0';
	SIGNAL reset_na : std_logic := '0';
	SIGNAL i_r, i_g, i_b : unsigned(7 DOWNTO 0) := x"00";
	SIGNAL i_hs, i_vs, i_fl, i_de, i_ce : std_logic := '0';

	TYPE vout_t IS RECORD
		r, g, b : unsigned(7 DOWNTO 0);
		hs, vs, de, vbl, brd : std_logic;
	END RECORD;
	TYPE avl_t IS RECORD
		read, write : std_logic;
		address     : std_logic_vector(27 DOWNTO 0);
		burstcount  : std_logic_vector(7 DOWNTO 0);
		writedata   : std_logic_vector(127 DOWNTO 0);
		readdata    : std_logic_vector(127 DOWNTO 0);
		readdatavalid : std_logic;
	END RECORD;
	SIGNAL v0, v1 : vout_t;
	SIGNAL a0, a1 : avl_t;

	FUNCTION sl(b : boolean) RETURN std_logic IS
	BEGIN
		IF b THEN RETURN '1'; ELSE RETURN '0'; END IF;
	END FUNCTION;
	CONSTANT FB_ENA    : std_logic := sl(SCEN = 1);
	CONSTANT INTERLACE : boolean := SCEN = 2 OR SCEN = 3;
	CONSTANT BOB       : std_logic := sl(SCEN = 2);
	-- input: 160 x 60 active (per field when interlaced), 200 x 66 total
	CONSTANT IHT : natural := 200; CONSTANT IHA : natural := 160;
	CONSTANT IVT : natural := 66;  CONSTANT IVA : natural := 60;
	-- output: 320 x 120 active, 360 x 126 total
	CONSTANT OHT : natural := 360; CONSTANT OHA : natural := 320;
	CONSTANT OVT : natural := 126; CONSTANT OVA : natural := 120;

	SIGNAL done : boolean := false;
	SIGNAL vid_diff, avl_diff, reads, writes, lit, oframes : natural := 0;
	SIGNAL min_gap : natural := 1000000;
	SIGNAL gap_reads : natural := 0;
	SIGNAL inter_cyc, bob_cyc : natural := 0;

BEGIN
	o_clk   <= NOT o_clk   AFTER 3366 ps WHEN NOT done;  -- 148.5 MHz
	i_clk   <= NOT i_clk   AFTER 10 ns   WHEN NOT done;  -- 50 MHz
	avl_clk <= NOT avl_clk AFTER 5 ns    WHEN NOT done;  -- 100 MHz
	reset_na <= '1' AFTER 200 ns;

	-- input video, a pixel every second i_clk
	gen : PROCESS (i_clk)
		VARIABLE ce : std_logic := '0';
		VARIABLE x, y, fr : natural := 0;
	BEGIN
		IF rising_edge(i_clk) THEN
			ce := NOT ce;
			i_ce <= ce;
			IF ce = '1' THEN
				i_de <= '1' WHEN x < IHA AND y < IVA ELSE '0';
				i_hs <= '1' WHEN x >= 170 AND x < 180 ELSE '0';
				i_vs <= '1' WHEN y >= 62 AND y < 64 ELSE '0';
				i_fl <= '1' WHEN INTERLACE AND fr MOD 2 = 1 ELSE '0';
				i_r <= to_unsigned((x + 3 * fr) MOD 256, 8);
				i_g <= to_unsigned((y * 4 + fr) MOD 256, 8);
				i_b <= to_unsigned((x * y + 5 * fr) MOD 256, 8);
				x := x + 1;
				IF x = IHT THEN
					x := 0;
					y := y + 1;
					IF y = IVT THEN
						y := 0;
						fr := fr + 1;
					END IF;
				END IF;
			END IF;
		END IF;
	END PROCESS;

	u0 : ENTITY work.ascal_orig
		GENERIC MAP (RAMBASE => x"20000000", RAMSIZE => x"00800000",
			PALETTE2 => false, ADAPTIVE => false, DOWNSCALE_NN => true,
			FRAC => 8, N_DW => 128, N_AW => 28)
		PORT MAP (
			i_r => i_r, i_g => i_g, i_b => i_b, i_hs => i_hs, i_vs => i_vs,
			i_fl => i_fl, i_de => i_de, i_ce => i_ce, i_clk => i_clk,
			o_r => v0.r, o_g => v0.g, o_b => v0.b, o_hs => v0.hs, o_vs => v0.vs,
			o_de => v0.de, o_vbl => v0.vbl, o_brd => v0.brd, o_ce => '1', o_clk => o_clk,
			o_fb_ena => FB_ENA, o_fb_hsize => 150, o_fb_vsize => 100,
			o_fb_format => "000100", o_fb_base => x"31800000",
			o_fb_stride => to_unsigned(302, 14),
			o_lltune => OPEN, i_hdmax => OPEN, i_vdmax => OPEN,
			mode => "00000", bob_deint => BOB,
			htotal => OHT, hsstart => OHA + 10, hsend => OHA + 20, hdisp => OHA,
			hmin => 0, hmax => OHA - 1,
			vtotal => OVT, vsstart => OVA + 2, vsend => OVA + 4, vdisp => OVA,
			vmin => 0, vmax => OVA - 1,
			poly_clk => i_clk, poly_dw => (OTHERS => '0'), poly_a => (OTHERS => '0'), poly_wr => '0',
			avl_clk => avl_clk, avl_waitrequest => '0',
			avl_readdata => a0.readdata, avl_readdatavalid => a0.readdatavalid,
			avl_burstcount => a0.burstcount, avl_writedata => a0.writedata,
			avl_address => a0.address, avl_write => a0.write, avl_read => a0.read,
			avl_byteenable => OPEN, reset_na => reset_na);

	u1 : ENTITY work.ascal
		GENERIC MAP (RAMBASE => x"20000000", RAMSIZE => x"00800000",
			PALETTE2 => false, ADAPTIVE => false, DOWNSCALE_NN => true,
			FRAC => 8, N_DW => 128, N_AW => 28)
		PORT MAP (
			i_r => i_r, i_g => i_g, i_b => i_b, i_hs => i_hs, i_vs => i_vs,
			i_fl => i_fl, i_de => i_de, i_ce => i_ce, i_clk => i_clk,
			o_r => v1.r, o_g => v1.g, o_b => v1.b, o_hs => v1.hs, o_vs => v1.vs,
			o_de => v1.de, o_vbl => v1.vbl, o_brd => v1.brd, o_ce => '1', o_clk => o_clk,
			o_fb_ena => FB_ENA, o_fb_hsize => 150, o_fb_vsize => 100,
			o_fb_format => "000100", o_fb_base => x"31800000",
			o_fb_stride => to_unsigned(302, 14),
			o_lltune => OPEN, i_hdmax => OPEN, i_vdmax => OPEN,
			mode => "00000", bob_deint => BOB,
			htotal => OHT, hsstart => OHA + 10, hsend => OHA + 20, hdisp => OHA,
			hmin => 0, hmax => OHA - 1,
			vtotal => OVT, vsstart => OVA + 2, vsend => OVA + 4, vdisp => OVA,
			vmin => 0, vmax => OVA - 1,
			poly_clk => i_clk, poly_dw => (OTHERS => '0'), poly_a => (OTHERS => '0'), poly_wr => '0',
			avl_clk => avl_clk, avl_waitrequest => '0',
			avl_readdata => a1.readdata, avl_readdatavalid => a1.readdatavalid,
			avl_burstcount => a1.burstcount, avl_writedata => a1.writedata,
			avl_address => a1.address, avl_write => a1.write, avl_read => a1.read,
			avl_byteenable => OPEN, reset_na => reset_na);

	m0 : ENTITY work.avl_mem PORT MAP (avl_clk, a0.read, a0.write, a0.address, a0.burstcount,
		a0.writedata, a0.readdata, a0.readdatavalid);
	m1 : ENTITY work.avl_mem PORT MAP (avl_clk, a1.read, a1.write, a1.address, a1.burstcount,
		a1.writedata, a1.readdata, a1.readdatavalid);

	cmp_v : PROCESS (o_clk)
		VARIABLE l : line;
		VARIABLE vs_d : std_logic := '0';
		VARIABLE since : natural := 1000000;
		VARIABLE vac_d : unsigned(11 DOWNTO 0) := (OTHERS => '0');
		VARIABLE rp_d : std_logic := '0';
		ALIAS orig_vacpt   IS <<SIGNAL .tb.u0.o_vacpt   : unsigned(11 DOWNTO 0)>>;
		ALIAS orig_readpre IS <<SIGNAL .tb.u0.o_read_pre : std_logic>>;
		ALIAS orig_fload   IS <<SIGNAL .tb.u0.o_fload   : natural>>;
		ALIAS orig_inter   IS <<SIGNAL .tb.u0.o_inter   : std_logic>>;
		ALIAS orig_bob     IS <<SIGNAL .tb.u0.o_bob_deint : std_logic>>;
	BEGIN
		IF rising_edge(o_clk) AND reset_na = '1' THEN
			IF v0 /= v1 THEN
				IF vid_diff < 10 THEN
					write(l, "video differs at " & time'image(now) & " frame " & integer'image(oframes));
					writeline(output, l);
				END IF;
				vid_diff <= vid_diff + 1;
			END IF;
			IF v0.de = '1' AND (v0.r /= 0 OR v0.g /= 0 OR v0.b /= 0) THEN
				lit <= lit + 1;
			END IF;
			IF v0.vs = '1' AND vs_d = '0' THEN
				oframes <= oframes + 1;
				IF oframes + 1 = FRAMES THEN
					done <= true;
				END IF;
			END IF;
			vs_d := v0.vs;
			-- cycles since the last o_vacpt change, at each read request
			IF orig_vacpt /= vac_d THEN
				since := 0;
			ELSE
				since := since + 1;
			END IF;
			vac_d := orig_vacpt;
			IF orig_readpre /= rp_d AND orig_fload = 0 THEN
				gap_reads <= gap_reads + 1;
				IF since < min_gap THEN
					min_gap <= since;
				END IF;
			END IF;
			rp_d := orig_readpre;
			IF orig_inter = '1' THEN
				inter_cyc <= inter_cyc + 1;
				IF orig_bob = '1' THEN
					bob_cyc <= bob_cyc + 1;
				END IF;
			END IF;
		END IF;
	END PROCESS;

	cmp_a : PROCESS (avl_clk)
		VARIABLE l : line;
	BEGIN
		IF rising_edge(avl_clk) AND reset_na = '1' THEN
			IF a0.read /= a1.read OR a0.write /= a1.write OR
			   ((a0.read = '1' OR a0.write = '1') AND a0.address /= a1.address) OR
			   (a0.write = '1' AND a0.writedata /= a1.writedata) THEN
				IF avl_diff < 10 THEN
					write(l, "avalon differs at " & time'image(now));
					writeline(output, l);
				END IF;
				avl_diff <= avl_diff + 1;
			END IF;
			IF a0.read = '1' THEN reads <= reads + 1; END IF;
			IF a0.write = '1' THEN writes <= writes + 1; END IF;
		END IF;
	END PROCESS;

	report_p : PROCESS
		VARIABLE l : line;
	BEGIN
		WAIT UNTIL done;
		write(l, "SCEN " & integer'image(SCEN) & ": frames " & integer'image(oframes) &
			" video_diff " & integer'image(vid_diff) & " avalon_diff " & integer'image(avl_diff) &
			" reads " & integer'image(reads) & " write_beats " & integer'image(writes) &
			" lit_pixels " & integer'image(lit) &
			" read_requests_fload0 " & integer'image(gap_reads) &
			" min_cycles_vacpt_to_read " & integer'image(min_gap) &
			" o_clk_inter " & integer'image(inter_cyc) & " o_clk_inter_bob " & integer'image(bob_cyc));
		writeline(output, l);
		WAIT;
	END PROCESS;
END ARCHITECTURE sim;
