# Documentation workflow

This is the canonical process for documentation assessment, authoring, normalization, review, and retirement. Read `docs/_system/constitution.md` first; it governs every judgment.

## Authority

Documentation-only work may inspect the repository but may modify only `docs/`. It never fixes code, tests, scripts, workflows, configuration, infrastructure, schemas, or deployed state. Validation is repository-only; never query live or external systems. Report implementation concerns in the task result and create no issue or findings file without separate authorization. The explicit lifecycle commands `install`, `upgrade`, and `configure` are the exceptions: they may retrieve the OttoDoc engine and write only its canonical engine, generated agent-platform adapters, generated indexes, and documentation-check workflow.

## Agent interface

`OttoDoc <action>` is the portable, first-class command form in any supported agent interface. Supported actions are `install`, `upgrade`, `configure`, `assess`, `create`, `update`, `move`, `retire`, `intake`, `review`, `check`, `fix`, and `explain`. Treat a request beginning with an OttoDoc command as an explicit request to use this documentation engine. The agent selects the applicable workflow, roles, templates, and deterministic tooling from the action and the instructions that follow it. `Install` adds the OttoDoc engine to a repository, `upgrade` replaces an installed engine with the newest canonical files, `configure` selects or refreshes generated files for a named agent platform, and `update` edits a knowledge document.

### Upgrade workflow

For `OttoDoc upgrade`, determine which single platform is currently configured from OttoDoc's generated adapter markers. If exactly one of Claude, Codex, or Cursor is evident, invoke `docs/_system/scripts/upgrade.ps1 -Platform <platform>` from the repository root. Ask the owner to name the platform only when it is absent or ambiguous. Do not ask the user to invoke the script.

The upgrader retrieves the `main` branch of `https://github.com/coder3814/OttoDoc`, validates the archive shape, fully replaces `docs/_system/` so obsolete engine files do not survive, reconfigures the selected platform, regenerates indexes, and runs lint and drift checks. It backs up the previous engine, generated platform files, and indexes during execution and restores them if validation fails. Report the source, platform, validation result, and resulting repository diff. Do not commit or push unless the user separately requests it.

`OttoDoc intake [filename]` accepts one optional filename: one filename processes that direct child of `docs/_intake/`, while no filename processes the entire folder. Do not require users to name or invoke implementation scripts. Scripts remain available to agents, maintainers, and CI as the execution layer.

## Agent-driven work

Dispatch `doc-coordinator` after every completed system-modifying task and for agent-driven documentation work. The coordinator assesses impact itself and may conclude that no documentation change is justified. When work is needed, it dispatches `doc-author`, then a fresh-context `doc-reviewer`, returning findings to the author for at most two revision cycles before asking the owner.

Required documentation remains in the same change or pull request as its implementation. The coordinator, author, and reviewer retain the authority boundaries in their canonical definitions under `docs/_system/process/`.

## Human drafts

Humans may place rough documents and external material directly in the flat `docs/_intake/` folder without conforming to the final structure. Filenames must be unique; do not add directories. Placement is inert. `OttoDoc intake <filename>` routes that one direct child through the coordinator; `OttoDoc intake` routes every file currently in intake. Reject paths, directories, multiple filenames, and filename patterns. The author preserves intended meaning and human-provided external facts while normalizing kind, scope, summary-first structure, concision, links, and frontmatter; material ambiguity returns to the owner.

## Direct maintainer workflow

Maintainers may scaffold or edit documentation directly when they need the underlying execution layer. Agent normalization and fresh-context review follow before completion.

- Scaffold: `docs/_system/scripts/scaffold.ps1 -Kind <runbook|reference|decision|explanation|plan|design> -Slug <kebab-slug> -Title "<Title>" -Actor "<actor>" [-Subject <kebab-subject>]`
- Lint: `docs/_system/scripts/lint.ps1`
- Regenerate: `docs/_system/scripts/regen.ps1`
- Prove current: `docs/_system/scripts/regen.ps1 -Check`

Never hand-edit an `index.md`. A material content change updates `generated`; a typo-only or relocation-only change does not. Moves and deletions include fixing inbound links and dissolving empty subject folders. Documents and regenerated indexes land together.
