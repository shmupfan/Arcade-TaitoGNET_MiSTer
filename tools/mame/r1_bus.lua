-- R1/R2 bus trace (MAME 0.288, Taito G-NET): main-CPU accesses to
--   the ZN-2 window 0x1fa51c00-0x1fa51dff and 0x1fa60000 (zn.cpp:170-172),
--   the SPU registers 0x1f801c00-0x1f801dff,
--   the root counters 0x1f801100-0x1f80112f,
--   memory control 0x1f801000-0x1f801023 (writes) and IRQ stat/mask writes,
--   DMA channel 4 (SPU) CHCR starts.
-- Writes, under $R1B_OUT (keep it under sim/r1/, gitignored):
--   summary.txt   counts by register/value/PC, spacing histograms, polling runs
--   persec.csv    per-second counts of the main classes
--   seq_spu.txt   R1B_SEQ_N tapped events from the first 0x1fa51c00 access
--                 (time, PC, kind, addr, data, mask)
--   seq_play.txt  R1B_SEQ_N events from R1B_COIN_AT + 30 s (gameplay)
--   ram_end.bin   main RAM (4 MB) at exit, for disassembly of the PCs
-- Env: R1B_OUT (dir), R1B_COIN_AT (emulated s; coin pulse 0.1 s, start at +2 s,
--      fire held from +5 s with left/right movement), R1B_SEQ_N (default 6000).
-- Landmines: machine.time.seconds is an integer, use :as_double(); taps and
-- notifiers live in the global R1B table or they are garbage collected.
local fmt = string.format
local OUT = os.getenv("R1B_OUT") or "."
local COIN_AT = tonumber(os.getenv("R1B_COIN_AT") or "")
local SEQ_N = tonumber(os.getenv("R1B_SEQ_N") or "6000")
local m = manager.machine
local cpu = m.devices[":maincpu"]
local sp = cpu.spaces["program"]
local pcst = cpu.state["pc"]
local function now() return m.time:as_double() end
local function pc() return pcst.value end

R1B = { taps = {}, subs = {} }

-- counters ------------------------------------------------------------------
local cnt = {}            -- generic key -> count
local function inc(k, n) cnt[k] = (cnt[k] or 0) + (n or 1) end
local persec = {}         -- second -> class -> count
local classes = { "x51c_r", "x51c_w", "x60_r", "x60_w", "spu_r", "spu_w", "rc0_r", "rc1_r", "rc2_r",
                  "rcmode_r", "rc_w", "ack_t0", "ack_t1", "ack_t2", "ack_vbl", "ack_dma", "ack_spu", "dma4" }
local function ps(cls)
  local s = math.floor(now())
  local row = persec[s]
  if not row then row = {}; persec[s] = row end
  row[cls] = (row[cls] or 0) + 1
end

-- event sequence logs ---------------------------------------------------------
local seq = { spu = { n = 0, buf = {} }, play = { n = 0, buf = {} } }
local seq_on = false       -- set by the first 0x1fa51c00 access
local function ev(kind, addr, data, mask)
  local t = now()
  local line
  if seq_on and seq.spu.n < SEQ_N then
    line = fmt("%.9f %08x %s %08x %08x %08x", t, pc(), kind, addr, data, mask)
    seq.spu.n = seq.spu.n + 1; seq.spu.buf[seq.spu.n] = line
  end
  if COIN_AT and t >= COIN_AT + 30 and seq.play.n < SEQ_N then
    line = line or fmt("%.9f %08x %s %08x %08x %08x", t, pc(), kind, addr, data, mask)
    seq.play.n = seq.play.n + 1; seq.play.buf[seq.play.n] = line
  end
end

-- 16-bit register address from a 32-bit bus tap
local function half(off, mask)
  if mask == 0xffff0000 then return off + 2 end
  return off
end

-- spacing histogram (log2 of ns)
local function hist(name, dt)
  local ns = dt * 1e9
  local b = ns < 1 and -1 or math.floor(math.log(ns, 2))
  inc(fmt("hist %s %02d", name, b))
end

-- SPU -------------------------------------------------------------------------
local last_spu_t, last_spu_w_t = nil, nil
local last_spu_desc = "-"
local x51c_pending = nil   -- time of a 0x1fa51c00 read waiting for the next SPU access
local function spu_name(a)
  local o = a - 0x1f801c00
  if o < 0x180 then return fmt("voice.%x", o & 0xf) end
  return fmt("%03x", o)
end
local function spu_access(dir, off, data, mask)
  local a = half(off, mask)
  local t = now()
  local name = spu_name(a)
  inc(fmt("spu %s %s", dir, name))
  inc(fmt("spupc %s %08x", dir, pc()))
  ps(dir == "W" and "spu_w" or "spu_r")
  if last_spu_t then hist("spu_any", t - last_spu_t) end
  if dir == "W" then
    if last_spu_w_t then hist("spu_w", t - last_spu_w_t) end
    last_spu_w_t = t
  end
  if x51c_pending then
    hist("x51c_to_next_spu", t - x51c_pending)
    inc(fmt("x51c_next_spu %s %s", dir, name))
    x51c_pending = nil
  end
  last_spu_t = t
  last_spu_desc = dir .. " " .. name
  ev("spu" .. dir, a, data, mask)
