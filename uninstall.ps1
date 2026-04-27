<#
.SYNOPSIS
    S4F3-MUT3 uninstaller - reverses everything setup.ps1 created.
.DESCRIPTION
    Self-elevates if not already admin. Idempotent.

    Removes:
      - Start Menu shortcuts (Tailscale + AdGuard folder)
      - Scheduled tasks (AdGuardHome on/off Tailscale start/stop)
      - Windows Firewall rules for AdGuardHome.exe
      - AdGuardHome service + C:\AdGuardHome\
      - Hosts file entries
      - C:\ProgramData\Tailscale\tailscaled-env.txt

    Restores:
      - AdGuardHome service: removed entirely
      - Tailscale service: StartType -> Automatic
      - Tailscale: accept-dns -> true

    Manual steps (web UI only):
      - Tailscale admin console: remove the custom nameserver added at install time,
        disable Override DNS
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$current = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Re-launching elevated...' -ForegroundColor Yellow
    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
    ) -Wait
    exit
}

function Step($msg) { Write-Host "`n[STEP] $msg" -ForegroundColor Cyan }
function OK($msg)   { Write-Host "  [ok] $msg" -ForegroundColor Green }
function Skip($msg) { Write-Host "  [skip] $msg" -ForegroundColor DarkGray }

# === Start Menu shortcuts ===
Step 'Removing Start Menu shortcuts'
$invokingUser = (Get-CimInstance -ClassName Win32_ComputerSystem).UserName
$invokingProfile = $null
if ($invokingUser -and ($invokingUser -split '\\')[1]) {
    $invokingProfile = (Get-CimInstance -ClassName Win32_UserProfile -Filter "Loaded='True'" |
        Where-Object { (Split-Path $_.LocalPath -Leaf) -eq ($invokingUser -split '\\')[1] }).LocalPath
}
if ($invokingProfile) {
    $dir = Join-Path $invokingProfile 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Tailscale + AdGuard'
    if (Test-Path $dir) {
        Remove-Item -Path $dir -Recurse -Force
        OK "removed $dir"
    } else {
        Skip 'no shortcut folder'
    }
}

# === Scheduled tasks ===
Step 'Removing scheduled tasks'
foreach ($task in @('AdGuardHome on Tailscale start', 'AdGuardHome off on Tailscale stop')) {
    if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $task -Confirm:$false
        OK "removed task '$task'"
    } else {
        Skip "task '$task' not present"
    }
}

# === AdGuard service + install dir ===
Step 'Removing AdGuard Home'
$aghExe = 'C:\AdGuardHome\AdGuardHome.exe'
if (Get-Service -Name AdGuardHome -ErrorAction SilentlyContinue) {
    # Clear service dependency first so cascade-stop does not fight the uninstall
    sc.exe config AdGuardHome depend= / | Out-Null
    Stop-Service -Name AdGuardHome -Force -ErrorAction SilentlyContinue
    if (Test-Path $aghExe) {
        & $aghExe -s uninstall 2>&1 | Out-Null
        OK 'service uninstalled'
    } else {
        sc.exe delete AdGuardHome | Out-Null
        OK 'service registration deleted'
    }
}
if (Test-Path 'C:\AdGuardHome') {
    Remove-Item 'C:\AdGuardHome' -Recurse -Force
    OK 'C:\AdGuardHome removed'
}

# === Firewall rules ===
Step 'Removing Windows Firewall rules'
foreach ($name in @('AdGuard Home DNS UDP', 'AdGuard Home DNS TCP', 'AdGuard Home Web UI')) {
    if (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue) {
        Remove-NetFirewallRule -DisplayName $name
        OK "removed '$name'"
    } else {
        Skip "rule '$name' not present"
    }
}

# === Hosts file ===
Step 'Cleaning hosts file'
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$hosts = Get-Content $hostsPath
$filtered = @()
$skipUntilBlank = $false
foreach ($line in $hosts) {
    if ($line -match '# Block Tailscale telemetry') { $skipUntilBlank = $true; continue }
    if ($skipUntilBlank) {
        if ($line -match 'log\.tailscale\.io') { continue }
        $skipUntilBlank = $false
    }
    $filtered += $line
}
$filtered | Set-Content -Path $hostsPath -Encoding ASCII
OK 'hosts file cleaned'

# === Tailscale env var ===
Step 'Restoring Tailscale log uploads'
$tsEnv = 'C:\ProgramData\Tailscale\tailscaled-env.txt'
if (Test-Path $tsEnv) {
    Remove-Item $tsEnv -Force
    Restart-Service Tailscale -Force -ErrorAction SilentlyContinue
    OK "$tsEnv removed, Tailscale restarted"
} else {
    Skip 'env file not present'
}

# === Tailscale service to Automatic + accept-dns true ===
Step 'Restoring Tailscale service config'
sc.exe config Tailscale start= auto | Out-Null
OK 'Tailscale -> Automatic'

$tsExe = 'C:\Program Files\Tailscale\tailscale.exe'
if (Test-Path $tsExe) {
    & $tsExe set --accept-dns=true 2>&1 | Out-Null
    OK 'accept-dns=true set'
}

Write-Host "`n=== Uninstall complete ===" -ForegroundColor Green
Write-Host ''
Write-Host 'Manual cleanup remaining (web UI only):'
Write-Host '  Tailscale admin console: https://login.tailscale.com/admin/dns'
Write-Host '    - Remove the custom nameserver you added at install time'
Write-Host '    - Toggle Override DNS servers OFF'
Write-Host ''
Write-Host 'Press any key to exit...'
[Console]::ReadKey() | Out-Null
