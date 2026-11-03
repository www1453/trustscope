# Conditional design: camera-1 cross-check on a camera-0 NG (NOT BUILT)

Status: **design only**.  It is to be built only if the four measurements in
`dl/XCHECK_20261026_protocol.md` pass.  Written before the board data so the
decision "build / do not build" is not made against a moving target.

## 1. What it would add, and what it would not touch

Untouched: the camera-0 comparison, its gates, `MB_DIFF_DAREA`, the tolerance
map, the registration, the AEC, camera-0's verdict, the STM32 code.

Added: when the camera-0 difference arm is about to publish NG
(`diff_verdict()` reaches `da >= lim`, `ps_ui/main.c:10143-10147`), the same
flagged region is looked at in camera 1.  If camera 1 does NOT differ there, the
difference arm returns CANNOT JUDGE (2) with a distinct reason instead of NG,
and the final verdict becomes CANNOT JUDGE (never PASS).

Decision table:

| camera 0 | camera 1 in the mapped region | published |
|---|---|---|
| DAREA < limit | not consulted | PASS (unchanged) |
| DAREA >= limit | >= threshold | NG (unchanged) |
| DAREA >= limit | < threshold, measured | **CANNOT JUDGE, "single-view anomaly"** |
| DAREA >= limit | cross-check could not run | NG (unchanged -- a broken camera 1 must not turn every NG into a refusal) |

The last row is a deliberate fail-safe choice and is part of the design: only
*positive evidence of a single-view anomaly* demotes an NG.  Absence of a
camera-1 reference is not evidence.

## 2. The correspondence

One plane homography H: cam0 -> cam1, estimated ONCE offline from a still board
pair (the belt plane is planar, so one H serves every placement on it).  The
build stores it as 9 Q16 fixed-point coefficients (or as 4 corner offsets plus a
bilinear correction, if the fixed-point division turns out to be costly).

Per comparison the mapped region is 4 corners, each through the board's own
motion first: `cam1 = H o M0(corner)` where M0 is the registration transform
the comparison already publishes (`MB_DIFF_DX/DY`, `MB_REG_SCALE`,
`MB_REG_ANGLE100`).  4 fixed-point matrix-vector products plus an affine
composition, no division: the homography is applied to a point as
`(h11 x + h12 y + h13) / (h31 x + h32 y + h33)`; 4 divisions per comparison are
acceptable (GDIV on the A9 is ~10-20 cycles).

## 3. The camera-1 reference

Captured in `ref_take()` (`ps_ui/main.c:6975`), from the store camera 1 has just
finished (the same `(raw+3)&3` rule the live path uses, `main.c:12776-12780`),
into a patch buffer:

| item | value |
|---|---|
| what | the camera-1 image of the mapped reference part box + 32 px margin |
| size | ~584 x 324 x 1 B ~= 189 KB for a 520x260 part |
| where | DDR 0x127C4000..0x127FF000 (the free hole below the 0x12800000 MMU limit; no existing buffer moves) |
| when | once per reference, on MB_CMD = 9 |
| cost | copy ~190 KB with row invalidates: ~5-10 ms, once |

Plus the camera-1 frame mean at reference time (1 word), used for the gain.

## 4. The statistic

For every 8x8 cell in the mapped region:
`d = (cam1_live_cell_mean * gain) >> 8 - cam1_ref_cell_mean - bias`,
the same arithmetic as the camera-0 fine pass (`main.c:8036`), with
`gain = 256 * ref_mean / live_mean` from camera 1's own mean
(`MB_CAM1_MEAN`, measured on sampled rows every 4th loop, `main.c:12796`).
Cells with `|d| > 30` are counted and the largest 8-connected group is taken,
i.e. the same amplitude-and-area rule as camera 0.  Decision: single-view if
`cells < XCHK_CELLS_MIN` (to be set from the measured separation of the defect
and the shadow, not guessed).

Cost per use: the region is ~300 cells worst case -> 300 x 64 px x 2 views =
38 KB of byte reads plus ~100 row invalidates: **under 1 ms**, and only on a
comparison that is already NG.

## 5. New mailbox words

The mailbox region is now 1 MB (`dl/MB_WORDS_20261026.md`, WORD_LIMIT 640), so
515+ is free.

| word | name | meaning |
|---|---|---|
| 515 | `MB_XCHK_STATE` | 0 not run, 1 both views differ, 2 single-view anomaly, 3 no cam1 reference, 4 cam1 frame unusable |
| 516 | `MB_XCHK_CELLS` | camera-1 cells over 30 grey in the mapped region |
| 517 | `MB_XCHK_GROUP` | largest 8-connected group of those cells |
| 518 | `MB_XCHK_AMP` | largest |d| in the region, grey |
| 519 | `MB_XCHK_REF_OK` | 1 = a camera-1 reference patch exists |
| 520-523 | `MB_XCHK_BX0/BY0/BX1/BY1` | the mapped region, camera-1 source px |
| 524 | `MB_XCHK_GAIN` | camera-1 gain in force, 256 = 1.0 |
| 525 | `MB_XCHK_N` | cross-checks run since boot |

## 6. Cost and risk

- Firmware: ~150-200 lines, 10 words, one 189 KB DDR buffer, no OCM change, no
  PL change, no new bitstream.
- Loop: **0 ms** in the common case (the branch is inside `da >= lim`, which
  never happened in 181 measured good-board comparisons); **<1 ms** when it runs;
  one 5-10 ms copy per reference.
- Effort: 8-10 h including the acceptance rows, IF the fixed homography holds
  across placements.  If it does not, a per-frame camera-1 mask + similarity is
  needed: 12-16 h, at which point the recommendation is not to build it.
- Failure modes to publish, not hide: the camera-1 store can be 1-2 frames old
  relative to camera 0 (independent rings); the camera-1 AEC is free-running, so
  a global brightness step is absorbed by the gain word and a *local* one is
  not; component height parallax is ~5 px/mm between the two views at this
  baseline, so the region is dilated by one cell before counting.
