<#
.SYNOPSIS
    S4F3-MUT3 — mutes log.tailscale.io telemetry on Windows via TS_NO_LOGS_NO_SUPPORT,
    hosts file, and AdGuard Home for tailnet-wide enforcement (Android too).
.DESCRIPTION
    Idempotent — safe to re-run. Self-elevates if not already admin.

    What it does:
      1. Installs AdGuard Home v0.107.74 to C:\AdGuardHome (if missing)
      2. Writes TS_NO_LOGS_NO_SUPPORT=true to C:\ProgramData\Tailscale\tailscaled-env.txt
      3. Adds 0.0.0.0 / ::0 log.tailscale.io entries to the Windows hosts file
      4. Adds Windows Firewall inbound rules for AdGuardHome.exe (UDP 53, TCP 53, TCP 3000)
      5. Inserts ||log.tailscale.io^ into AdGuardHome.yaml user_rules
      6. Sets AdGuardHome and Tailscale services to Manual start
      7. Runs `tailscale set --accept-dns=false` (works around Windows WFP DNS interception)
      8. Creates two scheduled tasks that mirror AdGuard to Tailscale's service state
      9. Creates Start Menu shortcuts under "Tailscale + AdGuard"

    What it does NOT do (web UI only):
      - Tailscale admin console DNS: add this machine's tailnet IPv4 as nameserver,
        Override DNS, MagicDNS on (script auto-detects and prints the IP at the end)
      - AdGuard Home initial setup wizard at http://localhost:3000

    See README.md for full context.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# === Self-elevate ===
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
function Warn($msg) { Write-Host "  [warn] $msg" -ForegroundColor Yellow }

# === 1. AdGuard Home install ===
Step 'AdGuard Home install'
$aghPath = 'C:\AdGuardHome'
$aghExe  = Join-Path $aghPath 'AdGuardHome.exe'
if (-not (Test-Path $aghExe)) {
    $version  = 'v0.107.74'
    $expected = 'c7c892e8734d3968d61506f4a3add612513c4779f157b7eb7453fb924ca2e7c8'
    $url      = "https://github.com/AdguardTeam/AdGuardHome/releases/download/$version/AdGuardHome_windows_amd64.zip"
    $tmpZip   = Join-Path $env:TEMP 'AdGuardHome_windows_amd64.zip'
    $tmpDir   = Join-Path $env:TEMP 'AdGuardHome_extract'

    Write-Host "  downloading $version..."
    Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing
    $sha = (Get-FileHash -Algorithm SHA256 -Path $tmpZip).Hash.ToLower()
    if ($sha -ne $expected) {
        throw "SHA256 mismatch. Expected $expected, got $sha"
    }
    OK "SHA256 verified: $sha"

    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
    Move-Item -Path (Join-Path $tmpDir 'AdGuardHome') -Destination $aghPath
    Remove-Item $tmpZip, $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

    & $aghExe -s install | Out-Null
    OK 'service installed'
} else {
    Skip "C:\AdGuardHome already exists"
}

# === 2. TS_NO_LOGS_NO_SUPPORT ===
Step 'Disable Tailscale client log uploads'
$tsEnv = 'C:\ProgramData\Tailscale\tailscaled-env.txt'
if (-not (Test-Path $tsEnv) -or -not ((Get-Content $tsEnv -ErrorAction SilentlyContinue) -match 'TS_NO_LOGS_NO_SUPPORT=true')) {
    Stop-Service Tailscale -Force -ErrorAction SilentlyContinue
    New-Item -Path $tsEnv -ItemType File -Force | Out-Null
    Set-Content -Path $tsEnv -Value 'TS_NO_LOGS_NO_SUPPORT=true' -Encoding ASCII
    Start-Service Tailscale
    Start-Sleep -Seconds 3
    OK 'TS_NO_LOGS_NO_SUPPORT=true written, service restarted'
} else {
    Skip 'env var already set'
}

# === 3. Hosts file ===
Step 'Hosts file entries'
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$hostsContent = Get-Content $hostsPath -Raw
if ($hostsContent -notmatch 'Block Tailscale telemetry') {
    Add-Content -Path $hostsPath -Value @"

# Block Tailscale telemetry
0.0.0.0 log.tailscale.io
::0 log.tailscale.io
"@
    OK 'hosts entries added'
} else {
    Skip 'hosts entries already present'
}

