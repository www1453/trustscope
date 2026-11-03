# 2026-10-30 — does the dual-view AND help? Offline design, map verification, and the deciding run

> **Status.** The *deciding* measurement — the paired per-cell comparison on the same
> boards — has **not happened yet**: it needs one evidence dump per board from the current
> build, and no such dump exists for any board (the only dual-view dump on the station,
> `dl/evid_20261030/`, is the empty belt: all four grids are the not-judged sentinel and
> all 14,400 `and.raw` bytes are `2`, gate refused — the tool correctly rejects it).
> What this file contains is everything that can be established **without** the board:
> the map's verification, the population the test will run on, the trap's size, the frozen
> recipe and kill line, the exact 27-placement sequence, and a one-command analysis with
> known-answer tests. Every number below is reproducible offline by the commands in §8.
> Sections marked **[PENDING]** are filled by one command when the dumps land.

Evidence levels follow the project's claim discipline: **E1** = a proxy or a partial
measurement, **E2** = the target quantity measured, **E3** = E2 reproducible by one command.

---

## 1. The call about the board: yes, it has to be used — 27 placements, 26 dumps

The question is a **joint** one: it asks whether a cell that is deep in *camera 0* is also
deep in *camera 1*, in *the same board's* two views. There is no dual-view per-cell data in
the repository for any board:

| what exists | what it has | why it cannot decide |
|---|---|---|
| `dl/evid_20261030/` | both views' signed residual, tolerances, masks, AND grid | empty belt: all sentinel, all `and.raw = 2` |
| `dl/sweep_frames/20261029_181623_sweep/` | one camera-0 frame, mask, `|d|` and tolerance per board (80 boards) | **camera 1 is absent by construction** |
| `dl/xcheck_20261026/goodA/` | a real cam0+cam1 image pair of a good board | one placement, no per-cell residual, no scratch |
| `dl/st6_cal_20261024.json` | a calibration-search cost table | no homography at all (§2.1) |

So the board must be used, but only for **one dump per board** — 26 dumps plus one
reference placement. The dump's only core operation is `stop`/`con` around the reads (the
same operation the dump that already succeeded at 17:07 used). **Nothing is built, flashed,
reset or re-programmed**, so this is not the failure that has cost 15 minutes of restore
three times today. Cost: ~40 s per placement, ~20–25 minutes in total.

The board set, frozen before any board data (pre-registration §2,
`dl/AND_OFFLINE_20261030_PREREG.md`, SHA-256
`1e1733276599726b8e3f86383708e8f67bbcf1b823775bc7c1c062b83c2fd0d8`, commit `dfeae6c`):

* **reference** `b0/g0` (the only good board with 2026-10-29 DAREA 0) — placed once;
* **12 scratch** — every comparable scratch (the hard constraint: 12 is all the station has);
* **12 good** — stratified seeded draw (seed 20261030, 4 per 2026-10-29-DAREA stratum);
* **2 good supplement** — `b11/g11`, `b14/g14`, the worst two on 2026-10-29, reported
  individually and **excluded** from the pooled good p95.

**Why this is sufficient and a full 80-board re-run is not needed.** The comparison is
*paired inside each board on identical cells*, so its power is the number of **positives**
(scratch boards), and 12 is all that exists; no larger run creates more positives. The good
side needs a tail distribution, not a population survey: 12 boards × ~600 judged cells is
~7,000 paired cells, and the **board** is the resampling unit for the CI. Adding boards
would re-estimate the same two p95s more precisely; it cannot create positives.

---

## 2. The map: three sources, one usable — and it is not the one the brief named

### 2.1 The named source does not contain a homography (E1, measured)

`dl/st6_cal_20261024.json` is described in the brief as "reference-to-reference homography,
RMS 0.137 px". It is not. `python dl/and_offline_20261030.py --audit-calib` prints:

```
top-level keys: ['dumps', 'incerr', 'e0', 'cost', 'ok']
NO HOMOGRAPHY / AFFINE MATRIX ANYWHERE IN THIS FILE
it is a calibration-search cost table: keys ['deg','x','y','sc','deg10','deg20','deg50','x1','x2','y1','y2','sc1','sc2']
entries per key: 24
```

There is no 3×3 matrix in the file, under any key or nesting. The 0.137 px figure is the
**stereo calibration's reprojection RMS** (`cv2.stereoCalibrate`'s return in
`dl/stereo_calibrate.py:186`), i.e. how well the calibration points fit the pinhole model —
not the residual of a homography that could be applied to a cell grid. **The homography
therefore cannot be "verified": it is absent.** Reconstructing one from the 2026-10-24
calibration would give a map for the *calibration board's plane*, which is not the QC
board's plane (the brief's own warning). Nothing was silently substituted; the map used
below is estimated from the rig's own board-plane data and its source is named.

