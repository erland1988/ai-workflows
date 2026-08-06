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

每个波次按以下顺序处理（合并**全程串行**）：

1. **波内并行编码**：为该波每个模块创建独立 worktree + feature 分支（基于基分支），各派一个**后台** implementer 子代理。每个 implementer 在独立 worktree 内自行完成「实现 → 自审查 → 自修复 → 再审查」循环，主会话不介入。implementer 返回后检查其「顾虑」列是否有遗留问题（详细规则见下方「子代理自循环」章节）。
2. **合并**：逐个模块合并回主工作区（合并铁律，见下）。所有模块都操作基分支，不能同时 merge。
3. **批量更新 ledger**：该波全部模块收尾后，一次性更新 ledger，再进入下一波。

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

精确控制单个模块编码。**同一套流程**，等价于「1 波 1 模块」：创建 worktree + 派后台 implementer（内部自循环）→ 合并 → 更新 ledger。不引入任何单独的执行分支。

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
读取模块 plan.md → 派后台 implementer（波内各模块并行，内部自循环：实现 → 自审查 → 自修复）
  → 检查返回（状态/遗留）→ 合并回基分支 → 更新 ledger
```

各环节详见下方「单模块执行流程」。

**波内并行实施要点**：

- **后台派发**：同波每个模块各派一个 implementer，用后台方式运行（`run_in_background: true`）。各模块 worktree 相互独立，无共享可变状态。
- **收齐再续**：主会话用 `TaskOutput`（`block=true`）等待该波**全部** implementer 完成，才进入后续检查/合并阶段。
- **并发上限**：同波模块数 ≤4 时全部并行；超过则分批（每批 ≤4 个并行，其余排队），避免后台子代理过多导致协调失稳。

**模块 design.md 的风险标注**（低风险/高风险）保留，但**不用于选择执行路径**——它作为附加上下文注入 implementer 提示词，提示子代理对高风险模块（核心逻辑/数据迁移/多文件协调）加强自审。

### 子代理提示词位置

- `subagents/implementer.md`（实现 + 自审查 + 自修复 一体子代理）

### 中间文件生命周期

wip-code 不再生成跨子代理的中间审查文件。implementer 自循环在单次调用内完成，审查直接基于 worktree 当前代码，无需 `full_diff.patch` 之类静态 diff 快照。

## 单模块执行流程

唯一路径，不区分执行载体：

| 步骤 | 执行方 |
|------|--------|
| 创建 worktree | 主会话（coordinator） |
| 执行 Step | 后台 implementer 子代理整模块一次吞入 |
| 自审查→自修复循环 | implementer 内部完成（换审查员视角，详见 `subagents/implementer.md`） |
| 合并 | 主会话（主工作区） |

1. **创建 worktree**：基于基分支（ledger 记录，已校验一致）创建 feature 分支和独立工作区
2. 执行前 `git status` 确认工作区干净
3. **派发后台 implementer**：在提示词中注入 worktree 绝对路径，要求子代理开工前 `pwd` 校验，所有改动限定在 worktree 内。后台运行，波内各模块并行。
4. 收齐该波全部 implementer 后，检查各自返回的「状态」和「顾虑」列——有遗留问题（3 遍自审查未修完）则按**失败策略 A** 或人工介入处理。
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

## 子代理自循环（实现 → 自审查 → 自修复）

**每个模块的编码、审查、修复全部由单个 implementer 子代理在一次调用内完成**。主会话担任 coordinator，只负责 创建 worktree → 派发 → 等待 → 合并。implementer 内部自带「实现 → 自审查 → 自修复 → 再审查 → 完成」循环（详见 `subagents/implementer.md`）。

主会话不在 implementer 运行期间介入审查/修复——那是 implementer 自己的循环。

### 调用契约

| 环节 | 主会话 | implementer |
|------|--------|-------------|
| 实现 | 注入 design/plan/契约/全局约束 | 按 plan.md 逐 Step 实现 + 提交 |
| 自审查 | 不介入 | 换审查员视角全量审视，测试全绿是硬门槛 |
| 自修复 | 不介入 | 发现问题立即修，修完跑测试再进下一遍 |
| 收尾 | 等待返回 | 返回 状态/提交/测试/覆盖率/顾虑/自审清单 |
| 遗留升级 | 看到「顾虑」列遗留问题后决定是否升级 | 3 遍内修不完的如实列在「顾虑」栏 |

- **自审查硬上限 3 遍**：implementer 第 3 遍结束仍有遗留 → 在「顾虑」栏如实列出，不宣布完成
- **测试/编译全绿是每遍通过的硬门槛**：不允许"看代码觉得对就行"
- **主会话兜底**：implementer 返回「完成_有顾虑」带遗留 → 主会话决定是否升级（人工介入 / 重新派发 / 接受并标记 ⚠️）

### 主会话进度汇报模板

implementer 是一次调用，主会话在其运行期间无逐条进度可报。汇报集中在派发与收尾：

```
🚀 [data-models] 派发 implementer（worktree 内实现 + 自审查自修复自循环）
⏳ [data-models] 等待 implementer 返回…
✅ [data-models] implementer 返回：状态=完成，自审查 2 遍修复 3 个，测试全绿
```

### 遗留问题记录格式

implementer 报告遗留问题（3 遍内未修完）时，主会话写入 ledger.md 模块进度表：

```markdown
| data-models | ✅ | ✅ | ✅ | ⚠️ 有限通过 | — | 遗留：L10-缓存 key 无命名空间前缀 |
```

## 断点续传

全自动模式下中途失败或会话中断：

```
wip-code
  → 扫描 ledger.md，发现 data-models 已完成、business-logic 失败
  → 跳过已完成模块，从 business-logic 继续（重新波次划分，仅跑未完成集）
```

也可以通过 `wip-load` 加载上下文后，用 `wip-code <模块名>` 精确恢复单个模块。
