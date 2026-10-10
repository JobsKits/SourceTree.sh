#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS@SourceTree】♻️双击Git（识别子Git） 提交回退.command
# - 核心用途：Sourcetree soft 撤回未推送提交；终端支持 upstream、提交、tag 和 reflog 回退。
# - 影响范围：soft 保留工作区并更新暂存区；hard 舍弃已跟踪改动，但不递归重置子模块。
# - 运行提示：终端参数模式仍先回车确认；hard 必须输入 YES，Sourcetree 只执行 soft。
# shell: zsh

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
RAW_SCRIPT_PATH="$0"
SCRIPT_PATH=""
SCRIPT_BASENAME=""
LOG_FILE=""
LOG_READY=0
IS_SOURCETREE_RUNTIME=0
PLAIN_OUTPUT=0
REPO_ROOT=""
UPSTREAM_REF=""
RESET_TARGET=""
RESET_MODE=""
SELECTION=""

# 仅以 Sourcetree 环境标记或父进程确认入口，不把命令行参数当作身份。
is_sourcetree_runtime() {
  /usr/bin/env | /usr/bin/grep -Ei '^SOURCETREE|^SOURCE_TREE' >/dev/null && return 0
  local process_id="$PPID" process_name="" guard=0
  while [[ -n "$process_id" && "$process_id" != 0 && "$guard" -lt 8 ]]; do
    process_name="$(/bin/ps -o comm= -p "$process_id" 2>/dev/null || true)"
    [[ "$process_name" == *SourceTree* || "$process_name" == *Sourcetree* ]] && return 0
    process_id="$(/bin/ps -o ppid= -p "$process_id" 2>/dev/null | /usr/bin/tr -d ' ' || true)"
    guard=$((guard + 1))
  done
  return 1
}
# 准备路径与纯文本输出，首屏不创建日志或改动 Git。
prepare_intro_context() {
  local filename="${RAW_SCRIPT_PATH:t}" candidate="${RAW_SCRIPT_PATH:A}"
  local fallback=""
  for fallback in "${HOME}/SourceTree.command/${filename}/${filename}" "${HOME}/Documents/Github/JobsGenesis/SourceTree.command/${filename}/${filename}"; do
    [[ -f "$candidate" ]] && break
    [[ -f "$fallback" ]] && candidate="$fallback"
  done
  SCRIPT_PATH="$candidate"
  SCRIPT_BASENAME="${filename:r}"
  LOG_FILE="${${TMPDIR:-/tmp}:A}/${SCRIPT_BASENAME}.log"
  is_sourcetree_runtime && IS_SOURCETREE_RUNTIME=1
  configure_output_mode
}
# 确认前后均配置外部命令的纯文本环境。
configure_output_mode() {
  if [[ "$IS_SOURCETREE_RUNTIME" == 1 || ! -t 1 || -z "${TERM:-}" || "${TERM:-}" == dumb || -n "${NO_COLOR+x}" ]]; then
    PLAIN_OUTPUT=1
    export NO_COLOR=1 FORCE_COLOR=0 CLICOLOR=0 ANSI_COLORS_DISABLED=1 npm_config_color=false
  fi
  return 0
}
strip_ansi_stream() {
  /usr/bin/perl -pe 's/\e\[[0-9;]*[[:alpha:]]//g'
}
# 展示颜色与业务正文分开，路径中的反斜杠保持原值。
log() {
  local level="$1" message="$2" rendered="$2" color=""
  case "$level" in
    info) color=$'\033[1;34m' ;;
    success) color=$'\033[1;32m' ;;
    warn) color=$'\033[1;33m' ;;
    error) color=$'\033[1;31m' ;;
  esac
  [[ "$PLAIN_OUTPUT" == 1 ]] || rendered="${color}${message}"$'\033[0m'
  if [[ "$LOG_READY" == 1 ]]; then
    print -r -- "$rendered" | tee -a "$LOG_FILE"
  else
    print -r -- "$rendered"
  fi
}
info_echo() { log info "ℹ $1"; }
success_echo() { log success "✔ $1"; }
warn_echo() { log warn "⚠ $1"; }
error_echo() { log error "✖ $1"; }
# 自述失败必须终止，不能进入后面的重置逻辑。
show_script_intro_and_wait() {
  prepare_intro_context
  print -r -- "============================== Git 提交回退 ==============================" | jobs_intro_style title
  print -r -- "脚本名称：${SCRIPT_BASENAME}.command" | jobs_intro_style title
  print -r -- "1、Sourcetree 仅 soft 回退未推送提交，改动保留在暂存区。" | jobs_intro_style body
  print -r -- "2、终端支持 soft、hard、提交、tag 和 reflog 五种模式；传入仓库路径仍需确认。" | jobs_intro_style body
  print -r -- "3、远端回退使用已配置的 upstream；未配置时才尝试 origin/当前分支，不自动 fetch。" | jobs_intro_style body
  print -r -- "4、soft 只允许 upstream 为 HEAD 祖先；落后或分叉时停止，避免引入或覆盖远端历史。" | jobs_intro_style body
  print -r -- "5、所有 hard 模式会舍弃已跟踪的未提交内容，必须输入 YES；不递归重置子模块。" | jobs_intro_style body
  print -r -- "取消方式：Ctrl+C；日志位于 ${LOG_FILE}" | jobs_intro_style body
  if [[ "$IS_SOURCETREE_RUNTIME" == 1 ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    print -u2 -r -- "当前不是 Sourcetree，且没有可交互输入；请在终端重新运行。"
    exit 1
  fi
  read -r '?已了解用途与影响，按回车继续；Ctrl+C 取消：' _ || exit 1
}
initialize_script_runtime() {
  emulate -R zsh
  setopt NO_NOMATCH ERR_EXIT PIPE_FAIL
  export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
  : > "$LOG_FILE"
  LOG_READY=1
  configure_output_mode
}
check_environment() {
  command -v git >/dev/null && git --version >/dev/null || { error_echo "Git 不可用。"; return 1; }
}
# 拖入路径只做字符串解引用，不执行用户输入。
resolve_repository() {
  local candidate="${1:-${REPO:-}}" entered=""
  if [[ -z "$candidate" ]]; then
    if [[ "$IS_SOURCETREE_RUNTIME" == 1 ]]; then
      error_echo '未收到仓库路径；请在动作参数栏填写 $REPO。'
      return 1
    fi
    info_echo "输入或拖入仓库路径；直接回车使用当前目录：${PWD}"
    read -r 'entered?仓库路径：' || return 1
    candidate="${entered:-$PWD}"
  fi
  candidate="${candidate%$'\r'}"
  [[ -e "$candidate" ]] || candidate="${(Q)candidate}"
  [[ -f "$candidate" ]] && candidate="${candidate:h}"
  [[ -d "$candidate" ]] || { error_echo "目标目录不存在：${candidate}"; return 1; }
  REPO_ROOT="$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null)" || { error_echo "目标不在 Git 工作树中：${candidate}"; return 1; }
  REPO_ROOT="${REPO_ROOT:A}"
  info_echo "当前 Git 仓库：${REPO_ROOT}"
}
# 冲突、未完成操作或游离 HEAD 下不能把回退解释为未推送提交撤回。
check_repository_state() {
  local metadata="$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir)" marker=""
  if [[ -n "$(git -C "$REPO_ROOT" ls-files --unmerged)" ]]; then
    error_echo "存在未解决冲突，请先处理。"
    return 1
  fi
  for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply sequencer index.lock; do
    [[ ! -e "${metadata}/${marker}" ]] || { error_echo "存在未完成操作或锁：${marker}"; return 1; }
  done
}
# 只读取本地远端跟踪快照；有明确配置但引用丢失时不猜另一条线路。
resolve_upstream_target() {
  local branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  local configured_remote=""
  [[ -n "$branch" ]] || { error_echo "游离 HEAD 没有明确当前分支，不能回退到远端。"; return 1; }
  configured_remote="$(git -C "$REPO_ROOT" config --get "branch.${branch}.remote" || true)"
  UPSTREAM_REF="$(git -C "$REPO_ROOT" rev-parse --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [[ -z "$UPSTREAM_REF" && -z "$configured_remote" ]]; then
    UPSTREAM_REF="refs/remotes/origin/${branch}"
  fi
  [[ "$UPSTREAM_REF" == refs/remotes/* ]] || { error_echo "当前分支没有有效远端跟踪 upstream；请先核对跟踪配置。"; return 1; }
  RESET_TARGET="$(git -C "$REPO_ROOT" rev-parse --verify "${UPSTREAM_REF}^{commit}" 2>/dev/null)" || { error_echo "远端跟踪引用不可用：${UPSTREAM_REF}"; return 1; }
  info_echo "本地跟踪快照：${UPSTREAM_REF} [${RESET_TARGET}]"
}
# soft 不改变工作区，仅撤回已确定尚未进入 upstream 的线性历史。
reset_soft_to_remote() {
  resolve_upstream_target || return 1
  if ! git -C "$REPO_ROOT" merge-base --is-ancestor "$RESET_TARGET" HEAD; then
    error_echo "本地分支落后于 upstream 或历史已经分叉；请先 Fetch 并检查双方历史。"
    return 1
  fi
  local ahead="$(git -C "$REPO_ROOT" rev-list --count "${RESET_TARGET}..HEAD")"
  if [[ "$ahead" == 0 ]]; then
    info_echo "没有需要撤回的未推送提交，保持现状。"
    return 0
  fi
  info_echo "撤回 ${ahead} 个本地提交，保留工作区及已有暂存内容。"
  run_git reset --soft "$RESET_TARGET" || return 1
  success_echo "已 soft 回退；对应内容保留在暂存区。"
}
# 保留外部 Git 的原始退出码，任何重置失败都不能打印成功。
run_git() {
  local -a result_codes=()
  if git -C "$REPO_ROOT" "$@" 2>&1 | strip_ansi_stream | tee -a "$LOG_FILE"; then
    return 0
  fi
  result_codes=("${pipestatus[@]}")
  [[ "${result_codes[1]}" != 0 ]] && return "${result_codes[1]}"
  return 1
}
# hard 以已解析的提交号固定目标，防止 tag 名歧义和确认后引用变化。
confirm_and_reset_hard() {
  local target="$1" description="$2" answer="" commit=""
  commit="$(git -C "$REPO_ROOT" rev-parse --verify "${target}^{commit}" 2>/dev/null)" || { error_echo "所选目标不是有效提交：${description}"; return 1; }
  warn_echo "仓库：${REPO_ROOT}"
  warn_echo "hard 回退目标：${description} [${commit}]；已跟踪的未提交内容会被舍弃。"
  read -r 'answer?输入 YES 执行；其它输入取消：' || return 1
  if [[ "$answer" != YES ]]; then
    info_echo "已取消 hard 回退。"
    return 0
  fi
  run_git -c submodule.recurse=false reset --hard --no-recurse-submodules "$commit" || return 1
  success_echo "已 hard 回退到 ${commit}；子模块工作树保持原状。"
}
# fzf 已有则复用；没有时使用 zsh 原生编号选择，不引入包管理器安装副作用。
choose_entry() {
  local title="$1" entry="" reply=""
  local -a entries=()
  shift
  for entry in "$@"; do
    [[ -n "$entry" ]] && entries+=("$entry")
  done
  SELECTION=""
  [[ "${#entries[@]}" -gt 0 ]] || { error_echo "没有可供选择的记录：${title}"; return 1; }
  if command -v fzf >/dev/null 2>&1; then
    SELECTION="$(printf '%s\n' "${entries[@]}" | fzf --no-sort --reverse --prompt="${title}：")" || return 0
  else
    info_echo "${title}（输入编号；输入 0 取消）"
    local index=1
    for entry in "${entries[@]}"; do
      print -r -- "${index}、${entry}"
      index=$((index + 1))
    done
    read -r 'reply?编号：' || return 1
    [[ "$reply" == <-> && "$reply" -gt 0 && "$reply" -le "${#entries[@]}" ]] || return 0
    SELECTION="${entries[$reply]}"
  fi
}
# 提交列表首列始终为完整 hash，不从图形线条里猜目标。
run_interactive_reset() {
  local -a records=()
  choose_entry "选择回退模式" "soft 回退到 upstream" "hard 回退到 upstream" "选择提交 hard 回退" "选择 tag hard 回退" "选择 reflog hard 回退" || return 1
  RESET_MODE="$SELECTION"
  case "$RESET_MODE" in
    'soft 回退到 upstream') reset_soft_to_remote ;;
    'hard 回退到 upstream')
      resolve_upstream_target || return 1
      confirm_and_reset_hard "$RESET_TARGET" "$UPSTREAM_REF"
      ;;
    '选择提交 hard 回退')
      records=("${(@f)$(git -C "$REPO_ROOT" log --all --format='%H %s' --max-count=200)}")
      choose_entry "选择提交" "${records[@]}" || return 1
      [[ -n "$SELECTION" ]] || return 0
      confirm_and_reset_hard "${SELECTION%% *}" "$SELECTION"
      ;;
    '选择 tag hard 回退')
      records=("${(@f)$(git -C "$REPO_ROOT" tag --sort=-creatordate)}")
      choose_entry "选择 tag" "${records[@]}" || return 1
      [[ -n "$SELECTION" ]] || return 0
      confirm_and_reset_hard "refs/tags/${SELECTION}" "$SELECTION"
      ;;
    '选择 reflog hard 回退')
      records=("${(@f)$(git -C "$REPO_ROOT" reflog --format='%H %gd %gs' --max-count=200)}")
      choose_entry "选择 reflog" "${records[@]}" || return 1
      [[ -n "$SELECTION" ]] || return 0
      confirm_and_reset_hard "${SELECTION%% *}" "$SELECTION"
      ;;
    *) info_echo "已取消回退。" ;;
  esac
}
run_reset_workflow() {
  if [[ "$IS_SOURCETREE_RUNTIME" == 1 ]]; then
    reset_soft_to_remote
  else
    run_interactive_reset
  fi
}
print_completion() {
  success_echo "提交回退流程结束；日志：${LOG_FILE}"
}
main() {
  show_script_intro_and_wait # 首屏自述与确认，Sourcetree 仅跳过入口确认。
  initialize_script_runtime # 确认后准备日志与 Shell 选项。
  check_environment # 验证 Git 可用。
  resolve_repository "$@" # 使用指定仓库或终端输入，避免误处理脚本所在仓库。
  check_repository_state # 冲突、锁与未完成操作阻止重置。
  run_reset_workflow # Sourcetree 执行安全 soft 模式，终端允许选择并确认 hard 模式。
  print_completion # 业务成功后输出结果与日志位置。
}

main "$@"
