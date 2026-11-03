# Dual-camera cross-check: pre-registered measurement protocol (2026-10-26)

> STATUS at the end of the 2026-10-26 window: **V1 and V2 are MEASURED** (camera 1
> sees the part fully; the cam0->cam1 plane homography has a 1.12 px RMS and a
> dense edge peak exactly at its prediction).  **V3 and V4 are NOT measured** --
> that window had no contaminated board and no shadow.  Numbers:
> `dl/XCHECK_20261026.md`.  Nothing was implemented, because the brief's gate is
> "only if all four pass".  This file is kept as it was pre-registered; its kill
> criteria were written before the data and are not retro-fitted.

Author: delegated agent, task "decide by measurement whether cam1 can reject
single-view false positives, then implement".  Firmware: `ps_ui/main.c`.
Host tools: `dl/host_qc/xcheck_capture.py`, `dl/host_qc/xcheck_analyze.py`.
Board Tcl: `ps_fft_dual/xcheck_dump_20261026.tcl` (READ ONLY: connect + mrd).

## 0. What is measured, and what would kill the idea

Hypothesis: a real defect changes the surface in a way both cameras see from
their different angles; a shadow or specular highlight is a lighting artefact
that shows in one view only.  So require camera 1 to differ in the mapped region
before a camera-0 NG is published.

The hypothesis dies if any of these is measured:
- D1: camera 1 does not show the part at all (or shows a different place).
- D2: the cam0 -> cam1 correspondence residual is comparable to the part itself.
- D3: camera 1 has no usable differential (already established offline: its only
  published per-frame numbers are exposure statistics, `ps_ui/main.c:10169`;
  the *physics* test below stands in for it, using the same statistic computed
  offline on two camera-1 frames).
- D4: a shadow that makes camera 0 fail appears in camera 1's difference too.
  **This is the gate for the whole feature.**  A shadow is a change of the light
  reaching the surface; both sensors look at the same surface, so a distant
  lamp's shadow is expected to be in both views.  Specular highlights are the
  view-dependent artefact; shadows are not, unless the occluder is one camera's
  own light path.

## 1. Predictions, written before any board data

| # | prediction | would falsify |
|---|---|---|
| P1 | camera 1 shows the belt and the part, fully or mostly inside the frame.  A PRIOR from the two 2026-10-24 panel screenshots (ps_ui/dlfb_pv_full1_view.png = cam0, ps_ui/dlfb_pv_cam1_view.png = cam1): the green board blob moves from (234,203)-(508,336) to (345,202)-(587,333) in the 640x360 panel camera area, i.e. the board's centre moves about (+190,-4) source px and its apparent width changes 242/274 = 0.88 while its height changes 0.985.  That is a real change of viewpoint, so a substantial disparity is expected.  (The panel render cannot give the baseline: two feature-based estimates of the same pair disagreed with each other and with the blob, so none of them is quoted.)  The dump replaces the prior. | D1 |
| P2 | the cam0->cam1 plane homography residual at the part is < 5 px (part is ~500 px wide) | D2 if > 50 px |
| P3 | the contaminated board's defect is visible in camera 1's own difference in the mapped region (>= 8 cells at 30 grey, the camera-0 rule) | D3 (the defect is a camera-0-only story) |
| P4 | a shadow strong enough to make camera 0 fail (DAREA >= 8) is ALSO visible in camera 1 (>= 8 cells) | D4 -- if falsified, the idea lives |

P4 is the one this document expects to fail.  If it does, the recommendation is
"do not build": a shadow is not single-view, and a cross-check that only rejects
specular highlights does not address the false positives the station has.

## 2. The statistic used for both views

Camera 0's verdict uses `MB_DIFF_DAREA`: the largest 8-connected group of 8x8
cells whose |live*gain/256 - ref - bias| > 30 grey, over the part mask
(`ps_ui/main.c:8085-8103`, `main.c:10143`).  Camera 1 publishes no such number,
so the tool computes the identical rule offline on camera 1's own live/reference
pair: same 8x8 cell means, same frame-wide gain, same 30 grey, same connected
group.  Both numbers are therefore the same measurement on two pictures.

STATED DIFFERENCE: the firmware compares the mean of `MB_AVG_N` frames (8 in
the acceptance), while a dump holds ONE frame.  The offline counts are therefore
noisier than the firmware's, never quieter -- they are an upper bound on the
number of cells over the threshold.  That direction is safe for the kill
criterion (a large C1 cannot be explained away as single-frame noise), and it is
why the noise-floor row exists: it measures that single-frame floor directly.

## 3. Capture sequence (one contiguous board block, ~30 min)

Each "capture" is one read-only xsdb run (~10-20 s): the mailbox before and
after, camera 0's completed store, camera 1's completed store, the live mask.

