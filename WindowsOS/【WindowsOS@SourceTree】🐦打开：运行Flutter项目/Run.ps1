# 🐦打开：运行Flutter项目 | Jobs Windows Sourcetree
# Created by Jobs on 2026年10月23日，星期五.
# 用途：选择设备运行项目；Android 可启动已有 AVD，缺失时确认初始化；Ctrl+C 取消。
[CmdletBinding()]
param([Parameter(Position=0)][string]$Target, [string]$Option, [string]$Value,
      [switch]$SourceTree, [switch]$Terminal)
$ErrorActionPreference = 'Stop'
$exitCode = 0
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '此入口仅支持 Windows，请使用 MacOS 目录。' }
    if (-not $Target) { $Target = (Get-Location).Path }
    if ($SourceTree -and -not $Terminal) {
        Write-Host 'Jobs：选择 Android、Web 或 Windows 设备运行项目；正在转交独立终端进行确认，Sourcetree 窗口不等待输入。'
        $payload = @{ Script=$PSCommandPath; Target=$Target; Option=$Option; Value=$Value } | ConvertTo-Json -Compress
        $data = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
        $code = '$p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("'+$data+'"))|ConvertFrom-Json; & $p.Script -Target $p.Target -Option $p.Option -Value $p.Value -Terminal'
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
        Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) | Out-Null
        exit 0
    }
    Write-Host 'Jobs | 🐦打开：运行Flutter项目' -ForegroundColor Red
    Write-Host '用途：选择 Android、Web 或 Windows 设备运行项目。'
    Write-Host '影响：仅所选项目及入口声明的目标；危险写操作另需 YES。日志：%TEMP%\JobsSourceTree*。'
    Write-Host 'Android 模拟器支持启动已有 / 缺失时初始化；确认后可能补齐工具与下载所选镜像。'
    Write-Host '设备用 fzf 上下键及输入筛选，← 返回上一层；Ctrl+C 取消，不自动更换项目 Flutter 版本。'
    if ([Console]::IsInputRedirected) { throw '需要独立交互终端；没有确认不能继续。' }
    [void](Read-Host '按回车继续')
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Scripts/SourceTree.psm1') -Force -DisableNameChecking
    Invoke-JobsSourceTreeAction -Action 'run' -Target $Target -Option $Option -Value $Value
} catch {
    $exitCode=1
    Write-Host ($_.Exception.Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@','$1***@') -ForegroundColor Red
} finally {
    if ($Terminal) { [void](Read-Host ('退出码 '+$exitCode+'；按回车关闭')) }
}
exit $exitCode
