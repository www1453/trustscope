# Item 1 (2026-10-26, session B1): camera 0 on an empty belt -- the mask term's hold can no longer be released by a clipped frame

Firmware `ps_ui/main.c`, source hash **EC090D84** as flashed (build `9784D2BB` is the same
source with shorter comment text; see section 6). Board: `ps_fft_dual/strict_load_cores.tcl`
only -- no bitstream, no power cycle, no VDMA register write. The comparison arithmetic, the
tolerance map, the amplitude/area rule, the registration and camera 1's controller were NOT
touched.

## 0. The one-paragraph answer

On an empty still belt with a reference that contains a part, camera 0 hunted because the
anti-windup hold that exists to stop exactly that was **released by the very clipped frame
the clip guard was about to reject, through two independent paths**: (i) the release test
`g_part_pts >= PART_MIN_PTS` is TRUE on a clipped frame (clipping inflates the mask --
1,287 cells measured), and (ii) the clip guard's own dim counted as "a non-mask lever move"
and cleared the hold, so the act of undoing the mask-driven move re-armed it. Both release
conditions are now unreachable from a clipped frame: the recovery release also requires
`g_cam0_clip_pm <= lim_now`, and only a lever moved FOR DARKNESS (dec 1/2) releases the
hold. Measured after: 150 clean samples with a deliberate 196-cell mask deficit -- state 1
in 150/150, k 2 in 150/150, **0 k transitions**, clip 0, and a 300-sample window in which
the only two transitions coincide with a measured scene event and recover in 20 s.

## 1. The defect, measured twice

| | last night (dl/CAM1_AEC_20261026.md s.4) | tonight, before the change |
|---|---|---|
| window | 300 samples / 288.3 s | 160 samples / 93.2 s (`.tmp/b1/before_empty.csv`) |
| `MB_AEC_K` | 2<->3, **26 transitions** | 2x151 / 3x9, **14 transitions** |
| `MB_CAM0_CLIP` | 109..144 (limit 10) | 0..139, over the limit in 10/160 |
| `MB_AEC_STATE` | 2 in 16/300 | 1x144 / 2x16 |
| `MB_AEC_MASK` | 1287 during the clipped frames | 190..264 |
| `MB_AEC_TRIES` | 0 (never published then) | **44 -> 58** |
| `MB_DIFF_N` | frozen at 60 | frozen at 384, `MB_DIFF_OK` 3x11 / 5x149 |
| `MB_PART_INVIEW` | -- | 0 in 160/160 |
| `MB_AEC_HOLD`/`MASKL` | not present | **3154822222 / -542448026 = unwritten DDR**, the control that proves these words were not written before this build |

Two mechanisms, both in `aec_control()`:
1. The mask term is gated on "the reference has a part" and driven by `g_part_pts`, the live
   mask against the background. On an empty belt the live mask was non-zero and below the
   400 floor, so the term read "the part is short: not enough light" and stepped k up.
2. The hold that is supposed to stop that was released by the clipped frame: the mask
   inflation above 400 satisfied the recovery release, and the clip guard's own dim was a
   "non-mask move" that cleared the hold. One evaluation later the mask was short again.

The AEC's own bounded search did not stop it either: `aec_stuck_tries > AEC_STUCK_TRIES`
only cancels a move **when the state is 3**, and here the state was 2, so the counter climbed
44 -> 58 with no effect. That is a third observation, stated and not fixed (the brief's list
of things not to touch includes the amplitude/area and comparison rules; this is the AEC's
bounded search, and changing it would change when the term stops).

## 2. What changed (file:line)

`ps_ui/main.c`:
* `main.c:1574-1602` -- two words: `MB_AEC_HOLD` 532, `MB_AEC_MASKL` 533; `MB_AEC_FLAGS`
  bit4 = hold. Mailbox 373 -> 375 words, 0 collisions, four pre-existing warnings.
* `aec_control()`'s anti-windup block: the recovery release is
  `if (g_part_pts >= PART_MIN_PTS && g_cam0_clip_pm <= lim_now)`.
* the "forget the mask move" block: `dec == 10 || dec == 11` stores `aec_mask_last`;
  `dec == 1 || dec == 2` (a move for darkness) releases the hold; `dec == 3/4/5` (clip /
  over-bright) keep both.
* the publish block: the two new words and flags bit4, every loop.

## 3. What the measurement changed about the framing (the most useful result of the night)

