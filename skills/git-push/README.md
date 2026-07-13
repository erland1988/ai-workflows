# GitPush

一键完成 `git add` → `git commit` → `git push`，提交信息根据代码变更自动生成中文描述。

## 快速开始

```
git-push           # 一键提交并推送（会先展示变更确认）
```

## 流程

```
git status --porcelain
    ↓ 有变更
展示 git diff --stat 并确认
    ↓ 确认
git add .
    ↓
git commit -m "<自动生成的中文提交信息>"
    ↓
git push
    ↓
✅ 推送完成
```

## 提交信息规范

格式：`<type>: <中文描述>`

| type | 说明 |
|------|------|
| feat | 新功能 |
| fix | 修复 Bug |
| refactor | 重构 |
| chore | 构建/工具/配置变更 |
| docs | 文档 |
| style | 代码格式 |
| perf | 性能优化 |
| test | 测试 |
| ci | CI/CD |

## 技能内部结构

```
skills/git-push/
├── SKILL.md               # 主技能定义 + 详细执行规则
└── README.md              # 本文件
```
