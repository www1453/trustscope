# 资源、时序与端到端延迟实测（2026-10-27）

> 对应评分项：**3.3.4 优化目标**（"在目标器件上取得可测量的性能表现，**并给出与基线的对比**"）、
> **3.3.5.1 工程包**（"**综合与实现报告，含资源占用、时钟频率与关键性能指标**"）、
> **3.3.5.3 设计报告**（"**优化过程，含优化前后的性能与资源对比表**"）。
>
> 本文每个数字都写了两件事：**来源文件/命令**，以及**它是测的、算的还是没测**。
> 没有来源的数字不写；测不到的数字写"未测"并说明原因，不用估计值冒充实测。

---

## 0. 一页结论

| 项 | 数值 | 等级 |
|---|---|---|
| 器件 / 出货比特流 | xc7z020clg400-2 / `safe_bitstreams/BIT_20261024_fp1.bit`（SHA256 `BAF0DCE1…B2DF8`，与 bring-up 脚本加载的 `impl_1/design_1_wrapper.bit` **逐字节相同**） | E3（哈希可复算） |
| LUT / LUTRAM / FF | 36,513 (68.63%) / 2,306 (13.25%) / 58,900 (55.36%) | E2（实现后报告 + 重建报告） |
| BRAM / DSP | 138.5/140 (98.93%) / 219/220 (99.55%) | E2 |
| 时序 | WNS **+0.908 ns**、TNS 0、WHS **+0.037 ns**、THS 0、WPWS +8.870；**"All user specified timing constraints are met."** | E2 |
| 时钟 | FCLK_CLK0 **50.000 MHz**、FCLK_CLK1 **32.728 MHz**（LCD 像素钟，XDC 约束 33.003 MHz）、JTAG dbg_hub TCK 30.303 MHz（非设计时钟） | E2 |
| PS | ARM Cortex-A9 **667 MHz**（PLL 1333.333 / 2） | E2（IP 参数 + 板端 SLCR 读回与 ps7_init 一致） |
| 循环周期 | **159.1 / 176.6 / 177.5 ms**（三个 32 循环窗口），12.3 s 帧计数积分 **5.54 循环/s** | E2 |
| 帧延迟（采集完成→显示翻页，固件实测） | 均值 **118.6 / 130.8 / 142.8 ms**；**最大 324.5 / 351.5 / 377.6 ms** | E2 |
| 一次比较 | **136.1 / 136.2 / 163.5 ms**（每 16 循环一次，摊薄 8.5–10.2 ms/循环） | E2 |
| 判定上屏（推导） | 新 **NG ≈ 0.42–0.45 s**；新 **PASS/UNK ≈ 1.24–1.33 s**（6 循环去抖） | E1（由实测分量 + 代码顺序推导，**未直接测**） |
| 采集/处理速率 | 采集 **8.7–10.3 fps**（97.0–114.9 ms/帧），处理 **5.5–5.7 循环/s** ⇒ 掉帧 | E2 |

**一句话**：性能数字是有的，但"判定上屏"比"帧上屏"慢一整个循环（多相机门限要去抖 6 个循环）；
本文件把两者分开写，因为把帧延迟当成判定延迟会夸大性能。

---

## 1. 构建身份：这份报告到底在说哪个比特流

| 事实 | 值 | 怎么得到的 |
|---|---|---|
| Vivado 工程 | `D:/BaiduNetdiskDownload/23_ov5640_dual/Vivado/two FFT/two FFT.xpr` | `ps_fft_dual/rebuild_fp1_1024.tcl:1`、`ps_fft_dual/logs/build.log:3` |
| 最后一次实现运行 | `two FFT.runs/impl_1`，bitstream `2026-10-24 13:10:23` | 目录时间戳 |
| impl_1 产出比特流 | `design_1_wrapper.bit`，4,045,676 B，SHA256 `BAF0DCE1C1AE941B3BED4124B6283A71B9208EFB98EE1C02B91C33E4852B2DF8` | `Get-FileHash -Algorithm SHA256` |
| 出货副本 | `safe_bitstreams/BIT_20261024_fp1.bit`，**同一 SHA256** | 同上 |
| bring-up 实际加载的文件 | `D:/BaiduNetdiskDownload/23_ov5640_dual/Vivado/two FFT/two FFT.runs/impl_1/design_1_wrapper.bit` | `ps_fft_dual/stereo_bringup_byname.tcl:29` |

结论：**impl_1 的这份实现报告，就是出货 bitstream 的报告**（哈希相同，不是"看起来像"）。
工程目录在仓库外（D: 盘），仓库里只有比特流副本与构建脚本；这一点如实写在报告里，
评委按 `safe_bitstreams/` 的哈希 + 本文命令可复算。

固件身份（板端读数，见 §5.1）：

