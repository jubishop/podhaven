---
status: planning
---

# Auto-Skip Silence

Automatically skip silent stretches during podcast playback, with the same
three-level control model as playback speed: a global default, a nullable
per-podcast override, and an immediate toggle for the currently playing episode.

## Status

Planning only. No code yet.

## Why

Podcast listeners often want dead air compressed without increasing speech
speed. Playback rate already solves a related preference problem, but it changes
all audio. Auto-skip silence should only remove stretches that are genuinely
quiet, preserving speech cadence, music beds, ads, and other non-silent content.

## Decision status

No playback mechanism is chosen yet.

The settings model and silence-analysis persistence can be planned now, but the
actual playback architecture needs a deliberate decision before implementation.
There are two product behaviors and several implementation paths with different
tradeoffs:

- **Discrete skip.** Detect silent gaps past a minimum duration and remove or
  jump over them; everything else plays untouched. Feels like dead air is gone.
- **Continuous compression.** Shorten pauses by a variable amount in real time,
  with fewer hard boundaries. Feels like the host left less space between words.
  This is closer to Overcast "Smart Speed".

The rest of this doc assumes the feature remains "auto-skip silent segments",
but does not choose whether the skip is implemented with seeks, composition, a
custom engine, or a processing tap. Make that decision after the spikes below.

Read the playback sections as an option set, not a decision record. Each option
is plausible enough to evaluate, and each has enough risk that implementation
should wait until the tradeoffs have been considered again with prototype
evidence.

## Shared analysis conclusion

`AVAssetReader` pre-analysis is still the most likely common piece.

Whether playback ultimately uses `AVPlayer` seeks, `AVMutableComposition`,
`AVAudioEngine`, or an `MTAudioProcessingTap`, PodHaven needs reliable knowledge
of where silent regions are. `AVAssetReader` + `AVAssetReaderTrackOutput` can
decode an `AVURLAsset` audio track to linear PCM for offline analysis. That keeps
silence detection off the render path and lets the app cache analysis results.

The main open question is not "how do we detect silence?" It is "how should the
player consume the detected ranges?"

## Playback options to evaluate

### Option 1: `AVPlayer` seek over ranges

Precompute silent ranges, keep playing the original asset, and call seek when the
current time approaches a silent range.

Pros:

- Smallest change to the current `AVPlayer`/`PodAVPlayer` stack.
- App time remains original episode time; chapters, transcripts, progress,
  `PlaybackCoverage`, Now Playing, and remote scrubs stay conceptually simple.
- Works with remote playback in principle, because the player still consumes the
  original media URL.
- Immediate playbar toggle is simple: enable or disable the skip decision.

Cons:

- Short-gap seeks may click, stutter, or feel worse than the silence they remove.
- VBR MP3 seek accuracy can be loose unless tolerance-controlled seeking is added
  and proven acceptable.
- Skip decisions happen during playback, so the implementation needs lookahead,
  loop guards, and minimum-skip spacing.
- A pause-heavy episode may trigger many seeks.

This remains viable only if the smoothness spike proves seeks over typical
podcast gaps are not audible enough to matter.

### Option 2: `AVMutableComposition` from audible ranges

Precompute silent ranges, derive audible ranges, build an `AVMutableComposition`
by inserting only the audible source ranges, and play the copied `AVComposition`
with `AVPlayerItem`.

Pros:

- Keeps `AVPlayer` as the transport while avoiding repeated runtime seeks.
- Playback can be gapless because the item timeline has no removed silence.
- Non-destructive: the cached source file remains unchanged.
- Avoids VBR seek precision for every skipped gap.

Cons:

- Introduces a source-time to composition-time mapping.
- `PodAVPlayer` must hide composition time from the rest of the app or every
  position consumer becomes more complex.
- `PlaybackCoverage` cannot mark one contiguous original-time interval when a
  compact transport tick crosses a removed silent gap.
- Toggling auto-skip on/off mid-episode means swapping between original and
  composition items while preserving source time, rate, and play/pause state.
- Needs a spike for composition build/playback performance on long VBR MP3 files
  with many inserted segments.
- Likely local-file-first; uncached remote playback may need to run without
  auto-skip until the file is cached and analyzed.

This is a candidate if the product wants discrete skipping and seeks sound bad,
but the mapping cost is real.

