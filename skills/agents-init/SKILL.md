---
name: agents-init
description: 初始化项目 AI 工具配置，让 Claude Code、Cursor 和 Cline 都能自动读取 AGENTS.md。检查 .gitignore、创建 AGENTS.md、配置 .clinerules、.claude/ 和 .cursor/。
---

# AgentsInit

初始化项目 AI 工具配置（AGENTS.md + .clinerules + .claude/ + .cursor/），确保 **Claude Code**、**Cursor** 和 **Cline（VS Code 扩展）** 都能自动读取 `AGENTS.md` 作为项目上下文。**所有操作由 AI 直接执行。**

## 执行步骤

按顺序完成：

### 1. 检查并补全 `.gitignore`

读取项目根目录下 `.gitignore`：

- 若文件不存在 → 创建并写入：
  ```
  # AI 工具本地配置
  .claude/
  .cursor/
  .clinerules
  ```
- 若文件存在 → 逐行检查确保包含以下条目（缺失则追加）：
  ```
  # AI 工具本地配置
  .claude/
  .cursor/
  .clinerules
  ```
- 如果已包含 `.claude/`、`.cursor/` 和 `.clinerules`（无论是否有注释头），跳过
- 如果任一缺失，先追加注释行 `# AI 工具本地配置`（若尚未存在），再追加缺失条目

### 2. 创建 `AGENTS.md`

检查项目根目录下 `AGENTS.md` 是否存在：

- 若已存在 → 跳过，提示用户已有 `AGENTS.md`，确认是否覆盖
- 若不存在 → 创建基础模板：

```markdown
# AGENTS.md

## 项目概述

<!-- 简要描述项目是什么、做什么 -->

## 技术栈

<!-- 列出主要技术栈 -->

## 项目结构

<!-- 描述关键目录结构 -->

## 开发规范

<!-- 编码规范、提交规范等 -->

## 常用命令

<!-- 构建、运行、测试等命令 -->
```

> 创建后提示用户根据项目实际情况补充内容。

### 3. 创建 `.clinerules`（Cline 配置）

检查项目根目录下 `.clinerules` 是否存在：

- 若已存在 → 跳过，提示用户已有 `.clinerules`，确认是否覆盖
- 若不存在 → 创建并写入：

  ```markdown
  # 项目规则

  AGENTS.md 是本项目的上下文文件，包含项目概述、技术栈、结构、开发规范和常用命令。
  请先阅读 AGENTS.md 获取项目信息。
  ```

> 此文件让 **Cline**（VS Code AI 编码扩展）在对话中引用 `AGENTS.md` 作为项目上下文。

### 4. 创建 `.claude/CLAUDE.md`

确保 `.claude/` 目录存在（若不存在则创建），写入：

```
@AGENTS.md
```

> 此文件让 Claude Code 自动读取 `AGENTS.md` 作为项目上下文。

### 5. 创建 `.cursor/settings.json`

确保 `.cursor/` 目录存在（若不存在则创建），写入：

```json
{
  "cursor.rules": "AGENTS.md"
}
```

> 此文件让 Cursor 自动引用 `AGENTS.md` 作为项目规则。

### 6. 输出结果

列出已创建/修改的文件清单及状态：

```
✅ 项目 AI 工具配置完成

操作清单：
├── .gitignore             → {已存在/已创建}，{已追加/无需修改}
├── AGENTS.md              → {已创建/已存在（跳过）}
├── .clinerules            → {已创建/已存在（跳过）}  [Cline]
├── .claude/CLAUDE.md      → {已创建/已存在}
└── .cursor/settings.json  → {已创建/已存在}

📋 下一步：
   - 在 AGENTS.md 中填写项目概述、技术栈、开发规范
   - 可使用 /agents-init 随时重新执行
```

## 异常处理

| 情况 | 处理方式 |
|------|---------|
| `AGENTS.md` 已存在 | 提示用户并询问是否覆盖，用户确认后才覆盖 |
| `.clinerules` 已存在 | 提示用户并询问是否覆盖，用户确认后才覆盖 |
| `.claude/` 或 `.cursor/` 创建失败 | 提示权限问题，建议手动创建 |
| `.gitignore` 目录层级错位 | 确保在项目根目录操作，非子目录 |
