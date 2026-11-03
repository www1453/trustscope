# Stage C (2026-10-25) — four whole 10 ms periods, the part mask in the control loop, and a latch that can leave

Build `TSC1` / `06C4E921`.  Flashed with `ps_fft_dual/strict_load_cores.tcl` only (no
bitstream, no power cycle, no running-VDMA poke): the board was **cold** when this session
started and the three-step documented bring-up was run first — see section 0.

**What this fixes, in one line each.**  (1) With VTS 740 at most two 10 ms periods fit in
a frame, so the anti-flicker lock offered three exposures; VTS is now 1200, the frame is
44.15 ms, and **k = 1..4** (10/20/30/40 ms) fit.  (2) The AEC could report CONVERGED while
`PART_MIN_PTS` was not met, because the part mask was not an input and was not even
measured while the frame was being refused.  (3) A latched AEC had no way out of its own
latch: it changed nothing, so the image could not become usable, so the latch could not
clear.  It now clears on the **first evaluation** whose image is usable, measured.

---

## 0. The board was cold: how that was established, and what was run

Measured before anything was written (the honest check is the one that can fail):

| probe | value | meaning |
|---|---|---|
| `0x10F00000` (MB_MAGIC) | `0xFFFFFFFF` | mailbox never published this power-on |
| `0x10000000` (camera-0 store 0) | `0xFFFFFFFF` | DDR not initialised |
| `0x00100000` (just above OCM) | `0xFFFFFFFF` | same |
| `0x00000000` (reset vector) | `0x9FA90DDC` | **not** `0xEA000006` = our image is not loaded |
| `rrd pc` | `0xFFFFFF28` | not executing our code |

So the board was cold and the documented cold bring-up was run:
`ps_fft_dual/stereo_bringup_byname.tcl` (ps7_init + `ps7_post_config`, FCLK_CLK0 50 MHz,
**`fpga -file` of the project's existing `design_1_wrapper.bit`**, v_tc, both sensors
`0x56`/`0x5640`, both capture channels live: control 30/32 words changing, camera 1 28/32),
then `ps_fft_dual/disp_fix_20261023.tcl`, then `strict_load_cores.tcl`.
**No bitstream was built or modified** — the file is the same one used on 2026-10-24
(`design_1_wrapper.bit`, 4,045,676 bytes, mtime 2026-10-24 13:10), and a cold board with
no PL configuration has no video path at all.  Everything after that point is firmware.

**Human check that no script can do (still required before a power-on):** the J10
PIN35(B20)↔PIN28(V12) jumper must be OUT.  Not observable from software and not touched.

---

## 1. The word map, rebuilt from the source before any read (task step 0)

`python dl/mb_words.py --write dl/MB_WORDS_20261025.md` parses every `#define MB_*` out of
`ps_ui/main.c`; `--tcl dl/mb_map_20261025.tcl` emits the name→index table the readers use.

| item | value |
|---|---|
| MB_* defines parsed as words | **316** (315 distinct indices) |
| indices carrying two DIFFERENT names | **0** |
| "byte N" comments that disagree with 4 x index | **0** |
| magic values that are not word indices | 2 (`MB_P1_OK`, `MB_VALID`) |

Every read in this session went through a **name**, and an unknown name is a hard error
(`ps_fft_dual/mb_rd_20261025.tcl`, `mb_snap_20261025.tcl`, `mb_aec_trace_20261025.tcl`).
The readers cannot be handed a stale number because they are never handed a number.

**Two things the map found that the brief's numbers did not say.**
* The parent's `ps_fft_dual/_b_state.tcl` indices are all CORRECT against this source
  (366 `MB_PART_PTS`, 368 `MB_PART_USED`, 494 `MB_DIFF_FCELLS`, 496 `MB_DIFF_FVALID`), so
  "366/368/494/496 returned nonsense" was not a stale-number problem in that script: the
  nonsense values are what an **unpublished** mailbox returns (section 2).  Its one real
  labelling error is `W 0` printed as "progress": word 0 is `MB_MAGIC`.
* `MB_MAGIC` (word 0) is **host-written**, and the PS gates `MB_VERDICT` on it
  (`main.c:9421`).  With no magic the panel's verdict is 9 = unknown and `MB_VERDICT`
  reads DDR junk — which is why a verdict can look like garbage on a freshly booted board.
  The acceptance runs stamp `0x54534331` first, as a host is supposed to.

**And one collision the build check could not see** (found by adding a scan, section 5):
words 160..163 are written by **literal** offset for the end-to-end latency counters, so
my first numbering of `MB_AEC_TRIES`/`MB_SEN_VTS` at 160/161 shared those words and
`MB_SEN_VTS` read 63374337 instead of 1200.  They are now at 164/165, and
`check_layout.py` scans literal offsets too.

