# ClaudeCodeNotifyBeacon

A dead-simple, reliable desktop notifier for [Claude Code](https://claude.ai/code) on Windows.
When Claude needs your input or finishes a turn, you get a native Windows toast with the
Claude icon — so you can tab away during long runs and get pulled back at the right moment.

**No daemon. No background process. No external modules.** One PowerShell script fires a toast
through the built-in Windows notification API. That's the whole thing.

## When it notifies

| Hook | Fires when | Default |
|---|---|---|
| **Notification** | Claude Code wants your attention — waiting for input or asking permission | on |
| **Stop** | Claude finishes a turn | on (toggle in `notify.ps1`) |

If turn-complete toasts feel too chatty, open `notify.ps1` and set `$NotifyOnStop = $false`.
You'll still be pinged whenever Claude actually needs you.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built in — nothing to install)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

## Install

```powershell
git clone https://github.com/Junyi-Tang/ClaudeCodeNotifyBeacon.git
cd ClaudeCodeNotifyBeacon
.\install.ps1
```

The installer backs up your `~/.claude/settings.json`, registers the two hooks without
duplicating anything, and fires a test toast. **Restart any open Claude Code session
afterward** so it reloads settings.

Uninstall just as cleanly:

```powershell
.\install.ps1 -Uninstall
```

### Manual setup (no installer)

Add to `~/.claude/settings.json` (adjust the path):

```json
{
  "hooks": {
    "Notification": [
      { "matcher": "", "hooks": [
        { "type": "command", "command": "powershell -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File \"C:\\path\\to\\ClaudeCodeNotifyBeacon\\notify.ps1\"" }
      ] }
    ],
    "Stop": [
      { "hooks": [
        { "type": "command", "command": "powershell -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File \"C:\\path\\to\\ClaudeCodeNotifyBeacon\\notify.ps1\"" }
      ] }
    ]
  }
}
```

## Configuration

Edit the block at the top of `notify.ps1`:

| Setting | Default | What it does |
|---|---|---|
| `$NotifyOnStop` | `$true` | Toast when a turn finishes |
| `$PlaySound` | `$true` | Play the default notification sound |
| `$DebounceSeconds` | `5` | Drop an identical toast fired again within this window |

## How it works

1. Claude Code runs the hook command and pipes event JSON to `notify.ps1` on stdin.
2. The script reads the event (`Notification` / `Stop`), builds a short message, and debounces duplicates.
3. It fires a `ToastGeneric` notification via `Windows.UI.Notifications`, sent under Windows'
   built-in PowerShell app identity (always recognized, so the toast reliably displays) and
   branded inside with the Claude logo and a bold "Claude Code" title.

The script always exits 0 and never writes to stdout, so it can't interfere with Claude Code.

### Verify it's working

```powershell
powershell -STA -File tools\verify.ps1
```

This fires both hook types through the real pipeline and reads Windows' Action Center back to
confirm each toast was actually delivered. Exit code 0 means it works, no eyeballing required.

## Troubleshooting

- **No toast appears** — check that notifications are on and **Focus Assist / Do Not Disturb is off**
  (Settings → System → Notifications). Errors, if any, are logged to `%TEMP%\claude-notify-error.log`.
- **Brief console flash** — the hook launches `powershell -WindowStyle Hidden`, which minimizes but
  may not fully eliminate a flash depending on your terminal.
- **Icon looks wrong** — regenerate it with `powershell -STA -File tools\render-icon.ps1`.
- **Toast says "Windows PowerShell" at the top** — that's intentional. Windows only displays toasts
  for an app identity it recognizes, and the built-in PowerShell identity is the one guaranteed to be
  present — so the beacon uses it. The Claude logo and "Claude Code" title inside the toast are the
  real branding.

## License

MIT — see [LICENSE](LICENSE).
