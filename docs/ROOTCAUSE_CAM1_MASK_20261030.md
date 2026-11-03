# 2026-10-30 — camera 1's live mask: the root cause, the fix, the diagnostics, and the gate

> **Status: the fix is built, loaded and measured.** Sections 1–7 were written before the
> load and are unchanged (the gate was pre-registered). Section 8 is what the board said,
> and section 9 lists what is still open. Flashed image: **`TSC1EF097D3C`**.

---

## 1. The question, and the four measurements that framed it

On an empty belt, with a freshly captured background, firmware `TSC19FCEAB62`:

| word | value | meaning |
|---|---|---|
| `MB_CAM0_PTS` (`part_pts`) | **0** | camera 0: nothing in view, correct |
| `MB_CAM1_PTS` (605) | **3044** | camera 1: "a part" on an empty belt |
| `MB_CAM1_REF` (606) | **3060** | camera 1's reference (taken with a board) |
| `MB_CAM1_DIFFOK` (600) | **6** | part not fully in view |
| `MB_CAM1_REFQ` (613) | **1** | reference quality failed |
| `MB_CAM1_BGOK` (611) | **1** | camera 1 HAS a background, so the background rule is in force |
| `and_ok / why` | 0 / **2** | the AND refused: camera 1 refused |

The brief's four zero-build tests had already eliminated: a decaying persistence (ten
consecutive reads are constant at 3044), a stale frame (five `MB_CMD = 12` captures give
3044 every time), a brightness difference (exposure 8662 and gain 16 are bit-identical on
both cameras, and both means read ~500 ‰ — `dl/CAM1_EXPOSURE_20261030.md`).

Two observations were left over, and they are what the answer had to explain:

1. **the number moves with the scene** — 3017 with the board present, 3044 without. A
   latched or stored mask cannot do that, so the live mask IS being recomputed;
2. **but it is always about the size of the board** (≈3044 of the 6,400 cells the belt
   band allows, i.e. ~48 % of the band), so what it is computed against does not describe
   the empty belt.

## 2. The root cause, in one sentence with the code site

**Two defects, both in the camera-1 path, and the mask needs both fixed: (i) camera 1's
live pass is skipped whenever camera 0 refuses — and on an empty belt camera 0 ALWAYS
refuses — so the published mask is the one from the last comparison camera 1 actually ran;
and (ii) when that pass does run, the background GRID it subtracts has been overwritten by
the background PICTURE, because the camera-1 table declared a 691,200-byte buffer as
51,136 bytes and put the grid 65,536 bytes into it.**

### (i) the pass that does not run — the direct cause of "not recomputed"

`ps_ui/main.c`, `dual_view_compare()`: the first statement used to be

```c
if (view_peek(0u)->r_ok == 0u) { and_publish_invalid(3u); return; }   /* "must not cost 140 ms" */
```

Camera 1's mask is rebuilt only inside its own `diff_frame()`. On an empty belt camera 0's
`diff_frame()` refuses every comparison (`MB_DIFF_OK = 5`, no part in view → the
registration has nothing to lock onto), so `r_ok` is 0 on every slot and camera 1's pass
never ran: `MB_CAM1_PTS` could only ever hold the value of the last comparison camera 1
did run, which was one with a board in view.

**Proven from the mailbox alone, no dump:** `and_why` read **3** while `cam1_diffok` read
**6**. The AND's gates test camera 1 first (`why = 2`), so a camera 1 that had refused in
this very comparison would have produced 2; 3 therefore says camera 1's pass did not run,
and the 6 is a stale code from an earlier one. That is the "0.5 % match" between
`MB_CAM1_PTS` (3044) and `MB_CAM1_REF` (3060): both describe the same board-present frame,
one as a stored baseline and one as the last live number.

### (ii) the grid that is overwritten — why the pass would still be wrong

* `ps_ui/main.c`, camera-1 buffer table: `BG1_BASE = 0x12E30000`, declared `0x0C7C0`;
  `BG_GRID1 = 0x12E40000`. The image really is `BG_W*BG_H*3 = 640*360*3 = 691,200 =
  0xA8C00`, so it runs 0x12E30000..0x12ED8C00 and covers **15** of the block's own
  buffers: `BG_GRID1`, `FINE_FLAG1`, `FINE_HIT1`, `FINE_SUM1`, `FINE_DEEP1`, `FINE_TOL1`,
  `TOL_HDR1`, `PART_LATT1`, `PART_GMSK1`, `PART_CC1_TMP`, `PART_CC1_STK`, `DHIT1`,
  `DEEP0`, `DEEP1`, `ANDM`. Overrun: 625,664 bytes.
