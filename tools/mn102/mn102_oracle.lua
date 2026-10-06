-- MN10200 (Taito Zoom sound CPU) instruction-trace oracle for MAME 0.288,
-- used with tools/mn102/mn102_oracle.sh to verify rtl/zoom/mn10200*.sv.
--
-- Writes one stream, MN102_TRACE (a file or a FIFO; game-derived, keep it
-- under gitignored sim/): the debugger trace of :taito_zoom:mn10200
-- (noloop). Before each instruction a tracelog line
--   T pc d0 d1 d2 d3 a0 a1 a2 a3 psw mdr totalcycles fc57 fc50 fc42
-- with the state before that instruction executes (after any interrupt
-- entry), then MAME's disassembly line, then one line per access by that
-- instruction to the external devices (ZSG-2 0x800000-0x8007ff, TMS57002
-- 0xc00000, mailbox 0xe00000-0xe000ff):
--   B R|W addr data mask
-- The testbench replays the reads and checks the writes. The internal
-- registers 0xfc00-0xffff are not tapped, because the tracelog reads
-- fc57/fc50/fc42 through the debugger (no side effects on those).
local cpu = manager.machine.devices[":taito_zoom:mn10200"]
local sp = cpu.spaces["program"]
local dbg = manager.machine.debugger
local function tap(lo, hi, name)
  MN102_ORACLE_TAPS = MN102_ORACLE_TAPS or {}
  table.insert(MN102_ORACLE_TAPS, sp:install_read_tap(lo, hi, name .. "r", function(o, d, m)
    dbg:command(string.format('tracelog "B R %06x %04x %04x\\n"', o, d, m)) end))
  table.insert(MN102_ORACLE_TAPS, sp:install_write_tap(lo, hi, name .. "w", function(o, d, m)
    dbg:command(string.format('tracelog "B W %06x %04x %04x\\n"', o, d, m)) end))
end
tap(0x800000, 0x8007ff, "zsg2")
tap(0xc00000, 0xc00001, "tms")
tap(0xe00000, 0xe000ff, "mbox")
local tf = assert(os.getenv("MN102_TRACE"))
-- Landmine: tracelog evaluates its symbols in the debugger's visible CPU and
-- writes to that CPU's trace file. Without focus the visible CPU reverts to
-- the main CPU at the start-up break and the action prints nothing. focus
-- plus visible_cpu keeps it on the MN10200 from the first instruction.
dbg:command("focus :taito_zoom:mn10200")
dbg.visible_cpu = cpu
dbg:command("trace " .. tf .. ",:taito_zoom:mn10200,noloop,"
  .. "{tracelog \"T %06X %06X %06X %06X %06X %06X %06X %06X %06X %04X %04X %X %02X %02X %02X\\n\","
  .. "pc,d0,d1,d2,d3,a0,a1,a2,a3,curflags,mdr,totalcycles,b@fc57,b@fc50,b@fc42}")
MN102_ORACLE_STOP = emu.add_machine_stop_notifier(function()
  dbg:command("trace off,:taito_zoom:mn10200")
end)
-- Optional inputs so the sound driver gets gameplay commands: MN102_COIN_AT
-- (emulated seconds) inserts a coin, presses start 2 s later, fire from 5 s
-- later and alternates left / right every 0.5 s (as mn102_trace.lua).
local coin_at = tonumber(os.getenv("MN102_COIN_AT") or "")
if coin_at then
  local function field(name)
    for _, p in pairs(manager.machine.ioport.ports) do
      for fname, f in pairs(p.fields) do if fname == name then return f end end
    end
  end
  local plan = {
    { coin_at, "Coin 1", 1 }, { coin_at + 0.1, "Coin 1", 0 },
    { coin_at + 2, "1 Player Start", 1 }, { coin_at + 2.1, "1 Player Start", 0 },
    { coin_at + 5, "P1 Button 1", 1 },
  }
  local step = 1
  MN102_ORACLE_FRAME = emu.add_machine_frame_notifier(function()
    local now = manager.machine.time:as_double()
    while plan[step] and now >= plan[step][1] do
      local f = field(plan[step][2])
      if f then f:set_value(plan[step][3]) end
      step = step + 1
    end
    if now > coin_at + 5 then
      local l, r = field("P1 Left"), field("P1 Right")
      local ph = math.floor(now * 2) % 2
      if l then l:set_value(ph) end
      if r then r:set_value(1 - ph) end
    end
  end)
end
