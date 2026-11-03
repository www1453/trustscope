# Stage R (2026-10-27): the AREA DEFICIT inside the fitted quad — measured offline

**Firmware: nothing changed.** `ps_ui/main.c` is untouched, nothing was built or flashed,
no board and no xsdb was touched.  Every number below comes from frames already in the
tree, and every one of them is reproduced by `dl/area_deficit_20261027.py`.

The question was whether the *area deficit inside the fitted reference quad* can see a
corner chip — the statistic STAGE_Q recommended after showing that a fitted **vertex**
cannot (`dl/STAGE_Q_20261027_colour_edge_quad.md:208-212`).  This document answers it by
counting that area on real frames, with a known answer (painted chips, §3) and a null (the
same board against itself, §2).

**Short answer.**  The formulation *as written* — "cells inside the outline that are not
board" — does not work: its null on real good boards is **16 to 29 cells** while a 4×4
chip measures **12 to 16**, so the two overlap at every window (§2.1, §5).  The reason is
measured, not guessed: the PCB is **32.2 % non-green by design** (white silk and
components), so "not board" is a property of the board's printing.  Read the other way —
"looks like the belt", the same 2G−R−B rule with the belt population as the positive
class — the null falls to **3 to 12**, and adding the brightness dimension the rule lacks
brings it to **0 to 4**.  In that form the statistic separates a **6×6** chip by only
**1.79 : 1**, and cannot separate a **4×4** chip at all.  **The frames on disk cannot
answer it for the three real corner boards, because there are no frames of them** — §7
gives the exact capture list that would.

---

## 0. What is reused, and what is new

| | |
|---|---|
| colour rule | **2G−R−B**, the firmware's own sampler: four single pixels at +2/+5 inside the 8×8 cell, `part_score`, `ps_ui/main.c:4512-4528`; bytes are B,G,R (`CAM_STRIDE 3840`, `main.c:196`).  Reproduced exactly (`cscore`, `dl/area_deficit_20261027.py:92`).  **Not re-derived.** |
| board threshold | 26, STAGE_Q's validated value (`STAGE_Q:48-61`). |
| expected shape | four robust side lines → the quad.  Trimmed least squares, `TRIM 2.0` cells, corner zones dropped — the estimator `qcost.c` implements (`fit_line`, `:189`; `quad_of`, `:213`). |
| the statistic | `deficit(k, W)` = number of cells whose centre is (a) inside the quad, (b) within `W` cells of vertex *k* (Chebyshev), (c) a deficit cell of the given variant; and `d = max` over the four corners (`deficit_grid`, `:296`). |
| **new** | the brightness dimension (`cluma`, `:102`) and, for the fully relative variant, the belt measured **beside the same corner on the same frame** (`band_mask`, `:270`; `band_level`, `:288`). |

Nobody needs a vertex for this: the quad's **lines** are enough, four comparisons per cell,
no polygon rasterisation and no second buffer.  Vertices are only the window anchors.

### The reference board, as measured (`section_probe`, `:467`)

`.tmp/a1/ref_base.bin` (the dumped `REF_BASE`): cell score mean **−17.29** sd 32.87;
largest 8-connected green group **1,210** cells; **1,731** cells inside the fitted quad.

| side | fit | resid (cells) | points |
|---|---|---|---|
| left | x = −0.3192·y + 62.031 | 0.62 | 25 |
| right | x = +0.1293·y + 92.717 | 0.31 | 23 |
| top | y = +0.0287·x + 47.593 | 0.45 | 52 |
| bottom | y = +0.0116·x + 77.866 | 0.55 | 50 |

Vertices (cell coordinates): TL (46.41, 48.92), TR (99.24, 50.44), BL (37.04, 78.30),
BR (102.94, 79.06).  The board is **52.8 / 65.9** cells wide and **29.4 / 28.6** high, so
the quad is 1,731 cells and its perimeter is **177** cells.

### What is actually inside that quad — the finding the whole of §2 rests on

| 2G−R−B band | cells | share of the quad |
|---|---|---|
| ≤ −45 (belt core) | 8 | 0.5 % |
| −45 … −35 (belt) | 14 | 0.8 % |
| −35 … −20 | 41 | 2.4 % |
| −20 … 0 | 161 | 9.3 % |
| 0 … 26 **white silk / components** | **305** | **17.6 %** |
| > 26 (board) | 1,202 | 69.4 % |

