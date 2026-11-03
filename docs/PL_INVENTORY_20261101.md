# PL 设计清单（2026-11-01）—— 一件一行，每行都有可查的文件

> 只新增本文件，未改任何既有文件；未上板、未跑 Vivado。资源/时序数字一律**引用** `dl/PL_CONTRIBUTION_20261101.md`（下称 `PLC`），本文不重新推导。缩写：`XDC` = `ps_fft_dual/vivado/two_fft.xdc`（285 行，与 `submission/board/two_fft.xdc` 同 SHA256 `D2F7A048…E9EFD`）；`timing` = `dl/pl_frontend/baseline_impl_20261024/design_1_wrapper_timing_summary_routed.rpt`；`util` = 同目录 `design_1_wrapper_utilization_placed.rpt`。冒号后为行号。

## 1. PL 设计清单（15 件）

| # | 模块/文件 | 类型 | 做什么 | 规模 / 代价 | 证据文件 |
|---:|---|---|---|---|---|
| 1 | `alinx_ov5640`（实例 `alinx_ov5640_0`，双目两路） | IP | AN5642 的 DVP 并口采集：10 bit 数据 + PCLK/HREF/VSYNC → 内部 RGB → AXI4-Stream | **未测**（厂商 IP 源码在本工程中无资源记录，不估算） | `submission/legacy/fpga_snapshot_20261019/board/alinx_ov5640.v`；`ps_fft_dual/bd_add_analyzer_fe.tcl:13-16`（记 `alinx_ov5640_0` 仍在设计中） |
| 2 | 第二路 16 引脚的**逐脚核对** | constraint | 16 个第二路引脚与厂商 `an5642.xdc` 的 `cmos2_*` 一一对应，并把方向写死：数据/PCLK/HREF/VSYNC=输入，复位=输出，I2C=三态开漏（故无对顶风险） | **16 条 `PACKAGE_PIN`**，第 256–271 行连续 16 行 | `XDC:256-271`（其中 `:272` 是 `CLOCK_DEDICATED_ROUTE FALSE`）；对照表 `ps_fft_dual/vendor/alynx_doc/j10_j11.txt`；成图 `dl/J10_CAMERA_WIRING.md` |
| 3 | 全片引脚落位 | constraint | 出货比特流的物理引脚全集 | **66 条 `set_property PACKAGE_PIN`**（全文 67 处命中，第 277 行那处是注释，不是约束） | `XDC`（`PACKAGE_PIN` 于 :12–:285；第一路相机 :33-45，屏 :51-104） |
| 4 | `axi_iic`（`cam_iic_1`）+ `cam_i2c.c` | IP | SCCB/I2C 配置传感器：写表、回读、曝光；寄存器读不到时返回 `0x100` 哨兵值而非伪造数据 | 驱动 446 行 C | `ps_ui/cam_i2c.c:415-443`；`XDC:251-254,269-270`（`cam_iic_1_io_*` 三态 + 上拉） |
| 5 | `ov5640_table.txt`（303 条寄存器表）+ bring-up 重推 | IP | 720p 模式的完整寄存器序列；**每次 bring-up 都整表重写一遍**——这正是"参考只在一次固件会话内有效"的来源：表被重写后，上一次会话读到的登记值不再代表当前状态 | **303 条**（逐行两条字段全部计入） | `ps_fft_dual/ov5640_table.txt`（303 行）；重推逻辑 `ps_fft_dual/stereo_bringup_byname.tcl:380-397`（表条数不符即 `FATAL`）；结论来源 `dl/BUG_camera_vdma_stall.md:37`；"参考只在一次会话内有效"见 `dl/STEREO_SUCCESS_ROOTCAUSE.md:89`、`dl/HANDOVER_20261016.md:119` |
| 6 | `analyzer_fe.v` | RTL | 逻辑分析仪式取图前端：采样 `ch_i` 或内部图案发生器，渲染 800×480 RGB888 栅格，以 **AXI4-Stream** 输出，顶替相机数据通路 | 281 行；**1,152,000 B/帧** | `ps_fft_dual/rtl/analyzer_fe.v:1-38`（帧格式/字节序实测确认，非假设）；接入 `ps_fft_dual/bd_add_analyzer_fe.tcl` |
| 7 | `ts_cnn_top`（HLS 量化 CNN） | HLS | 5 层量化 CNN 推理，主机加载权重 | **31 ms/次**（≈29–31 ms）、**8/8** 逐位 KAT、**147,672 B** 权重；csynth：31,678 LUT / 44,184 FF / **155** BRAM18 / **153** DSP | `dl/CNN_KAT_20261027.md:13,23,48`（板测）；`dl/hls/hls_proj/sol1/syn/report/ts_cnn_top_csynth.rpt:71` |
| 8 | `xts_cnn_top_hw.h`（AXI-Lite 控制寄存器） | IP | CNN 的 CPU 侧寄存器映射：`ap_ctrl` 在 `0x0`，GIE/IER/ISR 在 `0x4/0x8/0xC`；6 个 64 位指针参数 `img/wq/mtab/stab/btab/logits` 在 `0x10…0x54` | 84 行，10 个寄存器组 | `dl/hls/ip_v12_verified/drivers/ts_cnn_top_v1_0/src/xts_cnn_top_hw.h:30-33,72-83` |
| 9 | `axi_vdma_0` + `axi_vdma_2`（两路到 DDR） | IP | 帧存进 DDR、再取回送屏：`axi_vdma_0` S2MM（cam0）+ MM2S（显示），`axi_vdma_2` 为第二路新增的独立通道 | 2 个 VDMA；`axi_vdma_2` 的加装方式：**一个 cell 都不删** | `ps_fft_dual/stereo_2vdma_v2.tcl:1-12,36`；通道配置 `ps_fft_dual/stereo_bringup_byname.tcl:401,407` |
| 10 | `capture_ram.v` | RTL | 自建探针采样器（**显式 FSM**）：IDLE 同时等 `ctrl_i[31]` 重装填 **与** hsync 上升沿 → FILL 存 LEN 个样本并置 `done` → 采完即**冻结**缓冲，CPU 经 `axi_gpio_1` 读不会被撕裂；用地址/数据窗口取代跑不通的 VDMA S2MM 通路 | 109 行；`LEN=8192` 样本 × 31 bit | `ps_fft_dual/rtl/capture_ram.v:1-27`（FSM 与替代理由）；`XDC:208-223`（模块为 OOC `module_ref`，故约束报"匹配到什么"而非报错） |
| 11 | `spi_gen.v` | RTL | **在 PL 里自己造一个 SPI 主机**，作为自家协议解码通路的已知良好激励源：SCK=100 kHz（`DIV=250`@50 MHz），一次 8 bit 传输 80 µs，每个半周期约 23 个采样点，正好落在 176 µs/220 ns 的采集窗内 | 120 行 | `ps_fft_dual/rtl/spi_gen.v:1-37`（"why it exists" 原文即在此文件头） |
| 12 | 时序约束（`create_clock` / `false_path` / 不用 `clock_groups`） | constraint | 唯一自建时钟 `lcd_pclk` 周期 **30.300 ns**；调试探针 9 条跨域路径按 `set_false_path` 处理并写明理由；**不用** `set_clock_groups -asynchronous`（见第 2 节） | WNS **+0.908 ns**、TNS 0/140,009、WHS **+0.037 ns**、FCLK_CLK0 **50 MHz**、Fmax≈**52.4 MHz** | `XDC:10,178-192,214-223`；`timing:154,157,167,264-266`；总数见 `PLC` §1.2–1.3 |
| 13 | **关键路径在 CNN 里** | constraint（结果） | 最差路径不落在视频通路，而在 `ts_cnn_top_0/inst/gmem2_m_axi_U/.../mem_reg/CLKARDCLK`（RAMB36E1）→ `grp_conv3x3_32_32_32_s_fu_242/.../bl_2_fu_576_reg[2]/D`，slack 0.908 ns，需求 20.000 ns，数据路径 18.730 ns 中布线占 16.605 ns（**88.7%**） | 布线主导 ⇒ 新增逻辑很容易把它推负 | `timing:262-266`；`PLC` §1.3 |
| 14 | `tb_analyzer_fe.v` | testbench | `analyzer_fe` 的自检平台（帧格式/流握手） | 174 行 | `ps_fft_dual/sim/tb_analyzer_fe.v` |
| 15 | `tb_ts_stats.v` + 其它自有 RTL（`axis_sampler.v`、`ts_stats.v`、`ts_stats_axi.v`、`ts_stats_bram.v`） | testbench / RTL | 统计核的 AXI 侧自检与其 RTL 实现 | tb 108 行；其余四件规模**未测** | `ps_fft_dual/rtl/tb_ts_stats.v`；`ps_fft_dual/rtl/ts_stats*.v`、`axis_sampler.v` |

