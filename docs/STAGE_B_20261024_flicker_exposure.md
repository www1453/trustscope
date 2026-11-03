# Stage B (2026-10-24) — the rolling-shutter band removed at its source: the exposure is locked to whole 100 Hz ripple periods

Status: DONE, flashed, accepted, committed.  Build `TSC1` / `74789C88`.  The sensor's line
time is **derived** (frame period over VTS, both measured), not assumed: 36.79 us
(271.8 source rows per 10 ms ripple period, 4349 units of the OV5640 exposure register).
The exposure is now locked to whole periods and the AEC controls brightness with the
**gain**, so the band cancels by construction.  Measured on single-frame reference dumps:
band amplitude **5.41 counts at half a period -> 0.05-0.08 counts at whole periods**; the
comparison's own published row profile went **6.4-7.0 counts -> 0.04-0.07 counts**, and
the frame-to-frame common-mode error `MB_REG_INCERR` went **62..102 (median 84) ->
20..26 (median 22)** with the difference's sigma **78 -> 11** units of 1/16 grey.  131
clean still-scene comparisons on the locked build read 0 cells (coarse) and 0 (fine),
with no PASS at or above the limit.  The hold margins stay **16 / 32**; the reason and the
one calibration item the bench would not allow are in section 6.

## 1. The line time, derived rather than guessed

At boot `sensor_timing_derive()` (main.c:4290, called at 9231) measures the capture
store period on the frame pointer (bit 4 is the Gray LSB of the store index: its sequence
over four stores is 0,1,1,0, so one transition per two stores; first/last transition
timestamps over a ~224 ms window divided by `2*(n-1)`), reads VTS/HTS/PLL over its own
I2C (VTS read twice and required to agree), and publishes the whole derivation:

| word | value on this board | meaning |
|---|---|---|
| MB_FRAME_TICKS 503 | 9,115,101 | capture store period, 334.8 MHz ticks = **27.23 ms** |
| MB_SEN_SIZE 511 | 0x02E40764 | VTS 740, HTS 1892 |
| MB_SEN_TIMING 510 | 0x80211304 | 0x3036=0x80 (PLL mult), 0x3035=0x21, 0x3037=0x13, 0x3824=4 |
| MB_LINE_PS 504 | 36,790 | derived line period, ps = **36.79 us** |
| MB_LINE10 509 | **4349** | one 10 ms ripple period in 1/16-line exposure units |

10 ms / 36.79 us = 271.8 lines = 4349 exposure units.  The OV5640 exposure register is in
1/16 line (application note section 14.1: `shutter = 0x3500<<12 | 0x3501<<4 | 0x3502>>4`);
the old comment calling `MB_AEC_EXP` "lines" was off by 16 and is corrected here.  The
sensors are configured at 0x3036=0x80 / VTS 740 / HTS 1892 (read back, not assumed).

**Known-answer check on the derivation.**  If the illuminant is ~100 Hz, the band's
spatial period must be 271.8 source rows.  The measured period at the exposures where
the band is visible is **266.2 / 268.0 / 268.2 rows** (section 2) -- 1.3..2.1% from the
derivation, which is the accuracy of the fit against a 3-dump phase sample.  A 50 Hz
(20 ms) ripple would need 543.6 rows: the data excludes it.  The 27.2 ms frame time
independently matches the 2026-10-24 capture-ring measurement (27.2 ms/store).

## 2. Step 1 — the band as a function of exposure (measured)

**Instrument.**  `MB_EXP_LOCK` (word 508) pins camera 0's exposure; the AEC then reaches
a usable image with the **gain only** (the "locked exposure" mode; the same lever the
AEC already owns).  For each exposure: settle, take a fresh reference (`MB_CMD = 9`), and
dump `REF_BASE` (0x12400000, 1280x720x3).  REF_BASE is written by `ref_take()` only, so a
dump is ONE frame; a capture-store dump splices ~100 frames with different ripple phases.

**Analysis.**  Two dumps at the same exposure are the same picture plus the band at two
different phases; their row-profile **difference** cancels the scene (which has a large
vertical step: ~40 counts upper half, ~140 lower) and leaves two sinusoids.  Each profile
is divided by its own mean first, so a gain/light change cancels too.  With the period
fixed to the derived 271.8 rows, `A = sqrt(mean(D^2)/2)` over the three pairs.
`ps_ui/stB_pair.py`, raw output `dl/stB_bar_20261024.txt`, dumps `dl/stB_ref_*.raw`.

