---
name: upload-comate-spec
description: "将 comate 1.0 项目的需求与变更规格（PRD + change 的 brief + specs/<capability>/spec.md）合并上传到飞书云文档。默认按「一次开发任务」圈定范围（自动探测本地 task；--task 指定；--changes 按 change 名）。当用户说「上传文档到飞书」「把这次的需求和规格传给飞书」「导出 comate 规格文档」「上传 PRD 和变更规格」「上传某个需求的文档」「upload-comate-spec」时使用。"
---

# upload-comate-spec

把当前 comate 1.0 项目的**需求文档**与**变更规格**合并成一份，上传到飞书云文档。

**只读** comate 的产物：不写 `state.json`、不跑 comate 命令、不改任何项目文件。

## 收录范围

| 顺序 | 来源 | 说明 |
|------|------|------|
| 1 | `comate/knowledge-base/requirements/*/PRD-*.md` | 需求文档 |
| 2 | `comate/comate/changes/<name>/brief.md` | 变更简报：为什么做、范围、非目标、关键决定、验收示例 |
| 3 | `comate/comate/changes/<name>/specs/<capability>/spec.md` | 行为规格：该能力的完整目标规格（可多份） |
| 4 | `comate/comate/archive/YYYY-MM-DD-<name>/…` | 已归档的 change，产物结构与进行中相同 |

comate 1.0 的文档模型只有两层：**PRD（要不要做）+ brief/spec（做成什么样）**。
旧版的 OpenSpec `proposal.md` / `design.md` 与 Superpowers `*-design.md` 已不再产生；
技术取舍写在 brief 的「决定」「约束与不变量」里，不再有独立的「技术设计文档」。

**change 枚举规则**：

- 同时扫 `changes/`（进行中）与 `archive/`（已归档）；
- 变更名取 `state.json` 的 `name`（权威），归档目录名的 `YYYY-MM-DD-` 前缀不算变更名；
- 同名 change 两边都有时**只收进行中的**：归档的是它的历史副本，两边都收会重复。

**不收录**：

- `state.json` —— 机器状态与唯一真相源，读者不需要；
- `tasks.md` —— 实施清单，属于过程记录；
- `verification.md` —— 验收结果，随开发变化，且由脚本生成；
- `removed-specs/` —— 已删除能力的备份，不是目标规格；
- `openspec/`、`docs/knowledge-base/`、`docs/superpowers/` 下的旧版产物 —— 1.0 项目里即使因迁移残留也不收，避免过期文档混入。

## 圈定「一次开发任务」（默认行为）

**默认即 task 模式** —— 不传圈定参数时，脚本自动按「一次开发任务」收文档。
**不提供「收全部」**：那会把多个任务的文档混进一份。

| 用法 | 依据 | 说明 |
|---|---|---|
| （无参数）／`--task` | change 的 `state.json` sources 反查 | **默认**。自动探测本地 task：唯一则采用，多个／零个则报错并列出 |
| `--task <关键字>` | 同上，按关键字筛 | 本地有多个 task 时用它指定 |
| `--changes <名,...>` | change 名子串匹配，逗号分隔 | **绕过 task 模式**。适合需求来自对话、没有 PRD 的 change |

```bash
# 默认：自动探测本地 task
upload.sh --dry-run

# 本地有多个 task 时指定其一（报错信息会列出候选）
upload.sh --dry-run --task login

# 需求来自对话、没有 PRD：按 change 名圈定
upload.sh --dry-run --changes tweak-copy
```

**task 从哪来**：comate 的运行时单元是 **change 而非任务** —— 一次 `/comate` 只处理一个 change。
任务分组没有独立记录，但 `comate new <name> --source <PRD>` 会把 PRD 路径写进 change 的
`state.json`（`sources` 数组）；**引用同一份 PRD 的一组 change 即一个 task**。
一个功能目录里有多份 PRD，也只算一个 task。

自动探测**优先只扫进行中的 change**：归档的历史 change 常与当前任务同属一个 PRD，
全扫会让默认模式长期报「多个 task」。进行中一个都没有时，才退到归档。

