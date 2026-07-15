// Copyright Justin Bishop, 2025

import FactoryKit
import IdentifiedCollections
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
  @PersistedBroadcast("commandCenterScrubbingEnabled") var commandCenterScrubbingEnabled: Bool =
    true
  @PersistedBroadcast("maxQueueLength") var maxQueueLength: Int = 50
  @PersistedBroadcast("maxRecommendedEpisodesInUpNext") var maxRecommendedEpisodesInUpNext: Int = 5
  @PersistedBroadcast("showNowPlayingInUpNext") var showNowPlayingInUpNext: Bool = false
  @PersistedBroadcast("alwaysShowPodcastImageInUpNext") var alwaysShowPodcastImageInUpNext: Bool =
    true
  @PersistedBroadcast("alwaysShowPodcastImageForUpNextRecommendations")
  var alwaysShowPodcastImageForUpNextRecommendations: Bool = true
  @PersistedBroadcast("alwaysShowPodcastImageForOnDeck") var alwaysShowPodcastImageForOnDeck: Bool =
    false
  @PersistedBroadcast("showTimeRemainingInEpisodeLists") var showTimeRemainingInEpisodeLists: Bool =
    false
  @PersistedBroadcast("autoPlayTopRecommendationWhenQueueEmpty")
  var autoPlayTopRecommendationWhenQueueEmpty: Bool = true

  @PersistedBroadcast("enableWriteProbe") var enableWriteProbe: Bool = false

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

  // What the remote Command Center "like" feedback button does to the on-deck
  // episode. `.addTag` carries the tag it assigns; a tag deleted after being
  // chosen is treated as no action until the user picks another.
  enum CommandCenterLikeAction: Codable, DefaultsStorable, Sendable {
    case love
    case like
    case saveInCache
    case addTag(Tag.ID)

    func title(tags: IdentifiedArrayOf<Tag>) -> String {
      switch self {
      case .love: "Love"
      case .like: "Like"
      case .saveInCache: "Save in Cache"
      case .addTag(let tagID):
        if let tag = tags[id: tagID] {
          "Tag: \(tag.name)"
        } else {
          "Add Tag"
        }
      }
    }
  }
  @PersistedBroadcast("commandCenterLikeAction")
  var commandCenterLikeAction: CommandCenterLikeAction = .like

  // What the remote Command Center "dislike" feedback button does to the on-deck
  // episode. See CommandCenterLikeAction for the `.addTag` lifetime note.
  enum CommandCenterDislikeAction: Codable, DefaultsStorable, Sendable {
    case dislike
    case addTag(Tag.ID)

    func title(tags: IdentifiedArrayOf<Tag>) -> String {
      switch self {
      case .dislike: "Dislike"
      case .addTag(let tagID):
        if let tag = tags[id: tagID] {
          "Tag: \(tag.name)"
        } else {
          "Add Tag"
        }
      }
    }
  }
  @PersistedBroadcast("commandCenterDislikeAction")
  var commandCenterDislikeAction: CommandCenterDislikeAction = .dislike

  // The trailing (swipe-left) row actions on episode lists, in display order.
  // The leading (swipe-right) queue actions are fixed and not configurable.
  enum EpisodeSwipeAction:
    String, Codable, DefaultsStorable, CaseIterable, Identifiable, Sendable
  {
    case playPause = "Play/Pause"
    case rate = "Rate"
    case markFinished = "Mark Finished"
    case cache = "Cache"
    case saveInCache = "Save in Cache"
    case tag = "Tag"
    case transcribe = "Transcribe"

    var id: String { rawValue }
    var title: String { rawValue }
  }
  @PersistedBroadcast("episodeSwipeActions")
  var episodeSwipeActions: [EpisodeSwipeAction] = [.playPause, .rate]

  // "Focused" keeps just the corpus-mean centering — recommendations stay
  // close to the podcasts you've already rated. "Exploratory" additionally
  // strips the next three principal components, which empirically encode
  // podcast *format* rather than topic, opening up topical discovery across
  // shows you haven't engaged with yet.
  enum RecommendationDeconeMode:
    String, Codable, DefaultsStorable, CaseIterable, Identifiable, Sendable
  {
    case focused = "Focused"
    case exploratory = "Exploratory"

    var id: String { rawValue }
  }
  @PersistedBroadcast("recommendationDeconeMode")
  var recommendationDeconeMode: RecommendationDeconeMode = .exploratory

  // Weight of the podcast-affinity term in the scoring blend; the similarity
  // term always takes the remainder (1.0 − this). 0.0 = pure content
  // similarity; 0.5 = equal split.
  @PersistedBroadcast("podcastAffinityWeight") var podcastAffinityWeight: Double = 0.1

  private static let log = Log.as("UserSettings")

  fileprivate init() {
    Self.log.debug("Initializing user settings")
  }
}
