-- Psyvariar play-through for reference captures (MAME 0.288).
-- Coin 1 + start at PLAY_AT, then fire held with left/right/up movement,
-- and coin + start pulsed every PLAY_CONT s (auto-continue), so play goes on
-- past deaths. Snapshot every PLAY_SNAP frames to snap/f<frame>.png (native
-- resolution, MAME applies the ROT270 rotation). Optional window
-- PLAY_DENSE_FROM..PLAY_DENSE_TO (s) with a snapshot every frame.
-- Env: PLAY_OUT, PLAY_STOP (s), PLAY_AT (40), PLAY_CONT (10), PLAY_SNAP (30)
-- PLAY_WINDOWS="a:b,c:d" (s): snapshot every frame and record the GPU
-- command stream to gpu_stream.bin (format of tools/mame/oracle.lua
-- ORACLE_GPU_STREAM, readable by tools/gpu_stream.py; frame = this script's
-- frame count) inside these windows only.
-- PLAY_GS_WINDOWS="a:b,...": GPU stream only (no snapshots) in these windows.
-- PLAY_VRAM_FRAMES="F,...": at the start of frame F (in the frame notifier
-- that begins it, before any GPU word of frame F) write vram_<F>.bin (MAME
-- p_vram, 16-bit little-endian pixels, as oracle.lua's VRAM dumps).
local fmt = string.format
local OUT = os.getenv("PLAY_OUT") or "."
local STOP = tonumber(os.getenv("PLAY_STOP") or "240")
local AT = tonumber(os.getenv("PLAY_AT") or "40")
local CONT = tonumber(os.getenv("PLAY_CONT") or "10")
local SNAP = tonumber(os.getenv("PLAY_SNAP") or "30")
local DF = tonumber(os.getenv("PLAY_DENSE_FROM") or "-1")
local DT = tonumber(os.getenv("PLAY_DENSE_TO") or "-1")
local m = manager.machine
local scr = m.screens[":screen"]
local sp = m.devices[":maincpu"].spaces["program"]
local WIN = {}
for a, b in string.gmatch(os.getenv("PLAY_WINDOWS") or "", "([%d%.]+):([%d%.]+)") do WIN[#WIN + 1] = { tonumber(a), tonumber(b) } end
local function inwin(t) for _, w in ipairs(WIN) do if t >= w[1] and t <= w[2] then return true end end return false end
local GSWIN = {}
for a, b in string.gmatch(os.getenv("PLAY_GS_WINDOWS") or "", "([%d%.]+):([%d%.]+)") do GSWIN[#GSWIN + 1] = { tonumber(a), tonumber(b) } end
local function ingswin(t)
  if inwin(t) then return true end
  for _, w in ipairs(GSWIN) do if t >= w[1] and t <= w[2] then return true end end
  return false
end
local VRAMF = {}
for n in string.gmatch(os.getenv("PLAY_VRAM_FRAMES") or "", "%d+") do VRAMF[tonumber(n)] = true end
local gpudev = m.devices[":gpu"]
local function field(name)
  for _, p in pairs(m.ioport.ports) do
    for fname, f in pairs(p.fields) do if fname == name then return f end end
  end
end
local F = {}
for _, n in ipairs({"Coin 1", "1 Player Start", "P1 Button 1", "P1 Left", "P1 Right", "P1 Up", "P1 Down"}) do F[n] = field(n) end
local log = io.open(OUT .. "/play.log", "w")
local frame = 0
PSY = {}
-- windowed GPU stream (records as oracle.lua)
local gs = (#WIN > 0 or #GSWIN > 0) and assert(io.open(OUT .. "/gpu_stream.bin", "wb")) or nil
local gs_buf = {}
local function gs_put(kind, words)
  if not ingswin(m.time:as_double()) then return end
  gs_buf[#gs_buf + 1] = string.pack("<I4BI4", frame, kind, #words)
  for i = 1, #words do gs_buf[#gs_buf + 1] = string.pack("<I4", words[i]) end
  if #gs_buf > 4096 then gs:write(table.concat(gs_buf)); gs_buf = {} end
end
local function ram32(a) return sp:read_u32(a & 0x3ffffc) end
local dma2_madr, dma2_bcr = 0, 0
if gs then
  PSY.t1 = sp:install_write_tap(0x1f801810, 0x1f801817, "psy_gp", function(o, d, mk)
    gs_put((o & 4) == 0 and 0 or 1, { d })
  end)
  PSY.t2 = sp:install_write_tap(0x1f8010a0, 0x1f8010af, "psy_dma2", function(o, d, mk)
    local r = o & 0xc
    if r == 0 then dma2_madr = d & 0xffffff
    elseif r == 4 then dma2_bcr = d
    elseif r == 8 and (d & 0x01000000) ~= 0 and ingswin(m.time:as_double()) then
      local mode, to_gpu = (d >> 9) & 3, (d & 1) == 1
      if to_gpu and mode == 1 then
        local bs, bc = dma2_bcr & 0xffff, (dma2_bcr >> 16) & 0xffff
        if bs == 0 then bs = 0x10000 end
        if bs * bc <= 0x40000 then
          local w, a = {}, dma2_madr
          for i = 1, bs * bc do w[i] = ram32(a); a = a + 4 end
          gs_put(2, w)
        end
      elseif to_gpu and mode == 2 then
        local a, nodes, seen = dma2_madr, 0, {}
        repeat
          if seen[a] then break end
          seen[a] = true
          local h = ram32(a); local n = h >> 24; local w = {}
          for i = 1, n do w[i] = ram32(a + 4 * i) end
          if n > 0 then gs_put(3, w) end
          a = h & 0xffffff; nodes = nodes + 1
        until (a & 0x800000) ~= 0 or nodes > 65536
      else
        gs_put(4, { d })
      end
    end
  end)
end
PSY.f = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  local t = m.time:as_double()
  if VRAMF[frame] then
    local it = emu.item(gpudev.items["0/p_vram"])
    local f = assert(io.open(fmt("%s/vram_%d.bin", OUT, frame), "wb"))
    f:write(it:read_block(0, it.count * it.size)); f:close()
    log:write(fmt("vram %d %.6f\n", frame, t))
  end
  if t >= AT then
    local k = (t - AT) % CONT
    F["Coin 1"]:set_value(k < 0.1 and 1 or 0)
    F["1 Player Start"]:set_value((k >= 2 and k < 2.1) and 1 or 0)
    F["P1 Button 1"]:set_value((t >= AT + 5) and 1 or 0)
    -- slow weave: left, centre, right, centre (2 s each); up/down in a 7 s cycle
    local ph = math.floor((t - AT) / 2) % 4
    F["P1 Left"]:set_value(ph == 1 and 1 or 0)
    F["P1 Right"]:set_value(ph == 3 and 1 or 0)
    local v = math.floor((t - AT) / 3.5) % 2
    F["P1 Up"]:set_value(v == 0 and 1 or 0)
    F["P1 Down"]:set_value(v == 1 and 1 or 0)
  end
  if (SNAP > 0 and frame % SNAP == 0) or (t >= DF and t <= DT) or inwin(t) then
    scr:snapshot(fmt("f%06d.png", frame))
    log:write(fmt("%d %.6f\n", frame, t))
  end
  if t >= STOP then
    log:close()
    if gs then gs:write(table.concat(gs_buf)); gs:close() end
    m:exit()
  end
end)
