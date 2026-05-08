// Copyright Justin Bishop, 2026

import Foundation

protocol EpisodeListable: EpisodeFoundational, Hashable {
  var feedURL: FeedURL { get }
  var image: URL { get }
  var podcastImage: URL { get }
  // nil signals that tag data isn't available on this episode shape; a
  // (possibly empty) Set means the row carries its current tag IDs and the
  // UI may offer filtered tag editing against it.
  var tagIDs: Set<Tag.ID>? { get }
}

extension EpisodeListable {
  var tagIDs: Set<Tag.ID>? { nil }
}
