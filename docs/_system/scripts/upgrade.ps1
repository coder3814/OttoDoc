# Replaces the installed OttoDoc engine with the newest files from its GitHub repository.
# This is the execution layer for the agent-facing `OttoDoc upgrade` command.
# Compatible with Windows PowerShell 5.1 and pwsh.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Claude', 'Codex', 'Cursor')]
    [string]$Platform,

    [ValidatePattern('^https://github\.com/[^/]+/[^/]+/?$')]
    [string]$Repository = 'https://github.com/coder3814/OttoDoc',

    [ValidatePattern('^[A-Za-z0-9._/-]+$')]
    [string]$Ref = 'main',

    [string]$ArchivePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$oldSystemRoot = Split-Path -Parent $PSScriptRoot
$docsRoot = Split-Path -Parent $oldSystemRoot
$repoRoot = Split-Path -Parent $docsRoot
$workRoot = Join-Path $repoRoot ('.ottodoc-upgrade-' + [guid]::NewGuid().ToString('N'))
$extractRoot = Join-Path $workRoot 'source'
$backupSystem = Join-Path $workRoot 'previous-system'
$backupFiles = Join-Path $workRoot 'previous-generated-files'
$backupIndexes = Join-Path $workRoot 'previous-indexes'
$downloadPath = Join-Path $workRoot 'ottodoc.zip'
$systemReplaced = $false
$generatedFilesBackedUp = $false
$indexesBackedUp = $false
$intakeCreated = $false
$succeeded = $false

$platformTargets = @{
    'Claude' = @(
        '.claude/agents/doc-coordinator.md',
        '.claude/agents/doc-author.md',
        '.claude/agents/doc-reviewer.md',
        '.claude/skills/doc/SKILL.md'
    )
    'Codex' = @(
        'AGENTS.md',
        '.agents/skills/documentation/SKILL.md',
        '.codex/agents/doc-coordinator.toml',
        '.codex/agents/doc-author.toml',
        '.codex/agents/doc-reviewer.toml'
    )
    'Cursor' = @(
        '.cursor/rules/documentation.mdc',
        '.cursor/skills/documentation/SKILL.md',
        '.cursor/agents/doc-coordinator.md',
        '.cursor/agents/doc-author.md',
        '.cursor/agents/doc-reviewer.md'
    )
}
$managedTargets = @($platformTargets[$Platform]) + @('.github/workflows/docs.yml')

function Copy-RelativeFile {
    param([string]$SourceRoot, [string]$RelativePath, [string]$DestinationRoot)
    $source = Join-Path $SourceRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { return }
    $destination = Join-Path $DestinationRoot $RelativePath
    $destinationDirectory = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $destinationDirectory)) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

