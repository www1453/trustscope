# Step 0 (2026-10-24) — why the part mask is nearly empty: (a) there is no part in view

**Answer: (a). The camera is looking at the room, not at the bench. The mask is not
broken, the margin is not wrong for a part, and this is not the WIP build's doing.
No threshold was changed to make it pass. The operator has to re-frame the camera.**

## What was measured, and with what

Board up, running the `c1066f4` tree (FWID `TSC1` / `1E2293B1`) before any change.
Read-only mailbox sampling, `ps_fft_dual/qc_state_20261024.tcl`:

| word | value (4-6 samples) | meaning |
|---|---|---|
| 366 MB_PART_PTS | 36, 47, 65, 68, 73, 78 | live mask points after erosion (floor is 400) |
| 367 MB_PART_REF | 48, 49 | the stored baseline's mask is just as empty |
| 368 MB_PART_USED | 0 | the registration never scored a point |
| 369 MB_PART_MEDIAN | −22, −23 | frame block-score median, published as median+128 |
| 370 MB_PART_MARGIN | 12 | the threshold actually used |
| 232 MB_REG_STATE | 2 | CANNOT JUDGE |
| 180/181 MB_DIFF_OK / CELLS | 5 / 0xFFFFFFFF | refused, not measured |
| 224 MB_READY | 1 | the settle gate is open; the scene is still |

A fresh reference was then taken with the documented host command (`MB_CMD = 9`,
`ps_fft_dual/fix1_reftake_20261023.tcl`): `MB_PART_REF` went 48 → **46**, and the live
mask stayed at **35..53** over six samples. So a new baseline does not change the
answer: there is nothing part-shaped in the frame the baseline is made from.

## The picture

A full-frame dump is forbidden for structure work (it splices ~28 frames), so the frame
was covered by five narrow strips (0..199, 200..259, 260..459, 460..519, 520..719) with
`ps_fft_dual/qc_strip_20261024.tcl`; they are stitched in
`ps_ui/s24_stitched_view.png` only so a person can see the whole scene at once. The
scene is a door, boxes and a table. There is no PCB anywhere in the 1280x720 frame; the
only green-dominant objects are a bottle and a box in the lower half.

The strips are **pictures**, not a frame-to-frame comparison, and the firmware never
sees the stitched image.

## Ruling out (b): the margin is doing exactly what it was chosen to do

The firmware's own arithmetic was re-run on the stitched frame (2x2 samples at +2,+5,
C truncation, frame median, 3x3 erosion), at every margin in the range the code
documents. Current scene, measured now:

| margin | threshold (median −22) | eroded mask points | verdict against the 400-point floor |
|---|---|---|---|
| 6 | −16 | 597 | would pass — and would register the background |
| 8 | −14 | 310 | refused |
| 10 | −12 | 114 | refused |
| **12 (used)** | **−10** | **43** | **refused, correctly** |
| 16 | −6 | 10 | refused |
| 24 | +2 | 0 | refused |

The board reads 35..78 points; this independent replay reads 43 at the same margin, so
the mask arithmetic and the published numbers agree. Margin 6 would make the *box on
the floor* look like a part (597 points) — i.e. tuning the margin to force a pass is
exactly the failure mode the 400-point floor exists to prevent. (b) is refuted.

## Ruling out (c): the WIP build did not break the mask

The same mask rule applied to a **real part frame** from 2026-10-23 (`ps_ui/st2_A_live.raw`,
which contains the PCB filling the middle of the frame) gives **2,599 eroded points** at
margin 12 — the same number `dl/STAGE4_20261023_relative_mask.md` recorded for that frame.
A second real part frame (`ps_ui/n4.raw`, the board rotated about 3 degrees) gives
1,655..1,932 points depending on how the missing top 300 rows are treated. So with a part
in front of the camera this code produces 1,600..2,600 mask points, 20-50x what the room
produces. The mask was not broken by `c1066f4`; it is reporting the scene truthfully.

## Ruling out (d): AWB drift is not what this is

The colour balance is not healthy in the absolute sense — the frame median score is
−22, i.e. the green channel is typically 22 counts below max(R,B), and the room looks
pink. But the mask is a *relative* rule and it is finding the greenest blocks in the
frame; it cannot turn the door into a PCB. The two independent checks that settled the
AWB question on 2026-10-23 (the frame median and a no-shared-code replay) both agree
with the firmware here. There is no evidence that a colour-balance move is what emptied
the mask; the direct evidence is that the camera is aimed at the room.

What WOULD be needed to settle AWB drift definitively is the controlled experiment from
the earlier notes (one scene, two balance states, balance read back). It is not needed
to explain this reading, and it must not be used to excuse it.

## What the operator has to do (the exact experiment)

1. Aim camera 0 at the stopped belt so the PCB part sits **inside the field of view**,
   preferably occupying 10-25% of the frame, as it did at 20:12-21:04 on 2026-10-23
   (`ps_ui/st2_A_live_view.png` and `ps_ui/board.png` are examples of a usable framing).
2. Do not touch the white balance, the exposure or the lamp.
3. Take a fresh baseline: `xsdb ps_fft_dual/fix1_reftake_20261023.tcl`
   (this writes `MB_CMD = 9`, a documented host command; it changes no PL state).
4. Read back: `xsdb ps_fft_dual/qc_state_20261024.tcl 4`. Success is
   `MB_PART_PTS` = **1,000..3,000**, `MB_PART_REF` in the same range, `MB_REG_STATE = 1`,
   `MB_DIFF_OK = 1`, and `MB_DIFF_CELLS` small (0..8 on a good part).
   If `MB_PART_PTS` stays under 400 with the part visibly in the frame, stop: that is a
   scene/mask question and needs a new measurement, not a threshold change.

Nothing about this was fixed in firmware. The threshold, the margin and the floor are
unchanged.
