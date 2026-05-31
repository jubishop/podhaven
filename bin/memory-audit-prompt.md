# Memory audit (scheduled)

Review active notes under `memory/` and archive stale ones to `memory/archive/`. Open a PR only when you move files.

## Scope

- Include: `.md` files directly in `memory/` except `README.md`.
- Exclude from moves: `memory/archive/**`, `memory/pr_reviews/**`.

## Memory format (fix violations you touch)

Each page has YAML frontmatter:

```yaml
---
name: kebab-case-slug          # cross-links use this, not filename
description: one-line snippet  # scope + when to use
type: user | feedback | project | reference
status: active | resolved      # project only; omit on other types
---
```

- `user` / `feedback` / `reference`: durable — keep unless obsolete.
- `project` + `status: active`: open incident — archive when verified done.
- `feedback` and `project`: lead with the rule, then **Why:** and **How to apply:**.
- Cross-links: `[[kebab-case-name]]`.

Do not use memory for code conventions, git history, planning (`docs/`), or TODOs (GitHub issues).

## Relevance

**Keep** unless clearly stale:

- `user`, `feedback`, `reference` — obsolete only if contradicted by current code/docs.
- `project` + `status: active` — still live; verify with `rg`, file reads, `gh issue view` when an issue is cited.

**Archive** when:

- `project` incident resolved and verified (fix merged, no longer reproduces).
- Temporary debugging context now captured in code, tests, or `docs/`.
- Linked GitHub issue closed and note adds no durable learning.

When uncertain, **keep** and note why. Prefer false negatives.

## Archive procedure

1. `git mv memory/<file>.md memory/archive/<file>.md` (preserve filename).
2. Set `status: resolved` in frontmatter.
3. Fix broken `[[wiki-links]]` on related live notes if needed.
4. Do not delete files or edit unrelated code/docs.

## Pull request

- Moved files → commit `memory: archive stale notes from scheduled audit`, push; let auto-create-PR open the PR. PR body lists archived files + kept notes.
- No moves → no git commits, no PR.

## Run artifact (always)

Write the report to `artifacts/memory-audit-report.md`:

- This is a **cloud agent artifact** path, not a git commit.
- Do **not** commit the report when there are no archival changes.
- CI downloads it after the run completes via the Cursor artifacts API.

```markdown
# Memory audit report

- Run date (UTC): <ISO-8601>
- Active notes reviewed: <count>
- Archived: <count>
- Kept: <count>

## Archived
| File | Reason |
| ... |

## Kept (no action)
| File | Reason still relevant |
| ... |

## Uncertain (kept)
| File | Why uncertain |
| ... |
```

If nothing archived, Archived section: `_None._`

## Process

1. Enumerate active memory files; use `qmd search` / `qmd get` only when needed.
2. Read frontmatter + body; cross-check code/issues for `type: project`.
3. Write `artifacts/memory-audit-report.md`.
4. Commit and push only if you archived files.
