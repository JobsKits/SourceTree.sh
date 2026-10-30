#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】🌍打开远程仓库地址.command
# - 核心用途：解析目标 Git 仓库，收集全部远程 URL，唯一地址直接复制，多个地址在终端用 fzf 选择；配对入口支持打开网页。
# - 影响范围：不修改 Git 状态或业务文件；仅写日志、剪贴板或打开浏览器；缺少 fzf 时确认后安装依赖。
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
    "${HOME}/SourceTree.command/MacOS/${script_name}/${script_name}" \
    "${HOME}/Documents/Github/JobsGenesis/SourceTree.command/MacOS/${script_name}/${script_name}"; do
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
REMOTE_ACTION=copy
REQUESTED_REMOTE=""
FZF_BIN=""
typeset -a REMOTE_URLS=() REMOTE_LABELS=()

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
  [[ "${1:-}" != --terminal-select ]] || TERMINAL_SELECT=1
  SCRIPT_PATH="$(resolve_script_path)"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${${SCRIPT_PATH:t}:r}"
  LOG_FILE="${LOG_DIR}/${SCRIPT_BASENAME}.log"
  [[ "$SCRIPT_BASENAME" != *打开远程仓库地址* ]] || REMOTE_ACTION=open
  if [[ "${TERMINAL_SELECT:-0}" != 1 ]] && is_sourcetree_runtime; then
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
  prepare_intro_output "$@"
  if [[ -z "${NO_COLOR+x}" && "${PLAIN_OUTPUT:-0}" != 1 && "$IS_SOURCETREE_RUNTIME" != "1" && -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 ==============================" | jobs_intro_style title
  note_echo "脚本名称：${SCRIPT_BASENAME}.command" | jobs_intro_style title
  note_echo "脚本路径：${SCRIPT_PATH}" | jobs_intro_style body
  note_echo "核心用途：收集目标 Git 仓库全部 fetch / push 地址；获取入口复制，打开入口使用系统浏览器。" | jobs_intro_style body
  note_echo "选择规则：完整 URL 去重后，单地址直接执行；多个地址在 Terminal 用 fzf 单选，Esc 取消。" | jobs_intro_style body
  note_echo "参数建议：Sourcetree 自定义动作参数填写 \$REPO；终端可传入仓库路径和可选远程名。" | jobs_intro_style body
  note_echo "安全边界：不提交、不推送、不改 Git 配置、索引或业务文件；打开网页联网，依赖安装需终端确认。" | jobs_intro_style body
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
  export PATH="${PATH:-}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_NAMESPACE
  prepare_intro_output "$@"
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
# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
jobs_brew_note() {
  print -u2 -r -- "ℹ $*"
}
# 验证候选能够执行；共享安装只读不代表未安装。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 发现既有健康安装，不以目录可写性决定是否重新安装。
jobs_brew_find() {
  local candidate
  local -a candidates
  candidates=("${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew
    "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew")
  for candidate in "${candidates[@]}"; do
    if jobs_brew_candidate_ok "$candidate"; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}
# 计算官方系统目录；实际支持范围和授权交由官方安装器处理。
jobs_brew_system_prefix() {
  case "$(/usr/bin/uname -m)" in
    arm64) print -r -- /opt/homebrew ;;
    *) print -r -- /usr/local ;;
  esac
}
# 缺失时强提示选择安装路径；YES 只表示选择系统目录，不验证密码或权限。
jobs_brew_choose_installation() {
  local answer="" system_prefix="$(jobs_brew_system_prefix)"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
    jobs_brew_note "缺少 Homebrew，需要人工选择安装路径；请在可交互终端重新运行，未执行安装。"
    return 1
  fi
  print -u2 -r -- "⚠ Homebrew 尚未就绪，必须先选择安装路径："
  print -u2 -r -- "1、输入精确大写 YES：选择系统标准目录 $system_prefix（Apple Silicon：/opt/homebrew；Intel：/usr/local）。"
  print -u2 -r -- "   这表示你准备向系统目录安装；官方安装器可能随后要求管理员密码，并自行验证权限。"
  print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
  print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
  print -u2 -n -r -- "➤ 安装路径选择："
  if ! IFS= read -r answer; then
    jobs_brew_note "输入已取消或结束，停止安装。"
    return 1
  fi
  if [[ "$answer" == YES ]]; then
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=system
  else
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=user
  fi
}
# 将官方系统安装器下载到临时文件后执行，失败不自动改装到用户目录。
jobs_brew_install_system() {
  local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
  jobs_brew_note "来源：https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh；目标：$system_prefix"
  if curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
    /bin/bash "$installer" || installer_result=$?
  else
    installer_result=1
  fi
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return 1
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
    jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
    return 1
  }
  if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
    jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
    return 1
  fi
  git_bin="$(command -v git 2>/dev/null)"
  [[ -n "$git_bin" ]] && "$git_bin" --version >/dev/null 2>&1 || { jobs_brew_note "用户目录安装需要可用 Git；请先准备 Git / Command Line Tools。"; return 1; }
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
  jobs_brew_note "来源：https://github.com/Homebrew/brew.git（官方稳定版本）；目标：$prefix"
  export HOMEBREW_NO_SUDO=1
  mkdir -p "${prefix:h}" || return 1
  stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
  if ! curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$stage/release.json"; then
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本失败，停止安装。"
    return 1
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] ||
     ! GIT_TERMINAL_PROMPT=0 "$git_bin" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$release_tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" ||
     ! "$git_bin" -C "$stage/brew" checkout -b stable ||
     ! "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
     ! mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var"; then
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 用户目录初始化失败，停止安装。"
    return 1
  fi
  # 空目录也只在下载成功后移除，避免提前改动用户的目标目录。
  if [[ -d "$prefix" ]] && ! rmdir -- "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  if ! mv "$stage/brew" "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  rm -r -- "$stage"
  typeset -g JOBS_HOMEBREW_BIN="$prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "用户目录安装后复检失败：$prefix"; return 1; }
}
# 激活当前进程并验证 Ruby 命令层；只有新安装才持久化 shellenv。
jobs_brew_activate() {
  local brew_env
  brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
  eval "$brew_env" || return 1
  typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
  export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
  rehash
  HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || { jobs_brew_note "Homebrew 命令层复检失败，停止后续业务。"; return 1; }
  if [[ "${1:-}" == installed ]]; then
    if [[ "${JOBS_HOMEBREW_INSTALL_MODE:-}" == user && -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
    fi
    jobs_brew_note "Homebrew 仅在本进程激活；未修改 Shell 启动配置。"
  fi
}
# 在原版安装位置复用或安装 Homebrew，安装失败必须终止外层业务。
jobs_brew_install_or_exit() {
  local installed=""
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
    return 0
  fi
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    jobs_brew_choose_installation || exit 1
    case "$JOBS_HOMEBREW_INSTALL_MODE" in
      system) jobs_brew_install_system || exit 1 ;;
      user) jobs_brew_install_user || exit 1 ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}
