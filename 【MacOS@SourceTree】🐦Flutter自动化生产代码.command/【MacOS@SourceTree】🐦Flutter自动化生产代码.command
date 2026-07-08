#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】🐦Flutter自动化生产代码.command
# - 核心用途：执行“🐦Flutter自动化生产代码”对应的移动端项目自动化任务。
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
# 封装 strip_ansi_text 对应的独立处理逻辑。
strip_ansi_text() {
  perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}
# 根据运行入口和终端能力预先切换纯文本输出，避免 Sourcetree 显示 ANSI 转义码。
prepare_plain_output_context() {
  [[ -n "${TERM:-}" ]] || export TERM="dumb"
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" || ! -t 1 || "$TERM" == "dumb" || -n "${NO_COLOR:-}" || "${JOBS_PLAIN_OUTPUT:-0}" == "1" ]]; then
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
  if [[ "${SOURCETREE_PLAIN_OUTPUT:-0}" == "1" ]]; then
    printf "%b\n" "$1" | strip_ansi_text | tee -a "$LOG_FILE"
  else
    printf "%b\n" "$1" | tee -a "$LOG_FILE"
  fi
}
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
# ============================= 标准工具函数 =============================
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}
# 封装 abs_path 对应的独立处理逻辑。
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
# 收集并校验用户输入，决定后续执行路径。
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
# 收集并校验用户输入，决定后续执行路径。
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
# 封装 inject_shellenv_block 对应的独立处理逻辑。
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
# 封装 activate_homebrew_shellenv 对应的独立处理逻辑。
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
# 执行已经拆分完成的独立业务步骤。
run_brew_health_update() {
  info_echo "正在执行 Homebrew 健康更新..."
  brew update  || { error_echo "brew update 失败"; return 1; }
  brew upgrade || { error_echo "brew upgrade 失败"; return 1; }
  brew cleanup || { error_echo "brew cleanup 失败"; return 1; }
  brew doctor  || warn_echo "brew doctor 有警告，请按输出处理"
  brew -v      || warn_echo "打印 brew 版本失败，可忽略"
  success_echo "Homebrew 健康更新完成"
}
# 执行对应的环境配置或同步处理。
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
# 封装 brew_install_or_upgrade 对应的独立处理逻辑。
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
# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_readme_and_wait() {
  if typeset -f is_sourcetree_runtime >/dev/null 2>&1 && is_sourcetree_runtime; then
    IS_SOURCETREE_RUNTIME=1
  fi
  prepare_plain_output_context
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
# 执行已经拆分完成的独立业务步骤。
run_original_logic() {
  # ============================= 原脚本业务逻辑区 =============================
  # ============================== 配置开关（可用环境变量覆盖） ==============================
  WATCH="${WATCH:-0}"     # 交互时可 WATCH=1 开启 build_runner watch；非交互一律关闭
  PROJECT_DIR="${PROJECT_DIR:-}"  # 指定项目根；不指定则自动探测

  # ============================== 工具链选择（FVM 优先） ==============================
  typeset -ga flutter_cmd dart_cmd
  # 封装 _set_toolchain 对应的独立处理逻辑。
  _set_toolchain() {
    if command -v fvm >/dev/null 2>&1 && [[ -f ".fvmrc" || -d ".fvm" ]]; then
      flutter_cmd=(fvm flutter)
      dart_cmd=(fvm dart)
    else
      if ! command -v flutter >/dev/null 2>&1; then
        echo "❌ 未找到 flutter 命令；请确认 PATH 或安装 FVM/Flutter。"; exit 1
      fi
      flutter_cmd=(flutter)
      # 优先使用 Flutter 内置的 dart（避免系统 dart 版本不一致）
      local dart_in_flutter
      dart_in_flutter="$(dirname "$(command -v "${flutter_cmd[@]}")")/../cache/dart-sdk/bin/dart"
      if [[ -x "$dart_in_flutter" ]]; then
        dart_cmd=("$dart_in_flutter")
      else
        dart_cmd=(dart)
      fi
    fi
  }
  # ============================== TTY 检测 & 说明 ==============================
  _is_tty() { [[ -t 0 && -t 1 ]]; }
  # 封装 print_description 对应的独立处理逻辑。
  print_description() {
    cat <<'DESC'
[目的]
1) 确保你在 Flutter 项目根目录（同时存在 lib/ 与 pubspec.yaml）。
2) 交互模式下会等待你按回车并支持拖拽路径；非交互模式自动探测项目根。
3) 根据项目配置自动跑：pub get、build_runner、图标、Splash、l10n、FFI、Pigeon、Protobuf。

