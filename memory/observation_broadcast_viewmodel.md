---
name: observation-broadcast-viewmodel
description: Broadcast notifies SwiftUI synchronously for main-actor writes (#399) and one main-turn late for off-main writes; that timing decides whether a @Broadcasted value can be read through an @Observable viewModel computed property
type: feedback
---
Reading a `@Broadcasted` value through a computed property on an `@Observable` viewModel (where the dependency is `@ObservationIgnored`) re-renders reliably **when the broadcast is written on the main actor**. When the write happens **off** the main actor the notification arrives one main-actor turn late, which is fine for surfaces that always render (ForEach items, text) but can miss conditional view creation (`if let`) and gesture-bound List edits.

**Why:** Pre-#399, `Broadcast.notifyObservers` always deferred the notification to the next main-actor turn, so even main-actor writes landed a runloop turn late — breaking conditional UI (the PlayBar share button never appeared; the EpisodeSwipe delete-minus didn't show on a 1→2 flip) and List-edit gesture transactions. #399 (PR #407) made notification **synchronous for main-actor writes**; off-main writes still hop to main asynchronously, since a background actor can't synchronously touch main.

**How to apply:**
- On-main writer → VM-computed read is fine. `EpisodeSwipeSettingsViewModel.actions` is exactly this: a computed pass-through to `userSettings.episodeSwipeActions` whose List reorder/delete now land within the gesture transaction (it was reverted from a stored-array workaround once #399 landed). No "read it directly in the view" workaround needed.
- Off-main writer feeding an always-rendered surface → also fine. UpNext gates its rec-score sort option on `RecommendationEngine.hasScoringContext`, written off-main in the engine's `.utility` cache-rebuild debounce, and reads it through the viewModel's `allSortMethods` computed into a `Menu`/`ForEach`; the one-turn-late notification just reveals the option a beat later.
- Off-main writer feeding conditional creation (`if let`) or gesture-bound List edits → the risky case. `onDeck` is written from `PlayManager` on `@PlayActor` (off main), so `#399` didn't change its timing and `PlayBarSheet` still reads `sharedState.onDeck` directly in the view. For these, either marshal the write to the main actor or mirror the value into a `@MainActor @Observable` stored property.

Related: [[factory-v3-migration]].
