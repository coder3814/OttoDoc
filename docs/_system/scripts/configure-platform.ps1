# Adds one explicitly requested agent platform to the configured set, or refreshes it.
# Part of the engine (constitution section 9): changed only on the repository owner's explicit request.
# Compatible with Windows PowerShell 5.1 and pwsh.
#
#   configure-platform.ps1 -Platform Claude
#   configure-platform.ps1 -Platform Codex
#   configure-platform.ps1 -Platform Cursor
#
# Additive by design: platforms already configured are left exactly as they are.
# Removal is remove-platform.ps1; verification is check-adapters.ps1.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Claude', 'Codex', 'Cursor')]
    [string]$Platform,

    # Deprecated compatibility shim. Verification moved to check-adapters.ps1, which
    # takes no arguments because its scope is installed state rather than a caller's
    # choice. This switch survives only because upgrade.ps1 and bootstrap.ps1 copies
    # already installed in the field call it, and an upgrade that fails here rolls back
    # and strands the installation on the old engine. Removable once those have moved.
    [switch]$Check
)

. (Join-Path $PSScriptRoot 'common.ps1')

if ($Check) {
    & (Join-Path $PSScriptRoot 'check-adapters.ps1')
    exit $LASTEXITCODE
}

$repoRoot = Get-RepoRoot
$systemRoot = Get-SystemRoot

$configured = @(Get-ConfiguredPlatforms -RepoRoot $repoRoot)
$target = @(Select-OrderedPlatforms (@($configured) + @($Platform)))

$written = @()
$replaced = @()

try {
    $owned = Get-PlatformOwnedPaths $Platform
    foreach ($sourceRelative in $owned.Keys) {
        $targetRelative = $owned[$sourceRelative]
        $targetPath = Join-Path $repoRoot $targetRelative
        $expected = Get-CanonicalAdapter -SystemRoot $systemRoot -SourceRelative $sourceRelative

        # Configuring a platform is an explicit instruction to install its adapters at
        # OttoDoc's own paths, so a differing file there is replaced rather than refused -
        # that is also what makes refresh during upgrade work, where every installed
        # adapter is stale against new canon by definition. The replacement is reported
        # and left as an uncommitted diff; git is the undo.
        if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
            $actual = [System.IO.File]::ReadAllText($targetPath)
            if (-not (Compare-NormalizedContent $expected $actual)) { $replaced += $targetRelative }
        }

        $targetDirectory = Split-Path -Parent $targetPath
        if (-not (Test-Path -LiteralPath $targetDirectory)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }
        Write-Utf8LfFile -Path $targetPath -Content $expected
        $written += $targetRelative
    }

    $blockTarget = Get-PlatformBlockTarget $Platform
    if ($blockTarget -ne '') {
        $blockPath = Join-Path $repoRoot $blockTarget
        $block = Get-CanonicalAdapter -SystemRoot $systemRoot -SourceRelative (Get-PlatformBlockSource $Platform)
        $style = Get-SharedFileStyle -Path $blockPath
        $existing = ''
        if (Test-Path -LiteralPath $blockPath -PathType Leaf) {
            $existing = Remove-LegacyWholeFileAdapter -Content ([System.IO.File]::ReadAllText($blockPath))
        }
        Write-SharedFile -Path $blockPath -Content (Set-OttodocBlock -Content $existing -Block $block) -Style $style
        $written += ('{0} (OttoDoc block only)' -f $blockTarget)
    }

    $workflowPath = Join-Path $repoRoot $Script:WorkflowTarget
    $workflowDirectory = Split-Path -Parent $workflowPath
    if (-not (Test-Path -LiteralPath $workflowDirectory)) {
        New-Item -ItemType Directory -Path $workflowDirectory -Force | Out-Null
    }
    Write-Utf8LfFile -Path $workflowPath -Content (Get-GeneratedWorkflow -SystemRoot $systemRoot -Platforms $target)
    $written += $Script:WorkflowTarget
}
catch {
    Write-Output ('PLATFORM CONFIGURATION FAILED: {0}' -f $_.Exception.Message)
    exit 1
}

foreach ($item in $written) { Write-Output ('CONFIGURED [{0}]: {1}' -f $Platform, $item) }
foreach ($item in $replaced) { Write-Output ('REPLACED: {0} did not match canon and was regenerated.' -f $item) }
Write-Output ('PLATFORM CONFIGURATION OK [{0}]: configured set is now {1}.' -f $Platform, ($target -join ', '))
exit 0