---

## 2. The state the board was found in — measured, not assumed

Old firmware (`4674FA10`, the last one flashed on 2026-10-24), on this cold boot:

```
MB_AEC_STATE 3   MB_AEC_EXP 8698 (k=2)   MB_AEC_GAIN 16   MB_AEC_MEAN 545..549
MB_AEC_EVCLIP 14..21   MB_CLIP_LIME 10   MB_AEC_LAST 7 (stuck, holding)
MB_READY 0       MB_DIFF_OK 3 (AEC stuck -> the comparison never runs)
MB_DIFF_VERDICT 2 (CANNOT JUDGE),  MB_PART_PTS 1200, MB_PART_REF 1071
MB_EXP_LOCK 1495970783  <-- DDR junk: nonzero, out of the valid 16..60000 range
```

This reproduces the brief exactly: exposure 8698 = 2 x `MB_LINE10` (4349), mean in the
150..780 band, state 3, READY 0, CANNOT JUDGE.  **But the cause is not the narrow range
this time** — the frame was clipping (17 per-mille of green channels against the 10
per-mille limit), and the controller could not dim because the exposure was pinned shut.

### 2.1 The dead-end latch, measured

`MB_AEC_STATE 3` was tested first and its body changed nothing, so nothing could make the
image usable.  Direct measurement of the exit: writing `MB_EXP_LOCK = 4349` (k=1, a frame
that does not clip) cleared it on the **next** evaluation (`state 3 -> 1`, `dec 8`,
`massMB_AEC_EXP 8698 -> 4349`, mean 549 -> 352, clip 17 -> 0).  The verdict then ran.
That is the exit the firmware did not have by itself.

### 2.2 `host_lock == 0` was the wrong test — one-variable A/B

The k-step guards tested `host_lock == 0u`, but a pin is only valid in 16..60000 (the
validity test three blocks above).  A **nonzero out-of-range** word therefore blocked
every exposure step while pinning nothing, leaving only the gain — and at the gain rail
the controller latched STUCK.  Every cold boot leaves exactly such a word (0xFFFFFFFF, or
DDR junk).  Controlled experiment, same scene, same image, one word different:

| `MB_EXP_LOCK` before `rst -cores` | what the AEC did |
|---|---|
| `0xFFFFFFFF` (what a power cycle leaves) | exp stuck at 8698, `state 3`, `dec 7`, clip 17 -> **CANNOT JUDGE** |
| `0` | exp 8698 -> 4349 (`dec 3`, k 2->1), `state 1`, mean 352 -> comparison runs |

That is the mechanism, and it is a stage-B regression, not a new one.

### 2.3 Two more defects the trace exposed

* **The controller acted on an unmeasured clip share.**  On a cold boot the first
  evaluation read `g_cam0_clip_pm = 10560` per-mille from a barely-started measure pass
  and dimmed the gain 64 -> 40 -> 16 on it.
* **The mask was never measured while the frame was refused.**  `diff_frame()` builds it,
  and the gate skips `diff_frame()` when `g_aec_state == 3`, so in exactly the state that
  needed the mask, `MB_PART_PTS` was stale.

---

## 3. What changed (`ps_ui/main.c` of this build)

| line | item |
|---|---|
| 1543-1572 | the stage-C word block: `MB_AEC_MASK` 157, `MB_AEC_K` 158, `MB_AEC_FLAGS` 159, `MB_AEC_TRIES` 164, `MB_SEN_VTS` 165; the four new decision codes 10..13 in the `MB_AEC_LAST` table; and the record of the 160..163 literal-offset collision |
| 4726-4795 | `sensor_frame_length_set()`: VTS 740 -> **1200**, in the proven two-one-byte-write form, readback verified with every rewrite counted, then a 135 ms drain so the line-time measurement sees only new-length frames |
| 4797-4810 + 9810 | the derivation window 224 ms -> **597 ms**, with the measured reason (see section 4.2) |
| 7180-7206 | `AEC_MEAS_MIN_N` 9600, `AEC_MASK_HYST` 48, `AEC_MASK_COOL` 12, `AEC_STUCK_TRIES` 12, each with the measurement that chose it |
| 7310-7500 | the locked-exposure law, reshaped: `pinned` replaces `host_lock == 0`; no decision on an unmeasured frame; the band+clip+mask test runs FIRST for every state; the part-mask term; the bounded recovery search; the boot period-count rounds **down** |
| 5812-5832 | `mask_sample_refused()`: the mask is measured on a refused frame, from a re-selected and invalidated store |
| 11038 | the call site, on the refusal branch only |
| 7503-7512 | the mask term requires `g_part_pts > 0`, so a mask that has not been measured yet cannot read as "short" |

