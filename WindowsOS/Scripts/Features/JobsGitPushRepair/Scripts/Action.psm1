# JobsGitPushRepair | Jobs Windows Sourcetree Push 排障模块
# Created by Jobs on 2026年11月5日，星期四.

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

Set-StrictMode -Version 2.0
$script:PushLog = ''
# 展示副本统一脱敏，原始 URL 只作为参数交给 Git。
function Protect-JobsPushText {
    param([string]$Text)
    $Text -replace '(?im)^.*(?:Proxy-Authorization|Authorization)\s*:.*$','[Authorization header omitted]' -replace '\x1b\[[0-9;]*[A-Za-z]','' -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@','$1***@' -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*','$1?[已省略]'
}
# 同步展示和保存纯文本诊断，避免把凭据写入日志。
function Write-JobsPushStatus {
    param([string]$Text)
    $safe = Protect-JobsPushText $Text
    Write-JobsUrlText $safe
    if ($script:PushLog) { Add-Content -LiteralPath $script:PushLog -Value $safe -Encoding UTF8 }
}
# Git 参数逐项传递；实际失败以退出码判定，兼容 Windows PowerShell 的 stderr 包装。
function Invoke-JobsPushGit {
    param([string]$Repository,[string[]]$Arguments,[switch]$Show)
    $savedPreference = $ErrorActionPreference
    $savedEncoding = $OutputEncoding
    $savedConsole = [Console]::OutputEncoding
    try {
        $ErrorActionPreference = 'Continue'
        $OutputEncoding = New-Object Text.UTF8Encoding($false)
        [Console]::OutputEncoding = $OutputEncoding
        $global:LASTEXITCODE = 0
        $lines = @(& git --no-optional-locks -C $Repository -c color.ui=false -c core.quotepath=false @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedPreference
        $OutputEncoding = $savedEncoding
        [Console]::OutputEncoding = $savedConsole
    }
    $output = $lines -join "`n"
    if ($Show -and $output) { Write-JobsPushStatus $output }
    [pscustomobject]@{ Code = $code; Text = $output }
}
# 普通推送的并发更新既可能报非快进，也可能在服务端 CAS 时才报旧值不匹配。
function Test-JobsPushRemoteRace {
    param([string]$Text)
    return $Text -match '(?i)non-fast-forward|fetch first|stale info|remote ref updated since checkout|incorrect old value provided|is at .*but expected '
}
# 根据原生错误归类并给出下一步；未知错误保留失败，不猜测破坏性补救。
function Get-JobsPushFailure {
    param([string]$Text)
    $category = 'unknown'; $next = '查看日志中的首个 Git/remote 错误；保留现场，确认具体原因后重跑。'; $retry = $false
    if ($Text -match '(?i)GH013|GH006|protected branch|protected branch hook|branch protection|repository rule|pull request.*required') { $category='policy';$next='按平台要求创建 PR、完成必需检查或由管理员调整对应规则，再正常推送。' }
    elseif ($Text -match '(?i)secret scanning|push protection|detected secret|GH009') { $category='secret';$next='撤销泄漏凭据，并按平台给出的具体提交/路径清理秘密；历史重写需另行授权。' }
    elseif ($Text -match '(?i)quota|repository.*too large|repo size|storage limit|bandwidth.*limit') { $category='quota';$next='处理平台仓库/LFS 容量或带宽配额；本地改缓冲区不能解除配额。' }
    elseif ($Text -match '(?i)GH001|large files detected|file.*exceeds.*limit|maximum.*(file|pack).*size|pack exceeds|(?:HTTP(?:/[0-9.]+)?(?: error)?|error:)\s*413\b') { $category='size';$next='按服务端列出的对象定位大文件，使用平台认可的 LFS/产物存储；清理历史需另行授权。' }
    elseif ($Text -match '(?i)git-lfs|git lfs|LFS.*(missing|error|failed|object|batch)|lfs.*not found') { $category='lfs';$next='核对 Git LFS 安装、lfs env、对象完整性与 LFS 端点/授权，再重试；不跳过 LFS hook。' }
    elseif ($Text -match '(?i)permission denied \(publickey\)|authentication failed|could not read (Username|Password)|terminal prompts disabled|invalid (username|password)|(?:HTTP(?:/[0-9.]+)?(?: error)?|error:)\s*401\b') { $category='authentication';$next='修复选定主机的 SSH key/agent 或 HTTPS 凭据，确认 Sourcetree 与终端账户一致；不清空凭据库。' }
    elseif ($Text -match '(?i)repository not found|access denied|write access.*not granted|permission to .* denied|(?:HTTP(?:/[0-9.]+)?(?: error)?|error:)\s*(403|404)\b|not allowed to push|read.only (repository|remote)|repository.*read.only') { $category='permission';$next='核对完整推送地址、仓库存在性、账号写权限及组织 SSO/令牌 scope。404 也可能表示私仓无权限。' }
    elseif ($Text -match '(?i)host key verification|REMOTE HOST IDENTIFICATION|certificate.*(problem|failed|invalid)|SSL.*certificate|unable to get.*issuer') { $category='trust';$next='核对 SSH 主机指纹、系统时间和受信任证书；不关闭 TLS/SSH 校验。' }
    elseif (Test-JobsPushRemoteRace $Text) { $category='history';$next='重新取得所选推送端的目标分支，并保留双方历史整合后普通推送。' }
    elseif ($Text -match '(?i)cannot lock ref|unable to create.*lock|another git process|\.lock.*(exists|exist)|is at .*but expected') { $category='lock';$next='确认 Git/IDE 操作已结束，检查错误点名的精确锁/引用；用专用 Commit/Fetch 修复入口备份处理，不删除整棵 refs。' }
    elseif ($Text -match '(?i)CONFLICT|unmerged|not concluded.*merge|needs merge|rebase.*in progress') { $category='conflict';$next='在 Sourcetree 解决已列冲突并完成当前 merge/rebase，再重跑；本脚本保留冲突现场。' }
    elseif ($Text -match '(?i)would be overwritten by (merge|checkout)|untracked working tree files|local changes.*would be overwritten') { $category='working-tree';$next='本地文件与远端新增路径冲突；先备份并审查这些文件再正常整合，脚本不覆盖或删除。' }
    elseif ($Text -match '(?i)unrelated histories|shallow update not allowed|no merge base|shallow.*(root|history)') { $category='history-boundary';$next='确认是否选错仓库/分支；浅克隆可在另行确认后补全历史，不自动合并无关根。' }
    elseif ($Text -match '(?i)unable to auto-detect email|author identity unknown|committer identity unknown|empty ident|user\.email') { $category='identity';$next='为当前仓库设置真实 user.name / user.email 后重试；不伪造作者。' }
    elseif ($Text -match '(?i)gpg failed|failed to sign|signing key|gpg.*sign|ssh-keygen.*sign') { $category='signature';$next='修复当前签名工具、密钥或 agent；不自动禁用签名要求。' }
    elseif ($Text -match '(?i)pre-receive hook declined|hook declined|pre-push hook|hook.*failed|remote rejected') { $category='hook';$next='阅读本地/服务端 hook 的具体输出，修复规则要求后重跑；不使用 --no-verify。' }
    elseif ($Text -match '(?i)src refspec.*does not match|does not appear to be a git repository|bad refspec|invalid refspec') { $category='target';$next='核对本地是否已有提交、远端名称/地址及目标 refs/heads 分支映射。' }
    elseif ($Text -match '(?i)no space left|disk.*full|read-only file system|unable.*(write|unlink)|permission denied') { $category='filesystem';$next='检查错误路径的磁盘空间和当前用户权限；不批量 chmod/chown 或删除对象。' }
    elseif ($Text -match '(?i)bad object|corrupt|missing blob|missing tree|unable to read.*object|not a valid object') { $category='objects';$next='先备份仓库并用 git fsck 定位对象损坏，必要时从可信副本恢复；不删除对象库。' }
    elseif ($Text -match '(?i)could not resolve|connection.*(timed out|reset|refused)|operation timed out|network is unreachable|connection closed|broken pipe|early EOF|unexpected disconnect|(?:HTTP(?:/[0-9.]+)?(?: error)?|error:)\s*(408|429|5[0-9][0-9])\b|RPC failed|curl (18|28|35|52|55|56|92)') { $category='network';$next='检查当前主机 DNS、连接、服务状态及已配置代理；只做有限重试，不更改系统代理。';$retry=$true }
    [pscustomobject]@{ Category=$category; Next=$next; Retryable=$retry }
}
# 失败原因和后续操作始终与原生命令输出一起保留。
function Stop-JobsPushFailure {
    param([string]$Text)
    $failure = Get-JobsPushFailure $Text
    Write-JobsPushStatus $Text
    throw ('['+$failure.Category+'] '+$failure.Next)
}
# 读取可选配置并区分键缺失与配置解析失败。
function Get-JobsPushConfig {
    param([string]$Repository,[string]$Key,[switch]$Local)
    $arguments = @('config')
    if ($Local) { $arguments += '--local' }
    $result = Invoke-JobsPushGit $Repository ($arguments + @('--get-all',$Key))
    if ($result.Code -eq 1) { return @() }
    if ($result.Code -ne 0) { Stop-JobsPushFailure $result.Text }
    return @($result.Text -split "`n" | Where-Object { $_ -cne '' })
}
# 菜单只处理候选，不将用户路径拼进代码，也不默认选择多个远端之一。
function Select-JobsPushRemote {
    param([string[]]$Remotes)
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { throw '多个远端无法唯一确定；请传 -Remote，或在独立交互终端选择。' }
    $fzf = Get-Command fzf -CommandType Application -ErrorAction SilentlyContinue
    if (-not $fzf) { throw '多个远端需要 fzf；请准备 fzf，或使用 -Remote 显式指定，未安装任何依赖。' }
    & $fzf.Source --version | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'fzf 不可用，请修复选择器或显式指定 -Remote。' }
    $rows = @('取消本轮') + @($Remotes)
    $keys = @('FZF_DEFAULT_OPTS','FZF_DEFAULT_OPTS_FILE','FZF_DEFAULT_COMMAND','FZF_DEFAULT_COMMAND_FILE')
    $saved = @{}
    foreach ($key in $keys) { $saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$null,'Process') }
    try {
        $selection = @($rows | & $fzf.Source --no-multi --reverse --prompt '推送线路 > ' --header '回车选择；默认取消；Esc / Ctrl+C 取消')
        $selectCode = $LASTEXITCODE
    } finally {
        foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') }
    }
    if ($selectCode -in @(1,130) -or $selection.Count -eq 0 -or $selection[0] -ceq '取消本轮') { throw '已取消，没有执行修复或推送。' }
    if ($selectCode -ne 0 -or $selection.Count -ne 1 -or $selection[0] -cnotin $Remotes) { throw '远端选择器返回异常，已停止。' }
    return $selection[0]
}
# 定位 Git 的真实元数据路径，兼容子模块和 linked worktree。
function Get-JobsPushGitPath {
    param([string]$Repository,[string]$Name)
    $result = Invoke-JobsPushGit $Repository @('rev-parse','--git-path',$Name)
    if ($result.Code -ne 0) { Stop-JobsPushFailure $result.Text }
    if ([IO.Path]::IsPathRooted($result.Text)) { return [IO.Path]::GetFullPath($result.Text) }
    return [IO.Path]::GetFullPath((Join-Path $Repository $result.Text))
}
# 检查工作树和所有未完成事务，任何已有改动均保留。
function Assert-JobsPushWorktree {
    param([string]$Repository,[string]$LocalBranch,[string]$ExpectedHead)
    $branch = Invoke-JobsPushGit $Repository @('symbolic-ref','--quiet','--short','HEAD')
    $head = Invoke-JobsPushGit $Repository @('rev-parse','--verify','HEAD^{commit}')
    if ($branch.Code -ne 0 -or $head.Code -ne 0) { throw '[target] 当前为游离 HEAD 或尚无提交，请先在 Sourcetree 选择已有工作分支。' }
    if ($LocalBranch -and $branch.Text -cne $LocalBranch) { throw '当前分支已并发变化，已停止。' }
    if ($ExpectedHead -and $head.Text -cne $ExpectedHead) { throw 'HEAD 已被其它操作更改，已停止。' }
    foreach ($name in @('MERGE_HEAD','CHERRY_PICK_HEAD','REVERT_HEAD','rebase-merge','rebase-apply','sequencer','BISECT_LOG','index.lock','HEAD.lock','packed-refs.lock','shallow.lock','config.lock','FETCH_HEAD.lock',('refs/heads/'+$branch.Text+'.lock'))) {
        if (Test-Path -LiteralPath (Get-JobsPushGitPath $Repository $name)) { throw ('[lock/conflict] 未完成操作或锁：'+$name+'；请先完成原操作，不自动删除。') }
    }
    $flags = Invoke-JobsPushGit $Repository @('ls-files','-v','-z')
    if ($flags.Code -ne 0) { Stop-JobsPushFailure $flags.Text }
    foreach ($entry in $flags.Text.Split([char]0)) {
        if ($entry -cmatch '^[a-zS] ') { throw '[working-tree] 索引含 assume-unchanged/skip-worktree 标志，可能隐藏本地数据；请先审查这些路径或使用明确的 sparse 专用流程。' }
    }
    $state = Invoke-JobsPushGit $Repository @('status','--porcelain=v1','--untracked-files=all','--ignore-submodules=none')
    if ($state.Code -ne 0) { Stop-JobsPushFailure $state.Text }
    if ($state.Text) { Write-JobsPushStatus $state.Text;throw '[dirty] 工作区/暂存区/子模块存在改动。请先自行审查、提交或保存，再重跑；本入口不暂存、不 stash。' }
    [pscustomobject]@{ Branch=$branch.Text; Head=$head.Text }
}
# 按显式参数、推送配置及上游解析唯一线路和目标，不切换或创建本地分支。
function Resolve-JobsPushTarget {
    param([string]$Repository,[string]$LocalBranch,[string]$Remote,[string]$Branch)
    $remoteResult = Invoke-JobsPushGit $Repository @('remote')
    if ($remoteResult.Code -ne 0) { Stop-JobsPushFailure $remoteResult.Text }
    $remotes = @($remoteResult.Text -split "`n" | Where-Object { $_ })
    if ($remotes.Count -eq 0) { throw '[target] 尚未配置远端，请先在 Sourcetree 添加正确仓库地址。' }
    foreach ($name in $remotes) { if ($name -match '[\x00-\x20\x7f]' -or $name.StartsWith('-')) { throw '远端名称不安全，未执行网络命令。' } }
    $upstreamRemote = @(Get-JobsPushConfig $Repository ('branch.'+$LocalBranch+'.remote'))
    if (-not $Remote) {
        foreach ($key in @(('branch.'+$LocalBranch+'.pushRemote'),'remote.pushDefault')) {
            $configured = @(Get-JobsPushConfig $Repository $key)
            if ($configured.Count -gt 1) { throw '推送线路配置存在多个值，请用 -Remote 明确指定。' }
            if ($configured.Count -eq 1) { $Remote=$configured[0];break }
        }
        if (-not $Remote -and $upstreamRemote.Count -eq 1 -and $upstreamRemote[0] -cne '.') { $Remote=$upstreamRemote[0] }
        if (-not $Remote) {
            if ($remotes.Count -eq 1) { $Remote=$remotes[0] } else { $Remote=Select-JobsPushRemote $remotes }
        }
    }
    if ($Remote -cnotin $remotes) { throw '[target] 指定的推送远端不存在；没有改写远端配置。' }
    $mirror = @(Get-JobsPushConfig $Repository ('remote.'+$Remote+'.mirror'))
    if (@($mirror | Where-Object { $_ -match '^(?i:true|yes|on|1)$' }).Count) { throw '[target] 此 remote 配置为镜像推送，请使用专用镜像流程。' }
    foreach ($key in @('receivepack','uploadpack')) {
        if (@(Get-JobsPushConfig $Repository ('remote.'+$Remote+'.'+$key)).Count) { throw ('[target] 配置了自定义 '+$key+'；请先确认传输语义，通用修复不绕过它。') }
    }
    $fetch = Invoke-JobsPushGit $Repository @('remote','get-url','--all',$Remote)
    $push = Invoke-JobsPushGit $Repository @('remote','get-url','--push','--all',$Remote)
    if ($fetch.Code -ne 0 -or $push.Code -ne 0) { Stop-JobsPushFailure ($fetch.Text+"`n"+$push.Text) }
    $fetchUrls = @($fetch.Text -split "`n");$pushUrls = @($push.Text -split "`n")
    if ($fetchUrls.Count -ne 1 -or $pushUrls.Count -ne 1 -or -not $pushUrls[0]) { throw '[target] 一个 remote 有多个/空 URL，无法保证单线修复；请先拆分明确线路。' }
    $pushUrl = $pushUrls[0]
    if ($pushUrl -match '[\x00-\x1f\x7f]' -or $pushUrl.StartsWith('-')) { throw '[target] 推送地址含不安全字符。' }
    $expanded = Invoke-JobsPushGit $Repository @('ls-remote','--get-url','--',$pushUrl)
    if ($expanded.Code -ne 0 -or $expanded.Text -cne $pushUrl) { throw '[target] URL 重写再次变化，无法冻结同一端点；请检查 insteadOf/pushInsteadOf。' }
    $explicitBranch = -not [string]::IsNullOrWhiteSpace($Branch)
    if (-not $Branch) {
        $mapping = @(Get-JobsPushConfig $Repository ('remote.'+$Remote+'.jobsPushBranch') -Local)
        if ($mapping.Count -gt 1) { throw '本地 jobsPushBranch 有多个值，请明确 -Branch。' }
        if ($mapping.Count -eq 1) { $Branch=$mapping[0] }
    }
    if (-not $Branch) {
        $specs = @(Get-JobsPushConfig $Repository ('remote.'+$Remote+'.push'))
        if ($specs.Count) {
            if ($specs.Count -ne 1 -or $specs[0] -notmatch '^(?:HEAD|refs/heads/([^:]+)|([^:]+)):(?:refs/heads/)?([^:*]+)$') { throw '[target] push refspec 非唯一精确分支映射，请显式 -Branch；不执行 matching/通配/删除。' }
            $source = if ($Matches[1]) { $Matches[1] } elseif ($Matches[2]) { $Matches[2] } else { 'HEAD' }
            if ($source -cne 'HEAD' -and $source -cne $LocalBranch) { throw '[target] push refspec 源不是当前分支，请明确 -Branch。' }
            $Branch=$Matches[3]
        }
    }
    if (-not $Branch -and $upstreamRemote.Count -eq 1 -and $upstreamRemote[0] -ceq $Remote) {
        $upstream = @(Get-JobsPushConfig $Repository ('branch.'+$LocalBranch+'.merge'))
        if ($upstream.Count -gt 1) { throw '[target] 当前分支存在多个上游，请明确 -Branch。' }
        if ($upstream.Count -eq 1 -and $upstream[0].StartsWith('refs/heads/')) { $Branch=$upstream[0].Substring(11) }
    }
    if (-not $Branch) { $Branch=$LocalBranch }
    if ($Branch -match '[\x00-\x20\x7f]' -or $Branch.StartsWith('-') -or (Invoke-JobsPushGit $Repository @('check-ref-format',('refs/heads/'+$Branch))).Code -ne 0) { throw '[target] 目标分支不是合法的 refs/heads 名称。' }
    $snapshot = Invoke-JobsPushGit $Repository @('show-ref','--verify','--quiet','refs/heads/Gitee@snapshot')
    if ($LocalBranch -ceq 'Gitee@snapshot' -or ($LocalBranch -ceq 'byPods' -and $pushUrl -match '(?i)(?:@|//)gitee\.com[:/]') -or ($snapshot.Code -eq 0 -and $pushUrl -match '(?i)(?:@|//)gitee\.com[:/]')) { throw '[snapshot] OC 的 Gitee 独立快照必须使用专用发布流程，不合并完整 byPods 历史。' }
    [pscustomobject]@{ Remote=$Remote; Branch=$Branch; Url=$pushUrl; FetchUrl=$fetchUrls[0]; ExplicitBranch=$explicitBranch }
}
# 网络只做有限次重试，鉴权、规则、冲突等直接停止。
function Invoke-JobsPushRead {
    param([string]$Repository,[string[]]$Arguments)
    for ($attempt=1;$attempt -le 3;$attempt++) {
        $result = Invoke-JobsPushGit $Repository $Arguments
        if ($result.Code -eq 0) { return $result }
        $failure = Get-JobsPushFailure $result.Text
        Write-JobsPushStatus ('第 '+$attempt+'/3 次读取失败：'+$result.Text)
        if (-not $failure.Retryable -or $attempt -eq 3) { Stop-JobsPushFailure $result.Text }
        Start-Sleep -Seconds $attempt
    }
}
# 只读取精确分支，OID 与 ref 必须成对匹配，不能用其它 refs 冒充成功。
function Get-JobsPushRemoteHead {
    param([string]$Repository,[string]$Url,[string]$Branch)
    $ref = 'refs/heads/'+$Branch
    $result = Invoke-JobsPushRead $Repository @('ls-remote','--heads','--',$Url,$ref)
    if (-not $result.Text) { return '' }
    $lines = @($result.Text -split "`n")
    if ($lines.Count -ne 1 -or $lines[0] -notmatch '^([0-9a-f]{40}|[0-9a-f]{64})\s+(refs/heads/.+)$' -or $Matches[2] -cne $ref) { throw '[target] 服务端未返回唯一精确分支 OID。' }
    return $Matches[1]
}
# 合并前显式保护远端新增路径；ort 合并不能仅依靠 no-overwrite-ignore 保护忽略文件。
function Assert-JobsPushIncomingPaths {
    param([string]$Repository,[string]$RemoteRef)
    $base = Invoke-JobsPushGit $Repository @('merge-base','HEAD',$RemoteRef)
    if ($base.Code -ne 0) { Stop-JobsPushFailure $base.Text }
    $added = Invoke-JobsPushGit $Repository @('diff','--no-renames','--diff-filter=A','--name-only','-z',$base.Text,$RemoteRef,'--')
    if ($added.Code -ne 0) { Stop-JobsPushFailure $added.Text }
    foreach ($relative in $added.Text.Split([char]0)) {
        if (-not $relative) { continue }
        $parts = @($relative -split '/')
        $current = $Repository; $prefix = ''
        for ($i=0;$i -lt $parts.Count;$i++) {
            $current = Join-Path $current $parts[$i]
            $prefix = if ($prefix) { $prefix+'/'+$parts[$i] } else { $parts[$i] }
            try { $attributes = [IO.File]::GetAttributes($current) }
            catch [IO.FileNotFoundException] { continue }
            catch [IO.DirectoryNotFoundException] { continue }
            if ($i -lt $parts.Count-1 -and ($attributes -band [IO.FileAttributes]::Directory) -ne 0 -and ($attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { continue }
            $tracked = Invoke-JobsPushGit $Repository @('ls-files','--error-unmatch','-z','--',$prefix)
            if ($tracked.Code -eq 0 -and @($tracked.Text.Split([char]0)) -ccontains $prefix) { continue }
            throw ('[working-tree] 远端新增路径与本地未跟踪/忽略数据碰撞：'+$prefix+'；保留本地文件，先备份审查后再整合。')
        }
    }
}
# 从推送端取得快照，基于双方当前提交快进或合并；不重写已有提交。
function Merge-JobsPushTarget {
    param([string]$Repository,$Target,[string]$LocalBranch,[string]$ExpectedHead,[string]$TemporaryRef)
    $before = Assert-JobsPushWorktree $Repository $LocalBranch $ExpectedHead
    $remoteHead = Get-JobsPushRemoteHead $Repository $Target.Url $Target.Branch
    if (-not $remoteHead) {
        if (-not $Target.ExplicitBranch) { throw '[target] 目标分支尚不存在；请用 -Branch 明确授权首次发布，不自动新建未知分支。' }
        return $before.Head
    }
    Write-JobsPushStatus ('抓取来源：'+$Target.Remote+' | '+$Target.Url+' | refs/heads/'+$Target.Branch)
    [void](Invoke-JobsPushRead $Repository @('fetch','--no-tags','--no-write-fetch-head','--refmap=','--',$Target.Url,('refs/heads/'+$Target.Branch+':'+$TemporaryRef)))
    $fetched = Invoke-JobsPushGit $Repository @('rev-parse','--verify',($TemporaryRef+'^{commit}'))
    if ($fetched.Code -ne 0) { Stop-JobsPushFailure $fetched.Text }
    [void](Assert-JobsPushWorktree $Repository $LocalBranch $before.Head)
    if ((Invoke-JobsPushGit $Repository @('merge-base','--is-ancestor',$fetched.Text,$before.Head)).Code -eq 0) { return $before.Head }
    $base = Invoke-JobsPushGit $Repository @('merge-base',$before.Head,$fetched.Text)
    if ($base.Code -ne 0) {
        $shallow = Invoke-JobsPushGit $Repository @('rev-parse','--is-shallow-repository')
        if ($shallow.Text -ceq 'true') { throw '[history-boundary] 浅克隆缺少共同祖先；请审查后补全历史再重跑。' }
        throw '[history-boundary] 两端没有共同祖先，可能目标错误或独立快照；不自动拼接无关历史。'
    }
    $fastForward = (Invoke-JobsPushGit $Repository @('merge-base','--is-ancestor',$before.Head,$fetched.Text)).Code -eq 0
    if (-not $fastForward) {
        foreach ($ident in @('GIT_AUTHOR_IDENT','GIT_COMMITTER_IDENT')) {
            $identity = Invoke-JobsPushGit $Repository @('var',$ident)
            if ($identity.Code -ne 0) { Stop-JobsPushFailure $identity.Text }
        }
    }
    Assert-JobsPushIncomingPaths $Repository $TemporaryRef
    Write-JobsPushStatus ('历史整合：'+$(if ($fastForward) { '快进' } else { '保留双方提交的 merge' })+'；原 HEAD：'+$before.Head+'；远端：'+$fetched.Text)
    $merge = Invoke-JobsPushGit $Repository @('-c','merge.autostash=false','-c','rerere.enabled=false','-c','rerere.autoupdate=false','merge','--ff','--no-edit','--no-autostash','--no-overwrite-ignore',$TemporaryRef) -Show
    if ($merge.Code -ne 0) { Stop-JobsPushFailure $merge.Text }
    return (Assert-JobsPushWorktree $Repository $LocalBranch '').Head
}
# 仅刷新 fetch/push 同端点且映射可证明的标准跟踪引用；CAS 防止覆盖并发 fetch。
function Update-JobsPushTrackingRef {
    param([string]$Repository,$Target,[string]$ExpectedHead)
    if ($Target.Url -cne $Target.FetchUrl) { return }
    $trackingRef = 'refs/remotes/'+$Target.Remote+'/'+$Target.Branch
    if ((Invoke-JobsPushGit $Repository @('check-ref-format',$trackingRef)).Code -ne 0) { return }
    $matched = $false
    $specs = @(Get-JobsPushConfig $Repository ('remote.'+$Target.Remote+'.fetch'))
    foreach ($configured in $specs) {
        $spec = $configured.TrimStart('+')
        if ($spec.StartsWith('^')) { Write-JobsPushStatus '存在负向 fetch refspec，保留原跟踪引用，请按仓库配置获取。';return }
        if ($spec -ceq ('refs/heads/*:refs/remotes/'+$Target.Remote+'/*') -or $spec -ceq ('refs/heads/'+$Target.Branch+':'+$trackingRef)) { $matched=$true }
    }
    if (-not $matched) { return }
    $symbolic = Invoke-JobsPushGit $Repository @('symbolic-ref','--quiet',$trackingRef)
    if ($symbolic.Code -eq 0) { Write-JobsPushStatus ('跟踪引用为符号引用，保留原状：'+$trackingRef);return }
    if ($symbolic.Code -ne 1) { return }
    $old = Invoke-JobsPushGit $Repository @('rev-parse','--quiet','--verify',$trackingRef)
    if ($old.Code -notin @(0,1)) { return }
    $oldOid = if ($old.Code -eq 0) { $old.Text } else { '0' * $ExpectedHead.Length }
    if ($oldOid -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') { return }
    $updated = Invoke-JobsPushGit $Repository @('update-ref','-m','jobs push repair: verified remote tip',$trackingRef,$ExpectedHead,$oldOid)
    if ($updated.Code -eq 0) { Write-JobsPushStatus ('已刷新本次远端跟踪引用：'+$trackingRef) }
    else { Write-JobsPushStatus ('服务端 OID 已核验，但跟踪引用刷新失败，保留并发值/锁：'+$updated.Text+'；请正常 Fetch 或使用专用 Fetch 修复。') }
}
# 执行当前仓库的一条明确线路；只诊断模式不 fetch/merge/push 或写仓库元数据。
function Repair-JobsPush {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Repository,[string]$Remote,[string]$Branch,[switch]$Diagnose,[string]$LogFile)
    $script:PushLog = $LogFile
    $savedPrompt = [Environment]::GetEnvironmentVariable('GIT_TERMINAL_PROMPT','Process')
    $guard = $null; $guardPath = ''; $temporaryRef = ''; $root = ''
    try {
        $env:GIT_TERMINAL_PROMPT = '0'
        $bare = Invoke-JobsPushGit $Repository @('rev-parse','--is-bare-repository')
        if ($bare.Code -ne 0) { Stop-JobsPushFailure $bare.Text }
        if ($bare.Text -ceq 'true') { throw '[target] bare 仓库没有当前工作分支，请使用专用发布流程。' }
        $rootResult = Invoke-JobsPushGit $Repository @('rev-parse','--show-toplevel')
        if ($rootResult.Code -ne 0) { Stop-JobsPushFailure $rootResult.Text }
        $root = $rootResult.Text
        $initial = Assert-JobsPushWorktree $root '' ''
        $target = Resolve-JobsPushTarget $root $initial.Branch $Remote $Branch
        Write-JobsPushStatus ('当前仓库：'+$root+'；本地分支：'+$initial.Branch+'；HEAD：'+$initial.Head)
        Write-JobsPushStatus ('推送目标：'+$target.Remote+' | '+$target.Url+' | refs/heads/'+$target.Branch)
        if ($target.Url -cne $target.FetchUrl) { Write-JobsPushStatus ('获取地址：'+$target.FetchUrl+'；与推送地址不同，本次只从推送端读取并整合历史。') }
        if ($Diagnose) {
            $remoteHead = Get-JobsPushRemoteHead $root $target.Url $target.Branch
            Write-JobsPushStatus ('只诊断：远端提交='+$remoteHead+'；未 fetch/merge/push，未修改工作区、索引、分支或配置。')
            return [pscustomobject]@{ Head=$initial.Head; RemoteHead=$remoteHead; Diagnosed=$true }
        }
        $guardPath = Get-JobsPushGitPath $root 'jobs-push-repair.lock'
        $guard = [IO.File]::Open($guardPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $journalDirectory = Get-JobsPushGitPath $root 'jobs-push-repair'
        [void][IO.Directory]::CreateDirectory($journalDirectory)
        $operation = (Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N')
        $journal = Join-Path $journalDirectory ($operation+'.txt')
        $temporaryRef = 'refs/jobs-push-repair/'+$operation+'/target'
        @(('branch='+$initial.Branch),('before='+$initial.Head),('remote='+$target.Remote),('destination=refs/heads/'+$target.Branch)) | Set-Content -LiteralPath $journal -Encoding UTF8
        Write-JobsPushStatus ('恢复记录：'+$journal+'；原提交同时保留在正常分支 reflog，不新建本地备份分支。')
        $expected = $initial.Head
        for ($attempt=1;$attempt -le 3;$attempt++) {
            $expected = Merge-JobsPushTarget $root $target $initial.Branch $expected $temporaryRef
            [void](Assert-JobsPushWorktree $root $initial.Branch $expected)
            Add-Content -LiteralPath $journal -Value ('planned='+$expected) -Encoding UTF8
            Write-JobsPushStatus ('普通推送 '+$attempt+'/3：'+$expected+' → '+$target.Url+' refs/heads/'+$target.Branch)
            $push = Invoke-JobsPushGit $root @('-c','push.followTags=false','push','--porcelain','--no-follow-tags','--recurse-submodules=no','--',$target.Url,($expected+':refs/heads/'+$target.Branch)) -Show
            # 即使 push 传输失败，先读回服务端：可能服务端已接受但确认包丢失。
            $remoteHead = Get-JobsPushRemoteHead $root $target.Url $target.Branch
            if ($remoteHead -ceq $expected) {
                [void](Assert-JobsPushWorktree $root $initial.Branch $expected)
                Add-Content -LiteralPath $journal -Value ('verified='+$remoteHead) -Encoding UTF8
                Update-JobsPushTrackingRef $root $target $expected
                Write-JobsPushStatus ('已核验本地与指定远端 OID 完全一致：'+$expected)
                return [pscustomobject]@{ Head=$expected; RemoteHead=$remoteHead; Diagnosed=$false }
            }
            if ($push.Code -eq 0) { throw '[verification] push 返回成功，但服务端提交已变化/不匹配；保留现场，请重跑检查。' }
            $failure = Get-JobsPushFailure $push.Text
            if ($attempt -eq 3 -or (-not $failure.Retryable -and $failure.Category -cne 'history')) { Stop-JobsPushFailure $push.Text }
            Write-JobsPushStatus ('远端尚未接受计划提交：'+$failure.Category+'；重新抓取并检查，不强推。')
            Start-Sleep -Seconds $attempt
            # 下一轮重新抓取同一引用前清掉本轮临时 ref，避免远端重写导致本地 ref 快进拒绝。
            $existing = Invoke-JobsPushGit $root @('rev-parse','--verify',$temporaryRef)
            if ($existing.Code -eq 0) { [void](Invoke-JobsPushGit $root @('update-ref','-d',$temporaryRef,$existing.Text)) }
        }
    } finally {
        if ($temporaryRef -and $root) {
            $existing = Invoke-JobsPushGit $root @('rev-parse','--verify',$temporaryRef)
            if ($existing.Code -eq 0) { [void](Invoke-JobsPushGit $root @('update-ref','-d',$temporaryRef,$existing.Text)) }
        }
        if ($guard) { $guard.Dispose();[IO.File]::Delete($guardPath) }
        [Environment]::SetEnvironmentVariable('GIT_TERMINAL_PROMPT',$savedPrompt,'Process')
        $script:PushLog = ''
    }
}
Export-ModuleMember -Function Repair-JobsPush,Get-JobsPushFailure
