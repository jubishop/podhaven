// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import SwiftUI

struct OnDeck {
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
