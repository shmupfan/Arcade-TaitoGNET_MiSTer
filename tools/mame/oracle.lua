-- G-NET M0 oracle (MAME 0.288): frame captures plus main-CPU access logs for
-- GPU, SPU, Taito Zoom host port and mailbox, G-NET control registers,
-- flash command traffic, RF5C296 / ATA and CAT702 / znmcu / SIO0.
-- PLAN.md section 4 (M0) and section 7 item 5.
--
-- Usage: normally via tools/mame/oracle_run.sh <set> <seconds> <outdir> [--cold]
--
-- Environment:
--   ORACLE_OUT         run directory for the logs (default "oracle_out")
--   ORACLE_SNAP_EVERY  PNG snapshot every N frames (default 60, 0 = off);
--                      screen:snapshot("f<frame>.png"), relative to
--                      -snapshot_directory (video:snapshot() would number
--                      files 0000, 0001... with no frame in the name). MAME
--                      itself adds <set>/0000.png at exit (-seconds_to_run)
--   ORACLE_COIN_AT     emulated seconds for coin 1 (held 0.1 s), start 2 s
--                      later, then fire held and left/right wiggle (as
--                      tools/mame/r18_trace.lua); default none
--   ORACLE_FLASH_RAW   1 = log every flash window write on its own line
--                      (default: program sequences folded into PROG runs)
--
-- Logs (text, one access per line, hex without 0x, t = emulated seconds
-- from manager.machine.time:as_double(), fr = frame notifier count):
--   gpu.log      t fr W addr data mask            GP0/GP1, DMA2 MADR/BCR/CHCR
--   spu.log      t fr W addr data mask            0x1f801c00-0x1f801dff
--   zoom.log     t fr R|W addr data mask          0x1fb80000-3, 0x1fba0000,
--                                                 0x1fbc0000, mailbox 0x1fbe0000-1ff
--   ctrl.log     t fr R|W addr data mask          0x1fb40000, 0x1fb60000,
--                                                 0x1fa30000, 0x1fb70000,
--                                                 boardconfig 0x1fa10200 (R21)
--   sec.log      t fr R|W addr data mask          znsecsel 0x1fa10300, SIO0
--                                                 0x1f801040-0x1f80104f
--   ata.log      t fr R|W addr data mask o=byteoff reg   RF5C296 0x1fb00000-0x1fb0ffff
--   flash.log    see below
--   flashrd.log  sec chip blockoff count          reads per 64 KB block per second
--   events.log   start, resets, inputs, snapshots, stop
--   summary.txt  counts per log, flash command counts per chip, copy timing
-- Repeats: an access identical to the previous line of the same log (same
-- dir, addr, data, mask) is folded into it as " xN tlast". In ata.log reads
-- of the same register fold even when the data differs (ATA data port,
-- status polling) as " xN tlast last=<data> sum=<sum32 of data>".
--
-- flash.log (window 0x1f000000-0x1f7fffff, 16-bit chips on the 32-bit bus;
-- one line per 16-bit lane written; bank = control bit 2 | JP1 << 1):
--   t fr W addr data mask bank chip choff val
--       addr = address of the 16-bit lane; data/mask as the tap saw them;
--       choff = byte offset in the chip;
--       val = the 16-bit lane value written
--   t fr PROG bank chip start end words sum32 tlast cmd aux
--       a run of Intel program operations (cmd 0x40 or 0x10 then the data
--       word) to ascending consecutive words; end is the last word's offset;
--       t is the first data write; aux = 0x50/0x70 status writes folded in
--       (the BIOS issues 50, 70, 50 before every 40 + data pair)
-- Chips: firm (U30 28F160), zoomprog (U27 28F400), wave0/1/2 (U56/U55/U29),
-- eprom (BIOS, bank 2), card_attr (RF5C296 memory window: PC card
-- attribute memory, card unlock), unmapped.
--
-- Lessons carried from r18_trace.lua: machine.time.seconds is integer
-- seconds only (use as_double); every tap and notifier handle is pinned in
-- the global ORACLE table or it is garbage collected and stops firing.

