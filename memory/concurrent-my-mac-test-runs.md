---
name: "concurrent-my-mac-test-runs"
description: "Only one My Mac test run can use the PodHaven test host at a time; a machine-wide lock taken by bin/test-all and bin/with-my-mac-lock makes runs wait. An unlocked run kills the other's host, whose tests report \"Test crashed with signal kill\" at 0.000s."
type: "reference"
---

# Concurrent My Mac test runs

Only one `PodHaven` test run on the My Mac destination can safely run at a
time on this machine, across every checkout and agent session. When a second
`xcodebuild test` installs the test host, the first run's host is killed. The
result bundle then reports tests failed with `Test crashed with signal kill`
(or `Test crashed with signal kill before establishing connection`) at 0.000
seconds, and `bin/test-all` fails at the `xcodebuild` or `siri-performance`
phase.

Observed on 2026-10-14. Two sessions started `bin/test-all` in different
worktrees about a minute apart. All 2395 tests in the later run failed this
way, and the earlier run failed its Siri performance phase. On 2026-10-28 a
separate `xcodebuild` install killed a running `bin/test-all` host after
agents had been asked to check `pgrep` first; that manual check is not enough.

`bin/test-all` and `bin/with-my-mac-lock` now share a machine-wide lock, so
runs wait for each other instead. The
[current-revision workflow](../docs/development-workflow.md#current-revision-swift-validation)
describes it. Wrap every focused My Mac `xcodebuild test` in
`bin/with-my-mac-lock`. Runs that skip the lock, such as Xcode's own test
action or a checkout from before the lock existed, can still collide.

Treat a run whose failures are all `signal kill` at 0.000s as invalid evidence
and rerun it; it says nothing about the code under test.
