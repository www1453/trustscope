# The front end does not fit: a measured area failure, not a timing one

**Date:** 2026-10-28 (PL front-end, day 1 of 3)
**Question this answers:** does the verified AXI wrapper plus `pl_fe_core` fit in the
xc7z020 of this station?
**Answer:** **no.** `place_design` refuses it, and the reason is **slices**, not LUTs and not
hold. The brief's briefed risk was that *hold* would break at +0.037 ns; the real blocker is
that the device has no slice capacity left, and the 16,687-"free LUT" arithmetic in
`PL_INTEGRATION_20261028.md` §2 does not describe the resource that binds.

This is a complete answer to the gate. The block design has been restored, verified, and the
station's bitstream was never touched.

---

## 1. What failed, exactly

`impl_1`, from the synthesis of the design **with** the front end:

```
opt_design      complete (2 min 21 s, .dcp 29 MB -- the design is real, not stubs)
place_design    FAILED

ERROR: [Place 30-487] The packing of instances into the device could not be obeyed.
       There are a total of 13300 slices in the device, of which 9677 slices are
       available, however, the unplaced instances require 10126 slices.
ERROR: [Place 30-99]  Placer failed ... Detail Placement failed
SQL  : Number of control sets and instances constrained to the design
         Control sets: 1832
         Luts: 41092 (combined) 50631 (total), available capacity: 53200
```

**Short by ~449 slices** (10,126 required against 9,677 available), i.e. about **4.6 %** of
the remaining slice capacity, or roughly **1,800 LUT-equivalents** once the placer's packing
efficiency is accounted for.

## 2. Why the arithmetic in the integration note did not see this

`PL_INTEGRATION_20261028.md` §2 argued from **LUT percentages**: 36,513 used of 53,200
(68.63 %), 16,687 free, plus 1,863 for the block = 72.14 %. Every one of those numbers is
correct and the conclusion drawn from them is wrong, because:

* **A slice holds 4 LUTs, and the binding constraint is slices, not LUTs.** 36,513 LUTs is at
  best 9,128 slices; with 1,817 unique control sets, 2,294 F7 muxes, 2,306 LUTRAM (which can
  only go in the 3,325 SLICEMs) and the carry chains, the baseline already occupies most of
  the 13,300 slices. "31 % of the LUTs are free" and "4.6 % of the slices are free" are both
  true and describe very different amounts of room.
* **The wrapper costs more than the block.** Measured out-of-context, `pl_fe_top`
  (core + AXI read master + write master + control slave) is **LUT 2,711 / FF 1,577 / BRAM 0
  / DSP 0** — i.e. **+848 LUT and +1,006 FF** over `pl_fe_core` alone. The placer's own count
  of the whole design is **41,092 LUT**, a delta of **+4,579** over the baseline: the
  remaining **~1,870 LUT** are the 1x1 AXI interconnect, the **two automatic protocol
  converters** Vivado inserted between it and `S_AXI_HP2`, and the extra
  `ps7_0_axi_periph` master port. None of those existed when the 1,863-LUT figure was quoted.
* The note's own honest expectation was "75-78 % LUT with the wrapper". The measured figure
  is **77.2 %**. The estimate was right; the resource it was expressed in was not.

## 3. What is NOT the cause, so nobody re-tests it

| candidate | verdict |
|---|---|
| **hold (WHS)** | **never reached.** Placement fails before routing, so the +0.037 ns question was not answered — it is still open, and it is now downstream of an area problem. |
| the front end's arithmetic | untouched: 2,711 LUT / 0 BRAM / 0 DSP measured, and the block is still bit-exact. |
| the interface decision | unaffected. HP2 was the right port; it is simply on a full device. |
| a bad synthesis | no. `opt_design` completed on a 29 MB netlist; the 0-LUT `report_utilization` at the synthesis stage is this project's normal out-of-context artefact (see `PLFE_DAY1_20261028.md` §5). |
| the ≥2.3 px/clk idea | would make it **worse** — a wider datapath costs more area, and area is the blocker. |

## 4. The options, which are the owner's to choose

None of these is attempted here; each changes something the owner has already decided about.

1. **Free the area somewhere else.** The two ILAs (`u_ila_vid`, `ila_5mp`) are diagnostics,
   not function, and an ILA with wide probes costs hundreds of LUTs. Removing one is the
   single most direct lever, and it trades debugging visibility for the front end.
