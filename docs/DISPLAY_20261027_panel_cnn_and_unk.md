# Panel change 2026-10-27: retire the CNN line, make GATE UNK self-explaining

Firmware-only change in `ps_ui/main.c` (free functions `text()`/`glyph()` + `draw_panel`).
No verdict logic, no debounce, no comparison, no tolerance map, no registration, no AEC,
no mailbox layout change. Written BEFORE the edit (claim-discipline R4).

## Hypothesis

H1: the panel's `CNN ...` rows are the only place the accelerator's self-test result
reaches a human, and they read `CNN PASS/8 0` (plus `CNN ARG REGS BAD` when
`g_cnn_ok == 0`) on a board whose CNN never passed its known-answer test. Retiring the
rows removes the "0", leaves `MB_CNN_*` (124..130), `cnn_drv.c` and the `cnn_infer()`
call untouched, and changes nothing about the verdict.

H2: the local gate's third answer (`g_local_verdict == 2`, drawn `UNK`) is produced by
voters outside the panel: camera 0 (`g_aec_state == 3` or `g_cam0_meas_n == 0`),
camera 1 (`g_cam1_ptr_bad`, `g_cam1_aec_state == 3`, `g_cam1_mean_pm` outside
`AEC_DARK_PM..AEC_BRIGHT_PM`), and the diff arm (`MB_READY != 1`, no baseline,
background/photometry refusals). Naming the first voter's own reason under the GATE row
turns "UNK" into a statement the operator can act on.

## Predictions (falsifiable, each with a check that needs no board unless marked)

| # | predication | check |
|---|---|---|
| P1 | build prints exactly the same FOUR pre-existing warnings, and `check_layout.py` reports `0 collisions` | `ps_ui/build.ps1` |
| P2 | the word-131 literal-offset clash the layout check reports (KNOWN) DISAPPEARS, because the panel was its only reader (`R32(MAILBOX + 131u*4u)`); expect `5 literal indices, 1 shared` -> `4, 0` | `ps_ui/build.ps1` output |
| P3 | no draw-path string contains `CNN PASS`, `CNN SELF-TEST`, `CNN ARG REGS BAD`, `CNN SELFTEST TIMEOUT`, `CNN C`, `L0`, `L1` any more; the panel carries `CNN NOT IN PATH` once | `grep` on the draw path |
| P4 | every character of every new/modified string is in the font table `IDX` (`0123456789:.%-/ ABCDEFGHIJKLMNOPQRSTUVXY`); a missing glyph draws as a BLANK, so glyph coverage is checked by SIMULATING `glyph()` from the table itself, not by reading the string | `dl/panel_text_check.py` (new, offline) |
| P5 | the panel's lowest drawn row stays < 480 in every top-verdict state (the two CNN rows freed 24 px, the cause row costs 11 px, net -1 px from the CNN block down) | same script: y arithmetic of `draw_panel` |
| P6 | with `g_local_verdict == 2` and `g_aec_state == 2`, the row 11 px under GATE reads `AEC ADJ`; with `== 3`, `AEC STUCK`; with `== 1` and `MB_READY != 1`, `NOT READY`; with everything else quiet, `SEE DIFF` | same script: cause ladder truth table |
| P7 | ON THE BOARD after `strict_load_cores.tcl`: a halted frame dump of the scanned UI buffer contains the exact FONT bitmaps of `CNN NOT IN PATH` at the panel coordinates, and the operator reads that line off the panel | `dl_fb_dump_20261024.tcl <tag>` + `dl/panel_text_check.py --decode` + operator |

## Falsification

- Any new string containing a glyph outside `IDX` (reads as a blank) => P4 fails, the
  change is wrong regardless of the build result.
- The build's warning count changing => the edit touched something it should not.
- The mailbox collision count staying at 1 with word 131 still shared => the old CNN row
  is still being drawn somewhere.
- On the board: the panel still showing `CNN PASS` or a `0` beside it => the flashed image
  is not this source (the stale-.bin trap), not a display question.

## Measured offline, 2026-10-27 (before any board access)

Tooling: `dl/panel_text_check.py` (new), which reads `FONT`/`IDX` out of `main.c` and
`ps_ui/dlfb_final_panel.png`, a panel dumped from the board on 2026-10-24
(`ps_fft_dual/dl_fb_dump_20261024.tcl` -> `ps_ui/dlfb_final.raw`).

1. **Build** (`ps_ui/build.ps1`): exit 0, **four warnings, the same four** (main.c:913,
   1214, 11631, 1014), `mailbox: 394 MB_* words, 394 distinct, 0 collisions`,
   `mailbox: 4 indices written by literal offset, 0 also claimed by an MB_* name`
   (was 5 and 1 -- the retired row was the last literal-offset reader of word 131, the
   KNOWN clash the layout check has been reporting), `all layout checks pass`.
   ELF 198,592 bytes.
