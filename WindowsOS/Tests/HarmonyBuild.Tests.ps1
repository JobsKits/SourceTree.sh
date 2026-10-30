# HarmonyBuild.Tests.ps1 | Jobs 鸿蒙双产物隔离验证
# Created by Jobs on 2026年10月28日，星期三.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$module = Import-Module (Join-Path $root 'Scripts/Features/JobsFlutterPackager/Scripts/Action.psm1') -PassThru -Force -DisableNameChecking
$temporaryRoot = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { [IO.Path]::GetTempPath() } else { '/private/tmp' }
$fixture = Join-Path $temporaryRoot ('JobsHarmonyBuildTest-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$count = @{ Value = 0 }
try {
    & $module {
        param($fixture, $count)
        function Assert-Equal {
            param($Actual, $Expected, [string]$Label)
            if ($Actual -cne $Expected) { throw ($Label + '：实际 ' + $Actual + '，预期 ' + $Expected) }
            $count.Value++
        }
        function Assert-Throws {
            param([scriptblock]$Operation, [string]$Label)
            $failed = $false
            try { & $Operation } catch { $failed = $true }
            if (-not $failed) { throw ($Label + '：预期失败却成功') }
            $count.Value++
        }
        $project = Join-Path $fixture '中文 Flutter project'
        foreach ($relative in @('lib', 'ohos', 'build/ohos')) {
            [void][IO.Directory]::CreateDirectory((Join-Path $project $relative))
        }
        [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), "name: jobs_fixture`ndependencies:`n  flutter:`n    sdk: flutter`n")
        foreach ($relative in @('ohos/build-profile.json5', 'ohos/oh-package.json5')) {
            [IO.File]::WriteAllText((Join-Path $project $relative), '{}')
        }
        $sdk = Join-Path $fixture 'SDK with 空格'
        [void][IO.Directory]::CreateDirectory((Join-Path $sdk 'bin'))
        [IO.File]::WriteAllText((Join-Path $sdk 'bin/flutter.bat'), '@rem never executed')
        Assert-Equal (Get-JobsPackagerFlutter -Project $project -SdkRoot $sdk) (Join-Path $sdk 'bin/flutter.bat') '显式 SDK 中文空格路径'
        Assert-Throws { Get-JobsPackagerFlutter -Project $project -SdkRoot (Join-Path $fixture 'missing') } '显式 SDK 缺失停止'
        [IO.File]::WriteAllText((Join-Path $project '.fvmrc'), '{"flutter":"custom_ohos"}')
        Assert-Throws { Get-JobsPackagerFlutter -Project $project } 'FVM 缺失不回退全局'
        Assert-Equal (Get-JobsPackagerHarmonyOptions -Type all -Mode release -Flavor '').Type 'all' '双产物配置'
        Assert-Throws { Get-JobsPackagerHarmonyOptions -Type all -Mode invalid -Flavor '' } '拒绝模式'
        Assert-Throws { Get-JobsPackagerHarmonyOptions -Type all -Mode release -Flavor prod } '拒绝不可靠 flavor'
        function JobsFixtureExitSeven { $global:LASTEXITCODE = 7 }
        $failureCode = 0
        try { Invoke-JobsPackagerTool -File JobsFixtureExitSeven -Arguments @() -Project $project }
        catch { $failureCode = $_.Exception.Data['JobsExitCode'] }
        Assert-Equal $failureCode 7 '构建失败携带原退出码'
        # 所有探测均替换为只读内存返回，不调用真实工具链。
        function Find-JobsExecutable { param($Name, $Candidates); return (Join-Path $fixture 'fake-tool') }
        $script:ProbeApp = $true
        function Invoke-JobsPackagerProbe {
            param($File, $Arguments, $Project)
            if ($Arguments.Count -eq 3 -and $Arguments[0] -eq 'build') {
                if ($Arguments[1] -eq 'app' -and -not $script:ProbeApp) {
                    return [pscustomobject]@{ ExitCode = 0; Output = 'Usage: flutter build <subcommand>' }
                }
                return [pscustomobject]@{ ExitCode = 0; Output = ('Usage: flutter build ' + $Arguments[1]) }
            }
            return [pscustomobject]@{ ExitCode = 0; Output = 'fixture version' }
        }
        Assert-JobsPackagerHarmonyToolchain -Project $project -Flutter 'fixture-flutter' -Targets @('hap', 'app')
        $count.Value++
        $script:ProbeApp = $false
        Assert-Throws { Assert-JobsPackagerHarmonyToolchain -Project $project -Flutter 'fixture-flutter' -Targets @('hap', 'app') } '缺 APP 能力停止'
        function Assert-JobsPackagerHarmonyToolchain { param($Project, $Flutter, $Targets); Assert-Equal ($Targets -join ',') 'hap,app' '构建前核验两种能力' }
        function Initialize-JobsPackagerHarmonyEnvironment {
            $env:TOOL_HOME = 'fixture tool home'
            $env:DEVECO_SDK_HOME = 'fixture sdk'
            $env:PATH = 'fixture path'
        }
        $script:Calls = New-Object 'System.Collections.Generic.List[string]'
        $script:Failure = ''
        $script:Missing = ''
        $script:RemoveHapOnApp = $false
        function Invoke-JobsPackagerTool {
            param($File, $Arguments, $Project)
            $command = $Arguments -join ' '
            $script:Calls.Add($command)
            if ($command -eq $script:Failure) { throw '隔离模拟构建失败 7' }
            if ($Arguments[0] -eq 'build' -and $Arguments[1] -ne $script:Missing) {
                [IO.File]::WriteAllText((Join-Path $Project ('build/ohos/entry-default-signed.' + $Arguments[1])), $command)
            }
            if ($script:RemoveHapOnApp -and $Arguments[0] -eq 'build' -and $Arguments[1] -eq 'app') {
                Remove-Item -LiteralPath (Join-Path $Project 'build/ohos/entry-default-signed.hap') -Force
            }
        }
        $environment = @{}
        foreach ($name in @('PATH', 'TOOL_HOME', 'DEVECO_SDK_HOME')) { $environment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
        $savedFlavor = $env:FLAVOR
        $env:FLAVOR = ''
        try {
            Invoke-JobsPackagerHarmonyBuild -Project $project -FlutterSdk $sdk -Type all -Mode release
            Assert-Equal ($script:Calls -join '|') 'pub get|build hap --release|build app --release' '固定双产物顺序'
            foreach ($name in $environment.Keys) { Assert-Equal ([Environment]::GetEnvironmentVariable($name, 'Process')) $environment[$name] ('恢复 ' + $name) }
            Assert-Equal (@(Get-JobsPackagerHarmonyArtifacts -Project $project -Type hap).Count) 1 'HAP 非空'
            Assert-Equal (@(Get-JobsPackagerHarmonyArtifacts -Project $project -Type app).Count) 1 'APP 非空'
            foreach ($failure in @('pub get', 'build hap --release', 'build app --release')) {
                $script:Calls.Clear()
                $script:Failure = $failure
                Assert-Throws { Invoke-JobsPackagerHarmonyBuild -Project $project -FlutterSdk $sdk -Type all -Mode release } ('传播失败 ' + $failure)
                if ($failure -eq 'pub get') { Assert-Equal $script:Calls.Count 1 'pub 失败不构建' }
                if ($failure -eq 'build hap --release') { Assert-Equal $script:Calls.Count 2 'HAP 失败不继续 APP' }
                foreach ($name in $environment.Keys) { Assert-Equal ([Environment]::GetEnvironmentVariable($name, 'Process')) $environment[$name] ('失败恢复 ' + $name) }
            }
            $script:Failure = ''
            $script:RemoveHapOnApp = $true
            Assert-Throws { Invoke-JobsPackagerHarmonyBuild -Project $project -FlutterSdk $sdk -Type all -Mode release } 'APP 构建删掉 HAP 时整体失败'
            $script:RemoveHapOnApp = $false
            Remove-Item -LiteralPath (Join-Path $project 'build/ohos/entry-default-signed.app')
            $script:Missing = 'app'
            Assert-Throws { Invoke-JobsPackagerHarmonyBuild -Project $project -FlutterSdk $sdk -Type all -Mode release } 'APP 未输出整体失败'
            [IO.File]::WriteAllText((Join-Path $project 'build/ohos/empty.app'), '')
            Assert-Throws { Get-JobsPackagerHarmonyArtifacts -Project $project -Type app } '空 APP 不算产物'
            $outside = Join-Path $fixture 'external-module'
            [void][IO.Directory]::CreateDirectory((Join-Path $outside 'build/outputs'))
            [IO.File]::WriteAllText((Join-Path $outside 'build/outputs/external.app'), 'external fixture')
            $link = Join-Path $project 'ohos/linked-module'
            $linked = $false
            try {
                [void](New-Item -ItemType SymbolicLink -Path $link -Target $outside -ErrorAction Stop)
                $linked = $true
            } catch { Write-Host 'SKIP：本机无创建链接权限；保留其它产物检查。' }
            if ($linked) {
                Assert-Throws { Get-JobsPackagerHarmonyArtifacts -Project $project -Type app } '不采纳链接模块的外部产物'
                Remove-Item -LiteralPath $link -Force
                $plainModule = Join-Path $project 'ohos/plain-module'
                [void][IO.Directory]::CreateDirectory($plainModule)
                $link = Join-Path $plainModule 'build'
                [void](New-Item -ItemType SymbolicLink -Path $link -Target (Join-Path $outside 'build'))
                Assert-Throws { Get-JobsPackagerHarmonyArtifacts -Project $project -Type app } '不采纳链接输出目录的外部产物'
                Remove-Item -LiteralPath $link -Force
            }
            Rename-Item -LiteralPath (Join-Path $project 'lib') -NewName 'lib-backup'
            Assert-Throws { Invoke-JobsPackagerHarmonyBuild -Project $project -FlutterSdk $sdk -Type all -Mode release } '缺 lib 不构建'
        } finally {
            $env:FLAVOR = $savedFlavor
        }
    } $fixture $count
    $dispatcher = Import-Module (Join-Path $root 'Scripts/SourceTree.psm1') -PassThru -Force -DisableNameChecking
    & $dispatcher {
        param($count, $fixture)
        $script:LogFile = Join-Path $fixture 'dispatch.log'
        $script:ExpectedLog = $script:LogFile
        function Import-Module {
            param($Path, [switch]$Force, [switch]$DisableNameChecking, [switch]$PassThru)
            New-Module {
                function Invoke-JobsPackagerHarmonyBuild {
                    param($Project, $Type)
                    [pscustomobject]@{ Project = $Project; Type = $Type; Log = $script:PackagerLog }
                }
            }
        }
        $result = Invoke-JobsFeatureModule 'JobsFlutterPackager' 'fixture project' 'ohos'
        if ($result.Type -cne 'all' -or $result.Project -cne 'fixture project') { throw '调度未强制双产物或目标改变' }
        $count.Value++
        if ($result.Log -cne $script:ExpectedLog) { throw '调度未传入会话日志' }
        $count.Value++
    } $count $fixture
    Remove-Module $dispatcher -Force
    Write-Host ('PASS：' + $count.Value + ' 项鸿蒙双产物断言；没有执行真实 SDK 或构建。')
} finally {
    Remove-Module $module -Force
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
