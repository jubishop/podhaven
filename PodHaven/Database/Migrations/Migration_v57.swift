// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Logging

extension Schema {
  static func migrateV57(_: Database) throws {
    let defaults = Container.shared.standardDefaults()
    let oldKey = "alwaysShowPodcastImageInUpNext"
    let newKey = "alwaysShowPodcastImageForUpNextRecommendations"
    guard defaults.data(forKey: newKey) == nil else { return }
    guard let data = defaults.data(forKey: oldKey) else { return }
    let value: Bool
    do {
      value = try JSONDecoder().decode(Bool.self, from: data)
    } catch {
      log.caughtError(
        "v57: failed to decode \(oldKey)",
        error,
        level: { _ in .info }
      )
      return
    }
    do {
      let encoded = try JSONEncoder().encode(value)
      defaults.set(encoded, forKey: newKey)
      log.info("v57: seeded \(newKey) = \(value)")
    } catch {
      log.caughtError("v57: failed to encode \(newKey)", error)
    }
  }
}
