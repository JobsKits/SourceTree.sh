# 隔离真实 Git 验证，不访问托管服务或用户项目。
param([string]$ModulePath=(Join-Path $PSScriptRoot '../Scripts/SourceTree.psm1'))
$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('jobs-st-tests-'+[guid]::NewGuid().ToString('N'))
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -and $root.StartsWith('/var/') -and (Test-Path -LiteralPath '/private/var')){$root='/private'+$root}
[void][IO.Directory]::CreateDirectory($root)
$environmentKeys=@('GIT_CONFIG_NOSYSTEM','GIT_CONFIG_GLOBAL','GIT_CONFIG_COUNT','GIT_CONFIG_KEY_0','GIT_CONFIG_VALUE_0','GIT_ALLOW_PROTOCOL','GIT_TERMINAL_PROMPT')
$savedEnvironment=@{}
foreach($key in $environmentKeys){$savedEnvironment[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
$env:GIT_CONFIG_NOSYSTEM='1';$env:GIT_CONFIG_GLOBAL=Join-Path $root 'empty-global-config'
$env:GIT_CONFIG_COUNT='0';$env:GIT_CONFIG_KEY_0=$null;$env:GIT_CONFIG_VALUE_0=$null
$env:GIT_ALLOW_PROTOCOL='file';$env:GIT_TERMINAL_PROMPT='0'
$script:passed=0
function Assert-Check {param($Condition,$Message) if(-not $Condition){throw $Message};$script:passed++;Write-Host "PASS $Message"}
function Invoke-TestGit {
    param([string]$Repo,[string[]]$GitArgs)
    $previousPreference=$ErrorActionPreference
    try {
        # PowerShell 5.1 将 Git 的提示性 stderr 包装为错误，实际成败以退出码判定。
        $ErrorActionPreference='Continue'
        & git -C $Repo @GitArgs 2>&1|Out-Null
        $code=$LASTEXITCODE
    } finally { $ErrorActionPreference=$previousPreference }
    if($code -ne 0){throw ('git failed: '+($GitArgs -join ' '))}
}
try {
    $module=Import-Module $ModulePath -Force -DisableNameChecking -PassThru
    $unicodeRepo=Join-Path $root '中文仓库 & space [编码]'
    [void][IO.Directory]::CreateDirectory($unicodeRepo)
    Invoke-TestGit $unicodeRepo @('init','-b','main')
    $expectedRoot=(Get-Item -LiteralPath $unicodeRepo).FullName
    foreach($codePage in @(437,936)) {
        $encodingCheck=& $module {
            param($Repository,$CodePage)
            $savedConsoleEncoding=[Console]::OutputEncoding
            $savedOutputEncoding=$OutputEncoding
            try {
                $OutputEncoding=[Text.Encoding]::GetEncoding(1252)
                $expectedOutputEncoding=$OutputEncoding
                [Console]::OutputEncoding=[Text.Encoding]::GetEncoding($CodePage)
                $resolved=Resolve-JobsRepository $Repository
                $successConsoleRestored=[Console]::OutputEncoding.CodePage -eq $CodePage
                $successOutputRestored=[object]::ReferenceEquals($OutputEncoding,$expectedOutputEncoding)
                $failed=$false
                try { Invoke-JobsGit $Repository @('jobs-encoding-invalid-command') -Quiet | Out-Null }
                catch { $failed=$true }
                $failureConsoleRestored=[Console]::OutputEncoding.CodePage -eq $CodePage
                $failureOutputRestored=[object]::ReferenceEquals($OutputEncoding,$expectedOutputEncoding)
                $allowed=Invoke-JobsGit $Repository @('jobs-encoding-invalid-command') -Quiet -AllowFailure
                [pscustomobject]@{
                    Root=$resolved
                    SuccessRestored=($successConsoleRestored -and $successOutputRestored)
                    FailureRaised=$failed
                    FailureRestored=($failureConsoleRestored -and $failureOutputRestored)
                    AllowedFailure=($allowed.Code -ne 0)
                    AllowedRestored=([Console]::OutputEncoding.CodePage -eq $CodePage -and [object]::ReferenceEquals($OutputEncoding,$expectedOutputEncoding))
                }
            } finally {
                $OutputEncoding=$savedOutputEncoding
                [Console]::OutputEncoding=$savedConsoleEncoding
            }
        } $unicodeRepo $codePage
        Assert-Check ($encodingCheck.Root -ceq $expectedRoot) ("CP$codePage native Git preserves Unicode repository path")
        Assert-Check $encodingCheck.SuccessRestored ("CP$codePage restores both encodings after success")
        Assert-Check $encodingCheck.FailureRaised ("CP$codePage native Git failure propagates")
        Assert-Check $encodingCheck.FailureRestored ("CP$codePage restores both encodings after failure")
        Assert-Check ($encodingCheck.AllowedFailure -and $encodingCheck.AllowedRestored) ("CP$codePage allowed failure preserves exit code and encodings")
    }
    $project=Join-Path $root '中文 space [x]';[void][IO.Directory]::CreateDirectory((Join-Path $project 'lib'))
    $file=Join-Path $project 'lib/demo.dart'
    $source="// Created by Jobs`nimport 'package:demo/%E4%B8%AD%E6%96%87.dart';`nconst x='package:x/%E4%B8%AD';`nexport 'package:x/%2F%E4%B8%AD.dart';`n"
    [IO.File]::WriteAllText($file,$source,(New-Object Text.UTF8Encoding($false)))
    & $module {param($p) Repair-JobsFlutterImports $p} $project
    $changed=[IO.File]::ReadAllText($file)
    Assert-Check ($changed.Contains('中文.dart')) 'Unicode import decoded'
    Assert-Check ($changed.Contains("const x='package:x/%E4%B8%AD'")) 'normal string untouched'
    Assert-Check ($changed.Contains('%2F中.dart')) 'ASCII escape retained'
    $backup=@(Get-ChildItem -LiteralPath (Join-Path $project '.import_backup') -Recurse -Filter demo.dart)
    Assert-Check ([IO.File]::ReadAllText($backup[0].FullName) -ceq $source) 'exact source backup'
    $vendor=Join-Path $project 'lib/vendor';[void][IO.Directory]::CreateDirectory($vendor)
    [IO.File]::WriteAllText((Join-Path $vendor 'x.dart'),$source)
    & $module {param($p) Repair-JobsFlutterImports $p} $project
    Assert-Check ([IO.File]::ReadAllText((Join-Path $vendor 'x.dart')) -ceq $source) 'vendor skipped'
    $repo=Join-Path $root 'repo [a]';[void][IO.Directory]::CreateDirectory($repo)
    Invoke-TestGit $repo @('init','-b','main');Invoke-TestGit $repo @('config','user.name','Jobs Test');Invoke-TestGit $repo @('config','user.email','jobs-test@example.invalid')
    [IO.File]::WriteAllText((Join-Path $repo 'one.txt'),'one');Invoke-TestGit $repo @('add','.');Invoke-TestGit $repo @('commit','-m','first')
    $first=(& git -C $repo rev-parse HEAD).Trim()
    $bare1=Join-Path $root 'upstream.git';$bare2=Join-Path $root 'mirror.git'
    Invoke-TestGit $root @('init','--bare','-b','main',$bare1)
    Invoke-TestGit $root @('init','--bare','-b','main',$bare2)
    Invoke-TestGit $repo @('remote','add','origin',$bare1);Invoke-TestGit $repo @('remote','add','gitee',$bare2)
    Invoke-TestGit $repo @('push','-u','origin','main');Invoke-TestGit $repo @('push','gitee','main:gitee')
    [IO.File]::WriteAllText((Join-Path $repo 'one.txt'),'two');Invoke-TestGit $repo @('add','.');Invoke-TestGit $repo @('commit','-m','local')
    & $module {param($r) Reset-JobsCommit $r 'soft' ''} $repo
    Assert-Check ((& git -C $repo rev-parse HEAD).Trim() -ceq $first) 'soft returns upstream'
    Assert-Check ([IO.File]::ReadAllText((Join-Path $repo 'one.txt')) -ceq 'two') 'soft retains working content'
    Assert-Check ((& git -C $repo diff --cached --name-only) -eq 'one.txt') 'soft retains staging'
    & $module {function script:Read-Host {param($Prompt) 'YES'}}
    & $module {param($r) Push-JobsRepositoryTree $r} $repo
    $head=(& git -C $repo rev-parse HEAD).Trim()
    Assert-Check ((& git --git-dir=$bare1 rev-parse refs/heads/main).Trim() -ceq $head) 'origin main same HEAD'
    Assert-Check ((& git --git-dir=$bare2 rev-parse refs/heads/gitee).Trim() -ceq $head) 'gitee branch same HEAD'
    Assert-Check ((@(& git -C $repo for-each-ref --format='%(refname:short)' refs/heads) -join ',') -ceq 'main') 'no extra local branches'
    Assert-Check (-not(Test-Path -LiteralPath (Join-Path $repo '.git/jobs-windows-push-checkpoint.json'))) 'checkpoint cleared on success'
    # 本地 bare hook 只在隔离 Unix 夹具可用；Windows 仍执行其它原生检查。
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
        $hook=Join-Path $bare1 'hooks/pre-receive'
        [IO.File]::WriteAllText($hook,"#!/bin/sh`nexit 1`n",(New-Object Text.UTF8Encoding($false)))
        & chmod +x $hook
        [IO.File]::WriteAllText((Join-Path $repo 'one.txt'),'three')
        $failed=$false
        try{& $module {param($r) Push-JobsRepositoryTree $r} $repo}catch{$failed=$true}
        Assert-Check $failed 'second remote failure propagated'
        $pending=Join-Path $repo '.git/jobs-windows-push-checkpoint.json'
        Assert-Check (Test-Path -LiteralPath $pending) 'checkpoint exists after first repository failure'
        $prepared=(& git -C $repo rev-parse HEAD).Trim()
        Remove-Item -LiteralPath $hook
        & $module {function script:Read-Host {param($Prompt) if($Prompt -match '中断检查点'){'R'}else{'YES'}}}
        & $module {param($r) Push-JobsRepositoryTree $r} $repo
        Assert-Check ((& git -C $repo rev-parse HEAD).Trim() -ceq $prepared) 'resume reuses prepared commit'
        Assert-Check ((& git --git-dir=$bare1 rev-parse refs/heads/main).Trim() -ceq $prepared) 'resume completes failed remote'
    }
    Invoke-TestGit $repo @('config','remote.origin.pushurl',$bare2)
    $beforeReject=(& git -C $repo rev-parse HEAD).Trim()
    $rejected=$false
    try{& $module {param($r) Push-JobsRepositoryTree $r} $repo}catch{$rejected=$true}
    Assert-Check $rejected 'different pushurl rejected'
    Assert-Check ((& git -C $repo rev-parse HEAD).Trim() -ceq $beforeReject) 'pushurl rejection before commit'
    $child=Join-Path $repo 'nested child [b]'
    [void][IO.Directory]::CreateDirectory($child)
    Invoke-TestGit $child @('init','-b','main')
    Invoke-TestGit $child @('config','user.name','Jobs Test')
    Invoke-TestGit $child @('config','user.email','jobs-test@example.invalid')
    Invoke-TestGit $child @('commit','--allow-empty','-m','child')
    $moduleFile=Join-Path $repo '.gitmodules'
    Invoke-TestGit $repo @('config','--file',$moduleFile,'submodule.child.path','nested child [b]')
    $queue=@(& $module {param($r) Get-JobsRepositoryQueue $r} $repo)
    Assert-Check ($queue.Count -eq 2 -and $queue[0] -ceq $child -and $queue[1] -ceq $repo) 'nested repositories ordered child before parent'
    Write-Host "$script:passed checks passed"
} finally {
    foreach($key in $environmentKeys){[Environment]::SetEnvironmentVariable($key,$savedEnvironment[$key],'Process')}
    Remove-Item -LiteralPath $root -Recurse -Force
}
