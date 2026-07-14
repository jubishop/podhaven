---
status: abandoned
---

# Episode Transcripts

> **Superseded for v1 by [Manual Episode Transcription](manual-transcripts.md).** The autonomous, three-tier, two-table design below was not built — v1 ships user-initiated, on-device transcription storing timed segments as JSON in a single `episode.transcript` column. This doc is retained as the **research record for the deferred pieces**: RSS `<podcast:transcript>` import (Tier 1), opportunistic/autonomous transcription (Tier 2), speaker diarization, and transcript search/summaries. Pick those up here.

On-device transcription of podcast episodes for search and (future) summary generation. Design conclusions captured 2026-05-05; RSS-format and diarization research added 2026-06-13.

## Status

Abandoned as a standalone initiative. The salvageable research below feeds future tiers layered on top of the v1 manual feature. iOS 26 minimum.

## Why

Episode search today matches against title + description, which misses the substance of the episode. Transcripts unlock real content search, and downstream open the door to Apple Intelligence summaries, chapter generation, and quote/clip features.

## Constraints

These shape every decision below.

- **No servers, no subscription fees.** PodHaven stays local-first. Anything that requires standing up infrastructure or charging users is out.
- **No third-party transcript APIs** (Taddy, Pod Engine, Podscan). Per-episode pricing scales with heavy users — exactly the wrong incentive — and would phone home about every episode the user plays. PodHaven currently sends no playback telemetry to anyone; that's worth preserving.
- **No Apple Podcasts transcripts API.** Apple auto-generates transcripts inside the Apple Podcasts app (iOS 17.4+) but exposes nothing to third parties. The iTunes Search API has no transcript field and never has.

## Strategy: three tiers

Cheapest path first, most reliable path last. Each tier feeds the same `transcript` table; consumers don't care which tier produced a row.

### Tier 1 — RSS `<podcast:transcript>` during feed refresh

The Podcasting 2.0 RSS namespace lets publishers attach a transcript URL directly:

```xml
<podcast:transcript url="https://example.com/ep42.vtt" type="text/vtt" />
```

Coverage in the wild varies wildly by host. A scan of the user's 165 subscribed feeds showed very few publish this tag — but parsing it is small and free, so the few episodes that do come along get transcripts at zero compute cost and with no iOS-version requirement.

Whether the tag is useful depends entirely on its `type` — it is **not** always "just raw text":

| `type` | Timed? | Speaker labels? | Notes |
| --- | --- | --- | --- |
| `text/vtt` (WebVTT) | Yes — cue start/end (segment-level) | Optional, via `<v Name>` voice tags | Most common machine export; maps directly onto `TranscriptSegment`. |
| `application/srt` / `application/x-subrip` | Yes — segment-level | Possible (inline) | Same shape as VTT. |
| `application/json` (Podcasting 2.0) | Yes — per-segment, often word-level | **Yes** — `segments[].speaker` alongside `startTime`/`endTime`/`body` | Richest: this format alone supplies diarization for free. |
| `text/html` | No | No | Formatted prose; store untimed (readable, no seek). |
| `text/plain` | No | No | Raw text; untimed. |

So a VTT/SRT/JSON `<podcast:transcript>` carries the same timing the on-device path produces and drops straight into the v1 timed-segment column model; a JSON one even supplies the speaker labels we otherwise defer. Only HTML/plain are untimed. Coverage in the wild is low and skews VTT/SRT, so treat RSS transcripts as a **bonus source** that pre-empts on-device compute when present: prefer `json > vtt > srt > html/plain`, and fetch lazily (or eagerly during caching, since the audio is already downloading).

`Feed/Models/PodcastRSS.swift` does not parse the `podcast:` namespace today — that, plus a small VTT/SRT/JSON → `[TranscriptSegment]` parser, is the work.

### Tier 2 — Opportunistic on-device via `BGProcessingTask`

iOS 26+ `SpeechAnalyzer` + `SpeechTranscriber` with `preset: .offlineTranscription`, run from the existing `BackgroundTaskScheduler` template (the same one `EmbeddingProcessor` uses). Transcribes one episode per wake against the cached audio file, persists segments incrementally so a kill mid-episode resumes via "needs transcript" query on the next wake.

