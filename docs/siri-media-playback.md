---
status: current
---

# Siri media playback

## Process boundary

The main app owns the library database and player. The Intents extension reads
only a versioned JSON catalog in the existing build-specific app group. It
never opens the app's Documents database, creates the app's dependency graph,
or starts audio. Debug, Development, and Release keep their existing separate
app groups and receive distinct extension bundle identifiers.

The catalog contains saved podcast and episode names, durable database IDs,
and source identities. Source identities prevent a reused database ID from
selecting different media. It contains no transcript, description, artwork,
playback history, or downloaded audio.

Schema version 2 stores each podcast's ID, feed URL, and title once. Each
podcast nests its episodes as positional ID, GUID, and title arrays, and the
writer leaves slashes unescaped. An episode's source identity combines its own
ID and GUID with its podcast's feed URL. The reader accepts only its own schema
version, so a file from another version fails truthfully until the app
republishes. See [catalog size](#catalog-size).

Launch database initialization never builds the catalog on the calling thread.
It moves the previous file aside, then queues the launch check on the database
writer ahead of any library write. That job registers the commit observer. It
restores the set-aside file when it is [verifiably current](#launch-freshness)
and otherwise publishes the committed library. Until it finishes, the extension
finds no catalog and fails truthfully rather than reading an unverified
snapshot. The main app's Siri handler waits for that check or publication
before reading the catalog, so a cold handoff resolves against the committed
library.

Afterward, the app republishes synchronously on the writer after relevant
commits, including background refresh and deletion. Before a relevant commit,
the previous catalog becomes unavailable. A crash or failed write therefore
causes a truthful temporary failure instead of silently trusting an obsolete
snapshot. Rollback restores the last published or kept catalog. The app
database stays in its current location. Each publication has a new generation
ID; a kept catalog keeps its generation. The main app checks that generation
after its asynchronous lookup and before playback.
Names, deletion, publication dates, and finished state invalidate pending
selections; routine position writes do not.

### Launch freshness

Every launch used to rebuild the catalog, reading every episode row and
rewriting the file, even when the library had not changed. Sentry logs held 240
slow launch publications in the 14 days to October 30, 2026, nearly all in
background launches, typically 1–30 seconds and up to 68 seconds. Launch now
keeps a catalog it can prove current.

Migration v84 adds a one-row `siriCatalogRevision` table. Triggers replace its
random revision in the same transaction as every podcast or episode insert or
delete and every update of a column the commit observer treats as relevant.
`SiriCatalogTests` holds the triggers to the observer's column set, so a
migration that rebuilds either table must recreate them. A random value rather
than a counter keeps a restored or replaced database from matching a catalog
published from a different history.

Each publication records a `source`: that revision, the number of applied
migrations, and `SiriCatalogPublisher.policyVersion`. Bump the policy version
whenever the same library would publish a different catalog, such as a change
to the [size-limit omission policy](#catalog-size). Launch keeps the set-aside
file only when it is nonempty, within the reader limit, has the current schema
version, and records the database's current source. Anything else republishes:

- A relevant commit whose republication never finished. Commits invalidate the
  file first, and the trigger changes the revision even if that invalidation
  failed.
- A launch migration. Its data changes fire the triggers, and any applied
  migration changes the count, which covers table rebuilds that bypass them.
- A catalog schema or publication policy change.
- An invalid or unstamped file, including one an earlier app version wrote.

The kept file's bytes become the publisher's rollback restore point. A
publication or failed check removes the set-aside copy, and the next launch's
move replaces any copy a crash left behind.

The extension rereads the catalog for resolution, confirmation, and handling.
The system callback copies request fields into a Sendable value. An explicit
`@concurrent` boundary reads, decodes, and matches the catalog away from the main
actor. Framework resolution objects and callbacks stay on the worker. Only
main-app playback ownership crosses to the main actor. New handle requests invalidate older pending
catalog selections. Playback also reads its final generation check off the main
actor and rechecks cancellation, ownership, and authorization after that await.

Name matching uses a single-pass ASCII path or Foundation Unicode folding with
scalar separation. An album filter normalizes each podcast title once per
request and skips other podcasts' episodes. Publication does no additional
normalization or indexing. Matching normalizes case, diacritics, punctuation,
and whitespace. Exact names rank above prefixes and contained phrases. Equally ranked results use Siri's native
disambiguation. Unnamed recommendations, unsupported options, absent catalog
data, and missing authorization fail without opening the phone.

Audio handling returns `.handleInApp`. The main app receives
`application(_:handlerFor:)` and returns an `INPlayMediaIntentHandling` object.
The handler prepares shared background playback
and checks the requested ID and source identity against its current database.
This uses UIKit's supported replacement for the older
`application(_:handle:completionHandler:)` callback, deprecated since iOS 14.
A podcast resumes its current unfinished episode, otherwise its newest saved
unfinished episode, with episode ID breaking date ties. A named finished
episode can be replayed while the catalog includes it; see
[catalog size](#catalog-size). Explicit play resumes the current episode.

The main app owns request cancellation, deadlines, and callback completion.
Newer Siri or shared-player requests supersede obsolete work. A response reports
success only after the shared player is ready and playing the requested item.
CarPlay presentation remains owned by the current connection; voice playback
also works without a CarPlay scene.

## System configuration and validation

The extension supports `INPlayMediaIntent` and podcast media categories, with
no restriction while locked after first unlock. It remains restricted while
protected data is unavailable. The main app declares Siri usage and requests
authorization during phone foreground startup. CarPlay never requests permission
or tells the driver to unlock the phone. One assistant affordance belongs on
the Up Next root, with native system visibility and authorization gating.

Automated matching, catalog, delegate, playback, callback, and template tests
cover the app-owned behavior. The accepted delivery evidence consists of these
tests, isolated preview builds, and signed artifact checks for extension
embedding, bundle identities, app groups, and Siri capability. The exact final
revision must pass `bin/test-all`, including the existing CarPlay suites.

Real Siri-driven handoff across the extension and app processes is deferred
and remains unverified. The Simulator media request did not launch the main
app despite authorization and a valid catalog. A generic Siri query also failed,
while the network control passed. These observations do not establish the cause
or prove the app's system integration correct. The user explicitly accepted the
existing automated and signed configuration evidence; a successful real Siri
handoff is not a delivery, merge, after-merge, or issue-closing requirement.
Known app defects and failures in the required automated app suite still block
acceptance.

Spoken Siri, native assistant-cell activation, locked installed-file access,
vehicle audio, and hardware accessibility/input remain unverified unless
separately tested. These optional checks do not block delivery or closure.

See [CarPlay validation](carplay-validation.md) and Apple's
[Intents extension configuration](https://developer.apple.com/documentation/sirikit/creating-an-intents-app-extension),
[audio handoff](https://developer.apple.com/documentation/intents/inplaymediaintenthandling/handle(intent:completion:)),
and [Siri authorization](https://developer.apple.com/documentation/sirikit/requesting-authorization-to-use-siri).

## Resolution diagnostics and performance

Every file-backed resolution records read, decode, and match durations, bytes,
entry count, maximum title length in UTF-8 bytes, request kind and media type,
callback and worker thread flags, outcome, and a random operation ID. The app
and extension each retain at most 16 summaries in a 16 KiB atomic JSON journal.
Records include their original timestamp, process session, version, build, and
commit. Each phase replaces the same operation record, so an interrupted read
or match leaves a pending marker. These files contain no query, media title,
media ID, GUID, or feed URL.

Phase durations exclude synchronous journal writes. Total duration includes
diagnostic overhead between phases. In the app, it also includes any wait for
the launch catalog publication, which no phase measures. A cold handoff can
therefore be reported as slow; compare it with the same log session's
`siriCatalogPublication trigger=launch` summary.

Sentry receives an automatic event for a resolution taking at least one second
or returning a failure, limited to one event per category per minute in the
process. Slow successes and failures use separate categories, including when
a failure is also slow. The extension retains its summaries in the shared app
group. The app reports eligible slow successes and failures on its next Sentry
startup, with separate origin and upload attribution and a bounded receipt list
to prevent repeat uploads. This deferred path needs a later app launch. Both journals accompany
Sentry events, including recovered and delayed fatal hang events, through the
existing attachment-hint callback. The combined additional attachment bound is
32 KiB. Original record attribution must be compared with the incident; nearby
or previous-session work alone does not establish a hang cause. Bounded history
can be displaced by later operations.

`SiriLargeCatalogTests` exercises 100,100 entries with unknown and episode media
types, matching and mismatching album filters, no match, long Unicode titles,
and deterministic ambiguity. Each synthetic resolution has a five-second
completion budget; the callback regression proves that the main actor regains
control while catalog work is pending without using sleep-based assertions.
This synthetic budget is a regression gate, not a claim about every device or
pathological metadata distribution. `bin/test-all` runs this suite in a separate,
required phase after the other app tests. This keeps unrelated test scheduling
out of the timing measurement while retaining the same budgets. The
`SiriPerformance.xcresult` bundle and `siri-performance.log` are retained beside
the other full-run evidence and receive the same diagnostic checks.

An optimized local diagnostic benchmark used a 16,564,058-byte schema 1
catalog. Before the change, read/decode took about 2/420 ms and broad matching
took 429–665 ms; album matching took 214 ms. Afterward, read/decode took about
2/248 ms, broad matching took 113–139 ms, and album matching took 15 ms. Decode
code is unchanged, so its timing difference is run-to-run variation. This experiment does not
reproduce or fully explain the reported 98-second hang.

Run `bin/sentry-siri-smoke --device <iOS-Simulator-UDID>` with Sentry CLI access.
The helper uses its authenticated token for exact-byte downloads. It builds an isolated probe
from current sources, delays only its synthetic file handle, and uses the real
handler and production Sentry configuration. It then triggers a controlled
recovered hang. The helper lists both remote events, downloads the retained
summaries, and verifies bounds, phase data, matching operation/session/build
attribution, and absence of the private sentinel metadata. Evidence stays in
ignored `.cache/sentry-siri-smoke/`, within the
[smoke evidence bound](sentry-recovered-hang-diagnostics.md#controlled-ios-verification).
It never installs on a physical device.

## Catalog size

`SiriCatalogFile.maximumBytes` bounds what the extension reads and decodes.
Schema 1 repeated each podcast's feed URL and title in every episode entry. On
October 25, 2026, TestFlight 1.5 (589) published 189 podcasts and 110,822
episodes as 31,123,436 bytes, 92.8% of the limit, or about 280 bytes per entry.
Once a catalog passes the limit, every Siri request fails.

`SiriCatalogFileTests` writes a synthetic library twice that size, 378 podcasts
and 221,644 episodes, with field lengths that match the measured bytes per
entry. Schema 1 encoded it as 62,867,963 bytes; schema 2 encodes it as
29,520,544 bytes, 88% of the unchanged limit. The real reader then resolves its
podcasts and episodes. In the Debug test host, schema 2 cut
`SiriLargeCatalogTests` decode time from about 200 ms to 30 ms and album
matching from about 20 ms to 2 ms. Broad matching stayed near 200 ms.

A library about 2.3 times the measured one would exceed the limit even in
schema 2. On October 29, 2026, the owner decided to bound what the publisher
writes. The limit and the schema stay unchanged; raising the limit would need
memory measurements from the Intents extension.

A catalog within the limit is published unchanged, with no extra query or
encoding. Otherwise the publisher keeps every podcast and omits episodes until
the encoded catalog fits:

1. Finished episodes go first, oldest publication date first, with episode ID
   breaking ties.
2. Unfinished episodes go only after every finished one, also oldest first.

Each pass estimates sizes before JSON escapes and encodes the result again,
until the catalog fits or no episodes remain. Omitted episodes cannot be
resolved by name. Podcasts stay resolvable, and the app picks a podcast's
episode from its own database. Publication dates and finished state already
trigger republication, so an episode joins or leaves the catalog at the next
relevant commit. Only when the podcasts alone exceed the limit do diagnostics
report `oversized=true`, and readers then fail truthfully.

`SiriCatalogTests` publishes a synthetic library through the database
observer: 3 podcasts and 16,800 episodes, 4,200 of them unfinished, with long
titles that contain escaped quotes. Unbounded, it encoded as 68,443,858 bytes,
about twice the limit, and the reader rejected it. Bounded, the publisher kept
every unfinished episode and the 4,031 newest finished ones, omitted 8,569,
and wrote 33,534,182 bytes. The real reader then resolves every podcast and
the kept episodes, and an omitted episode no longer matches. In the Debug test
host on My Mac, publication took 169 ms unbounded and 286 ms bounded.

## Publication diagnostics

Each catalog publication logs one bounded summary with fixed fields:

| Field | Meaning |
| --- | --- |
| `trigger` | `launch` for the first check or publication in a process, `commit` afterward |
| `skipped` | Whether launch kept a current catalog instead of publishing; `false` for commits |
| `checkMs` | Launch [freshness](#launch-freshness) check time; `none` for commits |
| `publishMs`, `fetchMs`, `writeMs` | Total, row fetch and entry build, and JSON encode, any omission, plus atomic write; `none` when skipped |
| `podcasts`, `episodes` | Published entry counts; `none` when skipped |
| `omitted` | Episodes left out so the catalog fits the reader limit; `none` when skipped |
| `bytes`, `maxBytes`, `oversized` | Encoded or kept size, the extension reader's limit, and whether readers will reject it |
| `openMs` | Launch database open and migration time; `none` for commits |
| `appState` | UIKit application state when launch initialization began; `none` for commits |
| `suppressed` | Commit warnings kept as local debug summaries since the last one sent |

A summary becomes a warning when publication, the launch check, or launch open
time reaches one second, the publisher omits episodes, or the catalog exceeds
the reader limit. A kept catalog is never oversized, so a skipped launch warns
only when it is slow.
`SentryLogHandler` forwards warnings to Sentry Logs with its existing version,
build, commit, and log session attributes. Launch warnings occur at most once
per process. Commit warnings are limited to one per 15 minutes per process; the
rest stay as local debug summaries. Summaries contain no titles, feed URLs,
GUIDs, or media IDs.
Like the existing launch log, `appState` reflects UIKit during launch: the
foreground Simulator smoke launch reported `background`, so this field alone
does not prove a background launch.

A cold Siri handoff that arrives during the launch check or publication waits
for it, so its latency includes the remaining time. Extension requests in that
window fail truthfully.

A local diagnostic benchmark seeded 110 podcasts and 110,000 episodes, giving a
27,709,630-byte schema 1 catalog. In a Debug test host on My Mac, the previous synchronous
launch path held the main thread for 546–587 ms. After the change, launch
initialization returned in 4.9–7.4 ms, and publication finished on the writer
about 0.8–0.9 seconds after initialization began. Phone hardware is slower; the
diagnostics report real devices.

A later benchmark seeded 110 podcasts and 110,000 episodes, giving a
17,722,120-byte schema 2 catalog. In a Debug test host on My Mac, a launch that
republished it took 276–282 ms from opening the database to
`siriCatalogPublished()`. A launch that kept it took 15–16 ms, including reading
the file and decoding its source. With the revision triggers, inserting 20,000
episodes, marking them all finished, and deleting them through their podcast
each stayed within the same run-to-run variation as without them.

Run `bin/sentry-siri-publication-smoke --device <iOS-Simulator-UDID>` with Sentry
CLI access. The helper builds an isolated probe from current sources and seeds a
private sentinel library. It then runs the production launch path with a delayed
catalog write and the production Sentry log configuration. It reads the remote log
back and verifies its fields, bounds, build and session attribution, and the
absence of sentinel metadata. Evidence stays in ignored
`.cache/sentry-siri-publication-smoke/`, within the
[smoke evidence bound](sentry-recovered-hang-diagnostics.md#controlled-ios-verification).
It never installs on a physical device.
