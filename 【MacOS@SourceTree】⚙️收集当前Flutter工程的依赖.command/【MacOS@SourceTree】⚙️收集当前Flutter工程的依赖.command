#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】⚙️收集当前Flutter工程的依赖.command
# - 核心用途：从 Sourcetree 传入的仓库目录收集 Flutter / Dart 工程依赖，并在桌面生成 Zip 压缩包。
# - 影响范围：读取工程依赖、复制依赖源码到临时目录、在桌面生成压缩包；默认不修改工程依赖。
# - 运行提示：Sourcetree 模式无交互连续执行；终端模式会先确认，可按参数启用 fzf 多选或 flutter pub get。

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

initialize_script_runtime() {
  setopt NO_NOMATCH

  SCRIPT_PATH="$(resolve_script_path)"
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd -P)"
  SCRIPT_BASENAME="$(basename "$SCRIPT_PATH" | sed 's/\.[^.]*$//')"
  LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
  : > "$LOG_FILE"

  [[ -n "${TERM:-}" ]] || export TERM="dumb"
  if is_sourcetree_runtime; then
    IS_SOURCETREE_RUNTIME=1
    RUN_PUB_GET=0
  else
    IS_SOURCETREE_RUNTIME=0
    RUN_PUB_GET=1
  fi

  if [[ "" == "1" || ! -t 1 || "" == "dumb" || -n "${NO_COLOR:-}" || "${JOBS_PLAIN_OUTPUT:-0}" == "1" ]]; then
    SOURCETREE_PLAIN_OUTPUT=1
    export NO_COLOR="${NO_COLOR:-1}"
    export FORCE_COLOR=0
    export CLICOLOR="0"
    export ANSI_COLORS_DISABLED="1"
    export npm_config_color=false
  else
    SOURCETREE_PLAIN_OUTPUT=0
  fi
}

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

strip_ansi_text() {
  perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}

log() {
  if [[ "${SOURCETREE_PLAIN_OUTPUT:-0}" == "1" ]]; then
    printf "%b\n" "$1" | strip_ansi_text | tee -a "$LOG_FILE"
  else
    printf "%b\n" "$1" | tee -a "$LOG_FILE"
  fi
}
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

fail() {
  error_echo "$1"
  exit 1
}

show_script_intro_and_wait() {
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" != "1" && -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 =============================="
  note_echo "脚本名称：${SCRIPT_BASENAME}.command"
  note_echo "脚本路径：${SCRIPT_PATH}"
  note_echo "核心用途：收集当前 Flutter / Dart 工程依赖源码、原生依赖和关键清单，并在桌面生成 Zip。"
  warn_echo "影响范围：默认只读取工程和复制文件到临时目录、桌面压缩包；终端模式使用 --pub-get 才会执行 flutter pub get。"
  note_echo "SourceTree：读取传入的 \$REPO 参数，无交互连续执行，默认不启用 fzf 多选。"
  gray_echo "日志文件：${LOG_FILE}"
  highlight_echo "======================================================================="
  echo ""

  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" ]]; then
    gray_echo "已识别为 Sourcetree 自定义动作，将跳过交互并连续执行。"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    fail "当前不是 Sourcetree，且没有可交互输入；请在终端中重新运行。"
  fi
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}

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