| 项 | 值 |
|---|---|
| 源码哈希 | `ps_ui/build_id.h`: `FW_SRC_HASH "2E8B1A84"`，`FW_SRC_N 13` |
| ELF | `ps_ui/ps_ui.elf`，200,640 B，`2026-10-27 19:00:48` |
| 板端 `MB_FWID0..2` | `0x31435354`（"TSC1"）+ `0x42384532` + `0x34384131` = `TSC1` + **`2E8B1A84`** ⇒ 板上跑的就是这份源码编出的镜像 |

---

## 2. 资源占用（出货比特流）

### 2.1 表

| 资源 | 已用 | 可用 | 占比 | 备注 |
|---|---|---|---|---|
| Slice LUTs | **36,513** | 53,200 | **68.63%** | |
| ├ LUT as Logic | 34,207 | 53,200 | 64.30% | |
| └ **LUT as Memory（LUTRAM）** | **2,306** | **17,400** | **13.25%** | 其中分布式 RAM 260、移位寄存器（SRL）2,046 |
| Slice Registers（FF） | **58,900** | 106,400 | **55.36%** | 无 latch |
| Block RAM Tile | **138.5** | 140 | **98.93%** | RAMB36 114/140 = 81.43%；RAMB18 49/280 = 17.50% |
| **DSP48E1** | **219** | 220 | **99.55%** | 几乎全在 HLS 卷积核 `ts_cnn_top`（见 §7） |
| Bonded IOB | 62 | 125 | 49.60% | 两路相机 + LCD + 触摸 |
| BUFGCTRL | 5 | 32 | 15.63% | |
| MMCM / PLL | 0 | 4 | 0% | 时钟全部来自 PS7 FCLK |

**资源上的硬事实（报告应直说）**：BRAM 只剩 1.5 个 tile（98.93%），DSP 只剩 1 个（99.55%）。
"再加一个数据通路"在今天的网表里没有空间，任何 PL 侧扩展都必须先删东西（§7）。

### 2.2 出处（两条独立来源，数值完全一致）

**来源 A —— 实现运行自带的实现后报告（placed 状态）**

```
文件: D:/BaiduNetdiskDownload/23_ov5640_dual/Vivado/two FFT/two FFT.runs/impl_1/
      design_1_wrapper_utilization_placed.rpt
报告头: | Date         : Sat Oct 24 13:04:21 2026
        | Command      : report_utilization -file design_1_wrapper_utilization_placed.rpt
                         -pb design_1_wrapper_utilization_placed.pb
        | Design State : Fully Placed
```

**来源 B —— 本次（2026-10-27 19:19）从已实现 checkpoint 重跑，post-route**

命令（一步不改，可复现）：

```
D:\Vitis\Vivado\2023.1\bin\vivado.bat -mode batch -nojournal -nolog ^
  -source C:\Users\wzh\Documents\trustscope\.tmp\fp1_reports_20261027.tcl
```

脚本内容（`open_checkpoint` 不需要综合、不需要板子）：

```tcl
open_checkpoint {D:/BaiduNetdiskDownload/23_ov5640_dual/Vivado/two FFT/two FFT.runs/impl_1/design_1_wrapper_routed.dcp}
report_utilization -file {C:/Users/wzh/Documents/trustscope/ps_fft_dual/logs/fp1_util_routed_20261027.rpt}
report_timing_summary -max_paths 1 -report_unconstrained -file {C:/Users/wzh/Documents/trustscope/ps_fft_dual/logs/fp1_timing_routed_20261027.rpt}
```

```
输出: ps_fft_dual/logs/fp1_util_routed_20261027.rpt
报告头: | Date         : Tue Oct 27 19:19:08 2026
        | Command      : report_utilization -file C:/Users/wzh/Documents/trustscope/
                         ps_fft_dual/logs/fp1_util_routed_20261027.rpt
        | Design State : Routed
```

> 说明：impl_1 里原本没有 routed 状态的 utilization 报告（Vivado 只在 place 后生成
> `utilization_placed.rpt`），所以**本文件额外跑了一次 routed 报告**。两者逐格相同
> （36,513 / 2,306 / 58,900 / 138.5 / 219），差异为 0，说明 place 后的网表就是最终网表。

---

## 3. 时序（出货比特流）

| 指标 | 值 | 说明 |
|---|---|---|
| **WNS** | **+0.908 ns** | 最差建立路径在 `clk_fpga_0`（50 MHz，20.000 ns） |
| TNS | 0.000 ns | 失败端点 **0 / 140,009** |
| **WHS** | **+0.037 ns** | 保持余量只有 37 ps，与 2026-10-19 那版（+9 ps）同一量级 |
| THS | 0.000 ns | 失败端点 0 / 139,873 |
| WPWS | +8.870 ns | 失败端点 0 / 62,380 |
| 结论 | **"All user specified timing constraints are met."** | 报告原文 |
| Fmax 推算 | 1 / (20.000 − 0.908) = **52.4 MHz**（50 MHz 域） | 由 WNS 算，标注为推算 |

**最差路径**（不是视频通路，是 CNN）：

