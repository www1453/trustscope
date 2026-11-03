# 踩坑清单 · 索引

> 这是本技能包中**最重要**的部分。
> 每条都包含 **触发条件 / 现象 / 根因 / 排查步骤 / 修复 / 失效条件 / 来源**。

## 按症状反查（推荐用法）

遇到问题时，**先在下表找到症状，再点进对应条目**：

| 你看到的现象 | 去看 |
|---|---|
| 构建"成功"了，但程序行为没变 | [tool-and-build-traps.md](tool-and-build-traps.md) § T1 |
| **改了 RTL 重新构建烧板，行为与改动前逐位相同** | [tool-and-build-traps.md](tool-and-build-traps.md) § **T6** / § **T7** |
| **构建日志写 `Complete!`，但链接的是过期缓存** | [tool-and-build-traps.md](tool-and-build-traps.md) § **T6** |
| **构建"失败"、退出码 1，但报错只是一条无害告警** | [tool-and-build-traps.md](tool-and-build-traps.md) § **T8** |
| **工具报 `read-only` / 权限错，但文件属性是正常的** | [tool-and-build-traps.md](tool-and-build-traps.md) § **T9** |
| **`Set-Location` 后 .NET 仍从别处找相对路径** | [tool-and-build-traps.md](tool-and-build-traps.md) § **T10** |
| **函数里的字符串凭空不打印（被 `if` 吞了）** | [tool-and-build-traps.md](tool-and-build-traps.md) § **T11** |
| 比特流下载报 `DONE PIN is not HIGH` / 配置失败 | [tool-and-build-traps.md](tool-and-build-traps.md) § T2 |
| 脚本能跑通但硬件没反应 | [tool-and-build-traps.md](tool-and-build-traps.md) § T3 |
| `.ps1` / `.tcl` 报莫名其妙的括号错误 | [tool-and-build-traps.md](tool-and-build-traps.md) § T5 |
| **功能对但性能差好几倍（Debug 默认 -O0）** | [tool-and-build-traps.md](tool-and-build-traps.md) § T4 |
| 抓到一段"完美稳定"的波形 | [measurement-traps.md](measurement-traps.md) § M1 |
| 从少量数据就得出结论 | [measurement-traps.md](measurement-traps.md) § M2 |
| 测出来的电平和预期不符 | [measurement-traps.md](measurement-traps.md) § M3 |
| 万用表读到"半高"电平，像是坏了 | [measurement-traps.md](measurement-traps.md) § M6 |
| ⭐ **波形漂亮但功能全失败（信号源接错）** | [measurement-traps.md](measurement-traps.md) § M5 |
| **通信全正常但功能完全不工作** | [measurement-traps.md](measurement-traps.md) § M4 |
| **自检报 FAIL，但数据其实是好的** | [measurement-traps.md](measurement-traps.md) § **M7** |
| ⭐ **同一个量每次读都不一样，差几百倍** | [measurement-traps.md](measurement-traps.md) § **M8** |
| ⭐ **"信号恒为 0 / 没有变化" 就直接怪导线** | [measurement-traps.md](measurement-traps.md) § **M9** |
| **一个故障拖了很多轮，最后发现只是没看返回值** | [measurement-traps.md](measurement-traps.md) § **M10** |
| **调试器说 `Blocked address` / 够不到那个寄存器** | [measurement-traps.md](measurement-traps.md) § **M11** |
| ⭐ **"我明明验证过" —— 但证据已经被覆盖了** | [measurement-traps.md](measurement-traps.md) § **M12** |
| ⭐ **自测全过，换成别人给的数据立刻解错** | [measurement-traps.md](measurement-traps.md) § **M13** |
| ⭐ **"目标坏了" —— 其实是你的探测脚本坏了** | [measurement-traps.md](measurement-traps.md) § **M14** |
| BD 修改脚本打印 "done" 但设计没变 | [block-design-traps.md](block-design-traps.md) § B1 |
| 改完 BD 报 `[BD 41-758]` 时钟引脚无有效源 | [block-design-traps.md](block-design-traps.md) § B2 |
| 综合报某个标识符语法错误 | [block-design-traps.md](block-design-traps.md) § B3 |
| 脚本第一次成功、第二次报"已连接" | [block-design-traps.md](block-design-traps.md) § B4 |
| 改了 BD 但改动没生效（忘了保存） | [block-design-traps.md](block-design-traps.md) § B5 |
| ⭐ **CPU 轮询 PL 的完成标志，永远读不到** | [block-design-traps.md](block-design-traps.md) § **B6** |
| **BD 脚本报"参数个数不够"，但参数明明是有的** | [block-design-traps.md](block-design-traps.md) § **B7** |
| **脚本做完前面所有步骤，在最后一步中止** | [block-design-traps.md](block-design-traps.md) § **B8** |
| ⭐ **给 interface 引脚"加负载"，其实把接口绑定换掉了** | [block-design-traps.md](block-design-traps.md) § **B9** |
| **BD 改坏了、修不下去；分不清是环境还是文件** | [block-design-traps.md](block-design-traps.md) § **B10** |
| **Tcl 报 `invalid command name "else"`** | [block-design-traps.md](block-design-traps.md) § **B11** |
| ⭐ **寄存器写进去、回读也对，但它已经不参与选择了** | [measurement-traps.md](measurement-traps.md) § **M47** |
| ⭐ **交付的固件行为和源码对不上，而校验和全对** | [tool-and-build-traps.md](tool-and-build-traps.md) § **T36** |
| ⭐ **屏上是花屏/错帧，但帧缓冲 dump 完全正确** | [measurement-traps.md](measurement-traps.md) § **M38** |
| ⭐ **屏不再更新，但"还亮着"** | [measurement-traps.md](measurement-traps.md) § **M41** |
| ⭐ **重烧 PL 之后屏显示错乱** | [measurement-traps.md](measurement-traps.md) § **M43** |
| ⭐ **换比特流时把屏"锁"住了** | [measurement-traps.md](measurement-traps.md) § **M44** |
| **以为是"死在最前面"，但中间环节全绿** | [measurement-traps.md](measurement-traps.md) § **M40** |
| **新加的寄存器/字段读不到** | [measurement-traps.md](measurement-traps.md) § **M45** |
| ⭐ **同一个 dump 文件，读到的是上一次的内容** | [measurement-traps.md](measurement-traps.md) § **M46** |
| **一个常量今天翻过去、明天又翻回来** | [measurement-traps.md](measurement-traps.md) § **M42** |
| ⭐ **BD 改动后报 `[BD 41-758]` / 时钟源丢失（删网删过头）** | [block-design-traps.md](block-design-traps.md) § **B17b** |
| **改完 BD 想用 git 撤回去 —— 但 BD 根本不在仓库里** | [block-design-traps.md](block-design-traps.md) § **B22** |
| **PS 写的内存 DMA 搬到旧值 / PL 写的新值 CPU 读不到** | [zynq-cache-dma-traps.md](zynq-cache-dma-traps.md)（clean 与 invalidate 是两个方向） |
| **诊断脚本全绿，但结论是错的** | [diagnostic-tool-traps.md](diagnostic-tool-traps.md)（D1–D6 全组） |
| ⭐ **判据永远不通过，而板子自己的字说它干净** | [diagnostic-tool-traps.md](diagnostic-tool-traps.md) § **D6** |
| ⭐ **统计量在"同一块板对自己"时就已经越线** | [measurement-traps.md](measurement-traps.md) § **M53** |
| ⭐ **"这个优化没有收益" —— 用的是看不见收益的统计量和场景** | [measurement-traps.md](measurement-traps.md) § **M54** |
| ⭐ **一个功能自己悄悄变成关的，而且一直关着** | [measurement-traps.md](measurement-traps.md) § **M55** |
| ⭐ **文件被另一个会话同时改 / 第二个调试会话读数全是 `0xFFFFFFFF`** | [tool-and-build-traps.md](tool-and-build-traps.md) § **T48** |
| ⭐ **备份逐文件哈希全过，但 Block Design 还是改过的那个** | [tool-and-build-traps.md](tool-and-build-traps.md) § **T49** |
| ⭐ **用旧判据自己的输出当标签训练出来的模型，每类都输给旧判据** | [measurement-traps.md](measurement-traps.md) § **M56** |
| **只 grep 到构建日志里的 OK 就开始下载** | [build-verification-traps.md](build-verification-traps.md) |

