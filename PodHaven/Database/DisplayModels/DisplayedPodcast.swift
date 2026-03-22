// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation

@dynamicMemberLookup
struct DisplayedPodcast:
  PodcastDisplayable,
  Searchable,
  Stringable,
  Hashable,
  Sendable
{
  @DynamicInjected(\.repo) private var repo

  let podcast: any PodcastListable

  init(_ podcast: any PodcastListable) {
    Assert.precondition(
      !(podcast is DisplayedPodcast),
      "Cannot wrap an instance of itself as a DisplayedPodcast"
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
    if let podcast = getPodcast() {
      hasher.combine(podcast)
    } else if let unsavedPodcast = getUnsavedPodcast() {
      hasher.combine(unsavedPodcast)
    } else if let listablePodcast = podcast as? ListablePodcast {
      hasher.combine(listablePodcast)
    } else {
      Assert.fatal("Can't make hash from: \(type(of: podcast))")
    }
  }

  static func == (lhs: DisplayedPodcast, rhs: DisplayedPodcast) -> Bool {
    if let leftPodcast = lhs.getPodcast(), let rightPodcast = rhs.getPodcast() {
      return leftPodcast == rightPodcast
    }

    if let leftUnsavedPodcast = lhs.getUnsavedPodcast(),
      let rightUnsavedPodcast = rhs.getUnsavedPodcast()
    {
      return leftUnsavedPodcast == rightUnsavedPodcast
    }

    if let leftListable = lhs.podcast as? ListablePodcast,
      let rightListable = rhs.podcast as? ListablePodcast
    {
      return leftListable == rightListable
    }

    return false  // Different concrete types are not equal
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

  // MARK: - PodcastDisplayable (delegated when available, defaults otherwise)

  var iTunesID: ITunesPodcastID? { displayable?.iTunesID }
  var link: URL? { displayable?.link }
  var defaultPlaybackRate: Double? { displayable?.defaultPlaybackRate }
  var queueAllEpisodes: QueueAllEpisodes { displayable?.queueAllEpisodes ?? .never }
  var cacheAllEpisodes: CacheAllEpisodes { displayable?.cacheAllEpisodes ?? .never }
  var notifyNewEpisodes: Bool { displayable?.notifyNewEpisodes ?? false }

  private var displayable: (any PodcastDisplayable)? { podcast as? any PodcastDisplayable }

  // MARK: - Helpers

  static func getOrCreatePodcast(_ podcast: any PodcastListable) async throws -> Podcast {
    try await getDisplayedPodcast(podcast).getOrCreatePodcast()
  }
  func getOrCreatePodcast() async throws -> Podcast {
    if let podcast = getPodcast() {
      return podcast
    } else if let unsavedPodcast = getUnsavedPodcast() {
      if let existingSeries = try await repo.podcastSeries(
        unsavedPodcast.feedURL,
        iTunesID: unsavedPodcast.iTunesID
      ) {
        return existingSeries.podcast
      }

      // Podcast doesn't exist by our keys, parse feed to discover resolved URL
      let podcastFeed = try await PodcastFeed.parse(unsavedPodcast.feedURL)

      // The parsed feed may have a different feedURL (redirect/itunes:new-feed-url).
      // Check if that resolved URL matches an existing podcast.
      if podcastFeed.updatedFeedURL != unsavedPodcast.feedURL {
        if let existingSeries = try await repo.podcastSeries(
          podcastFeed.updatedFeedURL,
          iTunesID: unsavedPodcast.iTunesID
        ) {
          if existingSeries.podcast.iTunesID == nil, let iTunesID = unsavedPodcast.iTunesID {
            try await repo.updateITunesID(existingSeries.podcast.id, iTunesID: iTunesID)
          }
          return existingSeries.podcast
        }
      }

      let podcastSeries = try await repo.insertSeries(
        try podcastFeed.toUnsavedSeries(iTunesID: unsavedPodcast.iTunesID)
      )
      return podcastSeries.podcast
    } else if let podcastID = podcast.podcastID {
      guard let podcastSeries = try await repo.podcastSeries(podcastID) else {
        Assert.fatal("Podcast not found for ID \(podcastID)")
      }
      return podcastSeries.podcast
    } else {
      Assert.fatal("Can't make Podcast from: \(type(of: podcast))")
    }
  }

  static func getPodcast(_ podcast: any PodcastListable) -> Podcast? {
    getDisplayedPodcast(podcast).getPodcast()
  }
  func getPodcast() -> Podcast? {
    if let searchResult = podcast as? SearchResultPodcast {
      return searchResult.podcast
    }
    return podcast as? Podcast
  }

  static func getUnsavedPodcast(_ podcast: any PodcastListable) -> UnsavedPodcast? {
    getDisplayedPodcast(podcast).getUnsavedPodcast()
  }
  func getUnsavedPodcast() -> UnsavedPodcast? { podcast as? UnsavedPodcast }

  static func toOriginalUnsavedPodcast(_ podcast: any PodcastListable) throws
    -> UnsavedPodcast
  {
    try getDisplayedPodcast(podcast).toOriginalUnsavedPodcast()
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

  static func getDisplayedPodcast(_ podcast: any PodcastListable) -> DisplayedPodcast {
    guard let displayedPodcast = podcast as? DisplayedPodcast
    else { return DisplayedPodcast(podcast) }

    return displayedPodcast
  }
}
