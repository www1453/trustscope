# Does a learned model COMPLEMENT the shipped rule? — a pre-registered offline test on 80 boards (2026-10-30)

**Answer: no. The pre-registered verdict is WORSE.** On the 75 boards both systems can
decide, the model catches the same number of defects as the rule (**19/35 each**), catches
**1 of the 3 contamination misses** (`d7`) and **2 of the 12 scratches** (`d31`, `d34`),
and pays for them with **2 false rejects among the 40 good boards** (`g20`, `g25`) against
the rule's 1 (`g14`). McNemar on the 35 defective boards: 3 discordant each way,
**p = 1.0000**. It is not complementary, it is not better, and it is one false reject worse.

The reason is measured, not mysterious: **the model's board score is a contamination
signal that the rule already has** (contamination AUC **0.968** [0.919, 1.000], 17/21
against the rule's 18/21), while for the scratch class it lands exactly where the four
earlier rounds predicted — **AUC 0.360** [0.194, 0.537], which covers 0.5, and the
scratches' median vote *fraction* (0.082) is **below** the good boards' (0.143). The three
contamination misses sit inside the good distribution's upper tail on vote fraction
(0.30 / 0.26 / 0.29 against good 0.00–0.47, median 0.14), so catching one of three is what
a threshold at the rule's false-reject budget gives.

Two controls make the null stronger rather than weaker, and they are the parts of this
report worth reading:

* **the same physical board, captured twice, scored 18 votes and 2 votes** under the same
  fold's model and the same threshold, and the decision flipped (`g20` NG, `g20_1` OK). The
  score's repeatability is larger than every between-class gap this study was trying to
  measure;
* **a single CSV column, `part_pts`, passes the pre-registered complementarity bar**
  (C 2/3, S 8/12, F 1/40) — and it is not detecting the scratch: it is detecting that the
  row comparison's mask was **inflated by up to +474 cells** on 15 defective captures and
  0 good ones (`part_pts` vs capture order rho = +0.614). The criterion is satisfiable by a
  station artifact, and this one is on the same boards that carry the scratch labels.

Offline only: no board, no `xsdb`, no `ps_ui/`, no firmware, no build. `dl/sweep_frames/`
and the two sweep CSVs were read only. Everything below is reproducible with one command
(§12), and every number came from a frozen pre-registration
(`dl/cnn_complement_20261030/PREREG_20261030T2048.md`, sha256 `dabbe055…8fdebd9`) plus one
amendment written before any analysis existed
(`PREREG_AMENDMENT_A1_ORDER_CONFOUND.md`, sha256 `3b479df6…2261911`).

---

## 1. The question, and the two wrong answers the design had to exclude

Rounds 1–4 trained a model to **replace** the rule and all four lost (8/19 vs 16/19,
McNemar p = 0.0078), with the cause measured: the only per-cell labels the pipeline could
supply were the comparison's own over-tolerance cells, so the learner inherited the
comparison's blind spot (pitfall M56). This round asks the different question:

> **does a learned model produce a signal that is not already in `darea` — does it catch the
> boards the rule misses, without acquiring good boards as false rejects?**

The rule at its shipped point (`DAREA >= 6`, already in the mailbox on all 80 rows):
**18/21 contamination, 1/12 scratch, 0/2 corner, 1 false reject in 41 good rows**. The three
contamination misses read `darea` 5, 5, 5 (`d7`, `d9`, `d13`).

**Wrong answer 1 — "the union detects more."** Rule-OR-model detects at least as much as the
rule by construction. The verdict is computed on the **model alone** (§7); the union is
reported in §6 with the false rejects it costs, and decides nothing.

**Wrong answer 2 — "it caught boards the rule missed" without asking why.** A model trained
on board-level labels can raise its score for reasons that have nothing to do with the
defect. That is why the trivial-scalar control (§9) runs under the identical leave-one-out
and the capture-order control (§10) was added before any result existed.

## 2. Population: 80 rows, 79 frames, 78 boards, 75 decided

The brief's "80 boards (41 good, 21 contamination, 12 scratch, 2 corner)" reconciles exactly,
but not at the row level:

| level | n | note |
|---|---|---|
| CSV rows | 80 | the unit the brief quotes |
| frame directories | 79 | `g38`'s is `_partial/REJECTED_g38_20261029_192826_darea+judged`, **0 bytes** |
| physical boards | 78 | `g20` captured twice (`g20`, `g20_1`), one label, held out together |
| rows the rule decided | 76 | 4 rows are `diff_ok=5` refusals: `g3`, `d6`, `d33`, `d35` |
| **decided boards with a frame** | **75** | **40 good + 35 defective** — the population below |
| decided, by class (rows) | 41 / 21 / 12 / 2 | good / contamination / scratch / corner = the brief |

The rule's `1/41` good-side denominator counts the rejected `g38` row (its verdict exists
without its frame). The model cannot score `g38`, so its false-reject denominator is 40;
the rule's false rejects on **those same 40** is also 1 (`g14`), so the comparison is on
identical boards. `g3` (good) and `d6`, `d33`, `d35` (defective) are **refusals**: the rule
made no answer, so they enter no denominator for either system; they are reported by name in
§11 because "the rule could not decide" is itself a gap.

