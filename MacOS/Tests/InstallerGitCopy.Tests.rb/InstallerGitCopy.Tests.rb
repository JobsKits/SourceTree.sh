# frozen_string_literal: true
# Created by Jobs on 2026年10月29日，星期四。
# 在私有临时目录验证复制、socket 跳过与目标保护，不运行真实安装入口。

# JOBS_TERMINAL_STYLE_GUARD_V1_BEGIN
if $PROGRAM_NAME == __FILE__
  # 直接运行时由 fork 父进程保护配色；子进程继续原文件，不重放 Ruby 参数和预载模块。
  def jobs_terminal_style_bootstrap_v1
    return unless $PROGRAM_NAME == __FILE__
    plain = lambda do
      ENV.update('PLAIN_OUTPUT' => '1', 'NO_COLOR' => '1', 'FORCE_COLOR' => '0',
                 'CLICOLOR' => '0', 'ANSI_COLORS_DISABLED' => '1', 'npm_config_color' => 'false')
    end
    notify = lambda do |message|
      encoding = $stderr.external_encoding || Encoding::UTF_8
      $stderr.write((message + "\n").encode(encoding, invalid: :replace, undef: :replace))
    end
    return unless $stdin.tty? && $stdout.tty?
    return if ENV.key?('NO_COLOR') || ENV['PLAIN_OUTPUT'] == '1' ||
              ENV['IS_SOURCETREE_RUNTIME'] == '1' ||
              ENV.keys.any? { |key| key.match?(/\A(?:SOURCETREE|SOURCE_TREE)/i) }
    return if ['', 'dumb'].include?(ENV.fetch('TERM', ''))
    if File::ALT_SEPARATOR == '\\' || !Process.respond_to?(:fork) ||
       Thread.list.length > 1 || ENV['TMUX'] || ENV['STY']
      plain.call
      return
    end
    tty_name = IO.popen(['tty'], err: File::NULL, &:read).strip
    groups = IO.popen(['ps', '-o', 'pgid=', '-o', 'tpgid=', '-p', Process.pid.to_s], err: File::NULL, &:read).split
    unless tty_name.match?(%r{\A/dev/[A-Za-z0-9_./-]+\z}) && groups.length == 2 &&
           groups.all? { |group| group.match?(/\A\d+\z/) } && groups[0].to_i > 0 && groups[0] == groups[1]
      plain.call
      return
    end
    owner = ENV['JOBS_TERMINAL_STYLE_OWNER']
    if ENV['JOBS_TERMINAL_STYLE_TTY'] == tty_name && owner && owner.match?(/\A\d+\z/)
      begin
        Process.kill(0, owner.to_i)
        return
      rescue Errno::ESRCH, Errno::EPERM
      end
    end
    require 'io/console'
    require 'tmpdir'
    if Thread.list.length > 1
      plain.call
      return
    end
    tty = File.open('/dev/tty', 'r+')
    tty.binmode
    tty.sync = true
    keys = ['10', '11', '12'] + (0..15).map { |index| "4;#{index}" }
    palette = %w[000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee
                 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff]
    targets = { '10' => 'ffffff', '11' => '000000', '12' => 'ffffff' }
    palette.each_with_index { |color, index| targets["4;#{index}"] = color }
    query = lambda do |key|
      tty.write("\e]#{key};?\a")
      bytes = ''.b
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.3
      loop do
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return nil if remaining <= 0 || !IO.select([tty], nil, nil, remaining)
        piece = tty.read_nonblock(256, exception: false)
        next if piece == :wait_readable
        return nil unless piece && !piece.empty?
        bytes << piece
        return nil if bytes.bytesize > 256 || !bytes.start_with?("\e".b)
        break if bytes.end_with?("\a".b) || bytes.end_with?("\e\\".b)
      end
      match = bytes.match(/\A\e\]#{Regexp.escape(key)};rgb:([0-9a-fA-F]{1,4})\/([0-9a-fA-F]{1,4})\/([0-9a-fA-F]{1,4})(?:\a|\e\\)\z/n)
      return nil unless match
      components = match.captures.map { |hex| (hex.to_i(16) * 65535.0 / (16**hex.length - 1)).round }
      { raw: bytes, rgb: components }
    rescue IOError, SystemCallError
      nil
    end
    snapshot = lambda do
      values = {}
      tty.raw(min: 0, time: 0, intr: true) do
        keys.each do |key|
          value = query.call(key)
          return nil unless value
          values[key] = value
        end
      end
      values
    rescue IOError, SystemCallError, ArgumentError
      nil
    end
    original = snapshot.call
    unless original
      notify.call('终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。')
      tty.close
      plain.call
      return
    end
    directory = Dir.mktmpdir('jobs-terminal-style-')
    recovery = File.join(directory, 'restore.sh')
    original_bytes = keys.map { |key| original.fetch(key).fetch(:raw) }.join
    recovery_source = "#!/bin/sh\n" \
      "[ -t 0 ] && [ \"$(tty)\" = '#{tty_name}' ] || { printf '请在原终端运行恢复入口。\\n' >&2; exit 1; }\n" \
      "printf '本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：' >&2\n" \
      "IFS= read -r jobs_restore_choice\n[ \"$jobs_restore_choice\" = YES ] || exit 1\n" \
      "printf '%s\\033[0m' '#{original_bytes}' > /dev/tty\n"
    File.open(recovery, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.binmode
      file.write(recovery_source.b)
    end
    notify.call("本次终端临时使用黑底白字；强退后恢复入口：sh \"#{recovery}\"")
    changed = false
    applied = nil
    # 比较仍生效的本轮颜色，只恢复未被用户另行修改的项。
    cleanup = lambda do
      current = applied && snapshot.call
      unless current
        notify.call("终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh \"#{recovery}\"")
        return false
      end
      conflicts = []
      restore_bytes = ''.b
      keys.each do |key|
        if current.fetch(key).fetch(:rgb) == applied.fetch(key).fetch(:rgb)
          restore_bytes << original.fetch(key).fetch(:raw)
        else
          conflicts << key
        end
      end
      tty.write(restore_bytes + "\e[0m".b)
      if conflicts.empty?
        File.unlink(recovery)
        Dir.rmdir(directory)
        true
      else
        notify.call("检测到运行期间的配色变更，已保留这些项：#{conflicts.join(' ')}")
        notify.call("确认要覆盖后续改色时才使用恢复入口：sh \"#{recovery}\"")
        false
      end
    rescue IOError, SystemCallError
      notify.call("终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh \"#{recovery}\"")
      false
    end
    child_pid = nil
    guardian = false
    interrupted = nil
    previous_signals = {}
    %w[INT TERM HUP].each do |name|
      previous_signals[name] = Signal.trap(name) do
        interrupted = name
        if child_pid && name != 'INT'
          begin
            Process.kill(name, child_pid)
          rescue Errno::ESRCH
          end
        end
      end
    end
    begin
      changed = true
      tty.write(targets.map { |key, color| "\e]#{key};##{color}\a" }.join + "\e[0m")
      applied = snapshot.call
      unless applied
        notify.call('无法核实本次临时配色，已停止启动业务。')
        raise SystemExit, 1
      end
      desired = targets.all? do |key, hex|
        rgb = hex.scan(/../).map { |component| component.to_i(16) * 257 }
        applied.fetch(key).fetch(:rgb).zip(rgb).all? { |actual, expected| (actual - expected).abs <= 255 }
      end
      unless desired
        notify.call('终端未接受本次配色，恢复后使用纯文本。')
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      if interrupted
        raise SystemExit, 128 + Signal.list.fetch(interrupted)
      end
      if Thread.list.length > 1
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      $stdout.flush
      $stderr.flush
      begin
        child_pid = Process.fork
      rescue NotImplementedError, SystemCallError
        restored = cleanup.call
        changed = false
        raise SystemExit, 1 unless restored
        plain.call
        return
      end
      unless child_pid
        changed = false
        ENV['JOBS_TERMINAL_STYLE_TTY'] = tty_name
        ENV['JOBS_TERMINAL_STYLE_OWNER'] = Process.ppid.to_s
        raise SystemExit, 128 + Signal.list.fetch(interrupted) if interrupted
        return
      end
      guardian = true
      result = nil
      loop do
        begin
          _, result = Process.wait2(child_pid)
          break
        rescue Interrupt, Errno::EINTR
        end
      end
      status_code = result.exitstatus || 128 + result.termsig
      %w[INT TERM HUP].each { |name| Signal.trap(name, 'IGNORE') }
      restored = cleanup.call
      changed = false
      status_code = 1 if !restored && status_code.zero?
      tty.close
      Process.exit!(status_code)
    ensure
      if changed
        %w[INT TERM HUP].each { |name| Signal.trap(name, 'IGNORE') }
        cleanup.call
      end
      previous_signals.each { |name, handler| Signal.trap(name, handler) } unless guardian
      tty.close unless tty.closed?
    end
  rescue IOError, SystemCallError, LoadError => error
    if guardian
      notify.call("终端保护监督进程异常：#{error.message}")
      Process.exit!(1)
    end
    raise SystemExit, 1 if changed
    notify.call("终端保护不可用，使用纯文本：#{error.message}")
    plain.call
  end
  jobs_terminal_style_bootstrap_v1

end
# JOBS_TERMINAL_STYLE_GUARD_V1_END

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'shellwords'
require 'socket'
require 'tmpdir'

class InstallerGitCopyTests < Minitest::Test
  SCRIPT = File.expand_path('../【MacOS】安装SourceTree自定义菜单.command/【MacOS】安装SourceTree自定义菜单.command', File.dirname(__dir__))

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
