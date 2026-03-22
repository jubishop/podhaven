// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB

@dynamicMemberLookup
struct ListedPodcast:
  PodcastListable,
  Searchable,
  Hashable,
  Sendable
{
  @DynamicInjected(\.repo) private var repo

  let podcast: any PodcastListable

  init(_ podcast: any PodcastListable) {
    Assert.precondition(
      !(podcast is ListedPodcast),
      "Cannot wrap an instance of itself as a ListedPodcast"
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

  var iTunesID: ITunesPodcastID? { podcast.iTunesID }
  var feedURL: FeedURL { podcast.feedURL }
  var image: URL { podcast.image }
  var title: String { podcast.title }
  var description: String { podcast.description }
  var subscriptionDate: Date? { podcast.subscriptionDate }
  var subscribed: Bool { podcast.subscribed }

  // MARK: - Getters

  func getListablePodcast() -> ListablePodcast? { podcast as? ListablePodcast }
  func getSearchResultPodcast() -> SearchResultPodcast? { podcast as? SearchResultPodcast }
  func getUnsavedPodcast() -> UnsavedPodcast? { podcast as? UnsavedPodcast }

  func getDisplayedPodcast() -> DisplayedPodcast? {
    guard let displayable = podcast as? any PodcastDisplayable else { return nil }
    return DisplayedPodcast(displayable)
  }

  func toOriginalUnsavedPodcast() throws -> UnsavedPodcast {
    if let searchResult = getSearchResultPodcast() {
      return try searchResult.podcast.toOriginalUnsavedPodcast()
    } else if let unsavedPodcast = getUnsavedPodcast() {
      return try unsavedPodcast.toOriginalUnsavedPodcast()
    } else {
      Assert.fatal("Can't make Original UnsavedPodcast from: \(type(of: podcast))")
    }
  }

  func getOrCreatePodcast() async throws -> Podcast {
    if let unsavedPodcast = getUnsavedPodcast() {
      return try await DisplayedPodcast.getOrCreatePodcast(unsavedPodcast)
    } else if let listablePodcast = getListablePodcast() {
      guard let podcastSeries = try await repo.podcastSeries(listablePodcast.id) else {
        throw DatabaseError(message: "Podcast not found for ID \(listablePodcast.id)")
      }
      return podcastSeries.podcast
    } else {
      Assert.fatal("Can't make podcast from: \(type(of: podcast))")
    }
  }
}
