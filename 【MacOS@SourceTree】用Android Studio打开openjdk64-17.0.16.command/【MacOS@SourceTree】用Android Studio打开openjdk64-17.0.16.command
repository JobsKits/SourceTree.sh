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
  # Android Studio 启动脚本（SourceTree 友好版）
  # - 纯文本日志，无颜色/emoji
  # - 模块化函数，main 里统一调用
  # - 逻辑：进入目录 -> 初始化 jenv -> 确认/纳管 JDK17 -> 选择与激活 -> 诊断 -> 启动 Android Studio

  set -euo pipefail

  # ========================= 公共日志 =========================
  info() { echo "[INFO] $*"; }
  ok()   { echo "[OK]   $*"; }
  warn() { echo "[WARN] $*"; }
  err()  { echo "[ERR]  $*" >&2; }

  # ========================= 模块：工作目录 =========================
  WORKDIR=""
  init_workdir() {
    local target="${1:-$PWD}"
    if ! cd "$target" 2>/dev/null; then
      err "目标目录不存在：$target"
      exit 1
    fi
    WORKDIR="$(pwd -P)"
    info "工作目录：$WORKDIR"
  }

  # ========================= 模块：jenv 初始化 =========================
  init_jenv() {
    if ! command -v jenv >/dev/null 2>&1; then
      err "未检测到 jenv。请先安装：brew install jenv"
      exit 1
    fi
    eval "$(jenv init -)"
    # 可选插件：导出 JAVA_HOME；失败不阻断
    jenv enable-plugin export >/dev/null 2>&1 || true
    ok "jenv 已初始化"
  }

  # ========================= 模块：确保系统存在 JDK 17 =========================
  ensure_system_jdk17() {
    if ! /usr/libexec/java_home -v 17 >/dev/null 2>&1; then
      err "系统未安装 JDK 17；请先安装（Temurin 17 / Zulu 17 等）。"
      exit 1
    fi
    ok "检测到系统可用的 JDK 17"
  }

  # ========================= 模块：将 JDK 17 纳入 jenv 管理（幂等） =========================
  adopt_jdk17_into_jenv() {
    jenv add "$(/usr/libexec/java_home -v 17)" >/dev/null 2>&1 || true
    jenv rehash
    ok "JDK 17 已纳入 jenv（或已存在）"
  }

  # ========================= 模块：选择 jenv 内的 JDK 17 版本 =========================
  PICK_17=""
  select_jdk17() {
    # 兼容 openjdk/temurin/zulu 的命名；挑一个“名字里带 17”的版本
    PICK_17="$(jenv versions --bare | grep -E '(^|[[:space:]])(.*17(\.|$).*)' | head -n1 || true)"
    if [[ -z "${PICK_17:-}" ]]; then
      err "jenv 中未发现 JDK 17；请检查：jenv versions"
      exit 1
    fi
    ok "选择 JDK 版本：$PICK_17"
  }

  # ========================= 模块：激活 JDK 17（shell 级 + 目录锁定） =========================
  activate_jdk17() {
    jenv shell "$PICK_17"
    export JENV_VERSION="$PICK_17"
    export JAVA_HOME="$(jenv prefix)"
    export PATH="$JAVA_HOME/bin:$PATH"
    echo "$PICK_17" > .java-version
    ok "已激活 JDK 17，并写入 .java-version"
  }

  # ========================= 模块：诊断输出 =========================
  print_diagnostics() {
    info "JENV_VERSION=$JENV_VERSION"
    info "JAVA_HOME=$JAVA_HOME"
    java -version
  }

  # ========================= 模块：启动 Android Studio =========================
  open_android_studio() {
    local target_path="."

    # A) JetBrains CLI 启动器（可继承当前 shell 环境）
    if command -v studio >/dev/null 2>&1; then
      ok "使用 CLI 启动：studio ${target_path}"
      exec studio "${target_path}"
    fi

    # B) GUI .app（注意：GUI 可能不继承当前 shell 的 JAVA_HOME）
    local -a CANDIDATES=(
      "/Applications/Android Studio.app"
      "$HOME/Applications/Android Studio.app"
      "/Applications/Android Studio Beta.app"
      "$HOME/Applications/Android Studio Beta.app"
      "/Applications/Android Studio Preview.app"
      "$HOME/Applications/Android Studio Preview.app"
    )
    local app
    for app in "${CANDIDATES[@]}"; do
      if [[ -d "$app" ]]; then
        warn "未检测到 CLI 启动器，改用 GUI：$app"
        exec open -a "$app" "${target_path}"
      fi
    done

    # C) 都没有 → 打开官网下载
    warn "未找到 Android Studio，打开官网下载页面。"
    exec open "https://developer.android.com/studio"
  }

  # ========================= 主流程 =========================
  main() {
    init_workdir "${1:-$PWD}"
    init_jenv
    ensure_system_jdk17()
    adopt_jdk17_into_jenv
    select_jdk17
    activate_jdk17
    print_diagnostics
    open_android_studio
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