function Get-KnowledgeIndexes {
    return @(Get-ChildItem -LiteralPath $docsRoot -Recurse -File -Filter 'index.md' -Force | Where-Object {
        -not $_.FullName.StartsWith($oldSystemRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and
        -not $_.FullName.StartsWith($workRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
    })
}

function Restore-Installation {
    Write-Output 'UPGRADE ROLLBACK: restoring the previous OttoDoc installation.'

    if ($indexesBackedUp) {
        foreach ($index in @(Get-KnowledgeIndexes)) {
            Remove-Item -LiteralPath $index.FullName -Force
        }
        if (Test-Path -LiteralPath $backupIndexes) {
            foreach ($file in @(Get-ChildItem -LiteralPath $backupIndexes -Recurse -File -Force)) {
                $relative = $file.FullName.Substring($backupIndexes.Length).TrimStart('\', '/')
                Copy-RelativeFile -SourceRoot $backupIndexes -RelativePath $relative -DestinationRoot $docsRoot
            }
        }
    }

    if ($generatedFilesBackedUp) {
        foreach ($targetRelative in $managedTargets) {
            $target = Join-Path $repoRoot $targetRelative
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                Remove-Item -LiteralPath $target -Force
            }
            Copy-RelativeFile -SourceRoot $backupFiles -RelativePath $targetRelative -DestinationRoot $repoRoot
        }
    }

    if ($systemReplaced) {
        if (Test-Path -LiteralPath $oldSystemRoot) {
            Remove-Item -LiteralPath $oldSystemRoot -Recurse -Force
        }
        Move-Item -LiteralPath $backupSystem -Destination $oldSystemRoot
    }

    if ($intakeCreated) {
        $intakePath = Join-Path $docsRoot '_intake'
        if ((Test-Path -LiteralPath $intakePath -PathType Container) -and
            @(Get-ChildItem -LiteralPath $intakePath -Force).Count -eq 0) {
            Remove-Item -LiteralPath $intakePath -Force
        }
    }
}

try {
    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null

    if ($ArchivePath) {
        $resolvedArchive = (Resolve-Path -LiteralPath $ArchivePath).Path
        Copy-Item -LiteralPath $resolvedArchive -Destination $downloadPath -Force
        Write-Output ('UPGRADE SOURCE: local archive {0}' -f $resolvedArchive)
    }
    else {
        $repositoryBase = $Repository.TrimEnd('/')
        $archiveUrl = '{0}/archive/refs/heads/{1}.zip' -f $repositoryBase, $Ref
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
    $incomingSystem = $candidates[0].FullName
    foreach ($required in @('constitution.md', 'process/workflow.md', 'scripts/upgrade.ps1', 'scripts/configure-platform.ps1', 'scripts/lint.ps1', 'scripts/regen.ps1', 'scripts/rename.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $incomingSystem $required) -PathType Leaf)) {
            throw ('Downloaded engine is incomplete; missing docs/_system/{0}.' -f $required)
        }
    }

    New-Item -ItemType Directory -Path $backupFiles -Force | Out-Null
    foreach ($targetRelative in $managedTargets) {
        Copy-RelativeFile -SourceRoot $repoRoot -RelativePath $targetRelative -DestinationRoot $backupFiles
    }
    $generatedFilesBackedUp = $true

    New-Item -ItemType Directory -Path $backupIndexes -Force | Out-Null
    foreach ($index in @(Get-KnowledgeIndexes)) {
        $relative = $index.FullName.Substring($docsRoot.Length).TrimStart('\', '/')
        Copy-RelativeFile -SourceRoot $docsRoot -RelativePath $relative -DestinationRoot $backupIndexes
    }
    $indexesBackedUp = $true

    Move-Item -LiteralPath $oldSystemRoot -Destination $backupSystem
    Move-Item -LiteralPath $incomingSystem -Destination $oldSystemRoot
    $systemReplaced = $true

    $intakePath = Join-Path $docsRoot '_intake'
    if (-not (Test-Path -LiteralPath $intakePath)) {
        New-Item -ItemType Directory -Path $intakePath | Out-Null
        $intakeCreated = $true
        Write-Output 'CREATED: docs/_intake/'
    }

    $configure = Join-Path $oldSystemRoot 'scripts/configure-platform.ps1'
    $lint = Join-Path $oldSystemRoot 'scripts/lint.ps1'
    $regen = Join-Path $oldSystemRoot 'scripts/regen.ps1'

    & $configure -Platform $Platform
    if ($LASTEXITCODE -ne 0) { throw 'Agent-platform configuration failed.' }
    & $lint
    if ($LASTEXITCODE -ne 0) { throw 'Knowledge-tree lint failed under the new engine.' }
    & $regen
    if ($LASTEXITCODE -ne 0) { throw 'Index regeneration failed under the new engine.' }
    & $configure -Platform $Platform -Check
    if ($LASTEXITCODE -ne 0) { throw 'Agent-platform verification failed under the new engine.' }
    & $regen -Check
    if ($LASTEXITCODE -ne 0) { throw 'Generated-index verification failed under the new engine.' }

    $succeeded = $true
    Write-Output ('UPGRADE OK: OttoDoc refreshed from {0} at ref {1}; platform {2} configured and verified.' -f $Repository, $Ref, $Platform)
}
catch {
    $upgradeError = $_.Exception.Message
    try {
        Restore-Installation
        Write-Output 'UPGRADE ROLLBACK OK: the previous installation was restored.'
    }
    catch {
        Write-Output ('UPGRADE ROLLBACK FAILED: {0}' -f $_.Exception.Message)
    }
    Write-Output ('UPGRADE FAILED: {0}' -f $upgradeError)
}
finally {
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -LiteralPath $workRoot -Recurse -Force
    }
}

if (-not $succeeded) { exit 1 }
exit 0
