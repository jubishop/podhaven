---
status: current
---

# Auto-Skip Silence

Agreed design and AVPlayer prototype, September 10, 2026.
Implementation is tracked in [issue #656](https://github.com/jubishop/podhaven/issues/656).
This plan replaces the earlier unapproved comparison of playback approaches.

## What

Implement automatic silence shortening for downloaded podcast audio using the existing **AVPlayer / PodAVPlayer transport with precise seeks**. Deliver a usable feature with global settings, nullable podcast overrides, and a temporary control for the current playback.

This is the agreed implementation scope from the design discussion. It is not a research-only issue. Complete the AVPlayer implementation and its validation, then close this issue. The user's later listening and approval are not a closure gate. Later listening may justify separate issues for audible jumps, rough transitions, preset tuning, or a broader playback-engine redesign. Keep that expectation in the repository design documentation. **AVAudioEngine is a possible later approach, not the transport selected for this issue.**

## Why

Shorten clear pauses while preserving natural speech cadence and the selected speech speed. Listeners who choose higher playback speeds should also get somewhat more aggressive pause shortening. Avoid requiring manual timing adjustments or repeated audio analysis whenever speed changes.

## How

### Modes and speed scaling

- Offer **Gentle, Balanced, Aggressive, and Off**. There is no Custom mode, minimum-gap slider, retained-pause slider, or user-facing sound-level threshold.
- The global mode initially defaults to **Off**. Podcast overrides initially remain unset.
- The enabled presets define internal 1× values for minimum qualifying quiet duration and total quiet duration retained around the cut. Gentle preserves more space; Aggressive removes more; Balanced sits between them.
- Start with a gentle scaling curve: divide both baseline source-audio timing values by `sqrt(selectedPlaybackRate)`. Playback itself then applies the selected rate. This is a prototype starting rule, with final preset values, bounds, and protection margins tuned through listening.
- For example only, a 1× minimum of 0.8 seconds and retained pause of 0.3 seconds would become approximately 0.57 and 0.21 seconds of source audio at 2×; the retained pause would be heard for about 0.11 seconds. Do not accidentally count the rate adjustment twice when calculating or describing heard duration.
- Use the current selected speed, including mid-playback changes. A paused player's transport rate of zero is not the selected listening speed.
- Keep sound-level detection independent of preset and speed. Speed changes must not make quiet speech more likely to be classified as silence.
- Recalculate future skip boundaries from reusable analysis when the mode or speed changes. Do not decode the file again merely for those changes. Preserve safe minimum margins, positive useful skip lengths, and monotonic preset ordering throughout the supported rate range.

### Settings, precedence, and lifetime

Resolve the effective mode in this order:

1. An explicit temporary override for the current playback.
2. An explicit podcast override.
3. The global setting.

| Surface | Behavior |
| --- | --- |
| `SettingsView`, Playback section | Persist the global mode. |
| `PodcastSettingsView`, Playback section | Follow the existing nullable override pattern used by playback speed. Unset uses the global mode; an explicit mode, including Off, overrides it. Clearing the override restores inheritance. Show the effective inherited choice. |
| Expanded playback sheet | Change only this episode's current playback. Do not write to podcast settings, global settings, or a persisted per-episode preference. |

The current playback follows applicable podcast/global changes until the user selects a mode in the player. That selection creates the temporary override, which then wins over later default changes. Preserve it through pause/resume, seeking, playback-speed changes, remote-to-cache item swaps, interruptions, route recovery, and media-services recovery of the same playback. Clear it when that playback ends or another episode is selected. A new playback, including after an app relaunch, starts from the effective podcast/global setting. Do not confuse rebuilding a player item for recovery with starting a new playback session.

Turning Off prevents further automatic skips immediately. Other effective changes update future skip decisions during current playback when eligible audio is ready. While waiting for downloaded/analyzed audio, retain the latest selection and apply it when the actual playback source becomes eligible.

### Interface contract

- Add a **separate compact silence control immediately to the right of the existing playback-speed control** in `PlayBarSheet.metaControlsRow`. Both belong in the left group before the spacer; keep the existing controls on the right.
- The player control opens a popover/menu with only **Gentle, Balanced, Aggressive, Off**, with the current effective selection indicated. No reset action, explanatory text, timing controls, or new playback-options panel. Do not combine it with the speed popover.
- Put detailed explanations only in the existing question-mark help popovers (`SettingsRow`) in `SettingsView` and `PodcastSettingsView`. Explain natural pause shortening, relative preset strength, automatic speed scaling, inheritance, and the downloaded/analyzed-audio requirement. Explain the current-playback scope of the player control there if needed.
- Use `AppIcon` and accessible native menu/picker semantics. Give the compact control an accurate VoiceOver label and selected value. Preserve Dynamic Type, reading order, adequate hit targets, and usable narrow layouts with chapter controls and the transcript visible.
- Add isolated `#Preview` states for inherited and explicit settings, enabled/Off selections, and the expanded player layout. No network or persistent database access in previews.

### Analyze downloaded audio once

- Analyze **every downloaded episode whose effective silence setting is enabled**, including downloaded episodes outside the queue. Queue membership affects priority, not eligibility.
- Prioritize the current episode, then queue order, then other eligible downloads. A temporary enabled override makes the current episode eligible even if its podcast/global default is Off.
- Use one analysis worker at a time. Integrate with existing foreground/background scheduling and thermal-pressure handling. Keep work cancellable, bounded in memory, and outside the UI and audio-render paths. Do not start a second media download for analysis.
- Reconcile eligibility after downloads finish, settings change, the current playback or queue changes, and on launch. Do not re-query the whole library on every playback-position update. Deferral or background-task expiration must not stop ordinary playback.
- Decode the local audio with `AVAssetReader` and `AVAssetReaderTrackOutput` to PCM. Separate sample reading, quiet-interval detection, preset/rate policy, and playback orchestration so each can be tested at the correct boundary.
- Use conservative audio-level detection, initially evaluated over short windows. Calibrate the detector and boundary protection on actual podcasts. Preserve quiet speech, breaths, music, and other audible material; this is not speech-only filtering, ad removal, or transcript-gap skipping.
- Evaluate channel energy without cancellation from downmixing opposite-phase stereo. An audible signal in either channel must protect that interval. Preserve brief audible sounds between quiet intervals instead of merging across them blindly.
- Missing samples, invalid values, timestamp discontinuities, and decode failures are not evidence of silence. Fail back to normal playback.
- Store the detected quiet intervals before applying any preset's minimum-gap filter or cut padding. Retain enough resolution and sufficiently short candidates for the most aggressive supported preset/rate combination. Store source timestamps and detector version. Do not cache only one preset's final skip ranges.
- Publish a complete validated map atomically. Partial or failed analysis must never appear as complete. Cancellation and failures must not cause unbounded retries or block other eligible episodes.

### Persistence and source identity

- Use a typed mode with a persisted global value and a nullable podcast value. Extend `UserSettings`, `PodcastSettings`, `UnsavedPodcast` in `Podcast.swift`, the repository writer, and necessary `OnDeck` projections/observations. The current-playback override remains transient.
- Add the next migration; do not edit shipped migrations. Use literal stored values in migration checks and test the migration with raw SQL.
- Keep analysis in a separate bounded cache/table, outside hot episode-list and On Deck projections. Do not retain full decoded audio in memory or store separate maps for each speed/preset.
- Bind a map to the **actual installed local media content**, its duration/format as needed, and detector version. Episode ID, URL, deterministic cached filename, or matching duration alone cannot prove identical audio. A repaired or re-downloaded file can have different content at the same path. Use an explicit file-generation/content-identity contract integrated with `CacheFileStore`; the existing `AudioFileHasher` is available if content hashing is needed.
- Validate identity before publishing analysis and before attaching it to playback. Account for multiple episodes referencing one cached file and for replacement/eviction during analysis.
- Invalidate stale maps when the underlying file or detector changes. Preset/rate changes reuse a valid map. Keep valid analysis while its local file remains cached, including while the preference is Off, so re-enabling is cheap. Remove orphaned analysis when the corresponding cached content is evicted or deleted; avoid indefinite accumulation.

### AVPlayer playback integration

- Keep original episode audio and **original source time everywhere**: duration, progress, scrubbing, chapter navigation, transcript timestamps, Now Playing, and persisted positions. Silence skipping advances the position; it does not shorten the displayed duration or rewrite the cached audio.
- Playback starts normally when analysis is missing, pending, failed, stale, or unavailable. Skips require a valid map for the **exact local file currently bound to the player**. A cached file merely existing is insufficient; never use its map against a remote stream.
- Coordinate download/analysis readiness with the existing remote-to-cache item replacement. When the feature is enabled and the local source is ready, activate it without requiring the user to scrub or restart the episode. Preserve source position, selected rate, play/pause state, and the temporary override. If the local source fails, normal remote playback may continue with skipping inactive.
- Extend the existing `AVPlayable` OS boundary and its real `AVPlayer` conformance for tolerance-controlled seeking, and boundary observation if used. Use sample-accurate seek requests (`toleranceBefore` and `toleranceAfter` zero) for automatic cuts initially; measure actual behavior with supported media.
- Schedule from media time. Boundary observers can help, with the existing time stream as reconciliation; they are not guaranteed to report every boundary. Always validate the actual current source time and current item/generation before deciding. Do not add a polling loop or rely solely on the three-second database checkpoint.
- Cut only inside a detected quiet interval. Retain protection on both sides and land **before the end of the quiet interval**, not after speech resumes. Recheck that a late callback still has a useful forward cut available. If it does not, let the audio play normally.
- Prevent repeated skipping of the same interval during one traversal. Recalculate future boundaries safely on preset/rate changes. Avoid adjacent-seek thrashing and cuts whose benefit is smaller than measured seek overhead.
- Give manual transport actions precedence over pending automatic seeks. Never auto-seek while paused, buffering, loading, or replacing/recovering an item. Cancel obsolete work on disable, item changes, or source replacement. Late completions must not alter another episode, resume playback against user intent, or restore obsolete observers.
- Restore appropriate observation after interrupted/failed automatic seeks. Do not write an intended target as a successful position after a failed seek; reconcile with the actual player position.
- After a manual seek into a quiet interval completes, **immediately shorten the remaining silence** if a safe, useful forward cut remains. Do not exempt that interval merely because the user sought into it. If paused, wait for playback to resume. A user seek supersedes an older automatic seek; reevaluate from its confirmed landing position and prevent repeated skips of the same interval during that traversal.
- Automatic skips do not create or replace an Undo Seek candidate and do not emit sounds, haptics, or repeated user notifications. Preserve chapter navigation, lock-screen/widget controls, queue advancement, and Stop After Current Episode behavior.
- Persist actual source position while keeping removed intervals out of heard `PlaybackCoverage`. Flush genuinely heard progress before a cut and reset the coverage baseline after it; do not either mark the skipped interval as heard or lose the audible portion since the last checkpoint. Account for the existing coverage bitmap's resolution rather than promising sample-level precision.

### Implementation and validation order

1. Establish the mode/inheritance and pure preset/rate policy with failing regression tests, then implement them.
2. Exercise precise seeks over known ranges in cached MP3/AAC samples to understand landing accuracy and overhead. Use those findings for conservative cut margins and initial preset values. This is an early implementation step, not a separate research-only deliverable.
3. Implement and test local PCM analysis, source-bound cache persistence, and the scheduler.
4. Integrate current-playback state, live settings/speed updates, readiness/cache switching, seeks, position/coverage accounting, and lifecycle cleanup.
5. Add the settings and separate expanded-player control, help popovers, accessibility, and previews.
6. Complete regression/build checks and document initial listening and performance evidence, the shipped preset/detector values, known limitations, and the follow-up path. Finish the usable AVPlayer implementation under this issue. Later sound-quality iterations or engine redesign belong in new issues when warranted by testing.

Useful current code locations: `PodHaven/Environment/UserSettings.swift`; `PodHaven/Database/Models/{PodcastSettings,Podcast,OnDeck}.swift`; `PodHaven/Database/Repo.swift`; `PodHaven/State/SharedState.swift`; `PodHaven/Play/PlayManager.swift` and its playback/events/recovery files; `PodHaven/Play/Utility/PodAVPlayer.swift`; `PodHaven/Play/Protocols/AVPlayable.swift`; `PodHaven/Play/Extensions/AVPlayer.swift`; `PodHaven/Cache/{CacheManager,CacheFileStore}.swift`; `PodHaven/Recommendations/Embeddings/EmbeddingProcessor.swift`; `PodHaven/Utility/BackgroundTaskScheduler.swift`; `PodHaven/Views/Settings/{SettingsView,Components/SettingsRow}.swift`; `PodHaven/Views/Podcasts/PodcastSettingsView.swift`; `PodHaven/Views/PlayBar/{PlayBarSheet,Models/PlayBarViewModel}.swift`.

### Regression coverage

- All precedence combinations, explicit Off versus unset, clearing a podcast override, inherited live changes, temporary player overrides, and new-session reset versus same-session recovery. Changing the player mode must not write a persistent setting. Detect user selections explicitly rather than mistaking inherited updates for manual overrides.
- Scaling at slower/normal/faster rates, preset ordering, padding floors, short/unprofitable gaps, Off behavior, and selected rate retained while paused. Mode/rate changes must not restart decoding or grow stored maps.
- Synthetic mono/stereo PCM, opposite-phase channels, silence at boundaries, brief sounds inside gaps, quiet speech/music fixtures, short gaps, different sample rates, long files, no silence, all silence, discontinuities, cancellation, and decode failure.
- Raw-SQL migrations; analysis round trips; stale version/file identity; same URL/path/duration with replaced bytes; shared cache references; eviction/deletion and out-of-order analysis completion; valid analysis reuse after disabling/re-enabling.
- All eligible downloads, including non-queued ones; current/queue priority; no work for ineligible audio; only one worker; eligibility changes; background expiration/thermal deferral; no library scan per playback tick; bounded failures and cleanup.
- Remote playback with an available local map still never auto-skips until switched to that local asset. Readiness and item replacement preserve current position/rate/play state and temporary settings without user seeking. Stale/failed analysis leaves playback usable.
- Known quiet ranges produce correct precise-seek targets; late/missed boundaries do not cut speech; no loops; manual seeking into silence triggers a safe remaining-silence cut after completion (or after resuming from pause); actual seek completion/failure/interruption; competing manual actions; paused/buffering states; item/episode changes; route changes and media-services reset; queue/end-of-episode/Stop After Current Episode behavior.
- Source timestamps remain consistent in UI, database, transcripts/chapters, and Now Playing. Heard coverage includes audio before/after cuts and excludes removed spans as far as the existing bitmap can represent. Automatic cuts do not interfere with Undo Seek.
- Menu choices and placement; no player explanations/reset/Custom controls; correct persistence scope; accessible selection/reading order; narrow and large-text layouts with chapters/transcript; isolated previews compile.

Use the repository's Swift Testing fixtures and real orchestration with fakes at OS boundaries. Prove functional regression tests fail before each implementation change and pass afterward. Do not expose private logic or add production APIs solely for tests. Run suite-level filters using My Mac (Designed for iPhone), always pass `-hideShellScriptEnvironment`, format touched Swift, and finish with zero warnings. Follow `AGENTS.md` for required application checks and run document checks for the design updates.

Initial listening/performance evidence should cover representative studio, quiet/noisy interview, and music-bearing episodes; mono/stereo MP3 and AAC, including variable-bitrate and long recordings; the supported speed range and mid-playback changes; and available speaker/headphone/Bluetooth/background flows. Record analysis time, peak memory, map size, and seek artifacts/overhead on a real device where possible. Clearly identify hardware checks that were not performed. Do not claim perfect audio quality or substitute a passing fake-player test for listening evidence.

## Prototype constants and evidence

The implementation keeps one detector map per installed cache-file generation.
`CacheFileStore` creates a new generation when it installs replacement bytes,
retains the generation when another episode reuses that file, and removes the
map when the last reference or invalid file is removed. Startup also removes
orphaned metadata. Analysis publication and player attachment check the same
generation. A remote item cannot use the map of a local file.

The detector uses the peak absolute sample value across all channels in each
10 ms window. A window qualifies below 0.001 full scale (−60 dBFS). It keeps
quiet candidates of at least 40 ms before preset filtering. An audible window
splits candidates; missing timestamps do not join them. Invalid samples reject
analysis. The decoder reads interleaved float PCM without downmixing and bounds
one sample buffer to 1 MiB. A map is limited to 100,000 intervals and 8 MB of
encoded data. Failed analysis is attempted at most twice per file generation
and detector version, on separate eligibility triggers. Cancellation does not
publish a partial map or record a permanent failure.

| Preset | Minimum source gap at 1× | Total source pause retained at 1× |
| --- | --- | --- |
| Gentle | 1.2 s | 0.60 s |
| Balanced | 0.9 s | 0.40 s |
| Aggressive | 0.65 s | 0.28 s |

Both values scale by `1 / sqrt(selectedRate)` over the UI's 0.8–2× range.
Each end retains at least 100 ms of source audio. A cut must remove at least
150 ms of heard time after this protection. Automatic seek targets and boundary
observations use a 600,000-unit timescale, with zero seek tolerances. The general
60-unit time helper remains unchanged for existing callers. These are initial,
conservative values, not a claim that all pauses should be shortened.

### Local decoder and transport measurements

Measurements used the optimized production detector on three existing local
podcast downloads. The files and the application's persistent database were
read without modification. The run used a Mac; these are not iPhone battery or
thermal measurements.

| Recording | Source duration | Analysis time | Map size | Quiet candidates |
| --- | --- | --- | --- | --- |
| Talking Elite Fitness, “Crossing Over...Again, and a Conversation with Arielle Loewen” | 66.5 min | 5.40 s | 64,779 bytes | 1,752 |
| My First Million, “How I Bought a $3.4M Business For $200K” | 81.0 min | 5.75 s | 54,636 bytes | 1,475 |
| My First Million, Robert Greene interview | 84.3 min | 6.92 s | 92,769 bytes | 2,515 |

The combined process reached 24.3 MB maximum resident memory. At 1×, Balanced
would use 13, 3, and 20 of those candidates respectively. The remaining short
candidates are retained for other presets and speeds, rather than decoded again.

After waiting for `AVPlayerItem.Status.readyToPlay`, 81 zero-tolerance seek
requests inside detected quiet ranges completed at 0.8×, 1×, and 2×. Median
completion delay was 58 ms; the maximum was 108 ms. Reported player position
was within 21 microseconds of the requested target. A separate 36-request run
on synthetic mono VBR MP3 and opposite-phase stereo AAC completed with a maximum
115 ms delay. Reported time accuracy does not prove the absence of an audible
transition or measure the audio hardware's output latency.

The checked-in synthetic fixtures alternate a tone and silence. They cover
MP3/AAC decoding, channel cancellation, source timestamps, and window protection.
They contain generated audio, not excerpts from the podcast downloads.

### Cache-switch failure behavior

The player restores its confirmed source position when switching from streaming
to downloaded audio. Turning Off or pausing during this operation preserves
position restoration and the latest playback intent. A manual seek or a new
episode supersedes the operation.

If positioning the downloaded item fails, the player restores the original
streaming item at the confirmed position. Silence shortening stays inactive,
and automatic retries for that installed file generation are suppressed for
the current playback. If streaming restoration also fails, playback stays
paused and the existing error alert explains the failure.

Foreground decoding starts only after the app's explicit foreground signal.
A background-only launch waits for an operating-system background-task grant.

### Verification limits and later work

This validation measured decoding, memory, and seek completion. It did not
perform auditory listening or a physical iPhone, speaker, headphone, Bluetooth,
or background audio-route session. The three downloaded recordings do not form
an annotated quiet-speech or music corpus. Peak protection and conservative
padding reduce risk, but do not establish perfect sound quality.

Automated tests exercise mode inheritance, transient selection, cache identity,
real decoding, thermal deferral, remote-to-cache readiness, manual and failed
seeks, coverage accounting, and media-services recovery. Hosted accessibility
inspection checks the separate control's label, selected value, placement, and
hit target at narrow widths and large text sizes. The narrow-layout check includes chapter controls and an expanded transcript.
The final My Mac run passed 2,156 tests across 292 suites, including the existing
chapter, transcript, queue, and recovery coverage. Swift formatting, preview
compilation, and document checks passed; the final build emitted no compiler
warnings. The My Mac harness still prints macOS accessibility-bundle loading
errors for RealityFoundation and ScreenTimeUI before the tests; hosted
accessibility assertions passed.

Later listening can identify audible jumps, soft-speech clipping, or preset
changes. Such findings should be evaluated as focused follow-up work. The
user's later listening and approval do not create an indefinite closure gate
for the AVPlayer implementation, and AVAudioEngine remains a possible later
transport redesign.

## Done when

- [ ] A usable AVPlayer precise-seek implementation automatically shortens detected silence for eligible downloaded audio.
- [ ] The four modes, global default, nullable podcast override, and temporary current-playback override behave exactly as specified, including live inheritance until the player selection is modified.
- [ ] The separate compact control sits immediately right of playback speed, contains only the four choices, and persists no podcast/global/episode preference.
- [ ] Presets scale gently with current playback speed without repeated audio analysis; initial values and protection limits are documented.
- [ ] Every eligible downloaded episode can be prepared, including episodes outside the queue, with bounded scheduling, persistence, cancellation, and cache cleanup.
- [ ] Original timelines, playback coverage, manual controls, normal streaming fallback, cache switching, background/remote playback, and recovery remain correct.
- [ ] Required regression tests, builds, formatting, accessibility checks, previews, and documentation checks pass; listening/performance evidence and its limits are recorded.
- [ ] The design document records that this issue closes after this AVPlayer implementation and validation. Potential later sound-quality or engine changes are explicitly follow-up work, not an indefinite closure condition.

## API references

- [AVAssetReader](https://developer.apple.com/documentation/avfoundation/avassetreader) and [AVAssetReaderTrackOutput](https://developer.apple.com/documentation/avfoundation/avassetreadertrackoutput).
- [AVPlayer precise seeking](https://developer.apple.com/documentation/avfoundation/avplayer/seek(to:tolerancebefore:toleranceafter:completionhandler:)): exact tolerances can add decoding delay; prior seek completions can be interrupted.
- [AVPlayer boundary time observation](https://developer.apple.com/documentation/avfoundation/avplayer/addboundarytimeobserver(forTimes:queue:using:)): callbacks are not guaranteed for every boundary and must recheck current time; retain/remove observer tokens correctly.
