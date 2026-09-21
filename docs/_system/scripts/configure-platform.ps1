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
    $before = @(Read-OttodocRecord -RepoRoot $repoRoot)
    $target = @(Select-OrderedPlatforms ($before + @($Platform)))
    Write-OttodocRecord -RepoRoot $repoRoot -Platforms $target
    # Only a newly added platform seeds the ignore file: a refresh must not restore a
    # pattern the owner deliberately removed.
    $ignored = @()
    if ($before -notcontains $Platform) {
        $ignored = @(Add-OttodocIgnorePatterns -RepoRoot $repoRoot -Patterns $Script:PlatformAdapters[$Platform]['Ignore'])
    }
    $result = Invoke-PlatformConverge -RepoRoot $repoRoot -SystemRoot $systemRoot
}
catch {
    Write-Output ('PLATFORM CONFIGURATION FAILED: {0}' -f $_.Exception.Message)
    exit 1
}

foreach ($item in $result['drift']) { Write-Output ('CONVERGED: {0}' -f $item) }
foreach ($item in $ignored) { Write-Output ('IGNORED: {0} added to {1}' -f $item, $Script:IgnoreTarget) }
Write-Output ('PLATFORM CONFIGURATION OK [{0}]: configured set is now {1}.' -f $Platform, ($target -join ', '))
exit 0
