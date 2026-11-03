# Why every AXI-master write was rejected: the TrustZone controller, not the block

**Date:** 2026-10-28 (evening, after `dl/ATTEMPT2_20261028.md`)
**Question:** every write response from `pl_fe_top` came back non-OKAY on silicon, the
statistics buffer at `0x12AC0000` never changed, `STATUS.err` was set and `done` never
asserted, while the read side appeared to complete with `VALUES = 46,800`.
**Answer:** the block is correct. The Zynq-7000 TrustZone controller was refusing **every**
transaction from the front end, reads included, because the front end drives `AxPROT[1] = 1`
(non-secure) and on this station every DDR byte is secure. **One register write fixes it, and
it has been verified end-to-end, including in firmware with no host assistance.**

**Evidence grade of the main claim: E3 for the fix** — one command (`xsdb
dl/plfe_tz2_20261028.tcl`) reproduces "writes land, done=1, err=0" and one
(`xsdb dl/plfe_fwuse_20261028.tcl`) reproduces "the PS consumes 92 PL passes with the
firmware's own TZ setting". E2 for the A/B result: `cam` −9.84 ms against an A/A resolution
limit of 0.95 ms.

---

## 0. The station, and what was already ruled out

The attempt bitstream (ILAs removed, front end in) was loaded, firmware `TSC1EAA4676C`,
`MB_PLFE_ON = 0`, capture live. Already refuted before this session (from
`dl/ATTEMPT2_20261028.md`): a missing bitstream, the wrong slave address, burst geometry,
the AXI attribute *encodings* being illegal, and the master address space being unmapped in
the block design.

Everything below is a read of the running station or a simulation. No rebuild was performed;
the bitstream on the board is the same file it was running at the start.

---

## 1. Hypothesis matrix, and what happened to each

| # | Hypothesis | If true we would see | Distinguishing experiment | Cost | Verdict |
|---|---|---|---|---|---|
| H1 | The write master is told the wrong base address, so it masters an address that decodes to nothing (DECERR) | `STATS` (0x1C) not `0x12AC0000` | read the control registers back on silicon | 2 min | **refuted**: `STORE0..3 = 0x10000000/0x10400000/0x10C00000/0x12000000`, `STATS = 0x12AC0000`, `CTRL.EN = 1` |
| H2 | The HP2 aperture does not cover the buffer, or `S_AXI_HP2` is not what the master reaches | a segment whose range excludes `0x12AC0000`, or a different slave | read the built hardware handoff, not the memory | 2 min | **refuted**: `HP2_DDR_LOWOCM` = 1 GB at `0x00000000` (`§3`) |
| H3 | The AXI4→AXI3 protocol converter is mis-configured | wrong `SI/MI_PROTOCOL`, wrong translation mode | read the IP's own `.xci` and the IP definition | 5 min | **refuted**: `SI_PROTOCOL=AXI4`, `MI_PROTOCOL=AXI3`, `TRANSLATION_MODE=2` ("incompatible bursts split"), 64-bit, ID 0→6 |
| H4 | The RTL write master violates AXI4 in a corner the always-OKAY testbench never exercised | a strict checker / backpressure run rejects something | new testbench with a strict checker, LFSR backpressure and fault injection | 45 min | **refuted**: 0 violations (§4) |
| H5 | **The TrustZone controller refuses non-secure PL accesses** | `TZ_DDR_RAM` secure, `TZ_FPGA_M` checking enabled, and fixing it makes the writes land | read the TZ registers with known-answer controls, then change one and re-run a pass | 10 min | **CONFIRMED** (§2) |

---

## 2. The cause

### 2.1 The two signals

`pl_fe_rd.v:102` and `pl_fe_wr.v:89`:

```verilog
assign m_arprot = 3'b010;   // non-privileged, NON-SECURE, data
assign m_awprot = 3'b010;   // same
```

`AxPROT[1] = 1` means **non-secure**. On Zynq-7000 the TrustZone controller decides from
exactly that bit whether a master may reach DDR.

### 2.2 The two registers, measured (not remembered)

