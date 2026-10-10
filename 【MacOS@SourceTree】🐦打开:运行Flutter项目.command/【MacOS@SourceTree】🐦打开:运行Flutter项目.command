#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】🐦打开:运行Flutter项目.command
# - 核心用途：定位工程 setup.command，或把标准 Flutter 模拟器运行交给系统 Terminal。
# - 影响范围：可能补齐 setup.command 执行权限；标准回退先确认项目 SDK 和模拟器就绪，超时停止。
# - 运行提示：运行后会先打印内置自述；Sourcetree 模式无交互连续执行，终端模式确认后继续。
# =====================================================================
# Jobs 标准化脚本外壳
# 说明：Sourcetree 中优先定位 Flutter 工程 setup.command；没有 setup.command 时，回退到 flutter run。
# =====================================================================
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
# Sourcetree 自定义动作可能只传脚本名，不传绝对路径；这里兜底找回真实脚本位置。
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

PROJECT_ROOT=""
SETUP_COMMAND_PATH=""
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
# 去除 ANSI 彩色码，避免 Sourcetree 输出窗口出现乱码。
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
# 展示脚本用途和影响范围，并在系统终端中等待用户确认。
show_script_intro_and_wait() {
  prepare_script_metadata
  if [[ -z "${NO_COLOR+x}" && "${IS_SOURCETREE_RUNTIME:-0}" != "1" && -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" && "${PLAIN_OUTPUT:-0}" != 1 ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 ==============================" | jobs_intro_style title
  note_echo "脚本名称：${SCRIPT_BASENAME}.command" | jobs_intro_style title
  note_echo "脚本路径：${SCRIPT_PATH}" | jobs_intro_style body
  note_echo "运行入口：兼容系统终端双击运行和 Sourcetree 自定义动作运行。" | jobs_intro_style body
  note_echo "核心行为：优先定位当前 Git / Flutter 工程中的 setup.command；没有 setup.command 时先启动 iOS Simulator，再回退执行 flutter run。" | jobs_intro_style body
  note_echo "设计原因：setup.command、模拟器启动或 flutter run 可能涉及入口、设备、运行宿主等人工选择，不适合直接在 Sourcetree 受限窗口里执行。" | jobs_intro_style body
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
  if [[ ! -e "$p" ]]; then
    p="$(strip_outer_quotes "$p")"
    [[ "$p" == '~/'* ]] && p="$HOME/${p#\~/}"
    [[ -e "$p" ]] || p="${(Q)p}"
  fi
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

  local -a candidates=()
  while IFS= read -r -d '' candidate; do
    candidates+=("$candidate")
  done < <(
    find "$root" \
      \( -type d \( -name .git -o -name Pods -o -name PodsManual -o -name 'ManualBy*Pods*' -o -name .dart_tool -o -name .fvm -o -name build -o -name DerivedData -o -name node_modules -o -name vendor -o -name third_party \) -prune \) -o \
      \( -type f -name setup.command -print0 \)
  )
  (( ${#candidates[@]} <= 1 )) || { error_echo "发现多个 setup.command，请传入具体工程目录。" >&2; return 2; }
  (( ${#candidates[@]} == 1 )) || return 1
  print -r -- "${candidates[1]}"
  return 0
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

  if (( $# > 0 )); then
    error_echo "传入路径没有可用的 Flutter / Git 工程，请确认目标。"
    return 1
  fi

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

  local setup_ec=0
  candidate="$(find_setup_command_under_dir "$PROJECT_ROOT")" || setup_ec=$?
  (( setup_ec != 2 )) || return 1
  if [[ -z "$candidate" ]]; then
    [[ -f "$PROJECT_ROOT/pubspec.yaml" && -d "$PROJECT_ROOT/lib" ]] || { error_echo "没有 setup.command，当前目录也不是 Flutter 工程：$PROJECT_ROOT"; return 1; }
    SETUP_COMMAND_PATH=""
    warn_echo "未在当前工程中找到 setup.command：${PROJECT_ROOT}"
    warn_echo "将回退为在系统 Terminal 中先启动 iOS Simulator，再执行 flutter run。"
    return 0
  fi

  SETUP_COMMAND_PATH="$(abs_path "$candidate")"
  if [[ ! -x "$SETUP_COMMAND_PATH" && "${JOBS_SOURCETREE_SETUP_DRY_RUN:-0}" == 1 ]]; then
    warn_echo "Dry-run：setup.command 尚无执行权限；正式运行时会尝试补齐。"
    return 0
  fi
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
  local wait_seconds="${SIMULATOR_WAIT_SECS:-60}"
  [[ "$wait_seconds" == <1-> ]] || { error_echo 'SIMULATOR_WAIT_SECS 必须是正整数。' >&2; return 1; }
  local terminal_script='export PATH="$HOME/.pub-cache/bin:$HOME/.fvm/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
if [[ -x .fvm/flutter_sdk/bin/flutter ]]; then
  flutter_cmd=("$PWD/.fvm/flutter_sdk/bin/flutter")
elif [[ -f .fvmrc || -f .fvm/fvm_config.json ]]; then
  command -v fvm >/dev/null 2>&1 || { print "缺少项目 FVM，请先恢复 SDK。"; exit 1; }
  flutter_cmd=(fvm flutter)
else
  command -v flutter >/dev/null 2>&1 || { print "未找到 Flutter。"; exit 1; }
  flutter_cmd=(flutter)
fi
command -v xcrun >/dev/null 2>&1 || { print "缺少 Xcode / xcrun。"; exit 1; }
"${flutter_cmd[@]}" emulators --launch apple_ios_simulator || open -a Simulator || exit 1
boot_device=""
for ((i=0; i<WAIT_SECONDS; i++)); do
  boot_device="$(xcrun simctl list devices booted 2>/dev/null | /usr/bin/awk -F "[()]" '\''/\(Booted\)/ {print $(NF-3); exit}'\'')"
  [[ -n "$boot_device" ]] && break
  sleep 1
done
[[ -n "$boot_device" ]] || { print "模拟器等待超时，已停止 Flutter 运行。"; exit 1; }
"${flutter_cmd[@]}" run -d "$boot_device"'
  terminal_script="${terminal_script/WAIT_SECONDS/$wait_seconds}"
  print -r -- "cd ${(q)PROJECT_ROOT} && ( ${terminal_script} )"
}
# 使用系统 Terminal 执行 setup.command 或标准 Flutter 运行命令，让后续人工选择回到完整终端。
open_setup_in_terminal() {
  local command_text=""
  if [[ -n "${SETUP_COMMAND_PATH:-}" ]]; then
    command_text="cd ${(q)PROJECT_ROOT} && ${(q)SETUP_COMMAND_PATH}"
  else
    command_text="$(build_flutter_run_command)" || return $?
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