| exposure (1/16 line) | periods of 10 ms | band A (relative) | band A (counts, belt level) | sinc(T/P) prediction |
|---|---|---|---|---|
| 2174 | **0.50** | 0.0967 | **5.41** (level 56) | 1.00 |
| 3100 | 0.71 | 0.0410 | **3.06** (level 75) | 0.56 (measured 0.42) |
| **4349** | **1.00** | 0.00085 | **0.08** (level 94) | 0.00 |
| 6524 | 1.50 | 0.0164 | **2.03** (level 124) | 0.33 (measured 0.17) |
| **8698** | **2.00** | 0.00036 | **0.05** (level 147) | 0.00 |

The collapse at whole periods is 60-100x against the half-period value, and the two
intermediate points are lower than the ideal box-integration prediction -- either the
integration window is not a perfect box or the 3-pair estimate is noisy (the pair
spreads printed in the log are 14..96% of 2A, i.e. the phases are random as expected).
**The null result that would have refuted the hypothesis did not occur**: the band really
is an exposure-time effect and really vanishes on whole periods.

The pair phase spread is also the known answer that this is the illuminant and not the
scene: the same scene, same exposure, different phase every reference.

## 3. Step 2 — what shipped (`ps_ui/main.c`)

| line | item |
|---|---|
| 2103-2141 | the stage-B word block: MB_FRAME_TICKS/LINE_PS/SEN_TIMING/SEN_SIZE, MB_EXP_LOCK (host), MB_LINE10 |
| 4290-4370 | `sensor_timing_derive()`: the measurement above; fail-safe (a bad read leaves `g_line10 = 0` and the AEC unlocked) |
| 4370-4378 | `g_kmax` = whole periods that fit inside the frame (`(VTS-4)*16 / L10` = 2 here); above it the sensor clamps the shutter and the multiple would be lost |
| 2502-2513 | `g_dhit` (3,600 bytes) moved to DDR at 0x126D8000 to make room; see section 5 |
| 6769-6806 | the locked exposure is resolved before the controller runs and written when it changes |
| 6810-6880 | **the locked-exposure law**: brightness with the GAIN; the period count steps only at a gain rail and only when the host has not pinned the value. 0/1/2/3/4/5/6/7/8/9 `MB_AEC_LAST` codes keep their old meanings |
| 9231 | the derivation is called once at boot, after the sensor writes and before the first AEC evaluation |

The default operating point is the multiple whose 1x-gain brightness is closest to the
old boot point (`CAM_LONG_L * CAM_GAIN`): measured **2 periods (8698), gain 16 (1x),
mean 517 pm**, i.e. the same brightness the old AEC settled on (~500 pm), with one period
of headroom down and the gain range up.  `MB_AEC_EXP` publishes 8698, `MB_AEC_GAIN` 16.

**Camera 1 is NOT changed**: its AEC still runs the old law and its image still carries
the band when the panel shows camera 1.  The comparison, the registration and camera 0's
display (the default view) are the ones this task is about; stated rather than buried.

## 4. Step 2 — the re-measurement

**(a) The band, from the comparison's own published words.**  `MB_DIFF_ROW` (416..460,
45 row means of the live-reference difference, 1/16 grey) fitted at the known 16.99-grid-
row period (L10/256):

| build / exposure | band amplitude, median / max |
|---|---|
| before, stage-A build, legacy AEC (2105 = 0.48 period) | **103-112 units = 6.4-7.0 counts** (8 profiles, `dl/_row_samples.txt`) |
| after, locked 2 periods (8698) | **0.6-1.1 units = 0.04-0.07 counts** (B2/B4) |
| during the disturbed runs (B1/B3) | 0.5-9.4 units (0.03-0.59 counts) -- still ~10x below the old band |

**(b) The frame-to-frame common-mode term.**  `MB_REG_INCERR` (394) is the held
transform's error re-measured on every frame; it is the term that made the margins too
tight (stage 6 measured 62..73):

