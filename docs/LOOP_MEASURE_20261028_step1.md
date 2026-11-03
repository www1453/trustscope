# The loop-time instrument: reconciliation, noise floor, and the pre-registration for step 2

**Date:** 2026-10-28
**Station state as found (verified, not assumed):** firmware `TSC17C54944F`
(`MB_FWID0..2 = 0x31435354 / 0x34354337 / 0x46343439`, little-endian "TSC1"+"7C54944F"),
`MB_AEC_STATE = 1` (converged), `MB_EXPOSURE = 8698` (pinned as stated), `MB_READY = 1`,
`MB_DIFF_OK = 1` (compared), `MB_CNN_PASS = 8`, `MB_PART_TK_ON = 1`.
The board was **not** power-cycled and **no** bitstream was loaded: every number below is a
read of the running station.

**Status of this document.** Sections 1-6 are step 1 of the brief, which is a gate. Sections 7-8
are the pre-registration: they say, *before* any "after" number exists, which instrument counts,
how many windows are needed, and what result would be reported as an improvement and what would
be reported as "inside the noise". **Sections 7-8 were written before step 2 was attempted.**

Everything below comes from three scripts in this directory:

| Script | What it does | Log |
|---|---|---|
| `measure_loop_v3.tcl` | timer calibration, observer test, consecutive 32-loop windows | `measure_loop_cal.log`, `measure_loop_before2.log` |
| `measure_phase_20261028.tcl` | 20 consecutive windows with the full 7-phase vector | `measure_phase_before.log` |
| `ab_phase_20261028.tcl` | A/B/A known-answer test of the phase attribution (§6b); **writes only word 512, restores it, verifies the restore twice** | `ab_phase_20261028.log` |
| `loop_noise_floor.py`, `loop_phase_analysis.py`, `ab_phase_analysis.py` | the arithmetic, from the raw tick totals | `loop_noise_floor.json` |

---

## 1. The two definitions, as the code defines them

### Definition A — `MB_T_TOTAL` / `MB_T_N` (the firmware's own loop timer)

`main.c:10122` and `main.c:10125`:

```
#define MB_T_TOTAL   76u         /* byte 304: whole loop                        */
#define MB_T_N       79u         /* byte 316: how many loops these sums cover   */
```

`main.c:15508-15512`, inside `main_loop`, once per iteration:

```c
tH = R32(GTIMER);
g_sum_pub += tH - tG;
g_sum_total += tH - g_t_prev;   /* g_t_prev was the PREVIOUS iteration's tH */
g_t_prev = tH;
++g_nloops;
```

`main.c:15518-15527`, only when the window is full:

```c
if (g_nloops >= 32u || g_sum_total > 3000000000u) {
    ...
    R32(MAILBOX + MB_T_TOTAL  * 4u) = g_sum_total;
    R32(MAILBOX + MB_T_N      * 4u) = g_nloops;
    ...
    g_sum_total = 0u;  g_nloops = 0u;
}
```

So one reading is the **sum of 32 consecutive complete iterations**, measured from one
end-of-loop (`tH`) to the next, by the same clock, with no host in the loop.
`MB_T_TOTAL / MB_T_N / (ticks per ms)` is the loop period.

### Definition B — `PROGRESS` transition counting

`dl/evidence_20261027/loop_rate_20261027.tcl:38-45`:

```tcl
set p [RM [W 11]]
if {$prev >= 0 && $p != $prev} { incr trans }
...
set frames_per_s [expr {double($trans) * 1000.0 / double($el)}]
L [format "loop period  ~ %.1f ms  (%.2f loops/s)" [expr {1000.0 / $frames_per_s}] $frames_per_s]
```

It counts **changes of the value of word 11** and reports `elapsed / changes` as the loop
period.

---

## 2. Why they disagree — from the code, then confirmed by measurement

### 2.1 The code

Word 11 is `MB_PROGRESS`, and the firmware documents what it is at `main.c:12564-12581`:

