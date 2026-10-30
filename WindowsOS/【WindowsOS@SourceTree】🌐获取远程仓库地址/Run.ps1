# 🌐获取远程仓库地址 | Jobs Windows Sourcetree
# Created by Jobs on 2026年10月28日，星期三.
# 用途：复制所选 Git 远程原始地址到剪贴板；单地址直接执行，多地址转独立终端 fzf；Ctrl+C 取消。
[CmdletBinding()]
param([Parameter(Position=0)][string]$Target, [string]$Option, [string]$Value,
      [switch]$SourceTree, [switch]$Terminal)
$ErrorActionPreference = 'Stop'
$exitCode = 0
try {
    Write-Host 'Jobs | 🌐获取远程仓库地址'
    Write-Host '用途：复制所选 Git 远程原始地址到剪贴板。全部 remote 的 fetch/push 地址去重，单地址直接执行，多地址使用 fzf。'
    Write-Host '影响：剪贴板或默认浏览器；只读 Git，不提交、不推送、不改 Git 配置。日志在系统临时目录 JobsSourceTree*。'
    Write-Host '运行：Sourcetree 无输入等待；需要选择/安装时打开独立终端。终端先回车确认，Ctrl+C 取消。'
    Write-Host '依赖：健康 Git/fzf 复用；缺失时经确认使用 WinGet 安装/修复一次，刷新当前进程 PATH 并复检。'
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '此入口仅支持 Windows，请使用 MacOS 目录。' }
    if (-not $Target) {
        if ($SourceTree) { throw '未收到仓库路径；请在 Sourcetree 动作参数中配置 -Target "$REPO"。' }
        $Target = (Get-Location).Path
    }
    if (-not $SourceTree -or $Terminal) {
        if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { throw '需要独立交互终端；没有确认不能继续。' }
        [void](Read-Host '按回车继续；Ctrl+C 取消')
    }
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'Scripts/SourceTree.psm1') -Force -DisableNameChecking
    Invoke-JobsSourceTreeAction -Action 'remote' -Target $Target -SourceTree:($SourceTree -and -not $Terminal) -EntryScript $PSCommandPath
} catch {
    $exitCode=1
    $safe=$_.Exception.Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@','$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*','$1?[已省略]'
    Write-Host $safe
} finally {
    if ($Terminal -and -not [Console]::IsInputRedirected) { [void](Read-Host ('退出码 '+$exitCode+'；按回车关闭')) }
}
exit $exitCode
