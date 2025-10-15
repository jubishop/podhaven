## MCP Usage
- If discussing Swift, SwiftUI, and iOS: Consult the apple-docs-mcp for up to date information.

## Repo Guardrails
- Never create commits or push unless the humans explicitly ask.
- Assume the working tree may hold user edits; respect them and avoid resets or reverts.
- Stay sandbox-friendly: ask for elevated access only when instructions require files outside the workspace.

## Build & Test
- Do not run builds or tests unless the request is explicit.
- Surface meaningful snippets instead of raw command dumps; keep output concise.

## Project Map
- `PodHaven/` – main SwiftUI app. Folders cover Database, Cache, Feed, Play, iTunes (API client and models), Share, Logging, Environment (alerts, navigation, sleepers), Utility (asserts, background tasks), Protocols, PropertyWrappers, UseCases, and modularized Views (e.g., Views/Search).
- `PodHavenTests/` – Swift Testing suites using `Testing` + `FactoryTesting`, in-memory GRDB, and rich fakes for playback, feeds, and downloads.
- `PodHavenMacros/` – local package providing `@Saved` and `@ReadableError` macros plus associated plugins.
- `PodhavenShare/` – share extension that reuses container factories to import feeds, episodes, and OPML files.
- `Tools/` – helper scripts (e.g., RSS validation, targeted test runners).

## Architecture Guide

### Compatibility
- Backward compatibility is not necessary.  Always use the latest features and libraries.

### Database & Persistence
- `AppDB` configures GRDB connections and migrations defined in `Database/Schema.swift` (incremental, versioned).
- Models follow `UnsavedX` + `@Saved<UnsavedX>` patterns from `SavedMacro`; domain types expose GRDB associations and helper SQL expressions.
- Identifiers use `Tagged` wrappers (`Podcast.ID`, `Episode.ID`, `FeedURL`, `MediaGUID`, etc.) for zero-ambiguity IDs.
- `Repo` centralizes DB reads/writes with typed query builder APIs; `Observatory` exposes `AsyncValueObservation` streams for reactive state; `Queue` manages ordering logic with transactional helpers.
- RSS updates rely on `RSSUpdatable` comparisons to retain user state while refreshing feed metadata.

### Observability & View State
- View models adopt `@Observable @MainActor` and stash long-lived tasks in `@ObservationIgnored` properties to avoid observation churn.
- Views trigger async work through `task` modifiers that call `execute()` or feature-specific entry points; cancellation paths clean up ongoing `Task`s via `disappear()` or similar lifecycle methods.
- Selection-heavy flows reuse the `SelectableList` protocol surface with `SelectableListUseCase` as the concrete implementation (see `SelectableEpisodeList` and `SelectablePodcastList` conformers such as `PodcastsListViewModel`) for filtering, sorting, and bulk actions.

### Dependency Injection (FactoryKit)
- Factories live in `Container` extensions; `.scope(.cached)` is the default for singleton-like services.
- Property wrappers: `@DynamicInjected` for lazily cached services, `@InjectedObservable` for observable env objects, `@WrappedShared` for Point-Free `Sharing` backed persistence.
- Use `Container.shared` inside protocols/utilities that need cross-cutting services.
- Override factories with `.context(.preview)` and `.context(.test)` in the Preview and Test extensions; tests leverage `FactoryTesting` to swap in fakes.

### Concurrency Patterns
- Domain-specific actors (`PlayActor`, `FeedActor`) serialize playback and feed fetching; `RefreshManager` fans out refresh jobs using `withThrowingDiscardingTaskGroup`.
- `CacheManager` actor consumes `AsyncValueObservation` streams from `Observatory` and fans out downloads with `withDiscardingTaskGroup`.
- `Sleeper` (via `Sleepable`) provides cancellable debouncing for search view models.
- Always propagate cancellation (`Task.checkCancellation()` / guarding `Task.isCancelled`) before updating state.

### Networking & Feed Processing
- Networking flows conform to `DataFetchable` / `DownloadingTask`; `URLSession` implements both with additional validation helpers.
- `FeedManager` queues background feed downloads through `DownloadManager` and auto-cleans task state; `RefreshManager` fans out refresh jobs using feed + repo coordination.
- `ITunesService` calls iTunes endpoints with async decoding; `ShareService` parses share URLs to import OPML, podcasts, or episodes.

