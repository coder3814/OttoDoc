# Replaces the installed OttoDoc engine with the newest files from its GitHub
# repository and converges the recorded platforms (lifecycle.md: upgrade).
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
        Write-Output ('UPGRADE SOURCE: local archive {0}' -f $resolvedArchive)
    }
    else {
        $archiveUrl = '{0}/archive/refs/heads/{1}.zip' -f $Repository.TrimEnd('/'), $Ref
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

    # Everything below runs on the new engine's helpers.
    . (Join-Path $systemRoot 'scripts/platforms.ps1')

    $intakePath = Join-Path $docsRoot '_intake'
    if (-not (Test-Path -LiteralPath $intakePath)) {
        New-Item -ItemType Directory -Path $intakePath | Out-Null
        Write-Output 'CREATED: docs/_intake/'
    }

    $configured = @(Read-OttodocRecord -RepoRoot $repoRoot)
    $result = Invoke-PlatformConverge -RepoRoot $repoRoot -SystemRoot $systemRoot
    foreach ($item in $result['drift']) { Write-Output ('CONVERGED: {0}' -f $item) }

    & (Join-Path $systemRoot 'scripts/regen.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Lint or index regeneration failed under the new engine.' }

    $succeeded = $true
    $setDescription = '(none)'
    if ($configured.Count -gt 0) { $setDescription = ($configured -join ', ') }
    Write-Output ('UPGRADE OK: OttoDoc refreshed from {0} at ref {1}; configured platforms: {2}. Review the uncommitted diff.' -f $Repository, $Ref, $setDescription)
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