```
Slack (MET): 0.908ns
  Source:      design_1_i/ts_cnn_top_0/inst/gmem2_m_axi_U/load_unit/.../mem_reg/CLKARDCLK
               (RAMB36E1, clk_fpga_0 20.000ns)
  Destination: .../grp_conv3x3_32_32_32_Pipeline_VITIS_LOOP_181_1_fu_905/bl_2_fu_576_reg[2]/D
  Data Path Delay: 18.730ns (logic 2.125ns = 11.3%, route 16.605ns = 88.7%)
```

88.7% 是布线延迟（0 级逻辑），说明这条路径受布局布线拥塞影响，不是逻辑深度问题；
任何新增逻辑都可能把它推负，与 WHS 只有 37 ps 是同一件事。

### 3.1 时钟

| 时钟 | 频率 | 周期 | 来源 |
|---|---|---|---|
| `clk_fpga_0` = PS **FCLK_CLK0** | **50.000 MHz** | 20.000 ns | timing summary Clock Summary；PS7 IP `PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ = 50.000000` |
| `clk_fpga_1` = PS **FCLK_CLK1** | **32.728 MHz** | 30.555 ns | 同上；IP 请求 33 MHz，实现值 32.727272 |
| `lcd_pclk[0]` | 33.003 MHz | 30.300 ns | XDC `create_clock -period 30.300 [get_ports lcd_pclk]`（`ps_fft_dual/vivado/two_fft.xdc:10`） |
| `dbg_hub/.../TCK` | 30.303 MHz | 33.000 ns | JTAG 调试核，不是设计时钟 |

注意：`lcd_pclk` 由 FCLK_CLK1 驱动（H18，OUTPUT），XDC 在端口上又按 30.300 ns 建了一个钟。
30.300 ns 比实际 30.555 ns 更紧（0.84%），所以这个约束是**偏保守**的，不是放松。

### 3.2 出处

```
文件: D:/BaiduNetdiskDownload/23_ov5640_dual/Vivado/two FFT/two FFT.runs/impl_1/
      design_1_wrapper_timing_summary_routed.rpt
报告头: | Date         : Sat Oct 24 13:09:35 2026
        | Command      : report_timing_summary -max_paths 10 -report_unconstrained
                         -file design_1_wrapper_timing_summary_routed.rpt
                         -pb design_1_wrapper_timing_summary_routed.pb
                         -rpx design_1_wrapper_timing_summary_routed.rpx
                         -warn_on_violation
        | Design State : Routed
```

本次重建（`ps_fft_dual/logs/fp1_timing_routed_20261027.rpt`，2026-10-27 19:19:41）
复现出**完全相同**的 WNS/TNS/WHS/THS/WPWS 与时钟表。

---

## 4. PS 侧：ARM 667 MHz，以及哪些阶段跑在它上面

### 4.1 ARM 主频

| 证据 | 值 |
|---|---|
| PS7 IP 参数 `PCW_ACT_APU_PERIPHERAL_FREQMHZ` | **666.666687 MHz**（`design_1_processing_system7_0_0.xci`） |
| PS7 IP 参数 `PCW_CPU_CPU_PLL_FREQMHZ` | 1333.333 MHz（÷2 = 667） |
| 板端 SLCR 读回 `0xF8000100` | `0x00028008`（FBDIV = 0x28 = 40 → 33.333 × 40 = 1333.3 MHz） |
| 板端 SLCR 读回 `0xF8000120` | `0x1F000200`，与 `ps7_init.tcl` 的 `mask_write 0XF8000120 0x1F003F30 0x1F000200` **一致** |

即：板上正在跑的 PS 时钟树就是 XSA 里 ps7_init 写的那套，ARM = 667 MHz。
（`ps_fft_dual/ps7_init*.tcl` 各版本在 0xF8000100/0xF8000120 上写的是同一组值。）

### 4.2 软硬件分工（写报告用）

| 功能 | 在哪 | 代码/证据 |
|---|---|---|
| 两路 OV5640 采集、`cam_switch`、2×S2MM VDMA | **PL** | BD 实例 `alinx_ov5640_0/1`、`cam_switch`、`axi_vdma_0/1` |
| 显示：MM2S VDMA、`v_tc`、`v_axi4s_vid_out` | **PL** | `axi_vdma_2`、`v_tc_0`、`v_axi4s_vid_out_0` |
| 相机复位 GPIO、第二路相机 `axi_iic`、探针计数器 | **PL** | `axi_gpio_0/1`、`cam_iic_1`、`cam_pclk_cnt`、`clk_probe_cnt` |
| HLS 卷积核 `ts_cnn_top` | **PL（占 219 DSP，当前不产出）** | §7；`MB_CNN_RUNS` 未写入 |
| 采集存储选择、撕裂检测 | PS | `main.c` `cap_read_index()` / `tear_sig_compare()` |
| 曝光/AEC（含 I2C 写传感器） | PS | `main.c` AEC 控制器 + `cam_i2c.c` |
| 参考帧/背景/容差图 | PS | `ref_take()` / `bg_take()` / `tol_at()` |
| **配准** | PS | `reg_search()`，实测 `MB_REG_TICKS` 17.0–17.1 ms |
| **比较**（格点/粗单元/细格/轮廓） | PS | `diff_frame()`，实测 `MB_DIFF_MS` 136–164 ms |
| **判定与去抖** | PS | `diff_verdict()` + 6 循环去抖（§5.4） |
| 面板 UI 渲染 | PS（直接画帧缓冲） | `draw_camera()` / `draw_panel()`；不用 `v_osd`（无 license） |
| 证据快照 | PS | `evid_copy()`，`MB_EVID_TICKS`（本会话为 0，未触发） |

