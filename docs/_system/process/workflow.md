# Documentation workflow

This is the canonical process for documentation assessment, authoring, normalization, review, and retirement. Read `docs/_system/constitution.md` first; it governs every judgment.

## Authority

Documentation-only work may inspect the repository but may modify only `docs/`. It never fixes code, tests, scripts, workflows, configuration, infrastructure, schemas, or deployed state. Validation is repository-only; never query live or external systems. Report implementation concerns in the task result and create no issue or findings file without separate authorization. The lifecycle commands specified in [`../lifecycle.md`](../lifecycle.md) are the exceptions; their authority is defined there.

## Agent interface

Every OttoDoc action except `install` is a per-verb slash command in each configured platform: `/ottodoc-<verb>` in Claude Code and Cursor, and the `ottodoc-<verb>` skill in Codex, invoked as `$ottodoc-<verb>` because Codex has no repository-level slash commands. Supported actions are `install`, `upgrade`, `configure`, `remove`, `uninstall`, `assess`, `create`, `update`, `rename`, `move`, `retire`, `intake`, `review`, `check`, `fix`, and `explain`. The prose form `OttoDoc <action>` is the portable equivalent in any supported agent interface, and the only form for `install`, which necessarily runs before any adapter exists. Treat either form as an explicit request to use this documentation engine. The agent selects the applicable workflow, roles, templates, and deterministic tooling from the action and the instructions that follow it. `Update` edits a knowledge document, and `rename` changes only a concept filename while repairing links and regenerating indexes.

### Lifecycle commands

`install`, `upgrade`, `configure`, `remove`, `uninstall`, and `check` manage the installation itself and are specified canonically in [`../lifecycle.md`](../lifecycle.md) — read it before executing one. Two workflow rules apply on top of that spec:

- A lifecycle command frequently arrives from an agent with no prior OttoDoc context. Do not assume the engine was already discovered in this session: locate it under `docs/_system/`, read `lifecycle.md`, then proceed. If `docs/_system/` is absent, OttoDoc is not installed and the correct action is `install`.
- The platform name for `configure` and `remove` is always required — never infer it, never treat a missing name as "all of them", and never escalate `remove` to `uninstall`. Confirm with the owner before invoking `uninstall`; the script itself is non-interactive so that other commands and CI may call it.

`OttoDoc intake [filename]` accepts one optional filename: one filename processes that direct child of `docs/_intake/`, while no filename processes the entire folder. Do not require users to name or invoke implementation scripts. Scripts remain available to agents, maintainers, and CI as the execution layer.

## Agent-driven work

Dispatch `doc-coordinator` after every completed system-modifying task and for agent-driven documentation work. The coordinator assesses impact itself and may conclude that no documentation change is justified. When work is needed, it dispatches `doc-author`, then a fresh-context `doc-reviewer`, re-dispatching the author with any findings for at most two revision cycles before asking the owner.

Dispatch is a call that returns. Each role delivers its report as its final response to whoever dispatched it, and the coordinator collects every result itself rather than ending its turn to wait for one. Roles never message each other by name, because a role name identifies a definition rather than a running agent.

Required documentation remains in the same change or pull request as its implementation. The coordinator, author, and reviewer retain the authority boundaries in their canonical definitions under `docs/_system/process/`.

## Human drafts

Humans may place rough documents and external material directly in the flat `docs/_intake/` folder without conforming to the final structure. Filenames must be unique; do not add directories. Placement is inert. `OttoDoc intake <filename>` routes that one direct child through the coordinator; `OttoDoc intake` routes every file currently in intake. Reject paths, directories, multiple filenames, and filename patterns. The author preserves intended meaning and human-provided external facts while normalizing kind, scope, summary-first structure, concision, links, and frontmatter; material ambiguity returns to the owner.

## Direct maintainer workflow

Maintainers may scaffold or edit documentation directly when they need the underlying execution layer. Agent normalization and fresh-context review follow before completion.

- Scaffold: `docs/_system/scripts/scaffold.ps1 -Kind <runbook|reference|decision|explanation|plan|design> -Slug <kebab-slug> -Title "<Title>" -Actor "<actor>" [-Subject <kebab-subject>]`
- Rename: `docs/_system/scripts/rename.ps1 -Path <knowledge-file> -Slug <new-kebab-slug>`
- Lint: `docs/_system/scripts/lint.ps1`
- Regenerate: `docs/_system/scripts/regen.ps1`
- Prove current: `docs/_system/scripts/regen.ps1 -Check`
- Verify adapters: `docs/_system/scripts/check-adapters.ps1`

Never hand-edit an `index.md`. A material content change updates `generated`; a typo-only or relocation-only change does not. Moves and deletions include fixing inbound links and dissolving empty subject folders. Documents and regenerated indexes land together.
