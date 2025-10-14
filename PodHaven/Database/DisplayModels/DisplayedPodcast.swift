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

  let podcast: any PodcastDisplayable

  init(_ podcast: any PodcastDisplayable) {
    Assert.precondition(
      !(podcast is DisplayedPodcast),
      "Cannot wrap an instance of itself as a DisplayedPodcast"
    )

    self.podcast = podcast
  }

  subscript<T>(dynamicMember keyPath: KeyPath<any PodcastDisplayable, T>) -> T {
    podcast[keyPath: keyPath]
  }

  // MARK: - Identifiable

  var id: FeedURL { feedURL }

  // MARK: - Hashable / Equatable

  func hash(into hasher: inout Hasher) {
    if let podcast = getPodcast() {
      hasher.combine(podcast)
    } else if let unsavedPodcast = getUnsavedPodcast() {
      hasher.combine(unsavedPodcast)
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

    return false  // Different concrete types are not equal
  }

  // MARK: - Stringable / Searchable

  var toString: String { podcast.toString }
  var searchableString: String { podcast.searchableString }

  // MARK: - PodcastDisplayable

  var podcastID: Podcast.ID? { podcast.podcastID }
  var feedURL: FeedURL { podcast.feedURL }
  var image: URL { podcast.image }
  var title: String { podcast.title }
  var description: String { podcast.description }
  var link: URL? { podcast.link }
  var subscriptionDate: Date? { podcast.subscriptionDate }
  var subscribed: Bool { podcast.subscribed }

  // MARK: - Helpers

  static func getOrCreatePodcast(_ podcast: any PodcastDisplayable) async throws -> Podcast {
    guard let displayedPodcast = podcast as? DisplayedPodcast
    else { return try await DisplayedPodcast(podcast).getOrCreatePodcast() }

    return try await displayedPodcast.getOrCreatePodcast()
  }

  func getOrCreatePodcast() async throws -> Podcast {
    if let podcast = getPodcast() {
      return podcast
    } else if let unsavedPodcast = getUnsavedPodcast() {
      if let existingSeries = try await repo.podcastSeries(unsavedPodcast.feedURL) {
        return existingSeries.podcast
      }

      // Podcast doesn't exist, parse feed and insert
      let podcastFeed = try await PodcastFeed.parse(unsavedPodcast.feedURL)
      let podcastSeries = try await repo.insertSeries(
        try podcastFeed.toUnsavedPodcast(),
        unsavedEpisodes: Array(podcastFeed.toEpisodeArray())
      )
      return podcastSeries.podcast
    } else {
      Assert.fatal("Can't make Podcast from: \(type(of: podcast))")
    }
  }

  func getPodcast() -> Podcast? { podcast as? Podcast }
  func getUnsavedPodcast() -> UnsavedPodcast? { podcast as? UnsavedPodcast }
}
