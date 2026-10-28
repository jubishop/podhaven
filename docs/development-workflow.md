---
status: current
---

# Development workflow

This repository keeps knowledge as Markdown and uses optional QMD search.
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

Setup requires Git and Python 3.9 or later. Checks also require ShellCheck,
available through the operating system's package manager. The local memory
audit also requires Claude Code, GitHub CLI, QMD, ripgrep, and QMD's Node.js or Bun runtime.
Its tests use fake services and do not make model requests.
QMD and direnv are optional. Missing optional tools produce clear notices; an installed but
failing QMD returns an error. Install QMD using its
[official instructions](https://github.com/tobi/qmd#installation).
The starter records its tested QMD version in `.project-starter.json`.

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
The app retains its existing iOS 26 deployment target. The macro package
also declares its minimum Swift tools version in `PodHavenMacros/Package.swift`.
Keep development, CI, and release tools compatible with these requirements.
Use the existing manifests and setup mechanisms instead of adding conflicting
version declarations.

Swift Collections uses release 1.6.0. Its development branch introduced a
Swift runtime symbol that prevented the app from launching on OS 26. Keep
dependency runtime requirements compatible with the app's deployment target.

When changing application commands, reject unsupported toolchains before
installation, tests, builds, or release work. Report the detected version,
the supported versions, and how to select a compatible toolchain. Check the
selected tools with `xcodebuild -hideShellScriptEnvironment -version` and
`xcrun swift --version`. Use `DEVELOPER_DIR` to select a different installed
Xcode for a command.

Prefer maintained releases and coordinate upgrades across development, CI,
and deployment after dependency and behavior checks. Review automatic version
selectors when changing the supported major versions; do not silently widen
that policy. Document and foundation checks must remain independent of Xcode
and Swift because they do not use those tools.

## Worktrees

Shared worktree, model, and recovery rules are in
[knowledge search](foundation/knowledge-search.md#worktrees-and-models).

Use `ghdw <name>` for normal removal. It verifies the merge lifecycle before
removing a worktree, then calls this repository's `bin/post-worktree-remove`.
`ghm` gets the same cleanup because it uses `ghdw`. Direct Git removals are
covered by the next preparation or hourly sweep.

## Xcode caches and automatic cleanup

`bin/setup-application` prepares Xcode caches. `bin/setup`, `bin/prep-worktree`,
and the Git hook that sets up each new worktree all run it.

Each checkout gets private DerivedData at Xcode's default path. Its
`SourcePackages` link points to the shared `~/Library/Developer/SharedSourcePackages/PodHaven`
folder. Preparation copies missing per-user workspace settings from the primary
checkout and preserves existing settings. It does not start a warm-up build.
Independent package directories are preserved for inspection.

`bin/install-cleanup-agent` installs an idempotent macOS LaunchAgent from the
primary checkout. It runs at login/load and once each hour while the user is
logged in. Cleanup also runs during `bin/prep-worktree` and after `ghdw` removal.
There is no routine maintenance command to remember. Reinstall the agent after
moving the primary checkout. Its plist is
`~/Library/LaunchAgents/com.jubi.podhaven.worktree-cleanup.plist`. The agent
starts uv's default `~/.local/bin/python3` through `/bin/sh`, so it follows
Python updates without a reinstall: macOS pins a login item to its program's
signature, which Apple's shell keeps and each new interpreter changes. The
installer refuses to write the agent until
`uv python install --default` has created that interpreter.

Cleanup only removes a DerivedData folder when its plist and path hash identify
an absent checkout owned by this clone. Registered worktrees, existing checkout
directories, unrelated caches, and independent package caches are preserved.
Preparation and cleanup share a filesystem lock. Build-process and open-file
checks also guard deletion; Xcode does not take our lock. Ambiguous activity
causes deferral and a later automatic retry.

Before deletion, cleanup checks shared SwiftPM artifact paths. A path through
an orphan's `SourcePackages` link is replaced with its verified, existing shared
target. Repair requires Xcode and package users to be closed. Unverifiable
references defer cleanup. Shared packages and QMD model weights are retained.

Inspect candidates with `bin/prune-worktree-caches --dry-run`. Use `bin/doctor-xcode`
to read the latest removal totals, deferred reasons, errors, package-link health,
and hourly job state. The latest report replaces its predecessor under the
common Git directory's `knowledge/xcode/cleanup.json`; fatal errors use a single
`.cache/worktree-cleanup/last-error.json`. Hourly output does not accumulate logs.
Caches with no trustworthy ownership metadata require manual investigation.

If Xcode uses custom cache locations, set absolute local Git values before setup:
`knowledge.xcodeDerivedDataPath` and `knowledge.xcodePackagesPath`. The shared
package location must stay outside DerivedData. These overrides also support
isolated integration tests; they do not change Xcode's own preferences.

### Validation checkout isolation

Shared rules are in [checkout isolation](foundation/engineering-policy.md#validation-checkout-isolation).
Xcode's synchronized target folders define application sources, and
`bin/lint-swift-format` searches its declared production roots. Foundation
static checks use this checkout's Git file list; tooling tests are discovered
under `bin/tests`. Preserve these boundaries when extending the commands.

Keep mutable test data and build output separate between checkouts. Preserve
the supported package sharing and per-checkout DerivedData described above;
do not share mutable build output to save setup time.

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
a clean checkout at that revision. It reuses the latest retained passing report
only when the revision, checkout contents, toolchain, macOS version, destination,
and evidence artifacts still match. Otherwise, it runs the complete suite. A new commit or
change to the integration base requires a fresh full run.
`bin/test-all --verify --revision <sha>` checks existing evidence without running
tests and fails when it cannot reuse that evidence. Plain `bin/test-all` always
runs the complete suite and also supports uncommitted development work.

`bin/test-all` runs repository checks, Python skill and helper tests, shell
tooling tests, Swift formatting checks, macro tests, and the complete
`PodHaven` test plan on My Mac (Designed for iPhone). The large Siri catalog
timing suite runs in a separate, required phase after the other app tests.
Its five-second budgets therefore exclude contention from unrelated tests.
Both phases must pass with zero skipped tests and validated diagnostics;
their logs and result bundles are retained in the same evidence directory.

My Mac also runs hosted UI tests that the iOS Simulator skips. Use additional
simulator checks when a change needs environment-specific coverage. Development
checks use local targets; physical-device testing belongs to separate release
workflows and must respect the [device restriction](../AGENTS.md#repo-guardrails).
The local run is the test gate; GitHub does not run test CI.

For focused application tests, use My Mac by default with
`-destination 'platform=macOS,name=My Mac'`. Select a complete suite/class with
`-only-testing:PodHavenTests/SomeSuite`; method filters can report success while
running zero tests.

Run focused tests with `bin/with-my-mac-lock env -u SDKROOT xcodebuild test ...`
so they take the [My Mac test lock](#my-mac-test-lock) and Xcode selects the
SDK for the requested destination; `bin/test-all` takes the lock and clears
inherited `SDKROOT` itself.

Run `bin/test-all --preflight` to check the Xcode, Swift, and macOS versions
without running tests. Release commands run this preflight too.

My Mac code coverage also needs access to the PodHaven app's data. In System
Settings → Privacy & Security → Files & Folders, expand the terminal or app
running tests and enable PodHaven. If this access is denied, tests can pass
while Xcode cannot collect coverage files; the diagnostic check rejects that
run's warnings.

Each attempt retains logs, its `.xcresult` bundle, diagnostic reports, and
`run.json` under `.cache/test-all/`. The report records the revision, local
changes, toolchain, destination, and outcome. A new attempt keeps only the
newest evidence directories, up to `RETAINED_RUNS` in `bin/test-all` (five,
counting itself), and removes older ones. That bound always keeps the newest
earlier run, which reuse and comparison need, and leaves other entries alone.
The command permits uncommitted development work but rejects a checkout that
changes during the run. When full validation is required, retain a passing
report for the final clean revision through the push, merge, or release. An
earlier dirty-worktree run does not establish acceptance of that commit.

The command runs automated tests with isolated service fixtures. Live Sentry
smoke tests in `.agents/scripts/sentry-cli/test_sentry_skills.sh` and real QMD
smoke tests remain separate because they need external credentials, current
service data, or installed models. Run the relevant smoke tests when those
integrations change; they do not replace the automated suite.

Retain the `.xcresult` bundle and raw `xcodebuild` log for local runs.
Pass `-hideShellScriptEnvironment` and `LM_FORCE_LINK_GENERATION=YES` to test
builds. The latter runs App Intents extraction even when a dynamic package's
dependency file does not list App Intents. It confirms that there are no
relevant symbols instead of emitting a skipped-extraction warning; it does
not suppress warnings or bypass metadata validation.

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

## Sentry triage commands

Run `bin/snfeedback` to select unresolved user feedback, or `bin/snissue` to
select an unresolved issue that is not feedback. Both show the newest items
first, with activity within the last 365 days. They use `fzf` when installed
and a numbered prompt otherwise. Listing requires authenticated `sentry` and
`gh` commands plus `jq`; analysis requires Claude Code (`claude`).

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
instead of reopening shipped work.

| | Feedback | Error issues |
| --- | --- | --- |
| Label | `sentry-feedback` | `sentry-issue` |
| Body marker | `<!-- sentry-feedback:<slug> -->` | `<!-- sentry-issue:<numeric-id> -->` |
| Findings block | `analyze-sentry-feedback-findings` | `analyze-sentry-issue-findings` |

The pickers and checkers match an issue by its marker or a link to the Sentry
item; the pickers show it as intake, analyzed, closed, or untracked. Error issues
analyzed before the marker existed count as analyzed when their body has a
`## Sentry closeout` section.

Both skills require the GitHub issue to include a Sentry record and closeout
instructions. Sentry drops events after its retention period and drops an
issue once they all age out; a recurrence then gets a new short ID, so later
triage finds the history by the record's signature. After GitHub closure, the
closing agent resolves the linked Sentry item, in the fix's commit when there
is one, or archives an error accepted as noise, and reads back its status.
For PR-backed work, `fix-issue` carries that task into `Do After Merging` for
the `after-merge` agent to execute and verify. Never delete a Sentry issue;
its history goes with it.

## Checks and project extensions

**Decision — 2026-09-28:** Require the full local suite only for functionally
material changes. The user requested this to avoid full app runs for changes
that cannot affect functionality. Comments and formatting-only changes use
relevant syntax or formatting checks, including before push or merge. Since
2026-10-15, documentation needs no checks, as text under the
[foundation policy](foundation/engineering-policy.md#kinds-of-change).

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
| Documentation-only delivery | No checks. |
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
`bin/check-application` runs all repository tooling tests in `bin/tests`, and
every mode also verifies the generated active-memory index. Keep the existing
Swift build and test requirements for application changes; documentation-only
delivery does not require building the Swift app.

`bin/test-all` includes the separate application, macro, and skill tests and
`bin/check --full --no-reuse`, which reruns the tooling tests, including the
shell tests in `bin/tests`, instead of reusing an earlier pass.
`bin/check --full` alone is not a full test run.
`bin/tests` covers the knowledge worker and cache ownership and artifact
repair; Project Starter tests the shared memory audit. `bin/smoke-knowledge` checks real QMD retrieval and
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

`.project-starter.json` records the installed Project Starter release, the
hashes of its managed files, and the enabled `memory-audit` feature. Update
them with Project Starter's `bin/sync`. PodHaven overrides no managed file:
its Xcode preparation runs from the project-owned `bin/setup-application`.

## Scheduled memory audit

A weekly local job checks every active [memory](../memory/README.md) note
against the code and GitHub evidence, archives or updates stale notes, and
commits validated changes to `main`. It is Project Starter's shared
[memory audit](foundation/memory-audit.md) feature, whose page covers
installing, running, inspecting, and stopping it, and its model, validation,
and failure handling. PodHaven's `memoryAudit` settings in
`.config/knowledge.json` add:

- **Schedule:** the default Saturday at 06:00 in the Mac's local time zone.
  Audits on the same Mac take turns through the feature's shared lock.
- **Failure issue:** a new `Memory audit failing` issue gets the
  `memory-audit-failure` label.
- **Index:** archiving a note removes its entry from the README's
  "Active notes" list.
- **Context:** the prompt records that this subscription-backed Claude Code
  job replaced the paid OpenRouter audit and the later Codex job, and that the
  Sentry Intake GitHub workflow, which uses no model, stays in use.

Run `bin/memory-audit install` in the primary checkout to register or update
the LaunchAgent, and
`launchctl print gui/$(id -u)/com.jubishop.podhaven.memory-audit` to inspect
it.
