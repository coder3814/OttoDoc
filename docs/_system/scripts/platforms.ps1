# Agent-platform management: the adapter map, the record file, marker blocks, and
# the converge routine every lifecycle command shares. Canonical spec: docs/_system/lifecycle.md.
# Dot-sourced by bootstrap, configure-platform, remove-platform, check-adapters,
# uninstall, and upgrade. Compatible with Windows PowerShell 5.1 and pwsh.

. (Join-Path $PSScriptRoot 'common.ps1')

$Script:SupportedPlatforms = @('Claude', 'Codex', 'Cursor')

# Every OttoDoc command verb except install, which necessarily runs before any
# adapter exists. Each verb becomes one slash-command adapter per platform.
$Script:CommandVerbs = @(
    'assess', 'create', 'update', 'rename', 'move', 'retire', 'intake',
    'review', 'check', 'fix', 'explain',
    'upgrade', 'configure', 'remove', 'uninstall'
)

# The single authoritative statement of which files belong to which platform.
# Ownership of the target paths is absolute (lifecycle.md): converge overwrites and
# removes them without inspecting their content. SettingsTarget names a shared JSON
# settings file into which converge merges exactly one prompt-time hook registration
# (SettingsEvent running SettingsCommand); only Claude has such an extension point
# today - for the other platforms the gap is documented in lifecycle.md rather than
# approximated with more static text.
$Script:PlatformAdapters = [ordered]@{
    'Claude' = [ordered]@{
        Owned = [ordered]@{
            'integrations/claude/agents/doc-coordinator.md' = '.claude/agents/doc-coordinator.md'
            'integrations/claude/agents/doc-author.md'      = '.claude/agents/doc-author.md'
            'integrations/claude/agents/doc-reviewer.md'    = '.claude/agents/doc-reviewer.md'
            'integrations/claude/hooks/doc-routing.js'      = '.claude/hooks/doc-routing.js'
        }
        BlockSource = 'integrations/claude/CLAUDE.md'
        BlockTarget = 'CLAUDE.md'
        SettingsTarget = '.claude/settings.json'
        SettingsEvent = 'UserPromptSubmit'
        SettingsCommand = 'node .claude/hooks/doc-routing.js'
    }
    'Codex' = [ordered]@{
        Owned = [ordered]@{
            'integrations/codex/agents/doc-coordinator.toml'   = '.codex/agents/doc-coordinator.toml'
            'integrations/codex/agents/doc-author.toml'        = '.codex/agents/doc-author.toml'
            'integrations/codex/agents/doc-reviewer.toml'      = '.codex/agents/doc-reviewer.toml'
        }
        BlockSource = 'integrations/codex/AGENTS.md'
        BlockTarget = 'AGENTS.md'
        SettingsTarget = ''
        SettingsEvent = ''
        SettingsCommand = ''
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
        SettingsTarget = ''
        SettingsEvent = ''
        SettingsCommand = ''
    }
}

