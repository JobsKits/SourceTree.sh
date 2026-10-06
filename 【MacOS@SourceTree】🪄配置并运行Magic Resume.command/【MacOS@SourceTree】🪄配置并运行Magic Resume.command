#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】🪄配置并运行Magic Resume.command
# - 核心用途：校验或同级拉取 JOYCEQL/magic-resume，安装依赖并后台启动开发服务器。
# - 影响范围：可能新建同级仓库目录、安装 Node.js / pnpm、写入 node_modules，并启动本地 3000 端口服务。
# - 运行提示：运行后会先打印内置自述；Sourcetree 模式无交互连续执行，终端模式确认后继续。

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
EXPECTED_DISPLAY_SLUG="JOYCEQL/magic-resume"
EXPECTED_SLUG="joyceql/magic-resume"
EXPECTED_HTTPS_URL="https://github.com/JOYCEQL/magic-resume"
CLONE_URL="https://github.com/JOYCEQL/magic-resume.git"
LOCAL_URL="http://localhost:3000"
LOCAL_PORT="3000"

SCRIPT_ENTRY_SOURCE="$0"
SCRIPT_PATH=""
SCRIPT_DIR=""
SCRIPT_BASENAME=""
LOG_FILE=""
DEV_SERVER_LOG=""
DEV_SERVER_PID_FILE=""
IS_SOURCETREE_RUNTIME=0
PLAIN_OUTPUT=0
RUNTIME_INITIALIZED=0

INPUT_REPO_ROOT=""
REPO_ROOT=""
REPO_INPUT_SOURCE=""
MATCHED_REMOTE=""
SIBLING_TARGET=""
SIBLING_TARGET_REQUIRES_CLONE=0
SERVER_REUSED=0

BREW_BIN=""
NODE_BIN=""
NPM_BIN=""
PNPM_BIN=""
PACKAGE_MANAGER_SPEC="pnpm@latest"

