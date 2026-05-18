# Design Docs

Intentional artifacts — architecture, initiatives, and research written on purpose. PR-reviewed. Contrast with [`memory/`](../memory/README.md), which holds shorter notes captured as work happens.

## Frontmatter

Each doc starts with:

```yaml
---
status: planning | in-progress | shipped | blocked | abandoned
---
```

- `planning` — design captured, no implementation merged
- `in-progress` — implementation work has merged
- `shipped` — feature complete; no remaining TODOs in the body
- `blocked` — paused pending an external event
- `abandoned` — explicitly dropped; doc kept for history

Edit `status:` by hand when it changes.

## Where to put a new doc

- `docs/initiatives/` — multi-PR design work you intend to build (or are building).
- `docs/research/` — surveys, evaluations, option analyses where the output is a decision or recommendation rather than an implementation.

When adding or removing a doc, **update the lists below**. They exist as a quick human-readable index.

## Initiatives

- [ML Recommendations](initiatives/ml-recommendations.md) — on-device ML episode recommendation engine using `NLContextualEmbedding`; v1 across PR #117 + `worktree-appleMLRecommendations-UI`
- [Episode Transcripts](initiatives/transcripts.md) — three-tier on-device transcript strategy (`<podcast:transcript>` RSS parse + opportunistic `BGProcessingTask` for queue/On Deck/top-rec + user-initiated `BGContinuedProcessingTask`); planning only
- [Smart Lists](initiatives/smart-lists.md) — user-editable filter rules replacing the hardcoded `EpisodesView` lists; one-level-nested any/all groups, drag-to-reorder hub, per-list editor sheet, sort persisted on row; planning only
- [Search Recommendations](initiatives/search-recommendations.md) — rank unsubscribed-podcast episodes from search results and trending chips via the existing similarity scorer; scoring foundations are shipped, while the search banner, collector, and discovery list remain planned

## Research

- [Embedding Model Alternatives](research/embedding-model-alternatives.md) — survey of replacements for `NLContextualEmbedding`; on-device-only constraint narrows it to CoreML-converted Sentence-BERT (MiniLM/BGE), but holding for WWDC '26 in case `FoundationModels` exposes an embedding API
