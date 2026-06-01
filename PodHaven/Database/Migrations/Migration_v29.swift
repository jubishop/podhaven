// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Logging

extension Schema {
  static func migrateV29(_: Database) throws {
    // Migrate persisted UserDefaults values from native format to JSON Data.
    // Commit 20fd026a changed DefaultsStorable to use Codable (JSON) for all types,
    // but values stored by earlier builds used native UserDefaults storage.
    let defaults = UserDefaults.standard

    func migrate<T: Codable>(_ key: String, _ nativeValue: @autoclosure () -> T) {
      guard let existing = defaults.object(forKey: key), !(existing is Data) else { return }
      do {
        let data = try JSONEncoder().encode(nativeValue())
        defaults.set(data, forKey: key)
      } catch {
        log.caughtError(
          "v29 migration: failed to encode '\(key)' (\(type(of: existing)))",
          error,
          level: { _ in .info }
        )
      }
    }

    // Int
    migrate("currentEpisodeID", defaults.integer(forKey: "currentEpisodeID"))
    migrate("maxQueueLength", defaults.integer(forKey: "maxQueueLength"))

    // Bool
    migrate("shrinkPlayBarOnScroll", defaults.bool(forKey: "shrinkPlayBarOnScroll"))
    migrate("enableUndoSeek", defaults.bool(forKey: "enableUndoSeek"))
    migrate("showNowPlayingInUpNext", defaults.bool(forKey: "showNowPlayingInUpNext"))
    migrate(
      "alwaysShowPodcastImageInUpNext",
      defaults.bool(forKey: "alwaysShowPodcastImageInUpNext")
    )
    migrate(
      "showTimeRemainingInEpisodeLists",
      defaults.bool(forKey: "showTimeRemainingInEpisodeLists")
    )

    // Double
    migrate("cacheSizeLimitGB", defaults.double(forKey: "cacheSizeLimitGB"))
    migrate("defaultPlaybackRate", defaults.double(forKey: "defaultPlaybackRate"))
    migrate("skipForwardInterval", defaults.double(forKey: "skipForwardInterval"))
    migrate("skipBackwardInterval", defaults.double(forKey: "skipBackwardInterval"))
  }
}
