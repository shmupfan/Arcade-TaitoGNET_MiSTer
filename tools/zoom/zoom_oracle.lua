-- Taito Zoom board oracle for MAME 0.288 (or the 61c7940 build), used with
-- tools/zoom/zoom_oracle.sh to verify rtl/zoom/zoom_board.sv
-- (docs/zoom_board_design.md 10).
--
-- One stream, ZOOM_TRACE (file or FIFO; game-derived, keep it under
-- gitignored sim/), written through the debugger's trace of
-- :taito_zoom:mn10200, so every line is in MAME's execution order:
--   T pc d0 d1 d2 d3 a0 a1 a2 a3 psw mdr totalcycles fc57 fc50 fc42
--       before each MN10200 instruction (as tools/mn102/mn102_oracle.lua),
--       followed by MAME's disassembly line
--   B R|W addr data mask [sec asec cnt | L pc cnt]
--       an MN10200 access to the ZSG-2 (with its local time in seconds and
--       attoseconds and the ZSG-2 m_sample_count), the TMS57002 data port
--       (writes with the DSP's PC and the sample count where the byte lands)
--       or the mailbox
--   H R|W addr data mask sec asec
--       a main-CPU access to the Zoom ports 0x1FB80000-0x1FBE01FF
--   C data sec asec
--       a main-CPU write to the control register 0x1FB40000 (bit 4 = Zoom
--       reset)
--   S k cnt si0 si1 si2 si3 so2 so3
--       once per TMS57002 sample: k = floor(t x 32552) of its first external
--       RAM read, cnt = ZSG-2 m_sample_count, si = the TMS57002 serial
--       inputs (the four ZSG-2 outputs scaled by the route gains,
--       docs/zsg2_rtl.md 4.1), so2/so3 = the SO1 pair (24 bits) as it
--       stands then (taito_zm.cpp:201-202 routes outputs 2 and 3)
-- A main-CPU line sits where the MN10200 first runs after the access, which
-- is the instruction from which MAME's MN10200 sees it.
local mach = manager.machine
local cpu = mach.devices[":taito_zoom:mn10200"]
local maincpu = mach.devices[":maincpu"]
local z = mach.devices[":taito_zoom:zsg2"]
local tms = mach.devices[":taito_zoom:tms57002"]
local sp = cpu.spaces["program"]
local msp = maincpu.spaces["program"]
local dbg = mach.debugger
local cnt_item = emu.item(z.items["0/m_sample_count"])
local si_item = emu.item(tms.items["0/si"])
local so_item = emu.item(tms.items["0/so"])
local function cnt() return cnt_item:read(0) end
local function tl(s) dbg:command('tracelog "' .. s .. '\\n"') end
local function now()
  local t = mach.time
  return t.seconds, t.attoseconds
end

ZOOM_TAPS = {}
local function tap(space, lo, hi, name, rd, wr)
  if rd then table.insert(ZOOM_TAPS, space:install_read_tap(lo, hi, name .. "r", rd)) end
  if wr then table.insert(ZOOM_TAPS, space:install_write_tap(lo, hi, name .. "w", wr)) end
end
-- MN10200 side
tap(sp, 0x800000, 0x8007ff, "zsg2",
  function(o, d, m) local s, a = now(); tl(string.format("B R %06x %04x %04x %d %d %d", o, d, m, s, a, cnt())) end,
  function(o, d, m) local s, a = now(); tl(string.format("B W %06x %04x %04x %d %d %d", o, d, m, s, a, cnt())) end)
-- TMS57002 data port: also where the byte lands in MAME, the DSP's PC and
-- the sample count of the stream it syncs to (the ZSG-2 m_sample_count)
local tpc = tms.state["PC"]
tap(sp, 0xc00000, 0xc00001, "tms",
  function(o, d, m) tl(string.format("B R %06x %04x %04x", o, d, m)) end,
  function(o, d, m) tl(string.format("B W %06x %04x %04x L %d %d", o, d, m, tpc.value, cnt())) end)
for _, r in ipairs({ { 0xe00000, 0xe000ff, "mbox" } }) do
  tap(sp, r[1], r[2], r[3],
    function(o, d, m) tl(string.format("B R %06x %04x %04x", o, d, m)) end,
    function(o, d, m) tl(string.format("B W %06x %04x %04x", o, d, m)) end)
end
-- main-CPU side
tap(msp, 0x1fb80000, 0x1fbe01ff, "host",
  function(o, d, m) local s, a = now(); tl(string.format("H R %08x %08x %08x %d %d", o, d, m, s, a)) end,
  function(o, d, m) local s, a = now(); tl(string.format("H W %08x %08x %08x %d %d", o, d, m, s, a)) end)
tap(msp, 0x1fb40000, 0x1fb40003, "ctrl", nil,
  function(o, d, m) if m & 0xff ~= 0 then local s, a = now(); tl(string.format("C %02x %d %d", d & 0xff, s, a)) end end)
-- per-sample ZSG-2 outputs as the TMS57002 sees them
local lastk = -1
tap(tms.spaces["data"], 0x00000, 0x3ffff, "tmsd",
  function(o, d, m)
    local k = math.floor(mach.time:as_double() * 32552)
    if k ~= lastk then
      lastk = k
      tl(string.format("S %d %d %d %d %d %d %d %d", k, cnt(), si_item:read(0), si_item:read(1), si_item:read(2), si_item:read(3),
        so_item:read(2), so_item:read(3)))
    end
  end, nil)

local tf = assert(os.getenv("ZOOM_TRACE"))
-- tracelog writes to the visible CPU's trace file: keep it on the MN10200
-- (landmine noted in tools/mn102/mn102_oracle.lua)
dbg:command("focus :taito_zoom:mn10200")
dbg.visible_cpu = cpu
dbg:command("trace " .. tf .. ",:taito_zoom:mn10200,noloop,"
  .. "{tracelog \"T %06X %06X %06X %06X %06X %06X %06X %06X %06X %04X %04X %X %02X %02X %02X\\n\","
  .. "pc,d0,d1,d2,d3,a0,a1,a2,a3,curflags,mdr,totalcycles,b@fc57,b@fc50,b@fc42}")
ZOOM_STOP = emu.add_machine_stop_notifier(function()
  dbg:command("trace off,:taito_zoom:mn10200")
end)

-- Optional gameplay input: ZOOM_COIN_AT (s) coin, start 2 s later, fire
-- from 5 s later, left/right alternating every 0.5 s (as mn102_oracle.lua)
local coin_at = tonumber(os.getenv("ZOOM_COIN_AT") or "")
if coin_at then
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
  local step = 1
  ZOOM_FRAME = emu.add_machine_frame_notifier(function()
    local t = mach.time:as_double()
    while plan[step] and t >= plan[step][1] do
      local f = field(plan[step][2])
      if f then f:set_value(plan[step][3]) end
      step = step + 1
    end
    if t > coin_at + 5 then
      local l, r = field("P1 Left"), field("P1 Right")
      local ph = math.floor(t * 2) % 2
      if l then l:set_value(ph) end
      if r then r:set_value(1 - ph) end
    end
  end)
end
