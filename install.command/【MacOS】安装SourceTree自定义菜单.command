#!/bin/zsh

# =========================
# 基础路径变量
# =========================
SCRIPT_PATH="${0:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"
SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
INSTALL_DIR_NAME="${SCRIPT_DIR:t}"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
: > "$LOG_FILE"

SOURCE_PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
SOURCE_ACTIONS_PLIST="${SCRIPT_DIR}/actions.plist"

# SourceTree 执行自定义菜单时必须使用稳定路径，不能指向临时解压目录或当前代码目录。
# 在 Jobs 的电脑上，${HOME} 即 /Users/jobs，因此最终部署目录为：/Users/jobs/SourceTree.sh
DEPLOY_PARENT_DIR="${HOME}"
DEPLOY_PROJECT_ROOT="${DEPLOY_PARENT_DIR}/SourceTree.sh"
DEPLOY_INSTALL_DIR="${DEPLOY_PROJECT_ROOT}/${INSTALL_DIR_NAME}"
DEPLOY_ACTIONS_PLIST_TEMPLATE="${DEPLOY_INSTALL_DIR}/actions.plist"

RUNTIME_DIR=""
RUNTIME_ACTIONS_PLIST=""
ACTIVE_ACTIONS_PLIST=""

TARGET_SOURCETREE_DIR="${HOME}/Library/Application Support/SourceTree"
TARGET_ACTIONS_PLIST="${TARGET_SOURCETREE_DIR}/actions.plist"

SOURCETREE_APP_NAME="Sourcetree"
SOURCETREE_PROCESS_NAME="Sourcetree"
SOURCETREE_OFFICIAL_URL="https://www.sourcetreeapp.com/"

DID_SYNC_SCRIPT_PACKAGE=0
DID_SYNC_ACTIONS_PLIST=0
PATCHED_ACTION_TARGET_COUNT=0