需求来自对话的 change（`new` 未带 `--source`）**没有 sources，反查不到 task** ——
自动探测会明确报错并建议改用 `--changes`。

**标题**（飞书**文档名**）：单变更 → 变更名；多变更 → task／`--changes` 关键字；兜底 → 项目根目录名。可用 `--title` 覆盖。
注意这只决定文档名；正文里的分组标题另取 PRD 汉字名（无 PRD 时回退 change 名，见「合并结构」）。

### 筛选对「需求」部分同样生效

启用任一筛选时，`PRD-*.md` 会**收窄到被选中变更的 `state.json` sources 真正引用的那几份**。

- `--task A` 不会再带上 B 的 PRD；
- 选中的变更若都没带 `--source`，则**一份 PRD 都不收**（正确：它们本就不来自 PRD）；
- 无筛选时保持「收全部 PRD」的原行为。

## 执行步骤

### 1. 先预览（默认动作）

**立即执行：** 运行预览，确认收录清单无误后再上传。

```bash
# 只要清单就丢弃正文（清单走 stderr，照常可见）—— 避免整篇正文刷屏/进上下文
bash ~/.claude/skills/upload-comate-spec/scripts/upload.sh --dry-run > /dev/null
```

输出会列出每份被收录的文档、合并后的字节数。**两个流是分开的**：

- 收录清单、字节数、日志 → **stderr**，即便重定向 stdout 也照常可见
- 合并后的正文 → **stdout**，**默认不落盘** —— 不生成 `upload-comate-spec-preview.md`，项目工作区保持干净

要检查正文结构（层级、分组标题）或留档时，重定向或 `--out`：

```bash
SK=~/.claude/skills/upload-comate-spec/scripts/upload.sh

# 检查标题骨架
bash "$SK" --dry-run > /tmp/preview.md && grep -n '^#\{1,4\} ' /tmp/preview.md

# 落到指定位置留档
bash "$SK" --dry-run --out ./preview.md
```

上传路径同样不碰工作区：合并产物写进 `mktemp` 临时文件，由 EXIT trap 清理。

向用户展示：收录了哪几份文档、总字节数。**若清单与用户预期不符，停止并询问**（可用 `--prd <关键字>` 缩小 PRD 范围）。

### 2. 上传

确认清单后执行：

```bash
bash ~/.claude/skills/upload-comate-spec/scripts/upload.sh
```

上传走飞书官方 CLI（`lark-cli`），使用**当前登录用户自己的身份**（`--as user`）：

- 文档落在**操作者本人的飞书云空间**，不落到某个共享应用的云空间；
- 每个使用者各自执行 `lark-cli auth login`，脚本不读取、不保存任何 app secret；
- 成功后输出飞书文档链接，向用户展示该链接。

## 合并结构

```
> 生成时间 / 项目路径 / 文档数量        ← 正文不输出 H1：飞书文档本身有标题块，再加会重复

# 第一部分：需求
  （PRD 正文，标题降 1 级；H1 的 `PRD-NNN-<slug>:` 编号前缀被去掉，只留汉字产品名）

# 第二部分：变更规格
  ## <变更显示名>                       ← 每个变更一组（PRD 汉字名，单变更也打）
    ### 变更简报（comate brief）        ← 固定身份标题
        #### 目标 / 范围 / 决定 …        （brief 降 3 级，其 H1 是有效章节，不省）
    ### 行为规格（comate spec）
        #### <capability>               （每份 spec 的 H1 即 capability 名，降 3 级）
        #### <capability>               （多份并列）

# 附录
  | 项目路径 | 文档数量 | 生成时间 |
```

**表头设计**：

- **正文不输出 markdown H1** —— 飞书文档本身有标题块（= 导入任务的 `file_name`），再加一个 H1 会让标题在顶部出现两次。
- 两类文档各有一个**固定身份标题**（H3），读者一眼知道这份是 brief 还是 spec：
  **变更简报**（为什么做、决定什么）→ **行为规格**（做成什么样）。
  不叫「技术设计」：1.0 没有独立的技术设计文档，取舍在 brief 的「决定」里，spec 只描述行为。
