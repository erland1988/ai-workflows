"""飞书脚本公共函数：配置、认证、API 调用"""

import json
import os
import re
import sys
from pathlib import Path

import requests

BASE_URL = "https://open.feishu.cn/open-apis"


def _find_skill_root():
    """从当前脚本位置向上查找 skill 根目录 (work-in-process/)。

    查找策略（按优先级）：
    1. 从 __file__ 向上一级（scripts -> work-in-process），检查 SKILL.md。
    2. 仍失败：从 cwd 向上查找 .claude/skills/work-in-process/。
    """
    # 策略 1: 从脚本位置向上一级（scripts/ 直接位于 work-in-process/ 下）
    start = Path(__file__).resolve().parent.parent
    if (start / "SKILL.md").exists():
        return str(start)

    # 策略 2: 从 cwd 向上查找
    cwd = Path.cwd()
    for parent in [cwd] + list(cwd.parents):
        target = parent / ".claude" / "skills" / "work-in-process"
        if target.is_dir():
            return str(target)

    # 最后回退
    return str(start)


SKILL_ROOT = _find_skill_root()
# config.json 在项目根目录的 .wip/ 下
# SKILL_ROOT: .../project/.claude/skills/work-in-process
# 往上 2 级到 .claude，再往上到项目根
_PROJECT_ROOT = Path(SKILL_ROOT).parent.parent.parent
CONFIG_PATH = os.path.join(str(_PROJECT_ROOT), ".wip", "config.json")

# 固定根目录名称，所有操作都在该目录下进行
ROOT_FOLDER = "work-in-process"


def load_json(path, default=None):
    """加载 JSON 文件，不存在或解析失败返回 default"""
    if not os.path.isfile(path):
        return default
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError):
        return default


def load_config():
    cfg = load_json(CONFIG_PATH)
    if cfg is None:
        print(f"[FAIL] 配置文件不存在: {CONFIG_PATH}")
        sys.exit(1)
    return cfg


def validate_config(cfg):
    """校验必要配置项"""
    missing = [k for k in ("feishuAppId", "feishuAppSecret") if not cfg.get(k)]
    if missing:
        print(f"[FAIL] config.json 缺少配置项: {', '.join(missing)}")
        sys.exit(1)


def _check_resp(resp, step_name):
    body = resp.json()
    code = body.get("code", -1)
    if code != 0:
        msg = body.get("msg", "unknown error")
        print(f"[FAIL] {step_name}: code={code}, msg={msg}")
        sys.exit(1)
    return body


def get_tenant_token(app_id, app_secret):
    url = f"{BASE_URL}/auth/v3/tenant_access_token/internal"
    resp = requests.post(url, json={"app_id": app_id, "app_secret": app_secret})
    body = _check_resp(resp, "获取 tenant_access_token")
    token = body["tenant_access_token"]
    print(f"[OK] 获取 token 成功: {token[:16]}...")
    return token


def find_folder(token, folder_name, parent_token=""):
    """查找文件夹，返回 folder_token；找不到返回 None

    Args:
        token: tenant_access_token
        folder_name: 要查找的文件夹名称
        parent_token: 父文件夹token，空字符串表示根目录
    """
    page_token = ""
    while True:
        url = f"{BASE_URL}/drive/v1/files"
        params = {"page_size": 50, "direction": "DESC"}
        if parent_token:
            params["folder_token"] = parent_token
        if page_token:
            params["page_token"] = page_token
        resp = requests.get(url, headers={"Authorization": f"Bearer {token}"}, params=params)
        body = _check_resp(resp, "查询文件夹列表")
        for f in body["data"].get("files", []):
            if f["type"] == "folder" and f["name"] == folder_name:
                return f["token"]
        if not body["data"].get("has_more"):
            break
        page_token = body["data"].get("page_token", "")
    return None


