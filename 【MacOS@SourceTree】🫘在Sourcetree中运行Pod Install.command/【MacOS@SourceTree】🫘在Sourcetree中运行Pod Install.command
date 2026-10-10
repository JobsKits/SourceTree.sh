#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】🫘在Sourcetree中运行Pod Install.command
# - 核心用途：在明确工程目录执行 pod install，默认纯净模式且不更新规格索引。
# - 影响范围：下载项目依赖，可能更新 Pods、Podfile.lock 和工作区；递归需显式开启。
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

ROOT_DIR=""
POD_INSTALL_RECURSIVE=0
POD_INSTALL_PURE=1
POD_INSTALL_DEPLOYMENT=0
POD_INSTALL_REPO_UPDATE=0
POD_INSTALL_ARGS=()
POD_BIN=""
# 展示安装范围与默认参数，确认失败停止。
show_script_intro_and_wait() {
  prepare_display_context
  print -r -- "${SCRIPT_BASENAME}：安装项目 Pods" | jobs_intro_style title
  print -r -- "1、默认只处理传入目录，执行 pod install --no-repo-update；--recursive 才递归。" | jobs_intro_style body
  print -r -- "2、默认启用 JOBS_POD_INSTALL_PURE=1；--with-hooks 或 --full 允许 Podfile 外部增强。" | jobs_intro_style body
  print -r -- "3、--repo-update 更新规格索引；--deployment 限制锁文件变更，参数顺序不影响该选项。" | jobs_intro_style body
  print -r -- "影响：依赖、锁文件与 workspace；日志：${LOG_FILE}；Ctrl+C 取消。" | jobs_intro_style body
  [[ "$IS_SOURCETREE_RUNTIME" == 1 ]] && return 0
  [[ -t 0 ]] || die "当前不是 Sourcetree 且没有可交互输入，请在终端运行。"
  read -r "?👉 按回车继续；Ctrl+C 取消：" _ || exit 1
}
# 解析单个明确目录和独立选项，避免后续参数静默覆盖目标。
parse_pod_install_args() {
  local target="${SOURCETREE_REPO_PATH:-${REPO:-$PWD}}" explicit_target=0 literal_paths=0
  while (( $# )); do
    if [[ "$literal_paths" == 1 ]]; then
      (( explicit_target == 0 )) || die "只接受一个目标目录。"
      target="$1"; explicit_target=1
    else
      case "$1" in
        --recursive) POD_INSTALL_RECURSIVE=1 ;;
        --pure) POD_INSTALL_PURE=1 ;;
        --with-hooks|--full) POD_INSTALL_PURE=0 ;;
        --repo-update) POD_INSTALL_REPO_UPDATE=1 ;;
        --deployment) POD_INSTALL_DEPLOYMENT=1 ;;
        --) literal_paths=1 ;;
        -*) die "未知参数：$1" ;;
        *)
          (( explicit_target == 0 )) || die "只接受一个目标目录。"
          target="$1"; explicit_target=1
          ;;
      esac
    fi
    shift
  done
  target="$(strip_outer_quotes "$target")"
  [[ -f "$target" ]] && target="${target:h}"
  [[ -d "$target" ]] || die "目标目录不存在：$target"
  ROOT_DIR="${target:A}"
  POD_INSTALL_ARGS=(--no-repo-update)
  (( POD_INSTALL_REPO_UPDATE == 0 )) || POD_INSTALL_ARGS=(--repo-update)
  (( POD_INSTALL_DEPLOYMENT == 0 )) || POD_INSTALL_ARGS+=(--deployment)
}
# 验证 CocoaPods 可执行，不因命令名存在就继续调用损坏 shim。
check_pod_environment() {
  POD_BIN="$(command -v pod 2>/dev/null || true)"
  [[ -n "$POD_BIN" ]] || die "未找到 pod，请先安装并激活 CocoaPods / Ruby 工具链。"
  "$POD_BIN" --version >/dev/null 2>&1 || die "CocoaPods 健康检查失败：$POD_BIN --version；请检查 Ruby/gem 环境。"
  export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LC_CTYPE=en_US.UTF-8 COCOAPODS_DISABLE_STATS=true
  export RUBYOPT="${RUBYOPT:+$RUBYOPT }-EUTF-8:UTF-8"
  info_echo "目录：$ROOT_DIR；递归：$POD_INSTALL_RECURSIVE；纯净：$POD_INSTALL_PURE；参数：${POD_INSTALL_ARGS[*]}"
}
# 安装单个目录并把外部彩色输出降级，保留真实失败码。
process_pod_directory() {
  local directory="$1"
  [[ -f "$directory/Podfile" ]] || { error_echo "目标目录没有 Podfile：$directory"; return 1; }
  info_echo "处理目录：$directory"
  (
    cd "$directory" || exit 1
    run_cmd env JOBS_POD_INSTALL_PURE="$POD_INSTALL_PURE" JOBS_POD_INSTALL_SKIP_EXTERNAL_SCRIPTS="$POD_INSTALL_PURE" "$POD_BIN" install "${POD_INSTALL_ARGS[@]}"
  ) || { error_echo "pod install 失败：$directory"; return 1; }
  success_echo "pod install 成功：$directory"
}
# 只清理本次递归安装创建的枚举列表。
cleanup_pod_scope_list() {
  local list_file="$1"
  [[ "$list_file" == "${TMPDIR:-/tmp}"/jobs_pod_find.* && -f "$list_file" ]] || return 0
  rm -f -- "$list_file" || warn_echo "临时列表清理失败：$list_file"
}
# 先验证完整的 Podfile 集合，再安装并汇总失败及空扫描状态。
run_pod_install_scope() {
  local podfile="" podfiles_list="" total=0 failed=0 find_ec=0
  if (( POD_INSTALL_RECURSIVE == 0 )); then
    process_pod_directory "$ROOT_DIR" || exit 1
    return 0
  fi
  podfiles_list="$(mktemp "${TMPDIR:-/tmp}/jobs_pod_find.XXXXXX")" || die "无法创建 Podfile 枚举列表。"
  trap "cleanup_pod_scope_list ${(q)podfiles_list}" EXIT # 清理路径在注册时固定，覆盖完整枚举与安装。
  if find "$ROOT_DIR" \( -name .git -o -name node_modules -o -name Pods -o -name .dart_tool -o -name build -o -name DerivedData \) -prune -o -type f -name Podfile -print0 > "$podfiles_list" 2>> "$LOG_FILE"; then
    while IFS= read -r -d '' podfile; do
      total=$((total + 1))
      process_pod_directory "${podfile:h}" || failed=$((failed + 1))
    done < "$podfiles_list"
  else
    find_ec=$?
    die "递归枚举未完整完成：$ROOT_DIR；退出码 $find_ec。未对部分结果安装；日志：$LOG_FILE"
  fi
  info_echo "总计 $total 个 Podfile；失败 $failed 个。日志：$LOG_FILE"
  (( total > 0 )) || die "递归范围没有 Podfile，未执行安装。"
  (( failed == 0 )) || exit 1
}
# 编排自述、目录参数、工具检查和依赖安装。
main() {
  show_script_intro_and_wait # 展示依赖写入范围并按运行入口确认。
  initialize_script_runtime # 确认后初始化日志及 Shell。
  parse_pod_install_args "$@" # 限定目标并生成与顺序无关的参数。
  check_pod_environment # 验证 pod 健康并准备 UTF-8 环境。
  run_pod_install_scope # 只在明确范围安装并传播失败。
}

main "$@"
