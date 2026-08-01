# Documentation engine shared helpers. Part of the engine (constitution section 9):
# changed only on the repository owner's explicit request.
# Dot-sourced by lint.ps1, regen.ps1, scaffold.ps1, and rename.ps1. Compatible with Windows PowerShell 5.1 and pwsh.

Set-StrictMode -Version 2.0

# Kind directory -> required frontmatter Type value. Order here is the canonical root-index order.
$Script:KindDirs = [ordered]@{
    'runbooks'     = 'Runbook'
    'reference'    = 'Reference'
    'decisions'    = 'Decision'
    'explanations' = 'Explanation'
    'plans'        = 'Plan'
    'design'       = 'Design'
}

$Script:KindQuestions = @{
    'runbooks'     = 'How do I perform this operation?'
    'reference'    = 'What is the fact?'
    'decisions'    = 'Why is it this way?'
    'explanations' = 'How does this work?'
    'plans'        = 'What do we intend?'
    'design'       = 'What should this conform to?'
}

$Script:ReservedDirs = @('_system', '_intake')

function Get-DocsRoot {
    # scripts live at docs/_system/scripts -> docs root is two levels up.
    # Two Join-Path hops rather than one '..\..' literal: a backslash is an ordinary
    # filename character on Linux, where CI runs these scripts under pwsh.
    return (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') '..')).Path
}

function Get-SystemRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-RepoRoot {
    return (Split-Path -Parent (Get-DocsRoot))
}

function Remove-Quotes([string]$v) {
    if ($v.Length -ge 2) {
        if (($v[0] -eq '"' -and $v[$v.Length-1] -eq '"') -or ($v[0] -eq "'" -and $v[$v.Length-1] -eq "'")) {
            return $v.Substring(1, $v.Length - 2)
        }
    }
    return $v
}

function ConvertFrom-Frontmatter {
    # Minimal parser for the constrained frontmatter contract (constitution section 3).
    # Returns @{ ok; error; data; keys } where data maps top-level keys to:
    # string (scalar), string[] (flow/block list), or hashtable (nested block).
    param([string[]]$Lines)

    if ($null -eq $Lines -or $Lines.Count -lt 3 -or $Lines[0].TrimEnd() -ne '---') {
        return @{ ok = $false; error = 'missing frontmatter (file must open with ---)' }
    }
    $end = -1
    for ($i = 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].TrimEnd() -eq '---') { $end = $i; break }
    }
    if ($end -lt 0) { return @{ ok = $false; error = 'unterminated frontmatter (no closing ---)' } }

    $data = @{}
    $keys = @()
    $i = 1
    while ($i -lt $end) {
        $line = $Lines[$i]
        if ($line.Trim() -eq '' -or $line.TrimStart().StartsWith('#')) { $i++; continue }
        if ($line -match '^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$') {
            $key = $Matches[1]
            $val = $Matches[2].Trim()
            $keys += $key
            if ($val -eq '') {
                # nested block: indented mapping lines or "- " list entries
                $child = @{}
                $list = @()
                $i++
                while ($i -lt $end -and $Lines[$i] -match '^\s+\S') {
                    $cl = $Lines[$i].Trim()
                    if ($cl.StartsWith('- ')) {
                        $list += $cl.Substring(2).Trim()
                    }
                    elseif ($cl -match '^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$') {
                        $child[$Matches[1]] = Remove-Quotes $Matches[2].Trim()
                    }
                    $i++
                }
                if ($list.Count -gt 0) { $data[$key] = $list } else { $data[$key] = $child }
                continue
            }
            elseif ($val -match '^[>|]') {
                # folded/literal block scalars would silently misparse - reject loudly
                return @{ ok = $false; error = ('folded/literal block scalar not supported (key: {0}) - use a plain or quoted value' -f $key) }
            }
            elseif ($val -match '^\[(.*)\]$') {
                # flow list: [a, b, c]
                $items = @()
                foreach ($part in $Matches[1].Split(',')) {
                    $p = (Remove-Quotes $part.Trim())
                    if ($p -ne '') { $items += $p }
                }
                $data[$key] = $items
            }
            elseif ($val -match '^\{.*\}$') {
                # bare flow mapping (e.g. verified: { by: x, at: y }) - kept as raw string; presence is enough
                $data[$key] = $val
            }
            else {
                $data[$key] = Remove-Quotes $val
            }
        }
        $i++
    }
    return @{ ok = $true; data = $data; keys = $keys; bodyStart = $end + 1 }
}

