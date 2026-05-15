# Memory

Short, currently-active context that benefits any LLM agent to have available every session: open incidents under investigation, user/feedback rules the agent must apply, in-flight project state, references to external systems.

**Convention:** agents should load `MEMORY.md` (a one-line-per-entry catalog) at session start so this context is in mind throughout. Some harnesses do this automatically (Claude Code, via its memory subsystem); other agents should follow the same convention by reading `MEMORY.md` as part of their startup routine. Keep this directory small — when a page stops being relevant to *every* session, move it to `knowledge/` (long-form reference) or `memory/archive/` (historical).

## How it relates to the other persistence layers

See [knowledge/README.md](../knowledge/README.md) for the full picture. In short:

| Layer | Role |
|---|---|
| `memory/` (this dir) | Auto-loaded, must stay small |
| `knowledge/` | On-demand reference, scales freely |
| `docs/` | PR-reviewed architecture/initiative docs |
| GitHub Issues | Discrete TODOs with open/close lifecycle |

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

## Memory types

- **`user`** — facts about the user's role, preferences, responsibilities, knowledge level. Helps an agent tailor explanations and assumptions.
- **`feedback`** — guidance the user has given about how to approach work. Both corrections ("don't do X") and confirmations ("yes, that approach was right"). Record from failure *and* success so the agent doesn't drift away from validated approaches.
- **`project`** — non-derivable facts about ongoing work: who's doing what, deadlines, motivations, incidents under active investigation. Decays fast — convert relative dates to absolute (`Thursday` → `2026-03-05`).
- **`reference`** — pointers to where information lives in external systems (Linear projects, Grafana dashboards, Slack channels).

## What does NOT belong in memory

- Code patterns, conventions, architecture, file paths — derivable from the code.
- Git history, recent changes, who-changed-what — `git log` / `git blame` are authoritative.
- Debugging solutions / fix recipes — the fix is in the code; the commit message has the context.
- Long-form reference (library quirks, migration notes, workflow guides) — that's `knowledge/`.
- TODOs and planned work — those are GitHub Issues.

## Cross-linking

Use `[[page-name]]` to reference another wiki page (no `.md`, no directory prefix). Resolves first within the current directory, then sibling wiki directories. Obsidian-compatible.

## Index and log

- **`MEMORY.md`** — content-oriented catalog. **Agents should load this at session start** (some harnesses do automatically). One line per entry, under ~150 characters.
- **`log.md`** — append-only timeline of memory mutations. Format: `## [YYYY-MM-DD] <kind> | <title>` where `<kind>` ∈ `add | update | archive | lint | incident`.

`incident` entries are reserved for dated observations attached to an open investigation page (e.g. the NowPlayingInfo desync recurrences). They go in `log.md` rather than being inlined in the investigation page itself — the page stays a synthesis; the log keeps the chronology.

## Lint and archive

Stale memories move to `memory/archive/` (greppable, no longer auto-loaded). A weekly scheduled agent routine runs auto-archive-with-veto: it audits pages for staleness (last-modified date, claim freshness vs. current code, broken `[[links]]`) and proposes moves; the user reviews the diff before any move is final.

Manual archive is also fine: move the file, drop its `MEMORY.md` line, append a `## [date] archive | <title>` entry to `log.md`.
