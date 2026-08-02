# Agent-platform management: the adapter map, the record file, marker blocks, and
# the converge routine every lifecycle command shares. Canonical spec: docs/_system/lifecycle.md.
# Dot-sourced by bootstrap, configure-platform, remove-platform, check-adapters,
# uninstall, and upgrade. Compatible with Windows PowerShell 5.1 and pwsh.

. (Join-Path $PSScriptRoot 'common.ps1')

$Script:SupportedPlatforms = @('Claude', 'Codex', 'Cursor')

# The single authoritative statement of which files belong to which platform.
# Ownership of the target paths is absolute (lifecycle.md): converge overwrites and
# removes them without inspecting their content.
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

$Script:WorkflowSource = 'integrations/github-actions/docs.yml'
$Script:WorkflowTarget = '.github/workflows/docs.yml'
$Script:RecordTarget = 'docs/.ottodoc'

# Only the bare tokens are load-bearing. The surrounding marker prose is for humans
# and may be reworded by a later engine version without orphaning installed blocks.
$Script:BlockBeginToken = 'ottodoc:begin'
$Script:BlockEndToken = 'ottodoc:end'

# ---------------------------------------------------------------------------
# The record file
# ---------------------------------------------------------------------------

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

function Read-OttodocRecord {
    # The configured platform set, from docs/.ottodoc. A missing record reads as the
    # empty set; unknown names are ignored.
    param([string]$RepoRoot)
    $path = Join-Path $RepoRoot $Script:RecordTarget
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    $found = @()
    $m = [regex]::Match([System.IO.File]::ReadAllText($path), '(?m)^platforms:\s*(.*)$')
    if ($m.Success) {
        foreach ($part in $m.Groups[1].Value.Split(',')) { $found += $part.Trim() }
    }
    return @(Select-OrderedPlatforms $found)
}

function Write-OttodocRecord {
    param([string]$RepoRoot, [string[]]$Platforms)
    $ordered = @(Select-OrderedPlatforms $Platforms)
    $content = ('platforms: ' + ($ordered -join ', ')).TrimEnd() + "`n"
    Write-Utf8LfFile -Path (Join-Path $RepoRoot $Script:RecordTarget) -Content $content
}

# ---------------------------------------------------------------------------
# Marker blocks in shared files
# ---------------------------------------------------------------------------

function Find-OttodocBlock {
    # Locates OttoDoc's block by bare token. Throws on a duplicate or unterminated
    # block (lifecycle.md: hard error, resolved by hand). Returns @{ found; start; end }
    # with zero-based line indexes.
    param([string[]]$Lines, [string]$Label)
    $starts = @()
    $ends = @()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -like ('*' + $Script:BlockBeginToken + '*')) { $starts += $i }
        elseif ($Lines[$i] -like ('*' + $Script:BlockEndToken + '*')) { $ends += $i }
    }
    if ($starts.Count -eq 0 -and $ends.Count -eq 0) {
        return @{ found = $false; start = -1; end = -1 }
    }
    if ($starts.Count -ne 1 -or $ends.Count -ne 1 -or $ends[0] -lt $starts[0]) {
        throw ('{0}: malformed OttoDoc block (duplicate, unterminated, or out of order markers) - fix it by hand' -f $Label)
    }
    return @{ found = $true; start = $starts[0]; end = $ends[0] }
}

function Get-OttodocBlock {
    # The installed block including its markers, or '' when the file carries none.
    param([string]$Content, [string]$Label)
    $lines = @($Content.Replace("`r`n", "`n").Split("`n"))
    $found = Find-OttodocBlock -Lines $lines -Label $Label
    if (-not $found['found']) { return '' }
    return (($lines[$found['start']..$found['end']]) -join "`n")
}

function Set-OttodocBlock {
    # Full-file content with $Block installed: replacing the existing block in place, or
    # appended below whatever the owner already wrote.
    param([string]$Content, [string]$Block, [string]$Label)
    $blockLines = @($Block.Replace("`r`n", "`n").TrimEnd("`n").Split("`n"))
    if ([string]::IsNullOrEmpty($Content)) { return (($blockLines -join "`n") + "`n") }

    $lines = @($Content.Replace("`r`n", "`n").Split("`n"))
    $found = Find-OttodocBlock -Lines $lines -Label $Label
    if ($found['found']) {
        $result = @()
        if ($found['start'] -gt 0) { $result += $lines[0..($found['start'] - 1)] }
        $result += $blockLines
        if ($found['end'] -lt ($lines.Count - 1)) { $result += $lines[($found['end'] + 1)..($lines.Count - 1)] }
        return ($result -join "`n")
    }

    $head = ($lines -join "`n").TrimEnd("`n")
    if ($head.Trim() -eq '') { return (($blockLines -join "`n") + "`n") }
    return ($head + "`n`n" + ($blockLines -join "`n") + "`n")
}

function Remove-OttodocBlock {
    # Returns @{ changed; content; empty } - content with the block removed, and whether
    # anything of the owner's survives it.
    param([string]$Content, [string]$Label)
    $lines = @($Content.Replace("`r`n", "`n").Split("`n"))
    $found = Find-OttodocBlock -Lines $lines -Label $Label
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
# Converge
# ---------------------------------------------------------------------------

function Get-CanonicalContent {
    # The exact bytes OttoDoc writes to a generated target, read from canon under
    # docs/_system/. A missing source means the engine itself is broken.
    param([string]$SystemRoot, [string]$SourceRelative)
    $source = Join-Path $SystemRoot $SourceRelative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw ('canonical source missing: docs/_system/{0}' -f $SourceRelative)
    }
    return ([System.IO.File]::ReadAllText($source).Replace("`r`n", "`n"))
}

