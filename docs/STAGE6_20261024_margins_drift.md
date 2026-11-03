# Stage 6 (2026-10-24) — the hold margins re-derived on the averaged lattice, and drift published as its own state

**Result in one line: the two hold margins were re-derived from measurements on the
averaged lattice (12 dumped frames, 261 comparisons) and they do not move —
`REG_WARM_MARGIN` 16, `REG_JUMP_MARGIN` 32 — because the measured gap between the largest
gain a WRONG candidate produced (15) and the cost of a real half-degree / one-source-pixel
move (4..31 / 32..89) is six units wide and 16 is the value inside it; what does change is
that a registration which changes its mind now publishes its own state — `MB_REG_MODE` 5,
`MB_REG_MOVE` (491), `MB_REG_NREAIM` (492), `MB_REG_GAIN` (493) — and that frame's
comparison is REFUSED (state 2, `MB_DIFF_OK` 5, CANNOT JUDGE) instead of being compared.
The measured cost of the safe choice, and the measured negative that goes with it: the
drift happened **4 times in 263 comparisons** across 8 runs at N = 8, all four re-aim
frames were refused (no false PASS on them), and **52 of the 263 comparisons still read
8+ cells** after those re-aims, because the refusal covers one frame while the
comparison's own 3-hit persistence rule needs three. One further natural wrong adoption,
taken after the acceptance, was measured WITH its gain: **32**, twice the warm margin and
as costly as a real half-degree rotation — so the drift cannot be tuned away, only
reported. The drift is now countable; it is not fixed.**

## The defect this stage addresses

Stage 2 made the live side the mean of 8 frames and, by removing the noise tail, exposed a
registration drift the single-frame build had been hiding: at N=1 a drift to
−0.20 deg / −3.5 px was followed by `MB_DIFF_CELLS` = 0 while **193** cells were over the
threshold before the blob rule; at N=8 the same class of drift reads 14..25 cells.  The
margins the search uses to decide whether to move were derived on **one frame**, whose
noise floor is 1.6x higher than the averaged one, and nothing in the mailbox distinguished
"the answer was held" from "the answer was replaced by a different one".  Both are
addressed below, and the second turned out to be the more important of the two: the first
re-derivation confirms the old numbers, the second makes the old failure visible.

## 1. The calibration, re-done on the object the search actually scores

`ps_ui/st6_warm_cal.py` put one real frame through the shipped arithmetic.  The search now
scores the **mean of 8 frames**, so the same question is asked of the firmware's own
averaged lattice: `ps_fft_dual/st6_dump_20261024.tcl` dumps `LATT_BASE` (the averaged
lattice), `LIVE_MASK`, `BASE_MASK` and the reference `GREY_BASE` once per comparison (four
reads in ~0.7 s against a 2.5 s comparison period, counter checked before and after), and
`ps_ui/st6_warm_cal_avg.py` replays `reg_score()` on them.

**The dump is validated against the firmware, not assumed.**  In all 12 dumps
(`dl/st6_dump_20261024.txt`, MB_DIFF_N 272..283):
`e0 == MB_REG_INCERR` — the dumped lattice / reference / masks reproduce the firmware's own
error at the held transform **exactly** (66, 65, 73, 62, 63, 73, 66, 63, 70, 72, 66, 71);
the dumped mask sums equal `MB_PART_PTS`/`MB_PART_REF`; and the replay's integer stage
winners equal the published words 235..238 (`wdx`, `wdy`, `wth`, `wsc`) **12/12**.  The
replay's *final* window error agrees with word 239 in 2/12 and differs by 0..10 units in
the rest: the last parabola branch is not bit-exact with the target.  That is the
uncertainty on the absolute costs below; every delta is a difference of scores the same
replay computed on the same data.

**The cost of a known transform error, 1/16 grey level (one level = 16), 24 signed samples
over 12 averaged lattices (`ps_ui/st6_cal_agg.py`):**