* `bg_take()` (main.c): fills `BG_GRID_BASE` from the frame, then calls `bg_copy_half()`,
  which writes the whole 691,200-byte image. **The grid is written first and destroyed
  second, in the same function.**
* The compile-time guard tested the wrong size — `#if (BG1_BASE + 0xC7C0u) > BG_GRID1` —
  so the overrun passed the build.

Why (ii) produces ≈half a band: `part_masks()`'s background rule publishes "cells where
|live − background| > 24". With the grid replaced by raw RGB bytes (an image slice,
1,920-byte rows) the field being subtracted is not the empty belt at all, so a large
fraction of the band exceeds the threshold on any scene and the cells reach the frame/band
border — which is the refusal code 6 and the reference-quality failure.

It also explains the one thing the band did NOT fix. Before the band, the whole-frame
variant of this mask exceeded `BG_AREA_MAX` (7,200) and the rule fell back to the colour
rule (the 3408 of `TSC1AEA35B84`); with the band the mask is cut to 6,400 cells first, so
it stays under the area gate, the corrupted background rule runs, and the count lands at
3044 — a different number with the same cause.

## 3. The measurement, with its controls (read-only; no build, no write)

`ps_fft_dual/_roi_root_20261030.tcl` read four 14 KB regions from the running board and
`dl/_roi_root_check_20261030.py` decided what kind of object each one is. An address
cannot be tested for aliasing by reading it, so the test is about **content**: an 8×8
green-mean grid has no channel phase and a 160-byte row pitch; RGB image bytes have both.

| region | phase-3 spread | corr(lag 160 B) | corr(lag 1,920 B) | verdict |
|---|---|---|---|---|
| camera 0's grid (control, known good) | 0.10 | **+0.978** | +0.547 | GRID |
| camera 1's live lattice (control) | 0.36 | **+0.927** | +0.505 | GRID |
| camera 1's frame store (control, image) | 22.99 | +0.365 | +0.323 | IMAGE |
| **camera 1's BG "grid" @ 0x12E40000** | **13.81** | **−0.102** | **+0.977** | **IMAGE** |

The two controls that must come out GRID do, the one that must come out IMAGE does, and
the suspect region behaves like the image control and unlike both grids. **The bytes the
camera-1 part mask subtracts from are image bytes.** The arithmetic in the source and this
measurement agree; neither alone would have been enough.

Live state read in the same session (`ps_fft_dual/_roi_root_20261030.tcl`):
`FWID = TSC19FCEAB62`, `frames 27337`, `diff_n 804`, `roi614 = 0x00590032`,
cam0 `pts 0 / ref 592 / diffok 5 / refq 0 / bg_state 1`,
cam1 `pts 3044 / ref 3060 / diffok 6 / refq 1 / bgok 1`,
`and ok 0 why 3`, cam1 `exp 8662 vts 740 k 2 state 1 mean 513` — i.e. the same state the
brief describes, measured again before the change.

## 4. The fix

| site | change |
|---|---|
| `main.c` `dual_view_compare()` | **the early return on camera 0's refusal is gone.** Camera 1's pass runs on every comparison slot; the AND is still refused, by `dual_and_build()`'s own gates. Stated cost: a slot on which camera 0 refuses now pays camera 1's pass (~140 ms, published in `MB_CAM1_TICKS`) — +8.8 ms on the average loop at one comparison per 16 loops, measured in `MB_T_TOTAL`/`MB_T_N`. |
| `main.c` camera-1 table | `BG1_BASE` → **0x12E84000** (first 16 KB boundary after `ANDM`), `BG_GRID1` unchanged at 0x12E40000 — nothing writes over it any more. `BG1_BYTES = 0xA8C00` is now a named constant, and `typedef char bg1_size_must_equal_bg_bytes[(BG1_BYTES == BG_BYTES) ? 1 : -1]` makes the declared size and the size `bg_copy_half()` writes one object that cannot disagree. |
| `main.c` guards | the bogus `0xC7C0` is gone: the guard is `BG1_BASE + BG1_BYTES > V1_MAPPED_END`, and a new guard chain covers the two evidence grids. |
| `ps_ui/mmu.c` | the camera-1 window is **5 sections** (0x12B00000..0x12FFFFFF) because the image now ends at 0x12F2CC00. |
| camera 0 | **not touched.** No camera-0 address, mask expression, count or published word changed. The only additions on its path are one counter increment per comparison and one 16-bit evidence store per judged fine cell (section 5) — neither is read by any camera-0 decision. |

