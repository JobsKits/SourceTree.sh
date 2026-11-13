# frozen_string_literal: true
# Created by Jobs on 2026年10月29日，星期四。
# 仅在隔离目录校验运行交接，不打开 Terminal、不启动真实 Flutter / 模拟器。

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
require 'tmpdir'

class FlutterRunDispatchTests < Minitest::Test
  PACKAGE_NAME = '【MacOS@SourceTree】🐦打开：运行Flutter项目.command'
  SCRIPT_NAME = PACKAGE_NAME
  SOURCE = File.expand_path("../#{PACKAGE_NAME}/#{SCRIPT_NAME}", __dir__)

  def setup
    @root = Dir.mktmpdir('sourcetree-flutter-run-')
    @package = File.join(@root, "复制 改名 ' $(touch NEVER)-动作")
    @project = File.join(@root, "工程 空格 ' $(touch NEVER)-项目")
    @library = File.join(@root, 'definitions.zsh')
    @trace = File.join(@root, 'runner-args')
    FileUtils.mkdir_p([@package, File.join(@package, 'Scripts'), File.join(@project, 'lib'), File.join(@root, 'elsewhere')])
    File.write(File.join(@project, 'pubspec.yaml'), "name: fixture\ndependencies: {flutter: {sdk: flutter}}\n")
    File.write(@library, File.read(SOURCE).sub(/^main "\$@"\s*\z/, ''))
    File.write(File.join(@package, 'Scripts', 'FlutterRunner.jxa'), '// fixture')
    File.write(File.join(@package, 'Scripts', 'RunFlutterProject.zsh'), "#!/bin/zsh\nprintf '%s\\n' \"$@\" > \"$RUN_DISPATCH_TRACE\"\n")
    @env = {
      'HOME' => @root, 'TMPDIR' => @root, 'PATH' => '/usr/bin:/bin:/usr/sbin:/sbin',
      'RUN_DISPATCH_TRACE' => @trace, 'NO_COLOR' => '1', 'SOURCETREE_TEST' => nil
    }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def run_definitions(body, env: {})
    script = <<~ZSH
      source #{@library.shellescape}
      setopt NO_NOMATCH PIPE_FAIL
      SCRIPT_DIR=#{@package.shellescape}
      PROJECT_ROOT=#{@project.shellescape}
      LOG_FILE=#{File.join(@root, 'action.log').shellescape}
      LOG_READY=0
      PLAIN_OUTPUT=1
      SOURCETREE_PLAIN_OUTPUT=1
      cd #{File.join(@root, 'elsewhere').shellescape} || exit 99
      #{body}
    ZSH
    Open3.capture3(@env.merge(env), '/bin/zsh', '-f', '-c', script)
  end

  def test_relocated_bundle_and_project_are_passed_as_literal_arguments
    out, err, result = run_definitions(<<~'ZSH')
      command_text="$(build_flutter_run_command)" || exit $?
      /bin/zsh -f -c "$command_text"
    ZSH
    assert result.success?, out + err
    assert_equal ['--project', @project], File.readlines(@trace, chomp: true)
    refute File.exist?(File.join(@root, 'elsewhere', 'NEVER'))
    refute File.exist?(File.join(@root, 'NEVER'))
  end

  def test_packaged_runner_accepts_the_launcher_argument_contract
    runner = File.join(File.dirname(SOURCE), 'Scripts', 'RunFlutterProject.zsh')
    definitions = File.read(runner).sub(/^main "\$@"\s*\z/, '')
    File.write(File.join(@package, 'Scripts', 'RunFlutterProject.zsh'), definitions + <<~'ZSH')
      json_helper() { print true; }
      log() { :; }
      read_project "$@"
      print -r -- "$PROJECT_PATH" > "$RUN_DISPATCH_TRACE"
    ZSH
    out, err, result = run_definitions(<<~'ZSH')
      command_text="$(build_flutter_run_command)" || exit $?
      /bin/zsh -f -c "$command_text"
    ZSH
    assert result.success?, out + err
    assert_equal [File.realpath(@project)], File.readlines(@trace, chomp: true)
  end

  def test_missing_helper_rejects_handoff_without_running
    File.delete(File.join(@package, 'Scripts', 'FlutterRunner.jxa'))
    out, err, result = run_definitions('build_flutter_run_command')
    refute result.success?, out + err
    assert_includes out + err, '缺少同包 Flutter 运行器'
    refute File.exist?(@trace)
  end

  def test_missing_runner_rejects_handoff_without_running
    File.delete(File.join(@package, 'Scripts', 'RunFlutterProject.zsh'))
    out, err, result = run_definitions('build_flutter_run_command')
    refute result.success?, out + err
    refute File.exist?(@trace)
  end

  def test_standard_dry_run_generates_bound_command_without_opening_terminal
    out, err, result = run_definitions(<<~'ZSH', env: { 'JOBS_SOURCETREE_SETUP_DRY_RUN' => '1' })
      resolve_setup_command || exit $?
      open_setup_in_terminal
    ZSH
    assert result.success?, out + err
    assert_includes out, 'Dry-run'
    assert_includes out, 'RunFlutterProject.zsh'
    refute File.exist?(@trace)
  end

  def test_setup_remains_preferred_without_bundled_runner
    setup_path = File.join(@project, 'setup.command')
    File.write(setup_path, '# fixture')
    FileUtils.remove_entry(File.join(@package, 'Scripts'))
    out, err, result = run_definitions(<<~'ZSH', env: { 'JOBS_SOURCETREE_SETUP_DRY_RUN' => '1' })
      resolve_setup_command || exit $?
      open_setup_in_terminal
    ZSH
    assert result.success?, out + err
    assert_includes out, 'setup.command'
    refute_includes out, 'RunFlutterProject.zsh'
    refute File.executable?(setup_path)
  end

  def test_explicit_invalid_project_does_not_use_current_project
    out, err, result = run_definitions(<<~'ZSH')
      cd "$PROJECT_ROOT" || exit 99
      resolve_project_root /no/such/flutter/project
    ZSH
    refute result.success?, out + err
    assert_includes out, '传入路径没有可用'
    refute File.exist?(@trace)
  end

  def test_multiple_setup_candidates_are_rejected
    %w[one two].each do |name|
      FileUtils.mkdir_p(File.join(@project, name))
      File.write(File.join(@project, name, 'setup.command'), '# fixture')
    end
    out, err, result = run_definitions('resolve_setup_command')
    refute result.success?, out + err
    assert_includes out + err, '多个 setup.command'
    refute File.exist?(@trace)
  end

  def test_packaged_resources_exist_and_do_not_depend_on_original_source_tree
    package = File.dirname(SOURCE)
    %w[RunFlutterProject.zsh FlutterRunner.jxa README.md].each do |name|
      assert File.file?(File.join(package, 'Scripts', name)), name
    end
    refute_includes File.read(SOURCE), '/Users/jobs/Documents/Github'
  end
end
