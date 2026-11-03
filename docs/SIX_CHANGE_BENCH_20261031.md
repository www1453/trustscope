# Six source changes, one build, one bench attempt -- 2026-10-31

**Build** `CCE22223` (13 source files, `ps_ui/build_id.h`; ELF 207,192 B, `ps_ui.bin`
127,996 B; `.text` 127,920 + `.data` 76 + `.bss` 6,692).  **Commit** `5f638b3`.
**Station** powered, Zynq-7020, both AN5642s, running this build from 13:00.

**OUTCOME IN ONE LINE: the firmware was built, downloaded, verified and is the image on the
board; the station then lost its PS->PL AXI path (FAULT 0x11111104, the documented failure)
before any comparison could be read, so NONE of the five bench items was measured.  The
"and_ok becomes 1" question is answered by code path (E0), not by a bench number.**

---

## 1. The six changes, and what each is

| # | where | one-line change |
|---|---|---|
| 1 | `dual_and_build()` gate, `ps_ui/main.c` (~line 16600) | the constant `PART_MIN_PTS` (400) for BOTH views becomes `part_min_pts_ref(vN->s_part_ref)` per view, so camera 1's structurally-152..387 mask can clear its own floor |
| 2 | `part_min_pts_view()`, `ps_ui/main.c` (~line 8540) | hard minimum 128 -> `PART_MIN_FLOOR` 64, with the empty-belt argument in the comment; the new `part_min_pts_ref(ref)` takes the reference explicitly so the AND can use both views |
| 3 | camera 1 AEC target | **NOT MADE**: the premise does not reproduce; see section 4 |
| 4 | `bg_take()`, `ps_ui/main.c` (~line 9930) | a pinned exposure with a non-autonomous AEC now refuses with its OWN code (`MB_BG_STATE` 6) and invalidates `MB_BG_CELLS`/`MB_BG_MEDD` to 0xFFFFFFFF, instead of the conflated 2 and a stale count |
| 5 | `reg_diag_finish()`, `diag_publish()`, `MB_NCC_MS` 651 | the NCC pass is timed where it runs and published, so `MB_DIFF_MS - MB_NCC_MS` is the comparison without its registration diagnostics |
| 6 | `MB_CAM1_SEED..CONVSC` 418..421 -> 640..643; `MB_CAM0_REGWHY..NCC` 422..427 -> 644..649; `MB_DIAG_SEQ` 650 | ten one-day-old words renumbered OUT of `MB_DIFF_ROW`'s 45-word band (416..460), which was overwriting them with row means; a publication sequence makes a mixed row detectable |

Source checks, both independent of the board:

* `ps_ui/check_layout.py` (runs on every build): **481 MB_* words, 481 distinct indices,
  0 collisions**.
* `dl/check_mb_words_elf.py --low 417 --high 651`: **no forbidden reference**; 650/651 are
  referenced from `main_loop` (650 also from `view_init`), which is where they are written.
* `dl/mb_word_spans.py` (new, the block-span scan): **before** the change the free runs were
  572..574 and 640..699 and the collision list contained 418..427 inside `MB_DIFF_ROW`;
  **after** the change the free runs are 572..574 and 652..699, the highest defined index is
  651, and there are **0** collisions.

## 2. The baseline, measured before the load (old build `TSC14CA85A0E`)

Three reads two seconds apart; the words quoted were identical in all three unless marked.

| quantity | camera 0 | camera 1 |
|---|---|---|
| `diff_ok` | 1 | 1 |
| part mask (`pts`) | 825, 824, 824 | **161, 200, 214** (the known transient) |
| reference mask | 843 | 152 |
| `darea` | 0 | 0 |
| `fvalid` | 828 | 142 |
| mean | 274 | 274 |
| clip | 0 | 0 |
| exposure / gain | 8662 (PINNED, `MB_EXP_LOCK` 8662) / 16 | 4331 (k=1) / 16 |
| VTS / ceiling | 1200 | 740 / 11776 (this boot, before the VTS change) |

The AND on that state: **`and_ok` 0, `and_why` 4** -- both views had `diffok = 1` and
`fvalid != 0`, so the only refusal was the constant 400 against camera 1's 161..214.  That
is the defect change 1 removes, measured.

