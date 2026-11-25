---
status: current
---

# Development workflow

This repository keeps knowledge as Markdown and searches it with QMD.
Each checkout has its own index. Git hooks refresh it in the background.

## First setup

Run from the repository root:

```sh
bin/setup
bin/install-cleanup-agent  # macOS, primary checkout only
bin/doctor
bin/doctor-xcode           # macOS
bin/check --full
```

Setup needs Git, Python 3, and QMD, plus direnv when the project has an
`.envrc`; see [required tools](foundation/knowledge-search.md#required-tools).
Install QMD using its
[official instructions](https://github.com/tobi/qmd#installation);
`bin/doctor` reports the installed QMD version. Checks also require
ShellCheck, available through the operating system's package manager;
`bin/check --full` also requires actionlint, fish, and Ruby.

Setup validates configuration, activates bundled hooks when no existing
integration would be displaced, prepares caches, and waits for the initial
index refresh. QMD may download local models on first use. Rerunning setup
preserves existing choices and skips indexing when inputs are unchanged.

The bundle omits `.envrc`. Create it only when the project needs environment
settings, and review it before running `direnv allow`. QMD does not need direnv
or shell-wide environment exports. Preserve useful existing environment
settings when adapting setup; remove an obsolete QMD-only file.

## Runtime and toolchain versions

Local development and tests require macOS 27 or later, Xcode 27 or later,
and Swift 6.4 or later, as declared in the [README](../README.md#prerequisites).
The app and its extensions share one iOS 26 deployment target, since the
system won't load an extension that targets a newer iOS than the device runs.
New Xcode targets default to the newest SDK, so match theirs to the app's;
`bin/tests/test_xcode_project.py` fails when any build configuration differs.
The macro package also declares its minimum Swift tools version in
`PodHavenMacros/Package.swift`.
Keep development, CI, and release tools compatible with these requirements.
Use the existing manifests and setup mechanisms instead of adding conflicting
version declarations.

When changing application commands, reject unsupported toolchains before
installation, tests, builds, or release work. Report the detected version,
the supported versions, and how to select a compatible toolchain. Check the
selected tools with `xcodebuild -hideShellScriptEnvironment -version` and
`xcrun swift --version`. Use `DEVELOPER_DIR` to select a different installed
Xcode for a command.

Coordinate toolchain upgrades across development, CI, and deployment after
dependency and behavior checks. Review automatic version selectors when
changing the supported major versions; do not silently widen that policy.
Document and foundation checks must remain independent of Xcode and Swift
because they do not use those tools.

## Package dependencies

The app's Swift package requirements, and the macro package's swift-syntax
and swift-tagged, deliberately track each project's development branch,
`main` or GRDB's `master`, instead of release versions. Fixes and support for
new toolchains, such as Swift 6.4 and Xcode 27, arrive as soon as they land
rather than with the next release. Version ranges from the newest releases and
exact release pins were considered and rejected. Two app requirements differ:
Swift Collections has the exact pin described below, and
swift-concurrency-extras uses a version range.

These safeguards make branch tracking safe:

- `Package.resolved` records each package's exact revision, so builds stay
  reproducible until someone updates packages.
- Every package update is a reviewed change that passes `bin/test-all`.
- A package whose development branch breaks the app's deployment target gets
  an exact release pin. Swift Collections uses release 1.6.0 because its
  development branch introduced a Swift runtime symbol that prevented the app
  from launching on OS 26. Keep dependency runtime requirements compatible
  with the app's deployment target.

The app's `Package.resolved` and `PodHavenMacros/Package.resolved` pin the
macro package's dependencies separately. Xcode builds the macros from the
app's pins, while `bin/test-all` tests them with `swift test` from the macro
package's own. Before running tests, `bin/test-all` fails when a macro
package pin differs from or is missing in the app's file. After updating
packages, copy the app's new pins for those dependencies into
`PodHavenMacros/Package.resolved`.

The agent configurations in `.mcp.json`, `.cursor/mcp.json`, and
`.codex/config.toml` pin the Apple documentation MCP server,
`@kimsungwhee/apple-docs-mcp`, to one exact version. It is a single-maintainer
package that runs with the user's full privileges on the Mac that holds the
release credentials, so a new release must not run unreviewed. Bump it only
after reviewing the release's changes, in all three files at once;
`bin/tests/test_mcp_config.py` requires every npx-launched server to name one
exact version everywhere.

## Worktrees

Shared worktree, model, and recovery rules are in
[knowledge search](foundation/knowledge-search.md#worktrees-and-models).

After removing a worktree, run `bin/post-worktree-remove` from the primary
checkout. It runs `bin/prune-worktree-caches --apply`, which deletes the
DerivedData of removed checkouts. A removal not followed by it is covered by
the next preparation or hourly sweep.

## Xcode caches and automatic cleanup

`bin/setup-application` prepares Xcode caches, after setting the SSH keepalive
that the [tooling pre-push gate](#tooling-pre-push-gate) relies on.
`bin/setup`, `bin/prep-worktree`, and the Git hook that sets up each new
worktree all run it.

**Decision — 2026-11-24:** The user chose to give each checkout packages of
its own, cloned from a shared seed (jubishop/podhaven#1012). When checkouts
shared one package folder, a checkout pinning other revisions switched its
package checkouts under another checkout's build, which then failed or
compiled the wrong revision. Failing fast once a build found the folder
switched would still fail builds, and serializing resolution can't hold raw
`xcodebuild` or Xcode.

Each checkout gets private DerivedData at Xcode's default path, and its
`SourcePackages` is an APFS copy-on-write clone of the seed,
`~/Library/Developer/SharedSourcePackages/PodHaven`. SwiftPM records absolute
paths through whichever folder resolved them, even a since-deleted custom
DerivedData, so preparation moves those in the clone's `workspace-state.json`
and in each package checkout's Git alternates and origin into the clone. It
refuses a clone whose checkouts or artifacts don't match that metadata, as
when the seed was caught mid-update, and Xcode then resolves the checkout's
packages afresh. Builds in a clone never update the seed, so a clone fetches
only what its pins need beyond it. Preparation also replaces a checkout's
earlier link to the seed with a clone once that checkout's DerivedData is idle
and the clone verifies. Until then the link stays, because checkouts still
linking the seed may read paths it recorded through that link. Preparation
makes a missing seed from a private package folder.
It copies missing per-user workspace settings from the primary checkout and
preserves existing settings. It does not start a warm-up build.

`bin/install-cleanup-agent` installs an idempotent macOS LaunchAgent from the
primary checkout. It runs at login/load and once each hour while the user is
logged in. Cleanup also runs during `bin/prep-worktree` and from
`bin/post-worktree-remove`.
There is no routine maintenance command to remember. Reinstall the agent after
moving the primary checkout. Its plist is
`~/Library/LaunchAgents/com.jubi.podhaven.worktree-cleanup.plist`. The agent
starts uv's default `~/.local/bin/python3` through `/bin/sh`, so it follows
Python updates without a reinstall: macOS pins a login item to its program's
signature, which Apple's shell keeps and each new interpreter changes. The
installer refuses to write the agent until
`uv python install --default` has created that interpreter.

Cleanup only removes a DerivedData folder when its plist and path hash identify
an absent checkout owned by this clone, or, before Xcode has written that plist,
when its name is the path hash of a recorded checkout that is gone. Its private
packages go with it. Registered worktrees, existing checkout directories, and
unrelated caches are preserved.
Preparation and cleanup share a filesystem lock. Build-process and open-file
checks also guard deletion; Xcode does not take our lock. Ambiguous activity
causes deferral and a later automatic retry.

Before deletion, cleanup checks the seed's SwiftPM artifact paths for checkouts
that still link it. A path through an orphan's `SourcePackages` is replaced
with its existing target in the seed, verified as the same file while that
folder still links the seed. Repair requires Xcode and
package users to be closed. Unverifiable references defer cleanup. The seed and
QMD model weights are retained.

Inspect candidates with `bin/prune-worktree-caches --dry-run`. Use `bin/doctor-xcode`
to read the latest removal totals, deferred reasons, errors, whether this
checkout's packages are private, and hourly job state. The latest report
replaces its predecessor under the common Git directory's
`knowledge/xcode/cleanup.json`; fatal errors use a single
`.cache/worktree-cleanup/last-error.json`. Hourly output does not accumulate logs.
Caches with no trustworthy ownership metadata require manual investigation.

If Xcode uses custom cache locations, set absolute local Git values before setup:
`knowledge.xcodeDerivedDataPath` and `knowledge.xcodePackagesPath`, the seed.
The seed must stay outside DerivedData, on the same APFS volume. These
overrides also support isolated integration tests; they do not change Xcode's
own preferences.

### Validation checkout isolation

Shared rules are in [checkout isolation](foundation/engineering-policy.md#validation-checkout-isolation).
Xcode's synchronized target folders define application sources, and
`bin/lint-swift-format` searches its declared production roots. Foundation
static checks use this checkout's Git file list; tooling tests are discovered
under `bin/tests`. Preserve these boundaries when extending the commands.

Keep mutable test data, packages, and build output separate between checkouts,
as the per-checkout DerivedData and package clones described above do; do not
share them to save setup time.

## Diagnostics

`bin/doctor` checks the shared foundation; see
[diagnostics](foundation/knowledge-search.md#diagnostics).
`bin/doctor-xcode` reports Xcode cache and cleanup state and exits 1 when
something needs attention; `--json` prints the full report.

## File organization

Every Swift file must stay under 1000 lines, as required by
[AGENTS.md](../AGENTS.md#coding-standards); other files follow the
[file organization policy](foundation/engineering-policy.md#file-organization).
Preserve the Swift extension rules in AGENTS.md when splitting Swift types.

## Test-driven development

Every regression fix and functional change requires an automated test that
fails before implementation and passes afterward; this is stronger than the
[shared policy](foundation/engineering-policy.md#test-driven-development),
which allows exceptions. Preserve PodHaven's Swift Testing fixtures and
suite-level filters from [AGENTS.md](../AGENTS.md#testing), and use focused
`unittest` runs for tooling.

### Test cost and coverage

Shared rules are in [test cost and coverage](foundation/engineering-policy.md#test-cost-and-coverage).
PodHaven's Swift tests already support concurrency through per-test Factory
isolation. Preserve that design. Before adding concurrency elsewhere, identify
shared files, processes, data, and services and provide independent setup and
cleanup. Do not hide races with retries, longer timeouts, weaker assertions,
or serialization of the Swift suites.

Use event signals or database observations to wait for asynchronous work.
Keep the real work and its outcome assertions; avoid repeated prerequisite
journeys when an isolated fixture supplies the same starting state. Test each
worker's configured priority once, then cover actual priority execution and
overrides in the shared scheduler. Keep real audio decoding and the complete
download-to-analysis journey in their dedicated tests.
Foreground silence-priority tests use an already-analyzed cache fixture to
verify real worker priority and completion without waiting for audio I/O.

Hosted view tests use `withHostedTestWindow` to perform their first layout
inside the test's dependency context and await UIKit appearance and teardown.
Keep views installed and preserve their rendered assertions.

On My Mac, hiding the test host, such as with Hide Others from another app,
minimizing its window, or switching to a Space without its window moves its
scene to the background, where SwiftUI stops rendering hosted views.
`withHostedTestWindow` therefore keeps the scene's window on screen while the
app is hidden, shows it on every desktop and on other apps' full-screen
Spaces, and disables its minimize button and Minimize command. Only an
accessory app's windows can join another app's full-screen Space, so the test
host becomes one, without a Dock icon or menu bar, and its window then appears
over a full-screen app during a run. It also brings back a minimized or hidden
window without activating the app, which covers a window minimized another
way, such as with Minimize All, and a test host hidden before its first
hosted test, which it also unhides. After a hide, UIKit treats the returned
window as off screen until it next checks the window, so the helper then posts
an active-Space change, which makes UIKit check it. A test that builds its own
window in that scene calls `keepTestSceneOnScreen` first.

### Current-revision Swift validation

Use this full-suite procedure when the [validation policy](#checks-and-project-extensions)
requires it for functionally material changes. For a PR merge, integrate its
current head with the latest `main` before validation and verify the merge
will contain the tested tree.

For the final clean revision that requires full validation, run:

```sh
bin/test-all --ensure --revision <sha>
```

Replace `<sha>` with the full commit hash being validated. The command requires
a clean checkout at that revision. It searches the retained reports newest
first and reuses the first passing one whose revision, checkout contents,
toolchain, macOS version, destination, and evidence artifacts still match, so a
newer failed, interrupted, or other-checkout run does not hide it. Otherwise,
it runs the complete suite. A new commit or
change to the integration base requires a fresh full run.
`bin/test-all --verify --revision <sha>` checks existing evidence without running
tests and fails when it cannot reuse that evidence. Plain `bin/test-all` always
runs the complete suite and also supports uncommitted development work.

`bin/test-all` runs repository checks, Python skill and helper tests, shell
tooling tests, Swift formatting checks, macro tests, and the complete
`PodHaven` test plan on My Mac (Designed for iPhone). Each timing suite, the
large Siri catalog suite and the large OPML import suite, runs in its own
required phase after the other app tests, so its budgets exclude contention
from unrelated tests. The OPML suite's main-thread budget counts the main
thread's own CPU time, which other tests' main-actor work would inflate. Every
phase must pass with zero skipped tests and validated diagnostics; their logs
and result bundles are retained in the same evidence directory.

My Mac also runs hosted UI tests that the iOS Simulator skips. Use additional
simulator checks when a change needs environment-specific coverage. Development
checks use local targets; physical-device testing belongs to separate release
workflows and must respect the [device restriction](../AGENTS.md#repo-guardrails).
The local run is the test gate; GitHub does not run test CI.

For focused application tests, use My Mac by default with
`-destination 'platform=macOS,name=My Mac'`. Select a complete suite/class with
`-only-testing:PodHavenTests/SomeSuite`; method filters can report success while
running zero tests.

Run focused tests with the README's
[suite command](../README.md#run-a-specific-test-suite), which passes the
test-build flags listed below. Its `bin/with-my-mac-lock env -u SDKROOT` prefix
takes a [validation slot](#validation-slots) and the
[My Mac test lock](#my-mac-test-lock), and lets Xcode select the SDK for the
requested destination; `bin/test-all` takes both and clears inherited `SDKROOT`
itself.

Run `bin/test-all --preflight` to check the Xcode, Swift, and macOS versions
without running tests. Release commands run this preflight too.

My Mac code coverage also needs access to the PodHaven app's data. In System
Settings → Privacy & Security → Files & Folders, expand the terminal or app
running tests and enable PodHaven. If this access is denied, tests can pass
while Xcode cannot collect coverage files; the diagnostic check rejects that
run's warnings.

After both phases, `bin/test-all` compares the test host's temporary
directory, `Data/tmp` in the `com.artisanalsoftware.PodHaven.debug`
container, with its contents before the run. It fails when tests left a new
entry there; only the system's `TemporaryItems` and saved-state folders are
exempt. Tests write files under `TestFiles.uniqueURL()`, which keeps one root
per test process. The process removes its root when it exits, and the next
test process removes any root that a crashed one left behind. Reading that
directory needs the same access to PodHaven's data.

Each `xcodebuild test` run also makes a directory in that container's `Data`
for the test host's coverage profiles and leaves it there. Xcode names it with
`ProcessInfo.globallyUniqueString`, `<UUID>-<pid>-<hex>`, where the pid is the
process that made it. When its `xcodebuild test` phases end, even when one
fails and stops the run, `bin/test-all` removes each directory of exactly that
shape, with any profile inside, unless its pid is still running and started
before the directory was made. That keeps a live run's directory and clears
those that focused runs and Xcode's own test action leave behind.

Each attempt retains logs, its `.xcresult` bundle, diagnostic reports, and
`run.json` under `.cache/test-all/`. The report records the revision, local
changes, toolchain, destination, and outcome. Its `phases` record each phase
the run reached: tooling, Swift lint, macros, and the three `xcodebuild test`
phases, each with its result validation. For each, it records the 1-, 5-, and
15-minute load averages and the core count at the phase's start and end, and
the peak 1-minute load sampled every `LOAD_SAMPLE_SECONDS` while it ran. A
phase whose peak exceeded twice the core count is `saturated`. When a
saturated phase fails, including when a check of its output fails, the failure
output and the report's `saturation` field say that the failure may be
load-induced. The flag only informs: the run still fails, and `--ensure` and
`--verify` never reuse it. A new attempt keeps only the
newest evidence directories, up to `RETAINED_RUNS` in `bin/test-all` (five,
counting itself), and removes older ones. That bound always keeps the newest
earlier run, which reuse and comparison need, and leaves other entries alone.
The command permits uncommitted development work but rejects a checkout that
changes during the run. When full validation is required, retain a passing
report for the final clean revision through the push, merge, or release. An
earlier dirty-worktree run does not establish acceptance of that commit.

While each `xcodebuild test` phase runs, `bin/test-all` watches for a stalled
test host. The host is the latest `PodHaven (<pid>)` the phase's log names, so
a host that XCTest relaunches after a timeout is followed, and build output
before any host exists never counts. When the log stops growing for
`QUIET_LOG_SECONDS` (two minutes) while that host is alive, the command takes
two `sample` captures of it, `SAMPLE_GAP_SECONDS` apart, as
`<log>-host-<pid>-1.sample.txt` and `-2.sample.txt` in the evidence directory,
and names them in the failure output. It takes at most one pair per phase and
then keeps waiting for `xcodebuild`, so the samples add evidence without
ending the run early or changing whether it passes. Comparing the two samples
shows which threads stayed blocked. Only the app phase's log names its host
while tests run. A timing phase's log names its host only after
the host exits, so a stall in that phase leaves no samples.

The command runs automated tests with isolated service fixtures. Live Sentry
smoke tests in `.agents/scripts/sentry-cli/test_sentry_skills.sh` and real QMD
smoke tests remain separate because they need external credentials, current
service data, or installed models. Run the relevant smoke tests when those
integrations change; they do not replace the automated suite.

Retain the `.xcresult` bundle and raw `xcodebuild` log for local runs.
Pass `-hideShellScriptEnvironment`, `-skipMacroValidation`, and
`LM_FORCE_LINK_GENERATION=YES` to test builds, as the
[suite command](../README.md#run-a-specific-test-suite) does. Without
`-skipMacroValidation`, the build stops at package macros Xcode hasn't been
told to trust. `LM_FORCE_LINK_GENERATION=YES` runs App Intents extraction even
when a dynamic package's dependency file does not list App Intents. It
confirms that there are no relevant symbols instead of emitting a
skipped-extraction warning; it does not suppress warnings or bypass metadata
validation.

Run `bin/check-swift-results <bundle.xcresult> --build-log <xcodebuild.log>`
after focused tests, adding `--full` for the complete suite. This gate requires
passing tests, zero skipped tests, complete priority arguments, zero build diagnostics and raw
build warnings, and no framework runtime diagnostics in exported test output.
The sole approved exception is the exact transitional Sentry callback warning
described in [recovered-hang diagnostics](sentry-recovered-hang-diagnostics.md).
Intentional application warning/error logs from error-path tests remain
available and are distinct from compiler and framework diagnostics.

#### My Mac test lock

Only one My Mac test run can use the PodHaven test host at a time on this Mac:
a second `xcodebuild test` that installs the app kills the host of a run in
progress, from any checkout or session. See
[concurrent My Mac test runs](../memory/concurrent-my-mac-test-runs.md).
`bin/test-all` therefore holds a machine-wide lock,
`~/.cache/podhaven/my-mac-tests.lock`, across both of its `xcodebuild test`
phases, and `bin/with-my-mac-lock COMMAND [ARG...]` runs a focused command
under the same lock. A run that finds the lock busy prints the holder's
process ID, start time, command, and checkout, then waits for it.

The lock is an advisory file lock, so the system releases it when every
process holding it exits or is killed; no stale lock outlives a run. The
`xcodebuild` processes started under the lock keep it too, so one that
outlives its `bin/test-all` still blocks the next run. A nested
`bin/with-my-mac-lock` or `bin/test-all` reuses the lock it inherits instead
of waiting on itself. If a holder hangs, stop its run, including its
`xcodebuild`, to release the lock. Xcode's own test action does not take the
lock.

UIKit on the Mac sends every scene to the background while the displays
sleep, which fails every hosted test running then, so a run that takes the
lock also holds a display-sleep assertion with
`caffeinate -d -u -w <its process ID>`. That wakes a display that is already
off and keeps it on until the run exits, or for `bin/with-my-mac-lock`, until
its command exits. A nested run reuses the assertion with the lock.

A screen saver or a locked screen doesn't background hosted tests while the
display is on, so runs hold neither off. On 2026-11-24, hosted suites passed
under a screen saver started before and during their run, and a full
`bin/test-all` passed on a Mac whose screen stayed locked with a password
while its display was on (jubishop/podhaven#1061).

#### Validation slots

**Decision — 2026-11-09:** Concurrent sessions queue for machine-wide
validation slots instead of saturating the Mac. That day, about ten sessions
each ran `bin/test-all` at once, load averages reached 289–510 on 18 cores, and
every run failed with timeouts that said nothing about the code under test.
The My Mac test lock serializes only the `xcodebuild test` phases; the tooling
phase, whose `bin/tests` fakes start thousands of short-lived processes, was
the largest source of load.

`PODHAVEN_VALIDATION_SLOTS` sets how many heavy runs do their work at once on
this Mac, as a positive integer that defaults to 2; any other value fails with
a clear error. Set it outside the repository, such as in a shell profile, so
every checkout on the Mac shares one count. These runs take a slot:

- `bin/test-all`, from before its first phase until it exits.
  `bin/test-all --preflight`, `--verify`, and an `--ensure` run that reuses
  evidence do no heavy work and take no slot.
- `bin/check --full`, through `bin/check-application`, including in the
  [tooling pre-push gate](#tooling-pre-push-gate). A pass that `bin/check`
  reuses runs no checks and takes no slot.
- Focused runs under `bin/with-my-mac-lock`.

The fast `bin/check`, `bin/lint-swift-format`, and the macro `swift test` take
no slot when run on their own.

Each slot is an advisory file lock, `~/.cache/podhaven/validation-slot-<n>.lock`,
which holds a one-line record of its holder's process ID, start time, command,
and checkout. The system releases a slot when its holder exits or is killed,
so no stale slot outlives a run. Every run waits without a time limit, whether
interactive or unattended, and says which slot it took.

**Decision — 2026-11-24:** Waiting runs take free slots in the order they
began waiting, so a run is never passed over. Before, whichever waiter polled
first after a release won, and on 2026-11-24 one run waited 15 minutes
while four that began waiting later took slots ahead of it. A run that finds
no slot free, or earlier runs still waiting, holds the lock on a numbered
ticket in `~/.cache/podhaven/validation-queue/` until it takes a slot, so a
waiter that exits or is killed leaves the queue at once, and the next run to
look deletes its file. Only the oldest live waiter takes a free slot. A short
lock, `~/.cache/podhaven/validation-queue.lock`, guards the queue; nothing
waits for anything else while holding it. A waiting run polls at a short
interval and prints the holders and how many earlier runs wait ahead of it,
then each slot's new holder and its new place whenever they change.

A run from a checkout that predates the queue ignores it and can still take a
freed slot ahead of the queue, but every run takes a slot through the same
lock, so no slot ever has two holders.

A nested run reuses the slot it runs inside instead of waiting on itself. The
holder exports `PODHAVEN_VALIDATION_SLOT`, which names the slot's file and
holder process, because managed `bin/check` starts `bin/check-application`
without passing it any descriptor. A child reuses that slot only when the
slot's record names that process and the slot is still locked. So the tooling
phase of `bin/test-all` runs inside the run's own slot.

Runs take their slot before the My Mac test lock and never wait for a slot
while holding that lock, so a focused run and `bin/test-all` can't deadlock.
They also take it before an Xcode or SwiftPM build limit kept outside the
repository: nothing that holds such a build slot waits for a validation slot.
The limit uses only this repository's lock files, so it works the same on any
Mac.

#### Second Mac

**Decision — 2026-11-10:** `bin/test-all` sends a run to a second Mac whenever
that Mac's lane is free, not only when this Mac is busy, to take load off this
Mac, whose load comes from all its sessions. Runs there are somewhat slower,
which the owner accepted. The second Mac is the Mac mini that the private
jubishop/home-infra repository keeps as a test host; its `memory/mac-mini.md`
covers the host's toolchain, signing, and scheduled jobs.

The Git config value `podhaven.testHost` names the host as an SSH destination,
such as `mac-mini`. Set it in the primary checkout with
`git config podhaven.testHost mac-mini`, so every worktree shares it; the
repository is public, so the destination stays out of it. With no value set,
`bin/test-all` runs here as it always has.

A run can go to the second Mac only when its checkout is clean, since only a
commit can be sent there; with or without `--ensure` and `--revision`, that
covers the full runs before a push, merge, or release. A run over uncommitted
changes, one under `bin/with-my-mac-lock`, and focused runs stay here. So do
`--preflight`, `--verify`, and an `--ensure` run that reuses evidence, which
run no tests.

- **Choosing a lane:** a run takes the second Mac's lane when it is free,
  otherwise this Mac's when it is, and otherwise waits, saying who holds each,
  and takes whichever frees first. This Mac's lane is free when its My Mac test
  lock is and a [validation slot](#validation-slots) is free with no run
  waiting. The run prints which Mac it uses, and why when it stays here.
- **The lane:** the run pushes its commit, and the tip of origin's default
  branch, to a mirror on the host,
  `~/Library/Caches/podhaven/test-lanes/mirror.git`, and runs
  `bin/_test_lane_host.py` there over SSH. That checks the commit out in the
  lane's own worktree, `test-lanes/lane-1`, with every untracked and ignored
  file removed, so the run sees only the commit's files while the lane's
  fixed path keeps its DerivedData warm. The lane's `origin/HEAD` names this
  checkout's, so `bin/check`'s whitespace check reads the same changes there.
  It then runs that checkout's `bin/test-all` in the host's desktop session
  under `nice`, where signing works. The mirror keeps the newest `MIRROR_REFS` commits pushed to it, and
  the lane keeps only its latest run's files, so the host's disk use stays
  bounded.
- **Locks:** the lane holds the host's scheduled-jobs lock through
  `lockf -t 0`, so a held lock is a busy lane, and the host's own jobs, such
  as its Xcode updates and nightly test runs, can't start under a run. The
  host runs one test lane at a time, PodHaven's or Screenr's: on 2026-11-24 a
  PodHaven run beside a Screenr check didn't show a second lane safe, as
  home-infra's page records, and jubishop/home-infra#220 measures again. A run
  there holds no validation slot or My Mac test lock on this Mac. The host's
  `bin/test-all` takes that Mac's own, so the stalled-host sampling, the test
  host's temporary-directory check, and every other check run there as here.
- **Evidence:** the run's output streams back as it runs, with the host's
  evidence paths shown as this checkout's, and its logs, result bundles, and
  samples come back into this checkout's `.cache/test-all`. The `run.json`
  there records the run under `remote`, with the host and that run's own
  checkout state and toolchain. A run there passes only when it tested exactly
  this commit's files with this Mac's Xcode, Swift, and macOS, and its files
  match its report. This checkout must stay unchanged until the run ends, as
  for a run here. `--ensure` and `--verify` then reuse it like evidence from
  this Mac.
- **Falling back:** when the host is unreachable, has no one logged in at its
  desktop, refuses commands in its desktop session, runs another Xcode, Swift,
  or macOS than this Mac, or can't take the commit, the run stays here and
  says why. It also comes back here when the connection fails during the run,
  or the run ends without a report. A run there that failed only to sign,
  such as for a profile a new extension needs, asks the host to renew its
  signing, by creating the request file its renewal job watches, and runs
  here. Any other failure there fails the run, as it would here.
- **Long runs:** SSH keepalives end the client when the host stops answering,
  and the run writes a heartbeat to the session every `HEARTBEAT_SECONDS`.
  When the session's input ends or the heartbeat stops for
  `HEARTBEAT_TIMEOUT_SECONDS`, the host stops its run, and `lockf` then
  releases the lane, so a dropped connection never holds it.

## Sentry triage commands

Run `bin/snfeedback` to select unresolved user feedback, or `bin/snissue` to
select an unresolved issue that is not feedback. Both show the newest items
first, with activity within the last 365 days. They use `fzf` when installed
and a numbered prompt otherwise. With `--list`, they print the rows and exit
instead, which is how the analysis skills list them. With `--track
<reference>`, they print every issue tracking one item, canonical first, for
the analysis skills to start from; `bin/snissue --track` takes a numeric ID or
issue URL and needs no Sentry access. Both are fish scripts, so they require
fish. Listing requires authenticated `sentry` and `gh` commands plus `jq`;
analysis requires Claude Code (`claude`).

`bin/snissue` shows severity, available event and user counts, and the state
of the GitHub issue that tracks the Sentry issue. It accepts a Sentry issue
URL, a short ID such as `PODHAVEN-42`, or a numeric ID to skip the picker.
Selection launches Claude Code with `/analyze-sentry-issue` from the current
checkout root. `bin/snfeedback` does the same for feedback with
`/analyze-sentry-feedback`. Each skill reads its tracking issue's history,
diagnoses the item, recommends a fix, and uses `create-issue` to track
sanitized findings in GitHub without changing application code. It updates
the canonical issue only when the findings materially change.

The daily Sentry Intake GitHub workflow gives every unresolved item a tracking
issue. `bin/check-sentry-feedback` covers feedback and `bin/check-sentry-issues`
covers error issues. Each creates an intake issue with a body marker, its
label, and an instruction comment declaring its analysis skill as a
`fix-issue` prerequisite. When an error issue recurs after all its tracking
issues closed, the checker opens a recurrence intake issue that links them
instead of reopening shipped work. Feedback never recurs: each Sentry feedback
issue is one user's submission, and new feedback arrives under a new slug with
its own tracking issue. A feedback item's tracking issue, open or closed,
therefore stays its record for good, and the checker reports it as already
tracked. Both checkers share `bin/_sentry_intake.sh` and fail rather than
check a partial Sentry list. Each new intake issue starts at `p2`, and its
analysis skill then sets `p1`, `p2`, or `p3` from the findings; the checkers
never change the priority of an issue that already tracks an item.

| | Feedback | Error issues |
| --- | --- | --- |
| Label | `sentry-feedback` | `sentry-issue` |
| Body marker | `<!-- sentry-feedback:<slug> -->` | `<!-- sentry-issue:<numeric-id> -->` |
| Findings block | `analyze-sentry-feedback-findings` | `analyze-sentry-issue-findings` |

The pickers and checkers match an issue by its marker or a link to the Sentry
item; the pickers show it as intake, analyzed, closed, or untracked. Error issues
analyzed before the marker existed count as analyzed when their body has a
`## Sentry closeout` section. `bin/_sentry_issue_tracking.jq` holds the
error-issue rule for `bin/check-sentry-issues` and `bin/snissue`.

The controlled `bin/integration` probes behind the `bin/sentry-*-smoke`
commands report to the production Sentry project, so the smokes can verify
delivery end to end. Each probe tags its events `diagnostic-run`.
`bin/check-sentry-issues` and `bin/snissue` skip issues whose only events carry
that tag; an issue with any untagged event still gets intake. A new probe that
starts the Sentry SDK must set the tag, and a tooling test enforces it.

Both skills require the GitHub issue to include a Sentry record and closeout
instructions. Sentry drops events after its retention period and drops an
issue once they all age out; a recurrence then gets a new short ID, so later
triage finds the history by the record's signature. Once the work is done, an
agent resolves the linked Sentry item, in the fix's commit when there is one,
or archives an error accepted as noise, and reads back its status. For
PR-backed work, `fix-issue` carries that task into `Do After Merging` for the
`after-merge` agent to execute and verify after GitHub closure. For issue-only
work, the agent that finishes the work does it before closing the issue or
handing closure to a caller that owns it, because that caller may not touch
Sentry. Never delete a Sentry issue; its history goes with it.

## Checks and project extensions

**Decision — 2026-09-28:** Require the full local suite only for functionally
material changes. The user requested this to avoid full app runs for changes
that cannot affect functionality. Comments and formatting-only changes use
relevant syntax or formatting checks, including before push or merge. Since
2026-10-15, documentation is text under the
[foundation policy](foundation/engineering-policy.md#kinds-of-change), and
since 2026-11-05 it needs only `bin/check --documents-only` before it is
pushed.

Assess the complete change being delivered, not only the last commit. Changes
to application behavior, data or migrations, dependencies, executable tooling,
build or runtime configuration, tests, or release artifacts are functionally
material. A documentation commit does not exempt unvalidated functional work
in the same delivery. If the effect is uncertain, run the full suite. The
tradeoff is that non-functional deliveries do not produce fresh full-suite
evidence. Creating a versioned release or fresh archive still uses the
[release gate](releases.md#full-local-validation-gate).

Choose validation by the changed files and the stage of the work:

| Work | Check |
| --- | --- |
| Discussion, planning, or read-only inspection | No checks. |
| Documentation-only delivery | `bin/check --documents-only`. |
| Comments or formatting only | Relevant syntax or formatting checks; no full app suite. |
| Ordinary application changes | Focused Swift build and suite-level tests locally during development. |
| Tooling edits during development | Focused tooling tests and `bin/check`. |
| Initial setup; changes to foundation tools, hooks, configuration, tests, or CI | `bin/check --full` after the edits are complete. |
| A tooling PR ready for review | `bin/check --full` once for the final changes. |
| Pushing, merging, or releasing functionally material changes | `bin/test-all --ensure --revision <sha>` for the final clean revision, including integration with the latest `main` before a PR merge. |
| Focused checks leave material uncertainty | Full validation for the affected application or tooling. |

When full validation is required, pending, skipped, or failed runs do not
satisfy the gate. GitHub does not run test CI. Follow the
[current-revision procedure](#current-revision-swift-validation).

Batch related edits before checking. A conversational reply is not a release
gate. During development, reuse passing focused results while their relevant
inputs are unchanged. When required, the full gate needs evidence for the
final revision and integration base. Repeat a check when its inputs change or a failure
needs verification.

`bin/check --documents-only`, `bin/check`, and `bin/check --full` follow the
[shared check modes](foundation/engineering-policy.md#checks). Here,
`bin/check-application` lints what the foundation checks skip, then runs
every repository tooling test. ShellCheck lints every other shell script, such
as the Sentry helpers under `.agents`, and follows the files they source;
actionlint lints the GitHub workflows; and fish and Ruby check the syntax of
their scripts, including fastlane's. It then runs the suites in `bin/tests`
together, then each Python skill and helper suite under `.agents` on its own
through unittest, so a suite runs its tests even without a main block. It runs
every check and suite even after one fails. Keep the existing Swift build
and test requirements for application changes; documentation-only delivery
does not require building the Swift app.

`bin/test-all` includes the separate application and macro tests and
`bin/check --full --no-reuse`, which reruns the tooling tests, including the
skill tests and the shell tests in `bin/tests`, instead of reusing an earlier
pass.
`bin/check --full` alone is not a full test run.
`bin/tests` covers cache ownership and artifact repair; Project Starter tests
the knowledge tools. `bin/smoke-knowledge` checks real QMD retrieval and
linked-worktree isolation in disposable repositories. It reuses
`~/.cache/qmd/models` and does not publish changes.

Every tooling test suite, in `bin/tests` and `.agents`, imports
`bin/tests/service_guard.py`. It puts failing stand-ins for commands that
reach live services, such as `sentry`, `gh`, `fastlane`, `llm`, and
`xcodebuild`, ahead of `PATH`. A test that runs one fails, even when the
script under test ignores the failure, instead of acting on real accounts.
Fake every such command a script under test runs. A test that runs one on
purpose claims the blocked calls with `service_guard.take_blocked()`.
Run one suite with `python3 -B -m unittest discover -s bin/tests -p 'test_deploy.py'`,
which keeps the guard importable; a dotted `bin.tests` module name fails to
import it instead of running unguarded.

Tooling tests run fixture commands through `bin/tests/hang_guard.py`, with
`hang_guard.run`, or `start` and `finish` for a command the test talks to
while it runs, instead of choosing their own timeouts. Fixture commands start
many fake commands, each a fresh interpreter, so a loaded machine can slow a
run far past its usual time although nothing hangs. The shared `HANG_LIMIT`
therefore only stops a real hang, and machine load never decides a test's
outcome. Each command starts in its own session; on a timeout, the helper
kills that whole process group and waits for it to end, so the test reports
one `TimeoutExpired` and its temporary directory still cleans up. Keep a short
wait only where its expiry is the assertion. Give each subtest that runs a
release or gate command its own fixture, so one interrupted or failed run
can't fail the subtests after it.

`.project-starter.json` records the installed Project Starter release and the
hashes of its managed files. Update them with Project Starter's `bin/sync`.
PodHaven overrides no managed file: its Xcode preparation runs from the
project-owned `bin/setup-application`.

### Tooling pre-push gate

**Decision — 2026-11-06:** The pre-push hook enforces the tooling tests, so a
Project Starter sync or direct tooling push can't leave them failing on `main`
unnoticed. After the managed
[document checks](foundation/engineering-policy.md#pre-push-hook),
`bin/pre-push-application` runs `bin/check --full`, which includes the skill
and helper tests under `.agents`, on each pushed revision that changes tooling,
in a disposable linked worktree, and Git refuses the push when it fails or
cannot run. Uncommitted edits neither hide nor cause a failure.

Tooling is every path under `bin/` and `.agents/`, including pages, because
tooling tests read skill prose, and every other non-Markdown path outside the
application targets. Pushes that change only application targets or other
Markdown skip the gate; application changes reach `main` through pull requests
validated by `bin/test-all`. A new branch counts only its commits that no
remote-tracking branch holds.

The gate reuses a recent passing `bin/check --full` for the same tree, so
running `bin/check --full` on the final clean commit before pushing makes the
gate nearly instant. Rebasing changes the tree, so the gate runs the tooling
tests again, which takes several minutes.

**Decision — 2026-11-08:** Git opens an SSH connection and reads the remote's
refs before it runs the hook, then leaves that connection idle until the hook
finishes. GitHub can close it during a full run, so the push used to fail
after the checks passed, with exit status 141 and no other message. Smart
HTTPS remotes don't hold a connection across the hook. Two measures keep a
gated SSH push from failing that way:

- **Keepalive:** `bin/setup-application`, which `bin/setup`, `bin/prep-worktree`,
  and each new worktree run, sets the repository's `core.sshCommand` to
  `ssh -o ServerAliveInterval=30`. It leaves an SSH command that is already
  configured alone: `GIT_SSH_COMMAND`, `GIT_SSH`, or `core.sshCommand` in any
  scope.
- **Fallback:** when the gate runs the tooling tests in full for an SSH
  remote whose SSH command has no positive `ServerAliveInterval`, it lets
  them record their pass and then refuses the push, saying the checks passed
  and to push again. Git can still exit with status 141 after that message,
  because it writes to the closed connection as it disconnects. The retry
  reuses that pass at once. A keepalive set only in `~/.ssh/config` isn't
  detected, so such a push takes the retry.

## Scheduled memory audit

Home's nightly guidance review, `~/docs/guidance-review.md`, audits
PodHaven's [memory](../memory/README.md) notes against the code and GitHub
evidence when they come due, in place of Project Starter's weekly memory
audit, which 4.0.0 retired. That page covers when it runs, its model and
billing, how its changes land, and its failures.

It bills memory-note audits to `ANTHROPIC_MEMORY_AUDIT_API_KEY` in `~/.env`,
the key every adopter's memory-note audits share. The same line in the
primary checkout's `.env`, even with an empty value, would override the
shared key for PodHaven, so that file sets none. The
[model selection](../memory/memory-audit-model-selection.md) note records why.
