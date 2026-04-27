# Quick syntax check for all .ps1 files in the repo.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$files = Get-ChildItem -Path $repo -Recurse -Filter '*.ps1' | Where-Object { $_.Name -ne '_parse_check.ps1' }
$any = $false
foreach ($f in $files) {
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    $rel = $f.FullName.Substring($repo.Length + 1)
    if ($errors -and $errors.Count -gt 0) {
        Write-Host "FAIL: $rel" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "  line $($_.Extent.StartLineNumber):$($_.Extent.StartColumnNumber) - $($_.Message)" -ForegroundColor Red }
        $any = $true
    } else {
        Write-Host "OK:   $rel" -ForegroundColor Green
    }
}
if ($any) { exit 1 } else { exit 0 }
