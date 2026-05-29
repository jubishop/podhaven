---
name: stalled-playback-load
description: Investigation notes for feedback podhaven:7514288031, where playback stayed in loading after selecting an episode. Use when a future report says an episode load sat on the loading indicator, especially around PlayManager.performLoad, Queue.unshift, or DB writer access.
type: project
---

# Stalled playback load

## Incident

Sentry feedback `podhaven:7514288031` on build `1.0+507`
(`e6a396c5`) reported that loading `THIS WEEK IN AI` stalled with the
loading indicator.

The attached app log showed `PlayManager.performLoad(_:)`, `setStatus(.loading)`,
and `clearOnDeck()` for the incoming episode, but did not show
`configureAudioSession`, `PodAVPlayer.load`, `loadAsset`, or
`performLoadAsset`. That means the old log does not support a cache/network
asset-loading stall; the load probably did not reach player-item loading.

There was an outgoing episode and it was expected to be restored to the queue.
However, no `Queue._unshift` log appeared after the load began. Since
`Queue._unshift` logs inside the `appDB.db.write` transaction, the best
hypothesis is that `queue.unshift(outgoing.id)` was waiting before entering
the GRDB writer transaction, not spending time in the simple queue SQL itself.

The later `Repo.updateDuration` log for the same incoming episode does not
disprove writer contention: `Repo.updateDuration` logs before its own
`appDB.db.write`, not after the write completes.

## Instrumentation added

`PodHaven/Play/PlayManager.swift` now logs incoming/outgoing episode details
and before/after timing for each awaited phase in `performLoad(_:)`, including
the outgoing queue restore.

`PodHaven/Database/Queue.swift` now logs before and after the async
`appDB.db.write` wrapper in `unshift(_:)`. On the next recurrence:

- `performLoad: restoring outgoing episode to queue` without
  `queue: unshift write requested` means the stall is before calling Queue.
- `queue: unshift write requested` without `queue: unshifting` means it is
  waiting for GRDB writer access.
- `queue: unshifting` without `queue: unshift write completed` means the work
  is inside `_unshift` or a nested call.
- `performLoad: loading player item` means the stall reached cache/network
  asset loading.