# === 4. Windows Firewall rules ===
Step 'Windows Firewall rules for AdGuardHome.exe'
$rules = @(
    @{ Name = 'AdGuard Home DNS UDP'; Protocol = 'UDP'; Port = 53 }
    @{ Name = 'AdGuard Home DNS TCP'; Protocol = 'TCP'; Port = 53 }
    @{ Name = 'AdGuard Home Web UI';  Protocol = 'TCP'; Port = 3000 }
)
foreach ($r in $rules) {
    if (Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue) {
        Skip "rule '$($r.Name)' exists"
    } else {
        New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -Action Allow `
            -Protocol $r.Protocol -LocalPort $r.Port -Program $aghExe -Profile Any | Out-Null
        OK "rule '$($r.Name)' created"
    }
}

# === 5. AdGuard user_rules ===
Step 'AdGuard custom filter rule'
$cfgPath = Join-Path $aghPath 'AdGuardHome.yaml'
if (Test-Path $cfgPath) {
    $cfg = Get-Content $cfgPath -Raw
    if ($cfg -match "(?ms)user_rules:\s*\r?\n  - '\|\|log\.tailscale\.io\^'") {
        Skip 'rule already in AdGuardHome.yaml'
    } else {
        Stop-Service AdGuardHome -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $lines = Get-Content $cfgPath
        $out = New-Object System.Collections.Generic.List[string]
        $inUserRules = $false
        $found = $false
        foreach ($line in $lines) {
            if ($line -match '^user_rules:') {
                $out.Add('user_rules:')
                $out.Add("  - '||log.tailscale.io^'")
                $inUserRules = $true
                $found = $true
                continue
            }
            if ($inUserRules) {
                if ($line -match '^  - ') { continue }
                $inUserRules = $false
            }
            $out.Add($line)
        }
        if (-not $found) {
            $out.Add('user_rules:')
            $out.Add("  - '||log.tailscale.io^'")
        }
        $out -join "`n" | Set-Content -Path $cfgPath -Encoding ASCII -NoNewline
        Start-Service AdGuardHome
        Start-Sleep -Seconds 3
        OK 'rule inserted, service restarted'
    }
} else {
    Warn 'AdGuardHome.yaml not found yet — complete first-run setup at http://localhost:3000 then re-run this script'
}

# === 6. Service start types → Manual ===
Step 'Service start types → Manual'
foreach ($s in @('AdGuardHome', 'Tailscale')) {
    $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
    if (-not $svc) { Warn "$s service not found"; continue }
    if ($svc.StartType -ne 'Manual') {
        sc.exe config $s start= demand | Out-Null
        OK "$s → Manual"
    } else {
        Skip "$s already Manual"
    }
}

# === 7. Tailscale --accept-dns=false ===
Step 'Tailscale: accept-dns=false (workaround for Windows WFP)'
$tsExe = 'C:\Program Files\Tailscale\tailscale.exe'
if (Test-Path $tsExe) {
    & $tsExe set --accept-dns=false 2>&1 | Out-Null
    OK 'accept-dns=false set'
} else {
    Warn 'tailscale.exe not found at standard path'
}

# === 8. Scheduled tasks ===
Step 'Scheduled tasks (mirror AdGuard to Tailscale state)'
function New-EventTrigger {
    param([string]$Subscription)
    $class = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
    $t = New-CimInstance -CimClass $class -ClientOnly
    $t.Enabled = $true
    $t.Subscription = $Subscription
    return $t
}
$subRunning = "<QueryList><Query Id='0' Path='System'><Select Path='System'>*[System[Provider[@Name='Service Control Manager'] and (EventID=7036)]] and *[EventData[Data[@Name='param1']='Tailscale' and Data[@Name='param2']='running']]</Select></Query></QueryList>"
$subStopped = "<QueryList><Query Id='0' Path='System'><Select Path='System'>*[System[Provider[@Name='Service Control Manager'] and (EventID=7036)]] and *[EventData[Data[@Name='param1']='Tailscale' and Data[@Name='param2']='stopped']]</Select></Query></QueryList>"
$principal  = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest -LogonType ServiceAccount
$settings   = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

