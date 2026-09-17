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
bin/check --full
```

Setup requires Git and Python 3.9 or later. Checks also require ShellCheck,
available through the operating system's package manager. Full tooling checks
also use Node.js 24, matching the Memory Audit workflow, to test the audit runner.
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

## Search

From the root, use `bin/knowledge`. Setup also creates a repository-local
`git knowledge` alias when that name is free, so the command works from any
subdirectory. An existing alias is preserved.

```sh
git knowledge search "worktree" -c docs
git knowledge query "how should decisions be recorded" --no-rerank
git knowledge get qmd://docs/development-workflow.md -l 80
git knowledge context list
```

Choose keyword search for names and known terms. Use a semantic query for
broader questions. Read a focused source page before relying on a result.
Source Markdown remains authoritative. Known-file reads and broader source
searches after a successful lookup with no matches remain appropriate. Follow
the [failure policy](#search-failures) when a configured lookup fails.

The command supplies QMD configuration, cache, and database paths only to
the QMD process. It does not change the shell's cache directory or depend on
personal shell wrappers. It refuses named indexes to keep checkout isolation.
If an executable must be selected explicitly, use an absolute local setting:

```sh
git config --local knowledge.qmdPath /absolute/path/to/qmd
```

The shared `.config/knowledge.json` defines Markdown collections, exclusions,
and short descriptions attached to search results. The helper renders an
ignored `.config/qmd/index.yml` with absolute paths. Change the shared JSON,
then refresh; direct QMD collection/context edits to the generated file will
be replaced. The starter supports `**/*.md` collection patterns.

## Optional home memory

Home notes are excluded by default. Opt in through local Git configuration:

```sh
git config --local knowledge.homeMemoryPath /absolute/path/to/personal/notes
bin/qmd-index
```

This setting is shared by linked worktrees but is not committed. Notes are
indexed locally, not copied into the project. Missing directories produce
a notice. To remove the collection:

```sh
git config --local --unset knowledge.homeMemoryPath
bin/qmd-index
```

## Refresh and recovery

`post-checkout`, `post-commit`, `post-merge`, and `post-rewrite` hooks request
background refreshes. The foreground command is:

```sh
bin/qmd-index
```

Git hooks do not run on every file save. Run this command after uncommitted
knowledge edits when current search results matter. It waits for the requested
refresh and returns its success or failure. Every knowledge lookup verifies
source, configuration, database presence, and successful refresh state before
returning results. Stale or unknown inputs trigger a coordinated refresh.
Refresh messages go to stderr so JSON output remains valid. Unchanged inputs
reuse the existing index and embeddings.

Automatic refresh waits up to 60 seconds. Set a positive local
`knowledge.searchRefreshTimeout` value in seconds when a project needs a
different bound. A timeout returns an error without results; the background
worker may still finish. Use `bin/doctor` and the foreground refresh to inspect
and recover. Explicit foreground refreshes can wait for larger indexing jobs.

Results are buffered until QMD succeeds and freshness is checked again. If
sources change during the lookup, discard the results and return an error.
This verifies indexed inputs and completed refresh state, not the semantic
quality of search results or the internal integrity of the SQLite database.

One worker serves each checkout. It hashes indexed Markdown and configuration,
including optional home notes, to skip unchanged inputs. Bursts of requests
share the worker. If inputs change during indexing, the worker runs another
pass. QMD itself handles incremental index and embedding updates. A failed
update does not start embedding. Git does not wait for indexing to finish.

Freshness includes the QMD release version, including prerelease and build
metadata. It excludes the optional Git commit suffix in `qmd --version`, which
can identify an unrelated surrounding repository. QMD subprocesses do not
inherit Git repository selectors from hooks. Diagnostics retain the full
reported version. After replacing a custom QMD build without changing its
release version, run `bin/qmd-index --force`.

Use `bin/qmd-index --force` to rebuild even when recorded inputs match.
Inspect `.cache/qmd/index.log` after failure. Logs rotate at approximately
1 MB on worker start, retaining one previous file. A stopped worker releases
its operating-system lock; rerun the foreground command to recover. Avoid
direct `qmd update` and `qmd embed`, which bypass this coordination.

### Search failures

When configured QMD fails, immediately tell the user what failed. Run
`bin/doctor`, inspect the refresh log, and attempt a focused repair. Verify
recovery by repeating the failed lookup successfully. Do not report success
from a command that returned an error, timed out, or discarded stale results.

If repair fails, pause knowledge-dependent work until the user explicitly
approves a fallback. Do not silently substitute `rg`, direct Markdown reads,
another index, or a different search tool to bypass the failure. Unrelated
work may continue when it does not depend on the missing knowledge.

A successful lookup with no matches is not a tool failure. Reading known
files and broadening that successful search remain allowed. A project may
deliberately operate without optional QMD, but its absence or failure does
not establish that decision; use an existing explicit project choice or ask
the user. Keep the Markdown source usable in that approved mode.

## Worktrees

After the repository has a commit:

```sh
git worktree add -b feature-name worktrees/feature-name
```

The first checkout prepares the worktree. `bin/prep-worktree` can repeat the
preparation. It discovers worktrees through Git, supports separate Git metadata,
and keeps databases under each checkout's `.cache/qmd/index.sqlite`. Preparation
records the verified primary path in local `knowledge.primaryWorktree` to
support Git layouts whose worktree listing exposes only the metadata path.
Rerun preparation in the primary checkout after moving it.

All projects and worktrees share model files at `~/.cache/qmd/models`.
This fixed path is independent of `XDG_CACHE_HOME`. Each checkout links its
`.cache/qmd/models` there; its index stays in `.cache/qmd/index.sqlite` inside
that checkout. Setup creates the shared directory. With QMD installed, initial
embedding downloads a missing embedding model there; query expansion and
reranking download their models on first use. Existing files are reused.

Setup and refresh migrate old caches. They verify file contents before removing
identical copies from a checkout-local directory. Conflicting filenames or
unexpected entries stop migration without deleting those files. Inspect the
reported paths before retrying. An old symlink is replaced, but its external
target is retained because other consumers may still need it. Remove redundant
external copies only after verifying their contents and redirecting all users.
Do not delete `~/.cache/qmd/models` when cleaning up a repository or worktree.

A linked worktree's `.envrc` is approved automatically only when its bytes
match a primary checkout file that direnv already reports as allowed.
Ordinary branch switches do not approve changed environment files. Bare
repositories have no primary environment file to inherit trust from.

After moving a checkout, use Git's worktree repair procedure if required,
then inspect `bin/doctor`. Run `bin/prep-worktree` to repair a broken model
link and restore the fixed shared cache. Existing indexes remain local.

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
`~/Library/LaunchAgents/com.jubi.podhaven.worktree-cleanup.plist`.

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

Scope build, formatter, static analysis, and test inputs to the active
checkout. Exclude nested worktrees, temporary copies, and unrelated generated
output explicitly. Include required generated inputs deliberately; Git ignore
rules alone do not control tool discovery.

Xcode's synchronized target folders define application sources, and
`bin/lint-swift-format` searches its declared production roots. Foundation
static checks use this checkout's Git file list; tooling tests are discovered
under `bin/tests`. Preserve these boundaries when extending the commands.

Keep mutable test data and build output separate between checkouts. Preserve
the supported package sharing and per-checkout DerivedData described above;
do not share mutable build output to save setup time.

When changing discovery or cache settings, verify that errors in intended
files remain detectable and invalid files in an unrelated checkout stay
excluded. Check fresh and warm caches after adding, changing, or removing a
nested checkout. Investigate stale results instead of adding broad exclusions.

## Existing hooks

Setup does not overwrite a different active `core.hooksPath` or bypass
executable hooks in the default Git hooks directory. The agent applying this
foundation must integrate with the existing manager's supported entry points.

Each of the four post-event hooks must call `bin/knowledge-hook`, passing the
event name and original arguments. For a shell-based post-commit hook, the
added call is:

```sh
repo_root=$(git rev-parse --show-toplevel) || exit 1
"$repo_root/bin/knowledge-hook" post-commit "$@"
```

Use the actual event name in each file. The helper does not read stdin, so
existing post-rewrite input remains available. Preserve the existing hook's
exit status, argument handling, order requirements, and normal behavior.
Place the call before an existing unconditional `exit`, or integrate it through
the manager's own configuration. Do not append code that can never execute.

After integration:

```sh
git config --local knowledge.hooks external
bin/setup
```

Verify each event in a disposable checkout appropriate to the project. Check
that both the existing hook behavior and knowledge refresh occur, including
post-rewrite stdin and nonzero existing-hook exit codes. `bin/doctor` reports
which forwarding events it has observed in this checkout and their timestamps.
Observations are evidence of past runs, not proof that a later hook edit works.

## Diagnostics

`bin/doctor` and `bin/doctor --json` inspect setup without approving environment
files, downloading models, or rebuilding an index. They report the hook path,
tools, collections, model locations, Xcode cache/cleanup state, last refresh result, and whether recorded
inputs are current, stale, unknown, or unavailable. An unavailable optional
tool is a notice. Broken required setup or an installed but failing tool makes
the command return a failure status with recovery instructions.

Freshness means the recorded input fingerprint matches and the index exists;
it is not an integrity scan of the SQLite database. If QMD reports database
errors despite a current fingerprint, use the foreground refresh and inspect
its log. Manually replacing the database requires a forced refresh.

## File organization

Keep each file focused on one responsibility or feature area. Every Swift
file must stay under 1000 lines, as required by [AGENTS.md](../AGENTS.md#coding-standards).
For other hand-written source and tests, approximately 1000 lines is a review
threshold. Generated and externally maintained files do not need arbitrary
splitting.

Extract cohesive areas with clear state ownership and readable call paths.
Do not compress formatting, create numbered fragments, or move unrelated
responsibilities into another large file to satisfy a count. Preserve the
Swift extension rules in AGENTS.md when splitting Swift types.

### Markdown pages

Keep each memory, documentation, or other hand-written Markdown page focused
on one topic or reader task. Before extending a long page, review its scope
and remove repetition. Split it when it mixes independent topics, a section
can be read and maintained on its own, or readers must scan unrelated material
to find what they need. Use those signals instead of line, word, or token limits.

Extract complete topics into descriptively named pages. Keep a short overview
and links in the original page, and update indexes and incoming file or heading
links. Keep each rule or decision in one authoritative place. Preserve its
reasons, evidence, dates, status, and enough context to understand it on its own.
Archive obsolete material according to the memory or docs lifecycle rules.

Keep README indexes and automatically loaded instructions concise; link to
detailed guidance instead of copying it. Headings help readers navigate a
coherent page, but do not resolve unrelated topics accumulating in one file.
Larger pages are acceptable when readers need the material together. Do not
compress prose, discard useful context, or create arbitrary numbered fragments
just to make a page shorter. Preserve generated and tool-managed record formats.

## Third-party dependencies

Prefer fewer third-party dependencies. Start with standard libraries, platform
APIs, and the smallest complete implementation the project can maintain.
Choose that approach when it meets the requirements at a reasonable cost.
A package is appropriate when its concrete benefits justify its maintenance
burden.

Compare complete solutions, including validation, edge cases, security,
upgrades, and additional packages brought in by a dependency. Initial
implementation convenience alone is not enough. Apply this preference through
ordinary technical judgment; it does not introduce a separate approval step
or require replacement of existing packages.

## Test-driven development

Every regression fix and functional change requires an automated test that
fails before implementation and passes afterward. Use this sequence:

1. Add or update a focused test. Confirm it fails for the expected behavior.
   A setup failure or a run that executes no tests does not establish this.
2. Implement the change and confirm the focused test passes.
3. Refactor if needed, then run the checks required for the affected behavior.

A test that passes before and after does not prove the changed behavior.
Documentation-only edits need document checks, not new behavior tests.

Test user-visible outcomes, public interfaces, and external interactions.
Place fakes at OS, network, storage, and service boundaries so our own logic
runs. Do not test private structure or add production APIs only for tests.
Preserve PodHaven's Swift Testing fixtures and suite-level filters from
[AGENTS.md](../AGENTS.md#testing); use focused `unittest` runs for tooling.

### Test cost and coverage

Prepare unrelated prerequisites with isolated fixtures or existing public
interfaces. Use the least costly test level that proves the behavior. Retain
complete journeys and tests that depend on the actual interaction surface.
When moving a repeated case to a cheaper test, preserve its evidence.

Measure representative runs before and after test optimizations. Compare
the same environment, test inventory, setup costs, and total time. Report
failed and retried runs separately. Do not remove coverage to improve timing.

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
For color assertions, set the host's color scheme and active-appearance traits
so macOS window focus does not dim the controls being measured.

### Current-revision Swift validation

Follow the [testing policy](../AGENTS.md#testing) before pushing any branch,
merging into `main`, or releasing. This includes documentation and tooling
changes. For a PR merge, integrate its current head with the latest `main`
before validation and verify the merge will contain the tested tree.

For the final clean revision, run:

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
`PodHaven` test plan on My Mac (Designed for iPhone). My Mac also runs hosted
UI and accessibility tests that the iOS Simulator skips. Use additional
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
Privacy & Security → Accessibility. The wrapper connects only to the PodHaven
test host through a temporary, token-protected loopback endpoint to initialize
inspection. Hosted control tests dispatch UIKit primary actions or activate
SwiftUI accessibility elements inside the test's dependency context. Direct
`Cmd+U` runs do not start this client. The wrapper also clears inherited
`SDKROOT` so Xcode selects the SDK for the requested destination.

Each attempt retains logs, its `.xcresult` bundle, diagnostic reports, and
`run.json` under `.cache/test-all/`. The report records the revision, local
changes, toolchain, destination, and outcome. The command permits uncommitted
development work but rejects a checkout that changes during the run. Before
pushing any branch, merging into `main`, or releasing, require a passing report
for the final clean revision. Do not treat an earlier dirty-worktree run as acceptance of a new
commit. Keep the evidence until the operation is complete.

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
Intentional application warning/error logs from error-path tests remain
available and are distinct from compiler and framework diagnostics.

## Checks and project extensions

Choose validation by the changed files and the stage of the work:

| Work | Check |
| --- | --- |
| Discussion, planning, or read-only inspection | No checks. |
| A batch of Markdown edits | `bin/check --documents-only`. |
| Ordinary application changes | Focused Swift build and suite-level tests locally during development. |
| Tooling edits during development | Focused tooling tests and `bin/check`. |
| Initial setup; changes to foundation tools, hooks, configuration, tests, or CI | `bin/check --full` after the edits are complete. |
| A tooling PR ready for review | `bin/check --full` once for the final changes. |
| Pushing any branch, merging into `main`, or releasing | `bin/test-all --ensure --revision <sha>` for the final clean revision, including integration with the latest `main` before a PR merge. |
| Focused checks leave material uncertainty | Full validation for the affected application or tooling. |

Require successful full local validation before pushing any branch, merging
into `main`, or releasing. Pending, skipped, or failed runs do not satisfy
the gate. Preserve the release validation in [Versioning and releases](releases.md).

Batch related edits before checking. A conversational reply is not a release
gate. During development, reuse passing focused results while their relevant
inputs are unchanged. The full gate requires evidence for the final revision
and integration base. Repeat a check when its inputs change or a failure
needs verification.

`bin/check --documents-only` validates the documented frontmatter subset,
index coverage, local file links, and ordinary heading anchors.
`bin/check` adds Python syntax checks for the tools and tests, shell checks
(Bash for `.envrc`, POSIX shell for the bundled hooks), and Git whitespace
checks. It does not run the disposable-repository tests.
Both routine modes skip application typechecking, lint, tests, builds, and
package-manager startup. Run relevant Swift checks explicitly during app work.

`bin/check --full` adds all repository tooling tests in `bin/tests`. They use
disposable repositories and simulated QMD/direnv, with no model downloads or
network access. Remote URLs are not fetched by foundation checks.

All modes also verify the generated active-memory index. Keep the
existing Swift build and test requirements for application changes.
A Markdown or tooling edit does not require building the Swift app during
development. The full gate still applies before pushing any branch, merging
into `main`, or releasing.

Keep the foundation checks when adding application tests, builds, and linters.
For generated or externally owned docs, add deliberate patterns to
`checks.exclude` in `.config/knowledge.json`. Avoid broad exclusions that hide
hand-written project knowledge.

`bin/test-all` includes `bin/check --full` and the separate application,
macro, skill, and shell tests. `bin/check --full` alone is not a full test run.
`bin/tests` covers the knowledge worker, cache ownership and artifact
repair, and audit publication gates. `bin/smoke-knowledge`
checks real QMD retrieval and linked-worktree isolation in disposable repositories.
It reuses `~/.cache/qmd/models` and does not publish changes.

## Scheduled memory audit

The audit uses `deepseek/deepseek-v4.1-flash` through OpenRouter. It requests
medium reasoning and uses a $0.50 run cost guard. The guard is checked after each
response, so the final request can take spending above that threshold.
It remains semantic curation:
it verifies claims against repository and captured GitHub evidence.

CI installs and verifies ripgrep for repository searches before making model
requests. It renders `.config/knowledge.json` with `bin/knowledge-config --ci`
into its own keyword-only index. It does not include local personal notes or run QMD
embedding/model downloads. Legacy Sentry history stays outside default search.
The model can edit existing ordinary active notes or archive them. The runner
uses Git moves so the exported patch includes archive destinations and any later
edits to those files. The model cannot edit README policy, existing archives,
or tool-managed ledgers. The publisher
checks patch scope, regenerates only the active-index marker section, then
validates metadata, index coverage, and local links before opening a PR.

Use `PUBLISH_CHANGES=false` with `bin/finalize-memory-audit` only in a clean,
disposable fixture when testing an audit patch. The publisher expects the model
result in `artifacts/openrouter-final.md` and applies it to that fixture.

`.project-starter.json` records the copied release and tested QMD version.
Compare future releases manually and merge relevant improvements. These files
belong to the project; there is no automatic updater or runtime dependency on
the starter repository. Retain `LICENSE.project-starter` with copied material.
