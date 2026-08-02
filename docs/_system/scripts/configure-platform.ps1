# Adds one explicitly requested agent platform to the record, or refreshes it
# (lifecycle.md: configure). Additive: adding one platform never removes another.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Claude', 'Codex', 'Cursor')]
    [string]$Platform
)

. (Join-Path $PSScriptRoot 'platforms.ps1')

$repoRoot = Get-RepoRoot
$systemRoot = Get-SystemRoot

try {
    $target = @(Select-OrderedPlatforms (@(Read-OttodocRecord -RepoRoot $repoRoot) + @($Platform)))
    Write-OttodocRecord -RepoRoot $repoRoot -Platforms $target
    $result = Invoke-PlatformConverge -RepoRoot $repoRoot -SystemRoot $systemRoot
}
catch {
    Write-Output ('PLATFORM CONFIGURATION FAILED: {0}' -f $_.Exception.Message)
    exit 1
}

foreach ($item in $result['drift']) { Write-Output ('CONVERGED: {0}' -f $item) }
Write-Output ('PLATFORM CONFIGURATION OK [{0}]: configured set is now {1}.' -f $Platform, ($target -join ', '))
exit 0
