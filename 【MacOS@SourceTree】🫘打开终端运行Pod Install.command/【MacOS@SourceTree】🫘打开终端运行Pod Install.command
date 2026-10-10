#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】🫘打开终端运行Pod Install.command
# - 核心用途：从 Sourcetree 打开终端，转交同库 Pod Install 入口执行。
# - 影响范围：启动 Terminal；子入口回车确认后安装依赖，可能更新 Pods、锁文件和工作区。
# - 运行提示：Sourcetree 无交互；终端先展示自述并按回车确认，Ctrl+C 取消。
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

SCRIPT_SOURCE="$0"
SCRIPT_PATH=""
SCRIPT_DIR=""
SCRIPT_BASENAME=""
LOG_FILE=""
LOG_READY=0
IS_SOURCETREE_RUNTIME=0
PLAIN_OUTPUT=0
# 仅根据显式环境或父进程链识别 Sourcetree，普通相对路径调用仍需确认。
is_sourcetree_runtime() {
  env | grep -Eqi '^(SOURCETREE|SOURCE_TREE)[^=]*=' && return 0
  local process_id="$PPID" process_name="" depth=0
  while [[ "$process_id" == <-> && "$process_id" -gt 1 && "$depth" -lt 8 ]]; do
    process_name="$(ps -o comm= -p "$process_id" 2>/dev/null || true)"
    [[ "$process_name" == *SourceTree* || "$process_name" == *Sourcetree* ]] && return 0
    process_id="$(ps -o ppid= -p "$process_id" 2>/dev/null | tr -d ' ' || true)"
    depth=$((depth + 1))
  done
  return 1
}
# 准备展示所需路径和纯文本策略，不写入文件或修改项目。
prepare_display_context() {
  local candidate="" script_name="${SCRIPT_SOURCE:t}"
  for candidate in "$SCRIPT_SOURCE" "$HOME/SourceTree.command/$script_name/$script_name" "$HOME/Documents/Github/JobsGenesis/SourceTree.command/$script_name/$script_name"; do
    [[ -f "$candidate" ]] || continue
    SCRIPT_PATH="${candidate:A}"
    break
  done
  [[ -n "$SCRIPT_PATH" ]] || { print -u2 -r -- "无法定位脚本：$script_name"; exit 1; }
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
  is_sourcetree_runtime && IS_SOURCETREE_RUNTIME=1
  if [[ "$IS_SOURCETREE_RUNTIME" == 1 || ! -t 1 || -z "${TERM:-}" || "${TERM:-}" == dumb || -n "${NO_COLOR+x}" || "${JOBS_PLAIN_OUTPUT:-0}" == 1 ]]; then
    PLAIN_OUTPUT=1
    export NO_COLOR=1 FORCE_COLOR=0 CLICOLOR=0 ANSI_COLORS_DISABLED=1 npm_config_color=false
  fi
}
# 移除外部命令的颜色转义码，保证 Sourcetree 日志可读。
strip_ansi_stream() {
  /usr/bin/perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e\][^\a]*(?:\a|\e\\)//g'
}
# 保真输出路径和消息，确认后才同步写入日志。
log() {
  if [[ "$LOG_READY" == 1 ]]; then
    printf '%s\n' "$1" | tee -a "$LOG_FILE"
  else
    printf '%s\n' "$1"
  fi
}
# 为完整终端着色，消息中的路径按字面保留。
color_log() {
  local message="$2"
  if [[ "$PLAIN_OUTPUT" == 0 && -t 1 ]]; then
    printf -v message '%b%s%b' "$1" "$2" '\033[0m'
  fi
  log "$message"
}
# 输出明确的正常步骤。
info_echo() { color_log '\033[0;34m' "[INFO] $1"; }
# 输出明确的完成结果。
success_echo() { color_log '\033[1;32m' "[OK] $1"; }
# 输出需要留意的边界。
warn_echo() { color_log '\033[1;33m' "[WARN] $1"; }
# 输出失败原因。
error_echo() { color_log '\033[1;31m' "[ERROR] $1"; }
# 报告失败后停止，禁止后续步骤误报成功。
die() { error_echo "$1"; exit 1; }
# 确认后初始化系统工具 PATH、zsh 选项及本次日志。
initialize_script_runtime() {
  setopt NO_NOMATCH ERR_EXIT PIPE_FAIL
  export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
  : > "$LOG_FILE"
  LOG_READY=1
}
# 外部命令输出同步落盘，并明确传播原命令及日志管道失败。
run_cmd() {
  "$@" 2>&1 | strip_ansi_stream | tee -a "$LOG_FILE"
  local -a command_codes=("${pipestatus[@]}")
  local command_code=0
  for command_code in "${command_codes[@]}"; do
    (( command_code == 0 )) || return "$command_code"
  done
}
# 去除拖入路径的外层引号和末尾换行，不删除文件名内部引号。
strip_outer_quotes() {
  local value="$1"
  value="${value%$'\n'}"
  value="${value%$'\r'}"
  if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
    value="${value[2,-2]}"
  fi
  [[ "$value" == '~' ]] && value="$HOME"
  [[ "$value" == '~/'* ]] && value="$HOME/${value#\~/}"
  print -r -- "$value"
}

