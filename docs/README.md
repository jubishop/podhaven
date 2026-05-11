# Design Docs

## Initiatives

- [ML Recommendations](initiatives/ml-recommendations.md) — on-device ML episode recommendation engine using `NLContextualEmbedding`; v1 across PR #117 + `worktree-appleMLRecommendations-UI`
- [Episode Transcripts](initiatives/transcripts.md) — three-tier on-device transcript strategy (`<podcast:transcript>` RSS parse + opportunistic `BGProcessingTask` for queue/On Deck/top-rec + user-initiated `BGContinuedProcessingTask`); planning only
- [Smart Lists](initiatives/smart-lists.md) — user-editable filter rules replacing the hardcoded `EpisodesView` lists; one-level-nested any/all groups, drag-to-reorder hub, per-list editor sheet, sort persisted on row; planning only
- [Search Recommendations](initiatives/search-recommendations.md) — rank episodes of unsubscribed podcasts in search results via the existing ML engine; banner above search grid opens a discovery `EpisodesListView` that fills in rolling as RSS fetches + on-the-fly embeddings complete; planning only
