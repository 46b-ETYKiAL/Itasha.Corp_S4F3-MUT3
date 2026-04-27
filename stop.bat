@echo off
REM Double-click to stop Tailscale + AdGuardHome.
REM Calls scripts\stop.ps1 which self-elevates via UAC.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\stop.ps1"
