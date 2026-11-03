# GAIN FREEZE — the grey-scale pair is taken with the reference, not with the live frame

Date: 2026-10-29.  Board: none touched by this change (write/build only; the station is
with the owner and a 100-board sweep has just finished on it).  The build produced by
this change is a **checkpoint**, not the shipping image: the working tree also carries an
uncommitted BELT mask change (see section 9), and the shipping build will be cut from the
merged tree, not from this checkpoint.

## 1. The mechanism, and the measurement that asked for it

Every comparison used to re-derive the brightness correction from the frame it was about
to judge:

* `ps_ui/main.c:9254` (HEAD d9cb334, function `diff_frame`):
  `g_diff_scale = lm ? ((g_ref_mean << 8) / lm) : 256u;`
  — `lm` is the mean of **this live frame's** 80x45 cell lattice.
* `ps_ui/main.c:9494-9495`: that scale is applied to each cell.
* `ps_ui/main.c:9508`: `g_diff_bias = sum_d / (DIFF_W * DIFF_H);`
  — the mean signed residual of **this same pass**, applied on the **next** comparison.

So both numbers are feedback from the frame being judged.  A 1-4 grey re-centring is
enough to flip cells that sit on the 14-count threshold.

Measured consequence, twice, on the same station:

| what was measured | value | source |
|---|---|---|
| stationary board, `MB_DIFF_DAREA` between comparisons | **±6 cells** | `dl/awb_20261028/REPORT_20261028_awb.md` §5 |
| 41 good boards against one reference | **DAREA 0…7, median 2** | `dl/host_qc/logs/sweep_20261029_181623_sweep.csv` |
| aggregate grey repeatability of the same frames | **2.2-2.8 grey** | same report, §6 |

The spread is the re-centring, not the noise.

## 2. What is frozen, and why the frozen value is the identity

The pair is computed **once, in `ref_take()`** (`MB_CMD = 9`, the boot reference, the
`MB_CMD = 17` re-derive, and the panel button all go through it), stored in RAM, and used
by every later comparison until the next reference.  Re-take ⇒ re-freeze.

At the instant of the reference the live lattice and the reference lattice **are the same
picture**: `ref_capture()` copies the frame into `REF_BASE`, and `ref_mean_build()`
computes the same 14,400-cell mean from it.  The value the old expression yields there is
therefore exactly **1.0 in 8.8 fixed point (256)** and a bias of **0**.  The frozen pair is
the identity *by construction* — which is the point: a correction that cannot follow each
frame's own mean.  Storing it rather than hard-coding 256/0 is what lets a sweep row say
which pair was used, and lets a future reference that is taken under different conditions
carry a different pair without changing the comparison code.

**The light gate is still measured.**  A live gain outside 0.5..2.0 still refuses with
`MB_DIFF_OK = 4`, because that is a refusal, not a correction: it re-centres nothing.  What
is gone is the compensation itself.  Consequence, stated rather than hidden: a slow light
drift is no longer divided out; it appears as a global grey offset.  Only the 0.5..2.0
refusal remains.  This is the main new risk of the change and the re-sweep is its test.

**No reference ⇒ today's behaviour.**  If no frozen pair is in force (`g_frz_ok == 0`),
`diff_frame()` falls back verbatim to the old live-scale computation and the old delayed
bias update.  It never divides by a frozen zero and never applies a stale denominator.

## 3. Sites changed (HEAD d9cb334 line numbers)

