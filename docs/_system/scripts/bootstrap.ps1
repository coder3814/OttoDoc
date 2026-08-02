# Bootstraps the portable documentation engine in a repository (lifecycle.md: install).
# Creates missing kind directories and docs/_intake/, records the chosen platform,
# converges, and generates the indexes. Fails closed: a pre-existing nonconformant
# tree aborts the install with nothing modified.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Claude', 'Codex', 'Cursor')]
    [string]$Platform
)

. (Join-Path $PSScriptRoot 'platforms.ps1')

$docsRoot = Get-DocsRoot
$repoRoot = Get-RepoRoot
$systemRoot = Get-SystemRoot

foreach ($kind in $Script:KindDirs.Keys) {
    $kindPath = Join-Path $docsRoot $kind
    if (-not (Test-Path -LiteralPath $kindPath)) {
        New-Item -ItemType Directory -Path $kindPath | Out-Null
        Write-Output ('CREATED: docs/{0}/' -f $kind)
    }
}
$intakePath = Join-Path $docsRoot '_intake'
if (-not (Test-Path -LiteralPath $intakePath)) {
    New-Item -ItemType Directory -Path $intakePath | Out-Null
    Write-Output 'CREATED: docs/_intake/'
}

& (Join-Path $PSScriptRoot 'lint.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output 'BOOTSTRAP FAILED: the existing documentation tree is not conformant; no existing content was modified.'
    exit 1
}

try {
    Write-OttodocRecord -RepoRoot $repoRoot -Platforms @($Platform)
    Invoke-PlatformConverge -RepoRoot $repoRoot -SystemRoot $systemRoot | Out-Null
}
catch {
    Write-Output ('BOOTSTRAP FAILED: {0}' -f $_.Exception.Message)
    exit 1
}

& (Join-Path $PSScriptRoot 'regen.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output 'BOOTSTRAP FAILED: index generation failed.'
    exit 1
}

Write-Output ('BOOTSTRAP OK: portable documentation engine installed; configured set is {0}.' -f $Platform)
exit 0
