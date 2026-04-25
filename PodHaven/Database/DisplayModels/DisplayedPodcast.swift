// Copyright Justin Bishop, 2026

import Foundation

@dynamicMemberLookup
struct DisplayedPodcast:
  PodcastDisplayable,
  Searchable,
  Stringable,
  Hashable,
  Sendable
{
  let podcast: any PodcastDisplayable

  init(_ podcast: any PodcastDisplayable) {
    Assert.precondition(
      !(podcast is DisplayedPodcast),
      "Cannot wrap a wrapper type as a DisplayedPodcast"
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
    AnyHashable(podcast).hash(into: &hasher)
  }

  static func == (lhs: DisplayedPodcast, rhs: DisplayedPodcast) -> Bool {
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

  // MARK: - PodcastDisplayable

  var description: String { podcast.description }
  var link: URL? { podcast.link }
  var defaultPlaybackRate: Double? { podcast.defaultPlaybackRate }
  var queueAllEpisodes: QueueAllEpisodes { podcast.queueAllEpisodes }
  var cacheAllEpisodes: CacheAllEpisodes { podcast.cacheAllEpisodes }
  var notifyNewEpisodes: Bool { podcast.notifyNewEpisodes }
  var freshnessCadence: FreshnessCadence { podcast.freshnessCadence }

  // MARK: - Helpers

  func getOrCreatePodcast() async throws -> Podcast {
    if let podcast = getPodcast() {
      return podcast
    } else if let unsavedPodcast = getUnsavedPodcast() {
      return try await unsavedPodcast.getOrCreatePodcast()
    } else {
      Assert.fatal("Can't make Podcast from: \(type(of: podcast))")
    }
  }

  func getPodcast() -> Podcast? { podcast as? Podcast }
  func getUnsavedPodcast() -> UnsavedPodcast? { podcast as? UnsavedPodcast }
}
