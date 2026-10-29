---
status: current
---

# Engineering policy

Shared engineering rules for projects built on Project Starter. A project's
own instructions and pages take precedence over this policy and the managed
`AGENTS.md` block wherever they differ, stricter or looser, so a project can
set its own edge cases.

## Third-party dependencies

Prefer the standard library, platform APIs, and small implementations the
project can own. Add a dependency when its concrete benefits outweigh its
costs. Compare it with the smallest complete owned implementation, including
validation, edge cases, security, maintenance, upgrades, and the packages it
brings. Avoiding initial work is not enough reason on its own. Apply this
through ordinary technical judgment, not an approval step, and preserve
existing stack choices.

## Test-driven development

Regression fixes and functional changes need automated tests of the changed
behavior. Use red-green TDD when practical:

1. **Red:** write or update a focused test and confirm it fails for the
   expected reason. A setup error or a run with no tests does not count.
2. **Green:** make the smallest change that passes it.
3. **Refactor** with the tests passing, then run the relevant checks.

A test that passes both before and after the change does not demonstrate it.
When testing first is impractical, say why, keep automated coverage, and
report what was verified. Documentation-only edits need no tests, not
new behavior tests.

Test through external surfaces: user-visible outcomes, public interfaces, and
interactions with external systems. Do not call private helpers, assert
internal structure or incidental call order, or add production APIs only for
tests. Put fakes at operating-system, network, storage, and service boundaries
so the project's own logic runs.

### Test cost and coverage

Use the cheapest test level that establishes the behavior. Prepare
prerequisites through fixtures or public interfaces when setup is not under
test, and keep end-to-end tests for complete journeys and behavior that
depends on the real interaction surface. Moving or removing a slow case must
keep equivalent evidence.

Measure representative runs before and after test-performance work, and
report failed or retried runs separately. Parallelize only after giving shared
files, processes, and data clear ownership and validating independence. Keep
sequential execution where interference remains, and never hide failures with
retries or weaker assertions.

### Flaky tests

Never ignore a flaky test. Fix it on the spot when the fix fits the current
change. When it doesn't, such as when it lies outside the pull request's
scope, file a GitHub issue for it right away, without waiting to be asked, or
reuse the one that already tracks it, so a later agent can fix it. Name that
issue when reporting the work.

## File organization

Keep each file focused on one responsibility or feature area. About 1,000
lines is a review threshold for hand-written source, tests, and styles, not a
cap. Extract a cohesive area when that improves clarity. Do not compress
formatting, create numbered fragments, or move unrelated code into a new
catch-all file to meet a count. Generated and external files are exempt.

### Markdown pages

Keep each memory, docs, or other hand-written page focused on one topic or
reader task. Split a page when it mixes independent topics or readers must
scan unrelated material, not because of its length. Move complete topics into
descriptively named pages, leave a short overview and links, and update
indexes and incoming links. Keep each rule or decision in one authoritative
place with its reasons, evidence, dates, and status. Keep indexes and
automatically loaded instructions short and link to details. Preserve
generated and tool-managed formats.

## Validation checkout isolation

Builds, static analysis, formatting, and tests discover project sources only
in the active checkout. Exclude nested worktrees, temporary copies, and
unrelated output, and include required generated inputs explicitly; Git ignore
rules alone do not establish this boundary. Keep mutable test data, services,
and build output separate between concurrent checkouts. Share only immutable
caches that the tool supports sharing.

When changing discovery or caches, verify that errors in intended files are
still reported, that an unrelated checkout's invalid files are not, and that
fresh and warm caches behave after a checkout is added, changed, or removed.

## Runtime and toolchain versions

Use the latest stable release of each runtime, compiler, build tool, and
developer tool instead of pinning a version that someone must remember to
bump. For Node, that is the newest LTS line.

- Declare the minimum supported version in the stack's usual manifest, such
  as `"engines": {"node": ">=24"}`, and write `lts/*` (or the ecosystem's
  equivalent) in version files.
- Application commands reject only versions below that minimum, before
  installing, testing, building, or starting services. Report the version
  found, the minimum, and how to select a newer one.
- CI installs the latest stable release on every run (for example,
  `node-version: lts/*` with `check-latest: true`, so the runner does not
  reuse an older cached release), and a new release is tested without anyone
  asking.
- Workflows reference GitHub Actions by major tag, such as
  `actions/checkout@v7`, not by commit SHA, and install CI tools at their
  latest version. Move to a new major tag when one ships. A job that holds
  deployment credentials pins each third-party action it runs to a commit
  SHA, with that reason in a comment beside the pin.
- Developer machines and servers update on a schedule that verifies the
  result and rolls back on failure.
- Pin a version only to work around a known incompatibility, and record the
  issue and the condition for removing the pin next to it.

Raise the minimum when the project starts relying on a newer release.
Application dependency lockfiles stay; this applies to runtimes and tools.
Keep document and foundation checks independent of application runtimes.