function Get-TreeDocs {
    # Every concept doc in the knowledge tree: .md files under the kind directories,
    # excluding index.md and anything inside assets/ folders.
    param([string]$DocsRoot)
    $docs = @()
    foreach ($kind in $Script:KindDirs.Keys) {
        $kindPath = Join-Path $DocsRoot $kind
        if (-not (Test-Path -LiteralPath $kindPath)) { continue }
        $found = Get-ChildItem -LiteralPath $kindPath -Recurse -File -Filter '*.md' -Force | Where-Object {
            $_.Name -ne 'index.md' -and $_.Directory.Name -ne 'assets'
        }
        if ($null -ne $found) { $docs += @($found) }
    }
    return $docs
}

function Get-RelativeDocPath {
    param([string]$DocsRoot, [string]$FullPath)
    $rel = $FullPath.Substring($DocsRoot.Length).TrimStart('\', '/')
    return $rel.Replace('\', '/')
}

function Get-MarkdownLinks {
    # Relative link targets from a markdown body (skips absolute URLs, anchors, mailto).
    param([string[]]$BodyLines)
    $targets = @()
    foreach ($line in $BodyLines) {
        foreach ($m in [regex]::Matches($line, '\[[^\]]*\]\(([^)\s]+)\)')) {
            $t = $m.Groups[1].Value
            $t = $t.Split('#')[0]   # drop anchor
            if ($t -eq '') { continue }
            if ($t -match '^[a-zA-Z][a-zA-Z0-9+.-]*:') { continue }  # scheme: http, https, mailto...
            $targets += [uri]::UnescapeDataString($t)   # %20 etc. decoded before resolution
        }
    }
    return $targets
}

function Write-Utf8LfFile {
    # Deterministic output: UTF-8 without BOM, LF line endings.
    param([string]$Path, [string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Compare-NormalizedContent {
    # True when contents match after newline normalization (git autocrlf tolerance).
    param([string]$Expected, [string]$Actual)
    $e = $Expected.Replace("`r`n", "`n")
    $a = $Actual.Replace("`r`n", "`n")
    return ($e -eq $a)
}

# ===========================================================================
# Agent-platform adapters (constitution section 9)
# ===========================================================================
# The single authoritative statement of which files belong to which platform.
# configure-platform.ps1, remove-platform.ps1, check-adapters.ps1, uninstall.ps1,
# upgrade.ps1, and CI-workflow generation all read this map. Nothing restates it -
# the map existing in several places with several scopes is what produced stranded
# adapters, narrowed upgrades, and unverified CI globs.
#
# Owned files are written and deleted whole at OttoDoc-specific paths. They carry no
# generated-by stamp: a file is OttoDoc's only when its path appears in this map AND
# its content matches what the installed engine renders for that path. Anything else
# sitting at a known path is reported and left untouched.
#
# Block files sit at paths the owner and other tools also use. OttoDoc contributes a
# delimited block, creates the file only when it is absent, and owns nothing else in
# it. There the markers are the proof of ownership, so a block is stripped by marker
# whether or not its content still matches canon.

$Script:SupportedPlatforms = @('Claude', 'Codex', 'Cursor')

$Script:PlatformAdapters = [ordered]@{
    'Claude' = [ordered]@{
        Owned = [ordered]@{
            'integrations/claude/agents/doc-coordinator.md' = '.claude/agents/doc-coordinator.md'
            'integrations/claude/agents/doc-author.md'      = '.claude/agents/doc-author.md'
            'integrations/claude/agents/doc-reviewer.md'    = '.claude/agents/doc-reviewer.md'
            'integrations/claude/skills/doc/SKILL.md'       = '.claude/skills/doc/SKILL.md'
        }
        BlockSource = 'integrations/claude/CLAUDE.md'
        BlockTarget = 'CLAUDE.md'
    }
    'Codex' = [ordered]@{
        Owned = [ordered]@{
            'integrations/codex/skills/documentation/SKILL.md' = '.agents/skills/documentation/SKILL.md'
            'integrations/codex/agents/doc-coordinator.toml'   = '.codex/agents/doc-coordinator.toml'
            'integrations/codex/agents/doc-author.toml'        = '.codex/agents/doc-author.toml'
            'integrations/codex/agents/doc-reviewer.toml'      = '.codex/agents/doc-reviewer.toml'
        }
        BlockSource = 'integrations/codex/AGENTS.md'
        BlockTarget = 'AGENTS.md'
    }
    'Cursor' = [ordered]@{
        Owned = [ordered]@{
            'integrations/cursor/rules/documentation.mdc'       = '.cursor/rules/documentation.mdc'
            'integrations/cursor/skills/documentation/SKILL.md' = '.cursor/skills/documentation/SKILL.md'
            'integrations/cursor/agents/doc-coordinator.md'     = '.cursor/agents/doc-coordinator.md'
            'integrations/cursor/agents/doc-author.md'          = '.cursor/agents/doc-author.md'
            'integrations/cursor/agents/doc-reviewer.md'        = '.cursor/agents/doc-reviewer.md'
        }
        BlockSource = ''
        BlockTarget = ''
    }
}

# CI enforcement is common to every configuration and is generated from the
# configured set rather than copied.
$Script:WorkflowSource = 'integrations/github-actions/docs.yml'
$Script:WorkflowTarget = '.github/workflows/docs.yml'

# Only the bare tokens are load-bearing. The surrounding marker prose is for humans
# and may be reworded by a later engine version without orphaning installed blocks.
$Script:BlockBeginToken = 'ottodoc:begin'
$Script:BlockEndToken = 'ottodoc:end'

function Get-PlatformOwnedPaths {
    # source path (relative to docs/_system) -> target path (relative to the repo root)
    param([string]$Platform)
    return $Script:PlatformAdapters[$Platform]['Owned']
}

function Get-PlatformBlockTarget {
    # Repo-relative path of the platform's shared file, or '' when it has none.
    param([string]$Platform)
    return [string]$Script:PlatformAdapters[$Platform]['BlockTarget']
}

function Get-PlatformBlockSource {
    param([string]$Platform)
    return [string]$Script:PlatformAdapters[$Platform]['BlockSource']
}

function Select-OrderedPlatforms {
    # De-duplicate and return in map order, so every generated artifact is deterministic
    # regardless of the order platforms were configured in.
    param([string[]]$Names)
    $result = @()
    foreach ($platform in $Script:SupportedPlatforms) {
        if ($Names -contains $platform) { $result += $platform }
    }
    return $result
}

function Get-ConfiguredPlatforms {
    # The configured set is installed state, read from the generated CI workflow - the
    # one OttoDoc-owned file that lives outside docs/_system/ and therefore survives the
    # wholesale engine replacement performed by upgrade.ps1.
    #
    # This is deliberately weaker than the ownership rule used for deletion. During an
    # upgrade the engine is replaced before anything else runs, so every installed
    # adapter is stale against new canon by definition; a content-match detector would
    # report the empty set and refresh nothing.
    param([string]$RepoRoot)

    $workflow = Join-Path $RepoRoot $Script:WorkflowTarget
    if (-not (Test-Path -LiteralPath $workflow -PathType Leaf)) { return @() }

    $text = [System.IO.File]::ReadAllText($workflow)
    $found = @()

    $record = [regex]::Match($text, '(?m)^#\s*ottodoc-platforms:\s*(.*)$')
    if ($record.Success) {
        foreach ($part in $record.Groups[1].Value.Split(',')) {
            $name = $part.Trim()
            if ($Script:SupportedPlatforms -contains $name) { $found += $name }
        }
        return @(Select-OrderedPlatforms $found)
    }

    # Pre-additive installations recorded the single configured platform only in the
    # check step. Read that form too, or the first upgrade from an older engine detects
    # nothing and silently refreshes no adapters.
    foreach ($legacy in [regex]::Matches($text, 'configure-platform\.ps1\s+-Platform\s+([A-Za-z]+)')) {
        $name = $legacy.Groups[1].Value
        if ($Script:SupportedPlatforms -contains $name) { $found += $name }
    }
    return @(Select-OrderedPlatforms $found)
}

function Get-GeneratedWorkflow {
    # Renders .github/workflows/docs.yml for a configured set.
    #
    # Only the recorded platform list varies. The path globs stay broad on purpose:
    # narrowing them to the configured platforms would stop CI from firing on an adapter
    # belonging to a platform that is not configured, which is exactly the orphan
    # check-adapters.ps1 exists to catch.
    param([string]$SystemRoot, [string[]]$Platforms)

    $source = Join-Path $SystemRoot $Script:WorkflowSource
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw ('canonical source missing: docs/_system/{0}' -f $Script:WorkflowSource)
    }
    $ordered = @(Select-OrderedPlatforms $Platforms)
    $record = '(none)'
    if ($ordered.Count -gt 0) { $record = ($ordered -join ', ') }
    return ([System.IO.File]::ReadAllText($source).Replace("`r`n", "`n").Replace('{{PLATFORMS}}', $record))
}

function Get-CanonicalAdapter {
    # The exact bytes OttoDoc would write to an owned target, and the yardstick the
    # ownership rule measures an on-disk file against.
    param([string]$SystemRoot, [string]$SourceRelative)
    $source = Join-Path $SystemRoot $SourceRelative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw ('canonical source missing: docs/_system/{0}' -f $SourceRelative)
    }
    return ([System.IO.File]::ReadAllText($source).Replace("`r`n", "`n"))
}

# ---------------------------------------------------------------------------
# Marker blocks in shared files
# ---------------------------------------------------------------------------

function Find-OttodocBlock {
    # Locates OttoDoc's block by bare token. Returns
    # @{ found; start; end; error } with zero-based line indexes.
    param([string[]]$Lines)

    $starts = @()
    $ends = @()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -like ('*' + $Script:BlockBeginToken + '*')) { $starts += $i }
        elseif ($Lines[$i] -like ('*' + $Script:BlockEndToken + '*')) { $ends += $i }
    }

    if ($starts.Count -eq 0 -and $ends.Count -eq 0) {
        return @{ found = $false; start = -1; end = -1; error = '' }
    }
    if ($starts.Count -gt 1 -or $ends.Count -gt 1) {
        # Only a bad merge produces this. Resolving it silently would discard content.
        return @{ found = $false; start = -1; end = -1; error = 'contains more than one OttoDoc block' }
    }
    if ($starts.Count -ne 1 -or $ends.Count -ne 1) {
        return @{ found = $false; start = -1; end = -1; error = 'contains an unterminated OttoDoc block' }
    }
    if ($ends[0] -lt $starts[0]) {
        return @{ found = $false; start = -1; end = -1; error = 'OttoDoc end marker precedes its begin marker' }
    }
    return @{ found = $true; start = $starts[0]; end = $ends[0]; error = '' }
}

function Get-OttodocBlock {
    # The installed block including its markers, or '' when the file carries none.
    # Throws on a malformed block rather than guessing.
    param([string]$Content)
    $lines = @($Content.Replace("`r`n", "`n").Split("`n"))
    $found = Find-OttodocBlock -Lines $lines
    if ($found['error'] -ne '') { throw $found['error'] }
    if (-not $found['found']) { return '' }
    return (($lines[$found['start']..$found['end']]) -join "`n")
}

function Set-OttodocBlock {
    # Full-file content with $Block installed: replacing the existing block in place, or
    # appended below whatever the owner already wrote.
    param([string]$Content, [string]$Block)

    $blockLines = @($Block.Replace("`r`n", "`n").TrimEnd("`n").Split("`n"))
    if ([string]::IsNullOrEmpty($Content)) { return (($blockLines -join "`n") + "`n") }

    $lines = @($Content.Replace("`r`n", "`n").Split("`n"))
    $found = Find-OttodocBlock -Lines $lines
    if ($found['error'] -ne '') { throw $found['error'] }

    if ($found['found']) {
        $result = @()
        if ($found['start'] -gt 0) { $result += $lines[0..($found['start'] - 1)] }
        $result += $blockLines
        if ($found['end'] -lt ($lines.Count - 1)) { $result += $lines[($found['end'] + 1)..($lines.Count - 1)] }
        return (($result -join "`n"))
    }

    $head = ($lines -join "`n").TrimEnd("`n")
    if ($head.Trim() -eq '') { return (($blockLines -join "`n") + "`n") }
    return ($head + "`n`n" + ($blockLines -join "`n") + "`n")
}

function Remove-OttodocBlock {
    # Returns @{ changed; content; empty } - content with the block removed, and whether
    # anything of the owner's survives it.
    param([string]$Content)

    $lines = @($Content.Replace("`r`n", "`n").Split("`n"))
    $found = Find-OttodocBlock -Lines $lines
    if ($found['error'] -ne '') { throw $found['error'] }
    if (-not $found['found']) {
        return @{ changed = $false; content = $Content; empty = ($Content.Trim() -eq '') }
    }

    $result = @()
    if ($found['start'] -gt 0) { $result += $lines[0..($found['start'] - 1)] }
    if ($found['end'] -lt ($lines.Count - 1)) { $result += $lines[($found['end'] + 1)..($lines.Count - 1)] }
    $remaining = ($result -join "`n")
    $isEmpty = ($remaining.Trim() -eq '')
    if (-not $isEmpty) { $remaining = $remaining.TrimEnd("`n") + "`n" }
    return @{ changed = $true; content = $remaining; empty = $isEmpty }
}

function Remove-LegacyWholeFileAdapter {
    # Before shared files carried a delimited block, OttoDoc generated AGENTS.md whole and
    # refused to run when the file was not its own - so the marker it wrote on the first
    # line is proof it owned the entire file. Translating that ownership into a block
    # means dropping the legacy content; otherwise every installation upgraded from that
    # engine carries the old instructions duplicated above its new block forever.
    param([string]$Content)
    if ([string]::IsNullOrEmpty($Content)) { return $Content }
    foreach ($line in @($Content.Replace("`r`n", "`n").Split("`n"))) {
        if ($line.Trim() -eq '') { continue }
        if ($line.Trim() -like '<!-- Generated documentation-engine adapter*') { return '' }
        return $Content
    }
    return $Content
}

function Get-SharedFileStyle {
    # Shared files belong to the owner. Preserve their newline convention and BOM so
    # contributing or stripping a block does not rewrite every other line in their diff.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @{ UseCrLf = $false; HasBom = $false }
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [System.IO.File]::ReadAllText($Path)
    return @{ UseCrLf = ($text.Contains("`r`n")); HasBom = $hasBom }
}

function Write-SharedFile {
    param([string]$Path, [string]$Content, $Style)
    $out = $Content.Replace("`r`n", "`n")
    if ($Style['UseCrLf']) { $out = $out.Replace("`n", "`r`n") }
    $enc = New-Object System.Text.UTF8Encoding([bool]$Style['HasBom'])
    [System.IO.File]::WriteAllText($Path, $out, $enc)
}

# ---------------------------------------------------------------------------
# Decommission
# ---------------------------------------------------------------------------

function Remove-EmptyParentDirectory {
    # Walks up from a deleted file removing directories the deletion emptied, stopping
    # at the repository root or the first directory that still holds something.
    param([string]$RepoRoot, [string]$StartDirectory)

    $root = (Resolve-Path -LiteralPath $RepoRoot).Path.TrimEnd('\', '/')
    $current = $StartDirectory
    while (-not [string]::IsNullOrEmpty($current)) {
        if (-not (Test-Path -LiteralPath $current -PathType Container)) { break }
        $resolved = (Resolve-Path -LiteralPath $current).Path.TrimEnd('\', '/')
        if ($resolved -eq $root) { break }
        if (-not $resolved.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { break }
        if (@(Get-ChildItem -LiteralPath $resolved -Force).Count -ne 0) { break }
        Remove-Item -LiteralPath $resolved -Force
        $current = Split-Path -Parent $resolved
    }
}

function Remove-PlatformFiles {
    # The shared decommission routine: remove-platform.ps1 calls it for one platform and
    # uninstall.ps1 for every supported platform. Returns
    # @{ removed = @(); skipped = @() } where skipped names files at known paths that
    # OttoDoc did not write and therefore will not delete.
    param([string]$RepoRoot, [string]$SystemRoot, [string]$Platform)

    $removed = @()
    $skipped = @()

    foreach ($sourceRelative in (Get-PlatformOwnedPaths $Platform).Keys) {
        $targetRelative = (Get-PlatformOwnedPaths $Platform)[$sourceRelative]
        $target = Join-Path $RepoRoot $targetRelative
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { continue }

        $expected = Get-CanonicalAdapter -SystemRoot $SystemRoot -SourceRelative $sourceRelative
        $actual = [System.IO.File]::ReadAllText($target)
        if (-not (Compare-NormalizedContent $expected $actual)) {
            $skipped += ('{0}: not written by OttoDoc (content does not match canon) - left in place' -f $targetRelative)
            continue
        }
        Remove-Item -LiteralPath $target -Force
        Remove-EmptyParentDirectory -RepoRoot $RepoRoot -StartDirectory (Split-Path -Parent $target)
        $removed += $targetRelative
    }

    $blockTarget = Get-PlatformBlockTarget $Platform
    if ($blockTarget -ne '') {
        $target = Join-Path $RepoRoot $blockTarget
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $style = Get-SharedFileStyle -Path $target
            $content = [System.IO.File]::ReadAllText($target)
            try {
                $stripped = Remove-OttodocBlock -Content $content
            }
            catch {
                $skipped += ('{0}: {1} - left in place' -f $blockTarget, $_.Exception.Message)
                $stripped = $null
            }
            if ($null -ne $stripped) {
                if ($stripped['changed']) {
                    if ($stripped['empty']) {
                        Remove-Item -LiteralPath $target -Force
                        $removed += $blockTarget
                    }
                    else {
                        Write-SharedFile -Path $target -Content $stripped['content'] -Style $style
                        $removed += ('{0} (OttoDoc block only)' -f $blockTarget)
                    }
                }
            }
        }
    }

    return @{ removed = $removed; skipped = $skipped }
}
