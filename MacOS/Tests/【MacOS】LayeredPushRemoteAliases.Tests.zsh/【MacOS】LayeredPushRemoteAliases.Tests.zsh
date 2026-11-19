#!/bin/zsh
# 脚本自述：
# - 核心用途：验证逐层推送的远程别名、分支映射、失败停止和原有分支保护。
# - 影响范围：只在本次 /tmp 目录创建仓库与本地 bare 远端；禁止 SSH / HTTP 传输。
# - 运行提示：默认验证相邻生产脚本，也可传入另一份生产脚本的绝对路径。

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

# 识别询问展示的彩色能力，纯文本调用不添加控制码。
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
# 仅格式化提示文本，分开突出题干和操作选项。
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
# 为真实read提示渲染样式，不读取或改变输入。
jobs_prompt_render() {
  local jobs_prompt_color=0
  if [ -t 0 ] && [ -t 2 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  printf "%s" "$1" | jobs_prompt_format "$jobs_prompt_color" 0 0 1
}


TEST_SOURCE_PATH="${0:A}"
TEST_SUBJECT=""
TEST_ROOT=""
TEST_CASE_DIR=""
TEST_REPOSITORY=""
TEST_HUB_BARE=""
TEST_GITEE_BARE=""
TEST_POLICY=0
TEST_PASSED=0
TEST_FAILED=0
TEST_CASE_NUMBER=0
TEST_HUB_URL='git@github.com:jobs-fixture/repository.git'
TEST_GITEE_URL='git@gitee.com:jobs-fixture/repository.git'

# 所有测试都复用真实生产函数，只移除唯一的最终入口调用。
prepare_test_workspace() {
  emulate -R zsh
  setopt NO_NOMATCH PIPE_FAIL
  [[ "${1:-}" != --run ]] || shift
  TEST_SUBJECT="${1:-${TEST_SOURCE_PATH:h:h:h}/【MacOS@SourceTree】🚀逐层空白提交并Push.command/【MacOS@SourceTree】🚀逐层空白提交并Push.command}"
  [[ -f "$TEST_SUBJECT" && "$(/usr/bin/tail -n 1 "$TEST_SUBJECT")" == 'main "$@"' ]] || {
    print -u2 -r -- "生产脚本不存在或入口结构已变化：${TEST_SUBJECT}"
    return 1
  }
  TEST_ROOT="$(/usr/bin/mktemp -d /tmp/jobs-layered-push-aliases.XXXXXX)" || return 1
  /usr/bin/sed '$d' "$TEST_SUBJECT" > "$TEST_ROOT/production-functions.zsh" || return 1
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_TERMINAL_PROMPT=0 GIT_ALLOW_PROTOCOL=file GIT_SSH_COMMAND=/usr/bin/false GIT_PROXY_COMMAND=/usr/bin/false
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_NAMESPACE GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
  source "$TEST_ROOT/production-functions.zsh" || return 1
}
# 生产逻辑继续看见官方主机；只有真实传输参数映射到本次本地远端。
git() {
  local -a arguments=("$@")
  local index=0 transport=0 repository=""
  [[ "${arguments[1]:-}" != -C ]] || repository="${arguments[2]}"
  if (( ${arguments[(Ie)fetch]} || ${arguments[(Ie)push]} || ${arguments[(Ie)ls-remote]} )); then
    transport=1
  fi
  if [[ "$transport" == 1 ]]; then
    print -r -- "${(j: :)arguments}" >> "$TEST_CASE_DIR/transport.log"
    for ((index = 1; index <= ${#arguments}; index++)); do
      case "${arguments[index]}" in
        "$TEST_HUB_URL") arguments[index]="$TEST_HUB_BARE" ;;
        "$TEST_GITEE_URL") arguments[index]="$TEST_GITEE_BARE" ;;
      esac
    done
    # 游离恢复的生产路径使用 remote 名称，Git 自己解析其 URL。
    for ((index = 1; index <= ${#arguments}; index++)); do
      if [[ -n "$repository" && "${arguments[index]}" != -* ]]; then
        local configured_url="$(/usr/bin/git -C "$repository" config --get "remote.${arguments[index]}.url" 2>/dev/null || true)"
        case "$configured_url" in
          "$TEST_HUB_URL") arguments[index]="$TEST_HUB_BARE" ;;
          "$TEST_GITEE_URL") arguments[index]="$TEST_GITEE_BARE" ;;
        esac
      fi
    done
  fi
  /usr/bin/git "${arguments[@]}"
}

assert_equal() {
  [[ "$1" == "$2" ]] || { print -u2 -r -- "期望：$2；实际：$1"; return 1; }
}

assert_failure() {
  if "$@"; then
    print -u2 -r -- "预期停止，但实际成功：$*"
    return 1
  fi
}
# 每例独立子进程隔离生产数组、替身函数和临时配置。
run_case() {
  local title="$1" callback="$2"
  TEST_CASE_NUMBER=$((TEST_CASE_NUMBER + 1))
  TEST_CASE_DIR="$TEST_ROOT/case-${TEST_CASE_NUMBER}"
  /bin/mkdir -p "$TEST_CASE_DIR" || return 1
  if ( "$callback" ) > "$TEST_CASE_DIR/result.log" 2>&1; then
    TEST_PASSED=$((TEST_PASSED + 1))
    print -r -- "PASS  ${title}"
  else
    TEST_FAILED=$((TEST_FAILED + 1))
    print -r -- "FAIL  ${title}；日志：${TEST_CASE_DIR}/result.log"
    /usr/bin/tail -n 16 "$TEST_CASE_DIR/result.log"
  fi
}

new_repository() {
  TEST_REPOSITORY="$TEST_CASE_DIR/工作仓库 空格"
  TEST_HUB_BARE="$TEST_CASE_DIR/github.git"
  TEST_GITEE_BARE="$TEST_CASE_DIR/gitee.git"
  TEST_POLICY=0
  LOG_FILE="$TEST_CASE_DIR/production.log"
  PLAIN_OUTPUT=1
  /usr/bin/git -c init.templateDir= init -q --initial-branch=main "$TEST_REPOSITORY" || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config user.name Fixture || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config user.email fixture@example.invalid || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config commit.gpgSign false || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" commit --allow-empty -qm fixture || return 1
}
# 临时路径不会落入真实业务根，仅替换策略范围判定，分支解析仍用生产实现。
enable_fixed_policy() {
  TEST_POLICY=1
  uses_gitee_branch_policy() { [[ "$TEST_POLICY" == 1 ]]; }
}

add_two_remotes() {
  /usr/bin/git -C "$TEST_REPOSITORY" remote add "${1:-Github}" "$TEST_HUB_URL" || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" remote add "${2:-码云}" "$TEST_GITEE_URL"
}

assert_push_mapping() {
  local expected_hub="$1" expected_gitee="$2" index=0 hub_seen=0 gitee_seen=0 target=""
  for target in "${RESOLVED_PUSH_TARGETS[@]}"; do
    index=$((index + 1))
    case "$target" in
      "$TEST_HUB_URL") assert_equal "${RESOLVED_PUSH_REFS[index]}" "refs/heads/${expected_hub}" || return 1; hub_seen=1 ;;
      "$TEST_GITEE_URL") assert_equal "${RESOLVED_PUSH_REFS[index]}" "refs/heads/${expected_gitee}" || return 1; gitee_seen=1 ;;
      *) print -u2 -r -- "意外推送地址：${target}"; return 1 ;;
    esac
  done
  [[ "$hub_seen" == 1 && "$gitee_seen" == 1 && "${#RESOLVED_PUSH_TARGETS}" == 2 ]]
}

