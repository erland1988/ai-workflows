---
name: wip-code
description: 按 plan.md 执行编码，基于波次划分的并行流水线（波内并行后台子代理，波间串行），支持单模块或全自动执行
---

# wip-code

按模块执行计划（plan.md）编写代码，**唯一编码路径：波次并行流水线**。

## 调用方式

```
wip-code                 → 全自动模式：发现所有未完成模块，按依赖排序，波次并行逐个波执行
wip-code <模块名>         → 单模块模式：精确控制指定模块（= 1 波 1 模块）
```

---

## 全自动模式：wip-code（无参数）

### 步骤 1：发现项目

- 扫描 `.wip/` 目录，找到所有项目
- 单项目 → 自动选择
- 多项目 → 列出让用户选

### 步骤 2：校验基分支

读取 `ledger.md` 项目信息区的「基分支」字段（wip-init 写入），与当前 git 分支比对：

```bash
git rev-parse --abbrev-ref HEAD
```

- **一致** → 继续
- **不一致** → 提示并停止，等待用户决策。基分支是项目初始化时记录的目标分支，wip-code 的 feature 分支从它拉出、合并回它，绕开它会把开发代码并入错误分支（如发布/备份分支）

> 若 ledger 缺失「基分支」字段（旧项目），以当前分支为准并提示用户在 ledger 中补记。

### 步骤 3：发现未完成模块

读取 `ledger.md` 的模块进度表，筛选出**编码列为 ⬜ 或 🔄**的模块。

### 步骤 4：波次划分

读取 `design.md` 的模块划分表，取「前置依赖」列，按**依赖深度分层**划分为波次：

- **Wave 1**：无前置依赖的模块
- **Wave N**：所有前置依赖都落在 Wave 1..N-1 的模块
- 同一波次内模块**互相无依赖**，可并行
- 波间串行：下一波的所有模块，其前置依赖必须在上一波完成并合并

```
示例：
  模块            前置依赖        波次
  data-models     无             Wave 1
  business-logic  data-models    Wave 2
  api-endpoints   data-models    Wave 2   ← 与 business-logic 无依赖，可并行
  auth-validation api-endpoints  Wave 3
```

**波内文件重叠预检**：并行前，逐个读各模块 `design.md` 的「预估变更」表，两两比对文件路径。有重叠 → 两模块拆到不同波次（或后续合并时人工处理冲突）。预检零成本，挡掉绝大多数潜在合并冲突。

### 步骤 5：展示执行计划

```
📋 执行计划（按依赖波次分组）：

  Wave 1:
    ① data-models      ⬜ 待编码
  Wave 2:
    ② business-logic   ⬜ 待编码
    ③ api-endpoints    ⬜ 待编码   ← 与 ② 并行
  Wave 3:
    ④ auth-validation  ⬜ 待编码

共 4 个模块，3 个波次。预计全部完成后建议执行 wip-review。

确认开始？(y/n)，或输入"skip N"跳过指定模块：
```

### 步骤 6：逐波执行（波内并行 + 波间串行）

每个波次按以下顺序处理（审查/修复/合并**全程串行**）：

1. **波内并行编码**：为该波每个模块创建独立 worktree + feature 分支（基于基分支），各派一个**后台** implementer 子代理（各自在独立 worktree 内跑，互不干扰）。主会话用 `TaskOutput` 阻塞等待该波**全部** implementer 收齐。
2. **审查→修复循环（逐条巡检）**：对每个模块启动增量审查/修复循环——reviewer 每次只找一条问题，fixer 修完 reviewer 验证（仅看修复 diff），通过后再找下一条；严重度单调下降（🔴→🟡→🟢），单模块总轮次硬上限 10 轮。详细规则见下方「审查→修复循环」章节。
3. **合并**：逐个模块合并回主工作区（合并铁律，见下）。所有模块都操作基分支，不能同时 merge。
4. **批量更新 ledger**：该波全部模块收尾后，一次性更新 ledger，再进入下一波。

**失败策略 A（失败隔离）**：

| 失败模块的情况 | 处理 |
|---|---|
| 同波内，但无模块依赖它 | 其余模块继续；该波收尾后汇报失败，流程继续，`wip-code` 重跑时从失败模块续 |
| 同波内，且被下一波依赖 | 该波其余模块跑完 → 流程暂停等待人工介入（修复后重跑下一波） |
| 是波内最后一个/唯一模块 | 暂停等待人工介入 |

