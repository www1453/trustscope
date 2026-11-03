# Stage D (2026-10-25) — the part's own cluster as the ROI, and a verdict made of amplitude and area

Build `TSC1` / **`627926F0`**.  Flashed with `ps_fft_dual/strict_load_cores.tcl` only: no
bitstream, no power cycle, no VDMA poke.  The board was already running stage C
(`06C4E921`); `rst -cores` + `dow` is the documented firmware-only load.

Two changes, in the brief's order:

1. **the part mask keeps the part's cluster and drops the room's islands**, and the fine
   pass judges only where the live and baseline masks agree;
2. **the verdict reads an amplitude-and-area statistic** — the area of the largest
   connected group of cells more than 30 grey levels from the baseline — instead of the
   count of cells over 14.

The old count stays published (`MB_DIFF_FCELLS`) so the change is auditable against it.
A refused frame still reads CANNOT JUDGE, in both directions.

---

## 0. What was read first, and what it changed

`dl/STAGE_C_20261025_exposure_range_mask_latch.md` (the build and the AEC work),
`dl/VERDICT_SCOPE_20261024.md` (the verdict reads the in-part fine count only),
`dl/MB_WORDS_20261025.md` (the word map), `dl/STAGE8_20261024_fine_cells_and_adaptive.md`
(the 8x8 fine cells and the adaptive-threshold change that was measured and NOT shipped).

**Every read on the board went through a NAME**, via `dl/mb_map_20261025.tcl` regenerated
from this source (`python dl/mb_words.py --tcl ...`, 328 names) and read by
`ps_fft_dual/stD_accept_20261025.tcl`, `ps_fft_dual/mb_snap_20261025.tcl`,
`ps_ui/stD_snap.py` (snapshot files).  No script in this session contains a mailbox
number.

**One figure in the brief does not describe this bench, and it matters.**  The brief says
the mask covers "about 40% of the frame while the part is about 30%".  Measured on the
frames dumped from the board (`.tmp/stD/cur/live.raw`, 2026-10-25 10:12):

| quantity | measured |
|---|---|
| part mask, shipped rule, after erosion | **588 cells = 4.08%** of the 160x90 lattice |
| the PCB's own box in the picture (x 400..960, y 380..600 source px) | **13.4%** of the frame area |
| mask cells outside that box | 198 of 588 (34%) |
| the same on the 2026-10-23 close-up framing (`ps_ui/st2_A_live.raw`, board fills the frame) | 2,599 cells = 18.0% |

So on today's framing the mask is 4% and the part's box is 13%, in a 30/40-style relation
(mask smaller than the part's bounding box, because the mask is the green solder mask
between silkscreen and components, not the board's silhouette) — but the absolute numbers
are a quarter of the brief's.  Everything below is reported in the measured units, and the
"true fraction" is the PCB box, stated as such, not restated from the brief.

---

## 1. Change 1 — the ROI: the part's cluster, and live-baseline agreement

### 1.1 What the shipped mask actually selects, measured

`ps_ui/stD_mask_ab.py` ports `part_masks()` (green dominance `G-max(R,B)` of the 2x2
samples at +2/+5 in every 8x8 block, threshold at the frame's **own median + 12**, 3x3
erosion) and is checked against the firmware's own dumped array:

* replay vs the dumped `LIVE_MASK` on the frame it was built from: **14,263 of 14,400
  cells identical (99.05%)**, mask 588 vs 561; the 27-cell residual is mask movement
  between the mask's frame and the dump (stage 8 measured 149 cells of movement between
  dumps 3 s apart on this object).
* on the 10-24 failing-state dumps the same port agrees to 96.5..97.0% with the dumped
  masks (7 s of separation between frame and mask dump).

The mask is not one object: **30 components** on the live frame (45 on the 10-24 failing
frames), and 198 of 588 cells are outside the part.  The overlays are
`.tmp/stD/cur/live_shipped.png` (red = mask) and `.tmp/stD/cur/live_afterK2.png` (blue =
after this change): before, there are mask patches on the floor and the furniture; after,
every kept cell is on the PCB.

### 1.2 The rule, and the two rules that were measured and rejected

`ps_ui/stD_mask_rule.py`, on the same frame and the reference frame:

| rule | live mask | of frame | verdict |
|---|---|---|---|
| shipped | 588 | 4.08% | — |
| **literal largest 4-connected component** | **188** | 1.31% | **REJECTED: below `PART_MIN_PTS` 400** |
| closing K=1, largest cluster | 246 | 1.71% | REJECTED: also below 400 |
| **closing K=2, largest cluster** | **510** | 3.54% | **shipped** (absorbs 17 components, drops 13 / 78 cells) |
| closing K=3, K=4 | 510 | 3.54% | no further change |
| closing K=6 | 522 | 3.62% | starts re-absorbing distant islands |

The literal rule fails **because the part's own mask is 30..45 fragments** (silkscreen and
components split the green solder mask): "keep the largest island" keeps one patch of the
PCB and throws the rest away, and the mask then falls under the 400-point floor the
registration requires, i.e. the board would refuse *every* comparison.  On the 2026-10-23
close-up framing the same rule is nearly a no-op (2,599 → 2,596), because there the part
is one component.

**Shipped rule** (`main.c:3421`, `mask_dilate_k` `main.c:3484`, `cc_largest`
`main.c:3512`): keep the largest connected component of the mask **dilated by 2 lattice
cells** (16 source px), intersected with the mask itself.  No cell is added — the result is
a subset of the eroded mask — so the "margin removed" is not a strip of the part's border
but the *disconnected* fragments: measured on the live frame, **13 components / 78 cells**
(1.08% of the frame) are dropped and all of them are background; on the reference frame 19
components / 66 cells.  The cost is stated in the source at `main.c:3415-3428`: a defect on
a mask fragment more than 16 source px from the part's main body is no longer judged.  The
pre-rule count is published as `MB_PART_RAW` (word 21) so the trade is visible at runtime.

### 1.3 The judged ROI is now live-and-baseline agreement

`ref_part_ok()` (`main.c:5723`), used at `main.c:6450`: a fine cell is judged only when
`LIVE_MASK` says part **and** the cell's centre, mapped through the same transform
`ref_at()` samples with (same Q12 coefficients, same shift), lands on a `BASE_MASK` part
cell.  Before this, a third of the judged cells were part-against-not-part: the search
itself publishes that fraction as `MB_PART_USED / MB_PART_PTS` = 345/517 on the old build.

### 1.4 Change 1's acceptance numbers, on the board (build `627926F0`)

| quantity | before (stage C, measured 10:05-10:10) | after | how |
|---|---|---|---|
| `MB_PART_PTS` | 517..573 | **466..556** (rows of the still run) | mailbox, per judged comparison |
| `MB_PART_RAW` | — (word did not exist) | **525..631** | the pre-cluster count |
| cells removed by the cluster rule | — | **26..75 (5..12%)** | RAW − PTS |
| `MB_PART_REF` | 603 | **521..543** | per reference |
| `MB_PART_USED` | 345..358 | **273..318** | the search's scored points, stride 1 |
| the search's floor (`PART_PTS/2`) | 258 | 250 | `main.c:3540`'s relative floor; used stays above |
| `MB_DIFF_FVALID` | 517..573 (= `PART_PTS`, no agreement test) | **468..509 (88..94% of `PART_PTS`)** | per judged comparison |

The mask is 8..12% smaller and the judged area is another 6..12% smaller than the mask
(`FVALID/PART_PTS` = 0.88..0.94 where it was exactly 1.00 — the old build judged every
in-mask cell).  `FVALID` in absolute terms went from 517..573 (old build, different frames)
to **468..506**; the offline same-frame measurement of the agreement at the identity is
480 of 519 live cells = 92.5%.  So the judging area shrank by roughly a fifth in total.
That is the price of the agreement, and it is published on every comparison.

### 1.5 Did the registration's residual improve?  Measured against an independent fit

`ps_ui/stD_reg_fit.py` is the previous session's instrument, re-implemented: it fits
`baseline(p) = c + R(-theta)(live(p) - c) - D` on the part region by minimising the mean
absolute green difference, then scores any transform handed to it on the same region with
the same measure.  Frames: the reference and live frame dumped from the board before the
change (`.tmp/stD/cur/ref.raw`, `live.raw`), i.e. the *same physical state* both builds saw.

| transform | dx16 | dy16 | angle100 | scale256 | mean abs green diff over the part |
|---|---|---|---|---|---|
| **independent fit (truth proxy)** | **+840** | **−88** | **+90** | **259** | **9.67 grey** |
| old build published (stage C) | +800 | −192 | +37 | 253 | **13.42** |
| new build, cold adoption run 1 | +842 | −100 | +80 | 255 | **12.15** |
| new build, cold adoption run 2 | +896 | −90 | +107 | 259 | **10.59** |

