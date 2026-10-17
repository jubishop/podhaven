---
name: "task-detached-migration"
description: "Why `Task.detached` is banned and how to hop off `@MainActor` for CPU work without it."
type: "reference"
---

# `Task.detached` migration pattern

`Task.detached` is banned in this codebase. It strips priority, cancellation, and actor inheritance from the spawned task, producing orphan work that's invisible to the parent. Default to `Task { ... }` (and store the handle when the task outlives the call).

## The legitimate use case it was hiding: hopping off `@MainActor` for CPU work

The reason `Task.detached` typically gets reached for is to escape `@MainActor` so a hot CPU loop doesn't run on the main thread. There's a better way that preserves priority, cancellation, and the structured-concurrency chain.

**Pattern:** mark the CPU work `@concurrent`: a static method on an `enum`, or a method on a `Sendable` type. `await`-ing it from `@MainActor` runs the body off the caller's actor, while priority, cancellation, and the parent task's lineage all flow through. `EmbeddingService.podcastContextVector` and `RecommendationEngine.similarityScores` use this form.

This project sets `SWIFT_APPROACHABLE_CONCURRENCY = YES` with `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` (`PodHaven.xcodeproj/project.pbxproj`). Under that setting, a plain `nonisolated async` function runs on its caller's actor, not the cooperative pool, so it does not move CPU work off the main actor. Use `@concurrent` for that.

```swift
enum Heavy {
  @concurrent static func crunch(_ data: Data) async -> Result {
    // CPU work runs off the caller's actor.
    ...
  }
}

@MainActor
func onSomething() {
  Task { [weak self] in
    guard let self else { return }
    let result = await Heavy.crunch(self.payload)
    self.applyResult(result)
  }
}
```

## Why not `Task.detached`?

- **Priority is lost.** The detached task starts at default priority regardless of what the caller wanted.
- **Cancellation is severed.** The parent task can't cancel it, and `Task.checkCancellation()` inside checks a fresh cancellation slot.
- **Actor inheritance is dropped.** You have to manually `MainActor.run { }` to come back, and that hop is observable to SwiftUI/observation tracking.
- **It's invisible to the parent.** Structured concurrency was designed so the parent waits or cancels children; detached escapes that. The orphan can outlive the screen, the user, and any reasoning about lifetimes.

## Related

- [factory-v3-migration](factory-v3-migration.md) — actor-isolation rules for Factory-resolved types, where many `@MainActor` / cooperative-pool boundary issues surface.
