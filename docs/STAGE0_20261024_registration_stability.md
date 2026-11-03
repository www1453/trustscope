# Stage 0 (2026-10-24) — the registration stops solving from scratch

**Result in one line: on a scene nobody touched, 84 consecutive comparisons after fresh
references now publish ONE transform (angle 0.00 deg, dx 0.00 px, dy 0.00 px, scale
1.0000) where the previous build published five different answers in eleven attempts,
including 4.00 degrees, 14 pixels and a scale of 1.0625. The cell count fell from 0..27 to
0..12, so the registration half of the acceptance is met; the cell count is NOT yet
bounded below the 8-cell limit, because the remaining variation is the rolling-shutter row
bar, which is Stage 2/Stage 4's job and not this one's.**

## The defect, measured before touching anything

`ps_fft_dual/st0_sample_20261024.tcl` (read-only, 400 ms sampling, 20 s) on the old build
`TSC1/49CF0B22`, static scene, part in view, `MB_READY = 1` throughout. Every attempt:

| t (ms) | diff_n | angle (deg) | dx (px) | dy (px) | scale | match err (lv) | cells |
|---|---|---|---|---|---|---|---|
| 139 | 188 | −0.11 | 0.00 | −0.13 | 1.0000 | 3.50 | 0 |
| 1849 | 189 | −0.10 | −0.38 | 1.13 | 1.0078 | 5.25 | 0 |
| 4057 | 190 | −0.15 | −0.13 | −2.25 | 0.9844 | 6.63 | 0 |
| 6359 | 191 | **+3.95** | **14.00** | **−16.13** | 1.0000 | 10.31 | 8 |
| 8633 | 192 | −0.10 | 0.25 | 0.88 | 1.0039 | 7.69 | 5 |
| 10914 | 193 | **+0.60** | **8.00** | **−20.00** | **0.9023** | 11.38 | 27 |
| 15464 | 194 | −0.10 | 0.00 | 0.13 | 1.0039 | 4.00 | 0 |
| 18298 | 195 | **+4.00** | **4.00** | 2.00 | **1.0625** | 12.06 | 0 |
| 20535 | 196 | −0.05 | 0.13 | 0.25 | 1.0000 | 8.56 | 0 |
| 25011 | 197 | −0.05 | −0.38 | 0.00 | 1.0039 | 4.13 | 0 |
| 27286 | 198 | +0.25 | −0.25 | 0.00 | 1.0000 | 7.00 | 0 |

Raw log: `dl/st0_before_20261024.log`. Two further attempts (after diff_n 193 and 196)
refused with state 2 and published `angle −0.80` next to `dx 8.00 px, dy −20.00 px` — three
numbers from three different transforms, which is a second defect fixed below.

The `dl/*.log` files are `.gitignore`d in this repository, so the logs themselves are not in
the commit; every number quoted from them is transcribed in this document, and each is
reproduced by the script named above it.

## Why it wandered: the search was asked for a resolution the frame does not have

`ps_ui/st6_warm_cal.py` (new) drives the same arithmetic over a real part frame
(`ps_ui/st2_A_live.raw`) at a known truth and measures what a misalignment costs, in
1/16 grey level — word 203's own unit:

| misalignment | cost (`err16`) |
|---|---|
| 0.1 degree | +6 .. +11 (0.4 .. 0.7 level) |
| 0.2 degree | +16 .. +24 |
| 0.5 degree | +42 .. +61 |
| 1 half-res px | +54 .. +92 |
| 1 unit of 1/256 scale | +25 .. +35 |

and the SAME transform re-measured on consecutive frames of the static scene reads 56, 84,
106, 123, 64, 137, 66, 112 — an up-to-80-unit frame-to-frame term, ten times the 0.1-degree
step. That term is not independent noise; it is the rolling-shutter row bar
(`dl/STAGE1_20261023_gate.md`), which shifts the whole error surface. A global argmin over
five dimensions is free to land anywhere on that surface, and it did.

## What changed (`ps_ui/main.c`)

| line | item |
|---|---|
| 2580–2760 | the Stage 0 block: the constants, the held-answer state, `reg_restore_hold()`, `reg_refuse()`, `reg_outside_better()`, `reg_refine3()` |
| 2688 | `reg_refine3()` — the final 3x3 sub-pixel refinement, now the ONE implementation, shared by the cold search and the local window |
| 2715 | `reg_warm_search()` — translation ±6 half-res px, angle ±0.40 deg, scale ±2/256, then the same 3x3 and both parabolas |
| 2979 | `reg_search()` entry now restores the held transform, and every refusal goes through `reg_refuse()` |
| 3080 | the held answer is scored on every frame and is a candidate |
| 3092 | the local window is searched first; a candidate must gain one grey level to be adopted |
| 3280 | the gate: no candidate is published unless it gains — `REG_WARM_MARGIN` (1 level) if it is near, `REG_JUMP_MARGIN` (2 levels) if it is far |
| 3366 | `ref_take()` seeds the held answer with the identity, because a fresh reference IS the current placement |
| 3465 | the seven audit words 393–399 and the six window words 234–239 are published |

