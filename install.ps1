<#
  ClaudeCodeNotifyBeacon - install.ps1
  Registers the Notification + Stop hooks in ~/.claude/settings.json so Claude Code toasts you
  when it needs input or finishes a turn.

  Usage:
    .\install.ps1                  # install (backs up settings.json, wires hooks, fires a test toast)
    .\install.ps1 -Uninstall       # remove the hooks
    .\install.ps1 -NoTest          # install without firing the test toast
    .\install.ps1 -SettingsFile X  # target a specific settings.json (e.g. a project .claude\settings.json)
#>
[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$NoTest,
    [string]$SettingsFile
)

$ErrorActionPreference = 'Stop'
$root        = $PSScriptRoot
$notify      = Join-Path $root 'notify.ps1'
$legacyAppId = 'ClaudeCode.NotifyBeacon'   # unused now; cleaned up on uninstall (older versions registered it)
$ourCmd      = "powershell -NoProfile -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File `"$notify`""

if ($SettingsFile) { $settingsPath = $SettingsFile }
else { $settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json' }

function Save-Json($obj, $path) {
    # Write UTF-8 WITHOUT BOM - Claude Code's JSON parser rejects a BOM.
    $json = $obj | ConvertTo-Json -Depth 30
    [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding $false))
}

function Set-JsonProp($obj, [string]$name, $value) {
    # A PSCustomObject won't accept assignment to a property that doesn't exist yet; add it instead.
    if ($obj.PSObject.Properties[$name]) { $obj.$name = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}

if (-not (Test-Path $notify)) { throw "notify.ps1 not found next to install.ps1 ($notify)" }

# ---- Load (or create) settings.json ------------------------------------
if (Test-Path $settingsPath) {
    $backup = "$settingsPath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item $settingsPath $backup -Force
    Write-Host "Backed up settings.json -> $backup"
    try { $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json }
    catch { throw "Could not parse $settingsPath as JSON. Aborting so nothing is clobbered. ($_)" }
}
else {
    New-Item -ItemType Directory -Force -Path (Split-Path $settingsPath) | Out-Null
    $settings = [pscustomobject]@{}
    Write-Host "No settings.json found; creating a new one."
}

if (-not $settings.PSObject.Properties['hooks']) {
    $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
}
$hooks = $settings.hooks

# Remove any existing entries that point at this notify.ps1 (so we never duplicate, and so
# -Uninstall removes them cleanly).
foreach ($evt in @('Notification', 'Stop')) {
    if ($hooks.PSObject.Properties[$evt]) {
        $kept = @(@($hooks.$evt) | Where-Object {
            $cmds = @($_.hooks | ForEach-Object { [string]$_.command })
            -not ($cmds -match 'notify\.ps1')
        })
        $hooks.$evt = $kept
    }
}

if ($Uninstall) {
    foreach ($evt in @('Notification', 'Stop')) {
        if ($hooks.PSObject.Properties[$evt] -and @($hooks.$evt).Count -eq 0) {
            $hooks.PSObject.Properties.Remove($evt)
        }
    }
    if (@($hooks.PSObject.Properties).Count -eq 0) { $settings.PSObject.Properties.Remove('hooks') }
    Save-Json $settings $settingsPath
    Remove-Item "HKCU:\SOFTWARE\Classes\AppUserModelId\$legacyAppId" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Uninstalled. Restart any open Claude Code session to reload settings.json." -ForegroundColor Green
    return
}

# ---- Add our hook entries ----------------------------------------------
$notificationEntry = [pscustomobject]@{
    matcher = ''
    hooks   = @([pscustomobject]@{ type = 'command'; command = $ourCmd })
}
$stopEntry = [pscustomobject]@{
    hooks = @([pscustomobject]@{ type = 'command'; command = $ourCmd })
}

Set-JsonProp $hooks 'Notification' @(@($hooks.Notification) + $notificationEntry | Where-Object { $_ })
Set-JsonProp $hooks 'Stop'         @(@($hooks.Stop) + $stopEntry | Where-Object { $_ })

Save-Json $settings $settingsPath
Write-Host "Registered Notification + Stop hooks in $settingsPath" -ForegroundColor Green
Write-Host ""
Write-Host "Done. Restart any open Claude Code session so it reloads settings.json." -ForegroundColor Green

if (-not $NoTest) {
    & powershell -STA -NoProfile -ExecutionPolicy Bypass -File $notify -Test
    Write-Host "Fired a test toast - check the bottom-right of your screen."
}
