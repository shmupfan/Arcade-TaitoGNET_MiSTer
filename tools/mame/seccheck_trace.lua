-- G-NET BIOS security check trace (MAME 0.288, needs -debug -debugger none
-- -debuglog): docs/gnet_bios_security_check.md.
--   SEC_OUT=<dir under sim/oracle/> mame shikigam ... -autoboot_script this
-- Writes to SEC_OUT:
--   taps.log        CAT702 select writes (0x1fa10300) and U30 reads at
--                   0x1f000100-0x1f0003ff: emulated time, PC, data
--   trace.log       debugger instruction trace from the first frame, with
--                   tracelog markers BP_<name> at the breakpoints
--   ram_312c.bin    main RAM 0-0x3FFFFF at the first entry of 0x312C
--   src_1f000120.bin  the 0x2800 bytes 0x312C copies from U30 (CPU view)
--   ram_1f1c.bin    main RAM after 0x312C returns (0x1F1C)
--   dasm_*.txt      disassembly of the RAM code and of the BIOS targets
-- The debugger printf output (registers, COP0, I_STAT/I_MASK) goes to
-- debug.log in the working directory (-debuglog).
-- Env: SEC_OUT, SEC_STOP (emulated s, default 0.1).
local fmt = string.format
local OUT = os.getenv("SEC_OUT") or "."
local STOP = tonumber(os.getenv("SEC_STOP") or "0.1")
local m = manager.machine
local cpu = m.devices[":maincpu"]
local sp = cpu.spaces["program"]
local pcst = cpu.state["pc"]
local log = io.open(OUT .. "/taps.log", "w")
local function now() return m.time:as_double() end
SEC = { taps = {}, subs = {} }
local nhdr = 0
SEC.taps.sel = sp:install_write_tap(0x1fa10300, 0x1fa10303, "sec_sel", function(o, d, mk)
  log:write(fmt("%.9f SEL pc=%08x d=%02x\n", now(), pcst.value, d & 0xff))
end)
SEC.taps.hdr = sp:install_read_tap(0x1f000100, 0x1f0003ff, "sec_hdr", function(o, d, mk)
  nhdr = nhdr + 1
  if nhdr <= 64 then log:write(fmt("%.9f HDR pc=%08x a=%08x d=%08x m=%08x\n", now(), pcst.value, o, d, mk)) end
end)
local REGS = 'a0=%x a1=%x a2=%x a3=%x t0=%x t1=%x v0=%x v1=%x s6=%x sp=%x ra=%x SR=%x Cause=%x EPC=%x ISTAT=%x IMASK=%x'
local REGV = 'a0,a1,a2,a3,t0,t1,v0,v1,s6,sp,ra,SR,Cause,EPC,d@1f801070,d@1f801074'
local started = false
SEC.subs.frame = emu.add_machine_frame_notifier(function()
  local t = now()
  if not started then
    started = true
    local d = m.debugger
    local function c(s) d:command(s) end
    c(fmt('trace %s/trace.log,maincpu', OUT))
    -- 1: entry of the descramble routine; 2: chunk guard; 3: return to caller
    c(fmt('bpset 312c,1,{tracelog "BP_312C\\n";printf "BP_312C %s\\n",%s;save %s/ram_312c.bin,0,400000;save %s/src_1f000120.bin,1f000120,2800;dasm %s/dasm_ram_1d00_3400.txt,1d00,1700;bpdisable 1;g}', REGS, REGV, OUT, OUT, OUT))
    c(fmt('bpset 3170,1,{tracelog "BP_3170\\n";printf "BP_3170 %s\\n",%s;bpdisable 2;g}', REGS, REGV))
    c(fmt('bpset 1f1c,1,{tracelog "BP_1F1C\\n";printf "BP_1F1C fp=%%x %s\\n",fp,%s;save %s/ram_1f1c.bin,0,400000;bpdisable 3;g}', REGS, REGV, OUT))
    -- exception vector and the A(40h) target: logged on every hit
    c(fmt('bpset 80000080,1,{tracelog "BP_EXC\\n";printf "BP_EXC %s\\n",%s;g}', REGS, REGV))
    c(fmt('bpset 80,1,{tracelog "BP_EXC0\\n";printf "BP_EXC0 %s\\n",%s;g}', REGS, REGV))
    c(fmt('bpset bfc0b530,1,{tracelog "BP_A40\\n";printf "BP_A40 %s\\n",%s;g}', REGS, REGV))
    c(fmt('dasm %s/dasm_bios_b4c0_b600.txt,bfc0b4c0,140', OUT))
    c(fmt('dasm %s/dasm_vec_80.txt,80000080,80', OUT))
    m.debugger.execution_state = "run"
    log:write(fmt("%.9f START trace and breakpoints\n", t))
  end
  if t >= STOP then
    log:write(fmt("%.9f STOP hdr_reads=%d\n", t, nhdr)); log:close(); m:exit()
  end
end)