| build | comparisons | INCERR min/median/max | MB_DIFF_SIGMA median |
|---|---|---|---|
| before (stage-A build, dl/stA_runA2/A3/A4) | 206 | **62 / 84 / 102** | **78-80** units (4.9 counts) |
| after (dl/stB_runB2, B4) | 131 | **20 / 22-23 / 26** | **11-12** units (0.7 counts) |

**(c) The still-scene distribution must not regress — it does not.**  131 independent
comparisons on the locked build (B2 64 + B4 67; fresh reference, N=8, READY 1 and
AVG_CNT 8 on every row, one 1.4 KB burst per row):

| run | comparisons | settle | coarse cells 0 / 1..7 / >=8 | fine cells 0 / 1..7 / >=8 | PASS with over >= limit |
|---|---|---|---|---|---|
| B2 | 64 | 0 | 64 / 0 / 0 | 64 / 0 / 0 | 0 |
| B4 | 67 | 0 | 67 / 0 / 0 | 67 / 0 / 0 | 0 |
| (B0 smoke) | 10 | 0 | 10 / 0 / 0 | 10 / 0 / 0 | 0 |
| **total** | **141** | 0 | **141 / 0 / 0** | **141 / 0 / 0** | **0** |

The coarse raw count in the clean runs is **0** (it was 0..5 with occasional 8 before), and
the decision's own gain (`INCERR - CANDERR`) is **-2..+1** (it was up to 15 across 261
comparisons in stage 6).  **The bench was not still for the whole session**: runs B1 (40
comparisons during a light disturbance) and B3 (57) are reported, not filtered -- 18 and 7
settle slots, INCERR 41..68, sigma 45..48, and in B3 the *fine* count itself reached >=8 in
21 comparisons (verdict NG).  Those runs are the scene, not the fix: their band amplitude
stayed at the after level (section 4a) while the coarse differences on the belt rose, i.e.
the band was gone and something else (the light) moved.  A later calibration attempt hit
the same disturbance (section 6).

## 5. Cost, build, flash

* **One buffer moved to DDR, by name:** `g_dhit`, the 80x45 coarse consecutive-hit array,
  **3,600 bytes**, now at **0x126D8000** (the free hole between FINE_SUM, ends 0x126D7080,
  and BG_BASE, 0x12700000).  It is CPU-only (no DMA, no other master), read and written
  once per comparison.  Nothing else changed address or size.  Reason: with 800 bytes free
  after stage A the linker refused the stage-B image (`section .bss will not fit in region
  ocm`), and shaving working code is not an option.
* `.text` 0x18EBC = 102,204 bytes (+960 for the derivation, the lock, and the moved
  array's code); `.bss` 0x6300 = 25,344 (-3,584, the g_dhit move minus 16 bytes of new
  statics).  Image ends 0x1F220 = 127,520 bytes of 131,072, i.e. **3,552 bytes of OCM
  free** (800 before).
* `build.ps1`: 309 MB_* words, 309 distinct, 0 collisions; all layout checks pass; only
  the four pre-existing warnings.
* Flashed with `ps_fft_dual/strict_load_cores.tcl` (firmware only; no bitstream, no power
  cycle, no running-VDMA poke).  FWID `TSC1` / `74789C88` (= the source hash stamped by
  `dl/build_id.py`; a rebuild reproduced the same hash and image size).
* Board left in the documented state: MB_EXP_LOCK = 0 (a real power cycle reads
  0xFFFFFFFF, also "off"), AEC state 1 at the quantized default (2 periods, gain 16,
  mean ~517), READY 1, AVG_N 8, cells 0, fine cells 0 (`ps_fft_dual/_b_state.tcl`).

## 6. Step 3 — the registration calibration, and whether 16/32 still hold

**What was measured.**  On the clean locked build the decision's own noise -- the gain of
the best wrong candidate, `INCERR - CANDERR`, the quantity `REG_WARM_MARGIN` is set
against -- is **-2..+1** over 131 comparisons (stage 6 measured up to **15** over 261 on
the banded build).  The clean-frame noise floor that a margin of 4 would cover is now
real, i.e. on a quiet bench the admissible window for tracking a 0.1-degree move is much
wider than stage 6's (15, 21).

