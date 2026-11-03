# Change 1 (display layer) — the panel's fps field is no longer gated on the host

2026-10-24. Part of a three-change display-layer sequence; this document covers change 1 only.
No bitstream, no power cycle, no VDMA register write; firmware flashed with
`ps_fft_dual/strict_load_cores.tcl`.

## What changed

`ps_ui/main.c`

- `draw_panel()` at main.c:7523 — the frame-rate field was
  `uint32_t fpsx10 = valid ? mb[MB_FPSX10] : 0u;` where
  `valid = (mb[MB_MAGIC] == MB_VALID)` requires a HOST-written magic word.
  `MB_FPSX10` is written by THIS program (main.c:9364..9377, once a second, from the
  global timer and `MB_PS_FRAMES`), so the device's own frame rate was hidden whenever
  no host was attached.
- Now: `uint32_t fpsx10 = mb[MB_FPSX10];` with an out-of-range clamp, and a comment at
  that line stating WHY the two groups of panel fields differ:
  host-sourced words (`MB_VERDICT`, `MB_TOTAL`, `MB_NG`, `MB_UNSURE`, `MB_ALARM`,
  `MB_CLIP_LIM`) have no meaning without the host and stay gated on `MB_MAGIC`;
  device-sourced values (the fps word) are measurements this board made and must not
  depend on a second process being attached.
- The host-sourced fields are untouched: same `valid` expression, same ternaries,
  same pixels when a host IS attached.

Nothing else in the file changed. The measurement path (`draw_camera_impl`'s
accumulators, `diff_frame`, the registration, the averaging, the classifier) is not
touched by this change.

## What the framebuffer read-back proved

Method: `ps_fft_dual/dl_fb_dump_20261024.tcl` halts the core, reads `DIS_PARK`
(0x43010000+0x28) to learn which of the two UI buffers the display is scanning, dumps that
buffer (1 152 000 bytes) and resumes. `ps_ui/dl_panel_decode.py` decodes the dump:
the glyphs are matched against the panel's own 5x7 `FONT` table from main.c, so the digits
are a statement about pixels, not about the code that was supposed to draw them.

Structural gates (a dump that is not the panel must fail rather than decode):
header bar colour (15,111,122) exact, button fill (22,40,52) exact, 88.6% of the panel
area is the panel background, the camera area holds no panel-background pixel, and the
header pixel differs from its RGB-swapped value (the B,G,R store order is confirmed, not
assumed).

| dump | MB_FPSX10 | host attached? | fps field pixels |
|---|---|---|---|
| `before1` (previous firmware) | 70 (7.0 fps) | **no** — MB_MAGIC read 0x8FCFF95F | `00.0` at y=202 |
| `after1` (this build) | 70 (7.0 fps) | **no** — MB_MAGIC read 0x8FCFF95F | `07.0` at y=202 |

That pair is the point: the same mailbox word, the same absence of a host, and the field
moved from `00.0` to `07.0`. The unmatched "00.0" is also the negative control — it is
absent after the change.

The host fields are still gated, proven at the pixel level rather than by reading the
source: the TOTAL field reads `000000` while `MB_TOTAL` holds 0xE175CAFB. `text_num` prints
six digits, so an ungated TOTAL would read `769467`. The gate is therefore intact for the
host group and gone for the fps field, which is exactly the change.

Evidence files: `ps_ui/dlfb_before1.raw`, `ps_ui/dlfb_after1.raw`, the two
`*_fps.png` crops (a 5x enlargement of the field), `ps_ui/dlfb_after1_panel.png`.

## What remains unverified

1. **The panel as a human sees it.** The read-back is DDR, not the LCD. The digits are
   proven to be in the buffer the display VDMA is parked on; whether the LCD shows them
   is not something this agent can observe. A human should glance at the panel once.
2. **The number's calibration.** `07.0` is what the firmware computes from the global
   timer and `MB_PS_FRAMES`; it is not compared here against an external wall clock for
   this boot. The cross-check that it tracks the loop will come from change 2, where the
   same field should DROP when the renderer gets more expensive (measured reading, not an
   assumption).
3. **A host-attached regression run.** The gate for host fields is unchanged code, and the
   pixel evidence above shows it still suppresses garbage, but no host was attached for
   this session, so "the panel still shows a real verdict when a host is present" is
   unverified in this build.
