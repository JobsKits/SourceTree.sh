#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】同步edgetunnel代码后手动升级.command
# - 核心用途：执行“同步edgetunnel代码后手动升级”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；Sourcetree 模式无交互连续执行，终端模式确认后继续。

# ============================== 基础路径 ==============================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
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
# 封装 strip_ansi_text 对应的独立处理逻辑。
strip_ansi_text() {
  perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}

EXPECTED_OWNER="cmliu"
EXPECTED_REPO="edgetunnel"
EXPECTED_SLUG="${EXPECTED_OWNER}/${EXPECTED_REPO}"
EXPECTED_HTTPS_URL="https://github.com/${EXPECTED_SLUG}"

BREW_BIN=""
REPO_ROOT=""
REPO_INPUT_SOURCE=""
MATCHED_REMOTE=""
WRANGLER_BIN=""
WRANGLER_LABEL=""
WRANGLER_CONFIG_FOR_DEPLOY=""
PLAIN_OUTPUT=0
# ============================== 输出模式 / 彩色日志 ==============================
configure_output_mode() {
  # SourceTree 自定义操作窗口不完整支持 ANSI 颜色，非 TTY 输出统一降级为纯文本。
  if [[ "${JOBS_PLAIN_OUTPUT:-0}" == "1" || -n "${NO_COLOR:-}" ]]; then
    PLAIN_OUTPUT=1
  elif [[ -t 1 ]]; then
    PLAIN_OUTPUT=0
  else
    PLAIN_OUTPUT=1
  fi

  if [[ "$PLAIN_OUTPUT" == "1" ]]; then
    export NO_COLOR=1
    export FORCE_COLOR=0
    export npm_config_color=false
  fi
}
# 封装 strip_ansi_stream 对应的独立处理逻辑。
strip_ansi_stream() {
  if [[ "$PLAIN_OUTPUT" == "1" ]]; then
    if command -v perl >/dev/null 2>&1; then
      perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e\][^\a]*(?:\a|\e\\)//g; s/\e[()][A-Za-z0-9]//g'
    else
      cat
    fi
  else
    cat
  fi
}
# 按当前输出级别记录终端信息，并同步写入脚本日志。
log()            { echo -e "$1" | strip_ansi_stream | tee -a "$LOG_FILE"; }
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
# 封装 die 对应的独立处理逻辑。
die() {
  error_echo "$1"
  err_echo "日志文件：$LOG_FILE"
  exit 1
}
# ============================== 通用执行 ==============================
run_cmd() {
  local title="$1"
  shift
  info_echo "$title"
  gray_echo "命令：$*"
  "$@" 2>&1 | strip_ansi_stream | tee -a "$LOG_FILE"
  local code=${pipestatus[1]}
  if [[ $code -ne 0 ]]; then
    error_echo "命令执行失败：$title"
    return $code
  fi
  return 0
}
# 执行已经拆分完成的独立业务步骤。
run_interactive_cmd() {
  local title="$1"
  shift
  info_echo "$title"
  gray_echo "命令：$*"
  "$@"
  local code=$?
  if [[ $code -ne 0 ]]; then
    error_echo "命令执行失败：$title"
    return $code
  fi
  success_echo "完成：$title"
  return 0
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
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
  note_echo "核心行为：同步 edgetunnel 后自动确认 Cloudflare KV 绑定，并执行 Worker 部署。"
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
# 封装 strip_outer_quotes 对应的独立处理逻辑。
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
# 收集并校验用户输入，决定后续执行路径。
ask_any_to_run() {
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" ]]; then
    gray_echo "Sourcetree 连续执行模式已跳过当前可选交互。"
    return 1
  fi
  local message="$1"
  local answer=""

  if [[ ! -t 0 ]]; then
    warn_echo "当前不是可交互终端，已跳过需手动确认的操作：$message"
    return 1
  fi

  read -r "?${message}（直接回车跳过；输入任意字符后回车执行）：" answer
  [[ -n "$answer" ]]
}
# 封装 normalize_user_input_path 对应的独立处理逻辑。
normalize_user_input_path() {
  local value="$1"
  value="$(strip_outer_quotes "$value")"
  if [[ "$value" == "~" ]]; then
    value="$HOME"
  elif [[ "$value" == "~/"* ]]; then
    value="${HOME}/${value#~/}"
  fi
  # 拖拽到终端的路径可能带有反斜杠转义；zsh 的 Q 标志负责还原。
  value="${(Q)value}"
  print -r -- "$value"
}
# ============================== Homebrew / MacOS ==============================
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}
# 解析并返回后续流程需要的目标信息。
find_brew() {
  local brew_path=""
  brew_path="$(command -v brew 2>/dev/null || true)"
  if [[ -n "$brew_path" && -x "$brew_path" ]]; then
    print -r -- "$brew_path"
    return 0
  fi

  for brew_path in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$brew_path" ]]; then
      print -r -- "$brew_path"
      return 0
    fi
  done

  return 1
}
# 封装 activate_brew 对应的独立处理逻辑。
activate_brew() {
  [[ -n "$BREW_BIN" && -x "$BREW_BIN" ]] || return 1
  local shellenv_cmd=""
  shellenv_cmd="$($BREW_BIN shellenv 2>/dev/null || true)"
  if [[ -n "$shellenv_cmd" ]]; then
    eval "$shellenv_cmd"
  fi
  export PATH="$(dirname "$BREW_BIN"):$PATH"
  hash -r 2>/dev/null || true
}
# 检查当前运行条件是否满足后续流程要求。
ensure_brew() {
  BREW_BIN="$(find_brew 2>/dev/null || true)"

  if [[ -z "$BREW_BIN" ]]; then
    warn_echo "未检测到 Homebrew，开始安装最新版 Homebrew。"
    run_cmd "安装 Homebrew" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || die "Homebrew 安装失败。"
    BREW_BIN="$(find_brew 2>/dev/null || true)"
    [[ -n "$BREW_BIN" ]] || die "Homebrew 安装后仍未找到 brew，请重新打开终端后再试。"
  else
    success_echo "已检测到 Homebrew：$BREW_BIN"
  fi

  activate_brew || die "Homebrew 环境激活失败。"

  if ask_any_to_run "是否刷新 Homebrew 索引：brew update"; then
    run_cmd "刷新 Homebrew 索引" "$BREW_BIN" update || die "Homebrew update 失败。"
  else
    warn_echo "已跳过 Homebrew 索引刷新。"
    gray_echo "说明：这是耗时操作，按要求默认不自动执行；如后续安装/升级失败，可重新运行并选择执行。"
  fi
}
# ============================== Git 仓库定位与校验 ==============================
ensure_git() {
  if command -v git >/dev/null 2>&1; then
    success_echo "已检测到 Git：$(command -v git)"
    return 0
  fi

  warn_echo "未检测到 Git，开始通过 Homebrew 安装 Git。"
  ensure_brew
  run_cmd "安装 Git" "$BREW_BIN" install git || die "Git 安装失败。"
  hash -r 2>/dev/null || true
  command -v git >/dev/null 2>&1 || die "Git 安装后仍不可用。"
}
# 封装 normalize_github_remote 对应的独立处理逻辑。
normalize_github_remote() {
  local url="$1"
  local slug=""

  url="${url//$'\r'/}"
  url="${url//$'\n'/}"
  url="${url%/}"
  url="${url%.git}"
  url="${url%/}"

  case "$url" in
    https://github.com/*)
      slug="${url#https://github.com/}"
      ;;
    http://github.com/*)
      slug="${url#http://github.com/}"
      ;;
    git@github.com:*)
      slug="${url#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      slug="${url#ssh://git@github.com/}"
      ;;
    git://github.com/*)
      slug="${url#git://github.com/}"
      ;;
    github.com:*)
      slug="${url#github.com:}"
      ;;
    github.com/*)
      slug="${url#github.com/}"
      ;;
    *)
      slug=""
      ;;
  esac

  slug="${slug%.git}"
  slug="${slug%/}"
  slug="${(L)slug}"
  print -r -- "$slug"
}
# 解析并返回后续流程需要的目标信息。
resolve_repo_root_from_candidate() {
  local candidate="$1"
  candidate="$(normalize_user_input_path "$candidate")"
  [[ -n "$candidate" ]] || return 1
  [[ -e "$candidate" ]] || return 2

  if [[ -f "$candidate" ]]; then
    candidate="${candidate:h}"
  fi

  local candidate_abs=""
  candidate_abs="$(cd "$candidate" 2>/dev/null && pwd -P || true)"
  [[ -n "$candidate_abs" && -d "$candidate_abs" ]] || return 3

  git -C "$candidate_abs" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 4
  git -C "$candidate_abs" rev-parse --show-toplevel 2>/dev/null || return 5
}
# 收集并校验用户输入，决定后续执行路径。
prompt_repo_path() {
  local input=""
  local resolved=""

  while true; do
    echo ""
    highlight_echo "请拖入或输入 ${EXPECTED_REPO} 仓库文件夹路径"
    gray_echo "正确示例：/Users/jobs/Documents/Github/${EXPECTED_REPO}"
    gray_echo "要求：该目录必须是 ${EXPECTED_HTTPS_URL} 对应的 Git 工作区。"
    read -r "?👉 仓库文件夹路径（Ctrl+C 取消）：" input

    input="$(normalize_user_input_path "$input")"
    if [[ -z "$input" ]]; then
      warn_echo "未输入路径，请重新拖入或输入仓库文件夹。"
      continue
    fi

    resolved="$(resolve_repo_root_from_candidate "$input" 2>/dev/null || true)"
    if [[ -n "$resolved" ]]; then
      REPO_INPUT_SOURCE="手动输入/拖拽路径"
      REPO_ROOT="$resolved"
      return 0
    fi

    warn_echo "无法从该路径识别 Git 仓库根目录：$input"
    gray_echo "请确认拖入的是 edgetunnel 仓库文件夹，不是脚本文件夹，也不是 SourceTree.command 部署目录。"
  done
}
# 解析并返回后续流程需要的目标信息。
resolve_target_repo_root() {
  local candidate=""
  local resolved=""

  if [[ $# -gt 0 ]]; then
    candidate="$*"
    resolved="$(resolve_repo_root_from_candidate "$candidate" 2>/dev/null || true)"
    if [[ -n "$resolved" ]]; then
      REPO_INPUT_SOURCE="SourceTree 参数 / 命令行参数"
      REPO_ROOT="$resolved"
      success_echo "已从参数识别仓库根目录：$REPO_ROOT"
      return 0
    fi

    die "传入参数无法识别为 Git 仓库：${candidate}。SourceTree 自定义操作参数必须填写 \$REPO。"
  fi

  if [[ -t 0 ]]; then
    prompt_repo_path
    success_echo "已从手动输入识别仓库根目录：$REPO_ROOT"
    return 0
  fi

  die "未收到仓库路径参数，且当前不是可交互终端。SourceTree 中请把参数设置为 \$REPO；独立运行请双击脚本后拖入仓库文件夹。"
}
# 检查当前运行条件是否满足后续流程要求。
validate_target_repo() {
  [[ -n "$REPO_ROOT" && -d "$REPO_ROOT" ]] || die "仓库根目录无效：${REPO_ROOT:-空}"

  local remotes_output=""
  remotes_output="$(git -C "$REPO_ROOT" remote 2>/dev/null || true)"
  [[ -n "$remotes_output" ]] || die "当前 Git 仓库没有配置 remote，无法确认是否为 ${EXPECTED_HTTPS_URL}。"

  local remote=""
  local url=""
  local normalized=""
  local matched=""

  for remote in ${(f)remotes_output}; do
    url="$(git -C "$REPO_ROOT" remote get-url "$remote" 2>/dev/null || true)"
    [[ -n "$url" ]] || continue
    normalized="$(normalize_github_remote "$url")"
    gray_echo "remote.${remote}.url = ${url} -> ${normalized:-无法识别}"
    if [[ "$normalized" == "${EXPECTED_SLUG}" ]]; then
      matched="${remote}:${url}"
      break
    fi
  done

  [[ -n "$matched" ]] || die "仓库 remote 不合法：必须指向 ${EXPECTED_HTTPS_URL}，HTTPS 和 SSH 写法均支持。"

  MATCHED_REMOTE="$matched"
  cd "$REPO_ROOT" || die "无法进入仓库根目录：$REPO_ROOT"
  success_echo "仓库校验通过：$MATCHED_REMOTE"
  success_echo "仓库来源：$REPO_INPUT_SOURCE"
  success_echo "已切换到仓库根目录：$REPO_ROOT"
}
# ============================== Node / npm / npx / Wrangler 支撑链 ==============================
ensure_node_by_brew() {
  ensure_brew

  if "$BREW_BIN" list --formula node >/dev/null 2>&1; then
    if ask_any_to_run "是否升级 Node.js（npm / npx 上游）：brew upgrade node"; then
      run_cmd "升级 Node.js（npm / npx 上游）" "$BREW_BIN" upgrade node || die "Node.js 升级失败。"
    else
      warn_echo "已跳过 Node.js 升级，继续使用当前已安装版本。"
    fi
  else
    if command -v node >/dev/null 2>&1; then
      warn_echo "检测到已有 node：$(command -v node)"
      warn_echo "但 Homebrew 未记录 node formula；为保证 npx 支撑链可控，将通过 Homebrew 安装最新版 node。"
    fi
    run_cmd "安装最新版 Node.js（包含 npm / npx）" "$BREW_BIN" install node || die "Node.js 安装失败。"
  fi

  activate_brew || true
  hash -r 2>/dev/null || true

  command -v node >/dev/null 2>&1 || die "Node.js 安装/升级后仍不可用。"
  command -v npm >/dev/null 2>&1 || die "npm 安装/升级后仍不可用。"
}
# 封装 refresh_npm_global_bin 对应的独立处理逻辑。
refresh_npm_global_bin() {
  command -v npm >/dev/null 2>&1 || return 0
  local npm_prefix=""
  npm_prefix="$(npm prefix -g 2>/dev/null || true)"
  if [[ -n "$npm_prefix" && -d "${npm_prefix}/bin" ]]; then
    export PATH="${npm_prefix}/bin:$PATH"
  fi
  hash -r 2>/dev/null || true
}
# 检查当前运行条件是否满足后续流程要求。
ensure_npm_npx_latest() {
  ensure_node_by_brew

  if ask_any_to_run "是否升级 npm 到最新版（npx 随 npm 一起提供）：npm install -g npm@latest"; then
    run_cmd "升级 npm 到最新版（npx 随 npm 一起提供）" npm install -g npm@latest || die "npm 升级失败。"
    refresh_npm_global_bin
  else
    warn_echo "已跳过 npm 升级，继续使用当前 npm / npx。"
  fi

  if ! command -v npx >/dev/null 2>&1; then
    warn_echo "当前缺少 npx，必须补齐后才能继续执行 wrangler。"
    run_cmd "补齐 npx 支撑链" npm install -g npm@latest || die "npx 补齐失败。"
    refresh_npm_global_bin
  fi

  command -v npx >/dev/null 2>&1 || die "npx 仍不可用。请检查 npm 全局 bin 是否在 PATH 内。"
}
# 封装 project_has_local_wrangler 对应的独立处理逻辑。
project_has_local_wrangler() {
  [[ -f "package.json" ]] || return 1

  local dev_dep=""
  local dep=""
  local opt_dep=""
  dev_dep="$(npm pkg get devDependencies.wrangler 2>/dev/null || true)"
  dep="$(npm pkg get dependencies.wrangler 2>/dev/null || true)"
  opt_dep="$(npm pkg get optionalDependencies.wrangler 2>/dev/null || true)"

  [[ "$dev_dep" != "{}" && "$dev_dep" != "null" && "$dev_dep" != "undefined" && -n "$dev_dep" ]] && return 0
  [[ "$dep" != "{}" && "$dep" != "null" && "$dep" != "undefined" && -n "$dep" ]] && return 0
  [[ "$opt_dep" != "{}" && "$opt_dep" != "null" && "$opt_dep" != "undefined" && -n "$opt_dep" ]] && return 0
  return 1
}
# 执行对应的清理操作，并保留必要的安全检查。
clear_quarantine_path() {
  local target="$1"
  [[ -e "$target" ]] || return 0
  xattr -dr com.apple.quarantine "$target" 2>/dev/null || true
}
# 执行对应的清理操作，并保留必要的安全检查。
clear_wrangler_quarantine() {
  local npm_root=""
  npm_root="$(npm root -g 2>/dev/null || true)"

  if [[ -n "$npm_root" ]]; then
    clear_quarantine_path "${npm_root}/wrangler"
    clear_quarantine_path "${npm_root}/esbuild"
    clear_quarantine_path "${npm_root}/@esbuild"
  fi

  clear_quarantine_path "${REPO_ROOT}/node_modules/wrangler"
  clear_quarantine_path "${REPO_ROOT}/node_modules/esbuild"
  clear_quarantine_path "${REPO_ROOT}/node_modules/@esbuild"
}
# 解析并返回后续流程需要的目标信息。
resolve_existing_wrangler() {
  WRANGLER_BIN=""
  WRANGLER_LABEL=""

  local local_bin="${REPO_ROOT}/node_modules/.bin/wrangler"
  if [[ -x "$local_bin" ]]; then
    WRANGLER_BIN="$local_bin"
    WRANGLER_LABEL="$local_bin"
    return 0
  fi

  local global_bin=""
  global_bin="$(command -v wrangler 2>/dev/null || true)"
  if [[ -n "$global_bin" && -x "$global_bin" ]]; then
    WRANGLER_BIN="$global_bin"
    WRANGLER_LABEL="$global_bin"
    return 0
  fi

  return 1
}
# 执行已经拆分完成的独立业务步骤。
run_wrangler_cmd() {
  local title="$1"
  shift

  if [[ -n "$WRANGLER_BIN" ]]; then
    run_cmd "$title" "$WRANGLER_BIN" "$@"
  else
    run_cmd "$title" npx wrangler "$@"
  fi
}
# 执行已经拆分完成的独立业务步骤。
run_interactive_wrangler_cmd() {
  local title="$1"
  shift

  if [[ -n "$WRANGLER_BIN" ]]; then
    run_interactive_cmd "$title" "$WRANGLER_BIN" "$@"
  else
    run_interactive_cmd "$title" npx wrangler "$@"
  fi
}
# 检查当前运行条件是否满足后续流程要求。
ensure_wrangler_latest() {
  ensure_npm_npx_latest
  export npm_config_yes="true"

  if project_has_local_wrangler; then
    if ask_any_to_run "是否升级本仓库 wrangler 到最新版：npm install --save-dev wrangler@latest"; then
      run_cmd "项目已声明 wrangler，升级本仓库 wrangler@latest" npm install --save-dev wrangler@latest || die "项目 wrangler 升级失败。"
    else
      warn_echo "已跳过本仓库 wrangler 升级，继续使用当前项目依赖。"
    fi
  else
    if resolve_existing_wrangler; then
      if ask_any_to_run "是否安装/升级全局 wrangler 到最新版：npm install -g wrangler@latest"; then
        run_cmd "项目未声明 wrangler，安装/升级全局 wrangler@latest 作为后备" npm install -g wrangler@latest || die "全局 wrangler 安装/升级失败。"
        refresh_npm_global_bin
      else
        warn_echo "已跳过全局 wrangler 升级，继续使用当前已安装版本。"
      fi
    else
      warn_echo "未检测到已安装的 wrangler，开始安装全局 wrangler@latest。"
      run_cmd "安装全局 wrangler@latest" npm install -g wrangler@latest || die "全局 wrangler 安装失败。"
      refresh_npm_global_bin
    fi
  fi

  clear_wrangler_quarantine
  resolve_existing_wrangler || true
  run_wrangler_cmd "确认 Wrangler 版本" --version || die "Wrangler 版本确认失败。"
}
# 检查当前运行条件是否满足后续流程要求。
check_toolchain_ready_for_sourcetree() {
  BREW_BIN="$(find_brew 2>/dev/null || true)"
  if [[ -n "$BREW_BIN" ]]; then
    success_echo "已检测到 Homebrew：$BREW_BIN"
    activate_brew || true
  else
    warn_echo "SourceTree 模式未检测到 Homebrew；本次不会安装 Homebrew。"
  fi

  refresh_npm_global_bin

  command -v node >/dev/null 2>&1 || die "SourceTree 模式缺少 Node.js。请先双击/终端运行本脚本完成工具链安装。"
  command -v npm >/dev/null 2>&1 || die "SourceTree 模式缺少 npm。请先双击/终端运行本脚本完成工具链安装。"
  command -v npx >/dev/null 2>&1 || die "SourceTree 模式缺少 npx。请先双击/终端运行本脚本完成工具链安装。"

  clear_wrangler_quarantine
  resolve_existing_wrangler || die "SourceTree 模式未找到已安装的 wrangler。请先双击/终端运行本脚本完成 wrangler 安装/升级。"

  success_echo "SourceTree 模式只检查工具链，不执行 brew/npm 安装或升级。"
  run_wrangler_cmd "确认 Wrangler 版本（SourceTree 只检查，不安装/升级）" --version || die "Wrangler 版本确认失败。"
}
# 封装 prepare_toolchain_for_current_context 对应的独立处理逻辑。
prepare_toolchain_for_current_context() {
  if is_interactive_terminal; then
    ensure_wrangler_latest
  else
    check_toolchain_ready_for_sourcetree
  fi
}
# 封装 print_toolchain_versions 对应的独立处理逻辑。
print_toolchain_versions() {
  highlight_echo "============================== 工具链版本 =============================="
  if [[ -n "$BREW_BIN" && -x "$BREW_BIN" ]]; then
    gray_echo "brew: $($BREW_BIN --version 2>/dev/null | head -n 1 || echo '不可用')"
  else
    gray_echo "brew: 未检测到或未参与本次执行"
  fi
  gray_echo "node: $(node -v 2>/dev/null || echo '不可用') ($(command -v node 2>/dev/null || echo '未找到'))"
  gray_echo "npm : $(npm -v 2>/dev/null || echo '不可用') ($(command -v npm 2>/dev/null || echo '未找到'))"
  gray_echo "npx : $(npx --version 2>/dev/null || echo '不可用') ($(command -v npx 2>/dev/null || echo '未找到'))"
  if [[ -n "$WRANGLER_LABEL" ]]; then
    gray_echo "wrangler: $WRANGLER_LABEL"
  else
    gray_echo "wrangler: npx wrangler"
  fi
  highlight_echo "======================================================================="
}
# ============================== Cloudflare / Wrangler 授权与部署 ==============================
is_interactive_terminal() {
  [[ -t 0 && -t 1 ]]
}
# 封装 print_sourcetree_auth_hint 对应的独立处理逻辑。
print_sourcetree_auth_hint() {
  warn_echo "SourceTree 自定义操作不是稳定的浏览器 OAuth 交互环境，本脚本不会在 SourceTree 内强行执行 wrangler login。"
  gray_echo "原因：wrangler login 会启动本机 localhost OAuth 回调；SourceTree 的脚本窗口容易造成回调状态不一致、输出延迟或登录失败。"
  echo "" | tee -a "$LOG_FILE"
  note_echo "正确流程："
  gray_echo "1. 先双击本脚本，或在终端独立运行本脚本，完成一次 Cloudflare 登录。"
  gray_echo "2. 登录成功后，再回到 SourceTree 点自定义菜单；SourceTree 模式只检查登录状态并执行 deploy。"
  echo "" | tee -a "$LOG_FILE"
  gray_echo "可直接在终端执行："
  gray_echo "${SCRIPT_PATH} ${REPO_ROOT}"
}
# 封装 wrangler_whoami_ok 对应的独立处理逻辑。
wrangler_whoami_ok() {
  local auth_log="/tmp/${SCRIPT_BASENAME}.wrangler-whoami.log"
  : > "$auth_log"

  info_echo "检查 Cloudflare 登录状态"
  if [[ -n "$WRANGLER_BIN" ]]; then
    gray_echo "命令：$WRANGLER_BIN whoami --json"
    "$WRANGLER_BIN" whoami --json > "$auth_log" 2>&1
  else
    gray_echo "命令：npx wrangler whoami --json"
    npx wrangler whoami --json > "$auth_log" 2>&1
  fi

  if [[ $? -eq 0 ]]; then
    cat "$auth_log" | strip_ansi_stream >> "$LOG_FILE"
    success_echo "已检测到 Cloudflare 登录状态：wrangler whoami 通过。"
    return 0
  fi

  cat "$auth_log" | strip_ansi_stream >> "$LOG_FILE"
  warn_echo "未检测到有效的 Cloudflare 登录状态：wrangler whoami 未通过。"
  gray_echo "whoami 详细输出已写入：$LOG_FILE"
  return 1
}
# 检查当前运行条件是否满足后续流程要求。
ensure_wrangler_auth() {
  export npm_config_yes="true"

  highlight_echo "============================== Wrangler Auth =============================="

  if [[ "${FORCE_WRANGLER_LOGIN:-0}" == "1" ]]; then
    if is_interactive_terminal; then
      warn_echo "已启用 FORCE_WRANGLER_LOGIN=1，将在交互终端中强制重新登录。"
      run_interactive_wrangler_cmd "执行 Cloudflare 登录" login || die "wrangler login 执行失败。"
      wrangler_whoami_ok || die "Cloudflare 登录后仍无法通过 wrangler whoami 校验。"
      return 0
    fi

    print_sourcetree_auth_hint
    die "当前不是可交互终端，不能执行 FORCE_WRANGLER_LOGIN=1。"
  fi

  if wrangler_whoami_ok; then
    return 0
  fi

  if is_interactive_terminal; then
    run_interactive_wrangler_cmd "执行 Cloudflare 登录" login || die "wrangler login 执行失败。"
    wrangler_whoami_ok || die "Cloudflare 登录后仍无法通过 wrangler whoami 校验。"
    return 0
  fi

  print_sourcetree_auth_hint
  die "SourceTree 非交互环境未检测到有效登录状态，请先在终端/双击模式完成 wrangler login。"
}
# 封装 capture_wrangler_cmd_to_file 对应的独立处理逻辑。
capture_wrangler_cmd_to_file() {
  local title="$1"
  local output_file="$2"
  shift 2

  info_echo "$title"
  if [[ -n "$WRANGLER_BIN" ]]; then
    gray_echo "命令：$WRANGLER_BIN $*"
    "$WRANGLER_BIN" "$@" > "$output_file" 2>&1
  else
    gray_echo "命令：npx wrangler $*"
    npx wrangler "$@" > "$output_file" 2>&1
  fi

  local code=$?
  if [[ -s "$output_file" ]]; then
    cat "$output_file" | strip_ansi_stream >> "$LOG_FILE"
  fi

  if [[ $code -ne 0 ]]; then
    error_echo "命令执行失败：$title"
    return $code
  fi

  return 0
}
# 解析并返回后续流程需要的目标信息。
resolve_edgetunnel_kv_namespace_title() {
  local title=""
  local config_file="${REPO_ROOT}/.edgetunnel-kv-namespace"

  if [[ -n "${EDGETUNNEL_KV_NAMESPACE_TITLE:-}" ]]; then
    title="$EDGETUNNEL_KV_NAMESPACE_TITLE"
  elif [[ -n "${EDGETUNNEL_KV_NAMESPACE:-}" ]]; then
    title="$EDGETUNNEL_KV_NAMESPACE"
  elif [[ -n "${JOBS_EDGETUNNEL_KV_NAMESPACE:-}" ]]; then
    title="$JOBS_EDGETUNNEL_KV_NAMESPACE"
  elif [[ -f "$config_file" ]]; then
    title="$(grep -vE '^\s*(#|$)' "$config_file" 2>/dev/null | head -n 1 || true)"
  fi

  title="$(strip_outer_quotes "${title:-}")"
  [[ -n "$title" ]] || title="JobsGo"
  print -r -- "$title"
}
# 封装 kv_namespace_lookup_from_json 对应的独立处理逻辑。
kv_namespace_lookup_from_json() {
  local json_file="$1"
  local lookup_mode="$2"
  local lookup_value="$3"
  local output_field="$4"

  [[ -f "$json_file" ]] || return 1

  KV_JSON_FILE="$json_file" \
  KV_LOOKUP_MODE="$lookup_mode" \
  KV_LOOKUP_VALUE="$lookup_value" \
  KV_OUTPUT_FIELD="$output_field" \
  node <<'NODE'
const fs = require('fs');
const file = process.env.KV_JSON_FILE;
const mode = process.env.KV_LOOKUP_MODE || 'any';
const value = process.env.KV_LOOKUP_VALUE || '';
const output = process.env.KV_OUTPUT_FIELD || 'id';
const raw = fs.readFileSync(file, 'utf8').trim();

function collect(input) {
  if (!input) return [];
  if (Array.isArray(input)) return input.flatMap(collect);
  if (typeof input !== 'object') return [];

  const picked = [];
  if (input.id || input.title || input.name) picked.push(input);

  for (const key of ['result', 'results', 'namespaces', 'namespace', 'kv_namespaces', 'kv_namespace']) {
    if (input[key]) picked.push(...collect(input[key]));
  }

  return picked;
}

function field(item, name) {
  if (!item) return '';
  if (name === 'title') return String(item.title || item.name || '');
  if (name === 'id') return String(item.id || '');
  return String(item[name] || '');
}

function selectFromItems(items) {
  let item;
  if (mode === 'title') {
    item = items.find(x => field(x, 'title') === value) ||
           items.find(x => field(x, 'title').toLowerCase() === value.toLowerCase());
  } else if (mode === 'id') {
    item = items.find(x => field(x, 'id') === value);
  } else {
    item = items.find(x => field(x, 'id'));
  }
  return field(item, output);
}

function tryJsonParse(text) {
  const candidates = [text];
  const firstArray = text.indexOf('[');
  const lastArray = text.lastIndexOf(']');
  if (firstArray >= 0 && lastArray > firstArray) candidates.push(text.slice(firstArray, lastArray + 1));
  const firstObj = text.indexOf('{');
  const lastObj = text.lastIndexOf('}');
  if (firstObj >= 0 && lastObj > firstObj) candidates.push(text.slice(firstObj, lastObj + 1));

  for (const candidate of candidates) {
    # 封装 try 对应的独立处理逻辑。
    try {
      const result = selectFromItems(collect(JSON.parse(candidate)));
      if (result) return result;
    } catch (_) {}
  }
  return '';
}

function tryTextParse(text) {
  const idRe = /\b[a-f0-9]{32}\b/i;
  const lines = text.split(/\r?\n/);

  if (mode === 'id') {
    const line = lines.find(x => x.includes(value));
    if (!line) return '';
    if (output === 'id') return value;
    if (output === 'title') return '已存在';
    return value;
  }

  if (mode === 'title') {
    const matched = lines.find(x => x.toLowerCase().includes(value.toLowerCase()) && idRe.test(x));
    const id = matched && matched.match(idRe)?.[0];
    if (id && output === 'id') return id;
    if (id && output === 'title') return value;
  }

  const id = text.match(idRe)?.[0] || '';
  if (!id) return '';
  if (output === 'id') return id;
  if (output === 'title') return value || '已创建';
  return id;
}

if (!raw) process.exit(1);
const result = tryJsonParse(raw) || tryTextParse(raw);
if (!result) process.exit(1);
process.stdout.write(result);
NODE
}
# 封装 extract_active_kv_binding_id_from_toml 对应的独立处理逻辑。
extract_active_kv_binding_id_from_toml() {
  local toml_file="$1"
  [[ -f "$toml_file" ]] || return 1

  WRANGLER_TOML_FILE="$toml_file" node <<'NODE'
const fs = require('fs');
const file = process.env.WRANGLER_TOML_FILE;
const text = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
const lines = text.split('\n');
const tableHeader = line => /^\s*\[.*\]\s*(?:#.*)?$/.test(line) && !/^\s*#/.test(line);
const kvHeader = line => /^\s*\[\[kv_namespaces\]\]\s*(?:#.*)?$/.test(line) && !/^\s*#/.test(line);
const unquote = value => value.replace(/^\s*['"]?/, '').replace(/['"]?\s*$/, '').trim();

for (let i = 0; i < lines.length; i++) {
  if (!kvHeader(lines[i])) continue;

  let j = i + 1;
  while (j < lines.length && !tableHeader(lines[j])) j++;
  const block = lines.slice(i, j);
  const hasKVBinding = block.some(line => /^\s*binding\s*=\s*['"]KV['"]\s*(?:#.*)?$/.test(line));
  if (!hasKVBinding) continue;

  const idLine = block.find(line => /^\s*id\s*=/.test(line));
  if (!idLine) process.exit(1);
  const id = unquote(idLine.split('=').slice(1).join('='));
  if (!id) process.exit(1);
  process.stdout.write(id);
  process.exit(0);
}

process.exit(1);
NODE
}
# 封装 add_local_git_exclude 对应的独立处理逻辑。
add_local_git_exclude() {
  local pattern="$1"
  local exclude_file=""

  exclude_file="$(git -C "$REPO_ROOT" rev-parse --git-path info/exclude 2>/dev/null || true)"
  [[ -n "$exclude_file" ]] || return 0

  mkdir -p "$(dirname "$exclude_file")" 2>/dev/null || true
  touch "$exclude_file" 2>/dev/null || true

  if [[ -f "$exclude_file" ]] && ! grep -qxF "$pattern" "$exclude_file" 2>/dev/null; then
    printf '\n%s\n' "$pattern" >> "$exclude_file" 2>/dev/null || true
  fi
}
# 封装 generate_wrangler_config_with_kv_binding 对应的独立处理逻辑。
generate_wrangler_config_with_kv_binding() {
  local namespace_id="$1"
  local source_toml="${REPO_ROOT}/wrangler.toml"
  local target_toml="${REPO_ROOT}/.wrangler.jobs.local.toml"

  [[ -f "$source_toml" ]] || die "未找到 wrangler.toml：$source_toml"
  [[ -n "$namespace_id" ]] || die "KV namespace id 为空，无法生成部署配置。"

  WRANGLER_TOML_SOURCE="$source_toml" \
  WRANGLER_TOML_TARGET="$target_toml" \
  KV_NAMESPACE_ID="$namespace_id" \
  node <<'NODE' || return 1
const fs = require('fs');
const source = process.env.WRANGLER_TOML_SOURCE;
const target = process.env.WRANGLER_TOML_TARGET;
const namespaceId = process.env.KV_NAMESPACE_ID;

const text = fs.readFileSync(source, 'utf8').replace(/\r\n/g, '\n');
let lines = text.split('\n');
if (lines.length && lines[lines.length - 1] === '') lines.pop();

const tableHeader = line => /^\s*\[.*\]\s*(?:#.*)?$/.test(line) && !/^\s*#/.test(line);
const kvHeader = line => /^\s*\[\[kv_namespaces\]\]\s*(?:#.*)?$/.test(line) && !/^\s*#/.test(line);
const out = [];

for (let i = 0; i < lines.length;) {
  if (kvHeader(lines[i])) {
    let j = i + 1;
    while (j < lines.length && !tableHeader(lines[j])) j++;
    const block = lines.slice(i, j);
    const hasKVBinding = block.some(line => /^\s*binding\s*=\s*['"]KV['"]\s*(?:#.*)?$/.test(line));
    if (hasKVBinding) {
      i = j;
      continue;
    }
  }

  out.push(lines[i]);
  i++;
}

while (out.length && out[out.length - 1].trim() === '') out.pop();
if (out.length) out.push('');
out.push('# 自动由脚本生成：edgetunnel 代码读取 env.KV');
out.push('[[kv_namespaces]]');
out.push('binding = "KV"');
out.push(`id = "${namespaceId}"`);

fs.writeFileSync(target, out.join('\n') + '\n', 'utf8');
NODE

  [[ $? -eq 0 ]] || die "生成本地 Wrangler 部署配置失败。"
  WRANGLER_CONFIG_FOR_DEPLOY="$target_toml"
  add_local_git_exclude ".wrangler.jobs.local.toml"
  success_echo "已生成本地部署配置：$target_toml"
  gray_echo "说明：原始 wrangler.toml 不会被改脏；部署时使用 --config .wrangler.jobs.local.toml。"
}
# 检查当前运行条件是否满足后续流程要求。
ensure_edgetunnel_kv_binding() {
  highlight_echo "============================== Cloudflare KV Binding ============================="

  local source_toml="${REPO_ROOT}/wrangler.toml"
  local generated_toml="${REPO_ROOT}/.wrangler.jobs.local.toml"
  [[ -f "$source_toml" ]] || die "未找到 wrangler.toml：$source_toml"

  local namespace_title=""
  local namespace_id=""
  local existing_id=""
  local existing_title=""
  local list_log="/tmp/${SCRIPT_BASENAME}.kv-list.log"
  local create_log="/tmp/${SCRIPT_BASENAME}.kv-create.log"

  namespace_title="$(resolve_edgetunnel_kv_namespace_title)"
  gray_echo "目标 KV 命名空间名称：$namespace_title"
  gray_echo "目标 Worker 绑定变量名：KV"

  capture_wrangler_cmd_to_file "读取 Cloudflare KV 命名空间列表" "$list_log" kv namespace list || die "读取 Cloudflare KV 命名空间列表失败。"

  existing_id="$(extract_active_kv_binding_id_from_toml "$source_toml" 2>/dev/null || true)"
  if [[ -z "$existing_id" && -f "$generated_toml" ]]; then
    existing_id="$(extract_active_kv_binding_id_from_toml "$generated_toml" 2>/dev/null || true)"
    [[ -n "$existing_id" ]] && gray_echo "已从上次自动生成的本地部署配置读取 KV id：$existing_id"
  fi

  if [[ -n "$existing_id" ]]; then
    existing_title="$(kv_namespace_lookup_from_json "$list_log" id "$existing_id" title 2>/dev/null || true)"
    if [[ -n "$existing_title" ]]; then
      success_echo "已检测到有效 KV 绑定：KV -> ${existing_title} (${existing_id})"
      generate_wrangler_config_with_kv_binding "$existing_id"
      return 0
    fi

    warn_echo "已记录的 KV id 未在当前 Cloudflare 账号下找到：$existing_id"
    warn_echo "将改用命名空间名称 ${namespace_title} 自动修复本次部署配置。"
  fi

  namespace_id="$(kv_namespace_lookup_from_json "$list_log" title "$namespace_title" id 2>/dev/null || true)"

  if [[ -z "$namespace_id" ]]; then
    warn_echo "未找到 KV 命名空间：$namespace_title，将自动创建。"
    capture_wrangler_cmd_to_file "创建 Cloudflare KV 命名空间" "$create_log" kv namespace create "$namespace_title" || die "创建 Cloudflare KV 命名空间失败：$namespace_title"

    namespace_id="$(kv_namespace_lookup_from_json "$create_log" title "$namespace_title" id 2>/dev/null || true)"
    [[ -n "$namespace_id" ]] || namespace_id="$(kv_namespace_lookup_from_json "$create_log" any "" id 2>/dev/null || true)"

    if [[ -z "$namespace_id" ]]; then
      warn_echo "创建命令未直接返回可解析 id，将重新读取命名空间列表确认。"
      capture_wrangler_cmd_to_file "重新读取 Cloudflare KV 命名空间列表" "$list_log" kv namespace list || die "重新读取 Cloudflare KV 命名空间列表失败。"
      namespace_id="$(kv_namespace_lookup_from_json "$list_log" title "$namespace_title" id 2>/dev/null || true)"
    fi
  else
    success_echo "已找到 KV 命名空间：$namespace_title (${namespace_id})"
  fi

  [[ -n "$namespace_id" ]] || die "无法取得 KV 命名空间 id：$namespace_title"

  generate_wrangler_config_with_kv_binding "$namespace_id"
  success_echo "KV 绑定已就绪：binding = KV，namespace = ${namespace_title}，id = ${namespace_id}"
}
# 执行已经拆分完成的独立业务步骤。
run_wrangler_deploy() {
  export npm_config_yes="true"

  ensure_wrangler_auth
  ensure_edgetunnel_kv_binding

  highlight_echo "============================== Wrangler Deploy ============================="
  if [[ -n "$WRANGLER_CONFIG_FOR_DEPLOY" ]]; then
    run_wrangler_cmd "执行 Cloudflare 部署" deploy --config "$WRANGLER_CONFIG_FOR_DEPLOY" || die "wrangler deploy 执行失败。"
  else
    run_wrangler_cmd "执行 Cloudflare 部署" deploy || die "wrangler deploy 执行失败。"
  fi
}
# 执行入口下沉后的完整业务流程和控制逻辑。
run_main_business_flow() {
  # 执行当前流程中的独立业务步骤：处理当前语句。
  [[ "$(uname -s)" == "Darwin" ]] || die "当前脚本按 macOS / zsh / Homebrew 环境编写，请在 macOS 上执行。"

  # 检查当前步骤所需的环境、路径或输入条件。
  ensure_git
  # 准备后续业务需要的配置、目录或运行上下文。
  resolve_target_repo_root "$@"
  # 检查当前步骤所需的环境、路径或输入条件。
  validate_target_repo
  # 准备后续业务需要的配置、目录或运行上下文。
  prepare_toolchain_for_current_context
  # 执行当前流程中的独立业务步骤：print_toolchain_versions。
  print_toolchain_versions
  # 执行当前流程中的独立业务步骤：run_wrangler_deploy。
  run_wrangler_deploy

  # 输出当前流程的完成状态、摘要和日志位置。
  success_echo "全部完成。"
  # 输出当前流程的完成状态、摘要和日志位置。
  success_echo "日志文件：$LOG_FILE"
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  setopt NO_NOMATCH
  set -u
  set -o pipefail 2>/dev/null || true
  : > "$LOG_FILE"
  is_sourcetree_runtime && IS_SOURCETREE_RUNTIME=1
  [[ -n "${TERM:-}" ]] || export TERM="dumb"
  if [[ "$IS_SOURCETREE_RUNTIME" == "1" || ! -t 1 || "$TERM" == "dumb" || -n "${NO_COLOR:-}" ]]; then
    SOURCETREE_PLAIN_OUTPUT=1
    export NO_COLOR="${NO_COLOR:-1}"
    export CLICOLOR="0"
    export ANSI_COLORS_DISABLED="1"
  fi
  configure_output_mode
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
