# PL 贡献量化（2026-11-01）—— 出货 bitstream 的资源/时序 + 软硬划分理由

> 证据分级：**E2** = 本工程实测、或本次直接读到的报告数值；**E1** = 读自另一日期/另一构建的报告，或由实测值推算；**E0** = 未测。
> 本文只新增这一个文件，不修改任何既有文件；未上板、未改固件、未跑综合。缩写：`util` = `dl/pl_frontend/baseline_impl_20261024/design_1_wrapper_utilization_placed.rpt`（头 **2026-10-24 13:04:21**，Fully Placed）；`timing` = 同目录 `design_1_wrapper_timing_summary_routed.rpt`（头 **2026-10-24 13:09:35**，Routed）；冒号后为行号。

## 0. 结论

1. **出货 bitstream 的报告存在**，但只以副本形式存在：出货构建当天（10-24）的两份报告在 `dl/pl_frontend/baseline_impl_20261024/`；工程 `impl_1` 已被 2026-10-28 19:32 的另一版构建覆盖，出货 checkpoint 已不可用。
2. **PL 的账**：LUT **36,513**（68.63%）、FF **58,900**（55.36%）、BRAM **138.5/140**（98.93%）、DSP **219/220**（99.55%）；WNS **+0.908 ns**、TNS **0**，时序全满足；FCLK_CLK0 **50.000 MHz**。
3. **分工立场**：比较与判定**能进 PL，但现阶段选择不进**——每次比较的输入已从 2.76 MB 压到 28.8 KB（≈96×），进 PL 只买到几十毫秒，却要为 **14** 个候选统计量的每次迭代付一次重建。

## 1. 任务一：出货 bitstream 的资源与时序

### 1.1 身份链：哪份报告属于出货 bitstream

| 事实 | 值 | 来源（日期） | 级 |
|---|---|---|---|
| 出货 bitstream | `submission/board/BIT_20261024_fp1.bit` ≡ `safe_bitstreams/` 同名文件，4,045,676 B，SHA256 `BAF0DCE1…B2DF8`，mtime 2026-10-24 13:10:23 | 本次 `Get-FileHash`（11-01）；`submission/board/ARTEFACTS.md`（10-28） | E3 |
| 与工程产物的同一性 | `two FFT.runs/impl_1/design_1_wrapper.bit` 同 SHA256、同 mtime | `dl/RESOURCES_AND_LATENCY_20261027.md` §1（10-27） | E1 |
| 实现报告 | `design_1_wrapper_utilization_placed.rpt`，头 `Sat Oct 24 13:04:21 2026`，Fully Placed | 上述副本（10-24 16:53 从 impl_1 拷出） | E2 |
| 时序报告 | `design_1_wrapper_timing_summary_routed.rpt`，头 `Sat Oct 24 13:09:35 2026`，Routed | 同上 | E2 |
| 报告→bitstream | 13:04 报告 → 13:09 时序 → 13:09:53 routed.dcp → 13:10:23 `.bit`：同一次 `impl_1` 运行 | `RESOURCES…:445-447`（10-27 记录） | E2 |
| 10-27 复算 | `fp1_util_routed_20261027.rpt`（头 `Tue Oct 27 19:19:08`，Routed），关键行逐格同值 | `dl/evidence_20261027/`（10-27） | E1 |
| 今天能否重跑 | **不能**：D: 盘 `impl_1` 现为 2026-10-28 19:32 的构建（34,520 LUT / 108.5 BRAM） | 本次读报告头（11-01） | E2 |

> 别误用旧报告：`submission/legacy/fpga_snapshot_20261019/docs/` 里另有一套 `design_1_wrapper_*` 报告（util 头 **2026-10-18 20:59:03**：32,815 LUT / 61.68%、109.5 BRAM / 78.21%、DSP 219），是出货前 6 天的**另一版**构建；差 +7.0 pp LUT / +20.7 pp BRAM 按 `RESOURCES…` §6 归四帧存与探针，DSP 未变（E1）。

### 1.2 资源（xc7z020clg400-2，Vivado 2023.1；`util`，2026-10-24 13:04:21）

