// Copyright Justin Bishop, 2026

import FactoryKit
import GRDB

extension Schema {
  static func migrateV33(_: Database) throws {
    cleanupStaleKeys(
      in: Container.shared.standardDefaults(),
      activeKeys: [
        "shrinkPlayBarOnScroll",
        "cacheSizeLimitGB",
        "defaultPlaybackRate",
        "skipForwardInterval",
        "skipBackwardInterval",
        "enableUndoSeek",
        "maxQueueLength",
        "showNowPlayingInUpNext",
        "alwaysShowPodcastImageInUpNext",
        "showTimeRemainingInEpisodeLists",
        "appearanceMode",
        "nextTrackBehavior",
        "currentEpisodeID",
        "PodcastsList-displayMode",
        "SearchView-displayMode",
      ],
      activePrefixes: [
        "PodcastsList-sortMethod-",
        "EpisodesList-sortMethod-",
      ]
    )
    cleanupStaleKeys(
      in: Container.shared.sharedDefaults(),
      activeKeys: [
        "skipForwardInterval",
        "skipBackwardInterval",
        "playbackStatus",
      ]
    )
  }

  // MARK: - v33: Stale Defaults Cleanup

  static func cleanupStaleKeys(
    in store: any KeyValueStore,
    activeKeys: Set<String>,
    activePrefixes: [String] = []
  ) {
    for key in store.allKeys {
      let isActive =
        activeKeys.contains(key) || activePrefixes.contains(where: { key.hasPrefix($0) })
      if !isActive {
        store.removeObject(forKey: key)
      }
    }
  }
}
