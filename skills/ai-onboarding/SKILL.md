---
name: ai-onboarding
description: 把项目改造成「AI 开箱能接手」的状态 —— 调研代码生成架构/接口文档（每条约束标注实测出处）、接入 comate 1.0（含 0.x 迁移）、编写 AGENTS.md、补 README。当用户说「给这个项目补文档」「让 AI 能维护这个项目」「项目文档初始化」「新项目上手」「建立文档体系」时使用。
---

# AI Onboarding

把一个「AI 打不开局面」的项目，改造成「AI 开箱能接手」的状态。

## 这个技能解决什么

接手一个缺乏文档的老项目时，几乎必然遇到：

- README 只有几十行启动命令
- 架构知识散落在代码里，没人写下来
- **AI 打开项目读不到任何指令**，只能靠人现场讲解

结果是每次接手都从零调研一遍。本技能把这次调研**固化成文档**，并让 AI 下次能自动读到。

## 三条铁律

1. **每条约束标注实测出处**（`文件:行`）。未经验证的推断不写入文档 —— **写错出处比不写更误导**。
2. **索引式，不复制内容**。`AGENTS.md` 只负责把 AI 引向单一事实源，不搬运内容，否则必然不同步。
3. **不写验证不了的内容**。读不出来的字段宁可留空或标「待确认」，也不猜。

## 前置条件

- Node.js >= 20、git（comate 1.0 的硬性要求）
- 项目根目录能执行 `comate`；未安装时：
  `npm install -g @house365/comate@next --registry=https://registry.npmjs.org`
- 试用期**不要**用 `comate update` 或安装 `@latest`（当前 `latest` 仍是旧版 0.10.x）

---

## 阶段 0：调研（不可跳）

**先摸清事实，一行文档都不写。**

| 维度 | 怎么查 |
|---|---|
| 技术栈 | `composer.json` / `package.json` / `pom.xml` / `go.mod` |
| 应用与分层 | 目录结构 + 各层文件数 |
| 路由方式 | 显式路由文件 vs 框架默认解析 |
| 统一返回 | 找基类 / trait 里的 `success` / `error` / `jsonApi` |
| 认证与权限 | 中间件、守卫、注解 |
| 数据层 | ORM、表前缀、软删除、模型里的 `$table` |
| 异步与定时 | 队列调用点、command、cron、常驻进程 |
| 外部依赖 | 搜 HTTP 客户端调用，按服务归类 |
| 本地怎么跑 | README、Dockerfile、CI 配置 |

> 调研结论**必须能落到 `文件:行`**。落不到的就是没查实，标「待确认」而不是猜。

---

## 阶段 1：接入 comate 1.0

comate 1.0 只有**一个 `/comate` skill** + 一个零依赖 Node 状态机，流程为
`open（写 brief + spec，停①确认）→ build ⇄ verify（独立 verifier 逐项验收）→ archive（归档进主规格）`。
所有资料统一放在项目根 `comate/`，旧版的 `openspec/`、`docs/architecture/`、`docs/knowledge-base/` 不再作为主目录。

先判断项目现状，再走对应路径：

| 现状 | 走哪条 |
|---|---|
| 全新项目，无 `docs/architecture/`、`docs/knowledge-base/`、`openspec/` | 1A 全新初始化 |
| 存在上述任一旧目录，或用过 comate 0.x | 1B 0.x 迁移 |

### 1A 全新初始化

```bash
comate init
```

生成：

```
comate/
├── architecture/          # 架构规范（本技能阶段 2、3 写入）
├── knowledge-base/        # requirements/（PRD）+ integrations/（第三方对接档案）
└── comate/
    └── config.json        # 构建 / 验收命令
```

`comate/comate/specs/`、`comate/comate/changes/` 由 `comate new` / 归档流程创建，不要手工预建。

### 1B 0.x / openspec 项目迁移

```bash
comate init --migrate --dry-run    # 先核对清单，不应有目标目录冲突
comate init --migrate
comate import-specs --dry-run      # 核对 openspec/specs/<能力>/spec.md → comate/comate/specs/
comate import-specs
git status --short
```

迁移要点：

- 旧目录搬迁映射：`docs/knowledge-base/` → `comate/knowledge-base/`，`docs/architecture/` → `comate/architecture/`
- `openspec/specs/` **源文件保留**，只是复制主规格；`openspec/changes/archive/` 原地保留，不转换
- 存在进行中的 0.x change 时**先不要升级**，用旧版完成并归档
- `import-specs` 遇冲突不覆盖，且无冲突文件可能已复制成功 —— 检查工作区后手动合并
- 项目内若有旧版 `.claude/skills/comate*`、`.agents/skills/comate*` 独立副本，会遮蔽新版用户级 skill，先备份并移出扫描目录

### 1C 配置并验证（两条路径都要做）

编辑 `comate/comate/config.json`，按项目实际情况填写（保留其他字段）：

```json
{
  "build_command": "npm run build",
  "verify_command": "npm test"
}
```