### Option 3: `AVAudioEngine` custom playback

Decode or schedule audio through `AVAudioEngine` / `AVAudioPlayerNode` and own
the render timeline directly.

Pros:

- Most control over sample-level behavior.
- Best fit for true continuous compression, crossfades, smoothing, or future DSP.
- Can avoid both seek glitches and composition segment constraints.

Cons:

- Replaces the current transport instead of adapting it.
- Rebuilds behavior around background audio, remote commands, Now Playing,
  interruptions, media-services reset recovery, queue transitions, cached-file
  swapping, and test fakes.
- Timeline mapping is still required if the UI/persistence stay in source time.
- Remote streaming/HLS support becomes a separate problem.

This becomes more compelling if the product target becomes continuous
compression or the AVPlayer-based options fail their spikes.

### Option 4: `MTAudioProcessingTap`

Attach an audio processing tap through `AVAudioMixInputParameters` and inspect or
mutate audio on the render path.

Pros:

- Keeps `AVPlayer` involved.
- Can observe real decoded samples during playback.
- Useful as a live meter, diagnostics feed, or possibly a streaming analysis
  path if offline pre-analysis is unavailable.

Cons:

- A tap does not shorten the `AVPlayerItem` timeline by itself.
- It discovers audio on the render path, which is late for "skip after 0.6s of
  silence" unless playback is delayed or paired with another mechanism.
- To actually remove silence it still needs a seek, a composition/custom item, or
  a custom render engine.
- Tap callback constraints make it the wrong place to perform app-actor seeks or
  persistence work.

This looks more like an auxiliary tool than a complete auto-skip architecture
unless a spike proves it can pair cleanly with a separate removal mechanism.

## Product model

### Global default

Add `UserSettings.autoSkipSilenceByDefault: Bool`, default `false`. This is a
`@PersistedBroadcast("autoSkipSilenceByDefault")` line — `UserSettings` is
UserDefaults-backed, so the global default needs no migration. `enableUndoSeek`
is the existing `Bool` precedent.

Surface it in `SettingsView` under Playback as:

- Label: "Auto-Skip Silence"
- Info text: explains that future episodes use this by default and individual
  podcasts can override it.

### Podcast override

Add a nullable `autoSkipSilence: Bool?` override. The stored field would live on
`UnsavedPodcast` (wrapped by `@Saved`) and be surfaced through `PodcastSettings`,
with the next available migration adding the column (default `NULL`). Existing
nullable overrides are `Double?`/`Int?`/enum?, so a `Bool?` column is a new shape,
but the mechanism is identical to `defaultPlaybackRate`.

`nil` means "use the global default". Non-nil means "always on" or "always off"
for new episodes from that podcast.

There is no central resolver to mirror: `defaultPlaybackRate` is coalesced inline
(`podcast.x ?? userSettings.y`) at every call site, not behind a helper.
Auto-skip must do the same wherever it is read.

Suggested UI in `PodcastSettingsView`. Two existing idioms fit:

- A `.menu` picker whose `nil` tag reads "Default" and whose caption shows the
  resolved value — directly mirrors the `freshnessCadence` override, which tags
  `FreshnessCadence?.none` as "Auto".
- A `.segmented` picker like `queueAllEpisodes`/`cacheAllEpisodes`, but those are
  backed by non-optional enums; a segmented "Default/On/Off" over a `Bool?` is a
  new idiom. Prefer the `freshnessCadence` menu pattern for consistency.

Edits commit to a `@State private var temp: PodcastSettings` and flush via
`viewModel.updateSettings(temp)`, like the other rows.

Do not overload a nullable `Bool` directly into a `Toggle`; the UI needs to
represent all three states.

### Current episode toggle

Add a session value, separate from the persisted global and podcast defaults, as
a new `@Broadcasted var autoSkipSilence: Bool` on `SharedState` — mirroring
`stopAfterCurrentEpisode`, not the `playRate` echo. Seed it on episode load in
`PlayManager.performLoad`, alongside the existing rate resolution, from:

```swift
podcast.autoSkipSilence ?? userSettings.autoSkipSilenceByDefault
```

