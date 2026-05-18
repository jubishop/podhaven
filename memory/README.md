# Memory

One flat list of long-lived notes for any LLM agent working in this repo: open incidents, user/feedback rules, gotchas, post-mortems, library quirks, debugging recipes, references to external systems.

Not auto-loaded into any session — agents discover pages on demand via [`qmd`](https://github.com/tobi/qmd). Run `qmd query "topic"` before non-trivial area work.

## Writing memories

Write freely whenever you learn something worth keeping. But **first run `qmd search` for the topic** — if a related page exists, update it rather than creating a new one. Avoid duplicates and contradictions.

What belongs here:
- User preferences, feedback, corrections, validated approaches.
- Open incidents and active investigations.
- Discovered gotchas, library quirks, workarounds, post-mortems.
- Pointers to external systems (dashboards, issue projects, Slack channels).

What does **not** belong here:
- Code patterns, conventions, file paths — derivable from the code.
- Git history, recent changes — `git log` / `git blame` are authoritative.
- Intentional architecture / planning — that's [`../docs/`](../docs/README.md).
- TODOs and planned work — those are GitHub issues.

## Page format

Each page is a single `.md` file with frontmatter:

```yaml
---
name: kebab-case-slug
description: one-line summary, used in search snippets
type: user | feedback | project | reference
---
```

For `feedback` and `project` types, lead the body with the rule or fact, then:

```
**Why:** <reason — past incident, constraint, strong preference>

**How to apply:** <when/where this kicks in>
```

Knowing *why* lets a future agent judge edge cases.

## Types

- **`user`** — facts about the user's role, preferences, knowledge level.
- **`feedback`** — guidance the user has given about how to approach work (corrections and validated approaches both).
- **`project`** — non-derivable facts about ongoing work: incidents, motivations, deadlines. Convert relative dates to absolute (`Thursday` → `2026-05-21`).
- **`reference`** — anything else worth remembering: discovered learnings, library quirks, pointers to external systems.

## Cross-linking

Use `[[page-name]]` to reference another memory page (no `.md`, no directory).
