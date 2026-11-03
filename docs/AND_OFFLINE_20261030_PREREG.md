# Pre-registration — the offline dual-view AND test (2026-10-30)

> **Written and committed BEFORE any per-board dual-view dump exists.**
> At the time of writing, the only dual-view dump on this station is
> `dl/evid_20261030/`, taken on an **empty belt** with no reference: both `d0`/`d1`
> are the "not judged" sentinel and all 14,400 `and.raw` bytes are `2` (gate refused).
> It therefore contains **no board data** and cannot be used to choose anything below.
>
> If this file is edited after the first board dump lands, the edit is a protocol
> change and must be recorded in `dl/AND_OFFLINE_20261030.md` §"protocol deviations".
> The SHA-256 of this file at commit time is printed in the final report.

## 0. The question, and the one wrong answer to avoid

Does requiring **both views** to see a cell (`|d| > tol` in each, mapped onto the same
board point) lower the good side's residual tail enough to matter, while leaving a
scratch's amplitude intact — **or does it only look better because warping shrinks the
population of judged cells?**

The named failure mode: compute the AND on the warped/eroded cell set, compare it to a
non-AND baseline computed over the **full** judged set, see both tails drop, and call it a
win. The drop would be a property of the smaller population, not of the AND.

**Therefore, in this analysis the non-AND baseline is always recomputed on exactly the
cells the AND was evaluated on** (same support, same threshold, same recipe), and the
population loss is reported first as a number.

## 1. Data this analysis consumes (one dump per board, `evidence_dump_20261030`)

Per board: `d0.raw`, `d1.raw` (signed int16 per cell, `-32768` = not judged), `tol0.raw`,
`tol1.raw`, `mask0.raw`, `mask1.raw`, `mask0b.raw`, `mask1b.raw`, `deep0.raw`,
`deep1.raw`, `and.raw`, `bg0.raw`, `bg1.raw`, `state.txt`. Layout 160×90 cells,
row-major, `cell = (y·160 + x)`. The dump is taken with the core **stopped** (one
coherent comparison), and `and.raw` distinguishes `1` formed / `0` not formed /
`2` the gate refused. A board whose `and.raw` is all `2`, or whose `state.txt` says
`and ok=0`, is **not a measurement** and is excluded (and reported as excluded).

Deliverable input directory: `dl/and_dumps_20261030/<label>/`, one subdirectory per
placement. No board data exists there at pre-registration time.

## 2. The board set — frozen here (26 dumps + 1 reference placement)

Selected from `dl/host_qc/logs/sweep_20261029_181623_sweep.csv`, **comparable** rows only
(`diff_ok_name = COMPARED`: 41 good / 21 contamination / 12 scratch / 2 corner).

**Reference board (placed once, not dumped):** `b0 g0` — the only good board with
`diff_darea = 0` on 2026-10-29. Its reference is what every measured board is compared
against, so a board with defects cannot be the reference.

**Scratch side — all 12 comparable scratches** (the hard constraint; `d33`/`d35` refused
registration on 2026-10-29 and have no baseline there, so they are out of the primary):

| board idx | label | 10-29 darea |
|---|---|---|
| 64 | d23 | 5 |
| 65 | d24 | 1 |
| 66 | d25 | 1 |
| 67 | d26 | 2 |
| 68 | d27 | 1 |
| 69 | d28 | 2 |
| 70 | d29 | 4 |
| 71 | d30 | 7 |
| 72 | d31 | 2 |
| 73 | d32 | 3 |
| 75 | d34 | 1 |
| 78 | d37 | 3 |

**Good side, primary 12 — stratified random, seed 20261030, 4 per stratum** of the
2026-10-29 camera-0 `diff_darea` (`≤1`, `=2`, `≥3`), drawn from the 40 good boards that
are not the reference, sorted by board index before sampling:

| board idx | label | 10-29 darea |
|---|---|---|
| 1 | g1 | 2 |
| 7 | g7 | 2 |
| 12 | g12 | 3 |
| 17 | g17 | 3 |
| 19 | g19 | 3 |
| 22 | g21 | 1 |
| 23 | g22 | 1 |
| 29 | g28 | 1 |
| 32 | g31 | 1 |
| 33 | g32 | 2 |
| 35 | g35 | 2 |
| 41 | g40 | 3 |

**Good side, supplement 2 — the two worst good boards on 2026-10-29**
(`b11 g11` darea 5, `b14 g14` darea 7). Reported **individually** and excluded from the
pooled good-side p95, so the primary good distribution stays the stratified draw; the
supplement answers "what happens where the false alarms actually are".

