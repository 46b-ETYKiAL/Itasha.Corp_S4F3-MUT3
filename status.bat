@echo off
REM Double-click for a read-only diagnostic. No elevation required.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\status.ps1"
echo.
pause