# <<< Jobs Homebrew install choice <<<
# 解析显式远程参数，兼容原第二参数和独立终端承接标志。
parse_remote_arguments() {
  [[ "${1:-}" != --terminal-select ]] || shift
  (( $# <= 2 )) || exit_with_error "用法：脚本 [仓库路径] [远程名]"
  REQUESTED_REMOTE="${2:-${REMOTE_NAME_OVERRIDE:-}}"
  resolve_repository_root "$@"
}
# 对菜单和日志隐藏用户信息、查询参数、片段和控制字符，原始地址仅用于业务。
protect_remote_text() {
  print -rn -- "$1" | /usr/bin/perl -pe 's/[\x00-\x1f\x7f]//g; s{(://)[^/]*\@}{$1***\@}g; s{^[^/:]+\@}{***\@}; s/[?#].*$/[参数已隐藏]/'
}
# 按完整地址去重，同时保留 remote 与 fetch / push 来源。
add_remote_candidate() {
  local remote="$1" direction="$2" url="$3" index=0
  [[ -n "$url" && "$url" != *[[:cntrl:]]* ]] || exit_with_error "远程地址为空或含控制字符，已停止。"
  index=${REMOTE_URLS[(Ie)$url]}
  if (( index > 0 )); then
    REMOTE_LABELS[$index]+="，${remote}/${direction}"
  else
    REMOTE_URLS+=("$url")
    REMOTE_LABELS+=("${remote}/${direction}")
  fi
}
# 收集每个 remote 生效的全部 fetch 与 push URL，不联网或修改 Git 配置。
collect_remote_candidates() {
  local names="" remote="" direction="" urls="" url="" found=0
  REMOTE_URLS=()
  REMOTE_LABELS=()
  names="$(git -C "$REPOSITORY_ROOT" remote 2>/dev/null)" || exit_with_error "无法列出 Git 远程。"
  while IFS= read -r remote; do
    [[ -n "$remote" ]] || continue
    [[ -z "$REQUESTED_REMOTE" || "$REQUESTED_REMOTE" == "$remote" ]] || continue
    [[ "$remote" != *[[:cntrl:]]* ]] || exit_with_error "远程名含控制字符，已停止。"
    found=1
    for direction in fetch push; do
      if [[ "$direction" == push ]]; then
        urls="$(git -C "$REPOSITORY_ROOT" remote get-url --push --all -- "$remote" 2>/dev/null)" || exit_with_error "读取 push 地址失败。"
      else
        urls="$(git -C "$REPOSITORY_ROOT" remote get-url --all -- "$remote" 2>/dev/null)" || exit_with_error "读取 fetch 地址失败。"
      fi
      while IFS= read -r url; do
        [[ -z "$url" ]] || add_remote_candidate "$remote" "$direction" "$url"
      done <<< "$urls"
    done
  done <<< "$names"
  (( found )) || exit_with_error "仓库未配置远程，或指定的远程不存在。"
  (( ${#REMOTE_URLS[@]} )) || exit_with_error "当前范围没有可用的远程地址。"
}
# 多地址时将仓库和远程筛选安全传入 Terminal，后台动作不发起任何交互。
open_terminal_for_selection() {
  if ! /usr/bin/osascript - "$SCRIPT_PATH" "$REPOSITORY_ROOT" "$REQUESTED_REMOTE" <<'APPLESCRIPT'
on run argv
  set shellCommand to "/bin/zsh " & quoted form of (item 1 of argv) & " --terminal-select " & quoted form of (item 2 of argv) & " " & quoted form of (item 3 of argv) & "; jobs_remote_result=$?; printf '\\n远程地址动作结束，退出码：%s\\n' \"$jobs_remote_result\""
  tell application "Terminal"
    activate
    do script shellCommand
  end tell
end run
APPLESCRIPT
  then
    exit_with_error "无法打开 Terminal；请检查自动化权限，或在终端直接运行本脚本。"
  fi
  success_echo "已打开 Terminal，请在新窗口确认并用 fzf 选择地址。"
  exit 0
}
# 检查 fzf 二进制、版本和当前选择所需选项，不读取用户默认参数。
fzf_candidate_ok() {
  local candidate="$1"
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  "$candidate" --version >/dev/null 2>&1 || return 1
  print -r -- $'1\tprobe' | /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE -u FZF_DEFAULT_COMMAND "$candidate" --no-multi --delimiter=$'\t' --with-nth=2.. --layout=reverse --border --header=probe --prompt='> ' --filter=probe >/dev/null 2>&1
}
# 在已知位置发现健康 fzf，复用当前可用来源。
find_healthy_fzf() {
  local candidate=""
  for candidate in "$(command -v fzf 2>/dev/null)" /opt/homebrew/bin/fzf /usr/local/bin/fzf "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/fzf" "$HOME/.fzf/bin/fzf"; do
    if fzf_candidate_ok "$candidate"; then
      FZF_BIN="$candidate"
      return 0
    fi
  done
  return 1
}
# 多地址才准备依赖：fzf → Homebrew → bash / curl / Git / CLT；安装一次后复检。
ensure_fzf_dependency() {
  find_healthy_fzf && return 0
  local answer="" operation=install
  warn_echo "fzf 缺失、损坏或缺少必要选项；需要 Homebrew 安装 / 修复。"
  note_echo "来源：Homebrew 官方源 https://formulae.brew.sh/formula/fzf；将写入所选 Homebrew 前缀。"
  IFS= read -r 'answer?直接回车安装 / 修复；输入任意字符后回车取消：' answer || exit_with_error "依赖确认已取消。"
  [[ -z "$answer" ]] || exit_with_error "已取消依赖安装。"
  /bin/bash --version >/dev/null 2>&1 || exit_with_error "依赖层 bash 不可用。"
  /usr/bin/curl --version >/dev/null 2>&1 || exit_with_error "依赖层 curl 不可用。"
  if ! /usr/bin/xcode-select -p >/dev/null 2>&1 || ! /usr/bin/xcrun --find clang >/dev/null 2>&1; then
    warn_echo "缺少可用 CLT / Xcode，请完成系统安装后重试。"
    /usr/bin/xcode-select --install || exit_with_error "无法启动 CLT 安装，请手动检查 xcode-select。"
    exit_with_error "CLT 安装尚需系统完成，已停止下游安装。"
  fi
  jobs_brew_install_or_exit
  if HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" list --versions fzf >/dev/null 2>&1; then
    operation=reinstall
  fi
  note_echo "正在从 Homebrew 官方源 ${operation} fzf；目标：${JOBS_HOMEBREW_PREFIX}。"
  HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" "$operation" fzf || exit_with_error "Homebrew 安装 / 修复 fzf 失败，已停止。"
  rehash
  find_healthy_fzf || exit_with_error "fzf 安装后复检失败，已停止；请检查 Homebrew 前缀和 fzf --version。"
}
# 唯一地址直接选定，多地址在真实 TTY 使用带隐藏序号的脱敏列表。
select_remote_candidate() {
  local selected="" rc=0 index=0 row=""
  local -a rows=()
  if (( ${#REMOTE_URLS[@]} == 1 )); then
    REMOTE_URL="${REMOTE_URLS[1]}"
    REMOTE_NAME="${REMOTE_LABELS[1]}"
    return 0
  fi
  [[ "$IS_SOURCETREE_RUNTIME" != 1 ]] || open_terminal_for_selection
  [[ -t 0 && -t 1 ]] || exit_with_error "多地址必须在可交互终端选择，当前没有 TTY。"
  ensure_fzf_dependency
  for (( index=1; index<=${#REMOTE_URLS[@]}; index++ )); do
    rows+=("${index}"$'\t'"$(protect_remote_text "${REMOTE_LABELS[$index]}")  $(protect_remote_text "${REMOTE_URLS[$index]}")")
  done
  selected="$(print -rl -- "${rows[@]}" | /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE -u FZF_DEFAULT_COMMAND "$FZF_BIN" --no-multi --delimiter=$'\t' --with-nth=2.. --layout=reverse --border --header='选择远程仓库地址：↑↓ 选择，回车确认；Esc / Ctrl+C 取消' --prompt='远程地址 > ')" || rc=$?
  case "$rc" in
    0) ;;
    1|130) note_echo "已取消或没有匹配地址，未执行复制 / 打开。"; exit 0 ;;
    *) exit_with_error "fzf 选择失败（退出码 ${rc}），未执行复制 / 打开。" ;;
  esac
  [[ -n "$selected" ]] || { note_echo "未选择地址，已取消。"; exit 0; }
  index=${rows[(Ie)$selected]}
  (( index > 0 )) || exit_with_error "选择器返回未知结果，已停止。"
  REMOTE_URL="${REMOTE_URLS[$index]}"
  REMOTE_NAME="${REMOTE_LABELS[$index]}"
}
# 将克隆 URL 转为网页 URL，仅允许 HTTP(S)，非默认 SSH 端口要求显式提供 HTTPS remote。
remote_url_to_web_url() {
  print -rn -- "$1" | /usr/bin/perl -e '
    local $/; my $u = <STDIN>; exit 1 if !defined($u) || $u =~ /[\x00-\x20\x7f\\]/;
    exit 1 if $u =~ /\A(?:file|javascript|data|vbscript|mailto|about|shell|ms-[a-z-]+):/i;
    my ($scheme,$authority,$path);
    if ($u =~ m{\A(https?)://([^/]+)(/.*)?\z}i) { ($scheme,$authority,$path)=(lc($1),$2,$3 // ""); }
    elsif ($u =~ m{\A(ssh|git)://([^/]+)/(.*)\z}i) {
      my $default_port = lc($1) eq "ssh" ? "22" : "9418";
      ($scheme,$authority,$path)=("https",$2,"/".$3); if ($authority =~ /:(\d+)$/) { exit 1 if $1 ne $default_port; $authority =~ s/:\d+$//; }
    }
    elsif ($u =~ m{\A(?:[^/@:]+\@)?([A-Za-z0-9_.-]+):([^/].*)\z} && length($1)>1) {
      ($scheme,$authority,$path)=("https",$1,"/".$2);
    } else { exit 1; }
    $authority =~ s/.*\@//; $path =~ s/[?#].*//; $path =~ s{/+$}{}; $path =~ s/\.git$//;
    exit 1 unless $authority =~ /\A(?:[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?|\[[0-9a-fA-F:]+\])(?::[0-9]+)?\z/;
    exit 1 if !$path || $path eq "/" || $path =~ /(?:\A|\/)\.\.?(?:\/|\z)/;
    print "$scheme://$authority$path";
  '
}
# 使用系统 URL 打开器，参数作为单个 URL 传入，不求值 Shell 文本。
open_remote_web_url() {
  /usr/bin/open "$1"
}
# 获取动作保留原地址；打开动作调用系统浏览器，结果真实反映命令退出状态。
perform_remote_action() {
  REMOTE_URL_DISPLAY="$(protect_remote_text "$REMOTE_URL")"
  if [[ "$REMOTE_ACTION" == open ]]; then
    local web_url=""
    web_url="$(remote_url_to_web_url "$REMOTE_URL")" || exit_with_error "该地址无法安全转换为网页；可使用获取动作复制原地址。"
    note_echo "网页地址：$(protect_remote_text "$web_url")"
    open_remote_web_url "$web_url" || exit_with_error "系统浏览器打开失败。"
    success_echo "已请求系统浏览器打开远程仓库。"
  else
    command -v pbcopy >/dev/null 2>&1 || exit_with_error "pbcopy 不可用，未复制。"
    print -rn -- "$REMOTE_URL" | pbcopy || exit_with_error "剪贴板写入失败。"
    success_echo "已复制选定的原始 Git 地址到剪贴板。"
  fi
}
# 输出脱敏后的地址、来源和本次日志位置。
print_remote_summary() {
  note_echo "仓库根目录：${REPOSITORY_ROOT}"
  note_echo "远程来源：${REMOTE_NAME}"
  note_echo "远程仓库地址：${REMOTE_URL_DISPLAY}"
  gray_echo "日志文件：${LOG_FILE}"
}
# 编排双入口共用的仓库解析、地址选择与复制 / 打开流程。
main() {
  show_script_intro_and_wait "$@" # 打印内置说明，终端确认，Sourcetree 后台直接继续。
  initialize_script_runtime # 初始化进程环境和日志，并隔离 Git 定位变量。
  check_environment # 验证 Git 可执行，不为唯一地址安装 fzf。
  parse_remote_arguments "$@" # 解析仓库路径、可选远程名和终端承接标志。
  collect_remote_candidates # 收集所有生效的 fetch / push URL 并去重。
  select_remote_candidate # 单地址直用，多地址转交独立终端 fzf 选择。
  perform_remote_action # 按脚本入口复制原始 URL 或打开网页 URL。
  print_remote_summary # 输出实际执行目标的脱敏摘要。
}

main "$@"