# 从绝对路径、当前目录和两个固定脚本库中找回脚本真实路径。
resolve_script_path() {
  local script_source="$SCRIPT_ENTRY_SOURCE"
  local script_name="$(basename -- "$script_source")"
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
# 准备仅用于首屏自述的脚本路径和日志名称，不提前写文件。
resolve_script_metadata() {
  local temp_root="${TMPDIR:-/tmp}"

  SCRIPT_PATH="$(resolve_script_path)"
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd -P)"
  SCRIPT_BASENAME="$(basename "$SCRIPT_PATH" | sed 's/\.[^.]*$//')"
  temp_root="${temp_root%/}"
  LOG_FILE="${temp_root}/${SCRIPT_BASENAME}.log"
  DEV_SERVER_LOG="${temp_root}/${SCRIPT_BASENAME}-dev.log"
  DEV_SERVER_PID_FILE="${temp_root}/${SCRIPT_BASENAME}-dev.pid"
}
# 组合环境变量、脚本解析路径和父进程链识别 Sourcetree 自定义动作。
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
# 去除 ANSI 控制字符，避免 Sourcetree 输出窗口和日志出现乱码。
strip_ansi_stream() {
  if command -v perl >/dev/null 2>&1; then
    perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e\][^\a]*(?:\a|\e\\)//g; s/\e[()][A-Za-z0-9]//g'
  else
    cat
  fi
}
# 在任何首屏输出前配置 Sourcetree 和非 TTY 场景的纯文本环境。
prepare_plain_output_context() {
  [[ -n "${TERM:-}" ]] || export TERM="dumb"
  if [[ "$IS_SOURCETREE_RUNTIME" == "1" || ! -t 1 || "$TERM" == "dumb" || -n "${NO_COLOR:-}" || "${JOBS_PLAIN_OUTPUT:-0}" == "1" ]]; then
    PLAIN_OUTPUT=1
    export NO_COLOR=1
    export FORCE_COLOR=0
    export CLICOLOR=0
    export ANSI_COLORS_DISABLED=1
    export npm_config_color=false
  else
    PLAIN_OUTPUT=0
  fi
}
# 同步输出运行信息；确认前只写屏幕，运行态初始化后同时写入日志。
log() {
  if [[ "$RUNTIME_INITIALIZED" == "1" ]]; then
    if [[ "$PLAIN_OUTPUT" == "1" ]]; then
      printf "%b\n" "$1" | strip_ansi_stream | tee -a "$LOG_FILE"
    else
      printf "%b\n" "$1" | tee -a "$LOG_FILE"
    fi
  elif [[ "$PLAIN_OUTPUT" == "1" ]]; then
    printf "%b\n" "$1" | strip_ansi_stream
  else
    printf "%b\n" "$1"
  fi
}
# 输出正常绿色信息。
color_echo()     { log "\033[1;32m$1\033[0m"; }
# 输出蓝色信息提示。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 输出绿色成功提示。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 输出黄色警告提示。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 输出黄色温馨提示。
warm_echo()      { log "\033[1;33m$1\033[0m"; }
# 输出紫色说明提示。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 输出红色错误提示。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 输出红色纯文本错误。
err_echo()       { log "\033[1;31m$1\033[0m"; }
# 输出紫色调试提示。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
# 输出青色高亮提示。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 输出灰色次要信息。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 输出加粗信息。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 输出下划线信息。
underline_echo() { log "\033[4m$1\033[0m"; }
# 打印内置自述，并按真实运行入口决定是否等待回车。
show_script_intro_and_wait() {
  resolve_script_metadata
  is_sourcetree_runtime && IS_SOURCETREE_RUNTIME=1
  prepare_plain_output_context

  if [[ "$IS_SOURCETREE_RUNTIME" != "1" && -t 1 && "$TERM" != "dumb" ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 ==============================" | jobs_intro_style title
  note_echo "脚本名称：${SCRIPT_BASENAME}.command" | jobs_intro_style title
  note_echo "核心用途：校验当前仓库；不匹配时先扫描全部同级仓库，确实不存在 ${EXPECTED_DISPLAY_SLUG} 才创建目录并克隆。" | jobs_intro_style body
  note_echo "运行策略：开发服务器使用 nohup 脱离终端后台运行；3000 端口就绪后自动打开浏览器，脚本随即结束。" | jobs_intro_style body
  warn_echo "影响范围：可能创建同级目录、安装 Node.js / pnpm、写入 node_modules，并将当前仓库已有的前台 Vite 服务重启为后台服务。" | jobs_intro_style body
  gray_echo "仓库地址：${EXPECTED_HTTPS_URL}" | jobs_intro_style body
  gray_echo "业务日志：${LOG_FILE}" | jobs_intro_style body
  gray_echo "服务日志：${DEV_SERVER_LOG}" | jobs_intro_style body
  gray_echo "取消方式：终端模式可在确认前按 Ctrl+C；Sourcetree 模式按自定义动作约定无交互连续执行。" | jobs_intro_style body
  highlight_echo "============================================================================" | jobs_intro_style title
  log "" | jobs_intro_style body

  if [[ "$IS_SOURCETREE_RUNTIME" == "1" ]]; then
    gray_echo "已识别为 Sourcetree 自定义动作，将跳过交互并连续执行。" | jobs_intro_style body
    return 0
  fi
  if [[ ! -t 0 ]]; then
    error_echo "当前不是 Sourcetree，且没有可交互输入；请在终端中重新运行。"
    return 1
  fi
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 在用户确认后初始化 Shell 选项、PATH、日志文件和输出环境。
initialize_script_runtime() {
  setopt NO_NOMATCH
  setopt PIPE_FAIL
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
  : > "$LOG_FILE"
  RUNTIME_INITIALIZED=1
  prepare_plain_output_context
  info_echo "运行环境初始化完成。"
  gray_echo "脚本路径：${SCRIPT_PATH}"
}
# 输出错误和日志位置后终止脚本。
die() {
  error_echo "$1"
  err_echo "业务日志：${LOG_FILE}"
  exit 1
}
# 执行外部命令并把去色后的输出同步写入业务日志。
run_cmd() {
  local title="$1"
  shift
  info_echo "$title"
  gray_echo "命令：$*"
  "$@" 2>&1 | strip_ansi_stream | tee -a "$LOG_FILE"
  local command_status="${pipestatus[1]}"
  if [[ "$command_status" -ne 0 ]]; then
    error_echo "命令执行失败：${title}"
    return "$command_status"
  fi
  success_echo "完成：${title}"
}
# 清理 SourceTree 参数或拖入路径外围的引号、file 协议和换行。
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
# 将用户输入路径还原为可安全解析的本机路径。
normalize_user_input_path() {
  local value="$(strip_outer_quotes "$1")"
  if [[ "$value" == "~" ]]; then
    value="$HOME"
  elif [[ "$value" == "~/"* ]]; then
    value="${HOME}/${value#~/}"
  fi
  value="${(Q)value}"
  print -r -- "$value"
}
# 从目录或仓库内文件向上解析 Git 工作区根目录。
resolve_repo_root_from_candidate() {
  local candidate="$(normalize_user_input_path "$1")"
  local candidate_abs=""

  [[ -e "$candidate" ]] || return 1
  [[ -d "$candidate" ]] || candidate="${candidate:h}"
  candidate_abs="$(cd "$candidate" 2>/dev/null && pwd -P || true)"
  [[ -n "$candidate_abs" ]] || return 1
  git -C "$candidate_abs" rev-parse --show-toplevel 2>/dev/null
}
# 在终端独立运行时提示输入一个可识别的 Git 仓库路径。
prompt_input_repository() {
  local input_path=""
  local resolved=""

  while true; do
    read -r "input_path?👉 请输入或拖入当前 Git 仓库目录（Ctrl+C 取消）：" input_path
    resolved="$(resolve_repo_root_from_candidate "$input_path" 2>/dev/null || true)"
    if [[ -n "$resolved" ]]; then
      INPUT_REPO_ROOT="$resolved"
      REPO_INPUT_SOURCE="手动输入/拖入路径"
      return 0
    fi
    warn_echo "无法从该路径识别 Git 仓库，请重新输入。"
  done
}
# 从 SourceTree 的 REPO 参数、命令行参数或当前目录确定运行仓库。
resolve_input_repository() {
  local candidate=""
  local resolved=""

  if [[ "$#" -gt 0 ]]; then
    for candidate in "$@"; do
      resolved="$(resolve_repo_root_from_candidate "$candidate" 2>/dev/null || true)"
      [[ -n "$resolved" ]] || continue
      INPUT_REPO_ROOT="$resolved"
      REPO_INPUT_SOURCE="SourceTree / 命令行参数"
      break
    done
    if [[ -z "$INPUT_REPO_ROOT" ]]; then
      resolved="$(resolve_repo_root_from_candidate "$*" 2>/dev/null || true)"
      [[ -n "$resolved" ]] || die "传入参数无法识别为 Git 仓库。SourceTree 自定义动作参数请填写 \$REPO。"
      INPUT_REPO_ROOT="$resolved"
      REPO_INPUT_SOURCE="SourceTree / 命令行参数"
    fi
  else
    resolved="$(resolve_repo_root_from_candidate "$PWD" 2>/dev/null || true)"
    if [[ -n "$resolved" ]]; then
      INPUT_REPO_ROOT="$resolved"
      REPO_INPUT_SOURCE="当前工作目录"
    elif [[ "$IS_SOURCETREE_RUNTIME" == "1" || ! -t 0 ]]; then
      die "未收到仓库路径且当前目录不是 Git 仓库。SourceTree 自定义动作参数请填写 \$REPO。"
    else
      prompt_input_repository
    fi
  fi

  success_echo "已识别运行仓库：${INPUT_REPO_ROOT}"
  gray_echo "仓库来源：${REPO_INPUT_SOURCE}"
}
# 把 GitHub 的常见 HTTPS、SSH 和 git 协议地址归一化为小写 owner/repo。
normalize_github_remote() {
  local url="$1"
  local slug=""

  url="${url//$'\r'/}"
  url="${url//$'\n'/}"
  url="${url%/}"
  url="${url%.git}"

  case "$url" in
    https://github.com/*) slug="${url#https://github.com/}" ;;
    http://github.com/*) slug="${url#http://github.com/}" ;;
    git@github.com:*) slug="${url#git@github.com:}" ;;
    ssh://git@github.com/*) slug="${url#ssh://git@github.com/}" ;;
    git://github.com/*) slug="${url#git://github.com/}" ;;
    github.com:*) slug="${url#github.com:}" ;;
    github.com/*) slug="${url#github.com/}" ;;
    *) slug="" ;;
  esac

  slug="${slug%.git}"
  slug="${slug%/}"
  print -r -- "${(L)slug}"
}
# 检查目标目录的任意 remote 是否指向官方 magic-resume 仓库。
repository_matches_expected() {
  local repository="$1"
  local remotes_output="$(git -C "$repository" remote 2>/dev/null || true)"
  local urls_output=""
  local remote=""
  local url=""

  [[ -n "$remotes_output" ]] || return 1
  for remote in ${(f)remotes_output}; do
    urls_output="$(git -C "$repository" remote get-url --all "$remote" 2>/dev/null || true)"
    for url in ${(f)urls_output}; do
      if [[ "$(normalize_github_remote "$url")" == "$EXPECTED_SLUG" ]]; then
        MATCHED_REMOTE="${remote}:${url}"
        return 0
      fi
    done
  done
  return 1
}
# 判断候选文件夹是否存在且完全为空。
directory_is_empty() {
  [[ -d "$1" ]] || return 1
  [[ -z "$(find "$1" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]
}
# 扫描父目录第一层的全部文件夹，寻找任意名称但 remote 匹配的同级仓库。
find_existing_expected_sibling_repository() {
  local parent_dir="${INPUT_REPO_ROOT:h}"
  local sibling=""
  local sibling_abs=""
  local repository_root=""

  info_echo "正在扫描当前仓库的全部同级目录：${parent_dir}"
  while IFS= read -r -d '' sibling; do
    [[ -d "$sibling" ]] || continue
    sibling_abs="$(cd "$sibling" 2>/dev/null && pwd -P || true)"
    [[ -n "$sibling_abs" && "$sibling_abs" != "$INPUT_REPO_ROOT" ]] || continue
    [[ -d "$sibling_abs/.git" || -f "$sibling_abs/.git" ]] || continue

    repository_root="$(git -C "$sibling_abs" rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "$repository_root" ]] || continue
    repository_root="$(cd "$repository_root" 2>/dev/null && pwd -P || true)"
    [[ "$repository_root" == "$sibling_abs" ]] || continue

    if repository_matches_expected "$sibling_abs"; then
      SIBLING_TARGET="$sibling_abs"
      SIBLING_TARGET_REQUIRES_CLONE=0
      success_echo "已在同级目录找到官方仓库：${SIBLING_TARGET}"
      gray_echo "匹配 remote：${MATCHED_REMOTE}"
      return 0
    fi
  done < <(
    find "$parent_dir" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -print0 2>/dev/null
  )

  warn_echo "同级目录中没有找到 ${EXPECTED_DISPLAY_SLUG}，将选择安全的空目录用于克隆。"
  return 1
}
# 确认同级目录不存在官方仓库后，选择可安全克隆的空路径。
select_sibling_target() {
  local parent_dir="${INPUT_REPO_ROOT:h}"
  local -a candidate_names=("magic-resume" "magic-resume-JOYCEQL")
  local index=0
  local candidate_name=""
  local candidate=""

  find_existing_expected_sibling_repository && return 0

  for index in {2..20}; do
    candidate_names+=("magic-resume-JOYCEQL-${index}")
  done

  for candidate_name in "${candidate_names[@]}"; do
    candidate="${parent_dir}/${candidate_name}"
    [[ "$candidate" == "$INPUT_REPO_ROOT" ]] && continue

    if [[ ! -e "$candidate" ]]; then
      SIBLING_TARGET="$candidate"
      SIBLING_TARGET_REQUIRES_CLONE=1
      return 0
    fi
    if [[ -d "$candidate" ]] && repository_matches_expected "$candidate"; then
      SIBLING_TARGET="$candidate"
      SIBLING_TARGET_REQUIRES_CLONE=0
      return 0
    fi
    if directory_is_empty "$candidate"; then
      SIBLING_TARGET="$candidate"
      SIBLING_TARGET_REQUIRES_CLONE=1
      return 0
    fi

    warn_echo "同级候选已被其它内容占用，已跳过：${candidate}"
  done

  die "当前仓库同级目录中没有可安全创建或复用的 magic-resume 路径。"
}
# 在空的同级目录中克隆官方仓库，不覆盖任何既有非空内容。
clone_expected_repository() {
  local target_preexisted=0
  [[ -e "$SIBLING_TARGET" ]] && target_preexisted=1

  if [[ "${JOBS_MAGIC_RESUME_DRY_RUN:-0}" == "1" ]]; then
    success_echo "Dry-run：计划创建/复用空目录并克隆 ${CLONE_URL}"
    gray_echo "目标目录：${SIBLING_TARGET}"
    exit 0
  fi

  if [[ "$target_preexisted" == "0" ]]; then
    mkdir "$SIBLING_TARGET" || die "无法创建同级空目录：${SIBLING_TARGET}"
    success_echo "已创建同级空目录：${SIBLING_TARGET}"
  elif ! directory_is_empty "$SIBLING_TARGET"; then
    die "克隆目标不是空目录，已停止以避免覆盖：${SIBLING_TARGET}"
  fi

  run_cmd "克隆 ${EXPECTED_DISPLAY_SLUG}" git clone "$CLONE_URL" "$SIBLING_TARGET" || die "仓库克隆失败；已保留现场，请根据日志检查网络或 Git 凭据。"
  repository_matches_expected "$SIBLING_TARGET" || die "克隆完成后 remote 校验失败：${SIBLING_TARGET}"
}
# 使用当前正确仓库，或切换到同级已存在/新克隆的官方仓库。
select_magic_resume_repository() {
  if repository_matches_expected "$INPUT_REPO_ROOT"; then
    REPO_ROOT="$INPUT_REPO_ROOT"
    success_echo "当前仓库校验通过：${MATCHED_REMOTE}"
  else
    warn_echo "当前仓库不是 ${EXPECTED_HTTPS_URL}，开始处理同级目录。"
    select_sibling_target
    if [[ "$SIBLING_TARGET_REQUIRES_CLONE" == "1" ]]; then
      clone_expected_repository
    else
      success_echo "已找到同级官方仓库，将直接复用：${SIBLING_TARGET}"
    fi
    REPO_ROOT="$SIBLING_TARGET"
  fi

  cd "$REPO_ROOT" || die "无法进入 magic-resume 仓库：${REPO_ROOT}"
  success_echo "已切换到 magic-resume 仓库：${REPO_ROOT}"
}
# 检查 macOS、Git、curl、lsof、nohup 和浏览器打开命令。
check_base_environment() {
  [[ "$(uname -s)" == "Darwin" ]] || die "该脚本仅支持 macOS。"
  local command_name=""
  for command_name in git curl lsof nohup open; do
    command -v "$command_name" >/dev/null 2>&1 || die "缺少必要命令：${command_name}"
  done
  success_echo "macOS 基础命令检查通过。"
}
# 按 Apple Silicon、Intel 和当前 PATH 顺序寻找 Homebrew。
find_brew() {
  local brew_path="$(command -v brew 2>/dev/null || true)"
  if [[ -n "$brew_path" && -x "$brew_path" ]]; then
    print -r -- "$brew_path"
    return 0
  fi
  for brew_path in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [[ -x "$brew_path" ]] || continue
    print -r -- "$brew_path"
    return 0
  done
  return 1
}
# 激活已安装 Homebrew 的真实 shellenv 和可执行路径。
activate_brew() {
  local shellenv_cmd=""
  [[ -n "$BREW_BIN" && -x "$BREW_BIN" ]] || return 1
  shellenv_cmd="$($BREW_BIN shellenv 2>/dev/null || true)"
  [[ -z "$shellenv_cmd" ]] || eval "$shellenv_cmd"
  export PATH="$(dirname "$BREW_BIN"):$PATH"
  hash -r 2>/dev/null || true
}
# 确认 Node.js 与 npm 可用；缺失时仅通过已有 Homebrew 安装。
ensure_node_runtime() {
  NODE_BIN="$(command -v node 2>/dev/null || true)"
  NPM_BIN="$(command -v npm 2>/dev/null || true)"
  if [[ -n "$NODE_BIN" && -n "$NPM_BIN" ]]; then
    success_echo "已检测到 Node.js：$($NODE_BIN --version)"
    return 0
  fi

  BREW_BIN="$(find_brew 2>/dev/null || true)"
  [[ -n "$BREW_BIN" ]] || die "未检测到 Node.js，且系统没有 Homebrew；请先安装 Node.js 后重试。"
  activate_brew || die "Homebrew 环境激活失败。"
  run_cmd "通过 Homebrew 安装 Node.js" "$BREW_BIN" install node || die "Node.js 安装失败。"
  NODE_BIN="$(command -v node 2>/dev/null || true)"
  NPM_BIN="$(command -v npm 2>/dev/null || true)"
  [[ -n "$NODE_BIN" && -n "$NPM_BIN" ]] || die "Node.js 安装后仍无法找到 node / npm。"
}
# 把 npm 全局可执行目录补入当前 PATH。
refresh_npm_global_path() {
  local npm_prefix="$($NPM_BIN prefix -g 2>/dev/null || true)"
  if [[ -n "$npm_prefix" && -d "${npm_prefix}/bin" ]]; then
    export PATH="${npm_prefix}/bin:$PATH"
  fi
  hash -r 2>/dev/null || true
}
# 读取项目声明并保证 pnpm 可用，避免 Sourcetree 的精简 PATH 找不到命令。
ensure_pnpm_runtime() {
  PACKAGE_MANAGER_SPEC="$($NODE_BIN -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.stdout.write(p.packageManager||"")' "$REPO_ROOT/package.json" 2>/dev/null || true)"
  [[ "$PACKAGE_MANAGER_SPEC" == pnpm@* ]] || PACKAGE_MANAGER_SPEC="pnpm@latest"
  PNPM_BIN="$(command -v pnpm 2>/dev/null || true)"

  if [[ -z "$PNPM_BIN" ]]; then
    run_cmd "安装项目声明的 pnpm：${PACKAGE_MANAGER_SPEC}" "$NPM_BIN" install --global "$PACKAGE_MANAGER_SPEC" || die "pnpm 安装失败，请检查 npm 全局目录权限。"
    refresh_npm_global_path
    PNPM_BIN="$(command -v pnpm 2>/dev/null || true)"
  fi

  [[ -n "$PNPM_BIN" && -x "$PNPM_BIN" ]] || die "未找到可执行的 pnpm。"
  success_echo "已检测到 pnpm：$($PNPM_BIN --version)"
}
# 核对仓库 remote 和快速开始所需的关键项目文件。
validate_magic_resume_project() {
  repository_matches_expected "$REPO_ROOT" || die "目标目录 remote 已变化，不再是 ${EXPECTED_HTTPS_URL}。"
  [[ -f "$REPO_ROOT/package.json" ]] || die "仓库缺少 package.json：${REPO_ROOT}"
  [[ -f "$REPO_ROOT/pnpm-lock.yaml" ]] || die "仓库缺少 pnpm-lock.yaml：${REPO_ROOT}"
  grep -Fq '"dev"' "$REPO_ROOT/package.json" || die "package.json 缺少 dev 脚本。"
  success_echo "magic-resume 项目结构检查通过。"
}
# 按官方 README 执行 pnpm install；Dry-run 只展示命令。
install_project_dependencies() {
  if [[ "${JOBS_MAGIC_RESUME_DRY_RUN:-0}" == "1" ]]; then
    success_echo "Dry-run：计划在 ${REPO_ROOT} 执行 pnpm install。"
    return 0
  fi
  run_cmd "安装 magic-resume 项目依赖" "$PNPM_BIN" install || die "pnpm install 执行失败。"
}
# 返回当前监听 3000 端口的进程 ID。
port_listener_pids() {
  lsof -nP -tiTCP:"$LOCAL_PORT" -sTCP:LISTEN 2>/dev/null || true
}
# 检查监听进程的工作目录是否属于当前 magic-resume 仓库。
listener_belongs_to_repository() {
  local pids_output="$(port_listener_pids)"
  local listener_pid=""
  local listener_cwd=""

  for listener_pid in ${(f)pids_output}; do
    listener_cwd="$(lsof -a -p "$listener_pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)"
    [[ -n "$listener_cwd" ]] || continue
    listener_cwd="$(cd "$listener_cwd" 2>/dev/null && pwd -P || true)"
    if [[ "$listener_cwd" == "$REPO_ROOT" ]]; then
      print -r -- "$listener_pid"
      return 0
    fi
  done
  return 1
}
# 检查监听进程命令是否明确属于 Vite 开发服务器。
process_is_vite_dev_server() {
  local process_command="$(ps -p "$1" -o command= 2>/dev/null || true)"
  [[ "$process_command" == *vite* && "$process_command" == *dev* ]]
}
# 读取脚本上次记录的实际监听进程 PID，并过滤过期或非法内容。
read_managed_server_pid() {
  local managed_pid=""
  [[ -f "$DEV_SERVER_PID_FILE" ]] || return 1
  managed_pid="$(sed -n '1p' "$DEV_SERVER_PID_FILE" 2>/dev/null | tr -d '[:space:]')"
  [[ "$managed_pid" == <-> ]] || return 1
  print -r -- "$managed_pid"
}
# 检查本地首页是否已经返回可接受的 HTTP 响应。
server_is_ready() {
  curl --silent --show-error --fail --max-time 2 --output /dev/null "$LOCAL_URL" 2>/dev/null
}
# 在限定时间内等待后台开发服务器就绪。
wait_for_development_server() {
  local max_seconds="${1:-60}"
  local elapsed=0

  while [[ "$elapsed" -lt "$max_seconds" ]]; do
    server_is_ready && return 0
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}
# 停止当前仓库未由本脚本托管的前台 Vite 服务，为后台重启释放端口。
stop_unmanaged_vite_server() {
  local listener_pid="$1"
  local elapsed=0

  process_is_vite_dev_server "$listener_pid" || die "3000 端口进程属于当前仓库，但不是可确认的 Vite dev；脚本不会结束该进程。"
  warn_echo "检测到当前仓库的前台/未托管 Vite 服务：PID ${listener_pid}"
  warn_echo "将发送 TERM 并重新后台启动，保证关闭终端后服务仍可用。"
  kill "$listener_pid" 2>/dev/null || die "无法停止现有 Vite 服务：PID ${listener_pid}"

  while [[ "$elapsed" -lt 10 ]]; do
    [[ -z "$(port_listener_pids)" ]] && return 0
    sleep 1
    elapsed=$((elapsed + 1))
  done
  die "现有 Vite 服务在 10 秒内没有释放 3000 端口；脚本不会强制结束进程。"
}
# 判断 3000 端口能否启动；只复用本脚本记录的后台服务。
reuse_existing_server_if_possible() {
  local pids_output="$(port_listener_pids)"
  local owned_pid=""
  local managed_pid=""

  [[ -n "$pids_output" ]] || return 1
  owned_pid="$(listener_belongs_to_repository 2>/dev/null || true)"
  if [[ -n "$owned_pid" ]]; then
    managed_pid="$(read_managed_server_pid 2>/dev/null || true)"
    if [[ "$managed_pid" == "$owned_pid" ]]; then
      info_echo "检测到本脚本托管的后台服务，正在确认可访问性：PID ${owned_pid}"
      wait_for_development_server 15 || die "已托管服务在 15 秒内未就绪。"
      SERVER_REUSED=1
      success_echo "已复用本脚本托管的 3000 端口服务。"
      return 0
    fi
    stop_unmanaged_vite_server "$owned_pid"
    return 1
  fi

  die "3000 端口已被其它目录的进程占用；为避免打开错误页面，脚本已停止。"
}
# 用 nohup、关闭标准输入和 zsh 作业脱离在后台启动 pnpm dev。
launch_development_server_in_background() {
  local dev_pid=""
  : > "$DEV_SERVER_LOG"

  cd "$REPO_ROOT" || die "无法进入项目目录启动服务：${REPO_ROOT}"
  NO_COLOR=1 FORCE_COLOR=0 CLICOLOR=0 ANSI_COLORS_DISABLED=1 npm_config_color=false \
    nohup "$PNPM_BIN" dev </dev/null >"$DEV_SERVER_LOG" 2>&1 &!
  dev_pid="$!"
  [[ -n "$dev_pid" ]] || die "后台服务启动后未获得进程 ID。"
  print -r -- "$dev_pid" > "$DEV_SERVER_PID_FILE"
  success_echo "已在后台启动 pnpm dev：PID ${dev_pid}"
  gray_echo "关闭当前终端或 Sourcetree 输出窗口不会停止该服务。"
  gray_echo "PID 文件：${DEV_SERVER_PID_FILE}"
  gray_echo "服务日志：${DEV_SERVER_LOG}"
}
# 用真正监听 3000 端口的子进程 PID 更新停止服务所需的 PID 文件。
record_server_listener_pid() {
  local listener_pid="$(listener_belongs_to_repository 2>/dev/null || true)"
  [[ -n "$listener_pid" ]] || return 1
  print -r -- "$listener_pid" > "$DEV_SERVER_PID_FILE"
  success_echo "已记录 3000 端口监听进程：PID ${listener_pid}"
}
# 启动或复用开发服务器；Dry-run 不创建进程。
start_or_reuse_development_server() {
  if [[ "${JOBS_MAGIC_RESUME_DRY_RUN:-0}" == "1" ]]; then
    success_echo "Dry-run：计划后台执行 pnpm dev，并等待 ${LOCAL_URL}。"
    return 0
  fi
  reuse_existing_server_if_possible && return 0
  launch_development_server_in_background
  wait_for_development_server 60 || die "开发服务器在 60 秒内未就绪，请查看服务日志：${DEV_SERVER_LOG}"
  record_server_listener_pid || warn_echo "服务已经就绪，但未能刷新监听进程 PID；停止服务前请用 lsof 核对。"
  success_echo "开发服务器已经就绪：${LOCAL_URL}"
}
# 使用系统默认浏览器打开 localhost；Dry-run 只展示地址。
open_magic_resume_in_browser() {
  if [[ "${JOBS_MAGIC_RESUME_DRY_RUN:-0}" == "1" ]]; then
    success_echo "Dry-run：计划使用默认浏览器打开 ${LOCAL_URL}。"
    return 0
  fi
  open "$LOCAL_URL" || die "无法使用默认浏览器打开 ${LOCAL_URL}。"
  success_echo "已使用默认浏览器打开：${LOCAL_URL}"
}
# 汇总仓库、后台进程和日志位置。
finish_script() {
  highlight_echo "============================== 执行完成 =============================="
  success_echo "magic-resume 仓库：${REPO_ROOT}"
  success_echo "访问地址：${LOCAL_URL}"
  [[ "$SERVER_REUSED" == "1" ]] && gray_echo "服务状态：复用当前仓库已有进程。"
  gray_echo "业务日志：${LOG_FILE}"
  gray_echo "服务日志：${DEV_SERVER_LOG}"
  highlight_echo "======================================================================"
}
# 编排脚本自述、仓库选择、环境配置、依赖安装和后台启动流程。
main() {
  show_script_intro_and_wait # 首先展示内置自述，并按 Sourcetree / 终端入口决定是否等待确认。
  initialize_script_runtime # 确认后初始化 Shell、PATH 和日志，保证后续输出可追踪。
  check_base_environment # 检查 macOS 与 Git、网络、端口、后台运行所需的系统命令。
  resolve_input_repository "$@" # 从 REPO 参数、命令行参数或当前目录识别运行仓库。
  select_magic_resume_repository # 校验当前 remote；不匹配时先扫描全部同级仓库，确实不存在才创建并克隆。
  validate_magic_resume_project # 核对 remote、package.json、锁文件和 dev 入口。
  ensure_node_runtime # 检查 Node.js 与 npm，缺失时通过已有 Homebrew 补齐。
  ensure_pnpm_runtime # 检查 pnpm，缺失时按项目声明的版本安装。
  install_project_dependencies # 按官方 README 执行 pnpm install。
  start_or_reuse_development_server # 复用已托管服务，或把当前仓库前台 Vite 转为 nohup 后台服务。
  open_magic_resume_in_browser # 服务就绪后使用系统默认浏览器打开 localhost:3000。
  finish_script # 输出最终仓库、访问地址、PID 和日志位置。
}

main "$@"
