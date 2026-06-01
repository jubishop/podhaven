# Memory audit (scheduled)

Deep curation pass on `memory/`. For every active note, read the full body, extract concrete claims, and verify each claim against the current repo before deciding to keep or archive. Open a PR only when you move files.

## Scope

- Include: `.md` files directly in `memory/` except `README.md`.
- Exclude from moves: `memory/archive/**`, `memory/pr_reviews/**`.

## Memory format (fix violations on files you touch)

```yaml
---
name: kebab-case-slug
description: one-line snippet with "applies when…" scope
type: user | feedback | project | reference
status: active | resolved      # project only
---
```

- `feedback` / `project`: rule first, then **Why:** and **How to apply:**.
- Cross-links: `[[kebab-case-name]]` (frontmatter `name`, not filename).
- Do not use memory for code conventions derivable from source, git history, `docs/` planning, or open TODOs (GitHub issues).

## Repo context (before per-note analysis)

Establish what changed since the last audit and what's still in flight:

### Since last run

1. Find the previous successful audit:
   `gh run list --workflow=memory-audit.yml --status success --limit 1 --json completedAt`
2. Use that `completedAt` as `--since`. If none exists (first run), use **7 days ago** (weekly schedule).
3. Review commits since then:
   `git log --since="<date>" --oneline --no-merges`
4. For commits touching areas a memory note covers, read the diff (`git show <sha> --stat` / read changed files). Recent merges fixing a noted bug or removing noted instrumentation are strong archive signals.

Record the since-date and a short summary of relevant commits in the report.

### Outstanding GitHub issues and PRs

For every active memory note — not only ones that cite an issue number:

1. List open work: `gh issue list --state open --limit 100` and `gh pr list --state open --limit 100`.
2. For any `#NNN` or PR URL in the note: `gh issue view NNN` / `gh pr view NNN` (state, title, linked PRs, closing commits).
3. Search open issues/PRs by keywords from the note's topic (file names, subsystem, error strings, test names). An open issue or in-flight PR on the same topic → **keep** unless the note is clearly superseded by that work.
4. A **closed** issue/merged PR that fully addresses the note's incident → strong **archive** signal when code matches.

Record which open/closed issues and PRs you checked per note in the report.

## Per-note analysis (required for every active file)

Do not archive from frontmatter or title alone. For each note, work through these phases and record evidence in the report.

### 1. Extract claims

From the body and frontmatter, list concrete, checkable claims:

- Named files, types, methods, tests, factories, env vars, build settings
- Behaviors ("X breaks when Y", "must use Z pattern")
- Referenced GitHub issues/PRs, SHAs, build numbers, Sentry feedback IDs
- Dates of last incident or "still open" language
- Prescriptive rules the note tells future agents to follow

### 2. Verify against the repo

For each claim, gather current evidence:

| Check | How |
| ----- | --- |
| Code still matches | `rg` + read the cited files/symbols; confirm APIs, patterns, and guards described in the note still exist as stated |
| Fix landed | If the note describes a bug + fix, find the fix in current code (not just that an old SHA existed); confirm the described failure mode is addressed |
| Recent commits | Cross-check `git log --since=<last-run>` for changes to cited paths; did a merge this week close out the investigation? |
| Regression test | If the note cites a test, confirm the test file/method exists and still encodes the invariant |
| Cited issue/PR | `gh issue view` / `gh pr view` for any `#NNN` or PR URL in the note |
| Related open work | Search open issues/PRs for the note's topic — still in flight? |
| Superseded | Search for newer code/docs that replace what the note teaches; check `docs/` and sibling memory notes |
| Derivable? | If the note only restates what a reader would learn from reading the code + `AGENTS.md`, it may not belong in active memory |
| Still actionable? | For `feedback`/`reference`: would a competent agent still need this note to avoid a mistake, or is it historical color? |

Use `git log -1 --format=%ci -- <path>` on key files when "when was this last touched?" matters for stale investigations.

