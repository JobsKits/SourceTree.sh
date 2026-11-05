# 脚本自述：当前仓库单条线路的 Push 诊断、历史整合、普通推送及 OID 核验。
# Created by Jobs on 2026年11月5日，星期四.
[CmdletBinding()]
param([Parameter(Position=0)][string]$Target,
      [Alias('Remote')][string]$Option,[Alias('Branch')][string]$Value,
      [switch]$Diagnose,[switch]$SourceTree,[switch]$Terminal)
$ErrorActionPreference = 'Stop'
# Sourcetree 输出窗口只启动独立终端，不等待确认或选择。
function Start-JobsPushEntryTerminal {
    $payload = @{ Script=$PSCommandPath; Target=$Target; Option=$Option; Value=$Value; Diagnose=[bool]$Diagnose } | ConvertTo-Json -Compress
    $data = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    $code = '$p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("'+$data+'"))|ConvertFrom-Json; & $p.Script -Target $p.Target -Option $p.Option -Value $p.Value -Diagnose:([bool]$p.Diagnose) -Terminal'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) | Out-Null
}
# 先展示源码内固定自述，确认前不创建日志或修改仓库。
function Show-JobsPushEntryIntro {
    $lines = @('Jobs | 📥修复Git无法Push',
        '用途：诊断当前仓库的一条明确推送线路；远端领先则快进，分叉则保留双方提交合并，再普通推送和读回核验。',
        '影响：只处理当前已有工作分支，不递归父子仓；需要干净工作树，可能产生 merge 提交。',
        '保护：不暂存、不 stash、不重写历史、不强推；冲突、锁、快照和平台权限限制保留并给出下一步。',
        '只诊断：-Diagnose 仅做本地检查与远端查询，不 fetch/merge/push；日志位于 %TEMP%/JobsSourceTree*。',
        '取消：Ctrl+C；多个远端使用 fzf 选择，或显式传 -Remote / -Branch。')
    $plain = $SourceTree -or [Console]::IsOutputRedirected -or [Environment]::GetEnvironmentVariable('NO_COLOR') -or $env:TERM -eq 'dumb'
    for ($i=0;$i -lt $lines.Count;$i++) {
        if ($plain) { Write-Host $lines[$i] }
        elseif ($i -eq 0) { Write-Host $lines[$i] -ForegroundColor Red }
        else { Write-Host $lines[$i] -ForegroundColor Blue }
    }
}
# 承接确认、参数和失败状态，结束时保留终端结果。
function Invoke-JobsPushEntry {
    $entryExit = 0
    try {
        Show-JobsPushEntryIntro
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '此双击入口仅支持 Windows；MacOS 使用对应 .command，模块隔离测试可在 pwsh 运行。' }
        if (-not $Target) { $Target = (Get-Location).Path }
        if ($SourceTree -and -not $Terminal) {
            Write-Host '正在打开独立终端确认；Sourcetree 动作进程不等待输入。'
            Start-JobsPushEntryTerminal
            return 0
        }
        if ([Console]::IsInputRedirected) { throw '需要可交互终端进行确认；没有确认不继续。' }
        [void](Read-Host '按回车确认以上范围并继续；Ctrl+C 取消')
        Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Scripts/SourceTree.psm1') -Force -DisableNameChecking
        Invoke-JobsSourceTreeAction -Action 'push-repair' -Target $Target -Option $Option -Value $Value -Diagnose:$Diagnose
    } catch {
        $entryExit = 1
        $safe = $_.Exception.Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@','$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*','$1?[已省略]'
        Write-Host $safe
    } finally {
        if ($Terminal) { [void](Read-Host ('退出码 '+$entryExit+'；按回车关闭')) }
    }
    return $entryExit
}
exit (Invoke-JobsPushEntry)
