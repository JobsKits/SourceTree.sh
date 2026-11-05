#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】📥修复Git无法Push.command
# - 核心用途：检查推送目标，安全整合非快进历史，普通推送后核对服务端提交；其它故障分类诊断。
# - 影响范围：仅当前仓库的已有分支和明确选择的远端分支；可能快进或创建保留双方历史的合并提交。
# - 运行提示：Sourcetree 转交 Terminal；终端先回车再确认计划；--diagnose 只诊断，--yes 表示明确授权执行。
# - 安全边界：不自动暂存、清理、stash、强推、变基、删除锁、改代理/鉴权或跨父子仓处理。

SCRIPT_PATH="${0:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"
REPO=""
REMOTE=""
BRANCH=""
LOCAL_BRANCH=""
PUSH_URL=""
FETCH_URL=""
GIT_DIR_PATH=""
COMMON_DIR=""
LOG_FILE=""
RUN_DIR=""
RESULT=""
GIT_STATUS=0
REMOTE_OID=""
LOCAL_OID=""
INITIAL_OID=""
DIAGNOSE=0
APPROVED=0
TERMINAL_SESSION=0
IS_SOURCETREE_RUNTIME=0
PLAIN_OUTPUT=0
OWN_LOCK=""
NETWORK_ATTEMPTS=3
MAX_SYNC_ROUNDS=3
MENU_BACK=0

