# Stage 5 (2026-10-24) — contour feature matching: the difference map now has a shape and a name

**Result in one line: the difference map the comparison already produced is now labelled
into 8-connected blobs, each measured (area, bbox, centroid, fill ratio, aspect ratio,
attachment to the part outline, enclosed background holes) and put through a deterministic
rule table that publishes one of hole / notch / contamination-foreign-object /
large-area-mismatch / unclassified / too-small plus the bbox, and the box is drawn on the
panel at exactly the published coordinates (verified by reading the pixels back out of the
framebuffer, not by looking at the code). The table was tested against 14 known-answer maps
through a port of the arithmetic and against 3 of them through the SHIPPED C on the board
(3 of 3 as expected). No classification accuracy is claimed: the operator's ~40 damaged
boards are the only way to measure that and this session cannot run them.**

## What changed (`ps_ui/main.c`)

| line | item |
|---|---|
| 1918–1949 | the words 462..480: class, bbox, area, fill, aspect, touch, holes, blob count, centroid, ticks, class bitmask, self-test |
| 4342–4346 | `BLOB_MAX`, `BLOB_MIN_CELLS`, `BLOB_LARGE`, `BLOB_FILL_NOTCH`, the label and queue arrays (DDR) |
| 4369 | `blob_cell_on()` — the map under test; substitutes a synthetic pattern for the self-test |
| 4392 | `blob_part_state()` — interior / boundary / outside, from the same eroded part mask the registration uses |
| 4415 | `blob_holes()` — bounded BFS from the bbox border, then the components it never reached |
| 4474 | `blob_classify()` — the rule table, one place, no thresholds fitted to a board |
| 4489 | `contour_run()` — 8-connected labelling, per-blob features, the class, the published words |
| 4634 | `blob_selftest()` — three synthetic maps through `contour_run()`, the class each produced |
| 4641 | the call in `diff_frame()`, after the persistence pass and before the full-resolution refinement |
| 5619 | `draw_blob_box()` — the box, in the overview mapping only |
| 8880 | the call right after `draw_camera()` |
| 9253 | `MB_CMD = 13` — the host command that runs the known-answer test |

## The rule table (first match wins)

| class | condition | why |
|---|---|---|
| 0 NONE | no cell survived the persistence rule | nothing to name |
| 1 TOO_SMALL | area < 3 cells | one cell is 2.9 x 4.0 mm at the documented 0.18/0.25 mm per pixel, so a couple of cells IS the detection floor. This class exists to refuse to name a defect, and it is checked FIRST |
| 2 HOLE | holes >= 1 | an enclosed background region inside the blob is a ring around a hole |
| 3 LARGE_AREA | area >= 40 cells (~460 mm2) | checked before notch so a missing corner is a mismatch, not a notch |
| 4 NOTCH | attached to the part outline (`touch` = 1) | the part's own shape is wrong there |
| 5 CONTAMINATION / FOREIGN OBJECT | not attached to the outline and compact (fill >= 55%) | something on the part, or outside it |
| 6 UNCLASSIFIED | none of the above | a low-fill sliver away from the outline: this instrument cannot name it, and says so |

**`NOTCH` IS "ATTACHED TO THE OUTLINE", NOT "LOW FILL RATIO", and the test is what found
out why.** The brief describes a notch as a boundary blob with a low fill ratio. The
known-answer run showed that a *rectangular* bite out of an edge has fill ratio 100% -- the
blob is exactly its own bounding box -- while a thin sliver has a low one. The first version
of the table (`touch && fill < 55%`) therefore classified the most obvious notch there is as
contamination. The feature that separates a shape defect of the part from something lying on
it is *where the blob is*, not how hollow it is; the fill ratio stays in the table (it is
what separates a compact blob from an unclassifiable sliver) and it is published. A
low-fill boundary blob is still a notch -- because every boundary blob is.

## The known-answer results

**Through the port (`ps_ui/st5_blob_check.py`, 14 of 14):**

| case | expected | got | the features that decided it |
|---|---|---|---|
| A ring 11x9 with a 7x5 hollow | HOLE | HOLE | area 64, bbox 11x9, fill 64%, holes 1 |
| B 30 cells on the part outline | NOTCH | NOTCH | area 30, fill 100%, aspect 750, touch 1 |
| B2 one row on the outline | NOTCH | NOTCH | area 15, aspect 1500, touch 1 |
| C compact 4x4 inside the part | CONTAMINATION | CONTAMINATION | area 16, fill 100%, touch 0 |
| D two cells | TOO_SMALL | TOO_SMALL | area 2 < the floor of 3 |
| E three cells | CONTAMINATION | CONTAMINATION | area 3 = the floor exactly |
| F 39 cells on the outline | NOTCH | NOTCH | 39 < 40, so not large-area |
| G 40 cells on the outline | LARGE_AREA | LARGE_AREA | 40 = the large-area line exactly |
| H 64 cells on the edge | LARGE_AREA | LARGE_AREA | large beats notch, on purpose |
| I two separate blobs | CONTAMINATION | CONTAMINATION | the largest is published; n_blobs = 2 |
| J nothing | NONE | NONE | - |
| K 1-cell ring, 5x5 | HOLE | HOLE | area 16, fill 64%, holes 1 |
| L diagonal sliver inside the part | UNCLASSIFIED | UNCLASSIFIED | area 10, bbox 10x10, fill 10% |
| M compact blob outside the part | CONTAMINATION | CONTAMINATION | touch 2 |

