// Copyright Justin Bishop, 2026

import Foundation
import GRDB

extension Schema {
  static func migrateV26(_: Database) throws {
    // Migrate currentEpisodeID from PlayManager to SharedState key.
    // This allows the cache purger to protect the current episode even when the app
    // is launched in the background (when onDeck is not populated).
    let oldKey = "PlayManager-currentEpisodeID"
    let newKey = "currentEpisodeID"
    if let oldValue = UserDefaults.standard.object(forKey: oldKey) as? Int {
      UserDefaults.standard.set(oldValue, forKey: newKey)
      UserDefaults.standard.removeObject(forKey: oldKey)
    }
  }
}
