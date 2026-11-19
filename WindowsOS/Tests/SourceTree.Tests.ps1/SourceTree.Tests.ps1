# 隔离真实 Git 验证，不访问托管服务或用户项目。
param([string]$ModulePath=(Join-Path $PSScriptRoot '../../Scripts/SourceTree.psm1'))
# 仅用于终端URL展示，不改变调用者数据。
function Test-JobsEnterChoiceColor {
    param([Collections.IDictionary]$Capabilities = $null)
    if ($null -eq $Capabilities) {
        try {
            $environment = [Environment]::GetEnvironmentVariables('Process')
            $Capabilities = @{ HostName = $Host.Name; InputRedirected = [Console]::IsInputRedirected; OutputRedirected = [Console]::IsOutputRedirected;
                               ErrorRedirected = [Console]::IsErrorRedirected; NoColorPresent = $environment.Contains('NO_COLOR');
                               PlainOutput = $env:PLAIN_OUTPUT; Term = $env:TERM; Windows = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT); VirtualTerminal = $false; SourceTree = ($env:IS_SOURCETREE_RUNTIME -eq '1') }
            if ($null -ne $Host.UI.PSObject.Properties['SupportsVirtualTerminal']) { $Capabilities.VirtualTerminal = $Host.UI.SupportsVirtualTerminal }
            foreach ($key in $environment.Keys) { if ([string]$key -match '^(?i:SOURCE_?TREE)') { $Capabilities.SourceTree = $true; break } }
        } catch { return $false }
    }
    return ($Capabilities.HostName -eq 'ConsoleHost' -and -not $Capabilities.InputRedirected -and -not $Capabilities.OutputRedirected -and
            -not $Capabilities.ErrorRedirected -and -not $Capabilities.NoColorPresent -and $Capabilities.PlainOutput -ne '1' -and
            $Capabilities.Term -ine 'dumb' -and (-not [string]::IsNullOrEmpty($Capabilities.Term) -or ($Capabilities.Contains('Windows') -and $Capabilities.Windows)) -and -not $Capabilities.SourceTree -and $Capabilities.VirtualTerminal)
}
# 仅用于终端URL展示，不改变调用者数据。
function Get-JobsUrlRanges {
    param([string]$Text)
    $pattern = '[A-Za-z][A-Za-z0-9+.-]*://[^\s<>"''\x1b]+'
    $punctuation = '，。；：！？、（）【】《》「」『』“”‘’'
    $offset = 0
    while ($offset -lt $Text.Length) {
        $match = [regex]::Match($Text.Substring($offset), $pattern)
        if (-not $match.Success) { break }
        $start = $offset + $match.Index
        $url = $match.Value
        foreach ($mark in $punctuation.ToCharArray()) {
            $at = $url.IndexOf($mark)
            if ($at -ge 0) { $url = $url.Substring(0, $at) }
        }
        while ($url.Length) {
            $last = $url.Substring($url.Length - 1, 1)
            $unmatched = $false
            foreach ($pair in @(@('(', ')'), @('[', ']'), @('{', '}'))) {
                if ($last -eq $pair[1] -and ([regex]::Matches($url, [regex]::Escape($pair[1]))).Count -gt ([regex]::Matches($url, [regex]::Escape($pair[0]))).Count) { $unmatched = $true }
            }
            if ('. , ; : ! ?'.Split(' ') -contains $last -or $unmatched) { $url = $url.Substring(0, $url.Length - 1) }
            else { break }
        }
        [pscustomobject]@{ Start = $start; End = $start + $url.Length }
        $offset = $start + $url.Length
    }
}
# 仅用于终端URL展示，不改变调用者数据。
function Format-JobsUrlText {
    param([AllowEmptyString()][string]$Text, [switch]$Color)
    $control = '\x1b\][^\x1b\x07]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]'
    $sgr = '\x1b\[[0-9;:]*m'
    $value = [regex]::Replace($Text, $control, {
        param($match)
        if ($Color -and $match.Value -match ('^' + $sgr + '$')) { return $match.Value }
        return ''
    })
    if (-not $Color) { return $value }
    $styles = @{}; $visible = New-Object Text.StringBuilder; $offset = 0
    foreach ($match in [regex]::Matches($value, $sgr)) {
        [void]$visible.Append($value.Substring($offset, $match.Index - $offset))
        $index = $visible.Length
        if (-not $styles.ContainsKey($index)) { $styles[$index] = '' }
        $styles[$index] += $match.Value
        $offset = $match.Index + $match.Length
    }
    [void]$visible.Append($value.Substring($offset))
    $plain = $visible.ToString(); $starts = @{}; $ends = @{}
    foreach ($range in @(Get-JobsUrlRanges $plain)) { $starts[$range.Start] = $true; $ends[$range.End - 1] = $true }
    $escape = [string][char]27; $active = ''; $inUrl = $false; $output = New-Object Text.StringBuilder
    for ($index = 0; $index -le $plain.Length; $index++) {
        if ($styles.ContainsKey($index)) {
            $tokens = $styles[$index]; [void]$output.Append($tokens)
            foreach ($match in [regex]::Matches($tokens, $sgr)) {
                $token = $match.Value; $code = $token.Substring(2, $token.Length - 3)
                $fields = $code.Split(';'); $reset = $code -eq ''
                for ($item = 0; $item -lt $fields.Count; $item++) {
                    if ($fields[$item] -eq '0') { $reset = $true }
                    if (@('38', '48', '58') -contains $fields[$item] -and $item + 1 -lt $fields.Count) {
                        if ($fields[$item + 1] -eq '2') { $item += 4 }
                        elseif ($fields[$item + 1] -eq '5') { $item += 2 }
                    }
                }
                if ($reset) { $active = '' }
                $active += $token
            }
            if ($inUrl) { [void]$output.Append($escape + '[32;4m') }
        }
        if ($index -eq $plain.Length) { break }
        if ($starts.ContainsKey($index)) { [void]$output.Append($escape + '[32;4m'); $inUrl = $true }
        [void]$output.Append($plain[$index])
        if ($ends.ContainsKey($index)) { [void]$output.Append($escape + '[0m' + $active); $inUrl = $false }
    }
    return $output.ToString()
}
# 仅用于终端URL展示，不改变调用者数据。
function Get-JobsDisplayBaseStyle {
    param([Collections.IDictionary]$Parameters)
    $codes = @{ Black=30; DarkBlue=34; DarkGreen=32; DarkCyan=36; DarkRed=31; DarkMagenta=35; DarkYellow=33; Gray=37; DarkGray=90; Blue=94; Green=92; Cyan=96; Red=91; Magenta=95; Yellow=93; White=97 }
    $style = ''; $escape = [string][char]27
    if ($Parameters.ContainsKey('ForegroundColor')) { $style += $escape + '[' + $codes[[string]$Parameters.ForegroundColor] + 'm' }
    if ($Parameters.ContainsKey('BackgroundColor')) { $style += $escape + '[' + ($codes[[string]$Parameters.BackgroundColor] + 10) + 'm' }
    return $style
}
# 单次绘制URL并保存纯文本信息记录，兼容原Write-Host参数。
function Write-JobsUrlText {
    [CmdletBinding()]
    param([Parameter(Position=0)][AllowNull()][object]$Object, [switch]$NoNewline, [ConsoleColor]$ForegroundColor, [ConsoleColor]$BackgroundColor, [object]$Separator = ' ')
    $text = if ($Object -is [array]) { $Object -join [string]$Separator } else { [string]$Object }
    $plain = Format-JobsUrlText $text
    if (-not (Test-JobsEnterChoiceColor)) { Write-Host $plain -NoNewline:$NoNewline; return }
    $baseStyle = Get-JobsDisplayBaseStyle $PSBoundParameters
    $rendered = Format-JobsUrlText ($baseStyle + $text + ([string][char]27+'[0m')) -Color
    $message = New-Object Management.Automation.HostInformationMessage
    $message.Message = $plain
    $message.NoNewLine = [bool]$NoNewline
    if ($PSBoundParameters.ContainsKey('ForegroundColor')) { $message.ForegroundColor = $ForegroundColor }
    if ($PSBoundParameters.ContainsKey('BackgroundColor')) { $message.BackgroundColor = $BackgroundColor }
    Write-Information -MessageData $message -Tags 'JobsDisplay' -InformationAction SilentlyContinue
    [Console]::Write($rendered)
    if (-not $NoNewline) { [Console]::WriteLine() }
}


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
function Assert-Check {param($Condition,$Message) if(-not $Condition){throw $Message};$script:passed++;Write-JobsUrlText "PASS $Message"}
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
    # 同时保留旧 Run.ps1 菜单和新同名源码入口的用户标题，不写真实菜单。
    $windowsRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $installer=Join-Path $windowsRoot 'Install-Menu.ps1/Install-Menu.ps1'
    $tokens=$null;$parseErrors=$null
    $installerAst=[Management.Automation.Language.Parser]::ParseFile($installer,[ref]$tokens,[ref]$parseErrors)
    $mergeDefinition=$installerAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Merge-JobsWindowsMenu'},$true)
    Invoke-Expression $mergeDefinition.Extent.Text
    $menuRoot=Join-Path $root '菜单 source layout'
    [void][IO.Directory]::CreateDirectory($menuRoot)
    $actionJson=[IO.File]::ReadAllText((Join-Path $windowsRoot 'actions.json'))
    [IO.File]::WriteAllText((Join-Path $menuRoot 'actions.json'),$actionJson)
    $menuActions=@($actionJson|ConvertFrom-Json)
    foreach($action in $menuActions){
        $fixtureAction=Join-Path $menuRoot $action.Script
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $fixtureAction))
        [IO.File]::WriteAllText($fixtureAction,'# fixture only; never executed')
    }
    $legacyLeaf=($menuActions[0].Script -split '/')[0] -replace '\.ps1$',''
    $newPath=$menuActions[1].Script.Replace('/','\')
    $existingMenu='<ArrayOfCustomAction><CustomAction><Caption>保留旧入口标题</Caption><Parameters>-File &quot;C:\old\'+$legacyLeaf+'\Run.ps1&quot;</Parameters></CustomAction><CustomAction><Caption>保留新入口标题</Caption><Parameters>-File &quot;D:\new\'+$newPath+'&quot;</Parameters></CustomAction><CustomAction><Caption>手工未知动作</Caption><Parameters>-File C:\custom\Unknown.ps1</Parameters></CustomAction></ArrayOfCustomAction>'
    $previousSystemRoot=$env:SystemRoot
    try {
        $env:SystemRoot=$menuRoot
        [xml]$mergedMenu=Merge-JobsWindowsMenu $existingMenu $menuRoot
        $nodes=@($mergedMenu.SelectNodes('/ArrayOfCustomAction/CustomAction'))
        Assert-Check ($nodes.Count -eq $menuActions.Count+1) 'menu migrates legacy and new entry without duplicates'
        Assert-Check (@($nodes|Where-Object {$_.Caption -ceq '保留旧入口标题'}).Count -eq 1) 'menu preserves legacy user caption'
        Assert-Check (@($nodes|Where-Object {$_.Caption -ceq '保留新入口标题'}).Count -eq 1) 'menu preserves new-layout user caption'
        Assert-Check (@($nodes|Where-Object {$_.Caption -ceq '手工未知动作'}).Count -eq 1) 'menu preserves unknown action'
        [xml]$repeatedMenu=Merge-JobsWindowsMenu $mergedMenu.OuterXml $menuRoot
        Assert-Check ($repeatedMenu.OuterXml -ceq $mergedMenu.OuterXml) 'menu migration is idempotent'
        $firstNode=@($nodes|Where-Object {$_.Caption -ceq '保留旧入口标题'})[0]
        Assert-Check ($firstNode.Parameters.Contains($menuActions[0].Script.Replace('/','\')) -or $firstNode.Parameters.Contains($menuActions[0].Script)) 'legacy action now targets packaged source'
        $duplicateMenu=$existingMenu.Replace('</ArrayOfCustomAction>','<CustomAction><Caption>重复旧动作</Caption><Parameters>-File &quot;C:\other\'+$legacyLeaf+'\Run.ps1&quot;</Parameters></CustomAction></ArrayOfCustomAction>')
        $duplicateRejected=$false
        try{[void](Merge-JobsWindowsMenu $duplicateMenu $menuRoot)}catch{$duplicateRejected=$true}
        Assert-Check $duplicateRejected 'duplicate action identities fail without guessing'
    } finally {
        $env:SystemRoot=$previousSystemRoot
    }
    Write-JobsUrlText "$script:passed checks passed"
} finally {
    foreach($key in $environmentKeys){[Environment]::SetEnvironmentVariable($key,$savedEnvironment[$key],'Process')}
    Remove-Item -LiteralPath $root -Recurse -Force
}
