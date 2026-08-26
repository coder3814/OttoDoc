# The Documentation Constitution

> **Note:** this document ships verbatim into every repository that installs OttoDoc, so nothing in it may name facts particular to one installation — no repository names, git tags, branch names, or history belonging to a single repo. Rules are stated in terms every consumer can apply.

This document governs everything under `docs/`. It is the single source of truth for how documentation is structured, created, changed, and removed. Every rule the tooling enforces and every judgment an author makes traces back to here. If practice and this document disagree, one of them is wrong — fix whichever it is, deliberately.

`docs/_system/` (this folder) is the engine: the rules, the vendored standard, the templates, and the scripts. Everything else under `docs/` is the knowledge tree: what we know about the repository and its subject. The engine is exempt from the format rules it enforces; the tree is fully subject to them.

## 1. The standard

Documents follow **Open Knowledge Format (OKF) v0.2**, vendored at [`_system/okf-spec.md`](okf-spec.md), as amended below. The OKF bundle is `docs/` itself; the root `index.md` carries `okf_version: "0.2"` — the one place index frontmatter is legal. Where this constitution and the spec disagree, the constitution wins.

Amendments to OKF v0.2:

1. **No `log.md`.** Git history is the log. Lint rejects a `log.md` anywhere in the tree.
2. **No Attested Computations.** Lint rejects the `Attested Computation` type and its contract keys.
3. **No staleness timers.** Lint rejects `stale_after`, and no process sweeps expiry dates. Indexes stay true by construction (§4), and truth is re-verified when a task touches a doc — not on a clock.
4. **Indexes are build products.** `index.md` files are written only by the regen script, never by hand (§4).
5. **Reserved directories.** `_system/` holds the engine — exempt from frontmatter, linting, and indexing. `assets/` subfolders hold non-markdown files (§5) — excluded from indexing. `_intake/` is the durable holding area for non-authoritative source material awaiting an explicit processing request (§6) — its contents are ignored by knowledge-tree lint and indexing.
6. **Broken links are lint failures.** The spec tolerates dangling links; we do not (§3).
7. **Stricter frontmatter than the spec requires** (§3): `title`, `description`, `tags`, and `generated` (both `by` and `at`) are mandatory, not recommended.
8. **Looser timestamps than the spec specifies:** date-only values (`YYYY-MM-DD`) suffice for `at` fields; full datetimes are not required.
9. **No document-level verification metadata.** Git, pull-request, and workflow history record review. Lint rejects `verified`, whose document-wide implication is broader than repository-only review can honestly support.

## 2. The tree

The root of `docs/` is a **closed set of kind directories** — no kind is added, removed, or renamed without amending this constitution. All six exist from day one, even when empty; an empty kind directory holds only its generated `index.md`. A kind is defined by what the reader *does* with the document — its reader question — not by subject or author. The six kinds:

| Directory | Type value | Reader question | The reader… |
|---|---|---|---|
| `runbooks/` | `Runbook` | How do I perform this operation? | follows it, step by step |
| `reference/` | `Reference` | What is the fact? | looks up a value and leaves |
| `decisions/` | `Decision` | Why is it this way? | reads the current choice and its rationale |
| `explanations/` | `Explanation` | How does this work? | reads for a mental model |
| `plans/` | `Plan` | What do we intend? | reads forward-looking intent |
| `design/` | `Design` | What should this conform to? | measures work against a standard |

The kinds in depth:

- **`Runbook`** — an ordered, imperative procedure with a defined end state, executed top to bottom. The measure of a runbook: someone who is not its author can perform the operation safely from it alone. It may carry a sentence of context where a step needs it ("step 3 matters because the indexer holds a lock"), but its dominant purpose is execution, not understanding. It is not a description of how a system behaves — that is an `Explanation`.
- **`Reference`** — noun-shaped facts: values, names, tables, inventories, credentials-by-pointer. Nobody reads a reference start to finish; a reader arrives with a question, extracts one fact, and leaves. The measure: the fact is findable and current. It states values without narrative — the *why* behind a value belongs in a `Decision` or `Explanation` it links to.
- **`Decision`** — a living document, one per technical or architectural choice: API shapes, algorithms, patterns, structural approaches. It states the current choice *and* its rationale — the forces on it, and the alternatives rejected with why — so a reader about to write code knows the methodology and the intent from one document. When the decision changes, the doc is rewritten in place (`generated` records it; git holds what it used to say). Decisions are not numbered and not append-only. A Decision is admitted through one of two doorways: it records a choice that is hard to reverse, surprising without context, **and** the result of a real trade-off — all three, or it is not recorded; or it states a standard future work must conform to that is not derivable from the code alone. A choice that passes neither doorway — easily reversed, obvious in hindsight, or the only real option, and binding on no future work — gets no document.
- **`Explanation`** — a descriptive account of how part of the system actually works today: the shape of a subsystem, the flow of data, the interaction of parts. Read whole, for a mental model; the measure is that a cold reader comes away with the right picture. It describes and never prescribes — it has no steps to follow and makes no normative claims about how things *should* be.
- **`Plan`** — forward-looking intent: work decided on but not yet done, including transient design intent ("how we plan to build X"). Deliberately short-lived — a plan dies on execution or abandonment (§7), and its useful residue lands in the docs the work produces.
- **`Design`** — visual design only: layout, artistic direction, UX implementation, design systems, and every standard the rendered product is measured against. It does not cover API design, algorithms, architecture patterns, or other non-visual standards such as coding or process conventions — those are technical choices and belong in `Decision`.

