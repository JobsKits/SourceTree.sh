#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】📥修复Git无法Fetch.command
# - 核心用途：先正常 Fetch；仅当远端跟踪引用出现文件/目录冲突时，备份阻塞元数据并重试。
# - 关键场景：上游分支在 foo 与 foo/bar 之间迁移，或远端大小写分支在 MacOS 上映射到同一路径。
# - 影响范围：只更新远端跟踪引用及 .git 元数据；不修改工作区、索引、本地提交或分支。
# - 运行提示：Sourcetree 模式无交互连续执行；终端独立运行需先按回车确认。

SCRIPT_NAME="${0:t}"
SCRIPT_BASENAME="${SCRIPT_NAME:r}"
LOG_DIR="${TMPDIR:-/tmp}"
LOG_DIR="${LOG_DIR%/}"
LOG_FILE="${LOG_DIR}/${SCRIPT_BASENAME}.log"
IS_SOURCETREE_RUNTIME=0
PLAIN_OUTPUT=0
LOG_READY=0
REPO_ROOT=""
REMOTE_NAME=""
GIT_COMMON_DIR=""
REMOTE_REFS_ROOT=""
REMOTE_LOGS_ROOT=""
FETCH_OUTPUT=""
FETCH_STATUS=0
REMOTE_HEADS_OUTPUT=""
BACKUP_ROOT=""
BLOCKER_COUNT=0
typeset -ga REMOTE_BRANCHES
REMOTE_BRANCHES=()
typeset -ga CONFLICT_BRANCHES
CONFLICT_BRANCHES=()

