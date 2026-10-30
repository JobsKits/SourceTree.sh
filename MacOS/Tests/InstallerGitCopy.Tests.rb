# frozen_string_literal: true
# Created by Jobs on 2026年10月29日，星期四。
# 在私有临时目录验证复制、socket 跳过与目标保护，不运行真实安装入口。

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'shellwords'
require 'socket'
require 'tmpdir'

class InstallerGitCopyTests < Minitest::Test
  SCRIPT = File.expand_path('../【MacOS】安装SourceTree自定义菜单.command/【MacOS】安装SourceTree自定义菜单.command', __dir__)

  def setup
    @root = File.realpath(Dir.mktmpdir('st-copy-', '/tmp'))
    @source = File.join(@root, 'SourceTree.command')
    @target = File.join(@root, '目标 空格', 'SourceTree.command')
    @library = File.join(@root, 'installer.zsh')
    @servers = []
    FileUtils.mkdir_p(@source)
    FileUtils.mkdir_p(File.join(@root, 'tmp'))
    File.write(@library, File.read(SCRIPT).sub(/^main "\$@"\s*\z/, ''))
    @env = {
      'HOME' => @root, 'TMPDIR' => File.join(@root, 'tmp'), 'GIT_CONFIG_GLOBAL' => File::NULL, 'GIT_CONFIG_NOSYSTEM' => '1',
      'GIT_CONFIG_COUNT' => '0', 'GIT_OPTIONAL_LOCKS' => '0',
      'GIT_DIR' => nil, 'GIT_WORK_TREE' => nil, 'GIT_INDEX_FILE' => nil,
      'GIT_COMMON_DIR' => nil, 'GIT_OBJECT_DIRECTORY' => nil,
      'GIT_ALTERNATE_OBJECT_DIRECTORIES' => nil
    }
  end

  def teardown
    @servers.each(&:close)
    FileUtils.chmod_R(0o700, @root)
    FileUtils.remove_entry(@root)
  end

  def socket(path)
    FileUtils.mkdir_p(File.dirname(path))
    @servers << UNIXServer.new(path)
  end

  def git(directory, *args)
    out, err, result = Open3.capture3(@env, '/usr/bin/git', '-c', 'core.fsmonitor=false', '-C', directory, *args)
    assert result.success?, out + err
    out.strip
  end

  def repository(external: false)
    metadata = external ? File.join(@root, 'git-storage') : File.join(@source, '.git')
    arguments = ['init', '-q']
    arguments += ['--separate-git-dir', metadata] if external
    git(@source, *arguments)
    File.write(File.join(@source, 'README.md'), "fixture\n")
    git(@source, 'add', 'README.md')
    git(@source, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture')
    git(@source, 'config', '--local', 'core.fsmonitor', 'true')
    git(@source, 'config', '--local', 'core.worktree', @source) if external
    metadata
  end

  def run_functions(body)
    script = <<~ZSH
      source #{@library.shellescape}
      SOURCE_PACKAGE_ROOT=#{@source.shellescape}
      SOURCE_PACKAGE_NAME=SourceTree.command
      DEPLOY_TARGET_PACKAGE=#{@target.shellescape}
      PLAIN_OUTPUT=1
      RUNTIME_INITIALIZED=1
      LOG_FILE=#{File.join(@root, 'copy.log').shellescape}
      : > "$LOG_FILE"
      #{body}
    ZSH
    Open3.capture3(@env, '/bin/zsh', '-f', '-c', script)
  end

  def send_fixture
    run_functions(<<~'ZSH')
      ask_deploy_target_package() { DEPLOYED_PACKAGE_ROOT="$DEPLOY_TARGET_PACKAGE"; }
      confirm_replace_existing_package() { return 0; }
      send_package_to_user_directory
    ZSH
  end

  def test_socket_is_skipped_while_regular_names_links_and_metadata_are_preserved
    socket(File.join(@source, 'fsmonitor--daemon.ipc'))
    File.symlink('fsmonitor--daemon.ipc', File.join(@source, 'socket-link'))
    nested = File.join(@source, "中文 空格\n目录")
    FileUtils.mkdir_p(nested)
    file = File.join(nested, 'fsmonitor--daemon.ipc')
    File.write(file, 'ordinary-file')
    File.chmod(0o751, file)
    File.symlink('fsmonitor--daemon.ipc', File.join(nested, 'symlink'))
    File.link(file, File.join(nested, 'hardlink'))
    _, err, result = Open3.capture3('/usr/bin/xattr', '-w', 'com.jobs.installer-test', 'preserved', file)
    assert result.success?, err

    out, err, result = run_functions('copy_tree_without_runtime_sockets "$SOURCE_PACKAGE_ROOT" "$DEPLOY_TARGET_PACKAGE"')
    assert result.success?, out + err
    refute File.exist?(File.join(@target, 'fsmonitor--daemon.ipc'))
    assert File.socket?(File.join(@source, 'fsmonitor--daemon.ipc'))
    assert_equal 'fsmonitor--daemon.ipc', File.readlink(File.join(@target, 'socket-link'))
    copied = File.join(@target, File.basename(nested), 'fsmonitor--daemon.ipc')
    assert_equal 'ordinary-file', File.read(copied)
    assert_equal 0o751, File.stat(copied).mode & 0o777
    assert_equal 'fsmonitor--daemon.ipc', File.readlink(File.join(File.dirname(copied), 'symlink'))
    assert_equal File.stat(copied).ino, File.stat(File.join(File.dirname(copied), 'hardlink')).ino
    value, err, result = Open3.capture3('/usr/bin/xattr', '-p', 'com.jobs.installer-test', copied)
    assert result.success?, err
    assert_equal 'preserved', value.strip
    log = File.read(File.join(@root, 'copy.log'))
    assert_includes log, '跳过运行时 socket：'
    refute_match(/cannot archive sockets|Could not pack extended attributes/, out + err + log)
    assert_empty Dir.children(File.join(@root, 'tmp'))
  end

  def test_standalone_git_directory_with_socket_is_copied_twice_without_failure
    metadata = repository
    socket(File.join(metadata, 'fsmonitor--daemon.ipc'))
    config_before = File.binread(File.join(metadata, 'config'))
    index_before = File.binread(File.join(metadata, 'index'))
    out, err, result = run_functions(<<~'ZSH')
      copy_source_worktree_to_temp "$DEPLOY_TARGET_PACKAGE"
      copy_git_metadata_to_temp "$DEPLOY_TARGET_PACKAGE"
    ZSH
    assert result.success?, out + err
    assert_equal git(@source, 'rev-parse', 'HEAD'), git(@target, 'rev-parse', 'HEAD')
    assert_equal '', git(@target, 'status', '--porcelain')
    assert File.socket?(File.join(metadata, 'fsmonitor--daemon.ipc'))
    refute File.exist?(File.join(@target, '.git', 'fsmonitor--daemon.ipc'))
    assert_equal config_before, File.binread(File.join(metadata, 'config'))
    assert_equal index_before, File.binread(File.join(metadata, 'index'))
  end

  def test_external_git_socket_full_send_preserves_source_and_backs_up_old_target
    metadata = repository(external: true)
    socket(File.join(metadata, 'fsmonitor--daemon.ipc'))
    FileUtils.mkdir_p(@target)
    File.write(File.join(@target, 'old-target'), 'preserve')
    config_before = File.binread(File.join(metadata, 'config'))
    index_before = File.binread(File.join(metadata, 'index'))

    out, err, result = send_fixture
    assert result.success?, out + err
    assert File.directory?(File.join(@target, '.git'))
    assert_equal git(@source, 'rev-parse', 'HEAD'), git(@target, 'rev-parse', 'HEAD')
    assert_equal File.realpath(@target), git(@target, 'rev-parse', '--show-toplevel')
    git(@target, 'fsck', '--no-reflogs')
    assert_equal '', git(@target, 'status', '--porcelain')
    assert File.socket?(File.join(metadata, 'fsmonitor--daemon.ipc'))
    assert_equal config_before, File.binread(File.join(metadata, 'config'))
    assert_equal index_before, File.binread(File.join(metadata, 'index'))
    backups = Dir.glob(@target + '.bak.*')
    assert_equal 1, backups.length
    assert_equal 'preserve', File.read(File.join(backups.first, 'old-target'))
    assert_empty Dir.glob(File.join(File.dirname(@target), '.SourceTree.command.tmp.*'))
  end

  def test_unreadable_regular_file_fails_and_keeps_existing_target
    file = File.join(@source, 'unreadable')
    File.write(file, 'required-source')
    File.chmod(0, file)
    FileUtils.mkdir_p(@target)
    File.write(File.join(@target, 'old-target'), 'preserve')
    out, err, result = send_fixture
    refute result.success?, out + err
    assert_equal 'preserve', File.read(File.join(@target, 'old-target'))
    assert_empty Dir.glob(@target + '.bak.*')
    assert_empty Dir.glob(File.join(File.dirname(@target), '.SourceTree.command.tmp.*'))
    assert_includes File.read(File.join(@root, 'copy.log')), 'Permission denied'
  end

  def test_extraction_failure_is_reported_by_the_copy_pipeline
    File.write(File.join(@source, 'file'), 'required-source')
    FileUtils.mkdir_p(@target)
    File.chmod(0o500, @target)
    out, err, result = run_functions('copy_tree_without_runtime_sockets "$SOURCE_PACKAGE_ROOT" "$DEPLOY_TARGET_PACKAGE"')
    refute result.success?, out + err
    assert_includes File.read(File.join(@root, 'copy.log')), 'Permission denied'
  end

  def test_plain_tree_is_quiet_and_copy_diagnostics_are_cleaned_up
    File.write(File.join(@source, 'file'), 'ordinary-source')
    out, err, result = run_functions(<<~'ZSH')
      copy_tree_without_runtime_sockets "$SOURCE_PACKAGE_ROOT" "$DEPLOY_TARGET_PACKAGE"
      copy_result=$?
      [[ "$copy_result" == 0 ]] || exit "$copy_result"
      success_echo "复制完成"
    ZSH
    assert result.success?, out + err
    assert_equal "✔ 复制完成\n", out
    assert_empty err
    assert_equal 'ordinary-source', File.read(File.join(@target, 'file'))
    assert_empty Dir.children(File.join(@root, 'tmp'))
  end

  def test_diagnostics_without_final_newline_cannot_join_success_output
    diagnostic = File.join(@root, 'diagnostic.log')
    File.write(diagnostic, 'tool diagnostic without final newline')
    out, err, result = run_functions(<<~ZSH)
      report_copy_diagnostics 0 #{diagnostic.shellescape}
      success_echo "复制完成"
    ZSH
    assert result.success?, out + err
    assert_equal "⚠ tool diagnostic without final newline\n✔ 复制完成\n", out
    assert_equal out, File.read(File.join(@root, 'copy.log'))
  end

  def test_unreadable_directory_stops_before_copying_a_partial_file_list
    directory = File.join(@source, 'private')
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, 'required-file'), 'must-not-be-lost')
    File.chmod(0, directory)
    FileUtils.mkdir_p(@target)
    File.write(File.join(@target, 'old-target'), 'preserve')
    out, err, result = send_fixture
    refute result.success?, out + err
    assert_equal 'preserve', File.read(File.join(@target, 'old-target'))
    assert_empty Dir.glob(@target + '.bak.*')
    assert_empty Dir.children(File.join(@root, 'tmp'))
  end
end
