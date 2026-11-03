# 状态记录 2026-10-23 上午（XDC 修复 + 新比特流 + probe_stream）

## 一、XDC 冲突：已修复（E2，可重放）

**根因（机械核对，非推断）**：`constrs_1` 里有 **4 个** XDC，不是 2 个。

| 文件 | PACKAGE_PIN | 与其他文件的关系 |
|---|---|---|
| ps_fft_dual/vivado/two_fft.xdc | 67 | 工程自己的、已验证的那份 |
| dl/touchfix/two_fft_rgb888.xdc | 47 | 同名引脚取值**全部相同**（一致冗余） |
| dl/touchfix/touch_gpio.xdc | 2 | 与 own 在 F19/F20 上一致 |
| submission/fpga_prize/board/two_fft_j11.xdc | 45 | 与 own **45 个端口引脚全部不同** |

j11 是另一套互斥引脚方案（把 LCD 输出映射到 J10/J11 相机脚上）。它独有端口数 = **0**，
所以删掉它不会留下未约束端口（这先堵住了 AGENTS.md 途径② 的"相机脚被配成输出"风险）。

**顺带发现的硬件隐患**：j11 把 **V12 指派为 `lcd_blen`（输出）**，而 V12 在 own 表里是
`cmos_d_0[0]`（相机输入），正是 AGENTS.md 途径① 里 J10 PIN28 那个"绝不能插跳线"的脚。
删掉 j11 同时消掉了这个"输出压相机脚"的隐患。

**今早 09:14 那次同类尝试为什么没生效**：`fix_xdc_conflict.tcl` 调了 `remove_files` 但
**没有保存工程**就 `exit`。Vivado 的工程编辑只在内存里，而 `save_project` 命令**不存在**，
写 .xpr 的动作是 `close_project`（见 `set_top_and_save.tcl` 的记录）。因此 j11 一直在
constrs_1 里，09:11 的 place_design 失败原样重现。

**这次的做法**：删除 → `close_project`（写盘）→ 重新 `open_project` → 读回 `constrs_1`
= 3 个文件 → 才允许构建。日志有 `XDC-PERSISTENCE-VERIFIED`。

脚本：`ps_fft_dual/xdcfix_build_20261023.tcl`（ASCII only，自检过）

## 二、构建：成功（E2）

| 项 | 值 |
|---|---|
| place_design | **completed successfully**（此前 failed to commit all instances） |
| already-occupied 告警 | **0**（此前 36 条 / 53 Critical Warning） |
| impl_1 STATUS | `write_bitstream Complete!`，PROGRESS 100% |
| 时序 | WNS=2.594 / WHS=0.032，`All user specified timing constraints are met` |
| 产物 | 4,045,676 B，mtime 09:45:57（晚于启动 09:22:52） |
| SHA256 | `5CEF5D86DE18FF4F1C68CF68F14A15A09848F3B81D8070AFA098248973113701` |
| 归档 | `safe_bitstreams/BIT_20261023_xdcfixed.bit`（哈希与源一致） |
| 与 10-20 那份 | **不同**（BD 改动进 PL 了，符合预期） |

**引脚方向核验（AGENTS.md 三条红线）**：
- 26 个 `cmos_*` 端口 **全部 INPUT**
- `IIC_0_0_*` / `cam_iic_1_*` **全部 BIDIR**
- `GPIO_0_tri_o[0]=B20`、`[1]=W14` = OUTPUT
- 没有任何 OUTPUT 端口落在相机焊盘上

（注：`.xpr` 里还剩的 3 个 XDC 会在解析时报 9 条 Critical Warning，全是既有无害项：
`aclken_0` 端口不存在、`two_fft_rgb888.xdc` 里 `lcd_touch_i2c_*` 端口已在 BD 里删掉。）

## 三、probe_stream：跑完了，但它测不出"新旧比特流谁好"（E2，结论为阴性）

