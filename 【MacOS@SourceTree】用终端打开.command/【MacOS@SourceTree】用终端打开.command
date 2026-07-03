#!/bin/zsh
# shell: zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】用终端打开.command
# - 核心用途：从 Sourcetree 参数、环境变量或终端输入解析目标目录，并让 macOS 终端进入该目录。
# - 影响范围：不修改 Git 状态，不改写业务文件；只启动 Terminal.app 并写入脚本日志。
# - 运行提示：Sourcetree 自定义动作请把参数设置为 $REPO；Sourcetree 模式无交互连续执行，终端模式确认后继续。

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export LANG="${LANG:-zh_CN.UTF-8}"
export LC_CTYPE="${LC_CTYPE:-UTF-8}"

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

SCRIPT_PATH="$(resolve_script_path)"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd -P)"
SCRIPT_BASENAME="$(basename "$SCRIPT_PATH" | sed 's/\.[^.]*$//')"
LOG_DIR="${TMPDIR:-/tmp}"
LOG_DIR="${LOG_DIR%/}"
LOG_FILE="${LOG_DIR}/${SCRIPT_BASENAME}.log"
IS_SOURCETREE_RUNTIME=0
PLAIN_OUTPUT=0
TARGET_INPUT=""
TARGET_INPUT_SOURCE=""
TARGET_DIRECTORY=""

