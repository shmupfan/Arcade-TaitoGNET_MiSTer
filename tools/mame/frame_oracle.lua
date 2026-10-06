-- Frame oracle (MAME 0.288): every video frame's visible bitmap, for
-- tools/frame_hash.py mame <dir> (which turns them into frames.tsv and
-- deletes them).
-- Env: FRAME_OUT (dir under sim/oracle/), FRAME_STOP (emulated s, default
-- 60), FRAME_COIN_AT (optional; inputs as tools/mame/oracle.lua: coin 1 for
-- 0.1 s, start 2 s later, fire held from +5 s with left/right movement).
-- Writes FRAME_OUT/times.tsv (frame, machine time at the frame notifier,
-- w, h) and FRAME_OUT/raw/f<frame>_<w>x<h>.argb (32-bit ARGB, little-
-- endian, row major); about 300 KB per 320 x 240 frame.
local fmt = string.format
local OUT = os.getenv("FRAME_OUT") or "."
local STOP = tonumber(os.getenv("FRAME_STOP") or "60")
local COIN_AT = tonumber(os.getenv("FRAME_COIN_AT") or "")
local m = manager.machine
local scr = m.screens[":screen"]
os.execute("mkdir -p '" .. OUT .. "/raw'")
local times = assert(io.open(OUT .. "/times.tsv", "w"))
times:write("#frame\tt_s\tw\th\n")
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
local step, wiggle, wphase, frame = 1, 0, -1, 0
FRAMEO = {}
FRAMEO.frame = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  local t = m.time:as_double()
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
  local s, w, h = scr:pixels()
  times:write(fmt("%d\t%.6f\t%d\t%d\n", frame, t, w, h))
  local f = assert(io.open(fmt("%s/raw/f%05d_%dx%d.argb", OUT, frame, w, h), "wb"))
  f:write(s); f:close()
  if t >= STOP then times:close(); m:exit() end
end)
