# Removes the OttoDoc engine and every agent platform, and leaves the documentation.
# Part of the engine (constitution section 9): changed only on the repository owner's explicit request.
# Compatible with Windows PowerShell 5.1 and pwsh.
#
#   uninstall.ps1
#
# Non-interactive on purpose, so other commands and CI can call it. The agent confirms
# with the owner before invoking it. The result is left as an uncommitted diff for
# review, exactly as upgrade behaves; git is the undo.
#
# Removes: docs/_system/, the generated CI workflow, every owned adapter path for every
# supported platform, OttoDoc's block from shared files, and the governance blockquote
# the regen script emits into the root index - the last so no link to a deleted
# constitution is left dangling.
#
# Preserves: every document, every generated index, every asset, and docs/_intake/ with
# its contents. After uninstall the tree is still conformant, so reinstalling and
# regenerating restores every index byte-identically.

[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'common.ps1')

$docsRoot = Get-DocsRoot
$repoRoot = Get-RepoRoot
$systemRoot = Get-SystemRoot

$removed = @()
$skipped = @()

try {
    $configured = @(Get-ConfiguredPlatforms -RepoRoot $repoRoot)

    # Rendered before anything is deleted: the yardstick lives inside docs/_system/,
    # which this script is about to remove.
    $expectedWorkflow = Get-GeneratedWorkflow -SystemRoot $systemRoot -Platforms $configured

    # Every supported platform, not only the configured ones, so adapters stranded by an
    # earlier installation are swept too.
    foreach ($platform in $Script:SupportedPlatforms) {
        $result = Remove-PlatformFiles -RepoRoot $repoRoot -SystemRoot $systemRoot -Platform $platform
        $removed += $result['removed']
        $skipped += $result['skipped']
    }

    $workflowPath = Join-Path $repoRoot $Script:WorkflowTarget
    if (Test-Path -LiteralPath $workflowPath -PathType Leaf) {
        if (Compare-NormalizedContent $expectedWorkflow ([System.IO.File]::ReadAllText($workflowPath))) {
            Remove-Item -LiteralPath $workflowPath -Force
            Remove-EmptyParentDirectory -RepoRoot $repoRoot -StartDirectory (Split-Path -Parent $workflowPath)
            $removed += $Script:WorkflowTarget
        }
        else {
            $skipped += ('{0}: not written by this engine (content does not match canon) - left in place' -f $Script:WorkflowTarget)
        }
    }

    # The governance pointer is uninstall's only edit inside the knowledge tree.
    $rootIndex = Join-Path $docsRoot 'index.md'
    if (Test-Path -LiteralPath $rootIndex -PathType Leaf) {
        $lines = @([System.IO.File]::ReadAllText($rootIndex).Replace("`r`n", "`n").Split("`n"))
        $kept = @()
        $dropped = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -like '> Governed by `[the documentation constitution`]*') {
                $dropped = $true
                # Collapse the blank line the removal would otherwise double up.
                if ($i + 1 -lt $lines.Count -and $lines[$i + 1].Trim() -eq '' -and
                    $kept.Count -gt 0 -and $kept[$kept.Count - 1].Trim() -eq '') {
                    $i++
                }
                continue
            }
            $kept += $lines[$i]
        }
        if ($dropped) {
            Write-Utf8LfFile -Path $rootIndex -Content ($kept -join "`n")
            $removed += 'docs/index.md (governance pointer only)'
        }
    }

    if (Test-Path -LiteralPath $systemRoot -PathType Container) {
        Remove-Item -LiteralPath $systemRoot -Recurse -Force
        $removed += 'docs/_system/'
    }
}
catch {
    Write-Output ('UNINSTALL FAILED: {0}' -f $_.Exception.Message)
    Write-Output 'Nothing further was removed. Review the repository diff; git is the undo.'
    exit 1
}

foreach ($item in $removed) { Write-Output ('REMOVED: {0}' -f $item) }
foreach ($item in $skipped) { Write-Output ('SKIPPED: {0}' -f $item) }
Write-Output 'PRESERVED: every document, every generated index, every asset, and docs/_intake/.'

if ($skipped.Count -gt 0) {
    Write-Output 'Files listed as SKIPPED sit at OttoDoc paths but do not match the canonical engine, so OttoDoc did not write them and will not delete them. Remove them by hand if they are unwanted.'
}

Write-Output 'UNINSTALL OK: the OttoDoc engine and all agent platforms were removed. Review the uncommitted diff.'
exit 0
