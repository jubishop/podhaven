---
name: "coremedia-mediacache-bound"
description: "CoreMedia keeps AVFoundation's streaming cache in an app's tmp/MediaCache and trims it to its own size limit, so neither PodHaven nor its tooling prunes the debug container's MediaCache."
type: "reference"
---

# CoreMedia MediaCache bound

`Data/tmp/MediaCache` in the `com.artisanalsoftware.PodHaven.debug` container
on My Mac is AVFoundation's streaming cache. It holds `CachedMedia-*` files
and `diskcacherepository.plist`, the index CoreMedia's
`FigDiskCacheRepository` keeps. Streaming a remote `AVURLAsset` writes there,
and PodHaven sets no cache options. macOS does not purge a container's `tmp`,
but CoreMedia bounds this cache itself, so it needs no cleanup from the app or
from development tooling.

The index's `targetsize` is CoreMedia's size limit. Every repository observed
on macOS 27, PodHaven's and other apps', recorded 500 MiB (524,288,000 bytes).
On October 29, 2026, a command-line `AVPlayer` streamed into seeded
repositories. Each time a process opened the cache to stream, CoreMedia:

- Evicted checked-in entries, the finished downloads it keeps for reuse,
  least recently modified first, until the total fell under `targetsize`.
  Eight 70 MB entries became seven.
- Removed checked-out entries that a process left when it exited or was
  killed mid-stream, verified with `SIGKILL`, as when a test run or Xcode
  replaces a streaming debug app.

The cache grows only while something streams, and each new stream trims it
back under the limit. Inspect it with
`plutil -p <container>/Data/tmp/MediaCache/diskcacherepository.plist`.
`bin/test-all` compares only the top-level entries of that `tmp`, so it does
not report new files inside an existing `MediaCache`.

Evidence: [jubishop/podhaven#808](https://github.com/jubishop/podhaven/issues/808).
