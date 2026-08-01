# Adds one explicitly requested agent platform to the configured set, or refreshes it.
# Part of the engine (constitution section 9): changed only on the repository owner's explicit request.
# Compatible with Windows PowerShell 5.1 and pwsh.
#
#   configure-platform.ps1 -Platform Claude
#   configure-platform.ps1 -Platform Codex
#   configure-platform.ps1 -Platform Cursor
#
# Additive by design: adding one platform never removes another. Every platform in the
# resulting set is written, so the workflow's record of that set and the files on disk
# cannot disagree. Removal is remove-platform.ps1; verification is check-adapters.ps1.

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
    # Orphans are warnings here for the same reason upgrade treats them that way: the
    # only callers of this switch are bootstrap and upgrade copies already installed in
    # the field, verifying work they just did. An orphan is neither theirs nor
    # resolvable without guessing, and failing on one would roll a transition upgrade
    # back and strand the repository on the old engine. CI calls check-adapters.ps1
    # directly and without the switch, so orphans still fail the build.
    & (Join-Path $PSScriptRoot 'check-adapters.ps1') -WarnOnOrphans
    exit $LASTEXITCODE
}

$repoRoot = Get-RepoRoot
$systemRoot = Get-SystemRoot

$configured = @(Get-ConfiguredPlatforms -RepoRoot $repoRoot)
$target = @(Select-OrderedPlatforms (@($configured) + @($Platform)))

$written = @()
$replaced = @()

try {
    # Every platform in the resulting set is written, not only the newly named one. The
    # workflow records that set and check-adapters holds the installation to it, so a
    # platform named in the record whose files are absent or stale is a broken
    # installation that fails its own check. Writing the whole set keeps record and
    # reality in step; for platforms that were already correct the write is a no-op.
    foreach ($current in $target) {
        $owned = Get-PlatformOwnedPaths $current
        foreach ($sourceRelative in $owned.Keys) {
            $targetRelative = $owned[$sourceRelative]
            $targetPath = Join-Path $repoRoot $targetRelative
            $expected = Get-CanonicalAdapter -SystemRoot $systemRoot -SourceRelative $sourceRelative

            # Configuring a platform is an explicit instruction to install its adapters at
            # OttoDoc's own paths, so a differing file there is replaced rather than
            # refused - that is also what makes refresh during upgrade work, where every
            # installed adapter is stale against new canon by definition. The replacement
            # is reported and left as an uncommitted diff; git is the undo.
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

        $blockTarget = Get-PlatformBlockTarget $current
        if ($blockTarget -eq '') { continue }

        $blockPath = Join-Path $repoRoot $blockTarget
        $block = Get-CanonicalAdapter -SystemRoot $systemRoot -SourceRelative (Get-PlatformBlockSource $current)
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

foreach ($item in $written) { Write-Output ('CONFIGURED: {0}' -f $item) }
foreach ($item in $replaced) { Write-Output ('REPLACED: {0} did not match canon and was regenerated.' -f $item) }
Write-Output ('PLATFORM CONFIGURATION OK [{0}]: configured set is now {1}.' -f $Platform, ($target -join ', '))
exit 0
