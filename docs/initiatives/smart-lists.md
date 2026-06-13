---
status: shipped
---

# Smart Lists

User-editable filter rules replacing the hardcoded `EpisodesView` lists. Design captured 2026-05-05; revised 2026-06-04 (schema now at v53, condition set expanded, scrub-on-tag-delete, two-phase build); revised 2026-06-12 (multiple nested groups, v56 migration, inline group editing — see §1/§2/§3a/§10); revised 2026-06-12 (swipe/edit-mode delete on the hub list).

## Context

`EpisodesView` is currently a static hub of 10 hardcoded `NavigationLink`s inside a `Form` (`EpisodesView.swift:10–56`), each pointing at an `EpisodesViewType` case whose destination instantiates `EpisodesListView` with a hand-written `SQLExpression` filter (`Navigation.swift:193–258`). The structure is already filter-driven — every list is just a different `SQLExpression` fed to the same view model — so generalizing it into user-editable rules is a natural extension rather than a rewrite.

This initiative introduces **Smart Lists**: persisted, editable any/all filter groups with at most **one level of nesting** — a top-level group of conditions plus any number of sub-groups, each holding only conditions. One level is sufficient — every realistic filter reduces to a top combinator over conditions and condition-groups. Disallowing deeper recursion keeps the data model, the engine, and the editor UI dramatically simpler. (v1 allowed at most a single sub-group; the 2026-06-12 revision lifted that to an array.) The 10 existing defaults are migrated into seeded `smartList` rows so users can rename/edit/delete them; new lists are created via a `+` toolbar button on `EpisodesView`; each existing list gains a gear toolbar button that opens a full-size configurator sheet.