Every frame passes the reader checks in §5 before any model touched it.

## 3. The model, the preprocessing, and the one thing that changed

**Architecture — reused unchanged** (`dl/model.py`, `TrustScopeNet`): three blocks of
`Conv2d 3x3/s1/p1 → BatchNorm → ReLU → MaxPool 2x2` at widths 16/32/32, then `fc 2048→64→2`;
7.80 M MACs for a 64x64 input. This is the network already synthesised into `ts_cnn_top`.
No bitstream, MAC count or I/O contract was touched.

**Preprocessing — reused unchanged** from the 2026-10-28 round: the green channel byte of
`frame.bin` (`main.c` copies exactly `row[..*3+1]`), native resolution; one 64x64 crop per
sample from an 80x80 window; augmentation shift ±8 px, gain 0.92–1.08, offset −8…+8, fresh
every epoch, `/255`; Adam 1e-3, cosine, **25 epochs**, batch 32, class-balanced sampler.

**Input contract — the full-resolution crop, not the deployed whole-frame 64x64
decimation.** In the deployed contract the part is ~24x12 px and a 2–5 px scratch is
sub-pixel; a model fed that could only reproduce the rule's blindness, which is the question
this round is trying to get past. **Consequence: a positive result here would be a result
about a *tiled* input path, not the shipped one.** The measured cost of the tiled path is
29–31 ms per patch on the board (~1.1 s for a 36-tile scan, not inline-viable at the 200 ms
takt; a 4-patch hybrid at the rule's candidate cells ≈ 120 ms). Nothing in this study ran on
silicon and no takt is claimed.

**What changed is the label source, and only that.** 2026-10-28 put positive patches on
cells the comparison itself measured as over tolerance. Here the label is the **human
ledger's board class** and the tile position is **label-independent** (the same 32-px tiling
of the part mask for every board). Every training tile of a defective board is positive;
every training tile of a good board is negative. That label is genuinely independent of the
rule: `dl/host_qc/sweep.py` asks for it **blind** — "it does not print the DAREA or the
verdict it just measured" (`sweep.py:43-47`), "the label is asked for AFTER the measurement
and before any number is printed" (`:1139-1140`) — and the tool says plainly "It cannot
verify a label. `g`/`d` is the operator's claim" (`:66-67`). This is the independent
annotation the 2026-10-28 report named as the missing ingredient, at board granularity.

**Aggregation — reused unchanged.** A tile votes NG when `logit1 > logit0`; the board is NG
when `#votes >= k`, with `k = 1 + max over the GOOD boards of the TRAINING fold`. k is per
fold and never sees the held-out board (observed range 6–18, median 12). Training uses every
second tiling position (1,304–1,315 windows/fold); evaluation uses every position
(22–47 per board, 2,621 total).

## 4. Validation: leave-one-board-out, and why it is necessary but not sufficient

