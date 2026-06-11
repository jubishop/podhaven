// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Logging

extension Schema {
  static func migrateV55(_ db: Database) throws {
    // Phase 2 cleanup of the legacy per-list sort prefs. A surviving key holds
    // the newest pre-upgrade sort pick (changes made after the v54 copy landed
    // only in UserDefaults), so re-copy each onto its matching row by title,
    // then delete the key. Title matching is reliable because lists couldn't
    // be renamed before the Smart List editor shipped.
    let allowedSortMethods = [
      "newestFirst", "oldestFirst", "recentlyAdded", "longest", "shortest",
      "recentlyFinished", "recentlyQueued", "recommendationScore",
    ]
    let defaults = Container.shared.standardDefaults()
    let prefix = "EpisodesList-sortMethod-"
    let keys = defaults.allKeys.filter { $0.hasPrefix(prefix) }
    for key in keys {
      guard let data = defaults.data(forKey: key) else { continue }
      let raw: String
      do {
        raw = try JSONDecoder().decode(String.self, from: data)
      } catch {
        log.caughtError("v55: undecodable sort pref at '\(key)'", error, level: { _ in .info })
        continue
      }
      guard allowedSortMethods.contains(raw) else { continue }
      try db.execute(
        sql: "UPDATE smartList SET sortMethod = ? WHERE title = ?",
        arguments: [raw, String(key.dropFirst(prefix.count))]
      )
    }
    // Keys go only after every surviving pref has been re-copied: defaults
    // aren't covered by the migration transaction, so a thrown UPDATE must
    // leave them in place for the retry.
    for key in keys {
      defaults.removeObject(forKey: key)
    }
  }
}
