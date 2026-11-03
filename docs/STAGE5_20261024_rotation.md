# Stage 5 (2026-10-24) — the registration estimates ROTATION

## Why

The operator cannot fixture the part. The measured board on this bench sits several
degrees off square (about 4.4 degrees by the operator's measurement), while the
comparison's tolerance is under 0.2 degrees. Translation + scale cannot remove an
orientation difference, so every good part would compare as a field of edge cells.
This stage extends the transform to

    baseline = centre + scale * R(-angle) * (live - centre) - shift

with the centre at the frame centre (the same convention shift and scale already used).
Shift and scale stay exactly as they were; rotation is the third parameter.

## What changed in `ps_ui/main.c`

| item | before | after |
|---|---|---|
| transform state | `g_px[]`, `g_py[]` (separable column/row maps, `reg_maps(scale)`) | four Q12 coefficients `g_ra11..g_ra22` (`reg_coeffs(scale_fp, th100)`), plus `g_reg_th100` (1/100 degree) |
| trig | none | 1-degree Q15 sine table, linear interpolation and quadrant reduction (`reg_sin_q15`, `reg_cos_q15`); chord error < 0.003 degree |
| search order | translation → scale → translation → mid → scale refine → fine | translation → **rotation (coarse, 1 deg)** → **rotation refine (0.1 deg)** → scale → translation (only if scale moved) → mid → scale refine → fine → scale parabola → **angle parabola** → final 3x3 translation |
| scoring | nearest sample of the half-res baseline | **nearest for coarse stages, bilinear for every refinement stage** (`reg_score(..., sub)`), using the same Q12 position `ref_at()` uses |
| comparison | `ref_at()` sampled the baseline at `centre + (live-centre)*scale - shift` | `ref_at()` applies the same rotation: `vx*cos + vy*sin`, `-vx*sin + vy*cos` before the scale and shift. Angle 0 still reproduces the old expression exactly |
| published | scale, shift, error | plus `MB_REG_ANGLE` (word 385, tenths of a degree, signed) and `MB_REG_ANGLE100` (word 386, hundredths, the search's own resolution, for auditing the rounding) |

The masks are untouched: a point is still scored only when the live mask says it is
part **and** the baseline mask says the point it maps to is part.

### Rotation before scale is a measured decision, not a preference

The first implementation kept the old order (scale first) and searched the angle after
it. On the offline known-answer test this **failed at 4.4 degrees**: a rotation is not a
scale, but at 4.4 degrees the scale sweep chose 1.045 as the least-bad trial scale, the
angle sweep anchored on that scale read **1.75 degrees instead of 4.4**, left 598 blob
cells, and the match error was 12.4 grey levels. At scale 1.0 the same angle sweep has a
clean minimum at 4 degrees (error 76 against 227 at zero). Putting the angle first fixed
it: 4.30 degrees recovered, 0 blob cells, error 3.9 levels. This is why the order in the
code is rotation-before-scale, and it is recorded here so it is not "cleaned up" later.

### Bilinear scoring in the refinement stages is also measured

With nearest sampling the 0.1-degree error surface was jagged (74, 77, 77, 78, 79, 78,
77 at 0.1-degree steps around 0.5 degree): every candidate quantises to a whole
half-resolution pixel, which is coarser than the angle step. Bilinear scoring made the
surface smooth and the recovery exact. The coarse stages stay nearest because they are
only placing the part in the window, and because bilinear on every point of a 289-offset
sweep would be wasted work.

## The offline known-answer test (`ps_ui/st5_rot_check.py`)

The camera is aimed at the room (see `dl/STEP0_20261024_mask_empty.md`), so a physically
rotated part cannot be presented to the firmware in this session. The algorithm was
therefore measured on a **real part frame** (`ps_ui/st2_A_live.raw`, an image of the PCB
filling the middle of the frame) rotated about the frame centre by a KNOWN angle, using
the same edge-clamped bilinear rotation as `st3_blur_sweep.py` (whose two artefacts, a
black wedge and a wrapped row, were already found and removed).

The script is a **port of the C integer arithmetic**, not the firmware: half-res grey,
8-pixel lattice, the mask (median + 12, 3x3 erosion), the exact search stages, the Q12
transform, `ref_at`/`ref_cell`'s bilinear 5x5 boxes and the comparison's gain, bias,
14-count threshold and 3x3 blob rule. The one numerical difference is the sine source
(library cos/sin rounded to Q15 instead of the 1-degree table); the resulting coefficient
difference is under 1 LSB, i.e. under 0.003 degrees.

Result, one line per injected rotation (cells are after the firmware's blob rule, so the
number to compare with the limit is `blob`):

| injected angle | recovered (deg) | error | top-edge slope difference | scale | match error (levels) | cells | blob |
|---|---|---|---|---|---|---|---|
| 0.00 | 0.00 | 0.00 | 0.00 | 1.000 | 0.44 | 0 | 0 |
| 0.16 | 0.17 | +0.01 | 0.18 | 1.000 | 0.75 | 0 | 0 |
| 0.50 | 0.50 | 0.00 | 0.63 | 1.000 | 1.06 | 0 | 0 |
| 1.00 | 1.00 | 0.00 | 1.01 | 1.000 | 1.06 | 0 | 0 |
| 4.40 | 4.40 | 0.00 | 4.20 | 1.000 | 1.06 | 0 | 0 |
| −4.40 | −4.40 | 0.00 | −3.96 | 1.000 | 1.00 | 0 | 0 |

**The independent check is the `slope-d` column**, not the estimator's own number: it is
a least-squares fit of the part's top edge (24 column-band medians, mask bbox, first
five-row green run) in the baseline and in the rotated image, and it does not use the
registration at all. Its agreement with the injected angle (within 0.45 degree at the
worst point, 0.01 at most points) checks both the magnitude and the sign convention.
The oracle column of the script (compare with the exact generating transform) is 0
cells at every angle, which separates "the comparator cannot do this" from "the
estimator missed the angle".

## Sign convention

**Positive = the part appears rotated CLOCKWISE in the displayed image** (y down), i.e.
its top edge slopes DOWN to the right. The independent top-edge fit uses the same
convention, so `atan(slope)` and `MB_REG_ANGLE` are directly comparable. If the
operator's convention is counter-clockwise-positive, their −4.4 degrees is this
document's **+44 tenths**; the magnitude is what must agree.

A sanity measurement on the bench's own last good frame (`ps_ui/board.raw`, the PCB
close-up of 2026-10-23 21:04): the top-edge fit reads **+3.2 degrees** with the same
method. That is a different framing from the −4.4-degree measurement the task quotes,
so the two numbers are not claimed to be the same experiment; it does confirm that a
real board on this bench is a few degrees off square and positive in this convention.

