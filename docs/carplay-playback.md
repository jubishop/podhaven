---
status: current
---

# CarPlay browsing and playback

The CarPlay connection owns presentation. `PlayManager` owns playback for all
surfaces. Connecting or browsing starts shared data observations, without
restoring media, running foreground recommendations, or activating idle audio.
See [scene lifecycle](carplay-lifecycle.md) for startup and protected storage.

## Up Next and rows

`CarPlayUpNext` projects the durable queue in its existing order. It displays
the current episode separately, including a saved current episode before
media restoration. It observes the existing recommendation pool, intersects
it with the normal candidate filter, preserves ranking, excludes the current
and queued episodes, and applies the user's recommendation limit, including
zero. No CarPlay observer starts the recommendation engine.

`CarPlayEpisodeList` creates native rows with title, podcast, duration or
remaining time, current status, download text, and playback progress. Text is
available before artwork. Rows retain their native identity while their
episode remains visible. Artwork completion must still match both the row
object and image URL. Leaving a page or disconnecting cancels artwork and
clears the old handlers.

Paging updates the existing list. Runtime item and section limits apply to
all sections together, including navigation controls. A page contains at most
50 total rows, even when the system permits more. Previous/Next controls use
space from that budget. When vehicle list restrictions are active, paging
is disabled and the visible prefix explains that more content is available
when vehicle limits permit. The durable queue is never shortened or reordered.

## Podcasts

The Podcasts tab observes saved subscriptions. Recently Updated shows up to ten
shows ordered by their newest saved episode publication date, with podcast ID
breaking ties. All Podcasts includes shows with no saved episodes and uses
locale-aware natural title ordering, then podcast ID. Both paths share the
runtime paging budget with episode lists, including navigation rows.

A show opens in Unfinished. All Episodes includes finished episodes; both use
newest-first publication dates with episode ID breaking ties. Switching filters
reuses the same template and resets its page. Listening state uses the existing
finished flag and resume position. Not started, In progress, Finished, and
Downloaded describe separate saved facts; unfinished does not mean new or unread.
Browsing never fetches a feed or changes a subscription.

Live observations retain visible row objects and page position. Popping a
podcast destination cancels its observation; hiding a page cancels artwork.
A deleted detail becomes an unavailable state without ejecting Now Playing or
issuing player commands. Query errors offer native Retry rows. Empty saved shows,
empty unfinished results, loading, and artwork failure remain distinct.

## Selection ownership

Each selected row passes its stable episode ID to `CarPlaySelection`.
Repeated taps on the same pending selection share one request and retain each
system completion. A different selection completes and invalidates its
predecessor. Every callback completes once, including failure, deletion,
timeout, supersession, and disconnect.

Selection captures the shared player's request revision, awaits existing
playback readiness, and resolves the ID through `Repo`. `PlayManager` checks
the revision and cancellation before accepting playback. Its request stream
also ends an obsolete CarPlay spinner promptly when another surface replaces
that request. Results from a superseded lookup or load cannot show an old
error or navigate.

Selecting a settled current episode opens Now Playing without loading,
changing position, or resuming it. An explicit play command still resumes.
For a new episode, successful return alone is insufficient: navigation
requires the selected episode to be settled and the request still relevant.

A connection-owned deadline ends stalled selection UI after 30 seconds with
a brief CarPlay error and tappable rows. Cancelling presentation work does
not cancel the player's independently owned accepted load. A later accepted
load can finish under normal player policy, but its expired or disconnected
callback cannot navigate. No blanket stop or load cancellation is issued.

## Now Playing and validation

The connection configures `CPNowPlayingTemplate.shared` and enables Up Next.
The album/artist shortcut is enabled when the saved current episode resolves.
A tap looks up the actual current episode again and rejects obsolete results.
Its podcast can be unsubscribed. The shortcut returns through the existing root
to the same podcast destination, reserving space for another Now Playing visit.
The playback-rate button cycles the rates configured by the
existing remote-command center and uses its shared command stream. Existing
metadata, skip intervals, play/pause, seek, and next-track behavior remain in
the shared player and command center.

Now Playing is pushed only when absent and with stack space available.
Up Next pops back to the existing root and selects its queue tab. Queue updates
never replace the root or eject Now Playing. Disconnect removes the observer,
clears buttons and row handlers, and invalidates connection callbacks.

Tests exercise real application orchestration and native template objects,
with fakes at system integration boundaries. Isolated SwiftUI content
previews do not reproduce the native CarPlay renderer. The user accepts
automated tests, preview builds, and applicable signed Simulator build checks
for delivery. Native visual, spoken Siri, locked-device, vehicle audio, and
hardware accessibility/input checks are explicitly unverified unless separately
performed; they are not merge or issue-closure gates. Automated failures and
known functional defects still block delivery.
