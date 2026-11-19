#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】📦双击打包Flutter.ohos.command
# - 核心用途：使用鸿蒙适配版 Flutter 一次构建 HAP 安装包和 APP 发布包。
# - 影响范围：解析工程依赖、执行 Hvigor 构建并写入构建目录；签名沿用工程配置。
# - 运行提示：先打印内置自述；终端回车确认，Sourcetree 无交互执行；缺少工具链时停止。

# JOBS_ST_OHOS_REQUIRED_BEGIN
# 仅激活当前进程并复检Homebrew，新安装才维护原shellenv块。
jobs_brew_activate() {
  local brew_env
  brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
  eval "$brew_env" || return 1
  typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
  export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
  rehash
  HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || { jobs_brew_note "Homebrew 命令层复检失败，停止后续业务。"; return 1; }
  if [[ "${1:-}" == installed ]]; then
    if [[ "${JOBS_HOMEBREW_INSTALL_MODE:-}" == user && -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
    fi
    # 只刷新本次进程，不向用户 Shell 启动文件写入持久配置。
    :
  fi
}
# 验证既有Homebrew命令真实可执行，不按目录可写性猜安装状态。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 只在缺失时选择系统或用户路径，保留本人原生权限与许可处理。
jobs_brew_choose_installation() {
  local answer="" system_prefix="$(jobs_brew_system_prefix)"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
    jobs_brew_note "缺少 Homebrew，需要人工选择安装路径；请在可交互终端重新运行，未执行安装。"
    return 1
  fi
  print -u2 -r -- "⚠ Homebrew 尚未就绪，必须先选择安装路径："
  print -u2 -r -- "1、输入精确大写 YES：选择系统标准目录 $system_prefix（Apple Silicon：/opt/homebrew；Intel：/usr/local）。"
  print -u2 -r -- "   这表示你准备向系统目录安装；官方安装器可能随后要求管理员密码，并自行验证权限。"
  jobs_prompt_output print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
  print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
  print -u2 -n -r -- "$(jobs_prompt_render "➤ 安装路径选择：")"
  if ! IFS= read -r answer; then
    jobs_brew_note "输入已取消或结束，停止安装。"
    return 1
  fi
  if [[ "$answer" == YES ]]; then
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=system
  else
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=user
  fi
}
# 持续获取声明的官方文件，取消和确定阻塞立即停止。
jobs_brew_download_file() {
  local destination="$1" description="$2" download_url attempt download_result=1 http_code
  local retry_round=0 retry_delay=1 round_has_retryable=0
  local -a request_headers download_urls
  local -A blocked_urls
  shift 2
  download_urls=("$@")
  (( ${#download_urls} > 0 )) || { jobs_brew_note '没有已声明的官方获取地址。'; return 2; }
  while true; do
    (( retry_round += 1 ))
    round_has_retryable=0
    for download_url in "${download_urls[@]}"; do
      [[ -z "${blocked_urls[$download_url]:-}" ]] || continue
      request_headers=()
      if [[ "$download_url" == https://api.github.com/repos/Homebrew/install/contents/install.sh\?ref=HEAD ]]; then
        request_headers=(-H 'Accept: application/vnd.github.raw+json')
      fi
      for attempt in 1 2 3; do
        jobs_brew_note "下载${description}（第 $retry_round 轮，第 $attempt 次）：$download_url"
        download_result=0
        http_code="$(curl -q -fsSL --proto '=https' --proto-redir '=https' \
          --connect-timeout 10 --max-time 30 "${request_headers[@]}" \
          --write-out '%{http_code}' "$download_url" -o "$destination" \
          2> >(tee -a "${LOG_FILE:-/dev/null}" >&2))" || download_result=$?
        if (( download_result == 0 )); then
          return 0
        fi
        rm -f -- "$destination" || return 1
        jobs_brew_note "${description}下载失败：curl 退出码 $download_result，HTTP ${http_code:-未知}。"
        case "$download_result" in
          129|130|143) return "$download_result" ;;
          5|6|7|18|28|35|52|55|56) ;;
          22)
            if [[ "$http_code" != 408 && "$http_code" != 429 && "$http_code" != 5[0-9][0-9] ]]; then
              blocked_urls[$download_url]=1
              break
            fi
            ;;
          *) blocked_urls[$download_url]=1; break ;;
        esac
        if (( attempt < 3 )); then
          jobs_brew_note '临时连接失败，1 秒后重试同一官方地址；Ctrl+C 可取消。'
          sleep 1 || return $?
        fi
      done
      if [[ -z "${blocked_urls[$download_url]:-}" ]]; then
        round_has_retryable=1
      fi
      jobs_brew_note '当前地址尚未取得可用响应；如有下一已声明官方地址，将按原顺序尝试，安装目录不变。'
    done
    if (( round_has_retryable == 0 )); then
      jobs_brew_note "获取${description}遇到确定错误，停止；未执行安装。日志：${LOG_FILE:-终端输出}。"
      return "$download_result"
    fi
    jobs_brew_note "官方来源暂时不可用，${retry_delay} 秒后继续下一轮；不设总次数或总时长上限，按 Ctrl+C 取消。"
    sleep "$retry_delay" || return $?
    if (( retry_delay < 30 )); then
      retry_delay=$(( retry_delay * 2 ))
      (( retry_delay <= 30 )) || retry_delay=30
    fi
  done
}
# 在私有暂存中获取固定官方版本，三路纯日志状态分别检查。
jobs_brew_fetch_release() {
  setopt LOCAL_OPTIONS LOCAL_TRAPS NO_ERREXIT
  local git_bin="$1" release_tag="$2" stage="$3" target="${3}/brew"
  local attempt_log="${3}/git-fetch-attempt.log" history="${3}/git-fetch-history.log"
  local attempt=1 result=0 delay=1 task_pid="" interrupted=0 failure=""
  [[ "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' && "$stage" == /* &&
     "${stage:t}" == .jobs-homebrew.* && -d "$stage" && ! -L "$stage" && ! -e "$target" && ! -L "$target" ]] || {
    jobs_brew_note 'Homebrew 获取版本或私有暂存路径无效，未执行 Git 获取。'
    return 2
  }
  "$git_bin" init --quiet "$target" || { result=$?; jobs_brew_note "Homebrew 暂存仓初始化失败（$result）：$target"; return "$result"; }
  "$git_bin" -C "$target" remote add origin https://github.com/Homebrew/brew.git || return $?
  trap 'interrupted=130; [[ -z "$task_pid" ]] || jobs_brew_stop_acquisition_tree "$task_pid"' INT
  trap 'interrupted=143; [[ -z "$task_pid" ]] || jobs_brew_stop_acquisition_tree "$task_pid"' TERM
  trap 'interrupted=129; [[ -z "$task_pid" ]] || jobs_brew_stop_acquisition_tree "$task_pid"' HUP
  while true; do
    jobs_brew_note "获取 Homebrew 官方版本 $release_tag（第 $attempt 次）：https://github.com/Homebrew/brew.git → $target；失败自动重试，Ctrl+C 取消。"
    : > "$attempt_log" || return 1
    print -r -- "━━ Homebrew $release_tag：第 $attempt 次 ━━" >> "$history" || return 1
    (
      local -a acquisition_statuses
      LC_ALL=C GIT_TERMINAL_PROMPT=0 "$git_bin" -C "$target" -c color.ui=false \
        -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 fetch --progress --depth 1 origin "refs/tags/$release_tag" 2>&1 |
        jobs_prompt_tee "$history" | jobs_prompt_tee "${LOG_FILE:-/dev/null}" | jobs_prompt_tee "$attempt_log" >&2
      acquisition_statuses=("${pipestatus[@]}")
      (( acquisition_statuses[2] == 0 && acquisition_statuses[3] == 0 && acquisition_statuses[4] == 0 )) || exit 74
      exit "${acquisition_statuses[1]}"
    ) <&0 &
    task_pid=$!
    result=0
    wait "$task_pid" || result=$?
    task_pid=""
    (( interrupted == 0 )) || return "$interrupted"
    jobs_brew_note "Homebrew $release_tag 获取第 $attempt 次退出码：$result。"
    if (( result == 0 )); then
      "$git_bin" -C "$target" checkout --quiet --detach FETCH_HEAD || return $?
      return 0
    fi
    case "$result" in
      74) jobs_brew_note "Homebrew 获取日志写入失败，停止；请检查磁盘空间、路径和权限。"; return 74 ;;
      129|130|131|137|143|126|127) return "$result" ;;
    esac
    failure="$(/usr/bin/tail -c 65536 "$attempt_log")" || return 1
    if print -r -- "$failure" | /usr/bin/grep -Eqi \
      'Permission denied|Operation not permitted|No space left on device|Read-only file system|File exists|already exists and is not an empty directory|Bad CPU type|Exec format error|unknown option|unrecognized option|invalid argument|couldn.t find remote ref|Remote branch .* not found|repository .* not found|Authentication failed|could not read Username|terminal prompts disabled|HTTP[^[:cntrl:]]*(401|403|404)|returned error: (401|403|404)|SSL certificate problem|certificate verify failed|unable to get local issuer certificate'; then
      jobs_brew_note "Homebrew 官方版本获取遇到本地、认证、证书或版本确定错误（$result），已停止；请核对日志：${LOG_FILE:-$history}。"
      return "$result"
    fi
    jobs_brew_note "Homebrew 网络获取尚未完成，保留本轮已收对象，${delay} 秒后继续；不设总次数或总时长上限，Ctrl+C 取消。"
    sleep "$delay" &
    task_pid=$!
    wait "$task_pid" || { result=$?; (( interrupted == 0 )) || return "$interrupted"; return "$result"; }
    task_pid=""
    (( interrupted == 0 )) || return "$interrupted"
    (( attempt += 1 ))
    (( delay >= 30 )) || delay=$(( delay * 2 ))
    (( delay <= 30 )) || delay=30
  done
}
# 只读发现可复用的健康Homebrew，不重装既有缓存。
jobs_brew_find() {
  local candidate
  local -a candidates
  candidates=("${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew
    "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew")
  for candidate in "${candidates[@]}"; do
    if jobs_brew_candidate_ok "$candidate"; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}
# 复用健康Homebrew，必要安装失败立即停止业务。
jobs_brew_install_or_exit() {
  local installed=""
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
    return 0
  fi
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    jobs_required_clt_tool git >&2 || return $?
    jobs_brew_choose_installation || exit 1
    case "$JOBS_HOMEBREW_INSTALL_MODE" in
      system) jobs_brew_install_system || jobs_brew_stop_failed_install $? ;;
      user) jobs_brew_install_user || jobs_brew_stop_failed_install $? ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}
