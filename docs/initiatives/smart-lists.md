# Smart Lists

User-editable filter rules replacing the hardcoded `EpisodesView` lists. Design captured 2026-05-05; planning only.

## Context

`EpisodesView` is currently a static hub of 10 hardcoded `NavigationLink`s, each destination instantiating `EpisodesListView` with a hand-written `SQLExpression` filter (`Navigation.swift:191–254`). The structure is already filter-driven — every list is just a different `SQLExpression` fed to the same view model — so generalizing it into user-editable rules is a natural extension rather than a rewrite.

This initiative introduces **Smart Lists**: persisted, editable any/all filter groups with at most **one level of nesting** (a top-level group of conditions plus, optionally, a single sub-group). One level is sufficient — every realistic filter reduces to a top combinator with conditions and at most one group of the opposite combinator inside it. Disallowing deeper recursion keeps the data model, the engine, and the editor UI dramatically simpler. The 10 existing defaults are migrated into seeded `smartList` rows so users can rename/edit/delete them; new lists are created via a `+` toolbar button on `EpisodesView`; each existing list gains a gear toolbar button that opens a full-size configurator sheet. v1 supports text conditions on title/description, episode state conditions, and tag membership conditions. Tags exist independently in two scopes — **episode tags** (via the `episodeTag` join table) and **podcast tags** (via the `podcastTag` join table on the episode's parent podcast) — and the filter must be able to target each scope independently within a single Smart List (e.g., "podcast tagged 'Tech' AND episode tagged 'Interview'"). The two scopes share the same `Tag` table; only the join path differs. `EpisodesView` itself gains an edit mode (mirroring the Queue) for drag-to-reorder of lists; multi-select is **not** part of v1 — delete remains a per-list action inside the editor sheet. The row stores **title + filter + sortMethod**: title and filter are user-editable in the configurator sheet, sortMethod is changed (as today) via the sort toolbar menu in `EpisodesListView` — the only difference is it now persists in SQLite instead of UserDefaults. Per-list-`PersistedBroadcast` sort prefs go away.

The intended outcome: every list visible in `EpisodesView` becomes a row in the new `smartList` table, and the SQL filter for each is generated from a `Codable` filter value at observation time.

---

## Architecture

### 1. Filter shape — `PodHaven/Database/Models/SmartListFilter.swift`

Flat, non-recursive `Codable` value. A top-level `Group` of conditions plus an optional single `Group` nested inside it. Each enum-with-payload uses an explicit `kind` discriminator (mirroring `PodcastsViewType` Codable at `Navigation.swift:142–172`) so adding new condition kinds in v2 cannot break v1 saved JSON.

```swift
struct SmartListFilter: Codable, Hashable, Sendable {
  var combinator: Combinator
  var conditions: [Condition]
  var nested: Group?              // at most one — no further recursion

  struct Group: Codable, Hashable, Sendable {
    var combinator: Combinator
    var conditions: [Condition]
  }

  enum Combinator: String, Codable, Sendable { case all, any }

  enum Condition: Codable, Hashable, Sendable {
    case text(TextField, TextOp, String)
    case state(StateCondition)
    case episodeTag(TagCondition)
    case podcastTag(TagCondition)
  }
  enum TextField: String, Codable, Sendable { case title, description }
  enum TextOp: String, Codable, Sendable { case contains, doesNotContain, equals, startsWith }
  enum StateCondition: String, Codable, Sendable {
    case isQueued, isUnqueued, isFinished, isUnfinished, isStarted, isUnstarted,
         isCached, isSaved, isLoved, isLiked, isDisliked, isNotInterested,
         isRated, isUnrated, wasPreviouslyQueued
  }
  // Shared by both .episodeTag and .podcastTag — only the join path differs at SQL time.
  enum TagCondition: Codable, Hashable, Sendable {
    case hasTag(Tag.ID), doesNotHaveTag(Tag.ID), hasAnyTag, hasNoTags
  }
}
```

`.episodeTag` and `.podcastTag` are deliberately separate `Condition` cases (rather than one `.tag(scope, …)` case) so the discriminator lives at the `Condition` level — same shape as `.text`/`.state`. The shared `TagCondition` payload keeps the four membership predicates (`hasTag`/`doesNotHaveTag`/`hasAnyTag`/`hasNoTags`) defined once. A single Smart List can mix both scopes freely (e.g., a top group with `.podcastTag(.hasTag(techTagID))` AND `.episodeTag(.hasTag(interviewTagID))`).

Custom `init(from:)` / `encode(to:)` on `Condition` and `TagCondition` write a stable `kind` string for each payload variant (`"episodeTag"` and `"podcastTag"` are the two tag discriminators). Decoding an unknown `kind` throws; `SmartListRepo` logs+drops the row so a future-version filter doesn't crash older clients. The outer `SmartListFilter` and inner `Group` use synthesized Codable since their fields are fixed.

### 2. Filter → SQLExpression — `PodHaven/Database/SmartListFilterEngine.swift`

Pure `(SmartListFilter) -> SQLExpression`. Two-level walk only: combine the top group's condition expressions, optionally append the nested group's combined expression as one extra term, then combine again with the top combinator. Reuses existing `Episode` static expressions (`Episode.swift:222–246`) wherever the mapping is direct.

- Combine helper: empty list → `AppDB.NoOp` (`AppDB.swift:65` is `true.sqlExpression`); for `.all`, reduce with `&&`; for `.any`, seed the reduce with the first term (`dropFirst().reduce(first) { $0 || $1 }`) — do **not** seed `||` reduce with `NoOp`, which would short-circuit to true.
- An empty top group with no nested group → `NoOp`. Matches today's "Recent Episodes" semantics.
- State conditions → existing constants: `isLoved` → `Episode.loved`, `isUnqueued` → `Episode.unqueued`, etc. `isSaved` → `Episode.savedInCache` (kept atomic since `saveInCache` isn't user-pickable in v1).
- Text conditions: lowercase compare on both sides via `lower(col) LIKE ?` (matches `Episode.contains` style at `Episode.swift:244–246`). For nullable `description` with `doesNotContain`, emit `(description IS NULL OR lower(description) NOT LIKE ?)` — required because `NOT (NULL LIKE ?)` is NULL, which excludes null-description rows incorrectly. `equals` → `lower(col) = lower(?)`. `startsWith` → escape `%` and `_` in input then `lower(col) LIKE lower(?) || '%'`.
- Tag conditions: subquery via raw `SQL`/`sqlExpression` — `Observatory.listablePodcastEpisodes(filter:order:limit:)` (`Observatory.swift:122–130`) only accepts a flat `SQLExpression` and offers no request-builder overload, so joins are not available. The two scopes use different join tables; pick the SQL by `Condition` case:
  - **`.episodeTag(...)` — joins `episodeTag` on `episode.id`:**
    - `hasTag(id)` → `episode.id IN (SELECT episodeId FROM episodeTag WHERE tagId = ?)`
    - `doesNotHaveTag(id)` → `episode.id NOT IN (...)` (NULL-safe; `episodeTag.episodeId` is NOT NULL)
    - `hasAnyTag` → `EXISTS (SELECT 1 FROM episodeTag WHERE episodeId = episode.id)`
    - `hasNoTags` → `NOT EXISTS (...)`
  - **`.podcastTag(...)` — joins `podcastTag` on `episode.podcastId` (which is nullable, per `Episode.swift:47`):**
    - `hasTag(id)` → `episode.podcastId IN (SELECT podcastId FROM podcastTag WHERE tagId = ?)` — episodes with `podcastId IS NULL` correctly fall out (NULL never matches `IN`).
    - `doesNotHaveTag(id)` → `(episode.podcastId IS NULL OR episode.podcastId NOT IN (SELECT podcastId FROM podcastTag WHERE tagId = ?))` — orphan episodes count as "podcast doesn't have this tag" since there's no podcast to bear the tag.
    - `hasAnyTag` → `EXISTS (SELECT 1 FROM podcastTag WHERE podcastId = episode.podcastId)` — `EXISTS` returns false on NULL `podcastId`, which is the desired semantics (no podcast → no tags).
    - `hasNoTags` → `(episode.podcastId IS NULL OR NOT EXISTS (SELECT 1 FROM podcastTag WHERE podcastId = episode.podcastId))` — orphan episodes count as having no podcast tags.
  - All eight forms are per-row but acceptable for v1; extending Observatory to take a request builder is a follow-up if perf bites.

Per CLAUDE.md, do not use `Optional.map` to project off `nested` — branch with `if let nested = filter.nested { … }` and append the nested combine to the top list before the final combine.

### 3. Migration v43 — `PodHaven/Database/Schema.swift`

String-literals-only per CLAUDE.md. Append after current latest (v42, `Schema.swift:566`):

```swift
migrator.registerMigration("v43") { db in
  let allowedSortMethods = [
    "newestFirst", "oldestFirst", "recentlyAdded",
    "longest", "shortest", "recentlyFinished", "recentlyQueued",
  ]
  try db.create(table: "smartList") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("title", .text).notNull()
    t.column("filter", .text).notNull()                    // JSON
    t.column("displayOrder", .integer).notNull()
    t.column("sortMethod", .text).notNull().defaults(to: "newestFirst")
      .check { allowedSortMethods.contains($0) }
    t.column("creationDate", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
  }
  try db.execute(sql: "CREATE INDEX smartList_displayOrder ON smartList(displayOrder)")

  // Migrate per-title sort prefs from UserDefaults onto the seeded rows, then
  // delete the old keys. PersistedBroadcast stores values as JSON-encoded Data
  // (see v29 migration); for a String-rawValue enum that's `"newestFirst"` etc.
  let defaults = Container.shared.standardDefaults()
  func migratedSortMethod(forTitle title: String) -> String {
    let key = "EpisodesList-sortMethod-\(title)"
    defer { defaults.removeObject(forKey: key) }
    guard let data = defaults.data(forKey: key),
          let raw = try? JSONDecoder().decode(String.self, from: data),
          allowedSortMethods.contains(raw)
    else { return "newestFirst" }
    return raw
  }

  // Then 10 INSERT statements, each using migratedSortMethod(forTitle:) for the
  // sortMethod arg. See "Seeded defaults" below.
}
```

Seed each default with a raw SQL `INSERT` whose `filter` arg is a hand-spelled JSON string literal (no `JSONEncoder`, no model types — string-literals rule) and whose `sortMethod` arg comes from `migratedSortMethod(forTitle:)`. `displayOrder` 0–9 in the order below. None of the defaults need a nested group — all are flat.

| # | Title | Today's filter (Navigation.swift:192–254) | Filter (SmartListFilter shape) |
|---|---|---|---|
| 0 | Recent Episodes | (none) | `combinator: all, conditions: [], nested: nil` |
| 1 | Unqueued | `unqueued && unfinished` | `all, [isUnqueued, isUnfinished], nil` |
| 2 | Cached | `cached` | `all, [isCached], nil` |
| 3 | Saved | `savedInCache` | `all, [isSaved], nil` |
| 4 | Finished | `finished` | `all, [isFinished], nil` |
| 5 | Unfinished | `unfinished && started` | `all, [isUnfinished, isStarted], nil` |
| 6 | Previously Queued | `previouslyQueued` | `all, [wasPreviouslyQueued], nil` |
| 7 | Liked | `liked \|\| loved` | `any, [isLiked, isLoved], nil` |
| 8 | Disliked | `disliked` | `all, [isDisliked], nil` |
| 9 | Not Interested | `notInterested` | `all, [isNotInterested], nil` |

Sample seed JSON for "Liked":
```json
{"combinator":"any","conditions":[
  {"kind":"state","value":"isLiked"},
  {"kind":"state","value":"isLoved"}
],"nested":null}
```

### 4. SmartList model — `PodHaven/Database/Models/SmartList.swift`

Standard PodHaven saved/unsaved pair following `Episode.swift` conventions: an `UnsavedSmartList` value type for in-flight construction, a `SmartList` saved record conforming to GRDB's `FetchableRecord` + `PersistableRecord` + `Identifiable`, with a `Tagged` ID for type-safe IDs across the codebase.

```swift
struct UnsavedSmartList: Codable, Sendable {
  var title: String
  var filter: SmartListFilter
  var displayOrder: Int
  var sortMethod: SmartListSortMethod
}

struct SmartList: FetchableRecord, PersistableRecord, Identifiable, Codable, Hashable, Sendable {
  typealias ID = Tagged<SmartList, Int64>
  let id: ID
  var title: String
  var filter: SmartListFilter
  var displayOrder: Int
  var sortMethod: SmartListSortMethod
  let creationDate: Date

  enum Columns {
    static let id, title, filter, displayOrder, sortMethod, creationDate: Column   // (literal column refs)
  }
}
```

`filter` column is `TEXT` (JSON). Conformance is via a `DatabaseValueConvertible` extension on `SmartListFilter` that encodes/decodes JSON through `JSONEncoder`/`JSONDecoder` — matches how other Codable columns in the project bridge to SQLite TEXT.

`SmartListSortMethod` is the existing `EpisodesListViewModel.SortMethod` lifted out of the view model into its own file (`PodHaven/Database/Models/SmartListSortMethod.swift`) so both the model layer and the view model can refer to it. Same `String, Codable, DefaultsStorable, SortingMethod` conformances and same raw values — wire-compatible with anything currently persisted. The `SortableEpisodeList` protocol and `EpisodesListViewModel` references update to the new top-level name.

### 5. Repo + Observatory

- New repo type: `SmartListRepo`. Follow factory pattern at `Repo.swift:11–16`: `fileprivate init(_ appDB: AppDB)`, registered via `Container` extension with `.scope(.cached)`. Methods: `fetchAll`, `fetchOne`, `insert`, `updateTitle`, `updateFilter`, `updateSortMethod(_:to:)`, `moveSmartList(_:to:)`, `delete`.
- `moveSmartList(_ id: SmartList.ID, to position: Int)` mirrors the renumbering pattern in `Queue._insert` (`Queue.swift:209–220`): inside one write transaction, fetch IDs ordered by `displayOrder`, remove the moved ID, insert at `position` (clamped), then issue per-row `UPDATE smartList SET displayOrder = ? WHERE id = ?` for the affected slice. Simpler than Queue because there's no `queueDate` analog — `displayOrder` is the only field to update.
- `updateSortMethod(_ id: SmartList.ID, to: SmartListSortMethod)` is a single-row `UPDATE smartList SET sortMethod = ? WHERE id = ?`. Called by `EpisodesListViewModel` whenever the user picks a new sort from the toolbar.
- `Observatory.smartLists() -> AsyncValueObservation<[SmartList]>` ordered by `displayOrder ASC, id ASC` — drives the `EpisodesView` hub.
- `Observatory.smartList(_ id: SmartList.ID) -> AsyncValueObservation<SmartList?>` — drives an open `EpisodesListView` so it picks up filter/sortMethod/title changes that come in from the configurator sheet (or from `updateSortMethod` writes by its own toolbar). New entry point alongside the existing collection observation.
- `Observatory.listablePodcastEpisodes(filter:order:limit:)` is unchanged; the VM converts the observed row's filter to `SQLExpression` via `SmartListFilterEngine` at observation start, and re-launches the observation when filter or sortMethod change.

### 6. Navigation refactor — `PodHaven/Environment/Navigation.swift`

- **Delete** `EpisodesViewType` enum (`Navigation.swift:131–134`) and the entire `case .episodesViewType` switch (`Navigation.swift:190–255`).
- **Add** `case smartList(SmartList.ID)` to `Destination`, with handler that resolves the row from a sharedState/repo lookup and instantiates `EpisodesListView(viewModel: EpisodesListViewModel(smartList: row))`. If the ID is missing (e.g., deleted on this device since the navigation path was saved), pop to the EpisodesView root rather than crashing — same defensive shape as the `.tag` fallback at `Navigation.swift:285–301`. The "no SmartLists at all" state (user has deleted every row) is handled at the `EpisodesView` level with an empty state plus the `+` button still in the toolbar.
- The persisted top-destination key (`navigationEpisodesTopDestination`, currently storing `EpisodesViewType` raw) is silently reset on first run after upgrade. Last-viewed-list is acceptable to lose once.

### 7. EpisodesListViewModel — sort moves to the SmartList row, VM observes its row

`EpisodesListViewModel.swift:122–129` currently holds `@PersistedBroadcast var currentSortMethod` keyed by `title`. Both the PersistedBroadcast machinery and the title-keying go away. The new shape:

- The VM is constructed from a `SmartList` row at navigation time (init takes `SmartList`).
- It stores `var smartListID: SmartList.ID` and exposes `var title`, `var filter: SQLExpression`, `var currentSortMethod: SmartListSortMethod` derived from the latest observed row.
- A long-lived task observes `Observatory.smartList(id: smartListID)`. On every emission, the VM updates `title`, `filter` (re-run through `SmartListFilterEngine`), and `currentSortMethod`. If `filter` or `sortMethod` changed, restart the inner episode observation (same `observationKey`-driven mechanism that already exists at `EpisodesListViewModel.swift:115–118`, just extended to include `currentSortMethod`).
- When the user picks a new sort from the toolbar, the VM calls `await smartListRepo.updateSortMethod(smartListID, to: newMethod)`. The Observatory tick reads back through `smartList(id:)` and the VM converges. (No optimistic-local-write needed: the user's pick → DB write → observation tick → UI update round-trip is fast.)

```swift
init(smartList: SmartList) {
  self.smartListID = smartList.id
  self.title = smartList.title
  self.filter = SmartListFilterEngine.sqlExpression(for: smartList.filter)
  self.currentSortMethod = smartList.sortMethod
}
```

This also fixes a latent issue: today, the configurator sheet saving a filter change wouldn't propagate to a currently-displayed `EpisodesListView`. With row observation, it will.

The v43 migration carries existing sort prefs onto the rows, so users see the same sort they had before the upgrade. No PersistedBroadcast keys remain after the migration.

### 8. EpisodesView — `PodHaven/Views/Episodes/EpisodesView.swift`

Replace static NavigationLinks with an observed `List` of `SmartList` rows, supporting edit-mode drag-to-reorder by following `UpNextView`'s pattern:

```swift
List {
  ForEach(viewModel.smartLists) { list in
    NavigationLink(value: Navigation.Destination.smartList(list.id)) {
      Text(list.title)
    }
  }
  .onMove(perform: viewModel.moveSmartList)      // SwiftUI shows native drag handles in editMode
}
.environment(\.editMode, $viewModel.editMode)   // viewModel.editMode is SwiftUI.EditMode
.toolbar {
  ToolbarItem(placement: .primaryAction) {
    AppIcon.addSmartList.labelButton {           // new AppIcon case, plus.circle
      sheet(id: "smart-list-create") {
        SmartListEditorView(viewModel: .init(mode: .create))
      }
    }
  }
  ToolbarItem(placement: .topBarTrailing) {
    if viewModel.editMode == .active {
      AppIcon.editFinished.labelButton { viewModel.editMode = .inactive }
    } else {
      AppIcon.editItems.labelButton { viewModel.editMode = .active }
    }
  }
}
```

`EpisodesViewModel` (new — small `@Observable @MainActor`): owns `var smartLists: [SmartList]`, `var editMode: EditMode = .inactive`, runs `for await rows in observatory.smartLists() { … }`, and exposes `moveSmartList(from: IndexSet, to: Int)` which calls `smartListRepo.moveSmartList(_:to:)` async (same shape as `UpNextViewModel.moveEpisode` at `UpNextViewModel.swift:224–238`). No multi-select state — delete remains inside the editor sheet only.

Add `.addSmartList` case to `AppIcon.swift` (`plus.circle`) — the existing `.subscribe`/`.addTag` cases are semantically loaded. `AppIcon.editItems` and `.editFinished` are already in the catalog.

### 9. EpisodesListView — gear toolbar

Add a `.primaryAction` toolbar item using existing `AppIcon.settings` (gear). Tapping opens the editor sheet in `.edit(smartList.id)` mode.

### 10. Configurator sheet — `PodHaven/Views/Episodes/SmartListEditor/`

- `SmartListEditorViewModel` — `@Observable @MainActor`; owns `var title: String`, `var filter: SmartListFilter`, `mode: .create | .edit(SmartList.ID)`. `save()` validates and calls `smartListRepo.insert` or `smartListRepo.updateTitle`+`updateFilter`. `delete()` for edit mode only.
- `SmartListEditorView` — sheet root; title `TextField` at top; then `SmartListGroupView(top: true, combinator: $vm.filter.combinator, conditions: $vm.filter.conditions)`; then, if `vm.filter.nested` is non-nil, a second `SmartListGroupView(top: false, …)` bound to the nested group with a small destructive "Remove Group" button; otherwise an "Add Group" button. Save/Cancel/Delete actions in toolbar. Uses canonical sheet pattern (`@DynamicInjected(\.sheet)` + `sheet(id:) { … }` from `Sheet.swift` + `PodHavenApp.swift:36`).
- `SmartListGroupView` — **non-recursive**. Renders a segmented `Picker` for `.any/.all`, a `ForEach` of `SmartListConditionRow`s bound to its conditions array, and an "Add Condition" button at the bottom. Top group has padding 0; nested group is indented once (`.padding(.leading, 12)`) and visually distinguished. Group-level buttons differ by position: top group has the "Add Group" button just below it (in the parent view); nested group has a "Remove Group" affordance.
- `SmartListConditionRow` — first picker chooses Kind (Title / Description / State / **Episode Tag** / **Podcast Tag**); subsequent controls swap based on Kind. State picker covers the `StateCondition` cases with human labels. Both tag kinds reuse the same picker UI — they read from the shared `sharedState.tags` and produce a `TagCondition` payload — only the wrapping `Condition` case (`.episodeTag` vs `.podcastTag`) differs, so users can freely combine them within one list (e.g., "Episode Tag is 'Interview' AND Podcast Tag is 'Tech'"). Each row has a leading "−" remove button (matches the screenshot reference shared in the brief).
- Validation: empty title disables Save; empty text-condition value blocks Save with inline error; empty top group with no nested group is allowed (matches `NoOp` semantics) but shows a soft warning ("This list will match every episode").
- Delete is always available in edit mode, behind a `.confirmationDialog`. Seeded defaults are just rows — users can rename, edit, or delete them like any other SmartList.

---

## Critical files

**New:**
- `PodHaven/Database/Models/SmartList.swift`
- `PodHaven/Database/Models/SmartListFilter.swift`
- `PodHaven/Database/Models/SmartListSortMethod.swift` — extracted from `EpisodesListViewModel.SortMethod`
- `PodHaven/Database/SmartListFilterEngine.swift`
- `PodHaven/Database/SmartListRepo.swift`
- `PodHaven/Views/Episodes/Models/EpisodesViewModel.swift` — small VM owning `smartLists` + `editMode` + `moveSmartList`
- `PodHaven/Views/Episodes/SmartListEditor/SmartListEditorView.swift`
- `PodHaven/Views/Episodes/SmartListEditor/SmartListEditorViewModel.swift`
- `PodHaven/Views/Episodes/SmartListEditor/SmartListGroupView.swift`
- `PodHaven/Views/Episodes/SmartListEditor/SmartListConditionRow.swift`
- `PodHavenTests/MigrationTests/v43Tests.swift`
- `PodHavenTests/SmartListFilterEngineTests.swift`
- `PodHavenTests/SmartListFilterCodableTests.swift`
- `PodHavenTests/SmartListRepoTests.swift`

**Modified:**
- `PodHaven/Database/Schema.swift` — register v43 migration with seed inserts
- `PodHaven/Database/Observatory.swift` — add `smartLists()`
- `PodHaven/Environment/Navigation.swift` — delete `EpisodesViewType` + handler, add `smartList(ID)` case
- `PodHaven/Environment/AppIcon.swift` — add `.addSmartList` case
- `PodHaven/Views/Episodes/EpisodesView.swift` — observed `List` of SmartList rows with `.onMove`, `+` and edit toggle toolbar items
- `PodHaven/Views/Episodes/EpisodesListView.swift` — add gear toolbar button
- `PodHaven/Views/Episodes/Models/EpisodesListViewModel.swift` — take `SmartList` in init; observe `Observatory.smartList(id:)` for live row updates; remove `@PersistedBroadcast` sort; persist sort changes through `SmartListRepo.updateSortMethod`

## Reused building blocks

- `Episode.queued`, `unqueued`, `cached`, `savedInCache`, `finished`, `unfinished`, `started`, `unstarted`, `loved`, `liked`, `disliked`, `notInterested`, `rated`, `previouslyQueued` (`Episode.swift:222–246`) — direct mapping for state conditions.
- `AppDB.NoOp` (`AppDB.swift:65`) — empty group sentinel.
- `Observatory._observe(...)` + `ValueObservation.tracking` (`Observatory.swift:266–272`) — observation helper, no changes.
- `Observatory.listablePodcastEpisodes(filter:order:limit:)` (`Observatory.swift:122–130`) — used as-is; engine produces the `SQLExpression` it expects.
- `PodcastsViewType` Codable at `Navigation.swift:142–172` — exact pattern for discriminated-`kind` Codable to mimic.
- Repo factory pattern at `Repo.swift:11–16`.
- Sheet presentation: `@DynamicInjected(\.sheet)` + `sheet(id:) { content }` (`Sheet.swift`, `PodHavenApp.swift:36`).
- `PowerList<ListablePodcastEpisode>` and existing search/sort toolbar in `EpisodesListView` — unchanged, keep working.
- Reorder pattern from `UpNextView.swift:29, 58` (`.onMove(perform:)` + `.environment(\.editMode, $vm.editMode)`) and `UpNextViewModel.swift:224–238` (`moveEpisode(from:to:)` shape). Persistence pattern from `Queue._insert` (`Queue.swift:209–220`) — renumber affected slice in a single write transaction.
- `AppIcon.editItems` / `AppIcon.editFinished` for the edit-mode toolbar toggle (existing cases).

## Test plan

1. **v43 migration test** (`v43Tests.swift`, raw SQL only, follows `v42Tests.swift` pattern): schema columns + types correct (including the `sortMethod` CHECK constraint); `smartList_displayOrder` index exists; exactly 10 rows seeded with distinct titles and displayOrder 0–9; each `filter` parses as JSON via `JSONSerialization` (don't use the model — pin the JSON shape, not its decoder); rows default to `sortMethod = "newestFirst"` when no UserDefaults pref exists; v42 data untouched. **Sort-pref migration sub-test**: pre-seed `EpisodesList-sortMethod-Liked` with the JSON-encoded value `Data("\"recentlyAdded\"".utf8)` and `EpisodesList-sortMethod-Finished` with garbage data into `Container.shared.standardDefaults()` before running the migration; assert the "Liked" row's `sortMethod` is `recentlyAdded` (carried over), the "Finished" row's `sortMethod` is `newestFirst` (garbage rejected, defaulted), all 10 known UserDefaults keys are absent after, and an unrelated key (e.g., `EpisodesList-sortMethod-SomeUserList`) is left untouched.
2. **Filter engine parity test** (`SmartListFilterEngineTests.swift`): for each of the 10 default filters, build the `SmartListFilter` value, run through the engine, and assert the output `SQLExpression` returns the **same episode set** as the existing hardcoded expression on a fixture DB. This is the regression anchor — if engine ever drifts from today's behavior, this fails.
3. **Filter engine edge-case tests**: nullable-description `doesNotContain` matches null rows; one-level-nested `any`-inside-`all` produces correctly parenthesized SQL (fixture designed so wrong precedence yields a different result set); `equals` and `startsWith` are case-insensitive; `startsWith` escapes `%` and `_`. **Tag-scope tests** (run for both `.episodeTag` and `.podcastTag` against the same fixture so divergence is impossible to miss): `hasNoTags` ↔ `hasAnyTag` complementarity; `hasTag` and `doesNotHaveTag` partition the row set correctly. **Tag-scope orphan tests** (`.podcastTag` only, since `episode.podcastId` is nullable): an episode with `podcastId = NULL` is excluded by `hasTag`/`hasAnyTag` and included by `doesNotHaveTag`/`hasNoTags`. **Tag-scope independence test**: a filter combining `.episodeTag(.hasTag(X))` AND `.podcastTag(.hasTag(Y))` matches only episodes whose own row carries tag X *and* whose parent podcast carries tag Y — verify with a fixture that includes episodes where only one of the two tags is present so swapping the join paths would yield a different result set.
4. **Codable round-trip** (`SmartListFilterCodableTests.swift`): each of 10 default filters + a fixture with a non-nil nested group: encode → decode → encode → assert byte-equal. Decoding an unknown `Condition` `kind` throws.
5. **Repo CRUD** (`SmartListRepoTests.swift`): insert / fetchAll / fetchOne / updateTitle / updateFilter / updateSortMethod / delete / `Observatory.smartLists()` emits on insert and on update; `Observatory.smartList(id:)` emits on row update and yields nil after delete.
6. **Repo reorder** (`SmartListRepoTests.swift`): seed 5 rows with displayOrder 0–4; call `moveSmartList(_:to:)` to move row index 0 to position 3, then row index 4 to position 1; assert resulting ordered IDs match the expected sequence; assert `Observatory.smartLists()` emits the new order.
7. **VM live-update** (`EpisodesListViewModelTests/`): construct an `EpisodesListViewModel(smartList:)` against an in-memory DB; mutate the SmartList row's filter via `SmartListRepo.updateFilter`; assert the VM's `filter` and the displayed episode set update via `Wait.until`. Repeat for `updateSortMethod`.
8. **Integration**: observe a SmartList whose filter is `isLoved`; mutate an episode rating to `loved`; assert the row appears via `Wait.until` (no `Task.sleep`, per CLAUDE.md).

Per CLAUDE.md regression-test rule: each engine-edge-case test must be confirmed to **fail against an intentionally-broken engine** (e.g., before adding the null-safe `description` branch) before the fix lands, to prove the test exercises the right behavior.

## Verification (end-to-end)

1. Build clean — zero warnings (CLAUDE.md guardrail).
2. Run full test suite.
3. Launch in simulator:
   - On fresh install: confirm 10 lists appear in `EpisodesView` with names matching the table above; tapping each shows the same episodes as before the migration (sanity).
   - On upgrade install (start from a v42 DB if possible): confirm migration succeeds and all 10 lists are present, and that `Container.shared.standardDefaults()` no longer contains the 10 old `EpisodesList-sortMethod-{title}` keys.
   - Tap `+` on `EpisodesView` → editor sheet opens, can build a one-level-nested filter (e.g., top group ALL with `title contains "AI"` AND a nested ANY group with `loved` OR `liked`), Save → new list appears in hub, tapping shows expected episodes.
   - Tap `+` again and build a mixed-scope filter (e.g., `Podcast Tag is "Tech"` AND `Episode Tag is "Interview"`), Save → list shows only episodes that satisfy *both* scopes (podcast carries Tech, episode itself carries Interview); add a third row toggling the episode-tag clause to a *different* tag and confirm the result set changes accordingly.
   - Tap gear on an existing list → sheet pre-populates with that list's title + filter, edit title → list renames in hub.
   - Edit a seeded list's filter → episode set updates live (verify Observatory reactivity).
   - Tap edit toggle in `EpisodesView` toolbar → drag handles appear; drag-reorder several lists; toggle out of edit mode; relaunch app → reordered list persists.
   - Delete any list (including a seeded one) from inside its editor sheet → list disappears from hub.
4. `swift-format` on every changed Swift file before commit.

## Open follow-ups (not blockers)

- Tag-condition perf via Observatory request-builder overload, if subqueries become a hotspot.
- Multi-select / bulk delete for SmartLists in edit mode, if it becomes desirable later.
