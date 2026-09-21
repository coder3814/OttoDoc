# The second half of an upgrade (lifecycle.md: upgrade): everything that happens after
# the engine has been replaced. upgrade.ps1 invokes this file from the NEW engine, by
# path, after the swap.
#
# It is a separate file on purpose. PowerShell reads a script whole before running it,
# so any step written in upgrade.ps1 itself is the PREVIOUS engine's step, and a change
# to it would only take effect one upgrade late - leaving the owner to commit a
# half-finished upgrade and run it again, with nothing saying so. A script invoked by
# path is read at the moment of the call, from the engine just installed.
#
# The parameters are an interface the previous engine's upgrade.ps1 calls. Never rename
# or remove one, and only ever add optional ones.

[CmdletBinding()]
param(
    [string]$Source = ''
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'platforms.ps1')

$docsRoot = Get-DocsRoot
$repoRoot = Get-RepoRoot
$systemRoot = Get-SystemRoot

try {
    $intakePath = Join-Path $docsRoot '_intake'
    if (-not (Test-Path -LiteralPath $intakePath)) {
        New-Item -ItemType Directory -Path $intakePath | Out-Null
        Write-Output 'CREATED: docs/_intake/'
    }

    # A repository installed before the ignore file existed, or one that lost it, gets
    # the same boundary a fresh install has. An existing file is the owner's and is
    # not touched. Announced, because it changes which paths owe a change note.
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $Script:IgnoreTarget) -PathType Leaf)) {
        $seededPatterns = @(Add-OttodocIgnorePatterns -RepoRoot $repoRoot)
        Write-Output ('CREATED: {0} - BEHAVIOR CHANGE: this upgrade gives the documented system a boundary. Changes confined to {1} no longer owe a change note. These are defaults, not a decision made for you: delete a line from the file to keep that path documented - for instance /CLAUDE.md, if it holds project rules you maintain.' -f $Script:IgnoreTarget, ($seededPatterns -join ', '))
    }

    $configured = @(Read-OttodocRecord -RepoRoot $repoRoot)
    $result = Invoke-PlatformConverge -RepoRoot $repoRoot -SystemRoot $systemRoot
    foreach ($item in $result['drift']) { Write-Output ('CONVERGED: {0}' -f $item) }
    if ($result['drift'] -contains 'docs/.gitattributes: missing') {
        # The rule arrives too late for this one run: Git flags a file whose size changed
        # without comparing content, so a CRLF checkout still reads rewritten files as modified.
        Write-Output 'NOTE: docs/.gitattributes is new. On a CRLF checkout (core.autocrlf=true) the files this upgrade rewrote show as modified with no content change until staged; git add -A clears them, and later upgrades stay clean.'
    }

    & (Join-Path $PSScriptRoot 'regen.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Lint or index regeneration failed under the new engine.' }

    $setDescription = '(none)'
    if ($configured.Count -gt 0) { $setDescription = ($configured -join ', ') }
    $sourceDescription = ''
    if ($Source -ne '') { $sourceDescription = (' from {0}' -f $Source) }
    Write-Output ('UPGRADE OK: OttoDoc refreshed{0}; configured platforms: {1}. Review the uncommitted diff.' -f $sourceDescription, $setDescription)
}
catch {
    Write-Output ('UPGRADE FAILED: {0}' -f $_.Exception.Message)
    Write-Output 'The working tree may hold a partial upgrade. Git is the undo: use git restore (and git clean for new files) to return to the last commit.'
    exit 1
}
exit 0
