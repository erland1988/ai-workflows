---
name: wip-init
description: 初始化 .wip/ 项目结构，中文描述智能推荐英文项目名
---

# wip-init

初始化 `.wip/` 项目结构，支持中文描述智能推荐英文项目名。**所有操作由 AI 直接执行，无需调用外部脚本。**

## 完整执行流程

### 前置检查

执行 wip-init 前先确认环境（权限预检）：

```bash
git rev-parse --is-inside-work-tree 2>/dev/null && echo "OK" || echo "NOT_GIT"
```

- 不在 git 仓库 → 提示用户当前目录不是 git 仓库，初始化或切换目录后重试
- 在 git 仓库 → 继续

### 步骤 0：获取项目描述

用户可能已提供描述，如果没有，主动询问：

> 请描述你要开发的项目或需求（中文），例如："订单系统重构""用户权限改造""支付模块优化"

### 步骤 1：总结项目标题

用户输入可能比较啰嗦或不适合直接当标题。AI 分析用户描述，提炼出一个简洁的项目标题（≤20 字），作为 `{description}`。

**总结原则**：
- 抓核心动词 + 核心对象，去掉废话和修饰词
- 如"我想把支付那块重新弄一下，主要是支付宝和微信的对接" → `支付对接改造`
- 如"订单表字段太多了查询慢，需要拆分冷热数据优化性能" → `订单冷热分离`
- 不确定时保留原始含义优先，不随意发散

向用户展示并等待确认：

```
📝 项目标题: {概括后的标题}

确认使用此标题？(y/n)，或直接输入自定义标题：
```

用户确认后确定 `{description}`。

### 步骤 2：智能命名

根据 `{description}` 分析关键词并推荐 2-3 个英文项目名。

**命名规范**：kebab-case（全小写短横线），如 `order-system-refactor`

向用户展示推荐选项，询问：

```
推荐以下项目名，请选择或自定义：

1. {option1}
2. {option2}
3. {option3}

输入序号（默认 1），或直接输入自定义名称（kebab-case）：
```

用户选择后确定 `project_name`：
- 如果输入纯数字 → 取对应序号的推荐名
- 如果输入字符串 → 转为 kebab-case 后使用（替换 `_` 和空格为 `-`，移除特殊字符，全小写）

### 步骤 3：创建目录结构

**分两步独立执行**，`.wip/` 和 `docs/wip` 互不影响。

**3a. 创建 `.wip/{project_name}` 目录**（仅 `modules/` 空壳，不预建任何模块子目录）：

```bash
mkdir -p ".wip/{project_name}/modules"
```

**3b. 创建 `docs/wip` 目录**（与 3a 分开执行）：

先检测 `docs/wip` 是否已作为文件存在：

```bash
test -f docs/wip && echo "IS_FILE" || (test -d docs/wip && echo "IS_DIR" || echo "NOT_EXIST")
```

- `IS_DIR` → 已存在，无需创建
- `NOT_EXIST` → 执行 `mkdir -p "docs/wip"`
- `IS_FILE` → **报错**：`docs/wip` 已作为文件存在，无法创建同名目录。提示用户手动处理（删除或改名该文件）后重试

> ⚠️ 即使 `docs/wip` 创建失败，也不影响 `.wip/` 目录（已在 3a 独立完成）。

### 步骤 4：生成 design.md（总体设计骨架）

写入 `.wip/{project_name}/design.md`：

```markdown
# {description} 总体设计

> `{description}` = 用户最初输入的中文描述（如"订单系统重构"），`{project_name}` 仅用于目录命名。

## 参考资料

## 需求背景
- 触发条件：
- 范围边界：
- 前置校验：
- 状态约束：
- 幂等语义：

## 设计方案

### 总体思路

### 架构概要

### 数据库概览

<!-- 表清单，不写 DDL。完整 DDL 见各模块设计 -->

| 表名 | 用途 | 所属模块 | 关键字段 |
|------|------|----------|----------|
| orders | 订单主表 | data-models | id, user_id, status, amount |

### 关键决策

## 模块划分

| 模块 | 说明 | 前置依赖 |
|------|------|----------|
| TBD | 待 wip-build 分析后填充 | - |

## 变更文件汇总（预估）

## 依赖关系图
```

