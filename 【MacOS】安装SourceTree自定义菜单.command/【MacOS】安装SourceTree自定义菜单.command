#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】安装SourceTree自定义菜单.command
# - 核心用途：先把 SourceTree.command 库发送到目标目录，再维护 Sourcetree 自定义菜单 actions.plist。
# - 影响范围：可能替换目标目录下的 SourceTree.command；选择同步方向时可能覆盖 Sourcetree 当前用户 actions.plist。
# - 运行提示：运行后会先打印内置自述；脚本包缺少 actions.plist 时会从 Sourcetree 默认路径自动回收。

SCRIPT_PATH="${0:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"
SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
SOURCE_PACKAGE_ROOT="${SCRIPT_DIR:h}"
SOURCE_PACKAGE_NAME="${SOURCE_PACKAGE_ROOT:t}"
INSTALL_DIR_NAME="${SCRIPT_DIR:t}"
LOG_DIR="${TMPDIR:-/tmp}"
LOG_DIR="${LOG_DIR%/}"
LOG_FILE="${LOG_DIR}/${SCRIPT_BASENAME}.log"

TARGET_SOURCETREE_DIR="${HOME}/Library/Application Support/SourceTree"
TARGET_ACTIONS_PLIST="${TARGET_SOURCETREE_DIR}/actions.plist"
LOCAL_ACTIONS_PLIST="${SCRIPT_DIR}/actions.plist"
HOME_PACKAGE_ROOT="${HOME}/${SOURCE_PACKAGE_NAME}"
DEPLOYED_PACKAGE_ROOT=""
DEPLOY_TARGET_PACKAGE=""
SOURCETREE_APP_NAME="Sourcetree"
SOURCETREE_PROCESS_NAME="Sourcetree"
ACTION_SYNC_PACKAGE_TO_SOURCETREE="将脚本包 actions.plist 同步到 Sourcetree 当前用户配置"
ACTION_SYNC_SOURCETREE_TO_PACKAGES="将 Sourcetree 当前用户配置同步回所有脚本包 actions.plist"
ACTION_SYNC_CANCEL="取消同步"

