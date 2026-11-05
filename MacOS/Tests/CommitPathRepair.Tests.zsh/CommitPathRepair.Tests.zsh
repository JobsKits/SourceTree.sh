#!/bin/zsh
# 脚本自述：
# - 脚本名称：CommitPathRepair.Tests.zsh
# - 核心用途：在隔离 Git 仓库内验证 Commit 旧路径修复及索引保护边界。
# - 影响范围：仅本次临时夹具；不访问真实业务仓库或网络，不改变用户 Git 配置。
# - 运行提示：终端先回车确认；--run 明确启动自动回归，结束保留夹具和日志。

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
