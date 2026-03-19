---
description: Audit test files against the project testing policy
argument-hint: [file or directory path to audit, or blank for full test suite]
disable-model-invocation: true
context: fork
---

Audit the specified test files (or the full test suite if no `$ARGUMENTS` provided) against the testing policy below. This skill does **not** run tests — it reviews test code for policy compliance.

## Testing Policy

### Suite declaration

Every test file must use the Swift Testing DSL with `@Suite("…", .container)`:

```swift
@Suite("of SomeFeature tests", .container)
```

- **`.container`** is required for any test that uses dependency injection or the database. It initializes the DI container with test fakes and an in-memory database. Omit `.container` only for pure-logic tests that need no injected dependencies.
- The suite description string should read naturally after "Suite": e.g. `@Suite("of Podcast model tests", .container)`.

### Suite type

Choose the test suite type based on concurrency needs:

- **`actor`** — preferred for async tests with shared mutable state; provides actor isolation without manual synchronization.
- **`@MainActor struct`** — for tests that must run on the main actor (e.g. UI-layer, playback controls).
- **`struct`** — for stateless, independent tests with no shared setup.
- **`class`** — use sparingly; prefer `actor` for shared state.

### Initialization over setUp

Use `init() async throws` for per-test setup — not a `setUp()` method. The initializer runs before each test, making it the right place to insert test data and start managers.

```swift
init() async throws {
  let unsavedPodcast = try Create.unsavedPodcast()
  podcastSeries = try await Container.shared.repo()
    .insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [Create.unsavedEpisode(guid: "ep1")]
      )
    )
  stateManager.start()
}
```

### Test method naming

Use `@Test("descriptive sentence")` with a readable description:

```swift
@Test("that a podcast can be created, fetched, and deleted")
func createAndDeletePodcast() async throws { … }
```

- The description string should describe the expected behavior, not the mechanics.
- The function name should be concise and reflect the test's intent.

### Assertions

Use `#expect` for all assertions — never XCTest's `XCTAssert*`:

```swift
#expect(value == expected)
#expect(value != nil)
#expect(!list.isEmpty)
```

For throwing code:

```swift
await #expect(throws: (any Error).self) {
  try await someThrowingFunction()
}
```

### Parameterized tests

Use the `arguments:` parameter on `@Test` for data-driven tests:

```swift
@Test("playback rate applies correctly", arguments: [0.5, 1.0, 1.5, 2.0])
func playbackRate(_ rate: Double) async throws { … }
```

### No `Task.sleep` — ever

Tests must **never** call `Task.sleep`. This is an absolute rule with no exceptions. Instead:

- **`Wait.until`** — poll until a condition becomes true, with a descriptive failure message:
  ```swift
  try await Wait.until(
    { Container.shared.sharedState().playbackStatus == .playing },
    { "Expected status to be playing, got \(Container.shared.sharedState().playbackStatus)" }
  )
  ```
- **`Wait.forValue`** — poll until an optional becomes non-nil, then return it:
  ```swift
  let onDeck = try await Wait.forValue {
    Container.shared.sharedState().onDeck
  }
  ```

Both default to 1000 attempts with 10ms delays. Override with `maxAttempts:` and `delay:` only when the default is insufficient.

### `sleeper.sleep` for time simulation only

`sleeper.sleep` may appear in tests **only** when the production code under test uses `sleeper.sleep` (e.g. debouncing, rate limiting) and the test needs to advance simulated time:

```swift
let sleeper = Container.shared.sleeper() as! FakeSleeper
try await sleeper.waitForSleepRequests(count: 1)
await sleeper.advanceTime(by: .seconds(3))
```

Never use `sleeper.sleep` as a generic delay mechanism. The pattern is always: wait for the production code to request a sleep, then advance time to complete it.

### Dependency injection

Use `@DynamicInjected` for dependencies:

```swift
@DynamicInjected(\.playManager) private var playManager
@DynamicInjected(\.sharedState) private var sharedState
```

When you need the fake's test-specific API, cast via the container:

```swift
private var avPlayer: FakeAVPlayer {
  Container.shared.avPlayer() as! FakeAVPlayer
}
```

Do not store the cast result in a `@DynamicInjected` property — compute it each time.

### Creating test data

Use `Create` helpers for building models:

- **Unsaved models** (not yet in DB): `Create.unsavedPodcast(...)`, `Create.unsavedEpisode(...)`.
- **Saved models** (inserted into DB): `Create.podcast(...)`, `Create.podcastEpisode(...)`, `Create.twoPodcastEpisodes()`, `Create.threePodcastEpisodes()`.
- **Full series**: Insert via `repo.insertSeries(UnsavedPodcastSeries(...))` when you need a podcast with specific episodes.

Specify only the parameters relevant to the test — let defaults handle the rest.

### Database assertions

Read directly from the database to verify persistence:

```swift
let episode = try await repo.db.read { db in
  try Episode.filter { $0.id == episodeID }.fetchOne(db)
}
#expect(episode?.currentTime == .seconds(10))
```

