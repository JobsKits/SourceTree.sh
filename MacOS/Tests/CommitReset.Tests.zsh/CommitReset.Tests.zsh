#!/bin/zsh
# 脚本自述：
# - 脚本名称：CommitReset.Tests.zsh
# - 核心用途：隔离验证提交回退的远端别名识别、soft 保留及失败保护。
# - 影响范围：仅本轮临时 Git 仓库，不联网、不修改用户 Git 配置或真实仓库。
# - 运行提示：终端先回车；--run 启动自动回归；结束保留夹具与日志。

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
    # 完整颜色帧有界重发；仅退出恢复容忍帧外回车和明确方向键。
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
                    # 仅退出恢复阶段允许帧外的明确控制键，普通文字仍然失败。
                    if [ "$jobs_style_query_phase" = cleanup ]; then
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
                            jobs_style_cleanup_control_keys=$(( ${jobs_style_cleanup_control_keys:-0} + 1 ))
                            if [ "$jobs_style_cleanup_control_keys" -gt 64 ]; then
                                jobs_style_query_failure='退出恢复期间已识别控制键超过 64 个，已停止自动恢复'
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
            jobs_style_cleanup_issue='无法读取或设置原终端输入模式，或临时配色未完成核验'
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            jobs_style_cleanup_control_keys=0
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
        trap 'jobs_style_exit_status=129; jobs_terminal_style_cleanup 129 continue; jobs_style_changed=0; exit 129' HUP
        trap 'jobs_style_exit_status=130; jobs_terminal_style_cleanup 130 continue; jobs_style_changed=0; exit 130' INT
        trap 'jobs_style_exit_status=143; jobs_terminal_style_cleanup 143 continue; jobs_style_changed=0; exit 143' TERM
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

TEST_PATH="${(%):-%x}"
SUBJECT=""
TEST_ROOT=""
CASE_DIR=""
REPOSITORY=""
BASE_COMMIT=""
TIP_COMMIT=""
CAPTURE=""
RESULT_CODE=0
CASE_INDEX=0
PASSED=0
FAILED=0

