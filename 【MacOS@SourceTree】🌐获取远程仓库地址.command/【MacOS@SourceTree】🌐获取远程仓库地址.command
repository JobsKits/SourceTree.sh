#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】🌐获取远程仓库地址.command
# - 核心用途：解析目标 Git 仓库，获取首选远程仓库地址并复制到 macOS 剪贴板。
# - 影响范围：不联网，不修改 Git 状态或业务文件；仅写入脚本日志和当前 macOS 剪贴板。
# - 运行提示：Sourcetree 自定义动作请把参数设置为 $REPO；Sourcetree 模式无交互连续执行，终端模式确认后继续。

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
# shell: zsh

# 解析脚本真实路径，兼容 Sourcetree 只传脚本名的运行环境。
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
    (cd "$(dirname "$candidate")" 2>/dev/null && printf "%s/%s\n" "$(pwd -P)" "$(basename "$candidate")")
    return 0
  done

  printf "%s/%s\n" "$PWD" "$script_name"
}

SCRIPT_PATH=""
SCRIPT_DIR=""
SCRIPT_BASENAME=""
LOG_DIR="${TMPDIR:-/tmp}"
LOG_DIR="${LOG_DIR%/}"
LOG_FILE=""
IS_SOURCETREE_RUNTIME=0
PLAIN_OUTPUT=0
LOG_READY=0
TARGET_INPUT=""
TARGET_INPUT_SOURCE=""
REPOSITORY_ROOT=""
REMOTE_NAME=""
REMOTE_URL=""
REMOTE_URL_DISPLAY=""

