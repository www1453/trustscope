# Camera 1 exposure vs optics — read-only probe

**Date** 2026-10-30 ~16:19–16:31 · **Build on board** `TSC19FCEAB62` (ROI) · **Board** good board, station running
**Method** JTAG `mrd` of the firmware mailbox, plus JTAG-driven **reads only** of the two PS I2C
controllers. **No sensor write, no firmware change, no build, no flash, no `rst`.** Scripts:
`ps_fft_dual/cam1exp_20261030.tcl`, `ps_fft_dual/cam1exp_i2c_20261030.tcl`, `ps_fft_dual/cam1exp_awb_20261030.tcl`.

---

## 0. Verdict, in one sentence

> **The exposure hypothesis is dead in the state measured: camera 1's exposure (0x3500/0x3501/0x3502 =
> `00 21 D6` = 8662) and gain (`0x350B` = 16) are *bit-identical* to camera 0's, its AWB channel
> gains differ by at most 7 LSB — inside each camera's own frame-to-frame jitter — and its measured
> green mean is 498 ‰, equal to camera 0's. Nothing on this board is 36 % darker right now.**

The brief's `mean 325 ‰ / mask 3017 / refq FAIL` is **half reproduced**: the mask count and the
reference-quality FAIL are real (3101 points, refq state 1), the **36 % brightness deficit is not**.
Camera 1 sat at 498 ‰ for the whole 30 s monitor, unchanged, with its controller converged.

---

## 1. Bus mapping, and how it was established

| camera | controller | base | route / pins | OV5640 slave address |
|---|---|---|---|---|
| camera 0 (the one that works) | PS **I2C0** | `0xE0004000` | MIO 50/51 → balls **T15/T16** | `0x3C` |
| camera 1 (the one in question) | PS **I2C1** | `0xE0005000` | **EMIO** through the PL → balls **P14/W18** (`cam_iic_1_io`) | `0x3C` |

Four independent lines of evidence, the last two being measurements rather than documents:

1. **The firmware's own definition** — `ps_ui/cam_i2c.c:31-34`:
   `I2C0_BASE 0xE0004000`, `I2C1_BASE 0xE0005000`, with the comment *"I2C0 -> right camera,
   I2C1 -> left"*. The 20-bit exposure code in the same file is the one used to decode below.
2. **The block-design history** — `ps_fft_dual/bd_swap_touch_to_ps_i2c.tcl:15-20` and
   `bd_swap_touch_back.tcl:11-15` both state the arrangement in words: `processing_system7_0/IIC_1 ->
   cam_iic_1_io` (camera 1, P14/W18), `IIC_0_0` (camera 0, MIO T15/T16, untouched by any of the swaps).
   `bd_swap_touch_back.tcl` is the last of those scripts, i.e. the current wiring.
3. **A measurement the two buses could not fake** — the two sensors hold **different VTS**: bus 0
   reports `0x380E/0x380F = 0x04B0` = **1200** lines, bus 1 reports `0x02E4` = **740** lines. The
   firmware computes those two numbers on *separate* code paths and publishes them separately
   (`MB_SEN_SIZE` = VTS 1200 for camera 0, `MB_CAM1_VTS` = 740 for camera 1). Both agree with the
   I2C read. So "bus 0 = camera 0, bus 1 = camera 1" is confirmed by the running system, not only
   by the sources.
4. **Neither read is landing on a stranger** — both buses returned the OV5640 chip ID
   `0x300A/0x300B = 0x56 0x40`.

Nothing was written to either sensor, so the "wrong bus would disturb the working camera" risk never
arose. The only writes in this probe were to the PS controllers' own CR/ISR/DATA/ADDR registers, with
the same control value (`0xE300` base) the firmware itself uses, and `SR.BUS_BUSY` was checked before
every transaction.

---

## 2. Raw register values, both cameras side by side

Two-sample vote per register (project rule, `i2c_lib.tcl`: this link returns wrong values
occasionally), third sample on disagreement. Values in hex; nothing bit-decoded without a source.

