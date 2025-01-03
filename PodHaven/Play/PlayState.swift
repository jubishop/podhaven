// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import SwiftUI

struct OnDeck: Sendable {
  let feedURL: URL
  let guid: String
  let podcastTitle: String
  let podcastURL: URL?
  let episodeTitle: String?
  let duration: CMTime
  let image: UIImage?
  let mediaURL: URL
  let pubDate: Date?

  init(
    feedURL: URL,
    guid: String,
    podcastTitle: String,
    podcastURL: URL?,
    episodeTitle: String?,
    duration: CMTime,
    image: UIImage?,
    mediaURL: URL,
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
    self.mediaURL = mediaURL
    self.pubDate = pubDate
  }
}

@dynamicMemberLookup
@Observable @MainActor final class PlayState: Sendable {
  static let shared = PlayState()

  // MARK: - Meta

  static subscript<T>(dynamicMember keyPath: KeyPath<PlayState, T>) -> T {
    shared[keyPath: keyPath]
  }

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

  private(set) var status: Status = .stopped
  private(set) var currentTime = CMTime.zero
  private(set) var onDeck: OnDeck?
  private init() {}

  func isOnDeck(_ podcastEpisode: PodcastEpisode) -> Bool {
    onDeck?.guid == podcastEpisode.episode.guid
      && onDeck?.feedURL == podcastEpisode.podcast.feedURL
      && onDeck?.mediaURL == podcastEpisode.episode.media
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
