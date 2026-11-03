# The verdict's counting scope: the in-part fine count is the only authority

2026-10-24.  Firmware before the change `32FE5990` (the REG_WIDEN build);
after it `6F249163` (the build the three acceptances below ran on), then
`227A3F70` and `4674FA10` after comment-only edits.  The images differ only in
the eight hash characters (19 bytes from 6F249163 to 227A3F70, 14 bytes from
227A3F70 to 4674FA10; `.tmp/verdict/diffbin.py`), so the machine code is
identical across all three.  Each build: 13 files, `ps_ui/build.ps1` exit 0,
0 mailbox collisions, layout checks pass, only the four pre-existing warnings.
Flashed with `ps_fft_dual/strict_load_cores.tcl` only: no bitstream, no power
cycle, no VDMA register pokes.

The bench light dimmed at about 21:45, AFTER the acceptance runs: camera 0's
mean fell from ~130 to 83 per-mille, the part mask fell to 305..386 points
(below `PART_MIN_PTS` 400), and the registration therefore refuses every
comparison (`MB_REG_STATE` 2, `MB_DIFF_VERDICT` 2 CANNOT JUDGE).  The board is
left in that state: it is the fail-safe doing its job on a scene it cannot
judge, not a regression of this change (the same build passed the still-scene
run minutes earlier, before the light moved).

## 0. The failure report itself has a measurement error: "FCELLS = 2" is not the fine count

The instrument used for the moved-part run, `ps_fft_dual/move_check_1024.tcl`
(mtime 21:08:29), read **word 462** and labelled it `fine`.  Word 462 is
`MB_BLOB_CLASS` (the class of the largest blob, 0..6).  `MB_DIFF_FCELLS` is
**word 494**; word 496 is its evidence word `MB_DIFF_FVALID`; `MB_DIFF_CELLS`
(whole frame, coarse) is 181.  The same script read word 232 as `mode` (that is
`MB_REG_STATE`; `MB_REG_MODE` is 393) and word 385 as `angle` (that is
`MB_REG_ANGLE` in tenths; `MB_REG_ANGLE100` is 386).

Measured on the live board: in the first snapshot of the failing state (21:12),
word 462 read 2 while word 494 read 21 (and 49..164 on later comparisons in the
same state); in the reconstructed failing state (section 4) word 494 read
107..138 over eleven judged comparisons.  So "fine = 2" and "part matches its
reference well" were both derived from the wrong word.  The instrument is fixed
in place (462 -> 494, 232 -> 393, 385 -> 386, FVALID added); its header records
why.

## 1. Shape chosen: (a), and the measurement that decides it

**Shape (a): the verdict reads `MB_DIFF_FCELLS` against the limit and nothing
else.  `MB_DIFF_CELLS` stays published and is never read by a verdict path.**

The shipped code already returned the fine count whenever the fine pass had
evidence; the one remaining path in which the coarse count could vote was the
fallback taken when `MB_DIFF_FVALID == 0` or `MB_DIFF_FCELLS == 0xFFFFFFFF`.
`diff_verdict()` (`ps_ui/main.c:7616`) now returns **CANNOT JUDGE (2)** in that
case: "the fine pass judged no in-part cell" is no evidence, and a coarse number
is evidence about the whole frame (i.e. mostly the belt), not about the part.
Shape (b) was rejected because it still lets a background-sensitive number vote:
the part mask is built from the frame's own median (`PART_MARGIN 12`), so on
this bench it includes the static table clutter as well as the PCB, and the
coarse pass counts that clutter whenever the light moves.  Measured: with the
part still and a fresh reference, the coarse count reached 103 while the in-part
fine count was 3..7 and the verdict was PASS -- exactly the pair shape (a) is
for.  (The same still run had 24 judged rows with coarse raw `MB_DIFF_OVER` >= 8
and fine 0: pre-existing background drift, not a part change.)

`MB_DIFF_LIM_USED` (223) is still published from the same resolved limit in the
same function; no comparison arithmetic, mask definition, margin, persistence
window, averaging, exposure lock, classifier or display was changed.

## 2. A DDR collision that had to be fixed (and is a regression of `32FE5990`)

`BASE_MASK_D` (added by the registration change at `main.c:2842`) was placed at
0x126C8000, which is `FINE_FLAG` (stage 8, below it); both are 14,400 bytes, so
they were exactly overlapping.

