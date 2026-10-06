-- ZSG-2 oracle for MAME 0.288 (Taito G-NET), used with tools/zsg2/zsg2_trace.sh.
-- Writes one log (env ZOUT) with three kinds of line:
--   A <t> <R|W> <offset> <data> <mask> <pc> <cnt>
--       every MN10200 access to the ZSG-2 (0x800000-0x8007ff); t is the
--       MN10200's local time, cnt the ZSG-2 m_sample_count when the tap ran
--       (a read tap runs after the handler, a write tap before it)
--   S <k> <cnt> <si0> <si1> <si2> <si3>
--       once per TMS57002 sample: k = floor(t * 32552) of the first external
--       RAM read of that sample, cnt = ZSG-2 m_sample_count, si = the
--       TMS57002 serial inputs (24 bit), which carry the ZSG-2 outputs
--       (tms57002.cpp:928-931; si0/si1 = out * 128, si2/si3 = out * 256)
--   C <cnt> <ch> <status> <cur_pos> <step_ptr> <vol> <cutoff> <vol_delta>
--       <emphasis> <ofilter> <s0> .. <s4>   (every 30 frames, active channels)
-- Inputs: coin at ZSG2_COIN_AT (default 40 s), start, then fire and
-- left/right so the sound driver sees gameplay (coin held 0.1 s only:
-- holding it 1 s resets the board 5 s later).
local out = assert(io.open(os.getenv("ZOUT") or "zsg2.log", "w"))
local coin_at = tonumber(os.getenv("ZSG2_COIN_AT") or "40")
local mach = manager.machine
local cpu = mach.devices[":taito_zoom:mn10200"]
local z = mach.devices[":taito_zoom:zsg2"]
local tms = mach.devices[":taito_zoom:tms57002"]
local cnt_item = emu.item(z.items["0/m_sample_count"])
local si_item = emu.item(tms.items["0/si"])
local function t() return mach.time:as_double() end
local function cnt() return cnt_item:read(0) end
local RATE = 32552

ZSG2_TAPS = {}
local sp = cpu.spaces["program"]
table.insert(ZSG2_TAPS, sp:install_read_tap(0x800000, 0x8007ff, "zsg2r", function(o, d, m)
  out:write(string.format("A %.9f R %06x %04x %04x %06x %d\n", t(), o, d, m, cpu.state["PC"].value, cnt()))
end))
table.insert(ZSG2_TAPS, sp:install_write_tap(0x800000, 0x8007ff, "zsg2w", function(o, d, m)
  out:write(string.format("A %.9f W %06x %04x %04x %06x %d\n", t(), o, d, m, cpu.state["PC"].value, cnt()))
end))

local lastk = -1
local ds = tms.spaces["data"]
table.insert(ZSG2_TAPS, ds:install_read_tap(0x00000, 0x3ffff, "tmsr", function(o, d, m)
  local k = math.floor(t() * RATE)
  if k ~= lastk then
    lastk = k
    out:write(string.format("S %d %d %d %d %d %d\n", k, cnt(),
      si_item:read(0), si_item:read(1), si_item:read(2), si_item:read(3)))
  end
end))

-- per-channel state snapshots
local fields = { "status", "cur_pos", "step_ptr", "vol", "output_cutoff", "vol_delta",
                 "emphasis_filter_state", "output_filter_state" }
local items = {}
for ch = 0, 47 do
  items[ch] = {}
  for i, f in ipairs(fields) do
    items[ch][i] = emu.item(z.items[string.format("%X/m_chan[ch].%s", ch, f)])
  end
  items[ch].samples = emu.item(z.items[string.format("%X/m_chan[ch].samples", ch)])
end
local function snap()
  local c = cnt()
  for ch = 0, 47 do
    local it = items[ch]
    if it[1]:read(0) & 0x8000 ~= 0 then
      local v = {}
      for i = 1, #fields do v[i] = it[i]:read(0) end
      local s = it.samples
      out:write(string.format("C %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n", c, ch,
        v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8],
        s:read(0), s:read(1), s:read(2), s:read(3), s:read(4)))
    end
  end
end

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
ZSG2_FRAME = emu.add_machine_frame_notifier(function()
  local now = t()
  frame = frame + 1
  if frame % 30 == 0 then snap() end
  while plan[step] and now >= plan[step][1] do
    local f = field(plan[step][2])
    if f then f:set_value(plan[step][3]) end
    out:write(string.format("I %.6f %s %d\n", now, plan[step][2], plan[step][3]))
    step = step + 1
  end
  if now > coin_at + 5 then
    local l, r = field("P1 Left"), field("P1 Right")
    local ph = math.floor(now * 2) % 2
    if l then l:set_value(ph) end
    if r then r:set_value(1 - ph) end
  end
end)
ZSG2_STOP = emu.add_machine_stop_notifier(function()
  out:write(string.format("E %.9f\n", t())); out:close()
end)