**32.2 % of the board's own area is under the board threshold**, and 17.6 % of it is white
printing.  `STAGE_Q:63-67` said this ("a PCB is *not* uniformly green") and drew the
consequence for the outline; the consequence for an **area deficit** had not been drawn.
It is drawn in §2.

---

## 1. The four variants

The rule has two populations and the deficit can be defined against either, plus a
brightness dimension the rule does not have.  All four are measured, because which one is
"the formulation as written" matters.

| id | deficit cell ⇔ | why it exists |
|---|---|---|
| **D1** | score ≤ 26 | the brief's literal wording: "inside the outline and **not board**" |
| **D2** | score ≤ −35 | the same rule, **belt** population as the positive class (STAGE_Q measured the belt at −44.0 ± 6.9) |
| **D4** | score ≤ −35 **and** luma ≥ 0.85·L_bg | `L_bg` = the frame's own background brightness.  Needed because 2G−R−B is a pure **difference**: it cannot tell the bright warm belt from the **dark blue-grey PCB substrate edge**, which is visible on every board's rim at this camera angle |
| **D5** | score ≤ s_bg(k) + 14 **and** luma ≥ 0.85·l_bg(k) | `s_bg, l_bg` = the belt **beside corner k on this frame** (`band_mask`), so the threshold moves with the light instead of with the session (§6) |

Two-sided thresholds per cell, on the reference frame:

| T | belt ≤ T | board ≤ T | floor ≤ T | belt : board |
|---|---|---|---|---|
| −50 | 20.06 % | 0.37 % | 0.00 % | 54 : 1 |
| −45 | 44.05 % | 0.52 % | 0.00 % | 85 : 1 |
| **−40** | 78.83 % | 0.81 % | 0.00 % | **97 : 1** |
| **−35** | 91.53 % | 1.04 % | 0.00 % | **88 : 1** |
| −30 | 98.10 % | 2.00 % | 0.30 % | 49 : 1 |
| −20 | 99.82 % | 3.48 % | 3.08 % | 29 : 1 |

−35 keeps 91.5 % of the belt for 1.04 % of the board — close to the best per-cell
odds (97 : 1 at −40) and the higher belt yield matters more, because the *lower*
thresholds cost signal and the board's false positives are only ~1 % of a 30–50 cell
window.  This is why `BELT_T = -35` (`:57`).

---

## 2. THE NULL — per pair, and over every board frame on disk

