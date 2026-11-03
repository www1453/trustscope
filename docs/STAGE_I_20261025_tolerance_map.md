# Stage I -- a per-cell tolerance map, learned from the good population

2026-10-25. Firmware: `ps_ui/main.c`; build `cd ps_ui; powershell -NoProfile
-ExecutionPolicy Bypass -File .\build.ps1`; board: `ps_ui/stI_board.tcl` (read-only except
for the two host words and MB_CMD) driven by `ps_ui/stI_run.py`; offline replay
`ps_ui/stI_replay.py`, map builder `ps_ui/stI_tolmap.py`, row summariser `ps_ui/stI_rows.py`.

## 1. The problem, as measured

Four good units against one good reference, one fixed amplitude threshold (|live - ref| >
30 grey; a defect is a connected group of >= 8 such cells): DAREA max = 4, 3, 8, 5. One of
four good units exceeds the 8-cell limit, and the defective board reads 9..11. At the
comparison's own best transform (chosen by its fine-cell arithmetic, `ps_ui/stH_celldiff.py`)
unit #3 still carries ~9 cells above 30 grey, so the overlap is not an alignment artifact.

Measured again in this session, on this build, with the map NOT yet in force (fewer than 3
good units learned), unit #2 -- a different good unit: 28 comparisons,
DAREA 4 x4, 5 x12, 6 x7, 11 x4, 12 x1 -> **5 NG of 28 (18%)**. The problem reproduces on a
second good unit, not only on #3.

## 2. What changed

| item | before | after |
|---|---|---|
| a cell exceeds when | `abs(d) > 30` grey | `abs(d) > tolerance[cell]` |
| the tolerance | the constant DEFECT_AMP = 30 | `max(30, the largest abs(d) any good unit showed here)` |
| keyed on | -- | the BASELINE 8x8 cell the comparison maps the live cell to |
| the defect test | connected group >= DEFECT_AREA (8) | **unchanged** |
| the fail-safe | refused -> CANNOT JUDGE | **unchanged** |

`DEFECT_AMP` stays as the map's FLOOR, so a cell no good unit ever exceeded keeps exactly
the behaviour this build shipped, and an empty map is a no-op.

### Where the map lives (nothing in OCM moved)

The ELF is linked entirely into OCM (`ps_ui/lscript.ld`), so `dow` does not touch DDR:

| buffer | address | size | survives |
|---|---|---|---|
| `FINE_TOL` | 0x126FC000 | 14,400 B | a firmware load |
| `TOL_HDR` | 0x126FF840 | 20 B | a firmware load |
| neither survives a power cycle, and a flash costs the map anyway | | | see below |

A flash still costs a relearn, and that is by design, not an oversight: `g_ref_ok` is RAM,
so the firmware takes a fresh reference 64 loops after every load (main.c:12904) and a new
reference empties the map. The header therefore carries a magic word, the sample count, the
map generation, the floor, and a sparse FNV-1a fingerprint of REF_BASE; `tol_boot()` empties
the map unless magic and fingerprint both match, and clamps every byte up to the floor on
the way in, so a corrupted byte can never be stricter than the shipped rule.

### Why the BASELINE cell and not the live cell -- measured

Replayed from two good units against one reference (`.tmp/stH/unit3` at dx16 -96 and
`.tmp/stH/def3` at dx16 +516, i.e. 38 px = 4.8 cells apart), regenerating the comparison's
own per-cell field (`ps_ui/stI_replay.py`, validated against MB_DIFF_FVALID / DN / DAREA /
FMAXD on the same dump: 482/483, 9/11, 3/3, 66/66):

| key | cells both units judged | correlation of abs(d) between them | cells one found deep that the other also did |
|---|---|---|---|
| live 8x8 cell | 182 | -0.002 | 0 of 3 |
| baseline 8x8 cell | **368** | **0.421** | 2 of 5 |

A live-keyed map would be learning where the board happened to be.

## 3. The map's own numbers

Learned from FOUR distinct good units, one comparison each, keyed on baseline cells:

| quantity | value |
|---|---|
| samples (`MB_TOL_N`) | 4 |
| cells relaxed above the 30-grey floor (`MB_TOL_VAR`) | **75 of 14,400 = 0.52%** |
| tolerance at the worst cell (`MB_TOL_MAX`) | **142 grey** |
| where (`MB_TOL_AT`) | baseline cell (gx 109, gy 57), key 9229 |
| distribution above the floor | 52 cells at 31..45 grey, 7 at 46..70, 5 at 71..100, **11 above 100** |
| what it did at runtime | rescued 49% of the deep-cell observations on unit #3, 62% on one run of unit #3's re-place, 11% on the reference unit |

The 11 cells above 100 grey are the map's weakest point and this report does not hide it:
those are cells where ONE good unit once differed by more than 100 grey, which is more
likely a specular highlight or an edge cell than natural board-to-board variation. A
production AOI map caps its envelope; this one does not, and the defect measurement below
is what says whether that matters here.

## 4. Acceptance

