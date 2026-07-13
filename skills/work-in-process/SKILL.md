---
name: work-in-process
description: 当用户需要规划、设计、拆解一个开发需求，或提到 wip、技术方案、执行计划时使用。基于 .wip/ 目录管理设计与执行，支持多项目独立管理。
---

# WorkInProcess

基于 `.wip/` 目录结构，管理从需求设计到编码实现的完整开发流程。

## 核心特性

- **智能命名**：中文描述 → 英文项目/模块名
- **强制模块化**：设计文档 + 执行计划（wip-build 一次性产出）
- **多项目并行**：各自独立目录
- **会话恢复**：`wip-load` 加载项目上下文，决策记录持久化
- **自动账本更新**：进度持久化
- **子代理驱动**：复杂模块整编（实现 → 审查 → 修复）

## 目录结构

```
.wip/{project-name}/
├── design.md                   # 总体设计（wip-build 生成）
├── modules/
│   └── {module-name}/          # 自动命名
│       ├── design.md           # 模块设计
│       └── plan.md             # 执行计划（wip-build 生成）
└── ledger.md                   # 进度账本（自动更新）

docs/wip/                       # 本地归档（wip-doc-store 产出）
├── 20260707_订单系统重构.md
└── ...
```

## 工作流程:

```
wip-init "订单系统重构"
    ↓
wip-build → 生成分模块设计 + 执行计划
    ↓
wip-check → 一次性全量检查（设计自洽性 + 计划完整性）
    ↓
wip-code → 编码（全自动：按依赖排序串行执行；或 wip-code <模块名> 精确控制）
    ↓
wip-review → 复核
    ↓
wip-doc-store / wip-feishu-upload → 本地归档 / 飞书上传设计文档
```

会话中断后:
```
wip-load "订单系统重构" → 加载完整上下文（进度/决策/Git 状态）→ 继续工作
```

## 子技能

| 子技能 | 功能 |
|--------|------|
| `wip-init` | 初始化项目结构，智能命名 |
| `wip-load` | 加载项目上下文，恢复中断的会话 |
| `wip-build` | 生成设计文档（总体+模块）+ 执行计划 |
| `wip-check` | 设计完整性检查（一次性全量） |
| `wip-code` | 执行编码（wip-code 全自动串行，或 wip-code <模块名> 精确控制） |
| `wip-review` | 编码后复核（design/plan/源码 三者一致性校验，先修文档后修代码） |
| `wip-clear` | 清空 .wip/ 目录 |
| `wip-feishu` | 飞书文档管理 |
| `wip-doc` | 本地文档存储 |

## 文件位置

| 类型 | 位置 | 说明 |
|------|------|------|
| 子技能 | `wip-*.md`（9 个） | 按子技能名直接访问，AI 直执行 |
| 子代理提示词 | `subagents/` | `implementer.md` / `reviewer.md` / `fixer.md` |
| 飞书脚本 | `scripts/feishu_*.py`（6 个） | Python API 调用 |

各子技能详见对应 md 文件。子代理按模块粒度触发，详见 `wip-code.md`。

### 飞书子命令：通用环境要求

所有 `wip-feishu-*` 子命令通过 `scripts/` 目录下的 Python 脚本与飞书 API 交互。

**前置依赖**：
- **Python 3.7+**
- **`requests` 库**：在 `scripts/` 目录执行 `pip install -r requirements.txt`

**飞书应用权限**：
- 上传/列出/搜索/删除：`drive:drive`
- 读取文档内容：额外需要 `docx:document`

**配置文件**：
- `wip-init` 首次执行时自动在 `.wip/config.json` 生成飞书配置模板（不提交 Git）
- 用户填入飞书应用的 `feishuAppId`、`feishuAppSecret` 后，飞书功能即可使用
- 格式：`{"feishuAppId": "", "feishuAppSecret": "", "feishuFolderName": "work-in-process"}`

## Ledger 机制（进度账本）

`.wip/{project}/ledger.md` 用于持久化项目进度，防止会话 compact 后丢失上下文。

