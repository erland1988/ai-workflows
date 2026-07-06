# Claude Code 自定义命令与技能仓库

个人 Claude Code 工具配置仓库。

## 内容

| 目录 | 用途 |
|------|------|
| `commands/` | 自定义命令 |
| `skills/` | 技能模块（详见各技能 README） |

## 使用方式

将 `skills/` 和 `commands/` 复制到目标项目的 `.claude/` 目录下即可。


## 问题
work-in-process技能 Write 工具不可用，改用 Bash 写入文件。
work-in-process技能 总体设计文档添加数据库DDL
work-in-process技能 没有明确指令，例如wip-code,不要编写代码
work-in-process技能 review报告是否需要、中文问题
work-in-process技能 wip-clear 不删除config.json重要
单个模块是不是不走worktree和合并