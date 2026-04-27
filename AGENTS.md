## Project Memory & Tracking

Three places hold persistent project context — pick the right one when saving or looking something up:

- **Memory (`memory/`)** — non-derivable context: the *why* behind past decisions, user/feedback notes, references to external systems. `memory/MEMORY.md` is the canonical index with one linked Markdown file per entry. Read and write those files directly; check memory before guessing about prior project-specific decisions or environment details. Memory is **not** a task list — if it's a "we still need to do X," it belongs in a GitHub Issue, not here.
- **GitHub Issues (`jubishop/podhaven`)** — discrete TODOs, bug reports, and planned refactors. Use `gh issue list` / `gh issue create` / `gh issue view`. Anything with a clear open/closed lifecycle goes here so it can be linked from PRs and closed automatically when merged.
- **Design docs (`docs/`)** — ongoing initiatives and architecture rationale, organized into category subfolders like `docs/initiatives/`. `docs/README.md` is the index with one-line pointers per doc; add an entry there when you add a doc. Use these for multi-PR efforts and "what we built / what's next" notes that should evolve in lockstep with the code and get reviewed in PRs.

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

## Factories
- Types intended to be constructed only through a `Container` factory must declare their `init` as `fileprivate`, so callers are forced to go through the registered factory and can't bypass it (see `AppLauncher`, `Repo`, `StateManager` for examples).

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

## Migrations
- Migration code must reference only literal constants (table/column names as string literals, allowed values as inline arrays, etc.) — never reach into model types, enums, or any other construct that could change. Renaming or removing such a reference would silently change what an already-shipped migration accepts/produces. Same rule that applies to migration *tests* in `## Testing`.

## Coding Standards
- Always use `[weak self]` in closures and Tasks that capture `self`, unless a strong reference is explicitly required.
- `.map` and `.compactMap` are for transforming lists — never use them to work around optionals. Don't write `x.map { $0.rawValue }` (use optional chaining `x?.rawValue`) or `[x].compactMap { $0 }` (use `if let x { … }` / `guard let x else { … }`). For anything beyond a direct projection, use `if let` / `guard let`.
- Never force-unwrap (`!`) in production code; use `Assert` or guarded unwraps with readable error handling.
- Prefer triple-quoted strings for multi-line or >100 character literals.
- Run `swift-format` on every Swift file you touch before handing work back.
- Use `//` for comments, not `///` (no doc comments).
- `// MARK: - <Section>` dividers are encouraged for organizing files; they are not "comments" — keep them where they help readers navigate.
- **Default to NO comment.** Silence is the right call when the surrounding code already explains itself. Add one only when (1) the *why* is non-obvious — a hidden constraint, a non-obvious invariant, a workaround for a specific bug, or behavior that would surprise a reader, AND (2) a future reader couldn't recover the *why* from identifier names, the call site, or `git blame`.
- **Length follows substance, not style.** Most comments that earn their place fit on a single line. A multi-line comment is fine when the *why* genuinely needs more — e.g., capturing a subtle invariant, the shape of a workaround, or the reasoning that future-you will need to weigh edge cases.
- Never leave behind unused code, properties, or parameters. If something becomes unused, remove it immediately.
- Avoid using `@unchecked`/`@retroactive`/`unsafe` in code unless absolutely necessary.
- Avoid `inout` parameters; return values instead.
- Use `@MainActor` on functions/types instead of `MainActor.run { }` blocks.
- Prefer named tuples — every element must have a label (e.g., `(name: String, count: Int)`), accessed by name rather than `.0`/`.1`.
- When creating an `Array`, `Dictionary`, `Set`, `ContiguousArray`, `Data`, or `String` that will be filled iteratively and the final size is known or reasonably bounded, use the `CapacityReservable` `init(capacity:)` initializer (e.g., `var results = [Item](capacity: items.count)`) instead of `[]` / `[:]` to avoid repeated reallocations.
