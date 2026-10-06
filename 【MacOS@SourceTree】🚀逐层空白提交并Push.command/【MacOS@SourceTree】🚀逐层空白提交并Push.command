#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】🚀逐层空白提交并Push.command
# - 核心用途：递归提交并推送当前仓库管理的子仓，再处理当前仓库及上层父仓。
# - 影响范围：游离态先丢弃临时内容并恢复远端版本；每层执行 git add -A、必要时提交并向已配置的 GitHub / 码云线路推送。
# - 运行提示：Sourcetree 动作打开 Terminal.app；在终端回车确认后执行并实时显示日志。

# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}
RAW_SCRIPT_PATH="$0"
SCRIPT_PATH=""
SCRIPT_DIR=""
SCRIPT_FILENAME=""
SCRIPT_BASENAME=""
LOG_ROOT="${TMPDIR:-/tmp}"
LOG_FILE=""
PLAIN_OUTPUT=0
IS_SOURCETREE_RUNTIME=0
START_REPOSITORY=""
PROCESSED_COUNT=0
COMMITTED_COUNT=0
PUSHED_COUNT=0
REMOTE_REFS_OUTPUT=""
COLOR_BLUE=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_RED=""
COLOR_CYAN=""
COLOR_RESET=""
typeset -ga REPOSITORY_CHAIN=()
typeset -gA DISCOVERED_REPOSITORIES=()
typeset -gA DETACHED_BRANCHES=()
typeset -gA DETACHED_REMOTES=()
typeset -gA DETACHED_TARGETS=()
typeset -gA SYNC_REMOTES=()
typeset -gA SYNC_REFS=()
typeset -gA SYNC_UPSTREAMS=()
typeset -gA PUSH_TARGETS=()
typeset -ga RESOLVED_PUSH_TARGETS=()
PUSHED_LINE_COUNT=0

# 在解析中文路径和输出自述前统一当前进程的字符编码。
configure_utf8_locale() {
  export LANG=en_US.UTF-8
  export LC_ALL=en_US.UTF-8
  export LC_CTYPE=en_US.UTF-8
}
# 识别脚本是否由 Sourcetree 自定义动作发起。
is_sourcetree_runtime() {
  env | grep -Ei '^SOURCETREE|^SOURCE_TREE' >/dev/null && return 0

  local process_id="$PPID"
  local process_name=""
  local guard=0
  while [[ -n "$process_id" && "$process_id" != "0" && "$guard" -lt 8 ]]; do
    process_name="$(ps -o comm= -p "$process_id" 2>/dev/null || true)"
    [[ "$process_name" == *SourceTree* || "$process_name" == *Sourcetree* ]] && return 0
    process_id="$(ps -o ppid= -p "$process_id" 2>/dev/null | tr -d ' ' || true)"
    guard=$((guard + 1))
  done
  return 1
}
# 从运行副本或备灾副本兜底解析真实脚本路径。
resolve_script_path() {
  local filename="${RAW_SCRIPT_PATH:t}"
  local candidate="${RAW_SCRIPT_PATH:A}"
  local runtime_candidate="/Users/jobs/SourceTree.command/${filename}/${filename}"
  local backup_candidate="/Users/jobs/Documents/Github/JobsGenesis/SourceTree.command/${filename}/${filename}"

  if [[ ! -f "$candidate" && -f "$runtime_candidate" ]]; then
    candidate="$runtime_candidate"
  elif [[ ! -f "$candidate" && -f "$backup_candidate" ]]; then
    candidate="$backup_candidate"
  fi
  SCRIPT_PATH="$candidate"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_FILENAME="${SCRIPT_PATH:t}"
  SCRIPT_BASENAME="${SCRIPT_FILENAME:r}"
  LOG_FILE="${LOG_ROOT%/}/${SCRIPT_BASENAME}.log"
}
# 在首行输出前准备 Sourcetree 所需的纯文本环境。
configure_output_mode() {
  if is_sourcetree_runtime; then
    IS_SOURCETREE_RUNTIME=1
  fi
  if [[ "$IS_SOURCETREE_RUNTIME" == "1" || ! -t 1 || -z "${TERM:-}" || "${TERM:-}" == "dumb" || -n "${NO_COLOR:-}" ]]; then
    PLAIN_OUTPUT=1
    export NO_COLOR=1
    export FORCE_COLOR=0
    export CLICOLOR=0
    export ANSI_COLORS_DISABLED=1
    export npm_config_color=false
    COLOR_BLUE=""
    COLOR_GREEN=""
    COLOR_YELLOW=""
    COLOR_RED=""
    COLOR_CYAN=""
    COLOR_RESET=""
  else
    COLOR_BLUE=$'\033[1;34m'
    COLOR_GREEN=$'\033[1;32m'
    COLOR_YELLOW=$'\033[1;33m'
    COLOR_RED=$'\033[1;31m'
    COLOR_CYAN=$'\033[1;36m'
    COLOR_RESET=$'\033[0m'
  fi
}
# 剔除外部命令输出中的 ANSI 控制字符。
strip_ansi_stream() {
  perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}
