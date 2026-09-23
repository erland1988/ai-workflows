# GitFlow

分支流转发布流水线：从 main 切开发分支，按分支类型流转到 dev / main，并自动打 alpha / rc 预发布 tag。

## 快速开始

```
git-flow start feature 用户中心    # 从 main 切出 feature/用户中心
git-flow dev                       # 合并到 dev + 打 v26.9.2-alpha.1
git-flow main                      # 合并到 main + 打 v26.9.2-rc.1
git-flow status                    # 查看当前卡在流水线哪一步
```

不带子命令时等价于 `git-flow status`，并会引导下一步。

## 流转图

```
                    ┌──────────────────────────────┐
                    │                              │
main ──start──> feature/xxx ──合──> dev ──打──> v26.9.2-alpha.1
  │                   │
  │                   └────合────> main ──打──> v26.9.2-rc.1

main ──start──> hotfix/xxx ──合──> main ──打──> v26.9.4-rc.1
                    │
                    └────合────> dev ──打──> v26.9.4-alpha.1
```

| 类型 | 流转顺序 | 说明 |
|------|---------|------|
| feature | dev → main | 常规需求：先在 dev 测试，再上 main |
| hotfix | main → dev | 紧急修复：先上 main，再回灌 dev |
| bugfix | dev → main | 常规缺陷修复 |

hotfix 先合 main 再回灌 dev，是为了让 dev 不缺失线上修复，避免下次 feature 合并时把旧 bug 带回来。

## 子命令

| 子命令 | 作用 | 副作用 |
|--------|------|--------|
| `start <type> <name>` | 从 main 切 `<type>` 类型分支 | 创建分支，可选推送远端 |
| `dev` | 当前分支 → dev，打 alpha tag | 合并、push、打 tag |
| `main` | 当前分支 → main，打 rc tag | 合并、push、打 tag |
| `status` | 报告流水线进度 | 无（只读） |

## tag 规则

| 目标分支 | 格式 | 示例 |
|---------|------|------|
| dev | `v{YY}.{M}.{N}-alpha.{k}` | `v26.9.2-alpha.1` |
| main | `v{YY}.{M}.{N}-rc.{k}` | `v26.9.2-rc.1` |

- `{YY}.{M}` 取自当前日期，`{N}` 同月递增、跨月重置为 1
- `{k}` 同版本内递增，换版本重置为 1
- 同一分支的 dev / main tag 版本号保持一致
- main 的 `rc.N` 即终态，不打裸版本号

```
feature1 首次合 dev   → v26.9.2-alpha.1
同一 feature 再合 dev → v26.9.2-alpha.2
该 feature 合 main    → v26.9.2-rc.1
新 feature 合 dev     → v26.9.3-alpha.1
```

## 配置

`.claude/git-flow.json`，首次运行时会询问并写入：

```json
{
  "mainBranch": "main",
  "devBranch": "dev",
  "remote": "origin",
  "tagPrefix": "v",
  "tagStage": { "dev": "alpha", "main": "rc" },
  "branchTypes": {
    "feature": { "prefix": "feature/", "flow": ["dev", "main"] },
    "hotfix":  { "prefix": "hotfix/",  "flow": ["main", "dev"] },
    "bugfix":  { "prefix": "bugfix/",  "flow": ["dev", "main"] }
  }
}
```

- 分支名通过 `mainBranch` / `devBranch` 配置，不写死
- `branchTypes` 可自行增删类型，`flow` 数组决定该类型的流转顺序
- 跳步会被拦截：如 hotfix 未合 main 直接执行 `dev`，会提示应先合 main

## 安全约束

技能内置以下硬约束，违反即中止：

1. 绝不 `dev → main`，main 只接受开发分支的合并
2. 合并到 dev/main、推送 tag 各自停下确认
3. 工作区不干净或未同步远端时先停
4. 合并冲突中止，不自动解
5. 同名 tag 拦截
6. tag 创建后必须 push
7. main/dev 上不直接提交
8. 失败时报告「停在哪、副作用是什么、如何退回」

## 技能内部结构

```
skills/git-flow/
├── SKILL.md               # 主技能定义 + 子命令规则 + 红线
└── README.md              # 本文件
```
