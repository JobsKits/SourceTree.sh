# SourceTree.psm1 | Jobs Windows Sourcetree 动作
# Created by Jobs on 2026年10月23日，星期五.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:LogFile = $null
# 清除展示中的认证信息，不修改业务参数。
function Protect-JobsText {
    param([string]$Text)
    $Text -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@','$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*','$1?[已省略]'
}
# 统一输出状态并保留纯文本日志。
function Write-JobsStatus {
    param([string]$Text)
    $safe = Protect-JobsText $Text
    Write-Host $safe
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $safe -Encoding UTF8 }
}
# 执行原生命令并保留失败退出码，参数始终以数组传递。
function Invoke-JobsTool {
    param([string]$Tool, [string[]]$Arguments, [string]$Directory, [switch]$Quiet, [switch]$AllowFailure)
    $command = Get-Command $Tool -ErrorAction Stop
    Push-Location -LiteralPath $Directory
    $previousPreference = $ErrorActionPreference
    $previousOutputEncoding = $OutputEncoding
    $previousConsoleEncoding = [Console]::OutputEncoding
    try {
        # Git 等工具输出 UTF8；系统 OEM 代码页会损坏中文仓库路径。
        $OutputEncoding = New-Object Text.UTF8Encoding($false)
        [Console]::OutputEncoding = $OutputEncoding
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        $lines = @(& $command.Source @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
        $OutputEncoding = $previousOutputEncoding
        [Console]::OutputEncoding = $previousConsoleEncoding
        Pop-Location
    }
    $output = $lines -join "`n"
    if (-not $Quiet -and $output) { Write-JobsStatus $output }
    if ($code -ne 0 -and -not $AllowFailure) { throw "$Tool 执行失败，退出码 $code。" }
    [pscustomobject]@{ Code = $code; Text = $output }
}
# 将 Git 操作固定到明确工作树。
function Invoke-JobsGit {
    param([string]$Repository,[string[]]$Arguments,[switch]$AllowFailure,[switch]$Quiet)
    Invoke-JobsTool 'git' (@('-C',$Repository) + $Arguments) $Repository -AllowFailure:$AllowFailure -Quiet:$Quiet
}
# 拒绝目录联接，避免递归和写操作越过用户选定边界。
function Resolve-JobsDirectory {
    param([string]$Target)
    $item = Get-Item -LiteralPath $Target -Force
    if (-not $item.PSIsContainer) { $item = $item.Directory }
    $scan = $item
    while ($null -ne $scan) {
        if (($scan.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '目标或上层目录是链接，停止。' }
        $scan = $scan.Parent
    }
    $item.FullName
}
# 仅返回实际仓库根，允许传入其内部普通路径。
function Resolve-JobsRepository {
    param([string]$Target)
    $dir = Resolve-JobsDirectory $Target
    $repository=(Invoke-JobsGit $dir @('rev-parse','--show-toplevel') -Quiet).Text.Trim()
    [IO.Path]::GetFullPath($repository)
}
# 危险动作必须精确输入 YES；没有输入时取消。
function Confirm-JobsDanger {
    param([string]$Message)
    Write-JobsStatus $Message
    $answer = Read-Host '精确输入 YES 执行；回车或其它输入取消'
    if ($answer -cne 'YES') { throw '已取消，未执行此危险操作。' }
}
# 复用随包携带的 Windows 业务模块，不要求安装右键扩展。
function Invoke-JobsFeatureModule {
    param([string]$Name,[string]$Target,[string]$Kind)
    $path = Join-Path $PSScriptRoot ('Features/' + $Name + '/Scripts/Action.psm1')
    $module = Import-Module $path -Force -DisableNameChecking -PassThru
    if ($Kind -eq 'android') { & $module { param($p) Invoke-JobsPackagerBuild -Project $p -Type 'all' } $Target }
    elseif ($Kind -eq 'ohos') {
        & $module {
            param($p, $log)
            if ($log) { $script:PackagerLog = $log }
            Invoke-JobsPackagerHarmonyBuild -Project $p -Type 'all'
        } $Target $script:LogFile
    }
    else { & $module { param($p) Invoke-JobsFeature -Target $p } $Target }
}
# 项目锁定 FVM 时禁止静默使用全局 SDK。
function Get-JobsFlutter {
    param([string]$Project)
    if (-not (Test-Path -LiteralPath (Join-Path $Project 'pubspec.yaml') -PathType Leaf)) { throw '请指定 Flutter 根目录。' }
    $local = Join-Path $Project '.fvm/flutter_sdk/bin/flutter.bat'
    if ((Test-Path -LiteralPath (Join-Path $Project '.fvmrc')) -or (Test-Path -LiteralPath (Join-Path $Project '.fvm/fvm_config.json'))) {
        if (-not (Test-Path -LiteralPath $local -PathType Leaf)) { throw '工程锁定 FVM，但 SDK 不完整；请先初始化对应版本。' }
        return $local
    }
    if (Test-Path -LiteralPath $local -PathType Leaf) { return $local }
    (Get-Command flutter -ErrorAction Stop).Source
}
# 仅遍历自有源码，跳过链接、依赖、生成产物和嵌套仓库。
function Get-JobsSourceFiles {
    param([string]$Directory)
    foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        if ($item.PSIsContainer) {
            if ($item.Name -in @('.git','node_modules','Pods','.dart_tool','build','DerivedData','vendor','third_party','.import_backup','PodsManual')) { continue }
            if (Test-Path -LiteralPath (Join-Path $item.FullName '.git')) { continue }
            Get-JobsSourceFiles $item.FullName
        } else { $item }
    }
}
# 解码 package 指令内完整 UTF8 高位序列，ASCII 转义保持原样。
function Repair-JobsFlutterImports {
    param([string]$Project)
    $utf8 = New-Object Text.UTF8Encoding($false,$true)
    $backup = Join-Path $Project ('.import_backup/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
    $count = 0
    foreach ($sub in @('lib','test','integration_test')) {
        $dir = Join-Path $Project $sub
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        foreach ($file in Get-JobsSourceFiles $dir) {
            if ($file.Extension -ne '.dart' -or $file.Name -match '\.(g|freezed|gr)\.dart$') { continue }
            $bytes = [IO.File]::ReadAllBytes($file.FullName)
            $text = $utf8.GetString($bytes)
            if ($text -match '(?im)Created by (?!Jobs\b)[^\r\n]+') { continue }
            $changed = [regex]::Replace($text,'(?m)^(\s*(?:import|export|part)\s+[''"]package:[^''"\r\n]+[''"])',{
                param($directive)
                [regex]::Replace($directive.Value,'(?:%[89a-fA-F][0-9a-fA-F])+',{
                    param($encoded)
                    try {
                        $values = [byte[]]@([regex]::Matches($encoded.Value,'%([0-9a-fA-F]{2})') | ForEach-Object { [Convert]::ToByte($_.Groups[1].Value,16) })
                        $utf8.GetString($values)
                    } catch { $encoded.Value }
                })
            })
            if ($changed -ceq $text) { continue }
            $relative = $file.FullName.Substring($Project.Length).TrimStart('\','/')
            $saved = Join-Path $backup $relative
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $saved))
            [IO.File]::WriteAllBytes($saved,$bytes)
            [IO.File]::WriteAllText($file.FullName,$changed,$utf8)
            $count++
        }
    }
    Write-JobsStatus "修复 $count 个自有 Dart 文件；备份：$backup"
}
# 仅 soft 撤回领先上游的提交；hard 分支显式选择并确认。
function Reset-JobsCommit {
    param([string]$Repository,[string]$Option,[string]$Value)
    if (-not $Option) { $Option = Read-Host 'soft=回退未推送提交；hard=选择提交；回车取消' }
    if ($Option -eq 'soft') {
        $upstream = (Invoke-JobsGit $Repository @('rev-parse','--verify','@{upstream}^{commit}') -Quiet).Text.Trim()
        [void](Invoke-JobsGit $Repository @('merge-base','--is-ancestor',$upstream,'HEAD') -Quiet)
        [void](Invoke-JobsGit $Repository @('reset','--soft',$upstream))
    } elseif ($Option -eq 'hard') {
        if (-not $Value) { [void](Invoke-JobsGit $Repository @('log','-20','--format=%H %s')); $Value = Read-Host '输入目标提交/tag/reflog 表达式' }
        $commit = (Invoke-JobsGit $Repository @('rev-parse','--verify',($Value + '^{commit}')) -Quiet).Text.Trim()
        Confirm-JobsDanger "仓库：$Repository；hard 回退 $commit，舍弃本仓已跟踪修改，保留子模块工作树。"
        [void](Invoke-JobsGit $Repository @('-c','submodule.recurse=false','reset','--hard','--no-recurse-submodules',$commit))
    } else { throw '已取消或不支持的回退模式。' }
}
# 只拉取使用明确 upstream，预检递归 gitlink 后按固定版本检出。
function Receive-JobsRepository {
    param([string]$Repository)
    $branch = (Invoke-JobsGit $Repository @('symbolic-ref','--quiet','--short','HEAD') -Quiet).Text.Trim()
    $remote = (Invoke-JobsGit $Repository @('config',('branch.'+$branch+'.remote')) -Quiet).Text.Trim()
    $merge = (Invoke-JobsGit $Repository @('config',('branch.'+$branch+'.merge')) -Quiet).Text.Trim()
    if ($remote -eq '.' -or $merge -notmatch '^refs/heads/' -or -not $remote) { throw '缺少明确远程 upstream。' }
    $url=(Invoke-JobsGit $Repository @('remote','get-url',$remote) -Quiet).Text
    Write-JobsStatus "来源：$remote $(Protect-JobsText $url)；目标：$Repository；分支：$merge"
    [void](Invoke-JobsGit $Repository @('fetch','--no-recurse-submodules',$remote,$merge))
    $target=(Invoke-JobsGit $Repository @('rev-parse','FETCH_HEAD^{commit}') -Quiet).Text.Trim()
    [void](Invoke-JobsGit $Repository @('merge-base','--is-ancestor','HEAD',$target) -Quiet)
    $dirty=(Invoke-JobsGit $Repository @('status','--porcelain','--untracked-files=all','--ignore-submodules=all') -Quiet).Text
    $children=@(Get-JobsRepositoryQueue $Repository)
    foreach ($child in $children) {
        if ($child -eq $Repository) { continue }
        if ((Invoke-JobsGit $child @('status','--porcelain','--untracked-files=all','--ignore-submodules=none') -Quiet).Text) { throw "子仓存在修改，保留并停止：$child" }
        $head=(Invoke-JobsGit $child @('rev-parse','HEAD') -Quiet).Text.Trim()
        if ((Invoke-JobsGit $child @('rev-list',$head,'--not','--remotes') -Quiet).Text) { throw "子仓有未发布的独有提交，保留并停止：$child" }
    }
    if ($dirty) {
        Write-JobsStatus $dirty
        Confirm-JobsDanger "本仓存在修改：$Repository。YES 仅舍弃本仓已跟踪内容；未跟踪文件保留，冲突时 Git 停止。"
        [void](Invoke-JobsGit $Repository @('-c','submodule.recurse=false','reset','--hard','--no-recurse-submodules','HEAD'))
    }
    [void](Invoke-JobsGit $Repository @('merge','--ff-only','--no-edit',$target))
    [void](Invoke-JobsGit $Repository @('submodule','sync','--recursive'))
    [void](Invoke-JobsGit $Repository @('submodule','update','--init','--recursive','--checkout'))
}
# 子仓先于父仓，未初始化子模块停止，避免误交空目录。
function Get-JobsRepositoryQueue {
    param([string]$Repository)
    $moduleFile=Join-Path $Repository '.gitmodules'
    if (Test-Path -LiteralPath $moduleFile -PathType Leaf) {
        $result=Invoke-JobsGit $Repository @('config','--file',$moduleFile,'--get-regexp','^submodule\..*\.path$') -Quiet -AllowFailure
        if ($result.Code -notin @(0,1)) { throw '无法读取子模块。' }
        foreach ($line in @($result.Text -split "`n")) {
            if (-not $line) { continue }
            $rel=($line -split '\s+',2)[1]
            $path=[IO.Path]::GetFullPath((Join-Path $Repository $rel))
            if (-not $path.StartsWith($Repository.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw '子模块越界。' }
            if (-not (Test-Path -LiteralPath (Join-Path $path '.git'))) { throw "子模块未初始化：$path" }
            $root=Resolve-JobsRepository $path
            if ($root.Replace('\','/').TrimEnd('/') -ine $path.Replace('\','/').TrimEnd('/')) { throw "子模块工作树错位：$path" }
            Get-JobsRepositoryQueue $path
        }
    }
    $Repository
}
# 保存队列阶段；失败仓复用同一提交，状态文件从不作为代码执行。
function Save-JobsPushCheckpoint {
    param([string]$Path,$State)
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temporary,($State|ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($true)))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}
# 配置只存摘要，续跑可识别远端/映射变化，不把凭据写入状态。
function Get-JobsPushConfigHash {
    param([string]$Repository)
    $text=(Invoke-JobsGit $Repository @('config','--null','--list','--show-origin') -Quiet).Text
    $sha=[Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).Replace('-','') }
    finally { $sha.Dispose() }
}
# 拒绝未完成操作和锁，不能把未解决现场自动暂存成新提交。
function Assert-JobsGitReady {
    param([string]$Repository)
    $gitdir=(Invoke-JobsGit $Repository @('rev-parse','--absolute-git-dir') -Quiet).Text.Trim()
    foreach($entry in @('index.lock','MERGE_HEAD','CHERRY_PICK_HEAD','REVERT_HEAD','rebase-merge','rebase-apply','sequencer')) {
        if(Test-Path -LiteralPath (Join-Path $gitdir $entry)){throw "存在未完成 Git 操作/锁：$Repository / $entry"}
    }
    if((Invoke-JobsGit $Repository @('ls-files','--unmerged') -Quiet).Text){throw "存在未合并索引：$Repository"}
}
# 续跑只接受原分支、原提交、原配置；已完成线路按远端真值重新核验。
function Assert-JobsPushEntry {
    param($Entry,[switch]$Remote)
    Assert-JobsGitReady $Entry.Path
    $now=(Invoke-JobsGit $Entry.Path @('rev-parse','HEAD') -Quiet).Text.Trim()
    $branch=(Invoke-JobsGit $Entry.Path @('symbolic-ref','--quiet','--short','HEAD') -Quiet).Text.Trim()
    if($now -cne $Entry.Head -or $branch -cne $Entry.Branch -or (Get-JobsPushConfigHash $Entry.Path) -cne $Entry.ConfigHash -or (Invoke-JobsGit $Entry.Path @('status','--porcelain','--ignore-submodules=none') -Quiet).Text){throw '检查点之后仓库/配置发生变化；保留现场，请选择从头执行。'}
    if($Remote){
        foreach($target in @($Entry.Targets)){
            $actual=(Invoke-JobsGit $Entry.Path @('ls-remote','--heads',$target.Remote,('refs/heads/'+$target.Branch)) -Quiet).Text
            if(($actual -split '\s+')[0] -cne $Entry.Head){throw '已完成仓库的远端发生变化，请从头执行。'}
        }
    }
}
# 逐层使用现有分支，获取全部线路后整合并显式推送同一 HEAD。
function Invoke-JobsPushCore {
    param([string]$Repository)
    $queue=@(Get-JobsRepositoryQueue $Repository)
    $gitdir=(Invoke-JobsGit $Repository @('rev-parse','--absolute-git-dir') -Quiet).Text.Trim()
    $checkpoint=Join-Path $gitdir 'jobs-windows-push-checkpoint.json'
    $state=[pscustomobject]@{Version=2;Queue=$queue;Done=@();Active=$null}
    if(Test-Path -LiteralPath $checkpoint){
        $saved=Get-Content -LiteralPath $checkpoint -Raw -Encoding UTF8|ConvertFrom-Json
        if((Read-Host '已有中断检查点：R 从失败处继续；其它从头执行') -ceq 'R'){
            if($saved.Version -ne 2 -or ($saved.Queue -join "`n") -cne ($queue -join "`n")){throw '检查点版本或队列变化，不能继续旧状态。'}
            for($i=0;$i -lt @($saved.Done).Count;$i++){
                if($saved.Done[$i].Path -cne $queue[$i]){throw '完成队列不是连续前缀，停止。'}
                Assert-JobsPushEntry $saved.Done[$i] -Remote
            }
            if($null -ne $saved.Active){
                if($saved.Active.Path -cne $queue[@($saved.Done).Count]){throw '失败仓与队列不匹配。'}
                Assert-JobsPushEntry $saved.Active
            }
            $state=$saved
        }
    }
    Confirm-JobsDanger ("将对子仓到父仓依次暂存全部修改、空消息提交、推送各明确线路：`n"+($queue -join "`n"))
    Save-JobsPushCheckpoint $checkpoint $state
    foreach($repo in $queue){
        if(@($state.Done|Where-Object Path -eq $repo).Count){continue}
        Assert-JobsGitReady $repo
        if($null -eq $state.Active){
            if((Split-Path -Leaf $repo) -eq 'JobsOCBaseConfigDemo@ByPods' -or (Invoke-JobsGit $repo @('remote','-v') -Quiet).Text -match 'Gitee@snapshot'){throw '独立快照仓库必须使用专用流程。'}
            $branch=(Invoke-JobsGit $repo @('symbolic-ref','--short','--quiet','HEAD') -Quiet).Text.Trim()
            if(-not $branch){throw "游离 HEAD：$repo；先恢复明确的已有分支。"}
            $remotes=@(((Invoke-JobsGit $repo @('remote') -Quiet).Text -split "`n")|Where-Object{$_})
            if(-not $remotes.Count){throw "没有远端：$repo"}
            $targets=@()
            foreach($remote in $remotes){
                $override=Invoke-JobsGit $repo @('config','--local',('remote.'+$remote+'.jobsPushBranch')) -Quiet -AllowFailure
                if($override.Code -notin @(0,1)){throw '读取目标分支失败。'}
                $target=$override.Text.Trim()
                if(-not $target){
                    if($remote -eq 'gitee'){$target='gitee'}
                    else{
                        $upstreamRemote=(Invoke-JobsGit $repo @('config',('branch.'+$branch+'.remote')) -Quiet -AllowFailure).Text.Trim()
                        if($upstreamRemote -eq $remote){$target=(Invoke-JobsGit $repo @('config',('branch.'+$branch+'.merge')) -Quiet).Text.Trim() -replace '^refs/heads/',''}
                        else{throw "$repo 的 $remote 目标分支不明确；配置本仓 remote.$remote.jobsPushBranch 后重试。"}
                    }
                }
                [void](Invoke-JobsGit $repo @('check-ref-format','--branch',$target) -Quiet)
                $fetchUrls=@(((Invoke-JobsGit $repo @('remote','get-url','--all',$remote) -Quiet).Text -split "`n")|Where-Object{$_})
                $pushUrls=@(((Invoke-JobsGit $repo @('remote','get-url','--push','--all',$remote) -Quiet).Text -split "`n")|Where-Object{$_})
                if($fetchUrls.Count -ne 1 -or $pushUrls.Count -ne 1 -or $fetchUrls[0] -cne $pushUrls[0]){throw "$remote 存在不同或多个 pushurl；本动作在提交前停止，请使用明确单线路配置。"}
                Write-JobsStatus "来源：$remote $(Protect-JobsText $fetchUrls[0])；仓库：$repo；分支：$target"
                [void](Invoke-JobsGit $repo @('fetch','--no-recurse-submodules',$remote,('refs/heads/'+$target)))
                $commit=(Invoke-JobsGit $repo @('rev-parse','FETCH_HEAD^{commit}') -Quiet).Text.Trim()
                $targets+=[pscustomobject]@{Remote=$remote;Branch=$target;Commit=$commit}
            }
            [void](Invoke-JobsGit $repo @('add','--all'))
            $messageFile=Join-Path ([IO.Path]::GetTempPath()) ('jobs-empty-message-'+[guid]::NewGuid().ToString('N'))
            [IO.File]::WriteAllBytes($messageFile,[byte[]]@())
            try{[void](Invoke-JobsGit $repo @('commit','--allow-empty-message','--allow-empty','--file',$messageFile))}
            finally{Remove-Item -LiteralPath $messageFile}
            $state.Active=[pscustomobject]@{Path=$repo;Branch=$branch;Head=(Invoke-JobsGit $repo @('rev-parse','HEAD') -Quiet).Text.Trim();ConfigHash=(Get-JobsPushConfigHash $repo);Targets=$targets;Stage='committed'}
            Save-JobsPushCheckpoint $checkpoint $state
        }
        if($state.Active.Stage -eq 'committed'){
            foreach($target in @($state.Active.Targets)){
                [void](Invoke-JobsGit $repo @('merge','--no-edit',$target.Commit))
                $state.Active.Head=(Invoke-JobsGit $repo @('rev-parse','HEAD') -Quiet).Text.Trim()
                Save-JobsPushCheckpoint $checkpoint $state
            }
            $state.Active.Stage='ready'
            Save-JobsPushCheckpoint $checkpoint $state
        }
        if($state.Active.Stage -ne 'ready'){throw '未知检查点阶段。'}
        $head=$state.Active.Head
        foreach($target in @($state.Active.Targets)){
            [void](Invoke-JobsGit $repo @('push',$target.Remote,('HEAD:refs/heads/'+$target.Branch)))
            $actual=(Invoke-JobsGit $repo @('ls-remote','--heads',$target.Remote,('refs/heads/'+$target.Branch)) -Quiet).Text
            if(($actual -split '\s+')[0] -cne $head){throw '远端提交核验失败；保留当前仓检查点。'}
        }
        $state.Done=@($state.Done)+@($state.Active)
        $state.Active=$null
        Save-JobsPushCheckpoint $checkpoint $state
    }
    Remove-Item -LiteralPath $checkpoint
}
# 用操作系统排他锁保护整个推送队列，异常退出也会释放句柄。
function Push-JobsRepositoryTree {
    param([string]$Repository)
    $gitdir=(Invoke-JobsGit $Repository @('rev-parse','--absolute-git-dir') -Quiet).Text.Trim()
    $lease=[IO.File]::Open((Join-Path $gitdir 'jobs-windows-push.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try { Invoke-JobsPushCore $Repository }
    finally { $lease.Dispose() }
}
# 检查并备份残留锁；不删除正在使用的 Git 元数据。
function Repair-JobsCommit {
    param([string]$Repository)
    $gitdir=(Invoke-JobsGit $Repository @('rev-parse','--absolute-git-dir') -Quiet).Text.Trim()
    $lock=Join-Path $gitdir 'index.lock'
    [void](Invoke-JobsGit $Repository @('fsck','--no-reflogs','--connectivity-only'))
    if (Test-Path -LiteralPath $lock) {
        if (@(Get-Process -Name git,git-remote-https,SourceTree -ErrorAction SilentlyContinue).Count) { throw '存在 Git/Sourcetree 进程，请关闭后在独立终端重试，不移动锁。' }
        $handle=[IO.File]::Open($lock,'Open','ReadWrite','None');$handle.Dispose()
        Confirm-JobsDanger "确认已排除在途任务，归档锁文件：$lock"
        Move-Item -LiteralPath $lock -Destination ($lock+'.backup.'+(Get-Date -Format 'yyyyMMddHHmmss'))
    }
    [void](Invoke-JobsGit $Repository @('status','--porcelain=v1'))
    [void](Invoke-JobsGit $Repository @('submodule','status','--recursive'))
    [void](Invoke-JobsGit $Repository @('add','--dry-run','--all'))
    Write-JobsStatus '提交入口已检查；未自动覆盖 gitlink 或重建索引。路径错位/缺失子仓请按诊断修复。'
}
# 先 fetch/prune，失败仅整理 Git 自身引用，不处理网络与凭据。
function Repair-JobsFetch {
    param([string]$Repository)
    $remotes=@(((Invoke-JobsGit $Repository @('remote') -Quiet).Text -split "`n") | Where-Object { $_ })
    foreach ($remote in $remotes) {
        $url=(Invoke-JobsGit $Repository @('remote','get-url',$remote) -Quiet).Text
        Write-JobsStatus "来源：$remote $(Protect-JobsText $url)；目标：$Repository"
        $result=Invoke-JobsGit $Repository @('fetch','--prune',$remote) -AllowFailure
        if ($result.Code -eq 0) { continue }
        if ($result.Text -notmatch '(cannot lock ref|not a directory|exists; cannot create|unable to resolve reference)') { throw 'Fetch 为网络/认证/其它错误，保留引用现场。' }
        [void](Invoke-JobsGit $Repository @('remote','prune',$remote))
        $result=Invoke-JobsGit $Repository @('fetch','--prune',$remote) -AllowFailure
        if ($result.Code -eq 0) { continue }
        Confirm-JobsDanger '仍有引用路径冲突，将用 git pack-refs 保存有效引用并释放 loose ref 路径。'
        [void](Invoke-JobsGit $Repository @('pack-refs','--all'))
        [void](Invoke-JobsGit $Repository @('fetch','--prune',$remote))
    }
}
# 查找常见 Windows IDE 安装路径，工具缺失时明确停止。
function Find-JobsEditor {
    param([string]$Name)
    $candidates=switch ($Name) {
        'code' { @('code', (Join-Path $env:LOCALAPPDATA 'Programs/Microsoft VS Code/Code.exe')) }
        'trae' { @('trae',(Join-Path $env:LOCALAPPDATA 'Programs/Trae/Trae.exe')) }
        'studio' { @('studio64.exe',(Join-Path $env:ProgramFiles 'Android/Android Studio/bin/studio64.exe')) }
        'typora' { @('typora',(Join-Path $env:ProgramFiles 'Typora/Typora.exe')) }
    }
    foreach ($candidate in $candidates) { $cmd=Get-Command $candidate -ErrorAction SilentlyContinue; if($cmd){ return $cmd.Source } }
    throw "找不到 $Name，请安装对应 Windows 工具或加入 PATH。"
}
# 打开编辑器时可指定 Java17，仅影响新进程及其后代。
function Open-JobsEditor {
    param([string]$Name,[string]$Directory,[switch]$Java17)
    $editor=Find-JobsEditor $Name
    $old=$env:JAVA_HOME
    try {
        if ($Java17) {
            $jdk=Read-Host '输入已安装 JDK17 的目录，仅供本次新进程使用'
            $jdk=Resolve-JobsDirectory $jdk
            [void](Invoke-JobsTool (Join-Path $jdk 'bin/java.exe') @('-version') $Directory)
            $version=Invoke-JobsTool (Join-Path $jdk 'bin/java.exe') @('-version') $Directory -Quiet
            if ($version.Text -notmatch 'version "17\.') { throw '需要 JDK17。' }
            $env:JAVA_HOME=$jdk
        }
        $quoted='"'+$Directory.Replace('"','\"')+'"'
        $working=$Directory
        if(Test-Path -LiteralPath $Directory -PathType Leaf){$working=Split-Path -Parent $Directory}
        Start-Process -FilePath $editor -ArgumentList $quoted -WorkingDirectory $working | Out-Null
    } finally { $env:JAVA_HOME=$old }
}
# 启动 pnpm 项目；窗口保留构建日志，关闭窗口即可停止开发服务。
function Start-JobsWebProject {
    param([string]$Directory,[switch]$Magic)
    if ($Magic) {
        $match=$false
        if (Test-Path -LiteralPath (Join-Path $Directory '.git')) { $match=(Invoke-JobsGit $Directory @('remote','-v') -Quiet).Text -match 'github\.com[:/]JOYCEQL/magic-resume(?:\.git)?(?:\s|$)' }
        if (-not $match) {
            foreach ($sibling in Get-ChildItem -LiteralPath (Split-Path -Parent $Directory) -Directory) {
                if (($sibling.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $sibling.FullName '.git'))) { continue }
                if ((Invoke-JobsGit $sibling.FullName @('remote','-v') -Quiet).Text -match 'github\.com[:/]JOYCEQL/magic-resume(?:\.git)?(?:\s|$)') { $Directory=$sibling.FullName;$match=$true;break }
            }
        }
        if (-not $match) {
            $destination=Join-Path (Split-Path -Parent $Directory) ('magic-resume-'+[guid]::NewGuid().ToString('N').Substring(0,8))
            Write-JobsStatus "来源：https://github.com/JOYCEQL/magic-resume.git；目标：$destination"
            [void](Invoke-JobsGit $Directory @('clone','--','https://github.com/JOYCEQL/magic-resume.git',$destination))
            $Directory=$destination
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Directory 'package.json'))) { throw '目标缺少 package.json。' }
    [void](Invoke-JobsTool 'node' @('--version') $Directory)
    [void](Invoke-JobsTool 'pnpm' @('--version') $Directory)
    if ($Magic) {
        if (@(Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue).Count) { throw '3000 端口已占用，保留已有进程并停止。' }
        [void](Invoke-JobsTool 'pnpm' @('install','--frozen-lockfile') $Directory)
        Write-JobsStatus 'Magic Resume：http://localhost:3000；此窗口运行服务，Ctrl+C 停止。'
        Push-Location -LiteralPath $Directory
        try { & pnpm dev --port 3000 --strictPort; if($LASTEXITCODE -ne 0){throw '开发服务失败。'} } finally { Pop-Location }
    } else {
        if (-not (Test-Path -LiteralPath (Join-Path $Directory 'wrangler.toml')) -and -not (Test-Path -LiteralPath (Join-Path $Directory 'wrangler.jsonc'))) { throw '缺少 Wrangler 工程配置。' }
        [void](Invoke-JobsTool 'pnpm' @('install','--frozen-lockfile') $Directory)
        [void](Invoke-JobsTool 'pnpm' @('exec','wrangler','whoami') $Directory)
        Confirm-JobsDanger '将按已有 Wrangler 配置部署到 Cloudflare，可能更新线上 Worker；不改签名、账户或 KV。'
        [void](Invoke-JobsTool 'pnpm' @('exec','wrangler','deploy') $Directory)
    }
}
# 验证本动作需要的工具，发现候选后再执行最小健康检查。
function Find-JobsRemoteTool {
    param([string]$Name,[string]$Directory)
    $candidates=@(Get-Command $Name -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object Source)
    if ($Name -eq 'git') {
        foreach ($base in @($env:LOCALAPPDATA,$env:ProgramFiles,${env:ProgramFiles(x86)})) {
            if ($base) {
                $candidates+=@(Join-Path $base 'Programs/Git/cmd/git.exe')
                $candidates+=@(Join-Path $base 'Git/cmd/git.exe')
                $candidates+=@(Join-Path $base 'Atlassian/SourceTree/git_local/bin/git.exe')
            }
        }
    }
    if ($Name -eq 'fzf' -and $env:LOCALAPPDATA) {
        $candidates+=@(Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Links/fzf.exe')
    }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        try {
            $health=Invoke-JobsTool $candidate @('--version') $Directory -Quiet
            if ($health.Text -notmatch '\d+\.\d+') { continue }
            if ($Name -eq 'winget') { [void](Invoke-JobsTool $candidate @('--info') $Directory -Quiet) }
            if ($Name -eq 'fzf') {
                $help=(Invoke-JobsTool $candidate @('--help') $Directory -Quiet).Text
                foreach ($flag in @('--multi','--layout','--prompt','--header')) {
                    if (-not $help.Contains($flag)) { throw "fzf 缺少必要选项：$flag" }
                }
                Test-JobsRemoteFzfOptions $candidate
            }
            return $candidate
        } catch { Write-JobsStatus "工具体检失败：$candidate；$($_.Exception.Message)" }
    }
    return $null
}
# 用无交互过滤验证实际选择参数，屏蔽用户额外绑定后恢复环境。
function Test-JobsRemoteFzfOptions {
    param([string]$Fzf)
    $keys=@('FZF_DEFAULT_OPTS','FZF_DEFAULT_OPTS_FILE','FZF_DEFAULT_COMMAND','FZF_DEFAULT_COMMAND_FILE')
    $saved=@{}
    foreach ($key in $keys) { $saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process');Remove-Item -LiteralPath ('Env:'+$key) -ErrorAction SilentlyContinue }
    try {
        $probe=@('jobs-fzf-option-probe' | & $Fzf --no-multi --reverse --prompt 'remote > ' --header 'probe' --filter 'jobs-fzf-option-probe')
        if ($LASTEXITCODE -ne 0 -or $probe.Count -ne 1 -or $probe[0] -cne 'jobs-fzf-option-probe') { throw 'fzf 实际参数验证失败。' }
    } finally {
        foreach ($key in $keys) { if ($null -eq $saved[$key]) { Remove-Item -LiteralPath ('Env:'+$key) -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') } }
    }
}
# 仅刷新当前进程，合并安装器新登记的路径。
function Update-JobsRemoteSessionPath {
    $paths=@($env:PATH -split [IO.Path]::PathSeparator)
    foreach ($scope in @('User','Machine')) {
        $paths+=@([Environment]::GetEnvironmentVariable('PATH',$scope) -split [IO.Path]::PathSeparator)
    }
    if ($env:LOCALAPPDATA) { $paths+=@(Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Links') }
    $env:PATH=(@($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) -join [IO.Path]::PathSeparator)
}
# 确保选择和安装只能在真实交互终端中进行。
function Assert-JobsRemoteTerminal {
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { throw '需要独立交互终端，已停止；请从 CMD/PowerShell 重试。' }
}
# 仅沿缺失分支检查 WinGet，当前用户一次安装或修复后重新体检。
function Ensure-JobsRemoteTool {
    param([string]$Name,[string]$Directory)
    $tool=Find-JobsRemoteTool $Name $Directory
    if ($tool) { return $tool }
    Assert-JobsRemoteTerminal
    $winget=Find-JobsRemoteTool 'winget' $Directory
    if (-not $winget) {
        throw '依赖链停在 WinGet/App Installer。请按 https://learn.microsoft.com/windows/package-manager/winget/ 修复 App Installer 后重试；未继续安装或执行。'
    }
    $package=if ($Name -eq 'git') { 'Git.Git' } elseif ($Name -eq 'fzf') { 'junegunn.fzf' } else { throw "不支持的依赖：$Name" }
    Write-JobsStatus "依赖来源：WinGet 官方 winget 源；包：$package；范围：当前用户。会联网安装/修复，不主动提权。"
    if ((Read-Host '缺少或损坏的必需依赖；按回车安装/修复，任意字符取消') -cne '') { throw '已取消依赖安装。' }
    [void](Invoke-JobsTool $winget @('install','--id',$package,'--exact','--source','winget','--scope','user','--force','--accept-source-agreements','--accept-package-agreements','--disable-interactivity') $Directory)
    Update-JobsRemoteSessionPath
    $tool=Find-JobsRemoteTool $Name $Directory
    if (-not $tool) { throw "$Name 一次安装/修复后二次体检失败，停止下游动作；请检查安装日志和 PATH。" }
    return $tool
}
# 所有 remote 的全部有效 fetch/push 地址按原值去重，不优先 origin。
function Get-JobsRemoteAddresses {
    param([string]$Repository)
    $result=New-Object 'Collections.Generic.List[object]'
    $byUrl=New-Object 'Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
    $names=(Invoke-JobsGit $Repository @('remote') -Quiet).Text -split "`n"
    foreach ($remote in $names) {
        if (-not $remote) { continue }
        if ($remote -match '[\x00-\x1f\x7f]') { throw '远程名称包含控制字符，停止。' }
        foreach ($key in @('url','pushurl')) {
            $raw=Invoke-JobsGit $Repository @('config','--null','--get-all',('remote.'+$remote+'.'+$key)) -Quiet -AllowFailure
            if ($raw.Code -notin @(0,1)) { throw '读取远程 URL 配置失败，停止。' }
            foreach ($value in $raw.Text.Split([char]0)) {
                if ($value -match '[\x00-\x1f\x7f]') { throw '远程地址配置包含控制字符，停止。' }
            }
        }
        foreach ($kind in @('fetch','push')) {
            $arguments=@('remote','get-url','--all')
            if ($kind -eq 'push') { $arguments+=@('--push') }
            $arguments+=@($remote)
            $urls=(Invoke-JobsGit $Repository $arguments -Quiet).Text -split "`n"
            foreach ($url in $urls) {
                if (-not $url) { continue }
                if ($url -match '[\x00-\x1f\x7f]') { throw '远程地址包含控制字符，停止。' }
                $label="$remote/$kind"
                if ($byUrl.ContainsKey($url)) {
                    $byUrl[$url].Labels+=@($label)
                } else {
                    $item=[pscustomobject]@{Url=$url;Labels=@($label)}
                    $byUrl.Add($url,$item)
                    $result.Add($item)
                }
            }
        }
    }
    if ($result.Count -eq 0) { throw '当前 Git 仓库没有配置任何远程地址。' }
    return $result.ToArray()
}
# SSH/原生 Git 转网页地址，HTTP(S) 保留端口；不猜非标准 SSH 端口映射。
function ConvertTo-JobsRemoteWebUrl {
    param([string]$Url)
    if ($Url -match '[\x00-\x20\x7f\\]' -or $Url -match '^[a-zA-Z]:') { throw '该远程地址不能安全转换为仓库网页；请配置明确的 HTTP(S) 地址。' }
    $uri=$null
    if ($Url -match '^(?i)(https?|ssh|git)://' -and [Uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$uri)) {
        if (-not $uri.Host -or $uri.AbsolutePath -eq '/') { throw '远程地址缺少主机或仓库路径。' }
        $hostPart=$uri.Host
        if ($uri.HostNameType -eq [UriHostNameType]::IPv6 -and -not $hostPart.StartsWith('[')) { $hostPart='['+$hostPart+']' }
        if ($uri.Scheme -in @('http','https')) {
            $scheme=$uri.Scheme
            $port=if ($uri.IsDefaultPort) { '' } else { ':'+$uri.Port }
        } else {
            if ($uri.Scheme -eq 'ssh' -and $uri.Port -notin @(-1,22)) { throw '非标准 SSH 端口无法确定网页端口；请配置明确的 HTTP(S) 远程地址。' }
            if ($uri.Scheme -eq 'git' -and $uri.Port -notin @(-1,9418)) { throw '非标准 Git 端口无法确定网页端口；请配置明确的 HTTP(S) 远程地址。' }
            $scheme='https';$port=''
        }
        $path=$uri.AbsolutePath -replace '/+$','' -replace '\.git$',''
        return $scheme+'://'+$hostPart+$port+$path
    }
    if ($Url -match '://|^[a-zA-Z][a-zA-Z0-9+.-]*::' -or $Url -match '^(?i)(file|javascript|data|vbscript|mailto|about|shell|ms-[a-z-]+):') {
        throw '该协议不是可打开的仓库网页，请配置明确的 HTTP(S) 远程地址。'
    }
    if ($Url -match '^(?:[^/@:]+@)?(?<host>\[[0-9a-fA-F:]+\]|[^/:@]+):(?<path>[^?#]+)$') {
        $remoteHost=$Matches.host;$remotePath=$Matches.path -replace '^/+','' -replace '/+$','' -replace '\.git$',''
        if (-not $remotePath -or $remoteHost -match '[?#]') { throw '远程地址缺少有效主机或路径。' }
        $web='https://'+$remoteHost+'/'+$remotePath
        if (-not [Uri]::TryCreate($web,[UriKind]::Absolute,[ref]$uri) -or -not $uri.Host) { throw '远程地址不能转换为网页。' }
        # Framework 与现代 .NET 的 IPv6 AbsoluteUri 格式不同；保留已校验的主机字面量。
        return 'https://'+$remoteHost+$uri.AbsolutePath
    }
    throw '只支持 HTTP(S)、SSH/scp 和 git 远程网页；本地路径或其它协议不打开。'
}
# 选择面板只展示脱敏文本，返回值必须与原行精确匹配。
function Select-JobsRemoteAddress {
    param([object[]]$Addresses,[string]$Directory)
    Assert-JobsRemoteTerminal
    $fzf=Ensure-JobsRemoteTool 'fzf' $Directory
    $rows=@()
    for ($i=0;$i -lt $Addresses.Count;$i++) {
        $safe=Protect-JobsRemoteText $Addresses[$i].Url
        $labels=Protect-JobsRemoteText ($Addresses[$i].Labels -join ', ')
        $rows+=('{0} | {1} | {2}' -f ($i+1),$labels,$safe)
    }
    $keys=@('FZF_DEFAULT_OPTS','FZF_DEFAULT_OPTS_FILE','FZF_DEFAULT_COMMAND','FZF_DEFAULT_COMMAND_FILE')
    $saved=@{}
    foreach ($key in $keys) { $saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process');Remove-Item -LiteralPath ('Env:'+$key) -ErrorAction SilentlyContinue }
    $oldEncoding=$OutputEncoding;$oldConsoleEncoding=[Console]::OutputEncoding
    try {
        $OutputEncoding=New-Object Text.UTF8Encoding($false);[Console]::OutputEncoding=$OutputEncoding
        $result=Invoke-JobsRemoteFzf $fzf $rows
        $selection=@($result.Rows)
        $code=$result.Code
    } finally {
        $OutputEncoding=$oldEncoding;[Console]::OutputEncoding=$oldConsoleEncoding
        foreach ($key in $keys) { if ($null -eq $saved[$key]) { Remove-Item -LiteralPath ('Env:'+$key) -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') } }
    }
    if ($code -in @(1,130)) { Write-JobsStatus '已取消或没有匹配地址，未复制、未打开。';return $null }
    if ($code -ne 0) { throw "fzf 选择失败，退出码 $code；未复制、未打开。" }
    if ($selection.Count -ne 1) { throw 'fzf 没有返回唯一地址，停止。' }
    $index=[Array]::IndexOf([string[]]$rows,[string]$selection[0])
    if ($index -lt 0) { throw 'fzf 返回未知选项，停止。' }
    return $Addresses[$index]
}
# 保留 fzf 原始退出码，避免将取消与执行失败混在一起。
function Invoke-JobsRemoteFzf {
    param([string]$Fzf,[string[]]$Rows)
    $output=@($Rows | & $Fzf --no-multi --reverse --prompt '远程仓库 > ' --header '回车选择；Esc / Ctrl+C 取消（不复制、不打开）')
    [pscustomobject]@{Code=$LASTEXITCODE;Rows=$output}
}
# 用编码数据转交独立 PowerShell，路径不拼入可执行语句。
function Start-JobsRemoteTerminal {
    param([string]$EntryScript,[string]$Target)
    if (-not $EntryScript -or -not (Test-Path -LiteralPath $EntryScript -PathType Leaf)) { throw '没有有效动作入口，无法打开选择终端。' }
    $payload=@{Script=$EntryScript;Target=$Target}|ConvertTo-Json -Compress
    $data=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    $code='$p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("'+$data+'"))|ConvertFrom-Json; & $p.Script -Target $p.Target -Terminal'
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $hostPath=Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $hostPath -PathType Leaf)) { $hostPath=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe' }
    Start-Process -FilePath $hostPath -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) -ErrorAction Stop | Out-Null
    Write-JobsStatus '已打开独立终端；请在新窗口确认并选择。'
}
# 两个动作共用候选与分流，单地址直接执行，多地址只在独立终端选择。
function Invoke-JobsRemoteAddressCore {
    param([string]$Target,[switch]$Open,[switch]$SourceTree,[string]$EntryScript)
    $directory=Resolve-JobsDirectory $Target
    $git=Find-JobsRemoteTool 'git' $directory
    if (-not $git -and $SourceTree) { Start-JobsRemoteTerminal $EntryScript $directory;return }
    if (-not $git) { $git=Ensure-JobsRemoteTool 'git' $directory }
    $env:PATH=(Split-Path -Parent $git)+[IO.Path]::PathSeparator+$env:PATH
    $repository=Resolve-JobsRepository $directory
    $addresses=@(Get-JobsRemoteAddresses $repository)
    if ($addresses.Count -gt 1 -and $SourceTree) { Start-JobsRemoteTerminal $EntryScript $repository;return }
    $selected=if ($addresses.Count -eq 1) { $addresses[0] } else { Select-JobsRemoteAddress $addresses $repository }
    if ($null -eq $selected) { return }
    Write-JobsStatus ('远程：'+(Protect-JobsRemoteText ($selected.Labels -join ', '))+'；地址：'+(Protect-JobsRemoteText $selected.Url))
    if ($Open) {
        $web=ConvertTo-JobsRemoteWebUrl $selected.Url
        Start-Process -FilePath $web -ErrorAction Stop | Out-Null
        Write-JobsStatus ('已打开仓库网页：'+$web)
    } else {
        Set-Clipboard -Value $selected.Url -ErrorAction Stop
        Write-JobsStatus '已复制原始远程地址到剪贴板。'
    }
}
# 远程动作专用脱敏，覆盖所有协议查询串、片段、userinfo 与控制字符。
function Protect-JobsRemoteText {
    param([string]$Text)
    $Text -replace '[\x00-\x1f\x7f]',' ' -replace '(?i)([a-z][a-z0-9+.-]*://)[^/\s]*@','$1***@' -replace '^[^/\s@:]+@','***@' -replace '[?#].*$','?[已省略]'
}
# 隔离 Sourcetree/调用终端继承的仓库寻址变量，结束后原样恢复。
function Invoke-JobsRemoteAddress {
    param([string]$Target,[switch]$Open,[switch]$SourceTree,[string]$EntryScript)
    $keys=@('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR','GIT_INDEX_FILE','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES','GIT_PREFIX','GIT_NAMESPACE','GIT_CEILING_DIRECTORIES','GIT_DISCOVERY_ACROSS_FILESYSTEM','GIT_SUPER_PREFIX')
    $saved=@{};$previousPath=$env:PATH
    foreach ($key in $keys) { $saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process');Remove-Item -LiteralPath ('Env:'+$key) -ErrorAction SilentlyContinue }
    try { Invoke-JobsRemoteAddressCore $Target -Open:$Open -SourceTree:$SourceTree -EntryScript $EntryScript }
    finally {
        $env:PATH=$previousPath
        foreach ($key in $keys) { if ($null -eq $saved[$key]) { Remove-Item -LiteralPath ('Env:'+$key) -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') } }
    }
}
# 根据稳定标识执行业务，传入路径不作为代码求值。
function Invoke-JobsSourceTreeAction {
    param([string]$Action,[string]$Target,[string]$Option,[string]$Value,[switch]$SourceTree,[string]$EntryScript)
    $script:LogFile=Join-Path ([IO.Path]::GetTempPath()) ('JobsSourceTree-'+$Action+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N')+'.log')
    Write-JobsStatus "动作：$Action；目标：$Target；日志：$script:LogFile"
    $dir=Resolve-JobsDirectory $Target
    switch ($Action) {
        'doctor' { Invoke-JobsFeatureModule 'JobsFlutterDoctor' $dir }
        'codegen' { Invoke-JobsFeatureModule 'JobsFlutterCodegen' $dir }
        'dependencies' { Invoke-JobsFeatureModule 'JobsFlutterDependencyExtractor' $dir }
        'android' { Invoke-JobsFeatureModule 'JobsFlutterPackager' $dir 'android' }
        'ohos' { Invoke-JobsFeatureModule 'JobsFlutterPackager' $dir 'ohos' }
        'pubget' { [void](Invoke-JobsTool (Get-JobsFlutter $dir) @('pub','get') $dir) }
        'run' {
            $runnerPath = Join-Path $PSScriptRoot 'Features/JobsFlutterRunner/Scripts/Action.psm1'
            $runner = Import-Module $runnerPath -Force -PassThru -DisableNameChecking
            $selection = & $runner {
                param($Project)
                Assert-JobsFlutterProject $Project
                $flutter = Get-JobsRunnerFlutter $Project
                $device = Select-JobsRunnerDevice $flutter $Project
                if ($null -eq $device) { return $null }
                return [pscustomobject]@{ Flutter = $flutter; Device = $device; AndroidSdk = $script:RunnerSelectedSdk }
            } $dir
            if ($null -eq $selection) { Write-JobsStatus '已取消运行。'; return }
            $oldAndroidHome = $env:ANDROID_HOME
            $oldAndroidRoot = $env:ANDROID_SDK_ROOT
            Push-Location -LiteralPath $dir
            try {
                if ($selection.AndroidSdk) { $env:ANDROID_HOME = $selection.AndroidSdk; $env:ANDROID_SDK_ROOT = $selection.AndroidSdk }
                & $selection.Flutter run -d $selection.Device
                if ($LASTEXITCODE -ne 0) { throw 'Flutter run 失败。' }
            } finally { Pop-Location; $env:ANDROID_HOME = $oldAndroidHome; $env:ANDROID_SDK_ROOT = $oldAndroidRoot }
        }
        'imports' { Repair-JobsFlutterImports $dir }
        'rollback' { Reset-JobsCommit (Resolve-JobsRepository $dir) $Option $Value }
        'pull' { Receive-JobsRepository (Resolve-JobsRepository $dir) }
        'push' { Push-JobsRepositoryTree (Resolve-JobsRepository $dir) }
        'commit-repair' { Repair-JobsCommit (Resolve-JobsRepository $dir) }
        'fetch-repair' { Repair-JobsFetch (Resolve-JobsRepository $dir) }
        'remote' { Invoke-JobsRemoteAddress $dir -SourceTree:$SourceTree -EntryScript $EntryScript }
        'remote-open' { Invoke-JobsRemoteAddress $dir -Open -SourceTree:$SourceTree -EntryScript $EntryScript }
        'path' { Write-JobsStatus $dir; Set-Clipboard -Value $dir }
        'terminal' { Start-Process powershell.exe -WorkingDirectory $dir }
        'code' { Open-JobsEditor 'code' $dir }
        'code17' { Open-JobsEditor 'code' $dir -Java17 }
        'trae' { Open-JobsEditor 'trae' $dir }
        'trae17' { Open-JobsEditor 'trae' $dir -Java17 }
        'studio' { Open-JobsEditor 'studio' $dir }
        'studio17' { Open-JobsEditor 'studio' $dir -Java17 }
        'typora' { $file=Join-Path $dir 'README.md';if(-not(Test-Path -LiteralPath $file)){throw '目标没有 README.md。'};Open-JobsEditor 'typora' $file }
        'unblock' {
            $files=@(Get-JobsSourceFiles $dir | Where-Object Extension -in @('.ps1','.cmd','.bat'))
            Write-JobsStatus ($files.FullName -join "`n")
            Confirm-JobsDanger '仅对上列可信脚本去除 Zone.Identifier 下载标记；不更改系统执行策略。'
            foreach($file in $files){Unblock-File -LiteralPath $file.FullName}
        }
        'magic' {Start-JobsWebProject $dir -Magic}
        'edgetunnel' {Start-JobsWebProject $dir}
        'download' {
            $destination=Join-Path $env:USERPROFILE ('SourceTree.command.download-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
            Write-JobsStatus "来源：https://github.com/JobsKits/SourceTree.sh.git；目标：$destination"
            [void](Invoke-JobsGit $dir @('clone','--','https://github.com/JobsKits/SourceTree.sh.git',$destination))
        }
        default { throw "未知动作：$Action" }
    }
    Write-JobsStatus '动作完成。'
}
Export-ModuleMember -Function Invoke-JobsSourceTreeAction
