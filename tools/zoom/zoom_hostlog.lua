-- Light Taito Zoom log for MAME 0.288 (or the 61c7940 build), for the
-- integration replay of sim/zoomlink (docs/zoom_board_design.md 14). Unlike
-- tools/zoom/zoom_oracle.lua it needs no debugger and logs no MN10200
-- instruction, so MAME runs at close to its normal speed. One line per
-- access, in MAME's order, to the file ZOOM_HOSTLOG (game-derived: keep it
-- under a gitignored directory):
--   H R|W addr data mask sec asec    main-CPU access to 0x1FB80000-0x1FBE01FF
--                                    (as zoom_oracle.lua)
--   C data sec asec                  main-CPU write to the control register
--   M R|W addr data mask sec asec    MN10200 access to the mailbox
--                                    0xE00000-0xE000FF
--   S k so2 so3                      with ZOOM_HOSTLOG_SO=1: once per
--                                    TMS57002 sample (k = floor(t x 32552)
--                                    at its first external RAM read), the
--                                    SO1 pair (24 bits) as it stands then,
--                                    as zoom_oracle.lua's S lines
-- ZOOM_COIN_AT=<s>: coin, start 2 s later, fire from 5 s later, left/right
-- alternating every 0.5 s (as zoom_oracle.lua).
local mach = manager.machine
local cpu = mach.devices[":taito_zoom:mn10200"]
local maincpu = mach.devices[":maincpu"]
local sp = cpu.spaces["program"]
local msp = maincpu.spaces["program"]
local out = assert(io.open(assert(os.getenv("ZOOM_HOSTLOG")), "w"))
local function now()
  local t = mach.time
  return t.seconds, t.attoseconds
end

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
if os.getenv("ZOOM_HOSTLOG_SO") then
  local tms = mach.devices[":taito_zoom:tms57002"]
  local so_item = emu.item(tms.items["0/so"])
  local lastk = -1
  tap(tms.spaces["data"], 0x00000, 0x3ffff, "tmsd",
    function(o, d, m)
      local k = math.floor(mach.time:as_double() * 32552)
      if k ~= lastk then
        lastk = k
        out:write(string.format("S %d %d %d\n", k, so_item:read(2), so_item:read(3)))
      end
    end, nil)
end

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

ZOOM_STOP = emu.add_machine_stop_notifier(function() out:close() end)
