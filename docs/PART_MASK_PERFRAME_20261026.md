# Per-loop part-mask publication (item 1), 2026-10-26

Firmware: `ps_ui/main.c`, build hash `B9406BAF` (firmware word MB_FWID1).  Board:
Zynq-7020, cold bring-up this session (`stereo_bringup_byname.tcl` -> `disp_fix_20261023.tcl`
-> `strict_load_cores.tcl`), bitstream SHA256 `BAF0DCE1…B2DF8` = `safe_bitstreams/BIT_20261024_fp1.bit`
(byte-identical to the file the bring-up script loads from D:).

## 0. The one-paragraph answer

The part's position was republished only once per comparison (one loop in `DIFF_EVERY` =
16), measured at 1.4-2.4 s; it is now republished from **every loop** on the store the loop
has already selected.  A full shipped mask per loop was built first and **measured at
20.3..26.0 ms**, moving the loop 137.4 -> 176.6 ms, so it was rejected.  The shipped pass
uses the same threshold, brightness compensation and 3x3 erosion **without the cluster
rule**, and costs **4.8 ms** (background path) measured in `MB_PART_TK_MS`.  The loop cost
is not hidden: with the publisher ON the measured loop is **138.0 ms** against **104.9 ms**
in the same scene with it OFF (one variable: `MB_PART_TK_ON`), and the extra ~28 ms is
**not** the 4.8 ms pass itself - see section 4.

## 1. The defect being fixed (measured 2026-10-25, re-used as the baseline)

`dl/host_qc/README.md` section 13 "The live fast-poll runs and the publish-rate limit":
`MB_PART_PTS` was republished at the comparison/refusal cadence only - 595 held 1.74 s,
258 held 2.4 s, 89 held 0.9 s and 1142 arrived inside one 80 ms poll.  The belt carries a
part 30-60 lattice cells inside one such interval, so the same creep target (550) landed
the part at **x65 in one run and x36 in the next** (29 cells = 232 px), and a reference
taken at one landing did not register the other (`MB_DIFF_OK` = 5).  No host-side poll or
tuning fixes a 1.5 s-old number.

## 2. What is published per loop, and from which frame

`part_track()` (main.c, the block after `part_bbox_publish`), called once per loop
immediately after the capture store is selected and invalidated (`main.c`, the
`part_track(g_long_buf);` call before `tC`), so it reads the store the loop is about to
render and the ring cannot come back to it for three handovers.

Per loop it publishes, from ONE pass over ONE frame:

| word | meaning per loop |
|---|---|
| `MB_PART_PTS` (366) | cells over the mask threshold after the 3x3 erosion - the same quantity the comparison publishes as `MB_PART_RAW`; this is the **pre-cluster** count |
| `MB_PART_BX0/BY0/BX1/BY1` (115/116/136/166) | the mask's bbox, lattice cells, from the row/column profile |
| `MB_PART_EDGE` (167), `MB_PART_INVIEW` (69) | border clearance and "a real part wholly in view", same formula as the comparison |
| `MB_PART_RAW` (21) | the same eroded count (equal to PTS by construction in this pass) |
| `MB_PART_RULE` (35), `MB_PART_BGWHY` (37) | which rule ran (0 green, 1 background) and why the background rule could not |
| `MB_BG_MEDD` (39) | background health, background path only |
| `MB_PART_MEDIAN` (369) | the green rule's score median, green path only |

New words (the old mailbox had **no free index**, see section 5):

| word | index | meaning |
|---|---|---|
| `MB_PART_TK_ON` | 512 | host: 1 = per-loop publish (default), 0 = old cadence (A/B arm) |
| `MB_PART_TK_MS` | 513 | ticks the per-loop pass took, `/334800` = ms |
| `MB_PART_TK_N` | 514 | per-loop passes since boot (proves the cadence) |
| `MB_PART_PTS_C` | 515 | the comparison's **clustered** count - the old meaning of `MB_PART_PTS` |

The comparison's arithmetic is untouched: it still builds the clustered mask every
comparison; only its count now lands in `MB_PART_PTS_C` (and in `MB_PART_PTS` too when
`MB_PART_TK_ON` = 0, which is what makes the A/B about the same word and one variable).
The comparison's globals (`g_part_pts`, the AEC's input, the audit words) are not modified
by the per-loop pass.

The box is a **profile** box, not the cluster's box: a row or column bounds it only if it
carries at least `TK_LINE_MIN` = 8 mask cells.  That floor exists because the part-view
note at `draw_camera_impl` measured an isolated lattice point at (138,7) stretching a
496x264 box to 680x648; a per-loop box that chases speckle would make a closed-loop stop
jitter.  On the production state the profile box and the cluster box agreed to the cell
(x47..102 y50..79 from the comparison; the per-loop words read within one cell).

## 3. The rejected version, with its numbers

The first implementation called the shipped `part_masks()` once per loop (full rule
including the cluster) and published from the returned mask.  Measured on the board
(background rule active, part at the station):

| measurement | value | how |
|---|---|---|
| pass cost | 20.3, 20.3, 26.0 ms | `MB_PART_TK_MS` / 334800 |
| loop, per-loop mask ON | 176.60 ms | `MB_T_TOTAL / MB_T_N / 334800` |
| loop, same build before the call was added | 137.4 ms | `dl/STAGE8_20261024_fine_cells_and_adaptive.md:221` |
| delta | +39 ms, +28.7% | |