Design rules that are load-bearing and must not be "cleaned up":

1. **A fresh reference seeds the identity.** The reference is copied from a live frame, so
   at that instant the correct transform is exactly the identity. Making it the held
   answer turns that fact into a constraint on the first search after every baseline.
2. **Adoption requires a measured gain.** `REG_WARM_MARGIN` is one grey level: far above
   the finest real step (0.4..0.7 level), far below a one-pixel misalignment (3.4..5.8
   levels). It suppresses step chatter without suppressing tracking.
3. **A window's edge is not evidence by itself.** `reg_outside_better()` asks whether the
   error is still falling one step further out. Applying the cold search's "saturated
   window" rule literally here made the local search NEVER answer — measured 0 of 24
   comparisons, `NWARM` stayed 0 — because the angle surface is flat to within the row bar
   and the noise minimum sits on an edge about half the time.
4. **The held answer is held only while it fits.** Above `REG_HOLD_LIM` (15 levels,
   against a worst measured aligned value of 8.6 and an unusable limit of 30) the state is
   3, UNSTABLE, and the comparison refuses. That state exists so a disagreement between
   two measurements is never published as an answer.

## The acceptance measurement, and how it was taken

`ps_fft_dual/st0_accept2_20261024.tcl`: write `MB_CMD = 9` (a fresh reference from a live
store), wait 3 s, then sample every 400 ms for 38 s, printing `MB_DIFF_N` (word 189) with
`MB_DIFF_CELLS`, `MB_REG_ANGLE100`, `MB_DIFF_DX/DY`, `MB_REG_SCALE`, `MB_REG_STATE`, plus
the new decision words. **The cadence has to be stated, because it limits what the test
can show:** the comparison runs once per 16 loops, i.e. **one attempt per 2.2–2.9 s** at
6.8 fps. Ten *independent* readings therefore need 25–30 s, not 10 s; sampling faster than
the cadence only repeats one comparison. Both are reported: the raw 400 ms sequence (95
samples, so each comparison appears 6–10 times, unchanged — that is itself the test that a
reading is stable within a comparison) and the distinct comparisons below.

Final build, run C (`dl/st0_after5_20261024.log`), first twelve of 28 attempts:

| t (ms) | diff_n | mode | angle (deg) | dx (px) | dy (px) | scale | err (lv) | held err | window err | cells |
|---|---|---|---|---|---|---|---|---|---|---|
| 331 | 39 | 2 hold | 0.00 | 0.00 | 0.00 | 1.0000 | 3.94 | 63 | 61 | 0 |
| 1068 | 40 | 2 hold | 0.00 | 0.00 | 0.00 | 1.0000 | 10.25 | 164 | 164 | 0 |
| 3958 | 41 | 2 hold | 0.00 | 0.00 | 0.00 | 1.0000 | 3.63 | 58 | 59 | 0 |
| 6141 | 42 | 2 hold | 0.00 | 0.00 | 0.00 | 1.0000 | 6.81 | 109 | 109 | 0 |
| 8997 | 43 | 2 hold | 0.00 | 0.00 | 0.00 | 1.0000 | 9.06 | 145 | 144 | 0 |
| 11138 | 44 | 2 hold | 0.00 | 0.00 | 0.00 | 1.0000 | 3.38 | 54 | 53 | 0 |
| 14139 | 45 | 2 hold | 0.00 | 0.00 | 0.00 | 1.0000 | 9.25 | 148 | 149 | 0 |
| 16348 | 46 | 2 hold | 0.00 | 0.00 | 0.00 | 1.0000 | 6.81 | 109 | 108 | 0 |
| 19302 | 47 | 2 hold | 0.00 | 0.00 | 0.00 | 1.0000 | 3.50 | 56 | 57 | 0 |
| 21552 | 48 | 2 hold | 0.00 | 0.00 | 0.00 | 1.0000 | 8.44 | 135 | 135 | 0 |
| 23742 | 49 | 2 hold | 0.00 | 0.00 | 0.00 | 1.0000 | 8.88 | 142 | 142 | 0 |
| 26716 | 50 | 2 hold | 0.00 | 0.00 | 0.00 | 1.0000 | 4.06 | 65 | 66 | 0 |

