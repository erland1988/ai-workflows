#!/bin/bash
# upload-comate-spec — 合并 comate 1.0 项目的需求与变更规格并上传飞书云文档
#
# 用法:
#   upload.sh [--dry-run] [--prd <关键字>] [--title <标题>] [--folder <子文件夹>] [--project <路径>]
#
# 退出码: 0 OK | 1 BLOCK | 2 USAGE | 3 ENV | 4 CORRUPT

set -euo pipefail

readonly OK=0 BLOCK=1 USAGE=2 ENV=3 CORRUPT=4
# 上传走飞书官方 CLI（@larksuite/cli）：认证、目录、导入、删除都交给它，
# 脚本不再持有任何应用凭据，每个用户用自己的登录态（--as user）。
readonly LARK_CLI="${LARK_CLI:-lark-cli}"
# 飞书云空间根文件夹名，固定值（不通过配置项覆盖）
readonly ROOT_FOLDER="comate-spec"
# comate 1.0 项目布局（仓库根相对路径）。脚本层是 comate/comate，
# 需求（PRD）与集成档案在上一层 comate/knowledge-base。
readonly COMATE_BASE="comate/comate"
readonly CHANGES_REL="${COMATE_BASE}/changes"
readonly ARCHIVE_REL="${COMATE_BASE}/archive"
readonly REQ_REL="comate/knowledge-base/requirements"

die() { local code="$1"; shift; printf 'ERROR: %s\n' "$*" >&2; exit "$code"; }
# 日志一律走 stderr：stdout 保留给函数返回值，避免被 $(...) 捕获污染
info() { printf '[INFO] %s\n' "$*" >&2; }
ok() { printf '[OK] %s\n' "$*" >&2; }
warn() { printf '[WARN] %s\n' "$*" >&2; }

# ---------------------------------------------------------------------
# 变更筛选（由 main 从命令行设置，供 collect_files 读取）
# ---------------------------------------------------------------------
# 背景：comate 的运行时单元是「change」而非「任务」——一次 /comate 只处理一个 change，
# 「一个任务含哪些 change」没有独立记录；但 `comate new <name> --source <PRD>` 会把
# PRD 路径钉进 change 的 state.json（sources 数组），引用同一份 PRD 的 change 即为一组任务。
# 故提供两条路：
#   --changes a,b,c  —— 手动指定本次任务含哪些 change（按名字子串匹配）
#   --task <关键字>  —— 自动：收录 sources 引用了匹配该关键字的 PRD 的 change
g_changes_filter=""
g_task_filter=""
# task 模式开关：1 = 启用。与 g_task_filter 分开是因为 --task 允许不带值（空关键字 = 自动探测），
# 此时关键字为空但模式仍须生效 —— 不能再用 [ -n "$g_task_filter" ] 判断模式。
g_task_mode=0

# change_matches_filter <名称...> — 任一名称命中 --changes 的逗号分隔子串即通过；
# 未设置 --changes 时恒为通过
change_matches_filter() {
  [ -z "$g_changes_filter" ] && return 0
  local pat="" name=""
  local IFS=','
  for pat in $g_changes_filter; do
    [ -z "$pat" ] && continue
    for name in "$@"; do
      case "$name" in *"$pat"*) return 0 ;; esac
    done
  done
  return 1
}

# state_field <变更目录> <字段> — 读 state.json 的顶层字符串字段。
# state.json 是 2 空格缩进的 pretty JSON（由 comate 脚本写入），单个字段用 grep 足够，
# 不引入 jq。读不到时输出空，由调用处回退。
state_field() {
  local dir="$1" key="$2"
  [ -f "$dir/state.json" ] || return 0
  grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$dir/state.json" 2>/dev/null \
    | head -1 \
    | sed 's/^[^:]*:[[:space:]]*"//; s/"$//' || true
}

