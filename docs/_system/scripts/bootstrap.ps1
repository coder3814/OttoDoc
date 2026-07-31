# Bootstraps the portable documentation engine in a repository.
# Part of the engine (constitution section 9): changed only on the repository owner's explicit request.
# Creates missing kind directories and generated indexes; never imports or rewrites existing content.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Claude', 'Codex', 'Cursor')]
    [string]$Platform
)

. (Join-Path $PSScriptRoot 'common.ps1')

$docsRoot = Get-DocsRoot

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

& (Join-Path $PSScriptRoot 'configure-platform.ps1') -Platform $Platform
if ($LASTEXITCODE -ne 0) {
    Write-Output 'BOOTSTRAP FAILED: agent platform was not configured.'
    exit 1
}

& (Join-Path $PSScriptRoot 'regen.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output 'BOOTSTRAP FAILED: the existing documentation tree is not conformant; no existing content was modified.'
    exit 1
}

& (Join-Path $PSScriptRoot 'configure-platform.ps1') -Platform $Platform -Check
if ($LASTEXITCODE -ne 0) {
    Write-Output 'BOOTSTRAP FAILED: configured platform files did not pass check mode.'
    exit 1
}

& (Join-Path $PSScriptRoot 'regen.ps1') -Check
if ($LASTEXITCODE -ne 0) {
    Write-Output 'BOOTSTRAP FAILED: generated indexes did not pass check mode.'
    exit 1
}

Write-Output 'BOOTSTRAP OK: portable documentation engine installed.'
exit 0