**The trigger is not "the reference contains a part". It is a background that no longer
matches the live exposure.** After the flash I took a fresh background on the same empty belt
(`MB_CMD` = 12, `MB_BG_STATE` 1, `MB_BG_MEDD` 3-4) and the empty-belt mask collapsed from
**190..264 cells to 0-9**; with that fresh background the OLD build would not have hunted
either. `MB_BG_STATE` 4 ("adopted") is therefore **not a freshness signal**: the background
in force before the flash was an adopted one from an earlier session, and its mismatch was
the whole trigger. Stated as a station rule: *take the background only on a verified-empty
belt, and treat 4 as "adopted", never as "current".*

Because a fresh-background acceptance would have proved nothing, the fix was exercised
against a **deterministic short-mask trigger built through a documented host path**
(`ps_fft_dual/b1_patch_20261026.tcl`): lower a 16x16-cell patch of the background's own 8x8
grid (`BG_GRID_BASE` 0x127A8C00) by 40 counts and adopt it with `MB_CMD` = 18, which re-runs
the firmware's own "does this background describe this scene" test (`MB_BG_STATE` 4, 256 raw
cells = 1.8 % of the grid). The live mask becomes 196 cells (box 61,46..74,59,
`MB_PART_INVIEW` 0) -- the same magnitude as the 190..264 a stale background produced. This
is reusable for the mask-scope work: a controlled, non-destructive mask deficit without
waiting for a background to go stale.

## 4. Acceptance

Arm (a), the brief's state, natural: board reference 536 in force, belt empty and still,
150 samples / 94.9 s (`.tmp/b1/after_empty_natural.csv`):
`MB_AEC_STATE` **1 in 150/150**, `MB_AEC_K` **2 in 150/150 (0 transitions)**,
`MB_AEC_EXP` 8698 constant, `MB_CAM0_CLIP` **0 in 150/150**, `MB_AEC_MEAN` 521..525,
`MB_AEC_HOLD` 0 in the first 11 samples then **1 in 139/150**, `MB_AEC_MASKL` 3,
`MB_AEC_TRIES` 2 -> 0, `MB_PART_PTS` 0..85, `MB_PART_REF` 536, `MB_PART_RULE` 1,
`MB_BG_CELLS` 97..355, `MB_PART_INVIEW` **0 in 150/150**, `MB_DIFF_N` frozen at 89,
`MB_DIFF_OK` 5 in 150/150. The transient (2 mask-driven moves) happened as the board left,
before the trace; the trace shows the hold latching at sample 12. A real belt artefact then
appeared (part_pts 3 -> 85, presence 115 -> 355) and the controller did not react.

Arm (b), the deficit present, 300 samples / 172.9 s (`.tmp/b1/after_empty_mask196.csv`):
mask 196 held for samples 0..198 (115 s) with `MB_AEC_HOLD` 1, `MB_AEC_MASKL` 5, clip 0,
`MB_AEC_TRIES` 0 -- no lever moves. Then an **unplanned scene event** (samples 196..202:
`MB_BG_CELLS` 400 -> 1456 and `MB_PART_PTS` 225 -> 825, a large object/shadow crossing the
upper right; nobody touched the belt) raised the mask 196 -> 342 -> **419 >= 400**, which
released the hold exactly as designed; the term made ONE move (dec 10, k 2 -> 3, exp 13047,
`MB_CAM0_CLIP` **135**), the clip guard undid it (exp 8698, clip 114 -> 0, dec 9 = reversal
held, `MB_AEC_TRIES` 2) and the hold re-latched at sample 225 (`MB_AEC_MASKL` 419). Samples
225..299 are stable. Window totals: **2 k transitions, both at the scene event, 0 from
hunting**; state 1 in 298/300; clip over the limit in 2/300.

A second 300-sample window was attempted for a cleaner one and was **worse** (6 k
transitions, presence swinging 304..2436 cells, mask to 1785): the room was busy. It is
thrown away and not quoted as an acceptance.