Placement rules:

- **Dominant purpose decides — for every kind.** Real documents blur at the edges: a runbook contains a sentence of explanation, an explanation embeds a fact, a decision sketches a procedure. A document's kind is assigned by what the document is *for*, not by every kind of material it happens to contain. When material inside one doc is needed by other docs, extract it into a doc of its proper kind and link to it — a split is made when a real task demands it, never speculatively.
- **One reader question, one recognizable situation, one coherent outcome.** Shared subject matter does not make independent concepts one document. Split major sections that have independent entry conditions, prerequisites, risks, outcomes, maintenance causes, or uses. Keep prerequisites, warnings, verification, and troubleshooting with the single reader goal they support. A title joined by “and,” several independently usable top-level procedures, or a summary that must enumerate separate purposes triggers scope review.
- **Facts have one canonical owner.** When current documents conflict, repository state resolves the claim where possible; one document owns the verified current fact and other contexts link to it. If both claims are true under different conditions, make the scopes explicit. If repository-only inspection cannot resolve a material conflict, ask the owner rather than choosing a winner.
- **Subject subfolders are earned.** A kind's directory stays flat until roughly three or four docs share a subject; then a subject folder is created and those docs move into it. Folders are never created empty, may be dissolved when they shrink, and do not nest — one level below the kind. Lint checks placement at the kind level only; subject grouping is editorial judgment.

**The glossary.** `reference/glossary.md` is the project's domain vocabulary: one entry per concept, naming the canonical term, defining in a sentence or two what the concept *is* — not what it does — and listing the synonyms to avoid. Be opinionated: when several words compete for one concept, one wins and the rest are outlawed. Only concepts particular to this project's domain are admitted — general programming vocabulary is not — and definitions carry no implementation detail. Mechanically it is an ordinary Reference document, created lazily when the first term is resolved. But it holds one standing no other document has: vocabulary bears on every task rather than on a discoverable class of them, so the routing obligation (§8) names it directly — agents speak in its canonical terms, challenge usage that conflicts with an entry, sharpen fuzzy language toward a precise term, and treat a term resolved during any task as documentation impact to capture.

## 3. The document contract

One document = one concept file. Every `.md` in the tree (outside `_system/`, `_intake/`, and index files) carries YAML frontmatter:

```yaml
---
type: Runbook                # required — exactly one of the six Type values in §2
title: Prod search reindex   # required — human-readable display name
description: How to rebuild the prod Lucene index from SQL, end to end.
                             # required — ONE sentence; becomes this doc's index line
tags: [search, prod-ops]     # required — lowercase kebab-case; the mechanical search surface
generated:                   # required — who last authored/rewrote the content, and when
  by: human:<id>             # actor convention: human:<id> for people (id = a stable short
                             #   handle, e.g. the git username), <producer>/<version> for
                             #   agents (e.g. claude/fable-5), process:<id> for automated processes
  at: 2026-07-30             # required — date-only suffices (§1, amendment 8)
---
```

- **`description` is load-bearing.** It is the doc's line in every index above it and the surface all search converges on. It must let a reader decide, from the one sentence alone, whether to open the doc. Naming the subject is not enough: the sentence also states the class of task the document bears on — what work it constrains, decides, or enables. The test: could an agent doing unrelated-looking work recognize from this sentence alone that the document constrains that work? "Why ingress uses an IP allowlist" fails it; "Why ingress uses an IP allowlist, constraining any work that exposes a page publicly" passes.
- **`generated` tracks content, not keystrokes.** Any content change updates it — new actor, new date; mechanical touch-ups like typo fixes do not. This rule cannot be linted; it holds only because every author honors it.
- Other OKF fields (`sources`, `resource`, `status`) are legal and used when meaningful; unknown extra keys are preserved per the spec. Nothing beyond the block above is required.
- File names are lowercase kebab-case. `index.md` and `log.md` are reserved and never name a concept.