| reg | camera 0 | camera 1 | difference |
|---|---|---|---|
| `0x3503` AEC/AGC control | `0x03` | `0x03` | **same** |
| `0x3500` exposure hi | `0x00` | `0x00` | same |
| `0x3501` exposure mid | `0x21` | `0x21` | same |
| `0x3502` exposure lo | `0xD6` | `0xD6` | same |
| `0x350A` gain hi | `0x00` | `0x00` | same |
| `0x350B` gain lo | `0x10` | `0x10` | same |
| `0x3400` AWB blk 0 | `0x05` | `0x05` | same |
| `0x3401` AWB blk 1 | `0x8B` (moves) | `0x8C` (moves) | +1 |
| `0x3402` AWB blk 2 | `0x04` | `0x04` | same |
| `0x3403` AWB blk 3 | `0x00` | `0x00` | same |
| `0x3404` AWB blk 4 | `0x05` | `0x05` | same |
| `0x3405` AWB blk 5 | `0xB9` (moves) | `0xC0` (moves) | +7 |
| `0x3208` group hold | `0xF0` | `0xF0` | same |
| `0x380E` VTS hi *(extra)* | `0x04` | `0x02` | **−2** |
| `0x380F` VTS lo *(extra)* | `0xB0` | `0xE4` | **+52** |
| `0x3406` *(extra)* | `0x00` | `0x00` | same |
| `0x5001` *(extra)* | `0xA3` | `0xA3` | same |

Decoded with the project's own field splits (`cam_i2c.c` `cam_get_exposure`, `cam_set_gain_bus`):

| quantity | camera 0 | camera 1 | ratio |
|---|---|---|---|
| exposure, 20-bit (1/16 line) | **8662** | **8662** | **1.000** |
| exposure, lines | 541.4 | 541.4 | 1.000 |
| gain (0x350A/B, 0x400 max) | **16** | **16** | 1.000 |
| VTS, lines | 1200 | 740 | 0.62 |
| green mean, per-mille | 498 | 498 | 1.000 |

The mailbox agrees with the sensors on every quantity it also reports (`MB_AEC_EXP` 8662,
`MB_CAM1_AEC_EXP` 8662, `MB_GAIN` 16, `MB_CAM1_AEC_GAIN` 16, VTS 1200/740) — that agreement is what
makes the I2C read trustworthy on each bus, since the mailbox is computed by completely different code.

**Are the two means even comparable?** Yes, and this was checked rather than assumed. Both cameras'
mean comes from `measure_pass(..., CAM_H/2, ...)` (`main.c:16651` and `main.c:16710`) — the same row
span. The `MB_CAM1_ROI` band that fixed camera 1's mask does **not** touch the brightness path: it is
applied by `cam1_roi_zero(dst)` to the **mask lattice** (`main.c:5807-5824`, `5912`), zeroing cells
outside rows 50..89 *before* the threshold/erosion/cluster, and it is a no-op for camera 0. So
`mean 498 ‰` on both cameras is the same measurement over the same rows.

### The AWB block is alive, and that is the whole story of the 1-and-7-LSB differences

Three samples per register, 2 s apart, twice (two independent series):

| reg | camera 0 (series 1 / series 2) | camera 1 (series 1 / series 2) |
|---|---|---|
| `0x3400` | `05 05 05` / `05 05 05` static | `05 05 05` / `05 05 05` static |
| `0x3401` | `8A 91 91` / `90 8D 96` **moves** | `8E 8E 8C` / `85 89 91` **moves** |
| `0x3402` | `04 04 04` static | `04 04 04` static |
| `0x3403` | `00 00 00` static | `00 00 00` static |
| `0x3404` | `05 05 05` static | `05 05 05` static |
| `0x3405` | `B3 B0 B5` / `B5 B3 B3` **moves** | `B4 BD B4` / `B0 AE B0` **moves** |
| `0x3406` | `00 00 00` static | `00 00 00` static |
| `0x5001` | `A3 A3 A3` static | `A3 A3 A3` static |
| `0x3208` | `F0 F0 F0` static | `F0 F0 F0` static |

**How much the AWB block differs between the cameras, and what it implies for green:** read as three
16-bit channel gains — `(0x3400,0x3401)`, `(0x3402,0x3403)`, `(0x3404,0x3405)` — the middle pair is
`0x0400` = **1024 = exactly 1.000×** and is *static and identical* on both cameras; the other two are
≈1.39× and ≈1.42× on both. The **largest between-camera difference anywhere in the block is 7 LSB**
(≈3.9 % of one channel), and it is *the same size as each camera's own jitter* — camera 0's `0x3401`
alone ranged 0x8A–0x96 (12 LSB) and its `0x3405` 0xB0–0xB5. So the two AWB blocks are
**statistically indistinguishable**, and the channel that sits at exactly 1.000× is at exactly 1.000×
on both. I cannot verify from a document which of the three is green; what I can state is that
**no channel gain differs by more than ~4 %, so AWB cannot account for ~half of a 36 % deficit** —
it cannot account for more than a few percent of anything, and if the 1.000× channel is green it
accounts for 0 %.

---

## 3. Diff against the 303-entry table

`ps_fft_dual/ov5640_table.txt`, 303 entries, checked mechanically:

* The table writes **`0x3503 = 0x00` exactly twice** (entries 251 and 300). Both sensors now read
  `0x3503 = 0x03`, so that value did **not** come from the table — it is the firmware's own
  manual-mode write (`main.c:15990` writes `0x3503 = 0x03` on bus `0xE0005000` before setting an
  exposure; `cam_i2c.c:358` states AEC and AGC are manual).
* The table writes **nothing else** in this space: no `0x3500`, `0x3501`, `0x3502`, `0x350A`,
  `0x350B`, no `0x3400`–`0x3406`, no `0x3208`. (Only `0x3C01`, `0x460B` and the two `0x3503` entries
  even match a `0x3x` pattern.)
* Therefore **every value in the exposure, gain and AWB rows was written by something other than the
  table** — the firmware's two AEC controllers, or the sensor's own ISP (the AWB block moves between
  samples, so the sensor's AWB is running on both). There is no camera-1-specific table state.

---

## 4. Is the exposure the answer? — no, and the 325 ‰ needs a different explanation

The decisive comparison the brief asks for:

```
camera 0 exposure = 8662     camera 1 exposure = 8662     ratio 1.0000
camera 0 gain     = 16       camera 1 gain     = 16       ratio 1.0000
camera 0 mean     = 498 pm   camera 1 mean     = 498 pm   ratio 1.0000   (30 s, 10 samples)
```

Camera 1's exposure is **not smaller — it is the same number, and so is the mean.** By the brief's own
rule ("if it is equal or larger while the image is 36 % darker, the exposure hypothesis dies"), the
exposure hypothesis dies — *and so does the premise that the image is darker*.

**Where the 325 ‰ most likely came from (inference, E1, not measured):** this firmware's own measured
bench note (`main.c:12366`) says **"k=1/gain16 reads 325 pm, k=2/gain16 reads 517 pm"** — 325 ‰ is this
camera's signature at a **one-period shutter**. Camera 1's shutter is now `k = 2` of `k_max = 2`
(8662 = 2 × `MB_LINE10` 4331), and its `k_max` is derived *at boot from a single VTS read*
(`cam1_timing_derive()`, `main.c:8956`), falling back to `k_max = 1` — half the shutter — if that read
fails or `g_line10` is still 0 at that moment. `MB_CAM1_VTS` = 740 and `k_max` = 2 now, so this boot
was lucky. The loop has run ~12 400 frames since power-up and `MB_CAM1_AEC_EVAL` = 1553 = `frames/8`
exactly, so the loop was never restarted, and the 325 ‰ reading was most likely taken **before the
camera-1 controller walked its shutter from k=1 to k=2** — a real code path (`main.c:13017` raises k
while the image is dark), and it is the one mechanism on this board that produces exactly 325 ‰ at
gain 16.

**What to measure to settle it** (a later round, ~40 s): read `MB_CAM1_AEC_K` / `MB_CAM1_AEC_EXP` /
`MB_CAM1_MEAN` every 3 s for the first 30 s after a reload. If k starts at 1 and walks to 2, the 325 ‰
is a boot transient and the fix is to make `cam1_timing_derive()` run after `g_line10` is known (or
retry it), not to touch an exposure register.

---

## 5. The computed factor — and why an exposure write alone cannot deliver it

The brief's arithmetic, done in the brief's own units:

* Measured now: the factor to bring camera 1 to camera 0's mean is **498/498 = 1.000× — no change
  needed, and no 36 % deficit to explain.**
* If the 325 ‰ state is real: factor = **509 / 325 = 1.5662×**, i.e. exposure 8662 × 1.5662 =
  **13566** (1/16 line) = **848 lines** = 3.13 periods of 10 ms.
* **That value is not reachable on camera 1 as configured.** The OV5640 clamps the shutter to
  `VTS − 4` lines (the project's own model, `main.c:8934-8942`). Camera 1's VTS is 740 →
  ceiling **736 lines = 11776**. 13566 > 11776 by 15 %. Camera 0 can do it only because its frame
  length was deliberately raised to VTS 1200 → ceiling 1196 lines = 19136.
* **So the first write in any later round is camera 1's frame length, not its exposure.** Nearest
  whole period above 3.13 is `k = 3` → 12993 = 812 lines → requires VTS ≥ 816.

### Register sequence for a later round — **UNTESTED, and needs a bench session, not this probe**

```
# 1) give camera 1 the same frame-length headroom camera 0 already has (740 -> 1200)
#    ONE 4-byte transaction. Two separate writes are NOT safe here: main.c:3781 records
#    0x380E/0x380F coming back holding 0x3501 after two back-to-back writes.
write 0x380E/0x380F = 0x04B0         (cam_write16_bus(0xE0005000, 0x380E, 1200))
read  back 0x380E/0x380F, two samples must agree and equal 0x04B0

# 2) then the shutter, as a whole number of 10 ms periods (k = 3 -> 12993 = 0x32C1)
write 0x3500 = 0x00                  (top nibble; cam_set_exposure_bus skips it when unchanged)
write 0x3501 = 0x32
write 0x3502 = 0xC1
read  back 0x3500..0x3502, decode, must equal 12993

# 3) gain: leave at 16 (the floor; 0x350A=0x00 0x350B=0x10). It is the only lever that is
#    already min, so it cannot be used to go brighter beyond 16 -> 40 -> 64.
```

**Group hold (`0x3208`), explicitly untested.** It reads **`0xF0` on both cameras** right now, and
nothing in this repository writes it (not the 303-entry table, not `cam_i2c.c`, not `main.c`). I have
no OV5640 datasheet in this workspace, so I am **not** asserting what the low nibble of `0xF0` means
or which latch protocol this part wants. What can be said with evidence:

* the two-step "set the frame length, then set the shutter" sequence above is **not atomic** — between
  step 1 and step 2 the sensor runs the new frame length with the old shutter, which is exactly the
  clamped-shutter condition `main.c:8933-8949` warns about;
* if `0x3208` is used to wrap steps 1 and 2, the sequence must start from whatever `0xF0` actually
  latches, which is **unknown** — reading `0x3208` back after a test write is the only way to learn it;
* therefore the bench procedure must be: **read `0x3208`, prove what a latch does on this part with a
  harmless register, and only then** wrap the VTS+exposure pair. Marked untested because it is.

---

## 6. What I could not read, and what would settle each

* **Bit meanings.** `0x3503`, `0x3208`, `0x5001`, `0x3400–0x3406` are reported **raw only**. The only
  bit-level statement in this note that has a source is `0x3503 = 0x03` = manual (from this project's
  own `cam_i2c.c:358` and `main.c:15990`). Settled by: an OV5640 datasheet in the workspace.
* **Which AWB register is green.** Not resolvable without a datasheet. It does not change the
  conclusion, because the whole block agrees to ≤4 %.
* **Whether the 325 ‰ state existed in *this* boot.** The firmware keeps no history of k or of the
  commanded exposure, so it cannot be reconstructed after the fact. Settled by: the 30 s post-reload
  monitor proposed in §4.
* **Camera 1's reference-quality diagnostics.** Only the state word (`MB_CAM1_REFQ` 613 = 1 = fail) is
  published; the dark/coverage/area words 545–550 are **camera 0's only**. So *why* camera 1's
  reference fails quality is not readable from the mailbox — and camera 1's live mask is 3101 points
  against camera 0's 569, a 5.4× difference taken inside a band that is already restricted to the
  belt. That is a **segmentation** difference, not a brightness one, and it is where the remaining
  dual-view failure lives.
* **Optics, directly.** I measured no optical quantity. What the data refute is the *prediction* of
  the optics hypothesis — a darker image at equal exposure and gain — which is not observed.
* **The bitstream's netlist.** The bus mapping rests on the firmware's constants and the BD scripts'
  last state, plus the VTS cross-check above; I did not re-read the implemented design.

---

## 7. How to replay

```powershell
& 'D:\Vitis\Vitis\2023.1\bin\xsdb.bat' 'C:\Users\user\Documents\trustscope\ps_fft_dual\cam1exp_20261030.tcl'
& 'D:\Vitis\Vitis\2023.1\bin\xsdb.bat' 'C:\Users\user\Documents\trustscope\ps_fft_dual\cam1exp_i2c_20261030.tcl'
& 'D:\Vitis\Vitis\2023.1\bin\xsdb.bat' 'C:\Users\user\Documents\trustscope\ps_fft_dual\cam1exp_awb_20261030.tcl'
```

Each script re-runs its own controls: build id `TSC19FCEAB62` (the read path carries the live
firmware's values), `MB_PS_FRAMES` advancing (the loop is running), chip ID `0x56 0x40` on both buses,
and the mailbox-vs-register agreement on exposure, gain and VTS on **each** bus.

**One hazard, deliberately taken and mitigated.** `ps_ui/cam_i2c.c:96-101` records *"This driver
requires EXCLUSIVE ownership of the PS I2C controller: no XSDB I2C access while the firmware runs."*
The reads were only defensible because both AECs were converged and issuing **no** writes (the
firmware writes only when the lock value or an adjustment changes), and it was checked both ways:
`SR.BUS_BUSY` before every transaction, and the two AEC words compared before and after the window —
`CONTENTION CHECK PASS` in both I2C runs, with 101 and 731 loop frames elapsing during them. The
firmware rewrites `CR` at the start of each of its own transfers, so it does not depend on any
controller state this probe leaves behind.
