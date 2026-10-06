# Licensing check: PSX_MiSTer base and GPL-3 code

Checked 2026-10-04 on PSX_MiSTer main cd17b5a (merged into this repository
as the base). This is my reading, not legal advice.

## Question

Is PSX_MiSTer GPL-2.0-only? If so, GPL-3.0 code (XelaNotPu's
GPL-3.0-or-later cores, ppriest's GPL-3.0 TMS57002) could not be combined
with it.

## Facts (from the files)

| What | Licence statement |
|---|---|
| LICENSE (repo root) | GPLv2 text only; GitHub reports GPL-2.0 |
| README.md | no licence statement |
| PSX.sv (Robert Peip, Sorgelig) | GPL "version 2 of the License, or (at your option) any later version" |
| rtl/*.vhd (61 files: CPU, GTE, GPU, SPU, MDEC, DMA, CD, ...) | no licence header in any of them |
| sys/sys_top.v and 8 other files with a version 2 statement (PSX.sv included) | GPL-2.0-or-later |
| rtl/sdram.sv, rtl/ddram.sv, rtl/hps_ext.v (Sorgelig, Alexey Melnikov), sys/hps_io.sv, sys/ddr_svc.sv, sys/scandoubler.v, sys/sd_card.sv | GPL-3.0-or-later ("either version 3 of the License, or (at your option) any later version") |
| Any file saying "version 2 only" | none found (grep over sys/ and rtl/) |

## Reading

1. Nothing in PSX_MiSTer is GPL-2.0-only. The headed files are
   GPL-2.0-or-later or GPL-3.0-or-later; the unheaded RTL ships with a GPLv2
   LICENSE file and no version statement, and GPLv2 section 9 says that when
   a program does not specify a version number, any version ever published
   may be chosen.
2. The PSX_MiSTer bitstream already combines GPL-3.0-or-later files
   (sdram.sv, ddram.sv, hps_io.sv) with the rest, so the distributed core is
   in practice a GPL-3.0-or-later combined work today. Every MiSTer core
   using the standard sys/ framework is in the same position.
3. So adding GPL-3.0 code is compatible: the combined work is distributed
   under GPL-3.0 (or later). XelaNotPu's ZN2-Capcom README states the same
   conclusion for its own tree ("mixes GPLv2-or-later and GPLv3-or-later
   files, so the combined work and its synthesized bitstream are
   GPLv3-or-later").
4. One limit: ppriest's TMS57002 is GPL-3.0 (no "or later" as far as I
   found; needs-review in its headers). Using it would pin the
   combined work to GPL-3.0 exactly. Not planned (own Zoom implementation).

## Recommendation

- New files I write: GPL-2.0-or-later headers, the same as PSX.sv, so any
  of them could go upstream to PSX_MiSTer or to other cores unchanged.
- Release statement: the combined core is GPL-3.0-or-later (because of the
  framework files), as XelaNotPu states for theirs.
- No third-party GPL-3 code is planned. If any is ever used, keep its
  header, list it in the README credits, and keep the release statement as
  above.
- Ask Robert Peip whether the unheaded RTL is meant as GPL-2.0-or-later
  (optional); his answer would replace point 1's section 9 reading.

## Release statement (2026-10-06)

Adopted for the first release: the combined core and its RBF are
GPL-3.0-or-later. `LICENSE` keeps PSX_MiSTer's GPLv2 text and
`LICENSE-GPL3` holds the GPLv3 text. Files I wrote carry
GPL-2.0-or-later headers; files from other projects keep their own
headers.
