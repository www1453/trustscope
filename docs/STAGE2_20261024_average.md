# Stage 2 (2026-10-24) — multi-frame averaging: it removes the noise tail and exposes the drift

**Result in one line: with the live side taken as the mean of 8 frames, two independent
acceptance runs read `MB_DIFF_CELLS` = 0 in 90 of 90 comparisons (and a third read 0 in 45
of 47, the other two 1) on a still scene with a fresh reference, against 0 in 79 of 86 and
8..9 in two at N = 1 on the same build — while the per-judgement time did not change at
all (6.39 fps at N = 1, 4 and 8, measured back to back on the same scene).  It is shipped
as the boot default (`AVG_N_DEFAULT` 8, host-overridable).  The honest cost: averaging
also turns a registration drift that the shipped build hides (a held transform 2.5 px off
reads 0 cells at N = 1) into a visible 14..25-cell difference, so the drift is now the
dominant remaining defect and it is Stage 0's, not this stage's.**

## What changed (`ps_ui/main.c`)

| line | item |
|---|---|
| 1614 | `DIFF_EVERY` — the comparison cadence, named because the sampler must know where in the window it is |
| 1899–1916 | the nine words 408..415, 461 and the 45 row words 416..460 (see "what is published") |
| 2523 | `latt_point()` — the lattice point sampler, extracted so `latt_fill()` and the Stage 2 sampler cannot drift apart |
| 2584–2587 | `AVG_LATT_SUM` / `AVG_CELL_SUM` (DDR, in the 60 KB hole between the readiness grids and `GREY_BASE`), `AVG_N_MAX`, `AVG_N_DEFAULT` |
| 2606 | `avg_reset()` — zero both accumulators; called on every comparison loop, refused or not |
| 2627 | `avg_sample()` — one loop's contribution, guarded by `MB_READY == 1` and by the tear detector |
| 2668 | `avg_take()` — divides the sums, writes `LATT_BASE`, returns the frame count actually averaged |
| 2693 | `isqrt64()` — integer square root for the published sigma |
| 4256 | `diff_frame()` takes the average once and uses it for the live cell means |
| 4327 | `latt_fill()` is skipped when there is an average, so the registration scores the averaged lattice |
| 4419 | the per-row mean difference, published (45 words) |
| 8495 | the sampler call in `main_loop`, after `settle_gate()` published this loop's readiness |
| 8682 | the window closes on every comparison loop |

Design rules that are load-bearing and must not be "cleaned up":

1. **N = 1 is the old code path, not a second implementation.** `avg_sample()` returns
   before touching memory and `diff_frame()` takes the `cell_mean4()`/`latt_fill()` branch,
   so the control and the treatment differ in exactly one variable. That is what makes the
   A/B below an A/B.
2. **The window ends on the compared frame.** The comparison runs on one loop in
   `DIFF_EVERY`; the sampler takes the LAST N loops of that window (not the first), so the
   mean is of the frames immediately before the picture it is handed to. Filling up early
   would present a mean that ended half a window (up to 2 s) before the comparison.
3. **A frame that is not ready, or that was written while it was read, is not a sample.**
   `MB_READY` must be 1 (the gate's own opinion of this frame, published earlier in the
   same loop), and the tear detector's row count must be 0 — measured here, 3.8..9.1% of
   renders see a row change, so an 8-frame window has a 30..50% chance of containing a
   spliced frame, and a spliced frame is two pictures, not one. `MB_AVG_SKIP` and
   `MB_AVG_TEAR` publish how many were declined.
4. **The part mask is deliberately NOT averaged.** It is a region, eroded one block on
   every side, so averaging it could only change the boundary band the erosion already
   discards — at three channels per block per loop instead of one. The mask comes from the
   frame being compared; the lattice the search minimises over is the average.

## What is published