**Body.** Every concept document opens with one H1 title followed immediately by `## Summary`. The summary is normally two to four sentences: what the document covers, its intent, how the reader uses it, and its principal outcome or conclusion. It complements rather than repeats the frontmatter description. After it, every kind carries its minimum semantic contract:

- **Runbook:** prerequisites, ordered steps, and objective verification.
- **Reference:** the facts it canonically owns, organized for lookup.
- **Decision:** the current choice, forces, and alternatives rejected.
- **Explanation:** a descriptive account of how the current system works.
- **Plan:** intent, work, and the condition on which the plan retires.
- **Design:** the visual standard against which rendered work is measured.

Additional sections exist only when the content needs them. Write through progressive detail: essential orientation first, task-specific detail at the point of use, and exhaustive implementation detail in its canonical repository source. Every section must support the document's primary reader question. A concept document above roughly 1,500 words or with more than eight H2 sections receives an explicit scope review; these are judgment triggers, never lint failures or invitations to omit necessary knowledge.

**Links.** Docs link to each other with standard **relative paths** (`../reference/test-accounts.md`) — they render correctly in every tool we actually read with. A link's target must exist: lint fails broken intra-tree links (§1, amendment 6), so a link to a not-yet-written doc is not written yet. Moving or deleting a doc includes fixing its inbound links — lint enumerates them, making the obligation mechanical.

## 4. Indexes and the bottom-up rule

**The documents are the system; indexes are a projection of them.** Every character of an `index.md` is derived — titles and descriptions from frontmatter, structure from file locations, ordering and grouping from deterministic rules in the regen script, the governance pointer emitted by the script itself. An index carries **zero original information**, which guarantees:

- If every index vanished, one regen run restores them, byte-identical.
- Externally added or deleted files are reconciled by the next run: ghosts cannot survive, additions cannot hide.
- **Check mode** (regenerate in memory, diff against disk) answers "are the indexes truthful right now?" without modifying anything. CI runs it on every change to `docs/`; it is equally runnable on demand.

The rules that follow:

1. **Bottom-up completion.** A document change is not complete until every ancestor index reflects it. Mechanically: authoring ends with lint, then regen, and the same commit carries the document *and* the regenerated indexes.
2. **Never hand-edit an index.** A hand edit is, by definition, information not derivable from the documents; the next regen erases it. There are no exceptions, including "small fixes."
3. **The regen script is deterministic.** Same tree in, same bytes out — no timestamps, no environment-dependent ordering. Nondeterminism breaks check mode and is a bug of the highest severity.
4. **Lint runs before regen, and lint failure aborts.** A doc that fails lint cannot be indexed, because its index line cannot be derived. Regen never runs over a nonconformant tree — it never skips a file, so a document can never silently vanish from the catalog.
5. **The root index opens with the governance pointer** to this constitution, emitted structurally by the script — the first thing any reader of the tree encounters.

**How the tree is searched.** Three tiers, none requiring infrastructure: humans browse the directory structure and indexes; mechanical queries grep the frontmatter (`tags`, `description`, `type`); agents drill the indexes progressively from the root. **No embeddings, no database, no search service** — with a tree of markdown files, grep is instant, and anything heavier is bloat.

## 5. Assets

Non-markdown files (images, data files, scripts-that-are-content) are **payload, not knowledge**. The knowledge about an asset is prose, and prose lives in a concept doc.

- Every asset lives in a reserved `assets/` subfolder beside the docs that use it. An asset has exactly one home — beside its primary owner; other docs link across to it.
- Asset file names are lowercase kebab-case with an extension — casing and spaces in names are exactly how links rot across platforms.
- **Every asset must be owned**: linked from at least one concept doc that explains what it is. The linter fails orphans — an unexplained payload is unmergeable.
- Assets never appear in indexes; they are reached only through their owning doc.

## 6. Admission

Content enters the tree **only when a real task needs it**. No backfilling sections for completeness, no bulk imports, no "this might be useful someday." Empty is a valid and healthy state for any part of the tree.