| 资源 | 已用 | 可用 | 占比 | 行 |
|---|---:|---:|---:|---:|
| LUT | 36,513 | 53,200 | 68.63% | 35 |
| └ LUTRAM（LUT as Memory：分布式 RAM 260 + SRL 2,046） | 2,306 | 17,400 | 13.25% | 37-39 |
| FF | 58,900 | 106,400 | 55.36% | 40 |
| BRAM tile（RAMB36 114 / RAMB18 49） | 138.5 | 140 | **98.93%** | 106-111 |
| DSP48E1 | 219 | 220 | **99.55%** | 122 |
| IOB | 62 | 125 | 49.60% | 133 |

**只剩 1.5 个 BRAM tile、1 个 DSP**（E2，直接读表）：PL 侧任何扩展都得先删东西。

### 1.3 时序与时钟（`timing`，2026-10-24 13:09:35）

| 指标 | 值 | 行 |
|---|---|---:|
| **WNS / TNS** | **+0.908 ns / 0.000**（失败端点 0/140,009） | 154 |
| **WHS / THS** | **+0.037 ns / 0.000**（0/139,873） | 154 |
| WPWS / TPWS | +8.870 ns / 0.000（0/62,380） | 154 |
| 结论 | **All user specified timing constraints are met.** | 157 |
| Fmax（推算） | **≈52.4 MHz** = 1/(20.000−0.908) | E1 |

| 时钟 | 频率 / 周期 | 行 |
|---|---:|---:|
| `clk_fpga_0` = PS FCLK_CLK0 | **50.000 MHz / 20.000 ns** | 167 |
| `clk_fpga_1` = PS FCLK_CLK1 | **32.728 MHz / 30.555 ns** | 168 |
| `lcd_pclk[0]`（XDC 约束 30.300 ns，比实际 30.555 ns 紧 0.84%） | 33.003 MHz / 30.300 ns | 170 |
| `dbg_hub/…/TCK`（JTAG，非设计时钟） | 30.303 MHz / 33.000 ns | 169 |

最差路径不在视频通路，而在 CNN：`ts_cnn_top_0/inst/gmem2_m_axi_U/…`（RAMB36）→ `grp_conv3x3_32_32_32/…`，slack 0.908 ns、数据路径 18.730 ns（逻辑 2.125 / 布线 16.605 = **88.7%**）（timing:264-266；`RESOURCES…:134-140`）。布线占主导 ⇒ 新增逻辑容易把它推负，与 WHS 只有 37 ps 是同一件事（E2）。

### 1.4 分层：报告只有总数

- 出货报告是**平表**（Slice Logic / Memory / DSP / IO 总计），**没有 hierarchy 段** ⇒ "哪个模块占多少"在出货网表上**没有报告**（E0）。
- 唯一的分层数据（均 E1，来自 10-28 重建：同设计、不同布局）：depth-1 `design_1_i` 36,037 LUT / 58,124 FF / 114 RAMB36 / 49 RAMB18 / 219 DSP，`dbg_hub` 476 LUT / 776 FF（`dl/pl_frontend/attempt2_20261028/baseline_impl_util_hier.rpt`，10-28 18:30:49）；两个 BD ILA 计 **5,755 LUT / 7,782 FF / 30 RAMB36**（`dl/ATTEMPT2_20261028.md` §2，10-28）= 出货 LUT 的 15.8%、BRAM 的 21.7%。
- **CNN 核在出货网表里的分级资源 = E0**。唯一的分模块数是 10-15 HLS 估算：31,678 LUT / 44,184 FF / 155 BRAM18 / 153 DSP（`dl/hls/hls_proj/sol1/syn/report/ts_cnn_top_csynth.rpt`，2026-10-15 13:07）；它与实现后的 219 DSP 对不上，不能当出货数引用。
- 补齐代价：出货 checkpoint 已被覆盖，必须恢复 10-24 的 BD 重跑实现（25–40 min/次）再出 `report_utilization -hierarchical`，**约半天**（复核人估计）。10-28 重建已逐项复现全部总数（`attempt2_20261028/baseline_impl_util.rpt`，10-28 18:30:45；`baseline_timing.rpt`，18:31:20，WNS/WHS 同值），说明重建的总数可期待一致，但布局会不同。

## 2. 任务二：软硬划分的理由（每题一个数）

