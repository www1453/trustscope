# 2026-10-30 — camera 1's part-mask band (ROI): the change, the build, and the station failure that stopped the measurement

> Status: **the change is built and verified offline; the four-board measurement did NOT
> happen.** The station's CPU→PL AXI path failed again during the load, so the run that
> would decide the AND never started. Nothing below may be read as a measurement of the AND.
> The pre-registered criterion in `dl/DUALVIEW_AND_20261030.md` section 6 is untouched.

---

## 1. The defect this change answers, as measured before it

Firmware `TSC1AEA35B84` (the dual-view build), both references freshly taken, one good board
on the station:

| quantity | camera 0 | camera 1 |
|---|---|---|
| `part_pts` | 704 | **3408** |
| `part_ref` | 682 | **3421** |
| `diffok` | 1 (compared) | **6** (part not fully in view) |
| `refq` | 0 (pass) | **1** (fail) |

`and ok=0 why=2` (camera 1 refused), `and_ovl` unreadable, `ox=8 oy=0`.

The cause is not the comparison. Camera 1's field of view is much wider than camera 0's and
about 55 % of its frame is the **room above the belt**. The part mask is "differs from the
empty belt", so every room pixel that changed since the background was taken became "part".
That is the 3408, and it is why the mask reached the frame border and camera 1 refused.

## 2. The band: the rows, and how they were read off the frame

Camera 1's own store was dumped (`cam1_stores[0] = 0x11200000`, saved as
`dl/_cam1_view_20261030.jpg`). The dump is the 1280x720 store scaled to 800x450 — both
dimensions divided by 1.6 — so one dump row is 1.6 source rows and one lattice cell
(8 source px) is 5 dump rows. Measured on the image, not guessed:

| feature | dump rows | source rows (x1.6) | lattice cell rows (÷8) |
|---|---|---|---|
| the bright belt begins | 235 (left edge) .. 247 (middle, where the board is) | 376 .. 395 | 47 .. 49 |
| the board's body | 270 .. 425 | 432 .. 680 | 54 .. 85 |
| the frame | 0 .. 449 | 0 .. 719 | 0 .. 89 |

**The band taken is SOURCE PIXEL ROWS 400..719 = LATTICE CELL ROWS 50..89.** It starts at the
belt's far edge at its lowest measured point (dump 247 = source 395) and runs to the bottom of
the frame. It contains the belt and the whole board with 4 cells (32 source px) above the board
and 4 cells below it, and it contains no room row. A **row** band and not a column one because
the room is above the belt and the belt runs the full width; the board's columns are already
inside the frame.

## 3. What was changed

| site | change |
|---|---|
| `ps_ui/main.c` `MB_CAM1_ROI` (**614**) | the new published word: low 16 bits = first cell row, high 16 = last cell row, inclusive; `0xFFFFFFFF` = no band. Boot default `0x00590032` = rows 50..89 = source rows 400..719. HOST-writable, and the mask reads it every pass. |
| `ps_ui/main.c` `part_masks()` | camera 1's mask is zeroed outside the band **before** each rule's threshold/erosion/cluster (`cam1_roi_zero`), so the erosion's own border rule and the counts describe the banded mask. The guard is `g_view_no != 1` in `cam1_roi_band()`, so **camera 0 is untouched** — the mask the 22 boards were measured against is byte-identical. |
| `ps_ui/main.c` `view_init()` | writes the boot default into the word, so the band in force is readable and a host write is the only thing that can change it. |
| `dl/host_qc/qc_mailbox.py` | `cam1_roi` (614) appended; encoding and the "source row = 8 x cell row" conversion documented beside it. |

**Why the word is host-writable.** Writing `0xFFFFFFFF` builds the mask over the whole frame,
i.e. it reproduces the pre-change 3408 **on the same build**. That turns the band from an
assumption into an A/B that takes thirty seconds: same image, same reference, one word.

**The band's failure mode, stated:** a part placed above the band is outside camera 1's mask,
so camera 1 sees less of it than camera 0 and the AND's count would be low — a false PASS is
the dangerous direction. The band's top edge is the belt's far edge, so a board there is at the
belt's edge and not on the room, and the band is published so a run can check it against the
frame it is judging.

## 4. Build facts

