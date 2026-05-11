#!/bin/zsh
# =====================================================================
# Jobs 标准化脚本外壳
# 说明：保留原脚本业务逻辑，补齐 README 防误触、彩色日志、zsh 入口、Homebrew 健康自检标准。
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME="$(basename "$0" | sed 's/\.[^.]*$//')"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
: > "$LOG_FILE"

log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
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

# ============================= 标准工具函数 =============================
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}

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

ask_run() {
  echo ""
  note_echo "👉 $1"
  gray_echo "【回车=跳过，输入任意字符后回车=执行】"
  local input=""
  IFS= read -r "input?➤ "
  [[ -n "$input" ]]
}

confirm_yes() {
  echo ""
  warn_echo "⚠ $1"
  gray_echo "危险操作必须输入 YES 后回车；其它输入一律取消。"
  local input=""
  IFS= read -r "input?➤ "
  [[ "$input" == "YES" ]]
}

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

run_brew_health_update() {
  info_echo "正在执行 Homebrew 健康更新..."
  brew update  || { error_echo "brew update 失败"; return 1; }
  brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
  brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
  brew doctor  || warn_echo "brew doctor 有警告，请按输出处理"
  brew -v      || warn_echo "打印 brew 版本失败，可忽略"
  success_echo "Homebrew 健康更新完成"
}

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

show_readme_and_wait() {
  clear
  local readme_path="${SCRIPT_DIR}/README.md"
  if [[ -f "$readme_path" ]]; then
    highlight_echo "正在显示脚本自述文件：$readme_path"
    echo ""
    cat "$readme_path" | tee -a "$LOG_FILE"
  else
    warn_echo "未找到 README.md：$readme_path"
  fi
  echo ""
  read "?👉 请先阅读上面的自述文件，按回车继续执行，或按 Ctrl+C 取消..."
}

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
  info_echo()    { _color "34" "ℹ️  $*";  }
  success_echo() { _color "32" "✅ $*";   }
  warn_echo()    { _color "33" "⚠️  $*";  }
  error_echo()   { _color "31" "❌ $*";   }
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

main() {
  show_readme_and_wait
  run_original_logic "$@"
  success_echo "脚本执行结束。日志：$LOG_FILE"
}

main "$@"
