---
name: LogCapture per-test scoping for production-line assertions
description: Why the current process-wide LogCapture is unsafe for "did production log line X fire?" assertions under concurrent Swift Testing, and the task-local sink redesign to use when the first such test arrives.
type: reference
---
`PodHavenTests/LogCapture.swift` is a process-wide, append-only swift-log capture. `LoggingSystem.bootstrap` is one-shot per process and Swift Testing runs cases concurrently, so capture has to be installed once and shared. Today only `FileLogHandlerTests` consumes it, and it filters by a unique discriminator (`#line` in its own log call) — that's safe because each test emits its own messages.

**Trap: `LogCapture` is unsafe for asserting that a *production* log line fired, as written.**

`LogCapture.captured()` is the union of every event emitted in the process. If suite A drives a code path that hits `Self.log.warning("WidgetSnapshotWriter: snapshot missing")` and suite B is running concurrently and matches on `label == "PodHaven/Widget" && message == "WidgetSnapshotWriter: snapshot missing"`, suite B passes — even if its arrange/act produced nothing. False green, worse than a flake. Pre-snapshotting `captured().count` and only inspecting `dropFirst(baseline)` shrinks the window but doesn't close it (sibling tests still race inside the post-baseline window).

You also can't fix this by adding a per-test discriminator into the production message — that violates the "no test-only surface in production code" rule.

**Right fix when the first production-line assertion arrives: scope capture per-test via `@TaskLocal`.**

Swift Testing runs each test as a child task. `@TaskLocal` values propagate into child tasks but are isolated from siblings, mirroring how `FactoryTesting.ContainerTrait` already gives each `@Suite(.container)` test its own `Container.shared` via a task-local. The capturing handler looks up its sink from a task-local; when nothing is set, it drops the event from capture (the multiplexed stderr handler still prints it).

Sketch — replaces today's global `buffer`:

```swift
enum LogCapture {
  struct Captured: Sendable {
    let label: String
    let level: Logging.Logger.Level
    let message: String
    // when this gets implemented, also forward event.source/file/function/line
    // from CapturingLogHandler.log(event:) so call-site assertions are possible
  }

  final class Sink: Sendable {
    private let storage = ThreadSafe<[Captured]>([])
    func append(_ c: Captured) { storage { $0.append(c) } }
    func captured() -> [Captured] { storage() }
  }

  @TaskLocal fileprivate static var current: Sink?

  // Same one-shot bootstrap as today, but the handler reads `current`
  // instead of writing to a global buffer.
  static func installOnce() { /* LoggingSystem.bootstrap MultiplexLogHandler([stderr, CapturingLogHandler()]) */ }

  static func withSink<T>(_ operation: (Sink) async throws -> T) async rethrows -> T {
    let sink = Sink()
    return try await Self.$current.withValue(sink) { try await operation(sink) }
  }
}

private struct CapturingLogHandler: LogHandler {
  // ...
  func log(event: LogEvent) {
    LogCapture.current?.append(.init(
      label: label, level: event.level, message: event.message.description
    ))
  }
}
```

Test usage:

```swift
@Test func logsWhenWidgetSnapshotMissing() async throws {
  try await LogCapture.withSink { sink in
    try await produceConditionThatLogs()
    try await Wait.until {
      sink.captured().contains {
        $0.label == "PodHaven/Widget"
          && $0.level == .warning
          && $0.message == "WidgetSnapshotWriter: snapshot missing"
      }
    }
  }
}
```

A line emitted by another suite's task tree goes into that suite's sink only; this test can't be falsely credited.

**Caveats that still apply:**

- `@TaskLocal`s propagate through `Task { ... }` (structured + unstructured) but **not** through `Task.detached`. Production code using `Task.detached` would emit logs that fall through to a `nil` sink and become invisible to capture. We forbid `Task.detached` in production (see `CLAUDE.md` / `task-detached-migration.md`), so this is a non-issue today; if it ever returns it'll silently break log capture for those code paths.
- Long-lived helpers (Broadcast consumers, Sleepable continuations, etc.) emit on tasks that descend from whoever started them, which during a test is the test itself — they inherit the sink correctly. Anything that survives past the test (e.g. an actor whose work outlasts `withSink`) would have its later emissions dropped from capture, which is the right behavior.
- `swift-log` `Logger` instances bind their `LogHandler` at construction time. `installOnce()` must run before any `Self.log` (typically `static let`) in the file under test is first accessed *anywhere in the process*. Today this is handled by every capturing suite calling `LogCapture.installOnce()` from `init()`. With the per-test sink design this stays the same — `installOnce()` still has to win the bootstrap race; `withSink` only routes events that the always-installed `CapturingLogHandler` is already receiving.
- Today's process-wide buffer is intentionally append-only because no safe per-test clear is possible under concurrent execution. The per-test redesign sidesteps this entirely: each `withSink` gets a fresh `Sink`, no shared mutable buffer.

**When to actually do the rewrite:**

Don't preemptively. Today only `FileLogHandlerTests` uses `LogCapture` and it's safe because every match string carries a unique `line` value the test owns. The first time a test wants to assert "*the* production line at `Foo.swift:NNN` fired", do all of:

1. Add `Sink` + `@TaskLocal current` + `withSink` and have `CapturingLogHandler.log(event:)` write to `current` instead of the global buffer. Drop the global `buffer`.
2. Migrate `FileLogHandlerTests` to `withSink` at the same time so there's only one supported pattern.
3. Extend `Captured` with `event.source` / `event.file` / `event.function` / `event.line` (swift-log already passes them through `LogHandler.log(event:)`); production-line assertions should pin the call site, not just the message string. This also makes the handler future-proof against rewordings.

**Why this design over alternatives considered:**

- *Snapshot-the-buffer-and-diff*: still races inside the post-baseline window if sibling tests can hit the same code path.
- *Per-test discriminator in production messages*: violates "no test-only surface in production"; rejected.
- *Reset the global between tests*: impossible under concurrent execution; would corrupt sibling tests' capture.
- *Per-suite container-keyed sink* (using FactoryKit's `.container` task-local): equivalent in safety but ties log capture to the FactoryKit container lifecycle, which isn't conceptually about logging. The `@TaskLocal` sink stands on its own and works whether or not the test uses `@Suite(.container)`.

## Related

- [[factory_v3_migration]] — same `@TaskLocal`-driven test isolation pattern that FactoryTesting's `ContainerTrait` already uses for `Container.shared`. The `LogCapture` redesign is the same shape applied to swift-log capture.
