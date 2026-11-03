# 新会话开场提示词（直接整段复制粘贴）

---

先 `skill` 调用这四个：`fpga-casebook`、`measurement-discipline`、`fpga-debug-discipline`、`claim-discipline`。
然后读 `dl/HANDOVER_20261022_EVENING.md`（开头"22:15 补充"那四条最重要）。

## 板子的现状（2026-10-23 上午，已实测）

**能演示的工作状态**（昨晚恢复出来的，别破坏它）：
```
live14_bitpair.tcl   →  "BOOT ASSERTIONS PASSED ... capture live"
strict_load_cores.tcl → image downloaded + running
显示：+0x54=2400, +0x58=2400, +0x5C=0x10800000, +0x60=0x10A00000, CR=0x00010003, VSIZE=480
实测：capture live 27802–32197/38400 字节变化、18.7–19.0 fps、AEC state=1 clip=0
缺：触屏（这一版比特流没有 touch_gpio）
```

**完整版 `BIT_20261020_1951.bit`**：CNN / 相机1 / 触屏 / cam_iic_1 全在，
`MB_TOUCH_OK=1`、PID="911."，两路采集 `SR=0x00000000` 干净，**但应用渲染循环冻住**
（`frames` 不变，AEC 能读到真实画面 mean≈600）。

## 第一个任务：修 XDC 冲突，让工程能重新构建

**为什么优先**：`place_design` 失败（`failed to commit all instances`），53 条
`pad ... already occupied ... possibly due to user constraint`。**10-20 19:51 是最后一次成功构建**，
之后再没出过新比特流——BD 之后的所有改动都没进过 PL。不修这个，改 BD/固件全白费。

第一步（先看清用户约束）：
```tcl
open_project "D:/BaiduNetdiskDownload/23_ov5640_dual/Vivado/two FFT/two FFT.xpr"
get_files -of_objects [get_filesets constrs_1]
```

报错点名的文件是 `submission/fpga_prize/board/two_fft_j11.xdc` 的
**第 118/119/120/142/143 行**（`vid_io_out_0_data[*]` 与 `cmos_d_0[*]`、
`IIC_0_0_sda_io/scl_io` 抢同一批引脚）。

修法：
1. 对比那份文件与工程自带 `ps_fft_dual/vivado/two_fft.xdc` 的 PACKAGE_PIN 分配；
2. 删掉**重复的那份**（备份已就绪：`backups/20261023_091405__xdc_before_fix_20261023`）；
3. `reset_run synth_1` → `reset_run impl_1` → `launch_runs`（综合 100% 是好的，主要重跑实现）。

新比特流拷到 `safe_bitstreams/` 用**新名字**，别覆盖 10-20 那份。

## 第二个任务（XDC 修好之后）：让触屏和采集同时成立

> **2026-10-23 事后注（这一节已过期，别再照做）**：`probe_stream.tcl` 已归档到
> `C:\Users\wzh\Documents\fpga旧文件\02_被取代的完整流程\`。它缺 FCLK 修复、v_tc 时序与显示几何，
> 因此无论位流好坏都会给出 "no data"——这个判据当时是无效的。
> 采集的正确做法、以及"板上正常长什么样"，一律看 **`dl/ONBOARD_SCRIPTS.md`**。
> 结论：采集与触屏在 2026-10-23 已同时跑通（`both captures are live` + `MB_TOUCH_OK=1`）。

用新比特流 + `ps_fft_dual/probe_stream.tcl`（**不装应用**，只做：
ps7_init → 烧比特流 → 初始化传感器 → 配两路采集 → 量存储）。

判据一行：`RESULT: data arrives` 还是 `no data`。
- **有数据** → 传感器和通道都好，问题只在应用启动顺序；
- **没数据** → 传感器冷启动后没推流，查配置表。

## 已知的坑（这两天全踩过，别再踩）

1. **PS 的 SLCR 会锁死**：反复 `rst -system`+`fpga -f` 之后 `ps7_init` 报
   `Memory read error at 0xF800xxxx`，**只有断电 10 秒能清**。每次实验前先看到 `ps7_init` 成功。
2. **`live14_bitpair.tcl` 烧的是 09-27 那版**（无触屏/无 CNN）。跑它就会覆盖完整版 PL。
   它的 `set BIT` 路径改过又改回，**动它之前先看清当前值**。
3. **应用运行时主机写 PL 地址会被 MMU 挡**（`0x44A00030`、`0x40800000` 都试过失败）。
   要么在 `con` 之前配，要么让固件自己配。
4. **结尾带 `exit` 的 Tcl 不能 `source`**（会静默杀掉会话）。
5. **一次只改一个变量**，先跑已知好基线（`live14` 那条链）确认它现在还成立。

## 时间

截止 **2026-11-04 18:00**，今天 10-23，剩 **12 天**。
交付物：报告（草稿 `dl/REPORT_UPDATE_DRAFT_20261021.md`）、视频、GitHub、RAR —— **一项都还没做**。
XDC 修好之后如果构建仍失败，**立刻转交付物**，别再耗在板子上。
