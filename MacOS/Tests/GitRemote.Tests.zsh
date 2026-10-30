#!/bin/zsh
# 脚本自述：
# - 核心用途：以临时 Git 仓库、假剪贴板、假浏览器和假安装器验证远程地址动作。
# - 影响范围：只写本次系统临时目录；不联网、不安装、不操作真实业务仓库或剪贴板。
# - 运行提示：请在真实终端运行；fzf 分支使用假命令验证结果和取消传播。
# shell: zsh

TEST_SOURCE_PATH="${0:A}"
TEST_ROOT=""
TEST_REPOSITORY=""
TEST_SUBJECT=""
TEST_LIBRARY=""
TEST_PASSED=0
TEST_FAILED=0
# 清理本次专用临时目录，不触碰仓库或用户数据。
cleanup_test_workspace() {
  if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]]; then
    /usr/bin/find "$TEST_ROOT" -type f -exec /bin/chmod u+w {} +
    /bin/rm -r -- "$TEST_ROOT"
  fi
  return 0
}
# 打印测试说明并阻止非终端把选择器测试误报为通过。
show_test_intro() {
  print -r -- 'Git 远程地址隔离回归：只操作临时仓库，浏览器 / 剪贴板 / 安装均替身执行。'
  [[ -t 0 && -t 1 ]] || { print -u2 -r -- '请在真实终端运行本测试，以覆盖选择器的 TTY 门禁。'; exit 2; }
}
# 初始化隔离环境并提取函数定义，去掉生产脚本唯一的 main 调用。
prepare_test_workspace() {
  emulate -R zsh
  setopt NO_NOMATCH PIPE_FAIL
  TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/jobs-git-remote-tests.XXXXXX")" || exit 1
  TEST_SUBJECT="${TEST_SOURCE_PATH:h:h}/【MacOS@SourceTree】🌐获取远程仓库地址.command/【MacOS@SourceTree】🌐获取远程仓库地址.command"
  TEST_LIBRARY="$TEST_ROOT/remote-functions.zsh"
  /usr/bin/sed '$d' "$TEST_SUBJECT" > "$TEST_LIBRARY" || exit 1
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_NAMESPACE
  /bin/mkdir -p "$TEST_ROOT/bin"
  cat > "$TEST_ROOT/bin/fzf" <<'FZF'
#!/bin/zsh
[[ "$1" != --version ]] || { print -r -- '0.60.0'; exit 0; }
[[ -z "${FZF_DEFAULT_OPTS:-}${FZF_DEFAULT_OPTS_FILE:-}${FZF_DEFAULT_COMMAND:-}" ]] || exit 42
typeset -a rows=()
while IFS= read -r row; do rows+=("$row"); done
case "${TEST_FZF_MODE:-second}" in
  cancel) exit 130 ;;
  nomatch) exit 1 ;;
  fail) exit 2 ;;
  empty) exit 0 ;;
  forged) print -r -- $'1\t伪造结果'; exit 0 ;;
  *) print -r -- "${rows[2]}" ;;
esac
FZF
  cat > "$TEST_ROOT/bin/pbcopy" <<'CLIPBOARD'
#!/bin/zsh
/bin/cat > "$TEST_CLIPBOARD"
exit "${TEST_CLIPBOARD_RC:-0}"
CLIPBOARD
  cat > "$TEST_ROOT/bin/brew" <<'BREW'
#!/bin/zsh
print -r -- "$*" >> "$TEST_BREW_TRACE"
case "$1" in
  list) exit 1 ;;
  install|reinstall) [[ "${TEST_BREW_RC:-0}" == 0 ]] || exit "$TEST_BREW_RC"; /usr/bin/touch "$TEST_FZF_READY" ;;
