# AgentsInit

一键初始化项目 AI 工具配置，让 **Claude Code** 和 **Cursor** 都能自动读取 `AGENTS.md`。

## 快速开始

```
agents-init        # 一键初始化：.gitignore + AGENTS.md + .claude/ + .cursor/
```

## 功能清单

| 步骤 | 操作 | 说明 |
|------|------|------|
| 1 | 检查/补全 `.gitignore` | 确保 `.claude/` 和 `.cursor/` 被忽略 |
| 2 | 创建 `AGENTS.md` | 项目概述/技术栈/结构/规范/常用命令模板 |
| 3 | 配置 `.claude/CLAUDE.md` | 写入 `@AGENTS.md` 引用 |
| 4 | 配置 `.cursor/settings.json` | 设置 `cursor.rules: "AGENTS.md"` |
| 5 | 输出结果清单 | 展示已创建/修改的文件及状态 |

## 产出物

```
项目根目录/
├── AGENTS.md              # 项目上下文（需手动填充）
├── .gitignore             # 追加 AI 工具配置忽略
├── .claude/
│   └── CLAUDE.md          # → @AGENTS.md
└── .cursor/
    └── settings.json      # → cursor.rules: AGENTS.md
```

## 技能内部结构

```
skills/agents-init/
├── SKILL.md               # 主技能定义 + 详细执行规则
└── README.md              # 本文件
```
