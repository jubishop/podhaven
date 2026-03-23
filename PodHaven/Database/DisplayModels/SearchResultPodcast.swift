// Copyright Justin Bishop, 2025

import Foundation

struct SearchResultPodcast:
  PodcastListable,
  Searchable,
  Stringable,
  Hashable,
  Sendable
{
  let resultFeedURL: FeedURL
  let originalPodcast: UnsavedPodcast
  let originalEpisodeCount: Int
  let originalMostRecentEpisodeDate: Date?
  let savedPodcast: ListablePodcast

  // MARK: - Identifiable

  var id: FeedURL { resultFeedURL }

  // MARK: - PodcastListable

  var podcastID: Podcast.ID? { savedPodcast.podcastID }
  var feedURL: FeedURL { savedPodcast.feedURL }
  var iTunesID: ITunesPodcastID? { savedPodcast.iTunesID }
  var image: URL { savedPodcast.image }
  var title: String { savedPodcast.title }
  var subscriptionDate: Date? { savedPodcast.subscriptionDate }

  // MARK: - Hashable / Equatable
  // Intentionally hashes/compares on the canonical podcast, not resultFeedURL.
  // id (resultFeedURL) drives IdentifiedArray slot identity; hash/equality answer
  // "is this the same underlying podcast data?" so SwiftUI diffing re-renders when
  // the podcast changes, not when the search slot does.

  func hash(into hasher: inout Hasher) {
    hasher.combine(savedPodcast)
  }

  static func == (lhs: SearchResultPodcast, rhs: SearchResultPodcast) -> Bool {
    lhs.savedPodcast == rhs.savedPodcast
  }

  // MARK: - Stringable / Searchable

  var toString: String { savedPodcast.toString }
  var searchableString: String { originalPodcast.searchableString }

  func getPodcast() async throws -> Podcast {
    try await savedPodcast.getPodcast()
  }
}