Unregister-ScheduledTask -TaskName 'AdGuardHome on Tailscale start' -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'AdGuardHome off on Tailscale stop' -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask `
    -TaskName 'AdGuardHome on Tailscale start' `
    -Description 'Auto-starts AdGuardHome when the Tailscale service enters running state.' `
    -Trigger (New-EventTrigger -Subscription $subRunning) `
    -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -Command "Start-Service AdGuardHome"') `
    -Principal $principal -Settings $settings | Out-Null
OK "task 'AdGuardHome on Tailscale start' registered"

Register-ScheduledTask `
    -TaskName 'AdGuardHome off on Tailscale stop' `
    -Description 'Auto-stops AdGuardHome when the Tailscale service enters stopped state.' `
    -Trigger (New-EventTrigger -Subscription $subStopped) `
    -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -Command "Stop-Service AdGuardHome -Force"') `
    -Principal $principal -Settings $settings | Out-Null
OK "task 'AdGuardHome off on Tailscale stop' registered"

# === 9. Start Menu shortcuts (per-user) ===
Step 'Start Menu shortcuts'
$shortcutDir = Join-Path ([Environment]::GetFolderPath('Programs')) 'Tailscale + AdGuard'
# Programs folder above is the elevated SYSTEM user's. We want the invoking user's.
$invokingUser = (Get-CimInstance -ClassName Win32_ComputerSystem).UserName
if ($invokingUser -and ($invokingUser -split '\\')[1]) {
    $invokingProfile = (Get-CimInstance -ClassName Win32_UserProfile -Filter "Loaded='True'" |
        Where-Object { (Split-Path $_.LocalPath -Leaf) -eq ($invokingUser -split '\\')[1] }).LocalPath
    if ($invokingProfile) {
        $shortcutDir = Join-Path $invokingProfile 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Tailscale + AdGuard'
    }
}
New-Item -ItemType Directory -Path $shortcutDir -Force | Out-Null

$shell = New-Object -ComObject WScript.Shell

$start = $shell.CreateShortcut((Join-Path $shortcutDir 'Start Tailscale + AdGuard.lnk'))
$start.TargetPath  = 'powershell.exe'
$start.Arguments   = '-NoProfile -WindowStyle Hidden -Command "Start-Process cmd.exe -Verb RunAs -ArgumentList ''/c'',''net start Tailscale'' -Wait"'
$start.IconLocation = "$aghExe,0"
$start.Description = 'Starts the Tailscale service. AdGuard Home auto-follows via scheduled task.'
$start.WindowStyle = 7
$start.Save()

$stop = $shell.CreateShortcut((Join-Path $shortcutDir 'Stop Tailscale + AdGuard.lnk'))
$stop.TargetPath  = 'powershell.exe'
$stop.Arguments   = '-NoProfile -WindowStyle Hidden -Command "Start-Process cmd.exe -Verb RunAs -ArgumentList ''/c'',''net stop Tailscale'' -Wait"'
$stop.IconLocation = "$aghExe,0"
$stop.Description = 'Stops the Tailscale service. AdGuard Home auto-follows via scheduled task.'
$stop.WindowStyle = 7
$stop.Save()
OK "shortcuts created in $shortcutDir"

# === Done ===
Write-Host "`n=== Setup complete ===" -ForegroundColor Green
Write-Host "Press Win key, type 'Tailscale' — both shortcuts should appear."
Write-Host ''

# Detect this machine's tailnet IP for the user-facing instructions
$tailnetIp = $null
if (Test-Path $tsExe) {
    $tailnetIp = (& $tsExe ip -4 2>$null | Select-Object -First 1).Trim()
}
if (-not $tailnetIp) { $tailnetIp = '<this machine''s tailnet IP — run `tailscale ip -4`>' }

Write-Host 'Web-UI steps (only YOU can do these — see README.md):'
Write-Host '  1. AdGuard Home wizard at http://localhost:3000 (first-run only)'
Write-Host '  2. Tailscale admin console: https://login.tailscale.com/admin/dns'
Write-Host "     - Add nameserver $tailnetIp (Custom)"
Write-Host '     - Toggle Override DNS servers ON'
Write-Host '     - Toggle MagicDNS ON'
Write-Host ''
Write-Host 'Press any key to exit...'
[Console]::ReadKey() | Out-Null
