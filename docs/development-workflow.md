---
status: current
---

# Development workflow

This repository keeps knowledge as Markdown and uses optional QMD search.
Each checkout has its own index. Git hooks refresh it in the background.

## First setup

Install td and run `td init` in the primary checkout as described in the
[task workflow](foundation/task-tracking.md). This is separate from knowledge setup below.

Run from the repository root:

```sh
bin/setup
bin/install-cleanup-agent  # macOS, primary checkout only
bin/doctor
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

Inspect candidates with `bin/prune-worktree-caches --dry-run`. Use `bin/doctor`
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

`bin/doctor` also reports Xcode cache and cleanup state; see
[diagnostics](foundation/knowledge-search.md#diagnostics).

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
Keep views installed and preserve their rendered and accessibility assertions.

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

My Mac also runs hosted UI and accessibility tests that the iOS Simulator skips. Use additional
simulator checks when a change needs environment-specific coverage. Development
checks use local targets; physical-device testing belongs to separate release
workflows and must respect the [device restriction](../AGENTS.md#repo-guardrails).
The local run is the test gate; GitHub does not run test CI.

For focused application tests, use My Mac by default with
`-destination 'platform=macOS,name=My Mac'`. Select a complete suite/class with
`-only-testing:PodHavenTests/SomeSuite`; method filters can report success while
running zero tests.

On macOS 27, hosted SwiftUI tests need a native accessibility client to expose
controls. `bin/test-all` starts it through `bin/with-test-accessibility`. Use
`bin/with-test-accessibility xcodebuild test ...` for focused runs too. Grant
Accessibility access to the terminal or app running tests in System Settings →
Privacy & Security → Device Control and Data Access (the macOS 27 name for
Accessibility permissions). The wrapper connects only to the PodHaven test
host through a temporary, token-protected loopback endpoint to initialize
inspection. Hosted control tests dispatch UIKit primary actions or activate
SwiftUI accessibility elements inside the test's dependency context. Direct
`Cmd+U` runs do not start this client. The wrapper also clears inherited
`SDKROOT` so Xcode selects the SDK for the requested destination.

Run `bin/test-all --preflight` from the terminal or app that will launch the
tests to check the toolchain and Accessibility access without running tests.
The full suite also checks access before any test suite starts. When access
is missing, the wrapper requests the macOS permission prompt and stops.
Enable the app named by macOS, then rerun the preflight from that same app.
If access is already enabled but the check fails, quit and reopen that app
and check again. Release commands run this preflight too.

My Mac code coverage also needs access to the PodHaven app's data. In System
Settings → Privacy & Security → Files & Folders, expand the terminal or app
running tests and enable PodHaven. If this access is denied, tests can pass
while Xcode cannot collect coverage files; the diagnostic check rejects that
run's warnings.

Each attempt retains logs, its `.xcresult` bundle, diagnostic reports, and
`run.json` under `.cache/test-all/`. The report records the revision, local
changes, toolchain, destination, and outcome. The command permits uncommitted
development work but rejects a checkout that changes during the run. When
full validation is required, retain a passing report for the final clean
revision through the push, merge, or release. An earlier dirty-worktree run
does not establish acceptance of that commit.

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

## Sentry triage commands

Run `bin/snfeedback` to select unresolved user feedback, or `bin/snissue` to
select an unresolved issue that is not feedback. Both show the newest items
first, with activity within the last 365 days. They use `fzf` when installed
and a numbered prompt otherwise. Listing requires authenticated `sentry` and
`gh` commands plus `jq`; analysis requires Claude Code (`claude`).

`bin/snissue` shows severity, available event and user counts, and the state
of a GitHub issue whose title or body references the Sentry issue. It accepts
a Sentry issue URL, a short ID such as `PODHAVEN-42`, or a numeric ID to skip
the picker. Selection launches Claude Code with `/analyze-sentry-issue` from
the current checkout root. That skill diagnoses the issue and recommends a fix,
then uses `create-issue` to track sanitized findings in GitHub without changing
application code. Existing issues are reused when they already own the work.

`bin/snfeedback` launches Claude Code with `/analyze-sentry-feedback`, which
also uses `create-issue`. It preserves the feedback tracking markers and
updates its canonical GitHub issue only when the findings materially change.

Both skills require the GitHub issue to include Sentry closeout instructions.
After GitHub closure, the closing agent resolves the linked Sentry item and
reads back its resolved status. For PR-backed work, `issuefix` carries that
task into `Do After Merging` for the `after-merge` agent to execute and verify.

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

`bin/test-all` includes `bin/check --full` and the separate application,
macro, skill, and shell tests. `bin/check --full` alone is not a full test run.
`bin/tests` covers the knowledge worker, cache ownership and artifact repair,
and audit validation gates. `bin/smoke-knowledge` checks real QMD retrieval and
linked-worktree isolation in disposable repositories. It reuses
`~/.cache/qmd/models` and does not publish changes.

`.project-starter.json` records the installed Project Starter release, the
hashes of its managed files, and this project's overrides of `bin/_knowledge.py`
and `bin/_checks.py`. Update them with Project Starter's `bin/sync`, and merge
upstream changes into the overridden helpers by hand.

## Scheduled memory audit

Run `bin/memory-audit install` on macOS to register the weekly launchd job.
It runs on Saturday at 06:00 in the Mac's local time zone (Pacific on the
maintainer's machine). A sleeping Mac runs a missed calendar job after wake;
the user must be logged in. The LaunchAgent is
`~/Library/LaunchAgents/com.jubishop.podhaven.memory-audit.plist`.
Like the cleanup agent, it starts uv's default `~/.local/bin/python3` through
`/bin/sh`, so it follows Python updates; the installer refuses until `uv python install --default`
has created that interpreter. Tools under an fnm Node version are scheduled
through fnm's default alias, so Node updates do not need a reinstall. Reinstall
after moving the checkout or changing other tool locations. The installer
resolves runtime directories and checks that QMD starts with the scheduled PATH.
Installation does not run an audit immediately.

The job uses `claude -p` with `claude-haiku-5-5`, high effort, and the saved
Claude subscription login. It refuses API-key or third-party provider login
and excludes API keys from its environment. Subscription limits and any
purchased usage apply. There are no OpenRouter requests. Restricted mode
excludes user and project Claude settings and instruction files, so personal
permissions, MCP servers, and hooks do not become part of the scheduled audit. The Sentry Feedback GitHub workflow remains
independent and uses no model.

Each run fetches `origin/main` and audits that exact revision in an isolated
local clone under `.cache/memory-audit/runs/`. The run deletes the clone when it
finishes and keeps its context, report, patch, and logs in the run folder.
Uncommitted working files are not audited or modified. GitHub issues and PRs are fetched in two bounded collections
with up to 1,000 entries each. The model uses that captured evidence and a
separate keyword-only QMD index; it makes no network requests or QMD model
downloads. Missing older GitHub items must be recorded as evidence gaps. The
runner also lists the commits since the last successful audit, so the model
needs no `git log`. Unchanged repository, GitHub, and audit inputs skip the
model call, except right after a failed or interrupted run. A lock prevents
overlapping local runs. Model attempts share a 90-minute execution limit.

Claude has only Bash, read, and search tools, and no session is saved. Writes,
network commands, and reads outside the clone need approval, which the job
denies automatically. Only `jq` and `qmd search` are explicitly allowed, beyond
Claude Code's built-in read-only commands. It returns structured findings and
complete proposed note contents. The runner requires one finding per active note, permits
only updates to existing active notes or archival moves, and prevents overwriting
existing archives. From the session log, it also requires that the model read
every active note with the Read tool and made at least one source or evidence
lookup per note. On 2026-10-10 a run had kept all 16 notes in 32 seconds
without reading any. It regenerates the README's active-note list and validates
metadata, index coverage, and local links before exporting a patch. README
policy and tool-managed ledgers cannot be edited by the model.

When every check passes and the proposal changes notes, the runner commits the
change in the isolated clone and pushes it to `main` on GitHub, using the
checkout's Git identity. The owner chose direct commits on
2026-10-15: memory is text, and the commit is easy to revert. If
`main` moved during the audit, the commit is rebased onto it, unless the move
changed `memory/`; then the run fails and the next run audits the new notes.
The user's checkout is never touched; pull to see the change.

A failed run shows a macOS notification and opens a public GitHub issue titled
`Memory audit failing`, or comments on the open one, with the error and the
run's directory name. The next successful run closes it. A run that changes
nothing stays silent.

When proposal validation fails, the runner restores the original notes and gives
Claude one repair attempt with the rejected response and exact error. A second
invalid response fails the run. An archive that would break links in immutable
archives, ledgers, or docs must instead remain active. Rejected output and the
first attempt's logs are retained alongside the final attempt.

Run and inspect an audit:

```sh
bin/memory-audit run
bin/memory-audit run --force
cat .cache/memory-audit/latest.json
launchctl print gui/$(id -u)/com.jubishop.podhaven.memory-audit
```

`latest.json` records success, failure, or a skipped run and its directory.
Successful run directories contain `memory-audit-report.md`,
`memory-audit.patch`, and the proposed `repository/` checkout. All attempts keep
`run-meta.json`; model attempts also keep `events.jsonl`, `claude.log`, and the
structured result when available. A failure never updates `last-success.json`.
Logs stay local and ignored by Git; `latest.json` and `last-success.json`
record any `publishedCommit`. Each run deletes run directories older than 60
days, except those the state files name.

To stop the local schedule:

```sh
launchctl bootout gui/$(id -u)/com.jubishop.podhaven.memory-audit
```

Remove its plist to keep it from loading at the next login. The retired GitHub
Memory Audit workflow must remain disabled until its deletion is merged.

`.project-starter.json` records the copied release and tested QMD version.
Compare future releases manually and merge relevant improvements. These files
belong to the project; there is no automatic updater or runtime dependency on
the starter repository. Retain `LICENSE.project-starter` with copied material.