# 识别脚本是否由 Sourcetree 自定义动作实际发起。
is_sourcetree_runtime() {
  env | grep -Eqi '^SOURCETREE|^SOURCE_TREE' && return 0

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
    printf "%b\n" "$1" | strip_ansi_text | tee -a "$LOG_FILE"
  else
    printf "%b\n" "$1" | tee -a "$LOG_FILE"
  fi
}
# 输出蓝色提示类信息。
info_echo() {
  log "\033[1;34mINFO $1\033[0m"
}
# 输出绿色成功信息。
success_echo() {
  log "\033[1;32mOK $1\033[0m"
}
# 输出黄色警告信息。
warn_echo() {
  log "\033[1;33mWARN $1\033[0m"
}
# 输出紫色说明信息。
note_echo() {
  log "\033[1;35mNOTE $1\033[0m"
}
# 输出红色错误信息。
error_echo() {
  log "\033[1;31mERROR $1\033[0m"
}
# 输出灰色次要信息。
gray_echo() {
  log "\033[0;90m$1\033[0m"
}
# 输出高亮分隔信息。
highlight_echo() {
  log "\033[1;36m$1\033[0m"
}
# 输出错误并立即终止脚本。
exit_with_error() {
  error_echo "$1"
  exit 1
}
# 准备 Sourcetree 输出模式和本次日志文件。
prepare_intro_output() {
  : > "$LOG_FILE"
  if is_sourcetree_runtime; then
    IS_SOURCETREE_RUNTIME=1
  fi
  if [[ "$IS_SOURCETREE_RUNTIME" == "1" || ! -t 1 || -z "${TERM:-}" || "${TERM:-}" == "dumb" || -n "${NO_COLOR:-}" ]]; then
    PLAIN_OUTPUT=1
    export NO_COLOR="${NO_COLOR:-1}"
    export CLICOLOR="0"
    export ANSI_COLORS_DISABLED="1"
  fi
}
# 展示内置自述，终端模式等待确认，Sourcetree 模式直接继续。
show_script_intro_and_wait() {
  prepare_intro_output
  if [[ "$IS_SOURCETREE_RUNTIME" != "1" && -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 =============================="
  note_echo "脚本名称：${SCRIPT_BASENAME}.command"
  note_echo "脚本路径：${SCRIPT_PATH}"
  note_echo "核心用途：解析 Sourcetree 传入目标，打开 macOS 终端，并让新窗口命令行进入该目录。"
  note_echo "参数建议：Sourcetree 自定义动作参数填写 \$REPO；也支持命令行直接传入文件或目录路径。"
  note_echo "文件策略：如果传入的是文件，脚本会打开文件所在目录。"
  note_echo "安全边界：不提交、不推送、不删除、不修改 Git 索引或业务文件。"
  note_echo "运行策略：Sourcetree 内无交互连续执行；终端独立运行需回车确认。"
  gray_echo "日志文件：${LOG_FILE}"
  highlight_echo "============================================================================="

  if [[ "$IS_SOURCETREE_RUNTIME" == "1" ]]; then
    gray_echo "已识别 Sourcetree 自定义动作，跳过回车等待。"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    exit_with_error "当前不是 Sourcetree，且没有可交互输入；请在终端中重新运行。"
  fi

  echo ""
  read -r "?已阅读说明，按回车继续执行；按 Ctrl+C 取消：" _ || exit_with_error "读取确认失败，已取消执行。"
}
# 初始化 zsh 选项，确保后续路径处理行为稳定。
initialize_script_runtime() {
  emulate -R zsh
  set -e
  set -o pipefail
  setopt NO_NOMATCH
}
# 检查让终端进入目标目录所需的系统命令。
check_environment() {
  command -v osascript >/dev/null 2>&1 || exit_with_error "未找到 osascript 命令，无法让 Terminal.app 进入目标目录。"
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
  if [[ "$input_path" == "~/"* ]]; then
    print -r -- "${HOME}/${input_path#~/}"
    return 0
  fi
  print -r -- "$input_path"
}
# 从终端读取目标路径，直接回车时使用当前工作目录。
prompt_target_path() {
  local input_path=""
  echo ""
  note_echo "请拖入或输入要用终端打开的文件 / 目录。"
  gray_echo "直接回车：使用当前工作目录 ${PWD}"
  IFS= read -r "input_path?目标路径：" input_path || exit_with_error "读取目标路径失败，已取消执行。"

  input_path="$(strip_outer_quotes "$input_path")"
  if [[ -z "$input_path" ]]; then
    TARGET_INPUT="$PWD"
    TARGET_INPUT_SOURCE="终端当前目录"
    return 0
  fi

  TARGET_INPUT="$input_path"
  TARGET_INPUT_SOURCE="终端手动输入"
}
# 解析 Sourcetree 参数、环境变量或终端输入得到原始目标路径。
resolve_target_input() {
  if [[ $# -gt 0 ]]; then
    TARGET_INPUT="$*"
    TARGET_INPUT_SOURCE="Sourcetree 参数 / 命令行参数"
    return 0
  fi
  if [[ -n "${REPO:-}" ]]; then
    TARGET_INPUT="$REPO"
    TARGET_INPUT_SOURCE="环境变量 REPO"
    return 0
  fi
  if [[ "$IS_SOURCETREE_RUNTIME" == "1" ]]; then
    exit_with_error "未收到目标路径参数。请在 Sourcetree 自定义动作的参数栏填写 \$REPO。"
  fi
  if [[ -t 0 ]]; then
    prompt_target_path
    return 0
  fi

  exit_with_error "未收到目标路径参数，且当前没有可交互输入。"
}
# 把输入路径规整为可打开的物理目录路径。
normalize_target_directory() {
  local input_path="$1"
  local expanded_path=""
  local candidate_path=""
  local target_dir=""

  input_path="$(strip_outer_quotes "$input_path")"
  expanded_path="$(expand_user_path "$input_path")"
  [[ -n "$expanded_path" ]] || return 1

  if [[ "$expanded_path" == /* ]]; then
    candidate_path="$expanded_path"
  else
    candidate_path="${PWD}/${expanded_path}"
  fi

  if [[ -d "$candidate_path" ]]; then
    (cd -P "$candidate_path" 2>/dev/null && pwd -P)
    return 0
  fi
  if [[ -f "$candidate_path" ]]; then
    target_dir="${candidate_path:h}"
    (cd -P "$target_dir" 2>/dev/null && pwd -P)
    return 0
  fi

  return 1
}
# 解析并保存本次要打开的目录。
resolve_target_directory() {
  local resolved_path=""

  resolve_target_input "$@"
  resolved_path="$(normalize_target_directory "$TARGET_INPUT" 2>/dev/null || true)"
  [[ -n "$resolved_path" ]] || exit_with_error "无法解析可打开目录：${TARGET_INPUT}"
  TARGET_DIRECTORY="$resolved_path"
}
# 使用 AppleScript 打开终端，并把新窗口的命令行切到目标目录。
open_terminal_and_cd_target_directory() {
  osascript - "$TARGET_DIRECTORY" <<'APPLESCRIPT'
on run argv
  set targetPath to item 1 of argv
  tell application "Terminal"
    activate
    do script "cd " & quoted form of targetPath
  end tell
end run
APPLESCRIPT
}
# 使用 macOS 终端打开目标目录，并确保命令行停在该目录。
open_target_directory_in_terminal() {
  info_echo "准备打开终端并进入目录：${TARGET_DIRECTORY}"
  if open_terminal_and_cd_target_directory >> "$LOG_FILE" 2>&1; then
    success_echo "已打开 Terminal.app，命令行已进入目标目录。"
    return 0
  fi

  exit_with_error "无法让 Terminal.app 进入目标目录，请确认终端和自动化权限可正常使用。"
}
# 输出目标目录、来源和日志位置。
print_target_summary() {
  highlight_echo "============================== 终端打开结果 =============================="
  note_echo "目标来源：${TARGET_INPUT_SOURCE}"
  note_echo "原始目标：${TARGET_INPUT}"
  success_echo "终端当前目录：${TARGET_DIRECTORY}"
  gray_echo "日志文件：${LOG_FILE}"
  highlight_echo "==========================================================================="
}
# 编排脚本说明、环境检查、目标解析和终端打开流程。
main() {
  show_script_intro_and_wait # 展示脚本内置自述，并按运行入口决定是否等待确认。
  initialize_script_runtime # 初始化 zsh 运行选项，确保后续路径处理行为稳定。
  check_environment # 检查让终端进入目标目录所需的系统命令是否可用。
  resolve_target_directory "$@" # 从参数、环境变量或终端输入解析要打开的目录。
  open_target_directory_in_terminal # 打开 macOS 终端，并让命令行进入解析后的目标目录。
  print_target_summary # 输出目标来源、终端当前目录和日志位置。
}

main "$@"
