-- Every CPU write to the start and end bytes of spuzbobl's hiscore.dat block
-- (main RAM 0x28BF08 and 0x28C014) with its PC, around one soft reset at
-- HS_SOFTRESET_AT (default 30 s); log in $HS_OUT/wp.log (docs/hiscore.md 1).
-- Needs MAME's debugger for the watchpoints: run with -debug -debugger none
-- (tools/mame/hiscore_run.sh does).
if WP_LOADED then return end
WP_LOADED = true
local m = manager.machine
local cpu = m.devices[":maincpu"]
local sp = cpu.spaces["program"]
local OUT = os.getenv("HS_OUT") or "."
local SR_AT = tonumber(os.getenv("HS_SOFTRESET_AT") or "30")
local log = assert(io.open(OUT .. "/wp.log", "a"))
for _, base in ipairs({ 0x00000000, 0x80000000, 0xa0000000 }) do
  cpu.debug:wpset(sp, "w", base + 0x28bf08, 1, "1", "")
  cpu.debug:wpset(sp, "w", base + 0x28c014, 1, "1", "")
end
WP_NOTIF = emu.add_machine_frame_notifier(function()
  local t = m.time:as_double()
  if not WP_SR_DONE and t >= SR_AT then
    WP_SR_DONE = true
    log:write(string.format("%.4f soft_reset\n", t)); log:flush()
    m:soft_reset()
  end
end)
m.debugger.execution_state = "run"
WP_PERIODIC = emu.register_periodic(function()
  local d = m.debugger
  if d.execution_state == "stop" then
    log:write(string.format("%.6f hit pc=%08x start=%02x end=%02x\n", m.time:as_double(),
      (cpu.state["pc"] or cpu.state["CURPC"]).value, sp:read_u8(0x28bf08), sp:read_u8(0x28c014)))
    log:flush()
    d.execution_state = "run"
  end
end)
