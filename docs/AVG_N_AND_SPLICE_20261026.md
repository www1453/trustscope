# Two offline investigations from the 2026-10-26 performance analysis

**Everything here is offline.** No board, no xsdb, no build, no flash, no edit of `ps_ui/main.c`,
no `dl/host_qc/calibrate.py`, no STM32. Sources: the firmware at **HEAD `845be5d`**, the host tools
in `dl/host_qc/`, the Tcl instruments in `ps_fft_dual/`, and the data files already on disk.

**Which line numbers.** `ps_ui/main.c` was **being edited while this analysis ran** (14,493 lines in
`git show 845be5d:ps_ui/main.c`, 14,662 at 21:01, 14,514 at 21:11). Every `main.c:<n>` below is a
**HEAD `845be5d`** line number, which is also what `dl/PERF_20261026_proposal.md` cites, so the two
documents can be read together. Re-derive with `git show 845be5d:ps_ui/main.c`. Files under
`dl/host_qc/` and `ps_fft_dual/` are cited as they are on disk now (QC tools and Tcl scripts, not
under edit).
Evidence tags: **E2** measured (board or data on disk), **E1** read from code, **E0** model.

---

# Investigation 1 — who writes `MB_AVG_N = 1`

## 1.0 The one-paragraph answer

`MB_AVG_N` (word **408**, `#define MB_AVG_N 408u`, HEAD `main.c:2272`) is a host target **and a
firmware echo**. The firmware seeds **8** once at boot (`main.c:13163`) and then, **every loop**,
reads the word, adopts any change, and **writes it back** (`main.c:13859-13862`). That echo is a
latch: one host write of 1 is in force for ever, and the firmware has no way to tell its own echo
from a fresh host write. **Nine Tcl sites in eight files** can write 408 and **no Python tool in the
repo can** — but none of the Tcl tools existed yet (or was run) in the window that produced the 1 read
at 19:51, so **the writer of tonight's 1 is outside the tracked tools and cannot be named from repo
artifacts**. What *can* be measured is that the word was written **at least twice**, that no tool
restores it, and where the safety net is missing (`preflight.py` never looks at it). The fix I would
pick is a **named refusal in the host gates**, not a restore and not a firmware re-seed — §1.5.

## 1.1 What the word is, and why 1 is sticky  (E1)

```
main.c:2272   #define MB_AVG_N       408u  /* byte 1632: HOST: frames to average, 1 = off     */
main.c:2273   #define MB_AVG_CNT     409u  /* byte 1636: frames the last comparison averaged  */
main.c:2276   #define MB_AVG_TICKS   411u  /* byte 1644: ticks the last sampling pass took    */
main.c:4069   #define AVG_N_DEFAULT 8u     /* the build's documented default (measured) */
```

```c
/* boot, once, before the first loop: */
main.c:13163      R32(MAILBOX + MB_AVG_N * 4u) = AVG_N_DEFAULT;

/* every loop, after the render, before the comparison: */
main.c:13859      uint32_t want = R32(MAILBOX + MB_AVG_N * 4u);
main.c:13860      if (want > (uint32_t)AVG_N_MAX) { want = (uint32_t)AVG_N_MAX; }
main.c:13861      if (want != g_avg_n) { g_avg_n = want; avg_reset(); }
main.c:13862      R32(MAILBOX + MB_AVG_N * 4u) = g_avg_n;   /* echo what is IN FORCE */
```

Consequences that decide everything else (E1):

* **A host write is permanent.** The firmware copies the word into `g_avg_n` and writes it straight
  back, so the value cannot "time out"; nothing else in the firmware writes the word.
* **Nothing restores it.** `avg_reset()` (`main.c:4003`) zeroes the accumulators, not the target;
  `ref_take()` (`main.c:7428`) does not touch it; the boot self-test does not either. Only a reboot
  (re-runs `:13163`) or another host write changes it.
* **`MB_AVG_CNT` cannot disambiguate "off" from "one frame".** It is published as
  `(navg != 0u) ? navg : 1u` (`main.c:8283`), so at N=1 it reads **1** whether the sampler is off or
  has accumulated one frame.
* **`MB_AVG_TICKS` is stale, not zero, when the sampler is off** — `avg_sample()` returns before
  writing `g_avg_ticks` when `g_avg_n < 2` (`main.c:4028`), and the stale value keeps being published
  every loop. So the word that would expose "the sampler never runs" reads a healthy **28.0 ms**.

## 1.2 Every writer of word 408 in the repo  (E1; complete as of this tree)

Two firmware sites and nine Tcl sites. The grep set is in §1.7; `dl/host_qc/*.py` **writes nothing**.

