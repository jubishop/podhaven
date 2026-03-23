// Copyright Justin Bishop, 2026

import Foundation

protocol PodcastListable: Identifiable, Sendable, Stringable, Hashable, Searchable
where ID: Sendable {
  // MARK: - Core Properties

  var feedURL: FeedURL { get }
  var title: String { get }
  var iTunesID: ITunesPodcastID? { get }
  var image: URL { get }
  var subscriptionDate: Date? { get }

  // MARK: - Computed Properties

  var podcastID: Podcast.ID? { get }
  var isSaved: Bool { get }
  var subscribed: Bool { get }
}

extension PodcastListable {
  var podcastID: Podcast.ID? { id as? Podcast.ID }
  var isSaved: Bool { podcastID != nil }
  var iTunesID: ITunesPodcastID? { nil }
  var subscribed: Bool { subscriptionDate != nil }
}
