// Copyright Justin Bishop, 2026

import Foundation

@dynamicMemberLookup
struct ListedPodcast:
  PodcastListable,
  Searchable,
  Hashable,
  Sendable
{
  let podcast: any PodcastListable

  init(_ podcast: any PodcastListable) {
    Assert.precondition(
      !(podcast is ListedPodcast)
        && !(podcast is DisplayedPodcast)
        && !(podcast is Podcast),
      "ListedPodcast cannot wrap wrapper or full podcast types"
    )
    self.podcast = podcast
  }

  subscript<T>(dynamicMember keyPath: KeyPath<any PodcastListable, T>) -> T {
    podcast[keyPath: keyPath]
  }

  // MARK: - Identifiable

  var id: FeedURL {
    if let searchResult = getSearchResultPodcast() {
      return searchResult.resultFeedURL
    }
    return feedURL
  }

  // MARK: - Hashable / Equatable

  func hash(into hasher: inout Hasher) {
    AnyHashable(podcast).hash(into: &hasher)
  }

  static func == (lhs: ListedPodcast, rhs: ListedPodcast) -> Bool {
    AnyHashable(lhs.podcast) == AnyHashable(rhs.podcast)
  }

  // MARK: - Stringable / Searchable

  var toString: String { podcast.toString }
  var searchableString: String { podcast.searchableString }

  // MARK: - PodcastListable

  var podcastID: Podcast.ID? { podcast.podcastID }
  var feedURL: FeedURL { podcast.feedURL }
  var iTunesID: ITunesPodcastID? { podcast.iTunesID }
  var image: URL { podcast.image }
  var title: String { podcast.title }
  var subscriptionDate: Date? { podcast.subscriptionDate }
  var subscribed: Bool { podcast.subscribed }

  // MARK: - Helpers

  func getOrCreatePodcast() async throws -> Podcast {
    if let unsavedPodcast = getUnsavedPodcast() {
      return try await unsavedPodcast.getOrCreatePodcast()
    } else if let searchResult = getSearchResultPodcast() {
      return try await searchResult.getPodcast()
    } else if let listablePodcast = getListablePodcast() {
      return try await listablePodcast.getPodcast()
    } else {
      Assert.fatal("Can't make podcast from: \(type(of: podcast))")
    }
  }

  func getListablePodcast() -> ListablePodcast? { podcast as? ListablePodcast }
  func getSearchResultPodcast() -> SearchResultPodcast? { podcast as? SearchResultPodcast }
  func getUnsavedPodcast() -> UnsavedPodcast? { podcast as? UnsavedPodcast }

  func toOriginalUnsavedPodcast() throws -> UnsavedPodcast {
    if let searchResult = getSearchResultPodcast() {
      return try searchResult.originalPodcast.toOriginalUnsavedPodcast()
    } else if let unsavedPodcast = getUnsavedPodcast() {
      return try unsavedPodcast.toOriginalUnsavedPodcast()
    } else {
      Assert.fatal("Can't make Original UnsavedPodcast from: \(type(of: podcast))")
    }
  }
}
