# MAME sources used as the reference

MAME is the behavioural reference for the parts of the board that no
better source documents (evidence rank 5, docs/evidence_sources.md). I
read these files unmodified, at tag `mame0288` and, for the ZSG-2 fix, at
commit 61c794064422682db7a1f8b3d58c21563333a9c8 (short 61c7940, superctr,
2026-09-14, "sound/zsg2.cpp: narrow the current-volume readback to 13 bits
(#16134)"; it changes only `chan_r` case 0xb, and `zsg2.h` is identical).
No MAME code is in the RTL; each RTL document states its sources.

The files are not copied into this repository. The links below point at
the exact versions, and the md5 of each file as read is listed so a local
copy can be checked. Licences are as stated in each file header (most are
BSD-3-Clause; `pccard.cpp` and `pccard.h` are GPL-2.0-or-later).

Where a document cites `<file>:<line>` for one of these files, the line
numbers are those of the version listed here. MAME's `psx.cpp` and `psx.h`
under `src/devices/video/` are cited as `psxgpu.cpp` and `psxgpu.h`.

| Version | File | md5 |
|---|---|---|
| mame0288 | [src/devices/bus/pccard/ataflash.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/bus/pccard/ataflash.cpp) | `6801bfb9c37c13cafd1c6fc088b40468` |
| mame0288 | [src/devices/bus/pccard/ataflash.h](https://github.com/mamedev/mame/blob/mame0288/src/devices/bus/pccard/ataflash.h) | `9ea56d500669d0091074a23cab8b553f` |
| mame0288 | [src/devices/machine/atahle.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/machine/atahle.cpp) | `a42e8fbb00e1212fe5504bf78c081edd` |
| mame0288 | [src/devices/machine/atahle.h](https://github.com/mamedev/mame/blob/mame0288/src/devices/machine/atahle.h) | `dcf54fe3de77013ec93e090f9c24e13e` |
| mame0288 | [src/devices/machine/atastorage.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/machine/atastorage.cpp) | `0d1621b7ff43e604e6b895ad157aba47` |
| mame0288 | [src/devices/machine/atastorage.h](https://github.com/mamedev/mame/blob/mame0288/src/devices/machine/atastorage.h) | `811d2d023a076105f715147c6ab0ea4d` |
| mame0288 | [src/devices/machine/intelfsh.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/machine/intelfsh.cpp) | `204ecb8baa115d9df59c1676c60e096b` |
| mame0288 | [src/devices/machine/intelfsh.h](https://github.com/mamedev/mame/blob/mame0288/src/devices/machine/intelfsh.h) | `dafb670fa13977c1f05d1927f647a7e5` |
| mame0288 | [src/devices/machine/mb3773.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/machine/mb3773.cpp) | `9ed960a14942398181ebf03e34b91b42` |
| mame0288 | [src/devices/cpu/psx/mdec.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/cpu/psx/mdec.cpp) | `2006b3b79aeabc4616ba2b545f087cea` |
| mame0288 | [src/devices/cpu/mn10200/mn10200.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/cpu/mn10200/mn10200.cpp) | `11928627431edf4154061b8b971d05f8` |
| mame0288 | [src/devices/cpu/mn10200/mn10200.h](https://github.com/mamedev/mame/blob/mame0288/src/devices/cpu/mn10200/mn10200.h) | `e1c4d3a5b8fe01e1864fd6fd71dfe44a` |
| mame0288 | [src/devices/cpu/mn10200/mn102dis.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/cpu/mn10200/mn102dis.cpp) | `59dc4908d78dbb617d6550ef07e9982f` |
| mame0288 | [src/devices/cpu/mn10200/mn102dis.h](https://github.com/mamedev/mame/blob/mame0288/src/devices/cpu/mn10200/mn102dis.h) | `82474d2d92c80e23aa748827606c7d60` |
| mame0288 | [src/mame/namco/namcos12.cpp](https://github.com/mamedev/mame/blob/mame0288/src/mame/namco/namcos12.cpp) | `b2746f1cbfc7b9d7d0c302b7c7320498` |
| mame0288 | [src/devices/bus/pccard/pccard.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/bus/pccard/pccard.cpp) | `99f863167c2b4368efe6d19d6265c1e0` |
| mame0288 | [src/devices/bus/pccard/pccard.h](https://github.com/mamedev/mame/blob/mame0288/src/devices/bus/pccard/pccard.h) | `8c7208d87635ad9c204b1f6b8c618a08` |
| mame0288 | [src/devices/cpu/psx/psx.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/cpu/psx/psx.cpp) | `e7f365b7168f12610644f1b6719da40d` |
| mame0288 | [src/devices/cpu/psx/psx.h](https://github.com/mamedev/mame/blob/mame0288/src/devices/cpu/psx/psx.h) | `e6f7850b8bdc11572c5fdcbcd3bd2176` |
| mame0288 | [src/devices/video/psx.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/video/psx.cpp) | `32741eeb0835bafbfeaac552b33b75f2` |
| mame0288 | [src/devices/video/psx.h](https://github.com/mamedev/mame/blob/mame0288/src/devices/video/psx.h) | `9f8b664df3e11e6ed5ca7773e72483b8` |
| mame0288 | [src/devices/machine/rf5c296.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/machine/rf5c296.cpp) | `a1f1bb9af2f1a19e115a5c6c6fa5795b` |
| mame0288 | [src/devices/machine/rf5c296.h](https://github.com/mamedev/mame/blob/mame0288/src/devices/machine/rf5c296.h) | `1f185af24f439afbe8279d6dbdefefb6` |
| mame0288 | [src/devices/sound/spu.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/sound/spu.cpp) | `dd6c10292804d00cdbd24c26bc60984b` |
| mame0288 | [src/mame/sony/taito_zm.cpp](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taito_zm.cpp) | `0a5fc3fe71f40af90655538fc1f27167` |
| mame0288 | [src/mame/sony/taito_zm.h](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taito_zm.h) | `da2be30ecd8e27e14be278c02565e897` |
| mame0288 | [src/mame/sony/taitogn.cpp](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp) | `66ab408c23e819f1535d6b4b892f27d4` |
| mame0288 | [src/devices/cpu/tms57002/tms57002.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/cpu/tms57002/tms57002.cpp) | `b41420757ae96a48ef331c36e6de39bc` |
| mame0288 | [src/devices/cpu/tms57002/tms57002.h](https://github.com/mamedev/mame/blob/mame0288/src/devices/cpu/tms57002/tms57002.h) | `15dda60181e4c48316b63e82254293b2` |
| mame0288 | [src/devices/cpu/tms57002/tms57kdec.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/cpu/tms57002/tms57kdec.cpp) | `75e8d98c4e52b68743d1605e3a79f88d` |
| mame0288 | [src/devices/cpu/tms57002/tmsinstr.lst](https://github.com/mamedev/mame/blob/mame0288/src/devices/cpu/tms57002/tmsinstr.lst) | `b0a2df0f8794e11e9745f7542a869851` |
| mame0288 | [src/devices/cpu/tms57002/tmsmake.py](https://github.com/mamedev/mame/blob/mame0288/src/devices/cpu/tms57002/tmsmake.py) | `0c6691415f3a2fd6bc8daba7cad71a23` |
| mame0288 | [src/mame/sony/zn.cpp](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/zn.cpp) | `6afd5922e76d05530a1d30ce73223624` |
| mame0288 | [src/mame/sony/zn.h](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/zn.h) | `9a160d508de728f471c29ed0b60bfdf8` |
| mame0288 | [src/devices/sound/zsg2.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/sound/zsg2.cpp) | `b7b6745becb4c82e18cb72256f9f6fcc` |
| mame0288 | [src/devices/sound/zsg2.h](https://github.com/mamedev/mame/blob/mame0288/src/devices/sound/zsg2.h) | `6ffdca5263ec97eae7f2366b0d27ea4d` |
| 61c7940 | [src/devices/sound/zsg2.cpp](https://github.com/mamedev/mame/blob/61c794064422682db7a1f8b3d58c21563333a9c8/src/devices/sound/zsg2.cpp) | `c7a7caf63560dc0368cb1cf25573acf4` |
| 61c7940 | [src/devices/sound/zsg2.h](https://github.com/mamedev/mame/blob/61c794064422682db7a1f8b3d58c21563333a9c8/src/devices/sound/zsg2.h) | `6ffdca5263ec97eae7f2366b0d27ea4d` |

Other MAME 0.288 files cited by name (for example `cat702.cpp`,
`znmcu.cpp`, `sio.cpp`, `at28c16.cpp`) are read in a local MAME 0.288
source tree at the same tag and are not listed here.
