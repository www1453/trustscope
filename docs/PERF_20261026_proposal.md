# Why one comparison reads 167 ms (the 2026-10-24 build read 91 ms), and the cheapest change to move it

Offline analysis, 2026-10-26. **No board access, no build, no flash, nothing applied.**
Firmware analysed: `ps_ui/main.c` at **HEAD `845be5d`** (all `ps_ui/main.c:<n>` below are HEAD line
numbers). The working tree was being edited while this was written (`camera 1`/`aec_control`,
+55 lines at 20:52) — re-check any cited line against `git show 845be5d:ps_ui/main.c` before editing.

Measurement sources, all already on disk:

| source | what it gives |
|---|---|
| `dl/xcheck_20261026/goodA/capture.json` (19:51) and `goodA2` (19:53) | one full mailbox snapshot each: `MB_DIFF_MS` 55,992,504 and 55,946,155 ticks = **167.24 / 167.10 ms**, `MB_AVG_N` 1, `MB_AVG_CNT` 1, `MB_REG_TICKS` 5,588,706/5,584,882, `MB_BLOB_TICKS` 619,496/705,723, the eight `MB_T_*` window sums, `MB_CAP_DEC` 0, `MB_CAP_WAITS` 9,268/24,267 |
| `dl/PART_MASK_PERFRAME_20261026.md` §3-4 | the per-loop-mask A/B: loop 104.9 → 138.0 ms, class 15.6 → 35.7 ms, pass 4.83 ms, and the rejected full `part_masks()` at **20.3..26.0 ms per call** |
| `.tmp/ab_segA.csv` / `ab_segB.csv` (19:22) | 158 live `MB_PART_TK_MS` samples: min 4.77, **median 4.83**, max **22.53 ms**; the TK_ON=0 arm is frozen at 4.83 ms (the word is only written when the pass runs) |
| `dl/STAGE8_20261024_fine_cells_and_adaptive.md` §6 | the 91.1 ms comparison, the 137.4 ms loop, the sampler at 28.4 ms, `AVG_CNT` 8 in 196/196 |
| `dl/NG_GOODBOARD_20261026.md` §5 | the 2026-10-26 averaging A/B (sigma16 38.1/37.5 at N=1 vs 34.6/41.1/42.4 at N=8) |
| `dl/STAGE2_20261024_average.md` | the 10-24 averaging acceptance: cells>=8 in 2/43 at N=1, 0/47 at N=8; sigma16 med 115 vs 71-74 |
| `dl/EVIDENCE_20261026.md` §4 | `MB_EVID_TICKS` 10,277,315 = **30.7 ms** for the NG evidence copy |

---

## 0. The one-paragraph answer

`MB_DIFF_MS` is not "the comparison's arithmetic". It is the wall time from just before the capture
store is selected to the end of `diff_frame()`: it contains a bounded capture-handover wait, a 2.76 MB
D-cache invalidate, and then roughly **7 frame-reading passes over the same 2.76 MB store** plus the
registration search, the two-rule part mask, the fine pass and the contour pass. At **N = 1** (which
is what both 167 ms snapshots were taken with) three of those passes — the lattice, the 16x16 cell
means and the 8x8 fine means — are computed *inside* `diff_frame()`; at **N = 8** (the 10-24 build,
`AVG_CNT` 8 in 196/196) they are computed by `avg_sample()` outside it and `diff_frame()` reads
precomputed sums. So part of the 76 ms difference is a measurement-arm difference, and part is two
new passes added after 10-24 (`gm_latt_fill`, the background mask rule + always-on green audit).
The loop itself is **not** slower: 99.3 ms now (N=1) against 137.4 ms on 10-24 (N=8).

---

## 1. What makes up one comparison, in order, and what each word actually wraps

`main_loop()` (`ps_ui/main.c:12833`) is one `for (;;)` at `:13266`. The comparison runs in the
`else if (g_ref_ok != 0u && (frames % DIFF_EVERY) == 0u)` branch at `:14037`. Both snapshots are from
`MB_AVG_N = 1`, so the N=1 branch is the one that matters here.

### 1.1 The comparison section, in execution order

