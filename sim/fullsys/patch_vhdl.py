#!/usr/bin/env python3
"""Simulation-only copies of PSX_MiSTer VHDL for GHDL synthesis
(docs/fullsys_sim.md, workarounds). rtl/ is never edited.

  patch_vhdl.py <rtl_dir> <out_dir>

W1 gpu_crosshair, justifier_sensor, gpu_overlay: GHDL rejects a natural
   actual (to_integer of an unsigned) on an "integer range 0 to 1023" input
   ("bounds or direction of actual don't match"); the y inputs become natural.
W2 export: package pexport declares a signal nothing reads; GHDL synthesis
   has no signals in packages. Dropped.
W3 gpu_poly: no abs() on integer in GHDL synthesis ("unhandled dyn
   operation"); calls fs_util.fs_iabs.
W5 gpu_line, gpu_poly, gpu: the divider records are inout ports (the GPU
   unit drives start/dividend/divisor, gpu.vhd the results). GHDL synthesis
   stops with an internal error; each divN port is split into divN (out)
   and divN_i (in), and gpu.vhd wires line_div_o/poly_div_o to the OR mux.
W6 gpu_poly: "(signed13 & x"00000000") + x"100000000" - 2048" makes GHDL
   synthesis raise TYPES.INTERNAL_ERROR (netlists-utils.adb:166). The 36-bit
   literal (+2**32) is written as (to_signed(1, 13) & x"00000000"), the
   same 45-bit value.
W9 gnet/zn2_io (zn2-layer tree only): the byte lane slice
   p_wdata(8 * lane_byte(p_be) + 7 downto 8 * lane_byte(p_be)) is a port map
   actual that is not a static name ("actual must be a static name") and a
   dynamic slice GHDL synthesis cannot extract ("cannot extract same
   variable part"). The copy selects the lane with a case function fs_lane.
W10 gnet/zn2_cardmem (zn2-layer tree only): be(2 * c_lane + 1 downto
   2 * c_lane) := "11" on a variable raises TYPES.INTERNAL_ERROR
   (elab-vhdl_expr.adb:1114); the copy sets the two bits one by one.

Experiments (off unless the environment variable is set; they change
behaviour and are not workarounds):
FS_EXP_GPUVER=<n>  gpu.vhd answers GP1(10h) index 7 (GPU version) with n,
   as MAME's CXD8654Q does with 2 (psxgpu.cpp, gputype 2). Upstream leaves
   GPUREAD unchanged for index 7.
FS_EXP_FLREAD_BE=1  zn2_board.vhd flash storage port reads with all four
   byte enables (writes keep the lane mask). Upstream reads with "1100" or
   "0011", and sdram.sv puts ~be[1:0] on A12:A11 = DQMH:DQML at the READ, so an
   odd word's burst is masked (SDRAM read DQM latency 2).
FS_EXP_SIO0RD=1  zn_sio0.vhd bus reads decode bus_addr(3 downto 1) and put
   halfword reads at offsets 2/6/A/E in bits 15:0, as joypad.vhd and sio.vhd
   do (memorymux applies only rotate16 to pad reads). Upstream decodes
   bus_addr(3 downto 2), so a JOY_CTRL read (0x1F80104A) returns JOY_MODE.
"""
import re, sys, os

rtl, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)

def rd(n):
    return open(os.path.join(rtl, n + '.vhd'), encoding='latin-1').read()

def wr(n, t):
    open(os.path.join(out, n + '.vhd'), 'w', encoding='latin-1').write(t)

def sub(pat, rep, t, count_min=1, flags=0):
    t2, n = re.subn(pat, rep, t, flags=flags)
    if n < count_min:
        sys.exit('patch_vhdl: pattern not found: ' + pat)
    return t2

# W1
for n, pat in (('gpu_crosshair', r'(ypos_[a-z]+\s+:\s*in)\s+integer range 0 to 1023;'),
               ('justifier_sensor', r'(ypos_[a-z]+\s+:\s*in)\s+integer range 0 to 1023;'),
               ('gpu_overlay', r'(i_pixel_out_y\s+:\s*in)\s+integer range 0 to 1023;')):
    wr(n, sub(pat, r'\1 natural;', rd(n)))

# W2
wr('export', sub(r'\n\s*signal regs\s*:\s*tExportRegs;', '\n', rd('export')))

# W3 + W5
for n in ('gpu_line', 'gpu_poly'):
    t = rd(n)
    if n == 'gpu_poly':
        t = sub(r'(?<![a-z_])abs\(', 'fs_iabs(', t)
        t = sub(r'\nentity ', '\nuse work.fs_util.all;\nentity ', t)
        t = sub(r'\+ x"100000000" - 2048', '+ (to_signed(1, 13) & x"00000000") - 2048', t, 3)
    t = sub(r'(div[1-6])(\s*):\s*inout div_type;', r'\1\2: out div_type; \1_i : in div_type;', t, 6)
    t = sub(r'\b(div[1-6])\.(quotient|done|remainder)\b', r'\1_i.\2', t)
    wr(n, t)

