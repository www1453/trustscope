# Report addendum, 2026-10-28 — two numbers to correct, one explanation to replace

**Purpose.** Two figures the submission currently carries are wrong, and one explanation it
does not carry should be added. This document states each correction with the measurement
behind it, in a form the report pass can lift directly. **I have not edited the report.**

A one-paragraph summary for the report pass is at the end (§5).

---

## 1. Correction: the averaging ceiling is 11.2 %, not 7.9 %

**As currently written:** the block can replace at most **14.0 ms of the 176.6 ms loop =
7.9 %**, derived as (28.0-29.4 ms per pass − 1.4 ms read) × 8 passes per 16 loops.

**What is wrong:** the per-call cost. The source figure was
`MB_AVG_TICKS` **9.37-14.7 M ticks = 28.0-44.1 ms**, and the derivation used the bottom of
that range (28.0-29.4 ms). Measured across 20 consecutive windows on 2026-10-28, sampled per
window:

| | |
|---|---|
| `MB_AVG_TICKS` per call | **mean 39.00 ms**, min 29.61, max 47.80 |
| calls per loop | 0.5 (`DIFF_EVERY` 16, `AVG_N` 8 → 8 calls per 16 loops) |
| **what the PS pays per loop** | **0.5 × 39.00 = 19.5 ms** |
| what the replacement read costs | ~1.4 ms per call ≈ 0.7 ms per loop |
| **ceiling** | **~18.8 ms per loop** |

**Express it in milliseconds first, because the percentage moves with the batch.** The loop
mean is not a constant on this station: it measured **170.8**, **165.8** and **141.3 ms** in
three consecutive 20/10-window batches on the same build. So the same 18.8 ms is **11.2 %** of
the pooled 168.27 ms and **13.3 %** of the 141.3 ms batch. Quoting one percentage invites the
question "of which window?", and the answer changes the figure by two points. Quote
**~18.8 ms/loop (11-13 % depending on the batch)**.

Two secondary corrections that follow from the same work:

* the loop mean is **168.27 ms** across the two dedicated noise-floor batches (20 windows, sd
  21.63 ms), not 176.6 ms — the 176.6 was one window of a different session;
* the tick constant used to convert any of these is **333,415 ticks/ms**, not 334,800, so
  every published millisecond figure is 0.415 % low. It cancels in a before/after.

**Why this matters rather than being a rounding argument:** 7.9 % reads as "smaller than the
noise, so it cannot be measured". 11-13 % is still below the measured 12.85 % sd of the loop
total — so the conclusion about the *total* does not change — but the honest framing is
different and stronger: **the block is worth more than the report claims, and the reason the
claim had to move to the `cam` phase is the composition of the noise, not the size of the
prize.**

**Reference for the corrected chapter:** `dl/PL_INTEGRATION_20261028.md` §9, and
`dl/LOOP_MEASURE_20261028_step1.md` §5-6.

---

## 2. Explanation: what `class` is — and it is not what I first proposed

The submission describes `class` as "publish + cache invalidate + classify + bright counts,
includes `part_track`" and gives it 58.4-59.9 ms. Measured over 20 consecutive 32-loop windows
it is **30.82 ms mean, 11.29 min, 58.74 max, sd 13.53** — three regimes, and the phase that
dominates the loop total's variance.

**My first hypothesis is refuted and should not be reported.** I proposed that `class` moves
because `part_track()` switches between the background rule (4 reads/cell) and the old green
fallback (12 reads/cell, `main.c:4918-4921`). Measured:

* `MB_PART_RULE = 1`, `MB_PART_BGWHY = 0`, `MB_BG_STATE = 1` in **all 20 windows** — the rule
  never switched;
* `MB_PART_TK_MS` moved only **4.86 → 9.93 ms**, which cannot explain a 47 ms swing.

**What the code says is in `class`** (between `tB = main.c:14326` and `tC = main.c:14550`):

| Code | Cost | Verdict |
|---|---|---|
| `dcache_invalidate(store, CAM_BYTES)` at 14504 — 2,764,800 B | < 1 ms at a few cycles per line | **not the answer** |
| **`cam_mean_green(g_long_buf)`** at 14514 | **two independent full-frame passes over all 921,600 source pixels** — ~27.6 ms each at ~30 ns per uncached read, **~55 ms the pair** | **matches the 58.74 ms high regime** |
| **`cam_bright_count(g_long_buf)`** at 14517 | (as above) | (as above) |
| `part_track(g_long_buf)` at 14546 | 4.9-9.9 ms, measured by the firmware itself | too small |

**The explanatory signature, measured:** `corr(class, sync) = **+0.952**`. `class` moves *with*
`sync`, not against it. In a frame-paced loop a longer compute would normally be *absorbed* by a
shorter wait; that the wait grows too is the signature of a loop that must fit a **whole number
of capture frames**, so more compute pushes it across a frame boundary and both terms rise
together.