# change_name <变更目录> — 变更名。state.json 的 name 是权威值；
# 归档目录名带 `YYYY-MM-DD-` 前缀，仅在 state.json 读不到时才回退并剥掉前缀。
change_name() {
  local dir="$1" n
  n=$(state_field "$dir" name)
  [ -n "$n" ] || {
    n=$(basename "$dir")
    n=$(printf '%s' "$n" | sed 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//')
  }
  printf '%s\n' "$n"
}

# change_source_paths <变更目录> — 输出该变更 sources 引用的仓库内路径。
# 1.0 用 `comate new <name> --source <文件>` 把源文件路径与 sha256 写进 state.json；
# sources 是 state.json 里唯一带 path 的字段，每个对象形如
# { "path": "comate/…", "sha256": "…" }。
change_source_paths() {
  local dir="$1"
  [ -n "$dir" ] && [ -d "$dir" ] || return 0
  [ -f "$dir/state.json" ] || return 0
  grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' "$dir/state.json" 2>/dev/null \
    | sed 's/^[^:]*:[[:space:]]*"//; s/"$//' \
    | grep -v '^$' || true
}

# change_prd_paths <变更目录> — 只保留 sources 里的 PRD 路径。
# 一个 change 还可能钉其他附件（背景资料、设计稿），它们不参与 task 分组。
change_prd_paths() {
  local dir="$1"
  change_source_paths "$dir" | grep "^${REQ_REL}/" | grep '/PRD-[^/]*\.md$' || true
}

# list_change_dirs <项目根> — 输出进行中与已归档的 change 目录，每行一个。
# 同名 change 以进行中的为准：归档的是它的历史副本，两边都收会重复。
list_change_dirs() {
  local root="$1" dir n
  for dir in "$root/$CHANGES_REL"/*/; do
    [ -d "$dir" ] || continue
    printf '%s\n' "${dir%/}"
  done
  for dir in "$root/$ARCHIVE_REL"/*/; do
    [ -d "$dir" ] || continue
    n=$(change_name "${dir%/}")
    [ -d "$root/$CHANGES_REL/$n" ] && continue
    printf '%s\n' "${dir%/}"
  done
}

# auto_task_candidates <项目根> <1=仅进行中> — 自动探测用的任务候选（PRD 所在功能目录）。
# 一个任务 = 引用同一份 PRD 的一组 change，故按 PRD 所在目录去重；
# 同一功能目录里有多份 PRD 也只算一个任务。
auto_task_candidates() {
  local root="$1" active_only="${2:-0}" dir
  {
    for dir in "$root/$CHANGES_REL"/*/; do
      [ -d "$dir" ] || continue
      change_prd_paths "${dir%/}"
    done
    if [ "$active_only" != "1" ]; then
      for dir in "$root/$ARCHIVE_REL"/*/; do
        [ -d "$dir" ] || continue
        change_prd_paths "${dir%/}"
      done
    fi
  } | sed 's|/[^/]*$||' | sort -u
}

# change_display_name <项目根> <变更目录> — 分组标题用的可读名。
# change 名是英文 kebab-case（如 add-email-login），直接当分组标题读者认不出，
# 故顺着 state.json 的 sources 找到该变更引用的 PRD，
# 取其 H1（`PRD-001-xxx: 中文产品名`）冒号后的部分。
# 需求来自对话（new 未带 --source）时没有 PRD，输出空，由调用处回退 change 名。
change_display_name() {
  local root="$1" dir="$2" p prd h1 name
  [ -d "$dir" ] || return 0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      *PRD-*.md) ;;
      *) continue ;;
    esac
    prd="$p"
    case "$prd" in /*) ;; *) prd="$root/$p" ;; esac
    [ -f "$prd" ] || continue
    h1=$(grep -m1 '^# ' "$prd" 2>/dev/null | sed 's/^#[[:space:]]*//' | tr -d '\r' || true)
    [ -n "$h1" ] || continue
    # 取冒号后的部分。用 shell 参数展开而非 sed 字符类 —— 全角冒号是多字节字符，
    # sed 的 [^:：] 在 MSYS 下按字节匹配会把汉字切碎。
    name="${h1#*: }"
    if [ "$name" = "$h1" ]; then
      name="${h1#*：}"
      [ "$name" = "$h1" ] && continue   # 半角/全角冒号都没有 → 换下一份 PRD
    fi
    # 去掉首尾空白并剔除 tab —— 显示名会作为 TSV 的第 5 列传给 collect_files/merge_docs，
    # 夹带 tab 会被 read 当成字段分隔符，导致显示名截断。只处理 ASCII 空白，不碰汉字。
    name=$(printf '%s' "$name" | tr -d '\t' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$name" ] || continue
    printf '%s\n' "$name"
    return 0
  done < <(change_source_paths "$dir")
}

# change_passes_filters <变更目录> <变更名> [<目录名>] — 是否通过 --changes / --task 筛选。
# 抽成单一函数，供 change 循环与 referenced_kb_paths 共用，避免两处判定逻辑漂移。
# 第 3 个参数传目录名：归档目录带 `YYYY-MM-DD-` 前缀，用户按目录名圈定也能命中。
change_passes_filters() {
  local dir="$1" name="$2" raw="${3:-$2}"
  change_matches_filter "$name" "$raw" || return 1
  if [ "$g_task_mode" = "1" ] && [ -n "$g_task_filter" ]; then
    change_prd_paths "$dir" | grep -q -- "$g_task_filter" || return 1
  fi
  return 0
}

# referenced_kb_paths <项目根> [<apply_filter>] — 输出被选中变更的 sources 引用的 PRD 路径（去重）。
# apply_filter=0 时忽略 --changes/--task 筛选，用于「自动探测本地有哪些 task」。
referenced_kb_paths() {
  local root="$1" apply="${2:-1}" dir name
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    name=$(change_name "$dir")
    if [ "$apply" = "1" ]; then
      change_passes_filters "$dir" "$name" "$(basename "$dir")" || continue
    fi
    change_prd_paths "$dir"
  done < <(list_change_dirs "$root") | sort -u
}

# =====================================================================
# lark-cli 公共封装
# =====================================================================

