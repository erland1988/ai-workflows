"""wip-feishu-read：搜索并阅读 WIP 文档内容"""
import sys

import requests

from feishu_common import (
    BASE_URL,
    load_config,
    validate_config,
    get_tenant_token,
    list_all_docs,
    _check_resp,
)


def search_docs(docs, keyword):
    """按关键字/doc_id 搜索匹配的文档列表"""
    # doc_id 精确匹配优先
    for d in docs:
        if d["doc_id"] == keyword:
            return [d]
    # 标题模糊匹配
    return [d for d in docs if keyword.lower() in d.get("title", "").lower()]


def fetch_blocks(token, doc_id):
    """获取文档所有 block（含分页）"""
    blocks = []
    page_token = ""
    while True:
        url = f"{BASE_URL}/docx/v1/documents/{doc_id}/blocks"
        params = {"page_size": 500}
        if page_token:
            params["page_token"] = page_token
        resp = requests.get(url, headers={"Authorization": f"Bearer {token}"}, params=params)
        body = _check_resp(resp, "获取文档内容")
        blocks.extend(body["data"].get("items", []))
        if not body["data"].get("has_more"):
            break
        page_token = body["data"].get("page_token", "")
    return blocks


def render_blocks(blocks):
    """将 blocks 渲染为可读文本"""
    PREFIX_MAP = {
        2: "",      # text
        3: "# ",    # heading1
        4: "## ",   # heading2
        5: "### ",  # heading3
    }
    CONTENT_KEY_MAP = {
        2: "text",
        3: "heading1",
        4: "heading2",
        5: "heading3",
    }

    lines = []
    for block in blocks:
        bt = block.get("block_type", 2)
        prefix = PREFIX_MAP.get(bt, "")
        content_key = CONTENT_KEY_MAP.get(bt, "text")

        content = ""
        content_obj = block.get(content_key, {})
        for element in content_obj.get("elements", []):
            content += element.get("text_run", {}).get("content", "")

        lines.append(f"{prefix}{content}")

    return "\n".join(lines)


DIVIDER = "\n" + "=" * 72 + "\n"


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print("用法: python feishu_read.py <关键字|doc_id>")
        print("      搜索并阅读所有匹配的 WIP 文档内容")
        sys.exit(1)

    keyword = sys.argv[1]

    cfg = load_config()
    validate_config(cfg)
    folder_name = cfg.get("feishuFolderName", "")

    token = get_tenant_token(cfg["feishuAppId"], cfg["feishuAppSecret"])
    all_docs = list_all_docs(token, folder_name)
    matches = search_docs(all_docs, keyword)

    if not matches:
        print(f"\n未找到标题包含 '{keyword}' 的文档")
        sys.exit(1)

    print(f"\n匹配 {len(matches)} 篇文档：")
    for i, d in enumerate(matches, 1):
        print(f"  {i}. {d['title']}")
    print()

    read_count = 0
    skipped = []
    for i, doc in enumerate(matches):
        if len(matches) > 1:
            print(DIVIDER)
            print(f"[{i + 1}/{len(matches)}] {doc['title']}")
            print(f"  {doc['link']}")
            print(DIVIDER)
        else:
            print(f"  {doc['title']}")
            print(f"  {doc['link']}\n")

        try:
            blocks = fetch_blocks(token, doc["doc_id"])
            content = render_blocks(blocks)
            print(content)
            read_count += 1
        except SystemExit:
            skipped.append(doc["title"])
            print("[跳过] 该文档非 docx 类型，无法读取内容")

    if len(matches) > 1:
        print(DIVIDER)
        summary = f"共读取 {read_count} 篇文档"
        if skipped:
            summary += f"，跳过 {len(skipped)} 篇非 docx 文档"
        print(summary)
