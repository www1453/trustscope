# CNN 集成配方（从 `dl/w6/w6f` 的参考设计反推）

> 来源：解析 `dl/w6/w6f/w6f.srcs/sources_1/bd/design_1/design_1.bd`（JSON），只读。
> **为什么不直接照猜**：往 BD 里加一个 3 个 AXI master + 2 个 AXI-Lite slave 的 IP，
> 没有参考极易接错 —— 而 B12/B13 已经证明"BD 里的连接，看起来和实际经常不是一回事"。
> 这里已经有现成集成过的一份，**读它比猜它可靠得多**。

## 参考设计（w6f）的组件

| cell | VLNV | 作用 |
|---|---|---|
| `ts_cnn_top_0` | `trustscope:rtl:ts_cnn_top:1.0` | **被集成的加速器** |
| `ps7_0_axi_periph` | `xilinx.com:ip:axi_interconnect:2.1` | AXI-Lite 互连（**NUM_MI=3**） |
| `axi_ic_hp0` | `xilinx.com:ip:axi_interconnect:2.1` | 内存互连（**NUM_SI=3, NUM_MI=1**） |
| `dwc_gmem0` | `xilinx.com:ip:axi_dwidth_converter:2.1` | gmem0 位宽转换 |
| `dwc_gmem1` | `xilinx.com:ip:axi_dwidth_converter:2.1` | gmem1 位宽转换 |
| `axi_gpio_obs` | `xilinx.com:ip:axi_gpio:2.0` | 观测寄存器（调试用） |
| `obs_counter_0` | `xilinx.com:module_ref:obs_counter:1.0` | 计数器（调试用） |
| `xlconcat_obs` | `xilinx.com:ip:xlconcat:2.1` | 位拼接 |
| `processing_system7_0` | Zynq PS | |
| `rst_pl` | `xilinx.com:ip:proc_sys_reset:5.0` | 复位 |

**注意 `w6f` 是一个最小测试设计**（没有视频链路），所以它的互连端口数偏小。

## 连接（逐条，来自 `interface_nets` 与 `nets`）

### 时钟 —— 全部挂 `FCLK_CLK0`

```
processing_system7_0/FCLK_CLK0
  → ts_cnn_top_0/clk
  → axi_ic_hp0/ACLK + S00/S01/S02_ACLK + M00_ACLK
  → ps7_0_axi_periph/ACLK + S00_ACLK + M00/M01/M02_ACLK
  → rst_pl/slowest_sync_clk
  → processing_system7_0/S_AXI_HP0_ACLK
  → processing_system7_0/M_AXI_GP0_ACLK
```

### 复位

```
processing_system7_0/FCLK_RESET0_N → rst_pl/ext_reset_in
rst_pl/peripheral_aresetn
  → ts_cnn_top_0/rst_n
  → axi_ic_hp0/ARESETN + 各 S/M ARESETN
  → ps7_0_axi_periph/ARESETN + 各 S/M ARESETN
  → axi_gpio_obs/s_axi_aresetn
```

### AXI-Lite（控制寄存器）

```
processing_system7_0/M_AXI_GP0  →  ps7_0_axi_periph/S00_AXI
ps7_0_axi_periph/M00_AXI        →  ts_cnn_top_0/s_axi_control
ps7_0_axi_periph/M01_AXI        →  axi_gpio_obs/S_AXI
ps7_0_axi_periph/M02_AXI        →  ts_cnn_top_0/s_axi_control_r
```

### 内存数据通路

```
ts_cnn_top_0/m_axi_gmem0  →  dwc_gmem0/S_AXI  →  axi_ic_hp0/S00_AXI  ─┐
ts_cnn_top_0/m_axi_gmem1  →  dwc_gmem1/S_AXI  →  axi_ic_hp0/S01_AXI  ─┼→ axi_ic_hp0/M00_AXI
ts_cnn_top_0/m_axi_gmem2  ───────────────────→  axi_ic_hp0/S02_AXI  ─┘        │
                                                                                v
                                                              processing_system7_0/S_AXI_HP0
```

**为什么只有 gmem0/gmem1 有 `axi_dwidth_converter`，gmem2 没有**：
从 IP 的 `ts_cnn_top_info.xml`，参数映射是

| 参数 | 走哪个 master |
|---|---|
| `img` | gmem0 |
| `logits` | gmem0 |
| `wq` | gmem1 |
| `mtab` / `stab` / `btab` | gmem2 |

gmem0/gmem1 承载的数据位宽与互连默认不同，所以插了位宽转换器。**照抄这个结构即可。**

## 寄存器映射（PS 侧）

| 段 | 基址 | 范围 | 目标 |
|---|---|---|---|
| `SEG_ts_cnn_top_0_reg0` | **0x43C00000** | 64K | `ts_cnn_top_0/s_axi_control` |
| `SEG_ts_cnn_top_0_reg0_1` | **0x43C10000** | 64K | `ts_cnn_top_0/s_axi_control_r` |
| `SEG_axi_gpio_obs_Reg` | 0x41200000 | 64K | `axi_gpio_obs/S_AXI` |

**M_AXI 的地址段**：gmem0/1/2 各自映射到
`SEG_processing_system7_0_HP0_DDR_LOWOCM`，offset 0，range 1G。

## 集成到 AX7020（`two FFT`）时的差异 —— 这是真正的工作量

`w6f` 是**最小测试设计**，而 `two FFT` 是**完整视频系统**。两者差异决定了集成难度：