| misalignment | min .. max | median | old single-frame figures (Stage 0) |
|---|---|---|---|
| 0.1 degree | −3 .. +6 | +1 | 6 .. 11 |
| 0.2 degree | −5 .. +9 | +3 | 16 .. 24 |
| 0.5 degree | +4 .. +31 | +21 | 42 .. 61 |
| 1 half-res px (dx / dy) | +9 .. +37 / +25 .. +49 | +28 / +40 | 54 .. 92 |
| 2 half-res px (dx / dy) | +32 .. +74 / +44 .. +89 | +53 / +70 | — |
| 1/256 scale | +2 .. +9 | +7 | 25 .. 35 |
| 2/256 scale | +15 .. +29 | +24 | — |

The averaged-lattice costs are 2..4x **smaller** than the single-frame figures the margins
were originally derived from.  Two reasons, stated rather than buried: the old frame
(`ps_ui/st2_A_live.raw`) is a different part placement with a different part size in the
frame, and the old rotation cases were made by resampling the frame, which adds
interpolation blur.  The old numbers are therefore not reproduced by this data set; what
the margins are set by is the *relation* between these costs and the gate's own noise,
which is measured on the same frames.

**The gate's own noise is NOT the frame-to-frame term, and that is the finding.**  The
error of the SAME transform re-measured on consecutive averaged frames (`MB_REG_INCERR`,
word 394) reads 62..73 across the 12 dumps and 65..175 across the runs — a large term.  It
is COMMON MODE: it moves the whole error surface, so it does not move the decision, which
compares the held answer and the candidate **on the same frame**.  The decision's noise is
the *gain of the best wrong candidate* — word 394 minus word 395, measured on every
comparison:

| set | comparisons | min | median | max | gains >= 8 |
|---|---|---|---|---|---|
| 12 dumps (N=8, fresh reference) | 12 | −9 | 0 | +5 | none |
| pre-change build, 5 runs (`dl/st6_runs_pre_20261024.log`) | 185 | −16 | 0 | +12 | 10, 12, 12 |
| this build, 8 runs (`dl/st6_runs_new_20261024.txt`, `..._new2_...log`) | 261 | −14 | +1 | **+15** | 8, 8, 8, 8, 8, 9, 10, 10, 10, 12, 12, 13, 13, 13, 15 |

The largest gain a wrong candidate ever produced while the answer was still right is
**15**; the small ones are steady state, the large ones cluster on the frames where the
room's light changed.  The four natural re-aims and the seven injected ones all gained more
than 16 — the injected ones by construction (10 half-res px), the natural ones by an amount
this build could not publish on the *pre-change* data set (words 394/395 are overwritten by
the adoption), which is why `MB_REG_GAIN` (493) was added.  With 493 in place, **one natural
wrong adoption was measured with its gain: 32** (section 3, last paragraph).  That number is
twice the warm margin and at the top of the measured cost of a real 0.5-degree rotation
(4..31): a spurious move that no margin below 32 can exclude, and no margin above 31 can
exclude without also excluding every real half-degree rotation.  This is the measurement
that settles the margin question: the drift has to be reported, not tuned away.

## 2. The arithmetic the margins are set by, old and new

The margin has to satisfy two inequalities at once:

* **above the noise**: a WRONG candidate must not win.  Measured largest wrong-candidate
  gain: **15** (261 comparisons).  `REG_WARM_MARGIN` = 16 is 1 unit — 1.07x — above it.
* **below a real move**: a candidate that is RIGHT must win.  Measured gains of real moves:
  0.1 deg 2..6, 0.2 deg 1..9, 0.5 deg 4..31, 1 half-res px 9..49, 1 source px
  (2 half-res px) 32..89.

The two inequalities overlap: a 0.5-degree real rotation (median +21) and a 0.5-source-px
real move (9..49) cost about what the largest noise wins cost.  **No margin can separate a
sub-pixel real move from a noise win on this bench** — that is a measured statement, not a
preference — and the admissible window for tracking half-degree rotations is therefore
(15, 21).

* **`REG_WARM_MARGIN` 16 → 16.**  Not inherited: re-derived above.  Lowering it is ruled
  out by the 15-unit gain the gate had to reject (12 in the pre-change set, 15 in this
  one).  Raising it is ruled out by the 0.5-degree rotation cost (median 21, max 31): a
  margin of 24 would stop tracking most real half-degree rotations and produce NG on a good
  part, the opposite failure.  The old comment's figures (0.4..0.7 level for 0.1 deg,
  3.4..5.8 level for a pixel) are superseded by the table above; the conclusion they were
  quoted for survives, the margins do not move.
