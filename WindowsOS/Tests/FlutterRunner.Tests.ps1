# FlutterRunner.Tests.ps1 | Jobs SourceTree Windows
# Created by Jobs on 2026年10月29日，星期四.
# 隔离验证调度；不启动 Flutter、模拟器、工具安装或系统菜单。
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$module = Import-Module (Join-Path $root 'Scripts/SourceTree.psm1') -Force -PassThru -DisableNameChecking
$script:checks = 0
$oldAndroidHome = $env:ANDROID_HOME
$oldAndroidRoot = $env:ANDROID_SDK_ROOT
function Assert-Run {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:checks++
}
try {
    & $module {
        $script:Calls = [Collections.Generic.List[string]]::new()
        $script:CancelDevice = $false
        function script:Write-JobsStatus { param($Text) $script:Calls.Add('status:' + $Text) }
        function script:Resolve-JobsDirectory { param($Target) return $Target }
        function script:Push-Location { param($LiteralPath) $script:Calls.Add('push:' + $LiteralPath) }
        function script:Pop-Location { $script:Calls.Add('pop') }
        function script:Invoke-FakeFlutter {
            $script:Calls.Add('flutter:' + ($args -join ' '))
            $script:Calls.Add('sdk:' + $env:ANDROID_HOME + '|' + $env:ANDROID_SDK_ROOT)
            $global:LASTEXITCODE = 0
        }
        function script:Import-Module {
            param($Name, [switch]$Force, [switch]$PassThru, [switch]$DisableNameChecking)
            $script:Calls.Add('module:' + $Name)
            $cancel = $script:CancelDevice
            return New-Module -ArgumentList $cancel -ScriptBlock {
                param($Cancel)
                $script:Cancel = $Cancel
                $script:RunnerSelectedSdk = '/fixture/selected-sdk'
                function Assert-JobsFlutterProject { param($Project) }
                function Get-JobsRunnerFlutter { param($Project) return 'Invoke-FakeFlutter' }
                function Select-JobsRunnerDevice { param($Flutter, $Project) if ($script:Cancel) { return $null }; return 'emulator-selected' }
            }
        }
    }
    $env:ANDROID_HOME = 'old-home'
    $env:ANDROID_SDK_ROOT = 'old-root'
    & $module { Invoke-JobsSourceTreeAction -Action run -Target 'Fixture Project' }
    $calls = @(& $module { $script:Calls.ToArray() })
    Assert-Run (@($calls | Where-Object { $_.Replace('\','/') -like '*Features/JobsFlutterRunner/Scripts/Action.psm1' }).Count -eq 1) '运行动作调用随包设备选择模块'
    Assert-Run ($calls -contains 'flutter:run -d emulator-selected') ('使用选择器返回的明确设备继续前台Flutter：' + ($calls -join ' | '))
    Assert-Run ($calls -contains 'pop') '运行后恢复工作目录'
    Assert-Run ($calls -contains 'sdk:/fixture/selected-sdk|/fixture/selected-sdk') '前台Flutter继承选定SDK'
    Assert-Run ($env:ANDROID_HOME -ceq 'old-home' -and $env:ANDROID_SDK_ROOT -ceq 'old-root') 'Flutter结束后恢复SDK环境'
    & $module { $script:Calls.Clear(); $script:CancelDevice = $true; Invoke-JobsSourceTreeAction -Action run -Target 'Fixture Project' }
    $calls = @(& $module { $script:Calls.ToArray() })
    Assert-Run (@($calls | Where-Object { $_ -like 'flutter:*' -or $_ -like 'push:*' }).Count -eq 0) '取消设备选择不启动Flutter'
    foreach ($relative in @('Extension.json', 'Scripts/Action.psm1', 'Scripts/AndroidRuntime.ps1', 'Scripts/Common.psm1')) {
        Assert-Run (Test-Path -LiteralPath (Join-Path $root ('Scripts/Features/JobsFlutterRunner/' + $relative)) -PathType Leaf) ('完整随包资源：' + $relative)
    }
    Write-Host ('PASS: FlutterRunner.Tests.ps1 (' + $script:checks + ' assertions)')
} finally { Remove-Module $module; $env:ANDROID_HOME = $oldAndroidHome; $env:ANDROID_SDK_ROOT = $oldAndroidRoot }
