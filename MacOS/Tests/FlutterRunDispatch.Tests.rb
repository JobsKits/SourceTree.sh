# frozen_string_literal: true
# Created by Jobs on 2026年10月29日，星期四。
# 仅在隔离目录校验运行交接，不打开 Terminal、不启动真实 Flutter / 模拟器。

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
