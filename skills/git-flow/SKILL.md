---
name: git-flow
description: 分支流转发布流水线——从 prd 分支切开发分支(feature/hotfix)，按类型逐级流转 dev/test/prd 并打 alpha/beta/rc 预发布 tag。当用户提到发版、上线、合并到 dev/test/prd、打 tag、切发布分支、hotfix 流程时使用。
---

# GitFlow

分支流转发布流水线。按分支类型决定流转顺序，每次合并到目标分支后自动打预发布 tag。

## 核心概念

### 分支类型与流转顺序

| 类型 | 分支名前缀 | 流转顺序 | 说明 |
|------|-----------|---------|------|
| feature | `feature/` | dev → test → prd | 常规需求：dev 联调 → test 验收 → prd 上线 |
| hotfix | `hotfix/` | prd → test → dev | 紧急修复：先上 prd，再逐级回灌 |
| bugfix | `bugfix/` | dev → test → prd | 常规缺陷修复 |

所有类型都从 **prd** 分支切出。

### tag 规则

| 目标分支 | tag 格式 | 示例 |
|---------|---------|------|
| dev | `v{YY}.{M}.{N}-alpha.{k}` | `v26.9.2-alpha.1` |
| test | `v{YY}.{M}.{N}-beta.{k}` | `v26.9.2-beta.1` |
| prd | `v{YY}.{M}.{N}-rc.{k}` | `v26.9.2-rc.1` |

- `{YY}` 当前年份后两位，`{M}` 当前月份，`{N}` 同月递增、跨月重置为 1
- `{k}` 同版本内递增，换版本重置为 1
- prd 的 `rc.N` 即终态，不存在裸版本号 tag

## 配置

配置文件为 `.claude/git-flow.json`，由 `git-flow init` 创建，**其余子命令只读不写**：

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

**阶段**：`flow` 与 `tagStage` 的 key 是阶段名，同时也是子命令名（`dev` / `test` / `prd`）。阶段名对应 `<阶段名>Branch` 这个配置字段——`dev` → `devBranch`、`test` → `testBranch`、`prd` → `prdBranch`。分支叫什么由字段值决定，如 `prdBranch` 的值可以是 `main` 也可以是 `prd`。

`branchTypes[].flow` 决定该类型的流转顺序，可自行增删类型。所有子命令都基于此配置校验步序，不得写死分支名。

读取配置：

```bash
cat .claude/git-flow.json
```

早期版本使用 `mainBranch` 字段与二档 `tagStage`（仅 dev/main），与本结构不兼容。检测到 `mainBranch` 字段时，提示重跑 `git-flow init` 或手工改字段后再执行其他子命令。

## 子命令

**只有 `init` 会写文件**（配置与 `.gitignore`），其余子命令只读。配置缺失时，`init` 以外的子命令一律提示先执行 `git-flow init` 并停止。

不带子命令时：配置不存在 → 引导执行 `init`；已配置 → 执行 `status` 并根据结果引导下一步。

### init

初始化配置。

**配置已存在**：展示当前内容，询问是否覆盖，默认否。

**配置不存在**：先探测环境，再生成草案确认。

| 探测项 | 方法 |
|--------|------|
| 生产分支 | `git symbolic-ref refs/remotes/origin/HEAD`（结果形如 `refs/remotes/origin/main`） |
| 测试分支 | `git rev-parse --verify origin/test` |
| 开发分支 | `git rev-parse --verify origin/dev` |
| 远端名 | `git remote` 的首个 |

```bash
git symbolic-ref refs/remotes/origin/HEAD
git rev-parse --verify origin/test
git rev-parse --verify origin/dev
git remote
```

探测失败或结果不符预期时，逐项询问用户。随后展示草案等待确认：

```
探测到：
  生产分支 main（origin HEAD）
  测试分支 test（origin/test 存在）
  开发分支 dev（origin/dev 存在）
  远端     origin

将写入 .claude/git-flow.json：
{配置内容}

确认？(Y/n)
```

确认后写入配置。

**配置就位后检查 .gitignore**（新建、覆盖、沿用已有配置，均执行）：

```bash
git check-ignore -v .claude/git-flow.json
```

- **已被忽略**：说明由哪条规则覆盖（如 `.gitignore:5:.claude/`），不做改动。并提示：配置不进版本库，团队成员需各自执行 `git-flow init`。
- **未被忽略**：询问是否追加，默认是：

```
.claude/git-flow.json 未被忽略，会随 git add 提交进版本库。
是否追加到 .gitignore？(Y/n)
```

确认后追加（`.gitignore` 不存在则创建）：

