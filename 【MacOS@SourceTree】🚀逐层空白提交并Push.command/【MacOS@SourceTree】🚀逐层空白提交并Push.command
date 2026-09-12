#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】🚀逐层空白提交并Push.command
# - 核心用途：从当前 Git 仓库开始，将全部改动以空白提交说明提交并推送，再逐层处理父 Git 仓库。
# - 影响范围：每层执行 git add -A、必要时创建空白说明提交，并推送当前分支。
# - 运行提示：Sourcetree 模式无交互连续执行；终端独立运行需先按回车确认。

RAW_SCRIPT_PATH="${BASH_SOURCE[0]:-${(%):-%x}}"
SCRIPT_PATH="${RAW_SCRIPT_PATH:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"
SCRIPT_FILENAME="${SCRIPT_PATH:t}"
SCRIPT_BASENAME="${SCRIPT_FILENAME:r}"
LOG_ROOT="${TMPDIR:-/tmp}"
LOG_FILE="${LOG_ROOT%/}/${SCRIPT_BASENAME}.log"
PLAIN_OUTPUT=0
IS_SOURCETREE_RUNTIME=0
START_REPOSITORY=""
PROCESSED_COUNT=0
COMMITTED_COUNT=0
PUSHED_COUNT=0
COLOR_BLUE=""
COLOR_GREEN=""
COLOR_YELLOW=""
COLOR_RED=""
COLOR_CYAN=""
COLOR_RESET=""
typeset -ga REPOSITORY_CHAIN=()

# 识别脚本是否由 Sourcetree 自定义动作发起。
is_sourcetree_runtime() {
  env | grep -Eqi '^SOURCETREE|^SOURCE_TREE' && return 0

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
# 输出脚本内置自述，并按运行入口决定是否等待确认。
show_script_intro_and_wait() {
  resolve_script_path
  configure_output_mode
  if [[ "$IS_SOURCETREE_RUNTIME" != "1" && -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" ]]; then
    clear
  fi

  print -r -- "============================== 脚本内置自述 =============================="
  print -r -- "脚本名称：${SCRIPT_FILENAME}"
  print -r -- "核心用途：从当前仓库开始，将全部改动以空白说明提交并 push，再逐层处理父 Git 仓库。"
  print -r -- "影响范围：每层会执行 git add -A；无改动时不制造空提交，但仍尝试推送已有提交。"
  print -r -- "停止边界：任一层冲突、游离 HEAD、缺少推送远端或 push 失败时，不再处理上层。"
  print -r -- "运行策略：Sourcetree 内无交互连续执行；终端独立运行需回车确认，按 Ctrl+C 取消。"
  print -r -- "日志文件：${LOG_FILE}"
  print -r -- "============================================================================"
  print ""

  if [[ "$IS_SOURCETREE_RUNTIME" == "1" ]]; then
    print -r -- "已识别为 Sourcetree 自定义动作，将跳过交互并连续执行。"
    return 0
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
  : > "$LOG_FILE"
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
# 检查 Git 和脚本依赖的 macOS 基础命令。
check_environment() {
  local command_name=""
  for command_name in git perl ps tr tee; do
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
# 从内层到外层建立唯一的 Git 仓库处理链。
build_repository_chain() {
  local current_repository="$START_REPOSITORY"
  local parent_repository=""
  local existing_repository=""
  local duplicated=0
  local index=1

  REPOSITORY_CHAIN=()
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

  highlight_echo "已识别 ${#REPOSITORY_CHAIN[@]} 层 Git 仓库，将从内到外处理："
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
# 在任何写入前检查单层仓库的分支、冲突和推送目标。
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
  if [[ -n "$(git -C "$repository" diff --name-only --diff-filter=U 2>/dev/null)" ]]; then
    error_echo "存在未解决冲突，已停止：${repository}"
    return 1
  fi

  git_directory="$(git -C "$repository" rev-parse --absolute-git-dir 2>/dev/null || true)"
  for operation_marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply; do
    if [[ -e "${git_directory}/${operation_marker}" ]]; then
      error_echo "检测到未完成的 Git 操作 ${operation_marker}，已停止：${repository}"
      return 1
    fi
  done

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
  info_echo "正在暂存全部改动：${repository}"
  if ! run_git "$repository" add -A; then
    error_echo "git add -A 失败：${repository}"
    return 1
  fi
  if git -C "$repository" diff --cached --quiet --exit-code; then
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
# 推送单层仓库当前分支，必要时建立 upstream。
push_repository() {
  local repository="$1"
  local branch_name=""
  local upstream=""
  local fallback_remote=""

  branch_name="$(git -C "$repository" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  upstream="$(git -C "$repository" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  info_echo "正在推送：${repository}"
  if [[ -n "$upstream" ]]; then
    if ! run_git "$repository" push; then
      error_echo "git push 失败，已停止处理上层：${repository}"
      return 1
    fi
  else
    fallback_remote="$(resolve_fallback_remote "$repository" 2>/dev/null || true)"
    if ! run_git "$repository" push --set-upstream "$fallback_remote" "$branch_name"; then
      error_echo "首次 git push 失败，已停止处理上层：${repository}"
      return 1
    fi
  fi
  PUSHED_COUNT=$((PUSHED_COUNT + 1))
  success_echo "已完成推送：${repository}"
}
# 严格按内到外顺序提交并推送整条仓库链。
process_repository_chain() {
  local repository=""
  local level=1
  for repository in "${REPOSITORY_CHAIN[@]}"; do
    highlight_echo "==================== 处理第 ${level}/${#REPOSITORY_CHAIN[@]} 层 ===================="
    info_echo "仓库：${repository}"
    commit_repository_changes "$repository" || return 1
    push_repository "$repository" || return 1
    PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
    level=$((level + 1))
  done
}
# 输出整条仓库链的成功统计和日志位置。
show_completion_summary() {
  highlight_echo "============================== 处理完成 =============================="
  success_echo "已由内到外处理 ${PROCESSED_COUNT} 层 Git 仓库。"
  success_echo "新建空白说明提交：${COMMITTED_COUNT} 个；成功执行 push：${PUSHED_COUNT} 层。"
  info_echo "日志文件：${LOG_FILE}"
  highlight_echo "======================================================================="
}
# 编排自述、环境检查、父仓发现、预检与逐层推送。
main() {
  show_script_intro_and_wait # 首先展示脚本影响，并按真实运行入口决定是否等待确认。
  initialize_script_runtime # 在确认后启用 zsh 选项并初始化本次日志。
  check_environment # 验证 Git 与基础命令真实可用。
  resolve_start_repository "$@" # 从 Sourcetree 参数或当前目录解析起始 Git 仓库。
  build_repository_chain # 建立从当前仓库到最外层父仓的处理链。
  preflight_repository_chain # 在写入前统一检查所有层的安全条件与推送目标。
  process_repository_chain # 对每层执行全量暂存、空白说明提交和推送。
  show_completion_summary # 汇总已处理层数、提交数和推送结果。
}

main "$@"
