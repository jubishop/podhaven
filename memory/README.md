# Memory

Short, currently-active context that benefits any LLM agent to have available every session: open incidents under investigation, user/feedback rules the agent must apply, in-flight project state, references to external systems.

**Convention:** agents load `MEMORY.md` (a one-line-per-entry catalog of the hot tier) at session start so this context is in mind throughout. Some harnesses do this automatically (Claude Code, via its memory subsystem); other agents should follow the same convention by reading `MEMORY.md` as part of their startup routine.

## How it relates to the other persistence layers

| Layer | Role |
|---|---|
| `memory/` (this dir) | Auto-loaded hot tier (capped at 25); cold tier still queryable via qmd |
| `knowledge/` | Discovered learnings (gotchas, post-mortems); on-demand via qmd |
| `docs/` | Intentional artifacts (architecture, initiatives, research); PR-reviewed |
| GitHub Issues | Discrete TODOs with open/close lifecycle |

The line between `knowledge/` and `docs/` is *intentional vs discovered*: `docs/` holds artifacts you wrote on purpose (architecture you designed, initiatives you're planning); `knowledge/` holds things you captured because they happened (a gotcha you hit, a post-mortem after a fix landed).

## Tiers and capacity

Memory has two tiers:

- **Hot** — pages listed in `MEMORY.md`, auto-loaded into every session. **Capped at 25 entries.**
- **Cold** — pages in `memory/cold/`. NOT in `MEMORY.md`, NOT auto-loaded, but still queryable via qmd and still in the same schema.

The daily lint enforces the cap by git mtime: when `MEMORY.md` exceeds 25 entries, the least-recently-touched page demotes to `cold/` and its `MEMORY.md` line is removed. A cold page promotes back to hot if it's edited, `[[linked]]` from a hot page, or its slug appears in a recent commit/issue.

Demotions and promotions emit `## [date] demote | <title>` and `## [date] promote | <title>` entries in `log.md`.

## When a GitHub issue tracks the work

When a `type: project` page has a linked GitHub issue, the page holds **post-landing verification instructions only** — how to manually confirm the fix worked after the PR lands. The investigation narrative, fix plan, reproducer, and source-feedback metadata all live in the issue body. The memory page is the agent-facing checklist that fires when work in that area lands.

After the fix is verified, the page graduates to `knowledge/` automatically (see below).

## Graduation to knowledge/

`type: project` memory pages auto-graduate to `knowledge/` when EITHER:

- the linked GitHub issue is closed AND the page hasn't been touched for 7 days, OR
- the page hasn't been touched for 60 days (no linked issue required).

The daily lint performs the move: `git mv` to `knowledge/`, rewrite the framing into a post-mortem (strip "in-flight" language, restructure into Timeline / Root cause / Fix / Lessons sections from the existing body), update `MEMORY.md` and `knowledge/INDEX.md`, emit `## [date] graduate | <title> → knowledge/` to both logs.

Knowledge → docs and knowledge → memory transitions stay manual.

## Page format

Each page is a single `.md` file with frontmatter:

```yaml
---
name: kebab-case-slug
description: one-line summary, used in MEMORY.md and search
type: user | feedback | project | reference
---
```

The body should lead with the rule or fact. For `feedback` and `project` types, structure as:

```
<rule or fact, in one sentence>

**Why:** <reason — past incident, constraint, deadline, strong preference>

**How to apply:** <when/where this kicks in>
```

Knowing *why* lets a future agent judge edge cases rather than blindly follow the rule.

For `type: project` pages with a linked issue, the body is post-landing verification instructions instead (see "When a GitHub issue tracks the work" above).

## Memory types

- **`user`** — facts about the user's role, preferences, responsibilities, knowledge level. Helps an agent tailor explanations and assumptions.
- **`feedback`** — guidance the user has given about how to approach work. Both corrections ("don't do X") and confirmations ("yes, that approach was right"). Record from failure *and* success so the agent doesn't drift away from validated approaches.
- **`project`** — non-derivable facts about ongoing work: who's doing what, deadlines, motivations, incidents under active investigation. Decays fast — convert relative dates to absolute (`Thursday` → `2026-03-05`).
- **`reference`** — pointers to where information lives in external systems (Linear projects, Grafana dashboards, Slack channels).

## What does NOT belong in memory

- Code patterns, conventions, architecture, file paths — derivable from the code.
- Git history, recent changes, who-changed-what — `git log` / `git blame` are authoritative.
- Debugging solutions / fix recipes — the fix is in the code; the commit message has the context.
- Long-form retrospection (post-mortems, library quirks, migration notes) — that's `knowledge/`.
- Intentional architecture / planning — that's `docs/`.
- TODOs and planned work — those are GitHub Issues.
- For `type: project` pages with a linked issue: investigation narrative, fix plans, reproducers — those go in the issue body.

## Cross-linking

Use `[[page-name]]` to reference another wiki page (no `.md`, no directory prefix). Resolves first within the current directory, then sibling wiki directories. Obsidian-compatible.

## Index and log

- **`MEMORY.md`** — content-oriented catalog of the hot tier. **Agents should load this at session start** (some harnesses do automatically). One line per entry, under ~150 characters.
- **`log.md`** — append-only timeline of memory mutations. Format: `## [YYYY-MM-DD] <kind> | <title>` where `<kind>` ∈ `add | update | archive | lint | incident | demote | promote | graduate`.

`incident` entries are reserved for dated observations attached to an open investigation page. They go in `log.md` rather than being inlined in the investigation page itself — the page stays a synthesis; the log keeps the chronology.

## Lint and archive

The daily lint runs auto-archive, hot/cold tiering enforcement, cross-tier graduation, and file-consistency checks (broken `[[links]]`, frontmatter ↔ filename drift, index drift). Consistency findings open dedup'd GitHub issues with `[automation]` title prefix; runs emit a telemetry line to `automation-log.md` at repo root. See [[knowledge/README]] for the matching knowledge-tier conventions.

Manual archive is fine: move the file to `memory/archive/`, drop its `MEMORY.md` line, append a `## [date] archive | <title>` entry to `log.md`.