> **条目数（由 `dl/check_casebook_index.py` 数出来，不要手写）**：
> 有编号条目 **147 条** —— T 49 / M 56 / B 30 / zynq 缓存 6 / 诊断工具 D1–D6 共 6；
> 另有 1 条无编号的构建判据（`build-verification-traps.md`）。
> 本索引只覆盖其中 **55 条（37.4%）**：它是高频与高代价条目的入口，**不是全量索引**；
> 未列出的按各文件的 `## ` 标题查。
>
> **编号约定**：T/M/B 连续编号；`b` 后缀（M25b、B17b、T13b…）是**与主编号同主题但独立的另一条**，
> 引用时**必须连字母一起写** —— M25 是"用频谱分析去排除一个它分辨不了的假设"，
> M25b 才是"没有对照组的对比测试不成立"；AGENTS.md 曾把后者写成 M25。
>
> 带 ⭐ 的是**代价最大或最有普适性**的几条。
> （B11 是 Tcl 语言本身的坑，放在 block-design 一节，因为写 BD 脚本时最容易撞上。）
>
> 历史上这里写过"126 条"和"105 条"，两次都只数了一部分 —— 105 那次把 b 后缀条目
> 和 zynq/D 整组漏掉了。数字由脚本生成，改完跑一遍，不要靠记忆。

## 那一批最贵的坑（2026-09-18 / 19）

它们**叠在一起**造成了一个拖了很久的假象，**单独看每一条都不显眼**：

