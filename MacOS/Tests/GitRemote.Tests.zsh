#!/bin/zsh
# 脚本自述：
# - 核心用途：以临时 Git 仓库、假剪贴板、假浏览器和假安装器验证远程地址动作。
# - 影响范围：只写本次系统临时目录；不联网、不安装、不操作真实业务仓库或剪贴板。
# - 运行提示：请在真实终端运行；fzf 分支使用假命令验证结果和取消传播。
# shell: zsh

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
    jobs_style_applied_rows=''
    jobs_style_changed=0
    jobs_style_applied_complete=0
    jobs_style_query_active=0
    jobs_style_recovery=''
    jobs_style_exit_status=0
    jobs_style_esc=$(printf '\033')
    jobs_style_bel=$(printf '\007')
    # 只接受本次请求对应的 RGB 响应；非协议输入使本次探测失败。
    jobs_terminal_style_query() {
        jobs_style_query_key=$1
        printf '\033]%s;?\007' "$jobs_style_query_key" > /dev/tty || return 1
        jobs_style_reply=''
        for jobs_style_attempt in 1 2 3; do
            jobs_style_piece=$(dd bs=256 count=1 2>/dev/null < /dev/tty)
            jobs_style_reply=$jobs_style_reply$jobs_style_piece
            case $jobs_style_reply in
                *"$jobs_style_bel"|*"$jobs_style_esc\\") break ;;
                '') ;;
                "$jobs_style_esc"*) ;;
                *) break ;;
            esac
        done
        case $jobs_style_reply in
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_bel")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_bel"}
                ;;
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_esc\\")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_esc\\"}
                ;;
            *) return 1 ;;
        esac
        jobs_style_normalized=$(printf '%s\n' "$jobs_style_rgb" | LC_ALL=C awk -F/ '
            NF != 3 { exit 1 }
            {
                for (i = 1; i <= 3; i++) {
                    h = tolower($i)
                    if (length(h) < 1 || length(h) > 4 || h ~ /[^0-9a-f]/) exit 1
                    n = 0
                    for (j = 1; j <= length(h); j++) n = n * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
                    value[i] = int(n * 65535 / (16 ^ length(h) - 1) + 0.5)
                }
                printf "%d/%d/%d", value[1], value[2], value[3]
            }
        ') || return 1
        [ -n "$jobs_style_normalized" ]
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
    # 检测到后续改色时只恢复仍由本次保护持有的项，保留独立恢复入口。
    jobs_terminal_style_cleanup() {
        jobs_style_result=$1
        trap '' HUP INT TERM
        if [ "$jobs_style_query_active" = 1 ]; then
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || :
            jobs_style_query_active=0
        fi
        if [ "$jobs_style_changed" = 1 ]; then
            jobs_style_cleanup_ok=0
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            if [ "$jobs_style_applied_complete" = 1 ]; then
                jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
                if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
                    jobs_style_query_active=1
                    jobs_style_cleanup_ok=1
                    while IFS='|' read -r jobs_style_key jobs_style_expected jobs_style_original; do
                        [ -n "$jobs_style_key" ] || continue
                        if ! jobs_terminal_style_query "$jobs_style_key"; then
                            jobs_style_cleanup_ok=0
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
                    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || jobs_style_cleanup_ok=0
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
                printf '终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_recovery" >&2
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
    trap 'jobs_style_exit_status=129; exit 129' HUP
    trap 'jobs_style_exit_status=130; exit 130' INT
    trap 'jobs_style_exit_status=143; exit 143' TERM
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
    while IFS='|' read -r jobs_style_key jobs_style_original; do
        [ -n "$jobs_style_key" ] || continue
        if ! jobs_terminal_style_query "$jobs_style_key"; then
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
        printf '%s\n' '无法核实本次临时配色，已停止启动业务。' >&2
        jobs_style_exit_status=1
        exit 1
    fi
    jobs_style_applied_complete=1
    if [ "$jobs_style_targets_ok" != 1 ]; then
        jobs_terminal_style_cleanup 0 continue
        jobs_style_changed=0
        if [ "$jobs_style_cleanup_status" != 0 ]; then
            jobs_style_exit_status=1
            exit 1
        fi
        trap 'jobs_style_exit_status=129; exit 129' HUP
        trap 'jobs_style_exit_status=130; exit 130' INT
        trap 'jobs_style_exit_status=143; exit 143' TERM
        printf '%s\n' '终端未接受本次配色，已恢复原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
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

TEST_SOURCE_PATH="${0:A}"
TEST_ROOT=""
TEST_REPOSITORY=""
TEST_SUBJECT=""
TEST_LIBRARY=""
TEST_PATH_ROOT=""
TEST_PATH_SUBJECT=""
TEST_PATH_TRACE=""
TEST_PATH_EXPECT_MODE=""
TEST_PASSED=0
TEST_FAILED=0
# 清理本次专用临时目录，不触碰仓库或用户数据。
cleanup_test_workspace() {
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]]; then
    /usr/bin/find "$TEST_ROOT" -type f -exec /bin/chmod u+w {} +
    /bin/rm -r -- "$TEST_ROOT"
  fi
  return 0
}
# 打印测试说明并阻止非终端把选择器测试误报为通过。
show_test_intro() {
  print -r -- 'Git 远程地址隔离回归：只操作临时仓库，浏览器 / 剪贴板 / 安装均替身执行。'
  [[ -t 0 && -t 1 ]] || { print -u2 -r -- '请在真实终端运行本测试，以覆盖选择器的 TTY 门禁。'; exit 2; }
}
# 初始化隔离环境并提取函数定义，去掉生产脚本唯一的 main 调用。
prepare_test_workspace() {
  emulate -R zsh
  setopt NO_NOMATCH PIPE_FAIL
  TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-git-remote-tests.XXXXXX")" || exit 1
  TEST_SUBJECT="${TEST_SOURCE_PATH:h:h}/【MacOS@SourceTree】🌐获取远程仓库地址.command/【MacOS@SourceTree】🌐获取远程仓库地址.command"
  TEST_LIBRARY="$TEST_ROOT/remote-functions.zsh"
  /usr/bin/sed '$d' "$TEST_SUBJECT" > "$TEST_LIBRARY" || exit 1
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_NAMESPACE
  /bin/mkdir -p "$TEST_ROOT/bin"
  cat > "$TEST_ROOT/bin/fzf" <<'FZF'
#!/bin/zsh
[[ "$1" != --version ]] || { print -r -- '0.60.0'; exit 0; }
[[ -z "${FZF_DEFAULT_OPTS:-}${FZF_DEFAULT_OPTS_FILE:-}${FZF_DEFAULT_COMMAND:-}" ]] || exit 42
typeset -a rows=()
while IFS= read -r row; do rows+=("$row"); done
[[ -z "${TEST_FZF_INPUT:-}" ]] || print -rl -- "${rows[@]}" > "$TEST_FZF_INPUT"
case "${TEST_FZF_MODE:-second}" in
  cancel) exit 130 ;;
  nomatch) exit 1 ;;
  fail) exit 2 ;;
  empty) exit 0 ;;
  forged) print -r -- $'1\t伪造结果'; exit 0 ;;
  *) print -r -- "${rows[2]}" ;;