## On the board

* Built with `ps_ui/build.ps1`: 0 collisions, all layout checks pass, `.text` 84,116,
  `.bss` 30,932; only the four pre-existing warnings.
* Flashed with `xsdb ps_fft_dual/strict_load_cores.tcl`. Board reads FWID
  `TSC1` / `5DE70760` (matches `build_id.h`).
* The refusal path is unchanged and verified: with no part in view,
  `MB_PART_PTS` = 45..51 < 400, `MB_REG_STATE` = 2, `MB_REG_ANGLE` = 0,
  `MB_REG_ANGLE100` = 0, `MB_DIFF_OK` = 5, `MB_DIFF_VERDICT` = 2 (CANNOT JUDGE),
  `MB_READY` = 1. The rotation code is not reached, as designed.

## NOT verified (and how to verify it)

1. **The firmware's own angle on a physically rotated part — NOT DONE.** No part is in
   front of the camera; this session cannot move it. Exact experiment for whoever can:
   put the part on the stopped belt, take a baseline (`MB_CMD = 9`), read
   `MB_REG_ANGLE` (word 385) and `MB_REG_STATE` (232); then rotate the part by a known
   amount (a protractor or a trammel on the bench), take a strip with
   `xsdb ps_fft_dual/qc_strip_20261024.tcl` **before and after** and measure the
   top-edge slope of
   each with the same least-squares method; `MB_REG_ANGLE` must track the part, and the
   difference of the slopes must agree with the change in the reported word within
   0.5 degree. Then `MB_DIFF_CELLS` must be small (0..8) on a good part.
2. **The search cost on the board** (`MB_REG_TICKS`) is not measurable without a mask
   above 400 points, so the new bilinear stages' runtime is unmeasured. Estimate from
   the evaluation count: about 160,000 point evaluations, of which ~60,000 bilinear;
   the masked stages score ~1,500 points at stride 1, so this should stay within a few
   tens of milliseconds of the 39-43 ms the unmasked search took. It runs once per 16
   frames. Measure it with the operator's part present.
3. **The comparison throughput with rotation** (`MB_DIFF_MS`) is likewise unmeasured;
   `ref_at()` gains four multiplies per sample (360,000 samples per comparison), which
   should be a few milliseconds, but it is not measured.
4. The offline port and the firmware differ in the sine source (table vs library, < 1
   LSB). Not a behavioural difference at the 0.1-degree step, but it is a difference and
   it is stated rather than glossed over.
