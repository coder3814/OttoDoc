# Lifecycle

This is the management spec for an OttoDoc installation: how the engine and its platform adapters are installed, kept current, and removed. The documentation law lives in [`constitution.md`](constitution.md); nothing here changes it. `docs/_system/` is the complete portable engine — copying that one directory transfers the whole system.

## The record

`docs/.ottodoc` is the single authoritative statement of which agent platforms are configured:

```
platforms: Claude, Codex
```

It lives outside `_system/` so it survives engine replacement, is committed like any other file, and is removed only by uninstall. Zero configured platforms is an ordinary state — the engine still works and CI still runs. Which platforms a repository uses is owner intent: it is always read from the record, never guessed from files lying around.

## The adapter map

Every OttoDoc verb except `install` — the fifteen command verbs `assess`, `create`, `update`, `rename`, `move`, `retire`, `intake`, `review`, `check`, `fix`, `explain`, `upgrade`, `configure`, `remove`, and `uninstall` — is generated as one slash-command adapter per platform: a `/ottodoc-<verb>` skill on Claude, an `ottodoc-<verb>` skill on Codex (invoked as `$ottodoc-<verb>`, since Codex has no repository-level slash commands), and a `/ottodoc-<verb>` command on Cursor. `install` has no adapter because it necessarily runs before any adapter exists.

| Platform | Owned files - generated whole | Shared files - OttoDoc block or hook entry only |
|---|---|---|
| Claude | `.claude/agents/doc-coordinator.md`, `.claude/agents/doc-author.md`, `.claude/agents/doc-reviewer.md`, `.claude/hooks/doc-routing.js`, `.claude/skills/ottodoc-<verb>/SKILL.md` per command verb | `CLAUDE.md`, `.claude/settings.json` |
| Codex | `.codex/agents/doc-coordinator.toml`, `.codex/agents/doc-author.toml`, `.codex/agents/doc-reviewer.toml`, `.agents/skills/ottodoc-<verb>/SKILL.md` per command verb | `AGENTS.md` |
| Cursor | `.cursor/rules/documentation.mdc`, `.cursor/skills/documentation/SKILL.md`, `.cursor/agents/doc-coordinator.md`, `.cursor/agents/doc-author.md`, `.cursor/agents/doc-reviewer.md`, `.cursor/commands/ottodoc-<verb>.md` per command verb | none |
| every configuration | `.github/workflows/docs.yml` | - |

**Ownership of mapped paths is absolute.** The owned paths above belong to OttoDoc: converge overwrites and removes them without inspecting their content. Do not put your own files at these paths, and never edit a generated file directly — the next converge erases the edit.

## Prompt-time routing

The static "Using the documentation" block alone does not reliably make agents route from the knowledge tree on judgment tasks — evaluating a backlog, prioritizing work — because instructions resting in static context lose to task momentum. Where a platform offers a prompt-time extension point, OttoDoc therefore also injects the routing obligation into every user prompt.

On Claude, that surface is a `UserPromptSubmit` hook: the owned script `.claude/hooks/doc-routing.js` emits the obligation as `additionalContext`, and converge merges its registration — one command entry running `node .claude/hooks/doc-routing.js` — into the shared `.claude/settings.json`. The injected text is platform-generic and complements the `CLAUDE.md` block; it does not replace it.

> [!IMPORTANT]
> Project-settings hooks do not execute in headless Claude Code sessions (`claude -p`) until the project has been trusted once interactively. Open the project in an interactive session and approve the one-time prompt, or headless agents silently run without the routing hook.

Codex and Cursor currently expose no equivalent prompt-time extension point, so those platforms carry only the static block or rule. That is a known, deliberate gap: when such an extension point appears, the same obligation should be injected there rather than approximated with more static text.

## Converge

Every lifecycle command shares one routine: read the record, then make disk match it for each supported platform. Configured — write the platform's owned files from the canon under `_system/integrations/` and upsert its block in the shared file. Not configured — delete its owned files and strip its block, deleting the shared file only when the block was all it held. The CI workflow is rendered unconditionally. `-Check` computes the same desired state and reports differences without writing anything, exiting nonzero on drift.

**Marker blocks.** In shared files (`CLAUDE.md`, `AGENTS.md`) OttoDoc owns exactly one block delimited by lines containing the bare tokens `ottodoc:begin` and `ottodoc:end`. Everything outside the block is the owner's and is preserved — content, newline convention, and BOM alike. A duplicate or unterminated block is a hard error, resolved by hand rather than guessed at.

**Settings hooks.** In shared JSON settings files (`.claude/settings.json`) OttoDoc owns exactly one hook registration, recognized by its command string; every other setting is the owner's and its value is preserved. JSON carries no comment markers, so when the entry is added or removed the whole file is re-serialized as canonical two-space JSON — the owner's values survive, but not their formatting. A file already carrying the registration is left untouched byte for byte. When the registration was all the file held, removal deletes the file.

A settings file that is not a JSON object — unparseable, or a JSON array or scalar — is a hard error for the platform that owns it, resolved by hand; converge refuses rather than rewriting a file it cannot read. A platform that is *not* configured ignores such a file entirely, exactly as a shared markdown file carrying no OttoDoc block is ignored: an owner who never configured that platform is never blocked by it.

## Commands

| Command | Script | Effect |
|---|---|---|
| install | `scripts/bootstrap.ps1 -Platform <name>` | Copy `_system/` into `<repo>/docs/_system`, then: create kind directories and `_intake/`, write the record, converge, lint + regen |
| upgrade | `scripts/upgrade.ps1` | Replace `docs/_system/` wholesale from the OttoDoc repository, then converge, lint + regen |
| configure | `scripts/configure-platform.ps1 -Platform <name>` | Add the platform to the record, converge |
| remove | `scripts/remove-platform.ps1 -Platform <name>` | Remove the platform from the record, converge; removing the last platform is fine |
| uninstall | `scripts/uninstall.ps1` | Converge to zero platforms, then delete the workflow, the record, `docs/_system/`, and the root index's governance pointer — every document, index, asset, and `_intake/` survives |
| check | `scripts/check-adapters.ps1` | Converge `-Check`: report drift, change nothing |

Lifecycle commands may modify only the engine, the mapped adapter paths, OttoDoc's block in shared files, the record, the workflow, and the generated indexes; nothing else in the repository is theirs to touch. Install fails closed: pre-existing nonconforming documents abort it with no existing content modified. Upgrade requires a clean git tree and refuses to run over uncommitted changes.

**Git is the undo.** Every command leaves its result as an uncommitted diff for review; none commits or pushes, and none keeps backups or performs rollback. If a command fails partway, inspect the diff and use `git restore` to return to the last commit.