# 识别脚本是否由 Sourcetree 自定义动作实际发起。
is_sourcetree_runtime() {
  env | grep -Ei '^SOURCETREE|^SOURCE_TREE' >/dev/null && return 0

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
# 日志按原文输出；确认前只展示，确认后同步写入日志。
log() {
  local message="$1"
  if [[ "$LOG_READY" != "1" ]]; then
    if [[ "$PLAIN_OUTPUT" == "1" ]]; then
      printf '%s\n' "$message" | strip_ansi_text
    else
      printf '%s\n' "$message"
    fi
    return 0
  fi
  if [[ "$PLAIN_OUTPUT" == "1" ]]; then
    printf '%s\n' "$message" | strip_ansi_text | /usr/bin/tee -a "$LOG_FILE"
  else
    printf '%s\n' "$message" | /usr/bin/tee -a "$LOG_FILE"
  fi
}
# 固定颜色码单独处理，用户路径与正文不做反斜杠转义。
color_log() {
  local color="$1" message="$2"
  if [[ "$PLAIN_OUTPUT" == "1" ]]; then
    log "$message"
  else
    log "${color}${message}"$'\033[0m'
  fi
}
# 输出成功日志。
success_echo() { color_log $'\033[1;32m' "✔ $1"; }
# 输出警告日志。
warn_echo() { color_log $'\033[1;33m' "⚠ $1"; }
# 输出说明日志。
note_echo() { color_log $'\033[1;35m' "➤ $1"; }
# 输出错误日志。
error_echo() { color_log $'\033[1;31m' "✖ $1"; }
# 输出次要日志。
gray_echo() { color_log $'\033[0;90m' "$1"; }
# 输出高亮分隔日志。
highlight_echo() { color_log $'\033[1;36m' "🔹 $1"; }
# 输出错误并立即终止脚本。
exit_with_error() {
  error_echo "$1"
  exit 1
}
# 自述前只计算路径和展示模式，不写入日志或项目文件。
prepare_intro_output() {
  SCRIPT_PATH="$(resolve_script_path)"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${${SCRIPT_PATH:t}:r}"
  LOG_FILE="${LOG_DIR}/${SCRIPT_BASENAME}.log"
  if is_sourcetree_runtime; then
    IS_SOURCETREE_RUNTIME=1
  fi
  if [[ "$IS_SOURCETREE_RUNTIME" == "1" || ! -t 1 || -z "${TERM:-}" || "${TERM:-}" == "dumb" || -n "${NO_COLOR+x}" ]]; then
    PLAIN_OUTPUT=1
    export NO_COLOR="${NO_COLOR:-1}"
    export FORCE_COLOR=0
    export CLICOLOR="0"
    export ANSI_COLORS_DISABLED="1"
    export npm_config_color=false
  fi
}
# 展示内置自述，终端模式等待确认，Sourcetree 模式直接继续。
show_script_intro_and_wait() {
  prepare_intro_output
  if [[ -z "${NO_COLOR+x}" && "${PLAIN_OUTPUT:-0}" != 1 && "$IS_SOURCETREE_RUNTIME" != "1" && -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 ==============================" | jobs_intro_style title
  note_echo "脚本名称：${SCRIPT_BASENAME}.command" | jobs_intro_style title
  note_echo "脚本路径：${SCRIPT_PATH}" | jobs_intro_style body
  note_echo "核心用途：获取目标 Git 仓库的首选远程地址，并复制到 macOS 剪贴板。" | jobs_intro_style body
  note_echo "选择规则：优先 origin；没有 origin 且仅有一个远程时自动使用该远程。" | jobs_intro_style body
  note_echo "参数建议：Sourcetree 自定义动作参数填写 \$REPO；终端可传入仓库路径和可选远程名。" | jobs_intro_style body
  note_echo "安全边界：不联网、不提交、不推送、不修改 Git 配置、索引或业务文件。" | jobs_intro_style body
  note_echo "运行策略：Sourcetree 内无交互连续执行；终端独立运行需回车确认。" | jobs_intro_style body
  gray_echo "日志文件：${LOG_FILE}" | jobs_intro_style body
  highlight_echo "=============================================================================" | jobs_intro_style title

  if [[ "$IS_SOURCETREE_RUNTIME" == "1" ]]; then
    gray_echo "已识别 Sourcetree 自定义动作，跳过回车等待。" | jobs_intro_style body
    return 0
  fi
  if [[ ! -t 0 ]]; then
    exit_with_error "当前不是 Sourcetree，且没有可交互输入；请在终端中重新运行。"
  fi

  echo "" | jobs_intro_style body
  read -r "?👉 已阅读说明，按回车继续执行；按 Ctrl+C 取消：" _ || exit_with_error "读取确认失败，已取消执行。"
}
# 用户确认后初始化 Shell 环境和本次日志。
initialize_script_runtime() {
  emulate -R zsh
  setopt NO_NOMATCH ERR_EXIT PIPE_FAIL
  export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
  export LANG="${LANG:-zh_CN.UTF-8}"
  export LC_CTYPE="${LC_CTYPE:-UTF-8}"
  if ! : > "$LOG_FILE"; then
    print -u2 -r -- "无法创建日志文件：${LOG_FILE}；请检查系统临时目录。"
    exit 1
  fi
  LOG_READY=1
}
# 检查获取远程仓库地址需要的基础命令。
check_environment() {
  command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1 || exit_with_error "Git 无法执行；请检查 Git、CLT 或当前 PATH。"
}
# 去掉用户拖入路径时可能带上的外层引号和换行。
strip_outer_quotes() {
  local value="$1"
  value="${value%$'\r'}"
  value="${value%$'\n'}"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  print -r -- "$value"
}
# 展开用户输入路径里的当前用户家目录缩写。
expand_user_path() {
  local input_path="$1"
  if [[ "$input_path" == "~" ]]; then
    print -r -- "$HOME"
    return 0
  fi
  if [[ "$input_path" == '~/'* ]]; then
    print -r -- "${HOME}/${input_path#'~/'}"
    return 0
  fi
  print -r -- "$input_path"
}
# 从终端读取目标 Git 仓库路径，直接回车时使用当前工作目录。
prompt_repository_path() {
  local input_path=""
  echo ""
  note_echo "请拖入或输入目标 Git 仓库路径。"
  gray_echo "直接回车：使用当前工作目录 ${PWD}"
  IFS= read -r "input_path?👉 仓库路径：" input_path || exit_with_error "读取仓库路径失败，已取消执行。"

  input_path="$(strip_outer_quotes "$input_path")"
  if [[ -z "$input_path" ]]; then
    TARGET_INPUT="$PWD"
    TARGET_INPUT_SOURCE="终端当前目录"
    return 0
  fi

  TARGET_INPUT="$input_path"
  TARGET_INPUT_SOURCE="终端手动输入"
}
# 解析 Sourcetree 参数、环境变量或终端输入得到目标仓库路径。
resolve_target_input() {
  if [[ $# -gt 0 && -n "${1:-}" ]]; then
    TARGET_INPUT="$1"
    TARGET_INPUT_SOURCE="Sourcetree 参数 / 命令行参数"
    return 0
  fi
  if [[ -n "${REPO:-}" ]]; then
    TARGET_INPUT="$REPO"
    TARGET_INPUT_SOURCE="环境变量 REPO"
    return 0
  fi
  if [[ "$IS_SOURCETREE_RUNTIME" == "1" ]]; then
    exit_with_error "未收到仓库路径参数。请在 Sourcetree 自定义动作的参数栏填写 \$REPO。"
  fi
  if [[ -t 0 ]]; then
    prompt_repository_path
    return 0
  fi

  exit_with_error "未收到仓库路径参数，且当前没有可交互输入。"
}
# 把输入路径规整为存在的物理目录路径。
normalize_existing_directory() {
  local input_path="$1"
  local expanded_path=""
  local candidate_path=""

  input_path="$(strip_outer_quotes "$input_path")"
  expanded_path="$(expand_user_path "$input_path")"
  [[ -n "$expanded_path" ]] || return 1

  if [[ "$expanded_path" == /* ]]; then
    candidate_path="$expanded_path"
  else
    candidate_path="${PWD}/${expanded_path}"
  fi
  [[ -e "$candidate_path" ]] || return 1
  [[ -d "$candidate_path" ]] || candidate_path="${candidate_path:h}"
  (cd -P "$candidate_path" 2>/dev/null && pwd -P)
}
# 解析目标所在 Git 工作树的根目录。
resolve_repository_root() {
  local target_directory=""
  local repository_root=""

  resolve_target_input "$@"
  target_directory="$(normalize_existing_directory "$TARGET_INPUT" 2>/dev/null || true)"
  [[ -n "$target_directory" ]] || exit_with_error "目标路径不存在或无法访问：${TARGET_INPUT}"
  repository_root="$(git -C "$target_directory" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$repository_root" ]] || exit_with_error "目标不在 Git 工作树中：${target_directory}"
  REPOSITORY_ROOT="$(cd -P "$repository_root" 2>/dev/null && pwd -P)"
}
# 输出当前仓库已经配置的远程名称，供错误提示使用。
print_available_remotes() {
  local remote=""
  warn_echo "当前可用远程："
  while IFS= read -r remote; do
    [[ -n "$remote" ]] && gray_echo "- ${remote}"
  done < <(git -C "$REPOSITORY_ROOT" remote)
}
# 按显式参数、origin 和唯一远程的顺序确定远程名称。
resolve_remote_name() {
  local requested_remote="${2:-${REMOTE_NAME_OVERRIDE:-}}"
  local -a remotes=()
  local remote=""

  while IFS= read -r remote; do
    [[ -n "$remote" ]] && remotes+=("$remote")
  done < <(git -C "$REPOSITORY_ROOT" remote)
  (( ${#remotes[@]} > 0 )) || exit_with_error "当前 Git 仓库没有配置任何远程：${REPOSITORY_ROOT}"

  if [[ -n "$requested_remote" ]]; then
    if (( ${remotes[(Ie)$requested_remote]} == 0 )); then
      print_available_remotes
      exit_with_error "指定远程不存在：${requested_remote}"
    fi
    REMOTE_NAME="$requested_remote"
    return 0
  fi
  if (( ${remotes[(Ie)origin]} > 0 )); then
    REMOTE_NAME="origin"
    return 0
  fi
  if (( ${#remotes[@]} == 1 )); then
    REMOTE_NAME="${remotes[1]}"
    return 0
  fi

  print_available_remotes
  exit_with_error "未找到 origin，且仓库包含多个远程。终端运行时可把远程名作为第二个参数传入。"
}
# 读取选定远程的首个抓取地址。
resolve_remote_url() {
  local remote_url=""

  remote_url="$(git -C "$REPOSITORY_ROOT" remote get-url "$REMOTE_NAME" 2>/dev/null || true)"
  [[ -n "$remote_url" ]] || exit_with_error "无法读取远程地址：${REMOTE_NAME}"
  REMOTE_URL="$remote_url"
}
# 对输出和日志里的 HTTP 用户信息脱敏，剪贴板仍保留 Git 配置原值。
sanitize_remote_url_for_display() {
  if [[ "$REMOTE_URL" == http://*'@'* || "$REMOTE_URL" == https://*'@'* ]]; then
    REMOTE_URL_DISPLAY="${REMOTE_URL%%://*}://***@${REMOTE_URL##*@}"
    warn_echo "远程地址包含 HTTP 用户信息；输出和日志已脱敏，剪贴板保留原始地址。"
    return 0
  fi
  REMOTE_URL_DISPLAY="$REMOTE_URL"
}
# 将远程仓库原始地址复制到 macOS 剪贴板。
copy_remote_url_to_clipboard() {
  if command -v pbcopy >/dev/null 2>&1; then
    if print -r -- "$REMOTE_URL" | pbcopy; then
      success_echo "已复制到剪贴板。"
      return 0
    fi
    warn_echo "pbcopy 执行失败，已跳过剪贴板复制。"
    return 0
  fi

  warn_echo "未找到 pbcopy，已跳过剪贴板复制。"
}
# 输出仓库位置、远程名称、远程地址和日志位置。
print_remote_summary() {
  highlight_echo "============================== 远程仓库地址 =============================="
  note_echo "目标来源：${TARGET_INPUT_SOURCE}"
  note_echo "仓库根目录：${REPOSITORY_ROOT}"
  note_echo "远程名称：${REMOTE_NAME}"
  success_echo "远程仓库地址："
  print -r -- "$REMOTE_URL_DISPLAY" | tee -a "$LOG_FILE"
  gray_echo "日志文件：${LOG_FILE}"
  highlight_echo "==========================================================================="
}
# 编排脚本说明、仓库解析、远程选择、剪贴板复制和结果输出。
main() {
  show_script_intro_and_wait # 展示脚本内置自述，并按运行入口决定是否等待确认。
  initialize_script_runtime # 确认后初始化 zsh、命令环境和本次日志。
  check_environment # 检查 git 命令是否可用。
  resolve_repository_root "$@" # 从参数、环境变量或终端输入解析 Git 仓库根目录。
  resolve_remote_name "$@" # 优先选择显式远程、origin 或唯一远程。
  resolve_remote_url # 读取选定远程的首个抓取地址。
  sanitize_remote_url_for_display # 对日志输出中的 HTTP 用户信息做脱敏处理。
  copy_remote_url_to_clipboard # 将远程仓库原始地址复制到 macOS 剪贴板。
  print_remote_summary # 输出仓库根目录、远程名称、远程地址和日志位置。
}

main "$@"
