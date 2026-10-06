-- M1: feed a ps1-tests GPU stream (tools/ps1test_stream.py, "KK FFFFFFFF
-- WWWWWWWW", KK 01 = GP1, 02 = GP0) into MAME 0.288's GPU and dump VRAM.
-- At frame PS1T_AT (default 10) every word is written through the main CPU's
-- program space to GP0 (0x1f801810) or GP1 (0x1f801814), as a CPU store
-- would; MAME's psxgpu draws each command inside the write, so VRAM is
-- dumped (MAME save item p_vram, 16-bit little-endian, 1024 wide) right
-- after the last word, before the game's CPU runs again. The stream starts
-- with GP1(00) (reset) and full-VRAM fills of lines 0-511, so lines 0-511
-- hold only the test's drawing; lines 512-1023 still hold the game's data
-- (game-derived: keep the dump under a gitignored directory, never commit).
--
--   PS1T_STREAM=<stream.txt> PS1T_OUT=<vram.bin> mame <set> -rompath roms \
--     -video none -sound none -nothrottle -seconds_to_run 1 \
--     -autoboot_script tools/mame/ps1test_replay.lua
local m = manager.machine
local sp = m.devices[":maincpu"].spaces["program"]
local gpudev = m.devices[":gpu"]
local STREAM = assert(os.getenv("PS1T_STREAM"), "PS1T_STREAM not set")
local OUT = assert(os.getenv("PS1T_OUT"), "PS1T_OUT not set")
local AT = tonumber(os.getenv("PS1T_AT") or "10")
local frame = 0
PS1T = {}
PS1T.sub = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if frame ~= AT then return end
  local n = 0
  for line in io.lines(STREAM) do
    local k, _, w = line:match("^(%x+) (%x+) (%x+)")
    k = tonumber(k, 16); w = tonumber(w, 16)
    if k == 1 then sp:write_u32(0x1f801814, w) else sp:write_u32(0x1f801810, w) end
    n = n + 1
  end
  local it = emu.item(gpudev.items["0/p_vram"])
  local f = assert(io.open(OUT, "wb"))
  f:write(it:read_block(0, it.count * it.size))
  f:close()
  print(string.format("ps1test_replay: %d words at frame %d, VRAM written to %s", n, frame, OUT))
  m:exit()
end)
