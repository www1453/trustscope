# 交接 2026-10-22 晚（这一份覆盖当天早些时候的旧交接）

> **22:15 补充（今晚最后确认的四条，比下面任何内容都重要）**
>
> 1. **完整版 `BIT_20261020_1951.bit` 是对的**。断电后烧它：`cnn=4`、`touch=3`、
>    `cam1`/`iic1`/`vtc` 全在、两路采集 `SR=0x00000000`、**触屏 `MB_TOUCH_OK=1`（PID "911."）**。
>    之前它起不来是 **PS 状态坏了**（反复 `rst -system`+`fpga -f`），断电即恢复。
> 2. **`live14_bitpair.tcl` 里烧的是 `design_1_wrapper_bitpair_50m.bit`（2026-09-27）**——
>    它只含 v_tc + gpio0 + 两路视频，**没有 CNN、没有相机1、没有触屏 GPIO、没有 cam_iic_1**。
>    所以跑一次 live14 就会把触屏所在的 PL 覆盖掉。**这是触屏"一直坏"的真正原因。**
> 3. **传感器初始化必须放在流程末尾**（装完应用、配完通道之后）。放在前面会挂死 PS
>    （所有 AXI 读变成 `0xFFFFFFFF`）。
> 4. 用完整版时：通道干净、触屏活、AEC 读到 `mean=988`（说明有数据进内存），
>    但**渲染循环冻住**（`frames` 不变）。这是唯一剩下的问题，见 `run_complete.tcl`。
>
> **能工作的组合（今晚恢复用，无触屏）**：
> `live14`（09-27 比特流）→ `strict_load_cores` → 显示 `+0x54=+0x58=2400`
> → 实测 `capture live 27802/38400`、`18.7–19.0 fps`、`AEC state=1 clip=0`。


> 板子**主链路是好的**。触屏没通。交付物（报告/视频/GitHub/RAR）**一项未做**。
> 截止 **2026-11-04 18:00**，剩 **12 天**。

---

## 零、新会话开场必做：先把 skill 加载起来（不是读一遍，是 `skill` 工具调用）

这几条纪律今天全部用血换过，**必须在本会话开头就加载**，否则会重犯：

| skill | 什么情况下必须调用 |
|---|---|
| `fpga-casebook` | **动板子之前**第一件事。今天新增两条 case 就在里面：<br>「PS 的 SLCR 被锁死时，之后每一个实验都是假的」<br>「实验必须建立在已知好基线上，且一次只动一个变量」<br>外加一条工具陷阱：结束时带 `exit` 的 Tcl 不能被 `source` |
| `fpga-debug-discipline` | 每次要写/改 Vivado Tcl、BD、XDC、Vitis 裸机代码之前 |
| `measurement-discipline` | 每次要"读一个寄存器/看一个日志/看一眼屏幕"就下结论之前 |
| `claim-discipline` | 每次要说"修好了 / 跑通了 / 可以交付了"之前 |
| `agent-experiment-discipline` | 每次要做 A/B 对照实验之前 |

**建议的开场白（直接粘贴给新会话）**：

> 先 `skill` 调用 `fpga-casebook`、`measurement-discipline`、`fpga-debug-discipline`、
> `claim-discipline`，再读 `dl/HANDOVER_20261022_EVENING.md`。
> 板子主链路是好的（采集/显示/判定/AEC 都正常，19–20 fps），
> 先修触屏的 `touch_last_pid()`，然后立刻开始做交付物（报告/视频/GitHub/RAR）。

---

## 一、现在能跑的（实测，2026-10-22 19:30）

| 项 | 读数 | 判据 |
|---|---|---|
| 采集两路 | store 两次读变化 **23000–27000 / 38400 字节** | 数据在流 |
| 帧率 | **19.0–20.0 fps** | 主循环在转 |
| 显示 | `CR=0x00010003` `HSIZE=2400` `DLYS=2400` `VSIZE=480` | 屏幕有 UI |
| 自动曝光 | `state=1  exp=2666  mean=160  clip=0` | **已收敛，不卡死** |
| 差分 | `WANT_DIFF=1` | — |
| 触屏/放大 | ❌ `MB_TOUCH_OK=0`，GT911 无应答 | 见第四节 |

