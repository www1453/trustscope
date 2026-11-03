# Stage 4 — the part mask's threshold is now relative to the frame

Written 2026-10-23 21:2x, after the change was built, flashed and measured, and before it
was committed.  Numbers that are predictions are labelled as predictions.

## The defect

`part_masks()` thresholded `score = G - max(R,B)` at a fixed **12**.  The score is a
channel *difference*, so it survives an exposure change (the ADC gain multiplies all
three channels) but it does not survive a change in the camera's **colour balance** — and
the balance is moved by the OV5640's own auto white balance, which nothing in `ps_ui/`
controls: no white-balance register is written anywhere in this program.

## First: the evidence in STAGE3 could not support its own conclusion

`STAGE3_20261023_blur_and_cell.md` blamed the AWB on the strength of a frame with means
R=132 G=113 B=122.  That frame is `ps_ui/st1_now_s0.raw` (means measured here: R=132
G=111 B=121), and **the part is not in it**.  Rendered at full resolution it is a view of
the room under the bench:

    ps_ui/st4_awb_2047.png       that frame -- no board anywhere
    ps_ui/st4_awb_2038.png       st2_A_live.raw, the "good" state -- board fills the frame
    ps_ui/st4_awb_2012.png       st1_a_s0.raw, the "20:12" state -- same board, same place

So "0.03% of pixels over +12 and the mask collapsed to 0" on that frame is the CORRECT
answer for a frame with no part in it, not an AWB failure.  That piece of evidence is
withdrawn.  (It is worth recording why it looked convincing: the frame means really do
differ in the way the note described, and the mask really was empty.  The missing control
was "is the part in the picture" — a question a rendered image answers in one look.)

## The defect is real anyway, measured on the live board

Before this change, on the board, with the part in view (`strip_b.png`, rows 420..719 --
the board is on the bench), the published words were:

| word | value |
|---|---|
| 366 `MB_PART_PTS` | **2** |
| 367 `MB_PART_REF` | 0 |
| 232 `MB_REG_STATE` | 2 (CANNOT JUDGE) |
| 180 `MB_DIFF_OK` | 5 (refused: no registration) |

and the same live frame, measured offline: the frame's green dominance had collapsed
(pixels with score > 12: **0.10%**; frame means R=102 G=86 B=86 against R=132 G=133 B=134
at 20:38 — the R/G ratio moved 0.99 -> 1.19, which is a colour-balance change, not an
exposure change).  The absolute rule therefore found **2** lattice points out of 14,400.

## What changed (`ps_ui/main.c`)

| item | before | after |
|---|---|---|
| score | `part_green()` returns 1/0 against 12 absolute | `part_score()` (main.c:1677) returns the signed score |
| threshold | `score > 12` | `score > (frame median + PART_MARGIN)` (main.c:1750) |
| median | — | 256-bin histogram of the 160x90 block scores, in the same 14,400-byte mask buffer (two passes, `part_masks()` main.c:1715) |
| published | `MB_PART_PTS/REF/USED` | + `MB_PART_MEDIAN` (median+128, word 369), `MB_PART_MARGIN` (370), `MB_PART_MEDREF` (371) |
| margin | 12 (absolute) | **12 (relative)** — the same number, a different reference point |

The 2x2 samples at +2,+5, the 8x8 block, the 3x3 erosion and `PART_MIN_PTS = 400` are
unchanged.

### Why the margin is 12 — measured

Eroded mask points (out of 14,400) at several margins, on four real frames.  Computed by
`ps_ui/st4_awb_mask.py`, which reimplements `part_score()`/`part_masks()` in numpy
including C's truncating division:

| frame | abs rule | m6 | m8 | m10 | **m12** | m16 | m20 | m24 |
|---|---|---|---|---|---|---|---|---|
| `st1_a_s0.raw` 20:12 (part in view) | 1,256 | 3,808 | 3,558 | 3,179 | **2,950** | 2,524 | 2,135 | 1,922 |
| `st2_A_live.raw` 20:38 (part in view) | 1,613 | 3,403 | 3,127 | 2,827 | **2,599** | 2,296 | 2,087 | 1,952 |
| live 21:40 (part in view, collapsed balance) | **2** | 2,818 | 2,449 | 1,863 | **1,200** | 67 | 0 | — |
| `st1_now_s0.raw` (NO part in view) | 0 | 792 | 511 | 330 | **139** | 12 | 0 | — |

* 12 keeps the part in every state measured, including the one where the absolute rule
  found 2 points.
* 12 keeps `PART_MIN_PTS` meaningful: with no part in view a margin of 12 finds 139
  points, below the 400-point floor, so the registration refuses and the answer is
  CANNOT JUDGE.  Margins 6..8 would find 511..792 false points there, which is above the
  floor — i.e. the registration would start locking onto the background.
* 16 and above already miss most of the part on the live frame (67 points at 16).

The mask lands on the part: on `st2_A_live.raw` at margin 12 the mask bbox is
(368,160)-(1032,632) source px; stage 2 measured the board's own bbox on this bench as
(376,176)-(1024,624).  The mask and the independently-measured part agree to one lattice
step all round.

## The comparison: measured, and deliberately NOT changed

The task's premise was that "the cell comparison compares twelve colour channels and its
single global scalar gain cannot correct a per-channel shift".  **It does not**, and it
did not before this stage: every per-sample read in the comparison is the green channel —
`cell_mean4()` main.c:1455 reads `q[sx*3 + 1]`, `ref_at()` main.c:2469 reads `+1`, and so
do `diff_refine`, `settle_grid_fill`, `grey_capture` and `latt_fill`.  R and B are read
only by the fusion renderer.  "One value per sample" was already true.

What was open was **which** value, so both candidates were measured
(`ps_ui/st4_quantity.py`, same arithmetic as the firmware):

**A. AWB drift with a known answer.**  The 20:38 frame scaled by the per-channel gains
measured between the 20:38 and 20:47 frame means (R x1.003, G x0.854, B x0.920) — the
scene is provably unchanged, so the correct number of flagged cells is **zero**:

| quantity | scalar gain | max residual after gain+bias | cells over 14 |
|---|---|---|---|
| green alone | 301 | **2** counts | 0 |
| Y = (R+2G+B)/4 | 284 | 3 counts | 0 |

Both are corrected exactly by the one global scalar, because an AWB move is a
per-channel **multiplication** and a multiplication of the green channel is precisely what
one scalar on the green channel undoes.  A per-sample luminance is *not* more robust here;
it leaves one count more.

**B. Sensitivity** (`st3_blur_sweep.py`'s model, 16x16 cell + 5x5 box + blob rule, the
number to compare with the limit of 8):

| frame | quantity | 0 deg | 0.16 | 0.5 | 1.0 | 2-px |
|---|---|---|---|---|---|---|
| `st2_A_live.raw` | green | 0 | **3** | **52** | **155** | **11** |
| `st2_A_live.raw` | Y | 0 | 3 | 53 | 163 | 26 |
| `st1_a_s0.raw` | green | 0 | 2 | 43 | 119 | 14 |
| `st1_a_s0.raw` | Y | 0 | 2 | 47 | 148 | 17 |

The green row reproduces the published baseline (0 / 3 / 52 / 155) exactly, which is the
control that says the harness is the same harness.  Y is worse at 1 degree (163 vs 155)
and at the 2-px residual (26 vs 11).

**Decision: the per-sample quantity stays green alone**, on measurement.  The cost is
stated in the code: a defect that changed only R and B, leaving the green level alone, is
invisible to `MB_DIFF_CELLS`.  A second, colour-difference statistic would cover that
class; it is a separate change with its own measurement, not a silent addition here.

## Acceptance (a) — met on the board

