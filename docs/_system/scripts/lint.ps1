# Documentation tree linter (constitution section 8, mechanical enforcement). Part of the OttoDoc engine.
# Checks the knowledge tree only; _system/ and _intake/ are exempt by law (section 1 amendment 5).
# Template-hygiene checks (REPLACE description, replace-me tag, {{ placeholders) are deliberate
# extras beyond the constitution's text - they catch a scaffold left unfinished.
# Exit 0 = conformant; exit 1 = violations (one per line: path: message).

[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'common.ps1')

$docsRoot = Get-DocsRoot
$errors = New-Object System.Collections.Generic.List[string]
function Add-Err([string]$Path, [string]$Msg) { $errors.Add(('{0}: {1}' -f $Path, $Msg)) }

$kebabFile  = '^[a-z0-9]+(-[a-z0-9]+)*\.md$'
$kebabTag   = '^[a-z0-9]+(-[a-z0-9]+)*$'
$kebabAsset = '^[a-z0-9]+(-[a-z0-9]+)*(\.[a-z0-9]+)+$'
$bannedComputationKeys = @('runtime', 'parameters', 'computation', 'executor', 'attester')
$requiredSections = @{
    'Runbook'     = @('Prerequisites', 'Steps', 'Verify')
    'Reference'   = @('Facts')
    'Decision'    = @('The choice', 'Forces', 'Alternatives rejected')
    'Explanation' = @('How it works')
    'Plan'        = @('Intent', 'Work', 'Retirement')
    'Design'      = @('The standard')
}

