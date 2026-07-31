# Configures one explicitly requested agent platform from the portable documentation engine.
# Part of the engine (constitution section 9): changed only on the repository owner's explicit request.
#
#   configure-platform.ps1 -Platform Claude
#   configure-platform.ps1 -Platform Codex
#   configure-platform.ps1 -Platform Cursor
#   configure-platform.ps1 -Platform Claude -Check

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Claude', 'Codex', 'Cursor')]
    [string]$Platform,

    [switch]$Check
)

. (Join-Path $PSScriptRoot 'common.ps1')

$docsRoot = Get-DocsRoot
$repoRoot = Split-Path -Parent $docsRoot
$systemRoot = Split-Path -Parent $PSScriptRoot

$adapters = [ordered]@{}
switch ($Platform) {
    'Claude' {
        $adapters['integrations/claude/agents/doc-coordinator.md'] = '.claude/agents/doc-coordinator.md'
        $adapters['integrations/claude/agents/doc-author.md']      = '.claude/agents/doc-author.md'
        $adapters['integrations/claude/agents/doc-reviewer.md']    = '.claude/agents/doc-reviewer.md'
        $adapters['integrations/claude/skills/doc/SKILL.md']       = '.claude/skills/doc/SKILL.md'
    }
    'Codex' {
        $adapters['integrations/codex/AGENTS.md']                    = 'AGENTS.md'
        $adapters['integrations/codex/skills/documentation/SKILL.md'] = '.agents/skills/documentation/SKILL.md'
        $adapters['integrations/codex/agents/doc-coordinator.toml'] = '.codex/agents/doc-coordinator.toml'
        $adapters['integrations/codex/agents/doc-author.toml']      = '.codex/agents/doc-author.toml'
        $adapters['integrations/codex/agents/doc-reviewer.toml']    = '.codex/agents/doc-reviewer.toml'
    }
    'Cursor' {
        $adapters['integrations/cursor/rules/documentation.mdc']     = '.cursor/rules/documentation.mdc'
        $adapters['integrations/cursor/skills/documentation/SKILL.md'] = '.cursor/skills/documentation/SKILL.md'
        $adapters['integrations/cursor/agents/doc-coordinator.md']  = '.cursor/agents/doc-coordinator.md'
        $adapters['integrations/cursor/agents/doc-author.md']       = '.cursor/agents/doc-author.md'
        $adapters['integrations/cursor/agents/doc-reviewer.md']     = '.cursor/agents/doc-reviewer.md'
    }
}

# CI enforcement is common to every platform configuration.
$adapters['integrations/github-actions/docs.yml'] = '.github/workflows/docs.yml'

$drift = New-Object System.Collections.Generic.List[string]

foreach ($sourceRel in $adapters.Keys) {
    $targetRel = $adapters[$sourceRel]
    $source = Join-Path $systemRoot $sourceRel
    $target = Join-Path $repoRoot $targetRel

    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        Write-Output ('PLATFORM CONFIGURATION FAILED: canonical source missing: docs/_system/{0}' -f $sourceRel)
        exit 1
    }

    $expected = [System.IO.File]::ReadAllText($source).Replace("`r`n", "`n").Replace('{{PLATFORM}}', $Platform)

    if ($Check) {
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            $drift.Add(('{0}: missing' -f $targetRel))
            continue
        }
        $actual = [System.IO.File]::ReadAllText($target)
        if (-not (Compare-NormalizedContent $expected $actual)) {
            $drift.Add(('{0}: stale' -f $targetRel))
        }
        continue
    }

    if (Test-Path -LiteralPath $target -PathType Leaf) {
        $actual = [System.IO.File]::ReadAllText($target)
        if (-not (Compare-NormalizedContent $expected $actual) -and $actual -notmatch '(?i)generated[^\r\n]*adapter') {
            Write-Output ('PLATFORM CONFIGURATION FAILED: {0} already exists and is not a generated documentation-engine adapter. Merge the canonical pointer manually or move the existing file, then retry.' -f $targetRel)
            exit 1
        }
    }

    $targetDir = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
    Write-Utf8LfFile -Path $target -Content $expected
    Write-Output ('CONFIGURED [{0}]: {1}' -f $Platform, $targetRel)
}

if ($Check) {
    if ($drift.Count -gt 0) {
        $drift | ForEach-Object { Write-Output $_ }
        Write-Output ('PLATFORM CHECK FAILED [{0}]: {1} adapter(s) out of sync. Run configure-platform.ps1 -Platform {0}.' -f $Platform, $drift.Count)
        exit 1
    }
    Write-Output ('PLATFORM CHECK OK [{0}]: {1} adapter(s) match docs/_system.' -f $Platform, $adapters.Count)
    exit 0
}

Write-Output ('PLATFORM CONFIGURATION OK [{0}]: {1} adapter(s) configured.' -f $Platform, $adapters.Count)
exit 0
