---
name: wip-clear
description: 清空 .wip/ 目录下的项目内容和 worktree（保留 .wip/ 目录本身与 config.json），含二次确认
---

# wip-clear

清空 `.wip/` 目录下的**项目子目录**和 worktree，释放磁盘空间。**由 AI 直接执行，无需外部脚本。**

> ⚠️ **wip-clear 是「清空内容」，不是「删除目录」**。`wip-clear` 执行后：
> - `.wip/` 目录本身 **必须保留**（后续可随时 wip-init 新项目）
> - `.wip/config.json` **必须保留**（飞书配置跟具体项目无关，清空项目时保留）
> - `docs/wip/` **一律不动**（历史归档文档，不归 wip-clear 管）

## 🔴 红线（绝对禁止，违反即流程错误）

1. **禁止删除 `.wip/` 目录本身**。只允许删除 `.wip/` 下的**子目录**（路径必须以 `*/` 结尾）。
2. **禁止出现以下任何写法**（都会把 `.wip/` 目录连同 config.json 一起删掉）：
   - `rm -rf .wip` / `rm -rf .wip/`（不带子路径通配符）
   - `Remove-Item -Recurse -Force .wip` / `Remove-Item -Recurse .wip\*`（PowerShell 删除目录写法）
   - 任何把 `.wip/` 作为删除目标的命令
3. **删除命令必须在 Bash 工具（Git Bash）执行**，禁止用 PowerShell 工具执行删除。本技能所有 bash 命令默认走 Bash 工具。
4. **`wip-clear` 绝不触碰 `docs/wip/`**，不列出、不删除其中任何文件。

## 完整执行流程

### 步骤 0：前置检查

检查 `.wip/` 是否存在：

```bash
test -d .wip && echo "OK" || echo "MISSING"
```

- `MISSING` → `.wip/` 目录不存在，无需清理，直接输出"没有需要清理的项目"，退出。
- `OK` → 继续。同时记录 config.json 初始状态：
  ```bash
  test -f .wip/config.json && echo "CFG_EXISTS" || echo "CFG_NONE"
  ```

### 步骤 1：展示待删除内容

列出 `.wip/` 下所有内容：

```bash
ls -la .wip/
```

列出 Git feature 分支，并区分「本技能分支」与「其他分支」：

```bash
git branch | grep "  feature/"
```

列出 Git worktree（可能有残留的孤立 worktree）：

```bash
git worktree list
```

> **本技能分支** = 命名规范 `feature/{project}-{module}` 且 project 存在于 `.wip/` 下。**其他 feature 分支**不属于本技能产物，清理时保留。
>
> 若 `git worktree list` 输出包含路径指向 `.wip/worktrees/` 的 worktree，说明有残留。这些 worktree 会在步骤 3 删除 `.wip/` 子目录时一并消失，但其关联的 feature 分支需在步骤 4 单独清理。

### 步骤 2：二次确认

```
📁 .wip/
   ├── order-system-v2/          (done)
   ├── fulfillment-transfer/     (coding)
   ├── order-system/             (design)
   ├── worktrees/                (3 个目录)
   └── config.json               (保留，不动)

🌿 Git feature 分支:
   - feature/order-system-v2-core     (本技能分支，将删除)
   - feature/legacy-experiment        (其他分支，将保留)

⚠️ 确认清空 .wip/ 下的项目内容？此操作不可恢复！(yes/no)：
```

- 输入 `yes` → 继续
- 其他 → 取消，输出"已取消"

> 确认时明确告知用户：`.wip/` 目录本身、`config.json`、`docs/wip/` 均保留。

### 步骤 3：清空 .wip/ 内容

**3a. 判断是否有子目录可删**：

```bash
ls -d .wip/*/ 2>/dev/null || echo "NO_SUBDIR"
```

- `NO_SUBDIR` → 无项目子目录，跳过删除，直接进入步骤 3c 验证。
- 列出版本 → 继续 3b。

**3b. 删除 `.wip/` 下的子目录**（只删子目录，`.wip/config.json` 作为平级文件不受影响）：

```bash
rm -rf .wip/*/
```

> 该命令删除 `.wip/` 下所有**子目录**（项目目录 + worktrees 目录）。路径带 `*/` 结尾，不会命中 `.wip/config.json`，更不会删除 `.wip/` 本身。

**3c. 删除后验证**（必须执行，确认目录与配置未受误删）：

```bash
test -d .wip && echo "✅ .wip/ 目录仍在"
test -f .wip/config.json && echo "✅ .wip/config.json 已保留" || echo "ℹ️ config.json 不存在（初始即无，属正常）"
ls -la .wip/
```

> 若步骤 0 记录为 `CFG_EXISTS` 而此处 config.json 消失 → **流程错误，必须停下排查**，不得继续步骤 4。

### 步骤 4：删除本技能 Git feature 分支

只删除命名规范为 `feature/{.wip 项目}-{模块}` 的分支，**其他 feature 分支保留**：

```bash
# 在 Git Bash 下执行（Windows 主 shell 为 PowerShell，管道命令需走 git bash）
projects=$(ls .wip | grep -vE "config.json|worktrees")
for p in $projects; do
  git branch | grep -E "  feature/$p-" | sed 's/^[* ]*//' | xargs -r git branch -D
done
```

> 非本技能 feature 分支（无 `feature/{项目}-` 前缀）不删除，提示用户自行处理。

### 步骤 5：输出结果

```
✅ .wip/ 已清空（目录与 config.json 保留）

已删除:
  📁 order-system-v2/
  📁 fulfillment-transfer/
  📁 order-system/
  📁 worktrees/
  🌿 feature/order-system-v2-core (branch)

保留:
  📁 .wip/              ← 空目录，可随时 wip-init 新项目
  📄 .wip/config.json   ← 飞书配置
  📁 docs/wip/          ← 历史归档，未动
```

## 异常处理

| 情况 | 处理 |
|------|------|
| `.wip/` 不存在 | 输出"没有需要清理的项目"，退出 |
| `.wip/` 下无子目录 | 跳过删除，仅验证 config.json 后退出 |
| 无 feature 分支 | 跳过步骤 4，仍完成清理 |
| 分支删除失败 | 提示用户手动删除，不阻塞流程 |
| 存在非本技能 feature 分支 | 保留并提示用户，不删除 |
| 步骤 3c 验证 config.json 消失 | **停止，排查原因后向用户报告**，不得继续 |