Rows below are one placement each, with the map in force unless the "map size" column says
otherwise. `NG` is counted the way the firmware counts it: a measured comparison with
DAREA at or above the limit of 8. The raw row files are in
`dl/STAGE_I_20261025_rows/` so the next session can re-derive every number here with
`python ps_ui/stI_rows.py dl/STAGE_I_20261025_rows/<file>.csv`.

| unit | map size | comparisons (rows) | DAREA distribution | DAREA max | NG (distinct comparisons) | margin |
|---|---|---|---|---|---|---|
| #2, fixed threshold | 2 (not in force) | 23 (28) | 4x4 5x12 6x7 11x4 12x1 | 12 | **3** (5 NG rows) | -4 |
| #2 | 3 | 22 (25) | 1x1 2x2 3x14 5x5 6x1 9x1 10x1 | 10 | **2** | -2 |
| #2 | **4 (complete)** | **27 (29)** | 0x3 1x12 2x8 3x2 4x4 | **4** | **0** | **+4** |
| #3 | 3 | 26 (31) | 1x9 2x7 3x11 5x4 | 5 | 0 | +3 |
| #3 | **4 (complete)** | **22 (26)** | 1x8 2x8 3x10 | **3** | **0** | **+5** |
| #1 (reference unit), seating 1 | **4 (complete)** | **104 (121)** | 2x90 3x4 4x3 5x20 6x4 | **6** | **0** | **+2** |
| #1, seating 2 | **4 (complete)** | **27 (29)** | 0x3 1x12 2x8 3x2 4x4 | **4** | **0** | **+4** |
| #4 | **4 (complete)** | **28 (32)** | 1x15 2x17 | **1 .. 2** | **0** | **+6** |

ROWS ARE NOT COMPARISONS and the table gives both. A row is one host batch of 44 `mrd`
operations (~0.7 s) against a comparison every ~1.7 s, so a row can land on the same
comparison twice; the NG column counts DISTINCT comparisons, which is the honest denominator.
Unit #2's fixed-threshold run is the case that makes this matter: 5 NG *rows* of 28 are
3 NG *comparisons* of 23.

The same unit #2 goes 3 NG -> 2 NG -> 0 NG as the population grows from 2 to 3 to 4 good
units, which is the mechanism working as designed: the map is the envelope of the good
population, so it is only as complete as the population is.

**ALL FOUR GOOD UNITS ARE MEASURED WITH THE COMPLETE MAP AND NONE READS NG:** 104 + 27 + 22 +
28 = **181 comparisons over four units, 0 NG, worst DAREA 6** (the reference unit, margin +2);
the other three peak at 4, 3 and 2. Acceptance #1 holds for the four units in the population.
What it does NOT establish is generalisation to a fifth good board -- see section 6.

**ATTRIBUTION WARNING, recorded because it happened.** The file now stored as
`u1_seat2.csv` was first filed as unit #2 and then as unit #4 by relay, before the operator
confirmed it was unit #1 in a second seating (dx16 -122 against the long run's dx16 256).
The DAREA numbers are untouched by the relabel; only the unit they are attributed to
changed. The population count itself (`MB_TOL_N = 4`) rests on the operator's placement
bookkeeping and on nothing in the mailbox: measured, a repeated sample of one unit
contributed 12 newly-relaxed cells and a genuinely new board contributed 11..12, so
`MB_TOL_JUMP` cannot police the denominator, and `MB_TOL_EPOCH` counts map generations
(every reference and every clear), not units.

### 2. The defective board still reads NG -- yes, decisively

The contaminated unit (the one that read NG 21/21, DAREA 9..12, DAMP 70..89 under the fixed
threshold), with the four-unit map in force and the map at its MOST PERMISSIVE setting
(MB_TOL_SCALE 256, the value it is learned with):

| quantity | value |
|---|---|
| comparisons | 32 rows, **28 distinct comparisons**, all `MB_DIFF_OK = 1` |
| DAREA distribution | 14 x11, 15 x16, 16 x2, 17 x3 -> **minimum 14, maximum 17** |
| verdicts | **28 of 28 comparisons NG, 0 PASS, 0 CANNOT JUDGE** |
| margin | at least **6 cells above** the limit of 8 on every comparison |
| the map's help to it | DN total 2468 = DVAR 2389 + DRESQ **76** (3.1%) |
| worst row | DAREA 17, DAMP 72, FMAXD 91, DN 79, DRESQ 2 |

**Acceptance #2 holds: 28 of 28 distinct comparisons NG (of 32 rows), DAREA well above the minimum, 0 PASS.**

### 3. Are the defect's cells among the relaxed ones? -- no, and by a measured margin

The map relaxed 75 cells of 14,400 (0.52%). Of the defective board's 2468 deep-cell
observations, the map rescued **76 = 3.1%**, i.e. almost none, and on the worst row 2 of 79.
The relaxed set and the defect's cells are effectively disjoint. No tightening was needed,
so `MB_TOL_SCALE` was left at 256 and the 128/64/0 walk was not run -- the defect was
measured at the most permissive setting the learned map can have, which is the strongest
form this result can take.

