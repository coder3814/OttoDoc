# Verifies the installation against the record without writing (lifecycle.md: check).
# Thin wrapper around converge -Check; exits nonzero on any drift.

[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'platforms.ps1')

try {
    $result = Invoke-PlatformConverge -RepoRoot (Get-RepoRoot) -SystemRoot (Get-SystemRoot) -Check
}
catch {
    Write-Output ('ADAPTER CHECK FAILED: {0}' -f $_.Exception.Message)
    exit 1
}

$setDescription = '(none)'
if (@($result['configured']).Count -gt 0) { $setDescription = (@($result['configured']) -join ', ') }

if (@($result['drift']).Count -gt 0) {
    foreach ($item in $result['drift']) { Write-Output $item }
    Write-Output ('ADAPTER CHECK FAILED [{0}]: {1} difference(s) from the recorded configuration. Run configure-platform.ps1 or remove-platform.ps1 to converge.' -f $setDescription, @($result['drift']).Count)
    exit 1
}

Write-Output ('ADAPTER CHECK OK [{0}]: every generated file matches docs/_system and the record.' -f $setDescription)
exit 0