```c
/* PS-owned progress beacon (offset 44).
 *
 * A fault handler can tell you a fault happened, but not reliably WHERE.  This
 * beacon is written as each stage of a frame completes, so reading one word
 * says how far the code got before it stopped:
 *     1 entered the loop   2 measured          3 camera drawn
 *     4 panel drawn        5 bottom drawn      6 cache cleaned
 *     7 frame flipped
 * A value that stops advancing at 3 names the culprit directly, with no
 * interpretation of DFSR/DFAR needed.  That is a measurement, not a guess. */
#define MB_PROGRESS   11u
#define PG_LOOP    1u     #define PG_MEAS    2u     #define PG_CAM     3u
#define PG_PANEL   4u     #define PG_BOTTOM  5u     #define PG_CLEAN   6u
#define PG_FLIP    7u
```

and it is written **seven times per loop**: `PG_LOOP` at `14303`, `PG_MEAS` at `14707`,
`PG_CAM` at `15207`, `PG_PANEL` at `15216`, `PG_BOTTOM` at `15230`, `PG_CLEAN` at `15421`,
`PG_FLIP` at `15502`.

**This is a stage register, not a loop counter.** A change of its value is a **stage**
boundary. The script's `trans` is therefore the number of *observed stage transitions*, and
`elapsed / trans` is not the loop period — it is the loop period divided by the number of
stage transitions the host happened to observe per loop:

```
loop_period = elapsed / trans × (observed stage transitions per loop)
```

That factor is not a constant, and this is the part that makes the instrument unusable rather
than merely miscalibrated: **it is a function of the loop period itself.** The sampler polls at
a fixed rate, so the number of samples per loop, and hence the number of stage boundaries it can
see, changes when the loop period changes. The instrument's output depends on its own input.

### 2.2 Measurement confirmation

`dl/measure_loop_cal.log`, one burst of 150 samples of word 11:

```
sampled 150 times in 1870 ms (12.5 ms per sample), 21 transitions
distinct values seen = 2 1 5 4
counts per value (value count ...) = 2 71 1 72 5 6 4 1
transition rate = 11.23 per second; sampler Nyquist = 40.11 Hz
```

An earlier burst (`measure_loop_before.log`) saw `1 2 5 4 3` — five distinct values. Word 11 is
observed taking **4-5 distinct values**, dominated by `1` and `2` (71 + 72 of 150 samples),
because `PG_LOOP` and `PG_MEAS` span the long stages. It cannot be a loop counter.

The 2026-10-27 run that produced **119.0 ms** shows the same signature in its own log — it
printed `distinct markers = 2 5 1 4 3`, five values, while reporting the number as a loop
count. Its sampler took `12024/200 = 60.1 ms` per sample and produced `101` transitions in
12,024 ms, i.e. `8.40 "loops"/s`. **`8.40 Hz` is within 1% of that sampler's Nyquist limit,
`1000/(2×60.1) = 8.32 Hz`.** A rate pinned at the sampler's own Nyquist is the signature of an
aliased reading, not of a measured period — the instrument saturated.

Cross-check that the arithmetic is self-consistent: at a 60.1 ms poll on a loop of ~176 ms the
host takes ~2.9 samples per loop, i.e. ~1.94 adjacent-sample comparisons. With the stage
durations measured in §6a below (sync 25.4, class 32.9, qual 7.8, cam 69.1, panel 1.1, tail 8.3
ms) the chance that two samples 60 ms apart land in *different* stages is ≈0.70, giving
≈**1.36** observed transitions per loop — against **1.48** actually observed. The 119.0 ms
reading is consistent with a ~176 ms loop. **It does not contradict definition A; it agrees
with it, once the word's meaning is read out of the code.**

### 2.3 The defect that is independent of the word's meaning

The script's `after 20` sets a nominal 20 ms poll, but 200 iterations took 12,024 ms because each
iteration performs `mrd` calls whose JTAG latency dominates — an actual ~60 ms poll. A 60 ms
sampler cannot resolve a 176 ms periodic signal containing seven shorter stages. Even if
`MB_PROGRESS` had been a loop counter, the counting would have missed transitions.

---

## 3. The instrument of record

**`MB_T_TOTAL / MB_T_N`, converted with `333,415.5` ticks/ms.**

Reasons, in order of weight:

1. **It is inside the loop it measures.** The two endpoints are the same point of the same code
   (`tH` to `tH`), so every phase is covered exactly once and no host latency, no scheduling and
   no sampling enters the number.