```
ARM_PLL_CFG  (0xF8000110) = 0x000FA220   <- the value ps7_init itself wrote  (control)
LVL_SHFTR_EN (0xF8000900) = 0x0000000F   <- the value ps7_post_config wrote  (control)
SCL          (0xF8000000) = 0x00000000   <- secure configuration NOT locked
TZ_DDR_RAM   (0xF8000430) = 0x00000000   <- every DDR region SECURE
TZ_FPGA_M    (0xF8000484) = 0x00000000   <- TrustZone checking ENABLED for the PL ports
```

The two controls are what make the four TZ readings facts: both are values the frozen
`ps7_init` wrote, read back exactly, on the same read path.

**Addresses are from Xilinx, not from memory.** `TZ_DDR_RAM` is at SLCR + `0x430`, not
`0x440`; the definitions come from
`D:/vitis/Vitis/2023.1/data/embeddedsw/lib/sw_apps/zynq_dram_test/src/testDefines.h`
(SLCR base `0xF8000000`, `TZ_DDR_RAM 0x430`, `TZ_FPGA_M 0x484`, `TZ_FPGA_AFI 0x488`).
An earlier probe of mine read `0xF8000440` and called it `TZ_DDR_RAM`; that address is
`TZ_DMA_NS`, the DMA controller's register, and the reading was withdrawn (§7).

### 2.3 Why no FSBL is the missing link

`ps7_init` does not touch the TZ registers at all (checked: the frozen
`ps7_dual/GOOD_20261003_cdcfix/ps7_init_cdcfix_50m.tcl` has no `0xF80004xx` write). The
FSBL is what normally opens DDR up before the application runs. **This station is brought up
over JTAG — `ps7_init`, `ps7_post_config`, `dow`, `con` — so no FSBL ever runs**, and both
TZ registers sit at their reset values. `TZ_DDR_RAM` resets to secure; `TZ_FPGA_M` resets to
"check the PL ports".

### 2.4 Why nothing else in the design noticed

Every other PL master in the block design is a vendor IP whose `AxPROT` is tied to `000`
(secure). The AXI VDMA does not even bring the port out — its netlist line is
`.m_axi_s2mm_awprot(NLW_U0_m_axi_s2mm_awprot_UNCONNECTED[2:0])`. **The front end is the only
master in this design that actively declares non-secure**, which is why the capture, the
display and the CNN were untouched.

### 2.5 The test that closed it

With `TZ_DDR_RAM = 0xFFFFFFFF`, one host-triggered pass
(`dl/plfe_tz2_20261028.tcl`):

```
PASS|STATUS=0xB7010001|VALUES=0x0000B6D0|ERRS_DELTA=0
BUF_AFTER|topzero=64/64|first4=[12, 267, 520, 776]|changed_of_64=64
VERDICT|CONFIRMED
```

`STATUS = 0xB7010001` → `done = 1`, **`err = 0`**, `seq_echo` = the seq written. `VALUES =
46,800`. **Zero** new error responses. All 64 buffer words replaced, and every one has
`bits[31:24] == 0`, which is the front end's statistics-word encoding
(`{8'h00, array[2], index[14], value[8]}`) and cannot be produced by uninitialised DDR
(p ≈ 1/256 per word).

The surgical version, `TZ_DDR_RAM = 0x00000010` (bit 4 = the 64 MB region
`0x10000000–0x13FFFFFF`, which holds all four capture stores **and** the statistics buffer),
is enough — and the PS then consumed **7 PL passes in 3 s** with `VALUES = 46,800` and
`STATUS = 0x117F0001` (done=1, err=0).

---

## 3. The HP2 aperture, read from the hardware handoff

Not from memory, and not from the `.bd`: the built `design_1.hwh` (timestamp
`Wed Oct 28 19:09:26 2026`, i.e. the design that is in the bitstream) contains

```
<MEMRANGE ADDRESSBLOCK="HP2_DDR_LOWOCM" BASEVALUE="0x00000000" HIGHVALUE="0x3FFFFFFF"
          INSTANCE="processing_system7_0" MASTERBUSINTERFACE="m_axi"
          SLAVEBUSINTERFACE="S_AXI_HP2"/>
```

