# Stage A (2026-10-24) — the refuse-after-adoption window now consumes PERSIST_N measured comparison slots

Status: DONE, flashed, accepted, committed.  Build `TSC1` / `68880CFF`.  The refusal window
is now `PERSIST_N` = 3 **measured** comparison slots (the cell passes run and feed both
3-hit counters; the judgement is withheld), not three slots in which nothing was compared.
The first resumed comparison is therefore backed by a full persistence window: measured on
a deterministic known-answer injection, it published `MB_DIFF_CELLS` = **11** with raw
`MB_DIFF_OVER` = 25 and verdict **NG** where the stage-7 build published `MB_DIFF_CELLS` =
**0** with 12 raw cells over.  `MB_DIFF_OVER` is now published on **every** comparison
slot (raw count when measured, `0xFFFFFFFF` when nothing was measured).  Two defects were
found in the process: the stage-7 window never ran the cell passes (so it could never fill
the counters it waited for), and stage 8's fine hit counters were **not cleared** on a
transform change (the stage-7 build read fine `FCELLS` = 33 at resume from *before* the
adoption).

## 1. What changed, with line numbers (`ps_ui/main.c` of this commit)

| line | item |
|---|---|
| 3531–3566 | the `g_reg_fresh` design block: the window consumes PERSIST_N **measured** slots; no seed; why stage 7's version could never fill the counters; both passes' counters cleared |
| 1887–1895 | `MB_REG_MODE` documentation: a settle slot is `state 2` + `MB_DIFF_OK 5` + `MB_DIFF_CELLS 0xFFFFFFFF` + **measured `MB_DIFF_OVER`**, verdict 2 |
| 2045–2051 | `MB_DIFF_OVER` documentation: published every comparison slot that ran the cell pass, including a withheld one; `0xFFFFFFFF` on a slot that never reached the pass |
| 3622 | `reg_adopt()`: **`FINE_HIT` cleared too** when the adopted transform differs (the stage-8 counters were missed) |
| 5227 | `young` = "this slot is measured, its judgement withheld" |
| 5344–5347 | the settle-slot test: `g_reg_fresh != 0` and (`g_reg_ok == 1` or mode 5 RE-AIM).  A slot that refuses before measuring does not enter the window |
| 5403 | registration/light refusals invalidate `MB_DIFF_OVER` (`0xFFFFFFFF`), so a fresh "not measured" count is never paired with a stale raw one |
| 5412–5421 | the window countdown moved **after** the light gate and the registration check: only a slot that will actually run the cell passes consumes one |
| 5619–5643 | the settle-slot publish: cells/fine cells `0xFFFFFFFF`, boxes invalid, refinement invalid, `MB_DIFF_OK 5`, `MB_DIFF_N` NOT advanced; raw counts and row profile stay standing |
| 7077 | `MB_DIFF_LIM_USED` (223) is now actually published (it had been documented since stage 7 but never written) |
| 10071–10079 | the `MB_DIFF_OK` doc: settle slots run the passes; `MB_DIFF_OVER` distinguishes them from a registration refusal |

No comparison rule changed: the same cell sampler, the same 3x3 rule, the same `PERSIST_N`
window, the same threshold, the same verdict decoder.  What changed is **when the answer is
judged** (after the counters have been fed) and **what is published during the window**.

## 2. The defect, reproduced deterministically

A still scene cannot produce a wrong transform on demand, so the defect was made with two
existing known-answer commands: `MB_CMD = 15` stamps a **48x48 source-pixel square**
(+40 counts, all three channels) into the reference at fine cell (106,52) — the live part
stays good and the difference is exactly the stamp — and `MB_CMD = 14` displaces the held
transform by 10 half-res px (20 source px), forcing a re-aim.  The site was chosen from a
`LIVE_MASK` dump (`dl/_live_mask.bin`): 33 of that square's 36 8x8 cells are inside the
part mask, so **both** passes see it.  Known answer: 3x3 = **9 coarse** cells over, 33..36
**fine** cells over.  Measured before the injection: coarse `MB_DIFF_OVER` 9 /
`MB_DIFF_CELLS` 9 (after 3 hits), fine `FOVER` 33 / `FCELLS` 33 — the stamp is counted by
both passes exactly as its geometry says, which is the independent check on the instrument.