2. **It carries an in-band consistency check.** The seven phase sums cover `tA..tH`; the total
   covers `tH(previous)..tH(now)`; therefore
   `total − Σ(phases) = tA − tH(previous)` = the loop head, a few instructions and **not zero**.
   Across every window collected today that residual was **2,257-2,689 ticks = 0.0002 ms per
   loop of a ~145-227 ms loop (0.0001%-0.0002%)**, as §6a reports. A mis-wired accumulator or a
   double-counted phase would break that equality. It did not.
3. **Its window is exactly 32 consecutive iterations performed by the firmware**, so there is no
   aliasing: `MB_T_N = 32` was checked on every window used below, and windows published early
   by the overflow guard (`g_sum_total > 3e9`) were rejected.
4. **It is the instrument the catalogue value came from** (`159.12 / 176.60 / 177.50`),
   so before/after stays comparable with what is already in the record.

### 3.1 Instruments rejected, with the reason

| Instrument | Verdict | Reason |
|---|---|---|
| `PROGRESS` transition counting | **rejected** | counts stage changes of a 7-valued beacon (§2); sampled at its own Nyquist limit; the calibration factor depends on the quantity being measured |
| `MB_FPSX10` (word 7) | **rejected as a rate** | it is a ~1 s snapshot: `(frames since last update) × 10` over ≥334,800,000 ticks (`main.c:15475-15488`). It must divide by the same possibly-wrong tick constant, and its 1 s window is shorter than the loop's own wander. Read **110** (11.0 fps) at 12:34 and **40** (4.0 fps) at 13:07 — a 2.75× swing in 33 minutes while the frame counter over 60 s gave 5.61 and 5.95 loops/s. It is a panel display, not a rate of record. |
| frame-count integration (`MB_PS_FRAMES` over a host interval) | **kept as the independent cross-check, not as the number of record** | it needs no timer constant at all, which is exactly why it is useful: it agreed with definition A to 1.8% today (172.7-173.8 ms vs a 170.8 ms window mean). It cannot be the record because the host interval includes JTAG latency and because it says nothing about *which phase* changed. |

---

## 4. Validation of the instrument (four checks, all before use)

### 4.1 The tick rate — the constant was wrong, and it is now measured

Every ms figure in this project is `ticks / 334800`. `main.c:15450` calls that constant
"334.8 MHz on this configuration" and `main.c:10162` says the host recovers the rate from
ticks × fps "avoiding hard-coding a frequency that would then be quoted as fact" — but
`334800` is hard-coded in the conversions. So it was measured by **counting wraps**: the
timer's low word was sampled 31 times over ~61 s and each decrease counted as one wrap of 2³².

```
timer = 3115759190 ticks in 60866 ms = 333.448 MHz   (measure_loop_cal.log)
timer = 3152513576 ticks in 60988 ms = 333.383 MHz   (measure_loop_before2.log)
```

Two independent calibrations, 0.019% apart: **333,415.5 ticks/ms.** The code's 334,800 is
**0.415% high**, so every published millisecond figure is 0.415% **low** (176.60 published is
177.33 actual). This is small, and it cancels in any before/after comparison because both sides
use the same constant — but it is now a measured number instead of an assumption, and the
answer to "why did two different calibrations give 332.0 and 47.1 MHz earlier today" is
respectively *JTAG latency on a 10 s interval* and *a 60 s interval folding four wraps of a
32-bit counter*. Both of those were my errors, not the firmware's.

### 4.2 The firmware proves the timer counts

`MB_TIMER_OK = 1` and `GTIMER_CTL = 0x00000001` on every run. `timer_start()`
(`main.c:10167-10179`) only sets that word after observing the counter move; a dead timer reads
zero forever, and a report made of zeros is not a measurement.

### 4.3 Does the observer perturb the loop?

The brief's warning about the cacheable A9 debug path made this worth checking. `MB_PS_FRAMES`
was read across a 60 s quiet interval (4 reads total) and across a 60 s interval polled at ~29
`mrd`/s:

```
QUIET:                                    5.6109 loops/s = 178.23 ms/loop
polled hard (11 words x 160 polls):       6.7490 loops/s = 148.17 ms/loop
```

Polling did **not** slow the loop — the hard-polled interval was *faster*, which rules out
observer-induced slowdown as the explanation for anything below. It does **not** mean polling is
harmless: it means the loop's own drift (see §5) is larger than the perturbation, so the
perturbation cannot be separated by this design. The window collection therefore polls only
words 79 and 76, twice each, every 150-250 ms — 4-8 reads/s, an order of magnitude lighter.

