-- Super Puzzle Bobble high score probe (MAME 0.288, docs/hiscore.md 1).
-- Watches the hiscore.dat block of spuzbobl (main RAM 0x28BF08, 0x10D bytes)
-- and logs it to $HS_OUT/hs.log each time it changes (sampled every
-- HS_DUMP_EVERY frames, default 30). Optional:
--   HS_PLAN="t:field:v,..."   input plan (emulated seconds, field name, value)
--   HS_POKE_AT=<s>, HS_POKE="off=hex,..."   write bytes into the block once
--   HS_PLAY_AT=<s>, HS_PLAY_END=<s>   play: button 1 every 40 frames, random
--                             left/right, 1P Start every 300 frames
--   HS_SNAP=<frames>          snapshot every N frames
--   HS_SOFTRESET_AT=<s>       one soft reset (MAME restarts the script; the
--                             globals below keep it from running twice)
-- The EEPROM (at28c16) and the card (CHD diff) are compared outside, with
-- tools/mame/hiscore_run.sh.
if HS_LOADED then return end
HS_LOADED = true
local m = manager.machine
local sp = m.devices[":maincpu"].spaces["program"]
local OUT = os.getenv("HS_OUT") or "."
local log = assert(io.open(OUT .. "/hs.log", "a"))
local function L(s) log:write(string.format("%10.4f %s\n", m.time:as_double(), s)); log:flush() end
local TB, TL = 0x28bf08, 0x10d
L("script_start")
local function table_hex()
  local t = {}
  for i = 0, TL - 1 do t[#t + 1] = string.format("%02x", sp:read_u8(TB + i)) end
  return table.concat(t)
end
local function field(name)
  for _, p in pairs(m.ioport.ports) do
    for fname, f in pairs(p.fields) do if fname == name then return f end end
  end
end
local plan = {}
for t, f, v in string.gmatch(os.getenv("HS_PLAN") or "", "([%d%.]+):([^:,]+):(%d)") do
  plan[#plan + 1] = { tonumber(t), f, tonumber(v) }
end
table.sort(plan, function(a, b) return a[1] < b[1] end)
local step = 1
local EVERY = tonumber(os.getenv("HS_DUMP_EVERY") or "30")
local POKE_AT = tonumber(os.getenv("HS_POKE_AT") or "")
local POKE = os.getenv("HS_POKE") or ""
local PLAY_AT = tonumber(os.getenv("HS_PLAY_AT") or "")
local PLAY_END = tonumber(os.getenv("HS_PLAY_END") or "1e9")
local SNAP = tonumber(os.getenv("HS_SNAP") or "0")
local SR_AT = tonumber(os.getenv("HS_SOFTRESET_AT") or "")
local poked, last, frame = false, "", 0
local rnd = 12345
local function rand() rnd = (rnd * 1103515245 + 12345) % 2147483648; return rnd end
HS_NOTIF = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  local t = m.time:as_double()
  while plan[step] and t >= plan[step][1] do
    local f = field(plan[step][2])
    if f then f:set_value(plan[step][3]) end
    L(string.format("input %s=%d%s", plan[step][2], plan[step][3], f and "" or " (not found)"))
    step = step + 1
  end
  if POKE_AT and not poked and t >= POKE_AT then
    for o, v in string.gmatch(POKE, "(%x+)=(%x+)") do sp:write_u8(TB + tonumber(o, 16), tonumber(v, 16)) end
    poked = true
    L("poke " .. POKE)
  end
  if PLAY_AT and t >= PLAY_AT and t < PLAY_END then
    local b, l, r, st = field("P1 Button 1"), field("P1 Left"), field("P1 Right"), field("1 Player Start")
    local ph = frame % 40
    if b then b:set_value((ph < 4) and 1 or 0) end
    if ph == 10 then
      local d = rand() % 3
      if l then l:set_value(d == 0 and 1 or 0) end
      if r then r:set_value(d == 1 and 1 or 0) end
    elseif ph == 10 + (rand() % 25) then
      if l then l:set_value(0) end
      if r then r:set_value(0) end
    end
    if st then st:set_value((frame % 300) < 4 and 1 or 0) end
  end
  if SR_AT and not HS_SR_DONE and t >= SR_AT then HS_SR_DONE = true; L("soft_reset"); m:soft_reset() end
  if SNAP > 0 and frame % SNAP == 0 then m.video:snapshot() end
  if frame % EVERY == 0 then
    local h = table_hex()
    if h ~= last then L("TABLE " .. h); last = h end
  end
end)
