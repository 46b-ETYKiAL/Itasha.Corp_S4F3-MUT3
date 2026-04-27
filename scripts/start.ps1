<#
.SYNOPSIS
    Start Tailscale + AdGuardHome (S4F3-MUT3 stack).
.DESCRIPTION
    Self-elevates via UAC. Starts both services in dependency order
    (Tailscale first, then AdGuardHome). Waits for each to reach Running
    before continuing. Reports status and pauses for review.

    AdGuardHome is configured to depend on Tailscale by setup.ps1, so
    Start-Service AdGuardHome would also pull Tailscale up - but we
    start them explicitly here so the user sees both transitions.

.PARAMETER NoPause
    Skip the "Press any key" pause at the end. Useful when chaining.
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

# Wrap the entire body in try/finally so the close logic always runs even if
# something throws unexpectedly. Exit forcefully via [Environment]::Exit at
# the end so the PS process terminates immediately - even if a child process
# (e.g. the tray GUI) ever held a stdio handle to our console.
try {

Write-Host '== Start Tailscale + AdGuardHome ==' -ForegroundColor Cyan

foreach ($name in 'Tailscale', 'AdGuardHome') {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Host "  [ERR] service '$name' not registered - run setup.ps1 first" -ForegroundColor Red
        $failed = $true
        continue
    }
    if ($svc.Status -eq 'Running') {
        Write-Host "  [ok ] $name already running" -ForegroundColor DarkGreen
        continue
    }
    Write-Host "  [..] starting $name" -NoNewline -ForegroundColor Yellow
    try {
        Start-Service -Name $name
        $svc.WaitForStatus('Running', $timeout)
        Write-Host " - running" -ForegroundColor Green
    } catch {
        Write-Host " - FAILED" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor Red
        $failed = $true
    }
}

Write-Host ''
Get-Service Tailscale, AdGuardHome -ErrorAction SilentlyContinue |
    Format-Table Name, Status, StartType -AutoSize | Out-String | Write-Host

if (-not $failed) {
    # Launch Tailscale tray GUI via the Task Scheduler service so the new
    # process has NO parent console at all. tailscale-ipn.exe inherits any
    # console its launcher has and logs to it - using Start-Process or
    # WshShell.Run, the tray attaches to our PS console, floods it with log
    # output, AND keeps the conhost window alive after PS exits even with
    # [Environment]::Exit. svchost (Task Scheduler) has no console, so this
    # is fully detached.
    $ipnExe = 'C:\Program Files\Tailscale\tailscale-ipn.exe'
    if ((Test-Path $ipnExe) -and -not (Get-Process tailscale-ipn -ErrorAction SilentlyContinue)) {
        $taskName = '_S4F3MUT3_LaunchTray_OneShot'
        try {
            $action    = New-ScheduledTaskAction -Execute $ipnExe
            $principal = New-ScheduledTaskPrincipal `
                            -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
                            -LogonType Interactive `
                            -RunLevel Limited
            Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
            Start-ScheduledTask -TaskName $taskName
            Start-Sleep -Milliseconds 500
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-Host 'Tailscale tray: launched' -ForegroundColor DarkGreen
        } catch {
            Write-Host "Tailscale tray: launch failed - $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host '             open Tailscale from the Start Menu manually if needed' -ForegroundColor DarkGray
        }
    }

    # Tailnet IP probe with polling. After Start-Service, tailscaled needs
    # several seconds to load persisted auth state and reconnect to the
    # coordination server - it reports "NoState" until then. Poll every
    # 500ms for up to 12 seconds. Also lower $ErrorActionPreference around
    # the native call because tailscale.exe writes to stderr when in
    # NoState, which would otherwise become a terminating NativeCommandError.
    $tsExe = 'C:\Program Files\Tailscale\tailscale.exe'
    if (Test-Path $tsExe) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $ip = $null
        $deadline = (Get-Date).AddSeconds(12)
        Write-Host 'Tailnet: ' -NoNewline -ForegroundColor Cyan
        Write-Host 'waiting for daemon...' -NoNewline -ForegroundColor DarkGray
        while ((Get-Date) -lt $deadline -and -not $ip) {
            try {
                $ipOutput = & $tsExe ip -4 2>$null
                if ($LASTEXITCODE -eq 0 -and $ipOutput) {
                    $ip = ($ipOutput | Select-Object -First 1).ToString().Trim()
                }
            } catch {}
            if (-not $ip) { Start-Sleep -Milliseconds 500; Write-Host '.' -NoNewline -ForegroundColor DarkGray }
        }
        $ErrorActionPreference = $prevEAP
        Write-Host ''
        if ($ip) {
            Write-Host "Tailnet IP: $ip" -ForegroundColor Cyan
        } else {
            Write-Host 'Tailnet: daemon still in NoState after 12s - tray may need a manual reconnect' -ForegroundColor Yellow
        }
    }
    Write-Host 'AdGuard UI: http://localhost:3000' -ForegroundColor Cyan
}

} catch {
    Write-Host ''
    Write-Host "[FATAL] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    $failed = $true
} finally {
    if (-not $NoPause) {
        Write-Host ''
        Write-Host 'Closing in 4 seconds (Ctrl+C to keep open)...' -ForegroundColor DarkGray
        Start-Sleep -Seconds 4
    }
    [Environment]::Exit($(if ($failed) { 1 } else { 0 }))
}
