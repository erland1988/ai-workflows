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

同时列出 Git feature 分支：

```bash
git branch | grep "  feature/"
```

### 步骤 2：二次确认

```
📁 .wip/
   ├── order-system-v2/          (done)
   ├── fulfillment-transfer/     (coding)
   ├── order-system/             (design)
   └── worktrees/                (3 个目录)

🌿 Git feature 分支:
   - feature/order-system-v2-core

⚠️ 确认清空 .wip/ 全部内容？此操作不可恢复！(yes/no)：
```

- 输入 `yes` → 继续
- 其他 → 取消，输出"已取消"

### 步骤 3：删除 .wip/ 内容

```bash
rm -rf .wip/*/
```

只删除 `.wip/` 下的**子目录**（项目目录 + worktrees 目录）。`.wip/config.json` 作为平级文件不受影响，保留飞书配置。

### 步骤 4：删除 Git feature 分支

```bash
# 获取所有 feature 分支
git branch | grep "  feature/" | awk '{print $1}' | xargs -r git branch -D
```

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