Note: `g20` appears twice in the 2026-10-29 CSV (boards 20 and 21, two physical boards,
one label). Neither is selected, so the ambiguity does not enter this design.

**Why this subset is sufficient.** The comparison is *paired within a board on identical
cells*, so its power comes from the **12 positives**, and 12 is all the scratch boards the
station has — no larger scratch sample exists. The good side needs a distribution of the
tail, not a population survey: 12 boards × ~500–700 judged cells gives thousands of
paired cells, and the board is the clustering unit for the CI (below). A full 80-board
re-run would not add positives and would not change the paired estimator; it would only
re-estimate the same good-side p95 more precisely.

## 3. The mapping — pre-registered sources and the order they are tried

1. **The named calibration file `dl/st6_cal_20261024.json`.** Audited first: if it does
   not contain a usable 3×3 reference-to-reference homography (and the file on disk is a
   rectification-search cost table, not a matrix), it is **not usable as a map** and this
   is reported as the audit's result. It is never silently replaced by a claim that it
   was "verified".
2. **Primary: one affine map fitted on the good boards' masks only**, held fixed for every
   board. Fit = ECC (`MOTION_AFFINE`, `warpPerspective` convention) on Gaussian-blurred
   binary masks, initialised at the two masks' bbox-centre difference, with a
   moments-similarity fallback; the consensus map is the coordinate-wise median of the 12
   good-board fits. No scratch board contributes to the map. **This is why**: a map fitted
   per board would absorb each board's view-dependent specular difference — i.e. it would
   "fix" the very thing the AND is supposed to suppress. Fitting on good boards and
   applying blind to scratch boards is the only version that cannot cheat.
3. **Sensitivity maps:** (a) per-board fit (upper bound on alignment, not primary);
   (b) a single similarity (4 DOF) instead of affine; (c) the firmware's published
   `(and_ox, and_oy)` translation only — the as-shipped map; (d) the 2026-10-26 SIFT
   homography from `dl/xcheck_20261026/goodA/` (107 inliers, 1.16 px RMS, det > 0), an
   older session's independent estimate of the same rig, used as a cross-check only.

**Verification before use** (on the 12 good boards): warp `mask1` into view 0 with the
map, **IoU** against `mask0`, and **boundary mismatch** (mean distance between the two
mask boundaries after the warp, in cells). If the median IoU < 0.5, the map is not
identified by these masks and the run reports **"not interpretable"** — not "the AND does
not work". If IoU ≥ 0.8 the map proceeds as primary; between 0.5 and 0.8 it proceeds but
the coverage loss is reported as the dominant uncertainty.

**Mirror or rotation?** The mask's silhouette cannot answer this (a rectangle is
mirror-symmetric), so: (i) the determinant of the 2026-10-26 SIFT homography (already
`+1` in the offline check — no mirror); (ii) the **functional** test on the scratch
boards: under the correct map the scratch's deep cells must line up in the two views;
under a mirrored map they would not. Sign of the fitted affine's determinant is reported
either way.

## 4. The cell statistic — z, sign, and the combination

For each view, `z_v(c) = |d_v(c)| / tol_v(c)` on cells the view judged (`d ≠ -32768`),
where `tol_v(c)` is that view's own dumped per-cell tolerance (the same number the
firmware judged the cell by). Nothing is recomputed with a shared constant.

* **AND statistic (primary):** `A(c) = min(z0(c), z1(c'))` where `c' = M(c)` is the mapped
  cell (nearest neighbour: bilinear smooths a thin line away, which is the object of the
  test), and the cell is in the **support** only if both `d0(c)` and `d1(c')` are judged.
* **Non-AND baseline (primary, same cells):** `B(c) = z0(c)` on **exactly** the same
  support. `B` is camera 0's own shipped statistic restricted to the AND's cells.
* Threshold: `z ≥ 1.0` for the deep set (each cell against its own tolerance); the
  continuous statistics below use the z values, not the thresholded set.
* **Sign-consistency variant:** `A_s(c) = min(z0,z1)` if `sign(d0) == sign(d1)`, else `0`.
  Reported as a separate statistic (primary verdict uses `A`; if `A_s` changes the
  conclusion, both are reported and the reason is stated).

## 5. Statistics — written now, computed once

