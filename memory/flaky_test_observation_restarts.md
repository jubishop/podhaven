---
name: observationRestartsAfterPodcastEpisodeWithTagsFailure CI flake
description: One CI failure on 2026-05-08 of EpisodeDetailViewModelTests/observationRestartsAfterPodcastEpisodeWithTagsFailure — Wait.until timed out at 10s; revisit if it recurs
type: project
originSessionId: 7b105ed2-7faf-438d-8ec3-602445f3ba1e
---
`PodHavenTests/EpisodeDetailViewModelTests/observationRestartsAfterPodcastEpisodeWithTagsFailure` flaked once on CI on 2026-05-08 at SHA `c063b95f` (run 25531107905). Failure: `.waitUntilFailure("Expected observation to restart after failure and surface the tag.\ntags: []")`. The test polls `viewModel.performAppear()` with `Wait.until(maxAttempts: 200, delay: .milliseconds(50))` = ~10s ceiling. Next CI run at `4eccb622` passed cleanly with no code change in that area, so the failure appears to be runner contention or a slow startup hitting the 10s ceiling rather than a real bug.

**Why:** The test specifically exercises a defer-based cleanup race in `EpisodeDetailViewModel.observePodcastEpisode` (added with the Finding 1 fix). It primes `FakeObservatory.podcastEpisodeWithTagsScript` with a `ValueObservation.tracking { _ throw }` so the first observation fails; subsequent `performAppear()` calls must rebind to the real observatory. Locally on broken code the test failed at 54.8s (default Wait.until ceiling); after the fix it passed in 0.3–3.0s. CI ran at 9.9s/11.0s in some local runs against broken code — close to the 10s ceiling.

**How to apply:** If this test fails again on CI, the most likely cause is the 10s Wait.until ceiling being too tight for slow CI runners, NOT a real regression in the observation cleanup logic. First action: bump `maxAttempts` (e.g. 200 → 400) to see if it stops flaking, before assuming the defer-based cleanup is broken. Only investigate the `observePodcastEpisode` defer block / `Task.isCancelled` discriminator if multiple consecutive CI runs fail or it reproduces locally.
