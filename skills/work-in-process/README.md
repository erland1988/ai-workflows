# WorkInProcess

基于 `.wip/` 目录结构，管理从需求设计到编码实现的完整开发流程。

## 快速开始

```
wip-init "订单系统重构"        # 创建项目，AI 自动概括标题 + 智能英文命名 + 权限预检
wip-build                     # 生成设计文档（总体+模块）+ 执行计划（Phase/Step）
wip-check                     # 一次性全量检查（设计自洽性 + 计划完整性）
wip-code                      # 自动 worktree → 编码（子代理链） → 自动 merge
wip-review                    # 终态校验（design/plan/源码 三者一致性，先修文档后修代码）
wip-feishu-upload             # 合并上传设计文档到飞书

# 会话中断后恢复
wip-load "order-system-v2"    # 加载项目上下文（进度/决策/Git 状态）
```

## 子技能（8 个）

| 子技能 | 功能 | 详见 |
|--------|------|------|
| `wip-init` | 初始化项目结构，AI 自动概括标题 + 智能英文命名 | `wip-init.md` |
| `wip-load` | 加载项目上下文，会话中断后恢复 | `wip-load.md` |
| `wip-build` | 生成设计文档（总体+模块）+ 执行计划（Phase/Step） | `wip-build.md` |
| `wip-check` | 编码前一次性全量检查 | `wip-check.md` |
| `wip-code` | 编码（自动 worktree + 子代理驱动） | `wip-code.md` |
| `wip-review` | 编码后复核，终态校验（先修文档后修代码） | `wip-review.md` |
| `wip-clear` | 清空 .wip/（全部内容 + feature 分支），保留 config.json | `wip-clear.md` |
| `wip-feishu` | 飞书文档管理（上传/列出/搜索/读取/删除） | `wip-feishu.md` |

## 运行时目录结构

```
.wip/{project}/                # 项目根目录（wip-init 创建）
├── design.md                  # 总体设计文档（wip-build 填充）
├── modules/                   # 模块目录（wip-build 创建）
│   └── {module}/              # 按职责自动命名
│       ├── design.md          # 模块设计文档（wip-build 填充）
│       └── plan.md            # 执行计划（wip-build 生成）
├── ledger.md                  # 进度账本（全阶段自动更新）
└── worktrees/                 # Git Worktree 目录（wip-code 自动管理）
    └── {project}/
        └── {module}/          # 模块独立工作区
```

## 核心特性

- **智能命名**：用户输入中文描述 → AI 自动概括简洁标题 + 推荐英文项目/模块名
- **强制模块化**：简单需求=单模块，复杂需求=多模块拆分
- **一次产出**：wip-build 一次性生成设计文档 + 执行计划，中间无需用户介入
- **会话恢复**：`wip-load` 加载项目上下文，决策记录持久化，中断后无缝衔接
- **自动账本更新**：7 列进度表（设计/计划/worktree/编码/审查/合并），会话 compact 后无损恢复
- **子代理驱动**：复杂任务自动启用 3 子代理链（实现 → 审查 → 修复）
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
├── wip-clear.md                # 清空 .wip/（保留 config.json）
├── wip-feishu.md               # 飞书文档管理
├── subagents/                  # wip-code 子代理提示词
│   ├── implementer.md
│   ├── reviewer.md
│   └── fixer.md
├── scripts/                    # 6 个 Python 脚本（飞书 API 调用）
│   ├── feishu_common.py        # 公共库（认证/HTTP/工具）
│   ├── feishu_upload.py        # 上传设计文档
│   ├── feishu_list.py          # 列出文档
│   ├── feishu_search.py        # 搜索文档
│   ├── feishu_read.py          # 读取文档内容
│   └── feishu_delete.py        # 删除文档
└── templates/
    └── list.json               # 飞书列表输出模板
```

## 环境要求

- Python 3.7+
- `requests` 库：在 `scripts/` 目录执行 `pip install -r requirements.txt`
- 飞书功能需配置 `.wip/config.json`（wip-init 自动创建，不提交 Git，`drive:drive` + `docx:document` 权限）
- 使用 `wip-code` 需系统安装 `git`