(v1 diverged: it configures `SpeechTranscriber(attributeOptions: [.audioTimeRange])` directly — `preset: .offlineTranscription` is superseded by the current API — and persists the finished transcript as JSON in one column rather than an incremental segment table.)

Scoped to a **priority queue**, in order:

1. Episodes in the queue
2. Episodes in On Deck
3. High-score recommendations (top N from `RecommendationEngine`)

Anything outside that set is skipped. The "transcribe everything in the feed autonomously" version doesn't work — see "Why we don't try to keep up" below.

`requiresExternalPower = true` for this task. The compute is heavy enough (4–6× realtime, ~12 min for an hour episode) that thermal cost off-charger isn't worth it, and overnight charging is when the system is most generous with background runtime anyway.

### Tier 3 — User-initiated `BGContinuedProcessingTask`

iOS 26's new user-initiated background API. Two trigger points:

- **Play-time:** when the user taps play on an episode that has no transcript, kick off a `BGContinuedProcessingTaskRequest`. System renders a progress UI; user can cancel. Transcript usually finishes within ~10–15 min of starting an hour episode, well before they're halfway through.
- **Explicit "Transcribe" button** on the episode detail view, for the case where the user wants a transcript without playing.

This is the **guaranteed path** — it's the only one that doesn't depend on iOS giving us discretionary background time. If autonomous tier 2 hasn't gotten to an episode yet, play-time tier 3 catches up.

