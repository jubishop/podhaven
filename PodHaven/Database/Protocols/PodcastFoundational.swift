// Copyright Justin Bishop, 2026

import Foundation

protocol PodcastFoundational: Identifiable, Sendable, Stringable where ID: Sendable {
  // MARK: - Core Properties

  var feedURL: FeedURL { get }
  var title: String { get }

  // MARK: - Computed Properties

  var podcastID: Podcast.ID? { get }
  var isSaved: Bool { get }
}

extension PodcastFoundational {
  var podcastID: Podcast.ID? { id as? Podcast.ID }
  var isSaved: Bool { podcastID != nil }
}