* **`REG_JUMP_MARGIN` 32 → 32.**  A far candidate comes only from the cold search, whose
  candidate set is ~35x the warm window's (2,205 trial transforms against 63), so the
  extreme accidental gain it can find is larger — which argues for keeping the far margin
  at 2x the near one, as it is.  No far adoption was observed in 261 comparisons; the only
  far candidates measured were re-acquisitions, where the gain is the cost of the whole
  displacement (hundreds against 32), i.e. the jump margin is not what decides them.  It is
  stated as a 2x-of-the-warm prior, not as a measured optimum, because this bench produced
  no data that constrains it.
* **`REG_HOLD_LIM` 240** unchanged: the worst aligned reading measured is 175 (10.9 levels,
  in a scene change) and the unusable limit is 480.

**The margin cannot be the last line of defence; that is why the drift state exists.**  The
four natural re-aims on this build each produced a wrong transform that then read 10..186
cells.  Suppressing them with a larger margin would cost real rotation tracking (above);
the alternative is to make the move visible and refuse its own frame, which is what is
implemented.

## 3. Drift as its own published state (`ps_ui/main.c`)

What changed, with line numbers (all in `ps_ui/main.c` unless stated):

| line | item |
|---|---|
| 3191–3231 | the margin block: the derivation above, replacing the single-frame numbers |
| 3233 | `REG_MODE_REAIM` = 5 — the answer was adopted but it MOVED |
| 3248–3266 | the re-aim bound: one half-res px / 0.20 deg / 1/256 scale, and `REG_INJECT_D` |
| 3310–3311 | `g_reg_move100`, `g_reg_n_reaim` |
| 3323 | `g_reg_gain` (word 493) |
| 3342–3350 | `reg_adopt()` measures the move from the previously published transform, in each parameter's own unit as a percentage of its bound, before overwriting the hold |
| 3416–3428 | `reg_mode_after()`: if the move is at or past the bound, publish mode 5, count it, and set state 2 so the comparison refuses this frame |
| 3710 / 3724 / 3961 / 3977 | the four mode-publishing call sites, now all through `reg_mode_after()`; 3721 and 3990 record the gain |
| 4973–4975 | words 491/492/493 published with the transform they describe |
| 4919–4939 | `MB_CMD = 14`: the known-answer re-aim injection |
| 9711–9723 | the command handler for 14 |
| 1834–1858 | the header documentation of mode 5 and words 491..493 |

**The bound is calibrated, not chosen.**  It is the smallest change of each parameter whose
calibrated cost reaches one comparison threshold (14 counts of 1/16 grey level) — or, for
the shift, the smallest move the search can make beyond its sub-pixel parabola.  Measured
costs of exactly those three changes: 1 half-res px 9..49, 0.2 deg 1..9, 1/256 scale 2..9.

**The comparison is REFUSED on that frame: the safe choice, justified by measurement.**  The
frame on which the registration changes its mind is exactly the frame whose cell count is
not evidence.  Measured on the pre-change build (run PRE1, comparison 335) a warm adoption
moved the transform by 0.30 deg / 2.25 half-res px / 1/256, and that comparison read
`MB_DIFF_CELLS` = **0** while **83** cells were over the threshold before the 3x3 rule; the
three after it read 41, 41, 41.  The same shape was measured again on this build: run NEW3
(identity → −0.30 deg) read 0 cells with 61 over on the adoption frame, then 34..39 cells;
run NEW5 (identity → −0.20 deg / +1.75 px published) read 0 cells with 32 over, then
12..15 cells.  Comparing that frame produces a PASS on a part the registration has just
mis-registered.  The transform IS adopted, so the next comparison already uses it; the cost
is one comparison per re-aim.

The refusal uses the existing `g_reg_ok != 1` path, so it publishes state 2, `MB_DIFF_OK` 5,
and `diff_verdict()` answers 2 = CANNOT JUDGE.  **"Comparison refused" cannot become PASS**:
the fail-safe path is untouched, and in the acceptance no refusal frame read `MB_DIFF_OK` 1.

