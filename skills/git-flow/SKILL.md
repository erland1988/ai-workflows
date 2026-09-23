---
name: git-flow
description: 分支流转发布流水线——从 main 切开发分支(feature/hotfix)，按类型流转到 dev/main 并打 alpha/rc 预发布 tag。当用户提到发版、上线、合并到 dev 或 main、打 tag、切发布分支、hotfix 流程时使用。
---

# GitFlow

分支流转发布流水线。按分支类型决定流转顺序，每次合并到目标分支后自动打预发布 tag。

## 核心概念

### 分支类型与流转顺序

| 类型 | 分支名前缀 | 流转顺序 | 说明 |
|------|-----------|---------|------|
| feature | `feature/` | dev → main | 常规需求：先在 dev 测试，再上 main |
| hotfix | `hotfix/` | main → dev | 紧急修复：先上 main，再回灌 dev |
| bugfix | `bugfix/` | dev → main | 常规缺陷修复 |

所有类型都从 **main** 切出。

### tag 规则

| 目标分支 | tag 格式 | 示例 |
|---------|---------|------|
| dev | `v{YY}.{M}.{N}-alpha.{k}` | `v26.9.2-alpha.1` |
| main | `v{YY}.{M}.{N}-rc.{k}` | `v26.9.2-rc.1` |

- `{YY}` 当前年份后两位，`{M}` 当前月份，`{N}` 同月递增、跨月重置为 1
- `{k}` 同版本内递增，换版本重置为 1
- main 的 `rc.N` 即终态，不存在裸版本号 tag

## 配置

配置文件为 `.claude/git-flow.json`，由 `git-flow init` 创建，**其余子命令只读不写**：

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

`branchTypes[].flow` 决定该类型的流转顺序，可自行增删类型。所有子命令都基于此配置校验步序，不得写死分支名。

读取配置：

```bash
cat .claude/git-flow.json
```

## 子命令

**只有 `init` 会写配置文件，其余子命令只读。** 配置缺失时，`init` 以外的子命令一律提示先执行 `git-flow init` 并停止。

不带子命令时：配置不存在 → 引导执行 `init`；已配置 → 执行 `status` 并根据结果引导下一步。

### init

初始化配置。

**配置已存在**：展示当前内容，询问是否覆盖，默认否。

**配置不存在**：先探测环境，再生成草案确认。

| 探测项 | 方法 |
|--------|------|
| 主分支 | `git symbolic-ref refs/remotes/origin/HEAD`（结果形如 `refs/remotes/origin/main`） |
| 测试分支 | `git rev-parse --verify origin/dev` |
| 远端名 | `git remote` 的首个 |

```bash
git symbolic-ref refs/remotes/origin/HEAD
git rev-parse --verify origin/dev
git remote
```

探测失败或结果不符预期时，逐项询问用户。随后展示草案等待确认：

```
探测到：
  主分支   main（origin HEAD）
  测试分支 dev（origin/dev 存在）
  远端     origin

将写入 .claude/git-flow.json：
{配置内容}

确认？(Y/n)
```

确认后写入。并提示：若 `.claude/` 被 gitignore，配置不进版本库，团队成员需各自执行 `git-flow init`。

### status

只读探测，不产生任何修改。配置不存在时提示先执行 `git-flow init`。

```bash
git branch --show-current
git fetch origin --tags
git tag --list "v*" --sort=-v:refname | head -20
git merge-base --is-ancestor HEAD origin/dev && echo "已合入 dev"
git merge-base --is-ancestor HEAD origin/main && echo "已合入 main"
```

输出格式：

```
当前分支: feature/用户中心
类型    : feature（流转 dev → main）
最新 tag: v26.9.1-alpha.2

进度:
  [ ] dev  — 未合并
  [ ] main — 未合并

下一步: git-flow dev
```

### start <type> <name>

从 main 切出 `<type>` 类型的新分支。`<name>` 可用中文，自动转为英文分支名。

1. 校验配置文件存在，否则提示先执行 `git-flow init` 并停止
2. 校验 `<type>` 存在于配置的 `branchTypes`，否则列出可用类型并停止
3. 按「分支名生成」把 `<name>` 转为英文 slug，并校验不与现有分支重名
4. 执行：

```bash
git fetch origin --tags
git status --porcelain        # 必须无输出，否则停止
git checkout <mainBranch>
git pull --ff-only
git checkout -b <prefix><slug>
```

5. 询问是否推送到远端，确认后：

```bash
git push -u origin <prefix><slug>
```

#### 分支名生成

`<name>` 为中文时，翻译为**简洁通用的英文**，不做逐字直译：

| 输入 | slug |
|------|------|
| 高校 | `university` |
| 用户中心 | `user-center` |
| 订单系统重构 | `order-refactor` |
| 支付超时修复 | `payment-timeout` |

- 全小写，多词用连字符连接（kebab-case）
- 已是英文时直接规范化：转小写、空格与下划线转 `-`、剔除特殊字符
- 取核心语义，控制在 3 个词以内
- 生成的 slug 随执行计划一并展示，用户可当场指定其他名字

### dev / main

