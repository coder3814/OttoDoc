# Decommissions exactly one agent platform (lifecycle.md: remove). The name is always
# required; removing the last platform is ordinary and leaves the engine installed
# with zero configured platforms.

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
    $remaining = @(Select-OrderedPlatforms (@(Read-OttodocRecord -RepoRoot $repoRoot) | Where-Object { $_ -ne $Platform }))
    Write-OttodocRecord -RepoRoot $repoRoot -Platforms $remaining
    $result = Invoke-PlatformConverge -RepoRoot $repoRoot -SystemRoot $systemRoot
}
catch {
    Write-Output ('PLATFORM REMOVAL FAILED: {0}' -f $_.Exception.Message)
    exit 1
}

foreach ($item in $result['drift']) { Write-Output ('CONVERGED: {0}' -f $item) }
$setDescription = '(none)'
if ($remaining.Count -gt 0) { $setDescription = ($remaining -join ', ') }
Write-Output ('PLATFORM REMOVAL OK [{0}]: configured set is now {1}.' -f $Platform, $setDescription)
exit 0
