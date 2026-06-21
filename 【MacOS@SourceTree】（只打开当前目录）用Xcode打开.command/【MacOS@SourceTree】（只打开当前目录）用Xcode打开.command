#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】（只打开当前目录）用Xcode打开.command
# - 核心用途：执行“（只打开当前目录）用Xcode打开”对应的移动端项目自动化任务。
# - 影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。
# - 运行提示：运行后会先打印内置自述；Sourcetree 模式无交互连续执行，终端模式确认后继续。
# =====================================================================
# Jobs 标准化脚本外壳
# 说明：SourceTree 自定义动作：只检测当前目录，用 Xcode 打开当前仓库中的 .xcworkspace / .xcodeproj。
# =====================================================================

# SourceTree 由 macOS GUI 启动时经常没有 UTF-8 locale，中文脚本名/中文日志容易乱码。
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
# 统一 zsh 行为；避免路径中含 [] 等字符时触发 nomatch。
# 解析并返回 resolve script path 所需信息。
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
# 封装 supports color 对应的独立处理逻辑。
supports_color() {
  [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]
}
# 统一输出终端信息并同步记录日志。
log() {
  print -r -- "$1" | tee -a "$LOG_FILE"
}
# 封装 color log 对应的独立处理逻辑。
color_log() {
  local code="$1"
  local message="$2"
  if supports_color; then
    printf "\033[%sm%s\033[0m\n" "$code" "$message" | tee -a "$LOG_FILE"
  else
    print -r -- "$message" | tee -a "$LOG_FILE"
  fi
}
# 输出 color echo 对应级别的日志信息。
color_echo()     { color_log "1;32" "$1"; }
# 输出 info echo 对应级别的日志信息。
info_echo()      { color_log "1;34" "ℹ $1"; }
# 输出 success echo 对应级别的日志信息。
success_echo()   { color_log "1;32" "✔ $1"; }
# 输出 warn echo 对应级别的日志信息。
warn_echo()      { color_log "1;33" "⚠ $1"; }
# 输出 warm echo 对应级别的日志信息。
warm_echo()      { color_log "1;33" "$1"; }
# 输出 note echo 对应级别的日志信息。
note_echo()      { color_log "1;35" "➤ $1"; }
# 输出 error echo 对应级别的日志信息。
error_echo()     { color_log "1;31" "✖ $1"; }
# 输出 err echo 对应级别的日志信息。
err_echo()       { color_log "1;31" "$1"; }
# 输出 debug echo 对应级别的日志信息。
debug_echo()     { color_log "1;35" "🐞 $1"; }
# 输出 highlight echo 对应级别的日志信息。
highlight_echo() { color_log "1;36" "🔹 $1"; }
# 输出 gray echo 对应级别的日志信息。
gray_echo()      { color_log "0;90" "$1"; }
# 输出 bold echo 对应级别的日志信息。
bold_echo()      { color_log "1" "$1"; }
# 输出 underline echo 对应级别的日志信息。
underline_echo() { color_log "4" "$1"; }
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
# 判断 is interactive terminal 对应条件是否成立。
is_interactive_terminal() {
  [[ -t 0 && -t 1 ]]
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
  # ============================== 基本配置 ==============================
  umask 022
  LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"; : > "$LOG_FILE"
  # 统一输出终端信息并同步记录日志。
  log()  { echo "$*"; echo "$*" >>"$LOG_FILE"; }
  # 输出 info 对应级别的日志信息。
  info() { log "ℹ️  $*"; }
  # 封装 ok 对应的独立处理逻辑。
  ok()   { log "✅ $*"; }
  # 输出 warn 对应级别的日志信息。
  warn() { log "⚠️  $*"; }
  # 输出 err 对应级别的日志信息。
  err()  { log "❌ $*"; }

  # 修复 SourceTree 的精简 PATH。
  export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

  # 可选：强制只开 .xcodeproj（1=只开 project；默认=0）。
  FORCE_XCODEPROJ="${FORCE_XCODEPROJ:-0}"

  # ============================== 入口路径 ==============================
  local root_candidate="${REPO:-${1:-$PWD}}"
  root_candidate="${root_candidate//\"/}"
  [[ "$root_candidate" != "/" ]] && root_candidate="${root_candidate%/}"

  ROOT="$(abs_path "$root_candidate")" || { err "路径无效：$root_candidate"; return 1; }
  [[ -d "$ROOT" ]] || { err "路径不是目录：$ROOT"; return 1; }
  cd "$ROOT" || { err "无法进入目录：$ROOT"; return 1; }
  ROOT="$PWD"
  REPO_NAME="$(/usr/bin/basename "$ROOT")"
  ok "仓库根目录：$ROOT（仅检测当前目录，不递归）"
  # ============================== 工具函数 ==============================
  resolve_cmd(){
    for c in "$@"; do
      command -v "$c" >/dev/null 2>&1 && { echo "$c"; return; }
      [[ -x "$c" ]] && { echo "$c"; return; }
    done
    return 1
  }
  # 封装 do pod install 对应的独立处理逻辑。
  do_pod_install(){
    local dir="$1"
    if command -v bundle >/dev/null 2>&1 && [[ -f "$dir/Gemfile" ]]; then
      info "bundle exec pod install @ $dir"
      (cd "$dir" && bundle exec pod install)
    else
      local pod_cmd
      pod_cmd="$(resolve_cmd pod /opt/homebrew/bin/pod /usr/local/bin/pod)" || { warn "未找到 pod，跳过"; return 127; }
      info "pod install @ $dir"
      (cd "$dir" && "$pod_cmd" install)
    fi
  }
  # 执行 open in xcode 对应的独立业务步骤。
  open_in_xcode(){
    local target="$1"
    [[ -e "$target" ]] || { err "打开目标不存在：$target"; return 1; }
    info "打开：$target"
    /usr/bin/open -a "Xcode" "$target"
  }
  # 判断 has workspace 对应条件是否成立。
  has_workspace(){
    local dir="$1"
    local proj="$2"
    local prefer="$dir/$(/usr/bin/basename "$proj" .xcodeproj).xcworkspace"
    [[ -d "$prefer" ]] && return 0
    /usr/bin/find "$dir" -maxdepth 1 -type d -name "*.xcworkspace" -print -quit | grep -q .
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

  # ============================== 仅当前目录查找 .xcodeproj ==============================
  PROJ_LIST=()
  FIND_OUT="$(/usr/bin/find "$ROOT" -maxdepth 1 -type d -name "*.xcodeproj" -print 2>/dev/null || true)"
  [[ -n "$FIND_OUT" ]] && PROJ_LIST=("${(@f)FIND_OUT}")
  [[ ${#PROJ_LIST[@]} -gt 0 ]] || { err "当前目录未找到任何 .xcodeproj"; return 2; }

  # ============================== 评分选择最佳工程（无交互，当前目录内） ==============================
  BEST_PROJ=""
  BEST_SCORE=999999
  for proj in "${PROJ_LIST[@]}"; do
    local dir="$(/usr/bin/dirname "$proj")"
    local base="$(/usr/bin/basename "$proj" .xcodeproj)"
    local score=0
    has_workspace "$dir" "$proj" && (( score -= 100 ))             # workspace 优先
    [[ -f "$dir/Podfile" ]] && (( score -= 10 ))                   # 有 Podfile 次优
    [[ "$base" == "$REPO_NAME" ]] && (( score -= 5 ))             # 工程名=仓库名，微调
    (( score += ${#proj} / 1000 ))                                  # 稳定排序
    if (( score < BEST_SCORE )); then
      BEST_SCORE=$score
      BEST_PROJ="$proj"
    fi
  done

  TARGET_PROJ="$BEST_PROJ"
  TARGET_DIR="$(/usr/bin/dirname "$TARGET_PROJ")"
  ok "选中工程：$TARGET_PROJ"

  # ============================== 打开逻辑 ==============================
  PODFILE="$TARGET_DIR/Podfile"

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
# 执行入口下沉后的完整业务流程和控制逻辑。
run_main_business_flow() {
  run_original_logic "$@"
  local exit_code=$?
  if (( exit_code == 0 )); then
    success_echo "脚本执行结束。日志：$LOG_FILE"
  else
    error_echo "脚本执行失败，退出码：$exit_code。日志：$LOG_FILE"
  fi
  return $exit_code
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  emulate -L zsh
  setopt NO_NOMATCH
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
  # 执行入口下沉后的完整业务流程。
  run_main_business_flow "$@"
}

main "$@"
