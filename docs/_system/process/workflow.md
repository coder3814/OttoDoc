# Documentation workflow

This is the canonical process for documentation assessment, authoring, normalization, review, and retirement. Read `docs/_system/constitution.md` first; it governs every judgment.

## Authority

Documentation-only work may inspect the repository but may modify only `docs/`. It never fixes code, tests, scripts, workflows, configuration, infrastructure, schemas, or deployed state. Validation is repository-only; never query live or external systems. Report implementation concerns in the task result and create no issue or findings file without separate authorization. The explicit lifecycle commands `install`, `upgrade`, `configure`, `remove`, and `uninstall` are the exceptions: they may retrieve or delete the OttoDoc engine and write, refresh, or remove only its canonical engine, its generated agent-platform adapters, its own delimited block inside shared always-on files, its generated indexes, and its documentation-check workflow.

## Agent interface

`OttoDoc <action>` is the portable, first-class command form in any supported agent interface. Supported actions are `install`, `upgrade`, `configure`, `remove`, `uninstall`, `assess`, `create`, `update`, `rename`, `move`, `retire`, `intake`, `review`, `check`, `fix`, and `explain`. Treat a request beginning with an OttoDoc command as an explicit request to use this documentation engine. The agent selects the applicable workflow, roles, templates, and deterministic tooling from the action and the instructions that follow it. `Install` adds the OttoDoc engine to a repository, `upgrade` replaces an installed engine with the newest canonical files and refreshes every configured platform, `configure` adds or refreshes generated files for one named agent platform, `remove` decommissions one named agent platform, `uninstall` removes the engine and every platform while leaving the documentation, `update` edits a knowledge document, and `rename` changes only a concept filename while repairing links and regenerating indexes.

### Upgrade workflow

For `OttoDoc upgrade`, invoke `docs/_system/scripts/upgrade.ps1` from the repository root. It takes no platform argument: the configured set is installed state, which the script reads for itself, and every configured platform is refreshed. Do not ask the owner which platform is configured, and do not ask the user to invoke the script.

The upgrader retrieves the `main` branch of `https://github.com/coder3814/OttoDoc`, validates the archive shape, fully replaces `docs/_system/` so obsolete engine files do not survive, refreshes every configured platform, regenerates indexes, and runs lint, adapter, and index drift checks. It backs up the previous engine, generated platform files, and indexes during execution and restores them if validation fails. Report the source, the platforms refreshed, the validation result, and the resulting repository diff. Do not commit or push unless the user separately requests it.

### Configure workflow

`OttoDoc configure <Platform>` adds one platform to the configured set and leaves every other platform exactly as it is. Invoke `docs/_system/scripts/configure-platform.ps1 -Platform <platform>` from the repository root.

This command frequently arrives from an agent with no prior OttoDoc context — the owner has opened a second tool in a repository OttoDoc was installed into from a different one, and pasted the command out of the README. Do not assume the engine was already discovered in this session: locate it under `docs/_system/` first, read `workflow.md` and `constitution.md`, then proceed. If `docs/_system/` is absent, OttoDoc is not installed and the correct action is `install`, not `configure`.

### Remove and uninstall workflow

`OttoDoc remove <Platform>` decommissions exactly one platform: `docs/_system/scripts/remove-platform.ps1 -Platform <platform>`. The platform name is always required. Never infer it, never treat a missing name as "all of them", and never escalate to `uninstall` — if the owner did not name a platform, ask which one. Removing the only configured platform is allowed and is not a reason to offer uninstalling: it leaves OttoDoc installed with zero configured platforms, which is an ordinary state, and a platform can be restored at any time by configuring one.

`OttoDoc uninstall` removes the engine and every platform: `docs/_system/scripts/uninstall.ps1`. Confirm with the owner before invoking it, and say plainly what it does — every document, index, asset, and `docs/_intake/` is preserved, while `docs/_system/`, the workflow, every adapter, and the root index's governance pointer are removed. The script itself is non-interactive so that other commands and CI may call it.

Both commands delete a file at a known adapter path only when its content matches the canonical engine, and report anything that does not instead of touching it. Pass those skipped files on to the owner rather than removing them by hand. Both leave the result as an uncommitted diff for review; do not commit or push unless the user separately requests it.

`OttoDoc intake [filename]` accepts one optional filename: one filename processes that direct child of `docs/_intake/`, while no filename processes the entire folder. Do not require users to name or invoke implementation scripts. Scripts remain available to agents, maintainers, and CI as the execution layer.

## Agent-driven work

Dispatch `doc-coordinator` after every completed system-modifying task and for agent-driven documentation work. The coordinator assesses impact itself and may conclude that no documentation change is justified. When work is needed, it dispatches `doc-author`, then a fresh-context `doc-reviewer`, returning findings to the author for at most two revision cycles before asking the owner.

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
