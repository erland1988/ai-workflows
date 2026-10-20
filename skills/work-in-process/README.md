# WorkInProcess

基于 `.wip/` 目录结构，管理从需求设计到编码实现的完整开发流程。

## 快速开始

```
wip-init "订单系统重构"        # 创建项目，AI 自动概括标题 + 智能英文命名 + 权限预检
wip-build                     # 生成设计文档（总体+模块）+ 执行计划（Phase/Step）
wip-check                     # 一次性全量检查（设计自洽性 + 计划完整性）
wip-code                      # 全自动编码：按依赖波次划分 → 波内无依赖模块后台子代理并行
wip-rollback                  # 编码中需求变更回退 → 回到 wip-build 重新讨论
wip-review                    # 终态校验（通过后自动归档到 docs/wip/）
wip-feishu                    # 可选：手动上传设计文档到飞书

# 会话中断后恢复
wip-load "order-system-v2"    # 加载项目上下文（进度/决策/Git 状态）
```

## 子技能（10 个）

| 子技能 | 功能 | 详见 |
|--------|------|------|
| `wip-init` | 初始化项目结构，AI 自动概括标题 + 智能英文命名 | `wip-init.md` |
| `wip-load` | 加载项目上下文，会话中断后恢复 | `wip-load.md` |
| `wip-build` | 生成设计文档（总体+模块）+ 执行计划（Phase/Step） | `wip-build.md` |
| `wip-check` | 编码前一次性全量检查 | `wip-check.md` |
| `wip-code` | 编码（唯一路径：波次并行流水线） | `wip-code.md` |
| `wip-review` | 编码后复核，终态校验（先修文档后修代码） | `wip-review.md` |
| `wip-rollback` | 编码中需求变更回退（清理残留 worktree + 丢弃已合并代码 + 清空 modules + 重置 ledger，回到设计阶段） | `wip-rollback.md` |
| `wip-clear` | 清空 .wip/ 下项目内容 + feature 分支（保留 .wip/ 目录 + config.json，不碰 docs/wip/） | `wip-clear.md` |
| `wip-doc` | 本地文档归档（review 通过后自动） | `wip-doc.md` |
| `wip-feishu` | 飞书文档上传（可选） | `wip-feishu.md` |

## 运行时目录结构

```
.wip/                          # 工作区根目录（wip-init 创建）
├── {project}/                 # 项目根目录
│   ├── design.md              # 总体设计文档（wip-build 填充）
│   ├── modules/               # 模块目录（wip-build 创建）
│   │   └── {module}/          # 按职责自动命名
│   │       ├── design.md      # 模块设计文档（wip-build 填充）
│   │       └── plan.md        # 执行计划（wip-build 生成）
│   └── ledger.md              # 进度账本（全阶段自动更新）
├── worktrees/                 # Git Worktree 目录（wip-code 管理，与项目目录平级）
│   └── {project}/
│       └── {module}/          # 模块独立工作区
└── config.json                # 归档目录配置（feishuFolderName，不提交 Git）
```

## 核心特性

- **智能命名**：用户输入中文描述 → AI 自动概括简洁标题 + 推荐英文项目/模块名
- **强制模块化**：简单需求=单模块，复杂需求=多模块拆分
- **一次产出**：wip-build 一次性生成设计文档 + 执行计划，中间无需用户介入
- **会话恢复**：`wip-load` 加载项目上下文，决策记录持久化，中断后无缝衔接
- **自动账本更新**：5 个状态列（设计/计划/检查/编码/审查），worktree 和合并作为编码内部步骤记入详细日志
- **子代理驱动**：全部编码走单个 implementer 子代理（实现 → 自审查 → 自修复 自循环），波内无依赖模块后台子代理并行，主会话任 coordinator
- **自动归档 + 可选云备份**：review 通过后自动写入 `docs/wip/`，飞书上传按需执行
- **Worktree 自动管理**：wip-code 自动创建 feature 分支、编码、合并、清理

## 技能内部结构

```
skills/work-in-process/
├── SKILL.md                    # 主技能定义 + 通用规则
├── README.md                   # 本文件
├── wip-init.md                 # 初始化项目结构
├── wip-load.md                 # 加载上下文，会话恢复
├── wip-build.md                # 生成设计文档 + 执行计划
├── wip-check.md                # 全量检查（一次性）
├── wip-code.md                 # 执行编码
├── wip-review.md               # 编码后复核（先修文档后修代码）
├── wip-rollback.md             # 编码中需求变更回退
├── wip-clear.md                # 清空 .wip/ 下项目内容（保留 .wip/ 目录 + config.json，不碰 docs/wip/）
├── wip-doc.md                  # 本地文档归档
├── wip-feishu.md               # 飞书文档上传（可选）
└── subagents/                  # wip-code 子代理提示词
    └── implementer.md          # 实现 + 自审查 + 自修复 一体
```

## 环境要求

- `lark-cli`（`@larksuite/cli`）与 Node ≥ 20：仅 `wip-feishu` 需要
- 飞书上传前执行 `lark-cli auth login`；`.wip/config.json` 只需 `feishuFolderName`（wip-init 自动创建，不提交 Git）
- 使用 `wip-code` 需系统安装 `git`
