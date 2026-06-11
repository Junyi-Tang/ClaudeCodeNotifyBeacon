# Project notes

## Architecture

```
Claude Code hook ──(event JSON on stdin)──> notify.ps1 ──> Windows.UI.Notifications toast
```

That's it. No daemon, no IPC, no lock files, no background process. The toast is rendered by
the OS notification system, so there is nothing of ours to keep alive or crash.

- **`notify.ps1`** — reads the hook event, builds a message, debounces duplicates, fires a
  `ToastGeneric` toast under Windows' built-in PowerShell app identity. Always exits 0; never writes stdout.
- **`install.ps1`** — backs up `settings.json`, wires the `Notification` + `Stop` hooks
  idempotently (preserving everything else, written without a BOM). `-Uninstall` reverses it;
  `-SettingsFile` targets a specific settings.json.
- **`tools/verify.ps1`** — self-test: fires both hook types through the real pipeline and reads
  Windows' Action Center back to confirm delivery. Exit 0 = working.
- **`assets/claude-icon.png`** — the toast app logo, rendered from `claudecode-color.svg`
  by `tools/render-icon.ps1` (WPF, no external dependency).

## Design decision: toast, not a custom window

An earlier version rendered a custom WPF "Dynamic Island" pill via a pre-warmed PowerShell
daemon. It looked nicer but was structurally fragile — PowerShell is a poor host for a
persistent GUI process (STA threading, runspace scope, window-lifecycle and duplicate-daemon
bugs). The reliability ceiling was low and the install footprint was heavy.

This version trades the custom look for the OS toast API. The result is:

- **Reliable** — it's the same notification path every Windows app uses.
- **Zero-dependency** — no module to install, no binary to trust, no SmartScreen prompt.
- **Shareable** — anyone on Win10/11 + Claude Code runs one `install.ps1`.

If a branded custom pill is ever wanted again, the right move is a small compiled C#/.NET tray
app that owns its own window and message loop, with the hook reduced to a one-line signal —
not a PowerShell daemon.

## Design decision: which app identity sends the toast

Windows only displays a toast for an AppUserModelID it recognizes — one backed by a Start Menu
shortcut. A custom AUMID registered only in the registry is accepted by `Show()` without error
but is silently never displayed (this bit us during development: `Setting` reported `Enabled`,
`Show()` threw nothing, yet no toast appeared). Rather than ship a Start Menu shortcut purely to
register a branded identity, the beacon sends under the built-in Windows PowerShell AUMID, which
is always present and recognized. Cost: the small app-name line reads "Windows PowerShell".
Benefit: it reliably displays everywhere with zero setup. The visible branding (Claude logo +
"Claude Code" title) lives in the toast body, so it's a good trade. To reclaim the top-line name,
register a Start Menu shortcut stamped with a custom AUMID (IPropertyStore interop).

## Known limitations

- Windows only.
- The toast's top-line app name reads "Windows PowerShell" (see the app-identity note above).
- A brief console flash is possible when the hook launches PowerShell, depending on the terminal.
- Stop-hook toasts fire once per turn; tune with `$NotifyOnStop` / `$DebounceSeconds`.
- Script string literals stay ASCII — Windows PowerShell 5.1 reads the no-BOM `.ps1` files as
  ANSI, so non-ASCII in a displayed string would mojibake.
