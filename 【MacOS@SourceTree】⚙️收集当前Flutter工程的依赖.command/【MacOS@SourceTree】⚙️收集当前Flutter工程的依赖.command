#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】⚙️收集当前Flutter工程的依赖.command
# - 核心用途：从 Sourcetree 传入的仓库目录收集 Flutter / Dart 工程依赖，并在桌面生成 Zip 压缩包。
# - 影响范围：读取工程依赖、复制依赖源码到临时目录、在桌面生成压缩包；默认不修改工程依赖。
# - 运行提示：Sourcetree 模式无交互连续执行；终端模式会先确认，可按参数启用 fzf 多选或 flutter pub get。
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
readonly SCRIPT_SOURCE="$0"
LOG_READY=0
SCRIPT_PATH=""
SCRIPT_DIR=""
SCRIPT_BASENAME=""
LOG_FILE=""

IS_SOURCETREE_RUNTIME=0
SOURCETREE_PLAIN_OUTPUT=0
SELECT_MODE=0
RUN_PUB_GET=0
INPUT_PROJECT=""
PROJECT_ROOT=""
PROJECT_NAME=""
FLUTTER_CMD=()
PACKAGE_CONFIG=""
ZIP_PATH=""
TMP_PARENT=""
STAGE_NAME=""
STAGE=""
ALL_DEPS_TSV=""
SELECTED_DEPS_TSV=""
TOTAL_COUNT=0
SELECTED_COUNT=0
# 按脚本源码路径和标准目录解析真实入口文件。
resolve_script_path() {
  local script_source="$SCRIPT_SOURCE"
  local script_name="${SCRIPT_SOURCE:t}"
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
# 在用户确认后初始化 Shell、当前进程 PATH 和日志。
initialize_script_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  export PATH="$HOME/.pub-cache/bin:$HOME/.fvm/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
  prepare_plain_output_context
  : > "$LOG_FILE" || { print -r -- "日志不可写：$LOG_FILE" >&2; exit 1; }
  LOG_READY=1
}
# 处理当前步骤并向调用方返回执行结果。
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
# 在第一屏输出前确定纯文本模式，确认后再重复初始化输出环境。
prepare_plain_output_context() {
  SOURCETREE_PLAIN_OUTPUT=0
  PLAIN_OUTPUT=0
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == 1 || ! -t 1 || -z "${TERM:-}" || "${TERM:-}" == dumb || -n "${NO_COLOR+x}" || "${JOBS_PLAIN_OUTPUT:-0}" == 1 ]]; then
    SOURCETREE_PLAIN_OUTPUT=1
    PLAIN_OUTPUT=1
    export NO_COLOR=1 FORCE_COLOR=0 CLICOLOR=0 ANSI_COLORS_DISABLED=1 npm_config_color=false
  fi
}
# 只准备自述所需路径和入口身份，尚不创建日志或执行工程操作。
prepare_script_metadata() {
  SCRIPT_PATH="$(resolve_script_path)"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
  IS_SOURCETREE_RUNTIME=0
  if is_sourcetree_runtime; then
    IS_SOURCETREE_RUNTIME=1
  fi
  prepare_plain_output_context
}
# 处理当前步骤并向调用方返回执行结果。
strip_ansi_text() {
  perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}