| 模块 | 在哪 | 量化理由 | 证据（日期） |
|---|---|---|---|
| 双 AN5642 DVP 并口采集（16-bit ×2，实时像素流） | **PL** | 1280×720×3 = **2.76 MB/帧**（2,764,800 B），实测 **8.7–10.3 fps**（97.0–114.9 ms/帧）⇒ 单路约 24–28.5 MB/s；PS 的 GPIO/中断无法在 pclk 上采并口像素 | `dl/RESOURCES_AND_LATENCY_20261027.md` §5.4(c)（10-27 板测，E2） |
| 2:1 抽取 + 帧存 + 双 VDMA | **PL** | 零拷贝：帧存与 VDMA 在 fabric 内（BRAM 138.5/140）。同样的 2.76 MB 若由 PS 搬一趟，仅 D-cache invalidate 就 **2.6–5 ms/次**（86,400 line ops） | 同上 §2/§6；`dl/PERF_20261026_proposal.md:132`（E1/E2） |
| HLS 量化 CNN `ts_cnn_top` | **PL** | **219/220 DSP**（99.55%）的实际算力；**29–31 ms/次**推理、**8/8** 逐位 KAT、**147,672 B** 权重由主机加载。**它的 PS 软件基线未测** | `dl/CNN_KAT_20261027.md:13,23,78`（10-27 板测，E2）；DSP 见 §1.2 |
| 时序/引脚约束、跨时钟域、综合与实现 | **PL** | WNS **+0.908 ns**、WHS **+0.037 ns**、BRAM **98.93%**、DSP **99.55%** | 本文 §1.2–1.3（10-24 报告，E2） |
| 格点统计量（160×90） | **PS** | 每帧 **2.76 MB** → 每次比较 **28.8 KB**（28,800 B = 14,400 格 × int16）= **≈96×**；进 PL 只省几十 ms，却要为 **14** 个候选统计量的每次迭代付一次重建——这是"迭代速度"论证，也是诚实的那个 | `dl/ASK2_20261031_is_there_hope.md:98`（格式）；`submission/report/works_report_20261101.docx` / `dl/make_works_report.py:133,177`（14 种，10-31/11-01） |
| 判决 + 三道拒绝门 | **PS** | 同上：14 次迭代、每次重建；三道门（噪声地板 / 光照一致 / AEC 收敛）是策略逻辑，随统计量一起改 | `dl/REPORT_SKELETON_20261101.md:21-24`（11-01，E1/E2） |

**唯一的 PL↔PS 交互成本实测**：JTAG→PC **540–630 KB/s（典型上限 576 KB/s）**，整幅 2,764,800 B 需 **4.2–5.1 s/帧 = 0.20–0.24 fps**（`dl/LIVEWEB_20261101.md:19-23`，11-01）。所以"主机侧整幅 0.2 fps"是**调试通路**的属性，不是设计的属性；板上真实链路是 PL→DDR→PS 的 1280×720 流，实测 8.7–10.3 fps。

**立场（保留评审措辞）**：这些模块**能进 PL，但现阶段选择不进**（*able to go into the PL but chosen not to, at this stage*）。这不是"放不进去"：10-28 的 PL 前端：`pl_fe_core` 逐位通过（46,800/46,800），加 AXI wrapper 后实测 **2,711 LUT / 1,577 FF / 0 BRAM / 0 DSP**，但 `place_design` 在 41,092 LUT 上拒绝布局（缺 ~449 slice）（`dl/PLFE_DOES_NOT_FIT_20261028.md:6,49-51`，10-28）。把它做进去需要先删两个 ILA（5,755 LUT / 30 BRAM）再重跑实现——**是排期问题，不是可能性问题**。

## 3. E0 清单（未测，不得混入结论）

- CNN 的 PS 软件基线（同一 8/8 KAT 在 A9 上跑多久）：**未测**，本文不给 PL/PS 加速比。
- 出货网表的逐模块资源（§1.4 三条间接数是 E1，不是出货网表的分级报告）。
- 出货构建的 checkpoint 已不存在，任何"从 dcp 直接出分层报告"的路都不通。

_数据来源：本次只读 `dl/pl_frontend/baseline_impl_20261024/`、`dl/evidence_20261027/`、`dl/pl_frontend/attempt2_20261028/`、`D:\…\two FFT.runs\impl_1\`（仅列目录/读报告头）、`submission/board/`；未运行 Vivado、未上板、未改任何既有文件。_
