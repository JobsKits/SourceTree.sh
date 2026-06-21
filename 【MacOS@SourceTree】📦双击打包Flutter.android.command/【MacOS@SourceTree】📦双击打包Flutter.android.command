#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】📦双击打包Flutter.android.command
# - 核心用途：执行“📦双击打包Flutter.android”对应的移动端项目自动化任务。
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
# 封装 strip_ansi_text 对应的独立处理逻辑。
strip_ansi_text() {
  perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}
# 按当前输出级别记录终端信息，并同步写入脚本日志。
log() {
  if [[ "${SOURCETREE_PLAIN_OUTPUT:-0}" == "1" ]]; then
    printf "%b\n" "$1" | strip_ansi_text | tee -a "$LOG_FILE"
  else
    printf "%b\n" "$1" | tee -a "$LOG_FILE"
  fi
}
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log "\033[1;32m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log "\033[1;33m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err_echo()       { log "\033[1;31m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
underline_echo() { log "\033[4m$1\033[0m"; }
# ============================= 标准工具函数 =============================
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
# 执行已经拆分完成的独立业务步骤。
run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  # 【SourceTree 专用】Flutter Android 打包（自动发现子项目；纯文本；带心跳与阶段标记）
  set -euo pipefail

  # ---------------- 基本日志 ----------------
  SCRIPT_BASENAME="$(basename "$SCRIPT_PATH" | sed 's/\.[^.]*$//')"
  LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"; : > "$LOG_FILE"
  BUILD_LOG="/tmp/flutter_build_log.txt"; : > "$BUILD_LOG"
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  log()  { echo "$1" | tee -a "$LOG_FILE"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  info() { log "[INFO] $*"; }
  # 封装 ok 对应的独立处理逻辑。
  ok()   { log "[OK]   $*"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  warn() { log "[WARN] $*"; }
  # 按当前输出级别记录终端信息，并同步写入脚本日志。
  err()  { log "[ERR]  $*" >&2; }
  # 封装 ts 对应的独立处理逻辑。
  ts()   { date "+%Y-%m-%d %H:%M:%S"; }
  # 封装 hr 对应的独立处理逻辑。
  hr()   { log "----------------------------------------------------------------"; }
  # 封装 section 对应的独立处理逻辑。
  section(){ hr; log "== $* =="; hr; }

  HEARTBEAT_SECS="${HEARTBEAT_SECS:-15}"     # 心跳间隔（秒）
  OPEN_AFTER_BUILD="${OPEN_AFTER_BUILD:-1}"   # 1=构建成功后自动 open 产物目录

  # ---------------- 参数/环境 ----------------
  BUILD_TARGET="${BUILD_TARGET:-apk}"       # apk | appbundle | all
  BUILD_MODE="${BUILD_MODE:-release}"       # release | debug | profile
  FLAVOR="${FLAVOR:-}"                      # 可为空

  # 支持命令行覆盖
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)  BUILD_TARGET="${2:-$BUILD_TARGET}"; shift 2;;
      --mode)    BUILD_MODE="${2:-$BUILD_MODE}";     shift 2;;
      --flavor)  FLAVOR="${2:-$FLAVOR}";             shift 2;;
      --)        shift; break;;
      *)         break;;
    esac
  done

  REPO_DIR="${1:-$PWD}"
  # ---------------- 小工具 ----------------
  is_flutter_root() { [[ -f "$1/pubspec.yaml" && -d "$1/lib" ]]; }
  # 安全执行（带心跳、统计耗时、正确保留退出码；输出同时写入 LOG_FILE/BUILD_LOG）
  # 用法：run_with_heartbeat "标题" 目录 cmd args...
  run_with_heartbeat() {
    local title="$1"; shift
    local wdir="$1"; shift
    local start_ts=$(date +%s)
    section "$title"
    info "start: $(ts)"
    info "workdir: $wdir"
    info "heartbeat: ${HEARTBEAT_SECS}s"

    # 启动命令
    (
      cd "$wdir" && "$@"
    ) 2>&1 | tee -a "$BUILD_LOG" &
    local cmd_pid=$!

    # 心跳
    (
      while kill -0 "$cmd_pid" 2>/dev/null; do
        sleep "$HEARTBEAT_SECS"
        kill -0 "$cmd_pid" 2>/dev/null || break
        log "[HB] $(ts) running: $title (pid=$cmd_pid)"
      done
    ) & local hb_pid=$!

    # 等待
    wait "$cmd_pid"; ec=$?
    kill "$hb_pid" 2>/dev/null || true

    local end_ts=$(date +%s)
    local dur=$(( end_ts - start_ts ))
    if [[ $ec -eq 0 ]]; then
      ok "$title done (duration ${dur}s)"
    else
      err "$title failed (duration ${dur}s, ec=$ec). See $BUILD_LOG"
    fi
    return $ec
  }
  # ---------------- 解析 Flutter 根目录（自动向下搜索） ----------------
  resolve_flutter_root() {
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
    err "未找到 Flutter 项目（缺 pubspec.yaml 或 lib/）"; exit 1
  }
  # ---------------- 选择 flutter 命令 ----------------
  choose_flutter_cmd() {
    if command -v fvm >/dev/null 2>&1 && [[ -f "$FLUTTER_ROOT/.fvm/fvm_config.json" ]]; then
      FLUTTER_CMD=("fvm" "flutter"); info "使用：fvm flutter"
    else
      FLUTTER_CMD=("flutter"); info "使用：flutter"
    fi
  }
  # ---------------- Java 环境（固定 JDK17） ----------------
  ensure_java17() {
    section "Java 环境"
    if /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
      export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
      export PATH="$JAVA_HOME/bin:$PATH"
    else
      for p in /opt/homebrew/opt/openjdk@17 /usr/local/opt/openjdk@17; do
        if [[ -d "$p" && -x "$p/bin/java" ]]; then
          export JAVA_HOME="$p"; export PATH="$JAVA_HOME/bin:$PATH"; break
        fi
      done
    fi
    if ! command -v java >/dev/null 2>&1; then
      err "未检测到 JDK 17（java 不可用）。请安装 Temurin/Zulu/OpenJDK 17。"; exit 1
    fi
    ok "JAVA_HOME = $JAVA_HOME"
    info "java -version："; java -version | tee -a "$LOG_FILE" || true
  }
  # ---------------- 版本打印（防早退） ----------------
  print_versions() {
    section "环境版本"
    set +e
    if [[ -x "$FLUTTER_ROOT/android/gradlew" ]]; then
      info "Gradle Wrapper："
      (cd "$FLUTTER_ROOT/android" && ./gradlew -v) | tee -a "$LOG_FILE" || true
    else
      warn "未找到 $FLUTTER_ROOT/android/gradlew"
    fi
    local agp=""
    if [[ -f "$FLUTTER_ROOT/android/build.gradle" ]]; then
      agp="$(grep -Eo 'com\.android\.tools\.build:gradle:[0-9.]+' \
            "$FLUTTER_ROOT/android/build.gradle" 2>/dev/null | head -n1 | cut -d: -f3 || true)"
    fi
    if [[ -z "$agp" && -f "$FLUTTER_ROOT/android/settings.gradle" ]]; then
      agp="$(grep -Eo "com\.android\.application['\"]?[[:space:]]+version[[:space:]]+['\"]?[0-9.]+" \
            "$FLUTTER_ROOT/android/settings.gradle" 2>/dev/null | head -n1 \
            | grep -Eo '[0-9]+(\.[0-9]+){1,2}' || true)"
    fi
    set -e
    [[ -n "$agp" ]] && info "AGP：$agp" || warn "未检测到 AGP 版本"
  }
  # ---------------- pub get & build ----------------
  pub_get() {
    run_with_heartbeat "flutter pub get" "$FLUTTER_ROOT" "${FLUTTER_CMD[@]}" pub get
  }
  # 封装 build_one 对应的独立处理逻辑。
  build_one() {
    local target="$1"
    local args=(build "$target" "--$BUILD_MODE")
    [[ -n "$FLAVOR" ]] && args+=(--flavor "$FLAVOR")
    run_with_heartbeat "flutter build $target ($BUILD_MODE ${FLAVOR:+/ flavor=$FLAVOR})" \
                       "$FLUTTER_ROOT" "${FLUTTER_CMD[@]}" "${args[@]}"
  }
  # ---------------- 打开产物目录（存在才开） ----------------
  open_if_exists() {
    local p="$1"
    if [[ "$OPEN_AFTER_BUILD" != "1" ]]; then return 0; fi
    if [[ -d "$p" ]]; then info "打开目录：$p"; open "$p" 2>/dev/null || true
    else warn "目录不存在：$p"; fi
  }
  # ---------------- 主流程 ----------------
  main() {
    section "启动参数"
    info "target=$BUILD_TARGET  mode=$BUILD_MODE  flavor=${FLAVOR:-<none>}  heartbeat=${HEARTBEAT_SECS}s"
    info "脚本日志：$LOG_FILE"
    info "构建日志：$BUILD_LOG"

    resolve_flutter_root "$REPO_DIR"
    choose_flutter_cmd
    ensure_java17
    print_versions
    pub_get

    case "$BUILD_TARGET" in
      apk)        build_one apk        || { err "APK 构建失败（见 $BUILD_LOG）"; exit 1; } ;;
      appbundle)  build_one appbundle  || { err "AAB 构建失败（见 $BUILD_LOG）"; exit 1; } ;;
      all)
        build_one apk       || { err "APK 构建失败（见 $BUILD_LOG）"; exit 1; }
        build_one appbundle || { err "AAB 构建失败（见 $BUILD_LOG）"; exit 1; }
        ;;
      *) warn "未知 BUILD_TARGET=$BUILD_TARGET，回退到 apk"; build_one apk || { err "APK 构建失败（见 $BUILD_LOG）"; exit 1; } ;;
    esac

    # 列出产物，并在存在时打开目录
    if [[ -d "$FLUTTER_ROOT/build/app/outputs" ]]; then
      section "产物列表"
      (cd "$FLUTTER_ROOT/build/app/outputs" && ls -lhR) | tee -a "$LOG_FILE" || true
    fi
    [[ "$BUILD_TARGET" == "apk" || "$BUILD_TARGET" == "all" ]] \
      && open_if_exists "$FLUTTER_ROOT/build/app/outputs/flutter-apk"
    [[ "$BUILD_TARGET" == "appbundle" || "$BUILD_TARGET" == "all" ]] \
      && open_if_exists "$FLUTTER_ROOT/build/app/outputs/bundle/$BUILD_MODE"

    ok "完成。构建日志：$BUILD_LOG ；脚本日志：$LOG_FILE"
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