t = rd('gpu')
t = sub(r'(\n\s*)(div[1-6])(\s*)=>\s*line_div\(([0-5])\),',
        r'\1\2\3=> line_div_o(\4), \2_i => line_div(\4),', t, 6)
t = sub(r'(\n\s*)(div[1-6])(\s*)=>\s*poly_div\(([0-5])\),',
        r'\1\2\3=> poly_div_o(\4), \2_i => poly_div(\4),', t, 6)
t = sub(r'(signal line_div\s*:\s*t_div_array;)', r'\1\n   signal line_div_o : t_div_array;\n   signal poly_div_o : t_div_array;', t)
t = sub(r'(line_div|poly_div)\(i\)\.(start|dividend|divisor)', r'\1_o(i).\2', t, 6)
if os.environ.get('FS_EXP_GPUVER'):
    v = int(os.environ['FS_EXP_GPUVER'])
    t = sub(r'(\n(\s*)when 5 => --Get Drawing Offset\n[^\n]*\n)',
            r'\1\2when 7 => GPUREAD <= x"%08X"; -- FS_EXP_GPUVER (sim experiment)\n' % v, t)
wr('gpu', t)
if os.path.exists(os.path.join(rtl, 'gnet', 'zn2_io.vhd')):
    # W9/W10 apply to zn2-layer up to 4ae0210; 6d8e332 removed both
    # constructs (Quartus audit Z1 to Z3), so the copies are then unchanged
    os.makedirs(os.path.join(out, 'gnet'), exist_ok=True)
    t = rd('gnet/zn2_io')
    lane = r'p_wdata\(8 \* lane_byte\(p_be\) \+ 7 downto 8 \* lane_byte\(p_be\)\)'
    if re.search(lane, t):
        t = sub(r'\nbegin\n', """
   function fs_lane(d : std_logic_vector(31 downto 0); be : std_logic_vector(3 downto 0)) return std_logic_vector is
   begin
      case lane_byte(be) is
         when 0      => return d(7 downto 0);
         when 1      => return d(15 downto 8);
         when 2      => return d(23 downto 16);
         when others => return d(31 downto 24);
      end case;
   end function;
begin
""", t)
        t = sub(lane, 'fs_lane(p_wdata, p_be)', t)
    wr('gnet/zn2_io', t)
    t = rd('gnet/zn2_cardmem')
    t = re.sub(r'be\(2 \* c_lane \+ 1 downto 2 \* c_lane\) := "11";', "be(2 * c_lane) := '1'; be(2 * c_lane + 1) := '1';", t)
    wr('gnet/zn2_cardmem', t)
if os.path.exists(os.path.join(rtl, 'gnet', 'zn2_board.vhd')):
    os.makedirs(os.path.join(out, 'gnet'), exist_ok=True)
    t = rd('gnet/zn2_board')
    if os.environ.get('FS_EXP_FLREAD_BE'):
        t = sub(r'if \(fmem_addr\(0\) = \'1\'\) then fl_be <= "1100"; else fl_be <= "0011"; end if;',
                'if (fmem_we = \'0\') then fl_be <= "1111"; elsif (fmem_addr(0) = \'1\') then fl_be <= "1100"; else fl_be <= "0011"; end if; -- FS_EXP_FLREAD_BE', t)
    wr('gnet/zn2_board', t)
if os.path.exists(os.path.join(rtl, 'gnet', 'zn_sio0.vhd')):
    t = rd('gnet/zn_sio0')
    if os.environ.get('FS_EXP_SIO0RD'):
        t = sub(r'case to_integer\(bus_addr\(3 downto 2\)\) is\s*when 0 =>\s*bus_dataRead <= x"000000" & rx_data;\s*'
                r'st_rxrdy\s*<= \'0\';\s*rx_data\s*<= x"FF";\s*when 1 =>\s*bus_dataRead <= x"0000" & status;\s*'
                r'when 2 =>\s*bus_dataRead <= ctrl & mode;\s*when others =>\s*bus_dataRead <= baud & x"0000";\s*end case;',
                """case to_integer(bus_addr(3 downto 1)) is -- FS_EXP_SIO0RD
                  when 0 | 1 =>
                     if (bus_addr(1) = '0') then bus_dataRead <= x"000000" & rx_data; end if;
                     st_rxrdy     <= '0';
                     rx_data      <= x"FF";
                  when 2 => bus_dataRead <= x"0000" & status;
                  when 4 => bus_dataRead <= ctrl & mode;
                  when 5 => bus_dataRead <= x"0000" & ctrl;
                  when 6 => bus_dataRead <= baud & x"0000";
                  when 7 => bus_dataRead <= x"0000" & baud;
                  when others => null;
               end case;""", t)
    os.makedirs(os.path.join(out, 'gnet'), exist_ok=True)
    wr('gnet/zn_sio0', t)
print('patched into', out)
