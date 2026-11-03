# Fix 2 — the two capture channels' fourth frame stores overlapped

Done 2026-10-23 21:3x.  Everything below was read from the board; the "before" numbers are
the ones in the task text and were re-read here before the change.

## The defect

Two capture channels, four frame stores each, circular mode.  A store is
720 x 3840 = 2,764,800 bytes = 0x2A3000.

| channel | store 0 | store 1 | store 2 | store 3 |
|---|---|---|---|---|
| camera 0 (VDMA 0x43000000) | 0x10000000 | 0x10400000 | 0x10C00000 | 0x12000000 .. 0x122A2FFF |
| camera 1 (VDMA 0x44A00000) **before** | 0x11200000 | 0x11600000 | 0x11A00000 | **0x11E00000 .. 0x120A2FFF** |

Camera 1's store 3 ran 0x11E00000..0x120A2FFF while camera 0's store 3 started at
0x12000000: an overlap of **0x00A3000 = 667,648 bytes = camera-0 store 3 rows 0..173**.
Both channels read CR = 0x00010003 (RS = 1, Circular_Park = 1) before and after, i.e. both
were live and cycling, so the overlapped region held whichever camera wrote it last.

## What changed, and where

`ps_fft_dual/stereo_bringup_byname.tcl`:

* the four camera-1 addresses are now named constants (`BUFA2/BUFB2/BUFC2/BUFD2`) instead
  of three literals plus one in the call, with the measurement, the arithmetic and the
  choice written next to them;
* the fourth slot is **0x11D00000**;
* the comment that claimed "camera 1 stays on two stores (A,B,A,B)" was wrong about the
  code (the call passed four distinct addresses, which is what the S2MM registers read
  back) and has been replaced with what the registers actually show.

`ps_ui/main.c`: `cam1_stores[4]` now names 0x11A00000 / **0x11D00000**, and the two comment
blocks that asserted the overlap (`CAM0_STORE_SHARED`, the address map at GREY_BASE) say
it was measured, then fixed, with the new readback.  `CAM0_STORE_SHARED` is kept at **0**
because the readiness gate's store substitution is still justified by comparing two
different frames, not by the overlay; nothing reads the macro.

## Why 0x11D00000, and the constraints that were checked

* **Space.**  0x11D00000..0x11FA2FFF is free: camera 1's store 2 ends at 0x11CA2FFF, so
  there is 0x5D000 of gap below it, and camera 0's store 3 begins at 0x12000000, 0x0D0001
  above its end.  It is 1 MB aligned.
* **Why not move camera 0's fourth store instead:** it sits at the bottom of the
  0x12000000 region and the hole above it (0x122A3000..0x12400000, 1,441,792 bytes) is
  smaller than a store, so it has nowhere to go inside that region.  0x11D00000 is the
  only free, 1 MB aligned 2.76 MB hole in the DDR map.
* **The PL DMA writes physical DDR**, so the DMA needs no MMU mapping for a new address.
  What needs one is anything the **PS reads**, and `ps_ui/mmu.c` maps exactly:
  `0x00000000..0x003FFFFF` (OCM), `0x10000000..0x10EFFFFF` (WBWA: cam0 stores 0/1/2, UI A/B),
  `0x11000000..0x11FFFFFF` (WBWA, 16 sections: the whole camera-1 window),
  `0x12000000..0x127FFFFF` (WBWA: cam0 store 3, reference, lattices, greyscale),
  `0x10F00000..0x10FFFFFF` (non-cacheable: mailbox), `0x40000000..0x7FFFFFFF` (device: PL),
  `0xF8000000..0xF8FFFFFF` and `0xE0000000..0xEFFFFFFF` (PS, IOP).  0x11D00000..0x11FA2FFF
  is **entirely inside the 0x11000000 window** — the old 0x11E00000 store ran 0xA3000 past
  the end of that window into the 0x12000000 one, which happened to be mapped too.
* **No collision with anything in use**: 0x10800000/0x10A00000 UI buffers, 0x10F00000
  mailbox, 0x11000000..0x11043000 CNN, 0x12000000 cam0 store 3, 0x12400000 reference
  (to 0x126A3000), 0x126B0000 lattice, 0x126C0000/0x126C4000 part masks, 0x12700000
  background image, 0x127A8C00 background grid, 0x127B0000/0x127B0900 readiness grids,
  0x127C0000 greyscale baseline.  The overlap test below is computed over all 28 pairs of
  the eight stores, so it is not an eyeball check.