esac
FZF
  cat > "$TEST_ROOT/bin/pbcopy" <<'CLIPBOARD'
#!/bin/zsh
/bin/cat > "$TEST_CLIPBOARD"
exit "${TEST_CLIPBOARD_RC:-0}"
CLIPBOARD
  cat > "$TEST_ROOT/bin/brew" <<'BREW'
#!/bin/zsh
print -r -- "$*" >> "$TEST_BREW_TRACE"
case "$1" in
  list) exit 1 ;;
  install|reinstall) [[ "${TEST_BREW_RC:-0}" == 0 ]] || exit "$TEST_BREW_RC"; /usr/bin/touch "$TEST_FZF_READY" ;;
esac
BREW
  /bin/chmod +x "$TEST_ROOT/bin/fzf" "$TEST_ROOT/bin/pbcopy" "$TEST_ROOT/bin/brew"
}
# 每个用例使用独立子进程，生产函数的 exit 不影响后续用例。
run_case() {
  local title="$1" callback="$2"
  if ( "$callback" ); then
    TEST_PASSED=$((TEST_PASSED + 1))
    print -r -- "PASS  $title"
  else
    TEST_FAILED=$((TEST_FAILED + 1))
    print -r -- "FAIL  $title"
  fi
}
# 核对实际值，失败时给出便于排查的差异。
assert_equal() {
  [[ "$1" == "$2" ]] || { print -u2 -r -- "期望：$2；实际：$1"; return 1; }
}
# 为每例创建独立临时仓库并重置生产状态。
new_repository() {
  TEST_REPOSITORY="$(/usr/bin/mktemp -d "$TEST_ROOT/仓库 空格.XXXXXX")" || return 1
  git init -q "$TEST_REPOSITORY" || return 1
  REPOSITORY_ROOT="$TEST_REPOSITORY"
  REQUESTED_REMOTE=""
  REMOTE_URLS=()
  REMOTE_LABELS=()
  PLAIN_OUTPUT=1
  LOG_READY=0
  IS_SOURCETREE_RUNTIME=0
}
# 无远程必须失败，不能生成默认目标。
case_no_remote() {
  new_repository || return 1
  (collect_remote_candidates)
  (( $? != 0 ))
}
# 同一 fetch / push 地址去重后直接选择，不调用依赖安装。
case_single_remote() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" remote add origin 'git@example.com:group/repo.git' || return 1
  collect_remote_candidates
  ensure_fzf_dependency() { return 99; }
  select_remote_candidate || return 1
  assert_equal "${#REMOTE_URLS}" 1 && assert_equal "$REMOTE_URL" 'git@example.com:group/repo.git'
}
# origin 不享有默认优先权，多个不同远程都进入候选。
case_multiple_remotes() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" remote add origin 'https://github.example/group/repo.git'
  git -C "$TEST_REPOSITORY" remote add gitee 'https://gitee.example/group/repo.git'
  collect_remote_candidates
  assert_equal "${#REMOTE_URLS}" 2 && [[ "${(j:|:)REMOTE_URLS}" == *github.example* && "${(j:|:)REMOTE_URLS}" == *gitee.example* ]]
}
# 单个 remote 的多个 fetch 和专属 push 地址不能遗漏。
case_multiple_urls() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" remote add origin 'https://a.example/g/r.git'
  git -C "$TEST_REPOSITORY" config --add remote.origin.url 'https://b.example/g/r.git'
  git -C "$TEST_REPOSITORY" config --add remote.origin.pushurl 'ssh://git@c.example/g/r.git'
  collect_remote_candidates
  assert_equal "${#REMOTE_URLS}" 3 && assert_equal "${REMOTE_URLS[3]}" 'ssh://git@c.example/g/r.git'
}
# 不同 remote 的完全相同 URL 只保留一个，并保留两个来源标签。
case_deduplicate_urls() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" remote add origin 'https://same.example/g/r.git'
  git -C "$TEST_REPOSITORY" remote add mirror 'https://same.example/g/r.git'
  collect_remote_candidates
  assert_equal "${#REMOTE_URLS}" 1 && [[ "${REMOTE_LABELS[1]}" == *origin/fetch* && "${REMOTE_LABELS[1]}" == *mirror/fetch* ]]
}
# 显式 remote 限定范围，错误名称必须停止。
case_explicit_remote() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" remote add origin 'https://a.example/g/r.git'
  git -C "$TEST_REPOSITORY" remote add mirror 'https://b.example/g/r.git'
  parse_remote_arguments "$TEST_REPOSITORY" mirror
  collect_remote_candidates
  assert_equal "${REMOTE_URLS[1]}" 'https://b.example/g/r.git' || return 1
  REQUESTED_REMOTE=missing
  (collect_remote_candidates)
  (( $? != 0 ))
}
# Git 自己展开 insteadOf，不按字符串猜测生效 URL。
case_instead_of() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" config url.https://expanded.example/group/.insteadOf short:
  git -C "$TEST_REPOSITORY" remote add origin short:repo.git
  collect_remote_candidates
  assert_equal "${REMOTE_URLS[1]}" 'https://expanded.example/group/repo.git'
}
# 子目录、文件及嵌套仓库均识别最近工作树。
case_repository_paths() {
  new_repository || return 1
  /bin/mkdir -p "$TEST_REPOSITORY/子目录 深层/内部仓库"
  /usr/bin/touch "$TEST_REPOSITORY/子目录 深层/文件.txt"
  resolve_repository_root "$TEST_REPOSITORY/子目录 深层/文件.txt"
  assert_equal "$REPOSITORY_ROOT" "${TEST_REPOSITORY:A}" || return 1
  git init -q "$TEST_REPOSITORY/子目录 深层/内部仓库"
  resolve_repository_root "$TEST_REPOSITORY/子目录 深层/内部仓库"
  assert_equal "$REPOSITORY_ROOT" "${TEST_REPOSITORY:A}/子目录 深层/内部仓库"
}
# .git 指针文件形式的 worktree 仍然能定位其独立工作树。
case_worktree() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm fixture || return 1
  git -C "$TEST_REPOSITORY" worktree add -qb fixture-worktree "$TEST_REPOSITORY/工作树" || return 1
  [[ -f "$TEST_REPOSITORY/工作树/.git" ]] || return 1
  resolve_repository_root "$TEST_REPOSITORY/工作树"
  assert_equal "$REPOSITORY_ROOT" "${TEST_REPOSITORY:A}/工作树"
}
# 运行态初始化只清理当前进程 Git 定位变量，避免 Sourcetree 环境污染目标仓。
case_git_environment() {
  export GIT_DIR=/invalid/git GIT_WORK_TREE=/invalid/tree GIT_INDEX_FILE=/invalid/index GIT_COMMON_DIR=/invalid/common
  resolve_script_path() { print -r -- "$TEST_SUBJECT"; }
  is_sourcetree_runtime() { return 0; }
  LOG_DIR="$TEST_ROOT"
  initialize_script_runtime
  [[ -z "${GIT_DIR+x}${GIT_WORK_TREE+x}${GIT_INDEX_FILE+x}${GIT_COMMON_DIR+x}" ]]
}
# 菜单、终端和日志完整显示原始地址，保留 git@、用户信息、查询参数及片段。
case_full_display() {
  new_repository || return 1
  REMOTE_URLS=('git@example.com:g/r.git' 'https://name:secret@example.com/g/r.git?token=visible#fragment')
  REMOTE_LABELS=('origin/fetch，origin/push' 'mirror/fetch')
  export TEST_FZF_INPUT="$TEST_ROOT/full-display-menu" TEST_FZF_MODE=second
  export TEST_CLIPBOARD="$TEST_ROOT/full-display-clipboard" TEST_CLIPBOARD_RC=0 PATH="$TEST_ROOT/bin:$PATH"
  ensure_fzf_dependency() { FZF_BIN="$TEST_ROOT/bin/fzf"; }
  select_remote_candidate || return 1
  assert_equal "$REMOTE_URL" "${REMOTE_URLS[2]}" || return 1
  assert_equal "$(/bin/cat "$TEST_FZF_INPUT")" $'1\t'"${REMOTE_LABELS[1]}  ${REMOTE_URLS[1]}"$'\n2\t'"${REMOTE_LABELS[2]}  ${REMOTE_URLS[2]}" || return 1

  local index=0 output="$TEST_ROOT/full-display-output"
  REMOTE_ACTION=copy
  LOG_FILE="$TEST_ROOT/full-display.log"
  LOG_READY=1
  : > "$LOG_FILE"
  for (( index=1; index<=${#REMOTE_URLS[@]}; index++ )); do
    REMOTE_URL="${REMOTE_URLS[$index]}"
    REMOTE_NAME="${REMOTE_LABELS[$index]}"
    perform_remote_action > "$output" || return 1
    print_remote_summary >> "$output" || return 1
    assert_equal "$REMOTE_URL_DISPLAY" "$REMOTE_URL" || return 1
    assert_equal "$(/bin/cat "$TEST_CLIPBOARD")" "$REMOTE_URL" || return 1
    /usr/bin/grep -Fq -- "远程仓库地址：${REMOTE_URL}" "$output" || return 1
    /usr/bin/grep -Fq -- "远程来源：${REMOTE_NAME}" "$output" || return 1
    /usr/bin/grep -Fq -- "远程仓库地址：${REMOTE_URL}" "$LOG_FILE" || return 1
  done
  (add_remote_candidate origin fetch $'git@example.com:g/r.git\033[31m')
  (( $? != 0 ))
}
# 多类网络克隆 URL 转换时保留明确的 HTTP 端口并去掉 .git。
case_web_urls() {
  assert_equal "$(remote_url_to_web_url 'git@example.com:group/sub/repo.git')" 'https://example.com/group/sub/repo' || return 1
  assert_equal "$(remote_url_to_web_url 'ssh://git@example.com:22/group/repo.git')" 'https://example.com/group/repo' || return 1
  assert_equal "$(remote_url_to_web_url 'https://u:secret@example.com:8443/group/repo.git?token=secret')" 'https://example.com:8443/group/repo' || return 1
  assert_equal "$(remote_url_to_web_url 'http://example.com/group/repo.git/')" 'http://example.com/group/repo' || return 1
  assert_equal "$(remote_url_to_web_url 'git://example.com/group/repo.git')" 'https://example.com/group/repo'
}
# 本地路径、控制字符、危险协议和不能确定网页端口的 SSH 地址不得打开。
case_rejected_web_urls() {
  local input=""
  for input in '/tmp/repo.git' '../repo' 'C:\repo.git' 'file:///tmp/repo.git' 'javascript://example.com/alert(1)' 'ssh://git@example.com:2222/group/repo.git' 'https://example.com/../repo.git' $'https://example.com/g/\nrepo'; do
    if remote_url_to_web_url "$input" >/dev/null; then
      print -u2 -r -- "错误接受地址：$input"
      return 1
    fi
  done
}
# 剪贴板替身必须收到原始 URL；失败状态不能伪报成功。
case_copy_action() {
  export TEST_CLIPBOARD="$TEST_ROOT/clipboard" TEST_CLIPBOARD_RC=0
  export PATH="$TEST_ROOT/bin:$PATH"
  REMOTE_ACTION=copy
  REMOTE_URL='https://u:secret@example.com/g/r.git?token=secret'
  perform_remote_action
  assert_equal "$(/bin/cat "$TEST_CLIPBOARD")" "$REMOTE_URL" || return 1
  export TEST_CLIPBOARD_RC=7
  (perform_remote_action)
  (( $? != 0 ))
}
# 浏览器替身仅收到转换后的 HTTPS 地址，不启动真实应用。
case_open_action() {
  REMOTE_ACTION=open
  REMOTE_URL='git@example.com:group/repo.git'
  open_remote_web_url() { print -rn -- "$1" > "$TEST_ROOT/browser"; }
  perform_remote_action
  assert_equal "$(/bin/cat "$TEST_ROOT/browser")" 'https://example.com/group/repo'
}
# 假选择器选择第二条并校验隐藏 ID 映射和默认参数清理。
case_fzf_selection() {
  REMOTE_URLS=('https://a.example/g/r.git?token=one' 'https://b.example/g/r.git?token=two')
  REMOTE_LABELS=('origin/fetch' 'mirror/fetch')
  export FZF_DEFAULT_OPTS='--bind enter:execute(touch unsafe)' FZF_DEFAULT_OPTS_FILE=/invalid FZF_DEFAULT_COMMAND=unsafe TEST_FZF_MODE=second
  ensure_fzf_dependency() { FZF_BIN="$TEST_ROOT/bin/fzf"; }
  select_remote_candidate
  assert_equal "$REMOTE_URL" "${REMOTE_URLS[2]}"
}
# Esc、无匹配及空输出均以成功取消结束，后续业务标记保持不存在。
case_fzf_cancellation() {
  REMOTE_URLS=('https://a.example/r.git' 'https://b.example/r.git')
  REMOTE_LABELS=('a/fetch' 'b/fetch')
  ensure_fzf_dependency() { FZF_BIN="$TEST_ROOT/bin/fzf"; }
  local mode=""
  for mode in cancel nomatch empty; do
    export TEST_FZF_MODE="$mode"
    (select_remote_candidate; /usr/bin/touch "$TEST_ROOT/cancel-business")
    [[ $? == 0 && ! -e "$TEST_ROOT/cancel-business" ]] || return 1
  done
}
# 选择器失败和伪造结果必须以失败结束，不能复制或打开。
case_fzf_failure() {
  REMOTE_URLS=('https://a.example/r.git' 'https://b.example/r.git')
  REMOTE_LABELS=('a/fetch' 'b/fetch')
  ensure_fzf_dependency() { FZF_BIN="$TEST_ROOT/bin/fzf"; }
  local mode=""
  for mode in fail forged; do
    export TEST_FZF_MODE="$mode"
    (select_remote_candidate)
    (( $? != 0 )) || return 1
  done
}
# 对本机现有 fzf 进行无交互选项健康探针，不修改安装。
case_real_fzf_health() {
  local candidate="$(command -v fzf)"
  [[ -n "$candidate" ]] || { print -r -- 'SKIP  本机未安装 fzf，跳过真实二进制健康探针。'; return 0; }
  fzf_candidate_ok "$candidate"
}
# 全链健康时不触发 Homebrew 或安装分支。
case_dependency_healthy() {
  find_healthy_fzf() { return 0; }
  jobs_brew_install_or_exit() { return 91; }
  ensure_fzf_dependency
}
# 假安装器与状态文件覆盖 fzf 缺失、安装失败和安装后复检失败。
case_dependency_repair() {
  export TEST_BREW_TRACE="$TEST_ROOT/brew.trace" TEST_FZF_READY="$TEST_ROOT/fzf-ready" TEST_BREW_RC=0
  find_healthy_fzf() { [[ -e "$TEST_FZF_READY" ]]; }
  jobs_brew_install_or_exit() { JOBS_HOMEBREW_BIN="$TEST_ROOT/bin/brew"; JOBS_HOMEBREW_PREFIX="$TEST_ROOT"; }
  ensure_fzf_dependency <<< '' || return 1
  [[ -e "$TEST_FZF_READY" ]] && [[ "$(/bin/cat "$TEST_BREW_TRACE")" == *'install fzf'* ]]
}
# 安装失败必须停止，不能继续到成功业务。
case_dependency_install_failure() {
  export TEST_BREW_TRACE="$TEST_ROOT/brew-failed.trace" TEST_FZF_READY="$TEST_ROOT/fzf-failed" TEST_BREW_RC=8
  find_healthy_fzf() { return 1; }
  jobs_brew_install_or_exit() { JOBS_HOMEBREW_BIN="$TEST_ROOT/bin/brew"; JOBS_HOMEBREW_PREFIX="$TEST_ROOT"; }
  (ensure_fzf_dependency <<< '')
  (( $? != 0 )) && [[ ! -e "$TEST_FZF_READY" ]]
}
# 安装返回成功但 fzf 仍不健康时必须失败。
case_dependency_recheck_failure() {
  export TEST_BREW_TRACE="$TEST_ROOT/brew-recheck.trace" TEST_FZF_READY="$TEST_ROOT/fzf-recheck" TEST_BREW_RC=0
  find_healthy_fzf() { return 1; }
  jobs_brew_install_or_exit() { JOBS_HOMEBREW_BIN="$TEST_ROOT/bin/brew"; JOBS_HOMEBREW_PREFIX="$TEST_ROOT"; }
  (ensure_fzf_dependency <<< '')
  (( $? != 0 ))
}
# 多层缺失只走选定的安装来源，安装与激活各调用一次。
case_brew_missing_chain() {
  local trace="$TEST_ROOT/brew-chain.trace"
  jobs_brew_find() { return 1; }
  jobs_brew_choose_installation() { JOBS_HOMEBREW_INSTALL_MODE=user; print -r -- choose >> "$trace"; }
  jobs_brew_install_user() { print -r -- install >> "$trace"; }
  jobs_brew_activate() { print -r -- "activate:$1" >> "$trace"; }
  jobs_brew_install_or_exit
  assert_equal "$(/bin/cat "$trace")" $'choose\ninstall\nactivate:installed'
}
# 已有 Homebrew 只激活并复检，不安装或修改 Shell 配置。
case_brew_healthy_chain() {
  local trace="$TEST_ROOT/brew-healthy.trace"
  jobs_brew_find() { print -r -- "$TEST_ROOT/bin/brew"; }
  jobs_brew_choose_installation() { return 88; }
  jobs_brew_activate() { print -r -- "activate:$1" >> "$trace"; }
  jobs_brew_install_or_exit
  assert_equal "$(/bin/cat "$trace")" 'activate:'
}
# 完整获取入口从参数解析到剪贴板执行，Sourcetree 单地址不打开终端。
case_copy_entry_flow() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" remote add origin 'https://example.com/g/r.git'
  export SOURCETREE_TEST_CONTEXT=1 TEST_CLIPBOARD="$TEST_ROOT/full-clipboard" TEST_CLIPBOARD_RC=0
  export PATH="$TEST_ROOT/bin:$PATH"
  LOG_DIR="$TEST_ROOT"
  resolve_script_path() { print -r -- "$TEST_SUBJECT"; }
  ensure_fzf_dependency() { return 99; }
  open_terminal_for_selection() { return 98; }
  main "$TEST_REPOSITORY" || return 1
  assert_equal "$(/bin/cat "$TEST_CLIPBOARD")" 'https://example.com/g/r.git'
}
# 文件名决定打开模式，完整入口仍共用同一候选逻辑。
case_open_entry_flow() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" remote add origin 'git@example.com:group/repo.git'
  export SOURCETREE_TEST_CONTEXT=1
  LOG_DIR="$TEST_ROOT"
  resolve_script_path() { print -r -- "${TEST_SUBJECT:h:h}/【MacOS@SourceTree】🌍打开远程仓库地址.command/【MacOS@SourceTree】🌍打开远程仓库地址.command"; }
  open_remote_web_url() { print -rn -- "$1" > "$TEST_ROOT/full-browser"; }
  main "$TEST_REPOSITORY" || return 1
  assert_equal "$(/bin/cat "$TEST_ROOT/full-browser")" 'https://example.com/group/repo'
}
# Sourcetree 多地址只转交终端，后台不运行选择器或复制。
case_terminal_handoff_flow() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" remote add origin 'https://a.example/g/r.git'
  git -C "$TEST_REPOSITORY" remote add mirror 'https://b.example/g/r.git'
  export SOURCETREE_TEST_CONTEXT=1
  LOG_DIR="$TEST_ROOT"
  resolve_script_path() { print -r -- "$TEST_SUBJECT"; }
  open_terminal_for_selection() { print -rn -- "$REPOSITORY_ROOT" > "$TEST_ROOT/handoff"; exit 0; }
  (main "$TEST_REPOSITORY"; /usr/bin/touch "$TEST_ROOT/handoff-business")
  [[ $? == 0 && ! -e "$TEST_ROOT/handoff-business" ]] || return 1
  assert_equal "$(/bin/cat "$TEST_ROOT/handoff")" "${TEST_REPOSITORY:A}"
}
# 复制完整入口到改名目录，只替换 Terminal 外部命令，保留文件作用域和真实寻址。
create_path_fixture() {
  local kind="$1" name="" subject=""
  case "$kind" in
    copy) name='【MacOS@SourceTree】🌐获取远程仓库地址.command' ;;
    open) name='【MacOS@SourceTree】🌍打开远程仓库地址.command' ;;
    *) return 1 ;;
  esac
  TEST_PATH_ROOT="$(/usr/bin/mktemp -d "$TEST_ROOT/入口寻址.XXXXXX")" || return 1
  TEST_PATH_SUBJECT="$TEST_PATH_ROOT/搬迁后 中文 '空格/$name"
  TEST_PATH_TRACE="$TEST_PATH_ROOT/trace"
  TEST_PATH_EXPECT_MODE="$kind"
  subject="${TEST_SOURCE_PATH:h:h}/$name/$name"
  /bin/mkdir -p "${TEST_PATH_SUBJECT:h}" "$TEST_PATH_ROOT/无关工作目录" "$TEST_PATH_ROOT/logs" "$TEST_PATH_ROOT/home" || return 1
  /usr/bin/grep -Fq '/usr/bin/osascript - "$SCRIPT_PATH"' "$subject" || return 1
  /usr/bin/sed -e '$d' -e 's@/usr/bin/osascript -@test_terminal_command -@' "$subject" > "$TEST_PATH_SUBJECT" || return 1
  if /usr/bin/grep -Fq '/usr/bin/osascript' "$TEST_PATH_SUBJECT"; then
    print -u2 -r -- 'Terminal 命令替身未覆盖生产入口，停止夹具执行。'
    return 1
  fi
  cat >> "$TEST_PATH_SUBJECT" <<'FIXTURE'