用新比特流（`probe_stream_newbit_20261023.tcl`）和旧比特流（`probe_stream_oldbit_20261023.tcl`，
只差 BIT 一行）做了 A/B，两次都先断电冷启动、`ps7_init` 均成功（无 FATAL）。

| 项 | 新 (10-23) | 旧 (10-20) |
|---|---|---|
| 传感器 | 两颗都配上（0x56 / 0x5640，303/303 条） | 同 |
| VDMA version (+0x2C) | 未取到（我的对照当时写错） | 0x62000050 |
| S2MM CR / SR | 0x00010002 / 0x00011831 | 0x00010002 / 0x00011831 |
| SR 解码 | halted=1 err_internal=1 err_slave=1 err_fsz_more=1 frame_count=1 | **逐位相同** |
| store 变化 | **0/16** | **0/16** |
| RESULT 行 | INVALID MEASUREMENT（对照写错） | no data |

**结论**：两个比特流行为相同 ⇒ 没有证据表明 BD 改动弄坏了采集通路；
同时这个探针（不装应用）在两版上都拿不到数据，所以它**不能**用来判"新比特流能不能出图"。

**一次自我纠正（记录在案）**：我第一版 CONTROL B 把 `base+0x00` 当 VDMA version 读，
于是每次都报 FAILED。`xaxivdma_hw.h` 的权威定义是：
`TX_OFFSET=0x00`（MM2S 通道基址，故 0x00 是 MM2S_CR）、`RX_OFFSET=0x30`、`VERSION_OFFSET=0x2C`、
`CR_RESET=0x04`。改到 0x2C 后读到 0x62000050，PL 寄存器访问正常。
**这条错误证明"对照也会错"，所以对照本身必须有字面依据，不能凭记忆。**

**未解释项**：两版都在 S2MM 上出现 `ERR_INTERNAL + ERR_SLAVE + ERR_FSZ_MORE`。
`ERR_FSZ_MORE` 字面含义是"帧比预期大"，但传感器用的表与 live14 相同（720p）。
根因**未定位**，可能需要装应用走一遍已知可工作的序列来对比。

## 三·补 选项 A 已跑：新比特流**仍然**冻住渲染循环

脚本 `ps_fft_dual/run_newbit_20261023.tcl` = `run_complete.tcl` 仅 2 行差异（BIT 行 + 探针行），
其余 130 行逐行相同（机械校验过）。断电冷启动 → `ps7_init` 成功 → 烧新比特流 → 装应用
→ 配通道 → 配显示 → 传感器最后。

**新比特流的内容（探针实测，证明它确实是"完整版"）**

| 地址 | 读数 | 结论 |
|---|---|---|
| 0x43C20000 cnn | 0x00000004 | CNN 在 |
| 0x44A00030 cam1 | 0x00010002 | 第二路 VDMA 在 |
| **0x41220000 touch_old** | **NO ANSWER** | 当前 BD 在此无从设备 |
| **0x41230000 touch_gpio** | 0x00000003 | 触屏 GPIO 实际在这里 |
| 0x40800000 iic1 / 0x43C00000 vtc / 0x43010000 disp | 均应答 | 都在 |

**新的触屏根因（很可能就是"触屏一直坏"）**

- 当前 BD：`touch_gpio` @ **0x41230000**（`design_1.hwh` MEMRANGE）
- 固件：`TOUCH_GPIO_BASE = 0x41220000`（`ps_ui/touch.c:65`、`ps_ui/main.c:1474`）
- 0x41220000 在当前 BD 里**不存在** → 固件的读写落空
- `touch.c:65` 自己就有注释 `/* verify against the address editor after the build */`

10-20 那份位流里触屏能读出 PID "911."，说明那时 touch_gpio 在 0x41220000；10-22 的 BD 改动
把它挪到了 0x41230000，固件没跟着改。**这是固件/BD 地址不一致，不是触屏硬件坏。**

