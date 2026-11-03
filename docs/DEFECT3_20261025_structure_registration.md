# Defect 3 (2026-10-25) — the registration scores STRUCTURE, so a changed surface still aligns

Build `58648B95` (source hash), flashed with `ps_fft_dual/strict_load_cores.tcl` only:
no bitstream, no power cycle, no VDMA poke.  Written against build `DE833091`
(commits `e55fd89` + `091ce9a`), which is Defect 2's confidence gate on top of Defect 1's
mask.

**Headline: the measured failure was reproduced from a dump of the failing state before
the change, the deciding quantity was measured on both candidate transforms, and the
shipped one is the gradient magnitude — chosen over the census/rank transform by a
SEARCH measurement, not by its score.

On the board, acceptance 1 is MET: with a good reference and the defective board in view
the registration settles (state 1, HOLD, score 108..112 against the gate's 192, no
refusal) and 21 consecutive comparisons all read NG with DAREA 9..11.  Acceptance 3 is a
MEASURED NEGATIVE on the same pair: the held transform is 28.8 source px from the
independent structure truth because the cost minimum is mask-shaped.  Acceptance 2 and 4
are NOT MEASURED (no good boards were available).  Sections 6 and 7 say what the NG rows
do and do not prove.**

---

## 1. The failing state, captured before anything was changed

