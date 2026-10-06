-- ZN-2 board-layer access trace (MAME 0.288), for docs/zn2_layer_design.md.
-- Logs every main-CPU access to the ZN-2 registers that the M0 oracle
-- (oracle.lua) does not cover: PS1 memory control (exp1/exp2/BIOS delay and
-- size, com_delay, ram_config), IRQ mask, DMA control, CD and SIO1 ports,
-- expansion 2, ZN inputs, board config, CAT702/znmcu select, coin, the
-- 0x1fa40000/0x1fa51c00/0x1fa60000/0x1fb20000 probes, the AT28C16 EEPROM,
-- BIU/cache control, and any main RAM access above 2 MB (to see whether
-- software uses the 4 MB and its mirror).
--
-- Usage (via tools/mame/zn2_map_trace_run.sh):
--   ZN2MAP_OUT=<dir> mame <set> ... -autoboot_script tools/mame/zn2_map_trace.lua
-- Output: <dir>/zn2map.log, one line per access or per run of identical
-- consecutive accesses to one range: "t name R|W addr data mask [xN tlast]";
-- <dir>/zn2map_summary.txt, counts per range and distinct written values.
-- Logs are game-derived: keep them under sim/ (gitignored).

local m = manager.machine
local OUT = os.getenv("ZN2MAP_OUT") or "zn2map_out"
os.execute("mkdir -p '" .. OUT .. "'")
local sp = m.devices[":maincpu"].spaces["program"]
local fmt = string.format
local function now() return m.time:as_double() end

ZN2MAP = { taps = {} }
local f = assert(io.open(OUT .. "/zn2map.log", "w"))
local buf, nbuf = {}, 0
local function push(s)
  nbuf = nbuf + 1; buf[nbuf] = s
  if nbuf >= 512 then f:write(table.concat(buf, "\n", 1, nbuf), "\n"); nbuf = 0 end
end

local prev = {}   -- name -> {t, d, a, v, mk, n, tl}
local stats = {}  -- name -> {r = n, w = n, wv = {[val] = n}}
local function flushprev(name)
  local p = prev[name]
  if not p then return end
  local s = fmt("%.9f %s %s %08x %08x %08x", p.t, name, p.d, p.a, p.v, p.mk)
  if p.n > 1 then s = s .. fmt(" x%d %.9f", p.n, p.tl) end
  push(s)
  prev[name] = nil
end
local QUIET = { memctrl = true, irq = true, dpcr = true, x1fa51c00 = true, x1fa60000 = true }
local function rec(name, d, a, v, mk)
  local st = stats[name]
  if not st then st = { r = 0, w = 0, wv = {}, first = now() }; stats[name] = st end
  if d == "R" then st.r = st.r + 1 else
    st.w = st.w + 1
    local k = fmt("%08x/%08x/%08x", a, v, mk)
    st.wv[k] = (st.wv[k] or 0) + 1
  end
  st.last = now()
  if QUIET[name] then return end
  local p = prev[name]
  local t = now()
  if p and p.d == d and p.a == a and p.v == v and p.mk == mk then
    p.n = p.n + 1; p.tl = t
    return
  end
  flushprev(name)
  prev[name] = { t = t, d = d, a = a, v = v, mk = mk, n = 1, tl = t }
end

-- count-only ranges (main RAM): count, first/last time, lowest/highest address
local cnt = {}
local function count(name, d, a)
  local c = cnt[name]
  if not c then c = { r = 0, w = 0, first = now(), lo = a, hi = a }; cnt[name] = c end
  if d == "R" then c.r = c.r + 1 else c.w = c.w + 1 end
  c.last = now()
  if a < c.lo then c.lo = a end
  if a > c.hi then c.hi = a end
end
-- psx.cpp update_ram_config/update_rom_config reinstall RAM and ROM handlers
-- when 0x1f801060/0x1f801010 are written (once each, in the first 0.1 ms of
-- the BIOS), which drops taps on those ranges. Removing or reinstalling taps
-- from a change notifier crashed MAME 0.288 here, so the count taps go in at
-- the first frame instead; accesses before it (first ~16 ms) are not counted.
local ctaps = {}
local cdefs = {}
local function install_counters()
  for _, c in ipairs(cdefs) do
    local name, lo, hi, dirs = c[1], c[2], c[3], c[4]
    if dirs:find("W") then
      ctaps[#ctaps + 1] = sp:install_write_tap(lo, hi, "zn2map_" .. name .. "_w",
        function(o, d, mk) count(name, "W", o) end)
    end
    if dirs:find("R") then
      ctaps[#ctaps + 1] = sp:install_read_tap(lo, hi, "zn2map_" .. name .. "_r",
        function(o, d, mk) count(name, "R", o) end)
    end
  end
  ZN2MAP.ctaps = ctaps