# 拦截外部 Terminal 命令，保留生产函数的参数和失败处理。
test_terminal_command() {
  print -rl -- "$@" > "$TEST_PATH_TRACE.terminal"
  /bin/cat > "$TEST_PATH_TRACE.applescript"
  return "${TEST_TERMINAL_RC:-0}"
}
# 捕获网页目标，不启动真实浏览器。
open_remote_web_url() {
  print -r -- "$1" > "$TEST_PATH_TRACE.browser"
}
# 寻址与终端承接场景不应进入选择器依赖安装。
ensure_fzf_dependency() {
  print -r -- unexpected > "$TEST_PATH_TRACE.dependency"
  return 97
}
# 记录真实解析的脚本身份和入口模式。
record_path_fixture_identity() {
  print -r -- "$SCRIPT_PATH" > "$TEST_PATH_TRACE.path"
  print -r -- "$SCRIPT_DIR" > "$TEST_PATH_TRACE.dir"
  print -r -- "$SCRIPT_BASENAME" > "$TEST_PATH_TRACE.basename"
  print -r -- "$REMOTE_ACTION" > "$TEST_PATH_TRACE.mode"
}
# 在新 zsh 进程保留函数内 $0 语义，分别核对解析、业务和不存在的转交文件。
run_path_fixture() {
  setopt FUNCTION_ARGZERO
  LOG_DIR="$TEST_PATH_ROOT/logs"
  case "${TEST_PATH_MODE:-inspect}" in
    inspect)
      prepare_intro_output
      record_path_fixture_identity
      ;;
    single)
      main "$@"
      record_path_fixture_identity
      ;;
    handoff)
      main "$@"
      print -r -- unexpected > "$TEST_PATH_TRACE.after-handoff"
      ;;
    missing-handoff)
      prepare_intro_output
      SCRIPT_PATH="$TEST_PATH_ROOT/不存在.command"
      open_terminal_for_selection
      print -r -- unexpected > "$TEST_PATH_TRACE.after-handoff"
      ;;
  esac
}
run_path_fixture "$@"
FIXTURE
}
# 核对文件来源、目录、日志基名与复制 / 打开模式，不接受函数名充当脚本名。
assert_path_fixture_identity() {
  assert_equal "$(/bin/cat "$TEST_PATH_TRACE.path")" "${TEST_PATH_SUBJECT:A}" || return 1
  assert_equal "$(/bin/cat "$TEST_PATH_TRACE.dir")" "${TEST_PATH_SUBJECT:A:h}" || return 1
  assert_equal "$(/bin/cat "$TEST_PATH_TRACE.basename")" "${TEST_PATH_SUBJECT:t:r}" || return 1
  assert_equal "$(/bin/cat "$TEST_PATH_TRACE.mode")" "$TEST_PATH_EXPECT_MODE"
}
# 两个入口在中文空格改名目录和无关工作目录下仍识别自己的完整路径。
case_real_source_paths() {
  local kind=""
  for kind in copy open; do
    create_path_fixture "$kind" || return 1
    (cd "$TEST_PATH_ROOT/无关工作目录" && /usr/bin/env SOURCETREE_TEST_CONTEXT=1 TEST_PATH_ROOT="$TEST_PATH_ROOT" TEST_PATH_TRACE="$TEST_PATH_TRACE" /bin/zsh "$TEST_PATH_SUBJECT") || return 1
    assert_path_fixture_identity || return 1
  done
}
# 相对路径与只有文件名的执行方式均使用真实脚本文件，不依赖函数内 $0。
case_relative_source_paths() {
  local kind=""
  for kind in copy open; do
    create_path_fixture "$kind" || return 1
    (cd "$TEST_PATH_ROOT" && /usr/bin/env SOURCETREE_TEST_CONTEXT=1 TEST_PATH_ROOT="$TEST_PATH_ROOT" TEST_PATH_TRACE="$TEST_PATH_TRACE" /bin/zsh "${TEST_PATH_SUBJECT#$TEST_PATH_ROOT/}") || return 1
    assert_path_fixture_identity || return 1
    (cd "${TEST_PATH_SUBJECT:h}" && /usr/bin/env SOURCETREE_TEST_CONTEXT=1 TEST_PATH_ROOT="$TEST_PATH_ROOT" TEST_PATH_TRACE="$TEST_PATH_TRACE" /bin/zsh "${TEST_PATH_SUBJECT:t}") || return 1
    assert_path_fixture_identity || return 1
  done
}
# zsh -c 文本启动用文件层 $0 找回假 HOME 的运行副本，并忽略仓库内同名 zsh 干扰。
case_command_text_fallback() {
  local kind="" command_text="" name="" fallback=""
  for kind in copy open; do
    create_path_fixture "$kind" || return 1
    new_repository || return 1
    name="${TEST_PATH_SUBJECT:t}"
    command_text="$(/bin/cat "$TEST_PATH_SUBJECT")"
    fallback="$TEST_PATH_ROOT/home/SourceTree.command/MacOS/$name/$name"
    /bin/mkdir -p "${fallback:h}" || return 1
    /bin/cp "$TEST_PATH_SUBJECT" "$fallback" || return 1
    print -r -- decoy > "$TEST_REPOSITORY/zsh"
    TEST_PATH_SUBJECT="$fallback"
    (cd "$TEST_REPOSITORY" && /usr/bin/env HOME="$TEST_PATH_ROOT/home" SOURCETREE_TEST_CONTEXT=1 TEST_PATH_ROOT="$TEST_PATH_ROOT" TEST_PATH_TRACE="$TEST_PATH_TRACE" /bin/zsh -c "$command_text" "$name") || return 1
    assert_path_fixture_identity || return 1
  done
}
# 真正文件入口从仓库参数走到复制或网页目标，路径解析和入口模式均不替身。
case_real_single_entry_modes() {
  local kind=""
  for kind in copy open; do
    create_path_fixture "$kind" || return 1
    new_repository || return 1
    git -C "$TEST_REPOSITORY" remote add origin 'git@example.com:group/repo.git' || return 1
    (cd "$TEST_PATH_ROOT/无关工作目录" && /usr/bin/env PATH="$TEST_ROOT/bin:$PATH" SOURCETREE_TEST_CONTEXT=1 TEST_PATH_ROOT="$TEST_PATH_ROOT" TEST_PATH_TRACE="$TEST_PATH_TRACE" TEST_PATH_MODE=single TEST_CLIPBOARD="$TEST_PATH_TRACE.clipboard" TEST_CLIPBOARD_RC=0 /bin/zsh "$TEST_PATH_SUBJECT" "$TEST_REPOSITORY" > "$TEST_PATH_TRACE.output" 2>&1) || return 1
    assert_path_fixture_identity || return 1
    [[ ! -e "$TEST_PATH_TRACE.terminal" && ! -e "$TEST_PATH_TRACE.dependency" ]] || return 1
    if [[ "$kind" == copy ]]; then
      assert_equal "$(/bin/cat "$TEST_PATH_TRACE.clipboard")" 'git@example.com:group/repo.git' || return 1
      [[ ! -e "$TEST_PATH_TRACE.browser" ]] || return 1
    else
      assert_equal "$(/bin/cat "$TEST_PATH_TRACE.browser")" 'https://example.com/group/repo' || return 1
      [[ ! -e "$TEST_PATH_TRACE.clipboard" ]] || return 1
    fi
  done
}
# 多地址转交捕获生产 Terminal 调用的脚本、仓库和远程参数，不启动真实应用。
case_real_terminal_arguments() {
  local kind=""
  for kind in copy open; do
    create_path_fixture "$kind" || return 1
    new_repository || return 1
    git -C "$TEST_REPOSITORY" remote add origin 'https://a.example/g/r.git' || return 1
    git -C "$TEST_REPOSITORY" config --add remote.origin.url 'https://b.example/g/r.git' || return 1
    (cd "$TEST_PATH_ROOT/无关工作目录" && /usr/bin/env SOURCETREE_TEST_CONTEXT=1 TEST_PATH_ROOT="$TEST_PATH_ROOT" TEST_PATH_TRACE="$TEST_PATH_TRACE" TEST_PATH_MODE=handoff /bin/zsh "$TEST_PATH_SUBJECT" "$TEST_REPOSITORY" origin > "$TEST_PATH_TRACE.output" 2>&1) || return 1
    assert_equal "$(/bin/cat "$TEST_PATH_TRACE.terminal")" "-"$'\n'"${TEST_PATH_SUBJECT:A}"$'\n'"${TEST_REPOSITORY:A}"$'\norigin' || return 1
    [[ ! -e "$TEST_PATH_TRACE.after-handoff" && ! -e "$TEST_PATH_TRACE.dependency" && ! -e "$TEST_PATH_TRACE.browser" ]] || return 1
  done
}
# 找不到任何脚本副本时必须失败，不能把仓库内虚构路径交给 Terminal。
case_missing_command_text_path() {
  local kind="" command_text="" result=0
  for kind in copy open; do
    create_path_fixture "$kind" || return 1
    new_repository || return 1
    command_text="$(/bin/cat "$TEST_PATH_SUBJECT")"
    (cd "$TEST_REPOSITORY" && /usr/bin/env HOME="$TEST_PATH_ROOT/home" SOURCETREE_TEST_CONTEXT=1 TEST_PATH_ROOT="$TEST_PATH_ROOT" TEST_PATH_TRACE="$TEST_PATH_TRACE" TEST_PATH_MODE=handoff /bin/zsh -c "$command_text" "${TEST_PATH_SUBJECT:t}" "$TEST_REPOSITORY" > "$TEST_PATH_TRACE.output" 2>&1)
    result=$?
    (( result != 0 )) || return 1
    [[ ! -e "$TEST_PATH_TRACE.terminal" && ! -e "$TEST_PATH_TRACE.after-handoff" ]] || return 1
    [[ "$(/bin/cat "$TEST_PATH_TRACE.output")" == *无法定位真实脚本* ]] || return 1
  done
}
# 解析后文件再缺失时也必须在 Terminal 外部调用前停止。
case_missing_handoff_file() {
  local kind="" result=0
  for kind in copy open; do
    create_path_fixture "$kind" || return 1
    (cd "$TEST_PATH_ROOT/无关工作目录" && /usr/bin/env SOURCETREE_TEST_CONTEXT=1 TEST_PATH_ROOT="$TEST_PATH_ROOT" TEST_PATH_TRACE="$TEST_PATH_TRACE" TEST_PATH_MODE=missing-handoff /bin/zsh "$TEST_PATH_SUBJECT" > "$TEST_PATH_TRACE.output" 2>&1)
    result=$?
    (( result != 0 )) || return 1
    [[ ! -e "$TEST_PATH_TRACE.terminal" && ! -e "$TEST_PATH_TRACE.after-handoff" ]] || return 1
  done
}
# 顺序运行所有隔离场景，并以失败数量决定最终状态。
run_regressions() {
  run_case '无远程停止' case_no_remote
  run_case '唯一地址直接选择' case_single_remote
  run_case '多个远程完整枚举' case_multiple_remotes
  run_case '单远程多 fetch / push URL' case_multiple_urls
  run_case '跨远程 URL 去重与来源保留' case_deduplicate_urls
  run_case '显式 remote 与错误名称' case_explicit_remote
  run_case 'insteadOf 生效地址' case_instead_of
  run_case '中文空格文件和最近嵌套仓库' case_repository_paths
  run_case '.git 文件 worktree' case_worktree
  run_case 'Git 定位变量隔离' case_git_environment
  run_case '菜单终端日志完整原始地址' case_full_display
  run_case '网络 URL 网页转换' case_web_urls
  run_case '不安全和不明确地址拒绝' case_rejected_web_urls
  run_case '原始 URL 剪贴板与失败传播' case_copy_action
  run_case '浏览器转换目标' case_open_action
  run_case 'fzf 第二行映射及默认配置隔离' case_fzf_selection
  run_case 'fzf 取消空选无业务' case_fzf_cancellation
  run_case 'fzf 失败伪造结果停止' case_fzf_failure
  run_case '真实 fzf 健康探针' case_real_fzf_health
  run_case '依赖全链健康不安装' case_dependency_healthy
  run_case '末端缺失上游健康修复' case_dependency_repair
  run_case '依赖安装失败停止' case_dependency_install_failure
  run_case '依赖安装后复检失败停止' case_dependency_recheck_failure
  run_case 'Homebrew 多层缺失单次安装' case_brew_missing_chain
  run_case 'Homebrew 健康来源复用' case_brew_healthy_chain
  run_case '获取入口完整单地址流程' case_copy_entry_flow
  run_case '打开入口完整单地址流程' case_open_entry_flow
  run_case 'Sourcetree 多地址终端承接' case_terminal_handoff_flow
  run_case '两入口真实文件寻址及搬迁' case_real_source_paths
  run_case '两入口相对路径与文件名启动' case_relative_source_paths
  run_case 'zsh -c 文本启动与运行副本兜底' case_command_text_fallback
  run_case '两入口真实路径单地址业务' case_real_single_entry_modes
  run_case 'Terminal 转交真实脚本及仓库参数' case_real_terminal_arguments
  run_case 'zsh -c 缺少脚本副本停止' case_missing_command_text_path
  run_case 'Terminal 转交前脚本缺失停止' case_missing_handoff_file
  print -r -- "结果：$TEST_PASSED 通过，$TEST_FAILED 失败。"
  (( TEST_FAILED == 0 ))
}
# 加载生产函数后立即运行测试，避免执行生产 main。
load_subject_and_run() {
  source "$TEST_LIBRARY" || { cleanup_test_workspace; return 1; }
  run_regressions
  local result=$?
  cleanup_test_workspace
  return "$result"
}
# 编排说明、隔离环境与回归，不执行真实远程动作。
main() {
  show_test_intro # 打印隔离范围并验证真实 TTY。
  prepare_test_workspace # 准备临时 Git 和命令替身。
  load_subject_and_run # 载入生产函数并验证业务及失败边界。
}

main "$@"
