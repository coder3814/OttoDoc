# OttoDoc

OttoDoc is a repository-local documentation system for teams and coding agents. It defines a durable knowledge contract, structured document types, multi-agent authoring and review workflows, linting and index generation, and adapters for Claude, Codex, Cursor, and GitHub Actions.

## Install

Copy [`docs/_system`](docs/_system) into the same location in another repository, then run one explicit bootstrap command from that repository's root:

```powershell
./docs/_system/scripts/bootstrap.ps1 -Platform Claude
# or: -Platform Codex
# or: -Platform Cursor
```

Bootstrap creates missing documentation directories, installs the selected agent-platform adapter and GitHub workflow, and generates indexes. Existing nonconforming documentation causes bootstrap to stop so admission remains deliberate.

## Learn more

- [`docs/_system/README.md`](docs/_system/README.md) explains installation and maintenance.
- [`docs/_system/constitution.md`](docs/_system/constitution.md) defines the knowledge and governance contract.
- [`docs/_system/okf-spec.md`](docs/_system/okf-spec.md) specifies the open knowledge format.
- [`docs/_system/process`](docs/_system/process) defines the coordinator, author, reviewer, and workflow roles.

## License

This project is available under the [MIT License](LICENSE).
