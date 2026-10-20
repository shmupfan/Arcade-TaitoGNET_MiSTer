-- sianniv (issue #1) MDEC probe for MAME 0.288, warm boot from a post-copy nvram:
--   DBGOUT=<dir> [NOMDEC=1] mame sianniv ... -autoboot_script tools/mame/sianniv_mdec_probe.lua
-- Coin 1 at 32.0 s (0.1 s), Start at 35.0 s (0.8 s). Logs MDEC0/1, DMA0/1, DICR and
-- I_MASK writes, 0x802FF968 writes and frames whose PC is in the movie player
-- (0x80012f00-0x80013400) to <dir>/probe.log (appended: MAME re-runs the
-- script after a watchdog reset), snapshots every 60 frames from 30 s.
-- Result 2026-10-14: normal run: MDEC reset/in/out right after the coin (menu
-- background still) and at Start (zoom movie), game starts. NOMDEC=1 (start bit
-- of DMA0/DMA1 CHCR cleared, as the core's HAS_MDEC = 0): screen freezes on the
-- title after the coin, CPU spins at 0x80013300-0x80013334 waiting for gp+0x278
-- (set only by the DecDCTout DMA1 callback 0x80012f28), watchdog reset at 37.24 s.
local OUT = os.getenv("DBGOUT") or "."
local NOMDEC = os.getenv("NOMDEC") == "1"
local log = io.open(OUT .. "/probe.log", "a")
local cpu = manager.machine.devices[":maincpu"]
local sp = cpu.spaces["program"]
local function t() return manager.machine.time:as_double() end
local function L(s) log:write(string.format("%10.4f %s\n", t(), s)); log:flush() end
L("NOMDEC=" .. tostring(NOMDEC))

local plan = { {32.0, ":SYSTEM", "Coin 1", 1}, {32.1, ":SYSTEM", "Coin 1", 0},
               {35.0, ":SYSTEM", "1 Player Start", 1}, {35.8, ":SYSTEM", "1 Player Start", 0} }
local fields = {}
for _, port in pairs(manager.machine.ioport.ports) do
  for name, f in pairs(port.fields) do fields[name] = f end
end

local counts = {}
local function cnt(k) counts[k] = (counts[k] or 0) + 1; return counts[k] end
TAPS = {}
local function wtap(a, b, name, fn) TAPS[#TAPS + 1] = sp:install_write_tap(a, b, name, fn) end
local function rtap(a, b, name, fn) TAPS[#TAPS + 1] = sp:install_read_tap(a, b, name, fn) end

wtap(0x1f801820, 0x1f801827, "mdec_w", function(off, data, mask)
  local n = cnt("mdec_w " .. string.format("%x", off))
  if n <= 3 then L(string.format("MDEC W %08x = %08x pc %08x", off, data, cpu.state["pc"].value)) end
end)
rtap(0x1f801820, 0x1f801827, "mdec_r", function(off, data, mask)
  local n = cnt("mdec_r " .. string.format("%x", off))
  if n <= 3 then L(string.format("MDEC R %08x -> %08x pc %08x", off, data, cpu.state["pc"].value)) end
end)
wtap(0x1f801080, 0x1f80109f, "dma01", function(off, data, mask)
  local n = cnt(string.format("dma %x", off))
  local nd = data
  if NOMDEC and (off == 0x1f801088 or off == 0x1f801098) then nd = data & ~0x01000000 end
  if n <= 4 then L(string.format("DMA W %08x = %08x pc %08x%s", off, data, cpu.state["pc"].value, nd ~= data and " (start blocked)" or "")) end
  if nd ~= data then return nd end
end)
wtap(0x1f8010f0, 0x1f8010f7, "dpcr_dicr", function(off, data, mask)
  if off == 0x1f8010f4 and cnt("dicr") <= 6 then L(string.format("DICR W %08x pc %08x", data, cpu.state["pc"].value)) end
end)
wtap(0x1f801074, 0x1f801077, "imask", function(off, data, mask)
  local n = cnt("imask")
  if n <= 40 then L(string.format("I_MASK W %04x pc %08x", data & 0xffff, cpu.state["pc"].value)) end
end)
wtap(0x802ff968, 0x802ff96b, "si968", function(off, data, mask)
  local n = cnt("w968")
  if n <= 6 or n % 500 == 0 then L(string.format("W 802ff968 = %08x pc %08x (n %d)", data, cpu.state["pc"].value, n)) end
end)
-- code hits
for _, a in ipairs({0x80013310, 0x8001323c, 0x80013014, 0x8001308c, 0x80010008, 0x8001102c, 0x8003e198}) do
  rtap(a, a + 3, string.format("pc%x", a), function(off, data, mask)
    if cpu.state["pc"].value == a then
      local n = cnt(string.format("pc %08x", a))
      if n <= 3 or (n % 2000 == 0) then local ok, gp = pcall(function() return cpu.state["r28"].value end); L(string.format("PC %08x hit %d gp=%s", a, n, ok and string.format("%08x", gp) or "?")) end
    end
  end)
end

local done = {}
local last_sec = -1
FRAMESUB = emu.register_frame_done(function()
  local pc = cpu.state["pc"].value
  if pc >= 0x80012f00 and pc < 0x80013400 then local n = cnt("loopframes"); if n <= 3 or n % 10 == 0 then L(string.format("frame in 80012f00-80013400 pc %08x (n %d)", pc, n)) end end
  local fr = manager.machine.screens[":screen"]:frame_number()
  if fr % 60 == 0 and t() > 30 then manager.machine.screens[":screen"]:snapshot(string.format("f%05d.png", fr)) end
  for i, p in ipairs(plan) do
    if not done[i] and t() >= p[1] then
      done[i] = true
      local f = fields[p[3]]
      if f then f:set_value(p[4]); L("INPUT " .. p[3] .. " = " .. p[4]) else L("NO FIELD " .. p[3]) end
    end
  end
  local s = math.floor(t())
  if s ~= last_sec then
    last_sec = s
    if s >= 30 then
      L(string.format("sec PC %08x I_MASK %04x I_STAT %04x 968=%08x", cpu.state["pc"].value,
        sp:read_u32(0x1f801074) & 0xffff, sp:read_u32(0x1f801070) & 0xffff, sp:read_u32(0x802ff968)))
    end
  end
end)

STOPSUB = emu.add_machine_stop_notifier(function()
  local keys = {}
  for k in pairs(counts) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do L(string.format("COUNT %s %d", k, counts[k])) end
  local f = io.open(OUT .. "/ram_end.bin", "wb")
  local parts = {}
  for a = 0x80000000, 0x803ffffc, 4 do
    local w = sp:read_u32(a)
    parts[#parts + 1] = string.pack("<I4", w)
    if #parts == 4096 then f:write(table.concat(parts)); parts = {} end
  end
  f:write(table.concat(parts)); f:close()
  log:close()
end)
