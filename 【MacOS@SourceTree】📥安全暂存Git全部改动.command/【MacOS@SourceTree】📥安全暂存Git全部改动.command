#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】📥安全暂存Git全部改动.command
# - 核心用途：统一暂存当前 Git 仓库中的新增、修改、删除和重命名。
# - 关键场景：正确处理“已跟踪文件变为同名目录”等 Sourcetree 分步暂存容易报错的转换。
# - 影响范围：只修改 Git 索引，不提交、不推送、不删除工作区真实文件。

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export LANG="${LANG:-zh_CN.UTF-8}"
export LC_CTYPE="${LC_CTYPE:-UTF-8}"

# 解析脚本真实路径，兼容 Sourcetree 只传入脚本名的运行环境。
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
    (cd "$(dirname "$candidate")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename "$candidate")")
    return 0
  done

  printf '%s/%s\n' "$PWD" "$script_name"
}

SCRIPT_PATH="$(resolve_script_path)"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd -P)"
SCRIPT_BASENAME="$(basename "$SCRIPT_PATH" | sed 's/\.[^.]*$//')"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
IS_SOURCETREE_RUNTIME=0
PLAIN_OUTPUT=0
REPO_ROOT=""

# 识别 Sourcetree 自定义动作的非交互运行环境。
is_sourcetree_runtime() {
  env | grep -Eqi '^SOURCETREE|^SOURCE_TREE' && return 0
  [[ "$0" != /* && "$SCRIPT_PATH" == "${HOME}/SourceTree.command/"* ]] && return 0

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

# 移除 ANSI 颜色码，避免 Sourcetree 输出窗口显示乱码。
strip_ansi_text() {
  perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}

# 同步输出终端日志和本地日志文件。
log() {
  if [[ "$PLAIN_OUTPUT" == "1" ]]; then
    printf '%b\n' "$1" | strip_ansi_text | tee -a "$LOG_FILE"
  else
    printf '%b\n' "$1" | tee -a "$LOG_FILE"
  fi
}

# 输出信息级别日志。
info_echo()    { log "\033[1;34mℹ $1\033[0m"; }
# 输出成功级别日志。
success_echo() { log "\033[1;32m✔ $1\033[0m"; }
# 输出警告级别日志。
warn_echo()    { log "\033[1;33m⚠ $1\033[0m"; }
# 输出说明级别日志。
note_echo()    { log "\033[1;35m➤ $1\033[0m"; }
# 输出错误级别日志。
error_echo()   { log "\033[1;31m✖ $1\033[0m"; }
# 输出次要信息日志。
gray_echo()    { log "\033[0;90m$1\033[0m"; }
# 输出高亮分隔信息。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }

# 初始化 zsh 选项、日志与 Sourcetree 输出策略。
initialize_script_runtime() {
  emulate -R zsh
  set -e
  set -o pipefail
  setopt NO_NOMATCH
  : > "$LOG_FILE"

  if is_sourcetree_runtime; then
    IS_SOURCETREE_RUNTIME=1
  fi
  if [[ "$IS_SOURCETREE_RUNTIME" == "1" || ! -t 1 || -z "${TERM:-}" || "${TERM:-}" == "dumb" || -n "${NO_COLOR:-}" ]]; then
    PLAIN_OUTPUT=1
  fi
}

# 展示内置自述，终端模式等待确认，Sourcetree 模式直接继续。
show_script_intro_and_wait() {
  if [[ "$IS_SOURCETREE_RUNTIME" != "1" && -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 =============================="
  note_echo "脚本名称：${SCRIPT_BASENAME}.command"
  note_echo "核心行为：对当前仓库执行 git add -A -- .，完整刷新 Git 索引。"
  note_echo "适用场景：新增、修改、删除、重命名，以及文件与同名目录相互转换。"
  note_echo "安全边界：只暂存变更；不提交、不推送、不使用 -f 强制添加已忽略文件。"
  note_echo "文档关系：同目录 README.md 只作为静态说明，脚本运行时不依赖它。"
  gray_echo "日志文件：${LOG_FILE}"
  highlight_echo "============================================================================="

  if [[ "$IS_SOURCETREE_RUNTIME" == "1" ]]; then
    gray_echo "已识别 Sourcetree 自定义动作，跳过回车等待。"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    error_echo "当前不是 Sourcetree，且没有可交互输入。"
    return 1
  fi

  echo ""
  read -r "?👉 已阅读说明，按回车继续执行；按 Ctrl+C 取消：" _
}

# 从 Sourcetree 参数或当前目录解析 Git 仓库根目录。
resolve_repo_root() {
  local target="${1:-$PWD}"

  if [[ -f "$target" ]]; then
    target="$(dirname "$target")"
  fi
  if [[ ! -d "$target" ]]; then
    error_echo "目标路径不存在：${target}"
    return 1
  fi
  if ! REPO_ROOT="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)"; then
    error_echo "目标路径不在 Git 工作树内：${target}"
    return 1
  fi

  success_echo "已识别仓库：${REPO_ROOT}"
}

# 统一暂存工作区与索引中的全部改动。
stage_all_changes() {
  info_echo "正在安全暂存全部改动 ..."
  git -C "$REPO_ROOT" add -A -- .
  success_echo "Git 索引已刷新。"
}

# 输出暂存结果，便于在 Sourcetree 日志窗口中直接核对。
print_staged_summary() {
  local summary=""
  summary="$(git -C "$REPO_ROOT" diff --cached --name-status)"

  if [[ -z "$summary" ]]; then
    info_echo "当前没有待提交的暂存变更。"
    return 0
  fi

  note_echo "已暂存变更："
  printf '%s\n' "$summary" | tee -a "$LOG_FILE"
}

# 串联自述、仓库识别、索引刷新与结果输出。
run_main_flow() {
  initialize_script_runtime
  show_script_intro_and_wait
  resolve_repo_root "${1:-$PWD}"
  stage_all_changes
  print_staged_summary
  success_echo "处理完成。请回到 Sourcetree 刷新后检查并提交。"
  gray_echo "日志文件：${LOG_FILE}"
}

main() {
  # 主入口只委托完整业务流程，避免交互与 Git 操作散落。
  run_main_flow "$@"
}

main "$@"
