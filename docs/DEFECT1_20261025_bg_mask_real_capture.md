# Defect 1 (2026-10-25) — the empty-belt background is now sampled at the pitch the mask reads

Build **`EBF0919B`** (source hash from `dl/build_id.py`), flashed with
`ps_fft_dual/strict_load_cores.tcl` only: no bitstream, no power cycle, no VDMA poke.
Board was running stage E's `DE379078` before this. Second defect's build (on top of
this one) is `DE833091`, reported in `dl/DEFECT2_20261025_reg_confidence.md`.

Two changes, one defect: the background grid is filled by the sampler every reader
expects, and `BG_MASK_THR` is chosen from a sweep over a REAL empty-belt capture. The
registration, the fine pass, the verdict rule, the AEC, the averaging, the persistence
window, the amplitude/area thresholds and the display layer were **not touched**.

---

## 0. What the brief said, and what the first measurement said

The brief: with a real empty-belt background on the board, `MB_BG_CELLS` = 10,414 and the
part mask on the bare belt read `MB_PART_RAW` 419..466 / `MB_PART_PTS` 365..408, i.e. the
belt classified as "not background"; `BG_MASK_THR` 20 was below the belt's measured 8x8
residual (mean 2.74 / p95 12 / **max 45**).  All of that reproduces here.

**But the threshold was not the only cause, and it was not the biggest.**  Measured first,
on the board's own dumped buffers (`.tmp/stF/now1`, 11:45, build `DE379078`):

| test | measured |
|---|---|
| `BG_GRID_BASE`'s RIGHT half vs its LEFT half | mean\|d\| **0.65**, corr **1.000** |
| the same test on correct 8-px grids (`cell_mean8(live)`, the host-adopted stage-E grid) | 22.5 / 0.82 and 22.4 / 0.82 |
| cells whose read leaves the 2,764,800-byte capture store | **7,200 of 14,400** (up to 2,757,122 bytes past its end) |
| stored grid's mean, rows 0..44 vs rows 45..89 | 98.7 vs 108.0 (two different sources) |
| \|live lattice − stored grid\| after the median-ratio scale | median **46 grey** |
| the mask `part_masks()` would build from it at thr 20 | raw **8,934** > `BG_AREA_MAX` 7,200 → `MB_PART_BGWHY` 3 |

A period-80 duplication with correlation 1.000 is not a property of the belt. It is the
signature of a 16-pixel-pitch sampler indexed as an 8-pixel grid: for `gx >= 80` the base
column `gx*16` comes back at `(gx-80)*16` one source row down, and for `gy >= 45` the base
row is past row 720, i.e. past the store.

**THE CAUSE, in the source.** `bg_take()` filled the 160x90 8x8-cell grid with
`cell_mean4(src, gx, gy)` — the comparison's **16x16-cell, 5x5-box** sampler
(`DIFF_CELL` 16, `DIFF_W/H` 80x45), while `GRID_W/GRID_H` is 160x90 and every reader of
that grid (`bg_bbox()`/`bg_align()`, `bg_scale_median()`+`bg_diff_fill()` for the part
mask, and the host-adopted grid written by `MB_CMD = 18`) uses `bg_cell_mean8()` —
four GREEN pixels at +0/+4 inside each 8x8 cell, exactly `latt_point()`.  `git blame`
dates the line to **f0a34602, 2026-10-23**, so the empty-belt grid has never been the
quantity the mask subtracts from it.  This is the same failure the comparison's own note
at `cell_mean4()` records: *the two sides of a difference must sample the same way, or a
scene nobody touched reads a mask.*  It had not been caught because every measured mask
before today used a HOST-WRITTEN background (stage E's calibrated synthetic grid), which
was correct.

---

## 1. The fix

`ps_ui/main.c:5768` (`bg_take`), one call:

```
-            uint32_t v = cell_mean4(src, gx, gy);
+            uint32_t v = bg_cell_mean8(src, gx, gy);
```

with the measurement above written at the site, and the note at `BG_GRID_BASE`'s
definition corrected (it used to claim this arithmetic without having it).

Consequences, all measured on the board after the flash:

| quantity | before (stage E `DE379078`) | after (`EBF0919B`) |
|---|---|---|
| `MB_BG_STATE` after `MB_CMD = 12` | 1 | 1 |
| `MB_BG_CELLS` on the BARE belt | 8,494 .. 10,393 | **0** (0..15 over 24 s / 17 comparisons) |
| `MB_BG_MEDD` (median \|live*scale − bg\|) | not published (rule refused) | **1 .. 2 grey** |
| `MB_PART_BGWHY` | 3 (area) | **0** (the background rule is the answer) |
| `MB_PART_RULE` (1 = background) | 0 (green fallback) | **1** |
| `MB_PART_RAW` / `MB_PART_PTS` on the bare belt | 352..466 / 304..408 | **0 / 0** |

So the presence word and the part mask both read "empty belt" on an empty belt, which is
what the acceptance asks for, and the background rule now actually runs.

---

## 2. The threshold, swept on the real captures

Inputs: the firmware's own averaged live lattice on an EMPTY belt (`LATT_BASE`), the
firmware's own empty-belt grid, and four real part frames with the PCB in view (the 11:27
reference and the three known-transform references).  All at the 8x8 pitch the fixed
sampler produces.  Instrument: `ps_ui/stF_mask_sweep.py` (the same erosion and cluster
rule as `part_masks()`).

The empty-belt residual distribution over 14,400 cells: **mean 10.74, p50 6, p90 22,
p95 22, p99 23, max 25 grey**.  (The synthetic background stage E calibrated against read
2.74 / 12 / 45: the real one has a fatter body and a shorter tail.)