`pl_fe_top_0`'s `m_axi` reaches `S_AXI_HP2` over **1 GB at `0x00000000–0x3FFFFFFF`**.
`0x12AC0000` (the statistics buffer) and all four stores (`0x10000000`, `0x10400000`,
`0x10C00000`, `0x12000000`) are inside it, so no address the front end uses can DECERR from
the aperture. The `.xci` confirms `S_AXI_HP2` is AXI3, 64-bit data, 6-bit ID, 50 MHz, and
`PCW_USE_S_AXI_HP2 = 1`. **This was the last unread configuration item, and it is clean.**

---

## 4. The strict-slave simulation

`tb_pl_fe_top.v` drives `AWREADY`/`WREADY`/`ARREADY` high for the whole run and only ever
answers OKAY, which is exactly why the simulation was clean while the silicon was not.

`dl/pl_frontend/tb_pl_fe_master.v` (new) drives `pl_fe_wr` and `pl_fe_rd` directly and
replaces that with:

* a protocol checker: payload stability while `VALID && !READY` on AW, W and AR; AWSIZE /
  ARSIZE, AWBURST / ARBURST, 8-byte alignment, no 4 KB crossing, `ARLEN <= 15`; and the
  global equalities `W beats == Σ(AWLEN+1)` and `WLAST count == AW count`;
* **real backpressure** from a deterministic LFSR on `AWREADY`/`WREADY`/`ARREADY`/`RVALID`;
* **fault injection**: every BRESP SLVERR, or every RRESP SLVERR.

```
W1 clean write, backpressure on      values=64 errs=0 err=0 badresp=0
W2 every write response is SLVERR    values=32 errs=4 err=1 badresp=4
R1 clean read, backpressure on       err=0 errs=0 r_beats=48/48 pixels=128/128
R2 every read response is SLVERR     err=1 errs=48 r_beats=48 badresp=48 pixels=128/128
R2 TRAP CONFIRMED: all 128 pixels emitted with every RRESP=SLVERR
WSUM aw_count=10 w_beats=48 wlast_count=10 sum_len1=48 w_before_aw=0
STRICT_CHECKER_VIOLATIONS 0
STRICT_DONE
```

**Result: the master's AXI4 behaviour is legal under backpressure — 0 violations.** So H4 is
refuted, and the simulation says the protocol was never the problem.

**And R2 reproduces the trap in simulation.** With every read response an error, the read
master still emits all 128 pixels and `pl_fe_rd`'s `errs` counts 48. In the 1280×720 build
that becomes `VALUES = 46,800` — which is exactly what the silicon showed while every read
was being refused. Two checker artifacts were found and corrected on the way (a registered
AW queue that misfired when AW and the first W beat landed in the same cycle, then a
one-deep `have_aw` flag); neither was a DUT bug, and both are documented in the file so the
next person does not re-add them.

*(`w_before_aw = 0` in this run: the master is **allowed** to present W before AW, and an
always-ready slave could never have shown it either way; the checker deliberately does not
fail on it.)*

---

## 5. The error count was diagnostic, and it was available before any rebuild

Five isolated host-triggered passes (`dl/plfe_onepass_20261028.tcl`), with `MB_PLFE_ON = 0`
so the only pass in each window is the one written by the script:

```
ERR_DELTA = 15748, 15748, 15750, 15750, 15750      mean 15,749   spread ±2
```

That number is the burst count, not the beat count, and it pins the burst length:

* 46,800 words / 2 per 64-bit beat = **23,400 W beats per pass**;
* if bursts were the designed 8 beats, a pass would be 2,925 bursts;
* if every beat errored, the count would be 23,400; if every word, 46,800;
* the producer emits one word per ~19.7 clocks (46,800 words in 921,600 clocks), so the
  32-word write FIFO never fills and a burst is 1–2 beats — **≈15,700 bursts per pass**,
  which is exactly what the count says.