---

## 5. 端到端延迟（板端实测）

### 5.1 读法与固件身份闸门

**只读、一次一个 xsdb 客户端、不 reset、不重载 bitstream。** 每次读取一个 xsdb 批处理会话，
选核用名字（编号会漂移）：

```tcl
connect
after 500
targets -set -filter {name =~ "*Cortex-A9*#0"}
mrd -force -value 0x10F00000+4*<index>      ;# MAILBOX = 0x10F00000 (main.c:277)
```

固件身份（**按规矩 gate 在 MB_FWID0..2，不看 MB_MAGIC**）：

| 字 | 值 | 含义 |
|---|---|---|
| `MB_FWID0` (168) | `0x31435354` | "TSC1" |
| `MB_FWID1` (169) | `0x42384532` | "2E8B" |
| `MB_FWID2` (170) | `0x34384131` | "1A84" |

= `TSC1` + `2E8B1A84`，与 `ps_ui/build_id.h` 一致。**读到的每个延迟数字都属于这份固件。**
（顺带的反例：`MB_MAGIC`(0) 读回 `265,079,135`，不是 "TSC1"，所以面板上"主机判定"一栏
显示 `--`；`MB_VERDICT/TOTAL/OK/NG` 也确实是未初始化的垃圾值。这些**主机写字**不能当测量用。）

### 5.2 循环各段（三个 32 循环窗口，固件自己的 `MB_T_*` 和）

`MB_T_*` 是 **32 个循环的累加和**（`main.c:15721`），除以 `MB_T_N`、再除以 334,800 ticks/ms。

| 段 | 窗口 A (19:12:47) | 窗口 B (+4 s) | 窗口 C (19:17:57) | 这一段实际包含什么 |
|---|---|---|---|---|
| `sync`（等采集交接） | **35.93 ms** | 34.70 ms | 28.32 ms | `cam_bracket_sync()` 等下一个 CAP_FRPTR；**不是**曝光+VDMA 的时长 |
| `class`（发布+选帧+失效+分类） | **59.61** | 59.91 | 52.65 | 存储选择、2.76 MB `dcache_invalidate`、`part_track()`（`MB_PART_TK_MS` 4.86/8.10/12.55 ms 在这里面）、AEC/参考逻辑 |
| `qual`（质量度量） | 7.55 | 7.65 | 7.65 | `measure()` |
| `cam` | **65.74** | 67.06 | 62.73 | `draw_camera()` + 每循环发布 + **比较（1/16 次）** + 平均采样（8/16 次） |
| `panel` | 1.02 | 1.02 | 1.02 | `draw_panel()`（判定就是在这张图上） |
| `tail` | 6.76 | 7.15 | 6.76 | 底栏、按钮、缩略图、CNN/命令、`dcache_clean`、**park flip（翻页）** |
| `pub` | 0.0004 | 0.0004 | 0.0004 | 计数发布 |
| **合计** | **176.60** | **177.50** | **159.12** | |
| 分段求和校验 | 176.60 | 177.50 | 159.12 | 七段相加 = 总和（误差 < 0.01 ms） |

> ⚠️ 段名不能照字面读：`cam` 不等于"渲染"。比较在 `cam` 段里（代码顺序：`tD`=14911 →
> `draw_camera`=15014 → 比较=15278–15335 → `tE`=15411），平均采样也在里面。
> 用固件自己的子字拆开（**推导**）：
> `draw_camera ≈ cam − diff/16 − avg/2` = **37.6 / 42.6 / 37.8 ms**。

### 5.3 一次比较的分段（grabber → reference → registration → comparison → verdict → render）