## The change was applied the safe way, and why that matters

A capture channel's start-address registers must not be written while the channel is
running: the address list and the frame store pointer are what the DMA walks, so a
mid-frame write can drop part of a frame at an address the channel then re-reads as a
different store.  `ps_fft_dual/apply_cam1_storemap_20261023.tcl` therefore replays
`CFG_VDMA`'s order exactly — CR = 0 (stop), clear SR, program HSIZE/STRIDE and the four
start addresses, CR = run + circular, **VSIZE last** (VSIZE is what starts the transfer
engine) — for camera 1 only, and refuses to touch the hardware if it cannot read the
`BUFC2`/`BUFD2` constants out of the bring-up script or if the channel's stride/VSIZE are
not the expected 3840/720.  It does not program the PL, does not power-cycle, and does not
write any register of a running channel.

## Verification on the board

Read back after the change (`ps_fft_dual/fix2_verify_20261023.tcl`):

| channel | store 0 | store 1 | store 2 | store 3 |
|---|---|---|---|---|
| camera 0 | 0x10000000..0x102A2FFF | 0x10400000..0x106A2FFF | 0x10C00000..0x10EA2FFF | 0x12000000..0x122A2FFF |
| camera 1 | 0x11200000..0x114A2FFF | 0x11600000..0x118A2FFF | 0x11A00000..0x11CA2FFF | **0x11D00000..0x11FA2FFF** |

* **Overlaps among the eight stores: 0 of 28 pairs** (computed from the registers, not
  eyeballed).  cam0 store3 ends 0x122A2FFF; cam1 store3 ends 0x11FA2FFF; the gap between
  cam1 store3's end and cam0 store3's start is 0x5D001 bytes.
* **All four camera-1 stores are inside 0x11000000..0x11FFFFFF** and all four camera-0
  stores inside 0x10000000..0x122A2FFF (the 0x10000000 and 0x12000000 windows of mmu.c).
* **Both channels still running**: CR = 0x00010003 on both.
* **The new store is really being written** (`fix2_store_live_20261023.tcl`, two rounds,
  32 addresses 4 KB apart sampled 900 ms apart, with live controls):

  | store | round 1 | round 2 |
  |---|---|---|
  | cam0 store0 (control) | 32/32 changed | 32/32 |
  | cam1 store0 (control) | 32/32 | 32/32 |
  | cam1 store2 (control) | 32/32 | 32/32 |
  | **cam1 store3 = 0x11D00000** | **31/32** | **30/32** |

* **Camera 1 still reaches the PS**: `MB_CAM1_MEAN` 498..501 against `MB_CAM0_MEAN`
  521..525 (the control — both cameras are on the same scene), `MB_CAM1_FP` advancing
  7,3,0,1, `MB_CAM1_STORE` following it, `MB_CAM1_PTR_BAD` = 0.

## Not verified, and an unexplained observation

* **The bring-up script itself was not executed end to end.**  Running
  `stereo_bringup_byname.tcl` programs the bitstream, and this session is not allowed to
  reprogram the PL (and the board was warm).  So the *edited script* has not been through a
  cold bring-up: what was verified is that the addresses it now names were applied to the
  live channel with the same register sequence, and that they work.  A power-cycle
  bring-up is the remaining test: `stereo_bringup_byname.tcl` -> `disp_fix_20261023.tcl` ->
  `strict_load_cores.tcl`, then `fix2_verify_20261023.tcl`, which should print the same
  layout and 0 overlaps.
* **S2MM status bits are not explained.**  Both channels report SR = 0x00011810, and
  camera 1 reports 0x00015810 after the reprogram (bit 14 added), before and after the
  address change; writing 0x00007FF0 to SR does not keep them clear.  Their meaning was not
  established here (PG020's bits 4 and 14 would be DMAIntErr and Err_Irq), and frames
  arrive on both channels with the controls above.  Recorded as an open question, not as
  an "OK".
* The old claim that camera 1's fourth store "runs past the end of camera 1's MMU window"
  was true of 0x11E00000 and is false of 0x11D00000 — but neither store was ever read by
  the PS at those addresses, so this changes no runtime behaviour today.  It matters for
  Fix 3, which starts reading camera 1's stores by index.
