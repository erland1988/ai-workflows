---
name: wip-code
description: 按 plan.md 执行编码，自动选择执行模式（当前会话/子代理驱动），支持单模块或全自动串行
---

# wip-code

按模块执行计划（plan.md）逐步骤编写代码，**支持两种调用方式**。

## 调用方式

```
wip-code                 → 全自动模式：发现所有未完成模块，按依赖排序，串行逐个执行
wip-code <模块名>         → 单模块模式：精确控制指定模块
```

---

## 全自动模式：wip-code（无参数）★

当用户只输入 `wip-code`，不指定模块时，自动执行：

### 步骤 1：发现项目

- 扫描 `.wip/` 目录，找到所有项目
- 单项目 → 自动选择
- 多项目 → 列出让用户选

### 步骤 2：发现未完成模块

读取 `ledger.md` 的模块进度表，筛选出**编码列为 ⬜ 或 🔄**的模块。

### 步骤 3：按依赖排序

读取 `design.md` 的模块划分表，按「前置依赖」拓扑排序，产出执行序列。

```
示例：
  模块        前置依赖        执行顺序
  data-models  无             ①
  business-logic data-models  ②
  api-endpoints data-models   ②（可与 business-logic 并行，但串行安全）
  auth-validation api-endpoints ③
```

> **不并行**。串行执行更安全——前一个模块合并后，后一个模块基于最新 main 分支开始，避免 merge conflict。

### 步骤 4：展示执行计划

```
📋 执行序列（按依赖排序）：

  ① data-models      ⬜ 待编码
  ② business-logic   ⬜ 待编码
  ③ api-endpoints    ⬜ 待编码
  ④ auth-validation  ⬜ 待编码

共 4 个模块，预计全部完成后建议执行 wip-review。

确认开始？(y/n)，或输入"skip N"跳过指定模块：
```

### 步骤 5：串行执行

逐个模块执行（按 单模块执行流程）。

每个模块完成后：
- ✅ 输出小结：`[data-models] 完成 — 3/3 Step 通过，合并到 main`
- ❌ 失败则暂停，等待人工介入，不继续后续模块

### 步骤 6：完成汇报

```
✅ wip-code 完成

  ① data-models      ✅ 完成
  ② business-logic   ✅ 完成
  ③ api-endpoints    ✅ 完成
  ④ auth-validation  ❌ 失败（Step 2 阻塞）

已暂停，修复后重新执行 wip-code 将从断点继续。

📋 下一步：wip-review
```

---

## 单模块模式：wip-code <模块名>

精确控制单个模块编码。

## 核心机制

**wip-code 自动管理 Git Worktree**：
1. 开始编码前，自动基于当前分支创建 `feature/{project}-{module}` 分支
2. 在 `.wip/worktrees/{project}/{module}/` 独立工作区中编码，不影响主分支
3. 模块全部 Step 完成后，自动合并 feature 分支回基分支
4. 合并后自动清理 worktree 目录和 feature 分支

> Worktree 操作（创建/列出/合并/清理）由 AI 直接执行 `git worktree` 和 `git branch` 命令，无需外部脚本。

## 执行模式（自动判断）

| 信号 | 当前会话执行 | 子代理驱动 |
|------|-------------|-----------|
| 复杂度 | 单文件修改 | 多文件协调 |
| 风险等级 | 低风险 | 高风险（核心逻辑） |
| 测试要求 | 简单单元测试 | 复杂集成测试 |

## 模式 A：当前会话执行

- 在当前 Claude 会话中按 Step 顺序执行
- 适合：低风险、单文件修改的简单模块
- 流程：读取模块 plan.md → 按 Step 执行 → 验证 → 提交 → 合并

## 模式 B：子代理驱动 ★

- 整个模块交给子代理链完成
- 实现子代理 → 审查子代理 → 修复子代理
- 质量更高，适合复杂模块（多文件协调、核心逻辑）

### 子代理驱动流程

```
读取模块 plan.md（全部 Step）
    │
    ├── 派实现子代理 (implementer)
    │       └── 按 Step 顺序执行整个模块
    │       └── 输出：状态 + 所有提交 + 测试结果
    ├── 生成审查包（模块全部 diff）
    ├── 派审查子代理 (reviewer)
    │       └── 输出：规格符合性 + 发现清单
    ├── 判断结果
    │   ├── 通过 → 下一步（合并 + 下一模块）
    │   └── 需修复 → 派修复子代理 (fixer)
    └── 循环直到通过
```

### 子代理提示词位置

- `subagents/implementer.md`（实现子代理）
- `subagents/reviewer.md`（审查子代理）
- `subagents/fixer.md`（修复子代理）

### 中间文件生命周期

wip-code 运行期间会在 `.wip/{project}/` 下生成临时中间文件，用于子代理间传递审查材料：

| 文件 | 生成时机 | 生命周期 | 用途 |
|------|---------|----------|------|
| `full_diff.patch` | 模块整编完成后 | 临时文件，审查通过后自动删除 | 封装整个模块 `git diff` 变更内容，供 reviewer 子代理审查 |

`full_diff.patch` 是审查中间产物，**不属于 wip-review 的产出**。wip-review 直接检查源码和文档，不依赖此文件。

wip-review 不产生新的文档文件——一致性确认后仅更新 `ledger.md`，不生成独立的 `review.md`。

## 单模块执行流程（两种模式通用）

1. **自动创建 worktree**：基于当前分支创建 feature 分支和独立工作区
2. 执行前用 `git status` 确认工作区干净
3. 按 plan.md 的 Step 顺序逐一执行，根据模块复杂度自动选择当前会话或子代理驱动模式
4. 每步执行：编码 → 验证（编译/单测）→ 提交，通过后再进行下一步
5. 若某 Step 失败，暂停并报告问题，等待人工介入
6. 若发现 plan.md 与实际代码有出入，先回写更新 plan.md 再继续，保持文档与代码同步
7. 模块全部 Step 完成后做格式扫尾：确保新增代码与项目既有风格统一
8. **自动合并**：模块所有 Step 通过后，将 feature 分支合并回基分支，清理 worktree
9. **自动更新 ledger.md**：记录每步完成状态、合并信息，在决策记录中追加实现中的关键决策

## 断点续传

全自动模式下中途失败或会话中断：

```
wip-code
  → 扫描 ledger.md，发现 data-models 已完成、business-logic 失败
  → 跳过已完成模块，从 business-logic 继续
```

也可以通过 `wip-load` 加载上下文后，用 `wip-code <模块名>` 精确恢复单个模块。
