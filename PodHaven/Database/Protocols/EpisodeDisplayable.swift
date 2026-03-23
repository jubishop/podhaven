// Copyright Justin Bishop, 2025

import Foundation

protocol EpisodeDisplayable:
  EpisodeListable,
  Searchable,
  Sendable
{
  var feedURL: FeedURL { get }
  var podcastTitle: String { get }
  var description: String? { get }
  var queueDate: Date? { get }
}

extension EpisodeDisplayable {
  var previouslyQueued: Bool { queueDate != nil }
  var searchableString: String { "\(title) - \(description ?? "")" }
}
