# 2026-10-30 — the dual-view AND: camera 1 runs the same comparison, the two views are ANDed

> Status: the firmware change, the build and the tooling are done. The bench test below
> is **pre-registered** (written at 11:40, before the first flash of this build) and its
> result is appended at the end under "BENCH RESULT".
> **The AND is unproven.** This document exists so that the run that decides it cannot be
> reinterpreted afterwards.

---

## 1. What the dual-view AND is, and why it could work

Camera 1 already voted, but only as a brightness check: it measured mean, clipping and
staleness (`MB_CAM1_VERDICT`) and never compared anything against a reference. This
change makes it a **second view of the same detector**.

**The mechanism, measured, not assumed.**

| Quantity | Value | Property |
|---|---|---|
| specular difference between two **good** units of this board, at the pads | **168–200 grey** | a property of the **reflection geometry** → moves when the viewpoint moves |
| the measured **scratch** signature | **58 grey** | **not** specular → stable across viewpoints |

So on a good board the pads light up a *different set of cells* in each view, while a real
defect lights up *the same board point* in both. A cell-for-cell AND should therefore
subtract the specular and keep the defect.

**What the 22-board re-scan of the frozen build measured** (the baseline this change is
trying to improve): good side `DAREA` max **3**; and at the zero-false operating point,
**8/12** detected. The AND is the one mechanism left that could lower the good side
further and let the limit drop again. It is unproven.

**The definition, published (new words in §4):** a cell is *seen by both* when **both
cameras' |d| exceed that cell's own tolerance** (`FINE_TOL`, which is per view if the two
tolerances ever differ). The area gate does **not** move: the AND's cell set goes through
**the same connected-group rule** and is judged against **the same limit**
(`MB_DIFF_LIM_USED`, republished as `MB_AND_LIM` with the count it judged).

---

## 2. The lattice argument — what the existing registration does and does not give

**Read from the code** (`reg_score()`, `reg_mask_ok()`, `ref_part_ok()`, `ref_latt_map()`),
not inferred:

* `reg_score(dx,dy,...)` maps a **live** lattice point through the held transform into
  **that view's own reference** and asks whether the baseline mask is part there.
* So a fine cell `(i,j)` in camera 0 means *"the board point that was at camera 0's
  reference pixel (8i,8j)"*; the same `(i,j)` in camera 1 means *"the board point that was
  at camera 1's reference pixel (8i,8j)"*.

**Those are the same board point only if the two cameras see the board identically — and
they do not.** They are a stereo pair, and the entire premise of this change (the specular
moves with the viewpoint) is that they see it differently. There is **no cross-camera
transform anywhere in this firmware**: the registration is per view (live → its own
reference) and nothing maps camera 1's lattice onto camera 0's.

**Therefore the AND is NOT legal as it stands, and the firmware does not pretend it is.**
What it does instead:

* both references are captured from the **same board in the same pose, milliseconds
  apart**, so the board sits at a fixed place in each view's own lattice;
* the offset between those two places is **measured every comparison** as the difference
  of the two part masks' bounding-box centres, and published as `and_ox`/`and_oy`
  (**camera 1's cell = camera 0's cell + (ox,oy)**);
* that absorbs a **translation exactly and nothing else**. A scale or rotation difference
  is **not** compensated, so two words are published with every number to expose it:
  `and_scale` (bbox width ratio, 256 = same size) and `and_ovl` (mask overlap per 1000
  after the offset).

**What full rigour would take:** a reference-to-reference **homography** from the stereo
calibration this project already has (`dl/st6_cal_20261024.json`, RMS 0.137 px), applied
to the cell index — i.e. resampling one view's deep-set into the other's lattice. That is
a firmware change of its own, it needs the calibration in the image, and **it is not in
this build**. It is deliberately not in this build because the bench question today is
"does the AND suppress the specular at all", which a translation can answer if the overlap
is high. If the overlap is not high, the answer is "not interpretable", not "no".

---

## 3. What was changed, and where