# 校验官方安装器后仅执行一次，下载失败不切换安装位置。
jobs_brew_install_system() {
  local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
  if jobs_brew_download_file "$installer" 'Homebrew 官方安装器' \
      https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
      'https://api.github.com/repos/Homebrew/install/contents/install.sh?ref=HEAD'; then
    if [[ ! -s "$installer" || "$(head -n 1 "$installer")" != '#!/bin/bash' ]] || ! /bin/bash -n "$installer"; then
      rm -f -- "$installer"
      jobs_brew_note '官方安装器响应为空或内容校验失败（可能是 HTML / JSON 错误页）；未执行安装。'
      return 1
    fi
  else
    installer_result=$?
    rm -f -- "$installer"
    jobs_brew_note "系统目录安装器下载失败（curl 退出码 $installer_result）；尚未执行安装，不自动切换安装路径。"
    return "$installer_result"
  fi
  /bin/bash "$installer" || installer_result=$?
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return "$installer_result"
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 将校验过的固定官方版本发布到用户目录，不覆盖非空目标。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin release_result=0
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
    jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
    return 1
  }
  if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
    jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
    return 1
  fi
  local git_health=1 locate_result=0 git_candidate="" selected_developer="" clt_result=0 clt_diagnostic=""
  git_bin="$(command -v git 2>/dev/null)"
  # /usr/bin/git 可能只是CLT占位器；先查询真实工具，避免健康检查自行弹出安装窗口。
  if [[ "$git_bin" == /usr/bin/git || -z "$git_bin" ]]; then
    git_bin="$(/usr/bin/xcrun --find git 2>/dev/null)" || locate_result=$?
    case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
  fi
  if [[ -n "$git_bin" && -x "$git_bin" ]]; then
    git_health=0;"$git_bin" --version >/dev/null 2>&1 || git_health=$?
    case "$git_health" in 129|130|131|137|143) return "$git_health" ;; esac
  fi
  if (( git_health != 0 )); then
    [[ -z "${DEVELOPER_DIR:-}" ]] || { jobs_brew_note '显式DEVELOPER_DIR没有健康Git，保留用户开发目录，未自动改全局选择。'; return 1; }
    locate_result=0
    selected_developer="$(/usr/bin/xcode-select -p 2>/dev/null)" || locate_result=$?
    case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
    if [[ -n "$selected_developer" && -d "$selected_developer" ]]; then
      jobs_brew_note "既有开发目录未提供健康Git：$selected_developer；可能是许可、版本或本地文件阻塞，未反复安装或改全局xcode-select。"
      return 1
    fi
    if [[ "${DRY_RUN:-0}" == 1 || "${CHECK_ONLY:-0}" == 1 || ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]] ||
       env | LC_ALL=C /usr/bin/grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
      jobs_brew_note '用户目录Homebrew需要健康Git；当前为只读或非交互入口，未打开CLT安装窗口或写安装目标。'
      return 1
    fi
    jobs_brew_note '当前已选用户目录Homebrew安装需要Apple Command Line Tools的Git；只打开一次原生安装窗口，许可由本人处理，当前流程持续复检，Ctrl+C停止。' || return $?
    clt_diagnostic="$(/usr/bin/xcode-select --install 2>&1)" || clt_result=$?
    jobs_brew_note "$clt_diagnostic" || return $?
    if (( clt_result != 0 )) && [[ "$clt_diagnostic" != *'already being installed'* && "$clt_diagnostic" != *'正在安装'* ]]; then return "$clt_result"; fi
    while true; do
      locate_result=0
      git_candidate="$(/usr/bin/xcrun --find git 2>/dev/null)" || locate_result=$?
      case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
      if [[ -n "$git_candidate" && -x "$git_candidate" ]]; then
        git_health=0;"$git_candidate" --version >/dev/null 2>&1 || git_health=$?
        case "$git_health" in 129|130|131|137|143) return "$git_health" ;; esac
        if (( git_health == 0 )); then git_bin="$git_candidate";break;fi
      fi
      jobs_brew_note '等待Apple CLT提供健康Git；不会重复打开窗口，Ctrl+C停止。' || return $?
      /bin/sleep 3 || return $?
    done
  fi
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
  export HOMEBREW_NO_SUDO=1
  mkdir -p "${prefix:h}" || return 1
  stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
  if jobs_brew_download_file "$stage/release.json" 'Homebrew 官方稳定版本' \
      https://api.github.com/repos/Homebrew/brew/releases/latest; then
    release_result=0
  else
    release_result=$?
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本已停止（退出码 $release_result），未执行安装。"
    return "$release_result"
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    rm -r -- "$stage"
    jobs_brew_note '官方版本响应无有效 tag，停止；不重试版本解析或执行安装。'
    return 1
  fi
  if jobs_brew_fetch_release "$git_bin" "$release_tag" "$stage"; then
    release_result=0
  else
    release_result=$?
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 官方版本获取已停止（退出码 $release_result），未执行安装。"
    return "$release_result"
  fi
  if ! "$git_bin" -C "$stage/brew" checkout -b stable ||
     ! "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
     ! mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var"; then
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 用户目录初始化失败，停止安装。"
    return 1
  fi
  # 空目录也只在下载成功后移除，避免提前改动用户的目标目录。
  if [[ -d "$prefix" ]] && ! rmdir -- "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  if ! mv "$stage/brew" "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  rm -r -- "$stage"
  typeset -g JOBS_HOMEBREW_BIN="$prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "用户目录安装后复检失败：$prefix"; return 1; }
}
# 将Homebrew准备诊断写入当前人类展示与纯文本日志。
jobs_brew_note() {
  jobs_prompt_output print -u2 -r -- "ℹ $*"
  if [[ "${_JOBS_ENV_LOG_READY:-0}" == 1 && -n "${LOG_FILE:-}" ]]; then
    print -r -- "ℹ $*" >> "$LOG_FILE"
  fi
  return 0
}
# 只清理本次获取创建的子进程树，不影响无关SDK写者。
jobs_brew_stop_acquisition_tree() {
  local root="$1" child=""
  for child in $(/usr/bin/pgrep -P "$root" 2>/dev/null); do
    jobs_brew_stop_acquisition_tree "$child"
  done
  /bin/kill -TERM "$root" 2>/dev/null || true
  /bin/kill -KILL "$root" 2>/dev/null || true
}
# 用户取消保留信号码，其它失败停止外层业务。
jobs_brew_stop_failed_install() {
  case "$1" in
    129|130|143) exit "$1" ;;
    *) exit 1 ;;
  esac
}
# 计算当前系统架构对应的原生Homebrew目录。
jobs_brew_system_prefix() {
  case "$(/usr/bin/uname -m)" in
    arm64) print -r -- /opt/homebrew ;;
    *) print -r -- /usr/local ;;
  esac
}
# 将精确FVM安装与SDK探针接回既有持续获取和来源保护协议。
jobs_flutter_sdk_command() {
  local executable="$1" action="${2:-}" version="${3:-}"
  if [[ "${executable:t}" == fvm && "$action" == install && -n "$version" ]]; then
    shift 3
    jobs_flutter_fvm_install '工程精确FVM SDK' "$LOG_FILE" "$executable" "$version" "$@"
    return $?
  fi
  if [[ "${executable:t}" == fvm ]]; then
    jobs_flutter_fvm_runtime 'FVM管理器必要Dart运行时' "$LOG_FILE" "$executable" || return $?
    "$@"
    return $?
  fi
  jobs_flutter_sdk_retry '工程SDK必要准备' "$LOG_FILE" '' '' "$@"
}
# 仅为工具健康探针设单次上限，下载获取使用持续重试。
jobs_fzf_bounded_probe() {
  local child=0 watchdog=0 result=0
  "$@" <&0 &
  child=$!
  ( /bin/sleep 10; jobs_brew_stop_acquisition_tree "$child" ) >/dev/null 2>&1 &
  watchdog=$!
  wait "$child" || result=$?
  jobs_brew_stop_acquisition_tree "$watchdog"
  wait "$watchdog" 2>/dev/null || :
  return "$result"
}
# 把依赖诊断送往当前业务日志，避免混入机器结果。
jobs_fzf_note() {
  if (( ${+functions[jobs_prompt_output]} )); then
    jobs_prompt_output print -u2 -r -- "$*"
  else
    print -u2 -r -- "$*"
  fi
  if [[ -n "${LOG_FILE:-}" ]]; then print -r -- "$*" >> "$LOG_FILE"; fi
}
# 只重试必需获取的临时故障，取消及权限、版本、镜像确定错误停止。
jobs_required_acquire() {
  local label="$1" result=0 log_result=0 attempt=0 delay=1 offset=0 output_log="${LOG_FILE:-${TMPDIR:-/tmp}/JobsRequired.$$.log}"
  shift
  local -a results
  while true; do
    (( attempt += 1 ))
    jobs_fzf_note "➤ $label｜第 $attempt 次；网络失败持续重试，Ctrl+C 停止。日志：$output_log" || return $?
    : >> "$output_log" || return $?
    offset="$(/usr/bin/wc -c < "$output_log")" || return $?
    "$@" 2>&1 | jobs_required_sanitize | jobs_prompt_tee "$output_log" >&2
    results=("${pipestatus[@]}")
    result=${results[1]}
    for log_result in "${results[@]:1}"; do (( log_result == 0 )) || { (( result == 0 )) && return "$log_result"; return "$result"; }; done
    (( result != 0 )) || return 0
    case "$result" in 126|127|129|130|137|143) return "$result" ;; esac
    if /usr/bin/tail -c +$((offset + 1)) "$output_log" | /usr/bin/tail -c 65536 | /usr/bin/grep -Eqi 'Permission denied|Operation not permitted|No space left|No available formula|No formulae found|File exists|unsupported|not supported|requires Ruby version|Failed to build gem native extension|Gem::Ext::BuildError|cannot create executables|missing.*(header|compiler)|Xcode license|incompatible|Invalid option|Unknown command|No matching|Could not find.*gem|license.*(not accepted|rejected)|authentication failed|certificate.*(invalid|verify failed)|HTTP[^[:cntrl:]]*(401|403|404)|returned error: (401|403|404)|SSL certificate problem|certificate verify failed'; then
      jobs_fzf_note "✖ $label 遇到确定的权限、版本、许可或本地阻塞，退出码 $result；未继续业务。" || return $?
      return "$result"
    fi
    jobs_fzf_note "⚠ $label 未完成，$delay 秒后重试；Ctrl+C 结束。" || return $?
    /bin/sleep "$delay" || return $?
    (( delay >= 30 )) || delay=$(( delay * 2 > 30 ? 30 : delay * 2 ))
  done
}
# 只获取当前职责需要的精确包，结束后由调用方复检。
jobs_required_brew_package() {
  local package="$1" kind="${2:-formula}" action=install
  jobs_brew_install_or_exit >&2 || return $?
  local brew="${JOBS_HOMEBREW_BIN:-}" prefix=""
  [[ -n "$brew" ]] || return 1
  prefix="$("$brew" --prefix)" || return $?
  export PATH="$prefix/bin:$prefix/sbin:$PATH"; rehash
  local list_result=0
  HOMEBREW_NO_AUTO_UPDATE=1 "$brew" list "--$kind" --versions "$package" >/dev/null 2>&1 || list_result=$?
  case "$list_result" in 129|130|131|137|143) return "$list_result" ;; esac
  (( list_result != 0 )) || action=reinstall
  jobs_fzf_note "来源：Homebrew 官方目录｜包：$package｜目标：$prefix；仅本次进程刷新 PATH，不执行全局升级。" || return $?
  jobs_required_acquire "必需工具 $package" /usr/bin/env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 "$brew" "$action" "--$kind" "$package"
}
# 复用所选Apple开发工具；缺失才单次原生准备，取消不触发安装。
jobs_required_clt_tool() {
  local tool="$1" candidate="" selected="" install_result=0 diagnostic="" probe_result=0 locate_result=0
  locate_result=0
  candidate="$(/usr/bin/xcrun --find "$tool" 2>/dev/null)" || locate_result=$?
  case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    probe_result=0;jobs_fzf_bounded_probe "$candidate" --version </dev/null >/dev/null 2>&1 || probe_result=$?
    case "$probe_result" in 129|130|131|137|143) return "$probe_result" ;; esac
    (( probe_result != 0 )) || { JOBS_REQUIRED_COMMAND="$candidate"; return 0; }
  fi
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then jobs_fzf_note "✖ 显式 DEVELOPER_DIR 的 $tool 不可用；保留用户选择，未自动改变开发目录。"; return 1; fi
  locate_result=0;selected="$(/usr/bin/xcode-select -p 2>/dev/null)" || locate_result=$?
  case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
  if [[ -n "$selected" && -d "$selected" ]]; then
    jobs_fzf_note "✖ 已选择的开发目录 $selected 未提供健康 $tool；可能是版本、许可或本地文件阻塞。保留原选择，未反复安装或改全局 xcode-select。"
    return 1
  fi
  if [[ "${DRY_RUN:-0}" == 1 || "${CHECK_ONLY:-0}" == 1 ]]; then print -u2 -r -- "✖ $tool 尚未就绪；只读模式未打开安装界面。"; return 1; fi
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then print -u2 -r -- "✖ 缺少 $tool，当前不是可交互终端，未打开或等待原生安装界面。"; return 1; fi
  jobs_fzf_note "➤ $tool 需要 Apple Command Line Tools；将打开一次原生安装窗口，许可由本人确认，安装后当前流程自动复检，Ctrl+C 停止。" || return $?
  diagnostic="$(/usr/bin/xcode-select --install 2>&1)" || install_result=$?
  jobs_fzf_note "$diagnostic" || return $?
  if (( install_result != 0 )) && [[ "$diagnostic" != *'already being installed'* && "$diagnostic" != *'正在安装'* ]]; then return "$install_result"; fi
  while true; do
    locate_result=0
    candidate="$(/usr/bin/xcrun --find "$tool" 2>/dev/null)" || locate_result=$?
    case "$locate_result" in 129|130|131|137|143) return "$locate_result" ;; esac
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      probe_result=0;jobs_fzf_bounded_probe "$candidate" --version </dev/null >/dev/null 2>&1 || probe_result=$?
      case "$probe_result" in 129|130|131|137|143) return "$probe_result" ;; esac
      (( probe_result != 0 )) || { JOBS_REQUIRED_COMMAND="$candidate"; rehash; return 0; }
    fi
    jobs_fzf_note "等待 Apple 原生安装完成并提供 $tool；不会重复打开窗口，Ctrl+C 取消。" || return $?
    /bin/sleep 3 || return $?
  done
}
# 复用真实健康命令，必要获取后复检并保留原生取消码。
jobs_required_command() {
  local tool="$1" package="$2" kind="$3" candidate="" probe_result=0; shift 3
  candidate="$(command -v -- "$tool" 2>/dev/null)"
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    if [[ "$tool" == fvm ]]; then jobs_flutter_fvm_runtime "FVM所需Dart运行时" "$LOG_FILE" "$candidate" || return $?; fi
    jobs_fzf_bounded_probe "$candidate" "$@" </dev/null >/dev/null 2>&1 || probe_result=$?
    (( probe_result != 0 )) || { JOBS_REQUIRED_COMMAND="${candidate:A}"; return 0; }
    case "$probe_result" in 129|130|131|137|143) return "$probe_result" ;; esac
  fi
  jobs_required_brew_package "$package" "$kind" || return $?
  if [[ "$kind" == formula ]]; then
    local package_prefix="$("$JOBS_HOMEBREW_BIN" --prefix "$package")" || return $?
    [[ "$package_prefix" != /* || ! -d "$package_prefix/bin" ]] || export PATH="$package_prefix/bin:$PATH"
  fi
  rehash; candidate="$(command -v -- "$tool" 2>/dev/null)"; probe_result=0
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    jobs_fzf_bounded_probe "$candidate" "$@" </dev/null >/dev/null 2>&1 || probe_result=$?
    (( probe_result != 0 )) || { JOBS_REQUIRED_COMMAND="${candidate:A}"; return 0; }
    case "$probe_result" in 129|130|131|137|143) return "$probe_result" ;; esac
  fi
  jobs_fzf_note "✖ $package 获取后 $tool 仍未通过当前进程健康检查，未继续业务。" || return $?
  return 1
}
# 记录真实项目FVM声明指纹，发现并发变化就停止。
jobs_required_fvm_fingerprint() {
  local project="$1" file=""
  for file in "$project/.fvmrc" "$project/.fvm/fvm_config.json"; do
    if [[ -f "$file" ]]; then /usr/bin/shasum -a 256 "$file" || return $?;
    elif [[ -e "$file" || -L "$file" ]]; then return 1;
    else print -r -- 'ABSENT'; fi
  done
}
# 读取项目FVM版本、来源与缓存；影子配置不写真实项目。
jobs_required_fvm_json() {
  /usr/bin/osascript -l JavaScript - "$@" <<'JOBS_FVM_REQUIRED_JSON'
  ObjC.import('Foundation');
  function read(file) {
    var error=Ref();
    var text=$.NSString.stringWithContentsOfFileEncodingError($(file), $.NSUTF8StringEncoding, error);
    if(!text) throw Error('JSON 文件不可读：'+file);
    return JSON.parse(ObjC.unwrap(text).replace(/^\uFEFF/,''));
  }
  function run(args) {
    var mode=args.shift(), values=[], key, result='';
    if(mode==='shadow') {
      var target=args[0], legacy=args[1], config={};
      if($.NSFileManager.defaultManager.fileExistsAtPath($(target))) config=read(target);
      else if($.NSFileManager.defaultManager.fileExistsAtPath($(legacy))) config=read(legacy);
      config.flutter=args[4]; config.cachePath=args[2]; config.flutterUrl=args[3];
      if(!$(JSON.stringify(config,null,2)).writeToFileAtomicallyEncodingError($(target),true,$.NSUTF8StringEncoding,null)) throw Error('影子配置写入失败');
      return 'shadow-ready';
    }
    if(mode==='binding' || mode==='bindingSource') {
      args.forEach(function(file) {
        if(!file || !$.NSFileManager.defaultManager.fileExistsAtPath($(file))) return;
        var object=read(file), value=mode==='binding' ? (object.flutter || object.flutterSdkVersion) : (object.flutterUrl || object.flutter_url || object.flutterGitUrl);
        if(value!==undefined && value!==null && String(value).length) values.push(String(value));
      });
      if(values.some(function(value){return value!==values[0];})) throw Error('两份 FVM 声明不一致，未猜测版本或来源');
      return values.length ? values[0] : '';
    }
    if(mode==='machine') {
      var text=ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError($(args[0]),$.NSUTF8StringEncoding,null)).replace(/^\uFEFF/,'');
      for(var i=0;i<text.length;i++) { if(text[i]!=='{') continue;try{var data=JSON.parse(text.substring(i));if(data.frameworkVersion)return String(data.frameworkVersion);}catch(error){} }
      throw Error('Flutter 实际版本响应无法验证');
    }
    var root=read(args[0]), context=root.context;
    if(!context || typeof context!=='object') throw Error('FVM context API 不可验证');
    if(mode==='cacheRoot') {
      if(typeof context.cachePath==='string' && context.cachePath.length) return context.cachePath;
      if(typeof context.versionsCachePath==='string' && /\/versions\/?$/.test(context.versionsCachePath)) return context.versionsCachePath.replace(/\/versions\/?$/,'');
      throw Error('FVM API 没有可验证的缓存根目录，未猜测环境变量路径');
    }
    key=mode==='cache' ? 'versionsCachePath' : 'flutterUrl';
    result=context[key];
    if(typeof result!=='string' || !result.length || /[\r\n]/.test(result)) throw Error('FVM context 缺少有效 '+key);
    return result;
  }
JOBS_FVM_REQUIRED_JSON
}
# 在影子工程准备明确版本和同源缓存，不修改真实绑定或回退PATH。
jobs_required_fvm_project() {
  local project="${1:A}" version="" declared_source="" source="" cache="" cache_root="" before="" after="" stage="" sdk="" actual="" git_bin="" fvm_bin="" config=""
  JOBS_REQUIRED_FLUTTER=""
  before="$(jobs_required_fvm_fingerprint "$project")" || return $?
  version="$(jobs_required_fvm_json binding "$project/.fvmrc" "$project/.fvm/fvm_config.json")" || return $?
  declared_source="$(jobs_required_fvm_json bindingSource "$project/.fvmrc" "$project/.fvm/fvm_config.json")" || return $?
  (( ${+functions[jobs_flutter_sdk_command]} )) || { jobs_fzf_note '✖ 缺少随包 SDK 获取适配器定义，未开始准备。'; return 127; }
  local bound_sdk="$project/.fvm/flutter_sdk"
  if [[ -x "$bound_sdk/bin/flutter" && -e "$bound_sdk/bin/dart" ]]; then
    jobs_required_clt_tool git || return $?
    git_bin="$JOBS_REQUIRED_COMMAND"
    stage="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsFvmRequired.XXXXXXXX")" || return $?
    {
      jobs_flutter_sdk_command "$bound_sdk/bin/flutter" --version --machine > "$stage/sdk-machine.json" || return $?
      actual="$(jobs_required_fvm_json machine "$stage/sdk-machine.json")" || return $?
      if [[ "$version" =~ '^v?[0-9]+\.[0-9]+\.[0-9]+([+.-][A-Za-z0-9.-]+)?$' && "${actual#v}" != "${version#v}" ]]; then jobs_fzf_note '✖ 已绑定 SDK 的实际版本与工程明确版本不符，未安装替代 SDK 或改绑定。'; return 1; fi
      if [[ -n "$declared_source" ]]; then
        local bound_source="$("$git_bin" -C "$bound_sdk" config --get remote.origin.url)" || return $?
        [[ "${${bound_source%/}%.git}" == "${${declared_source%/}%.git}" ]] || { jobs_fzf_note '✖ 已绑定 SDK 的实际来源与工程声明不符，未替换用户 SDK。'; return 1; }
      fi
      [[ "$(jobs_required_fvm_fingerprint "$project")" == "$before" ]] || { jobs_fzf_note '✖ SDK 体检期间真实声明发生变化，未继续业务。'; return 1; }
      JOBS_REQUIRED_FLUTTER="${bound_sdk:A}/bin/flutter"
      return 0
    } always {
      if [[ -n "$stage" && "${stage:t}" == JobsFvmRequired.* && -d "$stage" ]]; then /bin/rm -r -- "$stage"; fi
    }
  fi
  if [[ ! "$version" =~ '^v?[0-9]+\.[0-9]+\.[0-9]+([+.-][A-Za-z0-9.-]+)?$' && "$version" != (stable|beta|main|master) ]]; then
    jobs_fzf_note '✖ 缺失的 FVM SDK 没有可验证的明确版本/channel 声明；未猜版本、未获取其它 SDK 或改写绑定。'
    return 1
  fi
  jobs_required_clt_tool git || return $?
  git_bin="$JOBS_REQUIRED_COMMAND"
  local existing_fvm="$(command -v fvm 2>/dev/null)"
  if [[ -n "$existing_fvm" && -x "$existing_fvm" ]]; then
    # Dart shim 的外部运行时也交给既有 SDK 选路，不让首次 --version 绕过持续获取。
    jobs_flutter_sdk_command "$existing_fvm" --version >/dev/null || return $?
  fi
  jobs_required_command fvm fvm formula --version || return $?
  fvm_bin="$JOBS_REQUIRED_COMMAND"
  stage="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsFvmRequired.XXXXXXXX")" || return $?
  {
    ( builtin cd "$project" && "$fvm_bin" api context --compress ) > "$stage/context-before.json" || return $?
    cache="$(jobs_required_fvm_json cache "$stage/context-before.json")" || return $?
    cache_root="$(jobs_required_fvm_json cacheRoot "$stage/context-before.json")" || return $?
    source="$(jobs_required_fvm_json source "$stage/context-before.json")" || return $?
    if [[ -n "${JOBS_OHOS_FVM_EXPECTED_SOURCE:-}" && "${${source%/}%.git}" != "${${JOBS_OHOS_FVM_EXPECTED_SOURCE%/}%.git}" ]]; then
      jobs_fzf_note "✖ FVM实际来源与已明确鸿蒙fork不一致，未获取其它SDK或改绑定。"
      return 2
    fi
    [[ "$cache" == /* && "$cache" != / && "$cache_root" == /* && "$cache_root" != / ]] || { jobs_fzf_note '✖ FVM 未提供绝对缓存目录，未执行安装。'; return 1; }
    if [[ -n "$declared_source" && "${declared_source%/}" != "${source%/}" ]]; then jobs_fzf_note '✖ FVM 实际来源与工程声明不一致，未切换下载源或继续安装。'; return 1; fi
    /bin/mkdir -p "$stage/project/.fvm" || return $?
    print -r -- $'name: jobs_required_sdk\ndependencies:\n  flutter:\n    sdk: flutter' > "$stage/project/pubspec.yaml" || return $?
    for config in .fvmrc .fvm/fvm_config.json; do
      [[ ! -f "$project/$config" ]] || /bin/cp "$project/$config" "$stage/project/$config" || return $?
    done
    jobs_required_fvm_json shadow "$stage/project/.fvmrc" "$stage/project/.fvm/fvm_config.json" "$cache_root" "$source" "$version" > /dev/null || return $?
    ( builtin cd "$stage/project" && FVM_CACHE_PATH="$cache_root" FVM_FLUTTER_URL="$source" "$fvm_bin" api context --compress ) > "$stage/context-shadow.json" || return $?
    [[ "$(jobs_required_fvm_json cache "$stage/context-shadow.json")" == "$cache" && "$(jobs_required_fvm_json source "$stage/context-shadow.json")" == "$source" ]] || {
      jobs_fzf_note '✖ 影子项目没有保留实际缓存目录或来源，未开始 SDK 下载。'; return 1
    }
    sdk="$cache/$version"
    local needs_install=1 remote=""
    if [[ -x "$sdk/bin/flutter" && -e "$sdk/bin/dart" ]]; then
      remote="$("$git_bin" -C "$sdk" config --get remote.origin.url)" || return $?
      [[ "${${remote%/}%.git}" == "${${source%/}%.git}" ]] || { jobs_fzf_note '✖ 现有同版本缓存来自其它 Git 来源；保留缓存，未覆盖或换源。'; return 1; }
      needs_install=0
    fi
    jobs_fzf_note "➤ 准备工程声明 FVM SDK：$version；来源：$(print -r -- "$source" | jobs_required_sanitize)；缓存：$cache；真实项目配置不写入。" || return $?
    if (( needs_install )); then
      ( builtin cd "$stage/project" && FVM_CACHE_PATH="$cache_root" FVM_FLUTTER_URL="$source" jobs_flutter_sdk_command "$fvm_bin" install "$version" ) || return $?
    else
      jobs_fzf_note '✔ 复用已存在的精确 FVM SDK；不重复执行安装。' || return $?
    fi
    after="$(jobs_required_fvm_fingerprint "$project")" || return $?
    [[ "$after" == "$before" ]] || { jobs_fzf_note '✖ FVM 准备期间真实声明发生变化，未覆盖并发修改或继续业务。'; return 1; }
    ( builtin cd "$project" && "$fvm_bin" api context --compress ) > "$stage/context-after.json" || return $?
    [[ "$(jobs_required_fvm_json cache "$stage/context-after.json")" == "$cache" && "$(jobs_required_fvm_json source "$stage/context-after.json")" == "$source" ]] || {
      jobs_fzf_note '✖ FVM 准备前后缓存或来源不一致，未使用不明确 SDK。'; return 1
    }
    sdk="$cache/$version"
    [[ -x "$sdk/bin/flutter" && -e "$sdk/bin/dart" ]] || { jobs_fzf_note '✖ FVM 返回成功但精确缓存未包含完整 Flutter/Dart 入口；未删除已有缓存或换其它版本。'; return 1; }
    remote="$("$git_bin" -C "$sdk" config --get remote.origin.url)" || return $?
    [[ "${${remote%/}%.git}" == "${${source%/}%.git}" ]] || { jobs_fzf_note '✖ 已获取 SDK 的实际 Git 来源与声明不符，未执行该 SDK。'; return 1; }
    ( builtin cd "$stage/project" && jobs_flutter_sdk_command "$sdk/bin/flutter" --version --machine ) > "$stage/sdk-machine.json" || return $?
    actual="$(jobs_required_fvm_json machine "$stage/sdk-machine.json")" || return $?
    if [[ "$version" != (stable|beta|main|master) && "${actual#v}" != "${version#v}" ]]; then jobs_fzf_note '✖ 实际 Flutter 版本与明确声明不一致，未继续业务。'; return 1; fi
    [[ "$(jobs_required_fvm_fingerprint "$project")" == "$before" ]] || { jobs_fzf_note '✖ SDK 复检期间真实工程声明发生变化，未继续业务。'; return 1; }
    JOBS_REQUIRED_FLUTTER="${sdk:A}/bin/flutter"
    return 0
  } always {
    if [[ -n "$stage" && "${stage:t}" == JobsFvmRequired.* && -d "$stage" ]]; then /bin/rm -r -- "$stage"; fi
  }
}
# 清除控制码并隐藏依赖输出中的凭据和敏感地址。
jobs_required_sanitize() {
  /usr/bin/perl -pe 's{([a-zA-Z][a-zA-Z0-9+.-]*://)[^/\s]*@}{$1***@}g; s{((?:https?|ssh|git|file)://[^\s?#]+)[?#][^\s]*}{$1?[REDACTED]}g'
}
# 缺少必要工具时才交给真实终端，原参数、工作目录和已解析目标均按数据传递。
jobs_required_terminal_handoff() {
  local entry="$1" target="$2" origin="$3" directory='' worker='' result=0 argument='' environment_key=''
  shift 3
  if [[ "${JOBS_REQUIRED_TOOL_TERMINAL:-0}" == 1 ]]; then
    print -u2 -r -- '✖ 工具准备终端不可交互，停止；未再次启动窗口。'
    return 1
  fi
  [[ -f "$entry" && -e "$target" && -d "$origin" ]] || return 2
  directory="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsRequiredTerminal.XXXXXX")" || return $?
  worker="$directory/准备必要工具.command"
  {
    print -rl -- '#!/bin/zsh' 'umask 077'
    print -r -- 'worker_self="${0:A}"'
    print -r -- 'cleanup_worker() { /bin/rm -f -- "$worker_self"; /bin/rmdir -- "${worker_self:h}" 2>/dev/null || :; }'
    print -r -- 'trap cleanup_worker EXIT'
    print -r -- 'export JOBS_REQUIRED_TOOL_TERMINAL=1 IS_SOURCETREE_RUNTIME=0'
    for environment_key in JAVA_HOME JENV_ROOT JENV_VERSION DEVELOPER_DIR JOBS_HOMEBREW_INSTALL_PREFIX GEM_HOME GEM_PATH GEMRC BUNDLE_GEMFILE RBENV_ROOT RBENV_VERSION RUBYOPT FLUTTER_OHOS_SDK DEVECO_STUDIO_HOME TOOL_HOME DEVECO_SDK_HOME HOS_SDK_HOME OHOS_SDK_HOME NODE_HOME HARMONY_CLT_ARCHIVE JOBS_HARMONY_TOOLS_HOME FVM_FLUTTER_URL FVM_CACHE_PATH; do
      if (( ${+parameters[$environment_key]} )); then
        printf 'export %s=%q\n' "$environment_key" "${(P)environment_key}"
      fi
    done
    printf 'export REPO=%q\n' "$target"
    printf 'cd -- %q || exit $?\n' "$origin"
    printf '/bin/zsh %q' "$entry"
    for argument in "$@"; do printf ' %q' "$argument"; done
    print -rl -- '' 'worker_result=$?' 'exit "$worker_result"'
  } > "$worker" || result=74
  if (( result == 0 )); then /bin/chmod 700 "$worker" || result=$?; fi
  if (( result == 0 )); then
    /usr/bin/osascript - "$worker" <<'JOBS_REQUIRED_TERMINAL_APPLESCRIPT' || result=$?
on run argv
    tell application "Terminal"
        activate
        do script (quoted form of (item 1 of argv))
    end tell
end run
JOBS_REQUIRED_TERMINAL_APPLESCRIPT
  fi
  if (( result != 0 )); then
    /bin/rm -f -- "$worker"
    /bin/rmdir -- "$directory" 2>/dev/null || :
    return "$result"
  fi
  print -u2 -r -- '已转交终端准备必要工具；原动作未安装或打开目标，最终结果请查看新终端。'
  return 20
}
# 先验证固定镜像大小、快照摘要和归档路径，再允许解压。
hs_validate_clt_archive() {
  local archive="$1" actual="" listing=""
  actual="$(/usr/bin/stat -f %z "$archive")" || return 1
  [[ "$actual" == "$HS_CLT_SIZE" ]] || { hs_error 'SDL 工具包大小不符，未解压。'; return 1; }
  actual="$(/usr/bin/shasum -a 256 "$archive")" || return 1
  [[ "${actual%% *}" == "$HS_CLT_SHA256" ]] || { hs_error 'SDL 工具包 SHA-256 不符，未解压；请核对下载版本。'; return 1; }
  listing="$(/usr/bin/unzip -Z1 "$archive")" || return 1
  print -r -- "$listing" | /usr/bin/awk '
    !/^(command-line-tools|__MACOSX)\// || /(^|\/)\.\.?(\/|$)/ || /\\/ || /\/\// || /[[:cntrl:]]/ { bad=1 }
    END { exit bad }
  ' || { hs_error 'SDL 工具包包含不安全路径，未解压。'; return 1; }
}
# 原子发布本次已验证目录，目标存在时拒绝覆盖或嵌入。
hs_publish_clt() {
  /usr/bin/osascript -l JavaScript - "$1" "$2" <<'JXA'
ObjC.import('Foundation');
function run(args) {
  var error = Ref();
  if (!$.NSFileManager.defaultManager.moveItemAtPathToPathError(args[0], args[1], error)) {
    throw Error('CLT 目录发布失败；不会覆盖或嵌入已有目录。');
  }
}
JXA
}
# 只清理本轮私有.install暂存，保留旧缓存与发布目标。
hs_cleanup_install() {
  if [[ -n "$HS_INSTALL_STAGE" && "$HS_INSTALL_STAGE" == "$HS_TOOLS_HOME"/.install.* && -d "$HS_INSTALL_STAGE" && ! -L "$HS_INSTALL_STAGE" ]]; then
    /bin/rm -rf -- "$HS_INSTALL_STAGE"
  fi
  HS_INSTALL_STAGE=""
}
# 校验并发布固定镜像的构建工具与SDK，不下载系统镜像或创建设备。
hs_perform_clt_install() {
  local publish_result=0 stage="$HS_INSTALL_STAGE" archive="${HARMONY_CLT_ARCHIVE:-}" root="" entry="" destination=""
  hs_log "📥 SDL 第三方免登录镜像：$HS_CLT_URL"
  hs_log "ℹ CLT $HS_CLT_VERSION；$HS_CLT_SIZE 字节；快照 SHA-256：$HS_CLT_SHA256"
  hs_log 'ℹ 该摘要固定 SDL 镜像内容，不代表已比对华为官方摘要；包内不含可启动的系统镜像。'
  if [[ -n "$archive" ]]; then
    [[ -f "$archive" ]] || { hs_error 'HARMONY_CLT_ARCHIVE 指定的文件不存在。'; return 1; }
    hs_log "ℹ 使用本地归档：$archive"
  else
    archive="$stage/tools.zip"
    hs_download_clt_archive "$archive" || return $?
  fi
  hs_validate_clt_archive "$archive" || return $?
  hs_log '✔ 工具包校验通过，正在解压依赖；这一步可能需要几分钟。'
  /bin/mkdir "$stage/extract" || return $?
  # macOS bsdtar 默认拒绝目录穿越及经符号链接写出解压根目录。
  /usr/bin/tar -xf "$archive" -C "$stage/extract" --no-same-owner --no-same-permissions || return $?
  root="$stage/extract/command-line-tools"
  [[ -d "$root" && ! -L "$root" && -x "$root/emulator/Emulator" && ! -L "$root/emulator/Emulator" && -f "$root/version.txt" ]] || {
    hs_error 'SDL 包缺少完整 Emulator 或版本文件，未安装。'; return 1
  }
  for entry in "$root"/**/*(ND@); do
    [[ "${entry:A}" == "${root:A}"/* ]] || { hs_error '工具包存在指向安装目录外的符号链接，未安装。'; return 1; }
  done
  HS_BIN="$root/emulator/Emulator"
  [[ -d "$root/sdk/default/openharmony/ets" && -d "$root/sdk/default/openharmony/native" && -x "$root/sdk/default/openharmony/toolchains/hdc" ]] || {
    hs_error 'CLT 包缺少真机所需 OpenHarmony SDK，未安装。'; HS_BIN=""; return 1
  }
  destination="$HS_TOOLS_HOME/clt-$HS_CLT_VERSION-${${stage:t}#.install.}"
  hs_publish_clt "$root" "$destination" || { publish_result=$?; HS_BIN=""; return "$publish_result"; }
  HS_BIN="$destination/emulator/Emulator"
  HARMONY_EMULATOR_BIN="$HS_BIN"
  hs_log "✔ SDL 工具依赖已安装并通过能力复检：$destination"
}
# 以私有暂存持有本轮安装，失败和取消均回收本轮现场。
hs_install_clt() {
  setopt LOCAL_TRAPS
  local result=0
  trap 'hs_cleanup_install; return 130' INT
  trap 'hs_cleanup_install; return 143' TERM
  trap 'hs_cleanup_install; return 129' HUP
  [[ ! -L "$HS_TOOLS_HOME" && ( ! -e "$HS_TOOLS_HOME" || -d "$HS_TOOLS_HOME" ) ]] || { hs_error '工具安装根目录不是普通目录，停止。'; return 1; }
  /bin/mkdir -p "$HS_TOOLS_HOME" || return 1
  HS_INSTALL_STAGE="$(umask 077; /usr/bin/mktemp -d "$HS_TOOLS_HOME/.install.XXXXXX")" || return 1
  hs_perform_clt_install || result=$?
  hs_cleanup_install
  return "$result"
}
# 先显示包内完整许可，由本人明确同意后才调用原生接受命令。
hs_review_licenses() {
  (( ! HS_LICENSES_CONFIRMED )) || return 0
  local directory="${HS_BIN:h}/agreement" file="" answer=""
  local -a files=("$directory/HarmonyOS_SDK_Agreement.txt" "$directory/HarmonyOS_Software_Service_Agreement.txt")
  for file in "${files[@]}"; do
    [[ -s "$file" && -r "$file" ]] || { hs_error "找不到可供阅读的官方许可：$file；未接受许可。"; return 1; }
  done
  for file in "${files[@]}"; do
    hs_log "━━━━━━━━━━ 官方许可原文：$file ━━━━━━━━━━"
    /bin/cat "$file" || return $?
    print
  done
  IFS= read -r "answer?$(jobs_prompt_render '阅读以上全部协议后，回车表示本人同意并继续；任意非空输入取消：')" || return 130
  [[ -z "$answer" ]] || return 130
  hs_run_command -license accept || return $?
  HS_LICENSES_CONFIRMED=1
}
# 固定镜像下载只负责文件与原生状态；重试、纯日志与取消由上层获取器持有。
hs_download_clt_archive_once() {
  local destination="$1"
  /usr/bin/curl -q --fail --show-error --location --progress-bar --retry 3 --connect-timeout 20 \
    --continue-at - --max-time 3600 --speed-limit 1024 --speed-time 90 --max-filesize "$HS_CLT_SIZE" \
    --proto "=https" --proto-redir "=https" --output "$destination" "$HS_CLT_URL"
}
# 只复用或准备工程明确的鸿蒙SDK；缺失未知来源时停止，绝不获取普通Flutter代替。
jobs_st_required_ohos_flutter() {
  local candidate='' source='' probe_result=0 sdk_root='' JOBS_OHOS_FVM_EXPECTED_SOURCE=''
  if [[ -n "$SDK_OVERRIDE" ]]; then
    SDK_OVERRIDE="$(normalize_input_path "$SDK_OVERRIDE")"
    [[ -x "$SDK_OVERRIDE/bin/flutter" ]] || { error_echo "指定SDK中没有可执行bin/flutter：$SDK_OVERRIDE；保留显式选择。"; return 1; }
    candidate="${SDK_OVERRIDE:A}/bin/flutter"
  elif [[ -f "$PROJECT_ROOT/.fvmrc" || -f "$PROJECT_ROOT/.fvm/fvm_config.json" || -e "$PROJECT_ROOT/.fvm/flutter_sdk" || -L "$PROJECT_ROOT/.fvm/flutter_sdk" ]]; then
    candidate="$PROJECT_ROOT/.fvm/flutter_sdk/bin/flutter"
    if [[ ! -x "$candidate" ]]; then
      source="$(jobs_required_fvm_json bindingSource "$PROJECT_ROOT/.fvmrc" "$PROJECT_ROOT/.fvm/fvm_config.json")" || return $?
      [[ -n "$source" ]] || source="${FVM_FLUTTER_URL:-}"
      if [[ -z "$source" || "${${source%/}%.git}" == (https://github.com/flutter/flutter|git@github.com:flutter/flutter) ]]; then
        error_echo '缺失的FVM SDK没有可验证的鸿蒙fork来源；请明确项目flutterUrl或--flutter-sdk，未猜普通Flutter版本或来源。'
        return 2
      fi
      JOBS_OHOS_FVM_EXPECTED_SOURCE="$source"
    fi
    if [[ "${IS_SOURCETREE_RUNTIME:-0}" == 1 || ! -t 0 || ! -t 2 ]]; then
      if ! jobs_st_sdk_runtime_ready "$candidate"; then
        jobs_st_handoff_required "$PROJECT_ROOT" || return $?
      fi
      CHECK_ONLY=1 jobs_required_clt_tool git || probe_result=$?
      case "$probe_result" in 129|130|131|137|143) return "$probe_result" ;; esac
      if (( probe_result != 0 )); then jobs_st_handoff_required "$PROJECT_ROOT" || return $?; fi
    fi
    jobs_required_fvm_project "$PROJECT_ROOT" || return $?
    candidate="$JOBS_REQUIRED_FLUTTER"
  else
    candidate="$(whence -p flutter 2>/dev/null)"
    [[ -n "$candidate" && -x "$candidate" ]] || {
      error_echo '没有已选择的鸿蒙Flutter SDK；请明确--flutter-sdk或FLUTTER_OHOS_SDK，未安装普通Flutter作为替代。'
      return 2
    }
  fi
  sdk_root="${candidate:A:h:h}"
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == 1 || ! -t 0 || ! -t 2 ]]; then
    if [[ -d "$sdk_root/bin/internal" ]] && ! jobs_st_sdk_runtime_ready "$candidate"; then
      jobs_st_handoff_required "$PROJECT_ROOT" || return $?
    fi
  fi
  FLUTTER_CMD=("${candidate:A}")
  info_echo "Flutter命令：${(j: :)FLUTTER_CMD}；HAP/APP能力在构建前复检，不切换来源。"
}
# 交接保留本轮已解析工程和原始参数；成功交接后原进程停止全部项目业务。
jobs_st_handoff_required() {
  local project="$1" result=0
  jobs_required_terminal_handoff "$SCRIPT_PATH" "$project" "$JOBS_ST_ORIGINAL_CWD" "${JOBS_ST_ORIGINAL_ARGS[@]}" || result=$?
  (( result != 20 )) || exit 0
  return "$result"
}
# 只探测当前选择的SDK缓存，不执行下载、替代来源或项目配置写入。
jobs_st_sdk_runtime_ready() {
  local candidate="$1" sdk="${1:A:h:h}" engine=''
  [[ -x "$candidate" && -x "$sdk/bin/cache/dart-sdk/bin/dart" ]] || return 1
  engine="$sdk/bin/cache/engine.stamp"
  [[ -f "$engine" ]] || engine="$sdk/bin/internal/engine.version"
  [[ -s "$engine" && -f "$sdk/bin/cache/engine-dart-sdk.stamp" ]] || return 1
  /usr/bin/cmp -s "$engine" "$sdk/bin/cache/engine-dart-sdk.stamp"
}
# 复检当前DevEco/PATH的真实命令；取消不变成缺工具，缺失与损坏分开报告。
jobs_ohos_toolchain_health() {
  local tool='' candidate='' result=0 java_home=''
  [[ -n "${DEVECO_SDK_HOME:-}" && -d "$DEVECO_SDK_HOME" ]] || return 3
  for tool in node npm ohpm java hvigorw; do
    candidate="$(whence -p -- "$tool" 2>/dev/null)"
    [[ -n "$candidate" && -x "$candidate" ]] || return 3
    if [[ "$tool" == java && "$candidate" == /usr/bin/java ]]; then
      result=0
      java_home="$(/usr/libexec/java_home 2>/dev/null)" || result=$?
      case "$result" in 129|130|131|137|143) return "$result" ;; esac
      [[ -n "$java_home" && -x "$java_home/bin/java" ]] || return 3
      candidate="$java_home/bin/java"
    fi
    result=0
    if [[ "$tool" == java ]]; then
      jobs_fzf_bounded_probe "$candidate" -version </dev/null >/dev/null 2>&1 || result=$?
    else
      jobs_fzf_bounded_probe "$candidate" --version </dev/null >/dev/null 2>&1 || result=$?
    fi
    (( result == 0 )) || return "$result"
  done
}
# 只有隐式环境确实缺失时准备固定镜像工具包；不覆盖显式SDK/DevEco或猜其它架构制品。
prepare_deveco_environment() {
  local result=0 explicit="${DEVECO_STUDIO_HOME:-}${TOOL_HOME:-}${DEVECO_SDK_HOME:-}${HOS_SDK_HOME:-}${OHOS_SDK_HOME:-}${NODE_HOME:-}${JAVA_HOME:-}"
  if jobs_ohos_locate_deveco_environment; then
    jobs_ohos_toolchain_health || result=$?
    (( result != 0 )) || return 0
    case "$result" in 129|130|131|137|143) return "$result" ;; esac
    (( result == 3 )) || { error_echo "现选工具链健康探针失败（$result），保留来源，不重装其它版本。"; return "$result"; }
  else
    result=$?
    (( result == 3 )) || return "$result"
  fi
  [[ -z "$explicit" ]] || { error_echo '显式DevEco/SDK/Node/Java选择缺少完整工具；保留配置，未安装其它版本覆盖。'; return 1; }
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == 1 || ! -t 0 || ! -t 2 ]]; then
    jobs_st_handoff_required "$PROJECT_ROOT" || return $?
  fi
  jobs_ohos_install_clt_tools || return $?
  export TOOL_HOME="${HS_BIN:h:h}"
  DEVECO_CONTENTS=''
  jobs_ohos_locate_deveco_environment || return $?
  jobs_ohos_toolchain_health || { result=$?; error_echo "镜像工具准备后仍未通过完整命令复检（$result），未运行项目业务。"; return "$result"; }
}
# 固定SDL快照沿用既有大小/摘要/安全解压/发布/许可协议；不安装镜像或启动模拟器。
jobs_ohos_install_clt_tools() {
  [[ "$(/usr/bin/uname -m)" == arm64 ]] || {
    error_echo '现有已验证镜像为Mac ARM64 CLT 6.1.1.280；当前架构不匹配，未猜下载地址或切换官网。'
    return 2
  }
  HS_CLT_VERSION='6.1.1.280'
  HS_CLT_URL='https://libsdl.org/harmonyos-devtools/commandline-tools-mac-arm64-6.1.1.280.zip'
  HS_CLT_SIZE=2025336267
  HS_CLT_SHA256='47d0e558b8285e1452f4d3611863027ec0d1135642761bef23402434e22382d4'
  HS_TOOLS_HOME="${JOBS_HARMONY_TOOLS_HOME:-$HOME/Library/Application Support/JobsHarmonySimulator}"
  HS_LOG="$LOG_FILE"; HS_TOOLS_ONLY=1; HS_BIN=''; HS_INSTALL_STAGE=''; HS_LICENSES_CONFIRMED=0
  hs_install_clt || return $?
  hs_review_licenses || return $?
  jobs_ohos_prepare_required_java || return $?
  [[ -x "$HS_BIN" ]] || { error_echo 'CLT发布后没有可复检入口，未运行项目业务。'; return 1; }
}
# Harmony工具诊断进入既有完整消息与纯文本日志通道，不混入机器回执。
hs_log() {
  info_echo "$*"
}
# Harmony工具失败记录原因并保留失败状态。
hs_error() {
  error_echo "$*"
  return 1
}
# 明确许可确认后运行原工具的接受命令，保留原生状态及日志失败。
hs_run_command() {
  local -a results
  "$HS_BIN" "$@" 2>&1 | jobs_prompt_tee "$HS_LOG"
  results=("${pipestatus[@]}")
  (( results[2] == 0 )) || return 74
  return "${results[1]}"
}
# 只对已选SDL工具包的临时获取故障持续重试，沿用本流程可取消SDK获取器。
hs_download_clt_archive() {
  jobs_required_acquire 'Harmony CLT固定镜像' hs_download_clt_archive_once "$@"
}
# 固定CLT未附JDK时才准备既有17基线；健康用户Java不升级，显式选择不覆盖。
jobs_ohos_prepare_required_java() {
  local candidate='' home="${JAVA_HOME:-}" root="${HS_BIN:h:h}" result=0 prefix='' known_home=0
  if [[ -n "$home" ]]; then
    [[ -x "$home/bin/java" ]] || { error_echo "显式JAVA_HOME没有java：$home；未覆盖。"; return 1; }
    candidate="$home/bin/java"; known_home=1
  else
    for home in "$root/jbr/Contents/Home" "$root/jbr" "$root/jre/Contents/Home"; do
      [[ ! -x "$home/bin/java" ]] || { candidate="$home/bin/java"; known_home=1; break; }
    done
    if [[ -z "$candidate" ]]; then
      candidate="$(whence -p java 2>/dev/null)"
      if [[ "$candidate" == /usr/bin/java ]]; then
        home="$(/usr/libexec/java_home 2>/dev/null)" || result=$?
        case "$result" in 129|130|131|137|143) return "$result" ;; esac
        if [[ -n "$home" && -x "$home/bin/java" ]]; then candidate="$home/bin/java"; known_home=1; else candidate=''; fi
      fi
    fi
  fi
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    result=0
    jobs_fzf_bounded_probe "$candidate" -version </dev/null >/dev/null 2>&1 || result=$?
    (( result == 0 )) || return "$result"
    (( ! known_home )) || export JAVA_HOME="$home"
    export PATH="${candidate:h}:$PATH"
    rehash
    return 0
  fi
  jobs_required_brew_package openjdk@17 formula || return $?
  prefix="$("$JOBS_HOMEBREW_BIN" --prefix openjdk@17)" || return $?
  home="$prefix/libexec/openjdk.jdk/Contents/Home"
  [[ -x "$home/bin/java" && -x "$home/bin/javac" ]] || { error_echo 'JDK17准备后缺少同源java/javac，未运行构建。'; return 1; }
  jobs_fzf_bounded_probe "$home/bin/java" -version </dev/null >/dev/null 2>&1 || return $?
  jobs_fzf_bounded_probe "$home/bin/javac" -version </dev/null >/dev/null 2>&1 || return $?
  export JAVA_HOME="$home" PATH="$home/bin:$PATH"
  rehash
}

# JOBS_ST_OHOS_REQUIRED_END
# >>> Jobs terminal style protection v1 >>>
# 临时保护当前终端配色，业务进程自行管理原有退出清理。
jobs_terminal_style_run() {
    # 无法可靠保存原色时，沿用脚本已有的纯文本约定。
    jobs_terminal_style_plain() {
        PLAIN_OUTPUT=1
        NO_COLOR=1
        FORCE_COLOR=0
        CLICOLOR=0
        ANSI_COLORS_DISABLED=1
        npm_config_color=false
        export PLAIN_OUTPUT NO_COLOR FORCE_COLOR CLICOLOR ANSI_COLORS_DISABLED npm_config_color
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    }
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] ||
       [ "${TERM:-}" = dumb ] || [ "${NO_COLOR+x}" = x ] ||
       [ "${PLAIN_OUTPUT:-0}" = 1 ] || [ "${IS_SOURCETREE_RUNTIME:-0}" = 1 ] ||
       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    fi
    if [ -n "${TMUX:-}${STY:-}" ]; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_tty=$(tty 2>/dev/null) || jobs_terminal_style_plain "$@"
    if ! ps -o pgid= -o tpgid= -p "$$" 2>/dev/null |
         LC_ALL=C awk 'NF == 2 && $1 == $2 && $1 > 0 { foreground = 1 } END { exit !foreground }'; then
        jobs_terminal_style_plain "$@"
    fi
    case ${JOBS_TERMINAL_STYLE_OWNER:-} in
        ''|*[!0-9]*) ;;
        *)
            if [ "${JOBS_TERMINAL_STYLE_TTY:-}" = "$jobs_style_tty" ] &&
               kill -0 "$JOBS_TERMINAL_STYLE_OWNER" 2>/dev/null; then
                if "$@"; then
                    jobs_style_exit_status=0
                else
                    jobs_style_exit_status=$?
                fi
                exit "$jobs_style_exit_status"
            fi
            ;;
    esac
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_terminal_style_plain "$@"
    jobs_style_saved=''
    jobs_style_saved_rows=''
    jobs_style_original_rows=''
    jobs_style_applied_rows=''
    jobs_style_changed=0
    jobs_style_applied_complete=0
    jobs_style_query_active=0
    jobs_style_recovery=''
    jobs_style_exit_status=0
    jobs_style_esc=$(printf '\033')
    jobs_style_bel=$(printf '\007')
    # 完整颜色帧有界重发；设置核验与退出恢复容忍帧外回车和明确方向键。
    jobs_terminal_style_query() {
        jobs_style_query_key=$1
        jobs_style_reply=''
        jobs_style_query_buffer=''
        jobs_style_query_target_reply=''
        jobs_style_query_target_normalized=''
        jobs_style_query_target_rgb=''
        jobs_style_query_st="${jobs_style_esc}\\"
        jobs_style_query_stale_count=0
        jobs_style_query_phase=${2:-strict}
        jobs_style_query_cr=$(printf '\r')
        jobs_style_query_lf=$(printf '\n.')
        jobs_style_query_lf=${jobs_style_query_lf%.}
        jobs_style_query_failure='未收到目标颜色的完整答复（最多 3 次查询，每次约 2 秒）'
        for jobs_style_query_round in 1 2 3; do
            printf '\033]%s;?\007' "$jobs_style_query_key" > /dev/tty || {
                jobs_style_query_failure='无法向原终端发送配色查询'
                return 1
            }
            for jobs_style_attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
                # 哨兵保留末尾换行，不能把只有回车的键盘输入误当成无答复。
                jobs_style_piece=$(dd bs=256 count=1 2>/dev/null < /dev/tty; printf '.')
                jobs_style_piece=${jobs_style_piece%.}
                jobs_style_query_buffer=$jobs_style_query_buffer$jobs_style_piece
                while [ -n "$jobs_style_query_buffer" ]; do
                    # 设置核验与退出恢复阶段允许帧外的明确控制键，普通文字仍然失败。
                    if [ "$jobs_style_query_phase" = cleanup ] || [ "$jobs_style_query_phase" = applied ]; then
                        jobs_style_query_control_sequence=''
                        jobs_style_query_control_partial=0
                        case $jobs_style_query_buffer in
                            "$jobs_style_query_cr"*) jobs_style_query_control_sequence=$jobs_style_query_cr ;;
                            "$jobs_style_query_lf"*) jobs_style_query_control_sequence=$jobs_style_query_lf ;;
                        esac
                        if [ -z "$jobs_style_query_control_sequence" ]; then
                            for jobs_style_query_direction in A B C D; do
                                for jobs_style_query_control_candidate in \
                                    "${jobs_style_esc}[${jobs_style_query_direction}" \
                                    "${jobs_style_esc}O${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;2${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;3${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;4${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;5${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;6${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;7${jobs_style_query_direction}" \
                                    "${jobs_style_esc}[1;8${jobs_style_query_direction}"; do
                                    case $jobs_style_query_buffer in
                                        "$jobs_style_query_control_candidate"*)
                                            jobs_style_query_control_sequence=$jobs_style_query_control_candidate
                                            break 2
                                            ;;
                                    esac
                                    case $jobs_style_query_control_candidate in
                                        "$jobs_style_query_buffer"*) jobs_style_query_control_partial=1 ;;
                                    esac
                                done
                            done
                        fi
                        if [ -n "$jobs_style_query_control_sequence" ]; then
                            jobs_style_phase_control_keys=$(( ${jobs_style_phase_control_keys:-0} + 1 ))
                            if [ "$jobs_style_phase_control_keys" -gt 64 ]; then
                                jobs_style_query_failure='本阶段已识别控制键超过 64 个，已停止自动恢复'
                                return 1
                            fi
                            jobs_style_query_buffer=${jobs_style_query_buffer#"$jobs_style_query_control_sequence"}
                            continue
                        fi
                        if [ "$jobs_style_query_control_partial" = 1 ]; then
                            break
                        fi
                    fi
                    case $jobs_style_query_buffer in
                        "$jobs_style_esc"|"$jobs_style_esc]") break ;;
                        "$jobs_style_esc]"*) ;;
                        *) jobs_style_query_failure='收到非配色查询输入，已停止读取'; return 1 ;;
                    esac
                    jobs_style_query_head=''
                    jobs_style_query_terminator=''
                    case $jobs_style_query_buffer in
                        *"$jobs_style_bel"*)
                            jobs_style_query_head=${jobs_style_query_buffer%%"$jobs_style_bel"*}
                            jobs_style_query_terminator=$jobs_style_bel
                            ;;
                    esac
                    case $jobs_style_query_buffer in
                        *"$jobs_style_query_st"*)
                            jobs_style_query_st_head=${jobs_style_query_buffer%%"$jobs_style_query_st"*}
                            if [ -z "$jobs_style_query_terminator" ] ||
                               [ "${#jobs_style_query_st_head}" -lt "${#jobs_style_query_head}" ]; then
                                jobs_style_query_head=$jobs_style_query_st_head
                                jobs_style_query_terminator=$jobs_style_query_st
                            fi
                            ;;
                    esac
                    [ -n "$jobs_style_query_terminator" ] || break
                    jobs_style_query_frame=$jobs_style_query_head$jobs_style_query_terminator
                    jobs_style_query_buffer=${jobs_style_query_buffer#"$jobs_style_query_frame"}
                    jobs_style_query_body=${jobs_style_query_head#"$jobs_style_esc]"}
                    case $jobs_style_query_body in
                        *';rgb:'*) ;;
                        *) jobs_style_query_failure='配色答复格式或 RGB 数据无效'; return 1 ;;
                    esac
                    jobs_style_query_frame_key=${jobs_style_query_body%%';rgb:'*}
                    case $jobs_style_query_frame_key in
                        10|11|12|'4;'[0-9]|'4;1'[0-5]) ;;
                        *) jobs_style_query_failure='收到不属于本次颜色协议的答复'; return 1 ;;
                    esac
                    jobs_style_query_frame_rgb=${jobs_style_query_body#"$jobs_style_query_frame_key;rgb:"}
                    jobs_style_query_frame_normalized=$(printf '%s\n' "$jobs_style_query_frame_rgb" | LC_ALL=C awk -F/ '
                        BEGIN { valid = 1 }
                        NR != 1 || NF != 3 { valid = 0; exit }
                        {
                            for (i = 1; i <= 3; i++) {
                                h = tolower($i)
                                if (length(h) < 1 || length(h) > 4 || h ~ /[^0-9a-f]/) {
                                    valid = 0
                                    exit
                                }
                                n = 0
                                for (j = 1; j <= length(h); j++) n = n * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
                                value[i] = int(n * 65535 / (16 ^ length(h) - 1) + 0.5)
                            }
                        }
                        END {
                            if (!valid || NR != 1) exit 1
                            printf "%d/%d/%d", value[1], value[2], value[3]
                        }
                    ')
                    if [ -z "$jobs_style_query_frame_normalized" ]; then
                        jobs_style_query_failure='配色答复格式或 RGB 数据无效'
                        return 1
                    fi
                    if [ "$jobs_style_query_frame_key" = "$jobs_style_query_key" ]; then
                        if [ -n "$jobs_style_query_target_reply" ] &&
                           [ "$jobs_style_query_target_normalized" != "$jobs_style_query_frame_normalized" ]; then
                            jobs_style_query_failure='同一颜色的重复答复不一致，已停止自动恢复'
                            return 1
                        fi
                        jobs_style_query_target_reply=$jobs_style_query_frame
                        jobs_style_query_target_normalized=$jobs_style_query_frame_normalized
                        jobs_style_query_target_rgb=$jobs_style_query_frame_rgb
                    else
                        jobs_style_query_stale_count=$((jobs_style_query_stale_count + 1))
                        if [ "$jobs_style_query_stale_count" -gt 128 ]; then
                            jobs_style_query_failure='收到过多旧颜色答复，已停止读取'
                            return 1
                        fi
                    fi
                done
                if [ -n "$jobs_style_query_target_reply" ] && [ -z "$jobs_style_query_buffer" ]; then
                    jobs_style_reply=$jobs_style_query_target_reply
                    jobs_style_normalized=$jobs_style_query_target_normalized
                    jobs_style_rgb=$jobs_style_query_target_rgb
                    return 0
                fi
            done
            # 残缺帧不能通过重发拼成另一个答复，更不能被当成键盘空输入。
            if [ -n "$jobs_style_query_buffer" ]; then
                jobs_style_query_failure='配色答复帧不完整，已停止自动恢复'
                return 1
            fi
        done
        return 1
    }
    # 查询可用不代表终端允许改色，按目标值核对实际生效结果。
    jobs_terminal_style_accepts_target() {
        jobs_style_requested_hex=''
        case $1 in
            10|12) jobs_style_requested_hex=ffffff ;;
            11) jobs_style_requested_hex=000000 ;;
            '4;'*)
                jobs_style_requested_index=0
                for jobs_style_requested_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
                    if [ "4;$jobs_style_requested_index" = "$1" ]; then
                        jobs_style_requested_hex=$jobs_style_requested_color
                        break
                    fi
                    jobs_style_requested_index=$((jobs_style_requested_index + 1))
                done
                ;;
        esac
        [ -n "$jobs_style_requested_hex" ] || return 1
        printf '%s|%s\n' "$jobs_style_normalized" "$jobs_style_requested_hex" | LC_ALL=C awk -F'|' '
            function hexbyte(h) {
                return (index("0123456789abcdef", substr(h, 1, 1)) - 1) * 16 + index("0123456789abcdef", substr(h, 2, 1)) - 1
            }
            {
                if (split($1, actual, "/") != 3 || length($2) != 6) exit 1
                for (i = 1; i <= 3; i++) {
                    difference = actual[i] - hexbyte(substr($2, i * 2 - 1, 2)) * 257
                    if (difference < -255 || difference > 255) exit 1
                }
            }
        '
    }
    # 核验中断时重新读取当前值，只撤回仍等于本轮目标值的颜色。
    jobs_terminal_style_rollback() {
        jobs_style_rollback_issue='无法读取或设置原终端输入模式'
        jobs_style_rollback_safe=''
        jobs_style_rollback_conflicts=''
        jobs_style_phase_control_keys=0
        jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
        if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
            jobs_style_query_active=1
            jobs_style_rollback_ok=1
            while IFS='|' read -r jobs_style_key jobs_style_original_normalized jobs_style_original; do
                [ -n "$jobs_style_key" ] || continue
                if ! jobs_terminal_style_query "$jobs_style_key" cleanup; then
                    jobs_style_rollback_ok=0
                    jobs_style_rollback_issue="回退颜色项 $jobs_style_key：$jobs_style_query_failure"
                    break
                fi
                if [ "$jobs_style_normalized" = "$jobs_style_original_normalized" ]; then
                    continue
                elif jobs_terminal_style_accepts_target "$jobs_style_key"; then
                    jobs_style_rollback_safe=$jobs_style_rollback_safe$jobs_style_original
                else
                    jobs_style_rollback_conflicts="$jobs_style_rollback_conflicts $jobs_style_key"
                fi
            done <<JOBS_STYLE_ROLLBACK
$jobs_style_original_rows
JOBS_STYLE_ROLLBACK
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_rollback_ok=0; jobs_style_rollback_issue='无法恢复原终端输入模式'; }
            jobs_style_query_active=0
            if [ "$jobs_style_rollback_ok" = 1 ] && printf '%s\033[0m' "$jobs_style_rollback_safe" > /dev/tty; then
                if [ -z "$jobs_style_rollback_conflicts" ]; then
                    rm -f "$jobs_style_recovery"
                    rmdir "${jobs_style_recovery%/*}" 2>/dev/null || :
                    return 0
                fi
                printf '检测到运行期间的配色变更，已保留这些项：%s\n' "$jobs_style_rollback_conflicts" >&2
                jobs_style_rollback_issue="核验中断后检测到其它配色变更：$jobs_style_rollback_conflicts"
            fi
        fi
        printf '终端配色未能安全自动恢复（%s）；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_rollback_issue" "$jobs_style_recovery" >&2
        return 1
    }
    # 检测到后续改色时只恢复仍由本次保护持有的项，保留独立恢复入口。
    jobs_terminal_style_cleanup() {
        jobs_style_result=$1
        trap '' HUP INT TERM
        if [ "$jobs_style_query_active" = 1 ]; then
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || :
            jobs_style_query_active=0
        fi
        if [ "$jobs_style_changed" = 1 ] && [ "$jobs_style_applied_complete" != 1 ]; then
            if jobs_terminal_style_rollback; then
                jobs_style_changed=0
            else
                [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
            fi
            if [ "${2:-}" = continue ]; then
                jobs_style_cleanup_status=$jobs_style_result
                return 0
            fi
            exit "$jobs_style_result"
        fi
        if [ "$jobs_style_changed" = 1 ]; then
            jobs_style_cleanup_ok=0
            jobs_style_cleanup_issue='无法读取或设置原终端输入模式，或临时配色未完成核验'
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            jobs_style_phase_control_keys=0
            if [ "$jobs_style_applied_complete" = 1 ]; then
                jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
                if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
                    jobs_style_query_active=1
                    jobs_style_cleanup_ok=1
                    while IFS='|' read -r jobs_style_key jobs_style_expected jobs_style_original; do
                        [ -n "$jobs_style_key" ] || continue
                        if ! jobs_terminal_style_query "$jobs_style_key" cleanup; then
                            jobs_style_cleanup_ok=0
                            jobs_style_cleanup_issue="颜色项 $jobs_style_key：$jobs_style_query_failure"
                            break
                        fi
                        if [ "$jobs_style_normalized" = "$jobs_style_expected" ]; then
                            jobs_style_restore_safe=$jobs_style_restore_safe$jobs_style_original
                        else
                            jobs_style_conflicts="$jobs_style_conflicts $jobs_style_key"
                        fi
                    done <<JOBS_STYLE_APPLIED
$jobs_style_applied_rows
JOBS_STYLE_APPLIED
                    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_cleanup_ok=0; jobs_style_cleanup_issue='无法恢复原终端输入模式'; }
                    jobs_style_query_active=0
                fi
            fi
            if [ "$jobs_style_cleanup_ok" = 1 ] && printf '%s\033[0m' "$jobs_style_restore_safe" > /dev/tty; then
                if [ -z "$jobs_style_conflicts" ]; then
                    rm -f "$jobs_style_recovery"
                    rmdir "${jobs_style_recovery%/*}" 2>/dev/null || :
                else
                    printf '检测到运行期间的配色变更，已保留这些项：%s\n' "$jobs_style_conflicts" >&2
                    printf '确认要覆盖后续改色时才使用恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
                    [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
                fi
            else
                printf '终端配色未能安全自动恢复（%s）；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_cleanup_issue" "$jobs_style_recovery" >&2
                [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
            fi
        fi
        if [ "${2:-}" = continue ]; then
            jobs_style_cleanup_status=$jobs_style_result
            return 0
        fi
        exit "$jobs_style_result"
    }
    trap 'jobs_terminal_style_cleanup "$jobs_style_exit_status"' 0
    trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP
    trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT
    trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM
    if ! stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    for jobs_style_key in 10 11 12 '4;0' '4;1' '4;2' '4;3' '4;4' '4;5' '4;6' '4;7' '4;8' '4;9' '4;10' '4;11' '4;12' '4;13' '4;14' '4;15'; do
        if ! jobs_terminal_style_query "$jobs_style_key"; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_saved=$jobs_style_saved$jobs_style_reply
        jobs_style_original_rows="$jobs_style_original_rows$jobs_style_key|$jobs_style_normalized|$jobs_style_reply
"
        jobs_style_saved_rows="$jobs_style_saved_rows$jobs_style_key|$jobs_style_reply
"
    done
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '%s\n' '终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_recovery_dir=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/jobs-terminal-style.XXXXXX") || jobs_terminal_style_plain "$@"
    jobs_style_recovery=$jobs_style_recovery_dir/restore.sh
    if ! (umask 077; {
        printf '#!/bin/sh\n'
        printf '[ -t 0 ] && [ "$(tty)" = '\''%s'\'' ] || { printf '\''请在原终端运行恢复入口。\\n'\'' >&2; exit 1; }\n' "$jobs_style_tty"
        printf 'printf '\''本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：'\'' >&2\n'
        printf 'IFS= read -r jobs_restore_choice\n[ "$jobs_restore_choice" = YES ] || exit 1\n'
        printf 'printf '\''%%s\\033[0m'\'' '\''%s'\'' > /dev/tty\n' "$jobs_style_saved"
    } > "$jobs_style_recovery"); then
        printf '%s\n' '无法保存终端配色恢复入口；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    printf '正在准备本次终端临时配色；强退后恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
    jobs_style_changed=1
    printf '\033]10;#ffffff\007\033]11;#000000\007\033]12;#ffffff\007' > /dev/tty
    jobs_style_index=0
    for jobs_style_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
        printf '\033]4;%s;#%s\007' "$jobs_style_index" "$jobs_style_color" > /dev/tty
        jobs_style_index=$((jobs_style_index + 1))
    done
    printf '\033[0m' > /dev/tty
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || { jobs_style_exit_status=1; exit 1; }
    stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    jobs_style_targets_ok=1
    jobs_style_phase_control_keys=0
    while IFS='|' read -r jobs_style_key jobs_style_original; do
        [ -n "$jobs_style_key" ] || continue
        if ! jobs_terminal_style_query "$jobs_style_key" applied; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_applied_rows="$jobs_style_applied_rows$jobs_style_key|$jobs_style_normalized|$jobs_style_original
"
        if ! jobs_terminal_style_accepts_target "$jobs_style_key"; then
            jobs_style_targets_ok=0
        fi
    done <<JOBS_STYLE_ORIGINAL
$jobs_style_saved_rows
JOBS_STYLE_ORIGINAL
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '临时配色核验失败（颜色项 %s：%s），正在核对原色恢复。\n' "$jobs_style_key" "$jobs_style_query_failure" >&2
        jobs_terminal_style_cleanup 0 continue
        jobs_style_changed=0
        if [ "$jobs_style_cleanup_status" != 0 ]; then
            jobs_style_exit_status=1
            exit 1
        fi
        trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP
        trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT
        trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM
        printf '%s\n' '已恢复原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    if [ "$jobs_style_targets_ok" != 1 ]; then
        jobs_terminal_style_cleanup 0 continue
        jobs_style_changed=0
        if [ "$jobs_style_cleanup_status" != 0 ]; then
            jobs_style_exit_status=1
            exit 1
        fi
        trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP
        trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT
        trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM
        printf '%s\n' '终端未接受本次配色，已恢复原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_applied_complete=1
    printf '%s\n' '本次终端已临时使用黑底白字。' >&2
    JOBS_TERMINAL_STYLE_TTY=$jobs_style_tty
    JOBS_TERMINAL_STYLE_OWNER=$$
    export JOBS_TERMINAL_STYLE_TTY JOBS_TERMINAL_STYLE_OWNER
    if "$@"; then
        jobs_style_exit_status=0
    else
        jobs_style_exit_status=$?
    fi
    exit "$jobs_style_exit_status"
}
# 仅监督直接执行的入口；被 source 时不切换配色、不重新执行业务。
jobs_terminal_style_bootstrap() {
    jobs_style_bootstrap_script=$1
    shift
    if [ -n "${ZSH_VERSION:-}" ]; then
        case ${ZSH_EVAL_CONTEXT:-} in
            *:file|*:file:*) return 0 ;;
        esac
    elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE:-$jobs_style_bootstrap_script}" != "$jobs_style_bootstrap_script" ]; then
        return 0
    fi
    if [ "${JOBS_TERMINAL_STYLE_REEXEC:-}" = "$jobs_style_bootstrap_script" ]; then
        unset JOBS_TERMINAL_STYLE_REEXEC
        return 0
    fi
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] ||
       [ "${TERM:-}" = dumb ] || [ "${NO_COLOR+x}" = x ] ||
       [ "${PLAIN_OUTPUT:-0}" = 1 ] || [ "${IS_SOURCETREE_RUNTIME:-0}" = 1 ] ||
       [ -n "${TMUX:-}${STY:-}" ] ||
       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
        return 0
    fi
    case ${JOBS_TERMINAL_STYLE_OWNER:-} in
        ''|*[!0-9]*) ;;
        *)
            if kill -0 "$JOBS_TERMINAL_STYLE_OWNER" 2>/dev/null &&
               [ "${JOBS_TERMINAL_STYLE_TTY:-}" = "$(tty 2>/dev/null)" ]; then
                return 0
            fi
            ;;
    esac
    JOBS_TERMINAL_STYLE_REEXEC=$jobs_style_bootstrap_script
    export JOBS_TERMINAL_STYLE_REEXEC
    jobs_terminal_style_run /bin/zsh "$jobs_style_bootstrap_script" "$@"
    jobs_style_bootstrap_result=$?
    exit "$jobs_style_bootstrap_result"
}
jobs_terminal_style_bootstrap "$0" "$@"
# <<< Jobs terminal style protection v1 <<<

# JOBS_FLUTTER_ROUTE_BEGIN
# 每个宿主Shell保留一个私有任务缓存，网络变量仅在wrapper的子进程中修改。
# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只展示提示选项；不读取答案、不改变默认值、返回码或业务环境。
# URL仅供显示；纯文本日志传color=0。
jobs_url_format() {
  LC_ALL=en_US.UTF-8 /usr/bin/awk -v color="${1:-0}" -v lines="${2:-1}" '
    # URL 范围只在展示文本上识别；不会改写真实请求或输出数据。
    function urlInit() {
      urlPattern = "[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]<>\"" sprintf("%c", 39) esc "]+"
      urlPunctuationCount = split("，|。|；|：|！|？|、|（|）|【|】|《|》|「|」|『|』|“|”|‘|’", urlPunctuation, "\\|")
    }
    function urlCount(value, token, total, idx) {
      total = 0
      for (idx = 1; idx <= length(value); idx++) if (substr(value, idx, 1) == token) total++
      return total
    }
    function urlTrim(value, idx, at, last) {
      for (idx = 1; idx <= urlPunctuationCount; idx++) {
        at = index(value, urlPunctuation[idx])
        if (at) value = substr(value, 1, at - 1)
      }
      while (length(value)) {
        last = substr(value, length(value), 1)
        if (index(".,;:!?", last) > 0 || (last == ")" && urlCount(value, ")") > urlCount(value, "(")) ||
            (last == "]" && urlCount(value, "]") > urlCount(value, "[")) || (last == "}" && urlCount(value, "}") > urlCount(value, "{"))) {
          value = substr(value, 1, length(value) - 1)
        } else break
      }
      return value
    }
    function urlClean(value, preserve, output, token, start, size) {
      gsub(esc "\\][^" esc sprintf("%c", 7) "]*(" sprintf("%c", 7) "|" esc "\\\\)", "", value)
      output = ""
      while (match(value, esc "\\[[0-?]*[ -/]*[@-~]")) {
        start = RSTART; size = RLENGTH; token = substr(value, start, size)
        output = output substr(value, 1, start - 1)
        if (preserve && token ~ /m$/) output = output token
        value = substr(value, start + size)
      }
      return output value
    }
    # 题干分段前临时遮蔽地址，地址里的 Enter、/、?、= 不参与选项识别。
    function urlProtect(value, output, at, size, token, marker, number, original) {
      urlProtectedCount = 0; output = ""; original = value; number = 0
      while (match(value, urlPattern)) {
        at = RSTART; size = RLENGTH; token = urlTrim(substr(value, at, size))
        do { marker = sprintf("%c", 2) "U" ++number sprintf("%c", 3) } while (index(original, marker))
        urlProtected[++urlProtectedCount] = token; urlMarkers[urlProtectedCount] = marker
        output = output substr(value, 1, at - 1) marker
        value = substr(value, at + length(token))
      }
      return output value
    }
    function urlRestore(value, idx, token, at) {
      for (idx = urlProtectedCount; idx > 0; idx--) {
        token = urlMarkers[idx]
        while ((at = index(value, token))) value = substr(value, 1, at - 1) urlProtected[idx] substr(value, at + length(token))
      }
      return value
    }
    # 保存原 SGR 的有效序列；RGB 中的零值不能误认为整体复位。
    function urlTrack(tokens, token, code, idx, total, reset, fields) {
      while (match(tokens, esc "\\[[0-9;:]*m")) {
        token = substr(tokens, RSTART, RLENGTH)
        tokens = substr(tokens, RSTART + RLENGTH)
        code = substr(token, 3, length(token) - 3); reset = (code == "")
        total = split(code, fields, ";")
        for (idx = 1; idx <= total; idx++) {
          if (fields[idx] == "0") reset = 1
          if ((fields[idx] == "38" || fields[idx] == "48" || fields[idx] == "58") && idx < total) {
            if (fields[idx + 1] == "2") idx += 4
            else if (fields[idx + 1] == "5") idx += 2
          }
        }
        if (reset) urlActive = ""
        urlActive = urlActive token
      }
    }
    # 用可见字符位置映射原 SGR，URL 内已有样式也会重新覆为绿下划线。
    function urlRender(value, output, visible, rest, key, at, size, token, idx, offset, url, inURL) {
      value = urlClean(value, color)
      if (!color) return value
      for (key in urlStyles) delete urlStyles[key]
      for (key in urlStarts) delete urlStarts[key]
      for (key in urlEnds) delete urlEnds[key]
      visible = ""; rest = value
      while (match(rest, esc "\\[[0-9;:]*m")) {
        at = RSTART; size = RLENGTH; token = substr(rest, at, size)
        visible = visible substr(rest, 1, at - 1)
        urlStyles[length(visible) + 1] = urlStyles[length(visible) + 1] token
        rest = substr(rest, at + size)
      }
      visible = visible rest; rest = visible; offset = 0
      while (match(rest, urlPattern)) {
        at = RSTART; size = RLENGTH; url = urlTrim(substr(rest, at, size))
        urlStarts[offset + at] = 1; urlEnds[offset + at + length(url) - 1] = 1
        offset += at + length(url) - 1; rest = substr(visible, offset + 1)
      }
      output = ""; inURL = 0
      for (idx = 1; idx <= length(visible) + 1; idx++) {
        if (idx in urlStyles) {
          token = urlStyles[idx]; output = output token; urlTrack(token)
          if (inURL) output = output esc "[32;4m"
        }
        if (idx > length(visible)) break
        if (idx in urlStarts) { output = output esc "[32;4m"; inURL = 1 }
        output = output substr(visible, idx, 1)
        if (idx in urlEnds) { output = output esc "[0m" urlActive; inURL = 0 }
      }
      return output
    }
    BEGIN { esc = sprintf("%c", 27); first = 1; urlInit() }
    {
      if (lines == 2) {
        if (!first) printf "%s\n", urlRender(pending)
        pending = $0; first = 0
      } else {
        if (!lines && !first) printf "\n"
        printf "%s", urlRender($0)
        if (lines) printf "\n"
        first = 0
      }
    }
    END {
      if (lines == 2 && !first) {
        sub(sprintf("%c", 1) "$", "", pending)
        printf "%s", urlRender(pending)
      }
    }
  '
}
# URL仅供显示；纯文本日志传color=0。
jobs_url_stream() {
  local url_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then url_color=1; fi
  jobs_url_format "$url_color" "${1:-1}"
}
jobs_prompt_color_ready() {
  env | LC_ALL=C /usr/bin/grep -qiE '^(SOURCETREE|SOURCE_TREE)' && return 1
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 原生 awk 分段着色；任意/非空输入优先，括号内外沿用同一个选项。
jobs_prompt_format() {
  # 中文字符类按UTF-8字符处理，仅约束此awk进程，保留调用者locale。
  LC_ALL=en_US.UTF-8 /usr/bin/awk -v color="${1:-0}" -v lines="${2:-0}" -v keep="${3:-0}" -v question="${4:-0}" '
    # URL 范围只在展示文本上识别；不会改写真实请求或输出数据。
    function urlInit() {
      urlPattern = "[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]<>\"" sprintf("%c", 39) esc "]+"
      urlPunctuationCount = split("，|。|；|：|！|？|、|（|）|【|】|《|》|「|」|『|』|“|”|‘|’", urlPunctuation, "\\|")
    }
    function urlCount(value, token, total, idx) {
      total = 0
      for (idx = 1; idx <= length(value); idx++) if (substr(value, idx, 1) == token) total++
      return total
    }
    function urlTrim(value, idx, at, last) {
      for (idx = 1; idx <= urlPunctuationCount; idx++) {
        at = index(value, urlPunctuation[idx])
        if (at) value = substr(value, 1, at - 1)
      }
      while (length(value)) {
        last = substr(value, length(value), 1)
        if (index(".,;:!?", last) > 0 || (last == ")" && urlCount(value, ")") > urlCount(value, "(")) ||
            (last == "]" && urlCount(value, "]") > urlCount(value, "[")) || (last == "}" && urlCount(value, "}") > urlCount(value, "{"))) {
          value = substr(value, 1, length(value) - 1)
        } else break
      }
      return value
    }
    function urlClean(value, preserve, output, token, start, size) {
      gsub(esc "\\][^" esc sprintf("%c", 7) "]*(" sprintf("%c", 7) "|" esc "\\\\)", "", value)
      output = ""
      while (match(value, esc "\\[[0-?]*[ -/]*[@-~]")) {
        start = RSTART; size = RLENGTH; token = substr(value, start, size)
        output = output substr(value, 1, start - 1)
        if (preserve && token ~ /m$/) output = output token
        value = substr(value, start + size)
      }
      return output value
    }
    # 题干分段前临时遮蔽地址，地址里的 Enter、/、?、= 不参与选项识别。
    function urlProtect(value, output, at, size, token, marker, number, original) {
      urlProtectedCount = 0; output = ""; original = value; number = 0
      while (match(value, urlPattern)) {
        at = RSTART; size = RLENGTH; token = urlTrim(substr(value, at, size))
        do { marker = sprintf("%c", 2) "U" ++number sprintf("%c", 3) } while (index(original, marker))
        urlProtected[++urlProtectedCount] = token; urlMarkers[urlProtectedCount] = marker
        output = output substr(value, 1, at - 1) marker
        value = substr(value, at + length(token))
      }
      return output value
    }
    function urlRestore(value, idx, token, at) {
      for (idx = urlProtectedCount; idx > 0; idx--) {
        token = urlMarkers[idx]
        while ((at = index(value, token))) value = substr(value, 1, at - 1) urlProtected[idx] substr(value, at + length(token))
      }
      return value
    }
    # 保存原 SGR 的有效序列；RGB 中的零值不能误认为整体复位。
    function urlTrack(tokens, token, code, idx, total, reset, fields) {
      while (match(tokens, esc "\\[[0-9;:]*m")) {
        token = substr(tokens, RSTART, RLENGTH)
        tokens = substr(tokens, RSTART + RLENGTH)
        code = substr(token, 3, length(token) - 3); reset = (code == "")
        total = split(code, fields, ";")
        for (idx = 1; idx <= total; idx++) {
          if (fields[idx] == "0") reset = 1
          if ((fields[idx] == "38" || fields[idx] == "48" || fields[idx] == "58") && idx < total) {
            if (fields[idx + 1] == "2") idx += 4
            else if (fields[idx + 1] == "5") idx += 2
          }
        }
        if (reset) urlActive = ""
        urlActive = urlActive token
      }
    }
    # 用可见字符位置映射原 SGR，URL 内已有样式也会重新覆为绿下划线。
    function urlRender(value, output, visible, rest, key, at, size, token, idx, offset, url, inURL) {
      value = urlClean(value, color)
      if (!color) return value
      for (key in urlStyles) delete urlStyles[key]
      for (key in urlStarts) delete urlStarts[key]
      for (key in urlEnds) delete urlEnds[key]
      visible = ""; rest = value
      while (match(rest, esc "\\[[0-9;:]*m")) {
        at = RSTART; size = RLENGTH; token = substr(rest, at, size)
        visible = visible substr(rest, 1, at - 1)
        urlStyles[length(visible) + 1] = urlStyles[length(visible) + 1] token
        rest = substr(rest, at + size)
      }
      visible = visible rest; rest = visible; offset = 0
      while (match(rest, urlPattern)) {
        at = RSTART; size = RLENGTH; url = urlTrim(substr(rest, at, size))
        urlStarts[offset + at] = 1; urlEnds[offset + at + length(url) - 1] = 1
        offset += at + length(url) - 1; rest = substr(visible, offset + 1)
      }
      output = ""; inURL = 0
      for (idx = 1; idx <= length(visible) + 1; idx++) {
        if (idx in urlStyles) {
          token = urlStyles[idx]; output = output token; urlTrack(token)
          if (inURL) output = output esc "[32;4m"
        }
        if (idx > length(visible)) break
        if (idx in urlStarts) { output = output esc "[32;4m"; inURL = 1 }
        output = output substr(visible, idx, 1)
        if (idx in urlEnds) { output = output esc "[0m" urlActive; inURL = 0 }
      }
      return output
    }
    function typedEnter(value, start, prefix) {
      prefix = substr(value, 1, start - 1)
      gsub(/[“”‘’「」『』"]/, "", prefix)
      gsub(sprintf("%c", 39), "", prefix)
      if (prefix ~ /(空格|[Ss][Pp][Aa][Cc][Ee])[[:space:]]*(后|再|并|[Tt][Hh][Ee][Nn])?[[:space:]]*$/) return 1
      return prefix ~ /(输入|键入|填写|[Tt]ype)[^；;|]*[[:alnum:]_+-]+[[:space:]]*(后|再|并)?[[:space:]]*$/
    }
    function greenPosition(value, token, start) {
      if (match(value, /(直接|仅|只需|只|按下|按)?[[:space:]]*(回车|回車)/)) {
        start = RSTART
        return typedEnter(value, start) ? 0 : start
      }
      if (!match(value, /(^|[^[:alnum:]_])([Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn])([^[:alnum:]_]|$)/)) return 0
      start = RSTART
      token = substr(value, RSTART, RLENGTH)
      match(token, /[Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn]/)
      start += RSTART - 1
      return typedEnter(value, start) ? 0 : start
    }
    function segment(value, inherited, is_question, start, kind, prefix, body, red, green, connector, left, right, splitAt) {
      if (value == "") return value
      kind = inherited
      start = 1
      if (!kind) {
        if (match(value, /(输入)?(任意|任何)(非空)?(字符|内容|输入|键)|非空(字符|内容|输入)?|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key/)) {
          red = RSTART
        }
        green = greenPosition(value)
        if (red && green && green < red) {
          left = substr(value, 1, red - 1)
          right = substr(value, red)
          connector = ""
          if (match(left, /(或者|或)[[:space:]]*$/)) {
            connector = substr(left, RSTART)
            left = substr(left, 1, RSTART - 1)
          }
          return segment(left, 0, is_question) connector segment(right, 31, 0)
        }
        if (red && green && red < green && match(value, /或[[:space:]]*(直接|仅|只需|只|按下|按)?(回车|回車)/)) {
          splitAt = RSTART
          return segment(substr(value, 1, splitAt - 1), 31, is_question) "或" segment(substr(value, splitAt + length("或")), 0, 0)
        }
        if (red) {
          kind = 31
          start = red
        } else if (green) {
          kind = 32
          start = green
        }
      }
      if (!color) return value
      if (!kind) return is_question && value !~ /^[[:space:]]*$/ ? esc "[1;36m" value esc "[0m" : value
      prefix = substr(value, 1, start - 1)
      body = substr(value, start)
      if (is_question && prefix !~ /^[[:space:]]*$/) prefix = esc "[1;36m" prefix esc "[0m"
      return prefix esc "[1;" kind "m" body esc "[0m"
    }
    function render(value, output, part, boundary, inherited, kind, consumed, depth, original, question_body) {
      original = value
      value = urlProtect(urlClean(value, 0))
      if (color && keep && !greenPosition(value) && value !~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) return urlRender(original)
      output = ""
      inherited = 0
      depth = 0
      question_body = question
      while (match(value, /[；;\/|，,、？?：:=＝（）()\[\]【】]/)) {
        part = substr(value, 1, RSTART - 1)
        boundary = substr(value, RSTART, RLENGTH)
        consumed = RSTART + RLENGTH
        output = output segment(part, inherited, question_body) boundary
        if (inherited || greenPosition(part) || part ~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) question_body = 0
        if (boundary ~ /[（(\[【]/) {
          depth++
          if (part ~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) inherited = 31
          else if (greenPosition(part)) inherited = 32
        } else if (boundary ~ /[）)\]】]/) {
          if (depth) depth--
        } else if (boundary ~ /[：:=＝]/) {
          if (!inherited) {
            if (part ~ /(任意|任何|非空|其它输入|其他输入)/) inherited = 31
            else if (greenPosition(part)) inherited = 32
          }
        } else if (!depth) inherited = 0
        value = substr(value, consumed)
      }
      return urlRender(urlRestore(output segment(value, inherited, question_body) (question && color ? esc "[0m" : "")))
    }
    BEGIN { esc = sprintf("%c", 27); first = 1; urlInit() }
    {
      if (lines == 2) {
        if (!first) printf "%s\n", render(pending)
        pending = $0
        first = 0
        next
      }
      if (!lines && !first) printf "\n"
      printf "%s", render($0)
      if (lines) printf "\n"
      first = 0
    }
    END {
      if (lines == 2 && !first) {
        sub(sprintf("%c", 1) "$", "", pending)
        printf "%s", render(pending)
      }
    }
  '
}
# read 的命令替换会使 stdout 成为管道，按输入与提示所在 stderr 判断终端。
jobs_prompt_render() {
  local jobs_prompt_color=0
  if [ -t 0 ] && [ -t 2 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  printf "%s" "$1" | jobs_prompt_format "$jobs_prompt_color" 0 0 1
}
# 仅放在显示链末端；tee 在此函数之前接收纯文本，不把 ANSI 写入日志。
jobs_prompt_stream() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  jobs_prompt_format "$jobs_prompt_color" 1 1
}
# 显示管道保留原末尾换行；只删除本轮追加的最后一个结束标记。
jobs_prompt_filter() {
  local jobs_prompt_color=0 jobs_prompt_question=0
  case "${1:-0}" in 1|--question) jobs_prompt_question=1 ;; esac
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  { /bin/cat; printf '\001'; } | jobs_prompt_format "$jobs_prompt_color" 2 "$((1 - jobs_prompt_question))" "$jobs_prompt_question"
}
# 仅包装原 printf/echo/print 展示，原参数、尾换行与显示命令退出码保持不变。
jobs_prompt_output() {
  local jobs_prompt_status=0 jobs_prompt_stderr=0 jobs_prompt_arg="" jobs_prompt_previous="" jobs_prompt_question=0
  if [ "${1:-}" = --question ]; then jobs_prompt_question=1; shift; fi
  if [ "${1:-}" = print ]; then
    for jobs_prompt_arg in "$@"; do
      case "$jobs_prompt_arg" in -?*u2*|-u2) jobs_prompt_stderr=1 ;; esac
      if [ "$jobs_prompt_previous" = -u ] && [ "$jobs_prompt_arg" = 2 ]; then jobs_prompt_stderr=1; fi
      jobs_prompt_previous="$jobs_prompt_arg"
      [ "$jobs_prompt_arg" != -- ] || break
    done
  fi
  if [ -n "${ZSH_VERSION:-}" ]; then
    if [ "$jobs_prompt_stderr" = 1 ]; then
      "$@" 2>&1 | jobs_prompt_filter "$jobs_prompt_question" >&2
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    else
      "$@" | jobs_prompt_filter "$jobs_prompt_question"
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    "$@" | jobs_prompt_filter "$jobs_prompt_question"
    jobs_prompt_status=$(( ${PIPESTATUS[0]} != 0 ? ${PIPESTATUS[0]} : ${PIPESTATUS[1]} ))
  else
    "$@" | jobs_prompt_filter "$jobs_prompt_question"
    jobs_prompt_status=$?
  fi
  return "$jobs_prompt_status"
}
# 仅替换日志 primitive 的 tee：磁盘同步追加纯文，终端保留非选项原色。
jobs_prompt_tee() {
  local jobs_prompt_log="$1" jobs_prompt_line="" jobs_prompt_newline=0
  while :; do
    jobs_prompt_line=""
    if IFS= read -r jobs_prompt_line; then jobs_prompt_newline=1; else jobs_prompt_newline=0; [ -n "$jobs_prompt_line" ] || break; fi
    if [ "$jobs_prompt_newline" = 1 ]; then
      { printf '%s\n' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s\n' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    else
      { printf '%s' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    fi
  done
}
# JOBS_INPUT_CHOICE_STYLE_END

jfs_route_cache_init() {
    if [[ -n "${JFS_ROUTE_CACHE_DIR:-${JOBS_FLUTTER_ROUTE_CACHE_DIR:-}}" ]]; then
        JFS_ROUTE_CACHE_DIR="${JFS_ROUTE_CACHE_DIR:-$JOBS_FLUTTER_ROUTE_CACHE_DIR}"
        [[ -d "$JFS_ROUTE_CACHE_DIR" && ! -L "$JFS_ROUTE_CACHE_DIR" && -f "$JFS_ROUTE_CACHE_DIR/.jobs-sdk-route" && "$(/usr/bin/stat -f %u "$JFS_ROUTE_CACHE_DIR")" == "$UID" && "$(/usr/bin/stat -f %Lp "$JFS_ROUTE_CACHE_DIR")" == 700 ]] && return 0
    fi
    JFS_ROUTE_CACHE_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp/}JobsFlutterSdkRoute.XXXXXX")" || return 1
    /bin/chmod 700 "$JFS_ROUTE_CACHE_DIR"
    print -r -- v1 > "$JFS_ROUTE_CACHE_DIR/.jobs-sdk-route"
}
# 审计不回显URL凭据或查询串，stdout始终留给SDK自身及机器输出。
jfs_route_note() {
    local output=""
    output="$(print -r -- "$2" | /usr/bin/perl -pe 's{([a-z][a-z0-9+.-]*://)[^\s/@]+@}{$1***@}ig; s{(https?://[^\s?#]+)[?#][^\s]*}{$1?[已省略]}ig; s{\e\[[0-9;?]*[ -/]*[@-~]}{}g')"
    print -u2 -r -- "$output"
    [[ -z "$1" ]] || print -r -- "$output" >> "$1"
}
# 只回收本轮创建的子树，避免中断后留下SDK下载者。
jfs_route_stop_tree() {
    local child=""
    # Freeze the owned parent first: killed download children cannot trigger a retry fork.
    /bin/kill -STOP "$1" 2>/dev/null || return 0
    for child in $(/usr/bin/pgrep -P "$1" 2>/dev/null); do jfs_route_stop_tree "$child"; done
    # Stopped processes cannot run TERM traps; kill this tree, then the caller reaps its child.
    /bin/kill -KILL "$1" 2>/dev/null || true
}
# 参数仅作为数据交给系统JXA解析，不执行SDK或项目代码。
jfs_route_data() {
    /usr/bin/osascript -l JavaScript - "$@" <<'JXA'
ObjC.import('Foundation');
function run(a) {
    function text(p) { var v=$.NSString.stringWithContentsOfFileEncodingError(p,$.NSUTF8StringEncoding,null), value=v ? ObjC.unwrap(v) : ''; return typeof value==='string' ? value : ''; }
    function json(p) { return JSON.parse(text(p)); }
    function clean(v) { v=String(v===undefined?'':v); if(/[\x00-\x1f\x7f]/.test(v)) throw Error('字段含控制字符'); return v; }
    function sha(v) { return /^[0-9a-f]{40}$/i.test(v||'') ? v.toLowerCase() : ''; }
    function version(v) { return /^v?\d+\.\d+\.\d+(?:[-+][\w.+-]+)?$/.test(v||'') ? v : ''; }
    if(a[0]==='json-valid') { json(a[1]); return 'valid'; }
    if(a[0]==='identity') {
        var root=a[1], wanted=a[2], engine=sha(a[4]) || (!a[4] ? sha(text(root+'/bin/internal/engine.version').trim()) : '');
        var m={}; try {m=json(root+'/bin/cache/flutter.version.json');} catch(_) {}
        var cached=engine && sha(m.engineRevision)===engine ? version(m.frameworkVersion) : '';
        var v=wanted || cached;
        return [clean(v),engine].join('\t');
    }
    if(a[0]==='sdk-base') {
        var update=text(a[1]+'/bin/internal/update_dart_sdk.sh'), line=update.match(/^.*DART_SDK_BASE_URL=.*FLUTTER_STORAGE_BASE_URL.*$/m), match=line && line[0].match(/FLUTTER_STORAGE_BASE_URL:-([^}\s"']+)/);
        return match && /^https:\/\//.test(match[1]) ? clean(match[1]).replace(/\/+$/,'') : '';
    }
    if(a[0]==='realm') {
        var realm=text(a[1]+'/bin/cache/engine.realm').replace(/\s/g,'');
        if(realm && (!/^[A-Za-z0-9_.\/-]+$/.test(realm) || realm.split('/').some(function(v){return v==='..'||v==='.';}))) throw Error('realm路径无效');
        return realm.replace(/^\/+|\/+$/g,'');
    }
    if(a[0]==='manifest') {
        var m=json(a[1]),wanted=a[2],arch=a[3],channel=/^(stable|beta|dev)$/.test(wanted)?wanted:'';
        if(!Array.isArray(m.releases)) throw Error('发布清单无releases');
        var rows=m.releases.filter(function(r) {
            if(channel && (!m.current_release || r.hash!==m.current_release[channel])) return false;
            if(!channel && wanted && r.version.replace(/^v/,'')!==wanted.replace(/^v/,'')) return false;
            if(!/^[0-9a-f]{64}$/i.test(r.sha256||'') || !/^([\w.-]+\/)*flutter_macos_[\w.+-]+\.zip$/.test(r.archive||'')) return false;
            return arch==='arm64' ? (r.dart_sdk_arch==='arm64'||/_arm64_/.test(r.archive)) : (r.dart_sdk_arch==='x64'||!/_arm64_/.test(r.archive));
        });
        if(!rows.length) throw Error('清单无匹配版本和架构');
        var r=rows[0]; return [r.version,'flutter_infra_release/releases/'+r.archive,r.sha256,sha(r.engine_revision||r.engineRevision)].map(clean).join('\t');
    }
    if(a[0]==='metadata-url') { var path=a[1].split('/'); return 'https://www.googleapis.com/storage/v1/b/'+encodeURIComponent(path.shift())+'/o/'+encodeURIComponent(path.join('/'))+'?fields=name,size,md5Hash'; }
    if(a[0]==='metadata') {
        var m=json(a[1]), object=a[2].split('/').slice(1).join('/');
        if(m.name!==object || !/^[0-9]+$/.test(String(m.size)) || !/^[A-Za-z0-9+/]{22}==$/.test(m.md5Hash||'')) throw Error('官方对象身份/摘要无效');
        var alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/',bits=0,count=0,hex='';
        m.md5Hash.replace(/=/g,'').split('').forEach(function(c){bits=(bits<<6)|alphabet.indexOf(c);count+=6;if(count>=8){count-=8;hex+=('0'+((bits>>count)&255).toString(16)).slice(-2);}});
        return [m.size,hex].join('\t');
    }
    if(a[0]==='probe') {
        var headers=text(a[1]), metrics=text(a[3]).trim().split('\t'), body=$.NSData.dataWithContentsOfFile(a[2]);
        if(!body) throw Error('无样本');
        var size=Number(body.length),code=Number(metrics[0]),total=Number(a[4]),md5=a[5],kind=a[6];
        var ranges=headers.match(/content-range:\s*bytes\s+0-(\d+)\/(\d+)/ig)||[],range=ranges.length?/0-(\d+)\/(\d+)/.exec(ranges[ranges.length-1]):null;
        if(kind==='source') { if(code!==206 && !(code===200&&size<=262144)) throw Error('来源正文状态无效'); }
        else if(code!==206 || !range || Number(range[2])<=0 || Number(range[1])>=Number(range[2]) || (total&&Number(range[2])!==total)) throw Error('非匹配206/对象总长');
        if(!size || size>262144 || (kind!=='source'&&size<Math.min(4096,total||4096))) throw Error('样本长度无效');
        if(kind!=='source' && range && Number(a[8])===0 && size!==Number(range[1])+1) throw Error('完整样本与Range长度不一致');
        var etags=headers.match(/etag:\s*(?:W\/)?"?([a-f0-9]{32})"?/ig)||[],etag=etags.length?/([a-f0-9]{32})/i.exec(etags[etags.length-1])[1].toLowerCase():'';
        if(md5 && etag!==md5) throw Error('ETag与官方对象MD5不一致');
        var preview=ObjC.unwrap($.NSString.alloc.initWithDataEncoding(body,$.NSISOLatin1StringEncoding))||'';
        if(kind==='source') { if(/^\s*(?:<!doctype\s+html|<html|\{\s*"error")/i.test(preview)) throw Error('错误页面'); if(a[7] && preview.indexOf(a[7])<0) throw Error('原始来源正文未匹配预期'); }
        else if(preview.slice(0,2)!=='PK') throw Error('非ZIP制品');
        return [Number(metrics[2])||size/Math.max(0.001,Number(metrics[3])),Number(metrics[1])||0,size].join('\t');
    }
    if(a[0]==='cache-read') {
        var c=json(a[1]); if(c.key!==a[2] || Number(a[3])-c.at>300 || Number(a[3])<c.at) throw Error('缓存失效');
        return ['base','proxyMode','proxy','object','sha','size','md5','version'].map(function(k){return k+'\t'+clean(c[k]);}).join('\n');
    }
    if(a[0]==='cache-write') {
        var c={key:a[2],at:Number(a[3]),base:a[4],proxyMode:a[5],proxy:a[6],object:a[7],sha:a[8],size:a[9],md5:a[10],version:a[11]};
        if(!$(JSON.stringify(c)).writeToFileAtomicallyEncodingError(a[1],true,$.NSUTF8StringEncoding,null)) throw Error('缓存写入失败');
        return 'saved';
    }
    throw Error('未知路由数据操作');
}
JXA
}
# 当前已设置代理（含空值）优先；候选只来自当前启用的系统代理配置。
jfs_route_candidates() {
    local name="" configured=0 settings="" kind="" enabled="" host="" port="" scheme=""
    JFS_PROXY_MODES=() JFS_PROXY_URLS=()
    for name in HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy; do
        (( ${+parameters[$name]} )) && configured=1
    done
    JFS_CURL_CONFIG=0
    if [[ -f "${JOBS_FLUTTER_ROUTE_CURL_CONFIG:-}" || -f "${CURL_HOME:-$HOME}/.curlrc" || -f "${XDG_CONFIG_HOME:-$HOME/.config}/curlrc" ]]; then JFS_CURL_CONFIG=1; configured=1; fi
    if [[ "$JFS_MODE" == git && -n "$JFS_SOURCE_URL" ]]; then
        /usr/bin/git config --get-urlmatch http.proxy "$JFS_SOURCE_URL" >/dev/null 2>&1 && configured=1
    fi
    if (( configured )); then JFS_PROXY_MODES=(env); JFS_PROXY_URLS=(''); return 0; fi
    JFS_PROXY_MODES=(direct) JFS_PROXY_URLS=('')
    settings="$(/usr/sbin/scutil --proxy 2>/dev/null)"
    for kind in HTTP HTTPS SOCKS; do
        enabled="$(print -r -- "$settings" | /usr/bin/awk -v k="${kind}Enable" '$1==k&&$2==":"{print $3;exit}')"
        host="$(print -r -- "$settings" | /usr/bin/awk -v k="${kind}Proxy" '$1==k&&$2==":"{print $3;exit}')"
        port="$(print -r -- "$settings" | /usr/bin/awk -v k="${kind}Port" '$1==k&&$2==":"{print $3;exit}')"
        [[ "$enabled" == 1 && "$port" == <-> && "$port" -gt 0 && "$port" -le 65535 && "$host" =~ '^[A-Za-z0-9_.:-]+$' ]] || continue
        scheme=http; [[ "$kind" != SOCKS ]] || scheme=socks5h
        [[ "$host" != *:* || "$host" == \[*\] ]] || host="[$host]"
        JFS_PROXY_MODES+=(proxy) JFS_PROXY_URLS+=("$scheme://$host:$port")
    done
}
# 只在探测或真实SDK子进程内调用；原本有显式代理时mode=env不改任何key。
jfs_route_apply_proxy() {
    [[ "$1" != env ]] || return 0
    local value="$2"
    export HTTP_PROXY="$value" HTTPS_PROXY="$value" ALL_PROXY="$value" http_proxy="$value" https_proxy="$value" all_proxy="$value"
}
# Curl受时间、Range和文件大小双重约束；不使用完整SDK测速。
jfs_route_curl() {
    local mode="$1" proxy="$2"; shift 2
    local -a options=()
    (( JFS_CURL_CONFIG )) || options=(--disable)
    [[ ! -f "${JOBS_FLUTTER_ROUTE_CURL_CONFIG:-}" ]] || options+=(--config "$JOBS_FLUTTER_ROUTE_CURL_CONFIG")
    [[ "$mode" == env ]] || options+=(--proxy "$proxy")
    /usr/bin/env LC_ALL=C "${JOBS_FLUTTER_ROUTE_CURL:-/usr/bin/curl}" "${options[@]}" --fail --location --max-redirs 4 --proto '=https' --proto-redir '=https' --connect-timeout 2 --max-time 6 "$@"
}
# 小型官方JSON通过原有网络候选获取，最终还需按具体对象身份解析。
jfs_route_fetch_json() {
    local url="$1" output="$2" index=0 task="" result=1
    local -a tasks=()
    for (( index=1; index<=${#JFS_PROXY_MODES}; index++ )); do
        ( jfs_route_curl "$JFS_PROXY_MODES[index]" "$JFS_PROXY_URLS[index]" --max-filesize 2097152 --output "$output.$index" "$url" >/dev/null 2> "$output.$index.error" ) &
        tasks+=($!)
    done
    for task in "${tasks[@]}"; do wait "$task" 2>/dev/null || true; done
    for (( index=1; index<=${#JFS_PROXY_MODES}; index++ )); do
        if [[ -s "$output.$index" ]] && jfs_route_data json-valid "$output.$index" >/dev/null 2>&1; then /bin/cp "$output.$index" "$output"; return 0; fi
    done
    return "$result"
}
# 从SDK实际元数据取得realm与默认源；显式用户源优先，fork自有默认源不替换。
jfs_route_bases() {
    JFS_BASES=('')
    [[ "$JFS_MODE" != git && "$JFS_MODE" != source ]] || return 0
    JFS_SDK_DEFAULT_BASE="$(jfs_route_data sdk-base "$JFS_SDK_ROOT" 2>/dev/null)"
    if (( ${+FLUTTER_STORAGE_BASE_URL} )); then
        JFS_BASES=("${FLUTTER_STORAGE_BASE_URL:-https://storage.googleapis.com}")
    elif [[ -n "$JFS_SDK_DEFAULT_BASE" && "$JFS_SDK_DEFAULT_BASE" != https://storage.googleapis.com && "$JFS_SDK_DEFAULT_BASE" != https://storage.flutter-io.cn ]]; then
        JFS_BASES=("$JFS_SDK_DEFAULT_BASE")
    else
        JFS_BASES=(https://storage.googleapis.com https://storage.flutter-io.cn)
    fi
}
# 只有真实官方origin或公开元数据证明，才把未显式授权的对象发给公共镜像。
jfs_route_sdk_is_official() {
    local sdk="$1" origin=""
    [[ -d "$sdk/.git" || -f "$sdk/.git" ]] || return 1
    origin="$(jfs_fvm_timed /usr/bin/env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR GIT_NO_LAZY_FETCH=1 GIT_TERMINAL_PROMPT=0 /usr/bin/git --no-optional-locks -c core.fsmonitor=false -C "$sdk" config --get remote.origin.url 2>/dev/null)" || return 1
    case "${origin%/}" in https://github.com/flutter/flutter|https://github.com/flutter/flutter.git|git@github.com:flutter/flutter.git|ssh://git@github.com/flutter/flutter.git) return 0 ;; esac
    return 1
}
jfs_route_protect_private_namespace() {
    if (( ${#JFS_BASES}>1 )) && [[ -n "$JFS_REALM" || "${JFS_PUBLIC_EVIDENCE:-0}" != 1 ]]; then
        JFS_BASES=("${JFS_SDK_DEFAULT_BASE:-https://storage.googleapis.com}")
        JFS_TRUST_NOTE+=' 对象未能证明属于公开标准命名空间，仅检查原SDK源与既有网络路线，不发送到新增镜像。'
    fi
}
# 无制品身份时只检测实际Git来源；没有可解析来源便保留原命令，不猜公共stable。
jfs_route_unresolved_identity() {
    local origin="${JFS_SOURCE_URL:-}"
    if [[ -d "$JFS_SDK_ROOT/.git" || -f "$JFS_SDK_ROOT/.git" ]]; then
        origin="$(jfs_fvm_timed /usr/bin/env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR GIT_NO_LAZY_FETCH=1 GIT_TERMINAL_PROMPT=0 /usr/bin/git --no-optional-locks -c core.fsmonitor=false -C "$JFS_SDK_ROOT" remote get-url origin 2>/dev/null)" || origin="${JFS_SOURCE_URL:-}"
    fi
    if [[ -n "$origin" && "$origin" != *$'\n'* ]]; then
        JFS_SOURCE_URL="$origin" JFS_MODE=git JFS_BASES=('') JFS_TRUST_NOTE='制品身份尚未解析，仅预检实际Git来源；保留SDK来源与原命令，不猜公共stable或声明二进制已验证。'
    else
        JFS_IDENTITY_UNRESOLVED=1 JFS_WARM=1
    fi
    return 0
}
# 根据具体版本/架构或SDK engine确定对象，官方不可达时允许已获准可信来源继续验证。
jfs_route_target() {
    local identity="" arm="" manifest="" details="" metadata_url="" base="" manifest_source=""
    arm="$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)"; JFS_ARCH=x64; [[ "$arm" != 1 ]] || JFS_ARCH=arm64
    identity="$(jfs_route_data identity "$JFS_SDK_ROOT" "$JFS_VERSION" "$JFS_ARCH" "${FLUTTER_PREBUILT_ENGINE_VERSION:-}")" || return 1
    JFS_VERSION="${identity%%$'\t'*}" JFS_ENGINE="${identity#*$'\t'}" JFS_WARM=0 JFS_IDENTITY_UNRESOLVED=0
    JFS_REALM="$(jfs_route_data realm "$JFS_SDK_ROOT" "${FLUTTER_REALM:-}" 2>/dev/null)" || return 2
    if [[ "$JFS_MODE" == dart && -n "$JFS_ENGINE" && -x "$JFS_SDK_ROOT/bin/cache/dart-sdk/bin/dart" && -f "$JFS_SDK_ROOT/bin/cache/engine-dart-sdk.stamp" && "$(<"$JFS_SDK_ROOT/bin/cache/engine-dart-sdk.stamp")" == "$JFS_ENGINE" ]]; then JFS_WARM=1; return 0; fi
    if [[ "$JFS_MODE" == git || "$JFS_MODE" == source ]]; then [[ -n "$JFS_SOURCE_URL" ]] || return 2; return 0; fi
    JFS_OBJECT="" JFS_SHA="" JFS_SIZE="" JFS_MD5="" JFS_TRUST_NOTE="" JFS_PUBLIC_EVIDENCE=0
    local private_target=0
    if (( ${#JFS_BASES}==1 )) && [[ "$JFS_BASES[1]" != https://storage.googleapis.com && "$JFS_BASES[1]" != https://storage.flutter-io.cn ]]; then private_target=1; fi
    [[ -z "$JFS_REALM" && -z "${FLUTTER_PREBUILT_ENGINE_VERSION:-}" ]] || private_target=1
    if [[ "$JFS_MODE" == archive && ( -d "$JFS_SDK_ROOT/.git" || -f "$JFS_SDK_ROOT/.git" ) ]] && ! jfs_route_sdk_is_official "$JFS_SDK_ROOT"; then private_target=1; fi
    if [[ "$JFS_MODE" == archive && -n "$JFS_SOURCE_URL" ]]; then
        case "${JFS_SOURCE_URL%/}" in https://github.com/flutter/flutter|https://github.com/flutter/flutter.git) ;; *) private_target=1 ;; esac
    fi
    if [[ "$JFS_MODE" == archive && "$private_target" == 1 ]]; then
        if [[ -n "$JFS_ENGINE" ]]; then JFS_MODE=platform
        else jfs_route_unresolved_identity; return $?; fi
    elif [[ ( "$JFS_MODE" != archive && -z "$JFS_ENGINE" ) || ( "$JFS_MODE" == archive && -z "$JFS_REQUESTED_VERSION" ) ]]; then
        jfs_route_unresolved_identity; return $?
    fi
    if [[ -n "$JFS_ENGINE" && "$JFS_MODE" != archive ]]; then
        if [[ -z "$JFS_REALM" && -z "${FLUTTER_PREBUILT_ENGINE_VERSION:-}" ]] && jfs_route_sdk_is_official "$JFS_SDK_ROOT"; then JFS_PUBLIC_EVIDENCE=1; fi
        JFS_OBJECT="flutter_infra_release/flutter/$JFS_ENGINE/dart-sdk-darwin-$JFS_ARCH.zip"
        [[ -z "$JFS_REALM" ]] || JFS_OBJECT="$JFS_REALM/$JFS_OBJECT"
    else
        manifest="$JFS_PROBE_DIR/releases.json"
        if jfs_route_fetch_json 'https://www.googleapis.com/storage/v1/b/flutter_infra_release/o/releases%2Freleases_macos.json?alt=media' "$manifest" &&
           details="$(jfs_route_data manifest "$manifest" "${JFS_VERSION:-stable}" "$JFS_ARCH" 2>/dev/null)"; then
            manifest_source='Google官方发布清单'
        else
            details=""
            for base in "${JFS_BASES[@]}"; do
                if jfs_route_fetch_json "${base%/}/flutter_infra_release/releases/releases_macos.json" "$manifest" &&
                   details="$(jfs_route_data manifest "$manifest" "${JFS_VERSION:-stable}" "$JFS_ARCH" 2>/dev/null)"; then
                    manifest_source="$base 发布清单"; break
                fi
            done
        fi
        [[ -n "$details" ]] || return 1
        IFS=$'\t' read -r JFS_VERSION JFS_OBJECT JFS_SHA JFS_ENGINE <<< "$details"
        JFS_TRUST_NOTE="发布SHA来源：$manifest_source；具体版本/宿主架构已匹配。"
        case "$manifest_source" in Google*|https://storage.googleapis.com*|https://storage.flutter-io.cn*) JFS_PUBLIC_EVIDENCE=1 ;; esac
    fi
    # 自定义显式源或fork源不向Google泄露其私有engine，也不宣称官方等价。
    if (( ${#JFS_BASES}==1 )) && [[ "$JFS_BASES[1]" != https://storage.googleapis.com && ( "$JFS_BASES[1]" != https://storage.flutter-io.cn || -n "$JFS_REALM" || -n "${FLUTTER_PREBUILT_ENGINE_VERSION:-}" ) ]]; then
        JFS_TRUST_NOTE+=" 自定义来源保持原URL，仅验证精确engine/版本/架构路径及Range/传输一致性，不声明与官方等价。"
        return 0
    fi
    metadata_url="$(jfs_route_data metadata-url "$JFS_OBJECT")" || return 1
    if jfs_route_fetch_json "$metadata_url" "$JFS_PROBE_DIR/object.json" &&
       details="$(jfs_route_data metadata "$JFS_PROBE_DIR/object.json" "$JFS_OBJECT" 2>/dev/null)"; then
        IFS=$'\t' read -r JFS_SIZE JFS_MD5 <<< "$details"
        JFS_TRUST_NOTE+=' 官方对象总长/MD5与候选ETag核验。'
        [[ -n "$JFS_REALM" ]] || JFS_PUBLIC_EVIDENCE=1
    else
        JFS_TRUST_NOTE+=' 官方摘要不可达，使用已获准可信来源的精确路径、Range总长/ETag及正文样本一致性；不冒称官方摘要核验。'
    fi
    jfs_route_protect_private_namespace
}

# 各候选并发探测；--max-filesize和子进程文件限额防止服务器忽略Range时下载整个SDK。
jfs_route_probe() (
    local id="$1" base="$2" mode="$3" proxy="$4" url="" result=0 ref="${JOBS_FLUTTER_ROUTE_GIT_REF:-}" started=0 elapsed=0 pid=""
    local prefix="$JFS_PROBE_DIR/probe.$id"
    ulimit -f 512
    if [[ "$JFS_MODE" == git ]]; then
        jfs_route_apply_proxy "$mode" "$proxy"
        [[ -n "$ref" ]] || { ref="refs/tags/$JFS_VERSION"; case "$JFS_VERSION" in stable|beta|main|master|dev) ref="refs/heads/$JFS_VERSION" ;; '') ref=HEAD ;; esac; }
        zmodload zsh/datetime
        started="$EPOCHREALTIME"
        /usr/bin/env GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 GIT_NO_LAZY_FETCH=1 "${JOBS_FLUTTER_ROUTE_GIT:-/usr/bin/git}" -c protocol.version=2 ls-remote --exit-code "$JFS_SOURCE_URL" "$ref" > "$prefix.body" 2> "$prefix.error" &
        pid=$!
        while /bin/kill -0 "$pid" 2>/dev/null; do
            if (( EPOCHREALTIME-started>=6 )); then jfs_route_stop_tree "$pid"; wait "$pid" 2>/dev/null; return 124; fi
            /bin/sleep 0.1
        done
        wait "$pid" || return $?
        /usr/bin/awk -v ref="$ref" '$2==ref && $1 ~ /^[0-9a-f]+$/ && length($1)==40 {found=1} END {exit !found}' "$prefix.body" || return 1
        elapsed=$(( EPOCHREALTIME-started ))
        printf '1\t%.4f\t%s\n' "$elapsed" "$(/usr/bin/wc -c < "$prefix.body")" > "$prefix.valid"
        return 0
    fi
    url="$JFS_SOURCE_URL"
    [[ "$JFS_MODE" == source ]] || url="${base%/}/$JFS_OBJECT"
    jfs_route_curl "$mode" "$proxy" --range 0-262143 --max-filesize 262144 --header 'Accept-Encoding: identity' --dump-header "$prefix.headers" --output "$prefix.body" --write-out '%{http_code}\t%{time_starttransfer}\t%{speed_download}\t%{time_total}' "$url" > "$prefix.metrics" 2> "$prefix.error" || result=$?
    # 只要获得足够且身份正确的206样本，低速导致的当次超时仍可参与真实指标比较。
    (( result==0 || result==28 )) || return "$result"
    jfs_route_data probe "$prefix.headers" "$prefix.body" "$prefix.metrics" "$JFS_SIZE" "$JFS_MD5" "$JFS_MODE" "${JOBS_FLUTTER_ROUTE_EXPECTED_TEXT:-}" "$result" > "$prefix.valid" 2> "$prefix.invalid" || return 1
)
# 缓存只接受本次输入指纹；源码/版本/架构/显式空值变化都重新探测。
jfs_route_key() {
    setopt LOCAL_OPTIONS
    unsetopt NOUNSET
    local name="" cache_engine="$JFS_ENGINE"
    [[ "$JFS_MODE" != archive ]] || cache_engine=""
    { print -r -- "private-identity-v2|$JFS_SDK_ROOT|$JFS_REQUESTED_VERSION|$JFS_ARCH|$cache_engine|${JFS_MODE/(dart|platform)/artifact}|$JFS_REALM|$JFS_SDK_DEFAULT_BASE|$JFS_SOURCE_URL|${JOBS_FLUTTER_ROUTE_GIT_REF:-}|${JOBS_FLUTTER_ROUTE_EXPECTED_TEXT:-}"
      [[ ! -f "${JOBS_FLUTTER_ROUTE_CURL_CONFIG:-}" ]] || /usr/bin/shasum -a 256 "$JOBS_FLUTTER_ROUTE_CURL_CONFIG"
      for name in FLUTTER_STORAGE_BASE_URL PUB_HOSTED_URL FLUTTER_REALM HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy NO_PROXY no_proxy; do print -r -- "$name:${+parameters[$name]}:${(P)name}"; done
    } | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}
# 失败的AUTO路线短时冷却，避免小样本始终最快却实际下载永远失败。
jfs_route_fingerprint() {
    print -rn -- "$1|$2|$3" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}
jfs_route_is_cooling() {
    local route="$1" now="$2" failed_at=""
    [[ -f "$JFS_ROUTE_FAILED_FILE" ]] || return 1
    failed_at="$(/usr/bin/awk -v key="$route" '$2==key{stamp=$1} END{print stamp}' "$JFS_ROUTE_FAILED_FILE")"
    [[ "$failed_at" == <-> ]] && (( now-failed_at<60 && now>=failed_at ))
}
# 读取受控缓存字段，不eval任何下载结果。
jfs_route_apply_cache() {
    local data="$1" key="" value="" base="" mode="" proxy=""
    while IFS=$'\t' read -r key value; do
        case "$key" in base) base="$value" ;; proxyMode) mode="$value" ;; proxy) proxy="$value" ;; object) export JOBS_FLUTTER_ROUTE_OBJECT_PATH="$value" ;; sha) export JOBS_FLUTTER_ROUTE_EXPECTED_SHA256="$value" ;; version) export JOBS_FLUTTER_ROUTE_RESOLVED_VERSION="$value" ;; esac
    done <<< "$data"
    if [[ "$JFS_MODE" != git && "$JFS_MODE" != source && ${+FLUTTER_STORAGE_BASE_URL} == 0 ]]; then export FLUTTER_STORAGE_BASE_URL="$base"; fi
    jfs_route_apply_proxy "$mode" "$proxy"
    JFS_ROUTE_SELECTED_ROUTE="$(jfs_route_fingerprint "$base" "$mode" "$proxy")"
}
# 低层接口只供已经隔离作用域的调用者；普通入口使用下面的子进程wrapper。
jobs_flutter_route_prepare() {
    setopt LOCAL_OPTIONS
    unsetopt NOUNSET
    local sdk="$1" version="$2" log_file="$3" mode="${4:-${JOBS_FLUTTER_ROUTE_MODE:-dart}}" attempt=1 delay=2 now=0 key="" cache="" data="" base="" id=0 index=0 task="" best="" speed=0 ttfb=0 bytes=0 best_speed=-1 best_ttfb=999 result=0
    local -a bases=() tasks=() ids=() candidate_bases=() candidate_modes=() candidate_proxies=()
    JFS_SDK_ROOT="$sdk" JFS_REQUESTED_VERSION="$version" JFS_VERSION="$version" JFS_MODE="$mode" JFS_SOURCE_URL="${JOBS_FLUTTER_ROUTE_SOURCE_URL:-}" JFS_ENGINE="" JFS_ARCH="" JFS_OBJECT="" JFS_SHA="" JFS_SIZE="" JFS_MD5=""
    case "$mode" in dart|platform|archive|git|source) ;; *) return 2 ;; esac
    if [[ "$mode" == git || "$mode" == source ]]; then [[ -n "$JFS_SOURCE_URL" && "$JFS_SOURCE_URL" != *$'\n'* ]] || return 2; fi
    jfs_route_cache_init || return 1
    export JOBS_FLUTTER_ROUTE_CACHE_DIR="$JFS_ROUTE_CACHE_DIR"
    while true; do
        JFS_PROBE_DIR="$(/usr/bin/mktemp -d "$JFS_ROUTE_CACHE_DIR/probe.XXXXXX")" || return 1
        jfs_route_candidates
        jfs_route_bases
        JFS_REALM="$(jfs_route_data realm "$JFS_SDK_ROOT" "${FLUTTER_REALM:-}" 2>/dev/null)" || return 2
        JFS_ARCH=x64; [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)" != 1 ]] || JFS_ARCH=arm64
        local local_identity=""
        local_identity="$(jfs_route_data identity "$JFS_SDK_ROOT" "$JFS_REQUESTED_VERSION" "$JFS_ARCH" "${FLUTTER_PREBUILT_ENGINE_VERSION:-}")" || return 2
        JFS_ENGINE="${local_identity#*$'\t'}"
        key="$(jfs_route_key)"; cache="$JFS_ROUTE_CACHE_DIR/$key.json"; JFS_ROUTE_SELECTED_CACHE="$cache"; JFS_ROUTE_FAILED_FILE="$JFS_ROUTE_CACHE_DIR/$key.failed"; JFS_ROUTE_LOG="$log_file"; now="$(/bin/date +%s)"
        local source_count=${#JFS_BASES}
        JFS_ROUTE_ROTATION_ALLOWED=0
        (( source_count*${#JFS_PROXY_MODES}>1 )) && JFS_ROUTE_ROTATION_ALLOWED=1
        if data="$(jfs_route_data cache-read "$cache" "$key" "$now" 2>/dev/null)"; then
            jfs_route_note "$log_file" "✓ 复用本任务300秒内同版本/架构/配置的SDK路线；无需重复联网测速。"
            jfs_route_apply_cache "$data"; return 0
        fi
        if [[ "$mode" != dart || -z "$JFS_ENGINE" || ! -x "$JFS_SDK_ROOT/bin/cache/dart-sdk/bin/dart" || ! -f "$JFS_SDK_ROOT/bin/cache/engine-dart-sdk.stamp" || "$(<"$JFS_SDK_ROOT/bin/cache/engine-dart-sdk.stamp")" != "$JFS_ENGINE" ]]; then
            jfs_route_note "$log_file" "▶ SDK网络准备第${attempt}轮：仅本轮进程使用原有源/代理候选，显式值及空值保留；系统/Git/Shell配置不变，退出目标进程即撤回。"
        fi
        if jfs_route_target; then
            if (( JFS_WARM )); then
                if [[ "${JFS_IDENTITY_UNRESOLVED:-0}" == 1 ]]; then
                    jfs_route_note "$log_file" 'ℹ SDK制品身份及原Git来源尚未解析；保留显式源、代理和原命令继续，不猜公共stable，不宣称二进制已通过网络验证。'
                else
                    jfs_route_note "$log_file" '✓ 本地SDK的目标Engine/Dart缓存已就绪，复用健康环境；无下载网络探测。'
                fi
                return 0
            fi
            # 目标重分类后不能把Git路线缓存当archive源读取并导出空storage。
            if [[ "$JFS_MODE" != "$mode" ]]; then
                key="$(jfs_route_key)"; cache="$JFS_ROUTE_CACHE_DIR/$key.json"; JFS_ROUTE_SELECTED_CACHE="$cache"; JFS_ROUTE_FAILED_FILE="$JFS_ROUTE_CACHE_DIR/$key.failed"
            fi
            bases=("${JFS_BASES[@]}")
            JFS_ROUTE_ROTATION_ALLOWED=0
            (( ${#bases}*${#JFS_PROXY_MODES}>1 )) && JFS_ROUTE_ROTATION_ALLOWED=1
            [[ -z "${JFS_TRUST_NOTE:-}" ]] || jfs_route_note "$log_file" "ℹ $JFS_TRUST_NOTE"
            jfs_route_note "$log_file" "▶ SDK网络检测：${JFS_VERSION:-未解析} / Darwin $JFS_ARCH；Engine：${JFS_ENGINE:-不适用}；原始源：${JFS_SOURCE_URL:-${(j:, :)bases}}；每候选连接2秒/总计6秒，小样本≤256KiB。"
            tasks=() ids=() candidate_bases=() candidate_modes=() candidate_proxies=(); id=0
            for base in "${bases[@]}"; do
                for (( index=1; index<=${#JFS_PROXY_MODES}; index++ )); do
                    (( id++ )); ids+=("$id"); candidate_bases+=("$base"); candidate_modes+=("$JFS_PROXY_MODES[index]"); candidate_proxies+=("$JFS_PROXY_URLS[index]")
                    jfs_route_probe "$id" "$base" "$JFS_PROXY_MODES[index]" "$JFS_PROXY_URLS[index]" & tasks+=($!)
                done
            done
            for task in "${tasks[@]}"; do wait "$task" 2>/dev/null || true; done
            best=""; best_speed=-1; best_ttfb=999
            local reference_prefix="" sample_prefix=""
            for id in "${ids[@]}"; do
                if [[ -s "$JFS_PROBE_DIR/probe.$id.valid" ]]; then
                    sample_prefix="$(/bin/dd if="$JFS_PROBE_DIR/probe.$id.body" bs=4096 count=1 2>/dev/null | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
                    if [[ -n "$reference_prefix" && "$sample_prefix" != "$reference_prefix" ]]; then
                        jfs_route_note "$log_file" "⚠ 候选$id与同一目标的其它有效样本前缀/引用不一致，拒绝。"
                        continue
                    fi
                    reference_prefix="$sample_prefix"
                    local route_id="$(jfs_route_fingerprint "$candidate_bases[id]" "$candidate_modes[id]" "$candidate_proxies[id]")"
                    if (( JFS_ROUTE_ROTATION_ALLOWED )) && jfs_route_is_cooling "$route_id" "$now"; then
                        jfs_route_note "$log_file" "➤ 候选$id小样本有效，但其真实获取刚失败，AUTO冷却60秒；优先尝试其它已验证路线。"
                        continue
                    fi
                    IFS=$'\t' read -r speed ttfb bytes < "$JFS_PROBE_DIR/probe.$id.valid"
                    if [[ "$mode" == git ]]; then speed=$(( 1.0/(ttfb+0.001) )); fi
                    if [[ "$mode" == git ]]; then
                        jfs_route_note "$log_file" "✓ 候选$id：$JFS_SOURCE_URL；网络：${candidate_modes[id]} ${candidate_proxies[id]}；Git目标ref查询=${ttfb}s；引用元数据=${bytes}B。"
                    else
                        jfs_route_note "$log_file" "✓ 候选$id：${candidate_bases[id]:-$JFS_SOURCE_URL}；网络：${candidate_modes[id]} ${candidate_proxies[id]}；首字节=${ttfb}s；样本=${bytes}B；吞吐=${speed}B/s。"
                    fi
                    if (( speed>best_speed || (speed==best_speed && ttfb<best_ttfb) )); then best="$id"; best_speed="$speed"; best_ttfb="$ttfb"; fi
                else
                    jfs_route_note "$log_file" "⚠ 候选$id未通过真实响应/目标对象校验：${candidate_bases[id]:-$JFS_SOURCE_URL}；网络：${candidate_modes[id]} ${candidate_proxies[id]}。"
                fi
            done
            if [[ -n "$best" ]]; then
                jfs_route_data cache-write "$cache" "$key" "$now" "$candidate_bases[best]" "$candidate_modes[best]" "$candidate_proxies[best]" "$JFS_OBJECT" "$JFS_SHA" "$JFS_SIZE" "$JFS_MD5" "$JFS_VERSION" >/dev/null || return 1
                data="$(jfs_route_data cache-read "$cache" "$key" "$now")" || return 1
                jfs_route_note "$log_file" "➤ 选用候选$best：身份校验通过，实测指标最高；仅本轮SDK进程及子进程生效，退出后按原入口启动即撤回。"
                jfs_route_apply_cache "$data"; return 0
            fi
        fi
        if [[ "${JOBS_FLUTTER_ROUTE_PREPARE_ONCE:-0}" == 1 ]]; then jfs_route_note "$log_file" "⚠ SDK网络不可达，本轮有界检测已结束；返回上层原有网络重试/双栈回退。"; return 75; fi
        jfs_route_note "$log_file" "⚠ SDK网络第${attempt}轮没有可验证可用路线；${delay}秒后自动重新检测，Ctrl+C结束；尚未进入SDK/业务。"
        /bin/sleep "$delay" || return 130
        (( attempt++ )); (( delay>=30 )) || delay=$((delay*2)); (( delay<=30 )) || delay=30
    done
}
# 下载失败只删除本模块自己的路线缓存，不清理SDK或用户下载片段。
jobs_flutter_route_invalidate() {
    if [[ "${JFS_ROUTE_ROTATION_ALLOWED:-0}" == 1 && -n "${JFS_ROUTE_SELECTED_ROUTE:-}" && "$JFS_ROUTE_FAILED_FILE" == "$JFS_ROUTE_CACHE_DIR/"*.failed ]]; then
        print -r -- "$(/bin/date +%s) $JFS_ROUTE_SELECTED_ROUTE" >> "$JFS_ROUTE_FAILED_FILE"
        /bin/chmod 600 "$JFS_ROUTE_FAILED_FILE"
        jfs_route_note "${JFS_ROUTE_LOG:-}" '➤ 本次实际获取失败，AUTO候选已短时冷却，下一轮优先其它已验证路线；显式配置不变。'
    fi
    [[ -z "${JFS_ROUTE_SELECTED_CACHE:-}" || "$JFS_ROUTE_SELECTED_CACHE" != "$JFS_ROUTE_CACHE_DIR/"*.json ]] || /bin/rm -f -- "$JFS_ROUTE_SELECTED_CACHE"
}
# 普通入口：独立子进程内选择路线和运行SDK，完整保留命令参数、stdin及stdout。
jobs_flutter_sdk_retry() {
    setopt LOCAL_OPTIONS LOCAL_TRAPS
    unsetopt NOUNSET
    local title="$1" log_file="$2" sdk="$3" version="$4" child="" result=0 cancelled=0 token=""; shift 4
    jfs_route_cache_init || return 1
    if [[ -z "$sdk" ]]; then
        for token in "$@"; do [[ "$token" == */bin/flutter ]] && sdk="${token:A:h:h}" && break; done
        [[ -n "$sdk" || ! -d "$PWD/.fvm/flutter_sdk" ]] || sdk="${PWD}/.fvm/flutter_sdk"
        [[ -n "$sdk" || -z "${commands[flutter]:-}" ]] || sdk="${commands[flutter]:A:h:h}"
    fi
    trap 'cancelled=130; [[ -z "$child" ]] || jfs_route_stop_tree "$child"' INT
    trap 'cancelled=143; [[ -z "$child" ]] || jfs_route_stop_tree "$child"' TERM
    trap 'cancelled=129; [[ -z "$child" ]] || jfs_route_stop_tree "$child"' HUP
    (
        local attempt=1 delay=2 code=0 name="" offset=0 detail="" route_mode=""
        local -A original_values original_set
        for name in FLUTTER_STORAGE_BASE_URL HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy NO_PROXY no_proxy; do original_set[$name]="${+parameters[$name]}"; original_values[$name]="${(P)name}"; done
        while true; do
            for name in ${(k)original_set}; do if [[ "$original_set[$name]" == 1 ]]; then export "$name=$original_values[$name]"; else unset "$name"; fi; done
            route_mode="${JOBS_FLUTTER_ROUTE_MODE:-dart}"
            if [[ "${JOBS_FLUTTER_ROUTE_LEGACY_FVM_AUTO:-0}" == 1 && -s "$sdk/bin/internal/engine.version" ]]; then
                route_mode=platform
                jfs_route_note "$log_file" 'ℹ 旧FVM源码已落地，按其当前engine代表制品检测；后续Git仍保持原源，不把当前engine冒称新版本。'
            fi
            jobs_flutter_route_prepare "$sdk" "$version" "$log_file" "$route_mode" || exit $?
            jfs_route_note "$log_file" "▶ $title；SDK获取第${attempt}次，失败自动重新测路并重试。"
            offset=0; [[ ! -f "$log_file" ]] || offset="$(/usr/bin/wc -c < "$log_file")"
            [[ "${JOBS_SDK_LOG_REPLACED:-0}" != 1 ]] || offset=0
            code=0
            if [[ "${JOBS_FLUTTER_ROUTE_CAPTURE_OUTPUT:-0}" == 1 ]]; then
                "$@" > >(/usr/bin/tee -a "$log_file") 2> >(/usr/bin/tee -a "$log_file" >&2) || code=$?
            else
                "$@" || code=$?
            fi
            if [[ "${JOBS_FLUTTER_ROUTE_ONCE:-0}" == 1 ]]; then exit "$code"; fi
            detail=""; [[ ! -f "$log_file" ]] || detail="$(/usr/bin/tail -c +$((offset+1)) "$log_file" | /usr/bin/tail -c 65536)"
            if (( code==0 )) && print -r -- "$detail" | /usr/bin/grep -Eqi 'Failed to download|Error downloading|Unable to download|Could not download|Download failed'; then code=1; fi
            (( code!=0 )) || exit 0
            case "$code" in 126|127|129|130|131|137|143) exit "$code" ;; esac
            if print -r -- "$detail" | /usr/bin/grep -Eqi 'Permission denied|Operation not permitted|No space left|Bad CPU type|No available formula|No formulae found|Failed to find package|unknown option|invalid argument|bad substitution|syntax error|read-only variable|Exec format error|license.*(not accepted|rejected)'; then exit "$code"; fi
            jobs_flutter_route_invalidate
            jfs_route_note "$log_file" "⚠ SDK获取未完成（$code），已使本轮路线缓存失效；${delay}秒后重测并重试。"
            /bin/sleep "$delay" || exit 130
            (( attempt++ )); (( delay>=30 )) || delay=$((delay*2)); (( delay<=30 )) || delay=30
        done
    ) <&0 &
    child=$!
    wait "$child" || result=$?
    (( cancelled==0 )) || return "$cancelled"
    return "$result"
}
# 业务只执行一次；调用方先单独使用--version准备SDK，不因业务失败重复构建/运行。
jobs_flutter_sdk_once() {
    JOBS_FLUTTER_ROUTE_ONCE=1 jobs_flutter_sdk_retry "$@"
}
# 仅静态确认文本FVM入口依赖PATH Dart时，准备其真正的Flutter Dart宿主。
# stdout保持空，避免污染 FVM_BIN=$(finder) 等机器输出。
jobs_flutter_fvm_runtime() {
    setopt LOCAL_OPTIONS
    unsetopt NOUNSET
    local title="$1" log_file="$2" manager="$3" kind="" body="" dart_bin="" sdk="" expected=""
    [[ -r "$manager" && -f "$manager" ]] || return 0
    manager="${manager:A}"
    kind="$(/usr/bin/file -b "$manager" 2>/dev/null)" || return 0
    case "$kind" in *Mach-O*|*ELF*) return 0 ;; *text*|*script*) ;; *) return 0 ;; esac
    body="$(/usr/bin/head -c 65536 "$manager")"
    # A local dart function/alias or changed PATH cannot prove an external dependency.
    print -r -- "$body" | /usr/bin/grep -Eq '^[[:space:]]*((function[[:space:]]+)?dart[[:space:]]*\(|alias[[:space:]]+dart=|export[[:space:]]+PATH=|PATH=)' && return 0
    print -r -- "$body" | /usr/bin/grep -Eq '^[[:space:]]*((exec|command|if)[[:space:]]+)?dart([[:space:];]|$)|^#![[:space:]]*/usr/bin/env([[:space:]]+-S)?[[:space:]]+dart([[:space:]]|$)' || return 0
    dart_bin="$(whence -p dart 2>/dev/null)" || return 0
    dart_bin="${dart_bin:A}"
    [[ "${dart_bin:t}" == dart && "${dart_bin:h:t}" == bin ]] || return 0
    sdk="${dart_bin:h:h}"
    [[ -x "$sdk/bin/flutter" && -f "$sdk/bin/internal/update_dart_sdk.sh" && -f "$sdk/bin/internal/shared.sh" ]] || return 0
    # Standalone/native Dart is already executable and must not trigger another SDK.
    kind="$(/usr/bin/file -b "$dart_bin" 2>/dev/null)" || return 0
    case "$kind" in *Mach-O*|*ELF*) return 0 ;; *text*|*script*) ;; *) return 0 ;; esac
    /usr/bin/grep -Eq 'shared\.sh|cache/dart-sdk' "$dart_bin" || return 0
    expected="${FLUTTER_PREBUILT_ENGINE_VERSION:-}"
    [[ -n "$expected" || ! -f "$sdk/bin/internal/engine.version" ]] || expected="$(<"$sdk/bin/internal/engine.version")"
    if [[ -n "$expected" && -x "$sdk/bin/cache/dart-sdk/bin/dart" && -f "$sdk/bin/cache/engine-dart-sdk.stamp" && "$(<"$sdk/bin/cache/engine-dart-sdk.stamp")" == "$expected" ]]; then return 0; fi
    jfs_route_note "$log_file" '▶ FVM文本入口依赖当前PATH的Flutter Dart shim；先准备该真实运行时，再查询FVM元数据。'
    JOBS_FLUTTER_ROUTE_MODE=dart JOBS_FLUTTER_ROUTE_CAPTURE_OUTPUT=1 \
        jobs_flutter_sdk_retry "$title" "$log_file" "$sdk" '' "$sdk/bin/flutter" --version >&2
}

