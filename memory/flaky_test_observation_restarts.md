---
name: observationRestartsAfterPodcastEpisodeWithTagsFailure CI flake
description: Two CI failures of EpisodeDetailViewModelTests/observationRestartsAfterPodcastEpisodeWithTagsFailure with identical Wait.until timeout fingerprint — bump maxAttempts before investigating logic
type: project
originSessionId: 7b105ed2-7faf-438d-8ec3-602445f3ba1e
---
`PodHavenTests/EpisodeDetailViewModelTests/observationRestartsAfterPodcastEpisodeWithTagsFailure` has now flaked **twice** on CI, both on `worktree-episodeTags`, same day, same assertion message: `.waitUntilFailure("Expected observation to restart after failure and surface the tag.\ntags: []")`.

- 2026-05-08 01:17 UTC — run 25531107905 at SHA `c063b95f`
- 2026-05-08 04:44 UTC — run 25537249477 at SHA `7df6c36e` (intervening run 25536613910 passed clean, so it is non-deterministic)

The test polls `viewModel.performAppear()` with `Wait.until(maxAttempts: 200, delay: .milliseconds(50))` = ~10s ceiling. Locally on broken code the test took 9.9s/11.0s in some runs — already grazing the ceiling.

**Why:** The test exercises a defer-based cleanup race in `EpisodeDetailViewModel.observePodcastEpisode` (Finding 1 fix). It primes `FakeObservatory.podcastEpisodeWithTagsScript` with a `ValueObservation.tracking { _ throw }` so the first observation fails; subsequent `performAppear()` calls must rebind to the real observatory. Two flakes with identical "tags: []" symptom (timeout, not wrong value) on a CI runner that is occasionally slow points strongly at the 10s ceiling, not a logic regression.

**How to apply:** With two flakes confirmed, the next action is to bump `maxAttempts` in this test (200 → 400, giving a 20s ceiling) and observe whether the flake stops. Only investigate the `observePodcastEpisode` defer block / `Task.isCancelled` discriminator if the test still flakes after the bump or it reproduces locally.
