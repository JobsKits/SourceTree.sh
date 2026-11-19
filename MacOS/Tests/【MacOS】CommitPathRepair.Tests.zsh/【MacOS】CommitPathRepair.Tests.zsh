#!/bin/zsh
# 脚本自述：
# - 脚本名称：CommitPathRepair.Tests.zsh
# - 核心用途：在隔离 Git 仓库内验证 Commit 旧路径修复及索引保护边界。
# - 影响范围：仅本次临时夹具；不访问真实业务仓库或网络，不改变用户 Git 配置。
# - 运行提示：终端先回车确认；--run 明确启动自动回归，结束保留夹具和日志。

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

TEST_PATH="${(%):-%x}"
SUBJECT=""
TEST_ROOT=""
CASE_DIR=""
REPOSITORY=""
CAPTURE=""
RESULT_CODE=0
CASE_INDEX=0
PASSED=0
FAILED=0

# 先说明隔离范围，自动回归必须显式传入 --run。
show_script_intro_and_wait() {
  print -r -- 'CommitPathRepair.Tests.zsh：仅在临时 Git 仓库验证旧路径修复。'
  print -r -- '不会连接远端；夹具、生产入口输出与失败证据保留在临时测试目录。'
  if [[ "${1:-}" == --run ]]; then
    return 0
  fi
  [[ -t 0 ]] || { print -u2 -r -- '非交互回归请显式传入 --run。'; exit 1; }
  read -r '?按回车开始；Ctrl+C 取消：' _ || exit 130
}
# 准备无用户配置、无网络及独立日志目录的测试环境。
prepare_environment() {
  emulate -R zsh
  setopt NO_NOMATCH PIPE_FAIL
  if [[ "${1:-}" == --run ]]; then
    shift
  fi
  SUBJECT="${1:-${TEST_PATH:A:h:h:h}/【MacOS@SourceTree】📥修复Git无法Commit.command/【MacOS@SourceTree】📥修复Git无法Commit.command}"
  [[ -f "$SUBJECT" ]] || { print -u2 -r -- "生产脚本不存在：$SUBJECT"; exit 1; }
  SUBJECT="${SUBJECT:A}"
  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/jobs-commit-path-tests.XXXXXX")" || exit 1
  mkdir -p "$TEST_ROOT/Hooks" || exit 1
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=/usr/bin/false GIT_PROXY_COMMAND=/usr/bin/false
  export GIT_AUTHOR_NAME='Jobs fixture' GIT_COMMITTER_NAME='Jobs fixture'
  export GIT_AUTHOR_EMAIL='fixture@example.invalid' GIT_COMMITTER_EMAIL='fixture@example.invalid'
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_NAMESPACE GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
  print -r -- "测试目录：$TEST_ROOT"
}
# 创建带中文与空格路径的基础提交，所有后续操作仅限该夹具。
new_fixture() {
  REPOSITORY="$CASE_DIR/工作仓库 空格"
  git init -q --initial-branch=main "$REPOSITORY" || return 1
  git -C "$REPOSITORY" config core.hooksPath "$TEST_ROOT/Hooks" || return 1
  git -C "$REPOSITORY" config commit.gpgsign false || return 1
  print -r -- 'base' > "$REPOSITORY/old.txt"
  print -r -- 'base' > "$REPOSITORY/unrelated.txt"
  git -C "$REPOSITORY" add -- old.txt unrelated.txt || return 1
  git -C "$REPOSITORY" commit -qm base || return 1
}
# 执行真实生产入口并保存状态码；Sourcetree 环境仅供夹具模拟无交互入口。
run_subject() {
  local expectation="$1"
  shift
  RESULT_CODE=0
  SOURCETREE=1 TERM=dumb /bin/zsh "$SUBJECT" "$REPOSITORY" "$@" > "$CASE_DIR/subject.log" 2>&1 || RESULT_CODE=$?
  CAPTURE="$(<"$CASE_DIR/subject.log")"
  if [[ "$expectation" == success && "$RESULT_CODE" != 0 ]]; then
    print -u2 -r -- "生产入口预期成功，实际退出 $RESULT_CODE：$CAPTURE"
    return 1
  fi
  if [[ "$expectation" == failure && "$RESULT_CODE" == 0 ]]; then
    print -u2 -r -- "生产入口预期失败，实际退出 0：$CAPTURE"
    return 1
  fi
  [[ "$CAPTURE" != *$'\033'* ]] || { print -u2 -r -- 'Sourcetree 输出残留 ANSI。'; return 1; }
}
# 比较可打印的精确值，失败时保留期望与实际值。
assert_equal() {
  [[ "$1" == "$2" ]] || { print -u2 -r -- "期望：$2；实际：$1"; return 1; }
}
# 确认索引没有某个精确路径，防止 pathspec 扩展掩盖结果。
assert_absent_from_index() {
  [[ -z "$(git -C "$REPOSITORY" ls-files -- ":(literal)$1")" ]] || { print -u2 -r -- "索引仍保留旧路径：$1"; return 1; }
}
# 比较已有索引备份和当前索引，验证拒绝分支逐字节保留真实状态。
assert_index_unchanged() {
  cmp -s "$CASE_DIR/index.before" "$(git -C "$REPOSITORY" rev-parse --path-format=absolute --git-path index)" || { print -u2 -r -- '真实索引被意外改写。'; return 1; }
}
# 留存执行前索引和配置，以便比较安全停止或幂等结果。
snapshot_index() {
  cp -p "$(git -C "$REPOSITORY" rev-parse --path-format=absolute --git-path index)" "$CASE_DIR/index.before"
}
# 文件变同名目录时只移除旧条目，保留全部未跟踪子文件。
test_file_to_directory() {
  new_fixture || return 1
  rm "$REPOSITORY/old.txt" || return 1
  mkdir "$REPOSITORY/old.txt" || return 1
  print -r -- 'new child' > "$REPOSITORY/old.txt/new.txt"
  local before_head="$(git -C "$REPOSITORY" rev-parse HEAD)"
  cp -p "$REPOSITORY/.git/config" "$CASE_DIR/config.before" || return 1
  snapshot_index || return 1
  run_subject success --repair-paths || return 1
  assert_absent_from_index old.txt || return 1
  assert_absent_from_index old.txt/new.txt || return 1
  assert_equal "$(<"$REPOSITORY/old.txt/new.txt")" 'new child' || return 1
  assert_equal "$(git -C "$REPOSITORY" rev-parse HEAD)" "$before_head" || return 1
  cmp -s "$CASE_DIR/config.before" "$REPOSITORY/.git/config" || { print -u2 -r -- 'Git 配置被意外修改。'; return 1; }
  local -a backups
  backups=("$REPOSITORY/.git"/index.jobs-paths-before.*(N))
  (( ${#backups[@]} > 0 )) || { print -u2 -r -- '没有留下原索引恢复备份。'; return 1; }
  cmp -s "$CASE_DIR/index.before" "${backups[-1]}" || { print -u2 -r -- '原索引备份不精确。'; return 1; }
  assert_equal "$(git -C "$REPOSITORY" diff --cached --no-renames --name-status)" $'D\told.txt'
}
# 普通删除也能精确暂存，且不会混入其它新文件。
test_plain_deletion() {
  new_fixture || return 1
  rm "$REPOSITORY/old.txt" || return 1
  print -r -- 'pending' > "$REPOSITORY/new.txt"
  run_subject success --repair-paths || return 1
  assert_absent_from_index old.txt || return 1
  assert_absent_from_index new.txt || return 1
  assert_equal "$(git -C "$REPOSITORY" diff --cached --name-status)" $'D\told.txt'
}
# 已完成的旧路径删除可重跑，旧 GUI 列表不会导致索引被重建。
test_already_removed_and_idempotent() {
  new_fixture || return 1
  rm "$REPOSITORY/old.txt" || return 1
  git -C "$REPOSITORY" add -u -- old.txt || return 1
  snapshot_index || return 1
  run_subject success --repair-paths || return 1
  assert_index_unchanged || return 1
  [[ "$CAPTURE" == *'刷新'* ]] || { print -u2 -r -- '缺少刷新 Sourcetree 的说明。'; return 1; }
  run_subject success --repair-paths || return 1
  assert_index_unchanged
}
# 已暂存的新目录子文件保持其部分暂存版本，未跟踪子文件不进入索引。
test_staged_directory_children() {
  new_fixture || return 1
  rm "$REPOSITORY/old.txt" || return 1
  mkdir "$REPOSITORY/old.txt" || return 1
  print -r -- 'staged child' > "$REPOSITORY/old.txt/child.txt"
  git -C "$REPOSITORY" add -- old.txt/child.txt || return 1
  print -r -- 'unstaged child' > "$REPOSITORY/old.txt/child.txt"
  print -r -- 'untracked child' > "$REPOSITORY/old.txt/extra.txt"
  snapshot_index || return 1
  run_subject success --repair-paths || return 1
  assert_index_unchanged || return 1
  assert_equal "$(git -C "$REPOSITORY" show :old.txt/child.txt)" 'staged child' || return 1
  assert_absent_from_index old.txt/extra.txt || return 1
  assert_equal "$(<"$REPOSITORY/old.txt/child.txt")" 'unstaged child'
}
# 精确复现 Sourcetree 先强制添加两个子项、再删除同名旧路径，验证两种入口均不改已有索引。
test_sourcetree_add_then_rm_directory() {
  new_fixture || return 1
  local name='【MacOS】⏬双击浏览器跳转第三方软件官网下载.command' rm_result=0 mode=""
  git -C "$REPOSITORY" mv -- old.txt "$name" || return 1
  git -C "$REPOSITORY" commit -qm 'script fixture' || return 1
  local before_head="$(git -C "$REPOSITORY" rev-parse HEAD)"
  rm "$REPOSITORY/$name" || return 1
  mkdir "$REPOSITORY/$name" || return 1
  print -r -- 'staged README' > "$REPOSITORY/$name/README.md"
  print -r -- 'staged script' > "$REPOSITORY/$name/$name"
  git -C "$REPOSITORY" add -f -- "$name/README.md" "$name/$name" || return 1
  print -r -- 'unstaged README' > "$REPOSITORY/$name/README.md"
  print -r -- 'untracked child' > "$REPOSITORY/$name/extra.txt"
  print -r -- 'staged unrelated' > "$REPOSITORY/unrelated.txt"
  git -C "$REPOSITORY" add -- unrelated.txt || return 1
  print -r -- 'unstaged unrelated' > "$REPOSITORY/unrelated.txt"
  snapshot_index || return 1
  git -C "$REPOSITORY" rm -q -f -- "$name" > "$CASE_DIR/rm.log" 2>&1 || rm_result=$?
  assert_equal "$rm_result" 128 || return 1
  [[ "$(<"$CASE_DIR/rm.log")" == *'recursively without -r'* ]] || return 1
  assert_index_unchanged || return 1
  for mode in auto --repair-paths; do
    if [[ "$mode" == auto ]]; then
      run_subject success || return 1
    else
      run_subject success "$mode" || return 1
    fi
    assert_index_unchanged || return 1
    [[ "$CAPTURE" == *"已暂存文件变目录：${name}（旧文件条目已移除，新目录已有 2 个索引子项）"* ]] || return 1
    [[ "$CAPTURE" == *'本轮未改写真实索引'* && "$CAPTURE" == *'取消旧选择'* ]] || return 1
    assert_equal "$(git -C "$REPOSITORY" show ":$name/README.md")" 'staged README' || return 1
    assert_equal "$(<"$REPOSITORY/$name/README.md")" 'unstaged README' || return 1
    assert_equal "$(git -C "$REPOSITORY" show ":$name/$name")" 'staged script' || return 1
    assert_absent_from_index "$name/extra.txt" || return 1
    assert_equal "$(git -C "$REPOSITORY" show :unrelated.txt)" 'staged unrelated' || return 1
    assert_equal "$(<"$REPOSITORY/unrelated.txt")" 'unstaged unrelated' || return 1
    assert_equal "$(git -C "$REPOSITORY" rev-parse HEAD)" "$before_head" || return 1
  done
}
# 相似前缀目录已有暂存子项不能冒充旧文件同名目录的替换。
test_directory_replacement_prefix_boundary() {
  new_fixture || return 1
  rm "$REPOSITORY/old.txt" || return 1
  mkdir "$REPOSITORY/old.txt" "$REPOSITORY/old.txt-copy" || return 1
  print -r -- 'other subtree' > "$REPOSITORY/old.txt-copy/child.txt"
  git -C "$REPOSITORY" add -- old.txt-copy/child.txt || return 1
  run_subject success || return 1
  [[ "$CAPTURE" != *'已暂存文件变目录：'* ]] || return 1
  assert_absent_from_index old.txt || return 1
  assert_equal "$(git -C "$REPOSITORY" show :old.txt-copy/child.txt)" 'other subtree'
}
# intent-to-add 只登记意图，不计作已有内容的新子项；与真实暂存混合时只统计后者。
test_directory_replacement_intent_to_add() {
  new_fixture || return 1
  rm "$REPOSITORY/old.txt" || return 1
  mkdir "$REPOSITORY/old.txt" || return 1
  print -r -- 'pending intent' > "$REPOSITORY/old.txt/intent.txt"
  git -C "$REPOSITORY" add -N -- old.txt/intent.txt || return 1
  snapshot_index || return 1
  run_subject success || return 1
  assert_index_unchanged || return 1
  [[ "$CAPTURE" != *'已暂存文件变目录：'* ]] || return 1
  print -r -- 'staged content' > "$REPOSITORY/old.txt/real.txt"
  git -C "$REPOSITORY" add -- old.txt/real.txt || return 1
  snapshot_index || return 1
  run_subject success || return 1
  assert_index_unchanged || return 1
  [[ "$CAPTURE" == *'已暂存文件变目录：old.txt（旧文件条目已移除，新目录已有 1 个索引子项）'* ]] || return 1
  assert_equal "$(git -C "$REPOSITORY" diff --cached --no-renames --ita-invisible-in-index --name-status)" $'D\told.txt\nA\told.txt/real.txt'
}
# 无关部分暂存及工作区内容不因修复旧文件删除而改变。
test_unrelated_partial_staging() {
  new_fixture || return 1
  print -r -- 'staged unrelated' > "$REPOSITORY/unrelated.txt"
  git -C "$REPOSITORY" add -- unrelated.txt || return 1
  print -r -- 'unstaged unrelated' > "$REPOSITORY/unrelated.txt"
  rm "$REPOSITORY/old.txt" || return 1
  run_subject success --repair-paths || return 1
  assert_equal "$(git -C "$REPOSITORY" show :unrelated.txt)" 'staged unrelated' || return 1
  assert_equal "$(<"$REPOSITORY/unrelated.txt")" 'unstaged unrelated' || return 1
  assert_absent_from_index old.txt
}
# 删除候选自身已含暂存改动时保留该版本，避免丢掉未提交内容。
test_candidate_has_staged_content() {
  new_fixture || return 1
  print -r -- 'unique staged old' > "$REPOSITORY/old.txt"
  git -C "$REPOSITORY" add -- old.txt || return 1
  rm "$REPOSITORY/old.txt" || return 1
  snapshot_index || return 1
  run_subject success --repair-paths || return 1
  assert_index_unchanged || return 1
  assert_equal "$(git -C "$REPOSITORY" show :old.txt)" 'unique staged old'
}
# 特殊路径必须按 NUL 与字面值处理，不误伤相似路径。
test_literal_paths() {
  new_fixture || return 1
  local name='中文 空格[*]?说明.txt' odd_name=$'换行\n制表\t文件.txt'
  print -r -- 'special' > "$REPOSITORY/$name"
  print -r -- 'odd' > "$REPOSITORY/$odd_name"
  print -r -- 'leading' > "$REPOSITORY/-leading.txt"
  print -r -- 'keep' > "$REPOSITORY/中文 空格a说明.txt"
  git -C "$REPOSITORY" add -A -- . || return 1
  git -C "$REPOSITORY" commit -qm paths || return 1
  rm "$REPOSITORY/$name" "$REPOSITORY/$odd_name" "$REPOSITORY/-leading.txt" || return 1
  run_subject success --repair-paths || return 1
  assert_absent_from_index "$name" || return 1
  assert_absent_from_index "$odd_name" || return 1
  assert_absent_from_index -leading.txt || return 1
  assert_equal "$(git -C "$REPOSITORY" show ':中文 空格a说明.txt')" keep
}
# 原符号链接即使消失或改成目录，也不由普通文件修复接管。
test_original_symlink_preserved() {
  new_fixture || return 1
  ln -s unrelated.txt "$REPOSITORY/link.txt" || return 1
  ln -s unrelated.txt "$REPOSITORY/deleted-link.txt" || return 1
  git -C "$REPOSITORY" add -- link.txt deleted-link.txt || return 1
  git -C "$REPOSITORY" commit -qm links || return 1
  rm "$REPOSITORY/link.txt" "$REPOSITORY/deleted-link.txt" || return 1
  mkdir "$REPOSITORY/link.txt" || return 1
  print -r -- 'preserved child' > "$REPOSITORY/link.txt/child.txt"
  snapshot_index || return 1
  run_subject either --repair-paths || return 1
  assert_index_unchanged || return 1
  assert_equal "$(git -C "$REPOSITORY" show :link.txt)" unrelated.txt || return 1
  assert_equal "$(<"$REPOSITORY/link.txt/child.txt")" 'preserved child'
}
# 已跟踪目录变成普通文件时，不能把被挡住的子条目批量误删。
test_parent_is_file() {
  new_fixture || return 1
  mkdir "$REPOSITORY/Parent" || return 1
  print -r -- 'child' > "$REPOSITORY/Parent/child.txt"
  git -C "$REPOSITORY" add -- Parent/child.txt || return 1
  git -C "$REPOSITORY" commit -qm parent || return 1
  rm "$REPOSITORY/Parent/child.txt" || return 1
  rmdir "$REPOSITORY/Parent" || return 1
  print -r -- 'replacement parent' > "$REPOSITORY/Parent"
  snapshot_index || return 1
  run_subject either --repair-paths || return 1
  assert_index_unchanged || return 1
  assert_equal "$(<"$REPOSITORY/Parent")" 'replacement parent'
}
# 普通文件的祖先已变符号链接时，不遍历外部目标或移除原子条目。
test_symlink_ancestor() {
  new_fixture || return 1
  mkdir "$REPOSITORY/Parent" "$CASE_DIR/外部目录" || return 1
  print -r -- child > "$REPOSITORY/Parent/child.txt"
  git -C "$REPOSITORY" add -- Parent/child.txt || return 1
  git -C "$REPOSITORY" commit -qm ancestor || return 1
  rm "$REPOSITORY/Parent/child.txt" || return 1
  rmdir "$REPOSITORY/Parent" || return 1
  ln -s "$CASE_DIR/外部目录" "$REPOSITORY/Parent" || return 1
  snapshot_index || return 1
  run_subject either --repair-paths || return 1
  assert_index_unchanged || return 1
  assert_equal "$(readlink "$REPOSITORY/Parent")" "$CASE_DIR/外部目录" || return 1
  [[ ! -e "$CASE_DIR/外部目录/child.txt" ]]
}
# skip-worktree 与 assume-unchanged 条目必须保留 flags 和原对象。
test_protected_index_flags() {
  new_fixture || return 1
  print -r -- 'skip' > "$REPOSITORY/skip.txt"
  print -r -- 'assume' > "$REPOSITORY/assume.txt"
  git -C "$REPOSITORY" add -- skip.txt assume.txt || return 1
  git -C "$REPOSITORY" commit -qm flags || return 1
  git -C "$REPOSITORY" update-index --skip-worktree -- skip.txt || return 1
  git -C "$REPOSITORY" update-index --assume-unchanged -- assume.txt || return 1
  rm "$REPOSITORY/skip.txt" "$REPOSITORY/assume.txt" "$REPOSITORY/old.txt" || return 1
  local before="$(git -C "$REPOSITORY" ls-files -v --stage -- skip.txt assume.txt)"
  run_subject success --repair-paths || return 1
  assert_equal "$(git -C "$REPOSITORY" ls-files -v --stage -- skip.txt assume.txt)" "$before" || return 1
  assert_absent_from_index old.txt
}
# 缺失 gitlink 不初始化、不退役、不改写子模块配置。
test_gitlink_preserved() {
  new_fixture || return 1
  local oid="$(git -C "$REPOSITORY" rev-parse HEAD)"
  git -C "$REPOSITORY" update-index --add --cacheinfo "160000,$oid,Child" || return 1
  git -C "$REPOSITORY" commit -qm gitlink || return 1
  rm "$REPOSITORY/old.txt" || return 1
  local before="$(git -C "$REPOSITORY" ls-files --stage -- Child)"
  run_subject success --repair-paths || return 1
  assert_equal "$(git -C "$REPOSITORY" ls-files --stage -- Child)" "$before" || return 1
  [[ ! -e "$REPOSITORY/Child" ]] || { print -u2 -r -- '缺失 gitlink 被擅自初始化。'; return 1; }
  assert_absent_from_index old.txt
}
# 冲突索引必须失败并逐字节保留，不能把未解决条目标为已解决。
test_unmerged_index() {
  new_fixture || return 1
  local base_oid="$(git -C "$REPOSITORY" rev-parse HEAD:old.txt)"
  printf '0 %040d\told.txt\n100644 %s 1\told.txt\n100644 %s 2\told.txt\n100644 %s 3\told.txt\n' 0 "$base_oid" "$base_oid" "$base_oid" | git -C "$REPOSITORY" update-index --index-info || return 1
  snapshot_index || return 1
  run_subject failure --repair-paths || return 1
  assert_index_unchanged || return 1
  [[ "$CAPTURE" == *'冲突'* ]] || { print -u2 -r -- '失败未解释冲突原因。'; return 1; }
  run_subject failure --stage-all || return 1
  assert_index_unchanged || return 1
  [[ "$CAPTURE" == *'冲突'* ]] || { print -u2 -r -- '完整修复模式失败未解释冲突原因。'; return 1; }
}
# 活索引锁不移动、不删除、不覆盖，并保持失败状态。
test_existing_index_lock() {
  new_fixture || return 1
  rm "$REPOSITORY/old.txt" || return 1
  local lock_fd
  exec {lock_fd}> "$REPOSITORY/.git/index.lock" || return 1
  print -r -- 'active lock fixture' >&$lock_fd
  snapshot_index || return 1
  run_subject failure --repair-paths || return 1
  assert_index_unchanged || return 1
  assert_equal "$(<"$REPOSITORY/.git/index.lock")" 'active lock fixture'
}
# 未知参数在业务前失败，避免误进全量暂存。
test_unknown_argument() {
  new_fixture || return 1
  rm "$REPOSITORY/old.txt" || return 1
  snapshot_index || return 1
  run_subject failure --repair-everything || return 1
  assert_index_unchanged || return 1
  [[ "$CAPTURE" == *'未知'* ]] || { print -u2 -r -- '失败未说明未知参数。'; return 1; }
}
# 默认入口自动检测文件变目录，并保留无关部分暂存。
test_default_auto_scope() {
  new_fixture || return 1
  rm "$REPOSITORY/old.txt" || return 1
  mkdir "$REPOSITORY/old.txt" || return 1
  print -r -- child > "$REPOSITORY/old.txt/new.txt"
  print -r -- staged > "$REPOSITORY/unrelated.txt"
  git -C "$REPOSITORY" add -- unrelated.txt || return 1
  print -r -- unstaged > "$REPOSITORY/unrelated.txt"
  run_subject success || return 1
  assert_absent_from_index old.txt || return 1
  assert_absent_from_index old.txt/new.txt || return 1
  assert_equal "$(git -C "$REPOSITORY" show :unrelated.txt)" staged || return 1
  assert_equal "$(<"$REPOSITORY/unrelated.txt")" unstaged
}
# 文档已经暂存迁移时，默认入口保留完整索引与无关部分暂存。
test_default_staged_rename() {
  new_fixture || return 1
  mkdir "$REPOSITORY/项目相关报告" || return 1
  git -C "$REPOSITORY" mv -- old.txt 项目相关报告/old.txt || return 1
  print -r -- 'staged unrelated' > "$REPOSITORY/unrelated.txt"
  git -C "$REPOSITORY" add -- unrelated.txt || return 1
  print -r -- 'unstaged unrelated' > "$REPOSITORY/unrelated.txt"
  print -r -- 'untracked' > "$REPOSITORY/new.txt"
  snapshot_index || return 1
  run_subject success || return 1
  assert_index_unchanged || return 1
  [[ "$CAPTURE" == *'已选择旧路径精确修复'* && "$CAPTURE" == *'提交已暂存内容'* ]] || return 1
  assert_equal "$(git -C "$REPOSITORY" show :unrelated.txt)" 'staged unrelated' || return 1
  assert_absent_from_index new.txt || return 1
  assert_equal "$(<"$REPOSITORY/unrelated.txt")" 'unstaged unrelated' || return 1
  run_subject success || return 1
  assert_index_unchanged || return 1
  git --no-optional-locks -C "$REPOSITORY" commit --dry-run --porcelain > "$CASE_DIR/commit-dry-run.log" 2>&1
}
# 已暂存普通删除也保留原选择，不把其余未暂存修改混入索引。
test_default_staged_deletion() {
  new_fixture || return 1
  git -C "$REPOSITORY" rm -q -- old.txt || return 1
  print -r -- 'unstaged' > "$REPOSITORY/unrelated.txt"
  snapshot_index || return 1
  run_subject success || return 1
  assert_index_unchanged || return 1
  [[ "$CAPTURE" == *'已选择旧路径精确修复'* ]] || return 1
  assert_equal "$(git -C "$REPOSITORY" show :unrelated.txt)" base || return 1
  assert_equal "$(<"$REPOSITORY/unrelated.txt")" unstaged
}
# 显式完整模式继续统一暂存新增、修改、删除，但不创建提交。
test_explicit_stage_all() {
  new_fixture || return 1
  local before_head="$(git -C "$REPOSITORY" rev-parse HEAD)"
  rm "$REPOSITORY/old.txt" || return 1
  print -r -- 'modified' > "$REPOSITORY/unrelated.txt"
  print -r -- 'added' > "$REPOSITORY/new.txt"
  run_subject success --stage-all || return 1
  assert_absent_from_index old.txt || return 1
  assert_equal "$(git -C "$REPOSITORY" show :unrelated.txt)" modified || return 1
  assert_equal "$(git -C "$REPOSITORY" show :new.txt)" added || return 1
  assert_equal "$(git -C "$REPOSITORY" rev-parse HEAD)" "$before_head" || return 1
  assert_equal "$(git -C "$REPOSITORY" diff --cached --no-renames --name-status)" $'A\tnew.txt\nD\told.txt\nM\tunrelated.txt' || return 1
  git -C "$REPOSITORY" diff --quiet
}
# linked worktree 使用自己的真实索引，不能改到主工作树索引。
test_linked_worktree_index() {
  new_fixture || return 1
  local original_repo="$REPOSITORY" linked_repo="$CASE_DIR/链接工作树 空格"
  git -C "$REPOSITORY" worktree add -qb linked "$linked_repo" || return 1
  cp -p "$REPOSITORY/.git/index" "$CASE_DIR/main-index.before" || return 1
  REPOSITORY="$linked_repo"
  rm "$REPOSITORY/old.txt" || return 1
  run_subject success --repair-paths || return 1
  assert_absent_from_index old.txt || return 1
  cmp -s "$CASE_DIR/main-index.before" "$original_repo/.git/index" || { print -u2 -r -- '主工作树索引被改写。'; return 1; }
}
# 每例使用单独进程与日志，失败不影响其它夹具。
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
# 逐项执行真实 Git 索引与完整生产入口的隔离场景。
run_regressions() {
  run_case '文件变目录只暂存旧文件删除' test_file_to_directory
  run_case '普通删除不混入新增文件' test_plain_deletion
  run_case '旧路径已从索引移除与重复执行' test_already_removed_and_idempotent
  run_case '新目录子文件部分暂存保持' test_staged_directory_children
  run_case 'Sourcetree先add两个子项再rm同名旧路径' test_sourcetree_add_then_rm_directory
  run_case '同名前缀其它目录不误报已暂存替换' test_directory_replacement_prefix_boundary
  run_case 'intent-to-add不冒充新子项内容已暂存' test_directory_replacement_intent_to_add
  run_case '无关部分暂存与工作区保持' test_unrelated_partial_staging
  run_case '删除候选已有暂存版本保持' test_candidate_has_staged_content
  run_case '中文空格通配字符换行与前导短横线' test_literal_paths
  run_case '原符号链接与新目录保留' test_original_symlink_preserved
  run_case '父目录变文件不误删子条目' test_parent_is_file
  run_case '祖先符号链接不穿越或移除' test_symlink_ancestor
  run_case '用户索引 flags 保护' test_protected_index_flags
  run_case '缺失 gitlink 不初始化或退役' test_gitlink_preserved
  run_case '精确与完整模式都拒绝未解决冲突' test_unmerged_index
  run_case '活 index.lock 保持原样' test_existing_index_lock
  run_case '未知参数失败且不全量暂存' test_unknown_argument
  run_case '默认自动识别文件变目录' test_default_auto_scope
  run_case '默认识别已暂存文档迁移并保留部分暂存' test_default_staged_rename
  run_case '默认识别已暂存普通删除并保留未暂存修改' test_default_staged_deletion
  run_case '显式完整模式兼容新增修改删除' test_explicit_stage_all
  run_case 'linked worktree 索引归属' test_linked_worktree_index
}
# 汇总并以非零退出码传递失败，所有证据保留供复查。
finish_regressions() {
  print -r -- "结果：${PASSED} 通过，${FAILED} 失败；证据：$TEST_ROOT"
  [[ "$FAILED" == 0 ]] || exit 1
}
# 编排自述、隔离环境与回归验收。
main() {
  show_script_intro_and_wait "$@" # 在写入临时夹具前说明用途、范围与取消方式。
  prepare_environment "$@" # 隔离身份、配置、协议与测试目录。
  run_regressions # 通过真实生产入口逐项验证 Git 索引安全边界。
  finish_regressions # 汇总证据并传播最终状态。
}

main "$@"