| # | what runs | where (HEAD) | reads the frame? | inputs |
|---|---|---|---|---|
| 1 | `cap_ho_sample()` + `cap_read_index()` — **bounded wait** for a capture edge | call `:14049-14050`, body `:810-863` | 1 PL word per spin | `CAP_FRPTR`, `MB_CAP_MSB` (0), `g_cap_period` |
| 2 | `dcache_invalidate(store, 2,764,800)` | `:14051`, body `ps_ui/mmu.c:98` | 86,400 line ops | the selected store |
| 3 | `t0 = GTIMER` … `MB_DIFF_MS = GTIMER - t0` | `:14047`, `:14064` | — | — |
| 4 | `avg_take()` — 0 when N<2 | in `diff_frame` `:8278`, body `:4076` | no | `AVG_*_SUM`, `g_avg_count` |
| 5 | `latt_fill(src)` — the 160x90 lattice | `:8353`, body `:3663` | **57.6k** | the store |
| 6 | `part_masks()` — green rule + erode + cluster, then background rule + median/erode + cluster | `:8362`, body `:4384` | green score **172.8k** | the store, `LATT_BASE`, `BG_GRID_BASE`, `g_bg_ok` |
| 7 | `part_bbox_publish()` | `:8395`, body `:4549` | no | `LIVE_MASK` |
| 8 | part-in-view refusal (returns `MB_DIFF_OK` 6) | `:8396-8414` | no | `g_part_pts`, `g_part_edge`, `g_bg_cells` |
| 9 | `gm_latt_fill(src)` — the structure lattice the search scores | `:8418`, body `:3335` | **230.4k** | the store |
| 10 | `reg_search()` | `:8433`, body `:6204` | no (scores `LIVE_GM`) | `LATT_BASE`, `LIVE_GM`, `BASE_GM`, `BASE_MASK`, `BASE_MASK_D` |
| 11 | PASS 2: coarse cells, `ref_cell()` per cell, bias, sigma, row means | `:8549-8590` | **14.4k** (REF_BASE) | `g_dflag`, `g_diff_scale`, `REF_BASE` |
| 12 | the fine pass: `cell_mean8`/`FINE_SUM`, `ref_cell8`, `tol_at`, `cc_largest`, 3x3, persistence | `:8629-8758` | ~17k | `LIVE_MASK`, `FINE_TOL`, `REF_BASE`, `AVG/FINE_SUM` |
| 13 | `contour_run()` | `:8908`, body `:8057` | no | `g_dflag`, `DHIT` |
| 14 | `diff_refine()` — only when the coarse count > 0, refused if either box side >= 256 px | `:8910`, body `:7630` | box at 2 reads/px | the store, `REF_BASE` |

Outside `MB_DIFF_MS`, but part of the same loop and of the same frame's cost: the store selection +
invalidate + `cam_mean_green`/`cam_bright_count` + `part_track()` in the **class** phase (`:13420-13518`),
`measure()`/`measure_pass` in **qual**, `draw_camera` in **cam**, `avg_sample()` (`:13865`),
and — on the loop *after* an NG — `evid_copy()` (`:13514`, 30.7 ms, which then replaces `part_track`).

### 1.2 What each published word really wraps (not what the name says)