# 输出日志并同步写入日志文件。
log() {
  printf "%b\n" "$1" | tee -a "$LOG_FILE"
}
# 输出绿色成功类信息。
color_echo() {
  log "\033[1;32m$1\033[0m"
}
# 输出蓝色提示类信息。
info_echo() {
  log "\033[1;34mℹ $1\033[0m"
}
# 输出绿色成功信息。
success_echo() {
  log "\033[1;32m✔ $1\033[0m"
}
# 输出黄色警告信息。
warn_echo() {
  log "\033[1;33m⚠ $1\033[0m"
}
# 输出黄色温馨提示。
warm_echo() {
  log "\033[1;33m$1\033[0m"
}
# 输出紫色说明信息。
note_echo() {
  log "\033[1;35m➤ $1\033[0m"
}
# 输出红色错误信息。
error_echo() {
  log "\033[1;31m✖ $1\033[0m"
}
# 输出红色纯文本错误信息。
err_echo() {
  log "\033[1;31m$1\033[0m"
}
# 输出紫色调试信息。
debug_echo() {
  log "\033[1;35m🐞 $1\033[0m"
}
# 输出青色高亮信息。
highlight_echo() {
  log "\033[1;36m🔹 $1\033[0m"
}
# 输出灰色次要信息。
gray_echo() {
  log "\033[0;90m$1\033[0m"
}
# 输出加粗信息。
bold_echo() {
  log "\033[1m$1\033[0m"
}
# 输出下划线信息。
underline_echo() {
  log "\033[4m$1\033[0m"
}
# 输出错误并立即终止脚本。
exit_with_error() {
  error_echo "$1"
  exit 1
}
# 打印脚本内置自述，并等待用户确认后再继续。
show_script_intro_and_wait() {
  if [[ -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" ]]; then
    clear
  fi

  print -r -- "============================== 脚本内置自述 =============================="
  print -r -- "脚本名称：${SCRIPT_BASENAME}.command"
  print -r -- "脚本路径：${SCRIPT_PATH}"
  print -r -- "第一阶段：发送 ${SOURCE_PACKAGE_NAME} 库到目标目录，默认目标父目录为当前用户家目录。"
  print -r -- "第二阶段：脚本包有 actions.plist 时通过 fzf 选择同步方向；没有时从 Sourcetree 默认路径自动回收。"
  print -r -- "影响范围：可能替换目标 ${SOURCE_PACKAGE_NAME} 目录；选择同步方向时可能覆盖 Sourcetree 的 actions.plist。"
  print -r -- "安全策略：目标库已存在时直接回车保留并继续；输入 YES 才会备份替换；actions.plist 覆盖前自动备份。"
  print -r -- "日志文件：${LOG_FILE}"
  print -r -- "取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。"
  print -r -- "============================================================================"
  echo ""

  if [[ ! -t 0 ]]; then
    print -u2 -r -- "当前没有可交互输入，请在终端中重新运行。"
    exit 1
  fi
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 初始化 Shell 运行选项和日志文件。
initialize_script_runtime() {
  set -e
  set -o pipefail
  setopt NO_NOMATCH
  : > "$LOG_FILE"
}
# 阻止 root 用户执行，避免把配置写入错误用户目录。
ensure_not_root_home() {
  if [[ "${HOME}" == "/var/root" || "${EUID}" -eq 0 ]]; then
    exit_with_error "请不要使用 sudo/root 执行本脚本。当前 HOME=${HOME}，会导致配置写入错误用户目录。"
  fi
}
# 检查发送 SourceTree.command 库需要的基础命令。
check_package_send_environment() {
  command -v ditto >/dev/null 2>&1 || exit_with_error "未找到 ditto，无法完整复制 ${SOURCE_PACKAGE_NAME}。"
  command -v git >/dev/null 2>&1 || exit_with_error "未找到 git，无法复制并校验 Git 元数据。"
}
# 检查 Sourcetree 自定义菜单同步需要的命令。
check_menu_environment() {
  command -v plutil >/dev/null 2>&1 || exit_with_error "未找到 plutil，无法校验 actions.plist。"
  command -v cmp >/dev/null 2>&1 || exit_with_error "未找到 cmp，无法比较文件。"
}
# 检查需要进入交互选择时的 fzf 依赖。
check_fzf_environment() {
  command -v fzf >/dev/null 2>&1 || exit_with_error "未找到 fzf，请先执行：brew install fzf"
}
# 去掉用户拖入路径时可能带上的外层引号和换行。
strip_outer_quotes() {
  local value="$1"
  value="${value%$'\r'}"
  value="${value%$'\n'}"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  print -r -- "$value"
}
# 展开用户输入路径里的当前用户家目录缩写。
expand_user_path() {
  local input_path="$1"
  if [[ "$input_path" == "~" ]]; then
    print -r -- "$HOME"
    return 0
  fi
  if [[ "$input_path" == "~/"* ]]; then
    print -r -- "${HOME}/${input_path#~/}"
    return 0
  fi
  print -r -- "$input_path"
}
# 把存在的路径规整为物理绝对路径。
normalize_existing_path() {
  local input_path="$1"
  if [[ -d "$input_path" ]]; then
    cd -P "$input_path" && pwd
    return 0
  fi
  print -r -- "$input_path"
}
# 把待创建路径规整为便于比较的绝对路径。
normalize_target_path() {
  local input_path="$1"
  local parent_dir="${input_path:h}"
  local base_name="${input_path:t}"

  if [[ -d "$input_path" ]]; then
    cd -P "$input_path" && pwd
    return 0
  fi
  if [[ -d "$parent_dir" ]]; then
    printf "%s/%s\n" "$(cd -P "$parent_dir" && pwd)" "$base_name"
    return 0
  fi
  print -r -- "$input_path"
}
# 判断数组里是否已经包含指定路径。
array_contains() {
  local needle="$1"
  shift || true
  local item=""
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}
# 根据用户输入生成最终 SourceTree.command 目标路径。
build_deploy_target_package_path() {
  local raw_input="$1"
  local cleaned_input=""
  local expanded_input=""
  local target_root=""

  cleaned_input="$(strip_outer_quotes "$raw_input")"
  if [[ -z "$cleaned_input" ]]; then
    target_root="$HOME"
  else
    target_root="$(expand_user_path "$cleaned_input")"
  fi
  target_root="${target_root%/}"

  if [[ "${target_root:t}" == "$SOURCE_PACKAGE_NAME" ]]; then
    print -r -- "$target_root"
  else
    print -r -- "${target_root}/${SOURCE_PACKAGE_NAME}"
  fi
}
# 询问用户要把 SourceTree.command 库发送到哪里。
ask_deploy_target_package() {
  local input_path=""
  echo ""
  note_echo "发送 ${SOURCE_PACKAGE_NAME} 库前，请确认目标目录。"
  gray_echo "直接回车：发送到当前用户家目录下的 ${SOURCE_PACKAGE_NAME}。"
  gray_echo "手动输入 / 拖入：可指定其它父目录；如果直接输入 ${SOURCE_PACKAGE_NAME} 路径，则按该路径处理。"
  read -r "?👉 请输入或拖入目标目录（直接回车使用 ${HOME}）：" input_path

  DEPLOY_TARGET_PACKAGE="$(build_deploy_target_package_path "$input_path")"
  DEPLOY_TARGET_PACKAGE="$(normalize_target_path "$DEPLOY_TARGET_PACKAGE")"
  DEPLOYED_PACKAGE_ROOT="$DEPLOY_TARGET_PACKAGE"
}
# 确认目标路径不会落在源库内部，避免递归复制。
ensure_deploy_target_is_safe() {
  local source_abs=""
  local target_abs=""

  source_abs="$(normalize_existing_path "$SOURCE_PACKAGE_ROOT")"
  target_abs="$(normalize_target_path "$DEPLOY_TARGET_PACKAGE")"

  if [[ "$target_abs" == "$source_abs" ]]; then
    warn_echo "源库和目标库是同一路径，跳过发送：${target_abs}"
    return 1
  fi
  if [[ "$target_abs" == "${source_abs}/"* ]]; then
    exit_with_error "目标路径不能放在源库内部，避免递归复制：${target_abs}"
  fi
  return 0
}
# 要求用户确认替换已有目标库。
confirm_replace_existing_package() {
  local input=""

  if [[ ! -e "$DEPLOY_TARGET_PACKAGE" ]]; then
    return 0
  fi

  echo ""
  warn_echo "目标库已存在：${DEPLOY_TARGET_PACKAGE}"
  gray_echo "直接回车：保留现有 ${SOURCE_PACKAGE_NAME}，继续进入 Sourcetree 自定义菜单安装流程。"
  gray_echo "输入 YES 后回车：备份旧目标库，再写入新的 ${SOURCE_PACKAGE_NAME}，随后继续安装流程。"
  IFS= read -r "input?👉 直接回车继续；输入 YES 备份替换后继续："
  if [[ "$input" == "YES" ]]; then
    return 0
  fi

  [[ -n "$input" ]] && warn_echo "输入不是 YES，本次保留现有 ${SOURCE_PACKAGE_NAME} 并继续。"
  return 1
}
# 复制源库工作树到临时目录。
copy_source_worktree_to_temp() {
  local temp_package="$1"
  ditto "$SOURCE_PACKAGE_ROOT" "$temp_package" || exit_with_error "复制工作树失败：${SOURCE_PACKAGE_ROOT} -> ${temp_package}"
}
# 把子 Git 的真实 Git 目录复制成目标库里的独立 .git。
copy_git_metadata_to_temp() {
  local temp_package="$1"
  local source_git_dir=""

  source_git_dir="$(git -C "$SOURCE_PACKAGE_ROOT" rev-parse --absolute-git-dir 2>/dev/null || true)"
  if [[ -z "$source_git_dir" || ! -d "$source_git_dir" ]]; then
    warn_echo "源库没有可复制的 Git 元数据，本次只发送工作树：${SOURCE_PACKAGE_ROOT}"
    return 0
  fi

  rm -rf "${temp_package}/.git"
  ditto "$source_git_dir" "${temp_package}/.git" || exit_with_error "复制 Git 元数据失败：${source_git_dir}"
  git -C "$temp_package" config --local --unset core.worktree 2>/dev/null || true
  git -C "$temp_package" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit_with_error "目标临时库 Git 元数据校验失败：${temp_package}"
  success_echo "已把 Git 元数据复制为目标库独立 .git。"
}
# 用临时目录替换最终目标库，并为旧目标生成备份。
replace_target_package_with_temp() {
  local temp_package="$1"
  local target_parent="${DEPLOY_TARGET_PACKAGE:h}"
  local backup_package=""

  mkdir -p "$target_parent" || exit_with_error "创建目标父目录失败：${target_parent}"
  if [[ -e "$DEPLOY_TARGET_PACKAGE" ]]; then
    backup_package="${DEPLOY_TARGET_PACKAGE}.bak.$(date '+%Y%m%d_%H%M%S')"
    mv "$DEPLOY_TARGET_PACKAGE" "$backup_package" || exit_with_error "备份旧目标库失败：${DEPLOY_TARGET_PACKAGE}"
    success_echo "已备份旧目标库：${backup_package}"
  fi

  if ! mv "$temp_package" "$DEPLOY_TARGET_PACKAGE"; then
    if [[ -n "$backup_package" && -e "$backup_package" && ! -e "$DEPLOY_TARGET_PACKAGE" ]]; then
      mv "$backup_package" "$DEPLOY_TARGET_PACKAGE" || true
    fi
    exit_with_error "写入目标库失败：${DEPLOY_TARGET_PACKAGE}"
  fi
}
# 发送 SourceTree.command 库到用户指定目录。
send_package_to_user_directory() {
  local target_parent=""
  local temp_package=""

  ask_deploy_target_package
  ensure_deploy_target_is_safe || return 0
  if ! confirm_replace_existing_package; then
    info_echo "已保留现有 ${SOURCE_PACKAGE_NAME}，继续进入 Sourcetree 自定义菜单安装流程。"
    return 0
  fi

  target_parent="${DEPLOY_TARGET_PACKAGE:h}"
  mkdir -p "$target_parent" || exit_with_error "创建目标父目录失败：${target_parent}"
  temp_package="${target_parent}/.${SOURCE_PACKAGE_NAME}.tmp.$(date '+%Y%m%d_%H%M%S').$$"
  rm -rf "$temp_package"
  copy_source_worktree_to_temp "$temp_package"
  copy_git_metadata_to_temp "$temp_package"
  replace_target_package_with_temp "$temp_package"
  success_echo "已发送 ${SOURCE_PACKAGE_NAME} 到：${DEPLOY_TARGET_PACKAGE}"
}
# 提示用户库发送步骤已经结束，接下来进入菜单安装。
announce_menu_install_phase() {
  echo ""
  highlight_echo "============================== 安装 SourceTree 自定义菜单 =============================="
  note_echo "${SOURCE_PACKAGE_NAME} 发送步骤已结束，下面开始处理 Sourcetree actions.plist。"
  highlight_echo "====================================================================================="
}
# 校验 actions.plist 是否存在且格式合法。
validate_plist() {
  local plist_path="$1"
  [[ -f "$plist_path" ]] || exit_with_error "未找到 actions.plist：${plist_path}"
  plutil -lint "$plist_path" >/dev/null || exit_with_error "actions.plist 格式校验失败：${plist_path}"
}
# 校验当前脚本包里的 actions.plist。
validate_local_actions_plist() {
  validate_plist "$LOCAL_ACTIONS_PLIST"
}
# 对目标文件生成覆盖前备份。
backup_file_if_exists() {
  local file_path="$1"
  [[ -f "$file_path" ]] || return 0
  local backup_file="${file_path}.bak.$(date '+%Y%m%d_%H%M%S')"
  cp -p "$file_path" "$backup_file" || exit_with_error "备份失败：${file_path}"
  success_echo "已备份：${backup_file}"
}
# 复制 actions.plist 到目标位置，覆盖前自动备份。
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
# 输出所有可同步的等位脚本包目录。
peer_install_dirs() {
  local -a package_roots
  local -a printed_dirs
  local package_root=""
  local install_dir=""

  package_roots=("$HOME_PACKAGE_ROOT" "$SOURCE_PACKAGE_ROOT")
  if [[ -n "$DEPLOYED_PACKAGE_ROOT" ]]; then
    package_roots+=("$DEPLOYED_PACKAGE_ROOT")
  fi

  printed_dirs=()
  for package_root in "${package_roots[@]}"; do
    install_dir="${package_root}/${INSTALL_DIR_NAME}"
    [[ -d "$install_dir" ]] || continue
    if ! array_contains "$install_dir" "${printed_dirs[@]}"; then
      print -r -- "$install_dir"
      printed_dirs+=("$install_dir")
    fi
  done
}
# 把当前脚本包 actions.plist 同步到其它等位脚本包。
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
# 把 Sourcetree 当前 actions.plist 同步回所有等位脚本包。
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
# 输出当前参与同步的脚本包 actions.plist 路径。
log_peer_actions_plist_paths() {
  local peer_dir=""

  while IFS= read -r peer_dir; do
    [[ -n "$peer_dir" && -d "$peer_dir" ]] || continue
    gray_echo "脚本包 actions.plist：${peer_dir}/actions.plist"
  done < <(peer_install_dirs)
}
# 输出 Sourcetree 自定义菜单同步结果。
finish_sourcetree_menu_sync() {
  success_echo "SourceTree 自定义菜单同步完成。"
  log_peer_actions_plist_paths
  gray_echo "Sourcetree actions.plist：${TARGET_ACTIONS_PLIST}"
  gray_echo "日志文件：${LOG_FILE}"
}
# 查找 Sourcetree 应用路径。
detect_sourcetree_app_path() {
  local app_path=""
  for app_path in "/Applications/Sourcetree.app" "/Applications/SourceTree.app"; do
    if [[ -d "$app_path" ]]; then
      printf "%s" "$app_path"
      return 0
    fi
  done
  return 1
}
# 判断指定应用进程是否正在运行。
is_app_running() {
  local process_name="$1"
  pgrep -x "$process_name" >/dev/null 2>&1
}
# 如果 Sourcetree 正在运行，则重启以加载新的 actions.plist。
restart_sourcetree_if_needed() {
  local app_path=""

  if ! is_app_running "$SOURCETREE_PROCESS_NAME"; then
    warn_echo "未检测到 Sourcetree 正在运行，本次不主动启动。"
    return 0
  fi

  app_path="$(detect_sourcetree_app_path 2>/dev/null || true)"
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
# 使用 fzf 选择 actions.plist 同步方向。
select_sync_action() {
  local choice=""
  check_fzf_environment
  choice="$(printf "%s\n%s\n%s\n" \
    "$ACTION_SYNC_PACKAGE_TO_SOURCETREE" \
    "$ACTION_SYNC_SOURCETREE_TO_PACKAGES" \
    "$ACTION_SYNC_CANCEL" \
    | fzf --prompt="SourceTree actions.plist 同步方向 > " --height=40% --border --reverse --no-multi)" || true

  [[ -n "$choice" ]] || choice="$ACTION_SYNC_CANCEL"
  print -r -- "$choice"
}
# 把当前脚本包 actions.plist 安装到 Sourcetree 当前用户配置。
sync_current_actions_to_sourcetree() {
  local copied=0

  info_echo "准备将当前脚本包 actions.plist 同步到 Sourcetree。"
  validate_plist "$LOCAL_ACTIONS_PLIST"
  copy_file_with_backup "$LOCAL_ACTIONS_PLIST" "$TARGET_ACTIONS_PLIST" || copied="$?"
  sync_local_to_peer_packages
  [[ "$copied" -eq 0 ]] && restart_sourcetree_if_needed
}
# 把 Sourcetree 当前用户配置同步回所有脚本包。
sync_sourcetree_actions_to_current() {
  info_echo "准备将 Sourcetree 当前配置同步回所有脚本包 actions.plist。"
  validate_plist "$TARGET_ACTIONS_PLIST"
  sync_sourcetree_to_peer_packages
}
# 本地缺少 actions.plist 时，从 Sourcetree 默认路径自动回收到脚本包。
sync_missing_local_actions_from_sourcetree() {
  [[ ! -f "$LOCAL_ACTIONS_PLIST" ]] || return 1

  warn_echo "当前脚本包未找到 actions.plist，跳过 fzf 选择。"
  info_echo "准备从 Sourcetree 默认配置备份到脚本包 actions.plist。"
  validate_plist "$TARGET_ACTIONS_PLIST"
  sync_sourcetree_to_peer_packages
  finish_sourcetree_menu_sync
  return 0
}
# 执行 Sourcetree 自定义菜单安装和回收流程。
run_sourcetree_menu_install_flow() {
  local choice=""

  sync_missing_local_actions_from_sourcetree && return 0
  validate_local_actions_plist
  choice="$(select_sync_action)"
  case "$choice" in
    "$ACTION_SYNC_PACKAGE_TO_SOURCETREE")
      sync_current_actions_to_sourcetree
      ;;
    "$ACTION_SYNC_SOURCETREE_TO_PACKAGES")
      sync_sourcetree_actions_to_current
      ;;
    "$ACTION_SYNC_CANCEL")
      info_echo "已选择取消同步，本次不覆盖任何 actions.plist。"
      log_peer_actions_plist_paths
      gray_echo "Sourcetree actions.plist：${TARGET_ACTIONS_PLIST}"
      gray_echo "日志文件：${LOG_FILE}"
      return 0
      ;;
    *)
      exit_with_error "未知选项：${choice}"
      ;;
  esac

  finish_sourcetree_menu_sync
}
# 编排脚本说明、库发送和 Sourcetree 菜单安装流程。
main() {
  show_script_intro_and_wait # 展示脚本内置自述，并等待用户确认整体影响范围。
  initialize_script_runtime # 初始化 Shell 选项和日志文件，后续失败及时中断。
  ensure_not_root_home # 阻止 sudo/root 写入错误用户目录。
  check_package_send_environment # 检查发送 SourceTree.command 库所需命令。
  send_package_to_user_directory # 先把 SourceTree.command 库发送到目标目录。
  announce_menu_install_phase # 明确库发送阶段结束，准备安装 SourceTree 自定义菜单。
  check_menu_environment # 检查 plutil 和 cmp 等菜单同步基础依赖。
  run_sourcetree_menu_install_flow "$@" # 按本地 actions.plist 状态同步 Sourcetree 自定义菜单。
}

main "$@"
