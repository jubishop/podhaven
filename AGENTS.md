## Project Memory
- Project-specific memory lives in `memory/`.
- Use `memory/MEMORY.md` as the canonical index of saved memories, with one linked Markdown file per memory in `memory/`.
- When asked to save, recall, or update a memory, read and write those files directly. Check memory before guessing about prior project-specific decisions or environment details.

## MCP Usage
- If discussing Swift, SwiftUI, and iOS: Consult the apple-docs mcp for up to date information.

## Repo Guardrails
- **This is a public repository.** Never add secrets, API keys, auth tokens, or credentials to any file.
- Never create commits or push unless the humans explicitly ask.
- Assume the working tree may hold user edits; respect them and avoid resets or reverts.

## Compatibility
- Backward compatibility is not necessary.  Always use the latest features and libraries.

## UI Structure
- Views stay declarative, forwarding actions to their view models or shared protocols; never introduce business logic inside SwiftUI view structs.
- Always use `AppIcon` for labels and images (e.g., `AppIcon.play` instead of `Image(systemName: "play.fill")`).

##  Shared Utilities & Helpers
- `Assert` funnels invariants through structured fatal logging; avoid `fatalError`/`precondition` outside this helper.
- `ThreadSafe` supports concurrency-safe storage.  `Broadcast` adds AsyncStreams and Observability.
- Never use `Task.sleep` in production code; always use the injected `Sleepable` (`sleeper`) so tests can control timing.

## Errors and Logging
- Log errors at the appropriate level using `ErrorKit` for formatting system error messages.
- All logging should go through static `Logger` instances created via `Log.as` methods.
- Catch errors locally only when the function has extra context derived entirely locally; otherwise let them propagate up the call stack.
- Every error must be logged somewhere by the top of the call stack — errors must never silently disappear.
- Keep `do`/`catch` scope minimal — wrap only the `try` calls, not surrounding work.
- Use `log.caughtError()` when there's a caught error object; use `log.error()` only when there's no error object.
- Avoid `try?` — prefer `do`/`catch` with appropriate logging so failures are visible. Exceptions: `Task.checkCancellation()` and `sleeper.sleep()` where silent failure is intentional.
- Include relevant values in log messages (counts, sizes, flags, settings) so logs are self-contained and useful without cross-referencing code.
- Place log statements after guards and conditionals, not at function entry — log what *did* happen, not what *might* happen.

## Testing
- Tests use the Swift Testing DSL: `@Suite("…", .container)` with `#expect` assertions; async tests rely on structured concurrency.
- Tests should NEVER use `Task.sleep`, ever. Use `Wait.until` or similar polling helpers to await conditions.
- Tests may use `sleeper.sleep` only to artificially advance time when testing production code that uses sleeps (e.g., debouncing, rate limiting).
- In-memory GRDB (`AppDB.inMemory()`) powers repo tests; helpers under `Create` build realistic unsaved models.
- Override factories with `.context(.test)` to plug in fakes from `PodHavenTests/Fakes`
- All test files belong to the `PodHavenTests` target.
- Migration tests must use raw SQL and `Container.shared.standardDefaults()` only — no model types, `Create` helpers, or other constructs that could change and break the test after the migration is written.
- **Test external behavior, not internal details.** Never expose `private` methods (making them `internal`, injecting closures for testability, exposing computed values, etc.) just to write a test. If something is hard to test through the public/observable API, that's a design signal — fix the API or improve the test fixture, don't drill into the implementation. Tests coupled to internals become brittle and block refactoring.

## Previews
- Previews stub factories for in-memory SwiftUI previews with no network calls or DB access.

## Database
- Prefer pure GRDB APIs (associations, aggregates, column expressions, `joining()`, `having()`, `filter()`, etc.) over raw SQL strings.

## Coding Standards
- Always use `[weak self]` in closures and Tasks that capture `self`, unless a strong reference is explicitly required.
- `.map` and `.compactMap` are for transforming lists — never use them to work around optionals. Don't write `x.map { $0.rawValue }` (use optional chaining `x?.rawValue`) or `[x].compactMap { $0 }` (use `if let x { … }` / `guard let x else { … }`). For anything beyond a direct projection, use `if let` / `guard let`.
- Never force-unwrap (`!`) in production code; use `Assert` or guarded unwraps with readable error handling.
- Prefer triple-quoted strings for multi-line or >100 character literals.
- Run `swift-format` on every Swift file you touch before handing work back.
- Use `//` for comments, not `///` (no doc comments).
- Never leave behind unused code, properties, or parameters. If something becomes unused, remove it immediately.
- Avoid using `@unchecked`/`@retroactive`/`unsafe` in code unless absolutely necessary.
- Avoid `inout` parameters; return values instead.
- Use `@MainActor` on functions/types instead of `MainActor.run { }` blocks.
- Prefer named tuples — every element must have a label (e.g., `(name: String, count: Int)`), accessed by name rather than `.0`/`.1`.
- When creating an `Array`, `Dictionary`, `Set`, `ContiguousArray`, `Data`, or `String` that will be filled iteratively and the final size is known or reasonably bounded, use the `CapacityReservable` `init(capacity:)` initializer (e.g., `var results = [Item](capacity: items.count)`) instead of `[]` / `[:]` to avoid repeated reallocations.
