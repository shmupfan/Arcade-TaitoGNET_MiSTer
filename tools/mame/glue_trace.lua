-- G-NET glue replay trace (MAME 0.288), for the M2 Verilator testbenches.
-- Logs every main-CPU access to the glue blocks with its data, losslessly,
-- streamed through zstd:
--   0x1f000000-0x1f7fffff  flash bank window (U30, U27, waves, RF5C296 memory)
--   0x1fa30000-0x1fa30003  control3
--   0x1fb00000-0x1fb0ffff  RF5C296 I/O (ExCA index/data, ATA task file)
--   0x1fb40000-0x1fb40003  control
--   0x1fb60000-0x1fb60003  control2
--   0x1fb70000-0x1fb70003  0x1fb70000 register
-- Record (little-endian, 33 bytes): u8 kind (0 read, 1 write, 2 machine
-- reset, 3 end), f64 t (first access), u32 addr, u32 data, u32 mask,
-- u32 count, f64 tlast. Consecutive identical accesses (same kind, addr,
-- data, mask) fold into one record with count and tlast.
-- Header: "GNGT", u32 version 1, 16-byte set name, u8 JP1.
-- Env: GLUE_OUT (output .zst path), GLUE_COIN_AT (emulated s, optional:
-- coin 0.1 s, start 2 s later, fire held from +5 s).
-- Lessons (r18_trace.lua, oracle.lua): time via :as_double(); every tap and
-- notifier handle pinned in a global table.

local m = manager.machine
local OUT = assert(os.getenv("GLUE_OUT"), "GLUE_OUT not set")
local COIN_AT = tonumber(os.getenv("GLUE_COIN_AT") or "")
local sp = m.devices[":maincpu"].spaces["program"]
GLUE = { taps = {}, subs = {} }
local f = assert(io.popen("zstd -q -f -3 -o '" .. OUT .. "'", "w"))
local JP1 = 0
do local p = m.ioport.ports[":JP1"]; if p then JP1 = p:read() & 1 end end
local name = emu.romname()
f:write("GNGT", string.pack("<I4", 1), name .. string.rep("\0", 16 - #name), string.pack("<B", JP1))

local buf, nb = {}, 0
local has, pk, pa, pv, pm, pc, pt, pl = false, 0, 0, 0, 0, 0, 0, 0
local nrec, nacc = 0, 0
local function now() return m.time:as_double() end
local function emit()
  if not has then return end
  nb = nb + 1
  buf[nb] = string.pack("<Bd I4 I4 I4 I4 d", pk, pt, pa, pv, pm, pc, pl)
  nrec = nrec + 1
  if nb >= 4096 then f:write(table.concat(buf, "", 1, nb)); nb = 0 end
  has = false
end
local function rec(k, a, v, mk)
  nacc = nacc + 1
  local t = now()
  if has and k == pk and a == pa and v == pv and mk == pm then
    pc = pc + 1; pl = t
    return
  end
  emit()
  has, pk, pa, pv, pm, pc, pt, pl = true, k, a, v, mk, 1, t, t
end
local function trace(lo, hi, tag)
  GLUE.taps[#GLUE.taps + 1] = sp:install_read_tap(lo, hi, "glue_r_" .. tag, function(o, d, mk) rec(0, o, d, mk) end)
  GLUE.taps[#GLUE.taps + 1] = sp:install_write_tap(lo, hi, "glue_w_" .. tag, function(o, d, mk) rec(1, o, d, mk) end)
end
trace(0x1f000000, 0x1f7fffff, "flash")
trace(0x1fa30000, 0x1fa30003, "ctrl3")
trace(0x1fb00000, 0x1fb0ffff, "rf5c296")
trace(0x1fb40000, 0x1fb40003, "ctrl")
trace(0x1fb60000, 0x1fb60003, "ctrl2")
trace(0x1fb70000, 0x1fb70003, "gn1fb7")

local function field(n)
  for _, p in pairs(m.ioport.ports) do
    for fname, fl in pairs(p.fields) do if fname == n then return fl end end
  end
end
local plan = {}
if COIN_AT then
  plan = { { COIN_AT, "Coin 1", 1 }, { COIN_AT + 0.1, "Coin 1", 0 },
           { COIN_AT + 2, "1 Player Start", 1 }, { COIN_AT + 2.1, "1 Player Start", 0 },
           { COIN_AT + 5, "P1 Button 1", 1 } }
end
local step = 1
GLUE.subs.frame = emu.add_machine_frame_notifier(function()
  local t = now()
  while plan[step] and t >= plan[step][1] do
    local fl = field(plan[step][2]); if fl then fl:set_value(plan[step][3]) end
    step = step + 1
  end
end)
GLUE.subs.reset = emu.add_machine_reset_notifier(function()
  emit(); has, pk, pa, pv, pm, pc, pt, pl = true, 2, 0, 0, 0, 1, now(), now(); emit()
end)
GLUE.subs.stop = emu.add_machine_stop_notifier(function()
  emit(); has, pk, pa, pv, pm, pc, pt, pl = true, 3, 0, 0, 0, nacc, now(), now(); emit()
  if nb > 0 then f:write(table.concat(buf, "", 1, nb)); nb = 0 end
  f:close()
  local s = io.open(OUT .. ".txt", "w")
  s:write(string.format("set %s jp1 %d records %d accesses %d end %.6f\n", name, JP1, nrec, nacc, now()))
  s:close()
end)