case_renamed_fallback() {
  new_repository && add_two_remotes || return 1
  assert_equal "$(resolve_fallback_remote "$TEST_REPOSITORY")" Github || return 1
  preflight_repository "$TEST_REPOSITORY" || return 1
  [[ -z "$(/usr/bin/git -C "$TEST_REPOSITORY" config --get branch.main.remote || true)" ]]
}

case_legacy_fallback() {
  new_repository && add_two_remotes origin gitee || return 1
  assert_equal "$(resolve_fallback_remote "$TEST_REPOSITORY")" origin
}

case_arbitrary_aliases() {
  new_repository && add_two_remotes 主线路 国内镜像 || return 1
  assert_equal "$(resolve_fallback_remote "$TEST_REPOSITORY")" 主线路 || return 1
  resolve_push_targets "$TEST_REPOSITORY" 主线路 && assert_push_mapping main main
}

case_ambiguous_github() {
  new_repository && add_two_remotes || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" remote add second-hub 'https://github.com/other/repository.git' || return 1
  assert_failure resolve_fallback_remote "$TEST_REPOSITORY" && assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" branch --format='%(refname:short)')" main
}

case_single_unknown() {
  new_repository || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" remote add 发布 'ssh://git@internal.example/group/repository.git' || return 1
  assert_equal "$(resolve_fallback_remote "$TEST_REPOSITORY")" 发布
}