# lark_json <点分路径> — 从 stdin 读 JSON 并按路径取值，取不到输出空。
# 路径里的数字段可用于数组（如 data.files.0.name）。
# lark-cli 本身依赖 Node，所以这里用 node 解析完整 JSON，不引入 jq。
lark_json() {
  local path="$1"
  node -e '
    let s = "";
    process.stdin.on("data", (d) => { s += d; })
      .on("end", () => {
        try {
          const j = JSON.parse(s);
          const v = String(process.argv[1])
            .split(".")
            .reduce((o, k) => (o == null ? o : o[k]), j);
          if (v !== undefined && v !== null) process.stdout.write(String(v));
        } catch {}
      });
  ' "$path"
}

# lark_require_auth — 检查 CLI 存在且 user 身份已登录。
# 统一用 --as user：文档落在操作者本人的云空间，各自用自己的登录态，
# 不共用脚本里的应用凭据。
lark_require_auth() {
  command -v "$LARK_CLI" >/dev/null 2>&1 \
    || die "$ENV" "未安装 lark-cli（@larksuite/cli），或不在 PATH: $LARK_CLI
安装: npm i -g @larksuite/cli
登录: lark-cli auth login"

  local out available
  out=$("$LARK_CLI" auth status 2>/dev/null) \
    || die "$ENV" "执行 lark-cli auth status 失败"
  available=$(printf '%s' "$out" | lark_json identities.user.available)
  [ "$available" = "true" ] \
    || die "$ENV" "lark-cli 的 user 身份未登录（脚本统一用 --as user）
请先运行: lark-cli auth login"

  ok "lark-cli 已登录（user 身份）"
}

# =====================================================================
# 项目定位与文件收集
# =====================================================================

# 只认 comate 1.0 的配置：有 comate/comate/config.json 的才是项目根。
# 不回退 openspec/ 或 .git/ —— 迁移后的仓库可能保留旧目录，
# 以它们定位会把旧路径的残留文档当成当前项目的产物。
find_project_root() {
  local d
  d=$(pwd)
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    if [ -f "$d/$COMATE_BASE/config.json" ]; then
      printf '%s\n' "$d"
      return 0
    fi
    d=$(dirname "$d")
  done
  return 1
}

# 输出: "序号<TAB>分区<TAB>变更名<TAB>路径<TAB>显示名"，序号用于组内排序（需求在前，变更在后）
collect_files() {
  local root="$1" prd_filter="${2:-}"
  local req_dir f rel kbrefs="" kb_narrow=0

  # task 模式或 --changes 生效时，PRD 收窄到「被选中变更的 sources 引用」的那几份，
  # 避免 `--task A` 把 B 的 PRD 也带进来。
  # 注意：收窄与否只看「筛选是否开启」，不看 kbrefs 是否非空 ——
  # 选中的变更若都没带 --source（需求来自对话），kbrefs 为空，正确行为是「一份 PRD 都不收」。
  if [ "$g_task_mode" = "1" ] || [ -n "$g_changes_filter" ]; then
    kb_narrow=1
    kbrefs=$(referenced_kb_paths "$root")
  fi

  for req_dir in "$root/$REQ_REL"/*/; do
    [ -d "$req_dir" ] || continue
    if [ -n "$prd_filter" ]; then
      case "$req_dir" in *"$prd_filter"*) ;; *) continue ;; esac
    fi
    for f in "${req_dir%/}"/PRD-*.md; do
      [ -f "$f" ] || continue
      if [ "$kb_narrow" = "1" ]; then
        rel="${f#"$root"/}"; rel="${rel#./}"
        printf '%s\n' "$kbrefs" | grep -qx -- "$rel" || continue
      fi
      printf '1\treq\t-\t%s\t-\n' "$f"
    done
  done

  # 每个 change 收两部分：
  #   brief.md                  —— 背景、范围、非目标、关键决定、验收示例
  #   specs/<capability>/spec.md —— 该能力的完整目标规格（可多份）
  # 1.0 不产生独立的技术设计文档，技术取舍在 brief 的「决定」「约束与不变量」里。
  #
  # 只收这两类文件：state.json 是机器状态、tasks.md 是实施清单、verification.md 是
  # 验收过程记录、removed-specs/ 是已删除能力的备份 —— 都会过时，不进读者文档。
  local dir name raw disp s
  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    name=$(change_name "$dir")
    raw=$(basename "$dir")
    # --changes 按 change 名或目录名匹配；--task 按 sources 引用的 PRD 匹配
    if ! change_passes_filters "$dir" "$name" "$raw"; then
      continue
    fi

    # 分组标题显示名：PRD H1 的汉字名，解析不到时回退 change 名。
    # PRD 讲的是整个需求，同一 PRD 拆出的多个变更会重名 —— 由 merge_docs 追加 change 名区分。
    disp=$(change_display_name "$root" "$dir")
    [ -n "$disp" ] || disp="$name"

    [ -f "$dir/brief.md" ] && printf '3a\tbrief\t%s\t%s\t%s\n' "$name" "$dir/brief.md" "$disp"
    for s in "$dir"/specs/*/spec.md; do
      [ -f "$s" ] || continue
      printf '3b\tspec\t%s\t%s\t%s\n' "$name" "$s" "$disp"
    done
  done < <(list_change_dirs "$root")
}

# =====================================================================
# 文档合并
# =====================================================================

# 去掉 YAML frontmatter（仅当文件以 --- 开头）
strip_frontmatter() {
  awk '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---"    { in_fm = 0; next }
    in_fm                   { next }
    { print }
  ' "$1"
}

