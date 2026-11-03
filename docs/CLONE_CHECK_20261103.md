# 克隆校验（2026-11-03）

推送 `0160169`（README 重排）后，用全新浅克隆重读主文件，确认远端渲染的就是四个区块的版本。

- `git clone --depth 1 https://github.com/www1453/trustscope.git clone_check` → 成功
- `git -C clone_check log --oneline -1` → `0160169 README: four blocks only; the 10-21 experiment record moves to docs/`
- `git ls-remote origin main` → `0160169793d7893b846fbbd81eb2751d12e0fe7e refs/heads/main`
- 克隆里的 `README.md`：81 行；四个区块齐全（`## 1. 这是什么` … `## 4. 导航`），
  第 16–25 行是逐字未动的指标块（873 字节，sha256 前 16 位 `9d4b8e76688aa64d`）
- 克隆里跑三条命令：`recompute_field_20261103.py` exit 0、`threshold_sweep_20261103.py` exit 0、
  `soak_20261101.py --report` exit 0，输出与冻结块一致
  （72.7% / 75.0% / 8.8% / 15.0% / 10.20 h / 12,626）

## 克隆到的 `README.md` 前 40 行（原样粘贴，行尾 CRLF 已按 LF 排版）

```text
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
```

> 说明：这台机器 `core.autocrlf=true`，所以克隆出的文件是 CRLF 行尾；内容与仓库里的 LF 版本一致。