| | dual-view build | **this build** |
|---|---|---|
| build id (words 168..170) | `TSC1AEA35B84` | **`TSC19FCEAB62`** |
| source hash | `AEA35B84`, 13 files | `9FCEAB62`, 13 files |
| ELF | 203,072 B | **203,340 B** |
| `.bin` (what is loaded) | 124,068 B, ends 0x1E4A4 | **124,308 B, ends 0x1E594** |
| `.text` | 123,984 | 124,232 |
| `.data` | 76 | 76 |
| `.bss` (at 0x24000) | 6,672 | **6,672** (unchanged: no new static data) |
| OCM free below the page table (0x20000) | 7,004 B | **6,764 B** |
| `.bss` free below the stack (0x2F000) | 38,384 B | 38,384 B |
| warnings | 4 | **4, the same four** (`dcache_invalidate` implicit + conflicting types, `always_inline`, `wait_probe_edge`) |
| layout check (`check_layout.py`) | pass | pass: 453 words, 0 collisions, 4 literal offsets, 0 also claimed |

**ELF scan** (`python dl/check_mb_words_elf.py --low 614 --high 614`): word 614 is referenced
only from `cam1_roi_zero` (where `cam1_roi_band` inlined), `main_loop` and `view_init`; **no**
raw little-endian address of it anywhere in the image's literal pools or data. `dl/mb_free.py`
after the change: 614 is claimed, free is 615..639 — and 615..639 stay free on purpose.

## 5. The load, and the station failure that ended it

**What was attempted:** a hot load — `stop` → `dow -force ps_ui.elf` → verify 130 sampled words
against `ps_ui.bin` (0 mismatches) → clear the fault block → `PC=0`, `CPSR=0xD3` → `con` — with
no `rst -system`, no `ps7_init`, no fabric reprogram and no `rst -processor`, because the station
was running the PS/PL configuration the last 22 boards were measured on and `startup.S`
invalidates both caches itself.

**What happened, in order.**

1. The first `stop`/`con` pair did **not** take: the build stamp stayed `TSC1BE7E51A4`, the
   counters stopped, and the core was later found halted inside `trap_dabt_c`'s `for (;;)`
   (`PC = 0xfc64`). The `stop`, `rwr pc` and `con` calls in that script were wrapped in `catch`,
   so their failure was swallowed — **this is my defect, and it is the casebook's "silent
   failure" in its most expensive form**: the core resumed on a program counter whose code had
   just been overwritten.
2. A second attempt with every step checked (`stop` → verify `targets` says Suspended →
   `rwr pc 0x0` → **read the PC back through `rrd`, parsed properly** → `con`) **did** start the
   image: the mailbox published the build's stamp and `MB_CAM1_ROI` read **`0x00590032`**, i.e.
   the new build boots and its new word is live. (The image measured was hash `D1DF6A1B`; the
   final build `9FCEAB62` differs from it only in one comment sentence — the `.text`, `.data`
   and `.bss` sizes are identical, 124,232 / 76 / 6,672.)
3. It then faulted on its **first PL register read**: `FAULT = 0x11111104`,
   `DSFR = 0x00000406` (synchronous external abort — an AXI error response, not a translation
   fault), `DFAR = 0`, `FAULTPC = 0x00010320`, `PROGRESS = 1` (`PG_LOOP`). Disassembling the
   build: `0x10320` is the `mov` before `0x10324: ldr r3, [r2, #8]` with `r2 = 0x41200000`,
   i.e. **the read of `CAP_FRPTR = 0x41200008`** — the same instruction, the same address, and
   the same fault code as the 11:42 failure recorded in `dl/DUALVIEW_AND_20261030.md` section 8
   for the **pre-change** build.

**The station's own state, measured read-only after the fault:**

| test | result | what it rules out |
|---|---|---|
| all eight capture stores (4 per camera), 32 sampled words each, 3 s apart | **32/32 changed in every one** | a dead fabric, dead cameras |
| `vdma_0` CR/SR | `0x00010003` / `0x00011810` | a stopped capture channel (identical to the 11:50 bring-up log) |
| `vdma_2` CR/SR | `0x00010003` / `0x00015810` | same |
| `axi_gpio_0` DATA1 (both camera reset lines) | `0x00000003` | sensors held in reset |
| JTAG read of `0x41200008` | answers | a blank or unprogrammed PL |
| the program's own trap | `FAULT 0x11111104`, `DFSR 0x406`, `FAULTPC 0x10320` | a translation fault, a null pointer |

