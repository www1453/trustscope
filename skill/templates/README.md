# 案例模板

本目录放**可被下一个题目直接套用**的骨架。

| 文件 | 用途 | 适用场景 |
|---|---|---|
| `bd_patch_template.tcl` | Vivado Block Design **增量修改**脚本骨架 | 需要对已有 BD 做可重复的修改 |
| `ps_lib.ps1` | 驱动外部工具（Vivado / Vitis / xsct / make）的 **PowerShell 安全原语库** | 用 PowerShell 调原生命令、做测量、跑构建 |
| `project_skeleton.md` | 仓库骨架 + **文件名只能用纯英文**的机械做法 | 项目开始 / 提交前改名 |
| `report_measurement_chapter.md` | "试过了、量过了、**失败了**"的测量章节骨架 | 实现了一个判据但没成，报告不知怎么写 |
| `claim_ledger.md` | 断言台账：每个结论的证据等级、来源、撤回记录 | 报告定稿前逐行核对 |
| `bringup_checklist.md` | 上板 bring-up：电气 + 软件两条线，含重烧纪律 | 新板第一次上电 / 老板突然不出图 |

> 后四份是 **Markdown 模板**：把它们复制进你的 `report/`，把表格里的行换掉即可。
> 它们与 `bd_patch_template.tcl` / `ps_lib.ps1` 的区别是：那两份是**可执行的骨架**，
> 这四份是**写作与检查的骨架**。两者都要求"每一格都要能填"——
> **填不出来的格子就是还没做的事**，不是需要润色的地方。

---

## `bd_patch_template.tcl` 的设计原则

它不是"一个例子"，而是**把三条纪律固化成了可复制的结构**：

| 原则 | 体现 |
|---|---|
| **幂等** | 创建前查存在、连接前查已连、断开前查已断；重复运行结果一致 |
| **禁止静默失败** | 每个查找都打印；空结果显式 `NOT FOUND`；末尾给 `DONE` / `FAILED` |
| **保护共享基础设施** | 保存前对时钟/复位网做 guard 断言，失败即中止 |

## 使用方法

1. **复制整个文件**，改名为你的补丁脚本（如 `patch_add_my_ip.tcl`）
2. 只修改 `--- 2. The actual patch ---` 这一段
3. **不要动**前面的 helper 和后面的 guard / 终态检查
4. 运行：
   ```
   vivado -mode batch -source patch_add_my_ip.tcl
   ```
   （或工程已打开时在 Tcl Console 里 `source <path>`）

## 预期输出

成功的判据是**逐行可核对**的，例如：

```
Project: <proj>
Active BD: design_1
--- add my ip ---
  Created my_ip_0
  Connected: processing_system7_0/FCLK_CLK0 -> my_ip_0/aclk
--- guards: critical nets must still exist ---
    processing_system7_0/FCLK_CLK0  nets=1
    processing_system7_0/FCLK_CLK1  nets=1
DONE: BD validated and saved.
```

## 失败时怎么判断

| 输出 | 含义 |
|---|---|
| `NOT FOUND` | 某次查找没匹配到对象 —— **不要忽略，先查清再继续** |
| `WARN: connect failed` | 连接失败，后续逻辑建立在错误前提上 |
| `GUARD FAILED: ... NOT saving.` | 共享时钟网被切断，**已中止且未保存**（磁盘设计完好） |
| `FAILED: validate_bd_design rejected the design` | 校验未通过，**同样未保存** |

## 失效条件

- **从零搭建 BD** 时不需要用它 —— 它面向**增量修改**已有设计。
- 如果你的修改涉及**删除整个 IP 并重建**（而不是改连线），
  它的幂等 helper 覆盖不到，需要额外写"已存在则先删除"的逻辑。

---

## `ps_lib.ps1` 的设计原则

**它不是为了"写得更优雅"，而是因为每一条对应的"随手写法"都至少产出过一次错误答案。**

用法：
```powershell
. ".\ps_lib.ps1"
```

| 函数 | 它防的是什么（真实发生过的） |
|---|---|
| `Invoke-Native` | `$ErrorActionPreference='Stop'` + `2>&1` 让 make 的无害 stderr **终止了整个构建脚本**，退出码 1 —— 而构建本身是好的 |
| `Get-AllDrivesGB` | `Get-PSDrive` 对每个盘都返回 **0.0 GB**（物理上不可能），差点据此判断"磁盘满了" |
| `Test-OuterWrite` | 工具报 `Project is read-only`，而文件属性 `IsReadOnly=False`；裸写入测试 2 秒就定位到是**环境权限**，不是文件 |
| `Test-ToolWithKnownAnswer` | 一个 HTTPS 探针在**百度/阿里上也报失败** —— 探针坏了，却被用来向别人下了"目标网站坏了"的结论 |
| `Find-Files` | `Get-ChildItem -File -Include *.md` 不带 `-Recurse` **静默返回空**，看起来像"没有文档" |
| `Write-Report` | 函数里的裸字符串进了输出流，被 `if (...)` 吞掉 —— **计数对了、明细全没了**，差点当成"脚本就这样打印" |

### 三条硬规则

1. **原生命令一律走 `cmd /c "... > 文件 2>&1"` 再读文件**
   —— 绝不把原生命令的 stderr 并进 PowerShell 管道
2. **路径一律绝对路径**
   —— `Set-Location` **不改** .NET 进程的当前目录，`[System.IO.*]` 会用启动目录
3. **任何测量先用已知答案验证工具**
   —— 这条最重要。**"知道这条纪律"不等于"会执行它"**，
   所以它被做成 `Test-ToolWithKnownAnswer` 这样一个**必经的函数**，
   而不是留在文档里当一句提醒

### 预期输出

```
=== 4. Test-ToolWithKnownAnswer: catch a broken probe BEFORE trusting it ===
    https probe (known broken on this machine)     *** DO NOT TRUST THIS PROBE ***
    http probe (known good)                        TRUSTWORTHY
```

**看到 `TRUSTWORTHY` 才允许把那个探针的结果写进结论。**

### 失效条件

- 纯 PowerShell cmdlet 的工作（不调外部程序）用不到 `Invoke-Native`
- 目标本来就是**不确定**、无法找到"已知答案"时，`Test-ToolWithKnownAnswer` 不适用
  —— 此时应改用**两个独立手段交叉验证**
