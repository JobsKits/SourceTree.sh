# Install-Menu.ps1 | Jobs Windows Sourcetree 菜单安装与恢复
# Created by Jobs on 2026年10月23日，星期五.
[CmdletBinding()]
param([ValidateSet('Install','Restore','Preview')][string]$Mode='Install', [string]$ConfigPath)
$ErrorActionPreference='Stop'
# 对精确配置文件计算摘要，恢复时保护后续修改。
function Get-JobsMenuHash {
    param([string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return ''}
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
# 按稳定脚本路径合并，保留用户自定义标题与未知动作。
function Merge-JobsWindowsMenu {
    param([string]$Existing,[string]$Root)
    $doc=New-Object Xml.XmlDocument
    $doc.PreserveWhitespace=$true
    $doc.XmlResolver=$null
    if($Existing){$doc.LoadXml($Existing)}else{$doc.LoadXml('<?xml version="1.0" encoding="utf-8"?><ArrayOfCustomAction xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>')}
    if($doc.DocumentElement.Name -ne 'ArrayOfCustomAction' -or $doc.DocumentType){throw '菜单XML结构不匹配，保留原文件。'}
    $actions=@(Get-Content -LiteralPath (Join-Path $Root 'actions.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
    foreach($action in $actions){
        $scriptPath=[IO.Path]::GetFullPath((Join-Path $Root $action.Script))
        if(-not(Test-Path -LiteralPath $scriptPath -PathType Leaf)){throw "动作缺失：$scriptPath"}
        $leaf=($action.Script -split '/')[0]
        $matches=@($doc.SelectNodes('/ArrayOfCustomAction/CustomAction') | Where-Object { $_.Parameters -and $_.Parameters.Replace('/','\').Contains('\'+$leaf+'\Run.ps1') })
        if($matches.Count -gt 1){throw "动作重复：$leaf"}
        $item=$null
        if($matches.Count){$item=$matches[0]}else{$item=$doc.CreateElement('CustomAction');[void]$doc.DocumentElement.AppendChild($item)}
        $fields=[ordered]@{Caption=$action.Name;Target=(Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe');Parameters=('-NoProfile -ExecutionPolicy Bypass -File "'+$scriptPath+'" -SourceTree -Target "$REPO"');OpenInSeparateWindow='false';ShowFullOutput='true';IsSilent='false'}
        foreach($key in $fields.Keys){
            $child=$item.SelectSingleNode($key)
            if($null -eq $child){$child=$doc.CreateElement($key);[void]$item.AppendChild($child)}
            elseif($key -eq 'Caption'){continue}
            $child.InnerText=$fields[$key]
        }
    }
    $doc.OuterXml
}
# 先预览再精确写入，备份与安装摘要供冲突检测恢复。
function Invoke-JobsMenu {
    Write-Host 'Jobs | 安装 Windows Sourcetree 菜单'
    Write-Host '影响：仅当前用户 customactions.xml；保留已有标题与未知动作，写前备份。'
    Write-Host '恢复：本脚本 -Mode Restore；若安装后配置有变化会停止，避免覆盖。Ctrl+C 取消。'
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw '此入口只支持 Windows。'}
    if([Console]::IsInputRedirected){throw '需要交互终端确认。'}
    [void](Read-Host '按回车继续')
    if(-not $ConfigPath){$script:ConfigPath=Join-Path $env:LOCALAPPDATA 'Atlassian/SourceTree/customactions.xml'}
    $config=[IO.Path]::GetFullPath($ConfigPath)
    $statePath=$config+'.jobs-state.json'
    if(@(Get-Process -Name SourceTree -ErrorAction SilentlyContinue).Count){throw '请保存任务并关闭 Sourcetree 后重试；不会强制结束进程。'}
    if($Mode -eq 'Restore'){
        if(-not(Test-Path -LiteralPath $statePath)){throw '没有本安装器的恢复记录。'}
        $state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json
        if((Get-JobsMenuHash $config) -cne $state.InstalledHash){throw '配置在安装后变化，停止恢复；请人工合并备份。'}
        if((Read-Host '输入 YES 恢复本轮安装前状态') -cne 'YES'){throw '已取消。'}
        if($state.Existed){Copy-Item -LiteralPath $state.Backup -Destination $config -Force}else{Remove-Item -LiteralPath $config}
        Remove-Item -LiteralPath $statePath
        Write-Host '已恢复。';return
    }
    $existing=''
    $beforeHash=Get-JobsMenuHash $config
    if($beforeHash){$existing=[IO.File]::ReadAllText($config)}
    $merged=Merge-JobsWindowsMenu $existing $PSScriptRoot
    if($Mode -eq 'Preview'){Write-Output $merged;return}
    Write-Host ('将登记 '+@(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'actions.json') -Raw -Encoding UTF8|ConvertFrom-Json).Count+' 个动作；目标：'+$config)
    if((Read-Host '输入 YES 写入菜单；其它取消') -cne 'YES'){throw '已取消。'}
    if((Get-JobsMenuHash $config) -cne $beforeHash){throw '配置并发变化，停止。'}
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $config))
    $backup=$config+'.bak.'+(Get-Date -Format 'yyyyMMddHHmmss')+'.'+[guid]::NewGuid().ToString('N')
    if($beforeHash){Copy-Item -LiteralPath $config -Destination $backup}
    $temporary=$config+'.tmp.'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temporary,$merged,(New-Object Text.UTF8Encoding($true)))
    Move-Item -LiteralPath $temporary -Destination $config -Force
    [ordered]@{Existed=[bool]$beforeHash;Backup=$backup;InstalledHash=(Get-JobsMenuHash $config)}|ConvertTo-Json|Set-Content -LiteralPath $statePath -Encoding UTF8
    Write-Host '菜单已写入；重新打开 Sourcetree 加载。Windows 实机界面仍需验收。'
}
try{Invoke-JobsMenu}catch{Write-Error $_ -ErrorAction Continue;exit 1}
