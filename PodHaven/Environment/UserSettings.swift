// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import SwiftUI

extension Container {
  var userSettings: Factory<UserSettings> {
    Factory(self) { UserSettings() }.scope(.cached)
  }
}

struct UserSettings: Sendable {
  @PersistedBroadcast("shrinkPlayBarOnScroll") var shrinkPlayBarOnScroll: Bool = true
  @PersistedBroadcast("cacheSizeLimitGB") var cacheSizeLimitGB: Double = 1.0
  @PersistedBroadcast("defaultPlaybackRate") var defaultPlaybackRate: Double = 1.0
  @PersistedBroadcast("skipForwardInterval") var skipForwardInterval: TimeInterval = 30
  @PersistedBroadcast("skipBackwardInterval") var skipBackwardInterval: TimeInterval = 15
  @PersistedBroadcast("enableUndoSeek") var enableUndoSeek: Bool = true
  @PersistedBroadcast("maxQueueLength") var maxQueueLength: Int = 50
  @PersistedBroadcast("maxRecommendedEpisodesInUpNext") var maxRecommendedEpisodesInUpNext: Int = 5
  @PersistedBroadcast("showNowPlayingInUpNext") var showNowPlayingInUpNext: Bool = false
  @PersistedBroadcast("alwaysShowPodcastImageInUpNext") var alwaysShowPodcastImageInUpNext: Bool =
    true
  @PersistedBroadcast("alwaysShowPodcastImageForOnDeck") var alwaysShowPodcastImageForOnDeck: Bool =
    false
  @PersistedBroadcast("showTimeRemainingInEpisodeLists") var showTimeRemainingInEpisodeLists: Bool =
    false

  enum AppearanceMode: String, Codable, DefaultsStorable, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
      switch self {
      case .system: nil
      case .light: .light
      case .dark: .dark
      }
    }
  }
  @PersistedBroadcast("appearanceMode") var appearanceMode: AppearanceMode = .system

  enum NextTrackBehavior: String, Codable, DefaultsStorable, CaseIterable, Identifiable, Sendable {
    case nextEpisode = "Next Episode"
    case skipInterval = "Skip Interval"
    case nextChapter = "Next Chapter"

    var id: String { rawValue }
  }
  @PersistedBroadcast("nextTrackBehavior") var nextTrackBehavior: NextTrackBehavior = .skipInterval

  private static let log = Log.as("UserSettings")

  fileprivate init() {
    Self.log.debug("Initializing user settings")
  }
}