| 阶段 | 数值 | 测的？ | 依据 |
|---|---|---|---|
| **grabber**：等采集交接 | **28.3–35.9 ms** | **实测**（等待部分） | `MB_T_SYNC/MB_T_N` |
| 　曝光 + VDMA 写一帧 | **未测** | **未测** | 没有计时字；只测到采集间隔 `MB_CAP_PERIOD` = 97.0–114.9 ms/帧 |
| **reference**：参考帧/背景 | 无每次比较的字 | **未测** | `ref_take()` 只在开机/命令时跑一次，无计时字 |
| 　参考的 8 帧平均（每 16 循环窗口内最多 8 次采样） | **29.4–39.3 ms / 次采样** | 实测（最近一次） | `MB_AVG_TICKS`，`MB_AVG_N=8`，`MB_AVG_SKIP=92`（有跳过的帧） |
| **registration**：配准 | **17.0–17.1 ms** | **实测** | `MB_REG_TICKS`（一次搜索；占比较 10.4–12.5%） |
| **comparison**：整次 `diff_frame` | **136.1 / 136.2 / 163.5 ms** | **实测** | `MB_DIFF_MS`（含选帧 + 2.76 MB invalidate + 配准） |
| **verdict**：`diff_verdict()` + 发布 | **未测** | **未测** | 直接函数调用，无计时字；只能由代码顺序界定 |
| **render**：`draw_camera` | **≈37.6–42.6 ms** | **推导** | `cam − diff/16 − avg/2`（见上） |
| 　`draw_panel`（判定上屏） | **1.02 ms** | **实测** | `MB_T_PANEL/MB_T_N` |
| 　`tail`（含翻页） | **6.76–7.15 ms** | **实测** | `MB_T_TAIL/MB_T_N` |

### 5.4 端到端与判定延迟（两个不同的量，分开写）

**(a) 帧延迟 —— 固件实测（`main.c:15648` 的 `g_e2e_*`，字 160–163）**

定义（代码原文）：`tB` = `cam_bracket_sync()` 之后、即"看见一帧采集完成"的瞬间；
`tG` = `DIS_PARK` 翻页之后、即"这一帧成为显示屏扫描源"的瞬间。中间包含比较与绘制。

| 窗口 | 均值 `sum/n` | 最大 `max` | 最后一个 `last` | 自洽检验：`loop − sync` |
|---|---|---|---|---|
| A | **142.8 ms** | **324.5 ms** | 210.7 ms | 176.60 − 35.93 = 140.67（差 2.1 ms） |
| B | 118.6 ms | **377.6 ms** | 204.5 ms | 177.50 − 34.70 = 142.80（**不吻合**，见下） |
| C | **130.8 ms** | **351.5 ms** | 88.3 ms | 159.12 − 28.32 = 130.80（差 0.0 ms） |

窗口 A/C 的 `E2E ≈ loop − sync` 在 2 ms 内闭合，说明这两个字量与分段定义自洽。
窗口 B 不闭合（差 24 ms）：T 段和 E2E 段是**两次读**，若两次读之间正好跨过一次
32 循环的发布，就会取到不同的窗口。这是读法的边界，不是固件的错；**引用时用 A/C，B 只作范围参考。**

**(b) 判定延迟 —— 推导（E1，未直接测）**

代码顺序决定了"判定比帧晚一个循环"：

1. 判定投票在 `main.c:15145-15168`，用的是**上一次**比较发布的字（本循环的 `diff_frame`
   在 `15278` 才跑）⇒ 比较 N 的结果在循环 **N+1** 才进入投票。
2. 去抖（`main.c:15153-15166`）：**NG 立即采纳**；PASS / CANNOT JUDGE 必须连续 6 个循环一致
   才发布 ⇒ 变化要等到循环 **N+6**。
3. `draw_panel()` 在同循环 `15418`，翻页在 `15644`。

| 情形 | 推导式 | 结果 |
|---|---|---|
| 帧上屏（稳态，与判定是否变化无关） | 测量值 | **118.6–142.8 ms 均值；324.5–377.6 ms 最大** |
| 一次比较所在循环的帧延迟 | `mean + 15/16 × diff` | **246–284 ms** |
| **新 NG 上屏** | 上式 + 1 个循环 | **≈ 0.42–0.45 s** |
| **新 PASS / UNK 上屏** | 上式 + 6 个循环（去抖） | **≈ 1.24–1.33 s** |

> 这三行是**推导**：`diff`、`mean`、循环周期都是实测的，但"判定上屏"没有计时字，
> 所以它只能标 E1。要变成 E2，需要在 `draw_panel` 前加一个字（改设计 + 重编 + 重烧），
> 本次规则不允许，故不做。

**(c) 循环速率（与延迟不是同一个量）**

| 量 | 值 | 方法 |
|---|---|---|
| 循环周期 | 159.1 / 176.6 / 177.5 ms | `MB_T_TOTAL/MB_T_N/334800`（32 循环窗口） |
| 循环速率 | **5.5–5.7 循环/s** | `MB_PS_FRAMES` 增量 68 帧 / 12.267 s = 5.54/s |
| 采集速率 | **8.7–10.3 fps** | `MB_CAP_PERIOD` = 96,991 / 114,866 µs（两次读） |
| 比较速率 | ≈ 0.35 次/s | 1 / (16 × 0.1766 s) |

⇒ 循环周期是采集间隔的 **1.4–1.8 倍**，所以约 30–45% 的采集帧在 4 存储环里被覆盖。
掉帧是设计现状，不是测量误差。

**(d) 不能用的字：`MB_FPSX10`**