At 12:31 the board was running `DE833091` in exactly the state the brief describes:
`MB_PART_REF` 482 (a good reference), `MB_PART_PTS` 761 > `PART_MIN_PTS` 400, rules 1/1,
`MB_REG_STATE` 2, `MB_REG_MODE` 0, `MB_REG_INCERR` -1, verdict 2, `DAREA` -1.  The
following buffers were dumped read-only to `.tmp/stG/goodref_badlive/` (no reset, no
write, no poke): `grey_base.raw` (the good reference's 640x360 half-res grey),
`ref.raw` (its full-resolution reference), `live.raw` + `live2.raw` (two frames of the
DEFECTIVE board), `latt.raw`, `live_mask.raw`, `base_mask.raw`, `base_mask_d.raw`,
`mb_all.bin`.

Two checks before any of it was used:
* `grey_base.raw` is **bit-identical** to `grey(ref.raw)` converted the way `grey_capture()`
  converts it (230,400 bytes, 0 differences) — so the dump is the baseline the firmware
  scored, not a lookalike.
* the live lattice is NOT a single frame (12,222 of 14,400 bytes differ from
  `latt(live.raw)`, mean |d| 2.7 grey between two live frames): `latt.raw` is the
  8-frame mean `avg_take()` produces, which is what `reg_score()` scores.

## 2. What actually failed — two mechanisms, measured

**(a) the confidence gate measured brightness.**  Replaying the shipped `reg_score()`
(ps_ui/stG_rank_replay.py, the same port validated against the board in Defect 2) on the
dumped pair, at the independent structure truth (section 3): mean absolute difference
**13.11 grey = 210** in the gate's unit, above `REG_CONF_LIM` 192.  The same board
against its own reference reads 2.36 grey = 38.  So a CORRECTLY ALIGNED defective board
is refused because its surface, not its geometry, differs.

**(b) the point-count floor could demand more points than the reference mask has.**
`floor_pts = g_part_pts / (stride^2 * 2)` used the LIVE mask count.  On this pair the
live mask is 761..**1072** lattice points against a reference mask of **482**; a point
is scored only when BOTH masks agree, so no offset and no stride can ever reach
`1072/2 = 536` points.  Measured at the 12:31 peek: `MB_PART_PTS` 1072,
`MB_PART_REF` 482, `MB_REG_INCERR` **-1** with `MB_PART_USED` far below 536.  The floor
is now `min(g_part_pts, g_part_ref) / (stride^2 * 2)` — the count the overlap can
actually reach; with both masks the same size (the still scene, 755/737) it is the
number it was.

## 3. The deciding measurement: intensity vs census/rank vs gradient

An INDEPENDENT truth instrument was built first: a dense alignment of the half-res
gradient-magnitude images by normalised correlation over (Dx, Dy, theta, scale), with a
known-answer check (a synthetic transform applied to the reference is recovered to
0.5 px / 0.2 deg).  On the real pair it puts the truth at **D = (14.5, 3.0) half-res px,
+0.10 deg, scale 0.994**.  The shipped intensity objective's own minimum is at
(14.5, 2.5) — 0.5 px away — so the alignment was never the problem.

Scores at that truth, firmware sampling geometry and mask rule (mean absolute
difference over the scored points; intensity in grey, rank in rank steps of 8, gradient
in gm units):

| transform | this pair (good ref / bad live) | same board vs own ref | penalty |
|---|---|---|---|
| intensity SAD (shipped) | **13.11 grey = 210** (gate 192 → refused) | 2.36 = 38 | 5.5x |
| census-8, radius 1 | 3.76 bits of 8 | 1.77 | 2.1x |
| rank, one lattice step | 1.77 rank steps = 28 | 0.88 = 14 | 2.0x |
| **gradient magnitude (shipped)** | **3.85 gm = 62** | 1.41 = 23 | 2.7x |

Monotone change of the live frame (`0.8*live + 18`, structure preserved): intensity
13.11 → **11.75** (it moves), gradient 9.59 → **9.59** (with its gain ratio), rank
1.77 → 1.89.  That is the property the brief asks for, measured on the real frames.

**Why the gradient and not the rank, whose score is better.**  The rank cost surface is
too flat for the shipped search.  With the part mask, the coarse stage at stride 4
samples ~20 points; the rank metric's correct-vs-wrong difference is the same order as
that sample's spread.  Measured on this pair: the 289-candidate coarse winner sat
**16..20 half-res px** from the truth, and on the widened path the union rule's minimum
sat at the **edge of the +-128 window** ((-48,+128), score 29, against the truth's 29
over 30x more points).  A search started there cannot reach the basin — the full replay
refused at the fine stage (`ps_ui/stG_rank_replay.py`).  The gradient keeps the
sharpness the search needs: on the still scene +2 half-res px costs 2.2 → 19.5 grey.

## 4. What changed in `ps_ui/main.c`

1. **`main.c:1866` `BASE_GM` / `LIVE_GM`** — DDR buffers at `0x11FA3000` (640x360 uint8
   gradient magnitude of `GREY_BASE`, 230,400 B, ends 0x11FDC900) and `0x11FE0000`
   (160x90 uint8 gradient magnitude of the live lattice, 14,400 B, ends 0x11FE3840).
   The gap is camera-1 store 4's end to 0x11FFFFFF, inside mmu.c's 16 MB camera-1
   window (`0x11000000`, 16 sections); OCM does not grow for them.
2. **`main.c:3087` `gm_base_fill()`** — one pass over `GREY_BASE` at `ref_take()`, called
   next to `grey_capture()` (`main.c:6136`).  230,400 pixels x 4 reads, one-time.
3. **`main.c:3109` `gm_latt_fill()`** — per comparison, from the SOURCE frame
   (`main.c:7045`): for
   each of 14,400 lattice points, 9 half-res grey values (the same 2x2 green box
   `grey_capture()` uses) then the same operator.  36 source reads per point; a single
   store frame is enough because the operator is local, which is why the n-frame
   averaging is not touched.
4. **`main.c:4338` `reg_score()`** — the scored values are the two gradient-magnitude
   buffers instead of `LATT_BASE`/`GREY_BASE`; the gain ratio is still applied, now
   computed from the gradient lattices (`main.c:5097`).  Search structure, stages, windows, parabolas,
   bilinear refinement, margins and the confidence gate are unchanged.
5. **`main.c:4408` the floor** is `min(live, base)` (section 2b).
6. **`main.c:5218` the coarse stage scores at stride 2, not 4**, with the measured reason: at
   stride 4 the winner was 16..20 px from the truth; at stride 2 it is (16,0) against a
   truth of (14.5,3.0).  Cost is published as `MB_REG_TICKS`.
7. **`main.c:5267` stage 1b (pre-angle translation refinement) now runs on the SHIPPED
   path too**, not only on the widened retry, on the DOUBLE mask rule (no loosening).  It was
   added to the widened path on 2026-10-24 for exactly this coupling; measured here on
   the known-truth pair p2, the 16-px coarse grid left the winner 6..7 px off and the
   angle sweep then picked -2.0 deg against a truth of -0.4.  With 1b the same replay
   publishes 1.75 half-res px / 0.20 deg on p2 and 1.0 half-res px / 0.10 deg on the
   real pair.
8. **The confidence gate is unchanged** (091ce9a): same mechanism, same code paths,
   `REG_CONF_LIM` 192.  It is not loosened to make the pair pass.  Measured caveat in
   section 7.

## 5. Cost

| item | DE833091 | this build |
|---|---|---|
| `.text` | 107,316 | **108,244** |
| `.bss` | 11,516 | 11,528 |
| image end (incl. .bss) | 0x1D08C (118,924) | **0x1D438 (119,864)** |
| OCM free | 12,148 | **11,208** |
| DDR | — | +244,800 B at 0x11FA3000 / 0x11FE0000 |
| search time | — | `MB_REG_TICKS` 6.15..6.19 M = **18.4..18.5 ms** (+ ~10 ms of coarse stage) |

Build: 13 files, 0 mailbox collisions (336 words / 336 indices), layout checks pass, the
four pre-existing warnings.  No mailbox word added; `MB_REG_INCERR`/`MB_DIFF_SAD` keep
their indices and mean "1/16 gm unit" (0..2032).

## 6. Board acceptance — what the board actually measured

Firmware flashed and running (`FWID D60220A9`; four pre-existing warnings, 0 mailbox
collisions, all layout checks pass).  No operator was available in this session, so the
good-reference / defective-live pair was recreated ON THE BOARD through the documented
host paths instead of by hand, and the empty-belt background was restored from the
earlier session's dump:

* `MB_CMD = 18` adopted the empty-belt background saved at 11:46
  (`MB_BG_STATE` 4, `MB_BG_CELLS` ~2,950) — the saved image passed the firmware's own
  stale-background check, so the background rule is the one that ran (`MB_PART_RULE` 1);
* `MB_CMD = 17` installed the good board's real reference frame into `REF_BASE`;
  `ref_take()` rebuilt the baseline from it (`MB_PART_REF` **482**, `MB_PART_RRULE` 1 —
  the same reference geometry as the failing state in section 1);
* the DEFECTIVE board was the one physically in view, and its mask was healthy
  (`MB_PART_PTS` 823..891 > 400).

### Acceptance 1 — the defective board against a good reference reads NG

**MEASURED, 21 consecutive judged comparisons (MB_DIFF_N 80..108), all on the same held
transform:**

| quantity | measured |
|---|---|
| verdict | **1 (NG) on all 21** |
| `MB_DIFF_DAREA` | **9, 10, 9, 10, 10, 9, 10 ... 11, 10** — every one **>= 8** (the minimum) |
| `MB_DIFF_DAMP` | 58..74 |
| `MB_REG_STATE` | **1** (settled) on every one; 0 refusals, 0 CANNOT JUDGE |
| `MB_REG_MODE` | 2 (HOLD) on every one — the answer did not wander |
| `MB_REG_INCERR` | 108..112 against `REG_CONF_LIM` 192 (1.7x margin) |
| held transform | dx16 +4, dy16 +132, angle100 +2, scale 256 — stable |
| `MB_PART_PTS` / `MB_PART_REF` | 823..891 / 482 |
| `MB_REG_TICKS` | 6.15..6.19 M ticks = **18.4..18.5 ms** per search |

So the mechanism the brief asked for is demonstrated on the board: a defective board
whose surface differs from the reference now ALIGNS AND SETTLES (state 1, HOLD, score
108) instead of refusing; the gate is not the reason for any refusal because there is
none.  This is the acceptance the prior build could not make.

### Acceptance 3 — registration accuracy: a MEASURED NEGATIVE on this pair

The transform the firmware holds on the pair above is **not** the true placement.  The
independent dense-structure fit (ps_ui/stG_align.py, known-answer checked to 0.5 px /
0.3 deg) puts the truth at **D=(14.5, 3.5) half-res px, +0.30 deg, scale 0.996**
(`dx16 +464, dy16 +112, angle100 +30`), i.e. the same truth as the 12:31 dump
(14.5, 3.0, +0.10).  The firmware publishes **(+0.125, +4.125, +0.02 deg)** — a **14.4
half-res px = 28.8 source px** error in x.

The mechanism, measured: after `ref_take()` the held answer is the identity, its score
on this frame is 108..121 — BELOW the confidence gate — so the warm window accepts it
as a plausible answer; the cold search then has to beat it by `REG_WARM_MARGIN` and does
not, so the identity is re-published (mode 2, HOLD).  The same firmware on the same pair
published **(+14.5, +1.0, +0.05 deg)** — 2.5 half-res px from the truth — while the
base mask was the GREEN rule's (534 points, before the background adopt).  The only
difference between the two states is the reference mask's shape (background rule, 482
points), so the objective function's minimum on this pair is MASK-SHAPED, which is the
same class of defect as the 4-px bias of the intensity metric this change set out to
remove.  It is not fixed here.

