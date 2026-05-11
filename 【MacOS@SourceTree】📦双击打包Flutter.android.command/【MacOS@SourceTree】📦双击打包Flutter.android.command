#!/bin/zsh
# =====================================================================
# Jobs 标准化脚本外壳
# 说明：保留原脚本业务逻辑，补齐 README 防误触、彩色日志、zsh 入口、Homebrew 健康自检标准。
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME="$(basename "$0" | sed 's/\.[^.]*$//')"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
: > "$LOG_FILE"

log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
color_echo()     { log "\033[1;32m$1\033[0m"; }
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
warm_echo()      { log "\033[1;33m$1\033[0m"; }
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
err_echo()       { log "\033[1;31m$1\033[0m"; }
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
gray_echo()      { log "\033[0;90m$1\033[0m"; }
bold_echo()      { log "\033[1m$1\033[0m"; }
underline_echo() { log "\033[4m$1\033[0m"; }

# ============================= 标准工具函数 =============================
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}

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

ask_run() {
  echo ""
  note_echo "👉 $1"
  gray_echo "【回车=跳过，输入任意字符后回车=执行】"
  local input=""
  IFS= read -r "input?➤ "
  [[ -n "$input" ]]
}

confirm_yes() {
  echo ""
  warn_echo "⚠ $1"
  gray_echo "危险操作必须输入 YES 后回车；其它输入一律取消。"
  local input=""
  IFS= read -r "input?➤ "
  [[ "$input" == "YES" ]]
}

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

run_brew_health_update() {
  info_echo "正在执行 Homebrew 健康更新..."
  brew update  || { error_echo "brew update 失败"; return 1; }
  brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
  brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
  brew doctor  || warn_echo "brew doctor 有警告，请按输出处理"
  brew -v      || warn_echo "打印 brew 版本失败，可忽略"
  success_echo "Homebrew 健康更新完成"
}

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

show_readme_and_wait() {
  clear
  local readme_path="${SCRIPT_DIR}/README.md"
  if [[ -f "$readme_path" ]]; then
    highlight_echo "正在显示脚本自述文件：$readme_path"
    echo ""
    cat "$readme_path" | tee -a "$LOG_FILE"
  else
    warn_echo "未找到 README.md：$readme_path"
  fi
  echo ""
  read "?👉 请先阅读上面的自述文件，按回车继续执行，或按 Ctrl+C 取消..."
}

run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  # 【SourceTree 专用】Flutter Android 打包（自动发现子项目；纯文本；带心跳与阶段标记）
  set -euo pipefail

  # ---------------- 基本日志 ----------------
  SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
  LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"; : > "$LOG_FILE"
  BUILD_LOG="/tmp/flutter_build_log.txt"; : > "$BUILD_LOG"

  log()  { echo "$1" | tee -a "$LOG_FILE"; }
  info() { log "[INFO] $*"; }
  ok()   { log "[OK]   $*"; }
  warn() { log "[WARN] $*"; }
  err()  { log "[ERR]  $*" >&2; }

  ts()   { date "+%Y-%m-%d %H:%M:%S"; }
  hr()   { log "----------------------------------------------------------------"; }
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

main() {
  show_readme_and_wait
  run_original_logic "$@"
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
