# Retraining ts_cnn_top on the 41-board data — result, and why it loses (2026-10-28)

**Answer to the question asked: the retrained net does NOT beat the shipped rule.**
Leave-one-board-out over all 41 boards, detection on the 19 boards the rule judged is
**8/19 for the net vs 16/19 for the rule**; false-NG is **1/21 vs 0/21**. There is no
class where the net wins (bent is tied 2/2; corner 1/3 vs 3/3, scratch 0/7 vs 4/7,
contam 5/7 vs 7/7), and every paired difference goes one way: 8 boards the rule detects
and the net misses, 0 the other way (McNemar exact p = 0.0078).

This is not a training accident. Section 4 shows the measured reason: **the only
per-cell labels the shipped pipeline can give a learner are its own over-tolerance
cells, and the largest of those are part-edge registration residual, not defects.**
Training on them teaches the net the rule's blind spot. The three scratch boards the
rule misses are exactly where that label is empty or edge-dominated. A fair test of
"CNN beats the rule on scratch" needs an annotation of the scratch that is independent
of the comparison — a new labelling task, not a retraining step. I stopped before that
because the task's own kill criterion says so, and because the deliverable video /
packaging is the higher priority.

The on-board half is also **blocked by the station, not by the code**: the PS debug
port answers `APB AP transaction error, DAP status 0x30000021`, no Cortex-A9 target
appears, and every memory read fails (section 5). No board write was attempted; the
shipped KAT script refused correctly on its FWID gate.

Everything below is measured or reproduced, with file names.

---

## 1. Step 1 — the toolchain is exact (the gate is cleared)

The chain is complete and tracked in the repo:

```
dl/runs/cnn_v1.pt  +  dl/data/synth_v1.npz
   --[dl/quantize.py]-->      dl/runs/cnn_v1_int_params.npz, cnn_v1_int_meta.json, fpga_vectors.npz
   --[dl/export_for_hls.py]--> dl/hls/data/params.bin (148,792 B), vectors.bin (820,804 B)
   --[dl/gen_cnn_bins.py]-->   ps_ui/cnn_{wq,mtab,stab,btab}.bin
   --[dl/hls/tb/tb_cnn.cpp]--> 200/200 logits bit-exact vs the Python integer reference
```

I re-ran `quantize.py`, `export_for_hls.py` and `gen_cnn_bins.py` in place and compared
SHA256 against the artefacts that passed the board KAT on 2026-10-27:

| artefact | result |
|---|---|
| `dl/hls/data/params.bin` | IDENTICAL (`7C0CBA2C6952DC61FB396222B3D783D5394A80DD7041D92A84BA8ACF2FA2A013`) |
| `dl/hls/data/vectors.bin` | IDENTICAL (`F7C48682D27C6850E8B7415CD3B0DBEB1E649FA99CFC2FCFA68D914B5E4905F1`) |
| `cnn_v1_int_params.npz`, `cnn_v1_int_meta.json`, `fpga_vectors.npz` | IDENTICAL |
| `cnn_wq/mtab/stab/btab/img0/expected.txt` | IDENTICAL |

The C kernel was rebuilt with the MinGW g++ shipped inside Vitis HLS
(`D:\Vitis\Vitis_HLS\2023.1\tps\mingw\8.3.0\win64.o\nt\bin\g++.exe`) and run on the
regenerated `params.bin`: **200/200 rows bit-exact, worst |logit delta| = 0**, and the
first eight rows are exactly the firmware's `cnn_tv_exp` pairs (`-49511/51420`,
`-37599/40145`, ...). Logs: `dl/cnn_retrain/quantize_rerun.log`,
`dl/cnn_retrain/export_rerun.log`, `dl/cnn_retrain/tb/tb_cnn_rerun.log`.

So the scripts are authoritative over the binary artefacts; `ps_ui/cnn_weights.h` and
`dl/hls/data/params.bin` are both downstream of `dl/runs/cnn_v1.pt` and they agree.

**Board confirmation of the KAT could not be repeated** because the station is
unreachable (section 5). The shipped blobs are byte-identical to the ones that passed
8/8, which is a proof by identity, not a fresh silicon run.

One incident, repaired: running `ps_fft_dual/cnn_kat_20261027.tcl` opens its own log
with `w`, and that log is git-tracked. It overwrote the 21:35 PASS transcript; I
restored it with `git checkout -- ps_fft_dual/logs/cnn_kat_20261027.log` and verified
`KAT PASS 8/8` is back at line 27. Do not run that script again without saving a copy.