**Why the margins still cannot move, from today's data.**  During the calibration attempt
(eight averaged lattices, `dl/stb_dump_20261024.txt`) one dump caught the disturbance at
its onset: `INCERR` 46 with a candidate at +0.3 degree and `WERR` 35, i.e. **a wrong
candidate gained 11 units** while the answer was still right.  `REG_WARM_MARGIN` = 16 is
the smallest value that rejects it; lowering the margin to the clean-frame value (4-6)
would have adopted that candidate, which is exactly the stage-6 failure (a wrong
transform held, then cells on a good part).  The upper side is unchanged: a real
half-degree rotation still costs 4..31 units (stage-6 table), so a margin above 31 would
stop tracking real rotations.  **`REG_WARM_MARGIN` 16 -> 16 and `REG_JUMP_MARGIN` 32 -> 32
are kept, and the number that motivates 16 is now measured on the locked build (11) as
well as on the banded one (15).**

**What the bench would not let me finish.**  The *cost* of a known 0.1-degree /
half-pixel error on the current frames needs the stage-6 offline replay: dump the averaged
lattice + reference grey + masks (`ps_fft_dual/st6_dump_20261024.tcl`) and run
`ps_ui/st6_cal_agg.py`.  Two attempts were made and both dumped frames during a light
disturbance (`AVGCNT` 1-4, `READY` 0, sigma 447..520, one reference mask exploded to 2355
points) -- the replay's own validation (`e0 == MB_REG_INCERR`) would have rejected them,
so they are reported rather than used.  **Exact experiment for a human/quiet bench
(~10 min, no operator action beyond leaving the room dark-stable):**
`xsdb ps_fft_dual/st6_dump_20261024.tcl dl/stbDq 12`, then
`python ps_ui/st6_cal_agg.py --log <the printed log> --prefix dl/stbDq --json-out <out>`;
discard any dump whose printed `INCERR` the replay does not reproduce, and compare the
0.1/0.2/0.5-degree and 0.5/1-px rows with the stage-6 table.  If a quiet bench gives a
smaller 0.1-degree cost than 4, a margin below 11 could be re-derived -- not before, and
not on a bench whose light can move.

## 7. What remains unverified, and every human-dependent experiment

1. **The bright-light rail.**  One whole period (10 ms) at 1x gain is the floor of the
   locked mode; a scene brighter than that (measured operating point 517 pm, the clip
   gate at 6 per-mille) cannot be dimmed without leaving the multiples, so the AEC latches
   STUCK and the verdict is CANNOT JUDGE -- fail-safe, but a lost part in a bright room.
   Experiment: add light until `MB_AEC_STATE` = 3, record the mean; decide whether the
   ceiling is acceptable or the bench needs a neutral-density filter.
2. **Camera 1** still runs the old AEC and still bands its view (section 3).  Experiment:
   switch the panel to camera 1 and compare its row profile with camera 0's.
3. **A moving part / conveyor.**  The locked exposure is 20 ms against a 27 ms frame; the
   band is gone but motion blur at 20 ms was not measured (the belt is stopped).  Experiment
   (operator): run the belt and read the fine cell count and `MB_DIFF_FVALID`.
4. **The 100 Hz assumption under a different lamp.**  Everything here rests on the
   illuminant's period; if the room lamp is replaced or run from a different supply, the
   quantum is the same 10 ms only if the ripple is still 100 Hz.  Experiment: re-run the
   exposure sweep (`ps_fft_dual/stB_exp_20261024.tcl` at 0.5/1.0/1.5/2.0 periods, 3 dumps
   each, `ps_ui/stB_pair.py --period <MB_LINE10/16>`) and check that the minima are still
   at whole periods; if the minima move, the ripple frequency changed and `LINE10` must be
   divided by the measured period ratio.
5. **The registration cost table** -- section 6, exact commands given.
6. **The 0.1-degree tracking itself** (requires a person): rotate a part by 0.1 / 0.5 / 1.0
   degrees with the locked exposure and read `MB_REG_MODE`, `MB_REG_MOVE`, `MB_REG_GAIN`;
   with the clean noise floor a 0.1-degree move should now win by more than 1 unit, which
   is the claim a margin below 16 would rest on.