## Kinds of change

How a change reaches the default branch depends on what it touches:

1. **Text** is not code: Markdown, including docs, memory, and agent
   instructions, and the prose of AI skills. Commit it directly on the default
   branch and push it without checks or a pull request.
2. **Development code** doesn't run in production: tests, CI workflows, hooks,
   check scripts, development and deploy tooling, scripts in AI skills, and the
   configuration they read. Run the [checks](#checks) it needs, then commit it
   directly on the default branch and push it, without a pull request.
3. **Production code** runs when the application executes: its code, the
   configuration it reads, its dependencies, and whatever starts it, such as
   service units or schedules. Run its checks and deliver it through a pull
   request.

A change that spans kinds follows the strictest kind it touches, and an
uncertain change is treated as the stricter kind. A project's own rules take
precedence, for example to require a pull request for a document that defines
what its application may do, or to allow direct pushes of production code.

## Checks

| Command | Runs |
| --- | --- |
| `bin/check --documents-only` | Managed-file hashes, document metadata, index coverage, local links, and heading anchors. |
| `bin/check` | The documents-only checks, plus Python syntax, ShellCheck, and Git whitespace checks. ShellCheck lints `.envrc` and each `bin/` script whose shebang names `sh`, `bash`, `dash`, or `ksh`, in that dialect. |
| `bin/check --full` | The `bin/check` checks, then the project's executable `bin/check-application`, when present. |

Put application typechecking, lint, tests, and builds in
`bin/check-application`. Only `--full` runs it, after the foundation checks
pass. Keep both routine modes free of application tools and package-manager
startup; they should finish well under a second on a small repository.

A project's `.shellcheckrc` configures ShellCheck, such as
`external-sources=true` to follow the files its scripts source.

Choose checks by the change and its stage:

- Discussion, planning, and read-only work: none.
- Text, and Project Starter syncs: none.
- Development code: the checks that exercise it, such as the changed tests or
  the tool's own tests. Changes to tests as a whole, CI, hooks, or the checks
  themselves run `bin/check --full` locally.
- Edits to production code: the relevant application checks, run directly.
- Material uncertainty about what a change affects: `bin/check --full` locally.
- Merge or release of production code: a successful `bin/check --full` for the
  delivered code, from an enforced CI gate or, without one, run locally. A
  pending, skipped, or failed CI run does not count.

Batch edits before checking, and reuse a passing result until its inputs
change. Report focused and full results separately.

`bin/check --full` reuses a passing `bin/check-application` run on its own: when
the checkout has no uncommitted or untracked changes, and that run passed in
the last 12 hours for the same tree and environment (the platform, `python3`
and `node` versions, and the packages in `.venv` and `node_modules`), it says
which commit passed and skips the application checks. A reused result counts
as a successful `bin/check --full` for that tree. Worktrees of a repository
share the record, and `bin/check --full --no-reuse` runs the application checks
regardless.

### Hosted CI

CI runs `bin/check --full` for pull requests and pushes to the default
branch. Its triggers set `paths-ignore: ['**.md']`, so a change to Markdown
alone starts no hosted run and needs no local check. When
Markdown affects behavior, such as pages the application serves or tests
read, use a `paths` filter instead: `'**'`, then `'!**.md'`, then those
pages. A workflow skipped by a path filter reports no status, so do not make
it a required check.

When hosted CI cannot run only because the Actions quota is exhausted or
GitHub is rate limiting, run `bin/check --full` locally on the exact revision
being delivered. A pass satisfies the merge or release gate. Record the
blocker, revision, commands, and result, and report CI as unavailable, not
passed. This does not cover failing or unexplained runs, or checks that
cannot run locally, and it never bypasses enforced branch protection or
required approvals.

`.project-starter.json` records the hashes of managed files. Change those
files through Project Starter releases, or record an override with its reason;
checks skip overridden files. Exclude generated or externally owned docs with
deliberate `checks.exclude` patterns in `.config/knowledge.json`, never to
bypass failures in hand-written pages.

A Project Starter sync writes text and development code that Project
Starter's release checks already exercised, so it goes directly to the default
branch without further checks. With no manual follow-up, commit only the
synced files, with `[skip ci]` in the message so
GitHub Actions starts no push workflows, and push from a checkout with no
other unpushed commits. Never bypass enforced branch protection.

## Deployment decisions

Documentation, agent instructions, task setup, comments, and other
nonfunctional changes may be pushed without a deployment or release. A
Project Starter sync with no manual follow-up needs no deployment. Assess every change since the last successful release.
Deploy when behavior, dependencies, assets, migrations, configuration, or
operations change, when uncertain, or when asked. A project that deploys on
push documents its supported skip mechanism and a manual override for edits a
path filter cannot classify. When skipping, record the reason and the last
deployed revision.
