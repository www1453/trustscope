# 校验脚本

本目录放**提交前自查**用的东西：仓库卫生（结构 / 命名）与烧录前清单。

> **和 `../scripts/` 的分工**：
> `../scripts/` 是**判据的检查**（闸门读没读到、统计量地板、名字撞不撞地址、泄漏扫描），
> 换一个题目也直接用；本目录是**提交动作前的检查**（文件名合不合规、能不能烧），
> 与"提交"这个动作绑定。两边不重复，也都不需要板子（`PRE_BURN_CHECKLIST.md` 是给人看的）。

| 脚本 | 检查什么 | 何时跑 |
|---|---|---|
| `check_repo_hygiene.ps1` | 仓库结构、文件名是否纯英文小写、必需文件是否齐全 | 每次提交前 |

---

## 为什么需要"仓库卫生"检查

竞赛指南明确要求：

> 仓库内所有目录名与文件名须使用**纯英文**（小写字母、数字、下划线或连字符），
> **不得出现中文、空格或特殊字符**，以保证跨平台复现与脚本自动化。
> 中文只出现在文件的正文内容中。

这条要求很容易被忽略 —— 因为在中文 Windows 上，**中文文件名看起来毫无问题**，
但一支陌生队伍在别的系统上 clone 下来就会遇到乱码、脚本失效。
**这正是"可复现性"这项得分的关键。**

## 使用方法

```powershell
cd <repo_root>
powershell -NoProfile -ExecutionPolicy Bypass -File skill/checks/check_repo_hygiene.ps1
```

## 预期输出

```
=== TrustScope repo hygiene check ===
[1] required files
    OK   README.md
    OK   src/
    ...
[2] filename charset (must be ASCII, lowercase, no spaces)
    OK   all 42 paths are clean
[3] staged files / leftovers
    ...
RESULT: PASS
```

## 失败时怎么判断

| 输出 | 含义 |
|---|---|
| `FAIL  path contains non-ASCII` | 有中文/特殊字符路径，**必须改名** |
| `FAIL  missing: <file>` | 缺少必需文件 |
| `RESULT: FAIL` | 存在必须修复的问题 |

## 失效条件

- 它只检查**结构和命名**，**不检查工程本身能否构建** ——
  "能否从零复现"必须由**真正在干净环境跑一遍构建**来验证，脚本替代不了。
