---
name: Podcast Detail Refactor, Parts 3–6 (planned)
description: Four sibling types (DisplayedPodcast, ListedEpisode, DisplayedEpisode, EpisodeDetailSource/Snapshot) still use the pre-Part-2 existential-wrapper pattern; finish converting them
type: project
originSessionId: 21f04e47-59e3-4372-8975-337554424a19
---
After Part 1 (`787c8817`) and Part 2 (`96260819`) landed, `ListedPodcast` got the explicit-enum treatment (`Source` with three cases, no existential storage, no `as?` downcasts) and `PodcastDetailSource`/`PodcastDetailSnapshot` were collapsed into `PodcastDetailSeed`. The reviewer pass after Part 2 (this memory's origin session) identified four sibling types that still use the pre-Part-2 wrapper pattern and were intentionally left out of scope. They form a coherent backlog.

**Why finish them:** Part 2's stated win was "make illegal states unrepresentable" by replacing `any PodcastListable` storage with an explicit Source enum. The four leftover types use the *same* existential + `@dynamicMemberLookup` + `as?` + `Assert.fatal`-fallback pattern. Leaving them half-converted means new contributors won't know which pattern is the standard, and the downcast helpers still let callers branch on type at runtime instead of through the type system.

**Recommended order (smallest blast radius first):**

1. **Part 3a — `ListedEpisode`** (smallest, mechanical mirror of Part 2)
2. **Part 3b — `EpisodeDetailSource` + `EpisodeDetailSnapshot`** (mechanical mirror of Part 1)
3. **Part 3c — `DisplayedEpisode`**
4. **Part 3d — `DisplayedPodcast`** (widest blast radius — save for last)

Each should be its own focused PR with the Part 2 process: pin public behavior with tests first, convert storage, sweep call sites, run focused tests.

---

## Part 3a: `ListedEpisode` → enum cases

**File:** `PodHaven/Database/DisplayModels/ListedEpisode.swift`

**Current shape:**
- `@dynamicMemberLookup` over `let episode: any EpisodeListable`
- Init has a runtime `Assert.precondition` rejecting `ListedEpisode`/`DisplayedEpisode`/`EpisodeDetailSnapshot`
- Hash/== branch on `getUnsavedPodcastEpisode()` vs `getListablePodcastEpisode()` with `Assert.fatal` fallback
- `getOrCreatePodcastEpisode()` does the same downcast cascade

**Concrete types wrapped:** `UnsavedPodcastEpisode`, `ListablePodcastEpisode` (only two — no bridge type, simpler than `ListedPodcast`)

**How to apply:**
1. Add `enum Source { case saved(ListablePodcastEpisode); case unsaved(UnsavedPodcastEpisode) }`
2. Replace storage with `let source: Source`
3. Move per-case logic onto Source (`canonicalEpisode`, `getOrCreatePodcastEpisode`, case extractors). Mirror the `canonicalPodcast` forwarding pattern used in `ListedPodcast.Source` after the post-Part-2 slim.
4. Drop `@dynamicMemberLookup`, `init(_ episode: any EpisodeListable)`, the `Assert.precondition`, and the `getX()` downcast helpers.
5. Replace hash/== with `hasher.combine(source)` and `lhs.source == rhs.source`.
6. Sweep call sites — replace `ListedEpisode(unsaved)` with `ListedEpisode(unsaved: …)` and downcast helpers with the new computed properties.

**Risk:** Lower than `ListedPodcast` Part 2 — only two cases, no bridge payload, no search-row identity quirk. Should be the easiest of the four.

---

## Part 3b: `EpisodeDetailSource` + `EpisodeDetailSnapshot` → `EpisodeDetailSeed`

**Files:**
- `PodHaven/Database/DisplayModels/EpisodeDetailSource.swift`
- `PodHaven/Database/DisplayModels/EpisodeDetailSnapshot.swift`
- `PodHaven/Views/Episodes/Models/EpisodeDetailViewModel.swift` (consumer)

**Current shape (mirrors pre-Part-1 podcast detail exactly):**
- `EpisodeDetailSnapshot` is a public struct conforming to `EpisodeDisplayable`, built from a `ListedEpisode` via the same downcast cascade
- `EpisodeDetailSource` is a struct with `@DynamicInjected(\.repo)`, two named inits (`init(episode:)`, `init(listedEpisode:)`), and helper methods (`savedEpisode`, `missingSavedResolution`, `deletedObservedPresentation`, `getOrCreatePodcastEpisode`)
- `EpisodeDetailSource` also carries an `unsavedFallback` for the missing-saved-episode resolution flow
- `DisplayedEpisode` references `EpisodeDetailSnapshot` as one of its wrapped types (note: this couples Part 3b to Part 3c)

**How to apply (mirror Part 1 `787c8817`):**
1. Replace `EpisodeDetailSource` with `enum EpisodeDetailSeed { case displayedEpisode(DisplayedEpisode); case listedEpisode(ListedEpisode) }`. The seed exposes `initialEpisode: DisplayedEpisode` (computed) and any state needed for the missing-saved-resolution flow.
2. Make `EpisodeDetailSnapshot` `private` to the seed file and rename to `EpisodeDetailInitialEpisode` (mirroring `PodcastDetailInitialPodcast`).
3. Move the repo-using helpers (`savedEpisode`, `getOrCreatePodcastEpisode`) onto `EpisodeDetailViewModel` directly. The seed becomes a pure value type.
4. The `unsavedFallback` + `missingSavedResolution` + `deletedObservedPresentation` flow needs careful handling — these aren't pure pass-through, they encode the "episode disappeared from DB" recovery logic. Decide whether they live on the view model or stay grouped on the seed.
5. Sweep `EpisodeDetailViewModel` and any other consumer.

**Coupling note:** `DisplayedEpisode` currently has a `getEpisodeDetailSnapshot()` downcast (it wraps the snapshot for the initial-presentation case). After 3b makes the snapshot private, `DisplayedEpisode` either needs the renamed `EpisodeDetailInitialEpisode` to be visible or — better — Part 3c needs to land at the same time so `DisplayedEpisode`'s enum case directly references the (now-private) initial-episode type. Recommend doing 3b and 3c as a paired PR if the coupling is awkward.

---

## Part 3c: `DisplayedEpisode` → enum cases

**File:** `PodHaven/Database/DisplayModels/DisplayedEpisode.swift`

**Current shape:**
- `@dynamicMemberLookup` over `let episode: any EpisodeDisplayable`
- Three-way hash/== branch over `getPodcastEpisode()`, `getUnsavedPodcastEpisode()`, `getEpisodeDetailSnapshot()` with `Assert.fatal` fallback
- `@DynamicInjected(\.repo)` (used in `getOrCreatePodcastEpisode`)

**Concrete types wrapped:** `PodcastEpisode`, `UnsavedPodcastEpisode`, `EpisodeDetailSnapshot`

**How to apply:**
1. Add `enum Source { case saved(PodcastEpisode); case unsaved(UnsavedPodcastEpisode); case initialPresentation(EpisodeDetailSnapshot /* or its renamed/private form after 3b */) }`
2. Same forwarding pattern as `ListedPodcast.Source` after the slim — `canonicalEpisode: any EpisodeDisplayable` helper plus per-case overrides where they differ
3. Drop the three `getX()` downcast helpers
4. Sweep call sites; `getPodcastEpisode()` / `getUnsavedPodcastEpisode()` are used in episode list paths and the play manager

**Coupling:** see Part 3b note about pairing with this if the snapshot type is being renamed.

---

## Part 3d: `DisplayedPodcast` → enum cases

**File:** `PodHaven/Database/DisplayModels/DisplayedPodcast.swift`

**Current shape:**
- `@dynamicMemberLookup` over `let podcast: any PodcastDisplayable`
- Hash/== uses `AnyHashable(podcast)` (post-Part-1 simplification — already cleaner than the others, but still existential)
- `getPodcast()`/`getUnsavedPodcast()` downcasts in `getOrCreatePodcast()`

**Concrete types wrapped:**
- `Podcast` (saved, full-detail)
- `UnsavedPodcast` (preloaded series / parsed feed)
- `PodcastDetailInitialPodcast` (currently `private` to `PodcastDetailSeed.swift` — Part 3d needs to lift it or fold it into the enum)

**How to apply:**
1. Mirror `ListedPodcast.Source`: `enum Source { case saved(Podcast); case unsaved(UnsavedPodcast); case initialPresentation(PodcastDetailInitialPodcast) }`
2. Replace `getPodcast()` / `getUnsavedPodcast()` with computed properties (`var saved: Podcast?`, `var unsaved: UnsavedPodcast?`) that switch on the enum
3. Decide on the forwarding pattern: either explicit per-property switches on Source, or a `canonicalPodcast: any PodcastDisplayable` helper with one-line forwarders (the same tradeoff resolved in `ListedPodcast` — the slim version uses canonicalPodcast)
4. Drop `@dynamicMemberLookup` and the `subscript<T>(dynamicMember:)`
5. Audit call sites of `getPodcast()`/`getUnsavedPodcast()`. `PodcastDetailViewModel.subscribe()` and `episodeList`-related paths are the main consumers; expect a ripple in `PodcastDetailViewModel.swift` and any other view model using these helpers.
6. Keep the existing initialization API (`DisplayedPodcast(Podcast)`, `DisplayedPodcast(UnsavedPodcast)`, `DisplayedPodcast(PodcastDetailInitialPodcast)`) at the call-site level — change the storage, not the surface.
7. `PodcastDetailInitialPodcast` is currently `private` to `PodcastDetailSeed.swift` — Part 3d needs to lift it back to file-internal/file-shared visibility.

**Risk:** `DisplayedPodcast` is reached by far more call sites than `ListedPodcast` (it's the standard "podcast for display" type across the app — view models, episode lists, navigation, share sheets). The conversion itself is mechanical, but the blast radius is wider. Lock down public behavior with tests first, just like Part 2 did. Save for last.

---

## Reference: how the ListedPodcast slim landed

After Part 2, the `Source` enum carried 11 stored properties redundantly with the cases. A follow-up pass (this memory's origin session) shaved those into one-line forwarders backed by a `canonicalPodcast: any PodcastListable` helper on `Source`, plus per-case overrides for `id` (slot identity differs for savedSearchResult) and `searchableString` (uses `originalPodcast` for savedSearchResult). Net: 165 → 144 lines. Pattern to mirror in 3a/3c/3d.

The existential reappears as a transient return value in `canonicalPodcast`, but storage is still the explicit enum — the "make illegal states unrepresentable" goal is preserved. If a future reviewer prefers no existential at all, the alternative is per-property switches on Source (more verbose, ~10 extra lines per type).
