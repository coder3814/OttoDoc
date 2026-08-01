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
    # scripts live at docs/_system/scripts -> docs root is two levels up
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
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
