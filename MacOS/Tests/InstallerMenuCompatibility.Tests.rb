# frozen_string_literal: true
# Created by Jobs on 2026年10月29日，星期四。
# 使用隔离用户目录和假动作脚本验证菜单寻址，不操作真实菜单或应用。

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
require 'json'
require 'minitest/autorun'
require 'open3'
require 'shellwords'
require 'tmpdir'

class InstallerMenuCompatibilityTests < Minitest::Test
  PACKAGE = File.expand_path('../【MacOS】安装SourceTree自定义菜单.command', __dir__)
  SCRIPT = File.join(PACKAGE, '【MacOS】安装SourceTree自定义菜单.command')
  TEMPLATE = File.join(PACKAGE, 'actions.plist')
  FLUTTER_SCRIPT = '【MacOS@SourceTree】🐦打开：运行Flutter项目.command'

  def setup
    @root = File.realpath(Dir.mktmpdir('st-menu-compat-', '/tmp'))
    @source = File.join(@root, '源用户 甲', "资料 ' $(touch NEVER)", 'SourceTree.command')
    @deployed = File.join(@root, '目标用户 乙', 'SourceTree.command')
    @library = File.join(@root, 'installer.zsh')
    @template = File.join(@root, 'template.plist')
    @current = File.join(@root, 'current.plist')
    File.write(@library, File.read(SCRIPT).sub(/^main "\$@"\s*\z/, ''))
    @items = read_archive(TEMPLATE)
    assert_equal 33, @items.length, '模板应只包含现行的 33 项仓库动作'
    @items.each do |item|
      name = File.basename(item.fetch('target'))
      item['target'] = File.join('/Users/jobs/SourceTree.command/MacOS', name, name)
    end
    make_library(@source)
    make_library(@deployed)
    write_archive(@template, @items)
    write_archive(@current, rebase(@items, '/Users/另一台Mac用户/SourceTree.command'))
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def jxa(program, *arguments)
    out, err, result = Open3.capture3('/usr/bin/osascript', '-l', 'JavaScript', '-', *arguments, stdin_data: program)
    assert result.success?, out + err
    out
  end

  def read_archive(path)
    JSON.parse(jxa(<<~'JXA', path))
      ObjC.import('Foundation');
      function run(argv) {
        var data = $.NSData.dataWithContentsOfFile(argv[0]);
        return JSON.stringify(ObjC.deepUnwrap($.NSKeyedUnarchiver.unarchiveObjectWithData(data)));
      }
    JXA
  end

  def write_archive(path, items)
    json = File.join(@root, 'archive-input.json')
    File.write(json, JSON.generate(items))
    jxa(<<~'JXA', json, path)
      ObjC.import('Foundation');
      function run(argv) {
        var json = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null));
        var data = $.NSKeyedArchiver.archivedDataWithRootObject($(JSON.parse(json)));
        if (!data.writeToFileAtomically(argv[1], true)) throw new Error('Cannot write test archive');
        return 'fixture archive saved';
      }
    JXA
  end

  def copy_items(items = @items)
    JSON.parse(JSON.generate(items))
  end

  def rebase(items, root)
    copy_items(items).each do |item|
      name = File.basename(item.fetch('target'))
      item['target'] = File.join(root, 'MacOS', name, name)
    end
  end

  def action_path(root, name)
    File.join(root, 'MacOS', name, name)
  end

  def make_library(root)
    @items.each do |item|
      path = action_path(root, File.basename(item.fetch('target')))
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "#!/bin/zsh\nexit 0\n")
      File.chmod(0o755, path)
    end
  end

  def run_fixture(body, preserved: false, source: @source, deployed: @deployed, output: 'merged.plist')
    result_file = File.join(@root, output)
    environment = {
      'HOME' => File.dirname(deployed), 'TMPDIR' => @root,
      'ST_SOURCE' => source, 'ST_DEPLOYED' => deployed,
      'ST_TEMPLATE' => @template, 'ST_CURRENT' => @current,
      'ST_PRESERVED' => preserved ? '1' : '0', 'ST_OUTPUT' => result_file,
      'ST_LOG' => File.join(@root, 'merge.log'), 'ST_TRACE' => File.join(@root, 'wrapper.trace')
    }
    body = <<~ZSH
      source #{@library.shellescape}
      SOURCE_PACKAGE_ROOT="$ST_SOURCE"
      SOURCE_PACKAGE_NAME=SourceTree.command
      HOME_PACKAGE_ROOT="$ST_DEPLOYED"
      DEPLOYED_PACKAGE_ROOT="$ST_DEPLOYED"
      LOCAL_ACTIONS_PLIST="$ST_TEMPLATE"
      TARGET_ACTIONS_PLIST="$ST_CURRENT"
      PRESERVED_EXISTING_PACKAGE="$ST_PRESERVED"
      PLAIN_OUTPUT=1
      RUNTIME_INITIALIZED=1
      LOG_FILE="$ST_LOG"
      : > "$LOG_FILE"
      #{body}
    ZSH
    out, err, result = Open3.capture3(environment, '/bin/zsh', '-f', '-c', body)
    [out, err, result, result_file]
  end

  def run_merge(**options)
    run_fixture('merge_actions_preserving_titles "$ST_OUTPUT"', **options)
  end

  def wrapper_stubs(pause_body)
    <<~ZSH
      pause_sourcetree_before_menu_sync() {
        print -r -- pause >> "$ST_TRACE"
        #{pause_body}
      }
      copy_file_with_backup() {
        print -r -- copy >> "$ST_TRACE"
        /bin/cp "$1" "$2"
      }
      sync_sourcetree_to_peer_packages() {
        print -r -- peers >> "$ST_TRACE"
      }
      restart_sourcetree_if_needed() {
        print -r -- "reopen:$SOURCETREE_NEEDS_REOPEN" >> "$ST_TRACE"
      }
      sync_current_actions_to_sourcetree
    ZSH
  end

  def assert_managed_root(items, root)
    expected = rebase(@items, root).map { |item| item.fetch('target') }
    assert_equal expected.sort, items.map { |item| item.fetch('target') }.sort
  end

  def test_two_user_homes_retarget_foreign_template_to_complete_deployed_library
    ['本机 用户', '另一台 访客'].each_with_index do |username, index|
      deployed = File.join(@root, 'Users', username, 'SourceTree.command')
      make_library(deployed)
      out, err, result, output = run_merge(deployed: deployed, output: "machine-#{index}.plist")
      assert result.success?, out + err
      assert_managed_root(read_archive(output), deployed)
      refute_includes out + err, '改用当前源库'
      refute File.exist?(File.join(@root, 'NEVER'))
    end
  end

  def test_only_explicitly_preserved_incomplete_target_can_fall_back_to_healthy_source
    missing = action_path(@deployed, File.basename(@items.first.fetch('target')))
    FileUtils.rm(missing)
    out, err, result, output = run_merge(output: 'without-preserve.plist')
    refute result.success?, out + err
    refute File.exist?(output)
    assert_includes out + err, '运行库校验失败'

    out, err, result, output = run_merge(preserved: true, output: 'preserved.plist')
    assert result.success?, out + err
    assert_managed_root(read_archive(output), @source)
    assert_includes out + err, '已保留旧库，菜单改用当前源库'
    refute File.exist?(missing), '菜单回退不应修补或替换用户保留的旧库'
  end

  def test_incomplete_source_and_target_reject_without_writing_output
    name = File.basename(@items.last.fetch('target'))
    [@source, @deployed].each { |root| FileUtils.rm(action_path(root, name)) }
    before = File.binread(@current)
    out, err, result, output = run_merge(preserved: true)
    refute result.success?, out + err
    refute File.exist?(output)
    assert_includes out + err, '当前源库也无法使用'
    assert_equal before, File.binread(@current)
  end

  def test_directories_and_nonexecutable_files_are_rejected_as_action_scripts
    name = File.basename(@items.first.fetch('target'))
    path = action_path(@deployed, name)
    FileUtils.rm(path)
    FileUtils.mkdir_p(path)
    out, err, result, output = run_merge(output: 'directory.plist')
    refute result.success?, out + err
    refute File.exist?(output)
    assert_includes out + err, '不是普通脚本文件'

    FileUtils.rmdir(path)
    File.write(path, "#!/bin/zsh\nexit 0\n")
    File.chmod(0o644, path)
    out, err, result, output = run_merge(output: 'nonexecutable.plist')
    refute result.success?, out + err
    refute File.exist?(output)
    assert_includes out + err, '脚本不可执行'
  end

  def test_legacy_ascii_colon_flutter_path_migrates_to_the_fullwidth_path
    legacy_template = copy_items
    legacy_current = rebase(@items, '/Users/旧Mac用户/SourceTree.command')
    [legacy_template, legacy_current].each do |items|
      flutter = items.find { |item| File.basename(item.fetch('target')) == FLUTTER_SCRIPT }
      refute_nil flutter
      flutter['target'] = flutter.fetch('target').gsub('打开：运行Flutter项目', '打开:运行Flutter项目')
    end
    write_archive(@template, legacy_template)
    write_archive(@current, legacy_current)
    out, err, result, output = run_merge
    assert result.success?, out + err
    items = read_archive(output)
    assert_equal 33, items.length
    assert_equal 1, items.count { |item| item.fetch('target') == action_path(@deployed, FLUTTER_SCRIPT) }
    refute items.any? { |item| item.fetch('target').include?('打开:运行Flutter项目') }
  end

  def test_user_fields_and_extra_actions_survive_retargeting_and_reinstallation
    current = rebase(@items, '/Users/旧Mac用户/SourceTree.command')
    customized = current.first
    customized['name'] = '🎯自取标题'
    customized['shortcutKeyCode'] = 19
    customized['shortcutKeyModifiers'] = 1_048_576
    customized['shortcutKeyDisplay'] = '⌘2'
    customized['separateWindow'] = !customized['separateWindow']
    customized['customSetting'] = { 'nested' => ['保持', 7, false] }
    extra = customized.merge('target' => File.join(@root, '自有 工具', 'custom.command'), 'name' => '🧪额外动作')
    current << extra
    write_archive(@current, current)
    out, err, result, output = run_merge
    assert result.success?, out + err
    items = read_archive(output)
    assert_equal 34, items.length
    actual = items.find { |item| File.basename(item.fetch('target')) == File.basename(customized.fetch('target')) }
    expected = customized.merge('target' => action_path(@deployed, File.basename(customized.fetch('target'))))
    assert_equal expected, actual
    assert_equal extra, items.last

    write_archive(@current, items)
    out, err, result, second = run_merge(output: 'second.plist')
    assert result.success?, out + err
    assert_equal items, read_archive(second)
  end

  def test_sync_reports_the_runtime_once_whether_or_not_the_app_was_running
    [false, true].each do |running|
      trace = File.join(@root, 'wrapper.trace')
      FileUtils.rm_f(trace)
      write_archive(@current, rebase(@items, '/Users/另一台Mac用户/SourceTree.command'))
      out, err, result, = run_fixture(wrapper_stubs("SOURCETREE_NEEDS_REOPEN=#{running ? 1 : 0}"))
      assert result.success?, out + err
      assert_equal 1, (out + err).scan('菜单运行库：').length
      assert_equal ['pause', 'copy', 'peers', "reopen:#{running ? 1 : 0}"], File.readlines(trace, chomp: true)
      assert_managed_root(read_archive(@current), @deployed)
      assert_empty Dir.glob(File.join(@root, 'sourcetree-actions.*'))
    end
  end

  def test_sync_preflight_failure_does_not_pause_or_overwrite
    FileUtils.rm(action_path(@deployed, File.basename(@items.first.fetch('target'))))
    before = File.binread(@current)
    out, err, result, = run_fixture(wrapper_stubs('SOURCETREE_NEEDS_REOPEN=1'))
    refute result.success?, out + err
    assert_includes out + err, '菜单预检失败'
    refute File.exist?(File.join(@root, 'wrapper.trace'))
    assert_equal before, File.binread(@current)
    assert_empty Dir.glob(File.join(@root, 'sourcetree-actions.*'))
  end

  def test_sync_failure_after_pause_reopens_without_overwriting
    before = File.binread(@current)
    path = action_path(@deployed, File.basename(@items.first.fetch('target')))
    pause_body = "SOURCETREE_NEEDS_REOPEN=1\n/bin/rm -- #{path.shellescape}"
    out, err, result, = run_fixture(wrapper_stubs(pause_body))
    refute result.success?, out + err
    assert_includes out + err, '退出后菜单合并失败'
    assert_equal ['pause', 'reopen:1'], File.readlines(File.join(@root, 'wrapper.trace'), chomp: true)
    assert_equal before, File.binread(@current)
    assert_empty Dir.glob(File.join(@root, 'sourcetree-actions.*'))
  end
end