**缺一件、必须点名**：`capture_ram.v` 与 `spi_gen.v` **没有专用 testbench**——全库检索 `tb_capture*` / `tb_spi*` 命中 0（第 10、11 行的"验证"来自顶层 ILA 与寄存器回读，不是单元级仿真）。这是本清单里唯一找不到证据文件的那一行。

### 1.1 为什么单独说一句 `spi_gen.v`

板上**没有可测的 SPI 外设**：相机是 SCCB/I2C 器件，而 AN5642 模块本身是坏的。也就是说，谁想验证自家那条 SPI 解码通路，手上根本没有合格的信号源——拿软件数组喂解码器只能证明"数组喂得对"，证明不了采样器、采集缓冲和游程解码。本项目的处理方式是**在 PL 里造一个已知良好的源**：`spi_gen.v` 就是那个主机，输出经 block design 直接接进采样器的 probe 总线（`bit1..3` = SCK/MOSI/CS_N），于是一条**真的被同一套硬件采到过**的信号被送进解码通路，不必再多接一根线（`spi_gen.v:1-37`）。

这就是评审要看的工程动作：不是"等待有合适的激励"，而是**为自己缺的那块测试基础设施补一件硬件**，并且把参数（`DIV=250` → SCK=100 kHz → 每半周期约 23 个采样点）按采集窗（176 µs / 220 ns）反推着定下来，而不是随手取个数。它和 `capture_ram.v` 是同一件事的两面：**没有可用的测量通道，就自己造一条**。