2. **Glyph coverage** (`--` default mode): all 31 `text()` literals in the draw path use
   only glyphs the table carries, and every one fits inside the 160-px panel.  The new
   strings, in ink columns: `CNN NOT IN PATH` +8..+96, `CAM1 AEC STUCK` +8..+90,
   `CAM1 NO FRAME` +8..+84, `CAM1 NO DATA` +8..+78, `CAM0 NO DATA` +8..+78, `CAM1 LIGHT`
   +8..+66, `AEC STUCK` +8..+60, `NOT READY` +8..+60, `SEE DIFF` +8..+54, `AEC IDLE`
   +8..+54, `AEC ADJ` +8..+48, `NO REF` +8..+42.
3. **Layout arithmetic** (`--layout`, summed out of `draw_panel`): the lowest drawn row is
   y=394 (host PASS/FAIL), glyph bottom 401, in a 480-row panel.  Every top-verdict state
   fits.
4. **Cause ladder** (`--cause`, extracted from the C source and evaluated): 11 scenarios,
   each drawing the intended token -- latched camera 0 `AEC STUCK`, latched camera 1
   `CAM1 AEC STUCK`, unverified store `CAM1 NO FRAME`, never measured `CAM1 NO DATA`, out
   of band `CAM1 LIGHT`, camera 0 with no channels `CAM0 NO DATA`, the retake case
   `AEC ADJ`, not started `AEC IDLE`, still moving `NOT READY`, no baseline `NO REF`,
   everything else `SEE DIFF`.
5. **Known-answer decode of the real 2026-10-24 frame** (`--decode`, exact 5x7 template
   match against the pixels, not against the code).  The host was not attached for that
   dump, so the layout is the `no host` branch:

   | string | found at | colour | source offset |
   |---|---|---|---|
   | `CLIP` | x=648, y=78 | (245,166,35) C_UNC | PAN_X+8 |
   | `PCT LIM` | x=706, y=78 | (127,163,184) C_DIM | PAN_X+66 |
   | `GATE` | x=648, y=89 | (127,163,184) C_DIM | PAN_X+8 |
   | `HOST` | x=702, y=89 | (127,163,184) C_DIM | PAN_X+62 |
   | `RUN` | x=648, y=112 | (127,163,184) C_DIM | PAN_X+8 |
   | `CAL RMS 0.137 PX` | x=648, y=123 | (46,204,113) C_OK | PAN_X+8 |
   | `CNN SELF-TEST` | x=648, y=134 | (245,166,35) C_UNC | PAN_X+8 |
   | `CNN PASS/8` | x=648, y=146 | (127,163,184) C_DIM | PAN_X+8 |
   | `CNN NOT IN PATH` | not found | -- | (old build, as expected) |

   The decoder reproducing every x offset and colour from the source is what makes it a
   usable instrument; the y values then confirm the row arithmetic (78 + 11 = 89 gate,
   + 11 + 12 = 112 run, + 11 = 123 CAL RMS, + 11 = 134 CNN row 1, + 12 = 146 CNN row 2).
   The operator's "CNN PASS/G 0" is this last row: `CNN PASS/8` in dim grey with the
   one-digit count `0` at PAN_X+76 -- the table's `8` at 5x7 reads as a `G` at bench
   distance, which is itself an argument for the change.

## Pre-registered prediction for the flash (tonight's session)

Same panel code above the CLIP row, so with the new image:

- no host attached: cause row (only when the gate is UNK) at y=100, bar 111, RUN 123,
  CAL RMS 134, **`CNN NOT IN PATH` at x=648, y=145**, colour (127,163,184);
- host attached and PASS/FAIL: add 16 px to all of those -> **x=648, y=161**.

Check: `xsdb ps_fft_dual/dl_fb_dump_20261024.tcl after`, then
`python dl/panel_text_check.py --decode ps_ui/dlfb_after.raw`.  Finding `CNN NOT IN PATH`
at y=145 (or 161 with a host) in C_DIM and NOT finding `CNN PASS/8` is the acceptance;
finding the old string instead means the board is still running the previous image.


## Not changing

`MB_CNN_OK..MB_CNN_CYC` (124..130), `cnn_drv.c`, `cnn_selftest_run()`, `cnn_infer()`,
`if (g_cnn_pass != 0u && (frames % CNN_EVERY) == 0u)` at main.c:14681, the debounce at
main.c:14382-14416, `v0/v1/vd` and the combination rule, `AEC`, `MB_READY`, all mailbox
indices. The report will say: the accelerator exists in the fabric but is not in the
decision path.