function Remove-GeneratedFile {
    # Deletes a generated file and, best effort, the directory the deletion emptied.
    param([string]$Path)
    Remove-Item -LiteralPath $Path -Force
    $parent = Split-Path -Parent $Path
    if ((Test-Path -LiteralPath $parent -PathType Container) -and
        @(Get-ChildItem -LiteralPath $parent -Force).Count -eq 0) {
        Remove-Item -LiteralPath $parent -Force
    }
}

function Invoke-PlatformConverge {
    # Makes the repository match the record (lifecycle.md): for each supported platform,
    # configured -> owned files written from canon and block upserted; not configured ->
    # owned files removed and block stripped. The CI workflow is rendered unconditionally.
    # With -Check, reports every difference without writing and returns the drift lines.
    param([string]$RepoRoot, [string]$SystemRoot, [switch]$Check)

    $configured = @(Read-OttodocRecord -RepoRoot $RepoRoot)
    $drift = @()

    foreach ($platform in $Script:SupportedPlatforms) {
        $isConfigured = ($configured -contains $platform)
        $adapter = $Script:PlatformAdapters[$platform]

        foreach ($sourceRelative in $adapter['Owned'].Keys) {
            $targetRelative = $adapter['Owned'][$sourceRelative]
            $target = Join-Path $RepoRoot $targetRelative
            $present = (Test-Path -LiteralPath $target -PathType Leaf)

            if ($isConfigured) {
                $expected = Get-CanonicalContent -SystemRoot $SystemRoot -SourceRelative $sourceRelative
                if ($present -and (Compare-NormalizedContent $expected ([System.IO.File]::ReadAllText($target)))) { continue }
                if ($present) { $drift += ('{0}: stale' -f $targetRelative) } else { $drift += ('{0}: missing' -f $targetRelative) }
                if (-not $Check) {
                    $directory = Split-Path -Parent $target
                    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
                    Write-Utf8LfFile -Path $target -Content $expected
                }
            }
            elseif ($present) {
                $drift += ('{0}: belongs to unconfigured platform {1}' -f $targetRelative, $platform)
                if (-not $Check) { Remove-GeneratedFile -Path $target }
            }
        }

        $blockTarget = [string]$adapter['BlockTarget']
        if ($blockTarget -eq '') { continue }
        $target = Join-Path $RepoRoot $blockTarget
        $existing = ''
        if (Test-Path -LiteralPath $target -PathType Leaf) { $existing = [System.IO.File]::ReadAllText($target) }
        $installedBlock = Get-OttodocBlock -Content $existing -Label $blockTarget

        if ($isConfigured) {
            $expectedBlock = Get-CanonicalContent -SystemRoot $SystemRoot -SourceRelative ([string]$adapter['BlockSource'])
            if (Compare-NormalizedContent $expectedBlock.TrimEnd("`n") $installedBlock.TrimEnd("`n")) { continue }
            if ($installedBlock -eq '') { $drift += ('{0}: OttoDoc block missing' -f $blockTarget) } else { $drift += ('{0}: OttoDoc block stale' -f $blockTarget) }
            if (-not $Check) {
                $style = Get-SharedFileStyle -Path $target
                Write-SharedFile -Path $target -Content (Set-OttodocBlock -Content $existing -Block $expectedBlock -Label $blockTarget) -Style $style
            }
        }
        elseif ($installedBlock -ne '') {
            $drift += ('{0}: OttoDoc block belongs to unconfigured platform {1}' -f $blockTarget, $platform)
            if (-not $Check) {
                $stripped = Remove-OttodocBlock -Content $existing -Label $blockTarget
                if ($stripped['empty']) { Remove-GeneratedFile -Path $target }
                else {
                    $style = Get-SharedFileStyle -Path $target
                    Write-SharedFile -Path $target -Content $stripped['content'] -Style $style
                }
            }
        }
    }

    $workflowPath = Join-Path $RepoRoot $Script:WorkflowTarget
    $expectedWorkflow = Get-CanonicalContent -SystemRoot $SystemRoot -SourceRelative $Script:WorkflowSource
    $workflowCurrent = (Test-Path -LiteralPath $workflowPath -PathType Leaf) -and
        (Compare-NormalizedContent $expectedWorkflow ([System.IO.File]::ReadAllText($workflowPath)))
    if (-not $workflowCurrent) {
        if (Test-Path -LiteralPath $workflowPath -PathType Leaf) { $drift += ('{0}: stale' -f $Script:WorkflowTarget) } else { $drift += ('{0}: missing' -f $Script:WorkflowTarget) }
        if (-not $Check) {
            $workflowDirectory = Split-Path -Parent $workflowPath
            if (-not (Test-Path -LiteralPath $workflowDirectory)) { New-Item -ItemType Directory -Path $workflowDirectory -Force | Out-Null }
            Write-Utf8LfFile -Path $workflowPath -Content $expectedWorkflow
        }
    }

    return @{ configured = $configured; drift = $drift }
}
