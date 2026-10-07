# Testing guide

Thanks for trying the Taito G-NET core. It is an alpha: the games boot
and play, but several things have only been checked in simulation or on
my own MiSTer, and some timings are known to differ from the real board.
Your reports decide what I fix next.

Setup (the RBF, the MRAs and making the game zips from your own MAME
files) is in the [README](../README.md#installation). Please don't share
the game zips: they are made from your own files.

## What helps most

In order of value:

1. **Each game from its main MRA to the attract mode and into play**
   (test 1). Ray Crisis, XII Stag and Night Raid have not been run on real
   hardware by me yet.
2. **A first-boot copy with a first boot MRA** (test 2): does the copy
   finish and the game start?
3. **Sound balance** between the music and the sound effects (test 3),
   especially if you know the real board.
4. **Timings against a real board** (test 8), if you own one or have
   footage of one.
5. **CRT and display checks**: picture position and sync on a CRT
   (test 4), rotation and Flip Screen (test 5).
6. **Pause** (test 6) and **saving across a power cycle** (test 7).
7. **Long play**: anything that hangs, resets, glitches or slows down.

If you own a G-NET board, the questions in "For board owners" at the end
are worth more to the core than any test on the MiSTer.

## Before you start

- Note the RBF file name and the MRA you load (main or first boot).
- Note your setup: HDMI or CRT (and 15 kHz or 31 kHz), and for HDMI the
  output resolution.
- Turn the **Debug overlay** on in the OSD for any test where a game
  hangs or resets. It draws a small black box of hex numbers in the top
  left of the picture and changes nothing else. On a vertical monitor the
  text runs sideways; just rotate the photo.
- Leave **Watchdog** On and the DIP switches off.

## Test 1: boot to attract and play (main MRAs)

Load `<Game>.mra` from the Arcade menu. Every game starts the same way:

| Time | What you should see |
|---|---|
| 0 to 2 s | White "TAITO G-NET" logo |
| from about 3 s | The game's loading screen: its name and version, and a bar that fills and says COMPLETE |

Then each game goes its own way. The times below are from MAME. The core
is later: about 0.5 s up to the loading bar, then 1.5 to 5 s from the
NOTICE screen on, and Ray Crisis's bar takes about 17 s on the core (MAME
12 s, a real board 14.7 s).

**Ray Crisis** (horizontal)

| MAME time | Screen |
|---|---|
| 3 to 15 s | "Prepares the start." with a blue bar and a blinking "WARNING! DON'T INSERT COIN" |
| 16 to 18 s | Black |
| 19 to 20 s | NOTICE in small text |
| 21 to 22 s | Blue TAITO logo |
| 23 s | "Con-Human", then the intro with green text and ship close-ups. Red "ALERT" and "ERROR ERROR" screens are part of the intro, not a fault |
| Coin, Start | "PUSH START BUTTON", then ENTRY CODE with a 30 s timer, then the game |

**Psyvariar -Medium Unit-** and **-Revision-** (vertical)

| MAME time | Screen |
|---|---|
| 3 to 4 s | "Prepares the start.", COMPLETE almost at once |
| 5 to 9 s | Black |
| 10 to 15 s | NOTICE over a star field |
| 17 s on | "Prologue": story text over 3D scenes |
| Coin, Start | Ship close-up, "PRESS START BUTTON", then a white flash, "AREA 1 EARTH" and the game within about 4 s |

The table is from a MAME run of Medium Unit; I have no MAME screen run of
Revision yet and expect the same flow.

**XII Stag** (vertical)

| MAME time | Screen |
|---|---|
| 3 to 5 s | Japanese loading screen, COMPLETE at about 4 s |
| 6 to 8 s | Black |
| 9 to 13 s | NOTICE "This video game is for use in Japan only" |
| 14 to 17 s | TAITO logo on grey |
| 18 to 21 s | "Triangle Service" logo on white |
| 27 s on | XII STAG title over a glowing sphere |
| Coin, Start | How-to screen, then the game over clouds |

**Shikigami no Shiro** (vertical)

| MAME time | Screen |
|---|---|
| 3 to 5 s | Japanese loading screen, COMPLETE at about 4 s |
| 5 to 8 s | Dark for about 2.5 s. This pause is normal; the game must not reset here |
| 8 to 10 s | NOTICE on brown |
| 11 to 13 s | TAITO logo on white |
| 14 to 19 s | "Alfa System presents" |
| 20 s on | Night city with Japanese story text |
| Coin, Start | Blue hexagons, Character Select (15 s timer), How to play (Start skips it), then the game |

**Night Raid** (horizontal)