# 将 Sourcetree 仓库参数交给独立终端，启动进程只负责打开窗口。
open_terminal_for_repository() {
  local repository="${1:-$PWD}"
  if [[ ! -d "$repository" && ! -f "$repository" ]]; then
    print -u2 -r -- "目标路径不存在：${repository}"
    return 1
  fi
  repository="${repository:A}"
  if ! command -v osascript >/dev/null 2>&1; then
    print -u2 -r -- "未找到 osascript，无法打开 Terminal.app。"
    return 1
  fi
  if ! osascript - "$SCRIPT_PATH" "$repository" <<'APPLESCRIPT'
on run argv
  set scriptPath to item 1 of argv
  set repositoryPath to item 2 of argv
  set shellCommand to "/bin/zsh " & quoted form of scriptPath & " " & quoted form of repositoryPath & "; jobs_push_result=$?; printf '\n逐层推送结束，退出码：%s\n' \"$jobs_push_result\""
  tell application "Terminal"
    activate
    do script shellCommand
  end tell
end run
APPLESCRIPT
  then
    print -u2 -r -- "终端启动失败；请检查 Terminal.app 自动化权限，或在终端直接运行脚本。"
    return 1
  fi
  print -r -- "已打开终端，请在新窗口回车确认；实时进度和最终结果均在终端查看。"
}
# 输出脚本内置自述，并按运行入口决定是否等待确认。
show_script_intro_and_wait() {
  configure_utf8_locale
  resolve_script_path
  configure_output_mode
  if [[ "$IS_SOURCETREE_RUNTIME" != "1" && -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" ]]; then
    clear
  fi

  print -r -- "============================== 脚本内置自述 ==============================" | jobs_intro_style title
  print -r -- "脚本名称：${SCRIPT_FILENAME}" | jobs_intro_style title
  print -r -- "核心用途：递归处理当前仓库管理的子仓，先子仓 commit + push，再处理当前仓库及父仓。" | jobs_intro_style body
  print -r -- "扫描边界：按 Git 索引中的 gitlink 发现子仓；跳过依赖及构建目录，不扫描上层兄弟仓。" | jobs_intro_style body
  print -r -- "影响范围：每层会执行 git add -A；无改动时不制造空提交，但仍尝试推送已有提交。" | jobs_intro_style body
  print -r -- "正常分支：先获取主上游及 GitHub / 码云各推送线路，提交并整合后逐条 push、核验同一提交；冲突时停止。" | jobs_intro_style body
  print -r -- "游离态策略：fetch 后舍弃游离态独有提交、未提交改动及未跟踪文件，恢复远端最新分支；保留忽略文件。" | jobs_intro_style body
  print -r -- "停止边界：冲突、未完成操作、恢复目标不明确、fetch 或 push 失败时停止；正常分支的改动保留。" | jobs_intro_style body
  print -r -- "运行策略：Sourcetree 打开独立终端；终端回车确认后执行，实时显示日志，按 Ctrl+C 取消。" | jobs_intro_style body
  print -r -- "日志文件：${LOG_FILE}" | jobs_intro_style body
  print -r -- "============================================================================" | jobs_intro_style title
  print "" | jobs_intro_style body

  if [[ "$IS_SOURCETREE_RUNTIME" == "1" ]]; then
    open_terminal_for_repository "$@"
    exit $?
  fi
  if [[ ! -t 0 ]]; then
    print -u2 -r -- "当前不是 Sourcetree，且没有可交互输入；请在终端中重新运行。"
    exit 1
  fi
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 在用户确认后初始化 zsh 选项和本次日志。
initialize_script_runtime() {
  setopt ERR_EXIT
  setopt NO_NOMATCH
  setopt PIPE_FAIL
  if ! : > "$LOG_FILE"; then
    print -u2 -r -- "无法创建日志文件：${LOG_FILE}；请检查临时目录是否存在且可写。"
    exit 1
  fi
  configure_output_mode
}
# 按当前输出模式记录消息。
log() {
  local message="$1"
  if [[ "$PLAIN_OUTPUT" == "1" ]]; then
    print -r -- "$message" | strip_ansi_stream | tee -a "$LOG_FILE"
  else
    print -r -- "$message" | tee -a "$LOG_FILE"
  fi
}
# 记录普通信息。
info_echo() {
  log "${COLOR_BLUE}ℹ $1${COLOR_RESET}"
}
# 记录成功信息。
success_echo() {
  log "${COLOR_GREEN}✔ $1${COLOR_RESET}"
}
# 记录警告信息。
warn_echo() {
  log "${COLOR_YELLOW}⚠ $1${COLOR_RESET}"
}
# 记录错误信息。
error_echo() {
  log "${COLOR_RED}✖ $1${COLOR_RESET}"
}
# 记录步骤和强调信息。
highlight_echo() {
  log "${COLOR_CYAN}🔹 $1${COLOR_RESET}"
}
# 执行 Git 命令，同时保留退出码并同步日志。
run_git() {
  local repository="$1"
  local exit_code=0
  shift
  if [[ "$PLAIN_OUTPUT" == "1" ]]; then
    git -C "$repository" "$@" 2>&1 | strip_ansi_stream | tee -a "$LOG_FILE"
    exit_code="${pipestatus[1]}"
  else
    git -C "$repository" "$@" 2>&1 | tee -a "$LOG_FILE"
    exit_code="${pipestatus[1]}"
  fi
  return "$exit_code"
}
# 查询远端引用，分开保存数据与错误，短暂失败最多重试三次。
read_remote_refs() {
  local repository="$1"
  local attempt=1 exit_code=0 error_file="" error_text=""
  shift
  REMOTE_REFS_OUTPUT=""
  error_file="$(mktemp "${LOG_ROOT%/}/jobs-remote-query.XXXXXX")" || return 1
  while [[ "$attempt" -le 3 ]]; do
    if REMOTE_REFS_OUTPUT="$(git -C "$repository" ls-remote "$@" 2>"$error_file")"; then
      error_text="$(<"$error_file")"
      [[ -z "$error_text" ]] || log "$error_text" >&2
      rm -f -- "$error_file"
      return 0
    else
      exit_code=$?
    fi
    REMOTE_REFS_OUTPUT=""
    error_text="$(<"$error_file")"
    error_echo "远端查询失败（${attempt}/3，退出码 ${exit_code}）：${repository}" >&2
    if [[ -n "$error_text" ]]; then
      log "$error_text" >&2
    else
      warn_echo "Git 未返回标准错误；请结合网络、凭据和 Sourcetree 运行环境检查。" >&2
    fi
    if [[ "$attempt" -lt 3 ]]; then
      info_echo "${attempt} 秒后重新查询远端。" >&2
      sleep "$attempt"
    fi
    attempt=$((attempt + 1))
  done
  rm -f -- "$error_file"
  return "$exit_code"
}
# 检查 Git 和脚本依赖的 macOS 基础命令。
check_environment() {
  local command_name=""
  for command_name in git perl ps tr tee mktemp sleep rm; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      error_echo "未找到必需命令：${command_name}"
      return 1
    fi
  done
  if ! git --version >/dev/null 2>&1; then
    error_echo "Git 命令存在但无法正常运行。"
    return 1
  fi
  success_echo "Git 环境检查通过：$(git --version)"
}
# 把 Sourcetree 传入路径或当前目录解析为起始 Git 根目录。
resolve_start_repository() {
  local candidate="${1:-$PWD}"
  if [[ -f "$candidate" ]]; then
    candidate="${candidate:h}"
  fi
  if [[ ! -d "$candidate" ]]; then
    error_echo "目标路径不存在：${candidate}"
    return 1
  fi

  START_REPOSITORY="$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "$START_REPOSITORY" || ! -d "$START_REPOSITORY" ]]; then
    error_echo "目标不在 Git 工作区内：${candidate}"
    return 1
  fi
  START_REPOSITORY="$(cd "$START_REPOSITORY" 2>/dev/null && pwd -P)" || {
    error_echo "无法解析 Git 根目录：${START_REPOSITORY}"
    return 1
  }
  success_echo "起始 Git 仓库：${START_REPOSITORY}"
}
# 识别当前仓库的最近上层 Git 仓库。
find_parent_repository() {
  local current_repository="$1"
  local parent_repository=""
  local parent_directory=""

  parent_repository="$(git -C "$current_repository" rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  if [[ -n "$parent_repository" ]]; then
    (cd "$parent_repository" 2>/dev/null && pwd -P)
    return $?
  fi

  parent_directory="${current_repository:h}"
  [[ "$parent_directory" == "$current_repository" ]] && return 1
  parent_repository="$(git -C "$parent_directory" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$parent_repository" && "$parent_repository" != "$current_repository" ]] || return 1
  (cd "$parent_repository" 2>/dev/null && pwd -P)
}
# 判断子仓路径是否位于默认排除的依赖或生成目录。
is_excluded_repository_path() {
  local component=""
  for component in "${(@s:/:)1}"; do
    case "$component" in
      .git|node_modules|Pods|.dart_tool|build|DerivedData) return 0 ;;
    esac
  done
  return 1
}
# 按 gitlink 递归发现受管理子仓，后序入队确保子仓先于父仓推送。
collect_repository_subtree() {
  local repository="$1"
  local entries=""
  local entry=""
  local relative_path=""
  local child_repository=""
  local child_root=""
  [[ -n "${DISCOVERED_REPOSITORIES[$repository]:-}" ]] && return 0
  DISCOVERED_REPOSITORIES[$repository]=1
  if ! entries="$(git -C "$repository" ls-files --stage -z)"; then
    error_echo "无法读取子仓索引：${repository}"
    return 1
  fi
  while IFS= read -r -d '' entry; do
    [[ "$entry" == '160000 '* ]] || continue
    relative_path="${entry#*$'\t'}"
    if is_excluded_repository_path "$relative_path"; then
      warn_echo "跳过依赖或构建目录中的子仓：${repository}/${relative_path}"
      continue
    fi
    child_repository="${repository}/${relative_path}"
    child_root="$(git -C "$child_repository" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ ! -d "$child_repository" || -L "$child_repository" || "${child_root:A}" != "${child_repository:A}" ]]; then
      error_echo "子仓未初始化或工作区无效，请先恢复后重试：${child_repository}"
      return 1
    fi
    collect_repository_subtree "${child_repository:A}" || return 1
  done < <(print -rn -- "$entries")
  REPOSITORY_CHAIN+=("$repository")
}
# 建立当前子树的后序队列，再追加上层父仓，不扩展上层兄弟仓。
build_repository_chain() {
  local current_repository="$START_REPOSITORY"
  local parent_repository=""
  local existing_repository=""
  local duplicated=0
  local index=1

  REPOSITORY_CHAIN=()
  DISCOVERED_REPOSITORIES=()
  collect_repository_subtree "$START_REPOSITORY" || return 1
  current_repository="$(find_parent_repository "$START_REPOSITORY" 2>/dev/null || true)"
  while [[ -n "$current_repository" ]]; do
    duplicated=0
    for existing_repository in "${REPOSITORY_CHAIN[@]}"; do
      [[ "$existing_repository" == "$current_repository" ]] && duplicated=1
    done
    [[ "$duplicated" == "1" ]] && break
    REPOSITORY_CHAIN+=("$current_repository")
    parent_repository="$(find_parent_repository "$current_repository" 2>/dev/null || true)"
    [[ -n "$parent_repository" && "$parent_repository" != "$current_repository" ]] || break
    current_repository="$parent_repository"
  done

  highlight_echo "已识别 ${#REPOSITORY_CHAIN[@]} 个 Git 仓库，将先子仓、后父仓处理："
  for current_repository in "${REPOSITORY_CHAIN[@]}"; do
    info_echo "${index}、${current_repository}"
    index=$((index + 1))
  done
}
# 选择未配置 upstream 时唯一可靠的推送远端。
resolve_fallback_remote() {
  local repository="$1"
  local -a remotes=()
  if git -C "$repository" remote get-url --push origin >/dev/null 2>&1; then
    print -r -- "origin"
    return 0
  fi
  remotes=("${(@f)$(git -C "$repository" remote 2>/dev/null)}")
  if [[ "${#remotes[@]}" -eq 1 && -n "${remotes[1]:-}" ]]; then
    git -C "$repository" remote get-url --push "${remotes[1]}" >/dev/null 2>&1 || return 1
    print -r -- "${remotes[1]}"
    return 0
  fi
  return 1
}
# 检查冲突和正在进行的 Git 操作，禁止在中间状态执行清理。
check_repository_operation() {
  local repository="$1"
  local git_directory="$(git -C "$repository" rev-parse --absolute-git-dir)" || return 1
  local marker=""
  local conflicts="$(git -C "$repository" ls-files --unmerged)" || return 1
  if [[ -n "$conflicts" ]]; then
    error_echo "存在未解决冲突：${repository}"
    run_git "$repository" diff --name-only --diff-filter=U
    error_echo "请解决上述文件并 git add 标记；再次运行时会完成待提交的合并。"
    return 1
  fi
  for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply sequencer; do
    if [[ -e "$git_directory/$marker" ]]; then
      if [[ "$marker" == MERGE_HEAD ]] && git -C "$repository" symbolic-ref --quiet HEAD >/dev/null; then
        info_echo "合并冲突已全部标记解决，将在提交阶段完成合并：${repository}"
        continue
      fi
      error_echo "存在未完成操作 ${marker}：${repository}"
      return 1
    fi
  done
}
# 优先读取父仓声明的子模块分支，没有声明时使用远端公布的默认分支。
resolve_detached_branch() {
  local repository="$1" remote="$2"
  local parent="$(find_parent_repository "$repository" || true)"
  local record="" key="" value="" branch="" advertised=""
  if [[ -n "$parent" && -f "$parent/.gitmodules" ]]; then
    while IFS= read -r -d '' record; do
      key="${record%%$'\n'*}"
      value="${record#*$'\n'}"
      [[ "${parent}/${value}" == "$repository" ]] || continue
      branch="$(git -C "$parent" config -f .gitmodules --get "${key%.path}.branch" || true)"
      if [[ "$branch" == '.' ]]; then
        branch="$(git -C "$parent" symbolic-ref --quiet --short HEAD || true)"
        [[ -n "$branch" ]] || return 1
      fi
      break
    done < <(git -C "$parent" config -z -f .gitmodules --get-regexp '^submodule\..*\.path$' || true)
  fi
  if [[ -z "$branch" ]]; then
    read_remote_refs "$repository" --symref "$remote" HEAD || return 1
    advertised="$REMOTE_REFS_OUTPUT"
    for record in "${(@f)advertised}"; do
      if [[ "$record" == 'ref: refs/heads/'*$'\tHEAD' ]]; then
        branch="${${record#ref: refs/heads/}%$'\tHEAD'}"
      fi
    done
  fi
  [[ -n "$branch" ]] || return 1
  git check-ref-format "refs/heads/$branch" >/dev/null || return 1
  print -r -- "$branch"
}
# 拒绝会覆盖忽略文件或改变子仓路径的恢复，确保已发现的子仓内容不被清理。
check_detached_restore_paths() {
  local repository="$1" target="$2"
  local ignored="" tracked="" current_links="" target_links=""
  local ignored_entries="$(git -C "$repository" ls-files --others --ignored --exclude-standard -z)" || return 1
  local tracked_entries=""
  tracked_entries="$(git -C "$repository" ls-tree -rz --name-only HEAD)$(git -C "$repository" ls-tree -rz --name-only "$target")" || return 1
  while IFS= read -r -d '' ignored; do
    while IFS= read -r -d '' tracked; do
      if [[ "$ignored" == "$tracked" || "$ignored" == "$tracked/"* || "$tracked" == "$ignored/"* ]]; then
        error_echo "忽略文件与恢复目标冲突，保留原状：${repository}/${ignored}"
        return 1
      fi
    done < <(print -rn -- "$tracked_entries")
  done < <(print -rn -- "$ignored_entries")
  current_links="$(git -C "$repository" ls-files --stage -z | perl -0ne 'print substr($_, index($_, "\t") + 1) if /^160000 /')" || return 1
  target_links="$(git -C "$repository" ls-tree -rz "$target" | perl -0ne 'print substr($_, index($_, "\t") + 1) if /^160000 /')" || return 1
  if [[ "$current_links" != "$target_links" ]]; then
    error_echo "远端版本改变了子仓路径，请先人工同步子模块结构：${repository}"
    return 1
  fi
}
# 全量准备恢复计划并获取远端最新提交，全部成功后才允许清理游离工作区。
prepare_detached_repositories() {
  local repository="" remote="" branch="" target="" local_tip="" worktrees=""
  DETACHED_BRANCHES=()
  DETACHED_REMOTES=()
  DETACHED_TARGETS=()
  export GIT_TERMINAL_PROMPT=0
  for repository in "${REPOSITORY_CHAIN[@]}"; do
    check_repository_operation "$repository" || return 1
    if git -C "$repository" symbolic-ref --quiet HEAD >/dev/null; then
      preflight_repository "$repository" || return 1
      continue
    fi
    remote="$(resolve_fallback_remote "$repository")" || { error_echo "无法确定恢复远端：${repository}"; return 1; }
    branch="$(resolve_detached_branch "$repository" "$remote")" || { error_echo "无法确定恢复分支：${repository}"; return 1; }
    info_echo "准备游离态恢复：${repository} -> ${remote}/${branch}"
    run_git "$repository" fetch --no-recurse-submodules --no-tags "$remote" "+refs/heads/${branch}:refs/remotes/${remote}/${branch}" || return 1
    target="$(git -C "$repository" rev-parse --verify "refs/remotes/${remote}/${branch}^{commit}")" || return 1
    local_tip="$(git -C "$repository" rev-parse --verify "refs/heads/${branch}" 2>/dev/null || true)"
    if [[ -n "$local_tip" ]] && ! git -C "$repository" merge-base --is-ancestor "$local_tip" "$target"; then
      error_echo "目标本地分支含远端没有的提交，不覆盖正常分支历史：${repository} [${branch}]"
      return 1
    fi
    worktrees="$(git -C "$repository" worktree list --porcelain)" || return 1
    if [[ $'\n'"$worktrees"$'\n' == *$'\n'"branch refs/heads/$branch"$'\n'* ]]; then
      error_echo "恢复分支被其它工作树占用：${repository} [${branch}]"
      return 1
    fi
    check_detached_restore_paths "$repository" "$target" || return 1
    DETACHED_BRANCHES[$repository]="$branch"
    DETACHED_REMOTES[$repository]="$remote"
    DETACHED_TARGETS[$repository]="$target"
  done
}
# 清理已完成预检的游离工作区，禁止递归重置子模块和删除忽略文件。
restore_detached_repositories() {
  local repository="" branch="" remote="" target="" confirmation=""
  [[ ${#DETACHED_TARGETS} -gt 0 ]] || return 0
  if [[ "$IS_SOURCETREE_RUNTIME" != 1 ]]; then
    warn_echo "将舍弃 ${#DETACHED_TARGETS} 个游离仓库的独有提交、未提交改动和未跟踪文件。"
    read -r 'confirmation?输入 YES 执行恢复，其它输入取消：'
    [[ "$confirmation" == YES ]] || { error_echo "已取消游离态恢复。"; return 1; }
  fi
  for repository in "${REPOSITORY_CHAIN[@]}"; do
    target="${DETACHED_TARGETS[$repository]:-}"
    [[ -n "$target" ]] || continue
    branch="${DETACHED_BRANCHES[$repository]}"
    remote="${DETACHED_REMOTES[$repository]}"
    check_repository_operation "$repository" || return 1
    if git -C "$repository" symbolic-ref --quiet HEAD >/dev/null; then
      error_echo "仓库分支在预检后发生变化，停止清理：${repository}"
      return 1
    fi
    warn_echo "舍弃游离态内容并恢复：${repository} -> ${remote}/${branch} [${target}]"
    run_git "$repository" -c submodule.recurse=false reset --hard --no-recurse-submodules HEAD || return 1
    run_git "$repository" clean -fd || return 1
    run_git "$repository" -c submodule.recurse=false switch --no-recurse-submodules --no-overwrite-ignore -C "$branch" "$target" || return 1
    run_git "$repository" branch --set-upstream-to="${remote}/${branch}" "$branch" || return 1
    success_echo "已消除游离 HEAD：${repository}"
  done
}
# 在任何提交前检查单层仓库的分支、冲突和推送目标。
preflight_repository() {
  local repository="$1"
  local branch_name=""
  local git_directory=""
  local operation_marker=""
  local upstream=""
  local fallback_remote=""

  if ! git -C "$repository" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error_echo "不是有效 Git 工作区：${repository}"
    return 1
  fi
  branch_name="$(git -C "$repository" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ -z "$branch_name" ]]; then
    error_echo "当前处于游离 HEAD，为避免生成难以找回的提交已停止：${repository}"
    return 1
  fi
  check_repository_operation "$repository" || return 1
  local primary="$(git -C "$repository" config --get "branch.${branch_name}.remote" || true)"
  [[ -n "$primary" ]] || primary="$(resolve_fallback_remote "$repository")" || return 1
  resolve_push_targets "$repository" "$primary" || {
    error_echo "无法解析推送线路：${repository}"
    return 1
  }
  info_echo "已识别 ${#RESOLVED_PUSH_TARGETS[@]} 条推送线路：${repository}"

  upstream="$(git -C "$repository" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [[ -z "$upstream" ]]; then
    fallback_remote="$(resolve_fallback_remote "$repository" 2>/dev/null || true)"
    if [[ -z "$fallback_remote" ]]; then
      error_echo "当前分支未配置 upstream，且无法唯一确定推送远端：${repository}"
      return 1
    fi
    info_echo "预检通过：${repository} [${branch_name}] 将首次推送到 ${fallback_remote}/${branch_name}"
  else
    info_echo "预检通过：${repository} [${branch_name} -> ${upstream}]"
  fi
}
# 在真实修改前对整条父仓链执行完整预检。
preflight_repository_chain() {
  local repository=""
  for repository in "${REPOSITORY_CHAIN[@]}"; do
    preflight_repository "$repository" || return 1
  done
  success_echo "全部仓库预检通过，开始由内向外处理。"
}
# 暂存单层仓库全部改动，必要时创建空白说明提交。
commit_repository_changes() {
  local repository="$1"
  local merge_pending=0
  check_repository_operation "$repository" || return 1
  git -C "$repository" rev-parse --quiet --verify MERGE_HEAD >/dev/null && merge_pending=1
  info_echo "正在暂存全部改动：${repository}"
  if ! run_git "$repository" add -A; then
    error_echo "git add -A 失败：${repository}"
    return 1
  fi
  if [[ "$merge_pending" == 0 ]] && git -C "$repository" diff --cached --quiet --exit-code; then
    info_echo "当前层没有需要新建提交的改动，继续检查 push：${repository}"
    return 0
  fi

  info_echo "正在创建空白提交说明的提交：${repository}"
  if ! run_git "$repository" commit --allow-empty-message --message=""; then
    error_echo "Git 提交失败，已停止处理上层：${repository}"
    return 1
  fi
  COMMITTED_COUNT=$((COMMITTED_COUNT + 1))
  success_echo "已完成空白说明提交：${repository}"
}
# 收集主上游及 GitHub / 码云远端的全部 push URL，按地址去重。
resolve_push_targets() {
  local repository="$1" primary="$2"
  local remote="" target="" urls=""
  local -a remotes=("$primary")
  local -A seen=()
  RESOLVED_PUSH_TARGETS=()
  remotes+=("${(@f)$(git -C "$repository" remote)}")
  for remote in "${remotes[@]}"; do
    [[ -n "$remote" ]] || continue
    urls="$(git -C "$repository" remote get-url --push --all "$remote")" || return 1
    for target in "${(@f)urls}"; do
      if [[ "$remote" != "$primary" ]]; then
        case "${remote:l}:${target:l}" in
          github:*|gitee:*|*://github.com/*|*://gitee.com/*|*@github.com:*|*@gitee.com:*|*://*@github.com/*|*://*@gitee.com/*) ;;
          *) continue ;;
        esac
      fi
      [[ -n "$target" && -z "${seen[$target]:-}" ]] || continue
      seen[$target]=1
      RESOLVED_PUSH_TARGETS+=("$target")
    done
  done
  [[ "${#RESOLVED_PUSH_TARGETS[@]}" -gt 0 ]]
}
# 在提交前获取每条推送线路的目标分支，空远端留待首次推送。
synchronize_repository_upstream() {
  local repository="$1"
  local branch="$(git -C "$repository" symbolic-ref --quiet --short HEAD)" || return 1
  local remote="$(git -C "$repository" config --get "branch.${branch}.remote" || true)"
  local remote_ref="$(git -C "$repository" config --get "branch.${branch}.merge" || true)"
  local advertised="" upstream="" target="" index=0
  local -a upstreams=()
  if [[ -z "$remote" || -z "$remote_ref" ]]; then
    remote="$(resolve_fallback_remote "$repository")" || return 1
    remote_ref="refs/heads/${branch}"
  fi
  if [[ "$remote" == '.' || "$remote_ref" != refs/heads/* ]]; then
    error_echo "无法确定可推送的远端上游：${repository}"
    return 1
  fi
  resolve_push_targets "$repository" "$remote" || return 1
  SYNC_REMOTES[$repository]="$remote"
  SYNC_REFS[$repository]="$remote_ref"
  PUSH_TARGETS[$repository]="${(F)RESOLVED_PUSH_TARGETS}"
  SYNC_UPSTREAMS[$repository]=""
  for target in "${RESOLVED_PUSH_TARGETS[@]}"; do
    index=$((index + 1))
    info_echo "读取第 ${index}/${#RESOLVED_PUSH_TARGETS[@]} 条推送线路：${repository}"
    read_remote_refs "$repository" --heads "$target" "$remote_ref" || {
      error_echo "无法读取第 ${index} 条线路的远端分支：${repository}"
      return 1
    }
    advertised="$REMOTE_REFS_OUTPUT"
    if [[ -z "$advertised" ]]; then
      info_echo "该线路分支尚不存在，将首次推送：${remote_ref}"
      continue
    fi
    upstream="refs/jobs-push-sync/${index}/${remote_ref#refs/heads/}"
    run_git "$repository" fetch --no-recurse-submodules --no-tags "$target" "+${remote_ref}:${upstream}" || return 1
    upstreams+=("$upstream")
  done
  SYNC_UPSTREAMS[$repository]="${(F)upstreams}"
}
# 整合全部线路后才推送，确保所有远端收到同一个最终提交。
integrate_repository_upstream() {
  local repository="$1" upstream=""
  local -a upstreams=("${(@f)SYNC_UPSTREAMS[$repository]}")
  for upstream in "${upstreams[@]}"; do
    [[ -n "$upstream" ]] || continue
    if git -C "$repository" merge-base --is-ancestor "$upstream" HEAD; then
      continue
    fi
    check_detached_restore_paths "$repository" "$upstream" || return 1
    info_echo "整合远端提交：${repository} [${upstream}]"
    if ! run_git "$repository" -c submodule.recurse=false merge --ff --no-edit --no-autostash "$upstream"; then
      error_echo "远端整合失败，保留本地提交和现场；如有冲突请解决后重新运行：${repository}"
      return 1
    fi
  done
}
# 逐条推送并核验实际 push 地址，全部成功后才标记本仓完成。
push_repository() {
  local repository="$1"
  local remote="${SYNC_REMOTES[$repository]}" remote_ref="${SYNC_REFS[$repository]}"
  local remote_tip="" local_tip="" advertised="" target="" index=0
  local branch="$(git -C "$repository" symbolic-ref --quiet --short HEAD)" || return 1
  local -a targets=("${(@f)PUSH_TARGETS[$repository]}")
  local_tip="$(git -C "$repository" rev-parse HEAD)" || return 1
  for target in "${targets[@]}"; do
    index=$((index + 1))
    info_echo "正在推送第 ${index}/${#targets[@]} 条线路：${repository} [${remote_ref#refs/heads/}]"
    if ! run_git "$repository" push "$target" "HEAD:${remote_ref}"; then
      error_echo "第 ${index} 条线路 push 失败，已成功线路保留，停止处理上层：${repository}"
      return 1
    fi
    read_remote_refs "$repository" --heads "$target" "$remote_ref" || return 1
    advertised="$REMOTE_REFS_OUTPUT"
    remote_tip="${advertised%%$'\t'*}"
    if [[ "$local_tip" != "$remote_tip" ]]; then
      error_echo "第 ${index} 条线路提交核验失败，停止处理上层：${repository}"
      return 1
    fi
    PUSHED_LINE_COUNT=$((PUSHED_LINE_COUNT + 1))
    success_echo "第 ${index} 条线路已核验一致：${local_tip}"
  done
  # 地址推送不改变 upstream，首次推送后仍只关联原来的主远端。
  run_git "$repository" config "branch.${branch}.remote" "$remote" || return 1
  run_git "$repository" config "branch.${branch}.merge" "$remote_ref" || return 1
  PUSHED_COUNT=$((PUSHED_COUNT + 1))
  success_echo "全部 ${#targets[@]} 条线路已同步：${repository}"
}
# 严格按内到外顺序提交并推送整条仓库链。
process_repository_chain() {
  local repository=""
  local level=1
  for repository in "${REPOSITORY_CHAIN[@]}"; do
    highlight_echo "==================== 处理第 ${level}/${#REPOSITORY_CHAIN[@]} 个仓库 ===================="
    info_echo "仓库：${repository}"
    if ! synchronize_repository_upstream "$repository" || ! commit_repository_changes "$repository" || ! integrate_repository_upstream "$repository" || ! push_repository "$repository"; then
      error_echo "处理停止：总数 ${#REPOSITORY_CHAIN[@]}，已完成 ${PROCESSED_COUNT}，失败 1；剩余仓库未执行。"
      info_echo "日志文件：${LOG_FILE}"
      return 1
    fi
    PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
    level=$((level + 1))
  done
}
# 输出整条仓库链的成功统计和日志位置。
show_completion_summary() {
  highlight_echo "============================== 处理完成 =============================="
  success_echo "已由内到外处理 ${PROCESSED_COUNT} 个 Git 仓库。"
  success_echo "新建空白说明提交：${COMMITTED_COUNT} 个；完整推送：${PUSHED_COUNT} 个仓库、${PUSHED_LINE_COUNT} 条线路；失败 0。"
  info_echo "日志文件：${LOG_FILE}"
  highlight_echo "======================================================================="
}
# 编排自述、环境检查、父仓发现、预检与逐层推送。
main() {
  show_script_intro_and_wait "$@" # Sourcetree 转交终端；终端展示影响并等待确认。
  initialize_script_runtime # 在确认后启用 zsh 选项并初始化本次日志。
  check_environment # 验证 Git 与基础命令真实可用。
  resolve_start_repository "$@" # 从 Sourcetree 参数或当前目录解析起始 Git 仓库。
  build_repository_chain # 递归发现当前子树，按子仓优先排序并追加上层父仓。
  prepare_detached_repositories # 先验证全部仓库并 fetch 游离态目标，失败时不清理文件。
  restore_detached_repositories # 舍弃确认范围内的游离态内容，恢复到已获取的远端版本。
  preflight_repository_chain # 在写入前统一检查所有层的安全条件与推送目标。
  process_repository_chain # 对每层执行全量暂存、空白说明提交和推送。
  show_completion_summary # 汇总已处理层数、提交数和推送结果。
}

main "$@"