# 识别脚本是否由 Sourcetree 自定义动作发起。
is_sourcetree_runtime() {
  /usr/bin/env | /usr/bin/grep -Eqi '^SOURCETREE|^SOURCE_TREE' && return 0
  [[ "$0" != /* && -f "${HOME}/SourceTree.command/${SCRIPT_NAME}/${SCRIPT_NAME}" ]] && return 0

  local pid="$PPID"
  local command_name=""
  local guard=0
  while [[ -n "$pid" && "$pid" != "0" && "$guard" -lt 8 ]]; do
    command_name="$(/bin/ps -o comm= -p "$pid" 2>/dev/null || true)"
    [[ "$command_name" == *SourceTree* || "$command_name" == *Sourcetree* ]] && return 0
    pid="$(/bin/ps -o ppid= -p "$pid" 2>/dev/null | /usr/bin/tr -d ' ' || true)"
    guard=$((guard + 1))
  done
  return 1
}
# 移除 ANSI 颜色码，避免 Sourcetree 输出窗口显示乱码。
strip_ansi_stream() {
  /usr/bin/perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}
# 在首次输出前确定 Sourcetree 和纯文本输出模式。
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
  fi
}
# 同步输出终端日志和本地日志文件。
log() {
  local message="$1"
  if [[ "$LOG_READY" != "1" ]]; then
    [[ "$PLAIN_OUTPUT" == "1" ]] && printf '%b\n' "$message" | strip_ansi_stream || printf '%b\n' "$message"
    return 0
  fi
  if [[ "$PLAIN_OUTPUT" == "1" ]]; then
    printf '%b\n' "$message" | strip_ansi_stream | /usr/bin/tee -a "$LOG_FILE"
  else
    printf '%b\n' "$message" | /usr/bin/tee -a "$LOG_FILE"
  fi
}
# 输出信息级别日志。
info_echo() { log "\033[1;34mℹ $1\033[0m"; }
# 输出成功级别日志。
success_echo() { log "\033[1;32m✔ $1\033[0m"; }
# 输出警告级别日志。
warn_echo() { log "\033[1;33m⚠ $1\033[0m"; }
# 输出说明级别日志。
note_echo() { log "\033[1;35m➤ $1\033[0m"; }
# 输出错误级别日志。
error_echo() { log "\033[1;31m✖ $1\033[0m"; }
# 输出次要信息日志。
gray_echo() { log "\033[0;90m$1\033[0m"; }
# 输出高亮分隔信息。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 原样输出 Git 命令结果，并在需要时移除 ANSI 控制字符。
log_external_output() {
  local output="$1"
  [[ -n "$output" ]] || return 0
  if [[ "$PLAIN_OUTPUT" == "1" ]]; then
    print -r -- "$output" | strip_ansi_stream | /usr/bin/tee -a "$LOG_FILE"
  else
    print -r -- "$output" | /usr/bin/tee -a "$LOG_FILE"
  fi
}
# 展示脚本内置自述，终端模式等待确认，Sourcetree 模式直接继续。
show_script_intro_and_wait() {
  configure_output_mode
  highlight_echo "============================== 脚本内置自述 =============================="
  note_echo "脚本名称：${SCRIPT_NAME}"
  note_echo "核心行为：先执行正常 git fetch --prune；仅在命中远端跟踪引用的文件/目录冲突时进入修复。"
  note_echo "修复策略：读取远端真实分支，清理失效的 remote-tracking refs，备份阻塞的 loose ref/reflog，然后重试 Fetch。"
  note_echo "适用场景：上游分支在 foo 与 foo/bar 之间迁移，或 SaaS 与 saas/... 在 MacOS 上发生大小写路径碰撞。"
  note_echo "安全边界：不合并、不 Pull、不提交、不推送、不修改工作区/索引/本地分支。"
  note_echo "运行策略：Sourcetree 内无交互连续执行；终端独立运行需按回车确认。"
  gray_echo "日志文件：${LOG_FILE}"
  highlight_echo "============================================================================="

  if [[ "$IS_SOURCETREE_RUNTIME" == "1" ]]; then
    gray_echo "已识别 Sourcetree 自定义动作，跳过回车等待。"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    error_echo "当前不是 Sourcetree，且没有可交互输入；请在终端中重新运行。"
    return 1
  fi
  print ""
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 初始化 zsh 选项、命令路径、日志和输出策略。
initialize_script_runtime() {
  emulate -R zsh
  set -e
  set -o pipefail
  setopt NO_NOMATCH
  export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
  export LANG="${LANG:-zh_CN.UTF-8}"
  export LC_CTYPE="${LC_CTYPE:-UTF-8}"
  : > "$LOG_FILE"
  LOG_READY=1
  configure_output_mode
}
# 从 Sourcetree 参数或当前目录解析 Git 工作仓根目录。
resolve_repo_root() {
  local target="${1:-$PWD}"
  [[ -f "$target" ]] && target="${target:h}"
  if [[ ! -d "$target" ]]; then
    error_echo "目标路径不存在：${target}"
    return 1
  fi
  if ! REPO_ROOT="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)"; then
    error_echo "目标路径不在 Git 工作仓中：${target}"
    return 1
  fi
  success_echo "已识别仓库：${REPO_ROOT}"
}
# 选择要修复和 Fetch 的远端，显式参数优先，其次使用 origin。
resolve_remote_name() {
  local requested_remote="${1:-}"
  local current_branch=""
  local upstream_remote=""
  local -a remotes
  remotes=(${(f)"$(git -C "$REPO_ROOT" remote)"})

  if [[ -n "$requested_remote" ]]; then
    REMOTE_NAME="$requested_remote"
  elif git -C "$REPO_ROOT" remote get-url origin >/dev/null 2>&1; then
    REMOTE_NAME="origin"
  else
    current_branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [[ -n "$current_branch" ]] && upstream_remote="$(git -C "$REPO_ROOT" config --get "branch.${current_branch}.remote" 2>/dev/null || true)"
    if [[ -n "$upstream_remote" && "$upstream_remote" != "." ]]; then
      REMOTE_NAME="$upstream_remote"
    elif [[ "${#remotes[@]}" -eq 1 ]]; then
      REMOTE_NAME="${remotes[1]}"
    else
      error_echo "无法自动确定远端；请在终端作为第二个参数传入远端名。"
      return 1
    fi
  fi

  if ! git -C "$REPO_ROOT" remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
    error_echo "仓库中不存在远端：${REMOTE_NAME}"
    return 1
  fi
  success_echo "已选择远端：${REMOTE_NAME}"
}
# 解析共用 Git 目录及远端跟踪引用的 loose ref/reflog 根目录。
resolve_git_metadata_paths() {
  local common_dir=""
  common_dir="$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null)"
  [[ "$common_dir" == /* ]] || common_dir="${REPO_ROOT}/${common_dir}"
  GIT_COMMON_DIR="${common_dir:A}"
  REMOTE_REFS_ROOT="${GIT_COMMON_DIR}/refs/remotes/${REMOTE_NAME}"
  REMOTE_LOGS_ROOT="${GIT_COMMON_DIR}/logs/refs/remotes/${REMOTE_NAME}"
  gray_echo "Git 元数据目录：${GIT_COMMON_DIR}"
}
# 执行一次 fetch --prune，保留原始输出与退出码供后续诊断。
perform_fetch() {
  local phase="$1"
  info_echo "${phase}：git fetch --prune ${REMOTE_NAME}"
  FETCH_OUTPUT=""
  FETCH_STATUS=0
  if FETCH_OUTPUT="$(LC_ALL=C git --no-optional-locks -C "$REPO_ROOT" -c color.branch=false -c color.diff=false -c color.status=false -c diff.mnemonicprefix=false -c core.quotepath=false fetch --prune "$REMOTE_NAME" 2>&1)"; then
    FETCH_STATUS=0
  else
    FETCH_STATUS=$?
  fi
  log_external_output "$FETCH_OUTPUT"
  return "$FETCH_STATUS"
}
# 判断 Fetch 输出是否命中远端跟踪引用的文件/目录冲突。
is_remote_ref_namespace_conflict() {
  print -r -- "$FETCH_OUTPUT" | /usr/bin/grep -Eq 'refs/remotes/|logs/refs/remotes/' || return 1
  print -r -- "$FETCH_OUTPUT" | /usr/bin/grep -Eqi 'Not a directory|Is a directory|exists; cannot create|cannot create.*directory|there are still logs under'
}
# 读取远端当前真实分支，作为判断本地阻塞项是否失效的依据。
load_remote_branches() {
  local oid=""
  local full_ref=""
  local branch_name=""
  REMOTE_BRANCHES=()
  REMOTE_HEADS_OUTPUT=""

  if ! REMOTE_HEADS_OUTPUT="$(LC_ALL=C git --no-optional-locks -C "$REPO_ROOT" ls-remote --heads --refs "$REMOTE_NAME" 2>&1)"; then
    error_echo "无法读取远端分支，为避免误修复已中止。"
    log_external_output "$REMOTE_HEADS_OUTPUT"
    return 1
  fi

  while IFS=$'\t' read -r oid full_ref; do
    [[ "$full_ref" == refs/heads/* ]] || continue
    branch_name="${full_ref#refs/heads/}"
    [[ -n "$branch_name" ]] && REMOTE_BRANCHES+=("$branch_name")
  done <<< "$REMOTE_HEADS_OUTPUT"

  if [[ "${#REMOTE_BRANCHES[@]}" -eq 0 ]]; then
    error_echo "远端 ${REMOTE_NAME} 没有可用分支，为避免误修复已中止。"
    return 1
  fi
  info_echo "已读取远端分支：${#REMOTE_BRANCHES[@]} 个。"
}
# 从 Git 错误中提取本次真正更新失败的远端跟踪分支。
extract_conflict_branches() {
  local parsed_branches=""
  local branch_name=""
  CONFLICT_BRANCHES=()
  parsed_branches="$(
    JOBS_FETCH_REMOTE_FOR_PARSE="$REMOTE_NAME" /usr/bin/perl -ne '
      my $remote = quotemeta($ENV{"JOBS_FETCH_REMOTE_FOR_PARSE"});
      while (/cannot (?:update (?:the )?ref|lock ref) '\''refs\/remotes\/$remote\/([^'\'']+)'\''/g) {
        print "$1\n";
      }
    ' <<< "$FETCH_OUTPUT" | /usr/bin/sort -u
  )"

  while IFS= read -r branch_name; do
    [[ -n "$branch_name" ]] && CONFLICT_BRANCHES+=("$branch_name")
  done <<< "$parsed_branches"

  if [[ "${#CONFLICT_BRANCHES[@]}" -eq 0 ]]; then
    error_echo "无法从 Fetch 错误中精确提取失败分支，为避免扩大修复范围已中止。"
    return 1
  fi
  info_echo "本次冲突分支：${(j:, :)CONFLICT_BRANCHES}"
}
# 确认错误中的目标分支仍真实存在于远端，避免根据过期输出修改元数据。
validate_conflict_branches_against_remote() {
  local conflict_branch=""
  local remote_branch=""
  local matched=0
  for conflict_branch in "${CONFLICT_BRANCHES[@]}"; do
    matched=0
    for remote_branch in "${REMOTE_BRANCHES[@]}"; do
      if [[ "$remote_branch" == "$conflict_branch" ]]; then
        matched=1
        break
      fi
    done
    if [[ "$matched" -ne 1 ]]; then
      error_echo "冲突分支已不在远端，为避免误修复已中止：${conflict_branch}"
      return 1
    fi
  done
}
# 诊断远端上只有大小写不同、但在 MacOS 默认文件系统会共用路径的分支前缀。
report_case_fold_collisions() {
  local conflict_branch=""
  local remote_branch=""
  local -a segments
  local prefix=""
  local index=0
  for conflict_branch in "${CONFLICT_BRANCHES[@]}"; do
    segments=("${(@s:/:)conflict_branch}")
    [[ "${#segments[@]}" -gt 1 ]] || continue
    prefix="${segments[1]}"
    for ((index = 1; index < ${#segments[@]}; index++)); do
      [[ "$index" -gt 1 ]] && prefix="${prefix}/${segments[$index]}"
      for remote_branch in "${REMOTE_BRANCHES[@]}"; do
        if [[ "$remote_branch" != "$prefix" && "${remote_branch:l}" == "${prefix:l}" ]]; then
          warn_echo "远端存在 MacOS 大小写路径碰撞：${remote_branch} <-> ${conflict_branch}"
          warn_echo "这不是本地代码修改造成的；本次仅备份阻塞 Fetch 的远端引用元数据。"
        fi
      done
    done
  done
}
# 先让 Git 按远端真实状态清理失效的 remote-tracking refs。
prune_stale_remote_refs() {
  local prune_output=""
  local prune_status=0
  info_echo "正在清理已从远端删除的跟踪引用 ..."
  if prune_output="$(LC_ALL=C git --no-optional-locks -C "$REPO_ROOT" remote prune "$REMOTE_NAME" 2>&1)"; then
    prune_status=0
  else
    prune_status=$?
  fi
  log_external_output "$prune_output"
  if [[ "$prune_status" -ne 0 ]]; then
    warn_echo "git remote prune 未完整执行，将继续仅备份已证实的文件/目录阻塞项。"
  fi
}
# 首次需要移动阻塞项时创建本次备份目录。
prepare_backup_root() {
  [[ -n "$BACKUP_ROOT" ]] && return 0
  BACKUP_ROOT="${GIT_COMMON_DIR}/jobs-ref-conflict-backups/$(/bin/date +%Y%m%d-%H%M%S)-$$"
  /bin/mkdir -p "$BACKUP_ROOT"
  note_echo "冲突元数据备份目录：${BACKUP_ROOT}"
}
# 将已验证的阻塞文件或目录移入 Git 元数据备份区。
backup_blocker_path() {
  local source_path="$1"
  local expected_type="$2"
  local type_label="目录"
  local relative_path=""
  local destination=""

  if [[ "$expected_type" == "file" ]]; then
    type_label="文件"
    [[ -f "$source_path" || -L "$source_path" ]] || return 0
    [[ ! -d "$source_path" ]] || return 0
  else
    [[ -d "$source_path" ]] || return 0
  fi

  prepare_backup_root
  relative_path="${source_path#${GIT_COMMON_DIR}/}"
  destination="${BACKUP_ROOT}/${relative_path}"
  /bin/mkdir -p "${destination:h}"
  warn_echo "备份并移开冲突${type_label}：${relative_path}"
  /bin/mv "$source_path" "$destination"
  BLOCKER_COUNT=$((BLOCKER_COUNT + 1))
}
# 根据单个远端分支名扫描会阻止其创建的前缀文件和同名目录。
scan_branch_for_blockers() {
  local branch_name="$1"
  local -a segments
  local prefix=""
  local index=0
  segments=("${(@s:/:)branch_name}")

  if [[ "${#segments[@]}" -gt 1 ]]; then
    prefix="${segments[1]}"
    for ((index = 1; index < ${#segments[@]}; index++)); do
      [[ "$index" -gt 1 ]] && prefix="${prefix}/${segments[$index]}"
      backup_blocker_path "${REMOTE_REFS_ROOT}/${prefix}" "file"
      backup_blocker_path "${REMOTE_LOGS_ROOT}/${prefix}" "file"
    done
  fi

  backup_blocker_path "${REMOTE_REFS_ROOT}/${branch_name}" "directory"
  backup_blocker_path "${REMOTE_LOGS_ROOT}/${branch_name}" "directory"
}
# 仅扫描本次 Fetch 错误明确点名的分支，避免扩大 Git 元数据修复范围。
scan_conflict_branches_for_blockers() {
  local branch_name=""
  BACKUP_ROOT=""
  BLOCKER_COUNT=0
  for branch_name in "${CONFLICT_BRANCHES[@]}"; do
    scan_branch_for_blockers "$branch_name"
  done

  if [[ "$BLOCKER_COUNT" -eq 0 ]]; then
    info_echo "未发现需要手动备份的 loose ref/reflog 阻塞项；将在 prune 后直接重试 Fetch。"
  else
    success_echo "已备份并移开 ${BLOCKER_COUNT} 个引用元数据阻塞项。"
  fi
}
# 遇到已知文件/目录冲突时执行安全修复，然后重试 Fetch。
repair_fetch_if_needed() {
  if perform_fetch "首次尝试"; then
    success_echo "Fetch 已正常完成，不需要修复 Git 元数据。"
    gray_echo "日志文件：${LOG_FILE}"
    return 0
  fi

  if ! is_remote_ref_namespace_conflict; then
    error_echo "Fetch 失败，但不属于本脚本支持的远端引用文件/目录冲突。"
    gray_echo "原始错误已写入日志：${LOG_FILE}"
    return "$FETCH_STATUS"
  fi

  warn_echo "已命中远端跟踪引用文件/目录冲突，开始安全修复。"
  load_remote_branches
  extract_conflict_branches
  validate_conflict_branches_against_remote
  report_case_fold_collisions
  prune_stale_remote_refs
  scan_conflict_branches_for_blockers

  if ! perform_fetch "修复后重试"; then
    error_echo "修复后 Fetch 仍失败；已备份的元数据不会自动删除。"
    [[ -n "$BACKUP_ROOT" ]] && gray_echo "备份目录：${BACKUP_ROOT}"
    gray_echo "日志文件：${LOG_FILE}"
    return "$FETCH_STATUS"
  fi

  success_echo "Fetch 修复完成，远端跟踪引用已刷新。"
  [[ -n "$BACKUP_ROOT" ]] && gray_echo "冲突元数据备份：${BACKUP_ROOT}"
  gray_echo "日志文件：${LOG_FILE}"
}
# 编排脚本自述、环境初始化、仓库识别和 Fetch 修复流程。
main() {
  show_script_intro_and_wait # 首先打印内置自述，并按真实运行入口决定是否等待确认。
  initialize_script_runtime # 确认后初始化 zsh、命令路径、日志和纯文本输出策略。
  resolve_repo_root "${1:-$PWD}" # 从 Sourcetree 的 $REPO 参数或当前目录识别工作仓。
  resolve_remote_name "${2:-}" # 优先使用显式远端参数，否则选择 origin 或唯一可用远端。
  resolve_git_metadata_paths # 解析 worktree 共用 Git 目录和远端引用元数据路径。
  repair_fetch_if_needed # 先正常 Fetch，仅在命中引用文件/目录冲突时备份修复并重试。
}

main "$@"
