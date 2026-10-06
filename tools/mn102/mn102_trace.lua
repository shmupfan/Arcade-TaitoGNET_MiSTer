-- MN10200 (Taito Zoom sound CPU) I/O oracle for MAME 0.288, used with
-- tools/mn102/mn102_trace.sh. Logs every access by the MN10200 to its
-- internal registers (0x00fc00-0x00ffff) and to the ZSG-2, TMS57002 and
-- mailbox windows, with the CPU's PC, and drives coin / start / fire so the
-- sound driver sees gameplay commands.
-- Env: MN102_OUT (log file), MN102_COIN_AT (emulated s, default 20).
local out = assert(io.open(os.getenv("MN102_OUT") or "mn102_io.log", "w"))
local coin_at = tonumber(os.getenv("MN102_COIN_AT") or "20")
local cpu = manager.machine.devices[":taito_zoom:mn10200"]
local sp = cpu.spaces["program"]
local function t() return manager.machine.time:as_double() end
local function pc() return cpu.state["PC"].value end
local function tap(lo, hi, name)
  MN102_TAPS = MN102_TAPS or {}
  table.insert(MN102_TAPS, sp:install_read_tap(lo, hi, name .. "r", function(o, d, m)
    out:write(string.format("%.6f R %06x %04x %04x %06x\n", t(), o, d, m, pc())) end))
  table.insert(MN102_TAPS, sp:install_write_tap(lo, hi, name .. "w", function(o, d, m)
    out:write(string.format("%.6f W %06x %04x %04x %06x\n", t(), o, d, m, pc())) end))
end
tap(0x00fc00, 0x00ffff, "io")
tap(0x800000, 0x8007ff, "zsg2")
tap(0xc00000, 0xc00001, "tms")
tap(0xe00000, 0xe000ff, "mbox")
-- PC trace through the debugger (MAME must run with -debug -debugger none)
local tf = os.getenv("MN102_TRACE")
if tf and manager.machine.debugger then
  manager.machine.debugger:command("trace " .. tf .. ",:taito_zoom:mn10200,noloop")
  out:write(string.format("%.6f TRACE %s\n", t(), tf))
end
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
MN102_FRAME = emu.add_machine_frame_notifier(function()
  local now = t()
  while plan[step] and now >= plan[step][1] do
    local f = field(plan[step][2])
    if f then f:set_value(plan[step][3]) end
    out:write(string.format("%.6f INPUT %s %d\n", now, plan[step][2], plan[step][3]))
    step = step + 1
  end
  if now > coin_at + 5 then
    local l, r = field("P1 Left"), field("P1 Right")
    local ph = math.floor(now * 2) % 2
    if l then l:set_value(ph) end
    if r then r:set_value(1 - ph) end
  end
end)
MN102_STOP = emu.add_machine_stop_notifier(function()
  if tf and manager.machine.debugger then manager.machine.debugger:command("trace off,:taito_zoom:mn10200") end
  out:write(string.format("%.6f END\n", t())); out:close()
end)
