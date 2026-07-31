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

Bootstrap creates any missing kind directories and the durable empty `docs/_intake/` directory, configures only the requested agent platform plus GitHub enforcement, and generates the initial indexes. There is no automatic platform detection and no multi-platform configuration mode. Configuring another platform requires another explicit user request. Bootstrap does not import, move, rewrite, or delete existing documentation. A repository with pre-existing nonconforming content fails closed so that admission remains deliberate.

## Maintain an installation

- Use the agent-facing `OttoDoc upgrade` command to retrieve and validate the newest engine from GitHub. Users do not need to invoke `scripts/upgrade.ps1` directly.
- To configure or refresh an agent platform, run `./docs/_system/scripts/configure-platform.ps1 -Platform <Claude|Codex|Cursor>` for the platform the user requested.
- To verify that platform without writing, add `-Check`.
- Never edit generated files under `.claude/`, `.codex/agents/`, `.agents/skills/documentation/`, `.cursor/`, or `.github/workflows/docs.yml` directly.

Read [the constitution](constitution.md) for the knowledge contract and governance, and [`process/`](process/) for the canonical coordinator, author, reviewer, and workflow definitions.
