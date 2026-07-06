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

- **当前阶段**：design / coding / review / done
- **模块进度表**：每个模块的 7 列状态
- **详细日志**：最近 8 条操作记录
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
```

### 步骤 5：输出上下文摘要

以结构化格式输出：

```
╔════════════════════════════════════════════════╗
║  📁 {project-name}                            ║
║  当前阶段: coding                              ║
║  创建时间: 2026-07-01 17:46                    ║
╚════════════════════════════════════════════════╝

📋 需求概要:
   订单系统重构 —— PHP Hello World 示例
   单模块 core，1 个变更文件 hello.php

✅ 已完成:
   core: 设计 ✅ 计划 ✅ worktree ✅ 编码 ✅ 合并 ✅

🔄 进行中:
   core: 审查 🔄

📜 最近活动:
   [17:55] core  worktree_merged   已合并 feature/order-system-v2-core 到 main
   [17:55] core  step_complete     Step 1 完成
   [17:52] core  check_passed      wip-check 通过
   [17:50] core  plan_created      执行计划生成

🧠 关键决策:
   [wip-build] 使用 echo 而非 printf —— PHP CLI 场景 echo 更简洁
   [wip-build] 1 Phase 1 Step —— 需求极简，无需多步
   [wip-code] 当前会话执行模式 —— 1 Step 单文件低风险

🌿 Git 状态:
   当前分支: main
   Feature 分支: (无)
   工作区: clean

➡️  下一步建议: wip-review
```

### 步骤 6：输出下一步建议

根据当前阶段自动推断：

| 当前阶段 | 建议 |
|----------|------|
| design | `wip-build` |
| designing/coding（全部未完成） | `wip-code` |
| coding（部分完成） | `wip-code` 继续未完成的模块 |
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
