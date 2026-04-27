<#
.SYNOPSIS
    Stop Tailscale + AdGuardHome (S4F3-MUT3 stack).
.DESCRIPTION
    Self-elevates via UAC. Stops both services in reverse dependency order
    (AdGuardHome first, then Tailscale). With the service dependency wired
    by setup.ps1, Stop-Service Tailscale -Force would cascade-stop
    AdGuardHome on its own - we stop them explicitly so the transitions
    are visible.

.PARAMETER NoPause
    Skip the "Press any key" pause at the end.
#>
[CmdletBinding()]
param(
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'

# === Self-elevate ===
$current = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    ) -Wait
    exit
}

$timeout = New-TimeSpan -Seconds 30
$failed = $false

# Wrap in try/finally so the close logic always runs and PS exits forcefully.
try {

Write-Host '== Stop Tailscale + AdGuardHome ==' -ForegroundColor Cyan

foreach ($name in 'AdGuardHome', 'Tailscale') {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Host "  [skip] service '$name' not registered" -ForegroundColor DarkGray
        continue
    }
    if ($svc.Status -eq 'Stopped') {
        Write-Host "  [ok ] $name already stopped" -ForegroundColor DarkGreen
        continue
    }
    Write-Host "  [..] stopping $name" -NoNewline -ForegroundColor Yellow
    try {
        Stop-Service -Name $name -Force
        $svc.WaitForStatus('Stopped', $timeout)
        Write-Host " - stopped" -ForegroundColor Green
    } catch {
        Write-Host " - FAILED" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor Red
        $failed = $true
    }
}

# Close the Tailscale tray GUI (separate user-mode process from the daemon).
# Without this, the icon would linger in the system tray showing "disconnected".
$ipn = Get-Process tailscale-ipn -ErrorAction SilentlyContinue
if ($ipn) {
    Write-Host '  [..] closing Tailscale tray GUI' -NoNewline -ForegroundColor Yellow
    try {
        $ipn | Stop-Process -Force
        Write-Host ' - closed' -ForegroundColor Green
    } catch {
        Write-Host ' - FAILED' -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host '  [ok ] Tailscale tray GUI not running' -ForegroundColor DarkGreen
}

Write-Host ''
Get-Service Tailscale, AdGuardHome -ErrorAction SilentlyContinue |
    Format-Table Name, Status, StartType -AutoSize | Out-String | Write-Host

} catch {
    Write-Host ''
    Write-Host "[FATAL] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    $failed = $true
} finally {
    if (-not $NoPause) {
        Write-Host 'Closing in 4 seconds (Ctrl+C to keep open)...' -ForegroundColor DarkGray
        Start-Sleep -Seconds 4
    }
    [Environment]::Exit($(if ($failed) { 1 } else { 0 }))
}