Fresh reference taken with `MB_CMD = 9` (the firmware's own host command), then
`FWID = 0x31435354 0x44384144 0x45353742` = `TSC1` + `DA8DB75E` = `ps_ui/build_id.h`.
Six samples, 0.7 s apart:

| word | before the fix | after |
|---|---|---|
| 366 `MB_PART_PTS` | 2 (and 39, then 0, earlier in the day) | **1,109 .. 1,519** |
| 367 `MB_PART_REF` | 0 | **1,532** |
| 232 `MB_REG_STATE` | 2 (CANNOT JUDGE) | **1** in 6 of 6 samples |
| 180 `MB_DIFF_OK` | 5 | **1** in 6 of 6 samples |
| 181 `MB_DIFF_CELLS` | 0xFFFFFFFF (not measured) | **0** on the fresh reference |
| 369 `MB_PART_MEDIAN` | — | **-18 .. -20** (published as median+128) |
| 370 `MB_PART_MARGIN` | — | **12** |
| 371 `MB_PART_MEDREF` | — | **-18** |

Independent cross-check on a dumped live frame (6.3 s full dump, static scene): the
numpy reimplementation of the same arithmetic gives **median -19** and **1,423** mask
points, against the firmware's own published -18..-20 and 1,109..1,519 — two
implementations that share no line of code, agreeing on both numbers.  The same dump under
the OLD rule gives **0** points, reproducing the failure.

## Acceptance (b) — the AWB demonstration, and what it is really worth

* **On the board, same frame, both rules:** the live frame that the old rule masks with
  **2** points the new rule masks with **1,200** (offline, same dump) and
  **1,109..1,519** (firmware, live).  The frame's balance at that moment was
  R=102 G=86 B=86 against R=132 G=133 B=134 at 20:38; green dominance had fallen from
  25.2% of pixels over +12 to 0.10%.
* **Across the three dumped balance states, with the part in view:** 2,950 / 2,599 / 139
  points (the last one has no part in the frame, which is why it is 139 and not thousands).
* **What this does NOT show:** a *controlled* AWB experiment — the same scene, the same
  light, only the AWB moved, with the sensor's balance read back to prove it moved.  The
  balance was never read back (nothing in this build reads the WB registers), and the two
  frames that bracket the biggest balance change in the dumps also differ in scene.  The
  synthetic drift in part A above is the controlled substitute, and it is a model of the
  drift (a per-channel gain), not the drift itself.

## Acceptance (c) — the sensitivity sweep

The comparison's per-sample arithmetic was not changed, so the model reproduces the
published baseline exactly rather than "not worse than" it: **0 / 3 / 52 / 155** at
0 / 0.16 / 0.5 / 1 degree and **11** at the 2-px residual on `st2_A_live.raw` (published
baseline: 0 / 3 / 52 / 155, 2-px 37).  The alternative that would have changed it (Y) was
measured and is worse (see B above).  On the current live frame the same scheme reads
0 / 0 / 48 / 194 with a 2-px residual of 68 — a different scene, so it is not comparable
to the baseline row and is reported only for completeness.

## Not verified, and what it would take

* **The scene was being physically moved during this session.**  The camera's view changed
  three times in 30 minutes: the board filling the frame (20:38 dump), the board lying on
  the bench seen at a grazing angle (21:31 strip), and a view of the room with a door and a
  person's arm at the right edge (21:40 and 21:55).  In the current view the mask — quite
  correctly, by its own rule — selects the **door**, which is the greenest large region.
  So `MB_PART_PTS` is in the thousands, but it is counting a door, not the part.
  **The operator must put the part back under camera 0, filling roughly a fifth of the
  frame, before `MB_PART_PTS`'s value can be read as "the part was found".**  Until then
  the acceptance numbers above are about the mask rule, not about the board being judged.
* **A controlled AWB experiment** (the same scene at two balance states, with the balance
  read back) has not been run.  It needs either an AWB register read in the firmware or an
  operator who can hold the scene still while the AWB settles differently.
* `ps_ui/st2_mask_check.py` still implements the OLD absolute rule; it is a stage-2
  artifact and now describes a rule the firmware no longer uses.
