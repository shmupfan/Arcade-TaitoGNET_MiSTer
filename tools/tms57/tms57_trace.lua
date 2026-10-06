-- TMS57002 (Taito Zoom effects DSP) oracle for MAME 0.288, used with
-- tools/tms57/tms57_trace.sh. Writes one text log (TMS57_OUT):
--
--   H <t> <W|R> <addr> <data> <mask> <xba> <pc> <sti> <hidx>
--       MN10200 access to the TMS57002 data port (0xc00000) or to port 1
--       (0x00fe64, PLOAD bit 0 / CLOAD bit 1). xba, pc, sti, hidx are the
--       DSP state when the access happens (the tap runs before the write).
--   S <xba> <pc> <si0..3> <so0..3>
--       one line per DSP sample, at the first external RAM byte the DSP
--       reads after a sync: si = the four serial inputs of this sample,
--       so = the outputs MAME streamed at this sync (previous program run),
--       valid while pc is below the first DOMH.
--   Z <tag> <t> <xba> <pc> then ZV/ZA/ZP/ZM lines and ZE: full DSP state
--       (scalars, arrays, PMEM, the 64 KB delay RAM). Tags: "pload" before
--       the first program download; "resync" at the first idle point after
--       each PLOAD rise and at least one sync (MAME starts the new program
--       mid-sample at a point set by its scheduler, see docs/tms57002_rtl.md);
--       "periodic" every TMS57_SNAP_EVERY emulated seconds.
--   INPUT / END lines.
--
-- Landmines: machine.time.seconds is an integer (use as_double); tap and
-- notifier handles are kept in globals (TMS57) so they are not collected;
-- holding coin 1 s resets the board 5 s later, so coin is pulsed 0.1 s.
local fmt = string.format
local OUT = os.getenv("TMS57_OUT") or "tms57.log"
local SNAP_EVERY = tonumber(os.getenv("TMS57_SNAP_EVERY") or "5")
local COIN_AT = tonumber(os.getenv("TMS57_COIN_AT") or "30")
local out = assert(io.open(OUT, "w"))
local m = manager.machine
local mn = m.devices[":taito_zoom:mn10200"]
local dsp = m.devices[":taito_zoom:tms57002"]
local msp = mn.spaces["program"]
local dspd = dsp.spaces["data"]
local dspp = dsp.spaces["program"]
local function now() return m.time:as_double() end
local function item(n)
  local k = dsp.items["0/" .. n]
  assert(k, "no save item " .. n)
  return emu.item(k)
end
local st_pc, st_xba = dsp.state["PC"], dsp.state["XBA"]
local it = {}
for _, n in ipairs({ "si", "so", "sti", "hidx" }) do it[n] = item(n) end

TMS57 = { taps = {}, subs = {} }
local last_xba = -1
local snapped_pload = false
local p1_last = 0xff

local SCALARS = { "macc", "macc_read", "macc_write", "st0", "st1", "sti", "aacc", "xoa", "xba",
  "xwr", "xrd", "txrd", "creg", "pc", "ca", "id", "ba0", "ba1", "rptc", "rptc_next", "sa",
  "xm_adr", "hidx", "update_counter_head", "update_counter_tail", "allow_update" }
local ARRAYS = { "cmem", "dmem0", "dmem1", "update", "si", "so", "host" }