- **每个变更都打 `## <变更显示名>` 分组标题**（单变更也打）。显示名按**三级回退**解析：

  1. 该 change 的 `sources` 引用的 **PRD H1 冒号后的汉字**（如 `邮箱登录`）；
  2. 回退：`state.json` 的 `name`（英文 kebab-case，读者认不出，仅次选）；
  3. 再回退：变更目录名（归档目录已去掉日期前缀）。

  **多变更撞名**（同一 PRD 拆出的多个 change 都回退到 PRD 名）才追加 change 名后缀区分，
  单一变更引用该 PRD 时保持简洁。

  注意分组标题只影响**正文**，飞书文档名仍取 change 名。
- **brief 与 spec 都降 3 级、不省 H1**：
  - brief 的 H1 是 `# 目标`、`# 范围` 等有效章节，省掉会丢失标题；
  - spec 的 H1 是 capability 名（如 `auth`），正是读者需要的分组名。
  降 3 级后它们落在 H4，其下 `##` 落 H5、`###` 落 H6（飞书支持到 H9）。
- PRD 仍降 1 级挂在 `# 第一部分` 之下。
- 飞书文档名加 `YYYYMMDD_` 前缀用于跨天去重；**标题已含 `YYYY-MM-DD` 时不再加**（否则日期重复）。

**排序**：按「变更名 → 组内序（3a brief / 3b spec）→ 路径」排序
（`sort -t$'\t' -k3,3 -k1,1 -k4,4`）—— 排序键用 change 名而非汉字显示名，
确保同一变更的文档聚在一起，多份 capability spec 按目录名稳定排列。
不能直接 `sort` 整行 —— 那会把所有变更的 brief 排到一起，打散同一变更的 brief/spec。

合并时自动做两件事：

- **剥离 YAML frontmatter** —— 文档头部若有 `---` 包围的元信息块（如手工补充的 frontmatter），不进入正文
- **过滤本机绝对路径** —— 丢弃含盘符路径（如 `D:\...`）的行，避免把本地目录结构带到飞书

## 重复上传

同一标题的文档**不会重复堆积**：上传前会检查**本项目目录内**是否已有同标题文档，有则先删除（移入飞书回收站，可恢复）再导入新版本。

代价是**文档 URL 会变化**——若已把链接发给他人，需要重新提供。

标题带 `YYYYMMDD` 前缀，因此**跨天上传会被视为不同文档**，历史版本自动保留；只有同一天内重复上传才会触发覆盖。

去重范围限于**当前用户云空间里的本项目目录**，所以不同项目、不同用户之间即便产生同标题文档也不会互相影响。

## 配置

不再需要任何应用凭据文件。上传统一走飞书官方 CLI：

```bash
npm i -g @larksuite/cli
lark-cli auth login
lark-cli auth status     # identities.user.available 应为 true
```

- 脚本所有命令都显式带 `--as user`，使用**操作者本人**的登录态；换人使用时各自登录即可。
- 文档归属操作者个人云空间：A 上传的文档 B 看不到同名覆盖，去重只在各自空间内生效。
- 早先由应用凭据（`cli_aab21d9764b99bc3`）上传的文档**不会再被识别或覆盖**，需要时请手动处理。
- `lark-cli` 依赖 Node ≥ 20；本机默认 Node 24，直接可用。

**文档落点**：`comate-spec/<项目名>/`

- 根目录 `comate-spec/` 写死在脚本中，不可配置
- 二级目录默认取项目根目录名（如 `clue-platform`），用于**隔离不同项目**——去重只在各自目录内生效，避免跨项目同标题文档被误删
- `--folder <名称>` 可覆盖二级目录名

## 上传方式

走飞书官方 CLI 的 **`drive +import`**：把合并后的 `.md` 导入为云文档（docx）。CLI 内部完成素材上传、创建导入任务与有限轮询，脚本不再手写 HTTP 请求。

