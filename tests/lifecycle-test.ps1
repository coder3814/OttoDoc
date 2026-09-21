# End-to-end test of the OttoDoc lifecycle commands in a scratch git repository.
# Lives outside docs/_system/ so it never ships with the engine.
#
#   powershell.exe -File tests/lifecycle-test.ps1
#
# Exercises the supported 90%: install, check, additive configure with owner content
# in a shared file, the owner-owned ignore file, remove down to zero platforms, upgrade from a local archive with
# the clean-tree gate, uninstall, and byte-identical reinstall.

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$sourceRepo = Split-Path -Parent $PSScriptRoot
$work = Join-Path $env:TEMP ('ottodoc-test-' + [guid]::NewGuid().ToString('N'))
$repo = Join-Path $work 'repo'
$scripts = Join-Path $repo 'docs\_system\scripts'
$script:failures = 0

function Assert {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { Write-Output ('PASS: ' + $Message) }
    else { Write-Output ('FAIL: ' + $Message); $script:failures++ }
}

function Read-Text([string]$Path) { return [System.IO.File]::ReadAllText($Path) }
function Read-Record { return (Read-Text (Join-Path $repo 'docs\.ottodoc')).Trim() }
function Read-IgnoreLines { return @((Read-Text (Join-Path $repo 'docs\.ottodocignore')).Replace("`r`n", "`n").Split("`n")) }