Leave-one-**board**-out over all 78 boards (**40 good + 38 defective groups**; 78 folds). The
brief's two facts do close one lane: one session, and an exposure pinned host-side, so there
is no batch or exposure level to hold out, and every board is compared against one constant
reference (`part_ref` 685), so the reference cannot leak board-to-board. What remains is
board-to-board variation — a different part, surface, specular pattern and defect instance —
and that is exactly what LOTO holds out.

**But it does not close a second lane, and Amendment A1 records it:**

```
board  0..41   kind=good       18:17:36 .. 19:32:03
board 42..80   kind=defective  19:34:09 .. 20:59:21
```

`max(good index) = 41 < min(defective index) = 42` — **every good capture precedes every
defective capture, with no interleaving.** The class label is perfectly confounded with
capture order, and LOTO removes board identity but not time. The confound is measurable in
the pixels (frame mean green vs board index rho = −0.515, p = 1.2e-6) but it is not itself a
class separator (frame mean 123.8–132.9 good vs 125.8–132.2 defective). §10 quantifies what
it can do, and §12 states what it means for the verdict.

## 5. Known-answer checks, run before any model

`python dl\cnn_complement_20261030\checks.py` — all pass, on 79 frame sets:

| check | result |
|---|---|
| C1 grid reader | largest 8-connected group of `fine_deep > fine_tol` inside the mask equals the firmware's own **snapshot DAREA** in `meta.json` on **79/79** |
| C2 mask reader | `count(mask>0)` equals `MB_PART_PTS_C` (`meta.snapshot.pts`) on **79/79** |
| C3 rule reproduction | from the CSV alone, over all 80 rows: **18/21, 1/12, 0/2, 1/41** — the brief's own numbers |
| C4 population | 80 rows = 79 dirs + 1 rejected; 79 dirs = 41 good + 38 defective; 78 boards |
| C5 exposure proxy | interior median green spans 15.5 grey across boards; **`MB_EXP_LOCK` is in no evidence file** — the pin is a session record, and this proxy cannot separate exposure drift from surface |

C3 is the one that matters for the baseline: the rule compared against here is the firmware's
own rule at the shipped limit, not a re-invention. C6, in the analysis, checks that the
trivial control's machinery reproduces it too: `darea` under the LOTO range rule agrees with
the shipped rule on **71/75** decided boards (the differences are the folds where the
training good maximum is 5 rather than 7).

## 6. Result: per class, and the confusion matrix against the rule

```
class            n    rule (DAREA>=6)              model (votes>=k)
good            40    1  = 1/41 rows  (g14)       2   (g20, g25)
contamination   21   18  86% [64-97]             17  81% [58-95]
scratch         12    1   8% [0-38]               2  17% [2-48]
corner           2    0   0% [0-84]               0   0% [0-84]
defective       35   19  54% [37-71]             19  54% [37-71]
```

Intervals are Clopper–Pearson 95 %. The model and the rule are **equal on totals** and
disagree on which boards:

```
                   model NG   model OK
rule NG                 16          4
rule OK                  5         50
refused                  1          3
```

The 4 in `rule NG / model OK`: `d14` (contamination, darea 7), `d30` (scratch, darea 7 — the
rule's only scratch), `d8` (contamination, darea 15) and `g14` (the rule's false reject,
which the model correctly passes). The 5 in `rule OK / model NG`: `d7`, `d31`, `d34` and the
two good false rejects `g20`, `g25`. On the 35 decided defective boards: **3 rule-only,
3 model-only, McNemar exact p = 1.0000**.

Union, for the record and not for the verdict: **22/35** defective detected (contamination
19/21, scratch 3/12) at **3/40** good false rejects — two more detections and two more false
rejects than the rule.

![The model's board score against the rule's datum (A), and each board's distance from its own fold's threshold (B).](cnn_complement_20261030/out/fig_scores.png)

Panel A shows the mechanism in one picture: the contamination boards (red) ride high on the
model's score and are already on the rule's right side of the limit; the three misses
`d7`/`d9`/`d13` sit at `darea` 5 with scores overlapping the good cluster. Panel B shows the
scratch (orange) sitting **below** the good boards' median distance from the boundary.