Anything drawn from previous documentation — intake files, a human draft, external material, or any earlier form of a doc — is input, never a required final shape. Its intended meaning and explicitly human-provided external facts are preserved, but its claims are recomposed from first principles into the smallest useful canonical document set. A claim no task needs gets no new home. Repository-defined claims are checked only against repository state; documentation actors never query live or external systems and never execute procedures. Current external state is attributed to its human source or labeled externally unverified. Material ambiguity returns to the owner.

**Documentation authority is narrow.** A documentation-only task may inspect the repository, but it may modify only `docs/` (including generated indexes and consumed `_intake/` sources). It never fixes code, tests, scripts, workflows, configuration, infrastructure, schemas, or deployed state. Implementation concerns appear separately in the task result; no findings file or issue is created without separate authorization. Documenting current defective behavior does not endorse it.

The lifecycle commands specified in [`lifecycle.md`](lifecycle.md) are the exceptions to that limit; their authority is defined there.

**Intake.** `docs/_intake/` is a durable, flat, inert holding area for non-authoritative source material. Installation creates it, and upgrades restore it when it is missing, so it remains available even when empty. A human may place any file type there that the active agent can read. Directories and unsupported files are rejected during assessment; filenames must be unique, and a collision is rejected rather than renamed or overwritten. Placement never starts processing. `OttoDoc intake [filename]` is the processing command. With one filename, the coordinator assesses that direct child of `_intake/`; with no filename, it assesses every file currently in `_intake/`. Paths, directories, multiple filenames, and filename patterns are invalid parameters.

After admitted documentation passes fresh-context review, the author deletes each consumed intake source in the same change. When processing concludes that a source should produce no live documentation, it reports that outcome and deletes the source only after the owner's explicit approval. The `_intake/` directory itself remains in place after its contents are consumed. Generated indexes never enter intake because they contain no original knowledge.

## 7. Retirement

When a document stops being true or stops being needed, **delete it**. Git history is the archive; the tree holds only live knowledge. `status: deprecated` is reserved for the narrow window where a doc is known-wrong-but-referenced and its replacement is not yet ready.

- **Plans** die on execution or abandonment — an executed plan's residue belongs in the docs the work produced, not in a stale intent file.
- **Decisions** retire like everything else: rewritten in place when the choice changes, deleted when the thing decided about ceases to exist. There is no archive of superseded decisions in the tree — git is the archive.

## 8. Process

Documentation is authored when a real task needs it — there is no autonomous documentation service. Every completed system-modifying task receives a bounded documentation-impact assessment from the read-only coordinator; “no documentation change justified” is a valid and common result. The coordinator changes no files. When a durable reader need exists, it dispatches the documentation-only author and then a fresh-context reviewer that changes no files. It permits at most two revision-and-review cycles before asking the owner. Required documentation lands in the same change or pull request as the implementation it describes. Completion is reported briefly in natural language; material implementation concerns are separate from routine orchestration detail.

Humans may supply rough documents or external material without first conforming to the engine. Agents normalize those inputs to this contract, preserve intended meaning, and ask before resolving material ambiguity. **Process lives with its actors under `_system/process/`**: workflow, coordination, authoring craft, and review criteria are canonical there. Platform-required files outside `_system/` are generated discovery adapters with no original process information.

**Every supported platform gets an always-on surface.** The post-task assessment above is law for *every* completed system-modifying task, so a platform that can only be reached by an agent choosing to reach for it cannot honor it. Which files carry each platform's surface is specified in [`lifecycle.md`](lifecycle.md). Where a platform offers a prompt-time extension point, the routing obligation — consult the tree before forming a plan, evaluation, or recommendation, and hold work and conversation to the glossary's canonical vocabulary (§2) — is additionally injected into every prompt, because static context alone has proven unreliable for judgment tasks; a platform without one carries only the static surface, a gap documented in `lifecycle.md` rather than papered over with more static text.

**Enforcement.** CI runs lint and check mode on every change touching `docs/` or any adapter path — pull requests and pushes to main alike. The mechanical set — frontmatter completeness, mandatory Summary placement, kind-level placement, file and asset naming, orphan assets, broken and mis-cased links, empty subject folders, banned constructs (§1), and index drift — fails the build. Adapter drift is checked by the lifecycle tooling ([`lifecycle.md`](lifecycle.md)). Scope, necessity, progressive disclosure, concision, canonical ownership, and editorial quality are enforced by coordinator assessment and fresh-context review. A document that merely conforms is not yet good.

**Approval.** Tree content flows through normal PRs. Agent-authored and agent-normalized docs receive fresh-context review before completion. The review verdict lives in Git, pull-request, and workflow history, never in document metadata.
