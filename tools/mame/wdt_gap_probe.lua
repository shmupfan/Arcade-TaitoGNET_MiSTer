-- Watchdog gap probe (MAME 0.288): logs every
-- MB3773 kick (bit 5 falling edge at 0x1fb40000), every write to
-- 0x1fb40000, and the main CPU PC at each frame, to $GAP_OUT/gap.log.
-- $GAP_STOP: emulated seconds to run (default 12).
local fmt = string.format
local OUT = os.getenv("GAP_OUT") or "."
local STOP = tonumber(os.getenv("GAP_STOP") or "12")
local m = manager.machine
local cpu = m.devices[":maincpu"]
local sp = cpu.spaces["program"]
local pcst = cpu.state["pc"]
local log = io.open(OUT .. "/gap.log", "w")
local function now() return m.time:as_double() end
GAP = { subs = {} }
local ck, last, frame = 0, 0.0, 0
GAP.tap = sp:install_write_tap(0x1fb40000, 0x1fb40003, "gap_ctrl", function(o, d, mk)
  if mk & 0xff == 0 then return end
  local t = now()
  local b = (d >> 5) & 1
  log:write(fmt("%.6f W %02x pc=%08x fr=%d\n", t, d & 0xff, pcst.value, frame))
  if b == 0 and ck == 1 then
    log:write(fmt("%.6f KICK pc=%08x gap=%.6f fr=%d\n", t, pcst.value, t - last, frame)); last = t
  end
  ck = b
end)
GAP.subs.frame = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  log:write(fmt("%.6f F%d pc=%08x\n", now(), frame, pcst.value))
  if now() >= STOP then log:write(fmt("%.6f END open_gap=%.6f\n", now(), now() - last)); log:close(); m:exit() end
end)
