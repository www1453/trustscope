# Stage 8 (2026-10-24) -- 8x8 comparison cells inside the part only; the local-threshold change measured and NOT shipped

Status: change 1 DONE, flashed, accepted (196 comparisons) and committed as `e71ae33`.
Change 2 was designed, measured against a known answer and **not shipped**: the fixed
14-grey-level threshold has no measured false-cell population to remove on this bench,
and the stronger local rule hides real defects.  Section 5 has the numbers; the code
still has `FINE_THRESH = DIFF_THRESH` and no adaptive path.

## 1. What changed (change 1), with line numbers (`ps_ui/main.c` of `e71ae33`)

| line | item |
|---|---|
| 1657 | the design block: 8x8 cells, why inside the mask, the measured price table |
| 1775 | compile-time check that the fine grid IS the part mask's lattice (one cell per 8x8 block) |
| 2070-2117 | the new mailbox words 494..502 and the known-answer stamp words 505..507 |
| 2584-2612 | `cell_mean8()` -- four samples, each a 3x3 box, at +2/+6 |
| 2851-2864 | `FINE_FLAG` / `FINE_HIT` / `FINE_SUM` in DDR, 57,600 bytes |
| 2893, 2941 | `avg_reset()` / `avg_sample()` accumulate the fine cells over the same N frames |
| 4453-4472 | `fine_publish_invalid()` -- a refusal invalidates the fine count too |
| 4581-4628 | `stamp_reference()` -- MB_CMD = 15 known-answer size stamp |
| 4767-4798 | `ref_cell8()` -- the reference side of the fine cell, the same four 3x3 boxes |
| 5417-5520 | the fine pass in `diff_frame()`: judge only cells inside `LIVE_MASK`, same 3x3 rule, same `PERSIST_N` |
| 7013-7032 | `diff_verdict()` reads `FCELLS` when `FVALID != 0`, else falls back to the coarse count |
| 10235-10242 | the command handler for MB_CMD = 15 |

The coarse 16x16 whole-frame pass is untouched: `MB_DIFF_CELLS`, the row profile, the
classifier and the difference view all still describe it, so the stage-7 distribution
(241 / 2 / 42 of 285) stays comparable.  The fine pass is a second, independent answer,
and it is the one the verdict reads.

## 2. Why 8x8, and why only inside the part -- measured offline first

`ps_ui/st8_fine_grid.py`.  Its coarse mode reproduces stage 3's documented sweep
(0/3/52/155 at 0/0.16/0.5/1 deg and 37 at a 2-px residual) **exactly** -- that is check A,
and it is what makes the rest of the table believable.  Check B: a frame against itself
reads 0 cells in every mode.  Check C: a stamped square of known size lights exactly the
expected cells (8x8 px -> 0 reported, 16x16 px -> 4, 32x32 px -> 16).

Cells after the firmware's 3x3 rule (limit 8), on `ps_ui/st2_A_live.raw`:

| scheme | 0 deg | 0.16 | 0.5 | 1 deg | 2-px residual |
|---|---|---|---|---|---|
| 16x16, whole frame (shipped) | 0 | 3 | 52 | 155 | 37 |
| 16x16, part interior only | 0 | 0 | 0 | 0 | 0 |
| 8x8, whole frame | 0 | 58 | 356 | 1036 | 283 |
| **8x8, part interior only** | **0** | **0** | **3** | **48** | **54** |

The whole-frame 8x8 numbers are unaffordable because what a rotation moves is the belt
and the frame border, not the part.  Inside the part the same fine scheme reads 0 at 0.16
and 0.5 degrees.

**The price, stated rather than tuned away.**  The fine scheme's tolerance to an
*uncompensated* residual is much lower (part interior, 0 deg, cells):

| residual | 0.25 px | 0.5 px | 1 px | 2 px |
|---|---|---|---|---|
| 16x16 | 0 | 0 | 0 | 2 |
| 8x8 | 0 | 0 | 17 | 54 |

So the fine pass lives or dies on the registration's sub-pixel residual.  `reg_refine3()`
refines the translation to 1/16 of a half-resolution search step (1/8 source pixel), and
the 196 board comparisons below hold the identity, i.e. they measure the 0-residual case
only.  A real sub-pixel residual is listed in section 7.

Injected brightness steps inside the part, +40 counts, cells after the 3x3 rule:

| stamp | 8x8 px (1.4x2.0 mm) | 16x16 px (2.8x4.0 mm) | 24x24 (4.2x6.0) | 32x32 (5.6x8.0) | 48x48 (8.4x12) |
|---|---|---|---|---|---|
| 8x8 (new) | 0 | 4 | 9 | 16 | 36 |
| 16x16 (shipped) | 0 | 0 | 3 | 5 | 9 |