Expose it on `PlayBarViewModel` and add a control to `PlayBarSheet`. The closest
precedent is `stopAfterEpisodeButton` + `viewModel.toggleStopAfterCurrentEpisode()`
(an on/off icon toggle reading/writing `SharedState`), not the rate `Binding`.
There is no "speed button" in `PlayBarSheet` to sit beside — speed is a separate
`PlaybackSpeedButton` that opens a slider popover; the natural slot is a third
icon button in `metaControlsRow`'s right cluster next to `stopAfterEpisodeButton`
(that row stacks above the chapter controls, so vertical space is tight when
chapters are present).

`AppIcon` has no fitting case today (`waveform.slash` is taken by `.noEpisode`);
add an off/on pair (e.g. `autoSkipSilence`/`autoSkipSilenceOn`) plus a
`SystemImageName`, following the `stopAfterEpisode`/`stopAfterEpisodeOn` pair.

Toggling affects only the current session, like changing playbar speed. Persisting
the toggle back to the episode would be a separate product decision; the rate
precedent suggests keeping the current-episode control transient.

## Silence analysis

### Analyzer

Add a `SilenceAnalyzer` service that runs off the playback hot path. It should:

1. Open the episode audio as an `AVURLAsset`.
2. Use `AVAssetReader` and `AVAssetReaderTrackOutput` to decode the audio track
   to linear PCM.
3. Downmix channels to one analysis stream.
4. Compute RMS over short windows, initially 20 ms.
5. Mark a range as silence only when the level stays below the threshold for at
   least the minimum duration.
6. Merge nearby ranges and drop ranges too close to the beginning/end if needed
   after user testing.

Initial conservative constants:

- Window: 20 ms
- Silence threshold: -45 dBFS
- Minimum silence duration: 0.6 s
- Resume pad: 0.12 s after the silent range
- Start pad: do not skip the first 0.15 s of a detected range

These should live in one config type, versioned with the analyzer. Bumping the
version invalidates old rows — which means every tuning tweak forces a full-file
re-decode of every analyzed episode. Either store the config in the row so
recompute can be selective, or accept the cache churn during early tuning.

A fixed absolute threshold is the weak starting point: mastering levels vary
enough that dead air in a loud show and an intentional quiet bed in another land
on opposite sides of a single dBFS line. A threshold relative to a rolling noise
floor or the track's overall RMS is the likely endpoint; start absolute, expect
to move.

FFmpeg's `silencedetect` / `silenceremove` filters use the same broad model:
volume below a threshold for at least a duration, usually with RMS/windowed
detection. Use that as the mental model, not voice activity detection. VAD is
speech-focused and would risk skipping intentional non-speech audio that is not
silent.

### When to analyze

Analyze only audio files PodHaven already has locally:

- Current On Deck episode after it has been cached.
- Queue episodes after download completion.
- Episodes explicitly saved in cache.

Do not stream-download a second copy just to analyze silence. `AVAssetReader`
can read `AVURLAsset`, but silence analysis is full-file decoding work; doing
that against remote media competes with playback and adds network cost for a
feature that should feel opportunistic.

If the user starts playback before analysis exists, play normally and enable
auto-skip once the map arrives. Avoid a loading gate.

### Background work

`EmbeddingProcessor` is the precedent to consider: a `BackgroundTaskScheduler`
(`BGProcessingTaskRequest`) background drain plus a foreground drain triggered by
a GRDB observation signal with a `Debounce`, fetching IDs only and hydrating in
chunks. An implementation could start with the foreground/utility path triggered
by cache completion and On Deck. Analysis is much cheaper than transcription, but
it is still full-file audio decode, so keep it cancellable and treat
`CancellationError` as a clean stop.

Prefer one episode at a time. More concurrency increases thermal and I/O cost
without much user-visible benefit.

Background scheduling is unreliable on device debug builds, so validate the drain
on a release build or through the foreground path.

## Persistence

Use a separate table rather than adding a heavy blob to the hot episode model.
Write it with GRDB's table builder (this repo never hand-writes `CREATE TABLE`
SQL in migrations), modeled on `episodeEmbedding`, in the next available
migration:

```swift
try db.create(table: "episodeSilenceAnalysis") { t in
  t.autoIncrementedPrimaryKey("id")
  t.belongsTo("episode", onDelete: .cascade).notNull().unique()
  t.column("sourceMediaURL", .text).notNull()
  t.column("duration", .double).notNull()
  t.column("algorithmVersion", .integer).notNull()
  t.column("status", .text).notNull()
  t.column("ranges", .blob)
  t.column("analyzedThrough", .double)
  t.column("errorMessage", .text)
  t.column("creationDate", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
}
```