| Site | Change |
|---|---|
| `ps_ui/main.c` `view_state_t` | **one state struct, two instances, in DDR at `VIEW_STATE_BASE` 0x11FE4000**. 106 fields previously file-scope statics + the 21 buffer pointers. Every forked static **kept its name and its uses**; only its declaration moved, and `#define g_x (g_cur->s_x)` makes the name mean the current view. A forgotten deletion is a **compile error**, not a silent split. |
| `ps_ui/main.c` buffer macros (21) | rewritten in place: `REF_BASE`, `GREY_BASE`, `BASE_GM`, `LIVE_GM`, `LATT_BASE`, `BG_BASE`, `BG_GRID_BASE`, `LIVE_MASK`, `BASE_MASK`, `BASE_MASK_D`, `FINE_FLAG`, `FINE_HIT`, `FINE_SUM`, `FINE_DEEP`, `FINE_TOL`, `TOL_HDR`, `PART_LATT`, `PART_GMSK`, `PART_CC_TMP`, `PART_CC_STK`, `DHIT` → the current view's field, **same type as before** (integer where every use casts, typed pointer otherwise), so no cast or index changes meaning. |
| `ps_ui/main.c` camera-1 buffers | new region **0x12B00000..0x12E83840** (3.51 MB), 16 KB-aligned regions with a **compile-time overlap guard between every pair** (`#if` — an arithmetic slip fails the build). |
| `ps_ui/main.c` `PB()/PB_AT()` | **every** mailbox write inside the comparison goes through it; while view 1 runs it writes **nothing**. Camera 1's numbers are published afterwards by one function (`cam1_publish()`). |
| `ps_ui/main.c` `diff_frame()` | unchanged arithmetic. Adds: a per-view result capture (`r_darea`, `r_damp`, `r_fcells`, `r_fvalid`, `r_ok`, `r_diffok`), and **the AND's input copied out at the exact instant it exists** (`PART_CC_TMP` right after the fine pass, before `cc_largest()` overwrites it) into `DEEP0`/`DEEP1`. |
| `ps_ui/main.c` `avg_take()` | returns 0 for view 1: the averaging accumulator is camera 0's, and handing it to camera 1 would fill camera 1's lattice with camera 0's picture. **Camera 1 runs the pipeline in its N = 1 mode** (a first-class path in this file), so its per-cell noise is √8 higher at `avg_n` 8 — stated, not hidden. |
| `ps_ui/main.c` `ref_take()` | records **camera 1's own** exposure/gain for camera 1's reference (`MB_CAM1_AEC_EXP/GAIN`), not camera 0's sensor read back over I2C. |
| `ps_ui/main.c` `ref_take_both()`, `cam1_bg_take()` | `MB_CMD = 9` now takes **a reference for each camera**; `MB_CMD = 12` now takes **a background for each camera** — one command each, because the two references must describe the same board in the same pose. |
| `ps_ui/main.c` `dual_view_compare()`, `dual_and_build()`, `cam1_publish()`, `view_init()` | the new driver, the AND, camera 1's publication, and the boot initialiser (DDR has no static initialisers, so all 11 non-zero defaults are applied explicitly and the block is written/read back as proof it exists). |
| `ps_ui/mmu.c` | `map_sections(0x12B00000, 4, AT_WBWA)` — camera 1's region. **No contiguous 2.76 MB hole exists** inside the windows already mapped (largest are 1,429,504 B at 0x102A3000 and 0x122A3000), which is why a new region was needed rather than a hole. |
| `dl/host_qc/qc_mailbox.py` | the 26 new words, **appended** (the read order's old prefix is unchanged). |

**Command to know:** `MB_CMD = 9` (reference) and `MB_CMD = 12` (background) now act on
**both** cameras. Nothing else about the host protocol changed.

---

## 4. The mailbox words — exact indices (588..613, the only free range)

`dl/mb_free.py` (which also taints every index a block write can reach) said **free
588..639** as the only free run above 583..587 — BELT claims 583/584, the gain freeze
585..587 — both with and without the BELT change applied, and `dl/host_qc/qc_mailbox.py`
claimed nothing there either. 614..639 are **left free on purpose**.

| idx | name | writer | meaning |
|---|---|---|---|
| 588 | `and_ok` | PS | 1 = both views judged this comparison and the AND was formed |
| 589 | `and_why` | PS | 0 formed, 1 camera 1 has no usable reference, 2 camera 1 refused, 3 camera 0 refused, 4 one view judged nothing / no part, 5 the per-view state block failed its boot read-back |
| 590 | `and_cells` | PS | cells whose \|d\| exceeds the cell's own tolerance in **both** cameras |
| 591 | `and_darea` | PS | largest connected group of those cells — **the AND's area** |
| 592 | `and_verdict` | PS | 0 pass / 1 NG / 2 cannot judge, from the AND alone |
| 593 | `and_lim` | PS | the limit `and_darea` was judged against (= `diff_lim_used`) |
| 594 | `and_ox` | PS | cross-view cell offset applied, x, signed in the low 16 bits |
| 595 | `and_oy` | PS | same in y |
| 596 | `and_ovl` | PS | the two part masks' overlap after that offset, per 1000 of the smaller mask |
| 597 | `and_scale` | PS | 256 × (camera 1 bbox width) / (camera 0 bbox width) |
| 598 | `and_ms` | PS | ticks camera 1's comparison + the AND took |
| 599 | `view_state` | PS | 1 = the per-view DDR state block read back its pattern at boot |
| 600 | `cam1_diffok` | PS | camera 1's comparison state, same encoding as `diff_ok` |
| 601 | `cam1_darea` | PS | **camera 1's own DAREA** — the per-view number the AND is made from |
| 602 | `cam1_damp` | PS | camera 1's group amplitude, grey |
| 603 | `cam1_fcells` | PS | camera 1's fine cells after the 3x3 + persistence rule |
| 604 | `cam1_fvalid` | PS | camera 1's judged fine cells |
| 605 | `cam1_pts` | PS | camera 1's live part-mask points |
| 606 | `cam1_ref` | PS | camera 1's baseline mask points (0 / 0xFFFFFFFF = no usable reference) |
| 607 | `cam1_refexp` | PS | exposure when camera 1's reference was taken |
| 608 | `cam1_refgain` | PS | gain when camera 1's reference was taken |
| 609 | `cam1_regstate` | PS | camera 1's registration state |
| 610 | `cam1_regerr` | PS | camera 1's registration error at the held answer |
| 611 | `cam1_bgok` | PS | 1 = camera 1 has its own empty-belt background |
| 612 | `cam1_ticks` | PS | ticks camera 1's comparison alone took |
| 613 | `cam1_refq` | PS | camera 1's reference-quality state (0 pass 1 fail 2 not measured 3 declared) |

**Read them as a set.** `and_ok = 0` means **no AND was formed**; `and_darea` is then
0xFFFFFFFF ("not measured") and must never be counted as a clean 0.

---

## 5. The loop budget

**Before this change, measured on the station (build `TSC1BE7E51A4`, the station's own
instrumentation, this session):**

| word | value | meaning |
|---|---|---|
| `MB_T_TOTAL`/`MB_T_N` | 1,891,975,040 ticks / 32 loops | **loop 177.33 ms** |
| `MB_DIFF_MS` | 45,404,493 ticks | **comparison 136.18 ms** |

`MB_DIFF_MS` is timed from *before* `cap_ho_sample()` and the 2.76 MB `dcache_invalidate`
to the end of `diff_frame()`, so it is "the comparison slot", not the comparison's own
arithmetic. (The brief cites 91.1 ms for the comparison; that number is **not**
reproducible on this build/station today — 136.18 ms is what the word reads — and the
difference is reported rather than smoothed over. The loop's 176.6 ms *is* reproduced:
177.33 ms.)

**"Running the comparison twice" is measured, not assumed:** see §7, where the same two
words are read after the change, together with `MB_CAM1_TICKS` and `MB_AND_MS`.

**Prediction, written before the run:** the comparison **slot** goes from ~305 ms
(168.8 ms baseline loop + 136.18 ms of comparison) to **~440–450 ms**, and the *average*
loop from 177.3 ms to **~186 ms** — because the comparison runs one loop in `DIFF_EVERY`
= 16. If the measured comparison slot exceeds **~400 ms**, the cheapest reduction is
**not** to accept it: see §8.

---

## 6. THE BENCH TEST — criterion written BEFORE the run

**Station establishment after flashing (in this order — the order matters):**

1. **Pin the exposure at the AEC's own equilibrium.** `MB_AEC_PIN` (word 508) = 0, wait
   for `aec_state = 1`, then write the current `MB_AEC_EXP` (word 145) back to 508.
2. **Capture the empty-belt background** with `MB_CMD = 12`. Want `bg_state = 1`,
   **`bg_cells ≈ 0`**. This must come **before** the reference: camera 1's baseline mask
   uses the background rule only if camera 1 has a background, and if it does not, the
   two views' baselines would be built by **different rules**.
3. **Take the reference** with `MB_CMD = 9` — this now takes **one for each camera**.
   Want `part_ref ≥ 400`, `diff_ok = 1`, and **`cam1_ref ≥ 400`**, `view_state = 1`.

**Then the same four boards: `d30`, `d23` (scratches) and `g11`, `g14` (the two good
boards whose DAREA was 5 and 7 — the worst of the population).**

For each board, record in this order:

* `diff_darea` (camera 0) and `cam1_darea` (camera 1) — **both per-view numbers**;
* `and_cells`, `and_darea`, `and_verdict`, `and_lim`;
* **`and_ovl` and `and_scale`** — the mapping's own evidence;
* `and_ok`/`and_why`; if `and_ok = 0` the row **is not a measurement**.

**THE CRITERION (this is the decision, and it does not move afterwards):**

> **The two GOOD boards' `and_darea` must fall BELOW the limit in force (`and_lim`,
> currently 8) while BOTH scratches' `and_darea` stays above it.**
>
> **And the failure mode is named in advance:** if the **scratches' AND also falls**, the
> AND has killed the defect together with the specular. That is a **negative result and
> must be reported as one** — not worked around by lowering the limit, not re-run until it
> looks better.
>
> **Mapping gate, applied before the criterion is judged at all:** a row whose
> `and_ovl` is low (rule of thumb: below ~600 per 1000) or whose `and_scale` is far from
> 256 is a statement about the **mapping**, not about the board, and does not decide
> anything. Say so instead of scoring it.

