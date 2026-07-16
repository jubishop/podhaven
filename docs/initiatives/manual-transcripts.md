---
status: in-progress
---

# Manual Episode Transcription

User-initiated, on-device transcription of individual episodes, rendered read-only in `EpisodeDetailView`. iOS 26+. Interactive tap-to-seek is a documented v2. Supersedes — for v1 — the autonomous three-tier design in [Episode Transcripts](transcripts.md) (abandoned).

## Status

The backend transcription runtime from #461 and episode projection support from #507 are merged into `main`. The remaining view integration is in #516 and is building clean, lint-clean, and unit-tested. The on-device `Transcriber` (real speech model) and the `BGProcessingTask` runtime behaviour are integration/device-tested, not in CI; both sit behind protocols/fakes so everything around them is unit-tested. The transcript renders read-only — **interactive playback (tap-to-seek, active-segment highlight, auto-scroll) is deferred to v2**; the per-segment timestamps are already stored, so v2 is purely a UI layer. Also deferred and tracked in [Episode Transcripts](transcripts.md): speaker diarization, RSS `<podcast:transcript>` import, transcript search, autonomous transcription.

## Why

Transcription is expensive — roughly 5× realtime of Neural-Engine compute (~12 min for an hour episode) — so it is strictly **user-initiated, one episode at a time**; nothing transcribes automatically (the cost model for a free, local-first app does not support it). The immediate value: read an episode you can't listen to now. Every segment is timestamped, so a v2 can turn the static transcript interactive — tap a line to jump playback there, with highlight + auto-scroll — without re-transcribing; the timing is already stored.

## Scope

In:
- On supported devices, a manual "Transcribe" action on every episode surface: detail toolbar, detail body, list context menu, swipe action, multi-select. The feature stays hidden until en-US support is positively confirmed.
- A persisted, termination-surviving queue that transcribes one episode at a time off the main actor.
- On-device transcription via iOS 26 `SpeechAnalyzer`/`SpeechTranscriber` against the cached audio file, producing timestamped segments.
- Timed segments stored as JSON in a single new optional `episode.transcript` TEXT column (nil = no transcript).
- Description and Transcription segmented tabs in `EpisodeDetailView`, with a read-only transcript render.
- Per-episode transcription state (queued / transcribing / transcribed / failed) in the detail view, with action availability kept live across the other episode surfaces.

Out (deferred — see [Episode Transcripts](transcripts.md)):
- Interactive transcript: tap-a-line-to-seek, active-segment highlight, auto-scroll. v1 renders read-only; the per-segment timestamps are persisted, so v2 is a pure UI layer (no re-transcription).
- Speaker diarization (no first-party API; FluidAudio is the documented v2 path).
- RSS `<podcast:transcript>` import (a complementary future source that reuses this same segment model).
- Autonomous / opportunistic transcription of the working set.
- Cross-episode transcript search (FTS5) and on-device summaries.
- Multi-locale: v1 is en-US only, gated on model availability.

## Key decisions