## 3. The board acceptance -- 196 independent comparisons, still scene

`ps_fft_dual/st8_accept_20261024.tcl`: MB_CMD = 9 (fresh reference from a live store),
wait 4 s, then one **atomic 1.4 KB mailbox burst per comparison** (words 168..511),
deduplicated by `MB_DIFF_N` (a refused slot does not advance the counter, so the change
detector also watches state / diff_ok / incerr / nreaim).  Three runs, raw rows in
`dl/st8_runA_20261024.txt`, `..._runB_...`, `..._runC_...`:

| run | comparisons | coarse cells 0 / 1..7 / >=8 | fine cells 0 / 1..7 / >=8 | refused slots | MB_READY != 1 | AVG_CNT < 8 |
|---|---|---|---|---|---|---|
| A | 63 | 63 / 0 / 0 | 63 / 0 / 0 | 0 | 0 | 0 |
| B | 64 | 64 / 0 / 0 | 64 / 0 / 0 | 0 | 0 | 0 |
| C | 69 | 69 / 0 / 0 | 69 / 0 / 0 | 0 | 0 | 0 |
| **total** | **196** | **196 / 0 / 0** | **196 / 0 / 0** | **0** | **0** | **0** |

The fine pass judged between 578 and 775 cells per comparison (per-run medians 666, 666
and 646; pooled median 661 over the 196 rows, re-parsed from the raw logs with a parser
independent of the harness), i.e. the answer is over the part's interior, not over a
handful of cells.  `FOVER` (cells over the
threshold *before* the 3x3 and persistence rules) was 0 in all 196, and the largest
|difference| was 9..14 grey levels against the 14 limit (14 exactly is at the limit but not
over the strict `>` test): the fixed threshold is not being challenged in the judged region
at all.  That last number is what settles change 2.

**The bench's own state, because it moved during the session.**  Between 17:50 and 18:05
two runs read 478..685 cells with a full-frame box and `MB_READY` 0 on several rows; the
row profile (`MB_DIFF_ROW`) showed +-13 counts then and +-7 in the acceptance above, and
`MB_AEC_EXP` moved 1871 -> 2105 lines (stage 2 recorded 4803).  The room's illumination
changed; the runs above are the still ones (READY 1 and AVG_CNT 8 on every row) and the
bad ones are reported rather than used.  `dl/st8_runN1_20261024.txt` is the same scene at
N = 1 (no averaging): 33 comparisons, 0 reported cells in all 33, but a raw `FOVER` of up
to 50 (median 4; 20 of 33 comparisons above 0) and largest |d| 19 -- the noise population
the 3x3 rule removes, and the only "before" this bench offered.

## 4. Known injected size on the board (MB_CMD = 15)

The host stamps a square of a known size and height into the **reference** image, so the
live part is a good part and the difference is exactly the square.  All three channels are
raised by the same amount, which leaves the part mask's green-dominance score
`G - max(R,B)` unchanged.  The stamp is cell-aligned by construction (`MB_INJ_CELL` is a
cell index), so the expected count after the 3x3 rule is exact.

| stamp (site) | FOVER | FCELLS after 3 hits | fine bbox | FMAXD | coarse cells | coarse verdict |
|---|---|---|---|---|---|---|
| 16x16 px = 2.8x4.0 mm at cell (110,54) | **4** | **4** | (110,54)-(111,55), the stamped 2x2 | 38..41 | **0** | PASS (would be) |
| 24x24 px = 4.2x6.0 mm at cell (64,74) | **9** | **9** | (64,74)-(66,76), the stamped 3x3 | 35..37 | **0** | PASS (would be) |

The 24x24 px stamp makes the fine pass report 9 cells = **NG**, while the shipped 16x16
comparison publishes 1 cell over the threshold and **0** after its 3x3 rule -- i.e. it
would have PASSED a 4.2 x 6.0 mm defect.  The fine bbox is exactly the stamped rectangle,
which is the independent check that the count is geometry and not noise.

Two sizes were **not** measured, and they are reported as unmeasured rather than as
"not detected":

* a 32x32 px stamp at the first site chosen (cell 61,70) lit only 7..10 cells over and
  reported 5, because the site was at the live mask's edge and the mask moved
  (`dl/st8_stamp32_20261024.txt`); the measured mask movement is **149 of 14,400 cells
  between two dumps 3 s apart**, and 36 of 224 in the small window around that site;
* an 8x8 px stamp (one cell) was written but its cell was **not in the live part mask**
  at comparison time (mask 655 -> 604 cells between the pick and the comparison), so the
  comparison never judged it (`dl/st8_stamp8_20261024.txt`).

