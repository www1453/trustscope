# TrustScope

Zynq-7020（ALINX AX7020）可信成像检测系统的全部工程文件。

**TrustScope decides whether a frame is usable before judging the board.** A dual-camera AOI
station on a Zynq-7020 (XC7Z020), bare-metal PS, no operating system. The verdict has three states
— `OK`, `NG`, and **"cannot judge"** — and the system refuses rather than guessing a pass.

Field results (whole work order, 111 boards = B001-B100 + C101-C111, 2026-11-01 evening):
capability-internal detection **72.7%** (40/55 — contamination 18/25, bent 10/15, corner chips 12/15);
main-run anchor, batch 1-5 single session **75.0%** (36/48); good-board false alarms in two labelled
scopes — single run, production scope **15.0%** (6/40), and re-test adjudicated **8.8%** (3/34; 3/40 =
7.5% of all boards); fine scratches **0%** (0/16, a known capability boundary stated in the report).
Continuous run: 10.20 h, 12,626 samples, 99.7% OK (12,594), 0 NG, 32 refusals (0.3%, all inside the
first 30 min — a start-up transient), 1 restart (cause not located; verdicts consistent after).

The report states three limits explicitly: fine scratches pass by design, the CNN is implemented
but not in the verdict path, and hole/notch inspection is not implemented.


## How to reproduce the numbers

Every figure in this repository is recomputable from the data committed with it:

```powershell
python tools/recompute_field_20261103.py     # per-class detection and false-alarm rates
python tools/threshold_sweep_20261103.py     # the limit 4-10 operating-point curve
python tools/soak_20261101.py --report       # the 10.20 h continuous run
```

**Toolchain:** AMD Vivado / Vitis **2023.1** (hardware design and the bare-metal PS project),
with the design targeting **XC7Z020 (ALINX AX7020)**. Python 3.11+ with `matplotlib` for the
figures; the JTAG tools call `xsdb` from the same 2023.1 installation.

**Where to look first:** the full design report is `works_report_20261103d.pdf` (25 pages);
the dated engineering record is in `docs/` (242 files, ordered by date in the filename).

```
trustscope/
├── README.md              <- 本文件（含赛题 3.3.5.4 要求的目录对照说明）
├── .gitignore             <- 排除抓帧、构建产物与三方厂商材料
├── app/                   <- PC 侧判定引擎与实验脚本（Python）
├── ps_ui/                 <- PS 侧裸机 C 源码（相机、I2C、MMU、显示、判定）
├── ps_fft_dual/           <- 板级工程：Vivado Tcl 脚本、XDC 约束、相机表、上板脚本
├── dl/                    <- 算法与文档：HLS 源码、金标准、文献、实测记录
├── skill/                 <- 技能包提交物
└── submission/            <- 竞赛提交材料
```

## 与赛题推荐目录结构的对照（选题指南 3.3.5.4）

赛题给的推荐结构**非强制**，但要求采用其他组织方式的队伍**在本文件中给出目录对照说明**。
对照如下：

| 赛题推荐 | 本仓库对应位置 | 说明 |
|---|---|---|
| `README.md` | `README.md` | 本文件 |
| `src/` | `ps_ui/`（PS 裸机 C）、`dl/hls/`（HLS 源码）、`app/`（PC 侧 Python） | 三种实现方式分开放置 |
| `sim/` | `dl/hls/hls_proj/` | HLS 的 C 仿真与综合工程 |
| `build/` | `ps_fft_dual/`（构建 Tcl）、`ps_fft_dual/logs/`（综合与实现报告） | 构建全为 Tcl 脚本，可从零复现 |
| `board/` | `ps_fft_dual/*.tcl`（上板脚本）、`ps_fft_dual/GOOD_*/`（已验证比特流快照） | 含实测输出与参考比对 |
| `data/` | `dl/data/`、`app/data/` | 测试数据、金标准、参考结果 |
| `skill/` | `skill/` | 技能包（含 `README.md`） |
| `report/` | `dl/*.md`（设计报告与实测记录）、`dl/lit/`（文献） | 报告素材就地保留 |

> **三方材料说明**：`ps_fft_dual/vendor/` 下是 ALINX 的板卡教程与相机规格书（**三方版权**），
> **不纳入本仓库分发**，需要者请向 ALINX 官方获取。厂商 IP `alinx_ov5640` 同样不在本仓库内，
> 复现步骤中说明了它的获取方式。

## 当前状态（2026-10-21）

板端可运行基线 = git `688c0f3`，下列读数全部取自断电重启后的**单次引导**（脚本
`ps_fft_dual/measure_fps.tcl` 数帧、`ps_fft_dual/phases.tcl` 读相位和）：

