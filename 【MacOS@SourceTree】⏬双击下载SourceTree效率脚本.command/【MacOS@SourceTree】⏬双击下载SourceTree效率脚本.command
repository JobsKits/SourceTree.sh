#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】⏬双击下载SourceTree效率脚本.command
# - 核心用途：下载官方脚本库，校验完成后备份替换运行目录。
# - 影响范围：写入运行目录；已有目录必须在终端输入 YES 后备份替换。
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

REPO_URL="https://github.com/JobsKits/SourceTree.sh.git"
CLONE_DIR="${HOME}/SourceTree.command"
STAGING_ROOT=""
BACKUP_DIR=""
# 展示下载与替换边界，确认失败立即退出。
show_script_intro_and_wait() {
  prepare_display_context
  print -r -- "${SCRIPT_BASENAME}：下载 SourceTree 效率脚本" | jobs_intro_style title
  print -r -- "1、先克隆到临时目录，检查每个 .command 的语法及配套 README，再写入运行目录。" | jobs_intro_style body
  print -r -- "2、已有运行目录先完整备份；下载或校验失败保留旧目录，不自动执行下载的脚本。" | jobs_intro_style body
  print -r -- "3、Sourcetree 只允许首次安装；已有运行目录请在终端输入 YES 进行备份替换。" | jobs_intro_style body
  print -r -- "来源：${REPO_URL}；日志：${LOG_FILE}；Ctrl+C 取消。" | jobs_intro_style body
  [[ "$IS_SOURCETREE_RUNTIME" == 1 ]] && return 0
  [[ -t 0 ]] || die "当前不是 Sourcetree 且没有可交互输入，请在终端运行。"
  read -r "?👉 按回车继续；Ctrl+C 取消：" _ || exit 1
}
# 限制安装目标并在下载前确认覆盖，保护现有自定义脚本。
check_download_environment() {
  [[ "$EUID" != 0 ]] || die "请勿使用 sudo/root 安装用户脚本。"
  git --version >/dev/null 2>&1 || die "Git 不可用，请检查 Command Line Tools。"
  [[ ! -L "$CLONE_DIR" ]] || die "运行目录是符号链接，停止替换：$CLONE_DIR"
  if [[ -e "$CLONE_DIR" ]]; then
    [[ -d "$CLONE_DIR" ]] || die "运行路径被普通文件占用：$CLONE_DIR"
    [[ "$IS_SOURCETREE_RUNTIME" != 1 ]] || die "运行目录已存在；请在终端确认备份替换。"
    local answer=""
    warn_echo "即将用下载版本替换：$CLONE_DIR。现有内容会完整移至同级备份。"
    read -r "?👉 输入 YES 后回车替换，其它输入取消：" answer || exit 1
    [[ "$answer" == YES ]] || { info_echo "已取消，运行目录未改动。"; exit 0; }
  fi
}
# 仅清理本次 mktemp 创建的下载暂存目录。
cleanup_download_staging() {
  [[ -n "$STAGING_ROOT" && -d "$STAGING_ROOT" && "${STAGING_ROOT:h}" == "$HOME" && "${STAGING_ROOT:t}" == .SourceTree.download.* ]] || return 0
  rm -rf -- "$STAGING_ROOT"
}
# 克隆到同级临时目录，失败时保留现有运行目录。
download_scripts_to_staging() {
  STAGING_ROOT="$(mktemp -d "$HOME/.SourceTree.download.XXXXXX")" || die "无法创建下载暂存目录。"
  run_cmd git clone --depth=1 "$REPO_URL" "$STAGING_ROOT/package" || die "下载失败，现有运行目录未改动。"
}
# 校验脚本包结构及 zsh 语法，只授权本次下载的入口文件。
validate_downloaded_scripts() {
  local script="" count=0
  [[ -f "$STAGING_ROOT/package/README.md" ]] || die "下载内容缺少总 README，停止替换。"
  while IFS= read -r -d '' script; do
    [[ -f "${script:h}/README.md" ]] || die "脚本缺少配套 README：$script"
    run_cmd /bin/zsh -n "$script" || die "脚本语法无效：$script"
    chmod u+x "$script" || die "无法授权：$script"
    count=$((count + 1))
  done < <(find "$STAGING_ROOT/package" \( -name .git -o -name node_modules -o -name Pods -o -name build -o -name .dart_tool -o -name DerivedData \) -prune -o -type f -name '*.command' -print0)
  (( count > 0 )) || die "下载内容没有 .command 入口，停止替换。"
  success_echo "已校验 $count 个入口。"
}
# 校验后先备份旧目录，再写入新目录；写入失败恢复旧内容。
install_validated_scripts() {
  if [[ -e "$CLONE_DIR" ]]; then
    BACKUP_DIR="$(mktemp -d "$HOME/SourceTree.command.bak.$(date '+%Y%m%d_%H%M%S').XXXXXX")" || die "无法准备备份目录。"
    rmdir "$BACKUP_DIR" || die "无法准备备份路径。"
    mv "$CLONE_DIR" "$BACKUP_DIR" || die "备份运行目录失败，停止替换。"
  fi
  if ! mv "$STAGING_ROOT/package" "$CLONE_DIR"; then
    if [[ -n "$BACKUP_DIR" && ! -e "$CLONE_DIR" ]]; then
      mv "$BACKUP_DIR" "$CLONE_DIR" || die "写入及恢复均失败，原目录保存在：$BACKUP_DIR"
    fi
    die "写入失败，已恢复原目录。"
  fi
  success_echo "下载完成：$CLONE_DIR"
  [[ -z "$BACKUP_DIR" ]] || info_echo "可恢复备份：$BACKUP_DIR"
  info_echo "菜单请使用库内安装入口维护，下载操作不会覆盖当前 Sourcetree 标题或配置。"
}
# 在覆盖整个事务的作用域注册清理，避免 zsh 函数返回时提前清掉下载内容。
run_download_flow() {
  trap cleanup_download_staging EXIT
  check_download_environment # 校验目标及替换授权。
  download_scripts_to_staging # 下载到独立暂存目录。
  validate_downloaded_scripts # 语法与结构通过后才允许替换。
  install_validated_scripts # 完整备份现有目录并安全写入新版本。
}
# 编排确认、日志初始化及完整下载事务。
main() {
  show_script_intro_and_wait # 先说明影响并完成终端确认。
  initialize_script_runtime # 确认后初始化日志和系统命令环境。
  run_download_flow # 下载校验后安全替换，并在流程结束清理暂存。
}

main "$@"