| # | tag | scene | why |
|---|---|---|---|
| 0 | `empty` | belt empty | camera 1's empty-belt reference; also the background for the firmware (`MB_CMD=12`) if the state was lost |
| 1 | `goodA` | good reference board, centre | camera-1 reference; the PASS row |
| 2 | `goodA2` | the same state, no one touching anything | the NOISE FLOOR of the two-view statistic: two captures of one state must read near zero, or every later number is a difference between two noise draws |
| 3 | `goodB` | same board, slid ~15-20 mm along the belt | correspondence stability (V2) |
| 4 | `goodC` | same board, slid the other way | V2, second point |
| 5 | `contam` | contaminated board, same spot as goodA | V3: is the defect in camera 1 |
| 6 | `shad0` | good board again, no shadow | V4 baseline |
| 7 | `shadL` | shadow from the left, nothing touching belt or board | V4 |
| 8 | `shadR` | shadow from the right | V4 |
| 9 | `goodZ` | good board, no shadow | control that the scene came back, and a second noise-floor row |

Physical rules for the block:
- The shadow caster (A4 card / hand) must be held ABOVE the bench and must not
  touch the belt or the board.  It must not be visible in either camera's frame;
  the captured images are checked for this and the row is rejected if it is.
- The shadow must be strong enough that camera 0's `MB_DIFF_DAREA` reaches 8
  (the limit).  The capture prints DAREA before and after; if it is < 8 the
  shadow is repeated stronger, otherwise the row does not test the feature.
- The contaminated board must be placed where goodA was, to within a few px:
  the mailbox publishes camera 0's registration shift (`MB_DIFF_DX/DY`), which
  is the placement error, and it is quoted with every row.

