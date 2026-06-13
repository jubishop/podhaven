# Memory

Long-lived repo notes for LLM agents: user guidance, incidents, gotchas, post-mortems, library quirks, debugging recipes, and external refs.

Not auto-loaded; discover pages with [`qmd`](https://github.com/tobi/qmd). Before writing, run `qmd search` and update an existing related page when possible.

## Scope

- User preferences, feedback, corrections, validated approaches.
- Open incidents and active investigations.
- Gotchas, library quirks, workarounds, post-mortems.
- Pointers to external systems (dashboards, issue projects, Slack channels).

Do not use memory for:

- Code patterns, conventions, file paths: derivable from the code.
- Git history, recent changes: `git log` / `git blame` are authoritative.
- Intentional architecture / planning: use [`../docs/`](../docs/README.md).
- TODOs and planned work: use GitHub issues.

## Format

Each page is one `.md` file with frontmatter:

```yaml
---
name: kebab-case-slug
description: one-line summary, used in search snippets
type: user | feedback | project | reference
status: active | resolved   # project notes only; omit on other types
---
```

The filename (e.g. `my_topic.md`) does not need to match `name`; cross-links use the frontmatter `name` slug.

This schema applies to memory **pages**. Tool-managed ledgers under `pr_reviews/` and `sentry_feedback/` are exempt — they keep their owning skills' frontmatter; see [PR review ledgers](#pr-review-ledgers) and [Sentry feedback ledgers](#sentry-feedback-ledgers).

Types:

- `user`: user facts and preferences.
- `feedback`: user corrections and validated approaches.
- `project`: non-derivable ongoing context; convert relative dates to absolute.
- `reference`: library quirks, external refs, and other durable learnings.

`project` notes must include `status: active` while the incident or investigation is live. Set `status: resolved` and move to `memory/archive/` when verified done.

For `feedback` and `project`, lead with the rule/fact, then:

```
**Why:** <reason: past incident, constraint, strong preference>

**How to apply:** <when/where this kicks in>
```

Use `[[page-name]]` to cross-link pages.

## Archive

When a note is no longer relevant for day-to-day lookup — resolved incidents, superseded guidance, outdated context — move it to `memory/archive/` with `status: resolved`. Archived notes stay in git for history but are excluded from `qmd` indexing — the `memory` collection ignores `archive/**` — so stale pages do not compete with live notes in search.

## PR review ledgers

`memory/pr_reviews/<pr-number>.md` files are tool-managed review ledgers written by the `/review`, `/prfix`, and `/team-review` skills. They use those skills' own frontmatter (`pr`, `title`, `branch`, `base`, `repo`) rather than the page schema above, and are excluded from `qmd` indexing — the `memory` collection ignores `pr_reviews/**` alongside `archive/**`. `/team-review` only appends `pending` findings for a later `/review` pass; don't reformat ledgers to the page schema or hand-edit them; the skills own their lifecycle.

## Sentry feedback ledgers

`memory/sentry_feedback/<path-safe-slug>.md` files (slug `:` replaced with `-`, e.g. `podhaven-7485822944.md`) are tool-managed triage ledgers written by the `analyze-sentry-feedback` skill — one per Sentry feedback item, with skill-owned frontmatter (`slug`, `shortId`, `description`, `sentry-status`) and a newest-first session log. Unlike `pr_reviews/`, they stay in the `qmd` index so past feedback analyses surface in topical search. Don't reformat them to the page schema; the skill owns their lifecycle.