## 二、可复现的启动流程（每步都有判据）

```
1. 断电 10 秒再上电                       ← 清 SLCR 锁的唯一办法
2. xsdb live14_bitpair.tcl
      判据: "BOOT ASSERTIONS PASSED (table, both channels running, capture live)"
3. xsdb strict_load_cores.tcl
      判据: "image downloaded" + "running"（固件 144,300 字节）
4. 显示寄存器（唯一正确的组合）:
      +0x00 CR    = 0x00010003
      +0x54 HSIZE = 2400      ← 800×3 RGB888
      +0x58 DLYS  = 2400      ← 必须也是 2400！只写 0x54 会出竖条纹
      +0x5C ADDR1 = 0x10800000 (UI_A)
      +0x60 ADDR2 = 0x10A00000 (UI_B)
      +0x50 VSIZE = 480       ← 最后写
5. 最终判据: store 两次读不同 + frames 递增 + AEC state=1
```

## 三、固件开关（`ps_ui/main.c` ≈2374 行）

```c
#define WANT_CNN            0    /* CNN 未接 */
#define WANT_TOUCH          1
#define WANT_DIFF           1
#define WANT_AEC            1
#define WANT_VIDEO_BRINGUP  0    /* 改走外部脚本，固件不配视频 */
```

固件标识 `FW_SRC_HASH 8EE12942`；邮箱 word168/169 读出 `TSC1` / `8EE1`。

## 四、触屏：卡位与下一步（5 分钟）

GT911 在 **PL axi_iic `0x40800000`**，地址 `0x5D`，PID 在 `0x8140`。

已查：`MB_TOUCH_OK=0`、`MB_TOUCH_PID=0`、`MB_TOUCH_ST=0`。
而 `touch_start()` 第一行就写 `g_last_pid = 0xAAAA0000`，固件确认是新构建
（FWID 对得上），**却仍读到 0** ⇒ **`touch_last_pid()` 返回的不是 `g_last_pid`**。

**下一步**：读 `ps_ui/touch.c` 的 `touch_last_pid()` 实现，改对之后邮箱会显示
`0xAAAA0000` 进入 / `0xAAAA0001` 释放线后 / `0xAAAA0002` 读 ID 前 /
`0xEEEEEEEE` I2C 传输失败 / 实际 PID。

**注意**：应用运行时主机 `mrd 0x40800000` 会失败（MMU 路径），
触屏只能靠固件自己发布状态。

## 五、今天踩的坑（已写入 `.dsh/skills/fpga-casebook/pitfalls/`）

| # | 坑 | 修复 |
|---|---|---|
| 1 | **PS SLCR/DAP 锁死**：反复 `rst -system`+`fpga -f` 后 `ps7_init` 在 `0xF8006078` 报 `Blocked address`，**之后所有实验都是假的** | **断电 10 秒**；每次实验前先确认 `ps7_init` 成功 |
| 2 | 显示 `+0x54` 与 `+0x58` **都要 2400** | 只写一个 → 竖条纹 |
| 3 | 结尾带 `exit` 的 Tcl 不能 `source`（静默杀会话） | `Select-String '^\s*exit\s*$'` 扫一遍 |
| 4 | 实验必须建在已知好基线上，一次只动一个变量 | 成功案例：基线 26036 → 只加载固件 26199，一次排除"固件停采集" |

## 六、不要再来一遍

- 不要再怀疑"固件停采集"（已单变量排除）
- 不要再从主机 `mwr/mrd` PL 的 VDMA/axi_iic（MMU 会挡）
- 不要再用 `rst -system` 当"干净加载"（会清 VDMA/显示，且可能触发 SLCR 锁）
- 不要再改采集/显示参数（第二节的组合是能跑的）

## 七、真正剩下的活

1. **触屏**（先修 `touch_last_pid()`）
2. **交付物（最重要，与板子无关）**：技术报告（草稿 `dl/REPORT_UPDATE_DRAFT_20261021.md`）、
   演示视频、GitHub 单提交仓库、RAR 提交包
3. 报告里要写明 CNN 当前是关闭的

## 八、仓库

```
master 最新 4b53359；.gitignore 已排除 submission*.zip 与 _pl_rebuild/
```