# =========================
# 彩色日志输出函数
# =========================
log()            { printf "%b\n" "$1" | tee -a "$LOG_FILE"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log "\033[1;32m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log "\033[1;33m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err_echo()       { log "\033[1;31m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
underline_echo() { log "\033[4m$1\033[0m"; }

# =========================
# 通用交互与错误处理
# =========================
cleanup_runtime_dir() {
    if [[ -n "${RUNTIME_DIR:-}" && -d "$RUNTIME_DIR" ]]; then
        rm -rf -- "$RUNTIME_DIR"
    fi
}
trap cleanup_runtime_dir EXIT

# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_readme_and_wait() {
  if [[ "${IS_SOURCETREE_RUNTIME:-0}" != "1" && -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" ]]; then
    clear
  fi

  highlight_echo "============================== 脚本内置自述 =============================="
  note_echo "脚本名称：${SCRIPT_BASENAME}.command"
  note_echo "脚本路径：${SCRIPT_PATH}"
  note_echo "运行入口：兼容系统终端双击运行和 Sourcetree 自定义动作运行。"
  note_echo "核心行为：按脚本名称执行对应的 SourceTree 效率动作，运行前会先展示这段内置自述，避免误触。"
  note_echo "环境策略：系统终端保留清屏、彩色输出和回车确认；Sourcetree 瘦身环境自动跳过清屏和等待，并输出纯文本日志。"
  note_echo "文档关系：同目录 README.md 只作为外部说明文档保留，运行时自述不读取、不拼接、不依赖 README.md。"
  warn_echo "继续前请确认 SourceTree 传入路径、当前仓库或拖入路径正确；按 Ctrl+C 可以取消。"
  gray_echo "日志文件：${LOG_FILE}"
  highlight_echo "======================================================================="
  echo ""

  if [[ "${IS_SOURCETREE_RUNTIME:-0}" != "1" && -t 0 ]]; then
    read "?👉 已阅读脚本内置自述，按回车继续执行；按 Ctrl+C 取消..."
  else
    gray_echo "当前为 Sourcetree 或非交互输入环境，已跳过回车等待。"
  fi
}

# 封装 wait_for_enter 对应的独立处理逻辑。
wait_for_enter() {
    local prompt_text="${1:-请按回车继续...}"
    warm_echo "${prompt_text}"
    read -r
}

# 封装 exit_with_error 对应的独立处理逻辑。
exit_with_error() {
    error_echo "$1"
    exit 1
}

# 检查当前运行条件是否满足后续流程要求。
ensure_not_root_home() {
    if [[ "${HOME}" == "/var/root" || "${EUID}" -eq 0 ]]; then
        exit_with_error "请不要使用 sudo/root 执行本脚本。当前 HOME=${HOME}，会导致脚本部署到错误位置。"
    fi
}

# =========================
# 条件检查模块
# =========================
check_local_actions_plist() {
    info_echo "检查当前包内 ${INSTALL_DIR_NAME}/actions.plist 模板是否存在 ..."

    if [[ ! -f "${SOURCE_ACTIONS_PLIST}" ]]; then
        exit_with_error "未找到 actions.plist 模板：${SOURCE_ACTIONS_PLIST}"
    fi

    success_echo "检测通过：actions.plist 模板存在"
    gray_echo "模板路径：${SOURCE_ACTIONS_PLIST}"
}

# 检查当前运行条件是否满足后续流程要求。
check_command_structure_in_dir() {
    local base_dir="$1"
    local scene_name="$2"

    info_echo "检查 ${scene_name} 的 .command 独立文件夹结构 ..."

    local command_dir_count=0
    local invalid_count=0
    local missing_readme_count=0
    local command_dir=""
    local command_name=""
    local command_file=""
    local readme_file=""

    local skipped_installer_count=0

    for command_dir in "${base_dir}"/*.command(N/); do
        command_name="${command_dir:t}"

        # install.command 是安装器目录，里面放 actions.plist 和本安装脚本。
        # 它不是 SourceTree 菜单业务脚本目录，所以不能按“同名 .command + README.md”的业务格式校验。
        if [[ "${command_name}" == "${INSTALL_DIR_NAME}" ]]; then
            skipped_installer_count=$((skipped_installer_count + 1))
            gray_echo "跳过安装器目录：${command_dir}"
            continue
        fi

        command_dir_count=$((command_dir_count + 1))
        command_file="${command_dir}/${command_name}"
        readme_file="${command_dir}/README.md"

        if [[ ! -f "${command_file}" ]]; then
            invalid_count=$((invalid_count + 1))
            error_echo "缺少同名脚本：${command_file}"
        fi

        if [[ ! -f "${readme_file}" ]]; then
            missing_readme_count=$((missing_readme_count + 1))
            warn_echo "缺少 README.md：${readme_file}"
        fi
    done

    if [[ "${command_dir_count}" -eq 0 ]]; then
        exit_with_error "${scene_name} 未发现任何业务 .command 独立文件夹：${base_dir}"
    fi

    if [[ "${invalid_count}" -gt 0 ]]; then
        exit_with_error "${scene_name} 存在 ${invalid_count} 个无效 .command 文件夹，请先修复。"
    fi

    if [[ "${missing_readme_count}" -gt 0 ]]; then
        warn_echo "${scene_name} 有 ${missing_readme_count} 个脚本文件夹缺少 README.md，本次仍继续安装。"
    fi

    success_echo "检测通过：${scene_name} 发现 ${command_dir_count} 个有效业务 .command 独立文件夹"
    [[ "${skipped_installer_count}" -gt 0 ]] && gray_echo "已跳过安装器目录数：${skipped_installer_count}"
}

# 检查当前运行条件是否满足后续流程要求。
check_source_command_structure() {
    check_command_structure_in_dir "${SOURCE_PROJECT_ROOT}" "源项目目录"
}

# 解析并返回后续流程需要的目标信息。
find_python3() {
    local python_bin=""

    for candidate in "/usr/bin/python3" "python3"; do
        if command -v "$candidate" >/dev/null 2>&1; then
            python_bin="$(command -v "$candidate")"
            printf "%s" "$python_bin"
            return 0
        fi
    done

    if command -v xcrun >/dev/null 2>&1; then
        python_bin="$(xcrun -find python3 2>/dev/null || true)"
        if [[ -n "$python_bin" && -x "$python_bin" ]]; then
            printf "%s" "$python_bin"
            return 0
        fi
    fi

    return 1
}

# 解析并返回后续流程需要的目标信息。
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

# 检查当前运行条件是否满足后续流程要求。
is_sourcetree_installed() {
    detect_sourcetree_app_path >/dev/null 2>&1 || [[ -d "${TARGET_SOURCETREE_DIR}" ]]
}

# 检查当前运行条件是否满足后续流程要求。
ensure_sourcetree_installed() {
    info_echo "检查当前机器是否已安装 SourceTree ..."

    if is_sourcetree_installed; then
        success_echo "检测通过：已检测到 SourceTree 或其配置目录"
        local detected_app_path="$(detect_sourcetree_app_path 2>/dev/null || true)"
        [[ -n "$detected_app_path" ]] && gray_echo "App 路径：${detected_app_path}"
        [[ -d "${TARGET_SOURCETREE_DIR}" ]] && gray_echo "配置目录：${TARGET_SOURCETREE_DIR}"
    else
        warn_echo "当前未检测到 SourceTree，是否前往安装？"
        gray_echo "回车：前往官网安装"
        gray_echo "Ctrl+C：终止脚本"
        read -r

        info_echo "正在打开 SourceTree 官网 ..."
        open "${SOURCETREE_OFFICIAL_URL}" || warn_echo "打开官网失败，请手动访问：${SOURCETREE_OFFICIAL_URL}"

        while true; do
            gray_echo ""
            warn_echo "尚未检测到 SourceTree 或其配置目录。"
            gray_echo "请先完成 SourceTree 安装。"
            gray_echo "安装完成后，回到此窗口按回车继续检测。"
            gray_echo "若还未安装完成，也可继续回车重试。"
            read -r

            if is_sourcetree_installed; then
                success_echo "检测通过：已检测到 SourceTree"
                break
            fi
        done
    fi

    mkdir -p "${TARGET_SOURCETREE_DIR}" || exit_with_error "创建 SourceTree 配置目录失败：${TARGET_SOURCETREE_DIR}"
    success_echo "SourceTree 配置目录已就绪"
    gray_echo "配置目录：${TARGET_SOURCETREE_DIR}"
}

# =========================
# 脚本包部署模块
# =========================
copy_directory_content() {
    local source_dir="$1"
    local target_dir="$2"

    mkdir -p "${target_dir}" || exit_with_error "创建目录失败：${target_dir}"

    if command -v ditto >/dev/null 2>&1; then
        ditto "${source_dir}" "${target_dir}" || return 1
        return 0
    fi

    if command -v rsync >/dev/null 2>&1; then
        rsync -a "${source_dir}/" "${target_dir}/" || return 1
        return 0
    fi

    rm -rf -- "${target_dir}" || return 1
    cp -R "${source_dir}" "${target_dir}" || return 1
}

# 执行对应的环境配置或同步处理。
sync_script_package_to_home() {
    info_echo "开始把脚本包部署到固定目录 ..."
    gray_echo "源目录：${SOURCE_PROJECT_ROOT}"
    gray_echo "目标目录：${DEPLOY_PROJECT_ROOT}"

    local source_real="$(cd "${SOURCE_PROJECT_ROOT}" && pwd -P)"
    local target_real=""
    if [[ -d "${DEPLOY_PROJECT_ROOT}" ]]; then
        target_real="$(cd "${DEPLOY_PROJECT_ROOT}" && pwd -P)"
    fi

    if [[ -n "${target_real}" && "${source_real}" == "${target_real}" ]]; then
        success_echo "当前脚本包已经位于固定部署目录，无需复制脚本包"
        DID_SYNC_SCRIPT_PACKAGE=0
    else
        mkdir -p "${DEPLOY_PROJECT_ROOT}" || exit_with_error "创建固定部署目录失败：${DEPLOY_PROJECT_ROOT}"

        local item=""
        local item_name=""
        local copied_command_dir_count=0

        for item in "${SOURCE_PROJECT_ROOT}"/*.command(N/); do
            item_name="${item:t}"

            # 安装器目录单独复制，避免被当成业务脚本统计。
            if [[ "${item_name}" == "${INSTALL_DIR_NAME}" ]]; then
                continue
            fi

            copy_directory_content "${item}" "${DEPLOY_PROJECT_ROOT}/${item_name}" || exit_with_error "复制脚本文件夹失败：${item}"
            copied_command_dir_count=$((copied_command_dir_count + 1))
        done

        if [[ -d "${SCRIPT_DIR}" ]]; then
            copy_directory_content "${SCRIPT_DIR}" "${DEPLOY_INSTALL_DIR}" || exit_with_error "复制 ${INSTALL_DIR_NAME} 目录失败"
        fi

        if [[ -d "${SOURCE_PROJECT_ROOT}/assets" ]]; then
            copy_directory_content "${SOURCE_PROJECT_ROOT}/assets" "${DEPLOY_PROJECT_ROOT}/assets" || exit_with_error "复制 assets 目录失败"
        fi

        for item in "${SOURCE_PROJECT_ROOT}"/*; do
            if [[ -f "${item}" ]]; then
                cp -f "${item}" "${DEPLOY_PROJECT_ROOT}/" || exit_with_error "复制根目录文件失败：${item}"
            fi
        done

        DID_SYNC_SCRIPT_PACKAGE=1
        success_echo "脚本包已部署到固定目录"
        gray_echo "已复制脚本文件夹数：${copied_command_dir_count}"
    fi

    if [[ ! -f "${DEPLOY_ACTIONS_PLIST_TEMPLATE}" ]]; then
        exit_with_error "部署目录中缺少 actions.plist 模板：${DEPLOY_ACTIONS_PLIST_TEMPLATE}"
    fi

    check_command_structure_in_dir "${DEPLOY_PROJECT_ROOT}" "固定部署目录"
}

# =========================
# actions.plist 生成与校验模块
# =========================
generate_runtime_actions_plist() {
    info_echo "基于固定部署目录生成运行时 actions.plist ..."

    local python_bin=""
    python_bin="$(find_python3 || true)"
    if [[ -z "$python_bin" ]]; then
        exit_with_error "未找到 python3，无法安全改写 NSKeyedArchiver 格式的 actions.plist。请先安装 Xcode Command Line Tools 或 Homebrew Python。"
    fi

    RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.XXXXXX")" || exit_with_error "创建临时目录失败"
    RUNTIME_ACTIONS_PLIST="${RUNTIME_DIR}/actions.plist"

    local output=""
    if ! output="$(DEPLOY_PROJECT_ROOT="${DEPLOY_PROJECT_ROOT}" DEPLOY_ACTIONS_PLIST_TEMPLATE="${DEPLOY_ACTIONS_PLIST_TEMPLATE}" RUNTIME_ACTIONS_PLIST="${RUNTIME_ACTIONS_PLIST}" "$python_bin" <<'PY'
import os
import plistlib
import stat
from pathlib import Path

deploy_project_root = Path(os.environ["DEPLOY_PROJECT_ROOT"]).resolve()
deploy_actions_plist_template = Path(os.environ["DEPLOY_ACTIONS_PLIST_TEMPLATE"]).resolve()
runtime_actions_plist = Path(os.environ["RUNTIME_ACTIONS_PLIST"]).resolve()

command_map = {}
for child in sorted(deploy_project_root.iterdir(), key=lambda item: item.name):
    if not child.is_dir():
        continue
    if not child.name.endswith(".command"):
        continue

    command_file = child / child.name
    if command_file.is_file():
        command_map[child.name] = str(command_file)

if not command_map:
    raise SystemExit(f"未发现有效的 .command/同名.command 文件结构：{deploy_project_root}")

with deploy_actions_plist_template.open("rb") as file_obj:
    plist_object = plistlib.load(file_obj)

patched_items = []
missing_names = set()

def patch_value(value):
    if isinstance(value, str):
        if value.endswith(".command") and "/" in value:
            command_name = Path(value).name
            if command_name in command_map:
                new_value = command_map[command_name]
                if value != new_value:
                    patched_items.append((value, new_value))
                return new_value
            missing_names.add(command_name)
        return value

    if isinstance(value, list):
        return [patch_value(item) for item in value]

    if isinstance(value, tuple):
        return tuple(patch_value(item) for item in value)

    if isinstance(value, dict):
        # 封装 return 对应的独立处理逻辑。
        return {patch_value(key): patch_value(item) for key, item in value.items()}

    return value

patched_plist_object = patch_value(plist_object)

if missing_names:
    missing_text = "\n".join(f"- {name}" for name in sorted(missing_names))
    raise SystemExit(
        "actions.plist 引用了固定部署目录中不存在的脚本，请先补齐脚本文件：\n"
        f"{missing_text}"
    )

referenced_targets = set()

def collect_command_targets(value):
    if isinstance(value, str):
        if value.endswith(".command") and "/" in value:
            referenced_targets.add(value)
        return

    if isinstance(value, (list, tuple)):
        for item in value:
            collect_command_targets(item)
        return

    if isinstance(value, dict):
        for key, item in value.items():
            collect_command_targets(key)
            collect_command_targets(item)

collect_command_targets(patched_plist_object)

if not referenced_targets:
    raise SystemExit("actions.plist 中未发现任何 SourceTree 自定义菜单脚本路径。")

invalid_prefix_paths = [path for path in sorted(referenced_targets) if not str(path).startswith(str(deploy_project_root) + "/")]
if invalid_prefix_paths:
    invalid_text = "\n".join(f"- {path}" for path in invalid_prefix_paths)
    raise SystemExit(
        "生成后的 actions.plist 仍存在非固定部署目录路径：\n"
        f"{invalid_text}"
    )

missing_target_paths = [path for path in sorted(referenced_targets) if not Path(path).is_file()]
if missing_target_paths:
    missing_text = "\n".join(f"- {path}" for path in missing_target_paths)
    raise SystemExit(
        "生成后的 actions.plist 仍然存在无效脚本路径：\n"
        f"{missing_text}"
    )

not_executable_paths = []
for target_path in sorted(referenced_targets):
    path_obj = Path(target_path)
    try:
        mode = path_obj.stat().st_mode
        if not (mode & stat.S_IXUSR):
            path_obj.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
            not_executable_paths.append(target_path)
    except OSError as error:
        raise SystemExit(f"设置执行权限失败：{target_path}\n{error}") from error

runtime_actions_plist.parent.mkdir(parents=True, exist_ok=True)
with runtime_actions_plist.open("wb") as file_obj:
    plistlib.dump(patched_plist_object, file_obj, fmt=plistlib.FMT_BINARY, sort_keys=False)

print(f"菜单引用脚本数：{len(referenced_targets)}")
print(f"已重写路径数：{len(patched_items)}")
print(f"已补齐执行权限数：{len(not_executable_paths)}")
print(f"固定部署目录：{deploy_project_root}")
print(f"运行时 actions.plist：{runtime_actions_plist}")
PY
)"; then
        exit_with_error "生成运行时 actions.plist 失败：\n${output}"
    fi

    while IFS= read -r line; do
        [[ -n "$line" ]] && gray_echo "$line"
        if [[ "$line" == 菜单引用脚本数：* ]]; then
            PATCHED_ACTION_TARGET_COUNT="${line#菜单引用脚本数：}"
        fi
    done <<< "$output"

    if [[ ! -f "${RUNTIME_ACTIONS_PLIST}" ]]; then
        exit_with_error "运行时 actions.plist 生成后不存在：${RUNTIME_ACTIONS_PLIST}"
    fi

    ACTIVE_ACTIONS_PLIST="${RUNTIME_ACTIONS_PLIST}"
    success_echo "运行时 actions.plist 生成完成"
}

# =========================
# 文件同步模块
# =========================
is_actions_plist_same() {
    if [[ ! -f "${ACTIVE_ACTIONS_PLIST}" || ! -f "${TARGET_ACTIONS_PLIST}" ]]; then
        return 1
    fi

    cmp -s "${ACTIVE_ACTIONS_PLIST}" "${TARGET_ACTIONS_PLIST}"
}

# 执行对应的环境配置或同步处理。
sync_actions_plist() {
    [[ -z "${ACTIVE_ACTIONS_PLIST}" ]] && exit_with_error "缺少运行时 actions.plist，请先生成后再同步"

    info_echo "开始检查运行时 actions.plist 与目标 actions.plist 是否一致 ..."

    if [[ ! -f "${TARGET_ACTIONS_PLIST}" ]]; then
        warn_echo "目标 actions.plist 不存在，将直接复制"

        cp -f "${ACTIVE_ACTIONS_PLIST}" "${TARGET_ACTIONS_PLIST}" || exit_with_error "复制 actions.plist 失败，请检查权限"

        DID_SYNC_ACTIONS_PLIST=1
        success_echo "复制成功，已写入新的 actions.plist"
        gray_echo "源文件：${ACTIVE_ACTIONS_PLIST}"
        gray_echo "目标文件：${TARGET_ACTIONS_PLIST}"
        return 0
    fi

    if is_actions_plist_same; then
        success_echo "运行时文件和目标文件内容完全一致，无需复制"
        gray_echo "已跳过备份、复制和重启操作"
        DID_SYNC_ACTIONS_PLIST=0
        return 1
    fi

    warn_echo "检测到运行时文件和目标文件内容不一致，准备备份并覆盖"

    local backup_file="${TARGET_ACTIONS_PLIST}.bak.$(date '+%Y%m%d_%H%M%S')"
    cp -f "${TARGET_ACTIONS_PLIST}" "${backup_file}" || exit_with_error "备份旧的 actions.plist 失败，请检查权限"
    success_echo "备份完成：${backup_file}"

    cp -f "${ACTIVE_ACTIONS_PLIST}" "${TARGET_ACTIONS_PLIST}" || exit_with_error "复制 actions.plist 失败，请检查权限"

    DID_SYNC_ACTIONS_PLIST=1
    success_echo "复制成功，已完成替换"
    gray_echo "源文件：${ACTIVE_ACTIONS_PLIST}"
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

# 封装 quit_app_gracefully 对应的独立处理逻辑。
quit_app_gracefully() {
    local app_name="$1"
    osascript -e "tell application \"${app_name}\" to quit" >/dev/null 2>&1 || true
}

# 封装 force_kill_app 对应的独立处理逻辑。
force_kill_app() {
    local process_name="$1"
    pkill -x "${process_name}" >/dev/null 2>&1 || true
}

# 封装 wait_for_app_exit 对应的独立处理逻辑。
wait_for_app_exit() {
    local process_name="$1"
    local timeout_seconds="${2:-15}"
    local elapsed=0

    while is_app_running "${process_name}"; do
        elapsed=$((elapsed + 1))
        gray_echo "等待 ${process_name} 完全退出 ... ${elapsed}s/${timeout_seconds}s"
        sleep 1

        if [[ ${elapsed} -ge ${timeout_seconds} ]]; then
            return 1
        fi
    done

    return 0
}

# 封装 launch_app 对应的独立处理逻辑。
launch_app() {
    local app_name="$1"
    local app_path="$2"

    info_echo "正在启动 ${app_name} ..."
    sleep 1

    if [[ -n "${app_path}" && -d "${app_path}" ]]; then
        open "${app_path}" || exit_with_error "启动 ${app_name} 失败，请手动打开"
    else
        open -a "${app_name}" || exit_with_error "启动 ${app_name} 失败，请手动打开"
    fi

    success_echo "${app_name} 已重新启动"
}

# 封装 restart_app 对应的独立处理逻辑。
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

# 封装 restart_sourcetree 对应的独立处理逻辑。
restart_sourcetree() {
    local app_path="$(detect_sourcetree_app_path 2>/dev/null || true)"
    restart_app "${SOURCETREE_APP_NAME}" "${SOURCETREE_PROCESS_NAME}" "${app_path}" 15
}

# =========================
# 收尾模块
# =========================
print_finish_message() {
    gray_echo ""
    bold_echo "=================================================="
    success_echo "执行完成"
    bold_echo "=================================================="

    if [[ "${DID_SYNC_SCRIPT_PACKAGE}" -eq 1 ]]; then
        note_echo "脚本包已复制/覆盖部署到固定目录。"
    else
        note_echo "脚本包已在固定部署目录，无需复制脚本包。"
    fi

    if [[ "${DID_SYNC_ACTIONS_PLIST}" -eq 1 ]]; then
        note_echo "actions.plist 已完成替换，并已自动重启 SourceTree。"
    else
        note_echo "actions.plist 与目标文件完全一致，未执行复制，未重启 SourceTree。"
    fi

    gray_echo "菜单引用脚本数：${PATCHED_ACTION_TARGET_COUNT}"
    gray_echo "固定部署目录：${DEPLOY_PROJECT_ROOT}"
    gray_echo "目标文件：${TARGET_ACTIONS_PLIST}"
    gray_echo "日志文件：${LOG_FILE}"
}

# 收集并校验用户输入，决定后续执行路径。
prompt_open_result_dirs() {
    gray_echo ""
    highlight_echo "是否打开固定部署目录？"
    gray_echo "目录路径：${DEPLOY_PROJECT_ROOT}"
    gray_echo "回车：立即打开"
    gray_echo "输入任意内容后回车：跳过"
    printf "> "
    local user_input=""
    read -r user_input

    if [[ -z "${user_input}" ]]; then
        info_echo "正在打开目录：${DEPLOY_PROJECT_ROOT}"
        open "${DEPLOY_PROJECT_ROOT}" || warn_echo "打开目录失败，请手动打开：${DEPLOY_PROJECT_ROOT}"
    else
        gray_echo "已跳过打开固定部署目录"
    fi

    gray_echo ""
    highlight_echo "是否打开 SourceTree 配置目录？"
    gray_echo "目录路径：${TARGET_SOURCETREE_DIR}"
    gray_echo "回车：立即打开"
    gray_echo "输入任意内容后回车：跳过"
    printf "> "
    user_input=""
    read -r user_input

    if [[ -z "${user_input}" ]]; then
        info_echo "正在打开目录：${TARGET_SOURCETREE_DIR}"
        open "${TARGET_SOURCETREE_DIR}" || warn_echo "打开目录失败，请手动打开：${TARGET_SOURCETREE_DIR}"
    else
        gray_echo "已跳过打开 SourceTree 配置目录"
    fi
}

# =========================
# 主函数
# 统一收口所有执行流程：
# 1. 显示说明并等待用户确认
# 2. 禁止 sudo/root 误执行
# 3. 校验源 actions.plist 模板是否存在
# 4. 校验源脚本包是否为业务 .command 独立文件夹结构，并跳过 install.command 安装器目录
# 5. 把脚本包部署到 ${HOME}/SourceTree.sh，也就是 Jobs 机器上的 /Users/jobs/SourceTree.sh
# 6. 校验 SourceTree 是否已安装；未安装则引导安装并循环等待
# 7. 基于固定部署目录生成运行时 actions.plist
# 8. 比较运行时文件与 SourceTree 目标文件是否一致
# 9. 仅在需要时备份并覆盖复制
# 10. 仅在发生复制时安全重启 SourceTree
# 11. 输出执行结果并询问是否打开相关目录
# =========================
run_main_flow() {
    show_readme_and_wait
    ensure_not_root_home
    check_local_actions_plist
    check_source_command_structure
    sync_script_package_to_home
    ensure_sourcetree_installed
    generate_runtime_actions_plist

    if sync_actions_plist; then
        restart_sourcetree
    fi

    print_finish_message
    prompt_open_result_dirs
}

# 统一收口脚本入口，仅委托已经拆分完成的业务流程。
main() {
  # 主入口只负责委托完整业务流程，复杂逻辑统一下沉。
  run_main_flow "$@"
}

main "$@"