> 并行本身带来的失败隔离价值：一个模块挂掉不拖死同波无关模块。仅当失败模块被下一波依赖时才整体暂停——守住「后一波基于最新基分支」的前提。

### 步骤 7：完成汇报

```
✅ wip-code 完成

  Wave 1:
    ① data-models      ✅ 完成
  Wave 2:
    ② business-logic   ✅ 完成
    ③ api-endpoints    ✅ 完成
  Wave 3:
    ④ auth-validation  ❌ 失败（Step 2 阻塞）

已暂停，修复后重新执行 wip-code 将从断点继续。

📋 下一步：wip-review
```

---

## 单模块模式：wip-code <模块名>

精确控制单个模块编码。**同一套流程**，等价于「1 波 1 模块」：创建 worktree + 派后台 implementer → reviewer →（fixer 循环）→ 合并 → 更新 ledger。不引入任何单独的执行分支。

## 核心机制

**wip-code 自动管理 Git Worktree**：
1. **残留检查**：编码前先 `git worktree list` 检查是否已有同名 worktree 残留（上次中断/异常退出所致）。有则先 `git worktree remove <path>` + `git branch -D feature/{project}-{module}` 清理，再创建新的。
2. 开始编码前，自动基于基分支（ledger 记录，已校验一致）创建 `feature/{project}-{module}` 分支
3. 在 `.wip/worktrees/{project}/{module}/` 独立工作区中编码，不影响主分支
4. 模块全部 Step 完成后，自动合并 feature 分支回基分支
5. 合并后自动清理 worktree 目录和 feature 分支

> Worktree 操作（创建/列出/合并/清理）由 AI 直接执行 `git worktree` 和 `git branch` 命令，无需外部脚本。

## 子代理驱动流程（唯一编码路径）

每个模块的编码、审查、修复全部由子代理完成，主会话担任 coordinator。流程概览：

```
读取模块 plan.md → 派后台 implementer（波内各模块并行）
  → 审查→修复循环（逐条巡检，≤10 轮，详见下方章节）
  → 合并回基分支 → 更新 ledger
```

各环节详见下方「单模块执行流程」。

**波内并行实施要点**：

- **后台派发**：同波每个模块各派一个 implementer，用后台方式运行（`run_in_background: true`）。各模块 worktree 相互独立，无共享可变状态。
- **收齐再续**：主会话用 `TaskOutput`（`block=true`）等待该波**全部** implementer 完成，才进入后续审查/修复/合并阶段。
- **并发上限**：同波模块数 ≤4 时全部并行；超过则分批（每批 ≤4 个并行，其余排队），避免后台子代理过多导致协调失稳。

**模块 design.md 的风险标注**（低风险/高风险）保留，但**不用于选择执行路径**——它作为附加上下文注入 implementer 提示词，提示子代理对高风险模块（核心逻辑/数据迁移/多文件协调）加强自审。

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

## 单模块执行流程

唯一路径，不区分执行载体：

| 步骤 | 执行方 |
|------|--------|
| 创建 worktree | 主会话（coordinator） |
| 执行 Step | 后台 implementer 子代理整模块一次吞入 |
| 审查→修复循环 | 主会话编排，reviewer + fixer 逐条巡检（详见下方章节） |
| 合并 | 主会话（主工作区） |

1. **创建 worktree**：基于基分支（ledger 记录，已校验一致）创建 feature 分支和独立工作区
2. 执行前 `git status` 确认工作区干净
3. **派发后台 implementer**：在提示词中注入 worktree 绝对路径，要求子代理开工前 `pwd` 校验，所有改动限定在 worktree 内。后台运行，波内各模块并行。
4. 收齐该波全部 implementer 后，按下方「审查→修复循环」章节执行逐条巡检。
5. Step 失败 → 按**失败策略 A** 处理（失败隔离，仅依赖阻断时暂停）。plan 与代码有出入 → 先回写 plan 再继续
6. 格式扫尾，确保新增代码与项目风格一致
7. **合并**：feature 分支合并回基分支（`{base_branch}`，来自 ledger 项目信息区），清理 worktree
   > ⚠️ **必须在主工作区合并**，禁止在 worktree 目录内 `git merge`（会把基分支反合入 feature，报 "Already up to date" 假合并，详见 SKILL.md「合并铁律」）。无论当前 cwd 在哪，都用下面的模板：
   > ```bash
   > cd "$(git rev-parse --git-common-dir)/.." \
   >   && git checkout "{base_branch}" \
   >   && git merge "feature/$PROJECT-$MODULE"
   > ```