# 自动回归由显式参数启用，普通双击先说明范围并等待确认。
show_script_intro_and_wait() {
  print -r -- 'CommitReset.Tests.zsh：只在本轮临时仓库执行真实 soft 回退。'
  print -r -- '不联网；Terminal 转交和选择器由替身验证；Ctrl+C 取消，结束保留日志。'
  [[ "${1:-}" != --run ]] || return 0
  [[ -t 0 ]] || { print -u2 -r -- '非交互回归请显式传入 --run。'; exit 1; }
  read -r '?按回车开始；Ctrl+C 取消：' _ || exit 130
}
# 隔离身份、配置、网络协议与 Git 定位变量，避免受用户环境干扰。
prepare_environment() {
  emulate -R zsh
  setopt NO_NOMATCH PIPE_FAIL
  [[ "${1:-}" != --run ]] || shift
  SUBJECT="${1:-${TEST_PATH:A:h:h:h}/【MacOS@SourceTree】♻️双击Git（识别子Git） 提交回退.command/【MacOS@SourceTree】♻️双击Git（识别子Git） 提交回退.command}"
  [[ -f "$SUBJECT" ]] || { print -u2 -r -- "生产脚本不存在：$SUBJECT"; exit 1; }
  SUBJECT="${SUBJECT:A}"
  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/jobs-commit-reset-tests.XXXXXX")" || exit 1
  mkdir -p "$TEST_ROOT/Hooks" "$TEST_ROOT/Logs" || exit 1
  export TMPDIR="$TEST_ROOT/Logs"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=/usr/bin/false GIT_PROXY_COMMAND=/usr/bin/false
  export GIT_AUTHOR_NAME='Jobs fixture' GIT_COMMITTER_NAME='Jobs fixture'
  export GIT_AUTHOR_EMAIL='fixture@example.invalid' GIT_COMMITTER_EMAIL='fixture@example.invalid'
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_NAMESPACE GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
  [[ "$(tail -n 1 "$SUBJECT")" == 'main "$@"' ]] || { print -u2 -r -- '生产脚本末行不是唯一 main 入口，停止函数提取。'; exit 1; }
  sed '$d' "$SUBJECT" > "$TEST_ROOT/subject-functions.zsh" || exit 1
  print -r -- "测试目录：$TEST_ROOT"
}
# 创建两个有文件差异的提交，路径覆盖中文与空格。
new_fixture() {
  REPOSITORY="$CASE_DIR/工作仓库 空格"
  git init -q --initial-branch=main "$REPOSITORY" || return 1
  git -C "$REPOSITORY" config core.hooksPath "$TEST_ROOT/Hooks" || return 1
  git -C "$REPOSITORY" config commit.gpgsign false || return 1
  print -r -- base > "$REPOSITORY/changed.txt"
  print -r -- original > "$REPOSITORY/partial.txt"
  git -C "$REPOSITORY" add -- changed.txt partial.txt || return 1
  git -C "$REPOSITORY" commit -qm base || return 1
  BASE_COMMIT="$(git -C "$REPOSITORY" rev-parse HEAD)" || return 1
  print -r -- tip > "$REPOSITORY/changed.txt"
  git -C "$REPOSITORY" add -- changed.txt || return 1
  git -C "$REPOSITORY" commit -qm tip || return 1
  TIP_COMMIT="$(git -C "$REPOSITORY" rev-parse HEAD)" || return 1
}
# 跟踪引用仅写入隔离仓库；没有 fetch 或真实远端。
add_snapshot() {
  local remote="$1" commit="${2:-$BASE_COMMIT}" branch="${3:-main}"
  git -C "$REPOSITORY" remote add "$remote" "$CASE_DIR/unused-${remote}.git" || return 1
  git -C "$REPOSITORY" update-ref "refs/remotes/${remote}/${branch}" "$commit"
}
assert_equal() {
  [[ "$1" == "$2" ]] || { print -u2 -r -- "期望：$2；实际：$1"; return 1; }
}
# 记录索引和配置原始字节，验证 soft 与安全停止均未改写它们。
snapshot_metadata() {
  cp -p "$(git -C "$REPOSITORY" rev-parse --path-format=absolute --git-path index)" "$CASE_DIR/index.before" || return 1
  cp -p "$(git -C "$REPOSITORY" rev-parse --path-format=absolute --git-path config)" "$CASE_DIR/config.before"
}
assert_metadata_unchanged() {
  cmp -s "$CASE_DIR/index.before" "$(git -C "$REPOSITORY" rev-parse --path-format=absolute --git-path index)" || { print -u2 -r -- '索引字节被改写。'; return 1; }
  cmp -s "$CASE_DIR/config.before" "$(git -C "$REPOSITORY" rev-parse --path-format=absolute --git-path config)" || { print -u2 -r -- 'Git 配置被改写。'; return 1; }
}
# 完整入口模拟 Sourcetree 无交互执行，保存实际输出与退出码。
run_subject() {
  local expectation="$1"
  shift
  RESULT_CODE=0
  SOURCETREE=1 TERM=dumb /bin/zsh "$SUBJECT" "$REPOSITORY" "$@" > "$CASE_DIR/subject.log" 2>&1 || RESULT_CODE=$?
  CAPTURE="$(<"$CASE_DIR/subject.log")"
  [[ "$CAPTURE" != *$'\033'* ]] || { print -u2 -r -- 'Sourcetree 输出残留 ANSI。'; return 1; }
  if [[ "$expectation" == success && "$RESULT_CODE" != 0 || "$expectation" == failure && "$RESULT_CODE" == 0 ]]; then
    print -u2 -r -- "生产入口预期 $expectation，实际退出 $RESULT_CODE：$CAPTURE"
    return 1
  fi
}
assert_reset() {
  assert_equal "$(git -C "$REPOSITORY" rev-parse HEAD)" "$BASE_COMMIT" || return 1
  assert_metadata_unchanged || return 1
  [[ "$CAPTURE" == *'已 soft 回退'* ]] || { print -u2 -r -- "$CAPTURE"; return 1; }
}
assert_stopped() {
  assert_equal "$(git -C "$REPOSITORY" rev-parse HEAD)" "$TIP_COMMIT" || return 1
  assert_metadata_unchanged || return 1
  [[ "$CAPTURE" != *'已 soft 回退'* ]] || return 1
}
case_two_renamed_remotes() {
  new_fixture && add_snapshot GitHub && add_snapshot 码云 && snapshot_metadata || return 1
  run_subject success && assert_reset
}
case_single_renamed_remote() {
  new_fixture && add_snapshot 自建远端 && snapshot_metadata || return 1
  run_subject success && assert_reset
}
case_origin_compatible() {
  new_fixture && add_snapshot origin && snapshot_metadata || return 1
  run_subject success && assert_reset
}
case_configured_different_branch() {
  new_fixture && add_snapshot 上游 "$BASE_COMMIT" releases/stable || return 1
  git -C "$REPOSITORY" config branch.main.remote 上游 || return 1
  git -C "$REPOSITORY" config branch.main.merge refs/heads/releases/stable || return 1
  snapshot_metadata && run_subject success && assert_reset
}
case_explicit_overrides_divergence() {
  new_fixture && add_snapshot GitHub && add_snapshot 码云 "$TIP_COMMIT" && snapshot_metadata || return 1
  run_subject success --upstream refs/remotes/GitHub/main && assert_reset
}
case_staged_and_worktree_preserved() {
  new_fixture && add_snapshot GitHub && add_snapshot 码云 || return 1
  print -r -- staged > "$REPOSITORY/partial.txt"
  git -C "$REPOSITORY" add -- partial.txt || return 1
  print -r -- unstaged >> "$REPOSITORY/partial.txt"
  print -r -- untracked > "$REPOSITORY/未跟踪 文件.txt"
  cp -p "$REPOSITORY/partial.txt" "$CASE_DIR/partial.before" || return 1
  cp -p "$REPOSITORY/未跟踪 文件.txt" "$CASE_DIR/untracked.before" || return 1
  snapshot_metadata && run_subject success && assert_reset || return 1
  cmp -s "$CASE_DIR/partial.before" "$REPOSITORY/partial.txt" || return 1
  cmp -s "$CASE_DIR/untracked.before" "$REPOSITORY/未跟踪 文件.txt" || return 1
  assert_equal "$(<"$REPOSITORY/changed.txt")" tip
}
case_missing_configured_snapshot() {
  new_fixture && add_snapshot GitHub && snapshot_metadata || return 1
  git -C "$REPOSITORY" config branch.main.remote missing || return 1
  git -C "$REPOSITORY" config branch.main.merge refs/heads/main || return 1
  snapshot_metadata && run_subject failure && assert_stopped
}
case_remote_only_configuration() {
  new_fixture && add_snapshot GitHub || return 1
  git -C "$REPOSITORY" config branch.main.remote GitHub || return 1
  snapshot_metadata && run_subject failure && assert_stopped
}
case_merge_only_configuration() {
  new_fixture && add_snapshot GitHub || return 1
  git -C "$REPOSITORY" config branch.main.merge refs/heads/main || return 1
  snapshot_metadata && run_subject failure && assert_stopped
}
case_local_upstream() {
  new_fixture && add_snapshot GitHub || return 1
  git -C "$REPOSITORY" branch local-target "$BASE_COMMIT" || return 1
  git -C "$REPOSITORY" config branch.main.remote . || return 1
  git -C "$REPOSITORY" config branch.main.merge refs/heads/local-target || return 1
  snapshot_metadata && run_subject failure && assert_stopped
}
case_explicit_overrides_bad_configuration() {
  new_fixture && add_snapshot GitHub || return 1
  git -C "$REPOSITORY" config branch.main.remote missing || return 1
  git -C "$REPOSITORY" config branch.main.merge refs/heads/main || return 1
  snapshot_metadata && run_subject success --upstream refs/remotes/GitHub/main && assert_reset
}
case_no_candidate() {
  new_fixture && snapshot_metadata || return 1
  run_subject failure && assert_stopped
}
case_other_branch_not_candidate() {
  new_fixture && add_snapshot GitHub "$BASE_COMMIT" other && snapshot_metadata || return 1
  run_subject failure && assert_stopped
}
case_explicit_missing_ref() {
  new_fixture && add_snapshot GitHub && snapshot_metadata || return 1
  run_subject failure --upstream refs/remotes/origin/main && assert_stopped
}
case_revision_expression_rejected() {
  new_fixture && add_snapshot GitHub && snapshot_metadata || return 1
  run_subject failure --upstream 'refs/remotes/GitHub/main~1' && assert_stopped
}
case_nonancestor_snapshot() {
  new_fixture || return 1
  local independent="$(git -C "$REPOSITORY" commit-tree "$(git -C "$REPOSITORY" rev-parse 'HEAD^{tree}')" -m independent)"
  add_snapshot GitHub "$independent" && snapshot_metadata || return 1
  run_subject failure && assert_stopped
}
case_detached_head() {
  new_fixture && add_snapshot GitHub || return 1
  git -C "$REPOSITORY" checkout -q --detach || return 1
  snapshot_metadata && run_subject failure && assert_stopped
}
case_existing_lock() {
  new_fixture && add_snapshot GitHub || return 1
  print -r -- 'held by fixture' > "$(git -C "$REPOSITORY" rev-parse --path-format=absolute --git-path index.lock)"
  snapshot_metadata && run_subject failure && assert_stopped || return 1
  assert_equal "$(<"$REPOSITORY/.git/index.lock")" 'held by fixture'
}
case_head_already_at_snapshot() {
  new_fixture && add_snapshot GitHub "$TIP_COMMIT" && snapshot_metadata || return 1
  run_subject success && assert_stopped || return 1
  [[ "$CAPTURE" == *'本次没有撤回提交'* ]]
}
# 真实子模块使用 .git 指针，父仓索引与提交均不得被子仓回退改写。
case_real_submodule() {
  new_fixture || return 1
  local source="$REPOSITORY" parent="$CASE_DIR/父仓 空格" parent_head=""
  git init -q --initial-branch=main "$parent" || return 1
  git -C "$parent" config core.hooksPath "$TEST_ROOT/Hooks" || return 1
  git -C "$parent" config commit.gpgsign false || return 1
  git -C "$parent" -c protocol.file.allow=always submodule add -q "$source" '子仓 空格' || return 1
  git -C "$parent" commit -qm submodule || return 1
  parent_head="$(git -C "$parent" rev-parse HEAD)" || return 1
  print -r -- 'parent staged' > "$parent/parent.txt"
  git -C "$parent" add -- parent.txt || return 1
  cp -p "$parent/.git/index" "$CASE_DIR/parent-index.before" || return 1
  cp -p "$parent/.git/config" "$CASE_DIR/parent-config.before" || return 1
  REPOSITORY="$parent/子仓 空格"
  [[ -f "$REPOSITORY/.git" ]] || return 1
  git -C "$REPOSITORY" remote rename origin GitHub || return 1
  git -C "$REPOSITORY" config --unset-all branch.main.remote || return 1
  git -C "$REPOSITORY" config --unset-all branch.main.merge || return 1
  git -C "$REPOSITORY" update-ref refs/remotes/GitHub/main "$BASE_COMMIT" || return 1
  add_snapshot 码云 && snapshot_metadata && run_subject success && assert_reset || return 1
  assert_equal "$(git -C "$parent" rev-parse HEAD)" "$parent_head" || return 1
  cmp -s "$CASE_DIR/parent-index.before" "$parent/.git/index" || return 1
  cmp -s "$CASE_DIR/parent-config.before" "$parent/.git/config" || return 1
  [[ "$CAPTURE" == *'直属父仓'* ]]
}
# 只替换 Terminal 启动，仍运行完整 main 检查多快照分流及未回退结果。
case_distinct_snapshots_dispatch() {
  new_fixture && add_snapshot GitHub && add_snapshot 码云 "$TIP_COMMIT" && snapshot_metadata || return 1
  cat > "$CASE_DIR/dispatch.zsh" <<'HARNESS'
source "$1"
open_terminal_for_selection() {
  print -r -- "$REPO_ROOT" > "$DISPATCH_TRACE"
}
shift
main "$@"
HARNESS
  SOURCETREE=1 TERM=dumb DISPATCH_TRACE="$CASE_DIR/dispatch.trace" /bin/zsh "$CASE_DIR/dispatch.zsh" "$TEST_ROOT/subject-functions.zsh" "$REPOSITORY" > "$CASE_DIR/subject.log" 2>&1 || return 1
  CAPTURE="$(<"$CASE_DIR/subject.log")"
  assert_equal "$(<"$CASE_DIR/dispatch.trace")" "${REPOSITORY:A}" && assert_stopped
}
# 选择器替身在返回前更新所选引用，生产解析必须发现快照变化并停止。
case_selected_snapshot_drift() {
  new_fixture && add_snapshot GitHub && add_snapshot 码云 && snapshot_metadata || return 1
  cat > "$CASE_DIR/drift.zsh" <<'HARNESS'
source "$1"
PLAIN_OUTPUT=1
IS_SOURCETREE_RUNTIME=0
resolve_repository "$2" || exit 1
choose_entry() {
  SELECTION="refs/remotes/GitHub/main [fixture]"
  git -C "$REPO_ROOT" update-ref refs/remotes/GitHub/main "$INITIAL_HEAD_COMMIT"
}
resolve_upstream_target
HARNESS
  local result=0
  TERM=dumb /bin/zsh "$CASE_DIR/drift.zsh" "$TEST_ROOT/subject-functions.zsh" "$REPOSITORY" > "$CASE_DIR/subject.log" 2>&1 || result=$?
  CAPTURE="$(<"$CASE_DIR/subject.log")"
  (( result != 0 )) && [[ "$CAPTURE" == *'快照在选择期间已变化'* ]] && assert_stopped
}
# 每例独立子进程，失败保留精确证据且继续运行其它场景。
run_case() {
  local title="$1" callback="$2"
  CASE_INDEX=$((CASE_INDEX + 1))
  CASE_DIR="$TEST_ROOT/case-$CASE_INDEX"
  mkdir -p "$CASE_DIR" || exit 1
  if ( "$callback" ) > "$CASE_DIR/result.log" 2>&1; then
    PASSED=$((PASSED + 1))
    print -r -- "PASS  $title"
  else
    FAILED=$((FAILED + 1))
    print -r -- "FAIL  $title：$CASE_DIR/result.log"
    cat "$CASE_DIR/result.log"
  fi
}
run_regressions() {
  run_case 'GitHub/码云同快照且无 upstream' case_two_renamed_remotes
  run_case '唯一改名远端且无 upstream' case_single_renamed_remote
  run_case 'origin 默认入口兼容' case_origin_compatible
  run_case '已配置异名远端与异名分支' case_configured_different_branch
  run_case '显式线路覆盖多快照歧义' case_explicit_overrides_divergence
  run_case '已有暂存、未暂存和未跟踪内容保持' case_staged_and_worktree_preserved
  run_case '已配置 upstream 快照缺失停止' case_missing_configured_snapshot
  run_case '只有 remote 的部分 upstream 配置停止' case_remote_only_configuration
  run_case '只有 merge 的部分 upstream 配置停止' case_merge_only_configuration
  run_case '本地分支 upstream 不自动切换远端' case_local_upstream
  run_case '显式线路可覆盖失效 upstream 配置' case_explicit_overrides_bad_configuration
  run_case '无任何候选停止' case_no_candidate
  run_case '其它分支快照不当作当前分支目标' case_other_branch_not_candidate
  run_case '显式缺失引用不回退其它线路' case_explicit_missing_ref
  run_case '显式修订表达式被拒绝' case_revision_expression_rejected
  run_case '非 HEAD 祖先目标停止' case_nonancestor_snapshot
  run_case '游离 HEAD 远端回退停止' case_detached_head
  run_case '现有 index.lock 保护' case_existing_lock
  run_case 'HEAD 已等于快照不虚报撤回' case_head_already_at_snapshot
  run_case '真实子模块 .git 文件与父仓保护' case_real_submodule
  run_case '多快照不同转交 Terminal 且不回退' case_distinct_snapshots_dispatch
  run_case '选择期间所选快照变化停止' case_selected_snapshot_drift
}
finish_regressions() {
  print -r -- "结果：${PASSED} 通过，${FAILED} 失败；证据：$TEST_ROOT"
  [[ "$FAILED" == 0 ]] || exit 1
}
main() {
  show_script_intro_and_wait "$@" # 在创建临时仓库前说明范围并确认。
  prepare_environment "$@" # 隔离配置、协议和全部测试日志。
  run_regressions # 真实入口与必要的交互替身分别验证。
  finish_regressions # 汇总并传播失败状态。
}

main "$@"