| | w6f（参考） | two FFT（目标） |
|---|---|---|
| `S_AXI_HP0` | 空，直接给 CNN | **已占**（`mem_intercon_disp`） |
| `S_AXI_HP1` | 未用 | **已占**（`mem_intercon_cap`） |
| `ps7_0_axi_periph` | 3 个 MI，全用 | 需查有没有空闲 MI |
| `mem_intercon_cap` | 无此 cell | `NUM_SI=1, NUM_MI=1`，**已满** |
| `dwc_*` | 2 个 | 需要新增 |

**所以集成到 AX7020 需要动互连的端口数** ——
这与双目（`axis_switch` 方案）遇到的问题同源，但**双目那边我找到了绕开的办法，CNN 这边绕不开**：
CNN 的 3 个 master 必须有路到 DDR。

**待查（下一步只读侦察）**：
1. `ps7_0_axi_periph` 有没有空闲 MI 端口（不够就得加端口数）
2. `mem_intercon_cap` / `mem_intercon_disp` 哪个更容易扩 `NUM_SI`
3. 是否有空的 HP 端口可另开一条（`S_AXI_HP0/1/2/3`）
4. `FCLK_CLK0` 频率与 CNN 的 6.67 ns 约束是否相容

## 复现这个分析

```cmd
python dl\w6_bd_analyze.py w6f w6d w6c w6a
```

`.bd` 的真实 JSON 结构（**第一版分析器就写错了，记在这里免得再错**）：

```
bd["design"]["components"]      <- IP 实例与端口
bd["design"]["nets"]            <- 普通网络（含 pins）
bd["design"]["interface_nets"]  <- 接口网络（含 interface_ports）
bd["design"]["addressing"]      <- 地址分配
```
**不是** `bd["design"]["bd"]`。

---

# 目标设计（two FFT）的侦察结果 —— 四条硬约束

`ps_fft_dual/cnn_integration_recon.tcl` 已跑（只读）。结论如下。

## ⛔ 约束 1：`ps7_0_axi_periph` **5 个 MI 全用满**

```
NUM_MI = 5
  M00_AXI <-> 已连接
  M01_AXI <-> 已连接
  M02_AXI <-> 已连接
  M03_AXI <-> 已连接
  M04_AXI <-> 已连接
```

CNN 要 2 个 AXI-Lite slave → **必须把 `NUM_MI` 从 5 加到 7**。

## ⛔ 约束 2：两个内存互连**都是 NUM_SI=1, NUM_MI=1**

```
mem_intercon_cap   S00_AXI <- axi_vdma_0_M_AXI_S2MM   （采集）
mem_intercon_disp  S00_AXI <- axi_vdma_1_M_AXI_MM2S   （显示）
```

CNN 有 **3 个 master 要通到 DDR** → 必须把某一个的 **`NUM_SI` 从 1 加到 4**。

## ⛔ 约束 3：**`0x43C00000` 已经被 `v_tc_0` 占了**

```
0x41200000  axi_gpio_0     （相机复位）
0x41210000  axi_gpio_1
0x43000000  axi_vdma_0     （采集）
0x43010000  axi_vdma_1     （显示）
0x43C00000  v_tc_0         <-- 参考设计给 CNN 的地址在这里已被占
```

→ CNN 的控制寄存器要另选基址（建议 **0x43C20000** 与 **0x43C30000**）。

## ⚠️ 约束 4：**`FCLK_CLK0` 是 50 MHz，而 CNN 是按 150 MHz 标定的**

```
FCLK_CLK0 = 50000000 Hz   （50 MHz）
FCLK_CLK1 = 32727272 Hz   （32.7 MHz）
```

HLS 的约束是 `create_clock -period 6.67`（= **150 MHz**），综合出的 Fmax 估计 205 MHz。
**但本设计的 `FCLK_CLK0` 只有 50 MHz。**

→ 若把 CNN 挂在这个时钟域上，它实际跑 **50 MHz**，
**推理时间约为 150 MHz 下的 3 倍**（记录里的 4.813 ms → 约 14.4 ms）。
**仍远低于 200 ms 的单件预算**，所以可以接受；但**报告里必须写实际频率下的时间，不能沿用 150 MHz 的数字**。

**不建议为此新增时钟域**：加时钟向导 + 跨时钟域同步会引入新的 CDC 风险，
而我们已经为 CDC 付过一次代价（9 条违规、WNS −3.79 ns）。

## 其他

| 项 | 值 |
|---|---|
| PS 上可用的 HP | **只有 HP0/HP1 被例化**（PS7 硬件有 4 个） |
| 启用 HP2/HP3 的代价 | **要改 PS7 配置 → `ps7_init` 会变 → 现有已验证的引导流程失效** ⚠️ **不做** |
| `axi_dwidth_converter` | 设计里**一个都没有**，需新增 2 个 |
| BD 现有 cell 数 | 36 |

## 结论：CNN 集成需要 5 处改动

| # | 改动 | 风险 |
|---|---|---|
| 1 | 加入 `ts_cnn_top_0` IP（来自 `dl/hls/ip_v12_verified`） | 低 |
| 2 | `ps7_0_axi_periph`：**NUM_MI 5 → 7** | **中**（互连重配） |
| 3 | `mem_intercon_cap`（或 `_disp`）：**NUM_SI 1 → 4** | **中**（互连重配） |
| 4 | 新增 2 × `axi_dwidth_converter` | 低 |
| 5 | 地址：**0x43C20000** + **0x43C30000**；时钟用 **FCLK_CLK0 = 50 MHz** | 低 |

**第 2、3 项是本集成的主要风险** —— 两者都是"改互连的端口数"，
而这类改动正是 B12/B13 教训的同一个区域。**改前必须先备份 BD，改后必须断言每个原消费方仍在。**