| `BG_MASK_THR` | bare-belt mask raw / pts | real part mask pts (min / median / max of 4 frames) |
|---|---|---|
| 20 (shipped) | **1,248 / 831** | 632 / 773 / 1,063 |
| 21 | 245 / 214 | 605 / 753 / 1,022 |
| 22 | 8 / 4 | 566 / 721 / 967 |
| 23 | 1 / 1 | 488 / 685 / 938 |
| **24 (chosen)** | **0 / 0** | **471 / 648 / 841** |
| 25 | 0 / 0 | 451 / 602 / 793 |
| 28 | 0 / 0 | 425 / 492 / 598 |
| 30 | 0 / 0 | 405 / 461 / 530 |

**Why 24.**  It is the first threshold at which the bare-belt mask is ZERO (at 20 the belt
itself clears `PART_MIN_PTS` 400, i.e. an empty belt could be registered as a part), and it
is the empty belt's p99 + 1, so not one cell of the measured noise passes it.  It also
keeps the largest part margin: every one of the four real part frames still clears the 400
floor (min 471 = 1.18x, median 648 = 1.62x).  At 30 the worst real part reads 405, i.e.
1.01x the floor, and a slightly darker frame would be refused.

**Verified on the board at 24** (build `EBF0919B`): bare belt `MB_PART_RAW` 0 /
`MB_PART_PTS` 0; then the 11:27 PCB reference injected with `MB_CMD = 17` →
**`MB_PART_REF` 667, `MB_PART_RRULE` 1** (1.67x the floor).  With the second defect's build
(`DE833091`), a fresh reference of the real defective board in view read
`MB_PART_RAW` **764** / `MB_PART_PTS` **764** (1.91x the floor), `MB_PART_RULE` 1,
`MB_PART_RRULE` 1, `MB_PART_BGWHY` 0 — no fallback.

**Stated limitation.** 1.18x is the worst measured part margin, not a comfortable one; the
974-point part mask stage E published was optimistic by construction (its background
copied the belt under the part from the frame being segmented).  And the real PCB's white
silkscreen resembles the belt, so the mask covers the board's dark regions (~650-760 of the
board's 1,930-cell box), not its whole silhouette.

---

## 3. Cost

| item | stage E (`DE379078`) | this build (`EBF0919B`) |
|---|---|---|
| `.text` | 107,180 | **107,276** |
| `.data` | 92 | 92 |
| `.bss` | 11,520 | **11,516** |
| image end (incl. `.bss`) | 0x1D008 (118,792) | **0x1D064 (118,884)** |
| **OCM free** | 12,280 | **12,188** |
| DDR | — | unchanged |

Build: `build.ps1` 13 files, **0 mailbox collisions** (336 words, 336 distinct indices), all
layout checks pass, only the four pre-existing warnings.  No new mailbox words, so
`dl/MB_WORDS_20261025.md` and `dl/mb_map_20261025.tcl` are unchanged.

---

## 4. What changed, by file and line

| site | line | change |
|---|---|---|
| `bg_take` sampler | `ps_ui/main.c:5768` | `cell_mean4` → `bg_cell_mean8`, with the measurement at the site |
| `BG_MASK_THR` | `ps_ui/main.c:3145` | 20 → **24**, with the sweep table at the site |
| the two notes it invalidated | `ps_ui/main.c:3088-3100`, `3140` | `BG_THRESH` is no longer the same number as the mask's, and `BG_GRID_BASE` is now built with the arithmetic its note always claimed |
| instrument, the sampler evidence | `ps_ui/stF_bg_probe.py` | the duplication test, the out-of-store count, the mask replay |
| instrument, the sweep | `ps_ui/stF_mask_sweep.py` | the threshold table and the two populations |
| harness | `ps_fft_dual/stF_bg_20261025.tcl` | `MB_CMD = 12` + a 24 s watch of `MB_BG_CELLS` / `MB_PART_PTS` |
| harness | `ps_fft_dual/stF_dump_20261025.tcl` | the buffers this needed, incl. `GREY_BASE` |

---

## 5. What remains unverified

1. **A real part in view, at the moment of the capture.**  The board was off the belt when
   the empty-belt background was captured, so the part-side counter (mask 667) was measured
   through the firmware's *reference* path (`MB_CMD = 17`, the real PCB image) and the
   live-path part mask with `EBF0919B` could not be measured until the board came back.
   With `DE833091` and the board in view it read 764 (section 2), so both paths are now
   measured — but not in the same comparison.
2. **The good-board margin.**  `1.18x` is the worst of four reconstructed frames.  No good
   board was on the belt; the operator's good PCB is the experiment.
3. **The bracket's phase.**  The live mask input is the mean of 8 frames and the measured
   frames alternate between two exposures ~1.5x apart; the background is a single frame.
   The empty-belt residual above (max 25) includes that mismatch, which is why the
   threshold sits at 24 and not at 12.  A background captured as an 8-frame mean would
   lower it and is the natural next step if a larger part margin is needed.
4. **`MB_CMD = 18` can refuse a good background once.**  Measured twice: the first adopt
   after a flash returned `MB_BG_STATE` 5 and the second returned 4, on the same buffers
   (the adopt's check runs on ONE current frame, whose exposure phase can be either side
   of the bracket).  A retry is the workaround; making the check phase-tolerant is a
   follow-up, not part of this defect.
5. **The other, larger margin.**  `MB_BG_CELLS` on the bare belt reads 0..15 rather than
   exactly 0, i.e. the presence detector is no longer seeing the belt as a part but it is
   not blind either; `BG_MIN_CELLS` (32) is unchanged and the empty belt stays below it.
