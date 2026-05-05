# Episode Transcripts

On-device transcription of podcast episodes for search and (future) summary generation. No code yet — design conclusions captured 2026-05-05.

## Status

Planning only. iOS 26 minimum. No timeline committed.

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

Prefer `text/vtt` > SRT > plain text. Fetch lazily on first access (or eagerly during cache, since the audio is already being downloaded).

`Feed/Models/PodcastRSS.swift` does not parse the `podcast:` namespace today — that's the work.

### Tier 2 — Opportunistic on-device via `BGProcessingTask`

iOS 26+ `SpeechAnalyzer` + `SpeechTranscriber` with `preset: .offlineTranscription`, run from the existing `BackgroundTaskScheduler` template (the same one `EmbeddingProcessor` uses). Transcribes one episode per wake against the cached audio file, persists segments incrementally so a kill mid-episode resumes via "needs transcript" query on the next wake.

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

## Why we don't try to keep up

A heavy listener can subscribe to ~5 hours/day of new audio. At 5× realtime that's ~60 minutes of sustained Neural Engine compute to transcribe daily — and iOS realistically grants on the order of 20–60 minutes of cumulative `BGProcessingTask` time per day to a well-behaved app. Even on a good night that's right at the edge; on a bad night (thermal, system busy, iOS expires the task) the backlog grows.

The honest user model: heavy subscribers don't *play* 5 hours/day. They play 1–2 hours of episodes mostly drawn from queue + On Deck + a few impulse picks. Transcribe that working set; let the long tail go untranscribed unless and until played. The product framing should match: **"transcripts for what you're about to play,"** not "transcripts for everything."

## Persistence sketch

New migration. Two tables:

- `transcript` — one row per episode that has been transcribed. Columns roughly: `episodeId` FK, `source` enum (`rss` / `onDevice`), `locale`, `modelRevision` (only meaningful for on-device — bumping invalidates), `status` enum (`pending` / `inProgress` / `complete` / `failed`), `completedThrough` for resume after BG expiry, `creationDate`.
- `transcript_segment` — one row per segment. Columns: `transcriptId` FK, `startTime`, `endTime`, `text`. Indexed on `(transcriptId, startTime)` for cheap "what's the active segment at time T" lookups during playback.

Storage cost is small — an hour-long episode is on the order of 10–20 KB of segment rows. Don't compress; keep it queryable.

`modelRevision` lets us invalidate and re-transcribe when Apple ships a meaningfully better model, the same pattern `EmbeddingService.recipeVersion` uses. RSS-sourced rows are immune to this — they never re-fetch on model bumps.

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