把当前分支合并到目标分支，并打该目标的 tag。两者除目标分支、tag 阶段、步序外完全一致。

**前置校验**（任一不通过即停止，不做任何修改）：

| 检查 | 方法 | 不通过时 |
|------|------|---------|
| 配置已初始化 | `.claude/git-flow.json` 存在 | 提示先执行 `git-flow init`，停止 |
| 当前分支类型允许流向该目标 | 配置 `flow` 含该目标 | 提示该类型应先合哪个分支 |
| 步序正确 | 见下方「步序校验」 | 提示应先执行前置步骤 |
| 工作区干净 | `git status --porcelain` | 提示先提交或 stash |
| 目标分支存在 | `git rev-parse --verify origin/<target>` | 提示目标分支不存在 |
| tag 不重名 | `git rev-parse --verify <新tag>` | 同名 tag 已存在，停止 |

**步序校验**：取配置 `flow` 中位于当前目标之前的全部分支，逐个验证当前 HEAD 已合入：

```bash
# 以 feature 执行 main 为例（dev 是其前置）
git merge-base --is-ancestor HEAD origin/dev || echo "尚未合并到 dev"
```

**执行**：

```bash
# 1. 计算版本号（见「版本号推导」），展示给用户并等待确认
# 2. 合并（先 fetch 保证基于最新远端）
git fetch origin --tags
git checkout <target>
git pull --ff-only
git merge --no-ff <当前分支>
git push origin <target>

# 3. 打 tag 并推送
git tag -a <新tag> -m "合并 <当前分支> 到 <target>"
git push origin <新tag>
```

**合并冲突**：立即中止（`git merge --abort`），报告冲突文件清单，交由用户处理后重新执行。禁止自动解冲突。

**失败处理**：若合并已推送但 tag 推送失败，明确告知「合并已生效，tag 未推送」，并给出补推命令 `git push origin <新tag>`。

**收尾**：main 合并完成且该分支 `flow` 已全部走完时，提示用户该分支已完成使命，可自行删除（不自动删）。

## 版本号推导

### 版本核心 `{YY}.{M}.{N}`

1. 读取当前日期得到 `YY`、`M`
2. 从全部 tag 中解析出形如 `v{YY}.{M}.{N}` 的记录，取该年月下的最大 `N`
3. **若当前分支已存在本次流程产生的 tag**（说明是同一版本的迭代）→ 复用其核心版本号，不推进
4. 否则 → `N = 该年月最大 N + 1`；若该年月无记录则 `N = 1`

判断当前分支是否已有本次流程的 tag：

```bash
git tag --contains HEAD --list "v*" --sort=v:refname | head -1
```

### 序号 `{k}`

`k = 该核心版本号 + 该阶段下已有 tag 数量 + 1`

```bash
git tag --list "v26.9.2-alpha.*" | wc -l
```

### 推导示例

| 场景 | 已有 tag | 本次 tag |
|------|---------|---------|
| feature1 首次合 dev | `v26.9.1-alpha.3` | `v26.9.2-alpha.1` |
| 同一 feature 修完再合 dev | `v26.9.2-alpha.1` | `v26.9.2-alpha.2` |
| 该 feature 合 main | `v26.9.2-alpha.2` | `v26.9.2-rc.1` |
| 新 feature2 合 dev | `v26.9.2-rc.1` | `v26.9.3-alpha.1` |
| hotfix 合 main（先执行） | `v26.9.3-alpha.1` | `v26.9.4-rc.1` |
| 该 hotfix 回灌 dev | `v26.9.4-rc.1` | `v26.9.4-alpha.1` |

**始终先展示推导结果与依据，等用户确认后才执行。**

## 红线

1. **绝不 `dev → main`**：dev 上含他人提交，直连等于把无关代码带上线。main 只从开发分支合并。
2. **每个不可逆动作前停下确认**：合并到 dev/main、推送 tag，各自单独确认，不批量放行。
3. **工作区不干净、未 fetch 最新远端 → 先停**。
4. **冲突即中止**，不自动解冲突。
5. **同名 tag 存在 → 拦截**，不静默覆盖。
6. **tag 创建后必须 push**，本地 tag 等于没打。
7. **main/dev 只接受合并**，不直接在其上提交。
8. **任一步失败 → 报告「停在哪一步、已产生的副作用、如何退回」**。

## 异常处理

| 情况 | 处理方式 |
|------|---------|
| 配置不存在 | 提示先执行 `git-flow init`，停止 |
| 分支类型未在配置中 | 列出可用类型，停止 |
| 步序错误（跳步） | 提示应先执行哪一步，停止 |
| 工作区不干净 | 提示先提交或 stash，停止 |
| `git pull --ff-only` 失败 | 本地与远端分叉，报告并停止，不自动 merge |
| 合并冲突 | `git merge --abort`，报告冲突文件，停止 |
| tag 重名 | 报告已存在的 tag，停止 |
| 合并成功但 tag 推送失败 | 报告合并已生效，给出补推命令 |
| 目标分支不存在 | 报告并停止，提示先创建 |

## 技能内部结构

```
skills/git-flow/
├── SKILL.md               # 主技能定义 + 子命令规则
└── README.md              # 使用说明
```
