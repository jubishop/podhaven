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
        && !(podcast is Podcast)
        && !(podcast is PodcastDetailSnapshot),
      "ListedPodcast cannot wrap wrapper or detail snapshot types"
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
    if let listablePodcast = getListablePodcast() {
      hasher.combine(listablePodcast)
    } else if let searchResult = getSearchResultPodcast() {
      hasher.combine(searchResult)
    } else if let unsavedPodcast = getUnsavedPodcast() {
      hasher.combine(unsavedPodcast)
    } else {
      Assert.fatal("Can't make hash from: \(type(of: podcast))")
    }
  }

  static func == (lhs: ListedPodcast, rhs: ListedPodcast) -> Bool {
    if let leftListable = lhs.getListablePodcast(), let rightListable = rhs.getListablePodcast() {
      return leftListable == rightListable
    }
    if let leftSearchResult = lhs.getSearchResultPodcast(),
      let rightSearchResult = rhs.getSearchResultPodcast()
    {
      return leftSearchResult == rightSearchResult
    }
    if let leftUnsaved = lhs.getUnsavedPodcast(), let rightUnsaved = rhs.getUnsavedPodcast() {
      return leftUnsaved == rightUnsaved
    }
    return false
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
      return try await DisplayedPodcast.getOrCreatePodcast(unsavedPodcast)
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
