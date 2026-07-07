import sys

from feishu_common import (
    load_config,
    validate_config,
    get_tenant_token,
    list_all_docs,
    delete_doc,
)


def pick_doc(docs, keyword):
    """根据关键字匹配文档，返回匹配的 doc 或 None"""
    if not docs:
        print("没有可删除的文档")
        return None

    # 尝试按 token 精确匹配
    for d in docs:
        if d["token"] == keyword:
            return d

    # 尝试按 doc_id（链接中的文档 ID）匹配
    for d in docs:
        if d["doc_id"] == keyword:
            return d

    # 尝试按完整 URL 匹配
    for d in docs:
        if d["url"] == keyword or keyword in d["url"]:
            return d

    # 模糊匹配标题
    matches = [d for d in docs if keyword.lower() in d["title"].lower()]
    if len(matches) == 1:
        return matches[0]
    elif len(matches) > 1:
        print(f"匹配到 {len(matches)} 篇文档，请用更精确的关键字或 doc_id：")
        for d in matches:
            print(f"  - {d['title']}")
            print(f"    {d['url']}")
        return None

    print(f"未找到匹配 '{keyword}' 的文档")
    return None


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print("用法: python feishu_delete.py <关键字|doc_id>")
        print("      python feishu_delete.py --all   (删除全部)")
        print("      先用 wip-feishu-list 查看文档列表")
        sys.exit(1)

    cfg = load_config()
    validate_config(cfg)
    app_id = cfg["feishuAppId"]
    app_secret = cfg["feishuAppSecret"]
    folder_name = cfg.get("feishuFolderName", "")

    token = get_tenant_token(app_id, app_secret)
    docs = list_all_docs(token, folder_name)

    if sys.argv[1] == "--all":
        if not docs:
            print("没有可删除的文档")
            sys.exit(0)
        print(f"将要删除 {len(docs)} 篇文档：")
        for i, d in enumerate(docs, 1):
            print(f"  {i}. {d['title']}")
        confirm = input("\n确认删除以上全部？(yes/no): ").strip().lower()
        if confirm != "yes":
            print("已取消")
            sys.exit(0)
        for d in docs:
            delete_doc(token, d["token"])
        print(f"\n已删除 {len(docs)} 篇文档")
    else:
        keyword = sys.argv[1]
        if not docs:
            print("没有可删除的文档")
            sys.exit(0)
        doc = pick_doc(docs, keyword)
        if doc is None:
            sys.exit(1)
        print(f"将要删除: {doc['title']}")
        confirm = input("确认删除？(yes/no): ").strip().lower()
        if confirm != "yes":
            print("已取消")
            sys.exit(0)
        delete_doc(token, doc["token"])
