#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】📦双击自动生成ipa文件.command
# - 核心用途：把与选定工程匹配的现有真机 App，或明确指定的 App，重新封装为 IPA。
# - 影响范围：不执行编译和重签名，不使用其它工程的最新 App；输出独立文件，保留已有 IPA。
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
  note_echo "核心用途：把与选定工程匹配的现有真机 App，或明确指定的 App，重新封装为 IPA。" | jobs_intro_style body
  warn_echo "影响范围：不执行编译和重签名，不使用其它工程的最新 App；输出独立文件，保留已有 IPA。" | jobs_intro_style body
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

IPA_TEMP_DIR=""
# 只清理本流程创建的独立 IPA 临时目录。
cleanup_ipa_staging() {
  [[ -n "$IPA_TEMP_DIR" && -d "$IPA_TEMP_DIR" && "$IPA_TEMP_DIR" == "${TMPDIR:-/tmp}"/jobs_ipa.* ]] || return 0
  rm -rf -- "$IPA_TEMP_DIR"
}
# 校验 IPA 配置、来源和输出参数。
parse_ipa_options() {
  IPA_CONFIG=Release
  IPA_OUT_DIR="$HOME/Desktop"
  IPA_PROJECT=""
  IPA_APP=""
  IPA_BASE=""
  while (( $# > 0 )); do
    case "$1" in
      --config|--out|--project|--app)
        (( $# >= 2 )) && [[ "$2" != --* ]] || { error_echo "$1 缺少参数值。"; return 2; }
        case "$1" in
          --config) IPA_CONFIG="$2" ;;
          --out) IPA_OUT_DIR="$2" ;;
          --project) IPA_PROJECT="$2" ;;
          --app) IPA_APP="$2" ;;
        esac
        shift 2
        ;;
      -h|--help)
        print -r -- '用法：脚本 [仓库目录] [--project 工程或工作区] [--app 已构建的真机.app] [--config Debug|Release] [--out 输出目录]'
        return 3
        ;;
      --)
        shift
        (( $# <= 1 )) && [[ -z "$IPA_BASE" ]] || { error_echo '只能指定一个仓库目录。'; return 2; }
        IPA_BASE="${1:-}"
        break
        ;;
      -*) error_echo "未知参数：$1"; return 2 ;;
      *) [[ -z "$IPA_BASE" ]] || { error_echo '只能指定一个仓库目录。'; return 2; }; IPA_BASE="$1"; shift ;;
    esac
  done
  case "$IPA_CONFIG" in Debug|Release) ;; *) error_echo '构建配置必须是 Debug 或 Release。'; return 2 ;; esac
}
# 使用 NUL 分隔收集工程，多个工作区 / 工程不能任取第一个。
resolve_ipa_project() {
  local base="${IPA_BASE:-${REPO:-$PWD}}" found_project=""
  local -a workspaces=() projects=()
  if [[ -n "$IPA_PROJECT" ]]; then
    [[ -d "$IPA_PROJECT" && ( "$IPA_PROJECT" == *.xcodeproj || "$IPA_PROJECT" == *.xcworkspace ) ]] || { error_echo "无效工程路径：$IPA_PROJECT"; return 1; }
    IPA_PROJECT="${IPA_PROJECT:A}"
    return 0
  fi
  [[ -d "$base" ]] || { error_echo "仓库目录不存在：$base"; return 1; }
  base="${base:A}"
  [[ "$base" != / && "$base" != "$HOME" ]] || { error_echo '请指定具体工程目录。'; return 1; }
  while IFS= read -r -d '' found_project; do
    case "$found_project" in
      *.xcworkspace) workspaces+=("$found_project") ;;
      *.xcodeproj) projects+=("$found_project") ;;
    esac
  done < <(find "$base" -maxdepth 3 \( -type d \( -name .git -o -name Pods -o -name PodsManual -o -name 'ManualBy*Pods*' -o -name .dart_tool -o -name build -o -name DerivedData -o -name node_modules \) -prune \) -o \( -type d \( -name '*.xcworkspace' -o -name '*.xcodeproj' \) -print0 -prune \))
  if (( ${#workspaces[@]} == 1 )); then
    IPA_PROJECT="${workspaces[1]}"
  elif (( ${#workspaces[@]} > 1 )); then
    error_echo '发现多个工作区，请用 --project 明确选择。'
    return 1
  elif (( ${#projects[@]} == 1 )); then
    IPA_PROJECT="${projects[1]}"
  else
    error_echo "工程候选数量：${#projects[@]}，请用 --project 明确选择。"
    return 1
  fi
}
# DerivedData 的 WorkspacePath 必须与选定工程匹配，禁止使用其它工程的最新产物。
resolve_existing_device_app() {
  if [[ -n "$IPA_APP" ]]; then
    IPA_APP="${IPA_APP:A}"
    return 0
  fi
  resolve_ipa_project || return $?
  local derived_dir="$HOME/Library/Developer/Xcode/DerivedData" derived_entry="" workspace_path="" app_candidate=""
  local -a app_candidates=()
  for derived_entry in "$derived_dir"/*(N/); do
    [[ -f "$derived_entry/Info.plist" ]] || continue
    workspace_path="$(/usr/libexec/PlistBuddy -c 'Print :WorkspacePath' "$derived_entry/Info.plist" 2>/dev/null || true)"
    [[ -n "$workspace_path" ]] || continue
    workspace_path="${workspace_path:A}"
    [[ "$workspace_path" == "$IPA_PROJECT" || ( "$IPA_PROJECT" == *.xcodeproj && "$workspace_path" == "$IPA_PROJECT/project.xcworkspace" ) ]] || continue
    for app_candidate in "$derived_entry/Build/Products/$IPA_CONFIG-iphoneos"/*.app(N/); do
      app_candidates+=("$app_candidate")
    done
  done
  if (( ${#app_candidates[@]} != 1 )); then
    error_echo "选定工程的 $IPA_CONFIG 真机 App 候选数量：${#app_candidates[@]}。请先完成对应构建，或用 --app 明确指定。"
    for app_candidate in "${app_candidates[@]}"; do
      gray_echo "候选：$app_candidate"
    done
    return 1
  fi
  IPA_APP="${app_candidates[1]}"
}
# 核对现有 App 的真机平台、类型和可执行文件。
validate_device_app() {
  [[ -d "$IPA_APP" && "$IPA_APP" == *.app && -f "$IPA_APP/Info.plist" ]] || { error_echo "无效 App：$IPA_APP"; return 1; }
  local platform="" executable="" bundle_type=""
  platform="$(/usr/libexec/PlistBuddy -c 'Print :DTPlatformName' "$IPA_APP/Info.plist" 2>/dev/null || true)"
  if [[ "$platform" != iphoneos ]]; then
    /usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms' "$IPA_APP/Info.plist" 2>/dev/null | grep -Fq iPhoneOS || { error_echo '只接受 iPhoneOS 真机 App，不能将模拟器 App 当作安装 IPA。'; return 1; }
  fi
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$IPA_APP/Info.plist" 2>/dev/null || true)"
  [[ -n "$executable" && "$executable" != */* && -f "$IPA_APP/$executable" ]] || { error_echo 'App 缺少有效 CFBundleExecutable。'; return 1; }
  bundle_type="$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$IPA_APP/Info.plist" 2>/dev/null || true)"
  [[ "$bundle_type" == APPL ]] || { error_echo '目标不是应用程序 App bundle。'; return 1; }
}
# 按已校验的工程和参数执行业务，逐步传播失败状态。
run_original_logic() {
  setopt NO_NOMATCH PIPE_FAIL
  local parse_ec=0
  parse_ipa_options "$@" || parse_ec=$?
  (( parse_ec == 3 )) && return 0
  (( parse_ec == 0 )) || return "$parse_ec"
  command -v ditto >/dev/null 2>&1 || { error_echo '缺少 macOS ditto。'; return 1; }
  resolve_existing_device_app || return $?
  validate_device_app || return $?
  mkdir -p "$IPA_OUT_DIR" || return $?
  IPA_OUT_DIR="${IPA_OUT_DIR:A}"
  local ipa_name="" ipa_destination=""
  ipa_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$IPA_APP/Info.plist" 2>/dev/null || true)"
  [[ -n "$ipa_name" ]] || ipa_name="${IPA_APP:t:r}"
  ipa_name="${ipa_name//\//_}"
  ipa_name="${ipa_name//:/_}"
  ipa_name="${ipa_name//$'\n'/_}"
  ipa_name="${ipa_name//$'\r'/_}"
  [[ -n "$ipa_name" && "$ipa_name" != . && "$ipa_name" != .. ]] || { error_echo '无效 IPA 文件名。'; return 1; }
  IPA_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jobs_ipa.XXXXXX")" || return $?
  trap cleanup_ipa_staging EXIT
  trap 'cleanup_ipa_staging; exit 130' INT
  trap 'cleanup_ipa_staging; exit 143' TERM
  mkdir -p "$IPA_TEMP_DIR/Payload" || return $?
  ditto "$IPA_APP" "$IPA_TEMP_DIR/Payload/${IPA_APP:t}" || return $?
  ipa_destination="$IPA_OUT_DIR/${ipa_name}_$(date '+%Y.%m.%d %H-%M-%S')_${IPA_TEMP_DIR:t}.ipa"
  info_echo "真机 App：$IPA_APP"
  info_echo "仅重新打包现有 App，不执行构建、重签名或 App Store 导出。"
  (cd "$IPA_TEMP_DIR" && /usr/bin/zip -qry "$IPA_TEMP_DIR/output.ipa" Payload) || return $?
  mv -n "$IPA_TEMP_DIR/output.ipa" "$ipa_destination" || return $?
  [[ ! -e "$IPA_TEMP_DIR/output.ipa" && -s "$ipa_destination" ]] || { error_echo "IPA 发布失败或文件名冲突：$ipa_destination"; return 1; }
  success_echo "IPA：$ipa_destination"
  open -R "$ipa_destination" 2>/dev/null || true
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
