#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】用Trae打开@openjdk64-17.0.16.command
# - 核心用途：验证健康 JDK 17 后使用 Trae 打开工程目录；文件名旧版本仅用于菜单兼容。
# - 影响范围：设置本次 JAVA_HOME/PATH；有健康 jenv 映射时保存项目 .java-version；不安装或升级工具。
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
  log "核心用途：验证健康 JDK 17 后使用 Trae 打开工程目录；文件名旧版本仅用于菜单兼容。"
  log "影响范围：设置本次 JAVA_HOME/PATH；有健康 jenv 映射时保存项目 .java-version；不安装或升级工具。"
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
  note_echo "核心行为：验证健康 JDK 17 后使用 Trae 打开工程目录；文件名旧版本仅用于菜单兼容。" | jobs_intro_style body
  note_echo "影响范围：设置本次 JAVA_HOME/PATH；有健康 jenv 映射时保存项目 .java-version；不安装或升级工具。" | jobs_intro_style body
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

JDK_HOME=""
JENV_ALIAS=""
# 同时验证 Java 和 javac 的真实主版本，拒绝仅名称包含 17 的候选。
jdk17_is_healthy() {
  local candidate="$1"
  local details=""
  [[ -x "$candidate/bin/java" && -x "$candidate/bin/javac" ]] || return 1
  details="$("$candidate/bin/java" -XshowSettings:properties -version 2>&1)" || return 1
  printf '%s\n' "$details" | /usr/bin/awk -F ' = ' '/^[[:space:]]*java.specification.version = / { found=($2 == "17") } END { exit !found }' || return 1
  details="$("$candidate/bin/javac" -version 2>&1)" || return 1
  [[ "$details" == 'javac 17' || "$details" == 'javac 17.'* || "$details" == 'javac 17-'* ]]
}
# 复用健康 jenv 映射，其次检查直接安装的 JDK；不安装管理器或锁定旧补丁版。
select_jdk17() {
  local alias=""
  local candidate=""
  local versions=""
  if command -v jenv >/dev/null 2>&1 && jenv --version >/dev/null 2>&1; then
    versions="$(jenv versions --bare 2>/dev/null)" || versions=""
    # major alias 优先，其它候选也必须通过实际可执行版本复验。
    for alias in 17 "${(@f)versions}"; do
      [[ -n "$alias" && "$alias" != system ]] || continue
      candidate="$(JENV_VERSION="$alias" jenv prefix 2>/dev/null)" || continue
      if jdk17_is_healthy "$candidate"; then
        JDK_HOME="$candidate"
        JENV_ALIAS="$alias"
        return 0
      fi
    done
  fi
  local -a candidates=("${JAVA_HOME:-}")
  candidate="$(/usr/libexec/java_home -v 17 2>/dev/null)" && candidates+=("$candidate")
  candidates+=(
    "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
    "/usr/local/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
    /Library/Java/JavaVirtualMachines/*/Contents/Home(N)
    "$HOME"/Library/Java/JavaVirtualMachines/*/Contents/Home(N)
  )
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" ]] || continue
    if jdk17_is_healthy "$candidate"; then
      JDK_HOME="$candidate"
      return 0
    fi
  done
  error_echo '未找到健康 JDK 17（java 和 javac 均需 17）；请安装或修复 JDK 后重试。'
  return 1
}
# 只对本次启动导出 Java；有已验证 jenv 映射时幂等保存项目级配置。
activate_jdk17() {
  export JAVA_HOME="$JDK_HOME"
  export PATH="$JAVA_HOME/bin:$PATH"
  if [[ -n "$JENV_ALIAS" ]]; then
    export JENV_VERSION="$JENV_ALIAS"
    local marker="$TARGET_PATH/.java-version"
    [[ ! -L "$marker" ]] || { error_echo "拒绝覆盖符号链接：$marker"; return 1; }
    if [[ ! -f "$marker" || "$(<"$marker")" != "$JENV_ALIAS" ]]; then
      printf '%s\n' "$JENV_ALIAS" > "$marker" || { error_echo "无法写入：$marker"; return 1; }
    fi
    info_echo "项目 jenv 版本：$JENV_ALIAS"
  else
    warn_echo '未发现健康 jenv 映射，仅设置本次启动环境；现有 .java-version 保留。'
  fi
  info_echo "JAVA_HOME=$JAVA_HOME"
  run_logged "$JAVA_HOME/bin/java" -version
}
# Java 入口限定工程目录，文件参数不用于改写项目配置。
require_target_directory() {
  [[ -d "$TARGET_PATH" ]] || { error_echo "Java 入口需要目录：$TARGET_PATH"; return 2; }
}
# CLI 能继承本次 Java 环境；GUI 的项目 JDK 仍由应用设置决定。
open_target() {
  open_editor_target "trae" "https://www.trae.cn/" "/Applications/Trae.app" "$HOME/Applications/Trae.app" "/Applications/Trae CN.app" "$HOME/Applications/Trae CN.app"
}
# 校验目标并完成业务，集中传播退出码和记录最终结果。
run_validated_open() {
  resolve_target_path "$@" || return $? # 校验并保存唯一目标路径。
  require_target_directory || return $? # Java 配置仅作用于明确的工程目录。
  select_jdk17 || return $? # 发现并复验实际 JDK 主版本为 17。
  activate_jdk17 || return $? # 导出本次启动环境并按需保存 jenv 目录配置。
  open_target || return $? # 启动目标编辑器，保留启动失败状态。
  success_echo "操作完成。日志：$LOG_FILE" # 输出成功结果和日志位置。
}
# 编排自述、运行环境和目标打开流程。
main() {
  show_readme_and_wait # 展示内置自述，确认失败时停止。
  initialize_script_runtime # 确认后固定环境并初始化日志。
  run_validated_open "$@" # 校验目标并完成业务，返回真实结果。
}

main "$@"
