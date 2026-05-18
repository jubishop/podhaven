---
name: PodcastDetail recommendation-score fan-out OOM
description: Post-landing verification procedure for issue #274's recommendation-scoring fan-out fix. Read before validating a PR for #274.
type: project
---

# PodcastDetail Recommendation-Score Fan-Out — Verification

Verification procedure for issue #274. Diagnosis, fix plan, reproducer, and source-feedback metadata all live on the issue; this page is the operational checklist for confirming the fix worked after the PR lands.

The bug is **not deterministically reproducible**, so verification leans on the regression test suite as the load-bearing signal and treats device/simulator captures as supplemental rather than definitive.

## Validation gates

The PR for #274 should not merge without:

1. **Regression-test suite passing** (load-bearing — see #274 for the five-test spec). Each test asserts a piece of the behaviour contract: bounded compute, latest-state-only publish, hot-cache bootstrap preserved, prewarming preserved on non-rec sorts, active rec sort live-updates. Each test must be proven failing on `9e5299de4` before the fix.
2. **Simulator `xctrace` Allocations comparison** before/after the fix (Half 1 below). Done by the implementing agent.
3. **On-device spot-check** during normal usage (Half 2 below). Done by @jubishop.

## Half 1 — Simulator xctrace, scripted (implementing agent)

CLI-only, no Instruments GUI. Captures an allocations comparison on the iOS Simulator.

1. Build commit `9e5299de4` (the broken baseline) into an iOS Simulator (any modern target; iPhone 17 Pro or similar).
2. Launch and record:

   ```
   xcrun xctrace record \
     --template Allocations \
     --device booted \
     --launch com.artisanalsoftware.PodHaven \
     --output /tmp/podhaven-prefix.trace
   ```

3. Drive the reproducer in the simulator UI (or via XCUITest harness if one is added): search → open a ≥200-episode unsubscribed podcast (use The AI Signal & The AI Noise feed URL if convenient, otherwise any large feed) → tap play on an episode → wait ~30 s.
4. Stop xctrace (Ctrl-C).
5. Repeat against the fix branch into `/tmp/podhaven-postfix.trace`.
6. Extract comparable metrics from both:

   ```
   xcrun xctrace export --input /tmp/podhaven-prefix.trace  --xpath '/trace-toc/run/data/table[@schema="allocations-summary"]' > /tmp/prefix-allocs.xml
   xcrun xctrace export --input /tmp/podhaven-postfix.trace --xpath '/trace-toc/run/data/table[@schema="allocations-summary"]' > /tmp/postfix-allocs.xml
   ```

   (Adjust the schema name to match the exact xctrace version's allocation-summary table; alternatives include `time-sample` and `allocation-events`.)
7. Post the diff in the PR description. Expected drops:
   - **Total allocations during the 0-10 s window after "tap play":** large drop.
   - **`PodcastSeriesDetail` / `ListableEpisode` / `IdentifiedArray*` allocation counts in the same window:** large drop if `#4`'s observation-storm work is also in this PR; modest-to-no drop if only `#1`-`#3` landed.
   - **`recommendations(for:)` invocation count** (instrumented via a `Self.log.info("recommendations: \(candidates.count) ids")` line, then `rg` over the trace's exported logs): should drop from many to ≤ 2 in the same window.

What this validates: the fix reduces allocation volume during the simulated reproducer scenario, not just satisfies the unit-test contract.

What it does **not** validate: whether the reduction clears iOS jetsam on a physical device — the simulator doesn't enforce jetsam the same way.

## Half 2 — On-device spot-check (@jubishop)

Because the bug isn't deterministically reproducible, Half 2 drops the "force a repro" framing and becomes "spot-check that post-fix behaviour is well-bounded under normal heavy usage." The regression test suite is the correctness signal; this is the real-device sanity check that the bound is observably respected in practice.

### Setup

1. In Xcode, select your physical iPhone as the run destination.
2. Set the scheme's Build Configuration to **Release** (`Edit Scheme → Run → Build Configuration → Release`) — Debug builds have allocation-tracking overhead and inflated retained-set sizes that distort the picture.
3. **Product → Profile** (Cmd+I). When Instruments opens, choose the **Allocations** template. (Optionally do a second pass with **Time Profiler**.)

### Recording flow (best-effort repro)

4. In Instruments, press the red Record button. Wait for "Capturing data."
5. On the phone, exercise the flow that most-closely matches the reporter's, ideally cold-launched:
   - Force-quit PodHaven, then foreground it.
   - Go to Search.
   - Search for The AI Signal & The AI Noise (or any ≥200-episode podcast not currently in your library — the bug shape needs an *unsaved* detail page; if AI Signal is already subscribed, pick a different large feed).
   - **From the detail page, tap play on any episode.** If this triggers the storm, you'll see allocations climb visibly.
   - Stay on the detail page for ~30-60 seconds. Don't navigate away.
6. Stop the recording after ~60 s whether or not the storm fires.

If the storm doesn't fire on first try, that's expected. Don't burn cycles chasing it — the goal is to capture whatever the device actually does and confirm it's bounded.

### What to look at, in this order

7. **Allocations summary during 0-30 s after "tap play":**
   - **All Heap & Anonymous VM** — does the bar climb steeply, plateau, or stay flat? On `9e5299de4` it climbs. After the fix it should plateau within a few seconds.
   - **Persistent bytes** — peak value? Reference: iPhone18 family has 12 GB RAM, but iOS jetsam for a *foreground* app typically kicks in around 1.5-2 GB depending on system pressure. Anything north of ~800 MB during a quiet detail-page open is bad.
   - **Persistent objects of class `PodcastSeriesDetail`** (filter box) — should be a small handful, not hundreds. Same for `ListableEpisode`.
8. **Call Tree, "All Allocations", grouped by Library → grouped by Call Tree:**
   - Heaviest allocator on `9e5299de4` is something like `PodcastDetailViewModel.transition(to:)` → `refreshEpisodeList` → `IdentifiedArray.init` / `ListedEpisode.init`, called thousands of times.
   - Post-fix, that path should drop off the top of the call tree.
9. **Memory warnings during the recording.** Check `Console.app` (connect phone, filter for `Memory warning`) or `Settings → Privacy & Security → Analytics & Improvements → Analytics Data` for new `JetsamEvent` files dated to the recording. Post-fix there should be none.
10. **Time Profiler pass (separate recording).** Same flow. Look at the Main Thread track during 0-10 s after "tap play." **Hangs** (red bars at the top of the Main Thread row): pre-fix shows sustained hangs during the storm; post-fix should be clean or short hiccups.

### Cheaper alternative: log grep

After running the fix through normal heavy usage (open detail pages for several large podcasts, switch sort modes, browse), pull `log.ndjson` and grep:

```
rg -c "Updating observed series" log.ndjson
rg -c "transitioning state saved" log.ndjson
rg -c "Log truncated from" log.ndjson
```

Pre-fix the reporter's log had ~2,200 / ~2,200 / 3 in a 3-second window. Post-fix in normal use these should all be tame and there should be no truncations.

This is lower-friction than Instruments and works whether or not the storm fires on a given session.

### What to report back in the PR thread

- Peak All Heap & Anonymous VM (MB) during 0-30 s after tap-play, pre vs post (if storm fired).
- Peak persistent-object count for `PodcastSeriesDetail` and `ListableEpisode`, pre vs post.
- Presence/absence of memory warning or JetsamEvent during the recording.
- Whether Main Thread had a sustained hang (Time Profiler pass).
- The three `rg -c` counts from a normal-usage session.

## Decision rule

- **Log counts tame AND Instruments either didn't fire the storm OR fired bounded:** `#1`-`#3` were sufficient. Open `#4` as a follow-up PR.
- **Log counts still high** (observation storm itself still fires in normal use, even if scoring fan-out is bounded): `#4` needs to be in the same PR as `#1`-`#3`. Continue investigating `ListableEpisode.databaseSelection` and the per-row-change-causes-full-rebuild question.
- **Memory warnings still occur in real use:** neither `#1`-`#3` nor `#4` are enough on their own — escalate.

## Related

- [[recommendation_sort_prewarming]] — intentional prewarming behaviour the fix must preserve.