| # | site | change |
|---|---|---|
| 1 | `main.c:2400` (mailbox `#define` block) | `MB_FRZ_SCALE/BIAS/STATE` = 585/586/587 and the rationale |
| 2 | `main.c:3379` (globals beside `g_diff_scale`) | `g_frz_scale`, `g_frz_bias`, `g_frz_ok`, `g_frz_serial`, `g_frz_last`, `frz_publish()` |
| 3 | `main.c:8364` (`ref_take` early return: exposure record unreadable) | freeze invalidated: `g_frz_ok = 0`, last outcome 2, republished |
| 4 | `main.c:8456` (`ref_take`, after the reference is accepted and `tol_reset()`) | the pair is stored (256 / 0), serial incremented, state published |
| 5 | `main.c:9252-9261` (`diff_frame`, the scale block) | live ratio kept **only as the 0.5..2.0 refusal test**; the applied pair is the frozen one, or today's if none is frozen |
| 6 | `main.c:9508` | the measured mean residual updates `g_diff_bias` **only when no freeze is in force** (today's path); with a freeze it is not fed back |
| 7 | `main.c:9509` | the frozen pair is republished beside the result it was applied to |
| 8 | `main.c:15433` (MB_CMD=9 request refused: AEC not settled / clipping) | last outcome 3, the pair in force is left alone |
| 9 | `main.c:15383` (one-shot boot words) | safe defaults published before anything can be captured: 256 / 512 (= bias 0) / state 0 |

## 4. The frozen words (host-readable, append-only)

| index | name | meaning |
|---|---|---|
| **585** | `frz_scale` | frozen gain, 8.8 fixed point, **256 = 1.0**, same unit as `MB_DIFF_SCALE` (200) |
| **586** | `frz_bias` | frozen bias, **+512** (0 reads as 512), same convention as `MB_DIFF_BIAS` (190) |
| **587** | `frz_state` | `bit0` = freeze in force; `bits1..7` = outcome of the last reference attempt (0 none, 1 frozen, 2 reference unusable, 3 request refused); `bits8..31` = **freeze serial**, incremented on every successful freeze (0 = never) — this is "when it was taken" |

Why 585 and not 583: `583` and `584` are claimed by the **uncommitted BELT change** in the
working tree (`MB_PART_RULESEL`, `MB_PART_CHROMA`), which is not in this commit.  The
committed tree is free from 583, but the working tree is free only from 585, and this
change has to be committable in both.  `dl/mb_free.py` reports `free 585..639` **with** the
BELT change applied and `free 583..639` without it; `dl/host_qc/qc_mailbox.py` claims none
of 585-587 in either version.  The check is recorded in the build facts below.

The map and the checker are updated in the **same commit**: `dl/host_qc/qc_mailbox.py`
(three `WordDef`s at the end), `dl/host_qc/check_words.py` (three name → macro rows),
`dl/host_qc/sweep.py` (three columns appended to `ROW_COLUMNS`, so the next sweep writes
them into every row).

The ELF is scanned as well (`dl/check_mb_words_elf.py`): a `#define` name check cannot see
a word reached through `MB_X + n`, and it cannot see a literal offset, so the built image's
text and data are searched for references to words 585-587 and for the appended range.

## 5. Prediction (written **before** the build — this section is the pre-registration)

**Hypothesis H.**  The good population's spread is produced by the per-comparison
re-centring; removing it makes the same limit behave better on the contamination class.

At the shipped limit 6 (`MB_DIFF_LIM_USED = 6`; the verdict is `DAREA >= limit`, confirmed
from `dl/host_qc/sweep.py:8` and from the old CSV, where DAREA 7 reads NG and DAREA 5 reads
PASS), the prediction for the **same 80 boards, same order** is:

| class | before (2026-10-29 sweep) | predicted after |
|---|---|---|
| contamination | **18/21 = 85.7 %** (misses read **5, 5, 5**) | **21/21 = 100 %** |
| scratch | **1/12 = 8.3 %** | **unchanged — this change cannot help it** |
| corner | **0/2** | unchanged |
| good | **0…7**, median 2; one at **7**, three at **5**; judgeable n = 41 | **0…3/4**, median ≤ 2; **no good board at ≥ 6** |
| false rejects (good rows at DAREA ≥ 6) | **1** (`g14`, DAREA 7) | **0**, and never more than 1 |

**The scratch class will not improve.**  A thin scratch is a sampling-geometry problem
(8x8 cell means: the firmware's own note at the fine-pass comment says a thin line "adds
tens of counts to the cell RANGE while moving the cell MEAN by a couple of grey levels").
Freezing the brightness pair does not put the scratch back into the mean.  Do not read a
scratch result as evidence for or against this change; 12 boards with one hit cannot
resolve it anyway.

**The numeric caveat, written down so the re-sweep can refute the prediction instead of
arguing with it.**  The three contamination misses read 5, 5, 5.  Under `DAREA >= 6` a 5
is still a miss.  For "the same limit 6 catches 5, 5, 5" to be true, the frozen comparison
must move those three rows to **≥ 6** — i.e. the re-centring must have been suppressing
them by at least one count.  That is a testable sub-prediction: **the three rows d7, d9,
d13 must read DAREA ≥ 6 after the freeze** (they are the 5,5,5 rows in the old CSV).  If
they stay at 5 while the good maximum falls to 4, then contamination is still 18/21 and
the claim as phrased fails; the honest next step would be a limit policy of 5
(`DAREA >= 5`), which is a different change and is not made here.

Also predicted, because they are the evidence that the mechanism ran at all:

* after `MB_CMD = 9`, `frz_state` bit0 = 1, `frz_scale` = 256, `frz_bias` = 512;
* `frz_state` is **constant across every comparison** of one sweep (same serial) unless a
  reference is re-taken; a re-take increments the serial by exactly 1;
* with no reference (before the boot reference), `frz_state` = 0 and the comparison does
  not run at all (as today).

## 6. Re-measurement protocol (same 80 boards, same order, paired)

1. Flash the **merged** tree's build; record `MB_FWID0..2` and confirm the id is not
   `327CD597` (the station still runs `327CD597` until this flash).
2. Take the reference exactly as before (`MB_CMD = 9`) on the same reference board (g0) in
   the same position.  Wait for `MB_DIFF_OK = 1` **and** `frz_state` bit0 = 1; record
   `frz_scale`, `frz_bias`, `frz_state`.
3. Run the same sweep tool over the **same 80 boards in the same order**, with the same
   labels.  The tool now writes `frz_scale`, `frz_bias`, `frz_state` into every row.
4. One command:

   ```
   python dl/host_qc/pair_compare.py --old dl/host_qc/logs/sweep_20261029_181623_sweep.csv --new <new sweep csv> --require-freeze
   ```

   It refuses to compare if the label set differs (and prints which labels changed).  Per
   class it prints: judgeable n, detected before/after, false rejects before/after, the
   paired DAREA delta for every label, a **McNemar exact test** on the discordant pairs
   (SciPy `binomtest`, which is **already two-sided** — the p-value is not doubled), and
   the good population's min/median/max plus how many sit at 5 and at 7.  It also decodes
   `frz_state` per row and refuses the freeze evidence if a row has no freeze in force.
5. 1.5 h budget: 80 boards at the old sweep's ~20 s/board (from the timestamps in the old
   CSV) is ~30 min of acquisition; the rest is the re-reference and the refusals.  If time
   runs out, the paired rows are still analysable — do not reorder boards to finish.

## 7. What happens on each of the six refusal codes

`MB_DIFF_OK` codes for a refused comparison.  In every one of them the frozen pair is
**not applied to a judgement**: the comparison either never reaches the arithmetic, or
returns before the cell pass.  The pair itself stays in force for the next comparison
unless the reference is replaced (codes 0 and the `ref_take` early return).

| code | name | what the freeze does |
|---|---|---|
| **0** | NO_REFERENCE | No reference ⇒ no comparison: the main loop does not call `diff_frame()`.  `frz_state` = 0 (not in force); the boot defaults 256/512 are readable but are never applied. |
| **2** | REFUSED_LIGHT_CHANGED | **Retired** as a production code (see the note above `MB_DIFF_OK`); no site assigns it.  If an old host sees it, the freeze path is not involved. |
| **3** | REFUSED_IMAGE_UNTRUSTWORTHY | Two sites.  (a) A `MB_CMD = 9` request while the AEC is not settled or the frame clips: the request is refused, the **old** pair stays in force, `frz_state` outcome becomes 3.  (b) A comparison while the AEC/clip gate is bad: no cell pass, pair unused. |
| **4** | REFUSED_CONDITIONS_DRIFTED | The live gain ratio is outside 0.5..2.0: refuse before the cell pass.  `MB_DIFF_SCALE` is published as the **measured live ratio** (so the host sees why), the frozen pair is untouched and still valid for the next frame. |
| **5** | REFUSED_REGISTRATION | Refuse before the cell pass; pair unused; still in force for the next comparison. |
| **6** | REFUSED_PART_NOT_FULLY_IN_VIEW | Refuse before the registration/cell passes; pair unused; still in force for the next comparison. |

## 8. What is NOT measured (this document is not a board result)

* **No board result at all.**  Nothing was flashed, nothing was read from the station.
  The station still runs build **`327CD597`** until the owner flashes.
* Whether the frozen identity actually narrows the good population (the central
  prediction).  Unmeasured until the paired re-sweep.
* Whether d7 / d9 / d13 move from 5 to ≥ 6.  Unmeasured.
* Light-drift robustness under a frozen pair.  The 0.5..2.0 gate is coarse; a 20 % drift
  is inside the gate and would appear as a global offset.  Unmeasured.
* The interaction with the uncommitted BELT mask change: this checkpoint **does not
  contain** it, so its build id is evidence that the freeze compiles, not that freeze +
  BELT together produce any particular DAREA.  The shipping build is the merged tree.
* The scratch class and the corner class: not addressed (see §5).
* The four refused rows of the old sweep (g3, d6, d33, d35) are excluded from the paired
  denominators; if they refuse again the effective n is smaller, and the script says so.

## 9. The uncommitted BELT change, and the merged-tree rule

The working tree contained another agent's uncommitted BELT mask change to
`ps_ui/main.c` (+ `dl/host_qc/qc_mailbox.py`, + `dl/host_qc/qc_belt.py`,
`dl/product_id/capture_neg.py`, a log, and two deleted zips).  It was preserved **before**
this change was written:

```
dl/patches/20261029_belt_uncommitted/main_c.patch
dl/patches/20261029_belt_uncommitted/qc_mailbox.patch
dl/patches/20261029_belt_uncommitted/main.c.worktree
dl/patches/20261029_belt_uncommitted/qc_mailbox.py.worktree
dl/patches/20261029_belt_uncommitted/sha256_before.txt
```

The commit for this change contains the freeze alone (plus its build artifacts).  The BELT
change was re-applied to the working tree afterwards, so **the tree at the end is the
merged state**: this commit + BELT on top, and the BELT change is still uncommitted.  A
build cut from that merged tree is the one to flash; the checkpoint's build id in this
commit is evidence that the freeze compiles and nothing more.

**Proof that the re-apply is the same change, not a paraphrase of it.**  The saved patch's
added and removed line streams are byte-identical to the recovered `git diff` for both
files (main.c: 326 added / 44 removed; qc_mailbox.py: 33 added / 0 removed).  The merged
`ps_ui/main.c` in the working tree is byte-identical (sha256
`941de759b9a5ca0a365b05a7f24dee7fcd71d3eb8401dbdff5f762097d4c6e6b`) to an independent
reconstruction: the committed base `d9cb334`, plus the BELT patch, plus this commit's
diff.  `qc_mailbox.py` minus the inserted BELT block equals the committed file byte for
byte.  The raw `git diff` text hash differs from the saved patch hash only in the hunk
headers and the `index` line, which necessarily change when the pre-image changes; that is
why the proof compares the added/removed streams and the reconstructed file, not the raw
diff text.

## 10. Build facts

*Appended after the build; the prediction in §5 was written before it.*

**This id is the freeze-only checkpoint, not the shipping image.**  It does not contain
the uncommitted BELT change, so a DAREA measured with `BE7E51A4` is evidence that the
freeze compiles and runs — it is not the number tomorrow's sweep will produce from the
merged tree.  Say which is which in any report: checkpoint `BE7E51A4`, station now
`327CD597`, shipping build = merged tree (new id, cut after the BELT change is committed).

Command: `ps_ui/build.ps1` (PowerShell 5.1, `-ExecutionPolicy Bypass`), exit 0.

| fact | value |
|---|---|
| **new build id** | **`BE7E51A4`** (the sixth; 13 source files) |
| build the station runs now | `327CD597` — unchanged until the owner flashes |
| warnings | **4**, the same four as the `327CD597` build, no new ones: implicit declaration of `dcache_invalidate` (main.c:934), conflicting types for it (main.c:1240), `always_inline` not inlinable (draw_camera_impl), `wait_probe_edge` defined but not used |
| `.text` | 119,944 B (was 120,048) |
| `.data` | 116 B (was 112) |
| `.bss` | **12,116 B** at 0x24000..0x26F54 (was 12,092) |
| `size` total | 132,176 B |
| ELF / bin | 201,796 B / 120,060 B; loadable end 0x1D4FC |
| OCM used (highest section end) | **159,572 B of 262,144 (60.9 %)**; page table 0x20000..0x24000 not overlapped |
| mailbox layout check (in build) | **424 `MB_*` words, 424 distinct indices, 0 collisions**; 4 literal offsets, 0 also named (was 421/421) |
| host map check | `check_words.py`: 144 host words, 141 defined/matched, 0 mismatches, tick rate 333,415 both sides.  The 3 "not defined yet" (`eg_margin`, `eg_roi`, `ref_avg`) are the pre-existing stage-L words, unchanged by this commit |
| `dl/mb_free.py` | after the change: `free 583..584 (2)` and `free 588..639 (52)` — i.e. 585/586/587 are now claimed and nothing else moved.  (The tool prints 423 parsed words / 422 distinct because `MB_FP_INVERT` is defined twice with the same name at index 219, a pre-existing parser artifact; the build's own check is authoritative at 424/424.) |

**ELF scan** (`dl/check_mb_words_elf.py`, run on `ps_ui/ps_ui.elf`).  The scanner reads
`MAILBOX` from `main.c`, handles both code shapes in this ARM image (a full `movw/movt`
address, and a materialised `0x10F00000` base plus `[reg, #index*4]`), and separately scans
the raw image for little-endian full addresses in the appended range:

```
word 585  in diff_frame     x1
word 585  in main_loop      x2
word 585  in ref_take       x2
word 586  in diff_frame     x1
word 586  in main_loop      x2
word 586  in ref_take       x2
word 587  in main_loop      x2
word 587  in ref_take       x2
raw little-endian values in the image: none
words in 583..639 that appear anywhere: 585, 586, 587
```

The count per function is the number of inlined `frz_publish()` sites: `ref_take` has two
(the early return and the success path), `main_loop` has two (the boot defaults and the
refused `MB_CMD = 9` branch), and `diff_frame` has one pair-only republication (585/586,
no 587 because it does not touch the state word).  **No other function and no other word
in 583..639 is referenced**, so a computed-index block or a literal offset cannot be
silently sharing 585/586/587.  This is a source/build check: it does not prove the
running image is this ELF.

**Comparison tool validation (known answers, run before the re-sweep).**  `pair_compare.py`
was run on the old CSV against itself: every delta 0, every McNemar p = 1.000, detected
18/21 contam, 1/12 scratch, 0/2 corner, 1 false reject, judgeable n = 41 good / 21 / 12 / 2
and 4 refusals — i.e. exactly the brief's population.  It was then run on a synthetic
"after" built by changing four rows: d7/d9/d13 5 -> 8 and g14 7 -> 4.  Expected and
observed: contamination 18 -> 21, McNemar p = 0.250 (binomtest 3/3, two-sided as printed,
not doubled); false rejects 1 -> 0, p = 1.000; overall 0.625; good max 7 -> 5, at7 1 -> 0.
A renamed label (`d7` -> `d99`) was refused with both labels named, and a file without the
`frz_*` columns was refused under `--require-freeze`.  Use `--require-freeze` for the real
re-sweep: a row that does not record the pair cannot prove which pair produced its DAREA.