(v1 diverged: it evaluated and **rejected** `BGContinuedProcessingTask` — heavyweight Live Activity UI, flagged Beta, launch-time reliability reports — and ships a discretionary `BGProcessingTask` instead. A reviver of this tier should re-evaluate the API rather than assume the "guaranteed path" framing; see [Manual Episode Transcription → Key decisions](manual-transcripts.md#key-decisions).)

## Why we don't try to keep up

A heavy listener can subscribe to ~5 hours/day of new audio. At 5× realtime that's ~60 minutes of sustained Neural Engine compute to transcribe daily — and iOS realistically grants on the order of 20–60 minutes of cumulative `BGProcessingTask` time per day to a well-behaved app. Even on a good night that's right at the edge; on a bad night (thermal, system busy, iOS expires the task) the backlog grows.

The honest user model: heavy subscribers don't *play* 5 hours/day. They play 1–2 hours of episodes mostly drawn from queue + On Deck + a few impulse picks. Transcribe that working set; let the long tail go untranscribed unless and until played. The product framing should match: **"transcripts for what you're about to play,"** not "transcripts for everything."

## Persistence sketch

New migration. Two tables:

- `transcript` — one row per episode that has been transcribed. Columns roughly: `episodeId` FK, `source` enum (`rss` / `onDevice`), `locale`, `modelRevision` (only meaningful for on-device — bumping invalidates), `status` enum (`pending` / `inProgress` / `complete` / `failed`), `completedThrough` for resume after BG expiry, `creationDate`.
- `transcript_segment` — one row per segment. Columns: `transcriptId` FK, `startTime`, `endTime`, `text`. Indexed on `(transcriptId, startTime)` for cheap "what's the active segment at time T" lookups during playback.

Storage cost is small — an hour-long episode is on the order of 10–20 KB of segment rows. Don't compress; keep it queryable.

`modelRevision` lets us invalidate and re-transcribe when Apple ships a meaningfully better model, the same pattern `EmbeddingService.recipeVersion` uses. RSS-sourced rows are immune to this — they never re-fetch on model bumps.

(v1 diverged from this two-table sketch: it stores timed segments as JSON in a single `episode.transcript` column — see [Manual Episode Transcription](manual-transcripts.md). Migrating to the `transcript_segment` table here becomes worthwhile if cross-episode search or diarization lands.)

**Implementer note — in-place transcript overwrite.** Any tier that replaces an episode's transcript in place — RSS import (Tier 1), or a model-revision re-transcribe — must do two things v1 deliberately leaves alone. (1) Skip the overwrite when an equivalent transcript already exists: v1 never re-transcribes a transcribed episode (`canTranscribe` is false at `.transcribed`; `TranscriptionProcessor.process` guards `!episode.hasTranscript`), so a needless overwrite is wasted ~5× compute, not just a UI glitch. (2) Invalidate the detail-view memo: `EpisodeDetailViewModel.decodedTranscript` caches the decoded transcript keyed by `episodeID` only, so an in-place change for an episode whose detail is open renders stale until the view is rebuilt — clear `transcriptCache` in `transition(to:)` (the sole post-init `state` writer). Left out of v1 because the overwrite is currently unreachable.

## Speaker diarization (deferred)

Multi-speaker labeling ("who spoke when") is **deferred past v1** but captured here so it can be picked up cleanly.

- **No first-party API.** iOS 26 `SpeechAnalyzer`/`SpeechTranscriber` transcribe but do not diarize; `SpeechDetector` only does voice-activity detection, not speaker identity. There is no Apple on-device diarization to call.
- **The path: FluidAudio** (open-source) — `FluidInference/FluidAudio`, a Swift package wrapping CoreML pyannote models (segmentation + speaker-embedding) plus VAD, optimized for the Neural Engine; supports iOS 17+/macOS 14+. Pipeline mirrors pyannote: powerset segmentation → embedding → VBx clustering, producing time ranges tagged with a speaker index. Models are a ~tens-of-MB CoreML download (Hugging Face `FluidInference/speaker-diarization-coreml`).
- **How it slots in.** Run diarization as a second pass over the same cached `AVAudioFile`, producing `(timeRange, speakerIndex)` spans; map each transcript segment to the speaker whose span covers its start time, and add a `speaker` field to `TranscriptSegment`. This is the point where the single JSON column may be worth migrating to a `transcript_segment` table (per-segment speaker queries; "episodes featuring speaker X").
- **Free alternative when present:** a publisher's `application/json` `<podcast:transcript>` already includes `segments[].speaker` — diarization with zero compute. The RSS Tier-1 importer should preserve it.
- **Cost/UX caveats:** an added model download plus a clustering pass on top of the ~5× transcription cost; speaker counts are estimated, not named; accuracy degrades with crosstalk and music. Gate behind an explicit opt-in.

References: FluidAudio (`github.com/FluidInference/FluidAudio`), Hugging Face `FluidInference/speaker-diarization-coreml`.

## Rejected alternatives

- **Third-party transcript APIs (Taddy, Pod Engine, Podscan, Podchaser, Listen Notes).** Privacy (every episode you play leaks to a vendor), cost (cents per episode × heavy users = real money on a free app), and added external dependency. Not worth it.
- **Self-hosted transcription server.** Pushes infra cost onto the developer with no user-paid plan to fund it. Considered and dropped.
- **WhisperKit fallback for pre-iOS-26.** Adds ~1 GB to the app or a separate model download. Per CLAUDE.md compatibility guidance ("backward compatibility with older iOS versions is not necessary") just gate on iOS 26.
- **Apple Podcasts transcripts API.** Doesn't exist publicly. Apple's transcripts live inside their app only.
- **Autonomous transcription of the entire feed.** Math doesn't work for heavy listeners — see above.

## Open questions

To resolve at implementation time, not now.

- **Locale handling.** Single-locale (en-US) v1 keeps `AssetInventory` model management trivial. Multi-locale means picking a locale per podcast (RSS `<language>`?) and dealing with the per-app installed-locales cap. Probably v1 = en-US only, gated behind a feature check.
- **`DictationTranscriber` fallback** for unsupported locales is a path if multi-locale ever matters, but defer.
- **Search index integration.** FTS5 over `transcript_segment.text`? The recommendation engine and search infrastructure are already separate concerns — work out the search-side join shape when actually building search.
- **Apple Intelligence summaries.** Once transcripts exist, `FoundationModels` can generate per-episode summaries on-device. Out of scope here but informs the persistence shape (don't denormalize hard).
- **`<podcast:transcript>` SRT/VTT parsing.** Need a small parser, or pull one in. Defer the import-vs-roll-our-own decision until implementation.

## Reference: research notes

- WWDC25 277 — "Bring advanced speech-to-text to your app with SpeechAnalyzer"
- WWDC25 227 — "Finish tasks in the background" (BGContinuedProcessingTask)
- Spurlock 2025 — only public hands-on of a full-episode background transcription, confirming `BGProcessingTask` expiry mid-episode on iPhone 17 Pro Max
- Podcasting 2.0 namespace spec for `<podcast:transcript>`
