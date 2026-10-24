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
    try {
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = 0
        $lines = @(& $command.Source @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference; Pop-Location }
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
    elseif ($Kind -eq 'ohos') { & $module { param($p) Invoke-JobsPackagerHarmonyBuild -Project $p -Type 'hap' } $Target }
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
# 根据稳定标识执行业务，传入路径不作为代码求值。
function Invoke-JobsSourceTreeAction {
    param([string]$Action,[string]$Target,[string]$Option,[string]$Value)
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
            $flutter=Get-JobsFlutter $dir
            $result=Invoke-JobsTool $flutter @('devices','--machine') $dir -Quiet
            $devices=@($result.Text | ConvertFrom-Json | Where-Object { $_.isSupported -ne $false -and $_.targetPlatform -notmatch 'ios|darwin' })
            if (-not $devices.Count) { throw '没有 Android/Web/Windows 可运行设备，请先启动设备。' }
            for($i=0;$i -lt $devices.Count;$i++){ Write-JobsStatus ("$($i+1)、"+$devices[$i].name+' ['+$devices[$i].id+']') }
            $selection=Read-Host '输入设备编号，回车取消'
            if ($selection -notmatch '^\d+$' -or [int]$selection -lt 1 -or [int]$selection -gt $devices.Count) { throw '已取消。' }
            Push-Location -LiteralPath $dir
            try { & $flutter run -d $devices[[int]$selection-1].id; if($LASTEXITCODE -ne 0){throw 'Flutter run 失败。'} } finally {Pop-Location}
        }
        'imports' { Repair-JobsFlutterImports $dir }
        'rollback' { Reset-JobsCommit (Resolve-JobsRepository $dir) $Option $Value }
        'pull' { Receive-JobsRepository (Resolve-JobsRepository $dir) }
        'push' { Push-JobsRepositoryTree (Resolve-JobsRepository $dir) }
        'commit-repair' { Repair-JobsCommit (Resolve-JobsRepository $dir) }
        'fetch-repair' { Repair-JobsFetch (Resolve-JobsRepository $dir) }
        'remote' { [void](Invoke-JobsGit (Resolve-JobsRepository $dir) @('remote','-v')) }
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