case_spoofed_network_host() {
  assert_failure remote_hosting_platform Github 'https://github.com.example/group/repo.git' || return 1
  assert_failure remote_hosting_platform Github 'https://github.com@unrelated.example/group/repo.git' || return 1
  assert_failure remote_hosting_platform 码云 'ssh://git@unrelated.example:2222/group/repo.git' || return 1
  assert_failure remote_hosting_platform Github 'git@notgithub.com:group/repo.git'
}

case_official_hosts() {
  assert_equal "$(remote_hosting_platform 任意名 'ssh://git@github.com:2222/group/repo.git')" github || return 1
  assert_equal "$(remote_hosting_platform 任意名 'https://name@gitee.com:8443/group/repo.git')" gitee || return 1
  assert_equal "$(remote_hosting_platform 任意名 'git@github.com:group/repo.git')" github || return 1
  assert_equal "$(remote_hosting_platform Github "$TEST_CASE_DIR/local.git")" github
}

case_fixed_default() {
  new_repository && add_two_remotes || return 1
  enable_fixed_policy
  resolve_push_targets "$TEST_REPOSITORY" Github && assert_push_mapping main gitee
}

case_actual_alias_override() {
  new_repository && add_two_remotes || return 1
  enable_fixed_policy
  /usr/bin/git -C "$TEST_REPOSITORY" config remote.码云.jobsPushBranch main || return 1
  resolve_push_targets "$TEST_REPOSITORY" Github && assert_push_mapping main main
}

case_legacy_override() {
  new_repository && add_two_remotes origin gitee || return 1
  enable_fixed_policy
  /usr/bin/git -C "$TEST_REPOSITORY" config remote.gitee.jobsPushBranch release/stable || return 1
  resolve_push_targets "$TEST_REPOSITORY" origin && assert_push_mapping main release/stable
}

case_empty_and_global_override() {
  new_repository && add_two_remotes || return 1
  enable_fixed_policy
  /usr/bin/git config --file "$TEST_CASE_DIR/global.gitconfig" remote.码云.jobsPushBranch main || return 1
  export GIT_CONFIG_GLOBAL="$TEST_CASE_DIR/global.gitconfig"
  resolve_push_targets "$TEST_REPOSITORY" Github && assert_push_mapping main gitee || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config remote.码云.jobsPushBranch '' || return 1
  resolve_push_targets "$TEST_REPOSITORY" Github && assert_push_mapping main gitee
}

case_orphaned_old_key() {
  new_repository && add_two_remotes || return 1
  enable_fixed_policy
  /usr/bin/git -C "$TEST_REPOSITORY" config remote.gitee.jobsPushBranch main || return 1
  resolve_push_targets "$TEST_REPOSITORY" Github && assert_push_mapping main gitee
}

case_invalid_branch() {
  new_repository && add_two_remotes || return 1
  enable_fixed_policy
  /usr/bin/git -C "$TEST_REPOSITORY" config remote.码云.jobsPushBranch 'bad..branch' || return 1
  assert_failure resolve_push_targets "$TEST_REPOSITORY" Github
}

