// Copyright Justin Bishop, 2026

import Foundation

struct DisplayedPodcast:
  PodcastDisplayable,
  Searchable,
  Stringable,
  Hashable,
  Sendable
{
  enum Source: Hashable, Sendable {
    case saved(Podcast)
    case unsaved(UnsavedPodcast)

    var canonicalPodcast: any PodcastDisplayable {
      switch self {
      case .saved(let podcast): return podcast
      case .unsaved(let podcast): return podcast
      }
    }

    var saved: Podcast? {
      guard case .saved(let podcast) = self else { return nil }
      return podcast
    }

    var unsaved: UnsavedPodcast? {
      guard case .unsaved(let podcast) = self else { return nil }
      return podcast
    }
  }

  let source: Source

  init(_ podcast: Podcast) { source = .saved(podcast) }
  init(_ podcast: UnsavedPodcast) { source = .unsaved(podcast) }

  // MARK: - Identifiable

  var id: FeedURL { feedURL }

  // MARK: - Hashable / Equatable

  func hash(into hasher: inout Hasher) { hasher.combine(source) }
  static func == (lhs: DisplayedPodcast, rhs: DisplayedPodcast) -> Bool {
    lhs.source == rhs.source
  }

  // MARK: - Stringable / Searchable

  var toString: String { source.canonicalPodcast.toString }
  var searchableString: String { source.canonicalPodcast.searchableString }

  // MARK: - PodcastListable

  var podcastID: Podcast.ID? { source.canonicalPodcast.podcastID }
  var feedURL: FeedURL { source.canonicalPodcast.feedURL }
  var iTunesID: ITunesPodcastID? { source.canonicalPodcast.iTunesID }
  var image: URL { source.canonicalPodcast.image }
  var title: String { source.canonicalPodcast.title }
  var subscriptionDate: Date? { source.canonicalPodcast.subscriptionDate }
  var subscribed: Bool { source.canonicalPodcast.subscribed }

  // MARK: - PodcastDisplayable

  var description: String { source.canonicalPodcast.description }
  var link: URL? { source.canonicalPodcast.link }
  var defaultPlaybackRate: Double? { source.canonicalPodcast.defaultPlaybackRate }
  var queueAllEpisodes: QueueAllEpisodes { source.canonicalPodcast.queueAllEpisodes }
  var cacheAllEpisodes: CacheAllEpisodes { source.canonicalPodcast.cacheAllEpisodes }
  var notifyNewEpisodes: Bool { source.canonicalPodcast.notifyNewEpisodes }
  var freshnessCadence: FreshnessCadence? { source.canonicalPodcast.freshnessCadence }

  // MARK: - Helpers

  func getOrCreatePodcast() async throws -> Podcast {
    switch source {
    case .saved(let podcast):
      return podcast
    case .unsaved(let unsavedPodcast):
      return try await unsavedPodcast.getOrCreatePodcast()
    }
  }
}
