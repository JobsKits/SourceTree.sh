#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】⏬只拉取远程代码.command
# - 核心用途：先抓取明确的远程上游，失败可回车重试；同步并核验父子仓后刷新 SourceTree 仓库界面缓存，不提交、不推送。
# - 影响范围：先 fetch；发现本地改动、未跟踪文件或独有提交时，终端红字列明范围，精确输入 YES 才舍弃。
# - 保护边界：忽略文件保留；未完成操作、游离 HEAD、上游不明确、子仓风险或忽略文件覆盖风险时停止。
# - 运行提示：SourceTree 只打开 Terminal.app；终端先回车确认，危险操作另需 YES，Ctrl+C 取消。

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

RAW_SCRIPT_PATH="$0"
SCRIPT_PATH=""
SCRIPT_DIR=""
SCRIPT_BASENAME=""
LOG_FILE=""
IS_SOURCETREE_RUNTIME=0
TERMINAL_RUN=0
PLAIN_OUTPUT=1
REPOSITORY=""
BRANCH=""
REMOTE=""
MERGE_REF=""
TRACKING_REF=""
SOURCE_URL=""
EFFECTIVE_URL=""
ORIGINAL_HEAD=""
TARGET_HEAD=""
WORKTREE_STATE=""
WORKTREE_FINGERPRINT=""
LOCAL_ONLY_COUNT=0
PREPARE_DIRECTORY=""
SYNC_STARTED=0
PLAN_PATHS=()
PLAN_PARENTS=()
PLAN_SECTIONS=()
PLAN_TARGETS=()
PLAN_URLS=()
PLAN_ORIGINAL_HEADS=()
PLAN_ORIGINAL_BRANCHES=()
PLAN_OBJECT_REPOS=()
PLAN_OLD_PINS=()
LOCK_DIRECTORY=""
LOCK_HELD=0
COLOR_RED=""
COLOR_BLUE=""
COLOR_GREEN=""
COLOR_RESET=""
SOURCETREE_APP=""
SOURCETREE_BUNDLE_ID=""
# 只读解析入口和展示变量，不在确认前写入文件。
prepare_display_context() {
  local candidate="${RAW_SCRIPT_PATH:A}"
  local filename="${RAW_SCRIPT_PATH:t}"
  local fallback=""
  for fallback in "${HOME}/SourceTree.command/MacOS/${filename}/${filename}" "${HOME}/Documents/Github/JobsGenesis/SourceTree.command/MacOS/${filename}/${filename}"; do
    [[ -f "$candidate" ]] && break
    [[ -f "$fallback" ]] && candidate="$fallback"
  done
  SCRIPT_PATH="$candidate"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.$(/bin/date +%Y%m%d-%H%M%S).$$.log"
  [[ "${1:-}" == --terminal-run ]] && TERMINAL_RUN=1
  if (( ! TERMINAL_RUN )); then
    local process_id="$PPID" process_name="" guard=0
    if /usr/bin/env | /usr/bin/grep -Eqi '^(SOURCETREE|SOURCE_TREE)'; then
      IS_SOURCETREE_RUNTIME=1
    fi
    while [[ -n "$process_id" && "$process_id" != 0 && "$guard" -lt 8 ]]; do
      process_name="$(/bin/ps -o comm= -p "$process_id" 2>/dev/null)"
      [[ "$process_name" == *SourceTree* || "$process_name" == *Sourcetree* ]] && IS_SOURCETREE_RUNTIME=1
      process_id="$(/bin/ps -o ppid= -p "$process_id" 2>/dev/null | /usr/bin/tr -d ' ')"
      guard=$((guard + 1))
    done
  fi
  configure_output_mode
}
# SourceTree 输出纯文本，独立终端按终端能力显示红字。
configure_output_mode() {
  PLAIN_OUTPUT=1
  if (( ! IS_SOURCETREE_RUNTIME )) && [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
    PLAIN_OUTPUT=0
    COLOR_RED=$'\033[1;31m'
    COLOR_BLUE=$'\033[0;34m'
    COLOR_GREEN=$'\033[0;32m'
    COLOR_RESET=$'\033[0m'
  else
    export NO_COLOR=1 FORCE_COLOR=0 CLICOLOR=0 ANSI_COLORS_DISABLED=1 npm_config_color=false
  fi
}
# 过滤终端控制码和地址凭据，日志只保留可读脱敏文本。
sanitize_stream() {
  /usr/bin/perl -pe 's/\e\[[0-?]*[ -\/]*[@-~]//g; s{([a-zA-Z][a-zA-Z0-9+.-]*://)[^/\s]*@}{$1***@}g; s{((?:https?|ssh|git|file)://[^\s?#]+)[?#][^\s]*}{$1?[REDACTED]}g'
}
# 显示内置自述；SourceTree 转交终端，终端先确认再进入业务。
show_script_intro_and_wait() {
  prepare_display_context "$@"
  print -r -- "${COLOR_RED}================ 只拉取远程代码 ================${COLOR_RESET}"
  print -r -- "${COLOR_BLUE}1、同步当前仓库明确的远程上游，再向下按各层父仓记录的提交检出子模块；不提交、不推送。${COLOR_RESET}"
  jobs_prompt_output print -r -- "${COLOR_BLUE}2、先抓取远程，失败后空回车重试，直到成功；任意非空输入或 Ctrl+C 取消。本地内容须另行精确输入 YES 才舍弃。${COLOR_RESET}"
  print -r -- "${COLOR_BLUE}3、子模块只跟随 gitlink，不追分支最新；子仓源码、暂存指针、独有游离提交和有损路径变更均停止。${COLOR_RESET}"
  jobs_prompt_output print -r -- "${COLOR_BLUE}4、SourceTree 打开独立终端；回车继续，Ctrl+C 取消；日志：${LOG_FILE}${COLOR_RESET}"
  print -r -- "${COLOR_BLUE}5、成功后刷新运行中的 SourceTree 当前仓库缓存，可能切到该仓库窗口；不删除账号、书签或设置，自动化 / 辅助功能不可用时提示手动 Cmd+R。${COLOR_RESET}"
  if (( IS_SOURCETREE_RUNTIME )); then
    open_terminal_for_repository "$@"
    exit $?
  fi
  if [[ ! -t 0 || ! -t 1 ]]; then
    jobs_prompt_output print -u2 -r -- "请在可交互终端运行；非交互输入不能代替回车或 YES 确认。"
    exit 1
  fi
  local answer=""
  IFS= read -r "answer?$(jobs_prompt_render '👉 已了解用途与风险，按回车继续；Ctrl+C 取消：')" || exit 1
  [[ -z "$answer" ]] || { print -r -- '已取消。'; exit 2; }
}
# 用 AppleScript argv 和 shell 引号传递路径，启动器不执行 Git 业务。
open_terminal_for_repository() {
  [[ "$#" -eq 1 && -d "$1" ]] || { print -u2 -r -- 'SourceTree 必须传入一个有效仓库目录（$REPO）。'; return 1; }
  /usr/bin/osascript - "$SCRIPT_PATH" "${1:A}" <<'APPLESCRIPT'
on run argv
  set scriptPath to item 1 of argv
  set repositoryPath to item 2 of argv
  set shellCommand to "/bin/zsh " & quoted form of scriptPath & " --terminal-run " & quoted form of repositoryPath & "; jobs_pull_result=$?; printf '\n只拉取结束，退出码：%s\n' \"$jobs_pull_result\""
  tell application "Terminal"
    activate
    do script shellCommand
  end tell
end run
APPLESCRIPT
  local launch_result=$?
  if (( launch_result != 0 )); then
    print -u2 -r -- 'Terminal 启动失败，请检查自动化权限或在终端手动运行脚本。'
    return "$launch_result"
  fi
  print -r -- '已打开 Terminal；确认、实时日志与最终退出码请查看新终端。'
}
# 确认后初始化私有日志和清理钩子。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
  umask 077
  : > "$LOG_FILE" || { print -u2 -r -- "无法创建日志：${LOG_FILE}"; exit 1; }
  configure_output_mode
  configure_gitee_https_transport
}
# 兼容旧根仓 / 子仓的 Gitee 标准 SSH 地址；只追加本次进程配置，保留既有 Git 环境规则。
configure_gitee_https_transport() {
  local config_count="${GIT_CONFIG_COUNT:-0}" prefix=""
  [[ "$config_count" == <-> && ${#config_count} -le 9 ]] || fail 'GIT_CONFIG_COUNT 无效，不能安全追加本次 HTTPS 兼容配置。'
  local -i config_index=$(( 10#$config_count ))
  local -a ssh_prefixes
  ssh_prefixes=('git@gitee.com:' 'ssh://git@gitee.com/' 'ssh://git@gitee.com:22/')
  for prefix in "${ssh_prefixes[@]}"; do
    typeset -gx "GIT_CONFIG_KEY_${config_index}=url.https://gitee.com/.insteadOf"
    typeset -gx "GIT_CONFIG_VALUE_${config_index}=$prefix"
    (( config_index += 1 ))
  done
  export GIT_CONFIG_COUNT="$config_index"
  log_message info 'Gitee 标准 SSH 地址在本次进程兼容 HTTPS；来源块显示 Git 配置展开后的拉取地址。'
}
# 同步记录脱敏纯文本和终端展示颜色。
log_message() {
  local role="$1" message="$2" clean_message="" color=""
  clean_message="$(print -r -- "$message" | sanitize_stream)" || exit 1
  print -r -- "$clean_message" >> "$LOG_FILE" || exit 1
  case "$role" in
    danger) color="$COLOR_RED" ;;
    success) color="$COLOR_GREEN" ;;
    *) color="$COLOR_BLUE" ;;
  esac
  print -r -- "${color}${clean_message}${COLOR_RESET}"
}
# 明确报错并停止后续写操作。
fail() {
  log_message danger "✖ $1"
  (( ! SYNC_STARTED )) || log_message danger '部分仓库可能已经检出目标；未创建提交或推送。请按日志处理后重新运行，不能将本次视为完成。'
  log_message info "日志：${LOG_FILE}"
  exit 1
}
# 所有 Git 操作禁用递归和本地钩子，避免一次拉取扩展业务范围。
repo_git() {
  command git -C "$REPOSITORY" -c color.ui=false -c core.hooksPath=/dev/null -c submodule.recurse=false "$@"
}
# 外部 Git 输出脱敏落盘，并保留管道失败状态。
run_git() {
  repo_git "$@" 2>&1 | sanitize_stream | /usr/bin/tee -a "$LOG_FILE"
}
# 仅接受有效目标目录，并确认 Git 真实可执行。
resolve_repository() {
  (( TERMINAL_RUN )) && shift
  [[ "$#" -le 1 ]] || fail '只接受一个仓库目录。'
  local requested="${1:-$PWD}"
  [[ -d "$requested" ]] || fail "目标目录不存在：${requested}"
  command -v git >/dev/null 2>&1 && command git --version >/dev/null 2>&1 || fail 'Git 不可用，请先安装或修复 Command Line Tools。'
  REPOSITORY="$(command git -C "$requested" rev-parse --show-toplevel 2>/dev/null)" || fail '目标不是 Git 工作树。'
  REPOSITORY="${REPOSITORY:A}"
  [[ "$(repo_git rev-parse --is-bare-repository)" == false ]] || fail '不支持裸仓库。'
  log_message info "仓库：${REPOSITORY}"
  LOCK_DIRECTORY="$(repo_git rev-parse --git-path jobs-readonly-pull.lock)" || fail '无法确定锁目录。'
  [[ "$LOCK_DIRECTORY" == /* ]] || LOCK_DIRECTORY="${REPOSITORY}/${LOCK_DIRECTORY}"
  /bin/mkdir "$LOCK_DIRECTORY" 2>/dev/null || fail "另一次只拉取任务可能正在运行；请核实后处理锁目录：${LOCK_DIRECTORY}"
  LOCK_HELD=1
}
# 只释放本进程取得的空锁目录。
release_repository_lock() {
  if (( LOCK_HELD && ZSH_SUBSHELL == 0 )); then
    if [[ -n "$PREPARE_DIRECTORY" && "$PREPARE_DIRECTORY" == "${LOCK_DIRECTORY}/prepare."* && -d "$PREPARE_DIRECTORY" ]]; then
      /usr/bin/find "$PREPARE_DIRECTORY" -depth -delete || print -u2 -r -- "无法清理本次临时准备目录：${PREPARE_DIRECTORY}"
    fi
    /bin/rm -f -- "${LOCK_DIRECTORY}/head-tree" "${LOCK_DIRECTORY}/target-tree" "${LOCK_DIRECTORY}/untracked" "${LOCK_DIRECTORY}/nested" "${LOCK_DIRECTORY}/ignored" "${LOCK_DIRECTORY}/protected-tree" "${LOCK_DIRECTORY}/snapshot" "${LOCK_DIRECTORY}/snapshot-paths"
    /bin/rmdir "$LOCK_DIRECTORY" 2>/dev/null || print -u2 -r -- "无法释放锁目录：${LOCK_DIRECTORY}"
    LOCK_HELD=0
  fi
}
# zsh 的函数内 EXIT trap 会随函数返回触发，改用脚本级退出函数。
TRAPEXIT() {
  release_repository_lock
}
# 中断进入脚本级退出清理，返回可识别的终止状态。
TRAPINT() {
  exit 130
}
# 终止信号不继续 Git 写操作。
TRAPTERM() {
  exit 143
}
# 终端断开时同样保留失败状态并释放本脚本锁。
TRAPHUP() {
  exit 129
}
# 冲突、进行中的 Git 操作和隐藏状态在任何 fetch / 清理前阻断。
assert_repository_ready() {
  local marker="" marker_path="" flags="" entry=""
  for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer BISECT_START index.lock; do
    marker_path="$(repo_git rev-parse --git-path "$marker")" || fail '无法检查 Git 操作状态。'
    [[ "$marker_path" == /* ]] || marker_path="${REPOSITORY}/${marker_path}"
    [[ ! -e "$marker_path" ]] || fail "存在未完成操作或 Git 锁：${REPOSITORY}（${marker}）；请先处理。"
  done
  [[ -z "$(repo_git ls-files -u)" ]] || fail '索引存在未解决冲突。'
  flags="$(repo_git ls-files -v)" || fail '无法检查索引标记。'
  for entry in "${(@f)flags}"; do
    [[ "$entry" != [a-zS]' '* ]] || fail '存在 assume-unchanged / skip-worktree（含稀疏检出），请先显式恢复普通工作树。'
  done
}
# 仅使用当前分支明确配置的单个远程上游，不猜分支或 origin。
resolve_upstream() {
  BRANCH="$(repo_git symbolic-ref --quiet --short HEAD)" || fail '当前是游离 HEAD，请先在 SourceTree 切换到已有的跟踪分支。'
  ORIGINAL_HEAD="$(repo_git rev-parse --verify HEAD)" || fail '当前分支没有有效提交。'
  REMOTE="$(repo_git config --get-all "branch.${BRANCH}.remote")" || fail '当前分支没有配置远程上游。'
  MERGE_REF="$(repo_git config --get-all "branch.${BRANCH}.merge")" || fail '当前分支没有配置上游分支。'
  [[ -n "$REMOTE" && "$REMOTE" != . && "$REMOTE" != -* && "$REMOTE" != *$'\n'* ]] || fail '只支持一个明确的远程上游。'
  [[ "$MERGE_REF" == refs/heads/* && "$MERGE_REF" != *$'\n'* ]] || fail '上游必须是单个远程分支。'
  repo_git check-ref-format "$MERGE_REF" || fail '上游分支名无效。'
  TRACKING_REF="$(repo_git for-each-ref --format='%(upstream)' "refs/heads/${BRANCH}")" || fail '无法解析远程跟踪引用。'
  [[ "$TRACKING_REF" == refs/remotes/* && "$TRACKING_REF" != *$'\n'* ]] || fail '远程跟踪映射不明确；请先修复分支上游配置。'
  SOURCE_URL="$(repo_git config --get-all "remote.${REMOTE}.url")" || fail '远程地址未配置。'
  [[ -n "$SOURCE_URL" && "$SOURCE_URL" != *$'\n'* ]] || fail '远程地址必须唯一。'
  EFFECTIVE_URL="$(repo_git ls-remote --get-url "$REMOTE")" || fail '无法展开当前 Git URL 配置。'
}
# 每轮抓取前后核对原分支、上游和来源，不沿用等待期间失效的目标。
assert_fetch_context_unchanged() {
  assert_repository_ready
  [[ "$(repo_git symbolic-ref --quiet --short HEAD)" == "$BRANCH" && "$(repo_git rev-parse HEAD)" == "$ORIGINAL_HEAD" ]] || fail '抓取期间分支或 HEAD 已变化，请重新运行。'
  [[ "$(repo_git config --get-all "branch.${BRANCH}.remote")" == "$REMOTE" && "$(repo_git config --get-all "branch.${BRANCH}.merge")" == "$MERGE_REF" ]] || fail '抓取期间上游配置已变化，请重新运行。'
  [[ "$(repo_git for-each-ref --format='%(upstream)' "refs/heads/${BRANCH}")" == "$TRACKING_REF" ]] || fail '抓取期间远程跟踪映射已变化，请重新运行。'
  [[ "$(repo_git config --get-all "remote.${REMOTE}.url")" == "$SOURCE_URL" && "$(repo_git ls-remote --get-url "$REMOTE")" == "$EFFECTIVE_URL" ]] || fail '抓取期间远程来源已变化，请重新运行。'
}
# 抓取失败只授权再次抓取；非空输入、输入结束及无终端均不进入同步。
wait_for_fetch_retry() {
  local fetch_result="$1" answer=""
  log_message danger "✖ 远程抓取失败（退出码：${fetch_result}），未舍弃本地内容。"
  log_message info '若出现 cannot lock ref / expected，可能有 SourceTree 自动抓取或其它 Git 进程同时更新引用；请等待其结束。持续失败请按上方原始错误处理。'
  log_message info "日志：${LOG_FILE}"
  [[ -t 0 && -t 1 ]] && (( ! IS_SOURCETREE_RUNTIME && ! SYNC_STARTED )) || fail '重试抓取必须在独立交互终端、开始同步之前进行。'
  IFS= read -r "answer?$(jobs_prompt_render '👉 空回车重新抓取远程；输入任意字符后回车或 Ctrl+C 取消：')" || { log_message info '输入结束，已取消；未舍弃本地内容。'; exit 2; }
  [[ -z "$answer" ]] || { log_message info '已取消，未舍弃本地内容。'; exit 2; }
  log_message info '已按回车，将重新核对状态并再次抓取远程；这不授权舍弃本地内容。'
}
# 来源先于每轮传输展示；只抓取目标分支，成功后才固定提交并进入同步预检。
fetch_target() {
  local attempt=0 fetch_result=0
  while true; do
    assert_fetch_context_unchanged
    attempt=$((attempt + 1))
    log_message info "━━━━━━━━━━ 阶段 1/2｜抓取远程（第 ${attempt} 次） ━━━━━━━━━━"
    log_message info '━━━━━━━━━━ 来源｜只拉取 ━━━━━━━━━━'
    log_message info "对象：${BRANCH} → ${REMOTE}/${MERGE_REF#refs/heads/}"
    log_message info "配置来源：${SOURCE_URL}"
    log_message info "拉取地址（本地 Git 配置展开）：${EFFECTIVE_URL}"
    log_message info "目标位置：${REPOSITORY}"
    if run_git fetch --no-tags --no-recurse-submodules -- "$REMOTE" "+${MERGE_REF}:${TRACKING_REF}"; then
      break
    else
      fetch_result=$?
      wait_for_fetch_retry "$fetch_result"
    fi
  done
  assert_fetch_context_unchanged
  TARGET_HEAD="$(repo_git rev-parse --verify "${TRACKING_REF}^{commit}")" || fail '远程目标不是有效提交。'
  log_message success "✔ 远程抓取成功；本次固定目标：${TARGET_HEAD}"
  log_message info '━━━━━━━━━━ 阶段 2/2｜检查并同步工作树 ━━━━━━━━━━'
}
# 完整检查可能被覆盖或清理的目录，枚举失败也必须停止。
assert_directory_has_no_nested_git() {
  local directory="$1" nested=""
  /usr/bin/find "$directory" \( -name .git -print0 -prune \) -o \( -type d -name objects -print0 -prune \) > "${LOCK_DIRECTORY}/nested" || fail "无法完整检查目录，已停止清理：${directory}"
  while IFS= read -r -d '' nested; do
    [[ "${nested:t}" != .git ]] || fail "存在嵌套 Git 仓库，不能安全清理：${nested:h}"
    if [[ -f "${nested:h}/HEAD" && -d "${nested:h}/refs" ]]; then
      fail "存在嵌套裸仓库，不能安全清理：${nested:h}"
    fi
  done < "${LOCK_DIRECTORY}/nested"
}
# 已跟踪目录内也可能被另行 git init，不能仅依赖未跟踪文件列表。
assert_tracked_paths_have_no_nested_git() {
  local listing="$1" entry="" item="" parent=""
  local -A checked_parents=()
  while IFS= read -r -d '' entry; do
    [[ "$entry" == 160000\ * ]] && continue
    item="${entry#*$'\t'}"
    if [[ -d "${REPOSITORY}/${item}" && ! -L "${REPOSITORY}/${item}" ]]; then
      assert_directory_has_no_nested_git "${REPOSITORY}/${item}"
    fi
    parent="${item:h}"
    while [[ "$parent" != . && -n "$parent" ]]; do
      [[ "${checked_parents[$parent]:-0}" != 1 ]] || break
      checked_parents[$parent]=1
      [[ ! -e "${REPOSITORY}/${parent}/.git" ]] || fail "已跟踪路径内存在独立 Git 仓库：${REPOSITORY}/${parent}"
      if [[ -f "${REPOSITORY}/${parent}/HEAD" && -d "${REPOSITORY}/${parent}/objects" && -d "${REPOSITORY}/${parent}/refs" ]]; then
        fail "已跟踪路径内存在裸仓库：${REPOSITORY}/${parent}"
      fi
      parent="${parent:h}"
    done
  done < "$listing"
}
# 子仓和临时裸仓共用最小 Git 配置；URL 仅逐层显式传入，不覆盖 root remote。
tree_git() {
  local tree_repository="$1"
  shift
  command git -C "$tree_repository" -c color.ui=false -c core.hooksPath=/dev/null -c submodule.recurse=false "$@"
}
# 保留 Git 失败状态，所有子仓传输输出同样脱敏。
run_tree_git() {
  tree_git "$@" 2>&1 | sanitize_stream | /usr/bin/tee -a "$LOG_FILE"
}
# 子模块路径不能穿过符号链接、仓外目录或 Git 元数据。
validate_submodule_path() {
  local parent_root="$1" child_path="$2" component="" prefix="$1"
  [[ -n "$child_path" && "$child_path" != /* && "$child_path" != -* && "$child_path" != *$'\n'* && "$child_path" != *$'\r'* ]] || fail "子模块路径无效：${parent_root}/${child_path}"
  for component in "${(@s:/:)child_path}"; do
    [[ -n "$component" && "$component" != . && "$component" != .. && "${component:l}" != .git ]] || fail "子模块路径越界或涉及元数据：${parent_root}/${child_path}"
    prefix+="/${component}"
    [[ ! -L "$prefix" ]] || fail "子模块路径经过符号链接：${prefix}"
  done
  [[ "${prefix:A}" == "${parent_root}/"* ]] || fail "子模块路径不在父仓内：${prefix}"
}
# 按远端仓库目录语义解析相对地址，保留 host、namespace、协议和自定义端口。
resolve_child_source_url() {
  local parent_url="$1" raw_url="$2" parent_root="$3" resolved=""
  [[ -n "$raw_url" && "$raw_url" != -* && "$raw_url" != *$'\n'* && "$raw_url" != *$'\r'* && "$raw_url" != *'::'* ]] || fail "子模块来源无效：${parent_root}"
  resolved="$(/usr/bin/perl -e '
    use strict; use warnings;
    my ($base, $url, $root) = @ARGV;
    if ($url =~ m{^\./|^\.\./}) {
      my ($prefix, $path);
      if ($base =~ m{^([a-zA-Z][a-zA-Z0-9+.-]*://[^/]*)(/.*)$}) { ($prefix, $path) = ($1, $2); }
      elsif ($base =~ m{^([^/:]+(?:\@[^/:]+)?:)(.+)$}) { ($prefix, $path) = ($1, $2); }
      else { ($prefix, $path) = ("", $base); $path = "$root/$path" unless $path =~ m{^/}; }
      my $absolute = $path =~ m{^/};
      my @parts;
      for my $part (split m{/}, "$path/$url") {
        next if $part eq "" || $part eq ".";
        if ($part eq "..") { die "Relative URL escapes repository scope\n" unless @parts; pop @parts; }
        else { push @parts, $part; }
      }
      die "Empty repository URL\n" unless @parts;
      $url = $prefix . ($absolute ? "/" : "") . join("/", @parts);
    }
    $url =~ s{^git\@gitee\.com:}{https://gitee.com/};
    $url =~ s{^ssh://git\@gitee\.com(?::22)?/}{https://gitee.com/};
    print $url;
  ' "$parent_url" "$raw_url" "$parent_root")" || fail "不能解析子模块相对来源：${parent_root}"
  print -r -- "$resolved"
}
# 已暂存的 gitlink 是用户意图，不能用 ignore-submodules=all 将它隐藏。
assert_no_staged_gitlinks() {
  local staged_raw=""
  staged_raw="$(repo_git diff --cached --raw --no-abbrev --ignore-submodules=none HEAD)" || fail "无法检查暂存指针：${REPOSITORY}"
  [[ -z "$(print -r -- "$staged_raw" | /usr/bin/awk '$1 == ":160000" || $2 == "160000"')" ]] || fail "存在已暂存的子模块指针或类型变化：${REPOSITORY}；请单独处理。"
}
# 对已有工作树保留原先的嵌套仓库保护，但允许纯子模块检出漂移。
assert_worktree_paths_safe() {
  assert_no_staged_gitlinks
  repo_git ls-tree -rz HEAD > "${LOCK_DIRECTORY}/head-tree" || fail "无法枚举当前树：${REPOSITORY}"
  repo_git ls-tree -rz "$TARGET_HEAD" > "${LOCK_DIRECTORY}/target-tree" || fail "无法枚举目标树：${REPOSITORY}"
  assert_tracked_paths_have_no_nested_git "${LOCK_DIRECTORY}/head-tree"
  assert_tracked_paths_have_no_nested_git "${LOCK_DIRECTORY}/target-tree"
  local candidate=""
  repo_git ls-files --others --exclude-standard --directory -z > "${LOCK_DIRECTORY}/untracked" || fail '无法枚举未跟踪目录。'
  # 只检查将被清理的未跟踪目录；其中的 Git 元数据不能因依赖目录名而漏检。
  while IFS= read -r -d '' candidate; do
    candidate="${candidate%/}"
    [[ -d "${REPOSITORY}/${candidate}" && ! -L "${REPOSITORY}/${candidate}" ]] || continue
    assert_directory_has_no_nested_git "${REPOSITORY}/${candidate}"
  done < "${LOCK_DIRECTORY}/untracked"
}
# 空目录可以初始化；非空普通目录或失效 Git 指针不作为下载目标覆盖。
assert_new_submodule_path_empty() {
  local child_root="$1" contents=""
  [[ ! -e "$child_root" ]] && return 0
  [[ -d "$child_root" && ! -L "$child_root" ]] || fail "新子模块目标不是空目录：${child_root}"
  contents="$(/usr/bin/find "$child_root" -mindepth 1 -maxdepth 1 -print)" || fail "无法检查新子模块目录：${child_root}"
  [[ -z "$contents" ]] || fail "子模块未初始化但目标目录非空，保留原内容并停止：${child_root}"
}
# 游离 HEAD 只在仍受已知引用或旧 / 新父仓指针保护时允许离开。
assert_child_head_is_preserved() {
  local child_root="$1" old_pin="$2" target_pin="$3" current_head="" containing_refs=""
  current_head="$(tree_git "$child_root" rev-parse --verify HEAD)" || fail "子仓没有有效 HEAD：${child_root}"
  containing_refs="$(tree_git "$child_root" for-each-ref --contains "$current_head" --format='%(refname)')" || fail "无法核对子仓提交引用：${child_root}"
  [[ -n "$containing_refs" || "$current_head" == "$old_pin" || "$current_head" == "$target_pin" ]] && return 0
  if [[ -n "$old_pin" ]] && tree_git "$child_root" merge-base --is-ancestor "$current_head" "$old_pin" 2>/dev/null; then
    return 0
  fi
  tree_git "$child_root" merge-base --is-ancestor "$current_head" "$target_pin" 2>/dev/null && return 0
  fail "子仓存在未受引用或父仓指针保护的游离提交：${child_root}（${current_head}）；请先保存该提交。"
}
# 子仓不继承父仓 YES；普通源码、暂存指针和未完成操作均须单独处理。
assert_child_worktree_ready() {
  local REPOSITORY="$1" TARGET_HEAD="$2" child_state="" actual_root=""
  actual_root="$(repo_git rev-parse --show-toplevel)" || fail "子模块工作树无效：${REPOSITORY}"
  [[ "${actual_root:A}" == "$REPOSITORY" ]] || fail "子模块路径指向其它工作树：${REPOSITORY}"
  log_message info "检查子仓：${REPOSITORY}"
  assert_repository_ready
  assert_no_staged_gitlinks
  child_state="$(repo_git status --porcelain=v1 --untracked-files=all --ignore-submodules=all)" || fail "无法检查子仓源码：${REPOSITORY}"
  [[ -z "$child_state" ]] || fail "子仓存在暂存 / 未暂存 / 未跟踪源码：${REPOSITORY}"$'\n'"${child_state}"
  assert_worktree_paths_safe
  assert_ignored_paths_safe
}
# 显式展示本层来源和父仓要求的固定提交，不把分支最新当作替代目标。
show_child_source() {
  local child_root="$1" source_url="$2" target_pin="$3" object_repo="$4" effective_url=""
  effective_url="$(tree_git "$object_repo" ls-remote --get-url -- "$source_url")" || fail "无法解析子仓来源：${child_root}"
  log_message info '━━━━━━━━━━ 来源｜子模块固定提交 ━━━━━━━━━━'
  log_message info "对象：${child_root}"
  log_message info "父仓记录提交：${target_pin}"
  log_message info "解析来源：${source_url}"
  log_message info "拉取地址（本地 Git 配置展开）：${effective_url}"
}
# 现有子仓预取对象；未初始化子仓在私有临时裸仓预检，缺提交时不改任何工作树。
prepare_child_commit() {
  local child_root="$1" source_url="$2" target_pin="$3" plan_number="$4" object_repo="$1"
  if [[ ! -e "${child_root}/.git" ]]; then
    object_repo="${PREPARE_DIRECTORY}/objects-${plan_number}.git"
    run_tree_git "$PREPARE_DIRECTORY" init --bare --quiet "$object_repo" || fail "无法建立子模块临时对象库：${child_root}"
  fi
  PLAN_OBJECT_REPOS[$plan_number]="$object_repo"
  show_child_source "$child_root" "$source_url" "$target_pin" "$object_repo"
  if ! tree_git "$object_repo" cat-file -e "${target_pin}^{commit}" 2>/dev/null; then
    local -a fetch_options
    fetch_options=(--no-tags --no-recurse-submodules)
    [[ "$object_repo" != "$child_root" ]] && fetch_options+=(--depth=1)
    run_tree_git "$object_repo" fetch "${fetch_options[@]}" -- "$source_url" "$target_pin" || fail "子仓目标提交不可取得：${child_root}"$'\n'"父仓 gitlink：${target_pin}"$'\n'"来源：${source_url}；请由发布端先补齐该提交。"
  fi
  tree_git "$object_repo" cat-file -e "${target_pin}^{commit}" 2>/dev/null || fail "子仓目标不是可检出的提交：${child_root}（${target_pin}；来源：${source_url}）"
}
# 删除、改名和子模块 / 普通路径互换会产生有损现场，本动作只接受保留路径和正常新增。
assert_gitlink_paths_preserved() {
  local object_repo="$1" original_revision="$2" target_revision="$3" working_root="$4" listing="${PREPARE_DIRECTORY}/paths-${#PLAN_PATHS}.tree" entry="" item="" target_entry=""
  [[ -n "$original_revision" ]] || return 0
  tree_git "$object_repo" ls-tree -rz "$original_revision" > "$listing" || fail "无法枚举子仓旧指针：${working_root}"
  while IFS= read -r -d '' entry; do
    [[ "$entry" == 160000\ * ]] || continue
    item="${entry#*$'\t'}"
    target_entry="$(tree_git "$object_repo" --literal-pathspecs ls-tree "$target_revision" -- "$item")" || fail "无法核对目标子模块路径：${working_root}/${item}"
    [[ "$target_entry" == 160000\ * ]] || fail "远程删除、改名或转换了子模块路径，保留现场并停止：${working_root}/${item}"
  done < "$listing"
}
# 先读取各层目标提交的 .gitmodules；整个计划只记录固定 SHA，不执行工作树检出。
prepare_descendant_plan() {
  local parent_root="$1" object_repo="$2" target_revision="$3" parent_url="$4" depth="$5" old_revision="$6"
  (( depth <= 64 )) || fail "子模块递归超过 64 层，可能存在循环：${parent_root}"
  assert_gitlink_paths_preserved "$object_repo" "$old_revision" "$target_revision" "$parent_root"
  local manifest="${PREPARE_DIRECTORY}/manifest-${#PLAN_PATHS}.gitmodules" tree_listing="${PREPARE_DIRECTORY}/target-${#PLAN_PATHS}.tree" keys_listing="${PREPARE_DIRECTORY}/keys-${#PLAN_PATHS}"
  local entry="" child_path="" child_pin="" old_pin="" old_entry="" metadata="" section="" config_entry="" config_key="" configured_path="" raw_url="" child_url="" child_root="" child_head="" child_branch="" cache_path="" plan_number=0
  local -A path_sections=()
  tree_git "$object_repo" ls-tree -rz "$target_revision" > "$tree_listing" || fail "无法读取目标目录树：${parent_root}"
  if tree_git "$object_repo" cat-file -e "${target_revision}:.gitmodules" 2>/dev/null; then
    tree_git "$object_repo" show "${target_revision}:.gitmodules" > "$manifest" || fail "无法读取目标 .gitmodules：${parent_root}"
    tree_git "$object_repo" config --file "$manifest" --list >/dev/null || fail "目标 .gitmodules 解析失败：${parent_root}"
    local config_result=0
    tree_git "$object_repo" config --file "$manifest" --null --get-regexp '^submodule\..*\.path$' > "$keys_listing" || config_result=$?
    (( config_result == 0 || config_result == 1 )) || fail "无法读取目标子模块登记：${parent_root}"
    while IFS= read -r -d '' config_entry; do
      config_key="${config_entry%%$'\n'*}"
      configured_path="${config_entry#*$'\n'}"
      section="${config_key#submodule.}"
      section="${section%.path}"
      validate_submodule_path "$parent_root" "$configured_path"
      validate_submodule_path "$parent_root" "$section"
      [[ -z "${path_sections[$configured_path]:-}" ]] || fail "重复的子模块 path：${parent_root}/${configured_path}"
      path_sections[$configured_path]="$section"
    done < "$keys_listing"
  fi
  while IFS= read -r -d '' entry; do
    [[ "$entry" == 160000\ * ]] || continue
    child_path="${entry#*$'\t'}"
    metadata="${entry%%$'\t'*}"
    child_pin="${metadata##* }"
    validate_submodule_path "$parent_root" "$child_path"
    section="${path_sections[$child_path]:-}"
    [[ -n "$section" ]] || fail "gitlink 缺少明确的 .gitmodules 登记：${parent_root}/${child_path}"
    raw_url="$(tree_git "$object_repo" config --file "$manifest" --get-all "submodule.${section}.url")" || fail "子模块没有来源：${parent_root}/${child_path}"
    child_url="$(resolve_child_source_url "$parent_url" "$raw_url" "$parent_root")" || fail "子模块来源解析失败：${parent_root}/${child_path}"
    child_root="${parent_root}/${child_path}"
    old_pin=""
    if [[ -n "$old_revision" ]]; then
      old_entry="$(tree_git "$object_repo" --literal-pathspecs ls-tree "$old_revision" -- "$child_path")" || fail "无法检查原子模块路径：${child_root}"
      [[ -z "$old_entry" || "$old_entry" == 160000\ * ]] || fail "远程将普通路径转换为子模块，保留现场并停止：${child_root}"
      if [[ -n "$old_entry" ]]; then
        metadata="${old_entry%%$'\t'*}"
        old_pin="${metadata##* }"
      fi
    fi
    child_head=""
    child_branch=""
    if [[ -e "${child_root}/.git" ]]; then
      [[ -n "$old_pin" ]] || fail "新增 gitlink 路径已有独立 Git，不能接管：${child_root}"
      child_head="$(tree_git "$child_root" rev-parse --verify HEAD)" || fail "子模块 Git 指针损坏：${child_root}"
      child_branch="$(tree_git "$child_root" symbolic-ref --quiet HEAD 2>/dev/null)" || child_branch=""
      assert_child_worktree_ready "$child_root" "$child_head"
    else
      assert_new_submodule_path_empty "$child_root"
      cache_path="$(tree_git "$object_repo" rev-parse --git-path "modules/${section}")" || fail "无法检查子模块缓存：${child_root}"
      [[ "$cache_path" == /* ]] || cache_path="${object_repo}/${cache_path}"
      [[ ! -e "$cache_path" ]] || fail "子模块工作树缺失但仍有缓存，先恢复工作树以保护索引和独有提交：${child_root}"
    fi
    PLAN_PATHS+=("$child_root")
    PLAN_PARENTS+=("$parent_root")
    PLAN_SECTIONS+=("$section")
    PLAN_TARGETS+=("$child_pin")
    PLAN_URLS+=("$child_url")
    PLAN_ORIGINAL_HEADS+=("$child_head")
    PLAN_ORIGINAL_BRANCHES+=("$child_branch")
    PLAN_OBJECT_REPOS+=("")
    PLAN_OLD_PINS+=("$old_pin")
    plan_number=${#PLAN_PATHS}
    prepare_child_commit "$child_root" "$child_url" "$child_pin" "$plan_number"
    if [[ -n "$child_head" ]]; then
      assert_child_head_is_preserved "$child_root" "$old_pin" "$child_pin"
      assert_child_worktree_ready "$child_root" "$child_pin"
    fi
    prepare_descendant_plan "$child_root" "${PLAN_OBJECT_REPOS[$plan_number]}" "$child_pin" "$child_url" "$((depth + 1))" "$child_head"
  done < "$tree_listing"
}
# 顶层保护先完成，再预检整棵将要检出的提交树。
assert_nested_repositories_safe() {
  assert_worktree_paths_safe
  PREPARE_DIRECTORY="$(/usr/bin/mktemp -d "${LOCK_DIRECTORY}/prepare.XXXXXX")" || fail '无法创建私有子模块准备目录。'
  prepare_descendant_plan "$REPOSITORY" "$REPOSITORY" "$TARGET_HEAD" "$SOURCE_URL" 0 "$ORIGINAL_HEAD"
  log_message info "已预检 ${#PLAN_PATHS} 个子模块的固定提交；尚未修改工作树。"
}
# 确认期间的子仓 HEAD、分支、源码或路径变化使整次计划失效。
assert_submodule_plan_unchanged() {
  local index=0 child_root="" current_branch=""
  for (( index=1; index<=${#PLAN_PATHS}; index++ )); do
    child_root="${PLAN_PATHS[$index]}"
    if [[ -n "${PLAN_ORIGINAL_HEADS[$index]}" ]]; then
      [[ -e "${child_root}/.git" && "$(tree_git "$child_root" rev-parse HEAD)" == "${PLAN_ORIGINAL_HEADS[$index]}" ]] || fail "确认期间子仓 HEAD 或路径变化：${child_root}"
      current_branch="$(tree_git "$child_root" symbolic-ref --quiet HEAD 2>/dev/null)" || current_branch=""
      [[ "$current_branch" == "${PLAN_ORIGINAL_BRANCHES[$index]}" ]] || fail "确认期间子仓分支变化：${child_root}"
      assert_child_worktree_ready "$child_root" "${PLAN_TARGETS[$index]}"
      assert_child_head_is_preserved "$child_root" "${PLAN_OLD_PINS[$index]}" "${PLAN_TARGETS[$index]}"
    else
      assert_new_submodule_path_empty "$child_root"
    fi
  done
}
# 每次只执行直属一层；子仓 URL 来自该层父 URL，绝不跟踪分支最新或创建本地提交。
synchronize_submodule_plan() {
  local index=0 child_root="" parent_root="" child_path="" section="" target_pin="" current_branch=""
  local -a update_options
  for (( index=1; index<=${#PLAN_PATHS}; index++ )); do
    child_root="${PLAN_PATHS[$index]}"
    parent_root="${PLAN_PARENTS[$index]}"
    child_path="${child_root#"${parent_root}/"}"
    section="${PLAN_SECTIONS[$index]}"
    target_pin="${PLAN_TARGETS[$index]}"
    update_options=(--init --checkout)
    if [[ -n "${PLAN_ORIGINAL_HEADS[$index]}" ]]; then
      update_options+=(--no-fetch)
      [[ "$(tree_git "$child_root" rev-parse HEAD)" == "${PLAN_ORIGINAL_HEADS[$index]}" ]] || fail "检出前子仓 HEAD 已变化：${child_root}"
      current_branch="$(tree_git "$child_root" symbolic-ref --quiet HEAD 2>/dev/null)" || current_branch=""
      [[ "$current_branch" == "${PLAN_ORIGINAL_BRANCHES[$index]}" ]] || fail "检出前子仓分支已变化：${child_root}"
      assert_child_worktree_ready "$child_root" "$target_pin"
    else
      assert_new_submodule_path_empty "$child_root"
    fi
    show_child_source "$child_root" "${PLAN_URLS[$index]}" "$target_pin" "${PLAN_OBJECT_REPOS[$index]}"
    # 新克隆可能遵循 shallow=true；允许 Git 补取已预检的旧 pin，避免浅克隆仅有分支 tip。
    run_tree_git "$parent_root" --literal-pathspecs -c "submodule.${section}.url=${PLAN_URLS[$index]}" submodule update "${update_options[@]}" -- "$child_path" || fail "子模块检出失败：${child_root}（gitlink：${target_pin}；来源：${PLAN_URLS[$index]}）"
    [[ "$(tree_git "$child_root" rev-parse HEAD)" == "$target_pin" ]] || fail "子模块提交核验失败：${child_root}（应为 ${target_pin}）"
    log_message success "✔ 子模块已按父仓检出：${child_root} → ${target_pin}；来源：${PLAN_URLS[$index]}"
  done
}
# hard reset 也可能移除挡路的忽略文件，先检查两棵树中的路径碰撞。
assert_ignored_paths_safe() {
  local collision=""
  repo_git ls-files --others --ignored --exclude-standard --directory -z > "${LOCK_DIRECTORY}/ignored" || fail '无法检查忽略文件。'
  [[ -s "${LOCK_DIRECTORY}/ignored" ]] || return 0
  repo_git ls-tree -rz --name-only HEAD > "${LOCK_DIRECTORY}/protected-tree" || fail '无法检查当前文件树。'
  repo_git ls-tree -rz --name-only "$TARGET_HEAD" >> "${LOCK_DIRECTORY}/protected-tree" || fail '无法检查目标文件树。'
  collision="$(/usr/bin/perl -e '
    use strict; use warnings; use feature "fc";
    use Encode qw(decode FB_CROAK);
    use Unicode::Normalize qw(NFD);
    sub normalized { my ($value) = @_; return NFD(fc(decode("UTF-8", $value, FB_CROAK))); }
    my ($tree_file, $ignored_file) = @ARGV;
    my (%ignored, %parents);
    open my $ignored_fh, "<", $ignored_file or die "Cannot read ignored paths: $!";
    local $/ = "\0";
    while (my $item = <$ignored_fh>) {
      chomp $item; $item =~ s{/$}{};
      my $key = normalized($item);
      $ignored{$key} = $item;
      my $parent = $key;
      while ($parent =~ s{/[^/]+$}{}) { $parents{$parent} = $item; }
    }
    open my $tree_fh, "<", $tree_file or die "Cannot read tree paths: $!";
    while (my $path = <$tree_fh>) {
      chomp $path; $path = normalized($path);
      if (exists $ignored{$path}) { print $ignored{$path}; exit 0; }
      if (exists $parents{$path}) { print $parents{$path}; exit 0; }
      while ($path =~ s{/[^/]+$}{}) {
        if (exists $ignored{$path}) { print $ignored{$path}; exit 0; }
      }
    }
  ' "${LOCK_DIRECTORY}/protected-tree" "${LOCK_DIRECTORY}/ignored")" || fail '忽略文件保护检查失败。'
  [[ -z "$collision" ]] || fail "忽略内容可能被目标覆盖：${REPOSITORY}/${collision}；请先手动移走。"
}
# 对暂存、未暂存和未跟踪内容建立只读摘要，确认后仍需完全相同。
capture_worktree_fingerprint() {
  local item="" snapshot="${LOCK_DIRECTORY}/snapshot"
  repo_git diff --no-ext-diff --no-textconv --binary --ignore-submodules=all > "$snapshot" || fail '无法读取未暂存内容摘要。'
  repo_git diff --cached --no-ext-diff --no-textconv --binary --ignore-submodules=all >> "$snapshot" || fail '无法读取暂存内容摘要。'
  repo_git ls-files --others --exclude-standard -z > "${LOCK_DIRECTORY}/snapshot-paths" || fail '无法读取未跟踪内容摘要。'
  while IFS= read -r -d '' item; do
    print -rn -- "$item" >> "$snapshot" || fail '无法保存内容摘要。'
    printf '\0' >> "$snapshot" || fail '无法保存内容摘要。'
    if [[ -L "${REPOSITORY}/${item}" ]]; then
      /usr/bin/readlink "${REPOSITORY}/${item}" >> "$snapshot" || fail '无法读取符号链接摘要。'
    elif [[ -f "${REPOSITORY}/${item}" ]]; then
      repo_git hash-object --no-filters -- "$item" >> "$snapshot" || fail '无法读取未跟踪文件摘要。'
    else
      fail "不支持的未跟踪文件类型或文件已变化：${REPOSITORY}/${item}"
    fi
  done < "${LOCK_DIRECTORY}/snapshot-paths"
  /usr/bin/shasum -a 256 "$snapshot" | /usr/bin/awk '{ print $1 }'
}
# 列出全部会被舍弃的路径和本地独有提交，再等待精确 YES。
review_local_risk() {
  WORKTREE_STATE="$(repo_git status --porcelain=v1 --untracked-files=all --ignore-submodules=all)" || fail '无法检查工作区。'
  LOCAL_ONLY_COUNT="$(repo_git rev-list --count "${TARGET_HEAD}..HEAD")" || fail '无法检查本地独有提交。'
  WORKTREE_FINGERPRINT="$(capture_worktree_fingerprint)" || fail '无法建立工作区内容摘要。'
  if [[ -n "$WORKTREE_STATE" || "$LOCAL_ONLY_COUNT" != 0 ]]; then
    log_message danger '⚠ 高危：继续将永久舍弃以下本地内容；不生成 stash 或备份。'
    log_message danger "仓库：${REPOSITORY}"
    log_message danger "当前分支：${BRANCH}；当前提交：${ORIGINAL_HEAD}"
    log_message danger "恢复目标：${REMOTE}/${MERGE_REF#refs/heads/}；提交：${TARGET_HEAD}"
    [[ -z "$WORKTREE_STATE" ]] || log_message danger "待舍弃的暂存 / 未暂存 / 未跟踪路径："$'\n'"${WORKTREE_STATE}"
    if [[ "$LOCAL_ONLY_COUNT" != 0 ]]; then
      log_message danger "待舍弃的本地独有提交：${LOCAL_ONLY_COUNT} 个"
      log_message danger "$(repo_git log --format='%h %s' "${TARGET_HEAD}..HEAD")"
    fi
    log_message danger '删除预览（不包含忽略文件，不使用双重 -f）：'
    run_git clean -nd || fail '无法预览未跟踪文件清理。'
    log_message danger '只有精确输入大写 YES 才舍弃并同步；回车、其它输入或 Ctrl+C 均取消。'
    local answer=""
    [[ -t 0 && -t 1 ]] || fail '危险操作必须在可交互终端确认。'
    print -n -r -- "${COLOR_RED}请输入 YES：${COLOR_RESET}"
    IFS= read -r answer || { log_message info '已取消，未舍弃本地内容。'; exit 2; }
    [[ "$answer" == YES ]] || { log_message info '已取消，未舍弃本地内容。'; exit 2; }
    log_message danger '已确认 YES：仅授权本次显示的仓库和固定目标。'
  fi
}
# 用户确认后重新核对 HEAD、分支、配置及路径，避免沿用失效计划。
assert_plan_unchanged() {
  assert_repository_ready
  [[ "$(repo_git symbolic-ref --quiet --short HEAD)" == "$BRANCH" && "$(repo_git rev-parse HEAD)" == "$ORIGINAL_HEAD" ]] || fail '确认期间分支或 HEAD 已变化，请重新运行。'
  [[ "$(repo_git config --get-all "branch.${BRANCH}.remote")" == "$REMOTE" && "$(repo_git config --get-all "branch.${BRANCH}.merge")" == "$MERGE_REF" ]] || fail '确认期间上游配置已变化，请重新运行。'
  [[ "$(repo_git status --porcelain=v1 --untracked-files=all --ignore-submodules=all)" == "$WORKTREE_STATE" ]] || fail '确认期间工作区状态已变化，请重新运行。'
  [[ "$(capture_worktree_fingerprint)" == "$WORKTREE_FINGERPRINT" ]] || fail '确认期间文件内容已变化，请重新运行并重新确认。'
  [[ "$(repo_git config --get-all "remote.${REMOTE}.url")" == "$SOURCE_URL" ]] || fail '确认期间远程来源已变化，请重新运行。'
  assert_worktree_paths_safe
  assert_submodule_plan_unchanged
  assert_ignored_paths_safe
}
# 干净分支仅快进；有明确 YES 授权时才 reset 和清理非忽略内容。
synchronize_repository() {
  SYNC_STARTED=1
  if [[ -n "$WORKTREE_STATE" || "$LOCAL_ONLY_COUNT" != 0 ]]; then
    run_git reset --hard --no-recurse-submodules "$TARGET_HEAD" || fail '重置失败，已停止；请检查工作区与日志。'
    run_git clean -fd || fail '清理失败，已停止；请检查工作区与日志。'
  elif [[ "$ORIGINAL_HEAD" != "$TARGET_HEAD" ]]; then
    run_git -c "branch.${BRANCH}.mergeOptions=" merge --ff-only --no-autostash --no-edit "$TARGET_HEAD" || fail '无法安全快进，已停止。'
  fi
  [[ "$(repo_git rev-parse HEAD)" == "$TARGET_HEAD" ]] || fail '同步后提交号核验失败。'
  synchronize_submodule_plan
  [[ -z "$(repo_git status --porcelain=v1 --untracked-files=all --ignore-submodules=none)" ]] || fail '同步后仍有本地变化，未标记成功。'
  log_message success "✔ 已同步：${BRANCH} → ${TARGET_HEAD}"
  log_message success "来源：${EFFECTIVE_URL}；${#PLAN_PATHS} 个子模块已按父仓固定提交核验；未执行提交或推送。"
  log_message info "日志：${LOG_FILE}"
}
# 从正在运行的进程解析真实 App 位置，只接受官方 SourceTree 标识。
find_running_sourcetree() {
  SOURCETREE_APP=""
  SOURCETREE_BUNDLE_ID=""
  local process_ids="" process_id="" process_path="" app_path="" bundle_id=""
  process_ids="$(/usr/bin/pgrep -x 'Sourcetree|SourceTree' 2>/dev/null)" || return 1
  for process_id in "${(@f)process_ids}"; do
    process_path="$(/bin/ps -p "$process_id" -o comm= 2>/dev/null)" || continue
    [[ "$process_path" == /*.app/Contents/MacOS/* ]] || continue
    app_path="${process_path%%.app/Contents/MacOS/*}.app"
    bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "${app_path}/Contents/Info.plist" 2>/dev/null)" || continue
    case "$bundle_id" in
      com.torusknot.SourceTreeNotMAS|com.torusknot.SourceTree)
        SOURCETREE_APP="$app_path"
        SOURCETREE_BUNDLE_ID="$bundle_id"
        return 0
        ;;
    esac
  done
  return 1
}
# 用运行时解析的 App 打开精确目标目录，不另开未知安装副本。
open_sourcetree_repository() {
  /usr/bin/open -a "$SOURCETREE_APP" "$REPOSITORY"
}
# 只在已核对路径的仓库窗口点“刷新”，避免按键落到其它仓库或对话框。
request_sourcetree_refresh() {
  /usr/bin/osascript - "$SOURCETREE_BUNDLE_ID" "$REPOSITORY" <<'APPLESCRIPT'
on run argv
  set bundleId to item 1 of argv
  set repositoryPath to item 2 of argv
  set repositoryIdentifier to "repo:" & repositoryPath
  considering case
    with timeout of 15 seconds
      tell application "System Events"
        if not UI elements enabled then error "辅助功能不可用，请在目标仓库手动按 Cmd+R。"
        set targetProcess to first application process whose bundle identifier is bundleId
        tell targetProcess
          set targetWindow to missing value
          repeat 40 times
            repeat with candidateWindow in windows
              try
                if (value of attribute "AXIdentifier" of candidateWindow) is repositoryIdentifier then
                  set targetWindow to candidateWindow
                  exit repeat
                end if
              end try
            end repeat
            if targetWindow is not missing value then exit repeat
            delay 0.1
          end repeat
          if targetWindow is missing value then error "未找到目标仓库窗口，未发送刷新。"
          if (count of sheets of targetWindow) > 0 then error "目标仓库存在对话框，未发送刷新。"
          perform action "AXRaise" of targetWindow
          set frontmost to true
          if (value of attribute "AXIdentifier" of window 1) is not repositoryIdentifier then error "前台仓库与目标不符，未发送刷新。"
          set repositoryMenu to missing value
          repeat with menuLabel in {"仓库", "Repository"}
            if exists menu bar item (contents of menuLabel) of menu bar 1 then
              set repositoryMenu to menu 1 of menu bar item (contents of menuLabel) of menu bar 1
              exit repeat
            end if
          end repeat
          if repositoryMenu is missing value then error "未找到仓库菜单，请手动按 Cmd+R。"
          repeat with refreshLabel in {"刷新", "Refresh"}
            if exists menu item (contents of refreshLabel) of repositoryMenu then
              if not enabled of menu item (contents of refreshLabel) of repositoryMenu then error "刷新命令不可用，未发送刷新。"
              if (value of attribute "AXIdentifier" of window 1) is not repositoryIdentifier then error "前台仓库已变化，未发送刷新。"
              click menu item (contents of refreshLabel) of repositoryMenu
              return "已发送当前仓库刷新"
            end if
          end repeat
          error "未找到刷新命令，请手动按 Cmd+R。"
        end tell
      end tell
    end timeout
  end considering
end run
APPLESCRIPT
}
# Git 成功后单独刷新界面；UI 失败只提示，不重复同步或清理用户配置。
refresh_sourcetree_after_pull() {
  local counts="" ahead="" behind="" refresh_output=""
  counts="$(repo_git rev-list --left-right --count "HEAD...${TRACKING_REF}")" || counts=""
  if [[ "$counts" == <->$'\t'<-> ]]; then
    ahead="${counts%%$'\t'*}"
    behind="${counts#*$'\t'}"
    log_message info "Git 实际状态：${BRANCH} 相对 ${REMOTE}/${MERGE_REF#refs/heads/}，待推送 ${ahead}，待拉取 ${behind}。"
  else
    log_message info '⚠ 无法读出最新待推送 / 待拉取计数；Git 同步核验已完成。'
  fi
  if ! find_running_sourcetree; then
    log_message info 'SourceTree 未运行或无法识别，跳过界面缓存刷新；下次打开目标仓库后可按 Cmd+R。'
    return 0
  fi
  log_message info "正在请求 SourceTree 刷新仓库界面缓存：${REPOSITORY}；不删除磁盘缓存或用户配置。"
  if ! refresh_output="$(open_sourcetree_repository 2>&1)"; then
    log_message info "⚠ Git 已同步，但无法在 SourceTree 打开目标仓库：${refresh_output}；请在该仓库手动按 Cmd+R，无需重跑同步。"
    return 0
  fi
  if refresh_output="$(request_sourcetree_refresh 2>&1)"; then
    log_message success '✔ 已向 SourceTree 当前仓库发送清缓存刷新（仓库 → 刷新 / Cmd+R）；界面数字由应用重新计算。'
  else
    log_message info "⚠ Git 已同步，SourceTree 自动刷新未完成：${refresh_output}；请在目标仓库手动按 Cmd+R。自动化或辅助功能权限不足时，在系统设置中授权实际启动终端后再用；不需要重跑 Git 同步。"
  fi
  return 0
}
# 逐步完成根仓及固定子模块的安全拉取，任何失败立即停止后续步骤。
main() {
  show_script_intro_and_wait "$@" # 先显示自述，由 SourceTree 转交终端并确认。
  initialize_runtime # 确认后建立私有日志与退出清理。
  resolve_repository "$@" # 校验目标并防止同一动作并行运行。
  assert_repository_ready # 未完成 Git 操作和隐藏状态先停止。
  resolve_upstream # 仅使用当前分支明确配置的远程上游。
  fetch_target # 先抓取，失败可回车重试，成功固定提交后才进入同步预检。
  assert_nested_repositories_safe # 子模块及嵌套仓库不纳入清理授权。
  assert_ignored_paths_safe # 防止 hard reset 间接覆盖忽略内容。
  review_local_risk # 红字列明风险，危险操作强制精确 YES。
  assert_plan_unchanged # 写操作前重新核对确认计划。
  synchronize_repository # 安全快进或按 YES 授权舍弃并核验结果。
  refresh_sourcetree_after_pull # Git 核验成功后刷新当前仓库的界面缓存并显示真实计数。
}

main "$@"