**自动更新时机**：
| 命令 | 更新内容 |
|------|----------|
| `wip-init` | 创建项目，当前阶段 = design |
| `wip-build` | 标记设计+计划完成，更新模块列表，追加决策记录 |
| `wip-check` | 标记检查通过/问题清单，当前阶段 = check |
| `wip-code` | 模块级事件 + worktree 管理 + 决策记录 |
| `wip-review` | 标记审查完成 |
| `wip-feishu-upload` | 标记已上传飞书 |
| `wip-doc-store` | 标记已归档本地 |

**ledger.md 格式**：

```markdown
# 项目进度账本: {project-name}

## 项目信息
- 名称: {project-name}
- 描述: {description}
- 创建时间: YYYY-MM-DD HH:mm:ss
- 当前阶段: design/check/coding/review/done

## 模块进度
| 模块 | 设计 | 计划 | 检查 | 编码 | 审查 |
|------|------|------|------|------|------|
| data-models | ✅ | ✅ | ✅ | 🔄 | ⬜ |
| business-logic | ✅ | ⬜ | ⬜ | ⬜ | ⬜ |

## 详细日志
| 时间 | 模块 | 动作 | 详情 | 提交 |
|------|------|------|------|------|
| 10:00 | data-models | worktree_created | Worktree 已创建 | - |
| 10:20 | data-models | implementer_done | 子代理完成编码 | - |
| 10:25 | data-models | reviewer_pass | 审查通过 | - |
| 10:45 | data-models | worktree_merged | 已合并 | b2c3d4e |

常用动作: `project_init`, `plan_created`, `worktree_created`, `step_start/complete`（仅模式A）, `implementer_done`, `reviewer_pass`, `fixer_applied`, `reviewer_roundN`, `worktree_merged`, `check_passed`, `review_done`, `doc_stored`, `feishu_uploaded`

## 阻塞问题
<!-- 如有 BLOCKED 状态记录这里 -->

## 决策记录

记录各阶段关键决策。按日期分组，每条一行。

### YYYY-MM-DD
- **[wip-build]** 项目拆分为 3 个模块 —— 数据层/业务层/接口层职责清晰
- **[wip-build]** 每 Phase 上限 3 Step
```

## 通用规则

### 编码边界（最高优先级）

**在 wip-code 之前，只产出设计文档（`.wip/` 目录），禁止修改任何项目源码。**

| 阶段 | 允许产出 | 禁止 |
|------|---------|------|
| wip-init | `.wip/{project}/` 骨架文件 | 新建/修改源码 |
| wip-build | `.wip/{project}/design.md` + 模块设计 + plan.md | 新建/修改源码 |
| wip-check | 检查报告（口头输出 + ledger 更新） | 新建/修改源码 |
| wip-code | ✅ 按计划写代码 | — |
| wip-review | 修正 design/plan 文档、审查结果 | 改源码（交 fixer 子代理改） |

违反此规则视为流程错误，必须回退。

### 每个步骤必须可执行

每个步骤缺一不可，禁止放入"仅确认""参考""梳理现有行为"等非执行项：

- **文件**：目标文件路径，标注新建/修改/删除
- **位置**：精确到方法名 + 行号锚点，让改动落点无歧义
- **背景**：为何改（仅在改动原因不直观时需要）
- **操作**：具体代码/SQL，可直接落地
- **验证**：编译/单测/联调的具体方式

### 独立章节要求

执行计划中必须有独立的顶层章节：

- **变更文件汇总**：表格 `# | 文件 | 操作 | 对应阶段`，带阶段回溯列
- **构建顺序**：依赖图 + 阶段内并行链路说明

以下内容必须融入执行计划各步骤，禁止独立成节：

- 数据库变更 → 融入数据层阶段的步骤
- 详细实现方案 → 融入业务逻辑层阶段的步骤

### 自查清单

- [ ] 数据变更涉及事务时已正确处理原子性
- [ ] 常量/枚举定义完整，边界条件已正确处理
- [ ] SQL 或配置替换精确匹配源码（含原有缩进格式）
- [ ] 已规避目标语言的常见陷阱（如变量捕获/作用域、可变默认值、隐式类型转换等）
- [ ] 资源（连接/句柄/锁/事务）已正确释放，无泄漏
- [ ] 查询方法变更后空结果处理正确
- [ ] 新增字段/表/属性与现有命名风格一致