**A known-answer test for the state (`MB_CMD = 14`).**  Command 14 displaces the held
transform by 10 half-res px and forgets its error; the next comparison has to correct it.
Seven injections (`ps_fft_dual/st6_inject_20261024.tcl`, `dl/st6_inject_20261024.log (git-ignored; the quotes are in this document)`,
`dl/st6_inject2_20261024.txt`) produced seven re-aims, each with

```
mode 5, state 2, MB_DIFF_OK 5, move 881..1225, MB_REG_NREAIM +1, and then a hold with 0 cells
```

Two details the test found and the host must know: (i) the frame before the re-aim is
published as state 3 (UNSTABLE) when the displaced hold can still be scored but does not
fit — i.e. one re-aim is preceded by one UNSTABLE frame, which is what state 3 is for;
(ii) **a re-aim frame is a refused comparison, so `MB_DIFF_N` does not advance on it** — a
host that gates on the comparison counter never sees `MB_REG_MODE` 5; it must count
`MB_REG_NREAIM`.  The first version of this harness made exactly that mistake and reported
"re-aim not seen" five times while the counter was incrementing.

**`MB_REG_GAIN` (493), added during the acceptance.**  The number the margin is compared
against was not published anywhere (394/395 are overwritten by the adoption), so the
natural re-aims' gains were unknowable; 493 publishes the adopted answer's gain over the
held one.  It is 0 on a hold, and 0 on an adoption whose predecessor could not be scored at
all — which is every injected re-aim (a 5-source-px displacement maps the part off the
baseline mask), so the injection test reads 0 by construction.

**One natural wrong adoption measured WITH its gain — the decisive observation.**  After
the acceptance runs, a fresh reference (`MB_CMD = 9`) was taken and the words were read by
polling; the first comparison after it did this:

```
mode 5, state 2, MB_DIFF_OK 5, verdict 2, move 200, MB_REG_GAIN 32, MB_REG_NREAIM 13 -> 14,
transform adopted: angle -0.40 deg, dx +0.4 source px, scale 1.0000
```

The reference had just been copied from a live frame, so the correct transform at that
moment is the identity **by construction**: this is a wrong adoption, with a measured gain
of **32**.  The next comparison then held that transform and read `MB_DIFF_CELLS` = 0 with
**114** cells over the threshold and verdict 0 = PASS — the drift and the false PASS in one
observation, on the final build, caught by mode 5 on the frame where it happened.  The gain
is twice `REG_WARM_MARGIN` (16) and at the top of the measured cost of a real 0.5-degree
rotation (4..31): a margin large enough to reject this move would reject real half-degree
rotations too.  Taking the reference again on the following four attempts did **not**
reproduce the move (all four held the identity with 0 cells), so the drift is intermittent,
not a property of taking a reference.

## 4. Acceptance, item by item, with the raw distributions

