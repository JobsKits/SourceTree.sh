#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】📦双击打包Flutter.iOS.command
# - 核心用途：执行“📦双击打包Flutter.iOS”对应的移动端项目自动化任务。
# - 影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。
# - 运行提示：运行后会先打印内置自述；Sourcetree 模式无交互连续执行，终端模式确认后继续。
# =====================================================================
# Jobs 标准化脚本外壳
# 说明：保留原脚本业务逻辑，补齐 README 防误触、彩色日志、zsh 入口、Homebrew 健康自检标准。
# =====================================================================
# Sourcetree 自定义动作可能只传脚本名，不传绝对路径；这里兜底找回真实脚本位置。
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
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
# 识别 Sourcetree 自定义动作的瘦身运行环境，系统终端双击运行不降级。
is_sourcetree_runtime() {
  env | grep -Eqi '^SOURCETREE|^SOURCE_TREE' && return 0
  [[ "$0" != /* && "$SCRIPT_PATH" == "${HOME}/SourceTree.command/"* ]] && return 0
  [[ "$0" != /* && "$SCRIPT_PATH" == "${HOME}/Documents/Github/JobsGenesis/SourceTree.command/"* ]] && return 0

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
# 统一输出终端信息并同步记录日志。
log() {
  if [[ "${SOURCETREE_PLAIN_OUTPUT:-0}" == "1" ]]; then
    printf "%b\n" "$1" | strip_ansi_text | tee -a "$LOG_FILE"
  else
    printf "%b\n" "$1" | tee -a "$LOG_FILE"
  fi
}
# 输出 color echo 对应级别的日志信息。
color_echo()     { log "\033[1;32m$1\033[0m"; }
# 输出 info echo 对应级别的日志信息。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 输出 success echo 对应级别的日志信息。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 输出 warn echo 对应级别的日志信息。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 输出 warm echo 对应级别的日志信息。
warm_echo()      { log "\033[1;33m$1\033[0m"; }
# 输出 note echo 对应级别的日志信息。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 输出 error echo 对应级别的日志信息。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 输出 err echo 对应级别的日志信息。
err_echo()       { log "\033[1;31m$1\033[0m"; }
# 输出 debug echo 对应级别的日志信息。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
# 输出 highlight echo 对应级别的日志信息。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 输出 gray echo 对应级别的日志信息。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 输出 bold echo 对应级别的日志信息。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 输出 underline echo 对应级别的日志信息。
underline_echo() { log "\033[4m$1\033[0m"; }
# ============================= 标准工具函数 =============================
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
show_readme_and_wait() {
  if typeset -f is_sourcetree_runtime >/dev/null 2>&1 && is_sourcetree_runtime; then
    IS_SOURCETREE_RUNTIME=1
  fi
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" != "1" && -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 =============================="
  note_echo "脚本名称：${SCRIPT_BASENAME}.command"
  note_echo "脚本路径：${SCRIPT_PATH}"
  note_echo "运行入口：兼容系统终端双击运行和 Sourcetree 自定义动作运行。"
  note_echo "核心行为：按脚本名称执行对应的 SourceTree 效率动作，运行前会先展示这段内置自述，避免误触。"
  note_echo "环境策略：系统终端保留清屏、彩色输出和回车确认；Sourcetree 瘦身环境自动跳过清屏和等待，并输出纯文本日志。"
  note_echo "文档关系：同目录 README.md 只作为外部说明文档保留，运行时自述不读取、不拼接、不依赖 README.md。"
  warn_echo "继续前请确认 SourceTree 传入路径、当前仓库或拖入路径正确；按 Ctrl+C 可以取消。"
  gray_echo "日志文件：${LOG_FILE}"
  highlight_echo "======================================================================="
  echo ""

  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" ]]; then
    gray_echo "已识别为 Sourcetree 自定义动作，将跳过交互并连续执行。"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    error_echo "当前不是 Sourcetree，且没有可交互输入；请在终端中重新运行。"
    return 1
  fi
  read "?👉 已阅读脚本内置自述，按回车继续执行；按 Ctrl+C 取消..."
}
# 执行 run original logic 对应的独立业务步骤。
run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  # 【SourceTree 专用】Flutter iOS 打包（自动发现子项目，纯文本；全局心跳 + 分阶段耗时）

  set -euo pipefail

  # ================= 日志/工具 =================
  SCRIPT_BASENAME="macos_sourcetree_build_ios"
  LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"; : > "$LOG_FILE"
  BUILD_LOG="/tmp/flutter_build_ios.log"; : > "$BUILD_LOG"
  # 统一输出终端信息并同步记录日志。
  log()      { echo "$1" | tee -a "$LOG_FILE"; }
  # 输出 info 对应级别的日志信息。
  info()     { log "[INFO] $*"; }
  # 封装 ok 对应的独立处理逻辑。
  ok()       { log "[OK]   $*"; }
  # 输出 warn 对应级别的日志信息。
  warn()     { log "[WARN] $*"; }
  # 输出 err 对应级别的日志信息。
  err()      { log "[ERR]  $*" >&2; }
  # 封装 hr 对应的独立处理逻辑。
  hr()       { log "----------------------------------------------------------------"; }
  # 封装 section 对应的独立处理逻辑。
  section()  { hr; log "== $* =="; hr; }
  # 封装 ts 对应的独立处理逻辑。
  ts()       { date "+%Y-%m-%d %H:%M:%S"; }

  HEARTBEAT_SECS="${HEARTBEAT_SECS:-15}"   # 心跳间隔（秒）
  OPEN_AFTER_BUILD="${OPEN_AFTER_BUILD:-1}" # 1=成功后打开产物目录
  STEP="init"

  # ======== 全局存活心跳（无论卡哪都能看到） ========
  HB_PID=""
  # 封装 start global hb 对应的独立处理逻辑。
  start_global_hb() {
    (
      while :; do
        sleep "$HEARTBEAT_SECS"
        echo "[HB] $(ts) alive pid=$$ step=$STEP" | tee -a "$LOG_FILE"
      done
    ) & HB_PID=$!
  }
  # 封装 stop global hb 对应的独立处理逻辑。
  stop_global_hb() { [[ -n "${HB_PID:-}" ]] && kill "$HB_PID" 2>/dev/null || true; }
  # 封装 cleanup 对应的独立处理逻辑。
  cleanup() { stop_global_hb; }
  trap cleanup EXIT INT TERM

  # ================= 选项 =================
  BUILD_MODE="${BUILD_MODE:-release}"   # release | debug | profile
  FLAVOR="${FLAVOR:-}"                  # 可为空

  # 命令行覆盖
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)   BUILD_MODE="${2:-$BUILD_MODE}"; shift 2;;
      --flavor) FLAVOR="${2:-$FLAVOR}";         shift 2;;
      --)       shift; break;;
      *)        break;;
    esac
  done

  BASE_DIR="${1:-$PWD}"
  # ================= 辅助函数 =================
  is_flutter_root() { [[ -f "$1/pubspec.yaml" && -d "$1/lib" ]]; }
  # 带心跳的长任务执行器（阶段心跳 + 耗时 + 保留退出码）
  run_with_heartbeat() {
    local title="$1"; shift
    local wdir="$1"; shift
    local start=$(date +%s)
    STEP="$title"

    section "$title"
    info "start: $(ts)"
    info "workdir: $wdir"
    info "heartbeat: ${HEARTBEAT_SECS}s"

    (
      cd "$wdir" && "$@"
    ) 2>&1 | tee -a "$BUILD_LOG" &
    local pid=$!

    (
      while kill -0 "$pid" 2>/dev/null; do
        sleep "$HEARTBEAT_SECS"
        kill -0 "$pid" 2>/dev/null || break
        echo "[HB] $(ts) running: $title (pid=$pid)" | tee -a "$LOG_FILE"
      done
    ) & local local_hb=$!

    wait "$pid"; local ec=$?
    kill "$local_hb" 2>/dev/null || true

    local end=$(date +%s)
    local dur=$(( end - start ))
    if [[ $ec -eq 0 ]]; then
      ok "$title done (duration ${dur}s)"
    else
      err "$title failed (duration ${dur}s, ec=$ec). See $BUILD_LOG"
    fi
    return $ec
  }
  # ================= 定位 Flutter 项目（自动向下搜索） =================
  resolve_flutter_root() {
    STEP="resolve"
    local base="$1"
    if ! cd "$base" 2>/dev/null; then
      err "无法进入目录：$base"; exit 1
    fi
    base="$(pwd -P)"
    section "定位 Flutter 项目"
    info "基准目录：$base"

    if is_flutter_root "$base"; then
      FLUTTER_ROOT="$base"; ok "命中：$FLUTTER_ROOT"; return 0
    fi

    local hit
    hit="$(/usr/bin/find "$base" -name pubspec.yaml -type f -print 2>/dev/null | head -n1 || true)"
    if [[ -n "$hit" ]]; then
      FLUTTER_ROOT="$(dirname "$hit")"
      if is_flutter_root "$FLUTTER_ROOT"; then
        ok "在子目录中找到：$FLUTTER_ROOT"; return 0
      fi
    fi

    err "未找到 Flutter 项目（缺 pubspec.yaml 或 lib/）"
    exit 1
  }
  # ================= 选择 flutter 命令 =================
  choose_flutter_cmd() {
    STEP="choose_flutter"
    if command -v fvm >/dev/null 2>&1 && [[ -f "$FLUTTER_ROOT/.fvm/fvm_config.json" ]]; then
      FLUTTER_CMD=("fvm" "flutter"); info "使用：fvm flutter"
    else
      FLUTTER_CMD=("flutter"); info "使用：flutter"
    fi
  }
  # ================= 环境检查 =================
  check_env() {
    STEP="check_env"
    section "检查 Xcode / CocoaPods"
    if ! command -v xcodebuild >/dev/null 2>&1; then
      err "未检测到 Xcode（xcodebuild）。请安装 Xcode 并同意许可（首次需运行一次 xcodebuild）。"
      exit 1
    fi
    if ! command -v pod >/dev/null 2>&1; then
      warn "未检测到 CocoaPods（pod）。如项目使用 Pods，构建可能失败。"
    fi
    ok "环境检查完成"
  }
  # ================= 版本打印（安全，不早退） =================
  print_versions() {
    STEP="versions"
    section "环境版本"
    set +e
    info "xcodebuild -version："
    xcodebuild -version | tee -a "$LOG_FILE" || true

    info "flutter --version："
    (cd "$FLUTTER_ROOT" && "${FLUTTER_CMD[@]}" --version) | tee -a "$LOG_FILE" || true

    # 兼容新旧：优先静默试 flutter dart，失败再试系统 dart
    if (cd "$FLUTTER_ROOT" && "${FLUTTER_CMD[@]}" dart --version >/dev/null 2>&1); then
      info "flutter dart --version："
      (cd "$FLUTTER_ROOT" && "${FLUTTER_CMD[@]}" dart --version) | tee -a "$LOG_FILE" || true
    elif command -v dart >/dev/null 2>&1; then
      info "dart --version："
      dart --version | tee -a "$LOG_FILE" || true
    else
      warn "未检测到 dart 命令（新版本 Flutter 已移除 'flutter dart' 子命令）"
    fi
    set -e
  }
  # ================= pub get & build ipa =================
  pub_get()   { run_with_heartbeat "flutter pub get" "$FLUTTER_ROOT" "${FLUTTER_CMD[@]}" pub get; }
  # 执行 build ios 对应的独立业务步骤。
  build_ios() {
    local args=(build ipa "--$BUILD_MODE")
    [[ -n "$FLAVOR" ]] && args+=(--flavor "$FLAVOR")
    run_with_heartbeat "flutter build ipa ($BUILD_MODE${FLAVOR:+ / flavor=$FLAVOR})" \
                       "$FLUTTER_ROOT" "${FLUTTER_CMD[@]}" "${args[@]}"
  }
  # ================= 打开产物（存在才开） =================
  open_if_exists() {
    local p="$1"
    if [[ -e "$p" ]]; then
      info "打开：$p"
      open "$p" 2>/dev/null || true
    else
      warn "不存在：$p"
    fi
  }
  # 执行 open outputs 对应的独立业务步骤。
  open_outputs() {
    STEP="open_outputs"
    local ipa_dir="$FLUTTER_ROOT/build/ios/ipa"
    local first_ipa=""
    if [[ -d "$ipa_dir" ]]; then
      first_ipa="$(/usr/bin/find "$ipa_dir" -type f -name '*.ipa' -print 2>/dev/null | head -n1 || true)"
    fi

    if [[ -n "$first_ipa" ]]; then
      ok "已生成 IPA：$(basename "$first_ipa")"
      [[ "$OPEN_AFTER_BUILD" == "1" ]] && open_if_exists "$ipa_dir"
      return 0
    fi

    local archive_dir="$FLUTTER_ROOT/build/ios/archive"
    local first_archive=""
    if [[ -d "$archive_dir" ]]; then
      first_archive="$(/usr/bin/find "$archive_dir" -type d -name '*.xcarchive' -print 2>/dev/null | head -n1 || true)"
    fi

    if [[ -n "$first_archive" ]]; then
      ok "生成了 xcarchive：$(basename "$first_archive")"
      [[ "$OPEN_AFTER_BUILD" == "1" ]] && open_if_exists "$archive_dir"
      return 0
    fi

    warn "未发现 IPA 或 xcarchive。请查看构建日志：$BUILD_LOG"
  }
  # ================= 主流程 =================
  main() {
    start_global_hb

    section "启动参数"
    info "mode=$BUILD_MODE  flavor=${FLAVOR:-<none>}  heartbeat=${HEARTBEAT_SECS}s"
    info "脚本日志：$LOG_FILE"
    info "构建日志：$BUILD_LOG"

    resolve_flutter_root "$BASE_DIR"
    choose_flutter_cmd
    check_env
    print_versions
    pub_get   || { err "pub get 失败，见：$BUILD_LOG"; exit 1; }
    build_ios || { err "构建失败，见：$BUILD_LOG"; exit 1; }

    if [[ -d "$FLUTTER_ROOT/build/ios" ]]; then
      section "产物列表：$FLUTTER_ROOT/build/ios"
      (cd "$FLUTTER_ROOT/build/ios" && ls -lhR) | tee -a "$LOG_FILE" || true
    fi

    open_outputs
    ok "完成。构建日志：$BUILD_LOG ；脚本日志：$LOG_FILE"
    STEP="done"
  }

  main "$@"

  # =========================== 原脚本业务逻辑区结束 ===========================
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  : > "$LOG_FILE"
  is_sourcetree_runtime && IS_SOURCETREE_RUNTIME=1
  [[ -n "${TERM:-}" ]] || export TERM="dumb"
  if [[ "$IS_SOURCETREE_RUNTIME" == "1" || ! -t 1 || "$TERM" == "dumb" || -n "${NO_COLOR:-}" ]]; then
    SOURCETREE_PLAIN_OUTPUT=1
    export NO_COLOR="${NO_COLOR:-1}"
    export CLICOLOR="0"
    export ANSI_COLORS_DISABLED="1"
  fi
}
# 编排脚本的高层业务流程。
main() {
  # 展示脚本内置自述，并按运行入口完成防误触确认。
  show_readme_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 执行 run_original_logic 对应的核心业务步骤。
  run_original_logic "$@"
  # 输出脚本执行结果、摘要和日志位置。
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