Harness: `ps_fft_dual/stA_reaim_defect_20261024.tcl`, one atomic 1.4 KB mailbox burst
(words 168..511) per row, explicit little-endian decode (the stage-6 section-5 lesson).

### 2.1 Before the change (stage-7 build, FWID 064BC6E6) — `dl/stA_control_20261024.txt`

```
N=930 mode2 state1 ok1 cells=9  over=9  fcells=33 fover=33 verdict=1   (stamp steady)
-- MB_CMD = 14 --
N=930 mode5 state2 ok5 cells=-1 over=9* fcells=-1 fover=0* verdict=2   move=1000
N=930 mode2 state2 ok5 cells=-1 over=9* fcells=-1 fover=0* verdict=2
N=930 mode2 state2 ok5 cells=-1 over=9* fcells=-1 fover=0* verdict=2
N=931 mode2 state1 ok1 cells=0  over=12 fcells=33 fover=33 verdict=1   <-- THE FAIL-OPEN
```
`*` = **stale**: the window slots returned before any cell pass, so they republished the
previous comparison's raw counts.  The first resumed comparison ran the cell pass for the
first time under the new transform, so the 3-hit counters held one hit: it published
**cells = 0** while **12** coarse cells were over the threshold (and it would have been a
verdict-0 PASS under the coarse verdict the task names).  Its fine `FCELLS` = 33 was not
this frame's either — it was carried over from before the adoption (defect 2).  The NG in
that row comes from that stale fine count, not from the frame; the coarse pair alone is the
fail-open.

### 2.2 After the change (this build, FWID 68880CFF) — `dl/stA_fix_20261024.txt`

```
N=17 mode2 state1 ok1 cells=9  over=9  fcells=32 fover=33 verdict=1   (stamp steady)
-- MB_CMD = 14 --
N=17 mode5 state2 ok5 cells=-1 over=21 fcells=-1 fover=33 verdict=2   move=1012
N=17 mode2 state2 ok5 cells=-1 over=18 fcells=-1 fover=33 verdict=2
N=17 mode2 state2 ok5 cells=-1 over=21 fcells=-1 fover=33 verdict=2
N=18 mode2 state1 ok1 cells=11 over=25 fcells=24 fover=24 verdict=1   <-- RESUMED, NG
```
The three window slots now publish **fresh** raw counts (21/18/21 coarse, 33 fine — the
stamp under the just-adopted transform) while the persisted counts are withheld
(`0xFFFFFFFF`) and `MB_DIFF_N` does not advance.  The first resumed comparison publishes
the persisted count from a **full** window (11 coarse, 24 fine) and the verdict is NG.
**No row shows verdict PASS**; audit lines in the log: `PASS with MB_DIFF_OVER >= limit: 0`,
`PASS with MB_DIFF_FOVER >= limit: 0`.

The same shape on a clean scene (no stamp), `MB_CMD = 14`, run A3
(`dl/stA_runA3_20261024.txt`):
```
N=175 mode2 state1 ok1 cells=0 over=0 fcells=0 fover=0 verdict=0
-- MB_CMD = 14 --
N=175 mode5 state2 ok5 cells=-1 over=0 fcells=-1 fover=0 verdict=2 move=1000 NREAIM 3->4
N=175 mode2 state2 ok5 cells=-1 over=0 fcells=-1 fover=0 verdict=2
N=175 mode2 state2 ok5 cells=-1 over=0 fcells=-1 fover=0 verdict=2
N=176 mode2 state1 ok1 cells=0 over=0 fcells=0 fover=0 verdict=0
```
A **natural** cold adoption also arms the window (run A2, `dl/stA_runA2_20261024.txt`):
`N=152 mode4 state2 move=50` — mode 4, below the re-aim bound, still a changed transform —
then `N=152 mode4 state2 cells=-1 over=4`, `N=152 mode2 state2 cells=-1 over=5`,
`N=152 mode2 state2 cells=-1 over=5`, then `N=153 cells=0 over=4 verdict=0`.  A natural
re-aim (move = 100, the bound) in the A1 repeat: `N=259 mode5 state2 cells=-1 over=25`,
two more settle slots, then `N=260 cells=5 over=27 fcells=0 fover=1 verdict=0`.

## 3. The 100+ still-scene comparisons