- `null` 表示自动探测；项目确实没有该命令时写 `"none"`
- `verify_command` 是 handoff 的硬门槛，不配置且探测不到，流程会卡住

```bash
comate doctor
comate status
```

`doctor` 只检查环境和配置，**不会替你跑构建和测试** —— 手动执行一遍刚配置的命令。

> 团队确定不用 comate 时跳过本阶段，架构/接口文档改放 `docs/architecture/`，并在 `AGENTS.md` 中保持一致。

---

## 阶段 2：架构文档

产出 `comate/architecture/backend-architecture.md`（前端项目另起 `frontend-architecture.md`）。

章节骨架（按项目实际增删）：

```
 1. 技术栈                 7. 数据层约定
 2. 应用与分层             8. 接口契约（易踩）
 3. 路由与参数注入         9. 已知风险（实测发现，未修）
 4. 接口返回与登录态      10. 环境与运维
 5. 权限模型              11. 相关文档
 6. 异步与定时任务
```

要点：

- 每条约束后面跟 `文件:行`
- 「已知风险」**只写实测确认的**，并标注「未修」
- 表格优先于段落
- 这是**架构规则**，不是 capability spec —— 不要放进 `comate/comate/specs/`
- `/comate` 在 open 阶段会要求 brief 的「约束与不变量」「决定」对齐这里的条目

---

## 阶段 3：接口文档

产出 `comate/architecture/api-contract.md`。

**只写对外接口** —— 后台 CRUD 接口改版频繁，为它们写文档是负债。

每个接口包含：路径、用途、参数表、响应示例、错误码、**可运行的 cURL**。
签名 / 认证机制单独一节写清楚（这是调用方最容易踩的地方）。

> cURL 里的签名值要**真算出来**，不写占位符 —— 能直接跑通到鉴权那一层才有价值。

第三方服务对接**不进本文档**，按 `comate/knowledge-base/integrations/<service>/` 建档
（模板见 `_TEMPLATE/`，也可用 `/comate-kb-integration` 生成 `README.md` + `api-snapshot.md`）。

---

## 阶段 4：AGENTS.md ⭐

产出根目录 `AGENTS.md` —— **让 AI 自动接手的关键**。

章节骨架：

```
## 项目是什么        一句话 + 关键领域概念
## 技术栈            含「必需依赖」「有无测试」这类关键事实
## 文档地图 ⭐        告诉 AI 去哪读 ← 核心章节
                     comate/architecture/      架构规则与接口契约
                     comate/knowledge-base/    PRD 与第三方对接档案
## 本地运行          指向 README，只留要点
## 变更流程          /comate：open → build → verify → archive
                     变更产物在 comate/comate/changes/，归档进 comate/comate/specs/
## 代码约定（摘要）   分层 / 路由 / 返回格式，标注「详情见 comate/architecture」
## 已知坑            指向 architecture 的已知风险章节
```

> **Claude Code 2.1.296+ 原生支持 `AGENTS.md`**：项目没有 `CLAUDE.md` 时自动加载它，
> 「位置和方式与 CLAUDE.md 完全相同」。因此**不需要**另外创建 `CLAUDE.md`。
>
> 其他工具：Cursor、Cline 同样识别根目录 `AGENTS.md`；Cline 可另加 `.clinerules` 指向它。

---

## 阶段 5：README

补齐三块（缺什么补什么）：

- **环境地址** —— 各环境域名与入口
- **本地开发** —— 域名解析 → web 服务器站点 → 环境文件与依赖
- **AI 协作** —— 一句话说明仓库有 `AGENTS.md`，AI 工具会自动读取；文档在 `comate/architecture/`

---

## 红线

1. **不写本机特有信息**（IP、容器名、宿主机路径）—— 各人环境不同，写死了会误导。用 `<占位符>` 或指向 README。
2. **不写敏感信息** —— 密码、密钥、**密码重置步骤**都不写入。单看每一项无害，凑起来就是接管系统的攻略；而 Git 历史永久保留，事后删除也清不干净。
3. **引用必须验证存在** —— 文档里指向的文件、章节、行号，写完要回验一遍。
4. **改了被引用的文档，要回验引用** —— 例如 README 增删行后，架构文档里的 `README.md:NN-MM` 会漂移。
5. **不从代码逆向「对接档案」** —— 外部依赖的 URL / 参数代码里本来就有，AI 读代码更准。档案的价值在代码之外的知识（响应格式、限流、联系人），拿不到就别建。
6. **不手改 comate 状态** —— `comate/comate/changes/<name>/state.json` 只由脚本写入，手改会被下一条命令校验发现；架构文档、接口文档不进 `comate/comate/specs/`。

---

## 收尾

- 提交前确认 `.env` 等敏感文件未被暂存
- `comate doctor` 无失败项、`comate status` 能正常执行
- 若项目使用 git 分支流程，走一次完整流转
- **让用户开一个新会话验证**：AI 能否不被告知就说出项目概况
