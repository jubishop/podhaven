## Project Memory & Tracking
Repo context lives in `memory/`, `docs/`, and GitHub issues:

- `memory/`: long-lived notes; search before writing and update existing notes when possible.
  - New or updated pages must follow [`memory/README.md`](memory/README.md).
  - Move notes that are no longer relevant to active work into `memory/archive/`; set `status: resolved` only on project notes.
- `docs/`: PR-reviewed design docs and research; update [`docs/README.md`](docs/README.md) when adding/removing docs.
- GitHub Issues (`jubishop/podhaven`): lifecycle-tracked TODOs, bugs, refactors.

Use the repository's QMD helper for topic lookup:

- `git knowledge search "known term"`: names, files, APIs, and exact concepts.
- `git knowledge query "question" --no-rerank`: broader topic lookup.
- `git knowledge get <path>[:line] -l N`: focused source reads.

Search before non-trivial work or writing memory. Use direct reads or `rg` for
known paths or stale/unavailable search. Markdown remains authoritative.
Run `bin/setup` after cloning. Use `bin/check --documents-only` for Markdown
edits and `bin/check` for fast tooling checks. Run `bin/check --full` after
setup or foundation changes, and before a tooling PR or release. Use the
existing Swift build and test checks for application changes. Do not run checks
for discussion or read-only work. Batch related edits before checking and
reuse passing results while relevant inputs are unchanged.
Run `bin/qmd-index` after uncommitted knowledge edits when current search
results are needed. Use `bin/doctor`
for read-only diagnostics. Hooks use each checkout's own scripts. Read the
[development workflow](docs/development-workflow.md) for cache cleanup and recovery.
Legacy Sentry history requires `-c sentry-history`; it is not current guidance.

## MCP Usage
- Swift/SwiftUI/iOS: consult apple-docs MCP for current info.

## Xcode Project
- All four target folders (`PodHaven`, `PodHavenShare`, `PodHavenWidget`, `PodHavenTests`) are synchronized folder groups (`PBXFileSystemSynchronizedRootGroup`): files added on disk join the target automatically; never edit `project.pbxproj` to register files. `PodHavenMacros` is a local SPM package.

## Repo Guardrails
- Public repo: no secrets, API keys, tokens, or credentials.
- No commits or pushes unless explicitly asked; preserve user edits and never reset/revert unknown changes.
- Build/test must end with zero compiler/linker/runtime/deprecation/unused-result/Sendable warnings.
- The Lint Swift build phase fails before `SwiftCompile`: a lint-only failure says nothing about whether the code compiles. Format touched files with `swift-format format --in-place --configuration .swift-format <files>`, check with `bin/lint-swift-format`, then rebuild to surface compile errors.

## Compatibility
- Use modern APIs and avoid unnecessary compatibility layers. Change deployment targets or dependency versions when the requested work requires it, or when an upgrade is explicitly requested.
- Shipped DB migrations are immutable. Never edit body/version; add the next migration for schema or seed changes.

## UI Structure
- SwiftUI views stay declarative; forward actions to view models or shared protocols; no business logic in views.
- Labels/images use `AppIcon`, e.g. `AppIcon.play`, not `Image(systemName: "play.fill")`.

## Accessibility
- Treat accessibility as required for every UI change: support VoiceOver with accurate labels, values, traits, actions, focus, and reading order; hide decorative elements.
- Prefer native semantic controls and support Dynamic Type. Selection, progress, disabled state, and overlays must remain understandable without visual context.
- Add focused accessibility regression tests for custom semantics and manually verify representative VoiceOver flows when automated inspection cannot cover them.

## Shared Utilities & Helpers
- Use existing helpers: `Assert` for invariants/fatal logging; `ThreadSafe`/`Broadcast` for safe storage, streams, and observability; injected `Sleepable`/`sleeper` for production timing.
- No `Task.detached`; use `Task { ... }` and store long-lived handles.

## Factories
- New container-built types follow the existing factory + `fileprivate init` pattern.
- Prefer `@DynamicInjected` where possible, otherwise just use `Container.shared`, but never pass a Factory around as a parameter.

## Errors and Logging
- Log with `ErrorKit` formatting at the appropriate level; use static `Logger`s from `Log.as`.
- Catch where the code can recover, present a failure, or finish an operation that cannot propagate errors. Otherwise, propagate.
- Add useful local context without hiding the failure. Never turn an error into a value that could be mistaken for success. Ensure errors are logged before they stop propagating, except for the silent cancellation checks and sleeps allowed below.
- Keep `do`/`catch` around `try` calls only.
- Caught object: `log.caughtError()`; no object: `log.error()`.
- `caughtError()` auto-downgrades unremarkable errors (`CancellationError`, cancelled/timed-out `URLError`) to `.debug` via `ErrorKit.isRemarkable`.
- Log self-contained values (counts, sizes, flags, settings) after guards/conditionals: what happened, not what might.