Measured on `32FE5990`: the fine pass was writing its own flags into
0x126C8000 (209 nonzero bytes, values 0/1/2; that frame FOVER 147, FCELLS 49),
which is exactly the address `ref_take()` writes the dilated baseline to.  The
widened rule was therefore reading fine flags on every comparison after the
first, and nothing could see it while the shipped double rule had a foothold
(RULE = 0).

Fix: `BASE_MASK_D` moved to **0x126E0000** (free DDR above DHIT, below
BG_BASE 0x12700000).  Verified on the new build: after a fresh reference and
comparisons, 0x126E0000 holds **2,145 points = the exact 3x3 dilation of the
1,013-point `BASE_MASK`**, and `FINE_FLAG` at 0x126C8000 is 0/1/2 only.  OCM is
unchanged (the buffer was already in DDR).  This is a move of an existing DDR
buffer by name, not a new allocation.

With the fix, the widened path is reachable and was observed working: in
acceptance 1 the cold search **adopted under RULE = 2** with
`MB_PART_USED = 888` (the highest used of the run, vs 466..523 under the shipped
rule) before the exact-rule refinement held the answer.  The earlier report
could not re-demonstrate RULE = 2 on the failing frame; this is that path on the
board.  (Causality is inferred: the old block was measured corrupt, but the old
build was not re-flashed to A/B this particular adoption.)

## 3. Acceptance 1 -- a moved good part passes with the coarse number large

Operator unavailable, so the allowed reference-injection hook was used
(`MB_CMD = 17`; `.tmp/regwiden/make_ref.py` + `inject_ref.tcl`).  A fresh
reference was taken at the current placement (`n = 142`), then the reference
image was displaced by S = (120, 40) source px and rotated +2.00 deg about the
frame centre, written into REF_BASE, and re-derived by the firmware.

Known truth: dx16 = -1920, dy16 = -640, angle100 = +200, scale = 256.

    BEFORE (identity hold, n=142): cells 0, fine 0, FVALID 977, verdict 0 PASS
    MB_CMD = 17:
      n=142 state 0  ->  MODE 5 re-aim, dx16 -2036 dy16 -512 ang -52
      n=143 (intermediate transform, judged): cells 450, fine 30, verdict 1 NG
      n=143 RULE 2  ->  WIDENED ADOPTION dx16 -1952 dy16 -636 ang 145
                        scale 255, PART_USED 888, SAD 132
      n=143 settle slots: OK 5, fine 0xFFFFFFFF, verdict 2 CANNOT JUDGE
      RESUMED:
      n=144  cells  52  fine 1  FVALID 1012  verdict 0 PASS
      n=145  cells  50  fine 1  FVALID  919  verdict 0 PASS
      n=146  cells  51  fine 1  FVALID  931  verdict 0 PASS
      n=147  cells  51  fine 1  FVALID  974  verdict 0 PASS
      n=148  cells  51  fine 1  FVALID 1023  verdict 0 PASS
      n=149  cells  50  fine 1  FVALID 1081  verdict 0 PASS
      n=150  cells  50  fine 1  FVALID  845  verdict 0 PASS
      n=151  cells  50  fine 1  FVALID  906  verdict 0 PASS
      n=152  cells  50  fine 1  FVALID 1083  verdict 0 PASS
    summary: rows 31, judged 16, refused 15, PASS with coarse OVER >= 8: 15

The adopted transform is within 2 source px, 0.55 deg and 1/256 scale of the
injected truth.  The whole-frame coarse count is 50..52 (limit 8) and the verdict
is PASS: the coarse number is published and does not vote.  This is shape (a)
working.  (The pre-change build would also have returned PASS here because the
fine evidence was valid; the removed fallback is what this change adds, and it is
guarded rather than exercised by this test.)

## 4. The real physical move: the NG is the fine count, not the coarse fallback

The pre-move reference dumped during the failing run (`dl/now_ref.raw`) was
written back into REF_BASE and re-derived (`MB_CMD = 17`); the PCB is still at
the moved placement, so this reconstructs the failing configuration.  On the new
build, 26 samples over 39 s:

    rows with CELLS 768..883, FCELLS 107..138, FOVER 222..279,
              FVALID 855..1094 (never 0), VERDICT 1 (NG), LOCAL 1
    one row in the middle re-adopted under RULE 2 (PART_USED 886, dx16 354,
              dy16 -288, ang 140, scale 252); still FCELLS 113 and NG after it

