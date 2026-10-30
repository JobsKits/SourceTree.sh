#!/bin/zsh
# 脚本自述：
# - 核心用途：验证逐层推送的远程别名、分支映射、失败停止和原有分支保护。
# - 影响范围：只在本次 /tmp 目录创建仓库与本地 bare 远端；禁止 SSH / HTTP 传输。
# - 运行提示：默认验证相邻生产脚本，也可传入另一份生产脚本的绝对路径。

TEST_SOURCE_PATH="${0:A}"
TEST_SUBJECT=""
TEST_ROOT=""
TEST_CASE_DIR=""
TEST_REPOSITORY=""
TEST_HUB_BARE=""
TEST_GITEE_BARE=""
TEST_POLICY=0
TEST_PASSED=0
TEST_FAILED=0
TEST_CASE_NUMBER=0
TEST_HUB_URL='git@github.com:jobs-fixture/repository.git'
TEST_GITEE_URL='git@gitee.com:jobs-fixture/repository.git'

# 所有测试都复用真实生产函数，只移除唯一的最终入口调用。
prepare_test_workspace() {
  emulate -R zsh
  setopt NO_NOMATCH PIPE_FAIL
  TEST_SUBJECT="${1:-${TEST_SOURCE_PATH:h:h}/【MacOS@SourceTree】🚀逐层空白提交并Push.command/【MacOS@SourceTree】🚀逐层空白提交并Push.command}"
  [[ -f "$TEST_SUBJECT" && "$(/usr/bin/tail -n 1 "$TEST_SUBJECT")" == 'main "$@"' ]] || {
    print -u2 -r -- "生产脚本不存在或入口结构已变化：${TEST_SUBJECT}"
    return 1
  }
  TEST_ROOT="$(/usr/bin/mktemp -d /tmp/jobs-layered-push-aliases.XXXXXX)" || return 1
  /usr/bin/sed '$d' "$TEST_SUBJECT" > "$TEST_ROOT/production-functions.zsh" || return 1
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_TERMINAL_PROMPT=0 GIT_ALLOW_PROTOCOL=file GIT_SSH_COMMAND=/usr/bin/false GIT_PROXY_COMMAND=/usr/bin/false
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX GIT_NAMESPACE GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
  source "$TEST_ROOT/production-functions.zsh" || return 1
}