**(a) 100+ independent comparisons at N = 8, still scene — 263 comparisons taken, but the
"cells under the limit in every one" criterion is NOT met, and the reason is the drift.**
Eight runs, fresh reference before each, one ATOMIC row per comparison (`MB_DIFF_N`
changes; each row is a single 1.3 KB mailbox burst, after the first harness was found to
mix two comparisons' words — see section 5 for that instrument lesson):

| run | comparisons | cells 0 | cells 1..7 | cells >= 8 | re-aims | UNSTABLE |
|---|---|---|---|---|---|---|
| NEW1 | 30 | 30 | 0 | 0 | 0 | 0 |
| NEW2 | 31 | 31 | 0 | 0 | 0 | 0 |
| NEW3 | 30 | 15 | 0 | 15 | 1 | 0 |
| NEW4 | 30 | 23 | 7 | 0 | 0 (1 in-bound adoption, mode 1) | 0 |
| NEW5 | 31 | 11 | 2 | 18 | 1 | 0 |
| NEW6 | 37 | 37 | 0 | 0 | 0 | 0 |
| NEW7 | 37 | 37 | 0 | 0 | 0 | 0 |
| NEW8 | 37 | 12 | 3 | 19 | 2 | 0 |
| **total** | **263** | **196** | **12** | **52** | **4** | **0** |

The 52 over-limit readings are contiguous stretches immediately AFTER a re-aim: NEW3
n=371..385 (34..39 cells), NEW5 n=432..449 (12..17), NEW8 n=569..592 (8..186).  They are the
drift itself, not the comparison's noise: the registration adopted a wrong transform and the
comparison then reports NG on a good part for the rest of the run.  Three rows carry
`MB_DIFF_CELLS` = 0xFFFFFFFF because their comparison was refused (the two re-aim rows and
one UNSTABLE frame).  **Of the 263 comparisons, 208 are under the limit, 52 are over it, and
3 were refused; the other 52 are the defect this stage makes visible, and they are reported
as a failure rather than filtered out.**  Raw
sequences: `dl/st6_runs_new_20261024.txt` and `dl/st6_runs_new2_20261024.log`, one line per
comparison, `dl/st6_accept_analysis.py` aggregates them.

**The new state caught all four, and the persistence rule still leaves a window.**
`MB_REG_NREAIM` went 22 → 26 over the eight runs; all four re-aim frames were refused
(state 2, `MB_DIFF_OK` 5).  But the comparison's own rule needs **three consecutive**
comparisons before it reports NG, so after a wrong re-aim the first one or two comparisons
still read PASS while `MB_DIFF_CELLS` is already 8+.  Measured: **3 comparisons with
`MB_DIFF_CELLS` >= 8 and verdict 0** — all in NEW8, immediately after its first wrong
re-aim.  That window is the comparison's persistence rule, which this task was told not to
touch; closing it is one piece of registration state (refuse comparisons until the new
transform has been held `PERSIST_N` times) and is recommended as the next step, with the
measurement above as the reason.

**(b) how many comparisons the registration re-aimed on: 4 of 263** (`MB_REG_NREAIM`
22 → 26); **how many were UNSTABLE: 0** in the acceptance (1 per injected re-aim in the
known-answer test, which is state 3 doing its job).

**(c) a real drift produces something a host can distinguish from a clean pass — quote the
words.**  Natural events: `MB_REG_NREAIM` (492) 22 → 26, and on those frames
`MB_REG_MODE` (393) = 5, `MB_REG_STATE` (232) = 2, `MB_DIFF_OK` (180) = 5, i.e.
CANNOT JUDGE, where the old build would have compared the frame and read 0 cells = PASS
(the same transform change read 0 cells with 61 and 32 cells over the threshold in two of
the runs, before the blob rule removed them).  Known-answer test: the same words read
5 / 2 / 5 with `MB_REG_MOVE` = 881..1225 (9..12 times the bound) and `MB_REG_NREAIM` +1.
A clean pass is `MB_REG_MODE` 2, `MB_REG_MOVE` 0, `MB_REG_NREAIM` unchanged, `MB_DIFF_OK` 1,
verdict 0 — the two are distinguishable by three words each, with no inference from the
cell count.

**(d) failure direction.**  No frame whose registration was refused published PASS: the
refusal path sets `MB_DIFF_OK` 5 and returns before the comparison, and 5 is what
`diff_verdict()` maps to CANNOT JUDGE.  All 44 NG verdicts and 14 CANNOT JUDGE verdicts are
in the runs with over-limit cells; the 3 PASS-with-8+-cells rows above are comparisons that
RAN under the persistence rule, not refused ones.

## 5. Two instrument lessons from this session (they cost real time)

1. **A row built from 25 separate `mrd` reads is not one comparison.**  The comparison runs
   once per 2.5 s and rewrites the mailbox in one burst; 25 single-word reads take 0.5..2 s,
   so a row can mix two frames' words.  It happened here: a row read `mode` 2 from
   comparison N+1 next to `nreaim` 1 from comparison N, and the first version of the re-aim
   test reported "RE-AIM NOT SEEN" five times while `MB_REG_NREAIM` was incrementing.  Every
   number in this document was taken with one 1.3 KB `mrd -bin -file` burst per row (~30 ms)
   and explicit little-endian decoding (`mrd`'s words come back byte-swapped for Tcl's
   native `I` scan — measured, not assumed).
2. **A refused comparison does not advance `MB_DIFF_N`.**  Words published on a refusal
   frame are visible for the rest of the loop and then replaced; a host that only reads on
   `MB_DIFF_N` changes will miss `MB_REG_MODE` 5 entirely.  Count `MB_REG_NREAIM`; sample
   `MB_REG_MODE` if the frame matters.

## 6. A measured unit defect in the published shift (found, NOT fixed here)

While deciding what `MB_REG_MOVE` should be expressed in, the shift's unit chain was found
to be inconsistent, and then measured.  `reg_score()` shifts in HALF-resolution pixels;
`reg_adopt()` stores `g_reg_dx_fp8 = (dx_i << 8)`, documented as 1/256 half-res px
(main.c:2320).  `ref_at()` then applies `- (g_reg_dx_fp8 << 5)` in Q12 SOURCE pixels
(main.c:4264) — **four times** the shift the search measured — and `MB_DIFF_DX` is
published as `dx_fp8 / 8`, documented as 1/16 source px (main.c:1908), which is also 4x too
big.  The two consumers agree with each other, so a still scene (dx = 0) cannot show it.

The measurement (`ps_ui/st6_shift_units.py`): a real part frame shifted by exactly 8 source
pixels, put through the ported comparison.  Applying the shift in the search's units gives
**0 cells, 0 blobs**; applying it the way `ref_at()` does gives **534 cells, 460 blobs**;
applying none gives 286 cells.  The published word would read 512 (= 32 px) where the
displacement is 128 (= 8 px).

**Not fixed in this stage, deliberately:** `ref_at()` is the comparison's sampler, which
this task was told not to touch, and the one-place fix (`dx_i << 6` / `ox << 2` in
`reg_adopt` and `reg_restore_hold`, making dx_fp8 the 1/128-source-px unit both consumers
already assume) would change how every non-zero shift is compared and needs its own
acceptance run.  It matters to this stage because it changes what "the drift was 3.5 px"
means: the physical shift is a quarter of the published one, and part of the 10..41-cell
readings after a drift may be the comparison over-shifting rather than the registration
being wrong.  Exact experiment: fix the two shifts, re-run the eight-run acceptance, compare
the post-re-aim cell counts with the 52/263 above.

**CORRECTION (2026-10-24, stage 7): the diagnosis in this section is wrong; the firmware
chain is correct and nothing in `ref_at()` / `reg_adopt()` / the publication was changed
for it.**  The measurement's synthetic truth used `dx_i = 2 * d` half-res px for a
displacement of `d` SOURCE pixels.  That is inverted: the grey image is 640x360 from a
1280x720 frame (`GREY_W = CAM_W/2`), so one source pixel is HALF a half-resolution pixel,
and `d` source px is `d/2` half-res px.  Feeding a 4x-too-large `dx_i` through the shipped
store is what produced the 534 cells, and `dx_i << 6` gave 8 px only because the two 4x
errors cancelled.  Re-run with the PORTED SEARCH as the authority: for the same 8-source-px
pair it returns `dx_i = 4`; the shipped store (`dx_i << 8` = 1024) makes `ref_at()` apply
exactly 8.00 source px and the ported comparison reads **0 cells, 0 blobs**; the proposed
`dx_i << 6` applies 2.00 px and reads 235 cells; no compensation reads 286; the old
harness's `2*d << 8` reads 534.  `MB_DIFF_DX = (dx_i << 8) / 8 = 128` = 8.00 source px in
the documented 1/16 unit.  The corrected known-answer test is `ps_ui/st6_shift_units.py`
(it derives the shift from the search and asserts all four cases); the full trace is in
`dl/STAGE7_20261024_shift_and_persist.md`.  The inference this section drew from the wrong
unit is therefore withdrawn: the 10..41-cell readings after a drift are not an
over-shift artefact, they are the registration error itself.

## 7. What remains unverified, and every human-dependent experiment

1. **A part that actually moves / rotates** (requires a person).  Experiment: take a
   reference (`MB_CMD = 9`), read `MB_REG_MODE`/`MB_REG_MOVE`/`MB_REG_GAIN` (393/491/493)
   and `MB_DIFF_CELLS` for 10 comparisons, slide the part 1-2 cm (or rotate 0.16 / 0.5 /
   1.0 deg against a protractor), repeat.  Expected: for a SMALL real move the transform is
   adopted as mode 1 or 4 with `MB_REG_MOVE` below 100 and `MB_REG_GAIN` equal to the cost
   of the displacement; for a LARGE one, mode 5 (one refused comparison) and `MB_REG_GAIN`
   in the hundreds.  If a real move publishes mode 5 that is the designed behaviour, not a
   fault; if the answer does NOT follow the part, the margins are too large for this bench.
2. **The gain of a natural drift — measured once (32), and it is the datum that settles the
   margin question.**  Of the four natural re-aims found in the acceptance runs only the
   fifth, taken after them, had word 493; it read 32.  More samples would
   describe the distribution, but one sample of 32 is already above any margin that real
   half-degree rotations allow, so the conclusion does not wait for them.  Experiment if a
   distribution is wanted (no operator): run `st6_warm_20261024.tcl` five times and read
   word 493 on every mode-5 row.
3. **Why the drift happens.**  The evidence points at the light: in all four natural events
   the re-aimed transform read 8..186 cells afterwards, i.e. the part had not moved and the
   surface had, and the room's fluorescent lamps and the AEC were not controlled.
   Experiment: point the camera at a matte grey card under a lamp that can be switched, take
   a reference, and watch `MB_REG_NREAIM` with the lamp on and off.  If re-aims follow the
   switch, the drift is a lighting-induced false minimum and the next fix belongs in the
   search (a re-aim required to persist for two frames), not in the margin.
4. **The persistence window after a re-aim** (section 4): measured 3 PASS-with-8+-cells
   comparisons.  Fixed in stage 7: a changed transform is refused for `PERSIST_N`
   comparison slots and the hit counters are cleared (see
   `dl/STAGE7_20261024_shift_and_persist.md`); the 8-run acceptance was re-run.
5. ~~**The 4x shift unit** (section 6) — separate task.~~  **Refuted in stage 7** (see the
   correction at the end of section 6): the firmware chain is correct; the test's unit
   conversion was inverted.  No firmware change was made for it.
6. **The damaged boards** (unchanged; the only claim that needs a person): for each board
   take a reference, then read `MB_BLOB_CLASS` (462), the bbox, `MB_BLOB_TOUCH` (470),
   `MB_BLOB_HOLES` (471) and `MB_DIFF_CELLS` (181) and record the operator's description;
   confusion matrix from that, nothing else.

## 8. Cost, build, flash

* `.text` **+384 bytes** and `.bss` **+16 bytes** are this stage's own (measured by
  compiling `HEAD`'s `main.c` and this one with the same flags: 88,420 → 88,804 text,
  28,844 → 28,860 bss).  The image ends at 0x183F8 with a 0x70FC `.bss`, i.e.
  128,244 bytes of the 128 KB OCM, leaving **2,828 bytes** (it was 3,228): 400 bytes of OCM
  margin spent, inside the ~3 KB budget, nothing moved to DDR.
