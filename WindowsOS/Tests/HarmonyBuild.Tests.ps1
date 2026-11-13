# HarmonyBuild.Tests.ps1 | Jobs 鸿蒙双产物隔离验证
# Created by Jobs on 2026年10月28日，星期三.
[CmdletBinding()]
param()
# BEGIN JOBS_TERMINAL_STYLE_V1 - session-only colors; no profile or registry changes.
function New-JobsTerminalStyleState {
    if ($PSVersionTable.PSVersion.Major -lt 5) { return @{ JobsTerminalPlainFallback = $true; Before = @{} } }
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $Host.Name -ne 'ConsoleHost') { return $null }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or [Console]::IsErrorRedirected) { return $null }
    if ((Test-Path Env:NO_COLOR) -or $env:TERM -ieq 'dumb' -or $env:PLAIN_OUTPUT -eq '1') { return $null }
    foreach ($key in [Environment]::GetEnvironmentVariables().Keys) {
        if ([string]$key -match '^(?i:SOURCE_?TREE)') { return $null }
    }
    if (-not ('Jobs.TerminalStyleV1.Native' -as [type])) {
        try {
        Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
namespace Jobs.TerminalStyleV1 {
    public static class Native {
        [StructLayout(LayoutKind.Explicit, Size=20, CharSet=CharSet.Unicode)]
        public struct InputRecord {
            [FieldOffset(0)] public ushort Kind;
            [FieldOffset(4)] public int Down;
            [FieldOffset(8)] public ushort Repeat;
            [FieldOffset(10)] public ushort Key;
            [FieldOffset(12)] public ushort Scan;
            [FieldOffset(14)] public char Character;
            [FieldOffset(16)] public uint Modifiers;
        }
        [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
        [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
        [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out uint mode);
        [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, uint mode);
        [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint milliseconds);
        [DllImport("kernel32.dll")] static extern bool GetNumberOfConsoleInputEvents(IntPtr h, out uint count);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool ReadConsoleInputW(IntPtr h, [Out] InputRecord[] records, uint count, out uint read);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, ExactSpelling=true)] static extern bool WriteConsoleInputW(IntPtr h, InputRecord[] records, uint count, out uint written);
        const string OwnerName = "JOBS_TERMINAL_STYLE_WINDOWS_OWNER";
        static readonly string[] Keys = { "10", "11", "4;0", "4;1", "4;2", "4;3", "4;4", "4;5", "4;6", "4;7", "4;8", "4;9", "4;10", "4;11", "4;12", "4;13", "4;14", "4;15" };
        static readonly string[] Hex = { "000000", "ff5f56", "5fd787", "ffd75f", "5fafff", "d787ff", "5fd7ff", "eeeeee", "9e9e9e", "ff8787", "87ffaf", "ffff87", "87bfff", "ffafff", "afffff", "ffffff" };
        static readonly Regex Reply = new Regex("\\x1b\\](?<key>10|11|4;[0-9]{1,2});(?<rgb>rgb:[0-9a-f]{1,4}/[0-9a-f]{1,4}/[0-9a-f]{1,4})(?:\\x07|\\x1b\\\\)", RegexOptions.IgnoreCase);
        public sealed class State {
            public IntPtr Input, Output;
            public uint OutputMode;
            public ConsoleColor Foreground, Background;
            public Dictionary<string,string> Original, Applied;
            public string Owner, PreviousOwner, Recovery;
            public bool Active, ModeChanged, Fallback;
            public Dictionary<string,string> EnvironmentBefore = new Dictionary<string,string>();
        }
        static string Escape(string key, string value) { return "\x1b]" + key + ";" + value + "\x07"; }
        static string Rgb(string hex) { return "rgb:" + hex.Substring(0,2) + "/" + hex.Substring(2,2) + "/" + hex.Substring(4,2); }
        static string Normal(string rgb) {
            string[] parts = rgb.Substring(4).Split('/');
            for (int n=0; n<3; n++) {
                int maximum = (1 << (4 * parts[n].Length)) - 1;
                int value = Convert.ToInt32(parts[n],16);
                parts[n] = ((value * 65535L + maximum/2) / maximum).ToString("x4");
            }
            return String.Join("/",parts);
        }
        // Preserve unrelated key/window records instead of consuming user input during color queries.
        static Dictionary<string,string> Query(State state) {
            uint pending;
            if (!GetNumberOfConsoleInputEvents(state.Input,out pending) || pending != 0) { return null; }
            StringBuilder commands = new StringBuilder();
            foreach (string key in Keys) { commands.Append(Escape(key,"?")); }
            Console.Write(commands.ToString());
            List<InputRecord> records = new List<InputRecord>();
            List<int> characterIndices = new List<int>();
            StringBuilder text = new StringBuilder();
            Dictionary<string,string> result = new Dictionary<string,string>();
            Stopwatch timer = Stopwatch.StartNew();
            try {
                while (timer.ElapsedMilliseconds < 600) {
                    if (result.Count == Keys.Length && GetNumberOfConsoleInputEvents(state.Input,out pending) && pending == 0) { break; }
                    if (WaitForSingleObject(state.Input,20) != 0) { continue; }
                    InputRecord[] item = new InputRecord[1]; uint read;
                    if (!ReadConsoleInputW(state.Input,item,1,out read) || read != 1) { break; }
                    int index = -1;
                    if (item[0].Kind == 1 && item[0].Character != '\0') {
                        if (item[0].Down != 0) { index = text.Length; text.Append(item[0].Character); }
                        else if (text.Length != 0 && text[text.Length-1] == item[0].Character) { index = text.Length-1; }
                    }
                    records.Add(item[0]); characterIndices.Add(index);
                    foreach (Match match in Reply.Matches(text.ToString())) {
                        string key = match.Groups["key"].Value;
                        if (Array.IndexOf(Keys,key) >= 0) { result[key] = match.Groups["rgb"].Value; }
                    }
                }
            } finally {
                bool[] used = new bool[text.Length];
                foreach (Match match in Reply.Matches(text.ToString())) {
                    for (int n=match.Index; n<match.Index+match.Length; n++) { used[n] = true; }
                }
                List<InputRecord> replay = new List<InputRecord>();
                for (int n=0; n<records.Count; n++) {
                    int index = characterIndices[n];
                    if (index < 0 || !used[index]) { replay.Add(records[n]); }
                }
                if (replay.Count != 0) {
                    uint written;
                    if (!WriteConsoleInputW(state.Input,replay.ToArray(),(uint)replay.Count,out written) || written != replay.Count) {
                        Console.Error.WriteLine("[Jobs] Could not replay terminal input; color protection is unavailable.");
                        result.Clear();
                    }
                }
            }
            return result.Count == Keys.Length ? result : null;
        }
        static void Plain(State state) {
            foreach (string key in new string[] { "NO_COLOR", "PLAIN_OUTPUT", "FORCE_COLOR", "CLICOLOR", "ANSI_COLORS_DISABLED" }) {
                state.EnvironmentBefore[key] = Environment.GetEnvironmentVariable(key);
                Environment.SetEnvironmentVariable(key, key == "FORCE_COLOR" || key == "CLICOLOR" ? "0" : "1");
            }
            state.Fallback = true;
        }
        public static void Enter(State state) {
            try {
                state.Input = GetStdHandle(-10); state.Output = GetStdHandle(-11);
                uint inputMode;
                if (!GetConsoleMode(state.Input,out inputMode) || !GetConsoleMode(state.Output,out state.OutputMode)) { Plain(state); return; }
                IntPtr window = GetConsoleWindow();
                if (window == IntPtr.Zero) { Plain(state); return; }
                string identity = window.ToInt64().ToString("x");
                state.PreviousOwner = Environment.GetEnvironmentVariable(OwnerName);
                if (!String.IsNullOrEmpty(state.PreviousOwner)) {
                    string[] owner = state.PreviousOwner.Split(':');
                    int pid; long started;
                    if (owner.Length == 3 && owner[0] == identity && Int32.TryParse(owner[1],out pid) && Int64.TryParse(owner[2],out started)) {
                        try { if (Process.GetProcessById(pid).StartTime.ToUniversalTime().Ticks == started) { return; } } catch {}
                    }
                }
                state.Foreground = Console.ForegroundColor; state.Background = Console.BackgroundColor;
                if ((state.OutputMode & 4) == 0) {
                    if (!SetConsoleMode(state.Output,state.OutputMode | 4)) { Plain(state); return; }
                    state.ModeChanged = true;
                }
                state.Original = Query(state);
                if (state.Original == null) { Restore(state); Plain(state); return; }
                state.Applied = new Dictionary<string,string>();
                state.Applied["10"] = "rgb:ff/ff/ff"; state.Applied["11"] = "rgb:00/00/00";
                for (int n=0; n<16; n++) { state.Applied["4;"+n] = Rgb(Hex[n]); }
                StringBuilder restore = new StringBuilder();
                foreach (string key in Keys) { restore.Append(Escape(key,state.Original[key])); }
                string encoded = Convert.ToBase64String(Encoding.UTF8.GetBytes(restore.ToString()));
                state.Recovery = Path.Combine(Path.GetTempPath(),"JobsTerminalStyle-"+Process.GetCurrentProcess().Id+"-"+Guid.NewGuid().ToString("N")+".ps1");
                string manual = "# Restore only the session colors saved by this Jobs script.\r\n"+
                    "if ([Console]::IsOutputRedirected) { throw 'Run in the original console.' }\r\n"+
                    "Add-Type -Namespace Jobs -Name RecoveryConsole -MemberDefinition '[System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern System.IntPtr GetStdHandle(int n); [System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern bool GetConsoleMode(System.IntPtr h, out uint m); [System.Runtime.InteropServices.DllImport(\"kernel32.dll\")] public static extern bool SetConsoleMode(System.IntPtr h, uint m);'\r\n"+
                    "$h = [Jobs.RecoveryConsole]::GetStdHandle(-11); [uint32]$m = 0\r\n"+
                    "if (-not [Jobs.RecoveryConsole]::GetConsoleMode($h, [ref]$m)) { throw 'Run in the original console.' }\r\n"+
                    "try {\r\nif (-not [Jobs.RecoveryConsole]::SetConsoleMode($h, ($m -bor 4))) { throw 'Cannot enable terminal recovery.' }\r\n"+
                    "[Console]::Write([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('"+encoded+"')))\r\n"+
                    "[Console]::ForegroundColor = [ConsoleColor]"+((int)state.Foreground)+"\r\n"+
                    "[Console]::BackgroundColor = [ConsoleColor]"+((int)state.Background)+"\r\n"+
                    "[Console]::Write([string][char]27 + '[39;49m')\r\n"+
                    "} finally { [void][Jobs.RecoveryConsole]::SetConsoleMode($h, $m) }\r\n";
                File.WriteAllText(state.Recovery,manual,new UTF8Encoding(false));
                state.Owner = identity+":"+Process.GetCurrentProcess().Id+":"+Process.GetCurrentProcess().StartTime.ToUniversalTime().Ticks;
                Environment.SetEnvironmentVariable(OwnerName,state.Owner);
                state.Active = true;
                foreach (string key in Keys) { Console.Write(Escape(key,state.Applied[key])); }
                Console.ForegroundColor = ConsoleColor.White; Console.BackgroundColor = ConsoleColor.Black;
                Dictionary<string,string> check = Query(state);
                foreach (string key in Keys) {
                    if (check == null || Normal(check[key]) != Normal(state.Applied[key])) { Restore(state); Plain(state); return; }
                }
            } catch (Exception error) {
                Restore(state); Plain(state);
                Console.Error.WriteLine("[Jobs] Terminal style unavailable: " + error.Message);
            }
        }
        public static void Restore(State state) {
            if (state == null) { return; }
            try {
                if (state.Active) {
                    Dictionary<string,string> current = Query(state);
                    bool complete = current != null;
                    if (current != null) {
                        bool restoreForeground = Console.ForegroundColor == ConsoleColor.White && Normal(current["10"]) == Normal(state.Applied["10"]) && Normal(current["4;15"]) == Normal(state.Applied["4;15"]);
                        bool restoreBackground = Console.BackgroundColor == ConsoleColor.Black && Normal(current["11"]) == Normal(state.Applied["11"]) && Normal(current["4;0"]) == Normal(state.Applied["4;0"]);
                        foreach (string key in Keys) {
                            if (Normal(current[key]) == Normal(state.Applied[key])) { Console.Write(Escape(key,state.Original[key])); }
                            else if (Normal(current[key]) != Normal(state.Original[key])) {
                                complete = false; Console.Error.WriteLine("[Jobs] Kept a concurrent color change: " + key);
                            }
                        }
                        if (restoreForeground) { Console.ForegroundColor = state.Foreground; Console.Write("\x1b[39m"); }
                        if (restoreBackground) { Console.BackgroundColor = state.Background; Console.Write("\x1b[49m"); }
                    }
                    if (complete) {
                        Dictionary<string,string> check = Query(state);
                        foreach (string key in Keys) { if (check == null || Normal(check[key]) != Normal(state.Original[key])) { complete = false; } }
                    }
                    if (complete) { File.Delete(state.Recovery); }
                    else { Console.Error.WriteLine("[Jobs] Color restore needs review. Manual recovery: powershell -NoProfile -File \""+state.Recovery+"\""); }
                }
            } catch (Exception error) {
                Console.Error.WriteLine("[Jobs] Color restore failed: "+error.Message+"; recovery: "+state.Recovery);
            } finally {
                if (state.Owner != null && Environment.GetEnvironmentVariable(OwnerName) == state.Owner) { Environment.SetEnvironmentVariable(OwnerName,state.PreviousOwner); }
                state.Active = false;
                uint currentMode;
                if (state.ModeChanged && GetConsoleMode(state.Output,out currentMode) && currentMode == (state.OutputMode | 4)) { SetConsoleMode(state.Output,state.OutputMode); }
                state.ModeChanged = false;
                if (state.Fallback) {
                    foreach (KeyValuePair<string,string> pair in state.EnvironmentBefore) {
                        string applied = pair.Key == "FORCE_COLOR" || pair.Key == "CLICOLOR" ? "0" : "1";
                        if (Environment.GetEnvironmentVariable(pair.Key) == applied) { Environment.SetEnvironmentVariable(pair.Key,pair.Value); }
                    }
                    state.Fallback = false;
                }
            }
        }
    }
}
'@
        } catch {
            [Console]::Error.WriteLine('[Jobs] Terminal style setup failed; using plain output: ' + $_.Exception.Message)
            return @{ JobsTerminalPlainFallback = $true; Before = @{} }
        }
    }
    return New-Object Jobs.TerminalStyleV1.Native+State
}
# Guard setup is optional; failure keeps business behavior and the user's original terminal settings.
function Start-JobsTerminalStyle {
    param($State)
    if ($State -is [Collections.IDictionary] -and $State.Contains('JobsTerminalPlainFallback')) {
        foreach ($key in @('NO_COLOR', 'PLAIN_OUTPUT', 'FORCE_COLOR', 'CLICOLOR', 'ANSI_COLORS_DISABLED')) {
            $State.Before[$key] = [Environment]::GetEnvironmentVariable($key)
            [Environment]::SetEnvironmentVariable($key, $(if (@('FORCE_COLOR', 'CLICOLOR') -contains $key) { '0' } else { '1' }))
        }
        return
    }
    if ($null -ne $State) { [Jobs.TerminalStyleV1.Native]::Enter($State) }
}
# A finally block also runs for script exit and Ctrl+C; direct .NET calls avoid stopped pipelines.
function Stop-JobsTerminalStyle {
    param($State)
    if ($State -is [Collections.IDictionary] -and $State.Contains('JobsTerminalPlainFallback')) {
        foreach ($key in $State.Before.Keys) {
            $applied = if (@('FORCE_COLOR', 'CLICOLOR') -contains $key) { '0' } else { '1' }
            if ([Environment]::GetEnvironmentVariable($key) -ceq $applied) { [Environment]::SetEnvironmentVariable($key, $State.Before[$key]) }
        }
        return
    }
    if ($null -ne $State) { [Jobs.TerminalStyleV1.Native]::Restore($State) }
}
# END JOBS_TERMINAL_STYLE_V1

