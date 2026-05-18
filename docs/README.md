# Design Docs

PR-reviewed architecture, initiatives, and research. Use [`memory/`](../memory/README.md) for captured notes and GitHub issues for TODOs.

Every doc starts with:

```yaml
---
status: planning | in-progress | shipped | blocked | abandoned
---
```

Statuses: `planning` = design captured; `in-progress` = implementation started; `shipped` = complete with no body TODOs; `blocked` = paused externally; `abandoned` = dropped but kept for history.

Put multi-PR build plans in `docs/initiatives/` and decision surveys in `docs/research/`. Update the lists below when adding/removing docs.

## Initiatives

- [ML Recommendations](initiatives/ml-recommendations.md): on-device ML recommendations with `NLContextualEmbedding`; in progress
- [Episode Transcripts](initiatives/transcripts.md): RSS transcript parsing plus background/user-initiated transcript fetching; abandoned
- [Smart Lists](initiatives/smart-lists.md): editable nested episode-list filters with persisted ordering; planning
- [Search Recommendations](initiatives/search-recommendations.md): rank unsubscribed-podcast episodes in search/trending with existing similarity scoring; foundations shipped, discovery UI planned

## Research

- [Embedding Model Alternatives](research/embedding-model-alternatives.md): on-device replacements for `NLContextualEmbedding`; waiting on WWDC '26 `FoundationModels`
- [Swift Backtrace API for Telemetry](research/swift-backtrace-telemetry.md): SE-0419 `Backtrace` for logs; blocked by missing `Runtime` on `iphoneos`/`iphonesimulator`
