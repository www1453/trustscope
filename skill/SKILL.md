---
name: fpga-casebook
description: >
  FPGA/Zynq 真实故障案例集 —— 与 fpga-debug-discipline / measurement-discipline 配套的"案例卷"。
  它不是参考手册（那是 xilinx-suite 的事），而是**已经发生过、且每一处有真实代价记录的失败**：
  构建"成功"但链接了过期缓存、interface 引脚被替换绑定、CPU 抓不到 PL 的单周期脉冲、
  PowerShell 把无害 stderr 当致命错误、统计量溢出后仍被当成有效数据、
  用前台 Start-Sleep 等一个十几分钟的构建因而必然超时……
  当前 **144 条有编号条目**：T 48（工具与构建）/ M 55（测量与证据）/ B 29（Block Design 与 Tcl）
  / zynq 缓存 6 / 诊断工具 D1–D6。数字由 `scripts/casebook_index.py`（通用版）或
  `dl/check_casebook_index.py` 生成，不要手写。
  （2026-10-23 与 2026-10-27 两次复核：更早写的"105 条"只数了主编号，漏掉了全部 b 后缀条目
  和 zynq/D 两组；2026-10-27 新增 M53–M55 / T48 / D6。）
whenToUse: >
  ★ 当出现**"看起来成功了，其实没生效"**类现象时，先加载本 skill 反查：
  构建日志写 Complete 但行为没变 / 改了 RTL 重新烧板结果逐位相同 /
  脚本打印 done 但设计没变 / 校验通过了但保存的东西是错的。
  ★ 当出现**"数据看起来合理，但结论互相矛盾"**时：
  同一个量每次读都不一样 / 自检报 FAIL 但数据其实是对的 /
  证据明明验证过却找不到了 / 目标"坏了"而其实是探针坏了。
  ★ 当显示链路出问题（屏花屏 / 屏不更新 / 换比特流后锁屏）时：
  先查 M38 / M41 / M43 / M44 —— 反馈的是"面板最后收到的帧"，不是"当前状态"。
  ★ 当命令报 `timed out after ...ms` / `signal timed out`，或明明传了更大的超时却没生效时：
  先查 T12 —— 多半是"用前台 Start-Sleep 等一个十几分钟的构建"，
  或者是硬上限把请求值静默裁剪到了 10 分钟，而不是工具坏了。
  ★ 在使用 Vivado Tcl 脚本、XSCT、Vitis 构建、PowerShell 驱动外部工具之前，
  先查一遍相关条目可以省掉数小时的返工。
  不适用：需要查 API/命令/流程怎么写 —— 那用 xilinx-suite。
---

# FPGA/Zynq 真实故障案例集

本 skill 不教你"怎么写"，只记录**"哪里会骗你"**——而且是**已经骗到过、留下了代价的**。

## 它和其他 skill 的分工

| 你要做的事 | 用哪个 |
|---|---|
| 忘了某条 Tcl / Vitis API 怎么写、器件怎么配 | `xilinx-suite`（知识型）|
| 需要"操作之前该先确认什么"的检查清单 | `fpga-debug-discipline`（纪律型）|
| 需要判断"这份数据能不能信" | `measurement-discipline`（纪律型）|
| **遇到了怪现象，要反查"这长什么样、上次是谁踩的、怎么定位"** | **本 skill（案例型）** |

## 六个文件

| 文件 | 覆盖 | 条目 |
|---|---|---|
| `pitfalls/tool-and-build-traps.md` | 构建系统、比特流打包、脚本编码、PowerShell、命令超时预算、过期产物、自检可信度、"下载≠复位"、注释里的过期实测值、双缓冲零窗口、未初始化的主机控制字、标称时间当分母、交付物与源码脱钩、**两个 agent 改同一个文件 / 两个调试会话插同一根线（T48）** | T 48 |
| `pitfalls/measurement-traps.md` | 波形/寄存器/电平测量与证据的可信度、内存布局假设、错误归因、"量错了那一段"、逐字节判据、控制量 vs 结果指标、恒等式指标、跨 stage 比较、均值分辨力、分解表分项不相加、寄存器"能存"≠"参与选择"、显示链路（M38–M47）、**零假设地板高于信号（M53）/"没有收益"用的是看不见收益的统计量（M54）/固件回显的主机目标字（M55）** | M 55 |
| `pitfalls/block-design-traps.md` | 用脚本改 BD、Tcl 语言坑、VDMA 多通道寄存器组与帧存选择、调试核造成的时序违规 | B 29 |
| `pitfalls/zynq-cache-dma-traps.md` | PS/PL 共享内存的缓存与 DMA 一致性：clean≠invalidate、L2 开不开、撕裂读、映射为不可缓存。**PYNQ 段落是按机制推导、未实测** | 6 |
| `pitfalls/diagnostic-tool-traps.md` | 诊断工具本身出错：`catch` 吞掉赋值、恒过的检查器、探针分辨率比现象还粗、**永远通不过的闸门（D6）** | D1–D6 |
| `pitfalls/build-verification-traps.md` | 构建判据：只 grep `OK:` 等于只问"你想让我过吗" | 无编号 |
| `pitfalls/README.md` | **症状反查表** —— 从"你看到的现象"直接跳到条目 | 索引 52/144 |

**用症状反查表，不要顺序读。** 但反查表是"高频与高代价条目"的入口，**不是全量索引**：
当前覆盖 52/144（36.1%，由 `scripts/casebook_index.py` 数出），未列出的按各文件 `## ` 标题查。