8. **更新 ledger.md**：记录模块级事件、合并信息、关键决策。该波全部模块收尾后批量更新。

## 审查→修复循环（逐条巡检）

implementer 完成后，每个模块进入独立的审查→修复循环。**核心原则：找到一条修一条，修完再找下一条**，避免批量收集问题后黑盒等待。

### 循环结构

```
severity ← 🔴（当前严重度，单调下降）
round ← 0

while round < 10:
    finding ← reviewer("找出当前 diff 中第一个 {severity} 级别的问题，仅报一条")
    if 无:
        severity 降级（🔴→🟡→🟢）
        if 已是最低级（🟢 也无发现）:
            break   // 模块干净，审查通过
    else:
        主会话汇报："[模块名] 发现 {severity} 问题：{finding.summary}"
        fixer 修复该发现
        reviewer 验证（仅看 fixer 的 diff，不做全模块重扫）
        if 通过:
            主会话汇报："[模块名] 已修复，继续巡检…"
        else:
            主会话汇报："[模块名] 修复未通过，重试…"
            继续循环（同一条发现重试，不跳过）
        round ← round + 1

if round >= 10:
    停止，将当前状态写入 ledger 遗留问题列，模块标记 ⚠️ 有限通过
```

### 逐条巡检规则

| 规则 | 说明 |
|------|------|
| **一次一条** | reviewer 每次只找「第一个遇到的问题」，不穷举全部。减少单次 agent 耗时，进度对主会话可见 |
| **严重度单调下降** | 🔴（严重）→ 🟡（重要）→ 🟢（轻微），同一级清空后才降级。不反复横跳 |
| **🟢 可配置** | 🟢（轻微）级别默认「只报不修」——reviewer 发现问题后记入 ledger 备注，但不派 fixer，不消耗轮次。直接跳过继续找下一条 🟢。若项目中 🟢 也需要修，可在模块 design.md 中标注 `fix-cosmetic: true` |
| **验证只扫 fixer diff** | fixer 修完后 reviewer 只验证修复涉及的改动区域，不做全模块重扫。避免 reviewer 在未改动区域嗅出新味道导致无限循环 |
| **硬上限 10 轮/模块** | 单模块审查→修复总轮次 ≤10，到线即停。无论是否干净，剩余问题写入 ledger，模块标记 ⚠️ 有限通过 |
| **同一条重试** | 若修复未通过验证，继续修同一条，不跳过。避免积累未解决问题 |

### 主会话进度汇报模板

每轮巡检时主会话打印一行状态，保持可观测：

```
🔍 [data-models] 巡检中（第 3 轮，已修复 2 个 🔴，当前：🟡）…
✅ [data-models] 🔴 已修复：空指针保护缺失
🔍 [data-models] 巡检中（第 4 轮，已修复 3 个，当前：🟡）…
✅ [data-models] 🟡 已修复：缓存过期策略未设置上限
...
🏁 [data-models] 审查通过（5 轮，修复 4 个：🔴×2 🟡×2，🟢×1 仅记录）
```

### 遗留问题记录格式

硬上限触发或 🟢 跳过时，写入 ledger.md 模块进度表：

```markdown
| data-models | ✅ | ✅ | ✅ | ⚠️ 有限通过 | — | 遗留：L10-缓存 key 无命名空间前缀(🟢) |
```

## 断点续传

全自动模式下中途失败或会话中断：

```
wip-code
  → 扫描 ledger.md，发现 data-models 已完成、business-logic 失败
  → 跳过已完成模块，从 business-logic 继续（重新波次划分，仅跑未完成集）
```

也可以通过 `wip-load` 加载上下文后，用 `wip-code <模块名>` 精确恢复单个模块。