### Playback & Audio
- `PlayManager` (under `PlayActor`) orchestrates AVAudioSession configuration, queue integration, command center wiring, and Point-Free `Sharing` storage of the current episode.
- `PlayState` is an `@Observable @dynamicMemberLookup` mirror of playback status, updated via NotificationCenter streams.
- `ManagingEpisodes` and `SelectableEpisodeList` protocols encapsulate queueing, caching, and playback actions for reuse across views.

### Downloads & Cache
- `CacheManager` actor manages background audio downloads, referencing `CacheBackgroundDelegate` for URLSession callbacks and `CacheState` for progress updates.
- Cached files live under `CacheManager.cacheDirectory`; filenames derive from hashed media URLs, with guardrails preventing deletion for queued/playing episodes.
- `AppDelegate` forwards background session completions to `CacheBackgroundDelegate` ensuring the system resumes suspended tasks correctly.

### Search & Discovery
- `SearchViewModel` drives the search tab by loading iTunes top charts (trending sections) for curated category grids and debouncing search text via `Sleeper` before querying iTunes search with `ITunesService.searchedPodcasts(matching:limit:)`.
- Trending sections are loaded on-demand per genre when selected via `showTrendingSection(_:)` with individual task management; each section tracks its own `LoadingState` and cached podcasts, refreshed via `refreshCurrentTrendingSection()` through pull-to-refresh.
- Views read `currentTrendingSection.state` to mirror the selected section's load/error status for presentation.
- Search results update on debounced text changes via `performSearch()`; `disappear()` cancels outstanding search and trending tasks.

### Navigation & UI Structure
- `Navigation` centralizes all routing using SwiftNavigation's `@CasePathable` destinations and tab-specific path managers conforming to `ManagingNavigationPaths`; switching tabs clears unrelated navigation state via `clearPath()`.
- Tab-specific nested classes (`Navigation.Settings`, `Navigation.Search`, etc.) manage their own `path: [Destination]` arrays; the `Navigation.navigationDestination(for:)` builder renders all possible routes.
- Views stay declarative, forwarding actions to their view models or shared protocols; never introduce business logic inside SwiftUI view structs.
- Custom alert/sheet modifiers (`customAlert`, `customSheet`) consume the injected `Alert`/`Sheet` environment objects.

### Error Handling & Logging
- Error enums conform to `ReadableError`; wrappers adopt `CatchingError` to attach underlying errors automatically.
- `ErrorKit` formats user-facing messages, filters mundane errors, and produces nested logging strings.
- Logging runs through `Log.as(...)` with categories declared in `LogSubsystem`; environment-specific bootstrap occurs in `PodHavenApp.configureLogging()` using `MultiplexLogHandler`, Sentry, OSLog, or Print handlers as appropriate.

### Shared Utilities & Helpers
- `Assert` funnels invariants through structured fatal logging; avoid `fatalError`/`precondition` outside this helper.
- `BackgroundTask`, `ThreadSafe`, `PodFileManager`, and `ImagePipeline` utilities support background refreshes, concurrency-safe storage, and image prefetching.
- Property wrappers (e.g., `OptionalURL`, `WrappedShared`) and protocol extensions (`DataFetchable`, `Searchable`) keep cross-cutting behavior centralized.

## Testing Practice
- Tests use the Swift Testing DSL: `@Suite("…", .container)` with `#expect` assertions; async tests rely on structured concurrency (no sleeps—use `Sleeper`).
- In-memory GRDB (`AppDB.inMemory()`) powers repo tests; helpers under `Create` build realistic unsaved models.
- Override factories with `.context(.test)` to plug in mocks (fake AV players, fake URLSessions, etc.).
- Performance suites live in `PodHavenTests/PerformanceTests` and isolate long-running tasks.
- Preview helpers stub factories for deterministic SwiftUI previews without network calls.

## Coding Standards
- Keep each top-level type in a same-named file; add `// MARK:` separators to outline sections (Initialization, State, Actions, etc.).
- Never force-unwrap (`!`) in production code; use `Assert` or guarded unwraps with readable error handling.
- Prefer triple-quoted strings for multi-line or >100 character literals; use camelCase variables and PascalCase types.
- Maintain alphabetical protocol conformance order and consistent attribute ordering.
- `@ObservationIgnored` guards DI properties and transient state inside observable types.
- Run `swift-format` on every Swift file you touch before handing work back.
- Include `Copyright Justin Bishop, 2025` at the top of all new Swift files.
