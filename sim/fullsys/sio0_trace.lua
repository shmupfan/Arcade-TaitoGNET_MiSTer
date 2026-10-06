-- SIO0 (0x1f801040-0x1f80104f) access trace for MAME 0.288, used to find the
-- Shikigami warm-boot stall (docs/fullsys_sim.md 5.4). Output <SIOOUT>/sio0.log,
-- one line per access: "<s> R|W <addr> <data> <mem_mask>". The taps go in at
-- the first frame (psx.cpp reinstalls handlers early in the BIOS). Logs are
-- game-derived: keep them under sim/ (gitignored work/).
--   SIOOUT=<dir> mame <set> ... -autoboot_script sim/fullsys/sio0_trace.lua
local m = manager.machine
local sp = m.devices[":maincpu"].spaces["program"]
local f = assert(io.open(os.getenv("SIOOUT") .. "/sio0.log", "w"))
local function log(d, o, v, mk) f:write(string.format("%.9f %s %08x %08x %08x\n", m.time:as_double(), d, o, v, mk)) end
SIOT = {}
SIOT.fr = emu.add_machine_frame_notifier(function()
  if SIOT.r then return end
  SIOT.r = sp:install_read_tap(0x1f801040, 0x1f80104f, "sio0r", function(o, d, mk) log("R", o, d, mk) end)
  SIOT.w = sp:install_write_tap(0x1f801040, 0x1f80104f, "sio0w", function(o, d, mk) log("W", o, d, mk) end)
end)
SIOT.st = emu.add_machine_stop_notifier(function() f:close() end)