case_multiple_override_values() {
  new_repository && add_two_remotes || return 1
  enable_fixed_policy
  /usr/bin/git -C "$TEST_REPOSITORY" config --add remote.码云.jobsPushBranch main || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config --add remote.码云.jobsPushBranch release/stable || return 1
  assert_failure resolve_push_targets "$TEST_REPOSITORY" Github
}

case_conflicting_same_url() {
  new_repository && add_two_remotes || return 1
  enable_fixed_policy
  /usr/bin/git -C "$TEST_REPOSITORY" remote add 第二码云 "$TEST_GITEE_URL" || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config remote.码云.jobsPushBranch main || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config remote.第二码云.jobsPushBranch release/stable || return 1
  assert_failure resolve_push_targets "$TEST_REPOSITORY" Github
}
# 两个真实 bare 远端都来自同一个提交，后续整合不使用网络替身返回伪 SHA。
seed_bare_remotes() {
  local gitee_branch="${1:-main}"
  /usr/bin/git -c init.templateDir= init -q --bare --initial-branch=main "$TEST_HUB_BARE" || return 1
  /usr/bin/git -c init.templateDir= init -q --bare --initial-branch="$gitee_branch" "$TEST_GITEE_BARE" || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" push -q "$TEST_HUB_BARE" HEAD:refs/heads/main || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" push -q "$TEST_GITEE_BARE" "HEAD:refs/heads/${gitee_branch}"
}

advance_bare_remote() {
  local bare="$1" filename="$2" branch="${3:-main}" writer=""
  writer="$TEST_CASE_DIR/writer-${filename}"
  /usr/bin/git -c init.templateDir= clone -q --branch "$branch" "$bare" "$writer" || return 1
  /usr/bin/git -C "$writer" config user.name Fixture || return 1
  /usr/bin/git -C "$writer" config user.email fixture@example.invalid || return 1
  print -r -- "$filename" > "$writer/$filename" || return 1
  /usr/bin/git -C "$writer" add -- "$filename" || return 1
  /usr/bin/git -C "$writer" -c commit.gpgSign=false commit -qm "$filename" || return 1
  /usr/bin/git -C "$writer" push -q origin "HEAD:refs/heads/${branch}"
}

run_real_pipeline() {
  preflight_repository "$TEST_REPOSITORY" || return 1
  synchronize_repository_upstream "$TEST_REPOSITORY" || return 1
  commit_repository_changes "$TEST_REPOSITORY" || return 1
  integrate_repository_upstream "$TEST_REPOSITORY" || return 1
  push_repository "$TEST_REPOSITORY"
}

assert_two_bare_tips() {
  local gitee_branch="$1" head="$(/usr/bin/git -C "$TEST_REPOSITORY" rev-parse HEAD)"
  assert_equal "$(/usr/bin/git --git-dir="$TEST_HUB_BARE" rev-parse refs/heads/main)" "$head" || return 1
  assert_equal "$(/usr/bin/git --git-dir="$TEST_GITEE_BARE" rev-parse "refs/heads/${gitee_branch}")" "$head" || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" symbolic-ref --short HEAD)" main || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" for-each-ref --format='%(refname:short)' refs/heads/)" main || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" config --get branch.main.remote)" Github || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" config --get branch.main.merge)" refs/heads/main
}

case_real_renamed_merge_and_push() {
  new_repository && add_two_remotes && seed_bare_remotes main || return 1
  advance_bare_remote "$TEST_HUB_BARE" github-change || return 1
  advance_bare_remote "$TEST_GITEE_BARE" gitee-change || return 1
  print -r -- local-change > "$TEST_REPOSITORY/local-change" || return 1
  run_real_pipeline && assert_two_bare_tips main || return 1
  [[ -f "$TEST_REPOSITORY/github-change" && -f "$TEST_REPOSITORY/gitee-change" && -f "$TEST_REPOSITORY/local-change" ]]
}

case_real_fixed_target() {
  new_repository && add_two_remotes && seed_bare_remotes gitee || return 1
  enable_fixed_policy
  print -r -- changed > "$TEST_REPOSITORY/changed" || return 1
  run_real_pipeline && assert_two_bare_tips gitee || return 1
  assert_failure /usr/bin/git --git-dir="$TEST_GITEE_BARE" show-ref --verify --quiet refs/heads/main
}

