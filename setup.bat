@echo off
REM Double-click to install/configure the S4F3-MUT3 stack (idempotent).
REM Calls setup.ps1 which self-elevates via UAC.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
