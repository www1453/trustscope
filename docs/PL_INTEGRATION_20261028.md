# Why the per-pixel front end is not in the FPGA

**Date:** 2026-10-28
**Question this answers:** the block is built, it is bit-exact on a real frame, it fits, and
it is cheap — so why is it not deployed?
**Answer in one sentence:** because the measurement that would have shown it helping was
broken, and fixing it produced a number — 37 ps of hold margin — that says this device
should not take a new clock domain this week; the integration itself is designed and its
first step is specified.

Every number below is measured on this station and cited to where it was measured. Where a
number is inferred rather than measured, the word **inferred** appears next to it. There is
a list of what is still unverified at the end, and it is not short.

---

## 1. What exists, and what it is worth

`dl/pl_frontend/` contains `pl_fe_core.v`, a raster datapath that computes the 160x90 grey
lattice, the 8x8 cell means with their within-cell range, and the 16x16 coarse means in one
pass at 1 pixel per clock, plus a testbench, a golden model, OOC synthesis reports and
`REPORT.md`.

| Property | Value | Where |
|---|---|---|
| Bit-exactness on a real frame | **46,800 of 46,800 values identical**, max abs diff 0 | `REPORT.md` §4 |
| Negative control | two deliberately corrupted inputs **rejected** | `REPORT.md` §4 |
| Cost | LUT **1,863** (1,125 logic + 738 LUTRAM), FF **571**, BRAM **0**, DSP **0** | OOC synth |
| OOC timing | WNS **+3.738 ns** | OOC synth |
| What it replaces | 936,000 scattered uncached reads per averaged frame | `REPORT.md` §5.1 |

The block is not in doubt. What was in doubt is whether anyone could **see** it working,
and that turned out to be the binding problem.

---

## 2. Reason 1 (leading): the device has 37 ps of hold margin

From the routed reports of the build that produced the current safe bitstream
`safe_bitstreams/BIT_20261024_fp1.bit`
(`two FFT.runs/impl_1/design_1_wrapper_timing_summary_routed.rpt` and
`design_1_wrapper_utilization_placed.rpt`, both 2026-10-24 13:04-13:09):

| Resource | Used | Available | % | Free |
|---|---|---|---|---|
| Slice LUTs | 36,513 | 53,200 | 68.63 % | 16,687 |
| — LUT as Logic | 34,207 | 53,200 | 64.30 % | |
| — LUT as Memory | 2,306 | 17,400 | 13.25 % | 15,094 |
| Slice Registers | 58,900 | 106,400 | 55.36 % | 47,500 |
| Block RAM Tile | 138.5 | 140 | **98.93 %** | 1.5 |
| DSPs | 219 | 220 | **99.55 %** | 1 |
| **WNS** | **+0.908 ns** | | | |
| **WHS** | **+0.037 ns** | | | |

**`WHS = +0.037 ns` means 37 picoseconds of positive hold slack.** That is the number this
decision turns on, and it was not in the project record before today.

Hold is not like setup. A setup violation can sometimes be closed by slowing a clock or
re-budgeting a path; a hold violation is a race against the same edge and is closed only by
adding delay or changing the netlist. Adding a new clock domain (`S_AXI_HP2_ACLK`), an AXI
interconnect port and ~2,000 LUT of new logic to a design sitting 37 ps above zero is more
likely than not to break it, and each attempt costs a 25-40 minute implementation cycle.

**The resource arithmetic is favourable and that is exactly why the timing number matters
more.** The block adds, on paper:

| | Now | With the block | % |
|---|---|---|---|
| Slice LUTs | 36,513 | **38,376** (+1,863) | **72.14 %** |
| — Logic | 34,207 | 35,332 (+1,125) | 66.41 % |
| — Memory | 2,306 | 3,044 (+738) | 17.49 % |
| Slice Registers | 58,900 | 59,471 (+571) | 55.89 % |
| Block RAM | 138.5 | **138.5 — unchanged** | 98.93 % |
| DSP | 219 | **219 — unchanged** | 99.55 % |

**This is a floor, not an estimate.** It is arithmetic on the out-of-context numbers and it
**excludes the entire AXI wrapper** — the read master, the write master, the AXI-Lite control
slave and the interconnect — none of which exists yet. With the wrapper, **75-78 % LUT is the
honest expectation**, and only a build can say whether hold survives at all.

The no-BRAM/no-DSP promise **holds and matters**: at 138.5 of 140 BRAM tiles and 219 of 220
DSPs, the only acceptable number for those two is zero, and the block delivers zero.

---

## 3. Reason 2: the verification gate needs a human, not more engineering