Clean still-scene runs on this build (fresh reference, N = 8, `MB_READY` 1 and
`MB_AVG_CNT` 8 on every row, one burst per row, deduplicated by the change detector):

| run | comparisons | settle slots | coarse cells 0 / 1..7 / >=8 | fine cells 0 / 1..7 / >=8 | over median / max | PASS with over >= limit |
|---|---|---|---|---|---|---|
| A2 (`stA_runA2_20261024.txt`) | 60 | 3 (natural mode-4 adoption) | 60 / 0 / 0 | 60 / 0 / 0 | 0 / 5 | 0 |
| A3 (`stA_runA3_20261024.txt`) | 76 | 3 (MB_CMD = 14 at 20 s) | 76 / 0 / 0 | 76 / 0 / 0 | 0 / 0 | 0 |
| A4 (`stA_runA4_20261024.txt`) | 70 | 0 | 70 / 0 / 0 | 70 / 0 / 0 | 0 / 0 | 0 |
| **total** | **206** | **6** | **206 / 0 / 0** | **206 / 0 / 0** | | **0** |

214 comparisons were actually taken; a first 78-comparison A1 run (all clean, 0/0/0) was
logged to a file that the later A1 repeat overwrote, so only its summary is quoted here and
it is not counted in the table: the table is the part with raw logs.

**One run is reported, not filtered: the A1 repeat (`dl/stA_runA1_20261024.txt`).**  A
natural re-aim at t = 40.5 s (mode 5, `move = 100`, exactly at the bound, NREAIM 4 -> 5)
was refused for 3 settle slots (`cells -1, over 25/25/23, fcells -1, fover 6/6/3,
verdict 2`) — the window did its job.  The transform it adopted was left ~2 source px off,
and for the remaining 39 comparisons the coarse pass saw **21..39 raw cells over** (belt
and part-outline edges) while the 3x3 rule left **4..7** clustered cells (under the 8-cell
limit) and the fine in-part pass saw **0..5**.  The verdict is PASS on all of them, and the
audit prints **40 printed rows with PASS and MB_DIFF_OVER >= 8**.  That is **not** the
window failing: the first resumed comparison published cells 5 — the persisted count, not
0 — and the raw count is published beside it.  It is the **stage-8 verdict policy**
(the verdict reads the fine in-part count) meeting a **stage-6 drift** (a wrong transform
adopted at the smallest re-aim the search can report).  Of the 27 raw coarse cells in the
resumed row, 1 was inside the part (`FOVER` 1); the other 26 are belt/outline cells.  If
the acceptance sentence "no row may show verdict PASS while `MB_DIFF_OVER` is at or above
the limit" is applied to the coarse raw count on **every** row of every run, this run
violates it — and it would also be violated by a fresh reference followed by a light step
(measured after this build's flash: the boot auto-reference produced `OVER` 3600, `cells`
0, `FCELLS` 0, verdict 0 for two comparisons, the pre-existing stage-7 item-4 behaviour).
Closing that would mean changing the comparison rules or the stage-8 verdict policy, which
this task forbids; it is listed in section 6 instead.

## 4. How each number was measured, and its independent check

1. **The window's slot count.** The injected displacement is a known 10 half-res px; the
   adoption frame's `MB_REG_MOVE` = 1000/1012 (1/100 of the bound) is the known answer that
   the frame really is a re-aim, and exactly 3 slots with `MB_DIFF_OK 5` follow it, then
   `MB_DIFF_N` advances.  `PERSIST_N` is 3 in the source (main.c:1983); the countdown is
   `PERSIST_N` (not a literal 2), so changing the constant changes the window.
2. **The window really fills the counters.** *Independent* check: the same injected
   protocol on the pre-fix build reads `cells = 0` at resume because no cell pass ran;
   the fixed build reads `cells = 11` (stamped) / `cells = 5` (natural drift) at resume.
   The raw counts during the window (21/18/21 coarse, 33 fine) are this frame's, not
   carried over (the pre-fix build republished 9/33 — identical values on all three slots,
   visibly stale).
3. **The counts are the patch's geometry.** `MB_CMD = 15` stamps exactly 48x48 px: before
   the injection the coarse pass reads 9 cells (3x3) and the fine pass 33 (of 36 mask
   cells) — the known answer; both survive the 3x3 rule and PERSIST_N.