**If the station cannot be driven safely (an xsdb or AEC problem), stop and report rather
than improvising.**

---

## 7. BUILD FACTS

| | before (HEAD + uncommitted BELT) | this build |
|---|---|---|
| build id (words 168..170) | `TSC1BE7E51A4` | **`TSC1AEA35B84`** |
| source hash | — | `AEA35B84`, 13 files |
| ELF | 202,752 B | **203,072 B** |
| `.bin` (what is loaded) | 120,884 B, ends 0x1D834 | **124,068 B, ends 0x1E4A4** |
| `.text` | 120,768 | 123,984 |
| `.data` | 116 | 76 |
| `.bss` (at 0x24000) | 12,132 | **6,672** (−5,460: the forked arrays moved to DDR) |
| OCM free below the page table (0x20000) | 10,188 B | **7,004 B** |
| `.bss` free below the stack (0x2F000) | 32,924 B | 38,384 B |
| warnings | 4 | **4, the same four** (`dcache_invalidate` implicit + conflicting types, `always_inline`, `wait_probe_edge`) |

**ELF scan** (`dl/check_mb_words_elf.py --low 588 --high 613`): every one of the 26 words
is referenced; the references come only from `main_loop` (where `dual_and_build`,
`dual_view_compare`, `and_publish_invalid` were inlined), `cam1_publish` and `view_init`;
**no** reference from `diff_frame`, `ref_take`, `bg_take`, `part_masks`, `part_track`,
`reg_search`, `reg_adopt`, `tol_boot`, `tol_reset`; and **no** raw little-endian address
of the range anywhere in the image's literal pools or data. No computed-index block write
can reach the range: `dl/mb_free.py` taints `MB_DIFF_ROW + gy` = 416..460 as the highest
block write, and the literal offsets are words 160..163.

