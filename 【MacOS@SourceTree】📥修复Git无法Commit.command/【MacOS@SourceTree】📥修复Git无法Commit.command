#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】📥修复Git无法Commit.command
# - 核心用途：检查子模块后，统一暂存当前 Git 仓库中的新增、修改、删除和重命名，规避 Sourcetree 分步 add/rm 导致的 Commit 阻塞。
# - 关键场景：处理文件与同名目录转换、旧 gitlink 删除前 .gitmodules 未暂存、子模块目录改名或复制后的 Git worktree 路径错位。
# - 影响范围：修改 Git 索引；可初始化缺失子模块，但不清理已有子模块的真实修改。

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export LANG="${LANG:-zh_CN.UTF-8}"
export LC_CTYPE="${LC_CTYPE:-UTF-8}"

# 解析脚本真实路径，兼容 Sourcetree 只传入脚本名的运行环境。
resolve_script_path() {
  local script_source="${BASH_SOURCE[0]:-${(%):-%x}}"
  local script_name="$(basename -- "$0")"
  local candidate=""

  for candidate in \
    "$script_source" \
    "${PWD}/${script_source}" \
    "${HOME}/SourceTree.command/${script_name}/${script_name}" \
    "${HOME}/Documents/Github/JobsGenesis/SourceTree.command/${script_name}/${script_name}"; do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    (cd "$(dirname "$candidate")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename "$candidate")")
    return 0
  done

  printf '%s/%s\n' "$PWD" "$script_name"
}

SCRIPT_PATH="$(resolve_script_path)"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd -P)"
SCRIPT_BASENAME="$(basename "$SCRIPT_PATH" | sed 's/\.[^.]*$//')"
LOG_DIR="${TMPDIR:-/tmp}"
LOG_DIR="${LOG_DIR%/}"
LOG_FILE="${LOG_DIR}/${SCRIPT_BASENAME}.log"
IS_SOURCETREE_RUNTIME=0
PLAIN_OUTPUT=0
REPO_ROOT=""
typeset -ga GITLINK_PATHS
GITLINK_PATHS=()