| word | what |
|---|---|
| `MB_AVG_N` (408) | host target, clamped to 1..16, echoed every loop |
| `MB_AVG_CNT` (409) | frames the last comparison was the mean of (1 = averaging off) |
| `MB_AVG_SKIP` (410) | loops declined because `MB_READY` was 0 |
| `MB_AVG_TEAR` (461) | loops declined because the store was being written |
| `MB_AVG_TICKS` (411) | ticks one sampling pass took |
| `MB_DIFF_SIGMA` (412) | sigma of the per-cell difference, 1/16 grey level — the noise floor the 14-count threshold sits on |
| `MB_DIFF_OVER` (413) | cells over the threshold BEFORE the blob and persistence rules |
| `MB_DIFF_MAXD` (414), `MB_DIFF_AT` (415) | the largest abs difference and which cell |
| `MB_DIFF_ROW` (416..460) | 45 row means of the difference, 1/16 grey level |

## How the measurement was taken, and what validates the instrument

`ps_fft_dual/st2_accept_20261024.tcl`: write `MB_CMD = 9` (fresh reference from a live
store), wait 4 s, then poll `MB_DIFF_N`; **one printed row per comparison**, because a
comparison is the unit of independence and sampling faster only repeats it (the previous
stage's report makes the same point). Each row is read with the counter checked before and
after, so a comparison that lands between two reads cannot be attributed to the wrong
frame.

Validation of the instrument, in the order it was done:

* **The old build's numbers are reproducible by the same script.** On the shipped build
  (`TSC1/9DD4`, before any of this code existed) the same script read 44 comparisons with
  cells 0 in 37, and `1, 13, 9, 10, 16, 48, 48` in the rest — with the two 48s and the 13
  in **2-row-tall, full-width** bounding boxes (`x0 2..79, y0 30..31`), i.e. a band, and
  the 9/10/16 in a left-edge box. Two different phenomena, both visible before the change.
* **N = 1 on the new build reproduces it**: 43 comparisons, 0 in 36, `2, 2, 3, 6` and
  `8, 9` — same order, same shape.
* **The loop-rate measurement is the firmware's own** (`MB_T_TOTAL`/`MB_T_N`, a sum over 32
  loops) and is cross-checked against `MB_PS_FRAMES` over a 4 s span the host times itself;
  the two agree within 4% at every setting.
* **A scene that is moving invalidates the run, and the run says so.** The first
  shipped-configuration attempt read 20 of 49 comparisons at or above the limit; the
  flagged box was at the frame's LEFT EDGE (x 2..9) — not the part — and
  `MB_AVG_SKIP` had incremented 25 times, i.e. the firmware's own readiness gate had said
  the scene was moving. That run is reported below rather than discarded, and the
  acceptance run that follows it is one in which `MB_AVG_SKIP` did not move at all.

## The numbers (all on this bench, this session, fresh reference before each run)

Cells is `MB_DIFF_CELLS` per independent comparison; the limit is 8. "drift" counts
comparisons in which the registration replaced the held transform (`MB_REG_MODE` != 2).

| run | build | N | comparisons | cells 0 | 1..7 | **>= 8** | sigma16 med | `MB_DIFF_OVER` med / max | max abs d | registration err16 med | drift |
|---|---|---|---|---|---|---|---|---|---|---|---|
| shipped, before | 9DD4 | 1 | 44 | 37 | 1 | **6** | - | - | - | - | - |
| control | 217E0889 | 1 | 43 | 36 | 5 | **2** | 115 | 40 / 1036 | 92 | 136 | 0 |
| N=4, no tear gate | 217E0889 | 4 | 119 | 42 | 0 | **77** | 84 | 43 / 77 | 56 | 88 | 2 |
| N=4, tear gate | AB2BE97F | 4 | 44 | 12 | 31 | **1** | 74 | 8 / 1133 | 93 | 83 | 0 |
| N=8, first run, no tear gate | 217E0889 | 8 | 45 | **45** | 0 | **0** | 71 | 0 / 6 | 18 | 80 | 0 |
| N=8, with tear gate | AB2BE97F | 8 | 45 | **45** | 0 | **0** | 71 | 0 / 6 | 18 | 80 | 0 |
| **N=8, shipped default** | 0E303B49 | 8 | 47 | **45** | 2 | **0** | 74 | 1 / 14 | 17 | 76 | 0 |