# 整体降级标题（# → 多 n 个 #），跳过代码块；同时过滤含本机绝对路径的行
# $1 = 降级层数（默认 1）
demote_headings() {
  local n="${1:-1}"
  awk -v n="$n" '
    /^```/ { in_code = !in_code; print; next }
    !in_code && /^#+ / { for (i = 0; i < n; i++) printf "#"; print; next }
    !in_code && /(^|[^A-Za-z])[A-Za-z]:[\\\/]/ { next }   # 丢弃含盘符绝对路径的行（前置断言避免误伤 https://）
    { print }
  '
}

# 去掉 PRD 标题的编号前缀，只留汉字名。用于第一部分的需求文档：
#   `# PRD-001-beike-ershoufang-timeline: 贝壳二手房房源动态并入统一采集链路`
#     → `# 贝壳二手房房源动态并入统一采集链路`
# 编号是内部标识（`PRD-NNN-<slug>`），对读者没有信息量；且「第一部分」下只有这一份需求文档，
# 不需要靠编号区分。分组的多个变更在第二部分各有自己的标题，互不影响。
# 只处理文件里第一个 `# PRD-...:` 行；找不到就原样输出（如标题用全角冒号时安全降级）。
strip_prd_number() {
  sed '0,/^# PRD-[^:]*:/s/^# PRD-[^:]*:[[:space:]]*/# /'
}

merge_docs() {
  local root="$1" out="$2" title="$3"
  shift 3
  local -a entries=("$@")
  local total="${#entries[@]}"

  # 不输出 markdown H1：飞书文档本身有标题块（= 导入任务的 file_name），
  # 再加一个 H1 会让标题在正文顶部重复出现一次。
  {
    printf '> 生成时间: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '> 项目: %s\n' "$(basename "$root")"
    printf '> 文档数量: %s\n\n' "$total"
    printf -- '---\n\n'
  } > "$out"

  # 分组标题去重：多个变更引用同一份 PRD 时，显示名（PRD 汉字名）会相同 —— 需追加变更目录名区分。
  # 只对「被两个以上变更共用」的显示名加后缀：单一变更引用该 PRD 时保持简洁。
  local dup_disps
  dup_disps=$(printf '%s\n' "${entries[@]}" \
    | awk -F'\t' '$2 != "req" && $5 != "" {print $3"\t"$5}' \
    | sort -u | awk -F'\t' '{print $2}' | sort | uniq -d)

  local section="" cur_change="" cur_order="" second_done=0
  local entry order sec label path disp base title
  for entry in "${entries[@]}"; do
    IFS=$'\t' read -r order sec label path disp <<< "$entry"
    base=$(basename "$path")

    if [ "$sec" != "$section" ]; then
      section="$sec"
      case "$sec" in
        req) printf '# 第一部分：需求\n\n' >> "$out" ;;
      esac
    fi

    # 变更类内容（brief + spec）统一归入第二部分，标题只打一次
    if [ "$sec" != "req" ] && [ "$second_done" -eq 0 ]; then
      printf -- '---\n\n# 第二部分：变更规格\n\n' >> "$out"
      second_done=1
    fi

    if [ "$sec" != "req" ]; then
      # 按变更分组，单变更也打分组标题 —— 标题用 PRD 汉字名（$disp）而非变更目录名：
      # 目录名是英文拼音（2026-09-20-beike-community-built-year），读者认不出。
      # 解析不到显示名时才回退目录名。
      if [ "$label" != "$cur_change" ]; then
        [ -n "$cur_change" ] && printf -- '---\n\n' >> "$out"
        cur_change="$label"
        title="${disp:-$label}"
        # 该显示名被多个变更共用时追加变更目录名 —— 否则会出现两张同名 H2，读者以为内容重复。
        # 去掉目录名的日期前缀（2026-09-21-beike-x → beike-x）：后缀更短，同类变更之间也更好对比。
        if printf '%s\n' "$dup_disps" | grep -qx -- "$title"; then
          title="$title（$(printf '%s' "$label" | sed 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//')）"
        fi
        printf '## %s\n\n' "$title" >> "$out"
        cur_order=""   # 换变更后，组内第一份文档需重新打身份标题
      fi
      # 身份标题：标明这份是 brief 还是 spec，每类各打一次。
      # 各文档的 H1 降 3 级挂其下，比「并列标题靠正文自称身份」更易读。
      if [ "$order" != "$cur_order" ]; then
        cur_order="$order"
        case "$order" in
          3a) printf '### 变更简报（comate brief）\n\n' >> "$out" ;;
          3b) printf '### 行为规格（comate spec）\n\n' >> "$out" ;;
        esac
      fi
    fi

    info "  收录: $base"
    if [ "$sec" = "req" ]; then
      strip_frontmatter "$path" | strip_prd_number | demote_headings 1 >> "$out"
    else
      # brief 与 spec 都降 3 级挂到身份标题（H3）之下：
      #   brief 的 H1 是「目标」「范围」等有效章节，不能省；
      #   spec 的 H1 是 capability 名（如 auth），正是读者需要的分组名。
      # 降 3 级后它们落在 H4，其下 `##` 落 H5、`###` 落 H6（飞书支持到 H9）。
      strip_frontmatter "$path" | demote_headings 3 >> "$out"
    fi
    printf '\n' >> "$out"
  done

  {
    printf -- '---\n\n# 附录\n\n'
    printf '| 属性 | 值 |\n|------|-----|\n'
    printf '| 项目 | %s |\n' "$(basename "$root")"
    printf '| 文档数量 | %s |\n' "$total"
    printf '| 生成时间 | %s |\n' "$(date '+%Y-%m-%d')"
  } >> "$out"
}