| # | file:line | the write (verbatim) | when it runs | restores the previous value? |
|---|---|---|---|---|
| F1 | `ps_ui/main.c:13163` (HEAD) | `R32(MAILBOX + MB_AVG_N * 4u) = AVG_N_DEFAULT;` | once, at boot, before the first loop | n/a — it *is* the seed (8) |
| F2 | `ps_ui/main.c:13862` (HEAD) | `R32(MAILBOX + MB_AVG_N * 4u) = g_avg_n;` | **every loop, for ever** | no — this is the latch; it re-writes whatever a host left |
| T1 | `ps_fft_dual/a1_fixcmd_20261026.tcl:59` → `:37-41` | `set echo [WR MB_AVG_N 8]` … `mwr -force [expr {0x10F00000 + $::MB($name)*4}] $value` | by hand, once, then polls | no. Deliberately puts the production value back; if the script dies after the write, 8 stays (the safe direction) |
| T2 | `ps_fft_dual/a1_avgab_20261026.tcl:28`, arms at `:56-60` | `mwr -force [expr {0x10F00000 + $::MB(MB_AVG_N)*4}] $n` with `arm 1`/`arm 8` ×5 → **1, 8, 1, 8, 8** | by hand, the averaging A/B | **no, and it is the dangerous one**: the value left in force is "whatever arm was running when the script stopped". Interrupted at `:56` (arm `off`) or `:58` (arm `off2`) it leaves **1**, and the echo keeps it. No `finally`, no read-back assertion before `exit 0` |
| T3 | `ps_fft_dual/st2_accept_20261024.tcl:36`, guard `:35` | `mwr -force [expr {$MB + 408*4}] $avgn` | only if a 3rd argv is given (`set avgn -1`, `:17-20`) | no |
| T4 | `ps_fft_dual/st6_dump_20261024.tcl:42`, guard `:41` | `mwr -force [expr {$MB + 408*4}] $avgn` | only with a 3rd argv (`:23-26`) | no |
| T5 | `ps_fft_dual/st6_warm_20261024.tcl:60`, guard `:59` | `mwr -force [expr {$MB + 408*4}] $avgn` | only with a 3rd argv (`:20-23`) | no |
| T6 | `ps_fft_dual/st8_accept_20261024.tcl:56`, guard `:55` | `mwr -force [expr {0x10F00000 + 408*4}] $avgn` | only with a 3rd argv (`:15-18`) | no |
| T7 | `ps_fft_dual/stA_accept_20261024.tcl:64`, guard `:63` | `mwr -force [expr {$MB + 408*4}] $avgn` | only with a 4th argv (`:21-25`) | no |
| T8 | `ps_fft_dual/st8_restore.tcl:9` | `mwr -force [expr {$MB + 408*4}] 8` | by hand, at the end of a stage | no — it *is* the restore (8) |
| T9 | `ps_fft_dual/stA_reaim_defect_20261024.tcl:76` | `mwr -force [expr {$MB + 408*4}] 8` | by hand, before a re-aim run | no — sets 8 on purpose |

Read-only users of the same word (**not** writers): `a1_read_20261026.tcl:93,120` (plus the
`404..412` neighbourhood dump that proves the *index*, not just the value),
`a1_read2_20261026.tcl:46`, `a2_verify_20261026.tcl:41`, `a2_trace_20261026.tcl:34,71`,
`b1_post_20261026.tcl:36`, `xcheck_state_20261026.tcl:52`, `xcheck_dump_20261026.tcl:167`,
`_a_probe.tcl:10`, `st8_probe.tcl:35`, `st7_state_20261024.tcl:43`, `dl/host_qc/check_words.py:69`
and `dl/host_qc/qc_mailbox.py:108` (names only), `.tmp/read_now.tcl:24`, `.tmp/dump_fail.tcl:42`.

**Only T2 can leave the board at 1 as a side effect of an ordinary run; T3–T7 can if someone passes
`1` on the command line; F1/F2 and T1/T8/T9 all put 8 there.** No script saves the previous value and
restores it, and no script verifies `MB_AVG_CNT`/`MB_AVG_TICKS` moved before it exits.

## 1.3 What tonight's data actually says  (E2, from raw dumps)

The mailbox was dumped as **512 raw words** four times inside the cross-check window
(`dl/xcheck_20261026/goodA{,2}/mb_{before,after}.bin`, 2,048 B each). Decoding word 408 in all four:

| dump (file mtime) | word 408 | 409 | 410 skip | 411 ticks | `MB_PS_FRAMES` |
|---|---|---|---|---|---|
| `goodA/mb_before.bin` 19:51:34 | **1** | 1 | 15 | 9,388,082 | 11,762 |
| `goodA/mb_after.bin` 19:51:48 | **1** | 1 | 15 | 9,388,082 | 11,767 |
| `goodA2/mb_before.bin` 19:53:10 | **1** | 1 | 15 | 9,388,082 | 12,586 |
| `goodA2/mb_after.bin` 19:53:24 | **1** | 1 | 15 | 9,388,082 | 12,589 |

`capture.json` agrees (`MB_AVG_N 1`, `MB_AVG_CNT 1`, `MB_AVG_TICKS 9388082`). So the 1 was in force
for at least the 110 s spanned by these four dumps, with the sampler frozen — exactly the latch of F2.

**One boot, not several.** `MB_PS_FRAMES` 145 (19:30:10, `dl/host_qc/evidence/20261026_192955`) →
6,753 (19:43:32, `…_194318`) → 11,762 (19:51:34) → 12,586 (19:53:10) is monotone and consistent with
96–121 ms per loop; the board had booted at ~19:29:5x. So the 1 at 19:51 and 19:53 is a value written
**after** that boot, during a session in which the firmware had already run the sampler at least once
(§1.4).

**No tracked tool ran in that window.** Every repo file touched between 19:30 and 20:00 was either
documentation, an analysis script, or one of three read-only captures:

* 19:29:55 and 19:43:18 `dl/host_qc/evidence.py` (the NG-evidence reader); its rows
  (`dl/host_qc/evidence/rows.csv`) show `part_ref` 498 then 662, `darea` 351 then 28;
* 19:50:34 / 19:51:34 / 19:53:10 — the three hw_server launches (`tcf*` logs in the repo root) of the
  cross-check dumps; `ps_fft_dual/xcheck_dump_20261026.tcl` has **no `mwr`** (grep in §1.7) and
  `dl/host_qc/xcheck_capture.py:27` states "NO WRITE PATH";
* `.tmp/inj.tcl` 19:41:52 and `.tmp/inj2.tcl` 19:42:59 write words **505/506** (`0x10F007E4`,
  `0x10F007E8`), not 408.

**And the two scripts that write 1 or 8 did not exist yet**: `a1_fixcmd_20261026.tcl` was created
**20:12:15** and `a1_avgab_20261026.tcl` **20:13:20** (file mtimes), i.e. after the 19:51/19:53
readings, and their own "before" data is the 20:03–20:08 `.tmp/a1` dump set. So the 1 at 19:51
**cannot** be a leftover of either script, and the "restore at 19:43" in the task brief does not
survive the artifacts: the restore that is documented (`NG_GOODBOARD_20261026.md` §5, commit
`1efa33d` at **20:17**) happened **after** the two 1 readings, not before them. The 19:43 timestamp
appears to come from `NG_GOODBOARD` §7.1's "`MB_CMD` = 9 … was sent at 19:43", which the evidence row
at 19:43:32 contradicts (that row is the deliberate-`MB_CMD 15` stamp, `darea` 28, `part_ref` 662 —
not the retake that produced `part_ref` 420).

