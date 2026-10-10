---
name: "carplay-artwork-test-observability"
description: "CPListItem.image returns CarPlay's downscaled copy, and Nuke memory-cache hits did not reach the pipeline delegate; observe row artwork size through a recording ImagePipeline delegate on a cache miss"
type: "reference"
---

# CarPlay artwork test observability

Two quirks shape any test that asserts the size of CarPlay row artwork.

- `CPListItem.image` does not return the image passed to `setImage(_:)`.
  CarPlay stores a copy scaled to `CPListItem.maximumImageSize` at the current
  display scale. In a My Mac test run on October 9, 2026, a 1200 × 1200 pixel
  input read back as 44 × 44 points at scale 2 (88 pixels). Assertions on
  `row.image` cannot detect oversized input.
- The pipeline that the list uses is the observable boundary.
  `PodHavenTests/Fakes/ImagePipelineRecorder.swift` installs a test
  `ImagePipeline` whose delegate records the pixel size of every successful
  response, keyed by URL.
- In the same run, on Nuke `main` at `2c2b23f6`, a memory-cache hit returned
  the cached image to the caller without a delegate `.finished` event.
  Tests that need delegate evidence must therefore load through a cache miss.
  Waiting for a recorded event keeps such a test from passing vacuously; a
  missing event fails it instead.

Origin: GitHub issue #734, which bounded CarPlay list artwork after main-thread
hangs on connect.
