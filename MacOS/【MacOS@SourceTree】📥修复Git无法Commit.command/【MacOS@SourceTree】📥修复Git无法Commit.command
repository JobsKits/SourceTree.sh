#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】📥修复Git无法Commit.command
# - 核心用途：自动识别 Sourcetree 旧路径/文件变目录故障，精确暂存旧文件删除；其它故障沿用 8 场景修复，先检查目录过滤器。
# - 关键场景：工作树绑定错位、残留索引锁、gitlink 顺序错误、嵌套路径迁移、子模块异常，以及文件/目录形态互换。
# - 影响范围：修改 Git 索引；可归档确认无进程占用的残留锁并初始化缺失子模块，但不清理已有子模块的真实修改。
# - 运行提示：Sourcetree 模式无交互连续执行；终端独立运行需先按回车确认。

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
# 解析脚本真实路径，兼容 Sourcetree 只传入脚本名的运行环境。
resolve_script_path() {
  local script_source="$SCRIPT_SOURCE"
  local script_name="$SCRIPT_NAME"
  local candidate=""

  for candidate in \
    "$script_source" \
    "${PWD}/${script_source}" \
    "${HOME}/SourceTree.command/MacOS/${script_name}/${script_name}" \
    "${HOME}/Documents/Github/JobsGenesis/SourceTree.command/MacOS/${script_name}/${script_name}"; do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    (cd "$(dirname "$candidate")" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$(basename "$candidate")")
    return 0
  done

  printf '%s/%s\n' "$PWD" "$script_name"
}

SCRIPT_SOURCE="${BASH_SOURCE[0]:-${(%):-%x}}"
SCRIPT_NAME="${0:t}"
SCRIPT_BASENAME="${SCRIPT_NAME:r}"
SCRIPT_PATH=""
SCRIPT_DIR=""
LOG_DIR="${TMPDIR:-/tmp}"
LOG_DIR="${LOG_DIR%/}"
LOG_FILE="${LOG_DIR}/${SCRIPT_BASENAME}.log"
IS_SOURCETREE_RUNTIME=0
PLAIN_OUTPUT=0
LOG_READY=0
TARGET_PATH=""
REPO_ROOT=""
INDEX_LOCK_PATH=""
COMMIT_SCENARIO_STEP=0
COMMIT_SCENARIO_TOTAL=8
COMMIT_REPAIR_MODE="auto"
PATH_REPAIR_ACTIVE=0
PATH_REPAIR_TEMP=""
PATH_REPAIR_LOCK=""
PATH_REPAIR_LOCK_OWNED=0
typeset -ga GITLINK_PATHS
GITLINK_PATHS=()

# 准备只用于自述和路径定位的脚本上下文，不写入文件或 Git 状态。
prepare_script_context() {
  SCRIPT_PATH="$(resolve_script_path)"
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd -P)"
}
# 识别 Sourcetree 自定义动作的非交互运行环境。
is_sourcetree_runtime() {
  env | grep -Ei '^SOURCETREE|^SOURCE_TREE' >/dev/null && return 0

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
# 移除 ANSI 颜色码，避免 Sourcetree 输出窗口显示乱码。
strip_ansi_text() {
  perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}
# 在首次输出前确定 Sourcetree 和纯文本输出模式。
configure_output_mode() {
  if is_sourcetree_runtime; then
    IS_SOURCETREE_RUNTIME=1
  fi
  if [[ "$IS_SOURCETREE_RUNTIME" == "1" || ! -t 1 || -z "${TERM:-}" || "${TERM:-}" == "dumb" || -n "${NO_COLOR+x}" ]]; then
    PLAIN_OUTPUT=1
    export NO_COLOR=1
    export FORCE_COLOR=0
    export CLICOLOR=0
    export ANSI_COLORS_DISABLED=1
    export npm_config_color=false
  fi
}
# 日志按原文输出；确认前只展示，确认后同步写入日志。
log() {
  local message="$1"
  if [[ "$LOG_READY" != "1" ]]; then
    if [[ "$PLAIN_OUTPUT" == "1" ]]; then
      printf '%s\n' "$message" | strip_ansi_text
    else
      printf '%s\n' "$message"
    fi
    return 0
  fi
  if [[ "$PLAIN_OUTPUT" == "1" ]]; then
    printf '%s\n' "$message" | strip_ansi_text | jobs_prompt_tee "$LOG_FILE"
  else
    printf '%s\n' "$message" | jobs_prompt_tee "$LOG_FILE"
  fi
}
# 固定颜色码单独处理，用户路径与正文不做反斜杠转义。
color_log() {
  local color="$1" message="$2"
  if [[ "$PLAIN_OUTPUT" == "1" ]]; then
    log "$message"
  else
    log "${color}${message}"$'\033[0m'
  fi
}
# 输出信息日志。
info_echo() { color_log $'\033[1;34m' "ℹ $1"; }
# 输出成功日志。
success_echo() { color_log $'\033[1;32m' "✔ $1"; }
# 输出警告日志。
warn_echo() { color_log $'\033[1;33m' "⚠ $1"; }
# 输出说明日志。
note_echo() { color_log $'\033[1;35m' "➤ $1"; }
# 输出错误日志。
error_echo() { color_log $'\033[1;31m' "✖ $1"; }
# 输出次要日志。
gray_echo() { color_log $'\033[0;90m' "$1"; }
# 输出高亮分隔日志。
highlight_echo() { color_log $'\033[1;36m' "🔹 $1"; }
# 输出一个独立 Commit 故障场景的开始标记和成因。
begin_commit_scenario() {
  local scenario_id="$1"
  local scenario_name="$2"
  local scenario_cause="$3"
  COMMIT_SCENARIO_STEP=$((COMMIT_SCENARIO_STEP + 1))
  highlight_echo "[${COMMIT_SCENARIO_STEP}/${COMMIT_SCENARIO_TOTAL}] ${scenario_id} · ${scenario_name}"
  gray_echo "出现原因：${scenario_cause}"
}
# 输出一个独立 Commit 故障场景的通过标记。
complete_commit_scenario() {
  local scenario_id="$1"
  success_echo "${scenario_id} 检测/处理通过，继续下一项。"
}
# 初始化 zsh 选项、日志与 Sourcetree 输出策略。
initialize_script_runtime() {
  emulate -R zsh
  set -e
  set -o pipefail
  setopt NO_NOMATCH
  export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
  export LANG="${LANG:-zh_CN.UTF-8}"
  export LC_CTYPE="${LC_CTYPE:-UTF-8}"
  : > "$LOG_FILE"
  LOG_READY=1
  configure_output_mode
}
# 展示内置自述，终端模式等待确认，Sourcetree 模式直接继续。
show_script_intro_and_wait() {
  prepare_script_context
  configure_output_mode
  if [[ -z "${NO_COLOR+x}" && "${PLAIN_OUTPUT:-0}" != 1 && "$IS_SOURCETREE_RUNTIME" != "1" && -t 1 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 ==============================" | jobs_intro_style title
  note_echo "脚本名称：${SCRIPT_BASENAME}.command" | jobs_intro_style title
  note_echo "核心行为：把 Commit 阻塞拆成 8 个独立场景，逐项检测/修复，最后验证索引入口已经解锁。" | jobs_intro_style body
  note_echo "路径修复：检测到原文件已变目录，或缺失旧文件已暂存删除/迁移时，只检查和暂存旧文件删除；先 add 新子项后 rm 旧路径的情况会核对并显示已暂存替换，保留新文件、无关修改和部分暂存；--repair-paths 可显式启用，--stage-all 沿用完整暂存。" | jobs_intro_style body
  note_echo "适用场景：Git 异常退出遗留索引锁、普通变更、文件与同名目录转换、缺失子模块工作树、旧 gitlink 删除，以及 .git/core.worktree 路径错位。" | jobs_intro_style body
  note_echo "过滤器修复：先检查 jobs-markdown-toc 的 Node 入口；仅凭本仓一致的安装记录更新失效配置，使用稳定入口并备份。--repair-filters 仅修过滤器，不暂存文件。" | jobs_intro_style body
  note_echo "锁处理策略：锁仍被进程持有时立即停止；只有确认无人占用时才移动到 Git 元数据备份目录。" | jobs_intro_style body
  note_echo "路径迁移：旧 gitlink 已登记但目录已改名时，会同步修复 .gitmodules、core.worktree 和父仓索引。" | jobs_intro_style body
  note_echo "副本修复：已登记到 .gitmodules 的同源子模块副本，会尝试创建独立 gitdir 后继续。" | jobs_intro_style body
  note_echo "子模块策略：缺失时尝试初始化；内部有修改时保持原状并警告，不阻断父仓索引刷新。" | jobs_intro_style body
  note_echo "典型报错：please stage your changes to .gitmodules or stash them to proceed。" | jobs_intro_style body
  note_echo "安全边界：不终止 Git 进程、不直接删除索引锁、不提交、不推送、不暂存子模块内部内容、不主动删除工作区文件。" | jobs_intro_style body
  note_echo "文档关系：同目录 README.md 只作为静态说明，脚本运行时不依赖它。" | jobs_intro_style body
  gray_echo "日志文件：${LOG_FILE}" | jobs_intro_style body
  highlight_echo "=============================================================================" | jobs_intro_style title

  if [[ "$IS_SOURCETREE_RUNTIME" == "1" ]]; then
    gray_echo "已识别 Sourcetree 自定义动作，跳过回车等待。" | jobs_intro_style body | jobs_prompt_filter
    return 0
  fi
  if [[ ! -t 0 ]]; then
    error_echo "当前不是 Sourcetree，且没有可交互输入。"
    exit 1
  fi

  echo "" | jobs_intro_style body
  read -r "?$(jobs_prompt_render "👉 已阅读说明，按回车继续执行；按 Ctrl+C 取消：")" _ || exit 1
}
# 解析兼容的仓库参数与可选修复范围，未知参数在业务前停止。
parse_commit_repair_mode() {
  case "${2:-}" in
    "") COMMIT_REPAIR_MODE="auto" ;;
    --repair-paths) COMMIT_REPAIR_MODE="paths"; PATH_REPAIR_ACTIVE=1 ;;
    --stage-all) COMMIT_REPAIR_MODE="all" ;;
    --repair-filters) COMMIT_REPAIR_MODE="filters"; PATH_REPAIR_ACTIVE=1; COMMIT_SCENARIO_TOTAL=3 ;;
    *) error_echo "未知修复选项：${2}"; return 1 ;;
  esac
  if (( $# > 2 )); then
    error_echo "用法：脚本 [仓库路径] [--repair-paths|--stage-all|--repair-filters]"
    return 1
  fi
}
# 冲突索引不能交给 add -A，否则会把未解决的冲突误标记为已解决。
ensure_no_unmerged_entries() {
  local unmerged="$(git -C "$REPO_ROOT" ls-files -u)"
  if [[ -n "$unmerged" ]]; then
    error_echo "存在未解决冲突，保留索引与工作区，请先解决冲突。"
    return 1
  fi
}
# 自动识别文件变目录及已暂存删除的缺失旧文件，避免 GUI 旧列表触发全量暂存。
select_commit_repair_scope() {
  if [[ "$COMMIT_REPAIR_MODE" == filters ]]; then
    info_echo "已选择仅修过滤器：保留业务索引、正文与子模块状态。"
    return 0
  fi
  ensure_no_unmerged_entries || return 1
  local record="" metadata="" relative_path=""
  local -A indexed_paths
  if [[ "$COMMIT_REPAIR_MODE" == auto ]] && git -C "$REPO_ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
    while IFS= read -r -d '' relative_path; do
      indexed_paths[$relative_path]=1
    done < <(git -C "$REPO_ROOT" ls-files -z)
    while IFS= read -r -d '' record; do
      metadata="${record%%$'\t'*}"
      relative_path="${record#*$'\t'}"
      [[ "$metadata" == 100644\ * || "$metadata" == 100755\ * ]] || continue
      if [[ -d "${REPO_ROOT}/${relative_path}" && ! -L "${REPO_ROOT}/${relative_path}" ]]; then
        PATH_REPAIR_ACTIVE=1
        break
      fi
      if [[ "$relative_path" != .gitmodules && ! -e "${REPO_ROOT}/${relative_path}" &&
            -z "${indexed_paths[$relative_path]:-}" ]] && is_obsolete_index_file "$relative_path"; then
        PATH_REPAIR_ACTIVE=1
        break
      fi
    done < <(git -C "$REPO_ROOT" ls-tree -rz HEAD)
  fi
  if [[ "$PATH_REPAIR_ACTIVE" == 1 ]]; then
    warn_echo "已选择旧路径精确修复：不执行全量 add，不初始化或迁移子模块。"
  else
    warn_echo "已选择原完整修复流程：C06 将暂存当前仓库全部改动。"
  fi
}
# 解析 .git 文件指向的真实 gitdir 路径。
resolve_gitdir_from_git_file() {
  local worktree_root="$1"
  local git_file="${worktree_root}/.git"
  local gitdir_value=""
  local gitdir_path=""

  [[ -f "$git_file" ]] || return 1
  gitdir_value="$(sed -n 's/^gitdir: //p' "$git_file" | head -n 1)"
  [[ -n "$gitdir_value" ]] || return 1
  if [[ "$gitdir_value" == /* ]]; then
    gitdir_path="$gitdir_value"
  else
    gitdir_path="${worktree_root}/${gitdir_value}"
  fi
  print -r -- "${gitdir_path:A}"
}
# 读取 gitdir/config 里登记的 core.worktree 绝对路径。
read_configured_worktree_path() {
  local gitdir_path="$1"
  local configured_worktree=""
  local configured_path=""

  [[ -f "${gitdir_path}/config" ]] || return 1
  configured_worktree="$(git config --file "${gitdir_path}/config" --get core.worktree 2>/dev/null || true)"
  [[ -n "$configured_worktree" ]] || return 1
  if [[ "$configured_worktree" == /* ]]; then
    configured_path="$configured_worktree"
  else
    configured_path="${gitdir_path}/${configured_worktree}"
  fi
  print -r -- "${configured_path:A}"
}
# 将误借用其它 gitdir 的目录转换为独立 Git 工作树。
convert_mislinked_git_file_to_standalone_worktree() {
  local target_abs="$1"
  local gitdir_path="$2"
  local backup_path="${target_abs}/.git.mislinked-backup-$(date +%Y%m%d%H%M%S)"
  local failed_path="${target_abs}/.git.failed-standalone-$(date +%Y%m%d%H%M%S)"

  [[ -f "${target_abs}/.git" && -d "$gitdir_path" ]] || return 1
  warn_echo "正在把错位目录转换为独立 Git 工作树：${target_abs}"
  mv "${target_abs}/.git" "$backup_path" || return 1
  mkdir -p "${target_abs}/.git"
  if ! rsync -a --exclude='fsmonitor--daemon*' "${gitdir_path}/" "${target_abs}/.git/" >> "$LOG_FILE" 2>&1; then
    mv "${target_abs}/.git" "$failed_path" 2>/dev/null || true
    mv "$backup_path" "${target_abs}/.git" 2>/dev/null || true
    error_echo "复制 Git 元数据失败，已恢复原 .git 指针文件：${target_abs}"
    return 1
  fi

  git config --file "${target_abs}/.git/config" --unset core.worktree 2>/dev/null || true
  git config --file "${target_abs}/.git/config" core.bare false
  if [[ "$(git -C "$target_abs" rev-parse --is-inside-work-tree 2>/dev/null || true)" != "true" ]]; then
    mv "${target_abs}/.git" "$failed_path" 2>/dev/null || true
    mv "$backup_path" "${target_abs}/.git" 2>/dev/null || true
    error_echo "独立 Git 工作树验证失败，已恢复原 .git 指针文件：${target_abs}"
    return 1
  fi

  mv "$backup_path" "${target_abs}/.git/$(basename "$backup_path")"
  success_echo "已转换为独立 Git 工作树：${target_abs}"
}
# 判断传入路径是否因目录改名导致 .git 与 core.worktree 指向不一致。
repair_invoked_gitdir_worktree_if_safe() {
  local target="$1"
  local target_abs="${target:A}"
  local gitdir_path=""
  local configured_path=""
  local inside_worktree=""

  [[ -d "$target_abs" && -f "${target_abs}/.git" ]] || return 0
  inside_worktree="$(git -C "$target_abs" rev-parse --is-inside-work-tree 2>/dev/null || true)"
  [[ "$inside_worktree" != "true" ]] || return 0
  gitdir_path="$(resolve_gitdir_from_git_file "$target_abs" 2>/dev/null || true)"
  [[ -n "$gitdir_path" ]] || return 0
  configured_path="$(read_configured_worktree_path "$gitdir_path" 2>/dev/null || true)"
  [[ -n "$configured_path" && "$configured_path" != "$target_abs" ]] || return 0

  if [[ -e "$configured_path" ]]; then
    warn_echo "检测到 Git 工作树路径错位：${target_abs}"
    warn_echo ".git 指向：${gitdir_path}"
    warn_echo "core.worktree 指向：${configured_path}"
    warn_echo "真实工作树仍存在，当前目录将改为独立 Git 工作树，避免 Sourcetree 继续显示 HEAD。"
    convert_mislinked_git_file_to_standalone_worktree "$target_abs" "$gitdir_path"
    return
  fi

  warn_echo "检测到目录改名后的 core.worktree 旧路径失效，正在修正：${target_abs}"
  git config --file "${gitdir_path}/config" core.worktree "$target_abs" || return 1
  success_echo "已修正 core.worktree：${target_abs}"
}
# 从 Sourcetree 参数或当前目录解析待处理路径，但暂不修改 Git 状态。
resolve_target_path() {
  local target="${1:-$PWD}"

  if [[ -f "$target" ]]; then
    target="$(dirname "$target")"
  fi
  if [[ ! -d "$target" ]]; then
    error_echo "目标路径不存在：${target}"
    return 1
  fi

  TARGET_PATH="${target:A}"
  info_echo "待处理路径：${TARGET_PATH}"
}
# 场景 C01：修复当前工作树自身的 .git/core.worktree 错位并识别仓库。
run_commit_scenario_c01_worktree_binding() {
  local scope_selected=0
  begin_commit_scenario "C01" "工作树定位与 gitdir 绑定" "目录改名、Sourcetree 书签指错目录，或 .git 指针仍绑定旧 core.worktree。"
  if REPO_ROOT="$(git -C "$TARGET_PATH" rev-parse --show-toplevel 2>/dev/null)"; then
    select_commit_repair_scope || return 1
    scope_selected=1
  fi
  if [[ "$PATH_REPAIR_ACTIVE" != 1 ]]; then
    repair_invoked_gitdir_worktree_if_safe "$TARGET_PATH"
  fi
  if ! REPO_ROOT="$(git -C "$TARGET_PATH" rev-parse --show-toplevel 2>/dev/null)"; then
    error_echo "目标路径不在 Git 工作树内：${TARGET_PATH}"
    return 1
  fi
  if [[ "$PATH_REPAIR_ACTIVE" == 1 && "$TARGET_PATH" != "${REPO_ROOT:A}" && "$TARGET_PATH" != "${REPO_ROOT:A}/"* ]]; then
    error_echo "路径修复发现工作树绑定错位，保留元数据并停止：${REPO_ROOT}"
    return 1
  fi
  if [[ "$scope_selected" != 1 ]]; then
    select_commit_repair_scope || return 1
  fi

  success_echo "已识别仓库：${REPO_ROOT}"
  complete_commit_scenario "C01"
}
# 列出当前仓库内可能正在修改 Git 索引的进程。
list_active_index_writers() {
  local process_id=""
  local process_cwd=""
  local process_command=""
  local repo_root_abs="${REPO_ROOT:A}"

  command -v pgrep >/dev/null 2>&1 || return 0
  command -v lsof >/dev/null 2>&1 || return 0
  while IFS= read -r process_id; do
    [[ -n "$process_id" && "$process_id" != "$$" ]] || continue
    process_cwd="$(lsof -a -p "$process_id" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)"
    [[ -n "$process_cwd" ]] || continue
    process_cwd="${process_cwd:A}"
    [[ "$process_cwd" == "$repo_root_abs" || "$process_cwd" == "${repo_root_abs}/"* ]] || continue
    process_command="$(ps -p "$process_id" -o command= 2>/dev/null || true)"
    [[ -n "$process_command" ]] || continue
    if printf '%s\n' "$process_command" | grep -Eq '(^|[[:space:]])(add|commit|rm|mv|reset|restore|checkout|switch|merge|rebase|cherry-pick|revert|am|apply|stash|update-index|read-tree|write-tree)([[:space:]]|$)'; then
      printf 'PID %s: %s\n' "$process_id" "$process_command"
    fi
  done < <(pgrep -x git 2>/dev/null || true)
  return 0
}
# 仅在无人占用且没有索引写进程时归档残留 index.lock。
repair_stale_index_lock() {
  local git_dir=""
  local lock_identity_before=""
  local lock_identity_after=""
  local lock_holders=""
  local active_index_writers=""
  local backup_dir=""
  local backup_path=""
  local timestamp=""
  local suffix=0

  git_dir="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  INDEX_LOCK_PATH="${git_dir}/index.lock"
  if [[ ! -e "$INDEX_LOCK_PATH" && ! -L "$INDEX_LOCK_PATH" ]]; then
    info_echo "未检测到 Git 索引锁，继续处理。"
    return 0
  fi
  if [[ -L "$INDEX_LOCK_PATH" || ! -f "$INDEX_LOCK_PATH" ]]; then
    error_echo "索引锁不是普通文件，拒绝自动处理：${INDEX_LOCK_PATH}"
    return 1
  fi
  if ! command -v lsof >/dev/null 2>&1; then
    error_echo "未找到 lsof，无法确认索引锁是否被占用，拒绝自动处理。"
    return 1
  fi

  lock_identity_before="$(stat -f '%d:%i' "$INDEX_LOCK_PATH" 2>/dev/null)" || return 1
  lock_holders="$(lsof -nP -- "$INDEX_LOCK_PATH" 2>/dev/null || true)"
  if [[ -n "$lock_holders" ]]; then
    error_echo "index.lock 正被进程持有，拒绝移动：${INDEX_LOCK_PATH}"
    printf '%s\n' "$lock_holders" | tee -a "$LOG_FILE"
    return 1
  fi
  active_index_writers="$(list_active_index_writers)"
  if [[ -n "$active_index_writers" ]]; then
    error_echo "当前仓库仍有可能修改索引的 Git 进程，拒绝移动 index.lock。"
    printf '%s\n' "$active_index_writers" | tee -a "$LOG_FILE"
    return 1
  fi
  lock_identity_after="$(stat -f '%d:%i' "$INDEX_LOCK_PATH" 2>/dev/null)" || return 1
  if [[ "$lock_identity_before" != "$lock_identity_after" ]]; then
    error_echo "检测期间 index.lock 已发生变化，拒绝自动处理。"
    return 1
  fi

  timestamp="$(date +%Y%m%d-%H%M%S)"
  backup_dir="${git_dir}/jobs-stale-lock-backups"
  backup_path="${backup_dir}/index.lock.${timestamp}.stale"
  while [[ -e "$backup_path" ]]; do
    suffix=$((suffix + 1))
    backup_path="${backup_dir}/index.lock.${timestamp}.${suffix}.stale"
  done
  mkdir -p "$backup_dir"
  mv "$INDEX_LOCK_PATH" "$backup_path"
  if ! git -C "$REPO_ROOT" ls-files --stage >/dev/null 2>&1; then
    mv "$backup_path" "$INDEX_LOCK_PATH" 2>/dev/null || true
    error_echo "现有 Git 索引无法读取，已恢复 index.lock，拒绝继续暂存。"
    return 1
  fi

  success_echo "已归档无人占用的残留 index.lock：${backup_path}"
}
# 场景 C02：识别活锁与残留 index.lock，只归档已经确认无人占用的残留锁。
run_commit_scenario_c02_index_lock() {
  begin_commit_scenario "C02" "索引锁阻塞" "Git 索引写进程仍在运行，或异常退出后遗留 .git/index.lock。"
  if [[ "$PATH_REPAIR_ACTIVE" == 1 ]]; then
    INDEX_LOCK_PATH="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)/index.lock"
    if [[ -e "$INDEX_LOCK_PATH" || -L "$INDEX_LOCK_PATH" ]]; then
      error_echo "路径修复保留现有 index.lock，请等待索引写操作结束：${INDEX_LOCK_PATH}"
      return 1
    fi
    complete_commit_scenario "C02"
    return 0
  fi
  repair_stale_index_lock
  complete_commit_scenario "C02"
}
# 收集父仓索引中真实登记的 gitlink 路径。
collect_gitlink_paths() {
  GITLINK_PATHS=()
  local entry=""
  local entries=""
  local mode=""
  local submodule_path=""

  entries="$(git -C "$REPO_ROOT" ls-files -s -z)" || {
    error_echo "无法读取 gitlink 索引，已停止。"
    return 1
  }
  while IFS= read -r -d '' entry; do
    mode="${entry%% *}"
    [[ "$mode" == "160000" ]] || continue
    submodule_path="${entry#*$'\t'}"
    [[ -n "$submodule_path" ]] && GITLINK_PATHS+=("$submodule_path")
  done < <(print -rn -- "$entries")
}
# 判断 gitlink 是否在 .gitmodules 中有可用的路径和 URL 配置。
submodule_has_valid_config() {
  local submodule_path="$1"
  local key=""
  local configured_path=""
  local section=""
  local url=""

  [[ -f "${REPO_ROOT}/.gitmodules" ]] || return 1
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    configured_path="$(git -C "$REPO_ROOT" config --file .gitmodules --get "$key" 2>/dev/null || true)"
    [[ "$configured_path" == "$submodule_path" ]] || continue
    section="${key#submodule.}"
    section="${section%.path}"
    url="$(git -C "$REPO_ROOT" config --file .gitmodules --get "submodule.${section}.url" 2>/dev/null || true)"
    [[ -n "$url" ]]
    return
  done < <(git -C "$REPO_ROOT" config --file .gitmodules --name-only --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)

  return 1
}
# 读取 .gitmodules 中指定子模块路径对应的 URL。
submodule_config_url() {
  local submodule_path="$1"
  local key=""
  local configured_path=""
  local section=""
  local url=""

  [[ -f "${REPO_ROOT}/.gitmodules" ]] || return 1
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    configured_path="$(git -C "$REPO_ROOT" config --file .gitmodules --get "$key" 2>/dev/null || true)"
    [[ "$configured_path" == "$submodule_path" ]] || continue
    section="${key#submodule.}"
    section="${section%.path}"
    url="$(git -C "$REPO_ROOT" config --file .gitmodules --get "submodule.${section}.url" 2>/dev/null || true)"
    [[ -n "$url" ]] || return 1
    print -r -- "$url"
    return 0
  done < <(git -C "$REPO_ROOT" config --file .gitmodules --name-only --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)

  return 1
}
# 计算父仓 .git/modules 下某个子模块路径应该使用的 gitdir。
submodule_gitdir_path() {
  local submodule_path="$1"
  local modules_root=""

  modules_root="$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null || true)"
  [[ -n "$modules_root" ]] || return 1
  [[ "$modules_root" == /* ]] || modules_root="${REPO_ROOT}/${modules_root}"
  print -r -- "${modules_root:A}/modules/${submodule_path}"
}
# 判断相对路径是否是父仓索引登记的 gitlink。
is_index_gitlink_path() {
  local relative_path="$1"
  local submodule_path=""

  for submodule_path in "${GITLINK_PATHS[@]}"; do
    [[ "$submodule_path" == "$relative_path" ]] && return 0
  done

  return 1
}
# 查找 .gitmodules 中唯一匹配指定路径的配置键。
find_submodule_path_key() {
  local submodule_path="$1"
  local key=""
  local configured_path=""
  local matched_key=""
  local matches=0

  [[ -f "${REPO_ROOT}/.gitmodules" ]] || return 1
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    configured_path="$(git -C "$REPO_ROOT" config --file .gitmodules --get "$key" 2>/dev/null || true)"
    [[ "$configured_path" == "$submodule_path" ]] || continue
    matched_key="$key"
    matches=$((matches + 1))
  done < <(git -C "$REPO_ROOT" config --file .gitmodules --name-only --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)

  [[ "$matches" -eq 1 ]] || return 1
  print -r -- "$matched_key"
}
# 回滚尚未完成的子模块路径自动修复元数据。
rollback_unstaged_submodule_path_migration() {
  local path_key="$1"
  local old_relative_path="$2"
  local gitdir_path="$3"
  local old_core_worktree="$4"

  git -C "$REPO_ROOT" config --file .gitmodules "$path_key" "$old_relative_path" || return 1
  git config --file "${gitdir_path}/config" core.worktree "$old_core_worktree" || return 1
  git -C "$REPO_ROOT" add -A -- .gitmodules || return 1
}
# 自动收口旧 gitlink 已登记、工作树已直接改名但尚未暂存的新路径。
repair_unstaged_submodule_path_migration() {
  local relative_path="$1"
  local candidate_root="$2"
  local gitdir_path="$3"
  local configured_path="$4"
  local repo_root_abs="${REPO_ROOT:A}"
  local old_relative_path=""
  local path_key=""
  local old_url=""
  local gitdir_url=""
  local old_core_worktree=""

  [[ ! -e "$configured_path" ]] || return 1
  [[ "$configured_path" == "${repo_root_abs}/"* ]] || return 1
  old_relative_path="${configured_path#${repo_root_abs}/}"
  [[ -n "$old_relative_path" && "$old_relative_path" != "$relative_path" ]] || return 1
  is_index_gitlink_path "$old_relative_path" || return 1
  submodule_has_valid_config "$old_relative_path" || return 1
  submodule_has_valid_config "$relative_path" && return 1
  path_key="$(find_submodule_path_key "$old_relative_path" 2>/dev/null || true)"
  [[ -n "$path_key" ]] || return 1
  old_url="$(submodule_config_url "$old_relative_path" 2>/dev/null || true)"
  gitdir_url="$(git config --file "${gitdir_path}/config" --get remote.origin.url 2>/dev/null || true)"
  [[ -n "$old_url" && "$old_url" == "$gitdir_url" ]] || return 1
  old_core_worktree="$(git config --file "${gitdir_path}/config" --get core.worktree 2>/dev/null || true)"
  [[ -n "$old_core_worktree" ]] || return 1

  warn_echo "检测到未完成的子模块目录迁移：${old_relative_path} -> ${relative_path}"
  info_echo "正在同步修复 .gitmodules、core.worktree 与父仓 gitlink。"
  if ! git -C "$REPO_ROOT" config --file .gitmodules "$path_key" "$relative_path"; then
    error_echo "更新 .gitmodules 子模块路径失败：${relative_path}"
    return 1
  fi
  if ! git config --file "${gitdir_path}/config" core.worktree "$candidate_root"; then
    rollback_unstaged_submodule_path_migration "$path_key" "$old_relative_path" "$gitdir_path" "$old_core_worktree" || true
    error_echo "更新子模块 core.worktree 失败，已尝试回滚：${relative_path}"
    return 1
  fi
  if ! is_valid_submodule_worktree "$relative_path"; then
    rollback_unstaged_submodule_path_migration "$path_key" "$old_relative_path" "$gitdir_path" "$old_core_worktree" || true
    error_echo "迁移后的子模块工作树验证失败，已尝试回滚：${relative_path}"
    return 1
  fi
  if ! git -C "$REPO_ROOT" -c advice.addEmbeddedRepo=false add -A -- .gitmodules "$old_relative_path" "$relative_path"; then
    error_echo "父仓 gitlink 迁移暂存失败，请核对索引：${old_relative_path} -> ${relative_path}"
    return 1
  fi

  success_echo "已自动修复子模块目录迁移：${old_relative_path} -> ${relative_path}"
}
# 根据 HEAD 与当前 .gitmodules 的同一 section，识别子模块路径迁移。
find_migrated_submodule_path() {
  local old_path="$1"
  local key=""
  local head_path=""
  local section=""
  local current_path=""

  git -C "$REPO_ROOT" cat-file -e 'HEAD:.gitmodules' 2>/dev/null || return 1
  [[ -f "${REPO_ROOT}/.gitmodules" ]] || return 1
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    head_path="$(git -C "$REPO_ROOT" config --blob HEAD:.gitmodules --get "$key" 2>/dev/null || true)"
    [[ "$head_path" == "$old_path" ]] || continue
    section="${key#submodule.}"
    section="${section%.path}"
    current_path="$(git -C "$REPO_ROOT" config --file .gitmodules --get "submodule.${section}.path" 2>/dev/null || true)"
    if [[ -n "$current_path" && "$current_path" != "$old_path" ]]; then
      printf '%s\n' "$current_path"
      return 0
    fi
  done < <(git -C "$REPO_ROOT" config --blob HEAD:.gitmodules --name-only --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)

  return 1
}
# 修正直接移动子模块目录后仍指向旧路径的 core.worktree。
repair_migrated_submodule_worktree() {
  local submodule_path="$1"
  local child_root="${REPO_ROOT}/${submodule_path}"
  local git_file="${child_root}/.git"
  local gitdir_value=""
  local gitdir_path=""
  local modules_root=""

  is_valid_submodule_worktree "$submodule_path" && return 0
  [[ -f "$git_file" ]] || return 1
  gitdir_value="$(sed -n 's/^gitdir: //p' "$git_file" | head -n 1)"
  [[ -n "$gitdir_value" ]] || return 1
  if [[ "$gitdir_value" == /* ]]; then
    gitdir_path="$gitdir_value"
  else
    gitdir_path="${child_root}/${gitdir_value}"
  fi
  gitdir_path="${gitdir_path:A}"
  modules_root="$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null || true)"
  [[ -n "$modules_root" ]] || return 1
  [[ "$modules_root" == /* ]] || modules_root="${REPO_ROOT}/${modules_root}"
  modules_root="${modules_root:A}/modules"
  [[ "$gitdir_path" == "${modules_root}/"* && -f "${gitdir_path}/config" ]] || return 1

  git config --file "${gitdir_path}/config" core.worktree "$child_root" || return 1
  if is_valid_submodule_worktree "$submodule_path"; then
    success_echo "已修正子模块 core.worktree：${submodule_path}"
    return 0
  fi

  return 1
}
# 判断子模块路径是否已经是有效 Git 工作树。
is_valid_submodule_worktree() {
  local submodule_path="$1"
  local child_root="${REPO_ROOT}/${submodule_path}"
  local actual_root=""
  [[ -d "$child_root" && -e "${child_root}/.git" ]] || return 1
  actual_root="$(git -C "$child_root" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$actual_root" && "${actual_root:A}" == "${child_root:A}" ]]
}
# 将已登记到 .gitmodules 的同源子模块副本改成独立 gitdir，避免共用旧路径元数据。
repair_configured_submodule_alias_copy() {
  local relative_path="$1"
  local candidate_root="$2"
  local borrowed_gitdir="$3"
  local target_url=""
  local borrowed_url=""
  local new_gitdir=""
  local backup_git_file=""
  local failed_git_file=""
  local failed_gitdir=""
  local copied_gitdir=0

  target_url="$(submodule_config_url "$relative_path" 2>/dev/null || true)"
  [[ -n "$target_url" && -f "${borrowed_gitdir}/config" ]] || return 1
  borrowed_url="$(git config --file "${borrowed_gitdir}/config" --get remote.origin.url 2>/dev/null || true)"
  [[ -n "$borrowed_url" && "$borrowed_url" == "$target_url" ]] || return 1
  new_gitdir="$(submodule_gitdir_path "$relative_path" 2>/dev/null || true)"
  [[ -n "$new_gitdir" && "$new_gitdir" != "$borrowed_gitdir" ]] || return 1
  if ! command -v rsync >/dev/null 2>&1; then
    error_echo "未找到 rsync，无法为子模块副本复制独立 gitdir：${relative_path}"
    return 1
  fi

  warn_echo "检测到 ${relative_path} 已登记到 .gitmodules，但仍借用旧 gitdir，正在创建独立 gitdir。"
  gray_echo "旧 gitdir：${borrowed_gitdir}"
  gray_echo "新 gitdir：${new_gitdir}"
  if [[ -e "$new_gitdir" || -L "$new_gitdir" ]]; then
    error_echo "目标 gitdir 已存在，保留已有元数据；请先人工核对归属：${new_gitdir}"
    return 1
  fi
  if [[ ! -d "$new_gitdir" ]]; then
    mkdir -p "${new_gitdir:h}" || return 1
    if ! rsync -a --exclude='fsmonitor--daemon*' "${borrowed_gitdir}/" "${new_gitdir}/" >> "$LOG_FILE" 2>&1; then
      failed_gitdir="${new_gitdir}.failed-alias-$(date +%Y%m%d%H%M%S)"
      mv "$new_gitdir" "$failed_gitdir" 2>/dev/null || true
      error_echo "复制子模块 Git 元数据失败，已停止：${relative_path}"
      [[ -n "$failed_gitdir" ]] && warn_echo "失败残留已转存：${failed_gitdir}"
      return 1
    fi
    copied_gitdir=1
  fi

  git config --file "${new_gitdir}/config" core.worktree "$candidate_root" || return 1
  git config --file "${new_gitdir}/config" core.bare false
  backup_git_file="${candidate_root}/.git.alias-backup-$(date +%Y%m%d%H%M%S)"
  failed_git_file="${candidate_root}/.git.failed-alias-$(date +%Y%m%d%H%M%S)"
  mv "${candidate_root}/.git" "$backup_git_file" || return 1
  printf 'gitdir: %s\n' "$new_gitdir" > "${candidate_root}/.git"

  if is_valid_submodule_worktree "$relative_path"; then
    mv "$backup_git_file" "${new_gitdir}/$(basename "$backup_git_file")" 2>/dev/null || true
    success_echo "已为子模块副本创建独立 gitdir：${relative_path}"
    return 0
  fi

  mv "${candidate_root}/.git" "$failed_git_file" 2>/dev/null || true
  mv "$backup_git_file" "${candidate_root}/.git" 2>/dev/null || true
  if [[ "$copied_gitdir" == "1" ]]; then
    failed_gitdir="${new_gitdir}.failed-alias-$(date +%Y%m%d%H%M%S)"
    mv "$new_gitdir" "$failed_gitdir" 2>/dev/null || true
    warn_echo "新 gitdir 验证失败，已转存：${failed_gitdir}"
  fi
  error_echo "子模块副本独立 gitdir 验证失败，已恢复原 .git 指针：${relative_path}"
  return 1
}
# 扫描嵌套 .git 文件，阻止 Sourcetree 把错位副本当作可提交路径。
preflight_gitdir_worktree_aliases() {
  collect_gitlink_paths
  local git_file=""
  local candidate_root=""
  local relative_path=""
  local gitdir_path=""
  local configured_path=""
  local inside_worktree=""
  local failures=0

  while IFS= read -r -d '' git_file; do
    candidate_root="$(dirname "$git_file")"
    [[ "${candidate_root:A}" == "${REPO_ROOT:A}" ]] && continue
    relative_path="${candidate_root#${REPO_ROOT}/}"
    inside_worktree="$(git -C "$candidate_root" rev-parse --is-inside-work-tree 2>/dev/null || true)"
    [[ "$inside_worktree" == "true" ]] && continue
    gitdir_path="$(resolve_gitdir_from_git_file "$candidate_root" 2>/dev/null || true)"
    [[ -n "$gitdir_path" ]] || continue
    configured_path="$(read_configured_worktree_path "$gitdir_path" 2>/dev/null || true)"
    [[ -n "$configured_path" && "$configured_path" != "${candidate_root:A}" ]] || continue

    if repair_unstaged_submodule_path_migration "$relative_path" "$candidate_root" "$gitdir_path" "$configured_path"; then
      continue
    fi
    if is_index_gitlink_path "$relative_path"; then
      if repair_migrated_submodule_worktree "$relative_path"; then
        continue
      fi
    fi
    if repair_configured_submodule_alias_copy "$relative_path" "$candidate_root" "$gitdir_path"; then
      continue
    fi

    error_echo "检测到错位 Git 工作树副本，已停止暂存：${relative_path}"
    warn_echo ".git 指向：${gitdir_path}"
    warn_echo "core.worktree 指向：${configured_path}"
    if [[ -e "$configured_path" ]]; then
      warn_echo "真实工作树仍存在：${configured_path}"
      warn_echo "请在 Sourcetree 打开真实工作树，并手动处理当前异常目录：${candidate_root}"
    else
      warn_echo "core.worktree 指向的旧路径不存在，但当前路径不是父仓登记的 gitlink，脚本不会擅自接管。"
    fi
    failures=$((failures + 1))
  done < <(find "$REPO_ROOT" \
    \( -path "${REPO_ROOT}/.git" -o -path '*/.git/*' -o -path '*/node_modules/*' -o -path '*/Pods/*' -o -path '*/.dart_tool/*' -o -path '*/build/*' -o -path '*/DerivedData/*' \) -prune \
    -o -type f -name .git -print0)

  if [[ "$failures" -gt 0 ]]; then
    error_echo "共有 ${failures} 个 .git/core.worktree 路径错位，未执行 git add -A。"
    return 1
  fi
}
# 场景 C04：扫描并收口嵌套工作树、子模块副本及未完成路径迁移。
run_commit_scenario_c04_nested_worktrees() {
  if [[ "$PATH_REPAIR_ACTIVE" == 1 ]]; then
    begin_commit_scenario "C04" "嵌套工作树保护" "本轮只修复旧文件索引，不需要修复嵌套元数据。"
    info_echo "C04 跳过：路径修复不改嵌套工作树元数据。"
    complete_commit_scenario "C04"
    return 0
  fi
  begin_commit_scenario "C04" "嵌套工作树与路径迁移" "子模块目录被移动/复制后，.git 指针、core.worktree、.gitmodules 与父仓 gitlink 没有同步。"
  preflight_gitdir_worktree_aliases
  complete_commit_scenario "C04"
}
# 判断子模块路径是否只是上次失败初始化留下的空目录。
is_empty_submodule_directory() {
  local submodule_path="$1"
  local child_root="${REPO_ROOT}/${submodule_path}"
  [[ -d "$child_root" ]] || return 1
  [[ -z "$(find "$child_root" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]
}
# 输出子模块内部变更，并说明父仓索引刷新仍会继续。
report_dirty_submodule() {
  local submodule_path="$1"
  warn_echo "子模块内部存在未提交修改，保持原状并继续父仓暂存：${submodule_path}"
  git -C "${REPO_ROOT}/${submodule_path}" status --short --untracked-files=all 2>/dev/null | sed 's/^/  /' | tee -a "$LOG_FILE"
  gray_echo "父仓提交不会包含这些工作区内容；请在对应子模块中单独处理。"
}
# 对本轮初始化后留下的半成品工作树做安全收口。
recover_new_submodule_worktree() {
  local submodule_path="$1"
  local child_root="${REPO_ROOT}/${submodule_path}"
  local expected_sha=""
  local current_sha=""

  is_valid_submodule_worktree "$submodule_path" || return 1
  expected_sha="$(git -C "$REPO_ROOT" ls-files -s -- "$submodule_path" | awk '$1 == 160000 { print $2; exit }')"
  current_sha="$(git -C "$child_root" rev-parse HEAD 2>/dev/null || true)"
  [[ -n "$current_sha" ]] || return 1

  if [[ -n "$expected_sha" ]] && git -C "$child_root" cat-file -e "${expected_sha}^{commit}" 2>/dev/null; then
    git -C "$child_root" checkout --detach "$expected_sha" >> "$LOG_FILE" 2>&1 || return 1
    current_sha="$expected_sha"
  else
    warn_echo "父仓锁定的子模块提交已不可用：${submodule_path} ${expected_sha:-unknown}"
    warn_echo "已保留新克隆工作树的当前有效 HEAD：${current_sha}"
  fi

  git -C "$child_root" restore --source=HEAD --staged --worktree -- . || return 1
  if [[ -n "$(git -C "$child_root" status --porcelain --untracked-files=all)" ]]; then
    return 1
  fi

  success_echo "子模块工作树已收口为 clean：${submodule_path} @ ${current_sha}"
}
# 判断 .gitmodules 是否已经在索引中记录变更。
gitmodules_has_staged_change() {
  ! git -C "$REPO_ROOT" diff --cached --quiet -- .gitmodules 2>/dev/null
}
# 判断旧 gitlink 是否已从当前 .gitmodules 移除，允许后续 git add -A 暂存删除。
is_retired_gitlink_after_gitmodules_change() {
  local submodule_path="$1"
  local child_root="${REPO_ROOT}/${submodule_path}"

  gitmodules_has_staged_change || return 1
  submodule_has_valid_config "$submodule_path" && return 1
  [[ ! -e "$child_root" ]] || is_empty_submodule_directory "$submodule_path"
}
# 初始化缺失子模块，并防止缺失 gitlink 被误暂存为删除。
ensure_submodule_worktree() {
  local submodule_path="$1"

  if is_valid_submodule_worktree "$submodule_path"; then
    return 0
  fi
  if [[ -e "${REPO_ROOT}/${submodule_path}" ]] && ! is_empty_submodule_directory "$submodule_path"; then
    error_echo "子模块路径已存在，但不是有效 Git 工作树：${submodule_path}"
    return 1
  fi
  if ! submodule_has_valid_config "$submodule_path"; then
    error_echo "gitlink 缺少有效 .gitmodules 配置，不会将它暂存为删除：${submodule_path}"
    return 1
  fi

  warn_echo "检测到缺失子模块工作树，正在按父仓登记尝试初始化：${submodule_path}"
  if git -C "$REPO_ROOT" submodule update --init --recursive -- "$submodule_path" 2>&1 | tee -a "$LOG_FILE"; then
    success_echo "子模块已初始化：${submodule_path}"
    return 0
  fi

  warn_echo "按父仓锁定提交初始化失败，检查是否为远端历史重写。"
  if recover_new_submodule_worktree "$submodule_path"; then
    return 0
  fi

  error_echo "子模块无法安全恢复，已中止：${submodule_path}"
  return 1
}
# 在全量暂存前检查所有 gitlink，子模块不安全时整体中止。
preflight_submodules() {
  collect_gitlink_paths
  if [[ ${#GITLINK_PATHS[@]} -eq 0 ]]; then
    info_echo "当前仓库没有 Git 子模块。"
    return 0
  fi

  info_echo "检测到 ${#GITLINK_PATHS[@]} 个 Git 子模块，开始安全检查。"
  local submodule_path=""
  local effective_path=""
  local migrated_path=""
  local failures=0
  local dirty_submodules=0
  for submodule_path in "${GITLINK_PATHS[@]}"; do
    effective_path="$submodule_path"
    migrated_path="$(find_migrated_submodule_path "$submodule_path" 2>/dev/null || true)"
    if [[ -n "$migrated_path" ]]; then
      effective_path="$migrated_path"
      warn_echo "检测到子模块路径迁移：${submodule_path} -> ${effective_path}"
      if ! repair_migrated_submodule_worktree "$effective_path"; then
        error_echo "新路径不是有效子模块工作树，已停止：${effective_path}"
        failures=$((failures + 1))
        continue
      fi
    else
      if is_retired_gitlink_after_gitmodules_change "$submodule_path"; then
        warn_echo "检测到旧 gitlink 已从当前 .gitmodules 移除，稍后由 git add -A 暂存删除：${submodule_path}"
        continue
      fi
      if ! ensure_submodule_worktree "$submodule_path"; then
        failures=$((failures + 1))
        continue
      fi
    fi
    if [[ -n "$(git -C "${REPO_ROOT}/${effective_path}" status --porcelain --untracked-files=all)" ]]; then
      report_dirty_submodule "$effective_path"
      dirty_submodules=$((dirty_submodules + 1))
      continue
    fi
    success_echo "子模块检查通过：${effective_path}"
  done

  if [[ "$failures" -gt 0 ]]; then
    error_echo "共有 ${failures} 个子模块未通过检查，未执行 git add -A。"
    return 1
  fi
  if [[ "$dirty_submodules" -gt 0 ]]; then
    warn_echo "共有 ${dirty_submodules} 个子模块保留了内部修改，继续刷新父仓 Git 索引。"
  fi
}
# 场景 C05：检查缺失、迁移、退役或带内部修改的子模块工作树。
run_commit_scenario_c05_submodules() {
  if [[ "$PATH_REPAIR_ACTIVE" == 1 ]]; then
    begin_commit_scenario "C05" "子模块保护" "本轮不需要初始化或迁移子模块。"
    info_echo "C05 跳过：路径修复保留所有 gitlink 和子模块。"
    complete_commit_scenario "C05"
    return 0
  fi
  begin_commit_scenario "C05" "子模块工作树与 gitlink 一致性" "父仓 gitlink、.gitmodules 和子模块工作树状态不一致，或父仓锁定提交已经不可用。"
  preflight_submodules
  complete_commit_scenario "C05"
}
# 在删除或迁移 gitlink 前优先暂存 .gitmodules，满足 Git 的子模块安全校验顺序。
stage_gitmodules_first() {
  local gitmodules_status=""

  if [[ ! -e "${REPO_ROOT}/.gitmodules" ]] && ! git -C "$REPO_ROOT" ls-files --error-unmatch .gitmodules >/dev/null 2>&1; then
    return 0
  fi
  gitmodules_status="$(git -C "$REPO_ROOT" status --porcelain -- .gitmodules 2>/dev/null || true)"
  [[ -n "$gitmodules_status" ]] || return 0

  if git -C "$REPO_ROOT" diff --quiet -- .gitmodules 2>/dev/null && gitmodules_has_staged_change; then
    info_echo ".gitmodules 已在索引中记录变更，继续处理 gitlink 删除/迁移。"
    return 0
  fi

  info_echo "检测到 .gitmodules 变更，正在优先写入索引 ..."
  gray_echo "典型场景：Sourcetree 先执行 git rm -q -f -- 旧子模块时，Git 会要求先暂存 .gitmodules。"
  git -C "$REPO_ROOT" add -A -- .gitmodules
  success_echo ".gitmodules 已优先暂存，可安全处理后续 gitlink 变更。"
}
# 场景 C03：先让 .gitmodules 与待删除或迁移的 gitlink 建立正确索引顺序。
run_commit_scenario_c03_gitmodules_order() {
  if [[ "$PATH_REPAIR_ACTIVE" == 1 ]]; then
    begin_commit_scenario "C03" ".gitmodules 保护" "普通旧文件删除无需改变子模块配置。"
    info_echo "C03 跳过：路径修复不改变 .gitmodules 的暂存内容。"
    complete_commit_scenario "C03"
    return 0
  fi
  begin_commit_scenario "C03" ".gitmodules 暂存顺序" "Sourcetree 先删除/迁移 gitlink，但 .gitmodules 的对应路径变化尚未进入索引。"
  stage_gitmodules_first
  complete_commit_scenario "C03"
}
# 清理本轮临时索引与自己持有的锁，保留可恢复备份。
cleanup_path_repair() {
  [[ -z "$PATH_REPAIR_TEMP" ]] || /bin/rm -f -- "$PATH_REPAIR_TEMP"
  if [[ "$PATH_REPAIR_LOCK_OWNED" == 1 ]]; then
    /bin/rm -f -- "$PATH_REPAIR_LOCK"
    PATH_REPAIR_LOCK_OWNED=0
  fi
}
# 检查旧文件确已缺失或变真实目录；祖先必须仍为真实目录，不穿越符号链接或文件。
is_obsolete_index_file() {
  local relative_path="$1" parent_path="${1:h}" absolute_parent=""
  while [[ "$parent_path" != . ]]; do
    absolute_parent="${REPO_ROOT}/${parent_path}"
    [[ ! -L "$absolute_parent" ]] || return 1
    [[ ! -e "$absolute_parent" || -d "$absolute_parent" ]] || return 1
    parent_path="${parent_path:h}"
  done
  [[ ! -L "${REPO_ROOT}/${relative_path}" && ( ! -e "${REPO_ROOT}/${relative_path}" || -d "${REPO_ROOT}/${relative_path}" ) ]]
}
# 对账 HEAD 旧文件与索引子树，指出先 add 后 rm 时已完成的文件变目录替换。
report_staged_directory_replacements() {
  local snapshot="$1" index_records="" added_records="" head_records="" record="" metadata="" relative_path="" parent_path="" child_count=0
  local -A indexed_paths indexed_descendants
  git -C "$REPO_ROOT" rev-parse --verify HEAD >/dev/null 2>&1 || return 0
  index_records="$(GIT_INDEX_FILE="$snapshot" git -C "$REPO_ROOT" ls-files --stage -z)" || return 1
  added_records="$(GIT_INDEX_FILE="$snapshot" git -C "$REPO_ROOT" diff --cached --no-renames --ita-invisible-in-index --diff-filter=A --name-only -z)" || return 1
  head_records="$(git -C "$REPO_ROOT" ls-tree -rz HEAD)" || return 1
  for record in "${(@0)index_records}"; do
    [[ -n "$record" ]] || continue
    relative_path="${record#*$'\t'}"
    indexed_paths[$relative_path]=1
  done
  for relative_path in "${(@0)added_records}"; do
    [[ -n "$relative_path" ]] || continue
    parent_path="${relative_path:h}"
    while [[ "$parent_path" != . ]]; do
      indexed_descendants[$parent_path]=$(( ${indexed_descendants[$parent_path]:-0} + 1 ))
      parent_path="${parent_path:h}"
    done
  done
  for record in "${(@0)head_records}"; do
    metadata="${record%%$'\t'*}"
    relative_path="${record#*$'\t'}"
    [[ "$metadata" == 100644\ * || "$metadata" == 100755\ * ]] || continue
    [[ -z "${indexed_paths[$relative_path]:-}" && -d "${REPO_ROOT}/${relative_path}" ]] || continue
    is_obsolete_index_file "$relative_path" || continue
    child_count="${indexed_descendants[$relative_path]:-0}"
    (( child_count > 0 )) || continue
    info_echo "已暂存文件变目录：${relative_path}（旧文件条目已移除，新目录已有 ${child_count} 个索引子项）。"
    gray_echo "前序 git add 已记录此替换；后续 git rm 旧路径会匹配新子项，without -r 不代表旧条目仍待删除。"
    warn_echo "不要补 -r（包括 git rm --cached -r）或重跑旧删除队列；保留当前暂存选择，刷新 Sourcetree 后核对。"
  done
  return 0
}
# 在独占锁和索引备份保护下，只移除未暂存过且确已消失的普通旧文件条目。
repair_sourcetree_obsolete_paths() {
  local index_path="" backup_path="" snapshot="" record="" metadata="" relative_path="" flag="" candidate="" entry_i=0
  local -a candidates expected_entries actual_entries
  local -A protected_paths
  index_path="$(git -C "$REPO_ROOT" rev-parse --path-format=absolute --git-path index)" || return 1
  if [[ ! -f "$index_path" || -L "$index_path" ]]; then
    error_echo "路径修复需要现有普通索引文件：${index_path}"
    return 1
  fi
  PATH_REPAIR_LOCK="${index_path}.lock"
  if ! ( setopt NO_CLOBBER; : > "$PATH_REPAIR_LOCK" ) 2>/dev/null; then
    error_echo "无法取得索引锁，保留现状：${PATH_REPAIR_LOCK}"
    return 1
  fi
  PATH_REPAIR_LOCK_OWNED=1
  trap 'cleanup_path_repair' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  PATH_REPAIR_TEMP="$(mktemp "${index_path}.jobs-paths.XXXXXX")" || return 1
  snapshot="$(mktemp "${index_path}.jobs-paths-before.XXXXXX")" || return 1
  /bin/cp -p -- "$index_path" "$snapshot" || return 1
  /bin/cp -p -- "$snapshot" "$PATH_REPAIR_TEMP" || return 1
  backup_path="$snapshot"
  info_echo "原索引备份：${backup_path}"
  report_staged_directory_replacements "$snapshot" || return 1
  while IFS= read -r -d '' record; do
    flag="${record[1]}"
    [[ "$flag" == H ]] || protected_paths["${record[3,-1]}"]=1
  done < <(GIT_INDEX_FILE="$snapshot" git -C "$REPO_ROOT" ls-files -v -z)
  while IFS= read -r -d '' record; do
    metadata="${record[3,-1]}"
    metadata="${metadata%%$'\t'*}"
    relative_path="${record#*$'\t'}"
    if [[ ( "$metadata" == 100644\ *\ 0 || "$metadata" == 100755\ *\ 0 ) &&
          "$relative_path" != .gitmodules && -z "${protected_paths["$relative_path"]:-}" ]] && is_obsolete_index_file "$relative_path"; then
      if GIT_INDEX_FILE="$snapshot" git -C "$REPO_ROOT" diff --cached --quiet --ita-visible-in-index -- ":(literal)${relative_path}"; then
        candidates+=("$relative_path")
        continue
      fi
      warn_echo "保留已有暂存内容的旧路径：${relative_path}"
    fi
    expected_entries+=("$record")
  done < <(GIT_INDEX_FILE="$snapshot" git -C "$REPO_ROOT" ls-files -v --stage -z)
  if (( ${#candidates[@]} == 0 )); then
    info_echo "没有可安全移除的旧索引条目；本轮未改写真实索引。请刷新 Sourcetree 文件状态并取消旧选择，核对已暂存内容。"
    cleanup_path_repair
    return 0
  fi
  for candidate in "${candidates[@]}"; do
    info_echo "仅暂存旧文件删除：${candidate}"
  done
  if ! printf '%s\0' "${candidates[@]}" | GIT_INDEX_FILE="$PATH_REPAIR_TEMP" git -C "$REPO_ROOT" update-index --force-remove -z --stdin; then
    error_echo "临时索引修复失败，真实索引保持原样。"
    return 1
  fi
  while IFS= read -r -d '' record; do
    actual_entries+=("$record")
  done < <(GIT_INDEX_FILE="$PATH_REPAIR_TEMP" git -C "$REPO_ROOT" ls-files -v --stage -z)
  if (( ${#expected_entries[@]} != ${#actual_entries[@]} )); then
    error_echo "临时索引条目校验失败，真实索引保持原样。"
    return 1
  fi
  for (( entry_i=1; entry_i<=${#expected_entries[@]}; entry_i++ )); do
    if [[ "${expected_entries[$entry_i]}" != "${actual_entries[$entry_i]}" ]]; then
      error_echo "临时索引内容或 flags 发生意外变化，真实索引保持原样。"
      return 1
    fi
  done
  for candidate in "${candidates[@]}"; do
    if ! is_obsolete_index_file "$candidate"; then
      error_echo "工作区路径在检测后发生变化，保留真实索引：${candidate}"
      return 1
    fi
  done
  if ! /usr/bin/cmp -s -- "$snapshot" "$index_path"; then
    error_echo "真实索引发生并发变化，停止写回；备份：${backup_path}"
    return 1
  fi
  /bin/cp -p -- "$PATH_REPAIR_TEMP" "$PATH_REPAIR_LOCK" || return 1
  /bin/mv -f -- "$PATH_REPAIR_LOCK" "$index_path" || return 1
  PATH_REPAIR_LOCK_OWNED=0
  cleanup_path_repair
  success_echo "已精确暂存 ${#candidates[@]} 个旧文件删除；新目录及其它暂存内容保持原样。"
}
# 按选定范围暂存旧路径删除，或沿用完整索引刷新。
stage_all_changes() {
  if [[ "$PATH_REPAIR_ACTIVE" == 1 ]]; then
    repair_sourcetree_obsolete_paths
    return $?
  fi
  info_echo "正在安全暂存全部改动 ..."
  git -C "$REPO_ROOT" -c advice.addEmbeddedRepo=false add -A -- .
  success_echo "Git 索引已刷新。"
}
# 场景 C06：用一次完整索引刷新处理普通变更及文件/目录形态互换。
run_commit_scenario_c06_full_index_refresh() {
  if [[ "$PATH_REPAIR_ACTIVE" == 1 ]]; then
    begin_commit_scenario "C06" "旧路径精确修复" "Sourcetree 对已变目录或已不在索引的旧文件路径执行 git rm，出现 without -r 或 pathspec did not match。"
  else
    begin_commit_scenario "C06" "完整索引刷新" "Sourcetree 对新增、删除、重命名或文件/同名目录互换执行分步 add/rm，命令顺序互相阻塞。"
  fi
  stage_all_changes
  complete_commit_scenario "C06"
}
# 场景 C07：复验索引可读、暂存入口可用且没有遗留 index.lock。
run_commit_scenario_c07_verify_unlock() {
  begin_commit_scenario "C07" "索引解锁复验" "前序修复需要用只读索引检查和 dry-run 再确认，没有把故障隐藏到下一次 Commit。"
  if [[ -e "$INDEX_LOCK_PATH" || -L "$INDEX_LOCK_PATH" ]]; then
    error_echo "复验发现 index.lock 仍存在，Commit 索引入口尚未解锁：${INDEX_LOCK_PATH}"
    return 1
  fi
  if ! git -C "$REPO_ROOT" ls-files --stage >/dev/null 2>&1; then
    error_echo "复验失败：Git 索引仍不可读取。"
    return 1
  fi
  if [[ "$PATH_REPAIR_ACTIVE" == 1 ]]; then
    success_echo "索引可读且无遗留锁；本轮只处理旧文件删除，未执行全量暂存。"
    warn_echo "请在 Sourcetree 刷新文件状态，取消旧选择；直接核对并提交已暂存内容，避免再次暂存已迁移的旧删除路径。"
    gray_echo "若仍重复 git rm 旧路径，请关闭并重新打开该仓库的文件状态页；不要重建旧文件或递归删除新目录。"
    complete_commit_scenario "C07"
    return 0
  fi
  if ! git -C "$REPO_ROOT" add --dry-run -A -- . >> "$LOG_FILE" 2>&1; then
    error_echo "复验失败：git add --dry-run -A -- . 仍无法通过。"
    return 1
  fi
  success_echo "索引可读，git add dry-run 通过；Commit 的暂存入口已解锁。"
  warn_echo "Hook、签名、身份、未解决冲突及磁盘/权限错误不属于本脚本覆盖范围，实际 Commit 仍以 Sourcetree 返回结果为准。"
  complete_commit_scenario "C07"
}
# 场景 C08：先修复有自有记录的本仓目录过滤器，避免 status/add 再触发失效运行时。
run_commit_scenario_c08_markdown_filter() {
  begin_commit_scenario "C08" "Markdown 目录过滤器" "Node 升级移除了旧版本路径，Git clean / smudge 仍引用旧路径，导致 add 或 commit -a 失败。"
  if [[ "$COMMIT_REPAIR_MODE" == paths ]]; then
    info_echo "显式旧路径模式不改过滤器；若报 clean 失败，请另用 --repair-filters。"
    complete_commit_scenario "C08"
    return 0
  fi
  local configured="" config_result=0 node_candidate="" node_path=""
  configured="$(git -C "$REPO_ROOT" config --get-regexp '^filter\.jobs-markdown-toc\.' 2>&1)" || config_result=$?
  if [[ "$config_result" == 1 ]]; then
    info_echo "本仓未配置 jobs-markdown-toc，跳过；不自动安装。"
    complete_commit_scenario "C08"
    return 0
  fi
  if [[ "$config_result" != 0 ]]; then
    error_echo "读取过滤器配置失败：${configured}"
    return 1
  fi
  for node_candidate in "$(command -v node 2>/dev/null || true)" /opt/homebrew/bin/node /usr/local/bin/node; do
    [[ -n "$node_candidate" && -x "$node_candidate" ]] || continue
    if "$node_candidate" --version >/dev/null 2>&1; then
      node_path="$node_candidate"
      break
    fi
  done
  if [[ -z "$node_path" ]]; then
    error_echo "没有可用 Node.js；请安装或修复 Node 后重试，未禁用过滤器或修改配置。"
    return 1
  fi
  "$node_path" --input-type=module - "$REPO_ROOT" "$node_path" <<'JOBS_MARKDOWN_FILTER_REPAIR' 2>&1 | strip_ansi_text | tee -a "$LOG_FILE"
// Repair only a recorded repository-local Jobs driver; probe Git without touching its index.
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';

const [root, node] = process.argv.slice(2);
const driver = 'filter.jobs-markdown-toc';
const script = '.jobs-markdown-toc/MarkdownToc.mjs';
const keys = ['clean', 'smudge', 'required'].map(key => `${driver}.${key}`);
const quote = value => "'" + value.replaceAll("'", "'\\''") + "'";
// Execute Git with binary input/output and explicit accepted exit codes.
function git(args, input, env = process.env, allowed = [0]) {
  const result = spawnSync('git', ['-C', root, ...args], { input, env, maxBuffer: 64 * 1024 * 1024 });
  if (result.error || !allowed.includes(result.status)) {
    throw new Error(result.error?.message || result.stderr?.toString() || `Git 失败：${args[0]} (${result.status})`);
  }
  return result;
}
// Read all values so ownership checks can distinguish local records from overrides.
function values(key, local = false) {
  const result = git(['config', ...(local ? ['--local'] : []), '--null', '--get-all', key], undefined, process.env, [0, 1]);
  return result.status === 1 ? [] : result.stdout.toString().split('\0').slice(0, -1);
}
// Compare recorded configuration arrays without normalizing user values.
function same(left, right) { return JSON.stringify(left) === JSON.stringify(right); }
// Snapshot only this driver's repository-local fields.
function current() { return Object.fromEntries(keys.map(key => [key, values(key, true)])); }
// Reject symlinks and non-files before reading managed tools or documents.
function regular(file) {
  let cursor = path.parse(file).root;
  for (const piece of file.slice(cursor.length).split(path.sep)) {
    cursor = path.join(cursor, piece);
    if (fs.lstatSync(cursor).isSymbolicLink()) throw new Error(`保留符号链接，停止修复：${cursor}`);
  }
  if (!fs.statSync(file).isFile()) throw new Error(`不是普通文件：${file}`);
}
// Recognize only the quoted command format emitted by the Jobs installer.
function executable(command, mode) {
  const suffix = ` ${quote(script)} ${mode}`;
  if (!command?.endsWith(suffix)) throw new Error('驱动不是本仓标准命令，保留配置。');
  const prefix = command.slice(0, -suffix.length);
  const candidate = prefix.slice(1, -1).replaceAll("'\\''", "'");
  if (prefix !== quote(candidate) || !/^(?:.*[/\\])?node(?:\.exe)?$/i.test(candidate)) {
    throw new Error('驱动不是可识别的 Node 命令，保留配置。');
  }
  return candidate;
}
// Replace a single owned value in one atomic Git configuration write.
function replace(key, entries) {
  if (entries.length !== 1) throw new Error('拒绝写入非单值驱动。');
  git(['config', '--local', '--replace-all', key, entries[0]]);
}
// Compare real filters against the same Git EOL/encoding pipeline with identity filters.
function probe(files, converter) {
  const directory = fs.mkdtempSync(path.join(path.resolve(root, git(['rev-parse', '--git-path', 'jobs-filter-probe']).stdout.toString().trim()) + '-'));
  fs.chmodSync(directory, 0o700);
  const objects = path.join(directory, 'objects');
  fs.mkdirSync(objects);
  const env = { ...process.env, GIT_OBJECT_DIRECTORY: objects };
  try {
    for (const file of files) {
      const source = fs.readFileSync(path.join(root, file));
      const text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(source);
      const cleaned = Buffer.from(converter.cleanMarkdown(text));
      const expected = git(['-c', `${driver}.clean=cat`, 'hash-object', '-w', `--path=${file}`, '--stdin'], cleaned, env).stdout.toString().trim();
      const actual = git(['hash-object', `--path=${file}`, '--stdin'], source, env).stdout.toString().trim();
      if (actual !== expected) throw new Error(`Git clean 转换不符：${file}`);
      const checkout = git(['-c', `${driver}.smudge=cat`, 'cat-file', '--filters', `--path=${file}`, expected], undefined, env).stdout;
      const checkoutText = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(checkout);
      const smudged = git(['cat-file', '--filters', `--path=${file}`, expected], undefined, env).stdout;
      if (!smudged.equals(Buffer.from(converter.smudgeMarkdown(checkoutText)))) {
        throw new Error(`Git smudge 转换不符：${file}`);
      }
      if (converter.smudgeMarkdown(text) !== text) throw new Error(`本地目录尚未恢复为 [toc]，请先审查并运行仓内 restore：${file}`);
    }
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
  console.log(`真实 Git clean / smudge 验证通过：${files.length} 份文档；业务索引与正文未修改。`);
}
// Validate ownership, repair stale runtime paths, and roll back this run on probe failure.
async function main() {
  for (const name of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES']) {
    if (process.env[name] !== undefined) throw new Error(`不接受 ${name} 覆盖，请在目标仓库正常环境运行。`);
  }
  if (values(`${driver}.process`).length) throw new Error('存在同名 process 过滤器，保留配置并停止。');
  const stateFile = path.resolve(root, git(['rev-parse', '--git-path', 'jobs-markdown-toc.json']).stdout.toString().trim());
  for (const file of [path.join(root, script), path.join(root, '.jobs-markdown-toc/manifest.json'), stateFile]) regular(file);
  const beforeState = fs.readFileSync(stateFile);
  const state = JSON.parse(beforeState);
  const before = current();
  if (state.version !== 1 || !same(before, state.installed)) throw new Error('安装记录与本仓配置不符，保留现场。');
  for (const key of keys) {
    if (before[key].length !== 1 || !same(values(key).slice(-1), before[key])) throw new Error(`配置有高优先级覆盖或重复本仓值，保留现场：${key}`);
  }
  if (before[keys[2]][0] !== 'true') throw new Error('required 不是标准 true，保留现场。');
  const oldNode = executable(before[keys[0]][0], 'clean');
  if (executable(before[keys[1]][0], 'smudge') !== oldNode) throw new Error('clean / smudge 的 Node 路径不一致。');
  const manifest = JSON.parse(fs.readFileSync(path.join(root, '.jobs-markdown-toc/manifest.json')));
  const files = manifest.files;
  if (manifest.version !== 1 || !Array.isArray(files) || !files.length || new Set(files).size !== files.length) throw new Error('目录清单无效。');
  for (const file of files) {
    if (typeof file !== 'string' || path.isAbsolute(file) || file.includes('\\') || file.split('/').some(part => !part || part === '.' || part === '..') || !/\.md$/i.test(file)) throw new Error('目录清单路径不安全。');
    const absolute = path.join(root, file);
    regular(absolute);
    const nearest = git(['-C', path.dirname(absolute), 'rev-parse', '--show-toplevel']).stdout.toString().trim();
    if (fs.realpathSync(nearest) !== fs.realpathSync(root)) throw new Error(`清单越过独立 Git 边界：${file}`);
    const attributes = git(['check-attr', '-z', 'filter', '--', file]).stdout.toString().split('\0');
    if (attributes[2] !== 'jobs-markdown-toc') throw new Error(`属性未登记本过滤器：${file}`);
  }
  const converter = await import(pathToFileURL(path.join(root, script)));
  const health = spawnSync(oldNode, ['--version'], { cwd: root, timeout: 10000 });
  // Replace version-specific paths even while they still work, using the discovered stable entry.
  const obsolete = /[/\\]Cellar[/\\]node[/\\]/.test(oldNode);
  if (!health.error && health.status === 0 && !obsolete) { probe(files, converter); return; }
  const after = { ...before, [keys[0]]: [`${quote(node.replaceAll('\\', '/'))} ${quote(script)} clean`], [keys[1]]: [`${quote(node.replaceAll('\\', '/'))} ${quote(script)} smudge`] };
  const backup = fs.mkdtempSync(path.resolve(root, git(['rev-parse', '--git-path', 'jobs-filter-backup']).stdout.toString().trim()) + '-');
  fs.chmodSync(backup, 0o700);
  fs.writeFileSync(path.join(backup, 'before.json'), JSON.stringify({ version: 1, before, after, state: beforeState.toString() }, null, 2) + '\n', { mode: 0o600 });
  console.log(`过滤器精确备份：${backup}`);
  console.log(`Node 入口：${oldNode} → ${node}`);
  if (!same(current(), before) || !fs.readFileSync(stateFile).equals(beforeState)) throw new Error('配置被并发修改，未写入。');
  const changed = [];
  const afterState = Buffer.from(JSON.stringify({ ...state, installed: after }, null, 2) + '\n');
  try {
    for (const key of keys.slice(0, 2)) { changed.push(key); replace(key, after[key]); }
    fs.writeFileSync(stateFile, afterState);
    for (const key of keys) if (!same(values(key).slice(-1), after[key])) throw new Error('修复后有效配置不符。');
    probe(files, converter);
  } catch (error) {
    for (const key of changed) {
      if (same(values(key, true), after[key])) replace(key, before[key]);
      else if (!same(values(key, true), before[key])) console.error(`配置已变化，未覆盖并发修改：${key}；恢复依据：${backup}`);
    }
    if (fs.readFileSync(stateFile).equals(afterState)) fs.writeFileSync(stateFile, beforeState);
    throw error;
  }
  console.log('已修复本仓过滤器及安装记录；未修改全局配置、未禁用过滤器。');
}
try { await main(); } catch (error) { console.error(error.message); process.exitCode = 1; }
JOBS_MARKDOWN_FILTER_REPAIR
  complete_commit_scenario "C08"
}
# 仅过滤器模式保留其它状态，常规模式继续原来的索引修复流程。
run_remaining_commit_scenarios() {
  if [[ "$COMMIT_REPAIR_MODE" == filters ]]; then
    return 0
  fi
  run_commit_scenario_c03_gitmodules_order # 先暂存子模块登记，再处理 gitlink。
  run_commit_scenario_c04_nested_worktrees # 检查嵌套工作树与路径迁移。
  run_commit_scenario_c05_submodules # 检查已登记子模块的一致性。
  run_commit_scenario_c06_full_index_refresh # 按所选范围修复索引。
  run_commit_scenario_c07_verify_unlock # 复验索引入口与锁状态。
}
# 输出暂存结果，便于在 Sourcetree 日志窗口中直接核对。
print_staged_summary() {
  [[ "$COMMIT_REPAIR_MODE" != filters ]] || return 0
  local summary=""
  summary="$(git -C "$REPO_ROOT" diff --cached --name-status)"

  if [[ -z "$summary" ]]; then
    info_echo "当前没有待提交的暂存变更。"
    return 0
  fi

  note_echo "已暂存变更："
  printf '%s\n' "$summary" | tee -a "$LOG_FILE"
}
# 输出完整流程的最终处理结果。
print_completion_message() {
  success_echo "处理完成。请回到 Sourcetree 刷新后检查并提交。"
  gray_echo "日志文件：${LOG_FILE}"
}
# 编排脚本自述、八个独立故障场景、解锁复验与结果输出。
main() {
  show_script_intro_and_wait # 首先打印内置自述，并按真实运行入口决定是否等待确认。
  initialize_script_runtime # 用户确认后初始化 zsh、命令路径、日志和纯文本输出策略。
  parse_commit_repair_mode "$@" # 保留原仓库参数，解析精确旧路径或完整暂存选项。
  resolve_target_path "${1:-$PWD}" # 规范化 Sourcetree 参数或当前目录，不提前修改 Git 状态。
  run_commit_scenario_c01_worktree_binding # C01：修复当前工作树自身的 gitdir/core.worktree 错位并识别仓库。
  run_commit_scenario_c02_index_lock # C02：区分活锁与残留锁，只归档可安全处理的 index.lock。
  run_commit_scenario_c08_markdown_filter # C08：在读取状态或暂存前检查本仓过滤器与实际 Git 转换。
  run_remaining_commit_scenarios # 按模式继续 C03–C07，或仅修过滤器后返回。
  print_staged_summary # 输出已进入暂存区的文件，便于回到 Sourcetree 核对。
  print_completion_message # 汇总处理结果与日志位置。
}

main "$@"
