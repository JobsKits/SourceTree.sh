#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】同步edgetunnel代码后手动升级.command
# - 核心用途：验证 edgetunnel 仓库和 Cloudflare 账号，配置精确 KV 绑定并部署 Worker。
# - 影响范围：生成本地部署配置、可能创建 Cloudflare KV 命名空间并更新 Worker；终端可补齐工具链。
# - 运行提示：运行后会先打印内置自述；Sourcetree 模式无交互连续执行，终端模式确认后继续。

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

# ============================== 基础路径 ==============================
# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
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

jobs_brew_note() {
  print -u2 -r -- "ℹ $*"
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
  jobs_prompt_output --question print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
  print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
  print -u2 -n -r -- "➤ 安装路径选择："
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
# 将官方系统安装器下载到临时文件后执行，失败不自动改装到用户目录。
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
# 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
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
    : # 仅本次流程刷新Homebrew环境，不写Shell启动配置。
  fi
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

# 持续获取必需官方文件，网络失败重试，确定错误及取消停止。
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

# 只停止当前获取器创建的子进程树，保留调用者陷阱。
jobs_brew_stop_acquisition_tree() {
  local root="$1" child=""
  for child in $(/usr/bin/pgrep -P "$root" 2>/dev/null); do
    jobs_brew_stop_acquisition_tree "$child"
  done
  /bin/kill -TERM "$root" 2>/dev/null || true
  /bin/kill -KILL "$root" 2>/dev/null || true
}

# 持续获取明确官方稳定 tag，精确版本校验后才发布。
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

# 保留获取失败和取消的原始状态，阻止后续业务。
jobs_brew_stop_failed_install() {
  case "$1" in
    129|130|143) exit "$1" ;;
    *) exit 1 ;;
  esac
}
# <<< Jobs Homebrew install choice <<<
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
readonly SCRIPT_ENTRY_SOURCE="$0"
jobs_fzf_note() {
  if (( ${+functions[jobs_prompt_output]} )); then
    jobs_prompt_output print -u2 -r -- "$*"
  else
    print -u2 -r -- "$*"
  fi
  if [[ -n "${LOG_FILE:-}" ]]; then print -r -- "$*" >> "$LOG_FILE"; fi
}

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

jobs_required_sanitize() {
  /usr/bin/perl -pe 's{([a-zA-Z][a-zA-Z0-9+.-]*://)[^/\s]*@}{$1***@}g; s{((?:https?|ssh|git|file)://[^\s?#]+)[?#][^\s]*}{$1?[REDACTED]}g'
}

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
    if /usr/bin/tail -c +$((offset + 1)) "$output_log" | /usr/bin/tail -c 65536 | /usr/bin/grep -Eqi 'Permission denied|Operation not permitted|No space left|No available formula|No formulae found|File exists|unsupported|not supported|requires Ruby version|Failed to build gem native extension|Gem::Ext::BuildError|cannot create executables|missing.*(header|compiler)|Xcode license|incompatible|Invalid option|Unknown command|No matching|Could not find.*gem|license.*(not accepted|rejected)|authentication failed|certificate.*(invalid|verify failed)'; then
      jobs_fzf_note "✖ $label 遇到确定的权限、版本、许可或本地阻塞，退出码 $result；未继续业务。" || return $?
      return "$result"
    fi
    jobs_fzf_note "⚠ $label 未完成，$delay 秒后重试；Ctrl+C 结束。" || return $?
    /bin/sleep "$delay" || return $?
    (( delay >= 30 )) || delay=$(( delay * 2 > 30 ? 30 : delay * 2 ))
  done
}

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