### 4.4 Two independent counters of loop iterations agree

`MB_PS_FRAMES` (word 10, `++frames` at `main.c:15501`) and `MB_TEAR_SELN` (word 379, the tear
check's denominator) are incremented by different code and read **53217 and 53217** at the same
instant. A counter that was double-incrementing or stalling would not track a second one
exactly. (An earlier run showed 51008 / 51009 — off by one, i.e. a read straddling a single
loop.)

> One methodological note, because it cost a wrong intermediate conclusion: comparing
> "loops implied by the window accumulators" against "ΔMB_PS_FRAMES" over a span always shows
> the windows covering **one extra window's worth (~32 loops, ~11%)**, because the first
> window collected begins before the span's start. Corrected for that boundary the two agree —
> 320 loops of window content minus one 32-loop boundary window ≈ 284-288, against 284 frames
> actually counted. I record this because the uncorrected ratio (1.1268) appeared twice and
> looks like a systematic firmware fault; it is not one.

---

## 5. The noise floor of the unmodified build

Ten consecutive 32-loop windows, twice, 41 minutes apart, same build, same session, same
instrument. `MB_T_N = 32` on every window.

### Batch 1 (`measure_loop_cal.log`)

| | |
|---|---|
| windows | 139.63, 161.99, 171.38, 171.77, 160.77, 166.21, 172.09, 187.47, 200.05, 126.28 ms |
| **mean** | **165.77 ms** |
| **min** | **126.28 ms** |
| **max** | **200.05 ms** |
| **spread (max−min)/min** | **58.42 %** |
| sd | 21.18 ms (12.8 % of the mean) |

### Batch 2 (`measure_loop_before2.log`)

| | |
|---|---|
| windows | 144.08, 178.22, 183.84, 226.37, 171.76, 149.49, 166.16, 160.70, 166.45, 160.62 ms |
| **mean** | **170.77 ms** |
| **min** | **144.08 ms** |
| **max** | **226.37 ms** |
| **spread (max−min)/min** | **57.11 %** |
| sd | 22.92 ms (13.4 % of the mean) |

**The floor reproduces**: the two batches' spreads are 58.42 % and 57.11 %, their sds 21.18 and
22.92 ms, and their means differ by 5.00 ms (3.0 %).

### Pooled, n = 20

| | |
|---|---|
| **mean** | **168.27 ms** |
| **min** | **126.28 ms** |
| **max** | **226.37 ms** |
| **spread over the 20 consecutive windows** | **79.25 %** (the two batches sit at 58 % and 57 % internally) |
| sd | **21.63 ms = 12.85 % of the mean** |
| lag-1 autocorrelation | +0.175 (windows are close to independent, so n-window means converge as 1/√n) |
| correlation with `MB_CAP_PERIOD` | +0.792 |

### 5.1 The answer to the question the brief asks

**The noise floor is 12.85 % (sd) / 57-58 % (range of ten consecutive windows).
The block's ceiling is 7.9-8.5 % of the loop. The noise floor is larger — 1.6× the effect in
sd, 7× in range — and the answer to "is it larger than 7.9 %" is therefore an unambiguous
**yes**. And worse than a single number: the *mean* of ten windows moved 144.6 → 165.8 → 170.8
ms across three measurement batches on one unmodified build, an 18 % swing with no build change.

Two further facts about the floor matter for what follows:

* **It is not stationary.** Today's sd (21.6 ms) is **2.09×** the sd of the three catalogue
  windows (10.36 ms). A floor measured today does not bound tomorrow's.
* **MB_CAP_PERIOD tracks the loop** (r = +0.79) and moved 90.6-231.1 ms during the runs. The
  loop is at least partly paced by the capture handover, and `sync` — the wait in
  `cam_bracket_sync()`, `main.c:944-991` — is a real 25.4 ms per loop.

---

## 6a. The phase decomposition: the total is the wrong statistic

The block cannot shorten the loop uniformly; it can only remove work from **one** phase.
`avg_sample()` is called at `main.c:14897`, which is between `tD = 14708` and `tE = 15208` — that
is, inside the `cam` phase. `part_track()` is at `main.c:14547`, between `tB = 14326` and
`tC = 14550` — inside `class`. So the firmware's own seven accumulators attribute work to the
right phase, and the block's effect has one place to appear.

20 consecutive windows with the full phase vector (`measure_phase_before.log`):

| phase | mean | sd | sd % | corr with total | share of the total's variance |
|---|---|---|---|---|---|
| sync | 25.40 | 4.74 | 18.67 % | +0.980 | 96.0 % |
| **class** | **32.93** | **12.52** | **38.03 %** | **+0.995** | **99.1 %** |
| qual | 7.78 | 0.21 | 2.72 % | −0.642 | 41.2 % |
| **cam** | **69.14** | **1.20** | **1.74 %** | −0.590 | 34.8 % |
| panel | 1.05 | 0.06 | 5.97 % | −0.057 | 0.3 % |
| tail | 8.29 | 0.17 | 2.00 % | −0.606 | 36.7 % |
| pub | 0.00 | 0.00 | — | +0.125 | 1.6 % |
| **total** | **144.59** | **16.16** | **11.18 %** | | |
| loop-head residual | 0.0002 | | | | |

**The only phase the block can move, `cam`, is the most stable phase in the loop (1.74 %).**
The total's variance is dominated by `class`, which swings in regimes — 12.0, 36 and 58.7 ms per
loop across these windows, a 5× change in a phase the block cannot touch. Comparing loop totals
therefore compares a 14 ms effect against the motion of a phase that is 4× noisier and 5×
larger than the effect.

Consequence, computed from the same 20 windows:

| windows per arm | resolution on the **total** (2σ, two means) | resolution on **cam** |
|---|---|---|
| 6 | 18.66 ms | **1.39 ms** |
| 10 | 14.46 ms | 1.07 ms |
| 20 | 10.22 ms | 0.76 ms |
| 40 | 7.23 ms | 0.54 ms |

**A 14 ms change in `cam` is a ~10σ event at six windows per arm. The same 14 ms change in the
total is 0.75× the resolution at six windows per arm — invisible.**

This is an *inference from a standard deviation*, and a standard deviation is a model. It was
therefore tested against a known answer, below.

---

## 6b. The known-answer test: an A/B/A on the live station

An inference from `sd` needs a control, or it is just a different way of guessing. There is a
host-written switch that removes a **known** cost from a **different** phase than the one the
block targets, so it can validate both halves of the argument at once.

* `MB_PART_TK_ON` (word 512) = 0 disables the per-loop part-mask pass.
* `part_track()` is called at `main.c:14547` — between `tB = 14326` and `tC = 14550` — so its
  cost is in **`class`**.
* The firmware publishes that cost itself: `MB_PART_TK_MS` (word 513) read **4.87 ms/loop** at
  the start of this test.
* `avg_sample()` is at `main.c:14897` — between `tD = 14708` and `tE = 15208` — so the cost the
  block would remove is in **`cam`**.

**Prediction, written before the run:** switching it off must move `class` and must **not** move
`cam`. An A/B/A (on, off, on) gives the A/A control: the difference between the two arms with
the *same* setting is what any between-arm comparison can resolve, measured rather than assumed.

**Result** (22 windows, 7-8 per arm, `measure_phase` protocol, boundary duplicates dropped):

| arm | n | total | sync | **class** | qual | **cam** | panel | tail |
|---|---|---|---|---|---|---|---|---|
| A1 (switch on) | 8 | 162.81 | 30.88 | **46.77** | 7.72 | **68.17** | 1.06 | 8.22 |
| B (switch off) | 7 | 148.78 | 28.25 | **34.43** | 7.71 | **69.03** | 1.06 | 8.30 |
| A2 (switch on) | 7 | 152.81 | 27.58 | **38.93** | 7.86 | **69.02** | 1.05 | 8.38 |
| A/B effect | | +14.04 | | +12.34 | | **−0.85** | | |
| **A/A control** | | **+10.00** | | **+7.84** | | **−0.84** | | |

(the switch was restored to 1 and the restore verified twice: word 512 read back as 1, and
`MB_PART_TK_N` resumed advancing, 54881 → 54885 → 55105.)

**What it establishes:**

1. **`cam` is specific.** Removing a `class` cost of 4.87 ms/loop left `cam` at 68.17 / 69.03 /
   69.02 — a maximum arm-to-arm difference of **0.84 ms**, while `cam`'s within-arm sd is
   0.32-1.00 ms. A change confined to another phase does not leak into `cam`. That is what makes
   `MB_T_CAM` usable as the primary statistic: it measures one phase and not the loop.
2. **The total is not resolvable at this sample size — measured, not estimated.** The two arms
   with the *same* setting (A1 and A2) differ by **10.00 ms**. That is the resolution of a
   between-arm total comparison at 7-8 windows per arm, and it is **71 % of the block's 14.0 ms
   ceiling**. The known 4.87 ms change cannot be seen through it, and the observed A/B
   difference (14.04 ms) is 2.9× the change actually made — which is the signature of drift
   dominating the arms, not of a measured effect.
3. **`class` regime-switches and that is what breaks the total.** Within-arm sd of `class` was
   11.96 / 9.34 / 15.55 ms — larger than the cost the switch removes. The A/A control on
   `class` (7.84 ms) is itself bigger than the 4.87 ms effect. Any statistic containing `class`
   inherits that.

So the argument for changing the statistic does not rest on a variance model: it rests on a
control where a known change was applied, the phase it belonged to moved as far as the noise
allowed, the phase the block targets did not move at all, and the two identical arms differed
by more than the change itself.

---

## 6. Pre-registration for step 2 — written before step 2 was attempted

**Instrument.** `MB_T_TOTAL / MB_T_N` and the seven phase sums, from consecutive 32-loop
windows with `MB_T_N = 32`, converted at **333,415.5 ticks/ms**, with the loop-head residual
checked to be in `[0, 100000]` ticks.

**Primary statistic: `MB_T_CAM` (word 73) ÷ `MB_T_N`.** This is the phase that contains
`avg_sample()` and the only phase the block can change.

**Secondary statistic: `MB_T_TOTAL` (word 76) ÷ `MB_T_N`.** This is whether the loop got faster.

**Control group: `class + qual + panel + tail + pub`.** The block does not touch these. They are
measured in the same window as `cam`, so if they move with `cam` the measurement is broken by
common-mode drift and nothing may be claimed from that run.

**Sample size.**
* `cam`: **≥ 6 consecutive 32-loop windows per arm** (resolution 1.39 ms against a 14.0 ms
  ceiling).
* `total`: **≥ 40 consecutive 32-loop windows per arm** (resolution 7.23 ms). Six is
  *pre-registered as insufficient* for the total, and a total measured on six windows will not
  be reported as evidence either way.

**Ordering.** Before and after must be taken with the same poll pattern (4-8 `mrd`/s, words 76
and 79 twice), the same window count, and the same arm structure. Because a flash reboots the PS
and destroys the DDR reference and the pinned exposure, a before/after cannot share a boot; the
**A/B/A structure must therefore be repeated identically on each build** so that a between-boot
shift can be distinguished from the effect. `MB_EXPOSURE` must be re-pinned to 8698 and the
background re-captured before any "after" window is taken, and any verdict numbers so obtained
belong to a **new reference** and must not be compared with the 909 table.

**Decision rule, fixed now.**

| Result | What will be reported |
|---|---|
| `cam` drops by ≥ 2σ (≥ 2.8 ms) and the control group does not move | "the PS stopped paying for the sampling pass; the saving is X ms/loop of `cam`" |
| `cam` drops but the total does not (inside the 40-window resolution) | **"the compute saving is real and the loop did not get faster"** — an absorbed saving, reported as such, not as an improvement |
| `cam` does not move | the block is not being used by the PS; a wiring or gate bug, not a performance result |
| the control group moves with `cam` | the run is invalid; no claim |
| total difference inside the noise floor | **"the difference is inside the 12.85 % noise floor"** and the mean difference is not reported as an improvement |

**What is *not* claimable even if everything works.** The ceiling is 14.0 ms = 8.3 % of a
168.27 ms mean. It cannot be described as a throughput gain of more than 8.3 %, and if `sync`
absorbs it, the throughput gain is 0.

---

## 7. Is step 2 worth doing? — the verdict

**Not with the measurement the brief specifies. Yes, with the measurement above.**

The reasoning, in the order it became measured rather than argued:

1. **The total cannot resolve the effect at six windows per arm.** Resolution 18.66 ms against a
   14.0 ms ceiling: the effect would have to be 1.33× its own maximum to be visible. And the
   A/B/A control in §6b put a *measured* number on this: two arms with the same setting differed
   by **10.00 ms**, 71 % of the ceiling and more than twice the 4.87 ms change the switch
   actually made. The expected outcome of a six-window before/after is the sentence *"inside the
   noise"* — which is honest, but it is produced by the sample size, not by the hardware, and
   spending a flash (which costs hours of reference re-capture) to buy that sentence is a bad
   trade.
2. **The total is the wrong statistic**, because its variance lives in `class` (sd 12.52 ms,
   5× the effect, in a phase the block cannot touch), while the phase the block does move is
   the most stable one in the loop (sd 1.20 ms). Changing the statistic changes the resolution
   from 18.66 ms to **1.39 ms at the same six windows**. That is not a trick — it is asking the
   question the block actually answers: *does the PS still pay for the sampling pass?*
3. **The loop may genuinely not get faster**, and that is a result the brief asks for. `sync`
   is 25.4 ms of explicit waiting for the capture handover; if the render finishes sooner, the
   wait grows. So the pre-registration deliberately separates "the PS stopped paying" from "the
   loop got faster", because they are different claims and only the first is near-certain to be
   measurable.
4. **The between-boot problem is the remaining risk.** A flash reboots the PS, so before and
   after cannot share a boot, and the *mean* of ten windows already moved 18 % between two
   batches on the *same* build. An interleaved A/B within one boot would remove this entirely,
   which is why **the integration should include a runtime bypass bit** (a register that selects
   "use the PL statistics" vs "run the PS pass"), so the A/B becomes a register write rather
   than a flash. That bit costs one AXI-Lite register bit and is the single design change that
   most improves the measurability of the result.

**So: the flash is worth spending only if (a) the primary statistic is `cam`, (b) the sample is
≥ 6 windows per arm for `cam` and ≥ 40 for the total, and (c) both arms repeat an identical
A/B/A structure on each build. If the brief's "six windows, compare the total" is kept, the
answer is already known and does not need a flash: the difference will be inside the noise.**

---

## 8. The integration interface — decision and its cost

**Decision: an HP-port master (Path A), reading the store the PS names, with a frame-identity
word written alongside the statistics, and a runtime bypass bit.**

### Why, and what it costs in the interconnect

The design facts, from `dl/pl_frontend/REPORT.md` §6 (a parse of `design_1.bd`): `S_AXI_HP0`
and `HP1` are both in use; **`PCW_USE_S_AXI_HP2` = 0 and `HP3` = 0, so both are free**; HP data
widths are 64 bits; `FCLK_CLK0` = 50.000000 MHz; `M_AXI_GP0` in use, `GP1` free.

Cost: one PS7 parameter (`PCW_USE_S_AXI_HP2 0→1`, plus `S_AXI_HP2_ACLK`) — no pin, no XDC; one
AXI4 read master and one AXI4 write master in RTL (the write side is 46,800 B of statistics per
frame); one AXI4-Lite control slave for the frame base address, the identity word and the bypass
bit; clock and reset taken from the **same `proc_sys_reset` domain as the HP port's `ACLK`**
(a reset from another domain is `[BD 41-1343]`). The alternative — a second master on the
existing HP interconnect via `smartconnect` — avoids the PS7 parameter but adds an interconnect
port; the PS7 parameter is the smaller change.

### Why not the VDMA stream tap (Path B)

Three reasons, all from the software rather than the hardware:

1. The PS compares a **store it selects**, out of a four-store rotation. A tap produces
   statistics for the frame *being captured*, which is a different picture whenever the belt moves.
2. `avg_sample()` will only accumulate a frame whose `MB_READY` it just checked and whose tear
   verdict it just took (`main.c:4334-4344`). A tap's statistics arrive at capture time, before
   that gate is evaluated, so **both gates would be silently bypassed**.
3. Since both paths need the identity word anyway, the tap saves address logic and buys nothing
   on the hard part. Path A additionally can be pointed at a *reference* frame later
   (`ref_mean_build()`, `main.c:3522`), which a tap cannot.

### The frame-identity hazard — **not implemented, and here is exactly what it needs**

The brief asks me to add a frame-identity word and a PS-side check, **or state plainly that the
integration would need one and that I did not implement it.**

**I did not implement it. The integration was not performed**, so nothing was added to the PS
side. Stating the requirement precisely, because it is the condition under which the integration
is correct at all:

* The PL must write, atomically with each statistics block, a **32-bit identity** =
  `(capture handover count, store index)` sampled at the instant the block began reading that
  store — not the identity at the instant it finished.
* The PS must compare it against the `(MB_READY, tear verdict, store index)` triple it used to
  approve the frame, and **discard the statistics if it does not match**. Discarding must fall
  back to the PS pass, not to a stale block.
* Without this, a PL block that is one frame behind publishes a mean of a frame the gate never
  saw, and the readiness and tear gates are bypassed *silently* — the verdict would still read
  PASS while the averaging had quietly begun including torn frames. That is a correctness change
  in `main.c`'s gating, not a read-path change, and it is a decision for whoever owns the PS side.

---

## 9. What remains unverified

| Item | State |
|---|---|
| Routed WNS with the block in the design | **not measured** — needs a full synth+impl (~25-40 min) |
| Whether the block's +1,863 LUT places without losing timing | **not measured** (1.25 free LUT/slice) |
| Whether `cam` actually drops by 14 ms | **not measured** — needs the integrated build |
| Whether a `cam` saving passes through to the total | **not measured**; `sync` = 25.4 ms of waiting makes absorption plausible |
| Whether the block's statistics are ever applied to the frame the gate approved | **not addressed** — see §8 |
| The 41-board verdicts with the block | **not checked** — needs a flash |
| DDR contention from ~125 MB/s of HP reads | **not measured** |
| Why `class` swings 12 → 36 → 59 ms/loop | **not explained**; it dominates the total's variance and is the reason the total is unusable. Worth its own investigation before any loop-time claim. |
| The exact cause of the `MB_FPSX10` 2.75× swing | **not resolved**, and not needed: it is rejected as a rate |

---

## 10. The one-paragraph version

The 119.0 ms figure was not a measurement of the loop: it counted changes of a seven-valued
*stage beacon* (`main.c:12564-12581`, written seven times per loop) and divided by them, at a
poll rate within 1 % of its own Nyquist limit, so its answer is a function of the loop period it
was trying to measure. `MB_T_TOTAL / MB_T_N` is the instrument of record, and it is now
calibrated (333,415.5 ticks/ms, measured by wrap counting, against the code's 334,800 — every
published ms is 0.415 % low) and checked in band (the seven phase sums reconcile with the total
to 0.0002 ms of a ~145 ms loop). On that instrument the unmodified build's noise floor, over
**20 consecutive 32-loop windows in two batches 41 minutes apart, is mean 168.27 ms, min 126.28,
max 226.37, spread 79.25 % pooled (58.42 % and 57.11 % within the two batches), sd 21.63 ms =
12.85 %** — larger than the block's 7.9 % ceiling in every way it can be stated, and the *mean*
of ten windows moved 18 % between batches with no build change. Six windows per arm on the loop
total resolves 18.66 ms against a 14.0 ms ceiling, so the specified measurement would return
"inside the noise" regardless of the hardware. But the loop total is the wrong statistic: the
block can only shorten `cam` (`avg_sample()` at `main.c:14897`), and `cam` is the most stable
phase in the loop at **69.14 ± 1.20 ms** (sd 1.74 %), while the total's variance is
`class` (sd 12.52 ms, a phase the block cannot touch). At the same six windows per arm, `cam`
resolves **1.39 ms**, so a 14 ms saving there is a ~10σ event. That was then tested against a
known answer rather than left as an inference: disabling the per-loop part-mask pass (a
documented 4.87 ms/loop in `class`) left `cam` at 68.17 / 69.03 / 69.02 ms across an A/B/A — a
0.84 ms arm-to-arm difference — while the two arms with the *same* setting differed by
**10.00 ms on the loop total**, 71 % of the ceiling and 2.9× the change actually made.
**Step 2 is therefore worth doing only if the claim is restated from "the loop got faster" to
"the PS stopped paying for the sampling pass", the sample is ≥ 6 windows per arm for `cam` and
≥ 40 for the total, the untouched phases are carried as a control group, and the integration
includes a runtime bypass bit so the A/B is a register write rather than a flash.** The flash
was not spent in this session, and the block design was not modified: no step-2 build was
attempted.