---

## 2. Dataset definition and counts

Source: `dl/sweep_frames/20261027_193725_sweep/<label>/` (41 boards: g0..g20 good,
d1..d20 defective; d8 has two sweep rows, one board) + the label ledger
`dl/host_qc/logs/sweep_20261027_193725_sweep.csv`.

* **Image**: `frame.bin` = 1280x720x3, green channel only, exactly the byte
  `cnn_infer()` copies (`main.c: row[..*3 + 1]`).
* **Grids**: `mask.bin`, `fine_deep.bin`, `fine_tol.bin` are 160x90 (one cell = 8x8
  source pixels). `fine_tol` is 30 everywhere on every board in this sweep, so the
  per-cell over-tolerance test is `fine_deep > 30` inside the mask.
* **Patch = one 64x64 native-resolution crop** (not a decimation of the whole frame:
  the part is 496x232 px, and a scratch is a 2-3 px line; in the firmware's current
  whole-frame 64x64 decimation the part is only ~24x30 px and the scratch is gone).
* **Positive patch**: on a defective board, centred on a cell the shipped comparison
  *measured* as over tolerance. Class comes from the human ledger; location comes from
  the per-cell measurement, never from the verdict (`DAREA >= limit`). 8-connected
  groups, largest first, up to 8 groups per board, 1-3 centres along groups > 8 cells.
* **Negative patch**: on a good board, from the same label-independent 32-px tiling.
* **Evaluation tiles**: every 32-px tiling position of the part mask (mean 36/board,
  1514 total), identical policy for every board, label-independent.

Counts (`python dl/cnn_retrain/dataset.py`):

| split | patches | boards |
|---|---|---|
| training positives | 209 | 20 defective |
| training negatives | 350 (every 2nd tile) | 21 good |
| evaluation tiles | 1514 | 41 |

**Leave-one-board-out** for all 41 folds; the held-out board contributes nothing to
training, to activation-range calibration, or to the aggregation threshold.

### 2.1 The aggregation rule (fixed before the run)

A tile votes NG when `logit1 > logit0`. A board is NG when
`count(voting tiles) >= k`, where

```
k = 1 + max over the GOOD boards of the training fold of (#voting tiles)
```

i.e. the smallest k that makes every visible good board pass. If no good board fires,
k = 1 (plain OR). k is per fold and never sees the held-out board.

### 2.2 What is wrong with the labels — the measured reason for the result

The positive location is "a cell the comparison measured over tolerance". That is a real
measurement, but it is not "the defect":

* the largest 8-connected groups on most boards sit on a systematic band on the part's
  bottom/outer edge (group bboxes in `python dl/cnn_retrain/group_bbox.py`; e.g. d6
  largest group `x48-53, y67-69`, part bbox `y47-74`), i.e. **registration residual at
  the part edge**, which the comparison itself cannot distinguish from a defect;
* rendering the actual positive patches (`dl/cnn_retrain/view/pos_patches.png`) shows
  part edges and vias, not the scratch;
* the part mask is the *green* region: it has holes over the metallic coil and
  connectors, and cells outside it are never judged (`lm[fi]==0 -> continue`,
  `main.c:9482`). Several scratch defects run across or next to those holes. The rule
  is structurally blind there, and a label taken from the rule is blind in the same
  place by construction.

Therefore a model trained on this label can at best imitate the rule's per-cell
evidence, including its blind spots. It cannot be expected to beat the rule on the
class where the rule fails — which is exactly what the measurements show.

---

## 3. Training and quantisation

* architecture unchanged: `dl/model.py` TrustScopeNet (3 conv blocks 16/32/32,
  fc 2048->64->2, 7.80 M MACs) — the network already in the bitstream;
* Adam 1e-3, cosine, 25 epochs, batch 32, class-balanced sampler, augmentation =
  +/-8 px shift, gain 0.92..1.08, offset -8..+8;
* quantisation exactly `dl/quantize.py`: uint8 affine activations, int8 symmetric
  per-output-channel weights, int32 accumulate, `(acc*M + (1<<(sh-1))) >> sh + z_out`,
  last layer not requantised; calibration on the training fold only;
* the deployable model (all 41 boards) is exported as
  `dl/cnn_retrain/out/params.bin` (148,792 B, same layout) + `cnn_*.bin`;