Errors against the fit: dx **2.5 source px → 0.13 px** (run 1), dy 6.5 px → 0.75 px, angle
**0.53° → 0.10°**; the second run is 3.5 px / 0.17°.  So the residual against an
independent image-domain fit **improved**, 13.42 → 10.59..12.15 grey (truth proxy 9.67).

**Two things about that table that must be said.**  (i) The firmware's angle sign is
opposite to a textbook rotation: `reg_coeffs()` gives `(c·vx + s·vy, -s·vx + c·vy)`.  My
first scoring used the textbook sign and reported the change as WORSE (14.36 → 15.37); the
sign was settled by measurement — scoring the same transform both ways on the same region
— and the table above is the corrected one (`+80` scored as `−0.80` in the fit's
convention, 12.15 grey, against 15.37 with the wrong sign).  (ii) The old build's transform
was a **warm held** answer while the new build's came from a **cold** search after
`MB_CMD = 17`; the cold answer is not deterministic across cold starts (two runs: 842 and
896 dx16, 80 and 107 angle100 — the same nondeterminism stage 7 documented).  The
comparison is therefore between "a warm hold under the old mask" and "a cold solve under
the new mask", which is the honest description of the two states, not a controlled A/B.

**The previous session's specific pair (published 14.1 half-res px / 3.48° against a fit of
18.6 / 4.68°) was NOT reproduced frame-for-frame**: that comparison needs the 10-24 21:12
dumped pair with its own published transform, and the 10-24 dumps in `dl/` do not carry a
snapshot of the mailbox at the same instant (`dl/now_mb.raw` is from 21:16, four minutes
after `now_ref.raw`).  What is reproduced is the *method* and its conclusion on today's
state, as the table shows.

---

## 2. Change 2 — amplitude and area, measured before chosen

### 2.1 The instrument

`ps_ui/stD_fine_replay.py` replays the firmware's fine pass line by line (four 3x3 boxes at
+2/+6 on the green channel; `ref_cell8` through `ref_at`'s Q12 bilinear with
`dx_fp8 = dx16·8`; the coarse pass's gain and bias; the live mask).  Its checks:

* **A** a frame against itself at the identity reads `|d|` max **2** (rounding of the coarse
  bias; the board itself has the same 1..2-count floor) — the port manufacturers no signal.
* **B** `FVALID` reproduces `mask.sum()` exactly (every in-mask cell judgeable).
* **C** on the live state the replay gives `FOVER` **104** against the board's **95** and
  `FMAXD` **54** against **56** — the difference is that the board's live side is the mean
  of 8 frames and the replay is one frame.  4..9% agreement on two different statistics.

### 2.2 The three populations, and the histograms (the numbers the thresholds came from)

`ps_ui/stD_populations.py`.  Bins are `|d|` in grey levels over **judged** cells only.

| population | judged | over 14 | after 3x3 | peak | histogram 14-20/20-25/25-30/30-35/35-40/40-45/45-50/50-60/60-80/80+ |
|---|---|---|---|---|---|
| (a) still, two real frames 2 s apart | 523 | **0** | 0 | 6 | 0 0 0 0 0 0 0 0 0 0 |
| (b) reference shifted 0.5 px | 523 | 0 | 0 | 9 | 0 0 0 0 0 0 0 0 0 0 |
| (b) shifted 1 px | 523 | 1 | 0 | 17 | 1 0 0 0 0 0 0 0 0 0 |
| (b) shifted 2 px | 523 | 12 | 0 | 32 | 10 1 0 1 0 0 0 0 0 0 |
| (b) shifted 3 px | 523 | 30 | 9 | 42 | 21 4 1 3 0 1 0 0 0 0 |
| (b) **real 50x12 px move, re-registered** | 523 | **72** | **24** | 54 | 52 8 8 2 1 0 0 **1** 0 0 |
| (c) **defect 40x40 px +60** (MB_CMD=15) | 523 | 19 | 19 | 60 | 0 0 0 0 0 0 0 **19** 0 0 |
| (c) defect 32x32 px **+20** (low contrast) | 523 | 14 | 14 | 20 | 14 0 0 0 0 0 0 0 0 0 |
| (c) defect 24x24 px **+22** (low contrast) | 523 | 7 | 7 | 22 | 0 7 0 0 0 0 0 0 0 0 |