The 80 KB hole the move created is not left as a hole: it holds the two signed-residual
evidence grids (section 5), so the block stays consecutive and every byte of it has an
owner and a guard.

## 5. The diagnostics, in the same build (words 615..634)

| word(s) | what it answers |
|---|---|
| 615/616 `MB_V0_FRAME`/`MB_V1_FRAME` | how many times each view's live mask has been rebuilt from a frame. "Is it recomputed at all" is now a read; the 2026-10-30 diagnosis got this question wrong once. |
| 617/618 `MB_V0_BGFR`/`MB_V1_BGFR` | the same counter at the moment that view's background was captured (0xFFFFFFFF = none), so "was the background taken after the belt was cleared" is a comparison, not an inference. |
| 619 `MB_V1_SIGMA` | camera 1's residual sigma in 1/16 grey, from the SAME statement that already computes camera 0's `MB_DIFF_SIGMA` — no new pass. It is a single-frame (N=1) residual, not a temporal sigma; stated in the code and in the host map. |
| 620 `MB_IGN_REF` | HOST. 1 = the judged ROI ignores the reference's part mask (the one place a reference can influence a mask-shaped number, `ref_part_ok`). Makes "does the mask read the reference" one write. Cleared at boot. |
| 621..630 `MB_CAM1_ROWH0..9` | camera 1's live mask in ten 9-row segments, so the row distribution is readable without walking the ROI word. Their sum equals `MB_CAM1_PTS` by construction. |
| 631..633 `MB_CAM1_EXP_NOW/CEIL/HEAD` | camera 1's shutter against its own ceiling `(VTS−4)·16`, with the remainder: VTS 740 vs camera 0's 1200 caps camera 1 at 61.5 % of camera 0's shutter. (The ceiling in 10 ms periods was already word 528.) |
| 634 `MB_BUILD_ID` | the source stamp's eight hex digits as one number (`0xEF097D3C` for this build), so "which image is running" is one read. |

Free range check: `dl/mb_free.py` reports **free 615..639** (25 words) with the BELT,
GAIN FREEZE, DUALVIEW and CAM1-ROI changes applied; the host map
(`dl/host_qc/qc_mailbox.py`) claimed nothing there. 615..634 are now claimed, 635..639 stay
free. `dl/check_mb_words_elf.py` scans the ELF for the whole range because a name check
cannot see a word reached through `MB_X + i` or a literal offset.

### The evidence buffers (the external review's request, granted)

The same build stores the two things that turn "would statistic X work under the AND?"
into an offline question:

| buffer | address | meaning |
|---|---|---|
| `D0_SIGN` | 0x12E30000 | view 0's **signed** residual d, one `int16` per fine cell; `−32768` = not judged |
| `D1_SIGN` | 0x12E38000 | the same for view 1 |
| `ANDM` | 0x12E80000 | the AND per cell: **1** formed, **0** not, **2** the gate refused this comparison |

`int16` and not a signed byte because the measured specular reaches 168..200 grey and a
byte would clip exactly the population the AND exists to suppress. Both grids are filled
with the "not judged" sentinel at boot, so a dump taken before the first comparison says
so instead of showing DDR garbage. `ps_fft_dual/evidence_dump_20261030.tcl` reads all of
it — plus both part masks, the tolerance maps and the state words — in one command, with
the core stopped so the snapshot is one comparison.

## 6. The gate, written before the load