TARGET_DIRECTORY=""
POD_RUNNER=""
# 展示终端转发行为，终端独立调用仍需确认。
show_script_intro_and_wait() {
  prepare_display_context
  print -r -- "${SCRIPT_BASENAME}：打开终端安装 Pods" | jobs_intro_style title
  print -r -- "1、解析传入项目目录，打开 Terminal.app 并转交本库 Pod Install 入口。" | jobs_intro_style body
  print -r -- "2、子入口显示用途并等待回车，再执行默认纯净模式的 pod install --no-repo-update。" | jobs_intro_style body
  print -r -- "3、此入口的成功仅代表终端启动；安装结果和退出码显示在新终端及子入口日志。" | jobs_intro_style body
  print -r -- "启动日志：${LOG_FILE}；Ctrl+C 取消。" | jobs_intro_style body
  [[ "$IS_SOURCETREE_RUNTIME" == 1 ]] && return 0
  [[ -t 0 ]] || die "当前不是 Sourcetree 且没有可交互输入，请在终端运行。"
  read -r "?👉 按回车继续；Ctrl+C 取消：" _ || exit 1
}
# 检查脚本转发链和明确项目目录。
resolve_terminal_pod_target() {
  (( $# <= 1 )) || die "只接受一个项目目录。"
  local target="$(strip_outer_quotes "${1:-${SOURCETREE_REPO_PATH:-${REPO:-$PWD}}}")"
  [[ -f "$target" ]] && target="${target:h}"
  [[ -d "$target" ]] || die "项目目录不存在：$target"
  TARGET_DIRECTORY="${target:A}"
  [[ -f "$TARGET_DIRECTORY/Podfile" ]] || die "项目目录没有 Podfile：$TARGET_DIRECTORY"
  POD_RUNNER="${SCRIPT_DIR:h}/【MacOS@SourceTree】🫘在Sourcetree中运行Pod Install.command/【MacOS@SourceTree】🫘在Sourcetree中运行Pod Install.command"
  [[ -f "$POD_RUNNER" ]] || die "同库 Pod Install 入口缺失：$POD_RUNNER"
  /bin/zsh -n "$POD_RUNNER" || die "Pod Install 子入口语法不合法。"
  command -v osascript >/dev/null 2>&1 || die "系统 osascript 不可用。"
}
# 使用 AppleScript argv 与 quoted form 安全传递包含特殊字符的路径。
open_terminal_and_run_pod_install() {
  if ! osascript - "$POD_RUNNER" "$TARGET_DIRECTORY" >>"$LOG_FILE" 2>&1 <<'APPLESCRIPT'
on run argv
  set runnerPath to item 1 of argv
  set targetPath to item 2 of argv
  set shellCommand to "cd " & quoted form of targetPath & " && /bin/zsh " & quoted form of runnerPath & " " & quoted form of targetPath & "; jobsPodCode=$?; printf '\\nPod Install 退出码：%s\\n' \"$jobsPodCode\""
  tell application "Terminal"
    activate
    do script shellCommand
  end tell
end run
APPLESCRIPT
  then
    die "Terminal 启动失败；请检查自动化权限。日志：$LOG_FILE"
  fi
  success_echo "已提交终端启动；请在新终端确认并查看安装结果。启动日志：$LOG_FILE"
}
# 编排确认、目标校验和终端启动。
main() {
  show_script_intro_and_wait # 说明启动与安装结果的边界并按入口确认。
  initialize_script_runtime # 确认后初始化启动日志。
  resolve_terminal_pod_target "$@" # 校验项目及同库子入口。
  open_terminal_and_run_pod_install # 打开 Terminal 并转交带确认的 Pod Install。
}

main "$@"
