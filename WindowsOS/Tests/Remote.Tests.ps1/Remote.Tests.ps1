#requires -Version 5.1
# 远程地址枚举、分流与依赖链隔离验证；不安装、不联网、不启动真实浏览器。
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


$__jobsTerminalStyleState = $null
try {
    if ($MyInvocation.InvocationName -ne '.') {
        $__jobsTerminalStyleState = New-JobsTerminalStyleState
        Start-JobsTerminalStyle $__jobsTerminalStyleState
    }
# BEGIN JOBS_TERMINAL_STYLE_ORIGINAL_BODY
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('JobsSourceTreeRemote-'+[guid]::NewGuid().ToString('N'))
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -and $fixture.StartsWith('/var/') -and (Test-Path -LiteralPath '/private/var')) { $fixture='/private'+$fixture }
[void][IO.Directory]::CreateDirectory($fixture)
$counter=@{Value=0}
# 每项断言保留具体业务边界。
function Assert-Check($Condition,[string]$Label) { if (-not $Condition) { throw $Label };$counter.Value++;Write-JobsUrlText "PASS $Label" }
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
    Write-JobsUrlText "PASS：$($counter.Value) 项远程动作断言。"
} finally {
    foreach ($key in $environmentKeys) { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') }
    foreach ($key in @('JOBS_REMOTE_TEST_ROWS','JOBS_REMOTE_TEST_CODE','JOBS_REMOTE_TEST_INVALID')) { [Environment]::SetEnvironmentVariable($key,$null,'Process') }
    Remove-Item -LiteralPath $fixture -Recurse -Force
}

# END JOBS_TERMINAL_STYLE_ORIGINAL_BODY
} finally {
    Stop-JobsTerminalStyle $__jobsTerminalStyleState
}
