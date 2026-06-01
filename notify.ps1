param([string]$Message = "")

# ── Hook entry point: ensure daemon alive, debounce, play sound, write trigger, exit fast ──

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
            if ($proc) { $daemonAlive = $true }
        } else {
            # Another notify.ps1 is starting the daemon right now — wait for it
            Start-Sleep -Seconds 3
            try {
                $lockContent2 = (Get-Content $daemonLock -Raw).Trim()
                if ($lockContent2 -ne "starting") {
                    $proc = Get-Process -Id ([int]$lockContent2) -ErrorAction SilentlyContinue
                    if ($proc) { $daemonAlive = $true }
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

# Hook stdin parsing (non-blocking)
if ([string]::IsNullOrEmpty($Message)) {
    try {
        if ([Console]::In.Peek() -ne -1) {
            $stdinLines = @()
            while ([Console]::In.Peek() -ne -1) {
                $line = [Console]::In.ReadLine()
                if ($null -eq $line) { break }
                $stdinLines += $line
            }
            $stdin = $stdinLines -join "`n"
            if ($stdin) {
                $json = $stdin | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($json) {
                    # Check multiple conditions to ensure we're truly done:
                    $hasBackgroundTasks = $json.background_tasks -and $json.background_tasks.Count -gt 0
                    $hasLastMessage = $json.last_assistant_message -and $json.last_assistant_message.Length -gt 0
                    $stopHookActive = $json.stop_hook_active -eq $true

                    # Only notify if: no background work, has message, and stop hook is NOT active
                    if (-not $hasBackgroundTasks -and $hasLastMessage -and -not $stopHookActive) {
                        $prompt = if ($json.user_prompt) { $json.user_prompt } else { "Task" }
                        if ($prompt.Length -gt 40) { $prompt = $prompt.Substring(0, 37) + "..." }
                        $Message = "Finished: `"$prompt`""
                    } else {
                        # Still working - don't notify
                        exit 0
                    }
                }
            }
        }
    } catch {
        # Silently fail
    }
}
if ([string]::IsNullOrEmpty($Message)) { $Message = "Task completed" }

# Write trigger — atomic write so FileSystemWatcher fires on complete content
$triggerFile = "$env:TEMP\claude_notify_trigger.txt"
[System.IO.File]::WriteAllText($triggerFile, $Message, [System.Text.Encoding]::UTF8)