## 7. The pre-registered verdict

Criterion, frozen before the run (`PREREG…§3`): `C` = contamination misses caught (of 3),
`S` = scratches caught (of 12), `F` = good false rejects (of 40);

```
COMPLEMENTARY iff (C >= 2 or S >= 3) and F <= 1
REDUNDANT     iff (C <  2 and S <  3) and F <= 1
WORSE         iff F >= 2
```

Applied once, mechanically:

| | value | bar | met |
|---|---|---|---|
| C | **1/3** (`d7` only) | ≥ 2 | **no** |
| S | **2/12** (`d31`, `d34`) | ≥ 3 | **no** |
| F | **2/40** (`g20`, `g25`) | ≤ 1 | **no** |

### **VERDICT: WORSE** (F = 2 ≥ 2).

Both catch bars are missed as well, so the model is not complementary on any reading: had the
false rejects been zero, the tree would have returned REDUNDANT. The distinction between
"redundant" and "worse" here is one board, and §8 says how little that is worth.

## 8. Intervals, and what will not be called a finding

* `C = 1/3` has a 95 % interval of **1 %–91 %**. The bar (≥2/3) is not met, but three boards
  cannot establish that a *different* model would also fail.
* `S = 2/12` is **17 % [2 %–48 %]**. Two boards either way would move it past the bar.
* `F = 2/40` is **5 % [1 %–17 %]**; the rule's 1/40 is 2 % [0 %–13 %]. The two intervals
  overlap almost entirely — **the verdict's margin is one board, and it is not statistically
  distinguishable from the rule.** The verdict is a category, not an effect size.
* The scratch AUC **0.360 [0.194, 0.537]** covers 0.5; corner 0.438 [0.075, 0.825] covers
  0.5 on two boards and says nothing at all.
