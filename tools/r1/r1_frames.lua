-- R1 speed study (MAME 0.288): per-frame screen signature for event timing.
-- Each frame: emulated time, frame count, mean R/G/B over a 32 x 24 grid of
-- the visible area, mean absolute difference to the previous frame, and the
-- screen's visible size. Optional inputs: R1_COIN_AT (emulated s) inserts a
-- coin (0.1 s pulse) and starts a game 2 s later.
-- Env: R1_OUT (csv path), R1_SNAP_EVERY (frames between PNG snapshots,
-- default 0 = none; written as f<frame>.png under -snapshot_directory).
local out = assert(io.open(os.getenv("R1_OUT") or "r1_frames.csv", "w"))
out:write("frame,t,w,h,r,g,b,diff\n")
local scr
for tag, s in pairs(manager.machine.screens) do scr = s; break end
local GX, GY = 32, 24
local prev = {}
R1_N = 0
local coin_at = tonumber(os.getenv("R1_COIN_AT") or "-1")
local plan = {}
if coin_at >= 0 then
  plan = { { coin_at, "Coin 1", 1 }, { coin_at + 0.1, "Coin 1", 0 },
           { coin_at + 2, "1 Player Start", 1 }, { coin_at + 2.1, "1 Player Start", 0 } }
end
local step = 1
local snap_every = tonumber(os.getenv("R1_SNAP_EVERY") or "0")
local function field(name)
  for _, p in pairs(manager.machine.ioport.ports) do
    for fname, f in pairs(p.fields) do if fname == name then return f end end
  end
end
R1_FRAME = emu.add_machine_frame_notifier(function()
  R1_N = R1_N + 1
  local t = manager.machine.time:as_double()
  while plan[step] and t >= plan[step][1] do
    local f = field(plan[step][2]); if f then f:set_value(plan[step][3]) end
    step = step + 1
  end
  -- screen:pixel takes coordinates within the visible area (0.288 has no
  -- visible_area binding; width/height are the visible size)
  local x0, y0, vw, vh = 0, 0, scr.width, scr.height
  local sr, sg, sb, d = 0, 0, 0, 0
  local i = 0
  for gy = 0, GY - 1 do
    for gx = 0, GX - 1 do
      local p = scr:pixel(x0 + math.floor((gx + 0.5) * vw / GX), y0 + math.floor((gy + 0.5) * vh / GY))
      local r, g, b = (p >> 16) & 0xff, (p >> 8) & 0xff, p & 0xff
      i = i + 1
      local q = prev[i]
      if q then d = d + math.abs(r - (q >> 16 & 0xff)) + math.abs(g - (q >> 8 & 0xff)) + math.abs(b - (q & 0xff)) end
      prev[i] = p
      sr, sg, sb = sr + r, sg + g, sb + b
    end
  end
  local n = GX * GY
  if snap_every > 0 and R1_N % snap_every == 0 then scr:snapshot(string.format("f%06d.png", R1_N)) end
  out:write(string.format("%d,%.6f,%d,%d,%.1f,%.1f,%.1f,%.2f\n", R1_N, t, vw, vh, sr / n, sg / n, sb / n, d / (3 * n)))
end)
R1_STOP = emu.add_machine_stop_notifier(function() out:close() end)
