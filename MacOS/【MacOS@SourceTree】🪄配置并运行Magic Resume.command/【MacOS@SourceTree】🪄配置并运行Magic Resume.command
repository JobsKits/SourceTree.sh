#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】🪄配置并运行Magic Resume.command
# - 核心用途：校验或同级拉取 JOYCEQL/magic-resume，安装依赖并后台启动开发服务器。
# - 影响范围：可能新建同级仓库目录、安装 Node.js / pnpm、写入 node_modules，并启动本地 3000 端口服务。
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

# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
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
  jobs_prompt_output print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
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
  if curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
    /bin/bash "$installer" || installer_result=$?
  else
    installer_result=1
  fi
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return 1
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
    jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
    return 1
  }
  if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
    jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
    return 1
  fi
  git_bin="$(command -v git 2>/dev/null)"
  [[ -n "$git_bin" ]] && "$git_bin" --version >/dev/null 2>&1 || { jobs_brew_note "用户目录安装需要可用 Git；请先准备 Git / Command Line Tools。"; return 1; }
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
  export HOMEBREW_NO_SUDO=1
  mkdir -p "${prefix:h}" || return 1
  stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
  if ! curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$stage/release.json"; then
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本失败，停止安装。"
    return 1
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] ||
     ! GIT_TERMINAL_PROMPT=0 "$git_bin" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$release_tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" ||
     ! "$git_bin" -C "$stage/brew" checkout -b stable ||
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
      system) jobs_brew_install_system || exit 1 ;;
      user) jobs_brew_install_user || exit 1 ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}
# <<< Jobs Homebrew install choice <<<
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
EXPECTED_DISPLAY_SLUG="JOYCEQL/magic-resume"
EXPECTED_SLUG="joyceql/magic-resume"
EXPECTED_HTTPS_URL="https://github.com/JOYCEQL/magic-resume"
CLONE_URL="https://github.com/JOYCEQL/magic-resume.git"
LOCAL_URL="http://localhost:3000"
LOCAL_PORT="3000"

SCRIPT_ENTRY_SOURCE="$0"
SCRIPT_PATH=""
SCRIPT_DIR=""
SCRIPT_BASENAME=""
LOG_FILE=""
DEV_SERVER_LOG=""
DEV_SERVER_PID_FILE=""
IS_SOURCETREE_RUNTIME=0
PLAIN_OUTPUT=0
RUNTIME_INITIALIZED=0

INPUT_REPO_ROOT=""
REPO_ROOT=""
REPO_INPUT_SOURCE=""
MATCHED_REMOTE=""
SIBLING_TARGET=""
SIBLING_TARGET_REQUIRES_CLONE=0
SERVER_REUSED=0

BREW_BIN=""
NODE_BIN=""
NPM_BIN=""
PNPM_BIN=""
PACKAGE_MANAGER_SPEC="pnpm@latest"

