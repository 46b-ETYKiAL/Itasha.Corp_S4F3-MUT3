@{
    # PSScriptAnalyzer config for S4F3-MUT3.
    # See https://github.com/PowerShell/PSScriptAnalyzer/blob/master/README.md
    Severity = @('Error', 'Warning')

    ExcludeRules = @(
        # Write-Host is intentional throughout - the lifecycle scripts (start/
        # stop/setup/uninstall/status) all run interactively and need to draw
        # status lines with colour. Replacing with Write-Output would break
        # the user-facing transcript. Justified.
        'PSAvoidUsingWriteHost',

        # The IP probe in scripts/start.ps1 deliberately swallows the
        # tailscale.exe stderr noise during NoState transitions; the outer
        # try/finally guarantees the close logic still runs. Justified.
        'PSAvoidUsingEmptyCatchBlock',

        # No advanced functions / cmdlets in this repo - all scripts are
        # script-scoped. Rule does not apply.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
