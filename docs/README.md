# Design Docs

PR-reviewed architecture, initiatives, and research. Use [`memory/`](../memory/README.md) for captured notes and GitHub issues for TODOs.

Every doc starts with:

```yaml
---
status: draft | current | superseded | archived
---
```

Status describes document authority, not implementation progress. Use `draft` or `current` for active docs and `superseded` or `archived` under `docs/archive/`. Track implementation progress in GitHub issues and the document body. Put multi-PR build plans in `docs/initiatives/` and decision surveys in `docs/research/`. Update the lists below when adding/removing docs.

## Development

- [Development workflow](development-workflow.md): setup, search, hooks, diagnostics, and automatic cache cleanup

## Initiatives

- [ML Recommendations](initiatives/ml-recommendations.md): on-device ML recommendations with `NLContextualEmbedding`
- [Episode Transcription](initiatives/manual-transcripts.md): current user-directed transcription, publisher imports, durable queues, timed segments, and transcript UI
- [Smart Lists](initiatives/smart-lists.md): editable nested episode-list filters with persisted ordering
- [Search Recommendations](initiatives/search-recommendations.md): rank unsubscribed-podcast episodes in search/trending with existing similarity scoring
- [Freshness Cadence Cache](initiatives/freshness-cadence-cache.md): cache auto-inferred `FreshnessCadence` in a column so scoring stops re-deriving it from episode pubDates
- [Auto-Skip Silence](initiatives/auto-skip-silence.md): compare playback architectures for skipping silent segments with global, podcast, and current-episode controls

## Research

- [Deferred transcription research](research/transcription-futures.md): autonomous work, speaker diarization, global search, summaries, and locale support

- [UserDefaults Storage Audit](research/userdefaults-storage-audit.md): key-by-key standard/app-group inventory, measured size and cadence, wrapper policy, and deferred transcription-queue follow-up
- [Embedding Model Alternatives](research/embedding-model-alternatives.md): on-device replacements for `NLContextualEmbedding`
- [SQLite Smart List Optimizer Maintenance](research/sqlite-smart-list-optimizer-maintenance.md): SQLite `PRAGMA optimize`, planner stats, and GRDB connection behavior behind Smart List performance maintenance
- [Swift Backtrace API for Telemetry](research/swift-backtrace-telemetry.md): SE-0419 `Backtrace` for logs