| MAME time | Screen |
|---|---|
| 3 to 5 s | Japanese loading screen, COMPLETE at about 4 s |
| 6 to 8 s | Black, then white. The longest pause of the six games |
| 9 to 11 s | NOTICE in blue text |
| 12 to 16 s | Purple cave fly-through |
| 17 s on | "THE BEST HOT PLAYERS" and "THE BEST COOL PLAYERS" tables |
| Coin, Start | TUTORIAL (Start skips it), then the game |

Screens that mean something went wrong (please photograph them):

- **"CanNotFindProgramRom / ERROR B930"**: the core could not read the
  sub-BIOS flash.
- **"SYSTEM ERROR"** after the logo: the BIOS found no usable card.
- **The logo coming back** every few seconds: a reset loop. Turn on the
  Debug overlay and photograph the box.
- A loading bar that stops moving for more than 30 s (main MRA) or
  5 minutes (first boot MRA): note where the bar stopped.

Report: the last screen reached, about how long it took to reach NOTICE,
and a few minutes of play: anything that looks or sounds wrong.

## Test 2: first-boot copy (first boot MRAs)

Load `<Game> (first boot).mra` from the game's folder under
`_alternatives` in the Arcade menu. The BIOS copies the card into
the flash chips, as a real board does after a card swap: a "Loading now."
screen (or its Japanese version) with a red warning not to turn off the
power or remove the card. In MAME the copy takes about 2 to 2.3 minutes
depending on the game (XII Stag is the shortest); on the core about
2.5 minutes. Do not reset or power off during it. The core does not keep
the flash between loads, so this happens at every load of a first boot
MRA.

Report: whether the copy finishes and the game starts, and the time from
the copy screen appearing to it going away.

## Test 3: sound balance

The music comes from the Taito Zoom board, most sound effects from the
PlayStation sound chip (SPU). How loud the effects are against the music
on a real board is not settled. MAME's balance was set by ear, and the
core's default is MAME's 0.3. One phone recording of a real Psyvariar
Revision cabinet suggests more for that game, but a higher default
sounded wrong for Night Raid, so the default stays at MAME's until there
is board evidence per game.

- Play a minute of each game and say whether the effects sound too quiet,
  right or too loud against the music.
- Try the **SFX Level** settings in the OSD and tell me which one sounds
  right in each game (0.3 is MAME's and the default; 0.45, 0.6, 0.9, 1.2
  and 1.5 are louder).
- Check for crackle, wrong pitch, drop-outs or missing music. The BIOS
  screens and the loading bars are silent; that is normal.
- If you know the real board well, or have a recording of one, say so:
  that is the most useful comparison I can get.

A phone video with sound is better than a description.

## Test 4: CRT picture and sync

On a CRT (15 kHz, direct video or an analog output):

- The picture should stay stable and black while an MRA loads and while
  the core resets (no loss of sync, no rolling).
- **CRT H Position** and **CRT V Position** move the picture. Say which
  settings centre it on your monitor, and whether the default is far off.
- Check the top of the picture for a bent or unstable first few lines.
- Ray Crisis switches between 256, 320, 512 and 640-dot modes (the NOTICE
  screen is 640 dots): check that every screen stays in sync.

## Test 5: rotation and Flip Screen

The vertical games are Psyvariar (both), XII Stag and Shikigami no Shiro.

- **HDMI**: with Orientation set to Vertical, the picture should stand
  upright. Try both Rotate Direction settings. A photo of the screen
  helps.
- **Rotated CRT**: Flip Screen turns the picture 180 degrees for a monitor
  mounted the other way. Check that it does and that nothing tears.
- With rotation on, try the Scandoubler Fx settings and say whether the
  picture stays clean.

## Test 6: pause

- The Pause button (map it in the OSD) or the P key should stop and
  restart the game. Opening the OSD pauses too, unless you turn that off.
- Leave a game paused for more than 10 seconds, then resume: it must carry
  on without resetting (the watchdog is held off during pause).
- Sound should be silent while paused and come back cleanly.

## Test 7: saving across a power cycle

The board's EEPROM (settings and high scores) is saved as NVRAM when you
open the OSD after the game has written to it.

1. Get a high score into a table, or change a setting in the game's test
   mode (press Test, or set DIP switch 4 On and reset; set it back
   afterwards).
2. Open the OSD once, so MiSTer saves the NVRAM.
3. Power the MiSTer off, then load the same game again.
4. Check that the score or the setting is still there.

Report: which game, what you changed, and whether it survived.

## Test 8: timings against a real board

If you own a board, or know of footage of one, these comparisons pin down
the CPU speed and the loading code:

- **Ray Crisis**: how long the "Prepares the start." bar takes, from its
  screen appearing to it going away. A real board takes 14.69 s (from a
  video of a board running the MB2011 BIOS); the core about 17 s.
- **Night Raid, Ray Crisis, Shikigami**: power-on to the NOTICE screen,
  and the length of the dark pause after the loading bar.
