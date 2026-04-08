#!/bin/bash

# =========================
# 基础路径变量
# =========================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"

SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

CURRENT_ACTIONS_PLIST="${SCRIPT_DIR}/actions.plist"
TARGET_SOURCETREE_DIR="${HOME}/Library/Application Support/SourceTree"
TARGET_ACTIONS_PLIST="${TARGET_SOURCETREE_DIR}/actions.plist"

SOURCETREE_APP_NAME="Sourcetree"
SOURCETREE_PROCESS_NAME="Sourcetree"
SOURCETREE_APP_PATH="/Applications/Sourcetree.app"
SOURCETREE_OFFICIAL_URL="https://www.sourcetreeapp.com/"

# 标记本次是否发生了实际复制
DID_SYNC_ACTIONS_PLIST=0

# =========================
# 彩色日志输出函数
# =========================
log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
color_echo()     { log "\033[1;32m$1\033[0m"; }
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
warm_echo()      { log "\033[1;33m$1\033[0m"; }
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
err_echo()       { log "\033[1;31m$1\033[0m"; }
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
gray_echo()      { log "\033[0;90m$1\033[0m"; }
bold_echo()      { log "\033[1m$1\033[0m"; }
underline_echo() { log "\033[4m$1\033[0m"; }

# =========================
# 通用交互与错误处理
# =========================

show_readme_and_wait() {
    bold_echo "=================================================="
    bold_echo "SourceTree 自定义操作 actions.plist 安装脚本"
    bold_echo "=================================================="
    note_echo "脚本路径：${SCRIPT_PATH}"
    note_echo "脚本目录：${SCRIPT_DIR}"
    note_echo "日志文件：${LOG_FILE}"
    gray_echo ""
    highlight_echo "【脚本用途】"
    gray_echo "将当前脚本目录下的 actions.plist"
    gray_echo "复制并覆盖到："
    gray_echo "${TARGET_ACTIONS_PLIST}"
    gray_echo ""
    highlight_echo "【执行前提】"
    gray_echo "1. 当前脚本目录下必须存在 actions.plist"
    gray_echo "2. 当前机器必须已安装 SourceTree，且目录存在："
    gray_echo "   ${TARGET_SOURCETREE_DIR}"
    gray_echo ""
    highlight_echo "【脚本行为】"
    gray_echo "1. 校验当前目录是否存在 actions.plist"
    gray_echo "2. 校验 SourceTree 是否已安装"
    gray_echo "3. 如未安装，则打开官网并循环等待安装完成"
    gray_echo "4. 比较源文件与目标文件内容是否完全一致"
    gray_echo "5. 若不同，则备份旧文件并覆盖复制"
    gray_echo "6. 若发生复制，则自动安全重启 SourceTree"
    gray_echo "7. 执行完成后询问是否打开 SourceTree 配置目录"
    gray_echo ""
    highlight_echo "【注意事项】"
    gray_echo "1. 该操作会覆盖目标 actions.plist"
    gray_echo "2. 若文件内容完全一致，则不会复制，也不会重启 SourceTree"
    gray_echo "3. 若 App 未正常退出，脚本会在超时后尝试强制结束进程"
    gray_echo ""
    warm_echo "请确认以上内容无误。按回车继续，按 Ctrl+C 取消执行。"
    read -r
}

wait_for_enter() {
    local prompt_text="${1:-请按回车继续...}"
    warm_echo "${prompt_text}"
    read -r
}

exit_with_error() {
    error_echo "$1"
    exit 1
}

# =========================
# 条件检查模块
# =========================

check_local_actions_plist() {
    info_echo "检查当前脚本目录下是否存在 actions.plist ..."

    if [[ ! -f "${CURRENT_ACTIONS_PLIST}" ]]; then
        exit_with_error "当前目录下不存在actions.plist，请检查后再执行"
    fi

    success_echo "检测通过：当前目录下存在 actions.plist"
    gray_echo "文件路径：${CURRENT_ACTIONS_PLIST}"
}

is_sourcetree_installed() {
    [[ -d "${TARGET_SOURCETREE_DIR}" ]]
}

