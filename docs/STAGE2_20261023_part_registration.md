# Stage 2 — register on the part, not on the frame

## The defect being fixed

`reg_search()` minimised its match error over **every** lattice point. On this bench
the belt, the floor and the wall are ~79% of the lattice, so the number it minimised
was dominated by things that never move: it reported "the scene did not move" while
the part did (measured earlier: the board's bounding box moved +4 px in y while the
search reported dy = 0.38 px and compensated nothing).

## What changed

* `part_green()` — green dominance, `score = G - max(R,B)`, 2x2 samples at +2,+5 inside
  each 8x8 block, threshold 12. Measured on this bench: board +17.0, belt −15.7,
  floor −51.9.
* `part_masks()` — builds the mask on the lattice, **eroded one lattice step** (3x3
  minimum, a 24-source-pixel margin) so no cell straddles the mask boundary, where a
  one-pixel placement error would become a large score.
* `reg_score()` — now scores a point only when the **live** mask says this lattice
  point is part **and** the **baseline** mask says the point it maps to is part. The
  search structure (coarse translation, trial scales, refine, parabola) is untouched.
* `MB_PART_PTS/REF/USED` (366/367/368) publish the mask area and the support the
  winning registration actually used.
* `reg_search()` refuses (`g_reg_ok = 2`) when either mask is below `PART_MIN_PTS` =
  400 lattice points = 2.8% of the frame; `diff_frame()` already turns that into
  `MB_DIFF_OK = 5` and `diff_verdict()` into CANNOT JUDGE, never PASS.
* Coarse reach widened from 48 to 128 half-res pixels (step 8 -> 16, mid +-8 -> +-12):
  ±7.4 mm was one hand placement away from saturating, and the masked search made the
  wider sweep *cheaper* than the old narrow unmasked one (289 offsets x ~92 points
  against 169 x 900).

## Measured on the board

| quantity | value |
|---|---|
| `MB_PART_PTS` / `MB_PART_REF` | 1,486 / 1,529 lattice points (≈9.5% of the frame, 95,000 px) |
| `MB_PART_USED` | 931 points scored by the winning search |
| static scene | dx = **0.00 px**, dy = **0.00 px**, scale 255, match error 5.1 levels, state 1 |
| search cost | 39–43 ms (13–14 M ticks), run once per 16 frames |

**The mask arithmetic was validated against an independent implementation**, not
against itself: `ps_ui/st2_mask_check.py` reproduces `part_masks()` from the half
description and returns 1,256 points on a dumped frame where the board publishes
1,386–1,534 (raw green 3,379 = 23.5% before erosion). Score inside the mask +29.0,
outside −16.3. `st2_mask_overlay.png` shows the mask sitting on the PCB.

## The acceptance test, and what it does NOT cover

The task asks for the board to be moved a few centimetres and the reported dx/dy to
track it, with the board's own bbox shift from dumped frames as an independent
measurement. **This session could not ask the operator to move the board** (a subagent
has no human interaction), so that experiment is **NOT DONE**.

What was done instead is a controlled test with a **known** displacement
(`ps_ui/st2_track_test.py`): a real frame is taken, the masked part is moved by a
known number of source pixels, the vacated area is filled with that row's own median,
and every other pixel is byte-identical — i.e. the part moves and the background does
not. Both statistics are then evaluated on the same pair:

| part moved by | FULL (old) | MASK (new) |
|---|---|---|
| +40 source px | **0 px** (err 65/16) | **+40 px** exactly (err 0) |
| +96 source px | **0 px** (err 71/16) | **+96 px** exactly (err 0) |
| +176 source px | **0 px** (err 86/16) | **+176 px** exactly (err 0) |

That is the defect and the fix with a known answer: the old statistic reports *no
displacement* for three different real displacements, and the masked one recovers each
exactly.

**It is not the firmware's own search on a physically moved board**, and it must not
be reported as such. What ties this implementation to the firmware's is the mask-count
agreement above and the static-scene result (dx = dy = 0.00 px against a known truth
of zero).

## Also found and fixed by that test

The point-count floor had an absolute clamp of 48. With a 923-point mask, stride 4
sees ~57 points, so the clamp demanded 84% of them and the coarse stage answered "not
measured" for a 176-pixel part move — while the same metric located a 96-pixel move
exactly. **That is a silent refusal of a real answer**, found only because the test
had a known truth. The clamp is now 16 (the relative floor `mask_pts / (2*stride^2)`
is what actually protects the statistic; `PART_MIN_PTS` already refuses tiny masks).

## Not verified

* The physical board move (operator unavailable): dx/dy tracking a hand-placed part is
  untested on the board. Exact instruction for whoever can do it:
  take a baseline with `MB_CMD = 9`, `mrd` dump the live store, slide the board
  1–2 cm, then read `MB_ALIGN_DX/DY` (226/227, 1/16 source px, signed) and compare
  against the green-mask centroid shift between the two dumps.
* The refusal path (`PART_MIN_PTS`) has not been exercised on the board: nothing
  available in this session removes the part from the view.
