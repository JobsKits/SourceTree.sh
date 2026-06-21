#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】📦双击自动生成ipa文件.command
# - 核心用途：执行“📦双击自动生成ipa文件”对应的移动端项目自动化任务。
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
  # shellcheck shell=zsh

  set -euo pipefail

  # ===============================================================
  # 默认配置
  # ===============================================================
  CONFIG="Release"           # Debug / Release
  OUT_DIR="${HOME}/Desktop"  # .ipa 输出目录
  PROJECT_PATH=""            # 指定 .xcodeproj 或 .xcworkspace 的完整路径
  LOG_FILE="/tmp/package_ipa.log"
  # ===============================================================
  # 语义化输出 & 日志
  # ===============================================================
  _color()        { local c="$1"; shift; printf "\033[%sm%s\033[0m\n" "$c" "$*"; }
  # 输出 info echo 对应级别的日志信息。
  info_echo()    { _color "34" "ℹ️  $*";  }
  # 输出 success echo 对应级别的日志信息。
  success_echo() { _color "32" "✅ $*";   }
  # 输出 warn echo 对应级别的日志信息。
  warn_echo()    { _color "33" "⚠️  $*";  }
  # 输出 error echo 对应级别的日志信息。
  error_echo()   { _color "31" "❌ $*";   }
  # 统一输出终端信息并同步记录日志。
  log()          { printf "%s %s\n" "$(date '+%F %T')" "$*" >> "$LOG_FILE"; }
  # ===============================================================
  # 帮助
  # ===============================================================
  usage() {
    cat <<EOF
用法:
  $(basename "$0") [--config Debug|Release] [--out 输出目录] [--project 路径]

参数:
  --config   构建配置，默认 Release
  --out      .ipa 输出目录，默认 \$HOME/Desktop
  --project  指定 .xcodeproj 或 .xcworkspace 的完整路径

示例:
  $(basename "$0") --config Release --out ~/Desktop
  $(basename "$0") --project ./MyApp.xcodeproj
EOF
  }
  # ===============================================================
  # 参数解析
  # ===============================================================
  parse_args() {
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --config)  CONFIG="${2:-Release}"; shift 2 ;;
        --out)     OUT_DIR="${2:-$OUT_DIR}"; shift 2 ;;
        --project) PROJECT_PATH="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)         warn_echo "忽略未知参数：$1"; shift ;;
      esac
    done
  }
  # ===============================================================
  # 准备环境
  # ===============================================================
  prepare_env() {
    mkdir -p "$OUT_DIR"
    : > "$LOG_FILE"
  }
  # ===============================================================
  # 获取仓库根目录（优先 git）
  # ===============================================================
  find_repo_root() {
    if command -v git >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
      git rev-parse --show-toplevel
    else
      cd "$(dirname "$0")"
      pwd
    fi
  }
  # ===============================================================
  # 选择工程文件（优先 .xcworkspace）
  # ===============================================================
  choose_project_path() {
    local root="$1"
    local path="$PROJECT_PATH"

    if [[ -z "$path" ]]; then
      set +e
      local WORKSPACES=($(find "$root" -maxdepth 2 -name "*.xcworkspace" -print 2>/dev/null))
      local PROJECTS=($(find "$root" -maxdepth 2 -name "*.xcodeproj"   -print 2>/dev/null))
      set -e

      if [[ ${#WORKSPACES[@]} -gt 0 ]]; then
        path="${WORKSPACES[1]}"
      elif [[ ${#PROJECTS[@]} -gt 0 ]]; then
        path="${PROJECTS[1]}"
      else
        error_echo "未在 $root 找到 .xcworkspace / .xcodeproj"
        exit 1
      fi
    fi

    if [[ ! -e "$path" ]]; then
      error_echo "--project 指定的路径不存在：$path"
      exit 1
    fi

    echo "$path"
  }
  # ===============================================================
  # 查找最新 .app（优先 CONFIG，再回退 Debug）
  # ===============================================================
  find_latest_app() {
    local derived="${HOME}/Library/Developer/Xcode/DerivedData"
    [[ -d "$derived" ]] || { error_echo "未找到 DerivedData：$derived。请先在 Xcode 做一次真机构建。"; exit 1; }

    set +e
    local app_path
    app_path=$(ls -td "${derived}"/*/Build/Products/${CONFIG}-iphoneos/*.app 2>/dev/null | head -n 1)
    set -e

    if [[ -z "${app_path:-}" || ! -d "$app_path" ]]; then
      warn_echo "未在 ${derived}/**/Build/Products/${CONFIG}-iphoneos/ 找到 .app，尝试使用 Debug..."
      set +e
      app_path=$(ls -td "${derived}"/*/Build/Products/Debug-iphoneos/*.app 2>/dev/null | head -n 1)
      set -e
    fi

    if [[ -z "${app_path:-}" || ! -d "$app_path" ]]; then
      error_echo "还是找不到 .app。请确认你已对真机目标完成构建（Product > Build）。"
      exit 1
    fi

    echo "$app_path"
  }
  # ===============================================================
  # 推断 IPA 名称（CFBundleDisplayName > CFBundleName > 工程名）
  # ===============================================================
  infer_ipa_name() {
    local app_dir="$1"
    local fallback="$2"
    local plist="$app_dir/Info.plist"
    local name=""

    if [[ -f "$plist" ]]; then
      name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "$plist" 2>/dev/null || true)
      [[ -z "$name" ]] && name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "$plist" 2>/dev/null || true)
    fi
    [[ -n "$name" ]] || name="$fallback"
    echo "$name"
  }
  # ===============================================================
  # 打包 .ipa
  # ===============================================================
  package_ipa() {
    local app_dir="$1"
    local ipa_path="$2"

    local tmp_dir payload_dir
    tmp_dir="$(mktemp -d)"
    payload_dir="${tmp_dir}/Payload"

    mkdir -p "$payload_dir"
    cp -R "$app_dir" "$payload_dir/"

    info_echo "📦 正在打包为 .ipa ..."
    (
      cd "$tmp_dir"
      /usr/bin/zip -qry "$ipa_path" "Payload"
    )
    rm -rf "$tmp_dir"
  }
  # ===============================================================
  # main：统一调度
  # ===============================================================
  main() {
    parse_args "$@"
    prepare_env

    local repo_root project_path project_base latest_app ipa_name ipa_path

    repo_root="$(find_repo_root)"
    info_echo "📂 工作目录：$repo_root"; log "repo_root=$repo_root"

    project_path="$(choose_project_path "$repo_root")"
    project_base="$(basename "$project_path")"
    success_echo "发现工程：$project_base"
    log "project=$project_path"

    latest_app="$(find_latest_app)"
    success_echo "✅ 最新 .app：$latest_app"
    log "app=$latest_app"

    ipa_name="$(infer_ipa_name "$latest_app" "${project_base%.*}")"
    ipa_path="${OUT_DIR}/${ipa_name}.ipa"

    package_ipa "$latest_app" "$ipa_path"
    success_echo "🎉 打包完成：$ipa_path"
    log "ipa=$ipa_path"

    open -R "$ipa_path" 2>/dev/null || true
  }

  # ===============================================================
  # 执行入口
  # ===============================================================
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