New-Item -ItemType Directory -Path $repo -Force | Out-Null
Push-Location $repo
try {
    git init -q
    git config user.email 'test@example.com'
    git config user.name 'Lifecycle Test'

    New-Item -ItemType Directory -Path (Join-Path $repo 'docs') | Out-Null
    Copy-Item -Recurse -LiteralPath (Join-Path $sourceRepo 'docs\_system') -Destination (Join-Path $repo 'docs\_system')

    # --- install Codex ---
    & (Join-Path $scripts 'bootstrap.ps1') -Platform Codex | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'bootstrap -Platform Codex exits 0'
    Assert ((Read-Record) -eq 'platforms: Codex') 'record is "platforms: Codex"'
    Assert (Test-Path (Join-Path $repo '.agents\skills\ottodoc-assess\SKILL.md')) 'Codex owned file written'
    Assert ((Read-Text (Join-Path $repo 'AGENTS.md')).Contains('ottodoc:begin')) 'AGENTS.md carries the block'
    Assert (Test-Path (Join-Path $repo '.github\workflows\docs.yml')) 'CI workflow written'
    Assert ((Read-Text (Join-Path $repo 'docs\.gitattributes')).Contains('* text=auto eol=lf')) 'docs/.gitattributes written'

    & (Join-Path $scripts 'check-adapters.ps1') | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'check passes after install'

    # --- install seeds the ignore file with every platform's surfaces, not only Codex's ---
    $ignorePath = Join-Path $repo 'docs\.ottodocignore'
    Assert (Test-Path $ignorePath) 'install seeds docs/.ottodocignore'
    $seeded = @('/CLAUDE.md', '/.claude/', '/AGENTS.md', '/.codex/', '/.agents/', '/.cursor/', '/.github/workflows/docs.yml')
    Assert (@($seeded | Where-Object { (Read-IgnoreLines) -cnotcontains $_ }).Count -eq 0) 'the seed lists every supported platform and the workflow'
    Assert ((Read-IgnoreLines) -cnotcontains '/docs/' -and (Read-IgnoreLines) -cnotcontains 'docs/') 'the built-in boundary is not listed in the file'

    # The file is the owner's: one pattern added, one seeded pattern deliberately removed.
    $owned = @(Read-IgnoreLines | Where-Object { $_ -cne '/.cursor/' }) -join "`n"
    [System.IO.File]::WriteAllText($ignorePath, $owned.TrimEnd("`n") + "`n/ToDo.md`n")

    # --- owner content around the block survives configure ---
    $agentsPath = Join-Path $repo 'AGENTS.md'
    [System.IO.File]::WriteAllText($agentsPath, "# Owner heading`n`n" + (Read-Text $agentsPath) + "`nOwner trailing note.`n")

    # Owner settings that must survive the hook merge.
    $settingsPath = Join-Path $repo '.claude\settings.json'
    New-Item -ItemType Directory -Path (Join-Path $repo '.claude') -Force | Out-Null
    [System.IO.File]::WriteAllText($settingsPath, '{"permissions":{"allow":["Bash"]}}')

    & (Join-Path $scripts 'configure-platform.ps1') -Platform Claude | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'configure -Platform Claude exits 0'
    Assert ((Read-Record) -eq 'platforms: Claude, Codex') 'record is "platforms: Claude, Codex"'
    $agents = Read-Text $agentsPath
    Assert ($agents.Contains('# Owner heading') -and $agents.Contains('Owner trailing note.')) 'owner content in AGENTS.md survives configure'
    Assert ($agents.Contains('ottodoc:begin')) 'AGENTS.md block still present'
    Assert ((Test-Path (Join-Path $repo 'CLAUDE.md')) -and (Read-Text (Join-Path $repo 'CLAUDE.md')).Contains('ottodoc:begin')) 'CLAUDE.md block appears'
    Assert (Test-Path (Join-Path $repo '.claude\skills\ottodoc-uninstall\SKILL.md')) 'Claude per-verb slash skill written'
    Assert (Test-Path (Join-Path $repo '.claude\hooks\doc-routing.js')) 'Claude routing hook script written'
    $settings = Read-Text $settingsPath
    Assert ($settings.Contains('"Bash"')) 'owner settings survive the hook merge'
    Assert ($settings.Contains('doc-routing.js') -and $settings.Contains('UserPromptSubmit')) 'settings.json carries the routing hook'
    Assert ((Read-IgnoreLines) -ccontains '/ToDo.md') 'owner pattern survives configure'
    Assert ((Read-IgnoreLines) -cnotcontains '/.cursor/') 'configuring Claude does not restore another platform''s removed pattern'
    Assert (@(Read-IgnoreLines | Where-Object { $_ -ceq '/CLAUDE.md' }).Count -eq 1) 'configure does not duplicate a pattern already listed'

    if (Get-Command node -ErrorAction SilentlyContinue) {
        $injected = (& node (Join-Path $repo '.claude\hooks\doc-routing.js')) -join "`n"
        Assert ($injected.Contains('/ToDo.md') -and $injected.Contains('/CLAUDE.md')) 'the hook injects the current ignore patterns'
    }

    & (Join-Path $scripts 'check-adapters.ps1') | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'check passes with two platforms'

    # --- a stripped hook registration is drift; converge re-merges it ---
    [System.IO.File]::WriteAllText($settingsPath, '{"permissions":{"allow":["Bash"]}}')
    & (Join-Path $scripts 'check-adapters.ps1') | Out-Null
    Assert ($LASTEXITCODE -ne 0) 'check fails when the settings hook is stripped'
    & (Join-Path $scripts 'configure-platform.ps1') -Platform Claude | Out-Null
    $settings = Read-Text $settingsPath
    Assert ($settings.Contains('"Bash"') -and $settings.Contains('doc-routing.js')) 'converge re-merges the hook beside owner settings'

    # --- refreshing a configured platform never restores a pattern the owner removed ---
    $ignoreWithout = @(Read-IgnoreLines | Where-Object { $_ -cne '/CLAUDE.md' }) -join "`n"
    [System.IO.File]::WriteAllText($ignorePath, $ignoreWithout)
    & (Join-Path $scripts 'configure-platform.ps1') -Platform Claude | Out-Null
    Assert ((Read-Text $ignorePath) -eq $ignoreWithout) 'refreshing Claude leaves the ignore file byte-identical'

    # --- a missing ignore file is reported by lint and reseeded whole, never partially ---
    Remove-Item -LiteralPath $ignorePath -Force
    $out = (& (Join-Path $scripts 'lint.ps1')) -join "`n"
    Assert ($out.Contains('IGNORE: docs/.ottodocignore is missing')) 'lint reports a missing ignore file'
    if (Get-Command node -ErrorAction SilentlyContinue) {
        $injected = (& node (Join-Path $repo '.claude\hooks\doc-routing.js')) -join "`n"
        Assert ($LASTEXITCODE -eq 0 -and $injected.Contains('are never part of it. ')) 'the hook states the built-in boundary alone when the file is missing'
    }
    & (Join-Path $scripts 'configure-platform.ps1') -Platform Claude | Out-Null
    Assert (@($seeded | Where-Object { (Read-IgnoreLines) -cnotcontains $_ }).Count -eq 0) 'configure reseeds a missing ignore file whole'
    [System.IO.File]::WriteAllText($ignorePath, $ignoreWithout)

    # --- converge leaves a settings file that already carries the hook untouched ---
    $settingsBefore = Read-Text $settingsPath
    & (Join-Path $scripts 'configure-platform.ps1') -Platform Claude | Out-Null
    Assert ((Read-Text $settingsPath) -eq $settingsBefore) 'converge is idempotent on settings.json'

    # --- removal takes OttoDoc's entry and nothing else: a group it shares with
    #     another tool keeps that tool's entry, and a foreign group that carries no
    #     hook list at all must survive untouched rather than read as one OttoDoc
    #     just emptied ---
    [System.IO.File]::WriteAllText($settingsPath, '{"hooks":{"UserPromptSubmit":[{"matcher":"Bash"},{"hooks":[{"type":"command","command":"node .claude/hooks/doc-routing.js"},{"type":"command","command":"echo theirs"}]}]}}')
    & (Join-Path $scripts 'check-adapters.ps1') | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'a hand-merged shared hook group reads as converged'
    & (Join-Path $scripts 'remove-platform.ps1') -Platform Claude | Out-Null
    Assert (Test-Path $settingsPath) 'removal does not delete a settings.json holding owner groups'
    $settings = Read-Text $settingsPath
    Assert (-not $settings.Contains('doc-routing.js')) 'removal strips OttoDoc''s entry from the shared group'
    Assert ($settings.Contains('echo theirs')) 'the other tool''s entry in the shared group survives removal'
    Assert ($settings.Contains('"matcher"')) 'a foreign group carrying no hook list survives removal'
    & (Join-Path $scripts 'configure-platform.ps1') -Platform Claude | Out-Null

    # --- an empty or null value at the hook path is merged into, not crashed on ---
    [System.IO.File]::WriteAllText($settingsPath, '{"hooks":{"UserPromptSubmit":[]}}')
    & (Join-Path $scripts 'configure-platform.ps1') -Platform Claude | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'converge survives an empty UserPromptSubmit array'
    Assert ((Read-Text $settingsPath).Contains('doc-routing.js')) 'hook merged into an empty UserPromptSubmit array'

    # --- a settings file OttoDoc cannot own is refused, never rewritten: both the
    #     unparseable case and valid JSON that is not an object ---
    [System.IO.File]::WriteAllText($settingsPath, '{not json')
    & (Join-Path $scripts 'configure-platform.ps1') -Platform Claude | Out-Null
    Assert ($LASTEXITCODE -ne 0) 'converge refuses an unparseable settings.json'
    Assert ((Read-Text $settingsPath) -eq '{not json') 'the refused settings.json is left untouched'

    [System.IO.File]::WriteAllText($settingsPath, '[{"a":1}]')
    & (Join-Path $scripts 'configure-platform.ps1') -Platform Claude | Out-Null
    Assert ($LASTEXITCODE -ne 0) 'converge refuses a settings.json that is a JSON array'
    Assert ((Read-Text $settingsPath) -eq '[{"a":1}]') 'the refused JSON array is left untouched'

    # --- but an unconfigured platform is not blocked by a file it has no stake in ---
    & (Join-Path $scripts 'remove-platform.ps1') -Platform Claude | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'removing Claude ignores a settings.json it cannot own'
    [System.IO.File]::WriteAllText($settingsPath, '{"permissions":{"allow":["Bash"]}}')
    & (Join-Path $scripts 'configure-platform.ps1') -Platform Claude | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'configure Claude again after the refusal'

    # --- check actually detects drift, and converge repairs it ---
    $ownedPath = Join-Path $repo '.claude\skills\ottodoc-check\SKILL.md'
    [System.IO.File]::WriteAllText($ownedPath, 'tampered')
    & (Join-Path $scripts 'check-adapters.ps1') | Out-Null
    Assert ($LASTEXITCODE -ne 0) 'check fails on a tampered owned file'
    & (Join-Path $scripts 'configure-platform.ps1') -Platform Claude | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'converge repairs the tampered file'
    & (Join-Path $scripts 'check-adapters.ps1') | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'check passes again after repair'

    # --- remove Codex: files gone, block stripped, owner content intact ---
    $ignoreBeforeRemove = Read-Text $ignorePath
    & (Join-Path $scripts 'remove-platform.ps1') -Platform Codex | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'remove -Platform Codex exits 0'
    Assert ((Read-Text $ignorePath) -eq $ignoreBeforeRemove) 'remove leaves the ignore file byte-identical'
    Assert (-not (Test-Path (Join-Path $repo '.agents'))) '.agents adapter tree removed'
    Assert (-not (Test-Path (Join-Path $repo '.codex'))) '.codex adapter tree removed'
    $agents = Read-Text $agentsPath
    Assert (-not $agents.Contains('ottodoc:begin')) 'AGENTS.md block stripped'
    Assert ($agents.Contains('# Owner heading') -and $agents.Contains('Owner trailing note.')) 'owner content in AGENTS.md intact after remove'

    # --- remove Claude: zero platforms is ordinary ---
    & (Join-Path $scripts 'remove-platform.ps1') -Platform Claude | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'remove -Platform Claude exits 0'
    Assert ((Read-Record) -eq 'platforms:') 'record shows zero platforms'
    Assert (-not (Test-Path (Join-Path $repo 'CLAUDE.md'))) 'CLAUDE.md deleted (block was all it held)'
    Assert (-not (Test-Path (Join-Path $repo '.claude\hooks\doc-routing.js'))) 'routing hook script removed'
    $settings = Read-Text $settingsPath
    Assert ($settings.Contains('"Bash"') -and -not $settings.Contains('doc-routing.js')) 'owner settings survive remove with the hook stripped'
    & (Join-Path $scripts 'check-adapters.ps1') | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'check passes with zero platforms'

    # From here the owner settings are no longer needed: delete them so the later
    # uninstall can prove a settings file OttoDoc alone created is deleted outright.
    Remove-Item -LiteralPath $settingsPath -Force
    Remove-Item -LiteralPath (Join-Path $repo '.claude') -Force

    # --- a real document, then Claude back for the upgrade test ---
    $doc = @'
---
type: Reference
title: Test fact
description: A single test fact used by the lifecycle test.
tags: [lifecycle]
generated:
  by: process:lifecycle-test
  at: 2026-08-01
---

# Test fact

## Summary

This reference exists so the lifecycle test can prove documents survive uninstall. It owns one fact, and a reader looks it up and leaves.

## Facts

The answer is 42.
'@
    [System.IO.File]::WriteAllText((Join-Path $repo 'docs\reference\test-fact.md'), $doc.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
    & (Join-Path $scripts 'regen.ps1') | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'regen accepts the test document'

    # --- lint surfaces change notes in intake as one informational line and never fails on them ---
    $out = & (Join-Path $scripts 'lint.ps1')
    Assert ($LASTEXITCODE -eq 0 -and -not (($out -join "`n").Contains('INTAKE:'))) 'lint prints no INTAKE line when intake holds no change note'
    $notePath = Join-Path $repo 'docs\_intake\change-2026-08-01-test-note.md'
    [System.IO.File]::WriteAllText($notePath, "# Change note: test`n")
    $out = & (Join-Path $scripts 'lint.ps1')
    Assert ($LASTEXITCODE -eq 0) 'lint still exits 0 with a change note in intake'
    Assert (($out -join "`n").Contains('INTAKE: 1 change note(s) awaiting processing')) 'lint prints the INTAKE line for the change note'
    Assert (($out -join "`n").Contains('IGNORE: ') -and ($out -join "`n").Contains('/ToDo.md')) 'lint prints the active ignore patterns'
    Remove-Item -LiteralPath $notePath -Force
    & (Join-Path $scripts 'configure-platform.ps1') -Platform Claude | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'configure Claude again exits 0'
    Assert ((Test-Path $settingsPath) -and (Read-Text $settingsPath).Contains('doc-routing.js')) 'settings.json created fresh when absent'

    # --- upgrade from a local archive; clean-tree gate first ---
    $pkg = Join-Path $work 'pkg\docs'
    New-Item -ItemType Directory -Path $pkg -Force | Out-Null
    Copy-Item -Recurse -LiteralPath (Join-Path $sourceRepo 'docs\_system') -Destination (Join-Path $pkg '_system')
    $zip = Join-Path $work 'ottodoc.zip'
    Compress-Archive -Path (Join-Path $work 'pkg\*') -DestinationPath $zip

    [System.IO.File]::WriteAllText((Join-Path $repo 'dirty.txt'), 'uncommitted')
    $out = & (Join-Path $scripts 'upgrade.ps1') -ArchivePath $zip
    Assert ($LASTEXITCODE -ne 0) 'upgrade refuses a dirty tree'
    Assert (($out -join "`n").Contains('UPGRADE REFUSED')) 'refusal names the clean-tree gate'
    Remove-Item (Join-Path $repo 'dirty.txt') -Force

    # The checkout a Windows owner actually has: autocrlf on, every file re-materialized
    # by Git. Without docs/.gitattributes this holds docs/ as CRLF, and the upgrade below
    # reports every file it rewrites as modified.
    git config core.autocrlf true
    git config core.safecrlf false
    git add -A
    git commit -q -m 'baseline before upgrade'
    git rm -r -q --cached .
    git reset -q --hard
    $ignoreBeforeUpgrade = Read-Text $ignorePath
    $out = & (Join-Path $scripts 'upgrade.ps1') -ArchivePath $zip
    Assert ($LASTEXITCODE -eq 0) 'upgrade from local archive exits 0'
    Assert (($out -join "`n").Contains('UPGRADE OK')) 'upgrade reports success'
    Assert ((Read-Record) -eq 'platforms: Claude') 'record survives upgrade'
    Assert (@(git status --porcelain).Count -eq 0) 'upgrading to an identical engine leaves no phantom modifications under autocrlf'
    Assert ((Read-Text $ignorePath) -eq $ignoreBeforeUpgrade) 'ignore file byte-identical after upgrade'
    & (Join-Path $scripts 'check-adapters.ps1') | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'check passes after upgrade'

    # --- upgrading a repository that has no ignore file gives it a fresh install's boundary ---
    Remove-Item -LiteralPath $ignorePath -Force
    git add -A
    git commit -q -m 'installed before the ignore file existed'
    $out = (& (Join-Path $scripts 'upgrade.ps1') -ArchivePath $zip) -join "`n"
    Assert ($LASTEXITCODE -eq 0) 'upgrade without an ignore file exits 0'
    Assert (@($seeded | Where-Object { (Read-IgnoreLines) -cnotcontains $_ }).Count -eq 0) 'upgrade seeds a missing ignore file whole'
    Assert ($out.Contains('CREATED: docs/.ottodocignore') -and $out.Contains('/CLAUDE.md')) 'upgrade announces the new boundary and its patterns'
    Assert (-not $out.Contains('is missing')) 'the upgrade''s own lint no longer reports a missing ignore file'

    # --- uninstall preserves the tree; reinstall restores the index byte-identically ---
    $indexBefore = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $repo 'docs\index.md')))

    & (Join-Path $scripts 'uninstall.ps1') | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'uninstall exits 0'
    Assert (-not (Test-Path (Join-Path $repo 'docs\_system'))) 'docs/_system removed'
    Assert (-not (Test-Path (Join-Path $repo '.github\workflows\docs.yml'))) 'CI workflow removed'
    Assert (-not (Test-Path (Join-Path $repo 'docs\.gitattributes'))) 'docs/.gitattributes removed'
    Assert (-not (Test-Path (Join-Path $repo 'docs\.ottodoc'))) 'record removed'
    Assert (-not (Test-Path $ignorePath)) 'ignore file removed'
    Assert (-not ((Test-Path (Join-Path $repo '.claude')) -or (Test-Path (Join-Path $repo 'CLAUDE.md')))) 'Claude adapters removed'
    Assert (Test-Path (Join-Path $repo 'docs\reference\test-fact.md')) 'document preserved'
    Assert (Test-Path (Join-Path $repo 'docs\index.md')) 'root index preserved'
    Assert (Test-Path (Join-Path $repo 'docs\_intake')) 'docs/_intake preserved'
    Assert (-not (Read-Text (Join-Path $repo 'docs\index.md')).Contains('Governed by')) 'governance pointer removed from root index'

    Copy-Item -Recurse -LiteralPath (Join-Path $sourceRepo 'docs\_system') -Destination (Join-Path $repo 'docs\_system')
    & (Join-Path $scripts 'bootstrap.ps1') -Platform Codex | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'reinstall exits 0'
    Assert ((Read-IgnoreLines) -ccontains '/.cursor/' -and (Read-IgnoreLines) -cnotcontains '/ToDo.md') 'reinstall seeds a fresh ignore file'
    $indexAfter = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $repo 'docs\index.md')))
    Assert ($indexBefore -eq $indexAfter) 'root index byte-identical after reinstall'
}
finally {
    Pop-Location
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}

if ($script:failures -gt 0) {
    Write-Output ('LIFECYCLE TEST FAILED: {0} assertion(s) failed.' -f $script:failures)
    exit 1
}
Write-Output 'LIFECYCLE TEST OK: every assertion passed.'
exit 0
