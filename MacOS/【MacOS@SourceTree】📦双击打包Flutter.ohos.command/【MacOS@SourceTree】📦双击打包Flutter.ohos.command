#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】📦双击打包Flutter.ohos.command
# - 核心用途：使用鸿蒙适配版 Flutter 构建 HAP 安装包或 APP 上架包。
# - 影响范围：解析工程依赖、执行 Hvigor 构建并写入构建目录；签名沿用工程配置。
# - 运行提示：先打印内置自述；终端回车确认，Sourcetree 无交互执行；缺少工具链时停止。

SCRIPT_SOURCE="$0"
SCRIPT_PATH=""
SCRIPT_DIR=""
SCRIPT_BASENAME=""
LOG_FILE=""
LOG_READY=0
IS_SOURCETREE_RUNTIME=0
PLAIN_OUTPUT=0
PROJECT_ROOT=""
BUILD_BASE=""
BUILD_MODE="${BUILD_MODE:-}"
BUILD_TARGET="${BUILD_TARGET:-}"
SDK_OVERRIDE=""
DEVECO_CONTENTS=""
FLUTTER_CMD=()
BUILD_TARGETS=()
OUTPUT_ROOTS=()

# 通过明确的环境标志和父进程识别 Sourcetree，非 TTY 只影响输出能力。
is_sourcetree_runtime() {
  env | /usr/bin/grep -Eqi '^(SOURCETREE|SOURCE_TREE)' && return 0
  local parent_pid="$PPID" process_name="" depth=0
  while [[ -n "$parent_pid" && "$parent_pid" != 0 && "$depth" -lt 8 ]]; do
    process_name="$(/bin/ps -o comm= -p "$parent_pid" 2>/dev/null)"
    [[ "$process_name" == *SourceTree* || "$process_name" == *Sourcetree* ]] && return 0
    parent_pid="$(/bin/ps -o ppid= -p "$parent_pid" 2>/dev/null | /usr/bin/tr -d ' ')"
    depth=$((depth + 1))
  done
  return 1
}
# 兼容 Sourcetree 只传文件名、中文路径及两个标准脚本位置。
resolve_script_path() {
  local script_name="${SCRIPT_SOURCE:t}" candidate=""
  for candidate in "$SCRIPT_SOURCE" "$PWD/$SCRIPT_SOURCE" \
    "$HOME/SourceTree.command/MacOS/$script_name/$script_name" \
    "$HOME/Documents/Github/JobsGenesis/SourceTree.command/MacOS/$script_name/$script_name"; do
    [[ -f "$candidate" ]] || continue
    SCRIPT_PATH="${candidate:A}"
    SCRIPT_DIR="${SCRIPT_PATH:h}"
    SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
    LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
    return 0
  done
  print -u2 -r -- "无法定位脚本，请使用完整路径运行：$script_name"
  return 1
}
# 在第一屏及正式执行前同步初始化纯文本环境。
configure_output_mode() {
  if [[ "$IS_SOURCETREE_RUNTIME" == 1 || ! -t 1 || -z "${TERM:-}" || "${TERM:-}" == dumb || -n "${NO_COLOR+x}" ]]; then
    PLAIN_OUTPUT=1
    export NO_COLOR=1 FORCE_COLOR=0 CLICOLOR=0 ANSI_COLORS_DISABLED=1 npm_config_color=false
  fi
}
# 过滤脚本和外部命令输出中的 ANSI 颜色与控制序列。
strip_ansi_stream() {
  /usr/bin/perl -pe 's/\e\][^\a]*(?:\a|\e\\)//g; s/\e\[[0-?]*[ -\/]*[@-~]//g; s/\\(?:033|e|x1[bB])\[[0-9;]*m//g'
}
# 终端和日志同步记录；日志始终保存可检索的纯文本。
log() {
  local line="$1"
  if [[ "$PLAIN_OUTPUT" == 1 ]]; then
    print -r -- "$line" | strip_ansi_stream
  else
    print -r -- "$line"
  fi
  if [[ "$LOG_READY" == 1 ]]; then
    print -r -- "$line" | strip_ansi_stream >> "$LOG_FILE" || return 1
  fi
}
# 颜色仅用于终端展示，避免把路径内反斜杠当转义字符。
color_log() {
  if [[ "$PLAIN_OUTPUT" == 1 ]]; then
    log "$2"
  else
    log "$(printf '\033[%sm%s\033[0m' "$1" "$2")"
  fi
}
# 输出构建步骤与环境信息。
info_echo() { color_log '1;34' "ℹ $1"; }
# 输出已经核验的结果。
success_echo() { color_log '1;32' "✔ $1"; }
# 输出需要人工处理的条件。
warn_echo() { color_log '1;33' "⚠ $1"; }
# 输出失败原因。
error_echo() { color_log '1;31' "✖ $1"; }
# 自述标题红色加粗，正文蓝色常规字重。
intro_line() {
  local style='0;34'
  [[ "$1" == title ]] && style='1;31'
  color_log "$style" "$2"
}
# 首先展示固定自述，确认之前不写日志或改动工程。
show_script_intro_and_wait() {
  resolve_script_path || exit 1
  if is_sourcetree_runtime; then
    IS_SOURCETREE_RUNTIME=1
  fi
  configure_output_mode
  intro_line title "================ 鸿蒙 Flutter 打包 ================"
  intro_line title "脚本名称：${SCRIPT_BASENAME}.command"
  intro_line body '1、用途：构建已有 Flutter 鸿蒙工程，默认生成 release HAP；可选 APP 或两者。'
  intro_line body '2、依赖：鸿蒙适配 Flutter → Dart / 鸿蒙 SDK → Node / ohpm / Hvigor / Java。'
  intro_line body '3、影响：联网解析依赖、执行工程构建与现有签名配置，写入缓存和构建目录。'
  intro_line body '4、策略：不自动安装、升级工具链，不创建 ohos 平台，不修改证书或系统环境配置。'
  intro_line body '5、Sourcetree 传入仓库路径后连续执行；独立终端回车继续，Ctrl+C 取消。'
  intro_line body "日志：$LOG_FILE"
  intro_line title '===================================================='
  [[ "$IS_SOURCETREE_RUNTIME" == 1 ]] && return 0
  if [[ ! -t 0 ]]; then
    error_echo '当前不是 Sourcetree 且没有交互输入，请在终端运行。'
    exit 1
  fi
  local answer=""
  IFS= read -r 'answer?👉 按回车继续；Ctrl+C 取消：' || exit 1
}
# 确认后配置当前进程和日志，保留调用者 PATH 优先级。
initialize_script_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  export PATH="${PATH:-/usr/bin:/bin}:/opt/homebrew/bin:/usr/local/bin:$HOME/.pub-cache/bin:$HOME/.fvm/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  configure_output_mode
  : > "$LOG_FILE" || { print -u2 -r -- "日志不可写：$LOG_FILE"; exit 1; }
  LOG_READY=1
}
# 先校验全部参数，再进入 SDK 或联网操作。
parse_build_options() {
  BUILD_MODE="${BUILD_MODE:-release}"
  BUILD_TARGET="${BUILD_TARGET:-hap}"
  SDK_OVERRIDE="${FLUTTER_OHOS_SDK:-}"
  while (( $# > 0 )); do
    case "$1" in
      --mode|--target|--flutter-sdk)
        (( $# >= 2 )) && [[ -n "$2" && "$2" != --* ]] || { error_echo "$1 缺少参数值。"; return 2; }
        case "$1" in
          --mode) BUILD_MODE="$2" ;;
          --target) BUILD_TARGET="$2" ;;
          --flutter-sdk) SDK_OVERRIDE="$2" ;;
        esac
        shift 2
        ;;
      --)
        shift
        (( $# <= 1 )) && [[ -z "$BUILD_BASE" ]] || { error_echo '只能指定一个工程目录。'; return 2; }
        BUILD_BASE="${1:-}"
        break
        ;;
      -*) error_echo "未知参数：$1"; return 2 ;;
      *) [[ -z "$BUILD_BASE" ]] || { error_echo '只能指定一个工程目录。'; return 2; }; BUILD_BASE="$1"; shift ;;
    esac
  done
  case "$BUILD_MODE" in release|debug|profile) ;; *) error_echo "无效构建模式：$BUILD_MODE"; return 2 ;; esac
  case "$BUILD_TARGET" in hap|app|all) ;; *) error_echo "无效鸿蒙产物类型：$BUILD_TARGET"; return 2 ;; esac
  [[ "${OPEN_AFTER_BUILD:-1}" == [01] ]] || { error_echo 'OPEN_AFTER_BUILD 只能是 0 或 1。'; return 2; }
  BUILD_TARGETS=("$BUILD_TARGET")
  [[ "$BUILD_TARGET" == all ]] && BUILD_TARGETS=(hap app)
  return 0
}
# 解除拖入路径的外层引号和转义，保留有效文件名中的原有字符。
normalize_input_path() {
  local input_value="$1"
  if [[ ! -e "$input_value" ]]; then
    input_value="${input_value%$'\r'}"
    input_value="${input_value%$'\n'}"
    [[ "$input_value" == \"*\" || "$input_value" == \'*\' ]] && input_value="${input_value[2,-2]}"
    [[ "$input_value" == '~/'* ]] && input_value="$HOME/${input_value#\~/}"
    [[ -e "$input_value" ]] || input_value="${(Q)input_value}"
  fi
  print -r -- "$input_value"
}
# 向上查找或在指定目录内查找唯一 Flutter 工程，跳过第三方和构建目录。
resolve_flutter_project() {
  local base="$(normalize_input_path "${BUILD_BASE:-${PROJECT_DIR:-${REPO:-$PWD}}}")" current="" candidate=""
  local -a candidates=()
  [[ -f "$base" ]] && base="${base:h}"
  [[ -d "$base" ]] || { error_echo "工程路径不存在：$base"; return 1; }
  base="${base:A}"
  [[ "$base" != / && "$base" != "$HOME" ]] || { error_echo '请指定工程目录，拒绝扫描根目录或整个用户目录。'; return 1; }
  current="$base"
  while [[ "$current" != / ]]; do
    if [[ -f "$current/pubspec.yaml" && -d "$current/lib" ]]; then
      PROJECT_ROOT="$current"
      break
    fi
    current="${current:h}"
  done
  if [[ -z "$PROJECT_ROOT" ]]; then
    while IFS= read -r -d '' candidate; do
      [[ -d "${candidate:h}/lib" ]] && candidates+=("${candidate:h}")
    done < <(/usr/bin/find "$base" \( -type d \( -name .git -o -name node_modules -o -name Pods -o -name PodsManual -o -name 'ManualBy*Pods*' -o -name .dart_tool -o -name .fvm -o -name build -o -name DerivedData -o -name vendor -o -name third_party -o -name ThirdParty \) -prune \) -o \( -type f -name pubspec.yaml -print0 \))
    if (( ${#candidates[@]} != 1 )); then
      error_echo "应找到唯一 Flutter 工程，候选数：${#candidates[@]}；请直接指定工程根目录。"
      for candidate in "${candidates[@]}"; do log "候选：$candidate"; done
      return 1
    fi
    PROJECT_ROOT="${candidates[1]}"
  fi
  [[ -f "$PROJECT_ROOT/ohos/build-profile.json5" && -f "$PROJECT_ROOT/ohos/oh-package.json5" ]] || {
    error_echo "工程缺少 ohos/build-profile.json5 或 ohos/oh-package.json5：$PROJECT_ROOT；请先完成鸿蒙适配。"
    return 1
  }
  cd "$PROJECT_ROOT" || return 1
  info_echo "工程目录：$PROJECT_ROOT"
}
# 显式指定 SDK 优先，其次项目固定 SDK，最后当前 PATH；不默默替换固定版本。
choose_flutter_sdk() {
  if [[ -n "$SDK_OVERRIDE" ]]; then
    SDK_OVERRIDE="$(normalize_input_path "$SDK_OVERRIDE")"
    [[ -x "$SDK_OVERRIDE/bin/flutter" ]] || { error_echo "指定 SDK 中没有可执行 bin/flutter：$SDK_OVERRIDE"; return 1; }
    FLUTTER_CMD=("${SDK_OVERRIDE:A}/bin/flutter")
  elif [[ -x "$PROJECT_ROOT/.fvm/flutter_sdk/bin/flutter" ]]; then
    FLUTTER_CMD=("$PROJECT_ROOT/.fvm/flutter_sdk/bin/flutter")
  elif [[ -f "$PROJECT_ROOT/.fvmrc" || -f "$PROJECT_ROOT/.fvm/fvm_config.json" ]]; then
    error_echo '工程固定了 FVM，但 .fvm/flutter_sdk 尚不可用。请先恢复该 SDK，或显式指定 --flutter-sdk；入口不自动下载 SDK。'
    return 1
  elif command -v flutter >/dev/null 2>&1; then
    FLUTTER_CMD=("${commands[flutter]:A}")
  else
    error_echo '没有 Flutter SDK。请用 --flutter-sdk 或 FLUTTER_OHOS_SDK 指定鸿蒙适配版 SDK 根目录。'
    return 1
  fi
  info_echo "Flutter 命令：${(j: :)FLUTTER_CMD}"
}
# 仅配置本进程的 DevEco 路径，保留显式 SDK 和 Java 设置。
prepare_deveco_environment() {
  local candidate="" requested="${DEVECO_STUDIO_HOME:-${TOOL_HOME:-}}"
  local -a candidates=()
  if [[ -z "${DEVECO_SDK_HOME:-}" && -n "${HOS_SDK_HOME:-}" ]]; then
    export DEVECO_SDK_HOME="$HOS_SDK_HOME"
  fi
  if [[ -n "$requested" ]]; then
    requested="$(normalize_input_path "$requested")"
    [[ -d "$requested/Contents" ]] && requested="$requested/Contents"
    [[ -d "$requested" ]] || { error_echo "DevEco 路径不存在：$requested"; return 1; }
    DEVECO_CONTENTS="$requested"
  elif [[ -z "${DEVECO_SDK_HOME:-}" ]]; then
    for candidate in /Applications/DevEco*.app/Contents(N) "$HOME"/Applications/DevEco*.app/Contents(N); do
      [[ -d "$candidate/sdk" ]] && candidates+=("$candidate")
    done
    if (( ${#candidates[@]} == 1 )); then
      DEVECO_CONTENTS="${candidates[1]}"
    elif (( ${#candidates[@]} > 1 )); then
      error_echo '发现多个 DevEco Studio，请用 DEVECO_STUDIO_HOME 明确选择。'
      return 1
    fi
  fi
  if [[ -n "$DEVECO_CONTENTS" ]]; then
    export TOOL_HOME="$DEVECO_CONTENTS"
    [[ -n "${DEVECO_SDK_HOME:-}" ]] || export DEVECO_SDK_HOME="$DEVECO_CONTENTS/sdk"
    export PATH="$DEVECO_CONTENTS/tools/node/bin:$DEVECO_CONTENTS/tools/ohpm/bin:$DEVECO_CONTENTS/tools/hvigor/bin:$DEVECO_CONTENTS/tool/node/bin:$DEVECO_CONTENTS/ohpm/bin:$DEVECO_CONTENTS/hvigor/bin:$PATH"
    if [[ -z "${JAVA_HOME:-}" && -x "$DEVECO_CONTENTS/jbr/Contents/Home/bin/java" ]]; then
      export JAVA_HOME="$DEVECO_CONTENTS/jbr/Contents/Home"
    fi
  fi
  if [[ -n "${JAVA_HOME:-}" ]]; then
    [[ -x "$JAVA_HOME/bin/java" ]] || { error_echo "JAVA_HOME 没有可执行 bin/java：$JAVA_HOME"; return 1; }
    export PATH="$JAVA_HOME/bin:$PATH"
  fi
  if [[ -n "${NODE_HOME:-}" ]]; then
    [[ -x "$NODE_HOME/bin/node" ]] || { error_echo "NODE_HOME 没有可执行 bin/node：$NODE_HOME"; return 1; }
    export PATH="$NODE_HOME/bin:$PATH"
  fi
  rehash
  [[ -n "${DEVECO_SDK_HOME:-}" && -d "$DEVECO_SDK_HOME" ]] || {
    error_echo '没有有效 DEVECO_SDK_HOME。请先准备 DevEco Studio / HarmonyOS SDK；不将 OHOS_SDK_HOME 当作同义路径。'
    return 1
  }
  info_echo "HarmonyOS SDK：$DEVECO_SDK_HOME"
}
# 外部输出同步过滤和落盘，启用 PIPE_FAIL 后任何阶段失败均会停止。
run_step() {
  local title="$1" command_ec=0
  shift
  info_echo "开始：$title" || return 1
  if "$@" 2>&1 | strip_ansi_stream | /usr/bin/tee -a "$LOG_FILE"; then
    success_echo "完成：$title"
  else
    command_ec=$?
    error_echo "$title 失败，退出码 $command_ec；日志：$LOG_FILE"
    return "$command_ec"
  fi
}
# 验证实际命令可执行，不安装或升级工程工具链。
check_build_toolchain() {
  local tool=""
  for tool in node npm ohpm java; do
    command -v "$tool" >/dev/null 2>&1 || { error_echo "缺少 $tool，请检查 DevEco 工具目录和 PATH。"; return 1; }
  done
  run_step 'Node.js 健康检查' node --version || return $?
  run_step 'npm 健康检查' npm --version || return $?
  run_step 'ohpm 健康检查' ohpm --version || return $?
  run_step 'Java 健康检查' java -version || return $?
  if command -v hvigorw >/dev/null 2>&1; then
    run_step 'Hvigor 健康检查' hvigorw --version || return $?
  else
    error_echo '缺少 hvigorw，请把 DevEco tools/hvigor/bin 加入 PATH。'
    return 1
  fi
  run_step 'Flutter 健康检查' "${FLUTTER_CMD[@]}" --version || return $?
  local target="" help_text=""
  for target in "${BUILD_TARGETS[@]}"; do
    if ! help_text="$("${FLUTTER_CMD[@]}" build "$target" --help 2>&1)"; then
      log "$help_text"
      error_echo "此 SDK 不支持 flutter build $target，请切换匹配工程的鸿蒙适配版 SDK。"
      return 1
    fi
    if ! print -r -- "$help_text" | /usr/bin/grep -Fq "flutter build $target"; then
      error_echo "未确认 flutter build $target 能力；当前 SDK 可能是普通 Android / iOS 版本。"
      return 1
    fi
  done
}
# 从 Flutter 汇总目录和 DevEco 模块输出目录收集实际产物。
report_build_outputs() {
  local target="$1" output_root="" artifact="" found=0
  local -a artifacts=()
  OUTPUT_ROOTS=("$PROJECT_ROOT/build/ohos" "$PROJECT_ROOT/ohos/build")
  for output_root in "$PROJECT_ROOT"/ohos/*/build(N/); do
    OUTPUT_ROOTS+=("$output_root")
  done
  for output_root in "${OUTPUT_ROOTS[@]}"; do
    [[ -d "$output_root" ]] || continue
    while IFS= read -r -d '' artifact; do
      [[ -s "$artifact" ]] || continue
      artifacts+=("$artifact")
    done < <(/usr/bin/find "$output_root" \( -type d \( -name node_modules -o -name intermediates \) -prune \) -o \( -type f -name "*.$target" \( -path '*/outputs/*' -o -path '*/build/ohos/*' \) -print0 \))
  done
  for artifact in "${artifacts[@]}"; do
    found=1
    if [[ "$artifact" == *-unsigned.* ]]; then
      warn_echo "未签名产物：$artifact；安装或上架前必须完成对应签名。"
    else
      success_echo "产物：$artifact"
    fi
  done
  (( found == 1 )) || { error_echo "构建命令结束，但未发现非空 .$target 产物。"; return 1; }
  if [[ "${OPEN_AFTER_BUILD:-1}" == 1 ]]; then
    /usr/bin/open -R "${artifacts[1]}" 2>/dev/null || warn_echo "无法在 Finder 定位：${artifacts[1]}"
  fi
}
# 全部前置检查通过后，按顺序解析依赖和构建所选包型。
run_build_flow() {
  parse_build_options "$@" || return $?
  resolve_flutter_project || return $?
  choose_flutter_sdk || return $?
  prepare_deveco_environment || return $?
  check_build_toolchain || return $?
  info_echo '依赖来源：沿用工程 pubspec.yaml / 锁文件和当前 Pub、ohpm 软件源配置。'
  run_step 'flutter pub get' "${FLUTTER_CMD[@]}" pub get || return $?
  local target=""
  for target in "${BUILD_TARGETS[@]}"; do
    run_step "flutter build $target --$BUILD_MODE" "${FLUTTER_CMD[@]}" build "$target" "--$BUILD_MODE" || return $?
    report_build_outputs "$target" || return $?
  done
  success_echo "鸿蒙构建结束；构建与签名是否满足发布要求需结合工程配置核对。日志：$LOG_FILE"
}
# 保留失败退出码，避免尾部日志掩盖构建错误。
run_checked_build() {
  local build_ec=0
  if run_build_flow "$@"; then
    return 0
  else
    build_ec=$?
    error_echo "脚本已停止，退出码 $build_ec。日志：$LOG_FILE"
    exit "$build_ec"
  fi
}
# 以唯一入口编排确认、初始化和构建。
main() {
  show_script_intro_and_wait # 先打印固定自述，终端确认后继续。
  initialize_script_runtime # 确认后准备当前进程环境和纯文本日志。
  run_checked_build "$@" # 检查工具链并构建，失败保留退出码。
}

main "$@"
