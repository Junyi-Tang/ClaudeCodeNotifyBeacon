# Claude Code Notify

A premium Windows desktop notification for [Claude Code](https://claude.ai/code). Shows a sleek Dynamic Island-style pill with the official Claude brand icon when your task completes.

![Dynamic Island pill notification](assets/claudecode-color.svg)

## Features

- **Dynamic Island pill** — 400×86 ink-black capsule, CornerRadius 37, drop shadow
- **Instant audio + visual** — system chime plays immediately, pill appears within 250ms
- **Official Claude icon** — SVG-parsed brand logo with correct EvenOdd fill-rule
- **Click to dismiss** — fast 150ms fade-out on click
- **Auto-dismiss** — smooth 350ms fade after 30 seconds
- **Storyboard animations** — GPU-accelerated WPF, no Start-Sleep blocking
- **Daemon architecture** — WPF assemblies pre-loaded, zero startup lag
- **Debounce** — 90s lock file prevents duplicate notifications
- **Dynamic task context** — reads hook stdin JSON to show real task summaries

## Requirements

- Windows 10 or 11
- PowerShell 5.1 (built-in)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

## Quick Start

### 1. Clone or download

```powershell
git clone https://github.com/YOUR_USERNAME/claude-code-notify.git
# or just download notify.ps1, notify-daemon.ps1, and assets/
```

### 2. Configure the hook

Add to your Claude Code settings (`~/.claude/settings.json` or project `.claude/settings.json`):

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -ExecutionPolicy Bypass -File \"C:\\Users\\YOURNAME\\path\\to\\notify.ps1\""
          }
        ]
      }
    ]
  },
  "preferredNotifChannel": "notifications_disabled"
}
```

### 3. Start the daemon

```powershell
Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", """C:\Users\YOURNAME\path\to\notify-daemon.ps1"""
)
```

The daemon stays running in the background. Start it once per login session.

### 4. Test

```powershell
"Test notification" | Out-File -FilePath "$env:TEMP\claude_notify_trigger.txt" -Encoding utf8 -Force
```

## How It Works

```
┌─────────────┐     ┌──────────────┐     ┌──────────────────┐
│ Claude Code │ ──▶ │  notify.ps1   │ ──▶ │ notify-daemon.ps1│
│ Notification│     │ sound + write │     │ WPF pill on      │
│ hook fires  │     │ trigger file  │     │ screen 30s       │
└─────────────┘     └──────────────┘     └──────────────────┘
                           ~10ms               ~250ms poll
```

1. Claude Code finishes a task → `Notification` hook fires
2. `notify.ps1` runs: debounce check → plays system chime → writes trigger file → exits
3. `notify-daemon.ps1` (persistent background process with WPF pre-loaded) detects the trigger within 250ms → renders the Dynamic Island pill instantly

## File Structure

```
claude-code-notify/
├── notify.ps1              # Hook entry point (trigger writer)
├── notify-daemon.ps1       # Persistent notification daemon (WPF)
├── assets/
│   └── claudecode-color.svg # Official Claude Code brand icon
└── README.md
```

## License

MIT