## 2. 时钟域论证：为什么**不**用 `set_clock_groups -asynchronous`

来源 `XDC:194-200`，原文照录：

```
# WHY NOT set_clock_groups -asynchronous
#   That declares the two clocks unrelated for the WHOLE design.  It would also
#   discard the 42 currently-PASSING clk_fpga_0 -> clk_fpga_1 paths and the v_tc
#   synchronizer above.  Those are real, both clocks come from the same PS PLL,
#   and their passing timing is meaningful evidence that would be thrown away.
#   It would also hide any FUTURE genuine crossing between these domains, which
#   is the opposite of what a constraint is for.
```

中文转述：**不用** `set_clock_groups -asynchronous`，因为那是把两个时钟域**整设计**宣布为互不相关；代价是同时丢掉当前**正在通过**的 42 条 `clk_fpga_0 → clk_fpga_1` 路径和上面那个 `v_tc` 同步器——它们是真的，两个时钟同出 PS 的 PLL，它们通过时序本身就是有意义的证据；更糟的是，这会把**将来**真正的跨域隐藏掉，而约束的作用恰恰相反。同段 `XDC:202-206` 还写明一条不肯藏起来的代价：跨域探针采到的位可能亚稳态，这对"人读的仪器"可接受，对功能数据不可接受，而这条路上没有功能数据；`XDC:208-212` 说明该约束在顶层综合期匹配不到引脚是**预期**的，所以它报告"匹配到了什么"，验收看实现后的 WNS。

为什么这段值得单列：绝大多数学生队的 XDC 是抄模板——时钟组、异步声明、`false_path` 一贴了事，从不说清自己**为什么**这么判；这段不但拒绝了一个更省事的写法，还同时给出了被丢弃路径的**实测条数与 WNS**、给出了接受亚稳态的边界条件。**写下来的推理**比任何"我们很重视时序"的自述都强，因为它可被反驳、可被复核。

## 3. 必须一并说清的四件事（防混读）

- **出货报告是平表**：只有 Slice Logic / Memory / DSP / IO 总计，**没有 hierarchy 段**，所以"哪个模块占多少"在出货网表上没有报告。要出逐模块数必须重建（恢复 10-24 的 BD 重跑实现，25–40 min/次）——**约半天**；原因是出货的 `routed.dcp` 已被 2026-10-28 19:32 的另一版构建覆盖（`PLC` §1.1、§1.4）。
- **10-19 那份报告是另一次构建，里面没有 CNN**：`32,815 LUT`（61.68%）、`109.5 BRAM`（78.21%）、DSP 219、WNS **+1.147 ns**，端点总数 130,143（出货是 140,009，两次构建的端点规模本就不同）（`PLC` §1.1 注；`dl/PERF_RESOURCE_20261019.md:36`）。
- **CNN 自己的 csynth 估算也不是出货配置**：`step3b` 报 LUT **27.8K** / DSP **153** / BRAM **163**（`dl/hls/history/step3b_ts_cnn_top_csynth.rpt:71`），`sol1` 报 31,678 LUT / **155** BRAM18 / 153 DSP。**163（或 155）个 BRAM 装不进出货设计的 138.5**，所以出货的那颗 CNN 是**裁剪过的变体**（csynth 是估算、非出货网表的实测归因，故这里只说"不是同一个配置"，不把它当出货数）。三个数——出货的 138.5 总量、10-19 的另一构建、CNN 的 csynth——**互不相等，不得互相代入**。
- **缺陷判决不在 RTL 里，且这是个带数字的决定**：每帧 2.76 MB（2,764,800 B）先压到每次比较 **28.8 KB**（14,400 格 × int16）= **≈96×**；进 PL 只买到几十毫秒，而 **14 个**候选统计量每迭代一次就要付一次重建。能进 PL 但现阶段选择不进（*able to go into the PL but chosen not to, at this stage*）——`PLC` §2；14 种否证见 `dl/make_works_report.py:133,177`。

_数据来源：本次只读 `ps_fft_dual/vivado/two_fft.xdc`、`ps_fft_dual/rtl/`、`ps_fft_dual/ov5640_table.txt`、`ps_ui/cam_i2c.c`、`dl/hls/`、`dl/CNN_KAT_20261027.md`、`dl/pl_frontend/baseline_impl_20261024/`、`dl/PERF_RESOURCE_20261019.md`；未运行 Vivado、未上板、未改任何既有文件。_
