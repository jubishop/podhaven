---
name: background_tasks_investigation
description: Deep investigation into BGTaskScheduler failures on TestFlight builds — dasd rejection, rate limiting, and scheduling strategies
type: project
---

# Background Task Scheduling Investigation (2026-03-14)

## The Problem
Background tasks (BGProcessingTask / BGAppRefreshTask) schedule and execute correctly on dev builds but fail silently on TestFlight/release builds. `BGTaskScheduler.submit()` returns success (no throw), but the system daemon `dasd` rejects the request internally.

## Key Findings

### 1. dasd Silently Rejects Submissions on TestFlight
Console.app logs (filter for `duetactivityscheduler` and `BackgroundTasks`) reveal:
```
com.apple.duetactivityscheduler  BackgroundTasks  Could not validate request <private> due to error Error Domain=_DASActivitySchedulerErrorDomain Code=0
```
- `submit()` does NOT throw — it appears to succeed from the app's perspective
- `getPendingTaskRequests` returns stale/empty results, confirming the submission was dropped
- The `<private>` values are masked on non-debug builds; use a debug build or logging profile to unmask

### 2. Dev Builds Do NOT Get Preferential Treatment
Earlier observation that dev builds worked was incorrect — dev builds also failed on Jubi's device. The issue was developer mode on the iPhone causing dasd to reject all background task submissions regardless of build type.

### 3. Rate Limiting is Per-App, Not Per-Task-Identifier
Renaming task identifiers does NOT reset rate limiting. Deleting and reinstalling the app partially resets it (tasks work briefly then get rate-limited again). The rate limit appears to be tracked by `dasd` at the app bundle identifier level.

### 4. Apple Docs Say submit() Replaces Existing Tasks — It Doesn't on TestFlight
Apple documentation for `submit(_:)` states: "Submitting a task request for an unexecuted task that's already in the queue replaces the previous task request." In practice on TestFlight builds, the old task persists with its original `earliestBeginDate` and the new submission is silently dropped.   But on dev builds it works as documented.

### 5. Explicit cancel() Before submit() Makes Things Worse
Adding `BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:)` before `submit()` successfully removes the old task, but the resubmit is still rejected by `dasd`, leaving ZERO pending tasks instead of a stale one.

### 6. BGProcessingTask vs BGAppRefreshTask
- **BGProcessingTask**: "Processing tasks run only when the device is idle. The system terminates any background processing tasks running when the user starts using the device."
- **BGAppRefreshTask**: Not affected by the idle requirement. Designed for "short-duration tasks that expect quick results." Limited to 1 in the queue at a time.
- Feed refreshing uses `.appRefresh`; cache purging uses `.processing`.
  - We've tried making both tasks `.processing` but this didn't help.

## Current Architecture (as of 2026-03-14)

### BackgroundTaskScheduler
- `scheduleNextIfNeeded()` — checks `getPendingTaskRequests` first, only calls `scheduleNext()` if no task with this identifier is pending. This avoids hammering `submit()` which triggers rate limiting.
- `scheduleNext()` — private, always uses the configured `cadence`. Called only from `scheduleNextIfNeeded()`.
- `register()` — registers handler with iOS, then calls `scheduleNextIfNeeded()` for initial scheduling. Guarded by `Function.neverCalled(identifier)`.

### Scheduling Points (all via scheduleNextIfNeeded)
1. **`register()`** — initial schedule at app launch (in `bootstrap()`)
2. **Execution handler** — reschedule after iOS runs the task
3. **`.background` scene phase** — retry if nothing is pending

### Task Configuration
- **feedRefresh**: `.appRefresh`, 30-min cadence, requires network
- **cachePurge**: `.processing(requiresNetworkConnectivity: false)`, 2-hour cadence

## Debugging Tips

### Console.app Filters
- Device: select iPhone in sidebar
- Filter by `duetactivityscheduler` or `BackgroundTasks` to see dasd decisions
- On debug builds, task identifiers are visible; on TestFlight they show `<private>`

### App Logs
- `BackgroundTaskScheduler` category shows all scheduling attempts
- "scheduleNextIfNeeded: task already pending" = working correctly, no resubmit needed
- "scheduleNextIfNeeded: no pending task" = will attempt to schedule
- "Pending background tasks:\n  " (empty) = dasd rejected the submission
- "iOS is executing the background task" = iOS actually ran the task (rarely seen on TF)

### Xcode Debugger
Dev builds can force-trigger background tasks:
```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.artisanalsoftware.PodHaven.dev.feedRefresh"]
```

## Latest Change Being Tested (2026-03-14 evening)
Three changes deployed to TestFlight:
1. **feedRefresh switched back to `.appRefresh`** (from `.processing`) — app refresh tasks aren't affected by the idle requirement, better fit for feed refreshing.
2. **Background scheduling now runs synchronously** — moved `handleScenePhaseChange` calls outside the `Task { }` in `PodHavenApp.onChange(of: scenePhase)`. Previously they ran inside an async `Task`, which may have executed after the app was already being suspended. Now `.background` handlers run synchronously in the `onChange` closure, while `.active` handlers still run in a `Task` (after `prepareForForeground()`).
3. **Self-imposed rate limiting on `scheduleNextIfNeeded`** — uses a `lastAttempt` Date persisted in UserDefaults (keyed by task identifier) to ensure we never call `submit()` more often than the task's cadence (1 hour for feedRefresh, 4 hours for cachePurge). This prevents hammering `dasd` with rapid-fire submissions which we believe triggered its undocumented rate limiting. The throttle check happens before even querying `getPendingTaskRequests`.

## Confirmed Working for Andy (2026-03-15 → 2026-03-16)
App logs from TestFlight user **Andy** show background tasks running successfully across multiple builds:

### Build 402 (Mar 13–16)
- **57 BG task executions** (43 feed refresh, 14 cache purge), **52 completed gracefully** (91%)
- Tasks consistently rescheduled with ~15-minute cadence for refreshFeed
- `getPendingTaskRequests` returning populated results (not stale/empty)
- No `dasd` rejection behavior observed

### Build 426 (Mar 16, ~5 hours of data)
- **3 BG task executions** (2 feed refresh, 1 cache purge), **all 3 completed gracefully** (100%)
- Task identifiers changed between builds: `com.artisanalsoftware.podhaven.refreshFeed` → `com.artisanalsoftware.PodHaven.feedRefresh` (and similar for purgeCache → cachePurge)
- Despite the identifier rename, dasd is still accepting and executing them — no disruption
- Scheduling and rescheduling working correctly with proper cadence

### Build 401 (Mar 12–13, ~11 hours)
- **12 BG task executions** (5 refresh, 7 purge), **all 12 completed gracefully** (100%)

## Still NOT Working for Jubi (2026-03-16 → 2026-03-23)
Background tasks were still not executing on Jubi's device as of 2026-03-23. Factory reset + backup restore didn't fix it. All other TestFlight users work fine — only Jubi's device fails.

**Likely root cause (2026-03-23): Developer Mode on iPhone.** Turning OFF developer mode appears to have fixed it. This explains everything:
- Only the developer (Jubi) had developer mode enabled — no other TestFlight users would
- dasd rejects background task submissions (both dev AND TestFlight builds) on devices with developer mode enabled
- Developer mode was re-enabled after factory reset + backup restore, so the reset didn't help
- Earlier finding that "dev builds get preferential treatment" was incorrect — dev builds also failed on Jubi's device

**How to apply:** If background tasks fail on a developer's device but work for all other users, check if Developer Mode is enabled on the iPhone. Turning it off may resolve dasd rejection for all build types. Pending confirmation that this fix holds over time.

## Developer Mode OFF — Results (2026-03-24)
Analyzed 16-hour log window (10:56 PM Mar 23 → 2:59 PM Mar 24) after developer mode was turned off:

### cachePurge (BGProcessingTask): WORKING — 2 executions!
1. **2:52 AM PT** — iOS executed it 1 min after 2:51 AM eligibility. Cleaned up 10 orphaned cached episode files. Rescheduled for 6:52 AM.
2. **10:26 AM PT** — iOS executed it ~3.5h after 6:52 AM eligibility (normal delay for BGProcessingTask needing idle). Cache 835.8 MB, within limit, no purge needed. Rescheduled for 2:26 PM.

### feedRefresh (BGAppRefreshTask): STILL NOT RUNNING
- Scheduled with earliest begin **12:07 AM PT** — sat for 10+ hours untouched
- At **10:19 AM PT**, a new build launched (shows new `deployed` environment type). Old pending feedRefresh vanished (cleared by app update). Freshly rescheduled for **11:19 AM PT**.
- As of **2:59 PM** (3.5h past eligibility), still sitting in the pending queue
- 43 "Pending background tasks" dumps all show it stuck at its earliest date
- Zero errors in the entire log — iOS just ignores the BGAppRefreshTask

### Likely cause for feedRefresh not running
BGProcessingTask (cachePurge) has deterministic triggers — device idle + conditions met. BGAppRefreshTask (feedRefresh) uses iOS's ML-based usage-prediction scheduling, which is more discretionary. After the developer mode toggle disrupted dasd's history for this device, the ML model may need time to rebuild usage patterns. Heavy foreground usage (7+ app launches in 16 hours) may also signal to iOS that background refresh is unnecessary since the user will trigger foreground refresh anyway.

### Bug found: `myDevice` shortcut in detectEnvironment()
`AppInfo.detectEnvironment()` line 107 had `return myDevice ? currentDevelopmentEnvironment() : .appStore` for release builds. On Jubi's device, this caused TestFlight builds to initially report as `iPhoneDev` instead of `.appStore` (before `finalizeEnvironment()` async refinement). While this doesn't directly affect background task scheduling, it's incorrect — fixed by removing the `myDevice` special case so all release builds start as `.appStore` and get refined via AppTransaction.

## feedRefresh CONFIRMED WORKING on Jubi's Device (2026-03-25)
Analyzed 33-hour log window (Mar 23 10:56 PM → Mar 25 8:22 AM PT):
- **12 background task executions total**: 7 feedRefresh + 5 cachePurge, **100% success rate**
- First feedRefresh fired at **3:04 PM Mar 24** — ~1.5 days after developer mode was turned off (Mar 23)
- feedRefresh then ramped to roughly hourly cadence by the evening (6:15 PM, 7:16 PM, 9:45 PM, 10:46 PM, 11:46 PM, then 7:50 AM next morning)
- Every execution found stale series and completed gracefully
- Zero errors or warnings in entire 3,681-line log
- cachePurge continues reliable (~4h cadence)

**Conclusion:** Developer mode OFF is the confirmed fix. The iOS ML scheduler needed ~1.5 days to rebuild usage patterns before it started executing BGAppRefreshTasks. Both task types are now fully operational on Jubi's device.

Background task handler logic can still be tested via Xcode simulator + LLDB:
```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"<task-identifier>"]
```

## Open Questions
- **Why does developer mode cause dasd to reject background tasks?** No Apple documentation explains this behavior. Unclear if it's intentional (security policy?) or a bug in iOS. The rejection is silent — `submit()` doesn't throw, dasd just drops the request internally.
- Is this an iOS 26 regression or long-standing behavior?
- Would filing a Feedback Assistant radar to Apple yield any insight?