* **the exported model passes the C kernel check 200/200 bit-exact**
  (`dl/cnn_retrain/tb/tb_new_weights.log`), worst |delta| 0;
* int-vs-float argmax agreement on 200 tiles is **0.97**, not 1.00 — the new model's
  logits are closer to the boundary than the shipped model's were; this is a real
  quantisation cost and is reported, not hidden.

Training cost: 25 epochs on ~560 patches = 15 s on this CPU; one LOTO fold including
calibration and evaluation = 28-40 s; all 41 folds = about 25 minutes.

---

## 4. Leave-one-board-out result

Full table: `python dl/cnn_retrain/analyze.py` (`out/loto_results.json`,
`out/analysis.json`). Per-tile scores are stored there.

```
class      n     rule    net
bent       2      2       2
corner     3      3       1
scratch    7      4       0
contam     7      7       5
total     19     16       8
false NG  21      0       1   (g0, the reference board)
paired: rule-only detections 8, net-only 0, McNemar exact p = 0.0078
```

* d14 (defective contam, the rule **refused** — `diff_ok=5`, no DAREA): the net says NG
  (count 13). One board on which the rule made no answer at all.
* The single false NG is on g0, the reference board, which is the darkest good board
  (mean green 152.1 vs 156-168 for the others) and the one the net fires on most. At
  the station g0 is a known-good board and would be part of calibration, so in
  deployment this particular false NG would not occur — but that is in-sample
  calibration, not a LOTO estimate.
* In-sample check of the exported model (trained on all 41): with k calibrated on the
  same good boards, **detection 7/19, false NG 0/21** — the model does not even fire on
  all of its own training boards' evaluation tiles. Its positive patches are memorised
  at their exact positions; the shifted 32-px tiles are not recognised. That is the
  overfitting failure mode this project has been burned by, and the LOTO number is the
  only honest one.

---

## 5. Board measurement — blocked by the station

Attempted, read-only, 2026-10-28 10:38-10:43:

```
targets: 1 DAP (APB AP transaction error, DAP status 0x30000021)
         2 xc7z020
targets -set ... Cortex-A9*#0 -> no targets found
mrd 0xF8000000 (SLCR) -> ERR ; mrd 0x10F00000 (mailbox) -> ERR ; all reads ERR
```

Earlier in the same five-minute window the A9 still showed `Running`, but every memory
read already failed. Killing a stale `hw_server` and reconnecting did not change it, so
this is the board's PS debug state, not host software. The shipped KAT script was run
and **refused to write** because its FWID gate read 0xFF bytes instead of
`TSC17C54944F` — the gate did exactly what it exists for.

No write, no reset, no bitstream, no power cycle was performed. What this means:

* the on-board KAT could not be re-confirmed today;
* the on-board 41-board measurement could not be run at all;
* the verified station state (`MB_PART_REF=909`, `MB_DIFF_LIM=6`, `MB_EXP_LOCK=8698`)
  could not be read, so I cannot say whether it survived. If the board was powered off,
  it is gone and the ~40 min re-sweep is needed before any demo.

**What is ready for when the board is back** (committed, never executed — treat as
untested until it runs):

