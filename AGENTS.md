## Project Memory & Tracking
Persistent context is repo-readable, organized into two flat stores plus GitHub issues:

- **Memory (`memory/`)** — one flat list of long-lived notes. Not auto-loaded into sessions; agents discover pages via `qmd`. Schema in `memory/README.md`.
- **Design docs (`docs/`)** — intentional artifacts: architecture, initiatives, research. PR-reviewed. Status lives in frontmatter `status:` (`planning | in-progress | shipped | blocked | abandoned`). When adding or removing a doc, update the human-readable list in `docs/README.md`.
- **GitHub Issues (`jubishop/podhaven`)** — lifecycle-tracked TODOs, bugs, refactors. Use `gh issue list/create/view`; link/close from PRs.

**Use `qmd` for topic lookup across `memory/` and `docs/`; avoid raw `grep` or speculative `Read`. Use the cheapest mode that fits.**

- `qmd search "known term"`: first choice for names, files, APIs, issue numbers, and exact concepts.
- `qmd query "question" --no-rerank`: default for fuzzy or open-ended topic lookup.
- `qmd get <path>[:line] -l N`: cheap page/slice fetch.

Run a qmd lookup before non-trivial area work; use `Read`/`grep` only for known paths. Config: `.config/qmd/index.yml`. Git hooks under `bin/hooks/` re-index after checkout, merge, commit, and rewrite — no manual `qmd update` needed.

**Writing memories.** Write freely whenever you learn something worth keeping (user preferences, validated approaches, gotchas, incidents, external refs). **Always `qmd search` the topic first** — if a related page exists, update it rather than creating a new one. Avoid duplicates and contradictions. Do **not** create or maintain a index; `qmd` is the lookup mechanism.

## MCP Usage
- Swift/SwiftUI/iOS: consult apple-docs MCP for current info.

## Repo Guardrails
- Public repo: no secrets, API keys, tokens, or credentials.
- No commits or pushes unless explicitly asked.
- Preserve user edits; no resets/reverts of unknown changes.
- Fix all compiler/linker/runtime/deprecation/unused-result/Sendable warnings at the root. Build/test must end with zero warnings; do not ignore, suppress, or leave noise.

## Compatibility
- No backward compatibility requirement for older iOS or library versions; use the latest.
- DB migrations are the exception: shipped migrations are immutable. Never edit body/version; add the next migration for schema or seed changes.

## UI Structure
- SwiftUI views stay declarative; forward actions to view models or shared protocols; no business logic in views.
- Labels/images use `AppIcon`, e.g. `AppIcon.play`, not `Image(systemName: "play.fill")`.

## Shared Utilities & Helpers
- `Assert` funnels invariants through structured fatal logging; avoid `fatalError`/`precondition` outside it.
- `ThreadSafe` provides concurrency-safe storage. `Broadcast` adds AsyncStreams and Observability.
- Production timing uses injected `Sleepable` (`sleeper`), never `Task.sleep`.
- No `Task.detached`; use `Task { ... }` and store long-lived handles.

## Factories
- Container-built types use `fileprivate init` to force factories. See `AppLauncher`, `Repo`, and `StateManager`.

## Errors and Logging
- Log with `ErrorKit` formatting at the appropriate level; use static `Logger`s from `Log.as`.
- Catch only to add local-only context; otherwise propagate. The top of the stack must log every error.
- Keep `do`/`catch` around `try` calls only.
- Caught object: `log.caughtError()`; no object: `log.error()`.
- Avoid `try?`; use `do`/`catch`. Exceptions: `Task.checkCancellation()` and `sleeper.sleep()` when silent failure is intentional.
- Log self-contained values (counts, sizes, flags, settings) after guards/conditionals: what happened, not what might.

## Testing
- Swift Testing: `@Suite("...", .container)`, `#expect`, and structured concurrency for async tests.
- Bugfixes require a regression test proven failing before the fix; if it passes before and after, it is not a regression test and the bug may not be real.
- Use suite/class-level `-only-testing:PodHavenTests/SomeSuite`. Method filters can look green while running zero tests; use them only after confirming the exact discovered ID.
- Tests never use `Task.sleep`; use `Wait.until` or polling helpers.
- Use `sleeper.sleep` only to advance time when testing production sleeps.
- No thread blockers for async coordination: `DispatchSemaphore`, `RunLoop.run`, `Thread.sleep`, `NSCondition.wait()`. They can deadlock the cooperative pool and GRDB. Use `Wait.until`, an `AsyncStream` continuation, or `withObservationTracking`.
- Repo tests use `AppDB.inMemory()`; `Create` helpers build realistic unsaved models.
- Override factories with `.context(.test)` and `PodHavenTests/Fakes`.
- All test files belong to `PodHavenTests`.
- Migration tests use raw SQL and `Container.shared.standardDefaults()` only; no model types, `Create`, or drifting constructs.
- Test observable behavior, not internals. Do not expose `private` methods, add test-only injection/accessors, or keep production API with only test callers. Delete test-only surface; improve the API or fixture if needed.

## Previews
- Previews stub factories for in-memory SwiftUI previews; no network or DB access.

## Database
- Prefer pure GRDB APIs (associations, aggregates, column expressions, `joining()`, `having()`, `filter()`, etc.) over raw SQL strings.

## Migrations
- Migration code uses only literals: table/column strings, inline allowed values, and no model types/enums/drifting refs. Renames must not alter shipped behavior. Same rule as migration tests.

## Coding Standards
- Use `[weak self]` in closures/Tasks that capture `self` unless a strong reference is required. Unwrap with `guard let self else { return }`; use `self.x`, not `self?.x`.
- `.map`/`.compactMap` transform lists, not optionals. Use `x?.rawValue`, `if let`, or `guard let`; not `x.map { $0.rawValue }` or `[x].compactMap { $0 }`.
- No force unwraps (`!`) in production; use `Assert` or guarded error handling.
- Prefer triple-quoted strings for multiline or >100-character literals.
- Run `swift-format` on every Swift file you touch.
- Comments use `//`, not `///`; no doc comments. `// MARK: - <Section>` is fine when useful.
- Default to no comment. Only explain non-obvious why: hidden constraints, invariants, workarounds, surprises not recoverable from names, call site, or `git blame`. Most useful comments are one line; use multiline only when needed.
- No issue/PR refs in production code comments (e.g., `#262`, `see #259`). They belong in the commit/PR. Tests are exempt.
- Remove unused code, properties, and parameters immediately.
- No one-call-site helper unless it earns the hop via early-exit/`guard` flow, recursion, or a clear named phase. Inline linear sequences.
- No non-specializing extension splits. Put conformances on the main declaration and requirements in the body. Use extensions only for constrained methods, retroactive external conformance, or `where Self == X`.
- In production code, avoid `@unchecked`, `@retroactive`, and `unsafe` unless necessary. Test code may use them freely.
- Avoid `inout`; return values instead.
- Prefer `@MainActor` on declarations over `MainActor.run`.
- Named tuples only: label every element and access by name.
- When filling an `Array`, `Dictionary`, `Set`, `ContiguousArray`, `Data`, or `String` with known/bounded final size, use `CapacityReservable init(capacity:)`, not `[]` / `[:]`.
