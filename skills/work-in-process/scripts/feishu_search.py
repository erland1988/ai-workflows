"""wip-feishu-search：按标题关键字搜索 WIP 文档"""
import sys

from feishu_common import (
    load_config,
    validate_config,
    get_tenant_token,
    list_all_docs,
)
from feishu_list import render_table, load_template, render_tsv


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print("用法: python feishu_search.py <关键字> [--tsv]")
        print("      按标题关键字搜索已上传的 WIP 文档")
        sys.exit(1)

    keyword = sys.argv[1]
    use_tsv = "--tsv" in sys.argv

    cfg = load_config()
    validate_config(cfg)
    folder_name = cfg.get("feishuFolderName", "")

    token = get_tenant_token(cfg["feishuAppId"], cfg["feishuAppSecret"])
    all_docs = list_all_docs(token, folder_name)
    docs = [d for d in all_docs if keyword.lower() in d.get("title", "").lower()]

    if not docs:
        print(f"\n未找到标题包含 '{keyword}' 的文档")
    elif use_tsv:
        render_tsv(docs)
    else:
        render_table(docs, load_template(), 1, len(docs))
