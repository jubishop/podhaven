# Knowledge

A wiki of long-form reference pages for any LLM agent working in this repo. Library quirks, debugging recipes, codebase patterns, migration notes, gotchas — the kind of synthesized knowledge an agent benefits from when working on a specific area, but doesn't need loaded every session.

Inspired by Karpathy's [LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f): synthesized markdown pages, cross-linked, queried on demand. Not auto-loaded — agents consult it when relevant.

## How it relates to the other persistence layers

| Layer | Role | When an agent reads it |
|---|---|---|
| `memory/` | Short, currently-active context (open incidents, user/feedback rules) | Auto-loaded via `memory/MEMORY.md` |
| `knowledge/` (this dir) | Long-form, area-specific reference | On demand, when working in a matching area |
| `docs/` | Architecture rationale, multi-PR initiatives | On demand, when needing design context |
| GitHub Issues | Discrete TODOs with lifecycle | When asking "what's open" |

The line between `knowledge/` and `docs/` is *audience and cadence*: `docs/` is reviewed in PRs by humans, evolves with code, holds architecture rationale. `knowledge/` is agent-curated, can be terse, can be wrong-and-corrected-later, scales without review gates.

## Page format

Each page is a single `.md` file with light frontmatter:

```yaml
---
name: kebab-case-slug
description: one-line summary, used for INDEX.md and search snippets
tags: [optional, comma, separated]
---
```

Body is normal markdown. No comment style is required — write the way the topic wants to be written. Prefer prose over telegraphic bullets, but use whatever fits.

## Naming

- `kebab-case.md` filenames.
- Filename matches the frontmatter `name` field.
- One topic per page. Split rather than grow indefinitely.

## Cross-linking

Use `[[page-name]]` to reference another wiki page (no `.md`, no directory prefix). Resolves first within the current directory, then sibling wiki directories (`memory/`, `knowledge/`). Obsidian-compatible.

For explicit citation in prose (e.g. linking to a file in `docs/`), use standard markdown: `[label](../docs/path.md)`.

## Index and log

- **`INDEX.md`** — one-line catalog of all pages, with descriptions. Updated whenever a page is added, removed, or substantially revised.
- **`log.md`** — append-only timeline of what changed and when. Entries take the form `## [YYYY-MM-DD] <kind> | <title>` where `<kind>` is `add`, `update`, `archive`, or `lint`.

## Lint and archive

Stale pages move to `knowledge/archive/` (still greppable, no longer indexed in `INDEX.md`). The repo runs a weekly auto-archive-with-veto lint via the agent's scheduled routines — see [[memory/README]] for how that's configured. Manual archive is also fine: move the file, drop the `INDEX.md` entry, and append a `## [date] archive | <title>` line to `log.md`.

## Search

The repo is indexed by [qmd](https://github.com/tobi/qmd) — agents can run hybrid BM25+vector queries with:

```bash
qmd query "user authentication flow"   # hybrid + rerank
qmd search "Factory v3"                # BM25 only
qmd vsearch "swift concurrency"        # vector only
```

Collections are defined in `qmd.yml` at repo root.
