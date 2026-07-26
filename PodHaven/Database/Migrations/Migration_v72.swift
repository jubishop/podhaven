// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB

extension Schema {
  static func migrateV72(_: Database) throws {
    let defaults = Container.shared.standardDefaults()

    defaults.removeObject(forKey: "transcriptionQueue")
    defaults.removeObject(forKey: "navigationEpisodesTopDestination")
    defaults.removeObject(forKey: "navigationPodcastsTopDestination")

    let exactStringValues: [(key: String, allowed: Set<String>)] = [
      ("appearanceMode", ["System", "Light", "Dark"]),
      ("nextTrackBehavior", ["Next Episode", "Skip Interval", "Next Chapter"]),
      ("PodcastsList-displayMode", ["grid", "list"]),
    ]
    for value in exactStringValues {
      try migrateNativeString(
        value.key,
        allowed: value.allowed,
        in: defaults
      )
    }

    let sortMethodValues: Set<String> = [
      "byTitle",
      "byMostRecentEpisode",
      "byMostRecentlyAdded",
      "byEpisodeCount",
      "byMostRecentlySubscribed",
    ]
    for key in defaults.allKeys where key.hasPrefix("PodcastsList-sortMethod-") {
      try migrateNativeString(
        key,
        allowed: sortMethodValues,
        in: defaults
      )
    }
  }

  private static func migrateNativeString(
    _ key: String,
    allowed: Set<String>,
    in store: any KeyValueStore
  ) throws {
    guard store.data(forKey: key) == nil else { return }
    guard let value = store.string(forKey: key), allowed.contains(value) else {
      store.removeObject(forKey: key)
      return
    }
    store.set(try JSONEncoder().encode(value), forKey: key)
  }
}
