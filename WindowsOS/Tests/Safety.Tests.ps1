#requires -Version 5.1
# 检查 SourceTree 参数入口、危险确认与错误传播；仅写本次临时目录。
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('JobsSourceTreeSafety-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$script:count=0
# 为每项安全门禁保留清楚的失败说明。
function Assert-Check($Condition,[string]$Label){if(!$Condition){throw $Label};$script:count++}
# 危险取消及命令失败都必须传播。
function Assert-Throws([scriptblock]$Body,[string]$Label){$failed=$false;try{& $Body}catch{$failed=$true};Assert-Check $failed $Label}
try{
    $module=Import-Module (Join-Path $root 'Scripts/SourceTree.psm1') -Force -DisableNameChecking -PassThru
    & $module {
        param($f)
        $script:LogFile=Join-Path $f 'fixture.log'
        $script:answer=''
        function script:Read-Host {param($Prompt) $script:answer}
        foreach($value in @('','yes','Yes',' YES','YES ')){$script:answer=$value;Assert-Throws {Confirm-JobsDanger 'fixture'} '精确 YES 以外取消'}
        $script:answer='YES';Confirm-JobsDanger 'fixture';Assert-Check $true '精确 YES 放行'
        $safe=Protect-JobsText 'https://user:secret@example.invalid/repo.git?token=private#fragment'
        Assert-Check ($safe -notmatch 'user|secret|token|private|fragment') '来源隐藏凭据与查询内容'
        Assert-Throws {Invoke-JobsTool 'jobs-source-tree-missing-command' @() $f} '缺少工具停止'
        $hostPath=(Get-Process -Id $PID).Path
        $answer=Invoke-JobsTool $hostPath @('-NoLogo','-NoProfile','-Command','[Console]::Error.WriteLine("fixture stderr"); exit 0') $f -Quiet
        Assert-Check ($answer.Code -eq 0 -and $answer.Text -match 'fixture stderr') 'stderr 成功命令不误报失败'
        Assert-Throws {Invoke-JobsTool $hostPath @('-NoLogo','-NoProfile','-Command','exit 7') $f -Quiet} '非零退出停止'
    } $fixture
    $wrappers=@(Get-ChildItem -LiteralPath $root -Directory|ForEach-Object{Get-ChildItem -LiteralPath $_.FullName -File -Filter '*.cmd'})
    Assert-Check ($wrappers.Count -eq 27) '完整 SourceTree 动作集'
    foreach($wrapper in $wrappers){
        $text=[IO.File]::ReadAllText($wrapper.FullName)
        Assert-Check ($text -match '"%~dp0Run\.ps1" %\*') ('保留脚本相对路径与参数 '+$wrapper.Name)
        Assert-Check ($text -match '(?m)^if "%~1"=="" if not "%JOBS_EXIT%"=="0" pause\r?$') ('有参失败不等待输入 '+$wrapper.Name)
        Assert-Check ($text -match '(?m)^exit /b %JOBS_EXIT%\r?$') ('保留退出码 '+$wrapper.Name)
    }
    if([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT){
        # 真实 CMD 只执行本次假命令，不运行 PowerShell 业务入口。
        $mock=Join-Path $fixture 'fake.cmd';[IO.File]::WriteAllText($mock,"@echo off`r`nexit /b 7`r`n",[Text.Encoding]::ASCII)
        $testCmd=Join-Path $fixture 'entry.cmd'
        $text=[IO.File]::ReadAllText($wrappers[0].FullName)
        $text=[regex]::Replace($text,'(?m)^powershell\.exe[^\r\n]*','call "%~dp0fake.cmd" %*')
        [IO.File]::WriteAllText($testCmd,$text,[Text.Encoding]::ASCII)
        $info=New-Object Diagnostics.ProcessStartInfo
        $info.FileName=$env:ComSpec;$info.Arguments='/d /s /c ""'+$testCmd+'" -SourceTree -Target "fixture path""'
        $info.UseShellExecute=$false;$info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $process=New-Object Diagnostics.Process;$process.StartInfo=$info
        try{
            [void]$process.Start();$finished=$process.WaitForExit(5000)
            if(!$finished){$process.Kill();throw 'CMD 失败后等待了输入'}
            Assert-Check ($process.ExitCode -eq 7) '真实 CMD 有参失败及时返回原退出码'
        }finally{$process.Dispose()}
    }else{Write-Host 'SKIP：CMD 原生运行仅在 Windows 执行；本机已检查全部 27 个转发入口。'}
    Write-Host "PASS：$script:count 项断言。"
}finally{Remove-Item -LiteralPath $fixture -Recurse -Force}
