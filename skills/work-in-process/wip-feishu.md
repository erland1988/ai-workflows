---
name: wip-feishu
description: 飞书文档上传，可选步骤
---

# wip-feishu

把 `.wip/` 下的设计文档合并后上传到飞书云文档。**上传是可选的**：由 `wip-review` 通过后询问用户，或用户明确要求时执行。

## 前置依赖

- `lark-cli`（`@larksuite/cli`），已执行 `lark-cli auth login`
- Node ≥ 20（lark-cli 自身依赖）
- 所有命令显式 `--as user`：文档落在**操作者本人**的飞书云空间，技能不读取、不保存任何 app secret

先检查登录态：

```bash
lark-cli auth status
```

`identities.user.available` 必须为 `true`；否则提示用户先 `lark-cli auth login`，不要继续。

## 用法

`wip-feishu [project]` ★

合并上传设计文档（总体设计 + 各模块设计）。

**合并规则**（与 `wip-doc` 共用 SKILL.md「合并输出规范」）：

- 主文档：`.wip/{project}/design.md`
- 模块文档：`.wip/{project}/modules/{module}/design.md`，按 `design.md` 模块划分表的依赖顺序排列，**不用字母序**
- 不上传：`plan.md`
- 结构：标题 → 生成时间/项目路径 → 第一部分总体设计 → 第二部分模块设计 → 附录
- 去掉源文件已有的第一行 `# ` 标题；附录字段固定为项目名称 / 模块数量 / 归档时间

**执行流程**：

1. 确定项目（规则见 `wip-doc.md`「项目选择规则」）
2. 从 `ledger.md` 读取 `- 描述:` 字段
3. 按合并规则生成一份 markdown 到临时文件，**文件名必须以 `.md` 结尾**（lark-cli 靠后缀推断格式）
4. 读取 `.wip/config.json` 的 `feishuFolderName`（缺省 `work-in-process`），确保云空间根目录与项目子目录存在：
   - 列目录：`lark-cli drive files list --as user --page-all`（子目录加 `--folder-token`）
   - 找文件夹：`type == "folder"` 且名称一致
   - 建文件夹：`lark-cli drive +create-folder --as user --name <名称> [--folder-token <父目录>]`
5. 同标题去重：在项目子目录里找 `type=docx` 且名称相同的文档，有则先删除：
   ```bash
   lark-cli drive +delete --as user --file-token <token> --type docx --yes
   ```
6. 导入（**必须在临时文件所在目录执行，`--file` 只接受相对路径**）：
   ```bash
   cd <临时目录>
   lark-cli drive +import --as user \
     --file <文件名>.md \
     --type docx \
     --name "<YYYYMMDD>_<描述> 设计文档" \
     --folder-token <项目子文件夹 token>
   ```
7. 解析返回：成功条件 `data.ready == true`，链接取 `data.url`（**不要自己拼 `bytedance.feishu.cn`**）。若返回 `data.ready=false` 与 `ticket`，续查：
   ```bash
   lark-cli drive +task_result --as user --scenario import --ticket <ticket>
   ```
8. 删除临时文件
9. **自动更新 ledger.md**：记录 `feishu_uploaded` 事件与文档链接

**文档标题**：`{YYYYMMDD}_{描述} 设计文档`，描述超过 20 字时截断。跨天再次上传视为新文档，历史保留；同一天重复上传会先删旧再导入（URL 会变化）。

**失败处理**：合并或导入失败时保留临时文件并报告路径；不要写入 `feishu_uploaded`。上传失败不影响已完成的本地归档与 review 结论。

## 其他飞书操作

`list / search / read / delete` 功能已移除。需要查看或管理云文档时，直接用飞书客户端，或 `lark-cli drive files list` / `lark-cli drive +delete`。
