#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】📥修复Git无法Fetch.command
# - 核心用途：按 5 个独立场景逐项尝试 Fetch；每次修复后立即复试，成功即停止后续元数据处理。
# - 关键场景：原生 prune、失效远端跟踪引用、foo 与 foo/bar 双向迁移，以及 MacOS 大小写路径碰撞。
# - 影响范围：更新远端跟踪引用及 .git 引用存储；不修改工作区、索引、提交历史或本地分支指向。
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

# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
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

jobs_intro_style() {
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
SCRIPT_NAME="${0:t}"
SCRIPT_BASENAME="${SCRIPT_NAME:r}"
LOG_DIR="${TMPDIR:-/tmp}"
LOG_DIR="${LOG_DIR%/}"
LOG_FILE="${LOG_DIR}/${SCRIPT_BASENAME}.log"
IS_SOURCETREE_RUNTIME=0
PLAIN_OUTPUT=0
LOG_READY=0
REPO_ROOT=""
REMOTE_NAME=""
GIT_COMMON_DIR=""
REMOTE_REFS_ROOT=""
REMOTE_LOGS_ROOT=""
FETCH_OUTPUT=""
FETCH_STATUS=0
FETCH_UNLOCKED=0
REMOTE_HEADS_OUTPUT=""
BACKUP_ROOT=""
BLOCKER_COUNT=0
FETCH_SCENARIO_STEP=0
FETCH_SCENARIO_TOTAL=5
typeset -ga REMOTE_BRANCHES
REMOTE_BRANCHES=()
typeset -ga CONFLICT_BRANCHES
CONFLICT_BRANCHES=()

# 识别脚本是否由 Sourcetree 自定义动作发起。
is_sourcetree_runtime() {
  /usr/bin/env | /usr/bin/grep -Ei '^SOURCETREE|^SOURCE_TREE' >/dev/null && return 0

  local pid="$PPID"
  local command_name=""
  local guard=0
  while [[ -n "$pid" && "$pid" != "0" && "$guard" -lt 8 ]]; do
    command_name="$(/bin/ps -o comm= -p "$pid" 2>/dev/null || true)"
    [[ "$command_name" == *SourceTree* || "$command_name" == *Sourcetree* ]] && return 0
    pid="$(/bin/ps -o ppid= -p "$pid" 2>/dev/null | /usr/bin/tr -d ' ' || true)"
    guard=$((guard + 1))
  done
  return 1
}
# 移除 ANSI 颜色码，避免 Sourcetree 输出窗口显示乱码。
strip_ansi_stream() {
  /usr/bin/perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
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
      printf '%s\n' "$message" | strip_ansi_stream
    else
      printf '%s\n' "$message"
    fi
    return 0
  fi
  if [[ "$PLAIN_OUTPUT" == "1" ]]; then
    printf '%s\n' "$message" | strip_ansi_stream | jobs_prompt_tee "$LOG_FILE"
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
# 输出一个独立 Fetch 故障场景的开始标记和成因。
begin_fetch_scenario() {
  local scenario_id="$1"
  local scenario_name="$2"
  local scenario_cause="$3"
  FETCH_SCENARIO_STEP=$((FETCH_SCENARIO_STEP + 1))
  highlight_echo "[${FETCH_SCENARIO_STEP}/${FETCH_SCENARIO_TOTAL}] ${scenario_id} · ${scenario_name}"
  gray_echo "出现原因：${scenario_cause}"
}
# 输出一个独立 Fetch 故障场景的通过标记。
complete_fetch_scenario() {
  local scenario_id="$1"
  success_echo "${scenario_id} 已完成 Fetch 复试，远端跟踪流程已经解锁。"
}
# 输出一个未命中的 Fetch 故障场景并继续下一项。
skip_fetch_scenario() {
  local scenario_id="$1"
  local reason="$2"
  info_echo "${scenario_id} 未命中：${reason}"
}
# 原样输出 Git 命令结果，并在需要时移除 ANSI 控制字符。
log_external_output() {
  local output="$1"
  [[ -n "$output" ]] || return 0
  if [[ "$PLAIN_OUTPUT" == "1" ]]; then
    print -r -- "$output" | strip_ansi_stream | /usr/bin/tee -a "$LOG_FILE"
  else
    print -r -- "$output" | /usr/bin/tee -a "$LOG_FILE"
  fi
}
# 展示脚本内置自述，终端模式等待确认，Sourcetree 模式直接继续。
show_script_intro_and_wait() {
  configure_output_mode
  highlight_echo "============================== 脚本内置自述 ==============================" | jobs_intro_style title
  note_echo "脚本名称：${SCRIPT_NAME}" | jobs_intro_style title
  note_echo "核心行为：把 Fetch 阻塞拆成 5 个独立场景；每修复一项立即重试，成功即停止后续元数据处理。" | jobs_intro_style body
  note_echo "修复策略：先正常 Fetch，再依次尝试 prune、packed-refs 大小写收口、前缀文件阻塞和同名目录阻塞。" | jobs_intro_style body
  note_echo "适用场景：上游分支在 foo 与 foo/bar 之间迁移，或 SaaS 与 saas/... 在 MacOS 上发生大小写路径碰撞。" | jobs_intro_style body
  note_echo "安全边界：不合并、不 Pull、不提交、不推送、不修改工作区/索引/本地分支指向。" | jobs_intro_style body
  note_echo "运行策略：Sourcetree 内无交互连续执行；终端独立运行需按回车确认。" | jobs_intro_style body | jobs_prompt_filter
  gray_echo "日志文件：${LOG_FILE}" | jobs_intro_style body
  highlight_echo "=============================================================================" | jobs_intro_style title

  if [[ "$IS_SOURCETREE_RUNTIME" == "1" ]]; then
    gray_echo "已识别 Sourcetree 自定义动作，跳过回车等待。" | jobs_intro_style body | jobs_prompt_filter
    return 0
  fi
  if [[ ! -t 0 ]]; then
    error_echo "当前不是 Sourcetree，且没有可交互输入；请在终端中重新运行。"
    exit 1
  fi
  print "" | jobs_intro_style body
  read -r "?$(jobs_prompt_render "👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：")" _ || exit 1
}
# 初始化 zsh 选项、命令路径、日志和输出策略。
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
# 从 Sourcetree 参数或当前目录解析 Git 工作仓根目录。
resolve_repo_root() {
  local target="${1:-$PWD}"
  [[ -f "$target" ]] && target="${target:h}"
  if [[ ! -d "$target" ]]; then
    error_echo "目标路径不存在：${target}"
    return 1
  fi
  if ! REPO_ROOT="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)"; then
    error_echo "目标路径不在 Git 工作仓中：${target}"
    return 1
  fi
  success_echo "已识别仓库：${REPO_ROOT}"
}
# 选择要修复和 Fetch 的远端，显式参数优先，其次使用 origin。
resolve_remote_name() {
  local requested_remote="${1:-}"
  local current_branch=""
  local upstream_remote=""
  local -a remotes
  remotes=(${(f)"$(git -C "$REPO_ROOT" remote)"})

  if [[ -n "$requested_remote" ]]; then
    REMOTE_NAME="$requested_remote"
  elif git -C "$REPO_ROOT" remote get-url origin >/dev/null 2>&1; then
    REMOTE_NAME="origin"
  else
    current_branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [[ -n "$current_branch" ]] && upstream_remote="$(git -C "$REPO_ROOT" config --get "branch.${current_branch}.remote" 2>/dev/null || true)"
    if [[ -n "$upstream_remote" && "$upstream_remote" != "." ]]; then
      REMOTE_NAME="$upstream_remote"
    elif [[ "${#remotes[@]}" -eq 1 ]]; then
      REMOTE_NAME="${remotes[1]}"
    else
      error_echo "无法自动确定远端；请在终端作为第二个参数传入远端名。"
      return 1
    fi
  fi

  if ! git -C "$REPO_ROOT" remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
    error_echo "仓库中不存在远端：${REMOTE_NAME}"
    return 1
  fi
  success_echo "已选择远端：${REMOTE_NAME}"
}
# 解析共用 Git 目录及远端跟踪引用的 loose ref/reflog 根目录。
resolve_git_metadata_paths() {
  local common_dir=""
  common_dir="$(git -C "$REPO_ROOT" rev-parse --git-common-dir 2>/dev/null)"
  [[ "$common_dir" == /* ]] || common_dir="${REPO_ROOT}/${common_dir}"
  GIT_COMMON_DIR="${common_dir:A}"
  REMOTE_REFS_ROOT="${GIT_COMMON_DIR}/refs/remotes/${REMOTE_NAME}"
  REMOTE_LOGS_ROOT="${GIT_COMMON_DIR}/logs/refs/remotes/${REMOTE_NAME}"
  gray_echo "Git 元数据目录：${GIT_COMMON_DIR}"
}
# 执行一次 fetch --prune，保留原始输出与退出码供后续诊断。
perform_fetch() {
  local phase="$1"
  info_echo "${phase}：git fetch --prune ${REMOTE_NAME}"
  FETCH_OUTPUT=""
  FETCH_STATUS=0
  if FETCH_OUTPUT="$(LC_ALL=C git --no-optional-locks -C "$REPO_ROOT" -c color.branch=false -c color.diff=false -c color.status=false -c diff.mnemonicprefix=false -c core.quotepath=false fetch --prune "$REMOTE_NAME" 2>&1)"; then
    FETCH_STATUS=0
  else
    FETCH_STATUS=$?
  fi
  log_external_output "$FETCH_OUTPUT"
  return "$FETCH_STATUS"
}
# 兼容 Git 仅输出 unable to update local ref 的简略诊断；后续仍需核验实际路径阻塞。
is_remote_ref_namespace_conflict() {
  if print -r -- "$FETCH_OUTPUT" | /usr/bin/grep -E 'refs/remotes/|logs/refs/remotes/' >/dev/null &&
     print -r -- "$FETCH_OUTPUT" | /usr/bin/grep -Ei 'Not a directory|Is a directory|exists; cannot create|cannot create.*directory|there are still logs under' >/dev/null; then
    return 0
  fi
  JOBS_FETCH_REMOTE_FOR_PARSE="$REMOTE_NAME" /usr/bin/perl -ne '
    my $remote = quotemeta($ENV{"JOBS_FETCH_REMOTE_FOR_PARSE"});
    $found = 1 if /^\s*!\s+.*\s->\s+$remote\/\S+\s+\(unable to update local ref\)/;
    END { exit($found ? 0 : 1) }
  ' <<< "$FETCH_OUTPUT"
}
# 读取远端当前真实分支，作为判断本地阻塞项是否失效的依据。
load_remote_branches() {
  local oid=""
  local full_ref=""
  local branch_name=""
  REMOTE_BRANCHES=()
  REMOTE_HEADS_OUTPUT=""

  if ! REMOTE_HEADS_OUTPUT="$(LC_ALL=C git --no-optional-locks -C "$REPO_ROOT" ls-remote --heads --refs "$REMOTE_NAME" 2>&1)"; then
    error_echo "无法读取远端分支，为避免误修复已中止。"
    log_external_output "$REMOTE_HEADS_OUTPUT"
    return 1
  fi

  while IFS=$'\t' read -r oid full_ref; do
    [[ "$full_ref" == refs/heads/* ]] || continue
    branch_name="${full_ref#refs/heads/}"
    [[ -n "$branch_name" ]] && REMOTE_BRANCHES+=("$branch_name")
  done <<< "$REMOTE_HEADS_OUTPUT"

  if [[ "${#REMOTE_BRANCHES[@]}" -eq 0 ]]; then
    error_echo "远端 ${REMOTE_NAME} 没有可用分支，为避免误修复已中止。"
    return 1
  fi
  info_echo "已读取远端分支：${#REMOTE_BRANCHES[@]} 个。"
}
# 从 Git 错误中提取本次真正更新失败的远端跟踪分支。
extract_conflict_branches() {
  local parsed_branches=""
  local branch_name=""
  CONFLICT_BRANCHES=()
  parsed_branches="$(
    JOBS_FETCH_REMOTE_FOR_PARSE="$REMOTE_NAME" /usr/bin/perl -ne '
      my $remote = quotemeta($ENV{"JOBS_FETCH_REMOTE_FOR_PARSE"});
      while (/cannot (?:update (?:the )?ref|lock ref) '\''refs\/remotes\/$remote\/([^'\'']+)'\''/g) {
        print "$1\n";
      }
      if (/^\s*!\s+.*\s->\s+$remote\/(\S+)\s+\(unable to update local ref\)/) {
        print "$1\n";
      }
    ' <<< "$FETCH_OUTPUT" | /usr/bin/sort -u
  )"

  while IFS= read -r branch_name; do
    [[ -n "$branch_name" ]] && CONFLICT_BRANCHES+=("$branch_name")
  done <<< "$parsed_branches"

  if [[ "${#CONFLICT_BRANCHES[@]}" -eq 0 ]]; then
    error_echo "无法从 Fetch 错误中精确提取失败分支，为避免扩大修复范围已中止。"
    return 1
  fi
  info_echo "本次冲突分支：${(j:, :)CONFLICT_BRANCHES}"
}
# 确认错误中的目标分支仍真实存在于远端，避免根据过期输出修改元数据。
validate_conflict_branches_against_remote() {
  local conflict_branch=""
  local remote_branch=""
  local matched=0
  for conflict_branch in "${CONFLICT_BRANCHES[@]}"; do
    matched=0
    for remote_branch in "${REMOTE_BRANCHES[@]}"; do
      if [[ "$remote_branch" == "$conflict_branch" ]]; then
        matched=1
        break
      fi
    done
    if [[ "$matched" -ne 1 ]]; then
      error_echo "冲突分支已不在远端，为避免误修复已中止：${conflict_branch}"
      return 1
    fi
  done
}
# 只有错误目标对应的实际文件/目录阻塞存在，才允许 prune 或移动元数据。
validate_physical_conflict_blockers() {
  local branch="" prefix="" root="" index=0 found=0
  local -a segments=()
  for branch in "${CONFLICT_BRANCHES[@]}"; do
    found=0
    for root in "$REMOTE_REFS_ROOT" "$REMOTE_LOGS_ROOT"; do
      [[ -d "${root}/${branch}" ]] && found=1
      segments=("${(@s:/:)branch}")
      prefix=""
      for ((index = 1; index < ${#segments[@]}; index++)); do
        [[ -n "$prefix" ]] && prefix="${prefix}/"
        prefix="${prefix}${segments[$index]}"
        [[ -f "${root}/${prefix}" ]] && found=1
      done
    done
    if [[ "$found" != 1 ]]; then
      error_echo "错误分支没有可验证的 loose ref/reflog 路径阻塞，保留原状：${branch}"
      return 1
    fi
  done
}
# 判断错误分支是否命中远端真实存在的大小写前缀碰撞。
detect_case_fold_collisions() {
  local conflict_branch=""
  local remote_branch=""
  local -a segments
  local prefix=""
  local index=0
  for conflict_branch in "${CONFLICT_BRANCHES[@]}"; do
    segments=("${(@s:/:)conflict_branch}")
    [[ "${#segments[@]}" -gt 1 ]] || continue
    prefix="${segments[1]}"
    for ((index = 1; index < ${#segments[@]}; index++)); do
      [[ "$index" -gt 1 ]] && prefix="${prefix}/${segments[$index]}"
      for remote_branch in "${REMOTE_BRANCHES[@]}"; do
        if [[ "$remote_branch" != "$prefix" && "${remote_branch:l}" == "${prefix:l}" ]]; then
          return 0
        fi
      done
    done
  done
  return 1
}
# 将有效远端跟踪引用收进 packed-refs，避免大小写前缀继续占用 loose ref 文件路径。
pack_refs_for_case_fold_collision() {
  local pack_output=""
  if ! pack_output="$(LC_ALL=C git --no-optional-locks -C "$REPO_ROOT" pack-refs --all 2>&1)"; then
    error_echo "无法把有效引用安全收进 packed-refs，已停止大小写碰撞修复。"
    log_external_output "$pack_output"
    return 1
  fi
  log_external_output "$pack_output"
  success_echo "已通过 git pack-refs 收口有效引用，释放大小写前缀的 loose ref 路径。"
}
# 仅备份远端大小写前缀碰撞所对应的 loose reflog，packed ref 继续保留有效引用。
backup_case_fold_collision_blockers() {
  local conflict_branch=""
  local remote_branch=""
  local -a segments
  local prefix=""
  local index=0
  for conflict_branch in "${CONFLICT_BRANCHES[@]}"; do
    segments=("${(@s:/:)conflict_branch}")
    [[ "${#segments[@]}" -gt 1 ]] || continue
    prefix="${segments[1]}"
    for ((index = 1; index < ${#segments[@]}; index++)); do
      [[ "$index" -gt 1 ]] && prefix="${prefix}/${segments[$index]}"
      for remote_branch in "${REMOTE_BRANCHES[@]}"; do
        if [[ "$remote_branch" != "$prefix" && "${remote_branch:l}" == "${prefix:l}" ]]; then
          warn_echo "远端存在 MacOS 大小写路径碰撞：${remote_branch} <-> ${conflict_branch}"
          warn_echo "有效引用已收进 packed-refs；现在只备份仍占路径的 loose ref/reflog。"
          backup_blocker_path "${REMOTE_REFS_ROOT}/${remote_branch}" "file"
          backup_blocker_path "${REMOTE_LOGS_ROOT}/${remote_branch}" "file"
        fi
      done
    done
  done
}
# 先让 Git 按远端真实状态清理失效的 remote-tracking refs。
prune_stale_remote_refs() {
  local prune_output=""
  local prune_status=0
  info_echo "正在清理已从远端删除的跟踪引用 ..."
  if prune_output="$(LC_ALL=C git --no-optional-locks -C "$REPO_ROOT" remote prune "$REMOTE_NAME" 2>&1)"; then
    prune_status=0
  else
    prune_status=$?
  fi
  log_external_output "$prune_output"
  if [[ "$prune_status" -ne 0 ]]; then
    warn_echo "git remote prune 未完整执行，将继续仅备份已证实的文件/目录阻塞项。"
  fi
}
# 首次需要移动阻塞项时创建本次备份目录。
prepare_backup_root() {
  [[ -n "$BACKUP_ROOT" ]] && return 0
  BACKUP_ROOT="${GIT_COMMON_DIR}/jobs-ref-conflict-backups/$(/bin/date +%Y%m%d-%H%M%S)-$$"
  /bin/mkdir -p "$BACKUP_ROOT"
  note_echo "冲突元数据备份目录：${BACKUP_ROOT}"
}
# 将已验证的阻塞文件或目录移入 Git 元数据备份区。
backup_blocker_path() {
  local source_path="$1"
  local expected_type="$2"
  local type_label="目录"
  local relative_path=""
  local destination=""

  if [[ "$expected_type" == "file" ]]; then
    type_label="文件"
    [[ -f "$source_path" || -L "$source_path" ]] || return 0
    [[ ! -d "$source_path" ]] || return 0
  else
    [[ -d "$source_path" ]] || return 0
  fi

  prepare_backup_root
  relative_path="${source_path#${GIT_COMMON_DIR}/}"
  destination="${BACKUP_ROOT}/${relative_path}"
  /bin/mkdir -p "${destination:h}"
  warn_echo "备份并移开冲突${type_label}：${relative_path}"
  /bin/mv "$source_path" "$destination"
  BLOCKER_COUNT=$((BLOCKER_COUNT + 1))
}
# 根据单个远端分支名备份会阻止层级目录创建的前缀文件。
backup_prefix_file_blockers_for_branch() {
  local branch_name="$1"
  local -a segments
  local prefix=""
  local index=0
  segments=("${(@s:/:)branch_name}")

  if [[ "${#segments[@]}" -gt 1 ]]; then
    prefix="${segments[1]}"
    for ((index = 1; index < ${#segments[@]}; index++)); do
      [[ "$index" -gt 1 ]] && prefix="${prefix}/${segments[$index]}"
      backup_blocker_path "${REMOTE_REFS_ROOT}/${prefix}" "file"
      backup_blocker_path "${REMOTE_LOGS_ROOT}/${prefix}" "file"
    done
  fi
}
# 根据单个远端分支名备份会阻止单层引用创建的同名目录。
backup_same_name_directory_blockers_for_branch() {
  local branch_name="$1"

  backup_blocker_path "${REMOTE_REFS_ROOT}/${branch_name}" "directory"
  backup_blocker_path "${REMOTE_LOGS_ROOT}/${branch_name}" "directory"
}
# 仅扫描错误明确点名分支的前缀文件阻塞，避免扩大修复范围。
backup_conflict_prefix_files() {
  local branch_name=""
  for branch_name in "${CONFLICT_BRANCHES[@]}"; do
    backup_prefix_file_blockers_for_branch "$branch_name"
  done
}
# 仅扫描错误明确点名分支的同名目录阻塞，避免扩大修复范围。
backup_conflict_same_name_directories() {
  local branch_name=""
  for branch_name in "${CONFLICT_BRANCHES[@]}"; do
    backup_same_name_directory_blockers_for_branch "$branch_name"
  done
}
# 根据最近一次 Fetch 错误刷新受支持的冲突分支上下文。
refresh_remote_ref_conflict_context() {
  if ! is_remote_ref_namespace_conflict; then
    error_echo "Fetch 失败，但不属于本脚本支持的远端引用文件/目录冲突。"
    gray_echo "最近一次原始错误已写入日志：${LOG_FILE}"
    return "$FETCH_STATUS"
  fi
  extract_conflict_branches
  validate_conflict_branches_against_remote
  validate_physical_conflict_blockers
}
# 元数据修复仅适用于标准 branch -> remote-tracking 映射。
validate_standard_fetch_mapping() {
  local mapping="" mappings=""
  mappings="$(git -C "$REPO_ROOT" config --get-all "remote.${REMOTE_NAME}.fetch" || true)"
  [[ -n "$mappings" ]] || { error_echo "远端没有标准 fetch 映射；保留原状，请人工检查 refspec。"; return 1; }
  for mapping in "${(@f)mappings}"; do
    if [[ "$mapping" != "+refs/heads/*:refs/remotes/${REMOTE_NAME}/*" && "$mapping" != "refs/heads/*:refs/remotes/${REMOTE_NAME}/*" ]]; then
      error_echo "检测到自定义 fetch refspec，拒绝按标准路径自动搬移元数据：${mapping}"
      return 1
    fi
  done
}
# 首次命中受支持错误后读取远端真值，并建立后续逐场景修复上下文。
prepare_supported_fetch_context() {
  [[ "$FETCH_UNLOCKED" == "1" ]] && return 0
  if ! is_remote_ref_namespace_conflict; then
    error_echo "Fetch 失败，但不属于本脚本支持的远端引用文件/目录冲突。"
    gray_echo "原始错误已写入日志：${LOG_FILE}"
    return "$FETCH_STATUS"
  fi
  warn_echo "已命中远端跟踪引用文件/目录冲突，开始逐场景修复。"
  validate_standard_fetch_mapping
  load_remote_branches
  refresh_remote_ref_conflict_context
}
# 在一个场景产生实际修复后立即重试 Fetch，并刷新下一场景所需错误上下文。
retry_fetch_after_scenario() {
  local scenario_id="$1"
  local phase="$2"
  if perform_fetch "$phase"; then
    FETCH_UNLOCKED=1
    complete_fetch_scenario "$scenario_id"
    return 0
  fi
  warn_echo "${scenario_id} 复试仍失败，继续核对下一项受支持场景。"
  refresh_remote_ref_conflict_context
}
# 场景 F01：先执行 Git 原生 fetch --prune，成功即停止所有额外修复。
run_fetch_scenario_f01_normal_fetch() {
  begin_fetch_scenario "F01" "常规 Fetch 与自动 prune" "普通远端更新，或 Git 自己即可清理的失效 remote-tracking refs。"
  if perform_fetch "F01 常规尝试"; then
    FETCH_UNLOCKED=1
    complete_fetch_scenario "F01"
    return 0
  fi
  warn_echo "F01 常规 Fetch 未解锁，准备判断是否属于安全可修复的引用路径冲突。"
}
# 场景 F02：单独执行 remote prune 后立即复试 Fetch。
run_fetch_scenario_f02_stale_refs() {
  [[ "$FETCH_UNLOCKED" == "1" ]] && return 0
  begin_fetch_scenario "F02" "失效远端跟踪引用" "远端分支已经删除或改名，但本地 remote-tracking ref/reflog 尚未完整清理。"
  prune_stale_remote_refs
  retry_fetch_after_scenario "F02" "F02 prune 后复试"
}
# 场景 F03：只处理远端分支前缀的大小写映射碰撞，命中后立即复试。
run_fetch_scenario_f03_case_fold_collision() {
  [[ "$FETCH_UNLOCKED" == "1" ]] && return 0
  begin_fetch_scenario "F03" "MacOS 大小写路径碰撞" "远端大小写敏感，而 MacOS 默认文件系统把 SaaS 与 saas/... 映射到同一路径。"
  if ! detect_case_fold_collisions; then
    skip_fetch_scenario "F03" "错误分支没有命中远端真实存在的大小写前缀分支。"
    return 0
  fi
  pack_refs_for_case_fold_collision
  backup_case_fold_collision_blockers
  retry_fetch_after_scenario "F03" "F03 大小写碰撞修复后复试"
  if [[ "$FETCH_UNLOCKED" != "1" ]] && detect_case_fold_collisions; then
    error_echo "远端仍同时保留大小写碰撞分支，packed-refs 收口后 Fetch 依然失败；为避免反复搬移同一路径已停止。"
    return "$FETCH_STATUS"
  fi
}
# 场景 F04：只处理 foo 文件阻止创建 foo/bar 目录的前缀文件冲突。
run_fetch_scenario_f04_prefix_file_blocker() {
  [[ "$FETCH_UNLOCKED" == "1" ]] && return 0
  begin_fetch_scenario "F04" "前缀文件阻塞层级分支" "远端从 foo 迁移到 foo/bar，本地旧 foo loose ref 或 reflog 文件挡住目录创建。"
  local blockers_before="$BLOCKER_COUNT"
  backup_conflict_prefix_files
  if [[ "$BLOCKER_COUNT" -eq "$blockers_before" ]]; then
    skip_fetch_scenario "F04" "错误点名分支的前缀位置没有 loose ref/reflog 文件。"
    return 0
  fi
  retry_fetch_after_scenario "F04" "F04 前缀文件修复后复试"
}
# 场景 F05：只处理 foo/bar 目录阻止创建 foo 文件的反向路径冲突。
run_fetch_scenario_f05_same_name_directory_blocker() {
  [[ "$FETCH_UNLOCKED" == "1" ]] && return 0
  begin_fetch_scenario "F05" "同名目录阻塞单层分支" "远端从 foo/bar 收口为 foo，本地旧 foo 目录及其 reflog 目录挡住文件创建。"
  local blockers_before="$BLOCKER_COUNT"
  backup_conflict_same_name_directories
  if [[ "$BLOCKER_COUNT" -eq "$blockers_before" ]]; then
    skip_fetch_scenario "F05" "错误点名分支的同名位置没有 loose ref/reflog 目录。"
    return 0
  fi
  retry_fetch_after_scenario "F05" "F05 同名目录修复后复试"
}
# 汇总所有受支持场景的复试结果，并将未解锁状态明确返回给 Sourcetree。
finalize_fetch_unlock_result() {
  if [[ "$FETCH_UNLOCKED" == "1" ]]; then
    success_echo "Fetch 流程已解锁，远端跟踪引用已刷新。"
    [[ -n "$BACKUP_ROOT" ]] && gray_echo "冲突元数据备份：${BACKUP_ROOT}"
    gray_echo "日志文件：${LOG_FILE}"
    return 0
  fi
  error_echo "5 个受支持场景均已逐项检测，Fetch 仍未解锁；脚本不会继续扩大 Git 元数据修改范围。"
  [[ -n "$BACKUP_ROOT" ]] && gray_echo "已备份元数据：${BACKUP_ROOT}"
  gray_echo "日志文件：${LOG_FILE}"
  return "${FETCH_STATUS:-1}"
}
# 编排脚本自述、环境初始化、仓库识别、五个独立场景和最终解锁判定。
main() {
  show_script_intro_and_wait # 首先打印内置自述，并按真实运行入口决定是否等待确认。
  initialize_script_runtime # 确认后初始化 zsh、命令路径、日志和纯文本输出策略。
  resolve_repo_root "${1:-$PWD}" # 从 Sourcetree 的 $REPO 参数或当前目录识别工作仓。
  resolve_remote_name "${2:-}" # 优先使用显式远端参数，否则选择 origin 或唯一可用远端。
  resolve_git_metadata_paths # 解析 worktree 共用 Git 目录和远端引用元数据路径。
  run_fetch_scenario_f01_normal_fetch # F01：先用 Git 原生 fetch --prune 尝试直接解锁。
  prepare_supported_fetch_context # F01 失败后仅为受支持的引用路径冲突建立远端真值上下文。
  run_fetch_scenario_f02_stale_refs # F02：清理失效 remote-tracking refs 后立即复试。
  run_fetch_scenario_f03_case_fold_collision # F03：处理 MacOS 大小写前缀碰撞后立即复试。
  run_fetch_scenario_f04_prefix_file_blocker # F04：处理旧前缀文件挡住新层级目录后立即复试。
  run_fetch_scenario_f05_same_name_directory_blocker # F05：处理旧层级目录挡住新单层引用后立即复试。
  finalize_fetch_unlock_result # 汇总成功场景或明确返回未解锁错误，不扩大处理范围。
}

main "$@"
