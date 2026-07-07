---
name: wip-feishu
description: 飞书文档管理（上传/列出/搜索/读取/删除）
---

# wip-feishu

飞书文档管理，支持合并上传设计文档。

## 子命令

### `wip-feishu-upload [project]` ★

合并上传设计文档（总体设计 + 各模块设计）。

**合并规则**：
- 主文档：`.wip/{project}/design.md`（总体设计）
- 子文档：`.wip/{project}/modules/{module}/design.md`
- 不上传：`plan.md`（执行计划留在本地）

**执行流程**：
1. 确定项目（项目选择规则见 `wip-doc.md`）
2. 按顺序读取并合并设计文档
3. 调用飞书 API 创建文档
4. **自动更新 ledger.md**

### `wip-feishu-list`

列出飞书云空间中已上传的文档。

### `wip-feishu-search [keyword]`

按关键字搜索文档。

### `wip-feishu-read [keyword]`

读取文档完整内容。

### `wip-feishu-delete [keyword|doc_id|--all]`

删除文档。

## 前置依赖

- 脚本: `scripts/feishu_*.py`
- 飞书应用需有 `drive:drive` 和 `docx:document` 权限
- 配置：`.wip/config.json`（wip-init 自动创建）