**渲染循环：仍然冻住（判据是 delta，不是单点读数）**

| 量 | 值 |
|---|---|
| `MB_PS_FRAMES`（0x10F00028） | 40 → 40，3 秒 delta **0** |
| `0x10000000` 前 8 字 | 全 `FFFFFFFF`（相机数据从未进 DDR） |
| `MB_CAP_TRANS` / `MB_CAP_SAMP` | 0 / 279166 |
| `MB_TEAR` / `MB_TEAR_N` | 0 / 40 |
| S2MM `SR` | 0x00010000（未 halt，但没有数据） |
| `MB_AEC_STATE` / `MB_AEC_MEAN` | 2（调整中）/ 470 |

**自我纠正**：上一步我把单点 `frames=40` 说成"循环在转"，这是错的。
`frames` 是累计计数，只有 delta 才有意义；3 秒 delta=0 才是判据。
（对应 casebook M 组"单点读数不能当趋势"。）

**与 10-20 那份的差异（不可直接归因）**：10-20 晚上 AEC mean=988 说明有数据进内存；
这次 mean=470 且 store 全 FF。但今晚的对照同时换了固件（`ps_ui.elf` 是 10-23 08:30 构建），
所以"是比特流退步"还是"是固件不同"**没有分离**，不能下结论。

## 三·补2 屏幕观察 + 我这次踩的两个新坑（值得进案例集）

操作者实测（人眼，agent 无权宣布）：**"有 UI，但画面是静止的，而且一直频闪。"**

由此可以定位的一件事：`run_complete.tcl` 写显示 CR = `0x00010003`，而本报告第 5 章 A 段的
实测结论是 `MM2S_VDMACR` bit1 为 `Circular_Park`（**0=Park，1=Circular**，PG020），
正确值是 `0x00010001`。Circular 模式让显示端在 A/B 两块帧存之间按扫描率来回读，
而两块里是两帧不同的画面（实测 `UI_A=0x10800000` 与 `UI_B=0x10A00000` 内容完全不同）
→ **这就是"静止 + 频闪"**。已在 `run_newbit_20261023.tcl` 里改为 `0x00010001`。

**坑 D6（新）：兜底值伪装成有效读数。**
我的 `RD` 写成 `set v 0; catch {set v [mrd ...]}`，读失败时返回 **0**。
而 `CR=0` 恰好是"通道停止"的合法编码 → 我把"读失败"读成了"通道被停"。
兜底值必须是不可能出现的值（如 -1）并单独标注，不能是合法寄存器值。

**坑 D7（新）：判据只查一位。**
我判断"已进入 Park 模式"只查了 `bit1==0`，但 `CR=0`（停止）同样满足 bit1==0。
正确判据是两条同时成立：`bit0(RS)==1 && bit1==0`。
**一位判据无法区分"我要的状态"和"更坏的状态"。**

**坑 T48（新，其实早就记在交接里）：应用运行时主机 poke PL 寄存器不可靠。**
交接文档"不要再来一遍"里写着"应用运行时主机写 PL 地址被 MMU 挡"。
我还是直接在应用运行时 `mwr 0x43010000`，结果后续读写全部 `READ-FAILED / write_error=1`，
**唯一能观察屏的寄存器通道因此断掉**。要改显示配置，应改脚本后从冷启动重跑，而不是热 poke。

## 四、下一步的两个选项

- **A**：用新比特流跑一遍已知能工作的演示序列（换 bit 后 live14 等价流程 + `strict_load_cores`），
  确认"采集 live / ~19 fps / AEC state=1 / 触屏 MB_TOUCH_OK"。约 5 分钟，可能需要再断一次电。
  这是唯一能回答"新比特流能不能出图"的测法。
- **B**：立刻转交付物（技术报告 / 演示视频 / GitHub 单提交 / RAR），**一项都还没做**，剩 12 天。