function Test-IsoDate([string]$s) {
    # strict: a real yyyy-MM-dd date, optionally followed by a T/space time suffix
    if ($s.Length -lt 10) { return $false }
    if ($s.Length -gt 10 -and $s[10] -ne 'T' -and $s[10] -ne ' ') { return $false }
    $tmp = [datetime]::MinValue
    return [datetime]::TryParseExact($s.Substring(0, 10), 'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None, [ref]$tmp)
}

# --- Root shape: exactly the six kind dirs + reserved dirs; only index.md as a root file ---
foreach ($entry in (Get-ChildItem -LiteralPath $docsRoot -Force)) {
    if ($entry.PSIsContainer) {
        if (-not ($Script:KindDirs.Contains($entry.Name)) -and -not ($Script:ReservedDirs -contains $entry.Name)) {
            Add-Err $entry.Name ('unknown root directory - the root of docs/ is the closed set of kinds (constitution section 2)')
        }
    }
    elseif ($entry.Name -ne 'index.md') {
        Add-Err $entry.Name 'stray file at docs/ root - only the generated index.md lives here'
    }
}
foreach ($kind in $Script:KindDirs.Keys) {
    if (-not (Test-Path -LiteralPath (Join-Path $docsRoot $kind))) {
        Add-Err $kind 'kind directory missing - all six exist from day one (constitution section 2)'
    }
}

# --- Structure walk: nesting depth, assets placement, reserved names ---
$assetFiles = @()   # full paths of files inside assets/ dirs
foreach ($kind in $Script:KindDirs.Keys) {
    $kindPath = Join-Path $docsRoot $kind
    if (-not (Test-Path -LiteralPath $kindPath)) { continue }

    foreach ($item in (Get-ChildItem -LiteralPath $kindPath -Recurse -Force)) {
        $rel = Get-RelativeDocPath $docsRoot $item.FullName
        if ($item.PSIsContainer) {
            if ($item.Parent.Name -eq 'assets') {
                Add-Err $rel 'assets/ holds files only, no subdirectories'
                continue
            }
            if ($item.Name -eq 'assets') { continue }
            $depth = ($rel.Split('/')).Count - 1   # 1 = child of kind dir, 2 = child of subject dir
            if ($depth -ge 2) {
                Add-Err $rel 'subjects do not nest - one folder level below the kind, plus assets/ (constitution section 2)'
            }
            elseif ($depth -eq 1) {
                # subject folder: must actually hold documents (folders are earned, constitution section 2)
                $subjectDocs = @(Get-ChildItem -LiteralPath $item.FullName -File -Filter '*.md' -Force |
                    Where-Object { $_.Name -ne 'index.md' })
                if ($subjectDocs.Count -eq 0) {
                    Add-Err $rel 'empty subject folder - folders are never created empty and dissolve when emptied (constitution section 2)'
                }
            }
        }
        else {
            if ($item.Name -eq 'log.md') { Add-Err $rel 'log.md is banned - git history is the log (constitution section 1 amendment 1)'; continue }
            $inAssets = ($item.Directory.Name -eq 'assets')
            if ($inAssets) {
                if ($item.Extension -eq '.md') { Add-Err $rel 'markdown inside assets/ - assets are non-markdown payload (constitution section 5)' }
                else {
                    if ($item.Name -cnotmatch $kebabAsset) {
                        Add-Err $rel 'asset file name must be lowercase kebab-case with extension (constitution section 5)'
                    }
                    $assetFiles += $item.FullName
                }
            }
            elseif ($item.Extension -ne '.md') {
                Add-Err $rel 'non-markdown file outside an assets/ folder (constitution section 5)'
            }
        }
    }
}

# --- Per-document contract checks ---
$docs = @(Get-TreeDocs $docsRoot)
$linkTargets = @()   # resolved full paths referenced by any doc
foreach ($doc in $docs) {
    $rel = Get-RelativeDocPath $docsRoot $doc.FullName
    $kind = $rel.Split('/')[0]

    if ($doc.Name -notmatch $kebabFile) {
        Add-Err $rel 'file name must be lowercase kebab-case (constitution section 3)'
    }

    $lines = [System.IO.File]::ReadAllLines($doc.FullName)
    $fm = ConvertFrom-Frontmatter $lines
    if (-not $fm.ok) { Add-Err $rel $fm.error; continue }
    $d = $fm.data

    # banned keys
    if ($fm.keys -contains 'stale_after') {
        Add-Err $rel 'stale_after is banned - no staleness timers (constitution section 1 amendment 3)'
    }
    if ($fm.keys -contains 'verified') {
        Add-Err $rel 'verified is banned - review evidence lives in Git and workflow history (constitution section 1 amendment 9)'
    }
    foreach ($bk in $bannedComputationKeys) {
        if ($fm.keys -contains $bk) {
            Add-Err $rel ('"{0}" is an Attested Computation contract key - banned (constitution section 1 amendment 2)' -f $bk)
        }
    }

    # type: required, exactly one of six (case-sensitive), matching the kind directory
    if (-not $d.ContainsKey('type') -or [string]::IsNullOrWhiteSpace([string]$d['type'])) {
        Add-Err $rel 'missing required frontmatter field: type'
    }
    else {
        $expected = $Script:KindDirs[$kind]
        if ([string]$d['type'] -cne $expected) {
            Add-Err $rel ('type "{0}" does not match its kind directory (expected exactly "{1}")' -f $d['type'], $expected)
        }
    }

    # title
    if (-not $d.ContainsKey('title') -or [string]::IsNullOrWhiteSpace([string]$d['title'])) {
        Add-Err $rel 'missing required frontmatter field: title'
    }
    elseif (([string]$d['title']).Contains('{{')) {
        Add-Err $rel 'title is still a template placeholder'
    }

    # description
    if (-not $d.ContainsKey('description') -or [string]::IsNullOrWhiteSpace([string]$d['description'])) {
        Add-Err $rel 'missing required frontmatter field: description'
    }
    elseif (([string]$d['description']).StartsWith('REPLACE')) {
        Add-Err $rel 'description is still the template placeholder'
    }

    # tags
    if (-not $d.ContainsKey('tags') -or @($d['tags']).Count -eq 0) {
        Add-Err $rel 'missing required frontmatter field: tags (non-empty list)'
    }
    else {
        foreach ($tag in @($d['tags'])) {
            if ($tag -eq 'replace-me') { Add-Err $rel 'tags still contain the template placeholder'; continue }
            if ($tag -notmatch $kebabTag) { Add-Err $rel ('tag "{0}" is not lowercase kebab-case' -f $tag) }
        }
    }

    # generated: both by and at
    if (-not $d.ContainsKey('generated')) {
        Add-Err $rel 'missing required frontmatter field: generated (block with by and at)'
    }
    elseif ($d['generated'] -isnot [hashtable]) {
        Add-Err $rel 'generated must be a block mapping - by and at on indented lines, not the flow { } form'
    }
    else {
        $gen = $d['generated']
        if (-not $gen.ContainsKey('by') -or [string]::IsNullOrWhiteSpace([string]$gen['by']) -or ([string]$gen['by']).Contains('{{')) {
            Add-Err $rel 'generated.by is required (actor convention, constitution section 3)'
        }
        if (-not $gen.ContainsKey('at') -or [string]::IsNullOrWhiteSpace([string]$gen['at'])) {
            Add-Err $rel 'generated.at is required (date, constitution section 3)'
        }
        elseif (-not (Test-IsoDate ([string]$gen['at']))) {
            Add-Err $rel ('generated.at "{0}" is not a real ISO date' -f $gen['at'])
        }
    }

    # body: H1 then mandatory Summary, followed by the kind's minimum semantic sections
    $body = @()
    if ($fm.ContainsKey('bodyStart') -and $fm.bodyStart -lt $lines.Count) {
        $body = @($lines[$fm.bodyStart..($lines.Count - 1)])
    }
    $nonBlank = @($body | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($nonBlank.Count -lt 1 -or $nonBlank[0] -notmatch '^#\s+\S') {
        Add-Err $rel 'body must begin with one H1 title (constitution section 3)'
    }
    if ($nonBlank.Count -lt 2 -or $nonBlank[1] -cne '## Summary') {
        Add-Err $rel 'the first body section after the H1 must be exactly "## Summary" (constitution section 3)'
    }
    else {
        $summaryIndex = [Array]::IndexOf($body, '## Summary')
        $nextHeading = $body.Count
        for ($j = $summaryIndex + 1; $j -lt $body.Count; $j++) {
            if ($body[$j] -match '^##\s+') { $nextHeading = $j; break }
        }
        $summaryText = @()
        if ($nextHeading -gt ($summaryIndex + 1)) {
            $summaryText = @($body[($summaryIndex + 1)..($nextHeading - 1)] | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and -not $_.TrimStart().StartsWith('<!--')
            })
        }
        if ($summaryText.Count -eq 0) {
            Add-Err $rel 'Summary section is empty'
        }
    }
    if ($d.ContainsKey('type') -and $requiredSections.ContainsKey([string]$d['type'])) {
        foreach ($section in $requiredSections[[string]$d['type']]) {
            if ($body -cnotcontains ('## ' + $section)) {
                Add-Err $rel ('missing required {0} section: ## {1}' -f $d['type'], $section)
            }
        }
    }

    # links: every relative target must exist (constitution section 1 amendment 6, section 3)
    foreach ($target in (Get-MarkdownLinks $body)) {
        $resolved = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($doc.DirectoryName, $target))
        if (-not (Test-Path -LiteralPath $resolved)) {
            Add-Err $rel ('broken link: {0}' -f $target)
        }
        else {
            # exact-casing check: Windows resolves case-insensitively, ubuntu CI does not
            $actual = (Get-Item -LiteralPath $resolved -Force).FullName.TrimEnd('\', '/')
            if ([string]::CompareOrdinal($actual, $resolved.TrimEnd('\', '/')) -ne 0) {
                Add-Err $rel ('link casing does not match the file on disk: {0}' -f $target)
            }
            $linkTargets += $actual
        }
    }
}

# --- Orphan assets: every asset is linked from at least one doc (constitution section 5) ---
foreach ($asset in $assetFiles) {
    if ($linkTargets -notcontains $asset) {
        Add-Err (Get-RelativeDocPath $docsRoot $asset) 'orphan asset - no concept doc links to it (constitution section 5)'
    }
}

# --- Report ---
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Output $_ }
    Write-Output ('LINT FAILED: {0} violation(s) across {1} document(s).' -f $errors.Count, $docs.Count)
    exit 1
}
Write-Output ('LINT OK: {0} document(s), 0 violations.' -f $docs.Count)
exit 0