---

## 8. BENCH RESULT — **BLOCKED, NO NUMBERS**. The station's CPU→PL path is broken.

**Nothing below was measured, and nothing below may be guessed at.**

**What happened, in order.**

1. The dual-view image was downloaded and **verified against the file** (130 sampled words,
   0 mismatches). The first start attempt used `stop` + `dow -data` + `PC=0` + `con`, the
   same shape as the project's `ps_dow_only.tcl`. The board came back with the **old**
   build id still in the mailbox and `FAULT = 0x11111104` — so the download had not taken
   effect: OCM is mapped write-back, the old program was running with the D-cache on, and a
   JTAG download does not touch it. The core resumed and executed **stale cached lines**.
2. The second attempt added `rst -processor` before the download — the textbook fix for
   stale code in cached memory. **This is what broke the station:** from that moment every
   **CPU access to a PL register** aborts.

**The evidence that it is the station and not this build.**

| test | result | what it rules out |
|---|---|---|
| `FAULT`/`FAULTPC`/`DSFR`/`DFAR` | `0x11111104` / `0x00010230` / `0x00000406` / `0x00000000` | — |
| the faulting instruction (objdump) | `ldr r3, [r2, #8]` with `r2 = 0x41200000`, i.e. a read of **CAP_FRPTR = 0x41200008**, a PL register | a null pointer, a bad stack slot: the address is computed from a constant |
| `PROGRESS` (word 11) at the fault | **1 = `PG_LOOP`**, the first beacon of the loop, immediately before the loop's first PL read | a crash during boot, view_init, mmu_init, the reference, the AEC |
| **THE PRE-CHANGE BUILD**, rebuilt from `backups/20261030_112705__20261030_before_dualview_and/` (120,884 B, byte-for-byte the size of the image that had been running for hours) and loaded the same way | **faults identically**: `FAULT 0x11111104` at its own PL read, `PROGRESS` also stalled at 1 | **the dual-view change.** The unmodified program dies the same way on this station now |
| PL→DDR still alive? | both capture stores written every frame, **32/32 sampled words change per 1.5 s**, both VDMA `CR = 0x00010003` | a dead fabric or dead cameras |
| JTAG→PL still alive? | `0x41200008 = 0x0000099A` (the frame pointer, advancing), `0x43000030`, `0x44A00030`, `0x43010000` all sane | a blank or unprogrammed PL |
| page table (read over JTAG) | entry for section `0x412` = `0x41200C16`, a valid device descriptor | a missing MMU mapping for the PL window |

