# Change 3 (display layer) — the third button cycles three states, the third is the diff boxes

2026-10-24. Last of three display-layer changes. Firmware flashed with
`ps_fft_dual/strict_load_cores.tcl` (no bitstream, no power cycle, no VDMA register written).

## What changed

`ps_ui/main.c`

1. **The third button (x 260..500) cycles `MB_VIEW` 0 -> 1 -> 2 -> 0** and its caption names
   the state it is in:
   * `0` **FULL L** — camera 0, full frame (the camera switch this button has always done)
   * `1` **FULL R** — camera 1, full frame (the same switch, other camera)
   * `2` **DIFF CELLS** — camera 0's full frame with the comparison's cells outlined
   The caption is "DIFF CELLS" and not "DIFF BOX" because the glyph table's `X` entry holds a
   **W** bitmap and its `Y` entry holds the X (measured: "DIFF BOX" rendered "DIFF BOW").
   Its sub-lines are `TAP TO CHANGE` / `THE PANEL MODE`.
2. **The host drives the same three values.** `MB_VIEW` (86): 0/1 keep their old camera
   meaning; 2 is the new state. A value outside 0..2 is ignored (an unwritten word reads
   0xFFFFFFFF).
3. **The diff-box view draws the comparison's own flags**, not a recomputation: every cell
   with `g_dflag != 0` gets a 2-pixel magenta outline of its 8x8 screen footprint (comparison
   cell = 16x16 source px = 8x8 output px in the overview; see the mapping in
   `draw_blob_box`). Magenta rather than red because red already means two things on this
   screen. The number drawn is published as `MB_DIFF_DRAWN` (word 490).
4. **The published count gates the draw.** `ref_take()` publishes `MB_DIFF_CELLS = 0` when a
   new reference is taken but does not clear `g_dflag`; drawing the array alone showed
   **18 stale boxes** after a fresh reference while the panel and the host both said 0 cells
   (measured this session). The view now draws nothing for 0 (and for 0xFFFFFFFF, "refused")
   and never paints more cells than the number says.
5. **In the PCB crop the boxes are suppressed** (`MB_DIFF_DRAWN` = 0): the crop's geometry is
   not the overview's, so an overview coordinate would land somewhere it was not measured.
   Same rule and same reason as `draw_blob_box()`.
6. **The regression from the first revision is fixed here as well as in change 2.** This
   change's original brief said "make ONE button cycle full -> part -> diff"; implemented
   literally by the agent, that took the camera switch away from the operator and was
   reported immediately. The delegation corrected it: the third button keeps the camera
   switch and gains the diff state, and the PCB crop moved to the LEFT button (`MB_ZOOM`).
   **The regression was caused by this agent following the brief literally**; the brief was
   incomplete too, and the correction came from the delegating agent after the operator
   noticed.

## The mapping, stated for the next reader

| word | value | display |
|---|---|---|
| `MB_ZOOM` (147) | 0 | full frame of the camera `MB_VIEW` names |
| | 1 | PCB crop (camera 0 only; overrides `MB_VIEW`) |
| `MB_VIEW` (86) | 0 | full frame, camera 0 ("FULL L") |
| | 1 | full frame, camera 1 ("FULL R") |
| | 2 | full frame, camera 0 + magenta diff cells ("DIFF CELLS") |
| `MB_DIFF_DRAWN` (490) | n | comparison cells the last diff render painted |

## What the framebuffer read-back proved

Same method as changes 1 and 2; `ps_ui/dl_diff_check.py` decodes and the structural gates run
first.

| check | result |
|---|---|
| structural gates on all six dumps | header/button colours exact, panel background 88.5..88.7%, camera area is a real picture |
| state 1 is camera 1 | camera 0 vs camera 1: 26.45 counts, correlation 0.7539 (different fields; PNGs kept) |
| state 2 draws the cells | 48 magenta pixels = exactly **one** 8x8 outline (2 px thick, 48 px), on the 8-pixel grid, at cell (46,26); `MB_DIFF_DRAWN` = 1 at that instant |
| the box is an overlay, not another render | outside the box, state 2 vs state 0 = 11.22 counts against a measured session drift floor of 11.08 counts (camera 0 vs camera 0, minutes apart) |
| the crop suppresses the boxes | 0 magenta pixels, `MB_DIFF_DRAWN` = 0 |
| a fresh reference removes them | 0 magenta pixels, `MB_DIFF_DRAWN` = 0, `MB_DIFF_CELLS` = 0 |
| captions | decoded from the framebuffer's own glyph table: `FULL L`, `FULL R`, `DIFF CELLS`, sub-line `TAP TO CHANGE` / `THE PANEL MODE`; the left button still reads `FULL FRAME / TAP FOR / PCB CROP` |

The positive case needed cells, and a still scene with a fresh reference has none: the run
waited for `MB_DIFF_CELLS` to become positive and caught it at 1. Earlier in the session the
same view was also seen with 1185 and then 3600 cells (the whole 80x45 grid) while the scene
drifted against a stale reference; those runs were on the build before the count gate, and
that gate changes nothing for a positive count.

Evidence: `ps_ui/dlfb_db0.raw`, `db1.raw`, `db2.raw`, `db0b.raw`, `db2crop.raw`,
`db2fresh.raw`; `ps_ui/dlfb_db2_box_zoom.png` (the box, 8x enlarged),
`ps_ui/dlfb_db0_buttons.png`, `dlfb_db1_buttons.png`, `dlfb_db2_buttons.png` (the captions);
`ps_ui/dldiff_words.txt`; log `ps_fft_dual/logs/dl_diff_accept3.log`.

## What remains unverified

1. **The LCD and the touch panel.** Every state was driven from the host through `MB_VIEW`;
   `MB_TOUCH_OK` = 1 (PID 0x39313100) but `MB_TOUCH_EV` = 0 and `MB_TAP` = 0 for the whole
   session, so the tap path is **unverified**. Exact experiment: tap the third button once
   and watch `MB_VIEW` go 0 -> 1 -> 2 -> 0 and `MB_TAP` increment; tap the left button and
   watch `MB_ZOOM` toggle. If neither moves, the touch driver -- not these buttons -- is the
   subject.
2. **A mid-range diff state.** This session could only produce 0 cells (fresh reference) or
   hundreds (stale reference). The view's behaviour at, say, 30 cells is inferred from the
   same loop, not measured.
3. **Cell semantics.** The boxes are the comparison's cells; whether a *particular* lit cell
   is contamination on the part or a registration artefact is not something this view
   decides. It shows where the comparison disagreed, nothing more.
