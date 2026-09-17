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

The connection configures `CPNowPlayingTemplate.shared`, enables Up Next,
and disables album/artist navigation until the Podcasts browser supplies its
destination. The playback-rate button cycles the rates configured by the
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