## 编号约定（引用前先读）

- T/M/B 连续编号；**`b` 后缀**（M25b、B17b、T13b…）是**与主编号同主题、但彼此独立的另一条**。
  引用时**必须连字母一起写**：
  - `M25` = 用频谱分析去"排除"一个它分辨不了的假设
  - `M25b` = 没有对照组的"对比测试"不成立
  - `B17` = 2026-10-17 的复现记录；`B17b` = 机制条目（`delete_bd_objs <net>` 删整条网络）
  - `B18` = 手写 AXI4-Lite 从口地址没到；`B18b` = 验证闸门写成看返回值
- 本项目的 `AGENTS.md` 曾把 `M25b` 写成 `M25`、把 `B18b` 写成 `B18`（2026-10-23 已改）。
  写错编号的代价是：读者按错误编号查到的是一条**内容完全不同的**教训。
- zynq 缓存用"坑 1–6"，诊断工具用 D1–D5；这两组不在 T/M/B 序列里，引用时不要写成 M/T/B。

## 每条都有的两样东西（这是它和网上整理清单的区别）

**1. 真实来源与代价** —— 不是"要注意检查时间戳"，而是：

```
T6  dcp 停留在 09-17 13:44，源文件 09-18 14:55
    -> 一整天的 RTL 修改，一版比特流都没进去，而每次构建都报 Complete!

M8  每帧耗时读出 1901 / 290 / 2.90 ms 三个互相矛盾的值
    -> 同一套代码不可能差 650 倍，是 u32 每 12.88 秒绕回一次

B10 BD 坏版本 94502 字节 -> JSON 手术后 91100 -> generate_target 后 94469
    -> 与出事前的良好版本完全一致，validate 才通过
```

**2. 失效条件** —— 什么时候这条**不该**用：

```
T5  失效：英文系统默认代码页 437/1252，风险低但仍建议 ASCII
M6  失效：连续刷新模式（Free-Run/Roll）的示波器不会踩这个坑
B4  失效：从零搭建 BD 时不需要
```

**没有失效条件的清单会退化成迷信。**

## 可执行部分（比文档更值得接进工作流）

```
scripts/run_selftests.py        一条命令证明这套校验脚本本身是好的（6/6 才算可用）
scripts/readset_lint.py         闸门必须读它判断的那个字段（D6 的机械版本）
scripts/null_floor.py           统计量的零假设地板 vs 已知信号（M53 的机械版本）
scripts/wordmap_check.py        两个名字占了同一个地址（撞号类：M45/M47/T48）
scripts/casebook_index.py       条目数与索引覆盖率；索引指向不存在的条目时以非零退出
scripts/leak_scan.py            多编码（utf-8/utf-8-sig/gbk）泄漏扫描 + 个人路径扫描
scripts/tcl_lint.py             Tcl 机械自检（非 ASCII / 括号 / 行尾 #），来自 ps_fft_dual 的原样副本
templates/ps_lib.ps1            驱动外部工具的安全原语；含 Test-ToolWithKnownAnswer
templates/bd_patch_template.tcl BD 增量修改骨架：幂等 + 禁止静默失败 + 保存前 guard
checks/check_repo_hygiene.ps1   批量检查脚本是否符合本 skill 的纪律
```

> 仓库内的专用版本（`dl/check_casebook_index.py`、`dl/` 下那个编码感知的泄漏扫描脚本、
> `ps_fft_dual/tcl_lint.py`）**保持在原位不动**：`scripts/` 下的是通用版/副本，
> 两边各自能跑，互不依赖。**整理目录不等于搬走工具。**
> 同步到已安装位置仍用 `dl/sync_casebook.py`（仓库 `skill/` → 已安装 skill 的单向同步，
> 逐文件按哈希校验）。

`ps_lib.ps1` 共 8 个函数，其中三个直接对应本项目的真实教训：

| 函数 | 它防的 |
|---|---|
| `Invoke-Native` | `$ErrorActionPreference='Stop'` + `2>&1` 让无害 stderr 终止整个构建脚本 |
| `Test-OuterWrite` | 工具报 `read-only` 而文件属性是正常的 → 其实是环境权限 |
| `Test-ToolWithKnownAnswer` | **坏探针在百度/阿里上也报失败，却被用来下"目标坏了"的结论** |

其余五个（`Select-NativeLine` / `Get-FreeSpaceGB` / `Get-AllDrivesGB` / `Find-Files` / `Write-Report`）
各自也对应一条教训，写在文件内的注释里。

## 最重要的一条结论

> **"知道这条纪律"不等于"会执行它"。**

证据就在本 skill 里：`measurement-discipline` 的第 1 条纪律是"先用已知答案验证测量工具"，
而这个项目的作者**在同一个会话里又违反了它一次**（见 M14）。

**所以：文档型条目只能防"没想过"的情形；
真正减少错误的，是把它变成代码里一个绕不过去的必经步骤** ——
例如构建脚本里的新鲜度断言、诊断脚本里的 SELFCHECK、`Test-ToolWithKnownAnswer`，
以及本 skill 自己的 `scripts/casebook_index.py`（数字由脚本生成，不手写）与
`scripts/run_selftests.py`（检查器先在自己的坏输入上失败一次）。

**加载本 skill 之后，优先做的是把这些"可执行部分"接进当前工作流，而不是读完文档。**