**It was written at least twice.** `NG_GOODBOARD_20261026.md` §5 records the frozen
`MB_AVG_TICKS` 9,373,111 **before** the restore; the four dumps above carry **9,388,082**. Since
`g_avg_ticks` is only assigned by a sampling pass (`main.c:4067`), the sampler
ran at least once *between* those two readings, i.e. the target was ≥2 somewhere in that gap and came
back to 1. So tonight's 1 is **not one stray write**: there were at least two, separated by at least
one write of 8. (Provenance caveat: I can re-verify 9,388,082 from the dumps; 9,373,111 is taken
from the earlier document and I could not date its read — the EVID meta block dumped at 20:03:59 is
still the 19:43 snapshot, `.tmp/a1/evid_meta.bin`, `frames` 6753, so it carries no word state.)

**Conclusion for the culprit (E2 negative, stated plainly):** no tool in this repository wrote the 1
it is asked about. The mechanism is an **out-of-repo `mwr` of word 408** (an interactive xsdb line or
another session's command), made permanent by the firmware's echo. I cannot name it, and I am not
going to guess a tool name.

## 1.4 Why it was not caught  (E1, each with its line)

1. **The firmware treats it as host property.** `main.c:13859-13862`; the firmware's own default is
   only asserted at boot (`:13163`), so a write at any later time wins for ever.
2. **The one host gate never looks at it.** `dl/host_qc/preflight.py:46-57` (`QUOTE_WORDS`) lists
   `ready`, `diff_ok`, `diff_n`, `st_*` … and **no `avg_n`/`avg_cnt`**; `evaluate()` (`:75-131`)
   decides PASS/FAIL/INCOMPLETE from `st_verdict`/`st_code`/`st_res` only. A preflight PASS is
   compatible with N=1.
3. **The count word is ambiguous by construction** (`main.c:8283`: `(navg != 0) ? navg : 1`), so
   `MB_AVG_CNT` 1 means both "off" and "one frame".
4. **The stale timing word looks healthy** (28.0 ms, `main.c:4028` + the every-loop publish at
   `:13866`), so the only word that would betray "the sampler is not running" reads as if it were.
5. **The measurement records cannot tell the two arms apart.** `dl/host_qc/qc_log.py:52-69` and the
   `dl/host_qc/logs/conveyor_*_cycles.csv` schema carry `ready`, `diff_*`, `limit` … but **no
   `avg_n`/`avg_cnt`**, so a QC session run at N=1 and one run at N=8 produce identical logs. This
   is the same failure class as the frozen-input words added in item 3 on 2026-10-26.
6. **The A/B script's last arm is an unverified assumption** (`a1_avgab:56-60`): nothing asserts the
   read-back is 8 before exit, and xsdb has no reliable `finally` (a killed `xsdb.exe` runs no
   `atexit`), so "the tool restores it" is exactly the mechanism an earlier session already learned
   not to trust (`NG_GOODBOARD` §5, `PERF` §4).

## 1.5 The fix, from the cheapest end  (E0 recommendation, with the reason)

**(a) A tool that sets 8 and restores it in `finally`/`atexit`.** Rejected as the *fix*, though worth
having: it cannot cover an out-of-repo `mwr` (which is what tonight was), it does not survive a
killed xsdb, and it still leaves the board at 1 for every other consumer of the mailbox while the
script runs. It also does not make a *judged* comparison observable.

**(b) A preflight/gate refusal — my pick.** Make "the averaging arm is not the production arm" a
**named refusal at the only moment it matters**:

* `dl/host_qc/preflight.py`: add `avg_n`, `avg_cnt`, `avg_ticks` to `QUOTE_WORDS`, and a fifth check
  ("AVG") that is PASS only when `avg_n >= 2` **and** `avg_cnt >= 2` (with `avg_ticks` non-zero);
  FAIL-named on `avg_n == 1`, exit code 5, and the line prints all three. ~15 lines, no firmware
  build, and the refusal is quotable in a log.
* the same predicate in `dl/host_qc/qc_conveyor.py:judgeable_reason()` (`:376-390`), so the
  production judgement path refuses rather than records, and
* `avg_n`/`avg_cnt` into the row schema (`qc_log.py:52-69`, `record.py:451-484`), so the two arms are
  distinguishable in the archives afterwards.
* `ps_fft_dual/a1_avgab_20261026.tcl`: write 8 and **assert the read-back is 8** as its last
  statement (`exit` non-zero otherwise), so an interrupted A/B is visible in the console.

Why this and not the other two: it is the only option that catches the state **at judgement time**,
it needs no build, it cannot be defeated by the echo latch, and it costs nothing on the board.

**(c) A firmware that re-seeds 8.** The version the brief names — "re-seed when it sees nothing has
changed it" — is **not implementable as stated**: the firmware cannot distinguish a host write from
its own echo (`:13862` writes the same word every loop), so "nothing has changed it" is unobservable,
and a rule that re-seeds whenever the word is not 8 would make the host unable to select 1 at all —
which destroys the one experiment the averaging argument rests on (`STAGE2_20261024_average.md`,
`NG_GOODBOARD` §5 A/B needs to write 1). A weaker, implementable variant is worth the line **if a
firmware build happens anyway**: re-seed 8 in `ref_take()` (the same event that defines a baseline),
so a stray 1 cannot survive into a session that starts with a fresh reference. It still cannot fire
mid-session, which is why it is not the fix.
**And it must not be "write 8 from the host and hope":** the earlier session's lesson
(`NG_GOODBOARD` §5, `PERF` §4) is that host-written words cannot be trusted to be restored — the
firmware's own record of that is the `TOL_SCALE` comment at HEAD `main.c:4055-4064` ("A host word that
changes the JUDGEMENT has to start from a value the firmware put there").

## 1.6 Acceptance test for the fix

On the bench, with the board at N=8: (1) `preflight.py` PASS, line contains `avg=8/8`;
(2) `mwr` word 408 = 1 by hand; (3) `preflight.py` must now exit **5** and name `AVG` — the value it
refused on is in the line; (4) `qc_conveyor.py` must hold with kind `avg_n` (or whatever the reason
string is named) instead of recording a row; (5) write 8 back and re-run: PASS, row carries `avg_n`
8. Steps (3)–(4) are the acceptance: a refusal that names the word, not a value that happens to be
right.

## 1.7 What I searched (so the negative is checkable)

```
git grep -n -E '\b408\b'                                    # every file
git grep -n -E 'MB_AVG_N|avg_n|AVG_N'                       # every file
grep -n 'mwr' ps_fft_dual/*.tcl dl/**/*.tcl .tmp/*.tcl       # every writable Tcl
grep -n -E '0x10[fF]00000|1632|0x660|mwr|MW |build_write_script' dl/host_qc/
```
Results as in §1.2. Notes: (i) `backups/**/ps_ui/main.c` and `handoff_*/`, `submission/**` contain
older copies of the same two firmware sites — no additional writer; (ii) the `mwr` hits in
`dl/host_qc/*.py` are `cv2.imwrite` and comments, the only mailbox write path is
`qc_mailbox.py:557-602` (`MW` by **name**, `pairs_from` rejects unknown names), and no caller passes
`avg_n`; (iii) `.tmp/*.tcl` only read 408 (`read_now.tcl:24`, `dump_fail.tcl:42`); (iv) the word
index is proven, not assumed: `a1_read_20261026.tcl:118-123` dumps the raw neighbourhood 404..412 and
the values in `mb_before.bin` are the named words (`408` sits between `MB_CAP_DBG7` 407 and
`MB_AVG_CNT` 409, and the map `dl/mb_map_20261026.tcl` was regenerated from the firmware's `#define`s
— 384 names; the only change to that map today is the *addition* of 532–543, so 408 did not move).

---

# Investigation 2 — does the comparison read a store the ring rewrites?

## 2.0 The one-paragraph answer

**Yes, and it is not a rare race: at the measured 167.24 ms the comparison outlives its store by at
least ~26 ms on every comparison.** The comparison reads the selected store **directly** — there is no
copy, all frame-reading passes dereference `cam0_stores[rd_idx]` — and the store is rewritten by the
ring **70.7–81.6 ms after it is selected**, i.e. at **42–49 %** of the comparison. The firmware's
selection code measures that window itself (`81.6 ms`, "three stores later").

**The comparison runs on a moving scene; the verdict does not.** Admission is
`g_ref_ok != 0 && frames % 16 == 0` with no look at the readiness gate (`main.c:14037`), so the
comparison, its cells and its `DAREA` are computed and published whatever the scene is doing. But
`diff_verdict()` returns **2 (CANNOT JUDGE) before it looks at anything else when `MB_READY != 1`**
(`main.c:10862`, "P1 (stage 1): NO VERDICT WHILE THE PICTURE IS STILL MOVING"), and `MB_READY` needs
**6 consecutive still loops** measured as **≤24 of 2,176 cells** changing by more than 10 counts.
So a published PASS/NG requires ~0.6–1.6 s of prior stillness, and the production host adds
`MB_READY == 1 && MB_DIFF_OK == 1` on top (`qc_conveyor.py:384-389`). **The splice is benign in the
accepted case** because a verdict requires that stillness and two consecutive still frames are nearly
identical. What is *not* covered: the gate's evidence ends where the 167 ms read begins, and "still"
is a count of cells rather than a displacement — the two holes are named in §2.4.4. On disk there is
**no** evidence of a splice hurting a verdict — and on a still scene there could not be (the firmware
says so itself, `main.c:880-884`). §2.6 gives the measurement that would close it.

## 2.1 Which buffer, and how long each pass reads it  (E1 + read counts from code)

**The buffer.** The comparison's source is `cam0_stores[rd_idx]` with `rd_idx = cap_read_index()`,
selected at the top of the comparison branch (HEAD `:14049-14051`):

```c
main.c:14047      uint32_t t0 = R32(GTIMER);
main.c:14049      cap_ho_sample();
main.c:14050      rd_idx = cap_read_index();
main.c:14051      dcache_invalidate((const void *)cam0_stores[rd_idx], CAM_BYTES);
main.c:14063      if (diff_frame((const volatile uint8_t *)cam0_stores[rd_idx]) != 0u) {
main.c:14064          R32(MAILBOX + MB_DIFF_MS * 4u) = R32(GTIMER) - t0;
main.c:14065          R32(MAILBOX + MB_DIFF_OK * 4u) = 1u;
```
with `cam0_stores[4] = {0x10000000, 0x10400000, 0x10C00000, 0x12000000}` (`main.c:405`) and
`CAM_BYTES = 1280*720*3 = 2,764,800` (`main.c:298`). At 19:51 `MB_CAP_RDIDX` was **2 → 0x10C00000**;
at 19:53 **0 → 0x10000000** (E2, `capture.json`). Note there are **two** selections per loop: the
class phase re-selects for the render at `:13472` (`g_long_buf`, `:13474`) and the comparison selects
again at `:14050`, so the tear detector at `:13801` guards the *render's* store, not this one.

**There is no copy anywhere.** `evid_copy()` (`main.c:4968`) is the only function that copies a store;
it runs at the top of the *next* loop on an NG and is not in this path. Every pass below dereferences
`src`:

| pass (execution order, HEAD) | call site | frame reads | reads the store? |
|---|---|---|---|
| `avg_take()` | `:8278` | 0 | no (reads `AVG_*_SUM`) |
| PASS 1 `cell_mean4`, 3,600 cells | `:8291` | `3,600 × (2×2 samples × 5×5 box) = 360,000` | **yes, direct** |
| PASS 1a background presence grid, 14,400 cells | `:8310` | `14,400 × 4 = 57,600` | **yes, direct** |
| gain test (`→ MB_DIFF_OK 4` if scale outside 128..512) | `:8328` | 0 | no |
| `latt_fill(src)` (N=1 only) | `:8353` | `14,400 × 4 = 57,600` | **yes, direct** |
| `part_masks(src, LATT_BASE, LIVE_MASK)` — green score | `:8362` | `14,400 × 12 = 172,800` (measured 20.3–26.0 ms for the whole call) | **yes, direct** |
| in-view gate (`→ MB_DIFF_OK 6`) | `:8395-8412` | 0 | no |
| `gm_latt_fill(src)` | `:8418` | `14,400 × 4 × 4 = 230,400` | **yes, direct** (the doc comment at `:3307-3314` says "36 reads = 518k"; the code is 4 × `gm_grey_at` × 4 bytes = **16**, so 230,400 — the comment is stale) |
| `reg_search()` | `:8433` | 0 frame (scores `LIVE_GM`/`BASE_GM`) | no — but it consumes `gm_latt_fill`'s output |
| PASS 2 `ref_cell` per cell | `:8549-8590` | 0 store (REF_BASE only) | no — the live side comes from `g_dflag`, filled by PASS 1 |
| fine pass `cell_mean8` | `:8652` | `36 × 477 judged = 17,172` | **yes, direct** |
| `contour_run()` | `:8908` | 0 | no |
| `diff_refine()` (only when cells > 0; refused in both snapshots) | `:8910` | 2/px over the box | **yes, direct** |
| **store reads, one N=1 comparison** | | **895,572** | |

At N≥2 the averaged sums (`AVG_LATT_SUM`, `AVG_CELL_SUM`) replace PASS 1, `latt_fill` and the fine
`cell_mean8` — 435k of those reads leave the comparison, which is why the N=1 arm is the one that
matters here (PERF §2.3).

## 2.2 The store's safe window, from the selection code's own numbers  (E1/E2)

`cap_read_index()`'s header is the measurement (HEAD `:701-733`):

* **one store is written every 27.2 ms** (`:705`), four stores = 109 ms;
* the fallback path (which is the active one: **`MB_CAP_DEC` = 0** in both snapshots, i.e. the 2-bit
  decode is unavailable on this bitstream) returns the store the last edge **completed** (`:858`) after
  waiting until the last handover is at most `interval/8` old (`:852-857`);
* `interval = g_cap_period`; `MB_CAP_PERIOD` reads **87,225 µs = 87.2 ms** at 19:51 (E2), against the
  true 54.4 ms edge interval — so `lim = 87.2/8 = 10.9 ms`;
* the selected store is rewritten "three stores later" = **81.6 ms** after that edge (`:705-721`).

Therefore, measured from the moment of selection:

> the selected store is **0–10.9 ms** old and is rewritten **70.7–81.6 ms later**.

The comment's own sanity check is that the *render* (~50–65 ms, `:790`) fits inside that window — and
it does, which is why `MB_TEAR_ROW`/`MB_TEAR_ROWN` reads 4/11,763 and 5/12,586 (E2, the two snapshots).
**The comparison is 167 ms, and nothing in this path is 81.6 ms long.**

## 2.3 The splice arithmetic  (E2 totals, E1 window, E0 the rate)

```
MB_DIFF_MS            55,992,504 ticks / 334,800 = 167.24 ms      (goodA, 19:51)
                      55,946,155 ticks          = 167.10 ms      (goodA2, 19:53)
store period          27.2 ms                                    (cap_read_index header, measured)
stores written during one comparison   167.24 / 27.2 = 6.15
rewrites of THE SELECTED store inside one comparison             1
   (the next one is 4 x 27.2 = 108.8 ms after the first, i.e. at 179.5-190.4 ms > 167.24)
fraction of the comparison at which it is rewritten   70.7-81.6 / 167.24 = 42-49 %
```

**Why the read span must exceed the window (E2 + E1 bound).** `MB_DIFF_MS` is timed from just before
`cap_ho_sample()`/`cap_read_index()` (`t0` at `:14047`) to the end of `diff_frame` (`:14064`), so

```
167.24 ms  =  wait W  +  invalidate (2.76 MB, 86,400 line ops, 2.6-5 ms)  +  read span P
```
`W` is bounded by the selection code: the loop exits as soon as the age of the last handover is
≤ 10.9 ms, so it waits **at most one handover interval ≈ 54.4 ms** (`:851-857`; the 261 ms bound only
applies if the capture has stalled, and then `MB_DIFF_MS` would be ≥261 ms, not 167).
Hence
```
W <= 54.4 ms  =>  P >= 167.24 - 5 - 54.4 = 107.8 ms  >  81.6 ms
```
**so at least 26 ms of the comparison reads a store that has already been rewritten** (the read-count
model below puts the overrun at 21–42 ms; the two agree inside their brackets).

**The rate this implies (E0, and it refutes one of the two calibrations on disk).** The passes measured
inside the comparison are `part_masks` 20.3–26.0 ms + `reg_search` 16.69 ms + `contour_run` 1.85 ms =
**38.8–44.5 ms** (PERF §2.1, from `dl/PART_MASK_PERFRAME_20261026.md` §3 and `MB_REG_TICKS` 5,588,706).
The remaining **722,772** store reads must therefore take `P − (38.8..44.5) >= 63.3..69.0 ms`, i.e.
**at least 88–95 ns per frame read**. That agrees with the `part_track` calibration (57,600 strided
reads in 4.83 ms = 83.9 ns/read, `.tmp/ab_segA.csv`, n=158) and **excludes the 30 ns/read rate
implied by `avg_sample`'s 936k sequential reads in 28.0 ms** for *these* passes: at 30 ns the passes
would finish in ~21.7 ms and leave a 100 ms wait, which the selection code cannot produce.

**Where the seam lands (E0, from the read counts and the 88–95 ns rate).**

| cumulative pass | frame reads | cumulative ms | reads frame |
|---|---|---|---|
| selection + invalidate | — | 0 (t0 = selection start) | — |
| PASS 1 `cell_mean4` | 360,000 | 0 → 31.7–34.2 | **N** |
| PASS 1a bg grid | 57,600 | → 36.8–39.7 | **N** |
| `latt_fill` | 57,600 | → 41.9–45.2 | **N** |
| `part_masks` (measured 20.3–26.0) | 172,800 | → 62.2–71.2 | **N** |
| `gm_latt_fill` | 230,400 | → 82.5–93.1 | **splice is inside this pass** (70.7–81.6) |
| `reg_search` (measured 16.69) | 0 | → 99.2–109.8 | N+1 (its input is N+1) |
| PASS 2 (`REF_BASE` only) | 0 | — | — |
| fine pass | 17,172 | → 100.7–111.4 | **N+1** |
| `contour_run` (measured 1.85) | 0 | → 102.5–113.2 | — |

So the *most likely* reading is that **PASS 1, the background grid, `latt_fill` and `part_masks` see
frame N, while `gm_latt_fill`, the registration, PASS 2 and the fine pass — the fine pass is what
produces `DAREA` — see frame N+1.** That is worse than a splice in "one late pass": the registration's
structure image and the fine pass are fitted to a *different frame* than the coarse live cell means
and the part mask. On a still scene the two frames are nearly identical and this is invisible; on a
moving scene it is a coherent 1-row-band error at the seam.
**Caveat, E0:** the cumulative column is a model pinned only at the three measured passes; the 88–95 ns
rate is *inferred* from the total, not measured per pass. The only way to pin it is §2.6.

## 2.4 The decisive question: can a verdict be published while the scene is changing?

### 2.4.1 The gate itself  (E1)

`settle_gate()` (HEAD `main.c:9025`) runs **every loop** (`:14018`) on `g_long_buf`, the store the
*render* just read, and compares its 8×8 lattice grid with the previous loop's:

* grid `READY_GW × READY_GH = 64 × 36` cells, cell 20×20 source px, sampled as a 4×4 lattice at
  +2/+7/+12/+17 (`main.c:2652-2669`); the decision uses rows 2..35, i.e. **34 × 64 = 2,176 cells**
  (`READY_Y0 = 2`);
* a cell "moved" when `|d| > READY_CELL_DIFF = 10` counts **after subtracting both the frame's mean
  change and that row's own mean** (so a rolling-shutter bar does not count, a moving part does);
* the frame is "still" when **`changed <= READY_MAX_CELLS = 24` cells** (1.1 % of 2,176);
* **`ready = 1` requires `READY_K = 6` consecutive such loops AND `g_aec_state == 1`**
  (`main.c:9153-9158`), and the grid is swapped at the end of every loop (`:9194-9198`) so each loop
  compares against the previous one;
* it publishes `MB_READY` (224), `MB_READY_STILL`, `MB_SETTLE_MOTION` (199), `MB_SETTLE_MOTG`,
  `MB_GATE_AECOK`, `MB_GATE_READY`, `MB_GATE_LOOPS`, per-row `MB_SETTLE_ROWM/ROWC`,
  `MB_SETTLE_HIST`, `MB_SETTLE_ABSSUM/SQSUM`.

### 2.4.2 The comparison is admitted without the gate; the *verdict* is not  (E1 — this is the finding)

```c
main.c:14037      } else if (g_ref_ok != 0u && (frames % DIFF_EVERY) == 0u) {
main.c:14038          if (g_aec_state == 3u || g_clip_gate != 0u) {
main.c:14039              R32(MAILBOX + MB_DIFF_OK * 4u) = 3u;      /* refused */
main.c:14044          } else {  ... cap_read_index ... diff_frame ... }
main.c:14080          R32(MAILBOX + MB_DIFF_VERDICT * 4u) = diff_verdict(0, 0);
```

The **admission** condition is `g_ref_ok != 0` and one loop in 16 — `MB_READY` is *not* in it. The gate
is used twice elsewhere:

* `avg_sample()` refuses to accumulate a frame when `MB_READY != 1` (`main.c:4031`);
* **`diff_verdict()` refuses to answer PASS/NG when `MB_READY != 1`** (`main.c:10862`), and it is
  called on every comparison loop at `:14080` (and again at `:13910`, before the comparison, to feed
  `MB_LOCAL_VERDICT` at `:13933`).

So the honest statement is a two-parter: **the comparison and its cell counts run and are published
while the scene moves** (`MB_DIFF_OK` = 1, `MB_DIFF_CELLS`, `MB_DIFF_DAREA` all fresh), **but the
verdict word cannot be 0 or 1 unless `MB_READY == 1` at the instant of publication**, and `MB_READY`
requires `READY_K = 6` consecutive still loops plus `g_aec_state == 1` (`main.c:9153-9158`). The other
refusals are: AEC stuck/clipping (`MB_DIFF_OK 3`, `:14039`), gain outside 0.5–2.0 (`MB_DIFF_OK 4`,
`:8328`), "no registration" (`MB_DIFF_OK 5`, `:8524`/`:8901`), "part not fully in view"
(`MB_DIFF_OK 6`, `:8410`). **None of them measures motion during the read**; they decide whether the
frame may be compared, not whether the read was coherent.

### 2.4.3 The two gates, and what their evidence actually covers  (E1)

| layer | where | requires | what it measured, and when |
|---|---|---|---|
| firmware `MB_READY` | `main.c:9025` (gate), `:13848` (call: class phase, **before** the comparison), `:10862` (verdict) | 6 consecutive loops with ≤24 of 2,176 cells changed by >10 counts, after removing the frame bias and each row's own mean; and AEC state 1 | the *render's* store vs the previous loop's grid — i.e. the ~1 loop (~99–167 ms) **before** the comparison's read, on a **different store selection** (`g_long_buf` at `:13474`, not `cam0_stores[rd_idx]` at `:14050`) |
| host | `qc_conveyor.py:376-390`, `:1269`, `:1325-1337` | `MB_READY == 1` **and** `MB_DIFF_OK == 1` **and** a comparison newer than the one seen at the belt stop | the same words, read once after the stop; the stale pre-stop PASS is explicitly discarded (`:1275-1285`) |
| host (informational only) | `preflight.py:46-57`, `:75-131` | nothing about stillness | quotes `ready` in the line; **does not gate on it** |

### 2.4.4 So can it splice while a verdict is published?  (the answer)

**Yes in principle, and here is exactly where — two named holes, neither measured:**

1. **The gate's evidence ends where the read begins.** The comparison is admitted on the loop whose
   gate reading was taken at `:13848`, i.e. from the frame *pair before* the read. The 167 ms read
   that follows is **1.7 loops of unchecked time**. A scene that starts moving inside that window —
   the conveyor starting, a hand entering, the part being nudged — produces a spliced comparison whose
   verdict is published with `MB_READY` still 1 (the word is only recomputed on the next loop).
2. **"Still" is a count of cells, not a displacement.** 24 of 2,176 cells at |d| > 10 counts after two
   mean subtractions is a threshold on how many 20×20-px cells changed, so a slow uniform drift whose
   moving edges are few enough stays "still" for ever. The gate's own comment says the row-mean
   subtraction is what leaves "the within-row structure that a moving part produces" — i.e. the gate
   is tuned for a *part*, not for a slow creep of the whole frame.

**But the accepted case is benign**, and that is the operational answer: a verdict of 0 or 1 is only
published after 6 consecutive still loops, and on a still scene two frames are nearly identical, so a
splice across them changes nothing (the firmware's tear detector's own header, `main.c:880-884`, says a
static scene cannot show a tear either). The question "does a verdict come with a splice" is therefore
*not* answered by "does the comparison splice" (it does) but by "can the gate be open while the scene
moves" — and that is the two holes above.

## 2.5 Evidence on disk  (E2, and what is missing)

**a. Judged comparisons and their motion metric.** All live judgements in the conveyor logs
(`dl/host_qc/logs/conveyor_*_cycles.csv`, `mode=live, synthetic=0`) — 6 rows — have **`ready = 1`**:

| time | verdict | darea | ready | diff_ok | diff_n before → after |
|---|---|---|---|---|---|
| 10-25 20:10:19 | PASS | 7 | 1 | 1 | 8907 → 8908 |
| 10-25 20:10:58 | CANNOT_JUDGE | – | 1 | 5 | 8909 → 8909 |
| 10-25 20:29:56 | PASS | 3 | 1 | 1 | (creep run `live_creep_closed`) |
| 10-25 20:33:58 | **NG** | 34 | 1 | 1 | 8933 → 8934 |
| 10-25 20:35:35 | **NG** | 36 | 1 | 1 | 8990 → 8991 |
| 10-25 21:45:54 | CANNOT_JUDGE | – | 1 | 5 | 201 → 201 |

**But no CSV in the repo records the motion magnitude** (`grep -l 'settle_motion|motion' *.csv` →
nothing), so "a judged comparison whose motion metric was non-zero" is **not answerable from disk**:
only the boolean was ever logged. That is a logging defect, not a measurement (§2.6, item 2). The 27
simulated rows (`synthetic=1`) are the tool's self-test and say nothing about the board.

**b. The two full snapshots are a *still* scene, and say so.** `MB_SETTLE_MOTION` **0**,
`MB_SETTLE_MOTG` **0**, `MB_REG_MOVE` **0** ("last accepted transform's move, 1/100 of the bound"),
`MB_READY` **1**, `MB_READY_STILL` **374 / 643**, `MB_GATE_READY/MB_GATE_LOOPS` = 92.9 % / 93.0 %
(E2, both `capture.json`). The scene really was still for ≥ 374 consecutive loops.

**c. `MB_DIFF_MS` vs `MB_DIFF_SIGMA`.** Only two comparisons on disk have both, and both are from the
same NG frame: 167.24 ms / sigma16 224 and 167.10 ms / sigma16 259 (14.0 / 16.2 grey). The averaging
A/B arms (sigma16 34.6–42.4) did **not** record `MB_DIFF_MS` (`a1_avgab`'s print list, `:38-40`), and
no PASS-frame `MB_DIFF_MS` exists (PERF §6.2). **The correlation cannot be computed**; N=2 is not a
correlation.

**d. Tear rows during judgements.** Only the two snapshots carry tear words: `MB_TEAR_ROW`/`MB_TEAR_ROWN`
= **4 / 11,763** and **5 / 12,586** (0.04 %), `MB_TEAR_BIG` 0, `MB_TEAR_SEL` 0, `MB_TEAR_WIN` 4/5,
`MB_TEAR_NOFLIP` 0. That is the *render* window (50–65 ms), which fits inside the store's life — it
says the render is safe, **not** that the comparison is. The detector's store (`g_long_buf`,
`main.c:13474`) and the comparison's store (`cam0_stores[rd_idx]`, `main.c:14050`) are **two different
selections** in the same loop, so even in time the tear detector does not cover the comparison.

**e. A new measurement: no seam in the two judged comparisons whose data is on disk.** I wrote
`dl/splice_check_20261026.py` (offline, no board) and ran it on the two NG-evidence snapshots. Its
group count is a **known-answer check against the firmware's own word**: it reproduces `DAREA` 351 and
28 **exactly**, on both grids, so the tool reads the right bytes.

```
=== dl/host_qc/evidence/20261026_194318   (the deliberate MB_CMD 15 stamp, 19:43:32)
    cells over 30 inside the mask: 28      largest 8-connected group: 28 cells, bbox (53,73)-(58,78)
    firmware's own DAREA: 28               top rows by over-count: (73,6,span 6) (75,5,5) (74,5,5)
    store row-mean step: max 21.95 grey at row 364, median 0.347, largest other step +-20 rows 17.04 (ratio 1.29)
=== dl/host_qc/evidence/20261026_192955   (the mechanical test, 19:30:10)
    cells over 30 inside the mask: 490     largest group: 351 cells, bbox (104,52)-(125,82)
    firmware's own DAREA: 351              top rows: (74,26,62) (73,26,61) (78,25,64) -- a 2-D block, not a band
    store row-mean step: max 18.84 grey at row 364, median 0.341, neighbours 16.38 (ratio 1.15)
```

A splice is a **one-row full-width** signature in the difference map, or **one isolated row-mean step**
in the store. Neither is present: the 19:43 top rows are compact (span 4–6 cells), the 19:30 group is a
**6-row-deep 2-D block** (22×31 cells) rather than a one-row band, and the largest row-mean step
in *both* stores is at **row 364**, which is the belt edge the background analysis already located
(`NG_GOODBOARD` §2.2: strongest row change at bg rows 179→180 = source rows 358–361), not an isolated
seam (ratio to its own neighbourhood 1.15/1.29).
**This negative is bounded by the scene**: on a still scene two frames differ by noise, so a splice is
invisible to this test — the firmware says exactly that of its own detector (`main.c:880-884`). It
exonerates these two comparisons *on this scene*, and it is the test to re-run on a moving scene.

## 2.6 The one measurement that settles it

**Primary — bracket `diff_frame` with the tear instrument that already exists.** In `diff_frame()`,
`tear_sig_capture(src)` on entry and `tear_sig_compare(src)` on exit (and optionally around PASS 1 and
the fine pass to name the pass), publishing two counters: comparisons whose source store changed
during the comparison, and sampled rows changed. Cost: 8 row sums × 16 bytes, twice — the existing
detector is already `main.c:918`/`:926` and already reads a store; nothing new is needed but two calls
and two words. It answers "does the comparison splice" **for every comparison, with the same 30/100-count
limits the render's detector uses**, instead of inferring it from a timing model. Run it **together
with** the gate words: the interesting number is not "how often did the comparison splice" (always, per
§2.3) but **"how often did a comparison with `MB_READY == 1` splice on a scene that was moving"** —
which needs the tear counts and `MB_SETTLE_MOTION`/`MB_SETTLE_MOTG` recorded per comparison, and a
scene with a *controlled* slow drift (the conveyor's creep mode) rather than a still belt, because on a
still scene the detector under-reports by construction (`main.c:880-884`).
(Free indices: the proposal's P1a claims 534/535 as `MB_T_DIFFSEL`/`MB_T_CLSEL` and the camera-1 work
has taken 532–543; check `python dl/mb_words.py` before taking two more.)

**Secondary, no build — the split.** Publish `MB_T_DIFFSEL` (ticks from `t0` to just after
`dcache_invalidate`, `main.c:14051`) so `P = MB_DIFF_MS − MB_T_DIFFSEL` is measured instead of
inferred, and compare it against 70.7–81.6 ms. This is PERF's P1a and it turns §2.3's model into a
number.

**Tertiary, host-only, no build and no new word.** Poll eight row sums of the selected store over JTAG
at ~4 ms intervals across one comparison (the same 8 rows `tear_row_sum()` uses, 128 bytes per poll) and
look for the instant one of them jumps. A jump inside the comparison is the rewrite; the fraction of
`MB_DIFF_MS` at which it happens is the seam position. This works today, on the current bitstream, and
is the cheapest way to confirm or kill §2.3 before any build.

**And fix the logging**: put `MB_SETTLE_MOTION`, `MB_SETTLE_MOTG` and `MB_AVG_N/CNT` into the row
schema (`qc_log.py:52-69`) so a future session can answer §2.5a and §1.4.5 from the archives instead of
from a snapshot of opportunity.

---

# What remains unverified, and what I did not do

1. **Who wrote the 1** (§1.3). Not in the repo; I will not guess. What is established: it was written
   at least twice tonight, no tracked tool ran at those times, and the two scripts that write 1 or 8
   post-date the 19:51 readings.
2. **The provenance of `MB_AVG_TICKS` 9,373,111** (`NG_GOODBOARD` §5) — I could not re-verify the
   moment of that read; the four raw dumps give 9,388,082. If 9,373,111 was read before 19:51, then the
   "sampler ran between the two" inference in §1.3 collapses and only one write of 1 is evidenced. The
   §1.2 writer inventory and the §1.5 fix do not depend on it.
3. **The per-pass split inside `diff_frame`** (§2.3 table) is a model: read counts from code (E1), three
   pass costs measured (E2), the 88–95 ns/read rate *inferred* from the total (E0). The seam position
   "42–49 %" is E2/E1; "inside `gm_latt_fill`" is the model.
4. **Whether a slow drift stays under the gate** (§2.4.1, §2.4.4). The threshold is 24 of 2,176 cells at
   |d| > 10 counts; the mapping from belt speed to changed cells is a measurement nobody has taken
   (the creep runs on 10-25 have `creep_actual_s = 0.000` in the judged rows, so they stopped before
   the creep they were named for). This is the gap the splice would have to hide in.
5. **No PASS-frame `MB_DIFF_MS`** exists on disk, so the 167 ms is a *failing* frame's number; a PASS
   frame may be cheaper (`diff_refine` refused in both snapshots, < 4 ms per PERF §2.3), and every
   number in §2.3 scales with it.
6. **`MB_CAP_AGE` does not describe the comparison's selection** — it read **2** in both snapshots, the
   code `cap_read_index_short()` sets (`main.c:753`), while the comparison's `cap_read_index()` sets 1
   (`:836`). The published age is therefore the class phase's, and the comparison's store age cannot be
   recovered afterwards. One more reason for §2.6's instrument.

Read-only: no file under `ps_ui/` was modified, no board access, no xsdb, no build, no
`dl/host_qc/calibrate.py`, nothing under `dl/build_stm32/`. The only new files are this report,
`dl/splice_check_20261026.py`, and the commit message file.