The acceptance gate is not "it builds". It is "it loads, it reports the same identity, and
**the same 41 boards get the same verdicts**". That gate cannot be reached by software alone,
for a reason that is in the firmware:

```c
ref_take((const volatile uint8_t *)cam0_stores[cap_read_index_short()]);   // main.c:15056
```

`ref_take()` takes its reference **from the live camera**. Loading a bitstream means
`rst -system` and `ps7_init`, which clears DDR and destroys the reference and the pinned
exposure. Re-establishing the station afterwards therefore requires someone to **put a good
board under the camera** — and the acceptance then belongs to a **new reference**, which by
the project's own rule (`main.c`, reference-generation note) must not be compared with the
existing 909 table.

So even a perfect build could not have been validated in an agent session. The report is
obliged to say so rather than to flash and claim.

---

## 4. Reason 3: the interface RTL does not exist

`dl/pl_frontend/` holds the datapath and its testbench. Path A needs three new AXI pieces
that are **unwritten and unsimulated**:

* an AXI4 **read master** that streams the 2,764,800-byte store as a raster at 1 px/clk;
* an AXI4 **write master** for the 46,800 bytes of statistics per frame;
* an AXI4-Lite **control slave** for the store base address, the trigger, the identity and
  the bypass bit.

That is roughly 600 lines, and the existing testbench covers `pl_fe_core` only. Writing it,
simulating it, and putting it into a device with 37 ps of hold margin, in one session, on a
design other work depends on, is the failure mode this project's casebook is built from.

---

## 5. The interface decision: HP-port master, not a VDMA tap

Parsed from `design_1.bd` itself, not from a comment:

| Parameter | Value |
|---|---|
| `PCW_USE_S_AXI_HP0` / `HP1` | 1 / 1 — both in use |
| **`PCW_USE_S_AXI_HP2` / `HP3`** | **0 / 0 — both free** |
| `PCW_USE_M_AXI_GP0` / `GP1` | 1 / 0 |
| `PCW_USE_S_AXI_ACP` | 0 |
| `PCW_FPGA0_PERIPHERAL_FREQMHZ` | 50 |

**Decision: an HP-port master reading the store the PS names.** Cost: one PS7 parameter
(`PCW_USE_S_AXI_HP2 0 -> 1` plus `S_AXI_HP2_ACLK`) — **no pin and no XDC change** — plus the
three AXI pieces above, plus a reset taken from **the same `proc_sys_reset` domain as the HP
port's `ACLK`** (a reset from another domain is `[BD 41-1343]`).

The VDMA stream tap was rejected for three reasons that are properties of the software:

1. The PS compares a **store it selects** out of a four-store rotation. A tap produces
   statistics for the frame *being captured*, which is a different picture whenever the belt
   moves — and on this station the capture hands over every ~90-230 ms.
2. `avg_sample()` will not accumulate a frame unless `MB_READY == 1` for that frame and
   `g_tear_drows == 0` (`main.c:4333-4344`). A tap's statistics arrive at capture time, before
   that gate is evaluated, so **both gates would be silently bypassed**.
3. Both paths need the identity word anyway, so a tap saves address logic and buys nothing
   on the hard part. Path A can additionally be pointed at a *reference* frame later
   (`ref_mean_build()`, `main.c:3522`), which a tap cannot.

---

## 6. How the frame identity would work — and it does not touch the verdict path

This was the question that could have made the integration impossible. The answer is that it
does **not** require changing the verdict path.

**The mechanism.**

1. The PS selects its store at `main.c:14506` (`cam0_stores[g_cap_sel]`).
2. Immediately afterwards it writes `{store_index, loop_seq}` to the AXI-Lite trigger register.
   The PL begins reading **that** store.
3. The PL publishes the statistics and **echoes `loop_seq`** in a status register with a
   `done` bit.
4. At `avg_sample()` (`main.c:14897`) the PS requires `done = 1` **and**
   `status_seq == loop_seq` — i.e. *these statistics are for the store I named, in this loop*.
   On any mismatch it runs the **existing 936,000-read PS pass, unchanged**.

**Why this cannot silently bypass the gates.** `settle_gate()` (14880), `tear_sig_capture()`
(14509), `tear_sig_compare()` (14833), `diff_frame()`, `diff_verdict()` and every downstream
word are **untouched**. The tear bracket runs around the render's read of the *same store*,
so a store that changed under the PL would also have changed under the render and the existing
`g_tear_drows` gate would have dropped the frame. A failed identity falls back to the PS pass:
the result can only be **slower, never wrong**.

**The assumption this rests on, and it is timing, not logic.** The PL's read must finish
**inside** the tear bracket. If it does not, the PL's read sticks out beyond the bracket and
the tear gate no longer covers it.

