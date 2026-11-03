# Stage 3 — trade detail for tolerance before comparing

## What changed

| item | before | after |
|---|---|---|
| comparison cell | 8x8 source px (160x90 grid) | **16x16 px (80x45 grid)** |
| cell value | 4 single-pixel green samples | **mean of four 5x5 boxes** (radius 2), centred at +4,+12 in each axis |
| reference side | 4 bilinear `ref_at` calls | **the same four 5x5 boxes through `ref_at`**, so a static scene still computes identical values on both sides |
| background detector | shared the comparison's grid | **keeps its own 8x8 grid** (`bg_cell_mean8`, `g_bggrid`) — `BG_GRID_BASE` is stored at that pitch and its threshold was tuned there |

`cell_mean4()` and `ref_cell()` are the only samplers; everything downstream (the 3x3
blob rule, persistence, the bbox words) is unchanged.

## Why those two numbers — measured, not chosen

`ps_ui/st3_blur_sweep.py` takes a real camera frame, rotates it about the frame centre
by a known angle with edge-clamped bilinear sampling, and applies the comparison's own
arithmetic plus the firmware's own 3x3 blob rule. Surviving cells, limit is 8:

| scheme | 0 deg | 0.16 deg | 0.5 deg | 1 deg | 2 deg |
|---|---|---|---|---|---|
| 8x8 cell, 4 point samples (**today**) | 0 | 41 | 519 | 1174 | 2501 |
| 8x8 cell, 7x7 box at 4 points | 0 | 36 | 268 | 869 | 2155 |
| 16x16 cell, 4 point samples | 0 | 4 | 170 | 303 | 550 |
| **16x16 cell, 5x5 box at 4 points** | 0 | **3** | 52 | 155 | 421 |
| 16x16 cell, full cell mean | 0 | 0 | 30 | 123 | 315 |

with an extra uncompensated **2-pixel vertical residual** at 0 deg:
8x8 4-point **812** | 8x8 box 283 | 16x16 4-point 215 | **16x16 box 37** | full mean 17.

Reading it: **blur alone barely helps** (41 -> 36 at 8x8) because an 8-pixel cell
cannot average over a 2-pixel displacement. The cell size does most of the work
(41 -> 4) and the box does the rest (4 -> 3). The full cell mean is better still but
costs a full frame scan per comparison; four 5x5 boxes are 100 reads per cell.

The two artefacts that had to be removed before any of this was believable: PIL's
`rotate(fillcolor=0)` fills a black wedge that alone read ~150 cells, and `np.roll`
wraps rows. With both fixed the straight image reads **0 cells under every scheme**,
which is the control that says the harness is not manufacturing signal.

## Measured on the board

The board publishes no cell count at the moment, because the part mask is empty — see
below. What was verified on the board is the **refusal path**, which is the behaviour
the task demands when the part cannot be found:

| word | value | meaning |
|---|---|---|
| 366 MB_PART_PTS | 39 | the mask is essentially empty (needed: 400) |
| 367 MB_PART_REF | 0 | the stored baseline has no part in it either |
| 232 MB_REG_STATE | 2 | CANNOT JUDGE, registration not attempted |
| 180 MB_DIFF_OK | **5** | refused: no registration |
| 222 MB_DIFF_VERDICT | **2** | CANNOT JUDGE — never PASS |

## A refusal that was being erased (found while checking the above)

The call site did:

    diff_frame(CAM_BUF);
    ...;
    MB_DIFF_OK = 1;          /* <-- unconditional */

`diff_frame()` sets `MB_DIFF_OK = 4` or `5` on its own refusal paths, and this line
overwrote whichever one it wrote. Measured before the fix, on the empty-mask frame:
`diff_ok = 1`, `reg_state = 2`, `cells = 0xFFFFFFFF`, `verdict = NG` — i.e. "I could
not register this frame" arrived at the host as **NG against an impossible cell
count**. `diff_frame()` now returns 1 only when the comparison really happened and the
caller publishes `MB_DIFF_OK = 1` only then. After the fix the same frame reads
`diff_ok = 5`, `verdict = 2`.

## Why the on-board cell count is not available: the camera's white balance moved

The green-dominance mask is `G - max(R,B) > 12`, an absolute threshold measured on
2026-10-23. Mid-session the sensor's auto white balance moved and the **green channel
dropped 19 counts frame-wide** with red and blue unchanged:

| frame | mean R | mean G | mean B | score p90 | score > 12 | best 16-px block |
|---|---|---|---|---|---|---|
| 20:12 | 112 | 112 | 116 | +28 | 21.6% | +45 |
| 20:38 | 131 | 132 | 133 | +32 | 24.1% | +51 |
| 20:47 | 132 | **113** | 122 | -8 | **0.03%** | **+2** |

At 20:47 no 16x16 block anywhere in the frame has a mean green dominance above +2, so
**no absolute threshold can find the board** — the mask is empty, the registration
correctly refuses, and the firmware answers CANNOT JUDGE for ever. The firmware does
the safe thing; the mask's premise (a colour balance the firmware does not control)
no longer holds.

Two independent checks say this is the scene and not the code: the board publishes 0-39
mask points and `ps_ui/st2_mask_check.py` — an implementation that shares no line of
code with it — returns 1 raw point on the same frame.

The AWB is not under this program's control: nothing in `ps_ui/` writes a white-balance
register, and the OV5640 runs its own AWB loop by default.

A relative rule (`score > median + 12`) would have survived this particular drift —
the frame median sat at -20 in all three states while the board's best block was +71
above it at 20:38 and +22 above it at 20:47 — but that is a change to a threshold the
task specified as absolute, it would need its own calibration, and a failed stage is
not the place to start one.

## Acceptance status

* "rotate the board a fraction of a degree to a couple of degrees and show
  MB_DIFF_CELLS drops substantially versus 309..403" — **NOT DONE on the board.**
  Measured offline instead, with the table above: at the same 0.16 deg the count goes
  from 41 (today's scheme, blob-filtered) to 3, and a 2-pixel residual from 812 to 37.
* "a good board must still pass" — **NOT DEMONSTRATED on the board.** The straight board
  reads 0 cells in the offline harness for every scheme, but the board itself cannot
  compare anything while the mask is empty.
* "do not simply make everything pass; report what a deliberately rotated board gives"
  — reported: 0.5 deg and worse still fail, by design.

## What would settle it

1. Fix the camera's white balance (manual WB, or re-derive the green-dominance
   threshold under the balance that will actually be used), then confirm
   `MB_PART_PTS` is back to ~1,500 and `MB_REG_STATE` is 1.
2. With the board straight: `MB_DIFF_CELLS` should read 0..8.
3. Rotate the board 0.16 deg and read again (expected a few cells by the table above),
   then 1 deg (expected well over the limit).
