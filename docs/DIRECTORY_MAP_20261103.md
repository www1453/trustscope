# 目录对照（选题指南 3.3.5.4）

本仓库是本作品的可交付裁剪集：只保留源码、引脚约束、实测数据、工程记录、技能包与报告。
选题指南给的推荐结构非强制，但要求采用其他组织方式的队伍给出目录对照说明；本文件就是这份
说明（`README.md` §4 保留一行指引）。

## 本仓库实际结构

```text
trustscope/
├── README.md                     <- 中文主文件（四个区块）
├── README.en.md                  <- 英文对照（同四个区块、同数、同标签）
├── LICENSE                       <- MIT
├── works_report_20261103d.pdf    <- 完整设计报告（25 页）
├── works_report_20261103d.docx   <- 同上，可编辑稿
├── src/                          <- PS 裸机 main.c、传送带固件、two_fft.xdc、固件戳
├── data/                         <- 实测 CSV（逐板判定、连续运行）与现场结果
├── docs/                         <- 日期化工程记录（按文件名日期排序）
├── figures/                      <- 报告插图
├── skill/                        <- 技能包与检查脚本
└── tools/                        <- 可复算脚本（三条命令见 README §3.2）
```

## 与推荐结构的对照

| 选题指南推荐 | 本仓库位置 | 说明 |
|---|---|---|
| `README.md` | `README.md` | 中文主文件；英文对照为 `README.en.md` |
| `src/` | `src/` | PS 裸机 `main.c`、传送带固件 `stm32_conveyor_main.c`、引脚约束 `two_fft.xdc`、固件戳 `build_id.h` |
| `sim/` | 未随本仓库分发 | HLS 的 C 仿真工程留在工作树；PL 模块清单见报告 §2.4 |
| `build/` | 未随本仓库分发 | 构建是 Tcl 脚本且依赖 Vivado 工程与厂商 IP；模块与资源/时序见报告 §2.3–§2.4、§6.2 |
| `board/` | `docs/`、`data/` | 上板过程与寄存器块记录在 `docs/HISTORY_20261021.md` 的「上板」一节；板测数据在 `data/` |
| `data/` | `data/` | 逐板判定 CSV、连续运行 CSV、现场结果 |
| `skill/` | `skill/` | 技能包（含 `skill/README.md`） |
| `report/` | 根目录 PDF/DOCX + `docs/` | 报告以 PDF 交付；工程记录按日期放 `docs/` |

## 未随本仓库分发的内容

- `ps_fft_dual/`、`ps_ui/`、`app/`、`dl/`、`submission/` 是 10-21 至 11-03 的工作树目录，
  不在本仓库内。文档里出现这些路径时按记录原样保留，**不作为本仓库的可执行命令**。
- `ps_fft_dual/vendor/` 下是 ALINX 的板卡教程与相机规格书（**三方版权**），不纳入分发；
  厂商 IP `alinx_ov5640` 同样不在本仓库，复现时向 ALINX 官方获取。
- 比特流与 Vivado 生成物按 `.gitignore` 排除（`*.bit`、`*.dcp`、`*.runs` 等），
  它们是可重建的中间产物；重建步骤见报告 §2.3–§2.4。
