---
name: wip-rollback
description: wip-code 已开始编码后,需求偏差较多需回到 wip-build 重新讨论时的标准回退动作——清理残留 worktree、丢弃已合并代码、重置 ledger
---

# wip-rollback

wip-code 编码中发现需求问题较多,需回到 wip-build 重新讨论设计时的回退操作。
集中处理三类残留,防止漏步:

| 残留 | 不处理的后果 |
|------|-------------|
| 残留 worktree + feature 分支 | 占用磁盘;wip-code 重跑时的残留检查会误清 |
| 已合并回基分支的旧需求代码 | 新需求重新编码时基线被污染,可能冲突 |
| ledger 模块进度仍标 ✅ | wip-code 断点续传会跳过已完成模块 → 改了设计却不重做代码 |

> ⚠️ **破坏性命令**:会丢弃编码进度与 worktree,并改写基分支历史。所有破坏步骤执行前二次确认。

## 调用方式

```
wip-rollback              → 回退全部编码进度
wip-rollback <模块名>      → 只回退指定模块,其余模块已完成编码保留
```

## 执行流程

### 步骤 1:加载状态,列出回退清单

读取 `ledger.md`(当前阶段/基分支/模块进度表),执行:

```bash
git branch --show-current
git status --short
git branch | grep "feature/"
git worktree list
```

汇总为回退清单:

- **未合并模块**:`git worktree list` 中路径含 `.wip/worktrees/` 的模块 → 步骤 3 清理
- **已合并模块**:ledger 模块进度表「编码」列已 ✅ 的模块 → 步骤 4 丢弃基分支代码
- 当前分支 ≠ 基分支时,先提示切回基分支再继续

### 步骤 2:二次确认 + 收掉后台子代理

```
📋 回退清单(全量 / 仅 {module}):

  🧹 将清理的 worktree + feature 分支:
     - .wip/worktrees/{project}/{module}  [feature/{project}-{module}]
  ↩️ 将丢弃的基分支代码:
     - {module}  (自 origin/{base_branch} 起的提交)

⚠️ 确认回退?此操作丢弃编码进度并改写基分支历史,不可恢复!(yes/no)：
```

- wip-code 若仍有后台 implementer/reviewer 子代理在跑,先 `TaskStop` 收掉再确认
- 非 `yes` → 取消,输出"已取消"

### 步骤 3:清理未合并模块的 worktree + 分支

逐个执行(wip-clear 同款逻辑,按命名规范只动本技能分支):

```bash
git worktree remove --force .wip/worktrees/{project}/{module}
git branch -D feature/{project}-{module}
```

- `--force` 丢弃 worktree 内未提交改动——这正是回退目的,无需保留
- worktree 内已有提交时,分支删除前确认该分支未被其他模块依赖

### 步骤 4:丢弃已合并代码(默认 reset,回到远端基线)

先同步远端并核对将丢弃的提交:

```bash
git fetch origin
git log --oneline origin/{base_branch}..{base_branch}
```

- 该区间提交应**全部**是本次 wip-code 合并产生的 → 直接丢弃
- 若混有非本需求提交(本地未 push 的其他改动) → 暂停提示,由用户决定

执行:

```bash
git reset --hard origin/{base_branch}
```

> 前提:该基分支未被他人拉取(改写历史)。多人协作被他人拉取过时,应改用 `git revert` 保留历史——默认场景(单人本地)用 reset 丢弃,不保留无意义编码历史。

### 步骤 5:重置 ledger

- 全量回退:各模块「编码」「审查」「设计」「计划」「检查」列 → ⬜(将覆盖式重写),当前阶段 → `design`
- 单模块回退:该模块「编码」「审查」列 → ⬜,需求若动到设计则该模块「设计」也 → ⬜,阶段 → `design`
- 追加决策记录,标注回退原因

```
### YYYY-MM-DD
- **[wip-rollback]** 回退 {module} 编码进度 —— {原因}（需求变更，回到设计阶段重新讨论）
```

### 步骤 6:提示下一步

```
✅ 已回退。当前阶段: design

📋 下一步: wip-build(覆盖式修正设计/计划)→ wip-check → wip-code
```

## 依赖

无外部脚本。全部由 AI 直接执行 git 与文件操作。