Notes on the shape:

- Satellite tables here use a separate `autoIncrementedPrimaryKey("id")` plus
  `belongsTo("episode").unique()`, not the episode FK as the primary key.
- `duration` is `.double` for sub-second precision; the episode table stores its
  `duration` as `.integer` (floored seconds), so this is a deliberate divergence,
  not an oversight.
- There is no `updateDate` precedent — the repo maintains `contentUpdatedAt` via a
  SQL trigger. If a mutation timestamp is needed, follow that or drop it.
- The cached-file column is `cachedFilename`, not `sourceCachedFilename`, and it is
  deterministic from the media URL, so it is not an independent input — drop it
  from the row (see invalidation below).

`ranges` is a `(startSeconds, endSeconds)` list. `PlaybackCoverage` is a packed
occupancy *bitmap* (1 bit per chunk), not a pair encoder, so there is no existing
codec to reuse — this is a new encoding. A compact float-pair blob or a JSON array
are both fine at podcast scale; pick JSON if debuggability matters more than size.

Keep this table out of broad list and On Deck observations. Playback may read the
row directly on load, but normal episode lists should not track it.

Invalidate an analysis row when any of these changes:

- `algorithmVersion`
- episode duration differs meaningfully from stored duration
- media URL changes (this also changes the deterministic cached filename, so it
  subsumes the old "cached filename changed" trigger)

Cache eviction (`cachedFilename → nil`) does not invalidate the analysis — the
ranges stay valid for the same media; eviction only gates *when* re-analysis can
run.

## Playback integration considerations

Do not implement this section until the playback mechanism is chosen. These are
the integration constraints each option must satisfy.

Common requirements:

- Resolve and store the current auto-skip enabled value on episode load.
- Fetch the current episode's silence map if complete.
- Trigger analysis opportunistically when the map is missing or stale.
- Keep the immediate playbar toggle session-scoped.
- Decide whether app-visible time remains original episode time. The default
  assumption should be yes: chapters, transcripts, saved progress,
  `PlaybackCoverage`, Now Playing, and remote scrubs all use original episode
  coordinates today.

### If `AVPlayer` seek wins

The skip decision belongs near the 250 ms `currentTimeStream` consumer, not the
3 s DB tick. Keep ranges sorted and hold a cursor to the next upcoming range; a
"range containing now" scan fires after entering silence and can play up to a
tick of dead air first.

Route automatic jumps through the existing seek path
(`PlayManager.seek -> PodAVPlayer.seek`) so Now Playing and position persistence
stay consistent. The seek path saves position only, not heard playback, so the
skipped interval should not be OR-marked into `PlaybackCoverage`.

This path needs loop guards:

- Do not re-skip the same range until playback moves outside it or the user seeks
  manually.
- Enforce a minimum interval between auto-skips so adjacent ranges do not thrash.
- Consider adding tolerance-controlled seek methods to `AVPlayable` and
  `FakeAVPlayer` if the seek-accuracy spike says they help.

### If `AVMutableComposition` wins

`PodAVPlayer` should own the mapping because it is the boundary around
`AVPlayer`. The rest of the app should continue speaking original episode time.

```swift
struct SilenceRange: Sendable, Equatable {
  let start: CMTime
  let end: CMTime
}

struct SilenceMap: Sendable, Equatable {
  let episodeID: Episode.ID
  let ranges: [SilenceRange]
}

struct PlaybackTimelineSegment: Sendable, Equatable {
  let source: CMTimeRange
  let composition: CMTimeRange
}

struct PlaybackTimeline: Sendable, Equatable {
  let episodeID: Episode.ID
  let segments: [PlaybackTimelineSegment]
}
```

When auto-skip is enabled and a complete map exists, derive audible source ranges
by subtracting silence from `0..<duration`, create an `AVMutableComposition`,
insert each audible source range contiguously, and record a segment for each
inserted range. Copy to `AVComposition` and create `AVPlayerItem(asset:)`.

Convert at every boundary:

- `currentTime()` returns source time.
- `currentTimeStream` yields source time.
- `seek(to:)` accepts source time and maps to composition time internally.
- Remote scrubs and progress-bar scrubs keep using source time.
- `NowPlayingInfo` keeps source elapsed/duration unless the product explicitly
  chooses compacted-duration UI.

