// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
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
    pubDate: Date?,
    key: PlayManagerAccessKey
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
}

extension Container {
  var playState: Factory<PlayState> {
    Factory(self) { @MainActor in PlayState() }.scope(.singleton)
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

  // TODO: Use an == operator for onDeck to PodcastEpisode here instead.
  func isOnDeck(_ podcastEpisode: PodcastEpisode) -> Bool {
    onDeck?.guid == podcastEpisode.episode.guid
      && onDeck?.feedURL == podcastEpisode.podcast.feedURL
      && onDeck?.media == podcastEpisode.episode.media
  }

  // MARK: - State Setters

  func setStatus(_ status: Status, _ key: PlayManagerAccessKey) {
    self.status = status
  }

  func setCurrentTime(_ currentTime: CMTime, _ key: PlayManagerAccessKey) {
    self.currentTime = currentTime
  }

  func setOnDeck(_ onDeck: OnDeck?, _ key: PlayManagerAccessKey) {
    self.onDeck = onDeck
  }
}