The defect's DAREA here (14..17) is larger than the 9..12 measured under the fixed
threshold, but the two runs are not directly comparable: a different reference (taken 14:50,
built by the background rule) and a different placement (dx16 -254, dy16 -74). What is
comparable is that both rules put it at or above the limit on every comparison.

### 4. 100+ comparisons on the reference unit, still scene

Unit #1, 121 rows covering **104 distinct comparisons**, 195 s, map in force, transform
constant (dx16 256, dy16 524, angle 0) for the whole run:

- `MB_DIFF_OK = 1` on **all 121 rows** -- no refusal of any kind, so none attributable to the change.
- 119 PASS, 0 NG, 2 CANNOT JUDGE. Both CANNOT rows are `MB_READY = 0` (the P1 readiness gate
  withheld the verdict; row indices 115 and 119 of `.tmp/stI/u1_long.csv`), not the map and
  not a refusal.
- No PASS with DAREA at or above the limit: the maximum over the run is 6.

## 5. The invariants that make a row evidence

Two checks are computed on every row and both are reported by `ps_ui/stI_rows.py`:

1. `MB_DIFF_DVAR + MB_DIFF_DRESQ == MB_DIFF_DN` -- the cells over 30 grey must split
   exactly into "still over its own tolerance" and "the map called it natural". A row that
   fails this is a torn snapshot (the words were read across a comparison boundary) and is
   reported as such, not used.
2. no row with `MB_DIFF_DAREA >= 8` may read PASS. Zero rows violated it in every run.

Torn rows: 2..8 per run out of 25..121 (a row is a host-side batch of 44 `mrd` operations,
about 0.7 s, against a comparison every ~1.7 s). They are counted, not hidden.

## 6. What remains unverified

- Whether the map generalises to a good board that is NOT in the population. The
  leave-one-out replay says it does not: with a map built from the other unit only, unit #3
  keeps DAREA 3 (1 of 9 deep cells rescued) and `def3` keeps DAREA 2. So on this bench the
  map is closest to a memorised envelope of the four sampled boards; a fifth unseen good
  board would be expected to read like the "map size 2" column above. That is a real
  limitation of the method as measured, and the next session should test it by learning a
  fifth unit and measuring a sixth -- not by learning a fifth unit and measuring the fifth.
  The four-unit result above therefore says "these four good boards now pass", not "any good
  board passes", and it must not be quoted as the latter.
- The 2 NG rows that survived at map size 3 on unit #2 (removed at size 4) and the
  alternation seen once (FMAXD 45..47 vs 82..90, unit #2, fixed threshold) have NO
  identified cause. The AEC hypothesis was tested and rejected where it could be: exposure,
  gain, k, state and steps were constant on every row of the two runs where those words were
  logged. The alternation predates the AEC columns, so it is unidentified, not explained.
- The two surviving-NG rows at map size 3 were the FIRST and LAST comparison of their
  window, with FMAXD climbing 116 -> 133 -> 132 -> 134 at the end; that is consistent with
  a placement-edge disturbance, but nobody saw the operator move and it stays a hypothesis.
- A persistence gate on the DAREA group (build the group from cells whose `FINE_HIT` has
  reached `PERSIST_N`) was designed and NOT shipped, because a firmware change empties the
  map and would have cost four fresh learns plus the whole measurement round again, putting
  acceptance #2 at risk. It is the recommended next change: it cannot absorb a static defect
  (a defect persists) and it does suppress a transient, which is the shape of the failures
  that survived here. Warm-up cost, stated: a freshly placed board would read DAREA 0 for
  PERSIST_N-1 comparisons, which is usually inside the 3-slot settle window but not
  guaranteed to be, so the defect acceptance would have to be re-run with that in mind.
- The map's 11 cells above 100 grey were not capped. The defect measurement shows they did
  not matter here (3.1% rescue), but a different defect could land on them; capping the
  envelope is the fix if that ever happens.
- The `MB_TOL_SCALE` walk (128 / 64 / 0) was NOT exercised on the board, because it was not
  needed. It is implemented and reads back (MB_TOL_SCALE = 256 was written by the firmware
  at boot and by the host), but "it tightens" is a code reading, not a measurement. The
  claim that carries weight today is the one measured at scale 256.

## 7. Provenance note (why the running image's stamp differs from the committed one)

`ps_ui/build_id.h` stamps a hash of the PS source into the image and `main.c` publishes it
at MB_FWID. The image that produced every number above was built at 14:53; a comment-only
edit to the `MB_TOL_EPOCH` documentation at 15:12 changed that hash, and the committed ELF
was rebuilt at 15:48 so that `ps_ui/ps_ui.elf`, `ps_ui/build_id.h` and `ps_ui/main.c` are
consistent with each other in the repository. The board is still running the 14:53 image:
its code is identical (the only difference between the two sources is a comment) but its
MB_FWID stamp is the earlier hash. It was deliberately NOT reflashed, because a flash forces
a fresh reference and empties the learned map, i.e. it would have destroyed the state every
acceptance number here was measured with. A package check that compares the board's MB_FWID
against `dl/build_id.py`'s current value will therefore report a mismatch until the image is
flashed again; that is expected and is recorded here rather than left to be discovered.