- **1280×720 双路、18.0 fps**，循环 55.6 ms。**融合关闭时 sync = 0.0 ms；融合开启时 8.0 fps、sync 69.6 ms**
  —— 融合的全部代价落在“每帧等多一次交接”上，其余相位两行相差不到 0.3 ms。
- **曝光 3000 行 + 增益 0x40** 已固化进固件（`ps_ui/cam_i2c.c` 的 `cam_set_gain_bus()`）。
  普通室内照明即可出图，**不再需要暗箱**（强光直射未测）。
- 画面：平均亮度 47–50、|dL/dx| = 2.17；在同一工作距离重新对焦后 3.03。
  同口径的历史最好记录是 2026-10-18 的 1.33。
- **5 MP（2592×1944）判定不可行**：14 项逐一实测排除 + ILA 直接证据，
  见 `submission/report/technical_report.docx` 第十一章。2592×1080 能采满，
  但镜头解析力只到约 1280 宽，多出来的像素不带来细节。

（以下为 2026-10-03 会话记录，保留以溯源）

**已解决**
- **PS 渲染帧率 2.87 → 19.60 fps（6.8×）**：打开 MMU + D-cache。
  先测清楚才动手 —— `L2C-310` 的 `Control = 0x00000000` 说明**L2 是关的**，
  所以只有 L1，`DCIMVAC`/`DCCMVAC` 就够（L2 开着的话还得额外编程 L2C-310）。
  一致性义务：采集帧存**读前作废**（否则画面冻住）、显示帧存**翻转前写回**（否则显示上一帧）、
  **mailbox 映射为不可缓存**（主机经 JTAG 写，缓存维护对它无效）。实现在 `ps_ui/mmu.c`。
- **时序违规清零**：那 9 条 `clk_fpga_1 -> clk_fpga_0` 违规**全部终止于调试捕获 RAM 的探针输入**，
  不是功能跨域路径（唯一非探针的那条在 `v_tc_0` 内部且满足时序）。
  所以**没有**用 `set_clock_groups -asynchronous`（那会连带丢掉 42 条真实且满足时序的路径），
  而是只对探针加精确的 `set_false_path`。重综合后 **violated paths: 0**。
  新比特流 `ps_fft_dual/design_1_wrapper_cdcfix_50m.bit`（旧的和 `GOOD_*` 都保留）。
- **显示双缓冲第一次真正生效**：`DIS CR` 的 bit8 **不存储**，所以原来的"翻转"是空操作，
  通道一直停在帧存 0（撕裂 + 一半工作从没显示）。改用 park 模式 + `PARK_PTR`
  （实测每帧翻转 84 次 / 4.36 秒，与 19.5 fps 同步）。
- **PS 裸机状态屏**：`ps_ui/` 已在板上跑通，左边实时相机、右边状态栏、底部诊断条。
- **颜色**：根因是 AN970 的 40 针接插件上 LCD 数据位**成对颠倒**
  （`B6,B7,B4,B5,B2,B3,B0,B1`），而 XDC（与厂商 `lcd_test.xdc` 逐脚相同）按顺序分配。
  修法：把 `vid_io_out_0_data[2k]` 与 `[2k+1]` 的 `PACKAGE_PIN` 成对对调（12 对 / 24 条）。
  **只改约束，不动 RTL / BD。** 参考实现 `ps_fft_dual/fix_lcd_bitpairs.py`。
- **帧率**：11.3 → 18.1 fps（相机侧；传感器 `0x3036=0x80` + VTS 740，已固化进 `ov5640_table.txt`）。

**开缓存之后必须知道的一件事（踩过一次）**
> `dow -data` + `con` **不会复位 CPU**。缓存和 MMU 保持**上一次运行**的状态 ——
> 上一版留下的**脏行**会写回、盖在新下载的镜像上，I-cache 里还留着**上一版镜像的指令**，
> 于是"刚下载的代码"和"CPU 正在执行的代码"不是一回事（症状：随机位置的数据中止、
> 寄存器里出现反汇编上不可能的值）。
> 所以 `ps_ui/startup.S` 的 `_start` **第一件事**就是关缓存、按 set/way 作废整个 D-cache
> （**丢弃**脏行而不是写回）、作废 I-cache/TLB、关 MMU —— 之后反复下载运行才可靠。

**已判定不可达**
- **60 fps**：`fps = PCLK/(HTS×VTS)`，需要 PCLK ≈ 85 MHz（现在 ≈ 21 MHz，差 4 倍）。
  实测 `0x3035` 的 SDIV0 由 2 降到 1 **必掉流**（50 MHz 与 100 MHz FCLK0 都试过），
  所以不是 FPGA 带宽问题。要更高帧率只能换传感器或换模式。