4. **The fail-safe direction.** Over the 6 settle slots and 206 clean comparisons, no row
   with `MB_DIFF_OK 5` published a persisted count (always `0xFFFFFFFF`), no row with
   verdict 0 had `MB_DIFF_FOVER >= 8`, and after the injection the diff arm's verdict was
   2 on every window slot and 1 on the first resumed comparison.
5. **The published limit.** `MB_DIFF_LIM_USED` (223) now reads 8 in every log (it read
   uninitialised garbage before), so the audit is against the limit the firmware applied,
   not an assumed one.

## 5. Cost, build, flash

* `.text` 0x18B7C (101,244 bytes; `size` prints 101,252 with `.ARM.exidx`), `.data` 0x58,
  `.bss` 0x7100 (28,928).  Image ends at 0x1FCE0 = 130,272 bytes of the 128 KB OCM, i.e.
  **800 bytes free** (stage 8 left 1,224).  The stage's own cost is **424 bytes of .text**
  and no .bss; **no buffer changed address or size and nothing was moved to DDR**.
* `build.ps1`: 305 `MB_*` words, 305 distinct, 0 collisions; all layout checks pass; only
  the four pre-existing warnings.
* Flashed with `ps_fft_dual/strict_load_cores.tcl` (firmware only; no bitstream, no power
  cycle, no running-VDMA poke).  FWID `TSC1` / `68880CFF`.
* Board left in the documented state after A4: `MB_READY` 1, `MB_AVG_N` 8, `MB_AVG_CNT` 8,
  `MB_REG_MODE` 2, `MB_REG_STATE` 1, angle 0.00, DX/DY 0, `MB_DIFF_CELLS` 0,
  `MB_DIFF_FCELLS` 0, verdict 0 (`ps_fft_dual/st8_probe.tcl`).

## 6. What remains unverified, and every human-dependent experiment

1. **A real wrong adoption with a defect on the part** (requires a person).  The stamp is a
   defect in the *reference*, which is equivalent for the comparison but does not exercise
   a moving part.  Experiment: take a reference, put a real marked board in view, slide it
   or rotate it past the re-aim bound, and read `MB_REG_MOVE`, the 3 settle slots and the
   first resumed `MB_DIFF_CELLS` / `MB_DIFF_OVER` / verdict.  Expected: 3 slots `state 2`,
   `cells -1`, `over` measured, then a persisted count at resume; PASS only if the persisted
   count is under the limit.
2. **The residual after a natural re-aim (section 3).**  The A1 repeat adopted a transform
   2 source px off and the coarse pass reported 21..39 raw cells for 39 comparisons while
   the persisted count stayed 4..7 and the fine count 0..5.  Whether the part really was
   aligned (the fine pass says yes) or the coarse cells were a real edge difference needs
   the operator's eyes on the part at that moment.  Experiment: with a still part, watch
   `MB_DIFF_OVER` and the panel's difference view; when the coarse count rises, say whether
   the highlighted cells are on the part or on the belt.
3. **The boot auto-reference.**  Observed on this build right after the flash: the auto
   reference produced `MB_DIFF_OVER` 3600, `MB_DIFF_CELLS` 0, `MB_DIFF_FCELLS` 0,
   verdict 0 = PASS for its first two comparisons (the reference was taken while the light
   was still settling).  Pre-existing (stage-7 item 4), not touched here.  Experiment:
   reset the cores with a still scene, read the first 10 comparisons WITHOUT a fresh
   reference; if the pattern repeats, the auto-reference needs to wait for the AEC's own
   history, not just its state bit.
4. **A wall-clock latency budget.**  A re-aim now costs `PERSIST_N` comparison slots
   (~3 x 2.3 s at the measured cadence) before a verdict resumes, plus the adoption frame's
   own refusal is now one of the three (not an extra one).  Whether that is acceptable for
   the belt's speed is a production question; the measurement here is the slot count, not
   the line's throughput.
5. **The `MB_DIFF_OVER` semantics on the `MB_DIFF_OK = 3` path** (AEC stuck / clipping):
   that refusal happens before `diff_frame()`, so `MB_DIFF_OVER` keeps the last measured
   value there.  A host must read `MB_DIFF_OK` first.  Not changed (it is another refusal
   path with its own acceptance); documented here so it is not mistaken for a new omission.