normalize_input_path() {
  local path_value="$1"
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

assign_project_root_from_prompt() {
  local resolved_root=""
  resolved_root="$(ask_project_root_until_valid)" || return 1
  PROJECT_ROOT="$resolved_root"
}

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

prepare_project_context() {
  cd "$PROJECT_ROOT" || fail "进入工程目录失败：$PROJECT_ROOT"
  PROJECT_NAME="$(basename "$PROJECT_ROOT")"
  PACKAGE_CONFIG="$PROJECT_ROOT/.dart_tool/package_config.json"
  info_echo "Flutter / Dart 工程根目录：$PROJECT_ROOT"

  if ! grep -Eq '^[[:space:]]*flutter:' "$PROJECT_ROOT/pubspec.yaml"; then
    warn_echo "pubspec.yaml 中未检测到 flutter: 配置，将按 Dart 工程继续处理。"
  fi
}

resolve_flutter_command() {
  if [[ -x "$PROJECT_ROOT/.fvm/flutter_sdk/bin/flutter" ]]; then
    FLUTTER_CMD=("$PROJECT_ROOT/.fvm/flutter_sdk/bin/flutter")
    info_echo "使用项目内 FVM Flutter。"
  elif command -v fvm >/dev/null 2>&1 && { [[ -f "$PROJECT_ROOT/.fvmrc" ]] || [[ -d "$PROJECT_ROOT/.fvm" ]]; }; then
    FLUTTER_CMD=(fvm flutter)
    info_echo "使用系统 FVM Flutter。"
  elif command -v flutter >/dev/null 2>&1; then
    FLUTTER_CMD=(flutter)
    info_echo "使用全局 Flutter。"
  else
    fail "未找到 Flutter。请先安装 Flutter 或把 flutter 加入 PATH。"
  fi
}

ask_any_to_run() {
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" ]]; then
    gray_echo "Sourcetree 连续执行模式不发起交互，已跳过：$1"
    return 1
  fi
  local answer=""
  read -r "?$1（直接回车跳过；输入任意字符后回车执行）：" answer
  [[ -n "$answer" ]]
}

prepare_package_config() {
  if (( RUN_PUB_GET == 1 )); then
    if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" ]]; then
      info_echo "按参数要求执行 flutter pub get..."
      "${FLUTTER_CMD[@]}" pub get 2>&1 | tee -a "$LOG_FILE"
      success_echo "flutter pub get 执行完成。"
    elif ask_any_to_run "是否执行 flutter pub get 以刷新依赖解析文件？"; then
      info_echo "正在执行 flutter pub get..."
      "${FLUTTER_CMD[@]}" pub get 2>&1 | tee -a "$LOG_FILE"
      success_echo "flutter pub get 执行完成。"
    else
      note_echo "已跳过 flutter pub get。"
    fi
  else
    note_echo "已按当前运行策略跳过 flutter pub get。"
  fi

  [[ -f "$PACKAGE_CONFIG" ]] || fail "未找到 ${PACKAGE_CONFIG}。请先在工程中执行 flutter pub get。"
}

check_environment() {
  command -v ruby >/dev/null 2>&1 || fail "未找到 Ruby，无法解析 package_config.json。"
  command -v rsync >/dev/null 2>&1 || fail "未找到 rsync，无法复制依赖目录。"
  command -v ditto >/dev/null 2>&1 || fail "未找到 macOS ditto，当前脚本仅支持 MacOS。"
  if (( SELECT_MODE == 1 )) && ! command -v fzf >/dev/null 2>&1; then
    fail "已启用 --select，但未找到 fzf；可先执行 brew install fzf。"
  fi
}

prepare_output_paths() {
  local timestamp="$(date +%Y%m%d_%H%M%S)"
  local desktop_path="$HOME/Desktop"
  mkdir -p "$desktop_path"

  ZIP_PATH="$desktop_path/${PROJECT_NAME}_flutter_deps_${timestamp}.zip"
  TMP_PARENT="$(mktemp -d "/tmp/${PROJECT_NAME}_flutter_deps_${timestamp}.XXXXXX")"
  STAGE_NAME="${PROJECT_NAME}_flutter_deps_${timestamp}"
  STAGE="$TMP_PARENT/$STAGE_NAME"
  ALL_DEPS_TSV="$STAGE/manifest/all_package_roots.tsv"
  SELECTED_DEPS_TSV="$STAGE/manifest/selected_package_roots.tsv"
  mkdir -p "$STAGE/manifest" "$STAGE/dart_packages" "$STAGE/native" "$STAGE/project_files"
}

cleanup_temp_files() {
  [[ -n "${TMP_PARENT:-}" && -d "$TMP_PARENT" && "$TMP_PARENT" == /tmp/* ]] || return 0
  rm -rf -- "$TMP_PARENT"
}

extract_package_roots() {
  info_echo "正在解析 package_config.json..."
  ruby -rjson -ruri -e '
config = File.expand_path(ARGV[0])
project_root = File.expand_path(ARGV[1])
pub_cache = File.expand_path(ENV["PUB_CACHE"] || File.join(Dir.home, ".pub-cache"))
base_dir = File.dirname(config)
base_uri = "file://#{base_dir}/"

JSON.parse(File.read(config)).fetch("packages", []).each do |pkg|
  name = pkg["name"].to_s
  root_uri = pkg["rootUri"].to_s
  next if name.empty? || root_uri.empty?

  begin
    uri = URI.parse(root_uri)
    if uri.scheme.nil?
      path = URI::DEFAULT_PARSER.unescape(URI.join(base_uri, root_uri).path)
    elsif uri.scheme == "file"
      path = URI::DEFAULT_PARSER.unescape(uri.path)
    else
      next
    end
  rescue URI::InvalidURIError
    path = File.expand_path(root_uri, base_dir)
  end

  path = File.expand_path(path)
  next if path == project_root || !File.directory?(path)

  type = if path.start_with?(pub_cache + "/")
           "pub-cache"
         elsif path.include?("/flutter/") || path.include?("/flutter_sdk/")
           "flutter-sdk"
         else
           "local-or-path"
         end
  puts [name, path, type].join("\t")
end
' "$PACKAGE_CONFIG" "$PROJECT_ROOT" | sort -u > "$ALL_DEPS_TSV"

  TOTAL_COUNT="$(wc -l < "$ALL_DEPS_TSV" | tr -d ' ')"
  (( TOTAL_COUNT > 0 )) || fail "未从 package_config.json 提取到依赖包路径。"
  success_echo "共发现 ${TOTAL_COUNT} 个依赖包根目录。"
}

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
    print -r -- "$selected_lines" > "$SELECTED_DEPS_TSV"
  else
    cp -p "$ALL_DEPS_TSV" "$SELECTED_DEPS_TSV"
  fi

  SELECTED_COUNT="$(wc -l < "$SELECTED_DEPS_TSV" | tr -d ' ')"
  info_echo "本次将打包 ${SELECTED_COUNT} 个 Dart / Flutter 依赖。"
}

copy_dir() {
  local source_dir="$1"
  local target_dir="$2"
  mkdir -p "$(dirname "$target_dir")"
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

copy_file_if_exists() {
  local source_file="$1"
  local target_file="$2"
  [[ -f "$source_file" ]] || return 0
  mkdir -p "$(dirname "$target_file")"
  cp -p "$source_file" "$target_file"
}

copy_dir_if_exists() {
  local source_dir="$1"
  local target_dir="$2"
  [[ -d "$source_dir" ]] || return 0
  info_echo "复制原生依赖目录：${source_dir#$PROJECT_ROOT/}"
  copy_dir "$source_dir" "$target_dir"
}

copy_project_file_rel() {
  local source_file="$1"
  [[ -f "$source_file" ]] || return 0
  local relative_path="${source_file#$PROJECT_ROOT/}"
  copy_file_if_exists "$source_file" "$STAGE/project_files/$relative_path"
}

copy_dart_packages() {
  local copied_manifest="$STAGE/manifest/copied_package_roots.tsv"
  local package_name=""
  local package_path=""
  local package_type=""
  local safe_name=""
  local target_dir=""
  : > "$copied_manifest"

  while IFS=$'\t' read -r package_name package_path package_type; do
    [[ -n "$package_name" && -d "$package_path" ]] || continue
    safe_name="$(print -rn -- "$package_name" | tr -c 'A-Za-z0-9._-' '_')"
    target_dir="$STAGE/dart_packages/$safe_name"
    info_echo "复制依赖：$package_name"
    copy_dir "$package_path" "$target_dir"
    printf '%s\t%s\t%s\t%s\n' "$package_name" "$package_path" "$package_type" "dart_packages/$safe_name" >> "$copied_manifest"
  done < "$SELECTED_DEPS_TSV"
}

copy_project_dependency_files() {
  local search_root=""
  local found_file=""

  copy_project_file_rel "$PROJECT_ROOT/pubspec.yaml"
  copy_project_file_rel "$PROJECT_ROOT/pubspec.lock"
  copy_project_file_rel "$PROJECT_ROOT/.metadata"
  copy_project_file_rel "$PROJECT_ROOT/analysis_options.yaml"
  copy_project_file_rel "$PROJECT_ROOT/.dart_tool/package_config.json"
  copy_project_file_rel "$PROJECT_ROOT/.dart_tool/package_graph.json"
  copy_project_file_rel "$PROJECT_ROOT/ios/Podfile"
  copy_project_file_rel "$PROJECT_ROOT/ios/Podfile.lock"
  copy_project_file_rel "$PROJECT_ROOT/macos/Podfile"
  copy_project_file_rel "$PROJECT_ROOT/macos/Podfile.lock"

  copy_dir_if_exists "$PROJECT_ROOT/ios/Pods" "$STAGE/native/ios/Pods"
  copy_dir_if_exists "$PROJECT_ROOT/macos/Pods" "$STAGE/native/macos/Pods"
  copy_dir_if_exists "$PROJECT_ROOT/ios/.symlinks" "$STAGE/native/ios/.symlinks"
  copy_dir_if_exists "$PROJECT_ROOT/macos/.symlinks" "$STAGE/native/macos/.symlinks"
  copy_dir_if_exists "$PROJECT_ROOT/build/ios/SwiftPackages" "$STAGE/native/ios/SwiftPackages"
  copy_dir_if_exists "$PROJECT_ROOT/build/macos/SwiftPackages" "$STAGE/native/macos/SwiftPackages"

  for search_root in "$PROJECT_ROOT/ios" "$PROJECT_ROOT/macos"; do
    [[ -d "$search_root" ]] || continue
    while IFS= read -r -d '' found_file; do
      copy_project_file_rel "$found_file"
    done < <(find "$search_root" -name 'Package.resolved' -type f -print0 2>/dev/null)
  done

  if [[ -d "$PROJECT_ROOT/android" ]]; then
    while IFS= read -r -d '' found_file; do
      copy_project_file_rel "$found_file"
    done < <(find "$PROJECT_ROOT/android" \( \
      -name 'build.gradle' -o \
      -name 'build.gradle.kts' -o \
      -name 'settings.gradle' -o \
      -name 'settings.gradle.kts' -o \
      -name 'gradle.properties' -o \
      -name 'libs.versions.toml' \
    \) -type f -print0 2>/dev/null)
  fi
}

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
  } > "$STAGE/manifest/project_info.txt"

  ("${FLUTTER_CMD[@]}" --version || true) > "$STAGE/manifest/flutter_version.txt" 2>&1
  ("${FLUTTER_CMD[@]}" pub deps --style=compact || true) > "$STAGE/manifest/flutter_pub_deps_compact.txt" 2>&1

  cat > "$STAGE/README.txt" <<'README'
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

create_zip_archive() {
  local zip_size=""
  info_echo "开始压缩到桌面：$ZIP_PATH"
  (cd "$TMP_PARENT" && ditto -c -k --sequesterRsrc --keepParent "$STAGE_NAME" "$ZIP_PATH")
  [[ -f "$ZIP_PATH" ]] || fail "压缩失败：$ZIP_PATH"
  zip_size="$(du -h "$ZIP_PATH" | awk '{print $1}')"
  success_echo "打包完成：$ZIP_PATH"
  success_echo "压缩包大小：$zip_size"
  gray_echo "执行日志：$LOG_FILE"
}

run_main_flow() {
  parse_arguments "$@"
  show_script_intro_and_wait
  resolve_project_root
  prepare_project_context
  resolve_flutter_command
  prepare_package_config
  check_environment
  prepare_output_paths
  trap cleanup_temp_files EXIT
  extract_package_roots
  select_package_roots
  copy_dart_packages
  copy_project_dependency_files
  write_package_manifest
  create_zip_archive
}

main() {
  initialize_script_runtime
  run_main_flow "$@"
}

main "$@"