# 对所有展示和落盘输出统一脱敏，避免 Git 错误回显 URL 凭据。
redact_stream() {
  /usr/bin/perl -pe 's/\e\[[0-9;]*[A-Za-z]//g; s{((?:proxy-authorization|authorization|set-cookie|cookie)\s*[:=]\s*)[^\r\n]*}{${1}[REDACTED]}gi; s{(https?://)[^/\s@]+@}{${1}[REDACTED]\@}gi; s{(https?://[^\s?#]+)[?#][^\s]*}{${1}?[REDACTED]}gi; s{((?:authorization|password|passwd|access_token|private_token|token)\s*[:=]\s*)\S+}{${1}[REDACTED]}gi'
}
# 输出纯文本审计；日志只接收已脱敏内容。
log() {
  if [[ -n "$LOG_FILE" ]]; then
    print -r -- "$*" | redact_stream | tee -a "$LOG_FILE"
  else
    print -r -- "$*" | redact_stream
  fi
}
# 输出阻塞原因并保持非零退出。
fail() {
  log "✖ $*"
  [[ -z "$LOG_FILE" ]] || log "日志：$LOG_FILE"
  exit 1
}
# 识别真实宿主，不用非 TTY 代替 Sourcetree 身份。
configure_output_mode() {
  local process_id="$PPID" process_name="" count=0
  if env | /usr/bin/grep -Eqi '^(SOURCETREE|SOURCE_TREE)'; then
    IS_SOURCETREE_RUNTIME=1
  fi
  while [[ "$process_id" != 0 && -n "$process_id" && "$count" -lt 8 ]]; do
    process_name="$(ps -o comm= -p "$process_id" 2>/dev/null)"
    [[ "$process_name" != *SourceTree* && "$process_name" != *Sourcetree* ]] || IS_SOURCETREE_RUNTIME=1
    process_id="$(ps -o ppid= -p "$process_id" 2>/dev/null | tr -d ' ')"
    count=$((count + 1))
  done
  if (( IS_SOURCETREE_RUNTIME )) || [[ ! -t 1 || -z "${TERM:-}" || "$TERM" == dumb || -n "${NO_COLOR+x}" ]]; then
    PLAIN_OUTPUT=1
    export NO_COLOR=1 FORCE_COLOR=0 CLICOLOR=0 ANSI_COLORS_DISABLED=1 npm_config_color=false
  fi
}
# 解析显式目标和运行策略；不对业务仓库产生写操作。
parse_arguments() {
  local -a positional=()
  local argument
  for argument in "$@"; do
    case "$argument" in
      --yes) APPROVED=1 ;;
      --diagnose) DIAGNOSE=1 ;;
      --terminal-session) TERMINAL_SESSION=1 ;;
      --help|-h) print -r -- '用法：脚本 [仓库] [remote] [远端分支] [--diagnose] [--yes]'; exit 0 ;;
      --*) fail "未知参数：$argument" ;;
      *) positional+=("$argument") ;;
    esac
  done
  (( ${#positional} <= 3 )) || fail '最多接受仓库、remote、远端分支三个位置参数。'
  REPO="${positional[1]:-$PWD}"
  REMOTE="${positional[2]:-}"
  BRANCH="${positional[3]:-}"
  REPO="${REPO%$'\r'}"
  REPO="${REPO#\"}"; REPO="${REPO%\"}"
  [[ ! -f "$REPO" ]] || REPO="${REPO:h}"
  [[ -d "$REPO" ]] || fail "路径不存在：$REPO"
  REPO="${REPO:A}"
}
# 渲染标题与正文，彩色仅在完整终端启用。
intro_line() {
  local role="$1" message="$2" color='0;34'
  [[ "$role" != title ]] || color='1;31'
  if (( PLAIN_OUTPUT )); then
    print -r -- "$message"
  else
    printf '\033[%sm%s\033[0m\n' "$color" "$message"
  fi
}
# 先展示写死的自述，真实执行前保留终端防误触。
show_script_intro_and_wait() {
  configure_output_mode
  intro_line title '📥 修复 Git 无法 Push'
  intro_line body '1、只处理当前仓库及选定线路；诊断目标、工作区、操作状态与远端历史。'
  intro_line body '2、安全快进／合并后普通推送；可能产生合并提交；推送后核对服务端 OID。'
  intro_line body '3、冲突、锁、权限、保护、LFS、配额等按原因停止并给处理方向，未知错误保留原始诊断。'
  intro_line body '4、不暂存未提交内容、不强推、不重写历史、不改代理、不绕过 hook；Ctrl+C 取消。'
  intro_line body "目标目录：$REPO；日志将写入临时目录的 jobs-push-repair.*。"
  if (( IS_SOURCETREE_RUNTIME && ! TERMINAL_SESSION )); then
    return 0
  fi
  (( APPROVED || DIAGNOSE )) && return 0
  [[ -t 0 ]] || fail '缺少交互终端；请在终端运行，或明确传 --yes / --diagnose。'
  local answer
  read -r 'answer?已了解影响，按回车继续检查；Ctrl+C 取消：' || exit 130
}
# Sourcetree 启动进程只转交参数；不会在输出窗口等待选择。
handoff_if_needed() {
  (( IS_SOURCETREE_RUNTIME && ! TERMINAL_SESSION )) || return 0
  [[ -f "$SCRIPT_PATH" ]] || fail '无法定位入口脚本，请使用安装器修复动作路径。'
  osascript - "$SCRIPT_PATH" "$REPO" "$REMOTE" "$BRANCH" "$DIAGNOSE" <<'APPLESCRIPT'
on run argv
  set cmd to "/bin/zsh " & quoted form of item 1 of argv & " --terminal-session " & quoted form of item 2 of argv
  if item 3 of argv is not "" then set cmd to cmd & " " & quoted form of item 3 of argv
  if item 4 of argv is not "" then set cmd to cmd & " " & quoted form of item 4 of argv
  if item 5 of argv is "1" then set cmd to cmd & " --diagnose"
  set cmd to cmd & "; jobs_push_rc=$?; printf '\nPush 修复结束，退出码：%s\n' \"$jobs_push_rc\""
  tell application "Terminal"
    activate
    do script cmd
  end tell
end run
APPLESCRIPT
  (( $? == 0 )) || fail 'Terminal 打开失败，请检查自动化权限后在终端运行。'
  log '已转交 Terminal，请在那里检查并确认计划。'
  exit 0
}
# 初始化当前进程和独立审计目录，不更改全局 Git 或网络配置。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  configure_output_mode
  export GIT_OPTIONAL_LOCKS=0
  umask 077
  command -v git >/dev/null || fail '缺少 Git，请先准备命令行工具。'
  RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/jobs-push-repair.XXXXXX")" || fail '无法创建日志目录。'
  LOG_FILE="$RUN_DIR/run.log"
  : > "$LOG_FILE"
  trap 'log "已中断；保留 Git 操作现场，请检查 git status 后再运行。"; exit 130' INT TERM HUP
  log "日志：$LOG_FILE"
}
# 仅释放本进程成功取得的互斥目录。
release_lock() {
  if [[ -n "$OWN_LOCK" ]]; then
    /bin/rm -f "$OWN_LOCK/pid"
    /bin/rmdir "$OWN_LOCK" 2>/dev/null
    OWN_LOCK=""
  fi
}
# zsh 的函数内 EXIT trap 会在函数返回时触发；全局命名 trap 才覆盖整个脚本。
TRAPEXIT() {
  release_lock
}
# 执行 Git 并实时显示已脱敏输出，保留真实退出码和结果供分流。
run_git() {
  local -a command_status
  local output_file="$RUN_DIR/command.log"
  LC_ALL=C GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never git -C "$REPO" -c color.ui=false "$@" 2>&1 | redact_stream | tee "$output_file" | tee -a "$LOG_FILE"
  command_status=("${pipestatus[@]}")
  RESULT="$(<"$output_file")"
  GIT_STATUS="${command_status[1]}"
  if (( command_status[2] != 0 || command_status[3] != 0 || command_status[4] != 0 )); then
    GIT_STATUS=1
  fi
  (( GIT_STATUS == 0 )) || log "Git 命令失败，退出码：$GIT_STATUS"
  return "$GIT_STATUS"
}
# 识别普通推送期间目标分支发生的并发移动。
is_remote_race() {
  local message="${1:l}"
  [[ "$message" == *'non-fast-forward'* || "$message" == *'fetch first'* || "$message" == *'stale info'* || "$message" == *'incorrect old value provided'* || ( "$message" == *'is at '* && "$message" == *'but expected '* ) ]]
}
# 将任何失败归入可行动原因，未知项仍保留原始错误。
diagnose_failure() {
  local message="${1:l}"
  if is_remote_race "$1"; then
    log '[P10 并发更新] 目标又有新提交，将重新获取、整合后有限重试。'
    return 0
  fi
  case "$message" in
    *'non-fast-forward'*|*'fetch first'*|*'stale info'*) log '[P10 并发更新] 目标又有新提交，将重新获取、整合后有限重试。' ;;
    *'publickey'*|*'authentication failed'*|*'could not read username'*|*'terminal prompts disabled'*|*'invalid username'*|*'saml'*|*'sso'*) log '[P11 鉴权] 检查当前主机账号、SSH agent/公钥、凭据管理器与组织 SSO；不删除凭据、不记录密钥。' ;;
    *'repository not found'*|*'permission denied'*|*'write access'*|*'error: 403'*|*'http 403'*|*'http/2 403'*|*'http/1.1 403'*|*'denied to'*) log '[P12 地址／权限] 确认脱敏显示的仓库地址、登录账号及写权限；SSH 可连通不等于有仓库写权限。' ;;
    *'protected branch'*|*'gh006'*|*'gh013'*|*'repository rule'*|*'signed commit'*|*'must be signed'*|*'changes must be made through a pull request'*) log '[P13 平台规则] 按服务端提示通过 PR、签名或审批满足分支规则；不自动改规则、不跳过验证。' ;;
    *'secret scanning'*|*'push protection'*|*'secret detected'*|*'gh009'*) log '[P14 敏感内容] 在平台按指引定位并撤销泄露凭据；历史清理需要单独评审，不自动重写。' ;;
    *'lfs'*|*'large files'*|*'gh001'*|*'exceeds'*|*'quota'*|*'too large'*) log '[P15 大文件／LFS／配额] 按服务端具体限制核对待推对象、LFS 安装与对象上传、仓库容量；不以改 http.postBuffer 或自动改历史冒充修复。' ;;
    *'hook declined'*|*'pre-receive'*|*'pre-push'*|*'remote rejected'*) log '[P16 hook 拒绝] 根据上方本地／服务端 hook 提示修复；保留 hook，不执行 --no-verify。' ;;
    *'cannot lock ref'*|*'.lock'*|*'unable to create'*) log '[P17 锁／引用／磁盘] 先确认并发 Git 与锁归属；如为远端跟踪引用冲突，使用现有 Fetch 修复入口。不自动删锁或改权限。' ;;
    *'ssl certificate'*|*'certificate verification'*|*'host key verification'*|*'remote host identification'*) log '[P18 信任验证] 核对证书、系统时间、SSH 主机指纹及可信来源；不关闭 TLS/SSH 校验。' ;;
    *'resolve host'*|*'resolve hostname'*|*'timed out'*|*'timeout'*|*'connection reset'*|*'connection refused'*|*'broken pipe'*|*'early eof'*|*'rpc failed'*|*'error: 502'*|*'error: 503'*|*'error: 504'*|*'http 502'*|*'http 503'*|*'http 504'*|*'http/2 502'*|*'http/2 503'*|*'http/2 504'*) log '[P19 网络] 有限重试后仍失败；检查 DNS、连接、已有代理及平台状态。脚本不更改系统或全局代理。' ;;
    *'bad object'*|*'corrupt'*|*'missing blob'*|*'unpacker error'*) log '[P20 对象异常] 保留现场，使用 git fsck --full 定位；从可信远端补对象或隔离重克隆，不自动删对象库。' ;;
    *'unable to auto-detect email'*|*'identity unknown'*|*'gpg failed'*|*'signing failed'*) log '[P21 提交身份／签名] 使用本仓自己的正确身份和已有签名配置完成合并；不写伪造身份或关闭签名。' ;;
    *'no space left'*|*'read-only file system'*|*'disk full'*) log '[P22 存储] 检查工作区、Git 目录与临时目录容量／权限，不自动删除文件或递归修改权限。' ;;
    *) log '[P99 未知] 保留上方脱敏原始错误与失败码；依实际错误处理后重跑，未宣称已修复。' ;;
  esac
}
# 只重试明确短暂传输错误，权限／信任／hook 故障立即停止。
is_transient() {
  local message="${1:l}"
  [[ "$message" == *'timed out'* || "$message" == *'timeout'* || "$message" == *'connection reset'* || "$message" == *'broken pipe'* || "$message" == *'early eof'* || "$message" =~ '(HTTP|http|error:)[[:space:]]+(502|503|504)([^0-9]|$)' ]]
}
# 重试只用于读取／获取；推送失败在外层先核验服务端是否已接收。
read_with_retry() {
  local attempt
  for (( attempt=1; attempt<=NETWORK_ATTEMPTS; attempt++ )); do
    run_git "$@" && return 0
    is_transient "$RESULT" || return 1
    (( attempt < NETWORK_ATTEMPTS )) || return 1
    log "短暂网络失败，重试 $((attempt + 1))/$NETWORK_ATTEMPTS。"
    sleep 1
  done
  return 1
}
# 只有 status 成功且无任何条目才允许写操作，错误不得被空 stdout 掩盖。
ensure_clean_worktree() {
  local index_entry
  if ! git -C "$REPO" ls-files -v -z > "$RUN_DIR/index-flags" 2> "$RUN_DIR/index-flags-error"; then
    log "$(<"$RUN_DIR/index-flags-error")"
    fail '[P06] 无法读取索引标志，停止。'
  fi
  while IFS= read -r -d '' index_entry; do
    if [[ "${index_entry[1]}" == S || "${index_entry[1]}" == [a-z] ]]; then
      fail "[P06] 索引存在 skip-worktree／assume-unchanged（可能隐藏本地内容）：${index_entry#??}；先按原 sparse／索引配置审查，不自动清除标志。"
    fi
  done < "$RUN_DIR/index-flags"
  run_git status --ignore-submodules=none --porcelain=v1 --untracked-files=normal || {
    diagnose_failure "$RESULT"
    fail '[P06] 无法可靠读取工作区／索引，停止；不能把读取失败当干净。'
  }
  [[ -z "$RESULT" ]] || fail "[P06] ${1:-存在未提交内容／未跟踪文件／子模块改动；先审查并正常保存后重跑。}"
}
# 检查工作树、未完成操作和锁，避免对已有现场施加第二次修复。
check_repository_state() {
  local key value operation marker
  for key in GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE; do
    value="${(P)key}"
    [[ -z "$value" ]] || fail "检测到 $key 环境覆盖，请在干净终端运行，避免操作错误 Git 状态。"
  done
  REPO="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)" || fail '[P01] 不是可用的普通 Git 工作树（bare 仓库不自动处理）。'
  LOCAL_BRANCH="$(git -C "$REPO" symbolic-ref -q --short HEAD)" || fail '[P02] 游离 HEAD，先在 Sourcetree 选择明确的已有工作分支；不自动建分支。'
  LOCAL_OID="$(git -C "$REPO" rev-parse --verify HEAD 2>/dev/null)" || fail '[P03] 当前分支尚无提交，先审查并正常提交；脚本不自动提交工作区。'
  INITIAL_OID="$LOCAL_OID"
  GIT_DIR_PATH="$(git -C "$REPO" rev-parse --absolute-git-dir)" || fail '无法定位 gitdir。'
  COMMON_DIR="$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)" || fail '无法定位公共 Git 目录。'
  for operation in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply sequencer; do
    marker="$(git -C "$REPO" rev-parse --git-path "$operation")"
    [[ "$marker" == /* ]] || marker="$REPO/$marker"
    [[ ! -e "$marker" ]] || fail "[P04] 存在未完成操作 $operation；先按 git status 完成或明确取消原操作。"
  done
  for marker in "$GIT_DIR_PATH/index.lock" "$GIT_DIR_PATH/HEAD.lock" "$GIT_DIR_PATH/FETCH_HEAD.lock" "$COMMON_DIR/packed-refs.lock" "$COMMON_DIR/config.lock"; do
    [[ ! -e "$marker" ]] || fail "[P05] 检测到锁：$marker。检查持锁进程；脚本保留锁，不根据文件年龄删除。"
  done
  ensure_clean_worktree
  value="$(git -C "$REPO" rev-parse --is-shallow-repository)" || fail '[P07] 无法判断浅克隆状态。'
  [[ "$value" != true ]] || fail '[P07] 浅克隆无法可靠判断全部历史。确认来源后显式补全历史，再重跑。'
  log "[P01–P07] 工作区干净；分支 $LOCAL_BRANCH；HEAD $INITIAL_OID。"
}
# 多候选必须用菜单明确选择；取消或无终端不能猜目标。
choose_candidate() {
  local prompt="$1" selected key header
  local -a menu_options
  shift
  (( APPROVED == 0 )) || fail "$prompt 存在多个候选；--yes 不代替选择，请传入明确 remote／分支。"
  [[ -t 0 ]] || fail "$prompt 存在多个候选，请在终端选择或显式传参。"
  command -v fzf >/dev/null && fzf --version >/dev/null || fail '多候选需要 fzf；准备好后重跑，或显式传入 remote／分支。'
  header="$prompt；方向键／Tab 移动，回车选择"
  menu_options=(--height=40% --border --reverse --bind='tab:down,btab:up')
  if (( MENU_BACK )); then
    menu_options+=(--expect=left)
    header="$header；← 返回上一层"
  fi
  selected="$(printf '%s\n' '取消本轮' "$@" | fzf "${menu_options[@]}" --header="$header")"
  local menu_rc=$?
  if (( MENU_BACK )); then
    key="${selected%%$'\n'*}"
    [[ "$key" != left ]] || return 75
    selected="${selected#*$'\n'}"
  fi
  (( menu_rc == 0 )) || exit 130
  [[ -n "$selected" && "$selected" != '取消本轮' ]] || exit 130
  REPLY="$selected"
}
# 解析唯一且可证明的单线路映射，显式 refspec 优先于 push.default。
resolve_push_target() {
  local candidate upstream_remote upstream_ref spec source destination mirror snapshot raw_specs
  local -a remotes specs targets urls fetch_urls
  remotes=("${(@f)$(git -C "$REPO" remote)}")
  (( ${#remotes} > 0 )) || fail '[P08] 没有 remote，请先添加已确认的仓库地址。'
  upstream_remote="$(git -C "$REPO" config --get "branch.$LOCAL_BRANCH.remote")"
  upstream_ref="$(git -C "$REPO" config --get "branch.$LOCAL_BRANCH.merge")"
  if [[ -z "$REMOTE" ]]; then
    candidate="$(git -C "$REPO" config --get "branch.$LOCAL_BRANCH.pushRemote")"
    [[ -n "$candidate" ]] || candidate="$(git -C "$REPO" config --get remote.pushDefault)"
    [[ -n "$candidate" || "$upstream_remote" == '.' ]] || candidate="$upstream_remote"
    if [[ -n "$candidate" ]]; then
      REMOTE="$candidate"
    elif (( ${#remotes} == 1 )); then
      REMOTE="${remotes[1]}"
    else
      MENU_BACK=0
      choose_candidate '选择唯一推送远端' "${remotes[@]}" || exit 130
      REMOTE="$REPLY"
    fi
  fi
  (( ${remotes[(Ie)$REMOTE]} )) || fail "[P08] 不是已配置的 remote：$REMOTE"
  mirror="$(git -C "$REPO" config --bool --get "remote.$REMOTE.mirror")"
  (( $? <= 1 )) || fail '[P08] mirror 配置无效，先修正本仓配置。'
  [[ "$mirror" != true ]] || fail '[P08] mirror 远端需专用发布流程，本动作不执行镜像推送。'
  snapshot="$(git -C "$REPO" config --get-regexp 'jobs.*[Ss]napshot|[Ss]napshot.*jobs' 2>/dev/null)"
  [[ "$LOCAL_BRANCH" != 'Gitee@snapshot' ]] || fail '[P08] Gitee@snapshot 仅使用已有专用发布链。'
  urls=("${(@f)$(git -C "$REPO" remote get-url --push --all "$REMOTE")}")
  fetch_urls=("${(@f)$(git -C "$REPO" remote get-url --all "$REMOTE")}")
  (( ${#urls} == 1 && ${#fetch_urls} == 1 )) || fail '[P08] 多个 URL 需逐条明确发布流程；不自动选择其中一个。'
  PUSH_URL="${urls[1]}"; FETCH_URL="${fetch_urls[1]}"
  [[ -n "$PUSH_URL" && "$PUSH_URL" != -* ]] || fail '[P08] 无效推送地址。'
  candidate="$(git -C "$REPO" ls-remote --get-url "$PUSH_URL")" || fail '无法展开推送 URL。'
  [[ "$candidate" == "$PUSH_URL" ]] || fail '[P08] URL 重写规则会对已展开地址再次改写，无法冻结同一服务端，请先整理规则。'
  if [[ "$PUSH_URL" == *gitee.com* && ( "$LOCAL_BRANCH" == byPods || -n "$snapshot" ) ]]; then
    fail '[P08] 检测到 Gitee 独立快照线路；请使用原专用发布入口，禁止合并完整历史。'
  fi
  if [[ -z "$BRANCH" ]]; then
    raw_specs="$(git -C "$REPO" config --get-all "remote.$REMOTE.push")"
    specs=()
    [[ -z "$raw_specs" ]] || specs=("${(@f)raw_specs}")
    for spec in "${specs[@]}"; do
      [[ -n "$spec" ]] || continue
      [[ "$spec" != +* && "$spec" != *\** && "$spec" == *:* ]] || fail '[P08] 强制／通配／隐式 refspec 不自动解释，请传明确远端分支。'
      source="${spec%%:*}"; destination="${spec#*:}"
      if [[ "$source" == HEAD || "$source" == "$LOCAL_BRANCH" || "$source" == "refs/heads/$LOCAL_BRANCH" ]]; then
        [[ "$destination" == refs/heads/* ]] || fail '[P08] 目标不是远端工作分支。'
        targets+=("${destination#refs/heads/}")
      fi
    done
    if (( ${#specs} > 0 )); then
      targets=("${(@u)targets}")
      (( ${#targets} == 1 )) || fail '[P08] refspec 无法确定唯一目标；请传明确远端分支。'
      BRANCH="${targets[1]}"
    elif [[ "$upstream_remote" == "$REMOTE" && "$upstream_ref" == refs/heads/* ]]; then
      BRANCH="${upstream_ref#refs/heads/}"
    else
      read_with_retry ls-remote --heads "$PUSH_URL" || { diagnose_failure "$RESULT"; fail '无法查询推送目标。'; }
      targets=()
      while IFS=$'\t' read -r candidate destination; do
        [[ "$destination" == refs/heads/* ]] && targets+=("${destination#refs/heads/}")
      done <<< "$RESULT"
      (( ${targets[(Ie)$LOCAL_BRANCH]} )) && BRANCH="$LOCAL_BRANCH"
      if [[ -z "$BRANCH" ]]; then
        (( ${#targets} > 0 )) || fail '[P08] 空远端：请显式传远端分支，确认创建目标。'
        MENU_BACK=1
        choose_candidate '选择远端分支' "${targets[@]}" || return $?
        BRANCH="$REPLY"
      fi
    fi
  fi
  BRANCH="${BRANCH#refs/heads/}"
  git check-ref-format "refs/heads/$BRANCH" >/dev/null 2>&1 || fail '[P08] 远端分支名非法。'
  [[ "$BRANCH" != 'Gitee@snapshot' ]] || fail '[P08] 不创建远端 Gitee@snapshot 分支。'
  [[ "$LOCAL_BRANCH" != main && "$LOCAL_BRANCH" != byPods || "$PUSH_URL" != *JobsOCBaseConfigDemo* || "$LOCAL_BRANCH" == "$BRANCH" ]] || fail '[P08] OC main／byPods 职责不允许交叉推送。'
  log "[P08 计划] 仓库：$REPO；本地：$LOCAL_BRANCH → $REMOTE/$BRANCH"
  log "推送来源：$PUSH_URL"
  if [[ "$FETCH_URL" != "$PUSH_URL" ]]; then
    log "普通 fetch 地址：$FETCH_URL；本次以真实推送地址读取／获取，避免合并另一仓库。"
  fi
  [[ "$upstream_remote" == "$REMOTE" && "$upstream_ref" == "refs/heads/$BRANCH" ]] || log '上游缺失／不同：使用本次明确映射，不修改现有上游配置。'
}
# 选择分支返回时只重建目标计划，不递归重跑业务。
resolve_target_with_return() {
  local initial_remote="$REMOTE" initial_branch="$BRANCH" selection_rc
  while true; do
    resolve_push_target && return 0
    selection_rc=$?
    (( selection_rc == 75 )) || exit "$selection_rc"
    REMOTE="$initial_remote"
    BRANCH="$initial_branch"
    log '已返回目标选择；没有执行写操作。'
  done
}
# 从真实推送端读取目标 OID；空结果与查询失败明确分开。
query_remote() {
  local oid ref
  REMOTE_OID=""
  read_with_retry ls-remote --refs "$PUSH_URL" "refs/heads/$BRANCH" || return 1
  while IFS=$'\t' read -r oid ref; do
    [[ "$ref" != "refs/heads/$BRANCH" ]] || REMOTE_OID="$oid"
  done <<< "$RESULT"
  [[ -z "$REMOTE_OID" || "$REMOTE_OID" =~ '^[0-9a-f]{40}([0-9a-f]{24})?$' ]]
}
# 只读模式不 fetch、不改索引／配置／引用，不声称已修复。
report_diagnosis() {
  query_remote || { diagnose_failure "$RESULT"; fail '读取服务端失败。'; }
  log "[P09 诊断] 本地 $LOCAL_OID；远端 ${REMOTE_OID:-不存在（需显式确认创建）}。"
  if [[ "$LOCAL_OID" == "$REMOTE_OID" ]]; then
    log '本地与远端相同，无需推送。'
  elif [[ -n "$REMOTE_OID" ]] && git -C "$REPO" cat-file -e "$REMOTE_OID^{commit}" 2>/dev/null; then
    log "独有提交数（本地／远端）：$(git -C "$REPO" rev-list --left-right --count "$LOCAL_OID...$REMOTE_OID")"
  else
    log '远端对象尚不在本地；执行模式会精确获取后判断，当前只读诊断不获取。'
  fi
  log '诊断结束，未执行合并或推送。'
  exit 0
}
# 计划形成后确认写操作；--yes 仅接受调用者显式授权，不隐式设置。
approve_plan() {
  local selection_rc
  (( DIAGNOSE == 0 )) || report_diagnosis
  (( APPROVED == 0 )) || return 0
  [[ -t 0 ]] || fail '执行需要终端计划确认，或显式 --yes。'
  while true; do
    MENU_BACK=1
    choose_candidate '执行此计划？默认取消；合并可能产生提交并推送' '执行安全整合并推送'
    selection_rc=$?
    if (( selection_rc == 75 )); then
      REMOTE=""; BRANCH=""
      resolve_target_with_return
      continue
    fi
    [[ "$REPLY" == '执行安全整合并推送' ]] || exit 130
    return 0
  done
}
# 写操作前取得本工作树互斥锁；锁异常保留并报告。
acquire_lock() {
  local lock_path="$GIT_DIR_PATH/jobs-push-repair.lock"
  mkdir "$lock_path" 2>/dev/null || fail "[P05] 已有修复会话或遗留锁：$lock_path；确认进程退出后人工核对，不自动删除。"
  OWN_LOCK="$lock_path"
  print -r -- "$$" > "$OWN_LOCK/pid"
}
# 预检新增路径和祖先，避免 ort 合并覆盖被忽略文件或沿符号链接写出工作树。
protect_incoming_paths() {
  local merge_base="$1" relative_path candidate parent object_type
  if ! git -C "$REPO" diff --no-renames --diff-filter=A --name-only -z "$merge_base" "$REMOTE_OID" -- > "$RUN_DIR/incoming-paths" 2> "$RUN_DIR/incoming-error"; then
    log "$(<"$RUN_DIR/incoming-error")"
    fail '[P06] 无法可靠检查合并新增路径，停止。'
  fi
  while IFS= read -r -d '' relative_path; do
    candidate="$REPO/$relative_path"
    object_type="$(git -C "$REPO" cat-file -t "HEAD:$relative_path" 2>/dev/null)"
    if [[ ( -e "$candidate" || -L "$candidate" ) && "$object_type" != blob && "$object_type" != commit ]]; then
      fail "[P06] 远端新增路径与本地现有内容碰撞（含 ignored 文件）：$relative_path；先自行妥善保存后重跑。"
    fi
    parent="${candidate:h}"
    while [[ "$parent" != "$REPO" && "$parent" == "$REPO/"* ]]; do
      if [[ -L "$parent" || ( -e "$parent" && ! -d "$parent" ) ]]; then
        fail "[P06] 远端新增路径的祖先被本地文件／链接阻挡：$parent；保留并停止。"
      fi
      parent="${parent:h}"
    done
  done < "$RUN_DIR/incoming-paths"
}
# 精确获取推送目标到 FETCH_HEAD，避开旧 remote-tracking ref 的目录冲突。
integrate_remote() {
  local merge_base remote_before local_before merge_error
  query_remote || { diagnose_failure "$RESULT"; fail '读取远端失败。'; }
  [[ -n "$REMOTE_OID" ]] || { log '[P09] 目标分支不存在，将仅创建本次明确选择的分支。'; return 0; }
  remote_before="$REMOTE_OID"
  read_with_retry fetch --no-tags --no-recurse-submodules --refmap= "$PUSH_URL" "refs/heads/$BRANCH" || { diagnose_failure "$RESULT"; fail '精确 Fetch 失败；引用冲突可另用 Fetch 修复入口。'; }
  REMOTE_OID="$(git -C "$REPO" rev-parse --verify 'FETCH_HEAD^{commit}')" || fail 'FETCH_HEAD 不是有效提交。'
  LOCAL_OID="$(git -C "$REPO" rev-parse HEAD)"
  [[ "$(git -C "$REPO" symbolic-ref -q --short HEAD)" == "$LOCAL_BRANCH" ]] || fail '检测到分支并发切换，停止。'
  ensure_clean_worktree '获取期间工作区被修改，保留并停止。'
  if git -C "$REPO" merge-base --is-ancestor "$REMOTE_OID" HEAD; then
    log '[P09] 远端为本地祖先或两端相同，已满足普通推送条件。'
    return 0
  fi
  merge_base="$(git -C "$REPO" merge-base HEAD "$REMOTE_OID")" || fail '[P23] 无共同祖先；可能为快照或远端重建，不自动 --allow-unrelated-histories。'
  local_before="$LOCAL_OID"
  log "[P09] 独有提交（本地／远端）：$(git -C "$REPO" rev-list --left-right --count "HEAD...$REMOTE_OID")"
  log "整合前 HEAD：$local_before；目标：$REMOTE_OID；共同祖先：$merge_base"
  protect_incoming_paths "$merge_base"
  if git -C "$REPO" merge-base --is-ancestor HEAD "$REMOTE_OID"; then
    run_git -c merge.autostash=false merge --ff-only --no-autostash --no-overwrite-ignore "$REMOTE_OID" || { diagnose_failure "$RESULT"; fail '快进失败，保留现场。'; }
  else
    run_git -c merge.autostash=false merge --ff --no-edit --no-autostash --no-overwrite-ignore "$REMOTE_OID" || {
      merge_error="$RESULT"
      log '[P24] 合并未完成；冲突路径如下（若为空，查看上方身份／签名／hook 错误）。'
      run_git diff --name-only --diff-filter=U
      diagnose_failure "$merge_error"
      fail '在 Sourcetree 审查并解决冲突后正常提交，再运行本入口；不会自动选 ours/theirs 或回滚。'
    }
  fi
  git -C "$REPO" merge-base --is-ancestor "$local_before" HEAD && git -C "$REPO" merge-base --is-ancestor "$REMOTE_OID" HEAD || fail '整合后未保留双方祖先，停止推送。'
  log "整合完成：$(git -C "$REPO" rev-parse HEAD)；原 HEAD 可在 reflog 和本日志核对。"
}
# 仅刷新可证明属于本次线路的跟踪引用，比较旧 OID 防止覆盖并发 fetch。
refresh_tracking_ref() {
  local expected="$1" spec old_oid tracking_ref="refs/remotes/$REMOTE/$BRANCH" matched=0
  [[ "$FETCH_URL" == "$PUSH_URL" ]] || return 0
  while IFS= read -r spec; do
    spec="${spec#+}"
    if [[ "$spec" == "refs/heads/*:refs/remotes/$REMOTE/*" || "$spec" == "refs/heads/$BRANCH:$tracking_ref" ]]; then
      matched=1
    elif [[ "$spec" == ^* ]]; then
      log '存在负向 fetch refspec，保留原跟踪引用，请按仓库原配置刷新。'
      return 0
    fi
  done <<< "$(git -C "$REPO" config --get-all "remote.$REMOTE.fetch")"
  (( matched )) || return 0
  git -C "$REPO" symbolic-ref -q "$tracking_ref" >/dev/null 2>&1 && return 0
  old_oid="$(git -C "$REPO" rev-parse --verify "$tracking_ref" 2>/dev/null)"
  if run_git update-ref -m 'jobs push repair: verified remote tip' "$tracking_ref" "$expected" "$old_oid"; then
    log "已刷新本次远端跟踪引用：$REMOTE/$BRANCH。"
  else
    log '⚠ 服务端推送已核验，但跟踪引用刷新失败（可能锁／引用冲突）；保留错误，请使用 Fetch 修复入口或重新获取。'
  fi
}
# 推送后精确核验；并发非快进有限重试，网络失败先查服务端是否已接受。
repair_and_push() {
  local round push_result push_status expected
  acquire_lock
  for (( round=1; round<=MAX_SYNC_ROUNDS; round++ )); do
    integrate_remote
    expected="$(git -C "$REPO" rev-parse HEAD)"
    ensure_clean_worktree '推送前发现新工作区改动，停止。'
    [[ "$(git -C "$REPO" symbolic-ref -q --short HEAD)" == "$LOCAL_BRANCH" ]] || fail '推送前分支已切换，停止。'
    log "[P10] 普通推送第 $round/$MAX_SYNC_ROUNDS 轮：$expected → $REMOTE/$BRANCH"
    push_status=0
    run_git -c push.followTags=false -c push.recurseSubmodules=no push --porcelain -- "$PUSH_URL" "${expected}:refs/heads/$BRANCH" || push_status=$?
    push_result="$RESULT"
    if query_remote; then
      if [[ "$REMOTE_OID" == "$expected" ]]; then
        [[ "$(git -C "$REPO" rev-parse HEAD)" == "$expected" ]] || fail '服务端已接收，但本地 HEAD 同时变化，未达到最终一致。'
        refresh_tracking_ref "$expected"
        log "✔ [P25 已核验] $REMOTE/$BRANCH = 本地 HEAD = $expected"
        log "完成；仅处理 $REPO 的选定线路。日志：$LOG_FILE"
        return 0
      fi
    else
      diagnose_failure "$RESULT"
      fail '推送后服务端核验失败，不能宣称成功；重跑会先读取并核对远端。'
    fi
    diagnose_failure "$push_result"
    if (( push_status == 0 )) || is_remote_race "$push_result" || is_transient "$push_result"; then
      (( round == MAX_SYNC_ROUNDS )) || continue
    fi
    fail '推送未达到服务端 OID 一致；保留本地提交与现场，按上述分类处理后重跑。'
  done
  fail '远端持续变化或网络持续失败，已达到有限重试上限。'
}
# 编排说明、只读预检、计划确认与安全修复。
main() {
  parse_arguments "$@" # 解析目标与调用者明确传入的执行策略。
  show_script_intro_and_wait # 首先显示用途和影响，再按终端策略确认。
  handoff_if_needed # Sourcetree 不阻塞，交给独立终端执行。
  initialize_runtime # 确认后初始化日志与当前进程选项。
  check_repository_state # 保护已有工作区、操作现场与环境覆盖。
  resolve_target_with_return # 明确唯一推送线路和远端分支，支持菜单逐层返回。
  approve_plan # 先给出可审查计划，再执行或仅诊断。
  repair_and_push # 安全整合并普通推送，服务端核验后才报告完成。
}
main "$@"
