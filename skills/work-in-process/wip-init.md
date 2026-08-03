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

在当前工作区的项目根目录下执行：

```bash
mkdir -p ".wip/{project_name}/modules/core"
mkdir -p "docs/wip"
```

如果 `.wip/` 目录已存在，无需重复创建根目录。`docs/wip/` 同理。

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
| core | 待定义 | 无 |

## 变更文件汇总（预估）

## 依赖关系图
```

### 步骤 5：生成 modules/core/design.md（模块设计骨架）

写入 `.wip/{project_name}/modules/core/design.md`：

```markdown
# core 设计

## 模块边界

### 职责

### 不做的事

### 接口契约

## 数据模型

## 状态机（如有）

## 实现思路

## 预估变更
| 文件 | 操作 | 说明 |
|------|------|------|

## 依赖
- 前置模块: 无
- 后置模块: 无
```

### 步骤 6：生成 ledger.md（进度账本）

写入 `.wip/{project_name}/ledger.md`：

```markdown
# 项目进度账本: {project_name}

## 项目信息
- 名称: {project_name}
- 描述: {description}
- 创建时间: {YYYY-MM-DD HH:mm:ss}
- 当前阶段: design
- 最后更新: {YYYY-MM-DD HH:mm:ss}

## 模块进度
| 模块 | 设计 | 计划 | 检查 | 编码 | 审查 |
|------|------|------|------|------|------|
| core | ⬜ | ⬜ | ⬜ | ⬜ | ⬜ |

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

### 步骤 7：检查飞书配置

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

### 步骤 8：更新 .gitignore

检查项目根目录的 `.gitignore`：
- 如果文件不存在 → 创建并写入 `.wip/` 和 `.claude/`
- 如果文件存在 → 检查并追加缺失的条目：
  - 无 `.wip/` 条目 → 追加 `.wip/`
  - 无 `.claude/` 条目 → 追加 `.claude/`
  - 已有对应条目 → 跳过

> `.wip/` 是项目设计文档，视团队需要决定是否提交。`.claude/` 是个人配置（skills/commands/settings），不提交。

### 步骤 9：输出确认

目录结构创建完成后，向用户汇报：

```
✅ 项目 {project_name} 已初始化

📁 .wip/{project_name}/
   ├── design.md          ← 总体设计（待 wip-build 填充）
   ├── modules/
   │   └── core/
   │       └── design.md  ← 模块设计（待 wip-build 填充）
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
| 用户输入无效序号 | 提示重新选择，默认使用选项 1 |
| 项目名包含非法字符 | 自动清理：替换 `_` 和空格为 `-`，移除 `[^\w\-]`，转小写 |

## 与 wip-build 的衔接

wip-init 只创建单模块骨架（`modules/core/`），后续：
- `wip-build` 根据需求分析，将 `core` 拆分为多个模块
- `wip-build` 填充各模块的设计文档