So: **the fabric is configured and capturing, the host can read every PL register, and only
the CPU's AXI path to the fabric is gone.** The project has already recorded this exact
failure and its cause — `ps_fft_dual/bringup_fw.tcl` line 5: *"a PS reset leaves the
PL-side AXI path unusable -- measured as VDMA SR=0x10021 / DMASlvErr"*. That is what
`rst -processor` did here.

**Why I did not repair it myself.** The repair is not a firmware step: it is
`rst -system` + `ps7_init` + `ps7_post_config` + **re-programming the fabric** +
`sensors_init` + re-arming both capture channels and the display channel. Re-programming
the fabric throws away every VDMA/display register the station is running on, and the
`ps7_init` variant decides the PS/PL clocks — i.e. the repair can silently change the very
station the 22-board baseline was measured on. That is a change to the owner's live
instrument, not a file edit, and it is the case the brief named as "stop and report rather
than improvising".

**The exact recovery order (for whoever sequences it).**

```
xsdb> connect
xsdb> targets -set -filter {name =~ "*Cortex-A9*#0"}
xsdb> rst -system                       ; after 1500
xsdb> source ps_fft_dual/ps7_init*.tcl  ; the SAME variant the station used (50m or not)
xsdb> ps7_init ; ps7_post_config
xsdb> targets -set -filter {name =~ "*xc7z020*"} ; fpga -f safe_bitstreams/BIT_20261028_plfe_attempt.bit
xsdb> targets -set -filter {name =~ "*Cortex-A9*#0"} ; source ps_fft_dual/sensors_init.tcl
       (I2C answers only in the same session as ps7_init -- AGENTS.md)
xsdb> source ps_fft_dual/stereo_both.tcl    ; both capture channels + the 0x11D00000 store map
       + the display channel arming (ps_run.tcl's MMIO section, or ps_display.tcl)
xsdb> xsdb ps_fft_dual/dualview_start_20261030.tcl   ; downloads, verifies, starts, and
       refuses if CPU->PL is still broken
       then section 6: pin the exposure, MB_CMD = 12 (background), MB_CMD = 9 (reference)
       then the four boards.
```

**The board is left in a defined state:** OCM holds the dual-view image
(`word0 = 0xEA000006`, `word[0x20] = 0xEE110F10`), the core is **halted at PC = 0 and not
running**, both capture channels are still armed and still writing their stores, and no
mailbox word was left claiming a measurement this build did not take.

**Consequences for this document.**

* **THE FOUR-BOARD RUN DID NOT HAPPEN.** `d30`, `d23`, `g11`, `g14` were not placed and no
  per-view DAREA, AND count or verdict exists. Section 6's criterion is still the criterion
  and it has not been met, failed, or reinterpreted.
* **THE NEW LOOP TIME IS NOT MEASURED.** The board never executed the second comparison
  past its first loop, so `MB_CAM1_TICKS` and `MB_AND_MS` hold the boot seeds (0) and
  `MB_T_TOTAL/MB_T_N` describes the *previous* build. The prediction in §5 stands
  unconfirmed: comparison slot ≈ 440–450 ms, average loop ≈ 186 ms. **This is an open item,
  not a result.**
* **IT IS NOT PROVEN THAT THE SECOND PASS WORKS AT ALL ON HARDWARE.** What is proven is
  that it compiles against the real tree, that its state block passed its own read-back
  (`MB_VIEW_STATE = 1` was observed on the board), that the mailbox words are mapped and
  referenced only from the expected sites in the built image, and that the host map agrees
  with the firmware. Everything about the AND's *numbers* is untested.