Coverage needs special handling. Today `repo.updatePlayback` marks one
contiguous range from `playedFrom` to `currentTime`. Under a compacted
composition, a single transport tick can map across a removed silent gap in
source time. Marking the whole source span would falsely record skipped silence
as heard. This path needs either a repo writer that accepts multiple heard source
ranges for one tick or a timeline helper that decomposes each compact tick into
audible source subranges before persistence.

Toggling auto-skip on/off mid-episode means swapping the current item while
preserving source current time, play/pause state, and rate. Expect a small
user-initiated interruption unless a spike proves the swap is seamless.

### If `AVAudioEngine` wins

Treat this as a playback transport replacement, not a local change. The new
engine layer must provide the same outputs `PlayManager` relies on today:
current-time stream, rate stream, control-status stream, did-play-to-end signal,
seek, pause, play, recovery after interruptions, and enough state for Now Playing
and command-center handlers.

It also needs a clear time policy. If the engine performs continuous compression,
there may be no fixed precomputed source-to-output map. In that case position
mapping is dynamic and must be treated as first-class product behavior, not an
implementation detail.

### If `MTAudioProcessingTap` wins any role

Use the tap only as an analysis or metering input unless a separate mechanism is
chosen for actually shortening playback. Do not do persistence or actor-isolated
transport changes directly inside tap callbacks.

## Risks / spikes before committing

Prototype these before implementation. They should produce the architecture
decision, not merely validate a decision already made.

1. **Product behavior.** Decide whether the user-visible goal is discrete removal
   of sufficiently long silent segments or continuous pause compression. This
   determines whether the `AVPlayer`-based options are enough.
2. **Seek-over-silence smoothness.** Hardcode ranges and seek over them on real
   episodes. Listen for clicks, stutters, Bluetooth behavior, and VBR landing
   accuracy. Also measure whether tolerance-controlled seeks help.
3. **Composition viability.** Build a composition from real long podcast files
   with many ranges. Measure item creation time, segment-count limits or slowdowns,
   playback smoothness, rate behavior, and item-swap behavior when toggling
   auto-skip during playback.
4. **Timeline mapping complexity.** Prototype source-time persistence and
   `PlaybackCoverage` updates for a compacted timeline. If this feels fragile,
   composition may not be worth its smoother playback.
5. **AVAudioEngine feasibility.** Only spike if continuous compression remains a
   serious candidate. Verify background audio, remote commands, interruptions,
   rate/pitch behavior, and source-time mapping before committing to the rewrite.
6. **Tap usefulness.** If considering `MTAudioProcessingTap`, prove what it adds
   over `AVAssetReader` analysis and how it would pair with an actual removal
   mechanism.
7. **Analyzer cost on a long episode.** Full-file PCM decode of a 2-hour episode
   is the real CPU bound. Benchmark one before assuming the foreground drain is
   cheap enough to run on cache completion.

## Observability

Log at debug level when:

- analysis starts, completes, is cancelled, or fails
- an analysis row is considered stale
- playback skips/removes a range, if the chosen mechanism has an observable event

Playback logs should include episode ID, source current time, range start/end,
target time or compact segment, and whether the map came from cache or was newly
analyzed. Do not log per-window RMS values outside temporary local debugging.

## Testing

### Unit tests

- `SilenceAnalyzer` detects one silent range in synthetic PCM.
- It ignores quiet ranges shorter than the minimum duration.
- It merges ranges separated by tiny non-silent gaps.
- It preserves non-silent low-level content above threshold.
- Encoding/decoding `SilenceMap` round-trips.
- Analyzer version changes mark rows stale.

### Migration/repo tests

- New podcast override column defaults to `NULL`.
- `PodcastSettings` persists `nil`, `true`, and `false`.
- `episodeSilenceAnalysis` cascades on episode delete.
- Stale analysis is not returned for changed duration/version.

### Playback tests

Common tests:

- Missing analysis does not block playback.
- Loading a new episode resolves the setting from podcast override before the
  global default.
- Disabled current-session toggle disables the chosen skip/compression behavior.
- Playbar toggle changes only session state.

If `AVPlayer` seek wins:

- `FakeAVPlayer` drives ticks (`advanceTime`/`currentTimeValue` synchronously fire
  the periodic observers) and seeks (`seekHandler`).
- A tick approaching a silent range seeks to range end plus pad.
- User seeking into a silent range skips once, not in a loop.
- Auto-skip seek does not mark `PlaybackCoverage` for the skipped interval.
- A minimum interval between skips is enforced.

If `AVMutableComposition` wins:

- Composition builder inserts only audible ranges in order.
- Source-to-composition and composition-to-source mappings round-trip at segment
  starts, middles, and ends.
- `PodAVPlayer.currentTimeStream` yields source time while the underlying player
  advances in composition time.
- Seeking accepts source time and lands on the mapped composition time.
- Coverage persistence marks only audible source ranges when a compact tick spans
  a removed silent range.
- Toggling on/off swaps items while preserving source position, rate, and
  play/pause state.

If `AVAudioEngine` wins:

- Engine-backed player emits the same semantic streams `PlayManager` expects.
- Source-time mapping works during rate changes, seeks, interruptions, and end of
  episode.

If `MTAudioProcessingTap` has a role:

- Tap analysis never performs persistence or actor-isolated transport changes from
  the tap callback.

### UI tests / view-model tests

- Settings toggle writes the global persisted default.
- Podcast settings can choose Default/On/Off and clear back to default.
- Playbar toggle updates current-session state without mutating global or
  podcast settings.

## Rejected or deferred variants

These are not the main playback options, but they may come up during design:

- **Speech/VAD-based detection.** Wrong product behavior. The feature should skip
  silence, not every non-speech region.
- **Remote full-file analysis before playback.** Adds network cost and latency.
  Keep analysis local and opportunistic unless a later streaming-specific design
  requires something else.
- **Destructively editing cached audio.** Rewriting the cached file to remove
  silence breaks source time coordinates for chapters, transcripts, Now Playing,
  and saved progress, and corrupts the cache for reuse. Composition reaches a
  similar gapless result non-destructively if that option wins.

## Open questions

- Should a short audible cue or subtle haptic indicate that a skip happened?
  Probably no initially; it should feel invisible.
- Surface skipped seconds as a session statistic. Pull a debug-only counter into
  early spikes regardless — during mechanism comparison and threshold tuning it is the
  cheapest proof the feature is doing anything.
- What threshold feels best across studio podcasts, phone interviews, and noisy
  field recordings? Start conservative and tune from real files (see the absolute
  vs adaptive note under Analyzer).
- How should auto-skip interact with existing playback features? Decide whether an
  automatic removal/skip should populate `enableUndoSeek` (likely not), how it
  behaves across chapter boundaries, and whether it should defer near a
  sleep-timer boundary.
- If the transcripts initiative lands with word-level timings, those are a much
  cheaper silence/gap signal than PCM decode for transcribed episodes (this is not
  VAD — it reuses timestamps already computed). Worth revisiting the analyzer
  source then.
- Should per-podcast override live in the same Playback section as rate or a
  separate "Listening" section if more controls arrive?

## References

- Apple `AVAssetReader`: https://developer.apple.com/documentation/avfoundation/avassetreader
- Apple `AVAssetReaderTrackOutput`: https://developer.apple.com/documentation/avfoundation/avassetreadertrackoutput
- Apple `AVPlayer` precise seek:
  https://developer.apple.com/documentation/avfoundation/avplayer/seek(to:tolerancebefore:toleranceafter:completionhandler:)
- Apple `MTAudioProcessingTap`: https://developer.apple.com/documentation/mediatoolbox/mtaudioprocessingtap
- Apple `AVAudioMixInputParameters.audioTapProcessor`:
  https://developer.apple.com/documentation/avfoundation/avaudiomixinputparameters/audiotapprocessor
- Apple `AVAudioEngine`: https://developer.apple.com/documentation/avfaudio/avaudioengine
- Apple `AVMutableComposition`: https://developer.apple.com/documentation/avfoundation/avmutablecomposition
- Apple `AVMutableCompositionTrack.insertTimeRange(_:of:at:)`:
  https://developer.apple.com/documentation/avfoundation/avmutablecompositiontrack/inserttimerange(_:of:at:)
- FFmpeg silence filters: https://ffmpeg.org/ffmpeg-filters.html#silencedetect
