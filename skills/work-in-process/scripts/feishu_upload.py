#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
WIP 设计文档合并上传脚本
将总体设计 + 各模块设计合并上传至飞书
"""

import argparse
import os
import re
import sys
from datetime import datetime
from pathlib import Path

import requests

from feishu_common import (
    _check_resp, get_tenant_token,
    find_or_create_root_folder, find_or_create_subfolder, ROOT_FOLDER,
    load_config, validate_config
)

BASE_URL = "https://open.feishu.cn/open-apis"


def get_project_root():
    """获取项目根目录"""
    current = Path.cwd()
    if '.claude' in str(current):
        while current.name != '.claude' and current != current.parent:
            current = current.parent
        if current.name == '.claude':
            return current.parent
    check = current
    while check != check.parent:
        if (check / '.wip').exists():
            return check
        check = check.parent
    return current


def find_wip_root():
    """查找 .wip 目录"""
    project_root = get_project_root()
    wip_path = project_root / '.wip'
    if wip_path.exists():
        return wip_path
    return None


def list_projects(wip_root):
    """列出所有项目"""
    projects = []
    for item in wip_root.iterdir():
        if item.is_dir() and (item / "design.md").exists():
            projects.append(item.name)
    return projects


def read_project_description(project_path):
    """从 ledger.md 读取项目中文描述"""
    ledger_path = project_path / "ledger.md"
    if not ledger_path.exists():
        return project_path.name
    try:
        with open(ledger_path, "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("- 描述: "):
                    return line.split("描述: ", 1)[1].strip()
    except Exception:
        pass
    return project_path.name


def summarize_description(desc, max_len=20):
    """描述过长时自动截断，保留 max_len 个字符 + ..."""
    if len(desc) <= max_len:
        return desc
    return desc[:max_len] + "..."


def read_file(file_path):
    """读取文件内容"""
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            return f.read()
    except Exception as e:
        print(f"[WARN] 无法读取 {file_path}: {e}")
        return ""


def read_module_order(project_path):
    """从 design.md 的「模块划分」表读取模块顺序，找不到则返回空列表（回退字母序）"""
    design_path = project_path / "design.md"
    order = []
    if not design_path.exists():
        return order
    try:
        with open(design_path, "r", encoding="utf-8") as f:
            content = f.read()
        in_section = False
        for line in content.splitlines():
            if line.startswith("## "):
                in_section = line.lstrip("# ").strip() == "模块划分"
                continue
            if in_section and line.startswith("|"):
                cells = [c.strip() for c in line.strip().strip("|").split("|")]
                # 跳过表头与分隔行（分隔行第一列全为 '-'）
                if cells and cells[0] and cells[0] != "模块" and not set(cells[0]).issubset("-"):
                    order.append(cells[0])
    except Exception:
        pass
    return order


def merge_design_docs(project_path):
    """合并设计文档"""
    stats = {"project": project_path.name, "modules": [], "total_chars": 0}
    lines = []

    # 标题 — 使用项目中文描述
    description = read_project_description(project_path)
    title_text = summarize_description(description)
    lines.append(f"# {title_text} 完整设计文档")
    lines.append("")
    lines.append(f"> 生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append(f"> 项目路径: .wip/{project_path.name}/")
    lines.append("")
    lines.append("---")
    lines.append("")

    # 第一部分：总体设计
    lines.append("# 第一部分：总体设计")
    lines.append("")

    design_md = project_path / "design.md"
    if design_md.exists():
        content = read_file(design_md)
        content = re.sub(r'^# .+\n', '', content)
        lines.append(content)
        stats["total_chars"] += len(content)

    lines.append("")
    lines.append("---")
    lines.append("")

    # 第二部分：模块设计
    lines.append("# 第二部分：模块设计")
    lines.append("")

    modules_path = project_path / "modules"
    if modules_path.exists():
        # 按 design.md 模块划分表的依赖顺序，而非字母序
        order = read_module_order(project_path)
        dirs = {d.name: d for d in modules_path.iterdir() if d.is_dir()}
        modules = []
        for m in order:
            if m in dirs:
                modules.append(dirs.pop(m))
        modules += sorted(dirs.values(), key=lambda d: d.name)  # order 外的模块兜底按字母序
        for module_dir in modules:
            module_design = module_dir / "design.md"
            if module_design.exists():
                module_name = module_dir.name
                stats["modules"].append(module_name)
                lines.append(f"## 模块: {module_name}")
                lines.append("")
                content = read_file(module_design)
                content = re.sub(r'^# .+\n', '', content)
                lines.append(content)
                lines.append("")
                lines.append("---")
                lines.append("")
                stats["total_chars"] += len(content)

    # 附录
    lines.append("# 附录：项目元数据")
    lines.append("")
    lines.append("| 属性 | 值 |")
    lines.append("|------|-----|")
    lines.append(f"| 项目名称 | {project_path.name} |")
    lines.append(f"| 模块数量 | {len(stats['modules'])} |")
    lines.append(f"| 归档时间 | {datetime.now().strftime('%Y-%m-%d')} |")
    lines.append("")

    return "\n".join(lines), stats


def create_doc(token, title, folder_token=None):
    """创建飞书文档"""
    url = f"{BASE_URL}/docx/v1/documents"
    body = {"title": title}
    if folder_token:
        body["folder_token"] = folder_token
    resp = requests.post(url,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        json=body)
    body = _check_resp(resp, "创建文档")
    doc_id = body["data"]["document"]["document_id"]
    print(f"[OK] 创建文档: {doc_id}")
    return doc_id


def parse_inline(text):
    """将行内 markdown（**加粗** / `代码` / *斜体*）转为飞书 text_run 元素列表"""
    elements = []
    i = 0
    buffer = ""
    n = len(text)
    while i < n:
        if text.startswith("**", i):
            if buffer:
                elements.append({"text_run": {"content": buffer}})
                buffer = ""
            end = text.find("**", i + 2)
            if end == -1:
                buffer += text[i:]
                break
            elements.append({"text_run": {"content": text[i + 2:end], "style": {"bold": True}}})
            i = end + 2
        elif text.startswith("*", i):
            if buffer:
                elements.append({"text_run": {"content": buffer}})
                buffer = ""
            end = text.find("*", i + 1)
            if end == -1:
                buffer += text[i:]
                break
            elements.append({"text_run": {"content": text[i + 1:end], "style": {"italic": True}}})
            i = end + 1
        elif text[i] == "`":
            if buffer:
                elements.append({"text_run": {"content": buffer}})
                buffer = ""
            end = text.find("`", i + 1)
            if end == -1:
                buffer += text[i:]
                break
            elements.append({"text_run": {"content": text[i + 1:end], "style": {"inline_code": True}}})
            i = end + 1
        else:
            buffer += text[i]
            i += 1
    if buffer:
        elements.append({"text_run": {"content": buffer}})
    return elements


def add_doc_content(token, doc_id, content):
    """将内容写入飞书文档

    支持：标题(#/##/###)、文本、无序列表(-)、有序列表(1.)、引用(>)、代码块(```)、行内样式。
    表格暂以纯文本行呈现（二期做飞书 table block）。
    """
    lines = content.split('\n')
    children = []
    i = 0
    n = len(lines)

    while i < n:
        line = lines[i].rstrip()
        if line.startswith("```"):
            # 代码块：收集到下一个 ``` 为止
            i += 1
            code_lines = []
            while i < n and not lines[i].strip().startswith("```"):
                code_lines.append(lines[i].rstrip())
                i += 1
            i += 1  # 跳过结尾 ```
            children.append({
                "block_type": 14,
                "code": {
                    "language": 1,  # 1 = PlainText
                    "elements": [{"text_run": {"content": "\n".join(code_lines)}}]
                }
            })
        elif not line:
            children.append({"block_type": 2, "text": {"elements": [{"text_run": {"content": ""}}]}})
        elif line.startswith("### "):
            children.append({"block_type": 5, "heading3": {"elements": parse_inline(line[4:])}})
        elif line.startswith("## "):
            children.append({"block_type": 4, "heading2": {"elements": parse_inline(line[3:])}})
        elif line.startswith("# "):
            children.append({"block_type": 3, "heading1": {"elements": parse_inline(line[2:])}})
        elif line.startswith("> "):
            children.append({"block_type": 15, "quote": {"elements": parse_inline(line[2:])}})
        elif line.startswith("- ") or line.startswith("* "):
            children.append({"block_type": 12, "bullet": {"elements": parse_inline(line[2:])}})
        elif re.match(r'^\d+\.\s', line):
            children.append({
                "block_type": 13,
                "ordered": {"elements": parse_inline(re.sub(r'^\d+\.\s', '', line)), "style": 1}  # 1 = number
            })
        else:
            children.append({"block_type": 2, "text": {"elements": parse_inline(line)}})
        i += 1

    BATCH = 50
    total_batches = (len(children) - 1) // BATCH + 1
    for i in range(0, len(children), BATCH):
        batch = children[i:i + BATCH]
        url = f"{BASE_URL}/docx/v1/documents/{doc_id}/blocks/{doc_id}/children"
        resp = requests.post(url,
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            json={"children": batch})
        _check_resp(resp, f"写入内容 batch {i // BATCH + 1}/{total_batches}")

    print(f"[OK] 写入 {len(children)} 行内容")


def main():
    parser = argparse.ArgumentParser(description="合并上传 WIP 设计文档到飞书")
    parser.add_argument("--project", help="指定项目名；未指定时自动选择或交互选择")
    args = parser.parse_args()

    wip_root = find_wip_root()
    if not wip_root:
        print("[FAIL] 未找到 .wip 目录")
        sys.exit(1)

    projects = list_projects(wip_root)
    if not projects:
        print("[FAIL] 没有找到任何项目")
        sys.exit(1)

    if args.project:
        if args.project not in projects:
            print(f"[FAIL] 项目不存在: {args.project}")
            sys.exit(1)
        project_name = args.project
        print(f"[INFO] 指定项目: {project_name}")
    elif len(projects) == 1:
        project_name = projects[0]
        print(f"[INFO] 自动选择项目: {project_name}")
    else:
        print("发现以下项目:")
        for i, p in enumerate(projects, 1):
            print(f"  {i}. {p}")
        try:
            choice = input("\n请选择: ").strip()
            project_name = projects[int(choice) - 1]
        except (EOFError, ValueError, IndexError):
            print("[FAIL] 非交互环境无法选择，请用 --project 指定项目名")
            sys.exit(1)

    project_path = wip_root / project_name

    print(f"\n[INFO] 正在合并设计文档...")
    merged_content, stats = merge_design_docs(project_path)

    print(f"\n[INFO] 合并统计:")
    print(f"  - 模块数量: {len(stats['modules'])}")
    for m in stats["modules"]:
        print(f"    - {m}")
    print(f"  - 总字数: {stats['total_chars']}")

    cfg = load_config()
    validate_config(cfg)
    app_id = cfg.get("feishuAppId", "")
    app_secret = cfg.get("feishuAppSecret", "")
    folder_name = cfg.get("feishuFolderName", "")

    doc_title = f"{datetime.now().strftime('%Y%m%d')}_{summarize_description(read_project_description(project_path))} 设计文档"
    print(f"\n[INFO] 文档标题: {doc_title}")

    token = get_tenant_token(app_id, app_secret)
    root_token = find_or_create_root_folder(token)
    folder_token = find_or_create_subfolder(token, root_token, folder_name) if folder_name else root_token

    doc_id = create_doc(token, doc_title, folder_token)
    add_doc_content(token, doc_id, merged_content)

    url = f"https://bytedance.feishu.cn/docx/{doc_id}"
    print(f"\n[DONE] 上传完成: {url}")


if __name__ == "__main__":
    main()
