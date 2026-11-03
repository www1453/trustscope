# Problem 1 (2026-10-26): a good board read NG — the reference was of a board with black marks, and the averaging word was left at 1

Firmware: `ps_ui/main.c` + `ps_ui/mmu.c`, source hash **25666017** (`dl/build_id.py --show`), which is
what the board publishes as `MB_FWID0..2` (168..170): `0x31435354 0x36363532 0x37313036` = "TSC1" +
the hash's characters in reverse word order. Board: cold-booted, newest build, flashed only with
`ps_fft_dual/strict_load_cores.tcl`; no bitstream, no power cycle, no VDMA register was written.
**No firmware change was made in this item.** The only two host words written were `MB_AVG_N` (408)
and `MB_CMD` (101) = 9; both are documented host controls.

Instruments (new, ASCII-only Tcl + Python): `ps_fft_dual/a1_read_20261026.tcl`,
`a1_read2_20261026.tcl` (read-only dumps), `a1_fixcmd_20261026.tcl`, `a1_avgab_20261026.tcl`
(the controlled writes), `ps_ui/a1_analyze.py`, `a1_align.py`, `a1_replay.py`, `a1_zoom.py`,
`a1_marks.py`, `a1_png.py`. Name→index map regenerated: `dl/mb_map_20261026.tcl` (367 names; the
20261025 map predates the EVID/tracker words and could not resolve `MB_PART_PTS_C`, `MB_EVID_*`).
Dumps in `.tmp/a1/` (gitignored); evidence images in `dl/ng_20261026/`.

## 0. The two answers, in one paragraph each

**Why the good board read NG.** The part mask is not the belt edge and the group is not a surface
feature of the board in front of the camera. The dumped `REF_BASE` is an image of a board carrying
four black marks; the dumped live store is the same board and station, clean. The NG group
(`MB_DIFF_DAREA` 11-12, box lattice (52,68)-(59,71) = source px x416..479, y544..575, peak |d| 76-78)
is one of those marks. The mask has **no full-width strip anywhere** (the fullest row carries 23 of
160 cells) and its box is the board (x44..93, y50..79), so the belt edge — which sits at source rows
358..361, 40 px **above** the board's top edge — is not in the judged region at all. A fresh
reference of the board actually in view (`MB_CMD` = 9) returned `MB_DIFF_DAREA` **0**,
`MB_DIFF_VERDICT` **0 (PASS)** and `preflight.py` **PASS** on 44 consecutive comparisons.

**Why the averaging read 1.** `MB_AVG_N` (408) is a **host-written target**, not a count
(`ps_ui/main.c:2260`); the build writes its default **8** at boot (`main.c:12934`) and echoes what is
in force every loop (`main.c:13629-13632`). `MB_AVG_CNT` (409) is the published **count** and reads 1
when there is no average (`main.c:8211`). A host wrote 1 and nothing in the firmware restores it. The
averaging was therefore off, was re-enabled by writing 8, and is **demonstrably running** again:
`MB_AVG_CNT` 8 and `MB_AVG_TICKS` advancing every comparison (28-44 ms per sampling pass) versus
frozen at 9,373,111 ticks while the target was 1.

## 1. What was measured, and with what

| word | before | after the two host writes | how |
|---|---|---|---|
| `MB_DIFF_DAREA` (23) | 11, then 12 | **0** | mailbox, read by name |
| `MB_DIFF_DAMP` | 76-78 | 0 | " |
| `MB_DIFF_DBX0..DBY1` | 52,68,59,71 | 0xFFFFFFFF (no group) | " |
| `MB_DIFF_VERDICT` | 1 (NG) | **0 (PASS)** | " |
| `MB_LOCAL_VERDICT` | 1 | 0 | " |
| `MB_DIFF_FVALID` | 353 | 392-419 | " |
| `MB_DIFF_SIGMA` (sigma16) | 374-377 (23.5 grey) | 25-44 (1.6-2.8 grey) | " |
| `MB_PART_REF` | 671 (the marked board) | **420** (the clean board) | " |
| `MB_DIFF_DX/DY` (1/16 px) | +646 / -288 (+40.4 / -18.0 px) | 0 / 0 | " |
| `MB_AVG_N` | 1 | 8 | host word |
| `MB_AVG_CNT` | 1 | 8 | firmware publish |
| `MB_AVG_TICKS` | 9,373,111 (frozen) | 9.37-14.7 M, advancing | " |
| `preflight.py` | (not run before) | `PREFLIGHT PASS code=0 fail=0x00 | ref=420/400 bg(medd=3 cells=2458 rule=1 why=0 state=4) aec=1 clip=0 mask=619 vs presence=2458` | host tool, exit 0 |

