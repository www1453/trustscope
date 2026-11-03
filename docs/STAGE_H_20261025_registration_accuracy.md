# Stage H (2026-10-25) — the registration's accuracy: what was mask-shaped, what was not

Task: make the registration's cost independent of the mask's shape and bring the published
transform inside 2-3 source px / 0.3 deg on the known-truth pairs, without loosening the
confidence gate (`REG_CONF_LIM` 192) or the widened-cold-search escalation (`091ce9a`).

**Headline. (1) The brief's premise is only half true and the false half is measured: the
FINE cost's minimum is not mask-shaped (it does not move under six baseline-mask variants),
and the two mask-shape-independent cures the previous session recommended were both measured
and rejected. What WAS mask-shaped is the coarse stage's SAMPLING -- a ~65-point,
nearest-sampled, stride-2 surface whose minimum sat 20+ half-res px from the truth. That is
fixed in `main.c`, and a joint refine seeded at the reference's identity prior reaches the
fine minimum. (2) The four-good-unit population was measured in full: three units are under
the limit with margin (DAREA max 4 / 3 / 5), unit #3 is not (max 8, 4 NG rows in 23), and on
the comparison's OWN cell quantity the firmware's transform for #3 is 0.23 deg from that
quantity's optimum -- so the remaining spread is UNIT-TO-UNIT difference, not alignment, and
**the spread did not narrow**. (3) The defective board was not established: the board that
arrived when it was requested is a clean good board in the dumped frame. (4) Two of four
injected known-truth pairs land inside 2-3 source px / 0.3 deg; two miss (3.25 px / 0.57 deg
and 3.6 px / 0.0 deg). (5) One claim sent mid-session ("unit #3 is 2.12 deg from the truth,
so the alignment is the cause") is RETRACTED in section 7, and an angle refinement approved
on the strength of it was withdrawn before implementation.**

---

## 1. The instrument, and the check that makes it usable

`ps_ui/stH_reg_points.py` is `reg_score()` in Python: same Q15 sine table, same Q12 mapping,
same bilinear weights, same mask rules and floor, same 1/16-gm output. It builds `BASE_GM`
from `grey_base.raw` with `gm_base_fill()`'s operator and `LIVE_GM` from the dumped source
frame with `gm_latt_fill()`'s.

**Known-answer check against the board's own word**, on `.tmp/stG/accept1` (the good
reference / defective live pair, `mb_all.bin`): the replay returns **122 over 325 points** at
the held identity where the board published `MB_REG_INCERR` **110** over `MB_PART_USED`
**302**. Same place, same order; the differences come from the live frame being a later
capture than the board's own comparison (the live gradient is single-frame) and from the
part mask having moved 865 vs 854 points. A port that did not reproduce that number would
not have been used to choose anything.

## 2. What the mask does and does not shape — the deciding measurement

**The fine minimum is mask-stable.** Scoring the same pair with the baseline mask dilated
one cell, eroded one cell, shifted by one cell in x or y, or replaced by a structure
threshold (the six variants below), the stride-1 sub-pixel minimum stays at the same place:

| baseline mask | points | identity score | truth score | argmin (half-res px) | dist to truth |
|---|---|---|---|---|---|
| dumped (background rule) | 482 | 122 | 88 | (16,2) | 1.5 |
| dilated one cell | 787 | 135 | 98 | (15,2) | 1.5 |
| eroded one cell | 230 | 119 | 91 | (16,2) | 1.5 |
| shifted +2,0 cells | 482 | 112 | 88 | (15,2) | 1.5 |
| shifted 0,+2 cells | 482 | 127 | 97 | (15,2) | 1.5 |
| structure threshold | 122 | 135 | 143 | (16,3) | 1.5 |

So the mask changes the SCORE LEVEL (112..135 at the identity), never the LOCATION of the
fine minimum. What the level does is decide whether the confidence gate escalates and whether
a margin is met — that is the mechanism by which changing the reference mask from the green
rule's 534 points to the background rule's 482 changed the published answer, not a
mask-shaped objective.

**The coarse surface is what was wrong.** At stride 2 the double rule scores ~65 points. The
289-candidate ±128 grid, nearest-sampled:

* its winner is (32,0) at 87 where the truth basin reads ~100; only **14/289** candidates are
  scoreable at all. The search descends into that basin: the full stage sequence on the
  replay publishes **(34,0)** = **35 source px** from the truth, while the fine surface's own
  minimum is **3 source px** from it.
* nearest vs bilinear at ONE fixed transform (40,8): **79 vs 101** — a 22-unit error
  introduced purely by the sampling; that spurious 79 was the coarse winner.
* at stride 2 the surface is a parity artifact: at (32,-1) the even-even lattice subset
  reads **77** while the odd-odd subset reads **123**; at the true basin (16,3) they read
  **79 and 74**. The "minimum" belonged to the sampled subset, not to the alignment.

## 3. The two recommended cures, measured and rejected

**Option 1 — structure-gated points, baseline mask dropped from membership.** Points chosen
by live gradient strength (gm >= 2/3/4/5/6) inside the live mask, no baseline mask test:

* the truth's score rises **88 -> 125..178** (the extra points are the contamination edges the
  good reference does not have — the baseline mask was doing OUTLIER REJECTION, not just
  carving a region);
* the coarse surface goes flat (187..245 over the whole ±128 grid) and the full search
  publishes **88..97 source px off** (six thresholds, all worse than shipped).

**Option 2 — trimmed SAD.** Trimming the worst q of the per-point differences on the shipped
point set: at the coarse level q=0.2/0.3/0.4/0.5 puts the winner at (64,32)/(48,32)/(64,32)/
(16,32) with the truth-nearest candidate ranked 3rd..8th, and it divides the score by ~4
(identity 122 -> 38 at q=0.3), which would make the fixed `REG_CONF_LIM` 192 stop
discriminating. Rejected on both counts.

## 4. What changed in `ps_ui/main.c`

1. **Stages 1, 1b, 2, 5, 6 score SUB-PIXEL** (`reg_score(dx,dy,2u,1u)`; they sampled nearest
   before). This is the accuracy fix: on the three same-surface known pairs the stage
   sequence's published error goes **5.1 / 2.8 / 3.1 -> 1.0 / 0.2 / 0.1 source px**
   (`ps_ui/stH_search_sim.py --pairs`).
2. **`g_reg_phase` / `reg_score_phase_pair()`** — the two-parity average described in
   section 2, used by the joint refine's wide sweeps only. Cost: two stride-2 scores instead
   of one (~130 points per candidate instead of ~65).
3. **`reg_joint_refine()`** — one joint refinement of (dx,dy,angle,scale): ±20 half-res px at
   4-px steps (two-parity), then angle ±1.00 deg at 0.20, then scale ±4/256 at 1, then
   translation ±2 at 1-px on the full stride-1 grid, then the same two parabolas and the same
   stride-1 3x3 the cold search ends with. Every sweep includes its seed, so it can only
   lower the score. Measured offline, seeded at the failing pair's identity prior: it returns
   **(15.06,4.00) half-res px, error 61, against the independent truth (14.5,3.5) and the
   prior's 110** (`ps_ui/stH_seedref.py`).
4. **`g_reg_seeded`** — `ref_take()` seeds the held answer with the identity because the
   reference frame is a live frame. That prior can no longer win by default: while it is
   unmeasured the HOLD shortcut is skipped, the joint refine runs from it, and the result
   must earn the move by the SAME far/near margin and stay under the SAME `REG_CONF_LIM`
   192. On the dumped pair the prior's own score is 110, i.e. UNDER the gate at a
   14.5-half-res-px offset — which is exactly why the previous build held it for 21
   comparisons.
5. **The confidence gate and the widened escalation are untouched**: same mechanism, same
   code paths, `REG_CONF_LIM` 192, `REG_ERR_LIM`, the warm/jump margins, the re-aim bound
   and the persistence window are not changed.

Cost (build): `.text` 109,948 (+1,704 vs 108,244), `.bss` 11,532, image end 0x1DAF4
(121,588), **OCM free 9,484 B**, no new buffer, no new mailbox word, no bitstream. Steady-
state search `MB_REG_TICKS` **5.7M = 17 ms** (was 18.4 ms); the first comparison after a
reference (joint refine + possibly a cold solve) measured **68.4M = 204 ms** once — a real
cost regression on that one comparison, reported rather than hidden.