The largest **connected group** of cells above a candidate amplitude, same runs:

| population | amp>20 | amp>25 | amp>30 | amp>35 | amp>40 | amp>45 |
|---|---|---|---|---|---|---|
| (a) still | 0 | 0 | 0 | 0 | 0 | 0 |
| (b) 2 px shift | 1 | 1 | 1 | 0 | 0 | 0 |
| (b) 3 px shift | 2 | 2 | 2 | 1 | 1 | 0 |
| (b) real 50x12 px move | **3** | 3 | **2** | 1 | 1 | 1 |
| (c) 40x40 +60 | 19 | 19 | 19 | 19 | 19 | 19 |
| (c) 32x32 +20 | 0 | 0 | 0 | 0 | 0 | 0 |
| (c) 24x24 +22 | 7 | 0 | 0 | 0 | 0 | 0 |

**The sweep that bounds the real population.**  Four hand-picked shifts do not bound
anything, so every integer displacement (dy,dx) in 0..3 px was replayed (18 placements,
plus 0.5/1.5/2.5 px rows), and the worst case over the whole sweep is: largest connected
group **2 cells at amp>30**, 2 at amp>25, 1 at amp>35 — while the **old count reaches 17**
after its 3x3 rule at a 3-px residual, i.e. over the limit of 8.  That is the overlap the
brief describes, reproduced and quantified: the old statistic fails a good part at 3 px.

### 2.3 The numbers chosen

```
DEFECT_AMP  = 30 grey levels     (main.c:2247)
DEFECT_AREA = 8 cells            (= DIFF_LIM_DEFAULT, unchanged, main.c:2248)
```

Reasoning, from the table: 30 is **5x** the still-scene peak (6) and 15x the 14-count
threshold; at 30 the worst displaced placement in the sweep produces a group of 2 cells,
so the area minimum of 8 has a **4x** margin under it, and the 40x40 +60 stamp produces a
group of 19, a **2.4x** margin over it.  `DEFECT_AREA` is `DIFF_LIM_DEFAULT` **by
construction** so the host word `MB_DIFF_LIM` (a count of cells) keeps its unit and its
override function; what changed is that the number it is compared with is now a connected
group's area.  `MB_DIFF_DAREAMIN` (31) publishes it, `MB_DIFF_DAMPTHR` (30) publishes the
amplitude.

### 2.4 What the rule costs — the low-contrast trade, measured on the board

| defect injected into the reference | raw fine count (old rule) | **`DAREA` (new rule)** | verdict |
|---|---|---|---|
| 40x40 px **+60** | 25 | **25** | **NG** on all 23 comparisons |
| 24x24 px **+60** | 9 | **9** | **NG** on all 23 |
| 24x24 px **+22** | 9 | **0** | **PASS on all 23** |

So a **+22 grey step over 4.2 x 6.0 mm reads PASS**, and 21 of those 23 comparisons had the
old count at or above the limit of 8 — the old build would have called NG.  Below the
amplitude threshold nothing can rescue it: the difference has to be *deeper* than 30 grey
or *larger* than 8 cells above 30.  The smallest caught defect measured today is a 3x3-cell
(4.2 x 6.0 mm) patch at +60.

### 2.5 Publish list (all read by name in the acceptance harness)

| word | index | meaning |
|---|---|---|
| `MB_PART_RAW` | 21 | mask cells before the cluster rule |
| `MB_DIFF_DN` | 22 | deep cells this frame (`> MB_DIFF_DAMPTHR`) |
| `MB_DIFF_DAREA` | 23 | **the authority**: largest connected deep group, cells |
| `MB_DIFF_DAMP` | 24 | largest `|d|` inside that group, grey |
| `MB_DIFF_DAT` | 25 | `(gy<<8)|gx` of that cell |
| `MB_DIFF_DBX0..DBY1` | 26..29 | the group's box, 8x8 cells; 0xFFFFFFFF when empty |
| `MB_DIFF_DAMPTHR` | 30 | 30, the amplitude threshold |
| `MB_DIFF_DAREAMIN` | 31 | 8, the minimum area |
| `MB_DIFF_DLIM_USED` | 32 | the area limit actually applied (LIM resolved) |

