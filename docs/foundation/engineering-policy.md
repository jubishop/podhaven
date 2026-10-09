---
status: current
---

# Engineering policy

Shared engineering rules for projects built on Project Starter. Project pages
may add stronger requirements, which take precedence.

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
report what was verified. Documentation-only edits need document checks, not
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

Declare supported runtime, compiler, and build-tool versions in the stack's
usual manifests or version files, and keep development, CI, and deployment
compatible with them. Application commands stop before installing, testing,
building, or starting services on an unsupported version, and report the
version found, the supported range, and how to select a compatible one. Keep
document and foundation checks independent of application runtimes.

Prefer recent maintained releases, and long-term support channels where an
ecosystem offers them. Upgrade deliberately across development, CI, and
deployment. Never let an unbounded selector silently change the supported
major version.

## Checks

| Command | Runs |
| --- | --- |
| `bin/check --documents-only` | Managed-file hashes, document metadata, index coverage, local links, and heading anchors. |
| `bin/check` | The documents-only checks, plus Python syntax, ShellCheck, and Git whitespace checks. |
| `bin/check --full` | The `bin/check` checks, then the project's executable `bin/check-application`, when present. |

Put application typechecking, lint, tests, and builds in
`bin/check-application`. Only `--full` runs it, after the foundation checks
pass. Keep both routine modes free of application tools and package-manager
startup; they should finish well under a second on a small repository.

Choose checks by the change and its stage:

- Discussion, planning, and read-only work: none.
- Markdown edits: `bin/check --documents-only`, once per batch.
- Code edits: the relevant application checks, run directly.
- Setup, tooling, hook, CI, or test-infrastructure changes, or material
  uncertainty: `bin/check --full` locally.
- Merge or release: a successful `bin/check --full` for the delivered code,
  from an enforced CI gate or, without one, run locally. A pending, skipped,
  or failed CI run does not count.

Batch edits before checking, and reuse a passing result until its inputs
change. Report focused and full results separately. CI runs
`bin/check --full`.

`.project-starter.json` records the hashes of managed files. Change those
files through Project Starter releases, or record an override with its reason;
checks skip overridden files. Exclude generated or externally owned docs with
deliberate `checks.exclude` patterns in `.config/knowledge.json`, never to
bypass failures in hand-written pages.

## Deployment decisions

Documentation, agent instructions, task setup, comments, and other
nonfunctional changes may be pushed without a deployment or release; required
checks still run. Assess every change since the last successful release.
Deploy when behavior, dependencies, assets, migrations, configuration, or
operations change, when uncertain, or when asked. A project that deploys on
push documents its supported skip mechanism and a manual override for edits a
path filter cannot classify. When skipping, record the reason and the last
deployed revision.