## 5. Board measurements

Firmware flashed with `ps_fft_dual/strict_load_cores.tcl` only (no bitstream, no power cycle,
no VDMA poke). The empty-belt background from the earlier session survived the reflash and
was adopted with `MB_CMD = 18` (`MB_BG_STATE` 4, `MB_BG_CELLS` 1880, `MB_PART_BGWHY` 0); both
masks then ran on the background rule (`MB_PART_RULE` 1, `MB_PART_RRULE` 1).

### 5.1 Still scene, acceptance 4 — MEASURED (380 judged comparisons over the four units)

The reference unit (#1) alone, two runs of the still scene, one row per judged comparison
(`ps_fft_dual/stH_watch_20261025.tcl`): 195 rows, `MB_DIFF_N` 72..381.

| quantity | measured |
|---|---|
| verdict | **PASS on 195/195** |
| refusals / CANNOT JUDGE | **0 / 0** (every row `MB_REG_STATE` 1, `MB_DIFF_OK` 1) |
| `MB_DIFF_DAREA` | **0 x108, 1 x71, 2 x15, 4 x1** (max 4, mean 0.54); no PASS with DAREA >= 8 |
| `MB_REG_INCERR` | 32..44 (gate 192) |
| `MB_REG_MODE` | 2 (HOLD) on every judged row |
| held transform | within a few source px of the reference: (0,0,0,256) -> (36,6,+0.12,258) -> (4,0,-0.17,255) over the run |
| `MB_REG_TICKS` | 5.7M = 17 ms |

### 5.2 Known-truth pairs, acceptance 1 — MEASURED, PARTIALLY MET

Exact truth by construction: a reference frame was shifted by an integer number of SOURCE
pixels and injected with `MB_CMD = 17`, so the true transform is `dx16 = -16*Sx`,
`dy16 = -16*Sy`, 0.000 deg, scale 256. (The sign convention is checked by the h1 result:
publishing -512 against a truth of -496 would be +496 under the opposite convention.)

| pair | injected shift (src px) | truth (dx16, dy16, deg, scale) | published | error |
|---|---|---|---|---|
| h1 | +31, -9 | -496, +144, 0, 256 | -512, +130, +0.14, 255 | **1.0 / 0.88 src px, 0.14 deg** |
| h2 | +57, -18 | -912, +288, 0, 256 | -896, +260, +0.21, 255 | **1.0 / 1.75 src px, 0.21 deg** |
| h3 | -21, +13 | +336, -208, 0, 256 | +388, -244, +0.57, 256 | 3.25 / 2.25 src px, **0.57 deg** |
| h4 | +4, +2 | -64, -32, 0, 256 | -6, -6, 0.00, 259 | 3.6 / 1.6 src px, 0.00 deg |

So **2 of 4 pairs are inside 2-3 source px and 0.3 deg**; h3 misses the angle and h3/h4 the
position by ~0.5-1 source px. The mechanism is visible in the numbers: h1/h2 are placements
the joint refine reaches and resolves (their truth is at (15.5,4.5) and (28.5,9) half-res px,
and the refine's stride-1 local stage resolves to ~1 source px); h4 is a 2-half-res-px
placement where the single-frame gradient cost's contrast is the same size as the frame-to-
frame term the stage-0 note measures (up to 80 units), so the refine cannot see it: it
published ~0 instead of -4 source px. That is the objective's resolution floor, not the
search's basin.

### 5.3 Defective board vs good reference, acceptance 2 — NOT ESTABLISHED

Two requests for the defective board were relayed; at the end of the measured session the
board in the camera's view was still a clean good board (the dumped 1280x720 frame shows a
clean green PCB with the ME-42A silkscreen, no contamination; the transform had changed from
unit #4's, so a swap HAD happened, but what arrived looks like another good unit). Measured
on that board: 30 rows, `MB_DIFF_DAREA` 2x16, 3x7, 4x2, 6x5, 29 PASS + 1 withheld, 0 NG.

**If that board is in fact the defective unit, this is a FALSE ACCEPT and is the most serious
result of the session**; if it is another good unit (most likely, given the clean frame), the
defective measurement is simply not made. The distinction cannot be made from the image at
this resolution -- it needs the operator to say which physical unit is in view. It is
therefore recorded as NOT ESTABLISHED, not as PASS and not as NG.

### 5.3b Acceptance 1's named pair — NOT MEASURED on the board

The good-reference / defective-live pair (the brief's (14.5,3.5) half-res px, +0.30 deg,
0.996) needs the defective board. Replayed on the previous session's dump of exactly that
pair, the new flow publishes (15.06,4.00) = **1.1 source px** from the stG_align truth at
error 61 against the prior's 110, adopted by the 32-unit far margin; the angle is -0.23 deg
against the instrument's +0.30 (the firmware's own cost prefers its answer: 61 against 88).
Not claimed as a board result.

### 5.4 The four good units, acceptance 3 — MEASURED, AND THE SPREAD DID NOT NARROW

The operator placed the reference unit and three more good units, one at a time, against the
ONE reference taken on unit #1 (never retaken). Rows are read from the mailbox only.

| unit | rows | MB_DIFF_DAREA (count x rows) | max | verdict | alignment the registration found |
|---|---|---|---|---|---|
| #1 (reference, vs itself) | 195 | 0x108, 1x71, 2x15, 4x1 | **4** | PASS 195, 0 refused | within a few source px of identity |
| #2 | 138 | 1x47, 2x89, 3x2 | **3** | PASS 136, 2 settle-gate withheld | (17.9, 6.4) src px, -0.38 deg |
| #3 | 23 | 1x1, 2x1, 4x10, 7x6, 8x4 | **8** | PASS 18, **NG 4**, 1 withheld | (-6.0, 8.5) src px, -1.52 deg |
| #4 | 29 | 2x25, 3x3, 5x1 | **5** | PASS 27, 2 settle-gate withheld | (38.8, 16.5) src px, -0.70 deg |

Three of four are under the limit (8) with margin; **unit #3 is not, and its four NG rows are
a false reject on a board the operator says is good.** Before this change the same population
read DAREA 0 / 6..8 / 3 / mixed (5 PASS + 3 CANNOT JUDGE). The after-spread {0..4, 1..3,
4..8, 2..5} does **not** narrow the range: the spread is NOT alignment-dominated on this
population.

**The measurement that says so.** Unit #3 was the candidate for an alignment explanation, so
the comparison's OWN fine-cell quantity (`cell_mean8` vs `ref_cell8` at the published
transform, `ps_ui/stH_celldiff.py`) was computed on the dumped pair for the candidate
transforms:

| transform | mean abs cell difference | cells > 30 |
|---|---|---|
| the firmware's (-96,+136,-152,257) | **5.23** | **9** |
| the identical identity | 6.93 | 18 |
| the full-resolution fit's answer (-40,+88,+60,255) | 9.84 | 37 |
| the joint residual minimum (-96,+168,+200,257) | 13.54 | 42 |

and an angle scan of that same cell quantity at the firmware's own translation puts its
minimum at **-1.75 deg** (4.90, 5 cells > 30) against the firmware's -1.52 (5.23, 9 cells >
30). The firmware is **0.23 deg from the comparison's own optimum**, and the pair still has
~5 cells beyond the amplitude threshold there: unit #3's DAREA cannot be aligned away. An
angle refinement scored on the full-resolution fit's residual would have moved it to +0.6..
+2.0 deg, where this same comparison quantity is 4-8x worse (37-42 cells > 30). That change
was NOT made for that measured reason (see the retraction note in section 7).

Consequence, stated plainly: **the remaining spread is unit-to-unit difference, not the
alignment.** The registration's accuracy on units #1/#2/#4 is good (their DAREA 1..5 matches
the residual of two physically different boards), and unit #3 differs from the reference unit
by enough surface to cross the limit at ANY alignment — no registration change can fix it.

## 6. What is measured, what is not

* MEASURED: the fine minimum is mask-stable (section 2, six mask variants); the coarse
  surface was the defect (nearest vs bilinear 79 vs 101 at a fixed transform, 14/289
  scoreable, parity artifact 77 vs 123); the two recommended cures make it worse (section 3).