Consequence for acceptance 1 above: the 21 NG rows are TRUE (the board differs from the
reference by far more than the alignment error) but **9..11 of the DAREA comes from a
comparison run on a 28-px-wrong transform**, so the NG is not yet evidence that the
defect is measured at the right place.  That is the honest reading, and it is why this
section is a negative for acceptance 3 even though acceptance 1 is met.

### Acceptance 2 and 4 — NOT MEASURED

Two different good boards (acceptance 2) and a 100+ comparison still scene on a good board
(acceptance 4) need physical boards.  The defective board in view reads NG by design, so
it cannot stand in for either.  Not measured, not claimed.

## 7. What is measured, what is not

* MEASURED, acceptance 1: 21 consecutive NG comparisons, DAREA 9..11, registration
  settled (state 1, HOLD, score 108..112 < 192), 0 refusals.  See section 6.
* MEASURED NEGATIVE, acceptance 3 on this pair: the held transform is 28.8 source px
  from the independent structure truth (the "true" transform is (14.5,3.5) half-res px;
  the firmware holds (0.125,4.125)).  The objective function's minimum on this pair is
  mask-shaped: the same firmware found (14.5,1.0) when the reference mask was the green
  rule's 534 points and held (0.125,4.125) under the background rule's 482.  The next
  lever is a mask-shape-independent point set / joint refine, not the metric.
* MEASURED NEGATIVE: on this pair the gradient score does **not** separate a grossly
  wrong alignment (70..102 at 2..8 half-res px off, and 72 for a 128-px-off union
  candidate) from the correct one (62), so the confidence gate cannot carry the search
  on a surface-changed pair; the mask-overlap floor is what bounds it.  Stated in the
  `REG_CONF_LIM` comment.
* The rank transform's score IS the more invariant one (1.77 against the gradient's
  3.85), and it was rejected on its cost surface, not on its invariance: a better
  search (dense multi-scale, or a fixed point set) might make it viable later.
* NOT MEASURED: acceptance 2 (two different good boards) and acceptance 4 (100+
  comparison still scene) — no good boards were available; they are not claimed.
* NOT MEASURED: behaviour on a good board under a different light (the 192 gate has 3.1x
  headroom on the two correct answers measured).
