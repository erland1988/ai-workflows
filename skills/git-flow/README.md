# GitFlow

分支流转发布流水线：从 prd 切开发分支，按分支类型逐级流转 dev / test / prd，并自动打 alpha / beta / rc 预发布 tag。

## 快速开始

```
git-flow init                      # 初始化配置（首次使用时执行）
git-flow start feature 用户中心    # 从 prd 切出 feature/user-center（中文自动转英文）
git-flow dev                       # 合并到 dev  + 打 v26.9.2-alpha.1
git-flow test                      # 合并到 test + 打 v26.9.2-beta.1
git-flow prd                       # 合并到 prd  + 打 v26.9.2-rc.1
git-flow status                    # 查看当前卡在流水线哪一步
```

不带子命令时：配置不存在则引导执行 `init`，已配置则等价于 `git-flow status` 并引导下一步。

## 流转图

```
prd ──start──> feature/xxx
                  │
                  ├──合──> dev  ──打──> v26.9.2-alpha.1
                  ├──合──> test ──打──> v26.9.2-beta.1
                  └──合──> prd  ──打──> v26.9.2-rc.1

prd ──start──> hotfix/xxx
                  │
                  ├──合──> prd  ──打──> v26.9.4-rc.1
                  ├──合──> test ──打──> v26.9.4-beta.1
                  └──合──> dev  ──打──> v26.9.4-alpha.1
```

| 类型 | 流转顺序 | 说明 |
|------|---------|------|
| feature | dev → test → prd | 常规需求：dev 联调 → test 验收 → prd 上线 |
| hotfix | prd → test → dev | 紧急修复：先上 prd，再逐级回灌 |
| bugfix | dev → test → prd | 常规缺陷修复 |

hotfix 先合 prd 再逐级回灌 test / dev，是为了让下游分支不缺失线上修复，避免下次 feature 合并时把旧 bug 带回来。

## 子命令

| 子命令 | 作用 | 副作用 |
|--------|------|--------|
| `init` | 初始化配置，自动探测 prd / test / dev / 远端，并检查 `.gitignore` | 写入 `.claude/git-flow.json`，必要时追加 `.gitignore` |
| `start <type> <name>` | 从 prd 切 `<type>` 类型分支，中文名自动转英文，同名历史分支先判后清 | 创建分支、可选推送远端，确认后删除同名已完成分支 |
| `dev` | 当前分支 → dev，打 alpha tag | 合并、push、打 tag、切回原分支 |
| `test` | 当前分支 → test，打 beta tag | 合并、push、打 tag、切回原分支 |
| `prd` | 当前分支 → prd，打 rc tag | 合并、push、打 tag、切回原分支 |
| `status` | 报告流水线进度 | 无（只读） |

只有 `init` 会写文件，其余子命令只读；配置缺失时会提示先执行 `git-flow init`。

`dev` / `test` / `prd` 完成或中止后都会切回发起时所在的分支，不会把你留在阶段分支上。

## 分支命名

`start` 的 `<name>` 可用中文，会自动转为简洁的 kebab-case 英文 slug：

| 输入 | 分支名 |
|------|--------|
| 高校 | `feature/university` |
| 用户中心 | `feature/user-center` |
| 订单系统重构 | `feature/order-refactor` |
| 支付超时修复 | `feature/payment-timeout` |

英文输入直接规范化：转小写、空格与下划线转 `-`、剔除特殊字符。翻译取核心语义，不做逐字直译，控制在 3 个词以内。

若生成的同名分支已存在，`start` 会先判断它是否已完成使命（flow 目标全部合入，或相对 prd 无独有提交）：已完成则展示删除命令、确认后删除重建；仍有未合并提交则不动它，提示先推进流水线或换个名字。

## tag 规则

| 目标分支 | 格式 | 示例 |
|---------|------|------|
| dev | `v{YY}.{M}.{N}-alpha.{k}` | `v26.9.2-alpha.1` |
| test | `v{YY}.{M}.{N}-beta.{k}` | `v26.9.2-beta.1` |
| prd | `v{YY}.{M}.{N}-rc.{k}` | `v26.9.2-rc.1` |

- `{YY}.{M}` 取自当前日期，`{N}` 同月递增、跨月重置为 1
- `{k}` 同版本内递增，换版本重置为 1
- 同一分支的 dev / test / prd tag 版本号保持一致
- prd 的 `rc.N` 即终态，不打裸版本号

```
feature1 首次合 dev   → v26.9.2-alpha.1
同一 feature 再合 dev → v26.9.2-alpha.2
该 feature 合 test    → v26.9.2-beta.1
该 feature 合 prd     → v26.9.2-rc.1
新 feature 合 dev     → v26.9.3-alpha.1
```

## 配置

`.claude/git-flow.json`，由 `git-flow init` 创建，其余子命令只读：

```json
{
  "devBranch": "dev",
  "testBranch": "test",
  "prdBranch": "main",
  "remote": "origin",
  "tagPrefix": "v",
  "tagStage": { "dev": "alpha", "test": "beta", "prd": "rc" },
  "branchTypes": {
    "feature": { "prefix": "feature/", "flow": ["dev", "test", "prd"] },
    "hotfix":  { "prefix": "hotfix/",  "flow": ["prd", "test", "dev"] },
    "bugfix":  { "prefix": "bugfix/",  "flow": ["dev", "test", "prd"] }
  }
}
```

- 分支名通过 `devBranch` / `testBranch` / `prdBranch` 配置，不写死；`prdBranch` 的值可以叫 `main`，也可以叫 `prd`
- `flow` 与 `tagStage` 的 key 是阶段名（子命令名），阶段名对应 `<阶段名>Branch` 字段
- `branchTypes` 可自行增删类型，`flow` 数组决定该类型的流转顺序
- 跳步会被拦截：如 feature 未合 test 直接执行 `prd`，会提示应先合 test

## 安全约束

技能内置以下硬约束，违反即中止：

1. 绝不用阶段分支当合并源，dev / test 上的无关提交不能被直连带上线
2. 合并到 dev/test/prd、推送 tag、删除同名历史分支各自停下确认
3. 工作区不干净或未同步远端时先停
4. 合并冲突中止，不自动解
5. 同名 tag 拦截
6. tag 创建后必须 push
7. dev / test / prd 上不直接提交
8. 失败时报告「停在哪、副作用是什么、如何退回」

## 技能内部结构

```
skills/git-flow/
├── SKILL.md               # 主技能定义 + 子命令规则 + 红线
└── README.md              # 本文件
```