esac
BREW
  /bin/chmod +x "$TEST_ROOT/bin/fzf" "$TEST_ROOT/bin/pbcopy" "$TEST_ROOT/bin/brew"
}
# 每个用例使用独立子进程，生产函数的 exit 不影响后续用例。
run_case() {
  local title="$1" callback="$2"
  if ( "$callback" ); then
    TEST_PASSED=$((TEST_PASSED + 1))
    print -r -- "PASS  $title"
  else
    TEST_FAILED=$((TEST_FAILED + 1))
    print -r -- "FAIL  $title"
  fi
}
# 核对实际值，失败时给出便于排查的差异。
assert_equal() {
  [[ "$1" == "$2" ]] || { print -u2 -r -- "期望：$2；实际：$1"; return 1; }
}
# 为每例创建独立临时仓库并重置生产状态。
new_repository() {
  TEST_REPOSITORY="$(/usr/bin/mktemp -d "$TEST_ROOT/仓库 空格.XXXXXX")" || return 1
  git init -q "$TEST_REPOSITORY" || return 1
  REPOSITORY_ROOT="$TEST_REPOSITORY"
  REQUESTED_REMOTE=""
  REMOTE_URLS=()
  REMOTE_LABELS=()
  PLAIN_OUTPUT=1
  LOG_READY=0
  IS_SOURCETREE_RUNTIME=0
}
# 无远程必须失败，不能生成默认目标。
case_no_remote() {
  new_repository || return 1
  (collect_remote_candidates)
  (( $? != 0 ))
}
# 同一 fetch / push 地址去重后直接选择，不调用依赖安装。
case_single_remote() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" remote add origin 'git@example.com:group/repo.git' || return 1
  collect_remote_candidates
  ensure_fzf_dependency() { return 99; }
  select_remote_candidate || return 1
  assert_equal "${#REMOTE_URLS}" 1 && assert_equal "$REMOTE_URL" 'git@example.com:group/repo.git'
}
# origin 不享有默认优先权，多个不同远程都进入候选。
case_multiple_remotes() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" remote add origin 'https://github.example/group/repo.git'
  git -C "$TEST_REPOSITORY" remote add gitee 'https://gitee.example/group/repo.git'
  collect_remote_candidates
  assert_equal "${#REMOTE_URLS}" 2 && [[ "${(j:|:)REMOTE_URLS}" == *github.example* && "${(j:|:)REMOTE_URLS}" == *gitee.example* ]]
}
# 单个 remote 的多个 fetch 和专属 push 地址不能遗漏。
case_multiple_urls() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" remote add origin 'https://a.example/g/r.git'
  git -C "$TEST_REPOSITORY" config --add remote.origin.url 'https://b.example/g/r.git'
  git -C "$TEST_REPOSITORY" config --add remote.origin.pushurl 'ssh://git@c.example/g/r.git'
  collect_remote_candidates
  assert_equal "${#REMOTE_URLS}" 3 && assert_equal "${REMOTE_URLS[3]}" 'ssh://git@c.example/g/r.git'
}
# 不同 remote 的完全相同 URL 只保留一个，并保留两个来源标签。
case_deduplicate_urls() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" remote add origin 'https://same.example/g/r.git'
  git -C "$TEST_REPOSITORY" remote add mirror 'https://same.example/g/r.git'
  collect_remote_candidates
  assert_equal "${#REMOTE_URLS}" 1 && [[ "${REMOTE_LABELS[1]}" == *origin/fetch* && "${REMOTE_LABELS[1]}" == *mirror/fetch* ]]
}
# 显式 remote 限定范围，错误名称必须停止。
case_explicit_remote() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" remote add origin 'https://a.example/g/r.git'
  git -C "$TEST_REPOSITORY" remote add mirror 'https://b.example/g/r.git'
  parse_remote_arguments "$TEST_REPOSITORY" mirror
  collect_remote_candidates
  assert_equal "${REMOTE_URLS[1]}" 'https://b.example/g/r.git' || return 1
  REQUESTED_REMOTE=missing
  (collect_remote_candidates)
  (( $? != 0 ))
}
# Git 自己展开 insteadOf，不按字符串猜测生效 URL。
case_instead_of() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" config url.https://expanded.example/group/.insteadOf short:
  git -C "$TEST_REPOSITORY" remote add origin short:repo.git
  collect_remote_candidates
  assert_equal "${REMOTE_URLS[1]}" 'https://expanded.example/group/repo.git'
}
# 子目录、文件及嵌套仓库均识别最近工作树。
case_repository_paths() {
  new_repository || return 1
  /bin/mkdir -p "$TEST_REPOSITORY/子目录 深层/内部仓库"
  /usr/bin/touch "$TEST_REPOSITORY/子目录 深层/文件.txt"
  resolve_repository_root "$TEST_REPOSITORY/子目录 深层/文件.txt"
  assert_equal "$REPOSITORY_ROOT" "${TEST_REPOSITORY:A}" || return 1
  git init -q "$TEST_REPOSITORY/子目录 深层/内部仓库"
  resolve_repository_root "$TEST_REPOSITORY/子目录 深层/内部仓库"
  assert_equal "$REPOSITORY_ROOT" "${TEST_REPOSITORY:A}/子目录 深层/内部仓库"
}
# .git 指针文件形式的 worktree 仍然能定位其独立工作树。
case_worktree() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm fixture || return 1
  git -C "$TEST_REPOSITORY" worktree add -qb fixture-worktree "$TEST_REPOSITORY/工作树" || return 1
  [[ -f "$TEST_REPOSITORY/工作树/.git" ]] || return 1
  resolve_repository_root "$TEST_REPOSITORY/工作树"
  assert_equal "$REPOSITORY_ROOT" "${TEST_REPOSITORY:A}/工作树"
}
# 运行态初始化只清理当前进程 Git 定位变量，避免 Sourcetree 环境污染目标仓。
case_git_environment() {
  export GIT_DIR=/invalid/git GIT_WORK_TREE=/invalid/tree GIT_INDEX_FILE=/invalid/index GIT_COMMON_DIR=/invalid/common
  resolve_script_path() { print -r -- "$TEST_SUBJECT"; }
  is_sourcetree_runtime() { return 0; }
  LOG_DIR="$TEST_ROOT"
  initialize_script_runtime
  [[ -z "${GIT_DIR+x}${GIT_WORK_TREE+x}${GIT_INDEX_FILE+x}${GIT_COMMON_DIR+x}" ]]
}
# 日志和选择器隐藏凭据及查询内容，保留原始业务地址。
case_redaction() {
  local input='https://name:secret@example.com/g/r.git?token=hidden#fragment' output=""
  output="$(protect_remote_text "$input")"
  [[ "$output" == *example.com/g/r.git* && "$output" != *secret* && "$output" != *hidden* && "$output" != *fragment* ]] || return 1
  output="$(protect_remote_text $'git@example.com:g/r.git\033[31m')"
  [[ "$output" != *$'\033'* && "$output" != *git@* ]]
}
# 多类网络克隆 URL 转换时保留明确的 HTTP 端口并去掉 .git。
case_web_urls() {
  assert_equal "$(remote_url_to_web_url 'git@example.com:group/sub/repo.git')" 'https://example.com/group/sub/repo' || return 1
  assert_equal "$(remote_url_to_web_url 'ssh://git@example.com:22/group/repo.git')" 'https://example.com/group/repo' || return 1
  assert_equal "$(remote_url_to_web_url 'https://u:secret@example.com:8443/group/repo.git?token=secret')" 'https://example.com:8443/group/repo' || return 1
  assert_equal "$(remote_url_to_web_url 'http://example.com/group/repo.git/')" 'http://example.com/group/repo' || return 1
  assert_equal "$(remote_url_to_web_url 'git://example.com/group/repo.git')" 'https://example.com/group/repo'
}
# 本地路径、控制字符、危险协议和不能确定网页端口的 SSH 地址不得打开。
case_rejected_web_urls() {
  local input=""
  for input in '/tmp/repo.git' '../repo' 'C:\repo.git' 'file:///tmp/repo.git' 'javascript://example.com/alert(1)' 'ssh://git@example.com:2222/group/repo.git' 'https://example.com/../repo.git' $'https://example.com/g/\nrepo'; do
    if remote_url_to_web_url "$input" >/dev/null; then
      print -u2 -r -- "错误接受地址：$input"
      return 1
    fi
  done
}
# 剪贴板替身必须收到原始 URL；失败状态不能伪报成功。
case_copy_action() {
  export TEST_CLIPBOARD="$TEST_ROOT/clipboard" TEST_CLIPBOARD_RC=0
  export PATH="$TEST_ROOT/bin:$PATH"
  REMOTE_ACTION=copy
  REMOTE_URL='https://u:secret@example.com/g/r.git?token=secret'
  perform_remote_action
  assert_equal "$(/bin/cat "$TEST_CLIPBOARD")" "$REMOTE_URL" || return 1
  export TEST_CLIPBOARD_RC=7
  (perform_remote_action)
  (( $? != 0 ))
}
# 浏览器替身仅收到转换后的 HTTPS 地址，不启动真实应用。
case_open_action() {
  REMOTE_ACTION=open
  REMOTE_URL='git@example.com:group/repo.git'
  open_remote_web_url() { print -rn -- "$1" > "$TEST_ROOT/browser"; }
  perform_remote_action
  assert_equal "$(/bin/cat "$TEST_ROOT/browser")" 'https://example.com/group/repo'
}
# 假选择器选择第二条并校验隐藏 ID 映射和默认参数清理。
case_fzf_selection() {
  REMOTE_URLS=('https://a.example/g/r.git?token=one' 'https://b.example/g/r.git?token=two')
  REMOTE_LABELS=('origin/fetch' 'mirror/fetch')
  export FZF_DEFAULT_OPTS='--bind enter:execute(touch unsafe)' FZF_DEFAULT_OPTS_FILE=/invalid FZF_DEFAULT_COMMAND=unsafe TEST_FZF_MODE=second
  ensure_fzf_dependency() { FZF_BIN="$TEST_ROOT/bin/fzf"; }
  select_remote_candidate
  assert_equal "$REMOTE_URL" "${REMOTE_URLS[2]}"
}
# Esc、无匹配及空输出均以成功取消结束，后续业务标记保持不存在。
case_fzf_cancellation() {
  REMOTE_URLS=('https://a.example/r.git' 'https://b.example/r.git')
  REMOTE_LABELS=('a/fetch' 'b/fetch')
  ensure_fzf_dependency() { FZF_BIN="$TEST_ROOT/bin/fzf"; }
  local mode=""
  for mode in cancel nomatch empty; do
    export TEST_FZF_MODE="$mode"
    (select_remote_candidate; /usr/bin/touch "$TEST_ROOT/cancel-business")
    [[ $? == 0 && ! -e "$TEST_ROOT/cancel-business" ]] || return 1
  done
}
# 选择器失败和伪造结果必须以失败结束，不能复制或打开。
case_fzf_failure() {
  REMOTE_URLS=('https://a.example/r.git' 'https://b.example/r.git')
  REMOTE_LABELS=('a/fetch' 'b/fetch')
  ensure_fzf_dependency() { FZF_BIN="$TEST_ROOT/bin/fzf"; }
  local mode=""
  for mode in fail forged; do
    export TEST_FZF_MODE="$mode"
    (select_remote_candidate)
    (( $? != 0 )) || return 1
  done
}
# 对本机现有 fzf 进行无交互选项健康探针，不修改安装。
case_real_fzf_health() {
  local candidate="$(command -v fzf)"
  [[ -n "$candidate" ]] || { print -r -- 'SKIP  本机未安装 fzf，跳过真实二进制健康探针。'; return 0; }
  fzf_candidate_ok "$candidate"
}
# 全链健康时不触发 Homebrew 或安装分支。
case_dependency_healthy() {
  find_healthy_fzf() { return 0; }
  jobs_brew_install_or_exit() { return 91; }
  ensure_fzf_dependency
}
# 假安装器与状态文件覆盖 fzf 缺失、安装失败和安装后复检失败。
case_dependency_repair() {
  export TEST_BREW_TRACE="$TEST_ROOT/brew.trace" TEST_FZF_READY="$TEST_ROOT/fzf-ready" TEST_BREW_RC=0
  find_healthy_fzf() { [[ -e "$TEST_FZF_READY" ]]; }
  jobs_brew_install_or_exit() { JOBS_HOMEBREW_BIN="$TEST_ROOT/bin/brew"; JOBS_HOMEBREW_PREFIX="$TEST_ROOT"; }
  ensure_fzf_dependency <<< '' || return 1
  [[ -e "$TEST_FZF_READY" ]] && [[ "$(/bin/cat "$TEST_BREW_TRACE")" == *'install fzf'* ]]
}
# 安装失败必须停止，不能继续到成功业务。
case_dependency_install_failure() {
  export TEST_BREW_TRACE="$TEST_ROOT/brew-failed.trace" TEST_FZF_READY="$TEST_ROOT/fzf-failed" TEST_BREW_RC=8
  find_healthy_fzf() { return 1; }
  jobs_brew_install_or_exit() { JOBS_HOMEBREW_BIN="$TEST_ROOT/bin/brew"; JOBS_HOMEBREW_PREFIX="$TEST_ROOT"; }
  (ensure_fzf_dependency <<< '')
  (( $? != 0 )) && [[ ! -e "$TEST_FZF_READY" ]]
}
# 安装返回成功但 fzf 仍不健康时必须失败。
case_dependency_recheck_failure() {
  export TEST_BREW_TRACE="$TEST_ROOT/brew-recheck.trace" TEST_FZF_READY="$TEST_ROOT/fzf-recheck" TEST_BREW_RC=0
  find_healthy_fzf() { return 1; }
  jobs_brew_install_or_exit() { JOBS_HOMEBREW_BIN="$TEST_ROOT/bin/brew"; JOBS_HOMEBREW_PREFIX="$TEST_ROOT"; }
  (ensure_fzf_dependency <<< '')
  (( $? != 0 ))
}
# 多层缺失只走选定的安装来源，安装与激活各调用一次。
case_brew_missing_chain() {
  local trace="$TEST_ROOT/brew-chain.trace"
  jobs_brew_find() { return 1; }
  jobs_brew_choose_installation() { JOBS_HOMEBREW_INSTALL_MODE=user; print -r -- choose >> "$trace"; }
  jobs_brew_install_user() { print -r -- install >> "$trace"; }
  jobs_brew_activate() { print -r -- "activate:$1" >> "$trace"; }
  jobs_brew_install_or_exit
  assert_equal "$(/bin/cat "$trace")" $'choose\ninstall\nactivate:installed'
}
# 已有 Homebrew 只激活并复检，不安装或修改 Shell 配置。
case_brew_healthy_chain() {
  local trace="$TEST_ROOT/brew-healthy.trace"
  jobs_brew_find() { print -r -- "$TEST_ROOT/bin/brew"; }
  jobs_brew_choose_installation() { return 88; }
  jobs_brew_activate() { print -r -- "activate:$1" >> "$trace"; }
  jobs_brew_install_or_exit
  assert_equal "$(/bin/cat "$trace")" 'activate:'
}
# 完整获取入口从参数解析到剪贴板执行，Sourcetree 单地址不打开终端。
case_copy_entry_flow() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" remote add origin 'https://example.com/g/r.git'
  export SOURCETREE_TEST_CONTEXT=1 TEST_CLIPBOARD="$TEST_ROOT/full-clipboard" TEST_CLIPBOARD_RC=0
  export PATH="$TEST_ROOT/bin:$PATH"
  LOG_DIR="$TEST_ROOT"
  resolve_script_path() { print -r -- "$TEST_SUBJECT"; }
  ensure_fzf_dependency() { return 99; }
  open_terminal_for_selection() { return 98; }
  main "$TEST_REPOSITORY" || return 1
  assert_equal "$(/bin/cat "$TEST_CLIPBOARD")" 'https://example.com/g/r.git'
}
# 文件名决定打开模式，完整入口仍共用同一候选逻辑。
case_open_entry_flow() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" remote add origin 'git@example.com:group/repo.git'
  export SOURCETREE_TEST_CONTEXT=1
  LOG_DIR="$TEST_ROOT"
  resolve_script_path() { print -r -- "${TEST_SUBJECT:h:h}/【MacOS@SourceTree】🌍打开远程仓库地址.command/【MacOS@SourceTree】🌍打开远程仓库地址.command"; }
  open_remote_web_url() { print -rn -- "$1" > "$TEST_ROOT/full-browser"; }
  main "$TEST_REPOSITORY" || return 1
  assert_equal "$(/bin/cat "$TEST_ROOT/full-browser")" 'https://example.com/group/repo'
}
# Sourcetree 多地址只转交终端，后台不运行选择器或复制。
case_terminal_handoff_flow() {
  new_repository || return 1
  git -C "$TEST_REPOSITORY" remote add origin 'https://a.example/g/r.git'
  git -C "$TEST_REPOSITORY" remote add mirror 'https://b.example/g/r.git'
  export SOURCETREE_TEST_CONTEXT=1
  LOG_DIR="$TEST_ROOT"
  resolve_script_path() { print -r -- "$TEST_SUBJECT"; }
  open_terminal_for_selection() { print -rn -- "$REPOSITORY_ROOT" > "$TEST_ROOT/handoff"; exit 0; }
  (main "$TEST_REPOSITORY"; /usr/bin/touch "$TEST_ROOT/handoff-business")
  [[ $? == 0 && ! -e "$TEST_ROOT/handoff-business" ]] || return 1
  assert_equal "$(/bin/cat "$TEST_ROOT/handoff")" "${TEST_REPOSITORY:A}"
}
# 顺序运行所有隔离场景，并以失败数量决定最终状态。
run_regressions() {
  run_case '无远程停止' case_no_remote
  run_case '唯一地址直接选择' case_single_remote
  run_case '多个远程完整枚举' case_multiple_remotes
  run_case '单远程多 fetch / push URL' case_multiple_urls
  run_case '跨远程 URL 去重与来源保留' case_deduplicate_urls
  run_case '显式 remote 与错误名称' case_explicit_remote
  run_case 'insteadOf 生效地址' case_instead_of
  run_case '中文空格文件和最近嵌套仓库' case_repository_paths
  run_case '.git 文件 worktree' case_worktree
  run_case 'Git 定位变量隔离' case_git_environment
  run_case '菜单日志凭据脱敏' case_redaction
  run_case '网络 URL 网页转换' case_web_urls
  run_case '不安全和不明确地址拒绝' case_rejected_web_urls
  run_case '原始 URL 剪贴板与失败传播' case_copy_action
  run_case '浏览器转换目标' case_open_action
  run_case 'fzf 第二行映射及默认配置隔离' case_fzf_selection
  run_case 'fzf 取消空选无业务' case_fzf_cancellation
  run_case 'fzf 失败伪造结果停止' case_fzf_failure
  run_case '真实 fzf 健康探针' case_real_fzf_health
  run_case '依赖全链健康不安装' case_dependency_healthy
  run_case '末端缺失上游健康修复' case_dependency_repair
  run_case '依赖安装失败停止' case_dependency_install_failure
  run_case '依赖安装后复检失败停止' case_dependency_recheck_failure
  run_case 'Homebrew 多层缺失单次安装' case_brew_missing_chain
  run_case 'Homebrew 健康来源复用' case_brew_healthy_chain
  run_case '获取入口完整单地址流程' case_copy_entry_flow
  run_case '打开入口完整单地址流程' case_open_entry_flow
  run_case 'Sourcetree 多地址终端承接' case_terminal_handoff_flow
  print -r -- "结果：$TEST_PASSED 通过，$TEST_FAILED 失败。"
  (( TEST_FAILED == 0 ))
}
# 加载生产函数后立即运行测试，避免执行生产 main。
load_subject_and_run() {
  source "$TEST_LIBRARY" || { cleanup_test_workspace; return 1; }
  run_regressions
  local result=$?
  cleanup_test_workspace
  return "$result"
}
# 编排说明、隔离环境与回归，不执行真实远程动作。
main() {
  show_test_intro # 打印隔离范围并验证真实 TTY。
  prepare_test_workspace # 准备临时 Git 和命令替身。
  load_subject_and_run # 载入生产函数并验证业务及失败边界。
}

main "$@"