### 2.2 The one independent stereo measurement on the board plane (E1, measured)

`dl/xcheck_20261026/goodA/cam0.raw` + `cam1.raw` are a real stereo pair of a good board on
the belt, same station, 2026-10-26 (previous build, so this is a **cross-session** check and
is labelled as one). `--verify-pair` estimates the board-plane homography from SIFT on the
board ROI:

| quantity | value | meaning |
|---|---|---|
| SIFT matches / RANSAC inliers | 135 / **107** | plenty of correspondences on the PCB |
| reprojection RMS | **1.16 px** (= 0.15 cell) | sub-cell accuracy for the cell grid |
| `sign det(H)` | **+1** | **the two views are not a mirror pair** |
| local Jacobian at the board | u-scale **1.104**, v-scale **0.953**, rotation **−0.91°** | an **anisotropic affine**, not a similarity and not a translation |
| board displacement view0→view1 | **(+184.4, −6.9) px = (+23.05, −0.86) cells** | the big component is **horizontal** |

![the two views and the part mask](and_offline_20261030/fig_pair_mask.png)

### 2.3 What the part mask actually is (E1, measured — and it changes the plan's premise)

The brief treats "the mask" as a binary board silhouette, immune to specular. Measured on
the 2026-10-29 sweep (camera 0, 40 good + 12 scratch boards): the part mask is a **sparse
pad/field pattern**, median **625 cells = 4.3 % of the 14,400-cell lattice**, with pad-sized
holes everywhere (the figure's red outline). It is the same `|live − background| > 24` rule
that specular lights up, so it is **not** specular-immune: it is itself a view-dependent
feature set. Consequences, all handled in the design:

* a mask-based map must be fitted on **good boards only and held fixed**, never per board —
  a per-board fit would absorb that board's specular difference, i.e. "fix" the very thing
  the AND is supposed to suppress;
* the mask's bbox centre is a weak translation proxy, which is exactly what the firmware's
  `and_ox/and_oy` uses. A **525-cell mask cannot have bbox width 0**, so the reported
  `and_scale = 0` cannot be a true size ratio; it points at the word capture, not at the
  optics. The dumps will let this be reproduced exactly from the masks (§4, "firmware AND").

### 2.4 Why `oy = −23` is not a mounting explanation — and what the mask-level test shows

The published `(ox, oy) = (+8, −23)` puts a 23-cell magnitude on the **vertical** axis. The
one independent board-plane measurement says the displacement is **(+23.0, −0.9) cells** —
23 cells on the **horizontal** axis and essentially zero vertically.

A second, sharper test uses the same pair: take camera 0's own dumped pad mask, carry it
through the homography into camera 1's lattice (so **no specular is in it** — the only
remaining difference is the map), then measure how well each candidate map puts it back:

| map applied | offset (cells) | IoU of the pad field |
|---|---|---|
| the homography (full affine/perspective) | — | **0.990** |
| the best possible translation-only map | (+22.29, −0.93) | **0.721** |
| **the firmware's bbox-centre formula**, exactly as `dual_and_build()` computes it (`ox = c0x − c1x`, sampled at `x + ox`) | **(−23.50, +1.00)** | **0.042** |

Three conclusions, all from the one board-plane pair and all E1:

1. **The non-overlap is a map failure, not a board-geometry fact.** With specular removed,
   the affine keeps 99 % of the mask; the shift the code applies keeps 4 %.
2. **A translation cannot do it even in principle**: the best translation caps at IoU 0.72
   on this pad field (the views differ by ~10 % anisotropic scale and ~1° rotation), and the
   far corner drifts by up to ~23 cells. A translation-only AND, however well centred, loses
   ~28 % of the pad field before specular is even considered — that is a coverage loss the
   same-cell baseline must absorb.
3. **The sign of the code's offset is inverted relative to its own comment** on this pair:
   the physical displacement is `c1 − c0` = +23 cells, and the code computes `c0 − c1` and
   samples at `x + (c0 − c1)`. The comment says "camera 1's cell = camera 0's cell + (ox,oy)";
   the code applies the opposite. On this pair that alone costs the difference between an
   overlap and none at all.