**Labelled as a hypothesis, because the separating test has not been run:** the most probable
mechanism for the 12 → 36 → 59 ms regimes is **the cache state those two full-frame passes
see after the `dcache_invalidate` at 14504** — resident ⇒ ~12 ms, cold ⇒ ~59 ms. This is
*consistent with every number above* and it is **not proven**. The test that would settle it is
six lines of firmware on the existing `GTIMER` pattern, timing `cam_mean_green` and
`cam_bright_count` separately into two spare mailbox words (573, 574), and one build.

**Why the report should carry it at all:** it names a cost larger than the one the block was
built to remove. **`class` contains two full-frame passes worth up to ~55 ms between them —
roughly three times the 19.5 ms averaging pass.** If the datapath is integrated, the same
identity and tear argument applies to them, and that is the larger prize.

**Reference:** `dl/STEP2_20261028_stopped_before_bd.md` §5;
`dl/class_regime_windows_20261028.csv` (the 20 raw windows).

---

## 3. The phase table to use, replacing the three-window one

The submission's phase table comes from three windows of one session. This one is **20
consecutive windows on the same build, and every row including the total comes from that same
20-window set** (`dl/class_regime_windows_20261028.csv`), so the column adds up:

| phase | mean ms | min | max | sd | sd % | corr with total |
|---|---|---|---|---|---|---|
| **cam** (contains `avg_sample`) | **69.90** | 66.13 | 74.64 | **1.50** | **2.1 %** | −0.303 |
| class | 30.82 | 11.29 | 58.74 | 13.53 | 43.9 % | +0.997 |
| sync | 23.33 | 16.07 | 35.96 | 5.02 | 21.5 % | +0.958 |
| tail | 8.37 | 8.07 | 8.77 | 0.19 | 2.3 % | −0.051 |
| qual | 7.82 | 7.41 | 8.24 | 0.19 | 2.4 % | −0.400 |
| panel | 1.05 | 1.02 | 1.25 | 0.06 | 5.7 % | −0.134 |
| **total** | **141.29** | 115.33 | 177.53 | 17.75 | 12.6 % | — |

**Note the total's mean is 141.29 ms here and 168.27 ms in the noise-floor batches.** That is
not an error: it is the same instability this document is about, and it is why the ceiling
should be quoted in milliseconds (§1). A phase table from any single batch must state its own
total, and this one does.

The single fact worth carrying: **the phase the block can move (`cam`) is the most stable phase
in the loop (2.1 %) and does not track the total at all (r = −0.30), while the total's variance
lives in `class` (43.9 %, r = +0.997), which the block cannot touch.** That is why the claim
belongs on `cam`.

---

## 4. Numbers that should *not* change

For the avoidance of doubt, none of these are affected by the corrections above:

* the block: **1,863 LUT** (1,125 logic + 738 LUTRAM), **571 FF, 0 BRAM, 0 DSP**;
* **46,800 of 46,800** values bit-identical on a real frame, two corrupted inputs rejected;
* the noise floor: **mean 168.27, min 126.28, max 226.37 ms, spread 79.25 %, sd 21.63 = 12.85 %**
  (pre-registered over 20 windows, two batches);
* the loop total is **not** a statistic that can carry a sub-12 % claim at six windows per arm
  (resolution 18.66 ms); `cam` is (resolution 1.39 ms);
* the measured phases sum to the total to **0.0002 ms** of a ~145 ms loop — the in-band check
  that says the decomposition is sound.

---

## 5. One paragraph for the report pass

> Two figures in the current text should be corrected, and both move in the project's favour.
> The block's ceiling is not 14.0 ms / 7.9 %: `MB_AVG_TICKS` measures the averaging pass it
> replaces at **39.00 ms per call** over 20 windows (range 29.61-47.80), and at 8 calls per 16
> loops the PS pays **19.5 ms per loop** in it, so replacing the 936,000 scattered reads with a
> 46,800-byte statistics read leaves the block's ceiling at **~18.8 ms per loop** — 11-13 % of
> the loop depending on which batch, and it should be quoted in milliseconds because the loop
> mean itself moved between 141.3 and 170.8 ms across three batches on one build.
> Second, `class` is not adequately explained by "publish + cache invalidate + classify"; it
> swings **11.29 to 58.74 ms** (sd 13.53) and dominates the loop's variance, and the time inside
> it is dominated by **two independent full-frame passes** — `cam_mean_green` (`main.c:14514`)
> and `cam_bright_count` (`main.c:14517`) — each over all 921,600 source pixels, ~27.6 ms apiece
> by inference and ~55 ms the pair, which matches the 58.74 ms high regime; `corr(class, sync) =
> +0.952`, the signature of a loop that must fit a whole number of capture frames. The mechanism
> — cache residency after the `dcache_invalidate` at `main.c:14504` — remains a **hypothesis**,
> because the separating test (timing those two passes separately) has not been run. Neither
> correction changes the block's own numbers: 1,863 LUT, 571 FF, no BRAM, no DSP, 46,800 of
> 46,800 values bit-identical on a real frame.