ensure_sourcetree_installed() {
    info_echo "检查当前机器是否已安装 SourceTree ..."

    if is_sourcetree_installed; then
        success_echo "检测通过：已安装 SourceTree"
        gray_echo "目标目录存在：${TARGET_SOURCETREE_DIR}"
        return 0
    fi

    warn_echo "当前未安装SourceTree，是否前往安装？"
    gray_echo "回车：前往官网安装"
    gray_echo "Ctrl+C：终止脚本"
    read -r

    info_echo "正在打开 SourceTree 官网 ..."
    open "${SOURCETREE_OFFICIAL_URL}" || warn_echo "打开官网失败，请手动访问：${SOURCETREE_OFFICIAL_URL}"

    while true; do
        gray_echo ""
        warn_echo "尚未检测到 SourceTree 安装目录：${TARGET_SOURCETREE_DIR}"
        gray_echo "请先完成 SourceTree 安装。"
        gray_echo "安装完成后，回到此窗口按回车继续检测。"
        gray_echo "若还未安装完成，也可继续回车重试。"
        read -r

        if is_sourcetree_installed; then
            success_echo "检测通过：已安装 SourceTree"
            gray_echo "目标目录存在：${TARGET_SOURCETREE_DIR}"
            break
        fi
    done
}

# =========================
# 文件同步模块
# =========================

is_actions_plist_same() {
    if [[ ! -f "${CURRENT_ACTIONS_PLIST}" || ! -f "${TARGET_ACTIONS_PLIST}" ]]; then
        return 1
    fi

    cmp -s "${CURRENT_ACTIONS_PLIST}" "${TARGET_ACTIONS_PLIST}"
}

sync_actions_plist() {
    info_echo "开始检查源 actions.plist 与目标 actions.plist 是否一致 ..."

    if [[ ! -f "${TARGET_ACTIONS_PLIST}" ]]; then
        warn_echo "目标 actions.plist 不存在，将直接复制"

        cp -f "${CURRENT_ACTIONS_PLIST}" "${TARGET_ACTIONS_PLIST}" || exit_with_error "复制 actions.plist 失败，请检查权限"

        DID_SYNC_ACTIONS_PLIST=1
        success_echo "复制成功，已写入新的 actions.plist"
        gray_echo "源文件：${CURRENT_ACTIONS_PLIST}"
        gray_echo "目标文件：${TARGET_ACTIONS_PLIST}"
        return 0
    fi

    if is_actions_plist_same; then
        success_echo "源文件和目标文件内容完全一致，无需复制"
        gray_echo "已跳过备份、复制和重启操作"
        DID_SYNC_ACTIONS_PLIST=0
        return 1
    fi

    warn_echo "检测到源文件和目标文件内容不一致，准备备份并覆盖"

    local backup_file="${TARGET_ACTIONS_PLIST}.bak.$(date '+%Y%m%d_%H%M%S')"
    cp -f "${TARGET_ACTIONS_PLIST}" "${backup_file}" || exit_with_error "备份旧的 actions.plist 失败，请检查权限"
    success_echo "备份完成：${backup_file}"

    cp -f "${CURRENT_ACTIONS_PLIST}" "${TARGET_ACTIONS_PLIST}" || exit_with_error "复制 actions.plist 失败，请检查权限"

    DID_SYNC_ACTIONS_PLIST=1
    success_echo "复制成功，已完成替换"
    gray_echo "源文件：${CURRENT_ACTIONS_PLIST}"
    gray_echo "目标文件：${TARGET_ACTIONS_PLIST}"

    return 0
}

# =========================
# 通用 App 管理模块
# =========================

is_app_running() {
    local process_name="$1"
    pgrep -x "${process_name}" >/dev/null 2>&1
}

quit_app_gracefully() {
    local app_name="$1"
    osascript -e "tell application \"${app_name}\" to quit" >/dev/null 2>&1 || true
}

force_kill_app() {
    local process_name="$1"
    pkill -x "${process_name}" >/dev/null 2>&1 || true
}