2. **Shrink the wrapper.** FIFO depth 128 -> 48 beats (~80 LUT), a smaller write burst, a
   cheaper settle counter. Realistic saving: **a few hundred LUT**, not 1,800.
3. **Remove the two automatic protocol converters** by giving the master AXI ID ports and
   matching the HP port's ID width. Maybe 600-1,000 LUT, and it is unverified RTL work.
4. **Accept that it does not fit** and keep the measured result as the answer: built,
   bit-exact, cheap in BRAM/DSP, and **too large for the remaining slices of this device**.

## 5. What was restored, and how it was verified

The brief's instruction on failure is to restore from the first backup. Done, and the restore
was **not** complete the first time, which is the useful part:

1. `python dl/backup.py restore 20261028_161217__plfe_day1_before_anything` restored
   `design_1.bd`, `two FFT.xpr` and all three XDCs, hash-verified. The `.bd` came back
   **byte-identical** (SHA256 `60a7dcb9...` matches `MANIFEST.txt`).
2. **But `PCW_USE_S_AXI_HP2` still read 1 and `ps7_0_axi_periph` still had 19 masters.** Both
   of those settings also live in the block design's **IP instance files**
   (`bd/design_1/ip/...`), which the backup did not carry. A `.bd`-only restore is therefore
   **not** a restore of the block design.
3. `ps_fft_dual/plfe_bd_revert.tcl` put both back (HP2 -> 0, NUM_MI -> 18) and gated the save
   on validation. Final state, read back from the design:

```
BEFORE|hp2=1|hp3=0|periph_num_mi=19
BEFORE|cells_pl_fe_top=0|cells_plfe_hp=0
REVERT|PCW_USE_S_AXI_HP2 set back to 0
REVERT|ps7_0_axi_periph NUM_MI set back to 18
AFTER|hp2=0|clk_pins=62|num_mi=18
AFTER|addr_segs_for_pl_fe_top=0
AFTER|errors=0
SAVE|saved
GATE|PASS
```

`FCLK_CLK0` is back to **62 pins**, the pre-integration number; no `pl_fe_top` cell, no
interconnect, no address segment survives; `validate_bd_design` reports **0 ERROR messages**.
The saved `.bd`'s hash is no longer the backup's — Vivado re-serialises on save — so the
restore is verified by **reading the state back**, which is the stronger check anyway.

**Not re-run:** a full rebuild of the restored design. The state is the pre-integration
configuration on every check that can be read from it (same cells, same parameters, same
clock net, 0 errors) and the 2026-10-24 build was produced from exactly that state; but no
build was made after the restore, and that should be the first action of the next session
before anything is flashed.

## 6. The station

**Its bitstream was never touched.** No `fpga -f` was issued in this session; the only board
operations were `rst -cores` + `dow` of bare-metal firmware. It still runs
`safe_bitstreams/BIT_20261024_fp1.bit` and firmware `TSC1 904A1527`, and the evidence that the
PL is alive is that the loop, the VDMAs and the display are all still running:

```
fwid_str  TSC1904A1527
ready=1  verdict PASS  exp_lock=8698  aec_mean=513  bg_state=0  st_code=2  part_ref=904
```

**But do not trust that PASS as a QC state:** `MB_ST_CODE = 2` is the boot self-test's
**background** check and `MB_BG_STATE = 0` says the background is not valid, and
`MB_PART_REF = 904` is not the 659 the brief quotes (a firmware-only reload moves it; only
`ref_take()` writes it). The operator step — clear the belt, `MB_CMD=12`, a good board,
`MB_CMD=9` — is still outstanding.

## 7. What remains true, measured, and useful after this

* The block is **bit-exact** (46,800 of 46,800) and the **AXI transport is bit-exact** (all
  464 words of a small-frame pass, byte-equal, at 1 px/clk).
* **The tear bracket is 88.0-100.5 ms** against the 18.43 ms the read needs — the timing
  assumption was never the problem.
* The front end plus its wrapper costs **LUT 2,711 / FF 1,577 / BRAM 0 / DSP 0**, measured.
* **The device is out of slices.** That is the answer, and it is a number, not an opinion.
