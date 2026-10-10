#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】📦双击打包Flutter.android.command
# - 核心用途：构建选定 Flutter 工程的 APK、AAB 或两种产物。
# - 影响范围：联网解析依赖并调用工程 Android 构建与签名，工具链不自动升级。
# - 运行提示：运行后会先打印内置自述；Sourcetree 模式无交互连续执行，终端模式确认后继续。
# =====================================================================
# Jobs 标准化脚本外壳
# 说明：保留原脚本业务逻辑，补齐 README 防误触、彩色日志、zsh 入口、Homebrew 健康自检标准。
# =====================================================================
# Sourcetree 自定义动作可能只传脚本名，不传绝对路径；这里兜底找回真实脚本位置。
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
# 按脚本源码路径和标准目录解析真实入口文件。
resolve_script_path() {
  local script_source="$SCRIPT_SOURCE"
  local script_name="${SCRIPT_SOURCE:t}"
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

readonly SCRIPT_SOURCE="$0"
SCRIPT_PATH=""
SCRIPT_DIR=""
SCRIPT_BASENAME=""
LOG_FILE=""
LOG_READY=0
# 识别 Sourcetree 自定义动作的瘦身运行环境，系统终端双击运行不降级。
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

IS_SOURCETREE_RUNTIME=0

SOURCETREE_PLAIN_OUTPUT=0
# 封装 strip_ansi_text 对应的独立处理逻辑。
strip_ansi_text() {
  perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}
# 根据运行入口和终端能力预先切换纯文本输出，避免 Sourcetree 显示 ANSI 转义码。
# 在第一屏输出前确定纯文本模式，确认后再重复初始化输出环境。
prepare_plain_output_context() {
  SOURCETREE_PLAIN_OUTPUT=0
  PLAIN_OUTPUT=0
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == 1 || ! -t 1 || -z "${TERM:-}" || "${TERM:-}" == dumb || -n "${NO_COLOR+x}" || "${JOBS_PLAIN_OUTPUT:-0}" == 1 ]]; then
    SOURCETREE_PLAIN_OUTPUT=1
    PLAIN_OUTPUT=1
    export NO_COLOR=1 FORCE_COLOR=0 CLICOLOR=0 ANSI_COLORS_DISABLED=1 npm_config_color=false
  fi
}
# 只准备自述所需路径和入口身份，尚不创建日志或执行工程操作。
prepare_script_metadata() {
  SCRIPT_PATH="$(resolve_script_path)"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
  IS_SOURCETREE_RUNTIME=0
  if is_sourcetree_runtime; then
    IS_SOURCETREE_RUNTIME=1
  fi
  prepare_plain_output_context
}
# 按当前输出级别记录终端信息，并同步写入脚本日志。
# 确认前仅显示文字，确认后将同一输出同步写入日志。
write_log_output() {
  if [[ "${LOG_READY:-0}" == 1 ]]; then
    tee -a "$LOG_FILE"
  else
    cat
  fi
}
# 保留路径和命令中的字面反斜杠，只过滤展示用 ANSI 控制码。
log() {
  if [[ "${SOURCETREE_PLAIN_OUTPUT:-0}" == 1 ]]; then
    printf '%s\n' "$1" | strip_ansi_text | write_log_output
  else
    printf '%s\n' "$1" | write_log_output
  fi
}
# 颜色只作用于日志样式，正文始终按字面文字输出。
color_log() {
  if [[ "${SOURCETREE_PLAIN_OUTPUT:-0}" == 1 ]]; then
    log "$2"
  else
    log "$(printf '%b%s%b' "$1" "$2" '\033[0m')"
  fi
}
# 输出一般完成信息。
color_echo() { color_log '\033[1;32m' "$1"; }
# 输出步骤与环境信息。
info_echo() { color_log '\033[1;34m' "ℹ $1"; }
# 输出已完成步骤。
success_echo() { color_log '\033[1;32m' "✔ $1"; }
# 输出需要关注的风险。
warn_echo() { color_log '\033[1;33m' "⚠ $1"; }
# 输出温馨提示。
warm_echo() { color_log '\033[1;33m' "$1"; }
# 输出操作说明。
note_echo() { color_log '\033[1;35m' "➤ $1"; }
# 输出带前缀的错误信息。
error_echo() { color_log '\033[1;31m' "✖ $1"; }
# 输出错误正文。
err_echo() { color_log '\033[1;31m' "$1"; }
# 输出诊断信息。
debug_echo() { color_log '\033[1;35m' "🐞 $1"; }
# 输出展示重点。
highlight_echo() { color_log '\033[1;36m' "🔹 $1"; }
# 输出次要信息。
gray_echo() { color_log '\033[0;90m' "$1"; }
# 输出加粗信息。
bold_echo() { color_log '\033[1m' "$1"; }
# 输出带下划线的信息。
underline_echo() { color_log '\033[4m' "$1"; }
# 识别当前 CPU 架构。
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}
# 封装 abs_path 对应的独立处理逻辑。
abs_path() {
  local p="$1"
  [[ -z "$p" ]] && return 1
  p="${p//\"/}"
  [[ "$p" != "/" ]] && p="${p%/}"
  if [[ -d "$p" ]]; then
    (cd "$p" 2>/dev/null && pwd -P)
  elif [[ -f "$p" ]]; then
    (cd "${p:h}" 2>/dev/null && printf "%s/%s\n" "$(pwd -P)" "${p:t}")
  else
    return 1
  fi
}
# 收集并校验用户输入，决定后续执行路径。
ask_run() {
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" ]]; then
    gray_echo "Sourcetree 连续执行模式已跳过当前可选交互。"
    return 1
  fi
  echo ""
  note_echo "👉 $1"
  gray_echo "【回车=跳过，输入任意字符后回车=执行】"
  local input=""
  IFS= read -r "input?➤ "
  [[ -n "$input" ]]
}
# 收集并校验用户输入，决定后续执行路径。
confirm_yes() {
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" ]]; then
    gray_echo "Sourcetree 连续执行模式已跳过当前可选交互。"
    return 1
  fi
  echo ""
  warn_echo "⚠ $1"
  gray_echo "危险操作必须输入 YES 后回车；其它输入一律取消。"
  local input=""
  IFS= read -r "input?➤ "
  [[ "$input" == "YES" ]]
}
# 封装 inject_shellenv_block 对应的独立处理逻辑。
inject_shellenv_block() {
  local profile_file="$1"
  local shellenv_cmd="$2"
  local header="# >>> Homebrew 环境变量 >>>"
  [[ -z "$profile_file" || -z "$shellenv_cmd" ]] && { error_echo "缺少参数：inject_shellenv_block <profile_file> <shellenv_cmd>"; return 1; }
  mkdir -p "$(dirname "$profile_file")"
  touch "$profile_file"
  if grep -Fq "$shellenv_cmd" "$profile_file" 2>/dev/null; then
    info_echo "已存在 Homebrew shellenv：$profile_file"
  elif grep -Fq "$header" "$profile_file" 2>/dev/null; then
    info_echo "已存在 Homebrew 环境变量块：$profile_file"
  else
    {
      echo ""
      echo "$header"
      echo "$shellenv_cmd"
    } >> "$profile_file"
    success_echo "已写入 Homebrew shellenv：$profile_file"
  fi
  eval "$shellenv_cmd" || true
}
# 封装 activate_homebrew_shellenv 对应的独立处理逻辑。
activate_homebrew_shellenv() {
  local arch="$(get_cpu_arch)"
  local brew_bin=""
  if command -v brew >/dev/null 2>&1; then
    brew_bin="$(command -v brew)"
  elif [[ "$arch" == "arm64" && -x "/opt/homebrew/bin/brew" ]]; then
    brew_bin="/opt/homebrew/bin/brew"
  elif [[ -x "/usr/local/bin/brew" ]]; then
    brew_bin="/usr/local/bin/brew"
  fi
  [[ -z "$brew_bin" ]] && return 1

  local shell_name="${SHELL##*/}"
  local profile_file=""
  case "$shell_name" in
    zsh)  profile_file="$HOME/.zprofile" ;;
    bash) profile_file="$HOME/.bash_profile" ;;
    *)    profile_file="$HOME/.profile" ;;
  esac
  inject_shellenv_block "$profile_file" "eval \"\$(${brew_bin} shellenv)\""
  eval "$(${brew_bin} shellenv)"
}
# 执行已经拆分完成的独立业务步骤。
run_brew_health_update() {
  info_echo "正在执行 Homebrew 健康更新..."
  brew update  || { error_echo "brew update 失败"; return 1; }
  brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
  brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
  brew doctor  || warn_echo "brew doctor 有警告，请按输出处理"
  brew -v      || warn_echo "打印 brew 版本失败，可忽略"
  success_echo "Homebrew 健康更新完成"
}
# 执行对应的环境配置或同步处理。
install_homebrew() {
  local arch="$(get_cpu_arch)"
  local brew_bin=""

  if ! command -v brew >/dev/null 2>&1 && [[ ! -x "/opt/homebrew/bin/brew" && ! -x "/usr/local/bin/brew" ]]; then
    warn_echo "未检测到 Homebrew，准备按架构安装：$arch"
    if [[ "$arch" == "arm64" ]]; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || { error_echo "Homebrew 安装失败（arm64）"; return 1; }
      brew_bin="/opt/homebrew/bin/brew"
    else
      arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || { error_echo "Homebrew 安装失败（x86_64）"; return 1; }
      brew_bin="/usr/local/bin/brew"
    fi
    success_echo "Homebrew 安装完成"
    activate_homebrew_shellenv || true
    return 0
  fi

  activate_homebrew_shellenv || true
  info_echo "Homebrew 已安装。"
  if ask_run "是否执行 Homebrew 更新 / 升级 / 清理 / doctor？"; then
    run_brew_health_update
  else
    note_echo "已跳过 Homebrew 更新"
  fi
}
# 封装 brew_install_or_upgrade 对应的独立处理逻辑。
brew_install_or_upgrade() {
  local formula="$1"
  [[ -z "$formula" ]] && return 1
  install_homebrew || return 1
  if ! brew list --formula "$formula" >/dev/null 2>&1 && ! command -v "$formula" >/dev/null 2>&1; then
    note_echo "未检测到 $formula，正在安装..."
    brew install "$formula" || { error_echo "$formula 安装失败"; return 1; }
    success_echo "$formula 安装完成"
  else
    info_echo "$formula 已安装。"
    if ask_run "是否升级 $formula？"; then
      brew upgrade "$formula" || warn_echo "$formula 可能已是最新或升级失败，请检查输出"
      brew cleanup || true
    else
      note_echo "已跳过 $formula 升级"
    fi
  fi
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_script_intro_and_wait() {
  prepare_script_metadata
  if [[ -z "${NO_COLOR+x}" && "${IS_SOURCETREE_RUNTIME:-0}" != "1" && -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" && "${PLAIN_OUTPUT:-0}" != 1 ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 ==============================" | jobs_intro_style title
  note_echo "脚本名称：${SCRIPT_BASENAME}.command" | jobs_intro_style title
  note_echo "脚本路径：${SCRIPT_PATH}" | jobs_intro_style body
  note_echo "运行入口：兼容系统终端双击运行和 Sourcetree 自定义动作运行。" | jobs_intro_style body
  note_echo "核心用途：构建选定 Flutter 工程的 APK、AAB 或两种产物。" | jobs_intro_style body
  warn_echo "影响范围：联网解析依赖并调用工程 Android 构建与签名，工具链不自动升级。" | jobs_intro_style body
  note_echo "环境策略：系统终端保留清屏、彩色输出和回车确认；Sourcetree 瘦身环境自动跳过清屏和等待，并输出纯文本日志。" | jobs_intro_style body
  note_echo "文档关系：同目录 README.md 只作为外部说明文档保留，运行时自述不读取、不拼接、不依赖 README.md。" | jobs_intro_style body
  warn_echo "继续前请确认 SourceTree 传入路径、当前仓库或拖入路径正确；按 Ctrl+C 可以取消。" | jobs_intro_style body
  gray_echo "日志文件：${LOG_FILE}" | jobs_intro_style body
  highlight_echo "=======================================================================" | jobs_intro_style title
  echo "" | jobs_intro_style body

  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" ]]; then
    gray_echo "已识别为 Sourcetree 自定义动作，将跳过交互并连续执行。" | jobs_intro_style body
    return 0
  fi
  if [[ ! -t 0 ]]; then
    error_echo "当前不是 Sourcetree，且没有可交互输入；请在终端中重新运行。"
    exit 1
  fi
  read -r "?👉 已阅读脚本内置自述，按回车继续执行；按 Ctrl+C 取消..." _ || exit 1
}
# 执行已经拆分完成的独立业务步骤。
# 对输入只解除外层引号和拖拽转义，保留目录内原有引号。
normalize_flutter_input() {
  local input_value="$1"
  if [[ -e "$input_value" ]]; then
    print -r -- "$input_value"
    return 0
  fi
  input_value="${input_value%$'\r'}"
  input_value="${input_value%$'\n'}"
  if [[ "$input_value" == \"*\" || "$input_value" == \'*\' ]]; then
    input_value="${input_value[2,-2]}"
  fi
  [[ "$input_value" == '~/'* ]] && input_value="$HOME/${input_value#\~/}"
  if [[ ! -e "$input_value" ]]; then
    input_value="${(Q)input_value}"
  fi
  print -r -- "$input_value"
}
# 先向上定位，再在指定目录内查找；多个候选必须由用户明确路径。
resolve_flutter_project() {
  local base="$(normalize_flutter_input "${1:-${PROJECT_DIR:-${REPO:-$PWD}}}")"
  local candidate="" current=""
  local -a candidates=()
  [[ -f "$base" ]] && base="${base:h}"
  [[ -d "$base" ]] || { error_echo "工程路径不存在：$base"; return 1; }
  base="$(cd "$base" && pwd -P)" || return 1
  [[ "$base" != / && "$base" != "$HOME" ]] || { error_echo "拒绝扫描整个根目录或用户目录，请指定工程目录。"; return 1; }
  current="$base"
  while [[ "$current" != / ]]; do
    if [[ -f "$current/pubspec.yaml" && -d "$current/lib" ]]; then
      FLUTTER_ROOT="$current"
      return 0
    fi
    current="${current:h}"
  done
  while IFS= read -r -d '' candidate; do
    [[ -d "${candidate:h}/lib" ]] && candidates+=("${candidate:h}")
  done < <(find "$base" \( -type d \( -name .git -o -name node_modules -o -name Pods -o -name PodsManual -o -name 'ManualBy*Pods*' -o -name .dart_tool -o -name .fvm -o -name build -o -name DerivedData -o -name .import_backup -o -name vendor -o -name third_party -o -name ThirdParty \) -prune \) -o \( -type f -name pubspec.yaml -print0 \))
  if (( ${#candidates[@]} != 1 )); then
    error_echo "应找到唯一 Flutter 工程，当前候选数量：${#candidates[@]}。请直接传入工程根目录。"
    for candidate in "${candidates[@]}"; do
      gray_echo "候选：$candidate"
    done
    return 1
  fi
  FLUTTER_ROOT="${candidates[1]}"
}
# 进入工程后再选择其固定 SDK，避免使用启动目录的 FVM 配置。
choose_project_flutter() {
  typeset -ga FLUTTER_CMD DART_CMD
  cd "$FLUTTER_ROOT" || return 1
  export PATH="$HOME/.pub-cache/bin:$HOME/.fvm/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
  if [[ -x "$FLUTTER_ROOT/.fvm/flutter_sdk/bin/flutter" ]]; then
    FLUTTER_CMD=("$FLUTTER_ROOT/.fvm/flutter_sdk/bin/flutter")
    DART_CMD=("$FLUTTER_ROOT/.fvm/flutter_sdk/bin/dart")
  elif [[ -f .fvmrc || -f .fvm/fvm_config.json ]]; then
    command -v fvm >/dev/null 2>&1 || { error_echo "工程固定了 FVM，但本地 SDK / fvm 不可用，请先恢复对应 SDK。"; return 1; }
    FLUTTER_CMD=(fvm flutter)
    DART_CMD=(fvm dart)
  elif command -v flutter >/dev/null 2>&1; then
    local flutter_executable="${commands[flutter]:A}"
    FLUTTER_CMD=("$flutter_executable")
    if [[ -x "${flutter_executable:h}/dart" ]]; then
      DART_CMD=("${flutter_executable:h}/dart")
    else
      DART_CMD=(dart)
    fi
  else
    error_echo "没有可用的 Flutter SDK，请检查 PATH 或项目 FVM 配置。"
    return 1
  fi
  info_echo "工程目录：$FLUTTER_ROOT"
  info_echo "Flutter 命令：${(j: :)FLUTTER_CMD}"
}
# 过滤展示输出，不将业务函数放进管道。
flutter_command_output() {
  if [[ "${SOURCETREE_PLAIN_OUTPUT:-0}" == 1 ]]; then
    strip_ansi_text
  else
    cat
  fi
}
# 管道失败与命令失败都必须向调用方传播。
run_flutter_step() {
  local title="$1"
  shift
  info_echo "开始：$title"
  if "$@" 2>&1 | flutter_command_output | tee -a "$LOG_FILE"; then
    success_echo "完成：$title"
  else
    local command_ec=$?
    error_echo "$title 失败，退出码：$command_ec。后续步骤已停止。"
    return "$command_ec"
  fi
}

BUILD_LOG=""
BUILD_HB_PID=""
# 停止并回收当前构建的进度心跳。
stop_build_heartbeat() {
  if [[ -n "$BUILD_HB_PID" ]]; then
    kill "$BUILD_HB_PID" 2>/dev/null || true
    wait "$BUILD_HB_PID" 2>/dev/null || true
    BUILD_HB_PID=""
  fi
}
# 前台管道保留所有阶段退出码；后台仅负责进度展示。
run_build_with_heartbeat() {
  local title="$1"
  shift
  local started="$(date +%s)" command_ec=0
  info_echo "开始：$title；心跳 ${HEARTBEAT_SECS}s"
  (
    while kill -0 $$ 2>/dev/null; do
      sleep "$HEARTBEAT_SECS"
      info_echo "[HB] $(date '+%F %T') 正在执行：$title"
    done
  ) &
  BUILD_HB_PID=$!
  if "$@" 2>&1 | flutter_command_output | tee -a "$BUILD_LOG" "$LOG_FILE"; then
    command_ec=0
  else
    command_ec=$?
  fi
  stop_build_heartbeat
  if (( command_ec != 0 )); then
    error_echo "$title 失败，退出码 $command_ec；构建日志：$BUILD_LOG"
    return "$command_ec"
  fi
  success_echo "$title 完成，耗时 $(( $(date +%s) - started ))s"
}
# 所有选项先校验，再执行工具链和网络操作。
parse_flutter_build_options() {
  BUILD_MODE="${BUILD_MODE:-release}"
  FLAVOR="${FLAVOR:-}"
  BUILD_TARGET="${BUILD_TARGET:-apk}"
  HEARTBEAT_SECS="${HEARTBEAT_SECS:-15}"
  OPEN_AFTER_BUILD="${OPEN_AFTER_BUILD:-1}"
  BUILD_BASE=""
  while (( $# > 0 )); do
    case "$1" in
      --mode|--flavor|--target)
        (( $# >= 2 )) && [[ "$2" != --* ]] || { error_echo "$1 缺少参数值。"; return 2; }
        case "$1" in
          --mode) BUILD_MODE="$2" ;;
          --flavor) FLAVOR="$2" ;;
          --target) BUILD_TARGET="$2" ;;
        esac
        shift 2
        ;;
      --)
        shift
        (( $# <= 1 )) && [[ -z "$BUILD_BASE" ]] || { error_echo '只能指定一个工程路径。'; return 2; }
        BUILD_BASE="${1:-}"
        break
        ;;
      -*) error_echo "未知参数：$1"; return 2 ;;
      *) [[ -z "$BUILD_BASE" ]] || { error_echo '只能指定一个工程路径。'; return 2; }; BUILD_BASE="$1"; shift ;;
    esac
  done
  case "$BUILD_MODE" in release|debug|profile) ;; *) error_echo "无效构建模式：$BUILD_MODE"; return 2 ;; esac
  case "$BUILD_TARGET" in apk|appbundle|all) ;; *) error_echo "无效 Android 产物类型：$BUILD_TARGET"; return 2 ;; esac
  [[ "$HEARTBEAT_SECS" == <1-> ]] || { error_echo 'HEARTBEAT_SECS 必须是正整数。'; return 2; }
}
# 复用并验证 JDK 17，不执行工具链升级。
ensure_project_java17() {
  local java_home_candidate="" java_version=""
  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]] &&
     "$JAVA_HOME/bin/java" -version 2>&1 | grep -Eq 'version "17([."]|$)'; then
    java_home_candidate="$JAVA_HOME"
  else
    java_home_candidate="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
    if [[ -z "$java_home_candidate" ]]; then
      for java_home_candidate in /opt/homebrew/opt/openjdk@17 /usr/local/opt/openjdk@17; do
        [[ -x "$java_home_candidate/bin/java" ]] && break
        java_home_candidate=""
      done
    fi
  fi
  [[ -n "$java_home_candidate" && -x "$java_home_candidate/bin/java" ]] || { error_echo '未找到可用 JDK 17，请先安装并配置 JAVA_HOME。'; return 1; }
  export JAVA_HOME="$java_home_candidate"
  export PATH="$JAVA_HOME/bin:$PATH"
  java_version="$(java -version 2>&1)" || { error_echo 'java -version 执行失败。'; return 1; }
  print -r -- "$java_version" | grep -Eq 'version "17([."]|$)' || { error_echo '当前 Java 主版本不是 17。'; return 1; }
  info_echo "JAVA_HOME：$JAVA_HOME"
  print -r -- "$java_version" | tee -a "$LOG_FILE"
}
# 按已校验的工程和参数执行业务，逐步传播失败状态。
run_original_logic() {
  setopt NO_NOMATCH PIPE_FAIL
  parse_flutter_build_options "$@" || return $?
  resolve_flutter_project "$BUILD_BASE" || return $?
  [[ -d "$FLUTTER_ROOT/android" && -f "$FLUTTER_ROOT/android/gradlew" ]] || { error_echo '工程缺少 android / gradlew，请先恢复 Android 平台。'; return 1; }
  choose_project_flutter || return $?
  ensure_project_java17 || return $?
  BUILD_LOG="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.build.log"
  : > "$BUILD_LOG" || return $?
  trap stop_build_heartbeat EXIT
  trap 'stop_build_heartbeat; exit 130' INT
  trap 'stop_build_heartbeat; exit 143' TERM
  run_build_with_heartbeat 'flutter pub get' "${FLUTTER_CMD[@]}" pub get || return $?
  local target="" output_dir="" found_file=""
  local -a targets=("$BUILD_TARGET") build_args=() outputs=()
  [[ "$BUILD_TARGET" == all ]] && targets=(apk appbundle)
  for target in "${targets[@]}"; do
    build_args=(build "$target" "--$BUILD_MODE")
    [[ -n "$FLAVOR" ]] && build_args+=(--flavor "$FLAVOR")
    run_build_with_heartbeat "flutter build $target" "${FLUTTER_CMD[@]}" "${build_args[@]}" || return $?
    if [[ "$target" == apk ]]; then
      output_dir="$FLUTTER_ROOT/build/app/outputs/flutter-apk"
    else
      output_dir="$FLUTTER_ROOT/build/app/outputs/bundle"
    fi
    [[ -d "$output_dir" ]] || { error_echo "命令结束但产物目录不存在：$output_dir"; return 1; }
    outputs=()
    while IFS= read -r -d '' found_file; do
      outputs+=("$found_file")
    done < <(find "$output_dir" -type f -name "*-$BUILD_MODE.${target/appbundle/aab}" -print0)
    (( ${#outputs[@]} > 0 )) || { error_echo "没有发现 $target 产物：$output_dir"; return 1; }
    for found_file in "${outputs[@]}"; do
      success_echo "产物：$found_file"
    done
    if [[ "$OPEN_AFTER_BUILD" == 1 ]]; then
      open "$output_dir" 2>/dev/null || warn_echo "无法打开产物目录：$output_dir"
    fi
  done
  success_echo "打包完成；构建日志：$BUILD_LOG"
}

# 初始化 Shell 和输出上下文。
# 在用户确认后初始化 Shell、当前进程 PATH 和日志。
initialize_script_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  export PATH="$HOME/.pub-cache/bin:$HOME/.fvm/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
  prepare_plain_output_context
  : > "$LOG_FILE" || { print -r -- "日志不可写：$LOG_FILE" >&2; exit 1; }
  LOG_READY=1
}
# 编排脚本的高层业务流程。
# 业务失败时立即结束入口，避免后续成功提示掩盖错误。
run_checked_business() {
  local business_ec=0
  if run_original_logic "$@"; then
    success_echo "脚本执行结束。日志：$LOG_FILE"
  else
    business_ec=$?
    error_echo "脚本执行失败，退出码：$business_ec。日志：$LOG_FILE"
    exit "$business_ec"
  fi
}
# 先完成自述确认，再准备运行环境并执行工程业务。
main() {
  show_script_intro_and_wait # 打印内置自述，终端模式确认后继续。
  initialize_script_runtime # 确认后初始化 Shell、PATH 和日志。
  run_checked_business "$@" # 执行业务，失败保留退出码并终止后续步骤。
}

main "$@"