Starting condition (the project's rule after a flash): belt empty ->
`MB_CMD=12`, then the good board -> `MB_CMD=9`, then verify `MB_PART_REF >= 400`
and `MB_DIFF_OK = 1`.  If the mailbox shows the background/reference already
valid and the firmware id unchanged, the retake is skipped and that is recorded.

Noise floor first.  Before any of the three physics questions, `goodA` vs
`goodA2` must read close to zero cells in BOTH views.  If two captures of the
same untouched scene already differ by more than the threshold, the cam1
difference is not a measurement of the defect or the shadow and the row is
reported as unmeasurable rather than interpreted.  This is the bench form of
"write down the noise floor before the effect".

## 3b. Numeric kill / pass criteria, fixed before the data

Every row uses the same mapped region and the same rule: 8x8 cells, frame-wide
gain, |d| > 30 grey, count of cells (the camera-0 DAREA rule).  Let C0 be
camera 0's cell count in the shadow's own DAREA box (from the capture) and C1
camera 1's cell count in that box mapped through H.

SHADOW (V4, the gate):
- VALID ROW: the firmware itself flagged the shadow, i.e. `MB_DIFF_OK = 1` and
  `MB_DIFF_DAREA >= 8`, and C0 >= 8 in our own recomputation.
- **P4 FAILS (shadow is not single-view) if C1/C0 >= 0.5**, in BOTH shadow
  directions, with both rows valid.
- **P4 HOLDS (shadow is single-view) only if C1/C0 <= 0.1**, in BOTH
  directions, with both rows valid.
- 0.1 < C1/C0 < 0.5 is INCONCLUSIVE and is reported as inconclusive, not as a
  pass for the idea.
- GUARD: if the noise-floor row (goodA vs goodA2, same untouched scene) yields
  C1 >= 8, camera 1's statistic is not trustworthy and every shadow row is
  reported as unmeasurable.

CONTAMINATED BOARD (V3): "the defect is in camera 1" if C1 >= 8 in the mapped
DAREA box (the same rule that calls camera 0's own defect), reported together
with C1/C0.  If C1 < 8 the defect is camera-0-only, which kills the idea for
that defect class as well.

CORRESPONDENCE (V2): the fixed-homography prediction of the part's camera-1 box
must be within 8 source px (one camera-1 cell) at every part corner, on at
least two placements.  A residual >= 32 px (4 cells) is FAILED.

## 4. Runbook for the block (one operator visit, ~10 min of physical action)

Step 0. `xsdb ps_fft_dual/xcheck_state_20261026.tcl` (read-only, 1 s).  Read
`MB_BG_STATE`, `MB_BG_AGE`, `MB_PART_REF`, `MB_DIFF_OK`, `MB_READY`, the AEC
state, `MB_CAM1_*`.  If the firmware was flashed or the background/reference is
absent, do the project's post-flash sequence first: empty belt -> `MB_CMD=12`,
good board -> `MB_CMD=9`, then `MB_PART_REF >= 400` and `MB_DIFF_OK = 1`.

Then, per state, one capture (each is one read-only xsdb run, 10-20 s):

```
.venv-calib\Scripts\python.exe dl\host_qc\xcheck_capture.py --tag empty  --wait-for ready
.venv-calib\Scripts\python.exe dl\host_qc\xcheck_capture.py --tag goodA
.venv-calib\Scripts\python.exe dl\host_qc\xcheck_capture.py --tag goodA2
.venv-calib\Scripts\python.exe dl\host_qc\xcheck_capture.py --tag goodB
.venv-calib\Scripts\python.exe dl\host_qc\xcheck_capture.py --tag goodC
.venv-calib\Scripts\python.exe dl\host_qc\xcheck_capture.py --tag contam
.venv-calib\Scripts\python.exe dl\host_qc\xcheck_capture.py --tag shad0
.venv-calib\Scripts\python.exe dl\host_qc\xcheck_capture.py --tag shadL
.venv-calib\Scripts\python.exe dl\host_qc\xcheck_capture.py --tag shadR
.venv-calib\Scripts\python.exe dl\host_qc\xcheck_capture.py --tag goodZ
```

After each capture, the tag's `capture.json` says `ok`, the mailbox stability
(`MB_DIFF_N` before vs after), DAREA and the AEC states.  A `TSXERROR` in the
log is a failed row, not a small one.

Then the analysis (the numbers that decide the four verifications):

```
.venv-calib\Scripts\python.exe dl\host_qc\xcheck_analyze.py --png dl\xcheck_20261026\png map  dl\xcheck_20261026\goodA --empty dl\xcheck_20261026\empty
.venv-calib\Scripts\python.exe dl\host_qc\xcheck_analyze.py          move dl\xcheck_20261026\goodA dl\xcheck_20261026\goodB --empty dl\xcheck_20261026\empty
.venv-calib\Scripts\python.exe dl\host_qc\xcheck_analyze.py --png dl\xcheck_20261026\png diff dl\xcheck_20261026\goodA2 --ref dl\xcheck_20261026\goodA --region darea
.venv-calib\Scripts\python.exe dl\host_qc\xcheck_analyze.py --png dl\xcheck_20261026\png diff dl\xcheck_20261026\contam --ref dl\xcheck_20261026\goodA --region darea --compensate
.venv-calib\Scripts\python.exe dl\host_qc\xcheck_analyze.py --png dl\xcheck_20261026\png diff dl\xcheck_20261026\shadL  --ref dl\xcheck_20261026\shad0  --region darea
.venv-calib\Scripts\python.exe dl\host_qc\xcheck_analyze.py --png dl\xcheck_20261026\png diff dl\xcheck_20261026\shadR  --ref dl\xcheck_20261026\shad0  --region darea
```

The shadow rows are the gate.  `--compensate` is used on `contam` because that
is a different physical board and its placement error is real; the shadow rows
keep the same board, so no compensation is applied to them (the registration
shift is printed either way so the reader can see the placement error).

One command reproduces the whole table from the capture directories, so no
number in the report is transcribed by hand:

```
.venv-calib\Scripts\python.exe dl\host_qc\xcheck_summary.py dl\xcheck_20261026
```

It prints V1 (camera 1's mask, the feature H, and an INDEPENDENT dense template
check of where the board patch lands), V2 (the fixed H applied to the other
placements), V3/V4 (one fixed region, all states), and the mailbox verdicts per
capture.  The template check exists because the first panel estimate in this
session fitted the floor plane and looked perfectly consistent; every real pair
now has to pass two independent mappings.

## 5. Offline work already done (no board)

- `xcheck_dump_20261026.tcl` parses as a complete Tcl script, is pure ASCII, and
  runs end to end against a hardware-free stub (`.tmp/xcheck_stub.tcl`); the
  stub run produced `TSXDONE` and the expected files.
- `xcheck_capture.py` parses the stub output and enforces exact file sizes.
- `xcheck_analyze.py`'s homography estimator was given a known-answer test: a
  real board frame warped by a known H, brightness x1.18 + noise; recovered H
  reproduces the warp to 0.16 px max at the board corners (RMS 0.39 px).
- The two-view cell statistic was tested on a synthetic pair where a +55 grey
  patch was injected into both views: both views reported 15 cells, max |d|
  55.0 (cam0) / 65.4 (cam1).
- Camera 1's real capability was established from the source, not assumed: no
  reference frame, no per-cell difference, no DAREA (`ps_ui/main.c:9248-10024`,
  `10169`).

## 6. What is NOT yet measured

Everything on the board: P1-P4, the mapping residual on the real scene, the
cam1 reference stability across captures, and the AEC state of camera 1 during
each capture.  These need the block in section 3.

## 7. Correction record (kept so the mistake cannot be repeated silently)

First attempt at the panel prior: I matched the WHOLE 640x360 panel camera area
of the two screenshots with SIFT+RANSAC and got a near-translation of (+23,-4)
source px, scale 1.019, which I read as "the two cameras are near-duplicates and
there is no usable baseline".  That was wrong, for a specific reason worth
recording: the panel image contains the floor, the table leg and the board at
different depths, so a single homography cannot describe it, and RANSAC fitted
the FLOOR plane.  Applying the floor's homography to the board is the classic
plane error.  Re-running with the match restricted to the board gave a
self-inconsistent answer (scale 1.27 x / 1.14 y), and the independent green-blob
measurement above contradicts both; the blob and the board's changed aspect are
the only numbers consistent with the images.  The estimator itself had already
been known-answer tested (0.16 px on a synthetic warp), so the failure was in
how the scene was handed to it -- a multi-plane scene, no roi -- not in the
estimator.  Lesson applied: every real pair is matched with the board's own
bounding box as the ROI, never full-frame.