case_real_main_override() {
  new_repository && add_two_remotes && seed_bare_remotes main || return 1
  enable_fixed_policy
  /usr/bin/git -C "$TEST_REPOSITORY" config remote.码云.jobsPushBranch main || return 1
  print -r -- changed > "$TEST_REPOSITORY/changed" || return 1
  run_real_pipeline && assert_two_bare_tips main || return 1
  assert_failure /usr/bin/git --git-dir="$TEST_GITEE_BARE" show-ref --verify --quiet refs/heads/gitee
}

case_explicit_upstream_stays() {
  new_repository && add_two_remotes && seed_bare_remotes main || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config branch.main.remote 码云 || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config branch.main.merge refs/heads/main || return 1
  print -r -- changed > "$TEST_REPOSITORY/changed" || return 1
  run_real_pipeline || return 1
  local head="$(/usr/bin/git -C "$TEST_REPOSITORY" rev-parse HEAD)"
  assert_equal "$(/usr/bin/git --git-dir="$TEST_HUB_BARE" rev-parse refs/heads/main)" "$head" || return 1
  assert_equal "$(/usr/bin/git --git-dir="$TEST_GITEE_BARE" rev-parse refs/heads/main)" "$head" || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" config --get branch.main.remote)" 码云 || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" for-each-ref --format='%(refname:short)' refs/heads/)" main
}

case_push_rejection_stops_second_line() {
  new_repository && add_two_remotes && seed_bare_remotes main || return 1
  local before="$(/usr/bin/git --git-dir="$TEST_GITEE_BARE" rev-parse refs/heads/main)"
  /bin/mkdir -p "$TEST_HUB_BARE/hooks" || return 1
  print -r -- $'#!/bin/sh\nexit 1' > "$TEST_HUB_BARE/hooks/pre-receive" || return 1
  /bin/chmod u+x "$TEST_HUB_BARE/hooks/pre-receive" || return 1
  print -r -- changed > "$TEST_REPOSITORY/changed" || return 1
  assert_failure run_real_pipeline || return 1
  assert_equal "$(/usr/bin/git --git-dir="$TEST_GITEE_BARE" rev-parse refs/heads/main)" "$before" || return 1
  [[ "$(/usr/bin/grep -c ' push ' "$TEST_CASE_DIR/transport.log")" == 1 ]]
}

case_detached_reuses_existing_branch() {
  new_repository && add_two_remotes && seed_bare_remotes main || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" checkout -q --detach || return 1
  REPOSITORY_CHAIN=("$TEST_REPOSITORY")
  prepare_detached_repositories || return 1
  assert_equal "${DETACHED_BRANCHES[$TEST_REPOSITORY]}" main || return 1
  assert_equal "${DETACHED_REMOTES[$TEST_REPOSITORY]}" Github || return 1
  restore_detached_repositories <<< YES || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" symbolic-ref --short HEAD)" main || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" for-each-ref --format='%(refname:short)' refs/heads/)" main
}

case_detached_missing_local_stops() {
  new_repository && add_two_remotes && seed_bare_remotes main || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" branch -m work || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" checkout -q --detach || return 1
  REPOSITORY_CHAIN=("$TEST_REPOSITORY")
  print -r -- keep > "$TEST_REPOSITORY/untracked-must-stay" || return 1
  assert_failure prepare_detached_repositories || return 1
  [[ -f "$TEST_REPOSITORY/untracked-must-stay" ]] || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" for-each-ref --format='%(refname:short)' refs/heads/)" work
}

