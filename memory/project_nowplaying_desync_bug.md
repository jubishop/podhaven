---
name: NowPlayingInfo elapsed time desync bug
description: Recurring bug where lock screen shows stale playback position after background playback, causing scrub/resume to rewind. Three confirmed stale scrub incidents analyzed 2026-04-03.
type: project
---

## NowPlayingInfo Elapsed Time Desync Bug

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
