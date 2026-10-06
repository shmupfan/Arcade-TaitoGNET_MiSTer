-- Dump main RAM (4 MB, KSEG0 view) at emulated time $DUMP_AT to $DUMP_OUT/ram_<t>.bin, then exit.
local m = manager.machine
local sp = m.devices[":maincpu"].spaces["program"]
local AT = tonumber(os.getenv("DUMP_AT") or "1")
local OUT = os.getenv("DUMP_OUT") or "."
DUMPN = emu.add_machine_frame_notifier(function()
  if m.time:as_double() >= AT then
    local f = assert(io.open(string.format("%s/ram_%.3f.bin", OUT, AT), "wb"))
    f:write(sp:read_range(0x80000000, 0x803fffff, 8)); f:close()
    m:exit()
  end
end)