The four builds are the four things that changed in this stage, in order: `217E0889` added
the last-N-of-the-window rule and the max-cell location word, `AB2BE97F` added the tear gate,
and `0E303B49` is the same code with the measured default written at boot. The N=1 control
and the N=4/no-gate row are on `217E0889`; the N=8 row is split across the two builds
deliberately, because the two 45-comparison runs are the same experiment with and without the
gate and both are clean.

The two N=4/no-gate runs that dominate that row are the drift runs: the search adopted
`-0.30 deg, dx +0.75 px` in one and `-0.15 deg, dx +2.5 px` in another, 1 and 8 comparisons
after the fresh reference, and every comparison after that read 14..25 cells in a stable
box. The single run in that row with no drift read 0 in 29 of 29.

## Acceptance, item by item

**(a) at least 30 independent comparisons, cells under the limit in every one — MET at
N = 8.** 137 comparisons across three runs (45 + 45 + 47), none at or above 8; 135 of them
exactly 0, two of them 1 (a single cell at 17 counts, box (62,42)-(62,42)). The full
distribution is the `cells` column above; the per-run sequences are in
`dl/st2_N8_20261024.log`, `dl/st2_N8g_20261024.log` and `dl/st2_shipb_20261024.log`. The
margin is not marginal: the raw count of cells over the threshold (`MB_DIFF_OVER`) reads 0 in
the median comparison and never above 6 in the first two runs, against 16..193 at N = 1 --
i.e. at N = 1 the 14-count threshold sits at 1.9 sigma, and at N = 8 at 4.2 sigma.

**(b) the sigma of the cell difference before vs after — 115/16 = 7.2 grey counts at N = 1,
71/16 = 4.4 at N = 8** (median of 43 and 90 comparisons). That is a factor 1.63, against
the 2.83 a perfectly independent 8-frame mean would give — the measured correlation between
frames is real and is the row band below.

**(c) the per-judgement time cost — none measurable.** Same scene, three settings, measured
back to back with no JTAG traffic inside each 12 s window (`st2_cost_20261024.tcl`):

| N | loop ticks / 32 loops | ms/loop | fps (firmware timer) | one sampling pass | the comparison |
|---|---|---|---|---|---|
| 1 | 1,677,191,338 | 156.55 | 6.39 | 15.5 ms (not run) | 69.4 ms |
| 4 | 1,677,187,144 | 156.55 | 6.39 | 15.5 ms | 55.5 ms |
| 8 | 1,677,174,832 | 156.55 | 6.39 | 15.5 ms | 55.6 ms |
| 1 | 1,677,168,785 | 156.55 | 6.39 | 15.5 ms | 69.4 ms |

Two facts, both measured: the comparison itself gets **14 ms cheaper** at N >= 4 because
`latt_fill()` moved into the sampler, and the loop is paced by a wait that absorbs the rest
(the same loop time to four significant figures at every setting, which is also the
observation that 97% of the loop's 156 ms is not CPU work in the timed phases). **So the
cost is not paid in frame rate — but it is not free either**: 8 passes x 15.5 ms = 124 ms of
extra work per 2.5 s window is being hidden by a wait. If that wait ever shortens (a faster
capture, a different store selection), the work becomes visible. The tear rate did not get
worse (3.80% at N=8 vs 4.24..9.08% at N=1, all measured in this session).

## The mechanism the row profile found — this is the part worth keeping

The 45-word row profile of the difference (`MB_DIFF_ROW`) on a still scene is a **smooth
periodic modulation in the row direction**: peaks at gy = 8, 24, 41 and troughs at gy = 16,
34, amplitude +-4..6 grey counts. Period about 12.5 grid rows = 200 source rows, i.e. about
3.6 cycles down a 720-row frame. That is the rolling-shutter bar seen as a *spatial
structure* rather than as a residual, and it is consistent with a lamp whose period is not
an integer fraction of the sensor's readout time (a 20 ms mains period against a ~72 ms
readout gives 3.6 cycles). Two consequences, both measured:

* the band is **below** the 14-count threshold (+-4..6 counts), so it does not by itself
  create cells — which is why the still-scene counts are 0 and not 20;
* it is why the noise floor only falls by 1.63 and not 2.83: consecutive frames share it.

**The averaging also changed what a registration drift looks like, and that is the finding
to carry forward.** At N = 1, a drift to `-0.20 deg, dx -3.5 px` was followed by a comparison
that read `cells = 0` with 193 cells over the threshold — the noise scattered them, so the
3x3 blob rule removed all of them. The shipped build therefore reports PASS on a part it has
just mis-registered by 3.5 pixels, and nothing in the mailbox says so. At N = 8 the same
class of drift leaves a coherent, clustered difference that survives the blob rule and reads
14..25 cells. Averaging did not create the drift; it stopped hiding it. That is a better
instrument and a worse-looking number, and it is stated here rather than tuned away.

## What remains unverified, with the exact experiment

1. **Whether N = 8 is immune to the drift, or was merely lucky twice.** Drift was observed
   in 2 of 3 runs at N = 4 (before the tear gate) and 0 of 2 runs at N = 8. The rate at
   N = 8 is therefore somewhere between 0 and ~40% per 2-minute run, and the sample cannot
   narrow it. Experiment (no operator action needed, ~20 min): run
   `xsdb ps_fft_dual/st2_accept_20261024.tcl X 115 8` five times and count the runs where
   `MB_REG_MODE` leaves 2; if any run drifts, the transform-dependent cell count must not be
   published as a verdict until Stage 0's hold margin is re-derived against the averaged
   lattice.
2. **A part that has actually moved.** Nothing in this session can move it. Experiment: take
   a reference (`MB_CMD = 9`), read `MB_REG_MODE` (393) and `MB_DIFF_CELLS` (181) for 10
   comparisons, slide the part 1-2 cm, repeat. Expected: mode 4 or 1 with a new answer, and
   cells back under 8 once adopted. If it does not follow the part, the averaging is not at
   fault but the margins are too large for this bench (re-derive with `ps_ui/st6_warm_cal.py`).
3. **Whether the row band is mains flicker or the capture seam.** Both produce a row
   modulation. Experiment: point the camera at a matte grey card under the room's light,
   take a reference, and read `MB_DIFF_ROW` (416..460) for 20 comparisons with the lamp on
   and then with the lamp off (a phone torch at a fixed distance is not a substitute). If
   the +-5-count sine disappears with the lamp, it is flicker; if it stays, it is the readout.
4. **The refusal path with no part in view** was not re-exercised this session (it needs the
   operator to remove the part). The code path is untouched by this stage except that
   `MB_AVG_CNT` is published before the refusal, so `MB_REG_STATE = 2` / `MB_DIFF_OK = 5` /
   `MB_DIFF_VERDICT = 2` should be unchanged; the previous session verified it on the same
   code.
5. **The averaging on a moving belt** is out of scope by construction: the sampler refuses
   frames while `MB_READY` is 0, so on a running belt the window fills slowly (or not at
   all) and `MB_AVG_CNT` says so. That is intended, but "intended" is not measured — the
   experiment is a run with the belt running, watching `MB_AVG_CNT` and `MB_AVG_SKIP`.

## Cost and build

`.text` 91,388, `.bss` 31,092 (both inside OCM; 36,000 bytes of accumulator live in DDR at
`0x127B2000`/`0x127BA000`, in the hole between the readiness grids and `GREY_BASE`).
`build.ps1`: 0 mailbox collisions (262 words, 262 distinct), all layout checks pass, only
the four pre-existing warnings. Flashed with `ps_fft_dual/strict_load_cores.tcl`; the board
reads FWID `TSC1` / `0E303B49`, `MB_READY` = 1, `MB_AVG_N` = 8, `MB_AVG_CNT` = 8,
`MB_REG_MODE` = 2 at angle 0.00, `MB_REG_STATE` = 1, `MB_DIFF_VERDICT` = 0 in all 47
comparisons of the acceptance run.
