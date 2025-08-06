// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import SwiftUI

struct OnDeck: Identifiable, Stringable {
  var id: Episode.ID { episodeID }

  // MARK: - Stringable

  var toString: String { "[\(id)] - \(mediaURL.hash()) - \(episodeTitle)" }

  // MARK: - Data

  let episodeID: Episode.ID
  let feedURL: FeedURL
  let guid: GUID
  let podcastTitle: String
  let podcastURL: URL?
  let episodeTitle: String
  let duration: CMTime
  let image: UIImage?
  let mediaURL: URL
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
    mediaURL: URL,
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

  // MARK: - Equatable

  static func == (lhs: OnDeck, rhs: PodcastEpisode) -> Bool { lhs.id == rhs.id }
  static func == (lhs: OnDeck, rhs: Episode) -> Bool { lhs.id == rhs.id }
}
