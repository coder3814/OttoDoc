# Documentation workflow

This is the canonical process for documentation assessment, authoring, normalization, review, and retirement. Read `docs/_system/constitution.md` first; it governs every judgment.

## Authority

Documentation-only work may inspect the repository but may modify only `docs/`. It never fixes code, tests, scripts, workflows, configuration, infrastructure, schemas, or deployed state. Validation is repository-only; never query live or external systems. Report implementation concerns in the task result and create no issue or findings file without separate authorization.

## Agent-driven work

Dispatch `doc-coordinator` after every completed system-modifying task and for agent-driven documentation work. The coordinator assesses impact itself and may conclude that no documentation change is justified. When work is needed, it dispatches `doc-author`, then a fresh-context `doc-reviewer`, returning findings to the author for at most two revision cycles before asking the owner.

Required documentation remains in the same change or pull request as its implementation. The coordinator, author, and reviewer retain the authority boundaries in their canonical definitions under `docs/_system/process/`.

## Human drafts

Humans may place rough documents and external material directly in the flat `docs/_intake/` folder without conforming to the final structure. Filenames must be unique; do not add directories. Placement is inert: route selected intake files through the coordinator only after an explicit user processing request. The author preserves intended meaning and human-provided external facts while normalizing kind, scope, summary-first structure, concision, links, and frontmatter; material ambiguity returns to the owner.

## Direct human workflow

Humans may scaffold or edit documentation directly. Agent normalization and fresh-context review follow before completion.

- Scaffold: `docs/_system/scripts/scaffold.ps1 -Kind <runbook|reference|decision|explanation|plan|design> -Slug <kebab-slug> -Title "<Title>" -Actor "<actor>" [-Subject <kebab-subject>]`
- Lint: `docs/_system/scripts/lint.ps1`
- Regenerate: `docs/_system/scripts/regen.ps1`
- Prove current: `docs/_system/scripts/regen.ps1 -Check`

Never hand-edit an `index.md`. A material content change updates `generated`; a typo-only or relocation-only change does not. Moves and deletions include fixing inbound links and dissolving empty subject folders. Documents and regenerated indexes land together.
