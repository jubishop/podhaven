---
name: NowPlayingInfo elapsed time desync bug
description: Recurring bug where iOS sends a stale backward scrub ~33s after AirPods-triggered background pause. 5 confirmed incidents; incident-3 fix (event-driven NowPlayingInfo writes) did NOT hold — bug reproduced 4/13 and 4/16.
type: project
originSessionId: 03a15cba-4c43-4960-b7e0-311fae53bf03
---
## NowPlayingInfo Elapsed Time Desync Bug

### Incident 5 — 2026-04-16 (Andy's report, log.ndjson analyzed 2026-04-18)

Andy: "Did the thing where it thought I fell asleep and paused and then skipped back 15mins after I restarted it." Thursday morning, episode 27140, AirPods, background.

**Timeline (Session 59, 2026-04-16 PDT):**
- 05:16:15.125 — `setPlaybackRate: 1.0, currentTime: 1:18:20` (playback starts, dict written with elapsed=1:18:20)
- 05:16:15 → 05:41:26 — 25 minutes of background playback; periodic observer fires `PlayManager.setCurrentTime` every 10s but **zero NowPlayingInfo writes** (confirms incident-3 fix behavior: continuous writes removed)
- 05:41:26.533 — Remote command: **pause** (AirPods sleep-pause)
- 05:41:26.542 — Pause handler writes `setPlaybackRate: 0.0, currentTime: 1:43:31, previousElapsed: Optional(1:18:20)` → **dict was 25:11 stale at pause**, correct value written immediately
- 05:41:59.157 — **Exactly 32.62s after pause**: `playbackPosition(5371.25, sourceEpisodeID: 27140)` = 1:29:31
- 05:41:59.164 — `logRemoteScrubDecision`: `requestedPosition: 1:29:31`, `sharedCurrentTime/avPlayerCurrentTime/nowPlayingElapsed: 1:43:31`, `appState: background`, `routeOutputs: [BluetoothA2DPOutput]`, `paused`, `reason: accepted` → scrub applied, rewinding 14:00
- 05:42:19.245 — Andy hits play; resumes from 1:29:31 (the "15 min" rewind he reported)

### Incident 4 — 2026-04-13 05:13 PDT (unreported, found in same log)

Same fingerprint: AirPods, background, episode 27067 "Tate-Keeping."
- Pause at 05:13:21.947, `setPlaybackRate: 0.0, currentTime: 26:44, previousElapsed: 12:38` → dict 14:06 stale
- Scrub at 05:13:54.516 (**32.57s after pause**): `playbackPosition(849.25)` = 14:09
- `nowPlayingElapsed: 26:44`, `requestedPosition: 14:09` → rewound 12:35

### Why the incident-3 fix DID NOT hold

The incident-3 theory — "iOS silently stops reflecting continuous NowPlayingInfo writes during extended background playback" — was **wrong**. Evidence from incidents 4 and 5:

1. `nowPlayingElapsed` at scrub time reads **correct** (matches avPlayerCurrentTime) in both incidents, because the pause handler wrote the right elapsed time. Yet iOS still sends a backward scrub.
2. iOS's extrapolation is not rate×realtime. Between last dict write and scrub:
   - 4/13: 846s of real time, iOS extrapolated ~91s (~11%) → scrub at 14:09
   - 4/16: 1544s of real time, iOS extrapolated ~671s (~44%) → scrub at 1:29:31
3. The scrub payload is computed from iOS's stale pre-pause internal state and dispatched ~33s later. Our pause handler's corrected write happens AFTER iOS has already captured the payload, so it can't influence it.