`MB_FPSX10` 在同一分钟的 20 次采样里在 **4.0–11.0** 之间跳（窗口被量化到整数个循环，
且 `(nn−n0)*10` 只对 1.000 s 才等于 fps）。它与 12.3 s 帧计数积分（5.54/s）**不自洽**，
所以本文件**不引用它**，速率一律用帧计数差值 + 主机时钟。

### 5.5 测量工具本身怎么验的（measurement-discipline）

1. **先验闸门**：`MB_FWID0..2` = `TSC1`+`2E8B1A84` 与 ELF 的 `build_id.h` 相同 → 读的是这份固件。
2. **自洽检验 1**：七段之和 = `MB_T_TOTAL`（误差 < 0.01 ms，三个窗口都成立）。
3. **自洽检验 2**：`E2E ≈ loop − sync`（窗口 A 差 2.1 ms、C 差 0.0 ms）——两个独立字量互证。
4. **已知答案对照**：`MB_MAGIC` 读回非 "TSC1"、`MB_VERDICT` 读回垃圾值，而同一批读里
   `MB_T_N=32`、`MB_AVG_N=8`、`MB_DIFF_N` 单调递增——说明"读到垃圾"是那些字**没人写**，
   不是读取通道坏了。
5. **反向检验**：`MB_FPSX10` 与帧计数矛盾 ⇒ 判定为不可用并弃用，而不是挑一个好看的值。

---

## 6. 与基线的对比（评分项明确要求）

**先说清楚这是什么对比**：不是同一天、同一场景、同一变量的受控 A/B。
下表是**本工程自己记录在案的历史数字**（2026-10-24、10-26 两个版本）与今天同一块板的实测并排；
场景、平均帧数 `MB_AVG_N`、以及 10-27 新增的代码都不同。凡是有受控 A/B 的，单独标出。

| 量 | 2026-10-24 版 | 2026-10-26 版 | **2026-10-27 本版** | 出处 |
|---|---|---|---|---|
| 循环周期 | 137.4 ms | 99.32 ms（`AVG_N=1`） | **159.1–177.5 ms**（`AVG_N=8`） | `dl/STAGE8_20261024_fine_cells_and_adaptive.md:221`；`dl/PERF_20261026_proposal.md:86-95`；本文 §5.2 |
| 一次比较 | 91.1 ms | 167.2 ms | **136.1–163.5 ms** | 同上 |
| 配准 | — | 16.69 ms | **17.0–17.1 ms** | `MB_REG_TICKS` |
| 8 帧平均采样 | 28.4 ms | 28.0 ms | **29.4–39.3 ms** | `MB_AVG_TICKS` |
| 每循环 part mask | 无 | 4.83 ms（中位） | **4.86–12.55 ms** | `MB_PART_TK_MS` |
| 等采集交接 | — | 0.0008 ms | **28.3–35.9 ms** | `MB_T_SYNC` |
| 循环速率 | 7.3 fps | 10.1 fps | **5.5–5.7 循环/s** | 1/周期；§5.4(c) |
| 资源 | 61.68% LUT / 99.55% DSP / 78.21% BRAM | — | **68.63% / 99.55% / 98.93%** | `dl/PERF_RESOURCE_20261019.md`；§2 |

**受控 A/B（同一版本、只改一个变量）**：`MB_PART_TK_ON` 0→1 的每循环掩膜发布，
实测循环 **104.9 → 138.0 ms（+33.1 ms）**、class 段 **15.6 → 35.7 ms**，而掩膜本身只有 4.83 ms；
差值主要落在采集交接/class 段，**未完全分离**（`dl/PART_MASK_PERFRAME_20261026.md` §4，原文即如此声明）。

**到底变了什么（诚实版）**：

1. **变慢的主要是"平均采样臂"**：10-26 的 99.3 ms 是 `AVG_N=1`（关闭平均）时的数；今天板上是
   `AVG_N=8`，每个 16 循环窗口里有 8 个循环要跑 29–39 ms 的采样（摊薄 ≈ 15–20 ms/循环）。
   这不是"代码退化"，是两种工作点的对比。比较本身的 136–164 ms 与 10-26 的 167 ms 同量级。
2. **等采集交接从 ~0 变成 28–36 ms**：循环（159–177 ms）现在慢于采集间隔（97–115 ms），
   每个循环要等下一个交接沿。它**不是**新增开销，而是"循环变慢"的可见后果。
   10-26 文档里那笔"无法归因的 ~28 ms"与它同量级，但"就是它"是**推断（E0）**，没有实验分离；
   今天它至少有了自己的计时字（`MB_T_SYNC`）。