# =====================================================================
# lark-cli 命令封装
# =====================================================================

# lark_list_folder <folder_token 可空> — 输出每行 "type<TAB>name<TAB>token"。
# 根目录不传 --folder-token；--page-all 让 CLI 自己翻页。
lark_list_folder() {
  local folder="${1:-}" out
  local -a args=(drive files list --as user --page-all)
  [ -n "$folder" ] && args+=(--folder-token "$folder")
  out=$("$LARK_CLI" "${args[@]}" 2>/dev/null) || return 1
  printf '%s' "$out" | node -e '
    let s = "";
    process.stdin.on("data", (d) => { s += d; })
      .on("end", () => {
        try {
          const j = JSON.parse(s);
          if (!j.ok) process.exit(1);
          for (const f of (j.data && j.data.files) || []) {
            if (f.type && f.name && f.token) {
              process.stdout.write([f.type, f.name, f.token].join("\t") + "\n");
            }
          }
        } catch { process.exit(1); }
      });
  '
}

# lark_find <folder_token|""> <名称> <类型 folder|docx> — 输出 token，未找到输出空
lark_find() {
  local folder="$1" name="$2" want="$3" listing ty n t
  listing=$(lark_list_folder "$folder") || return 1
  while IFS=$'\t' read -r ty n t; do
    [ "$ty" = "$want" ] || continue
    [ "$n" = "$name" ] || continue
    printf '%s\n' "$t"
    return 0
  done <<< "$listing"
  return 0
}

# lark_create_folder <名称> <父 token 可空> — 输出新 folder token
lark_create_folder() {
  local name="$1" parent="${2:-}" out token
  local -a args=(drive +create-folder --as user --name "$name")
  [ -n "$parent" ] && args+=(--folder-token "$parent")
  out=$("$LARK_CLI" "${args[@]}" 2>/dev/null) \
    || { printf '[FAIL] 创建文件夹失败: %s\n' "$name" >&2; return 1; }
  token=$(printf '%s' "$out" | lark_json data.token)
  [ -n "$token" ] || token=$(printf '%s' "$out" | lark_json data.folder_token)
  [ -n "$token" ] || token=$(printf '%s' "$out" | lark_json token)
  if [ -z "$token" ]; then
    printf '[FAIL] 创建文件夹返回中未找到 token: %s\n响应: %s\n' "$name" "$out" >&2
    return 1
  fi
  printf '%s\n' "$token"
}

# lark_delete <token> <类型> — 删除（进回收站）。CLI 已内置有限轮询；
# 仍超时时用 task_id 续查，避免旧文档还在时就开始导入。
lark_delete() {
  local ft="$1" ty="$2" out okv task_id i deleted
  out=$("$LARK_CLI" drive +delete --as user --file-token "$ft" --type "$ty" --yes 2>/dev/null) \
    || { printf '[FAIL] 删除失败: %s\n' "$ft" >&2; return 1; }
  okv=$(printf '%s' "$out" | lark_json ok)
  if [ "$okv" != "true" ]; then
    printf '[FAIL] 删除失败: %s\n响应: %s\n' "$ft" "$out" >&2
    return 1
  fi
  # 通常在 data.deleted 直接返回结果；只有 timed_out 才需要拿 task_id 续查。
  deleted=$(printf '%s' "$out" | lark_json data.deleted)
  [ -n "$deleted" ] || deleted=$(printf '%s' "$out" | lark_json deleted)
  [ "$deleted" = "true" ] && return 0
  task_id=$(printf '%s' "$out" | lark_json task_id)
  [ -n "$task_id" ] || task_id=$(printf '%s' "$out" | lark_json data.task_id)
  [ -n "$task_id" ] || return 0
  for i in $(seq 1 10); do
    sleep 1
    out=$("$LARK_CLI" drive +task_result --as user --scenario task_check --task-id "$task_id" 2>/dev/null) || continue
    deleted=$(printf '%s' "$out" | lark_json deleted)
    [ -n "$deleted" ] || deleted=$(printf '%s' "$out" | lark_json data.deleted)
    [ "$deleted" = "true" ] && return 0
  done
  warn "删除任务未在 10s 内确认完成: $ft"
  return 0
}

