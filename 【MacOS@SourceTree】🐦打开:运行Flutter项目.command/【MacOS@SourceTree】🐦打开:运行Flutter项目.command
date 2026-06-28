#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】🐦Flutter运行setup.command.command
# - 核心用途：执行“🐦Flutter运行setup.command”对应的移动端项目自动化任务。
# - 影响范围：可能修改项目依赖、生成文件、构建产物或开发工具配置。
# - 运行提示：运行后会先打印内置自述；Sourcetree 模式无交互连续执行，终端模式确认后继续。
# =====================================================================
# Jobs 标准化脚本外壳
# 说明：Sourcetree 中优先定位 Flutter 工程 setup.command；没有 setup.command 时，回退到 flutter run。
# =====================================================================

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
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

PROJECT_ROOT=""
SETUP_COMMAND_PATH=""
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
# 去除 ANSI 彩色码，避免 Sourcetree 输出窗口出现乱码。
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
# 展示脚本用途和影响范围，并在系统终端中等待用户确认。
show_readme_and_wait() {
  if typeset -f is_sourcetree_runtime >/dev/null 2>&1 && is_sourcetree_runtime; then
    IS_SOURCETREE_RUNTIME=1
  fi
  if [[ "$IS_SOURCETREE_RUNTIME" == "1" || ! -t 1 || "${TERM:-}" == "dumb" || -n "${NO_COLOR:-}" ]]; then
    SOURCETREE_PLAIN_OUTPUT=1
    export NO_COLOR="${NO_COLOR:-1}"
    export CLICOLOR="0"
    export ANSI_COLORS_DISABLED="1"
  fi
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" != "1" && -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 =============================="
  note_echo "脚本名称：${SCRIPT_BASENAME}.command"
  note_echo "脚本路径：${SCRIPT_PATH}"
  note_echo "运行入口：兼容系统终端双击运行和 Sourcetree 自定义动作运行。"
  note_echo "核心行为：优先定位当前 Git / Flutter 工程中的 setup.command；没有 setup.command 时先启动 iOS Simulator，再回退执行 flutter run。"
  note_echo "设计原因：setup.command、模拟器启动或 flutter run 可能涉及入口、设备、运行宿主等人工选择，不适合直接在 Sourcetree 受限窗口里执行。"
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
# 去掉用户拖入路径或 SourceTree 参数携带的引号、file:// 和换行。
strip_outer_quotes() {
  local value="$1"
  value="${value%$'\r'}"
  value="${value%$'\n'}"
  value="${value#file://}"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  print -r -- "$value"
}
# 将路径转换为绝对路径。
abs_path() {
  local p="$1"
  [[ -z "$p" ]] && return 1
  p="$(strip_outer_quotes "$p")"
  p="${p/#\~/$HOME}"
  [[ "$p" != "/" ]] && p="${p%/}"

  if [[ -d "$p" ]]; then
    (cd "$p" 2>/dev/null && pwd -P)
  elif [[ -f "$p" ]]; then
    (cd "${p:h}" 2>/dev/null && printf "%s/%s\n" "$(pwd -P)" "${p:t}")
  else
    return 1
  fi
}
# 将目录、pubspec.yaml 或仓库内文件归一化为可向上查找的目录。
normalize_project_input() {
  local raw="$1"
  local target=""

  target="$(abs_path "$raw" 2>/dev/null || true)"
  [[ -n "$target" ]] || return 1

  if [[ -f "$target" ]]; then
    target="${target:h}"
  fi

  print -r -- "$target"
}
# 从指定目录向上寻找 Flutter 工程根目录。
find_flutter_root_upwards() {
  local current=""
  current="$(normalize_project_input "$1" 2>/dev/null || true)"
  [[ -n "$current" && -d "$current" ]] || return 1

  while [[ "$current" != "/" ]]; do
    if [[ -f "$current/pubspec.yaml" ]]; then
      print -r -- "$current"
      return 0
    fi
    current="${current:h}"
  done

  return 1
}
# 从指定目录向上寻找 Git 仓库根目录。
find_git_root_upwards() {
  local current=""
  current="$(normalize_project_input "$1" 2>/dev/null || true)"
  [[ -n "$current" && -d "$current" ]] || return 1

  while [[ "$current" != "/" ]]; do
    if [[ -d "$current/.git" || -f "$current/.git" ]]; then
      print -r -- "$current"
      return 0
    fi
    current="${current:h}"
  done

  return 1
}
# 在工程目录中寻找 setup.command，优先使用根目录替身和 tool/setup/setup.command。
find_setup_command_under_dir() {
  local root="$1"
  local candidate=""

  if [[ -f "$root/setup.command" ]]; then
    print -r -- "$root/setup.command"
    return 0
  fi

  if [[ -f "$root/tool/setup/setup.command" ]]; then
    print -r -- "$root/tool/setup/setup.command"
    return 0
  fi

  while IFS= read -r -d $'\0' candidate; do
    print -r -- "$candidate"
    return 0
  done < <(
    find "$root" \
      \( -type d \( -name ".git" -o -name "Pods" -o -name ".dart_tool" -o -name "build" -o -name "DerivedData" -o -name "node_modules" \) -prune \) -o \
      \( -type f -name "setup.command" -print0 \) 2>/dev/null
  )

  return 1
}
# 从 SourceTree 参数、当前目录或拖入路径中确定工程目录。
resolve_project_root() {
  local input_path=""
  local flutter_root=""
  local git_root=""

  for input_path in "$@"; do
    [[ -n "$input_path" ]] || continue

    flutter_root="$(find_flutter_root_upwards "$input_path" 2>/dev/null || true)"
    if [[ -n "$flutter_root" ]]; then
      PROJECT_ROOT="$flutter_root"
      return 0
    fi

    git_root="$(find_git_root_upwards "$input_path" 2>/dev/null || true)"
    if [[ -n "$git_root" ]]; then
      PROJECT_ROOT="$git_root"
      return 0
    fi
  done

  flutter_root="$(find_flutter_root_upwards "$PWD" 2>/dev/null || true)"
  if [[ -n "$flutter_root" ]]; then
    PROJECT_ROOT="$flutter_root"
    return 0
  fi

  git_root="$(find_git_root_upwards "$PWD" 2>/dev/null || true)"
  if [[ -n "$git_root" ]]; then
    PROJECT_ROOT="$git_root"
    return 0
  fi

  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" || ! -t 0 ]]; then
    error_echo "Sourcetree / 非交互环境未能定位 Git 或 Flutter 工程目录。"
    return 1
  fi

  while true; do
    echo ""
    read -r "input_path?👉 请输入或拖入 Flutter 工程目录 / pubspec.yaml / 仓库内任意文件："
    flutter_root="$(find_flutter_root_upwards "$input_path" 2>/dev/null || true)"
    if [[ -n "$flutter_root" ]]; then
      PROJECT_ROOT="$flutter_root"
      return 0
    fi
    warn_echo "没有找到 pubspec.yaml，请重新输入。"
  done
}
# 定位 setup.command；标准 Flutter 工程没有 setup.command 时回退到模拟器启动和 flutter run。
resolve_setup_command() {
  local candidate=""

  candidate="$(find_setup_command_under_dir "$PROJECT_ROOT" 2>/dev/null || true)"
  if [[ -z "$candidate" ]]; then
    SETUP_COMMAND_PATH=""
    warn_echo "未在当前工程中找到 setup.command：${PROJECT_ROOT}"
    warn_echo "将回退为在系统 Terminal 中先启动 iOS Simulator，再执行 flutter run。"
    return 0
  fi

  SETUP_COMMAND_PATH="$(abs_path "$candidate")"
  if [[ ! -x "$SETUP_COMMAND_PATH" ]]; then
    chmod +x "$SETUP_COMMAND_PATH" 2>/dev/null || true
  fi

  if [[ ! -x "$SETUP_COMMAND_PATH" ]]; then
    error_echo "setup.command 不可执行，请检查权限：${SETUP_COMMAND_PATH}"
    return 1
  fi

  success_echo "已找到 setup.command：${SETUP_COMMAND_PATH}"
}
# 生成标准 Flutter 工程的运行命令，先拉起 iOS Simulator 再进入 flutter run。
build_flutter_run_command() {
  local project_root_quoted="${(q)PROJECT_ROOT}"
  print -r -- "cd ${project_root_quoted} && flutter emulators --launch apple_ios_simulator >/dev/null 2>&1 || open -a Simulator; for i in {1..60}; do xcrun simctl list devices booted 2>/dev/null | grep -q '(Booted)' && break; sleep 1; done; flutter run"
}
# 使用系统 Terminal 执行 setup.command 或标准 Flutter 运行命令，让后续人工选择回到完整终端。
open_setup_in_terminal() {
  local command_text=""
  if [[ -n "${SETUP_COMMAND_PATH:-}" ]]; then
    command_text="cd ${(q)PROJECT_ROOT} && ${(q)SETUP_COMMAND_PATH}"
  else
    command_text="$(build_flutter_run_command)"
  fi

  if [[ "${JOBS_SOURCETREE_SETUP_DRY_RUN:-}" == "1" ]]; then
    success_echo "Dry-run：已生成 Terminal 命令，未实际打开 Terminal。"
    gray_echo "Terminal 命令：${command_text}"
    return 0
  fi

  if ! command -v osascript >/dev/null 2>&1; then
    error_echo "当前系统缺少 osascript，无法打开系统 Terminal。"
    return 1
  fi

  if osascript - "$command_text" <<'APPLESCRIPT_EOF' >/dev/null 2>&1
on run argv
  set commandText to item 1 of argv
  tell application "Terminal"
    activate
    do script commandText
  end tell
end run
APPLESCRIPT_EOF
  then
    success_echo "已交给系统 Terminal 执行 Flutter 运行命令。"
    gray_echo "Terminal 命令：${command_text}"
    return 0
  fi

  error_echo "打开系统 Terminal 失败。"
  return 1
}
# 执行对应的环境配置或同步处理。
run_original_logic() {
  resolve_project_root "$@" || return 1
  success_echo "已定位工程目录：${PROJECT_ROOT}"
  resolve_setup_command || return 1
  open_setup_in_terminal || return 1
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
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
  # 执行 run_original_logic 对应的核心业务步骤。
  run_original_logic "$@"
  # 输出脚本执行结果、摘要和日志位置。
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
