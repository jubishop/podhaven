# Design Docs

PR-reviewed architecture, initiatives, and research. Use [`memory/`](../memory/README.md) for captured notes and GitHub issues for TODOs.

Every doc starts with:

```yaml
---
status: planning | in-progress | shipped | blocked | abandoned
---
```

`status:` in each doc is authoritative; do not repeat it in this index. Put multi-PR build plans in `docs/initiatives/` and decision surveys in `docs/research/`. Update the lists below when adding/removing docs.

## Initiatives

- [ML Recommendations](initiatives/ml-recommendations.md): on-device ML recommendations with `NLContextualEmbedding`
- [Episode Transcripts](initiatives/transcripts.md): RSS transcript parsing plus background/user-initiated transcript fetching
- [Smart Lists](initiatives/smart-lists.md): editable nested episode-list filters with persisted ordering
- [Search Recommendations](initiatives/search-recommendations.md): rank unsubscribed-podcast episodes in search/trending with existing similarity scoring
- [Scaling Memory Search](initiatives/scaling_memory.md): lifecycle, consolidation, and indexing changes to keep `qmd` memory search relevant as the corpus grows

## Research

- [Embedding Model Alternatives](research/embedding-model-alternatives.md): on-device replacements for `NLContextualEmbedding`
- [Swift Backtrace API for Telemetry](research/swift-backtrace-telemetry.md): SE-0419 `Backtrace` for logs