* The contamination AUC **0.968 [0.919, 1.000]** is real and is the one thing the model does
  well — but the rule already does it (18/21 against the model's 17/21), so it is the
  definition of redundant information, not of complementarity.

## 9. The trivial-feature control: one scalar passes the bar, and it is an artifact

Five single-number-per-board scalars, identical LOTO, identical range rule (`NG iff x leaves
the training fold's good min…max`):

| scalar | defective NG | C | S | F | verdict by the same tree |
|---|---|---|---|---|---|
| T1 mask cell count (primary) | 2/35 | 1/3 | 0/12 | 2/40 | WORSE |
| T2 median green, part interior | 4/35 | 0/3 | 0/12 | 2/40 | WORSE |
| T3 mean green, whole frame | 0/35 | 0/3 | 0/12 | 1/40 | REDUNDANT |
| T4 `part_pts` (CSV column) | 19/35 | **2/3** | **8/12** | 1/40 | **COMPLEMENTARY** |
| T5 `darea` (reference row) | 16/35 | 0/3 | 0/12 | 2/40 | WORSE |

**The learned model is not beaten by the pre-registered primary scalar** (T1 catches 2
defective boards to the model's 19), so prediction P4 on T1 holds. But **T4 passes the
criterion the model fails**, and that is worth more than the model's own number:

T4 is `part_pts`, the row comparison's part-cell count — a single integer in the ledger. It
"catches" 8 of the 12 scratches. It is not seeing a scratch. `part_pts` exceeds the **stored
snapshot mask** by a median of **+353 cells** on the 9 scratch boards it fires on
(range **+117 … +474**; `d26` reads 1023 cells against a 549-cell snapshot mask), and across
all 14 scratch rows the difference runs −36 … +474 (median +226), while on the 41 good rows
the same difference has median **+57** (−21 … +183). And the row bbox runs to the grid edge
(`part_bx1 = 158`) on **15 rows — all 15 defective, 0 of the 42 good rows** (`d19`–`d28`,
`d32`, `d33`, `d35`, `d37`, `d38`). `part_pts` against capture order: **rho = +0.614,
p = 1.4e-9**.

So the only datum that satisfies the pre-registered complementarity criterion is measuring
**how much background the row comparison's mask swallowed**, on the late captures. Two
consequences, both reported rather than smoothed over:

1. the criterion's catch bars can be cleared by a station artifact, so a COMPLEMENTARY
   verdict on this population would have needed the artifact check before being believed;
2. the mask inflation is a **real station defect on 15 of 38 defective captures** (up to 474
   extra cells = 30k px of background inside the judged mask). It deserves its own
   investigation and is not caused by anything in this study.

## 10. The capture-order control (T6): a clock "detects" 35/35

| system | defective | good false rejects | verdict by the same tree |
|---|---|---|---|
| capture-order index (T6) | **35/35** | 2/40 | WORSE |

A classifier that reads only the capture index reaches every defective board and costs two
good ones — better than the rule and better than the model. That is the size of the confound:
on this population, **board-level detection is not identifiable.** The model itself does not
follow the clock cleanly — `Spearman(votes, capture index)` is **+0.066 (p = 0.69) within the
good boards** and **−0.637 (p = 3.9e-5) within the defective boards** (it fires *less* on the
later defective boards) — so this particular model was not carried by drift. But a positive
result could not have been attributed to the defect, which is why the amendment fixed that
reading before the numbers existed, and why the next measurement is a re-capture with the
defective boards interleaved.

## 11. What the model actually learned

Four measurements, all from the stored per-board records (`out/per_board.csv`):

**(a) It learned contamination, which the rule already has.** Contamination AUC 0.968,
vote fraction median **0.536** (range 0.190–0.921) against good **0.143** (0.000–0.474). The
model is a second, noisier copy of the rule's own signal. `Spearman(max_score, darea) =
+0.663` (p = 9.5e-11) on the 75 decided boards.

**(b) It did not learn scratch, and the scratches sit on the good side.** Scratch AUC
**0.360 [0.194, 0.537]**; vote fraction median **0.082**, *below* the good boards' 0.143;
the scratch board with the most votes (`d34`, 15/43 = 0.35) is inside the good range, and
the best good board (`g20`, 18/38 = 0.47) is above it. This reproduces, with a fifth and
independent method, the prediction that shaped this experiment: the class that the ten
statistics across four axes could not separate (AUC 0.37–0.62, intervals covering 0.5) is
not separated by a learned representation of the same pixels either.

**(c) The three contamination misses are at the good boards' level.** Vote fractions
`d7` 0.30, `d9` 0.26, `d13` 0.29 against good 0.00–0.47, median 0.14. They sit in the good
distribution's upper quartile; a threshold that admits 2 of 40 good boards catches one of
three of them, which is what happened. `d9` has the highest board score of the three
(5.47, above every good board) but only 7 votes in 27 tiles — a reminder that "max score" and
"count ≥ k" are different decisions; the pre-registered one is the count.

**(d) The score is not repeatable on the same board.** `g20` and `g20_1` are **one physical
board captured twice**, evaluated in the same fold with the **same model and the same k = 16**:

```
g20    18 votes / 38 tiles = 0.47  -> NG
g20_1   2 votes / 22 tiles = 0.09  -> OK
```

The decision flips on a repeat capture. That 16-vote swing is the noise floor of this
measurement, and it is larger than every between-class difference the study was built to
detect. Any future claim of the form "the model catches N more boards" must be read against
it.

**(e) The absolute `k` lets the tile count help.** Tiles per board range 22–47
(median 35), and `Spearman(votes, n_tiles) = +0.681` (p = 1.8e-11): a board with 47 tiles
needs 13/47 = 28 % of its tiles to fire, one with 22 tiles needs 59 %. Normalising
(votes/n_tiles, same LOTO calibration) does **not** rescue the model — C 1/3, S 1/12,
F 3/40, still **WORSE** — so this is a real flaw in the aggregation inherited from the
earlier protocol, not an explanation that flips the verdict.

**(f) No threshold rescues it either.** A post-hoc sweep of one global `k` on the stored
counts: at **≤1 good false reject** the best operating point is `k = 16`, which catches
**0/3 misses and 0/12 scratches**. Every point that catches a scratch costs at least 4 good
boards (k = 6 → 3/12 scratch, 15/40 false rejects). This is the same shape the 2026-10-28
round found ("no k can approach 16/19"), reproduced on twice the data.

## 12. What remains unproven, and what would change the answer

1. **Any other model.** This tested the deployed architecture, the deployed preprocessing
   and one label source. The null is about *this* model on *this* population. A different
   architecture, or per-pixel labels, is untested — and the per-pixel difference is not in
   the record at all (no reference frame in the five evidence files).
2. **The scratch class, at pixel level.** The label is the operator's blind claim at board
   granularity; the 2026-10-28 annotation round found that the operator could not locate the
   scratch on 3 of 7 boards. Twelve boards, AUC 0.36, interval covering 0.5 — this is
   consistent with "no signal" and also with "a signal this model and this input contract
   cannot reach".
3. **The quantised deployment path.** Scores here are the float model. The 2026-10-28 model's
   int8-vs-float per-tile agreement was 0.97; that measurement is not repeated here, so the
   numbers above are not a statement about the bits on the board.
4. **The tiled path on silicon.** Never run (offline study), and the input contract differs
   from the shipped whole-frame decimation (§3).
5. **Whether the mask inflation is a station fault.** 15 rows show the row mask swallowing up
   to 474 extra cells; the cause (exposure state, part, threshold) is not diagnosed. Until it
   is, every `part_pts`/`darea` column on those boards carries it, and any board-level
   learner can cheat with it.
6. **A positive answer is unobtainable from this population** — the class is perfectly
   ordered in time (§4, §10). The measurement that would make a positive answer meaningful is
   a **re-capture of the same 80 boards with the defective boards interleaved**; it is one
   sweep, it removes the order confound, and it also re-establishes the reference.
7. **Prediction scorecard, stated plainly.** P1 (scratch 0–2/12, AUC interval covers 0.5):
   **held** (2/12, 0.360 [0.194, 0.537]). P2 (fewer contamination than the rule's 18):
   **held** (17). P3 (verdict REDUNDANT): **refuted** — the verdict is WORSE, i.e. the model
   was worse than predicted, not better. P4 (the primary scalar T1 does not match the model):
   **held** (T1 detects 2 defective boards, the model 19).

## 13. Reproduction

```
python dl\cnn_complement_20261030\run_all.py
```

runs the five known-answer checks, the 78 leave-one-board-out folds, the five trivial
scalars, the capture-order control and the analysis, and prints the verdict. **Measured wall
time on this host: 48.4 min for the folds** (78 × 29.9–41.6 s, 8 threads of 20) plus ~25 s
for the checks, the trivial controls and the analysis; total **≈ 49 min**. `loto.py` resumes
from `out/loto_results.json` if interrupted.

**Packages: nothing had to be installed.** The run used what was already on the machine —
Python 3.14.6, numpy 2.5.0, scipy 1.18.0, torch 2.14.0+cpu, matplotlib 3.11.0, Pillow 12.3.0.
No GPU, no sklearn, no downloads. One thread setting was measured (8 threads is ~30 % faster
than the default 14 for this batch size) and is recorded in `loto.py`.

Determinism: per-fold seeds `1234 + fold index`; bootstrap seed 20261030. A re-run reproduces
the fold results bit-for-bit on the same torch build; the *bootstrap* intervals are seeded and
reproducible, the model itself is not guaranteed across torch versions.

## 14. Files

| file | what |
|---|---|
| [`PREREG_20261030T2048.md`](cnn_complement_20261030/PREREG_20261030T2048.md) (+ `.sha256`) | the frozen pre-registration |
| [`PREREG_AMENDMENT_A1_ORDER_CONFOUND.md`](cnn_complement_20261030/PREREG_AMENDMENT_A1_ORDER_CONFOUND.md) (+ `.sha256`) | the capture-order confound, added at fold 6/78 |
| [`checks.py`](cnn_complement_20261030/checks.py) | C1–C5 known-answer checks |
| [`common.py`](cnn_complement_20261030/common.py) | population, labels, tiling, patches |
| [`loto.py`](cnn_complement_20261030/loto.py) | the 78 folds (`--smoke`, `--dry-run`) |
| [`trivial.py`](cnn_complement_20261030/trivial.py) | T1–T5 scalars, identical LOTO |
| [`analyze.py`](cnn_complement_20261030/analyze.py) | confusion matrix, intervals, AUC, T6, verdict |
| [`make_figure.py`](cnn_complement_20261030/make_figure.py) | the figure above |
| [`run_all.py`](cnn_complement_20261030/run_all.py) | one command |
| [`out/per_board.csv`](cnn_complement_20261030/out/per_board.csv) | every board: votes, k, score, both systems, all five scalars |
| [`out/analysis.json`](cnn_complement_20261030/out/analysis.json) | every number in this report |
| [`out/loto_results.json`](cnn_complement_20261030/out/loto_results.json) | per-fold k, training-good counts, per-tile scores |
| [`out/fig_scores.png`](cnn_complement_20261030/out/fig_scores.png) | the figure |

## 15. 中文摘要

**结论：不互补，反而更差（预注册判据直接给出 WORSE）。** 规则在出厂工作点（DAREA≥6）上是
污染 18/21、划伤 1/12、缺角 0/2、良品误判 1/41；模型在同一批 75 块可判板上是污染 17/21、
划伤 2/12、缺角 0/2、良品误判 **2/40**。总数打平（各 19/35），配对检验 p=1.0000，但模型多一块
良品误判。判据的三格：C=1/3（只抓到 d7）、S=2/12（d31、d34）、F=2/40（g20、g25）——三条都没
达标。

**模型学到的是污染，不是划伤。** 污染 AUC 0.968 [0.919,1.000]，但规则本来就有这个信息
（18/21 对 17/21），所以是冗余；划伤 AUC **0.360** [0.194,0.537]，区间盖住 0.5，划伤板的投票
比例中位数 **0.082 低于良品的 0.143**——划伤落在良品一侧。三块污染漏检 d7/d9/d13 的投票比例
0.30/0.26/0.29，全部落在良品分布上四分位之内，抓到一块正是"在 2/40 误判预算下的期望值"。

**两个对照把结论钉住了。** （一）**同一块板拍了两次**：g20 与 g20_1 在同一个模型、同一个 k=16
下得 18 票和 2 票，判决翻转——这个 16 票的摆动比本研究要量的类间差还大。（二）**一个 CSV 列就能
通过判据**：`part_pts` 拿到 C=2/3、S=8/12、F=1/40，看起来"互补"；但它量的是**行比较的掩模被
撑大**——15 块板掩模一直顶到格子边缘（bx1=158），**15 块全是不良板、41 块良品一次都没有**，
`part_pts` 比快照掩模多出中位 +238 格（最多 +474），且与拍摄顺序相关 rho=+0.614。所以：判据可以
被一个台位伪影满足，而这个伪影本身是 15 块不良板上的真实台位缺陷（行比较吃进最多 474 格背景）。

**为什么这块数据无法给出正面答案：类别与拍摄顺序完全共线。** 42 块良品全部在 0–41（18:17–19:32），
38 块不良全部在 42–80（19:34–20:59），没有任何交错。只用拍摄序号的"分类器"就能拿到 35/35、误判
2/40。因此留一板出并不能消除时间混杂：**正面结果无法归因于缺陷**，而**阴性结果仍然成立**（模型
连一个可学的时序线索都没利用，投票与序号在不良板内是 −0.637）。要得到可信的正面答案，需要把不良
板与良品交错重拍一次（一次扫描的代价），这也是本研究建议的下一个测量。

**判据预测对了几条**：P1（划伤 0–2/12、AUC 区间盖 0.5）成立；P2（污染少于规则）成立；
P3（判据预测 REDUNDANT）**被推翻**——实际是 WORSE，方向比预测更差；P4（主标量 T1 打不过模型）
成立。

**复现**：`python dl\cnn_complement_20261030\run_all.py`，78 折 48.4 分钟，总计约 49 分钟；
不需要安装任何包（已有 numpy/scipy/torch-cpu/matplotlib）。预注册 sha256 `dabbe055…8fdebd9`，
修正案 A1 sha256 `3b479df6…2261911`。