[提示]
- 非交互环境（如 SourceTree 自定义动作）不会等待输入，也不会进入 watch。
- 使用 FVM 时自动用 FVM 的 flutter/dart；否则用系统 flutter 与其内置 dart。
DESC
  }
  # 封装 wait_for_user_to_start 对应的独立处理逻辑。
  wait_for_user_to_start() {
    echo ""
    read "?👉 按下回车开始执行（Ctrl+C 取消）"
    echo ""
  }
  # ============================== 项目根判断 & 查找 ==============================
  _is_flutter_root() { [[ -d "$1/lib" && -f "$1/pubspec.yaml" ]]; }
  # 封装 _find_flutter_root_upwards 对应的独立处理逻辑。
  _find_flutter_root_upwards() {
    local d="$1"
    while [[ "$d" != "/" && -n "$d" ]]; do
      _is_flutter_root "$d" && { echo "$d"; return 0; }
      d="${d:h}"
    done
    return 1
  }
  # 解析并返回后续流程需要的目标信息。
  detect_and_cd_flutter_root() {
    # 优先显式指定
    if [[ -n "$PROJECT_DIR" ]]; then
      if _is_flutter_root "$PROJECT_DIR"; then
        cd "$PROJECT_DIR" || { echo "❌ 切换失败：$PROJECT_DIR"; exit 1; }
        echo "✅ 已切换到 Flutter 项目目录：$PWD"
        return 0
      else
        echo "❌ 指定的 PROJECT_DIR 不是 Flutter 根：$PROJECT_DIR"; exit 1
      fi
    fi

    if _is_tty; then
      # 交互模式：循环询问
      while true; do
        if _is_flutter_root "$PWD"; then
          echo "✅ 已确认 Flutter 项目目录：$PWD"; return 0
        fi
        echo "❌ 当前目录不是 Flutter 根：$PWD（需有 lib/ 与 pubspec.yaml）"
        echo "提示：可将项目根目录从 Finder 拖入后回车。"
        read "input_path?👉 请输入 Flutter 项目路径（或直接回车重新检测当前目录）： "
        [[ -z "$input_path" ]] && continue
        # 去引号与空格转义
        local p="${input_path//\\ / }"; p="${p%\"}"; p="${p#\"}"; p="${p%\'}"; p="${p#\'}"
        [[ "$p" = ~* ]] && p="${p/#\~/$HOME}"
        if _is_flutter_root "$p"; then
          cd "$p" || { echo "❌ 切换失败：$p"; echo ""; continue; }
          echo "✅ 已切换到 Flutter 项目目录：$PWD"; return 0
        else
          echo "❌ [$p] 不是合法 Flutter 根"; echo ""
        fi
      done
    else
      # 非交互模式：自动探测（当前目录 → git 根）
      if _is_flutter_root "$PWD"; then
        echo "✅ 非交互：使用当前目录作为 Flutter 根：$PWD"; return 0
      fi
      local git_root
      git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
      if [[ -n "$git_root" ]]; then
        local found
        found="$(_find_flutter_root_upwards "$git_root")" || true
        if [[ -n "$found" ]]; then
          cd "$found" || { echo "❌ 切换失败：$found"; exit 1; }
          echo "✅ 非交互：已定位 Flutter 根：$PWD"; return 0
        fi
      fi
      echo "❌ 非交互：未能自动定位 Flutter 根，请设置 PROJECT_DIR=路径 后重试。"; exit 1
    fi
  }
  # ============================== 运行辅助 ==============================
  run_step() {
    local title="$1"; shift
    echo "==> $title"
    if "$@"; then
      echo "✅ $title 完成"; echo ""
    else
      echo "⚠️  $title 失败（忽略继续）"; echo ""
    fi
  }
  # 封装 exists 对应的独立处理逻辑。
  exists() { command -v "$1" >/dev/null 2>&1; }
  # 检查当前运行条件是否满足后续流程要求。
  has_yaml_key() { grep -qE "^[[:space:]]*$1[[:space:]]*:" pubspec.yaml; }
  # ============================== 图标产物汇总 ==============================
  show_icon_summary() {
    echo "—— 图标产物汇总 ——"

    echo "【Android】👇"
    ls -1 android/app/src/main/res/mipmap-*/ic_launcher.* || echo "（未找到 Android ic_launcher 图标）"

    echo ""
    echo "【iOS】👇"
    ls -1 ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png 2>/dev/null || echo "（未找到 iOS 图标 PNG）"

    echo "—— 结束 ——"
    echo ""
  }
  # ============================== 主流程 ==============================
  main() {
    _set_toolchain
    if _is_tty; then clear; print_description; wait_for_user_to_start; else echo "ℹ 非交互模式（SourceTree 等）"; fi
    detect_and_cd_flutter_root

    # 1) 清理 & 依赖
    run_step "flutter clean" "${flutter_cmd[@]}" clean
    run_step "flutter pub get" "${flutter_cmd[@]}" pub get

    # 2) build_runner（一次性；watch 仅交互+显式开启）
    if grep -q 'build_runner' pubspec.yaml; then
      run_step "build_runner build" "${dart_cmd[@]}" run build_runner build --delete-conflicting-outputs
      if _is_tty && [[ "$WATCH" == "1" ]]; then
        echo "==> build_runner watch（按 Ctrl+C 结束）"
        exec "${dart_cmd[@]}" run build_runner watch --delete-conflicting-outputs
      fi
    fi

    # 3) App Icon（flutter_launcher_icons）
    if has_yaml_key "flutter_launcher_icons"; then
      # 清残留，避免 v26 xml 搞事
      find android/app/src/main/res -name 'ic_launcher*' -delete 2>/dev/null || true
      run_step "生成 App Icon (flutter_launcher_icons)" \
        "${flutter_cmd[@]}" pub run flutter_launcher_icons:main
      # ✅ 同时打印 Android + iOS 产物
      show_icon_summary
    fi

    # 4) Splash（flutter_native_splash）
    if grep -q 'flutter_native_splash' pubspec.yaml; then
      run_step "生成启动页 (flutter_native_splash)" \
        "${flutter_cmd[@]}" pub run flutter_native_splash:create
    fi

    # 5) 官方 l10n
    if [[ -d "lib/l10n" || -f "l10n.yaml" ]]; then
      run_step "生成本地化 (flutter gen-l10n)" "${flutter_cmd[@]}" gen-l10n
    fi

    # 6) ffigen（需配置）
    if grep -q 'ffigen' pubspec.yaml; then
      run_step "FFI 绑定生成 (ffigen)" "${dart_cmd[@]}" run ffigen
    fi

    # 7) Pigeon（若有 pigeons 目录）
    if [[ -d "pigeons" ]]; then
      mkdir -p lib/pigeon
      run_step "Pigeon 生成" "${dart_cmd[@]}" run pigeon \
        --input pigeons/messages.dart \
        --dart_out lib/pigeon/messages.g.dart
    fi

    # 8) Protobuf（若有 protos 且安装了 protoc）
    if [[ -d "protos" ]] && exists protoc; then
      mkdir -p lib/generated
      run_step "Protobuf/gRPC 生成" protoc --dart_out=grpc:lib/generated -Iprotos protos/*.proto
    fi

    echo "🎯 全部完成。"
  }

  main "$@"

  # =========================== 原脚本业务逻辑区结束 ===========================
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  : > "$LOG_FILE"
  is_sourcetree_runtime && IS_SOURCETREE_RUNTIME=1
  prepare_plain_output_context
  [[ -n "${TERM:-}" ]] || export TERM="dumb"
  if [[ "$IS_SOURCETREE_RUNTIME" == "1" || ! -t 1 || "$TERM" == "dumb" || -n "${NO_COLOR:-}" ]]; then
    SOURCETREE_PLAIN_OUTPUT=1
    export NO_COLOR="${NO_COLOR:-1}"
    export FORCE_COLOR=0
    export CLICOLOR="0"
    export ANSI_COLORS_DISABLED="1"
    export npm_config_color=false
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
