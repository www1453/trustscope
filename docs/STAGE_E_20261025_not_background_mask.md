# Stage E (2026-10-25) — the part mask is now "not background", not "green"

Build **`DE379078`** (source hash from `dl/build_id.py`, published at `MB_FWID1/FWID2`).
Flashed with `ps_fft_dual/strict_load_cores.tcl` only: no bitstream, no power cycle, no
VDMA poke.  Board was running `97260F62` before this.

One change: the colour-dominance mask is replaced by a background difference, with the old
rule kept as the published audit number and as the fallback, plus a host command to adopt a
saved background.  The registration, fine pass, verdict rule, AEC, averaging, persistence
window and display layer were **not touched**.

---

## 0. The failure this was written for, re-measured first

Board state at 10:48 (defective board on the belt, nothing changed by me yet):

| word | value | meaning |
|---|---|---|
| `MB_PART_RAW` (21) | 283..340 | mask cells before the cluster rule |
| `MB_PART_PTS` (366) | 123..271 | after the cluster rule |
| `PART_MIN_PTS` | 400 | the floor the registration refuses below |
| `MB_PART_REF` (367) | 503 | the baseline's own mask |
| `MB_BG_STATE` (230) | **0** | **no background image exists on this board** |
| `MB_DIFF_OK` (180) | 3 | comparisons refused: the AEC had declared itself stuck |

Two independent blockers were reproduced, not one: the mask is below its floor **and** the
AEC's mask term (stage C) had latched state 3 because of it.  The brief's diagnosis of the
mask is confirmed by the numbers; the AEC latch is a consequence of it that clears by itself
once the mask recovers (measured below: `MB_AEC_STATE` 3 -> 1).

---

## 1. The rule, before and after, with the area numbers

### Before (`main.c:3420-3690` in the previous build, now the fallback)

`score = G - max(R,B)` of the 2x2 samples at +2/+5 inside each 8x8 block, threshold at the
frame's **own median + 12**, 3x3 erosion, then the stage-D cluster rule.  A cell is part
only if the surface is green-dominant.

Measured on the frames the board was comparing (`.tmp/stE/cur/live.raw`, 2026-10-25 10:47):

| quantity | value |
|---|---|
| green mask, eroded, before the cluster rule | **309 cells = 2.15%** of the 144,000-point lattice |
| after the cluster rule | **121 cells = 0.84%** |
| on the board at the same instant (mailbox) | `RAW` 283..340, `PTS` 123..271 |
| `PART_MIN_PTS` | 400 |
| verdict | **CANNOT JUDGE** (registration state 2, every comparison) |

### After (`main.c:3690` `part_masks`, rule at `main.c:3075` / `main.c:3614`)

A cell is part when it differs from the **empty-belt background** by more than
`BG_MASK_THR = 20` grey, with the brightness compensated by the *ratio of the medians* of
the two 8x8 grids, then 3x3 erosion, then the same stage-D cluster rule.  Nothing about the
part's colour is assumed.

Measured on the same frame, through the firmware itself (synthetic background adopted,
section 2):