# 识别 Sourcetree 自定义动作的非交互运行环境。
is_sourcetree_runtime() {
  env | grep -Eqi '^SOURCETREE|^SOURCE_TREE' && return 0
  [[ "$0" != /* && "$SCRIPT_PATH" == "${HOME}/SourceTree.command/"* ]] && return 0

  local pid="$PPID"
  local command_name=""
  local guard=0
  while [[ -n "$pid" && "$pid" != "0" && "$guard" -lt 8 ]]; do
    command_name="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
    [[ "$command_name" == *SourceTree* || "$command_name" == *Sourcetree* ]] && return 0
    pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    guard=$((guard + 1))
  done

  return 1
}

# 移除 ANSI 颜色码，避免 Sourcetree 输出窗口显示乱码。
strip_ansi_text() {
  perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}

# 同步输出终端日志和本地日志文件。
log() {
  if [[ "$PLAIN_OUTPUT" == "1" ]]; then
    printf '%b\n' "$1" | strip_ansi_text | tee -a "$LOG_FILE"
  else
    printf '%b\n' "$1" | tee -a "$LOG_FILE"
  fi
}

# 输出信息级别日志。
info_echo()    { log "\033[1;34mℹ $1\033[0m"; }
# 输出成功级别日志。
success_echo() { log "\033[1;32m✔ $1\033[0m"; }
# 输出警告级别日志。
warn_echo()    { log "\033[1;33m⚠ $1\033[0m"; }
# 输出说明级别日志。
note_echo()    { log "\033[1;35m➤ $1\033[0m"; }
# 输出错误级别日志。
error_echo()   { log "\033[1;31m✖ $1\033[0m"; }
# 输出次要信息日志。
gray_echo()    { log "\033[0;90m$1\033[0m"; }
# 输出高亮分隔信息。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }

# 初始化 zsh 选项、日志与 Sourcetree 输出策略。
initialize_script_runtime() {
  emulate -R zsh
  set -e
  set -o pipefail
  setopt NO_NOMATCH
  : > "$LOG_FILE"

  if is_sourcetree_runtime; then
    IS_SOURCETREE_RUNTIME=1
  fi
  if [[ "$IS_SOURCETREE_RUNTIME" == "1" || ! -t 1 || -z "${TERM:-}" || "${TERM:-}" == "dumb" || -n "${NO_COLOR:-}" ]]; then
    PLAIN_OUTPUT=1
  fi
}

# 展示内置自述，终端模式等待确认，Sourcetree 模式直接继续。
show_script_intro_and_wait() {
  if [[ "$IS_SOURCETREE_RUNTIME" != "1" && -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 =============================="
  note_echo "脚本名称：${SCRIPT_BASENAME}.command"
  note_echo "核心行为：优先暂存 .gitmodules，再检查 Git 子模块，最后执行 git add -A -- . 完整刷新索引。"
  note_echo "适用场景：普通变更、文件与同名目录转换、缺失子模块工作树、旧 gitlink 删除，以及 .git/core.worktree 路径错位。"
  note_echo "副本修复：已登记到 .gitmodules 的同源子模块副本，会尝试创建独立 gitdir 后继续。"
  note_echo "子模块策略：缺失时尝试初始化；已存在但内部有修改时立即停止，不代替用户清理。"
  note_echo "典型报错：please stage your changes to .gitmodules or stash them to proceed。"
  note_echo "安全边界：不提交、不推送、不主动删除文件、不强制添加已忽略文件。"
  note_echo "文档关系：同目录 README.md 只作为静态说明，脚本运行时不依赖它。"
  gray_echo "日志文件：${LOG_FILE}"
  highlight_echo "============================================================================="

  if [[ "$IS_SOURCETREE_RUNTIME" == "1" ]]; then
    gray_echo "已识别 Sourcetree 自定义动作，跳过回车等待。"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    error_echo "当前不是 Sourcetree，且没有可交互输入。"
    return 1
  fi

  echo ""
  read -r "?👉 已阅读说明，按回车继续执行；按 Ctrl+C 取消：" _
}

# 解析 .git 文件指向的真实 gitdir 路径。
resolve_gitdir_from_git_file() {
  local worktree_root="$1"
  local git_file="${worktree_root}/.git"
  local gitdir_value=""
  local gitdir_path=""

  [[ -f "$git_file" ]] || return 1
  gitdir_value="$(sed -n 's/^gitdir: //p' "$git_file" | head -n 1)"
  [[ -n "$gitdir_value" ]] || return 1
  gitdir_path="${worktree_root}/${gitdir_value}"
  print -r -- "${gitdir_path:A}"
}
# 读取 gitdir/config 里登记的 core.worktree 绝对路径。
read_configured_worktree_path() {
  local gitdir_path="$1"
  local configured_worktree=""
  local configured_path=""

  [[ -f "${gitdir_path}/config" ]] || return 1
  configured_worktree="$(git config --file "${gitdir_path}/config" --get core.worktree 2>/dev/null || true)"
  [[ -n "$configured_worktree" ]] || return 1
  if [[ "$configured_worktree" == /* ]]; then
    configured_path="$configured_worktree"
  else
    configured_path="${gitdir_path}/${configured_worktree}"
  fi
  print -r -- "${configured_path:A}"
}
# 将误借用其它 gitdir 的目录转换为独立 Git 工作树。
convert_mislinked_git_file_to_standalone_worktree() {
  local target_abs="$1"
  local gitdir_path="$2"
  local backup_path="${target_abs}/.git.mislinked-backup-$(date +%Y%m%d%H%M%S)"
  local failed_path="${target_abs}/.git.failed-standalone-$(date +%Y%m%d%H%M%S)"

  [[ -f "${target_abs}/.git" && -d "$gitdir_path" ]] || return 1
  warn_echo "正在把错位目录转换为独立 Git 工作树：${target_abs}"
  mv "${target_abs}/.git" "$backup_path" || return 1
  mkdir -p "${target_abs}/.git"
  if ! rsync -a --exclude='fsmonitor--daemon*' "${gitdir_path}/" "${target_abs}/.git/" >> "$LOG_FILE" 2>&1; then
    mv "${target_abs}/.git" "$failed_path" 2>/dev/null || true
    mv "$backup_path" "${target_abs}/.git" 2>/dev/null || true
    error_echo "复制 Git 元数据失败，已恢复原 .git 指针文件：${target_abs}"
    return 1
  fi

  git config --file "${target_abs}/.git/config" --unset core.worktree 2>/dev/null || true
  git config --file "${target_abs}/.git/config" core.bare false
  if [[ "$(git -C "$target_abs" rev-parse --is-inside-work-tree 2>/dev/null || true)" != "true" ]]; then
    mv "${target_abs}/.git" "$failed_path" 2>/dev/null || true
    mv "$backup_path" "${target_abs}/.git" 2>/dev/null || true
    error_echo "独立 Git 工作树验证失败，已恢复原 .git 指针文件：${target_abs}"
    return 1
  fi

  mv "$backup_path" "${target_abs}/.git/$(basename "$backup_path")"
  success_echo "已转换为独立 Git 工作树：${target_abs}"
}
# 判断传入路径是否因目录改名导致 .git 与 core.worktree 指向不一致。
repair_invoked_gitdir_worktree_if_safe() {
  local target="$1"
  local target_abs="${target:A}"
  local gitdir_path=""
  local configured_path=""
  local inside_worktree=""

  [[ -d "$target_abs" && -f "${target_abs}/.git" ]] || return 0
  inside_worktree="$(git -C "$target_abs" rev-parse --is-inside-work-tree 2>/dev/null || true)"
  [[ "$inside_worktree" != "true" ]] || return 0
  gitdir_path="$(resolve_gitdir_from_git_file "$target_abs" 2>/dev/null || true)"
  [[ -n "$gitdir_path" ]] || return 0
  configured_path="$(read_configured_worktree_path "$gitdir_path" 2>/dev/null || true)"
  [[ -n "$configured_path" && "$configured_path" != "$target_abs" ]] || return 0

  if [[ -e "$configured_path" ]]; then
    warn_echo "检测到 Git 工作树路径错位：${target_abs}"
    warn_echo ".git 指向：${gitdir_path}"
    warn_echo "core.worktree 指向：${configured_path}"
    warn_echo "真实工作树仍存在，当前目录将改为独立 Git 工作树，避免 Sourcetree 继续显示 HEAD。"
    convert_mislinked_git_file_to_standalone_worktree "$target_abs" "$gitdir_path"
    return
  fi

  warn_echo "检测到目录改名后的 core.worktree 旧路径失效，正在修正：${target_abs}"
  git config --file "${gitdir_path}/config" core.worktree "$target_abs" || return 1
  success_echo "已修正 core.worktree：${target_abs}"
}
# 从 Sourcetree 参数或当前目录解析 Git 仓库根目录。
resolve_repo_root() {
  local target="${1:-$PWD}"

  if [[ -f "$target" ]]; then
    target="$(dirname "$target")"
  fi
  if [[ ! -d "$target" ]]; then
    error_echo "目标路径不存在：${target}"
    return 1
  fi
  repair_invoked_gitdir_worktree_if_safe "$target"
  if ! REPO_ROOT="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)"; then
    error_echo "目标路径不在 Git 工作树内：${target}"
    return 1
  fi

  success_echo "已识别仓库：${REPO_ROOT}"
}

# 收集父仓索引中真实登记的 gitlink 路径。
collect_gitlink_paths() {
  GITLINK_PATHS=()
  local entry=""
  local mode=""
  local submodule_path=""

  while IFS= read -r -d '' entry; do
    mode="${entry%% *}"
    [[ "$mode" == "160000" ]] || continue
    submodule_path="${entry#*$'\t'}"
    [[ -n "$submodule_path" ]] && GITLINK_PATHS+=("$submodule_path")
  done < <(git -C "$REPO_ROOT" ls-files -s -z)
}

# 判断 gitlink 是否在 .gitmodules 中有可用的路径和 URL 配置。
submodule_has_valid_config() {
  local submodule_path="$1"
  local key=""
  local configured_path=""
  local section=""
  local url=""

  [[ -f "${REPO_ROOT}/.gitmodules" ]] || return 1
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    configured_path="$(git -C "$REPO_ROOT" config --file .gitmodules --get "$key" 2>/dev/null || true)"
    [[ "$configured_path" == "$submodule_path" ]] || continue
    section="${key#submodule.}"
    section="${section%.path}"
    url="$(git -C "$REPO_ROOT" config --file .gitmodules --get "submodule.${section}.url" 2>/dev/null || true)"
    [[ -n "$url" ]]
    return
  done < <(git -C "$REPO_ROOT" config --file .gitmodules --name-only --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)

  return 1
}
# 读取 .gitmodules 中指定子模块路径对应的 URL。
submodule_config_url() {
  local submodule_path="$1"
  local key=""
  local configured_path=""
  local section=""
  local url=""

  [[ -f "${REPO_ROOT}/.gitmodules" ]] || return 1
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    configured_path="$(git -C "$REPO_ROOT" config --file .gitmodules --get "$key" 2>/dev/null || true)"
    [[ "$configured_path" == "$submodule_path" ]] || continue
    section="${key#submodule.}"
    section="${section%.path}"
    url="$(git -C "$REPO_ROOT" config --file .gitmodules --get "submodule.${section}.url" 2>/dev/null || true)"
    [[ -n "$url" ]] || return 1
    print -r -- "$url"
    return 0
  done < <(git -C "$REPO_ROOT" config --file .gitmodules --name-only --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)

  return 1
}
# 计算父仓 .git/modules 下某个子模块路径应该使用的 gitdir。
submodule_gitdir_path() {
  local submodule_path="$1"
  local modules_root=""

  modules_root="$(git -C "$REPO_ROOT" rev-parse --git-path modules 2>/dev/null || true)"
  [[ -n "$modules_root" ]] || return 1
  [[ "$modules_root" == /* ]] || modules_root="${REPO_ROOT}/${modules_root}"
  print -r -- "${modules_root:A}/${submodule_path}"
}
# 判断相对路径是否是父仓索引登记的 gitlink。
is_index_gitlink_path() {
  local relative_path="$1"
  local submodule_path=""

  for submodule_path in "${GITLINK_PATHS[@]}"; do
    [[ "$submodule_path" == "$relative_path" ]] && return 0
  done

  return 1
}

# 根据 HEAD 与当前 .gitmodules 的同一 section，识别子模块路径迁移。
find_migrated_submodule_path() {
  local old_path="$1"
  local key=""
  local head_path=""
  local section=""
  local current_path=""

  git -C "$REPO_ROOT" cat-file -e 'HEAD:.gitmodules' 2>/dev/null || return 1
  [[ -f "${REPO_ROOT}/.gitmodules" ]] || return 1
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    head_path="$(git -C "$REPO_ROOT" config --blob HEAD:.gitmodules --get "$key" 2>/dev/null || true)"
    [[ "$head_path" == "$old_path" ]] || continue
    section="${key#submodule.}"
    section="${section%.path}"
    current_path="$(git -C "$REPO_ROOT" config --file .gitmodules --get "submodule.${section}.path" 2>/dev/null || true)"
    if [[ -n "$current_path" && "$current_path" != "$old_path" ]]; then
      printf '%s\n' "$current_path"
      return 0
    fi
  done < <(git -C "$REPO_ROOT" config --blob HEAD:.gitmodules --name-only --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)

  return 1
}

# 修正直接移动子模块目录后仍指向旧路径的 core.worktree。
repair_migrated_submodule_worktree() {
  local submodule_path="$1"
  local child_root="${REPO_ROOT}/${submodule_path}"
  local git_file="${child_root}/.git"
  local gitdir_value=""
  local gitdir_path=""
  local modules_root=""

  is_valid_submodule_worktree "$submodule_path" && return 0
  [[ -f "$git_file" ]] || return 1
  gitdir_value="$(sed -n 's/^gitdir: //p' "$git_file" | head -n 1)"
  [[ -n "$gitdir_value" ]] || return 1
  gitdir_path="${child_root}/${gitdir_value}"
  gitdir_path="${gitdir_path:A}"
  modules_root="$(git -C "$REPO_ROOT" rev-parse --git-path modules 2>/dev/null || true)"
  [[ -n "$modules_root" ]] || return 1
  [[ "$modules_root" == /* ]] || modules_root="${REPO_ROOT}/${modules_root}"
  modules_root="${modules_root:A}"
  [[ "$gitdir_path" == "${modules_root}/"* && -f "${gitdir_path}/config" ]] || return 1

  git config --file "${gitdir_path}/config" core.worktree "$child_root" || return 1
  if is_valid_submodule_worktree "$submodule_path"; then
    success_echo "已修正子模块 core.worktree：${submodule_path}"
    return 0
  fi

  return 1
}

# 判断子模块路径是否已经是有效 Git 工作树。
is_valid_submodule_worktree() {
  local submodule_path="$1"
  local child_root="${REPO_ROOT}/${submodule_path}"
  local actual_root=""
  [[ -d "$child_root" && -e "${child_root}/.git" ]] || return 1
  actual_root="$(git -C "$child_root" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$actual_root" && "${actual_root:A}" == "${child_root:A}" ]]
}
# 将已登记到 .gitmodules 的同源子模块副本改成独立 gitdir，避免共用旧路径元数据。
repair_configured_submodule_alias_copy() {
  local relative_path="$1"
  local candidate_root="$2"
  local borrowed_gitdir="$3"
  local target_url=""
  local borrowed_url=""
  local new_gitdir=""
  local backup_git_file=""
  local failed_git_file=""
  local failed_gitdir=""
  local copied_gitdir=0

  target_url="$(submodule_config_url "$relative_path" 2>/dev/null || true)"
  [[ -n "$target_url" && -f "${borrowed_gitdir}/config" ]] || return 1
  borrowed_url="$(git config --file "${borrowed_gitdir}/config" --get remote.origin.url 2>/dev/null || true)"
  [[ -n "$borrowed_url" && "$borrowed_url" == "$target_url" ]] || return 1
  new_gitdir="$(submodule_gitdir_path "$relative_path" 2>/dev/null || true)"
  [[ -n "$new_gitdir" && "$new_gitdir" != "$borrowed_gitdir" ]] || return 1
  if ! command -v rsync >/dev/null 2>&1; then
    error_echo "未找到 rsync，无法为子模块副本复制独立 gitdir：${relative_path}"
    return 1
  fi

  warn_echo "检测到 ${relative_path} 已登记到 .gitmodules，但仍借用旧 gitdir，正在创建独立 gitdir。"
  gray_echo "旧 gitdir：${borrowed_gitdir}"
  gray_echo "新 gitdir：${new_gitdir}"
  if [[ ! -d "$new_gitdir" ]]; then
    mkdir -p "${new_gitdir:h}" || return 1
    if ! rsync -a --exclude='fsmonitor--daemon*' "${borrowed_gitdir}/" "${new_gitdir}/" >> "$LOG_FILE" 2>&1; then
      failed_gitdir="${new_gitdir}.failed-alias-$(date +%Y%m%d%H%M%S)"
      mv "$new_gitdir" "$failed_gitdir" 2>/dev/null || true
      error_echo "复制子模块 Git 元数据失败，已停止：${relative_path}"
      [[ -n "$failed_gitdir" ]] && warn_echo "失败残留已转存：${failed_gitdir}"
      return 1
    fi
    copied_gitdir=1
  fi

  git config --file "${new_gitdir}/config" core.worktree "$candidate_root" || return 1
  git config --file "${new_gitdir}/config" core.bare false
  backup_git_file="${candidate_root}/.git.alias-backup-$(date +%Y%m%d%H%M%S)"
  failed_git_file="${candidate_root}/.git.failed-alias-$(date +%Y%m%d%H%M%S)"
  mv "${candidate_root}/.git" "$backup_git_file" || return 1
  printf 'gitdir: %s\n' "$new_gitdir" > "${candidate_root}/.git"

  if is_valid_submodule_worktree "$relative_path"; then
    mv "$backup_git_file" "${new_gitdir}/$(basename "$backup_git_file")" 2>/dev/null || true
    success_echo "已为子模块副本创建独立 gitdir：${relative_path}"
    return 0
  fi

  mv "${candidate_root}/.git" "$failed_git_file" 2>/dev/null || true
  mv "$backup_git_file" "${candidate_root}/.git" 2>/dev/null || true
  if [[ "$copied_gitdir" == "1" ]]; then
    failed_gitdir="${new_gitdir}.failed-alias-$(date +%Y%m%d%H%M%S)"
    mv "$new_gitdir" "$failed_gitdir" 2>/dev/null || true
    warn_echo "新 gitdir 验证失败，已转存：${failed_gitdir}"
  fi
  error_echo "子模块副本独立 gitdir 验证失败，已恢复原 .git 指针：${relative_path}"
  return 1
}
# 扫描嵌套 .git 文件，阻止 Sourcetree 把错位副本当作可提交路径。
preflight_gitdir_worktree_aliases() {
  collect_gitlink_paths
  local git_file=""
  local candidate_root=""
  local relative_path=""
  local gitdir_path=""
  local configured_path=""
  local inside_worktree=""
  local failures=0

  while IFS= read -r -d '' git_file; do
    candidate_root="$(dirname "$git_file")"
    [[ "${candidate_root:A}" == "${REPO_ROOT:A}" ]] && continue
    relative_path="${candidate_root#${REPO_ROOT}/}"
    inside_worktree="$(git -C "$candidate_root" rev-parse --is-inside-work-tree 2>/dev/null || true)"
    [[ "$inside_worktree" == "true" ]] && continue
    gitdir_path="$(resolve_gitdir_from_git_file "$candidate_root" 2>/dev/null || true)"
    [[ -n "$gitdir_path" ]] || continue
    configured_path="$(read_configured_worktree_path "$gitdir_path" 2>/dev/null || true)"
    [[ -n "$configured_path" && "$configured_path" != "${candidate_root:A}" ]] || continue

    if is_index_gitlink_path "$relative_path"; then
      if repair_migrated_submodule_worktree "$relative_path"; then
        continue
      fi
    fi
    if repair_configured_submodule_alias_copy "$relative_path" "$candidate_root" "$gitdir_path"; then
      continue
    fi

    error_echo "检测到错位 Git 工作树副本，已停止暂存：${relative_path}"
    warn_echo ".git 指向：${gitdir_path}"
    warn_echo "core.worktree 指向：${configured_path}"
    if [[ -e "$configured_path" ]]; then
      warn_echo "真实工作树仍存在：${configured_path}"
      warn_echo "请在 Sourcetree 打开真实工作树，并手动处理当前异常目录：${candidate_root}"
    else
      warn_echo "core.worktree 指向的旧路径不存在，但当前路径不是父仓登记的 gitlink，脚本不会擅自接管。"
    fi
    failures=$((failures + 1))
  done < <(find "$REPO_ROOT" \
    \( -path "${REPO_ROOT}/.git" -o -path '*/.git/*' -o -path '*/node_modules/*' -o -path '*/Pods/*' -o -path '*/.dart_tool/*' -o -path '*/build/*' -o -path '*/DerivedData/*' \) -prune \
    -o -type f -name .git -print0)

  if [[ "$failures" -gt 0 ]]; then
    error_echo "共有 ${failures} 个 .git/core.worktree 路径错位，未执行 git add -A。"
    return 1
  fi
}

# 判断子模块路径是否只是上次失败初始化留下的空目录。
is_empty_submodule_directory() {
  local submodule_path="$1"
  local child_root="${REPO_ROOT}/${submodule_path}"
  [[ -d "$child_root" ]] || return 1
  [[ -z "$(find "$child_root" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]
}

# 输出子模块内部变更，并阻止父仓误暂存。
report_dirty_submodule() {
  local submodule_path="$1"
  error_echo "子模块内部存在未提交修改，已停止暂存：${submodule_path}"
  git -C "${REPO_ROOT}/${submodule_path}" status --short --untracked-files=all 2>/dev/null | sed 's/^/  /' | tee -a "$LOG_FILE"
  warn_echo "请先在子模块内提交、暂存或明确处理这些改动；脚本不会自动丢弃。"
}

# 对本轮初始化后留下的半成品工作树做安全收口。
recover_new_submodule_worktree() {
  local submodule_path="$1"
  local child_root="${REPO_ROOT}/${submodule_path}"
  local expected_sha=""
  local current_sha=""

  is_valid_submodule_worktree "$submodule_path" || return 1
  expected_sha="$(git -C "$REPO_ROOT" ls-files -s -- "$submodule_path" | awk '$1 == 160000 { print $2; exit }')"
  current_sha="$(git -C "$child_root" rev-parse HEAD 2>/dev/null || true)"
  [[ -n "$current_sha" ]] || return 1

  if [[ -n "$expected_sha" ]] && git -C "$child_root" cat-file -e "${expected_sha}^{commit}" 2>/dev/null; then
    git -C "$child_root" checkout --detach "$expected_sha" >> "$LOG_FILE" 2>&1 || return 1
    current_sha="$expected_sha"
  else
    warn_echo "父仓锁定的子模块提交已不可用：${submodule_path} ${expected_sha:-unknown}"
    warn_echo "已保留新克隆工作树的当前有效 HEAD：${current_sha}"
  fi

  git -C "$child_root" restore --source=HEAD --staged --worktree -- . || return 1
  if [[ -n "$(git -C "$child_root" status --porcelain --untracked-files=all)" ]]; then
    return 1
  fi

  success_echo "子模块工作树已收口为 clean：${submodule_path} @ ${current_sha}"
}

# 判断 .gitmodules 是否已经在索引中记录变更。
gitmodules_has_staged_change() {
  ! git -C "$REPO_ROOT" diff --cached --quiet -- .gitmodules 2>/dev/null
}

# 判断旧 gitlink 是否已从当前 .gitmodules 移除，允许后续 git add -A 暂存删除。
is_retired_gitlink_after_gitmodules_change() {
  local submodule_path="$1"
  local child_root="${REPO_ROOT}/${submodule_path}"

  gitmodules_has_staged_change || return 1
  submodule_has_valid_config "$submodule_path" && return 1
  [[ ! -e "$child_root" ]] || is_empty_submodule_directory "$submodule_path"
}

# 初始化缺失子模块，并防止缺失 gitlink 被误暂存为删除。
ensure_submodule_worktree() {
  local submodule_path="$1"

  if is_valid_submodule_worktree "$submodule_path"; then
    return 0
  fi
  if [[ -e "${REPO_ROOT}/${submodule_path}" ]] && ! is_empty_submodule_directory "$submodule_path"; then
    error_echo "子模块路径已存在，但不是有效 Git 工作树：${submodule_path}"
    return 1
  fi
  if ! submodule_has_valid_config "$submodule_path"; then
    error_echo "gitlink 缺少有效 .gitmodules 配置，不会将它暂存为删除：${submodule_path}"
    return 1
  fi

  warn_echo "检测到缺失子模块工作树，正在按父仓登记尝试初始化：${submodule_path}"
  if git -C "$REPO_ROOT" submodule update --init --recursive -- "$submodule_path" 2>&1 | tee -a "$LOG_FILE"; then
    success_echo "子模块已初始化：${submodule_path}"
    return 0
  fi

  warn_echo "按父仓锁定提交初始化失败，检查是否为远端历史重写。"
  if recover_new_submodule_worktree "$submodule_path"; then
    return 0
  fi

  error_echo "子模块无法安全恢复，已中止：${submodule_path}"
  return 1
}

# 在全量暂存前检查所有 gitlink，子模块不安全时整体中止。
preflight_submodules() {
  collect_gitlink_paths
  if [[ ${#GITLINK_PATHS[@]} -eq 0 ]]; then
    info_echo "当前仓库没有 Git 子模块。"
    return 0
  fi

  info_echo "检测到 ${#GITLINK_PATHS[@]} 个 Git 子模块，开始安全检查。"
  local submodule_path=""
  local effective_path=""
  local migrated_path=""
  local failures=0
  for submodule_path in "${GITLINK_PATHS[@]}"; do
    effective_path="$submodule_path"
    migrated_path="$(find_migrated_submodule_path "$submodule_path" 2>/dev/null || true)"
    if [[ -n "$migrated_path" ]]; then
      effective_path="$migrated_path"
      warn_echo "检测到子模块路径迁移：${submodule_path} -> ${effective_path}"
      if ! repair_migrated_submodule_worktree "$effective_path"; then
        error_echo "新路径不是有效子模块工作树，已停止：${effective_path}"
        failures=$((failures + 1))
        continue
      fi
    else
      if is_retired_gitlink_after_gitmodules_change "$submodule_path"; then
        warn_echo "检测到旧 gitlink 已从当前 .gitmodules 移除，稍后由 git add -A 暂存删除：${submodule_path}"
        continue
      fi
      if ! ensure_submodule_worktree "$submodule_path"; then
        failures=$((failures + 1))
        continue
      fi
    fi
    if [[ -n "$(git -C "${REPO_ROOT}/${effective_path}" status --porcelain --untracked-files=all)" ]]; then
      report_dirty_submodule "$effective_path"
      failures=$((failures + 1))
      continue
    fi
    success_echo "子模块检查通过：${effective_path}"
  done

  if [[ "$failures" -gt 0 ]]; then
    error_echo "共有 ${failures} 个子模块未通过检查，未执行 git add -A。"
    return 1
  fi
}

# 在删除或迁移 gitlink 前优先暂存 .gitmodules，满足 Git 的子模块安全校验顺序。
stage_gitmodules_first() {
  local gitmodules_status=""

  if [[ ! -e "${REPO_ROOT}/.gitmodules" ]] && ! git -C "$REPO_ROOT" ls-files --error-unmatch .gitmodules >/dev/null 2>&1; then
    return 0
  fi
  gitmodules_status="$(git -C "$REPO_ROOT" status --porcelain -- .gitmodules 2>/dev/null || true)"
  [[ -n "$gitmodules_status" ]] || return 0

  if git -C "$REPO_ROOT" diff --quiet -- .gitmodules 2>/dev/null && gitmodules_has_staged_change; then
    info_echo ".gitmodules 已在索引中记录变更，继续处理 gitlink 删除/迁移。"
    return 0
  fi

  info_echo "检测到 .gitmodules 变更，正在优先写入索引 ..."
  gray_echo "典型场景：Sourcetree 先执行 git rm -q -f -- 旧子模块时，Git 会要求先暂存 .gitmodules。"
  git -C "$REPO_ROOT" add -A -- .gitmodules
  success_echo ".gitmodules 已优先暂存，可安全处理后续 gitlink 变更。"
}

# 统一暂存工作区与索引中的全部改动。
stage_all_changes() {
  info_echo "正在安全暂存全部改动 ..."
  git -C "$REPO_ROOT" -c advice.addEmbeddedRepo=false add -A -- .
  success_echo "Git 索引已刷新。"
}

# 输出暂存结果，便于在 Sourcetree 日志窗口中直接核对。
print_staged_summary() {
  local summary=""
  summary="$(git -C "$REPO_ROOT" diff --cached --name-status)"

  if [[ -z "$summary" ]]; then
    info_echo "当前没有待提交的暂存变更。"
    return 0
  fi

  note_echo "已暂存变更："
  printf '%s\n' "$summary" | tee -a "$LOG_FILE"
}

# 串联自述、仓库识别、.gitmodules 优先暂存、子模块预检、索引刷新与结果输出。
run_main_flow() {
  initialize_script_runtime
  show_script_intro_and_wait
  resolve_repo_root "${1:-$PWD}"
  stage_gitmodules_first
  preflight_gitdir_worktree_aliases
  preflight_submodules
  stage_all_changes
  print_staged_summary
  success_echo "处理完成。请回到 Sourcetree 刷新后检查并提交。"
  gray_echo "日志文件：${LOG_FILE}"
}

main() {
  # 主入口只委托完整业务流程，避免交互与 Git 操作散落。
  run_main_flow "$@"
}

main "$@"