**Revised root-cause theory:** When AirPods auto-pause fires during a long background session, iOS captures its internal extrapolated position (which has drifted backward relative to rate×realtime for reasons unknown — possibly because iOS pauses its extrapolation clock when the app is suspended but not when it's merely backgrounded). iOS then dispatches `pause`, and ~33s later (likely an AirPods reconnection-timeout window) sends a `changePlaybackPosition` with that captured stale position as a "resync."

### Fingerprint (all 5 incidents)

- `playbackStatus: paused`
- `appState: background`
- `routeOutputs` contains a wireless route (BluetoothA2DPOutput in all 5 cases)
- Scrub arrives **32–33s after** the preceding `setPlaybackRate(0.0)` — extremely tight window
- `requestedPosition` significantly behind `avPlayerCurrentTime` (10–14 min in observed cases)
- `playbackPosition(X.25, …)` — scrub value has `.25s` quantization (iOS system-generated fingerprint; user-drag scrubs have arbitrary precision)

### Key Files

- `PodHaven/Play/Utility/NowPlayingInfo.swift` — dict management (setCurrentTime, setPlaybackRate with previousElapsed logging)
- `PodHaven/Play/Utility/PodAVPlayer.swift` — periodic time observer, AVPlayer wrapper
- `PodHaven/Play/PlayManager.swift` — orchestrates playback, event-driven NowPlayingInfo writes
- `PodHaven/Play/PlayManager+Events.swift` — `logRemoteScrubDecision` (includes nowPlayingElapsed read, line 51)
- `PodHaven/Play/CommandCenter.swift` — remote command handler (line 45)

### Incident 3 — 2026-04-03 (Andy's logs, build 445, commit 25465a57)

Andy reported "skipped back a few mins after going to sleep." Log analysis found **3 stale scrub incidents** across 4 days of logs (3/31–4/3), all following the same pattern.

**Stale scrub summary:**

| When | Episode | Requested | Actual | Delta | Delay after pause |
|------|---------|-----------|--------|-------|-------------------|
| 3/31 23:19 | 26920 | 11:14 | 22:19 | -11:05 | 33s |
| 4/3 01:49 | 26978 | 4:32 | 16:07 | -11:35 | 33s |
| 4/3 06:57 | 26978 | 18:21 | 28:36 | -10:15 | 33s |

(Also one benign scrub on 3/31 05:05 where requested == actual.)

**Common fingerprint — all 3 stale scrubs share:**
- `appState: UIApplicationState(rawValue: 2)` (background)
- `routeOutputs: ["BluetoothA2DPOutput"]` (AirPods)
- `sharedCurrentTime` == `avPlayerCurrentTime` (app internal state is correct)
- Scrub arrives **exactly 33 seconds** after the AirPods-triggered pause
- Position is ~10-11 minutes behind actual

**Key diagnostic findings (new logging from incident 2 fixes):**
1. `setCurrentTime` logs flowed every 10 seconds through the entire playback up to the pause — **the periodic observer IS working in background** (original leading theory from incident 2 disproven)
2. `sharedCurrentTime` and `avPlayerCurrentTime` matched at scrub time — **no internal state desync**
3. No guard failures logged in NowPlayingInfo (no "nowPlayingInfo is nil", no negative elapsed, no zero duration)
4. This puts us in case 3 from the incident 2 diagnostic checklist: "setCurrentTime logs KEEP appearing and sharedCurrentTime was correct"

**Root cause (confirmed):** iOS silently stops reflecting continuous `MPNowPlayingInfoCenter.nowPlayingInfo` writes during extended background playback. The code was writing `ElapsedPlaybackTime` every 250ms via the periodic time observer. iOS appears to throttle/drop these writes after some minutes. Because the extrapolation formula (`ElapsedPlaybackTime + PlaybackRate × timeSinceWrite`) makes the lock screen advance correctly even with stale `ElapsedPlaybackTime`, the staleness is invisible until pause — when rate becomes 0 and the stale value is exposed. iOS then generates a `playbackPosition(staleValue)` scrub 33 seconds after AirPods disconnect (likely a reconnection timeout).

**Fix shipped (build TBD):**
1. **Removed continuous NowPlayingInfo writes** — `NowPlayingInfo.setCurrentTime` no longer called from the periodic observer's `PlayManager.setCurrentTime`. StateManager still gets every update for UI.
2. **Event-driven ElapsedPlaybackTime writes only:**
   - On seek: `PlayManager.seek(to:)` writes `NowPlayingInfo.setCurrentTime(time)`
   - On rate change (play/pause/speed): `PlayManager.setPlaybackRate` fetches `podAVPlayer.currentTime()` and passes it to `NowPlayingInfo.setPlaybackRate(rate, currentTime:)` which atomically writes both rate AND elapsed time in one dict write
   - `setOnDeck` still writes initial ElapsedPlaybackTime (unchanged)
3. **Relies on iOS extrapolation** between events — Apple's recommended pattern
4. **Routed seekForward/seekBackward through seek(to:)** to consolidate the NowPlayingInfo write point

**Additional diagnostic logging shipped:**
- `NowPlayingInfo.setCurrentTime` now logs each write (only fires on seeks, so low volume)
- `NowPlayingInfo.setPlaybackRate` now logs `previousElapsed` (what the dict had before the write) and `currentTime` (what we're writing) — if the bug recurs, this shows whether the dict was stale at pause time
- `logRemoteScrubDecision` now reads and logs `nowPlayingElapsed` from `MPNowPlayingInfoCenter` — shows what iOS actually has at scrub time

**Fallback pattern if fix doesn't work (not implemented):**
The system-generated stale scrub has a detectable fingerprint: arrives exactly 33s after pause, while paused, in background, over Bluetooth, with position significantly behind avPlayerCurrentTime. A user-initiated lock screen scrub wouldn't match this pattern (user wakes screen first, timing is variable). Could reject scrubs matching this pattern, but prefer fixing the root cause over hacks.

### Incident 2 — 2026-03-26

Reported by tester "andy". Listening to pod #1 which ended, auto-advanced to pod #2, played ~10 min in background, AirPods sleep-pause fired, user resumed and it went back to the beginning of pod #2.

**Proven bug found:** `lastLoggedTime` in PlayManager was initialized to `0` and never reset between episodes. After episode #1 at ~4260s, the `>= 10` threshold suppressed ALL `setCurrentTime` logs for episode #2 until it passed ~4270s (~71 minutes). So the absence of logs does NOT prove the periodic observer stopped — it was a logging bug hiding evidence.

**Fixes shipped:** `lastLoggedTime` changed to wall-clock `Date`, initialized to `.distantPast`. Added `logRemoteScrubDecision` with full context. Added `currentTime()` and `playbackStatus()` accessors on PodAVPlayer.

### Incident 1 — 2026-03-15

Reported by tester Andy on build 402. AirPods sleep-pause caused lock screen to show position from ~14 minutes ago.

**Fixes applied:** Removed `.scope(.cached)` from system singleton factories (MPNowPlayingInfoCenter, etc.) which could return stale instances after media services reset. Added warning logs on nil nowPlayingInfo guards. Added system event observers (media services lost, time jumped, thermal state). Route change handler now saves position.

**FactoryKit gotcha:** Do NOT add explicit `.scope(.unique)` to factories — it overrides test context scopes and breaks fakes.

### How NowPlayingInfo Extrapolation Hides Staleness

`MPNowPlayingInfoCenter` extrapolates: `displayedPosition = ElapsedPlaybackTime + PlaybackRate × (now - lastDictWrite)`. With rate 1.0, the lock screen advances correctly even with stale `ElapsedPlaybackTime`. The stale value is only exposed when rate changes to 0.0 on pause.

### Key Files

- `PodHaven/Play/Utility/NowPlayingInfo.swift` — all now playing info dict management
- `PodHaven/Play/Utility/PodAVPlayer.swift` — periodic time observer, AVPlayer wrapper
- `PodHaven/Play/PlayManager.swift` — orchestrates playback, event-driven NowPlayingInfo writes
- `PodHaven/Play/PlayManager+Events.swift` — remote scrub decision logging
