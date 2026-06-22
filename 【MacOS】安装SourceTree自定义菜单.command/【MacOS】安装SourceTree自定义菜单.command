#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】安装SourceTree自定义菜单.command
# - 核心用途：用 fzf 在 actions.plist 与 Sourcetree 当前配置之间双向同步。
# - 影响范围：可能覆盖当前脚本包内 actions.plist，或覆盖当前用户 Sourcetree 的 actions.plist。
# - 运行提示：运行后会先打印内置自述；必须通过 fzf 明确选择同步方向。

SCRIPT_PATH="${0:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"
SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

TARGET_SOURCETREE_DIR="${HOME}/Library/Application Support/SourceTree"
TARGET_ACTIONS_PLIST="${TARGET_SOURCETREE_DIR}/actions.plist"
LOCAL_ACTIONS_PLIST="${SCRIPT_DIR}/actions.plist"
HOME_PACKAGE_ROOT="${HOME}/SourceTree.command"
REPO_PACKAGE_ROOT="${HOME}/Documents/Github/JobsGenesis/SourceTree.command"
INSTALL_DIR_NAME="${SCRIPT_DIR:t}"
SOURCETREE_APP_NAME="Sourcetree"
SOURCETREE_PROCESS_NAME="Sourcetree"

log()            { printf "%b\n" "$1" | tee -a "$LOG_FILE"; }
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

exit_with_error() {
  error_echo "$1"
  exit 1
}

initialize_script_runtime() {
  setopt NO_NOMATCH
  : > "$LOG_FILE"
}

