@echo off
REM Double-click to uninstall the S4F3-MUT3 stack (reverses setup).
REM Calls scripts\uninstall.ps1 which self-elevates via UAC.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\uninstall.ps1"
