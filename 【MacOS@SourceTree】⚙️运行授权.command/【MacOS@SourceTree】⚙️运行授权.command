#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】⚙️运行授权.command
# - 核心用途：对明确选定的 .command 文件添加用户执行权限。
# - 影响范围：只修改目标入口权限并移除该文件的隔离属性；递归跳过缓存、第三方及生成目录。
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

BASE_DIR=""
typeset -gaU TARGETS=()
# 展示授权范围，确认失败即停止。
show_script_intro_and_wait() {
  prepare_display_context
  print -r -- "${SCRIPT_BASENAME}：授权 .command 入口" | jobs_intro_style title
  print -r -- "1、参数可为文件或目录；无参数使用 REPO 或脚本库根目录。默认只扫描当前目录。" | jobs_intro_style body
  print -r -- "2、RECURSIVE=1 才递归；跳过 .git、node_modules、Pods、.dart_tool、build、DerivedData。" | jobs_intro_style body
  print -r -- "3、仅对 .command 普通文件 chmod u+x，并移除该文件的 quarantine；任何失败返回非零。" | jobs_intro_style body
  print -r -- "日志：${LOG_FILE}；Ctrl+C 取消。" | jobs_intro_style body
  [[ "$IS_SOURCETREE_RUNTIME" == 1 ]] && return 0
  [[ -t 0 ]] || die "当前不是 Sourcetree 且没有可交互输入，请在终端运行。"
  read -r "?👉 按回车继续；Ctrl+C 取消：" _ || exit 1
}
# 只清理本次完整枚举创建的临时列表。
cleanup_authorization_list() {
  local list_file="$1"
  [[ "$list_file" == "${TMPDIR:-/tmp}"/jobs_auth_find.* && -f "$list_file" ]] || return 0
  rm -f -- "$list_file" || warn_echo "临时列表清理失败：$list_file"
}
# 完整验证递归枚举后才加入目标，避免按部分结果授权。
collect_directory_scripts() {
  local directory="$1" script="" scripts_list="" find_ec=0
  if [[ "${RECURSIVE:-0}" == 1 ]]; then
    scripts_list="$(mktemp "${TMPDIR:-/tmp}/jobs_auth_find.XXXXXX")" || { error_echo "无法创建授权枚举列表。"; return 1; }
    trap "cleanup_authorization_list ${(q)scripts_list}" EXIT # 捕获转义后的路径，避免函数退出时局部变量已释放。
    if find "$directory" \( -name .git -o -name node_modules -o -name Pods -o -name .dart_tool -o -name build -o -name DerivedData \) -prune -o -type f -name '*.command' -print0 > "$scripts_list" 2>> "$LOG_FILE"; then
      while IFS= read -r -d '' script; do
        TARGETS+=("$script")
      done < "$scripts_list"
    else
      find_ec=$?
      error_echo "递归枚举未完整完成：$directory；退出码 $find_ec。未授权任何部分结果；日志：$LOG_FILE"
      return "$find_ec"
    fi
  else
    while IFS= read -r -d '' script; do TARGETS+=("$script"); done < <(find "$directory" -maxdepth 1 -type f -name '*.command' -print0)
  fi
}
# 接受多个路径，明确文件不再被当作基准目录丢掉。
resolve_authorization_targets() {
  local -a inputs=("$@")
  local input="" resolved=""
  (( ${#inputs} > 0 )) || inputs=("${REPO:-${SCRIPT_DIR:h}}")
  for input in "${inputs[@]}"; do
    resolved="$(strip_outer_quotes "$input")"
    [[ -e "$resolved" && ! -L "$resolved" ]] || die "路径不存在或是符号链接：$resolved"
    resolved="${resolved:A}"
    if [[ -d "$resolved" ]]; then
      collect_directory_scripts "$resolved" || exit $?
    elif [[ "$resolved" == *.command && -f "$resolved" ]]; then
      TARGETS+=("$resolved")
    else
      die "只接受目录或 .command 文件：$resolved"
    fi
  done
  info_echo "待授权入口：${#TARGETS} 个；递归：${RECURSIVE:-0}。"
}
# 授权单个入口并在隔离属性确实存在时移除。
authorize_one_script() {
  local script="$1"
  chmod u+x "$script" 2>>"$LOG_FILE" || { error_echo "授权失败：$script"; return 1; }
  if command -v xattr >/dev/null 2>&1 && xattr -p com.apple.quarantine "$script" >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "$script" 2>>"$LOG_FILE" || { error_echo "移除隔离属性失败：$script"; return 1; }
  fi
  success_echo "$script"
}
# 汇总实际失败数，并把批量失败传播给调用者。
run_authorization() {
  local script="" failed=0
  for script in "${TARGETS[@]}"; do
    authorize_one_script "$script" || failed=$((failed + 1))
  done
  info_echo "总计 ${#TARGETS} 个；成功 $((${#TARGETS} - failed)) 个；失败 $failed 个。日志：$LOG_FILE"
  (( failed == 0 )) || exit 1
}
# 编排说明、目标收集和逐项授权。
main() {
  show_script_intro_and_wait # 先说明权限影响并按入口确认。
  initialize_script_runtime # 确认后初始化日志与 Shell。
  resolve_authorization_targets "$@" # 解析多个目标并限定 .command 范围。
  run_authorization # 逐项授权并传播失败统计。
}

main "$@"