# The per-verb slash-command adapters: /ottodoc-<verb> on Claude and Cursor,
# $ottodoc-<verb> on Codex (which has no repository-level slash commands).
# Appended to the map here so the file lists remain a single authoritative statement.
foreach ($commandVerb in $Script:CommandVerbs) {
    $Script:PlatformAdapters['Claude']['Owned'][('integrations/claude/skills/ottodoc-{0}/SKILL.md' -f $commandVerb)] =
        ('.claude/skills/ottodoc-{0}/SKILL.md' -f $commandVerb)
    $Script:PlatformAdapters['Codex']['Owned'][('integrations/codex/skills/ottodoc-{0}/SKILL.md' -f $commandVerb)] =
        ('.agents/skills/ottodoc-{0}/SKILL.md' -f $commandVerb)
    $Script:PlatformAdapters['Cursor']['Owned'][('integrations/cursor/commands/ottodoc-{0}.md' -f $commandVerb)] =
        ('.cursor/commands/ottodoc-{0}.md' -f $commandVerb)
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
# Hook registrations in shared JSON settings files
# ---------------------------------------------------------------------------
# The JSON analogue of the marker block: in a settings file the owner may also
# use, OttoDoc owns exactly one command-hook entry, recognized by its command
# string. Everything else in the file is the owner's. JSON carries no comments,
# so there are no markers; the file is re-serialized deterministically
# (canonical two-space JSON) whenever the entry is added or removed.

function Get-JsonProperty {
    # A property value from a parsed JSON object, or $null when absent or the
    # parent is not an object. Safe under StrictMode.
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertTo-JsonStringLiteral {
    param([string]$Value)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq '"') { [void]$sb.Append('\"') }
        elseif ($ch -eq '\') { [void]$sb.Append('\\') }
        elseif ([int]$ch -lt 0x20) {
            if ($ch -eq "`b") { [void]$sb.Append('\b') }
            elseif ($ch -eq "`f") { [void]$sb.Append('\f') }
            elseif ($ch -eq "`n") { [void]$sb.Append('\n') }
            elseif ($ch -eq "`r") { [void]$sb.Append('\r') }
            elseif ($ch -eq "`t") { [void]$sb.Append('\t') }
            else { [void]$sb.Append(('\u{0:x4}' -f [int]$ch)) }
        }
        else { [void]$sb.Append($ch) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-CanonicalJson {
    # Deterministic JSON writer: two-space indent, property order preserved, no
    # unicode escaping of printable text. ConvertTo-Json is avoided because its
    # formatting and escaping differ between Windows PowerShell 5.1 and pwsh,
    # which would make the merged file depend on which shell converged it.
    param($Value, [int]$Depth = 0)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
    if ($Value -is [string] -or $Value -is [char]) { return (ConvertTo-JsonStringLiteral ([string]$Value)) }
    if ($Value -is [datetime]) {
        # pwsh's ConvertFrom-Json revives ISO-dated strings as DateTime; round-trip them.
        return (ConvertTo-JsonStringLiteral ($Value.ToString('yyyy-MM-ddTHH:mm:ss')))
    }
    if ($Value -is [System.ValueType]) {
        return [string][System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    $pad = '  ' * $Depth
    $padInner = '  ' * ($Depth + 1)
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Collections.IDictionary]) {
        $items = @($Value)
        if ($items.Count -eq 0) { return '[]' }
        $parts = @()
        foreach ($item in $items) { $parts += ($padInner + (ConvertTo-CanonicalJson $item ($Depth + 1))) }
        return ('[' + "`n" + ($parts -join (',' + "`n")) + "`n" + $pad + ']')
    }
    $properties = @($Value.PSObject.Properties)
    if ($properties.Count -eq 0) { return '{}' }
    $parts = @()
    foreach ($property in $properties) {
        $parts += ($padInner + (ConvertTo-JsonStringLiteral $property.Name) + ': ' + (ConvertTo-CanonicalJson $property.Value ($Depth + 1)))
    }
    return ('{' + "`n" + ($parts -join (',' + "`n")) + "`n" + $pad + '}')
}

function Test-OttodocSettingsHook {
    # True when the parsed settings already register OttoDoc's command under the event.
    param($Settings, [string]$EventName, [string]$Command)
    $eventGroups = Get-JsonProperty (Get-JsonProperty $Settings 'hooks') $EventName
    foreach ($group in @($eventGroups)) {
        if ($null -eq $group) { continue }
        foreach ($entry in @(Get-JsonProperty $group 'hooks')) {
            if ($null -eq $entry) { continue }
            if (((Get-JsonProperty $entry 'type') -eq 'command') -and ((Get-JsonProperty $entry 'command') -eq $Command)) {
                return $true
            }
        }
    }
    return $false
}

function Add-OttodocSettingsHook {
    # Returns the settings object with OttoDoc's hook group appended under the event,
    # leaving every other property of the owner's untouched.
    param($Settings, [string]$EventName, [string]$Command)
    if ($null -eq $Settings) { $Settings = New-Object PSObject }
    $hooks = Get-JsonProperty $Settings 'hooks'
    if ($null -eq $hooks) {
        $hooks = New-Object PSObject
        $Settings | Add-Member -MemberType NoteProperty -Name 'hooks' -Value $hooks
    }
    $entry = New-Object PSObject
    $entry | Add-Member -MemberType NoteProperty -Name 'type' -Value 'command'
    $entry | Add-Member -MemberType NoteProperty -Name 'command' -Value $Command
    $group = New-Object PSObject
    $group | Add-Member -MemberType NoteProperty -Name 'hooks' -Value @($entry)
    $eventGroups = Get-JsonProperty $hooks $EventName
    if ($null -eq $eventGroups) {
        $hooks | Add-Member -MemberType NoteProperty -Name $EventName -Value @($group)
    }
    else {
        $hooks.PSObject.Properties[$EventName].Value = @($eventGroups) + @($group)
    }
    return $Settings
}

function Remove-OttodocSettingsHook {
    # Strips OttoDoc's command entry and dissolves the containers that held only it.
    # Returns @{ changed; settings; empty } - empty when nothing of the owner's remains.
    param($Settings, [string]$EventName, [string]$Command)
    $changed = $false
    $hooks = Get-JsonProperty $Settings 'hooks'
    $eventGroups = Get-JsonProperty $hooks $EventName
    if ($null -ne $eventGroups) {
        $keptGroups = @()
        foreach ($group in @($eventGroups)) {
            if ($null -eq $group) { continue }
            $entries = @(Get-JsonProperty $group 'hooks')
            $kept = @($entries | Where-Object {
                $null -ne $_ -and -not (((Get-JsonProperty $_ 'type') -eq 'command') -and ((Get-JsonProperty $_ 'command') -eq $Command))
            })
            if ($kept.Count -ne $entries.Count) {
                $changed = $true
                # A group whose only content was OttoDoc's entry dissolves with it.
                if ($kept.Count -eq 0 -and @($group.PSObject.Properties).Count -eq 1) { continue }
                $group.PSObject.Properties['hooks'].Value = $kept
            }
            $keptGroups += , $group
        }
        if ($changed) {
            if ($keptGroups.Count -eq 0) { $hooks.PSObject.Properties.Remove($EventName) }
            else { $hooks.PSObject.Properties[$EventName].Value = $keptGroups }
            if (@($hooks.PSObject.Properties).Count -eq 0) { $Settings.PSObject.Properties.Remove('hooks') }
        }
    }
    $isEmpty = ($null -eq $Settings) -or (@($Settings.PSObject.Properties).Count -eq 0)
    return @{ changed = $changed; settings = $Settings; empty = $isEmpty }
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
    # Deletes a generated file and, best effort, every directory the deletion emptied,
    # walking upward until a directory still holds something (the repository root always does).
    param([string]$Path)
    Remove-Item -LiteralPath $Path -Force
    $parent = Split-Path -Parent $Path
    while ($parent -and (Test-Path -LiteralPath $parent -PathType Container) -and
        @(Get-ChildItem -LiteralPath $parent -Force).Count -eq 0) {
        Remove-Item -LiteralPath $parent -Force
        $parent = Split-Path -Parent $parent
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
        if ($blockTarget -ne '') {
            $target = Join-Path $RepoRoot $blockTarget
            $existing = ''
            if (Test-Path -LiteralPath $target -PathType Leaf) { $existing = [System.IO.File]::ReadAllText($target) }
            $installedBlock = Get-OttodocBlock -Content $existing -Label $blockTarget

            if ($isConfigured) {
                $expectedBlock = Get-CanonicalContent -SystemRoot $SystemRoot -SourceRelative ([string]$adapter['BlockSource'])
                if (-not (Compare-NormalizedContent $expectedBlock.TrimEnd("`n") $installedBlock.TrimEnd("`n"))) {
                    if ($installedBlock -eq '') { $drift += ('{0}: OttoDoc block missing' -f $blockTarget) } else { $drift += ('{0}: OttoDoc block stale' -f $blockTarget) }
                    if (-not $Check) {
                        $style = Get-SharedFileStyle -Path $target
                        Write-SharedFile -Path $target -Content (Set-OttodocBlock -Content $existing -Block $expectedBlock -Label $blockTarget) -Style $style
                    }
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

        $settingsTarget = [string]$adapter['SettingsTarget']
        if ($settingsTarget -ne '') {
            $target = Join-Path $RepoRoot $settingsTarget
            $eventName = [string]$adapter['SettingsEvent']
            $command = [string]$adapter['SettingsCommand']
            $settings = $null
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                $raw = [System.IO.File]::ReadAllText($target)
                if ($raw.Trim() -ne '') {
                    try { $settings = ConvertFrom-Json -InputObject $raw -ErrorAction Stop }
                    catch { throw ('{0}: not valid JSON - fix it by hand' -f $settingsTarget) }
                }
            }
            $hasHook = Test-OttodocSettingsHook -Settings $settings -EventName $eventName -Command $command

            if ($isConfigured) {
                if (-not $hasHook) {
                    $drift += ('{0}: OttoDoc hook missing' -f $settingsTarget)
                    if (-not $Check) {
                        $merged = Add-OttodocSettingsHook -Settings $settings -EventName $eventName -Command $command
                        $directory = Split-Path -Parent $target
                        if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
                        Write-Utf8LfFile -Path $target -Content ((ConvertTo-CanonicalJson $merged) + "`n")
                    }
                }
            }
            elseif ($hasHook) {
                $drift += ('{0}: OttoDoc hook belongs to unconfigured platform {1}' -f $settingsTarget, $platform)
                if (-not $Check) {
                    $stripped = Remove-OttodocSettingsHook -Settings $settings -EventName $eventName -Command $command
                    if ($stripped['empty']) { Remove-GeneratedFile -Path $target }
                    else { Write-Utf8LfFile -Path $target -Content ((ConvertTo-CanonicalJson $stripped['settings']) + "`n") }
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