| word | actually wraps | comes from |
|---|---|---|
| `MB_DIFF_MS` (186) | from before the capture selection **to the end of `diff_frame`**: the bounded capture wait + the 2.76 MB invalidate + every pass 4-14 above. It is **only written when `diff_frame()` returns non-zero**, so a refused comparison leaves the previous value standing — a stale `MB_DIFF_MS` looks exactly like a fresh one. | `:14047/14064` |
| `MB_REG_TICKS` (233) | the whole `reg_search()` call, `t0` at entry `:6209` to the write on every return path (`:6343/6364/6391/6827/6839`), in ticks. It is **read again on `REG_MODE_HOLD`** (the snapshot is mode 2 with 16.69 ms), so it is not "the cost of a re-solve". | `:6209…6839` |
| `MB_AVG_TICKS` (411) | one `avg_sample()` call: `latt_point` + `cell_mean4` + `cell_mean8` reads = 936k frame reads. **Written only when the sampler runs**; at N=1 it returns at `:4028` and the word keeps its last value. Both 167 ms snapshots carry `MB_AVG_TICKS` = 9,388,082 (28.0 ms) from an earlier N=8 window — a plausible number that describes nothing current. | `:4025-4067` |
| `MB_PART_TK_MS` (513) | `part_track()` only: `latt_fill_into` (57.6k reads) + `bg_scale_median` + `bg_diff_fill` + `u8_median` + `mask_thr_erode` (+ the green fallback). Not the selection, not the invalidate, not the comparison's `part_masks`. | `:4705-4767` |
| `MB_EVID_TICKS` (525) | `evid_copy()`: 2.88 MB frame+mask+grids copy plus cache clean, at the **top of the next loop**, replacing `part_track` on that loop. | `:4968-5008`, measured 30.7 ms |
| `MB_BLOB_TICKS` | `contour_run()` only. | `:8059` |
| `MB_T_SYNC` (70) | `cam_bracket_sync()` (`:944`) = the wait for `CAP_FRPTR` to differ from the last loop's value. **Not** the capture-handover wait used by the store selection — at a 99 ms loop the bit has always flipped already, so it measures 8,669/32 = **0.0008 ms**. | `:13270-13294` |
| `MB_T_CLASS` (71) | publish + **store selection (with its own bounded wait) + 2.76 MB invalidate + mean/bright counts + `evid_copy`/`part_track`** — "class" is not "classify". Measured **31.23 ms/loop**. | `:13294-13518` |
| `MB_T_QUAL` (72) | `measure_pass` for cam0 (every loop) and cam1 (every 4th) + `measure()` = **7.39 ms/loop**. | `:13518-13676` |
| `MB_T_CAM` (73) | `draw_camera` + diff cells + blob box + tear compare + 2 AEC controllers + `settle_gate` + `avg_sample` + verdict debounce + **the comparison** + self-test + ~30 mailbox words = **52.92 ms/loop**. This is where `MB_DIFF_MS` lands. | `:13676-14155` |
| `MB_T_TAIL` (75) | `draw_bottom` + buttons + thumbs + CNN + `MB_CMD` handler + `dcache_clean(UI)` + park flip = **6.75 ms**; `MB_T_PANEL` = 1.04 ms; `MB_T_PUB` = 0.0003 ms. | `:14155-14445` |

All `MB_T_*` are **sums over `MB_T_N` loops** (32 here), so divide. Check of the 19:51 snapshot
(ticks/ms at 334,800 ticks/ms):

| phase | ticks/loop | ms/loop |
|---|---|---|
| sync | 271 | **0.0008** |
| class | 10,456,543 | **31.23** |
| qual | 2,472,820 | **7.39** |
| cam | 17,718,928 | **52.92** |
| panel | 346,819 | **1.04** |
| tail | 2,261,328 | **6.75** |
| pub | 111 | 0.0003 |
| **total** | 33,256,889 | **99.32** |

The seven add to 99.33 ms, i.e. the segment accounting closes.

---

## 2. The 167 ms, decomposed

### 2.1 Measured inside it (directly, in ticks)

| item | ms | evidence |
|---|---|---|
| `reg_search()` | **16.69** (16.68 in the second snapshot) | `MB_REG_TICKS` 5,588,706 |
| `part_masks()` (both rules, 2 erodes + 2 clusters) | **20.3-26.0** | measured when it was called once per loop, `dl/PART_MASK_PERFRAME_20261026.md` §3 |
| `contour_run()` | **1.85** (2.10) | `MB_BLOB_TICKS` 619,496 / 705,723 |
| subtotal measured | **38.8-44.6** | |

### 2.2 Modelled, with the model calibrated on this board

The calibration is not a guess: `part_track()` reads 57,600 bytes of the frame in a strided 2x2
pattern and measures **4.83 ms median** (`.tmp/ab_segA.csv`, n=158) → the frame is walked at
**~84 ns per strided read**, and the per-pass cost scales with the number of distinct 32-byte cache
lines touched (L1 only: `ps_ui/mmu.c` maps the stores write-back cacheable, but L2C-310 control reads
0, so there is no L2 — `mmu.c:11-12`). At that rate:

| pass (N=1 only) | frame reads | ms (84 ns/read) | frame lines | ms at 170-330 ns/line |
|---|---|---|---|---|
| `latt_fill` | 57,600 | 4.8 | 28,800 | 4.9-9.5 |
| `part_masks` green score | 172,800 | 14.5 | 28,800 | 4.9-9.5 |
| PASS 1 `cell_mean4` (3,600 x 100) | 360,000 | 30.2 | 72,000-108,000 | 12-36 |
| PASS 1a background presence grid | 57,600 | 4.8 | 28,800 | 4.9-9.5 |
| `gm_latt_fill` (14,400 x 16) | 230,400 | 19.4 | 115,200 | 20-38 |
| fine `cell_mean8` (477 judged cells) | 17,200 | 1.4 | 5,700 | 1-2 |
| PASS 2 `ref_cell` (REF_BASE) | 14,400 | 1.2 | 7,200 | 1.2-2.4 |
| **frame-reading passes, all** | **909,600** | **76** | **~315,000** | **49-107** |
| … of which the green score is already inside the measured `part_masks` above | 172,800 | -14.5 | -28,800 | -5 to -9.5 |
| **frame-reading passes, not already counted in §2.1** | **736,800** | **61.8** | **~286,000** | **44-88** |
| cache invalidate 2.76 MB | — | — | 86,400 line ops | 2.6-5 |
| capture-handover wait at step 1 | — | **0-54, not instrumented** | — | — |
| **modelled total, exclusive of §2.1** | | | | **47-147** |

