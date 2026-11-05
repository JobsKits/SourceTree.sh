# 用真实隔离 Git 仓库验证 Push 修复；只访问本地 bare remote，不操作用户项目。
# 运行：pwsh -NoProfile -File ./WindowsOS/Tests/PushRepair.Tests.ps1/PushRepair.Tests.ps1
param([string]$ModulePath=(Join-Path $PSScriptRoot '../../Scripts/Features/JobsGitPushRepair/Scripts/Action.psm1'))
$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('jobs-push-repair-tests-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$script:Passed = 0
$environmentKeys = @('GIT_CONFIG_NOSYSTEM','GIT_CONFIG_GLOBAL','GIT_CONFIG_COUNT','GIT_ALLOW_PROTOCOL','GIT_TERMINAL_PROMPT')
$savedEnvironment = @{}
foreach ($key in $environmentKeys) { $savedEnvironment[$key]=[Environment]::GetEnvironmentVariable($key,'Process') }
$env:GIT_CONFIG_NOSYSTEM='1';$env:GIT_CONFIG_GLOBAL=Join-Path $testRoot 'empty-global';$env:GIT_CONFIG_COUNT='0';$env:GIT_ALLOW_PROTOCOL='file';$env:GIT_TERMINAL_PROMPT='0'
# 执行测试 Git 并检查退出码，不以 stderr 的提示文字判失败。
function Test-Git {
    param([string]$Repo,[string[]]$GitArgs)
    $savedPreference=$ErrorActionPreference
    try {
        $ErrorActionPreference='Continue'
        $text=@(& git -C $Repo @GitArgs 2>&1 | ForEach-Object { $_.ToString() }) -join "`n"
        $code=$LASTEXITCODE
    } finally { $ErrorActionPreference=$savedPreference }
    if ($code -ne 0) { throw ('测试 Git 失败：'+($GitArgs -join ' ')+' '+$text) }
    return $text
}
# 每一项断言独立计数。
function Assert-Test {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw ('FAIL '+$Message) }
    $script:Passed++;Write-Host ('PASS '+$Message)
}
# 拒绝路径必须抛出匹配原因，不能悄悄转为成功。
function Assert-Refused {
    param([scriptblock]$Action,[string]$Pattern,[string]$Message)
    $caught=''
    try { & $Action | Out-Null } catch { $caught=$_.Exception.Message }
    Assert-Test ($caught -match $Pattern) ($Message+' ['+$caught+']')
}
# 创建互不共享的两份工作树和本地 bare 远端。
function New-Fixture {
    param([string]$Name)
    $dir=Join-Path $testRoot $Name
    [void][IO.Directory]::CreateDirectory($dir)
    $remote=Join-Path $dir 'remote.git';$local=Join-Path $dir '中文 本地 [x]';$peer=Join-Path $dir 'peer'
    [void](Test-Git $dir @('init','--bare','-b','main',$remote))
    [void][IO.Directory]::CreateDirectory($local)
    [void](Test-Git $local @('init','-b','main'))
    foreach ($repo in @($local)) {
        [void](Test-Git $repo @('config','user.name','Jobs Test'));[void](Test-Git $repo @('config','user.email','jobs-test@example.invalid'))
    }
    [IO.File]::WriteAllText((Join-Path $local 'base.txt'),'base')
    [void](Test-Git $local @('add','base.txt'));[void](Test-Git $local @('commit','-m','base'))
    [void](Test-Git $local @('remote','add','origin',$remote));[void](Test-Git $local @('push','origin','main'))
    [void](Test-Git $dir @('clone',$remote,$peer))
    [void](Test-Git $peer @('config','user.name','Jobs Test'));[void](Test-Git $peer @('config','user.email','jobs-test@example.invalid'))
    [pscustomobject]@{ Directory=$dir;Local=$local;Remote=$remote;Peer=$peer;Base=(Test-Git $local @('rev-parse','HEAD')) }
}
# 只为隔离工作树创建可区分的提交。
function Add-TestCommit {
    param([string]$Repo,[string]$File,[string]$Content)
    [IO.File]::WriteAllText((Join-Path $Repo $File),$Content)
    [void](Test-Git $Repo @('add','--',$File));[void](Test-Git $Repo @('commit','-m',$Content))
    return Test-Git $Repo @('rev-parse','HEAD')
}
# 只供 Git for Windows / POSIX Git 的隔离 hook 使用，路径作为 Shell 字面量。
function ConvertTo-TestShellQuote {
    param([string]$Value)
    return "'" + $Value.Replace("'",("'"+[char]34+"'"+[char]34+"'")) + "'"
}
try {
    $module=Import-Module $ModulePath -Force -DisableNameChecking -PassThru
    $f=New-Fixture 'diagnose'
    $index=Get-FileHash -LiteralPath (Join-Path $f.Local '.git/index')
    $config=Get-FileHash -LiteralPath (Join-Path $f.Local '.git/config')
    $refs=Test-Git $f.Local @('show-ref')
    $diagnosis=Repair-JobsPush -Repository $f.Local -Remote origin -Diagnose
    Assert-Test ($diagnosis.Diagnosed -and $diagnosis.Head -ceq $diagnosis.RemoteHead) '只诊断读回精确 OID'
    Assert-Test ((Get-FileHash -LiteralPath (Join-Path $f.Local '.git/index')).Hash -ceq $index.Hash -and (Get-FileHash -LiteralPath (Join-Path $f.Local '.git/config')).Hash -ceq $config.Hash -and (Test-Git $f.Local @('show-ref')) -ceq $refs) '只诊断保留索引、配置、引用'
    Assert-Test (-not (Test-Path -LiteralPath (Join-Path $f.Local '.git/jobs-push-repair'))) '只诊断不创建仓库日志目录'
    $f=New-Fixture 'ahead'
    $head=Add-TestCommit $f.Local 'local.txt' 'local'
    [void](Test-Git $f.Local @('config','push.followTags','true'));[void](Test-Git $f.Local @('tag','-a','must-stay-local','-m','local tag'))
    $result=Repair-JobsPush -Repository $f.Local -Remote origin
    Assert-Test ($result.Head -ceq $head -and (Test-Git $f.Remote @('rev-parse','main')) -ceq $head) '本地领先正常推送'
    Assert-Test ((Test-Git $f.Local @('rev-parse','refs/remotes/origin/main')) -ceq $head) '同端点默认 fetch 映射刷新跟踪引用'
    Assert-Test (-not (Test-Git $f.Remote @('tag'))) 'followTags 配置不扩大推送范围'
    Assert-Test ((Test-Git $f.Local @('for-each-ref','--format=%(refname)','refs/heads')) -ceq 'refs/heads/main') '没有额外本地分支'
    Assert-Test (-not (Test-Path -LiteralPath (Join-Path $f.Local '.git/jobs-push-repair.lock')) -and -not (Test-Git $f.Local @('for-each-ref','--format=%(refname)','refs/jobs-push-repair'))) '成功后释放互斥锁与临时引用'
    $f=New-Fixture 'behind'
    $head=Add-TestCommit $f.Peer 'remote.txt' 'remote';[void](Test-Git $f.Peer @('push','origin','main'))
    [void](Repair-JobsPush -Repository $f.Local -Remote origin)
    Assert-Test ((Test-Git $f.Local @('rev-parse','HEAD')) -ceq $head) '远端领先快进且不产生无用 merge'
    $f=New-Fixture 'diverged'
    $local=Add-TestCommit $f.Local 'local.txt' 'local';$peer=Add-TestCommit $f.Peer 'remote.txt' 'remote';[void](Test-Git $f.Peer @('push','origin','main'))
    $result=Repair-JobsPush -Repository $f.Local -Remote origin
    Assert-Test ((Test-Git $f.Local @('show','-s','--format=%P','HEAD')).Split(' ').Count -eq 2) '分叉产生保留双方历史的 merge'
    [void](Test-Git $f.Local @('merge-base','--is-ancestor',$local,'HEAD'));[void](Test-Git $f.Local @('merge-base','--is-ancestor',$peer,'HEAD'))
    Assert-Test ($result.Head -ceq (Test-Git $f.Remote @('rev-parse','main'))) '合并后两端 OID 精确一致'
    $f=New-Fixture 'dirty'
    [IO.File]::WriteAllText((Join-Path $f.Local 'untracked.txt'),'keep me')
    Assert-Refused { Repair-JobsPush -Repository $f.Local -Remote origin } '\[dirty\]' '未跟踪改动保留并停止'
    Assert-Test ([IO.File]::ReadAllText((Join-Path $f.Local 'untracked.txt')) -ceq 'keep me' -and (Test-Git $f.Remote @('rev-parse','main')) -ceq $f.Base) '脏工作树无副作用'
    $f=New-Fixture 'conflict'
    [void](Add-TestCommit $f.Local 'base.txt' 'local');$peer=Add-TestCommit $f.Peer 'base.txt' 'remote';[void](Test-Git $f.Peer @('push','origin','main'))
    Assert-Refused { Repair-JobsPush -Repository $f.Local -Remote origin } '\[conflict\]' '真实冲突失败传播'
    Assert-Test ((Test-Path -LiteralPath (Join-Path $f.Local '.git/MERGE_HEAD')) -and (Test-Git $f.Remote @('rev-parse','main')) -ceq $peer) '保留 merge 冲突现场且未推送'
    Assert-Refused { Repair-JobsPush -Repository $f.Local -Remote origin } '未完成操作' '未结束 merge 不再次修复'
    $f=New-Fixture 'ambiguity'
    [void](Test-Git $f.Local @('remote','add','second',$f.Remote))
    Assert-Refused { Repair-JobsPush -Repository $f.Local -Diagnose } '多个远端' '无唯一远端时不猜 origin'
    [void](Test-Git $f.Local @('config','branch.main.pushRemote','origin'))
    $result=Repair-JobsPush -Repository $f.Local -Diagnose
    Assert-Test $result.Diagnosed '明确 pushRemote 优先于多远端'
    $f=New-Fixture 'upstream'
    [void](Test-Git $f.Local @('config','branch.main.remote','origin'));[void](Test-Git $f.Local @('config','branch.main.merge','refs/heads/main'))
    $result=Repair-JobsPush -Repository $f.Local -Diagnose
    Assert-Test $result.Diagnosed '现有上游解析成功'
    $f=New-Fixture 'mapping'
    [void](Test-Git $f.Local @('push','origin','main:published'));[void](Test-Git $f.Local @('config','remote.origin.push','main:published'))
    $head=Add-TestCommit $f.Local 'local.txt' 'mapped'
    [void](Repair-JobsPush -Repository $f.Local -Remote origin)
    Assert-Test ((Test-Git $f.Remote @('rev-parse','published')) -ceq $head -and (Test-Git $f.Remote @('rev-parse','main')) -ceq $f.Base) '远端异名映射只更新对应分支'
    [void](Test-Git $f.Local @('config','remote.origin.push','refs/heads/*:refs/heads/*'))
    Assert-Refused { Repair-JobsPush -Repository $f.Local -Remote origin } 'refspec' '拒绝隐式通配映射'
    $f=New-Fixture 'push-url'
    $pushRemote=Join-Path $f.Directory 'push.git';[void](Test-Git $f.Directory @('clone','--bare',$f.Remote,$pushRemote))
    [void](Test-Git $f.Local @('remote','set-url','--push','origin',$pushRemote))
    $head=Add-TestCommit $f.Local 'local.txt' 'push-target'
    [void](Repair-JobsPush -Repository $f.Local -Remote origin)
    Assert-Test ((Test-Git $pushRemote @('rev-parse','main')) -ceq $head -and (Test-Git $f.Remote @('rev-parse','main')) -ceq $f.Base) 'pushurl 与 fetchurl 不同仍只处理推送端'
    Assert-Test ((Test-Git $f.Local @('rev-parse','refs/remotes/origin/main')) -ceq $f.Base) 'fetch/push 异端点不刷新原跟踪引用'
    [void](Test-Git $f.Local @('config','--add','remote.origin.pushurl',$f.Remote))
    Assert-Refused { Repair-JobsPush -Repository $f.Local -Remote origin } '多个/空 URL' '多个推送地址拒绝批量写入'
    $f=New-Fixture 'new-destination'
    [void](Test-Git $f.Local @('config','remote.origin.jobsPushBranch','new-target'))
    Assert-Refused { Repair-JobsPush -Repository $f.Local -Remote origin } '尚不存在' '未知远端分支不隐式创建'
    [void](Repair-JobsPush -Repository $f.Local -Remote origin -Branch 'new-target')
    Assert-Test ((Test-Git $f.Remote @('rev-parse','new-target')) -ceq $f.Base) '显式目标分支允许首次发布'
    $f=New-Fixture 'lock'
    [IO.File]::WriteAllText((Join-Path $f.Local '.git/index.lock'),'foreign lock')
    Assert-Refused { Repair-JobsPush -Repository $f.Local -Remote origin } 'index.lock' '已有锁拒绝并保留'
    Assert-Test ([IO.File]::ReadAllText((Join-Path $f.Local '.git/index.lock')) -ceq 'foreign lock') '不删除他人锁'
    $f=New-Fixture 'detached'
    [void](Test-Git $f.Local @('checkout','--detach','HEAD'))
    Assert-Refused { Repair-JobsPush -Repository $f.Local -Remote origin } '游离 HEAD' '游离状态不恢复猜测分支'
    Assert-Refused { Repair-JobsPush -Repository $f.Remote -Remote origin } 'bare' 'bare 仓库不套用工作树修复'
    $f=New-Fixture 'unrelated'
    $unrelated=Join-Path $f.Directory 'unrelated';[void][IO.Directory]::CreateDirectory($unrelated)
    [void](Test-Git $unrelated @('init','-b','main'));[void](Test-Git $unrelated @('config','user.name','Jobs Test'));[void](Test-Git $unrelated @('config','user.email','jobs-test@example.invalid'))
    [void](Add-TestCommit $unrelated 'other.txt' 'other-root');[void](Test-Git $unrelated @('remote','add','origin',$f.Remote))
    Assert-Refused { Repair-JobsPush -Repository $unrelated -Remote origin } '没有共同祖先' '无关历史不强行拼接'
    $f=New-Fixture 'mirror'
    [void](Test-Git $f.Local @('config','remote.origin.mirror','true'))
    Assert-Refused { Repair-JobsPush -Repository $f.Local -Remote origin } '镜像推送' '镜像配置走专用流程'
    $f=New-Fixture 'snapshot'
    [void](Test-Git $f.Local @('branch','-m','byPods'));[void](Test-Git $f.Local @('remote','set-url','origin','git@gitee.com:JobsGo/JobsOCBaseConfigDemo.git'))
    Assert-Refused { Repair-JobsPush -Repository $f.Local -Remote origin } '\[snapshot\]' 'OC byPods 的 Gitee 独立快照边界先于联网'
    $f=New-Fixture 'ignored-collision'
    [void](Add-TestCommit $f.Local '.gitignore' 'private.txt')
    [IO.File]::WriteAllText((Join-Path $f.Local 'private.txt'),'important ignored data')
    [void](Add-TestCommit $f.Peer 'private.txt' 'remote tracked content');[void](Test-Git $f.Peer @('push','origin','main'))
    Assert-Refused { Repair-JobsPush -Repository $f.Local -Remote origin } '\[working-tree\]' '远端跟踪路径与本地忽略文件碰撞时停止'
    Assert-Test ([IO.File]::ReadAllText((Join-Path $f.Local 'private.txt')) -ceq 'important ignored data') '合并不覆盖本地忽略文件'
    $f=New-Fixture 'local-rename-directory'
    [void](Test-Git $f.Local @('mv','base.txt','moving.txt'))
    [void][IO.Directory]::CreateDirectory((Join-Path $f.Local 'base.txt'))
    [void](Test-Git $f.Local @('mv','moving.txt','base.txt/original.txt'))
    [void](Test-Git $f.Local @('commit','-m','move old file into same-name directory'))
    [void](Add-TestCommit $f.Peer 'remote.txt' 'unrelated remote change');[void](Test-Git $f.Peer @('push','origin','main'))
    $result=Repair-JobsPush -Repository $f.Local -Remote origin
    Assert-Test ((Test-Path -LiteralPath (Join-Path $f.Local 'base.txt/original.txt')) -and $result.Head -ceq (Test-Git $f.Remote @('rev-parse','main'))) '本地旧文件迁入同名目录而远端未改该路径不误阻断'
    $f=New-Fixture 'accepted-disconnected'
    $head=Add-TestCommit $f.Local 'local.txt' 'accepted'
    & $module {
        $script:NativePushGit=(Get-Command Invoke-JobsPushGit).ScriptBlock
        function script:Invoke-JobsPushGit {
            param([string]$Repository,[string[]]$Arguments,[switch]$Show)
            $actual=& $script:NativePushGit -Repository $Repository -Arguments $Arguments -Show:$Show
            if ($Arguments -contains 'push' -and $actual.Code -eq 0) { return [pscustomobject]@{Code=128;Text='RPC failed; connection closed after remote accepted'} }
            return $actual
        }
    }
    $result=Repair-JobsPush -Repository $f.Local -Remote origin
    Assert-Test ($result.RemoteHead -ceq $head) '服务端已接受但本地传输失败时先读回核验'
    $module=Import-Module $ModulePath -Force -DisableNameChecking -PassThru
    $f=New-Fixture 'hook-rejection'
    [void](Add-TestCommit $f.Local 'local.txt' 'blocked')
    $hook=Join-Path $f.Remote 'hooks/pre-receive'
    [IO.File]::WriteAllText($hook,"#!/bin/sh`necho 'pre-receive hook declined: project policy' >&2`nexit 1`n",(New-Object Text.UTF8Encoding($false)))
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { & chmod u+x $hook }
    Assert-Refused { Repair-JobsPush -Repository $f.Local -Remote origin } '\[hook\]' '服务端 hook 不被跳过'
    Assert-Test ((Test-Git $f.Remote @('rev-parse','main')) -ceq $f.Base) 'hook 拒绝未更改服务端'
    $f=New-Fixture 'missing-shallow-base'
    [void](Add-TestCommit $f.Peer 'first.txt' 'first');[void](Test-Git $f.Peer @('push','origin','main'))
    $shallow=Join-Path $f.Directory 'shallow'
    $remoteUri=([Uri](Get-Item -LiteralPath $f.Remote).FullName).AbsoluteUri
    if (-not $remoteUri) { $remoteUri='file://'+(Get-Item -LiteralPath $f.Remote).FullName }
    [void](Test-Git $f.Directory @('clone','--depth=1',$remoteUri,$shallow))
    [void](Test-Git $shallow @('config','user.name','Jobs Test'));[void](Test-Git $shallow @('config','user.email','jobs-test@example.invalid'))
    [void](Add-TestCommit $shallow 'local.txt' 'local shallow')
    # 仅隔离夹具模拟服务端历史改写，生产修复入口绝不使用 force。
    [void](Test-Git $f.Peer @('checkout','--detach',$f.Base));[void](Add-TestCommit $f.Peer 'other.txt' 'remote sibling')
    [void](Test-Git $f.Peer @('push','--force','origin','HEAD:refs/heads/main'))
    Assert-Refused { Repair-JobsPush -Repository $shallow -Remote origin } '浅克隆缺少共同祖先' '浅克隆证据不足不当作无关根合并'
    $f=New-Fixture 'remote-push-race'
    $local=Add-TestCommit $f.Local 'local.txt' 'local race'
    $peer=Add-TestCommit $f.Peer 'peer.txt' 'peer race'
    [void](Test-Git $f.Peer @('push','origin','HEAD:refs/jobs-test/prepared-race'))
    $hook=Join-Path $f.Local '.git/hooks/pre-push';$marker=Join-Path $f.Directory 'race-once'
    $hookBody="#!/bin/sh`nif [ ! -f "+(ConvertTo-TestShellQuote $marker)+" ]; then`n  git --git-dir="+(ConvertTo-TestShellQuote $f.Remote)+" update-ref refs/heads/main "+$peer+' '+$f.Base+" || exit 1`n  : > "+(ConvertTo-TestShellQuote $marker)+"`nfi`nexit 0`n"
    [IO.File]::WriteAllText($hook,$hookBody,(New-Object Text.UTF8Encoding($false)))
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { & chmod u+x $hook }
    $result=Repair-JobsPush -Repository $f.Local -Remote origin
    $journal=@(Get-ChildItem -LiteralPath (Join-Path $f.Local '.git/jobs-push-repair') -File)[0]
    $plans=@(Get-Content -LiteralPath $journal.FullName | Where-Object { $_ -like 'planned=*' })
    Assert-Test ($plans.Count -eq 2 -and (Test-Path -LiteralPath $marker)) '真实 pre-push 窗口的远端旧值竞争触发有限重试'
    [void](Test-Git $f.Local @('merge-base','--is-ancestor',$local,'HEAD'));[void](Test-Git $f.Local @('merge-base','--is-ancestor',$peer,'HEAD'))
    Assert-Test ($result.Head -ceq (Test-Git $f.Remote @('rev-parse','main')) -and $result.Head -ceq (Test-Git $f.Local @('rev-parse','refs/remotes/origin/main'))) '并发重试整合双方历史并刷新图中跟踪引用'
    $f=New-Fixture 'exact-tracking'
    [void](Test-Git $f.Local @('config','remote.origin.fetch','+refs/heads/main:refs/remotes/origin/main'))
    $head=Add-TestCommit $f.Local 'local.txt' 'exact tracking';[void](Repair-JobsPush -Repository $f.Local -Remote origin)
    Assert-Test ((Test-Git $f.Local @('rev-parse','refs/remotes/origin/main')) -ceq $head) '精确 fetch refspec 可证明时刷新跟踪引用'
    $f=New-Fixture 'negative-tracking'
    [void](Test-Git $f.Local @('config','--add','remote.origin.fetch','^refs/heads/main'))
    $head=Add-TestCommit $f.Local 'local.txt' 'negative tracking';[void](Repair-JobsPush -Repository $f.Local -Remote origin)
    Assert-Test ((Test-Git $f.Remote @('rev-parse','main')) -ceq $head -and (Test-Git $f.Local @('rev-parse','refs/remotes/origin/main')) -ceq $f.Base) '负向 fetch refspec 保留原跟踪引用'
    $f=New-Fixture 'symbolic-tracking'
    [void](Test-Git $f.Local @('update-ref','refs/remotes/other/main',$f.Base))
    [void](Test-Git $f.Local @('update-ref','-d','refs/remotes/origin/main'))
    [void](Test-Git $f.Local @('symbolic-ref','refs/remotes/origin/main','refs/remotes/other/main'))
    $head=Add-TestCommit $f.Local 'local.txt' 'symbolic tracking';[void](Repair-JobsPush -Repository $f.Local -Remote origin)
    Assert-Test ((Test-Git $f.Local @('symbolic-ref','refs/remotes/origin/main')) -ceq 'refs/remotes/other/main' -and (Test-Git $f.Local @('rev-parse','refs/remotes/other/main')) -ceq $f.Base) '符号跟踪引用及指向对象均保留'
    $f=New-Fixture 'tracking-cas-race'
    $middle=Add-TestCommit $f.Local 'first.txt' 'first local';$head=Add-TestCommit $f.Local 'second.txt' 'second local'
    & $module {
        param($Middle)
        $script:ConcurrentTracking=$Middle
        $script:NativePushGit=(Get-Command Invoke-JobsPushGit).ScriptBlock
        function script:Invoke-JobsPushGit {
            param([string]$Repository,[string[]]$Arguments,[switch]$Show)
            if ($Arguments -contains 'update-ref' -and $Arguments -contains 'refs/remotes/origin/main' -and $Arguments -contains 'jobs push repair: verified remote tip') {
                [void](& $script:NativePushGit -Repository $Repository -Arguments @('update-ref','refs/remotes/origin/main',$script:ConcurrentTracking))
            }
            return & $script:NativePushGit -Repository $Repository -Arguments $Arguments -Show:$Show
        }
    } $middle
    [void](Repair-JobsPush -Repository $f.Local -Remote origin)
    Assert-Test ((Test-Git $f.Remote @('rev-parse','main')) -ceq $head -and (Test-Git $f.Local @('rev-parse','refs/remotes/origin/main')) -ceq $middle) '跟踪引用 CAS 失败不覆盖并发 fetch 值'
    $module=Import-Module $ModulePath -Force -DisableNameChecking -PassThru
    $failures=@{
        'Permission denied (publickey).'='authentication';'remote: GH006: Protected branch update failed'='policy';'remote: detected secret in commit'='secret';
        'remote: Repo size exceeds quota'='quota';'remote: GH001: Large files detected'='size';'git-lfs filter-process error'='lfs';
        'Repository not found'='permission';'SSL certificate problem'='trust';'non-fast-forward'='history';'cannot lock ref'='lock';'remote rejected: incorrect old value provided'='history';'remote: cannot lock ref main: is at abc123 but expected def456'='history';
        'CONFLICT (content): Merge conflict'='conflict';'refusing to merge unrelated histories'='history-boundary';'Author identity unknown'='identity';
        'gpg failed to sign the data'='signature';'pre-receive hook declined'='hook';'src refspec main does not match any'='target';
        'No space left on device'='filesystem';'fatal: bad object'='objects';'Connection timed out'='network';'new vendor error'='unknown'
    }
    foreach ($message in $failures.Keys) { Assert-Test ((Get-JobsPushFailure $message).Category -ceq $failures[$message]) ('失败分类 '+$failures[$message]) }
    $safe=& $module { Protect-JobsPushText 'https://user:secret@example.invalid/repo.git?token=hidden' }
    Assert-Test (-not $safe.Contains('secret') -and -not $safe.Contains('hidden')) '日志 URL 凭据与查询信息脱敏'
    $safe=& $module { Protect-JobsPushText "fatal: Authorization: Bearer hidden`nProxy-Authorization: Basic secret`nordinary line" }
    Assert-Test (-not $safe.Contains('secret') -and -not $safe.Contains('hidden') -and $safe.Contains('ordinary line')) '授权头整行脱敏且保留其它错误'
    Write-Host ('全部通过：'+$script:Passed+' 项；隔离证据：'+$testRoot)
} finally {
    foreach ($key in $environmentKeys) { [Environment]::SetEnvironmentVariable($key,$savedEnvironment[$key],'Process') }
}