# 小型只读命令必须有界；仅过滤后的上下文字段通过stdout，不落完整环境JSON。
jfs_fvm_timed() (
    local child_pid='' started=$SECONDS result=0
    trap '[[ -z "$child_pid" ]] || jfs_route_stop_tree "$child_pid"; exit 130' INT
    trap '[[ -z "$child_pid" ]] || jfs_route_stop_tree "$child_pid"; exit 143' TERM
    trap '[[ -z "$child_pid" ]] || jfs_route_stop_tree "$child_pid"; exit 129' HUP
    "$@" <&0 &
    child_pid=$!
    while /bin/kill -0 "$child_pid" 2>/dev/null; do
        if (( SECONDS-started>=10 )); then
            jfs_route_stop_tree "$child_pid"
            wait "$child_pid" 2>/dev/null
            return 124
        fi
        /bin/sleep 0.1
    done
    wait "$child_pid" || result=$?
    return "$result"
)
# FVM context包含完整环境，仅在内存管道筛选实际Git源和SDK缓存位置。
jfs_fvm_context_fields() {
    local fvm_bin="$1" requested="$2"
    "$fvm_bin" api context 2>/dev/null | /usr/bin/ruby -rjson -e '
      begin
        c=JSON.parse(STDIN.read).fetch("context")
        url=c["flutterUrl"]; cache=c["versionsCachePath"]; wanted=ARGV.fetch(0)
        if wanted.include?("/")
          fork=wanted.split("/",2).first; forks=(c["config"]||{})["forks"]
          entry=forks.is_a?(Hash) ? forks[fork] : nil
          url=entry if entry.is_a?(String)
          url=entry["url"] || entry["flutterUrl"] if entry.is_a?(Hash)
          raise "unresolved fork" if entry.nil?
        end
        raise "missing fields" unless url.is_a?(String) && !url.empty? && cache.is_a?(String) && cache.start_with?("/")
        raise "unsafe fields" if [url,cache].any?{|s|s.match?(/[\x00-\x1f\x7f]/)}
        STDOUT.write([url,cache].join("\t"))
      rescue StandardError
        exit 1
      end
    ' "$requested"
    local -a command_status=("${pipestatus[@]}")
    (( command_status[1]==0 && command_status[2]==0 ))
}
# 老FVM无context API时只读既有配置，不改用户源，不从版本目录猜fork仓库。
jfs_fvm_legacy_fields() {
    /usr/bin/ruby -rjson -e '
      begin
        wanted=ARGV.fetch(0); root=ENV.fetch("HOME")
        cfg={}; file=File.join(root,"Library/Application Support/fvm/.fvmrc")
        cfg=JSON.parse(File.read(file)) if File.file?(file)
        [File.join(Dir.pwd,".fvmrc"),File.join(Dir.pwd,".fvm/fvm_config.json")].each do |project_file|
          if File.file?(project_file)
            project=JSON.parse(File.read(project_file)); cfg=cfg.merge(project); break
          end
        end
        url=ENV.key?("FVM_FLUTTER_URL") ? ENV["FVM_FLUTTER_URL"] : cfg["flutterUrl"]
        url="https://github.com/flutter/flutter.git" if url.nil?
        cache=ENV["FVM_CACHE_PATH"] || ENV["FVM_HOME"] || cfg["cachePath"]
        cache=File.join(root,File.directory?(File.join(root,".fvm/versions")) ? ".fvm" : "fvm") if cache.nil? || cache.empty?
        cache=File.join(cache,"versions")
        if wanted.include?("/")
          forks=cfg["forks"]; entry=forks.is_a?(Hash) ? forks[wanted.split("/",2).first] : nil
          url=entry if entry.is_a?(String)
          url=entry["url"] || entry["flutterUrl"] if entry.is_a?(Hash)
          raise "unresolved fork" if entry.nil?
        end
        raise "unsafe fields" unless url.is_a?(String) && !url.empty? && cache.start_with?("/")
        raise "unsafe fields" if [url,cache].any?{|s|s.match?(/[\x00-\x1f\x7f]/)}
        STDOUT.write([url,cache].join("\t"))
      rescue StandardError
        exit 1
      end
    ' "$1"
}
# 把Git获取返回零但缺SDK入口的残缺安装继续留在获取阶段。
jfs_fvm_install_once() {
    local log_file="$1" sdk="$2" fvm_bin="$3" version="$4" code=0
    shift 4
    "$fvm_bin" install "$version" "$@" 2>&1 | /usr/bin/tee -a "$log_file"
    code=${pipestatus[1]}
    (( code==0 )) || return "$code"
    [[ -x "$sdk/bin/flutter" ]] || { jfs_route_note "$log_file" '⚠ FVM返回成功但Flutter入口缺失，将重新获取。'; return 1; }
}
# 旧组合通道先验证同一实际网络环境可读原Git，再执行安装，不能重写其来源。
jfs_fvm_combined_once() {
    local log_file="$1" sdk="$2" fvm_bin="$3" version="$4" url="$5" ref="$6" code=0
    shift 6
    jfs_fvm_timed /usr/bin/env GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 "${JOBS_FLUTTER_ROUTE_GIT:-/usr/bin/git}" -c protocol.version=2 ls-remote --exit-code "$url" "$ref" >/dev/null 2>&1 || code=$?
    (( code==0 )) || { jfs_route_note "$log_file" "⚠ FVM组合通道的原Git源未通过有界检查（$code）。"; return "$code"; }
    jfs_fvm_install_once "$log_file" "$sdk" "$fvm_bin" "$version" "$@"
}
# 先读FVM生效上下文，优先分离Git和SDK自举；原生附加参数及用户fork保持。
jobs_flutter_fvm_install() {
    setopt LOCAL_OPTIONS
    unsetopt NOUNSET
    local title="$1" log_file="$2" fvm_bin="$3" version="$4" fields='' source_url='' versions='' sdk='' help_text='' code=0
    local no_setup=0 setup_flag='' ref='' token=''
    local -a install_args=()
    shift 4
    [[ -n "$version" && "$version" != -* && "$version" != /* && "$version" != *$'\n'* && "$version" != *$'\r'* && "/$version/" != */../* && "/$version/" != */./* ]] || { jfs_route_note "$log_file" '✖ FVM版本为空或路径无效。'; return 2; }
    jobs_flutter_fvm_runtime "${title}：FVM所需Dart运行时" "$log_file" "$fvm_bin" || return $?
    fields="$(jfs_fvm_timed jfs_fvm_context_fields "$fvm_bin" "$version")" || code=$?
    case "$code" in 129|130|137|143) return "$code" ;; esac
    if [[ -z "$fields" ]]; then fields="$(jfs_fvm_legacy_fields "$version")" || { jfs_route_note "$log_file" '✖ 无法可靠取得FVM源/缓存配置，保留原配置并停止。'; return 2; }; fi
    IFS=$'\t' read -r source_url versions <<< "$fields"
    sdk="${versions%/}/$version"
    # 已存在的fork缓存以其真实origin为准，不将自定义仓库改为官方。
    if [[ -d "$sdk/.git" || -f "$sdk/.git" ]]; then
        token="$(/usr/bin/env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR /usr/bin/git --no-optional-locks -c core.fsmonitor=false -C "$sdk" remote get-url origin 2>/dev/null)" && source_url="$token"
    fi
    help_text="$(jfs_fvm_timed "$fvm_bin" install --help 2>/dev/null)" || code=$?
    case "$code" in 129|130|137|143) return "$code" ;; esac
    if [[ "$help_text" == *'--[no-]setup'* || "$help_text" == *'--no-setup'* ]]; then setup_flag=--no-setup
    elif [[ "$help_text" == *'--skip-setup'* ]]; then setup_flag=--skip-setup
    fi
    for token in "$@"; do
        case "$token" in
            --no-setup|--skip-setup) no_setup=1 ;;
            --setup|-s) ;;
            *) install_args+=("$token") ;;
        esac
    done
    token="${version##*/}"
    ref="refs/tags/${token#v}"
    case "$token" in stable|beta|dev|main|master) ref="refs/heads/$token" ;; esac
    [[ "$token" =~ '^[0-9a-fA-F]{7,40}$' ]] && ref=HEAD
    if [[ -n "$setup_flag" ]]; then
        install_args+=("$setup_flag")
        JOBS_FLUTTER_ROUTE_MODE=git JOBS_FLUTTER_ROUTE_SOURCE_URL="$source_url" JOBS_FLUTTER_ROUTE_GIT_REF="$ref" \
            jobs_flutter_sdk_retry "${title}：原Git源获取" "$log_file" "$sdk" "$version" jfs_fvm_install_once "$log_file" "$sdk" "$fvm_bin" "$version" "${install_args[@]}" || return $?
    else
        # 老版没有关闭自举的能力时，制品路线先选定，再验证同环境原Git源可用。
        [[ "$no_setup" == 0 ]] || { jfs_route_note "$log_file" '✖ 当前FVM无法兑现显式仅安装、不自举的要求；未执行安装。'; return 2; }
        local legacy_mode=git legacy_auto=1
        case "${source_url%/}" in
            https://github.com/flutter/flutter|https://github.com/flutter/flutter.git)
                if [[ "$token" == stable || "$token" == beta || "$token" == dev || "$token" =~ '^v?[0-9]+\.[0-9]+\.[0-9]+([-+].*)?$' ]]; then legacy_mode=archive; legacy_auto=0; fi ;;
        esac
        if (( legacy_auto )); then
            jfs_route_note "$log_file" 'ℹ 旧FVM无法分离自举且目标无可信公开archive：先检测原Git来源；源码形成后再检测实际engine制品，不宣称首轮已验证未知二进制。'
        fi
        JOBS_FLUTTER_ROUTE_MODE="$legacy_mode" JOBS_FLUTTER_ROUTE_LEGACY_FVM_AUTO="$legacy_auto" \
        JOBS_FLUTTER_ROUTE_SOURCE_URL="$source_url" JOBS_FLUTTER_ROUTE_GIT_REF="$ref" \
            jobs_flutter_sdk_retry "${title}：Git与制品组合通道" "$log_file" "$sdk" "$version" jfs_fvm_combined_once "$log_file" "$sdk" "$fvm_bin" "$version" "$source_url" "$ref" "${install_args[@]}" || return $?
    fi
    (( no_setup==0 )) || return 0
    JOBS_FLUTTER_ROUTE_MODE=dart \
        JOBS_FLUTTER_ROUTE_CAPTURE_OUTPUT=1 jobs_flutter_sdk_retry "${title}：Dart/引擎自举" "$log_file" "$sdk" "$version" "$sdk/bin/flutter" --version
}
# 升级使用同一选中网络环境检查原跟踪Git，再执行原命令；Git失败也使候选降权。
jfs_flutter_upgrade_once() {
    local log_file="$1" sdk="$2" url="$3" ref="$4" code=0
    shift 4
    jfs_fvm_timed /usr/bin/env GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 \
        "${JOBS_FLUTTER_ROUTE_GIT:-/usr/bin/git}" -c protocol.version=2 \
        ls-remote --exit-code "$url" "$ref" >/dev/null 2>&1 || code=$?
    (( code==0 )) || { jfs_route_note "$log_file" "⚠ SDK升级的原Git跟踪ref在同一网络环境中不可读（$code）；本轮未执行upgrade。"; return "$code"; }
    "$@" || return $?
    local engine_file="$sdk/bin/cache/engine.stamp"
    [[ -f "$engine_file" ]] || engine_file="$sdk/bin/internal/engine.version"
    [[ -x "$sdk/bin/cache/dart-sdk/bin/dart" && -f "$engine_file" && -f "$sdk/bin/cache/engine-dart-sdk.stamp" ]] && \
        /usr/bin/cmp -s "$engine_file" "$sdk/bin/cache/engine-dart-sdk.stamp" || {
        jfs_route_note "$log_file" '⚠ upgrade返回成功但目标SDK原生Dart/engine stamp仍未就绪，保留在SDK获取阶段。'
        return 1
    }
}
# sdk/channel都来自明确参数或真实本地SDK，不把目录名和公共stable当成用户的升级目标。
jobs_flutter_upgrade() {
    setopt LOCAL_OPTIONS
    unsetopt NOUNSET
    local title="$1" log_file="$2" sdk="$3" requested="$4" branch='' remote='' url='' ref='' target='' mode='' token=''
    shift 4
    (( $#>0 )) || return 2
    if [[ -z "$sdk" ]]; then
        for token in "$@"; do [[ "$token" == */bin/flutter ]] && sdk="${token:A:h:h}" && break; done
        [[ -n "$sdk" || ! -d "$PWD/.fvm/flutter_sdk" ]] || sdk="$PWD/.fvm/flutter_sdk"
        [[ -n "$sdk" || -z "${commands[flutter]:-}" ]] || sdk="${commands[flutter]:A:h:h}"
    fi
    [[ -d "$sdk/.git" || -f "$sdk/.git" ]] || { jfs_route_note "$log_file" '✖ 无法定位SDK原Git仓库，未猜测来源或执行升级。'; return 2; }
    # 只读当前SDK配置，忽略其它仓库遗留的Git目录环境变量。
    local -a local_git=(/usr/bin/env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_COMMON_DIR \
        "${JOBS_FLUTTER_ROUTE_GIT:-/usr/bin/git}" --no-optional-locks -c core.fsmonitor=false -C "$sdk")
    branch="$("${local_git[@]}" symbolic-ref --quiet --short HEAD 2>/dev/null)" || {
        jfs_route_note "$log_file" '✖ SDK不在可升级的跟踪分支，保留原版本；未猜测频道。'
        return 2
    }
    [[ -n "$branch" && "$branch" != *$'\n'* && "$branch" != *$'\r'* ]] || return 2
    remote="$("${local_git[@]}" config --get "branch.$branch.remote" 2>/dev/null)" || remote=origin
    [[ -n "$remote" && "$remote" != . ]] || { jfs_route_note "$log_file" '✖ SDK跟踪来源不是远端仓库，未执行网络升级。'; return 2; }
    url="$("${local_git[@]}" remote get-url "$remote" 2>/dev/null)" || return 2
    [[ -n "$url" && "$url" != *$'\n'* && "$url" != *$'\r'* ]] || return 2
    ref="$("${local_git[@]}" config --get "branch.$branch.merge" 2>/dev/null)" || ref="refs/heads/$branch"
    [[ "$ref" == refs/heads/* ]] && "${local_git[@]}" check-ref-format "$ref" >/dev/null 2>&1 || return 2
    target="${requested:-$branch}"
    case "$target" in
        stable|beta|dev)
            case "${url%/}" in
                https://github.com/flutter/flutter|https://github.com/flutter/flutter.git) mode=archive ;;
                *) mode=platform; jfs_route_note "$log_file" 'ℹ 自定义SDK跟踪源保持原样；只核验当前实际engine代表制品，不取公共channel归档冒充fork目标。' ;;
            esac
            ;;
        *)
            mode=platform
            jfs_route_note "$log_file" 'ℹ 当前为自定义/开发分支；按当前engine代表制品探测网络，不宣称验证了该分支的新版本制品，不切换到公共stable。'
            ;;
    esac
    JOBS_FLUTTER_ROUTE_MODE="$mode" jobs_flutter_sdk_retry "$title" "$log_file" "$sdk" "$target" \
        jfs_flutter_upgrade_once "$log_file" "$sdk" "$url" "$ref" "$@"
}
# 子进程CLI保留stdin，不需要eval环境，也不依赖固定仓库位置。
jfs_route_main() {
    case "${1:-}" in
        --flutter-upgrade) shift; (( $#>=5 )) || return 2; jobs_flutter_upgrade "$@" ;;
        --fvm-runtime) shift; (( $#==3 )) || return 2; jobs_flutter_fvm_runtime "$@" ;;
        --fvm-install) shift; (( $#>=4 )) || return 2; jobs_flutter_fvm_install "$@" ;;
        --cache-dir) jfs_route_cache_init || return $?; print -r -- "$JFS_ROUTE_CACHE_DIR" ;;
        --run) shift; (( $#>=5 )) || return 2; jobs_flutter_sdk_retry "$@" ;;
        --once) shift; (( $#>=5 )) || return 2; jobs_flutter_sdk_once "$@" ;;
        --) shift; (( $#>0 )) || return 2; local log_file="${JOBS_FLUTTER_ROUTE_LOG:-}"; [[ -n "$log_file" ]] || log_file="$(/usr/bin/mktemp "${TMPDIR:-/tmp/}JobsFlutterSdkRouteLog.XXXXXX")"; jobs_flutter_sdk_retry 'Flutter SDK' "$log_file" "${JOBS_FLUTTER_ROUTE_SDK_ROOT:-}" "${JOBS_FLUTTER_ROUTE_VERSION:-}" "$@" ;;
        *) print -u2 '内部SDK网络模块：--run 标题 日志 SDK根 版本 命令 参数…'; return 2 ;;
    esac
}
# JOBS_FLUTTER_ROUTE_END

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
BUILD_REPORTED_ARTIFACTS=()

# 通过明确的环境标志和父进程识别 Sourcetree，非 TTY 只影响输出能力。
is_sourcetree_runtime() {
  [[ "${JOBS_REQUIRED_TOOL_TERMINAL:-0}" == 1 ]] && return 1
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
jobs_intro_line_base() {
  local style='0;34'
  [[ "$1" == title ]] && style='1;31'
  color_log "$style" "$2"
}
# 只处理已生成的人类展示文本，保留标题/正文原样式和管道失败状态。
intro_line() {
  setopt LOCAL_OPTIONS PIPE_FAIL
  jobs_intro_line_base "$@" | jobs_url_stream
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
  intro_line body '1、用途：构建已有 Flutter 鸿蒙工程，默认一次生成 release HAP 和 APP；CLI 兼容单包目标。'
  intro_line body '2、依赖：鸿蒙适配 Flutter → Dart / 鸿蒙 SDK → Node / ohpm / Hvigor / Java。'
  intro_line body '3、影响：联网解析依赖、执行工程构建与现有签名配置，写入缓存和构建目录。'
  intro_line body '4、策略：健康工具复用；只为已选工程准备明确fork SDK或固定SDL工具链，不猜普通Flutter、不创建ohos平台、不修改证书或系统环境配置。'
  jobs_prompt_output intro_line body '5、Sourcetree 传入仓库路径后连续执行；独立终端回车继续，Ctrl+C 取消。'
  intro_line body "日志：$LOG_FILE"
  intro_line title '===================================================='
  [[ "$IS_SOURCETREE_RUNTIME" == 1 ]] && return 0
  if [[ ! -t 0 ]]; then
    error_echo '当前不是 Sourcetree 且没有交互输入，请在终端运行。'
    exit 1
  fi
  local answer=""
  IFS= read -r "answer?$(jobs_prompt_render '👉 按回车继续；非空输入取消；Ctrl+C 取消：')" || exit 1
  [[ -z "$answer" ]] || exit 0
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
  BUILD_TARGET=all
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
  [[ "${JOBS_REQUIRED_TOOL_TERMINAL:-0}" != 1 || -z "${REPO:-}" || -n "$BUILD_BASE" ]] || base="$(normalize_input_path "$REPO")"
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
  jobs_st_required_ohos_flutter
}
# 仅配置本进程的 DevEco 路径，保留显式 SDK 和 Java 设置。
# 保留现有DevEco、独立CLT和显式SDK的只读定位规则，不安装或切换来源。
jobs_ohos_locate_deveco_environment() {
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
    for candidate in /Applications/DevEco*.app/Contents(N) "$HOME"/Applications/DevEco*.app/Contents(N) "${JOBS_HARMONY_TOOLS_HOME:-$HOME/Library/Application Support/JobsHarmonySimulator}"/clt-*(N/); do
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
  if [[ -z "${DEVECO_SDK_HOME:-}" ]]; then return 3; fi
  [[ -d "$DEVECO_SDK_HOME" ]] || { error_echo "显式或已选HarmonyOS SDK目录不存在：$DEVECO_SDK_HOME；未覆盖配置。"; return 1; }
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
  jobs_flutter_sdk_retry 'Flutter / Dart首次补齐' "$LOG_FILE" "${FLUTTER_CMD[1]:A:h:h}" "" run_step 'Flutter 健康检查' "${FLUTTER_CMD[@]}" --version || return $?
  local target="" help_text=""
  for target in "${BUILD_TARGETS[@]}"; do
    if help_text="$("${FLUTTER_CMD[@]}" build "$target" --help 2>&1)"; then
      :
    else
      local capability_result=$?
      log "$help_text"
      error_echo "此SDK的flutter build $target能力探针失败（$capability_result），保留来源并停止。"
      return "$capability_result"
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
    BUILD_REPORTED_ARTIFACTS+=("$artifact")
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
  JOBS_ST_ORIGINAL_ARGS=("$@")
  JOBS_ST_ORIGINAL_CWD="$PWD"
  BUILD_REPORTED_ARTIFACTS=()
  parse_build_options "$@" || return $?
  resolve_flutter_project || return $?
  choose_flutter_sdk || return $?
  prepare_deveco_environment || return $?
  check_build_toolchain || return $?
  info_echo '依赖来源：沿用工程 pubspec.yaml / 锁文件和当前 Pub、ohpm 软件源配置。'
  JOBS_FLUTTER_ROUTE_MODE=platform jobs_flutter_sdk_retry '鸿蒙Flutter平台SDK' "$LOG_FILE" "${FLUTTER_CMD[1]:A:h:h}" "" run_step 'Flutter precache --ohos' "${FLUTTER_CMD[@]}" precache --ohos || return $?
  run_step 'flutter pub get' "${FLUTTER_CMD[@]}" pub get || return $?
  local target="" artifact=""
  for target in "${BUILD_TARGETS[@]}"; do
    run_step "flutter build $target --$BUILD_MODE" "${FLUTTER_CMD[@]}" build "$target" "--$BUILD_MODE" || return $?
    report_build_outputs "$target" || return $?
  done
  # APP 构建可能重建输出树，完成前再核对已登记的两类产物。
  for artifact in "${BUILD_REPORTED_ARTIFACTS[@]}"; do
    [[ -f "$artifact" && ! -L "$artifact" && -s "$artifact" ]] || {
      error_echo "最终产物复核失败，后续构建移除或清空了包：$artifact"
      return 1
    }
  done
  success_echo "鸿蒙构建结束（${(j: + :)BUILD_TARGETS}）；构建与签名是否满足发布要求需结合工程配置核对。日志：$LOG_FILE"
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