The two framings do not agree (61.8 vs 44-88) because the byte-rate and the line-rate differ on the
same frame: `avg_sample()` walks the frame in address order and reads 936k bytes at 30 ns/read
(28.4 ms), while a strided pass that touches only a third of the lines pays 84 ns/read (from
`part_track`'s own 4.83 ms for 57,600 reads). The honest statement is a bracket:

> measured inside `MB_DIFF_MS` (§2.1): **38.8-44.8 ms**, of which 20.3-26.0 is `part_masks`.
> modelled passes not already counted + invalidate + wait: **47-147 ms**.
> Total: **86-192 ms** against **167.2 measured** — the bracket contains the measurement, and at the
> low end **~81 ms (167 - 39 - 47) is attributable to nothing on disk**. The only candidate of that
> size that is in the code but not in any timing word is the bounded capture wait
> (`cap_read_index()`, bound `interval*3` where `interval` is the inflated `g_cap_period` — up to
> ~163 ms; the fallback path is active because **`MB_CAP_DEC` = 0**, `MB_CAP_WAITS` 9,268 of 24,267
> selections).

This is exactly the remainder the project already found once from the other end: enabling the
per-loop mask added +33.1 ms to the loop while the pass itself measured 4.83 ms, and the class phase
accounted for only +20.1 of it. The class phase is where the *other* capture wait lives; `T_CLASS`
31.23 ms minus `part_track` 4.83 minus the ~2.9 ms of `cam_mean_green`/`bright`/invalidate leaves
**~23 ms of class-phase wall time that no word explains** — consistent with a ~20-27 ms average
wait, and evidence that the same wait is inside `MB_DIFF_MS` too.

### 2.3 Why "167 vs 91" is not one variable — two confounds, with numbers

1. **Averaging arm.** Both 167 ms snapshots have `MB_AVG_N` 1, `MB_AVG_CNT` 1. The 91.1 ms build had
   `AVG_CNT` 8 in 196/196 (`STAGE8`, §6). At N=1 `diff_frame` runs `latt_fill` (`:8353`) and
   `cell_mean4` per cell (`:8291`) and `cell_mean8` per judged cell (`:8652`) itself; at N>=2 all
   three are precomputed by `avg_sample()` (`:4046-4065`) and merely read as sums. That moves
   **~435k frame reads (~20-45 ms by the table above) into the timed section** without any code
   regression.
2. **Frame content.** The 167 ms was measured on a frame whose reference contained four black marks
   (`NG_GOODBOARD_20261026.md`) — `MB_DIFF_CELLS` 536, `DAREA` 10/11. A clean PASS frame has
   `MB_DIFF_CELLS` 0. The only pass gated on "cells > 0" is `diff_refine()` (`:8910`), and in both
   snapshots it refused on the 256-px bound (`MB_DIFF_RSTATE` 2, `RPX` 0), so this confound is
   **small (< 4 ms)** — but it also means the 167 ms is not the number a PASS frame produces, and
   no PASS-frame `MB_DIFF_MS` exists on disk (the 20:50 board state has `DAREA` 0 but only 52 words
   were dumped, `MB_DIFF_MS` not among them).

---

## 3. Which added passes account for the difference — file:line and commit

Commits touching `ps_ui/main.c` between the 91 ms build (`eea8d22` / main.c `e71ae33`, 2026-10-24
18:33) and HEAD `845be5d`: `581c6f8`, `e55fd89`, `091ce9a`, `ee4ea5a`, `5421dfb`, `6d2bec9`,
`acc727f`, `6edfff5`, `ea4bcef`, `845be5d`. The ones with a new **per-comparison full-frame or
14,400-cell pass** are:

| # | change | commit | where (HEAD) | cost in one comparison | confidence |
|---|---|---|---|---|---|
| 1 | the registration scores **structure** (gradient magnitude): a new `LIVE_GM` lattice over the whole frame every comparison | `ee4ea5a` 2026-10-25 | `gm_latt_fill()` `:3335-3354`, called `:8418`; `gm_base_fill()` `:3313` at the reference | **230,400 frame reads = 19.4 ms** (84 ns/read) / 20-38 ms (line model) — **new since 10-24** | E1 (read count from code; rate from `MB_PART_TK_MS`) |
| 2 | the part mask is **two rules, run always**: green rule (score + erode + cluster) kept as the audit and the fallback, background rule added | `581c6f8` + `e55fd89` 2026-10-25 | `part_masks()` `:4384-4468`; green at `:4408-4434`, background `:4442-4459`; comment states both run always at `:4347` | one full `part_masks()` = **20.3-26.0 ms**, of which the green score alone is 172,800 reads (14.5 ms). The 10-24 build ran the green rule only, once (~10-14 ms) → **+8-14 ms** | E2 for the total (measured), E1 for the split |
| 3 | the tolerance map: one lookup + optional learn per judged fine cell | `6d2bec9` 2026-10-25 | `tol_at()` `:3927`, used `:8661`; learn `:8683-8688` | < 0.5 ms (477 lookups) | E1 |
| 4 | part-in-view refusal | `acc727f` 2026-10-25 | `:8396-8414` | ~0 | E1 |
| 5 | sub-pixel coarse scoring / low-confidence escalation | `5421dfb`, `091ce9a` 2026-10-25 | `reg_search()` `:6204`, `reg_score_phase_pair()` `:5430` | **none measurable**: `MB_REG_TICKS` 16.69 ms now vs 16 ms (`STAGE0`), 17 ms (`STAGE_H`), 18.4 ms (`DEFECT3`) | E2 |
| 6 | per-loop part mask | `6edfff5` 2026-10-26 | `part_track()` `:4705`, call `:13515` | **0 inside `MB_DIFF_MS`** (it is class-phase, 4.83 ms median). Its A/B cost +33.1 ms of *loop* is the separate finding, §2.2 | E2 |
| 7 | boot self-test + NG evidence snapshot | `ea4bcef` 2026-10-26 | `boot_selftest()` `:4805`; `evid_copy()` `:4968`, call `:13514` | self-test 0.05-0.1 ms; the evidence copy 30.7 ms but on the **next** loop and only after NG | E2 |
| 8 | camera 1 anti-flicker lock | `845be5d` 2026-10-26 | `cam1_timing_derive()` `:7059` | boot-time only | E1 |

**Attribution of the 76 ms (167 - 91):**

| contribution | ms | basis |
|---|---|---|
| the N=1 arm: `latt_fill` + PASS 1 `cell_mean4` + fine `cell_mean8` move inside `MB_DIFF_MS` | **20-45** | read counts x 84 ns/read; 435k reads |
| `gm_latt_fill` (new, #1) | **19-38** | 230.4k reads |
| the second mask rule + the always-on green audit (#2) | **8-14** | `part_masks` 20.3-26.0 measured vs the 10-24 green-only mask |
| capture wait — unchanged code, no word | 0 to ~20 | §2.2, unattributed |
| everything else (tol map, in-view gate, registration) | < 2 | measured words |
| **sum** | **47-119**, centred on the measured 76 | |

So: **~half of the gap is the averaging arm, not a regression**; the two real regressions are the
structure lattice (`ee4ea5a`) and the two-rule mask (`581c6f8`/`e55fd89`), together ~27-52 ms.

---

## 4. The averaging: what the evidence actually supports

**The 167 ms does not contain the averaging.** The sampler is off in both 167 ms snapshots
(`MB_AVG_N` 1, `MB_AVG_CNT` 1). What the sampler costs is a **loop** cost, paid on the last
`g_avg_n` loops of each 16-loop window (`avg_sample()` returns early at `:4030`), and measured at
**28.0-44.0 ms per sampling pass** (`MB_AVG_TICKS`); i.e. ~14-22 ms added to the 16-loop average, and
28-44 ms to each of the 8 sampled loops.

**What its benefit is measured to be.**

| measurement | N=1 | N=8 | comment |
|---|---|---|---|
| `MB_DIFF_CELLS` >= 8 (the verdict input), 10-24, fresh reference | 2 of 43 | **0 of 45, 0 of 47** | `STAGE2_20261024_average.md`; this is the statistic the verdict reads |
| `MB_DIFF_SIGMA`, 10-24 | 115 median sigma16 = 7.2 grey | 71-74 = 4.4-4.6 grey | the "7.2 → 4.4" claim |
| `MB_DIFF_SIGMA`, 2026-10-26 A/B | 38.1 / 37.5 = 2.38 / 2.34 grey | 34.6 / 41.1 / 42.4 = 2.16 / 2.57 / 2.65 grey | `NG_GOODBOARD_20261026.md` §5 — **straddles, no resolvable effect** |

The 2026-10-26 A/B is **not a refutation**, and it must not be quoted as one:

* it measured `MB_DIFF_SIGMA`, not the cell tail, and on that frame sigma was **2.4 grey at N=1** —
  three times quieter than the 10-24 N=1 run (7.2 grey), so the frame noise the averaging removes was
  already gone; the sigma was dominated by the spatial interpolation residual (the reference was
  40 px off: `MB_DIFF_DX/DY` +646/-288, `REG_STATE` 1 mode 2);
* it is 5 arms of 8 comparisons with no pre-registered effect size, and the two statistics have
  different denominators (10-24: cells per comparison over 43/45 comparisons).

**Verdict (E1):** the averaging cannot be switched off on the evidence in hand. The one experiment
that showed its value is on the verdict's own input (2/43 false-NG-sized counts → 0/47), and the
2026-10-26 negative was taken on a different statistic on a frame where that statistic could not see
frame noise. What is *also* true, and is the operational problem: the target is a host word, it has
twice been found at 1 (19:51, 19:53 — after `NG_GOODBOARD` had restored it to 8 at 19:43), nothing
in the firmware restores it, and `MB_AVG_TICKS` keeps a plausible stale 28.0 ms so a reader cannot
tell "off" from "on" without `MB_AVG_CNT`.

**If it were switched off (for ~14-22 ms of loop time and 20-45 ms of comparison time), what must be
re-measured before that decision is defensible:**

1. the **good-board DAREA/FCELLS population** at N=1 and N=8, same station, fresh reference,
   >= 30 independent comparisons each, pre-registered criterion "no comparison at or above
   `MB_DIFF_LIM` 8" — the 10-24 data suggests N=1 fails 2/43, which is a 5% false-NG rate;
2. the **defect's DAREA** at both N, using the firmware's own known answer (`MB_CMD` 15 stamp, which
   reads DAREA 28, `EVIDENCE_20261026.md` §4) plus the operator's real defective board — averaging
   must not lower DAREA on a real defect (it cannot be allowed to average a defect away);
3. `MB_AVG_TEAR` / `MB_AVG_SKIP` on the clean scene (the sampler drops torn/still frames, so the
   N=8 arms in a busy scene are not all 8 frames).

Until (1)-(3) run, the cheapest *defensible* setting is the build default N=8 plus a host gate that
refuses to judge with `MB_AVG_CNT` 1 — and that is a **net loss** of 20-45 ms on the comparison, which
is the opposite of the goal.

---

## 5. Proposal: the cheapest change toward 91 ms (NOT applied)

Nothing in this section has been edited into any source file. Two patches, in order. Neither one
reaches 91 ms, and section 5.3 says what would.

### 5.1 P1 — measurement + the one cheap removal (recommended first)

**P1a. Two words for the two untimed sections.** Free indices: 532/533 were just taken by the
concurrent camera-1 edit, so claim **534/535** after `python dl/mb_words.py` confirms them free
(the map generator and `check_layout.py` enforce one owner per index).

* `MB_T_DIFFSEL` (534): ticks from `t0` to just after `dcache_invalidate` at `:14051`. This splits
  `MB_DIFF_MS` into *selection+wait+invalidate* and *`diff_frame` proper* — without it the 77 ms
  remainder cannot be closed.
* `MB_T_CLSEL` (535): ticks around the class-phase `cap_read_index()` call at `:13473`. This is the
  wait that the per-loop-mask A/B already showed ~23 ms of unexplained class time.

Both are pure PS writes inside code that already exists; no arithmetic changes.

**P1b. Skip the green audit when the background rule is the answer.** Today `part_masks()` scores
the green rule first (`:4408-4434`, 172,800 frame reads, 14.5 ms) and then runs the background rule
(`:4442-4459`); when the background rule succeeds (`MB_PART_RULE` 1, the production state —
`MB_PART_GREEN` 1275 / `MB_PART_GCLU` 756 were published on the 19:51 frame purely as an audit)
the green mask is thrown away. Reorder: run the background rule first (it needs only `latt`, not the
green mask), and run the green rule only when the background rule fails **or** once every 16th
comparison for the audit trail, publishing which comparison the audit describes.

* Saving: **the green score pass 14.5 ms + its erode/cluster (~2-4 ms) ≈ 15 ms** on every comparison
  in the production state (line model: 5-10 ms; the band is stated, not hidden).
* Risk: low for correctness (the fallback is computed on exactly the frames that need it), but the
  audit words `MB_PART_GREEN`/`MB_PART_GCLU` become "described by comparison X" instead of
  "this frame" — the words' meaning changes and `dl/host_qc/README.md` and `preflight.py` must be
  updated in the same commit; `MB_PART_GREEN` = 0xFFFFFFFF must be used for "not measured on this
  comparison", never 0.
* OCM: code reordered, no new buffer.

**P1 expected: 167 → 147-157 ms**, plus the two words that show where the rest is.
**Acceptance P1:** `MB_DIFF_MS` falls by >= 8 ms on 5 consecutive comparisons with `MB_DIFF_OK` 1 and
`MB_DIFF_CELLS`/`FCELLS`/`DAREA`/`SIGMA` bit-identical to the pre-patch build on the same scene
(same reference, no retake, no `MB_MAGIC` change); `MB_T_DIFFSEL` and `MB_T_CLSEL` are non-zero and
their sum is consistent with the fall.

### 5.2 P2 — the structure lattice (`gm_latt_fill`), the other real regression

`gm_latt_fill` (`:3335`) computes 4 `gm_grey_at` per lattice point = 230,400 frame reads on every
comparison, but `reg_search()` scores `LIVE_GM` only at the points its masks admit and at the
sub-sampling each stage uses (`reg_score(..., sub)` at `:5333`). Cheapest honest version: fill
`LIVE_GM` only for the points `reg_search` will actually score at the **coarsest** stage, and let the
finer stages interpolate — or compute the lattice at the half density it is scored at.

* Saving: up to **19 ms** (230.4k reads) in the best case, realistically 8-12 ms.
* Risk: **medium** — this changes the registration's error surface, and the registration's accuracy
  is one of the project's measured claims (`dl/STAGE_H_20261025_registration_accuracy.md`). It must
  not ship without re-running that acceptance and the stereo RMS check.
* Do P1 first; P2 only if the registration acceptance can be re-run in the same session.

### 5.3 What would actually be needed for ~91 ms, and why it is not "cheap"

`91 ms` was measured at **N=8**, on a build **without** `gm_latt_fill` and with a **single** mask
rule. Reproducing it on HEAD means removing, in one build: the N=1 arm (20-45, i.e. restore N=8 —
already available as a host word), `gm_latt_fill` (19-38), the mask audit (15), and — for the last
20-40 — making the capture-handover wait deterministic. The last one is the hard one: the decode that
would remove it is `MB_CAP_MSB`/bit 15, and **`MB_CAP_DEC` reads 0 on this load** (`CAP_G1` 0,
`CAP_PAIRS` 2), so the two-bit store index is not available in this fabric. That is a Block Design /
probe issue, not a firmware change, and it is the thing to fix if 91 ms is a requirement rather than
a reference point.

**Realistic end state with P1 + P2 + N=8: 105-125 ms** for the comparison loop, with the loop at
113-121 ms. Without the capture wait, no combination of the passes gets below ~100.

### 5.4 The acceptance test the next session would run

```
# 0. state: good board at the station, DAREA 0, no retake since the patch, MB_AVG_N as stated.
#    (read-only; no rst, no dow; newest ps_ui build only if the patch is being tested)
1. baseline on HEAD: 5 comparisons -> MB_DIFF_MS, MB_T_DIFFSEL, MB_T_CLSEL, MB_DIFF_CELLS,
   FCELLS, DAREA, SIGMA, MB_REG_TICKS, MB_REG_ERR16, MB_T_CLASS/T_N, MB_T_TOTAL/T_N
2. same 5 on the patched build, same scene, same reference, no MB_CMD
3. PASS criteria
   a. MB_DIFF_MS falls by >= 8 ms and MB_T_DIFFSEL+MB_T_CLSEL explain >= 80% of the fall
   b. MB_DIFF_CELLS / FCELLS / DAREA / SIGMA identical, comparison for comparison
   c. MB_REG_STATE 1, MB_REG_MODE 2, MB_REG_ERR16 within the pre-patch range
   d. a fresh reference (MB_CMD 9) then 30 comparisons: DAREA 0 and verdict 0 in all 30
   e. known-answer defect (MB_CMD 15 stamp): DAREA still 28 (EVIDENCE_20261026.md §4)
   f. the wrong-answer control: MB_CMD 14 re-aim still gives MB_REG_MODE 5, MOVE >= 100,
      state 2 / verdict 2 on that comparison and a normal hold after
4. averaging experiment (independent of the patch): 30 comparisons at N=1 and 30 at N=8 on the
   good board, fresh reference each, recording MB_DIFF_CELLS and MB_DIFF_DAREA; then the MB_CMD 15
   stamp at both N. This is the experiment that decides whether the sampler earns its 28-44 ms.
```

**One correctness caveat that came out of this analysis and should be checked with the same dumps
(E1, not measured):** the comparison selects a store that completed 0-27 ms earlier and then reads
it for 167 ms, while the ring rewrites that store one store period later (27.2 ms measured on 10-24
per `cap_read_index()`'s own note, `:705-720`; 81.6 ms per four stores). `diff_frame`'s frame reads
therefore extend past the store's safe window, so the passes that read the frame late (the fine
pass at `:8650-8653`, PASS 2 if the transform is slow, `diff_refine`) may be reading a splice of two
stores. The existing tear detector covers the *render*, not the comparison. Offline check with the
existing instrument: replay `ps_ui/a1_replay.py`'s fine pass on the store and compare with
`FINE_DEEP` — 14,117/14,400 cells matched on the 26th, so the check has a known answer.

---

## 6. What could not be determined offline

1. **How much of the 77 ms remainder is the capture wait.** No word times `cap_read_index()`, and
   `MB_CAP_ELAPSED` is written *after* the wait and read 0 in both snapshots. P1a is the fix.
2. **`MB_DIFF_MS` on a PASS frame on this build.** Both 167 ms readings are from an NG frame
   (`DAREA` 10-11). The `MB_DIFF_MS` effect of `diff_refine`/`cc_largest` on an NG frame cannot be
   separated without a PASS-frame reading; `diff_refine` provably refused in both snapshots, so the
   bound is < 4 ms, but it is a bound, not a measurement.
3. **The per-pass split inside `diff_frame`.** The two calibrations on disk (30 ns/read from
   `avg_sample`, 84 ns/read from `part_track`) differ by 2.8x because the access patterns differ
   (sequential sweep vs strided third-of-the-lines). The totals bracket 167 ms; the individual rows
   in §2.2 do not.
4. **Where the 20-29 ms of per-loop improvement since 10-24 comes from.** 137.4 ms at N=8 on 10-24
   vs 99.3 ms at N=1 now: after removing the sampler (8/16 loops x 28-44 ms) ~20 ms is still
   unaccounted, on the same `T_*` instrument. Not investigated; not needed for the 167 ms question.
5. **Why `MB_CAP_DEC` is 0** (bit 15 of `CAP_FRPTR` never changes on this load). The 2026-10-24
   note says the bitstream routes `frame_ptr[1]` to probe bit 15; the board says otherwise. This is
   the single blocker for making the wait disappear, and it is a BD question, not a firmware one.
6. **Who writes `MB_AVG_N` 1.** Same unknown as `NG_GOODBOARD_20261026.md` §5.2 — found at 1 again
   at 19:51/19:53 after it had been restored to 8.

## 7. Reproducing every number here

```
# the full mailbox snapshots used above
dl\xcheck_20261026\goodA\capture.json     MB_DIFF_MS 55,992,504 / 334,800 = 167.24 ms
dl\xcheck_20261026\goodA2\capture.json    MB_DIFF_MS 55,946,155 / 334,800 = 167.10 ms
# the per-loop-mask pass distribution
.tmp\ab_segA.csv   (158 samples, median 1,617,413 ticks = 4.83 ms, max 7,542,619 = 22.53 ms)
# the 10-24 comparison
dl\STAGE8_20261024_fine_cells_and_adaptive.md  section 6 (91.1 ms, 137.4 ms loop, AVG_CNT 8 x196)
# wording of every word
python dl\mb_words.py --write dl\MB_WORDS_20261026.md
# line numbers: HEAD, not the working tree, which is being edited
git show 845be5d:ps_ui/main.c
```
