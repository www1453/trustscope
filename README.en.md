# TrustScope — a trustworthy-imaging QC system for flat workpieces

## 1. What this is

TrustScope is a stop-band incoming-inspection station: two OV5640 sensors feed a Zynq-7020
(XC7Z020, ALINX AX7020), capture runs at 1280x720; the three-state verdict runs on the bare-metal
PS on board, and the corner-coverage channel for missing corners runs on the workstation host
(two-channel design, report §2.3). The system answers one question, whether the board can be
judged at all, and returns three states: **OK**, **NG**, and **cannot judge**; what it cannot
judge it refuses, never counting it as a pass. The verdict path is auditable: a 160x90 grid,
8x8 px = 0.4 mm per cell, NG when the cell-mean difference exceeds 30 grey levels and the largest
8-connected group covers at least 8 cells. Field results for the whole 111-board work order are
in the next section.

## 2. Measured results

The block below is the measured-results text, frozen verbatim (per-board run 2026-11-01,
continuous run 2026-11-02 night to 11-03 morning). It is computed from the data committed under
`data/`; the commands that recompute it are in §3.2.

Field results (whole work order, 111 boards = B001-B100 + C101-C111, 2026-11-01 evening):
capability-internal detection **72.7%** (40/55 — contamination 18/25, bent 10/15, corner chips 12/15);
main-run anchor, batch 1-5 single session **75.0%** (36/48); good-board false alarms in two labelled
scopes — single run, production scope **15.0%** (6/40), and re-test adjudicated **8.8%** (3/34; 3/40 =
7.5% of all boards); fine scratches **0%** (0/16, a known capability boundary stated in the report).
Continuous run: 10.20 h, 12,626 samples, 99.7% OK (12,594), 0 NG, 32 refusals (0.3%, all inside the
first 30 min — a start-up transient), 1 restart (cause not located; verdicts consistent after).

The report states three limits explicitly: fine scratches pass by design, the CNN is implemented
but not in the verdict path, and hole/notch inspection is not implemented.

## 3. Reproducing the numbers (two legs)

### 3.1 Toolchain leg: Vivado / Vitis 2023.1

**AMD Vivado / Vitis 2023.1** — used for both the hardware design and the bare-metal PS project
(the competition requires the version to be stated). Part **XC7Z020 (ALINX AX7020)**; the 10-24
shipping build ran FCLK_CLK0 at 50.000 MHz with WNS +0.908 ns / TNS 0 / WHS +0.037 ns and
0 of 140,009 endpoints failing.

- **Pin constraints**: [`src/two_fft.xdc`](src/two_fft.xdc). The 16 second-camera pins are mapped
  one-for-one against the vendor `an5642.xdc` and the LCD pins against `lcd_test.xdc`; check that
  table before touching a pin number.
- **PS bare-metal**: [`src/main.c`](src/main.c) (camera, I2C, MMU + D-cache, display, verdict
  loop); the firmware stamp is generated from 13 source files, see [`src/build_id.h`](src/build_id.h).
- **Conveyor firmware**: [`src/stm32_conveyor_main.c`](src/stm32_conveyor_main.c).
- **HLS CNN and build**: [`src/hls/`](src/hls/) (CNN kernel, same-source testbench, HLS driver;
  **not in the verdict path**) and [`src/build/`](src/build/) (Block Design integration, build and
  XSA export Tcl; **no bitstream**).
- **Build and board steps**: this repository carries source, constraints and build Tcl only — no
  Vivado project, no bitstream, no board scripts. The module list, resources and timing are in report
  §2.3–§2.4 and §6.2; the board sequence (xsdb scripts, register blocks) is recorded in the "上板"
  section of [`docs/HISTORY_20261021.md`](docs/HISTORY_20261021.md) — those `ps_fft_dual/` and
  `ps_ui/` paths come from the 10-21 working tree, are not in this repository, and are kept as a
  record rather than as runnable commands.

### 3.2 Data leg: three commands

Run from the repository root; the input is the measured CSV committed under `data/`, no board
needed. Python 3.11+, standard library only (the figure script
`tools/make_report_figures_20261103.py` additionally needs `matplotlib`).

```powershell
python tools/recompute_field_20261103.py     # per-class detection and false-alarm rates
python tools/threshold_sweep_20261103.py     # the limit 4-10 operating-point curve
python tools/soak_20261101.py --report       # the 10.20 h continuous run
```

What each prints (all of it recomputes to section 2):

- `recompute_field_20261103.py` -> `IN-SCOPE DETECTION (adjudicated, all batches) : 40/55 = 72.7%`;
  `main-run-only anchor (batch1-5, one session) : 36/48 = 75.0%`;
  `false-alarm : 3/34 = 8.8% (judgeable) | 3/40 = 7.5% (all)`;
  `main run : NG 6 / UNSTABLE 3 / CANNOT 1 / OK 30` (i.e. the single-run production scope,
  6/40 = 15.0%); per class `pollution 18/25 = 72.0%`, `bent 10/15 = 66.7%`,
  `corner 12/15 = 80.0%`, `scratch 0/16 = 0.0%`; last line
  `ledger total: 111 boards = g40 + c25 + b15 + s16 + k15`.
- `threshold_sweep_20261103.py` -> the header `t | good FA | pollution | bent | scratch | in-scope det`
  plus 7 rows (t=4..10). Row t=8: good-board false alarms `6/36 = 16.7%`, in-scope detection
  `36/48 = 75.0%`; row t=4: `42/48 = 87.5%` detection against `14/36 = 38.9%` false alarms;
  it closes with `corner channel (independent): 12/15 = 80.0%`.
- `soak_20261101.py --report` -> `rows : 12626`, `duration : 10.20 h  (36725.7 s)`,
  `mean sampling period: 2.9 s`, `OK 12594 (99.7 %)`, `NG 0 (0.0 %)`, `CANNOT 32 (0.3 %)`,
  and one restart (the line the script prints for it is `重启 (frame counter decreased) : 1`,
  i.e. the frame counter decreased once).

## 4. Where to look

- **The full report**: [`report/trustscope_report.pdf`](report/trustscope_report.pdf) (26 pages; the
  `.docx` of the same name is the editable copy).
- **The dated engineering record**: [`docs/`](docs/) (246 files, ordered by date in the
  filename). Read the three-rate table at the top of
  [`docs/HISTORY_20261021.md`](docs/HISTORY_20261021.md) first — 18.0 fps / 8.7-10.3 fps / about
  1.6 per second are not the same quantity.
- **Data and figures**: [`data/`](data/) (measured CSV, field results), [`figures/`](figures/)
  (report figures).
- **Skill package and checks**: [`skill/`](skill/).
- **Directory map (selection guide 3.3.5.4)**: [`docs/DIRECTORY_MAP_20261103.md`](docs/DIRECTORY_MAP_20261103.md).
- **中文版**: [`README.md`](README.md).
