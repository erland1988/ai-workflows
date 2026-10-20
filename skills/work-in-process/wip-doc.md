---
name: wip-doc
description: 本地设计文档归档，wip-review 通过后自动执行
---

# wip-doc

把 `.wip/` 下的设计文档合并归档至 `docs/wip/`。**所有操作由 AI 直接执行（shell 命令 + 文件读写），无需脚本。**

## 归档目录

```
docs/wip/                           ← wip-doc 首次执行时自动创建
├── 20260707_订单系统重构.md
├── 20260707_支付对接改造.md
└── ...
```

**文件命名规范**：`{YYYYMMDD}_{项目描述}.md`

- 日期取 wip-doc 执行当天
- 项目描述来自 `ledger.md` 中的 `- 描述:` 字段，空格替换为 `-`

## 用法

`wip-doc [project]` ★

合并设计文档（总体设计 + 各模块设计），写入 `docs/wip/`。

**自动执行**：`wip-review` 审查通过、ledger 更新后会自动调用一次；也可在任意阶段手动执行。同一天重复执行会覆盖同名文件。

**合并规则**：遵循 SKILL.md「合并输出规范」——主文档 `design.md` + 各模块 `design.md`，模块按依赖顺序排列，不纳入 `plan.md`。

**执行流程**：

1. 确定项目（自动选择逻辑见下方）
2. 从 `ledger.md` 读取项目描述
3. 确保 `docs/wip/` 目录存在（不存在则 `mkdir -p`）
4. 按顺序读取并合并设计文档（总体设计 → 各模块设计 → 附录元数据）
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

## 项目选择规则

`[project]` 未指定时：① 会话上下文 > ② `.wip/` 只有1个项目 > ③ 多项目列出来选 > ④ 无项目报错。`wip-doc` 和 `wip-feishu` 共用。

## 本地文档操作

`list / search / read / delete` 功能已移除。需要查看、搜索或删除归档时，直接用文件系统或编辑器操作 `docs/wip/`，无需额外命令。
