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

## Prompt-time obligations

The static "Using the documentation" block alone does not reliably make agents route from the knowledge tree on judgment tasks — evaluating a backlog, prioritizing work — because instructions resting in static context lose to task momentum. The same is true of filing the change note before a change lands, which competes with the momentum of shipping. Where a platform offers a prompt-time extension point, OttoDoc therefore injects both standing obligations — routing from the tree, and filing and keeping current the change note for the accumulated change — into every user prompt.

On Claude, that surface is a `UserPromptSubmit` hook: the owned script `.claude/hooks/doc-routing.js` emits both obligations as `additionalContext`, and converge merges its registration — one command entry running `node .claude/hooks/doc-routing.js` — into the shared `.claude/settings.json`. The injected text is platform-generic and complements the `CLAUDE.md` block; it does not replace it. The script keeps its original name though it now carries both obligations: the path is an owned adapter path, and renaming it would churn every installation for no functional gain.

> [!IMPORTANT]
> Project-settings hooks do not execute in headless Claude Code sessions (`claude -p`) until the project has been trusted once interactively. Open the project in an interactive session and approve the one-time prompt, or headless agents silently run without the obligations hook — changes can then land without their change note as well as unrouted.

A prompt-time obligation fires on the agent's turn, so it covers the path where the agent commits the change or raises the pull request. An owner who commits by hand after the agent's last task passes no prompt through the hook, and nothing catches a change that lands without its note, or with a note the last task never reached. The constitution's rule is stricter than this mechanism: it says the note lands with the change, however the change lands. Closing that remainder would take a commit-time extension point — on Claude, a `PreToolUse` matcher on `git commit` — and until one is configured the agent-driven path is the covered one. This is recorded here rather than left to be discovered.

Codex and Cursor currently expose no equivalent prompt-time extension point, so those platforms carry only the static block or rule — for the change note as much as for routing. That is a known, deliberate gap: when such an extension point appears, the same obligations should be injected there rather than approximated with more static text.

## Reasoning levels

Each role declares in its canonical definition under `_system/process/` the reasoning level its work demands, and the adapters render that declaration in whatever form the platform accepts. There are two levels, because there are only two kinds of work here:

- **Deep** — the most capable model available and the highest reasoning effort the platform exposes. Held by `doc-coordinator` and `doc-reviewer`: the gate that decides whether documentation is justified, and the gate that decides whether what was written is good enough to land.
- **Standard** — a capable mid-tier model at ordinary effort. Held by `doc-author`, which works from a bounded delta against supplied evidence and a template, and whose output a deep reviewer checks before it lands.

The shape is deliberate: spend on deciding and verifying, not on the step between them, and never let a role's level be decided by whatever model the owner happened to be driving when the task came up.

| Role | Level | Claude | Codex | Cursor |
|---|---|---|---|---|
| `doc-coordinator` | Deep | `model: opus`, `effort: high` | `model_reasoning_effort = "high"` | `model: inherit` |
| `doc-reviewer` | Deep | `model: opus`, `effort: high` | `model_reasoning_effort = "high"` | `model: inherit` |
| `doc-author` | Standard | `model: sonnet`, `effort: medium` | `model_reasoning_effort = "medium"` | `model: inherit` |

**What each platform can express.** Only Claude renders the declaration whole, because its `model` field takes durable family aliases — `opus` and `sonnet` name whatever currently holds those tiers, so an adapter written today still means the right thing after a model generation turns over.

Codex carries the effort half. Its per-agent `model` key takes a concrete model identifier and offers no family alias, so pinning one would bind every consuming repository to a model that dates; the key is therefore left unset and the platform's own default model applies at the declared effort.

Cursor expresses neither. Its `model` field takes `inherit` or a specific identifier, and effort rides only as a bracketed parameter on such an identifier — `claude-opus-5[effort=high]` — so there is no way to state the level without pinning. The adapters keep `model: inherit`, which means the deep roles get whatever the owner drives with and the author is not held down. This is a known gap of the same kind as the missing prompt-time extension point above, recorded rather than papered over: when Cursor offers a relative model selector, the declaration should render there.

A repository whose Claude installation lacks access to a named tier falls back to that platform's own resolution; the engine does not attempt to detect availability.

**Revisiting the assignment.** These tiers are a judgment call; if review findings start clustering on writing quality rather than on facts, raise the author.

**Owner override.** There is none by design. Agent adapter paths are owned absolutely (above), so converge overwrites a hand-edited level on the next run. Changing a level means changing the role's canonical definition and the adapters together, which is the same discipline every other process change follows.

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