# 生产逻辑继续看见官方主机；只有真实传输参数映射到本次本地远端。
git() {
  local -a arguments=("$@")
  local index=0 transport=0 repository=""
  [[ "${arguments[1]:-}" != -C ]] || repository="${arguments[2]}"
  if (( ${arguments[(Ie)fetch]} || ${arguments[(Ie)push]} || ${arguments[(Ie)ls-remote]} )); then
    transport=1
  fi
  if [[ "$transport" == 1 ]]; then
    print -r -- "${(j: :)arguments}" >> "$TEST_CASE_DIR/transport.log"
    for ((index = 1; index <= ${#arguments}; index++)); do
      case "${arguments[index]}" in
        "$TEST_HUB_URL") arguments[index]="$TEST_HUB_BARE" ;;
        "$TEST_GITEE_URL") arguments[index]="$TEST_GITEE_BARE" ;;
      esac
    done
    # 游离恢复的生产路径使用 remote 名称，Git 自己解析其 URL。
    for ((index = 1; index <= ${#arguments}; index++)); do
      if [[ -n "$repository" && "${arguments[index]}" != -* ]]; then
        local configured_url="$(/usr/bin/git -C "$repository" config --get "remote.${arguments[index]}.url" 2>/dev/null || true)"
        case "$configured_url" in
          "$TEST_HUB_URL") arguments[index]="$TEST_HUB_BARE" ;;
          "$TEST_GITEE_URL") arguments[index]="$TEST_GITEE_BARE" ;;
        esac
      fi
    done
  fi
  /usr/bin/git "${arguments[@]}"
}

assert_equal() {
  [[ "$1" == "$2" ]] || { print -u2 -r -- "期望：$2；实际：$1"; return 1; }
}

assert_failure() {
  if "$@"; then
    print -u2 -r -- "预期停止，但实际成功：$*"
    return 1
  fi
}

# 每例独立子进程隔离生产数组、替身函数和临时配置。
run_case() {
  local title="$1" callback="$2"
  TEST_CASE_NUMBER=$((TEST_CASE_NUMBER + 1))
  TEST_CASE_DIR="$TEST_ROOT/case-${TEST_CASE_NUMBER}"
  /bin/mkdir -p "$TEST_CASE_DIR" || return 1
  if ( "$callback" ) > "$TEST_CASE_DIR/result.log" 2>&1; then
    TEST_PASSED=$((TEST_PASSED + 1))
    print -r -- "PASS  ${title}"
  else
    TEST_FAILED=$((TEST_FAILED + 1))
    print -r -- "FAIL  ${title}；日志：${TEST_CASE_DIR}/result.log"
    /usr/bin/tail -n 16 "$TEST_CASE_DIR/result.log"
  fi
}

new_repository() {
  TEST_REPOSITORY="$TEST_CASE_DIR/工作仓库 空格"
  TEST_HUB_BARE="$TEST_CASE_DIR/github.git"
  TEST_GITEE_BARE="$TEST_CASE_DIR/gitee.git"
  TEST_POLICY=0
  LOG_FILE="$TEST_CASE_DIR/production.log"
  PLAIN_OUTPUT=1
  /usr/bin/git -c init.templateDir= init -q --initial-branch=main "$TEST_REPOSITORY" || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config user.name Fixture || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config user.email fixture@example.invalid || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config commit.gpgSign false || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" commit --allow-empty -qm fixture || return 1
}

# 临时路径不会落入真实业务根，仅替换策略范围判定，分支解析仍用生产实现。
enable_fixed_policy() {
  TEST_POLICY=1
  uses_gitee_branch_policy() { [[ "$TEST_POLICY" == 1 ]]; }
}

add_two_remotes() {
  /usr/bin/git -C "$TEST_REPOSITORY" remote add "${1:-Github}" "$TEST_HUB_URL" || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" remote add "${2:-码云}" "$TEST_GITEE_URL"
}

assert_push_mapping() {
  local expected_hub="$1" expected_gitee="$2" index=0 hub_seen=0 gitee_seen=0 target=""
  for target in "${RESOLVED_PUSH_TARGETS[@]}"; do
    index=$((index + 1))
    case "$target" in
      "$TEST_HUB_URL") assert_equal "${RESOLVED_PUSH_REFS[index]}" "refs/heads/${expected_hub}" || return 1; hub_seen=1 ;;
      "$TEST_GITEE_URL") assert_equal "${RESOLVED_PUSH_REFS[index]}" "refs/heads/${expected_gitee}" || return 1; gitee_seen=1 ;;
      *) print -u2 -r -- "意外推送地址：${target}"; return 1 ;;
    esac
  done
  [[ "$hub_seen" == 1 && "$gitee_seen" == 1 && "${#RESOLVED_PUSH_TARGETS}" == 2 ]]
}

case_renamed_fallback() {
  new_repository && add_two_remotes || return 1
  assert_equal "$(resolve_fallback_remote "$TEST_REPOSITORY")" Github || return 1
  preflight_repository "$TEST_REPOSITORY" || return 1
  [[ -z "$(/usr/bin/git -C "$TEST_REPOSITORY" config --get branch.main.remote || true)" ]]
}

case_legacy_fallback() {
  new_repository && add_two_remotes origin gitee || return 1
  assert_equal "$(resolve_fallback_remote "$TEST_REPOSITORY")" origin
}

case_arbitrary_aliases() {
  new_repository && add_two_remotes 主线路 国内镜像 || return 1
  assert_equal "$(resolve_fallback_remote "$TEST_REPOSITORY")" 主线路 || return 1
  resolve_push_targets "$TEST_REPOSITORY" 主线路 && assert_push_mapping main main
}

case_ambiguous_github() {
  new_repository && add_two_remotes || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" remote add second-hub 'https://github.com/other/repository.git' || return 1
  assert_failure resolve_fallback_remote "$TEST_REPOSITORY" && assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" branch --format='%(refname:short)')" main
}

case_single_unknown() {
  new_repository || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" remote add 发布 'ssh://git@internal.example/group/repository.git' || return 1
  assert_equal "$(resolve_fallback_remote "$TEST_REPOSITORY")" 发布
}

case_spoofed_network_host() {
  assert_failure remote_hosting_platform Github 'https://github.com.example/group/repo.git' || return 1
  assert_failure remote_hosting_platform Github 'https://github.com@unrelated.example/group/repo.git' || return 1
  assert_failure remote_hosting_platform 码云 'ssh://git@unrelated.example:2222/group/repo.git' || return 1
  assert_failure remote_hosting_platform Github 'git@notgithub.com:group/repo.git'
}

case_official_hosts() {
  assert_equal "$(remote_hosting_platform 任意名 'ssh://git@github.com:2222/group/repo.git')" github || return 1
  assert_equal "$(remote_hosting_platform 任意名 'https://name@gitee.com:8443/group/repo.git')" gitee || return 1
  assert_equal "$(remote_hosting_platform 任意名 'git@github.com:group/repo.git')" github || return 1
  assert_equal "$(remote_hosting_platform Github "$TEST_CASE_DIR/local.git")" github
}