```
PL read budget      18.43 ms   (921,600 px at 1 px/clk, 50 MHz)
tear bracket       ~22.6 ms   (14506 -> 14833, **inferred** from measured phase shares)
                  ---------
margin             ~ 4.2 ms   ~19 %
```

**That 19 % margin is inferred from line counts, not measured**, and it is the first thing the
next session must measure — six lines of firmware (two `GTIMER` reads around the interval,
published to two spare mailbox words) and one build. If it comes back negative, the choices are:

* **widen the datapath to >= 2.3 px/clk** — a re-verified datapath, which is the real cost of
  this integration and is *not* in the brief's plan; or
* **let the PS wait for the PL**, which contracts the saving from ~18.8 ms to roughly 4-5 ms
  per loop, because 18.43 ms of the pass is still paid — this time as a stall.

---

## 7. The bypass bit: word 572, and why it is not declared yet

**`MB_PLFE_ON` = mailbox word 572**, host-written, **default 0 = bypassed**, so a boot with no
host script runs exactly the shipped code path. It is a *permission*, not a switch: even at 1,
a failed identity falls back to the PS pass.

572 is the first free index above the current maximum of 571 (every `#define MB_* <n>u` in
`main.c` was scanned — 411 distinct indices claimed; 572-600 are free).

**It is deliberately not declared in `dl/host_qc/qc_mailbox.py` yet.** A mailbox word the
firmware does not write is precisely the fault the boot self-test's check (d) exists to catch
(`MB_ST_CODE`, `main.c:3141`: "a host word every consumer read as UNK because nothing was
writing it"). Declaring it now would manufacture that fault on purpose. It should land in the
same commit as the firmware that writes it.

---

## 8. What would have to happen, in order

1. **Back up first.** The block design lives **outside git**
   (`D:/BaiduNetdiskDownload/23_ov5640_dual/Vivado/two FFT/`), so `git revert` cannot undo a
   BD edit. `python dl\backup.py save <name> "<...>/design_1.bd" "<...>/two FFT.xpr"`, and
   verify the restore independently because that path contains a space (casebook **B19**).
2. **Measure the tear bracket** (§6). Six lines, one build. Gates everything.
3. **Time `cam_mean_green` and `cam_bright_count` separately** — see §9; the same build. This
   prices the larger prize.
4. **Write and simulate the AXI wrapper** before it goes near the BD.
5. **Then the block design**, under the project's rules: assert 2 endpoints before any
   disconnect; **never `delete_bd_objs` a net** (casebook B17b — it removed the global clock
   once); assert the global clock net's pin count never decreases; count ERROR messages before
   and after `validate_bd_design` (it returns an empty string either way — casebook B18b);
   **no pin or XDC change**.
6. **Synthesis and implementation**, and read **`WHS` first, not `WNS`**.
7. **Then the flash, with an operator** (§3), re-pinning exposure to 8698 and re-taking the
   reference — with the explicit consequence that the resulting verdicts belong to a **new
   reference** and must not be compared with the 909 table.

---

## 9. What the measurement work found, and why it made the block worth more

This is the part that a judge should hear, because it is the part that changed the answer.

**The instrument that was being misread.** The project carried two loop-time figures that
disagreed by 33 %: 159-177 ms from `MB_T_TOTAL` and 119.0 ms from `PROGRESS`-transition
counting. `MB_PROGRESS` is a **seven-valued stage beacon** (`main.c:12564-12581`, written seven
times per loop), not a loop counter — so counting its transitions divides by "observed stage
changes per loop", which is itself a function of the loop period. Its own log printed five
distinct values while reporting a rate. And the 119.0 ms sampler ran within 1 % of its **own
Nyquist limit** (8.40 Hz against 8.32 Hz), which is the signature of an aliased reading. It
never contradicted `MB_T_TOTAL`; it was reading a different quantity and calling it a loop.

**The tick constant was 0.415 % wrong.** Every millisecond figure in this project is
`ticks / 334800`. Measured by wrap counting, twice: 333.448 and 333.383 MHz. The constant is
0.415 % high, so every published ms number is 0.415 % low. Small, and it cancels in a
before/after — but it is now a measurement instead of an assumption.

**The noise floor was pre-registered before any "after" number existed.** 20 consecutive
32-loop windows, two batches 41 minutes apart, on the unmodified build:

| | |
|---|---|
| mean / min / max | **168.27 / 126.28 / 226.37 ms** |
| spread | **79.25 %** pooled (58.42 % and 57.11 % within the two batches) |
| sd | **21.63 ms = 12.85 %** |

The *mean of ten windows* moved 18 % between batches with no build change. Against a 7.9-8.5 %
effect, the loop **total** cannot show it: six windows per arm resolves 18.66 ms.

**But the loop total is the wrong statistic, and this is the finding that matters.**
`avg_sample()` lives in the `cam` phase (`main.c:14897`, between tD=14708 and tE=15208). Over
20 windows the phases are:

| phase | mean ms | sd ms | sd % |
|---|---|---|---|
| **cam** — the only one the block can move | **69.90** | **1.50** | **2.1 %** |
| class | 30.82 | 13.53 | 43.9 % |
| sync | 23.33 | 5.02 | 21.5 % |
| tail | 8.37 | 0.19 | 2.3 % |
| qual | 7.82 | 0.19 | 2.4 % |
| panel | 1.05 | 0.06 | 5.7 % |

The only phase the block can move is the **most stable** phase in the loop, and the total's
variance lives in `class` — which the block cannot touch. At the same six windows per arm,
`cam` resolves **1.39 ms** instead of 18.66 ms. A known-answer A/B/A confirmed the instrument
is specific: removing a documented 4.87 ms/loop cost from `class` left `cam` at
68.17 / 69.03 / 69.02 ms (arm-to-arm difference **0.84 ms**), while two arms with the *same*
setting differed by **10.00 ms** on the loop total.

**And the ceiling is higher than the report says.** `MB_AVG_TICKS` measures the averaging pass
at **39.00 ms per call** (mean over 20 windows, range 29.61-47.80) — not the 28.0-29.4 the
catalogue assumed. `avg_sample()` runs 8 times per 16 loops, so the PS pays
**0.5 x 39.00 = 19.5 ms/loop** in it. Replacing the reads with the 46,800-byte statistics read
(~1.4 ms per call, ~0.7 ms/loop) makes the block's ceiling **~18.8 ms/loop** — 11-13 % of the
loop depending on the batch, not 14.0 ms / 7.9 %. **The block is worth more than the report
claims.** It is still inside the 12.85 % sd of the loop total — which is exactly why `cam`, not
the total, is the statistic that can carry the claim.

---

## 10. What remains unverified

| Item | State | What would settle it |
|---|---|---|
| **The tear bracket** (`14506 -> 14833`) | **inferred** at ~22.6 ms from line counts | six lines of firmware + one build |
| Whether the PL's 18.43 ms read fits inside it | **not established** — the §6 assumption | the same measurement |
| **The `class` mechanism** | **hypothesis** (cache state after the `dcache_invalidate` at 14504), consistent with the numbers, **not proven** | time `cam_mean_green` and `cam_bright_count` separately |
| The whole-design `class` cost | `cam_mean_green` at 14514 and `cam_bright_count` at 14517, **two full-frame passes**, ~27.6 ms each by inference, ~55 ms the pair, matching the 58.74 ms high regime | the same measurement |
| **Routed WNS/WHS with the block and the wrapper** | **not measured** — no build | synth + impl; read `WHS` first |
| Whether the block loads and reproduces the verdicts | **not attempted** — needs an operator | the gate in §3 |
| **The `cam` saving on silicon** | **not measured** | an interleaved A/B with the bypass bit, 12 windows per arm |
| DDR contention from ~125 MB/s of HP reads | **not measured** | the same A/B |

---

## 11. The paragraph for the defence

> The per-pixel front end is built, simulated bit-exact on a real captured frame (46,800 of
> 46,800 values, with two deliberately corrupted inputs rejected), and costs 1,863 LUT
> (1,125 logic + 738 LUTRAM), 571 FF, **no BRAM and no DSP** — which matters on a device
> already at 98.93 % of its block RAM and 99.55 % of its DSPs. It is not deployed, and the
> reason is not that it would not fit: adding it takes the fabric from 68.63 % to a 72.14 %
> floor, and both constrained resources stay flat. The reason is that the device it would go
> into has **37 picoseconds of hold margin**, and a hold violation is not fixed by slowing a
> clock. Behind that sit two more: the interface RTL (an AXI read master, write master and
> control slave) is unwritten, and the verification gate — same bitstream, same verdicts on
> the same boards — needs a human to place a reference board, because `ref_take()` takes its
> reference from the live camera. The integration is designed, not abandoned: the frame-identity
> mechanism is specified and does **not** touch the verdict path. And measuring it properly
> raised the prize — the averaging pass it replaces measures **39.00 ms per call, 19.5 ms per
> loop**, so the block's ceiling is **~18.8 ms/loop (11.2 %)**, worth more than the 7.9 % the
> report originally claimed. What had to be fixed first was the instrument: the project was
> quoting a loop time taken from a seven-valued stage beacon sampled at its own Nyquist limit,
> and a tick constant that was 0.415 % wrong.
