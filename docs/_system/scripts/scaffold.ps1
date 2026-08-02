# New-document scaffold (constitution section 8 via the /doc skill). Part of the OttoDoc engine.
# Creates a concept doc from its kind's template, in the correct directory.
#
#   scaffold.ps1 -Kind runbook -Slug prod-search-reindex -Title "Prod search reindex" -Actor "claude/fable-5"
#   scaffold.ps1 -Kind reference -Slug test-accounts -Title "Test accounts" -Actor "human:maintainer" -Subject accounts

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('runbook', 'reference', 'decision', 'explanation', 'plan', 'design')]
    [string]$Kind,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')]
    [string]$Slug,

    [Parameter(Mandatory = $true)]
    [string]$Title,

    [Parameter(Mandatory = $true)]
    [string]$Actor,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')]
    [string]$Subject
)

. (Join-Path $PSScriptRoot 'common.ps1')

if ($Slug -eq 'index' -or $Slug -eq 'log') {
    Write-Output ('SCAFFOLD FAILED: "{0}" is a reserved filename (constitution section 3).' -f $Slug)
    exit 1
}

$docsRoot = Get-DocsRoot

$kindDirNames = @{
    'runbook' = 'runbooks'; 'reference' = 'reference'; 'decision' = 'decisions'
    'explanation' = 'explanations'; 'plan' = 'plans'; 'design' = 'design'
}
$kindDir = Join-Path $docsRoot $kindDirNames[$Kind]

$targetDir = $kindDir
if ($PSBoundParameters.ContainsKey('Subject')) {
    $targetDir = Join-Path $kindDir $Subject
    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir | Out-Null
        Write-Output ('NOTE: created new subject folder "{0}" - subject folders are earned at roughly three or four docs sharing a subject (constitution section 2). Make sure this one is.' -f $Subject)
    }
}

$target = Join-Path $targetDir ($Slug + '.md')
if (Test-Path -LiteralPath $target) {
    Write-Output ('SCAFFOLD FAILED: {0} already exists.' -f (Get-RelativeDocPath $docsRoot $target))
    exit 1
}

$template = Join-Path $PSScriptRoot ('..\templates\' + $Kind + '.md')
$content = [System.IO.File]::ReadAllText((Resolve-Path $template).Path)
$content = $content.Replace('{{TITLE}}', $Title)
$content = $content.Replace('{{ACTOR}}', $Actor)
$content = $content.Replace('{{DATE}}', (Get-Date -Format 'yyyy-MM-dd'))

Write-Utf8LfFile -Path $target -Content $content.Replace("`r`n", "`n")

Write-Output ('SCAFFOLD OK: {0}' -f (Get-RelativeDocPath $docsRoot $target))
Write-Output 'Next: author the content, replace the description and tags placeholders, then lint and regen (constitution section 8).'
exit 0
