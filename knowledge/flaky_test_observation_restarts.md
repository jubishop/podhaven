---
name: observationRestartsAfterPodcastEpisodeWithTagsFailure CI flake (resolved)
description: Three CI timeouts of EpisodeDetailViewModelTests/observationRestartsAfterPodcastEpisodeWithTagsFailure resolved by raising Wait.until's priority for that test — root cause was the polled performAppear() spawning a Task that inherited .background and got starved
type: project
originSessionId: 7b105ed2-7faf-438d-8ec3-602445f3ba1e
---
`PodHavenTests/EpisodeDetailViewModelTests/observationRestartsAfterPodcastEpisodeWithTagsFailure` flaked on CI three times — bumping `maxAttempts` 200 → 400 (10s → 20s ceiling) did NOT help, so the original "slow runner" theory was wrong.

- 2026-05-08 01:17 UTC — run 25531107905 at SHA `c063b95f` (10s ceiling)
- 2026-05-08 04:44 UTC — run 25537249477 at SHA `7df6c36e` (10s ceiling)
- 2026-05-08 05:38 UTC — run 25538977061 at SHA `ffcd83a7` (20s ceiling, after bump)

**Root cause:** `Wait.until` ran its polling task at `.background`. The poll closure called `viewModel.performAppear()`, which inside `startObservation()` spawned an unstructured `Task { … }` that **inherited `.background` from the polling task**. On a contended CI scheduler, that observation task could be deferred indefinitely. Because `startObservation()` short-circuits when the prior `observationTask` is "still running" (line 451), every subsequent rebind landed in that wedge — the failed task never finished, never ran its `defer { observationTask = nil }`, and the test timed out at the `Wait.until` ceiling regardless of how high we set it.

**Resolution:** added an optional `priority` parameter to `Wait.{until, forValue}` (defaulting to `.background`) and updated this test to pass `priority: .userInitiated`. With the polling task at `.userInitiated`, the inner observation `Task {}` inherits `.userInitiated` too, runs promptly, fails, clears `observationTask`, and the next rebind lands cleanly. `maxAttempts` was returned to 200.

**Why:** The test exercises a defer-based cleanup race in `EpisodeDetailViewModel.observePodcastEpisode`. Wait's `.background` default exists deliberately to avoid starving production tasks during normal polls; this test was an outlier because the poll closure itself spawns the work it's waiting on.

**How to apply:** if any future polling test spawns its own `Task {}` from inside the poll closure (anything calling `performAppear`-style methods that fire-and-forget unstructured tasks), pass an explicit `priority:` to `Wait.until` / `Wait.forValue` rather than relying on the `.background` default — or that child task can be starved on CI even though it would never starve locally.

## Related

- [[factory_v3_migration]] — Factory v3 actor-isolation rules; the test target's `autoRegister` running on the cooperative pool is the same class of "spawned task inherits an unexpected execution context" issue.
