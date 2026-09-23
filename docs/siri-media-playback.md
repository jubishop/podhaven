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
playback history, or downloaded audio. The app creates it at database startup
and updates it synchronously after relevant commits, including background
refresh and deletion. Before a relevant commit, the previous catalog becomes
unavailable. A crash or failed write therefore causes a truthful temporary
failure instead of silently trusting an obsolete snapshot. Rollback republishes
the unchanged library. The app database stays in its current location. Each
publication has a new generation ID. The main app checks that generation after
its asynchronous lookup and before playback. Names, deletion, publication dates,
and finished state invalidate pending selections; routine position writes do not.

The extension rereads the catalog for resolution, confirmation, and handling.
The system callback copies request fields into a Sendable value. An explicit
`@concurrent` boundary reads, decodes, and matches the catalog away from the main
actor. Framework resolution objects are built on that worker and transferred to
the main actor for completion. New handle requests invalidate older pending
catalog selections. Playback also reads its final generation check off the main
actor and rechecks cancellation, ownership, and authorization after that await.

Name matching uses a single-pass ASCII path or Foundation Unicode folding with
scalar separation. Each request caches up to 1,024 normalized album names.
The cache does not survive the request and cannot return stale catalog entries.
Publication does no additional normalization or indexing. Matching normalizes
case, diacritics, punctuation, and whitespace. Exact names rank
above prefixes and contained phrases. Equally ranked results use Siri's native
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
episode can be replayed. Explicit play resumes the current episode.

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

Sentry receives an automatic event for a resolution taking at least one second
or returning a failure, limited to one event per category per minute in the
process. The extension retains its summaries in the shared app group. The app
reports eligible extension failures on its next Sentry startup, with separate
origin and upload attribution and a bounded receipt list to prevent repeat
uploads. This deferred path needs a later app launch. Both journals accompany
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
pathological metadata distribution.

An optimized local diagnostic benchmark used a 16,564,058-byte catalog. Before
the change, read/decode took about 2/420 ms and broad matching took 429–665 ms;
album matching took 214 ms. Afterward, read/decode took about 2/248 ms, broad
matching took 113–139 ms, and album matching took 15 ms. Decode code is unchanged,
so its timing difference is run-to-run variation. This experiment does not
reproduce or fully explain the reported 98-second hang.

Run `bin/sentry-siri-smoke --device <iOS-Simulator-UDID>` with Sentry CLI access.
The helper uses its authenticated token for exact-byte downloads. It builds an isolated probe
from current sources, delays only its synthetic file handle, and uses the real
handler and production Sentry configuration. It then triggers a controlled
recovered hang. The helper lists both remote events, downloads the retained
summaries, and verifies bounds, phase data, matching operation/session/build
attribution, and absence of the private sentinel metadata. Evidence stays in
ignored `.cache/sentry-siri-smoke/`. It never installs on a physical device.
