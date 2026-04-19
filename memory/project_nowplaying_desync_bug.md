---
name: NowPlayingInfo elapsed time desync bug
description: Recurring bug where iOS sends a stale backward scrub ~30–33s after AirPods-triggered background pause. 6 confirmed incidents. Both the incident-3 fix (event-driven writes) and the incident-5 fix (fb43f650, periodic CurrentPlaybackDate anchor + playbackState mirror) FAILED to prevent recurrence on 4/19. Response: removed CurrentPlaybackDate entirely (on-demand audio doesn't need it) and added a 30s wall-clock diagnostic snapshot to catch AVPlayer/dict/mediaserverd drift on the next incident.
type: project
originSessionId: 03a15cba-4c43-4960-b7e0-311fae53bf03
---
## NowPlayingInfo Elapsed Time Desync Bug

### Incident 6 — 2026-04-19 (Andy's report, log.ndjson analyzed same day) — fb43f650 fix DID NOT hold

Andy reported another scrubbing-backwards incident. Build was running fb43f650 (committed 4/18 11:17 PDT) — confirmed by visible 3-second-cadence `setCurrentTime` logs from the new periodic anchor.

**Timeline (Session 30, 2026-04-19 PDT):**
- 13:11:04.988 — `setOnDeck: [27238]` "Nolan, Spielberg…", elapsed=0:00, CurrentPlaybackDate=Date(), playbackState=.paused
- 13:11:05.068 — `setPlaybackRate: 1.0`, playback starts from 0:00
- 13:11:31.464 — scenePhase: **`backgrounded`** (player at ~0:25)
- 13:11:31 → 13:47:38 — 36 min background playback. Periodic anchor logs every 3s of playback delta (working as designed).
- 13:47:38.938 — Last anchor before pause: `setCurrentTime: 33:48` (CurrentPlaybackDate refreshed)
- 13:47:41.151 — Remote command: **pause** (AirPods sleep-pause)
- 13:47:41.155 — Pause handler: `setPlaybackRate: 0.0, currentTime: 33:50, previousElapsed: Optional(33:48)` → **dict only 2s stale at pause** (vs 25:11/14:06 stale in incidents 4/5)
- 13:48:11.467 — **30.32s after pause**: `playbackPosition(1020.7501434850001, sourceEpisodeID: 27238)` = **17:00.75**
- 13:48:11.470 — `logRemoteScrubDecision`: `requestedPosition: 17:00`, `sharedCurrentTime/avPlayerCurrentTime/nowPlayingElapsed: 33:50`, `appState: background`, `routeOutputs: [BluetoothA2DPOutput]`, `paused`, `reason: accepted` → scrub applied, rewinding **16:50**

### Why the fb43f650 fix DID NOT hold

The fb43f650 theory: iOS's auto-extrapolation drifts during long background sessions; periodically anchoring `MPNowPlayingInfoPropertyCurrentPlaybackDate = Date()` (every 3s of playback delta + on rate change + on route change) plus mirroring rate into `playbackState` should keep iOS's view of position consistent.

**Evidence the fix worked at the layer it targeted:**
1. Periodic `setCurrentTime` anchor fired every 3s right up to pause (visible in logs).
2. `previousElapsed: 33:48` at pause vs `currentTime: 33:50` written → dict was only 2s stale (vs 25:11 stale in incident 5 with the same wall-time gap).

**Evidence the fix didn't address the actual bug:**
1. iOS still sent a stale scrub with the same fingerprint (background, BluetoothA2DPOutput, paused, ~30s post-pause, .25/.75 quantization).
2. The captured stale position (17:00) does not correspond to ANY value the dict held — never anchored at 17:00, never had CurrentPlaybackDate matching a wall time that would extrapolate to 17:00, no rate/anchor combination in the dict produces 17:00.

**Updated root-cause theory:** The system-generated stale scrub does NOT read from `MPNowPlayingInfoCenter.nowPlayingInfo` at all. iOS captures the position from a separate internal source — most likely `mediaserverd`'s cached view of `AVAudioSession`/`AVPlayer` state, which is what the AirPods-reconnect window queries when reconciling after auto-pause. That internal view is throttled during long background sessions independent of our dict writes.

**What 17:00 might mean:** Wall-clock at scrub minus 1020s = 13:31:11. At 13:31:11 the player was around 20:07 (assuming linear playback from 13:11:04 + minor buffering). So 17:00 ≠ "position 30s ago". It also ≠ position at backgrounding (0:25). It does not cleanly match any obvious anchor — supports the "internal mediaserverd state" theory rather than any dict-derived value.

### Response shipped after incident 6 (2026-04-19)

Incident 6 proved the dict wasn't the scrub source (dict only 2s stale at pause, yet scrub still fired), so we shifted from "tune the dict" to "instrument and observe":

1. **Removed `MPNowPlayingInfoPropertyCurrentPlaybackDate` entirely** from `NowPlayingInfo.setOnDeck` and `NowPlayingInfo.setCurrentTime`. Incident 6 showed writing it every 3s doesn't prevent the bug, and for on-demand audio the property is genuinely redundant — iOS's implicit receive-time extrapolation does the same thing. The live-stream "playback origin date" semantic doesn't apply to pre-recorded podcasts. If a future incident suggests iOS uses this property for the stale-scrub capture, put it back as `Date()` (write-timestamp semantic, NOT `Date() − elapsed`).
2. **Removed the two speculative `NowPlayingInfo.setCurrentTime` dict writes** also added by fb43f650: the pre-pause anchor in the audio-interruption handler (redundant — the rate observer's `setPlaybackRate(0.0)` writes ElapsedPlaybackTime+PlaybackRate atomically right after), and the route-change anchor (motivated by the disproven "iOS captures dict during wireless-reconnect windows" theory).
3. **Added `logBackgroundPlaybackSnapshot` in PlayManager+Events.swift**. Captures: AVPlayer currentTime, dict ElapsedPlaybackTime, dict PlaybackRate, AVPlayer `timeControlStatus`, `reasonForWaitingToPlay`, sharedPlaybackStatus, appState, routeOutputs. Called from three places:
   - Periodic 30s wall-clock from `PlayManager.setCurrentTime` (label `periodic +Ns`) — daily log overhead ~250KB at 6h/day playback, within the 3MB rotation for 24h retention
   - Immediately on `.pause` interruption (label `pause`)
   - `startPostPauseObservation` task fires 9 snapshots at 5s intervals (+5s through +45s) labeled `post-pause +Ns`, cancelled/restarted on next pause
4. **Added `PodAVPlayer.reasonForWaitingToPlay()`** accessor for the snapshot.
5. **Removed the two CurrentPlaybackDate-specific tests** from `NowPlayingInfoTests`; removed the dict-key assertion in `LoadingTests`.

### Candidate theory — AirPods "Pause when falling asleep" rewind (added 2026-04-19)

Apple's "Pause Media When Falling Asleep" feature (AirPods 4, AirPods Pro 2, AirPods Pro 3 only) uses motion/head-pose sensors to detect sleep onset. Theory: iOS/AirPods internally stamp the "user stopped actively listening" time *T*, keep playing until sleep is confirmed, then dispatch `pause` followed ~33s later by a `changePlaybackPosition` scrub *back to T* as an intentional "rewind to where you dozed off" behavior.

**Fits:**
- Explains why the stale position matches no value our dict ever held (separate internal state in mediaserverd/audiod fed by the AirPods sensor stream).
- Rewind magnitudes (10–17 min across incidents 3–6) are plausible sleep-onset-to-confirmation intervals.
- All confirmed incidents are on a wireless Bluetooth route — consistent with an AirPods-only feature.
- Andy's reports sound like he actually was asleep by pause time, so premature-detection-from-his-POV holds.

**Doesn't fit:**
- Apple docs describe *pause* only, not rewind-on-pause. If this were public behavior we'd expect it documented.
- 32–33s post-pause delay is suspiciously BLE-reconnection-shaped, not sleep-confirmation-shaped.

**Falsification tests:**
- Confirm Andy's AirPods model. If he's on AirPods 3 or pre-Pro-2, theory dies.
- If a future stale scrub fires on a non-sleep-capable route (CarPlay, wired, older Bluetooth, HomePod), theory dies.
- If post-pause snapshots ever show the scrub position matching a stable dict anchor, theory weakens (dict-derived instead).

**Implication:** if this is the mechanism, it's deterministic iOS behavior we cannot prevent from our side — the fingerprint-rejection mitigation is the right move regardless.

### Signals to watch for in next incident's snapshot data

- **Dict `nowPlayingElapsed` differs from pause-handler write** across `post-pause +Ns` snapshots → iOS IS rewriting the dict during the reconnect window; the fb43f650 theory isn't fully dead, just wasn't captured by old instrumentation.
- **`waitingReason` non-nil during `periodic +Ns` playback snapshots** → AVPlayer is stalling internally without us noticing → extrapolation drift is explained by "iOS paused its extrapolation clock because playback wasn't actually producing audio."
- **`avPlayerCurrentTime` runs ahead of `nowPlayingElapsed` by more than ~3s** in periodic playback snapshots → our 3s anchor isn't being read by iOS after all; writes are being silently dropped/throttled.
- **Dict `nowPlayingRate` stuck at 1.0 across post-pause snapshots** → rate observer's `setPlaybackRate(0.0)` write didn't reach iOS, even though our pause handler logged it.

### Fingerprint instrumentation shipped 2026-04-19 (same day as incident 6 response)

Goal: find a signal unique to system-generated scrubs that a user physically cannot produce, so we can classify without relying on the ~33s magic number.

1. **`MPRemoteCommandEvent.timestamp` lag** — Plumbed through `Command.playbackPosition(…, eventTimestamp:)`. `logRemoteScrubDecision` now logs raw `eventTimestamp` and `eventLagSeconds = Date().timeIntervalSinceReferenceDate - eventTimestamp`. Hypothesis: user-initiated lock-screen scrubs lag ~0ms; system-generated scrubs stamped at pre-pause capture time should lag multiple seconds (possibly ~30s matching the post-pause delay). Added `timestamp` to `MPRemoteCommandEventable` protocol and fake events. **This is the primary user-undoable signal.**
2. **Enriched `AVAudioSession.interruptionNotification` logging** — logs `typeRaw`, `optionsRaw`, and `AVAudioSessionInterruptionReasonKey` (iOS 14.5+). `.routeDisconnected` reason (iOS 17+) directly identifies AirPods-disconnect interruptions.
3. **Enriched route-change logging** — now includes `previousOutputs` from `AVAudioSessionRouteChangePreviousRouteKey`, so we can see full old→new route transitions in the log.

The `wasSuspended` key was deprecated in iOS 14.5; reason key supersedes it. NDJSON log timestamps on `Audio interruption notification` / `Audio route changed` / `applying remote scrub` lines let `analyze-logs` correlate temporal proximity without needing an in-memory ring buffer.

Files touched: `PodHaven/Play/Protocols/MPRemoteCommandableCenter.swift`, `PodHaven/Play/Utility/CommandCenter.swift`, `PodHaven/Play/PlayManager+Events.swift`, `PodHavenTests/Fakes/FakeMPRemoteCommandCenter.swift`, `PodHavenTests/PlayManagerTests/PlaybackControlsTests.swift`.

### Still-open mitigations (NOT implemented; ranked)

- **Reject system scrubs by fingerprint.** When `appState=background`, `playbackStatus=paused`, wireless route, position ends in `.25`/`.75`, and `requestedPosition` > e.g. 30s behind `avPlayerCurrentTime`, reject. User-initiated lock-screen scrubs don't match this pattern. Avoided because it's a hack — want root cause first.
- **Put CurrentPlaybackDate back as `Date()`** if snapshot data shows iOS's `ElapsedPlaybackTime` view diverging from ours during background in a way that suggests a missing anchor.

### Key Files

- `PodHaven/Play/Utility/NowPlayingInfo.swift` — dict management (no CurrentPlaybackDate writes; setPlaybackRate mirrors to playbackState)
- `PodHaven/Play/Utility/PodAVPlayer.swift` — periodic time observer, AVPlayer wrapper, `reasonForWaitingToPlay()` accessor
- `PodHaven/Play/PlayManager.swift` — `setCurrentTime` gates the 3s anchor delta and the 30s diagnostic-snapshot wall-clock delta
- `PodHaven/Play/PlayManager+Events.swift` — `logBackgroundPlaybackSnapshot`, `logRemoteScrubDecision`, interruption + route-change handlers
- `PodHaven/Play/CommandCenter.swift` — remote command handler

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