**Not touched:** the display layer, the classifier, the comparison arithmetic, the
persistence window, the registration logic, camera 1's controller line.

**Cost.** `.text` 0x1983C (104,516), `.bss` 0x631C (25,372), image ends 0x1FBBC =
129,980 of the 131,072-byte OCM region: **1,092 bytes free** (3,552 before).  Nothing was
moved to DDR this time — it fitted.  `check_layout.py`: 317 `MB_*` words, 0 collisions, all
layout checks pass; compile warnings are the four pre-existing ones.

---

## 4. Measurements

### 4.1 The new frame and the quantum (re-derived, not scaled)

| word | value | how |
|---|---|---|
| `MB_SEN_SIZE` 511 | `0x04B00764` | VTS **1200**, HTS 1892, read back over I2C |
| `MB_SEN_VTS` 165 | 1200 | what this build wrote and verified |
| `MB_FRAME_TICKS` 503 | 14,781,254 | capture-store period on the frame pointer, 334.8 MHz ticks = **44.152 ms** (22.65 fps) |
| `MB_LINE_PS` 504 | 36,790 | re-derived as frame/VTS x tick = 36.79 us |
| `MB_LINE10` 509 | **4349** | 16 x 10 ms / line = 4348.8 |

The line time did **not** change (HTS and the PLL did not), and the derivation is a
derivation, not a scaling: `line = frame_ticks / VTS` = 14,781,254/1200 = 12,317.7 ticks,
16 x 3,348,000/12,318 = 4349.  The frame period independently agrees: 1200 x 36.79 us =
44.15 ms, measured 44.15 ms.

### 4.2 The derivation window had to grow, and it was caught by the board

First flash of this change came up with `MB_LINE10` reading 4349 but **`MB_AEC_K` = 0**,
i.e. `g_line10 == 0`: the derivation had failed and the AEC had fallen back to the unlocked
law and walked the exposure to **1871** — not a whole period, the flicker lock silently
off, with every other published word still looking healthy (they were stale from the
previous run and read perfectly plausibly).  Cause: the window is fixed at 224 ms and the
`n >= 3` guard counts parity transitions (one per two stores); at 44.1 ms/frame the window
holds ~5 stores and `n` came out 2..3.  The window is now 597 ms (~13 stores, `n ~ 6`,
the same margin the 27 ms frame had).  `MB_AEC_K` is the word that made this visible — it
is published by this change for exactly that reason.

### 4.3 The k range, measured by clamping rather than asserted

Pinning `MB_EXP_LOCK` far above the frame clamp: **60000 -> `MB_AEC_EXP` 17396 = 4 x 4349**,
so `k_max = 4` (the firmware clamps the pin to `g_kmax x LINE10`).  Arithmetic behind it:
(1200-4) x 16/4349 = 4.40 -> 4 whole periods; the fourth period needs 1087.3 lines against
a clamp at 1196 lines, **109 lines (10%) of margin**.  At the VTS ~1100 the task mentioned
the same k range exists but the margin is 8.7 lines (0.8%) — a 1% error in the line time
would put the request over the clamp, and a clamped shutter is not a whole number of
periods.  That is why 1200 was chosen.

Whole-period known answer, one row per k (`MB_EXP_LOCK` = k x 4349, `MB_AEC_EXP` read back):

| k | pin | `MB_AEC_EXP` | `exp mod LINE10` | `MB_AEC_K` |
|---|---|---|---|---|
| 1 | 4349 | 4349 | **0** | 1 |
| 2 | 8698 | 8698 | **0** | 2 |
| 3 | 13047 | 13047 | **0** | 3 |
| 4 | 17396 | 17396 | **0** | 4 |

### 4.4 Boot (the acceptance's first item), hostile `MB_EXP_LOCK` = 0xFFFFFFFF

| when | `MB_AEC_STATE` | k | gain | mean | clip | note |
|---|---|---|---|---|---|---|
| boot (first evaluation, ~20 ms) | 2 adjusting | 2 | 40 | 788 | (rising) | starts at k=2 and dims |
| 2.1 s | 2 adjusting | 1 | 16 | 549 | 20 | the k step happened |
| **3.2 s** | **1 converged** | 1 | 16 | 352 | 0 | |
| **5 s** | **1** | 1 | 16 | 352 | 0 | |
| **30 s** | **1** | 1 | 16 | 352 | 0 | stable, no blips |