wait_for_app_exit() {
    local process_name="$1"
    local timeout_seconds="${2:-15}"
    local elapsed=0

    while is_app_running "${process_name}"; do
        ((elapsed++))
        gray_echo "等待 ${process_name} 完全退出 ... ${elapsed}s/${timeout_seconds}s"
        sleep 1

        if [[ ${elapsed} -ge ${timeout_seconds} ]]; then
            return 1
        fi
    done

    return 0
}

launch_app() {
    local app_name="$1"
    local app_path="$2"

    info_echo "正在启动 ${app_name} ..."
    sleep 1

    if [[ -n "${app_path}" && -d "${app_path}" ]]; then
        open -a "${app_path}" || exit_with_error "启动 ${app_name} 失败，请手动打开"
    else
        open -a "${app_name}" || exit_with_error "启动 ${app_name} 失败，请手动打开"
    fi

    success_echo "${app_name} 已重新启动"
}

restart_app() {
    local app_name="$1"
    local process_name="$2"
    local app_path="$3"
    local timeout_seconds="${4:-15}"

    [[ -z "${app_name}" ]] && exit_with_error "restart_app 缺少参数：app_name"
    [[ -z "${process_name}" ]] && process_name="${app_name}"

    info_echo "准备重启 ${app_name} ..."

    if is_app_running "${process_name}"; then
        note_echo "检测到 ${app_name} 正在运行，准备优雅退出 ..."
        quit_app_gracefully "${app_name}"

        if wait_for_app_exit "${process_name}" "${timeout_seconds}"; then
            success_echo "${app_name} 已正常退出"
        else
            warn_echo "${app_name} 长时间未退出，尝试强制结束进程 ..."
            force_kill_app "${process_name}"
            sleep 2

            if is_app_running "${process_name}"; then
                exit_with_error "${app_name} 强制退出失败，请手动关闭后再试"
            fi

            success_echo "${app_name} 已被强制结束"
        fi
    else
        warn_echo "当前未检测到 ${app_name} 运行中，将直接启动"
    fi

    launch_app "${app_name}" "${app_path}"
}

restart_sourcetree() {
    restart_app "${SOURCETREE_APP_NAME}" "${SOURCETREE_PROCESS_NAME}" "${SOURCETREE_APP_PATH}" 15
}

# =========================
# 收尾模块
# =========================

print_finish_message() {
    gray_echo ""
    bold_echo "=================================================="
    success_echo "执行完成"
    bold_echo "=================================================="

    if [[ "${DID_SYNC_ACTIONS_PLIST}" -eq 1 ]]; then
        note_echo "actions.plist 已完成替换，并已自动重启 SourceTree。"
    else
        note_echo "actions.plist 与目标文件完全一致，未执行复制，未重启 SourceTree。"
    fi

    gray_echo "日志文件：${LOG_FILE}"
}

prompt_open_sourcetree_config_dir() {
    gray_echo ""
    highlight_echo "是否打开 SourceTree 配置目录？"
    gray_echo "目录路径：${TARGET_SOURCETREE_DIR}"
    gray_echo "回车：立即打开"
    gray_echo "输入任意内容后回车：跳过"
    printf "> "
    read -r user_input

    if [[ -z "${user_input}" ]]; then
        info_echo "正在打开目录：${TARGET_SOURCETREE_DIR}"
        open "${TARGET_SOURCETREE_DIR}" || warn_echo "打开目录失败，请手动打开：${TARGET_SOURCETREE_DIR}"
    else
        gray_echo "已跳过打开目录"
    fi
}

# =========================
# 主函数
# 统一收口所有执行流程：
# 1. 显示说明并等待用户确认
# 2. 校验本地 actions.plist 是否存在
# 3. 校验 SourceTree 是否已安装；未安装则引导安装并循环等待
# 4. 比较源文件与目标文件是否一致
# 5. 仅在需要时备份并覆盖复制
# 6. 仅在发生复制时安全重启 SourceTree
# 7. 输出执行结果
# 8. 询问是否打开 SourceTree 配置目录
# =========================
main() {
    show_readme_and_wait
    check_local_actions_plist
    ensure_sourcetree_installed

    if sync_actions_plist; then
        restart_sourcetree
    fi

    print_finish_message
    prompt_open_sourcetree_config_dir
}

main "$@"