这样做的原因：避免逐块调用 block API 拼装 JSON——markdown 里的引号、反斜杠、换行在 shell 下手工转义极易出错；飞书自己的 markdown 渲染器对**表格**、嵌套列表的处理也更完整。

以下约束均来自实测（已固化在脚本中，改动时勿破坏）：

- **`--file` 只接受 cwd 下的相对路径** —— 传绝对路径会报 `unsafe file path`。脚本会 `cd` 到临时目录后只传文件名。
- **文件必须带 `.md` 后缀** —— CLI 靠后缀推断 `file_extension`；`mktemp` 生成的无后缀文件会直接失败。脚本先复制成 `comate-import.XXXXXX.md` 再导入，用完即删。
- **同一目录下的导入必须串行** —— 并发会触发 `232140101/232140100/233523001`；脚本一次只传一份，天然串行。
- **返回值字段在 `data` 下** —— 成功判断为 `data.ready == true`，链接取 `data.url`（租户域名，不要自己拼 `feishu.cn`）。导入超时时返回 `data.ready=false` 与 `ticket`，用 `drive +task_result --scenario import --ticket <ticket>` 续查。
- **删除是异步的** —— `drive +delete --yes` 通常在 `data.deleted=true` 直接返回；若 `timed_out=true`，脚本用 `task_id` 调 `+task_result --scenario task_check` 续查，避免旧文档还在时就开始导入。
- **所有命令显式 `--as user`** —— 默认身份是 `auto`，可能落到 bot；脚本固定用当前登录用户，确保文档归属正确、去重范围正确。

## 依赖

| 命令 | 用途 | 检查 |
|------|------|------|
| `bash` >= 3 | 运行脚本 | — |
| `lark-cli`（`@larksuite/cli`） | 认证、目录、导入、删除 | 必需，需已 `auth login` |
| `node` >= 20 | lark-cli 自身依赖；脚本也用它解析 JSON | 必需 |
| `awk` / `sed` / `grep` | 合并与解析 | 必需 |

不需要 `curl`、Python、jq。

## 失败排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `未安装 lark-cli` | 全局未安装或不在 PATH | `npm i -g @larksuite/cli` |
| `lark-cli 的 user 身份未登录` | 没登录，或 token 已失效 | `lark-cli auth login`，再用 `auth status` 确认 `identities.user.available=true` |
| `未找到 comate 项目根` | 当前目录不在 comate 1.0 项目内 | 在项目根执行；确认存在 `comate/comate/config.json`；或 `--project` 指定根 |
| `未收集到任何文档` | 项目没有 PRD，也没有 change 的 brief/spec | 确认 change 目录下有 `brief.md` / `specs/*/spec.md`；旧版目录（`openspec/`、`docs/superpowers/`）不再支持 |
| `筛选后无任何文档` | `--changes` / `--task` 没命中，或命中的 change 没有产物 | 按报错提示换 `--changes`，或确认 change 名 |
| `导入命令执行失败` | 文件路径/后缀不合法，或 CLI 报错 | 脚本已复制成相对路径的 `.md` 文件；若仍失败，手动在临时目录跑一次 `lark-cli drive +import ...` 看完整报错 |
| `unsafe file path` | 给 `--file` 传了绝对路径 | 必须 `cd` 到文件目录后传文件名，勿改回绝对路径 |
| `232140101` / `232140100` / `233523001` | 同目录并发导入 | 串行重试（脚本本身串行；不要并发跑多个实例） |
| `导入未完成或失败` | 飞书转换排队或任务失败 | 按输出里的 `ticket` 调 `lark-cli drive +task_result --scenario import --ticket <t>` 续查；失败时看 `job_error_msg` |
| `删除失败` `1061007` | 文件已删除 | 视为目标已不可用，无需重试 |
| 旧文档没被覆盖 | 旧文档属于另一个用户/另一个应用，或不在本项目目录 | 去重只看当前用户云空间里的 `comate-spec/<项目名>/`；跨用户不会互删 |
| 收录了不该传的文档 | 范围判断 | 用 `--prd <关键字>` 过滤 PRD 目录 |
