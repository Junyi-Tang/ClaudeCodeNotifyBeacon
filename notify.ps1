param([string]$Message = "")

# ── Capture stdin once — used by both diagnostic log and main parsing ──
$stdinRaw = ""
try { if ([Console]::In.Peek() -ne -1) { $stdinRaw = [Console]::In.ReadToEnd() } } catch {}

# ── Diagnostic log (remove after verification) ──
$logFile = "$env:TEMP\claude_notify_hook_log.txt"
$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
"$ts | CALLED | Msg='$Message' | PID=$PID | stdin=$($stdinRaw.Substring(0, [Math]::Min(200, $stdinRaw.Length)))" | Out-File $logFile -Append -Encoding UTF8

# ── Hook entry point: ensure daemon alive, debounce, write trigger, exit fast ──

# Auto-start daemon if not running
$daemonAlive = $false
$daemonLock = "$env:TEMP\claude_notify_daemon.lock"

# Fast path: check lock file for a running daemon PID
if (Test-Path $daemonLock) {
    try {
        $lockContent = (Get-Content $daemonLock -Raw).Trim()
        if ($lockContent -ne "starting") {
            $daemonPid = [int]$lockContent
            $proc = Get-Process -Id $daemonPid -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -eq "powershell") {
                $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$daemonPid" -ErrorAction SilentlyContinue).CommandLine
                if ($cmdLine -like "*notify-daemon.ps1*") { $daemonAlive = $true }
            }
        } else {
            # Another notify.ps1 is starting the daemon right now — wait for it
            Start-Sleep -Seconds 3
            try {
                $lockContent2 = (Get-Content $daemonLock -Raw).Trim()
                if ($lockContent2 -ne "starting") {
                    $daemonPid2 = [int]$lockContent2
                    $proc2 = Get-Process -Id $daemonPid2 -ErrorAction SilentlyContinue
                    if ($proc2 -and $proc2.ProcessName -eq "powershell") {
                        $cmdLine2 = (Get-CimInstance Win32_Process -Filter "ProcessId=$daemonPid2" -ErrorAction SilentlyContinue).CommandLine
                        if ($cmdLine2 -like "*notify-daemon.ps1*") { $daemonAlive = $true }
                    }
                }
            } catch {}
        }
    } catch {}
}

# Slow path: scan processes if lock file didn't confirm
if (-not $daemonAlive) {
    try {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop | ForEach-Object {
            if ($_.CommandLine -like "*notify-daemon.ps1*") {
                $daemonAlive = $true
                $_.ProcessId | Out-File $daemonLock -Force
            }
        }
    } catch {}
}

if (-not $daemonAlive) {
    $daemonPath = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) "notify-daemon.ps1"
    Remove-Item "$env:TEMP\claude_notify_ready.txt" -Force -ErrorAction SilentlyContinue
    "starting" | Out-File $daemonLock -Force
    Start-Process powershell -WindowStyle Hidden -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-File", $daemonPath)
    # Wait for daemon to signal ready (up to 10s)
    $readyFile = "$env:TEMP\claude_notify_ready.txt"
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        if (Test-Path $readyFile) { break }
    }
}

# Debounce — skip if last notification was < 15s ago
$lockFile = "$env:TEMP\claude_notify_lock.txt"
$now = Get-Date
if (Test-Path $lockFile) {
    try {
        $last = Get-Date (Get-Content $lockFile -Raw).Trim()
        if (($now - $last).TotalSeconds -lt 15) { exit 0 }
    } catch {}
}
[System.IO.File]::WriteAllText($lockFile, $now.ToString("o"), [System.Text.Encoding]::UTF8)

# Hook stdin parsing (uses $stdinRaw captured above — stdin is not re-read)
if ([string]::IsNullOrEmpty($Message)) {
    try {
        if ($stdinRaw) {
            $json = $stdinRaw | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($json -and $json.user_prompt) {
                $prompt = $json.user_prompt
                if ($prompt.Length -gt 40) { $prompt = $prompt.Substring(0, 37) + "..." }
                $Message = "Finished: `"$prompt`""
            }
        }
    } catch {}
}
if ([string]::IsNullOrEmpty($Message)) { $Message = "Task completed" }

# Write trigger — atomic write so daemon detects complete content
$triggerFile = "$env:TEMP\claude_notify_trigger.txt"
[System.IO.File]::WriteAllText($triggerFile, $Message, [System.Text.Encoding]::UTF8)
