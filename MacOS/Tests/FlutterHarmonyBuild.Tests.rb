# frozen_string_literal: true
# Created by Jobs on 2026年10月28日，星期三。
# 生产函数配合私有假工具链回归；不构建真实工程或修改菜单。

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

class FlutterHarmonyBuildTests < Minitest::Test
  SCRIPT = File.expand_path('../【MacOS@SourceTree】📦双击打包Flutter.ohos.command/【MacOS@SourceTree】📦双击打包Flutter.ohos.command', __dir__)

  def setup
    @root = Dir.mktmpdir('sourcetree-harmony-build-')
    @project = File.join(@root, "工程 空格 ' $(touch NEVER)")
    @bin = File.join(@root, 'bin')
    @sdk = File.join(@root, 'sdk')
    @trace = File.join(@root, 'trace')
    FileUtils.mkdir_p([@project, @bin, @sdk, File.join(@project, 'lib'), File.join(@project, 'ohos')])
    File.write(File.join(@project, 'pubspec.yaml'), "name: fixture\ndependencies: { flutter: { sdk: flutter } }\n")
    %w[build-profile.json5 oh-package.json5].each { |name| File.write(File.join(@project, 'ohos', name), '{}') }
    @library = File.join(@root, 'library.zsh')
    File.write(@library, File.read(SCRIPT).sub(/^main "\$@"\s*\z/, ''))
    %w[node npm ohpm java hvigorw].each { |tool| mock(tool, 'exit 0') }
    mock('flutter', <<~'ZSH')
      print -r -- "$*" >> "$HARMONY_TEST_TRACE"
      [[ "$1" != --version ]] || exit 0
      [[ "$1:$2" != pub:get ]] || exit 0
      if [[ "$3" == --help ]]; then
        [[ "$2" != "${HARMONY_TEST_UNSUPPORTED:-}" ]] || exit 64
        print -r -- "Usage: flutter build $2 [arguments]"
        exit 0
      fi
      [[ "$2" != "${HARMONY_TEST_FAIL:-}" ]] || exit 43
      [[ "$2" != "${HARMONY_TEST_NO_OUTPUT:-}" ]] || exit 0
      output="$HARMONY_TEST_PROJECT/build/ohos/$2/entry-signed.$2"
      /bin/mkdir -p "${output:h}"
      print -r -- 'fixture-package' > "$output"
    ZSH
    @env = {
      'HOME' => @root, 'PATH' => "#{@bin}:/usr/bin:/bin", 'TMPDIR' => @root,
      'BUILD_TARGET' => nil, 'BUILD_MODE' => nil, 'FLUTTER_OHOS_SDK' => nil,
      'DEVECO_STUDIO_HOME' => nil, 'TOOL_HOME' => nil, 'JAVA_HOME' => nil, 'NODE_HOME' => nil,
      'DEVECO_SDK_HOME' => @sdk, 'OPEN_AFTER_BUILD' => '0',
      'HARMONY_TEST_PROJECT' => @project, 'HARMONY_TEST_TRACE' => @trace
    }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def mock(name, body)
    path = File.join(@bin, name)
    File.write(path, "#!/bin/zsh\n#{body}\n")
    File.chmod(0o700, path)
  end

  def run_flow(*arguments, env: {})
    body = <<~ZSH
      source #{@library.shellescape}
      setopt NO_NOMATCH PIPE_FAIL
      PLAIN_OUTPUT=1
      LOG_READY=1
      LOG_FILE=#{File.join(@root, 'build.log').shellescape}
      : > "$LOG_FILE"
      run_build_flow #{@project.shellescape} #{arguments.shelljoin}
    ZSH
    Open3.capture3(@env.merge(env), '/bin/zsh', '-f', '-c', body)
  end

  def test_default_builds_both_release_packages_in_order
    out, err, result = run_flow
    assert result.success?, out + err
    calls = File.readlines(@trace, chomp: true)
    assert_equal ['pub get', 'build hap --release', 'build app --release'], calls.reject { |line| line == '--version' || line.end_with?('--help') }
    %w[hap app].each { |type| assert File.size?(File.join(@project, "build/ohos/#{type}/entry-signed.#{type}")) }
    refute File.exist?(File.join(@root, 'NEVER'))
    assert_includes out, '鸿蒙构建结束（hap + app）'
  end

  def test_app_capability_is_checked_before_dependency_resolution
    out, err, result = run_flow(env: { 'HARMONY_TEST_UNSUPPORTED' => 'app' })
    refute result.success?, out + err
    refute_includes File.read(@trace), 'pub get'
    refute File.exist?(File.join(@project, 'build'))
  end

  def test_default_ignores_ambient_single_target
    out, err, result = run_flow(env: { 'BUILD_TARGET' => 'hap' })
    assert result.success?, out + err
    assert_includes File.read(@trace), 'build hap --release'
    assert_includes File.read(@trace), 'build app --release'
  end

  def test_second_build_failure_is_not_reported_as_overall_success
    out, err, result = run_flow(env: { 'HARMONY_TEST_FAIL' => 'app' })
    assert_equal 43, result.exitstatus, out + err
    assert File.size?(File.join(@project, 'build/ohos/hap/entry-signed.hap'))
    refute_includes out, '鸿蒙构建结束'
  end

  def test_missing_app_artifact_is_failure_after_two_successful_commands
    out, err, result = run_flow(env: { 'HARMONY_TEST_NO_OUTPUT' => 'app' })
    refute result.success?, out + err
    assert_includes out + err, '未发现非空 .app 产物'
    refute_includes out, '鸿蒙构建结束'
  end

  def test_explicit_single_target_keeps_cli_compatibility
    out, err, result = run_flow('--target', 'hap', '--mode', 'debug')
    assert result.success?, out + err
    assert_includes File.read(@trace), 'build hap --debug'
    refute_includes File.read(@trace), 'build app'
  end

  def test_menu_arguments_override_ambient_single_target_and_mode
    out, err, result = run_flow('--target', 'all', '--mode', 'release', env: { 'BUILD_TARGET' => 'app', 'BUILD_MODE' => 'debug' })
    assert result.success?, out + err
    assert_includes File.read(@trace), 'build hap --release'
    assert_includes File.read(@trace), 'build app --release'
  end

  def test_app_rebuild_removing_hap_fails_final_pair_verification
    mock_path = File.join(@bin, 'flutter')
    File.write(mock_path, File.read(mock_path).sub('output="$HARMONY_TEST_PROJECT', '[[ "$2" != app ]] || /bin/rm -f "$HARMONY_TEST_PROJECT/build/ohos/hap/entry-signed.hap"; output="$HARMONY_TEST_PROJECT'))
    out, err, result = run_flow
    refute result.success?, out + err
    assert_includes out + err, '最终产物复核失败'
    assert File.size?(File.join(@project, 'build/ohos/app/entry-signed.app'))
    refute_includes out, '鸿蒙构建结束'
  end
end
