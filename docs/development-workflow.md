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
available through the operating system's package manager. QMD and direnv are
optional. Missing optional tools produce clear notices; an installed but
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
Source Markdown remains authoritative when search is unavailable or stale.

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
refresh and returns its success or failure. Search warns when its recorded
inputs are stale or unknown.

One worker serves each checkout. It hashes indexed Markdown and configuration,
including optional home notes, to skip unchanged inputs. Bursts of requests
share the worker. If inputs change during indexing, the worker runs another
pass. QMD itself handles incremental index and embedding updates. A failed
update does not start embedding. Git does not wait for indexing to finish.

Use `bin/qmd-index --force` to rebuild even when recorded inputs match.
Inspect `.cache/qmd/index.log` after failure. Logs rotate at approximately
1 MB on worker start, retaining one previous file. A stopped worker releases
its operating-system lock; rerun the foreground command to recover. Avoid
direct `qmd update` and `qmd embed`, which bypass this coordination.

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

New model caches use the common Git directory's `knowledge/models` folder.
Each checkout links its `.cache/qmd/models` to that shared location. An existing
primary model cache is preserved and shared with new worktrees. Existing
worktree model caches are preserved, even if they are independent.

A linked worktree's `.envrc` is approved automatically only when its bytes
match a primary checkout file that direnv already reports as allowed.
Ordinary branch switches do not approve changed environment files. Bare
repositories have no primary environment file to inherit trust from.

After moving a checkout, use Git's worktree repair procedure if required,
then inspect `bin/doctor`. A broken pre-existing model link is preserved for
inspection. Once you have confirmed it is only a broken link, remove that
link and rerun `bin/prep-worktree`; do not delete a directory of model files.

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

## Checks and project extensions

Choose validation by the changed files and the stage of the work:

| Work | Check |
| --- | --- |
| Discussion, planning, or read-only inspection | No checks. |
| A batch of Markdown edits | `bin/check --documents-only`. |
| Tooling edits during development | Focused tooling tests and `bin/check`. |
| Initial setup; changes to foundation tools, hooks, configuration, tests, or CI | `bin/check --full` after the edits are complete. |
| A tooling PR or release ready for delivery | `bin/check --full` once for the final changes. |

Batch related edits before checking. A conversational reply is not a release
gate. Reuse a passing result while its relevant source, configuration, and
dependencies are unchanged. Repeat a check when those inputs change or a
failure needs verification. CI always runs the full check.

`bin/check --documents-only` validates the documented frontmatter subset,
index coverage, local file links, and ordinary heading anchors.
`bin/check` adds Python syntax checks for the tools and tests, shell checks
(Bash for `.envrc`, POSIX shell for the bundled hooks), and Git whitespace
checks. It does not run the disposable-repository tests.

`bin/check --full` adds all repository tooling tests in `bin/tests`. They use
disposable repositories and simulated QMD/direnv, with no model downloads or
network access. Remote URLs are not fetched by foundation checks.

All modes also verify the generated active-memory index. Keep the
existing Swift build and test requirements for application changes.
A Markdown or tooling edit does not require building the Swift app.

Keep the foundation checks when adding application tests, builds, and linters.
For generated or externally owned docs, add deliberate patterns to
`checks.exclude` in `.config/knowledge.json`. Avoid broad exclusions that hide
hand-written project knowledge.

The Python Tests workflow runs `bin/check --full` in addition to the existing skill
tests. `bin/tests` covers the knowledge worker, cache ownership and artifact
repair, and audit publication gates. `bin/smoke-knowledge --models <existing-model-directory>`
checks real QMD retrieval and linked-worktree isolation in disposable repositories.
It reuses existing models and does not publish changes.

## Scheduled memory audit

The audit uses `deepseek/deepseek-v4-flash-0731` through OpenRouter, with medium
reasoning and the existing $0.20 run cost guard. It remains semantic curation:
it verifies claims against repository and captured GitHub evidence.

CI renders `.config/knowledge.json` with `bin/knowledge-config --ci` into its
own keyword-only index. It does not include local personal notes or run QMD
embedding/model downloads. Legacy Sentry history stays outside default search.
The model can edit existing ordinary active notes or archive them. It cannot
edit README policy, existing archives, or tool-managed ledgers. The publisher
checks patch scope, regenerates only the active-index marker section, then
validates metadata, index coverage, and local links before opening a PR.

Use `PUBLISH_CHANGES=false` with `bin/finalize-memory-audit` only in a clean,
disposable fixture when testing an audit patch. The publisher expects the model
result in `artifacts/openrouter-final.md` and applies it to that fixture.

`.project-starter.json` records the copied release and tested QMD version.
Compare future releases manually and merge relevant improvements. These files
belong to the project; there is no automatic updater or runtime dependency on
the starter repository. Retain `LICENSE.project-starter` with copied material.