def find_or_create_root_folder(token):
    """查找或创建根目录 work-in-process，返回 folder_token"""
    root_token = find_folder(token, ROOT_FOLDER, "")
    if root_token:
        print(f"[OK] 找到根目录: {ROOT_FOLDER}")
        return root_token

    # 不存在则创建（在根目录创建，folder_token 为空）
    url = f"{BASE_URL}/drive/v1/files/create_folder"
    resp = requests.post(url,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        json={"name": ROOT_FOLDER, "folder_token": ""})
    body = _check_resp(resp, f"创建根目录 {ROOT_FOLDER}")
    root_token = body["data"]["token"]
    print(f"[OK] 已创建根目录: {ROOT_FOLDER}")
    return root_token


def find_or_create_subfolder(token, parent_token, folder_name):
    """在指定父文件夹下查找或创建子文件夹，返回 folder_token"""
    if not folder_name:
        return parent_token

    sub_token = find_folder(token, folder_name, parent_token)
    if sub_token:
        print(f"[OK] 找到子文件夹: {folder_name}")
        return sub_token

    # 不存在则创建
    url = f"{BASE_URL}/drive/v1/files/create_folder"
    resp = requests.post(url,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        json={"name": folder_name, "folder_token": parent_token})
    body = _check_resp(resp, f"创建子文件夹 {folder_name}")
    sub_token = body["data"]["token"]
    print(f"[OK] 已创建子文件夹: {folder_name}")
    return sub_token


def list_docs(token, folder_token, page_size=100):
    """列出文件夹中的 WIP 文档，返回统一 dict 列表"""
    page_size = min(max(1, page_size), 200)
    docs = []
    page_token = ""
    while True:
        url = f"{BASE_URL}/drive/v1/files"
        params = {"folder_token": folder_token, "page_size": page_size, "direction": "DESC"}
        if page_token:
            params["page_token"] = page_token
        resp = requests.get(url, headers={"Authorization": f"Bearer {token}"}, params=params)
        body = _check_resp(resp, "查询文档列表")
        for f in body["data"].get("files", []):
            if f["type"] == "docx":
                link = f.get("url", f"https://bytedance.feishu.cn/docx/{f['token']}")
                doc_id = f["token"]
                # 从 URL 补全 doc_id
                m = re.search(r"/docx/([A-Za-z0-9]+)", link)
                if m:
                    doc_id = m.group(1)
                docs.append({
                    "title": f["name"],
                    "token": f["token"],
                    "link": link,
                    "doc_id": doc_id,
                    "date": f.get("created_time", ""),
                })
        if not body["data"].get("has_more"):
            break
        page_token = body["data"].get("page_token", "")
    return docs


def list_all_docs(token, folder_name, page_size=100):
    """在 work-in-process 根目录下查找/创建子文件夹，并列出文档

    Args:
        token: tenant_access_token
        folder_name: 子文件夹名称（可选，空字符串表示直接在根目录下操作）
        page_size: 每页文档数
    """
    # 1. 先找到或创建根目录
    root_token = find_or_create_root_folder(token)

    # 2. 在根目录下查找或创建子文件夹
    if folder_name:
        target_token = find_or_create_subfolder(token, root_token, folder_name)
        print(f"[INFO] 目标文件夹: {ROOT_FOLDER}/{folder_name}")
    else:
        target_token = root_token
        print(f"[INFO] 目标文件夹: {ROOT_FOLDER}")

    # 3. 列出目标文件夹中的文档
    docs = list_docs(token, target_token, page_size)
    if not docs:
        print(f"[INFO] 目标文件夹中暂无文档")
    return docs


def delete_doc(token, file_token):
    """删除文档（移入回收站）"""
    url = f"{BASE_URL}/drive/v1/files/{file_token}?type=docx"
    resp = requests.delete(url, headers={"Authorization": f"Bearer {token}"})
    _check_resp(resp, f"删除文档 {file_token}")
    print(f"[OK] 已删除: {file_token}")