Board in view, after the fix (the "PASS unchanged" half): `MB_CMD` = 9 -> `MB_PART_REF` 536,
`MB_DIFF_OK` 1, `MB_DIFF_VERDICT` 0 (PASS), `MB_DIFF_DAREA` 0, `MB_DIFF_FVALID` 530-533,
`MB_PART_USED` 425, `MB_REG_STATE` 1, `MB_ST_VERDICT` 0 / code 0 / fail 0x00 / res 0x00,
camera 0 state 1 / k 2 / mean 501-505 / clip 6-7, camera 1 state 1 / k 1 / exp 4349 /
mean 329-333 / clip 4, `MB_AEC_HOLD` 0 (release path (a) verified: the mask recovered to
536 >= 400 on an unclipped frame and the hold went 1 -> 0). A 40-sample window with the board
in view read `MB_DIFF_OK` 1 / `MB_DIFF_VERDICT` 0 / `MB_DIFF_DAREA` 0 in 40/40 while
`MB_DIFF_N` advanced 73 -> 79, and `preflight.py` returned
`PREFLIGHT PASS code=0 fail=0x00 | ref=536/400 bg(medd=2 cells=1587 rule=1 why=0 state=1) aec=1 clip=0 mask=608 vs presence=1587`, exit 0.

Note on the re-reference: the FIRST reference taken after the flash read **480 with a box of
1,5..158,77 (the whole frame)** and the station then refused every comparison (`MB_DIFF_OK`
5, `MB_REG_STATE` 2, `MB_REG_MODE` 0, DAREA unmeasured). `MB_BG_MEDD` had read **9** (over
the stale bound 8) between the fresh background and that reference -- the operator's shadow
while placing the board. Once the operator stepped clear the live mask went back to
board-sized and the retake gave 536 with a board-sized box and PASS. Station rule: *take the
reference only after the operator has left the frame.*

## 5. What remains unverified / limits

1. **The hold is released only by a mask >= 400 on an unclipped frame, or by a lever moved
   for darkness.** A part that arrives UNDEREXPOSED (mask 1..399) would therefore not release
   it, and the term would stay off. That is one new failure mode, deliberately not patched
   with a third rule that has not been measured. The three-line candidate, for the next
   session: release when `g_part_pts >= aec_mask_last + AEC_MASK_HYST` on an unclipped frame
   (a measured, material rise) as well as above 400.
2. **The k transition is bounded, not eliminated**, when the scene itself crosses the floor:
   one move per episode (measured: one move, clip 135, recovered in 20 s). That is the
   design, but it means "0 transitions" is only true while the scene does not cross 400.
3. **The scene events were not identified.** Two large objects/shadows crossed the frame
   during the 300-sample windows (`MB_BG_CELLS` to 1456 and 2436) with the room supposedly
   empty; the objects are in the mask, not in the background (the background was fresh).
   Whether they were people, a door or a lamp was not determined.
4. **The empty-belt mask is not zero** even with a fresh background: 0-9 cells, occasionally
   up to 85 with a belt artefact. `MB_PART_INVIEW` 0 and `MB_DIFF_OK` 5 are what the station
   refuses on. The mask's scope (room objects, belt seams) is item 2 and was NOT changed.
5. **One new `MB_AEC_TRIES` observation, not fixed:** the bounded search cancels a move only
   when the state is 3, so in the state-2 cycle the counter is decorative (44 -> 58
   measured). Changing it changes when the term stops and was out of scope.

## 6. Provenance

The flashed image is source hash **EC090D84** (`MB_FWID0..2` = 31435354 39304345 34384430).
The committed source (`9784D2BB`) differs from it only in comment text: the two
`objcopy -O binary` images differ in **19 bytes**, all of them the embedded source-hash
string or a 32-bit constant derived from it (offset 0x142C0: "TSC1EC090D84" vs
"TSC19784D2BB"; offset 0xD994: the same hash as MOVW/MOVT immediates). The instruction stream
is otherwise byte-identical.

## 7. Reproducing it

```
cd ps_ui; powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
xsdb ps_fft_dual/strict_load_cores.tcl                      # the only flash path
xsdb ps_fft_dual/b1_post_20261026.tcl                        # post-flash state + fresh background (empty belt)
xsdb ps_fft_dual/b1_bg_guard_20261026.tcl 300 400            # the same, but refuses if the view is occupied
xsdb ps_fft_dual/b1_ref_20261026.tcl                         # MB_CMD=9 + 20, PASS + preflight inputs
xsdb ps_fft_dual/b1_trace_20261026.tcl .tmp/b1 t.csv 300 200 "<names>"
python ps_ui/b1_trace_report.py .tmp/b1/t.csv
xsdb ps_fft_dual/b1_armb_20261026.tcl                        # release the hold, restore, re-create the deficit
xsdb ps_fft_dual/b1_patch_20261026.tcl 60 45 16 16 40        # just the deficit
xsdb ps_fft_dual/b1_trigger_20261026.tcl 4349                # the rejected exposure-mismatch trigger
```