```
T6  构建链接了过期的 OOC 检查点   ->  RTL 改了一整天，一版比特流都没进去
T7  改动"完全无效"却先怀疑别的原因 ->  据此写了一个针对错误原因的第二修复
M8  u32 统计量溢出               ->  每帧耗时读出 1901 / 290 / 2.90 ms 三个矛盾值
M9  "信号恒 0"其实是没驱动        ->  误判成"导线断了"
M10 (void) 丢掉超时返回值         ->  "采集没启动"与"输入恒 0"无法区分
B6  CPU 抓不到 PL 的 20 ns 脉冲   ->  每帧空转 1.9 秒，帧率掉到 0.5 fps
T8  PowerShell 把 stderr 当致命错 ->  构建"失败"，其实只是被无辜中断
M7  自检没被自检                 ->  好数据被判成不可信
M11 JTAG 够不到 PL AXI           ->  放弃"直读"，改走"DDR 快照 + CPU 搬运"
```

**其中三条来自同一个动作 —— "把不可信的东西当成可信的"：**

```
M12 证据被滚动缓冲冲掉           ->  "我明明验证过"，但读的时候已经没了
M13 自测数据证伪不了自己带来的假设 ->  换成 PC 发来的数据，立刻解错（暴露真 bug）
M14 探针本身坏了却拿来下结论      ->  百度/阿里也"挂"了，才反推出尺子是坏的
```

**一条贯穿全部的总原则**：

> **不要在"证据"和"结论"之间少走一步。**
> 每一条都是这个模式：拿到一个看起来合理的数字/现象，
> **跳过了"这个数是怎么来的、它可信吗、我的改动真的生效了吗"这一步。**

**而 M14 给出的结论更重要：**

> **"知道这条纪律"不等于"会执行它"。**
> 唯一有效的办法是把它**变成代码里一个绕不过去的必经步骤** ——
> 于是有了 `templates/ps_lib.ps1` 里的 `Test-ToolWithKnownAnswer`。

## 2026-10-27 那一批：**判据自己先死，然后才轮到板子**

这一天没有烧坏任何东西，也没有新的硬件故障。五条新条目全部来自**判决本身**：

```
M53  三个统计量在同一天被自己的零假设判死   ->  角缺 3-4 格，而地板 141-825 格
D6   参考质量闸门永远不通过                ->  它读的字不在读取集合里（PLUMBING，不是板子）
M54  "帧平均没有收益"                      ->  量的是 sigma，不是判据读的计数；场景里噪声已不在
M55  平均被悄悄写成关，而且保持关着        ->  固件每轮回显主机目标字，一次误写永久生效
T48  两个 agent 改同一个文件 / 两个 xsdb    ->  git status + mtime 才让它可见而不是无声
```

共同点：**没有一条是"工具不会用"。四条是"信了一份不该信的证据"，一条是"连证据的
来源都被别人同时改着"。** 这也是本技能包存在的理由 —— 见顶层 `README.md`。

从这一批里固化出两条可以机械执行的规则，都已经变成脚本而不是纪律：

1. **零假设先行**：任何"先采 population 再定阈值"的计划，先跑两块板的 null
   （`scripts/null_floor.py`，一分钟）；`max(null) >= min(已知缺陷)` ⇒ 统计量判死。
2. **每个闸门打印它的输入**：闸门拒绝时，先看它的输入是 `None` 还是坏值
   （`scripts/readset_lint.py`，离线、不需要板子）。

## 文件

| 文件 | 覆盖范围 | 条目 |
|---|---|---|
| [tool-and-build-traps.md](tool-and-build-traps.md) | 构建系统、比特流打包、脚本编码、PowerShell、超时预算、过期产物、并发写、备份范围 | T 49 |
| [measurement-traps.md](measurement-traps.md) | 波形/寄存器/电平测量与证据的可信度、显示链路、缓存假设、零假设地板 | M 55 |
| [block-design-traps.md](block-design-traps.md) | 用脚本修改 Vivado Block Design、Tcl 语言坑 | B 29 |
| [zynq-cache-dma-traps.md](zynq-cache-dma-traps.md) | PS/PL 共享内存的缓存与 DMA 一致性（PYNQ 段落是按机制推导，未实测） | 6 |
| [diagnostic-tool-traps.md](diagnostic-tool-traps.md) | 诊断工具本身出错：catch 吞赋值、恒过的检查器、探针分辨率、永远不通过的闸门 | D1–D6 |
| [build-verification-traps.md](build-verification-traps.md) | 构建判据：只 grep OK 等于只问"你想让我过吗" | 无编号 |
| [`../templates/ps_lib.ps1`](../templates/ps_lib.ps1) | `Invoke-Native` / `Test-OuterWrite` / `Test-ToolWithKnownAnswer` 等 8 个函数 | — |

## 一条通用原则

> **每个"成功"都必须有独立的证据。**
>
> 构建说成功 → 看**产物的时间戳和大小**。
> 断言说匹配 → 看**匹配到的对象个数**。
> 波形很好看 → **改动信号再抓一次**看它跟不跟。