# 从绝对路径、当前目录和两个固定脚本库中找回脚本真实路径。
resolve_script_path() {
  local script_source="$SCRIPT_ENTRY_SOURCE"
  local script_name="$(basename -- "$script_source")"
  local candidate=""

  for candidate in \
    "$script_source" \
    "${PWD}/${script_source}" \
    "${HOME}/SourceTree.command/MacOS/${script_name}/${script_name}" \
    "${HOME}/Documents/Github/JobsGenesis/SourceTree.command/MacOS/${script_name}/${script_name}"; do
    [[ -n "$candidate" && -f "$candidate" ]] || continue
    (cd "$(dirname "$candidate")" 2>/dev/null && printf "%s/%s\n" "$(pwd -P)" "$(basename "$candidate")")
    return 0
  done

  printf "%s/%s\n" "$PWD" "$script_name"
}
# 准备仅用于首屏自述的脚本路径和日志名称，不提前写文件。
resolve_script_metadata() {
  local temp_root="${TMPDIR:-/tmp}"

  SCRIPT_PATH="$(resolve_script_path)"
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd -P)"
  SCRIPT_BASENAME="$(basename "$SCRIPT_PATH" | sed 's/\.[^.]*$//')"
  temp_root="${temp_root%/}"
  LOG_FILE="${temp_root}/${SCRIPT_BASENAME}.log"
  DEV_SERVER_LOG="${temp_root}/${SCRIPT_BASENAME}-dev.log"
  DEV_SERVER_PID_FILE="${temp_root}/${SCRIPT_BASENAME}-dev.pid"
}
# 组合环境变量、脚本解析路径和父进程链识别 Sourcetree 自定义动作。
is_sourcetree_runtime() {
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
# 去除 ANSI 控制字符，避免 Sourcetree 输出窗口和日志出现乱码。
strip_ansi_stream() {
  if command -v perl >/dev/null 2>&1; then
    perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e\][^\a]*(?:\a|\e\\)//g; s/\e[()][A-Za-z0-9]//g'
  else
    cat
  fi
}
# 在任何首屏输出前配置 Sourcetree 和非 TTY 场景的纯文本环境。
prepare_plain_output_context() {
  [[ -n "${TERM:-}" ]] || export TERM="dumb"
  if [[ "$IS_SOURCETREE_RUNTIME" == "1" || ! -t 1 || "$TERM" == "dumb" || -n "${NO_COLOR+x}" || "${JOBS_PLAIN_OUTPUT:-0}" == "1" ]]; then
    PLAIN_OUTPUT=1
    export NO_COLOR=1
    export FORCE_COLOR=0
    export CLICOLOR=0
    export ANSI_COLORS_DISABLED=1
    export npm_config_color=false
  else
    PLAIN_OUTPUT=0
  fi
}
# 同步输出运行信息；确认前只写屏幕，运行态初始化后同时写入日志。
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
# 打印内置自述，并按真实运行入口决定是否等待回车。
show_script_intro_and_wait() {
  resolve_script_metadata
  is_sourcetree_runtime && IS_SOURCETREE_RUNTIME=1
  prepare_plain_output_context

  if [[ -z "${NO_COLOR+x}" && "$IS_SOURCETREE_RUNTIME" != "1" && "$PLAIN_OUTPUT" != 1 && -t 1 && "$TERM" != "dumb" ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 ==============================" | jobs_intro_style title
  note_echo "脚本名称：${SCRIPT_BASENAME}.command" | jobs_intro_style title
  note_echo "核心用途：校验当前仓库；不匹配时先扫描全部同级仓库，确实不存在 ${EXPECTED_DISPLAY_SLUG} 才创建目录并克隆。" | jobs_intro_style body
  note_echo "运行策略：开发服务器使用 nohup 脱离终端后台运行；3000 端口就绪后自动打开浏览器，脚本随即结束。" | jobs_intro_style body
  warn_echo "影响范围：可能创建同级目录、安装 Node.js / pnpm、写入 node_modules，并将当前仓库已有的前台 Vite 服务重启为后台服务。" | jobs_intro_style body
  gray_echo "仓库地址：${EXPECTED_HTTPS_URL}" | jobs_intro_style body
  gray_echo "业务日志：${LOG_FILE}" | jobs_intro_style body
  gray_echo "服务日志：${DEV_SERVER_LOG}" | jobs_intro_style body
  gray_echo "取消方式：终端模式可在确认前按 Ctrl+C；Sourcetree 模式按自定义动作约定无交互连续执行。" | jobs_intro_style body
  highlight_echo "============================================================================" | jobs_intro_style title
  log "" | jobs_intro_style body

  if [[ "$IS_SOURCETREE_RUNTIME" == "1" ]]; then
    gray_echo "已识别为 Sourcetree 自定义动作，将跳过交互并连续执行。" | jobs_intro_style body
    return 0
  fi
  if [[ ! -t 0 ]]; then
    error_echo "当前不是 Sourcetree，且没有可交互输入；请在终端中重新运行。"
    exit 1
  fi
  read -r "?$(jobs_prompt_render "👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：")" _ || exit 1
}
# 在用户确认后初始化 Shell 选项、PATH、日志文件和输出环境。
initialize_script_runtime() {
  setopt NO_NOMATCH
  setopt PIPE_FAIL
  export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
  : > "$LOG_FILE"
  RUNTIME_INITIALIZED=1
  prepare_plain_output_context
  info_echo "运行环境初始化完成。"
  gray_echo "脚本路径：${SCRIPT_PATH}"
}
# 输出错误和日志位置后终止脚本。
die() {
  error_echo "$1"
  err_echo "业务日志：${LOG_FILE}"
  exit 1
}
# 执行外部命令并把去色后的输出同步写入业务日志。
run_cmd() {
  local title="$1"
  shift
  info_echo "$title"
  gray_echo "命令：$*"
  "$@" 2>&1 | strip_ansi_stream | tee -a "$LOG_FILE"
  local command_status="${pipestatus[1]}"
  if [[ "$command_status" -ne 0 ]]; then
    error_echo "命令执行失败：${title}"
    return "$command_status"
  fi
  success_echo "完成：${title}"
}
# 清理完整外围引号及末尾换行，保留文件名内部引号和反斜线。
strip_outer_quotes() {
  local value="$1"
  while [[ "$value" == *$'\r' || "$value" == *$'\n' ]]; do
    value="${value%?}"
  done
  if (( ${#value} >= 2 )) && [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
    value="${value[2,-2]}"
  fi
  print -r -- "$value"
}
# 按字面解析 argv 路径，仅去除完整外围引号、换行并展开家目录缩写。
normalize_user_input_path() {
  local value="$(strip_outer_quotes "$1")"
  if [[ "$value" == "~" ]]; then
    value="$HOME"
  elif [[ "$value" == "~/"* ]]; then
    value="${HOME}/${value#\~/}"
  fi
  print -r -- "$value"
}
# 从目录或仓库内文件向上解析 Git 工作区根目录。
resolve_repo_root_from_candidate() {
  local candidate="$(normalize_user_input_path "$1")"
  local candidate_abs=""

  [[ -e "$candidate" ]] || return 1
  [[ -d "$candidate" ]] || candidate="${candidate:h}"
  candidate_abs="$(cd "$candidate" 2>/dev/null && pwd -P || true)"
  [[ -n "$candidate_abs" ]] || return 1
  git -C "$candidate_abs" rev-parse --show-toplevel 2>/dev/null
}
# 在终端独立运行时提示输入一个可识别的 Git 仓库路径。
prompt_input_repository() {
  local input_path=""
  local resolved=""

  while true; do
    read -r "input_path?👉 请输入或拖入当前 Git 仓库目录（Ctrl+C 取消）：" input_path || die "路径输入已结束，停止执行。"
    input_path="$(normalize_user_input_path "$input_path")"
    if [[ ! -e "$input_path" ]]; then
      local unescaped_path="${(Q)input_path}"
      [[ ! -e "$unescaped_path" ]] || input_path="$unescaped_path"
    fi
    resolved="$(resolve_repo_root_from_candidate "$input_path" 2>/dev/null || true)"
    if [[ -n "$resolved" ]]; then
      INPUT_REPO_ROOT="$resolved"
      REPO_INPUT_SOURCE="手动输入/拖入路径"
      return 0
    fi
    warn_echo "无法从该路径识别 Git 仓库，请重新输入。"
  done
}
# 从 SourceTree 的 REPO 参数、命令行参数或当前目录确定运行仓库。
resolve_input_repository() {
  (( $# <= 1 )) || die "只接受一个仓库路径，请给含空格的路径加引号。"
  local candidate="${1:-${SOURCETREE_REPO_PATH:-${REPO:-$PWD}}}" resolved=""
  resolved="$(resolve_repo_root_from_candidate "$candidate" 2>/dev/null || true)"
  if [[ -n "$resolved" ]]; then
    INPUT_REPO_ROOT="$resolved"
    REPO_INPUT_SOURCE="参数 / 环境 / 当前目录"
  elif (( $# > 0 )) || [[ -n "${SOURCETREE_REPO_PATH:-}${REPO:-}" || "$IS_SOURCETREE_RUNTIME" == 1 || ! -t 0 ]]; then
    die "指定路径无法识别为 Git 仓库：$candidate；Sourcetree 参数请填 \$REPO。"
  else
    prompt_input_repository
  fi
  success_echo "已识别运行仓库：${INPUT_REPO_ROOT}"
  gray_echo "仓库来源：${REPO_INPUT_SOURCE}"
}
# 把 GitHub 的常见 HTTPS、SSH 和 git 协议地址归一化为小写 owner/repo。
normalize_github_remote() {
  local url="$1"
  local slug=""

  url="${url//$'\r'/}"
  url="${url//$'\n'/}"
  url="${url%/}"
  url="${url%.git}"

  case "$url" in
    https://github.com/*) slug="${url#https://github.com/}" ;;
    http://github.com/*) slug="${url#http://github.com/}" ;;
    git@github.com:*) slug="${url#git@github.com:}" ;;
    ssh://git@github.com/*) slug="${url#ssh://git@github.com/}" ;;
    git://github.com/*) slug="${url#git://github.com/}" ;;
    github.com:*) slug="${url#github.com:}" ;;
    github.com/*) slug="${url#github.com/}" ;;
    *) slug="" ;;
  esac

  slug="${slug%.git}"
  slug="${slug%/}"
  print -r -- "${(L)slug}"
}
# 检查目标目录的任意 remote 是否指向官方 magic-resume 仓库。
repository_matches_expected() {
  local repository="$1"
  local remotes_output="$(git -C "$repository" remote 2>/dev/null || true)"
  local urls_output=""
  local remote=""
  local url=""

  [[ -n "$remotes_output" ]] || return 1
  for remote in ${(f)remotes_output}; do
    urls_output="$(git -C "$repository" remote get-url --all "$remote" 2>/dev/null || true)"
    for url in ${(f)urls_output}; do
      if [[ "$(normalize_github_remote "$url")" == "$EXPECTED_SLUG" ]]; then
        MATCHED_REMOTE="${remote}:${url}"
        return 0
      fi
    done
  done
  return 1
}
# 判断候选文件夹是否存在且完全为空。
directory_is_empty() {
  local directory="$1" entries=""
  [[ -d "$directory" ]] || return 1
  entries="$(find "$directory" -mindepth 1 -maxdepth 1 -print -quit 2>&1)" || die "无法枚举候选目录，停止克隆：${directory}；${entries}"
  [[ -z "$entries" ]]
}
# 扫描父目录第一层的全部文件夹，寻找任意名称但 remote 匹配的同级仓库。
find_existing_expected_sibling_repository() {
  local parent_dir="${INPUT_REPO_ROOT:h}"
  local sibling=""
  local sibling_abs=""
  local repository_root=""

  info_echo "正在扫描当前仓库的全部同级目录：${parent_dir}"
  while IFS= read -r -d '' sibling; do
    [[ -d "$sibling" ]] || continue
    sibling_abs="$(cd "$sibling" 2>/dev/null && pwd -P || true)"
    [[ -n "$sibling_abs" && "$sibling_abs" != "$INPUT_REPO_ROOT" ]] || continue
    [[ -d "$sibling_abs/.git" || -f "$sibling_abs/.git" ]] || continue

    repository_root="$(git -C "$sibling_abs" rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "$repository_root" ]] || continue
    repository_root="$(cd "$repository_root" 2>/dev/null && pwd -P || true)"
    [[ "$repository_root" == "$sibling_abs" ]] || continue

    if repository_matches_expected "$sibling_abs"; then
      SIBLING_TARGET="$sibling_abs"
      SIBLING_TARGET_REQUIRES_CLONE=0
      success_echo "已在同级目录找到官方仓库：${SIBLING_TARGET}"
      gray_echo "匹配 remote：${MATCHED_REMOTE}"
      return 0
    fi
  done < <(
    find "$parent_dir" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -print0 2>/dev/null
  )

  warn_echo "同级目录中没有找到 ${EXPECTED_DISPLAY_SLUG}，将选择安全的空目录用于克隆。"
  return 1
}
# 确认同级目录不存在官方仓库后，选择可安全克隆的空路径。
select_sibling_target() {
  local parent_dir="${INPUT_REPO_ROOT:h}"
  local -a candidate_names=("magic-resume" "magic-resume-JOYCEQL")
  local index=0
  local candidate_name=""
  local candidate=""

  find_existing_expected_sibling_repository && return 0

  for index in {2..20}; do
    candidate_names+=("magic-resume-JOYCEQL-${index}")
  done

  for candidate_name in "${candidate_names[@]}"; do
    candidate="${parent_dir}/${candidate_name}"
    [[ "$candidate" == "$INPUT_REPO_ROOT" ]] && continue

    if [[ ! -e "$candidate" ]]; then
      SIBLING_TARGET="$candidate"
      SIBLING_TARGET_REQUIRES_CLONE=1
      return 0
    fi
    if [[ -d "$candidate" ]] && repository_matches_expected "$candidate"; then
      SIBLING_TARGET="$candidate"
      SIBLING_TARGET_REQUIRES_CLONE=0
      return 0
    fi
    if directory_is_empty "$candidate"; then
      SIBLING_TARGET="$candidate"
      SIBLING_TARGET_REQUIRES_CLONE=1
      return 0
    fi

    warn_echo "同级候选已被其它内容占用，已跳过：${candidate}"
  done

  die "当前仓库同级目录中没有可安全创建或复用的 magic-resume 路径。"
}
# 在空的同级目录中克隆官方仓库，不覆盖任何既有非空内容。
clone_expected_repository() {
  local target_preexisted=0
  [[ -e "$SIBLING_TARGET" ]] && target_preexisted=1

  if [[ "${JOBS_MAGIC_RESUME_DRY_RUN:-0}" == "1" ]]; then
    success_echo "Dry-run：计划创建/复用空目录并克隆 ${CLONE_URL}"
    gray_echo "目标目录：${SIBLING_TARGET}"
    exit 0
  fi

  if [[ "$target_preexisted" == "0" ]]; then
    mkdir "$SIBLING_TARGET" || die "无法创建同级空目录：${SIBLING_TARGET}"
    success_echo "已创建同级空目录：${SIBLING_TARGET}"
  elif ! directory_is_empty "$SIBLING_TARGET"; then
    die "克隆目标不是空目录，已停止以避免覆盖：${SIBLING_TARGET}"
  fi

  run_cmd "克隆 ${EXPECTED_DISPLAY_SLUG}" git clone "$CLONE_URL" "$SIBLING_TARGET" || die "仓库克隆失败；已保留现场，请根据日志检查网络或 Git 凭据。"
  repository_matches_expected "$SIBLING_TARGET" || die "克隆完成后 remote 校验失败：${SIBLING_TARGET}"
}
# 使用当前正确仓库，或切换到同级已存在/新克隆的官方仓库。
select_magic_resume_repository() {
  if repository_matches_expected "$INPUT_REPO_ROOT"; then
    REPO_ROOT="$INPUT_REPO_ROOT"
    success_echo "当前仓库校验通过：${MATCHED_REMOTE}"
  else
    warn_echo "当前仓库不是 ${EXPECTED_HTTPS_URL}，开始处理同级目录。"
    select_sibling_target
    if [[ "$SIBLING_TARGET_REQUIRES_CLONE" == "1" ]]; then
      clone_expected_repository
    else
      success_echo "已找到同级官方仓库，将直接复用：${SIBLING_TARGET}"
    fi
    REPO_ROOT="$SIBLING_TARGET"
  fi

  cd "$REPO_ROOT" || die "无法进入 magic-resume 仓库：${REPO_ROOT}"
  success_echo "已切换到 magic-resume 仓库：${REPO_ROOT}"
}
# 检查 macOS、Git、curl、lsof、nohup 和浏览器打开命令。
check_base_environment() {
  [[ "$(uname -s)" == "Darwin" ]] || die "该脚本仅支持 macOS。"
  local command_name=""
  for command_name in git curl lsof nohup open; do
    command -v "$command_name" >/dev/null 2>&1 || die "缺少必要命令：${command_name}"
  done
  git --version >/dev/null 2>&1 || die "Git 健康检查失败；请先修复 Git / Command Line Tools。"
  success_echo "macOS 基础命令与 Git 健康检查通过。"
}
# 按 Apple Silicon、Intel 和当前 PATH 顺序寻找 Homebrew。
find_brew() {
  jobs_brew_find
}
# 激活已安装 Homebrew 的真实 shellenv 和可执行路径。
activate_brew() {
  JOBS_HOMEBREW_BIN="$BREW_BIN"
  jobs_brew_activate
}
# 确认 Node.js 与 npm 可用；缺失时仅通过已有 Homebrew 安装。
ensure_node_runtime() {
  NODE_BIN="$(command -v node 2>/dev/null || true)"
  NPM_BIN="$(command -v npm 2>/dev/null || true)"
  if [[ -n "$NODE_BIN" && -n "$NPM_BIN" ]] && "$NODE_BIN" --version >/dev/null 2>&1 && "$NPM_BIN" --version >/dev/null 2>&1; then
    success_echo "Node.js / npm 健康检查通过：$($NODE_BIN --version)"
    return 0
  fi
  [[ "${JOBS_MAGIC_RESUME_DRY_RUN:-0}" != 1 ]] || die "Dry-run 不安装工具链；请先准备可用 Node.js / npm。"
  jobs_brew_install_or_exit
  BREW_BIN="$JOBS_HOMEBREW_BIN"
  activate_brew || die "Homebrew 环境激活失败。"
  run_cmd "通过 Homebrew 安装 Node.js" "$BREW_BIN" install node || die "Node.js 安装失败。"
  activate_brew || die "安装后 Homebrew 环境刷新失败。"
  NODE_BIN="$(command -v node 2>/dev/null || true)"
  NPM_BIN="$(command -v npm 2>/dev/null || true)"
  [[ -n "$NODE_BIN" && -n "$NPM_BIN" ]] && "$NODE_BIN" --version >/dev/null 2>&1 && "$NPM_BIN" --version >/dev/null 2>&1 || die "安装后 Node.js / npm 仍不可用，停止后续业务。"
}
# 把 npm 全局可执行目录补入当前 PATH。
refresh_npm_global_path() {
  local npm_prefix="$($NPM_BIN prefix -g 2>/dev/null || true)"
  if [[ -n "$npm_prefix" && -d "${npm_prefix}/bin" ]]; then
    export PATH="${npm_prefix}/bin:$PATH"
  fi
  hash -r 2>/dev/null || true
}
# 读取项目声明并保证 pnpm 可用，避免 Sourcetree 的精简 PATH 找不到命令。
ensure_pnpm_runtime() {
  PACKAGE_MANAGER_SPEC="$($NODE_BIN -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.stdout.write(p.packageManager||"")' "$REPO_ROOT/package.json" 2>/dev/null || true)"
  [[ "$PACKAGE_MANAGER_SPEC" == pnpm@* ]] || PACKAGE_MANAGER_SPEC="pnpm@latest"
  PNPM_BIN="$(command -v pnpm 2>/dev/null || true)"

  if [[ -z "$PNPM_BIN" ]] || ! "$PNPM_BIN" --version >/dev/null 2>&1; then
    [[ "${JOBS_MAGIC_RESUME_DRY_RUN:-0}" != 1 ]] || die "Dry-run 不安装 pnpm；请先准备项目所需 pnpm。"
    run_cmd "安装项目声明的 pnpm：${PACKAGE_MANAGER_SPEC}" "$NPM_BIN" install --global "$PACKAGE_MANAGER_SPEC" || die "pnpm 安装失败，请检查 npm 全局目录权限。"
    refresh_npm_global_path
    PNPM_BIN="$(command -v pnpm 2>/dev/null || true)"
  fi

  [[ -n "$PNPM_BIN" && -x "$PNPM_BIN" ]] && "$PNPM_BIN" --version >/dev/null 2>&1 || die "pnpm 安装后健康检查失败。"
  success_echo "已检测到 pnpm：$($PNPM_BIN --version)"
}
# 核对仓库 remote 和快速开始所需的关键项目文件。
validate_magic_resume_project() {
  repository_matches_expected "$REPO_ROOT" || die "目标目录 remote 已变化，不再是 ${EXPECTED_HTTPS_URL}。"
  [[ -f "$REPO_ROOT/package.json" ]] || die "仓库缺少 package.json：${REPO_ROOT}"
  [[ -f "$REPO_ROOT/pnpm-lock.yaml" ]] || die "仓库缺少 pnpm-lock.yaml：${REPO_ROOT}"
  grep -Fq '"dev"' "$REPO_ROOT/package.json" || die "package.json 缺少 dev 脚本。"
  success_echo "magic-resume 项目结构检查通过。"
}
# 按官方 README 执行 pnpm install；Dry-run 只展示命令。
install_project_dependencies() {
  if [[ "${JOBS_MAGIC_RESUME_DRY_RUN:-0}" == "1" ]]; then
    success_echo "Dry-run：计划在 ${REPO_ROOT} 执行 pnpm install。"
    return 0
  fi
  run_cmd "安装 magic-resume 项目依赖" "$PNPM_BIN" install || die "pnpm install 执行失败。"
}
# 返回当前监听 3000 端口的进程 ID。
port_listener_pids() {
  lsof -nP -tiTCP:"$LOCAL_PORT" -sTCP:LISTEN 2>/dev/null || true
}
# 核验全部监听进程均为当前仓库 Vite dev，避免 IPv4 / IPv6 混合占用误判。
listener_belongs_to_repository() {
  local pids_output="$(port_listener_pids)"
  local listener_pid="" listener_cwd="" selected_pid=""

  [[ -n "$pids_output" ]] || return 1
  for listener_pid in ${(f)pids_output}; do
    [[ "$listener_pid" == <-> ]] || return 1
    listener_cwd="$(lsof -a -p "$listener_pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)"
    [[ -n "$listener_cwd" ]] || return 1
    listener_cwd="$(cd "$listener_cwd" 2>/dev/null && pwd -P || true)"
    [[ "$listener_cwd" == "$REPO_ROOT" ]] || return 1
    process_is_vite_dev_server "$listener_pid" || return 1
    [[ -n "$selected_pid" ]] || selected_pid="$listener_pid"
  done
  [[ -n "$selected_pid" ]] || return 1
  print -r -- "$selected_pid"
}
# 检查监听进程命令是否明确属于 Vite 开发服务器。
process_is_vite_dev_server() {
  local process_executable="$(ps -p "$1" -o comm= 2>/dev/null || true)"
  local process_command="$(ps -p "$1" -o command= 2>/dev/null || true)"
  local vite_entry="${REPO_ROOT}/node_modules/vite/bin/vite.js"
  local node_prefix="" candidate="" expected_prefix="" arguments="" subcommand=""
  local -a node_prefixes=("$process_executable" "${process_executable:t}")
  local -a vite_entries=("$vite_entry" "${vite_entry:A}" "${REPO_ROOT}/node_modules/.bin/../vite/bin/vite.js")

  [[ "${process_executable:t}" == node && -f "$vite_entry" ]] || return 1
  if [[ -n "$NODE_BIN" ]]; then
    node_prefixes+=("$NODE_BIN" "${NODE_BIN:A}")
  fi
  for node_prefix in "${node_prefixes[@]}"; do
    [[ -n "$node_prefix" ]] || continue
    for candidate in "${vite_entries[@]}"; do
      expected_prefix="${node_prefix} ${candidate} "
      [[ "$process_command" == "$expected_prefix"* ]] || continue
      arguments="${process_command#"$expected_prefix"}"
      subcommand="${arguments%%[[:space:]]*}"
      [[ "$subcommand" == dev || "$subcommand" == serve ]] && return 0
    done
  done
  return 1
}
# 读取脚本上次记录的实际监听进程 PID，并过滤过期或非法内容。
read_managed_server_pid() {
  local managed_pid=""
  [[ -f "$DEV_SERVER_PID_FILE" ]] || return 1
  managed_pid="$(sed -n '1p' "$DEV_SERVER_PID_FILE" 2>/dev/null | tr -d '[:space:]')"
  [[ "$managed_pid" == <-> ]] || return 1
  print -r -- "$managed_pid"
}
# 检查本地首页是否已经返回可接受的 HTTP 响应。
server_is_ready() {
  curl --silent --show-error --fail --max-time 2 --output /dev/null "$LOCAL_URL" 2>/dev/null
}
# 在限定时间内等待后台开发服务器就绪。
wait_for_development_server() {
  local max_seconds="${1:-60}"
  local elapsed=0

  while [[ "$elapsed" -lt "$max_seconds" ]]; do
    server_is_ready && return 0
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}
# 停止当前仓库未由本脚本托管的前台 Vite 服务，为后台重启释放端口。
stop_unmanaged_vite_server() {
  local listener_pid="$1"
  local elapsed=0

  process_is_vite_dev_server "$listener_pid" || die "3000 端口进程属于当前仓库，但不是可确认的 Vite dev；脚本不会结束该进程。"
  warn_echo "检测到当前仓库的前台/未托管 Vite 服务：PID ${listener_pid}"
  warn_echo "将发送 TERM 并重新后台启动，保证关闭终端后服务仍可用。"
  kill "$listener_pid" 2>/dev/null || die "无法停止现有 Vite 服务：PID ${listener_pid}"

  while [[ "$elapsed" -lt 10 ]]; do
    [[ -z "$(port_listener_pids)" ]] && return 0
    sleep 1
    elapsed=$((elapsed + 1))
  done
  die "现有 Vite 服务在 10 秒内没有释放 3000 端口；脚本不会强制结束进程。"
}
# 判断 3000 端口能否启动；只复用本脚本记录的后台服务。
reuse_existing_server_if_possible() {
  local pids_output="$(port_listener_pids)"
  local owned_pid=""
  local managed_pid=""

  [[ -n "$pids_output" ]] || return 1
  owned_pid="$(listener_belongs_to_repository 2>/dev/null || true)"
  if [[ -n "$owned_pid" ]]; then
    managed_pid="$(read_managed_server_pid 2>/dev/null || true)"
    if [[ "$managed_pid" == "$owned_pid" ]]; then
      process_is_vite_dev_server "$owned_pid" || die "PID 文件对应的监听进程不是 Vite dev，停止复用。"
      info_echo "检测到本脚本托管的后台服务，正在确认可访问性：PID ${owned_pid}"
      wait_for_development_server 15 || die "已托管服务在 15 秒内未就绪。"
      SERVER_REUSED=1
      success_echo "已复用本脚本托管的 3000 端口服务。"
      return 0
    fi
    stop_unmanaged_vite_server "$owned_pid"
    return 1
  fi

  die "3000 端口已被其它目录的进程占用；为避免打开错误页面，脚本已停止。"
}
# 用 nohup、关闭标准输入和 zsh 作业脱离在后台启动 pnpm dev。
launch_development_server_in_background() {
  local dev_pid=""
  : > "$DEV_SERVER_LOG"

  cd "$REPO_ROOT" || die "无法进入项目目录启动服务：${REPO_ROOT}"
  NO_COLOR=1 FORCE_COLOR=0 CLICOLOR=0 ANSI_COLORS_DISABLED=1 npm_config_color=false \
    nohup "$PNPM_BIN" dev --port "$LOCAL_PORT" --strictPort </dev/null >"$DEV_SERVER_LOG" 2>&1 &!
  dev_pid="$!"
  [[ -n "$dev_pid" ]] || die "后台服务启动后未获得进程 ID。"
  print -r -- "$dev_pid" > "$DEV_SERVER_PID_FILE"
  success_echo "已在后台启动 pnpm dev：PID ${dev_pid}"
  gray_echo "关闭当前终端或 Sourcetree 输出窗口不会停止该服务。"
  gray_echo "PID 文件：${DEV_SERVER_PID_FILE}"
  gray_echo "服务日志：${DEV_SERVER_LOG}"
}
# 用真正监听 3000 端口的子进程 PID 更新停止服务所需的 PID 文件。
record_server_listener_pid() {
  local listener_pid="$(listener_belongs_to_repository 2>/dev/null || true)"
  [[ -n "$listener_pid" ]] && process_is_vite_dev_server "$listener_pid" || return 1
  print -r -- "$listener_pid" > "$DEV_SERVER_PID_FILE"
  success_echo "已记录 3000 端口监听进程：PID ${listener_pid}"
}
# 启动或复用开发服务器；Dry-run 不创建进程。
start_or_reuse_development_server() {
  if [[ "${JOBS_MAGIC_RESUME_DRY_RUN:-0}" == "1" ]]; then
    success_echo "Dry-run：计划后台执行 pnpm dev，并等待 ${LOCAL_URL}。"
    return 0
  fi
  reuse_existing_server_if_possible && return 0
  launch_development_server_in_background
  wait_for_development_server 60 || die "开发服务器在 60 秒内未就绪，请查看服务日志：${DEV_SERVER_LOG}"
  record_server_listener_pid || die "端口响应未归属于当前仓库的 Vite dev，停止打开页面；请查看服务日志。"
  success_echo "开发服务器已经就绪：${LOCAL_URL}"
}
# 使用系统默认浏览器打开 localhost；Dry-run 只展示地址。
open_magic_resume_in_browser() {
  if [[ "${JOBS_MAGIC_RESUME_DRY_RUN:-0}" == "1" ]]; then
    success_echo "Dry-run：计划使用默认浏览器打开 ${LOCAL_URL}。"
    return 0
  fi
  open "$LOCAL_URL" || die "无法使用默认浏览器打开 ${LOCAL_URL}。"
  success_echo "已使用默认浏览器打开：${LOCAL_URL}"
}
# 汇总仓库、后台进程和日志位置。
finish_script() {
  highlight_echo "============================== 执行完成 =============================="
  success_echo "magic-resume 仓库：${REPO_ROOT}"
  success_echo "访问地址：${LOCAL_URL}"
  [[ "$SERVER_REUSED" == "1" ]] && gray_echo "服务状态：复用当前仓库已有进程。"
  gray_echo "业务日志：${LOG_FILE}"
  gray_echo "服务日志：${DEV_SERVER_LOG}"
  highlight_echo "======================================================================"
}
# 编排脚本自述、仓库选择、环境配置、依赖安装和后台启动流程。
main() {
  show_script_intro_and_wait # 首先展示内置自述，并按 Sourcetree / 终端入口决定是否等待确认。
  initialize_script_runtime # 确认后初始化 Shell、PATH 和日志，保证后续输出可追踪。
  check_base_environment # 检查 macOS 与 Git、网络、端口、后台运行所需的系统命令。
  resolve_input_repository "$@" # 从 REPO 参数、命令行参数或当前目录识别运行仓库。
  select_magic_resume_repository # 校验当前 remote；不匹配时先扫描全部同级仓库，确实不存在才创建并克隆。
  validate_magic_resume_project # 核对 remote、package.json、锁文件和 dev 入口。
  ensure_node_runtime # 检查 Node.js 与 npm，缺失时由本脚本内的 Homebrew 自检补齐。
  ensure_pnpm_runtime # 检查 pnpm，缺失时按项目声明的版本安装。
  install_project_dependencies # 按官方 README 执行 pnpm install。
  start_or_reuse_development_server # 复用已托管服务，或把当前仓库前台 Vite 转为 nohup 后台服务。
  open_magic_resume_in_browser # 服务就绪后使用系统默认浏览器打开 localhost:3000。
  finish_script # 输出最终仓库、访问地址、PID 和日志位置。
}

main "$@"