The 2026-10-30 pose cannot be assumed to give the same numbers (the reported `ox = +8` is
positive, while this pair's formula gives −23.5), which is itself evidence that the sparse
pad masks' bbox centres are a noisy input. The three candidate explanations therefore remain
open **until the dumps are reproduced offline**:

1. the formula's sign/convention (2.4.3) — testable by comparing `c0 − c1` from the dumped
   masks with the mailbox `and_ox/and_oy`;
2. the sparse-mask bbox instability (specular changes which pads exist, so the bbox moves);
3. a coordinate transposition in the capture of one view's bbox words.

The script reproduces the firmware's own `(ox, oy, ovl, scale, cells)` from the dumped masks
and compares them with the mailbox; that separates (1)/(3) from (2). **This is a question the
deciding run answers; it is not assumed below.**

---

## 3. The population the test will run on (pre-data, camera 0, 2026-10-29)

This is existing data, not dual-view, and it is reported here because it was measured
**before** the deciding data and constrains what the kill line can mean. z = |d| / the cell's
own tolerance (the sweep's tolerance is the 30-grey floor on every judged cell, so z = |d|/30).

| class | boards | judged cells | p95 | p99 | max | cells > 1 (deep) | cells > 3 |
|---|---|---|---|---|---|---|---|
| good | 40 | 24,480 | **0.600** | 1.100 | 3.53 | 1.26 % | 8 |
| scratch | 12 | 6,983 | **0.667** | 1.200 | 3.17 | 1.75 % | 1 |

Two facts follow, and they matter for reading the kill line:

* the scratch boards' p95 is only **1.11×** the good boards' p95 — at the 95th percentile
  the two populations are almost the same distribution;
* on **both** classes the p95 (0.60 / 0.67) sits **below the cell's own tolerance (=1)**;
  only 1–2 % of cells are "deep". **The p95 is a noise statistic here; the signal lives in
  the top ~1 % (max 3.5)**. A "2× fall in p95" is therefore a statement about the noise
  floor, not directly about the defect.

This was written before any dual-view data. It does not move the pre-registered kill line
(§4), but the report will show the **max/p99** rows beside the p95 rows, and the
**defect-local** statistic (the scratch's own cells) beside the pooled one, so the mechanism
can be read even if the p95 cannot see it.

---

## 4. The deciding measurement — what one command produces **[PENDING]**

`python dl/and_offline_20261030.py --dumps dl/and_dumps_20261030 --out dl/and_offline_20261030`
writes `results.json` + `RESULTS.md` (tables) and prints the verdict line. In order:

1. **The map** — consensus affine from the 12 good boards' masks only (coordinate-wise
   median), held fixed, applied blind to the scratch boards; per-board IoU against the
   `mask0` it was warped to, and boundary mismatch in cells. Source named per board
   (`ecc-affine` / `moments`). If median IoU < 0.5 the run reports **not interpretable**.
2. **Coverage first** — camera 0's judged cells vs the AND's support (cells judged in both
   views after the warp), against the 14,400-cell lattice, **and the retention**
   `N_AND / N_cam0`: that ratio is the dilution factor, the trap's size.
3. **The same-cell non-AND baseline** — camera 0's own z on **exactly** the AND's support.
   The full-set baseline is computed too, but only to *measure* the false win it would buy.
4. **Percentiles** — good and scratch p95 and max on the same cells, before/after;
   `D_good = p95(base)/p95(AND)`, `D_scr = p95(base)/p95(AND)`.
5. **Paired Δ per board** — `p95(AND) − p95(base)` on identical cells, 12 boards per class,
   **bootstrap CI over boards** (10,000 resamples, percentile 2.5–97.5, seed 20261030).
6. **Sign consistency** — the same AND with `sign(d0) == sign(d1)` required, as a separate
   statistic, plus the sign-agreement rate on the deep cells of each class (the physical
   prediction: specular disagrees between views, a scratch does not).
7. **The firmware's own AND** — recomputed at its published offset and at the verified map:
   deep0 cells, cells seen by both, and the mailbox's `and_cells/and_darea/ox/oy/ovl/scale`.
8. **Sensitivity table** — erosion 0/1, nearest/bilinear, min/geometric mean, z≥1.0/1.5,
   sign on/off. **Only the primary row decides** (§4.1). The other map sources are not p95
   rows: the per-board fit appears as an IoU column beside the held-fixed map (a map fitted
   per board would absorb that board's specular — it is the upper bound, not a candidate),
   and the firmware's offset appears in its own table with the cells it actually sees.

The two pre-registered stop conditions are enforced in code: median mask IoU < 0.5 → status
`not interpretable`; more than 4 of 26 boards refused → status `inconclusive`. In either case
the verdict line says so instead of reporting a kill-line outcome.

### 4.1 The primary recipe and the kill line (frozen, `dl/AND_OFFLINE_20261030_PREREG.md` §6–7)

Primary: **nearest neighbour**, **erosion 0**, **min(z0,z1)**, **z ≥ 1.0**, **good-only
affine held fixed**, dumped per-cell tolerance, no sign requirement. Erosion 0 is primary
because a scratch is thinner than two cells in places and erosion can delete the defect; in a
paired design the boundary cells sit in both arms, so they add noise to both rather than bias
one. Erosion 1 is the sensitivity row with its coverage cost reported.

The kill line, in mechanical form, written before the numbers:

```
EFFECTIVE      iff  D_good >= 2.0  AND  D_scr <= 2.5
NOT EFFECTIVE  otherwise
```

with the brief's "2.5×" clause read as the **loss** side (the parenthetical "falls almost as
much" fixes the direction): the scratch side must keep more than 1/2.5 = 40 % of its p95.
The ambiguity in the sentence's wording is recorded here rather than silently resolved. The
line is applied once, to the primary recipe, and the outcome is stated either way — no
searching for a variant that passes.

**The trap, on this data, measured [PENDING]:** `p95(camera 0 over its full judged set)`
versus `p95(camera 0 on the AND's support)`. That ratio is the improvement the population
change alone would hand the AND. A synthetic known answer puts its size at **6.15×** when
the excluded region is the high-residual one (selftest, §6), and the real camera-0 erosion
test shows the opposite limit: one-cell erosion removes **44 %** of the judged cells on these
masks (it keeps 56 %, measured) and still moves the p95 by only **1.04–1.05×**. Shrinkage
alone barely moves the p95; if the real full/same-cell ratio is large, the excluded cells
really are systematically the high ones — which is exactly the trap.

---

## 5. The sequence — 27 placements, one command each

Each command is self-checking (build stamp, fresh comparison, `and_ok`, file sizes); a
failure exits 2 and is logged in `dl/and_dumps_20261030/runlog.csv` — re-place that board,
do not hand-wave it. The background command retries only on camera 0's clip-0 / not-stuck
moments (the loop `ps_fft_dual/a2_bgretake_20261026.tcl` already uses, because `MB_CMD = 12`
is refused while the AEC hunts). Output: one directory per board under
`dl/and_dumps_20261030/`.

```text
# 1. BELT EMPTY, no board in the fixture (pins the exposure, captures the background)
python dl/and_dump_20261030.py --stage background --yes

# 2. REFERENCE BOARD b0/g0 in the fixture, then REMOVE it (takes both views' references)
python dl/and_dump_20261030.py --stage reference --label b0_g0 --yes

# 3. one line per measured board, one placement per line (the order is frozen)
python dl/and_dump_20261030.py --stage dump --label b64_d23 --yes     # scratch
python dl/and_dump_20261030.py --stage dump --label b65_d24 --yes     # scratch
python dl/and_dump_20261030.py --stage dump --label b66_d25 --yes     # scratch
python dl/and_dump_20261030.py --stage dump --label b67_d26 --yes     # scratch
python dl/and_dump_20261030.py --stage dump --label b68_d27 --yes     # scratch
python dl/and_dump_20261030.py --stage dump --label b69_d28 --yes     # scratch
python dl/and_dump_20261030.py --stage dump --label b70_d29 --yes     # scratch
python dl/and_dump_20261030.py --stage dump --label b71_d30 --yes     # scratch
python dl/and_dump_20261030.py --stage dump --label b72_d31 --yes     # scratch
python dl/and_dump_20261030.py --stage dump --label b73_d32 --yes     # scratch
python dl/and_dump_20261030.py --stage dump --label b75_d34 --yes     # scratch
python dl/and_dump_20261030.py --stage dump --label b78_d37 --yes     # scratch
python dl/and_dump_20261030.py --stage dump --label b1_g1 --yes       # good (stratum 2)
python dl/and_dump_20261030.py --stage dump --label b7_g7 --yes       # good (2)
python dl/and_dump_20261030.py --stage dump --label b12_g12 --yes     # good (3)
python dl/and_dump_20261030.py --stage dump --label b17_g17 --yes     # good (3)
python dl/and_dump_20261030.py --stage dump --label b19_g19 --yes     # good (3)
python dl/and_dump_20261030.py --stage dump --label b22_g21 --yes     # good (1)
python dl/and_dump_20261030.py --stage dump --label b23_g22 --yes     # good (1)
python dl/and_dump_20261030.py --stage dump --label b29_g28 --yes     # good (1)
python dl/and_dump_20261030.py --stage dump --label b32_g31 --yes     # good (1)
python dl/and_dump_20261030.py --stage dump --label b33_g32 --yes     # good (2)
python dl/and_dump_20261030.py --stage dump --label b35_g35 --yes     # good (2)
python dl/and_dump_20261030.py --stage dump --label b41_g40 --yes     # good (3)
python dl/and_dump_20261030.py --stage dump --label b11_g11 --yes     # good SUPPLEMENT (worst-2)
python dl/and_dump_20261030.py --stage dump --label b14_g14 --yes     # good SUPPLEMENT (worst-2)
```

`python dl/and_dump_20261030.py --list` prints the same list without the comments.
One board at a time in the usual fixture pose; the reference is the last thing removed
before the first measured board; the belt is empty between boards. The 2026-10-29 labels
contain one duplicate (`g20` on boards 20 and 21); neither is selected, but keeping the
10-29 order keeps the index unambiguous.

---

## 6. Tooling and its known-answer tests (E3)

`python dl/and_offline_20261030.py --selftest` — no board, no dumps, synthetic data with a
known answer. It passed all 15 checks on 2026-10-30:

| known answer | result |
|---|---|
| recover an injected affine from two masks | max param error **0.085** (0.15 for a similarity) |
| IoU at the recovered map | **0.995** (similarity 0.948) |
| **no effect**: identical views → D must be 1 | D_good **1.05**, D_scr **1.05** |
| **the trap**: support cut to the low-z half | same-cell D **1.05** while the full-set baseline inflates the ratio **6.15×** → the naive baseline would have reported a huge false win |
| **mechanism**: specular in one view only + a shared scratch | D_good **4.55**, D_scr **1.01** → effective |
| **sign axis**: same cells, opposite signs | p95 at the |z| AND **3.63** → **0.67** with the sign required |
| refused dump handling | the real empty-belt dump is rejected: `and.raw is all 2` |

The trap test is the important one: with a **known zero effect**, the naive full-set
baseline reports a 6× "improvement" while the same-cell baseline reports 1.05. That is the
false "the AND works" the brief names, reproduced deliberately and caught.

`--verify-pair`, `--sweep-dilution`, `--audit-calib`, `--selftest` are all offline; only
`dl/and_dump_20261030.py` talks to the station, and only for the 27 placements above.

---

## 7. What remains unproven (stated either way)

* **The AND's effect on the board population is not measured.** Coverage, the paired Δ with
  its CI, the before/after percentiles, the sign variant, the sensitivity table and the kill
  line are all **[PENDING]** the 26 dumps. No number in this file is a stand-in for them.
* **The board-plane map for the 2026-10-30 reference pose is not measured.** The 1.16 px /
  107-inlier map is from 2026-10-26; it is used only as a cross-check. The primary map comes
  from the good boards' dumped masks and is validated per board by IoU.
* **Whether the two views' residuals share a common-mode component** (which decides whether
  the AND can lower the good tail at all) is unknown; the sign-agreement rates on the dumps
  will measure it.
* **Whether `and_scale = 0` is a capture artifact or a real word bug** is not settled here;
  the dump will reproduce the firmware's formula from the masks.
* **The camera-1 reference quality** (`cam1_refq`) is a single state word with no per-view
  quality numbers (recorded in `dl/ROOTCAUSE_CAM1_MASK_20261030.md` §7); a reference that is
  silently poor would make every residual on the scratch boards look different for a reason
  other than the defect.
* **The display / bench state** is not looked at and nothing here claims it.

## 8. Protocol deviations (recorded, not smoothed over)

* **ECC direction.** The first draft fed `cv2.findTransformECC` an inverted matrix pair and
  inverted its result. The synthetic known-answer test caught it (recovered translation off
  by 46 cells, IoU 0.36). Fixed and re-verified: the returned matrix is already
  cam0-cell → cam1-cell, the initialisation is not inverted, and it recovers the injected
  affine to 0.085. The fix was made **during the selftest, before any board dump existed**,
  so it changes no number from the board.
* **No other deviation.** The recipe, the board set, the statistics and the kill line are
  the ones committed in `dl/AND_OFFLINE_20261030_PREREG.md`; nothing in this file was
  chosen after looking at dual-view data, because there is none.

## 9. Reproduce every number in this file

```text
python dl/and_offline_20261030.py --audit-calib        # §2.1
python dl/and_offline_20261030.py --verify-pair         # §2.2
python dl/and_offline_20261030.py --sweep-dilution      # §2.3, §3
python dl/and_offline_20261030.py --selftest            # §6
python dl/and_offline_20261030.py                       # §4, once the dumps exist
```
