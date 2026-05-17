# Design Docs

Intentional artifacts — architecture, initiatives, and research written on purpose. PR-reviewed because the content is deliberate. Contrast with [`knowledge/`](../knowledge/README.md), which holds *discovered* learnings (gotchas, post-mortems, workarounds) captured because they happened.

Decision rule for a new page: *did I write this on purpose, or am I capturing something that happened?* Intentional → `docs/`. Discovered → `knowledge/`.

## Frontmatter

Each doc starts with a YAML frontmatter block:

```yaml
---
status: planning | in-progress | shipped | blocked | abandoned
---
```

- `planning` — design captured, no implementation merged
- `in-progress` — implementation work has merged
- `shipped` — feature complete and merged; no remaining TODOs in the body
- `blocked` — paused pending an external event
- `abandoned` — explicitly dropped; doc kept for history

The weekly status-sync routine reads recent PR history and flips the `status:` field automatically when evidence supports a forward transition. It never edits narrative prose. Transitions INTO `blocked` or `abandoned` are human-only — edit by hand.

## Where to put a new doc

- `docs/initiatives/` — multi-PR design work you intend to build (or are building). New initiatives start at `planning`.
- `docs/research/` — surveys, evaluations, and option analyses where the output is a decision or recommendation rather than an implementation. Typically `planning` or `blocked`.

Add the new doc to the index below.

## Initiatives

- [ML Recommendations](initiatives/ml-recommendations.md) — on-device ML episode recommendation engine using `NLContextualEmbedding`; v1 across PR #117 + `worktree-appleMLRecommendations-UI`
- [Episode Transcripts](initiatives/transcripts.md) — three-tier on-device transcript strategy (`<podcast:transcript>` RSS parse + opportunistic `BGProcessingTask` for queue/On Deck/top-rec + user-initiated `BGContinuedProcessingTask`); planning only
- [Smart Lists](initiatives/smart-lists.md) — user-editable filter rules replacing the hardcoded `EpisodesView` lists; one-level-nested any/all groups, drag-to-reorder hub, per-list editor sheet, sort persisted on row; planning only
- [Search Recommendations](initiatives/search-recommendations.md) — rank episodes of unsubscribed podcasts from search results *and* trending-category chips (including "Top") via the existing similarity scorer; banner above grid opens a search-specific discovery episode list that fills in rolling as RSS fetches + on-the-fly embeddings complete; planning only

## Research

- [Embedding Model Alternatives](research/embedding-model-alternatives.md) — survey of replacements for `NLContextualEmbedding`; on-device-only constraint narrows it to CoreML-converted Sentence-BERT (MiniLM/BGE), but holding for WWDC '26 in case `FoundationModels` exposes an embedding API