end
R1B.taps[#R1B.taps + 1] = sp:install_write_tap(0x1f801c00, 0x1f801dff, "r1b_spu_w",
  function(o, d, k) spu_access("W", o, d, k) end)
R1B.taps[#R1B.taps + 1] = sp:install_read_tap(0x1f801c00, 0x1f801dff, "r1b_spu_r",
  function(o, d, k) spu_access("R", o, d, k) end)

-- ZN-2 window and toggle --------------------------------------------------------
local last_x51c_t, last_x60_t = nil, nil
local function x51c(dir, o, d, k)
  local t = now()
  local a = half(o, k)
  inc(fmt("x51c %s %03x", dir, a - 0x1fa51c00))
  inc(fmt("x51cpc %s %08x", dir, pc()))
  ps(dir == "W" and "x51c_w" or "x51c_r")
  if last_spu_t then hist("spu_to_x51c", t - last_spu_t) end
  inc(fmt("x51c_prev_spu %s", last_spu_desc))
  if last_x51c_t then hist("x51c_gap", t - last_x51c_t) end
  last_x51c_t = t
  x51c_pending = t
  seq_on = true
  ev("x51c" .. dir, a, d, k)
end
R1B.taps[#R1B.taps + 1] = sp:install_read_tap(0x1fa51c00, 0x1fa51dff, "r1b_x51c_r",
  function(o, d, k) x51c("R", o, d, k) end)
R1B.taps[#R1B.taps + 1] = sp:install_write_tap(0x1fa51c00, 0x1fa51dff, "r1b_x51c_w",
  function(o, d, k) x51c("W", o, d, k) end)
local function x60(dir, o, d, k)
  local t = now()
  inc(fmt("x60 %s %08x mask %08x data %08x", dir, o, k, d))
  inc(fmt("x60pc %s %08x", dir, pc()))
  ps(dir == "W" and "x60_w" or "x60_r")
  if last_x51c_t then hist("x51c_to_x60", t - last_x51c_t) end
  last_x60_t = t
  ev("x60" .. dir, o, d, k)
end
R1B.taps[#R1B.taps + 1] = sp:install_read_tap(0x1fa60000, 0x1fa60003, "r1b_x60_r",
  function(o, d, k) x60("R", o, d, k) end)
R1B.taps[#R1B.taps + 1] = sp:install_write_tap(0x1fa60000, 0x1fa60003, "r1b_x60_w",
  function(o, d, k) x60("W", o, d, k) end)

-- memory control writes (delay/size registers) ---------------------------------
R1B.taps[#R1B.taps + 1] = sp:install_write_tap(0x1f801000, 0x1f801023, "r1b_memctrl_w",
  function(o, d, k)
    inc(fmt("memctrl W %08x %08x", o, d))
    ev("mcW", o, d, k)
  end)

-- root counters ---------------------------------------------------------------
-- polling runs: consecutive reads of the same counter register (any PC); a
-- counter write or a read of another counter register ends a run
local run = { key = nil, n = 0, t0 = 0, t1 = 0 }
local function run_close()
  if run.key and run.n > 0 then
    local b = run.n >= 64 and "64+" or run.n >= 16 and "16-63" or run.n >= 4 and "4-15" or run.n >= 2 and "2-3" or "1"
    inc(fmt("rcrun %s len %s", run.key, b))
    local mk = "rcrunmax " .. run.key
    if run.n > (cnt[mk] or 0) then
      cnt[mk] = run.n
      cnt["rcrunspan_us " .. run.key] = math.floor((run.t1 - run.t0) * 1e6 + 0.5)
    end
  end
  run.key = nil; run.n = 0
end
local function rc_access(dir, o, d, k)
  local t = now()
  local n = (o - 0x1f801100) >> 4
  local r = (o >> 2) & 3
  local rname = ({ "value", "mode", "target", "r3" })[r + 1]
  local p = pc()
  if dir == "W" then
    run_close()
    inc(fmt("rc W c%d %s %04x pc %08x", n, rname, d & 0xffff, p))
    ps("rc_w")
  else
    inc(fmt("rc R c%d %s", n, rname))
    inc(fmt("rcpc R c%d %s pc %08x", n, rname, p))
    if r == 0 then ps(fmt("rc%d_r", n)) else ps("rcmode_r") end
    local key = fmt("c%d.%s", n, rname)
    if run.key == key then
      run.n = run.n + 1; run.t1 = t
    else
      run_close()
      run.key = key; run.n = 1; run.t0 = t; run.t1 = t
    end
  end
  ev("rc" .. dir, o, d, k)
end
R1B.taps[#R1B.taps + 1] = sp:install_read_tap(0x1f801100, 0x1f80112f, "r1b_rc_r",
  function(o, d, k) rc_access("R", o, d, k) end)