`MB_DIFF_FCELLS`/`FOVER`/`FVALID`/`FMAXD`/`FAT`/`FX0..FY1` keep their old meanings and are
still published; `fine_publish_invalid()` (`main.c:5346`) invalidates the new words
together with them, and a settle slot publishes `DAREA = 0xFFFFFFFF` (never 0).

---

## 3. The four acceptances, with how each was measured

All on build `627926F0`, on the board, read by name through
`ps_fft_dual/stD_accept_20261025.tcl`.  `MB_DIFF_VERDICT` is the firmware's own word; the
panel's `MB_VERDICT` is host-sourced and was not written (it still holds DDR junk
`0xDFF59D7E`, as stage C documented).

**(1) A good board at a deliberately different placement reads PASS.**
The physical state on the bench *is* such a placement: the reference in DDR was taken at an
earlier placement (the old build read it as `FCELLS` 26..34, `PART_USED` 345, dx16 800).
That exact reference image was dumped (`ref.raw`), written back into `REF_BASE`, and
re-derived with `MB_CMD = 17`:

* 20 judged comparisons + 1 settle slot (`OK=5` → CANNOT JUDGE, correct)
* **raw fine count 16..20 on every one of the 20** (all ≥ the old limit 8)
* **`DAREA` 0 on every one of the 20** (one comparison read 1 during adoption)
* **verdict PASS on all 20.**

**(2) The known defect stamp still reads NG.**  `MB_CMD = 15`, 40x40 px, +60 grey, at cell
(67,73) — chosen as a 5x5-cell block fully inside *both* the live and the baseline masks:

* 23 judged comparisons, 0 refused
* `DN` 25, **`DAREA` 25**, `DAMP` 68..69, `DBOX` **(67,73)-(71,77)** — exactly the stamped
  5x5 block, which is the independent check that the area is geometry and not noise
* **verdict NG on all 23**; after a fresh reference: `DAREA` 0, PASS.

**(3) The low-contrast defect is reported honestly, as a miss.**  `MB_CMD = 15`, 24x24 px,
+22 grey: 23 judged comparisons, raw count **9**, **`DAREA` 0**, **PASS on all 23**.  A
+20 grey 32x32 px stamp was measured offline and behaves the same (14 cells, all in the
14..20 bin).  Section 2.4 states the trade; nothing here hides it.

**(4) 100+ still-scene comparisons do not regress.**  Fresh reference, 300 s, one row per
judged comparison:

* **154 judged comparisons, 0 refused**
* **raw `FCELLS` = 0 in all 154** (`max_raw_fcells` is the harness's own count over every
  row, not a spot check)
* **`DAREA` = 0 in all 154** (`max_darea=0`, same aggregation)
* PASS with the raw count ≥ 8: **0**; PASS with `DAREA` ≥ 8: **0**
* verdict not PASS: **none**
* in the rows printed (the last 20 of the 154): `FOVER` 0, `FMAXD` 4..8, `FVALID` 468..506,
  `PART_RAW` 525..609, `PART_PTS` 483..542, `PART_REF` 521, `PART_USED` 286..313, `READY` 1
  and `AVG_CNT` 8
* registration held the identity: dx16 −2, dy16 0, angle100 +3, scale 256.

The stage-C baseline for this acceptance was 120 comparisons with fine 0 everywhere; this
run is 154 with the same result, at a judging area about a fifth smaller (section 1.4).

---

## 4. Cost: OCM, DDR, and what moved