case_fixed_default() {
  new_repository && add_two_remotes || return 1
  enable_fixed_policy
  resolve_push_targets "$TEST_REPOSITORY" Github && assert_push_mapping main gitee
}

case_actual_alias_override() {
  new_repository && add_two_remotes || return 1
  enable_fixed_policy
  /usr/bin/git -C "$TEST_REPOSITORY" config remote.码云.jobsPushBranch main || return 1
  resolve_push_targets "$TEST_REPOSITORY" Github && assert_push_mapping main main
}

case_legacy_override() {
  new_repository && add_two_remotes origin gitee || return 1
  enable_fixed_policy
  /usr/bin/git -C "$TEST_REPOSITORY" config remote.gitee.jobsPushBranch release/stable || return 1
  resolve_push_targets "$TEST_REPOSITORY" origin && assert_push_mapping main release/stable
}

case_empty_and_global_override() {
  new_repository && add_two_remotes || return 1
  enable_fixed_policy
  /usr/bin/git config --file "$TEST_CASE_DIR/global.gitconfig" remote.码云.jobsPushBranch main || return 1
  export GIT_CONFIG_GLOBAL="$TEST_CASE_DIR/global.gitconfig"
  resolve_push_targets "$TEST_REPOSITORY" Github && assert_push_mapping main gitee || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config remote.码云.jobsPushBranch '' || return 1
  resolve_push_targets "$TEST_REPOSITORY" Github && assert_push_mapping main gitee
}

case_orphaned_old_key() {
  new_repository && add_two_remotes || return 1
  enable_fixed_policy
  /usr/bin/git -C "$TEST_REPOSITORY" config remote.gitee.jobsPushBranch main || return 1
  resolve_push_targets "$TEST_REPOSITORY" Github && assert_push_mapping main gitee
}

case_invalid_branch() {
  new_repository && add_two_remotes || return 1
  enable_fixed_policy
  /usr/bin/git -C "$TEST_REPOSITORY" config remote.码云.jobsPushBranch 'bad..branch' || return 1
  assert_failure resolve_push_targets "$TEST_REPOSITORY" Github
}

case_multiple_override_values() {
  new_repository && add_two_remotes || return 1
  enable_fixed_policy
  /usr/bin/git -C "$TEST_REPOSITORY" config --add remote.码云.jobsPushBranch main || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config --add remote.码云.jobsPushBranch release/stable || return 1
  assert_failure resolve_push_targets "$TEST_REPOSITORY" Github
}

case_conflicting_same_url() {
  new_repository && add_two_remotes || return 1
  enable_fixed_policy
  /usr/bin/git -C "$TEST_REPOSITORY" remote add 第二码云 "$TEST_GITEE_URL" || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config remote.码云.jobsPushBranch main || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config remote.第二码云.jobsPushBranch release/stable || return 1
  assert_failure resolve_push_targets "$TEST_REPOSITORY" Github
}

# 两个真实 bare 远端都来自同一个提交，后续整合不使用网络替身返回伪 SHA。
seed_bare_remotes() {
  local gitee_branch="${1:-main}"
  /usr/bin/git -c init.templateDir= init -q --bare --initial-branch=main "$TEST_HUB_BARE" || return 1
  /usr/bin/git -c init.templateDir= init -q --bare --initial-branch="$gitee_branch" "$TEST_GITEE_BARE" || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" push -q "$TEST_HUB_BARE" HEAD:refs/heads/main || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" push -q "$TEST_GITEE_BARE" "HEAD:refs/heads/${gitee_branch}"
}

advance_bare_remote() {
  local bare="$1" filename="$2" branch="${3:-main}" writer=""
  writer="$TEST_CASE_DIR/writer-${filename}"
  /usr/bin/git -c init.templateDir= clone -q --branch "$branch" "$bare" "$writer" || return 1
  /usr/bin/git -C "$writer" config user.name Fixture || return 1
  /usr/bin/git -C "$writer" config user.email fixture@example.invalid || return 1
  print -r -- "$filename" > "$writer/$filename" || return 1
  /usr/bin/git -C "$writer" add -- "$filename" || return 1
  /usr/bin/git -C "$writer" -c commit.gpgSign=false commit -qm "$filename" || return 1
  /usr/bin/git -C "$writer" push -q origin "HEAD:refs/heads/${branch}"
}