## Testing
- Swift Testing: follow existing fixtures (`@Suite("...", .container)`, `#expect`, `AppDB.inMemory()`, `Create`, `PodHavenTests/Fakes`).
- Use `FactoryKit` with `scope(.cached)` and then override with `context(.test)` in `PodHavenTests/Extensions/Container.swift` for test injection.
- `@Suite("...", .container)` isolates Factory injected state per-test; supporting full test concurrency. Do not use `.serialized`.
- Every functional change requires a regression test proven failing before the implementation and passing afterward; if it passes before and after, it does not prove the changed behavior.
- Default local test runs to My Mac (Designed for iPhone): `-destination 'platform=macOS,name=My Mac'`.
- Always pass `-hideShellScriptEnvironment` to `xcodebuild`; the shared scheme pre-action otherwise prints inherited environment values into raw logs.
- Use suite/class-level `-only-testing:PodHavenTests/SomeSuite`. Method filters can look green while running zero tests.
- Async tests use `Wait.until`, `Wait.forValue`, polling helpers, `AsyncStream` continuations, or `withObservationTracking`; never `Task.sleep` or thread blockers (`DispatchSemaphore`, `RunLoop.run`, `Thread.sleep`, `NSCondition.wait()`). Use `sleeper.sleep` only to advance production sleeps.
- All Swift test files belong to `PodHavenTests`. Repository tooling tests live in `bin/tests`.
- Migration tests use raw SQL and `Container.shared.standardDefaults()` only; no model types, `Create`, or drifting constructs.
- Test observable behavior, not internals. Do not expose `private` methods, add test-only injection/accessors, or keep production API with only test callers. Delete all test-only surfaces.
- Put the test seam at the OS-integration boundary, not above our own logic. Wrap system-framework types in app-owned protocols that the real types conform to (via `extension`) and fake those, so our orchestration runs for real in tests.
- To assert on swift-log output, use `LogCapture.withSink` (per-test isolation via `@TaskLocal`).

## Previews
- Every graphical change requires adequate Xcode `#Preview` coverage. Add or update preview blocks so the changed UI and its relevant states can be inspected without running the app, and verify that the previews build.
- Previews use stubbed dependencies and an isolated in-memory database when needed. Never access the network or persistent app databases.

## Database
- Prefer pure GRDB APIs (associations, aggregates, column expressions, `joining()`, `having()`, `filter()`, etc.) over raw SQL strings.

## Migrations
- Migration code uses only literals: table/column strings and inline allowed values; no model types/enums/drifting refs. Renames must not alter shipped behavior.
- New derived/cached columns backfill existing rows inside the same migration with raw SQL; no launch-time backfill pass.
- `CHECK` constraints pass when the expression is NULL: use `IS`, not `=`, for `json_type(col, '$.path')` guards so rows missing the key are rejected.

## Coding Standards
- Keep every Swift file under 1000 lines.
- Use `@discardableResult` when ignoring the result is a supported use of the API. Otherwise, preserve unused-result warnings and allow explicit `_ =` at individual call sites when discarding the result is intentional and safe. Do not add wrappers solely to avoid `_ =`.

### Production Only
- Choose captures based on the required lifetime. Use weak captures when stored callbacks must not retain their owner. Finite tasks may retain their owner until completion. Long-lived tasks need an explicit cancellation owner and stopping point; weak capture alone does not establish either.
- Avoid `try?`; use `do`/`catch`. Exceptions: `Task.checkCancellation()` and `sleeper.sleep()` when silent failure is intentional.
- No force unwraps (`!`); use `Assert` or guarded error handling.
- Never use `map`/`flatMap` to unwrap optionals; use `if let`/`guard let`. Reserve `map`/`flatMap` for collections.
- Run `swift-format` on every Swift file you touch. Production code must pass `bin/lint-swift-format`.
- Comments use `//`, not `///`; no doc comments. Default to no comment whenever possible, or very succinct comment if absolutely necessary.
- No code-comment refs to repo items — issues/PRs (e.g. `#262`), docs/memories (e.g. `foo.md`); that context belongs in the commit/PR. Stable external urls are fine.
- Don't bake specific constant values into comments; they drift when the constant changes and silently go wrong. Describe behavior relative to the named constant.
- No one-call-site helper unless it earns the hop via early-exit/`guard` flow, recursion, or a clear named phase. Inline linear sequences.
- Put protocol conformances on the main declaration with their requirements in the body; don't spin up an `extension Foo: SomeProtocol` just to hold a conformance. Reserve conformance extensions for constrained methods, retroactive external conformance, or `where Self == X`. Splitting a type across files with a plain `extension Foo { … }` is justified only to keep a file under that 1000-line limit (as with `PlayManager`) or to avoid awkward dependency graphs (such as `Database/` depending on `Views/`).
- Don't loop/poll to wait for conditions; use async/await and continuations.
- Avoid `@unchecked`, `@retroactive`, and `unsafe` unless necessary.
- Avoid `inout` or passing reference types only to be mutated and read back by the caller; return values instead.
- Prefer `@MainActor` on declarations over `MainActor.run`.
- Model state transitions as enums, not `Bool` flags.
- Prefer `struct` over `class`; reach for `class` only when reference identity or shared mutable state genuinely require it.