R1B.taps[#R1B.taps + 1] = sp:install_write_tap(0x1f801100, 0x1f80112f, "r1b_rc_w",
  function(o, d, k) rc_access("W", o, d, k) end)

-- IRQ: I_STAT acknowledge writes (a 0 bit clears it), I_MASK values ------------
local ackbit = { [0] = "ack_vbl", [3] = "ack_dma", [4] = "ack_t0", [5] = "ack_t1", [6] = "ack_t2", [9] = "ack_spu" }
R1B.taps[#R1B.taps + 1] = sp:install_write_tap(0x1f801070, 0x1f801077, "r1b_irq_w",
  function(o, d, k)
    if o == 0x1f801070 then
      for b, cls in pairs(ackbit) do
        if (k >> b) & 1 == 1 and (d >> b) & 1 == 0 then ps(cls); inc("irq ack " .. cls) end
      end
    else
      inc(fmt("irq mask %04x", d & 0xffff))
    end
    ev("irqW", o, d, k)
  end)

-- DMA channel 4 (SPU) starts --------------------------------------------------
R1B.taps[#R1B.taps + 1] = sp:install_write_tap(0x1f8010c8, 0x1f8010cb, "r1b_dma4",
  function(o, d, k)
    if d & 0x01000000 ~= 0 then
      ps("dma4"); inc(fmt("dma4 start chcr %08x", d))
      ev("dma4", o, d, k)
    end
  end)

-- inputs (coin held 0.1 s only: longer resets the G-NET 5 s later) --------------
local function field(name)
  for _, p in pairs(m.ioport.ports) do
    for fname, f in pairs(p.fields) do if fname == name then return f end end
  end
end
local plan = {}
if COIN_AT then
  plan = {
    { COIN_AT, "Coin 1", 1 }, { COIN_AT + 0.1, "Coin 1", 0 },
    { COIN_AT + 2, "1 Player Start", 1 }, { COIN_AT + 2.1, "1 Player Start", 0 },
    { COIN_AT + 5, "P1 Button 1", 1 },
  }
end
local step, wiggle, wphase, frame = 1, 0, -1, 0
local events = {}
R1B.subs.frame = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  local t = now()
  while plan[step] and t >= plan[step][1] do
    local f = field(plan[step][2])
    if f then f:set_value(plan[step][3]) end
    events[#events + 1] = fmt("%.3f input %s=%d%s", t, plan[step][2], plan[step][3], f and "" or " (missing)")
    step = step + 1
  end
  if COIN_AT and t > COIN_AT + 5 then
    wiggle = wiggle + 1
    local ph = (wiggle // 60) % 4
    if ph ~= wphase then
      wphase = ph
      local l, r = field("P1 Left"), field("P1 Right")
      if l and r then l:set_value(ph == 1 and 1 or 0); r:set_value(ph == 3 and 1 or 0) end
    end
  end
  if COIN_AT and (frame % 1800 == 0) then m.video:snapshot() end
end)
R1B.subs.reset = emu.add_machine_reset_notifier(function()
  events[#events + 1] = fmt("%.3f reset", now())
end)

R1B.subs.stop = emu.add_machine_stop_notifier(function()
  run_close()
  -- main RAM (4 MB) at exit, to disassemble the PCs above (tools/mame/r1_mips_dis.py)
  local d = io.open(OUT .. "/ram_end.bin", "wb")
  if d then d:write(sp:read_range(0x80000000, 0x803fffff, 8)); d:close() end
  local s = assert(io.open(OUT .. "/summary.txt", "w"))
  s:write(fmt("set %s emulated_seconds %.6f frames %d coin_at %s taps %d\n", emu.romname(), now(), frame,
    COIN_AT and fmt("%.1f", COIN_AT) or "none", #R1B.taps))
  for _, e in ipairs(events) do s:write("event " .. e .. "\n") end
  local keys = {}
  for k in pairs(cnt) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do s:write(fmt("%s %d\n", k, cnt[k])) end
  s:close()
  local c = assert(io.open(OUT .. "/persec.csv", "w"))
  c:write("second," .. table.concat(classes, ",") .. "\n")
  local secs = {}
  for k in pairs(persec) do secs[#secs + 1] = k end
  table.sort(secs)
  for _, sec in ipairs(secs) do
    local row = { tostring(sec) }
    for _, cl in ipairs(classes) do row[#row + 1] = tostring(persec[sec][cl] or 0) end
    c:write(table.concat(row, ",") .. "\n")
  end
  c:close()
  for name, q in pairs(seq) do
    local f = assert(io.open(fmt("%s/seq_%s.txt", OUT, name), "w"))
    f:write("# time pc kind addr data mask\n")
    if q.n > 0 then f:write(table.concat(q.buf, "\n", 1, q.n), "\n") end
    f:close()
  end
end)
print(fmt("r1_bus: %s -> %s (%d taps)", emu.romname(), OUT, #R1B.taps))