Use `AppDB.inMemory()` via the `.context(.test)` factory override — never hit a real database.

### Call verification with FakeCallable

All fakes conform to `FakeCallable`. Use its assertion methods to verify interactions:

```swift
let fakeRepo = repo as! FakeRepo

// Verify call count
try fakeRepo.expectCalls(methodName: "updateSeriesFromFeed", count: 1)

// Inspect parameters
let call = try fakeRepo.expectCall(
  methodName: "updateSeriesFromFeed",
  parameters: (podcastSeries: PodcastSeries, podcast: Podcast?).self
)
#expect(call.parameters.podcastSeries.id == expected.id)

// Verify absence
try fakeRepo.expectNoCall(methodName: "delete")

// Reset between test phases
fakeRepo.clearAllCalls()
```

### Test helpers

Use existing domain-specific helpers rather than inlining complex setup:

- **`PlayHelpers`** — `load`, `play`, `pause`, `waitFor(_: PlaybackStatus)`, `waitForOnDeck`, `waitForQueue`, etc.
- **`CacheHelpers`** — `downloadToCache`, `waitForCached`, `simulateBackgroundFinish`, `simulateBackgroundFailure`, etc.
- **`ActorContainer<T>`** — for capturing and waiting on async values.

### Test target membership

- Every test file belongs to **either** `ParallelTests` or `PerformanceTests`, never both.
- Almost all tests go in `ParallelTests`. Use `PerformanceTests` only for benchmarks.
- Xcode auto-adds new files to both targets. Exclude from the wrong target by adding the file's path (relative to `PodHavenTests/`) to the `membershipExceptions` list in the corresponding `PBXFileSystemSynchronizedBuildFileExceptionSet` in `project.pbxproj`.

### Test structure: Create, Act, Assert

Follow this pattern consistently:

```swift
@Test("loading an episode sets it as on-deck")
func loadSetsOnDeck() async throws {
  // Create
  let podcastEpisode = try await Create.podcastEpisode()

  // Act
  try await playManager.load(podcastEpisode)

  // Assert
  try await PlayHelpers.waitForOnDeck(podcastEpisode)
  #expect(sharedState.onDeck?.id == podcastEpisode.id)
}
```

Keep each phase distinct. Avoid interleaving multiple act-assert cycles in a single test unless testing a sequential workflow.

### Error handling in tests

- Tests may use `try` freely — a thrown error fails the test with a clear message, which is the desired behavior.
- Do not wrap test code in `do`/`catch` unless the test specifically needs to verify error behavior.
- Never use `try?` in tests — let failures surface.

### No business logic in tests

Tests should exercise production code, not reimplement it. If a test needs complex setup logic, it belongs in a helper (under `PodHavenTests/Utility/`) or in `Create`.

### Coding standards that apply to tests

- Run `swift-format` on every test file you touch.
- Use `//` for comments, not `///`.
- Use `[weak self]` in closures and Tasks that capture `self`.
- No force-unwraps (`!`) except when casting to known fake types (e.g. `as! FakeRepo`).
- No unused code, properties, or parameters.

## Audit Steps

### Step 1 — Scope

If `$ARGUMENTS` is provided, limit the audit to those files/directories. Otherwise audit all Swift files under `PodHavenTests/`.

### Step 2 — Find all policy sites

Search the scoped files for:
- `Task.sleep` — must never appear in any test file
- `XCTAssert`, `XCTFail`, `XCTUnwrap` — must use `#expect` instead
- `setUp()`, `tearDown()`, `setUpWithError()` — must use `init() async throws` instead
- `try?` — must not appear in tests; let errors propagate
- `@Suite` without `.container` — verify the test genuinely needs no DI
- `Thread.sleep` — must never appear
- Direct `sleeper.sleep` calls — verify they are advancing fake time, not delaying
- Force-unwraps (`!`) — verify they are only on fake casts (`as! FakeSomething`)
- Missing `Wait.until` / `Wait.forValue` — flag any polling loops or artificial delays
- Inline setup logic that should use `Create` helpers or domain helpers

### Step 3 — Evaluate each site

For each site, determine:
1. Does the test follow the **Create, Act, Assert** pattern?
2. Are assertions using **`#expect`** exclusively?
3. Is the suite **type** appropriate (`actor` / `@MainActor struct` / `struct`)?
4. Is **`.container`** present when DI is used, and absent when it's not needed?
5. Are **`Wait.until`** or **`Wait.forValue`** used instead of sleeps or polling loops?
6. Is **`FakeCallable`** used for interaction verification instead of custom tracking?
7. Is the test **target membership** correct (not in both `ParallelTests` and `PerformanceTests`)?
8. Are **test helpers** (`PlayHelpers`, `CacheHelpers`, etc.) used where applicable instead of inline duplication?

### Step 4 — Report

For each violation or improvement found:
1. File path and line number
2. Current code (brief excerpt)
3. Which policy rule is violated
4. Suggested fix

If **no violations** are found, report that the audited tests are compliant.

If you encounter any scenario you're **uncertain** about, stop and ask the user rather than guessing.
