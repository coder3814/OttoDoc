# Replaces the installed OttoDoc engine with the newest files from its GitHub repository
# and refreshes every configured agent platform.
# This is the execution layer for the agent-facing `OttoDoc upgrade` command.
# Compatible with Windows PowerShell 5.1 and pwsh.
#
#   upgrade.ps1
#
# There is no -Platform parameter. Upgrade refreshes the platforms the repository
# actually has configured, read from the generated CI workflow. Naming one platform
# could only mean "refresh just this one", which is the narrowing this replaced, or
# "also add this one", which is configure-platform.ps1's job.

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

. (Join-Path $PSScriptRoot 'common.ps1')

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

# The configured set is read before anything is touched. The generated workflow it comes
# from lives outside docs/_system/, so it survives the wholesale engine replacement below.
$configuredPlatforms = @(Get-ConfiguredPlatforms -RepoRoot $repoRoot)

# Backed up broadly: every adapter path of every supported platform, both shared files,
# and the workflow. Rollback must be able to restore a file the new engine created as
# well as one it changed, and shared files are backed up whole because OttoDoc's block
# inside them cannot be restored independently of the owner's surrounding content.
$managedTargets = @()
foreach ($platform in $Script:SupportedPlatforms) {
    $owned = Get-PlatformOwnedPaths $platform
    foreach ($sourceRelative in $owned.Keys) { $managedTargets += $owned[$sourceRelative] }
    $blockTarget = Get-PlatformBlockTarget $platform
    if ($blockTarget -ne '' -and $managedTargets -notcontains $blockTarget) { $managedTargets += $blockTarget }
}
$managedTargets += $Script:WorkflowTarget

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
    foreach ($required in @(
        'constitution.md',
        'process/workflow.md',
        'scripts/common.ps1',
        'scripts/upgrade.ps1',
        'scripts/configure-platform.ps1',
        'scripts/remove-platform.ps1',
        'scripts/check-adapters.ps1',
        'scripts/uninstall.ps1',
        'scripts/lint.ps1',
        'scripts/regen.ps1',
        'scripts/rename.ps1')) {
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

    # Adopt the new engine's helpers for everything below this line.
    . (Join-Path $oldSystemRoot 'scripts/common.ps1')

    $intakePath = Join-Path $docsRoot '_intake'
    if (-not (Test-Path -LiteralPath $intakePath)) {
        New-Item -ItemType Directory -Path $intakePath | Out-Null
        $intakeCreated = $true
        Write-Output 'CREATED: docs/_intake/'
    }

    $configure = Join-Path $oldSystemRoot 'scripts/configure-platform.ps1'
    $checkAdapters = Join-Path $oldSystemRoot 'scripts/check-adapters.ps1'
    $lint = Join-Path $oldSystemRoot 'scripts/lint.ps1'
    $regen = Join-Path $oldSystemRoot 'scripts/regen.ps1'

    if ($configuredPlatforms.Count -eq 0) {
        # Zero configured platforms is an ordinary state, but the workflow still has to
        # exist and still has to record the empty set.
        Write-Output 'UPGRADE NOTE: no agent platform is configured; refreshing the engine, the workflow, and the indexes only.'
        $workflowPath = Join-Path $repoRoot $Script:WorkflowTarget
        $workflowDirectory = Split-Path -Parent $workflowPath
        if (-not (Test-Path -LiteralPath $workflowDirectory)) {
            New-Item -ItemType Directory -Path $workflowDirectory -Force | Out-Null
        }
        Write-Utf8LfFile -Path $workflowPath -Content (Get-GeneratedWorkflow -SystemRoot $oldSystemRoot -Platforms @())
    }
    else {
        foreach ($platform in $configuredPlatforms) {
            & $configure -Platform $platform
            if ($LASTEXITCODE -ne 0) { throw ('Agent-platform configuration failed for {0}.' -f $platform) }
        }
    }

    & $lint
    if ($LASTEXITCODE -ne 0) { throw 'Knowledge-tree lint failed under the new engine.' }
    & $regen
    if ($LASTEXITCODE -ne 0) { throw 'Index regeneration failed under the new engine.' }
    & $checkAdapters
    if ($LASTEXITCODE -ne 0) { throw 'Agent-platform verification failed under the new engine.' }
    & $regen -Check
    if ($LASTEXITCODE -ne 0) { throw 'Generated-index verification failed under the new engine.' }

    $succeeded = $true
    $setDescription = '(none)'
    if ($configuredPlatforms.Count -gt 0) { $setDescription = ($configuredPlatforms -join ', ') }
    Write-Output ('UPGRADE OK: OttoDoc refreshed from {0} at ref {1}; configured platforms {2} refreshed and verified.' -f $Repository, $Ref, $setDescription)
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