local m = manager.machine
local setname = emu.romname()
local OUT = os.getenv("ORACLE_OUT") or "oracle_out"
os.execute("mkdir -p '" .. OUT .. "'")
local SNAP_EVERY = tonumber(os.getenv("ORACLE_SNAP_EVERY") or "60")
local COIN_AT = tonumber(os.getenv("ORACLE_COIN_AT") or "")
local FLASH_RAW = os.getenv("ORACLE_FLASH_RAW") == "1"

local sp = m.devices[":maincpu"].spaces["program"]
local screen = m.screens[":screen"]
if not screen then for _, s in pairs(m.screens) do screen = s; break end end

ORACLE = { taps = {}, subs = {} }
local fmt = string.format
local frame = 0
local function now() return m.time:as_double() end

---------------------------------------------------------------------------
-- buffered log with repeat folding
---------------------------------------------------------------------------
local FLUSH_AT = 512
local logs = {}

local function new_log(name, stream_reads)
  local L = {
    name = name, f = assert(io.open(OUT .. "/" .. name .. ".log", "w")),
    buf = {}, n = 0, lines = 0, acc = 0, stream = stream_reads,
    has = false, ext = nil,
  }
  logs[#logs + 1] = L
  return L
end

local function push(L, s)
  local n = L.n + 1
  L.buf[n] = s
  L.lines = L.lines + 1
  if n >= FLUSH_AT then
    L.f:write(table.concat(L.buf, "\n", 1, n), "\n")
    L.n = 0
  else
    L.n = n
  end
end

local function emit(L)
  if not L.has then return end
  local s = fmt("%.9f %d %s %08x %08x %08x", L.pt, L.pf, L.pd, L.pa, L.pv, L.pm)
  if L.ext then s = s .. " " .. L.ext end
  if L.pc > 1 then
    if L.stream and L.pd == "R" then
      s = s .. fmt(" x%d %.9f last=%08x sum=%08x", L.pc, L.pl, L.plv, L.ps)
    else
      s = s .. fmt(" x%d %.9f", L.pc, L.pl)
    end
  end
  push(L, s)
  L.has = false
end

-- ext: optional decoded columns (string), only computed for new lines
local function rec(L, d, a, v, mk, extfn)
  L.acc = L.acc + 1
  local t = now()
  if L.has and L.pd == d and L.pa == a and L.pm == mk then
    if L.pv == v then
      L.pc = L.pc + 1; L.pl = t; L.plv = v; L.ps = (L.ps + v) & 0xffffffff
      return
    elseif L.stream and d == "R" then
      L.pc = L.pc + 1; L.pl = t; L.plv = v; L.ps = (L.ps + v) & 0xffffffff
      return
    end
  end
  emit(L)
  L.has = true
  L.pt, L.pf, L.pd, L.pa, L.pv, L.pm = t, frame, d, a, v, mk
  L.pc, L.pl, L.plv, L.ps = 1, t, v, v
  L.ext = extfn and extfn(a, v, mk) or nil
end

local function flush_log(L)
  emit(L)
  if L.n > 0 then L.f:write(table.concat(L.buf, "\n", 1, L.n), "\n"); L.n = 0 end
  L.f:flush()
end

local function tap(dir, lo, hi, name, fn)
  local h
  if dir == "W" then h = sp:install_write_tap(lo, hi, "oracle_" .. name, fn)
  else h = sp:install_read_tap(lo, hi, "oracle_" .. name, fn) end
  ORACLE.taps[#ORACLE.taps + 1] = h
end

-- log both directions of a range into L (dirs "R", "W" or "RW")
local function trace(L, dirs, lo, hi, name, extfn)
  if dirs:find("W") then
    tap("W", lo, hi, name .. "_w", function(o, d, mk) rec(L, "W", o, d, mk, extfn) end)
  end
  if dirs:find("R") then
    tap("R", lo, hi, name .. "_r", function(o, d, mk) rec(L, "R", o, d, mk, extfn) end)
  end
end

local events = assert(io.open(OUT .. "/events.log", "w"))
local function event(s)
  events:write(fmt("%.9f %d %s\n", now(), frame, s))
  events:flush()
end

---------------------------------------------------------------------------
-- 1-5, 7, 8: register logs
---------------------------------------------------------------------------
local gpu = new_log("gpu", false)
trace(gpu, "W", 0x1f801810, 0x1f801817, "gpu")       -- GP0 0x10, GP1 0x14
trace(gpu, "W", 0x1f8010a0, 0x1f8010af, "dma2")      -- MADR, BCR, CHCR

---------------------------------------------------------------------------
-- GPU command stream for M1 replay (opt-in: ORACLE_GPU_STREAM=1)
-- gpu_stream.bin, little-endian records: u32 frame, u8 kind, u32 nwords,
-- then nwords u32. kind 0 = CPU write to GP0, 1 = CPU write to GP1,
-- 2 = DMA2 block (RAM to GPU), 3 = DMA2 linked list (headers removed, one
-- record per list node, so packet boundaries survive), 4 = DMA2 other mode
-- or direction (no payload; CHCR in the single word). The RAM is read when
-- the CHCR start write happens, which is what MAME's DMA then transfers.
---------------------------------------------------------------------------
local GPU_STREAM = os.getenv("ORACLE_GPU_STREAM") == "1"
local gs = nil
local gs_buf, gs_n, gs_words = {}, 0, 0
local dma2_madr, dma2_bcr = 0, 0
local function gs_put(kind, words)
  gs_buf[#gs_buf + 1] = string.pack("<I4BI4", frame, kind, #words)
  for i = 1, #words do gs_buf[#gs_buf + 1] = string.pack("<I4", words[i]) end
  gs_n = gs_n + 1
  gs_words = gs_words + #words
  if #gs_buf > 4096 then gs:write(table.concat(gs_buf)); gs_buf = {} end
end
local function ram32(a) return sp:read_u32(a & 0x3ffffc) end   -- ZN-2: 4 MB main RAM
if GPU_STREAM then
  gs = assert(io.open(OUT .. "/gpu_stream.bin", "wb"))
  tap("W", 0x1f801810, 0x1f801817, "gs_cpu", function(o, d, mk)
    gs_put((o & 4) == 0 and 0 or 1, { d })
  end)
  tap("W", 0x1f8010a0, 0x1f8010af, "gs_dma2", function(o, d, mk)
    local r = o & 0xc
    if r == 0 then dma2_madr = d & 0xffffff
    elseif r == 4 then dma2_bcr = d
    elseif r == 8 and (d & 0x01000000) ~= 0 then
      local mode, to_gpu = (d >> 9) & 3, (d & 1) == 1
      if to_gpu and mode == 1 then
        local bs, bc = dma2_bcr & 0xffff, (dma2_bcr >> 16) & 0xffff
        if bs == 0 then bs = 0x10000 end
        if bs * bc > 0x40000 then event(fmt("gpu_stream: DMA2 block %d x %d too large, skipped", bs, bc)); return end
        local w, a = {}, dma2_madr
        for i = 1, bs * bc do w[i] = ram32(a); a = a + 4 end
        gs_put(2, w)
      elseif to_gpu and mode == 2 then
        local a, nodes, words = dma2_madr, 0, 0
        local seen = {}
        repeat
          if seen[a] then event(fmt("gpu_stream: DMA2 list loops at %06x after %d nodes", a, nodes)); break end
          seen[a] = true
          local h = ram32(a)
          local n = h >> 24
          local w = {}
          for i = 1, n do w[i] = ram32(a + 4 * i) end
          if n > 0 then gs_put(3, w) end
          words = words + n
          a = h & 0xffffff
          nodes = nodes + 1
        until (a & 0x800000) ~= 0 or nodes > 65536
        GS_STATS = GS_STATS or { lists = 0, nodes = 0, words = 0, maxnodes = 0 }
        GS_STATS.lists = GS_STATS.lists + 1
        GS_STATS.nodes = GS_STATS.nodes + nodes
        GS_STATS.words = GS_STATS.words + words
        if nodes > GS_STATS.maxnodes then GS_STATS.maxnodes = nodes end
      else
        gs_put(4, { d })
      end
    end
  end)
end

local spu = new_log("spu", false)
trace(spu, "W", 0x1f801c00, 0x1f801dff, "spu")

local zoom = new_log("zoom", false)
trace(zoom, "RW", 0x1fb80000, 0x1fb80003, "zoom_reg")  -- data 0-1, address 2-3
trace(zoom, "RW", 0x1fba0000, 0x1fba0003, "zoom_irqw")
trace(zoom, "RW", 0x1fbc0000, 0x1fbc0003, "zoom_irqr")
trace(zoom, "RW", 0x1fbe0000, 0x1fbe01ff, "zoom_mbox")

-- flash bank tracking needs the control register value
local JP1 = 0
do
  local p = m.ioport.ports[":JP1"]
  if p then JP1 = p:read() & 1 end
end
local bank = JP1 << 1
local ctrl = new_log("ctrl", false)
trace(ctrl, "R", 0x1fb40000, 0x1fb40003, "ctrl")
tap("W", 0x1fb40000, 0x1fb40003, "ctrl_w", function(o, d, mk)
  if mk & 0xff ~= 0 then bank = ((d >> 2) & 1) | (JP1 << 1) end
  rec(ctrl, "W", o, d, mk)
end)
trace(ctrl, "RW", 0x1fb60000, 0x1fb60003, "ctrl2")
trace(ctrl, "RW", 0x1fa30000, 0x1fa30003, "ctrl3")
trace(ctrl, "RW", 0x1fb70000, 0x1fb70003, "gn1fb7")
trace(ctrl, "R", 0x1fa10200, 0x1fa10203, "boardcfg")

local sec = new_log("sec", false)
trace(sec, "RW", 0x1fa10300, 0x1fa10303, "znsecsel")
trace(sec, "RW", 0x1f801040, 0x1f80104f, "sio0")

-- 7: RF5C296. Byte offset into the controller window plus the register name
-- (ataflash.cpp: offsets 0-7 ATA command block, 8-15 control block;
-- rf5c296.cpp: 0x3e0 ExCA index, 0x3e1 ExCA data)
local ATA_R = { [0] = "data", "err", "seccnt", "secnum", "cyllo", "cylhi", "drvhd", "status" }
local ATA_W = { [0] = "data", "feat", "seccnt", "secnum", "cyllo", "cylhi", "drvhd", "cmd" }
local function lane0(mk)
  if mk & 0xff ~= 0 then return 0 elseif mk & 0xff00 ~= 0 then return 1
  elseif mk & 0xff0000 ~= 0 then return 2 else return 3 end
end
local ata = new_log("ata", true)
local function ata_ext_w(a, v, mk)
  local o = (a - 0x1fb00000) + lane0(mk)
  local r = (o == 0x3e0 and "exca_idx") or (o == 0x3e1 and "exca_data") or
    (o < 8 and ATA_W[o]) or (o < 16 and ("ctl" .. (o - 8))) or "?"
  return fmt("o=%x %s", o, r)
end
local function ata_ext_r(a, v, mk)
  local o = (a - 0x1fb00000) + lane0(mk)
  local r = (o == 0x3e0 and "exca_idx") or (o == 0x3e1 and "exca_data") or
    (o < 8 and ATA_R[o]) or (o < 16 and ("ctl" .. (o - 8))) or "?"
  return fmt("o=%x %s", o, r)
end
tap("W", 0x1fb00000, 0x1fb0ffff, "ata_w", function(o, d, mk) rec(ata, "W", o, d, mk, ata_ext_w) end)
tap("R", 0x1fb00000, 0x1fb0ffff, "ata_r", function(o, d, mk) rec(ata, "R", o, d, mk, ata_ext_r) end)

---------------------------------------------------------------------------
-- 6: flash window
---------------------------------------------------------------------------
local function chip_of(b, off)
  if b == 0 then
    if off < 0x200000 then return "firm", off end
    if off < 0x300000 then return "card_attr", off - 0x200000 end
    if off < 0x380000 then return "zoomprog", off - 0x300000 end
  elseif b == 1 or b == 3 then
    if off < 0x600000 then return "wave" .. (off >> 21), off & 0x1fffff end
  else
    if off < 0x100000 then return "eprom", off end
    if off < 0x200000 then return "zoomprog", (off - 0x100000) & 0x7ffff end
    if off < 0x400000 then return "firm", off - 0x200000 end
  end
  return "unmapped", off
end
local INTEL = { firm = true, zoomprog = true, wave0 = true, wave1 = true, wave2 = true }

local flash = new_log("flash", false)
local fstat = {}          -- chip -> { cmd byte -> count, words = n }
local fprog_pending = nil -- { t, cmd } after a 0x40/0x10 setup write
local run = nil           -- current PROG run
local last_cmd_t = nil    -- time of the last program/erase command
local first_cmd_t = nil
local function fs(chip)
  local s = fstat[chip]
  if not s then s = { words = 0, cmd = {} }; fstat[chip] = s end
  return s
end
local function run_flush()
  if not run then return end
  emit(flash)
  push(flash, fmt("%.9f %d PROG %d %s %06x %06x %d %08x %.9f %02x %d", run.t, run.f, run.b,
    run.chip, run.start, run.last, run.n, run.sum, run.tl, run.cmd, run.aux))
  run = nil
end
local function mark(s, t)
  if not first_cmd_t then first_cmd_t = t end
  last_cmd_t = t
  if not s.t0 then s.t0 = t end
  s.t1 = t
end
-- Classification runs in both modes: after a 0x40/0x10 setup write the next
-- write is program data, anything else on an Intel chip is a command byte
-- (low byte; the BIOS writes the command in both bytes, e.g. 0x4040).
-- Compact mode folds into one PROG run: the setup writes, the data words to
-- consecutive ascending offsets, and the 0x50 (clear status) / 0x70 (read
-- status) writes between them on the same chip (counted in the aux column).
local function flash_lane(t, a, d, mk, wa, val)
  local off = wa - 0x1f000000
  local chip, choff = chip_of(bank, off)
  local s = fs(chip)
  if not INTEL[chip] then
    s.words = s.words + 1
    run_flush()
    rec(flash, "W", wa, d, mk, function() return fmt("%d %s %06x %04x", bank, chip, choff, val) end)
    return
  end
  local c = nil
  local pcmd = fprog_pending
  if pcmd then
    fprog_pending = nil
    s.words = s.words + 1
    mark(s, t)
  else
    c = val & 0xff
    s.cmd[c] = (s.cmd[c] or 0) + 1
    if c == 0x40 or c == 0x10 then fprog_pending = c end
    if c == 0x20 or c == 0xd0 or c == 0x40 or c == 0x10 or c == 0xe8 then mark(s, t) end
  end
  if not FLASH_RAW then
    if pcmd then
      if run and run.chip == chip and run.b == bank and choff == run.last + 2 then
        run.last = choff; run.n = run.n + 1; run.sum = (run.sum + val) & 0xffffffff; run.tl = t
      else
        run_flush()
        run = { t = t, f = frame, b = bank, chip = chip, start = choff, last = choff,
                n = 1, sum = val, tl = t, cmd = pcmd, aux = 0 }
      end
      return
    end
    if c == 0x40 or c == 0x10 then return end
    if run and run.chip == chip and (c == 0x50 or c == 0x70) then run.aux = run.aux + 1; return end
  end
  run_flush()
  rec(flash, "W", wa, d, mk, function() return fmt("%d %s %06x %04x", bank, chip, choff, val) end)
end
local flash_writes = 0
tap("W", 0x1f000000, 0x1f7fffff, "flash_w", function(o, d, mk)
  flash_writes = flash_writes + 1
  local t = now()
  if mk & 0xffff ~= 0 then flash_lane(t, o, d, mk, o, d & 0xffff) end
  if mk & 0xffff0000 ~= 0 then flash_lane(t, o, d, mk, o + 2, (d >> 16) & 0xffff) end
end)

-- reads: count per 64 KB block of the bank-relative window per second
local rdcount = {}
local rdsec = 0
local flashrd = assert(io.open(OUT .. "/flashrd.log", "w"))
local rd_total = 0
tap("R", 0x1f000000, 0x1f7fffff, "flash_r", function(o, d, mk)
  local k = (bank << 7) | ((o - 0x1f000000) >> 16)
  rdcount[k] = (rdcount[k] or 0) + 1
end)
local function rd_flush(sec_end)
  local keys = {}
  for k in pairs(rdcount) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local b, blk = k >> 7, k & 0x7f
    local chip, choff = chip_of(b, blk << 16)
    flashrd:write(fmt("%d %s %06x %d\n", rdsec, chip, choff, rdcount[k]))
    rd_total = rd_total + rdcount[k]
  end
  rdcount = {}
  rdsec = sec_end
end

---------------------------------------------------------------------------
-- inputs (as r18_trace.lua: coin held 0.1 s only, longer resets the game)
---------------------------------------------------------------------------
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
local step, wiggle, wphase = 1, 0, -1

---------------------------------------------------------------------------
-- notifiers
---------------------------------------------------------------------------
local nsnaps = 0
-- VRAM dumps for M1 (ORACLE_VRAM_DUMPS="30,60,..." frame numbers): writes
-- vram_<frame>.bin (2 MB, MAME p_vram, 16-bit little-endian pixels, 1024
-- wide) and appends the display registers to vram_dumps.txt.
local VRAM_DUMPS = {}
for n in string.gmatch(os.getenv("ORACLE_VRAM_DUMPS") or "", "%d+") do VRAM_DUMPS[tonumber(n)] = true end
local gpudev = m.devices[":gpu"]
local function gpu_item(name) return emu.item(gpudev.items["0/" .. name]) end
local function vram_dump(fr)
  local it = gpu_item("p_vram")
  local f = assert(io.open(fmt("%s/vram_%d.bin", OUT, fr), "wb"))
  f:write(it:read_block(0, it.count * it.size))
  f:close()
  local r = {}
  for _, k in ipairs({ "m_n_displaystartx", "n_displaystarty", "n_horiz_disstart", "n_horiz_disend",
                       "n_vert_disstart", "n_vert_disend", "n_gpustatus" }) do
    r[#r + 1] = k .. "=" .. tostring(gpu_item(k):read(0))
  end
  local l = assert(io.open(OUT .. "/vram_dumps.txt", "a"))
  l:write(fmt("%d %.6f %s\n", fr, now(), table.concat(r, " ")))
  l:close()
end
ORACLE.subs.frame = emu.add_machine_frame_notifier(function()
  if VRAM_DUMPS[frame] then vram_dump(frame) end
  frame = frame + 1
  local t = now()
  while plan[step] and t >= plan[step][1] do
    local f = field(plan[step][2])
    if f then f:set_value(plan[step][3]) end
    event(fmt("input %s=%d%s", plan[step][2], plan[step][3], f and "" or " (field not found)"))
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
  if SNAP_EVERY > 0 and frame % SNAP_EVERY == 0 then
    local name = fmt("f%07d.png", frame)
    screen:snapshot(name)
    nsnaps = nsnaps + 1
    event("snap " .. name)
  end
  if math.floor(t) > rdsec then rd_flush(math.floor(t)) end
  if frame % 600 == 0 then
    for _, L in ipairs(logs) do emit(L); if L.n > 0 then L.f:write(table.concat(L.buf, "\n", 1, L.n), "\n"); L.n = 0 end end
  end
end)

local resets = 0
ORACLE.subs.reset = emu.add_machine_reset_notifier(function()
  resets = resets + 1
  bank = JP1 << 1  -- driver_reset: m_flashbank->set_bank(m_jp1->read() << 1)
  fprog_pending = nil
  event("reset")
end)

ORACLE.subs.stop = emu.add_machine_stop_notifier(function()
  if gs then
    gs:write(table.concat(gs_buf)); gs:close()
    event(fmt("gpu_stream records %d words %d", gs_n, gs_words))
    if GS_STATS then event(fmt("gpu_stream lists %d nodes %d words %d maxnodes %d", GS_STATS.lists, GS_STATS.nodes, GS_STATS.words, GS_STATS.maxnodes)) end
  end
  run_flush()
  rd_flush(rdsec)
  flashrd:close()
  for _, L in ipairs(logs) do flush_log(L); L.f:close() end
  event("stop")
  events:close()
  local s = assert(io.open(OUT .. "/summary.txt", "w"))
  s:write(fmt("set %s\nemulated_seconds %.6f\nframes %d\nsoft_resets %d\nsnapshots %d\njp1 %d\n",
    setname, now(), frame, resets, nsnaps, JP1))
  s:write(fmt("coin_at %s\nflash_raw %s\n", COIN_AT and fmt("%.3f", COIN_AT) or "none", tostring(FLASH_RAW)))
  flash.acc = flash_writes  -- every tap call, folded program traffic included
  for _, L in ipairs(logs) do
    s:write(fmt("log %s accesses %d lines %d\n", L.name, L.acc, L.lines))
  end
  s:write(fmt("log flashrd reads %d\n", rd_total))
  local chips = {}
  for c in pairs(fstat) do chips[#chips + 1] = c end
  table.sort(chips)
  for _, c in ipairs(chips) do
    local st = fstat[c]
    local parts = {}
    local cmds = {}
    for k in pairs(st.cmd) do cmds[#cmds + 1] = k end
    table.sort(cmds)
    for _, k in ipairs(cmds) do parts[#parts + 1] = fmt("%02x:%d", k, st.cmd[k]) end
    s:write(fmt("flash %s %s %d first_cmd %s last_cmd %s cmds %s\n", c,
      INTEL[c] and "program_words" or "writes", st.words, st.t0 and fmt("%.6f", st.t0) or "-",
      st.t1 and fmt("%.6f", st.t1) or "-", table.concat(parts, " ")))
  end
  s:write(fmt("flash first_program_or_erase_cmd %s\n", first_cmd_t and fmt("%.6f", first_cmd_t) or "-"))
  s:write(fmt("flash last_program_or_erase_cmd %s\n", last_cmd_t and fmt("%.6f", last_cmd_t) or "-"))
  s:write(fmt("taps %d\n", #ORACLE.taps))
  s:close()
end)

event(fmt("start set=%s jp1=%d snap_every=%d coin_at=%s flash_raw=%s taps=%d", setname, JP1,
  SNAP_EVERY, COIN_AT and fmt("%.3f", COIN_AT) or "none", tostring(FLASH_RAW), #ORACLE.taps))
print(fmt("oracle: %s -> %s (%d taps)", setname, OUT, #ORACLE.taps))
