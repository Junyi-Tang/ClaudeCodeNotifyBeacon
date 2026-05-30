param([string]$Message = "")

# ── Hook entry point: ensure daemon alive, debounce, play sound, write trigger, exit fast ──

# Auto-start daemon if not running
$daemonLock = "$env:TEMP\claude_notify_daemon.lock"
$daemonAlive = $false
if (Test-Path $daemonLock) {
    try {
        $daemonPid = [int](Get-Content $daemonLock -Raw).Trim()
        $daemonProc = Get-Process -Id $daemonPid -ErrorAction SilentlyContinue
        if ($daemonProc -and $daemonProc.ProcessName -eq "powershell") {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$daemonPid" -ErrorAction SilentlyContinue).CommandLine
            if ($cmdLine -like "*notify-daemon.ps1*") { $daemonAlive = $true }
        }
    } catch {}
}
if (-not $daemonAlive) {
    $daemonPath = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) "notify-daemon.ps1"
    Remove-Item "$env:TEMP\claude_notify_ready.txt" -Force -ErrorAction SilentlyContinue
    Start-Process powershell -WindowStyle Hidden -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-File", $daemonPath)
    # Wait for daemon to signal ready (up to 10s)
    $readyFile = "$env:TEMP\claude_notify_ready.txt"
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        if (Test-Path $readyFile) { break }
    }
}

$lockFile = "$env:TEMP\claude_notify_lock.txt"
$now = Get-Date
if (Test-Path $lockFile) {
    try {
        $last = Get-Date (Get-Content $lockFile -Raw).Trim()
        if (($now - $last).TotalSeconds -lt 90) { exit 0 }
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
                    $hasBackgroundTasks = $json.background_tasks -and $json.background_tasks.Count -gt 0
                    $hasLastMessage = $json.last_assistant_message -and $json.last_assistant_message.Length -gt 0
                    $stopHookActive = $json.stop_hook_active -eq $true
                    if (-not $hasBackgroundTasks -and $hasLastMessage -and -not $stopHookActive) {
                        $prompt = if ($json.user_prompt) { $json.user_prompt } else { "Task" }
                        if ($prompt.Length -gt 40) { $prompt = $prompt.Substring(0, 37) + "..." }
                        $Message = "Finished: `"$prompt`""
                    } else {
                        exit 0
                    }
                }
            }
        }
    } catch {}
}
if ([string]::IsNullOrEmpty($Message)) { $Message = "Task completed" }

# Write trigger — atomic write so FileSystemWatcher fires on complete content
$triggerFile = "$env:TEMP\claude_notify_trigger.txt"
[System.IO.File]::WriteAllText($triggerFile, $Message, [System.Text.Encoding]::UTF8)
