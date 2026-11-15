#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】📥修复Git无法Push.command
# - 核心用途：检查推送目标，安全整合非快进历史，普通推送后核对服务端提交；其它故障分类诊断。
# - 影响范围：仅当前仓库的已有分支和明确选择的远端分支；可能快进或创建保留双方历史的合并提交。
# - 运行提示：Sourcetree 转交 Terminal；终端先回车再确认计划；--diagnose 只诊断，--yes 表示明确授权执行。
# - 安全边界：不自动暂存、清理、stash、强推、变基、删除锁、改代理/鉴权或跨父子仓处理。

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

# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只展示提示选项；不读取答案、不改变默认值、返回码或业务环境。
jobs_prompt_color_ready() {
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 原生 awk 分段着色；任意/非空输入优先，括号内外沿用同一个选项。
jobs_prompt_format() {
  /usr/bin/awk -v color="${1:-0}" -v lines="${2:-0}" -v keep="${3:-0}" '
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
    function segment(value, inherited, start, kind, prefix, body, red, green, connector, left, right, splitAt) {
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
          return segment(left, 0) connector segment(right, 31)
        }
        if (red && green && red < green && match(value, /或[[:space:]]*(直接|仅|只需|只|按下|按)?(回车|回車)/)) {
          splitAt = RSTART
          return segment(substr(value, 1, splitAt - 1), 31) "或" segment(substr(value, splitAt + length("或")), 0)
        }
        if (red) {
          kind = 31
          start = red
        } else if (green) {
          kind = 32
          start = green
        }
      }
      if (!kind || !color) return value
      prefix = substr(value, 1, start - 1)
      body = substr(value, start)
      return prefix esc "[1;" kind "m" body esc "[0m"
    }
    function render(value, output, part, boundary, inherited, kind, consumed, depth, original) {
      original = value
      gsub(esc "\\[[0-9;]*m", "", value)
      if (color && keep && !greenPosition(value) && value !~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) return original
      output = ""
      inherited = 0
      depth = 0
      while (match(value, /[；;\/|，,、？?：:=＝（）()\[\]【】]/)) {
        part = substr(value, 1, RSTART - 1)
        boundary = substr(value, RSTART, RLENGTH)
        consumed = RSTART + RLENGTH
        output = output segment(part, inherited) boundary
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
      return output segment(value, inherited)
    }
    BEGIN { esc = sprintf("%c", 27); first = 1 }
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
  printf "%s" "$1" | jobs_prompt_format "$jobs_prompt_color" 0
}
# 仅放在显示链末端；tee 在此函数之前接收纯文本，不把 ANSI 写入日志。
jobs_prompt_stream() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  jobs_prompt_format "$jobs_prompt_color" 1 1
}
# 显示管道保留原末尾换行；只删除本轮追加的最后一个结束标记。
jobs_prompt_filter() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  { /bin/cat; printf '\001'; } | jobs_prompt_format "$jobs_prompt_color" 2 1
}
# 仅包装原 printf/echo/print 展示，原参数、尾换行与显示命令退出码保持不变。
jobs_prompt_output() {
  local jobs_prompt_status=0 jobs_prompt_stderr=0 jobs_prompt_arg="" jobs_prompt_previous=""
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
      "$@" 2>&1 | jobs_prompt_filter >&2
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    else
      "$@" | jobs_prompt_filter
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$(( ${PIPESTATUS[0]} != 0 ? ${PIPESTATUS[0]} : ${PIPESTATUS[1]} ))
  else
    "$@" | jobs_prompt_filter
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
    print -r -- "$*" | redact_stream | jobs_prompt_tee "$LOG_FILE"
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
  read -r "answer?$(jobs_prompt_render '已了解影响，按回车继续检查；Ctrl+C 取消：')" || exit 130
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