Order is mandatory; a failure stops the run (the brief's C1 → C2 → C3 → C5).

| # | test | prediction |
|---|---|---|
| **C1** | empty belt, no command, 10 reads 1 s apart | camera 1's `pts` is **constant** and **≤ 100** (camera 0 is 0). A few dozen is plausible; hundreds is not. |
| **C2** | five `MB_CMD = 12` in a row | the five readings are **identical** (the background is a photograph of a static belt; a correct grid is idempotent under re-capture). |
| **C3** | both cameras at the same exposure/gain (measured identical: 8662 / 16), empty belt | the two `pts` are the **same order**: |cam1 − cam0| ≤ 100, against today's 3044 vs 0. |
| **C5** | board on → board off + background re-captured | board on: cam1 `pts` **rises above 400** (a part is in view); board off + `MB_CMD=12`: back to C3's baseline **within ±100**. |
| **C6** | (free, same build) `MB_IGN_REF = 1` with the belt empty and a board on | `MB_CAM1_PTS` **unchanged** (the mask does not read the reference) while `MB_CAM1_FVALID` moves. |
| **C7** | (free, same build) the row histogram | `sum(MB_CAM1_ROWH0..9) == MB_CAM1_PTS` on every reading; with a board, the mass sits in segments 6..9 (cell rows 54..85 measured from camera 1's own dumped frame). |
| **C8** | (free, same build) the exposure words | `MB_CAM1_EXP_CEIL = 11,776`, `MB_CAM1_EXP_NOW = 8,662`, `MB_CAM1_EXP_HEAD = 3,114` — the headroom stated in the brief's own units. |

**If C1–C3 fail, the root cause in section 2 is WRONG**, even though the byte-level
measurement in section 3 is right: it would mean the corrupted grid is not what the mask
reads, and the run stops there rather than moving the band.

Only after C1–C5: the two references, `and_ovl`/`and_scale` written down BEFORE any board
is placed, then `d30`, `d23`, `g11`, `g14` — both views' DAREA, `and_cells`, `and_ovl`,
`and_scale`, the verdict, against the pre-registered criterion of
`dl/DUALVIEW_AND_20261030.md` section 6, unchanged.

## 7. What is NOT proven by this change

* The AND itself remains **unproven** (it has never formed on this station).
* Camera 1's **reference quality** diagnostics: only the state word is per view; words
  545..550 remain camera 0's. `MB_CAM1_REFQ = 1` will be explained by the refusal it
  produces, not by a per-view quality number.
* The **sampler mismatch**, found while reading `part_masks()` and NOT fixed here: the live
  lattice comes from `latt_point()` (green taps at cell +0/+1 px) while the background grid
  comes from `bg_cell_mean8()` (taps at +0/+4 px). The comment at `bg_diff_fill()` claims
  they are the same arithmetic; they are not. On a smooth belt the residual is a few
  counts, far below `BG_MASK_THR` (24) — camera 0's empty-belt count of 0 is the evidence —
  so it is not this defect, and changing it would change the camera-0 path the 22-board
  population was measured through. Recorded, not touched.
* Camera 1's mask still runs with **N = 1** (no accumulator of its own), so its sigma is a
  single-frame residual. Unchanged by this build; `MB_V1_SIGMA` is what measures it.

---

## 8. What the board said (measured, 2026-10-30 16:5x–17:0x)

**Load:** `ps_fft_dual/strict_load_cores.tcl` — the loader that has never failed. Verified
afterwards by `_postload_20261030.tcl`: stamp `TSC1EF097D3C`, `MB_BUILD_ID` 0xEF097D3C,
`view_state` 1, `MB_PS_FRAMES` advancing, and **both views' live-mask counters equal and
advancing (v0 = v1 = 24 → 27)** — the first direct proof that camera 1's pass now runs.
No fault; the fault block still held the PREVIOUS build's record (`FAULT 0x11111104`,
`FAULTPC 0x1E`, DFSR/DFAR 0), which is stale because the loop keeps advancing.

| gate | predicted | measured | verdict |
|---|---|---|---|
| **C1** 10 reads, 1 s apart | constant and ≤ 100 | **0 0 0 0 0 0 0 0 0 0**, `v1_frame` 63 → 68 across the reads (camera 0 also 0) | **PASS** |
| **C2** five `MB_CMD=12` | identical | **0, 0, 0, 0, 0**; `v1_bgfr` moved 69/70/72/73/75 | **PASS** |
| **C3** empty belt, both views | same order (≤ 100 apart) | cam0 **0**, cam1 **0**, difference **0** (was 3044 vs 0) | **PASS** |
| **C6** `MB_IGN_REF=1` | `cam1_pts` unchanged | unchanged (0 → 0) | **PASS, WEAK** — see below |
| **C7** histogram sum | equals `cam1_pts` | 0 = 0, MATCH | **PASS, WEAK** — see below |
| **C8** exposure words | 8662 / 11776 / 3114 | **8662 / 11776 / 3114**, VTS 740, k = 2, kmax = 2 | **PASS** |
| **C5** round trip | — | **NOT YET RUN** (needs the operator to place and remove a board) | **OPEN** |

**The byte-level before/after, same test, same controls** (`_roi_root_check_20261030.py`,
the camera-1 background grid at 0x12E40000):

| region | phase-3 spread | corr(160 B) | corr(1,920 B) | verdict |
|---|---|---|---|---|
| camera 0's grid (control) | 0.17 | +0.978 | +0.546 | GRID |
| camera 1's live lattice (control) | 0.36 | +0.927 | +0.505 | GRID |
| camera 1's frame store (control) | 22.99 | +0.365 | +0.323 | IMAGE |
| **camera 1's BG grid, BEFORE the fix** | **13.81** | **−0.102** | **+0.977** | **IMAGE** |
| **camera 1's BG grid, AFTER the fix** | **0.13** | **+0.971** | **+0.528** | **GRID** |

The suspect region moved from the image column to the grid column of a test that separates
both known grids from a known image in the same run. The two grids' means are 129.9
(camera 0) and 133.2 (camera 1) — the same belt, seen by two cameras at the same exposure.

**The evidence buffers, checked on the same dump** (`evidence_dump_20261030.tcl`): with no
reference taken yet, all 14,400 cells of both `d0`/`d1` read the "not judged" sentinel and
all 14,400 `and.raw` bytes read **2** (the gate refused) — i.e. the dump says "nothing was
judged" instead of showing DDR garbage or a previous comparison's grid.

## 9. Still open

1. **C5**, the round trip (the operator places and removes one board). Everything about
   "the mask follows the frame" rests on it; C1 alone cannot distinguish a live 0 from a
   stored 0.
2. **C6 and C7 were measured at 0 and are therefore WEAK.** "0 did not change" and
   "0 = 0" are true and not informative: both must be repeated with a board in view, where
   the mask is a few thousand cells. `roi_gate_c5_20261030.tcl` re-checks C7 with the board
   on; **C6 with a board on is still owed** and is a one-word write once a board is placed.
3. The **AND itself** — still never formed on this station. The criterion of
   `dl/DUALVIEW_AND_20261030.md` section 6 is untouched.
4. `d30`, `d23`, `g11`, `g14` — not run.
5. `MB_V1_SIGMA` read `0xFFFFFFFF` (not measured) on the empty belt, because a comparison
   that refuses before the cell pass has no residual to measure. It will read a number as
   soon as a comparison reaches the cell pass (a board in view).
6. **The named pre-load liveness check `MB_DIFF_N` does not work on an empty belt.** It
   counts SUCCESSFUL comparisons, so with nothing on the belt it stands still while the
   loop is perfectly alive (measured: 804 → 804 over 4 s, frames advancing). The check that
   does work is words 615/616 — the per-view live-mask rebuild counters — which is one of
   the reasons they were added. Any future "is it running" test should read those.
7. **The display was not looked at** by anyone in this session; nothing here claims the
   panel shows anything.

### The cost of always running the pass, measured (not estimated)

The code comment in `dual_view_compare()` says a refusal slot now "pays camera 1's pass
(~140 ms)". That figure is the FULL pipeline (registration + both cell passes) and it is
the wrong number for the case it describes: on a refusal slot camera 1 stops at the same
early gate camera 0 does, so it never reaches the registration or the fine pass. Measured
on the station after this change (`MB_T_TOTAL`/`MB_T_N`, `MB_CAM1_TICKS`):

| quantity | value |
|---|---|
| loop time | **138.5 ms** per loop (32 loops) |
| camera 1's pass on a refusal slot | **45.1 ms** (`MB_CAM1_TICKS`) |
| implied average loop cost | **+2.8 ms** (one comparison every 16 loops), i.e. +2 % |

The comment is left as it is **on purpose**: editing it would change the source hash in
`build_id.h` and orphan the stamped image that is on the board. The measured figure is
here, next to the measurement, and the correction belongs in the next build's comment.