`MB_READY` 1, `MB_AVG_CNT` 6..8, and a **fresh reference** (`MB_CMD = 9`) then gives
`MB_DIFF_CELLS 0`, `MB_DIFF_FCELLS 0`, `MB_DIFF_FVALID 625`, `MB_DIFF_VERDICT 0 = PASS`,
`MB_REG_STATE 1`.  So: converged 3.2 s after `con`, and the comparison runs — the thing the
board could not do at all before this change.

### 4.5 Dimmer and brighter, emulated with the host pin (nothing else was available)

**Emulated, stated plainly:** the bench light was not touched.  `MB_EXP_LOCK` was used to
put the sensor at an exposure that makes the *frame* darker or brighter than the operating
point, which is the same signal the controller sees.

* **Dimmer — handled, no latch.**  Exposure pinned at **1000 units (0.23 period)**, i.e.
  ~4.3x less light: the frame fell to mean 329 with clip 0; the controller raised the
  **gain to 64** (16 -> 40 -> 64) and reported `state 1`, `dec 13` (mask chasing), with a
  comparison running and passing.  No STUCK.
* **Brighter — reported honestly, recovered on release.**  Pinned at k=2 (8698), the frame
  clips **19 per-mille against the limit 10**, so the controller wanted to dim and could
  not (the host had pinned the exposure): `state 3`, `dec 7`.  It did not pretend the
  frame was fine.  On release it was back at `state 1`, k=1, mean 352, clip 0.
  **What the wider range does and does not buy:** it extends the *dark* end (a scene
  needing more light can now use 30 and 40 ms).  It does nothing for the bright end, whose
  floor is still one period at 1x gain; a scene brighter than that still latches, and the
  fix for that is the latch now recovering (next paragraph), not this change.

### 4.6 The latch recovery bound

**Bound implemented: the latch clears on the FIRST evaluation whose image is usable**
(mean inside 150..780, clip within the host limit, and the part mask not short) — the test
is the first branch of the evaluation, for every state, so nothing can be latched past it.
Measured: from `state 3` with the exposure pinned unusably, releasing the pin gave
`state 2` -> **`state 1` on the next evaluation (1 x 250 ms poll, `evals` 110 -> 111)**.
While an image is unusable the controller keeps moving one lever per evaluation, bounded
by `AEC_STUCK_TRIES` 12 moves, then holds but keeps re-testing.

### 4.7 Tearing — no regression (the frame timing changed, so this was re-checked)

The row-based detector over the acceptance run and the still-scene run:

| counter | value |
|---|---|
| renders whose selected source store was written during the render (`MB_TEAR_SEL`/`SELN`) | **0 / 942** |
| renders where a sampled row really changed (`MB_TEAR_ROW`/`ROWN`) | **0 / 943** |
| renders with a row change above 100 counts (`MB_TEAR_BIG`) | **0** |
| torn renders with / without a handover inside the render (`MB_TEAR_WIN` / `NOFLIP`) | **0 / 0** |

The direction of the change is the safe one: a store is rewritten once per 4 frame
periods, and the period just grew from 27.2 ms to 44.15 ms, so the margin a render has on
the store it reads got larger, not smaller.  Capture-store selection is unchanged
(`MB_CAP_AGE` 2, `MB_CAP_PAIRS` 2, decode not enabled — as before this change).

### 4.8 The part mask in the loop

`MB_AEC_MASK` 157 publishes the mask the decision used, `MB_AEC_FLAGS` 159 publishes why:
bit0 host pinned, bit1 mask short (chasing), bit2 a part is expected (the reference mask
is >= `PART_MIN_PTS`), bit3 the measurement is fresh.  Observed during the dimmer
emulation: `flags = 15` (pinned + chasing + expected + fresh) with `MB_AEC_MASK` 429 —
below `PART_MIN_PTS + AEC_MASK_HYST` 448 — and the controller holding brightness rather
than declaring convergence.  On the still scene at k=1: mask 509..642, `flags = 12`
(expected + fresh, not chasing), `state 1`.

**Not yet observed on this bench:** the mask term actually *rescuing* a short mask by
stepping the exposure, because at every usable exposure available today the mask is
509..642.  Last night's short mask (314..377 at mean 333) did not reproduce this morning
(the same k=1 now reads 352 and 596): the scene or the part placement moved overnight.
The code path is exercised (`dec 13`, `flags` bit1, `tries` 3 during the dimmer emulation)
but the *outcome* is not: it is in the list below as the first thing a quiet bench should
re-run.

---

## 5. `check_layout.py`: a collision class the build check could not see