| quantity | value |
|---|---|
| `MB_PART_RAW` | **974** (then 848..1,009 over a 300 s run) |
| `MB_PART_PTS` | **974** (then 865..1,009) |
| `MB_PART_REF` | 985 (the baseline mask, same rule) |
| `MB_PART_GREEN` / `MB_PART_GCLU` (the old rule, same frames) | 268..361 / 110..280 |
| `MB_BG_MEDD` | 3..5 grey (median \|live*scale - bg\|: the belt's health) |
| `MB_PART_RULE` / `MB_PART_BGWHY` | 1 / 0 on every comparison |
| verdict | the comparison runs (and is PASS on the still scene, NG on a known defect) |

**The old rule is still computed and published on every comparison** (`MB_PART_GREEN` is
exactly what the old build published as `MB_PART_RAW`; `MB_PART_GCLU` is exactly what it
published as `MB_PART_PTS`), so the change is auditable against every historical
distribution.  On this frame the old rule reads 309/121 and the new one 974/974.

### Why the threshold is 20, and what is *not* measured

* The belt's own frame-to-frame noise at this pitch, from two dumps 2 s apart:
  mean **1.4** counts, max 11 over all 14,400 cells.  20 is 14x the mean.
* The part differs from the belt by ~50-100 grey (belt ~152, dark PCB ~119).
* **Not measured: |live - background| on a real captured empty-belt background.**  There is
  none on this board and the belt cannot be emptied without the operator.  That is the one
  number this session could not produce, and it is the acceptance criterion for the
  operator run in section 6.

### Why the compensation is a ratio of medians, not of means (`main.c:3614`)

The presence detector's mean-ratio is biased by the part's own share of the frame.
Measured on the dumped frame with the belt reconstructed under the part: the two grid
**means** are 92.67 and 98.21 (ratio 271/256 = 1.059) while the **medians** are 71 and 73
(263/256 = 1.027); the true light ratio is 1.000, because both frames are the same scene.
On a 152-count belt the mean estimator adds **+9 counts** of pure arithmetic error, nearly
half of the 20-count threshold.  The mask therefore uses the median ratio; the presence
detector keeps its mean (it is not this change's to move) and both are published.

### Staleness: three checks, and the failure directions

`main.c:3690` refuses the background rule and falls back to the old one, publishing why
(`MB_PART_BGWHY`: 1 no background, 2 light out of band, 3 area implausible):

1. `g_bg_ok == 0` — no background has been captured or adopted this boot;
2. the median brightness ratio outside 0.5..2.0 — the same band the presence detector uses;
3. the raw mask over **`BG_AREA_MAX` = 50% of the frame** — "this background is not
   describing this scene".  This bound is measured on the two wrong backgrounds the board
   actually has: the DDR leftover at 0x127A8C00 reads **84%**, the 2026-10-23 dumps
   (`ps_ui/bg_grid.bin`) read **77%**, against **13.4%** for the part's own box.

Both failure directions are safe.  A background taken with the part on the belt gives an
*empty* mask, which is below `PART_MIN_PTS` and refuses.  A stale background that *adds*
belt cells adds cells that are belt in both frames, where the fine difference is ~0.
**Stated limitation:** a localised change on the belt (a new shadow, an object put down)
joins the mask as a false part region; it is bounded by the 50% check and by the baseline
agreement, and it was not measurable today.

### The background is refreshed, and it survives a reboot

* `MB_CMD = 12` (unchanged) captures it from the **empty belt**.  It is refused while the
  AEC is stuck (state 2) or the image clips (state 3), as before.
* **New `MB_CMD = 18`** (`main.c:5669` `bg_adopt`, handler at `main.c:12142`): the host
  writes the two saved buffers back (`0x12700000` 691,200 B, `0x127A8C00` 14,400 B) and the
  firmware validates them with the same check before using them (`MB_BG_STATE` 4 adopted /
  5 refused).  Without this, `g_bg_ok` would be forgotten by every `dow` and the station
  would need the operator to lift the board after every firmware load.

---

## 2. What was NOT available, and how it was substituted (read this before the numbers)

**There is no empty-belt background on this bench, and it cannot be made without the
operator.**  So every board number in section 3 was measured with a **calibrated synthetic
background**: the part's footprint (x 512..1104, y 370..660 — its own box plus a margin) is
replaced, per row and per channel, by the linear interpolation of the belt columns just
outside it, and **the same operation is calibrated on visible belt of the same kind**:

| calibration (visible belt, 1,275 cells) | 8x8-cell error |
|---|---|
| mean | **2.74** counts |
| p95 | 12 |
| max | 45 |

against a threshold of 20.  The files are `.tmp/stE/host/bg_grid.bin` / `bg_img.bin`, built
by `.tmp/stE/stE_mkbghost.py`, and they were written to DDR and adopted with `MB_CMD = 18`.

**This substitution is a limitation, not a detail.**  It cannot measure the belt's own
false-positive rate (the belt outside the footprint is copied from the frame being
segmented, so it is identical by construction), and the operator's real capture must
confirm both the threshold and the belt side.  Every number below says which background it
was measured with.

---

## 3. The four acceptances

### (1) The real defective board must now be judged, not refused — **met for the mask, and the verdict needed a different reference than the brief assumed**

Measured on the board with build `DE379078`, background adopted (`MB_BG_STATE` = 4),
watched by `ps_fft_dual/stE_accept_20261025.tcl`:

| requirement | measured | note |
|---|---|---|
| `MB_PART_RAW` above `PART_MIN_PTS` 400 | **974** (848..1,009 over 300 s) | was 283..340 |
| `MB_PART_PTS` above 400 | **974** (865..1,009) | was 123..271 |
| the comparison runs | **146 judged comparisons, 0 refused** in 300 s | was 0, all refused |
| verdict **NG** with `MB_DIFF_DAREA` >= 8 | **NG, `DAREA` 23..25, `DAMP` 61, `DBOX` (119,63)-(123,67)** on 18 of 18 comparisons | see below |

**The NG is a known-answer defect, not the board's own surface change**, and here is why,
measured rather than argued:

* A reference of the **defective board itself** (fresh `MB_CMD = 9`) is the only reference
  this bench can make, and comparing that board with itself correctly reads **PASS**
  (`DAREA` 0..1).  A QC verdict needs a *good* reference; that is a second board.
* The only good reference available is the image still in `REF_BASE` at 10:47 (an earlier
  placement, dumped to `.tmp/stE/cur/ref.raw`).  Injected with `MB_CMD = 17` it gives a
  healthy mask (`MB_PART_REF` 736, `PART_USED` 611) but **the registration never settles**:
  over 90 s `MB_DIFF_N` stayed frozen at 81, `MB_REG_MODE` was 5 (a new answer adopted) on
  every frame and the transform moved (dx16 1846 -> 1762, angle100 -387 -> +205, scale 291
  -> 267).  The two boards are different assemblies at a 1.14x different scale, and the
  search oscillates on that pair.  Verdict: CANNOT JUDGE — the safe answer, but not the
  NG the acceptance asks for.
* The NG above is therefore the stage-D known-answer stamp (`MB_CMD = 15`, 40x40 px, +60
  grey) at cell **(119,63)** — chosen by *measurement*: of the 104 five-by-five blocks
  fully inside the live-and-baseline agreement, it is the darkest (mean green 65.4), so the
  stamp cannot clip and its full +60 is visible.  `DBOX` came back exactly the stamped
  5x5 block, which is the independent geometric check that `DAREA` is geometry and not
  noise.
* **A stamp at cell (100,65) first read `DAREA` 6 -> PASS.**  That is a finding about the
  bench, not about the mask: that block is on a bright, silkscreen-heavy part of the board,
  where `reference + 60` clips at 255, and part of it lies outside the agreement mask
  (`FVALID` 661 of 858).  With the stamp on a dark, fully judged block the same rule reads
  23..25.  Both runs are in `.tmp/stE` and both are reported.

### (2) Good boards must not regress (3 different PCBs, `DAREA` 0..2, PASS) — **NOT MEASURED, needs the operator**

No good board can be placed without the operator.  What *was* measured is the same
statistic on the board that is on the belt, with a fresh reference of it:

| run | judged | `DAREA` | `FCELLS` | verdict |
|---|---|---|---|---|
| 300 s still, new rule | **146** | max **3** (0 in most rows) | max 14 | PASS on all 146 |
| stage-D reference (old mask) | 154 | max 0 | 0 | PASS on all |

`DAREA` reached **3** where it used to be 0: the judged ROI is now the board's silhouette
(~919 cells) instead of the green solder mask (~500), i.e. about twice as many cells, and
the textured parts of the PCB are now inside it.  The brief's good-board bound is **0..2**,
so this is **inside the bound but with no margin left**, and the good-board run is the
acceptance that matters most next.  It is not a pass; it is a measured risk.

### (3) Still scene: 100+ comparisons, no mask-attributable refusal, no forbidden pair — **met, with one reading of the last clause**

300 s run, fresh reference, one row per judged comparison (`stE_accept_20261025.tcl still
300 900`):

* **146 judged comparisons, 0 refused** (0 mask-attributable, 0 other)
* **all 146 on the background rule** (`MB_PART_RULE` = 1)
* `MB_PART_PTS` 865..1,009 against the 400 floor; `MB_PART_USED` 585..740
* **`MB_DIFF_DAREA` 0 in 143 of 146, max 3**; `PASS with DAREA >= 8`: **0**
* `PASS with the RAW fine count >= 8`: **17** — the raw count is no longer the authority
  (stage D replaced it with `DAREA`); the same pair occurred in stage D's own acceptance
  and was recorded there as correct.  Both counts are reported because the brief's wording
  predates that change.
* earlier runs in the same state: 61 and 22 judged comparisons, 0 refusals, `DAREA` 0

### (4) Registration must not regress — **MEASURED REGRESSION. This is the open item.**

The instrument is the one the brief names, `ps_ui/stD_reg_fit.py`, extended with an
optional search box (`--dx/--dy/--th/--sc`, **defaults unchanged**, so every stage-D number
still reproduces).  The method: build a reference whose true transform is **known exactly**
(the part moved by a chosen amount, the belt left alone — `.tmp/stE/stE_part_shift.py`),
confirm the truth with the independent fit, then compare what the firmware published.
Injected with `MB_CMD = 17`; the injected bytes were verified identical to the host file in
`REF_BASE` afterwards.

| test | independent fit (= truth) | firmware published | error | residual at that answer vs at the truth |
|---|---|---|---|---|
| part +30.5/-9.25 px, -0.20 deg | (-30.50, +9.50, -0.20, 1.000) | (-27.88, +2.25, +1.60, 0.984) | **2.6 px / 7.3 px / 1.40 deg** | 36.84 vs **3.54** grey |
| part +56.5/-18.25 px, -0.40 deg | (-56.50, +18.50, -0.40, 1.000) | (-26.00, +38.25, -0.10, 1.109) | **30.5 px / 19.8 px / 0.30 deg** | 32.99 vs **3.68** grey |
| whole scene +56.5/-18.25, -0.40 deg | (-56.50, +18.50, -0.40, 1.000) | (-34.00, -6.50, +7.37, 1.004) | **22.5 px / 25.0 px / 7.77 deg** | 32.60 vs **2.70** grey |

Before (stage D, archived in `dl/STAGE_D_20261025_roi_amplitude.md` section 1.5): published
**+842** against a fit of **+840** — **0.13 px / 0.75 px / 0.10 deg**.

**Mechanism, read from the code and consistent with every row above.**  The widened
(DIL1/union) cold search is entered only when the shipped cold search **refuses**
(`REG_COLD_FAIL`, `main.c:3900-3920`; `g_reg_widen`).  A displaced part makes the held
answer unscoreable under the old, selective green mask, so the search escalated and found
the displacement.  The new mask is 2x larger and far more permissive: the held answer
*always* scores, the search never refuses, and it publishes a local answer 2.6..30 px away
with a residual ten times the truth's — `MB_REG_MODE` = 2 (HOLD) / 5 (RE-AIM) on every row,
`MB_REG_RULE` = 0 (not widened) on every settled row.

**What is solid and what is not.**  Solid: on three pairs whose truth the independent fit
recovers *exactly* (to 0.5 px / 0.00 deg), the firmware's answer is 2.6..30 px away and its
residual is 10x worse; the same answer was 0.13 px on stage D's pair.  Not solid: my pairs
are *reconstructed* (the part moved by bilinear resampling, the belt under it interpolated)
while stage D's pair was a real physical displacement, so this is not a one-variable A/B of
the mask; and the mask's part in it is inferred from the escalation condition, not measured
directly, because the old build cannot even run on this scene (its mask is 121 < 400, i.e.
it refuses).  **A fix is a registration change (escalate on a low-confidence answer, not
only on a refusal) and is deliberately NOT in this change.**

---

## 4. Cost: OCM, DDR, and what moved

| item | before (stage D) | after | note |
|---|---|---|---|
| `.text` | 105,876 | 107,180 | +1,304 |
| `.data` | 92 | 92 | — |
| `.bss` | 10,972 | 11,520 | +548 (the 512-byte histogram + statics) |
| image end | 0x1C8D4 (116,948) | **0x1D008 (118,792)** | 131,072-byte OCM region |
| **OCM free** | 14,124 | **12,280** | cost **1,844 bytes**, nothing moved out of OCM |
| DDR | — | **+28,800** | two 14,400-byte scratch grids |

DDR, in the free hole between `g_bggrid`'s end (0x126F3840) and `BG_BASE` (0x12700000):

| buffer | address | bytes | why |
|---|---|---|---|
| `PART_LATT` | 0x126F4000 | 14,400 | the 8x8 cell means of the frame the mask is built from, when that frame is not `LATT_BASE` (the reference, the refusal path, the adopt check) |
| `PART_GMSK` | 0x126F8000 | 14,400 | the old rule's mask while both rules are measured |

Both are pure scratch (every byte written immediately before the call that reads it), 16 KB
aligned, CPU-only cacheable DDR, no DMA; **no existing buffer changed address or size**.
0 bytes of OCM.  Build: `build.ps1` 13 files, 0 mailbox collisions (**336 words, 336
distinct indices**), all layout checks pass, only the four pre-existing warnings.
`dl/MB_WORDS_20261025.md` and `dl/mb_map_20261025.tcl` regenerated (335 names).

**Seven new mailbox words**, indices 33..39, free per `dl/mb_free.py`:
`MB_PART_GREEN` 33, `MB_PART_GCLU` 34, `MB_PART_RULE` 35, `MB_PART_RRULE` 36,
`MB_PART_BGWHY` 37, `MB_BG_AGE` 38, `MB_BG_MEDD` 39.  `MB_BG_STATE` gained codes 4
(adopted) and 5 (adopt refused).

---

## 5. What changed, by file and line (build `DE379078`)

| site | line | change |
|---|---|---|
| new words | `ps_ui/main.c:2266-2273` | the seven words above |
| thresholds | `ps_ui/main.c:3075-3076` | `BG_MASK_THR` 20, `BG_AREA_MAX` 7,200 |
| background addresses + state | `ps_ui/main.c:3080-3103` | **moved here** from the stage-3 block, unchanged, so `part_masks` can see them |
| lattice helper | `ps_ui/main.c:3150` | `latt_fill_into(src,dst)` returns the mean; `latt_fill` is now a wrapper |
| new scratch | `ps_ui/main.c:3260-3287` | `PART_LATT`, `PART_GMSK` |
| erosion | `ps_ui/main.c:3484` | `mask_thr_erode()` extracted from `part_masks`, arithmetic unchanged |
| cluster rule | `ps_ui/main.c:3538` | `mask_cluster()` extracted, arithmetic unchanged |
| median | `ps_ui/main.c:3561` | `u8_median()` |
| background diff | `ps_ui/main.c:3577` | `bg_diff_fill()` |
| compensation | `ps_ui/main.c:3614` | `bg_scale_median()` |
| **the rule** | `ps_ui/main.c:3690` | `part_masks(src, latt, dst)`: old rule first (audit + fallback), then the background rule with its three checks |
| reference | `ps_ui/main.c:5797` | `ref_take` builds the reference's own lattice and passes it |
| live | `ps_ui/main.c:6691` | `diff_frame` passes the averaged lattice it already has |
| refusal path | `ps_ui/main.c:6573` | `mask_sample_refused` fills the lattice from the store it just selected |
| adopt | `ps_ui/main.c:5669`, `11891`, `12142` | `bg_adopt()` + `MB_CMD = 18` + its deferral |
| age | `ps_ui/main.c:6655` | `MB_BG_AGE` counted per comparison attempt |
| map | `dl/MB_WORDS_20261025.md`, `dl/mb_map_20261025.tcl` | regenerated, 335 words |
| harness | `ps_fft_dual/stE_accept_20261025.tcl` | new: snap/mask/still/stamp/ref/bg/adopt/injectbg/injectref |
| instrument | `ps_ui/stD_reg_fit.py` | optional `--dx/--dy/--th/--sc` search box, defaults unchanged |
| instruments | `.tmp/stE/stE_bgmask.py`, `stE_mkbghost.py`, `stE_part_shift.py`, `stE_shift_ref.py` | the offline measurements and the known-transform references |
| backup | `backups/20261025_105714__stE_before_bgmask` | `main.c` as it was |

---

## 6. What remains unverified, and every human-dependent step

**Not measured, in the order they matter:**

1. **The registration regression (section 3.4).**  Measured, mechanism identified, not
   fixed.  *Evidence needed to settle it:* the same known-transform pair on a build with
   the old mask and a scene where the old mask is above its floor (a good board).
2. **A real empty-belt background.**  The threshold of 20 and the belt's false-positive
   rate are calibrated against a *reconstructed* belt.  Measured needed: a real capture,
   then `MB_BG_MEDD` (expected 0..8) and the mask's area (expected 3..15%).
3. **Three good boards, `DAREA` 0..2, PASS.**  The still scene on the defective board
   already reaches `DAREA` 3, i.e. the margin under the brief's bound is thin.
4. **The real defective board judged NG against a good reference.**  Blocked by the
   registration, not by the mask (section 3.1).
5. **The AEC's mask term** now sits far above its floor (`PART_PTS` ~950 against 448) —
   the opposite of stage D's finding, but only on this one framing.
6. **The part view** (`MB_PV_*`) derives its box from `LIVE_MASK`, which is now ~2x larger
   and a different shape; the framing was not watched.  *Human:* select the part view and
   confirm the box is stable for 60 s (`MB_PV_N` must not climb).

**Human-dependent steps, with exact instructions.**

* **H1 — take the real background (needed once, then it can be saved and re-adopted):**
  1. Lift the defective board off the belt.  Leave the belt **empty**, hands and tools out
     of the camera's view, the lamp exactly as the station runs.
  2. From the host: `xsdb ps_fft_dual/stE_accept_20261025.tcl bg`  (writes `MB_CMD = 12`).
  3. Check: `MB_BG_STATE` = 1, `MB_BG_CELLS` < 32, `MB_BG_MEDD` 0..8.  If `MB_BG_STATE` is
     2 or 3 the AEC is stuck or the image clips — fix the light, not the firmware.  If
     2/3 persists, `MB_EXP_LOCK` is a host pin: clear it (`mwr 0x10F00000+508*4 0`).
  4. Save the two buffers so this never has to be repeated:
     `xsdb` -> `mrd -bin -file bg_img.bin 0x12700000 172800` and
     `mrd -bin -file bg_grid.bin 0x127A8C00 3600`.  After any later firmware load:
     `stE_accept_20261025.tcl injectbg bg_grid.bin bg_img.bin` (`MB_CMD = 18`, must read
     `MB_BG_STATE` = 4).
* **H2 — a good reference, for the NG verdict:** with a **good** PCB on the belt in the
  framing the station uses, host writes `MB_CMD = 9`.  Check `MB_PART_REF` > 400 and
  `MB_PART_RRULE` = 1.  Do not move the camera afterwards.
* **H3 — the defective board:** put the defective board on the belt where the good one
  was, then read `MB_PART_RAW`, `MB_PART_PTS`, `MB_DIFF_FVALID`, `MB_DIFF_DAREA`,
  `MB_DIFF_DAMP`, `MB_DIFF_DBOX`, `MB_DIFF_VERDICT` over 20 comparisons
  (`stE_accept_20261025.tcl mask 60 700`).  Required: `PART_PTS` > 400, `DAREA` >= 8,
  verdict 1 (NG).  **If it reads PASS, report the numbers — with a registration answer
  2.6..30 px off (section 3.4) a PASS is the expected outcome until that is fixed.**
* **H4 — three good boards:** each placed by hand in the same place, fresh reference each
  time (`MB_CMD = 9`), then 20+ comparisons each.  Expected `DAREA` 0..2 and PASS; the
  measured still-scene maximum on the defective board is already 3.
* **H5 — the J10 jumper** (PIN35 B20 / PIN28 V12) must be out before any power-on.  A human
  check; not observable from software and not touched here.

---

## 7. Reproducing any number above

```
python ps_ui/stE_bgmask.py                     # the rule offline, with the calibrated belt
python .tmp/stE/stE_mkbghost.py                # the synthetic background files
python .tmp/stE/stE_part_shift.py live.raw ref.raw 30.5 -9.25 -0.20
python ps_ui/stD_reg_fit.py <ref> <live> <mask> --dx .. --dy .. --th .. --sc .. [dx16 dy16 a100 sc]
xsdb ps_fft_dual/stE_accept_20261025.tcl snap|mask|still|stamp|ref|bg|adopt|injectbg|injectref
xsdb ps_fft_dual/strict_load_cores.tcl         # firmware only -- the ONLY flashing path used
```

Board left in: build `DE379078`, synthetic background adopted (`MB_BG_STATE` 4), fresh
reference of the defective board, identity held (dx16 0, angle100 0, scale 256),
`MB_DIFF_N` 735, `MB_PART_RAW` 933, `MB_PART_PTS` 933, `MB_PART_REF` 958,
`MB_PART_RULE` 1, `MB_DIFF_FVALID` 789, `MB_DIFF_DAREA` 0, verdict 0 (PASS) on the still
scene.  **The background in DDR is the calibrated synthetic one, not an empty-belt
capture** — a `dow` clears `g_bg_ok`, and `MB_CMD = 12` with an empty belt replaces it
(human step H1).
