# 本地提取原生Dart边界；真实PE校验，进程返回替身；禁止SDK/Flutter/curl调用。

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
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('JobsExtractorNative-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$script:checks=0
function Assert-Native([bool]$Value,[string]$Text){$script:checks++;if(-not$Value){throw $Text}}
try{
    $scripts=Join-Path $temporary 'package';[void][IO.Directory]::CreateDirectory($scripts)
    $source=Join-Path $root 'Scripts/Features/JobsFlutterDependencyExtractor/Scripts'
    foreach($name in @('Common.psm1','Action.psm1')){Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $scripts $name)}
    # All newly introduced network gateways are hard failures; no real transport can escape old mocks.
    [void][IO.Directory]::CreateDirectory((Join-Path $scripts 'SdkDownloadOutput.ps1'))
    [IO.File]::WriteAllText((Join-Path $scripts 'SdkDownloadOutput.ps1/SdkDownloadOutput.ps1'),@'
function Import-JobsSdkDownloadRoute { throw 'fixture SDK/network forbidden' }
function Invoke-JobsSdkRoutedCommand { throw 'fixture SDK/network forbidden' }
'@,(New-Object Text.UTF8Encoding($true)))
    $project=Join-Path $temporary 'project';$sdk=Join-Path $project '.fvm/flutter_sdk'
    $dart=Join-Path $sdk 'bin/cache/dart-sdk/bin/dart.exe';[void][IO.Directory]::CreateDirectory((Split-Path -Parent $dart))
    $pe=New-Object byte[] 96;$pe[0]=77;$pe[1]=90;$pe[60]=64;$pe[64]=80;$pe[65]=69;$pe[68]=100;$pe[69]=134
    [IO.File]::WriteAllBytes($dart,$pe)
    [IO.File]::WriteAllText((Join-Path $sdk 'bin/flutter.bat'),'fixture Flutter forbidden')
    [IO.File]::WriteAllText((Join-Path $project '.fvmrc'),'{"flutter":"3.38.4"}')
    $action=Import-Module (Join-Path $scripts 'Action.psm1') -Force -PassThru -DisableNameChecking
    $common=Get-Module -All|Where-Object{$_.Path-eq(Join-Path $scripts 'Common.psm1')}|Select-Object -First 1
    &$common{
        $script:nativeCalls=New-Object 'Collections.Generic.List[object]';$script:nativeExit=0
        function script:Invoke-JobsProcessOnce {
            param($FilePath,$Arguments,$WorkingDirectory,$TimeoutSeconds)
            if([IO.Path]::GetFileName($FilePath)-ine'dart.exe'){throw 'fixture Flutter/curl/tool invocation forbidden'}
            $script:nativeCalls.Add([pscustomobject]@{File=$FilePath;Arguments=$Arguments;Directory=$WorkingDirectory;Timeout=$TimeoutSeconds})
            return [pscustomobject]@{ExitCode=$script:nativeExit;StdOut=$(if($Arguments[0]-ceq'--version'){'Dart SDK version: 3.10.3 (stable)'}else{'local extraction finished'});StdErr='native fixture stderr'}
        }
    }
    Assert-Native (&$action{param($d)Test-JobsExtractorNativeExecutable $d}$dart) 'native-only入口先真实校验PE机器签名'
    Assert-Native (-not[IO.File]::Exists((Join-Path $sdk 'bin/cache/engine-dart-sdk.stamp'))) '夹具必须缺Flutter stamp，不能靠健康SDK绕过问题'
    $found=&$action{param($p)Find-JobsExtractorDart $p}$project
    Assert-Native ($found-ceq$dart) '原生--version健康检查离线完成，不启动Flutter补stamp'
    $argv=@('本地 提取引擎.dart','--project',$project,'--destination','路径 & ! %')
    $result=&$action{param($d,$a,$p)Invoke-JobsExtractorNativeDart $d $a $p 21600}$dart $argv $project
    Assert-Native ($result.ExitCode-eq0-and$result.StdOut-ceq'local extraction finished'-and$result.StdErr-ceq'native fixture stderr') '本地提取保留退出码及stdout/stderr'
    $calls=@(&$common{$script:nativeCalls.ToArray()})
    Assert-Native ($calls.Count-eq2-and$calls[0].Arguments[0]-ceq'--version') '只执行原生健康检查和本地提取，不执行其它工具'
    Assert-Native (($calls[1].Arguments-join'|')-ceq($argv-join'|')-and$calls[1].Directory-ceq$project-and$calls[1].Timeout-eq21600) '沿用原进程argv、工作目录和超时契约'
    Assert-Native (-not[IO.File]::Exists((Join-Path $sdk 'bin/cache/engine-dart-sdk.stamp'))) '成功提取不生成Flutter stamp或下载SDK'
    &$common{$script:nativeExit=130}
    $cancelled=$false
    try{[void](&$action{param($p)Find-JobsExtractorDart $p}$project)}catch [OperationCanceledException]{$cancelled=$true}
    Assert-Native $cancelled '原生130作为取消穿透候选健康检查catch'
    Assert-Native ((&$common{$script:nativeCalls.Count})-eq3) '取消不重试、不继续其它候选或提取业务'
    foreach($name in @('flutter.exe','fvm.exe')){
        $tool=Join-Path $temporary $name;[IO.File]::WriteAllBytes($tool,$pe);$rejected=$false
        try{[void](&$common{param($d,$p)Invoke-JobsProcess $d @('--version') $p 1 -ExtractorNativeDartOnly}$tool $project)}catch{$rejected=$true}
        Assert-Native $rejected ('native-only不能绕过真实SDK工具：'+$name)
    }
    $bad=Join-Path $temporary 'bad/dart.exe';[void][IO.Directory]::CreateDirectory((Split-Path -Parent $bad));[IO.File]::WriteAllText($bad,'not a native PE')
    $rejected=$false
    try{[void](&$action{param($d,$p)Invoke-JobsExtractorNativeDart $d @('--version') $p 1}$bad $project)}catch{$rejected=$true}
    Assert-Native $rejected '伪装dart.exe不能进入native-only执行器'
    # Without the action-owned context the generic Dart route remains active.
    $routed=$false
    try{[void](&$common{param($d,$p)Invoke-JobsProcess $d @('--version') $p 1}$dart $project)}catch{$routed=$_.Exception.Message.Contains('SDK/network forbidden')}
    Assert-Native $routed '普通Dart调用仍进入SDK路由，豁免仅限显式提取上下文'
    Assert-Native ((&$common{$script:nativeCalls.Count})-eq3) '拒绝路径不调用原生进程'
    Write-JobsUrlText ('PASS: ExtractorNativeOnly.Tests.ps1 ('+$script:checks+' assertions; real PE validation, process mocked, no SDK/network)')
}finally{
    Get-Module -All|Where-Object{$_.Path-and$_.Path.StartsWith($temporary)}|Remove-Module -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
