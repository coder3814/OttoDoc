# Verifies every installed agent-platform adapter against the canonical engine.
# Part of the engine (constitution section 9): changed only on the repository owner's explicit request.
# Compatible with Windows PowerShell 5.1 and pwsh.
#
#   check-adapters.ps1
#   check-adapters.ps1 -WarnOnOrphans
#
# Takes no platform argument on purpose. The invariant it enforces is a single statement -
# every adapter file on disk belongs to a configured platform and matches canon - and
# its scope is defined by installed state rather than by a caller. That is also what
# makes the zero-platform case ordinary rather than special: with nothing configured,
# every adapter file on disk is an orphan by the same rule, with no branch for it.

[CmdletBinding()]
param(
    # Report adapters belonging to no configured platform without failing on them.
    #
    # Only upgrade passes this. An orphan is pre-existing state that upgrade did not
    # create and cannot resolve without guessing which platforms the owner wants, which
    # section 9 forbids - and failing on it would roll the upgrade back and strand the
    # repository on the old engine permanently. Repositories that hit the pre-additive
    # `configure` bug, which wrote a second platform's adapters and then failed before
    # recording it, are exactly the ones in this state and exactly the ones needing the
    # upgrade most. CI never passes this switch, so the orphan still fails the build; the
    # owner just gets to choose between configuring that platform and removing it.
    [switch]$WarnOnOrphans
)

. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Get-RepoRoot
$systemRoot = Get-SystemRoot

# The only throwing failure here is a canonical source missing from docs/_system/, which
# means the engine itself is broken rather than the installation drifting. CI runs this
# script, so report it in one line instead of a stack trace.
trap {
    Write-Output ('ADAPTER CHECK FAILED: {0}' -f $_.Exception.Message)
    Write-Output 'The installed engine under docs/_system/ is incomplete. Run OttoDoc upgrade to restore it.'
    exit 1
}

$findings = New-Object System.Collections.Generic.List[string]
$orphans = New-Object System.Collections.Generic.List[string]
$verified = 0

$configured = @(Get-ConfiguredPlatforms -RepoRoot $repoRoot)

# --- The generated workflow, which is also the record of the configured set ---
$workflowPath = Join-Path $repoRoot $Script:WorkflowTarget
if (-not (Test-Path -LiteralPath $workflowPath -PathType Leaf)) {
    $findings.Add(('{0}: missing' -f $Script:WorkflowTarget))
}
else {
    $expectedWorkflow = Get-GeneratedWorkflow -SystemRoot $systemRoot -Platforms $configured
    if (-not (Compare-NormalizedContent $expectedWorkflow ([System.IO.File]::ReadAllText($workflowPath)))) {
        $findings.Add(('{0}: stale' -f $Script:WorkflowTarget))
    }
    else { $verified++ }
}

foreach ($platform in $Script:SupportedPlatforms) {
    $isConfigured = ($configured -contains $platform)
    $owned = Get-PlatformOwnedPaths $platform

    foreach ($sourceRelative in $owned.Keys) {
        $targetRelative = $owned[$sourceRelative]
        $targetPath = Join-Path $repoRoot $targetRelative
        $present = (Test-Path -LiteralPath $targetPath -PathType Leaf)

        if (-not $isConfigured) {
            if ($present) {
                $orphans.Add(('{0}: orphan ({1} is not configured)' -f $targetRelative, $platform))
            }
            continue
        }
        if (-not $present) {
            $findings.Add(('{0}: missing' -f $targetRelative))
            continue
        }
        $expected = Get-CanonicalAdapter -SystemRoot $systemRoot -SourceRelative $sourceRelative
        if (-not (Compare-NormalizedContent $expected ([System.IO.File]::ReadAllText($targetPath)))) {
            $findings.Add(('{0}: stale' -f $targetRelative))
            continue
        }
        $verified++
    }

    $blockTarget = Get-PlatformBlockTarget $platform
    if ($blockTarget -eq '') { continue }

    $blockPath = Join-Path $repoRoot $blockTarget
    if (-not (Test-Path -LiteralPath $blockPath -PathType Leaf)) {
        if ($isConfigured) { $findings.Add(('{0}: missing' -f $blockTarget)) }
        continue
    }

    $installedBlock = ''
    try {
        $installedBlock = Get-OttodocBlock -Content ([System.IO.File]::ReadAllText($blockPath))
    }
    catch {
        $findings.Add(('{0}: {1}' -f $blockTarget, $_.Exception.Message))
        continue
    }

    if (-not $isConfigured) {
        if ($installedBlock -ne '') {
            $orphans.Add(('{0}: orphan OttoDoc block ({1} is not configured)' -f $blockTarget, $platform))
        }
        continue
    }
    if ($installedBlock -eq '') {
        $findings.Add(('{0}: OttoDoc block missing' -f $blockTarget))
        continue
    }
    $expectedBlock = Get-CanonicalAdapter -SystemRoot $systemRoot -SourceRelative (Get-PlatformBlockSource $platform)
    if (-not (Compare-NormalizedContent $expectedBlock.TrimEnd("`n") $installedBlock.TrimEnd("`n"))) {
        $findings.Add(('{0}: OttoDoc block stale' -f $blockTarget))
        continue
    }
    $verified++
}

$setDescription = '(none)'
if ($configured.Count -gt 0) { $setDescription = ($configured -join ', ') }

$findings | ForEach-Object { Write-Output $_ }

if ($orphans.Count -gt 0) {
    $orphans | ForEach-Object { Write-Output $_ }
    Write-Output 'Those adapter files belong to a platform that is not in the configured set. Run configure-platform.ps1 -Platform <name> to adopt that platform, or remove-platform.ps1 -Platform <name> to delete its files. OttoDoc will not choose for you.'
}

$problems = $findings.Count
if (-not $WarnOnOrphans) { $problems += $orphans.Count }

if ($problems -gt 0) {
    Write-Output ('ADAPTER CHECK FAILED [{0}]: {1} problem(s). Run configure-platform.ps1 to refresh a platform, or remove-platform.ps1 to decommission one.' -f $setDescription, $problems)
    exit 1
}

if ($orphans.Count -gt 0) {
    Write-Output ('ADAPTER CHECK OK [{0}]: {1} file(s) match docs/_system; {2} orphan(s) reported above, not treated as failures here.' -f $setDescription, $verified, $orphans.Count)
    exit 0
}

Write-Output ('ADAPTER CHECK OK [{0}]: {1} file(s) match docs/_system and no orphans are present.' -f $setDescription, $verified)
exit 0
