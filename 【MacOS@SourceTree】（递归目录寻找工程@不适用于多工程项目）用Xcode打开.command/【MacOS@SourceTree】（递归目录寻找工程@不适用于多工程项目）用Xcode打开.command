#!/bin/zsh
# =====================================================================
# Jobs 标准化脚本外壳
# 说明：SourceTree 自定义动作：递归查找当前仓库中的 .xcodeproj，并用 Xcode 打开对应 .xcworkspace / .xcodeproj。
# 注意：递归模式会自动评分选择一个工程，不适合真正的多工程仓库。
# =====================================================================

# SourceTree 由 macOS GUI 启动时经常没有 UTF-8 locale，中文脚本名/中文日志容易乱码。
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

# 统一 zsh 行为；避免路径中含 [] 等字符时触发 nomatch。
emulate -L zsh
setopt NO_NOMATCH

resolve_script_path() {
  local src="${(%):-%x}"
  [[ -z "$src" ]] && src="$0"

  if [[ "$src" == /* ]]; then
    print -r -- "${src:A}"
  else
    print -r -- "${PWD:A}/${src}"
  fi
}

SCRIPT_PATH="$(resolve_script_path)"
SCRIPT_DIR="${SCRIPT_PATH:h}"
SCRIPT_BASENAME="$(/usr/bin/basename "$SCRIPT_PATH" | sed 's/\.[^.]*$//')"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
: > "$LOG_FILE"

supports_color() {
  [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]
}

log() {
  print -r -- "$1" | tee -a "$LOG_FILE"
}

color_log() {
  local code="$1"
  local message="$2"
  if supports_color; then
    printf "\033[%sm%s\033[0m\n" "$code" "$message" | tee -a "$LOG_FILE"
  else
    print -r -- "$message" | tee -a "$LOG_FILE"
  fi
}

color_echo()     { color_log "1;32" "$1"; }
info_echo()      { color_log "1;34" "ℹ $1"; }
success_echo()   { color_log "1;32" "✔ $1"; }
warn_echo()      { color_log "1;33" "⚠ $1"; }
warm_echo()      { color_log "1;33" "$1"; }
note_echo()      { color_log "1;35" "➤ $1"; }
error_echo()     { color_log "1;31" "✖ $1"; }
err_echo()       { color_log "1;31" "$1"; }
debug_echo()     { color_log "1;35" "🐞 $1"; }
highlight_echo() { color_log "1;36" "🔹 $1"; }
gray_echo()      { color_log "0;90" "$1"; }
bold_echo()      { color_log "1" "$1"; }
underline_echo() { color_log "4" "$1"; }

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

  if [[ ! -t 0 ]]; then
    note_echo "当前为非交互环境，自动跳过"
    return 1
  fi

  local input=""
  IFS= read -r "input?➤ "
  [[ -n "$input" ]]
}

confirm_yes() {
  echo ""
  warn_echo "⚠ $1"
  gray_echo "危险操作必须输入 YES 后回车；其它输入一律取消。"

  if [[ ! -t 0 ]]; then
    warn_echo "当前为非交互环境，自动取消危险操作"
    return 1
  fi

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

is_interactive_terminal() {
  [[ -t 0 && -t 1 ]]
}

show_readme_and_wait() {
  # SourceTree 自定义动作没有可交互 TTY：不能 clear，也不能 read 阻塞，否则会出现
  # “TERM environment variable not set.” 或 read 直接 EOF。双击 / 终端运行时才显示 README。
  if ! is_interactive_terminal; then
    info_echo "检测到 SourceTree / 非交互环境，跳过 README 展示与回车阻塞"
    return 0
  fi

  if [[ -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    clear
  fi

  local readme_path="${SCRIPT_DIR}/README.md"
  if [[ -f "$readme_path" ]]; then
    highlight_echo "正在显示脚本自述文件：$readme_path"
    echo ""
    cat "$readme_path" | tee -a "$LOG_FILE"
  else
    warn_echo "未找到 README.md：$readme_path"
    gray_echo "当前脚本路径：$SCRIPT_PATH"
  fi
  echo ""
  read "?👉 请先阅读上面的自述文件，按回车继续执行，或按 Ctrl+C 取消..."
}

run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  # ============================== 基本配置 ==============================
  umask 022
  LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"; : > "$LOG_FILE"

  log()  { print -r -- "$*"; print -r -- "$*" >>"$LOG_FILE"; }
  info() { log "ℹ️  $*"; }
  ok()   { log "✅ $*"; }
  warn() { log "⚠️  $*"; }
  err()  { log "❌ $*"; }

  # 修复 SourceTree 的精简 PATH。
  export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

  # 可选：强制只开 .xcodeproj（1=只开 project；默认=0）。
  FORCE_XCODEPROJ="${FORCE_XCODEPROJ:-0}"

  # ============================== 入口路径 ==============================
  local root_candidate="${REPO:-${1:-$PWD}}"
  root_candidate="${root_candidate//\"/}"
  [[ "$root_candidate" != "/" ]] && root_candidate="${root_candidate%/}"

  local ROOT=""
  ROOT="$(abs_path "$root_candidate")" || { err "路径无效：$root_candidate"; return 1; }
  [[ -d "$ROOT" ]] || { err "路径不是目录：$ROOT"; return 1; }
  cd "$ROOT" || { err "无法进入目录：$ROOT"; return 1; }
  ROOT="$PWD"
  local REPO_NAME="$(/usr/bin/basename "$ROOT")"
  ok "仓库根目录：$ROOT（递归检测子目录；不适用于多工程项目）"

  # ============================== 工具函数 ==============================
  resolve_cmd(){
    for c in "$@"; do
      command -v "$c" >/dev/null 2>&1 && { echo "$c"; return; }
      [[ -x "$c" ]] && { echo "$c"; return; }
    done
    return 1
  }

  do_pod_install(){
    local dir="$1"
    if command -v bundle >/dev/null 2>&1 && [[ -f "$dir/Gemfile" ]]; then
      info "bundle exec pod install @ $dir"
      (cd "$dir" && bundle exec pod install)
    else
      local pod_cmd=""
      pod_cmd="$(resolve_cmd pod /opt/homebrew/bin/pod /usr/local/bin/pod)" || { warn "未找到 pod，跳过"; return 127; }
      info "pod install @ $dir"
      (cd "$dir" && "$pod_cmd" install)
    fi
  }

  open_in_xcode(){
    local target="$1"
    [[ -e "$target" ]] || { err "打开目标不存在：$target"; return 1; }
    info "打开：$target"
    /usr/bin/open -a "Xcode" "$target"
  }

  depth(){
    local candidate="$1"
    local rel="${candidate#$ROOT/}"
    echo "$rel" | awk -F'/' '{print NF}'
  }

  has_workspace(){
    local dir="$1"
    local proj="$2"
    local prefer="$dir/$(/usr/bin/basename "$proj" .xcodeproj).xcworkspace"
    [[ -d "$prefer" ]] && return 0
    /usr/bin/find "$dir" -maxdepth 1 -type d -name "*.xcworkspace" -print -quit 2>/dev/null | grep -q .
  }

  # --- 清除 SwiftPM 缓存的隔离标记（解决 devicekit-manifest 被拦截） ---
  clear_spm_quarantine() {
    if [[ -d "$HOME/Library/org.swift.swiftpm" ]]; then
      xattr -dr com.apple.quarantine "$HOME/Library/org.swift.swiftpm" 2>/dev/null || true
    fi
    if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
      /usr/bin/find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 3 -type d -name "SourcePackages" -print0 2>/dev/null \
        | xargs -0 xattr -dr com.apple.quarantine 2>/dev/null || true
    fi
    /usr/bin/find "$HOME/Library/Developer" -type f -name "devicekit-manifest" -perm -111 -print0 2>/dev/null \
      | xargs -0 xattr -dr com.apple.quarantine 2>/dev/null || true
  }

  # --- 显式解析 SwiftPM，确保 Package Dependencies 出现 ---
  resolve_swiftpm_for_workspace() {
    local ws="$1"
    local scheme=""
    local json=""

    command -v xcodebuild >/dev/null 2>&1 || { warn "缺少 xcodebuild，跳过 SwiftPM 解析"; return 0; }

    json="$(xcodebuild -workspace "$ws" -list -json 2>/dev/null || true)"
    if [[ -n "$json" && -x "/usr/bin/python3" ]]; then
      scheme="$(/usr/bin/python3 -c '
import json
import sys
try:
    data = json.loads(sys.argv[1] if len(sys.argv) > 1 else "")
except Exception:
    print("")
    sys.exit(0)
schemes = ((data.get("workspace") or {}).get("schemes") or [])
cands = [s for s in schemes if not str(s).lower().startswith("pods")]
print(cands[0] if cands else (schemes[0] if schemes else ""))
' "$json" 2>/dev/null || true)"
    fi

    if [[ -n "$scheme" ]]; then
      info "解析 SwiftPM：scheme=$scheme"
      xcodebuild -quiet -resolvePackageDependencies -workspace "$ws" -scheme "$scheme" >/dev/null 2>&1 || \
        warn "xcodebuild 解析 SwiftPM 失败（可忽略）"
    else
      warn "未找到可用 Scheme，跳过 SwiftPM 解析"
    fi
  }

  # 统一动作：打开 workspace（先清隔离 → 解析 SPM → open）。
  open_workspace_properly() {
    local ws="$1"
    clear_spm_quarantine
    resolve_swiftpm_for_workspace "$ws"
    open_in_xcode "$ws"
  }

  # ============================== 递归查找 .xcodeproj ==============================
  local FIND_OUT=""
  local -a PROJ_LIST
  PROJ_LIST=()

  FIND_OUT="$(/usr/bin/find "$ROOT" \
    \( \
      -path "*/Pods" -o \
      -path "*/.git" -o \
      -path "*/build" -o \
      -path "*/DerivedData" -o \
      -path "*/node_modules" -o \
      -path "*/vendor" -o \
      -path "*/third_party" \
    \) -prune -o \
    -type d -name "*.xcodeproj" -print 2>/dev/null || true)"

  [[ -n "$FIND_OUT" ]] && PROJ_LIST=("${(@f)FIND_OUT}")
  [[ ${#PROJ_LIST[@]} -gt 0 ]] || { err "未找到任何 .xcodeproj"; return 2; }

  if (( ${#PROJ_LIST[@]} > 1 )); then
    warn "递归模式发现多个 .xcodeproj，将按评分自动选择一个。该模式不适用于多工程项目。"
    local p=""
    for p in "${PROJ_LIST[@]}"; do
      info "候选工程：$p"
    done
  fi

  # ============================== 评分选择最佳工程（无交互） ==============================
  local BEST_PROJ=""
  local BEST_SCORE=999999
  local proj=""
  for proj in "${PROJ_LIST[@]}"; do
    local dir="$(/usr/bin/dirname "$proj")"
    local base="$(/usr/bin/basename "$proj" .xcodeproj)"
    local score=0
    has_workspace "$dir" "$proj" && (( score -= 100 ))             # workspace 优先
    [[ -f "$dir/Podfile" ]] && (( score -= 10 ))                   # 有 Podfile 次优
    (( score += $(depth "$proj") ))                                # 距根越浅越好
    [[ "$base" == "$REPO_NAME" ]] && (( score -= 5 ))             # 工程名=仓库名，微调
    (( score += ${#proj} / 1000 ))                                  # 稳定排序
    if (( score < BEST_SCORE )); then
      BEST_SCORE=$score
      BEST_PROJ="$proj"
    fi
  done

  local TARGET_PROJ="$BEST_PROJ"
  local TARGET_DIR="$(/usr/bin/dirname "$TARGET_PROJ")"
  ok "选中工程：$TARGET_PROJ"

  # ============================== 打开逻辑 ==============================
  local PODFILE="$TARGET_DIR/Podfile"

  # 如需强制只开 .xcodeproj（想看“项目视图 + Package Dependencies”而非 Pods 工程）。
  if [[ "$FORCE_XCODEPROJ" == "1" ]]; then
    ok "FORCE_XCODEPROJ=1，强制打开 .xcodeproj"
    open_in_xcode "$TARGET_PROJ"
    return $?
  fi

  if [[ -f "$PODFILE" ]]; then
    local prefer="$TARGET_DIR/$(/usr/bin/basename "$TARGET_PROJ" .xcodeproj).xcworkspace"
    local ws=""

    if [[ -d "$prefer" ]]; then
      open_workspace_properly "$prefer"
      return $?
    fi

    ws="$(/usr/bin/find "$TARGET_DIR" -maxdepth 1 -type d -name "*.xcworkspace" -print -quit 2>/dev/null || true)"
    if [[ -n "$ws" ]]; then
      open_workspace_properly "$ws"
      return $?
    fi

    warn "存在 Podfile 但无 .xcworkspace，执行 pod install..."
    if do_pod_install "$TARGET_DIR"; then
      if [[ -d "$prefer" ]]; then
        open_workspace_properly "$prefer"
        return $?
      fi
      ws="$(/usr/bin/find "$TARGET_DIR" -maxdepth 1 -type d -name "*.xcworkspace" -print -quit 2>/dev/null || true)"
      if [[ -n "$ws" ]]; then
        open_workspace_properly "$ws"
        return $?
      fi
      warn "pod install 后仍无 .xcworkspace，回退打开 .xcodeproj"
      open_in_xcode "$TARGET_PROJ"
      return $?
    else
      warn "pod install 失败，回退打开 .xcodeproj"
      open_in_xcode "$TARGET_PROJ"
      return $?
    fi
  fi

  # 无 Podfile → 直接打开 .xcodeproj。
  open_in_xcode "$TARGET_PROJ"
  return $?

  # =========================== 原脚本业务逻辑区结束 ===========================
}

main() {
  show_readme_and_wait
  run_original_logic "$@"
  local exit_code=$?
  if (( exit_code == 0 )); then
    success_echo "脚本执行结束。日志：$LOG_FILE"
  else
    error_echo "脚本执行失败，退出码：$exit_code。日志：$LOG_FILE"
  fi
  return $exit_code
}

main "$@"