The dominant cost is the cluster rule's 49-neighbour dilation plus flood fill, which
`part_masks()` runs **twice** when both rules are measured (green audit and background
answer).  The 0.9 M-pixel-read figure in the brief (14,400 cells x 64 px) is not what this
firmware ever computed: one lattice cell is the 2x2 green box at (8i,8j), four reads, so
the lattice is 57,600 reads.  The pixel reads are not the problem; the byte passes are.

## 4. The shipped cost, and what it does not explain

Same board, same scene, production state (background from the empty belt, part at the
station, `MB_PART_REF` 586, `MB_DIFF_OK` 1, `DAREA` 0 < limit 8):

| measurement | TK_ON=0 | TK_ON=1 | how |
|---|---|---|---|
| loop | 104.9 ms (twice) | 138.0 ms (twice) | `MB_T_TOTAL/MB_T_N/334800`, 32-loop windows |
| class phase | 15.6 ms | 35.7 ms | `MB_T_CLASS/MB_T_N/334800` |
| loops/s from the frame counter | 9.3-9.4 | 6.2-7.3 | `MB_PS_FRAMES` delta / host clock |
| per-loop pass | - | 4.83 ms (one 16.2 ms sample) | `MB_PART_TK_MS` |

**Finding, stated rather than averaged away:** enabling the publisher costs +33.1 ms
(+31.6%) on the same build and scene, while the pass itself measures 4.83 ms.  The
difference is in the class phase (+20.1 ms) and the other phases; the leading candidate is
the bounded capture-handover wait inside that same phase (`MB_CAP_MSB` is 0 by default, so
`cap_read_index()` uses the edge-wait fallback and a slower loop arrives at a different
point in the capture cycle).  That has **not** been separated with a timing word, so it is
reported as an unattributed remainder, not as a claim.  Relative to the historical
137.4 ms loop the ON build is neutral; relative to its own OFF state it is +31.6%.

On the empty belt the same A/B read 100.1 ms (OFF) and 118.7-120.1 ms (ON).

## 5. Buffers, OCM, DDR, and why the mailbox went past 512

* `TRACK_MASK` = 14,400 B at **0x126B8000**, in the 51,136-byte hole between `LATT_BASE`
  (ends 0x126B3840) and `LIVE_MASK` (0x126C0000).  It is DDR, CPU-only, cacheable, no DMA;
  it is deliberately **not** `LIVE_MASK`, which the registration, the fine pass and the
  part-view framing read outside the comparison.
* profile arrays: `g_tk_row[90] + g_tk_col[160]` = 250 B of `.bss`.
* OCM: build end `0x1E728`, OCM region is 128 KB (0x0..0x20000) -> **6,360 B free**
  (before this change: 7,872 B).  `.text` +1,200 B, `.bss` +304 B.
* the mailbox had **zero free indices** (`python dl/mb_words.py`: 352 defines, all
  240..307 / 315..326 / 330..365 / 416..460 are array bases, 160..163 are literal writes).
  Words 512+ are inside the 1 MB mailbox region (0x10F00000..0x10FFFFFF), so the 512-word
  limit was a convention; `dl/mb_words.py` `WORD_LIMIT` is now 640 and the regenerated map
  is `dl/MB_WORDS_20261026.md`.

## 6. Acceptance: part moving by hand, host polling at 20 ms

PENDING - the JTAG link dropped at 19:03 before this measurement and the board had not
come back when this section was written.  Procedure (one operator action, ~50 s of sliding
the good board sideways by hand, no motor):

1. `MB_PART_TK_ON = 1`, poll `part_pts`, bbox, `part_inview` and `part_pts_c` every 20 ms
   with one persistent xsdb session (`qc_fast.PersistentXsdb`, mrd only).
2. split the log where the flag changes; per segment report the number of distinct
   (pts, bbox, inview) values and the hold interval between changes.

## 7. Limits and what remains unverified

* The per-loop count is **pre-cluster**.  In the production (background) state the cluster
  kept the whole eroded mask on this bench (`MB_PART_PTS` 590 / 600 vs `MB_PART_PTS_C` 590
  / 600); under the green fallback (no background) the cluster trimmed ~34% (1719 -> 1143).
  Host thresholds measured against the clustered count (380 / 550 / 635 / 800 in
  `dl/host_qc/README.md`) are therefore **not** the same numbers under the green fallback;
  under the background rule they agree on this bench.
* The profile box is not the cluster box; measured agreement was <= 1 cell here, not proven
  over a population.
* The per-loop mask is taken from the single selected frame, not from the `MB_AVG_N`
  average the comparison uses; the two can differ by the noise the average removes.
* The +28 ms of loop time not explained by the pass (section 4) is unseparated.
* The motion acceptance (section 6) is not measured yet.

## 8. Reproducing it

```
# cost and cadence words (read-only, one persistent session):
python dl\host_qc\qc_fast.py --selftest
# A/B on the same build:
#   write 0 to word 512 (MB_PART_TK_ON), read MB_T_TOTAL/MB_T_N, then write 1 and repeat.
# map:
python dl\mb_words.py --write dl/MB_WORDS_20261026.md
python dl\host_qc\check_words.py
```