So: the fabric is configured and capturing, the host can still read every PL register, and
**only the CPU's AXI path to the fabric is gone** — the station failure of today, again.

**A measurement of mine that was wrong, recorded because it was wrong.** The first evidence
script reported "camera0 CONTROL = 0/32 words changed, THIS MEASUREMENT IS VOID". It was the
*script* that was void: it passed the first sampled **value** where it meant to pass the
**address**, so it re-read a small unmapped address twice and compared garbage with itself.
Re-measured with the address (all eight stores, 32 words, 3 s): 32/32 everywhere. The tool was
broken, not the capture — the reason the control existed.

**What is NOT established:** whether the CPU→PL path was already dead before the first load
attempt, or died during it. The load's silent `catch` means the first attempt ran the old
program counter into overwritten code, and that window is not instrumented. What IS established
is that the fault is the documented station failure at the documented instruction, that the
station had the identical failure earlier today before this build existed, and that this change
adds no PL access of its own (it is part-mask arithmetic and one mailbox word).

**The station was left halted** (core Suspended inside the trap handler; OCM holds the image
hash `D1DF6A1B`, whose code is the final `9FCEAB62`; no mailbox word claims a measurement this
build did not take). The restore is `ps_fft_dual/bringup_now_20261029.tcl` + the display fix + a
re-flash, and it is the owner's to run.

## 6. The measurement that did not happen, and the criterion it will be judged by

**Unchanged from `dl/DUALVIEW_AND_20261030.md` section 6** (written at 11:40, before the first
flash of the dual-view build):

> The two GOOD boards' `and_darea` must fall BELOW the limit in force (`and_lim`, currently 8)
> while BOTH scratches' `and_darea` stays above it.
> And the failure mode is named in advance: if the scratches' AND also falls, the AND has killed
> the defect together with the specular. That is a negative result and must be reported as one.
> Mapping gate, applied before the criterion is judged at all: a row whose `and_ovl` is low
> (below ~600 per 1000) or whose `and_scale` is far from 256 is a statement about the mapping,
> not about the board, and does not decide anything.

**Added before the boards go on (the owner's instruction):** read `and_ovl` and `and_scale`
after the references and BEFORE any board is placed, and write them down. A low `and_ovl` is a
**stop**, not a caveat.

**Sequence after the restore** — one xsdb client at a time, and the operator's actions are
marked:

1. re-flash `ps_ui.bin` (`ps_fft_dual/roi_load_after_reset_20261030.tcl`), and refuse to go on
   unless the stamp reads `TSC19FCEAB62` and `MB_CAM1_ROI` reads `0x00590032`;
2. pin the exposure at the AEC's own equilibrium (`roi_pin_20261030.tcl`): `MB_EXP_LOCK` (508)
   = the converged `MB_AEC_EXP` (145). The pin is honoured by camera 0's AEC only
   (`MB_EXP_LOCK` has one reader, in `aec_control`); **camera 1 keeps its own auto-exposure and
   is left alone**, because changing it now would confound which change moved `part_pts`;
3. **operator: clear the belt** → `roi_bg_20261030.tcl` sends `MB_CMD = 12` and wants
   `bg_state = 1`, `bg_cells` near 0, `cam1_bgok = 1`;
4. **operator: put a clean good board on** → `roi_ref_20261030.tcl` sends `MB_CMD = 9` and wants
   `part_ref >= 400`, `diffok = 1`, `refq = 0`, `cam1_ref >= 400`, `cam1_refq = 0`,
   `view_state = 1` — **and prints `and_ovl` / `and_scale` before any board is placed**;
5. **the verification gate of this change:** camera 1's `part_pts` must fall from **3408** to
   camera 0's order, `and_why` must reach 0 with `and_ovl` reported. **If it does not, STOP and
   report** — the band is not tuned until the number looks good;
6. then `d30`, `d23`, `g11`, `g14`, one place each, `roi_board_20261030.tcl` per board.

**The A/B that costs thirty seconds:** write `0xFFFFFFFF` to `MB_CAM1_ROI` and camera 1's mask
goes back to the whole frame on the same build. If `part_pts` does not return to ~3408 with the
band off, then whatever moved it is not the band, and the run says so.