The verdict rule that turned DAREA 11 into NG is `main.c:10694`: `return (da >= lim) ? 1u : 0u;`
with `MB_DIFF_LIM` 8 (`MB_DIFF_LIM_USED` 8), i.e. **at or above** the limit fails.

## 2. The belt-edge hypothesis, tested against the mask and the background (REFUTED)

Three independent reads, all from the same session (`ps_fft_dual/a1_read_20261026.tcl`):

1. **No strip exists.** `LIVE_MASK` (0x126C0000, 14,400 B) held **426 cells** with bbox lattice
   x44..93 / y50..79 (source x352..751, y400..639) — the board only. Per-row counts: the maximum is
   **23 of 160** cells (row 72). The per-loop pre-cluster mask (`TRACK_MASK`, 0x126B8000) held 490
   cells and also has **no row** at or above 140/160. A belt-edge band would be a full-width row
   strip; there is none, before or after the cluster rule.
2. **Where the belt edge is.** The background image `BG_BASE` (0x12700000, 640x360) has its strongest
   row-to-row change at bg row 179→180, `|d rowmean|` **43.4** (next: 24.9 at 178→179), i.e. source
   rows **358..361**. The board's top edge is at source row 400 (`MB_PART_BY0` 50). The group is at
   source y544..575 — **144 px below** the board's top edge, not at it.
3. **What the mask is made of there.** Inside the group box, the background grid reads 192..196 and
   the live 8x8 lattice reads 117..154: the mask cells are set because the **board** covers the white
   belt (a 55-75 grey step), not because of an edge artefact. `MB_PART_RULE` 1 (background rule),
   `MB_PART_BGWHY` 0, `MB_BG_MEDD` 3 (the belt's own noise floor).

## 3. What the difference actually is: content in the reference that is not on the board

The reference image (`REF_BASE`, 0x12400000, 2,764,800 B) and the live store (`MB_CAP_RDIDX` = 2 →
0x10C00000, same size) were dumped in one session. Both are coherent frames of the same station (the
same room background, the same PCB artwork); they differ in **four black marks on the PCB in the
reference** that the live frame does not have. Counting pixels inside the board box with green
< 55 grey: **2,249 in the reference vs 186 in the live frame**; at < 50 grey, 1,908 vs 127. The
reference's marks touch 191 lattice cells.

`dl/ng_20261026/ng_group_pair.png` shows the group rectangle (x400..520, y528..600) as live |
transform-warped reference | |d|x3: the diagonal black line is present only in the reference, and the
right-hand panel shows it as the difference.

**Instrument validation (this is why the conclusion is not just "the picture looks different").** An
offline replay of the firmware's fine pass (`ps_ui/a1_replay.py`, exactly `ref_at`/`ref_cell8`/
`cell_mean8`/`ref_part_ok`, the published transform scale 254, dx16 646, dy16 -288, angle 0) on the
same dump reproduces the firmware's **own** numbers:

| quantity | firmware word | replay |
|---|---|---|
| DAREA (largest 8-connected group of cells over DEFECT_AMP 30) | 11 | **11** |
| group box | 52,68..59,71 | **52,68..59,71 (identical)** |
| cells with |d| > 30 in the judged set | 29 | 31 |
| per-cell |d| grid (`FINE_DEEP`, 0x126EC000) | — | **14,117 of 14,400 cells identical**, max diff 13 |

