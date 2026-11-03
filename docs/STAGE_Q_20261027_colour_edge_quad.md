# Stage Q (2026-10-27): the colour edge and the quad — a MEASURED NEGATIVE

Firmware: **nothing changed.** `ps_ui/main.c` is untouched (`git status` clean for it),
nothing was built into `ps_ui.elf` for the board, nothing was flashed.  This document is
the measurement that says why the change should not be made as specified.

The task's own kill criterion was applied first and it failed.  Everything below is
measured on real frames already in the tree, and every number can be reproduced with
`.tmp/quad/*.py`.

---

## 0. OCM cost, reported before any code was written into the firmware

**3,260 bytes are free.**  Measured two ways, both from the current build:

| source | number |
|---|---|
| `ps_ui.map`: `__bss_end = 0x1F344` (127,812) against the `ocm` region end `0x20000` (131,072) | **3,260** |
| `arm-none-eabi-size ps_ui.elf`: text 119,236 + data 108 + bss 8,468 = 127,812 | **3,260** |

The block was then written and compiled **alone** with `ps_ui/build.ps1`'s own flags
(`-mcpu=cortex-a9 -marm -O2 -ffreestanding -nostdlib -fno-builtin -fno-stack-protector`),
with the one call site added so `-O2` could not drop it as dead code:

| what | bytes |
|---|---|
| `.text` | **2,236** |
| `.data` / `.bss` | **0** (the boundary arrays are stack locals) |
| stack, deepest path (`q_stage` 56 + `q_quad` 688 + `q_fit` 96) | 840 |
| free after the block (3,260 − 2,236) | **1,024** |

**It fits.**  The stack does not raise the high-water mark: the existing deepest frame is
`part_view_update` **1,032** bytes (`-fstack-usage`), against a 4,096-byte stack region.
So OCM was never the reason to stop.  The null was.

---

## 1. The colour rule, derived from pixels

Sampler is the firmware's own (`part_score`, `ps_ui/main.c:4512`): four single pixels at
(+2,+2), (+5,+2), (+2,+5), (+5,+5) inside the 8x8 cell at source (8i, 8j); a pixel is 3
bytes, `+0 +1 +2` = **B, G, R** (`CAM_STRIDE 3840 = 1280*3`, `main.c:196`).

Populations on the station reference frame (`.tmp/a1/ref_base.bin`, the dumped
`REF_BASE`), per 8x8 cell, **2G − R − B**, threshold **26**:

| region | n cells | mean | sd | p1 | p50 | p99 | cells over 26 |
|---|---|---|---|---|---|---|---|
| board | 1350 | **+47.06** | 36.64 | −35 | +58 | +116 | 915 (67.8%) |
| belt left | 476 | **−42.35** | 6.46 | −63 | −42 | −32 | **0** |
| belt right | 629 | **−46.86** | 5.00 | −62 | −46 | −38 | **0** |
| belt front | 525 | **−41.99** | 7.94 | −61 | −42 | −22 | **0** |
| floor centre | 1656 | −3.23 | 8.65 | −22 | −4 | +24 | 13 (0.54%) |
| floor right | 768 | −17.66 | 14.19 | −54 | −16 | +7 | 0 |
| room corner | 432 | −24.45 | 14.63 | −59 | −26 | +4 | 0 |

* **board vs belt: +47.1 ± 36.6 against −44.0 ± 6.9, d′ = 3.45.**
* **board vs floor: +47.1 ± 36.6 against −7.8 ± 12.6, d′ = 2.00.**
* At threshold 26: **0 of 1,630 belt cells and 0 of 432 room cells pass**; 13 of 2,424
  floor cells do (0.54%).

