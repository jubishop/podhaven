---
name: playbar-sheet-stuck-off-screen
description: Theory + fix attempt for PlayBar chevron-up tap failing to present a sheet (non-reproducible, 2026-04-26)
type: project
status: resolved
---

# PlayBar sheet stuck off-screen (2026-04-26)

User tapped the chevron-up on the expanded PlayBar (Settings tab) repeatedly with nothing appearing. Confirmed by screen recording. Non-reproducible. The shipped build had no logging in `PlayBar.showPlayBarSheet` or `Sheet.callAsFunction`, so the cause was inferred from surrounding logs, not directly observed.

## Theory of cause

SwiftUI's `.sheet(isPresented:)` only animates a new presentation on `false → true` transitions. The centralized `Sheet` (`PodHaven/Environment/Sheet.swift`) derived `isPresented` from `config != nil` via `customSheet`. If `config` was stuck non-nil while the visual sheet was already gone (state desync — e.g. the dismissal binding-setter never fired during a scene-phase transition), subsequent `sheet { ... }` calls would replace `config` but `isPresented` would stay at `true` and SwiftUI would see no edge.

Suspected trigger from same-morning logs: a 7-second window with two `activated` scene-phase events (09:17:26.456 and 09:17:33.666) without an intervening `backgrounded`, plus an `EpisodeDetailViewModel.performAppear() → disappear()` flicker at 09:17:27-28 (episode 27333, "A.I. Backlash…"). A brief EpisodeDetail sheet visually dismissed during the chaotic scene transition could have left `Sheet.config` non-nil. The chevron-up taps at ~09:17:35 then no-op'd at the SwiftUI level.

## Fix attempted

PR on `worktree-sheetFixes` (commit `ace7020b`): switched the centralized `Sheet` to SwiftUI's identity-driven `.sheet(item:)` with `Identifiable SheetConfig` (`id = UUID()` fresh per presentation, plus `userID: AnyHashable?` preserving the existing same-id dedup). SwiftUI re-presents on any item id change — non-nil → non-nil included — so the bool-transition desync class is eliminated entirely.

Also added logging on the Sheet path and the three standalone `.sheet(...)` call sites that bypass it (`OPMLView`, `PodcastDetailView`, `SearchView`) so the next repro is fully observable.

`Alert` was left as the original — SwiftUI has no `.alert(item:)` overload, but alerts are button-dismissed (binding setter always fires) so the desync risk there is mostly theoretical.

**Why:** Theory is unconfirmed because the bug is non-reproducible. The fix is forward-looking insurance against a class of state desync, and `.sheet(item:)` is also more idiomatic SwiftUI.

**How to apply:** If "tap doesn't present a sheet" recurs: (1) check the new Sheet logs first — a `present` line followed by no visible sheet means SwiftUI swallowed the presentation, indicating either a regression in `customSheet` (no longer using `.sheet(item:)`) or another sheet modifier blocking iOS's single-modal slot; (2) the standalone `.sheet(...)` sites in OPMLView/PodcastDetailView/SearchView have their own bindings — check them separately; (3) if the new tap logs are absent across attempts, the issue is button hit-testing, not sheet state.
