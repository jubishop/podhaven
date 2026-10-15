---
name: "concurrent-my-mac-test-runs"
description: "Two My Mac test runs at once (e.g. bin/test-all from different worktrees or agent sessions) kill each other's PodHaven test host; every test then reports \"Test crashed with signal kill\" at 0.000s."
type: "reference"
---

# Concurrent My Mac test runs

Only one `PodHaven` test run on the My Mac destination can safely run at a
time on this machine, across every checkout and agent session. When a second
`xcodebuild test` launches the test host, the first run's host is killed. The
result bundle then reports every test failed with `Test crashed with signal
kill` (or `Test crashed with signal kill before establishing connection`) at
0.000 seconds, and `bin/test-all` fails at the `xcodebuild` or
`siri-performance` phase.

Observed on 2026-10-14. Two sessions started `bin/test-all` in different
worktrees about a minute apart. All 2395 tests in the later run failed this
way, and the earlier run failed its Siri performance phase.

Before starting a full or focused My Mac run, check for one already in
progress, such as `pgrep -fl "xcodebuild test|bin/test-all"`. If one is
running, wait for it to exit. Treat a run whose failures are all `signal kill`
at 0.000s as invalid evidence and rerun it alone; it says nothing about the
code under test.
