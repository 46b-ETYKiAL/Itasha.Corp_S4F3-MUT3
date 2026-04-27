<#
.SYNOPSIS
    Read-only diagnostic for the S4F3-MUT3 stack.
.DESCRIPTION
    Reports the state of every component setup.ps1 should have wired:
      - Both services + dependency
      - Required files (AdGuardHome.exe, AdGuardHome.yaml, tailscaled-env.txt, tailscale.exe)
      - Hosts file block
      - Windows Firewall rules
      - Start Menu shortcuts
      - Tailnet IP
      - AdGuard web UI reachability

    Some checks read elevation-restricted files (AdGuardHome.yaml,
    tailscaled-env.txt). When run non-elevated those checks report
    "unreadable (run elevated)" rather than failing the whole script.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

function Hdr($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function OK($msg)  { Write-Host "  [ ok ] $msg" -ForegroundColor Green }
function Bad($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Inf($msg) { Write-Host "  [info] $msg" -ForegroundColor DarkGray }

$elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $elevated) { Inf 'running non-elevated - some checks will be skipped' }

# === Services ===
Hdr 'Services'
$tsSvc  = Get-Service -Name Tailscale   -ErrorAction SilentlyContinue
$aghSvc = Get-Service -Name AdGuardHome -ErrorAction SilentlyContinue
if ($tsSvc)  { OK  "Tailscale   - $($tsSvc.Status), StartType=$($tsSvc.StartType)" }
else         { Bad 'Tailscale service not registered' }
if ($aghSvc) { OK  "AdGuardHome - $($aghSvc.Status), StartType=$($aghSvc.StartType)" }
else         { Bad 'AdGuardHome service not registered (run setup.ps1)' }

# === Service dependency ===
Hdr 'Service dependency (cascade-stop wiring)'
if ($aghSvc) {
    $deps = @($aghSvc.RequiredServices | Select-Object -ExpandProperty Name)
    if ($deps -contains 'Tailscale') {
        OK 'AdGuardHome depends on Tailscale - cascade-stop active'
    } else {
        Bad 'AdGuardHome has no dependency on Tailscale - re-run setup.ps1'
    }
} else {
    Inf 'skipped (AdGuardHome service missing)'
}

# === Files ===
Hdr 'Files'
$paths = @(
    'C:\Program Files\Tailscale\tailscale.exe',
    'C:\AdGuardHome\AdGuardHome.exe',
    'C:\AdGuardHome\AdGuardHome.yaml',
    'C:\ProgramData\Tailscale\tailscaled-env.txt'
)
foreach ($p in $paths) {
    try {
        if (Test-Path -LiteralPath $p -ErrorAction Stop) { OK "present: $p" }
        else { Bad "missing: $p" }
    } catch {
        Inf "unreadable (run elevated): $p"
    }
}

# === tailscaled-env.txt content ===
Hdr 'TS_NO_LOGS_NO_SUPPORT env var'
$envFile = 'C:\ProgramData\Tailscale\tailscaled-env.txt'
try {
    $envContent = Get-Content -LiteralPath $envFile -ErrorAction Stop
    if ($envContent -match 'TS_NO_LOGS_NO_SUPPORT=true') { OK 'TS_NO_LOGS_NO_SUPPORT=true present' }
    else { Bad "$envFile exists but TS_NO_LOGS_NO_SUPPORT=true not found" }
} catch {
    Inf 'unreadable (run elevated)'
}

# === AdGuardHome.yaml user_rules ===
Hdr 'AdGuardHome custom filter rule'
$cfgPath = 'C:\AdGuardHome\AdGuardHome.yaml'
try {
    $cfg = Get-Content -LiteralPath $cfgPath -Raw -ErrorAction Stop
    if ($cfg -match '\|\|log\.tailscale\.io\^') { OK '||log.tailscale.io^ present in user_rules' }
    else { Bad 'rule missing - re-run setup.ps1 (or complete the first-run wizard if AdGuardHome.yaml does not exist yet)' }
} catch {
    Inf 'unreadable (run elevated)'
}

# === Hosts file block ===
Hdr 'Hosts file block'
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
try {
    $hosts = Get-Content -LiteralPath $hostsPath -ErrorAction Stop
    if ($hosts -match '^\s*0\.0\.0\.0\s+log\.tailscale\.io') { OK '0.0.0.0 log.tailscale.io present' }
    else { Bad '0.0.0.0 log.tailscale.io entry missing' }
} catch {
    Inf 'unreadable'
}

# === Firewall rules ===
Hdr 'Windows Firewall rules'
foreach ($n in 'AdGuard Home DNS UDP','AdGuard Home DNS TCP','AdGuard Home Web UI') {
    if (Get-NetFirewallRule -DisplayName $n -ErrorAction SilentlyContinue) { OK $n }
    else { Bad "missing rule: $n" }
}

# === Start Menu shortcuts ===
Hdr 'Start Menu shortcuts'
$shortcutDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Tailscale + AdGuard"
foreach ($s in 'Start Tailscale + AdGuard.lnk','Stop Tailscale + AdGuard.lnk') {
    $full = Join-Path $shortcutDir $s
    if (Test-Path -LiteralPath $full) { OK $s }
    else { Bad "missing shortcut: $full" }
}

# === Legacy scheduled tasks (informational) ===
Hdr 'Legacy scheduled tasks (should be absent - superseded by service dependency)'
$legacyTasks = @('AdGuardHome on Tailscale start', 'AdGuardHome off on Tailscale stop')
$anyLegacy = $false
foreach ($t in $legacyTasks) {
    if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
        Inf "still registered: '$t' (harmless; uninstall.ps1 will clean up)"
        $anyLegacy = $true
    }
}
if (-not $anyLegacy) { OK 'no legacy event-trigger tasks present' }

# === Tailnet IP ===
Hdr 'Tailnet'
$tsExe = 'C:\Program Files\Tailscale\tailscale.exe'
if (Test-Path $tsExe) {
    $ip = (& $tsExe ip -4 2>$null | Select-Object -First 1)
    if ($ip) { OK "tailnet IPv4: $ip" }
    else { Bad 'tailscale ip -4 returned nothing (logged out / service stopped?)' }
} else {
    Bad "$tsExe missing"
}

# === AdGuard web UI ===
Hdr 'AdGuard web UI reachability'
# Use raw TCP probe first (more reliable than Invoke-WebRequest, which throws
# .NET "Operation is not valid" on some PS 5.1 / redirect combinations even
# when the port is up).
$tcp = $null
try {
    $client = New-Object System.Net.Sockets.TcpClient
    $async  = $client.BeginConnect('127.0.0.1', 3000, $null, $null)
    $tcp = $async.AsyncWaitHandle.WaitOne(2000, $false) -and $client.Connected
    $client.Close()
} catch { $tcp = $false }

if ($tcp) {
    OK 'http://127.0.0.1:3000/ - port open (AdGuard web UI listening)'
} else {
    Bad 'http://127.0.0.1:3000/ - port closed (AdGuardHome service stopped or web UI not bound)'
}

Write-Host ''