**The board's spread is the honest part of this table.** Its sd is 36.6, not 6, because a
PCB is *not* uniformly green: the green solder mask is +58 and the white silkscreen and
components are near 0 or negative, so 32.2% of the cells over the board are UNDER the
threshold.  That is tolerable for an outline (the PCB's border ring is green) and fatal
for anything that needs the whole surface.

### Which discriminant, and the one the firmware already rejected

| discriminant | board | belt | floor | verdict |
|---|---|---|---|---|
| **2G−R−B** | +47.06 ± 36.64 | −44.0 ± 6.9 | −7.8 ± 12.6 | **chosen**: d′ 3.45 vs belt, 0 belt cells over |
| G−R | +35.27 ± 26.40 | −13.1…−19.0 | −5.08 ± 8.52 | separates too, but the floor's p99 is +24 at a mid of 22 |
| G−B | +11.39 ± 16.68 | −24.9…−29.0 | +1.66 ± 6.81 | **311 belt cells above the midpoint** — this is the overlap |
| G−max(R,B) | +10.43 ± 17.30 | −25.0…−29.2 | −6.24 ± 7.18 | wrong for this board: the PCB is cyan (**B ≈ G**), so `max(R,B)` is B and the score collapses |

`G−B` failing is not new: `ps_ui/main.c:1944` already records "the green PCB and the belt
overlap in the green-vs-blue margin".  **This measurement reproduces it independently**
and shows why `2G−R−B` gets around it: the belt is *warm* white (G 197.8 is its LOWEST
channel), so subtracting both other channels drives the belt to −42 while the board's
cyan-green sits at +47.

---

## 2. THE NULL — the kill criterion — **IT FAILS**

The statistic: four side lines fitted robustly (trimmed least squares, corner zones
dropped), four vertices = the intersections, compared per vertex in lattice cells
(1 cell = 8 source px).

The null is *the same board, the same placement, two frames*, so the correct registration
is the identity and no registration error can be blamed.

Corner zone 10% of each side (the setting where all four vertices are measurable on nearly
every real frame):

| pair | cells | vertices measurable | per-vertex offset (live2 − live), cells | largest |
|---|---|---|---|---|
| stH/now1 | 1221/1217 | 4/4 | TL(+0.04,−0.01) TR(−0.06,+0.12) BL(+0.12,−0.09) BR(−0.25,+0.25) | **0.25** |
| stI/u2 | 1149/1170 | 4/4 | TL(−0.00,−0.04) TR(+0.46,−0.05) BL(−0.15,+0.13) BR(+0.14,−0.20) | 0.46 |
| stI/u3b | 1200/1175 | 4/4 | TL(+0.01,+0.00) TR(−0.51,−0.16) BL(−0.02,+0.01) BR(+0.04,−0.06) | 0.51 |
| stI/u4 | 1152/1170 | 4/4 | TL(+0.02,+0.10) TR(+0.01,−0.12) BL(+0.07,−0.24) BR(−0.05,+0.63) | 0.63 |
| regtest/live | 2987/2959 | 4/4 | TL(+0.05,−0.06) TR(+0.17,−0.17) BL(+0.05,−0.10) BR(−0.13,−0.20) | 0.20 |
| stI/u1 | 1196/1199 | 4/4 | TL(+0.83,−0.08) TR(+0.41,+0.10) BL(+0.09,+0.33) BR(**+2.62**,−0.47) | **2.62** |
| regtest/ref (the reference against itself) | 2953/2949 | 4/4 | TL(**−3.58**,−0.08) TR(−3.16,−0.50) BL(−2.76,−0.44) BR(−3.39,+1.16) | **3.58** |

**n = 7, min 0.20, median 0.51, max 3.58; 5 of 7 under 1.00 cell — 2 FAIL.**

It is not one unlucky setting.  Corner zone 18%: 6 pairs, median 0.73, max 5.12, 4/6 pass.
Corner zone 0%: only 2 pairs keep all four vertices measurable and both are 8.6 and 9.3
cells.  And the number of measurable vertices swings with that arbitrary parameter
(`stI/u1` reads 2.62 at 10% and 5.12 at 18%), which by itself disqualifies a statistic
that has to carry an acceptance.

**Why it fails, measured, not guessed.**  A vertex is the INTERSECTION of two
*extrapolated* lines, i.e. the point farthest from where each line's points actually are.
The board is ~66 cells wide, so a side's centroid is ~20-30 cells from a vertex; a slope
error of 0.01-0.05 cell/cell (which is what a one-cell boundary wobble over a 40-60 point
side produces between two frames) lands as 0.2-1.5 cells at the vertex.  The lever arm
multiplies the noise, and the vertex is the worst possible place to read a line fit.
Measured per-side slope changes between the same-board frames confirm the mechanism:
`left −0.2626 → −0.2658 (Δ 0.0032/cell)` with a 20-30 cell lever arm.

This is the same failure class as the two statistics that died at this bench today
(`dl/STAGE_*`: OUT area 825 against itself) — a real, structural floor, not a tuning
problem.

---

## 3. The corner chip — the specified statistic cannot see it, at any null

Known-answer test on the real reference frame: paint the **belt's own measured colour**
over a corner of the board (so the frame is otherwise identical and the placement is
identical by construction), refit, and read the affected vertex.

| chip | TL | TR | BL | BR |
|---|---|---|---|---|
| 2×2 cells | +0.21 | 0.00 | +0.17 | 0.00 |
| 3×3 | 0.04 | 0.03 | 0.74 | 0.00 |
| 4×4 (16 cells of area) | 0.10 | 0.06 | 0.68 | 0.08 |
| 6×6 (36 cells) | 0.32 | **7.79** | 0.67 | 0.22 |
| 8×8 (64 cells) | unmeasurable | **12.46** | **8.29** | 0.16 |
| 12×12 | unmeasurable | 18.05 | 13.76 | 16.18 |

The task's own scale for this defect is "tens of cells", i.e. 4×4 to 6×6.  In that band
three of the four corners read **0.03-0.68 cells** — under the statistic's own noise — and
one corner reads 7.79.  The response depends on **which corner** the same chip is at, not
on the chip.

**And it has to be that way.**  A corner chip removes material *at the corner*; both
adjacent sides keep all their remaining points, and a robust fit through them returns the
same two lines, so their intersection — the vertex — does not move.  What a chip moves is
the *observed* corner, which the vertex is explicitly not.  The 7.79 and 12.46 readings at
TR are the chip leaking into the TR-corner *slope* estimate, i.e. an artefact, and it is
the artefact that makes the statistic non-repeatable rather than useful.

**A fitted quad is blind to a corner chip by construction.**  The acceptance's 3:1 ratio
(corner ≥ 3 cells while the null stays < 1) is unreachable, independent of the null.

What *does* see it is area, and that is already in the firmware: `MB_OUT_MISS` /
`MB_OUT_AREA` (`main.c:2563-2574`) is the "baseline says part, live says not" direction;
its problem was the 1-cell dilation tolerance, not its formulation.

---

## 4. The free bonus: a bare belt

`.tmp/synthsum/empty/cam0.raw` is **not evidence** — it is synthetic, flat 204.5 in all
three channels.  The real bare-belt frame available is `.tmp/a2/empty/cam0_now.bin`:

* cells over 26: **42 of 14,400 (0.29%)**; over 40: 13; the largest single cell score 52.
* the same frame's channel means are B 142.0, G 133.5, R 144.9 — a dim, warm scene, not
  this bench's bright belt, so even this is a different light from the reference frame.

So the colour rule turns a bare belt into **42 cells instead of 3,520** (the current
"not background" mask), which is a 84:1 improvement and answers "can the station tell
no-part from part" — but it is **42, not ~0**, and the residual is a real green object in
the room (visible in `.tmp/quad/masks.png`).  Any rule that needs ~0 must also drop the
smallest connected component, which the firmware's `cc_largest` (`main.c:5814`) does.

---

## 5. Cost per comparison

The colour pass reads 160×90 cells × 4 samples × 3 bytes = **172,800 byte reads**, which is
*exactly* what the existing green-score pass in `part_masks()` already reads
(`main.c:4801-4813`), plus 4 × 4 trimmed fit iterations over ≤160 points.  Anchors already
measured on this board: the whole `part_masks()` call is **20.3-26.0 ms**
(`MB_PART_TK_MS`), the background-only path **4.8 ms** (`dl/PART_MASK_PERFRAME_20261026.md`).
A pass of this shape is therefore single-digit ms; it can also run at the comparison
cadence (every 16th loop, ~2.2 s) instead of every loop.  **Not measured on the board —
nothing was flashed.**

---

## 6. What is unverified, and what would change the answer

* **Nothing was measured on the board.**  No flash, no reference, no operator round.  Every
  number here is offline, from frames already in the tree.
* The registration was *not* used: for a same-placement null the identity is correct, which
  makes these numbers the *most favourable* case for the statistic.  The firmware's own
  1-2 px registration could only make a re-placed board's null worse, not better.
* Only *one* reference frame was available to derive the colour populations
  (`REF_BASE` dumped 2026-10-27).  A different light changes the belt's level; the rule's
  two populations should be re-derived per station, which the threshold word makes
  possible without a reflash.
* **What would reopen it:** an *observed-corner* statistic, not a fitted vertex.  The
  honest per-vertex number for a chip is the missing area inside the fitted quad within a
  corner window (cells), whose null is the quantisation band and whose signal is the chip.
  That is measurable from the same 2,236-byte block: the quad is the *reference frame*, and
  the deficit is the count.  It should be tried as a count, not as a position.

## 7. Files

| file | what |
|---|---|
| `.tmp/quad/pop.py`, `regions.py`, `render.py` | the two populations and the mask pictures |
| `.tmp/quad/qfit2.py`, `qfit3.py`, `null_c.py` | the quad fit and the null |
| `.tmp/quad/final.py`, `repeat.py`, `report_nums.py` | the chip sweep, the empty belt, the tables above |
| `.tmp/quad/qcost.c` | the block, for the OCM measurement only — **not linked into anything** |
| `.tmp/quad/masks.png`, `empty_view.png`, `ref_base_view.png` | what the rules actually select |
