#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
WIP 设计文档合并上传脚本
将总体设计 + 各模块设计合并上传至飞书
"""

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
        modules = sorted([d for d in modules_path.iterdir() if d.is_dir()])
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
    lines.append(f"| 设计完成时间 | {datetime.now().strftime('%Y-%m-%d')} |")
    lines.append(f"| 总字数 | {stats['total_chars']} |")
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


def add_doc_content(token, doc_id, content):
    """将内容写入飞书文档"""
    lines = content.split('\n')
    children = []

    for line in lines:
        line = line.rstrip()
        if not line:
            children.append({"block_type": 2, "text": {"elements": [{"text_run": {"content": ""}}]}})
        elif line.startswith("### "):
            children.append({"block_type": 5, "heading3": {"elements": [{"text_run": {"content": line[4:]}}]}})
        elif line.startswith("## "):
            children.append({"block_type": 4, "heading2": {"elements": [{"text_run": {"content": line[3:]}}]}})
        elif line.startswith("# "):
            children.append({"block_type": 3, "heading1": {"elements": [{"text_run": {"content": line[2:]}}]}})
        else:
            children.append({"block_type": 2, "text": {"elements": [{"text_run": {"content": line}}]}})

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
    wip_root = find_wip_root()
    if not wip_root:
        print("[FAIL] 未找到 .wip 目录")
        sys.exit(1)

    projects = list_projects(wip_root)
    if not projects:
        print("[FAIL] 没有找到任何项目")
        sys.exit(1)

    if len(projects) == 1:
        project_name = projects[0]
        print(f"[INFO] 自动选择项目: {project_name}")
    else:
        print("发现以下项目:")
        for i, p in enumerate(projects, 1):
            print(f"  {i}. {p}")
        choice = input("\n请选择: ").strip()
        project_name = projects[int(choice) - 1]

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