- **Timed JSON in one column, not a segment table.** `SpeechTranscriber` yields per-segment (even per-word) time ranges via the `.audioTimeRange` attribute option. We serialize `[TranscriptSegment]` (start time + text) as JSON into a single optional `episode.transcript` TEXT column. v1 renders this read-only, but we **store the per-segment timing now** so a v2 can add tap-to-seek/highlight as a pure UI layer — while honoring the one-column ask and one migration. For a single open episode the whole transcript is held in memory, so no per-segment SQL is needed. The stored fields — segment start + text — migrate without loss to a real `transcript_segment` table if cross-episode search later wants one. Diarization is not a pure migration, though: it needs a fresh second pass to produce speaker spans (no speaker data exists in the JSON to carry over), which is part of why it stays deferred.
- **Discretionary `BGProcessingTask` for background drain (not `BGContinuedProcessingTask`).** We mirror `EmbeddingProcessor`: a foreground background-priority `Task` drains while the app is open, and a registered `BGProcessingTask` lets iOS drain the queue opportunistically when backgrounded. iOS 26's `BGContinuedProcessingTask` was evaluated and rejected — it surfaces a user-facing **Live Activity** (heavyweight/odd for "transcribe an episode"), it's flagged **Beta**, and it had notable reliability reports at the 26.0 launch. The trade: `BGProcessingTask` is discretionary (iOS decides when to grant it — possibly delayed), so a transcription started right before backgrounding resumes on the next grant or the next foreground activation, not immediately. The persisted queue makes every path resumable, and — unlike the beta API — this one is unit-testable with the existing `FakeBGTaskScheduler`.
- **Queue persisted in UserDefaults, not SQLite.** An ordered `[Episode.ID]` via `@PersistedBroadcast("transcriptionQueue")` — the exact shape and mechanism already used by `SharedState.recommendedEpisodePool`. Survives termination, thread-safe, SwiftUI-observable, and streamable, all for free. SQLite is intentionally avoided for this transient work-list.
- **Default-hidden device capability gate.** `TranscriptionAvailability` starts unknown, checks the en-US `SpeechTranscriber.supportedLocales` catalog when the app enters the foreground, and exposes the feature only after a positive result. Unknown and unsupported states render no transcription tabs, buttons, menus, bulk actions, or swipe-setting options. The processor keeps its own support check as a defensive boundary for persisted work.
- **Diarization deferred to v2.** No first-party Apple diarization. FluidAudio (CoreML pyannote, ANE, iOS 17+) is the path; pickup notes live in [Episode Transcripts → Speaker diarization](transcripts.md#speaker-diarization-deferred). A publisher-provided RSS JSON transcript would also supply speaker labels.

## Data model

- **Migration v67** (`PodHaven/Database/Migrations/Migration_v67.swift`, registered `"v67"` in `Schema.makeMigrator()`): `ALTER TABLE episode ADD COLUMN transcript TEXT` — nullable, default NULL, no backfill. Does not trip the `episode_content_updated` trigger (which fires only on title/description change). Migration test `v67Tests.swift` migrates through `"v66"` before asserting the new column.
- **Model:** add `transcript: String?` to `UnsavedEpisode` and `Column("transcript")` to `Episode.Columns`, with a computed `decodedTranscript: Transcript?` that lazily caches its decoded value in memory while persisting only the original JSON.
- **Codable payload:** `struct TranscriptSegment { let start: TimeInterval; let text: String }` plus a `Transcript` wrapper carrying `segments`, `locale`, `createdAt`, and a `modelRevision` (so a future model bump can invalidate, mirroring `EmbeddingService.recipeVersion`). Encoded to the column as JSON; the column holds only the finished transcript — transient queue/progress state never touches the DB.
- **Repo:** `updateTranscript(_ id:transcript:)` mirroring `updateCachedFilename` (nullable single-column `updateAll`).

## Transcription engine — `PodHaven/Transcriptions/`

- **`Transcriber` service**: wraps `SpeechAnalyzer` + `SpeechTranscriber(locale:, attributeOptions: [.audioTimeRange])` behind app-owned speech protocols, feeds the cached `AVAudioFile` through the analyzer to completion, and collects the finalized `results` AsyncSequence; each result's `AttributedString` runs carry an `audioTimeRange` (`CMTimeRange`) whose start becomes the segment `start`. The range's latest end, over the file duration (read up front via the analyzer seam), drives transcription progress, reported as a monotonic `0...1` fraction through an `onProgress` callback. Work stays off MainActor. (Exact file-input entry point per WWDC25 277; use `.audioTimeRange` — the abandoned doc's `preset: .offlineTranscription` is superseded by current API.)
- **Model availability gates** via the speech model-manager seam: the shared UI capability starts hidden and appears only after en-US support is confirmed; the processor independently rejects unsupported hardware/locales before acquiring episode audio. It then checks installed locales and installs the en-US model when missing. en-US only in v1.
- **Audio dependency:** on-device transcription needs the **local** file, not the stream. The processor ensures the episode is cached via `CacheManager.cachedURL(downloadingIfNeeded:)`, which starts or joins the cache download through an `AsyncLatch`, then transcribes the returned cached file URL.

## Queue, processing & state

- **`TranscriptionQueue`** (cached Factory service, `fileprivate init`): `@PersistedBroadcast("transcriptionQueue") var queue: [Episode.ID] = []` (enqueue/dequeue/contains); a head-only `AsyncStream<Episode.ID>` yields the current item and advances after it is removed or failed, replaying a retained head when a lifecycle handoff starts a new stream; `@Broadcasted var progress: [Episode.ID: Double] = [:]` (active-item progress fed live by the engine's `onProgress`, mirroring `SharedState.downloadProgress`); `@Broadcasted var failed: Set<Episode.ID> = []` (transient, cleared on retry/dismiss).
- **`TranscriptionProcessor`** (cached service, mirrors `EmbeddingProcessor` conventions): one `for await episodeID` loop consumes the queue's head-only work stream, ensures audio, runs `Transcriber`, writes `Repo.updateTranscript`, updates progress, and dequeues — strictly one at a time. Foreground and background entry points serialize on shared drain ownership; cancellation releases the retained head back to the stream. Failures are recorded and dequeued. The work source is the **persisted queue**, not a DB "needs work" query — the deliberate divergence from the embedding template (which is autonomous).
- **Background drain:** `TranscriptionProcessor` owns a `BackgroundTaskScheduler(identifier: "\(AppInfo.bundleIdentifier).transcription", cadence: .minutes(1), taskType: .processing(...))` (new identifier in `BGTaskSchedulerPermittedIdentifiers`; the `processing` background mode is already declared). `register()` — called from `AppLauncher`, mirroring `embeddingProcessor.register()` — installs a handler using the same processor loop in a bounded-until-empty mode. Unlike periodic clients, transcription uses the scheduler's on-demand mode: registration submits only when persisted work exists, backgrounding schedules while the queue is nonempty, and draining the last item cancels the successor request. The one-minute value is only the earliest begin date for real queued work; no request is kept pending for an empty queue. On expiry the handler completes `false`, releases its current head, and the persisted queue resumes on the next grant/activation.
- **Per-episode status (mirrors caching's `Episode.CacheStatus` + `downloadProgress`):**

  ```swift
  enum TranscriptionStatus {
    case none, queued(position: Int, total: Int), transcribing(Double), transcribed, failed
  }
  ```

  derived like `Episode.CacheStatus.from(...)`:
  - `.transcribed` ⟸ the caller reports a usable stored transcript (presence on rows; successful decode in detail)
  - `.transcribing(p)` ⟸ id is the active item (`transcriptionProgress[id]`)
  - `.queued(position:total:)` ⟸ the id's one-based index and current depth in the ordered queue
  - `.failed` ⟸ `failed.contains(id)`
  - else `.none`

  A `transcriptionStatus(for:)` accessor drives detail presentation and action eligibility on every surface. Queue/progress are `Broadcast`s, so both stay live without adding transcription indicators to episode rows.

## UI integration (stacked follow-up)

- **Detail body:** a full-width segmented `Picker` switches between Description and Transcription. The Transcription tab shows a CTA when `.none`; exact queue position when `.queued`; a determinate progress bar with percentage when `.transcribing` (an indeterminate spinner before progress climbs above 0); the rendered read-only transcript when `.transcribed`; decode recovery for unreadable stored JSON; and an error + retry when `.failed`.
- **Detail toolbar:** a `ToolbarItem(.primaryAction)` inserted between `ShareEpisodeButton` and the rating `Menu`, so the trailing group reads `[rating] [transcribe] [share]` (primaryAction lays out right-to-left). The transcript glyph stays visible and pulses while transcription is active; the detailed progress remains in the Transcription tab.
- **Shared actions:** add `transcribeEpisode(_:)` to the `ManagingEpisodes` protocol (decl + default impl) → instantly available in the list **context menu** and **swipe actions**; add `transcribeSelectedEpisodes()` to `SelectableEpisodeList` → the **multi-select** batch menu. Enqueue is gated by status (skip already-transcribed/queued/transcribing). `EpisodeDetailViewModel` does not adopt `ManagingEpisodes`, so it gets its own `transcribe()` method.
- **Swipe option in Settings:** add `case transcribe` to `EpisodeSwipeAction` plus its three exhaustive-switch sites (`icon(for:)`, `trailingAction(_:)`, and `isAvailable(_:)`). The option is absent until device support is confirmed, and `isAvailable` hides the configured row action once an episode is transcribed/queued. ("Swipe left" = the trailing-edge actions this codebase models as `trailingAction`.)
- **Icon:** add `AppIcon.transcribeEpisode` (enum case + `Data(...)` + an SF Symbol name).
- **Interactive playback (deferred to v2):** tap-a-segment-to-seek + active-segment highlight + auto-scroll. The plumbing is ready: tapping would use `EpisodeDetailViewModel.loadAndPlay(_:seekTo:)` (seek if on-deck, else load-then-seek), and highlight/auto-scroll would bind to `PodAVPlayer.currentTimeStream` / `sharedState.onDeck?.currentTime`, selecting the active segment by start time. v1 renders read-only; the per-segment timestamps are already persisted.
- **Optional row glyph:** a small "has transcript / transcribing" indicator in `EpisodeListView` rows, alongside the cache indicator, for at-a-glance state.

## Phased build plan

1. **Schema + model** — Migration v67, `transcript` column + `Episode.Columns`, `Transcript`/`TranscriptSegment` Codable, `Repo.updateTranscript`, migration test. (Foundation; nothing user-visible.)
2. **Engine** — `PodHaven/Transcriptions/Transcriber` + speech model gate + the awaited `cachedURL(downloadingIfNeeded:)` cache helper. Unit-tested behind speech-framework protocol seams with fakes.
3. **Queue + processor (foreground)** — `TranscriptionQueue` (persisted) + `TranscriptionProcessor` loop, one-at-a-time, status/progress broadcasts. Tests with speech/cache fakes.
4. **UI (stacked follow-up)** — detail tabs and read-only transcript, toolbar button, `ManagingEpisodes`/`SelectableEpisodeList` actions, context menu, swipe case + settings, multi-select, `AppIcon`, and live action gating across surfaces.
5. **Background drain** — `BGProcessingTask` via the existing `BackgroundTaskScheduler` (new Info.plist identifier, `register()` in `AppLauncher`, `scheduleNext()` on background), mirroring `EmbeddingProcessor`; unit-tested with `FakeBGTaskScheduler`.

Phases 1–3 are independently shippable; 4 makes it usable; 5 completes it. (Interactive playback — tap-to-seek / highlight / auto-scroll — is deferred to v2.)

## Testing

- Migration test (`v67Tests.swift`) — raw SQL, migrate `upTo: "v66"` then `"v67"`, assert the column.
- Queue persistence: enqueue → simulated relaunch (re-read defaults) → order preserved.
- Processor loop: speech/cache fakes drive one-at-a-time ordering, foreground/background exclusivity, progress, dequeue, failure, unsupported-device preflight before audio acquisition, stale-download recovery, and on-demand background scheduling; `FakeBGTask.expire()` verifies that background expiration retains the current head for the next foreground drain.
- Status derivation: each `TranscriptionStatus` branch.
- `Transcriber` against the real model is integration-only; production stays behind the protocol so units use the fake.

## Known follow-ups

- **Audio retention (decided):** transcription downloads the audio if absent via `CacheManager.cachedURL(downloadingIfNeeded:)` and leaves the episode's existing cache/purge policy unchanged — the original lean, no keep-then-restore.
- **Failure surfacing (UI follow-up, with a gap):** the Transcription tab shows an inline "Transcription failed" + Retry; `failed` is transient (cleared on retry or relaunch). Open gap: there is no explicit dismiss affordance, so a user who won't retry can't clear the failed state from the UI.
- **Background-grant timing & thermals (open):** `BGProcessingTask` grants are discretionary and can be delayed; the on-demand request's `.minutes(1)` earliest begin date and `requiresExternalPower = false` are tunable once device-tested (transcription is ~5× realtime, so thermal-gating to charging is a possible future knob). Foreground and background drains share exclusive ownership, so lifecycle handoff cannot double-transcribe a queue head.

## References

- WWDC25 277 — "Bring advanced speech-to-text to your app with SpeechAnalyzer"
- In-repo `BGProcessingTask` template: `EmbeddingProcessor` + `BackgroundTaskScheduler` (+ `FakeBGTaskScheduler` for tests). `BGContinuedProcessingTask` (WWDC25 227) was evaluated and rejected — see Key decisions.
- `SpeechTranscriber.ResultAttributeOption.audioTimeRange`
- In-repo mirror targets: `EmbeddingProcessor`/`EmbeddingService`/`ContextualEmbedding` (background ML template), `CacheManager` + `SharedState.downloadProgress` (state/progress), `SharedState.recommendedEpisodePool` (persisted ID list), `EpisodeDetailViewModel.loadAndPlay(_:seekTo:)` (seek).
