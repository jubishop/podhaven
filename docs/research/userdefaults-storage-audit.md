---
status: shipped
---

# UserDefaults Storage Audit

## Conclusion

PodHaven's remaining defaults use is appropriate and small. A representative
development install used a 2,507-byte standard-domain binary plist and a
134-byte app-group plist. The standard domain was 3,961 bytes when expanded to
XML. Other installed build profiles measured 256–1,242 bytes in the standard
domain and 42–76 bytes in the app-group domain.

The transcription queue was the exception. It was an ordered, relational work
queue stored as one JSON array and rewritten after every enqueue or removal.
The former value is now imported into an ordered GRDB table by migration v71
and removed from defaults by migration v72. All ongoing defaults access now
uses `@PersistedBroadcast` or `@PersistedThreadSafe`; direct store access is
limited to persistence infrastructure and immutable or forward migrations.

[Apple describes `UserDefaults`](https://developer.apple.com/documentation/foundation/userdefaults)
as a persistent settings store whose in-memory representation changes
immediately and whose disk persistence is asynchronous. That makes the
remaining tiny, low-cadence values suitable, but does not make a growing work
queue suitable.

## Method

The inventory combines:

- static searches for all defaults factories, wrappers, `DefaultsStorable`
  calls, direct `UserDefaults` calls, and migration access;
- serialized `Data.count` measurements for current and representative values;
- binary-plist and XML-plist sizes from installed development profiles;
- code-path tracing of every writer during settings changes, episode
  transitions, recommendation refreshes, embedding scheduling, and widget
  playback transitions; and
- a full-library stress bound from a local database containing 103,751 episode
  IDs.

Sizes below describe the JSON `Data` payload unless stated otherwise. JSON
numbers can theoretically take up to about 24 bytes; bounded UI choices are
usually 1–4 bytes. "App-update" lifetime includes process restart. Losing a
preference is functionally safe because the code has a default, but is not
acceptable user experience; restoring its prior value is intentional, not
stale-state risk.

## Standard-domain inventory

### User settings

Every row is owned by `UserSettings`, written by Settings UI unless noted, and
kept through `@PersistedBroadcast` because multiple live readers observe
changes. Writes occur only when the user changes the setting; sliders may
produce a short burst during one interaction. Equal assignments are
deduplicated by `Broadcast`.

| Key | Primary readers / purpose | Type and serialized size | Lifetime and stale/loss behavior | Decision |
| --- | --- | --- | --- | --- |
| `shrinkPlayBarOnScroll` | `ContentView`; tab/play-bar layout | `Bool`, 4–5 B | App-update preference; safe default on loss, prior value desired | Keep |
| `cacheSizeLimitGB` | `CachePurger`; cache budget | `Double`, usually 1–4 B, ≤24 B | App-update preference; loss changes eviction policy, staleness desired | Keep |
| `defaultPlaybackRate` | playback and podcast settings; global rate | `Double`, usually 3 B, ≤24 B | App-update preference; safe default on loss, staleness desired | Keep |
| `skipForwardInterval` | playback, Command Center, widget snapshot writer | `Double`, UI values 1–2 B | App-update preference; safe default on loss, staleness desired | Keep |
| `skipBackwardInterval` | playback, Command Center, widget snapshot writer | `Double`, UI values 1–2 B | App-update preference; safe default on loss, staleness desired | Keep |
| `enableUndoSeek` | `PlayBarViewModel`; seek undo | `Bool`, 4–5 B | App-update preference; safe default on loss, staleness desired | Keep |
| `commandCenterScrubbingEnabled` | `CommandCenter`; remote scrubbing | `Bool`, 4–5 B | App-update preference; safe default on loss, staleness desired | Keep |
| `maxQueueLength` | queue insertion/enforcement | `Int`, 1–3 B with the UI/migration cap | App-update preference; safe bounded default on loss, staleness desired | Keep |
| `maxRecommendedEpisodesInUpNext` | `UpNextViewModel`; visible recommendation limit | `Int`, normally 1–2 B | App-update preference; safe default on loss, staleness desired | Keep |
| `showNowPlayingInUpNext` | `UpNextView`; presentation | `Bool`, 4–5 B | App-update preference; safe default on loss, staleness desired | Keep |
| `alwaysShowPodcastImageInUpNext` | Up Next and widget snapshot presentation | `Bool`, 4–5 B | App-update preference; safe default on loss, staleness desired | Keep |
| `alwaysShowPodcastImageForUpNextRecommendations` | Up Next recommendation presentation | `Bool`, 4–5 B | App-update preference; safe default on loss, staleness desired | Keep |
| `alwaysShowPodcastImageForOnDeck` | playback and on-deck presentation | `Bool`, 4–5 B | App-update preference; safe default on loss, staleness desired | Keep |
| `showTimeRemainingInEpisodeLists` | episode-list duration presentation | `Bool`, 4–5 B | App-update preference; safe default on loss, staleness desired | Keep |
| `autoPlayTopRecommendationWhenQueueEmpty` | `PlayManager`; queue-empty behavior | `Bool`, 4–5 B | App-update preference; safe default on loss, staleness desired | Keep |
| `enableWriteProbe` | debug Settings and `WriteProbe`; diagnostics | `Bool`, 4–5 B | App-update debug preference; loss is acceptable | Keep |
| `appearanceMode` | app color scheme | raw-value enum, 6–8 B | App-update preference; system default is safe, staleness desired | Keep; v72 normalizes legacy native strings |
| `nextTrackBehavior` | playback, Command Center, Now Playing | raw-value enum, 14–15 B | App-update preference; safe default on loss, staleness desired | Keep; v72 normalizes legacy native strings |
| `commandCenterLikeAction` | Command Center feedback action | enum, about 11–64 B including an optional 64-bit tag ID | App-update preference; a deleted tag safely becomes no action | Keep |
| `commandCenterDislikeAction` | Command Center feedback action | enum, about 14–64 B including an optional 64-bit tag ID | App-update preference; a deleted tag safely becomes no action | Keep |
| `episodeSwipeActions` | episode-list swipe configuration | enum array, 21 B default and 80 B with every action | App-update preference; unavailable actions are filtered at use time | Keep |
| `recommendationDeconeMode` | recommendation scoring | raw-value enum, 9–13 B | App-update preference; loss changes ranking but remains safe | Keep |
| `podcastAffinityWeight` | recommendation scoring | `Double`, usually 3 B, ≤24 B | App-update preference; loss changes ranking but remains safe | Keep |

### UI list preferences

| Key | Owner, readers, and writers | Type / size and cadence | Lifetime and stale/loss behavior | Decision |
| --- | --- | --- | --- | --- |
| `PodcastsList-displayMode` | `PodcastsListViewModel`; UI reads and toggle writes | raw-value enum, 6 B; one write per toggle | App-update preference; grid fallback is safe | Keep with `@PersistedBroadcast`; v72 normalizes legacy native strings |
| `PodcastsList-sortMethod-<title>` | One `PodcastsListViewModel` per fixed or tag-titled list; sort menu writes | raw-value enum, 9–26 B; one write per selection | App-update preference; obsolete renamed-tag keys are harmless and measured domain size is tiny | Keep with `@PersistedBroadcast`; v72 normalizes all legacy native-string values |

The sort-key family can grow by one small key when a tag name changes, and two
equal tag names share a presentation preference. That is acceptable for a
non-critical UI preference at the measured domain size; it should move to a
stable relational identity if podcast lists themselves become database-backed.

### Small durable operational state

| Key | Owner, readers, and writers | Type / measured or bounded size | Write cadence | Lifetime and stale/loss behavior | Decision |
| --- | --- | --- | --- | --- | --- |
| `currentEpisodeID` | `SharedState`; `StateManager` writes, playback/cache/recommendations read | optional episode ID, 1–19 B | Episode load/stop transitions only | Process restart; missing means idle, stale/missing DB row is detected and ignored | Keep with `@PersistedBroadcast` |
| `recommendedEpisodePool` | recommendation engine writes, Up Next and playback seed from it | ID array, 669 B observed for 100 IDs; ≤2,001 B for 100 maximum-width IDs | Once per completed recommendation refresh | Process restart cache; loss is acceptable because it rebuilds, stale IDs are filtered | Keep with `@PersistedBroadcast`; fixed 100-item bound |
| `embeddingWorkDemand` | `EmbeddingWorkDemand`; producers and `EmbeddingProcessor` read/write | state machine, 101 B idle and 133 B during a representative full refresh | Demand/generation and drain state transitions; can be bursty | Process restart; loss only delays DB-derived work, pipeline versioning repairs stale state | Keep with `@PersistedThreadSafe` |

`EmbeddingWorkDemand` previously called `DefaultsStorable` directly around its
own lock. It now uses `@PersistedThreadSafe` and its projected atomic `update`,
so compare-and-mutate operations remain one critical section. The wrapper
persists only changed values, including suppressing repeated widget snapshots
and no-op embedding transitions.

## App-group inventory

The app owns the snapshot writer; the widget intents also read and optimistically
write playback status. These values must be visible across processes, so the
app-group domain is the correct lifetime. All use `@PersistedThreadSafe` with
`sharedDefaults`.

| Key | Readers / writers | Type and serialized size | Write cadence | Stale/loss behavior | Decision |
| --- | --- | --- | --- | --- | --- |
| `skipForwardInterval` | app snapshot writer; widget intent reads | `Int`, 2 B for the default | Initial snapshot and user setting changes | Loss safely uses the widget default; slightly stale value affects one intent | Keep |
| `skipBackwardInterval` | app snapshot writer; widget intent reads | `Int`, 2 B for the default | Initial snapshot and user setting changes | Loss safely uses the widget default; slightly stale value affects one intent | Keep |
| `playbackStatus` | app snapshot writer and widget play/pause intents | enum, 13–14 B in settled states; loading adds roughly the UTF-8 title plus 28 B | Playback state transitions; same-value writes are suppressed | Loss falls back to stopped; scheduled widget fallback entries decay stale active states | Keep |

The largest measured app-group domain was 134 bytes. There is no launch or
app/widget synchronization concern at this volume, and migration v72 does not
touch this domain.

## Values not kept in defaults

### Transcription queue

The old `transcriptionQueue` value was a JSON `[Episode.ID]` rewritten as a
whole after every mutation. It requires ordering, uniqueness, foreign-key
lifetime, atomic batch insertion, and row deletion, which are relational
semantics.

In the measured database:

- 100 IDs encoded to about 0.7 KB;
- 1,000 IDs encoded to about 7 KB;
- 10,000 IDs encoded to about 64 KB; and
- all 103,751 episode IDs encoded to 615,165 bytes.

Draining that worst-case shrinking array one element at a time would perform
roughly 30 GiB of cumulative JSON encoding before any operating-system write
coalescing. The new `episodeTranscriptionQueue` table stores one ordered row per
episode. Enqueue is a single database transaction, duplicate inserts are
ignored, episode deletion cascades, and removing the head deletes one row.
`TranscriptionQueue` retains `@Broadcasted` in-memory observation while
`TranscriptionQueueStore` owns durability. Initial hydration is asynchronous,
so resolving the cached service never performs a synchronous database read
while the dependency container is constructing it; consumers and mutations
await hydration before using the projection.

Migration v71 creates the table and imports valid, existing IDs in first-seen
order. It deliberately leaves the old key until the database migration
commits. Migration v72 then deletes the old key, making an interrupted upgrade
retry-safe.

### Session-only state

Static inventory confirms that transient control state remains in memory:
download and transcription progress, scene phase, the hydrated on-deck model,
in-process playback status, stop-after-current, live play rate, tag and smart
list mirrors, the hydrated queue projection, transcription cancellation, and
failed-attempt presentation. None survives relaunch merely because it may
survive suspension.

## Migration-only and infrastructure access

Normal feature code has no direct per-key `UserDefaults`, `DefaultsStorable`,
or `KeyValueStore` reads/writes outside a `@Persisted` variant. The remaining
direct access is intentional:

| Location | Purpose |
| --- | --- |
| `Environment/UserDefaults.swift` | Constructs the injected standard and app-group stores |
| `DefaultsStorable.swift` and the three wrappers | Central JSON encoding, decoding, stale-value cleanup, and persistence |
| v26 | Immutable historical rename of the current-episode key |
| v29 | Immutable historical conversion of native primitive values to JSON `Data` |
| v32 | Immutable historical queue-length clamp |
| v33 | Immutable historical cleanup of unknown standard/app-group keys |
| v40 and v57 | Immutable historical setting-key copies/renames |
| v54 and v55 | Immutable historical episode-list sort migration into GRDB |
| v63 | Immutable historical Search display-key cleanup |
| v71 | Retry-safe import of the old transcription queue into GRDB |
| v72 | Old queue/navigation cleanup and legacy raw-string normalization |

The audit found two obsolete navigation keys left after navigation restoration
was removed: `navigationEpisodesTopDestination` and
`navigationPodcastsTopDestination`. Migration v72 deletes both. It also closes
a compatibility gap left by v29: older raw-value enums were stored as native
strings, while current wrappers expect JSON `Data`. Valid values for
`appearanceMode`, `nextTrackBehavior`, `PodcastsList-displayMode`, and every
`PodcastsList-sortMethod-` key are normalized; invalid native values are
removed so current defaults apply.

## Verification

Focused migration tests cover ordered import, duplicates/missing episodes,
malformed legacy data, retry-safe cleanup, obsolete-key removal, valid native
string conversion, invalid value removal, and existing JSON preservation.
Queue tests prove persistence through factory recreation without a
`transcriptionQueue` defaults blob. Wrapper tests prove same-value assignment
and no-op atomic updates do not write. Existing processor, background-task,
cache, view-model, and accessibility tests exercise the asynchronous database
queue integration, including concurrent queue resolution and database writes.

No additional migration issue is warranted: the only material size/churn
problem is resolved here, and the remaining domains are bounded to a few
kilobytes with event-driven writes.
