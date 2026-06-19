<#
  tools/verify.ps1 - proves notify.ps1 actually delivers toasts (no human eyeballing needed).

  Feeds event JSON to notify.ps1 on stdin the same way Claude Code does (a native parent
  redirecting stdin, here via cmd.exe), with a unique nonce in each toast, then reads Windows'
  own Action Center history back and confirms the nonce is present. If Windows stored the
  toast, it displayed it. Exit 0 = all checks passed.
#>
$AppId  = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
$notify = Join-Path (Split-Path -Parent $PSScriptRoot) 'notify.ps1'
$tmp    = Join-Path $env:TEMP 'beacon-verify.json'

# verify is a *delivery* test: bypass the terminal-only surface gate so it proves the toast path
# works no matter which surface you run it from (including from inside the desktop app).
$env:BEACON_FORCE = '1'

$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
$null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]

$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId)
Write-Host "Notification setting for identity: $($notifier.Setting)"
if ("$($notifier.Setting)" -ne 'Enabled') {
    Write-Host "FAIL: notifications are disabled ($($notifier.Setting)) - toasts will not display." -ForegroundColor Red
    exit 1
}

function Test-Case([string]$Name, [string]$Json, [string]$Nonce) {
    Set-Content -Path $tmp -Value $Json -Encoding ascii
    # Use the SAME flags install.ps1 registers, so this exercises the real installed hook command.
    cmd /c "powershell -NoProfile -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File `"$notify`" < `"$tmp`"" | Out-Null
    Start-Sleep -Milliseconds 800
    $hist = [Windows.UI.Notifications.ToastNotificationManager]::History.GetHistory($AppId)
    $hit = $false
    foreach ($h in $hist) { if ($h.Content.GetXml() -like "*$Nonce*") { $hit = $true; break } }
    if ($hit) { Write-Host ("PASS: {0} toast delivered to Action Center (matched '{1}')." -f $Name, $Nonce) -ForegroundColor Green }
    else      { Write-Host ("FAIL: {0} toast NOT found in Action Center (looked for '{1}')." -f $Name, $Nonce) -ForegroundColor Red }
    return $hit
}

$n1 = 'ntfy' + (Get-Random -Maximum 999999)
$json1 = '{"hook_event_name":"Notification","message":"Needs your permission ' + $n1 + '","cwd":"C:\\proj\\demo"}'

$n2 = 'stop' + (Get-Random -Maximum 999999)
$json2 = '{"hook_event_name":"Stop","cwd":"C:\\proj\\' + $n2 + '"}'

$ok1 = Test-Case 'Notification' $json1 $n1
$ok2 = Test-Case 'Stop'         $json2 $n2

Remove-Item $tmp -ErrorAction SilentlyContinue

Write-Host ""
if ($ok1 -and $ok2) {
    Write-Host "ALL CHECKS PASSED - the beacon fires and Windows is displaying it." -ForegroundColor Green
    exit 0
}
Write-Host "SOME CHECKS FAILED." -ForegroundColor Red
exit 1