show_script_intro_and_wait() {
  [[ -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" ]] && clear
  highlight_echo "============================== 脚本内置自述 =============================="
  note_echo "脚本名称：${SCRIPT_BASENAME}.command"
  note_echo "脚本路径：${SCRIPT_PATH}"
  note_echo "核心用途：通过 fzf 选择同步方向，在脚本包 actions.plist 和 Sourcetree 当前配置之间同步。"
  warn_echo "影响范围：会覆盖目标 actions.plist；覆盖前自动生成同目录 .bak.时间戳 备份。"
  note_echo "可选方向：1. 当前 actions.plist -> Sourcetree；2. Sourcetree 当前配置 -> 当前 actions.plist。"
  gray_echo "日志文件：${LOG_FILE}"
  highlight_echo "======================================================================="
  echo ""

  if [[ ! -t 0 ]]; then
    exit_with_error "当前没有可交互输入，无法打开 fzf 菜单；请在终端中运行。"
  fi
  read -r "?👉 已了解同步方向与覆盖风险，按回车继续；按 Ctrl+C 取消：" _
}

ensure_not_root_home() {
  if [[ "${HOME}" == "/var/root" || "${EUID}" -eq 0 ]]; then
    exit_with_error "请不要使用 sudo/root 执行本脚本。当前 HOME=${HOME}，会导致配置写入错误用户目录。"
  fi
}

check_environment() {
  command -v fzf >/dev/null 2>&1 || exit_with_error "未找到 fzf，请先执行：brew install fzf"
  command -v plutil >/dev/null 2>&1 || exit_with_error "未找到 plutil，无法校验 actions.plist。"
  command -v cmp >/dev/null 2>&1 || exit_with_error "未找到 cmp，无法比较文件。"
}

validate_plist() {
  local plist_path="$1"
  [[ -f "$plist_path" ]] || exit_with_error "未找到 actions.plist：${plist_path}"
  plutil -lint "$plist_path" >/dev/null || exit_with_error "actions.plist 格式校验失败：${plist_path}"
}

backup_file_if_exists() {
  local file_path="$1"
  [[ -f "$file_path" ]] || return 0
  local backup_file="${file_path}.bak.$(date '+%Y%m%d_%H%M%S')"
  cp -p "$file_path" "$backup_file" || exit_with_error "备份失败：${file_path}"
  success_echo "已备份：${backup_file}"
}

copy_file_with_backup() {
  local source_file="$1"
  local target_file="$2"
  validate_plist "$source_file"
  mkdir -p "$(dirname "$target_file")" || exit_with_error "创建目录失败：$(dirname "$target_file")"

  if [[ -f "$target_file" ]] && cmp -s "$source_file" "$target_file"; then
    success_echo "源文件与目标文件一致，无需覆盖。"
    gray_echo "源文件：${source_file}"
    gray_echo "目标文件：${target_file}"
    return 1
  fi

  backup_file_if_exists "$target_file"
  cp -p "$source_file" "$target_file" || exit_with_error "复制失败：${source_file} -> ${target_file}"
  validate_plist "$target_file"
  success_echo "已同步 actions.plist"
  gray_echo "源文件：${source_file}"
  gray_echo "目标文件：${target_file}"
  return 0
}

peer_install_dirs() {
  local home_install_dir="${HOME_PACKAGE_ROOT}/${INSTALL_DIR_NAME}"
  local repo_install_dir="${REPO_PACKAGE_ROOT}/${INSTALL_DIR_NAME}"

  print -r -- "$home_install_dir"
  [[ "$repo_install_dir" != "$home_install_dir" ]] && print -r -- "$repo_install_dir"
}

sync_local_to_peer_packages() {
  local peer_dir=""
  local peer_plist=""

  while IFS= read -r peer_dir; do
    [[ -n "$peer_dir" && -d "$peer_dir" ]] || continue
    [[ "$peer_dir" == "$SCRIPT_DIR" ]] && continue
    peer_plist="${peer_dir}/actions.plist"
    info_echo "同步当前 actions.plist 到等位脚本包：${peer_plist}"
    copy_file_with_backup "$LOCAL_ACTIONS_PLIST" "$peer_plist" || true
  done < <(peer_install_dirs)
}

sync_sourcetree_to_peer_packages() {
  local peer_dir=""
  local peer_plist=""

  while IFS= read -r peer_dir; do
    [[ -n "$peer_dir" && -d "$peer_dir" ]] || continue
    peer_plist="${peer_dir}/actions.plist"
    info_echo "同步 Sourcetree 当前配置到脚本包：${peer_plist}"
    copy_file_with_backup "$TARGET_ACTIONS_PLIST" "$peer_plist" || true
  done < <(peer_install_dirs)
}

detect_sourcetree_app_path() {
  local app_path=""
  for app_path in "/Applications/Sourcetree.app" "/Applications/SourceTree.app"; do
    [[ -d "$app_path" ]] && { printf "%s" "$app_path"; return 0; }
  done
  return 1
}

is_app_running() {
  local process_name="$1"
  pgrep -x "$process_name" >/dev/null 2>&1
}

restart_sourcetree_if_needed() {
  if ! is_app_running "$SOURCETREE_PROCESS_NAME"; then
    warn_echo "未检测到 Sourcetree 正在运行，本次不主动启动。"
    return 0
  fi

  local app_path="$(detect_sourcetree_app_path 2>/dev/null || true)"
  info_echo "检测到 Sourcetree 正在运行，准备重启以载入最新 actions.plist。"
  osascript -e "tell application \"${SOURCETREE_APP_NAME}\" to quit" >/dev/null 2>&1 || true
  sleep 2
  if is_app_running "$SOURCETREE_PROCESS_NAME"; then
    pkill -x "$SOURCETREE_PROCESS_NAME" >/dev/null 2>&1 || true
    sleep 1
  fi

  if [[ -n "$app_path" ]]; then
    open "$app_path" || warn_echo "重启 Sourcetree 失败，请手动打开。"
  else
    open -a "$SOURCETREE_APP_NAME" || warn_echo "重启 Sourcetree 失败，请手动打开。"
  fi
}

select_sync_action() {
  local choice=""
  choice="$(printf "%s\n%s\n" \
    "将目前的actions.plist同步至sourcetree里面" \
    "将目前sourcetree里面的配置同步至actions.plist里面" \
    | fzf --prompt="SourceTree actions.plist 同步方向 > " --height=40% --border --reverse --no-multi)" || true

  [[ -n "$choice" ]] || exit_with_error "未选择同步方向，已取消。"
  print -r -- "$choice"
}

sync_current_actions_to_sourcetree() {
  info_echo "准备将当前脚本包 actions.plist 同步到 Sourcetree。"
  validate_plist "$LOCAL_ACTIONS_PLIST"
  copy_file_with_backup "$LOCAL_ACTIONS_PLIST" "$TARGET_ACTIONS_PLIST"
  local copied="$?"
  sync_local_to_peer_packages
  [[ "$copied" -eq 0 ]] && restart_sourcetree_if_needed
}

sync_sourcetree_actions_to_current() {
  info_echo "准备将 Sourcetree 当前配置同步回脚本包 actions.plist。"
  validate_plist "$TARGET_ACTIONS_PLIST"
  sync_sourcetree_to_peer_packages
}

run_main_business_flow() {
  ensure_not_root_home
  check_environment
  validate_plist "$LOCAL_ACTIONS_PLIST"

  local choice=""
  choice="$(select_sync_action)"
  case "$choice" in
    "将目前的actions.plist同步至sourcetree里面")
      sync_current_actions_to_sourcetree
      ;;
    "将目前sourcetree里面的配置同步至actions.plist里面")
      sync_sourcetree_actions_to_current
      ;;
    *)
      exit_with_error "未知选项：${choice}"
      ;;
  esac

  success_echo "SourceTree 自定义菜单同步完成。"
  gray_echo "脚本包 actions.plist：${LOCAL_ACTIONS_PLIST}"
  gray_echo "Sourcetree actions.plist：${TARGET_ACTIONS_PLIST}"
  gray_echo "日志文件：${LOG_FILE}"
}

main() {
  initialize_script_runtime
  show_script_intro_and_wait
  run_main_business_flow "$@"
}

main "$@"