**Two counterfactuals, one variable each** (`a1_replay.py` section B/C):

* a local translation refinement of the reference sampling, ddx/ddy in ±3 px: the group's mean |d|
  stays 21-27 (best 21.4 at (3,3)) while the surrounding ring improves to 14.9 at (0,+3) — a
  placement error would improve both. **Not a registration residual.**
* removing the group's own mean difference (+25.3 grey, i.e. treating it as a brightness offset):
  mean |d| falls from 26.3 to 20.7, max from 76 to 51. **Not a photometric offset.**

So the group is neither the belt edge, nor placement, nor lighting: it is content in `REF_BASE`.

## 4. The operation that restored PASS, and what it proves

`MB_CMD` = 9 (handler `main.c:13782-13789`; it refuses when camera 0 is STUCK or clipping, both false:
`MB_AEC_STATE` 1, `MB_CAM0_CLIP` 6) took a reference of the frame in view. `MB_TOL_EPOCH` advanced
22 → 23 (`ref_take` → `tol_reset`, `main.c:7492`), `MB_PART_REF` became **420**, `MB_DIFF_DX/DY` 0/0,
and every comparison since read `MB_DIFF_DAREA` 0 / `MB_DIFF_VERDICT` 0 / `MB_DIFF_FOVER` 0 over
**44 consecutive comparisons** (`MB_DIFF_N` 1135 → 1179). The firmware self-test on demand
(`MB_CMD` = 20) read `ST verdict=0 code=0 fail=0x0 res=0x0`.

That is the acceptance: a good board at the station returns **PASS with DAREA 0**, and the reason the
earlier patch appeared is **the reference, not the board and not the mask** — with the numbers above.

**A new station risk, stated rather than buried:** the clean board's reference mask is **420** against
the `PART_MIN_PTS` floor of **400** (1.05x; `main.c:3424`, check 1 of the self-test). The previous
reference read 671. `preflight.py` passes, but a retake that lands 5% lower would FAIL REF and refuse
every comparison (`MB_DIFF_OK` 5), the fault the self-test was built for
(`dl/SELFTEST_20261026.md`). Why the clean board's mask is smaller than the marked board's was not
investigated; it is not a change made here.

## 5. Frame averaging: target or count, what resets it, and what it does

* **Target, not count.** `#define MB_AVG_N 408u /* byte 1632: HOST: frames to average, 1 = off */`
  (`main.c:2260`); `MB_AVG_CNT` (409) is "frames the last comparison averaged" (`main.c:2261`).
  The boot writes `AVG_N_DEFAULT` = 8 (`main.c:3972`, write at `main.c:12934`); each loop clamps a
  target above 16, adopts any change, resets the accumulators and echoes the in-force value
  (`main.c:13629-13632`). A target below 2 makes `avg_sample` return immediately (`main.c:4016`) and
  `avg_take` return 0 (`main.c:4069`), so the comparison uses the single frame
  (`main.c:8217-8219`).
* **What does NOT reset it:** the readiness gate only declines a sample (`main.c:4019`, counted in
  `MB_AVG_SKIP`), a reference retake does not touch it (`ref_take`, `main.c:7356-7493`), and the
  per-loop mask publisher does not either. Only a host write or a reboot changes it.
* **What was found:** the word stood at **1** with `MB_AVG_CNT` 1. This board's own history says it
  had been 8 earlier in the boot: `MB_AVG_TICKS` was frozen at **9,373,111 ticks = 28.0 ms**, a value
  only `avg_sample` writes, and `MB_AVG_SKIP` was 15, a counter only the sampler increments. So the
  boot default took effect, the sampler ran, and a host write later set it to 1. **Which host wrote it
  is not determined**: no tool in this repo writes word 408 today (`dl/host_qc/*.py` only defines the
  name; the stage-2 scripts that write it are 2026-10-24 acceptance tools), so the writer was a
  one-off command, and that is stated as unknown rather than guessed.