run_real_pipeline() {
  preflight_repository "$TEST_REPOSITORY" || return 1
  synchronize_repository_upstream "$TEST_REPOSITORY" || return 1
  commit_repository_changes "$TEST_REPOSITORY" || return 1
  integrate_repository_upstream "$TEST_REPOSITORY" || return 1
  push_repository "$TEST_REPOSITORY"
}

assert_two_bare_tips() {
  local gitee_branch="$1" head="$(/usr/bin/git -C "$TEST_REPOSITORY" rev-parse HEAD)"
  assert_equal "$(/usr/bin/git --git-dir="$TEST_HUB_BARE" rev-parse refs/heads/main)" "$head" || return 1
  assert_equal "$(/usr/bin/git --git-dir="$TEST_GITEE_BARE" rev-parse "refs/heads/${gitee_branch}")" "$head" || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" symbolic-ref --short HEAD)" main || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" for-each-ref --format='%(refname:short)' refs/heads/)" main || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" config --get branch.main.remote)" Github || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" config --get branch.main.merge)" refs/heads/main
}

case_real_renamed_merge_and_push() {
  new_repository && add_two_remotes && seed_bare_remotes main || return 1
  advance_bare_remote "$TEST_HUB_BARE" github-change || return 1
  advance_bare_remote "$TEST_GITEE_BARE" gitee-change || return 1
  print -r -- local-change > "$TEST_REPOSITORY/local-change" || return 1
  run_real_pipeline && assert_two_bare_tips main || return 1
  [[ -f "$TEST_REPOSITORY/github-change" && -f "$TEST_REPOSITORY/gitee-change" && -f "$TEST_REPOSITORY/local-change" ]]
}

case_real_fixed_target() {
  new_repository && add_two_remotes && seed_bare_remotes gitee || return 1
  enable_fixed_policy
  print -r -- changed > "$TEST_REPOSITORY/changed" || return 1
  run_real_pipeline && assert_two_bare_tips gitee || return 1
  assert_failure /usr/bin/git --git-dir="$TEST_GITEE_BARE" show-ref --verify --quiet refs/heads/main
}

case_real_main_override() {
  new_repository && add_two_remotes && seed_bare_remotes main || return 1
  enable_fixed_policy
  /usr/bin/git -C "$TEST_REPOSITORY" config remote.码云.jobsPushBranch main || return 1
  print -r -- changed > "$TEST_REPOSITORY/changed" || return 1
  run_real_pipeline && assert_two_bare_tips main || return 1
  assert_failure /usr/bin/git --git-dir="$TEST_GITEE_BARE" show-ref --verify --quiet refs/heads/gitee
}

case_explicit_upstream_stays() {
  new_repository && add_two_remotes && seed_bare_remotes main || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config branch.main.remote 码云 || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" config branch.main.merge refs/heads/main || return 1
  print -r -- changed > "$TEST_REPOSITORY/changed" || return 1
  run_real_pipeline || return 1
  local head="$(/usr/bin/git -C "$TEST_REPOSITORY" rev-parse HEAD)"
  assert_equal "$(/usr/bin/git --git-dir="$TEST_HUB_BARE" rev-parse refs/heads/main)" "$head" || return 1
  assert_equal "$(/usr/bin/git --git-dir="$TEST_GITEE_BARE" rev-parse refs/heads/main)" "$head" || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" config --get branch.main.remote)" 码云 || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" for-each-ref --format='%(refname:short)' refs/heads/)" main
}

case_push_rejection_stops_second_line() {
  new_repository && add_two_remotes && seed_bare_remotes main || return 1
  local before="$(/usr/bin/git --git-dir="$TEST_GITEE_BARE" rev-parse refs/heads/main)"
  /bin/mkdir -p "$TEST_HUB_BARE/hooks" || return 1
  print -r -- $'#!/bin/sh\nexit 1' > "$TEST_HUB_BARE/hooks/pre-receive" || return 1
  /bin/chmod u+x "$TEST_HUB_BARE/hooks/pre-receive" || return 1
  print -r -- changed > "$TEST_REPOSITORY/changed" || return 1
  assert_failure run_real_pipeline || return 1
  assert_equal "$(/usr/bin/git --git-dir="$TEST_GITEE_BARE" rev-parse refs/heads/main)" "$before" || return 1
  [[ "$(/usr/bin/grep -c ' push ' "$TEST_CASE_DIR/transport.log")" == 1 ]]
}

