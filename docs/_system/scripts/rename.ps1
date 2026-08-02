# Knowledge-document rename. Part of the OttoDoc engine.
# Renames one concept document in place, repairs inbound Markdown links, and regenerates indexes.
#
#   rename.ps1 -Path docs/reference/retry-policy.md -Slug retry-behavior

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')]
    [string]$Slug
)

. (Join-Path $PSScriptRoot 'common.ps1')

if ($Slug -eq 'index' -or $Slug -eq 'log') {
    Write-Output ('RENAME FAILED: "{0}" is a reserved filename (constitution section 3).' -f $Slug)
    exit 1
}

$docsRoot = Get-DocsRoot
$repositoryRoot = (Resolve-Path (Join-Path $docsRoot '..')).Path
$sourceCandidate = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $repositoryRoot $Path }

try { $source = (Resolve-Path -LiteralPath $sourceCandidate -ErrorAction Stop).Path }
catch {
    Write-Output ('RENAME FAILED: source does not exist: {0}' -f $Path)
    exit 1
}

$conceptPaths = @(Get-TreeDocs $docsRoot | ForEach-Object { $_.FullName })
if ($source -notin $conceptPaths) {
    Write-Output 'RENAME FAILED: source must be a knowledge document under a document-kind directory (not index.md or an asset).'
    exit 1
}

$destination = Join-Path (Split-Path -Parent $source) ($Slug + '.md')
if ([string]::Equals($source, $destination, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Output ('RENAME FAILED: source already has the filename {0}.md.' -f $Slug)
    exit 1
}
if (Test-Path -LiteralPath $destination) {
    Write-Output ('RENAME FAILED: destination already exists: {0}' -f (Get-RelativeDocPath $docsRoot $destination))
    exit 1
}

$lintOutput = & (Join-Path $PSScriptRoot 'lint.ps1')
if ($LASTEXITCODE -ne 0) {
    $lintOutput | ForEach-Object { Write-Output $_ }
    Write-Output 'RENAME ABORTED: lint must pass before a rename.'
    exit 1
}

function Get-RelativeLinkPath([string]$FromDirectory, [string]$ToPath) {
    $from = New-Object System.Uri(([System.IO.Path]::GetFullPath($FromDirectory).TrimEnd('\') + '\'))
    $to = New-Object System.Uri([System.IO.Path]::GetFullPath($ToPath))
    return [uri]::UnescapeDataString($from.MakeRelativeUri($to).ToString())
}

$backups = @{}
$markdownFiles = @(Get-ChildItem -LiteralPath $docsRoot -Recurse -File -Filter '*.md' -Force | Where-Object {
    $_.FullName -notlike ((Join-Path $docsRoot '_system') + '\*') -and $_.Name -ne 'index.md'
})

try {
    foreach ($file in $markdownFiles) {
        $original = [System.IO.File]::ReadAllText($file.FullName)
        $sourceFilePath = $file.FullName
        $writePath = if ([string]::Equals($file.FullName, $source, [System.StringComparison]::OrdinalIgnoreCase)) { $destination } else { $file.FullName }
        $sourceDirectory = Split-Path -Parent $sourceFilePath

        $updated = [regex]::Replace($original, '(?m)(\[[^\]]*\]\()([^\)\s]+)(\))', {
            param($match)
            $target = $match.Groups[2].Value
            if ($target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:' -or $target.StartsWith('#')) { return $match.Value }
            $parts = $target.Split('#', 2)
            $pathPart = [uri]::UnescapeDataString($parts[0])
            if ($pathPart -eq '') { return $match.Value }
            $resolvedTarget = [System.IO.Path]::GetFullPath((Join-Path $sourceDirectory $pathPart))
            if (-not [string]::Equals($resolvedTarget, $source, [System.StringComparison]::OrdinalIgnoreCase)) { return $match.Value }
            $newTarget = Get-RelativeLinkPath (Split-Path -Parent $writePath) $destination
            if ($parts.Count -eq 2) { $newTarget += '#' + $parts[1] }
            return $match.Groups[1].Value + $newTarget + $match.Groups[3].Value
        })

        if ($updated -ne $original) {
            $backups[$file.FullName] = $original
        }
    }

    Move-Item -LiteralPath $source -Destination $destination

    foreach ($originalPath in $backups.Keys) {
        $writePath = if ([string]::Equals($originalPath, $source, [System.StringComparison]::OrdinalIgnoreCase)) { $destination } else { $originalPath }
        $original = $backups[$originalPath]
        $sourceDirectory = Split-Path -Parent $originalPath
        $updated = [regex]::Replace($original, '(?m)(\[[^\]]*\]\()([^\)\s]+)(\))', {
            param($match)
            $target = $match.Groups[2].Value
            if ($target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:' -or $target.StartsWith('#')) { return $match.Value }
            $parts = $target.Split('#', 2)
            $pathPart = [uri]::UnescapeDataString($parts[0])
            if ($pathPart -eq '') { return $match.Value }
            $resolvedTarget = [System.IO.Path]::GetFullPath((Join-Path $sourceDirectory $pathPart))
            if (-not [string]::Equals($resolvedTarget, $source, [System.StringComparison]::OrdinalIgnoreCase)) { return $match.Value }
            $newTarget = Get-RelativeLinkPath (Split-Path -Parent $writePath) $destination
            if ($parts.Count -eq 2) { $newTarget += '#' + $parts[1] }
            return $match.Groups[1].Value + $newTarget + $match.Groups[3].Value
        })
        Write-Utf8LfFile -Path $writePath -Content $updated.Replace("`r`n", "`n")
    }

    $regenOutput = & (Join-Path $PSScriptRoot 'regen.ps1')
    if ($LASTEXITCODE -ne 0) { throw (($regenOutput | Out-String).Trim()) }
}
catch {
    $failureMessage = $_.Exception.Message
    if (Test-Path -LiteralPath $destination) { Move-Item -LiteralPath $destination -Destination $source -Force }
    foreach ($originalPath in $backups.Keys) { Write-Utf8LfFile -Path $originalPath -Content $backups[$originalPath] }
    # A failed regeneration may have written some indexes before failing. Restore their projection too.
    & (Join-Path $PSScriptRoot 'regen.ps1') 2>&1 | Out-Null
    Write-Output ('RENAME FAILED; document, link, and index edits rolled back: {0}' -f $failureMessage)
    exit 1
}

Write-Output ('RENAME OK: {0} -> {1}' -f (Get-RelativeDocPath $docsRoot $source), (Get-RelativeDocPath $docsRoot $destination))
Write-Output ('LINKS UPDATED: {0} file(s).' -f $backups.Count)
$regenOutput | ForEach-Object { Write-Output $_ }
exit 0
