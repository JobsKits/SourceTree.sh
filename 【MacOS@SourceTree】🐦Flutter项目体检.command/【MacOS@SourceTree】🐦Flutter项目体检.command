#!/bin/zsh
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
    "${HOME}/SourceTree.sh/${script_name}/${script_name}" \
    "${HOME}/Documents/Github/JobsGenesis/SourceTree.sh/${script_name}/${script_name}"; do
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
: > "$LOG_FILE"

# 识别 Sourcetree 自定义动作的瘦身运行环境，系统终端双击运行不降级。
is_sourcetree_runtime() {
  env | grep -Eqi '^SOURCETREE|^SOURCE_TREE' && return 0
  [[ "$0" != /* && "$SCRIPT_PATH" == "${HOME}/SourceTree.sh/"* ]] && return 0
  [[ "$0" != /* && "$SCRIPT_PATH" == "${HOME}/Documents/Github/JobsGenesis/SourceTree.sh/"* ]] && return 0

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
is_sourcetree_runtime && IS_SOURCETREE_RUNTIME=1

[[ -n "${TERM:-}" ]] || export TERM="dumb"
SOURCETREE_PLAIN_OUTPUT=0
if [[ "$IS_SOURCETREE_RUNTIME" == "1" || ! -t 1 || "$TERM" == "dumb" || -n "${NO_COLOR:-}" ]]; then
  SOURCETREE_PLAIN_OUTPUT=1
  export NO_COLOR="${NO_COLOR:-1}"
  export CLICOLOR="0"
  export ANSI_COLORS_DISABLED="1"
fi

strip_ansi_text() {
  perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}

log() {
  if [[ "${SOURCETREE_PLAIN_OUTPUT:-0}" == "1" ]]; then
    printf "%b\n" "$1" | strip_ansi_text | tee -a "$LOG_FILE"
  else
    printf "%b\n" "$1" | tee -a "$LOG_FILE"
  fi
}
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

  if [[ "${IS_SOURCETREE_RUNTIME:-0}" != "1" && -t 0 ]]; then
    read "?👉 已阅读脚本内置自述，按回车继续执行；按 Ctrl+C 取消..."
  else
    gray_echo "当前为 Sourcetree 或非交互输入环境，已跳过回车等待。"
  fi
}

run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  set -euo pipefail

  # ================================== 全局 ==================================
  SCRIPT_BASENAME="$(basename "$SCRIPT_PATH" | sed 's/\.[^.]*$//')"
  LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

  log()          { echo -e "$1" | tee -a "$LOG_FILE"; }
  success_echo() { log "✔ $1"; }
  error_echo()   { log "❌ $1"; }
  info_echo()    { log "ℹ $1"; }

  # ================================== 参数检查 ==================================
  check_args() {
    local PROJECT_DIR="${1:-}"
    local ACTION="${2:-doctor}"  # 可选: doctor | clean-get | pub-get

    if [[ -z "$PROJECT_DIR" ]]; then
      error_echo "请传入 Flutter 项目根目录"
      exit 1
    fi
    if [[ ! -f "$PROJECT_DIR/pubspec.yaml" ]]; then
      error_echo "目标目录不是 Flutter 项目：$PROJECT_DIR"
      exit 1
    fi

    echo "$PROJECT_DIR|$ACTION"
  }

  # ================================== 注入环境（为 SourceTree） ==================================
  ensure_env() {
    # SourceTree 下常见：不加载登录 shell，PATH 缺失 brew/fvm
    # Apple Silicon
    if [[ -x "/opt/homebrew/bin/brew" ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    # Intel
    if [[ -x "/usr/local/bin/brew" ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi

    # 常见本地 bin
    export PATH="$HOME/.fvm/bin:$HOME/.pub-cache/bin:$PATH"
  }

  # ================================== 工具链选择（FVM 优先） ==================================
  # 产出：全局数组 flutter_cmd dart_cmd
  typeset -ga flutter_cmd dart_cmd
  set_toolchain() {
    local dir="$1"
    cd "$dir"  # 必须先进入项目目录，FVM 才能读 .fvmrc

    # 1) 优先 fvm wrapper（识别 .fvmrc / .fvm）
    if command -v fvm >/dev/null 2>&1 && [[ -f ".fvmrc" || -d ".fvm" ]]; then
      flutter_cmd=(fvm flutter)
      dart_cmd=(fvm dart)
      info_echo "使用 FVM：$(fvm flutter --version | head -n1)"
      return
    fi

    # 2) 直接使用本地链接的 .fvm/flutter_sdk
    if [[ -x ".fvm/flutter_sdk/bin/flutter" ]]; then
      flutter_cmd=(".fvm/flutter_sdk/bin/flutter")
      dart_cmd=(".fvm/flutter_sdk/bin/dart")
      info_echo "使用本地 .fvm/flutter_sdk：$(".fvm/flutter_sdk/bin/flutter" --version | head -n1)"
      return
    fi

    # 3) 兜底：系统 flutter
    if command -v flutter >/dev/null 2>&1; then
      flutter_cmd=(flutter)
      dart_cmd=(dart)  # 会优先用 Flutter 自带 dart
      warn_echo() { log "⚠ $1"; }
      warn_echo "未检测到 FVM 环境，回退到系统 flutter：$(flutter --version | head -n1)"
      return
    fi

    error_echo "未找到可用的 Flutter。请安装 FVM 或配置 PATH。"
    exit 1
  }

  # ================================== 业务动作 ==================================
  run_doctor() {
    success_echo "进入目录：$(pwd)"
    log "开始执行 flutter doctor..."
    "${flutter_cmd[@]}" doctor | tee -a "$LOG_FILE"
    success_echo "执行完成 ✅"
  }

  run_clean_get() {
    success_echo "进入目录：$(pwd)"

    log "开始执行 flutter clean..."
    "${flutter_cmd[@]}" clean | tee -a "$LOG_FILE"

    log "开始执行 flutter pub get..."
    "${flutter_cmd[@]}" pub get | tee -a "$LOG_FILE"

    success_echo "执行完成 ✅"
  }

  run_pub_get_only() {
    success_echo "进入目录：$(pwd)"
    log "开始执行 flutter pub get..."
    "${flutter_cmd[@]}" pub get | tee -a "$LOG_FILE"
    success_echo "执行完成 ✅"
  }

  # ================================== 主函数 ==================================
  main() {
    local args; args=$(check_args "$@")
    local project_dir="${args%%|*}"
    local action="${args##*|}"

    ensure_env
    set_toolchain "$project_dir"

    case "$action" in
      doctor)     run_doctor ;;
      clean-get)  run_clean_get ;;
      pub-get)    run_pub_get_only ;;
      *)          error_echo "未知动作：$action（可选：doctor | clean-get | pub-get）"; exit 2 ;;
    esac
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
