<#
  ClaudeCodeNotifyBeacon - notify.ps1
  Fires a native Windows toast when Claude Code needs your attention or finishes a turn.

  - No daemon, no background process, no external modules. Uses the OS toast API directly.
  - Invoked by Claude Code's Notification / Stop hooks (JSON on stdin), or manually with -Message.
  - Always exits 0 and never writes to stdout, so it can never interfere with Claude Code.
#>
[CmdletBinding()]
param(
    [string]$Message,
    [string]$Title = 'Claude Code',
    [switch]$Test
)

# ---- Config -------------------------------------------------------------
$NotifyOnStop   = $true   # toast when a turn finishes. Set $false for "only when Claude needs input".
$PlaySound      = $true   # play the default notification sound
$DebounceSeconds = 5      # suppress an identical toast fired again within this window
$SuppressIdleWaiting = $true  # skip the idle "waiting for your input" ping that fires ~60s after a turn
                              # ends (redundant with the Stop toast). Permission-request pings still fire.
# Built-in Windows PowerShell app identity. Windows only displays toasts for an AppUserModelID it
# recognizes (one backed by a Start Menu shortcut); a custom AUMID is silently dropped. Using the
# always-present PowerShell identity makes toasts reliably appear. Branding lives inside the toast
# (Claude icon + bold "Claude Code" title), so the only cosmetic cost is a small top-line app label.
$AppId          = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
# -------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
$icon = Join-Path $PSScriptRoot 'assets\claude-icon.png'

function Write-ErrLog([string]$msg) {
    try { Add-Content -Path (Join-Path $env:TEMP 'claude-notify-error.log') -Value "[$(Get-Date -f s)] $msg" -Encoding utf8 } catch {}
}

function ConvertTo-XmlText([string]$s) {
    if ($null -eq $s) { return '' }
    $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&apos;')
}

function Test-FromDesktopApp {
    # Walk up the parent-process chain. The Claude *desktop app* is a GUI shell named claude.exe whose
    # path is NOT the CLI engine - the engine always runs from a '\claude-code\' folder, and the Store
    # build of the app lives under '\WindowsApps\Claude_...'. A terminal session has no such ancestor.
    # If we find one, this turn came from the desktop app (which ships its own notifications), so we
    # stay quiet and let the terminal be the only surface that toasts.
    try {
        $cur = $PID
        for ($i = 0; $i -lt 12; $i++) {
            $p = Get-CimInstance Win32_Process -Filter "ProcessId = $cur" -ErrorAction Stop
            if (-not $p) { break }
            $name = [string]$p.Name
            $path = [string]$p.ExecutablePath
            if ($path -match '(?i)\\WindowsApps\\Claude_') { return $true }
            if ($name -ieq 'claude.exe' -and $path -and ($path -notmatch '(?i)(\\claude-code\\|\\\.local\\bin\\)')) { return $true }
            $ppid = [int]$p.ParentProcessId
            if ($ppid -le 0 -or $ppid -eq $cur) { break }
            $cur = $ppid
        }
    } catch {}
    return $false
}

try {
    # ---- Gather hook context (JSON on stdin), if any --------------------
    $raw = ''
    if (-not $Test -and [Console]::IsInputRedirected) { $raw = [Console]::In.ReadToEnd() }

    $data = $null
    if ($raw.Trim()) { try { $data = $raw | ConvertFrom-Json } catch { $data = $null } }

    $event = if ($data -and $data.hook_event_name) { [string]$data.hook_event_name } else { '' }

    # Don't re-fire while a Stop hook is already being processed (prevents loops).
    if ($data -and $data.stop_hook_active) { exit 0 }

    # Terminal-only: the desktop app already shows its own notifications, so a toast there is
    # redundant. Skip this gate for explicit fires (-Test, -Message, or BEACON_FORCE=1 from verify).
    if (-not $Test -and -not $Message -and $env:BEACON_FORCE -ne '1' -and (Test-FromDesktopApp)) {
        Write-ErrLog 'Suppressed: launched from the Claude desktop app (it has its own notifications).'
        exit 0
    }

    if ($event -eq 'Stop' -and -not $NotifyOnStop -and -not $Test) { exit 0 }

    # The idle "waiting for your input" Notification fires ~60s after a turn ends - redundant with the
    # Stop toast. Suppress it, but keep permission-request Notifications (different message text).
    if ($SuppressIdleWaiting -and $event -eq 'Notification' -and -not $Test -and -not $Message) {
        $msgText = if ($data -and $data.message) { [string]$data.message } else { '' }
        if ($msgText -match '(?i)waiting for your input') { Write-ErrLog "Suppressed idle-waiting Notification: $msgText"; exit 0 }
    }

    # ---- Build the message --------------------------------------------
    $body = ''
    if ($Test) {
        $body = 'Test notification - your beacon is working.'
    }
    elseif ($Message) {
        $body = $Message
    }
    elseif ($data -and $data.message) {
        $body = [string]$data.message          # Notification hook supplies this (e.g. needs permission)
    }
    elseif ($event -eq 'Stop') {
        $body = 'Turn complete.'
    }
    else {
        $body = 'Claude needs your attention.'
    }

    # Project folder as small attribution context
    $ctx = ''
    if ($data -and $data.cwd) { try { $ctx = Split-Path -Leaf ([string]$data.cwd) } catch {} }
    if (-not $ctx -and $Test) { $ctx = Split-Path -Leaf $PSScriptRoot }

    # ---- Debounce identical toasts -------------------------------------
    if (-not $Test) {
        $keyBytes = [Text.Encoding]::UTF8.GetBytes("$event|$body")
        $md5 = [Security.Cryptography.MD5]::Create()
        $hash = ([BitConverter]::ToString($md5.ComputeHash($keyBytes))).Replace('-', '').Substring(0, 12)
        $tick = Join-Path $env:TEMP "claude-notify-$hash.tick"
        if (Test-Path $tick) {
            $age = (Get-Date) - (Get-Item $tick).LastWriteTime
            if ($age.TotalSeconds -lt $DebounceSeconds) { exit 0 }
        }
        Set-Content -Path $tick -Value '' -Force
    }

    # ---- Fire the toast ------------------------------------------------
    $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $null = [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]

    $imageXml = ''
    if (Test-Path $icon) { $imageXml = "<image placement=`"appLogoOverride`" hint-crop=`"none`" src=`"$(ConvertTo-XmlText $icon)`"/>" }
    $ctxXml = ''
    if ($ctx) { $ctxXml = "<text placement=`"attribution`">$(ConvertTo-XmlText $ctx)</text>" }
    $audioXml = if ($PlaySound) { '<audio src="ms-winsoundevent:Notification.Default"/>' } else { '<audio silent="true"/>' }

    $xml = @"
<toast duration="short">
  <visual>
    <binding template="ToastGeneric">
      $imageXml
      <text>$(ConvertTo-XmlText $Title)</text>
      <text>$(ConvertTo-XmlText $body)</text>
      $ctxXml
    </binding>
  </visual>
  $audioXml
</toast>
"@

    $doc = [Windows.Data.Xml.Dom.XmlDocument]::new()
    $doc.LoadXml($xml)
    $toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($toast)
}
catch {
    Write-ErrLog $_.Exception.Message
}
exit 0