```bash
printf '\n# git-flow 本地配置\n.claude/git-flow.json\n' >> .gitignore
```

只追加这一个路径，**不要写整个 `.claude/`**——该目录可能含团队共享配置（如 `.claude/settings.json`）。用户拒绝时保留现状，并提示该文件会被提交。

### status

只读探测，不产生任何修改。配置不存在时提示先执行 `git-flow init`。

```bash
git branch --show-current
git fetch origin --tags
git tag --list "v*" --sort=-v:refname | head -20
git merge-base --is-ancestor HEAD origin/<devBranch>  && echo "已合入 dev"
git merge-base --is-ancestor HEAD origin/<testBranch> && echo "已合入 test"
git merge-base --is-ancestor HEAD origin/<prdBranch>  && echo "已合入 prd"
```

输出格式：

```
当前分支: feature/用户中心
类型    : feature（流转 dev → test → prd）
最新 tag: v26.9.1-alpha.2

进度:
  [ ] dev  — 未合并
  [ ] test — 未合并
  [ ] prd  — 未合并

下一步: git-flow dev
```

### start <type> <name>

从 prd 分支切出 `<type>` 类型的新分支。`<name>` 可用中文，自动转为英文分支名。

1. 校验配置文件存在，否则提示先执行 `git-flow init` 并停止
2. 校验 `<type>` 存在于配置的 `branchTypes`，否则列出可用类型并停止
3. 按「分支名生成」把 `<name>` 转为英文 slug，并处理同名历史分支（见下）
4. 执行：

```bash
git fetch origin --tags
git status --porcelain        # 必须无输出，否则停止
git checkout <prdBranch>
git pull --ff-only
git checkout -b <prefix><slug>
```

5. 询问是否推送到远端，确认后：

```bash
git push -u origin <prefix><slug>
```

#### 同名历史分支

生成 slug 后，检查 `<prefix><slug>` 在本地与远端是否已存在：

```bash
git rev-parse --verify <prefix><slug>
git rev-parse --verify origin/<prefix><slug>
```

**都不存在** → 直接进入第 4 步。

**存在** → 判断该历史分支是否已完成使命（两条任一成立即可）：

```bash
# a. flow 的目标分支已全部合入（以 feature 为例，按 flow 逐个列全）
git merge-base --is-ancestor <prefix><slug> origin/<devBranch>  && \
git merge-base --is-ancestor <prefix><slug> origin/<testBranch> && \
git merge-base --is-ancestor <prefix><slug> origin/<prdBranch>
# b. 相对 prd 分支无独有提交
git rev-list --count origin/<prdBranch>..<prefix><slug>
```

**已完成（a 或 b 成立）** → 展示确认，删除后继续第 4 步：

```
检测到同名历史分支 : feature/user-center
状态               : 已合入 dev、test、prd，无独有提交
位置               : 本地存在，origin 存在

该分支已完成使命，删除后重建。将执行：
  git branch -D feature/user-center
  git push origin --delete feature/user-center

确认？(Y/n)
```

用户拒绝 → 停止，提示改个名字重新执行 `git-flow start`。

**未完成（a、b 均不成立，仍有未合并提交）** → **不删除**，停止并报告：

```
同名分支 feature/user-center 仍有未合并提交（领先 prd 3 个提交）。
不会自动删除，请先处理：
  继续推进 → git-flow dev / git-flow test / git-flow prd
  改新名字 → git-flow start feature <其他名>
```

删除前必须单独确认，且**只删判定为已完成的同名分支**；仍有未合并内容的分支一律不碰。

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

### dev / test / prd

把当前分支合并到目标阶段的分支，并打该阶段的 tag。三者除目标分支、tag 阶段、步序外完全一致。

**前置校验**（任一不通过即停止，不做任何修改）：

| 检查 | 方法 | 不通过时 |
|------|------|---------|
| 配置已初始化 | `.claude/git-flow.json` 存在 | 提示先执行 `git-flow init`，停止 |
| 当前分支类型允许流向该目标 | 配置 `flow` 含该目标 | 提示该类型应先合哪个分支 |
| 步序正确 | 见下方「步序校验」 | 提示应先执行前置步骤 |
| 工作区干净 | `git status --porcelain` | 提示先提交或 stash |
| 目标分支存在 | `git rev-parse --verify origin/<target>` | 提示目标分支不存在 |
| tag 不重名 | `git rev-parse --verify <新tag>` | 同名 tag 已存在，停止 |

**步序校验**：取配置 `flow` 中位于当前目标之前的全部阶段，逐个验证当前 HEAD 已合入：

