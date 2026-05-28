## Project Memory & Tracking
Repo context lives in `memory/`, `docs/`, and GitHub issues:

- `memory/`: long-lived notes; search before writing and update existing notes when possible.
- `docs/`: PR-reviewed design docs; update `docs/README.md` when adding/removing docs.
- GitHub Issues (`jubishop/podhaven`): lifecycle-tracked TODOs, bugs, refactors.

Use `qmd` for topic lookup across `memory/` and `docs`; cheapest mode that fits:

- `qmd search "known term"`: first choice for names, files, APIs, issue numbers, and exact concepts.
- `qmd query "question" --no-rerank`: default for fuzzy or open-ended topic lookup.
- `qmd get <path>[:line] -l N`: cheap page/slice fetch.

Run a qmd lookup before non-trivial area work; use `Read`/`rg` only for known paths. Hooks under `bin/hooks/` re-index after checkout, merge, commit, and rewrite; no manual `qmd update` or `qmd embed` needed.

## MCP Usage
- Swift/SwiftUI/iOS: consult apple-docs MCP for current info.

## Repo Guardrails
- Public repo: no secrets, API keys, tokens, or credentials.
- No commits or pushes unless explicitly asked; preserve user edits and never reset/revert unknown changes.
- Build/test must end with zero compiler/linker/runtime/deprecation/unused-result/Sendable warnings.

## Compatibility
- No backward compatibility requirement for older iOS or library versions; use the latest.
- DB migrations are the exception: shipped migrations are immutable. Never edit body/version; add the next migration for schema or seed changes.

## UI Structure
- SwiftUI views stay declarative; forward actions to view models or shared protocols; no business logic in views.
- Labels/images use `AppIcon`, e.g. `AppIcon.play`, not `Image(systemName: "play.fill")`.

## Shared Utilities & Helpers
- Use existing helpers: `Assert` for invariants/fatal logging; `ThreadSafe`/`Broadcast` for safe storage, streams, and observability; injected `Sleepable`/`sleeper` for production timing.
- No `Task.detached`; use `Task { ... }` and store long-lived handles.

## Factories
- New container-built types follow the existing factory + `fileprivate init` pattern.
- Prefer `@DynamicInjected` where possible, otherwise just use `Container.shared`.

## Errors and Logging
- Log with `ErrorKit` formatting at the appropriate level; use static `Logger`s from `Log.as`.
- Catch only to add local-only context; otherwise propagate. The top of the stack must log every error.
- Keep `do`/`catch` around `try` calls only.
- Caught object: `log.caughtError()`; no object: `log.error()`.
- `caughtError()`/`error()` auto-downgrade unremarkable errors (`CancellationError`, cancelled/timed-out `URLError`) to `.debug` via `ErrorKit.isRemarkable`.
- Log self-contained values (counts, sizes, flags, settings) after guards/conditionals: what happened, not what might.

## Testing
- Swift Testing: follow existing fixtures (`@Suite("...", .container)`, `#expect`, `AppDB.inMemory()`, `Create`, `PodHavenTests/Fakes`). Do not use `.serialized`.
- Use `FactoryKit` with `scope(.cached)` and then override with `context(.test)` in `PodHavenTests/Extensions/Container.swift` for test injection.
- Bugfixes require a regression test proven failing before the fix; if it passes before and after, it is not a regression test and the bug may not be real.
- Default local test runs to My Mac (Designed for iPhone): `-destination 'platform=macOS,name=My Mac'`.
- Use suite/class-level `-only-testing:PodHavenTests/SomeSuite`. Method filters can look green while running zero tests.
- Async tests use `Wait.until`, polling helpers, `AsyncStream` continuations, or `withObservationTracking`; never `Task.sleep` or thread blockers (`DispatchSemaphore`, `RunLoop.run`, `Thread.sleep`, `NSCondition.wait()`). Use `sleeper.sleep` only to advance production sleeps.
- All test files belong to `PodHavenTests`.
- Migration tests use raw SQL and `Container.shared.standardDefaults()` only; no model types, `Create`, or drifting constructs.
- Test observable behavior, not internals. Do not expose `private` methods, add test-only injection/accessors, or keep production API with only test callers. Delete test-only surface; improve the API or fixture if needed.

## Previews
- Previews stub factories for in-memory SwiftUI previews; no network or DB access.

## Database
- Prefer pure GRDB APIs (associations, aggregates, column expressions, `joining()`, `having()`, `filter()`, etc.) over raw SQL strings.

## Migrations
- Migration code uses only literals: table/column strings and inline allowed values; no model types/enums/drifting refs. Renames must not alter shipped behavior.

## Coding Standards (Production Only)
- Use `[weak self]` in closures/Tasks that capture `self` unless a strong reference is required. Unwrap with `guard let self else { return }`; use `self.x`, not `self?.x`.
- Avoid `try?`; use `do`/`catch`. Exceptions: `Task.checkCancellation()` and `sleeper.sleep()` when silent failure is intentional.
- No force unwraps (`!`); use `Assert` or guarded error handling.
- Never use `map`/`flatMap` to unwrap optionals; use `if let`/`guard let`. Reserve `map`/`flatMap` for collections.
- Run `swift-format` on every Swift file you touch.
- Comments use `//`, not `///`; no doc comments. Default to no comment whenever possible, or very succinct comment if absolutely necessary.
- No external refs in code comments — issues/PRs (e.g. `#262`), docs/memories (e.g. `foo.md`), etc. They move or disappear; context belongs in the commit/PR.
- No one-call-site helper unless it earns the hop via early-exit/`guard` flow, recursion, or a clear named phase. Inline linear sequences.
- No non-specializing extension splits. Put conformances on the main declaration and requirements in the body. Use extensions only for constrained methods, retroactive external conformance, or `where Self == X`.
- Avoid `@unchecked`, `@retroactive`, and `unsafe` unless necessary.
- Avoid `inout` or passing reference types only to be mutated and read back by the caller; return values instead.
- Prefer `@MainActor` on declarations over `MainActor.run`.
- Model state transitions as enums, not `Bool` flags.
- Prefer `struct` over `class`; reach for `class` only when reference identity or shared mutable state genuinely require it.