# lark_import <文件绝对路径> <folder_token 可空> <标题> — 输出文档 URL
# 两个关键点：
#   1. --file 只接受当前工作目录下的相对路径，故 cd 到文件所在目录后传 basename；
#   2. CLI 靠后缀推断格式，mktemp 出来的合并文件没有 .md 后缀，
#      故在临时目录复制一份带 .md 后缀的副本再导入，用完即删。
# CLI 内置轮询；超时返回 ready=false + ticket，用 +task_result 续查。
lark_import() {
  local path="$1" folder="$2" title="$3" work dir base out i ready url token ticket
  work=$(mktemp "${TMPDIR:-/tmp}/comate-import.XXXXXX.md") \
    || { printf '[FAIL] 创建导入临时文件失败\n' >&2; return 1; }
  if ! cp "$path" "$work"; then
    rm -f "$work"
    printf '[FAIL] 复制合并产物到临时文件失败\n' >&2
    return 1
  fi
  dir=$(dirname "$work")
  base=$(basename "$work")
  local -a args=(drive +import --as user --file "$base" --type docx --name "$title")
  [ -n "$folder" ] && args+=(--folder-token "$folder")
  if ! out=$( (cd "$dir" && "$LARK_CLI" "${args[@]}") 2>/dev/null ); then
    rm -f "$work"
    printf '[FAIL] 导入命令执行失败\n' >&2
    return 1
  fi
  rm -f "$work"

  ready=$(printf '%s' "$out" | lark_json data.ready)
  [ -n "$ready" ] || ready=$(printf '%s' "$out" | lark_json ready)
  ticket=$(printf '%s' "$out" | lark_json ticket)
  [ -n "$ticket" ] || ticket=$(printf '%s' "$out" | lark_json data.ticket)

  # 未在 CLI 内置窗口内完成：按 ticket 续查（最多 60s）
  if [ "$ready" != "true" ] && [ -n "$ticket" ]; then
    for i in $(seq 1 30); do
      sleep 2
      out=$("$LARK_CLI" drive +task_result --as user --scenario import --ticket "$ticket" 2>/dev/null) || continue
      ready=$(printf '%s' "$out" | lark_json data.ready)
      [ -n "$ready" ] || ready=$(printf '%s' "$out" | lark_json ready)
      [ "$ready" = "true" ] && break
    done
  fi

  if [ "$ready" != "true" ]; then
    printf '[FAIL] 导入未完成或失败，ticket=%s\n响应: %s\n' "${ticket:-?}" "$out" >&2
    return 1
  fi

  # 返回字段按优先级兜底：不同版本 CLI 把结果放在 data.url / url / data.token
  url=$(printf '%s' "$out" | lark_json data.url)
  [ -n "$url" ] || url=$(printf '%s' "$out" | lark_json url)
  if [ -z "$url" ]; then
    token=$(printf '%s' "$out" | lark_json data.token)
    [ -n "$token" ] || token=$(printf '%s' "$out" | lark_json token)
    [ -n "$token" ] && url="https://feishu.cn/docx/$token"
  fi
  if [ -z "$url" ]; then
    printf '[FAIL] 导入完成但未找到文档链接\n响应: %s\n' "$out" >&2
    return 1
  fi
  printf '%s\n' "$url"
}

# lark_ensure_folder <根目录名> <子目录名可空> — 输出目标 folder_token
lark_ensure_folder() {
  local root_name="$1" sub_name="${2:-}" t sub
  t=$(lark_find "" "$root_name" folder) || die "$BLOCK" "查询根文件夹失败: $root_name"
  if [ -z "$t" ]; then
    t=$(lark_create_folder "$root_name" "") || die "$BLOCK" "创建根文件夹失败: $root_name"
    ok "已创建根文件夹: $root_name"
  else
    ok "找到根文件夹: $root_name"
  fi
  if [ -n "$sub_name" ]; then
    sub=$(lark_find "$t" "$sub_name" folder) || die "$BLOCK" "查询子文件夹失败: $sub_name"
    if [ -z "$sub" ]; then
      sub=$(lark_create_folder "$sub_name" "$t") || die "$BLOCK" "创建子文件夹失败: $sub_name"
      ok "已创建子文件夹: $sub_name"
    else
      ok "找到子文件夹: $sub_name"
    fi
    t="$sub"
  fi
  printf '%s\n' "$t"
}

# =====================================================================
# 主流程
# =====================================================================

usage() {
  cat >&2 <<'EOF'
用法: upload.sh [选项]

  --dry-run          只合并到本地文件，不上传（用于预览内容）
  --out <路径>       --dry-run 时的输出路径（默认把正文打到 stdout，不落盘）
  --prd <关键字>     只收录路径含该关键字的 PRD 目录
  --task [<关键字>]  按「一次开发任务」圈定范围（**默认行为**）：
                     带关键字 → 收 state.json sources 引用了匹配该关键字的 PRD 的 change；
                     不带值   → 自动探测本地 task，唯一则采用，多个/零个则报错并列出。
  --changes <名,...> 改按 change 名圈定（子串匹配，逗号分隔多个），绕过 task 模式 ——
                     适合需求来自对话、没有 PRD 的 change
  --title <标题>     覆盖飞书文档标题
  --folder <名称>    覆盖默认子文件夹名（默认取项目根目录名）
  --project <路径>   指定项目根（默认从当前目录向上查找）
  -h, --help         显示帮助

说明：**默认即 task 模式**，不提供「收全部」—— 那会把多个任务的文档混进同一份。
comate 的运行时单元是 change 而非任务；任务分组没有独立记录，
只能从各 change 的 state.json sources（new --source 钉住的 PRD）反查。
EOF
}

