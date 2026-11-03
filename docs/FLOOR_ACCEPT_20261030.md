# Part-floor acceptance, 2026-10-30 — build TSC14CA85A0E

The station, the build and the five gate readings, in the order they were taken. Every
number here was measured on the board with the image identified below; nothing is a
prediction. The raw captures are the `dl/_floor_*.log` files listed at the end.

## The change

| site | change |
|---|---|
| `ps_ui/main.c` `part_min_pts_view()` | the camera-0 special case is deleted. Both views now return `clamp(g_part_ref/2, 128, PART_MIN_PTS)`. Camera 0's floor on this station was 281 (reference 562) instead of the constant 400; the constant could only ever be reached by a reference of 800+. |
| `ps_ui/main.c` the comment above it | the paragraph "CAMERA 0 KEEPS PART_MIN_PTS = 400, unchanged: 22 boards were measured against it" is replaced: one rule for both views, the measured d23 numbers, why the 22-board population is safe, why half and why the clamp stays, and the STATED RISK. |
| `ps_ui/main.c` camera-0 registration diagnostics | words 422..427: `cam0_regwhy`, `cam0_seed`, `cam0_seedsc`, `cam0_conv`, `cam0_convsc`, `cam0_ncc`; the same packing and REGWHY codes as camera 1's 418..421/635/639. `reg_diag_finish()` now runs for both views, and view 0's values are published once per loop from `diag_publish()` so a PART_OUT refusal cannot leave the previous why standing. A PART_OUT frame publishes `cam0_ncc = 0xFFFFFFFF` ("not measured") instead of the previous frame's correlation. |
| `dl/host_qc/qc_mailbox.py`, `dl/host_qc/check_words.py` | the host map and the source checker carry the six new words. |
| wording | the claim is narrow: only frames whose clustered mask is 261..399 can change, and only from CANNOT JUDGE to entering the comparison. Every other gate is untouched. |

## Build

| fact | value |
|---|---|
| build id | **TSC14CA85A0E** (`FW_SRC_HASH 4CA85A0E`, 13 source files) |
| ELF / bin | 206,728 B / 127,636 B; loadable image ends 0x1F294 |
| sections | .text 0x1F240 at 0x0, .ARM.exidx 8 at 0x1F240, .data 0x4C at 0x1F248, .bss 0x1A10 (6,672 B) at 0x24000..0x25A10 — all in OCM; page table 0x20000..0x24000 not overlapped |
| entry / first word | 0x20 / EA000006 |
| warnings | four, the pre-existing set (implicit then conflicting `dcache_invalidate`, always_inline `draw_camera_impl`, unused `wait_probe_edge`); no new warning |
| layout check | 479 MB_* words, 479 distinct indices, 0 collisions; 384,000 pixels tiled |
| ELF scan | `check_mb_words_elf.py --low 417 --high 639 --require 422 .. 427` -> every required word present, no forbidden reference |
| load | `ps_fft_dual/strict_load_cores.tcl` (core-only), "image downloaded / running" first try; stamp TSC14CA85A0E and MB_BUILD_ID 0x4CA85A0E read back, frames and both views' mask counters advancing |
| commit | local commit 914b111 |

## Gate 1 — empty belt (PASS)

Exposure pinned at the AEC's own equilibrium: word 508 = 8662, read back 8662, aec_state 1,
clip 0. One `MB_CMD = 12` -> bg_state 1, bg_cells 0, cam1_bgok 1, v0_bgfr = v1_bgfr = 67.

Triplets before the snapshot (pts, mean, diffok):

| # | cam0 | cam1 |
|---|---|---|
| t0 | 0, 494, 5 | 0, 494, 5 |
| t1 | 0, 498, 5 | 0, 498, 5 |
| t2 | 0, 498, 5 | 0, 498, 5 |

Ten reads one second apart: both views' pts = 0 in all ten, diffok = 5, mean 494/498.
The mask's own why was 3 (too few valid cells) on both views — the empty-belt refusal is
named, including on camera 0.

