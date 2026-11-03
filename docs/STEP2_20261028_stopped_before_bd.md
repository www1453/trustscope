# Step 2: stopped before the block design, with the reasons measured

**Date:** 2026-10-28, same session as `LOOP_MEASURE_20261028_step1.md`
**Status:** the block design was **not** modified. No bitstream was built, loaded or written.
The safe bitstream `safe_bitstreams/BIT_20261024_fp1.bit` and the Vivado project
`D:/BaiduNetdiskDownload/23_ov5640_dual/Vivado/two FFT/two FFT.xpr` are exactly as they
were found. The station was not power-cycled.

This document answers the seven points of the step-2 authorisation, in order, and it
explains why the work stopped before the RTL rather than after it.

---

## 0. Why stop here, in one paragraph

Three things were measured that together make an integration in this session either
unsafe or unverifiable, and all three are facts about the machine rather than
judgements about effort. **(a)** The build that produced the current safe bitstream has
**0.037 ns of hold margin** (`WHS +0.037` in
`design_1_wrapper_timing_summary_routed.rpt`) — 37 ps — so a re-implementation carrying
a new clock domain and ~2,000 more LUT is more likely than not to break hold, and a hold
violation is not fixable by slowing a clock. **(b)** The gate requires a bitstream that
*loads and reproduces the verdicts*, and after any reload the reference cannot be
re-created by software: `ref_take()` is called with
`cam0_stores[cap_read_index_short()]` ([main.c:15056](ps_ui/main.c#L15056)) — it takes
its reference **from the live camera**, so a human has to put a good board under it.
**(c)** The RTL that Path A needs does not exist: `dl/pl_frontend/` contains
`pl_fe_core.v`, a pure raster datapath, and nothing else. The AXI4 read master, write
master and AXI-Lite slave are unwritten and unsimulated. Writing ~600 lines of AXI and
putting them into a device with 37 ps of hold margin, unbuilt and unsimulated, on a
design other people depend on, is the failure mode the project's own casebook is full of.

So the honest position is: **the integration is possible, the measurement is now
specified, and the build should be done in a session that can also finish it.** Below is
everything needed to start it, including the parts of the design that are now settled.

---

## 1. Baseline: what the current build actually costs (verified, not quoted)

Read from the routed reports of the build that produced `BIT_20261024_fp1.bit`
(`two FFT.runs/impl_1/`, 2026-10-24 13:04-13:10). These are the same files the number
`16,687 free LUT` came from, and this is the first time they have been tabulated here.

| Resource | Used | Available | % | Free |
|---|---|---|---|---|
| Slice LUTs | 36,513 | 53,200 | 68.63 % | 16,687 |
| — LUT as Logic | 34,207 | 53,200 | 64.30 % | |
| — LUT as Memory | 2,306 | 17,400 | 13.25 % | 15,094 free LUTRAM |
| Slice Registers | 58,900 | 106,400 | 55.36 % | 47,500 |
| Block RAM Tile | 138.5 | 140 | **98.93 %** | 1.5 |
| DSPs | 219 | 220 | **99.55 %** | 1 |
| **WNS** | **+0.908 ns** | | | |
| **WHS** | **+0.037 ns** | | | |

**Arithmetic delta with the block** (this is arithmetic on the OOC numbers, **not a
build** — it excludes everything below):

| | Now | With the block | % |
|---|---|---|---|
| Slice LUTs | 36,513 | 38,376 (+1,863) | 72.14 % |
| — Logic | 34,207 | 35,332 (+1,125) | 66.41 % |
| — Memory | 2,306 | 3,044 (+738) | 17.49 % |
| Slice Registers | 58,900 | 59,471 (+571) | 55.89 % |
| Block RAM | 138.5 | 138.5 | 98.93 % |
| DSP | 219 | 219 | 99.55 % |

**The block keeps its promise of no BRAM and no DSP** — at 138.5 of 140 tiles, 0 BRAM is
the only acceptable answer and it holds. What this table does **not** include: the AXI4
read master, the AXI4 write master, the AXI4-Lite control slave, the frame-identity
registers, the interconnect, and the clock/reset distribution. Those are not designed
yet, so the 72.14 % is a floor, not an estimate. **A ceiling of ~75-78 % LUT is the
honest expectation once the wrapper exists, and only a build can say whether hold
survives.**

`WHS +0.037 ns` deserves to be the headline of this section. The current design has
**37 picoseconds** of hold margin. That is not a resource question; it means the
next build is the one that decides whether the front end can be added at all, and it
decides it before any of the performance work matters.

---

## 2. `PCW_USE_S_AXI_HP2/3`, before and after (point 4)

Read from `two FFT.srcs/sources_1/bd/design_1/design_1.bd` by parsing the JSON, not from
a comment:

| Parameter | Value |
|---|---|
| `PCW_USE_S_AXI_HP0` | 1 (in use) |
| `PCW_USE_S_AXI_HP1` | 1 (in use) |
| **`PCW_USE_S_AXI_HP2`** | **0** |
| **`PCW_USE_S_AXI_HP3`** | **0** |
| `PCW_USE_M_AXI_GP0` | 1 |
| `PCW_USE_M_AXI_GP1` | 0 |
| `PCW_USE_S_AXI_ACP` | 0 |
| `PCW_FPGA0_PERIPHERAL_FREQMHZ` | 50 |

**"After" does not exist, because the block design was not modified.** HP2 and HP3 are
both free and the interface decision stands: enable `S_AXI_HP2`, one PS7 parameter plus
`S_AXI_HP2_ACLK`, no pin and no XDC.

Interconnect cost, stated plainly: one AXI4 read master (streams the 2,764,800-byte
store, 64-bit at 50 MHz = 400 MB/s, so 6.91 ms minimum for the frame; the datapath at
1 px/clk is the limit at 18.43 ms), one AXI4 write master (46,800 bytes of statistics per
frame), one AXI4-Lite slave (store base address, trigger, identity, bypass), and a reset
taken from **the same `proc_sys_reset` domain as the HP port's `ACLK`** — a reset from
another domain is `[BD 41-1343]`.

---

## 3. The frame-identity mechanism — it CAN be done without touching the verdict path (point 3)

This was the question that could have made the integration impossible, and the answer is
that it does **not** require changing the verdict path. The mechanism:

**What the PS already knows at the point where it would use the statistics.** At
[main.c:14897](ps_ui/main.c#L14897) `avg_sample(g_long_buf, frames)` is called after
`settle_gate()` has published this loop's readiness ([14880](ps_ui/main.c#L14880)) and
after `tear_sig_compare(g_long_buf)` has counted the tear rows ([14833](ps_ui/main.c#L14833)).
The store was selected at [14506](ps_ui/main.c#L14506) as `cam0_stores[g_cap_sel]`. So the
PS holds the store index and a per-loop counter; it does not hold a PL-visible capture
generation, and it does not need one.

**The mechanism.**

1. Immediately after the store is selected (14506) the PS writes `{store_index, loop_seq}`
   to the AXI-Lite trigger register. The PL starts reading that store at once.
2. The PL publishes the statistics **and echoes `loop_seq`** in a status register, with a
   `done` bit.
3. At `avg_sample` the PS requires `done = 1` **and** `status_seq == loop_seq` — i.e. the
   statistics are for the store the PS named, in this loop. If either fails, it runs the
   existing 936,000-read PS pass unchanged.
4. **The tear and readiness gates are not touched and are not bypassed**, because
   `tear_sig_capture(g_long_buf)` at 14509 and `tear_sig_compare(g_long_buf)` at 14833
   bracket the render's read of the *same store*, and `g_tear_drows` at
   [4344](ps_ui/main.c#L4344) still decides whether the frame is accumulated.
   `settle_gate`, `diff_frame`, `diff_verdict` and everything downstream are untouched.

**The one assumption this rests on, which is a timing assumption and not a logic one.**
The PL's read must finish *inside* the interval the tear bracket covers. If it does, a
store that changed under the PL would also have changed under the render, and the existing
gate would have dropped the frame. If it does not, the PL's read sticks out beyond the
bracket and the tear gate no longer covers it — and that, not any counter, is the real
hazard.

**The budget.** The PL needs **18.43 ms** to walk 921,600 source pixels at 1 px/clk at
50 MHz. The bracket runs from the store selection (14506) to the tear comparison (14833).
Interpolating those points through the measured phase shares of §5 (class 32.93 ms from
tB=14326 to tC=14550, qual 7.78 ms to tD=14708, cam 69.14 ms to tE=15208) gives:

```
14506 -> 14550   6.5 ms      (44/224 of the class phase)
14550 -> 14708   7.8 ms      (the qual phase, measured)
14708 -> 14833  ~8.3 ms      (125/500 of the cam phase, by line count)
                 ------
                 ~22.6 ms    bracket
PL needs          18.43 ms
                 ------
                 ~4.2 ms     margin, ~19 %
```

**That ~4.2 ms is an inference from line counts, not a measurement, and it is the first
thing the next session should measure** — it is six lines of firmware (two `R32(GTIMER)`
reads around the interval, published to two spare mailbox words) and one build, and it
decides whether the existing 1 px/clk block can be overlapped at all. A 19 % margin on a
figure derived from line counts is not enough to design against. If the measured margin
is negative, the choices are: widen the datapath to ≥2.3 px/clk (a re-verified datapath,
which is the real cost of the integration and is not in the brief's plan), or accept the
PS waiting for the PL, which contracts the saving from ~14 ms to roughly 4-5 ms/loop
because 18.43 ms of the 28 ms pass is still paid, this time as a stall.

---

## 4. The bypass bit (point 2)

**Nominated word: 572.** It is the first free index above the current maximum (571);
words 1-571 are all claimed by an `MB_*` name, an array base or a literal offset (checked
by scanning every `#define MB_* <n>u` in `main.c` — 411 distinct indices, and 572-600 are
free).

**Semantics: `MB_PLFE_ON`, host-written, default 0 = bypassed.** With it at 0 the firmware
runs exactly the shipped code path, so a boot with no host script behaves like the
shipped build; with it at 1 the PS may take the PL statistics when the identity matches.
It is a *permission*, not a switch: even at 1, a failed identity falls back to the PS pass.

**Not declared in `dl/host_qc/qc_mailbox.py`, deliberately.** A mailbox word that the
firmware does not write is exactly the fault the boot self-test exists to catch
(`MB_ST_CODE` check (d), main.c:3141: "a host word every consumer read as UNK because
nothing was writing it"). Declaring it now would create that fault on purpose. **Declare
it in the same commit as the firmware that writes it.**

---

## 5. `class` — what it is, and what it is not (point 7)

20 consecutive windows, recording the phase vector together with every word that could
explain it (`class_regime_20261028.tcl`).

**First, the hypothesis I tested and it failed.** `class` contains `part_track()`
([main.c:14546](ps_ui/main.c#L14546), between tB=14326 and tC=14550), and `part_track()`
has two rules — the background rule at 4 reads/cell and the old green fallback at 12
([main.c:4918-4921](ps_ui/main.c#L4918-L4921)) — which would explain a cost that changes
by a factor. **It is refuted:** `MB_PART_RULE = 1`, `MB_PART_BGWHY = 0` and
`MB_BG_STATE = 1` were **identical in all 20 windows**. The rule never switched.
`MB_PART_TK_MS` did move — 4.87 ms/loop in 15 windows, 7.3-9.9 ms/loop in 5 — but a 5 ms
change cannot explain a 47 ms swing.

**Second, what it scales with, measured** (20 windows, exact):

| phase | mean | min | max | sd | behaviour |
|---|---|---|---|---|---|
| `class` | **30.82** | **11.29** | **58.74** | **13.53** | three regimes |
| `sync` | 23.33 | 16.07 | 35.96 | 5.02 | moves with `class` |
| `qual` | 7.82 | 7.41 | 8.24 | 0.19 | flat |
| `cam` | 69.90 | 66.13 | 74.64 | 1.50 | flat |
| `panel` | 1.05 | 1.02 | 1.25 | 0.06 | flat |
| `tail` | 8.37 | 8.07 | 8.77 | 0.19 | flat |

`corr(class, sync) = +0.952`. `class + sync` accounts for essentially all of the total's
variance; `qual`, `cam`, `panel` and `tail` together are flat to within a few percent.
And `class` moves *with* `sync` rather than against it, which is the signature of a loop
that must fit a whole number of capture frames: more compute pushes the loop across a
frame boundary and the wait grows too, instead of the wait shrinking to absorb it.

**Third, what is in `class`, from the code.** Three things cost real time between tB and
tC:

* `dcache_invalidate(store, CAM_BYTES)` at [14504](ps_ui/main.c#L14504) — 2,764,800 bytes,
  ~86,400 cache lines. Sub-millisecond at a few cycles per line, so **not the answer**.
* `cam_mean_green(g_long_buf)` at [14514](ps_ui/main.c#L14514) and
  `cam_bright_count(g_long_buf)` at [14517](ps_ui/main.c#L14517) — **two independent
  full-frame passes over all 921,600 source pixels**, back to back. At ~30 ns per uncached
  read that is ~27.6 ms each, ~55 ms for the pair, which **matches the 58.7 ms high
  regime** almost exactly.
* `part_track()` at 14546 — measured at 4.9-9.9 ms by the firmware itself.

**So the most probable mechanism is the cache state those two full-frame passes see.**
`dcache_invalidate` at 14504 is meant to make them cold. If the store is (partly) still
resident, the passes run from cache and cost ~12 ms; if it is cold they cost ~55 ms; the
regime depends on how much of the previous loop's render traffic left the store resident.
**This is consistent with the numbers but it is not proven**, and the way to prove it is
to time the two passes separately — six lines of firmware using the same GTIMER pattern
as the existing phases, published to two spare words (573, 574), and one build.

**One consequence worth naming now, and it revises the headline number.** `class` contains
**two full-frame passes** costing up to ~55 ms between them, against the averaging pass the
block was built for. And `MB_AVG_TICKS` now gives that pass a measured price: over the same
20 windows it was **mean 39.00 ms per call, min 29.61, max 47.80** (not the 28.0-29.4 ms the
catalogue assumed). `avg_sample()` runs 8 times per 16 loops (`DIFF_EVERY` 16, `AVG_N` 8),
so the PS pays **0.5 × 39.00 = 19.5 ms/loop** in it. Replacing the 936,000 scattered reads
with the 46,800-byte statistics read (~1.4 ms per call) leaves **~0.7 ms/loop**, so the
**ceiling is ~18.8 ms/loop = 11.2 % of the loop, not 14.0 ms / 7.9 %**.

That figure is still below the 12.85 % within-run sd of the loop *total*, so the conclusion
of step 1 does not change: the total cannot show it. It **strengthens** the case for the
`cam` statistic, which resolves 1.4 ms at six windows per arm and would see an 18.8 ms
change at ~13σ. It also raises the stakes on the §3 timing question — the same 18.43 ms PL
read is now competing against a 39 ms PS pass rather than a 28 ms one.

**And there is a bigger prize in the same phase.** The two full-frame passes already in
`class` cost up to ~55 ms between them — roughly three times the 19.5 ms averaging pass.
If the block's datapath is being integrated anyway, moving `cam_mean_green` and
`cam_bright_count` into it is a much larger saving than the averaging pass, and it rests on
the same identity and tear argument. That is a decision for whoever owns the next step, not
a recommendation to abandon the current plan — but it changes the cost/benefit of the same
amount of RTL work.

---

## 6. What the next session needs, in order

1. **Measure the bracket** (§3). Six lines of firmware, one build, no hardware change.
   This gates everything: if the measured `14506 -> 14833` interval is under 18.43 ms, the
   existing 1 px/clk block cannot be overlapped and the plan changes.
2. **Time `cam_mean_green` and `cam_bright_count` separately** (§5). Six more lines,
   same build. Names the `class` regime and decides whether the bigger prize is real.
3. **Back up before anything else**: `python dl\backup.py save pl_fe_bd <the .bd and .xpr>`.
   The block design lives **outside git**, at
   `D:/BaiduNetdiskDownload/23_ov5640_dual/Vivado/two FFT/`, so a `git revert` cannot undo
   a BD edit. This is the single most important procedural point in this document.
4. **Write and simulate the AXI wrapper before it goes near the BD** — a read master with
   burst and backpressure, a write master, an AXI-Lite slave. The existing testbench
   covers `pl_fe_core` only.
5. Then the BD, with the project's own rules: assert 2 endpoints before any disconnect,
   never `delete_bd_objs` a net, assert the global clock net's pin count never decreases,
   count ERROR messages before and after `validate_bd_design` (it returns empty either
   way — B18b), no pin or XDC change.
6. Then synth + impl, and **look at `WHS` first, not `WNS`**. With 37 ps of margin the
   hold number is the one that will decide whether this design can carry new logic.
7. Only then the flash — **and only with an operator**, because the reference has to be
   re-taken from a live board (§0b) and the exposure re-pinned to 8698.

---

## 7. Unverified, carried forward from step 1

Everything in §9 of `LOOP_MEASURE_20261028_step1.md` still stands, plus:

| Item | State |
|---|---|
| Routed WNS/WHS with the block in the design | **not measured** — no build |
| The `14506 -> 14833` bracket | **inferred at ~22.6 ms from line counts**, not measured |
| Whether the PL's read fits inside the tear bracket | **not established** — the §3 assumption |
| `cam_mean_green` / `cam_bright_count` individual costs | **not measured** — inferred ~27.6 ms each |
| The `class` regime mechanism | **hypothesised (cache residency), not proven**; the rule-switch hypothesis is **refuted** |
| Whether the block loads and reproduces the verdicts | **not attempted** |
| Whether `cam` drops by 14 ms | **not attempted** |

---

## 8. The one paragraph

The integration is possible and the safety question is answered — the frame-identity check
can be done **without touching the verdict path**, by the PS naming the store and the PL
echoing a sequence number, with the existing tear bracket covering the PL's read and the
unchanged PS pass as the fallback on any mismatch — but it was not started, for three
measured reasons: the RTL that Path A needs (AXI read master, write master, AXI-Lite
slave) does not exist and the existing testbench does not cover it; the build that
produced the current safe bitstream has **37 ps of hold margin**, so the next build is the
one that decides whether the device accepts the front end at all; and the gate requires a
loaded bitstream that reproduces the verdicts, which cannot be satisfied without an
operator because `ref_take()` takes its reference from the live camera and a reload
destroys it. The resource arithmetic on verified routed numbers is LUT 36,513 → 38,376
(68.63 % → 72.14 %) with BRAM and DSP unchanged at 138.5/140 and 219/220 — a floor, not an
estimate, because it excludes the whole AXI wrapper. And the `class` investigation came
back with a result worth more than the paragraph it was asked for: the phase that dominates
the loop's variance contains **two full-frame passes** (`cam_mean_green`, `cam_bright_count`)
costing up to ~55 ms between them — roughly three times the averaging pass the block was
built for, reached by the same identity and tear argument. It also re-priced the pass the
block does target: `MB_AVG_TICKS` measured **39.00 ms per call** over 20 windows, and at
8 calls per 16 loops that is 19.5 ms/loop, so the ceiling is **~18.8 ms/loop (11.2 %)**,
not 14.0 ms — still inside the 12.85 % sd of the loop total, which is why the `cam`
statistic remains the only one that can carry the claim.