end
local function counter(name, lo, hi, dirs)
  cdefs[#cdefs + 1] = { name, lo, hi, dirs }
end

local function trace(name, lo, hi, dirs)
  if dirs:find("W") then
    ZN2MAP.taps[#ZN2MAP.taps + 1] = sp:install_write_tap(lo, hi, "zn2map_" .. name .. "_w",
      function(o, d, mk) rec(name, "W", o, d, mk) end)
  end
  if dirs:find("R") then
    ZN2MAP.taps[#ZN2MAP.taps + 1] = sp:install_read_tap(lo, hi, "zn2map_" .. name .. "_r",
      function(o, d, mk) rec(name, "R", o, d, mk) end)
  end
end

-- PS1 memory control and on-chip registers
trace("memctrl",   0x1f801000, 0x1f801023, "RW") -- exp1 base, exp2 base, delay/size x6, com_delay
trace("ramcfg",    0x1f801060, 0x1f801063, "RW")
trace("irq",       0x1f801070, 0x1f801077, "W")
trace("dpcr",      0x1f8010f0, 0x1f8010f7, "W")
trace("cd",        0x1f801800, 0x1f801803, "RW")
trace("sio1",      0x1f801050, 0x1f80105f, "RW")
trace("mdec",      0x1f801820, 0x1f801827, "RW")
trace("exp2",      0x1f802000, 0x1f803fff, "RW")
trace("biu",       0xfffe0130, 0xfffe0133, "RW")
-- ZN board (zn.cpp maincpu_program_map, zn2_maincpu_program_map)
trace("p1p2svsys", 0x1fa00000, 0x1fa00303, "RW")
trace("p3p4",      0x1fa10000, 0x1fa10103, "RW")
trace("boardcfg",  0x1fa10200, 0x1fa10203, "RW")
trace("znsecsel",  0x1fa10300, 0x1fa10303, "W")
trace("coin",      0x1fa20000, 0x1fa20003, "RW")
trace("x1fa40000", 0x1fa40000, 0x1fa40003, "RW")
trace("x1fa51c00", 0x1fa51c00, 0x1fa51dff, "RW")
trace("x1fa60000", 0x1fa60000, 0x1fa60003, "RW")
trace("eeprom",    0x1faf0000, 0x1faf07ff, "RW")
trace("x1fb20000", 0x1fb20000, 0x1fb20007, "RW")
-- unmapped parts of 0x1fa00000-0x1fbfffff that a board decode might still see
trace("x1fa3x",    0x1fa30004, 0x1fa3ffff, "RW")
trace("x1fb3x",    0x1fb30000, 0x1fb3ffff, "RW")
trace("x1fb5x",    0x1fb50000, 0x1fb5ffff, "RW")
trace("x1fb9x",    0x1fb90000, 0x1fb9ffff, "RW")
trace("x1fbdx",    0x1fbd0000, 0x1fbdffff, "RW")
trace("x1fbfx",    0x1fbf0000, 0x1fbfffff, "RW")
-- BIOS ROM beyond 512 KB (mirror or bus error, rom_config)
counter("bioshi",    0x1fc80000, 0x1fffffff, "RW")
-- main RAM above 2 MB, in KUSEG, KSEG0 and KSEG1
counter("ram2to4",   0x00200000, 0x003fffff, "W")
counter("ram4to8",   0x00400000, 0x007fffff, "RW")
counter("ram2to4k0", 0x80200000, 0x803fffff, "W")
counter("ram4to8k0", 0x80400000, 0x807fffff, "RW")
counter("ram2to4k1", 0xa0200000, 0xa03fffff, "W")
counter("ram4to8k1", 0xa0400000, 0xa07fffff, "RW")

local installed = false
ZN2MAP.frame = emu.add_machine_frame_notifier(function()
  if not installed then
    installed = true
    install_counters()
    push(fmt("%.9f counters_installed", now()))
  end
end)

ZN2MAP.stop = emu.add_machine_stop_notifier(function()
  for name, _ in pairs(prev) do flushprev(name) end
  if nbuf > 0 then f:write(table.concat(buf, "\n", 1, nbuf), "\n"); nbuf = 0 end
  f:close()
  local s = assert(io.open(OUT .. "/zn2map_summary.txt", "w"))
  s:write(fmt("set %s emulated_seconds %.6f\n", emu.romname(), now()))
  local names = {}
  for n, _ in pairs(stats) do names[#names + 1] = n end
  table.sort(names)
  for _, n in ipairs(names) do
    local st = stats[n]
    s:write(fmt("%s reads %d writes %d first %.6f last %.6f\n", n, st.r, st.w, st.first, st.last))
    local keys = {}
    for k, _ in pairs(st.wv) do keys[#keys + 1] = k end
    table.sort(keys)
    local shown = 0
    for _, k in ipairs(keys) do
      if shown < 40 then s:write(fmt("  W %s x%d\n", k, st.wv[k])) end
      shown = shown + 1
    end
    if shown > 40 then s:write(fmt("  ... %d distinct writes\n", shown)) end
  end
  local cn = {}
  for n, _ in pairs(cnt) do cn[#cn + 1] = n end
  table.sort(cn)
  for _, n in ipairs(cn) do
    local c = cnt[n]
    s:write(fmt("%s count reads %d writes %d first %.6f last %.6f lo %08x hi %08x\n",
      n, c.r, c.w, c.first, c.last, c.lo, c.hi))
  end
  s:close()
end)