So in the failing state the fine count is **valid and above the limit**.  The
verdict is NG because `MB_DIFF_FCELLS >= 8`, not because the coarse count voted.
The removed fallback requires `FVALID = 0`, and no judged comparison in the
failing state had that.  The "third counting-scope failure" is, on this
evidence, a **fine-count failure**: the adopted transform does not align the PCB
well enough, and the fine pass sees the residual.

Independent check, from the dumped images (not the firmware's arithmetic): an
image-domain fit on the PCB region gives dx = 18.6 half-res px, angle 4.68 deg,
scale 0.974; the firmware published 14.1 half-res px, 3.48 deg, 0.961.  Mean
absolute green difference over the PCB: 13.09 grey at the independent fit,
30.84 at the published transform (identity: 31.94).  Replaying the fine cell
arithmetic over the dumped masks gives raw over-threshold counts of 140 at the
published transform, 105 at the PCB fit, 207 at identity -- the measured
`FOVER` was 147, which validates the replay.  Even the best affine leaves ~105
raw cells (mean |d| 7.9), so the residual is not purely geometric: the reference
and live frames differ in lighting/shadow as well.

**Consequence.**  Making this physically moved part pass would need either a
registration/mask change (the part mask includes the static table clutter, so
the global fit is pulled by it) or a threshold/margin change.  Both are outside
this task's "do not change" list, and the second would hide small defects.  That
trade is not mine to make; it is reported, not applied.  The reference-injection
acceptance above is the in-scope demonstration that the verdict no longer
counts the moved background.

## 5. Acceptance 2 -- a known defect inside the part still fails

`ps_fft_dual/st8_stamp_20261024.tcl 65 71 40 60 30 stamp40 noref` (fresh normal
reference, then the stage-A `MB_CMD = 15` stamp: a 40x40 px square, +60 grey,
top-left 8x8 cell (65,71), inside the PCB and inside the live part mask; passed
through the shipped comparison, not a host imitation).

    before: fine 0, FOVER 0, verdict 0 PASS
    n=174,175 (persistence window): FOVER 25, FCELLS 0, verdict 0 PASS
    n=176:  cells 9, FCELLS 25, FVALID 1014, FMAXD 67, FAT 18243
            (= gy 71, gx 67), box (65,71)..(69,75), VERDICT 1 NG
    ... the same on every judged comparison to n=186:
    n=186:  cells 9, FCELLS 25, FVALID  955, VERDICT 1 NG

A 5x5-cell stamp reports exactly 25 fine cells; the fine count is 25 against
limit 8 and the verdict is NG.  The fix did not make defects invisible.  The two
PASS slots before persistence reached 3 are the shipped persistence window
(unchanged on purpose; the same two slots exist in every historical run).

## 6. Acceptance 3 -- still scene, 100 comparisons

Run A, build `6F249163`, fresh reference, `.tmp/regwiden/still_accept.tcl stillN
240` (log `.tmp/regwiden/stillN.log`):

    100 unique comparisons (MB_DIFF_N 1..109), 99 judged + 1 settle slot
    fine FCELLS: 0 in all 99 judged rows (max 0)
    fine FOVER:  0 or 1 (max 1)
    verdicts:    PASS (0) in all 99 judged rows
    PASS with fine FCELLS >= limit: 0
    PASS with fine FOVER  >= limit: 0
    the one refused/settle slot: OK 5, verdict 2 CANNOT JUDGE (never PASS)
    coarse cells 0 in 75 rows, 8 in 9 rows, 9 in 15 rows (first at N=86);
    coarse raw OVER up to 36; 24 judged PASS rows have coarse raw >= 8

Run B, final build `227A3F70`, fresh reference, two back-to-back sessions on the
same reference (`.tmp/verdict/still_finalb.log`, `still_finalc.log`):

    140 unique comparisons (N 47..195), 139 judged + 1 settle slot
    fine FCELLS: 0 in all 139 judged rows
    fine FOVER:  3 rows with 8..11 (N=81,82,83), FCELLS 0 in those rows, PASS
    verdicts:    PASS in all 139 judged rows
    PASS with fine FCELLS >= limit: 0
    the one settle slot: OK 5, verdict 2 (never PASS)
    coarse cells: 0..8 (47 rows at 8); coarse raw OVER up to 34;
    103 judged PASS rows have coarse raw >= 8

The coarse rows in both runs are the pre-existing background drift measured in
`dl/REG_WIDEN_20261024.md` section 5 (that report saw the same: coarse 33, fine
0, PASS).  They are not a regression of this change -- the previous build also
had the fine count as the authority whenever `FVALID > 0` -- and they are the
designed consequence of shape (a): the coarse number is published, the fine
number votes.  If the acceptance's "raw count" is meant to be the *coarse* raw
count, then shape (a) cannot satisfy it by construction; the task text's
acceptance 1 ("PASS even though the whole-frame coarse number is large") says
the coarse one must not fail a part.

The three FOVER 8..11 rows in run B are the **persistence window** doing its job:
the raw fine count was over the limit for a moment but never stayed at the same
cells for `PERSIST_N = 3` comparisons, so the published fine count (the one that
votes) stayed 0.  The persistence window is on the "do not change" list.  So
"PASS with raw count >= limit" is zero only for the *published* fine count; for
the raw fine count it is 3/139 in run B and 0/99 in run A.  This is stated, not
hidden: the criterion as worded cannot be zero for both the fine raw and the
coarse raw counts at once without changing one of the forbidden things.

## 7. What remains unverified / human-dependent

1. **The physical 1-3 cm move was not repeated by an operator.**  The failing
   configuration was reconstructed from the dumped pre-move reference, and it
   reproduces the NG (fine 107..138).  To re-run it at the bench: take a
   reference (`MB_CMD = 9`), move the PCB 1-3 cm and ~2 deg, then read words
   181/494/495/496/222.  Expected on this firmware: fine > 8, verdict NG.  The
   board will NOT pass that physical test; section 4 says why.
2. The exact words of the original failing snapshot were not archived; the
   reconstruction is the evidence.  `move_check_1024.tcl` is fixed so a repeat
   reads the fine count.
3. The removed coarse fallback (`FVALID == 0`) is not exercised by these three
   tests, because every judged row had fine evidence.  A human can exercise it
   by covering camera 0 while a reference exists; the required result is
   `MB_DIFF_OK` unchanged, `MB_DIFF_FVALID 0`, `MB_DIFF_VERDICT 2` (previously
   the coarse count could have made it 0 or 1).
4. The defect test is a synthetic reference stamp (the brief allows it); it is
   not a physically damaged board.
5. The fine pass's sensitivity to background lighting (its mask includes the
   table clutter) is measured but not attributed further; changing it would
   change the mask definition, which this task forbids.