A one-cell defect is therefore at the mask's discretion on this object, whose mask is thin
and fragmented; the 16x16 and 24x24 stamps were placed at sites that stayed interior and
reproduced their geometry exactly.

## 5. Change 2 -- local adaptive threshold: measured, and NOT shipped

The change asks for a per-cell threshold derived from the neighbourhood's own contrast,
publishing the threshold used for the worst and the median cell, with both sides
demonstrated: a low-contrast region that produced false cells before no longer does, and a
genuine high-contrast change in the same kind of region is still detected.

`ps_ui/st8_adaptive_eval.py` measures both sides on the shipped 8x8-in-part arithmetic
(`dl/st8_adaptive_eval_20261024.txt`), with two candidate rules computed per cell:
`texture`: `max(14, K * std(live cell values, 5x5 cells))`;
`noise`: `max(14, K * std(difference, 7x7 cells))`.

**(a) The "before" population is empty at the REPORTED level, and only there.**  On the
still pair (`st2_A_live` vs `st2_B_live`, the same pair whose coarse mode is validated in
section 2) the fixed 14 produces **1** cell over the threshold and **0** after the 3x3
rule.  On the board the raw count `FOVER` was **0 in all 196** N=8 comparisons (largest
|d| 9..14; 14 exactly is at the limit but not over the strict `>` test), and **up to 50
per comparison at N = 1** (20 of 33 comparisons had `FOVER` > 0, median 4, largest |d|
19) -- and **0 reported cells in all 33** N=1 comparisons, because the 3x3 rule removes the
scattered noise.  That is the honest shape of the "before": at the shipped setting there
is no population at all, and in the unaveraged control mode there is a raw noise
population that the existing blob rule already removes completely.  A local threshold
would act on that raw population, but no *reported* false cell exists for it to fix.

**(b) What each rule would do, and what it would cost.**  Thresholds that would have been
applied (med = the median judged cell, worst = the cell with the largest |d|):

| rule | median cell | worst cell | cells raised above 14 | false cells removed |
|---|---|---|---|---|
| fixed 14 | 14 | 14 | 0% | -- (1 over / 0 reported) |
| texture K=2 | **27** | **32** | **88.5%** | 0 |
| texture K=3 | **40.5** | **48.1** | **95.2%** | 0 |
| noise K=4 | **14** | **14** | 4.7% | 0 |
| noise K=5 | 14 (p95 17.4) | 14 | 15.3% | 0 |

The sensitivity cost, with a genuine 16x16 px change stamped at two sites (cells reported):

| site (local 7x7 range) | amp | fixed 14 | texture K=2 |
|---|---|---|---|
| lowest-contrast (4 counts) | +16..+60 | 4 | 4 |
| typical texture (38 counts) | +16 | **4** | **0** |
| typical texture (38 counts) | +20 | **4** | **0** |
| typical texture (38 counts) | +24 | **4** | **0** |
| typical texture (38 counts) | +30..+60 | 4 | 4 |

The texture rule hides real 2.8 x 4.0 mm defects of +16..+24 counts in the textured
majority of the part (88.5% of judged cells get a threshold above 14; 74.6% above 20).
The noise rule is nearly a no-op here (median threshold stays 14) and removes nothing.

**(c) The one false-cell mechanism this bench actually produced is not addressable this
way.**  A smooth frame-wide band (the rolling-shutter/flicker structure, measured +-13
counts at 18:00 and +-7 in the acceptance) has a local standard deviation at its peak of
0.3 counts at +-7 and 0.5 counts at +-13: by construction a smooth structure has a *small*
local spread where it is large, so a local-contrast threshold cannot suppress it.  The
other measured false cells in this project's record are registration mistakes (stage 6:
52 of 263 comparisons, 10..186 cells) and whole-scene changes (stage 7 runs G/H) -- the
first is handled by the refusals and margins, the second must be reported as NG.

**Decision: do not ship change 2; keep the fixed 14.**  Both sides of its acceptance
cannot be demonstrated: at the shipped setting there is no false-cell population to fix
(196 of 196 comparisons at zero over the threshold), at N = 1 there is one but the existing
3x3 rule already removes it (0 reported in 33 of 33), the stronger rule measurably hides
real defects, and the weaker rule changes the threshold in <5% of cells without removing
anything.  The change is left in the tree as a measurement, not as code.

What would make it shippable: a bench condition that produces *reported* false cells at
the shipped settings -- e.g. a part whose interior has a noisy low-contrast region large
enough for noise to cluster into a 3x3 blob (a dark part at short exposure), or an
N = 1-like noise floor in the shipped mode.  Neither occurs here: at N = 8 the raw count
is 0, and at N = 1 the noise never clusters.

## 6. Cost, build, flash