3. **新增功能**（10-26 → 10-27，`git log -- ps_ui/main.c`）：证据快照（`8def42b` 17:18）、
   参考质量检查 REFQ（`62e45d3`）、自检冻结与相机 1 移动预算（`e0334ec`）、
   相机 0 掩膜项（`650afc2`）、stage L 的参考掩膜/边距（`75a65dc` 17:36，publish-only）。
   注意：stage L 的撤回提交是 `1eaf1c6`（19:21），**晚于板上 19:00 的镜像**，所以
   **镜像里仍有 stage L 的代码**——"已撤回"只对源码 HEAD 成立，不对板上镜像成立。
   这些改动占用的是 **OCM 与循环 CPU 时间**，不是 PL 资源——所以资源表（§2）与 10-19 相比
   只有 LUT +7 个百分点、BRAM +20 个百分点（四帧存与探针），DSP 没变（CNN 一直占着）。
4. **性能没有"变好"这回事**：本文件不主张加速。今天的循环比 10-26 的 99 ms 慢，
   换来的是每循环 part 跟踪、8 帧平均、证据快照与参考质量闸门。
   若报告要写"优化"，能站得住的只有：**配准架构与 8 帧平均使判定更稳**（`dl/STAGE2_20261024_average.md`：
   N=1 时 43 帧里 2 帧 cells≥8，N=8 时 47 帧里 0 帧），以及**比较的耗时仍与 10-26 的记录同量级**
   （136–164 ms 对 167 ms；注意 10-26 那次是 `AVG_N=1`，比较自身要做的逐帧读取更多），
   没有"随功能增加而恶化"的证据。

---

## 7. 为什么比较不放进 PL（报告段落，约 300 字）

PL 负责采集与显示：两路 OV5640 采集、`cam_switch`、两路 S2MM VDMA、显示 MM2S VDMA＋`v_tc`＋
`v_axi4s_vid_out`、相机复位 GPIO 与第二路 `axi_iic`，外加一个占 219/220 个 DSP 的 HLS 卷积核；
但当前镜像里这个卷积核不产出结果（`MB_CNN_RUNS` 读回的不是计数，说明从未写入）。面板 UI 也没用
`v_osd`（厂商例程依赖它，本机无 license），而是由 PS 直接画进帧缓冲。比较、配准、AEC、门限都在
A9 上：一次比较 136–164 ms，但每 16 个循环才做一次，摊薄后 8.5–10.2 ms/循环，只占 159–177 ms 循环的
5–6%——即使做成零耗时的 PL 块，循环也最多快 5%。每循环真正的开销是渲染（约 38 ms）、8 帧平均采样
（29–39 ms，隔循环）和 part 跟踪（5–13 ms）。PL 也已无余量：BRAM 98.9%、DSP 99.6%；固件被压在
128 KB OCM 里，余量只有 56–3,260 字节（同一天两次实测）。若还有时间，下一步不是搬比较，而是在
采集通路上加一个只做加减法的 PL 前端，边写帧边产出 160×90 格点与 16×16 单元均值，预计把循环降到
约 110–130 ms（1.4–1.6 倍）且不占 DSP；前提是先删掉或修好那个不产生结果的 CNN 块，否则 BRAM/DSP
都腾不出来。

---

## 8. 未测项（不写"应该没问题"）

- **未测**：判定从投票到上屏的精确延迟。因为 `diff_verdict()`/`draw_panel()` 无计时字，只能由代码顺序
  推导（E1）。需要：在 `draw_panel()` 前加一个字记录"本次判定的循环号/时戳"，重编重烧后再测。
- **未测**：曝光 + VDMA 单帧写入时长（"光子到 store 完整"）。需要 ILA 或 PL 时戳，属改设计。
- **未测**：`ref_take()` / `bg_take()` 的单次成本（只在开机/命令时跑）。
- **未测**：LCD 扫描输出本身的延迟（翻页后到肉眼可见，最多一个面板帧）。需要光电或相机对拍。
- **未测**：板上 `MB_EVID_TICKS`（本会话为 0，因为没有触发证据快照）；10-26 版本记录为 30.7 ms，
  本版加词后预计 +2–4 ms，**未实测**。
- **未测**：多板/多场景的统计分布。本文是**一块板、一个工位、若干窗口**的数，不是种群统计。
- **未测**：PL 侧扩展的真实收益（§7 的 110–130 ms 是按已测分量算的**预期**，没有实现，故不是实测）。

---

## 9. 复现命令（评委/后续 agent 可直接照抄）