**已知限制（已记录，未处理）**
- 采集链路仍是 **RGB565**（5:6:5，65536 色），而 AN970 面板是 24 位 / 1670 万色。
  瓶颈在我们自己这边：`cmos_8_16bit.v` 每 2 字节拼 16 位 + 子集转换器补零扩展。
- **`live14_bitpair.tcl` / `RESTORE.md` 仍指向旧比特流** `design_1_wrapper_bitpair_50m.bit`。
  CDC 修正版是 `design_1_wrapper_cdcfix_50m.bit`（配套 `ps7_init_cdcfix_50m.tcl`），
  时序已全满足，但**还没走过完整冷启动流程**，所以没有替换默认引用。
- ~~既有时序违规 `clk_fpga_1 → clk_fpga_0`~~ → **已解决**：那 9 条全部是调试探针路径，
  已用精确 `set_false_path` 约束掉，重综合后 0 条违规（见上文）。

## 回退

**回退点**：`ps_fft_dual/GOOD_20260927_bitpair/`（含 `RESTORE.md`），
比特流 MD5 `EA765132DE5489DB69217AE2045D9DA3`。
板上当前跑的是 `design_1_wrapper_cdcfix_50m.bit`（时序全满足那版），
旧版 `design_1_wrapper_bitpair_50m.bit` 完整保留，随时可换回。

**用 git 回退**：本目录是 git 仓库。

```bash
git log --oneline          # 看历史
git status                 # 看当前改动
git checkout -- <文件>      # 撤销某个文件的改动
git reset --hard <提交>     # 整体回到某个提交
```

**注意**：`.gitignore` 排除了抓帧（`*.bin`）与 Vivado 生成物（`*.dcp/*.runs/*.gen` 等），
所以 git 里**没有**这些大文件 —— 它们是可重新生成的，不是交付物。
但 `*.bit`（比特流）**在** git 里，因为那是交付物。

## 上板（板子重新插好后）

### 方式 A：主机侧渲染（相机画面 + 防撕裂，已验证）

```bash
cd ps_fft_dual
xsdb.bat live14_bitpair.tcl     # 加载比特流 + PS 初始化 + 配相机 + 起采集（约 100 秒后自己退出）
xsdb.bat steer_loop3.tcl        # 另开一个终端常驻，防撕裂；它退出后撕裂会回来
```

> 只要 `steer_loop3` 占着 JTAG，别的 xsdb 脚本就抢不到板子 —— 先把它杀掉。

### 方式 B：PS 裸机状态屏（相机画面 + 状态栏，**已在板上验证：3.0 fps**）

PS 自己渲染 800×480 的一帧（左边相机画面、右边状态列），双缓冲自己翻转，
主机不再碰显示通道。三步：

```powershell
cd ps_ui
powershell -ExecutionPolicy Bypass -File build.ps1   # 产出 ps_ui.elf 和 ps_ui.bin

$env:LIVE14_NO_STEER = "1"      # 只做 bring-up，不进那个会和 PS 抢 CR 的转向循环
cd ..\ps_fft_dual
xsdb.bat live14_bitpair.tcl     # 加载比特流 + PS 初始化 + 配相机 + 起两个 VDMA 通道
xsdb.bat ps_run.tcl             # 把显示通道交给 PS 的 UI 缓冲，加载并运行 ps_ui.bin
```

> `$env:LIVE14_NO_STEER` 只在当前 PowerShell 窗口有效；换个窗口跑就得重新设。

跑完之后：

```powershell
cd ..\ps_fft_dual
xsdb.bat ps_capture.tcl   # 采集没在出帧时重发整段寄存器（只写 CR 不管用）；自带帧指针计数
xsdb.bat ps_display.tcl   # 显示通道同样要重发；会报 Halted 位与 IOC_Irq
xsdb.bat ps_shot.tcl      # 停机后 dump 两个 UI 缓冲区，隔 1.5 秒 dump 两次
cd ..\ps_ui
python ui_bin_to_png.py ui_a.bin ui_a2.bin   # 转 PNG + 统计 + 两项检测
```

### 让面板显示**真实**的质检数字（而不是种子数据）