* **Re-enabled and measured.** `MB_AVG_N` = 8 → `MB_AVG_CNT` 1 → 6 → **8**, `MB_AVG_TICKS` taking a
  new value every comparison (9,367,114 .. 14,747,590 ticks = 28.0-44.0 ms per pass). One-variable
  A/B (`a1_avgab_20261026.tcl`), scene and reference untouched, only word 408 written:

| arm | sigma16 (mean of 8 comparisons) | grey |
|---|---|---|
| N=1 | 38.1 | 2.38 |
| N=8 | 34.6 | 2.16 |
| N=1 | 37.5 | 2.34 |
| N=8 | 41.1 | 2.57 |
| N=8 (final) | 42.4 | 2.65 |

  **Measured negative, stated:** on this scene the frame averaging is *active* but its effect on
  `MB_DIFF_SIGMA` is **not resolvable** — the N=8 arms straddle the N=1 arms (34.6 vs 38.1/37.5/41.1/
  42.4). `MB_DIFF_SIGMA` is the spread of the signed cell differences over the judged cells, which
  after a fresh reference is dominated by the spatial interpolation residual (1.6-2.8 grey), not by
  frame noise; the documented 7.2 → 4.4 count improvement was measured on a different statistic in
  stage 2. I did not reproduce that improvement here and do not claim it.
* **Left in force:** `MB_AVG_N` = 8 (the build's default), `MB_AVG_CNT` 8.

## 6. What changed

* **Firmware: nothing.** No file under `ps_ui/` was modified in this item.
* Host words written: `MB_AVG_N` 1 → 8 (restoring the documented default) and `MB_CMD` 9 (reference
  retake). No `MB_MAGIC`, no bitstream, no power cycle, no VDMA register.
* New instruments listed at the top; `dl/mb_map_20261026.tcl` regenerated
  (`python dl/mb_words.py --tcl dl/mb_map_20261026.tcl`, 367 names).
* Evidence images `dl/ng_20261026/` (reference board, live board, mask overlay, group pair).

## 7. What remains unverified

1. **Why the reference contained a board with black marks.** The dump proves the content difference;
   it does not say whether the marks were marker lines on the same unit that were later removed, or a
   different unit of the same design. The station log would have to say which board was in front of
   the camera when `MB_CMD` = 9 was sent at 19:43.
2. **Who wrote `MB_AVG_N` = 1.** Not in this repo's tools; a one-off host command is the only
   mechanism, so the writer is unknown.
3. **The averaging's effect on the verdict.** With DAREA 0 and `MB_DIFF_FOVER` 0 the averaged and
   unaveraged arms both PASS, so the averaging's benefit is not demonstrated on a *defective* part at
   this station.
4. **The reference mask margin (420 vs 400).** Passing but thin; a retake landing below 400 would
   refuse every comparison. The cause of the 671 → 420 drop is not investigated.
5. **The 40 px placement change** between the reference and the live frame (dx16 646, dy16 -288) was
   the board's position, and the registration accepted it (`MB_REG_STATE` 1, mode 2); this item did
   not test placements beyond it.

## 8. Reproducing it

```
# 1. dump the words + the buffers the comparison used (read-only, one client)
xsdb ps_fft_dual/a1_read_20261026.tcl  .tmp/a1
xsdb ps_fft_dual/a1_read2_20261026.tcl .tmp/a1
# 2. replay the fine pass and compare with FINE_DEEP (known answer), then the counterfactuals
python ps_ui/a1_replay.py
python ps_ui/a1_marks.py
# 3. evidence images
python ps_ui/a1_png.py
# 4. the two controlled host writes + the averaging A/B (writes MB_AVG_N and MB_CMD only)
xsdb ps_fft_dual/a1_fixcmd_20261026.tcl
xsdb ps_fft_dual/a1_avgab_20261026.tcl
# 5. the host gate
python dl/host_qc/preflight.py
```
