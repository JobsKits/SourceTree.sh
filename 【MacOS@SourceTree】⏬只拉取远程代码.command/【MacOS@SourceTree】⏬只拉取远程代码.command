#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】⏬只拉取远程代码.command
# - 核心用途：将当前仓库同步到明确的远程上游，逐层按父仓 gitlink 检出子模块，不提交、不推送。
# - 影响范围：先 fetch；发现本地改动、未跟踪文件或独有提交时，终端红字列明范围，精确输入 YES 才舍弃。
# - 保护边界：忽略文件保留；未完成操作、游离 HEAD、上游不明确、子仓风险或忽略文件覆盖风险时停止。
# - 运行提示：SourceTree 只打开 Terminal.app；终端先回车确认，危险操作另需 YES，Ctrl+C 取消。

RAW_SCRIPT_PATH="$0"
SCRIPT_PATH=""
SCRIPT_DIR=""
SCRIPT_BASENAME=""
LOG_FILE=""
IS_SOURCETREE_RUNTIME=0
TERMINAL_RUN=0
PLAIN_OUTPUT=1
REPOSITORY=""
BRANCH=""
REMOTE=""
MERGE_REF=""
TRACKING_REF=""
SOURCE_URL=""
EFFECTIVE_URL=""
ORIGINAL_HEAD=""
TARGET_HEAD=""
WORKTREE_STATE=""
WORKTREE_FINGERPRINT=""
LOCAL_ONLY_COUNT=0
PREPARE_DIRECTORY=""
SYNC_STARTED=0
PLAN_PATHS=()
PLAN_PARENTS=()
PLAN_SECTIONS=()
PLAN_TARGETS=()
PLAN_URLS=()
PLAN_ORIGINAL_HEADS=()
PLAN_ORIGINAL_BRANCHES=()
PLAN_OBJECT_REPOS=()
PLAN_OLD_PINS=()
LOCK_DIRECTORY=""
LOCK_HELD=0
COLOR_RED=""
COLOR_BLUE=""
COLOR_GREEN=""
COLOR_RESET=""
# 只读解析入口和展示变量，不在确认前写入文件。
prepare_display_context() {
  local candidate="${RAW_SCRIPT_PATH:A}"
  local filename="${RAW_SCRIPT_PATH:t}"
  local fallback=""
  for fallback in "${HOME}/SourceTree.command/${filename}/${filename}" "${HOME}/Documents/Github/JobsGenesis/SourceTree.command/${filename}/${filename}"; do
    [[ -f "$candidate" ]] && break
    [[ -f "$fallback" ]] && candidate="$fallback"
  done
  SCRIPT_PATH="$candidate"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.$(/bin/date +%Y%m%d-%H%M%S).$$.log"
  [[ "${1:-}" == --terminal-run ]] && TERMINAL_RUN=1
  if (( ! TERMINAL_RUN )); then
    local process_id="$PPID" process_name="" guard=0
    if /usr/bin/env | /usr/bin/grep -Eqi '^(SOURCETREE|SOURCE_TREE)'; then
      IS_SOURCETREE_RUNTIME=1
    fi
    while [[ -n "$process_id" && "$process_id" != 0 && "$guard" -lt 8 ]]; do
      process_name="$(/bin/ps -o comm= -p "$process_id" 2>/dev/null)"
      [[ "$process_name" == *SourceTree* || "$process_name" == *Sourcetree* ]] && IS_SOURCETREE_RUNTIME=1
      process_id="$(/bin/ps -o ppid= -p "$process_id" 2>/dev/null | /usr/bin/tr -d ' ')"
      guard=$((guard + 1))
    done
  fi
  configure_output_mode
}
# SourceTree 输出纯文本，独立终端按终端能力显示红字。
configure_output_mode() {
  PLAIN_OUTPUT=1
  if (( ! IS_SOURCETREE_RUNTIME )) && [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
    PLAIN_OUTPUT=0
    COLOR_RED=$'\033[1;31m'
    COLOR_BLUE=$'\033[0;34m'
    COLOR_GREEN=$'\033[0;32m'
    COLOR_RESET=$'\033[0m'
  else
    export NO_COLOR=1 FORCE_COLOR=0 CLICOLOR=0 ANSI_COLORS_DISABLED=1 npm_config_color=false
  fi
}
# 过滤终端控制码和地址凭据，日志只保留可读脱敏文本。
sanitize_stream() {
  /usr/bin/perl -pe 's/\e\[[0-?]*[ -\/]*[@-~]//g; s{([a-zA-Z][a-zA-Z0-9+.-]*://)[^/\s]*@}{$1***@}g; s{((?:https?|ssh|git|file)://[^\s?#]+)[?#][^\s]*}{$1?[REDACTED]}g'
}
# 显示内置自述；SourceTree 转交终端，终端先确认再进入业务。
show_script_intro_and_wait() {
  prepare_display_context "$@"
  print -r -- "${COLOR_RED}================ 只拉取远程代码 ================${COLOR_RESET}"
  print -r -- "${COLOR_BLUE}1、同步当前仓库明确的远程上游，再向下按各层父仓记录的提交检出子模块；不提交、不推送。${COLOR_RESET}"
  print -r -- "${COLOR_BLUE}2、先获取远程；本地改动、未跟踪文件和独有提交须精确输入 YES 才舍弃。${COLOR_RESET}"
  print -r -- "${COLOR_BLUE}3、子模块只跟随 gitlink，不追分支最新；子仓源码、暂存指针、独有游离提交和有损路径变更均停止。${COLOR_RESET}"
  print -r -- "${COLOR_BLUE}4、SourceTree 打开独立终端；回车继续，Ctrl+C 取消；日志：${LOG_FILE}${COLOR_RESET}"
  if (( IS_SOURCETREE_RUNTIME )); then
    open_terminal_for_repository "$@"
    exit $?
  fi
  if [[ ! -t 0 || ! -t 1 ]]; then
    print -u2 -r -- "请在可交互终端运行；非交互输入不能代替回车或 YES 确认。"
    exit 1
  fi
  local answer=""
  IFS= read -r 'answer?👉 已了解用途与风险，按回车继续；Ctrl+C 取消：' || exit 1
  [[ -z "$answer" ]] || { print -r -- '已取消。'; exit 2; }
}
# 用 AppleScript argv 和 shell 引号传递路径，启动器不执行 Git 业务。
open_terminal_for_repository() {
  [[ "$#" -eq 1 && -d "$1" ]] || { print -u2 -r -- 'SourceTree 必须传入一个有效仓库目录（$REPO）。'; return 1; }
  /usr/bin/osascript - "$SCRIPT_PATH" "${1:A}" <<'APPLESCRIPT'
on run argv
  set scriptPath to item 1 of argv
  set repositoryPath to item 2 of argv
  set shellCommand to "/bin/zsh " & quoted form of scriptPath & " --terminal-run " & quoted form of repositoryPath & "; jobs_pull_result=$?; printf '\n只拉取结束，退出码：%s\n' \"$jobs_pull_result\""
  tell application "Terminal"
    activate
    do script shellCommand
  end tell
end run
APPLESCRIPT
  local launch_result=$?
  if (( launch_result != 0 )); then
    print -u2 -r -- 'Terminal 启动失败，请检查自动化权限或在终端手动运行脚本。'
    return "$launch_result"
  fi
  print -r -- '已打开 Terminal；确认、实时日志与最终退出码请查看新终端。'
}
# 确认后初始化私有日志和清理钩子。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
  umask 077
  : > "$LOG_FILE" || { print -u2 -r -- "无法创建日志：${LOG_FILE}"; exit 1; }
  configure_output_mode
  configure_gitee_https_transport
}
# 兼容旧根仓 / 子仓的 Gitee 标准 SSH 地址；只追加本次进程配置，保留既有 Git 环境规则。
configure_gitee_https_transport() {
  local config_count="${GIT_CONFIG_COUNT:-0}" prefix=""
  [[ "$config_count" == <-> && ${#config_count} -le 9 ]] || fail 'GIT_CONFIG_COUNT 无效，不能安全追加本次 HTTPS 兼容配置。'
  local -i config_index=$(( 10#$config_count ))
  local -a ssh_prefixes
  ssh_prefixes=('git@gitee.com:' 'ssh://git@gitee.com/' 'ssh://git@gitee.com:22/')
  for prefix in "${ssh_prefixes[@]}"; do
    typeset -gx "GIT_CONFIG_KEY_${config_index}=url.https://gitee.com/.insteadOf"
    typeset -gx "GIT_CONFIG_VALUE_${config_index}=$prefix"
    (( config_index += 1 ))
  done
  export GIT_CONFIG_COUNT="$config_index"
  log_message info 'Gitee 标准 SSH 地址在本次进程兼容 HTTPS；来源块显示 Git 配置展开后的拉取地址。'
}
# 同步记录脱敏纯文本和终端展示颜色。
log_message() {
  local role="$1" message="$2" clean_message="" color=""
  clean_message="$(print -r -- "$message" | sanitize_stream)" || exit 1
  print -r -- "$clean_message" >> "$LOG_FILE" || exit 1
  case "$role" in
    danger) color="$COLOR_RED" ;;
    success) color="$COLOR_GREEN" ;;
    *) color="$COLOR_BLUE" ;;
  esac
  print -r -- "${color}${clean_message}${COLOR_RESET}"
}
# 明确报错并停止后续写操作。
fail() {
  log_message danger "✖ $1"
  (( ! SYNC_STARTED )) || log_message danger '部分仓库可能已经检出目标；未创建提交或推送。请按日志处理后重新运行，不能将本次视为完成。'
  log_message info "日志：${LOG_FILE}"
  exit 1
}
# 所有 Git 操作禁用递归和本地钩子，避免一次拉取扩展业务范围。
repo_git() {
  command git -C "$REPOSITORY" -c color.ui=false -c core.hooksPath=/dev/null -c submodule.recurse=false "$@"
}
# 外部 Git 输出脱敏落盘，并保留管道失败状态。
run_git() {
  repo_git "$@" 2>&1 | sanitize_stream | /usr/bin/tee -a "$LOG_FILE"
}
# 仅接受有效目标目录，并确认 Git 真实可执行。
resolve_repository() {
  (( TERMINAL_RUN )) && shift
  [[ "$#" -le 1 ]] || fail '只接受一个仓库目录。'
  local requested="${1:-$PWD}"
  [[ -d "$requested" ]] || fail "目标目录不存在：${requested}"
  command -v git >/dev/null 2>&1 && command git --version >/dev/null 2>&1 || fail 'Git 不可用，请先安装或修复 Command Line Tools。'
  REPOSITORY="$(command git -C "$requested" rev-parse --show-toplevel 2>/dev/null)" || fail '目标不是 Git 工作树。'
  REPOSITORY="${REPOSITORY:A}"
  [[ "$(repo_git rev-parse --is-bare-repository)" == false ]] || fail '不支持裸仓库。'
  log_message info "仓库：${REPOSITORY}"
  LOCK_DIRECTORY="$(repo_git rev-parse --git-path jobs-readonly-pull.lock)" || fail '无法确定锁目录。'
  [[ "$LOCK_DIRECTORY" == /* ]] || LOCK_DIRECTORY="${REPOSITORY}/${LOCK_DIRECTORY}"
  /bin/mkdir "$LOCK_DIRECTORY" 2>/dev/null || fail "另一次只拉取任务可能正在运行；请核实后处理锁目录：${LOCK_DIRECTORY}"
  LOCK_HELD=1
}
# 只释放本进程取得的空锁目录。
release_repository_lock() {
  if (( LOCK_HELD && ZSH_SUBSHELL == 0 )); then
    if [[ -n "$PREPARE_DIRECTORY" && "$PREPARE_DIRECTORY" == "${LOCK_DIRECTORY}/prepare."* && -d "$PREPARE_DIRECTORY" ]]; then
      /usr/bin/find "$PREPARE_DIRECTORY" -depth -delete || print -u2 -r -- "无法清理本次临时准备目录：${PREPARE_DIRECTORY}"
    fi
    /bin/rm -f -- "${LOCK_DIRECTORY}/head-tree" "${LOCK_DIRECTORY}/target-tree" "${LOCK_DIRECTORY}/untracked" "${LOCK_DIRECTORY}/nested" "${LOCK_DIRECTORY}/ignored" "${LOCK_DIRECTORY}/protected-tree" "${LOCK_DIRECTORY}/snapshot" "${LOCK_DIRECTORY}/snapshot-paths"
    /bin/rmdir "$LOCK_DIRECTORY" 2>/dev/null || print -u2 -r -- "无法释放锁目录：${LOCK_DIRECTORY}"
    LOCK_HELD=0
  fi
}
# zsh 的函数内 EXIT trap 会随函数返回触发，改用脚本级退出函数。
TRAPEXIT() {
  release_repository_lock
}
# 中断进入脚本级退出清理，返回可识别的终止状态。
TRAPINT() {
  exit 130
}
# 终止信号不继续 Git 写操作。
TRAPTERM() {
  exit 143
}
# 终端断开时同样保留失败状态并释放本脚本锁。
TRAPHUP() {
  exit 129
}
# 冲突、进行中的 Git 操作和隐藏状态在任何 fetch / 清理前阻断。
assert_repository_ready() {
  local marker="" marker_path="" flags="" entry=""
  for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer BISECT_START index.lock; do
    marker_path="$(repo_git rev-parse --git-path "$marker")" || fail '无法检查 Git 操作状态。'
    [[ "$marker_path" == /* ]] || marker_path="${REPOSITORY}/${marker_path}"
    [[ ! -e "$marker_path" ]] || fail "存在未完成操作或 Git 锁：${REPOSITORY}（${marker}）；请先处理。"
  done
  [[ -z "$(repo_git ls-files -u)" ]] || fail '索引存在未解决冲突。'
  flags="$(repo_git ls-files -v)" || fail '无法检查索引标记。'
  for entry in "${(@f)flags}"; do
    [[ "$entry" != [a-zS]' '* ]] || fail '存在 assume-unchanged / skip-worktree（含稀疏检出），请先显式恢复普通工作树。'
  done
}
# 仅使用当前分支明确配置的单个远程上游，不猜分支或 origin。
resolve_upstream() {
  BRANCH="$(repo_git symbolic-ref --quiet --short HEAD)" || fail '当前是游离 HEAD，请先在 SourceTree 切换到已有的跟踪分支。'
  ORIGINAL_HEAD="$(repo_git rev-parse --verify HEAD)" || fail '当前分支没有有效提交。'
  REMOTE="$(repo_git config --get-all "branch.${BRANCH}.remote")" || fail '当前分支没有配置远程上游。'
  MERGE_REF="$(repo_git config --get-all "branch.${BRANCH}.merge")" || fail '当前分支没有配置上游分支。'
  [[ -n "$REMOTE" && "$REMOTE" != . && "$REMOTE" != -* && "$REMOTE" != *$'\n'* ]] || fail '只支持一个明确的远程上游。'
  [[ "$MERGE_REF" == refs/heads/* && "$MERGE_REF" != *$'\n'* ]] || fail '上游必须是单个远程分支。'
  repo_git check-ref-format "$MERGE_REF" || fail '上游分支名无效。'
  TRACKING_REF="$(repo_git for-each-ref --format='%(upstream)' "refs/heads/${BRANCH}")" || fail '无法解析远程跟踪引用。'
  [[ "$TRACKING_REF" == refs/remotes/* && "$TRACKING_REF" != *$'\n'* ]] || fail '远程跟踪映射不明确；请先修复分支上游配置。'
  SOURCE_URL="$(repo_git config --get-all "remote.${REMOTE}.url")" || fail '远程地址未配置。'
  [[ -n "$SOURCE_URL" && "$SOURCE_URL" != *$'\n'* ]] || fail '远程地址必须唯一。'
  EFFECTIVE_URL="$(repo_git ls-remote --get-url "$REMOTE")" || fail '无法展开当前 Git URL 配置。'
}
# 来源先于传输展示；只获取目标分支，失败时绝不清理工作区。
fetch_target() {
  log_message info '━━━━━━━━━━ 来源｜只拉取 ━━━━━━━━━━'
  log_message info "对象：${BRANCH} → ${REMOTE}/${MERGE_REF#refs/heads/}"
  log_message info "配置来源：${SOURCE_URL}"
  log_message info "拉取地址（本地 Git 配置展开）：${EFFECTIVE_URL}"
  log_message info "目标位置：${REPOSITORY}"
  run_git fetch --no-tags --no-recurse-submodules -- "$REMOTE" "+${MERGE_REF}:${TRACKING_REF}" || fail '远程获取失败，未舍弃本地内容。'
  TARGET_HEAD="$(repo_git rev-parse --verify "${TRACKING_REF}^{commit}")" || fail '远程目标不是有效提交。'
  log_message info "本次固定目标：${TARGET_HEAD}"
}
# 完整检查可能被覆盖或清理的目录，枚举失败也必须停止。
assert_directory_has_no_nested_git() {
  local directory="$1" nested=""
  /usr/bin/find "$directory" \( -name .git -print0 -prune \) -o \( -type d -name objects -print0 -prune \) > "${LOCK_DIRECTORY}/nested" || fail "无法完整检查目录，已停止清理：${directory}"
  while IFS= read -r -d '' nested; do
    [[ "${nested:t}" != .git ]] || fail "存在嵌套 Git 仓库，不能安全清理：${nested:h}"
    if [[ -f "${nested:h}/HEAD" && -d "${nested:h}/refs" ]]; then
      fail "存在嵌套裸仓库，不能安全清理：${nested:h}"
    fi
  done < "${LOCK_DIRECTORY}/nested"
}
# 已跟踪目录内也可能被另行 git init，不能仅依赖未跟踪文件列表。
assert_tracked_paths_have_no_nested_git() {
  local listing="$1" entry="" item="" parent=""
  local -A checked_parents=()
  while IFS= read -r -d '' entry; do
    [[ "$entry" == 160000\ * ]] && continue
    item="${entry#*$'\t'}"
    if [[ -d "${REPOSITORY}/${item}" && ! -L "${REPOSITORY}/${item}" ]]; then
      assert_directory_has_no_nested_git "${REPOSITORY}/${item}"
    fi
    parent="${item:h}"
    while [[ "$parent" != . && -n "$parent" ]]; do
      [[ "${checked_parents[$parent]:-0}" != 1 ]] || break
      checked_parents[$parent]=1
      [[ ! -e "${REPOSITORY}/${parent}/.git" ]] || fail "已跟踪路径内存在独立 Git 仓库：${REPOSITORY}/${parent}"
      if [[ -f "${REPOSITORY}/${parent}/HEAD" && -d "${REPOSITORY}/${parent}/objects" && -d "${REPOSITORY}/${parent}/refs" ]]; then
        fail "已跟踪路径内存在裸仓库：${REPOSITORY}/${parent}"
      fi
      parent="${parent:h}"
    done
  done < "$listing"
}
# 子仓和临时裸仓共用最小 Git 配置；URL 仅逐层显式传入，不覆盖 root remote。
tree_git() {
  local tree_repository="$1"
  shift
  command git -C "$tree_repository" -c color.ui=false -c core.hooksPath=/dev/null -c submodule.recurse=false "$@"
}
# 保留 Git 失败状态，所有子仓传输输出同样脱敏。
run_tree_git() {
  tree_git "$@" 2>&1 | sanitize_stream | /usr/bin/tee -a "$LOG_FILE"
}
# 子模块路径不能穿过符号链接、仓外目录或 Git 元数据。
validate_submodule_path() {
  local parent_root="$1" child_path="$2" component="" prefix="$1"
  [[ -n "$child_path" && "$child_path" != /* && "$child_path" != -* && "$child_path" != *$'\n'* && "$child_path" != *$'\r'* ]] || fail "子模块路径无效：${parent_root}/${child_path}"
  for component in "${(@s:/:)child_path}"; do
    [[ -n "$component" && "$component" != . && "$component" != .. && "${component:l}" != .git ]] || fail "子模块路径越界或涉及元数据：${parent_root}/${child_path}"
    prefix+="/${component}"
    [[ ! -L "$prefix" ]] || fail "子模块路径经过符号链接：${prefix}"
  done
  [[ "${prefix:A}" == "${parent_root}/"* ]] || fail "子模块路径不在父仓内：${prefix}"
}
# 按远端仓库目录语义解析相对地址，保留 host、namespace、协议和自定义端口。
resolve_child_source_url() {
  local parent_url="$1" raw_url="$2" parent_root="$3" resolved=""
  [[ -n "$raw_url" && "$raw_url" != -* && "$raw_url" != *$'\n'* && "$raw_url" != *$'\r'* && "$raw_url" != *'::'* ]] || fail "子模块来源无效：${parent_root}"
  resolved="$(/usr/bin/perl -e '
    use strict; use warnings;
    my ($base, $url, $root) = @ARGV;
    if ($url =~ m{^\./|^\.\./}) {
      my ($prefix, $path);
      if ($base =~ m{^([a-zA-Z][a-zA-Z0-9+.-]*://[^/]*)(/.*)$}) { ($prefix, $path) = ($1, $2); }
      elsif ($base =~ m{^([^/:]+(?:\@[^/:]+)?:)(.+)$}) { ($prefix, $path) = ($1, $2); }
      else { ($prefix, $path) = ("", $base); $path = "$root/$path" unless $path =~ m{^/}; }
      my $absolute = $path =~ m{^/};
      my @parts;
      for my $part (split m{/}, "$path/$url") {
        next if $part eq "" || $part eq ".";
        if ($part eq "..") { die "Relative URL escapes repository scope\n" unless @parts; pop @parts; }
        else { push @parts, $part; }
      }
      die "Empty repository URL\n" unless @parts;
      $url = $prefix . ($absolute ? "/" : "") . join("/", @parts);
    }
    $url =~ s{^git\@gitee\.com:}{https://gitee.com/};
    $url =~ s{^ssh://git\@gitee\.com(?::22)?/}{https://gitee.com/};
    print $url;
  ' "$parent_url" "$raw_url" "$parent_root")" || fail "不能解析子模块相对来源：${parent_root}"
  print -r -- "$resolved"
}
# 已暂存的 gitlink 是用户意图，不能用 ignore-submodules=all 将它隐藏。
assert_no_staged_gitlinks() {
  local staged_raw=""
  staged_raw="$(repo_git diff --cached --raw --no-abbrev --ignore-submodules=none HEAD)" || fail "无法检查暂存指针：${REPOSITORY}"
  [[ -z "$(print -r -- "$staged_raw" | /usr/bin/awk '$1 == ":160000" || $2 == "160000"')" ]] || fail "存在已暂存的子模块指针或类型变化：${REPOSITORY}；请单独处理。"
}
# 对已有工作树保留原先的嵌套仓库保护，但允许纯子模块检出漂移。
assert_worktree_paths_safe() {
  assert_no_staged_gitlinks
  repo_git ls-tree -rz HEAD > "${LOCK_DIRECTORY}/head-tree" || fail "无法枚举当前树：${REPOSITORY}"
  repo_git ls-tree -rz "$TARGET_HEAD" > "${LOCK_DIRECTORY}/target-tree" || fail "无法枚举目标树：${REPOSITORY}"
  assert_tracked_paths_have_no_nested_git "${LOCK_DIRECTORY}/head-tree"
  assert_tracked_paths_have_no_nested_git "${LOCK_DIRECTORY}/target-tree"
  local candidate=""
  repo_git ls-files --others --exclude-standard --directory -z > "${LOCK_DIRECTORY}/untracked" || fail '无法枚举未跟踪目录。'
  # 只检查将被清理的未跟踪目录；其中的 Git 元数据不能因依赖目录名而漏检。
  while IFS= read -r -d '' candidate; do
    candidate="${candidate%/}"
    [[ -d "${REPOSITORY}/${candidate}" && ! -L "${REPOSITORY}/${candidate}" ]] || continue
    assert_directory_has_no_nested_git "${REPOSITORY}/${candidate}"
  done < "${LOCK_DIRECTORY}/untracked"
}
# 空目录可以初始化；非空普通目录或失效 Git 指针不作为下载目标覆盖。
assert_new_submodule_path_empty() {
  local child_root="$1" contents=""
  [[ ! -e "$child_root" ]] && return 0
  [[ -d "$child_root" && ! -L "$child_root" ]] || fail "新子模块目标不是空目录：${child_root}"
  contents="$(/usr/bin/find "$child_root" -mindepth 1 -maxdepth 1 -print)" || fail "无法检查新子模块目录：${child_root}"
  [[ -z "$contents" ]] || fail "子模块未初始化但目标目录非空，保留原内容并停止：${child_root}"
}
# 游离 HEAD 只在仍受已知引用或旧 / 新父仓指针保护时允许离开。
assert_child_head_is_preserved() {
  local child_root="$1" old_pin="$2" target_pin="$3" current_head="" containing_refs=""
  current_head="$(tree_git "$child_root" rev-parse --verify HEAD)" || fail "子仓没有有效 HEAD：${child_root}"
  containing_refs="$(tree_git "$child_root" for-each-ref --contains "$current_head" --format='%(refname)')" || fail "无法核对子仓提交引用：${child_root}"
  [[ -n "$containing_refs" || "$current_head" == "$old_pin" || "$current_head" == "$target_pin" ]] && return 0
  if [[ -n "$old_pin" ]] && tree_git "$child_root" merge-base --is-ancestor "$current_head" "$old_pin" 2>/dev/null; then
    return 0
  fi
  tree_git "$child_root" merge-base --is-ancestor "$current_head" "$target_pin" 2>/dev/null && return 0
  fail "子仓存在未受引用或父仓指针保护的游离提交：${child_root}（${current_head}）；请先保存该提交。"
}
# 子仓不继承父仓 YES；普通源码、暂存指针和未完成操作均须单独处理。
assert_child_worktree_ready() {
  local REPOSITORY="$1" TARGET_HEAD="$2" child_state="" actual_root=""
  actual_root="$(repo_git rev-parse --show-toplevel)" || fail "子模块工作树无效：${REPOSITORY}"
  [[ "${actual_root:A}" == "$REPOSITORY" ]] || fail "子模块路径指向其它工作树：${REPOSITORY}"
  log_message info "检查子仓：${REPOSITORY}"
  assert_repository_ready
  assert_no_staged_gitlinks
  child_state="$(repo_git status --porcelain=v1 --untracked-files=all --ignore-submodules=all)" || fail "无法检查子仓源码：${REPOSITORY}"
  [[ -z "$child_state" ]] || fail "子仓存在暂存 / 未暂存 / 未跟踪源码：${REPOSITORY}"$'\n'"${child_state}"
  assert_worktree_paths_safe
  assert_ignored_paths_safe
}
# 显式展示本层来源和父仓要求的固定提交，不把分支最新当作替代目标。
show_child_source() {
  local child_root="$1" source_url="$2" target_pin="$3" object_repo="$4" effective_url=""
  effective_url="$(tree_git "$object_repo" ls-remote --get-url -- "$source_url")" || fail "无法解析子仓来源：${child_root}"
  log_message info '━━━━━━━━━━ 来源｜子模块固定提交 ━━━━━━━━━━'
  log_message info "对象：${child_root}"
  log_message info "父仓记录提交：${target_pin}"
  log_message info "解析来源：${source_url}"
  log_message info "拉取地址（本地 Git 配置展开）：${effective_url}"
}
# 现有子仓预取对象；未初始化子仓在私有临时裸仓预检，缺提交时不改任何工作树。
prepare_child_commit() {
  local child_root="$1" source_url="$2" target_pin="$3" plan_number="$4" object_repo="$1"
  if [[ ! -e "${child_root}/.git" ]]; then
    object_repo="${PREPARE_DIRECTORY}/objects-${plan_number}.git"
    run_tree_git "$PREPARE_DIRECTORY" init --bare --quiet "$object_repo" || fail "无法建立子模块临时对象库：${child_root}"
  fi
  PLAN_OBJECT_REPOS[$plan_number]="$object_repo"
  show_child_source "$child_root" "$source_url" "$target_pin" "$object_repo"
  if ! tree_git "$object_repo" cat-file -e "${target_pin}^{commit}" 2>/dev/null; then
    local -a fetch_options
    fetch_options=(--no-tags --no-recurse-submodules)
    [[ "$object_repo" != "$child_root" ]] && fetch_options+=(--depth=1)
    run_tree_git "$object_repo" fetch "${fetch_options[@]}" -- "$source_url" "$target_pin" || fail "子仓目标提交不可取得：${child_root}"$'\n'"父仓 gitlink：${target_pin}"$'\n'"来源：${source_url}；请由发布端先补齐该提交。"
  fi
  tree_git "$object_repo" cat-file -e "${target_pin}^{commit}" 2>/dev/null || fail "子仓目标不是可检出的提交：${child_root}（${target_pin}；来源：${source_url}）"
}
# 删除、改名和子模块 / 普通路径互换会产生有损现场，本动作只接受保留路径和正常新增。
assert_gitlink_paths_preserved() {
  local object_repo="$1" original_revision="$2" target_revision="$3" working_root="$4" listing="${PREPARE_DIRECTORY}/paths-${#PLAN_PATHS}.tree" entry="" item="" target_entry=""
  [[ -n "$original_revision" ]] || return 0
  tree_git "$object_repo" ls-tree -rz "$original_revision" > "$listing" || fail "无法枚举子仓旧指针：${working_root}"
  while IFS= read -r -d '' entry; do
    [[ "$entry" == 160000\ * ]] || continue
    item="${entry#*$'\t'}"
    target_entry="$(tree_git "$object_repo" --literal-pathspecs ls-tree "$target_revision" -- "$item")" || fail "无法核对目标子模块路径：${working_root}/${item}"
    [[ "$target_entry" == 160000\ * ]] || fail "远程删除、改名或转换了子模块路径，保留现场并停止：${working_root}/${item}"
  done < "$listing"
}
# 先读取各层目标提交的 .gitmodules；整个计划只记录固定 SHA，不执行工作树检出。
prepare_descendant_plan() {
  local parent_root="$1" object_repo="$2" target_revision="$3" parent_url="$4" depth="$5" old_revision="$6"
  (( depth <= 64 )) || fail "子模块递归超过 64 层，可能存在循环：${parent_root}"
  assert_gitlink_paths_preserved "$object_repo" "$old_revision" "$target_revision" "$parent_root"
  local manifest="${PREPARE_DIRECTORY}/manifest-${#PLAN_PATHS}.gitmodules" tree_listing="${PREPARE_DIRECTORY}/target-${#PLAN_PATHS}.tree" keys_listing="${PREPARE_DIRECTORY}/keys-${#PLAN_PATHS}"
  local entry="" child_path="" child_pin="" old_pin="" old_entry="" metadata="" section="" config_entry="" config_key="" configured_path="" raw_url="" child_url="" child_root="" child_head="" child_branch="" cache_path="" plan_number=0
  local -A path_sections=()
  tree_git "$object_repo" ls-tree -rz "$target_revision" > "$tree_listing" || fail "无法读取目标目录树：${parent_root}"
  if tree_git "$object_repo" cat-file -e "${target_revision}:.gitmodules" 2>/dev/null; then
    tree_git "$object_repo" show "${target_revision}:.gitmodules" > "$manifest" || fail "无法读取目标 .gitmodules：${parent_root}"
    tree_git "$object_repo" config --file "$manifest" --list >/dev/null || fail "目标 .gitmodules 解析失败：${parent_root}"
    local config_result=0
    tree_git "$object_repo" config --file "$manifest" --null --get-regexp '^submodule\..*\.path$' > "$keys_listing" || config_result=$?
    (( config_result == 0 || config_result == 1 )) || fail "无法读取目标子模块登记：${parent_root}"
    while IFS= read -r -d '' config_entry; do
      config_key="${config_entry%%$'\n'*}"
      configured_path="${config_entry#*$'\n'}"
      section="${config_key#submodule.}"
      section="${section%.path}"
      validate_submodule_path "$parent_root" "$configured_path"
      validate_submodule_path "$parent_root" "$section"
      [[ -z "${path_sections[$configured_path]:-}" ]] || fail "重复的子模块 path：${parent_root}/${configured_path}"
      path_sections[$configured_path]="$section"
    done < "$keys_listing"
  fi
  while IFS= read -r -d '' entry; do
    [[ "$entry" == 160000\ * ]] || continue
    child_path="${entry#*$'\t'}"
    metadata="${entry%%$'\t'*}"
    child_pin="${metadata##* }"
    validate_submodule_path "$parent_root" "$child_path"
    section="${path_sections[$child_path]:-}"
    [[ -n "$section" ]] || fail "gitlink 缺少明确的 .gitmodules 登记：${parent_root}/${child_path}"
    raw_url="$(tree_git "$object_repo" config --file "$manifest" --get-all "submodule.${section}.url")" || fail "子模块没有来源：${parent_root}/${child_path}"
    child_url="$(resolve_child_source_url "$parent_url" "$raw_url" "$parent_root")" || fail "子模块来源解析失败：${parent_root}/${child_path}"
    child_root="${parent_root}/${child_path}"
    old_pin=""
    if [[ -n "$old_revision" ]]; then
      old_entry="$(tree_git "$object_repo" --literal-pathspecs ls-tree "$old_revision" -- "$child_path")" || fail "无法检查原子模块路径：${child_root}"
      [[ -z "$old_entry" || "$old_entry" == 160000\ * ]] || fail "远程将普通路径转换为子模块，保留现场并停止：${child_root}"
      if [[ -n "$old_entry" ]]; then
        metadata="${old_entry%%$'\t'*}"
        old_pin="${metadata##* }"
      fi
    fi
    child_head=""
    child_branch=""
    if [[ -e "${child_root}/.git" ]]; then
      [[ -n "$old_pin" ]] || fail "新增 gitlink 路径已有独立 Git，不能接管：${child_root}"
      child_head="$(tree_git "$child_root" rev-parse --verify HEAD)" || fail "子模块 Git 指针损坏：${child_root}"
      child_branch="$(tree_git "$child_root" symbolic-ref --quiet HEAD 2>/dev/null)" || child_branch=""
      assert_child_worktree_ready "$child_root" "$child_head"
    else
      assert_new_submodule_path_empty "$child_root"
      cache_path="$(tree_git "$object_repo" rev-parse --git-path "modules/${section}")" || fail "无法检查子模块缓存：${child_root}"
      [[ "$cache_path" == /* ]] || cache_path="${object_repo}/${cache_path}"
      [[ ! -e "$cache_path" ]] || fail "子模块工作树缺失但仍有缓存，先恢复工作树以保护索引和独有提交：${child_root}"
    fi
    PLAN_PATHS+=("$child_root")
    PLAN_PARENTS+=("$parent_root")
    PLAN_SECTIONS+=("$section")
    PLAN_TARGETS+=("$child_pin")
    PLAN_URLS+=("$child_url")
    PLAN_ORIGINAL_HEADS+=("$child_head")
    PLAN_ORIGINAL_BRANCHES+=("$child_branch")
    PLAN_OBJECT_REPOS+=("")
    PLAN_OLD_PINS+=("$old_pin")
    plan_number=${#PLAN_PATHS}
    prepare_child_commit "$child_root" "$child_url" "$child_pin" "$plan_number"
    if [[ -n "$child_head" ]]; then
      assert_child_head_is_preserved "$child_root" "$old_pin" "$child_pin"
      assert_child_worktree_ready "$child_root" "$child_pin"
    fi
    prepare_descendant_plan "$child_root" "${PLAN_OBJECT_REPOS[$plan_number]}" "$child_pin" "$child_url" "$((depth + 1))" "$child_head"
  done < "$tree_listing"
}
# 顶层保护先完成，再预检整棵将要检出的提交树。
assert_nested_repositories_safe() {
  assert_worktree_paths_safe
  PREPARE_DIRECTORY="$(/usr/bin/mktemp -d "${LOCK_DIRECTORY}/prepare.XXXXXX")" || fail '无法创建私有子模块准备目录。'
  prepare_descendant_plan "$REPOSITORY" "$REPOSITORY" "$TARGET_HEAD" "$SOURCE_URL" 0 "$ORIGINAL_HEAD"
  log_message info "已预检 ${#PLAN_PATHS} 个子模块的固定提交；尚未修改工作树。"
}
# 确认期间的子仓 HEAD、分支、源码或路径变化使整次计划失效。
assert_submodule_plan_unchanged() {
  local index=0 child_root="" current_branch=""
  for (( index=1; index<=${#PLAN_PATHS}; index++ )); do
    child_root="${PLAN_PATHS[$index]}"
    if [[ -n "${PLAN_ORIGINAL_HEADS[$index]}" ]]; then
      [[ -e "${child_root}/.git" && "$(tree_git "$child_root" rev-parse HEAD)" == "${PLAN_ORIGINAL_HEADS[$index]}" ]] || fail "确认期间子仓 HEAD 或路径变化：${child_root}"
      current_branch="$(tree_git "$child_root" symbolic-ref --quiet HEAD 2>/dev/null)" || current_branch=""
      [[ "$current_branch" == "${PLAN_ORIGINAL_BRANCHES[$index]}" ]] || fail "确认期间子仓分支变化：${child_root}"
      assert_child_worktree_ready "$child_root" "${PLAN_TARGETS[$index]}"
      assert_child_head_is_preserved "$child_root" "${PLAN_OLD_PINS[$index]}" "${PLAN_TARGETS[$index]}"
    else
      assert_new_submodule_path_empty "$child_root"
    fi
  done
}
# 每次只执行直属一层；子仓 URL 来自该层父 URL，绝不跟踪分支最新或创建本地提交。
synchronize_submodule_plan() {
  local index=0 child_root="" parent_root="" child_path="" section="" target_pin="" current_branch=""
  local -a update_options
  for (( index=1; index<=${#PLAN_PATHS}; index++ )); do
    child_root="${PLAN_PATHS[$index]}"
    parent_root="${PLAN_PARENTS[$index]}"
    child_path="${child_root#"${parent_root}/"}"
    section="${PLAN_SECTIONS[$index]}"
    target_pin="${PLAN_TARGETS[$index]}"
    update_options=(--init --checkout)
    if [[ -n "${PLAN_ORIGINAL_HEADS[$index]}" ]]; then
      update_options+=(--no-fetch)
      [[ "$(tree_git "$child_root" rev-parse HEAD)" == "${PLAN_ORIGINAL_HEADS[$index]}" ]] || fail "检出前子仓 HEAD 已变化：${child_root}"
      current_branch="$(tree_git "$child_root" symbolic-ref --quiet HEAD 2>/dev/null)" || current_branch=""
      [[ "$current_branch" == "${PLAN_ORIGINAL_BRANCHES[$index]}" ]] || fail "检出前子仓分支已变化：${child_root}"
      assert_child_worktree_ready "$child_root" "$target_pin"
    else
      assert_new_submodule_path_empty "$child_root"
    fi
    show_child_source "$child_root" "${PLAN_URLS[$index]}" "$target_pin" "${PLAN_OBJECT_REPOS[$index]}"
    # 新克隆可能遵循 shallow=true；允许 Git 补取已预检的旧 pin，避免浅克隆仅有分支 tip。
    run_tree_git "$parent_root" --literal-pathspecs -c "submodule.${section}.url=${PLAN_URLS[$index]}" submodule update "${update_options[@]}" -- "$child_path" || fail "子模块检出失败：${child_root}（gitlink：${target_pin}；来源：${PLAN_URLS[$index]}）"
    [[ "$(tree_git "$child_root" rev-parse HEAD)" == "$target_pin" ]] || fail "子模块提交核验失败：${child_root}（应为 ${target_pin}）"
    log_message success "✔ 子模块已按父仓检出：${child_root} → ${target_pin}；来源：${PLAN_URLS[$index]}"
  done
}
# hard reset 也可能移除挡路的忽略文件，先检查两棵树中的路径碰撞。
assert_ignored_paths_safe() {
  local collision=""
  repo_git ls-files --others --ignored --exclude-standard --directory -z > "${LOCK_DIRECTORY}/ignored" || fail '无法检查忽略文件。'
  [[ -s "${LOCK_DIRECTORY}/ignored" ]] || return 0
  repo_git ls-tree -rz --name-only HEAD > "${LOCK_DIRECTORY}/protected-tree" || fail '无法检查当前文件树。'
  repo_git ls-tree -rz --name-only "$TARGET_HEAD" >> "${LOCK_DIRECTORY}/protected-tree" || fail '无法检查目标文件树。'
  collision="$(/usr/bin/perl -e '
    use strict; use warnings; use feature "fc";
    use Encode qw(decode FB_CROAK);
    use Unicode::Normalize qw(NFD);
    sub normalized { my ($value) = @_; return NFD(fc(decode("UTF-8", $value, FB_CROAK))); }
    my ($tree_file, $ignored_file) = @ARGV;
    my (%ignored, %parents);
    open my $ignored_fh, "<", $ignored_file or die "Cannot read ignored paths: $!";
    local $/ = "\0";
    while (my $item = <$ignored_fh>) {
      chomp $item; $item =~ s{/$}{};
      my $key = normalized($item);
      $ignored{$key} = $item;
      my $parent = $key;
      while ($parent =~ s{/[^/]+$}{}) { $parents{$parent} = $item; }
    }
    open my $tree_fh, "<", $tree_file or die "Cannot read tree paths: $!";
    while (my $path = <$tree_fh>) {
      chomp $path; $path = normalized($path);
      if (exists $ignored{$path}) { print $ignored{$path}; exit 0; }
      if (exists $parents{$path}) { print $parents{$path}; exit 0; }
      while ($path =~ s{/[^/]+$}{}) {
        if (exists $ignored{$path}) { print $ignored{$path}; exit 0; }
      }
    }
  ' "${LOCK_DIRECTORY}/protected-tree" "${LOCK_DIRECTORY}/ignored")" || fail '忽略文件保护检查失败。'
  [[ -z "$collision" ]] || fail "忽略内容可能被目标覆盖：${REPOSITORY}/${collision}；请先手动移走。"
}
# 对暂存、未暂存和未跟踪内容建立只读摘要，确认后仍需完全相同。
capture_worktree_fingerprint() {
  local item="" snapshot="${LOCK_DIRECTORY}/snapshot"
  repo_git diff --no-ext-diff --no-textconv --binary --ignore-submodules=all > "$snapshot" || fail '无法读取未暂存内容摘要。'
  repo_git diff --cached --no-ext-diff --no-textconv --binary --ignore-submodules=all >> "$snapshot" || fail '无法读取暂存内容摘要。'
  repo_git ls-files --others --exclude-standard -z > "${LOCK_DIRECTORY}/snapshot-paths" || fail '无法读取未跟踪内容摘要。'
  while IFS= read -r -d '' item; do
    print -rn -- "$item" >> "$snapshot" || fail '无法保存内容摘要。'
    printf '\0' >> "$snapshot" || fail '无法保存内容摘要。'
    if [[ -L "${REPOSITORY}/${item}" ]]; then
      /usr/bin/readlink "${REPOSITORY}/${item}" >> "$snapshot" || fail '无法读取符号链接摘要。'
    elif [[ -f "${REPOSITORY}/${item}" ]]; then
      repo_git hash-object --no-filters -- "$item" >> "$snapshot" || fail '无法读取未跟踪文件摘要。'
    else
      fail "不支持的未跟踪文件类型或文件已变化：${REPOSITORY}/${item}"
    fi
  done < "${LOCK_DIRECTORY}/snapshot-paths"
  /usr/bin/shasum -a 256 "$snapshot" | /usr/bin/awk '{ print $1 }'
}
# 列出全部会被舍弃的路径和本地独有提交，再等待精确 YES。
review_local_risk() {
  WORKTREE_STATE="$(repo_git status --porcelain=v1 --untracked-files=all --ignore-submodules=all)" || fail '无法检查工作区。'
  LOCAL_ONLY_COUNT="$(repo_git rev-list --count "${TARGET_HEAD}..HEAD")" || fail '无法检查本地独有提交。'
  WORKTREE_FINGERPRINT="$(capture_worktree_fingerprint)" || fail '无法建立工作区内容摘要。'
  if [[ -n "$WORKTREE_STATE" || "$LOCAL_ONLY_COUNT" != 0 ]]; then
    log_message danger '⚠ 高危：继续将永久舍弃以下本地内容；不生成 stash 或备份。'
    log_message danger "仓库：${REPOSITORY}"
    log_message danger "当前分支：${BRANCH}；当前提交：${ORIGINAL_HEAD}"
    log_message danger "恢复目标：${REMOTE}/${MERGE_REF#refs/heads/}；提交：${TARGET_HEAD}"
    [[ -z "$WORKTREE_STATE" ]] || log_message danger "待舍弃的暂存 / 未暂存 / 未跟踪路径："$'\n'"${WORKTREE_STATE}"
    if [[ "$LOCAL_ONLY_COUNT" != 0 ]]; then
      log_message danger "待舍弃的本地独有提交：${LOCAL_ONLY_COUNT} 个"
      log_message danger "$(repo_git log --format='%h %s' "${TARGET_HEAD}..HEAD")"
    fi
    log_message danger '删除预览（不包含忽略文件，不使用双重 -f）：'
    run_git clean -nd || fail '无法预览未跟踪文件清理。'
    log_message danger '只有精确输入大写 YES 才舍弃并同步；回车、其它输入或 Ctrl+C 均取消。'
    local answer=""
    [[ -t 0 && -t 1 ]] || fail '危险操作必须在可交互终端确认。'
    print -n -r -- "${COLOR_RED}请输入 YES：${COLOR_RESET}"
    IFS= read -r answer || { log_message info '已取消，未舍弃本地内容。'; exit 2; }
    [[ "$answer" == YES ]] || { log_message info '已取消，未舍弃本地内容。'; exit 2; }
    log_message danger '已确认 YES：仅授权本次显示的仓库和固定目标。'
  fi
}
# 用户确认后重新核对 HEAD、分支、配置及路径，避免沿用失效计划。
assert_plan_unchanged() {
  assert_repository_ready
  [[ "$(repo_git symbolic-ref --quiet --short HEAD)" == "$BRANCH" && "$(repo_git rev-parse HEAD)" == "$ORIGINAL_HEAD" ]] || fail '确认期间分支或 HEAD 已变化，请重新运行。'
  [[ "$(repo_git config --get-all "branch.${BRANCH}.remote")" == "$REMOTE" && "$(repo_git config --get-all "branch.${BRANCH}.merge")" == "$MERGE_REF" ]] || fail '确认期间上游配置已变化，请重新运行。'
  [[ "$(repo_git status --porcelain=v1 --untracked-files=all --ignore-submodules=all)" == "$WORKTREE_STATE" ]] || fail '确认期间工作区状态已变化，请重新运行。'
  [[ "$(capture_worktree_fingerprint)" == "$WORKTREE_FINGERPRINT" ]] || fail '确认期间文件内容已变化，请重新运行并重新确认。'
  [[ "$(repo_git config --get-all "remote.${REMOTE}.url")" == "$SOURCE_URL" ]] || fail '确认期间远程来源已变化，请重新运行。'
  assert_worktree_paths_safe
  assert_submodule_plan_unchanged
  assert_ignored_paths_safe
}
# 干净分支仅快进；有明确 YES 授权时才 reset 和清理非忽略内容。
synchronize_repository() {
  SYNC_STARTED=1
  if [[ -n "$WORKTREE_STATE" || "$LOCAL_ONLY_COUNT" != 0 ]]; then
    run_git reset --hard --no-recurse-submodules "$TARGET_HEAD" || fail '重置失败，已停止；请检查工作区与日志。'
    run_git clean -fd || fail '清理失败，已停止；请检查工作区与日志。'
  elif [[ "$ORIGINAL_HEAD" != "$TARGET_HEAD" ]]; then
    run_git -c "branch.${BRANCH}.mergeOptions=" merge --ff-only --no-autostash --no-edit "$TARGET_HEAD" || fail '无法安全快进，已停止。'
  fi
  [[ "$(repo_git rev-parse HEAD)" == "$TARGET_HEAD" ]] || fail '同步后提交号核验失败。'
  synchronize_submodule_plan
  [[ -z "$(repo_git status --porcelain=v1 --untracked-files=all --ignore-submodules=none)" ]] || fail '同步后仍有本地变化，未标记成功。'
  log_message success "✔ 已同步：${BRANCH} → ${TARGET_HEAD}"
  log_message success "来源：${EFFECTIVE_URL}；${#PLAN_PATHS} 个子模块已按父仓固定提交核验；未执行提交或推送。"
  log_message info "日志：${LOG_FILE}"
}
# 逐步完成根仓及固定子模块的安全拉取，任何失败立即停止后续步骤。
main() {
  show_script_intro_and_wait "$@" # 先显示自述，由 SourceTree 转交终端并确认。
  initialize_runtime # 确认后建立私有日志与退出清理。
  resolve_repository "$@" # 校验目标并防止同一动作并行运行。
  assert_repository_ready # 未完成 Git 操作和隐藏状态先停止。
  resolve_upstream # 仅使用当前分支明确配置的远程上游。
  fetch_target # 成功获取并固定提交后才考虑舍弃。
  assert_nested_repositories_safe # 子模块及嵌套仓库不纳入清理授权。
  assert_ignored_paths_safe # 防止 hard reset 间接覆盖忽略内容。
  review_local_risk # 红字列明风险，危险操作强制精确 YES。
  assert_plan_unchanged # 写操作前重新核对确认计划。
  synchronize_repository # 安全快进或按 YES 授权舍弃并核验结果。
}

main "$@"