```powershell
# 1) 比特流身份：两个哈希应完全相同
Get-FileHash 'safe_bitstreams\BIT_20261024_fp1.bit' -Algorithm SHA256
Get-FileHash 'D:\BaiduNetdiskDownload\23_ov5640_dual\Vivado\two FFT\two FFT.runs\impl_1\design_1_wrapper.bit' -Algorithm SHA256

# 2) 资源与时序（不需要综合、不需要板子，约 2 分钟）
D:\Vitis\Vivado\2023.1\bin\vivado.bat -mode batch -nojournal -nolog ^
  -source dl\evidence_20261027\fp1_reports_20261027.tcl
#    -> ps_fft_dual\logs\fp1_util_routed_20261027.rpt
#    -> ps_fft_dual\logs\fp1_timing_routed_20261027.rpt

# 3) 板端读数（只读；一次一个 xsdb 会话；用名字选核）
D:\Vitis\Vitis\2023.1\bin\xsdb.bat dl\evidence_20261027\read_mailbox_2snap_20261027.tcl   # 两窗口 32 循环和
D:\Vitis\Vitis\2023.1\bin\xsdb.bat dl\evidence_20261027\read_loop_rate_12s_20261027.tcl   # 12 s 帧计数
D:\Vitis\Vitis\2023.1\bin\xsdb.bat dl\evidence_20261027\read_extra_and_slcr_20261027.tcl  # 采集周期/LCD 限值/PS 时钟寄存器
D:\Vitis\Vitis\2023.1\bin\xsdb.bat dl\evidence_20261027\read_cnn_and_magic_20261027.tcl   # CNN 状态/MAGIC/本板判定
```

板端脚本的写入路径：`mrd -force -value`（只读），不出现 `mwr`、不出现 `rst`、不出现 `fpga -f`。

---

## 10. 数据来源清单

| 文件 | 时间 | 说明 |
|---|---|---|
| `ps_fft_dual/logs/fp1_util_routed_20261027.rpt` | 2026-10-27 19:19:08 | 本次从 routed.dcp 重跑的资源报告（Routed） |
| `ps_fft_dual/logs/fp1_timing_routed_20261027.rpt` | 2026-10-27 19:19:41 | 本次从 routed.dcp 重跑的时序摘要（Routed） |
| `impl_1/design_1_wrapper_utilization_placed.rpt` | 2026-10-24 13:04:21 | 实现运行自带（Fully Placed），与上表逐格相同 |
| `impl_1/design_1_wrapper_timing_summary_routed.rpt` | 2026-10-24 13:09:35 | 实现运行自带（Routed） |
| `impl_1/design_1_wrapper_routed.dcp` | 2026-10-24 13:09:53 | 上述报告与比特流的共同来源 |
| `ps_ui/build_id.h` / `ps_ui/ps_ui.elf` | 2026-10-27 19:00 | 固件身份（`2E8B1A84`） |
| `dl/PERF_20261026_proposal.md` | 2026-10-26 21:00 | 10-24/10-26 基线数字与分段归因 |
| `dl/PART_MASK_PERFRAME_20261026.md` | 2026-10-26 19:10 | 每循环掩膜的受控 A/B（104.9→138.0 ms） |
| `dl/PERF_RESOURCE_20261019.md` | 2026-10-19 | 10-18 版的资源/时序对照 |
| `dl/STAGE8_20261024_fine_cells_and_adaptive.md` | 2026-10-24 | 91.1 ms 比较 / 137.4 ms 循环的原始记录 |
| `dl/STAGE_Q_20261027_colour_edge_quad.md` | 2026-10-27 19:02 | OCM 余量 3,260 B（两种量法） |
| `dl/EVIDENCE_SNAPSHOT_20261027.md` | 2026-10-27 17:20 | OCM 最紧时 56 B 的记录 |

> `ps_fft_dual/logs/` 在 `.gitignore` 里，所以本次重跑的两份报告**另存了一份进仓库**：
> `dl/evidence_20261027/fp1_util_routed_20261027.rpt` 与
> `dl/evidence_20261027/fp1_timing_routed_20261027.rpt`（内容逐字节相同）。
> 这样评委没有 D: 盘的工程也能核对资源与时序的原始表格。
> 产生这些数字的四个 Tcl 脚本也一并入库（`dl/evidence_20261027/*.tcl`），内容与本次运行完全相同。

板端读数（原始快照，2026-10-27 19:12–19:18，同一块 Zynq-7020 工位板）：

```
窗口 A  MB_T_TOTAL=1891977385 T_N=32 SYNC=384909220 CLASS=638589368 QUAL=80841500
        CAM=704354081 PANEL=10897816 TAIL=72378985 PUB=3822
        DIFF_MS=45561402 REG=5685457 AVG=13145974 TK=1628787
        E2E sum/max/n/last = 1529826408 / 108656796 / 32 / 70538362
窗口 B  T_TOTAL=1901617861 T_N=32 SYNC=371785190 CLASS=641866606 QUAL=81937954
        CAM=718490446 PANEL=10899957 TAIL=76631445 DIFF_MS=45607788 REG=5708517
        AVG=10679851 TK=2710816 E2E=1270337055 / 126407002 / 32 / 68452953
窗口 C  T_TOTAL=1704774235 T_N=32 SYNC=303408992 CLASS=564043295 QUAL=81940710
        CAM=672099751 PANEL=10900428 TAIL=72374791 DIFF_MS=54751090 REG=5710992
        AVG=9850257 TK=4202542 E2E=1401358975 / 117698362 / 32 / 29565334
速率    PS_FRAMES 16411→16479（68 帧 / 12.267 s）；CAP_PERIOD 96991 / 114866 us
```
