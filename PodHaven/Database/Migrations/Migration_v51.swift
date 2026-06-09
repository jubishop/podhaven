// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Logging

extension Schema {
  static func migrateV51(_ db: Database) throws {
    // The smartList table backs user-editable episode-filter lists. All 8 sort
    // methods are accepted (incl. recommendationScore), matching the lifted
    // SmartListSortMethod. Hoisted to a `let` so the check stays a single
    // `.contains`, avoiding the type-checker timeout chained equalities trip.
    let allowedSortMethods = [
      "newestFirst", "oldestFirst", "recentlyAdded", "longest", "shortest",
      "recentlyFinished", "recentlyQueued", "recommendationScore",
    ]
    try db.create(table: "smartList") { t in
      t.autoIncrementedPrimaryKey("id")
      t.column("title", .text).notNull()
      // filter holds the SmartListFilter as JSON. Guard the top-level shape the
      // decoder requires (object with a text combinator, an array of conditions,
      // and an absent/null/object nested group) so a malformed write can't leave
      // a row the read path later fails to decode. Per-condition validation
      // would need normalizing the filter into tables.
      t.column("filter", .text).notNull()
        .check(
          // `IS` (not `=`) so a missing combinator/conditions key resolves to
          // FALSE, not NULL — a CHECK passes on NULL, so `= 'text'` would let a
          // row missing the key through.
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
    try db.execute(sql: "CREATE INDEX smartList_displayOrder ON smartList(displayOrder)")

    // Copy each list's persisted sort pref from UserDefaults onto its seeded
    // row. The keys are NOT deleted: the existing episodes view model still
    // reads them until the UI is swapped to read from these rows. The value is
    // JSON-encoded Data, e.g. `"newestFirst"` for the String-raw sort enum.
    let defaults = Container.shared.standardDefaults()
    func migratedSortMethod(forTitle title: String) -> String {
      guard let data = defaults.data(forKey: "EpisodesList-sortMethod-\(title)") else {
        return "newestFirst"
      }
      do {
        let raw = try JSONDecoder().decode(String.self, from: data)
        return allowedSortMethods.contains(raw) ? raw : "newestFirst"
      } catch {
        log.caughtError(
          "v51: failed to decode stored sort pref for \(title)",
          error,
          level: { _ in .info }
        )
        return "newestFirst"
      }
    }

    // Seed the 10 lists currently hardcoded in EpisodesView, preserving order.
    // Filters are hand-spelled JSON literals (string-literals-only rule); all
    // are flat state filters, so no nested groups or other condition kinds.
    let seeds: [(title: String, displayOrder: Int, filter: String)] = [
      ("Recent Episodes", 0, #"{"combinator":"all","conditions":[],"nested":null}"#),
      (
        "Unqueued", 1,
        #"{"combinator":"all","conditions":[{"kind":"state","value":"isUnqueued"},{"kind":"state","value":"isUnfinished"}],"nested":null}"#
      ),
      (
        "Cached", 2,
        #"{"combinator":"all","conditions":[{"kind":"state","value":"isCached"}],"nested":null}"#
      ),
      (
        "Saved", 3,
        #"{"combinator":"all","conditions":[{"kind":"state","value":"isSaved"}],"nested":null}"#
      ),
      (
        "Finished", 4,
        #"{"combinator":"all","conditions":[{"kind":"state","value":"isFinished"}],"nested":null}"#
      ),
      (
        "Unfinished", 5,
        #"{"combinator":"all","conditions":[{"kind":"state","value":"isUnfinished"},{"kind":"state","value":"isStarted"}],"nested":null}"#
      ),
      (
        "Previously Queued", 6,
        #"{"combinator":"all","conditions":[{"kind":"state","value":"wasPreviouslyQueued"}],"nested":null}"#
      ),
      (
        "Liked", 7,
        #"{"combinator":"any","conditions":[{"kind":"state","value":"isLiked"},{"kind":"state","value":"isLoved"}],"nested":null}"#
      ),
      (
        "Disliked", 8,
        #"{"combinator":"all","conditions":[{"kind":"state","value":"isDisliked"}],"nested":null}"#
      ),
      (
        "Not Interested", 9,
        #"{"combinator":"all","conditions":[{"kind":"state","value":"isNotInterested"}],"nested":null}"#
      ),
    ]
    for seed in seeds {
      try db.execute(
        sql: "INSERT INTO smartList (title, filter, displayOrder, sortMethod) VALUES (?, ?, ?, ?)",
        arguments: [
          seed.title, seed.filter, seed.displayOrder, migratedSortMethod(forTitle: seed.title),
        ]
      )
    }
  }
}