```powershell
cd app
python server.py sim 8099            # 引擎（自己做质检判定，提供 /api/state）
python board_push.py                 # 轮询引擎 -> 写 ps_fft_dual/mailbox.txt
```
```powershell
cd ..\ps_fft_dual
xsdb.bat board_push.tcl              # 常驻：把 mailbox.txt 转发进 DDR mailbox
```
链路：`引擎 → HTTP → board_push.py → mailbox.txt → board_push.tcl(JTAG) → DDR → PS → 面板`。
`board_push.tcl` 会占住 JTAG（其他脚本抢不到板子），默认 300 秒后自己退出，
也可以建一个 `board_push.stop` 文件让它提前停。

> **显示通道是 MM2S，寄存器块和采集通道（S2MM）不一样** —— 写错地址是**静默无效**的：
> MM2S 用 `CR 0x00 / SR 0x04 / VSIZE 0x50 / HSIZE 0x54 / STRIDE 0x58 / ADDR 0x5C,0x60`；
> S2MM 用 `0x30 / 0x34 / 0xA0 / 0xA4 / 0xA8 / 0xAC,0xB0`。
> 判据：`SR` bit0=0 只说明"没停机"；**bit12(IOC_Irq) 在清过状态之后又置起来，才说明真的出拍了**。

`ui_bin_to_png.py` 会做两项**肉眼做不到**的判断：

- **彩色填充 bug**：一块"纯色"区域如果是**四色等量**，就是 32 位字写进了 3 字节像素
  （`fillrect_fast` 曾经就是这个 bug，画面上完全看不出来）
- **实时性**：两张 dump 的**相机区域变化百分比**。冻结帧和静止场景长得一样，
  只有比两张才能区分。实测正常值约 **88%**，面板/底栏应接近 **0%**

**若采集通道不出帧**（`CAP CR` 显示 running、`SR` 也正常，但画面是死的）：
跑 `xsdb.bat ps_capture.tcl`。这是 VDMA 顺序规则 —— 只写 `CR` 启不起来，
必须 `几何/地址 → CR=RUNSTOP → VSIZE 最后`。

**若 JTAG 掉线（只剩 DAP、两个 A9 核消失、读什么都返回 `0xFFFFFFFF`）：**
先跑 `xsdb.bat ps_recover.tcl`（它做 `connect` + `rst -system`）。
实测一次就恢复，**不需要断电**；`rst -system` 会清掉 PL，恢复后要重跑 `live14_bitpair.tcl`。

`ps_run.tcl` 会自己报出结论，看这几行就够：

```
  DIS CR = 0x00010003                              <- PL 在（0xFFFFFFFF 表示它不在）
    verified 8200 bytes against the file: 0 mismatching words   <- 内存 == 刚生成的文件
    t=600ms prog=6 frames=1 ...                    <- prog 走到 6 且 frames 在涨 = 真的在跑
```

`prog` 是进度信标（1 进循环 / 2 测完 / 3 相机画完 / 4 状态栏 / 5 底栏 / 6 翻转完成）：
**它停在哪一个数，就说明卡在哪一步** —— 这比事后解读 `DFSR/DFAR` 可靠得多。
（实测它总是 `prog=2`，说明一帧的时间几乎全花在 `draw_camera` 上。）

**⚠️ 内存图的坑（2026-10-03 实测，已写进 `ps_ui/lscript.ld` 注释）**：

| 地址范围 | 实测 |
|---|---|
| `0x00000000..0x0002FFFF` | 可写 —— **OCM 实际只有 192 KB** |
| `0x00030000..0x0003FFFF` | 读回 `0xFFFFFFFF`，**没译码** |
| `0xFFFF0000..0xFFFFFFFF` | 另有独立 64 KB |

把栈放到 `0x00030000` 以上，第一次压栈就同步外部中止 ——
而现象只是"帧计数器不动"。实测脚本：`ps_fft_dual/ps_ocm.tcl`、`ps_ocm2.tcl`。

---

## 2026-10-19 提交包

本赛季的提交材料收拢在 **[`submission/fpga_prize/`](submission/fpga_prize/)**：

- `build/rebuild.ps1` —— 检查 12 个输入与交叉编译器后才开始编译；缺一个就列出并停止；
- `board/` —— 真实上板用过的 bitstream、匹配的 ELF、`design_1.bd`、验证过的 XDC、`ps7_init`；
- `docs/REPORT_DRAFT.md` —— 按选题指南 §3.3.5.3 的七节写的设计报告草案；
- `docs/PERF_RESOURCE_20261019.md` —— 资源/时序/功耗实测（来自 Vivado 报告）；
- `docs/DETECT_LIMITS_20261019.md` —— 检测极限：0.119 mm/px，4 px≈0.48 mm 可检，
  细走线断口（0.2–0.3 mm）低于下限。

包内另附 `LICENSE`（MIT）与 `.gitignore`，可单独作为开源仓库根目录使用。