**Support and coverage (reported first, always).** `N_lat = 14,400`;
`N0` = camera 0's judged cells; `N_A` = support (`d0` and mapped `d1` both judged);
`N_A,er` = support after one-cell erosion. Coverage = `N_A/14,400`; **retention =
`N_A/N0`** (the dilution factor, the trap's size).

**Good side (primary 12).** Pooled per-cell distribution of `B` and of `A` over the
support, all 12 boards together; report **p95** and **max** for each. Drop factor
`D_good = p95(B)/p95(A)`.

**Scratch side (12).** Same pooling over the 12 scratch boards' support:
p95 and max of `B` and `A`; `D_scr = p95(B)/p95(A)`. Secondary, defect-local:
per board, the **defect region** = support cells where `max(z0,z1) ≥ 1`; report
p95/max of `B` and `A` there (`D_scr,def`), because the pooled scratch p95 is dominated by
pad specular on the same boards and does not, by itself, say whether the *defect* survived.

**Paired Δ per board and its CI.** For each board, `Δ = p95(A) − p95(B)` on the identical
support; report the 12 scratch Δs, their median, and a **bootstrap CI over boards**
(10,000 resamples of the 12 boards with replacement, percentile 2.5–97.5, seed 20261030).
The board is the resampling unit because cells within a board are spatially correlated.
The same is done for the 12 good boards.

**The trap, quantified.** `p95(B_all)` = camera 0's p95 over **all** its judged cells
(the full population, the wrong baseline) vs `p95(B)` on the restricted support. Their
ratio is the size of the false improvement that the population change alone would buy.
Reported for both classes.

## 6. Primary recipe (one row of the sensitivity table) and the variants

| axis | **primary** | sensitivity values |
|---|---|---|
| interpolation | **nearest neighbour** | bilinear |
| support erosion | **0 cells** | 1 cell |
| combination | **min** | geometric mean √(z0·z1) |
| threshold | **z ≥ 1.0** | z ≥ 1.5 |
| map | **good-only affine, held fixed** | per-board affine; similarity; firmware offset; 2026-10-26 SIFT H |
| tolerance | **dumped per-cell tol** | per-view robust σ (MAD of d on the good support, /0.6745) |
| sign | **not required** (primary) | `sign(d0)=sign(d1)` required |

Rationale for `erosion = 0` as primary: a scratch is thinner than two cells in places and
erosion can delete the defect itself; in a paired design the boundary cells sit in both
arms, so they add noise to both rather than bias one. Erosion 1 is the sensitivity row and
its coverage cost is reported. **No variant other than the primary decides anything**; the
variants are a table, and the verdict is the primary's.

## 7. THE KILL LINE (verbatim from the brief, with the reading used here)

> if the good side's 95th percentile does not fall by at least **2×** relative to the
> same-cell baseline, or if the scratch side's does **not** fall by a factor 2.5×
> (i.e. it falls almost as much), then **the AND is not effective**

**Reading.** A 2.5× fall of the scratch side is the *loss* side of the line: the AND has
then killed the defect together with the specular. The parenthetical ("falls almost as
much") fixes the direction of the inequality: the danger is the scratch falling **as much
as** the good side. The mechanical form used, written before the numbers:

```
EFFECTIVE      iff  D_good >= 2.0  AND  D_scr <= 2.5
NOT EFFECTIVE  otherwise
```

i.e. the AND must buy at least a factor 2 on the good tail while the scratch side keeps
more than 1/2.5 = 40 % of its p95. `D_scr,def` is reported beside it but does not move the
line. The line is applied to the primary recipe only, once, and the outcome is stated
either way. **No searching for a variant that passes**: if the primary fails and a variant
passes, the report says the primary failed and the variant is a hypothesis for a new
pre-registration.

## 8. What makes the run invalid (stop conditions, not results)

* Any board whose `and.raw` is all `2` or whose `state.txt` reports `and ok=0`: no AND was
  formed; excluded, counted, reported. If more than 4 of 26 boards are excluded, the run
  is reported as **inconclusive due to gate refusals**, not as a negative result.
* Median mask IoU < 0.5: the map is not identified → **not interpretable**.
* `d0`/`d1` all sentinel, or `tol` zero on judged cells: dump invalid.
* The station's build stamp is not `TSC1EF097D3C` in any dump: the dumps mix builds and
  are not a single population → invalid.
* The reference was not both-views (`cam1 ref < 400`): the AND could never form; invalid.

## 9. The one-sentence verdict (template, filled only after the numbers)

> "The AND lowers the good side's p95 by **X×** while the scratch keeps **Y×** of its
> defect amplitude (pooled scratch p95 **S×**), therefore **effective / ineffective**
> against the kill line."

## 10. Reproducibility

`python dl/and_offline_20261030.py --dumps dl/and_dumps_20261030 --out dl/and_offline_20261030`
is the one command; it re-derives every number, table and figure in the final report, and
prints the verdict line. `--selftest` runs the known-answer tests (synthetic mask pairs
with a known affine: recovered transform, IoU, mirror detection; sentinel handling) with
no board and no dumps. `--audit-calib` prints what the named calibration file actually
contains.
