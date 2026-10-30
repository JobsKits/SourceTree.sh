#requires -Version 5.1
# 远程地址枚举、分流与依赖链隔离验证；不安装、不联网、不启动真实浏览器。
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('JobsSourceTreeRemote-'+[guid]::NewGuid().ToString('N'))
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -and $fixture.StartsWith('/var/') -and (Test-Path -LiteralPath '/private/var')) { $fixture='/private'+$fixture }
[void][IO.Directory]::CreateDirectory($fixture)
$counter=@{Value=0}
# 每项断言保留具体业务边界。
function Assert-Check($Condition,[string]$Label) { if (-not $Condition) { throw $Label };$counter.Value++;Write-Host "PASS $Label" }
# 只运行临时仓库的本地 Git 配置命令。
function Invoke-TestGit {
    param([string[]]$Arguments)
    $previous=$ErrorActionPreference
    try { $ErrorActionPreference='Continue';& git -C $fixture @Arguments 2>&1 | Out-Null;$code=$LASTEXITCODE }
    finally { $ErrorActionPreference=$previous }
    if ($code -ne 0) { throw '临时 Git 配置失败。' }
}
$repositoryKeys=@('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_INDEX_FILE','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES','GIT_PREFIX','GIT_NAMESPACE','GIT_CEILING_DIRECTORIES','GIT_DISCOVERY_ACROSS_FILESYSTEM','GIT_SUPER_PREFIX')
$environmentKeys=$repositoryKeys+@('GIT_CONFIG_NOSYSTEM','GIT_CONFIG_GLOBAL','GIT_CONFIG_COUNT','FZF_DEFAULT_OPTS','FZF_DEFAULT_OPTS_FILE','FZF_DEFAULT_COMMAND','FZF_DEFAULT_COMMAND_FILE','PATH')
$saved=@{}
foreach ($key in $environmentKeys) { $saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process') }
$env:GIT_CONFIG_NOSYSTEM='1';$env:GIT_CONFIG_GLOBAL=Join-Path $fixture 'empty-config';$env:GIT_CONFIG_COUNT='0'
try {
    Invoke-TestGit @('init','-b','main')
    $module=Import-Module (Join-Path $root 'Scripts/SourceTree.psm1') -Force -PassThru -DisableNameChecking
    $failed=$false
    try { & $module {param($r) Get-JobsRemoteAddresses $r} $fixture | Out-Null } catch { $failed=$true }
    Assert-Check $failed '无 remote 停止'
    $url='https://user:secret@example.invalid/team/repo.git?token=private#fragment'
    Invoke-TestGit @('remote','add','origin',$url)
    $addresses=@(& $module {param($r) Get-JobsRemoteAddresses $r} $fixture)
    Assert-Check ($addresses.Count -eq 1 -and $addresses[0].Url -ceq $url) '单fetch及隐式push按原始URL合并'
    Assert-Check ($addresses[0].Labels.Count -eq 2) '合并行保留fetch与push来源'
    Invoke-TestGit @('config','--add','remote.origin.url','git@example.invalid:team/second.git')
    Invoke-TestGit @('config','--add','remote.origin.pushurl','ssh://git@example.invalid/team/push.git')
    Invoke-TestGit @('remote','add','mirror',$url)
    $addresses=@(& $module {param($r) Get-JobsRemoteAddresses $r} $fixture)
    Assert-Check ($addresses.Count -eq 3) '全部remote、多fetch及独立push URL均被枚举'
    Assert-Check (@($addresses | Where-Object Url -CEQ $url).Count -eq 1) '跨remote原始URL去重'
    Assert-Check (($addresses | Where-Object Url -CEQ $url).Labels.Count -eq 3) '去重后保留全部来源标签'
    $before=[IO.File]::ReadAllBytes((Join-Path $fixture '.git/config'))
    $conversions=@{
        'git@github.com:JobsKits/SourceTree.sh.git'='https://github.com/JobsKits/SourceTree.sh'
        'ssh://git@gitlab.example.invalid:22/group/sub/repo.git'='https://gitlab.example.invalid/group/sub/repo'
        'git://git.example.invalid:9418/team/repo.git'='https://git.example.invalid/team/repo'
        'https://user:secret@example.invalid:8443/a/b.git?q=private#fragment'='https://example.invalid:8443/a/b'
        'http://example.invalid:8080/a/b.git/'='http://example.invalid:8080/a/b'
        'git@[2001:db8::1]:team/repo.git'='https://[2001:db8::1]/team/repo'
    }
    foreach ($source in $conversions.Keys) {
        $actual=& $module {param($u) ConvertTo-JobsRemoteWebUrl $u} $source
        Assert-Check ($actual -ceq $conversions[$source]) ('网页转换 '+$source)
    }
    foreach ($source in @('file:///tmp/repo.git','javascript:alert(1)','data:text/html,x','ext::git x','C:/repo.git','../repo.git','/tmp/repo.git','ssh://git@example.invalid:2222/team/repo.git','git://example.invalid:1234/team/repo.git','https://example.invalid/')) {
        $failed=$false
        try { & $module {param($u) ConvertTo-JobsRemoteWebUrl $u} $source | Out-Null } catch { $failed=$true }
        Assert-Check $failed ('拒绝不安全或不明确的网页 '+$source)
    }
    # 模拟 fzf 返回值，记录展示输入与环境，不接触剪贴板。
    $env:JOBS_REMOTE_TEST_ROWS=Join-Path $fixture 'rows.txt';$env:JOBS_REMOTE_TEST_CODE='0'
    $env:FZF_DEFAULT_OPTS='--bind=start:execute(echo unsafe)';$env:FZF_DEFAULT_OPTS_FILE='fixture';$env:FZF_DEFAULT_COMMAND='fixture'
    & $module {
        function script:Assert-JobsRemoteTerminal {}
        function script:Ensure-JobsRemoteTool {param($Name,$Directory) 'fake-fzf'}
        function script:Invoke-JobsRemoteFzf {
            param($Fzf,$Rows)
            $Rows | Set-Content -LiteralPath $env:JOBS_REMOTE_TEST_ROWS -Encoding UTF8
            if ($env:FZF_DEFAULT_OPTS -or $env:FZF_DEFAULT_OPTS_FILE -or $env:FZF_DEFAULT_COMMAND) { throw '默认选项没有隔离' }
            $result=@()
            if ($env:JOBS_REMOTE_TEST_CODE -eq '0') { if ($env:JOBS_REMOTE_TEST_INVALID -eq '1') { $result=@('unknown') } else { $result=@($Rows[1]) } }
            [pscustomobject]@{Code=[int]$env:JOBS_REMOTE_TEST_CODE;Rows=$result}
        }
    }
    $selected=& $module {param($a,$r) Select-JobsRemoteAddress $a $r} $addresses $fixture
    Assert-Check ($selected.Url -ceq $addresses[1].Url) 'fzf按返回原行定位正确地址'
    $rows=[IO.File]::ReadAllText($env:JOBS_REMOTE_TEST_ROWS)
    Assert-Check ($rows -notmatch 'user:secret|token=private|#fragment') 'fzf和日志展示不含凭据或查询内容'
    Assert-Check ($env:FZF_DEFAULT_OPTS -ceq '--bind=start:execute(echo unsafe)' -and $env:FZF_DEFAULT_COMMAND -ceq 'fixture') 'fzf后恢复原进程选项'
    foreach ($code in @('1','130')) {
        $env:JOBS_REMOTE_TEST_CODE=$code
        $selected=& $module {param($a,$r) Select-JobsRemoteAddress $a $r} $addresses $fixture
        Assert-Check ($null -eq $selected) ('fzf取消/空选 '+$code)
    }
    foreach ($code in @('2','0')) {
        $env:JOBS_REMOTE_TEST_CODE=$code;$env:JOBS_REMOTE_TEST_INVALID='1';$failed=$false
        try { & $module {param($a,$r) Select-JobsRemoteAddress $a $r} $addresses $fixture | Out-Null } catch { $failed=$true }
        Assert-Check $failed ('fzf失败/未知选项停止 '+$code)
    }
    foreach ($source in @('ssh://user:secret@example.invalid/a.git?q=private#fragment','git://user:secret@example.invalid/a.git?q=private#fragment')) {
        $safe=& $module {param($u) Protect-JobsRemoteText $u} $source
        Assert-Check ($safe -notmatch 'user:secret|private|fragment') 'SSH/git查询和片段脱敏'
    }
    Invoke-TestGit @('config','--add','remote.origin.url',"https://example.invalid/a.git`nhttps://example.invalid/injected.git")
    $failed=$false
    try { & $module {param($r) Get-JobsRemoteAddresses $r} $fixture | Out-Null } catch { $failed=$true }
    Assert-Check $failed 'URL配置换行不能伪造成多个合法候选'
    Invoke-TestGit @('config','--unset-all','remote.origin.url','https://example.invalid/a.git')
    # 在独立模块实例中模拟分流及外部效果。
    Remove-Module $module
    $module=Import-Module (Join-Path $root 'Scripts/SourceTree.psm1') -Force -PassThru -DisableNameChecking
    $state=@{Launch=0;Copy=0;Open=0;Pick=0;MissingGit=$false;Addresses=@($addresses[0]);Cancel=$false;Copied='';Opened=''}
    & $module {
        param($state,$git)
        $script:State=$state;$script:HealthyGit=$git
        function script:Find-JobsRemoteTool {param($Name,$Directory) if (-not $script:State.MissingGit) { $script:HealthyGit } }
        function script:Start-JobsRemoteTerminal {param($EntryScript,$Target) $script:State.Launch++}
        function script:Get-JobsRemoteAddresses {param($Repository) $script:State.Addresses}
        function script:Select-JobsRemoteAddress {param($Addresses,$Directory) $script:State.Pick++;if (-not $script:State.Cancel) { $Addresses[-1] }}
        function script:Set-Clipboard {param($Value,$ErrorAction) $script:State.Copy++;$script:State.Copied=$Value}
        function script:Start-Process {param($FilePath,$ErrorAction) $script:State.Open++;$script:State.Opened=$FilePath}
    } $state @(Get-Command git -CommandType Application)[0].Source
    & $module {param($r) Invoke-JobsRemoteAddress $r -SourceTree -EntryScript 'fixture.ps1'} $fixture
    Assert-Check ($state.Copy -eq 1 -and $state.Copied -ceq $url -and $state.Launch -eq 0 -and $state.Pick -eq 0) '单地址Sourcetree直接复制原值，无终端无fzf'
    & $module {param($r) Invoke-JobsRemoteAddress $r -Open -SourceTree -EntryScript 'fixture.ps1'} $fixture
    Assert-Check ($state.Open -eq 1 -and $state.Opened -ceq 'https://example.invalid/team/repo' -and $state.Launch -eq 0) '单地址Sourcetree直接打开脱敏网页'
    $state.Addresses=$addresses
    & $module {param($r) Invoke-JobsRemoteAddress $r -SourceTree -EntryScript 'fixture.ps1'} $fixture
    Assert-Check ($state.Launch -eq 1 -and $state.Copy -eq 1 -and $state.Pick -eq 0) '多地址Sourcetree只转交终端'
    & $module {param($r) Invoke-JobsRemoteAddress $r -Open} $fixture
    Assert-Check ($state.Pick -eq 1 -and $state.Open -eq 2) '终端选择后只打开所选地址'
    $state.Cancel=$true
    & $module {param($r) Invoke-JobsRemoteAddress $r} $fixture
    Assert-Check ($state.Copy -eq 1 -and $state.Open -eq 2) '取消选择没有剪贴板或浏览器副作用'
    $state.MissingGit=$true
    & $module {param($r) Invoke-JobsRemoteAddress $r -SourceTree -EntryScript 'fixture.ps1'} $fixture
    Assert-Check ($state.Launch -eq 2) 'Sourcetree缺Git只转终端不原地安装'
    $state.MissingGit=$false;$state.Cancel=$false;$state.Addresses=@($addresses[0])
    foreach ($key in $repositoryKeys) { [Environment]::SetEnvironmentVariable($key,'ambient-fixture','Process') }
    & $module {param($r) Invoke-JobsRemoteAddress $r -SourceTree} $fixture
    $restored=$true
    foreach ($key in $repositoryKeys) { if ([Environment]::GetEnvironmentVariable($key,'Process') -cne 'ambient-fixture') { $restored=$false } }
    Assert-Check $restored '成功路径隔离继承Git寻址变量并逐一恢复'
    $state.Addresses=@([pscustomobject]@{Url='file:///tmp/fixture';Labels=@('origin/fetch')})
    $failed=$false
    try { & $module {param($r) Invoke-JobsRemoteAddress $r -Open -SourceTree} $fixture } catch { $failed=$true }
    $restored=$true
    foreach ($key in $repositoryKeys) { if ([Environment]::GetEnvironmentVariable($key,'Process') -cne 'ambient-fixture') { $restored=$false };Remove-Item -LiteralPath ('Env:'+$key) -ErrorAction SilentlyContinue }
    Assert-Check ($failed -and $restored) '失败路径仍恢复继承Git寻址变量'
    # 依赖链五类分支，所有安装器都为假命令。
    Remove-Module $module
    $module=Import-Module (Join-Path $root 'Scripts/SourceTree.psm1') -Force -PassThru -DisableNameChecking
    $chain=@{Healthy=$true;Winget=$true;Install=0;Refresh=0;Find=0;FailInstall=$false;FailVerify=$false}
    & $module {
        param($chain)
        $script:Chain=$chain
        function script:Assert-JobsRemoteTerminal {}
        function script:Read-Host {param($Prompt) ''}
        function script:Find-JobsRemoteTool {
            param($Name,$Directory)
            $script:Chain.Find++
            if ($Name -eq 'winget') { if ($script:Chain.Winget) { return 'fake-winget' };return $null }
            if ($script:Chain.Healthy -or ($script:Chain.Install -gt 0 -and -not $script:Chain.FailVerify)) { return 'healthy-'+$Name }
            return $null
        }
        function script:Invoke-JobsTool {param($Tool,$Arguments,$Directory) $script:Chain.Install++;if ($script:Chain.FailInstall) { throw 'fixture install failed' };[pscustomobject]@{Code=0;Text='ok'}}
        function script:Update-JobsRemoteSessionPath { $script:Chain.Refresh++ }
    } $chain
    $tool=& $module {param($r) Ensure-JobsRemoteTool 'fzf' $r} $fixture
    Assert-Check ($tool -ceq 'healthy-fzf' -and $chain.Find -eq 1 -and $chain.Install -eq 0) '全链健康不探WinGet不安装'
    $chain.Healthy=$false
    $tool=& $module {param($r) Ensure-JobsRemoteTool 'fzf' $r} $fixture
    Assert-Check ($tool -ceq 'healthy-fzf' -and $chain.Install -eq 1 -and $chain.Refresh -eq 1) '末端缺失，上游健康，一次安装刷新复检'
    $chain.Install=0;$chain.Winget=$false;$failed=$false
    try { & $module {param($r) Ensure-JobsRemoteTool 'fzf' $r} $fixture | Out-Null } catch { $failed=$true }
    Assert-Check ($failed -and $chain.Install -eq 0) '多层缺失停在WinGet，不带病继续'
    $chain.Winget=$true;$chain.FailInstall=$true;$failed=$false
    try { & $module {param($r) Ensure-JobsRemoteTool 'fzf' $r} $fixture | Out-Null } catch { $failed=$true }
    Assert-Check ($failed -and $chain.Install -eq 1) '安装失败传播且不重试'
    $chain.Install=0;$chain.FailInstall=$false;$chain.FailVerify=$true;$failed=$false
    try { & $module {param($r) Ensure-JobsRemoteTool 'fzf' $r} $fixture | Out-Null } catch { $failed=$true }
    Assert-Check ($failed -and $chain.Install -eq 1) '安装后体检失败停止且不重试'
    Assert-Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $fixture '.git/config'))) -ceq [Convert]::ToBase64String($before)) '全部远程动作不改Git配置'
    Write-Host "PASS：$($counter.Value) 项远程动作断言。"
} finally {
    foreach ($key in $environmentKeys) { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') }
    foreach ($key in @('JOBS_REMOTE_TEST_ROWS','JOBS_REMOTE_TEST_CODE','JOBS_REMOTE_TEST_INVALID')) { [Environment]::SetEnvironmentVariable($key,$null,'Process') }
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