# 确认前仅显示文字，确认后将同一输出同步写入日志。
write_log_output() {
  if [[ "${LOG_READY:-0}" == 1 ]]; then
    tee -a "$LOG_FILE"
  else
    cat
  fi
}
# 保留路径和命令中的字面反斜杠，只过滤展示用 ANSI 控制码。
log() {
  if [[ "${SOURCETREE_PLAIN_OUTPUT:-0}" == 1 ]]; then
    printf '%s\n' "$1" | strip_ansi_text | write_log_output
  else
    printf '%s\n' "$1" | write_log_output
  fi
}
# 颜色只作用于日志样式，正文始终按字面文字输出。
color_log() {
  if [[ "${SOURCETREE_PLAIN_OUTPUT:-0}" == 1 ]]; then
    log "$2"
  else
    log "$(printf '%b%s%b' "$1" "$2" '\033[0m')"
  fi
}
# 输出一般完成信息。
color_echo() { color_log '\033[1;32m' "$1"; }
# 输出步骤与环境信息。
info_echo() { color_log '\033[1;34m' "ℹ $1"; }
# 输出已完成步骤。
success_echo() { color_log '\033[1;32m' "✔ $1"; }
# 输出需要关注的风险。
warn_echo() { color_log '\033[1;33m' "⚠ $1"; }
# 输出温馨提示。
warm_echo() { color_log '\033[1;33m' "$1"; }
# 输出操作说明。
note_echo() { color_log '\033[1;35m' "➤ $1"; }
# 输出带前缀的错误信息。
error_echo() { color_log '\033[1;31m' "✖ $1"; }
# 输出错误正文。
err_echo() { color_log '\033[1;31m' "$1"; }
# 输出诊断信息。
debug_echo() { color_log '\033[1;35m' "🐞 $1"; }
# 输出展示重点。
highlight_echo() { color_log '\033[1;36m' "🔹 $1"; }
# 输出次要信息。
gray_echo() { color_log '\033[0;90m' "$1"; }
# 输出加粗信息。
bold_echo() { color_log '\033[1m' "$1"; }
# 输出带下划线的信息。
underline_echo() { color_log '\033[4m' "$1"; }
# 报告阻塞错误并结束当前脚本。
fail() {
  error_echo "$1"
  exit 1
}
# 处理当前步骤并向调用方返回执行结果。
show_script_intro_and_wait() {
  prepare_script_metadata
  if [[ -z "${NO_COLOR+x}" && "${IS_SOURCETREE_RUNTIME:-0}" != "1" && -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" && "${PLAIN_OUTPUT:-0}" != 1 ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 ==============================" | jobs_intro_style title
  note_echo "脚本名称：${SCRIPT_BASENAME}.command" | jobs_intro_style title
  note_echo "脚本路径：${SCRIPT_PATH}" | jobs_intro_style body
  note_echo "核心用途：收集当前 Flutter / Dart 工程依赖源码、原生依赖和关键清单，并在桌面生成 Zip。" | jobs_intro_style body
  warn_echo "影响范围：默认只读取工程和复制文件到临时目录、桌面压缩包；终端模式使用 --pub-get 才会执行 flutter pub get。" | jobs_intro_style body
  note_echo "SourceTree：读取传入的 \$REPO 参数，无交互连续执行，默认不启用 fzf 多选。" | jobs_intro_style body
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
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _ || exit 1
}
# 展示可用参数和调用方式。
usage() {
  cat <<'USAGE'
用法：
  ./【MacOS@SourceTree】⚙️收集当前Flutter工程的依赖.command /path/to/app
  ./【MacOS@SourceTree】⚙️收集当前Flutter工程的依赖.command --select /path/to/app
  ./【MacOS@SourceTree】⚙️收集当前Flutter工程的依赖.command --pub-get /path/to/app
  ./【MacOS@SourceTree】⚙️收集当前Flutter工程的依赖.command --no-pub-get /path/to/app

参数：
  -s, --select       使用 fzf 多选 Dart / Flutter 依赖，仅建议终端模式使用
  --pub-get          执行 flutter pub get 刷新依赖解析文件
  --no-pub-get       不执行 flutter pub get，直接使用现有解析文件
  -h, --help         显示帮助
USAGE
}
# 校验依赖收集参数并应用 Sourcetree 无交互策略。
parse_arguments() {
  while (( $# > 0 )); do
    case "$1" in
      -s|--select)
        SELECT_MODE=1
        shift
        ;;
      --pub-get)
        RUN_PUB_GET=1
        shift
        ;;
      --no-pub-get)
        RUN_PUB_GET=0
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        [[ $# -le 1 ]] || fail "-- 后只能传入一个 Flutter 项目路径。"
        [[ $# -eq 0 ]] || INPUT_PROJECT="$1"
        break
        ;;
      -*)
        fail "不支持的参数：$1（可使用 --help 查看帮助）"
        ;;
      *)
        [[ -z "$INPUT_PROJECT" ]] || fail "参数过多：$1"
        INPUT_PROJECT="$1"
        shift
        ;;
    esac
  done

  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" && "${SELECT_MODE}" -eq 1 ]]; then
    warn_echo "Sourcetree 连续执行模式不启用 fzf 多选，已改为全量收集依赖。"
    SELECT_MODE=0
  fi
}
# 解除拖入路径的外层引号和转义。
normalize_input_path() {
  local path_value="$1"
  if [[ -e "$path_value" ]]; then
    print -r -- "$path_value"
    return 0
  fi
  path_value="${path_value%$'\r'}"
  path_value="${path_value%$'\n'}"
  path_value="${path_value#\"}"
  path_value="${path_value%\"}"
  path_value="${path_value#\'}"
  path_value="${path_value%\'}"
  [[ "$path_value" == '~/'* ]] && path_value="$HOME/${path_value#\~/}"
  path_value="$(printf "%s" "$path_value" | perl -pe 's/\\([ ()\[\]&;])/$1/g')"
  [[ "$path_value" == "/" ]] || path_value="${path_value%/}"
  print -r -- "$path_value"
}
# 从目标目录向上查找依赖清单。
find_pubspec_upwards() {
  local current_dir="$1"
  current_dir="$(cd "$current_dir" 2>/dev/null && pwd -P)" || return 1

  while true; do
    [[ -f "$current_dir/pubspec.yaml" ]] && { print -r -- "$current_dir"; return 0; }
    [[ "$current_dir" == "/" ]] && break
    current_dir="$(dirname "$current_dir")"
  done
  return 1
}
# 确认输入路径是否指向唯一可用的 Dart 工程。
resolve_project_root_from_input() {
  local input_path=""
  input_path="$(normalize_input_path "$1")"

  [[ -f "$input_path" && "$(basename "$input_path")" == "pubspec.yaml" ]] && input_path="$(dirname "$input_path")"
  if [[ -d "$input_path" && -f "$input_path/pubspec.yaml" ]]; then
    (cd "$input_path" && pwd -P)
    return 0
  fi
  if [[ -d "$input_path" ]]; then
    find_pubspec_upwards "$input_path"
    return $?
  fi
  return 1
}
# 接收并校验终端中拖入的工程路径。
assign_project_root_from_prompt() {
  local resolved_root=""
  resolved_root="$(ask_project_root_until_valid)" || return 1
  PROJECT_ROOT="$resolved_root"
}
# 仅在终端中等待一个有效工程路径。
ask_project_root_until_valid() {
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" ]]; then
    fail "Sourcetree 未传入合法 Flutter / Dart 工程目录，无法交互补录路径。"
  fi

  local raw_path=""
  local resolved_root=""
  while true; do
    echo "" >&2
    read -r "?没有自动找到 pubspec.yaml，请输入或拖入 Flutter 项目根目录：" raw_path
    if resolved_root="$(resolve_project_root_from_input "$raw_path")"; then
      print -r -- "$resolved_root"
      return 0
    fi
    warn_echo "该目录下没有 pubspec.yaml，请重新输入。" >&2
  done
}
# 先解析显式工程，必要时在终端请求输入。
resolve_project_root() {
  if [[ -n "$INPUT_PROJECT" ]]; then
    if PROJECT_ROOT="$(resolve_project_root_from_input "$INPUT_PROJECT")"; then
      return 0
    fi
    warn_echo "传入路径不是合法工程目录：$INPUT_PROJECT"
    if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" ]]; then
      fail "Sourcetree 传入路径中未找到 pubspec.yaml：$INPUT_PROJECT"
    fi
    assign_project_root_from_prompt
  elif PROJECT_ROOT="$(find_pubspec_upwards "$PWD")"; then
    return 0
  elif PROJECT_ROOT="$(find_pubspec_upwards "$SCRIPT_DIR")"; then
    return 0
  else
    assign_project_root_from_prompt
  fi
}
# 进入工程并准备项目名和依赖配置路径。
prepare_project_context() {
  cd "$PROJECT_ROOT" || fail "进入工程目录失败：$PROJECT_ROOT"
  PROJECT_NAME="$(basename "$PROJECT_ROOT")"
  PACKAGE_CONFIG="$PROJECT_ROOT/.dart_tool/package_config.json"
  info_echo "Flutter / Dart 工程根目录：$PROJECT_ROOT"

  if ! grep -Eq '^[[:space:]]*flutter:' "$PROJECT_ROOT/pubspec.yaml"; then
    warn_echo "pubspec.yaml 中未检测到 flutter: 配置，将按 Dart 工程继续处理。"
  fi
}
# 选择工程固定 SDK 或已有全局 Flutter。
resolve_flutter_command() {
  if [[ -x "$PROJECT_ROOT/.fvm/flutter_sdk/bin/flutter" ]]; then
    FLUTTER_CMD=("$PROJECT_ROOT/.fvm/flutter_sdk/bin/flutter")
    info_echo "使用项目内 FVM Flutter。"
  elif [[ -f "$PROJECT_ROOT/.fvmrc" || -f "$PROJECT_ROOT/.fvm/fvm_config.json" ]]; then
    command -v fvm >/dev/null 2>&1 || fail "工程固定了 FVM，但本地 SDK / fvm 不可用，请先恢复对应 SDK。"
    FLUTTER_CMD=(fvm flutter)
    info_echo "使用系统 FVM Flutter。"
  elif command -v flutter >/dev/null 2>&1; then
    FLUTTER_CMD=(flutter)
    info_echo "使用全局 Flutter。"
  else
    fail "未找到 Flutter。请先安装 Flutter 或把 flutter 加入 PATH。"
  fi
}
# 可选操作回车跳过，Sourcetree 不发起输入等待。
ask_any_to_run() {
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" ]]; then
    gray_echo "Sourcetree 连续执行模式不发起交互，已跳过：$1"
    return 1
  fi
  local answer=""
  read -r "?$1（直接回车跳过；输入任意字符后回车执行）：" answer
  [[ -n "$answer" ]]
}
# 仅按显式选项刷新依赖并检查解析文件。
prepare_package_config() {
  if (( RUN_PUB_GET == 1 )); then
    if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" ]]; then
      info_echo "按参数要求执行 flutter pub get..."
      "${FLUTTER_CMD[@]}" pub get 2>&1 | strip_ansi_text | tee -a "$LOG_FILE" || fail "flutter pub get 失败，停止收集。"
      success_echo "flutter pub get 执行完成。"
    elif ask_any_to_run "是否执行 flutter pub get 以刷新依赖解析文件？"; then
      info_echo "正在执行 flutter pub get..."
      "${FLUTTER_CMD[@]}" pub get 2>&1 | strip_ansi_text | tee -a "$LOG_FILE" || fail "flutter pub get 失败，停止收集。"
      success_echo "flutter pub get 执行完成。"
    else
      note_echo "已跳过 flutter pub get。"
    fi
  else
    note_echo "已按当前运行策略跳过 flutter pub get。"
  fi

  if [[ ! -f "$PACKAGE_CONFIG" ]]; then
    local workspace_parent="${PROJECT_ROOT:h}"
    while [[ "$workspace_parent" != / ]]; do
      if [[ -f "$workspace_parent/.dart_tool/package_config.json" && -f "$workspace_parent/pubspec.yaml" ]] &&
         grep -Eq '^[[:space:]]*workspace[[:space:]]*:' "$workspace_parent/pubspec.yaml"; then
        PACKAGE_CONFIG="$workspace_parent/.dart_tool/package_config.json"
        info_echo "使用工作区解析文件：$PACKAGE_CONFIG"
        break
      fi
      workspace_parent="${workspace_parent:h}"
    done
  fi
  [[ -f "$PACKAGE_CONFIG" && -r "$PACKAGE_CONFIG" ]] || fail "未找到 ${PACKAGE_CONFIG}。请先在工程中执行 flutter pub get。"
}
# 检查依赖解析、复制和归档工具。
check_environment() {
  command -v ruby >/dev/null 2>&1 || fail "未找到 Ruby，无法解析 package_config.json。"
  command -v rsync >/dev/null 2>&1 || fail "未找到 rsync，无法复制依赖目录。"
  command -v ditto >/dev/null 2>&1 || fail "未找到 macOS ditto，当前脚本仅支持 MacOS。"
  if (( SELECT_MODE == 1 )) && ! command -v fzf >/dev/null 2>&1; then
    fail "已启用 --select，但未找到 fzf；可先执行 brew install fzf。"
  fi
}
# 创建唯一输出路径和临时收集目录。
prepare_output_paths() {
  local timestamp="$(date +%Y%m%d_%H%M%S)"
  local desktop_path="$HOME/Desktop"
  mkdir -p "$desktop_path" || return $?

  ZIP_PATH="$desktop_path/${PROJECT_NAME}_flutter_deps_${timestamp}.zip"
  TMP_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/jobs_flutter_deps.XXXXXX")" || return $?
  ZIP_PATH="$desktop_path/${PROJECT_NAME}_flutter_deps_${timestamp}_${TMP_PARENT:t}.zip"
  STAGE_NAME="${PROJECT_NAME}_flutter_deps_${timestamp}"
  STAGE="$TMP_PARENT/$STAGE_NAME"
  ALL_DEPS_TSV="$STAGE/manifest/all_package_roots.tsv"
  SELECTED_DEPS_TSV="$STAGE/manifest/selected_package_roots.tsv"
  mkdir -p "$STAGE/manifest" "$STAGE/dart_packages" "$STAGE/native" "$STAGE/project_files" || { local setup_ec=$?; cleanup_temp_files; return "$setup_ec"; }
}
# 只清理本流程创建的独立收集目录。
cleanup_temp_files() {
  [[ -n "${TMP_PARENT:-}" && -d "$TMP_PARENT" && "$TMP_PARENT" == "${TMPDIR:-/tmp}"/jobs_flutter_deps.* ]] || return 0
  rm -rf -- "$TMP_PARENT"
}
# 安全解析实际包路径和包名。
extract_package_roots() {
  info_echo "正在解析 package_config.json..."
  ruby -rjson -ruri -e '
config = File.expand_path(ARGV[0])
project_root = File.expand_path(ARGV[1])
pub_cache = File.expand_path(ENV["PUB_CACHE"] || File.join(Dir.home, ".pub-cache"))
base_dir = File.dirname(config)
seen = {}
packages = JSON.parse(File.read(config)).fetch("packages")
abort("packages must be an array") unless packages.is_a?(Array)
packages.each do |pkg|
  name = pkg.fetch("name").to_s
  root_uri = pkg.fetch("rootUri").to_s
  abort("Invalid or duplicate package name: #{name}") unless name.match?(/\A[a-z][a-z0-9_]*\z/) && !seen[name]
  seen[name] = true
  begin
    uri = URI.parse(root_uri)
    abort("Unsupported package URI: #{root_uri}") unless uri.scheme.nil? || uri.scheme == "file"
    abort("Remote file URI is unsupported: #{root_uri}") if uri.scheme == "file" && ![nil, "", "localhost"].include?(uri.host)
    path = File.expand_path(URI::DEFAULT_PARSER.unescape(uri.path), base_dir)
  rescue URI::InvalidURIError
    path = File.expand_path(URI::DEFAULT_PARSER.unescape(root_uri), base_dir)
  end
  abort("Dependency path is missing: #{path}") unless File.directory?(path)
  next if path == project_root
  abort("Dependency path contains TSV delimiters") if path.match?(/[\t\r\n]/)
  type = if path.start_with?(pub_cache + "/")
           "pub-cache"
         elsif path.include?("/flutter/") || path.include?("/flutter_sdk/")
           "flutter-sdk"
         else
           "local-or-path"
         end
  puts [name, path, type].join("\t")
end
' "$PACKAGE_CONFIG" "$PROJECT_ROOT" | sort -u > "$ALL_DEPS_TSV" || fail "依赖解析失败，未生成可用清单。"

  TOTAL_COUNT="$(wc -l < "$ALL_DEPS_TSV" | tr -d ' ')"
  (( TOTAL_COUNT > 0 )) || fail "未从 package_config.json 提取到依赖包路径。"
  success_echo "共发现 ${TOTAL_COUNT} 个依赖包根目录。"
}
# 确定全量集合或终端 fzf 多选结果。
select_package_roots() {
  local selected_lines=""
  if (( SELECT_MODE == 1 )); then
    info_echo "进入 fzf 多选：Tab 选中，Enter 确认，Esc 取消。"
    selected_lines="$(fzf -m \
      --delimiter=$'\t' \
      --with-nth=1,3,2 \
      --header='Tab 多选依赖；Enter 确认；Esc 取消' \
      --preview='printf "%s\n" {} | awk -F"\t" '\''{print "name: " $1 "\ntype: " $3 "\npath: " $2}'\''' \
      < "$ALL_DEPS_TSV" || true)"
    [[ -n "$selected_lines" ]] || fail "没有选择任何依赖，已取消。"
    print -r -- "$selected_lines" > "$SELECTED_DEPS_TSV" || return $?
  else
    cp -p "$ALL_DEPS_TSV" "$SELECTED_DEPS_TSV" || return $?
  fi

  SELECTED_COUNT="$(wc -l < "$SELECTED_DEPS_TSV" | tr -d ' ')"
  info_echo "本次将打包 ${SELECTED_COUNT} 个 Dart / Flutter 依赖。"
}
# 复制一个依赖目录并保留命令失败。
copy_dir() {
  local source_dir="$1"
  local target_dir="$2"
  mkdir -p "$(dirname "$target_dir")" || return $?
  rsync -a \
    --exclude='.git/' \
    --exclude='node_modules/' \
    --exclude='Pods/.git/' \
    --exclude='.dart_tool/' \
    --exclude='build/' \
    --exclude='DerivedData/' \
    --exclude='.packages' \
    "$source_dir/" "$target_dir/"
}
# 复制存在的清单文件，缺失可选项保持跳过。
copy_file_if_exists() {
  local source_file="$1"
  local target_file="$2"
  [[ -f "$source_file" ]] || return 0
  mkdir -p "$(dirname "$target_file")" || return $?
  cp -p "$source_file" "$target_file"
}
# 复制存在的原生依赖目录。
copy_dir_if_exists() {
  local source_dir="$1"
  local target_dir="$2"
  [[ -d "$source_dir" ]] || return 0
  info_echo "复制原生依赖目录：${source_dir#$PROJECT_ROOT/}"
  copy_dir "$source_dir" "$target_dir" || return $?
}
# 按工程相对路径保存关键清单。
copy_project_file_rel() {
  local source_file="$1"
  [[ -f "$source_file" ]] || return 0
  local relative_path="${source_file#$PROJECT_ROOT/}"
  copy_file_if_exists "$source_file" "$STAGE/project_files/$relative_path" || return $?
}
# 复制选中依赖并记录来源映射。
copy_dart_packages() {
  local copied_manifest="$STAGE/manifest/copied_package_roots.tsv"
  local package_name=""
  local package_path=""
  local package_type=""
  local safe_name=""
  local target_dir=""
  : > "$copied_manifest" || return $?

  while IFS=$'\t' read -r package_name package_path package_type; do
    [[ -n "$package_name" && -d "$package_path" ]] || fail "依赖目录在复制前消失：$package_path"
    safe_name="$(print -rn -- "$package_name" | tr -c 'A-Za-z0-9._-' '_')"
    target_dir="$STAGE/dart_packages/$safe_name"
    info_echo "复制依赖：$package_name"
    copy_dir "$package_path" "$target_dir" || return $?
    printf '%s\t%s\t%s\t%s\n' "$package_name" "$package_path" "$package_type" "dart_packages/$safe_name" >> "$copied_manifest" || return $?
  done < "$SELECTED_DEPS_TSV"
}
# 收集原生依赖和锁定配置。
copy_project_dependency_files() {
  local search_root=""
  local found_file=""

  copy_project_file_rel "$PROJECT_ROOT/pubspec.yaml" || return $?
  copy_project_file_rel "$PROJECT_ROOT/pubspec.lock" || return $?
  copy_project_file_rel "$PROJECT_ROOT/.metadata" || return $?
  copy_project_file_rel "$PROJECT_ROOT/analysis_options.yaml" || return $?
  copy_file_if_exists "$PACKAGE_CONFIG" "$STAGE/project_files/.dart_tool/package_config.json" || return $?
  if [[ "$PACKAGE_CONFIG" != "$PROJECT_ROOT/.dart_tool/package_config.json" ]]; then
    copy_file_if_exists "${PACKAGE_CONFIG:h:h}/pubspec.yaml" "$STAGE/manifest/workspace_pubspec.yaml" || return $?
  fi
  copy_project_file_rel "$PROJECT_ROOT/.dart_tool/package_graph.json" || return $?
  copy_project_file_rel "$PROJECT_ROOT/ios/Podfile" || return $?
  copy_project_file_rel "$PROJECT_ROOT/ios/Podfile.lock" || return $?
  copy_project_file_rel "$PROJECT_ROOT/macos/Podfile" || return $?
  copy_project_file_rel "$PROJECT_ROOT/macos/Podfile.lock" || return $?

  copy_dir_if_exists "$PROJECT_ROOT/ios/Pods" "$STAGE/native/ios/Pods" || return $?
  copy_dir_if_exists "$PROJECT_ROOT/macos/Pods" "$STAGE/native/macos/Pods" || return $?
  copy_dir_if_exists "$PROJECT_ROOT/ios/.symlinks" "$STAGE/native/ios/.symlinks" || return $?
  copy_dir_if_exists "$PROJECT_ROOT/macos/.symlinks" "$STAGE/native/macos/.symlinks" || return $?
  copy_dir_if_exists "$PROJECT_ROOT/build/ios/SwiftPackages" "$STAGE/native/ios/SwiftPackages" || return $?
  copy_dir_if_exists "$PROJECT_ROOT/build/macos/SwiftPackages" "$STAGE/native/macos/SwiftPackages" || return $?

  for search_root in "$PROJECT_ROOT/ios" "$PROJECT_ROOT/macos"; do
    [[ -d "$search_root" ]] || continue
    while IFS= read -r -d '' found_file; do
      copy_project_file_rel "$found_file" || return $?
    done < <(find "$search_root" \( -type d \( -name .git -o -name Pods -o -name .dart_tool -o -name build -o -name DerivedData -o -name node_modules \) -prune \) -o -name 'Package.resolved' -type f -print0 2>/dev/null)
  done

  if [[ -d "$PROJECT_ROOT/android" ]]; then
    while IFS= read -r -d '' found_file; do
      copy_project_file_rel "$found_file" || return $?
    done < <(find "$PROJECT_ROOT/android" \( -type d \( -name .git -o -name build -o -name .gradle -o -name node_modules \) -prune \) -o \( \
      -name 'build.gradle' -o \
      -name 'build.gradle.kts' -o \
      -name 'settings.gradle' -o \
      -name 'settings.gradle.kts' -o \
      -name 'gradle.properties' -o \
      -name 'libs.versions.toml' \
    \) -type f -print0 2>/dev/null)
  fi
}
# 写入归档说明和只读依赖诊断信息。
write_package_manifest() {
  {
    echo "Project name: $PROJECT_NAME"
    echo "Project root: $PROJECT_ROOT"
    echo "Created at: $(date)"
    echo "Sourcetree runtime: $IS_SOURCETREE_RUNTIME"
    echo "Select mode: $SELECT_MODE"
    echo "Run pub get: $RUN_PUB_GET"
    echo "Package config: $PACKAGE_CONFIG"
    echo "Selected packages: $SELECTED_COUNT / $TOTAL_COUNT"
    echo "Zip path: $ZIP_PATH"
  } > "$STAGE/manifest/project_info.txt" || return $?

  ("${FLUTTER_CMD[@]}" --version || true) > "$STAGE/manifest/flutter_version.txt" 2>&1 || return $?
  ("${FLUTTER_CMD[@]}" pub deps --style=compact || true) > "$STAGE/manifest/flutter_pub_deps_compact.txt" 2>&1 || return $?

  cat > "$STAGE/README.txt" <<'README' || return $?
目录说明：
- dart_packages/：package_config.json 实际解析到的 Dart / Flutter 包源码。
- native/：工程现有的 CocoaPods、旧版插件 symlink 和 SwiftPM 输出。
- project_files/：pubspec、Podfile.lock、Package.resolved、Gradle 声明等文件。
- manifest/：依赖清单、Flutter 版本、pub deps 输出与复制路径映射。

注意：
1. Sourcetree 默认模式不执行 flutter pub get，直接使用工程现有 package_config.json。
2. 不复制整个 ~/.gradle/caches，避免压缩包体积失控。
3. Pods 不存在时不会自动执行 pod install。
4. --select 只筛选 Dart / Flutter 包，原生依赖仍按工程现状复制。
README
}
# 生成并核对最终压缩包。
create_zip_archive() {
  local zip_size=""
  info_echo "开始压缩到桌面：$ZIP_PATH"
  (cd "$TMP_PARENT" && ditto -c -k --sequesterRsrc --keepParent "$STAGE_NAME" "$ZIP_PATH") || return $?
  [[ -f "$ZIP_PATH" ]] || fail "压缩失败：$ZIP_PATH"
  zip_size="$(du -h "$ZIP_PATH" | awk '{print $1}')"
  success_echo "打包完成：$ZIP_PATH"
  success_echo "压缩包大小：$zip_size"
  gray_echo "执行日志：$LOG_FILE"
}
# 覆盖依赖复制和归档的完整生命周期。
run_main_flow() {
  parse_arguments "$@" || return $? # 解析参数且 Sourcetree 模式不启用交互选择。
  resolve_project_root || return $? # 唯一定位传入的 Flutter / Dart 工程。
  prepare_project_context || return $? # 进入工程并准备项目依赖上下文。
  check_environment || return $? # 检查归档和依赖解析工具。
  resolve_flutter_command || return $? # 复用工程指定的 Flutter SDK。
  prepare_package_config || return $? # 按显式选项更新并检查依赖解析文件。
  prepare_output_paths || return $? # 创建独立的临时收集目录和输出路径。
  trap cleanup_temp_files EXIT # EXIT 生命周期覆盖后续复制和压缩，失败也清理独立临时目录。
  extract_package_roots || return $? # 读取实际解析到的包路径。
  select_package_roots || return $? # 确定全量或终端多选的包集合。
  copy_dart_packages || return $? # 复制实际依赖源码。
  copy_project_dependency_files || return $? # 复制原生依赖和工程清单。
  write_package_manifest || return $? # 写入可追溯的依赖与工程说明。
  create_zip_archive || return $? # 生成桌面压缩包并核对输出。
}
# 保留收集全流程退出码，确保入口不会把失败当作成功。
run_checked_collection() {
  local collection_ec=0
  if run_main_flow "$@"; then
    return 0
  else
    collection_ec=$?
    error_echo "依赖收集失败，退出码：$collection_ec。日志：$LOG_FILE"
    exit "$collection_ec"
  fi
}
# 在确认后执行依赖收集，并让临时目录清理覆盖整个复制归档流程。
main() {
  show_script_intro_and_wait # 打印内置自述，终端模式确认后继续。
  initialize_script_runtime # 确认后准备当前进程环境并创建日志。
  run_checked_collection "$@" # 收集实际解析的依赖，失败停止并保留退出码。
}

main "$@"