case_snapshot_boundary() {
  new_repository || return 1
  REPOSITORY_CHAIN=("${HOME}/Documents/Github/JobsOCBaseConfigDemo@ByPods")
  assert_failure check_snapshot_repository_boundary || return 1
  [[ ! -f "$TEST_CASE_DIR/transport.log" ]]
}
# 成功时只删除本次 mktemp 目录；失败时保留证据供修复。
finish_tests() {
  print -r -- "结果：${TEST_PASSED} 通过，${TEST_FAILED} 失败。"
  if [[ "$TEST_FAILED" == 0 ]]; then
    /bin/rm -r -- "$TEST_ROOT" || return 1
    return 0
  fi
  print -r -- "失败证据保留于：${TEST_ROOT}"
  return 1
}
# 先说明临时夹具边界；自动化调用须显式选择 --run。
show_test_intro_and_wait() {
  print -r -- '逐层推送别名隔离回归：仅系统临时目录中的本地 Git；SSH / HTTP 均禁止。'
  print -r -- '日志：本轮临时目录逐例保存，失败保留；Ctrl+C 可取消。'
  [[ "${1:-}" != --run ]] || return 0
  [[ -t 0 ]] || { print -u2 -r -- '请在终端确认，或显式传 --run 启动隔离回归。'; exit 2; }
  IFS= read -r "?$(jobs_prompt_render '已了解测试范围，按回车继续；Ctrl+C 取消：')" _ || exit 130
}
# 初始化失败时保留原退出码并停止后续用例，避免空路径误操作。
prepare_test_workspace_or_stop() {
  prepare_test_workspace "$@" || exit $?
}
# 编排已确认的隔离回归，不操作用户的真实仓库。
main() {
  show_test_intro_and_wait "$@" # 展示夹具、日志和取消边界。
  prepare_test_workspace_or_stop "$@" # 加载真实生产函数并隔离 Git 环境。
  run_case 'Github + 码云在无 upstream 时可预检' case_renamed_fallback # 验证新名字自动选择。
  run_case 'origin + gitee继续兼容' case_legacy_fallback # 保留旧名字行为。
  run_case '任意别名按官方主机识别' case_arbitrary_aliases # 不依赖显示名称。
  run_case '多个GitHub候选停止' case_ambiguous_github # 避免猜测上游。
  run_case '唯一自建服务仍可选择' case_single_unknown # 保留单线路兼容。
  run_case '平台名字不能伪装其它网络主机' case_spoofed_network_host # 核对完整主机边界。
  run_case 'SSH/HTTPS端口及本地别名识别' case_official_hosts # 保留地址形式兼容。
  run_case '改名后固定码云目标仍为gitee' case_fixed_default # 区分别名与目标分支。
  run_case '实际码云别名可覆盖为main' case_actual_alias_override # 验证仓库局部配置。
  run_case '旧gitee键和多层分支继续支持' case_legacy_override # 保留既有覆盖格式。
  run_case '忽略全局覆盖且空值回退' case_empty_and_global_override # 保持配置作用域。
  run_case '不继承已移除别名的孤立覆盖键' case_orphaned_old_key # 避免套用其它线路配置。
  run_case '非法目标分支停止' case_invalid_branch # 防止错误引用写入。
  run_case '多个覆盖值停止' case_multiple_override_values # 拒绝有歧义的配置。
  run_case '同一URL矛盾目标停止' case_conflicting_same_url # 避免重复推送不同目标。
  run_case '真实双端获取整合提交推送核验' case_real_renamed_merge_and_push # 合并双方历史后推同一HEAD。
  run_case '真实固定gitee目标且无额外本地分支' case_real_fixed_target # 保留两端异名映射。
  run_case '真实main覆盖不重建远端gitee' case_real_main_override # 保留账户仓主分支约定。
  run_case '已有显式upstream保持原线路' case_explicit_upstream_stays # 不用GitHub候选覆盖用户配置。
  run_case '第一线路拒绝后停止第二线路' case_push_rejection_stops_second_line # 验证失败传播。
  run_case '游离态复用已有main' case_detached_reuses_existing_branch # 不创建辅助分支。
  run_case '游离态缺失本地分支前置停止' case_detached_missing_local_stops # 不清理尚未授权内容。
  run_case 'OC独立快照门禁保持' case_snapshot_boundary # 避免合并独立历史。
  finish_tests # 汇总结果并清理本次隔离目录。
}

main "$@"