The row-mean band advertising itself, same three reads: words **428/429** (inside
`MB_DIFF_ROW`, reported "free" by `dl/mb_free.py`) read **8, 7 / 6, 10 / 6, 7** -- changing
between snapshots, i.e. row means, not diagnostics.  Words 418..427 were in that same band.

## 3. The load, and the abort

`ps_fft_dual/six_load_20261031.tcl` (stop, `rst -processor`, clear the fault block,
`dow -data`, `rwr pc/cpsr`, `con`; the PL/bitstream/VDMA configuration was not touched):

* download verified before running: 127,996 B, **46/46 sampled words** in OCM equal to
  `ps_ui.bin`, PC took 0;
* stamp after boot: `TSC1CCE22223`, `MB_BUILD_ID` 0xCCE22223 -- **the image on the board is
  this build**;
* then: `FAULT=0x11111104  DFSR=0x00000406  DFAR=0x00000000  FAULTPC=0x000111B0  COUNT=1`,
  `frames=104202` frozen, `progress=1`, while `CAP_FRPTR` still toggles (PL capture alive).

`DFSR` bit 10 marks the abort IMPRECISE and `FAULTPC` 0x111B0 disassembles to
`str r4,[sl,#36]` in `main_loop` -- not a faulting instruction.  0x11111104 is this
project's own documented "data abort on a PL read" signature, and on 2026-10-30 the
unmodified build faulted identically on this station (`dl/DUALVIEW_AND_20261030.md`).  The
station needs its bring-up restored; that restoration is the owner's, not this batch's.

## 4. Change 3, deliberately not made

The brief was: camera 1 clips 431 per-mille while camera 0 clips 0, so lower camera 1's AEC
target mean to ~200.  Measured instead: camera 1's clip word (`MB_CAM1_CLIP`, 211) read **0**
with mean 274, exp 4331 (k=1), gain 16 -- in three agreeing reads and again in the bench
snapshots.  The 431 is **camera 0's measure-pass mean** (`MB_CAM0_MEAN`, 212), not camera 1's
clip.  No change was made, for a second reason as well: camera 1 is already 1.57x darker
than camera 0 (274 vs 431 in the same read) and its mask (142..214) is the AND's bottleneck,
so a 200 target would make the view darker and the mask smaller.  The real camera-1 defect is
the control law (it acts only outside 150..780, so a past bright event ratchets it to k=1 and
holds it there) -- a separate finding, not touched here.

## 5. What is unmeasured, and what would settle it

| bench item | state | needs |
|---|---|---|
| empty belt x10: masks 0, `bg_state` 1, `bg_cells` <= 20 | **not measured** | a working station |
| `MB_CMD=12` with the exposure pinned | **not measured** (change 4 is in the image) | the same, plus a pin that puts the AEC in state 3 |
| g0 placed: both `diffok` 1, camera 0 mask in the 800s | **not measured** | board placement |
| d23: `and_ok` / `and_why` / `and_cells` / `and_darea` / `and_ovl` | **not measured** | board placement |
| words 640..651 read back coherent; 422 shows a row mean | **not measured** | a working station |

The code-path answer to "would and_ok become 1", and it is E0, not a measurement: on the
pre-load inputs (cam0 pts 824 >= clamp(843/2,64,400) = 400; cam1 pts 161..214 >=
clamp(152/2,64,400) = 76; both `fvalid != 0`) no gate refuses and `dual_and_build()` has no
later refusal before it writes `and_ok = 1`, so the AND would have been FORMED on that frame.
Whether `and_cells`, `and_darea` and `and_ovl` then describe anything is the question the
bench was for; with camera 1's 142..214-point mask the overlap is the number to watch.

## 6. Replay

```powershell
# source checks, no board
python ps_ui\check_layout.py ps_ui\main.c
python dl\mb_word_spans.py
python dl\host_qc\check_words.py
python dl\check_mb_words_elf.py --low 417 --high 651

# identity + trap record (read-only)
python dl\station_read.py --repeat 3 --interval 2.0
& 'D:\Vitis\Vitis\2023.1\bin\xsdb.bat' ps_fft_dual\six_trap_20261031.tcl

# the bench, once the station is brought up
& 'D:\Vitis\Vitis\2023.1\bin\xsdb.bat' ps_fft_dual\six_load_20261031.tcl     # wants CCE22223
& 'D:\Vitis\Vitis\2023.1\bin\xsdb.bat' ps_fft_dual\bench_snap_20261031.tcl   # one snapshot
```