Five `MB_CMD = 12` in a row: identical — pts 0 both views, diffok 5, bg_state 1,
bg_cells 0 after each. `bg_cells` wandered 2..20 BETWEEN captures during the ten reads,
below BG_MIN_CELLS (24) and back to 0 after each capture; expected, not a fault.

## Gate 2 — g0 with both references (PASS)

Triplets before the reference capture (pts, mean, diffok):

| # | cam0 | cam1 |
|---|---|---|
| pre1 | 575, 474, 5 | 265, 474, 5 |
| pre2 | 569, 478, 5 | 272, 478, 5 |
| pre3 | 587, 478, 5 | 285, 478, 5 |

`MB_CMD = 9` took both references in one command (diff_n moved 414 -> 1).

| reference | mask | refq | floor in force |
|---|---|---|---|
| camera 0 | 562 | 0 (pass) | **281** |
| camera 1 | 275 | 0 (pass) | **137** |

The pre-stated 523/261 did not occur: the reference measured 562 on this capture (516 on
the old build at 19:35, 523 in the review's reading). The gate's own number is 562 -> 281.

Post-capture triplets: (571,478,1)/(602,478,1)/(605,478,1) cam0,
(284,474,1)/(281,478,1)/(255,478,1) cam1.

Gate snapshot: cam0 pts 605 (pts_c 568), diffok 1, fvalid 552, fcells 0, darea 0,
diff_verdict 0 (PASS), regstate 1, incerr 14, sad 14, mode 2, why 0, ncc 984.
cam1 pts 255, diffok 1, fvalid 255, why 0.

## Gate 3 — d23, the board whose refusal was the point (PASS, it judges)

Triplets before the snapshot (pts, mean, diffok):

| # | cam0 | cam1 |
|---|---|---|
| t0 | 484, 478, 1 | 267, 478, 1 |
| t1 | 450, 482, 1 | 267, 482, 1 |
| t2 | 466, 482, 1 | 249, 482, 1 |

diffok was already 1 in all three, on both views.

| quantity | value |
|---|---|
| cam0 pts (word 366, pre-cluster) | 443..553 over five reads; 466/443 in the two snapshots |
| cam0 pts_c (word 515, the clustered count the floor gate compares) | **383..395** |
| cam0 ref | 562 (floor 281) |
| cam0 diffok / regstate | **1 / 1** |
| cam0 fvalid / fcells / darea / verdict | 350 (343..352) / 0..1 / 0 / 0 = PASS |
| cam0 regerr / sad / why / ncc | 29..30 / 29..30 / 0 / 784..814 |
| cam0 seed / converged | 0 / 0 (identity held, no move) |
| cam1 pts / diffok / fvalid / why | 249..252 in the snapshots (235..267 over all reads) / 1 / 189..190 / 0 |

The mechanism: the floor compares the CLUSTERED count (word 515). On d23 the clustered
count is 383..395 — below the old 400 floor and above the new 281. The old build's d23
frames carried the FEWCELLS sentinel set (19:39 dump: diffok 5, fvalid 0, fcells
0xFFFFFFFF); this build's d23 frames carry diffok 1, fvalid 350. The 425 quoted in the
brief was a pre-cluster-family number (word 366); the gate's own number is 383..395. The
death condition did not fire because d23 no longer refuses: `cam0_regerr` reads 29/30 (a
number, not 0xFFFFFFFF) and `cam0_regwhy` reads 0.

## Gate 4 — five-board good regression (zero flips)

Old = `dl/host_qc/logs/sweep_20261029_181623_sweep.csv`; new = this build, same station.

| board | old verdict | new verdict | flip | darea new (old) | pts_c new and band | old-build-tonight | label corroborated |
|---|---|---|---|---|---|---|---|
| g1 | 0 PASS | 0 PASS | no | 1 (2) | 328, inside 261..399 | no | yes |
| g7 | 0 PASS | 0 PASS | no | 3/2 (2) | 521/575, above 399 | no | yes |
| g12 | 0 PASS | 0 PASS | no | 1/2 (3) | 346/469, straddle | no | yes |
| g17 | 0 PASS | 0 PASS | no | 1 (3) | 503..520, above 399 | no | yes |
| g19 | 0 PASS | 0 PASS | no | 0 (3) | 394, inside 261..399 | no | yes |

Verdict invariance: five of five PASS before, five of five PASS after, zero flips. darea
moved by at most two cells and every board stayed in the good-board band; fvalid is lower
than 10-29 roughly in proportion to the smaller reference (685 -> 562), which is the
session. The guard passes.

Untouched-side set (cleanly above 399, the "judged before, still judged" evidence): g7 and
g17 only. g1 (328) and g19 (394) sit inside the band; g12 (346/469) straddles it. Those
three are boards the change acts on, and are not used as untouched-side evidence even
though their verdicts match.

The mislabelled g7 (scratched board under the good label): darea 1, PASS, pts_c 373/380,
fvalid 314/315, damp 35/37. Excluded from the table; kept raw as
`dl/_floor_g7_MISLABELLED_EXCLUDED_20261030.log`. Observation: a light scratch reads
darea=1 in the good-board position, i.e. at the clean-board level.

g12's frame-to-frame movement: two consecutive comparisons on a static board read pts_c
346 then 469 (123 cells) while the pre-cluster pts stayed 587/589. The cluster rule's own
count moves by more than 100 cells between comparisons with nothing physical moving. With
the session shift (reference 685 -> 562) this is the measured argument for a relative
floor rather than an absolute constant.

The two same-reference hard cases, kept separate from the five-board guard:

| case | old build (tonight) | new build (tonight) |
|---|---|---|
| g0 | diffok 1, darea 0, fvalid 497/507, ref 516 | diffok 1, darea 0, fvalid 552, ref 562 |
| d23 | diffok 5, fvalid 0, fcells 0xFFFFFFFF | diffok 1, fvalid 350, fcells 0/1 |

g0 is the "already judged, still judged" case under the same reference family; d23 is the
refusal-to-judgement case the change was made for.

## Death condition

Stated before the run: if d23 still refused but `regerr` moved off 0xFFFFFFFF, the floor
was cleared and the refusal had only moved. It did not fire: d23 is judged (diffok 1,
fvalid 350), regerr 29, why 0. No tuning was done at any point.

## What remains unproven

* The 26-board dump run was not started (not authorised at the time of writing).
* Camera 0's PART_OUT (why 1) and NOCONV (why 2) refusal states were not observed
  coherently: the two torn captures (why 0xFFFFFFFC, why 2 with inconsistent seed/conv)
  are JTAG reads landing inside a comparison, not states. The FEWCELLS state (why 3) was
  observed coherently on the empty belt with ncc = 0xFFFFFFFF.
* The NCC pass added to camera 0's comparison costs time that was not measured before/after;
  MB_DIFF_MS now includes it.
* The absolute reference mask is session-dependent (516, 523, 562 measured on the same
  station on one day); only the rule `ref/2` is stable, and that is the point of the change.
* The AND still refuses on every board (ok 0, why 4); it is unaffected by this change and
  remains unproven.
* The 22-board population was not re-run; the regression above is five boards plus g0/d23.

## Raw captures

`dl/_floor_empty_20261030.log`, `dl/_floor_ref_20261030.log`,
`dl/_floor_d23_20261030.log`, `dl/_floor_d23_confirm.log`,
`dl/_floor_g1_20261030.log`, `dl/_floor_g7b_20261030.log`,
`dl/_floor_g12_20261030.log`, `dl/_floor_g17_20261030.log`,
`dl/_floor_g17_confirm.log`, `dl/_floor_g19_20261030.log`,
`dl/_floor_g7_MISLABELLED_EXCLUDED_20261030.log` and its note.
