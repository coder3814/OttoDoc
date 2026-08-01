# Portable documentation engine

This directory is the complete, portable source of truth for the documentation system. Platform-discovery files outside it are generated adapters and contain no original process rules.

## Install in another repository

1. Copy this `_system` directory to `<repository>/docs/_system`.
2. From the repository root, explicitly choose one agent platform:

   ```powershell
   ./docs/_system/scripts/bootstrap.ps1 -Platform Claude
   # or: -Platform Codex
   # or: -Platform Cursor
   ```

Bootstrap creates any missing kind directories and the durable empty `docs/_intake/` directory, configures only the requested agent platform plus GitHub enforcement, and generates the initial indexes. Each command names exactly one platform; OttoDoc never guesses which platforms the owner wants. Configuring another platform requires another explicit user request, and is additive — it leaves platforms already configured untouched. Bootstrap does not import, move, rewrite, or delete existing documentation. A repository with pre-existing nonconforming content fails closed so that admission remains deliberate.

## Maintain an installation

- Use the agent-facing `OttoDoc upgrade` command to retrieve and validate the newest engine from GitHub. Users do not need to invoke `scripts/upgrade.ps1` directly. Upgrade takes no platform argument: it reads which platforms are configured and refreshes all of them.
- To add or refresh an agent platform, run `./docs/_system/scripts/configure-platform.ps1 -Platform <Claude|Codex|Cursor>`.
- To decommission one, run `./docs/_system/scripts/remove-platform.ps1 -Platform <Claude|Codex|Cursor>`. Removing the last one is allowed and leaves the engine installed with zero configured platforms.
- To remove the engine and every platform while keeping the documentation, run `./docs/_system/scripts/uninstall.ps1`.
- To verify every installed adapter without writing, run `./docs/_system/scripts/check-adapters.ps1`. It takes no arguments, and it fails on drift and on adapter files belonging to no configured platform alike.
- Never edit generated files under `.claude/`, `.codex/agents/`, `.agents/skills/documentation/`, `.cursor/`, or `.github/workflows/docs.yml` directly, and never edit inside the `ottodoc:begin`/`ottodoc:end` markers in `AGENTS.md` or `CLAUDE.md`. Everything outside those markers is yours.

Read [the constitution](constitution.md) for the knowledge contract and governance, and [`process/`](process/) for the canonical coordinator, author, reviewer, and workflow definitions.