main() {
  local dry_run=0 out_file=""
  local prd_filter="" title="" sub_folder="" project_root=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run=1; shift ;;
      --out)     [ $# -ge 2 ] || die "$USAGE" "--out 需要参数"; out_file="$2"; shift 2 ;;
      --prd)     [ $# -ge 2 ] || die "$USAGE" "--prd 需要参数"; prd_filter="$2"; shift 2 ;;
      --changes) [ $# -ge 2 ] || die "$USAGE" "--changes 需要参数"; g_changes_filter="$2"; shift 2 ;;
      --task)
        # 值可选：后一个参数存在且不以 - 开头时作为关键字；否则视为「不带值」→ 自动探测本地 task
        g_task_mode=1
        if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then g_task_filter="$2"; shift 2; else shift; fi
        ;;
      --title)   [ $# -ge 2 ] || die "$USAGE" "--title 需要参数"; title="$2"; shift 2 ;;
      --folder)  [ $# -ge 2 ] || die "$USAGE" "--folder 需要参数"; sub_folder="$2"; shift 2 ;;
      --project) [ $# -ge 2 ] || die "$USAGE" "--project 需要参数"; project_root="$2"; shift 2 ;;
      -h|--help) usage; exit "$OK" ;;
      *) die "$USAGE" "未知参数: $1" ;;
    esac
  done

  if [ -z "$project_root" ]; then
    project_root=$(find_project_root) || die "$ENV" "未找到 comate 项目根（向上查找 comate/comate/config.json）；先在项目根运行 comate init，或用 --project 指定"
  fi
  [ -d "$project_root" ] || die "$ENV" "项目根不存在: $project_root"

  # --- 默认进入 task 模式 ---
  # 未显式指定 --changes 时默认按「一次开发任务」圈定（task 由 change 的 state.json sources 反查）。
  # 不再提供「默认收全部」——那会把多个任务的文档混进同一份。
  if [ "$g_task_mode" = "0" ] && [ -z "$g_changes_filter" ]; then
    g_task_mode=1
  fi

  # --task 不带值 → 自动探测本地 task：唯一则采用，多个或零个则报错并列出。
  # 优先只扫进行中的 change：归档的历史 change 常与当前任务同属一个 PRD，
  # 全扫会让默认模式长期报「多个 task」。进行中一个都没有时才退到归档。
  if [ "$g_task_mode" = "1" ] && [ -z "$g_task_filter" ]; then
    local tasks n active=0 dir
    for dir in "$project_root/$CHANGES_REL"/*/; do
      [ -d "$dir" ] && { active=1; break; }
    done
    tasks=$(auto_task_candidates "$project_root" "$active")
    n=$(printf '%s\n' "$tasks" | grep -c . || true)
    case "$n" in
      0) die "$BLOCK" "本项目没有可自动识别的 task：没有 change 的 state.json sources 引用 PRD。
任务由 comate new <name> --source <PRD> 钉住的 PRD 反查得到；
需求来自对话（未带 --source）或只想传单个 change 时，请改用 --changes <变更名子串>。" ;;
      1) g_task_filter=$(basename "$tasks")
         info "自动识别 task: $g_task_filter" ;;
      *) die "$BLOCK" "检测到 $n 个 task，请用 --task <关键字> 指定其一：
$(printf '%s\n' "$tasks" | sed "s|^${REQ_REL}/||; s|^|  - |")" ;;
    esac
  fi

  # --- 收集文件 ---
  # 排序键：先按第 3 列（变更名，同一变更的文档聚在一起），再按第 1 列（组内序 3a/3b），
  # 最后按第 4 列（路径，让多份 capability spec 稳定按目录名排列）。
  # 注意不能直接 sort 整行——那会把所有 3a 排到一起，打散同一变更的 brief/spec。
  local -a entries=()
  while IFS= read -r line; do
    [ -n "$line" ] && entries+=("$line")
  done < <(collect_files "$project_root" "$prd_filter" | sort -t$'\t' -k3,3 -k1,1 -k4,4)

  if [ "${#entries[@]}" -eq 0 ]; then
    if [ -n "$g_changes_filter" ] || [ -n "$g_task_filter" ]; then
      die "$BLOCK" "筛选后无任何文档。
筛选条件: --changes '$g_changes_filter'  --task '$g_task_filter'
提示:
  --changes 按 change 名子串匹配（逗号可分隔多个）；
  --task    按 change 的 state.json sources 引用的 PRD 匹配 —— 用 new 时未带 --source
            的 change 没有 sources，会被全部排除，此时请改用 --changes。"
    fi
    die "$BLOCK" "未收集到任何文档。
期望位置:
  $project_root/$REQ_REL/*/PRD-*.md
  $project_root/$CHANGES_REL/*/{brief.md,specs/*/spec.md}
  $project_root/$ARCHIVE_REL/*/{brief.md,specs/*/spec.md}
