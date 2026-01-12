// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import Sharing
import SwiftUI

extension Container {
  var userSettings: Factory<UserSettings> {
    Factory(self) { UserSettings() }.scope(.cached)
  }
}

struct UserSettings: Sendable {
  @Shared(.appStorage("shrinkPlayBarOnScroll")) var shrinkPlayBarOnScroll: Bool = true
  @Shared(.appStorage("cacheSizeLimitGB")) var cacheSizeLimitGB: Double = 1.0
  @Shared(.appStorage("defaultPlaybackRate")) var defaultPlaybackRate: Double = 1.0
  @Shared(.appStorage("skipForwardInterval")) var skipForwardInterval: TimeInterval = 30
  @Shared(.appStorage("skipBackwardInterval")) var skipBackwardInterval: TimeInterval = 15
  @Shared(.appStorage("enableUndoSeek")) var enableUndoSeek: Bool = false
  @Shared(.appStorage("maxQueueLength")) var maxQueueLength: Int = 200
  @Shared(.appStorage("showNowPlayingInUpNext")) var showNowPlayingInUpNext: Bool = false

  enum NextTrackBehavior: String, CaseIterable, Identifiable {
    case nextEpisode = "Next Episode"
    case skipInterval = "Skip Interval"

    var id: String { rawValue }
  }

  @Shared(.appStorage("nextTrackBehavior")) var nextTrackBehavior: NextTrackBehavior = .nextEpisode

  private static let log = Log.as("UserSettings")

  fileprivate init() {
    Self.log.debug("Initializing user settings")
  }
}
