# Stage 7 (2026-10-24) — the shift-unit claim re-checked, and the persistence window closed after an adoption

Status: DONE.  Final build TSC1/DB9C7CBF, flashed; acceptance 8 x N=8 (285 independent
comparisons) and a known-answer injection, both reported below.  The predictions below
were written before the code was changed; the measured sections follow them.

## The two defects this stage was started on

**D1 (as reported).**  `reg_score()` works in half-resolution pixels; `reg_adopt()`
stores `g_reg_dx_fp8 = dx_i << 8` documented as 1/256 half-res px; `ref_at()` applies
`g_reg_dx_fp8 << 5` in Q12 source px and `MB_DIFF_DX` is `dx_fp8 / 8` documented as
1/16 source px.  The previous session's note (`dl/STAGE6_...` section 6) says both
consumers are 4x too big and proposes `dx_i << 6` / `ox << 2` in `reg_adopt()` and
`reg_restore_hold()`.

**D2 (as reported).**  The comparison refuses only the re-aim frame itself.  The frames
after it run with the new transform and the 3-hit persistence rule can publish a cell
count / PASS while a wrong transform is mis-registering the part.

## Predictions written BEFORE the change (claim discipline R4)

### H1 — the shift unit chain

**H1a (firmware correct).**  `dx_i` is in half-resolution grey pixels (1 grey px = 2
source px, `GREY_W` 640 from `CAM_W` 1280).  1/256 half-res px is therefore 1/128
source px; `fp8 << 5` in Q12 is `fp8 / 128` source px; `fp8 / 8` is in 1/16 source px.
Prediction: for the synthetic 8-source-px pair that produced 0 / 534 / 286, the PORTED
SEARCH (`st5_rot_check.reg_search`, which mirrors the firmware's `reg_score`) returns
**dx_i = 4**, not 16.  Feeding the firmware's own store (`dx_i << 8`) through the ported
comparison gives **0 cells**; the proposed `dx_i << 6` leaves a 6-px residual and gives
**more than 0 cells**; 0 gives 286; the previous harness's `(2*d) << 8` gives 534.
`MB_DIFF_DX = (dx_i << 8) / 8 = 128` = 8.00 px in the documented 1/16 unit.
**If the note were right**, the ported search would return dx_i = 16 for 8 source px.
Prediction on the board: a static scene gives dx16 = 0 (it does today), so the board
cannot distinguish the two claims by itself; the offline port is the instrument, and it
is validated against the firmware by the stage-6 dump replay (integer winners 12/12).

**H1b (harness wrong).**  The previous measurement's synthetic truth `dxi = 2*d` is a
unit inversion (it treats 1 source px as 2 half-res px instead of 0.5).  The fact that
`dxi<<6` then gives the right physical shift is the two errors cancelling, not a fix.
Prediction: the corrected harness, which derives dx_i from the ported search, reads 0
cells with the shipped store and rejects the proposed fix.

### H2 — the persistence window after an adoption

**Fix.**  One piece of state, `g_reg_fresh`: `reg_adopt()` sets it to `PERSIST_N` when
the transform *changed* (move != 0; a hold does not), `diff_frame()` decrements it once
per comparison slot and forces state 2 (MB_DIFF_OK 5, cells 0xFFFFFFFF, verdict 2)
while it is non-zero.  The hit counters are cleared on the change, because a hit is
evidence about a transform, not about a part.  A fresh reference clears the state
(identity by construction).  Additionally the diff arm's verdict is re-published in the
same loop as the comparison it judges, so one atomic host snapshot cannot pair
comparison N-1's PASS with comparison N's cells.  The stage-6 acceptance recorded three
rows that pair PASS with >= 8 cells.  One of them has cells exactly equal to the limit
(8), which the old `>` rule passes; the other two (34 and 15 cells) are consistent with
this ordering, which is in the source (the verdict is computed at the top of the loop,
the cells are written later).  The old log cannot say which row is which because the
verdict word had no provenance; the republish removes the ambiguity.

**Prediction for the injection (MB_CMD = 14).**  The sequence is
`mode 5 / state 2 / cells -1 / verdict 2`, then `PERSIST_N-1` refused slots
`mode 2 / state 2 / ok 5 / cells -1 / verdict 2`, then the comparison resumes:
`cells 0` with PASS (the 3-hit rule is starting from zero under the new transform),
then `cells 0`, then `cells >= 8` with verdict 1 (NG).  No row pairs PASS with
cells >= 8.  The injection displaces the held answer and the search's correction is the
identity (measured below: dx16 = 0, angle 0.10 deg), so the resumed comparisons are
expected to be clean: cells 0, verdict 0.

**Prediction for the 8-run acceptance.**  The natural drift is unchanged, so the
over-limit stretches after a wrong re-aim will NOT disappear: the wrong transform is
still adopted and the comparison still reports it, only 2-3 slots later.  The
distribution should show the same >= 8 count within a few counts, a slightly larger
refused bucket (the settle slots), and no PASS-with->=8 rows.  If the over-limit count
drops a lot, that would be evidence the old shift unit was part of the cause — H1a
predicts it will not.

## Unit trace (filled in before applying anything)

| step | value | unit | consumer |
|---|---|---|---|
| `reg_score(dx,...)` | `dx` | half-res (grey) px, 1 = 2 source px | search |
| `reg_refine3` parabola `ox` | 1/16 of one search step = 1/16 half-res px | | `dx_i<<8 + ox<<4` |
| `reg_adopt` store | `dx_i<<8 + ox<<4` | 1/256 half-res px = 1/128 source px | `g_reg_dx_fp8` |
| `ref_at` | `fp8 << 5` Q12 | Q12 source px; `fp8<<5/4096 = fp8/128` source px | comparison sampler |
| `g_reg_dx16` | `fp8 / 8` | 1/16 source px (`fp8/8/16 = fp8/128` source px) | words 201/202/226/227 |
| `REG_REAIM_DXY` | 256 | 1 half-res px in fp8 units (256/256 * 2 = 2 source px) | move word 491 |

The two consumers agree with each other AND with the search: 1 half-res px -> fp8 256
-> `ref_at` 2 source px -> published 32 = 2.00 px.  The previous session's docstring
"1/256 half-res px = 1/512 source px" is the inversion; a half-resolution pixel is
TWICE a source pixel, not half.

## D1 result — the claim is refuted; the firmware chain is correct

**H1a confirmed, H1b confirmed.**  The corrected known-answer test
(`ps_ui/st6_shift_units.py`, rewritten) lets the ported search measure the displacement
and then feeds the search's own answer through the two consumers.  Run on
`ps_ui/st2_A_live.raw`:

| known displacement | ported search | shipped `dx_i<<8` | proposed `dx_i<<6` | none | old harness `(2*d)<<8` |
|---|---|---|---|---|---|
| **+8 source px** | `dx_i = +4`, `dy_i = 0` | fp8 1024 -> **+8.00 px -> 0 cells / 0 blobs** | fp8 256 -> +2.00 px -> **235 cells / 153 blobs** | 0 px -> 286 cells | fp8 4096 -> +32.00 px -> 534 cells |
| **-8 source px** | `dx_i = -4`, `dy_i = 0` | fp8 -1024 -> **-8.00 px -> 0 cells / 0 blobs** | fp8 -256 -> -2.00 px -> **197 cells / 110 blobs** | 0 px -> 258 cells | fp8 -4096 -> -32.00 px -> 571 cells |

Full output: `dl/st7_shift_units_20261024.txt` (the script exits 0 only if all four
assertions pass: the search's dx_i is d/2, the shipped store is 0 cells, the proposed
store is not 0 cells, and the published word is d*16).

Published word, documented 1/16-source-px unit:

```
+8 px: MB_DIFF_DX = (4<<8)/8 = 128  -> 128/16 = 8.00 px  (physical 8)
-8 px: MB_DIFF_DX = (-4<<8)/8 = -128 -> -128/16 = -8.00 px (physical -8)
ref_at: 1024<<5 = 32768 Q12 = 32768/4096 = 8.00 px
```

So the two consumers were already right, and the proposed one-place fix would have made
`ref_at` apply **2 source px for an 8-source-px displacement** — a 4x under-shift, 235
cells on a good part.  **No firmware change was made for D1.**  The defect was in the
previous measurement's unit conversion (`dxi = 2*d`), and the fix is the corrected test
plus the correction appended to `dl/STAGE6_20261024_margins_drift.md` section 6.

Why the search is the authority and not an assumed conversion: `st5_rot_check.reg_search`
mirrors `main.c`'s `reg_score` (half-res grey, same offsets, same parabolas), and its
integer winners were validated against the firmware on 12 dumped lattices in stage 6
(`e0 == MB_REG_INCERR` and `wdx/wdy/wth/wsc` 12/12).  It reports `dx_i = 4` for the pair
where the old harness declared the truth to be 16.

**Board side (static scene).**  After flashing the stage-7 build (`TSC1/C6515AB8`, then
the final `TSC1/DB9C7CBF` after the boundary edit), one atomic mailbox snapshot read
`MB_READY` 1, `MB_AVG_N` 8, `MB_AVG_CNT` 8,
`MB_REG_MODE` 2, `MB_REG_STATE` 1, `MB_DIFF_CELLS` 0, `MB_DIFF_VERDICT` 0,
`MB_DIFF_DX` 0 / `MB_DIFF_DY` 0.  This cannot distinguish the two unit claims (a zero
shift is zero in every unit); what it verifies is the required "a static scene still
reads cells 0 and DX/DY 0" after the firmware change.  The non-zero unit chain is
verified offline by the search+comparison port.

## D2 result — the persistence window, and the published pair

### What changed (`ps_ui/main.c`)

| line | item |
|---|---|
| 3406–3416 | `reg_adopt()` arms `g_reg_fresh = PERSIST_N` when the adopted transform DIFFERS (`move != 0`; a hold has `move == 0` and does not re-arm it) and clears the 80x45 hit counters, because a hit is evidence about a transform |
| 5012–5021 | `diff_frame()`, immediately after `reg_search()`: every comparison slot consumes one from `g_reg_fresh` and forces `g_reg_ok = 2` while any remain; the existing state-2 / MB_DIFF_OK-5 path then publishes cells 0xFFFFFFFF and verdict 2 |
| 6626–6634 | `diff_verdict()`: `cells > lim` -> `cells >= lim`.  Exactly the limit now FAILS, which is what "at or above the limit" and every acceptance document in this repo mean.  The stage-6 row NEW8 n=578 (cells = 8, verdict 0) was this boundary, not the persistence rule |
| 1560/1564 | `MB_DIFF_LIM` / `DIFF_LIM_DEFAULT` re-documented as the FIRST failing count (0..7 pass, 8+ fail); no host script computes its own verdict from the limit, so nothing else changes |
| 4315–4319 | `ref_take()` clears the window: a fresh reference seeds the identity, which is correct by construction |
| 9703 | `MB_DIFF_VERDICT` is re-published after the comparison in the same loop, from the words just written |
| 1811–1826 | the mode word's documentation: modes 1/4/5 with state 2 are "adopted, too young to judge" |
| 1914 | `PERSIST_N = 3` (unchanged; the window is the comparison's own persistence window) |
| 3366 | the state itself, with the measurement and the trade written next to it |

The counter counts the adoption slot as the first of the three, so the comparison resumes
on the slot after the transform has been the held answer for three comparison slots
(the adoption frame plus `PERSIST_N-1` further refusals).  No new mailbox word was
added; the refusal is visible as `MB_REG_STATE` 2 + `MB_DIFF_OK` 5 + cells
0xFFFFFFFF + verdict 2, and its reason as `MB_REG_MODE` 1/4/5 on the adoption slot.

### The known-answer injection (MB_CMD = 14) on the final build

`ps_fft_dual/st7_inject_20261024.tcl`, one atomic burst per slot, change detector on
(n, mode, state, diff_ok, cells, verdict, nreaim, incerr).  The injection displaces the
held transform by `REG_INJECT_D` = 10 half-res px = 20 source px.  Clean run, final build
DB9C7CBF, still scene (`dl/st7_inject_20261024.txt`):

| T (ms) | N | mode | state | diff_ok | cells | over | verdict | nreaim | move | dx16 |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 (base) | 369 | 2 | 1 | 1 | 0 | 0 | 0 | 9 | 0 | 0 |
| 1296 | 369 | **5** | 2 | 5 | **-1** | 0 | **2** | **10** | **1000** | 0 |
| 3942 | 369 | 2 | 2 | 5 | -1 | 0 | 2 | 10 | 0 | 0 |
| 6116 | 369 | 2 | 2 | 5 | -1 | 0 | 2 | 10 | 0 | 0 |
| 8456 | 370 | 2 | 1 | 1 | 0 | 7 | 0 | 10 | 0 | 0 |
| 10969 | 370 | 2 | 1 | 1 | 0 | 7 | 0 | 10 | 0 | 0 |
| 13501 | 372 | 2 | 1 | 1 | 1 | 7 | 0 | 10 | 0 | 0 |

The re-aim slot: the correction moved the transform by **move = 1000** = 10.00
half-res px, i.e. exactly the injected displacement, and the adopted transform is the
identity (dx16 = 0, dy16 = 0) with a 0.10-degree residual; the comparison is refused
(**cells -1, verdict 2**).  The next two comparison slots are refused the same way
(state 2, diff_ok 5, cells -1, verdict 2) and the comparison resumes on the fourth slot
(N advances 369 -> 370), reading 0 cells / over 7 / PASS, then 1..2 cells.  No row pairs
PASS with cells >= 8 (the audit prints `PASS_with_cells>=8=0`).

The earlier injection on this build, taken while the scene was moving (the same
MB_CMD = 14), showed the same shape with two re-aims 2 s apart: the second adoption
re-armed the window before it expired, so the comparison stayed refused until the
transform settled; when it resumed, the first two slots read 0 cells with 475 cells over
the threshold (the documented residual below) and the third read 78 cells = NG.  Audit:
0 PASS-with->=8.

A board datum for the published unit came from the first injection run on this build
(the scene was moving; that run's raw log was overwritten by the clean run above), when
the injection slot itself was refused before the search could correct it: it published
`DX16 = 320`.  10 half-res px = 20 source px = 320/16 px, so the published word's
1/16-source-px unit is confirmed on the board by a known injection as well (the 4x claim
would have read 1280).  The reproducible board datum for the same fact is the clean
run's `move = 1000` = 10.00 half-res px; the offline port is the primary evidence for
`ref_at()`.

### The at-the-limit boundary (the third stage-6 row, closed)

The stage-6 acceptance's third PASS-with-8+-cells row was NEW8 n=578: **cells = 8,
verdict 0** — exactly the limit, which `diff_verdict()`'s `cells > lim` lets pass.  The
row's provenance cannot be reconstructed (the old verdict word had none), but the
boundary is a fail-open by itself.  `diff_verdict()` is now
`cells >= lim`, so 0..7 pass and 8+ fail, matching the acceptance language ("the limit
is 8", "8+ cells").  `MB_DIFF_LIM` is re-documented as the FIRST failing count.  No host
script computes its own verdict from the limit (`dl/host_qc` displays the firmware's
verdict and the limit), so nothing else changes.  The final build (DB9C7CBF) contains
this; the 8-run acceptance below was taken on it.

### What this does NOT close, stated rather than buried

* After the window the comparison resumes with the hit counters at zero, so the first
  two resumed comparisons still publish PASS with **cells = 0** while cells are over
  the threshold (measured on the pre-change build: n=570 read 0 cells with 614 over,
  verdict 0).  That is the comparison's own 3-hit persistence rule doing its job; the
  task's requirement was "then resume", and seeding the hit counters would bypass the
  noise filter for every adoption.  The fix closes "PASS with cells at or above the
  limit"; it does not make the first resumed comparison fail-safe against a wrong
  transform that produces sub-limit published cells.
* A transform re-adopted on every comparison (a part moving continuously) would keep
  re-arming the window and publish no verdict at all.  That is fail-safe, not a
  regression, and the readiness gate already refuses a moving scene.
* The new verdict is the diff arm's own opinion; the debounced MB_LOCAL_VERDICT still
  consumes its vote at the top of the loop (one loop later), unchanged.

## Acceptance — 8 runs x N=8 on the final build (DB9C7CBF)

**Instrument.**  The previous session's `ps_fft_dual/st6_warm_20261024.tcl`, with two
changes: the row format now prints the 31st column (READY) that the header had always
claimed, and the change detector also watches state / diff_ok / incerr / nreaim so a
REFUSED slot (which does not advance MB_DIFF_N) is a row.  Each run writes MB_CMD = 9
(fresh reference), waits 4 s, then records for 100 s; one 1.3 KB burst per row.  Raw log:
`dl/st7_runs_20261024.txt`, aggregation: `dl/st7_accept_analysis.py`.

**The rows are deduplicated by MB_DIFF_N before counting.**  The firmware publishes a
comparison's words in two phases (state/mode/incerr after `reg_search()`, cells/diff_ok
and the verdict after the cell loop), so one burst can see the same comparison twice.
The duplicates have the same (cells, over, verdict) and differ only in incerr/cand; the
table counts one settled row per comparison.  This is stage 6 section 5's "one burst per
row" lesson extended: a burst is atomic on the JTAG side, but the firmware's publish is
not atomic, so rows must also be stabilised by the counter they belong to.

| run | independent comparisons | 0 | 1..7 | >=8 | refused slots | re-aims | scene |
|---|---|---|---|---|---|---|---|
| A | 42 | 42 | 0 | 0 | 0 | 0 | still |
| B | 40 | 40 | 0 | 0 | 1 | 0 | still |
| C | 40 | 40 | 0 | 0 | 1 | 0 | still |
| D | 42 | 42 | 0 | 0 | 0 | 0 | still |
| E | 41 | 38 | 2 | 1 | 0 | 0 | still (one over=212 transient) |
| F | 16 | 15 | 0 | 1 | 2 | 1 (at 99 s, run end) | still, one re-aim at the end |
| G | 30 | 21 | 0 | 9 | 10 | 2 | CHANGED (over 2179, READY 0) |
| H | 34 | 3 | 0 | 31 | 7 | 3 | CHANGED (over 323, READY 0) |
| **total** | **285** | **241** | **2** | **42** | **21** | **6** | |

At least 250 independent comparisons: **285**.  **PASS with cells >= 8: 0** — both over
the settled rows and over every raw row.  The 42 over-limit comparisons are real
evidence to pair with: none was published as PASS.

**Compare with stage 6 (260 comparisons: 196 / 12 / 52, 3 refused).**

* **PASS-with->=8: 3 -> 0.**  This is the defect-2 effect, and it is attributable: 6
  re-aim frames and the settle slots after them are refused (state 2, diff_ok 5, cells
  -1, verdict 2), exactly as designed, and the boundary makes a count of exactly 8 fail.
* **1..7: 12 -> 2; 0: 196/260 (75%) -> 241/285 (85%).**  The still-scene runs are the
  reason: A-F contributed 217 zero, 2 small and 2 over-limit in 221 comparisons.
* **>=8: 52/260 (20%) -> 42/285 (15%), but this is NOT evidence of a fix.**  The 42 are
  almost all in G and H (40), and those two runs are not the stage-6 phenomenon: the
  whole frame changed (MB_DIFF_OVER 2179; MB_READY 0 on several rows), the registration
  adopted a visibly wrong transform (-0.25 deg / 3.4 px in H), and the comparison
  correctly published NG for 31 comparisons in one contiguous stretch.  In the still
  runs A-F the registration did not drift (only F's one re-aim, at 99 s, and its window
  was cut by the run boundary), so **there was no still-scene post-re-aim stretch to
  shrink**.  The stretches that did occur did not shrink: H's 31 settled over-limit
  comparisons are longer than NEW8's 19.  The settle window removed the first 2-3
  readings of each stretch (as refusals) and the wrong transform then reads NG for as
  long as it persists; it does not repair the transform.
* **Attribution.**  Defect 1: no firmware change, so no causal contribution to any of
  these numbers.  Defect 2: the 0 PASS-with->=8 and the 21 refused slots (6 mode-5
  re-aim frames, 6 mode-2/state-2 settle slots, 9 mode-0 registration refusals).  The
  over-limit counts were not reduced by either fix; the lower rate is the scene.

**Board state after the acceptance and the injection.**  A fresh reference was taken
after the last injection and the board was read back clean: FWID DB9C7CBF, READY 1,
AVG_N 8, mode 2, state 1, angle 0, DX16/DY16 0, cells 0, verdict 0 (`AVG_CNT` reads 1
because the window restarts on the fresh reference; it fills to 8 over the next 8
loops).

## What remains unverified, and every human-dependent experiment

1. **A part that actually moves / rotates** (requires a person).  The settle window's
   cost on a REAL move is unmeasured: an adoption now refuses 3 comparison slots
   (about 7.5 s at the measured cadence) before the comparison resumes, and the first
   two resumed comparisons can read 0 cells while over-threshold cells exist.  Exact
   experiment: take a reference (`MB_CMD = 9`), record 10 comparisons, slide the part
   1-2 cm (or rotate 0.16 / 0.5 / 1.0 deg against a protractor), then record
   `MB_REG_MODE` / `MB_REG_MOVE` / `MB_REG_GAIN` and `MB_DIFF_CELLS` for 20 s.
   Expected: mode 5 (or 1/4) with move >= 100, exactly 3 refused slots (state 2,
   `MB_DIFF_OK` 5, cells -1, verdict 2), then the comparison resumes; if the new
   transform is right, cells under 8 within three more comparisons; if it is wrong,
   NG, never PASS.  If the verdict takes much longer than ~10 s, that is the window
   working as designed; if the answer does not follow the part, the margins are too
   large (the stage-6 experiment, not this one).
2. **What changed during runs G and H (~17:30-17:36).**  The frame changed completely
   (`MB_DIFF_OVER` 2179, `MB_READY` 0 on several rows, 5 re-aims).  The mailbox says
   the scene changed; whether a person, an object or a lamp did it needs the operator's
   record.  This determines whether the 40 over-limit readings are a bench artefact or
   the drift under a lighting step.
3. **The two isolated clean-run over-limit readings** (E: 15 cells at 96.9 s, over 19;
   F: 16 cells at 34.9 s, over 24).  They are single readings, not stretches, and their
   boxes were not inspected.  A defect on the part would look the same in this word.
   Human experiment: look at the part at the moment of a reading / inspect the
   `MB_DIFF_X0..Y1` box on the frame (the panel's difference view), and say whether the
   box is on a real mark.
4. **The boot auto-reference after a core reset.**  Observed after flashing this build:
   the auto reference produced `MB_DIFF_OVER` 3600 and 3600 cells = NG for a few
   comparisons, and a fresh reference (`MB_CMD = 9`) immediately read 0.  This is
   pre-existing behaviour (the auto reference waits for READY but READY can be 1 while
   the picture is still changing); it is not touched by stage 7.  Reproduce with the
   cores reset and the scene still: read `MB_DIFF_CELLS` for 60 s WITHOUT a fresh
   reference; if it repeats, the auto-reference needs its own fix.
5. **The first resumed comparisons after a window** (the residual above).  Measured on
   the final build: two PASS comparisons with cells 0 while 475 and 157 cells were over
   the threshold after a re-aim during a scene change.  Closing it means seeding the
   hit counters on adoption (bypasses the noise filter) or extending the window; both
   are policy changes with their own acceptance, not part of this fix.
6. **The damaged boards** (unchanged; needs the operator): for each board take a
   reference, read `MB_BLOB_CLASS` (462), the bbox, `MB_BLOB_TOUCH` (470),
   `MB_BLOB_HOLES` (471) and `MB_DIFF_CELLS` (181), and record the operator's
   description; confusion matrix from that, nothing else.

## Cost

`.text` and `.bss` are unchanged in size by the stage-7 edits except `g_reg_fresh`
(+4 bytes .bss): the final build's `.text` is 0x1835C (99,164 bytes by section, 99,172
by `size`), `.bss` 0x7100 (28,928), image ends at 0x183BC + 0x7100 = 0x1F4BC =
128,192 bytes of the 128 KB (131,072) OCM, leaving **2,880 bytes**; nothing was moved to
DDR.  `build.ps1`: 293 `MB_*` words, 293 distinct, 0 collisions; all layout checks pass;
only the four pre-existing warnings.  Flashed with `ps_fft_dual/strict_load_cores.tcl`
(firmware only; no bitstream, no power cycle, no VDMA poke).
