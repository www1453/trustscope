# TrustScope

## 1. 这是什么

TrustScope 是一台停带式来料检验工位：双 OV5640 经 PL 采集 1280×720 画面，全部判定在
Zynq-7020（XC7Z020，ALINX AX7020）的裸机 PS 上完成，不依赖上位机。它只回答一个问题——
这块板能不能判：输出 **OK / NG / 无法判定** 三态，判不了的一律判“无法判定”，绝不计为合格。
判定路径可审计：160×90 格逐格比对，每格 8×8 px = 0.4 mm/格，格均值差 > 30 灰且最大
8 连通组 ≥ 8 格判 NG。整张作业单 111 块板的实测结果见下一节。

## 2. 实测指标

以下为现场实测指标块原文（逐板 2026-11-01、连续运行 2026-11-02 夜→11-03 晨），**冻结不改写**；
它由 `data/` 里随仓库提交的数据算出，复算命令见 §3.2。

Field results (whole work order, 111 boards = B001-B100 + C101-C111, 2026-11-01 evening):
capability-internal detection **72.7%** (40/55 — contamination 18/25, bent 10/15, corner chips 12/15);
main-run anchor, batch 1-5 single session **75.0%** (36/48); good-board false alarms in two labelled
scopes — single run, production scope **15.0%** (6/40), and re-test adjudicated **8.8%** (3/34; 3/40 =
7.5% of all boards); fine scratches **0%** (0/16, a known capability boundary stated in the report).
Continuous run: 10.20 h, 12,626 samples, 99.7% OK (12,594), 0 NG, 32 refusals (0.3%, all inside the
first 30 min — a start-up transient), 1 restart (cause not located; verdicts consistent after).

The report states three limits explicitly: fine scratches pass by design, the CNN is implemented
but not in the verdict path, and hole/notch inspection is not implemented.

## 3. 复现（两条腿）

### 3.1 工具链腿：Vivado / Vitis 2023.1

**AMD Vivado / Vitis 2023.1** —— 硬件设计与 PS 裸机工程都用这个版本（本竞赛要求写明版本）。
器件 **XC7Z020（ALINX AX7020）**；10-24 出货构建 FCLK_CLK0 50.000 MHz，
WNS +0.908 ns / TNS 0 / WHS +0.037 ns，未满足约束的端点 0/140,009。

- **引脚约束**：[`src/two_fft.xdc`](src/two_fft.xdc)。16 条第二路相机引脚逐脚对照厂商 `an5642.xdc`，
  LCD 引脚对照厂商 `lcd_test.xdc`；改引脚号之前先对该表。
- **PS 裸机程序**：[`src/main.c`](src/main.c)（相机、I2C、MMU + D-cache、显示、判定主循环）；
  固件戳由 13 个源文件生成，见 [`src/build_id.h`](src/build_id.h)。
- **传送带侧固件**：[`src/stm32_conveyor_main.c`](src/stm32_conveyor_main.c)。
- **构建与上板**：本仓库只带源码与约束，**不带 Vivado 工程、比特流、上板脚本**。从零构建的
  模块清单、资源与时序见报告 §2.3–§2.4 与 §6.2；上板的脚本序列与寄存器块记录在
  [`docs/HISTORY_20261021.md`](docs/HISTORY_20261021.md) 的“上板”一节——那里的 `ps_fft_dual/`、
  `ps_ui/` 路径取自 10-21 工作树，本仓库不含这两个目录，按记录原样保留，不作为本仓库的命令。

### 3.2 数据腿：三条命令

在仓库根目录执行；输入是 `data/` 里随仓库提交的实测 CSV，**不需要板子**。
Python 3.11+，只用标准库（画报告插图的 `tools/make_report_figures_20261103.py` 另需 `matplotlib`）。

```powershell
python tools/recompute_field_20261103.py     # 逐类检出率与误报率
python tools/threshold_sweep_20261103.py     # 限值 4-10 的工作点曲线
python tools/soak_20261101.py --report       # 10.20 h 连续运行的可靠性四项
```

各自打印什么（都能复算回第 2 节）：

- `recompute_field_20261103.py` → `IN-SCOPE DETECTION (adjudicated, all batches) : 40/55 = 72.7%`；
  `main-run-only anchor (batch1-5, one session) : 36/48 = 75.0%`；
  `false-alarm : 3/34 = 8.8% (judgeable) | 3/40 = 7.5% (all)`；
  `main run : NG 6 / UNSTABLE 3 / CANNOT 1 / OK 30`（即单次现场口径 6/40 = 15.0%）；
  逐类 `pollution 18/25 = 72.0%`、`bent 10/15 = 66.7%`、`corner 12/15 = 80.0%`、
  `scratch 0/16 = 0.0%%`（双 `%` 是脚本里的笔误，数值是 0/16）；末行
  `ledger total: 111 boards = g40 + c25 + b15 + s16 + k15`。
- `threshold_sweep_20261103.py` → 表头 `t | good FA | pollution | bent | scratch | in-scope det`
  加 7 行（t=4…10）。t=8 行：良品误报 `6/36 = 16.7%`、能力内检出 `36/48 = 75.0%`；
  t=4 行：检出 `42/48 = 87.5%` 对误报 `14/36 = 38.9%`；收尾 `corner channel (independent): 12/15 = 80.0%`。
- `soak_20261101.py --report` → `rows : 12626`、`duration : 10.20 h  (36725.7 s)`、
  `mean sampling period: 2.9 s`、`OK 12594 (99.7 %)`、`NG 0 (0.0 %)`、`CANNOT 32 (0.3 %)`、
  `重启 (frame counter decreased) : 1`（帧计数下降 1 次）。

## 4. 导航

- **完整设计报告**：[`works_report_20261103d.pdf`](works_report_20261103d.pdf)（25 页；同名 `.docx` 为可编辑稿）。
- **日期化工程记录**：[`docs/`](docs/)（246 个文件，按文件名日期排序）。先读
  [`docs/HISTORY_20261021.md`](docs/HISTORY_20261021.md) 顶部的三速率表——18.0 fps / 8.7–10.3 fps /
  约 1.6 次/秒不是同一个量。
- **数据与图**：[`data/`](data/)（实测 CSV、现场结果）、[`figures/`](figures/)（报告插图）。
- **技能包与检查脚本**：[`skill/`](skill/)。
- **目录对照（选题指南 3.3.5.4）**：[`docs/DIRECTORY_MAP_20261103.md`](docs/DIRECTORY_MAP_20261103.md)。
- **English version**：[`README.en.md`](README.en.md)。
