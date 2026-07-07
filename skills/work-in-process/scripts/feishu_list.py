"""wip-feishu-list：列出已上传的 WIP 文档"""
import os
import sys
from datetime import datetime

# 兼容 Windows GBK 终端，确保 emoji 等特殊字符可输出
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from feishu_common import (
    SKILL_ROOT, ROOT_FOLDER,
    load_config,
    load_json,
    validate_config,
    get_tenant_token,
    list_all_docs,
)

TEMPLATE_PATH = os.path.join(SKILL_ROOT, "templates", "list.json")

DEFAULT_TEMPLATE = {
    "columns": [
        {"key": "index", "label": "#", "width": 4},
        {"key": "title", "label": "标题", "width": 45},
        {"key": "date",  "label": "日期", "width": 12},
        {"key": "link",  "label": "链接", "width": 0},
    ],
    "separator": "─",
    "delimiter": " | ",
    "dateFormat": "%Y-%m-%d",
}


def load_template():
    tpl = load_json(TEMPLATE_PATH)
    if tpl is None:
        print(f"[WARN] 模板文件不存在，使用默认样式: {TEMPLATE_PATH}")
    return tpl or DEFAULT_TEMPLATE


def render_table(docs, tpl, page, page_size):
    """按模板渲染表格"""
    total = len(docs)
    total_pages = (total + page_size - 1) // page_size
    if page > total_pages:
        page = total_pages
    start = (page - 1) * page_size
    end = min(start + page_size, total)
    page_docs = docs[start:end]

    columns = tpl.get("columns", DEFAULT_TEMPLATE["columns"])
    sep_char = tpl.get("separator", "─")
    delimiter = tpl.get("delimiter", " | ")
    date_fmt = tpl.get("dateFormat", "%Y-%m-%d")

    def fmt_col(col, value, index=None):
        w = col.get("width", 0)
        key = col["key"]
        if key == "index":
            s = str(index)
        elif key == "date":
            try:
                s = datetime.fromtimestamp(int(value)).strftime(date_fmt)
            except (ValueError, TypeError):
                s = str(value)[:10]
        elif key == "title":
            s = value[:w - 1] if w > 0 else value
        else:
            s = value or ""
        return s.ljust(w) if w > 0 else s

    # 表头
    header_parts = []
    for col in columns:
        w = col.get("width", 0)
        label = col.get("label", col["key"])
        header_parts.append(label.ljust(w) if w > 0 else label)
    header_line = delimiter.join(header_parts)

    # 分隔线（每列宽度对应 sep_char，用 delimiter 拼接）
    sep_parts = []
    for col in columns:
        w = col.get("width", 0)
        label_len = len(col.get("label", col["key"]))
        sep_parts.append(sep_char * (w if w > 0 else label_len))
    sep_line = delimiter.join(sep_parts)

    print(f"\n{sep_line}")
    print(header_line)
    print(sep_line)
    for i, doc in enumerate(page_docs, start + 1):
        row = delimiter.join(fmt_col(col, doc.get(col["key"], ""), i) for col in columns)
        print(row)
    print(sep_line)
    print(f"共 {total} 篇文档  第 {page}/{total_pages} 页（page_size={page_size}）")


def render_tsv(docs):
    """Tab-separated values 输出，可直接复制粘贴到 Excel"""
    columns = [
        {"key": "index", "label": "#"},
        {"key": "doc_id", "label": "Doc ID"},
        {"key": "title", "label": "标题"},
        {"key": "link", "label": "链接"},
    ]
    print("\t".join(col["label"] for col in columns))
    for i, doc in enumerate(docs, 1):
        row = [
            str(i),
            doc.get("doc_id", ""),
            doc.get("title", ""),
            doc.get("link", ""),
        ]
        print("\t".join(row))


if __name__ == "__main__":
    # 解析 --tsv 标志
    use_tsv = False
    args = sys.argv[1:]
    if "--tsv" in args:
        use_tsv = True
        args.remove("--tsv")

    cfg = load_config()
    validate_config(cfg)
    folder_name = cfg.get("feishuFolderName", "")

    page_size = 100
    page = 1
    if len(args) >= 1:
        try:
            page_size = int(args[0])
        except ValueError:
            print(f"[FAIL] page_size 必须是整数，收到: {args[0]}")
            sys.exit(1)
    if len(args) >= 2:
        try:
            page = max(1, int(args[1]))
        except ValueError:
            print(f"[FAIL] page 必须是整数，收到: {args[1]}")
            sys.exit(1)

    token = get_tenant_token(cfg["feishuAppId"], cfg["feishuAppSecret"])
    docs = list_all_docs(token, folder_name, page_size)

    if not docs:
        print("\n尚无已上传的 WIP 文档")
    elif use_tsv:
        render_tsv(docs)
    else:
        render_table(docs, load_template(), page, page_size)
