---
name: wip-clear
description: 清空 .wip/ 目录下的所有项目，含二次确认
---

# wip-clear

清空 `.wip/` 目录下的所有项目和 worktree，释放磁盘空间。**由 AI 直接执行，无需外部脚本。**

> ⚠️ **不删除 `.wip/config.json`**。飞书配置跟具体项目无关，清空项目时保留。

## 完整执行流程

### 步骤 1：展示待删除内容

列出 `.wip/` 下所有内容：

```bash
ls -la .wip/
```

同时列出 Git feature 分支，并区分「本技能分支」与「其他分支」：

```bash
git branch | grep "  feature/"
```

> **本技能分支** = 命名规范 `feature/{project}-{module}` 且 project 存在于 `.wip/` 下。**其他 feature 分支**不属于本技能产物，清理时保留。

### 步骤 2：二次确认

```
📁 .wip/
   ├── order-system-v2/          (done)
   ├── fulfillment-transfer/     (coding)
   ├── order-system/             (design)
   └── worktrees/                (3 个目录)

🌿 Git feature 分支:
   - feature/order-system-v2-core     (本技能分支，将删除)
   - feature/legacy-experiment        (其他分支，将保留)

⚠️ 确认清空 .wip/ 全部内容？此操作不可恢复！(yes/no)：
```

- 输入 `yes` → 继续
- 其他 → 取消，输出"已取消"

### 步骤 3：删除 .wip/ 内容

```bash
rm -rf .wip/*/
```

只删除 `.wip/` 下的**子目录**（项目目录 + worktrees 目录）。`.wip/config.json` 作为平级文件不受影响，保留飞书配置。

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
✅ .wip/ 已清空

已删除:
  📁 order-system-v2/
  📁 fulfillment-transfer/
  📁 order-system/
  📁 worktrees/
  🌿 feature/order-system-v2-core (branch)

随时可开始新项目: wip-init "需求描述"
```

## 异常处理

| 情况 | 处理 |
|------|------|
| `.wip/` 为空 | 输出"没有需要清理的项目"，退出 |
| 无 feature 分支 | 跳过步骤 4，仍完成清理 |
| 分支删除失败 | 提示用户手动删除，不阻塞流程 |
| 存在非本技能 feature 分支 | 保留并提示用户，不删除 |