So: **one non-OKAY response per write burst, 100 % of bursts, reproducible to ±2** — the
signature of a uniform policy refusal, not of a data-dependent protocol corner. That
arithmetic, and the "writes never land while reads appear to" asymmetry, were both available
before any rebuild was spent.

---

## 6. The fix, and its verification

### 6.1 Where the fix belongs

A non-secure PL master is a property of this design, so the fix belongs in the firmware, not
in a measurement script. `ps_ui/main.c` now does this in `main_loop()`, before the loop:

```c
R32(0xF8000008u) = 0x0000DF0Du;   /* SLCR write unlock                     */
R32(0xF8000430u) = 0x00000010u;   /* TZ_DDR_RAM: bit 4 non-secure (64 MB)  */
R32(0xF8000004u) = 0x0000767Bu;   /* SLCR lock                             */
```

Bit 4 was chosen over `0xFFFFFFFF` so the rest of DDR stays secure; it covers
`0x10000000–0x13FFFFFF`, which is where both the capture stores and the statistics buffer
live. If the secure configuration is ever locked (`SCL = 1`, e.g. a real FSBL boot) the write
is ignored — correctly, because whoever booted the board has already dealt with it.

The RTL alternative — driving `AxPROT = 3'b000` — was rejected: it makes a PL master claim
secure accesses, which is the wrong direction for the security model. The PL *is* non-secure;
the DDR regions it needs must be marked accordingly.

### 6.2 Rebuild and verification

New firmware build: **`TSC1A829AA48`** (was `TSC1EAA4676C`).

```
FWID|TSC1A829AA48|IDENTITY|PASS
TZ|DDR_RAM(0xF8000430)=0x00000010|want=0x00000010|FPGA_M=0x00000000|SCL=0x00000000
TZ_FIX|PASS|the firmware itself opened 0x10000000-0x13FFFFFF to non-secure masters
```

Then, with **no host TZ write at all**, 46 s of `MB_PLFE_ON = 1`
(`dl/plfe_fwuse_20261028.tcl`):

```
used(578):  331(stale) -> 5 -> 12 -> 20 -> 25 -> 29 -> 36 -> 44 -> 49 -> 53
            -> 60 -> 68 -> 73 -> 77 -> 84 -> 92          <- 92 PL passes consumed
PL_STATUS = 0x01E20001   done=1, err=0
PL_VALUES = 46,800       MB_PLFE_VALS = 46,800
PL_ERRS   = 0x0004CE34   unchanged since before the reload
```

`MB_PLFE_USED` is incremented only inside `plfe_try_sample()`, after the PS has checked
`done`, the seq identity and `VALUES == 46,800` and read all 46,800 words, so 92 increments
is the whole chain working. `PL_ERRS` not moving at all is the independent check that no new
error responses are being generated.

**Note on the readout:** the first `used(578)` value (331) is a stale DDR word from the
previous boot; the firmware's own counter starts at 0 (BSS) and reached 92. The naive
`used_end - used_start` is therefore negative (−239) and the script's `VERDICT` line in that
file says `NOT-CONSUMED`; the sample series above is the correct reading and the verdict
string is wrong. The counter restarting is itself the proof that the image was reloaded.

### 6.3 The OCM footprint

The firmware links **into OCM** (`.text` at `0x00000000`, `entry 0x00000020`, `.bss` at
`0x00024000`, page table at `0x00020000–0x00024000`, image ends ≈`0x00034000`), i.e. it
occupies about 208 KB of the 256 KB OCM. That matters for the record: an OCM-based test of
the write master is not available, because a 187,200-byte statistics write starting at
`0xFFFF0000` would cross the top of the 4 GB map and wrap into DDR low — and it would
overwrite the running program on the way. This is why the substitute split below was chosen.

---

## 7. What the "BRAM split" was replaced with, and why that is not a dodge

The brief proposed one rebuild with an AXI BRAM slave to split "master" from "HP2/DDR path".
That rebuild was **not built**, for two measured reasons:

1. The write span is 187,200 bytes = 41 BRAM36, and the placed design has **31.5 free**.
   A partial BRAM window would have shown "some words land", which does not separate a
   protocol fault from an address fault.
2. The split was achieved without a rebuild at all: **the TZ registers are a switch on the
   receiving side of exactly the boundary the BRAM test was meant to probe.** `TZ_DDR_RAM =
   0x10` keeps the master, the protocol converter, the interconnect and the HP2 port
   *identical* and changes only whether the PS's TrustZone accepts the access. Writes landed.
   That is a cleaner split than a second slave: same master, same path, one bit different.

**What this does not establish.** The BRAM test would also have exercised a slave with
different response behaviour and different backpressure. That is now covered by simulation
(§4), not by silicon, and it is listed as unmeasured in §9.

---

## 8. The A/B/A, on `MB_T_CAM`, 12 windows per arm

Pre-registered in `dl/LOOP_MEASURE_20261028_step1.md` §6. Run with
`dl/measure_plfe_ab_tz_20261028.tcl tz1 12 EAA4676C` — a copy of the pre-registered script
with the TZ write added to the setup of **each arm** and restored at the end; the protocol
(statistic, fence, arm structure, window count, decision rule) is unchanged. Firmware
`TSC1EAA4676C` (the pre-fix image, so the arms differ only in `MB_PLFE_ON` and the TZ bit).

| phase (ms/loop) | A1 (PL on) | B (PL off) | A2 (PL on) | A/B | A/A |
|---|---|---|---|---|---|
| **cam (primary)** | **87.18** | **97.02** | **86.23** | **−9.84** | **+0.95** |
| sync | 51.33 | 48.52 | 55.56 | +2.81 | −4.23 |
| class | 75.09 | 77.18 | 81.93 | −2.08 | −6.84 |
| qual | 13.32 | 12.52 | 12.41 | +0.80 | +0.90 |
| panel | 1.04 | 1.14 | 1.07 | −0.10 | −0.03 |
| tail | 7.05 | 7.06 | 7.01 | −0.02 | +0.03 |
| pub | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| total | 235.01 | 243.44 | 244.22 | −8.43 | −9.20 |
| **control** (class+qual+panel+tail+pub) | 96.50 | 97.90 | 102.43 | **−1.40** | **−5.93** |

sd of `cam`: 3.26 / 4.85 / 4.13 ms. `MB_PLFE_USED` per arm: **+145 / 0 / +173** — the
treatment was actually applied in both A arms and never in B. 12/12/12 windows, 0 rejected,
loop-head residual within `[0, 100000]` on every window.

**Reading it against the pre-registered decision rule:**

* **`cam` dropped 9.84 ms and the control group did not move.** The control group's A/B
  difference (−1.40 ms) is well inside its own A/A resolution limit (−5.93 ms), so the run is
  valid and the drop is not common-mode drift.
* **The effect is 10.3× the A/A resolution limit** (0.95 ms) and 5.8σ (2se = 3.38 ms). This
  is not an inference from a standard deviation: the two identical arms differ by 0.95 ms
  while the treated arm differs from the untreated one by 9.84 ms.
* **Saving: 9.84 ms/loop, 10.1 % of the untreated `cam`.**
* **The loop total did not get faster.** Its A/B difference (−8.43 ms) is inside its own A/A
  control (−9.20 ms), so it is not resolvable at 12 windows — which the pre-registration
  predicted and pre-committed to reporting as **"the compute saving is real and the loop did
  not get faster"**, an absorbed saving, not a throughput gain. `sync` and `class` moved by
  more than their own resolution in the A/A comparison, so the absorbed time is in the
  pacing, not in the sampling pass.

**What may not be said:** that the station is faster. At 12 windows the total's resolution is
wider than the effect, exactly as pre-registered; a total claim needs 40 windows per arm.

---

## 9. The trap, named

> **A beat counter is not evidence that data arrived.** `pl_fe_rd` counted accepted R beats
> regardless of `RRESP`, so a pass in which every single read was refused still reported
> `VALUES = 46,800` — and that number was read as "the read works". Only the response codes
> said otherwise. The design *did* report the failure (`STATUS.err` was set, by `rd_err`),
> but the published count looked healthy, so the failure was attributed to the write side
> alone. Simulation reproduces it exactly: §4 R2 emits all 128 of 128 pixels with every
> RRESP = SLVERR.

