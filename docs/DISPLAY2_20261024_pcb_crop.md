# Change 2 (display layer) — the LEFT button now means "show only the PCB"

2026-10-24. Second of three display-layer changes. Firmware flashed with
`ps_fft_dual/strict_load_cores.tcl` (no bitstream, no power cycle, no VDMA register written).

## What changed, and the two corrections that shaped it

`ps_ui/main.c`

1. **The left button (x 8..248, y 366..470) now owns the PCB crop.** It toggles `MB_ZOOM`
   exactly as it always did; what `MB_ZOOM` *does* changed from a 1:1 centre crop to a crop
   framed on the part mask's bounding box. The 1:1 centre crop is **gone**, not hidden
   (the operator's "zoom" was never that picture, and its only user was the label).
   Labels, relabelled because the old ones described the old behaviour:
   `FULL FRAME / TAP FOR / PCB CROP` when off, `PCB CROP / TAP FOR / FULL FRAME` when on.
   **"W" and "Y" are not used, on purpose**: the 5x7 glyph table has no W, no Y and no Z --
   Y renders as an X and W/Z as blanks. Measured on this very button: the first version's
   `FULL VIEW` came out `FULL VIE`, and `PCB ONLY` would have come out `PCB ONLX`. That is
   why the words are FULL FRAME and PCB CROP.

2. **One renderer, one geometry, one zoom path.** The crop is `draw_camera_impl`'s existing
   crop loop with a runtime origin and a Q16 step: `step = max(bw/640, bh/360)` source pixels
   per output pixel, one step for both axes, sampled nearest-neighbour and centred on the
   box. The origin and step come from `part_view_update()`.

3. **The box comes from the registration's own mask** (`LIVE_MASK`, the 160x90 lattice of
   8x8 blocks). Two rules were measured, not guessed:
   * a lattice row/column counts only with **>= 3** mask points (raw min/max let one point at
     (138,7) stretch a 496x264 box to 680x648 -- 2.4x the area, top edge on the belt);
   * the box is the **longest contiguous run** of qualifying lines, not the outermost one.
     On three masks 2 s apart, the outermost rule moved the box's top edge by 80 screen px
     (stray rows crossing the threshold); the longest-run rule held the row and moved the
     columns by 8 px in total.

4. **Hysteresis.** A new framing is accepted only if the proposed origin moved by more than
   5% of the framed span, or the step by more than 5%. `MB_PV_N` counts accepted re-aims,
   so a view that moved on an unchanged box would be visible as a number.

5. **Nothing here may reach the measurement, and the first version did.** With the crop as
   the render pass, the crop's own clip share (13..14 per-mille -- the PCB's white pads are
   blown where the belt is not) crossed the host's 10 per-mille limit, so `g_clip_gate` went
   to 1 and the **comparison refused every opportunity** while the crop was on screen
   (measured: `MB_DIFF_OK = 3`, `MB_DIFF_N` frozen at 18). Fixed by drawing the crop in TWO
   PASSES: a full-frame measuring pass (which fills the clip/mean accumulators and publishes
   `MB_CLIP_PM`, `MB_CLIP_GATE`, `MB_CHANTOT`, `MB_RECOVER`, the saturation bbox) and, on top
   of it, a painting pass that measures nothing. Measured after the fix: `MB_CLIP_PM` = 6 in
   both views, `MB_DIFF_OK` = 1, `MB_DIFF_N` advancing, `AEC_STATE` = 1 and `MB_CAM0_MEAN`
   505..513 in both views.

6. **The camera switch was NOT taken away.** The first revision of this change replaced
   `MB_VIEW`'s camera selection with a display-mode selection and deleted the camera-1
   display path; the delegation corrected it. Reverted: `MB_VIEW` 0/1 still select camera 0 /
   camera 1, and the third button (`x 260..500`) still switches between them. What was added
   is a third state for that button (the difference boxes) -- change 3.

7. **OCM is full, so some dead weight had to go** (the program fills its measured 128 KB and
   the link failed with "section .bss will not fit in region ocm"): `draw_fullscreen()` (the
   full-screen mode withdrawn on 2026-10-18, unreachable since), the `g_zoom == 2` branches
   that called it, the camera-1 copy's 2,560-byte scratch row (`g_cam1_mode` was constant 0),
   and the never-called `draw_camera1_view()`. The renderer is now expanded exactly twice
   (`render_overview` / `render_crop`), not four times.

## The host-side mapping, stated for the next reader

