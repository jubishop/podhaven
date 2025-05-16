// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import SwiftUI

struct OnDeck: Sendable {
  let feedURL: FeedURL
  let guid: GUID
  let podcastTitle: String
  let podcastURL: URL?
  let episodeTitle: String?
  let duration: CMTime
  let image: UIImage?
  let media: MediaURL
  let pubDate: Date?

  init(
    feedURL: FeedURL,
    guid: GUID,
    podcastTitle: String,
    podcastURL: URL?,
    episodeTitle: String?,
    duration: CMTime,
    image: UIImage?,
    media: MediaURL,
    pubDate: Date?
  ) {
    self.feedURL = feedURL
    self.guid = guid
    self.podcastTitle = podcastTitle
    self.podcastURL = podcastURL
    self.episodeTitle = episodeTitle
    self.duration = duration
    self.image = image
    self.media = media
    self.pubDate = pubDate
  }

  // MARK: - Equatable

  static func == (lhs: OnDeck, rhs: PodcastEpisode) -> Bool {
    lhs.guid == rhs.episode.guid && lhs.feedURL == rhs.podcast.feedURL
      && lhs.media == rhs.episode.media
  }
}

extension Container {
  @MainActor
  var playState: Factory<PlayState> {
    Factory(self) { @MainActor in PlayState() }.scope(.cached)
  }
}

@dynamicMemberLookup
@Observable @MainActor final class PlayState: Sendable {
  // MARK: - Meta

  subscript<T>(dynamicMember keyPath: KeyPath<PlayState.Status, T>) -> T {
    status[keyPath: keyPath]
  }

  // MARK: - State Getters

  enum Status: Sendable {
    case loading, active, playing, paused, stopped, waiting

    var playable: Bool {
      switch self {
      case .active, .playing, .paused, .waiting: return true
      default: return false
      }
    }

    var loading: Bool { self == .loading }
    var active: Bool { self == .active }
    var playing: Bool { self == .playing }
    var paused: Bool { self == .paused }
    var stopped: Bool { self == .stopped }
    var waiting: Bool { self == .waiting }
  }

  var playbarVisible = true
  private(set) var status: Status = .stopped
  private(set) var currentTime = CMTime.zero
  private(set) var onDeck: OnDeck?

  fileprivate init() {}

  // MARK: - State Setters

  func setStatus(_ status: Status) {
    self.status = status
  }

  func setCurrentTime(_ currentTime: CMTime) {
    self.currentTime = currentTime
  }

  func setOnDeck(_ onDeck: OnDeck?) {
    self.onDeck = onDeck
  }
}