All 28: angle 0.00, dx 0.00, dy 0.00, scale 1.0000, state 1, mode 2 (held). Cells 0 in 23,
then 4, 5, 8, 8, 12 as the room's contents drifted late in the run.

**Three independent runs, three fresh references, 84 comparisons, zero transform
variation:**

| run | log | comparisons | transform values | cells | refusals |
|---|---|---|---|---|---|
| A | `dl/st0_after2_20261024.log` | 27 | one value (0/0/0/1.0000) | 0 ×26, 6 ×1 | 1 attempt |
| B | `dl/st0_after3_20261024.log` | 29 | one value | 0 ×29 | 0 |
| C | `dl/st0_after5_20261024.log` | 28 | one value | 0 ×23, 4, 5, 8×2, 12 | 0 |

Acceptance as specified ("every reading within 0.2 deg and 2 px, cells small"): **met for
the transform** — the spread is 0.00 deg and 0.00 px, not merely small. **Not fully met for
the cell count**: 4 of 84 comparisons read 8..12 cells, which is at or above the 8-cell
limit, on a scene nothing was touching.

## What the row bar still does, and why it is not Stage 0's job

The `held err` and `window err` columns above are the same transform measured twice on the
same frame; they differ by at most 2 units, so the local surface is smooth and the search is
now measuring something real. But the `err` column still swings 3.4..10.3 levels for that
one transform, because the picture itself changes frame to frame. That is the modulation
`dl/STAGE1_20261023_gate.md` measured at ±10 counts across whole rows. Averaging frames
(Stage 2) and a local threshold (Stage 4) are what attack it.

## A second defect found in the "before" data, and fixed

A refusal used to publish a **mix**: `angle −0.80` (from the stage that gave up, because
`reg_coeffs()` writes `g_reg_th100` as a side effect) next to `dx 8.00 px, dy −20.00 px`
(stale, from an attempt two frames earlier). Every refusal now goes through
`reg_refuse()` (`main.c:2779`), which restores the whole held transform and sets state 2, so
"could not judge this frame" publishes one consistent (last usable) transform. Verified on
the final build: the refusal row in run A's log reads angle 0.00, dx 0.00, dy 0.00, scale
1.0000, err "not measured" — one transform, one state.

## Not verified, with the exact experiment

1. **A physically moved part.** Nothing in this session can move it. Experiment: take a
   reference (`MB_CMD = 9`), read `MB_REG_ANGLE/DX/DY` (words 385/201/202) and
   `MB_REG_MODE` (393) for 10 comparisons, then slide the part 1–2 cm and repeat. Expected:
   `MB_REG_MODE` = 4 or 1 with a new answer, `MB_REG_INCERR` high before the move (the held
   answer no longer fits) and low after, and `MB_DIFF_CELLS` back near 0 once adopted. If
   the answer does NOT follow the part, the margins are too large for this bench and
   `REG_WARM_MARGIN` / `REG_JUMP_MARGIN` must be re-derived with `ps_ui/st6_warm_cal.py`
   on a frame pair that actually differs.
2. **A physically rotated part** (0.16 / 0.5 / 1.0 deg, the Stage 3 sweep). Same
   procedure; `MB_REG_ANGLE100` must track the protractor and `MB_REG_MODE` must stay 4.
3. **The one refused attempt in 84** was not instrumented at the stage that refused it, so
   the cause is open. The two words that bound it: `MB_REG_WWHY` = 1 (the held answer could
   not be scored on that frame) and state 2. The next measurement should sample
   `MB_PART_PTS`, `MB_PART_REF` and `MB_REG_WWHY` around the refusal, which
   `ps_fft_dual/st0_refusal_20261024.tcl` already does — 45 s of it did not reproduce one.
4. **The scene with real motion** (the belt running). Two runs of this session were
   contaminated by something moving through the field of view; in both, the transform
   stayed at the held value while `MB_DIFF_CELLS` went to 341..379. That is the right
   behaviour for a still part with a changing background, but it is one observation, not a
   test.

## Cost

The local window costs 10 stride-1 and ~66 stride-2 point sets against the cold search's
34 stride-1, ~230 stride-2 and 306 stride-4, so the steady state is **cheaper** than
solving from scratch; the search runs once per 16 loops, so even a full cold search is
0.3% of the loop budget. `MB_REG_TICKS` (word 233) reads ~5.5M ticks (16 ms at 334.8 MHz)
on the held path.

## Build

`ps_ui/build.ps1`: 0 mailbox collisions (245 words, 245 distinct), all layout checks pass,
`.text` 88,628, `.bss` 31,016, only the four pre-existing warnings. Flashed with
`ps_fft_dual/strict_load_cores.tcl`; the board reads `TSC1` / the new hash.