| word | meaning |
|---|---|
| `MB_ZOOM` (147) | 0 = full frame, 1 = PCB crop (the left button, and the operator's "zoom") |
| `MB_VIEW` (86) | 0 = camera 0, 1 = camera 1 (the third button's camera states) |
| `MB_PV_ON` (480) | 1 while the crop is actually drawn |
| `MB_PV_OX/OY` (481/482) | source pixel of output pixel (0,0) |
| `MB_PV_STEP` (483) | Q16 source px per output px |
| `MB_PV_BX0..BY1` (484..487) | the mask box the framing was taken from, source px |
| `MB_PV_MIN` (488) | host: mask points below this = no part (a known-answer test for the fallback) |
| `MB_PV_N` (489) | accepted re-aims since boot |

The crop overrides the camera (`MB_VIEW` = 1 with `MB_ZOOM` = 1 still shows camera 0's crop):
the box belongs to camera 0's mask, so a camera-0 rectangle on camera 1's picture would crop
the wrong field. The zoom word is read BEFORE the store is chosen, so toggling it can never
draw one frame of camera 1 through camera 0's rectangle.

## What the framebuffer read-back proved

Method unchanged from change 1: `dl_fb_dump`-style halt, `DIS_PARK`, dump the scanned buffer,
resume; `ps_ui/dl_pv_check.py` decodes. Structural gates first (header/button colours, panel
background fraction, real picture in the camera area) -- a dump that is not the panel fails
before any decode.

| check | result |
|---|---|
| framing == host recomputation from the mask | bbox (512,416)-(959,663), ox 513, oy 415, step 45875 -- **MATCH** |
| the displayed pixels ARE the part | mapping through the published geometry: 7.60 counts / corr 0.9543; controls +60 px in x 35.08/0.166, +60 px in y 40.00/0.136, no crop 48.28/0.009 |
| no jitter on an unchanged box | three consecutive crop dumps had identical geometry (aims 7) and the best alignment shift was **(+0,+0) px** (residual 10.80 counts, i.e. sensor noise) |
| the framing fills the display | box lands at screen y 1.4..354.3 and x -1.4..637.1 of 0..359 / 0..639 |
| the belt is gone | bright-belt pixels 15.5% -> 8.0%; green (PCB) 11.0% -> 73.6% of the camera area |
| camera switch still works | camera 1 vs camera 0 full frame: 25.60 counts, correlation 0.774 (different fields; see the two PNGs) |
| crop overrides the camera | with `MB_VIEW` = 1 the crop still maps to camera 0 (11.23 counts) not camera 1 (51.31) |
| no-mask fallback | `MB_PV_MIN` = 14000 -> `MB_PV_ON` = 0 and the camera area matches the full-frame view (12.02 counts / corr 0.932) against 60.40 vs the crop |
| the measurement is untouched | `MB_CLIP_PM` 6 in both views, `MB_CLIP_GATE` 0, `MB_DIFF_OK` 1, `MB_DIFF_N` advancing, `AEC_STATE` 1, `MB_CAM0_MEAN` 505..513 |

Evidence files: `ps_ui/dlfb_pv_crop1.raw`, `dlfb_pv_full1.raw`, `dlfb_pv_cam1.raw`,
`dlfb_pv_fallback.raw`, `dlfb_pv_crop1_view.png`, `dlfb_pv_crop1_buttons.png`,
`dlfb_pv_full1_buttons.png`, `dlfb_pv_cam1_view.png`; log
`ps_fft_dual/logs/dl_crop_accept2.log`; geometry `ps_ui/dlpv_words.txt`.

## What remains unverified

1. **The LCD itself.** Every claim above is about the DDR buffer the display VDMA is parked
   on. Whether the panel shows it is not something this agent can observe: a human should
   glance at it. (Same limitation as change 1.)
2. **The touch path.** `MB_TOUCH_OK` = 1 and the PID reads 0x39313100, but `MB_TOUCH_EV` = 0
   and `MB_TAP` = 0 for the whole session -- no touch event has ever been delivered on this
   board. Every state in this change was driven from the host through the mailbox. **Pending
   experiment**: tap the left button and watch `MB_ZOOM` (and `MB_TAP`) change; tap the third
   button and watch `MB_VIEW`.
3. **The scene's box is not still.** The mask's dense block moved by more than the deadband
   between some pairs of dumps in earlier runs (a 136-source-pixel left edge over 3 s), so
   the crop legitimately re-aims. The "no jitter" result above is from a window in which the
   geometry provably did not change; a longer still-scene run would be needed to quote a
   re-aim rate, and this bench does not provide one.
4. **The `render_crop` path with `g_pv_on == 0`** is unreachable from `draw_camera()` (it only
   calls the crop pass when a framing exists) but it is defined behaviour, not tested.
