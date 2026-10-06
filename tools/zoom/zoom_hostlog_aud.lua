-- Taito Zoom host log with an input plan and the Zoom's own audio, for the
-- comparison of docs/zoom_board_design.md 14.12 (MAME, the 61c7940 build):
-- tools/zoom/zoom_hostlog.lua's H, C and M lines (the sim/zoomlink replay
-- input) plus
--   K sec asec active writes   every 30 frames: ZSG-2 channels with status
--                              bit 15 set, MN10200 writes to the ZSG-2 since
--                              the last mark
--   I sec asec name value      an input change (coin, start, fire, left/right
--                              as tools/zsg2/zsg2_trace.lua)
-- and, for AUD_T0 <= t < AUD_T1, the Zoom output before the SPU mix
-- (ZOOM_AUD, int16 L, R per TMS57002 sample) and the TMS57002 serial inputs
-- and SO1 words (ZOOM_AUD.si, six u32: si0..si3, so[2], so[3]).
-- Env: ZOOM_HOSTLOG, ZOOM_AUD, AUD_T0, AUD_T1, PLAY_COIN_AT (s, default 40).
-- Run as tools/zoom/zoom_hostlog.sh does (-autoboot_script this file, the
-- warm NVRAM set, nice -n 15). Output is game-derived: gitignored dirs only.
local mach = manager.machine
local cpu = mach.devices[":taito_zoom:mn10200"]
local maincpu = mach.devices[":maincpu"]
local z = mach.devices[":taito_zoom:zsg2"]
local sp = cpu.spaces["program"]
local msp = maincpu.spaces["program"]
local out = assert(io.open(assert(os.getenv("ZOOM_HOSTLOG")), "w"))
local coin_at = tonumber(os.getenv("PLAY_COIN_AT") or "40")
local function now() local t = mach.time; return t.seconds, t.attoseconds end
ZOOM_TAPS = {}
local function tap(space, lo, hi, name, rd, wr)
  if rd then table.insert(ZOOM_TAPS, space:install_read_tap(lo, hi, name .. "r", rd)) end
  if wr then table.insert(ZOOM_TAPS, space:install_write_tap(lo, hi, name .. "w", wr)) end
end
tap(msp, 0x1fb80000, 0x1fbe01ff, "host",
  function(o, d, m) local s, a = now(); out:write(string.format("H R %08x %08x %08x %d %d\n", o, d, m, s, a)) end,
  function(o, d, m) local s, a = now(); out:write(string.format("H W %08x %08x %08x %d %d\n", o, d, m, s, a)) end)
tap(msp, 0x1fb40000, 0x1fb40003, "ctrl", nil,
  function(o, d, m) if m & 0xff ~= 0 then local s, a = now(); out:write(string.format("C %02x %d %d\n", d & 0xff, s, a)) end end)
tap(sp, 0xe00000, 0xe000ff, "mbox",
  function(o, d, m) local s, a = now(); out:write(string.format("M R %06x %04x %04x %d %d\n", o, d, m, s, a)) end,
  function(o, d, m) local s, a = now(); out:write(string.format("M W %06x %04x %04x %d %d\n", o, d, m, s, a)) end)
local zw = 0
tap(sp, 0x800000, 0x8007ff, "zsg2", nil, function(o, d, m) zw = zw + 1 end)
local st = {}
for ch = 0, 47 do st[ch] = emu.item(z.items[string.format("%X/m_chan[ch].status", ch)]) end
local function field(name)
  for _, p in pairs(mach.ioport.ports) do
    for fname, f in pairs(p.fields) do if fname == name then return f end end
  end
end
local plan = {
  { coin_at, "Coin 1", 1 }, { coin_at + 0.1, "Coin 1", 0 },
  { coin_at + 2, "1 Player Start", 1 }, { coin_at + 2.1, "1 Player Start", 0 },
  { coin_at + 5, "P1 Button 1", 1 },
}
local step, frame = 1, 0
ZOOM_FRAME = emu.add_machine_frame_notifier(function()
  local tnow = mach.time:as_double()
  frame = frame + 1
  if frame % 30 == 0 then
    local n = 0
    for ch = 0, 47 do if st[ch]:read(0) & 0x8000 ~= 0 then n = n + 1 end end
    local s, a = now()
    out:write(string.format("K %d %d %d %d\n", s, a, n, zw)); zw = 0
  end
  while plan[step] and tnow >= plan[step][1] do
    local f = field(plan[step][2])
    if f then f:set_value(plan[step][3]) end
    local s, a = now()
    out:write(string.format("I %d %d %s %d\n", s, a, plan[step][2], plan[step][3]))
    step = step + 1
  end
  if tnow > coin_at + 5 then
    local l, r = field("P1 Left"), field("P1 Right")
    local ph = math.floor(tnow * 2) % 2
    if l then l:set_value(ph) end
    if r then r:set_value(1 - ph) end
  end
end)
-- Zoom output before the SPU mix: TMS57002 so[2], so[3] (the stream
-- channels taito_zoom routes to its outputs 0 and 1, before set_output_gain),
-- 16 bits (so >> 8, as tms57002.cpp puts them), once per TMS57002 sample
-- (first external RAM read of the sample, as tools/zsg2/zsg2_trace.lua),
-- for AUD_T0 <= t < AUD_T1, little-endian int16 L, R to ZOOM_AUD
local tms = mach.devices[":taito_zoom:tms57002"]
local so_item = emu.item(tms.items["0/so"])
local si_item = emu.item(tms.items["0/si"])
local zsi = assert(io.open(os.getenv("ZOOM_AUD") .. ".si", "wb"))
local aud = assert(io.open(assert(os.getenv("ZOOM_AUD")), "wb"))
local a0, a1 = tonumber(os.getenv("AUD_T0") or "0"), tonumber(os.getenv("AUD_T1") or "1e9")
local lastk = -1
local ds = tms.spaces["data"]
table.insert(ZOOM_TAPS, ds:install_read_tap(0x00000, 0x3ffff, "tmsr", function(o, d, m)
  local tt = mach.time:as_double()
  local k = math.floor(tt * 32552)
  if k ~= lastk then
    lastk = k
    if tt >= a0 and tt < a1 then
      local l = (so_item:read(2) >> 8) & 0xffff
      local r = (so_item:read(3) >> 8) & 0xffff
      aud:write(string.pack("<I2I2", l, r))
      zsi:write(string.pack("<I4I4I4I4I4I4", si_item:read(0), si_item:read(1), si_item:read(2), si_item:read(3), so_item:read(2), so_item:read(3)))
    end
  end
end))
ZOOM_STOP = emu.add_machine_stop_notifier(function() out:close(); aud:close(); zsi:close() end)
