# AI Collaboration Record（大模型协作记录·索引）

> **正文**：[`report/llm_collaboration.md`](../report/llm_collaboration.md)（人机分工与纠错案例摘要）；**工程细节记录**：[`report/llm_collaboration_evidence.md`](../report/llm_collaboration_evidence.md)（六条主线、任务书引文、文件与提交索引）。本文件是证据索引。

依据赛纲 3.3.3.1（工具限制）、3.3.5.3（设计报告）、3.3.5.5（评分项"大模型协作与技能包"），
本文件是全部协作证据的检索入口。

**协作边界**：大模型提出实现方案与诊断假设；物理操作、证据筛选、结论复核由工程人员完成。
所有判定数字由 `tools/` 脚本从 `data/` 实测 CSV 复算得出，不经大模型转述（复算命令见 README §3.2）。
完整历史会话未逐条存档，报告 §2.5 已如实声明；现存材料按下面三类组织。

## 1. 提示词与任务书

| 文件 | 内容 |
|---|---|
| `docs/PROMPT_PERF_PUSH.md` | PL 内核性能追进任务书：硬预算 + 分阶段停止判据 + "不追什么"；报告 §2.5 引文一出处（2026-09-25，提交 c55e2f7） |
| `docs/PROMPT_NEXT_SESSION.md`、`docs/PROMPT_NEXT_SESSION_20261021.md`、`docs/PROMPT_NEXT_SESSION_20261023.md` | 跨会话交接任务书：每条含验收条件与禁止事项 |
| `docs/PROMPT_STREAMING.md` | 流式输出链路任务书 |
| `skill/prompts/`（3 模板 + README） | 从协作中提炼、可复用的提示词模板：`prompt_null_first`（先证伪）/ `prompt_retraction`（撤回错误主张）/ `prompt_subagent_brief`（子任务书） |

## 2. 自我纠错轨迹（错误假设 → 测量 → 推翻 → 修正）

| 文件 | 内容 |
|---|---|
| `docs/REVIEW_DEFECTS_20261103.md` | 16 项缺陷单：每项的假设、证伪过程与修复 |
| `docs/REVIEW_FIXES_20261021.md`、`docs/REVIEW_PYTHON_20261030.md` | 评审 → 修复闭环记录 |
| `docs/ROOTCAUSE_CAM1_MASK_20261030.md` | 一次错误归因的完整推翻与重定位 |
| `docs/BUG_camera_vdma_stall.md`、`docs/CLONE_CHECK_20261103.md`、`docs/DELIVERABLE_GAP_20261022.md` | 典型 bug 根因 / 复算一致性核查 / 交付缺口与身份红线扫描 |
| `skill/pitfalls/`（6 份踩坑清单） | 上述纠错提炼成的结构化排查方法：block-design / build-verification / diagnostic-tool / measurement / tool-and-build / zynq-cache-dma |

## 3. 会话交接与工作流

- `docs/HANDOVER_*.md` 系列：每轮工作结束时的交接——已确认事实、未决问题、下一轮指令，
  即智能体工作流的逐日直接证据。
- 报告 §2.5「大模型协作与技能提炼」：协作原则（每次聚焦一个问题、预先确定验收与停止条件、
  证据由工程人员复核）、模型主张表（表 5）与两段任务书引文。
- `skill/SKILL.md` 与 `skill/` 各子目录：提示词工作流、案例模板、校验脚本、踩坑清单四类，
  每项含适用范围、使用方法与失效条件（赛纲 3.3.5.2）。
- `docs/` 其余日期化档案为逐日工作底稿，按文件名日期排序。
