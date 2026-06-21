#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】♻️修复Flutter项目中文路径.command
# - 核心用途：执行“♻️修复Flutter项目中文路径”对应的移动端项目自动化任务。
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
  # 【MacOS】修复 Flutter 项目中 import 中文被 URI 编码的路径（SourceTree 专用 / 无颜色无 emoji）
  set -euo pipefail
  [[ "${DEBUG:-0}" == "1" ]] && set -x

  export LC_ALL=en_US.UTF-8
  export LANG=en_US.UTF-8

  # 错误输出
  SCRIPT_BASENAME="$(basename "$SCRIPT_PATH" | sed 's/\.[^.]*$//')"
  LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"; : > "$LOG_FILE"
  trap '
    code=$?
    script_path=${0:A}
    echo "✖ 失败（退出码 $code） at ${script_path}:${LINENO}"
    [[ ${#funcfiletrace[@]} -gt 0 ]] && { echo "—— 调用栈 ——"; print -l -- "${(F)funcfiletrace}"; }
    echo "—— 日志尾部（最近 80 行）——"; tail -n 80 "$LOG_FILE" 2>/dev/null || true
    exit $code
  ' ERR

  # SourceTree 下补 PATH
  export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
  # 输出函数（纯文本）
  log()        { echo "$1" | tee -a "$LOG_FILE"; }
  # 输出 info echo 对应级别的日志信息。
  info_echo()  { log "[INFO] $1"; }
  # 输出 success echo 对应级别的日志信息。
  success_echo(){ log "[OK]   $1"; }
  # 输出 warn echo 对应级别的日志信息。
  warn_echo()  { log "[WARN] $1"; }
  # 输出 error echo 对应级别的日志信息。
  error_echo() { log "[ERR]  $1"; }
  # 输出 debug echo 对应级别的日志信息。
  debug_echo() { [[ "${DEBUG:-0}" == "1" ]] && log "[DBG]  $1"; }
  # 判断 Flutter 项目
  is_flutter_project_root() { [[ -f "$1/pubspec.yaml" && -d "$1/lib" ]]; }

  # 解析项目根（参数/REPO 优先，找不到就全仓库搜索）
  typeset -g FLUTTER_ROOT=""
  typeset -g ENTRY_FILE=""
  # 解析并返回 resolve project root 所需信息。
  resolve_project_root() {
    set +e
    local arg="${1:-}" repo_root cand
    if [[ -n "$arg" ]]; then
      [[ -f "$arg" ]] && arg="$(dirname "$arg")"
      if cd "$arg" 2>/dev/null; then
        repo_root="$(pwd -P)"
        if is_flutter_project_root "$repo_root"; then
          FLUTTER_ROOT="$repo_root"; ENTRY_FILE="$repo_root/lib/main.dart"; set -e; return 0
        fi
      fi
    fi
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"
    else
      repo_root="$(pwd -P)"
    fi
    if [[ -f "$repo_root/pubspec.yaml" && -d "$repo_root/lib" ]]; then
      FLUTTER_ROOT="$repo_root"; ENTRY_FILE="$repo_root/lib/main.dart"; set -e; return 0
    fi
    cand="$(/usr/bin/find "$repo_root" -name pubspec.yaml -type f -print 2>/dev/null | head -n1)"
    if [[ -n "$cand" ]]; then
      FLUTTER_ROOT="$(dirname "$cand")"; ENTRY_FILE="$FLUTTER_ROOT/lib/main.dart"; set -e; return 0
    fi
    set -e
    error_echo "未找到 Flutter 项目（缺 pubspec.yaml 或 lib）"
    exit 1
  }

  # Perl 检测（有就用，没有就 Python 兜底）
  typeset -g USE_PERL_URI_ESCAPE=0
  # 检查 ensure perl and module 所需条件，不满足时阻止继续执行。
  ensure_perl_and_module() {
    if command -v perl >/dev/null 2>&1 && perl -MURI::Escape -e 1 >/dev/null 2>&1; then
      USE_PERL_URI_ESCAPE=1; info_echo "Perl + URI::Escape 可用"
    else
      USE_PERL_URI_ESCAPE=0; info_echo "未检测到 Perl 模块，使用 Python3 兜底"
    fi
  }
  # 修复 import（zsh glob）
  replace_uri_imports() {
    cd "$FLUTTER_ROOT"
    local BACKUP_DIR=".import_backup"; mkdir -p "$BACKUP_DIR"
    local changed=0
    for file in **/*.dart(N); do
      if grep -q "import 'package:[^']*%[0-9A-Fa-f][0-9A-Fa-f]" "$file"; then
        mkdir -p "$BACKUP_DIR/$(dirname "$file")"
        cp "$file" "$BACKUP_DIR/$file"
        if [[ "$USE_PERL_URI_ESCAPE" == "1" ]]; then
          perl -i -pe "use URI::Escape; s|(import\\s+'package:[^']*)|uri_unescape(\$1)|ge" "$file"
        else
          /usr/bin/env python3 - "$file" <<'PY'
import sys, re, urllib.parse, io
p = sys.argv[1]
with io.open(p,'r',encoding='utf-8',errors='ignore') as f:s=f.read()
def unq(m):return urllib.parse.unquote(m.group(0))
def repl(m):inner=m.group(1);return "import '"+re.sub(r'%[0-9A-Fa-f]{2}',unq,inner)+"'"
s2=re.sub(r"import\s+'(package:[^']*)'",repl,s)
if s2!=s:
  with io.open(p,'w',encoding='utf-8') as f:f.write(s2)
PY
        fi
        info_echo "修复：$file"; changed=$((changed+1))
      fi
    done
    [[ "$changed" -gt 0 ]] && success_echo "完成：修复 $changed 个文件；备份在 $BACKUP_DIR" || info_echo "未发现需要修复的 import"
  }
  # 自述
  print_banner() {
    echo "[RUN] 修复 Flutter 项目 import 中文路径"
    echo " - 自动识别项目根（参数/ \$REPO 优先，找不到就全仓库搜索）"
    echo " - Perl 模块缺失自动 Python3 兜底"
    echo " - 按相对路径备份到 .import_backup/"
  }
  # 编排脚本的高层业务流程。
  main() {
    print_banner
    resolve_project_root "${1:-${REPO:-}}"
    success_echo "项目路径：$FLUTTER_ROOT"
    ensure_perl_and_module
    replace_uri_imports
    success_echo "完成。日志：$LOG_FILE"
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