是否 comate 1.0 项目？找不到配置时先在项目根运行 comate init。"
  fi

  # --- 推导标题 ---
  if [ -z "$title" ]; then
    local name="" uniq_names uniq_count
    if [ "$g_task_mode" = "1" ] || [ -n "$g_changes_filter" ]; then
      # 有筛选：文档即「一次开发任务」—— 单变更用变更名，多变更用 task / --changes 关键字
      uniq_names=$(printf '%s\n' "${entries[@]}" | awk -F'\t' '$2 != "req" {print $3}' | sort -u)
      uniq_count=$(printf '%s\n' "$uniq_names" | grep -c . || true)
      if [ "$uniq_count" = "1" ]; then
        name=$(printf '%s\n' "$uniq_names" | head -1)
      elif [ "$g_task_mode" = "1" ]; then
        # g_task_filter 是 PRD 功能目录名（如 20260920-xxx 或 2026-09-20-xxx），
        # 去掉日期前缀更像可读的任务名
        name=$(printf '%s' "$g_task_filter" | sed 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//; s/^[0-9]\{8\}-//')
      else
        name="${g_changes_filter%%,*}"
      fi
    fi
    # 无筛选（或筛选后无变更）：用项目根目录名。
    # 不能用「第一个 PRD 目录名」—— 多 PRD / 多变更时那只是某一次任务的名字，会给整份文档错误命名。
    [ -n "$name" ] || name=$(basename "$project_root")
    title="${name} 需求与规格文档"
  fi

  info "项目根: $project_root"
  info "文档标题: $title"
  info "收录文档:"
  # 合并产物落点：
  #   上传    → 临时文件，由 EXIT trap 清理，绝不碰工作区
  #   dry-run → 默认先写临时文件、随后把正文打到 stdout（不落盘，避免污染项目工作区）；
  #             显式给了 --out 才写该文件并保留
  # merged 必须是全局变量：EXIT trap 在 main 返回后执行，local 变量此时已出作用域
  local to_stdout=0
  if [ "$dry_run" -eq 0 ]; then
    merged=$(mktemp "${TMPDIR:-/tmp}/upload-comate-spec.XXXXXX") || die "$ENV" "mktemp 失败"
    trap 'rm -f "${merged:-}"' EXIT
  elif [ -n "$out_file" ]; then
    merged="$out_file"
  else
    merged=$(mktemp "${TMPDIR:-/tmp}/upload-comate-spec-preview.XXXXXX") || die "$ENV" "mktemp 失败"
    to_stdout=1
    trap 'rm -f "${merged:-}"' EXIT
  fi

  merge_docs "$project_root" "$merged" "$title" "${entries[@]}"

  local chars
  chars=$(wc -c < "$merged" | tr -d ' ')
  ok "合并完成: $chars 字节"

  if [ "$dry_run" -eq 1 ]; then
    if [ "$to_stdout" -eq 1 ]; then
      # 正文走 stdout、日志走 stderr，两者不混 —— 故重定向 stdout 能得到纯净的合并结果
      info "预览正文输出到 stdout（存盘用 --out <路径>，或直接重定向）"
      cat "$merged"
    else
      ok "已输出预览文件: $merged"
      info "预览命令: cat \"$merged\""
    fi
    exit "$OK"
  fi

  # --- 上传 ---
  # 统一用 lark-cli 的 user 身份：文档落在操作者本人云空间，各自用自己的登录态。
  lark_require_auth

  # 二级目录用项目名隔离：不同项目若产生同标题文档，去重逻辑只在各自目录内生效，
  # 避免跨项目误删。--folder 可显式覆盖。
  local folder_token doc_name
  local sub_dir="${sub_folder:-$(basename "$project_root")}"
  info "目标文件夹: $ROOT_FOLDER/$sub_dir"
  folder_token=$(lark_ensure_folder "$ROOT_FOLDER" "$sub_dir") \
    || die "$BLOCK" "准备目标文件夹失败"

  # 飞书文档名加 YYYYMMDD_ 前缀用于跨天去重。但标题本身已含 YYYY-MM-DD（如变更名带日期）时
  # 再加就成了 `20260920_2026-09-20-…`，日期重复且难读 —— 此时不加前缀。
  doc_name="$title"
  case "$title" in
    *[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*) ;;
    *) doc_name="$(date '+%Y%m%d')_${title}" ;;
  esac

  # 同标题去重：先删旧文档再导入，避免重复（URL 会变化）。
  # 去重范围仅限当前用户云空间里的本项目目录。
  local old_doc url
  old_doc=$(lark_find "$folder_token" "$doc_name" docx) \
    || die "$BLOCK" "查询同名文档失败"
  if [ -n "$old_doc" ]; then
    info "发现同名文档，删除旧版本: $old_doc"
    lark_delete "$old_doc" docx || die "$BLOCK" "删除旧文档失败"
    ok "旧文档已删除（可在飞书回收站恢复）"
  fi

  info "上传并导入到飞书..."
  # --file 只接受 cwd 下相对路径，lark_import 内部会 cd 到临时文件所在目录。
  url=$(lark_import "$merged" "$folder_token" "$doc_name") \
    || die "$BLOCK" "文档导入失败"

  printf '\n'
  ok "上传完成"
  printf '文档链接: %s\n' "$url"
}

main "$@"