The statistic is **self-contained**: it needs the board's own fitted quad and its own
board, so the correct null is *one board, two frames* and, better, *one frame alone*.
Two forms are reported per pair: **A→B** (frame A's quad against frame B's board), and
**self** (each frame's own quad against its own board).  The self form is the one a
shipping statistic would compute, and it is the one the population table uses.

Window `W = 6` cells (chosen in §4).  All counts are cells.  `A→B` and `B→A` are the two
directions of the pair; `self` is each frame against itself.

### 2.1 `D1` — the formulation as written — **fails**

| pair | cells | TL | TR | BL | BR | max |
|---|---|---|---|---|---|---|
| stH/now1 | 1222/1228 | 20 / 20 | 2 / 1 | 13 / 14 | 23 / 20 | **23** |
| stI/u2 | 1179/1182 | 15 / 13 | 2 / 1 | 19 / 16 | 26 / 27 | **26** |
| stI/u3b | 1213/1209 | 16 / 13 | 2 / 3 | 16 / 16 | 17 / 21 | **17** |
| stI/u4 | 1177/1180 | 24 / 21 | 5 / 5 | 20 / 19 | 19 / 21 | **24** |
| regtest/live | 2989/3452 | 9 / 6 | 7 / 7 | 19 / 20 | 23 / 29 | **23** |
| stI/u1 | 1237/1250 | 15 / 14 | 1 / 1 | 15 / 15 | 20 / 21 | **20** |
| **regtest/ref (the reference against itself)** | 2957/2957 | **8** | **9** | **20** | **23** | **23** |

**n = 7, min 17, median 23, max 26.**  Then the whole population — every real captured
frame on disk that carries a measurable board (`section_boards`, `:606`):

* **86 frames** (of 114 of the right length; the rest have no board in view).
* max-over-corners per frame: **min 16, median 21, p90 24, max 29.  Not one frame reads 0.**
* per corner: TL max 26 (median 16), TR max 10 (median 2), BL max 20 (median 16),
  BR max 29 (median 20).

**This is not a quantisation band.  It is the board's printing.**  Look at the corner
medians: TR reads 2 and BL reads 16 on the *same* boards — the deficit follows where the
silkscreen is, not a cell of geometry.

### 2.2 `D2` — the belt side, fixed threshold

| pair | TL | TR | BL | BR | max |
|---|---|---|---|---|---|
| stH/now1 | 1 / 1 | 0 / 0 | 1 / 1 | 10 / 11 | **11** |
| stI/u2 | 0 / 0 | 0 / 0 | 2 / 1 | 6 / 3 | 6 |
| stI/u3b | 0 / 0 | 0 / 0 | 0 / 0 | 7 / 6 | 7 |
| stI/u4 | 0 / 0 | 0 / 0 | 2 / 1 | 6 / 9 | 9 |
| regtest/live | 1 / 1 | 1 / 1 | 1 / 1 | 12 / 10 | 12 |
| stI/u1 | 0 / 1 | 0 / 0 | 2 / 1 | 9 / 7 | 9 |
| regtest/ref (itself) | 0 | 2 | 1 | 8 | 8 |

**n = 7, min 6, median 9, max 12.**  Over the 86-frame population: **min 1, median 7,
p90 10, max 12.**  Better than D1 by 2×, but still not a band — and its worst corner is
always **BR**, which is where the board's own **substrate edge** sits (§2.3).

### 2.3 Why the null has a floor: the board's rim looks like the belt

The reference frame has **22 cells inside its quad with score ≤ −35**.  All 22 were listed
with their position, score and brightness (`section_signal` neighbourhood, and the working
note in §2.4).  They split into exactly two classes:

* **12 cells, max-channel 166–218** — genuinely the **belt**, seen inside the quad because
  the PCB outline is *not a quadrilateral*: it has a step at the right end and a chamfer,
  so the extrapolated quad overshoots the real board there.  The worst are all near
  BR: (98,71) −64, (95,72) −54, (100,71) −36, (99,78) −36, (100,78) −38.
* **10 cells, max-channel 116–150** — the PCB's **visible substrate edge**, a dark
  blue-grey whose 2G−R−B is −36 … −62 because B is high and G low, exactly like the belt's
  warm white.  Examples: (79,70) B116 G81 R100 → −54; (41,76) B132 G113 R130 → −36.

**The colour rule cannot separate those two from the belt, and it never could: 2G−R−B is a
difference, and both are "B-high, G-low".**  What separates them is *brightness* — and
brightness is not in the rule.

### 2.4 `D4` / `D5` — adding brightness, absolutely or relatively

`D4` (fixed threshold + brightness against the frame's own `L_bg`): over 86 frames the null
is **min 0, median 0, p90 1, max 2; 59 of 86 frames read 0.**  That looks like the
quantisation band the idea needs — but it is **not usable**, for two measured reasons:

1. **It is blind at two of the four corners.**  Painting a chip with *that corner's own
   measured background* makes `D4` read **0** at TL and TR, because the fixed −35 sits
   below the background's actual score there (−24 … −26, belt mixed with the floor above
   the board).  `section_sens` prints this as the `sig4x4` column of its threshold table:
   zero at every threshold from −50 to −25.  A null of 0 that comes from never firing is
   not a null.
2. **A fixed threshold cannot ship at all** — §6.

`D5` fixes both by measuring the belt **beside the corner, on the same frame**:

| pair | TL | TR | BL | BR | max |
|---|---|---|---|---|---|
| stH/now1 | 6 / 3 | 0 / 0 | 0 / 0 | 0 / 0 | 6 |
| stI/u2 | 5 / 5 | 0 / 0 | 0 / 0 | 0 / 0 | 5 |
| stI/u3b | 6 / 3 | 0 / 0 | 1 / 0 | 0 / 0 | 6 |
| stI/u4 | 3 / 4 | 0 / 0 | 0 / 0 | 0 / 0 | 4 |
| regtest/live | 1 / 1 | 0 / 0 | 3 / 3 | **14 / 12** | **14** |
| stI/u1 | 6 / 5 | 0 / 0 | 2 / 1 | 0 / 0 | 6 |
| regtest/ref (itself) | 0 | 0 | 2 | 8 | 8 |

**n = 7, min 4, median 6, max 14.**  Over the 86-frame population: **min 0, median 5,
p90 9, max 14** (per corner: TL 11, TR 1, BL 12, BR 14).  The 14 is one session
(`regtest`) where the board fills half the frame and its right end is a stepped edge.

**So the honest null, for the best variant that is neither blind nor fixed, is
0 … 14 cells, median 5, worst 14.**

---

## 3. THE SIGNAL — the known answer, painted

Paint the belt's measured colour over a corner of the real reference frame, at each of the
four *fitted* vertices, at 2×2, 3×3, 4×4, 6×6 and 8×8 cells (`paint_box`, `:412`;
`painted_cells`, `:422`).  The paint is anchored at the vertex and extends **into** the
board — the same construction STAGE_Q's chip table used (`STAGE_Q:139-144`), so the two
stages compare directly.

**Discipline first: the statistic must reproduce the area it was given.**  `PRED` below is
the exact number of cells whose four sample pixels the paint changed **and that were board
before** — computed from the sampler geometry, not estimated.  `MEAS` is what the statistic
reads.  Two paint modes: `flat` = the station belt colour (223, 198, 215) B,G,R, which is
STAGE_Q's; `adaptive` = **that corner's own belt, measured on that frame** (209,190,191) at
TL, (207,189,183) TR, (217,192,207) BL, (205,182,190) BR.

`D5`, `W = 6`, reference frame:

| chip | corner | PRED | MEAS flat | MEAS adaptive | the *other three* corners (must not move) |
|---|---|---|---|---|---|
| 2×2 | TL | 1 | 2 | 2 | TR 0 · BL 1 · BR 4 |
| 2×2 | TR | 2 | 3 | 2 | TL 0 · BL 1 · BR 4 |
| 2×2 | BL | 2 | 3 | 3 | TL 0 · TR 0 · BR 4 |
| 2×2 | BR | 2 | 8 | 8 | TL 0 · TR 0 · BL 1 |
| 3×3 | TL | 5 | 6 | 6 | TR 0 · BL 1 · BR 4 |
| 3×3 | TR | 6 | 7 | 6 | TL 0 · BL 1 · BR 4 |
| 3×3 | BL | 6 | 7 | 7 | TL 0 · TR 0 · BR 4 |
| 3×3 | BR | 3 | 11 | 11 | TL 0 · TR 0 · BL 1 |
| **4×4** | TL | 11 | 12 | 12 | TR 0 · BL 1 · BR 4 |
| **4×4** | TR | 12 | 13 | 12 | TL 0 · BL 1 · BR 4 |
| **4×4** | BL | 8 | 13 | 13 | TL 0 · TR 0 · BR 4 |
| **4×4** | BR | 3 | 16 | 16 | TL 0 · TR 0 · BL 1 |
| **6×6** | TL | 28 | 30 | 30 | TR 0 · BL 1 · BR 4 |
| **6×6** | TR | 25 | 26 | 25 | TL 0 · BL 1 · BR 4 |
| **6×6** | BL | 12 | 25 | 25 | TL 0 · TR 0 · BR 4 |
| **6×6** | BR | 11 | 28 | 28 | TL 0 · TR 0 · BL 1 |
| 8×8 | TL | 34 | 36 | 36 | TR 0 · BL 1 · BR 4 |
| 8×8 | TR | 30 | 31 | 30 | TL 0 · BL 1 · BR 4 |
| 8×8 | BL | 14 | 30 | 30 | TL 0 · TR 0 · BR 4 |
| 8×8 | BR | 11 | 28 | 28 | TL 0 · TR 0 · BL 1 |

Three things are established by that table:

1. **The statistic measures the area.**  `MEAS` equals `PRED` plus the cells that were
   already background-like before the paint (TL: 12 vs 11 at 4×4; TR: 12 vs 12; 6×6 TL 30 vs
   28, TR 25 vs 25).  Where `MEAS` exceeds `PRED` by more (BL 13 vs 8, BR 16 vs 3) the extra
   is cells that were **not board but not yet background** — silk and the dark substrate
   edge — which the paint converted.  That is the same rim that makes the BR null, and it
   is why the BR column of `PRED` is small: at BR the quad's acute corner already contains
   background, so painting it changes nothing.
2. **It is specific.**  A chip at one corner leaves the other three windows' readings
   *identical to the intact frame* (TL/TR 0, BL 1, BR 4, unchanged in every row) except for
   BR→4 which is the intact value.  No cross-talk.
3. **The response is corner-dependent in *amount*, not in *kind*.**  A 4×4 chip reads
   **12 / 12 / 13 / 16** at TL/TR/BL/BR — all four see it.  (Contrast the vertex statistic,
   which read 0.03–0.68 at three corners and 7.79 at the fourth, `STAGE_Q:139-144`.)
   The spread is the sub-cell phase of the vertex: a vertex that lands mid-cell can only
   remove whole sampled cells, so a 16-cell chip is 12 cells at one corner and 16 at another.

### Per size, at the weakest corner of this frame (this is the number §5 uses)

| s | cells | `PRED` | `MEAS` flat | `MEAS` adaptive |
|---|---|---|---|---|
| 2 | 4 | 1 … 2 | 2 … 8 | 2 … 8 |
| 3 | 9 | 3 … 6 | 6 … 11 | 6 … 11 |
| 4 | 16 | 3 … 12 | **12 … 16** | **12 … 16** |
| 6 | 36 | 11 … 28 | **25 … 30** | **25 … 30** |
| 8 | 64 | 11 … 34 | 28 … 36 | 28 … 36 |

Flat and adaptive agree, which is the point of the adaptive mode: the flat colour is
*brighter* than this corner's own belt yet reads the same, because the test is relative.

---

## 4. The corner window, chosen from the data

`W` must hold the defect (`W ≥ s`) and it must not grow the null.  Both curves, `D5`,
null over the 86-frame population and signal at the weakest corner:

| W | null max | null p90 | null med | s=2 | s=3 | s=4 | s=6 | s=8 | 4×4 / null |
|---|---|---|---|---|---|---|---|---|---|
| 3 | 4 | 2 | 2 | 2 | 4 | 6 | 6 | 6 | 1.50 (window too small to hold 4×4) |
| 4 | 14 | 3 | 2 | 2 | 6 | 9 | 12 | 12 | 0.64 |
| 5 | 11 | 7 | 4 | 2 | 6 | 12 | 19 | 19 | 1.09 |
| **6** | **14** | **9** | **5** | 2 | 6 | **12** | **25** | **28** | 0.86 |
| 7 | 17 | 11 | 6 | 2 | 6 | 12 | 29 | 39 | 0.71 |
| 8 | 17 | 13 | 7 | 2 | 6 | 12 | 29 | 47 | 0.71 |
| 10 | 22 | 18 | 12 | 2 | 6 | 12 | 29 | 52 | 0.55 |
| 12 | 37 | 23 | 14 | 2 | 6 | 12 | 29 | 52 | 0.32 |

**`W = 6` cells.**  It is the smallest window that fully contains the **largest defect in
the brief's own scale** (6×6), and it is where the 6×6 ratio peaks (25/14 = 1.79); every
larger window grows the null (14 → 17 → 17 → 22 → 37) while the 6×6 signal stops growing at
29.  Below `W = 6` the 6×6 chip is clipped (19 at W=5), which is why W=5's better-looking
4×4 ratio is an artefact.

For `D1` the same sweep is a monotone failure: 4×4 / null = 0.67, 0.73, 0.68, 0.52, 0.44,
0.48, 0.59, 0.60 at W = 3 … 12.  **It never separates at any window** — the null grows from
9 to 73 cells, the 4×4 signal from 6 to 44, and the null is always ahead.

---

## 5. The separation, per chip size, and what a threshold would be

Null = `D5`, `W = 6`, worst over the 86-frame population = **14 cells** (median 5, p90 9).
Signal = the weakest corner of the four (that is what an acceptance must survive).

| chip | weakest-corner signal | worst null | ratio | a threshold exists? |
|---|---|---|---|---|
| 2×2 | 2 | 14 | 0.14 | **no** |
| 3×3 | 6 | 14 | 0.43 | **no** |
| **4×4** | **12** | **14** | **0.86** | **no — the signal is inside the null** |
| **6×6** | **25** | **14** | **1.79** | **yes**: T = 20, margin 5 cells below the signal and 6 above the null |
| 8×8 | 28 | 14 | 2.00 | yes: T = 20, margin 8 below / 6 above |

**The stated defect is "tens of cells", i.e. 4×4 … 6×6.  At the bottom of that band the
statistic does not work; at the top it works with a 1.79 : 1 ratio and a five-cell margin.**
That is the number behind the conclusion.

### The three real corner boards: `d2`, `d6`, `d11` — **no frames exist, so say so**

They are in the 40-board sweep and they are the only real corner damage this project has:
`dl/host_qc/logs/sweep_20261027_160133_sweep.csv` — **d2 line 24, d6 line 28, d11 line
33**, all `defect=corner`, with `MB_DIFF_DAREA` **3, 7, 4**.

| | d2 | d6 | d11 | 21 good boards |
|---|---|---|---|---|
| shipped `MB_DIFF_DAREA` | 3 | 7 | 4 | 0,4,7,–,1,7,5,3,1,5,2,3,3,0,**9**,5,7,2,3,2,4 |

**The shipped statistic cannot see any of them**: the worst corner board reads 7 and the
worst *good* board reads 9 (g14, line 16).  That is why this work exists, and it also
fixes the expected scale of the real defect: their DAREA sits where a *small* chip sits,
which is the 4×4 end — the end this statistic does not reach either.

**No frames of d2, d6 or d11 exist on disk** (checked: `.tmp/` holds no capture whose
board is labelled with them; the sweep recorded mailbox words only).  So the question
"does a threshold catch all three while failing no good board" **cannot be answered from
the frames that exist** — neither by this document nor by any other offline method.  §7
says exactly what would answer it.

---

## 6. Why a fixed threshold cannot ship: the light moves more than the defect

Measured on the frames on disk, with the belt sampled **beside the bottom corners** (the two
corners where the band is pure belt, not belt mixed with the floor above the board),
172 samples over 86 frames:

| | min | p10 | median | p90 | max | spread |
|---|---|---|---|---|---|---|
| belt 2G−R−B | −56 | −54 | **−38** | −26 | −4 | 52 points |
| belt brightness (mean B,G,R) | 70.7 | 137.2 | **159.9** | 173.0 | 217.7 | **3.08 ×** |

* A fixed score threshold of **−35 sits at or above the belt's own level 47 %
  samples** — on nearly half the frames the background would not be classified as
  background, so a chip revealing it would read **zero**.  That is exactly what `D2` and
  `D4` do at the top corners in §2.4, printed as the `sig4x4 = 0` column of
  `section_sens`.
* The belt's **brightness** varies **3.08 ×** between frames.  No constant can gate it.

This is STAGE_Q's caveat standing up under measurement — "one reference frame, so a
different light needs the threshold re-derived" (`STAGE_Q:203-207`) — and it is worse than
the caveat says, because the re-derivation would have to happen *per frame*, not per
station.  **The only version that is not blind is the relative one** (`D5`), which measures
`s_bg` and `l_bg` from the belt beside each corner on the same frame: two medians over a
~50-cell band, which is cheap and needs no stored calibration.

Two useful properties of that relative form, measured (`section_sens`, `:724`):

* **It is insensitive to registration.**  Displacing the whole quad by 0.10, 0.25, 0.50 and
  0.75 cells in x and in y leaves the self-null at **max 4 cells, unchanged** — because the
  band moves with the quad, so the reference moves with the test.  Compare the vertex
  statistic, whose null was 0.20 … 3.58 cells and which got worse with every parameter.
* **It is not the same as the cell-centre convention.**  `conv='edge'` gives null 14 /
  signal 10, `conv='corner'` gives null 14 / signal 12 → the half-cell convention this
  document uses (`CONV = "corner"`, `:70`) is chosen because it buys 2 cells of signal for
  free.
* **It inherits the quad estimator's fragility.**  Corner zone 0.00 and 0.25 both read a
  4×4 signal of **0**, while 0.05 … 0.18 read **12** — the self-null stays 4 throughout.
  A free parameter of the fit that can zero the signal is a real risk, and it is one more
  reason not to ship this without a capture of a real chip.

---

## 7. What is unverified, and the exact capture list that would settle it

Not verified here, in order of how much it matters:

1. **No frame of a real corner chip exists.**  Every "signal" number above is paint.  A
   painted chip is a *flat* patch of one colour; a real milled/filed corner reveals the
   belt **under** the board, plus a fresh board edge whose colour is unknown (bright milled
   laminate or dark substrate).  The whole of §5 rests on the assumption that the revealed
   area looks like the belt **beside** the corner.  **That assumption is untested and
   untestable offline.**
2. **No frames of `d2`, `d6`, `d11`** — the only real corner boards (§5).
3. **One board dominates the geometry.**  The 86 frames are 4-5 physical units in a handful
   of placements, all in one station pose.  The null's worst values (14 at `regtest`) come
   from one session whose framing differs by 2.5×.
4. **The colour rule is still one light's rule** — and §6 says its two thresholds must be
   re-derived per frame, not per station.
5. **Nothing was run on the board.**  No flash, no reference, no operator round.  OCM cost
   is not re-measured here; `STAGE_Q:14-36` measured 2,236 bytes for the quad block and
   **1,024 bytes free**, and this statistic adds four line comparisons per cell plus two
   medians over a 50-cell band — but that is an estimate, not a measurement.

**The capture list that would answer it** (this is what "the frames on disk cannot answer
it" means concretely):

| # | capture | why it decides something |
|---|---|---|
| 1 | **`d2`, `d6`, `d11` at the station, one frame each, plus the 3 nearest good boards** | the only way to know whether the real chips are 4×4 (undetectable, §5) or 6×6 (detectable at 1.79 : 1) |
| 2 | **the same 3 boards with the corner filled flush** (tape or a scrap of PCB of the same thickness, filed to the original outline) | turns "painted chip" into "real missing material": the paired difference on the *same board* is the true signal |
| 3 | **one good board at three exposure steps** (e.g. AEC held one stop up and one stop down) | tests the relative rule against the 3.08 × brightness spread in §6 without leaving the bench |
| 4 | **`s_bg` and `l_bg` per corner written to a mailbox word at reference time** | makes the two thresholds auditable from the same row of the sweep CSV, instead of re-derived offline |
| 5 | **the fitted quad's four lines written to a dumpable buffer** | lets the deficit be recomputed from a dump, so the 40-board sweep's numbers can be re-judged by a second method — which it currently cannot (`dl/SWEEP_20261027.md:474-478`) |

---

## 8. Conclusion

**The frames on disk cannot answer it — here is exactly what would (§7).**

With the numbers behind that, in the order they were asked for:

* **The null is not a quantisation band.**  For the formulation as written it is
  **16–29 cells** (median 21, 86 frames, never 0), because 32.2 % of a PCB is white
  silkscreen by design.  For the belt-side reading it is **1–12**.  For the belt-side
  reading *with* a brightness dimension it is **0–14**, and only the frame-relative version
  of that is neither blind nor fixed to one session.
* **The signal** at the size the brief specifies is **12–16 cells for 4×4** and **25–30 for
  6×6**, at all four corners, specific (the other three windows do not move), and it
  reproduces the painted area cell for cell.
* **The separation is 0.86 : 1 at 4×4 and 1.79 : 1 at 6×6**, with a threshold at 20 cells
  having 5–6 cells of margin above the worst null and below the 6×6 signal.  **No threshold
  catches a 4×4 corner chip without failing good boards.**
* **`d2`, `d6`, `d11` cannot be judged**: no frames exist, and their shipped `DAREA`
  (3, 7, 4) sits inside the good-board range (0 … 9), so the *scale* of the real damage is
  unknown but small — which is the undetectable end.

So: **do not implement the statistic as specified** (its null overlaps the defect at every
window), and **do not implement the frame-relative version yet either** — it is promising
at 6×6, but it needs five more captures, the first of which is a frame of `d2`, `d6`,
`d11`.

---

## 9. Files

| file | what |
|---|---|
| `dl/area_deficit_20261027.py` | **the measurement.**  Sections: `probe` (§0), `null` (§2), `boards` (§2 population), `signal` (§3), `windows` (§4), `sens` (§6), `png`.  `python dl/area_deficit_20261027.py all` |
| `dl/area_deficit_20261027_view.png` | the reference frame with the fitted quad, the W=6 windows, and the deficit cells a **good** board already has |
| `.tmp/quad/probe_*.py` | the scratch probes that found the two mechanisms (silkscreen at BL/BR, substrate edge at BR); not deliverables |

Reproduce any table with, e.g. `python dl/area_deficit_20261027.py null`.  The script is
self-contained (numpy only, plus Pillow for the picture) and reads only frames already in
`.tmp/`; it treats `.tmp/synth*/` and `.tmp/xstub/` as **generated, not captured**
(`dl/ANOMALY_20261027.md` §2) and never loads them.
