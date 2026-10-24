# ⏬双击下载SourceTree效率脚本 | Jobs Windows Sourcetree
# Created by Jobs on 2026年10月23日，星期五.
# 用途：克隆效率脚本到新目录，保留已有库；终端确认后运行，Ctrl+C 取消。
[CmdletBinding()]
param([Parameter(Position=0)][string]$Target, [string]$Option, [string]$Value,
      [switch]$SourceTree, [switch]$Terminal)
$ErrorActionPreference = 'Stop'
$exitCode = 0
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '此入口仅支持 Windows，请使用 MacOS 目录。' }
    if (-not $Target) { $Target = (Get-Location).Path }
    if ($SourceTree -and -not $Terminal) {
        Write-Host 'Jobs：克隆效率脚本到新目录，保留已有库；正在转交独立终端进行确认，Sourcetree 窗口不等待输入。'
        $payload = @{ Script=$PSCommandPath; Target=$Target; Option=$Option; Value=$Value } | ConvertTo-Json -Compress
        $data = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
        $code = '$p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("'+$data+'"))|ConvertFrom-Json; & $p.Script -Target $p.Target -Option $p.Option -Value $p.Value -Terminal'
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
        Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) | Out-Null
        exit 0
    }
    Write-Host 'Jobs | ⏬双击下载SourceTree效率脚本' -ForegroundColor Red
    Write-Host '用途：克隆效率脚本到新目录，保留已有库。'
    Write-Host '影响：仅所选项目及入口声明的目标；危险写操作另需 YES。日志：%TEMP%\JobsSourceTree*。'
    Write-Host 'Ctrl+C 取消；缺少 SDK/工具时停止，不自动更换项目版本。'
    if ([Console]::IsInputRedirected) { throw '需要独立交互终端；没有确认不能继续。' }
    [void](Read-Host '按回车继续')
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Scripts/SourceTree.psm1') -Force -DisableNameChecking
    Invoke-JobsSourceTreeAction -Action 'download' -Target $Target -Option $Option -Value $Value
} catch {
    $exitCode=1
    Write-Host ($_.Exception.Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@','$1***@') -ForegroundColor Red
} finally {
    if ($Terminal) { [void](Read-Host ('退出码 '+$exitCode+'；按回车关闭')) }
}
exit $exitCode