| item | before (stage C) | after | note |
|---|---|---|---|
| `.text` | 104,516 | **105,876** | +1,360 (the two changes' code) |
| `.data` | 92 | 92 | — |
| `.bss` | 25,372 | **10,972** | −14,400: `g_bggrid` moved to DDR |
| image end | 0x1FBBC (129,980) | **0x1C8D4 (116,948)** | 131,072-byte OCM region |
| **OCM free** | **1,092** | **14,124** | |

**OCM did not fit, and one named buffer moved.**  With the two changes in, the link failed
with `region ocm overflowed by 236 bytes` while `g_bggrid` (14,400 bytes of `.bss`, the
background detector's live grid) was still in OCM.  It moved to **DDR `0x126F0000`**
(`main.c:2668`), and the reason is written at the definition: it is a pure scratch array —
`diff_frame()` fills every cell at `main.c:6180-6187` and the only reader is `bg_align()`,
which it is passed to — so no cell is ever read before it is written and a DDR address with
unknown initial content is irrelevant.  Nothing was deleted to make room, and no other
buffer changed address or size.

**DDR grew by 72,000 bytes**, all in the free hole between `BASE_MASK_D`'s end
(0x126E3840) and `BG_BASE` (0x12700000):

| buffer | address | bytes | why |
|---|---|---|---|
| `PART_CC_TMP` | 0x126E4000 | 14,400 | the cluster rule's dilation; later the deep-cell flag grid |
| `PART_CC_STK` | 0x126E8000 | 28,800 | the flood fill's stack, `uint16` cell indices |
| `FINE_DEEP` | 0x126EC000 | 14,400 | `|d|` of every judged fine cell, 0..255 |
| `g_bggrid` (moved) | 0x126F0000 | 14,400 | was 14,400 bytes of OCM |

They are deliberately **not** shared with each other's consumers: this project already lost
a round to two 14,400-byte buffers at one address (`BASE_MASK_D` / `FINE_FLAG`, 2026-10-24).
The flood fill's stack is bounded by construction — a cell is marked when *pushed*, so no
cell is pushed twice and the stack can never exceed 14,400 entries.

Build: 13 files, `build.ps1` exit 0 (the PowerShell `[exit code: 1]` is gcc's stderr
through the pipe, as the brief says), **329 `MB_*` words, 329 distinct indices, 0
collisions**, all layout checks pass, only the four pre-existing warnings, plus the one
KNOWN pre-existing literal-offset finding at word 131 (`MB_ARM_DT` vs the CNN panel's
selftest flag) which stage C reported and this session did not touch.

---

## 5. Defects found in the work itself, including one the board found

1. **A publish bug the first board run exposed.**  The group's box was published as
   `DBOX=67,73,-1,-1`: `dbx1`/`dby1` were initialised to `0xFFFFFFFF` as "unset", so
   `fx > dbx1` was never true.  Fixed (`main.c:6410-6416` initialise the maxima to 0 and
   publish 0xFFFFFFFF only when the group is empty) and re-measured: `DBOX=67,73,71,77`.
2. **A flood-fill bug caught before the board saw it.**  The first `cc_largest()` tested
   `a[idx] > thr` while marking visited cells with 2; with `thr = 0` a marked cell passes
   its own test and the fill never terminates.  Rewritten to a strict `== 1` grid contract.
3. **An offline sign-convention error** in the independent fit, corrected by measurement
   rather than argument (section 1.5).
4. **The literal largest-component rule the brief suggests is not usable on this bench** —
   measured, rejected, and replaced by the closing variant; section 1.2 has the numbers.

---

## 6. What remains unverified, and every human-dependent check

1. **The AEC's mask term now sits closer to its floor.**  The mask is 26..75 cells smaller,
   and stage C's decision uses `PART_MIN_PTS + AEC_MASK_HYST = 448`; measured rows are
   483..542 (still run) and 466 (one transient), so the margin fell from ~120 cells to
   ~20..90.  A dimmer scene could now make the controller chase brightness where it did
   not before.  *No operator needed:* dim the room by ~30% or cover the lamp partially and
   watch `MB_AEC_MASK`, `MB_AEC_FLAGS` (bit1), `MB_AEC_LAST` 10/11 and `MB_AEC_TRIES` for
   60 s.  The question is only whether `MB_AEC_MASK` crosses 448 while the mean stays in
   150..780.
2. **One framing only.**  Every number here is the 2026-10-25 wide framing (part ~13% of
   the frame, mask ~4%).  On the 2026-10-23 close-up framing the cluster rule is a no-op
   (2,599 → 2,596 cells) and the agreement test is unknown; the change was not measured
   there.  *Human:* re-frame the camera close on the board, take a reference
   (`MB_CMD = 9`), and read `MB_PART_RAW`, `MB_PART_PTS`, `MB_DIFF_FVALID`, `DAREA` for
   20 comparisons; the expected result is a no-op on the mask and a small FVALID loss.
3. **A real defect on a real part.**  All defects here are synthetic stamps in the
   reference image.  The operator's ~40 deliberately damaged boards are the experiment:
   for each, take a reference, then record `MB_DIFF_DAREA`, `DAMP`, `DBOX`,
   `MB_DIFF_FCELLS`, `MB_DIFF_VERDICT` and the operator's description.  Until that exists,
   no accuracy is claimed for the rule — only the separation between the three populations
   in section 2.2.
4. **A +20..30 grey defect is now invisible by construction.**  Measured, not hidden (2.4).
   If the product needs that sensitivity back, the lever is the *false-positive* side:
   either accept NG on a misplaced part, or add a placement-aware path (e.g. compare at
   two placements and take the better), which is a larger change than this one.
5. **Persistence is not applied to the new rule.**  The persisted window (`PERSIST_N`) is
   on the "do not change" list, so the deep-group area is measured on the raw current
   frame.  The risk a persistence window would remove — a one-frame transient — is
   mitigated by the amplitude threshold being 5x the still-scene peak, but a genuine
   specular glint of 8+ cells above 30 grey in one frame would read NG.  Not observed in
   154 still comparisons.
6. **The registration's cold-start nondeterminism is unchanged and was observed again**:
   two cold adoptions of the same injected reference gave dx16 842 and 896, angle100 80 and
   107.  Both are better than the old build's warm hold against the independent fit, but
   they are not the same answer, and a single cold adoption should not be quoted as "the"
   registration accuracy.
7. **The 40x40 px stamp's own cell count is not 25 by construction.**  Offline, the same
   40x40 stamp on the still frame was judged at 19 of its 25 cells (the block sits at the
   mask's edge on one side in that frame); on the board at cell (67,73) it was judged at all
   25 — `DN` 25, `DAREA` 25, `DBOX` (67,73)-(71,77).  So `DAREA` is the block's measured
   size after the mask and the agreement test, not the stamp's nominal size; the published
   box is what makes the two checkable against each other.
8. **`MB_PART_RAW` and the new `MB_DIFF_D*` words are new**: a host that reads them must be
   rebuilt against `dl/MB_WORDS_20261025.md` (regenerated: 328 words) or
   `dl/mb_map_20261025.tcl` (328 names).
9. **The J10 jumper** (PIN35 B20 / PIN28 V12) must be out before any power-on.  A human
   check; not observable from software and not touched here.
10. **An indirect effect on the part-view framing.**  No display-layer code was changed, but
    the "show only the PCB" view derives its box from `LIVE_MASK` (and its own
    `MB_PV_MIN`/hysteresis), and that mask is now 8..12% smaller.  The box is the longest
    contiguous run of qualifying rows/columns, so a smaller mask can move it; it was not
    measured this session (the panel was not being watched).  *Human:* select the part view
    (`MB_VIEW`/`MB_ZOOM` per stage 8) and confirm the framing is stable for 60 s, reading
    `MB_PV_ON`, `MB_PV_BX0..BY1` and `MB_PV_N` (the re-aim counter should stay put on a
    still part).

---

## 7. Reproducing any number above

```
python dl/mb_free.py                                  # which words are free
python dl/mb_words.py --tcl dl/mb_map_20261025.tcl    # regenerate the name map
python ps_ui/stD_mask_ab.py                           # mask replay vs the firmware's dump
python ps_ui/stD_mask_rule.py                         # shipped vs literal vs closing, per K
python ps_ui/stD_mask_roi.py                          # coverage and the agreement count
python ps_ui/stD_mask_view.py <frame.raw> <out>       # the overlays quoted in 1.1
python ps_ui/stD_fine_replay.py validate              # the fine pass + its three checks
python ps_ui/stD_populations.py                       # the three populations + the sweep
python ps_ui/stD_reg_fit.py <ref> <live> <mask> ...   # the independent fit vs published
python ps_ui/stD_snap.py <snap.bin> <first-word> <names...>   # words by name
xsdb ps_fft_dual/stD_accept_20261025.tcl snap|still|stamp|inject ...
xsdb ps_fft_dual/stD_dump_20261025.tcl <dir>          # frames + masks + fine arrays
```

Board left in the documented state: `MB_CMD = 9` fresh reference, identity held
(dx16 −2, angle100 −13 → −0.13°), `MB_DIFF_FCELLS` 0, `MB_DIFF_DAREA` 0,
`MB_DIFF_FVALID` 502, `MB_PART_RAW` 581, `MB_PART_PTS` 529, `MB_PART_REF` 523,
`MB_PART_USED` 303, `MB_READY` 1, `MB_AVG_CNT` 8, verdict 0 (PASS), FWID `TSC1` /
`627926F0`.
