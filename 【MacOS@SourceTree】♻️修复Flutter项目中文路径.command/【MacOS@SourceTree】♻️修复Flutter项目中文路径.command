#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】♻️修复Flutter项目中文路径.command
# - 核心用途：修复自有 Dart package 指令里的 URI 编码中文路径。
# - 影响范围：仅处理 lib、test、integration_test，原文件保存在每次独立的 .import_backup 子目录。
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
# 封装 strip ansi text 对应的独立处理逻辑。
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
# 统一输出终端信息并同步记录日志。
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
# 封装 abs path 对应的独立处理逻辑。
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
# 收集并校验 ask run 对应的用户确认。
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
# 收集并校验 confirm yes 对应的用户确认。
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
# 封装 inject shellenv block 对应的独立处理逻辑。
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
# 封装 activate homebrew shellenv 对应的独立处理逻辑。
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
# 执行 run brew health update 对应的独立业务步骤。
run_brew_health_update() {
  info_echo "正在执行 Homebrew 健康更新..."
  brew update  || { error_echo "brew update 失败"; return 1; }
  brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
  brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
  brew doctor  || warn_echo "brew doctor 有警告，请按输出处理"
  brew -v      || warn_echo "打印 brew 版本失败，可忽略"
  success_echo "Homebrew 健康更新完成"
}
# 准备并配置 install homebrew 对应的运行条件。
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
# 封装 brew install or upgrade 对应的独立处理逻辑。
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
# 输出 show readme and wait 对应的说明与结果。
show_script_intro_and_wait() {
  prepare_script_metadata
  if [[ -z "${NO_COLOR+x}" && "${IS_SOURCETREE_RUNTIME:-0}" != "1" && -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" && "${PLAIN_OUTPUT:-0}" != 1 ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 ==============================" | jobs_intro_style title
  note_echo "脚本名称：${SCRIPT_BASENAME}.command" | jobs_intro_style title
  note_echo "脚本路径：${SCRIPT_PATH}" | jobs_intro_style body
  note_echo "运行入口：兼容系统终端双击运行和 Sourcetree 自定义动作运行。" | jobs_intro_style body
  note_echo "核心用途：修复自有 Dart package 指令里的 URI 编码中文路径。" | jobs_intro_style body
  warn_echo "影响范围：仅处理 lib、test、integration_test，原文件保存在每次独立的 .import_backup 子目录。" | jobs_intro_style body
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
# 执行 run original logic 对应的独立业务步骤。
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
# 只解码 package 指令中的连续 UTF-8 高位字节，保留引号、斜杠等 ASCII 转义。
repair_package_directives() {
  perl -MEncode=decode,FB_CROAK -0777 -pe '
    sub unicode_path {
      my ($text) = @_;
      $text =~ s{((?:%[89a-fA-F][0-9a-fA-F])+)}{
        my $encoded = $1;
        my $bytes = $encoded;
        $bytes =~ s/%([0-9a-fA-F]{2})/chr(hex($1))/ge;
        my $decoded = eval { decode("UTF-8", $bytes, FB_CROAK) };
        defined($decoded) ? Encode::encode("UTF-8", $decoded) : $encoded;
      }ge;
      return $text;
    }
    s{^([ \t]*(?:import|export|part)[ \t]+(["\x27])package:)([^"\x27\r\n]*)(\2)}{$1 . unicode_path($3) . $4}gme;
  ' "$1"
}
# 对输入只解除外层引号和拖拽转义，保留目录内原有引号。
normalize_flutter_input() {
  local input_value="$1"
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
# 只解码 package 指令中的连续 UTF-8 高位字节，保留引号、斜杠等 ASCII 转义。
repair_package_directives() {
  perl -MEncode=decode,FB_CROAK -0777 -pe '
    sub unicode_path {
      my ($text) = @_;
      $text =~ s{((?:%[89a-fA-F][0-9a-fA-F])+)}{
        my $encoded = $1;
        my $bytes = $encoded;
        $bytes =~ s/%([0-9a-fA-F]{2})/chr(hex($1))/ge;
        my $decoded = eval { decode("UTF-8", $bytes, FB_CROAK) };
        defined($decoded) ? Encode::encode("UTF-8", $decoded) : $encoded;
      }ge;
      return $text;
    }
    s{^([ \t]*(?:import|export|part)[ \t]+(["\x27])package:)([^"\x27\r\n]*)(\2)}{$1 . unicode_path($3) . $4}gme;
  ' "$1"
}
# 按已校验的工程和参数执行业务，逐步传播失败状态。
run_original_logic() {
  setopt NO_NOMATCH PIPE_FAIL
  (( $# <= 1 )) || { error_echo "用法：脚本 [Flutter 工程目录]"; return 2; }
  command -v perl >/dev/null 2>&1 || { error_echo "缺少系统 Perl，无法安全修复 UTF-8 路径。"; return 1; }
  resolve_flutter_project "${1:-}" || return $?
  local source_file="" relative_file="" staged_file="" changed=0 skipped=0
  local backup_root="$FLUTTER_ROOT/.import_backup/$(date +%Y%m%d_%H%M%S)_$$"
  local -a source_roots=()
  for source_file in lib test integration_test; do
    [[ -d "$FLUTTER_ROOT/$source_file" && ! -L "$FLUTTER_ROOT/$source_file" ]] && source_roots+=("$FLUTTER_ROOT/$source_file")
  done
  while IFS= read -r -d '' source_file; do
    if [[ "$source_file" == *.g.dart || "$source_file" == *.freezed.dart || "$source_file" == *.mocks.dart ]] ||
       head -n 80 "$source_file" | grep -Eqi 'GENERATED CODE|DO NOT (EDIT|MODIFY)|Created by ' &&
       { [[ "$source_file" == *.g.dart || "$source_file" == *.freezed.dart || "$source_file" == *.mocks.dart ]] ||
         ! head -n 80 "$source_file" | grep -Eqi 'Created by Jobs'; }; then
      skipped=$((skipped + 1))
      continue
    fi
    relative_file="${source_file#$FLUTTER_ROOT/}"
    grep -Eq '^[[:space:]]*(import|export|part)[[:space:]]+["\x27]package:.*%[89a-fA-F][0-9a-fA-F]' "$source_file" || continue
    mkdir -p "$backup_root/${relative_file:h}" || return $?
    staged_file="$backup_root/$relative_file.decoded"
    repair_package_directives "$source_file" > "$staged_file" || return $?
    if cmp -s "$source_file" "$staged_file"; then
      rm -f -- "$staged_file"
      continue
    fi
    cp -p "$source_file" "$backup_root/$relative_file" || return $?
    cat "$staged_file" > "$source_file" || return $?
    rm -f -- "$staged_file"
    changed=$((changed + 1))
    info_echo "修复：$relative_file"
  done < <(find "${source_roots[@]}" \( -type d \( -name .git -o -name node_modules -o -name Pods -o -name PodsManual -o -name 'ManualBy*Pods*' -o -name .dart_tool -o -name build -o -name DerivedData -o -name .import_backup -o -name vendor -o -name third_party -o -name ThirdParty \) -prune \) -o \( -type f -name '*.dart' -print0 \))
  success_echo "修复文件：$changed；跳过生成 / 第三方文件：$skipped"
  (( changed == 0 )) || info_echo "原文件备份：$backup_root"
  return 0
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