* `build.ps1`: 0 mailbox collisions (293 `MB_*` words, 293 distinct), all layout checks
  pass, only the four pre-existing warnings.
* Flashed with `ps_fft_dual/strict_load_cores.tcl` (firmware only; no bitstream, no power
  cycle, no running-VDMA poke).  Board reads FWID `TSC1` / `9B32060F`, `MB_READY` 1,
  `MB_AVG_N` 8, `MB_AVG_CNT` 8, and the new words 491/492/493 publish 0 / 0 / 0 on a hold.
  The board was left with a fresh reference and verified clean: mode 2, state 1, move 0,
  `MB_REG_NREAIM` 14, transform identity (0.00 deg / 0 px / 1.0000), `MB_DIFF_CELLS` 0,
  verdict 0, `MB_READY` 1, `MB_AVG_CNT` 8 — four further reference-and-watch repetitions
  after the measured drift all held the identity with 0 cells.
* Harnesses and scripts added: `ps_fft_dual/st6_warm_20261024.tcl` (one atomic row per
  comparison, re-aim rows polled), `ps_fft_dual/st6_dump_20261024.tcl` +
  `ps_ui/st6_warm_cal_avg.py` + `ps_ui/st6_cal_agg.py` (the averaged-lattice calibration),
  `ps_fft_dual/st6_inject_20261024.tcl` (the known-answer re-aim), `ps_ui/st6_shift_units.py`
  (the 4x measurement), `dl/st6_accept_analysis.py` (the acceptance aggregation).
