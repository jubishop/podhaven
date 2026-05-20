---
status: planning
---

# Scaling Memory Search

`memory/` is a flat folder of `.md` notes discovered through `qmd` hybrid
search. It works well at today's size (13 pages, ~745 lines). This initiative
addresses what happens as the corpus grows: a `qmd search` / `qmd query` for
some keyword set returns a result list dominated by notes that are stale or
only tangentially related. The agent then burns context triaging them or —
worse — acts on a resolved incident as if it were still live.

## The Real Failure Mode

`qmd` already does ranked hybrid retrieval and has a reranker (the
`--no-rerank` flag in `AGENTS.md` implies the default reranks). So the risk is
not "qmd returns 500 hits" — an agent reads the top-K. The risk is **relevance
dilution**:

- **Stale matches.** A `project`-type incident note keeps matching its
  keywords forever. `project_nowplaying_desync_bug.md` will surface for
  `scrub`, `background pause`, and `AirPods` long after that bug is closed,
  and nothing in the result tells the agent it is history.
- **Topic fan-out.** The current pattern trends toward one note per incident.
  Three recommendation notes already exist (`recommendation_sort_prewarming`,
  `recommendation_engine_full_library_rescan`,
  `podcast_detail_recommendation_storm`). Left unchecked, file count grows
  linearly with incidents, and near-duplicate notes share keywords — pushing
  the one pertinent note down the ranking.
- **Snippet noise.** `qmd` shows the frontmatter `description` in search
  snippets. A vague description forces a `qmd get` body fetch just to decide
  relevance, which defeats the point of the snippet.

The fix is curation and lifecycle, not search-engine tuning. The goal: keep
the *active, indexed* corpus roughly bounded even as total history grows.

## Proposed Changes

In rough impact order.

### 1. Give memories a lifecycle

`project`-type notes are inherently temporary — the `memory/README.md` scope
already calls them "open incidents and active investigations." Today nothing
retires them.

- Add a `status:` field to frontmatter for `project` notes: `active` or
  `resolved`.
- When the underlying incident is closed and verified, move the note to
  `memory/archive/`.
- Exclude `memory/archive/` from `qmd` indexing (or index it at low weight) so
  resolved incidents stop competing with live notes. The history is still in
  git and on disk; it just leaves the default search surface.

This is the single highest-impact change: it caps the active corpus instead of
letting it grow monotonically. Durable `user` / `feedback` / `reference` notes
are unaffected and stay indexed.

### 2. A forcing function for consolidation

`memory/README.md` says "update an existing related page when possible" but
nothing enforces it. Add a concrete rule: when a third note on one topic would
be created, merge the set into a single topic page instead. Pair it with an
occasional curation pass (see Automation below). This keeps file count
sublinear in incident count and prevents keyword-sharing duplicates.

### 3. Make `description` carry triage weight

Because `qmd` shows `description` in snippets, a crisp scope clause lets the
agent reject an irrelevant hit without a body fetch. Standardize a short
"applies when…" clause in every `description`. `recommendation_sort_prewarming`
already does this well; the format section of `memory/README.md` should
mandate it.

### 4. Faceted scope via tags or subdirectories

Add an `area:` frontmatter field (e.g. `playback`, `recommendations`, `db`,
`testing`, `build`), or shard `memory/` into `memory/<area>/`. Either lets a
search be deliberately scoped. This ranks below 1–3 because `qmd` ranking
already handles relevance — its main value is letting the agent narrow on
purpose and helping humans navigate.

### 5. Tighten the consuming guidance

`AGENTS.md` currently defaults fuzzy lookup to `--no-rerank`. As the corpus
grows, reranking is exactly what fights dilution. Flip that default for
open-ended queries, and instruct agents to cap results at a small top-K.

## Automation and Forcing Functions

Changes 1–3 add curation discipline, which erodes unless something enforces it.
Options, lightest first:

- **Issue-linked archival.** Let a `project` note carry its GitHub issue
  number; a periodic check (or a hook) flags notes whose issue is closed as
  archival candidates.
- **Corpus-health check.** A lightweight script reports memory count, oldest
  `active` `project` note, and any topic with three or more notes — surfaced
  when it crosses a threshold so a curation pass is prompted, not forgotten.
- **Index exclusion wiring.** The `bin/hooks/` re-index hooks (`qmd update` /
  `qmd embed`) must be confirmed to respect an `archive/` exclusion, whether
  via `qmd` config or a `.qmdignore`-style mechanism.

## Open Questions

- Does `qmd` support frontmatter-field filtering (`type:`, `area:`, `status:`)
  natively, or must scoping be done through path/subdirectory and query terms?
- Does `qmd` support per-path indexing weights, or only include/exclude?
- Best archival trigger: manual on incident close, issue-state polling, or a
  hook on issue-close webhooks.

## Non-Goals

- Replacing `qmd` or changing its search algorithm.
- Deleting history — archived notes stay in git and on disk.
- Auto-generating or auto-summarizing memory content.
- Restructuring `docs/` or the GitHub-issues workflow; this initiative is
  scoped to `memory/`.
