---
name: wip-doc
description: 本地文档存储（合并/列出/搜索/读取/删除），与飞书云存储形成双通道归档
---

# wip-doc

本地文档存储，将 `.wip/` 下的设计文档合并归档至 `docs/wip/`。**所有操作由 AI 直接执行（shell 命令 + 文件读写），无需 Python 脚本。**

## 归档目录

```
docs/wip/                           ← wip-doc-store 首次执行时自动创建
├── 20260707_订单系统重构.md
├── 20260707_支付对接改造.md
└── ...
```

**文件命名规范**：`{YYYYMMDD}_{项目描述}.md`

- 日期取 store 执行当天
- 项目描述来自 `ledger.md` 中的 `- 描述:` 字段，空格替换为 `-`

## 子命令

### `wip-doc-store [project]` ★

合并设计文档（总体设计 + 各模块设计），写入 `docs/wip/`。

**合并规则**（与飞书版一致）：
- 主文档：`.wip/{project}/design.md`（总体设计）
- 子文档：`.wip/{project}/modules/{module}/design.md`
- 不归档：`plan.md`（执行计划留在本地）

**执行流程**：
1. 确定项目（自动选择逻辑见下方）
2. 从 `ledger.md` 读取项目描述
3. 确保 `docs/wip/` 目录存在（不存在则 `mkdir -p`）
4. 按顺序读取并合并设计文档（格式同飞书版：总体设计 → 各模块设计 → 附录元数据）
5. 写入 `docs/wip/{YYYYMMDD}_{描述}.md`
6. **自动更新 ledger.md**（记录 `doc_stored` 事件）

**合并后的文档结构**：
```markdown
# {项目描述} 完整设计文档

> 生成时间: YYYY-MM-DD HH:mm:ss
> 项目路径: .wip/{project_name}/

---

# 第一部分：总体设计

{design.md 内容，去掉已有的 # 标题行}

---

# 第二部分：模块设计

## 模块: {module-name}

{模块 design.md 内容，去掉已有的 # 标题行}

---

# 附录：项目元数据

| 属性 | 值 |
|------|-----|
| 项目名称 | {project_name} |
| 模块数量 | N |
| 归档时间 | YYYY-MM-DD |
```

### 项目选择规则

`[project]` 未指定时：① 会话上下文 > ② `.wip/` 只有1个项目 > ③ 多项目列出来选 > ④ 无项目报错。`wip-doc-store` 和 `wip-feishu-upload` 共用。

### `wip-doc-list`

列出 `docs/wip/` 下所有归档文档。

**输出格式**：

```
docs/wip/
  20260707_订单系统重构.md
  20260707_支付对接改造.md

共 N 篇文档
```

如果目录为空：
```
docs/wip/ 暂无归档文档
```

### `wip-doc-search <关键字>`

按标题关键字搜索本地归档。

**执行**：`ls docs/wip/ | grep -i "<关键字>"`

**输出**：
```
匹配 N 篇文档：
  20260707_订单系统重构.md
```

### `wip-doc-read <关键字|文件名>`

读取并输出指定文档的完整内容。

**匹配策略**：
1. 文件名精确匹配（含 `.md` 后缀）→ 直接读取
2. 关键字模糊匹配 `docs/wip/` 中的文件名
   - 匹配到 1 篇 → 直接输出
   - 匹配到多篇 → 列出让用户选择
   - 未匹配 → 报错

**输出**：直接打印文件内容到终端。

### `wip-doc-delete <关键字|文件名|--all>`

删除指定归档文档。

**匹配策略**：
- `--all`：列出全部文档，二次确认后全部删除
- 文件名精确匹配 → 确认后删除
- 关键字模糊匹配：
  - 匹配到 1 篇 → 确认后删除
  - 匹配到多篇 → 列出让用户选择

> 仅删除 `docs/wip/` 下的归档文件，不影响 `.wip/` 源文件。

## 与飞书对照

| 动作 | 本地 | 飞书云端 |
|------|------|----------|
| 存储 | `wip-doc-store` | `wip-feishu-upload` |
| 列出 | `wip-doc-list` | `wip-feishu-list` |
| 搜索 | `wip-doc-search` | `wip-feishu-search` |
| 阅读 | `wip-doc-read` | `wip-feishu-read` |
| 删除 | `wip-doc-delete` | `wip-feishu-delete` |
