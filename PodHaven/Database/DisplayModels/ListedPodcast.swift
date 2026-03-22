// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

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
    if let searchResult = podcast as? SearchResultPodcast {
      return searchResult.resultFeedURL
    }
    return feedURL
  }

  // MARK: - Hashable / Equatable

  func hash(into hasher: inout Hasher) {
    if let searchResult = podcast as? SearchResultPodcast {
      hasher.combine(searchResult)
    } else if let podcast = getPodcast() {
      hasher.combine(podcast)
    } else if let unsavedPodcast = getUnsavedPodcast() {
      hasher.combine(unsavedPodcast)
    } else if let listablePodcast = getListablePodcast() {
      hasher.combine(listablePodcast)
    } else {
      Assert.fatal("Can't make hash from: \(type(of: podcast))")
    }
  }

  static func == (lhs: ListedPodcast, rhs: ListedPodcast) -> Bool {
    if let leftPodcast = lhs.getPodcast(), let rightPodcast = rhs.getPodcast() {
      return leftPodcast == rightPodcast
    }
    if let leftUnsaved = lhs.getUnsavedPodcast(), let rightUnsaved = rhs.getUnsavedPodcast() {
      return leftUnsaved == rightUnsaved
    }
    if let leftListable = lhs.getListablePodcast(), let rightListable = rhs.getListablePodcast() {
      return leftListable == rightListable
    }
    return false
  }

  // MARK: - Stringable / Searchable

  var toString: String { podcast.toString }
  var searchableString: String { podcast.searchableString }

  // MARK: - PodcastListable

  var podcastID: Podcast.ID? { podcast.podcastID }
  var feedURL: FeedURL { podcast.feedURL }
  var image: URL { podcast.image }
  var title: String { podcast.title }
  var description: String { podcast.description }
  var subscriptionDate: Date? { podcast.subscriptionDate }
  var subscribed: Bool { podcast.subscribed }

  // MARK: - PodcastDisplayable (conditional)

  var iTunesID: ITunesPodcastID? { (podcast as? any PodcastDisplayable)?.iTunesID }

  // MARK: - Getters

  func getListablePodcast() -> ListablePodcast? { podcast as? ListablePodcast }
  func getUnsavedPodcast() -> UnsavedPodcast? { podcast as? UnsavedPodcast }
  func getPodcast() -> Podcast? {
    if let searchResult = podcast as? SearchResultPodcast {
      return searchResult.podcast
    }
    return podcast as? Podcast
  }

  func getDisplayedPodcast() -> DisplayedPodcast? {
    guard let displayable = podcast as? any PodcastDisplayable else { return nil }
    return DisplayedPodcast(displayable)
  }

  func toOriginalUnsavedPodcast() throws -> UnsavedPodcast {
    if let searchResult = podcast as? SearchResultPodcast {
      return try searchResult.podcast.toOriginalUnsavedPodcast()
    } else if let podcast = getPodcast() {
      return try podcast.toOriginalUnsavedPodcast()
    } else if let unsavedPodcast = getUnsavedPodcast() {
      return try unsavedPodcast.toOriginalUnsavedPodcast()
    } else {
      Assert.fatal("Can't make Original UnsavedPodcast from: \(type(of: podcast))")
    }
  }

  func getOrCreatePodcast() async throws -> Podcast {
    if let podcast = getPodcast() {
      return podcast
    } else if let unsavedPodcast = getUnsavedPodcast() {
      return try await DisplayedPodcast.getOrCreatePodcast(unsavedPodcast)
    } else if let podcastID = podcast.podcastID {
      guard let podcastSeries = try await repo.podcastSeries(podcastID) else {
        Assert.fatal("Podcast not found for ID \(podcastID)")
      }
      return podcastSeries.podcast
    } else {
      Assert.fatal("Can't get or create Podcast from: \(type(of: podcast))")
    }
  }
}