**Through the SHIPPED C on the board (`MB_CMD = 13`, `ps_fft_dual/st5_selftest_20261024.tcl`):**

```
case 1 (ring, expect HOLE)          got HOLE          (2)
case 2 (edge strip, expect NOTCH)   got NOTCH         (4)
case 3 (compact, expect CONTAM)     got CONTAMINATION (5)
MB_BLOB_SELFTEST = 0x0303  => 3 of 3 passed
case 3 features: area=16 bbox=(30,20)-(33,23) fill=100% aspect=100 touch=0 holes=0 blobs=1
```

The port predicts `area 16, bbox (30,20)-(33,23), fill 100%, aspect 100, touch 0, holes 0` for
case 3 and the firmware publishes exactly that. That agreement on a known map is the
strongest cross-check available here: **this project has no host C compiler** (build.ps1
drives arm-none-eabi-gcc only), so there is no way to unit-test the C off-target, and a
Python port that agrees with the C on three cases is not proof that they agree everywhere.
What it does establish is that the table is deterministic, the answers were written down
before the measurement, and the shipped code produces them.

## On a real difference (the board, this session)

`ps_fft_dual/st5_draw3_20261024.tcl`, a comparison with a real difference at the frame's
right edge:

```
class=5 (CONTAMINATION/FOREIGN)  grid bbox (63,25)-(70,25)  area 8 cells  touch=2 (outside the part)
expected on screen (overview, x8): (504,200)-(567,207)
red pixels found in the framebuffer: 240, at window columns 0..79, rows 16..23
interior pixel at that box's centre: not red  -> a frame, not a filled rectangle
```

The box's top edge lands on row 200 = 25 x 8 and its 8-row height is the bbox's one cell row
x 8, which is the overview mapping exactly. **The pixel read back is the independent check**:
"the drawing function was called" would have been a claim about the code, and the first read
of the framebuffer *looked* like it contradicted it -- `px()` stores B,G,R (main.c:5458), so
the red box reads back as bytes (0,0,255) and my first check looked for (255,0,0) and found
"nothing". Both the false negative and its cause are recorded here rather than quietly fixed,
because the same trap applies to every future framebuffer check.

The class for that blob is CONTAMINATION with `touch` = 2 (wholly outside the part): a
difference at the frame's right edge, 8 cells, compact. That is a sane answer for "something
that is not the part changed there" -- and it is also the honest limit of the class: the
instrument knows *that* something is there and *where*, not what it is.

## Cost

`MB_BLOB_TICKS` reads 195,311..206,196 ticks = 0.58..0.62 ms per comparison (once per ~2.3 s,
i.e. 0.4% of one loop in sixteen). The loop rate is unchanged at 6.39 fps. The label and
queue arrays are 14,400 bytes of DDR at `0x127BC000`/`0x127BE000`, in the hole between the
Stage 2 accumulators and `GREY_BASE`; nothing in `.bss` grew for them.

## What remains unverified, with the exact experiment

1. **Classification accuracy — NOT MEASURED, and it must not be claimed.** The rule table is a
   position argument tested on synthetic maps, not a fit to damaged boards. Experiment (the
   operator's, ~40 boards): for each board record `MB_BLOB_CLASS` (462), the bbox (463..466),
   `MB_DIFF_CELLS` (181) and the operator's own description; build the confusion matrix. Until
   then the only defensible statement is "the class is what the table says about the map",
   never "it identifies holes".
2. **A real ring-shaped difference on a real part.** The synthetic ring is exact geometry; a
   real hole's difference ring will be ragged. Experiment: a board with a known clearance
   hole, take a reference (`MB_CMD = 9`), and read `MB_BLOB_HOLES` (471) and
   `MB_BLOB_CLASS`; if a real hole reads HOLE with 1 hole, the ring detector works on real
   data and not only on a rectangle.
3. **A notch on a real part edge.** Same protocol with a board that has a filed notch; expect
   `MB_BLOB_TOUCH` = 1 and class 4. If a real notch reads CONTAMINATION, the outline test
   (`blob_part_state`, which relies on the eroded part mask) is too strict at the edge and the
   4x4-block "interior" rule needs re-deriving against the mask's actual erosion.
4. **The box in the 1:1 zoom is NOT drawn** (the mapping is a crop, not a halving, and a box
   in the wrong place is worse than none). The class is published in that mode; drawing the
   box there is a separate change with its own verification.
5. **A frame with more than `BLOB_MAX` (12) blobs** publishes the first twelve in raster
   order and reports the true count; which of them is classified is then not "the largest of
   all". Not exercised on this bench (the counts seen were 1..3 blobs).

## Build and flash

`.text` 96,004, `.bss` 31,432, 279 mailbox words with 0 collisions, all layout checks pass,
only the four pre-existing warnings. Flashed with `ps_fft_dual/strict_load_cores.tcl`; the
board reads FWID `TSC1` / `2E19C0C8`. No bitstream rebuild, no power cycle, no running-VDMA
poke.

## A note on the bench state during this stage

The scene was moving for part of the session (the firmware's own readiness gate declined 73
loops of 60 s in the last verification run, and `MB_AVG_CNT` fell to 1 in that window because
the Stage 2 sampler refuses frames while the scene is not ready). A comparison taken then read
27..32 cells, which is the moving-scene behaviour the earlier stages also report, not a
Stage 5 effect: Stage 5 only labels and draws, it does not change the count. The Stage 2
acceptance run quoted in `dl/STAGE2_20261024_average.md` is one in which `MB_AVG_SKIP` did not
move at all, and that distinction is the reason both are reported.