v1 supports **seven condition kinds**: episode text (title/description), **podcast text** (parent podcast title/description), episode state, episode-tag membership, podcast-tag membership, **duration range**, and **publish-date age**. Tags exist independently in two scopes — **episode tags** (via the `episodeTag` join table) and **podcast tags** (via the `podcastTag` join table on the episode's parent podcast) — and the filter must be able to target each scope independently within a single Smart List (e.g., "podcast tagged 'Tech' AND episode tagged 'Interview'"). The two scopes share the same `Tag` table; only the join path differs.

`EpisodesView` itself gains an edit mode (mirroring the Queue) for drag-to-reorder of lists; multi-select is **not** part of v1. Delete is available two ways: a custom trash swipe action on the hub rows (not `.onDelete` — its optimistic row-removal animation makes the row flicker when a confirmation gates the actual delete) and the Delete button inside the editor sheet — both confirmed via the injected `alert` (the same Delete/Cancel alert tag deletion uses), since a mistaken delete throws away a hand-built filter. The row stores **title + filter + sortMethod**: title and filter are user-editable in the configurator sheet, sortMethod is changed (as today) via the sort toolbar menu in `EpisodesListView` — the only difference is it now persists in SQLite instead of UserDefaults. Per-list-`PersistedBroadcast` sort prefs go away.

When a `Tag` is deleted, every Smart List filter that references it is **scrubbed in the same write transaction** (decode → drop the matching `.episodeTag`/`.podcastTag` conditions → re-encode → update). List cardinality is low, so this is cheaper than building an "unknown tag" placeholder state in the editor. The engine and editor remain **defensive** anyway — a tag ID that fails to resolve matches nothing rather than crashing — to cover cross-device / mid-delete races.

The intended outcome: every list visible in `EpisodesView` becomes a row in the new `smartList` table, and the SQL filter for each is generated from a `Codable` filter value at observation time.

### Build sequencing — two phases

The migration replaces the entire `EpisodesView` hub, so the work lands as two independently-reviewable PRs:

- **Phase 1 — data + engine (dormant).** Model, `@Saved` macro, `SmartListFilter`, `SmartListFilterEngine`, `SmartListSortMethod`, the v54 migration (creates + seeds the table), `SmartListRepo`, the two new `Observatory` entry points, the `DatabaseValueConvertible` bridge, the scrub-on-tag-delete hook, and the full test suite. The existing `EpisodesView` / `EpisodesViewType` hub is **left untouched** — the table is seeded but nothing reads it yet, so Phase 1 ships green on its own.
- **Phase 2 — UI swap.** Rewrite `EpisodesView` as an observed `List` with reorder + `+`, repoint `Navigation` to `smartList(ID)`, rebuild `EpisodesListViewModel` to take a `SmartList` and observe its row, add the gear toolbar + editor sheet, and delete `EpisodesViewType` and its switch. A v55 migration **re-copies** each `EpisodesList-sortMethod-*` UserDefaults pref onto its matching row (by title) and only then removes the now-orphaned keys, with GRDB guaranteeing the single run.

**Why Phase 1 copies but does not delete the old sort-pref keys:** if Phase 1 reaches users before Phase 2, the old `EpisodesListView` still reads — and **writes** — `EpisodesList-sortMethod-{title}`. So the v54 migration *copies* those prefs onto seeded rows but leaves the keys in place; Phase 2 — which removes the old reader — deletes them. Shipped migrations are immutable, so the destructive cleanup belongs in Phase 2's own v55 migration, not v54. Because sort changes made between the two releases land only in UserDefaults (nothing syncs them onto rows in Phase 1), v55 must **re-copy each key's value onto its row before deleting the key** — matching by title is reliable there since lists can't be renamed until Phase 2's editor ships.

---

## Architecture

### 1. Filter shape — `PodHaven/Database/Models/SmartListFilter.swift`

Flat, non-recursive `Codable` value. A top-level `Group` of conditions plus an array of `Group`s nested inside it. Each enum-with-payload uses an explicit `kind` discriminator (mirroring `PodcastsViewType` Codable at `Navigation.swift:137–174`) so adding new condition kinds in v2 cannot break v1 saved JSON.

```swift
struct SmartListFilter: Codable, Hashable, Sendable {
  var combinator: Combinator
  var conditions: [Condition]
  var groups: [Group]             // one level deep — no further recursion

  struct Group: Codable, Hashable, Sendable {
    var combinator: Combinator
    var conditions: [Condition]
  }

  enum Combinator: String, Codable, Sendable { case all, any }

  enum Condition: Codable, Hashable, Sendable {
    case episodeText(TextField, TextOp, String)  // episode title / description
    case podcastText(TextField, TextOp, String)  // parent podcast title / description
    case state(StateCondition)
    case episodeTag(TagCondition)
    case podcastTag(TagCondition)
    case duration(minSeconds: Int?, maxSeconds: Int?)   // inclusive; nil = open-ended
    case publishDate(PublishDateOp, days: Int)
  }

  enum TextField: String, Codable, Sendable { case title, description }   // shared by episodeText + podcastText
  enum TextOp: String, Codable, Sendable { case contains, doesNotContain, equals, startsWith }
  enum PublishDateOp: String, Codable, Sendable { case withinLast, olderThan }

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

`.episodeTag` and `.podcastTag` are deliberately separate `Condition` cases (rather than one `.tag(scope, …)` case) so the discriminator lives at the `Condition` level — same shape as `.episodeText`/`.state`. The shared `TagCondition` payload keeps the four membership predicates defined once. Likewise `.episodeText` and `.podcastText` are separate cases sharing the `TextField`/`TextOp` payloads. A single Smart List can mix scopes freely (e.g., a top group with `.podcastText(.title, .contains, "Tech")` AND `.episodeTag(.hasTag(interviewTagID))`).

Custom `init(from:)` / `encode(to:)` on `Condition` and `TagCondition` write a stable `kind` string for each payload variant (`"episodeText"`, `"podcastText"`, `"state"`, `"episodeTag"`, `"podcastTag"`, `"duration"`, `"publishDate"`). Decoding an unknown `kind` throws, which surfaces as a thrown error from the repo/observation read paths — the migration's CHECK guards the JSON shape at write time, and every production write encodes from a typed value, so an undecodable row is unreachable without an app downgrade. (If Smart Lists ever sync across devices, tolerant log+drop row decoding becomes a requirement.) The outer `SmartListFilter` and inner `Group` use synthesized Codable since their fields are fixed.

`SmartListFilter` also exposes a pure `func removingTag(_ id: Tag.ID) -> SmartListFilter` that strips every `.episodeTag`/`.podcastTag` condition whose `TagCondition` carries `id` (in the top group and every nested group, dropping a group emptied by the scrub), returning a value with the same combinators. Used by the scrub-on-delete path (§5).

### 2. Filter → SQLExpression — `PodHaven/Database/SmartListFilterEngine.swift`

Pure `(SmartListFilter, referenceDate: Date) -> SQLExpression`. The `referenceDate` parameter exists so relative `.publishDate` windows are computed deterministically (production passes `Date()`; tests pass a fixed date — keeps the engine pure and testable). Two-level walk only: combine the top group's condition expressions, append each non-empty nested group's combined expression as one extra term, then combine again with the top combinator. Reuses existing `Episode` static expressions (`Episode.swift:234–248`) wherever the mapping is direct.

- **Combine helper:** empty list → `AppDB.noOp` (`AppDB.swift:88` is `true.sqlExpression`); for `.all`, reduce with `&&`; for `.any`, seed the reduce with the first term (`dropFirst().reduce(first) { $0 || $1 }`) — do **not** seed `||` reduce with `noOp`, which would short-circuit to true.
- An empty top group with no nested groups → `noOp`. Matches today's "Recent Episodes" semantics.
- **State conditions** → existing constants: `isQueued`→`Episode.queued`, `isUnqueued`→`Episode.unqueued`, `isFinished`→`Episode.finished`, `isUnfinished`→`Episode.unfinished`, `isStarted`→`Episode.started`, `isUnstarted`→`Episode.unstarted`, `isCached`→`Episode.cached`, `isSaved`→`Episode.savedInCache`, `isLoved`→`Episode.loved`, `isLiked`→`Episode.liked`, `isDisliked`→`Episode.disliked`, `isNotInterested`→`Episode.notInterested`, `isRated`→`Episode.rated`, `isUnrated`→`!Episode.rated`, `wasPreviouslyQueued`→`Episode.previouslyQueued`. (`isSaved`→`Episode.savedInCache` kept atomic since `saveInCache` isn't separately user-pickable in v1.)
- **Episode text conditions** (`.episodeText`): GRDB column expressions, not raw SQL. `contains`/`startsWith` use `column.like(_:escape:)` with `%`/`_`/`\` escaped in the user input so only the added wildcards are wildcards; SQLite `LIKE` is ASCII case-insensitive, so no `lower()` is needed. `equals` uses `column.collating(.nocase) == value`. For nullable `description` with `doesNotContain`, emit `column == nil || !column.like(...)` — required because `NOT (NULL LIKE ?)` is NULL, which would drop null-description rows.
- **Podcast text conditions** (`.podcastText`): `Observatory.listablePodcastEpisodes(filter:)` takes only a flat `SQLExpression`, so route through the parent podcast with a `Podcast.select(id).filter(<predicate>).contains(Episode.Columns.podcastId)` subquery instead of a join (GRDB auto-aliases the subquery's `podcast`, isolating it from the request's joined `podcast`). `episode.podcastId` is NOT NULL (FK with cascade delete) and `podcast.id` is the primary key, so `IN`/`NOT IN` membership is null-safe and no orphan branch is needed.
  - `contains`/`startsWith`/`equals` reuse the same `like(_:escape:)` / `collating(.nocase)` predicates as the episode case, wrapped in the membership subquery.
  - `doesNotContain` negates the membership (`!matches`), which also keeps podcasts whose text is null — they never match the inner `LIKE`, so they fall outside the matched set.
- **Tag conditions** — GRDB membership subqueries (no raw SQL); pick the request by `Condition` case. Both `episodeTag.episodeId` and `episode.podcastId` are NOT NULL, so plain `IN`/`NOT IN` membership is null-safe and there are no orphan branches:
  - **`.episodeTag(...)`** — `EpisodeTag.select(episodeId)` (filtered by `tagId` for `hasTag`/`doesNotHaveTag`) `.contains(Episode.Columns.id)`, negated for `doesNotHaveTag`/`hasNoTags`.
  - **`.podcastTag(...)`** — `PodcastTag.select(podcastId)` (same shape) `.contains(Episode.Columns.podcastId)`, negated for the complements.
  - A `hasTag`/`doesNotHaveTag` whose `Tag.ID` no longer resolves is left as-is; the empty subquery makes `hasTag(missing)` match nothing and `doesNotHaveTag(missing)` match everything — both safe. (Scrub-on-delete normally removes these first; this is the defensive fallback.)
- **Duration conditions** (`.duration(minSeconds:maxSeconds:)`): `episode.duration` is stored as **seconds (Double)** (`CMTime.databaseValue` → `seconds.databaseValue`, `CMTime.swift:94–105`). Inclusive bounds — `duration >= Double(minSeconds)` AND/or `duration <= Double(maxSeconds)`; a `nil` bound is open-ended (both nil → no-op). Note unknown-duration rows store `0`, so `minSeconds: 0` includes them and any positive `minSeconds` excludes them.
- **Publish-date conditions** (`.publishDate(op, days:)`): cutoff = `referenceDate - days × 86,400s` (flat seconds, no calendar arithmetic). `withinLast` → `Episode.Columns.pubDate >= cutoff`; `olderThan` → `< cutoff`. Caveat: the cutoff is fixed when the display observation (re)starts (filter/sort/search change, or app session), not continuously re-evaluated — acceptable for v1.

Loop `for group in filter.groups where !group.conditions.isEmpty { … }` and append each group's combine to the top list before the final combine.

### 3. Migration v54 — `PodHaven/Database/Migrations/Migration_v54.swift`

Migrations are no longer inline in `Schema.swift`; each is a `migrateV{n}` static func in its own `Migration_v{n}.swift` file, registered by one line in `Schema.makeMigrator()` (`Schema.swift:29–66`, currently registered through v53). Add `migrator.registerMigration("v54", migrate: migrateV54)` and the new file. String-literals-only per CLAUDE.md.

```swift
extension Schema {
  static func migrateV54(_ db: Database) throws {
    let allowedSortMethods = [
      "newestFirst", "oldestFirst", "recentlyAdded",
      "longest", "shortest", "recentlyFinished", "recentlyQueued",
      "recommendationScore",
    ]
    try db.create(table: "smartList") { t in
      t.autoIncrementedPrimaryKey("id")
      t.column("title", .text).notNull()
      t.column("filter", .text).notNull().check(  // JSON, top-level shape guarded
        sql: """
          json_valid(filter)
          AND json_type(filter) = 'object'
          AND json_type(filter, '$.combinator') IS 'text'
          AND json_type(filter, '$.conditions') IS 'array'
          AND (
            json_type(filter, '$.nested') IS NULL
            OR json_type(filter, '$.nested') IN ('null', 'object')
          )
          """
      )
      t.column("displayOrder", .integer).notNull()
      t.column("sortMethod", .text).notNull().defaults(to: "newestFirst")
        .check { allowedSortMethods.contains($0) }
      t.column("creationDate", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
    }
    try db.create(index: "smartList_on_displayOrder", on: "smartList", columns: ["displayOrder"])

    // Copy per-title sort prefs from UserDefaults onto the seeded rows. Do NOT
    // delete the keys here — the old EpisodesListView still reads them until
    // Phase 2 ships (see "Build sequencing"). PersistedBroadcast stores values
    // as JSON-encoded Data (DefaultsStorable); a String-rawValue enum is the
    // JSON string `"newestFirst"` etc.
    let defaults = Container.shared.standardDefaults()
    func migratedSortMethod(forTitle title: String) -> String {
      let key = "EpisodesList-sortMethod-\(title)"
      guard let data = defaults.data(forKey: key),
            let raw = try? JSONDecoder().decode(String.self, from: data),
            allowedSortMethods.contains(raw)
      else { return "newestFirst" }
      return raw
    }

    // Then 10 INSERT statements, each using migratedSortMethod(forTitle:) for the
    // sortMethod arg. See "Seeded defaults" below.
  }
}
```

The `allowedSortMethods` list now includes `"recommendationScore"` (the `SortMethod` enum gained that case after the original design; Smart Lists persist it like any other sort).

Seed each default with a raw SQL `INSERT` whose `filter` arg is a hand-spelled JSON string literal (no `JSONEncoder`, no model types — string-literals rule) and whose `sortMethod` arg comes from `migratedSortMethod(forTitle:)`. `displayOrder` 0–9 in the order below. None of the defaults need a nested group — all are flat.

| # | Title | Today's filter (`Navigation.swift:193–258`) | Filter (SmartListFilter shape) |
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

### 3a. Migration v56 — multiple nested groups (2026-06-12 revision)

The v1 JSON stored at most one sub-group under a `nested` key (guarded by v54's CHECK as null/object). Lifting the limit moves the shape to a required `groups` **array**. SQLite cannot alter a CHECK constraint, so `Migration_v56` rebuilds `smartList`: it creates `smartList_new` with the same columns but a CHECK requiring `json_type(filter, '$.groups') IS 'array'`, copies every row with the filter converted in SQL (`nested` object → `json_array(filter -> '$.nested')` under `groups`; null/absent `nested` → `[]`; the `nested` key removed), drops the old table, renames, and recreates `smartList_on_displayOrder`. The `->` operator (not `->>`) keeps the extracted sub-group real JSON inside `json_array`. Because every row is rewritten and every production write encodes from the typed value, the decoder requires `groups` and does not tolerate the pre-v56 shape. v54's section above is historical — its CHECK and seed literals shipped with `nested` and are immutable.

### 4. SmartList model — `PodHaven/Database/Models/SmartList.swift`

Use the project's `@Saved<Unsaved…>` macro (as `Tag`/`Episode` do), not a hand-written pair. The macro generates `typealias ID = Tagged<SmartList, Int64>`, `let id`, `let creationDate`, `var unsaved`, and the GRDB `FetchableRecord`/`PersistableRecord` conformances (via `Savable`/`Saved` at `PodHaven/Database/Protocols/`). `UnsavedSmartList` conforms to `Savable` (which is `Codable, Hashable, FetchableRecord, PersistableRecord, Searchable, Sendable, Stringable`) and `Identifiable`.

```swift
struct UnsavedSmartList: Identifiable, Savable {
  var id: Self { self }               // no database id yet — the value is its own identity
  static let databaseTableName = "smartList"

  var title: String
  var filter: SmartListFilter
  var displayOrder: Int
  var sortMethod: SmartListSortMethod

  var toString: String { title }
  var searchableString: String { title }
}

@Saved<UnsavedSmartList>
struct SmartList: Saved {
  enum Columns {
    static let id = Column("id")
    static let title = Column("title")
    static let filter = Column("filter")
    static let displayOrder = Column("displayOrder")
    static let sortMethod = Column("sortMethod")
    static let creationDate = Column("creationDate")
  }

  // Derived passthroughs
  var title: String { unsaved.title }
  var filter: SmartListFilter { unsaved.filter }
  var displayOrder: Int { unsaved.displayOrder }
  var sortMethod: SmartListSortMethod { unsaved.sortMethod }
}
```

The `filter` column is `TEXT` (JSON). Conformance is via a `DatabaseValueConvertible` extension on `SmartListFilter` that encodes/decodes JSON through `JSONEncoder`/`JSONDecoder` — matches how other Codable columns bridge to SQLite TEXT. `sortMethod` is a `String`-rawValue Codable enum, which GRDB persists as its raw `TEXT` automatically. Like `UnsavedTag`, the `UnsavedSmartList` initializer trims the title and throws on empty/whitespace-only input; `SmartListRepo.updateTitle` applies the same guard (mirroring `Repo.renameTag`).

### 4a. SmartListSortMethod — `PodHaven/Database/Models/SmartListSortMethod.swift`

`EpisodesListViewModel.SortMethod` is lifted out of the view model into its own top-level data-layer type so both the model layer and the view model can refer to it. Same eight cases — `newestFirst, oldestFirst, recentlyAdded, longest, shortest, recentlyFinished, recentlyQueued, recommendationScore` — with the same raw values, keeping `sqlOrdering`/`sqlFilter` and gaining `DatabaseValueConvertible` (rawValue → `sortMethod` column). The UI affordances stay out of `Database/`: `appIcon` and the `SortingMethod` conformance live in the View-layer extension `PodHaven/Views/Episodes/Models/SmartListSortMethod+SortingMethod.swift`. `DefaultsStorable` is **retained** for Phase 1 — the existing VM still persists sort via `@PersistedBroadcast` — and gets dropped in Phase 2 along with the old keys.

### 5. Repo + Observatory

- **New repo type: `SmartListRepo`.** Follow the factory pattern at `Repo.swift:11–15` / `Observatory.swift:8–14`: `fileprivate init`, registered via a `Container` extension with `.scope(.cached)`, holding `AppDB.Writer`/`Reader`. Methods: `fetchAll`, `fetchOne`, `insert`, `updateTitle`, `updateFilter`, `updateSortMethod(_:to:)`, `moveSmartList(_:to:)`, `delete`.
- `moveSmartList(_ id: SmartList.ID, to position: Int)` renumbers in one write transaction using SwiftUI's original-list destination offset: fetch IDs ordered by `displayOrder`, find the source index, convert downward moves to the post-removal insertion index, remove the moved ID, insert at the clamped destination, then issue per-row `UPDATE smartList SET displayOrder = ? WHERE id = ?` for the affected slice.
- `updateSortMethod(_ id: SmartList.ID, to: SmartListSortMethod)` is a single-row `UPDATE smartList SET sortMethod = ? WHERE id = ?`. Called by `EpisodesListViewModel` whenever the user picks a new sort from the toolbar.
- **Scrub-on-tag-delete.** `Repo.deleteTag(_:)` (`Repo.swift:348–355`) currently deletes the `Tag` row in a single `writer.write`. Extend that same transaction to scrub Smart Lists: fetch all `SmartList` rows, compute `row.filter.removingTag(tagID)` (§1), and `UPDATE smartList SET filter = ? WHERE id = ?` for any row whose filter changed. Keeping it inside the existing `deleteTag` write block makes the delete + scrub atomic and reuses the model layer (Repo already depends on every model). The `Observatory.smartLists()` observation re-emits automatically.
- `Observatory.smartLists() -> AsyncValueObservation<[SmartList]>` ordered by `displayOrder ASC, id ASC` — drives the `EpisodesView` hub.
- `Observatory.smartList(_ id: SmartList.ID) -> AsyncValueObservation<SmartList?>` — drives an open `EpisodesListView` so it picks up filter/sortMethod/title changes from the configurator sheet (or from its own `updateSortMethod` writes).
- `Observatory.listablePodcastEpisodes(filter:order:limit:)` (`Observatory.swift:127–137`) is unchanged; the VM converts the observed row's filter to `SQLExpression` via `SmartListFilterEngine` at observation start, and re-launches the observation when filter or sortMethod change.

### 6. Navigation refactor — `PodHaven/Environment/Navigation.swift` (Phase 2)

- **Delete** `EpisodesViewType` enum (`Navigation.swift:132–135`) and the entire `case .episodesViewType` switch (`Navigation.swift:193–258`).
- **Add** `case smartList(SmartList.ID)` to `Destination`, with a handler that resolves the row (from a `sharedState`/repo lookup) and instantiates `EpisodesListView(viewModel: EpisodesListViewModel(smartList: row))`. If the ID is missing (deleted since the path was built), pop to the `EpisodesView` root rather than crashing — same defensive shape as the `.tag` fallback at `Navigation.swift:287–304`. The "no SmartLists at all" state (user deleted every row) is handled at the `EpisodesView` level with an empty state plus the `+` button still in the toolbar.
- The Episodes tab keeps `SavedPathManager` for last-viewed persistence, re-keyed to `SmartList.ID` under the same `navigationEpisodesTopDestination` storage key (`Tagged` already conforms to `DefaultsStorable`). The pre-upgrade `EpisodesViewType` value fails to decode and self-clears, so last-viewed resets exactly once across the upgrade. A smart list missing from the `sharedState.smartLists` mirror simply pops to the hub — the theoretical restored-ID-renders-before-first-emission race isn't worth a DB-confirmed fallback's complexity.

### 7. EpisodesListViewModel — sort moves to the SmartList row, VM observes its row (Phase 2)

`EpisodesListViewModel.swift:94` currently holds `@PersistedBroadcast var currentSortMethod` keyed by `title` (`init` at `:138–145`). Both the PersistedBroadcast machinery and the title-keying go away. The new shape:

- The VM is constructed from a `SmartList` row at navigation time (`init(smartList:)`).
- It stores `var smartListID: SmartList.ID` and derives `var title`, `var smartListFilter: SmartListFilter`, `var currentSortMethod: SmartListSortMethod` from the latest observed row. `filter: SQLExpression` is computed from `smartListFilter` via `SmartListFilterEngine.sqlExpression(for:referenceDate:)`.
- A long-lived task observes `Observatory.smartList(id: smartListID)`. On every emission, update `title`, `smartListFilter`, `currentSortMethod`. If the filter value or sortMethod changed, restart the inner episode observation.
- `DisplayObservationKey` (`EpisodesListViewModel.swift:128–134`) extends to key on the `SmartListFilter` value (which is `Hashable`) in addition to `sort` and `filterText`. (`SQLExpression` isn't `Hashable`, so key on the source value, not the compiled expression.)
- When the user picks a new sort from the toolbar, the VM writes `await smartListRepo.updateSortMethod(smartListID, to: newMethod)`; the `smartList(id:)` tick reads it back and the VM converges. `currentSortMethod`'s setter therefore becomes a write-through to the repo rather than a stored property. (No optimistic local write — the pick → DB write → observation tick → UI round-trip is fast.)

```swift
init(smartList: SmartList) {
  self.smartListID = smartList.id
  self.title = smartList.title
  self.smartListFilter = smartList.filter
  self.currentSortMethod = smartList.sortMethod
}
```

This also fixes a latent issue: today, the configurator sheet saving a filter change wouldn't propagate to a currently-displayed `EpisodesListView`. With row observation, it will.

### 8. EpisodesView — `PodHaven/Views/Episodes/EpisodesView.swift` (Phase 2)

Replace the static `Form` of `NavigationLink`s (`EpisodesView.swift:10–56`) with an observed `List` of `SmartList` rows supporting edit-mode drag-to-reorder, following `UpNextView`'s pattern (`UpNextView.swift:29` `.onMove`, `:58` `.environment(\.editMode, …)`):

```swift
List {
  ForEach(viewModel.smartLists) { list in
    NavigationLink(value: Navigation.Destination.smartList(list.id)) {
      Text(list.title)
    }
  }
  .onMove(perform: viewModel.moveSmartList)      // SwiftUI shows native drag handles in editMode
}
.environment(\.editMode, $viewModel.editMode)
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

`EpisodesViewModel` (new — small `@Observable @MainActor` in `PodHaven/Views/Episodes/Models/EpisodesViewModel.swift`): owns `var smartLists: [SmartList]`, `var editMode: EditMode = .inactive`, runs `for await rows in observatory.smartLists() { … }`, and exposes `moveSmartList(from: IndexSet, to: Int)` calling `smartListRepo.moveSmartList(_:to:)` (same shape as `UpNextViewModel.moveEpisode` at `UpNextViewModel.swift:312–326`) plus `deleteSmartList(_ smartList:)` which confirms via the injected `alert` (Delete/Cancel, matching tag deletion) before calling `smartListRepo.delete`. No multi-select state — row delete comes from a trash swipe action (edit mode only reorders), with the editor sheet's confirmed Delete button as the second path.

Add `.addSmartList` case to `AppIcon.swift` (`plus.circle`) — the existing `.subscribe`/`.addTag` cases are semantically loaded. `AppIcon.editItems` / `.editFinished` already exist.

### 9. EpisodesListView — gear toolbar (Phase 2)

Add a `.primaryAction` toolbar item using existing `AppIcon.settings` (gear). Tapping opens the editor sheet in `.edit(smartList.id)` mode. The existing search + sort toolbar stays; the sort menu now writes through `EpisodesListViewModel.currentSortMethod` (→ `SmartListRepo.updateSortMethod`).

### 10. Configurator sheet — `PodHaven/Views/Episodes/SmartListEditor/` (Phase 2)

- `SmartListEditorViewModel` — `@Observable @MainActor`; owns `var title: String`, `var filter: SmartListFilter`, `mode: .create | .edit(SmartList.ID)`. `save()` validates and calls `smartListRepo.insert` or `smartListRepo.updateTitle`+`updateFilter`. `delete()` for edit mode only.
- `SmartListEditorView` — sheet root; title `TextField` at top; then one "Conditions" section containing the top group's segmented `.any/.all` picker, its condition rows and "Add Condition" button, every nested group rendered inline below them (so groups visibly participate in the same Any/All math), and a trailing "Add Group" button — adding a group is part of the same workflow as adding a condition, and each add button sits beside the rows it appends to rather than stacking identically-labeled buttons. Save/Cancel/Delete in the toolbar. Uses the canonical sheet pattern (`@DynamicInjected(\.sheet)` + `sheet(id:) { … }`, `Sheet.swift` / `PodHavenApp.swift`).
- `SmartListGroupView` — **non-recursive**; renders one nested group inline in that list: a header row (leading "−" remove button + segmented `.any/.all` picker), then its `SmartListConditionRow`s and an "Add Condition" button, indented so the group reads as a single term of the outer combinator.
- `SmartListConditionRow` — a leading Kind picker (Episode Title / Episode Description / Podcast Title / Podcast Description / State / Episode Tag / Podcast Tag / Duration / Publish Date); the trailing controls swap by Kind:
  - **Text / Podcast text:** a `TextOp` picker + a text field.
  - **State:** a picker over the `StateCondition` cases with human labels.
  - **Episode Tag / Podcast Tag:** a `TagCondition` picker (hasTag / doesNotHaveTag / hasAnyTag / hasNoTags) plus, for the first two, a tag picker reading `sharedState.tags`. Both tag kinds reuse the same UI; only the wrapping `Condition` case differs.
  - **Duration:** min/max minutes steppers/fields (stored as `minSeconds`/`maxSeconds`; either side can be left open).
  - **Publish Date:** a `PublishDateOp` picker (within last / older than) + a days field.
  - Each row has a leading "−" remove button.
- Validation: empty title disables Save; an empty text/duration/pubDate value blocks Save with inline error; an entirely empty filter is allowed (matches `noOp`) but shows a soft warning ("This list will match every episode"). Empty nested groups are dropped on save rather than persisted.
- Delete is always available in edit mode, behind the standard Delete/Cancel alert. Seeded defaults are just rows — users can rename, edit, or delete them like any other SmartList.

---

## Critical files

**New (Phase 1 unless noted):**
- `PodHaven/Database/Models/SmartList.swift`
- `PodHaven/Database/Models/SmartListFilter.swift`
- `PodHaven/Database/Models/SmartListSortMethod.swift` — extracted from `EpisodesListViewModel.SortMethod`
- `PodHaven/Database/SmartListFilterEngine.swift`
- `PodHaven/Database/SmartListRepo.swift`
- `PodHaven/Database/Migrations/Migration_v54.swift`
- `PodHaven/Views/Episodes/Models/EpisodesViewModel.swift` *(Phase 2)*
- `PodHaven/Views/Episodes/SmartListEditor/SmartListEditorView.swift` *(Phase 2)*
- `PodHaven/Views/Episodes/SmartListEditor/SmartListEditorViewModel.swift` *(Phase 2)*
- `PodHaven/Views/Episodes/SmartListEditor/SmartListGroupView.swift` *(Phase 2)*
- `PodHaven/Views/Episodes/SmartListEditor/SmartListConditionRow.swift` *(Phase 2)*
- `PodHavenTests/MigrationTests/v54Tests.swift`
- `PodHavenTests/SmartListFilterEngineTests.swift`
- `PodHavenTests/SmartListFilterCodableTests.swift`
- `PodHavenTests/SmartListRepoTests.swift`

**Modified:**
- `PodHaven/Database/Schema.swift` — register `v54` *(Phase 1)*
- `PodHaven/Database/Repo.swift` + `Database/Protocols/Databasing.swift` — scrub Smart List filters inside `deleteTag` *(Phase 1)*
- `PodHaven/Database/Observatory.swift` (+ its protocol) — add `smartLists()` and `smartList(id:)` *(Phase 1)*
- `PodHaven/Views/Episodes/Models/EpisodesListViewModel.swift` — move `SortMethod` out *(Phase 1)*; take `SmartList` in init, observe `smartList(id:)`, remove `@PersistedBroadcast`, persist sort via `SmartListRepo.updateSortMethod` *(Phase 2)*
- `PodHaven/Environment/Navigation.swift` — delete `EpisodesViewType` + handler, add `smartList(ID)`, switch Episodes tab to `PathManager` *(Phase 2)*
- `PodHaven/Environment/AppIcon.swift` — add `.addSmartList` *(Phase 2)*
- `PodHaven/Views/Episodes/EpisodesView.swift` — observed `List` with `.onMove`, `+`/edit toolbar *(Phase 2)*
- `PodHaven/Views/Episodes/EpisodesListView.swift` — gear toolbar button *(Phase 2)*

## Reused building blocks

- `Episode.queued/unqueued/cached/savedInCache/finished/unfinished/started/unstarted/loved/liked/disliked/notInterested/rated/previouslyQueued` (`Episode.swift:234–248`) — direct mapping for state conditions.
- `AppDB.noOp` (`AppDB.swift:88`) — empty group sentinel.
- `Observatory.listablePodcastEpisodes(filter:order:limit:)` (`Observatory.swift:127–137`) — used as-is; engine produces the `SQLExpression` it expects.
- `PodcastsViewType` Codable (`Navigation.swift:137–174`) — exact pattern for discriminated-`kind` Codable.
- `@Saved<Unsaved…>` macro + `Saved`/`Savable` protocols (`Tag.swift`, `Database/Protocols/`).
- Repo/Observatory factory pattern (`Repo.swift:11–15`, `Observatory.swift:8–14`).
- Sheet presentation: `@DynamicInjected(\.sheet)` + `sheet(id:) { content }` (`Sheet.swift`, `PodHavenApp.swift`).
- `PowerList<ListablePodcastEpisode>` + existing search/sort toolbar in `EpisodesListView` — unchanged.
- Reorder: `.onMove(perform:)` + `.environment(\.editMode, $vm.editMode)` (`UpNextView.swift:29,58`); `moveEpisode(from:to:)` shape (`UpNextViewModel.swift:312–326`); renumber-in-one-transaction (`Queue.swift:229–248`).
- `AppIcon.editItems`/`.editFinished`/`.settings` (existing).
- `CMTime` ↔ seconds `Double` DB bridge (`CMTime.swift:94–105`) — duration comparisons.

## Test plan

1. **v54 migration test** (`v54Tests.swift`, raw SQL only, follows the latest `v{n}Tests.swift` pattern): schema columns + types correct (including the `sortMethod` CHECK constraint, which must accept `recommendationScore` and reject an unknown value); `smartList_on_displayOrder` index exists; exactly 10 rows seeded with distinct titles and `displayOrder` 0–9; each `filter` parses as JSON via `JSONSerialization` (pin the JSON shape, not the model's decoder); rows default to `sortMethod = "newestFirst"` when no UserDefaults pref exists; v53 data untouched. **Sort-pref sub-test:** pre-seed `EpisodesList-sortMethod-Liked` with `Data("\"recentlyAdded\"".utf8)` and `EpisodesList-sortMethod-Finished` with garbage `Data` into `Container.shared.standardDefaults()` before migrating; assert "Liked" → `recentlyAdded` (carried), "Finished" → `newestFirst` (garbage rejected). **Assert the keys are NOT deleted by the migration** (they're cleaned up in Phase 2, not here).
2. **Filter engine parity test** (`SmartListFilterEngineTests.swift`): for each of the 10 default filters, build the `SmartListFilter`, run it through the engine, and assert the output `SQLExpression` returns the **same episode set** as the existing hardcoded expression on a fixture DB. This is the regression anchor.
3. **Filter engine edge-case tests:** nullable-description `doesNotContain` matches null rows; one-level-nested `any`-inside-`all` parenthesizes correctly (fixture designed so wrong precedence yields a different set); `equals`/`startsWith` are case-insensitive; `startsWith` escapes `%`/`_`. **Podcast text tests** mirror the episode-text tests against the parent podcast (no orphan tests — `episode.podcastId` is NOT NULL), and run through the joined `listablePodcastEpisodes(filter:)` request to prove the subquery's `podcast` stays isolated from the request's joined `podcast`. **Tag-scope tests** (run for both `.episodeTag` and `.podcastTag` on the same fixture): `hasNoTags`↔`hasAnyTag` complementarity; `hasTag`/`doesNotHaveTag` partition; a missing/unresolved `Tag.ID` makes `hasTag` match nothing. **Scope-independence test:** `.episodeTag(.hasTag(X))` AND `.podcastTag(.hasTag(Y))` matches only episodes whose own row carries X *and* whose podcast carries Y (fixture includes single-tag episodes so swapping joins changes the result). **Duration tests:** `minSeconds`/`maxSeconds` bounds are inclusive and open-ended on `nil`; `minSeconds: 0` includes unknown-duration (`0`) rows. **PubDate tests:** with a fixed `referenceDate`, `withinLast` and `olderThan` day windows partition around the cutoff.
4. **Codable round-trip** (`SmartListFilterCodableTests.swift`): the 10 default filters + a fixture with a non-nil nested group + one fixture per new condition kind (`podcastText`, `duration`, `pubDate`): encode → decode → encode → assert byte-equal. Decoding an unknown `Condition` `kind` throws.
5. **Repo CRUD** (`SmartListRepoTests.swift`): insert / fetchAll / fetchOne / updateTitle / updateFilter / updateSortMethod / delete; `Observatory.smartLists()` emits on insert and update; `Observatory.smartList(id:)` emits on row update and yields nil after delete.
6. **Repo reorder** (`SmartListRepoTests.swift`): seed 5 rows (displayOrder 0–4); call `moveSmartList` with SwiftUI destination offsets (index 0 → position 3, then index 4 → position 1); assert resulting ordered IDs and dense `displayOrder` values.
7. **Scrub-on-tag-delete** (`SmartListRepoTests.swift` or `RepoTests`): seed a Smart List whose filter references tag X in both the top group and the nested group (plus an unrelated condition); call `Repo.deleteTag(X)`; assert the tag-X conditions are gone, the unrelated condition and combinators survive, and an unrelated Smart List is untouched. Regression: confirm it fails before the scrub hook is added.
8. **VM live-update** (`EpisodesListViewModelTests/`): construct `EpisodesListViewModel(smartList:)` against an in-memory DB; mutate the row's filter via `SmartListRepo.updateFilter`; assert the VM's `filter` and displayed set update via `Wait.until`. Repeat for `updateSortMethod`.
9. **Integration:** observe a SmartList whose filter is `isLoved`; mutate an episode rating to `loved`; assert the row appears via `Wait.until` (no `Task.sleep`, per CLAUDE.md).

Per CLAUDE.md regression-test rule: each engine edge-case test must be confirmed to **fail against an intentionally-broken engine** (e.g., before the null-safe `description` branch, or with the `minSeconds`/`maxSeconds` comparisons swapped) before the fix lands, to prove the test exercises the right behavior.

## Verification (end-to-end)

1. Build clean — zero warnings (CLAUDE.md guardrail).
2. Run full test suite.
3. Launch in simulator:
   - Fresh install: confirm 10 lists appear in `EpisodesView` with the names above; tapping each shows the same episodes as before the migration.
   - Upgrade install (from a v53 DB if possible): migration succeeds, all 10 lists present, seeded sort matches the pre-upgrade pref. After Phase 2 ships, confirm the 10 `EpisodesList-sortMethod-{title}` keys are gone and a sort change made between the two releases survived the v55 re-copy.
   - Tap `+` → editor opens; build a one-level-nested filter (top ALL with `Episode Title contains "AI"` AND a nested ANY group with `loved` OR `liked`), Save → new list appears, tapping shows expected episodes.
   - Build a mixed-scope filter (`Podcast Title contains "Tech"` AND `Episode Tag is "Interview"`), Save → only episodes satisfying *both*; toggle the episode-tag clause to a different tag and confirm the set changes.
   - Build a `Duration longer than 30 min` AND `Published within 7 days` filter → confirm the set narrows accordingly.
   - Tap gear on an existing list → sheet pre-populates with title + filter; edit title → renames in hub.
   - Edit a seeded list's filter → episode set updates live (Observatory reactivity).
   - Edit toggle → drag-reorder several lists; toggle out; relaunch → order persists.
   - Delete a tag that a Smart List references → confirm the list's conditions for that tag disappear and the list still works.
   - Delete any list (including a seeded one) from its editor sheet → disappears from hub.
4. `swift-format` on every changed Swift file before commit.

## Open follow-ups (not blockers)

- Tag/podcast-text-condition perf via an Observatory request-builder overload, if subqueries become a hotspot.
- Continuous re-evaluation of relative `.publishDate` windows (today the cutoff is fixed at observation start).
- Multi-select / bulk delete for SmartLists in edit mode.
