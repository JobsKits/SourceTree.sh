#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】安装SourceTree自定义菜单1.command
# - 核心用途：先把 SourceTree.command 库发送到目标目录，再维护 Sourcetree 自定义菜单 actions.plist。
# - 影响范围：可能替换目标目录下的 SourceTree.command；选择同步方向时可能覆盖 Sourcetree 当前用户 actions.plist。
# - 运行提示：运行后会先打印内置自述；脚本包缺少 actions.plist 时会从 Sourcetree 默认路径自动回收。

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

# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
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

# BEGIN JOBS_FZF_SELF_HEAL
# Homebrew 条件准备，来源为本轮现行 Jobs 自维护实现。
jobs_brew_note() {
  jobs_prompt_output print -u2 -r -- "ℹ $*"
  if [[ "${_JOBS_ENV_LOG_READY:-0}" == 1 && -n "${LOG_FILE:-}" ]]; then
    print -r -- "ℹ $*" >> "$LOG_FILE"
  fi
  return 0
}
# 验证候选能够执行；共享安装只读不代表未安装。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 发现既有健康安装，不以目录可写性决定是否重新安装。
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
# 计算官方系统目录；实际支持范围和授权交由官方安装器处理。
jobs_brew_system_prefix() {
  case "$(/usr/bin/uname -m)" in
    arm64) print -r -- /opt/homebrew ;;
    *) print -r -- /usr/local ;;
  esac
}
# 缺失时强提示选择安装路径；YES 只表示选择系统目录，不验证密码或权限。
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
# 持续获取临时网络失败；只尝试已声明官方地址，确定错误和取消立即停止。
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
# 校验官方安装脚本后仅执行一次，下载失败与安装失败分别报告。
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
# 只终止本次获取或等待创建的子进程树，不碰其它 SDK 写者。
jobs_brew_stop_acquisition_tree() {
  local root="$1" child=""
  for child in $(/usr/bin/pgrep -P "$root" 2>/dev/null); do
    jobs_brew_stop_acquisition_tree "$child"
  done
  /bin/kill -TERM "$root" 2>/dev/null || true
  /bin/kill -KILL "$root" 2>/dev/null || true
}
# 在本轮私有暂存目录持续获取固定官方 tag，复用已收对象；不重放安装。
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
# 获取固定官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
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
# 只更新本模块的 shellenv 配置块，并保留配置文件的符号链接和权限。
jobs_brew_save_shellenv() {
  local profile_file="$HOME/.zprofile" profile_stage shellenv_line current_shell="${SHELL:-/bin/zsh}"
  [[ "${current_shell##*/}" != bash ]] || profile_file="$HOME/.bash_profile"
  shellenv_line='eval "$('"${(q)JOBS_HOMEBREW_BIN}"' shellenv)"'
  profile_stage="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-profile.XXXXXX")" || return 1
  if [[ -e "$profile_file" || -L "$profile_file" ]]; then
    awk '
      $0 == "# >>> Jobs Homebrew shellenv >>>" { inside = 1; block = $0 ORS; next }
      inside {
        block = block $0 ORS
        if ($0 == "# <<< Jobs Homebrew shellenv <<<") { inside = 0; block = "" }
        next
      }
      { print }
      END { if (inside) printf "%s", block }
    ' "$profile_file" > "$profile_stage" || { rm -- "$profile_stage"; return 1; }
  fi
  {
    print -r -- '# >>> Jobs Homebrew shellenv >>>'
    print -rl -- "$shellenv_line" '# <<< Jobs Homebrew shellenv <<<'
  } >> "$profile_stage"
  if ! cmp -s "$profile_stage" "$profile_file"; then
    cat "$profile_stage" > "$profile_file" || { rm -- "$profile_stage"; jobs_brew_note "无法写入用户配置：$profile_file"; return 1; }
  fi
  rm -- "$profile_stage"
}
# 激活当前进程并验证 Ruby 命令层；只有新安装才持久化 shellenv。
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
    jobs_brew_save_shellenv || return 1
  fi
}
# 用户取消保持信号退出码，其它安装失败沿用原入口失败状态。
jobs_brew_stop_failed_install() {
  case "$1" in
    129|130|143) exit "$1" ;;
    *) exit 1 ;;
  esac
}
# 在原版安装位置复用或安装 Homebrew，安装失败必须终止外层业务。
jobs_brew_install_or_exit() {
  local installed=""
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
    return 0
  fi
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
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
# 展示选择器诊断并将纯文本追加到当前日志。
jobs_fzf_note() {
  if (( ${+functions[jobs_prompt_output]} )); then
    jobs_prompt_output print -u2 -r -- "$*"
  else
    print -u2 -r -- "$*"
  fi
  if [[ -n "${LOG_FILE:-}" ]]; then print -r -- "$*" >> "$LOG_FILE"; fi
}
# 为外部健康探针限定等待，只清理本轮创建的探针与看门进程。
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
# 同时验证可执行路径、版本和当前菜单实际使用的原生选项。
jobs_fzf_probe() {
  local candidate="$1" probe='__JOBS_FZF_HEALTH__' output="" result=0
  [[ -n "$candidate" && -x "$candidate" && ! -d "$candidate" ]] || return 1
  jobs_fzf_bounded_probe /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE -u FZF_DEFAULT_COMMAND "$candidate" --version >/dev/null 2>&1 || return 1
  output="$(print -r -- "P"$'\t'"$probe" | jobs_fzf_bounded_probe /usr/bin/env -u FZF_DEFAULT_OPTS -u FZF_DEFAULT_OPTS_FILE -u FZF_DEFAULT_COMMAND \
    "$candidate" --filter="$probe" --delimiter=$'\t' --with-nth=2.. --no-multi --layout=reverse --height=60% --border \
      --bind='up:up,down:down,tab:down,shift-tab:up' --expect=left --header='↑/↓ 选择；回车确认；← 返回上一层；Esc / Ctrl+C 取消')" || result=$?
  (( result == 0 )) && [[ "${output##*$'\n'}" == P$'\t'"$probe" ]]
}
# 按已有来源查找健康选择器，保留用户已经选定的工具。
jobs_fzf_find() {
  local candidate=""
  local -a candidates=("${JOBS_FZF_BIN:-}" "${commands[fzf]:-}" "${JOBS_HOMEBREW_PREFIX:-/nonexistent}/bin/fzf" /opt/homebrew/bin/fzf /usr/local/bin/fzf "$HOME/.local/homebrew/bin/fzf" "$HOME/.homebrew/bin/fzf" "$HOME/.fzf/bin/fzf" "$HOME/.local/bin/fzf")
  for candidate in "${candidates[@]}"; do
    if jobs_fzf_probe "$candidate"; then JOBS_FZF_BIN="${candidate:A}"; return 0; fi
  done
  return 1
}
# 只补齐已确认流程的必要选择器，复检后在当前会话继续。
jobs_fzf_ensure() {
  local mode="${1:-required}" brew="" action=install result=0 attempt=0 delay=1 output_log="" prefix="" offset=0 log_result=0
  local -a command_status
  if [[ "$mode" != check ]] && { [[ ! -t 0 || ! -t 2 ]] || [[ "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; }; then
    print -u2 -r -- '✖ 选择器需要可交互终端；未安装依赖或执行后续业务。'
    return 1
  fi
  if jobs_fzf_find; then
    if [[ "$mode" != check ]]; then export PATH="${JOBS_FZF_BIN:h}:$PATH"; rehash; fi
    return 0
  fi
  [[ "$mode" != check ]] || { print -u2 -r -- '✖ fzf 路径、版本或菜单选项检查失败；只读模式未安装或修复。'; return 1; }
  jobs_fzf_note '➤ 本次键盘选择需要健康 fzf；仅在缺失或损坏时通过 Homebrew 准备，Ctrl+C 可取消。' || return $?
  jobs_brew_install_or_exit >&2 || return $?
  brew="${JOBS_HOMEBREW_BIN:-}"
  [[ -n "$brew" ]] || { jobs_fzf_note '✖ Homebrew 准备未返回可执行路径。'; return 1; }
  prefix="$("$brew" --prefix)" || return $?
  export PATH="$prefix/bin:$prefix/sbin:$PATH"
  rehash
  output_log="${LOG_FILE:-${TMPDIR:-/tmp}/JobsFzf.$$.log}"
  HOMEBREW_NO_AUTO_UPDATE=1 "$brew" list --versions fzf >/dev/null 2>&1 && action=reinstall
  while true; do
    (( attempt += 1 ))
    jobs_fzf_note "➤ 必需依赖 fzf｜来源：https://formulae.brew.sh/formula/fzf｜目标：$prefix｜$action，第 $attempt 次；网络失败持续重试，Ctrl+C 结束。" || return $?
    offset=0
    [[ ! -f "$output_log" ]] || offset="$(/usr/bin/wc -c < "$output_log")"
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 "$brew" "$action" fzf 2>&1 | jobs_prompt_tee "$output_log" >&2
    command_status=("${pipestatus[@]}")
    result=${command_status[1]}
    log_result=${command_status[2]}
    if (( log_result != 0 )); then print -u2 -r -- "✖ fzf 输出记录失败，退出码 $log_result；未继续重试或报告就绪。"; return "$log_result"; fi
    if (( result == 0 )); then
      rehash
      if jobs_fzf_find; then jobs_fzf_note "✔ fzf 已通过版本与菜单选项复检：$JOBS_FZF_BIN"; return 0; fi
      jobs_fzf_note '✖ 安装器返回成功，但 fzf 仍未通过实际选项复检；保留日志并停止，未进入业务。'
      return 1
    fi
    case "$result" in 129|130|137|143) return "$result" ;; esac
    if /usr/bin/tail -c +$((offset + 1)) "$output_log" | /usr/bin/tail -c 65536 | /usr/bin/grep -Eqi 'Permission denied|Operation not permitted|No space left|No available formula|No formulae found|File exists|unsupported|not supported|license.*(not accepted|rejected)|authentication failed|certificate.*(invalid|verify failed)'; then
      jobs_fzf_note "✖ 必需依赖遇到确定的本地、版本、认证或许可阻塞，退出码 $result；日志：$output_log"
      return "$result"
    fi
    jobs_fzf_note "⚠ fzf 获取失败，退出码 $result；${delay} 秒后继续同一流程。日志：$output_log" || return $?
    /bin/sleep "$delay" || return $?
    (( delay < 30 )) && delay=$(( delay * 2 > 30 ? 30 : delay * 2 ))
  done
}

# END JOBS_FZF_SELF_HEAL

jobs_intro_style_base() {
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
# 只处理已生成的人类展示文本，保留标题/正文原样式和管道失败状态。
jobs_intro_style() {
  setopt LOCAL_OPTIONS PIPE_FAIL
  jobs_intro_style_base "$@" | jobs_url_stream
}
SCRIPT_PATH="${0:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"
SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
SOURCE_PACKAGE_ROOT="${SCRIPT_DIR:h:h}"
SOURCE_PACKAGE_NAME="${SOURCE_PACKAGE_ROOT:t}"
INSTALL_DIR_NAME="${SCRIPT_DIR:t}"
LOG_DIR="${TMPDIR:-/tmp}"
LOG_DIR="${LOG_DIR%/}"
LOG_FILE="${LOG_DIR}/${SCRIPT_BASENAME}.log"

TARGET_SOURCETREE_DIR="${HOME}/Library/Application Support/SourceTree"
TARGET_ACTIONS_PLIST="${TARGET_SOURCETREE_DIR}/actions.plist"
LOCAL_ACTIONS_PLIST="${SCRIPT_DIR}/actions.plist"
HOME_PACKAGE_ROOT="${HOME}/${SOURCE_PACKAGE_NAME}"
DEPLOYED_PACKAGE_ROOT=""
DEPLOY_TARGET_PACKAGE=""
DEPLOY_STAGING_DIR=""
SOURCETREE_APP_NAME="Sourcetree"
SOURCETREE_PROCESS_NAME="Sourcetree"
ACTION_SYNC_PACKAGE_TO_SOURCETREE="将脚本包 actions.plist 同步到 Sourcetree 当前用户配置"
ACTION_SYNC_SOURCETREE_TO_PACKAGES="将 Sourcetree 当前用户配置同步回所有脚本包 actions.plist"
ACTION_SYNC_CANCEL="取消同步"
PLAIN_OUTPUT=0
RUNTIME_INITIALIZED=0
SOURCETREE_NEEDS_REOPEN=0

# 移除 ANSI 颜色码，避免 Sourcetree 输出窗口显示乱码。
strip_ansi_text() {
  perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}
# 配置当前输出模式，非完整终端或 Sourcetree 环境统一输出纯文本。
configure_output_mode() {
  [[ -n "${TERM:-}" ]] || export TERM="dumb"
  if env | grep -Eqi '^SOURCETREE|^SOURCE_TREE' || [[ ! -t 1 || "$TERM" == "dumb" || -n "${NO_COLOR+x}" || "${JOBS_PLAIN_OUTPUT:-0}" == "1" ]]; then
    PLAIN_OUTPUT=1
    export NO_COLOR="${NO_COLOR:-1}"
    export FORCE_COLOR=0
    export CLICOLOR="0"
    export ANSI_COLORS_DISABLED="1"
    export npm_config_color=false
  fi
}
# 输出日志并同步写入日志文件。
render_log_stream() {
  if [[ "$PLAIN_OUTPUT" == 1 ]]; then
    strip_ansi_text
  else
    cat
  fi
}
# 确认前只输出屏幕，初始化后同时保存日志。
log() {
  local message="$1"
  if [[ "$RUNTIME_INITIALIZED" == 1 ]]; then
    printf "%s\n" "$message" | render_log_stream | jobs_prompt_tee "$LOG_FILE"
  else
    printf "%s\n" "$message" | render_log_stream
  fi
}
# 仅转换固定颜色码，路径和工具输出始终按原文字面值记录。
color_log() {
  local color="$1" message="$2"
  if [[ "$PLAIN_OUTPUT" == 1 ]]; then
    log "$message"
  else
    log "$(printf '\033[%sm%s\033[0m' "$color" "$message")"
  fi
}
# 输出正常信息。
color_echo() {
  color_log "1;32" "$1"
}
# 输出提示信息。
info_echo() {
  color_log "1;34" "ℹ $1"
}
# 输出成功信息。
success_echo() {
  color_log "1;32" "✔ $1"
}
# 输出警告信息。
warn_echo() {
  color_log "1;33" "⚠ $1"
}
# 输出温馨提示信息。
warm_echo() {
  color_log "1;33" "$1"
}
# 输出说明信息。
note_echo() {
  color_log "1;35" "➤ $1"
}
# 输出错误信息。
error_echo() {
  color_log "1;31" "✖ $1"
}
# 输出错误信息。
err_echo() {
  color_log "1;31" "$1"
}
# 输出调试信息。
debug_echo() {
  color_log "1;35" "🐞 $1"
}
# 输出高亮信息。
highlight_echo() {
  color_log "1;36" "🔹 $1"
}
# 输出次要信息。
gray_echo() {
  color_log "0;90" "$1"
}
# 输出加粗信息。
bold_echo() {
  color_log "1" "$1"
}
# 输出下划线信息。
underline_echo() {
  color_log "4" "$1"
}
# 输出错误并立即终止脚本。
exit_with_error() {
  error_echo "$1"
  exit 1
}
# 打印脚本内置自述，并等待用户确认后再继续。
show_script_intro_and_wait() {
  configure_output_mode
  if [[ -z "${NO_COLOR+x}" && "$PLAIN_OUTPUT" != 1 && -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" ]]; then
    clear
  fi

  print -r -- "============================== 脚本内置自述 ==============================" | jobs_intro_style title
  print -r -- "脚本名称：${SCRIPT_BASENAME}.command" | jobs_intro_style title
  print -r -- "脚本路径：${SCRIPT_PATH}" | jobs_intro_style body
  print -r -- "第一阶段：发送 ${SOURCE_PACKAGE_NAME} 库到目标目录，默认目标父目录为当前用户家目录。" | jobs_intro_style body
  print -r -- "第二阶段：脚本包有 actions.plist 时通过 fzf 选择同步方向；没有时从 Sourcetree 默认路径自动回收。" | jobs_intro_style body
  print -r -- "影响范围：可能替换目标 ${SOURCE_PACKAGE_NAME} 目录；安装菜单时正常退出并重开 Sourcetree，合并 actions.plist。" | jobs_intro_style body
  print -r -- "安全策略：目标库已存在时直接回车保留并继续；输入 YES 才会备份替换；actions.plist 覆盖前自动备份。" | jobs_intro_style body | jobs_prompt_filter
  print -r -- "选择器：仅进入列表且 fzf 缺失或损坏时，经本次确认用 Homebrew 补齐；新装 Homebrew 选择系统或用户目录，并仅写自身 shellenv 配置块。" | jobs_intro_style body
  print -r -- "日志文件：${LOG_FILE}" | jobs_intro_style body
  print -r -- "取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。" | jobs_intro_style body
  print -r -- "============================================================================" | jobs_intro_style title
  echo "" | jobs_intro_style body

  if [[ ! -t 0 ]]; then
    print -u2 -r -- "当前没有可交互输入，请在终端中重新运行。"
    exit 1
  fi
  read -r "?$(jobs_prompt_render "👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：")" _ || exit 1
}
# 初始化 Shell 运行选项和日志文件。
initialize_script_runtime() {
  set -e
  set -o pipefail
  setopt NO_NOMATCH
  : > "$LOG_FILE"
  RUNTIME_INITIALIZED=1
  configure_output_mode
}
# 阻止 root 用户执行，避免把配置写入错误用户目录。
ensure_not_root_home() {
  if [[ "${HOME}" == "/var/root" || "${EUID}" -eq 0 ]]; then
    exit_with_error "请不要使用 sudo/root 执行本脚本。当前 HOME=${HOME}，会导致配置写入错误用户目录。"
  fi
}
# 检查发送 SourceTree.command 库需要的基础命令。
check_package_send_environment() {
  [[ -x /usr/bin/tar ]] || exit_with_error "未找到系统 tar，无法完整复制 ${SOURCE_PACKAGE_NAME}。"
  command -v git >/dev/null 2>&1 || exit_with_error "未找到 git，无法复制并校验 Git 元数据。"
}
# 检查 Sourcetree 自定义菜单同步需要的命令。
check_menu_environment() {
  command -v plutil >/dev/null 2>&1 || exit_with_error "未找到 plutil，无法校验 actions.plist。"
  command -v cmp >/dev/null 2>&1 || exit_with_error "未找到 cmp，无法比较文件。"
}
# 检查需要进入交互选择时的 fzf 依赖。
check_fzf_environment() {
  jobs_fzf_ensure || exit_with_error "fzf 尚未就绪，停止菜单同步。"
  printf '%s\n' cancel | FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= "$JOBS_FZF_BIN" --filter=cancel --sync --reverse --no-multi --bind=start:pos(1),up:up,down:down,tab:down,shift-tab:up >/dev/null || exit_with_error "fzf 不支持当前菜单选项，未覆盖菜单。"
}
# 去掉用户拖入路径时可能带上的外层引号和换行。
strip_outer_quotes() {
  local value="$1"
  value="${value%$'\n'}"
  value="${value%$'\r'}"
  if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
    value="${value[2,-2]}"
  fi
  print -r -- "$value"
}
# 展开用户输入路径里的当前用户家目录缩写。
expand_user_path() {
  local input_path="$1"
  if [[ "$input_path" == "~" ]]; then
    print -r -- "$HOME"
    return 0
  fi
  if [[ "$input_path" == "~/"* ]]; then
    print -r -- "${HOME}/${input_path#\~/}"
    return 0
  fi
  print -r -- "$input_path"
}
# 把存在的路径规整为物理绝对路径。
normalize_existing_path() {
  local input_path="$1"
  if [[ -d "$input_path" ]]; then
    cd -P "$input_path" && pwd
    return 0
  fi
  print -r -- "$input_path"
}
# 把待创建路径规整为便于比较的绝对路径。
normalize_target_path() {
  local input_path="$1" existing="$1" suffix=""
  [[ "$input_path" == /* ]] || existing="$PWD/$input_path"
  while [[ ! -e "$existing" && ! -L "$existing" && "$existing" != / ]]; do
    suffix="/${existing:t}${suffix}"
    existing="${existing:h}"
  done
  [[ -d "$existing" ]] || { print -r -- "$input_path"; return 1; }
  print -r -- "$(cd -P "$existing" && pwd)${suffix}"
}
# 判断数组里是否已经包含指定路径。
array_contains() {
  local needle="$1"
  shift || true
  local item=""
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}
# 根据用户输入生成最终 SourceTree.command 目标路径。
build_deploy_target_package_path() {
  local raw_input="$1"
  local cleaned_input=""
  local expanded_input=""
  local target_root=""

  cleaned_input="$(strip_outer_quotes "$raw_input")"
  if [[ -z "$cleaned_input" ]]; then
    target_root="$HOME"
  else
    target_root="$(expand_user_path "$cleaned_input")"
  fi
  target_root="${target_root%/}"

  if [[ "${target_root:t}" == "$SOURCE_PACKAGE_NAME" ]]; then
    print -r -- "$target_root"
  else
    print -r -- "${target_root}/${SOURCE_PACKAGE_NAME}"
  fi
}
# 询问用户要把 SourceTree.command 库发送到哪里。
ask_deploy_target_package() {
  local input_path=""
  echo ""
  note_echo "发送 ${SOURCE_PACKAGE_NAME} 库前，请确认目标目录。"
  jobs_prompt_output --question gray_echo "直接回车：发送到当前用户家目录下的 ${SOURCE_PACKAGE_NAME}。"
  gray_echo "手动输入 / 拖入：可指定其它父目录；如果直接输入 ${SOURCE_PACKAGE_NAME} 路径，则按该路径处理。"
  read -r "?$(jobs_prompt_render "👉 请输入或拖入目标目录（直接回车使用 ${HOME}）：")" input_path

  DEPLOY_TARGET_PACKAGE="$(build_deploy_target_package_path "$input_path")"
  DEPLOY_TARGET_PACKAGE="$(normalize_target_path "$DEPLOY_TARGET_PACKAGE")"
  DEPLOYED_PACKAGE_ROOT="$DEPLOY_TARGET_PACKAGE"
}
# 确认目标路径不会落在源库内部，避免递归复制。
ensure_deploy_target_is_safe() {
  local source_abs=""
  local target_abs=""

  [[ ! -L "$DEPLOY_TARGET_PACKAGE" ]] || exit_with_error "目标库是符号链接，停止替换：$DEPLOY_TARGET_PACKAGE"
  source_abs="$(normalize_existing_path "$SOURCE_PACKAGE_ROOT")"
  target_abs="$(normalize_target_path "$DEPLOY_TARGET_PACKAGE")"

  if [[ "$target_abs" == "$source_abs" ]]; then
    warn_echo "源库和目标库是同一路径，跳过发送：${target_abs}"
    return 1
  fi
  if [[ "$target_abs" == "${source_abs}/"* ]]; then
    exit_with_error "目标路径不能放在源库内部，避免递归复制：${target_abs}"
  fi
  return 0
}
# 要求用户确认替换已有目标库。
confirm_replace_existing_package() {
  local input=""

  if [[ ! -e "$DEPLOY_TARGET_PACKAGE" ]]; then
    return 0
  fi

  echo ""
  warn_echo "目标库已存在：${DEPLOY_TARGET_PACKAGE}"
  jobs_prompt_output --question gray_echo "直接回车：保留现有 ${SOURCE_PACKAGE_NAME}，继续进入 Sourcetree 自定义菜单安装流程。"
  jobs_prompt_output --question gray_echo "输入 YES 后回车：备份旧目标库，再写入新的 ${SOURCE_PACKAGE_NAME}，随后继续安装流程。"
  IFS= read -r "input?$(jobs_prompt_render "👉 直接回车继续；输入 YES 备份替换后继续：")"
  if [[ "$input" == "YES" ]]; then
    return 0
  fi

  [[ -n "$input" ]] && warn_echo "输入不是 YES，本次保留现有 ${SOURCE_PACKAGE_NAME} 并继续。"
  return 1
}
# 保留文件与目录元数据，原生 tar 按类型跳过不可归档的运行时 socket。
copy_tree_without_runtime_sockets() {
  setopt LOCAL_OPTIONS PIPE_FAIL
  local source_dir="$1" target_dir="$2"
  mkdir -p "$target_dir" || return 1
  /usr/bin/tar -C "$source_dir" -cpf - . 2> >(tee -a "$LOG_FILE" >&2) |
    /usr/bin/tar -C "$target_dir" -xpf - 2> >(tee -a "$LOG_FILE" >&2)
}
# 复制源库工作树到临时目录。
copy_source_worktree_to_temp() {
  local temp_package="$1"
  note_echo "发送 ${SOURCE_PACKAGE_NAME} 工作树。"
  gray_echo "本地来源：${SOURCE_PACKAGE_ROOT}"
  gray_echo "暂存目标：${temp_package}"
  gray_echo "运行时 socket 不复制，跳过对象由系统 tar 显示并写入日志；普通文件与权限保留。"
  copy_tree_without_runtime_sockets "$SOURCE_PACKAGE_ROOT" "$temp_package" || exit_with_error "复制工作树失败：${SOURCE_PACKAGE_ROOT} -> ${temp_package}；详见日志 ${LOG_FILE}"
}
# 直接修改暂存配置文件，避免 Git 先进入复制后已失效的旧工作树。
clear_copied_git_worktree_config() {
  local temp_package="$1" config_file="" unset_result=0
  for config_file in "${temp_package}/.git/config" "${temp_package}/.git/config.worktree"; do
    [[ -e "$config_file" || -L "$config_file" ]] || continue
    [[ -f "$config_file" && ! -L "$config_file" ]] || exit_with_error "暂存 Git 配置不是独立普通文件，停止修改：${config_file}"
    unset_result=0
    git config --file "$config_file" --unset-all core.worktree >>"$LOG_FILE" 2>&1 || unset_result=$?
    if [[ "$unset_result" != 0 && "$unset_result" != 5 ]]; then
      exit_with_error "清理暂存 Git 工作树配置失败（退出码 ${unset_result}）：${config_file}；详见日志 ${LOG_FILE}"
    fi
  done
}
# 校验失败时同时记录 Git 原始诊断和业务错误，正常输出不刷屏。
validate_deploy_git_command() {
  local temp_package="$1" failure_message="$2" diagnostic="" git_result=0
  shift 2
  diagnostic="$(GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -C "$temp_package" "$@" 2>&1)" || git_result=$?
  if [[ "$git_result" != 0 ]]; then
    [[ -z "$diagnostic" ]] || error_echo "$diagnostic"
    exit_with_error "${failure_message}（Git 退出码 ${git_result}）：${temp_package}"
  fi
}
# 把子 Git 的真实 Git 目录复制成目标库里的独立 .git。
copy_git_metadata_to_temp() {
  local temp_package="$1"
  local source_git_dir=""
  local copied_worktree=""

  source_git_dir="$(git -C "$SOURCE_PACKAGE_ROOT" rev-parse --absolute-git-dir 2>/dev/null || true)"
  if [[ -z "$source_git_dir" || ! -d "$source_git_dir" ]]; then
    warn_echo "源库没有可复制的 Git 元数据，本次只发送工作树：${SOURCE_PACKAGE_ROOT}"
    return 0
  fi

  local source_common_dir="$(git -C "$SOURCE_PACKAGE_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [[ "$source_common_dir" == "$source_git_dir" ]] || exit_with_error "源库是共享 Git 对象的 linked worktree，不能只复制私有 gitdir；请独立克隆后再部署。"
  [[ ! -s "$source_common_dir/objects/info/alternates" && -z "${GIT_ALTERNATE_OBJECT_DIRECTORIES:-}" ]] || exit_with_error "源库借用了外部 Git 对象，不能作为独立副本发送；请先建立完整独立克隆。"
  gray_echo "Git 元数据来源：${source_git_dir}"
  gray_echo "Git 元数据目标：${temp_package}/.git"
  rm -rf "${temp_package}/.git"
  gray_echo "Git 运行时 socket 不复制；源文件、监控器与配置保持原状。"
  copy_tree_without_runtime_sockets "$source_git_dir" "${temp_package}/.git" || exit_with_error "复制 Git 元数据失败：${source_git_dir}；详见日志 ${LOG_FILE}"
  clear_copied_git_worktree_config "$temp_package"
  if ! copied_worktree="$(git -C "$temp_package" rev-parse --show-toplevel 2>&1)"; then
    error_echo "$copied_worktree"
    exit_with_error "目标临时库 Git 元数据校验失败：${temp_package}"
  fi
  [[ "$copied_worktree" == "${temp_package:A}" ]] || exit_with_error "目标临时库仍绑定其它工作树：${copied_worktree}；预期 ${temp_package:A}"
  if git -C "$temp_package" rev-parse --verify HEAD >/dev/null 2>&1; then
    validate_deploy_git_command "$temp_package" "目标临时库缺少 HEAD 对象，停止替换" cat-file -e 'HEAD^{commit}'
  else
    validate_deploy_git_command "$temp_package" "目标临时库 HEAD 无效，停止替换" symbolic-ref -q HEAD
  fi
  validate_deploy_git_command "$temp_package" "目标临时库 Git 状态校验失败，停止替换" status --porcelain
  success_echo "已把 Git 元数据复制为目标库独立 .git。"
}
# 用临时目录替换最终目标库，并为旧目标生成备份。
replace_target_package_with_temp() {
  local temp_package="$1"
  local target_parent="${DEPLOY_TARGET_PACKAGE:h}"
  local backup_package=""

  mkdir -p "$target_parent" || exit_with_error "创建目标父目录失败：${target_parent}"
  if [[ -e "$DEPLOY_TARGET_PACKAGE" ]]; then
    backup_package="${DEPLOY_TARGET_PACKAGE}.bak.$(date '+%Y%m%d_%H%M%S').$$"
    mv "$DEPLOY_TARGET_PACKAGE" "$backup_package" || exit_with_error "备份旧目标库失败：${DEPLOY_TARGET_PACKAGE}"
    success_echo "已备份旧目标库：${backup_package}"
  fi

  if ! mv "$temp_package" "$DEPLOY_TARGET_PACKAGE"; then
    if [[ -n "$backup_package" && -e "$backup_package" && ! -e "$DEPLOY_TARGET_PACKAGE" ]]; then
      mv "$backup_package" "$DEPLOY_TARGET_PACKAGE" || true
    fi
    exit_with_error "写入目标库失败：${DEPLOY_TARGET_PACKAGE}"
  fi
}
# 只清理本次 mktemp 产生且尚未移入目标的部署暂存目录。
cleanup_deploy_staging() {
  [[ -n "$DEPLOY_STAGING_DIR" && -d "$DEPLOY_STAGING_DIR" &&
     "${DEPLOY_STAGING_DIR:h}" == "${DEPLOY_TARGET_PACKAGE:h}" &&
     "${DEPLOY_STAGING_DIR:t}" == .${SOURCE_PACKAGE_NAME}.tmp.* ]] || return 0
  rm -rf -- "$DEPLOY_STAGING_DIR"
}
# 发送 SourceTree.command 库到用户指定目录。
send_package_to_user_directory() {
  local target_parent=""
  local temp_package=""

  ask_deploy_target_package
  ensure_deploy_target_is_safe || return 0
  if ! confirm_replace_existing_package; then
    info_echo "已保留现有 ${SOURCE_PACKAGE_NAME}，继续进入 Sourcetree 自定义菜单安装流程。"
    return 0
  fi

  target_parent="${DEPLOY_TARGET_PACKAGE:h}"
  mkdir -p "$target_parent" || exit_with_error "创建目标父目录失败：${target_parent}"
  temp_package="$(mktemp -d "${target_parent}/.${SOURCE_PACKAGE_NAME}.tmp.XXXXXX")" || exit_with_error "创建临时部署目录失败。"
  DEPLOY_STAGING_DIR="$temp_package"
  trap cleanup_deploy_staging EXIT
  copy_source_worktree_to_temp "$temp_package"
  copy_git_metadata_to_temp "$temp_package"
  replace_target_package_with_temp "$temp_package"
  success_echo "已发送 ${SOURCE_PACKAGE_NAME} 到：${DEPLOY_TARGET_PACKAGE}"
}
# 提示用户库发送步骤已经结束，接下来进入菜单安装。
announce_menu_install_phase() {
  echo ""
  highlight_echo "============================== 安装 SourceTree 自定义菜单 =============================="
  note_echo "${SOURCE_PACKAGE_NAME} 发送步骤已结束，下面开始处理 Sourcetree actions.plist。"
  highlight_echo "====================================================================================="
}
# 校验 actions.plist 是否存在且格式合法。
validate_plist() {
  local plist_path="$1"
  [[ -f "$plist_path" ]] || exit_with_error "未找到 actions.plist：${plist_path}"
  plutil -lint "$plist_path" >/dev/null || exit_with_error "actions.plist 格式校验失败：${plist_path}"
}
# 校验当前脚本包里的 actions.plist。
validate_local_actions_plist() {
  validate_plist "$LOCAL_ACTIONS_PLIST"
}
# 对目标文件生成覆盖前备份。
backup_file_if_exists() {
  local file_path="$1"
  [[ -f "$file_path" ]] || return 0
  local backup_file="${file_path}.bak.$(date '+%Y%m%d_%H%M%S').$$"
  cp -p "$file_path" "$backup_file" || exit_with_error "备份失败：${file_path}"
  success_echo "已备份：${backup_file}"
}
# 复制 actions.plist 到目标位置，覆盖前自动备份。
copy_file_with_backup() {
  local source_file="$1"
  local target_file="$2"
  validate_plist "$source_file"
  mkdir -p "$(dirname "$target_file")" || exit_with_error "创建目录失败：$(dirname "$target_file")"

  if [[ -f "$target_file" ]] && cmp -s "$source_file" "$target_file"; then
    success_echo "源文件与目标文件一致，无需覆盖。"
    gray_echo "源文件：${source_file}"
    gray_echo "目标文件：${target_file}"
    return 0
  fi

  backup_file_if_exists "$target_file"
  cp -p "$source_file" "$target_file" || exit_with_error "复制失败：${source_file} -> ${target_file}"
  validate_plist "$target_file"
  success_echo "已同步 actions.plist"
  gray_echo "源文件：${source_file}"
  gray_echo "目标文件：${target_file}"
  return 0
}
# 输出所有可同步的等位脚本包目录。
peer_install_dirs() {
  local -a package_roots
  local -a printed_dirs
  local package_root=""
  local install_dir=""

  package_roots=("$HOME_PACKAGE_ROOT" "$SOURCE_PACKAGE_ROOT" "$HOME/Documents/Github/JobsGenesis/SourceTree.command")
  if [[ -n "$DEPLOYED_PACKAGE_ROOT" ]]; then
    package_roots+=("$DEPLOYED_PACKAGE_ROOT")
  fi

  printed_dirs=()
  for package_root in "${package_roots[@]}"; do
    install_dir="${package_root}/MacOS/${INSTALL_DIR_NAME}"
    [[ -d "$install_dir" ]] || continue
    if ! array_contains "$install_dir" "${printed_dirs[@]}"; then
      print -r -- "$install_dir"
      printed_dirs+=("$install_dir")
    fi
  done
}
# 把当前脚本包 actions.plist 同步到其它等位脚本包。
sync_local_to_peer_packages() {
  local peer_dir=""
  local peer_plist=""

  while IFS= read -r peer_dir; do
    [[ -n "$peer_dir" && -d "$peer_dir" ]] || continue
    [[ "$peer_dir" == "$SCRIPT_DIR" ]] && continue
    peer_plist="${peer_dir}/actions.plist"
    info_echo "同步当前 actions.plist 到等位脚本包：${peer_plist}"
    copy_file_with_backup "$LOCAL_ACTIONS_PLIST" "$peer_plist"
  done < <(peer_install_dirs)
}
# 把 Sourcetree 当前 actions.plist 同步回所有等位脚本包。
sync_sourcetree_to_peer_packages() {
  local peer_dir=""
  local peer_plist=""

  while IFS= read -r peer_dir; do
    [[ -n "$peer_dir" && -d "$peer_dir" ]] || continue
    peer_plist="${peer_dir}/actions.plist"
    info_echo "同步 Sourcetree 当前配置到脚本包：${peer_plist}"
    copy_file_with_backup "$TARGET_ACTIONS_PLIST" "$peer_plist"
  done < <(peer_install_dirs)
}
# 输出当前参与同步的脚本包 actions.plist 路径。
log_peer_actions_plist_paths() {
  local peer_dir=""

  while IFS= read -r peer_dir; do
    [[ -n "$peer_dir" && -d "$peer_dir" ]] || continue
    gray_echo "脚本包 actions.plist：${peer_dir}/actions.plist"
  done < <(peer_install_dirs)
}
# 输出 Sourcetree 自定义菜单同步结果。
finish_sourcetree_menu_sync() {
  success_echo "SourceTree 自定义菜单同步完成。"
  log_peer_actions_plist_paths
  gray_echo "Sourcetree actions.plist：${TARGET_ACTIONS_PLIST}"
  gray_echo "日志文件：${LOG_FILE}"
}
# 查找 Sourcetree 应用路径。
detect_sourcetree_app_path() {
  local app_path=""
  for app_path in "/Applications/Sourcetree.app" "/Applications/SourceTree.app"; do
    if [[ -d "$app_path" ]]; then
      printf "%s" "$app_path"
      return 0
    fi
  done
  return 1
}
# 判断指定应用进程是否正在运行。
is_app_running() {
  local process_name="$1"
  pgrep -x "$process_name" >/dev/null 2>&1
}
# 如果 Sourcetree 正在运行，则重启以加载新的 actions.plist。
restart_sourcetree_if_needed() {
  [[ "$SOURCETREE_NEEDS_REOPEN" == 1 ]] || return 0
  local app_path="$(detect_sourcetree_app_path 2>/dev/null || true)" elapsed=0
  if [[ -n "$app_path" ]]; then
    open "$app_path" || exit_with_error "配置已安装，但 Sourcetree 无法重新打开。"
  else
    open -a "$SOURCETREE_APP_NAME" || exit_with_error "配置已安装，但 Sourcetree 无法重新打开。"
  fi
  while (( elapsed < 10 )); do
    if is_app_running "$SOURCETREE_PROCESS_NAME" || is_app_running SourceTree; then
      success_echo "Sourcetree 已重载。"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  exit_with_error "配置已安装，未能确认 Sourcetree 重新运行。"
}
# 使用 fzf 选择 actions.plist 同步方向。
select_sync_action() {
  local choice=""
  check_fzf_environment
  choice="$(printf "%s\n%s\n%s\n" \
    "$ACTION_SYNC_CANCEL" \
    "$ACTION_SYNC_PACKAGE_TO_SOURCETREE" \
    "$ACTION_SYNC_SOURCETREE_TO_PACKAGES" \
    | FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= "$JOBS_FZF_BIN" --sync --bind=start:pos(1),up:up,down:down,tab:down,shift-tab:up --prompt="SourceTree actions.plist 同步方向 > " --height=40% --border --reverse --no-multi)" || true

  [[ -n "$choice" ]] || choice="$ACTION_SYNC_CANCEL"
  print -r -- "$choice"
}
# 写入前正常退出 Sourcetree，避免退出落盘覆盖新配置，不强制终止。
pause_sourcetree_before_menu_sync() {
  local elapsed=0
  if ! is_app_running "$SOURCETREE_PROCESS_NAME" && ! is_app_running SourceTree; then
    return 0
  fi
  osascript -e 'tell application "Sourcetree" to quit' >/dev/null 2>&1 || exit_with_error "Sourcetree 拒绝正常退出，尚未覆盖配置。"
  while (( elapsed < 10 )); do
    if ! is_app_running "$SOURCETREE_PROCESS_NAME" && ! is_app_running SourceTree; then
      SOURCETREE_NEEDS_REOPEN=1
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  exit_with_error "Sourcetree 尚未退出，可能等待操作完成；不会强杀或覆盖配置。"
}
# 合并按脚本路径匹配的动作，补齐登记动作并保留当前自定义标题。
merge_actions_preserving_titles() {
  local merged_file="$1" runtime_root="$HOME_PACKAGE_ROOT"
  [[ -z "$DEPLOYED_PACKAGE_ROOT" || ! -d "$DEPLOYED_PACKAGE_ROOT" ]] || runtime_root="$DEPLOYED_PACKAGE_ROOT"
  osascript -l JavaScript - "$LOCAL_ACTIONS_PLIST" "$TARGET_ACTIONS_PLIST" "$merged_file" "$runtime_root" <<'JAVASCRIPT' || exit_with_error "菜单归档合并失败，未覆盖当前配置。"
ObjC.import('Foundation');
function run(argv) {
  function readArchive(path) {
    var data = $.NSData.dataWithContentsOfFile(path);
    if (!data || data.isNil()) throw new Error('Cannot read archive: ' + path);
    var items = ObjC.deepUnwrap($.NSKeyedUnarchiver.unarchiveObjectWithData(data));
    if (!Array.isArray(items)) throw new Error('Expected actions array');
    return items;
  }
  function canonical(target) {
    var name = target.split('/').pop();
    if (name === '【MacOS@SourceTree】Pod_Install.command') name = '【MacOS@SourceTree】🫘打开终端运行Pod Install.command';
    return target.indexOf('/SourceTree.command/') >= 0 ? argv[3] + '/MacOS/' + name + '/' + name : target;
  }
  // 这两个入口只供独立运行；同时过滤旧模板与当前菜单，避免作为额外动作重新加入。
  function isMenuAction(item) {
    var name = item.target.split('/').pop();
    return name !== '【MacOS@SourceTree】⏬双击下载SourceTree效率脚本.command' &&
      name !== '【MacOS@SourceTree】⚙️运行授权.command';
  }
  var templates = readArchive(argv[0]).filter(isMenuAction);
  var current = $.NSFileManager.defaultManager.fileExistsAtPath(argv[1]) ? readArchive(argv[1]).filter(isMenuAction) : [];
  var pullScriptName = '【MacOS@SourceTree】⏬只拉取远程代码.command';
  var pullScriptPath = argv[3] + '/MacOS/' + pullScriptName + '/' + pullScriptName;
  var pullDefault = { target: pullScriptPath, params: '$REPO', name: '⏬只拉取远程代码（终端）', repoAction: true, fileAction: false, separateWindow: false, showFullOutput: false, logAction: false, shortcutKeyCode: -1, shortcutKeyModifiers: 0, shortcutKeyDisplay: '' };
  if (!templates.some(function(item) { return canonical(item.target) === pullScriptPath; })) templates.push(pullDefault);
  var ohosScriptName = '【MacOS@SourceTree】📦双击打包Flutter.ohos.command';
  var ohosScriptPath = argv[3] + '/MacOS/' + ohosScriptName + '/' + ohosScriptName;
  var ohosDefault = { target: ohosScriptPath, params: '$REPO --target all --mode release', name: '📦打包生成HAP+APP文件（Flutter.ohos）', repoAction: true, fileAction: false, separateWindow: true, showFullOutput: true, logAction: false, shortcutKeyCode: -1, shortcutKeyModifiers: 0, shortcutKeyDisplay: '' };
  if (!templates.some(function(item) { return canonical(item.target) === ohosScriptPath; })) templates.push(ohosDefault);
  templates.forEach(function(item) {
    if (canonical(item.target) === ohosScriptPath) {
      item.params = ohosDefault.params;
      if (item.name === '📦双击打包Flutter.ohos') item.name = ohosDefault.name;
    }
  });
  var remoteOpenScriptName = '【MacOS@SourceTree】🌍打开远程仓库地址.command';
  var remoteOpenScriptPath = argv[3] + '/MacOS/' + remoteOpenScriptName + '/' + remoteOpenScriptName;
  var remoteOpenDefault = { target: remoteOpenScriptPath, params: '$REPO', name: '🌍打开远程仓库地址', repoAction: true, fileAction: false, separateWindow: false, showFullOutput: true, logAction: false, shortcutKeyCode: -1, shortcutKeyModifiers: 0, shortcutKeyDisplay: '' };
  if (!templates.some(function(item) { return canonical(item.target) === remoteOpenScriptPath; })) templates.push(remoteOpenDefault);
  var pushRepairScriptName = '【MacOS@SourceTree】📥修复Git无法Push.command';
  var pushRepairScriptPath = argv[3] + '/MacOS/' + pushRepairScriptName + '/' + pushRepairScriptName;
  var pushRepairDefault = { target: pushRepairScriptPath, params: '$REPO', name: '📥修复Git无法Push（终端）', repoAction: true, fileAction: false, separateWindow: false, showFullOutput: true, logAction: false, shortcutKeyCode: -1, shortcutKeyModifiers: 0, shortcutKeyDisplay: '' };
  if (!templates.some(function(item) { return canonical(item.target) === pushRepairScriptPath; })) templates.push(pushRepairDefault);
  var updates = {}, seen = {}, result = [];
  templates.forEach(function(item) {
    item.target = canonical(item.target);
    if (updates[item.target]) throw new Error('Duplicate template target: ' + item.target);
    if (!$.NSFileManager.defaultManager.isExecutableFileAtPath(item.target)) throw new Error('Missing or non-executable managed action: ' + item.target);
    updates[item.target] = item;
  });
  current.forEach(function(item) {
    var key = canonical(item.target), update = updates[key];
    if (seen[key]) throw new Error('Duplicate action target: ' + key);
    seen[key] = true;
    if (update) {
      var merged = Object.assign({}, update, item);
      merged.target = key;
      merged.params = update.params;
      merged.repoAction = update.repoAction;
      merged.fileAction = update.fileAction;
      if (key === ohosScriptPath && merged.name === '📦双击打包Flutter.ohos') merged.name = ohosDefault.name;
      result.push(merged);
    } else result.push(item);
  });
  templates.forEach(function(item) { if (!seen[item.target]) { seen[item.target] = true; result.push(item); } });
  // 体检标题去掉末尾句点，缺少开头 emoji 时补图标；保留其它正文与已有图标。
  var emojiPattern = '^(?:[\\p{Extended_Pictographic}\\p{Regional_Indicator}]|[0-9#*]\\x{FE0F}?\\x{20E3})';
  var emojiPrefix = $.NSRegularExpression.regularExpressionWithPatternOptionsError(emojiPattern, 0, null);
  if (!emojiPrefix || emojiPrefix.isNil()) throw new Error('Cannot validate menu emoji prefixes');
  result.forEach(function(item) {
    var scriptName = item.target.split('/').pop();
    if (scriptName === '【MacOS@SourceTree】🐦Flutter项目体检.command') item.name = String(item.name || '').replace(/\.+$/, '');
    var title = String(item.name || '');
    if (Number(emojiPrefix.numberOfMatchesInStringOptionsRange(title, 0, $.NSMakeRange(0, $(title).length))) > 0) return;
    var icon = scriptName.indexOf('】用Android Studio打开') >= 0 ? '🤖' :
      /】用(?:Trae|Trea)打开/.test(scriptName) ? '🧠' :
      scriptName.indexOf('】用VSCode打开') >= 0 ? '💻' : '🔧';
    item.name = icon + title;
  });
  // 用稳定脚本名归类，不依赖用户修改过的显示标题；额外动作保持相对顺序置于末尾。
  var menuScriptOrder = [
    // 打开：文档、IDE、终端、项目与远程网页。
    '【MacOS@SourceTree】📘用Typora打开蓝皮书.command',
    '【MacOS@SourceTree】（递归目录寻找工程@不适用于多工程项目）用Xcode打开.command',
    '【MacOS@SourceTree】（只打开当前目录）用Xcode打开.command',
    '【MacOS@SourceTree】用Android Studio打开.command',
    '【MacOS@SourceTree】用Android Studio打开openjdk64-17.0.16.command',
    '【MacOS@SourceTree】用Trea打开.command',
    '【MacOS@SourceTree】用Trae打开@openjdk64-17.0.16.command',
    '【MacOS@SourceTree】用VSCode打开.command',
    '【MacOS@SourceTree】用VSCode打开@openjdk64-17.0.16.command',
    '【MacOS@SourceTree】用终端打开.command',
    '【MacOS@SourceTree】🐦打开：运行Flutter项目.command',
    '【MacOS@SourceTree】🌍打开远程仓库地址.command',
    // Git 与地址：获取、拉取、推送、回退。
    '【MacOS@SourceTree】🌐获取远程仓库地址.command',
    '【MacOS@SourceTree】获取目标绝对地址.command',
    '【MacOS@SourceTree】⏬只拉取远程代码.command',
    '【MacOS@SourceTree】🚀逐层空白提交并Push.command',
    '【MacOS@SourceTree】♻️双击Git（识别子Git） 提交回退.command',
    // 修复：Git 与 Flutter 的修复入口连续排列。
    '【MacOS@SourceTree】📥修复Git无法Commit.command',
    '【MacOS@SourceTree】📥修复Git无法Fetch.command',
    '【MacOS@SourceTree】📥修复Git无法Push.command',
    '【MacOS@SourceTree】♻️修复Flutter项目中文路径.command',
    // Flutter 工程维护。
    '【MacOS@SourceTree】🐦Flutter项目体检.command',
    '【MacOS@SourceTree】⚙️收集当前Flutter工程的依赖.command',
    '【MacOS@SourceTree】🐦Flutter重新拉取第三方依赖.command',
    '【MacOS@SourceTree】🐦Flutter自动化生产代码.command',
    // CocoaPods 依赖。
    '【MacOS@SourceTree】🫘打开终端运行Pod Install.command',
    '【MacOS@SourceTree】🫘在Sourcetree中运行Pod Install.command',
    // 打包：Flutter Android / iOS / 鸿蒙相邻，随后是原生 iOS。
    '【MacOS@SourceTree】📦双击打包Flutter.android.command',
    '【MacOS@SourceTree】📦双击打包Flutter.iOS.command',
    '【MacOS@SourceTree】📦双击打包Flutter.ohos.command',
    '【MacOS@SourceTree】📦双击自动生成ipa文件.command',
    // 通用工具与专用项目。
    '【MacOS@SourceTree】同步edgetunnel代码后手动升级.command',
    '【MacOS@SourceTree】🪄配置并运行Magic Resume.command'
  ];
  var ranks = {};
  menuScriptOrder.forEach(function(name, index) { ranks[argv[3] + '/MacOS/' + name + '/' + name] = index; });
  result = result.map(function(item, index) {
    var rank = updates[item.target] && Object.prototype.hasOwnProperty.call(ranks, item.target) ? ranks[item.target] : menuScriptOrder.length;
    return { item: item, rank: rank, index: index };
  }).sort(function(a, b) { return a.rank - b.rank || a.index - b.index; }).map(function(entry) { return entry.item; });
  var data = $.NSKeyedArchiver.archivedDataWithRootObject($(result));
  if (!data.writeToFileAtomically(argv[2], true)) throw new Error('Cannot save merged archive');
}
JAVASCRIPT
  validate_plist "$merged_file"
}
# 把当前脚本包 actions.plist 安装到 Sourcetree 当前用户配置。
sync_current_actions_to_sourcetree() {
  local merged_file=""
  info_echo "按稳定脚本路径合并菜单，保留当前用户标题及额外动作。"
  validate_plist "$LOCAL_ACTIONS_PLIST"
  pause_sourcetree_before_menu_sync
  merged_file="$(mktemp "${TMPDIR:-/tmp}/sourcetree-actions.XXXXXX")" || exit_with_error "无法创建菜单临时文件。"
  merge_actions_preserving_titles "$merged_file"
  copy_file_with_backup "$merged_file" "$TARGET_ACTIONS_PLIST"
  rm -f "$merged_file"
  sync_sourcetree_to_peer_packages
  restart_sourcetree_if_needed
}
# 把 Sourcetree 当前用户配置同步回所有脚本包。
sync_sourcetree_actions_to_current() {
  info_echo "准备将 Sourcetree 当前配置同步回所有脚本包 actions.plist。"
  validate_plist "$TARGET_ACTIONS_PLIST"
  sync_sourcetree_to_peer_packages
}
# 本地缺少 actions.plist 时，从 Sourcetree 默认路径自动回收到脚本包。
sync_missing_local_actions_from_sourcetree() {
  [[ ! -f "$LOCAL_ACTIONS_PLIST" ]] || return 1

  warn_echo "当前脚本包未找到 actions.plist，跳过 fzf 选择。"
  info_echo "准备从 Sourcetree 默认配置备份到脚本包 actions.plist。"
  validate_plist "$TARGET_ACTIONS_PLIST"
  sync_sourcetree_to_peer_packages
  finish_sourcetree_menu_sync
  return 0
}
# 执行 Sourcetree 自定义菜单安装和回收流程。
run_sourcetree_menu_install_flow() {
  local choice=""

  sync_missing_local_actions_from_sourcetree && return 0
  validate_local_actions_plist
  choice="$(select_sync_action)"
  case "$choice" in
    "$ACTION_SYNC_PACKAGE_TO_SOURCETREE")
      sync_current_actions_to_sourcetree
      ;;
    "$ACTION_SYNC_SOURCETREE_TO_PACKAGES")
      sync_sourcetree_actions_to_current
      ;;
    "$ACTION_SYNC_CANCEL")
      info_echo "已选择取消同步，本次不覆盖任何 actions.plist。"
      log_peer_actions_plist_paths
      gray_echo "Sourcetree actions.plist：${TARGET_ACTIONS_PLIST}"
      gray_echo "日志文件：${LOG_FILE}"
      return 0
      ;;
    *)
      exit_with_error "未知选项：${choice}"
      ;;
  esac

  finish_sourcetree_menu_sync
}
# 编排脚本说明、库发送和 Sourcetree 菜单安装流程。
main() {
  show_script_intro_and_wait # 展示脚本内置自述，并等待用户确认整体影响范围。
  initialize_script_runtime # 初始化 Shell 选项和日志文件，后续失败及时中断。
  ensure_not_root_home # 阻止 sudo/root 写入错误用户目录。
  check_package_send_environment # 检查发送 SourceTree.command 库所需命令。
  send_package_to_user_directory # 先把 SourceTree.command 库发送到目标目录。
  announce_menu_install_phase # 明确库发送阶段结束，准备安装 SourceTree 自定义菜单。
  check_menu_environment # 检查 plutil 和 cmp 等菜单同步基础依赖。
  run_sourcetree_menu_install_flow "$@" # 按本地 actions.plist 状态同步 Sourcetree 自定义菜单。
}

main "$@"
