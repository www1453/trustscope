# The tear bracket, measured: 88.0 ms, not the 22.6 ms that was inferred

**Date:** 2026-10-28 (PL front-end, day 1 of 3)
**Question this answers:** `dl/PL_INTEGRATION_20261028.md` §6 carried the interval between
the store selection and `tear_sig_compare()` as **~22.6 ms, "inferred from line counts and
never measured"**, and said the whole integration rests on it. Does the PL front end's
**18.43 ms** read fit inside it?

**Answer:** yes, with about **4.8x margin**. The measured bracket is **88.0 ms minimum,
100.5 ms maximum, 90.4 ms mean**. The inference was wrong, and wrong in the safe direction.

---

## 1. What was measured, and where the two ends are in the code

The bracket is the interval the **tear gate already covers**. Two `GTIMER` reads were added
and their difference published (`MB_T_BRK`, word **576**; `MB_T_BRKN`, word **577**, counts
how many times it has been published).

**The words were renumbered, and the reason is a defect the integration note carried.** The
note reserved word **572** for `MB_PLFE_ON` and established that 572-600 were free by
scanning every `#define MB_*` in `ps_ui/main.c`. That check covers ONE namespace.
`dl/host_qc/qc_mailbox.py` already declares **572 = `eg_margin`, 573 = `eg_roi`,
574 = `ref_avg`** (the stage-L line, which this firmware does not implement). Writing tick
counts to 573/574 would have made `accept_range.py` print them as "cells the range statistic
judged" and "frames the reference mask is a mean of" -- garbage in a diagnostic, presented
authoritatively. All six PL-front-end words now live at **575-579 and 582**, which
`dl/mb_free.py` and the host map both call free, and `python dl/host_qc/check_words.py`
passes with them declared.

| end | `ps_ui/main.c` | what happens there |
|---|---|---|
| start | immediately after `tear_sig_capture(g_long_buf);` | the store has just been named (`g_long_buf = cam0_stores[g_cap_sel]`) and invalidated — this is the moment the PL would be triggered |
| end | immediately before `tear_sig_compare(g_long_buf);` | the tear gate closes; a read still in flight after this point is **outside** the gate |

The start is guarded by `g_brk_ok`, so a `continue` between the two ends cannot publish a
stale interval, and `MB_T_BRKN` lets a reader tell a live number from a stale one.

## 2. The number

40 samples, 120 ms apart, single-exposure mode, firmware `TSC1 4711380A`:

| | ticks | ms (ticks / 334800) |
|---|---|---|
| min | 29,438,326 | **87.93** |
| max | 33,647,448 | **100.50** |
| mean | 30,997,345 | **92.59** |

A second run 10 minutes later, 48 loops, gave a mean of **90.43 ms** (30,276,490 ticks).
The bracket is therefore **88-100 ms**, and it did not move between runs.

## 3. Was the instrument checked against a known answer?

Yes, and this matters because the number that came out is 4x the inference.

* `MB_TIMER_OK` (word 77) reads **1**: the firmware's own check that the timer was seen
  counting, not that it was assumed to be.
* `MB_T_TOTAL` (word 76) / `MB_T_N` (word 79) are the **32-loop accumulated** phase sums.
  `2838012313 / 32 / 334800` = **264.90 ms per loop**.
* The **wall clock** counted **22 loops in 6090 ms** = **276.82 ms per loop**.

Two independent measurements of the same loop period agree to **4.3 %**, with the loop's own
spread measured at 79 % pooled in this project's own pre-registration. The readout path
(GTIMER → mailbox word → JTAG → host) is therefore live and correctly scaled.

**One thing this does NOT validate:** the tick *constant*. The project divides by 334800
ticks/ms; the measured rate is 333.448 MHz, i.e. **333,448 ticks/ms**, so every ms figure
here (and in every other document in this repo) is **0.415 % high**. It cancels in a
ratio and does not change any conclusion.

## 4. The state the measurement was taken in, stated because it is not the shipped state

Loading the instrumented firmware (**`rst -cores` + `dow`, no `rst -system`**) preserved the
reference mask (`MB_PART_REF = 659` before and after, `MB_DIFF_OK = 1`) but the **image
state changed**:

| word | before the reload | after |
|---|---|---|
| `MB_AEC_MEAN` | 505-509 ‰ | **847 ‰** |
| `MB_READY` | 1 | **0** |
| `MB_ST_CODE` | 0 (self-test pass) | **255** (not run) |
| `MB_BG_STATE` | 1 | **0** |
| `MB_LOCAL_VERDICT` | 0 (PASS) | **1** (NG) |
| loop total | (168 ms in the 10-27 batch) | **265-277 ms** |

The camera came back brighter and the background no longer matches the frame. **The bracket
is a code-path timing and does not depend on the verdict**, so the measurement stands — but
the station is not in the state `dl/CONFIG_20261027.md` describes, and re-establishing it
(clear the belt, `MB_CMD=12`, a good board, `MB_CMD=9`) is an operator action.

**The direction of the bias:** this state is **58 % slower** than the 168 ms loop of the
10-27 batch (265 ms vs 168 ms). A longer bracket is the *permissive* direction, so the
honest statement is: **88 ms is measured on a slower-than-shipped station.** If the bracket
scaled with the loop, a healthy station's bracket would be about **56 ms**
(88 x 168/265) — **inferred, not measured** — which is still 3x the PL's 18.43 ms.

## 5. What this changes

`PL_INTEGRATION_20261028.md` §6 asked: does 18.43 ms fit in 22.6 ms? The answer is that it
fits in **88 ms**, and the "stop and say so" branch of the brief — widen the datapath to
>= 2.3 px/clk, or let the PS wait for the PL — **is not needed.** The single-lane datapath
that was verified bit-exact is usable on timing grounds.

The other constraint the identity mechanism needs is unaffected: `settle_gate()` and
`avg_sample()` both run **after** `tear_sig_compare()`, so a PL pass that finishes before the
bracket closes is available well before the PS demands it.

## 6. What remains unverified about timing

| item | state |
|---|---|
| the bracket on a healthy (168 ms-loop) station | **inferred ~56 ms**, not measured |
| the bracket with `MB_PLFE_ON = 1` and the PL reading the store concurrently | **not measured** — DDR contention from ~150 MB/s of HP reads is unmeasured |
| the PL's 18.43 ms on silicon | simulated at **1 px/clk (9303 cycles for 9216 px)**, not measured on the board |
