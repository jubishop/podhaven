// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Logging

extension Schema {
  static func migrateV32(_ db: Database) throws {
    // Cap maxQueueLength at 100 (previously allowed up to 500).
    let defaults = Container.shared.standardDefaults()
    let key = "maxQueueLength"
    if let data = defaults.data(forKey: key),
      let current = try? JSONDecoder().decode(Int.self, from: data),
      current > 100
    {
      let clamped = try JSONEncoder().encode(100)
      defaults.set(clamped, forKey: key)
      log.info("v32: clamped maxQueueLength from \(current) to 100")
    }

    // Trim queued episodes beyond position 100.
    // queueOrder is always a dense 0-based sequence, so this is equivalent
    // to removing everything past the 100th item.
    try db.execute(sql: "UPDATE episode SET queueOrder = NULL WHERE queueOrder >= 100")
  }
}
