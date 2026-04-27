@echo off
REM Double-click to start Tailscale + AdGuardHome.
REM Calls scripts\start.ps1 which self-elevates via UAC.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start.ps1"