When a note is long (incident timeline), focus verification on the **current recommended behavior** and whether the underlying problem is still open — not every historical paragraph.

### 3. Classify

Assign exactly one verdict per note — **keep** or **archive**. No "uncertain" bucket; use your best judgment from the evidence you gathered. Any archival PR is human-reviewed before merge.

| Verdict | Meaning |
| ------- | ------- |
| **keep** | Still live, still actionable, or still teaches something non-derivable |
| **archive** | Resolved, superseded, derivable from code/docs, or historical-only |
| **consolidate-candidate** | Overlaps heavily with another active note — pick **keep** or **archive** for this run anyway, and flag the overlap for human merge |

Fix wrong `type` / `status` frontmatter when you archive (or in the same PR if you touch the file).

**Archive** examples:

- `project` + fix is in `main`, tests/issues closed, and the note's "How to apply" is obsolete or duplicated elsewhere
- Investigation note whose only value was pre-fix logging — instrumentation merged, no open thread
- `reference` describing API behavior that changed (Factory v2 patterns when codebase is fully on v3)
- `feedback` rule contradicted by current code and `AGENTS.md`

**Keep** examples:

- Open bug with recent reports or diagnostic code still intentionally in place
- Durable constraint not obvious from code (user/device prefs, CI gotchas, non-derivable workflow)
- Reference material still needed despite code existing (explains *why*, not just *what*)

When evidence is mixed, decide anyway and state what tipped the scale in the report.

## Archive procedure

1. `git mv memory/<file>.md memory/archive/<file>.md` (preserve filename).
2. Set `status: resolved` on archived `project` notes.
3. Fix broken `[[wiki-links]]` on related live notes if needed.
4. Do not delete files or edit unrelated code/docs.

## Pull request

- Moved files → commit `memory: archive stale notes from scheduled audit`, push; let auto-create-PR open the PR.
- PR body: per archived file, one-line reason **with evidence** (e.g. "issue #357 closed, `performAppear` guard at `PodcastDetailViewModel.swift:…`").
- No moves → no git commits, no PR.

## Run artifact (always)

Write to `artifacts/memory-audit-report.md`:

- This is a **cloud agent artifact** path, not a git commit.
- Do **not** commit the report when there are no archival changes.
- CI downloads it after the run completes via the Cursor artifacts API.

```markdown
# Memory audit report

- Run date (UTC): <ISO-8601>
- Since last audit: <date>
- Relevant commits since then: <brief summary or "none">
- Active notes reviewed: <count>
- Archived: <count>
- Kept: <count>
- Consolidate candidates: <count>

## Per-note findings

| File | Type | Verdict | Key evidence |
| ---- | ---- | ------- | ------------ |
| ... | project | keep | #412 open; PR #420 in flight; PlayManager.swift touched this week |
| ... | project | archive | #357 closed+merged; fix at …; no open related issues |

## Archived

| File | Reason | Evidence |
| ---- | ------ | -------- |
| ... | ... | issue state, code path, test |

## Kept (no action)

| File | Why still relevant | Evidence checked |
| ---- | ------------------ | ---------------- |
| ... | ... | symbols/issues verified |

## Consolidate candidates

| Files | Overlap | This run's verdict |
| ----- | ------- | ------------------ |
| ... | ... | keep / archive |
```

If nothing archived, Archived section: `_None._`

## Process

1. Establish since-date (last successful audit run, or 7 days).
2. Review `git log --since=…` and open issues/PRs (`gh issue list`, `gh pr list`).
3. List all active memory files.
4. For each file: extract claims → verify in repo, commits, and GitHub → assign verdict (use `qmd search` only to find related notes for overlap detection).
5. Write the full per-note findings table before moving anything.
6. Move every **archive** verdict to `memory/archive/`.
7. Write `artifacts/memory-audit-report.md`.
8. Commit and push only if you archived files.
