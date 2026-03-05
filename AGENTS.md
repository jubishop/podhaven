## MCP Usage
- If discussing Swift, SwiftUI, and iOS: Consult the apple-docs and apple-deep-docs mcps for up to date information.

## Repo Guardrails
- **This is a public repository.** Never add secrets, API keys, auth tokens, or credentials to any file.
- Never create commits or push unless the humans explicitly ask.
- Assume the working tree may hold user edits; respect them and avoid resets or reverts.

## Build & Test
- Don't actually try to build or test unless the user explicitly asks.

## Compatibility
- Backward compatibility is not necessary.  Always use the latest features and libraries.

## UI Structure
- Views stay declarative, forwarding actions to their view models or shared protocols; never introduce business logic inside SwiftUI view structs.

##  Shared Utilities & Helpers
- `Assert` funnels invariants through structured fatal logging; avoid `fatalError`/`precondition` outside this helper.
- `ThreadSafe` supports concurrency-safe storage.
- Never use `Task.sleep` in production code; always use the injected `Sleepable` (`sleeper`) so tests can control timing.

## Errors and Logging
- All Error instances should conform to `ReadableError` and use `ErrorKit`.
- All logging should go through static `Logger` instances created via `Log.as` methods.

## Testing
- Tests use the Swift Testing DSL: `@Suite("…", .container)` with `#expect` assertions; async tests rely on structured concurrency.
- Tests should NEVER use `Task.sleep`, ever. Use `Wait.until` or similar polling helpers to await conditions.
- Tests may use `sleeper.sleep` only to artificially advance time when testing production code that uses sleeps (e.g., debouncing, rate limiting).
- In-memory GRDB (`AppDB.inMemory()`) powers repo tests; helpers under `Create` build realistic unsaved models.
- Override factories with `.context(.test)` to plug in fakes from `PodHavenTests/Fakes`
- Each test file belongs to either the `ParallelTests` or `PerformanceTests` target, never both. Almost always use `ParallelTests` unless it's a specific performance test.
- Xcode auto-adds new test files to both targets. To exclude a file from a target, add its path (relative to `PodHavenTests/`) to the `membershipExceptions` list in the corresponding `PBXFileSystemSynchronizedBuildFileExceptionSet` in `project.pbxproj`.

## Previews
- Previews stub factories for in-memory SwiftUI previews with no network calls or DB access.

## Coding Standards
- Always use `[weak self]` in closures and Tasks that capture `self`, unless a strong reference is explicitly required.
- Prefer `if let` / `guard let` over `.map` on optionals
- Never force-unwrap (`!`) in production code; use `Assert` or guarded unwraps with readable error handling.
- Prefer triple-quoted strings for multi-line or >100 character literals.
- Run `swift-format` on every Swift file you touch before handing work back.
- Use `//` for comments, not `///` (no doc comments).
- Never leave behind unused code, properties, or parameters. If something becomes unused, remove it immediately.
