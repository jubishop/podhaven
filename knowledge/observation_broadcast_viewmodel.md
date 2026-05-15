---
name: Observable + Broadcast observation gap
description: Reading SharedState's @Broadcasted properties through an @Observable viewModel's computed property may silently fail to trigger SwiftUI re-renders, especially for conditional view creation (if let)
type: feedback
originSessionId: b19353f7-b324-4393-a540-258ceaa3b582
---
Reading `sharedState.onDeck` through a computed property on an `@Observable` viewModel (where `sharedState` is `@ObservationIgnored`) caused the PlayBarSheet's share button to never appear. The `if let onDeck = viewModel.onDeck` check silently failed despite onDeck being set.

Theoretically the Broadcast's `access()`/`withMutation()` cycle should propagate through SwiftUI's `withObservationTracking`, but in practice it didn't work reliably for conditional view creation.

**Why:** Root cause unclear. Best theory is the `@Observable` macro's generated `access()` on the computed property getter interferes with SwiftUI tracking the nested Broadcast's `access()`. Other viewModel computed properties reading from the same sharedState (e.g. `isPlaying`, `episodeImage`) work — possibly because they always render something rather than gating view creation with `if let`.

**How to apply:** When a SwiftUI view needs to conditionally create subviews based on a `@Broadcasted` SharedState value, read from SharedState directly in the view (via `@DynamicInjected`) rather than through an `@Observable` viewModel's computed property. Watch for this pattern if other conditional views mysteriously fail to appear.

## Related

- [[factory_v3_migration]] — `@DynamicInjected` resolution and Factory v3 actor-isolation rules; relevant when refactoring a view to read SharedState directly.
