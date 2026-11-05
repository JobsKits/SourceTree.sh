# 本地提取原生Dart边界；真实PE校验，进程返回替身；禁止SDK/Flutter/curl调用。
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
    [IO.File]::WriteAllText((Join-Path $scripts 'SdkDownloadOutput.ps1'),@'
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
    Write-Host ('PASS: ExtractorNativeOnly.Tests.ps1 ('+$script:checks+' assertions; real PE validation, process mocked, no SDK/network)')
}finally{
    Get-Module -All|Where-Object{$_.Path-and$_.Path.StartsWith($temporary)}|Remove-Module -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
