#!/bin/zsh
# shell: zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】🫘打开终端运行Pod Install.command
# - 核心用途：从 Sourcetree 当前仓库打开 Terminal.app，并在仓库根目录运行 pod install。
# - 影响范围：pod install 可能下载依赖并更新 Pods、Podfile.lock 或工作区文件。
# - 运行提示：Sourcetree 自定义动作请传入 $REPO；Sourcetree 模式无交互，终端独立运行时确认后继续。

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_PATH="${BASH_SOURCE[0]:-${(%):-%x}}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd -P)"
SCRIPT_BASENAME="$(basename "$SCRIPT_PATH" | sed 's/\.[^.]*$//')"
LOG_DIR="${TMPDIR:-/tmp}"
LOG_FILE="${LOG_DIR%/}/${SCRIPT_BASENAME}.log"
IS_SOURCETREE_RUNTIME=0
TARGET_DIRECTORY=""

# 把终端信息同步写入日志文件。
log() {
  printf "%s\n" "$1" | tee -a "$LOG_FILE"
}
# 输出普通信息。
info_echo() {
  log "ℹ $1"
}
# 输出成功信息。
success_echo() {
  log "✔ $1"
}
# 输出警告信息。
warn_echo() {
  log "⚠ $1"
}
# 输出错误信息。
error_echo() {
  log "✖ $1"
}
# 识别脚本是否由 Sourcetree 自定义动作发起。
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
# 展示脚本用途，并在普通终端模式下等待确认。
show_script_intro_and_wait() {
  is_sourcetree_runtime && IS_SOURCETREE_RUNTIME=1
  log "============================== 脚本自述 =============================="
  info_echo "核心用途：从当前项目打开 Terminal.app，并运行 pod install。"
  warn_echo "影响范围：可能下载依赖，并更新 Pods、Podfile.lock 或工作区文件。"
  info_echo "日志文件：${LOG_FILE}"
  log "======================================================================="

  [[ "$IS_SOURCETREE_RUNTIME" == "1" ]] && return 0
  [[ -t 0 ]] || { error_echo "当前不是 Sourcetree 环境，也没有可交互终端。"; return 1; }
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 初始化 zsh 运行环境和日志文件。
initialize_script_runtime() {
  setopt NO_NOMATCH ERR_EXIT PIPE_FAIL
  touch "$LOG_FILE"
}
# 检查打开 Terminal.app 所需的系统命令。
check_environment() {
  command -v osascript >/dev/null 2>&1 || { error_echo "未找到 osascript。"; return 1; }
}
# 把文件或目录参数解析为项目目录。
resolve_target_directory() {
  local target="${1:-${SOURCETREE_REPO_PATH:-${PWD}}}"
  target="${target%$'\r'}"
  target="${target#\"}"
  target="${target%\"}"
  target="${target#\'}"
  target="${target%\'}"

  [[ -f "$target" ]] && target="${target:h}"
  [[ -d "$target" ]] || { error_echo "项目目录不存在：${target}"; return 1; }
  TARGET_DIRECTORY="$(cd "$target" && pwd -P)"
}
# 打开 Terminal.app，并在目标目录执行可见的 pod install 命令。
open_terminal_and_run_pod_install() {
  info_echo "准备在终端运行：cd ${TARGET_DIRECTORY} && pod install"
  if ! osascript - "$TARGET_DIRECTORY" >> "$LOG_FILE" 2>&1 <<'APPLESCRIPT'
on run argv
  set targetPath to item 1 of argv
  set shellCommand to "cd " & quoted form of targetPath & " && clear && printf '\\n🫘 当前项目：%s\\n🚀 开始执行：pod install\\n\\n' " & quoted form of targetPath & " && pod install"
  tell application "Terminal"
    activate
    do script shellCommand
  end tell
end run
APPLESCRIPT
  then
    error_echo "Terminal.app 启动失败，AppleScript 详细错误请查看：${LOG_FILE}"
    return 1
  fi
  success_echo "已打开 Terminal.app，并提交 pod install 命令。"
}
# 输出启动结果和排查位置。
print_result() {
  success_echo "项目目录：${TARGET_DIRECTORY}"
  info_echo "pod install 的实时输出请查看新打开的终端窗口。"
  info_echo "启动日志：${LOG_FILE}"
}
# 编排脚本说明、路径解析和终端启动流程。
main() {
  show_script_intro_and_wait # 展示内置自述，并按运行入口决定是否等待确认。
  initialize_script_runtime # 初始化 zsh 选项并清空本次启动日志。
  check_environment # 检查 Terminal.app 启动依赖。
  resolve_target_directory "$@" # 从 Sourcetree 参数或当前目录解析项目根目录。
  open_terminal_and_run_pod_install # 打开终端并执行 pod install。
  print_result # 输出项目路径和日志位置。
}

main "$@"