$__jobsTerminalStyleState = $null
try {
    if ($MyInvocation.InvocationName -ne '.') {
        $__jobsTerminalStyleState = New-JobsTerminalStyleState
        Start-JobsTerminalStyle $__jobsTerminalStyleState
    }
# BEGIN JOBS_TERMINAL_STYLE_ORIGINAL_BODY
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$module = Import-Module (Join-Path $root 'Scripts/Features/JobsFlutterPackager/Scripts/Action.psm1') -PassThru -Force -DisableNameChecking
$temporaryRoot = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { [IO.Path]::GetTempPath() } else { '/private/tmp' }
$fixture = Join-Path $temporaryRoot ('JobsHarmonyBuildTest-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$count = @{ Value = 0 }
try {
    & $module {
        param($fixture, $count)
        function Assert-Equal {
            param($Actual, $Expected, [string]$Label)
            if ($Actual -cne $Expected) { throw ($Label + '：实际 ' + $Actual + '，预期 ' + $Expected) }
            $count.Value++
        }
        function Assert-Throws {
            param([scriptblock]$Operation, [string]$Label)
            $failed = $false
            try { & $Operation } catch { $failed = $true }
            if (-not $failed) { throw ($Label + '：预期失败却成功') }
            $count.Value++
        }
        $project = Join-Path $fixture '中文 Flutter project'
        foreach ($relative in @('lib', 'ohos', 'build/ohos')) {
            [void][IO.Directory]::CreateDirectory((Join-Path $project $relative))
        }
        [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), "name: jobs_fixture`ndependencies:`n  flutter:`n    sdk: flutter`n")
        foreach ($relative in @('ohos/build-profile.json5', 'ohos/oh-package.json5')) {
            [IO.File]::WriteAllText((Join-Path $project $relative), '{}')
        }
        $sdk = Join-Path $fixture 'SDK with 空格'
        [void][IO.Directory]::CreateDirectory((Join-Path $sdk 'bin'))
        [IO.File]::WriteAllText((Join-Path $sdk 'bin/flutter.bat'), '@rem never executed')
        Assert-Equal (Get-JobsPackagerFlutter -Project $project -SdkRoot $sdk) (Join-Path $sdk 'bin/flutter.bat') '显式 SDK 中文空格路径'
        Assert-Throws { Get-JobsPackagerFlutter -Project $project -SdkRoot (Join-Path $fixture 'missing') } '显式 SDK 缺失停止'
        [IO.File]::WriteAllText((Join-Path $project '.fvmrc'), '{"flutter":"custom_ohos"}')
        Assert-Throws { Get-JobsPackagerFlutter -Project $project } 'FVM 缺失不回退全局'
        Assert-Equal (Get-JobsPackagerHarmonyOptions -Type all -Mode release -Flavor '').Type 'all' '双产物配置'
        Assert-Throws { Get-JobsPackagerHarmonyOptions -Type all -Mode invalid -Flavor '' } '拒绝模式'
        Assert-Throws { Get-JobsPackagerHarmonyOptions -Type all -Mode release -Flavor prod } '拒绝不可靠 flavor'
        function JobsFixtureExitSeven { $global:LASTEXITCODE = 7 }
        $failureCode = 0
        try { Invoke-JobsPackagerTool -File JobsFixtureExitSeven -Arguments @() -Project $project }
        catch { $failureCode = $_.Exception.Data['JobsExitCode'] }
        Assert-Equal $failureCode 7 '构建失败携带原退出码'
        # 所有探测均替换为只读内存返回，不调用真实工具链。
        function Find-JobsExecutable { param($Name, $Candidates); return (Join-Path $fixture 'fake-tool') }
        $script:ProbeApp = $true
        function Invoke-JobsPackagerProbe {
            param($File, $Arguments, $Project)
            if ($Arguments.Count -eq 3 -and $Arguments[0] -eq 'build') {
                if ($Arguments[1] -eq 'app' -and -not $script:ProbeApp) {
                    return [pscustomobject]@{ ExitCode = 0; Output = 'Usage: flutter build <subcommand>' }
                }
                return [pscustomobject]@{ ExitCode = 0; Output = ('Usage: flutter build ' + $Arguments[1]) }
            }
            return [pscustomobject]@{ ExitCode = 0; Output = 'fixture version' }
        }
        Assert-JobsPackagerHarmonyToolchain -Project $project -Flutter 'fixture-flutter' -Targets @('hap', 'app')
        $count.Value++
        $script:ProbeApp = $false
        Assert-Throws { Assert-JobsPackagerHarmonyToolchain -Project $project -Flutter 'fixture-flutter' -Targets @('hap', 'app') } '缺 APP 能力停止'
        function Assert-JobsPackagerHarmonyToolchain { param($Project, $Flutter, $Targets); Assert-Equal ($Targets -join ',') 'hap,app' '构建前核验两种能力' }
        function Initialize-JobsPackagerHarmonyEnvironment {
            $env:TOOL_HOME = 'fixture tool home'
            $env:DEVECO_SDK_HOME = 'fixture sdk'
            $env:PATH = 'fixture path'
        }
        $script:Calls = New-Object 'System.Collections.Generic.List[string]'
        $script:Failure = ''
        $script:Missing = ''
        $script:RemoveHapOnApp = $false
        function Invoke-JobsPackagerTool {
            param($File, $Arguments, $Project)
            $command = $Arguments -join ' '
            $script:Calls.Add($command)
            if ($command -eq $script:Failure) { throw '隔离模拟构建失败 7' }
            if ($Arguments[0] -eq 'build' -and $Arguments[1] -ne $script:Missing) {
                [IO.File]::WriteAllText((Join-Path $Project ('build/ohos/entry-default-signed.' + $Arguments[1])), $command)
            }
            if ($script:RemoveHapOnApp -and $Arguments[0] -eq 'build' -and $Arguments[1] -eq 'app') {
                Remove-Item -LiteralPath (Join-Path $Project 'build/ohos/entry-default-signed.hap') -Force
            }
        }
        $environment = @{}
        foreach ($name in @('PATH', 'TOOL_HOME', 'DEVECO_SDK_HOME')) { $environment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
        $savedFlavor = $env:FLAVOR
        $env:FLAVOR = ''
        try {
            Invoke-JobsPackagerHarmonyBuild -Project $project -FlutterSdk $sdk -Type all -Mode release
            Assert-Equal ($script:Calls -join '|') 'pub get|build hap --release|build app --release' '固定双产物顺序'
            foreach ($name in $environment.Keys) { Assert-Equal ([Environment]::GetEnvironmentVariable($name, 'Process')) $environment[$name] ('恢复 ' + $name) }
            Assert-Equal (@(Get-JobsPackagerHarmonyArtifacts -Project $project -Type hap).Count) 1 'HAP 非空'
            Assert-Equal (@(Get-JobsPackagerHarmonyArtifacts -Project $project -Type app).Count) 1 'APP 非空'
            foreach ($failure in @('pub get', 'build hap --release', 'build app --release')) {
                $script:Calls.Clear()
                $script:Failure = $failure
                Assert-Throws { Invoke-JobsPackagerHarmonyBuild -Project $project -FlutterSdk $sdk -Type all -Mode release } ('传播失败 ' + $failure)
                if ($failure -eq 'pub get') { Assert-Equal $script:Calls.Count 1 'pub 失败不构建' }
                if ($failure -eq 'build hap --release') { Assert-Equal $script:Calls.Count 2 'HAP 失败不继续 APP' }
                foreach ($name in $environment.Keys) { Assert-Equal ([Environment]::GetEnvironmentVariable($name, 'Process')) $environment[$name] ('失败恢复 ' + $name) }
            }
            $script:Failure = ''
            $script:RemoveHapOnApp = $true
            Assert-Throws { Invoke-JobsPackagerHarmonyBuild -Project $project -FlutterSdk $sdk -Type all -Mode release } 'APP 构建删掉 HAP 时整体失败'
            $script:RemoveHapOnApp = $false
            Remove-Item -LiteralPath (Join-Path $project 'build/ohos/entry-default-signed.app')
            $script:Missing = 'app'
            Assert-Throws { Invoke-JobsPackagerHarmonyBuild -Project $project -FlutterSdk $sdk -Type all -Mode release } 'APP 未输出整体失败'
            [IO.File]::WriteAllText((Join-Path $project 'build/ohos/empty.app'), '')
            Assert-Throws { Get-JobsPackagerHarmonyArtifacts -Project $project -Type app } '空 APP 不算产物'
            $outside = Join-Path $fixture 'external-module'
            [void][IO.Directory]::CreateDirectory((Join-Path $outside 'build/outputs'))
            [IO.File]::WriteAllText((Join-Path $outside 'build/outputs/external.app'), 'external fixture')
            $link = Join-Path $project 'ohos/linked-module'
            $linked = $false
            try {
                [void](New-Item -ItemType SymbolicLink -Path $link -Target $outside -ErrorAction Stop)
                $linked = $true
            } catch { Write-Host 'SKIP：本机无创建链接权限；保留其它产物检查。' }
            if ($linked) {
                Assert-Throws { Get-JobsPackagerHarmonyArtifacts -Project $project -Type app } '不采纳链接模块的外部产物'
                Remove-Item -LiteralPath $link -Force
                $plainModule = Join-Path $project 'ohos/plain-module'
                [void][IO.Directory]::CreateDirectory($plainModule)
                $link = Join-Path $plainModule 'build'
                [void](New-Item -ItemType SymbolicLink -Path $link -Target (Join-Path $outside 'build'))
                Assert-Throws { Get-JobsPackagerHarmonyArtifacts -Project $project -Type app } '不采纳链接输出目录的外部产物'
                Remove-Item -LiteralPath $link -Force
            }
            Rename-Item -LiteralPath (Join-Path $project 'lib') -NewName 'lib-backup'
            Assert-Throws { Invoke-JobsPackagerHarmonyBuild -Project $project -FlutterSdk $sdk -Type all -Mode release } '缺 lib 不构建'
        } finally {
            $env:FLAVOR = $savedFlavor
        }
    } $fixture $count
    $dispatcher = Import-Module (Join-Path $root 'Scripts/SourceTree.psm1') -PassThru -Force -DisableNameChecking
    & $dispatcher {
        param($count, $fixture)
        $script:LogFile = Join-Path $fixture 'dispatch.log'
        $script:ExpectedLog = $script:LogFile
        function Import-Module {
            param($Path, [switch]$Force, [switch]$DisableNameChecking, [switch]$PassThru)
            New-Module {
                function Invoke-JobsPackagerHarmonyBuild {
                    param($Project, $Type)
                    [pscustomobject]@{ Project = $Project; Type = $Type; Log = $script:PackagerLog }
                }
            }
        }
        $result = Invoke-JobsFeatureModule 'JobsFlutterPackager' 'fixture project' 'ohos'
        if ($result.Type -cne 'all' -or $result.Project -cne 'fixture project') { throw '调度未强制双产物或目标改变' }
        $count.Value++
        if ($result.Log -cne $script:ExpectedLog) { throw '调度未传入会话日志' }
        $count.Value++
    } $count $fixture
    Remove-Module $dispatcher -Force
    Write-Host ('PASS：' + $count.Value + ' 项鸿蒙双产物断言；没有执行真实 SDK 或构建。')
} finally {
    Remove-Module $module -Force
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}
