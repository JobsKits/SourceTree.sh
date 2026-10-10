#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】（只打开当前目录）用Xcode打开.command
# - 核心用途：只扫描当前目录第一层，选择明确的现有工程或 workspace 后用 Xcode 打开。
# - 影响范围：默认只打开目标和记录日志，不运行 pod install、不清理全局 SwiftPM/DerivedData。
# - 运行提示：终端先展示内置自述并等待回车；Sourcetree 实际发起时无交互执行。
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

SCRIPT_PATH=""
SCRIPT_DIR=""
SCRIPT_BASENAME=""
LOG_FILE=""
LOG_INITIALIZED=0
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
# 封装 strip_ansi_text 对应的独立处理逻辑。
strip_ansi_text() {
  perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}
# 根据运行入口和终端能力预先切换纯文本输出，避免 Sourcetree 显示 ANSI 转义码。
prepare_plain_output_context() {
  [[ -n "${TERM:-}" ]] || export TERM="dumb"
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" || ! -t 1 || "$TERM" == "dumb" || -n "${NO_COLOR+x}" || "${JOBS_PLAIN_OUTPUT:-0}" == "1" ]]; then
    SOURCETREE_PLAIN_OUTPUT=1
    COLOR_ENABLED=0
    export NO_COLOR="${NO_COLOR:-1}"
    export FORCE_COLOR=0
    export CLICOLOR="0"
    export ANSI_COLORS_DISABLED="1"
    export npm_config_color=false
  fi
}
# 按当前输出级别记录终端信息，并同步写入脚本日志。
log() {
  if [[ "${SOURCETREE_PLAIN_OUTPUT:-0}" == 1 ]]; then
    if [[ "$LOG_INITIALIZED" == 1 ]]; then
      printf '%s\n' "$1" | strip_ansi_text | tee -a "$LOG_FILE"
    else
      printf '%s\n' "$1" | strip_ansi_text
    fi
  elif [[ "$LOG_INITIALIZED" == 1 ]]; then
    printf '%s\n' "$1" | tee -a "$LOG_FILE"
  else
    printf '%s\n' "$1"
  fi
}
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log $'\033[1;32m'"$1"$'\033[0m'; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log $'\033[1;34m'"ℹ $1"$'\033[0m'; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log $'\033[1;32m'"✔ $1"$'\033[0m'; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log $'\033[1;33m'"⚠ $1"$'\033[0m'; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log $'\033[1;33m'"$1"$'\033[0m'; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log $'\033[1;35m'"➤ $1"$'\033[0m'; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log $'\033[1;31m'"✖ $1"$'\033[0m'; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err_echo()       { log $'\033[1;31m'"$1"$'\033[0m'; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log $'\033[1;35m'"🐞 $1"$'\033[0m'; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log $'\033[1;36m'"🔹 $1"$'\033[0m'; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log $'\033[0;90m'"$1"$'\033[0m'; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log $'\033[1m'"$1"$'\033[0m'; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
underline_echo() { log $'\033[4m'"$1"$'\033[0m'; }

TARGET_PATH=""
# 在自述前解析脚本路径、日志位置与输出模式；不执行打开或配置业务。
prepare_script_context() {
  SCRIPT_PATH="$(resolve_script_path)"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_FILE="${TMPDIR:-/tmp/}"
  LOG_FILE="${LOG_FILE%/}/${SCRIPT_BASENAME}.log"
  is_sourcetree_runtime && IS_SOURCETREE_RUNTIME=1
  prepare_plain_output_context
  return 0
}
# 确认后固定 zsh 语义，并补齐 Sourcetree 精简 PATH。
initialize_script_runtime() {
  emulate -R zsh
  setopt NO_NOMATCH PIPE_FAIL
  : > "$LOG_FILE" || { error_echo "无法创建日志：$LOG_FILE"; exit 1; }
  LOG_INITIALIZED=1
  log "脚本：${SCRIPT_BASENAME}.command"
  log "脚本路径：$SCRIPT_PATH"
  log "核心用途：只扫描当前目录第一层，选择明确的现有工程或 workspace 后用 Xcode 打开。"
  log "影响范围：默认只打开目标和记录日志，不运行 pod install、不清理全局 SwiftPM/DerivedData。"
  export PATH="${PATH:-/usr/bin:/bin}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  prepare_plain_output_context
}
# 保留用户路径原文，仅在原路径不存在时尝试去除配对外层引号。
normalize_target_path() {
  local candidate="$1"
  if [[ ! -e "$candidate" ]]; then
    candidate="${candidate%$'\r'}"
    if [[ "$candidate" == \"*\" || "$candidate" == \'*\' ]]; then
      candidate="${candidate[2,-2]}"
    fi
    if [[ ! -e "$candidate" ]]; then
      candidate="${(Q)candidate}"
    fi
  fi
  if [[ "$candidate" == '~' ]]; then
    candidate="$HOME"
  elif [[ "$candidate" == '~/'* ]]; then
    candidate="$HOME/${candidate#\~/}"
  fi
  [[ -e "$candidate" ]] || return 1
  if [[ -d "$candidate" ]]; then
    (cd -- "$candidate" 2>/dev/null && pwd -P)
  else
    (cd -- "${candidate:h}" 2>/dev/null && printf '%s/%s\n' "$PWD" "${candidate:t}")
  fi
}
# 参数优先于 REPO；Sourcetree 缺参数时停止，避免误开脚本所在目录。
resolve_target_path() {
  local candidate=""
  if (( $# > 1 )); then
    error_echo "本动作只接受一个文件或目录参数；含空格路径请整体加引号。"
    return 2
  elif (( $# == 1 )); then
    candidate="$1"
  elif [[ -n "${REPO:-}" ]]; then
    candidate="$REPO"
  elif [[ "$IS_SOURCETREE_RUNTIME" == 1 ]]; then
    error_echo '未收到目标路径；Sourcetree 参数请填写 "$REPO"。'
    return 2
  else
    candidate="$PWD"
  fi
  TARGET_PATH="$(normalize_target_path "$candidate")" || {
    error_echo "目标不存在或不可访问：$candidate"
    return 2
  }
  info_echo "目标路径：$TARGET_PATH"
}
# 外部命令输出同步落日志；保留真实命令退出码。
run_logged() {
  "$@" 2>&1 | strip_ansi_text | tee -a "$LOG_FILE"
  local command_exit=${pipestatus[1]}
  return "$command_exit"
}
# 无健康 CLI 时复用现有 app；缺应用时只打开官方页面。
open_editor_target() {
  local cli="$1"
  local official_url="$2"
  shift 2
  local app=""
  if [[ -n "$cli" ]] && command -v "$cli" >/dev/null 2>&1; then
    if "$cli" --version >/dev/null 2>&1; then
      info_echo "使用 CLI：$cli"
      run_logged "$cli" "$TARGET_PATH"
      return $?
    fi
    warn_echo "CLI 不可用：$cli，继续检查本机应用。"
  fi
  command -v open >/dev/null 2>&1 || { error_echo '缺少 macOS open 命令。'; return 127; }
  for app in "$@"; do
    [[ -d "$app" && -f "$app/Contents/Info.plist" ]] || continue
    info_echo "使用应用：$app"
    run_logged open -a "$app" "$TARGET_PATH"
    return $?
  done
  warn_echo '未检测到可用应用，打开官方页面；本次目标尚未打开。'
  run_logged open "$official_url" || return $?
  return 3
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_readme_and_wait() {
  prepare_script_context || exit 1
  if [[ -z "${NO_COLOR+x}" && "${PLAIN_OUTPUT:-0}" != 1 && "${IS_SOURCETREE_RUNTIME:-0}" != "1" && -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 ==============================" | jobs_intro_style title
  note_echo "脚本名称：${SCRIPT_BASENAME}.command" | jobs_intro_style title
  note_echo "脚本路径：${SCRIPT_PATH}" | jobs_intro_style body
  note_echo "运行入口：兼容系统终端双击运行和 Sourcetree 自定义动作运行。" | jobs_intro_style body
  note_echo "核心行为：只扫描当前目录第一层，选择明确的现有工程或 workspace 后用 Xcode 打开。" | jobs_intro_style body
  note_echo "影响范围：默认只打开目标和记录日志，不运行 pod install、不清理全局 SwiftPM/DerivedData。" | jobs_intro_style body
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
  read -r "?👉 已阅读脚本内置自述，按回车继续执行；按 Ctrl+C 取消..." _ || { error_echo "读取确认失败，已取消。"; exit 1; }
}

XCODE_TARGET=""
# 扫描使用 NUL 分隔并剪枝工程包和依赖目录，兼容路径换行。
collect_xcode_projects() {
  local scan_root="$1"
  local item=""
  XCODE_PROJECTS=()
  while IFS= read -r -d '' item; do
    [[ "${item:t}" != Pods.xcodeproj ]] && XCODE_PROJECTS+=("$item")
  done < <(/usr/bin/find "$scan_root" -maxdepth 1 -type d -name '*.xcodeproj' -print0)
}
# 当前层 workspace 不进入工程包里的 project.xcworkspace。
collect_workspaces() {
  local scan_root="$1"
  local item=""
  XCODE_WORKSPACES=()
  while IFS= read -r -d '' item; do
    XCODE_WORKSPACES+=("$item")
  done < <(/usr/bin/find "$scan_root" -maxdepth 1 -type d -name '*.xcworkspace' -print0)
}
# 精确同名或唯一候选才能自动选择；歧义时列出候选并停止。
select_xcode_target() {
  local -a XCODE_PROJECTS XCODE_WORKSPACES
  local project=""
  local candidate=""
  if [[ -d "$TARGET_PATH" && ( "$TARGET_PATH" == *.xcodeproj || "$TARGET_PATH" == *.xcworkspace ) ]]; then
    XCODE_TARGET="$TARGET_PATH"
    return 0
  fi
  [[ -d "$TARGET_PATH" ]] || { error_echo 'Xcode 入口需要目录、xcodeproj 或 xcworkspace。'; return 2; }
  collect_xcode_projects "$TARGET_PATH"
  collect_workspaces "$TARGET_PATH"
  if [[ "${FORCE_XCODEPROJ:-0}" != 1 ]]; then
    candidate="$TARGET_PATH/${TARGET_PATH:t}.xcworkspace"
    if [[ -d "$candidate" ]]; then
      XCODE_TARGET="$candidate"
      return 0
    fi
    if (( ${#XCODE_WORKSPACES[@]} == 1 )); then
      XCODE_TARGET="${XCODE_WORKSPACES[1]}"
      return 0
    fi
    if (( ${#XCODE_WORKSPACES[@]} > 1 )); then
      error_echo '当前目录存在多个 workspace，请传入明确的目标。'
      for candidate in "${(o)XCODE_WORKSPACES[@]}"; do
        note_echo "候选：$candidate"
      done
      return 2
    fi
  fi
  if (( ${#XCODE_PROJECTS[@]} == 0 )); then
    error_echo '扫描范围内未找到 xcodeproj；也没有可选顶层 workspace。'
    return 2
  fi
  if (( ${#XCODE_PROJECTS[@]} > 1 )); then
    error_echo '扫描范围内存在多个工程，请传入明确的 xcodeproj / xcworkspace。'
    for candidate in "${(o)XCODE_PROJECTS[@]}"; do
      note_echo "候选：$candidate"
    done
    return 2
  fi
  project="${XCODE_PROJECTS[1]}"
  XCODE_TARGET="$project"
  if [[ "${FORCE_XCODEPROJ:-0}" != 1 ]]; then
    candidate="${project:r}.xcworkspace"
    if [[ -d "$candidate" ]]; then
      XCODE_TARGET="$candidate"
    else
      collect_workspaces "${project:h}"
      if (( ${#XCODE_WORKSPACES[@]} == 1 )); then
        XCODE_TARGET="${XCODE_WORKSPACES[1]}"
      elif (( ${#XCODE_WORKSPACES[@]} > 1 )); then
        error_echo '选中工程旁存在多个 workspace，请传入明确目标。'
        for candidate in "${(o)XCODE_WORKSPACES[@]}"; do
          note_echo "候选：$candidate"
        done
        return 2
      elif [[ -f "${project:h}/Podfile" ]]; then
        warn_echo '存在 Podfile 但无 workspace，直接打开工程；需要依赖时使用独立 Pod Install 动作。'
      fi
    fi
  fi
  info_echo "选中目标：$XCODE_TARGET"
}
# 只有显式启用才解析 SwiftPM；不清理全局缓存或移除隔离属性。
resolve_swiftpm_if_requested() {
  [[ "${RESOLVE_SWIFTPM_BEFORE_OPEN:-0}" == 1 ]] || return 0
  command -v xcodebuild >/dev/null 2>&1 || { error_echo '启用 SwiftPM 解析但缺少 xcodebuild。'; return 127; }
  xcodebuild -version >/dev/null 2>&1 || { error_echo 'xcodebuild 不可用，请检查 Xcode 和 Command Line Tools。'; return 1; }
  local target_flag='-project'
  [[ "$XCODE_TARGET" == *.xcworkspace ]] && target_flag='-workspace'
  local -a arguments=(-resolvePackageDependencies "$target_flag" "$XCODE_TARGET")
  [[ -n "${XCODE_SCHEME:-}" ]] && arguments+=(-scheme "$XCODE_SCHEME")
  info_echo "按显式配置解析 SwiftPM：$XCODE_TARGET"
  run_logged xcodebuild "${arguments[@]}"
}
# 由 macOS open 解析已安装 Xcode，并同步输出实际启动结果。
open_xcode_target() {
  command -v open >/dev/null 2>&1 || { error_echo '缺少 macOS open 命令。'; return 127; }
  info_echo "打开 Xcode：$XCODE_TARGET"
  run_logged open -a Xcode "$XCODE_TARGET"
}
# 校验目标并完成业务，集中传播退出码和记录最终结果。
run_validated_open() {
  resolve_target_path "$@" || return $? # 校验并保存唯一目标路径。
  select_xcode_target || return $? # 在扫描范围内选择无歧义的现有工程。
  resolve_swiftpm_if_requested || return $? # 仅按显式配置解析 SwiftPM，失败则停止。
  open_xcode_target || return $? # 请求 Xcode 打开目标并保留真实退出码。
  success_echo "操作完成。日志：$LOG_FILE" # 输出成功结果和日志位置。
}
# 编排自述、运行环境和目标打开流程。
main() {
  show_readme_and_wait # 展示内置自述，确认失败时停止。
  initialize_script_runtime # 确认后固定环境并初始化日志。
  run_validated_open "$@" # 校验目标并完成业务，返回真实结果。
}

main "$@"
