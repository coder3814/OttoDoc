# Replaces the installed OttoDoc engine with the newest files from its GitHub
# repository, then hands off to the new engine's upgrade-finish.ps1 to converge the
# recorded platforms and report (lifecycle.md: upgrade).
#
#   upgrade.ps1 [-Repository <url>] [-Ref <ref>] [-ArchivePath <zip>]
#
# Requires a clean git tree: that is what makes git the undo. There is no backup and
# no rollback - on failure, review the diff and use git restore.

[CmdletBinding()]
param(
    [ValidatePattern('^https://github\.com/[^/]+/[^/]+/?$')]
    [string]$Repository = 'https://github.com/coder3814/OttoDoc',

    [ValidatePattern('^[A-Za-z0-9._/-]+$')]
    [string]$Ref = 'main',

    [string]$ArchivePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$systemRoot = Split-Path -Parent $PSScriptRoot
$docsRoot = Split-Path -Parent $systemRoot
$repoRoot = Split-Path -Parent $docsRoot

$gitStatus = & git -C $repoRoot status --porcelain
if ($LASTEXITCODE -ne 0) {
    Write-Output 'UPGRADE REFUSED: not a git repository. Git is the undo for an upgrade, so one is required.'
    exit 1
}
if (@($gitStatus | Where-Object { $_ }).Count -gt 0) {
    Write-Output 'UPGRADE REFUSED: the git working tree is not clean. Commit or stash your changes first; git is the undo.'
    exit 1
}

$workRoot = Join-Path $repoRoot ('.ottodoc-upgrade-' + [guid]::NewGuid().ToString('N'))
$extractRoot = Join-Path $workRoot 'source'
$downloadPath = Join-Path $workRoot 'ottodoc.zip'
$succeeded = $false

try {
    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null

    if ($ArchivePath) {
        $resolvedArchive = (Resolve-Path -LiteralPath $ArchivePath).Path
        Copy-Item -LiteralPath $resolvedArchive -Destination $downloadPath -Force
        $source = ('local archive {0}' -f $resolvedArchive)
        Write-Output ('UPGRADE SOURCE: {0}' -f $source)
    }
    else {
        # The generic archive form resolves branches, tags, and commit SHAs alike.
        $archiveUrl = '{0}/archive/{1}.zip' -f $Repository.TrimEnd('/'), $Ref
        $source = ('{0} at ref {1}' -f $Repository, $Ref)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Write-Output ('UPGRADE DOWNLOAD: {0}' -f $archiveUrl)
        Invoke-WebRequest -Uri $archiveUrl -OutFile $downloadPath -UseBasicParsing
    }

    Expand-Archive -LiteralPath $downloadPath -DestinationPath $extractRoot -Force
    $candidates = @(Get-ChildItem -LiteralPath $extractRoot -Recurse -Directory -Force | Where-Object {
        $_.Name -eq '_system' -and $_.Parent.Name -eq 'docs'
    })
    if ($candidates.Count -ne 1) {
        throw ('Downloaded archive must contain exactly one docs/_system directory; found {0}.' -f $candidates.Count)
    }

    Remove-Item -LiteralPath $systemRoot -Recurse -Force
    Move-Item -LiteralPath $candidates[0].FullName -Destination $systemRoot

    # Hand off to the engine just installed. This script was read whole before the swap,
    # so a step written here would be the previous engine's; upgrade-finish.ps1 is read
    # now, from the new engine, and owns everything after the swap - including the
    # final report. Keep this script to the gate, the fetch, and the swap.
    & (Join-Path $systemRoot 'scripts/upgrade-finish.ps1') -Source $source
    $succeeded = ($LASTEXITCODE -eq 0)
}
catch {
    Write-Output ('UPGRADE FAILED: {0}' -f $_.Exception.Message)
    Write-Output 'The working tree may hold a partial upgrade. Git is the undo: use git restore (and git clean for new files) to return to the last commit.'
}
finally {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
}

if (-not $succeeded) { exit 1 }
exit 0