* `ps_fft_dual/cnn_eval_20261028.tcl` — FWID-gated; halts A9 (the IP completes with the
  CPU halted, measured 2026-10-27); loads the retrained weights over the shipped ones;
  points IMG/LOGITS at scratch DDR (`0x12300000`/`0x12340000`, the free gap between
  camera-0 store 4 and the reference, per `main.c`'s map) precisely to avoid the
  cacheable-debug-path trap; walks 1514 tiles with `ap_start` and `AP_CTRL`, reads two
  int32 per tile; restores the six ARG registers and the shipped weights at the end.
* `ps_fft_dual/cnn_restore_20261028.tcl` — the same restore as a separate command, for
  an interrupted batch.
* `dl/cnn_retrain/board_analysis.py` — pairs the on-board logits with the integer
  reference and **refuses to report a verdict table unless every logit is bit-exact**.

Substitute used for the number in this report: the integer reference in
`dl/int_reference.py`, which is the same code path that produced the 200/200 csim-equivalent
result and the KAT's expected words. That makes the 8/19 a statement about *the algorithm
and the weights*, not about silicon; the silicon step for the new weights is the one
piece that remains unexecuted.

---

## 6. What it costs per frame

| quantity | value | source |
|---|---|---|
| one 64x64 patch on the board | **29-31 ms** at the 50 MHz FCLK | measured, `dl/CNN_KAT_20261027.md` |
| 36-tile part scan (this report's evaluation) | **1.08 s per board** | 36 x 30 ms |
| 4-tile hybrid scan (e.g. at the rule's candidate cells) | **120 ms per board** | 4 x 30 ms |
| current firmware path (one whole-frame 64x64 every 16 loops) | 30 ms per ~2-3 s = 1-2 % of loop time | measured |
| same kernel on this CPU (integer reference) | 5.8 ms/patch | measured, `dl/cnn_retrain/cost.py` |
| DSP | 219/220, unchanged | the bitstream was not touched |

The bitstream, the MAC count and the input/output contract are unchanged, so the
per-inference cost of the retrained net is exactly the shipped net's. The cost that
changes is the *number* of inferences: a full part scan is ~1 s/board and is not
inline-viable at the 200 ms takt; a 4-patch hybrid is 120 ms.

---

## 7. What remains unverified

1. **The on-board KAT with the shipped weights** was not re-run (station down); it is
   proven by byte-identity of the blobs, not by silicon today.
2. **The retrained weights have never run on silicon.** The C kernel reproduces them
   bit-exactly (200/200), and that kernel is the one the board KAT matched bit-for-bit,
   but the new blobs themselves were not executed on the board.
3. **Scratch ground truth** is not independent: it is the comparison's over-tolerance
   cells. A visual annotation of the 7 scratch boards was not made, so the hypothesis
   "a texture CNN beats the cell-mean rule on scratch" is **not tested**, only the
   narrower "a CNN trained on the rule's own evidence does not".
4. **The station's verified configuration** could not be read; after any reload the
   reference must be re-established.
5. The net's aggregation threshold k is calibrated on 20-21 good boards; with more good
   boards it would be less brittle. The k values observed were 5-16 tiles, i.e. the net's
   per-tile false-positive rate is the binding constraint, not the defect signal.
6. Int-vs-float argmax agreement of the exported model is 0.97 (3 % of tiles sit on the
   other side after quantisation); no per-class effect of this was measured.

---

## 8. Recommendation

* **Do not present the retrained net as a win, and do not put it in the video as one.**
  The honest, defensible line for the report is: the retraining path is built and
  proven bit-exact end to end; on this project's own 41 boards, a CNN trained on the
  comparison's own evidence loses to the comparison (8/19 vs 16/19 detection, p = 0.0078);
  and the reason is measured (edge-dominated, rule-derived labels), not mysterious.
* If the scratch class is worth another attempt, the next step is **not** more training:
  it is a visual annotation of the 7 scratch boards (where the scratch is, in pixels),
  which then also gives the first independent check of the rule's 4/7. Estimate one
  day, uncertain payoff.
* Restore the station before any demo: power cycle/reload, then re-run
  `ps_fft_dual/cnn_kat_20261027.tcl` (10 s) to get the weights back, and re-sweep the
  reference (~40 min) if DDR was lost. The panel line "CNN NOT IN PATH" is still stale
  and still needs a rebuild to change; do not rebuild before the deadline.

## 9. Files

Code and results (all under `dl/cnn_retrain/` unless noted):

* `dataset.py` — board/patch definition and counts; `retrain.py` — LOTO driver;
  `final_export.py` — all-41 model -> `out/params.bin`, `out/vectors.bin`, blobs;
  `analyze.py` — the table above; `cost.py`; `make_board_chunks.py`;
  `board_analysis.py`; `group_bbox.py`, `inner_check.py`, `pos_check.py`,
  `make_crops.py` / `make_pair.py` / `make_scratch_sheet.py` / `make_other_sheet.py` /
  `make_corner_sheet.py` — the visual checks quoted above;
* `out/loto_results.json`, `out/analysis.json`, `out/meta.json`,
  `out/board_manifest.json`, `out/board_expected_logits.npy` (tracked);
  `out/params.bin`, `out/vectors.bin`, `out/board_batch.bin`, `out/board_chunks/`
  are gitignored (`*.bin`) and reproducible with `python final_export.py` +
  `python make_board_chunks.py`;
* `dl/cnn_retrain/backup/` — the shipped artefacts with their hashes;
* `ps_fft_dual/cnn_eval_20261028.tcl`, `ps_fft_dual/cnn_restore_20261028.tcl`
  (untested, board down).