### 步骤 5：生成 ledger.md（进度账本）

读取当前 git 分支作为基分支：

```bash
git rev-parse --abbrev-ref HEAD
```

将其写入 ledger 项目信息区的「基分支」字段。

写入 `.wip/{project_name}/ledger.md`：

```markdown
# 项目进度账本: {project_name}

## 项目信息
- 名称: {project_name}
- 描述: {description}
- 基分支: {base_branch}        ← 当前 git 分支（wip-code 合并目标）
- 创建时间: {YYYY-MM-DD HH:mm:ss}
- 当前阶段: design
- 最后更新: {YYYY-MM-DD HH:mm:ss}

## 模块进度
| 模块 | 设计 | 计划 | 检查 | 编码 | 审查 |
|------|------|------|------|------|------|
| TBD | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |

## 详细日志
| 时间 | 模块 | 动作 | 详情 | 提交 |
|------|------|------|------|------|
| {HH:mm} | - | project_init | 项目初始化 | - |

## 阻塞问题
<!-- 如有 BLOCKED 状态记录这里 -->

## 决策记录
<!-- 各阶段关键决策，按日期分组 -->
```

> `{YYYY-MM-DD HH:mm:ss}` 和 `{HH:mm}` 替换为执行时的实际时间。

### 步骤 6：检查飞书配置

检查 `.wip/config.json` 是否存在：

```bash
test -f .wip/config.json && echo "EXISTS" || echo "NOT_FOUND"
```

如果不存在 → 创建：

```json
{
  "feishuAppId": "",
  "feishuAppSecret": "",
  "feishuFolderName": "work-in-process"
}
```

> 用户后续填入飞书应用的 `feishuAppId` 和 `feishuAppSecret` 后，`wip-feishu-upload` 等命令即可使用。

### 步骤 7：更新 .gitignore

检查项目根目录的 `.gitignore`：
- 如果文件不存在 → 创建并写入 `.wip/` 和 `.claude/`
- 如果文件存在 → 检查并追加缺失的条目：
  - 无 `.wip/` 条目 → 追加 `.wip/`
  - 无 `.claude/` 条目 → 追加 `.claude/`
  - 已有对应条目 → 跳过

> `.wip/` 是项目设计文档，视团队需要决定是否提交。`.claude/` 是个人配置（skills/commands/settings），不提交。

### 步骤 8：输出确认

目录结构创建完成后，向用户汇报：

```
✅ 项目 {project_name} 已初始化

📁 .wip/{project_name}/
   ├── design.md          ← 总体设计（待 wip-build 填充）
   ├── modules/            ← 空目录（待 wip-build 按需创建模块）
   └── ledger.md          ← 进度账本

📁 docs/wip/              ← 本地归档目录（空）

📋 下一步：
   - 讨论需求细节
   - 执行 wip-build 生成分模块设计

> ⚠️ **只产出 .wip/ 目录文件和 .claude/ 配置，禁止修改任何项目源码。** 编码从 wip-code 开始。
```

## 异常处理

| 情况 | 处理方式 |
|------|---------|
| `.wip/{project_name}` 已存在 | 提示用户项目已存在，询问是否覆盖或换名 |
| `docs/wip` 已作为文件存在 | 报错，提示用户手动删除或改名该文件后重试。不影响 `.wip/` 创建 |
| 用户输入无效序号 | 提示重新选择，默认使用选项 1 |
| 项目名包含非法字符 | 自动清理：替换 `_` 和空格为 `-`，移除 `[^\w\-]`，转小写 |

## 与 wip-build 的衔接

wip-init 只创建 `modules/` 空目录，不预建任何模块骨架。后续：
- `wip-build` 根据需求分析，按需创建模块子目录并生成设计文档
