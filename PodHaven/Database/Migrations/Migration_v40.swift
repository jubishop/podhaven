// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Logging

extension Schema {
  static func migrateV40(_: Database) throws {
    // Seed alwaysShowPodcastImageForOnDeck from alwaysShowPodcastImageInUpNext.
    // The OnDeck setting newly governs the floating now-playing row in Up
    // Next, which previously followed the queue setting; copy the value
    // forward so users who enabled the queue setting keep that row's
    // behavior unchanged.
    let defaults = Container.shared.standardDefaults()
    let oldKey = "alwaysShowPodcastImageInUpNext"
    let newKey = "alwaysShowPodcastImageForOnDeck"
    guard defaults.data(forKey: newKey) == nil else { return }
    guard let data = defaults.data(forKey: oldKey) else { return }
    let value: Bool
    do {
      value = try JSONDecoder().decode(Bool.self, from: data)
    } catch {
      log.caughtError(
        "v40: failed to decode \(oldKey)",
        error,
        level: { _ in .info }
      )
      return
    }
    do {
      let encoded = try JSONEncoder().encode(value)
      defaults.set(encoded, forKey: newKey)
      log.info("v40: seeded \(newKey) = \(value)")
    } catch {
      log.caughtError("v40: failed to encode \(newKey)", error)
    }
  }
}
