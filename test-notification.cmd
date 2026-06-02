@echo off
echo Testing ClaudeCodeNotifyBeacon...
echo.
echo 1. Checking daemon...
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { $_.CommandLine -like '*notify-daemon*' -and $_.CommandLine -notlike '*-Command*' } | ForEach-Object { Write-Host \"   Daemon running: PID $($_.ProcessId)\" }"
echo.
echo 2. Triggering notification...
powershell -NoProfile -ExecutionPolicy Bypass -Command "& 'C:\Users\27650\ClaudeCodeNotifyBeacon\notify.ps1' -Message 'Test notification'"
echo.
echo 3. Check bottom-right corner for toast notification.
echo    (If terminal has focus, Alt+Tab away first)
echo.
pause
