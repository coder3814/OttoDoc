# Removes the OttoDoc engine and every agent platform, leaving the documentation
# (lifecycle.md: uninstall). Non-interactive on purpose; the agent confirms with the
# owner first. The result is an uncommitted diff - git is the undo.
#
# Removes: every platform's generated files and blocks (converge to empty), the CI
# workflow, the record, docs/_system/, and the governance pointer in the root index.
# Preserves: every document, every generated index, every asset, and docs/_intake/.

[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'platforms.ps1')

$docsRoot = Get-DocsRoot
$repoRoot = Get-RepoRoot
$systemRoot = Get-SystemRoot

try {
    Write-OttodocRecord -RepoRoot $repoRoot -Platforms @()
    $result = Invoke-PlatformConverge -RepoRoot $repoRoot -SystemRoot $systemRoot
    foreach ($item in $result['drift']) { Write-Output ('CONVERGED: {0}' -f $item) }

    $workflowPath = Join-Path $repoRoot $Script:WorkflowTarget
    if (Test-Path -LiteralPath $workflowPath -PathType Leaf) {
        Remove-GeneratedFile -Path $workflowPath
        Write-Output ('REMOVED: {0}' -f $Script:WorkflowTarget)
    }
    Remove-Item -LiteralPath (Join-Path $repoRoot $Script:RecordTarget) -Force
    Write-Output ('REMOVED: {0}' -f $Script:RecordTarget)

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
            Write-Output 'REMOVED: docs/index.md (governance pointer only)'
        }
    }

    if (Test-Path -LiteralPath $systemRoot -PathType Container) {
        Remove-Item -LiteralPath $systemRoot -Recurse -Force
        Write-Output 'REMOVED: docs/_system/'
    }
}
catch {
    Write-Output ('UNINSTALL FAILED: {0}' -f $_.Exception.Message)
    Write-Output 'Review the repository diff; git is the undo.'
    exit 1
}

Write-Output 'PRESERVED: every document, every generated index, every asset, and docs/_intake/.'
Write-Output 'UNINSTALL OK: the OttoDoc engine and all agent platforms were removed. Review the uncommitted diff.'
exit 0