6. The exact-rule vs widened-rule adoption on the reconstructed physical state
   differed between runs (RULE 0 at 354/-288/140 vs the original 450/-130/348);
   the registration's choice is not deterministic across those cold starts and
   was not chased further here.
7. A separate, pre-existing hazard seen while sampling: immediately after
   `rst -cores` and before the firmware's first comparison, the mailbox still
   holds the PREVIOUS boot's `MB_DIFF_VERDICT = 0` / `MB_DIFF_N = 282` /
   `STATE = 0`.  A host that snapshots in that window can read a stale PASS with
   `MB_READY` not yet re-published.  This change does not address it (the
   published verdict is gated on `MB_READY` only inside `diff_verdict`, and the
   stale word is not rewritten until the first loop).  It is noted here because
   it is the same family as the "PASS on the first resumed comparison" failure;
   the fix would be to clear the verdict words before the loop starts, which is
   outside this task's file:line scope.
8. The final build `4674FA10` could not be put through the still acceptance a
   second time: the bench light dimmed at ~21:45 (camera mean 130 -> 83
   per-mille, part mask 305..386 points < `PART_MIN_PTS` 400), so the board now
   refuses every comparison (`MB_REG_STATE` 2, verdict 2 CANNOT JUDGE).  The
   final image is byte-identical in code to the accepted `6F249163`/`227A3F70`
   (hash bytes only, checked), and the same build had just passed the still run;
   the refusal is the fail-safe on a scene it cannot judge.  When the light is
   back: `MB_CMD = 9`, wait for READY, then `still_accept` again; the expected
   result is fine 0, PASS, no PASS with the published fine count above the
   limit.
9. `ps_fft_dual/move_check_1024.tcl` was fixed to read the real words; the
   exact output of the ORIGINAL failing run cannot be regenerated (the original
   snapshot was not archived).  Re-running it now reads 494/496 correctly.