This is the second time in this project an instrument that could not fail produced a healthy
number (the seven-valued `MB_PROGRESS` beacon counted as a loop rate was the first). Two
concrete rules follow, and they are in the casebook as **M57**:

1. An AXI slave's `RRESP`/`BRESP` must be **counted**, and the count must be **proved able to
   stop the pass** — `W2`/`R2` in `tb_pl_fe_master.v` are that proof, and they must exist
   before the count is trusted.
2. `pl_fe_rd.errs` is **left unconnected** in `pl_fe_top.v` (`.errs()`), so even the count was
   not readable for the read side. That is a real defect worth fixing even though the err
   flag did its job.

---

## 10. The sentence about the fallback

**The fallback path was designed for exactly this and worked**: `plfe_try_sample()` refused a
pass whose `STATUS.done` was 0 and ran the shipped 936,000-read PS pass unchanged, so for the
whole evening the station kept producing QC results while its front end was being refused on
every transaction — the block failed safe, it did not fail wrong.

---

## 11. Not verified, and what would verify it

| Item | State | What it needs |
|---|---|---|
| The **statistics are numerically correct** (not just present) | **not verified** — the A/B measured time, not values | an A/B against the PS pass on one frame (the pre-registered pipeline, 12 windows, then compare the verdict path); `done=1` proves the count and identity, not the arithmetic |
| Master + converter + HP2 against a **non-DDR slave** (the BRAM split) | **not built** (§7) | one rebuild with an AXI BRAM slave and a reduced write limit |
| **Backpressure** behaviour on silicon (`m_axi` under real stall) | **simulation only** (§4) | an ILA on `m_axi`, if it ever matters |
| Whether a real **FSBL/QSPI boot** leaves `TZ_DDR_RAM` open | **not tested** | a QSPI boot, then read `0xF8000430`; the firmware's own write makes it moot for the block, but the register value would document the boot path |
| `pl_fe_rd.errs` readback | **not connected in RTL** | one rebuild wiring it into a status register |
| `total` loop time on the PL path | **not resolvable at 12 windows** | ≥40 windows per arm (pre-registered) |
| Operator steps (pin exposure, empty belt, good board) | **not requested, deliberately** | only worth the operator's time now that the block works and before any verdict claim |

---

## 12. Files

| File | What it is |
|---|---|
| `dl/plfe_regs_20261028.tcl` | read-only register dump; proved the RW registers had never been written in that boot |
| `dl/plfe_pass_20261028.tcl` | controlled loop-driven pass: registers after `plfe_setup`, errors per loop |
| `dl/plfe_onepass_20261028.tcl` | five isolated host-triggered passes → 15,748…15,750 errors each |
| `dl/plfe_tz2_20261028.tcl` | **the decisive test**: correct TZ addresses, controls, write `TZ_DDR_RAM`, one pass, buffer diff, restore |
| `dl/plfe_e2e_20261028.tcl` | the surgical bit 4 alone, and `MB_PLFE_USED` advancing |
| `dl/plfe_fwfix_20261028.tcl` | loads `TSC1A829AA48` and proves the firmware sets the TZ bit itself |
| `dl/plfe_fwuse_20261028.tcl` | 46 s on the new firmware: 92 PL passes consumed, `PL_ERRS` frozen |
| `dl/measure_plfe_ab_tz_20261028.tcl` | the A/B/A with the TZ setup per arm; log `dl/measure_plfe_ab_tz1.log` |
| `dl/pl_frontend/tb_pl_fe_master.v` | the strict slave, backpressure and fault injection; log `dl/pl_frontend/sim_master/strict_run.log` |
| `ps_ui/main.c` | the fix (3 register writes in `main_loop()`), build `TSC1A829AA48` |
| `skill/pitfalls/measurement-traps.md` | new entry **M57** |