jobs_required_command() {
  local tool="$1" package="$2" kind="$3" candidate="" probe_result=0; shift 3
  candidate="$(command -v -- "$tool" 2>/dev/null)"
  if [[ -n "$candidate" && -x "$candidate" ]]; then
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
    for environment_key in JAVA_HOME JENV_ROOT JENV_VERSION DEVELOPER_DIR JOBS_HOMEBREW_INSTALL_PREFIX GEM_HOME GEM_PATH GEMRC BUNDLE_GEMFILE RBENV_ROOT RBENV_VERSION RUBYOPT; do
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


typeset -ga JOBS_EDGE_ORIGINAL_ARGS=("$@")
JOBS_EDGE_ORIGINAL_CWD="$PWD"
SCRIPT_DIR=""
SCRIPT_PATH=""
SCRIPT_BASENAME=""
LOG_DIR=""
LOG_FILE=""
# 准备自述路径和日志名称，不在确认前写入文件。
prepare_script_metadata() {
  SCRIPT_PATH="${SCRIPT_ENTRY_SOURCE:A}"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_DIR="${TMPDIR:-/tmp}"
  LOG_DIR="${LOG_DIR%/}"
  LOG_FILE="${LOG_DIR}/${SCRIPT_BASENAME}.log"
}
# 识别 Sourcetree 自定义动作的瘦身运行环境，系统终端双击运行不降级。
is_sourcetree_runtime() {
  [[ "${JOBS_REQUIRED_TOOL_TERMINAL:-0}" != 1 ]] || return 1
  env | grep -Eqi '^SOURCETREE|^SOURCE_TREE' && return 0

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

IS_SOURCETREE_RUNTIME=0

SOURCETREE_PLAIN_OUTPUT=0
# 封装 strip_ansi_text 对应的独立处理逻辑。
strip_ansi_text() {
  perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}

EXPECTED_OWNER="cmliu"
EXPECTED_REPO="edgetunnel"
EXPECTED_SLUG="${EXPECTED_OWNER}/${EXPECTED_REPO}"
EXPECTED_HTTPS_URL="https://github.com/${EXPECTED_SLUG}"

BREW_BIN=""
REPO_ROOT=""
REPO_INPUT_SOURCE=""
MATCHED_REMOTE=""
WRANGLER_BIN=""
WRANGLER_LABEL=""
WRANGLER_CONFIG_FOR_DEPLOY=""
PLAIN_OUTPUT=0
RUNTIME_INITIALIZED=0
# ============================== 输出模式 / 彩色日志 ==============================
# 根据运行入口和终端能力预先切换纯文本输出，避免 SourceTree 显示 ANSI 转义码。
prepare_plain_output_context() {
  [[ -n "${TERM:-}" ]] || export TERM="dumb"
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" || ! -t 1 || "$TERM" == "dumb" || -n "${NO_COLOR+x}" || "${JOBS_PLAIN_OUTPUT:-0}" == "1" ]]; then
    SOURCETREE_PLAIN_OUTPUT=1
    export NO_COLOR="${NO_COLOR:-1}"
    export CLICOLOR="0"
    export ANSI_COLORS_DISABLED="1"
  fi
}
# 配置当前脚本日志和命令输出的彩色或纯文本模式。
configure_output_mode() {
  prepare_plain_output_context
  # SourceTree 自定义操作窗口不完整支持 ANSI 颜色，非 TTY 输出统一降级为纯文本。
  if [[ "${JOBS_PLAIN_OUTPUT:-0}" == "1" || -n "${NO_COLOR+x}" || "${IS_SOURCETREE_RUNTIME:-0}" == "1" ]]; then
    PLAIN_OUTPUT=1
  elif [[ -t 1 ]]; then
    PLAIN_OUTPUT=0
  else
    PLAIN_OUTPUT=1
  fi

  if [[ "$PLAIN_OUTPUT" == "1" ]]; then
    export NO_COLOR=1
    export FORCE_COLOR=0
    export npm_config_color=false
  fi
}
# 封装 strip_ansi_stream 对应的独立处理逻辑。
strip_ansi_stream() {
  jobs_prompt_format 0 0
}
# 按当前输出级别记录终端信息，并同步写入脚本日志。
render_log_stream() {
  if [[ "$PLAIN_OUTPUT" == 1 ]]; then
    strip_ansi_stream
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
# 输出阻塞原因和日志位置并终止当前部署。
die() {
  error_echo "$1"
  err_echo "日志文件：$LOG_FILE"
  exit 1
}
# ============================== 通用执行 ==============================
run_cmd() {
  local title="$1" code=0 log_code=0
  local -a results
  shift
  info_echo "$title" || return $?
  gray_echo "命令：$*" || return $?
  "$@" 2>&1 | jobs_prompt_tee "$LOG_FILE"
  results=("${pipestatus[@]}");code=${results[1]};log_code=${results[2]}
  (( code == 0 )) || return "$code"
  (( log_code == 0 )) || return 74
}
# 让需要终端输入的原生命令直接继承TTY，保留原退出码。
run_interactive_cmd() {
  local title="$1"
  shift
  info_echo "$title"
  gray_echo "命令：$*"
  "$@"
  local code=$?
  if [[ $code -ne 0 ]]; then
    error_echo "命令执行失败：$title"
    return $code
  fi
  success_echo "完成：$title"
  return 0
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_readme_and_wait() {
  prepare_script_metadata
  if typeset -f is_sourcetree_runtime >/dev/null 2>&1 && is_sourcetree_runtime; then
    IS_SOURCETREE_RUNTIME=1
  fi
  configure_output_mode
  if [[ -z "${NO_COLOR+x}" && "$PLAIN_OUTPUT" != 1 && "${IS_SOURCETREE_RUNTIME:-0}" != "1" && -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 ==============================" | jobs_intro_style title
  note_echo "脚本名称：${SCRIPT_BASENAME}.command" | jobs_intro_style title
  note_echo "脚本路径：${SCRIPT_PATH}" | jobs_intro_style body
  note_echo "运行入口：兼容系统终端双击运行和 Sourcetree 自定义动作运行。" | jobs_intro_style body
  note_echo "核心行为：同步 edgetunnel 后自动确认 Cloudflare KV 绑定，并执行 Worker 部署。" | jobs_intro_style body
  note_echo "环境策略：系统终端保留清屏、彩色输出和回车确认；Sourcetree 瘦身环境输出纯文本；健康工具直接复用，缺失时转交独立终端确认和准备，原动作停止后续部署。" | jobs_intro_style body | jobs_prompt_filter
  note_echo "文档关系：同目录 README.md 只作为外部说明文档保留，运行时自述不读取、不拼接、不依赖 README.md。" | jobs_intro_style body
  warn_echo "继续前请确认 SourceTree 传入路径、当前仓库或拖入路径正确；按 Ctrl+C 可以取消。" | jobs_intro_style body
  gray_echo "日志目录：确认后创建本次独立临时目录" | jobs_intro_style body
  highlight_echo "=======================================================================" | jobs_intro_style title
  echo "" | jobs_intro_style body

  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" ]]; then
    gray_echo "已识别为 Sourcetree 自定义动作，将跳过交互并连续执行。" | jobs_intro_style body
    return 0
  fi
  if [[ ! -t 0 ]]; then
    error_echo "当前不是 Sourcetree，且没有可交互输入；请在终端中重新运行。"
    exit 1
  fi
  local intro_answer=""
  read -r "?$(jobs_prompt_render "👉 已阅读脚本内置自述，按回车继续执行；任意文字或Ctrl+C取消：")" intro_answer || return 130
  [[ -z "$intro_answer" ]] || return 130
}
# 仅移除一层配对外引号及行尾，不解释命令或转义。
strip_outer_quotes() {
  local value="$1"
  value="${value%$'\n'}"
  value="${value%$'\r'}"
  if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
    value="${value[2,-2]}"
  fi
  print -r -- "$value"
}
# 收集并校验用户输入，决定后续执行路径。
ask_any_to_run() {
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" == "1" ]]; then
    gray_echo "Sourcetree 连续执行模式已跳过当前可选交互。"
    return 1
  fi
  local message="$1"
  local answer=""

  if [[ ! -t 0 ]]; then
    warn_echo "当前不是可交互终端，已跳过需手动确认的操作：$message"
    return 1
  fi

  read -r "?$(jobs_prompt_render "${message}（直接回车跳过；输入任意字符后回车执行）：")" answer || exit 130
  [[ -n "$answer" ]]
}
# 仅展开用户输入的家目录前缀，保留路径字面值。
normalize_user_input_path() {
  local value="$1"
  value="$(strip_outer_quotes "$value")"
  if [[ "$value" == "~" ]]; then
    value="$HOME"
  elif [[ "$value" == "~/"* ]]; then
    value="${HOME}/${value#\~/}"
  fi
  print -r -- "$value"
}
# ============================== Homebrew / MacOS ==============================
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}
# 解析并返回后续流程需要的目标信息。
find_brew() {
  jobs_brew_find
}
# 只在当前进程激活已选Homebrew，不改用户Shell配置。
activate_brew() {
  local jobs_existing_brew=""
  if jobs_existing_brew="$(jobs_brew_find)"; then
    JOBS_HOMEBREW_BIN="$jobs_existing_brew"
    jobs_brew_activate || exit 1
  fi
  [[ -n "$BREW_BIN" && -x "$BREW_BIN" ]] || return 1
  local shellenv_cmd=""
  shellenv_cmd="$($BREW_BIN shellenv 2>/dev/null || true)"
  if [[ -n "$shellenv_cmd" ]]; then
    eval "$shellenv_cmd"
  fi
  export PATH="$(dirname "$BREW_BIN"):$PATH"
  hash -r 2>/dev/null || true
}
# 必要时准备Homebrew，保留用户可选的索引刷新步骤。
ensure_brew() {
  local jobs_existing_brew=""
  if jobs_existing_brew="$(jobs_brew_find)"; then
    JOBS_HOMEBREW_BIN="$jobs_existing_brew"
    jobs_brew_activate || return $?
  fi
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_install_or_exit
    return 0
  fi
  BREW_BIN="$(find_brew 2>/dev/null || true)"

  if [[ -z "$BREW_BIN" ]]; then
    warn_echo "未检测到 Homebrew，开始安装最新版 Homebrew。"
    jobs_brew_install_or_exit
    BREW_BIN="$JOBS_HOMEBREW_BIN"
    [[ -n "$BREW_BIN" ]] || die "Homebrew 安装后仍未找到 brew，请重新打开终端后再试。"
  else
    success_echo "已检测到 Homebrew：$BREW_BIN"
  fi

  jobs_fzf_bounded_probe "$BREW_BIN" --version >/dev/null 2>&1 || return $?
  activate_brew || return $?

  if ask_any_to_run "是否刷新 Homebrew 索引：brew update"; then
    run_cmd "刷新 Homebrew 索引" "$BREW_BIN" update || return $?
  else
    warn_echo "已跳过 Homebrew 索引刷新。"
    gray_echo "说明：这是耗时操作，按要求默认不自动执行；如后续安装/升级失败，可重新运行并选择执行。"
  fi
}
# 必需工具缺失时承接原目标、工作目录与参数，不在SourceTree动作内等待交互。
handoff_required_toolchain() {
  jobs_required_terminal_handoff "$SCRIPT_PATH" "$REPO_ROOT" "$JOBS_EDGE_ORIGINAL_CWD" "${JOBS_EDGE_ORIGINAL_ARGS[@]}"
}
# 版本探针有界执行；取消直接传递，普通损坏才进入准备分支。
edge_tool_health() {
  local tool="$1" candidate=''
  candidate="$(command -v -- "$tool" 2>/dev/null)" || return 1
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  jobs_fzf_bounded_probe "$candidate" --version </dev/null >/dev/null 2>&1
}
# ============================== Git 仓库定位与校验 ==============================
ensure_git() {
  local result=0
  edge_tool_health git || result=$?
  (( result != 0 )) || return 0
  case "$result" in 129|130|131|137|143) return "$result" ;; esac
  if ! is_interactive_terminal; then handoff_required_toolchain; return $?; fi
  jobs_required_clt_tool git || return $?
  export PATH="${JOBS_REQUIRED_COMMAND:h}:$PATH"; rehash
  edge_tool_health git
}
# 在任何工具准备前解析用户明确给出的现存目录。
resolve_candidate_directory() {
  local candidate="$(normalize_user_input_path "$1")"
  [[ -n "$candidate" && -e "$candidate" ]] || return 2
  [[ ! -f "$candidate" ]] || candidate="${candidate:h}"
  [[ -d "$candidate" ]] || return 2
  (cd -- "$candidate" && pwd -P)
}
# 检查候选路径的Git标记，再执行Git健康检查及只读仓库根定位。
prepare_candidate_repo() {
  local candidate='' parent='' result=0
  candidate="$(resolve_candidate_directory "$1")" || return $?
  parent="$candidate"
  while [[ ! -e "$parent/.git" && "$parent" != / ]]; do parent="${parent:h}"; done
  [[ -e "$parent/.git" ]] || return 2
  REPO_ROOT="$candidate"
  ensure_git || return $?
  REPO_ROOT="$(resolve_repo_root_from_candidate "$candidate")" || return $?
  [[ -n "$REPO_ROOT" ]]
}
# 统一HTTPS/SSH远程地址为仓库标识，用于既有目标校验。
normalize_github_remote() {
  local url="$1"
  local slug=""

  url="${url//$'\r'/}"
  url="${url//$'\n'/}"
  url="${url%/}"
  url="${url%.git}"
  url="${url%/}"

  case "$url" in
    https://github.com/*)
      slug="${url#https://github.com/}"
      ;;
    http://github.com/*)
      slug="${url#http://github.com/}"
      ;;
    git@github.com:*)
      slug="${url#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      slug="${url#ssh://git@github.com/}"
      ;;
    git://github.com/*)
      slug="${url#git://github.com/}"
      ;;
    github.com:*)
      slug="${url#github.com:}"
      ;;
    github.com/*)
      slug="${url#github.com/}"
      ;;
    *)
      slug=""
      ;;
  esac

  slug="${slug%.git}"
  slug="${slug%/}"
  slug="${(L)slug}"
  print -r -- "$slug"
}
# 使用Git只读确认工作区及其真实根目录，不回退当前目录。
resolve_repo_root_from_candidate() {
  local candidate="$1"
  candidate="$(normalize_user_input_path "$candidate")"
  [[ -n "$candidate" ]] || return 1
  [[ -e "$candidate" ]] || return 2

  if [[ -f "$candidate" ]]; then
    candidate="${candidate:h}"
  fi

  local candidate_abs=""
  candidate_abs="$(cd "$candidate" 2>/dev/null && pwd -P || true)"
  [[ -n "$candidate_abs" && -d "$candidate_abs" ]] || return 3

  git -C "$candidate_abs" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 4
  git -C "$candidate_abs" rev-parse --show-toplevel 2>/dev/null || return 5
}
# 在交互终端读取明确路径；EOF和取消直接停止。
prompt_repo_path() {
  local input=""
  local resolved=""

  while true; do
    echo ""
    highlight_echo "请拖入或输入 ${EXPECTED_REPO} 仓库文件夹路径"
    gray_echo "正确示例：~/Documents/GitHub/${EXPECTED_REPO}"
    gray_echo "要求：该目录必须是 ${EXPECTED_HTTPS_URL} 对应的 Git 工作区。"
    read -r "?$(jobs_prompt_render "👉 仓库文件夹路径（Ctrl+C 取消）：")" input || return 130

    input="$(normalize_user_input_path "$input")"
    if [[ ! -e "$input" ]]; then
      local unescaped="${(Q)input}"
      [[ -e "$unescaped" ]] && input="$unescaped"
    fi
    if [[ -z "$input" ]]; then
      warn_echo "未输入路径，请重新拖入或输入仓库文件夹。"
      continue
    fi

    local candidate_result=0
    prepare_candidate_repo "$input" || candidate_result=$?
    case "$candidate_result" in 20|129|130|131|137|143) return "$candidate_result" ;; esac
    if (( candidate_result == 0 )); then
      REPO_INPUT_SOURCE="手动输入/拖拽路径"
      return 0
    fi

    warn_echo "无法从该路径识别 Git 仓库根目录：$input"
    gray_echo "请确认拖入的是 edgetunnel 仓库文件夹，不是脚本文件夹，也不是 SourceTree.command 部署目录。"
  done
}
# 只接受一个显式目标，独立终端无参数时允许手输或拖入。
resolve_target_repo_root() {
  local candidate=""
  local resolved=""

  if [[ $# -gt 0 ]]; then
    (( $# == 1 )) || die "只接受一个仓库路径，请给含空格的路径加引号。"
    candidate="$1"
    local candidate_result=0
    prepare_candidate_repo "$candidate" || candidate_result=$?
    case "$candidate_result" in 20|129|130|131|137|143) return "$candidate_result" ;; esac
    if (( candidate_result == 0 )); then
      REPO_INPUT_SOURCE="SourceTree 参数 / 命令行参数"
      success_echo "已从参数识别仓库根目录：$REPO_ROOT"
      return 0
    fi

    die "传入参数无法识别为 Git 仓库：${candidate}。SourceTree 自定义操作参数必须填写 \$REPO。"
  fi

  if [[ "$IS_SOURCETREE_RUNTIME" != 1 && -t 0 ]]; then
    prompt_repo_path || return $?
    success_echo "已从手动输入识别仓库根目录：$REPO_ROOT"
    return 0
  fi

  die "未收到仓库路径参数，且当前不是可交互终端。SourceTree 中请把参数设置为 \$REPO；独立运行请双击脚本后拖入仓库文件夹。"
}
# 核对目标仓库remote身份后才进入该工作区。
validate_target_repo() {
  [[ -n "$REPO_ROOT" && -d "$REPO_ROOT" ]] || die "仓库根目录无效：${REPO_ROOT:-空}"

  local remotes_output=""
  remotes_output="$(git -C "$REPO_ROOT" remote 2>/dev/null || true)"
  [[ -n "$remotes_output" ]] || die "当前 Git 仓库没有配置 remote，无法确认是否为 ${EXPECTED_HTTPS_URL}。"

  local remote=""
  local url=""
  local normalized=""
  local matched=""

  for remote in ${(f)remotes_output}; do
    url="$(git -C "$REPO_ROOT" remote get-url "$remote" 2>/dev/null || true)"
    [[ -n "$url" ]] || continue
    normalized="$(normalize_github_remote "$url")"
    gray_echo "remote.${remote}.url = ${url} -> ${normalized:-无法识别}"
    if [[ "$normalized" == "${EXPECTED_SLUG}" ]]; then
      matched="${remote}:${url}"
      break
    fi
  done

  [[ -n "$matched" ]] || die "仓库 remote 不合法：必须指向 ${EXPECTED_HTTPS_URL}，HTTPS 和 SSH 写法均支持。"

  MATCHED_REMOTE="$matched"
  cd "$REPO_ROOT" || die "无法进入仓库根目录：$REPO_ROOT"
  success_echo "仓库校验通过：$MATCHED_REMOTE"
  success_echo "仓库来源：$REPO_INPUT_SOURCE"
  success_echo "已切换到仓库根目录：$REPO_ROOT"
}
# ============================== Node / npm / npx / Wrangler 支撑链 ==============================
ensure_node_by_brew() {
  local tool='' result=0 needs_repair=0
  for tool in node npm; do
    result=0;edge_tool_health "$tool" || result=$?
    case "$result" in 129|130|131|137|143) return "$result" ;; esac
    (( result == 0 )) || needs_repair=1
  done
  (( needs_repair != 0 )) || { success_echo '复用健康Node.js/npm，不强制改变来源。'; return 0; }
  ensure_brew || return $?
  jobs_required_brew_package node formula || return $?
  BREW_BIN="$JOBS_HOMEBREW_BIN"
  for tool in node npm; do edge_tool_health "$tool" || return $?; done
}
# 只将当前npm已选前缀中的现存bin加入本进程PATH。
refresh_npm_global_bin() {
  command -v npm >/dev/null 2>&1 || return 0
  local npm_prefix=""
  npm_prefix="$(npm prefix -g 2>/dev/null || true)"
  if [[ -n "$npm_prefix" && -d "${npm_prefix}/bin" ]]; then
    export PATH="${npm_prefix}/bin:$PATH"
  fi
  hash -r 2>/dev/null || true
}
# 保留npm可选升级，并仅在npx不可用时补齐和复检。
ensure_npm_npx_latest() {
  ensure_node_by_brew || return $?

  if ask_any_to_run "是否升级 npm 到最新版（npx 随 npm 一起提供）：npm install -g npm@latest"; then
    jobs_required_acquire "已选择升级 npm（包含 npx）" npm install -g npm@latest || return $?
    refresh_npm_global_bin
  else
    warn_echo "已跳过 npm 升级，继续使用当前 npm / npx。"
  fi

  local npx_result=0
  edge_tool_health npx || npx_result=$?
  case "$npx_result" in 129|130|131|137|143) return "$npx_result" ;; esac
  if (( npx_result != 0 )); then
    warn_echo "当前缺少 npx，必须补齐后才能继续执行 wrangler。"
    jobs_required_acquire "补齐 npx 支撑链" npm install -g npm@latest || return $?
    refresh_npm_global_bin
  fi

  edge_tool_health npx || return $?
}
# 读取现有package.json的三种Wrangler依赖声明。
project_has_local_wrangler() {
  [[ -f "package.json" ]] || return 1

  local dev_dep=""
  local dep=""
  local opt_dep=""
  dev_dep="$(npm pkg get devDependencies.wrangler 2>/dev/null || true)"
  dep="$(npm pkg get dependencies.wrangler 2>/dev/null || true)"
  opt_dep="$(npm pkg get optionalDependencies.wrangler 2>/dev/null || true)"

  [[ "$dev_dep" != "{}" && "$dev_dep" != "null" && "$dev_dep" != "undefined" && -n "$dev_dep" ]] && return 0
  [[ "$dep" != "{}" && "$dep" != "null" && "$dep" != "undefined" && -n "$dep" ]] && return 0
  [[ "$opt_dep" != "{}" && "$opt_dep" != "null" && "$opt_dep" != "undefined" && -n "$opt_dep" ]] && return 0
  return 1
}
# 复验项目优先的现存Wrangler，损坏项目依赖不回退其它版本。
resolve_existing_wrangler() {
  WRANGLER_BIN=""
  WRANGLER_LABEL=""

  local result=0
  local local_bin="${REPO_ROOT}/node_modules/.bin/wrangler"
  if [[ -x "$local_bin" ]]; then
    jobs_fzf_bounded_probe "$local_bin" --version </dev/null >/dev/null 2>&1 || result=$?
    case "$result" in 129|130|131|137|143) return "$result" ;; esac
    (( result == 0 )) || { error_echo "项目Wrangler不可用，保留项目依赖选择；未回退其它版本或清除隔离属性。"; return 2; }
    WRANGLER_BIN="$local_bin"
    WRANGLER_LABEL="$local_bin"
    return 0
  fi

  local global_bin=""
  global_bin="$(command -v wrangler 2>/dev/null || true)"
  if [[ -n "$global_bin" && -x "$global_bin" ]]; then
    jobs_fzf_bounded_probe "$global_bin" --version </dev/null >/dev/null 2>&1 || return $?
    WRANGLER_BIN="$global_bin"
    WRANGLER_LABEL="$global_bin"
    return 0
  fi

  return 1
}
# 以原argv调用已选Wrangler，日志只处理展示副本。
run_wrangler_cmd() {
  local title="$1"
  shift

  if [[ -n "$WRANGLER_BIN" ]]; then
    run_cmd "$title" "$WRANGLER_BIN" "$@"
  else
    run_cmd "$title" npx wrangler "$@"
  fi
}
# 让已选Wrangler登录直接继承当前终端。
run_interactive_wrangler_cmd() {
  local title="$1"
  shift

  if [[ -n "$WRANGLER_BIN" ]]; then
    run_interactive_cmd "$title" "$WRANGLER_BIN" "$@"
  else
    run_interactive_cmd "$title" npx wrangler "$@"
  fi
}
# 保留已确认的升级选择，缺失项目依赖按现有npm锁准备。
ensure_wrangler_latest() {
  ensure_npm_npx_latest || return $?
  export npm_config_yes="true"

  if project_has_local_wrangler; then
    if ask_any_to_run "是否升级本仓库 wrangler 到最新版：npm install --save-dev wrangler@latest"; then
      jobs_required_acquire "已选择升级本仓库 wrangler@latest" npm install --save-dev wrangler@latest || return $?
    else
      warn_echo "已跳过本仓库 wrangler 升级，继续使用当前项目依赖。"
    fi
  else
    if resolve_existing_wrangler; then
      if ask_any_to_run "是否安装/升级全局 wrangler 到最新版：npm install -g wrangler@latest"; then
        jobs_required_acquire "已选择全局 wrangler@latest" npm install -g wrangler@latest || return $?
        refresh_npm_global_bin
      else
        warn_echo "已跳过全局 wrangler 升级，继续使用当前已安装版本。"
      fi
    else
      local wrangler_result=$?
      case "$wrangler_result" in 2|129|130|131|137|143) return "$wrangler_result" ;; esac
      warn_echo "未检测到已安装的 wrangler，开始安装全局 wrangler@latest。"
      jobs_required_acquire "必需全局 wrangler@latest" npm install -g wrangler@latest || return $?
      refresh_npm_global_bin
    fi
  fi

  local resolve_result=0
  resolve_existing_wrangler || resolve_result=$?
  case "$resolve_result" in 2|129|130|131|137|143) return "$resolve_result" ;; esac
  if (( resolve_result != 0 )) && project_has_local_wrangler; then
    if [[ -f package-lock.json || -f npm-shrinkwrap.json ]]; then
      jobs_required_acquire "按现有npm锁文件准备项目依赖" npm ci || return $?
      resolve_existing_wrangler || return $?
    else
      error_echo "项目已声明Wrangler但缺少可用本地入口和npm锁文件；请使用该项目声明的包管理器准备，未猜测最新版。"
      return 1
    fi
  fi
  run_wrangler_cmd "确认 Wrangler 版本" --version || return $?
}
# 检查当前运行条件是否满足后续流程要求。
check_toolchain_ready_for_sourcetree() {
  local tool='' result=0
  refresh_npm_global_bin
  for tool in node npm npx; do
    result=0;edge_tool_health "$tool" || result=$?
    case "$result" in 129|130|131|137|143) return "$result" ;; esac
    if (( result != 0 )); then handoff_required_toolchain; return $?; fi
  done
  result=0;resolve_existing_wrangler || result=$?
  case "$result" in 129|130|131|137|143) return "$result" ;; esac
  if (( result != 0 )); then handoff_required_toolchain; return $?; fi
  success_echo '复用已通过版本检查的工具链；SourceTree原动作未安装或升级。'
}
# 交互终端准备必需工具；SourceTree只复验或转交新终端。
prepare_toolchain_for_current_context() {
  if is_interactive_terminal; then
    ensure_wrangler_latest
  else
    check_toolchain_ready_for_sourcetree
  fi
}
# 显示本轮实际使用的工具路径与版本。
print_toolchain_versions() {
  highlight_echo "============================== 工具链版本 =============================="
  if [[ -n "$BREW_BIN" && -x "$BREW_BIN" ]]; then
    gray_echo "brew: $($BREW_BIN --version 2>/dev/null | head -n 1 || echo '不可用')"
  else
    gray_echo "brew: 未检测到或未参与本次执行"
  fi
  gray_echo "node: $(node -v 2>/dev/null || echo '不可用') ($(command -v node 2>/dev/null || echo '未找到'))"
  gray_echo "npm : $(npm -v 2>/dev/null || echo '不可用') ($(command -v npm 2>/dev/null || echo '未找到'))"
  gray_echo "npx : $(npx --version 2>/dev/null || echo '不可用') ($(command -v npx 2>/dev/null || echo '未找到'))"
  if [[ -n "$WRANGLER_LABEL" ]]; then
    gray_echo "wrangler: $WRANGLER_LABEL"
  else
    gray_echo "wrangler: npx wrangler"
  fi
  highlight_echo "======================================================================="
}
# ============================== Cloudflare / Wrangler 授权与部署 ==============================
is_interactive_terminal() {
  [[ "$IS_SOURCETREE_RUNTIME" != 1 && -t 0 && -t 1 ]]
}
# 解释SourceTree的OAuth限制及独立终端登录入口。
print_sourcetree_auth_hint() {
  warn_echo "SourceTree 自定义操作不是稳定的浏览器 OAuth 交互环境，本脚本不会在 SourceTree 内强行执行 wrangler login。"
  gray_echo "原因：wrangler login 会启动本机 localhost OAuth 回调；SourceTree 的脚本窗口容易造成回调状态不一致、输出延迟或登录失败。"
  echo "" | tee -a "$LOG_FILE"
  note_echo "正确流程："
  gray_echo "1. 先双击本脚本，或在终端独立运行本脚本，完成一次 Cloudflare 登录。"
  gray_echo "2. 登录成功后，再回到 SourceTree 点自定义菜单；SourceTree 模式只检查登录状态并执行 deploy。"
  echo "" | tee -a "$LOG_FILE"
  gray_echo "可直接在终端执行："
  gray_echo "${SCRIPT_PATH} ${REPO_ROOT}"
}
# 捕获原始whoami响应，只将展示副本追加日志。
wrangler_whoami_ok() {
  local auth_log="${LOG_DIR}/${SCRIPT_BASENAME}.wrangler-whoami.log"
  : > "$auth_log"

  info_echo "检查 Cloudflare 登录状态"
  if [[ -n "$WRANGLER_BIN" ]]; then
    gray_echo "命令：$WRANGLER_BIN whoami --json"
    "$WRANGLER_BIN" whoami --json > "$auth_log" 2>&1
  else
    gray_echo "命令：npx wrangler whoami --json"
    npx wrangler whoami --json > "$auth_log" 2>&1
  fi

  if [[ $? -eq 0 ]]; then
    cat "$auth_log" | strip_ansi_stream >> "$LOG_FILE"
    success_echo "已检测到 Cloudflare 登录状态：wrangler whoami 通过。"
    return 0
  fi

  cat "$auth_log" | strip_ansi_stream >> "$LOG_FILE"
  warn_echo "未检测到有效的 Cloudflare 登录状态：wrangler whoami 未通过。"
  gray_echo "whoami 详细输出已写入：$LOG_FILE"
  return 1
}
# 沿用现有账号及显式强制登录策略，未授权不部署。
ensure_wrangler_auth() {
  export npm_config_yes="true"

  highlight_echo "============================== Wrangler Auth =============================="

  if [[ "${FORCE_WRANGLER_LOGIN:-0}" == "1" ]]; then
    if is_interactive_terminal; then
      warn_echo "已启用 FORCE_WRANGLER_LOGIN=1，将在交互终端中强制重新登录。"
      run_interactive_wrangler_cmd "执行 Cloudflare 登录" login || die "wrangler login 执行失败。"
      wrangler_whoami_ok || die "Cloudflare 登录后仍无法通过 wrangler whoami 校验。"
      return 0
    fi

    print_sourcetree_auth_hint
    die "当前不是可交互终端，不能执行 FORCE_WRANGLER_LOGIN=1。"
  fi

  if wrangler_whoami_ok; then
    return 0
  fi

  if is_interactive_terminal; then
    run_interactive_wrangler_cmd "执行 Cloudflare 登录" login || die "wrangler login 执行失败。"
    wrangler_whoami_ok || die "Cloudflare 登录后仍无法通过 wrangler whoami 校验。"
    return 0
  fi

  print_sourcetree_auth_hint
  die "SourceTree 非交互环境未检测到有效登录状态，请先在终端/双击模式完成 wrangler login。"
}
# 原样保存Wrangler协议输出，另写可读日志并传播退出码。
capture_wrangler_cmd_to_file() {
  local title="$1"
  local output_file="$2"
  shift 2

  info_echo "$title"
  if [[ -n "$WRANGLER_BIN" ]]; then
    gray_echo "命令：$WRANGLER_BIN $*"
    "$WRANGLER_BIN" "$@" > "$output_file" 2>&1
  else
    gray_echo "命令：npx wrangler $*"
    npx wrangler "$@" > "$output_file" 2>&1
  fi

  local code=$?
  if [[ -s "$output_file" ]]; then
    cat "$output_file" | strip_ansi_stream >> "$LOG_FILE"
  fi

  if [[ $code -ne 0 ]]; then
    error_echo "命令执行失败：$title"
    return $code
  fi

  return 0
}
# 按既定环境变量和仓内声明顺序读取命名空间名称。
resolve_edgetunnel_kv_namespace_title() {
  local title=""
  local config_file="${REPO_ROOT}/.edgetunnel-kv-namespace"

  if [[ -n "${EDGETUNNEL_KV_NAMESPACE_TITLE:-}" ]]; then
    title="$EDGETUNNEL_KV_NAMESPACE_TITLE"
  elif [[ -n "${EDGETUNNEL_KV_NAMESPACE:-}" ]]; then
    title="$EDGETUNNEL_KV_NAMESPACE"
  elif [[ -n "${JOBS_EDGETUNNEL_KV_NAMESPACE:-}" ]]; then
    title="$JOBS_EDGETUNNEL_KV_NAMESPACE"
  elif [[ -f "$config_file" ]]; then
    title="$(grep -vE '^\s*(#|$)' "$config_file" 2>/dev/null | head -n 1 || true)"
  fi

  title="$(strip_outer_quotes "${title:-}")"
  [[ -n "$title" ]] || title="JobsGo"
  print -r -- "$title"
}
# 按名称或ID精确解析Wrangler响应，不猜测其它命名空间。
kv_namespace_lookup_from_json() {
  local json_file="$1"
  local lookup_mode="$2"
  local lookup_value="$3"
  local output_field="$4"

  [[ -f "$json_file" ]] || return 1

  KV_JSON_FILE="$json_file" \
  KV_LOOKUP_MODE="$lookup_mode" \
  KV_LOOKUP_VALUE="$lookup_value" \
  KV_OUTPUT_FIELD="$output_field" \
  node <<'NODE'
const fs = require('fs');
const file = process.env.KV_JSON_FILE;
const mode = process.env.KV_LOOKUP_MODE || 'any';
const value = process.env.KV_LOOKUP_VALUE || '';
const output = process.env.KV_OUTPUT_FIELD || 'id';
const raw = fs.readFileSync(file, 'utf8').trim();

function collect(input) {
  if (!input) return [];
  if (Array.isArray(input)) return input.flatMap(collect);
  if (typeof input !== 'object') return [];

  const picked = [];
  if (input.id || input.title || input.name) picked.push(input);

  for (const key of ['result', 'results', 'namespaces', 'namespace', 'kv_namespaces', 'kv_namespace']) {
    if (input[key]) picked.push(...collect(input[key]));
  }

  return picked;
}

function field(item, name) {
  if (!item) return '';
  if (name === 'title') return String(item.title || item.name || '');
  if (name === 'id') return String(item.id || '');
  return String(item[name] || '');
}

function selectFromItems(items) {
  let item;
  if (mode === 'title') {
    item = items.find(x => field(x, 'title') === value);
  } else if (mode === 'id') {
    item = items.find(x => field(x, 'id') === value);
  } else {
    const ids = [...new Set(items.map(x => field(x, 'id')).filter(Boolean))];
    if (ids.length !== 1) return '';
    item = items.find(x => field(x, 'id') === ids[0]);
  }
  return field(item, output);
}

function tryJsonParse(text) {
  const candidates = [text];
  const firstArray = text.indexOf('[');
  const lastArray = text.lastIndexOf(']');
  if (firstArray >= 0 && lastArray > firstArray) candidates.push(text.slice(firstArray, lastArray + 1));
  const firstObj = text.indexOf('{');
  const lastObj = text.lastIndexOf('}');
  if (firstObj >= 0 && lastObj > firstObj) candidates.push(text.slice(firstObj, lastObj + 1));

  for (const candidate of candidates) {
    // 兼容 Wrangler 输出中夹带说明文本时截取出的候选 JSON。
    try {
      const parsed = JSON.parse(candidate);
      const items = collect(parsed);
      const shapeValid = Array.isArray(parsed) || (parsed && typeof parsed === 'object' &&
        (parsed.id || ['result', 'results', 'namespaces', 'namespace', 'kv_namespaces', 'kv_namespace'].some(k => k in parsed)));
      if (!shapeValid || parsed?.success === false) return { parsed: true, invalid: true, result: '' };
      return { parsed: true, invalid: false, result: selectFromItems(items) };
    } catch (_) {}
  }
  return { parsed: false, invalid: false, result: '' };
}

function tryTextParse(text) {
  // 文本 ID 后备只接受创建命令的单一 ID；列表查找必须提供可解析 JSON。
  if (mode !== 'any') return '';
  const ids = [...new Set(text.match(/\b[a-f0-9]{32}\b/ig) || [])];
  if (ids.length !== 1) return '';
  if (output === 'id') return ids[0];
  return output === 'title' ? '已创建' : '';
}

if (!raw) process.exit(2);
const parsed = tryJsonParse(raw);
if (parsed.invalid || (!parsed.parsed && mode !== 'any')) process.exit(2);
const result = parsed.parsed ? parsed.result : tryTextParse(raw);
if (!result) process.exit(1);
process.stdout.write(result);
NODE
}
# 严格查找列表；无匹配可继续创建，解析失败必须阻止部署。
lookup_kv_in_list() {
  local result="" code=0
  result="$(kv_namespace_lookup_from_json "$@")" || code=$?
  if (( code > 1 )); then
    print -u2 -r -- "无法解析 KV 列表，请检查 Wrangler 版本及账户响应：$1"
    return "$code"
  fi
  print -r -- "$result"
  return 0
}
# 只读取启用的顶层KV绑定，保留原TOML字节。
extract_active_kv_binding_id_from_toml() {
  local toml_file="$1"
  [[ -f "$toml_file" ]] || return 1

  WRANGLER_TOML_FILE="$toml_file" node <<'NODE'
const fs = require('fs');
const file = process.env.WRANGLER_TOML_FILE;
const text = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
const lines = text.split('\n');
const tableHeader = line => /^\s*\[.*\]\s*(?:#.*)?$/.test(line) && !/^\s*#/.test(line);
const kvHeader = line => /^\s*\[\[kv_namespaces\]\]\s*(?:#.*)?$/.test(line) && !/^\s*#/.test(line);
const unquote = value => value.replace(/^\s*['"]?/, '').replace(/['"]?\s*$/, '').trim();

for (let i = 0; i < lines.length; i++) {
  if (!kvHeader(lines[i])) continue;

  let j = i + 1;
  while (j < lines.length && !tableHeader(lines[j])) j++;
  const block = lines.slice(i, j);
  const hasKVBinding = block.some(line => /^\s*binding\s*=\s*['"]KV['"]\s*(?:#.*)?$/.test(line));
  if (!hasKVBinding) continue;

  const idLine = block.find(line => /^\s*id\s*=/.test(line));
  if (!idLine) process.exit(1);
  const id = unquote(idLine.split('=').slice(1).join('='));
  if (!id) process.exit(1);
  process.stdout.write(id);
  process.exit(0);
}

process.exit(1);
NODE
}
# 仅将本次生成的配置名称加入该仓库本地Git排除项。
add_local_git_exclude() {
  local pattern="$1"
  local exclude_file=""

  exclude_file="$(git -C "$REPO_ROOT" rev-parse --git-path info/exclude 2>/dev/null || true)"
  [[ -n "$exclude_file" ]] || return 0

  mkdir -p "$(dirname "$exclude_file")" 2>/dev/null || true
  touch "$exclude_file" 2>/dev/null || true

  if [[ -f "$exclude_file" ]] && ! grep -qxF "$pattern" "$exclude_file" 2>/dev/null; then
    printf '\n%s\n' "$pattern" >> "$exclude_file" 2>/dev/null || true
  fi
}
# 生成已校验KV配置副本，保留原始wrangler.toml。
generate_wrangler_config_with_kv_binding() {
  local namespace_id="$1"
  local source_toml="${REPO_ROOT}/wrangler.toml"
  local target_toml="${REPO_ROOT}/.wrangler.jobs.local.toml"

  [[ -f "$source_toml" ]] || die "未找到 wrangler.toml：$source_toml"
  [[ -n "$namespace_id" ]] || die "KV namespace id 为空，无法生成部署配置。"

  WRANGLER_TOML_SOURCE="$source_toml" \
  WRANGLER_TOML_TARGET="$target_toml" \
  KV_NAMESPACE_ID="$namespace_id" \
  node <<'NODE' || return 1
const fs = require('fs');
const source = process.env.WRANGLER_TOML_SOURCE;
const target = process.env.WRANGLER_TOML_TARGET;
const namespaceId = process.env.KV_NAMESPACE_ID;
if (!/^[a-f0-9]{32}$/i.test(namespaceId || "")) throw new Error("Invalid KV namespace ID");

const text = fs.readFileSync(source, 'utf8').replace(/\r\n/g, '\n');
let lines = text.split('\n');
if (lines.length && lines[lines.length - 1] === '') lines.pop();

const tableHeader = line => /^\s*\[.*\]\s*(?:#.*)?$/.test(line) && !/^\s*#/.test(line);
const kvHeader = line => /^\s*\[\[kv_namespaces\]\]\s*(?:#.*)?$/.test(line) && !/^\s*#/.test(line);
const out = [];

for (let i = 0; i < lines.length;) {
  if (kvHeader(lines[i])) {
    let j = i + 1;
    while (j < lines.length && !tableHeader(lines[j])) j++;
    const block = lines.slice(i, j);
    const hasKVBinding = block.some(line => /^\s*binding\s*=\s*['"]KV['"]\s*(?:#.*)?$/.test(line));
    if (hasKVBinding) {
      i = j;
      continue;
    }
  }

  out.push(lines[i]);
  i++;
}

while (out.length && out[out.length - 1].trim() === '') out.pop();
if (out.length) out.push('');
out.push('# 自动由脚本生成：edgetunnel 代码读取 env.KV');
out.push('[[kv_namespaces]]');
out.push('binding = "KV"');
out.push(`id = "${namespaceId}"`);

fs.writeFileSync(target, out.join('\n') + '\n', 'utf8');
NODE

  [[ $? -eq 0 ]] || die "生成本地 Wrangler 部署配置失败。"
  WRANGLER_CONFIG_FOR_DEPLOY="$target_toml"
  add_local_git_exclude ".wrangler.jobs.local.toml"
  success_echo "已生成本地部署配置：$target_toml"
  gray_echo "说明：原始 wrangler.toml 不会被改脏；部署时使用 --config .wrangler.jobs.local.toml。"
}
# 精确复用账号中的KV绑定，确实缺少时才创建。
ensure_edgetunnel_kv_binding() {
  highlight_echo "============================== Cloudflare KV Binding ============================="

  local source_toml="${REPO_ROOT}/wrangler.toml"
  local generated_toml="${REPO_ROOT}/.wrangler.jobs.local.toml"
  [[ -f "$source_toml" ]] || die "未找到 wrangler.toml：$source_toml"

  local namespace_title=""
  local namespace_id=""
  local existing_id=""
  local existing_title=""
  local list_log="${LOG_DIR}/${SCRIPT_BASENAME}.kv-list.log"
  local create_log="${LOG_DIR}/${SCRIPT_BASENAME}.kv-create.log"

  namespace_title="$(resolve_edgetunnel_kv_namespace_title)"
  gray_echo "目标 KV 命名空间名称：$namespace_title"
  gray_echo "目标 Worker 绑定变量名：KV"

  capture_wrangler_cmd_to_file "读取 Cloudflare KV 命名空间列表" "$list_log" kv namespace list || die "读取 Cloudflare KV 命名空间列表失败。"

  existing_id="$(extract_active_kv_binding_id_from_toml "$source_toml" 2>/dev/null || true)"
  if [[ -z "$existing_id" && -f "$generated_toml" ]]; then
    existing_id="$(extract_active_kv_binding_id_from_toml "$generated_toml" 2>/dev/null || true)"
    [[ -n "$existing_id" ]] && gray_echo "已从上次自动生成的本地部署配置读取 KV id：$existing_id"
  fi

  if [[ -n "$existing_id" ]]; then
    existing_title="$(lookup_kv_in_list "$list_log" id "$existing_id" title)" || die "KV 列表解析失败，停止部署。"
    if [[ -n "$existing_title" ]]; then
      success_echo "已检测到有效 KV 绑定：KV -> ${existing_title} (${existing_id})"
      generate_wrangler_config_with_kv_binding "$existing_id" || die "KV 配置生成失败，停止部署。"
      return 0
    fi

    warn_echo "已记录的 KV id 未在当前 Cloudflare 账号下找到：$existing_id"
    warn_echo "将改用命名空间名称 ${namespace_title} 自动修复本次部署配置。"
  fi

  namespace_id="$(lookup_kv_in_list "$list_log" title "$namespace_title" id)" || die "KV 列表解析失败，停止部署。"

  if [[ -z "$namespace_id" ]]; then
    warn_echo "未找到 KV 命名空间：$namespace_title，将自动创建。"
    capture_wrangler_cmd_to_file "创建 Cloudflare KV 命名空间" "$create_log" kv namespace create "$namespace_title" || die "创建 Cloudflare KV 命名空间失败：$namespace_title"

    namespace_id="$(kv_namespace_lookup_from_json "$create_log" title "$namespace_title" id 2>/dev/null || true)"
    [[ -n "$namespace_id" ]] || namespace_id="$(kv_namespace_lookup_from_json "$create_log" any "" id 2>/dev/null || true)"

    if [[ -z "$namespace_id" ]]; then
      warn_echo "创建命令未直接返回可解析 id，将重新读取命名空间列表确认。"
      capture_wrangler_cmd_to_file "重新读取 Cloudflare KV 命名空间列表" "$list_log" kv namespace list || die "重新读取 Cloudflare KV 命名空间列表失败。"
      namespace_id="$(lookup_kv_in_list "$list_log" title "$namespace_title" id)" || die "KV 列表解析失败，停止部署。"
    fi
  else
    success_echo "已找到 KV 命名空间：$namespace_title (${namespace_id})"
  fi

  [[ -n "$namespace_id" ]] || die "无法取得 KV 命名空间 id：$namespace_title"

  generate_wrangler_config_with_kv_binding "$namespace_id" || die "KV 配置生成失败，停止部署。"
  success_echo "KV 绑定已就绪：binding = KV，namespace = ${namespace_title}，id = ${namespace_id}"
}
# 现有授权和KV准备成功后调用原Worker部署命令。
run_wrangler_deploy() {
  export npm_config_yes="true"

  ensure_wrangler_auth || die "Cloudflare 授权检查失败，停止部署。"
  ensure_edgetunnel_kv_binding || die "KV 绑定准备失败，停止部署。"

  highlight_echo "============================== Wrangler Deploy ============================="
  if [[ -n "$WRANGLER_CONFIG_FOR_DEPLOY" ]]; then
    run_wrangler_cmd "执行 Cloudflare 部署" deploy --config "$WRANGLER_CONFIG_FOR_DEPLOY" || die "wrangler deploy 执行失败。"
  else
    run_wrangler_cmd "执行 Cloudflare 部署" deploy || die "wrangler deploy 执行失败。"
  fi
}
# 检查系统平台，避免在其它平台写入部署配置。
check_platform() {
  [[ "$(uname -s)" == Darwin ]] || die "该脚本仅支持 macOS。"
}
# 输出部署成功和日志位置。
finish_deployment() {
  success_echo "部署完成。日志：$LOG_FILE"
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  setopt NO_NOMATCH
  set -u
  set -o pipefail 2>/dev/null || true
  local runtime_directory=''
  runtime_directory="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsEdgeTunnel.XXXXXX")" || { error_echo '无法创建本次私有日志目录，未继续。'; return 74; }
  LOG_DIR="$runtime_directory";LOG_FILE="$LOG_DIR/${SCRIPT_BASENAME}.log"
  : > "$LOG_FILE" || return 74
  RUNTIME_INITIALIZED=1
  is_sourcetree_runtime && IS_SOURCETREE_RUNTIME=1
  configure_output_mode
}
# 转交终端仅表示已承接准备；原动作不得继续账号、KV或部署步骤。
run_deployment_for_target() {
  local result=0
  resolve_target_repo_root "$@" || result=$?
  (( result != 20 )) || return 0
  (( result == 0 )) || return "$result"
  validate_target_repo || return $?
  prepare_toolchain_for_current_context || result=$?
  (( result != 20 )) || return 0
  (( result == 0 )) || return "$result"
  print_toolchain_versions || return $?
  run_wrangler_deploy || return $?
  finish_deployment
}
# 依次编排内置自述、私有日志、平台检查与部署流程。
main() {
  show_readme_and_wait || return $? # 展示用途并按真实入口确认。
  initialize_script_runtime || return $? # 确认后创建独立日志。
  check_platform || return $? # 校验macOS平台。
  run_deployment_for_target "$@" # 目标校验、必要工具准备和原授权部署顺序执行。
}

main "$@"
