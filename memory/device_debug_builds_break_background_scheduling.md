---
name: device-debug-builds-break-background-scheduling
description: Installing a debug build on @jubishop's iPhone kills iOS background scheduling for every build on that device; the Simulator and TestFlight are the only run targets, and the physical device has no debugger.
type: project
---

Never propose installing or running a debug (Xcode-direct) build on @jubishop's physical iPhone.

@jubishop's report: *"if i install the app in debug mode on my phone then the background scheduling from iOS never happens on EITHER build, so i just stopped even doing it."* Once a debug build touches the device, iOS background scheduling (background app refresh / `BGTaskScheduler` work) stops firing — and it stays broken for the TestFlight build too, not just the debug one. So debug-on-device is off the table entirely.

**Why:** A debug install poisons background scheduling for the app on that device, and the breakage outlasts the debug build itself. The mechanism is not diagnosed — treat this as an observed, reproducible behavior, not an explained one.

**How to apply:** This constrains every "how do we reproduce / profile / debug this" decision:

- "Run it locally" / "attach the debugger" means the **iOS Simulator on the Mac** — the only place with an interactive debugger + Instruments. Never the physical iPhone.
- Real-hardware behavior — background scheduling, push, audio-session/playback edge cases, jetsam/OOM — must be exercised via **TestFlight**, which has **no debugger**. Diagnosing there requires self-contained instrumentation: structured logging, Sentry, one-shot error captures, on-device snapshots — not breakpoints.
- If a bug reproduces only on real hardware, plan an instrumented TestFlight build + Sentry-feedback loop. Do not offer a device debug session as a fallback — it does not exist for this project.

Related: [[podcast_detail_recommendation_storm]] — its verification procedure already splits "Simulator, scripted" from "on-device, no debugger" for exactly this reason.