The 160..163 near-miss above was possible because the existing check compares `#define`
indices only.  A second scan now also collects every `MAILBOX + <n>u * 4u` literal offset
and fails the build when a literal and a name claim the same word.  It immediately found a
**pre-existing** one, which is reported rather than fixed because the display layer is out
of scope: word 131 is `MB_ARM_DT` (the bracket arm interval) and the CNN panel reads it by
literal offset as its "selftest timeout" flag (`main.c:9588`) — so an arm interval of
exactly 5 would print "CNN SELFTEST TIMEOUT" on the panel.  It is listed in the check with
its reason, and the build fails on any *new* one.

---

## 6. Still-scene comparison distribution (acceptance item 4)

One run of `ps_fft_dual/stC_still_20261025.tcl 165 600` on the still scene, fresh
reference, no settle slots, every row one judged comparison (`MB_DIFF_N` advanced):

| comparisons | settle slots | coarse cells 0 / 1..7 / >=8 | fine cells 0 / 1..7 / >=8 | rows with verdict != PASS | PASS with fine >= 8 |
|---|---|---|---|---|---|
| **120** | 0 | **120 / 0 / 0** | **120 / 0 / 0** | **0** | **0** |

`MB_READY` 1 and `MB_AVG_CNT` 6..8 throughout; `MB_PART_PTS` 509..642 against
`MB_PART_REF` 612.  Tearing over the same run: `MB_TEAR_SEL` **0 / 4224** and
`MB_TEAR_ROW` **5 / 4224** (0.12%), all five counted as `WIN` (a handover inside the
render) with `NOFLIP` 0 and `MB_TEAR_BIG` 0.  For comparison the pre-change build measured
1 / 409 (0.24%) in the equivalent snapshot, so the rate went down, not up.

A shorter earlier run (67 comparisons, `stC_still_20261025.tcl 95 700`) is reported too and
agrees: 67 / 67 clean, 0 non-PASS.

`MB_VERDICT` (word 2) is **host-sourced** — the PS only reads it (`main.c:9445`, `main.c:9513`)
and nothing wrote it in this session, so it still holds DDR junk (`0xDFF59D7E`).  The
verdict the firmware computes itself is `MB_DIFF_VERDICT`, and that is 0 = PASS on every
judged row above.

---

## 7. What remains unverified, and every human-dependent check

1. **The mask term's outcome on a genuinely short mask.**  The input, the hysteresis, the
   cool-down and the decision codes are exercised, but every exposure that is usable on
   today's scene gives a mask of 509..642, so "it steps the exposure and the mask recovers"
   has not been seen end to end.  Experiment (no operator needed, ~2 min): pin
   `MB_EXP_LOCK` to ~2800 units so the mean stays in the band with the mask below 400, then
   watch `MB_AEC_MASK`, `MB_AEC_FLAGS` bit1, `MB_AEC_LAST` 10/11, and whether the mask
   crosses 448.  If the mean leaves the band at every pin that shortens the mask, the term
   cannot be demonstrated on this part without dimming the room.
2. **A genuinely darker scene climbing k upward.**  The host pin cannot make the controller
   step k up (the pin blocks the step by design), and today's scene sits at k=1.  The k
   ladder is verified arithmetically and by clamp, not by watching the AEC climb 1->2->3->4.
   Experiment: cover the part with a neutral-density filter or take the scene 4x darker and
   read `MB_AEC_K` over 30 s; it should walk up and stop inside the mask floor.
3. **The band at k=3 and k=4.**  The exposures are whole periods by arithmetic
   (`exp mod LINE10 == 0` measured for all four), but the optical null was measured on
   2026-10-24 only up to k=2.  If the illuminant is still 100 Hz the band must be null at
   k=3/k=4 too; that would be confirmed with the stage-B method (two single-frame reference
   dumps per exposure, `ps_ui/stB_pair.py --period 271.8`).  Not done here: it needs
   REF_BASE dumps, and this session did not want to overwrite the reference the verdict is
   using.
4. **A part that is removed after the baseline was taken.**  The mask term is gated on
   "the reference has a part", so an empty belt leaves it on; the controller would then
   hunt brightness up to `AEC_STUCK_TRIES` moves.  Bounded, and it ends in a reported STUCK
   rather than a false PASS, but it has not been measured.  Experiment: take a reference
   with the part in view, remove the part, watch `MB_AEC_TRIES` and `MB_AEC_LAST`.
5. **Camera 1** still runs its own controller and still bands its view.  Unchanged, as in
   stage B.
6. **The 100 Hz assumption** still underlies every whole-period claim (see stage B,
   section 7.4).
7. **The J10 jumper** (PIN35 B20 / PIN28 V12) must be out before any power-on — a human
   check, not a software one.
