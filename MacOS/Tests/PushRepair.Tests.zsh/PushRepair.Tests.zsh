#!/bin/zsh
# 脚本自述：
# - 核心用途：使用隔离 Git 仓库和本地 bare 远端验证 Push 修复的真实行为与停止边界。
# - 影响范围：仅本次 /tmp 测试目录；只允许 file 协议，不使用用户身份、配置、hook 或真实远端。
# - 运行提示：可选第一个参数为待测脚本；结束保留夹具和日志，不执行真实业务推送。

TEST_PATH="${0:A}"
SUBJECT=""
TEST_ROOT=""
CASE_DIR=""
REPOSITORY=""
REMOTE_BARE=""
PEER=""
CAPTURE=""
CASE_INDEX=0
PASSED=0
FAILED=0

# 准备独立配置和 file 协议边界，业务脚本仍走完整入口。
prepare_environment() {
  setopt NO_NOMATCH PIPE_FAIL
  SUBJECT="${1:-${TEST_PATH:h:h:h}/【MacOS@SourceTree】📥修复Git无法Push.command/【MacOS@SourceTree】📥修复Git无法Push.command}"
  [[ -f "$SUBJECT" ]] || { print -u2 -r -- "生产脚本不存在：$SUBJECT"; exit 1; }
  SUBJECT="${SUBJECT:A}"
  TEST_ROOT="$(mktemp -d /tmp/jobs-push-repair-tests.XXXXXX)" || exit 1
  mkdir -p "$TEST_ROOT/Hooks"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=/usr/bin/false GIT_PROXY_COMMAND=/usr/bin/false
  export GIT_AUTHOR_NAME='Jobs fixture' GIT_COMMITTER_NAME='Jobs fixture' GIT_AUTHOR_EMAIL='fixture@example.invalid' GIT_COMMITTER_EMAIL='fixture@example.invalid'
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_NAMESPACE GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
}
# 初始化 main 及可信空 hook 目录，避免宿主 Git 配置进入夹具。
init_repository() {
  git init -q --initial-branch=main "$1" || return 1
  git -C "$1" config core.hooksPath "$TEST_ROOT/Hooks"
  git -C "$1" config commit.gpgsign false
}
# 每例都有自己的带中文空格路径、bare 远端及对端工作树。
new_fixture() {
  REPOSITORY="$CASE_DIR/工作仓库 空格"
  REMOTE_BARE="$CASE_DIR/发布远端.git"
  PEER="$CASE_DIR/对端 工作树"
  init_repository "$REPOSITORY" || return 1
  print -r -- base > "$REPOSITORY/base.txt"
  git -C "$REPOSITORY" add base.txt
  git -C "$REPOSITORY" commit -qm base || return 1
  git init -q --bare --initial-branch=main "$REMOTE_BARE"
  git -C "$REPOSITORY" remote add origin "$REMOTE_BARE"
  git -C "$REPOSITORY" push -q origin main || return 1
  git clone -q "$REMOTE_BARE" "$PEER" || return 1
  git -C "$PEER" config core.hooksPath "$TEST_ROOT/Hooks"
  git -C "$PEER" config commit.gpgsign false
}
# 生成有意义的新提交供领先／落后／分叉测试使用。
add_commit() {
  local repo="$1" file="$2" content="$3"
  print -r -- "$content" > "$repo/$file"
  git -C "$repo" add -- "$file"
  git -C "$repo" commit -qm "$content"
}
# 执行完整生产入口并核对期待的成功／失败。
run_subject() {
  local expected="$1" result_code=0
  local guard_path="" initial_guard=0
  shift
  if [[ -n "${REPOSITORY:-}" && -d "$REPOSITORY" ]]; then
    guard_path="$(git -C "$REPOSITORY" rev-parse --absolute-git-dir 2>/dev/null)/jobs-push-repair.lock"
    [[ ! -e "$guard_path" ]] || initial_guard=1
  fi
  /bin/zsh "$SUBJECT" --terminal-session "$@" > "$CASE_DIR/subject.log" 2>&1 || result_code=$?
  CAPTURE="$(<"$CASE_DIR/subject.log")"
  if (( initial_guard == 0 )) && [[ -n "$guard_path" && -e "$guard_path" ]]; then
    print -u2 -r -- "生产入口遗留自身互斥锁：$guard_path"
    return 1
  fi
  if [[ "$expected" == success ]]; then
    [[ "$result_code" == 0 ]] || { print -u2 -r -- "预期成功，退出 $result_code"; print -u2 -r -- "$CAPTURE"; return 1; }
  else
    [[ "$result_code" != 0 ]] || { print -u2 -r -- "预期失败但退出 0：$CAPTURE"; return 1; }
  fi
}
# 比较精确值，失败直接说明可复现证据。
assert_equal() {
  [[ "$1" == "$2" ]] || { print -u2 -r -- "期望：$2；实际：$1"; return 1; }
}
# 核对预期诊断，防止只因意外报错而让停止测试通过。
assert_contains() {
  [[ "$1" == *"$2"* ]] || { print -u2 -r -- "缺少：$2；实际：$1"; return 1; }
}
# 核对本地与服务端目标精确一致且工作区干净。
assert_synced() {
  assert_equal "$(git -C "$REPOSITORY" rev-parse HEAD)" "$(git --git-dir="$REMOTE_BARE" rev-parse refs/heads/main)" || return 1
  if [[ "$(git -C "$REPOSITORY" remote get-url origin)" == "$(git -C "$REPOSITORY" remote get-url --push origin)" ]]; then
    assert_equal "$(git -C "$REPOSITORY" rev-parse refs/remotes/origin/main)" "$(git -C "$REPOSITORY" rev-parse HEAD)" || return 1
  fi
  assert_equal "$(git -C "$REPOSITORY" status --porcelain=v1)" '' || return 1
  assert_contains "$CAPTURE" '[P25 已核验]'
}
# 每例单独进程与日志，确保失败不污染后续测试。
run_case() {
  local title="$1" callback="$2"
  CASE_INDEX=$((CASE_INDEX + 1))
  CASE_DIR="$TEST_ROOT/case-$CASE_INDEX"
  mkdir -p "$CASE_DIR"
  if ( setopt ERR_RETURN; "$callback" ) > "$CASE_DIR/result.log" 2>&1; then
    PASSED=$((PASSED + 1))
    print -r -- "PASS  $title"
  else
    FAILED=$((FAILED + 1))
    print -r -- "FAIL  $title；日志：$CASE_DIR/result.log"
    tail -n 24 "$CASE_DIR/result.log"
  fi
}
# 本地领先时只普通推送，并保留已有本地分支集合。
test_ahead() {
  new_fixture
  add_commit "$REPOSITORY" local.txt local
  local branches="$(git -C "$REPOSITORY" for-each-ref --format='%(refname)' refs/heads)"
  run_subject success --yes "$REPOSITORY" origin main
  assert_synced
  assert_equal "$(git -C "$REPOSITORY" for-each-ref --format='%(refname)' refs/heads)" "$branches"
}
# 本地仅落后时必须真实快进并下载对端正文。
test_behind() {
  new_fixture
  add_commit "$PEER" remote.txt remote
  git -C "$PEER" push -q origin main
  run_subject success --yes "$REPOSITORY" origin main
  assert_synced
  assert_equal "$(<"$REPOSITORY/remote.txt")" remote
  assert_equal "$(git -C "$REPOSITORY" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" 2
}
# 分叉但互不覆盖的修改合并后必须保留双方祖先与双父提交。
test_diverged() {
  new_fixture
  add_commit "$REPOSITORY" local.txt local
  local local_oid="$(git -C "$REPOSITORY" rev-parse HEAD)"
  add_commit "$PEER" remote.txt remote
  git -C "$PEER" push -q origin main
  local remote_oid="$(git -C "$PEER" rev-parse HEAD)"
  run_subject success --yes "$REPOSITORY" origin main
  assert_synced
  git -C "$REPOSITORY" merge-base --is-ancestor "$local_oid" HEAD
  git -C "$REPOSITORY" merge-base --is-ancestor "$remote_oid" HEAD
  assert_equal "$(git -C "$REPOSITORY" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" 3
}
# 本地文件迁入同名目录时，远端未修改该路径不能误报为新增碰撞。
test_diverged_local_file_to_directory() {
  new_fixture
  mv "$REPOSITORY/base.txt" "$REPOSITORY/base.original"
  mkdir "$REPOSITORY/base.txt"
  mv "$REPOSITORY/base.original" "$REPOSITORY/base.txt/base.txt"
  git -C "$REPOSITORY" add -A
  git -C "$REPOSITORY" commit -qm local-file-to-directory
  local local_oid="$(git -C "$REPOSITORY" rev-parse HEAD)"
  add_commit "$PEER" remote.txt unrelated-remote-change
  git -C "$PEER" push -q origin main
  local remote_oid="$(git -C "$PEER" rev-parse HEAD)"
  run_subject success --yes "$REPOSITORY" origin main
  assert_synced
  [[ -d "$REPOSITORY/base.txt" && -f "$REPOSITORY/base.txt/base.txt" ]]
  assert_equal "$(<"$REPOSITORY/base.txt/base.txt")" base
  assert_equal "$(<"$REPOSITORY/remote.txt")" unrelated-remote-change
  git -C "$REPOSITORY" cat-file -e HEAD:base.txt/base.txt
  git -C "$REPOSITORY" merge-base --is-ancestor "$local_oid" HEAD
  git -C "$REPOSITORY" merge-base --is-ancestor "$remote_oid" HEAD
  [[ "$CAPTURE" != *'碰撞'* ]]
}
# 文本冲突保留 MERGE_HEAD 与冲突索引，不选一方、不推送。
test_conflict() {
  new_fixture
  add_commit "$REPOSITORY" base.txt local
  local local_oid="$(git -C "$REPOSITORY" rev-parse HEAD)"
  add_commit "$PEER" base.txt remote
  git -C "$PEER" push -q origin main
  local remote_oid="$(git -C "$PEER" rev-parse HEAD)"
  run_subject failure --yes "$REPOSITORY" origin main
  assert_contains "$CAPTURE" '[P24]'
  assert_equal "$(git -C "$REPOSITORY" rev-parse HEAD)" "$local_oid"
  assert_equal "$(git --git-dir="$REMOTE_BARE" rev-parse main)" "$remote_oid"
  [[ -f "$REPOSITORY/.git/MERGE_HEAD" ]]
  [[ -n "$(git -C "$REPOSITORY" ls-files -u)" ]]
}
# 未提交正文、索引和远端必须原样保留。
test_dirty() {
  new_fixture
  print -r -- unsaved >> "$REPOSITORY/base.txt"
  local before="$(git -C "$REPOSITORY" hash-object base.txt)"
  local index_before="$(shasum -a 256 "$REPOSITORY/.git/index")"
  run_subject failure --yes "$REPOSITORY" origin main
  assert_contains "$CAPTURE" '[P06]'
  assert_equal "$(git -C "$REPOSITORY" hash-object base.txt)" "$before"
  assert_equal "$(shasum -a 256 "$REPOSITORY/.git/index")" "$index_before"
}
# 游离 HEAD 不建立救援分支，也不移动已有 main。
test_detached() {
  new_fixture
  git -C "$REPOSITORY" checkout -q --detach HEAD
  local refs="$(git -C "$REPOSITORY" show-ref)"
  run_subject failure --yes "$REPOSITORY" origin main
  assert_contains "$CAPTURE" '[P02]'
  assert_equal "$(git -C "$REPOSITORY" show-ref)" "$refs"
}
# 未出生分支不自动创建第一份提交。
test_unborn() {
  REPOSITORY="$CASE_DIR/空工作树"
  init_repository "$REPOSITORY"
  run_subject failure --yes "$REPOSITORY" origin main
  assert_contains "$CAPTURE" '[P03]'
  assert_equal "$(git -C "$REPOSITORY" log --oneline 2>/dev/null)" ''
}
# 无共同历史时停止，不合并独立快照链。
test_unrelated() {
  new_fixture
  local separate="$CASE_DIR/无关历史"
  init_repository "$separate"
  add_commit "$separate" other.txt unrelated
  git -C "$separate" remote add origin "$REMOTE_BARE"
  git -C "$separate" push -q --force origin main
  local original="$(git -C "$REPOSITORY" rev-parse HEAD)"
  run_subject failure --yes "$REPOSITORY" origin main
  assert_contains "$CAPTURE" '[P23]'
  assert_equal "$(git -C "$REPOSITORY" rev-parse HEAD)" "$original"
  [[ ! -f "$REPOSITORY/.git/MERGE_HEAD" ]]
}
# 显式分支可以发布到空远端，但仅创建所选目标。
test_empty_remote() {
  REPOSITORY="$CASE_DIR/有提交的工作树"
  REMOTE_BARE="$CASE_DIR/空远端.git"
  init_repository "$REPOSITORY"
  add_commit "$REPOSITORY" first.txt first
  git init -q --bare --initial-branch=main "$REMOTE_BARE"
  git -C "$REPOSITORY" remote add origin "$REMOTE_BARE"
  run_subject success --yes "$REPOSITORY" origin main
  assert_synced
  assert_equal "$(git --git-dir="$REMOTE_BARE" for-each-ref --format='%(refname)')" refs/heads/main
}
# 多远端且无映射时 --yes 不能替代目标选择。
test_ambiguous_remote() {
  new_fixture
  git -C "$REPOSITORY" remote add second "$REMOTE_BARE"
  run_subject failure --yes "$REPOSITORY"
  assert_contains "$CAPTURE" '存在多个候选'
}
# 单远端和同名分支可自动确定，无需写入 upstream 配置。
test_upstream_missing() {
  new_fixture
  add_commit "$REPOSITORY" local.txt local
  run_subject success --yes "$REPOSITORY"
  assert_synced
  assert_equal "$(git -C "$REPOSITORY" config --get branch.main.remote)" ''
}
# 不同 fetch／push 仓库时只合并真正发布端的历史。
test_pushurl() {
  new_fixture
  local wrong="$CASE_DIR/错误读取端.git"
  git clone -q --bare "$REMOTE_BARE" "$wrong"
  add_commit "$PEER" publish.txt publish
  git -C "$PEER" push -q origin main
  local published="$(git -C "$PEER" rev-parse HEAD)"
  git -C "$PEER" remote set-url origin "$wrong"
  add_commit "$PEER" wrong.txt wrong
  git -C "$PEER" push -q origin main
  git -C "$REPOSITORY" remote set-url origin "$wrong"
  git -C "$REPOSITORY" config remote.origin.pushurl "$REMOTE_BARE"
  run_subject success --yes "$REPOSITORY" origin main
  assert_synced
  assert_equal "$(git -C "$REPOSITORY" rev-parse HEAD)" "$published"
  [[ ! -f "$REPOSITORY/wrong.txt" ]]
}
# 只诊断不得更新 FETCH_HEAD、真实索引、配置、本地引用或工作区。
test_diagnose() {
  new_fixture
  add_commit "$PEER" remote.txt remote
  git -C "$PEER" push -q origin main
  local before="$(git -C "$REPOSITORY" show-ref)"
  local index_before="$(shasum -a 256 "$REPOSITORY/.git/index")"
  local config_before="$(shasum -a 256 "$REPOSITORY/.git/config")"
  run_subject success --diagnose "$REPOSITORY" origin main
  assert_contains "$CAPTURE" '诊断结束'
  assert_equal "$(git -C "$REPOSITORY" show-ref)" "$before"
  assert_equal "$(shasum -a 256 "$REPOSITORY/.git/index")" "$index_before"
  assert_equal "$(shasum -a 256 "$REPOSITORY/.git/config")" "$config_before"
  [[ ! -f "$REPOSITORY/.git/FETCH_HEAD" ]]
  [[ ! -d "$REPOSITORY/.git/jobs-push-repair.lock" ]]
  [[ ! -f "$REPOSITORY/remote.txt" ]]
}
# 残留锁原样保留，生产脚本不能以解锁之名删除它。
test_lock() {
  new_fixture
  print -r -- owner > "$REPOSITORY/.git/index.lock"
  run_subject failure --yes "$REPOSITORY" origin main
  assert_contains "$CAPTURE" '[P05]'
  assert_equal "$(<"$REPOSITORY/.git/index.lock")" owner
}
# 服务端保护规则拒绝时保持错误码与双方提交，不绕过 hook。
test_hook_rejection() {
  new_fixture
  add_commit "$REPOSITORY" local.txt local
  local remote_before="$(git --git-dir="$REMOTE_BARE" rev-parse main)"
  printf '%s\n' '#!/bin/sh' 'echo "protected branch: changes require a pull request" >&2' 'exit 1' > "$REMOTE_BARE/hooks/pre-receive"
  chmod u+x "$REMOTE_BARE/hooks/pre-receive"
  run_subject failure --yes "$REPOSITORY" origin main
  assert_contains "$CAPTURE" '[P13 平台规则]'
  assert_equal "$(git --git-dir="$REMOTE_BARE" rev-parse main)" "$remote_before"
  assert_equal "$(git -C "$REPOSITORY" status --porcelain=v1)" ''
}
# 隐藏的 ignored 文件也不能被远端同路径正文覆盖。
test_ignored_collision() {
  new_fixture
  add_commit "$REPOSITORY" .gitignore collision.txt
  git -C "$REPOSITORY" push -q origin main
  git -C "$PEER" pull -q --ff-only
  print -r -- '本地被忽略但必须保留' > "$REPOSITORY/collision.txt"
  print -r -- '远端跟踪版本' > "$PEER/collision.txt"
  git -C "$PEER" add -f collision.txt
  git -C "$PEER" commit -qm collision
  git -C "$PEER" push -q origin main
  local original="$(git -C "$REPOSITORY" rev-parse HEAD)"
  run_subject failure --yes "$REPOSITORY" origin main
  assert_equal "$(<"$REPOSITORY/collision.txt")" '本地被忽略但必须保留'
  assert_equal "$(git -C "$REPOSITORY" rev-parse HEAD)" "$original"
  assert_contains "$CAPTURE" '[P06]'
  assert_contains "$CAPTURE" '碰撞'
}
# ort 分叉合并也必须在进入合并之前保护 ignored 同名文件。
test_diverged_ignored_collision() {
  new_fixture
  add_commit "$REPOSITORY" .gitignore collision.txt
  git -C "$REPOSITORY" push -q origin main
  git -C "$PEER" pull -q --ff-only
  add_commit "$REPOSITORY" local.txt divergent-local
  print -r -- '本地未提交的被忽略数据' > "$REPOSITORY/collision.txt"
  print -r -- '对端需要入库的同名数据' > "$PEER/collision.txt"
  git -C "$PEER" add -f collision.txt
  git -C "$PEER" commit -qm divergent-remote
  git -C "$PEER" push -q origin main
  local original="$(git -C "$REPOSITORY" rev-parse HEAD)"
  local remote_before="$(git --git-dir="$REMOTE_BARE" rev-parse main)"
  run_subject failure --yes "$REPOSITORY" origin main
  assert_contains "$CAPTURE" '[P06]'
  assert_contains "$CAPTURE" '碰撞'
  assert_equal "$(<"$REPOSITORY/collision.txt")" '本地未提交的被忽略数据'
  assert_equal "$(git -C "$REPOSITORY" rev-parse HEAD)" "$original"
  assert_equal "$(git --git-dir="$REMOTE_BARE" rev-parse main)" "$remote_before"
  [[ ! -f "$REPOSITORY/.git/MERGE_HEAD" ]]
  [[ -z "$(git -C "$REPOSITORY" ls-files -u)" ]]
}
# 新增目录的祖先是 ignored 普通文件时，保留文件而非删除或转换。
test_incoming_ancestor_file() {
  new_fixture
  add_commit "$REPOSITORY" .gitignore incoming
  git -C "$REPOSITORY" push -q origin main
  git -C "$PEER" pull -q --ff-only
  add_commit "$REPOSITORY" local.txt divergent-local
  print -r -- '阻挡目录的本地文件' > "$REPOSITORY/incoming"
  mkdir -p "$PEER/incoming"
  print -r -- '对端子文件' > "$PEER/incoming/nested.txt"
  git -C "$PEER" add -f incoming/nested.txt
  git -C "$PEER" commit -qm incoming-directory
  git -C "$PEER" push -q origin main
  local original="$(git -C "$REPOSITORY" rev-parse HEAD)"
  local remote_before="$(git --git-dir="$REMOTE_BARE" rev-parse main)"
  run_subject failure --yes "$REPOSITORY" origin main
  assert_contains "$CAPTURE" '[P06]'
  assert_contains "$CAPTURE" '祖先被本地文件／链接阻挡'
  assert_equal "$(<"$REPOSITORY/incoming")" '阻挡目录的本地文件'
  assert_equal "$(git -C "$REPOSITORY" rev-parse HEAD)" "$original"
  assert_equal "$(git --git-dir="$REMOTE_BARE" rev-parse main)" "$remote_before"
  [[ ! -d "$REPOSITORY/incoming" && ! -f "$REPOSITORY/.git/MERGE_HEAD" ]]
}
# 新增路径祖先是 ignored 软链时，不沿链接写入工作树外部。
test_incoming_ancestor_symlink() {
  new_fixture
  add_commit "$REPOSITORY" .gitignore incoming
  git -C "$REPOSITORY" push -q origin main
  git -C "$PEER" pull -q --ff-only
  add_commit "$REPOSITORY" local.txt divergent-local
  local outside="$CASE_DIR/工作树外目录"
  mkdir -p "$outside"
  ln -s "$outside" "$REPOSITORY/incoming"
  mkdir -p "$PEER/incoming"
  print -r -- '不允许写到链接目标' > "$PEER/incoming/nested.txt"
  git -C "$PEER" add -f incoming/nested.txt
  git -C "$PEER" commit -qm incoming-symlink-collision
  git -C "$PEER" push -q origin main
  local original="$(git -C "$REPOSITORY" rev-parse HEAD)"
  local remote_before="$(git --git-dir="$REMOTE_BARE" rev-parse main)"
  run_subject failure --yes "$REPOSITORY" origin main
  assert_contains "$CAPTURE" '[P06]'
  assert_contains "$CAPTURE" '祖先被本地文件／链接阻挡'
  [[ -L "$REPOSITORY/incoming" ]]
  assert_equal "$(readlink "$REPOSITORY/incoming")" "$outside"
  [[ ! -e "$outside/nested.txt" && ! -f "$REPOSITORY/.git/MERGE_HEAD" ]]
  assert_equal "$(git -C "$REPOSITORY" rev-parse HEAD)" "$original"
  assert_equal "$(git --git-dir="$REMOTE_BARE" rev-parse main)" "$remote_before"
}
# 子模块 ignore=all 不能隐藏真实未提交内容。
test_hidden_submodule_changes() {
  new_fixture
  local module="$CASE_DIR/子仓来源"
  init_repository "$module"
  add_commit "$module" tracked.txt module
  git -C "$REPOSITORY" -c protocol.file.allow=always submodule add -q "$module" child
  git -C "$REPOSITORY" commit -qm submodule
  git -C "$REPOSITORY" config submodule.child.ignore all
  print -r -- unsaved >> "$REPOSITORY/child/tracked.txt"
  local original="$(git -C "$REPOSITORY" rev-parse HEAD)"
  run_subject failure --yes "$REPOSITORY" origin main
  assert_contains "$CAPTURE" '[P06]'
  assert_equal "$(git -C "$REPOSITORY" rev-parse HEAD)" "$original"
  assert_contains "$(<"$REPOSITORY/child/tracked.txt")" unsaved
}
# status 不可见的 assume-unchanged 与 skip-worktree 内容都保留，不清除索引标志。
test_hidden_index_flags() {
  new_fixture
  add_commit "$REPOSITORY" skip.txt tracked
  git -C "$REPOSITORY" update-index --assume-unchanged base.txt
  git -C "$REPOSITORY" update-index --skip-worktree skip.txt
  print -r -- 'assume 隐藏的真实改动' > "$REPOSITORY/base.txt"
  print -r -- 'skip 隐藏的真实改动' > "$REPOSITORY/skip.txt"
  assert_equal "$(git -C "$REPOSITORY" status --porcelain=v1)" ''
  local index_before="$(shasum -a 256 "$REPOSITORY/.git/index")"
  local flags_before="$(git -C "$REPOSITORY" ls-files -v)"
  local original="$(git -C "$REPOSITORY" rev-parse HEAD)"
  local remote_before="$(git --git-dir="$REMOTE_BARE" rev-parse main)"
  run_subject failure --yes "$REPOSITORY" origin main
  assert_contains "$CAPTURE" '[P06]'
  assert_contains "$CAPTURE" 'skip-worktree／assume-unchanged'
  assert_equal "$(<"$REPOSITORY/base.txt")" 'assume 隐藏的真实改动'
  assert_equal "$(<"$REPOSITORY/skip.txt")" 'skip 隐藏的真实改动'
  assert_equal "$(git -C "$REPOSITORY" ls-files -v)" "$flags_before"
  assert_equal "$(shasum -a 256 "$REPOSITORY/.git/index")" "$index_before"
  assert_equal "$(git -C "$REPOSITORY" rev-parse HEAD)" "$original"
  assert_equal "$(git --git-dir="$REMOTE_BARE" rev-parse main)" "$remote_before"
}
# pre-push 前出现另一条真实远端提交后有限重试并保留双方历史。
test_remote_race() {
  new_fixture
  add_commit "$REPOSITORY" local.txt local
  add_commit "$PEER" remote.txt race
  local remote_oid="$(git -C "$PEER" rev-parse HEAD)"
  local local_oid="$(git -C "$REPOSITORY" rev-parse HEAD)"
  local hooks="$CASE_DIR/本地钩子"
  mkdir -p "$hooks"
  git -C "$REPOSITORY" config core.hooksPath "$hooks"
  printf '%s\n' '#!/bin/zsh' "if [[ ! -e '$CASE_DIR/raced' ]]; then" "  touch '$CASE_DIR/raced'" "  /usr/bin/git -C '$PEER' push -q origin main || exit 1" 'fi' > "$hooks/pre-push"
  chmod u+x "$hooks/pre-push"
  run_subject success --yes "$REPOSITORY" origin main
  assert_synced
  assert_contains "$CAPTURE" '第 2/3 轮'
  git -C "$REPOSITORY" merge-base --is-ancestor "$local_oid" HEAD
  git -C "$REPOSITORY" merge-base --is-ancestor "$remote_oid" HEAD
}
# 模拟服务端已接收而应答丢失；真实核验一致即可结束，不重推。
test_lost_acknowledgement() {
  new_fixture
  add_commit "$REPOSITORY" local.txt local
  local wrapper="$CASE_DIR/Bin"
  mkdir -p "$wrapper"
  printf '%s\n' '#!/bin/zsh' 'is_push=0' 'for argument in "$@"; do [[ "$argument" != push ]] || is_push=1; done' '/usr/bin/git "$@"' 'result=$?' 'if (( is_push && result == 0 )); then' '  print -u2 -r -- "Connection reset by peer (fixture acknowledgement lost)"' '  exit 1' 'fi' 'exit "$result"' > "$wrapper/git"
  chmod u+x "$wrapper/git"
  local original_path="$PATH"
  export PATH="$wrapper:$PATH"
  run_subject success --yes "$REPOSITORY" origin main
  export PATH="$original_path"
  assert_synced
  assert_contains "$CAPTURE" 'acknowledgement lost'
  [[ "$CAPTURE" != *'第 2/3 轮'* ]]
}
# 索引读取失败不能被空 stdout 误判为干净而推送。
test_corrupt_index() {
  new_fixture
  add_commit "$REPOSITORY" local.txt local
  local before="$(git --git-dir="$REMOTE_BARE" rev-parse main)"
  print -r -- 'fixture-invalid-index' > "$REPOSITORY/.git/index"
  local index_before="$(shasum -a 256 "$REPOSITORY/.git/index")"
  run_subject failure --yes "$REPOSITORY" origin main
  assert_equal "$(git --git-dir="$REMOTE_BARE" rev-parse main)" "$before"
  assert_equal "$(shasum -a 256 "$REPOSITORY/.git/index")" "$index_before"
}
# 未完成操作不能被第二次修复流程覆盖。
test_unfinished_operation() {
  new_fixture
  local original="$(git -C "$REPOSITORY" rev-parse HEAD)"
  print -r -- "$original" > "$REPOSITORY/.git/CHERRY_PICK_HEAD"
  run_subject failure --yes "$REPOSITORY" origin main
  assert_contains "$CAPTURE" '[P04]'
  assert_equal "$(<"$REPOSITORY/.git/CHERRY_PICK_HEAD")" "$original"
}
# bare 仓库不含工作树，不由当前动作自动接管。
test_bare_repository() {
  git init -q --bare --initial-branch=main "$CASE_DIR/bare.git"
  run_subject failure --yes "$CASE_DIR/bare.git" origin main
  assert_contains "$CAPTURE" '[P01]'
}
# 多推送 URL 必须停止，不能只验证其中一个。
test_multiple_pushurls() {
  new_fixture
  git -C "$REPOSITORY" config --add remote.origin.pushurl "$REMOTE_BARE"
  git -C "$REPOSITORY" config --add remote.origin.pushurl "$CASE_DIR/another.git"
  run_subject failure --yes "$REPOSITORY" origin main
  assert_contains "$CAPTURE" '[P08] 多个 URL'
}
# 镜像远端不会因显式目标而被当作普通分支接管。
test_mirror_remote() {
  new_fixture
  git -C "$REPOSITORY" config remote.origin.mirror true
  run_subject failure --yes "$REPOSITORY" origin main
  assert_contains "$CAPTURE" '[P08] mirror'
}
# 强制 refspec 无显式安全目标时拒绝自动推导。
test_forced_refspec() {
  new_fixture
  git -C "$REPOSITORY" config remote.origin.push '+refs/heads/main:refs/heads/main'
  run_subject failure --yes "$REPOSITORY" origin
  assert_contains "$CAPTURE" '强制／通配／隐式 refspec'
}
# 用户配置 followTags=true 也只能更新明确选定的分支。
test_followtags_disabled() {
  new_fixture
  add_commit "$REPOSITORY" local.txt local
  git -C "$REPOSITORY" tag -a fixture-release -m fixture-release
  git -C "$REPOSITORY" config push.followTags true
  run_subject success --yes "$REPOSITORY" origin main
  assert_synced
  assert_equal "$(git --git-dir="$REMOTE_BARE" for-each-ref --format='%(refname)' refs/tags)" ''
}
# 仅加载生产脱敏函数，URL 中认证、查询和 ANSI 均不得泄漏。
test_redaction() {
  sed '$d' "$SUBJECT" > "$CASE_DIR/functions.zsh"
  local result
  result="$(/bin/zsh -c 'source "$1"; print -r -- "https://user:supersecret@example.invalid/repo.git?token=hidden" | redact_stream' -- "$CASE_DIR/functions.zsh")"
  assert_contains "$result" 'https://[REDACTED]@example.invalid/repo.git?[REDACTED]'
  [[ "$result" != *supersecret* && "$result" != *hidden* ]]
  result="$(/bin/zsh -c 'source "$1"; print -r -- "Authorization: Bearer very-secret-value" | redact_stream' -- "$CASE_DIR/functions.zsh")"
  [[ "$result" != *very-secret-value* ]]
}
# 运行全部真实入口回归并汇总结果。
run_suite() {
  run_case '本地领先普通推送与本地分支集合不变' test_ahead
  run_case '仅落后真实快进' test_behind
  run_case '分叉合并保留双方祖先' test_diverged
  run_case '本地文件迁入同名目录与远端无关修改可合并' test_diverged_local_file_to_directory
  run_case '冲突保留索引和合并现场' test_conflict
  run_case '未提交内容及索引受保护' test_dirty
  run_case '游离 HEAD 停止且不创建分支' test_detached
  run_case '未出生分支停止' test_unborn
  run_case '无共同历史停止' test_unrelated
  run_case '空远端显式目标仅创建一个分支' test_empty_remote
  run_case '多远端歧义不由 --yes 猜测' test_ambiguous_remote
  run_case '单远端上游缺失自动确定同名目标' test_upstream_missing
  run_case 'pushurl 不同不合并错误 fetch 端' test_pushurl
  run_case '只诊断不改索引／配置／引用／正文' test_diagnose
  run_case '锁原样保留' test_lock
  run_case '服务端保护规则拒绝不绕过 hook' test_hook_rejection
  run_case 'ignored 同路径正文不可被合并覆盖' test_ignored_collision
  run_case 'ort 分叉合并保留 ignored 同名文件' test_diverged_ignored_collision
  run_case '新增路径祖先普通文件保护' test_incoming_ancestor_file
  run_case '新增路径祖先软链及工作树外目录保护' test_incoming_ancestor_symlink
  run_case '子模块 ignore=all 不隐藏未提交内容' test_hidden_submodule_changes
  run_case '索引隐藏标志及正文保持不变' test_hidden_index_flags
  run_case '远端并发更新后有限重试并保留双方历史' test_remote_race
  run_case '已接收但应答丢失先核验不重复推送' test_lost_acknowledgement
  run_case '损坏索引停止且不推送' test_corrupt_index
  run_case '未完成操作现场保留' test_unfinished_operation
  run_case 'bare 仓库停止' test_bare_repository
  run_case '多个推送 URL 停止' test_multiple_pushurls
  run_case '镜像远端停止' test_mirror_remote
  run_case '强制 refspec 不自动推导' test_forced_refspec
  run_case 'followTags 配置不导致额外标签推送' test_followtags_disabled
  run_case 'URL 凭据与查询脱敏' test_redaction
}
# 保留所有失败夹具以供定位，不清理证据。
report_results() {
  print -r -- "完成：$PASSED 通过，$FAILED 失败；证据：$TEST_ROOT"
  (( FAILED == 0 ))
}
# 编排隔离环境、真实 Git 场景与结果输出。
main() {
  prepare_environment "$@" # 隔离用户配置和网络，只使用本地 file 远端。
  run_suite # 执行完整入口的成功与停止边界回归。
  report_results # 汇总真实结果并传播失败状态。
}
main "$@"
