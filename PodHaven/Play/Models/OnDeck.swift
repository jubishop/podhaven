// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import SwiftUI

struct OnDeck: Identifiable, Stringable {
  var id: Episode.ID { episodeID }

  // MARK: - Stringable

  var toString: String { "[\(id)] - (\(mediaGUID)) - \(episodeTitle)" }

  // MARK: - Data

  let episodeID: Episode.ID
  let feedURL: FeedURL
  let guid: GUID
  let podcastTitle: String
  let podcastURL: URL?
  let episodeTitle: String
  let duration: CMTime
  let image: UIImage?
  let mediaURL: MediaURL
  let pubDate: Date?

  // MARK: - Initialization

  init(
    episodeID: Episode.ID,
    feedURL: FeedURL,
    guid: GUID,
    podcastTitle: String,
    podcastURL: URL?,
    episodeTitle: String,
    duration: CMTime,
    image: UIImage?,
    mediaURL: MediaURL,
    pubDate: Date?
  ) {
    self.episodeID = episodeID
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

  // MARK: - Derived Data

  var mediaGUID: MediaGUID { MediaGUID(guid: guid, mediaURL: mediaURL) }

  // MARK: - Equatable

  static func == (lhs: OnDeck, rhs: PodcastEpisode) -> Bool { lhs.id == rhs.id }
  static func == (lhs: OnDeck, rhs: Episode) -> Bool { lhs.id == rhs.id }
  static func == (lhs: OnDeck, rhs: any EpisodeInformable) -> Bool {
    lhs.mediaGUID == rhs.mediaGUID
  }
}