local function snapshot(tag)
  out:write(fmt("Z %s %.9f %x %x\n", tag, now(), st_xba.value, st_pc.value))
  for _, n in ipairs(SCALARS) do
    local i = item(n)
    local v
    if i.size == 8 then
      -- 64-bit items (macc): read() refuses values above 2^53
      v = string.unpack("<i8", i:read_block(0, 8))
    else
      v = i:read(0)
    end
    out:write(fmt("ZV %s %x\n", n, v))
  end
  for _, n in ipairs(ARRAYS) do
    local a = item(n)
    local t = {}
    for i = 0, a.count - 1 do t[#t + 1] = fmt("%x", a:read(i)) end
    out:write(fmt("ZA %s %s\n", n, table.concat(t, " ")))
  end
  local t = {}
  for i = 0, 255 do t[#t + 1] = fmt("%06x", dspp:read_u32(i) & 0xffffff) end
  out:write("ZP " .. table.concat(t, " ") .. "\n")
  for a = 0, 0xffff, 64 do
    local b = {}
    for j = 0, 63 do b[#b + 1] = fmt("%02x", dspd:read_u8(a + j)) end
    out:write(fmt("ZM %04x %s\n", a, table.concat(b)))
  end
  out:write("ZE\n")
end

-- a snapshot is taken only while the DSP is idle (S_IDLE, no external RAM
-- byte pending, PLOAD high): there the core's state is fully described by
-- the save items. Pending requests are served at the next host access or
-- frame that finds the DSP idle.
local pending = {}            -- tags waiting for an idle DSP
local rise_xba = nil          -- xba at the last PLOAD rise (resync waits for a sync after it)
local function dsp_idle()
  local sti = it.sti:read(0)
  return (sti & 0x20) ~= 0 and (sti & 0xc1) == 0
end
local function serve_pending()
  if #pending == 0 or not dsp_idle() then return end
  local keep = {}
  for _, tag in ipairs(pending) do
    if tag == "resync" and rise_xba == st_xba.value then keep[#keep + 1] = tag
    else snapshot(tag) end
  end
  pending = keep
end
local function host(rw)
  return function(o, d, mask)
    if rw == "W" and o == 0xfe64 and mask == 0x00ff then
      local v = d & 0xff
      if (p1_last & 1) == 1 and (v & 1) == 0 and not snapped_pload then
        -- first download: the whole state before it (the DSP may be running)
        snapped_pload = true
        snapshot("pload")
      end
      if (p1_last & 1) == 0 and (v & 1) == 1 then
        rise_xba = st_xba.value
        pending[#pending + 1] = "resync"
      end
      p1_last = v
    end
    if rw == "W" then serve_pending() end
    out:write(fmt("H %.9f %s %06x %04x %04x %x %x %x %x\n", now(), rw, o, d, mask,
      st_xba.value, st_pc.value, it.sti:read(0), it.hidx:read(0)))
  end
end
table.insert(TMS57.taps, msp:install_write_tap(0xc00000, 0xc00001, "tms57_dw", host("W")))
table.insert(TMS57.taps, msp:install_read_tap(0xc00000, 0xc00001, "tms57_dr", host("R")))
table.insert(TMS57.taps, msp:install_write_tap(0x00fe64, 0x00fe65, "tms57_pw", host("W")))

table.insert(TMS57.taps, dspd:install_read_tap(0x00000, 0x3ffff, "tms57_xr", function(o, d, mask)
  local x = st_xba.value
  if x ~= last_xba then
    last_xba = x
    local si, so = it.si, it.so
    out:write(fmt("S %x %x %x %x %x %x %x %x %x %x\n", x, st_pc.value,
      si:read(0), si:read(1), si:read(2), si:read(3), so:read(0), so:read(1), so:read(2), so:read(3)))
  end
end))

local function field(name)
  for _, p in pairs(m.ioport.ports) do
    for fname, f in pairs(p.fields) do if fname == name then return f end end
  end
end
local plan = {
  { COIN_AT, "Coin 1", 1 }, { COIN_AT + 0.1, "Coin 1", 0 },
  { COIN_AT + 2, "1 Player Start", 1 }, { COIN_AT + 2.1, "1 Player Start", 0 },
  { COIN_AT + 5, "P1 Button 1", 1 },
}
local step = 1
local next_snap = SNAP_EVERY
TMS57.subs.frame = emu.add_machine_frame_notifier(function()
  local t = now()
  while plan[step] and t >= plan[step][1] do
    local f = field(plan[step][2])
    if f then f:set_value(plan[step][3]) end
    out:write(fmt("INPUT %.6f %s %d%s\n", t, plan[step][2], plan[step][3], f and "" or " (field not found)"))
    step = step + 1
  end
  if t > COIN_AT + 5 then
    local l, r = field("P1 Left"), field("P1 Right")
    local ph = math.floor(t * 2) % 2
    if l then l:set_value(ph) end
    if r then r:set_value(1 - ph) end
  end
  if SNAP_EVERY > 0 and t >= next_snap then
    pending[#pending + 1] = "periodic"
    next_snap = next_snap + SNAP_EVERY
  end
  serve_pending()
end)
TMS57.subs.stop = emu.add_machine_stop_notifier(function()
  out:write(fmt("END %.9f\n", now()))
  out:close()
end)
