---
status: current
---

# Deferred transcription research

This page records questions for future work. It does not authorize implementation.
The [current transcription guide](../initiatives/manual-transcripts.md) owns the
shipped queue, publisher import, persistence, and UI behavior. GitHub issues own
implementation progress. The [superseded design](../archive/transcripts.md)
preserves the original proposals and research dated 2026-05-05 and 2026-06-13.

## Autonomous transcription

The old design proposed an automatically selected working set of episodes. A
future proposal must define user consent, which episodes qualify, a storage
budget, energy limits, and how work yields to explicit requests. It must fit the
current durable queues and avoid duplicate downloads or transcription work.
Measure demand and device cost before choosing a background scheduling policy.

## Speaker diarization

Diarization assigns speech time ranges to distinct speakers. The historical
research considered a separate audio pass using FluidAudio and Core ML models.
That is a candidate to evaluate, not a dependency decision. Verify current API
support, model license, download size, energy use, and accuracy before adoption.

A design must handle overlapping speech and uncertain assignments. It must also
define how publisher speaker labels and locally inferred speakers share a data
model. Segment start-time matching was an early sketch; test boundary errors
before using it. Do not infer a real person's identity from a speaker number.

## Global search and summaries

Evaluate whether segment-level global search needs different persistence from
the current timed segments and Smart List text filters. Define source attribution,
seek behavior, index size, and deletion rules before changing storage. Summaries
need their own quality evaluation and a clear account of which transcript and
model produced them.

## Locale support

Reassess supported languages, model availability, and locale selection against
current device APIs. Preserve the current guide's behavior until a new design and
its implementation are approved. Historical platform limits in the old design
have not been reverified for this documentation migration.