* OCM: `.text` 100,828 (was 99,164), `.bss` 28,928 (unchanged), image ends 0x1FB38,
  1,224 bytes of the 128 KB OCM free (was 2,880).  The fine grid's 57,600 bytes are in
  DDR at 0x126C8000..0x126D7080; **no existing buffer changed address or size**.
* `build.ps1`: 305 `MB_*` words, 305 distinct, 0 collisions; all layout checks pass; only
  the four pre-existing warnings.
* Timing: the sampler pass 15.5 -> 28.4 ms (`MB_AVG_TICKS` 5,166,906 -> 9,468,996 ticks;
  the fine grid adds 518k reads per pass, +14% over the coarse pass's 360k, and +83% of
  the pass time because each is a separate non-cacheable access).  The comparison loop
  reads `MB_DIFF_MS` = 91.1 ms (stage 2's 55.6 ms is a different build and is not a
  control); the loop is 137.4 ms (7.28 loops/s) and is still wait-paced, one comparison
  per 16 loops.  The tear rate rose during the session (AVG_TEAR 2 -> 110) but the
  averaging window still filled on every row (`AVG_CNT` 8 in all 196).
* Flashed with `ps_fft_dual/strict_load_cores.tcl` (firmware only; no bitstream, no power
  cycle, no VDMA poke).  FWID `TSC1` / `064BC6E6`.
* Board left in the documented state: `MB_AVG_N` 8, `MB_AVG_CNT` 8, `MB_READY` 1,
  `MB_REG_MODE` 2 (held, angle 0.00), `MB_REG_STATE` 1, DX/DY 0, `MB_DIFF_CELLS` 0,
  `MB_DIFF_FCELLS` 0, `MB_DIFF_FVALID` 622, verdict 0 (`ps_fft_dual/st8_restore.tcl`).

## 7. What remains unverified, and every human-dependent experiment

1. **A real sub-pixel residual.**  The fine pass needs < ~1 source px (17 cells at 1 px,
   54 at 2 px, section 2) and the 196 comparisons held the identity, so the non-zero case
   is unmeasured.  Experiment (operator, ~10 min): mount the part on a translation stage,
   take a reference, step it 0.09 mm (0.5 source px) and 0.18 mm (1 px) in x, and read
   `MB_DIFF_FCELLS` and `MB_REG_MODE`/`MB_REG_MOVE` for 10 comparisons at each step.  If
   the cells stay 0 after the 0.5-px step and jump at 1 px, the fine pass is inside its
   tolerance; if the registration *absorbs* the step (mode 1/4, low move), the residual is
   what the registration leaves, and the number to compare is the post-adoption count.
2. **A real defect on a real part.**  This session's defects are synthetic stamps.  The
   operator's ~40 deliberately damaged boards are the experiment: for each, take a
   reference, read `MB_DIFF_FCELLS`, the fine bbox `MB_DIFF_FX0..FY1`, `MB_BLOB_CLASS`
   and `MB_DIFF_VERDICT`, and record the operator's description.  A confusion matrix from
   that is the only accuracy claim this instrument can support.
3. **The mask's cell-scale movement.**  Measured 149 of 14,400 cells between dumps 3 s
   apart on this object; one 8x8 px stamp was not judged because its cell left the mask.
   Experiment: with a still part and a still lamp, dump LIVE_MASK 10 times 3 s apart and
   count the XOR; if it stays above ~1% the mask is not a stable region at 8x8 pitch and
   the fine count needs a mask-persistence rule (a separate change with its own
   acceptance).
4. **The physical scale.**  This document's mm figures use the task's conversion
   (0.175 x 0.25 mm per source pixel, 8x8 cells = 1.4 x 2.0 mm).  `dl/STAGE3_...` quotes
   "13 px/mm" (0.077 mm/px) for the same bench -- a factor 2.3 apart.  Experiment: put a
   ruler or a 10 mm gauge block in the framing, dump the live frame, and count pixels per
   mm; until then every mm in this document inherits the task's figure.
5. **The bench's illumination.**  `MB_AEC_EXP` moved 4803 (stage 2) -> 1871 -> 2105 lines
   during this session and the row band moved +-7..+-13 counts with it.  The acceptance
   above is a still-scene run at 2105 lines; a repeat under different light is a different
   measurement, not a replication.
6. **The classifier / verdict split.**  The class is computed on the coarse 16x16 map
   (unchanged, out of scope) while the verdict now reads the fine count, so the two can
   disagree by construction (e.g. a 16x16 px defect: fine 4 = PASS, coarse 0 = no blob).
   This is stated, not resolved; resolving it means re-deriving the classifier's cell
   thresholds for 8x8 cells, which is its own change.