case_detached_reuses_existing_branch() {
  new_repository && add_two_remotes && seed_bare_remotes main || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" checkout -q --detach || return 1
  REPOSITORY_CHAIN=("$TEST_REPOSITORY")
  prepare_detached_repositories || return 1
  assert_equal "${DETACHED_BRANCHES[$TEST_REPOSITORY]}" main || return 1
  assert_equal "${DETACHED_REMOTES[$TEST_REPOSITORY]}" Github || return 1
  restore_detached_repositories <<< YES || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" symbolic-ref --short HEAD)" main || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" for-each-ref --format='%(refname:short)' refs/heads/)" main
}

case_detached_missing_local_stops() {
  new_repository && add_two_remotes && seed_bare_remotes main || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" branch -m work || return 1
  /usr/bin/git -C "$TEST_REPOSITORY" checkout -q --detach || return 1
  REPOSITORY_CHAIN=("$TEST_REPOSITORY")
  print -r -- keep > "$TEST_REPOSITORY/untracked-must-stay" || return 1
  assert_failure prepare_detached_repositories || return 1
  [[ -f "$TEST_REPOSITORY/untracked-must-stay" ]] || return 1
  assert_equal "$(/usr/bin/git -C "$TEST_REPOSITORY" for-each-ref --format='%(refname:short)' refs/heads/)" work
}

case_snapshot_boundary() {
  new_repository || return 1
  REPOSITORY_CHAIN=("${HOME}/Documents/Github/JobsOCBaseConfigDemo@ByPods")
  assert_failure check_snapshot_repository_boundary || return 1
  [[ ! -f "$TEST_CASE_DIR/transport.log" ]]
}

# 成功时只删除本次 mktemp 目录；失败时保留证据供修复。
finish_tests() {
  print -r -- "结果：${TEST_PASSED} 通过，${TEST_FAILED} 失败。"
  if [[ "$TEST_FAILED" == 0 ]]; then
    /bin/rm -r -- "$TEST_ROOT" || return 1
    return 0
  fi
  print -r -- "失败证据保留于：${TEST_ROOT}"
  return 1
}

main() {
  print -r -- '逐层推送别名隔离回归：仅 /tmp 本地 Git；SSH / HTTP 均禁止。' # 展示实际验证范围。
  prepare_test_workspace "$@" || return 1 # 加载真实生产函数并隔离 Git 环境。
  run_case 'Github + 码云在无 upstream 时可预检' case_renamed_fallback # 验证新名字自动选择。
  run_case 'origin + gitee继续兼容' case_legacy_fallback # 保留旧名字行为。
  run_case '任意别名按官方主机识别' case_arbitrary_aliases # 不依赖显示名称。
  run_case '多个GitHub候选停止' case_ambiguous_github # 避免猜测上游。
  run_case '唯一自建服务仍可选择' case_single_unknown # 保留单线路兼容。
  run_case '平台名字不能伪装其它网络主机' case_spoofed_network_host # 核对完整主机边界。
  run_case 'SSH/HTTPS端口及本地别名识别' case_official_hosts # 保留地址形式兼容。
  run_case '改名后固定码云目标仍为gitee' case_fixed_default # 区分别名与目标分支。
  run_case '实际码云别名可覆盖为main' case_actual_alias_override # 验证仓库局部配置。
  run_case '旧gitee键和多层分支继续支持' case_legacy_override # 保留既有覆盖格式。
  run_case '忽略全局覆盖且空值回退' case_empty_and_global_override # 保持配置作用域。
  run_case '不继承已移除别名的孤立覆盖键' case_orphaned_old_key # 避免套用其它线路配置。
  run_case '非法目标分支停止' case_invalid_branch # 防止错误引用写入。
  run_case '多个覆盖值停止' case_multiple_override_values # 拒绝有歧义的配置。
  run_case '同一URL矛盾目标停止' case_conflicting_same_url # 避免重复推送不同目标。
  run_case '真实双端获取整合提交推送核验' case_real_renamed_merge_and_push # 合并双方历史后推同一HEAD。
  run_case '真实固定gitee目标且无额外本地分支' case_real_fixed_target # 保留两端异名映射。
  run_case '真实main覆盖不重建远端gitee' case_real_main_override # 保留账户仓主分支约定。
  run_case '已有显式upstream保持原线路' case_explicit_upstream_stays # 不用GitHub候选覆盖用户配置。
  run_case '第一线路拒绝后停止第二线路' case_push_rejection_stops_second_line # 验证失败传播。
  run_case '游离态复用已有main' case_detached_reuses_existing_branch # 不创建辅助分支。
  run_case '游离态缺失本地分支前置停止' case_detached_missing_local_stops # 不清理尚未授权内容。
  run_case 'OC独立快照门禁保持' case_snapshot_boundary # 避免合并独立历史。
  finish_tests # 汇总结果并清理本次隔离目录。
}

main "$@"
