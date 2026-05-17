# Knowledge

A wiki of long-form reference pages for any LLM agent working in this repo. Library quirks, debugging recipes, codebase patterns, migration notes, post-mortems — the kind of *discovered* learnings an agent benefits from when working on a specific area, but doesn't need loaded every session. Not auto-loaded — agents consult it when relevant.

## How it relates to the other persistence layers

| Layer | Role | When an agent reads it |
|---|---|---|
| `memory/` | Auto-loaded hot tier (capped at 25); cold tier still queryable | Auto-loaded via `memory/MEMORY.md` |
| `knowledge/` (this dir) | Discovered learnings, area-specific reference | On demand, when working in a matching area |
| `docs/` | Intentional artifacts: architecture, initiatives, research | On demand, when needing design context |
| GitHub Issues | Discrete TODOs with lifecycle | When asking "what's open" |

The line between `knowledge/` and `docs/` is **intentional vs discovered**: `docs/` holds artifacts you wrote on purpose (architecture you designed, initiatives you're planning, research you commissioned) — PR-reviewed because the content is deliberate. `knowledge/` holds things you captured because they happened (a gotcha you hit, a post-mortem after a fix landed, a workaround you found) — agent-curated, terse, wrong-and-corrected-later.

Decision rule for a new page: *did I write this on purpose, or am I capturing something that happened?* Intentional → `docs/`. Discovered → `knowledge/`.

## Page format

Each page is a single `.md` file with light frontmatter:

```yaml
---
name: kebab-case-slug
description: one-line summary, used for INDEX.md and search snippets
tags: [optional, comma, separated]
---
```

Body is normal markdown. Prefer prose over telegraphic bullets, but use whatever fits the topic.

## Naming

- `kebab-case.md` filenames.
- Filename matches the frontmatter `name` field.
- One topic per page. Split rather than grow indefinitely.

## Cross-linking

Use `[[page-name]]` to reference another wiki page (no `.md`, no directory prefix). Resolves first within the current directory, then sibling wiki directories (`memory/`, `knowledge/`). Obsidian-compatible.

For explicit citation in prose (e.g. linking to a file in `docs/`), use standard markdown: `[label](../docs/path.md)`.

## Index and log

- **`INDEX.md`** — one-line catalog of all pages, with descriptions. Updated whenever a page is added, removed, or substantially revised.
- **`log.md`** — append-only timeline of what changed and when. Entries take the form `## [YYYY-MM-DD] <kind> | <title>` where `<kind>` is `add`, `update`, `archive`, `lint`, or `graduate` (entries graduated in from `memory/`).

## Auto-population

Knowledge pages arrive via two automated paths in addition to manual writing:

- **Weekly PR-to-knowledge writer** scans merged PRs for high-signal lessons (strong post-mortem language or substantive bugfix bodies in gotcha-prone areas) and extracts them into pages here.
- **Memory graduation** (from the daily lint): `type: project` memory pages whose linked issue closes or that go untouched for 60 days graduate from `memory/` into `knowledge/`, rewritten as post-mortems.

Both routines emit telemetry lines to `automation-log.md` at repo root.

## Lint and archive

Stale pages move to `knowledge/archive/` (still greppable, no longer indexed in `INDEX.md`). The daily lint runs auto-archive plus file-consistency checks (broken `[[links]]`, frontmatter ↔ filename drift, index drift); consistency findings open dedup'd GitHub issues with `[automation]` title prefix. Manual archive is also fine: move the file, drop the `INDEX.md` entry, and append a `## [date] archive | <title>` line to `log.md`.

## Search

The repo is indexed by [qmd](https://github.com/tobi/qmd) — agents can run hybrid BM25+vector queries with:

```bash
qmd query "user authentication flow"   # hybrid + rerank
qmd search "Factory v3"                # BM25 only
qmd vsearch "swift concurrency"        # vector only
```

Collections are defined in `qmd.yml` at repo root.
