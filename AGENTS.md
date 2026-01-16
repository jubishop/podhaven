## MCP Usage
- If discussing Swift, SwiftUI, and iOS: Consult the apple-docs and apple-deep-docs mcps for up to date information.

## Repo Guardrails
- Never create commits or push unless the humans explicitly ask.
- Assume the working tree may hold user edits; respect them and avoid resets or reverts.
- Stay sandbox-friendly: ask for elevated access only when instructions require files outside the workspace.

## Build & Test
- Do not run builds or tests unless the request is explicit.

## Compatibility
- Backward compatibility is not necessary.  Always use the latest features and libraries.

## Database
- GRDB using SQLite.

## UI Structure
- Views stay declarative, forwarding actions to their view models or shared protocols; never introduce business logic inside SwiftUI view structs.

##  Shared Utilities & Helpers
- `Assert` funnels invariants through structured fatal logging; avoid `fatalError`/`precondition` outside this helper.
- `ThreadSafe` supports concurrency-safe storage.

## Errors and Logging
- All Error instances should conform to `ReadableError` and use `ErrorKit`.
- All logging should go through static `Logger` instances created via `Log.as` methods.

## Testing
- Tests use the Swift Testing DSL: `@Suite("…", .container)` with `#expect` assertions; async tests rely on structured concurrency.
- Tests should NEVER use `Task.sleep`, ever. Use `Wait.until` or similar polling helpers to await conditions.
- Tests may use `sleeper.sleep` only to artificially advance time when testing production code that uses sleeps (e.g., debouncing, rate limiting).
- In-memory GRDB (`AppDB.inMemory()`) powers repo tests; helpers under `Create` build realistic unsaved models.
- Override factories with `.context(.test)` to plug in fakes from `PodHavenTests/Fakes`

## Previews
- Previews stub factories for in-memory SwiftUI previews with no network calls or DB access.

## Coding Standards
- Keep each top-level type in a same-named file; add `// MARK:` separators to outline sections (Initialization, State, Actions, etc.).
- Never force-unwrap (`!`) in production code; use `Assert` or guarded unwraps with readable error handling.
- Prefer triple-quoted strings for multi-line or >100 character literals; use camelCase variables and PascalCase types.
- Maintain alphabetical protocol conformance order and consistent attribute ordering.
- Use @InjectedObservable when injecting observable types, @DynamicInjected otherwise.
- Add @InjectedObservable's first and then @DynamicInjected's after, each alphabetical within their group.
- `@ObservationIgnored` guards DI properties and transient state inside observable types.
- Run `swift-format` on every Swift file you touch before handing work back.
- Include `Copyright Justin Bishop, 2026` at the top of all new Swift files.
- Use `//` for comments, not `///` (no doc comments).
