# Decommissions exactly one agent platform. Leaves every other platform, the engine,
# and the knowledge tree untouched.
# Part of the engine (constitution section 9): changed only on the repository owner's explicit request.
# Compatible with Windows PowerShell 5.1 and pwsh.
#
#   remove-platform.ps1 -Platform Claude
#
# -Platform is always required. There is no default and no escalation: removing the only
# configured platform is allowed and leaves OttoDoc installed with zero configured
# platforms, which is an ordinary state - the engine is still on disk, CI still runs, and
# a platform is restored by configuring one again.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Claude', 'Codex', 'Cursor')]
    [string]$Platform
)

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Get-RepoRoot
$systemRoot = Get-SystemRoot

$configured = @(Get-ConfiguredPlatforms -RepoRoot $repoRoot)
$remaining = @(Select-OrderedPlatforms (@($configured) | Where-Object { $_ -ne $Platform }))

try {
    $result = Remove-PlatformFiles -RepoRoot $repoRoot -SystemRoot $systemRoot -Platform $Platform

    $workflowPath = Join-Path $repoRoot $Script:WorkflowTarget
    $workflowDirectory = Split-Path -Parent $workflowPath
    if (-not (Test-Path -LiteralPath $workflowDirectory)) {
        New-Item -ItemType Directory -Path $workflowDirectory -Force | Out-Null
    }
    Write-Utf8LfFile -Path $workflowPath -Content (Get-GeneratedWorkflow -SystemRoot $systemRoot -Platforms $remaining)
}
catch {
    Write-Output ('PLATFORM REMOVAL FAILED: {0}' -f $_.Exception.Message)
    exit 1
}

foreach ($item in $result['removed']) { Write-Output ('REMOVED [{0}]: {1}' -f $Platform, $item) }
foreach ($item in $result['skipped']) { Write-Output ('SKIPPED: {0}' -f $item) }
Write-Output ('UPDATED: {0}' -f $Script:WorkflowTarget)

if (-not ($configured -contains $Platform)) {
    Write-Output ('NOTE: {0} was not in the configured set; any of its files found on disk were orphans and have been swept.' -f $Platform)
}

$setDescription = '(none)'
if ($remaining.Count -gt 0) { $setDescription = ($remaining -join ', ') }
Write-Output ('PLATFORM REMOVAL OK [{0}]: configured set is now {1}.' -f $Platform, $setDescription)

if ($result['skipped'].Count -gt 0) {
    Write-Output 'Files listed as SKIPPED sit at OttoDoc paths but do not match the canonical engine, so OttoDoc did not write them and will not delete them. Remove them by hand if they are unwanted.'
}
exit 0
