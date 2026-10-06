-- R18: which PSX blocks the G-NET games use (MAME 0.288).
-- Counts main-CPU accesses to MDEC (0x1f801820-27), MDEC DMA channels 0/1
-- (CHCR at 0x1f801088 / 0x1f801098), SPU key-on (0x1f801d88-8b) and the
-- SPU control register (0x1f801daa). Inserts a coin, starts a game and holds
-- fire/move inputs so gameplay is covered as well as attract mode.
-- Env: R18_OUT (output file), R18_COIN_AT (emulated seconds, default 240).
local out_path = os.getenv("R18_OUT") or "r18.txt"
local coin_at = tonumber(os.getenv("R18_COIN_AT") or "240")
local sp = manager.machine.devices[":maincpu"].spaces["program"]
local c = { mdec_w = 0, mdec_r = 0, dma0 = 0, dma1 = 0, kon = 0, spucnt = 0, gpu_w = 0 }
local first = {}
-- machine.time.seconds is the integer part only; as_double gives fractions
local function t() return manager.machine.time:as_double() end
local function hit(k) c[k] = c[k] + 1; if not first[k] then first[k] = t() end end
R18_TAPS = {
  -- sanity: GPU GP0/GP1 writes must be non-zero once the BIOS draws
  sp:install_write_tap(0x1f801810, 0x1f801817, "gpu_w", function(o, d, m) hit("gpu_w") end),
  sp:install_write_tap(0x1f801820, 0x1f801827, "mdec_w", function(o, d, m) hit("mdec_w") end),
  sp:install_read_tap(0x1f801820, 0x1f801827, "mdec_r", function(o, d, m) hit("mdec_r") end),
  sp:install_write_tap(0x1f801088, 0x1f80108b, "dma0", function(o, d, m) if d & 0x01000000 ~= 0 then hit("dma0") end end),
  sp:install_write_tap(0x1f801098, 0x1f80109b, "dma1", function(o, d, m) if d & 0x01000000 ~= 0 then hit("dma1") end end),
  sp:install_write_tap(0x1f801d88, 0x1f801d8b, "kon", function(o, d, m) if d ~= 0 then hit("kon") end end),
  sp:install_write_tap(0x1f801da8, 0x1f801dab, "spucnt", function(o, d, m) hit("spucnt") end),
}
-- input helpers: find fields by name in any port
local function field(name)
  for _, p in pairs(manager.machine.ioport.ports) do
    for fname, f in pairs(p.fields) do if fname == name then return f end end
  end
end
local plan = {
  { coin_at,       "Coin 1", 1 }, { coin_at + 0.1, "Coin 1", 0 },
  { coin_at + 2,   "1 Player Start", 1 }, { coin_at + 2.1, "1 Player Start", 0 },
  { coin_at + 5,   "P1 Button 1", 1 },
}
local step = 1
local wiggle = 0
-- subscriptions must stay referenced or they are collected and stop firing
R18_SUBS = {}
R18_SUBS.frame = emu.add_machine_frame_notifier(function()
  local now = t()
  while plan[step] and now >= plan[step][1] do
    local f = field(plan[step][2])
    if f then f:set_value(plan[step][3]) end
    step = step + 1
  end
  if now >= (R18_NEXT_SNAP or coin_at + 10) then
    manager.machine.video:snapshot()
    R18_NEXT_SNAP = (R18_NEXT_SNAP or coin_at + 10) + 120
  end
  -- gentle left/right movement during play so the game does not stall
  if now > coin_at + 5 then
    wiggle = wiggle + 1
    local l, r = field("P1 Left"), field("P1 Right")
    if l and r then
      local phase = math.floor(wiggle / 60) % 4
      l:set_value(phase == 1 and 1 or 0); r:set_value(phase == 3 and 1 or 0)
    end
  end
end)
R18_RESETS = 0
R18_SUBS.reset = emu.add_machine_reset_notifier(function()
  R18_RESETS = R18_RESETS + 1
  local f = io.open(out_path, "a")
  f:write(string.format("reset at machine_seconds %.2f\n", t()))
  f:close()
end)
R18_SUBS.stop = emu.add_machine_stop_notifier(function()
  -- optional: dump main RAM (4 MB) for the static MDEC scan (tools/mame/r18_scan.py)
  local dump = os.getenv("R18_RAMDUMP")
  if dump then
    local d = io.open(dump, "wb")
    d:write(sp:read_range(0x80000000, 0x803fffff, 8))
    d:close()
  end
  -- append: a hard reset starts a new machine and re-runs this script
  local f = io.open(out_path, "a")
  f:write(string.format("instance_end system %s machine_seconds %.1f coin_at %.1f soft_resets %d\n", emu.romname(), t(), coin_at, R18_RESETS))
  for _, k in ipairs({ "gpu_w", "mdec_w", "mdec_r", "dma0", "dma1", "kon", "spucnt" }) do
    f:write(string.format("  %s %d first %s\n", k, c[k], first[k] and string.format("%.2f", first[k]) or "-"))
  end
  f:close()
end)
