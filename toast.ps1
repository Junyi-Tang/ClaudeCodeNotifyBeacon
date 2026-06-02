# Claude Code Stop hook notification
$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
[System.IO.File]::AppendAllText("$env:TEMP\claude_notify_hook_log.txt", "$ts | STOP HOOK FIRED`n", [System.Text.Encoding]::UTF8)

# Use BurntToast for proper Windows 11 toast notification
try {
    Import-Module BurntToast -ErrorAction Stop
    New-BurntToastNotification -Text "Claude Code", "Task complete" -ErrorAction SilentlyContinue
} catch {
    # Fallback to balloon notification
    Add-Type -AssemblyName System.Windows.Forms
    $notify = New-Object System.Windows.Forms.NotifyIcon
    $notify.Icon = [System.Drawing.SystemIcons]::Information
    $notify.Visible = $true
    $notify.ShowBalloonTip(5000, 'Claude Code', 'Task complete', [System.Windows.Forms.ToolTipIcon]::Info)
    Start-Sleep -Seconds 2
    $notify.Dispose()
}
