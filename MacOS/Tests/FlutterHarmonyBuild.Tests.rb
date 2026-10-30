# frozen_string_literal: true
# Created by Jobs on 2026年10月28日，星期三。
# 生产函数配合私有假工具链回归；不构建真实工程或修改菜单。

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
