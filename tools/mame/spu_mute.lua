-- Load tools/mame/psy_play.lua and additionally silence the PlayStation SPU
-- by forcing every write to the key-on registers (0x1f801d88-0x1f801d8b) to
-- zero, so no SPU voice starts. With -wavwrite this gives the Zoom-only mix;
-- the SPU part is the sample-wise difference from an unmuted run with the
-- same inputs (MAME's mix is a linear sum). Env as psy_play.lua plus
-- PLAY_SCRIPT_DIR (directory of psy_play.lua).
local dir = os.getenv("PLAY_SCRIPT_DIR") or "."
dofile(dir .. "/psy_play.lua")
local sp = manager.machine.devices[":maincpu"].spaces["program"]
SPUMUTE = sp:install_write_tap(0x1f801d88, 0x1f801d8b, "spu_kon_mute", function(o, d, mk) return 0 end)