```bash
# 以 feature 执行 prd 为例（dev、test 是其前置）
git merge-base --is-ancestor HEAD origin/<devBranch>  || echo "尚未合并到 dev"
git merge-base --is-ancestor HEAD origin/<testBranch> || echo "尚未合并到 test"
```

**执行**：

```bash
# 1. 计算版本号（见「版本号推导」），展示给用户并等待确认
# 2. 记录原分支，再合并（先 fetch 保证基于最新远端）
git fetch origin --tags
ORIG=$(git branch --show-current)
git checkout <target>
git pull --ff-only
git merge --no-ff $ORIG
git push origin <target>

# 3. 打 tag 并推送
git tag -a <新tag> -m "合并 $ORIG 到 <target>"
git push origin <新tag>

# 4. 切回原分支
git checkout $ORIG
```

**切回原分支**：只要已经 `checkout` 到 `<target>`，流程结束或中止时都必须切回 `$ORIG`，不把用户留在 dev/test/prd 上。

| 场景 | 处理 |
|------|------|
| 正常完成（含 tag 推送失败） | 先切回 `$ORIG`，再报告结果 |
| `git pull --ff-only` 失败 | 切回 `$ORIG` 后报告分叉，停止 |
| 合并冲突 | `git merge --abort` → `git checkout $ORIG` → 报告冲突文件 |

原分支已被删除等极端情况下切回失败，报告当前所在分支并停止，不强行操作。

**合并冲突**：立即中止（`git merge --abort`），切回原分支，报告冲突文件清单，交由用户处理后重新执行。禁止自动解冲突。

**失败处理**：若合并已推送但 tag 推送失败，切回原分支后明确告知「合并已生效，tag 未推送」，并给出补推命令 `git push origin <新tag>`。

**收尾**：切回原分支后，若该分支 `flow` 已全部走完，提示用户该分支已完成使命，可自行删除（不自动删）。

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
| 该 feature 合 test | `v26.9.2-alpha.2` | `v26.9.2-beta.1` |
| 该 feature 合 prd | `v26.9.2-beta.1` | `v26.9.2-rc.1` |
| 新 feature2 合 dev | `v26.9.2-rc.1` | `v26.9.3-alpha.1` |
| hotfix 合 prd（先执行） | `v26.9.3-alpha.1` | `v26.9.4-rc.1` |
| 该 hotfix 回灌 test | `v26.9.4-rc.1` | `v26.9.4-beta.1` |
| 该 hotfix 回灌 dev | `v26.9.4-beta.1` | `v26.9.4-alpha.1` |

**始终先展示推导结果与依据，等用户确认后才执行。**

## 红线

1. **绝不用阶段分支当合并源**：`dev`、`test` 上含他人提交，把 dev 分支直连到 test、或把 test 分支直连到 prd，等于把无关代码带上线。每个阶段只接受开发分支（feature/hotfix/bugfix）的合并，且该分支必须已合过前序阶段。
2. **每个不可逆动作前停下确认**：合并到 dev/test/prd、推送 tag、删除同名历史分支，各自单独确认，不批量放行。
3. **工作区不干净、未 fetch 最新远端 → 先停**。
4. **冲突即中止**，不自动解冲突。
5. **同名 tag 存在 → 拦截**，不静默覆盖。
6. **tag 创建后必须 push**，本地 tag 等于没打。
7. **dev/test/prd 只接受合并**，不直接在其上提交。
8. **任一步失败 → 报告「停在哪一步、已产生的副作用、如何退回」**。

## 异常处理

| 情况 | 处理方式 |
|------|---------|
| 配置不存在 | 提示先执行 `git-flow init`，停止 |
| 分支类型未在配置中 | 列出可用类型，停止 |
| `start` 遇到同名分支 | 已完成 → 确认后删除重建；仍有未合并提交 → 不删，提示推进或改名 |
| 步序错误（跳步） | 提示应先执行哪一步，停止 |
| 工作区不干净 | 提示先提交或 stash，停止 |
| `git pull --ff-only` 失败 | 切回原分支，报告本地与远端分叉，停止，不自动 merge |
| 合并冲突 | `git merge --abort`，切回原分支，报告冲突文件，停止 |
| tag 重名 | 报告已存在的 tag，停止 |
| 合并成功但 tag 推送失败 | 切回原分支，报告合并已生效，给出补推命令 |
| 目标分支不存在 | 报告并停止，提示先创建 |
| 已切到目标分支后中止 | 先切回原分支，再报告 |

## 技能内部结构

```
skills/git-flow/
├── SKILL.md               # 主技能定义 + 子命令规则
└── README.md              # 使用说明
```
