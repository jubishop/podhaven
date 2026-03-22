// Copyright Justin Bishop, 2026

import Foundation

protocol PodcastFoundational: Identifiable, Sendable, Stringable where ID: Sendable {
  var podcastID: Podcast.ID? { get }
  var feedURL: FeedURL { get }
  var title: String { get }
  var isSaved: Bool { get }
}

extension PodcastFoundational {
  var podcastID: Podcast.ID? { id as? Podcast.ID }
  var isSaved: Bool { podcastID != nil }
}
