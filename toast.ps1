# Simple inline toast notification — no daemon needed
$ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
[System.IO.File]::AppendAllText("$env:TEMP\claude_notify_hook_log.txt", "$ts | STOP HOOK FIRED`n", [System.Text.Encoding]::UTF8)

Add-Type -AssemblyName System.Windows.Forms
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.SystemIcons]::Information
$notify.Visible = $true
$notify.ShowBalloonTip(5000, 'Claude Code', 'Task complete', [System.Windows.Forms.ToolTipIcon]::Info)
Start-Sleep -Seconds 2
$notify.Dispose()