- **Ray Crisis attract demo 1** (the first demo after the intro): its
  length and how much it slows down. A real board takes about 51.5 s and
  drops frames; MAME takes 47.8 s and drops almost none.
- Any heavy scene where the real board slows down: does the core slow
  down in the same places and by about the same amount?

Film with a phone at 60 fps if it can, with the whole screen in view, and
count from the video. A direct capture is better still.

## How to report

Open an issue in this repository, one per problem. Please include:

- the RBF file name, the MRA, and HDMI or CRT;
- what you did and what happened, with the time it happened;
- a photo or a phone video (with sound for anything audio);
- for a hang or a reset: a photo of the Debug overlay box (see below);
- for timings: your numbers and how you measured them.

### Reading the debug overlay

All numbers are hexadecimal.

| Row | What it tells me |
|---|---|
| PC, DA | Where the CPU is running and the last address it touched. If the game hangs, these two tell me where |
| IO | The control register (normally alternating C8 and E8), the number of watchdog expiries, and the last I/O address |
| MS | Milliseconds since the core came out of reset |
| WD | Milliseconds since the last watchdog kick, and the longest such gap since power-on. The watchdog fires at 1F40 (8 s) |
| RS | Resets caused by the watchdog (should stay 00), other resets, and card sector reads (rise while a game loads) |
| XP, XD, XI, XM | A snapshot taken at the last watchdog expiry: where the CPU was, the time since the last kick, the time since reset. All zero means no expiry since the core was loaded |
| DR | Memory arbiter status. Normal is `DR 0000 000x` with a small last digit |

If the first number of RS goes up, the watchdog reset the game; then the
XP row is the most useful photo.

## For board owners

I'm trying to match the real hardware, and a few facts about the board
can only come from a real one. If you own a Taito G-NET (the ZN-2 main
board with the Taito FC PCB on top), any of these would help. Photos in
good light, square on and sharp enough to read the chip text are ideal.
I'll credit anything I use.

**Photos**

1. Both sides of the FC PCB (the top board), with the game you run noted
   and the board number (K91X0721A or K91X0721B). I want to know whether
   late boards (XII Stag, Shikigami no Shiro) use a different sound DSP
   ("ZFX-2") or sound CPU ("MN1020819DA").
2. A close-up of the AT28C16 EEPROM on the main board (position IC356,
   near the Sony BIOS chip), and of the crystal next to the CXD8661R.
3. The area around the MB3773 (U43) and ADM708 (U5) on the underside of
   the FC PCB, and the MB87078 (U1) on both sides.

**Measurements** (a multimeter, scope or frequency counter)

4. The value of the capacitor on pin 1 of the MB3773 (U43). It sets the
   watchdog time, which I currently have to guess.
5. Where the MB3773's reset outputs (pins 8 and 2) and the ADM708's reset
   pins (1, 7 and 8) go: to the connector to the main board, to the sound
   CPU, or to the board's logic chip.
6. The vertical and horizontal sync rates on the JAMMA sync pin. MAME's
   notes say 59.8260 Hz and 15.4333 kHz, and the second figure does not fit
   the first.
7. On the TMS57002 (U7): is pin 10 tied to 5 V or ground, and where does
   pin 80 go?
8. Where the Zoom reset line reaches: only the MN10200 sound CPU's reset
   pin, or also the ZSG-2 and TMS57002?
9. Which pin of the XC95108 (U64), or which address line, reaches the
   MB87078's DSEL pin, and whether the MB87078 controls the Zoom sound
   alone or the final mix.
10. The empty SW1 footprint under the MN1020012A (U42) and the empty U24
    on the underside: which MN1020012A pins their pads connect to.
11. With a scope, the MB3773 CK pin (pin 3) during the dark pause after a
    loading bar: I expect no pulses there for about 3 s.

**Recordings and videos**

12. A line-out recording (stereo switch set to stereo, volume dial noted)
    of a Psyvariar attract or a minute of play, the Shikigami no Shiro
    intro, and Night Raid and Ray Crisis attract demos. These set the
    balance between the music and the effects.
13. The analog sound path: where the PlayStation sound chip's output and
    the Zoom board's output are added together before the amplifier. A
    photo of the resistors there with their values, or a schematic, lets
    me set the balance from the hardware.
14. A timed video, ideally a direct capture, of a normal power-on of Night
    Raid, Ray Crisis or Shikigami no Shiro to the NOTICE screen.
15. A timed video of a first boot after swapping to a different game card,
    from power-on to the game's first screen.

**Documents**

16. The G card instruction manual for any of the five games: the test mode
    and DIP switch pages, the button names, and for Night Raid whether the
    monitor is mounted horizontally or vertically.
