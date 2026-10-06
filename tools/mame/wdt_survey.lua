-- MB3773 watchdog kick survey (MAME 0.288, Taito G-NET).
-- A kick is a falling edge of bit 5 written to the control register
-- 0x1fb40000 (taitogn.cpp control_w -> mb3773 write_line_ck; mb3773.cpp
-- re-arms its 5 s timer on ck 1 -> 0). Device reset arms it at t = 0.
-- Writes $WDT_OUT/kicks.log: one line per kick "t pc gap" (gap = emulated s
-- since the previous kick or reset), "RESET t" on a machine reset, and
-- "END t open_gap" at the stop. Inputs as tools/mame/oracle.lua with
-- $WDT_COIN_AT: coin 1 for 0.1 s, start 2 s later, fire held from +5 s
-- with left/right movement. $WDT_STOP: emulated seconds to run.
local fmt = string.format
local OUT = os.getenv("WDT_OUT") or "."
local STOP = tonumber(os.getenv("WDT_STOP") or "60")
local COIN_AT = tonumber(os.getenv("WDT_COIN_AT") or "")
local m = manager.machine
local cpu = m.devices[":maincpu"]
local sp = cpu.spaces["program"]
local pcst = cpu.state["pc"]
local log = io.open(OUT .. "/kicks.log", "w")
local function now() return m.time:as_double() end
WDT = { taps = {}, subs = {} }
local ck, last = 0, 0.0
WDT.taps.ctrl = sp:install_write_tap(0x1fb40000, 0x1fb40003, "wdt_ctrl", function(o, d, mk)
  if mk & 0xff == 0 then return end
  local b = (d >> 5) & 1
  if b == 0 and ck == 1 then
    local t = now()
    log:write(fmt("%.9f %08x %.9f\n", t, pcst.value, t - last))
    last = t
  end
  ck = b
end)
local function field(name)
  for _, p in pairs(m.ioport.ports) do
    for fname, f in pairs(p.fields) do if fname == name then return f end end
  end
end
local plan = {}
if COIN_AT then
  plan = { { COIN_AT, "Coin 1", 1 }, { COIN_AT + 0.1, "Coin 1", 0 },
           { COIN_AT + 2, "1 Player Start", 1 }, { COIN_AT + 2.1, "1 Player Start", 0 },
           { COIN_AT + 5, "P1 Button 1", 1 } }
end
local step, wiggle, wphase = 1, 0, -1
WDT.subs.reset = emu.add_machine_reset_notifier(function()
  local t = now()
  if t > 0 then log:write(fmt("RESET %.9f\n", t)) end
  ck, last = 0, t
end)
WDT.subs.frame = emu.add_machine_frame_notifier(function()
  local t = now()
  while plan[step] and t >= plan[step][1] do
    local f = field(plan[step][2]); if f then f:set_value(plan[step][3]) end
    step = step + 1
  end
  if COIN_AT and t > COIN_AT + 5 then
    wiggle = wiggle + 1
    local ph = (wiggle // 60) % 4
    if ph ~= wphase then
      wphase = ph
      local l, r = field("P1 Left"), field("P1 Right")
      if l and r then l:set_value(ph == 1 and 1 or 0); r:set_value(ph == 3 and 1 or 0) end
    end
  end
  if t >= STOP then log:write(fmt("END %.9f %.9f\n", t, t - last)); log:close(); m:exit() end
end)
