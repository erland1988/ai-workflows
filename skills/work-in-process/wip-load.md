---
name: wip-load
description: 加载指定项目的完整上下文（进度、决策、Git 状态），用于会话中断后恢复
---

# wip-load

加载指定项目的完整上下文，帮助用户在新会话中快速恢复工作状态。**由 AI 直接执行，不执行下一步操作。**

## 触发方式

```
wip-load <项目名>
```

示例：
- `wip-load "order-system-v2"`
- `wip-load "user-auth-upgrade"`

如果未指定项目名，列出 `.wip/` 下所有可用项目供选择：

```
可用项目:
  1. order-system-v2 (done)
  2. user-auth-upgrade (coding)
  3. payment-refactor (design)

请输入项目名或序号：
```

## 执行流程

### 步骤 1：加载 ledger.md

读取 `.wip/{project}/ledger.md`，提取：

- **当前阶段**：design / check / coding / review / done
- **基分支**：{base_branch}（wip-code 的合并目标，feature 分支从它拉出）
- **模块进度表**：每个模块的 6 列状态
- **详细日志**：最近 10 条操作记录
- **决策记录**：所有决策条目
- **阻塞问题**：如有 BLOCKED 条目

### 步骤 2：加载总体设计

读取 `.wip/{project}/design.md`，提取：

- 需求背景（触发条件、范围边界）
- 模块划分表
- 变更文件汇总

### 步骤 3：加载模块计划

读取 `.wip/{project}/modules/{module}/plan.md`（如有），提取：

- 当前模块的 Phase/Step 结构
- 已完成 / 进行中 / 待执行的 Step
- 变更文件汇总

### 步骤 4：检查 Git 状态

```bash
git branch --show-current
git status --short
git branch | grep "feature/"
git worktree list
```

将当前分支与 ledger 记录的基分支比对：
- **一致** → 无需提示
- **不一致** → 在摘要中醒目提示：当前分支 `{current}` ≠ 基分支 `{base_branch}`，wip-code 会以基分支为合并目标，请确认是否切回基分支再继续

如果 `git worktree list` 输出中包含路径指向 `.wip/worktrees/` 的 worktree，说明有残留的孤立 worktree（会话中断/异常退出等导致未清理）。此时应在摘要中醒目提示：

```
⚠️ 发现 N 个残留 worktree（通常在 .wip/worktrees/ 下）:
   - .wip/worktrees/{project}/{module}  [分支: feature/{project}-{module}]

建议执行 git worktree remove <path> + git branch -D <branch> 清理后再继续。
```

### 步骤 5：输出上下文摘要

以结构化格式输出：

```
╔════════════════════════════════════════════════╗
║  📁 {project-name}                            ║
║  当前阶段: coding  创建时间: 2026-07-01 17:46  ║
╚════════════════════════════════════════════════╝

📋 需求: 订单系统重构 — PHP Hello World，单模块 data-models，1 个变更文件

✅ 已完成: data-models 设计 ✅ 计划 ✅ 检查 ✅ 编码 ✅ 审查 ✅
🔄 进行中: business-logic 编码 🔄

📜 最近活动:
   [17:55] data-models worktree_merged  已合并
   [17:52] data-models reviewer_clear   审查通过（全量发现 + 分组修复）
   [17:50] data-models implementer_done 子代理完成编码
   [17:48] data-models worktree_created Worktree 已创建
   [17:46] data-models plan_created     执行计划生成

🧠 关键决策:
   - [wip-build] 使用 echo 而非 printf（PHP CLI 场景 echo 更简洁）
   - [wip-code] 波次并行编码（单模块,后台子代理驱动）

🌿 Git: 当前分支 {base_branch}（=基分支，一致） | Feature: (无) | 工作区: clean

➡️  下一步: wip-review
```

### 步骤 6：输出下一步建议

根据当前阶段自动推断：

| 当前阶段 | 建议 |
|----------|------|
| design | `wip-build` |
| check | `wip-code` |
| coding | `wip-code` |
| review | `wip-review` |
| done | 项目已完成，`wip-clear` 可清理 |

> ⚠️ wip-load 只输出上下文，**不自动执行下一步**。用户阅读摘要后自行决定。

## 异常处理

| 情况 | 处理 |
|------|------|
| `.wip/{project}` 不存在 | 提示项目不存在，列出可用项目 |
| `ledger.md` 缺失 | 提示账本缺失，仍尝试加载设计文档 |
| 无 `plan.md` | 跳过模块计划，标注"尚未生成执行计划" |
| `.wip/` 为空 | 提示"暂无项目，使用 wip-init 创建" |
