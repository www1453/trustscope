# Item 3 (2026-10-26, session B1): the boot self-test's per-check inputs are frozen with the verdict

Firmware `ps_ui/main.c`, source hash **434636D9** (flashed with `strict_load_cores.tcl` only;
`MB_FWID0..2` = 31435354 36343334 39443633). The same build also carries item 5 (camera 1's
budget instrument) and item 1; see `dl/AEC_EMPTYBELT_20261026.md`.

## 0. The one-paragraph answer

`dl/SELFTEST_20261026.md` section 5 recorded the defect: the four checks read words the
comparison publishes, and the next comparison (~every 2.4 s) overwrote them before a host read
them -- measured on the >50 % occlusion as `MB_ST_VERDICT` 1 / code 2 / fail 0x0A / res 0x44
next to `MB_BG_MEDD` and `MB_BG_CELLS` reading **0xFFFFFFFF**. Nine stores at the end of
`boot_selftest()` now copy the values the checks actually used into `MB_ST_IN_*` (534..542) at
the same instant the verdict is published. Measured on the board: in a failing state the
frozen words were **byte-identical across four reads over 7.5 s while the live words moved
underneath them**, the boot run's own snapshot was different and explained its own verdict,
and on the previous build the same words read pure DDR garbage.

## 1. What changed (file:line)

* `main.c:1603-1646` -- the nine words: `MB_ST_IN_REF` 534, `_REFOK` 535, `_PTS` 536,
  `_BGC` 537, `_MEDD` 538, `_RULE` 539, `_BGOK` 540, `_AEC` 541, `_CLIP` 542. Mailbox
  375 -> 384 words, 0 collisions, four pre-existing warnings.
* `boot_selftest()` -- nine `R32` stores after the verdict words, from the same registers the
  checks just read; the 0xFFFFFFFF sentinel is preserved (a "not measured" input stays
  "not measured", it is not turned into a fabricated zero).
* `dl/host_qc/qc_mailbox.py` -- WordDefs for the nine; `dl/host_qc/preflight.py` prints them
  in the same one-line verdict as `used(ref=... pts=... bgc=... )` (that host-side edit is in
  the working tree, see section 5).

Which check reads which word: check 1 REF -> REF, REFOK; check 2 BG -> RULE, MEDD, BGOK, PTS,
BGC; check 3 AEC -> AEC, CLIP; check 4 MASK -> PTS, BGC.

## 2. The measurement that makes it evidence

**A. The frozen words in a FAILING state, produced without an operator.** On the empty belt
with a fresh background the self-test genuinely fails: `MB_ST_VERDICT` 1, code 2, fail 0x0A,
res 0x44 (checks 2 and 4), because the mask count is 0 while the presence detector reads 48
cells (>= `BG_MIN_CELLS` 32) -- the two detectors really do disagree about a bare belt.

```
BEFORE  live(st_verdict=1 code=2 fail=0xA res=0x44 run=1 | pts=0 ref=434 rule=1 medd=4 cells=48 ...)
BEFORE  frozen(ref=434 refok=1 pts=581 bgc=0 medd=UNM rule=0 bgok=0 aec=1 clip=0)   <- the BOOT run
triggered CMD=20, run 1 -> 2
R1  frozen(ref=434 refok=1 pts=0 bgc=48 medd=2 rule=1 bgok=1 aec=1 clip=0)
R2  frozen(ref=434 refok=1 pts=0 bgc=48 medd=2 rule=1 bgok=1 aec=1 clip=0)
R3  frozen(ref=434 refok=1 pts=0 bgc=48 medd=2 rule=1 bgok=1 aec=1 clip=0)
R4  frozen(ref=434 refok=1 pts=0 bgc=48 medd=2 rule=1 bgok=1 aec=1 clip=0)
R1..R4 live  medd/cells moved underneath: 3/48, 3/49, 5/44, 5/43
```
Three things at once: the frozen values are REAL numbers (not 0xFFFFFFFF), they are the
values that produced the verdict (pts 0 < 400 while bgc 48 >= 32 is exactly why checks 2 and
4 failed), and they do not move while the live words do. The boot run's snapshot differs and
explains ITS verdict: at boot no background was loaded yet, the green rule ran (`rule` 0,
`bgok` 0), the mask was 581, and check 2 failed for that reason.

**B. The control on the previous build.** On the item-1-only build the same words read DDR
garbage: `preflight.py` printed `used(ref=4223242643 refok=4210450331 ... aec=517466697 ...)`.
So the value quoted in A is published by this change and is not a coincidence of DDR contents.

**C. The PASS direction on the final build, with the board in view** (after `MB_CMD` = 9:
`MB_PART_REF` 675, `MB_DIFF_OK` 1, PASS): `MB_ST_VERDICT` 0 / code 0 / fail 0x00 / res 0x00,
`MB_ST_TICKS` 156 ticks = 0.47 ms, and
`frozen(ref=675 refok=1 pts=737 bgc=1448 medd=2 rule=1 bgok=1 aec=1 clip=0)` -- the inputs of
a passing test, quotable next to it. `preflight.py` then printed the same values in its line:
`PREFLIGHT PASS code=0 fail=0x00 | ref=675/400 bg(medd=2 cells=1576 rule=1 why=0 state=1) aec=1 clip=0 mask=762 vs presence=1576 used(ref=675 refok=1 pts=740 bgc=1568 medd=2 rule=1 bgok=1 aec=1 clip=0)`,
exit 0.

## 3. Cost

Nine stores; `MB_ST_TICKS` 130-156 ticks = 0.39-0.47 ms per run, unchanged from the 0.46-0.48
ms measured for the same function before (dl/SELFTEST_20261026.md section 3). No buffer, no
MMU change, no arithmetic.

## 4. Limits

* The frozen words are a snapshot of the SECOND the checks ran, not of the frame they are
  about. A check that reads a stale published word freezes a stale word -- honestly labelled,
  because the same number is what the verdict used.
* `MB_ST_IN_BGC`/`MB_ST_IN_MEDD` legitimately read 0xFFFFFFFF when the comparison had not
  measured them at that instant (the boot run above shows exactly that, `medd=UNM bgc=0`).
  A reader must not treat "UNM" as a failure of the freeze; the verdict words say what the
  check decided with it.
* The AEC failure path (check 3 failing) is still not produced on the board -- unchanged from
  dl/SELFTEST_20261026.md; the frozen word would show it but the state cannot be staged.

## 5. What was NOT committed

`dl/host_qc/preflight.py` carries the host-side half of this change (the `used(...)` segment
in the one-line verdict and the nine names in `QUOTE_WORDS`), but at commit time that file
also contained another agent's uncommitted work (186 inserted lines across the same file), so
it was deliberately left out of this commit rather than committing someone else's work. The
firmware side and the tcl acceptance (`ps_fft_dual/b3_selftest_20261026.tcl`) are committed
and are what the quoted evidence came from.

## 6. Reproducing it

```
xsdb ps_fft_dual/b3_selftest_20261026.tcl       # trigger CMD=20, print frozen + live, 4 rounds
python dl\\host_qc\\preflight.py                 # one line, frozen inputs included
python dl\\host_qc\\check_words.py               # host map vs main.c: 90/90
```