* MEASURED: acceptance 4, 333 judged comparisons across the four good units, 0 registration
  refusals, no PASS with DAREA >= 8; max DAREA 4 / 3 / 8 / 5.
* MEASURED: acceptance 3 -- three of four good units under the limit (max 4, 3, 5), unit #3
  at max 8 with 4 NG rows, and on the comparison's own cell quantity the firmware's transform
  is 0.23 deg from that quantity's optimum (mean|d| 5.23 / 9 cells > 30 there, against 37 and
  42 for the two candidate "truths"). **The spread did NOT narrow; the remaining spread is
  unit-to-unit difference, not alignment.** False-NG on good units: 1 of 4 (unit #3).
* MEASURED: 2 of 4 injected known-truth pairs inside 2-3 px / 0.3 deg; h3 3.25 px / 0.57 deg
  and h4 3.6 px / 0.0 deg miss (section 5.2).
* NOT ESTABLISHED: acceptance 2 and acceptance 1's named pair -- the board that arrived when
  the defective unit was requested was a clean good board (section 5.3). Not claimed.
* APPROVED-THEN-WITHDRAWN CHANGE: a full-resolution intensity angle refinement was approved
  by the parent on the (later retracted) claim that unit #3's angle was 2.12 deg from the
  truth, and WITHDRAWN when `stH_celldiff.py` showed that quantity would move the angle to a
  place where the comparison's own cell quantity is 4-8x worse. Not implemented. The
  retraction is section 7.
* KNOWN COST REGRESSION: the first comparison after a reference measured 68.4M ticks = 204 ms
  (joint refine + cold solve); the steady state is 17 ms. No threshold or margin was tuned to
  hide it.
* STILL UNVERIFIED: the joint refine's behaviour on a reference whose part is more than ~3 mm
  from the prior (its window is ±20 half-res px = ±40 source px = ±3 mm); beyond that the
  cold stage sequence still runs and is what publishes, exactly as before. Also unverified:
  whether the clean board in view at the end was the requested defective unit (section 5.3).

## 7. Retraction, and the threshold the data implies

**Retracted claim.** "Unit #3's published angle is 2.12 deg from the truth, so the alignment
is why #3 fails." It was sent to the parent and is withdrawn here.

* Why it was wrong (1): the truth quoted came from `stD_reg_fit.py` run with `--th -3.0 0.2`,
  a search box that cannot return a positive angle above +0.2 deg. Unboxed, the same fit
  finds a lower residual at +2.0 deg (9.56 against 14.45 grey at +0.6), so the "truth" was
  an artifact of the box.
* Why it was wrong (2), and this is the general point: that fit minimises 16 single-pixel
  samples per cell, which is NOT the quantity the comparison judges. The comparison's own
  fine-cell arithmetic (`ps_ui/stH_celldiff.py`: `cell_mean8`/`ref_cell8`/`ref_at`, 3x3 box
  means at +2/+6, base-mask agreement) puts the firmware's transform FIRST of the candidates
  (mean 5.23, 9 cells > 30) and the fit's answer 4x worse (37). An angle refinement scored on
  the fit's residual would have minimised the wrong quantity. It was approved by the parent on
  the strength of the retracted claim and withdrawn on this measurement.
* What replaced it: the comparison-quantity angle scan, which finds the optimum at -1.75 deg
  against the firmware's -1.52 -- the firmware is 0.23 deg from its own objective's best.

**The threshold question.** The four good units' DAREA maxima are 4, 3, 8 and 5; the failing
limit is `DIFF_LIM` 8 (0..7 pass, 8+ fail). Unit #3 sits exactly ON the limit, so any
production threshold that passes it must be at least 9. The defective population measured by
the previous session with a good reference was DAREA 9..11 -- i.e. its MINIMUM is 9. There is
therefore **no threshold that both passes unit #3 and rejects the defective unit with any
margin**: the good maximum (8) and the defective minimum (9) are adjacent. Raising the limit
to 9 would pass unit #3 and also pass the defective unit's lowest readings; keeping it at 8
rejects unit #3 four times in 23 rows (a 17% false-NG rate on that unit, 1 of the 4 good
units). This is a property of the comparison's amplitude/area rule, which this session was
told not to touch -- it is reported, not changed.

