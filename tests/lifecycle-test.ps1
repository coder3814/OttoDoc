# End-to-end test of the OttoDoc lifecycle commands in a scratch git repository.
# Lives outside docs/_system/ so it never ships with the engine.
#
#   powershell.exe -File tests/lifecycle-test.ps1
#
# Exercises the supported 90%: install, check, additive configure with owner content
# in a shared file, remove down to zero platforms, upgrade from a local archive with
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

    & (Join-Path $scripts 'check-adapters.ps1') | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'check passes after install'

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

    & (Join-Path $scripts 'check-adapters.ps1') | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'check passes with two platforms'

    # --- a stripped hook registration is drift; converge re-merges it ---
    [System.IO.File]::WriteAllText($settingsPath, '{"permissions":{"allow":["Bash"]}}')
    & (Join-Path $scripts 'check-adapters.ps1') | Out-Null
    Assert ($LASTEXITCODE -ne 0) 'check fails when the settings hook is stripped'
    & (Join-Path $scripts 'configure-platform.ps1') -Platform Claude | Out-Null
    $settings = Read-Text $settingsPath
    Assert ($settings.Contains('"Bash"') -and $settings.Contains('doc-routing.js')) 'converge re-merges the hook beside owner settings'

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
    & (Join-Path $scripts 'remove-platform.ps1') -Platform Codex | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'remove -Platform Codex exits 0'
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

    git add -A
    git commit -q -m 'baseline before upgrade'
    $out = & (Join-Path $scripts 'upgrade.ps1') -ArchivePath $zip
    Assert ($LASTEXITCODE -eq 0) 'upgrade from local archive exits 0'
    Assert (($out -join "`n").Contains('UPGRADE OK')) 'upgrade reports success'
    Assert ((Read-Record) -eq 'platforms: Claude') 'record survives upgrade'
    & (Join-Path $scripts 'check-adapters.ps1') | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'check passes after upgrade'

    # --- uninstall preserves the tree; reinstall restores the index byte-identically ---
    $indexBefore = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Join-Path $repo 'docs\index.md')))

    & (Join-Path $scripts 'uninstall.ps1') | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'uninstall exits 0'
    Assert (-not (Test-Path (Join-Path $repo 'docs\_system'))) 'docs/_system removed'
    Assert (-not (Test-Path (Join-Path $repo '.github\workflows\docs.yml'))) 'CI workflow removed'
    Assert (-not (Test-Path (Join-Path $repo 'docs\.ottodoc'))) 'record removed'
    Assert (-not ((Test-Path (Join-Path $repo '.claude')) -or (Test-Path (Join-Path $repo 'CLAUDE.md')))) 'Claude adapters removed'
    Assert (Test-Path (Join-Path $repo 'docs\reference\test-fact.md')) 'document preserved'
    Assert (Test-Path (Join-Path $repo 'docs\index.md')) 'root index preserved'
    Assert (Test-Path (Join-Path $repo 'docs\_intake')) 'docs/_intake preserved'
    Assert (-not (Read-Text (Join-Path $repo 'docs\index.md')).Contains('Governed by')) 'governance pointer removed from root index'

    Copy-Item -Recurse -LiteralPath (Join-Path $sourceRepo 'docs\_system') -Destination (Join-Path $repo 'docs\_system')
    & (Join-Path $scripts 'bootstrap.ps1') -Platform Codex | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'reinstall exits 0'
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
