# 上板脚本的唯一权威清单（2026-10-23 建立）

> 仓库里有 **5 份** `live14_bitpair.tcl`、**22 份** `ps7_init*.tcl`、**15 份** `two_fft.xdc`、**6 份**
> `stereo_bringup_byname.tcl`。按时间戳挑会挑反：**最新的往往是当天失败的实验**，
> 而验证过的那份可能更旧。
>
> **做板上任何事之前，只从这张表里选文件。表里没有的，先问，不要自己造。**

---

## 一、四个动作，四个文件，别的都不要用

| 动作 | 唯一文件 | 成功的判据（必须看到这一行） |
|---|---|---|
| ① 板上电、配 PL、放相机、写传感器表、配两路采集 | `ps_fft_dual/stereo_bringup_byname.tcl` | `==> both captures are live, and both are LEFT RUNNING` |
| ② 配显示 VDMA 几何 | `ps_fft_dual/disp_fix_20261023.tcl` | `RESULT: display geometry is now set and verified` |
| ③ 装应用（不动 PL） | `ps_fft_dual/strict_load_cores.tcl` | `image downloaded` + `running` |
| ④ 读状态（只读，不下装） | `ps_fft_dual/qc_check_20261023.tcl` | `QC_CHECK_DONE` |

**顺序固定为 ① → ② → ③ → ④。** ② 必须在 ③ 之前：应用运行后主机写 PL 寄存器不可靠。

## 二、配套的固定件

| 用途 | 唯一文件 | 说明 |
|---|---|---|
| PS 初始化 | `ps_fft_dual/GOOD_20261003_cdcfix/ps7_init_cdcfix_50m.tcl` | **不是** `ps_fft_dual/ps7_init_50m.tcl` |
| 传感器寄存器表 | `ps_fft_dual/ov5640_table.txt` | 最终模式 1280x720（`0x3808/09`=0x0500、`0x380A/0B`=0x02D0） |
| 当前位流 | `safe_bitstreams/BIT_20261023_xdcfixed.bit` | 4,045,676 B，SHA256 `5CEF5D86…3113701` |
| 重建位流 | `ps_fft_dual/xdcfix_build_20261023.tcl` | 删冲突 XDC + close_project + 重开校验 + 综合实现 |
| 工程约束（唯一该保留的） | `ps_fft_dual/vivado/two_fft.xdc` | 另有 `dl/touchfix/` 两份与它一致；**`submission/.../two_fft_j11.xdc` 与之互斥，已从工程移除** |
| 固件 | `ps_ui/main.c` + `ps_ui/touch.c` + `ps_ui/mmu.c` … | 用 `ps_ui/build.ps1` 构建（打完会把源码哈希写进镜像） |

### 仓库里还存在、但**不要烧**的比特流

`ps_fft_dual/` 下仍有几份日期不同的 `.bit`。它们被少数老脚本按路径引用（所以没搬走），
但**都不是当前状态**。上板只用上表那个 `safe_bitstreams/BIT_20261023_xdcfixed.bit`。

| 文件 | 它是什么 | 谁还在引用 |
|---|---|---|
| `design_1_wrapper_cdcfix_50m.bit` | 10-03 的 CDC 修复版 | 老 `cdcfix_build.tcl`（产物路径）、`live14_bitpair.tcl` 注释 |
| `GOOD_20261003_cdcfix/design_1_wrapper_cdcfix_50m.bit` | 同上的存档副本 | 无（但同目录的 `ps7_init` 是**必用**的） |
| `design_1_wrapper_bitpair_fix.bit` | 09-27 bitpair 中间版本 | `bitpair_build.tcl`（产物路径） |
| `design_1_wrapper_bitpair_100m.bit` | 09-27 100 MHz 变体 | `fclk100_bitpair_build.tcl`（产物路径） |
| `backup_20260922/design_1_wrapper_20260918_1919.bit` | 09-18 快照 | `capture_and_lcd.tcl`、`run_cam_pclk_probe.tcl` |
| `design_1_wrapper_bitpair_50m.bit` | **09-27 live14 用的那份** | `live14_bitpair.tcl:26` 硬编码 |
| `design_1_wrapper_50m_live14.bit` | 同名变体 | 若干老脚本 |

已经搬到 `C:\Users\user\Documents\fpga旧文件\05_旧比特流\` 的（零引用）：`twoFFT.bit`、
`FFT.bit`×3、`vendor/vendor_pl.bit`、`dl/w6` 的 3 个。

## 三、哪些脚本**不要**再跑（已知是坏的或已被取代）

**2026-10-23 已全部移出仓库**，归档在 `C:\Users\user\Documents\fpga旧文件`，
按失败原因分三类，并附 `README.md` 逐条说明：

| 归档目录 | 里面是什么 |
|---|---|
| `01_判据写错的热poke尝试`（3 个） | 应用运行时热改 PL 寄存器；判据只查一位、读失败返回 0 |
| `02_被取代的完整流程`（9 个） | 漏 FCLK / 漏 v_tc / 漏显示几何 / 顺序错；含 `run_complete.tcl`、`run_newbit_20261023.tcl`、`probe_stream*.tcl` |
| `03_一次性只读诊断`（12 个） | 只读探测片段，结论已并入 `dl/HANDOVER_20261023.md` |

`ps_fft_dual/` 根目录里还有 **730 个历史 `.tcl`**（2.5 MB），是过去三周逐次调试留下的。
它们**没有被逐个复核过**，所以既不能保证可用、也不能保证安全，**一律不要用**；
上面这 5 个是唯一在用的：

```
stereo_bringup_byname.tcl      ①  板级 bring-up
disp_fix_20261023.tcl          ②  显示 VDMA 几何
strict_load_cores.tcl          ③  装应用
qc_check_20261023.tcl          ④  只读状态检查
xdcfix_build_20261023.tcl          重建比特流
```

> 只有 2026-10-23 当天我亲手造成的、以及当天文档明确点名的坏脚本被移走了（24 个）。
> 其余 730 个尚未归档——这是一项待办，不是已经做完的事。归档时要按"是否曾被结论引用"逐批复核，
> 不能整目录一搬了事（`live14_bitpair.tcl` 这种名字多份、内容不同的尤其危险）。

> 归档不删除：它们是一次次误判的证据，删了以后无法复核"当时到底排除了什么"。

## 四、板上"正常"长什么样（用来一眼判断）

```
CAP  SR = 0x00011810      <- err_internal + err_fsz_more 是常态，不是故障
CAP2 SR = 0x00011810      <- 判据只看 bit0(HALTED)：0 = 在跑
DISP CR = 0x00010001      <- bit0=1(RS) 且 bit1=0(Park)；bit1=1 会两帧存交替 → 频闪
VSIZE=480 HSIZE=2400 STRD=2400 ADDR1=0x10800000 ADDR2=0x10A00000
MB_PS_FRAMES              <- 只有 5 s 内的 delta 才有意义（约 16–19 fps）
MB_AEC_STATE = 1          <- 已收敛；0=空闲 2=调整中
MB_LOCAL_VERDICT (150)    <- 0=PASS 1=NG 2=无法判定（板上计算）
MB_TOUCH_OK = 1, MB_TOUCH_PID = 0x39313100  ("911.")
MB_VERDICT/NG/SCORE (2..9) 读成 0xFFFFFFFF  <- 设计如此，判定已改为板上算
```

**不要把单点读数当趋势**：`frames`、`AEC`、`store` 都必须看 delta。
