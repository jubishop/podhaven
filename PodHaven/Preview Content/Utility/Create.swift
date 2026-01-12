#if DEBUG
// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import IdentifiedCollections
import Tagged

enum Create {
  static func unsavedEpisode(
    podcastId: Podcast.ID? = nil,
    guid: GUID = GUID(String.random()),
    mediaURL: MediaURL = MediaURL(URL.valid()),
    title: String = String.random(),
    pubDate: Date? = Date(),
    duration: CMTime? = nil,
    description: String? = nil,
    link: URL? = nil,
    image: URL? = nil,
    finishDate: Date? = nil,
    currentTime: CMTime? = nil,
    queueOrder: Int? = nil,
    queueDate: Date? = nil,
    cachedFilename: String? = nil,
    saveInCache: Bool = false
  ) throws -> UnsavedEpisode {
    try UnsavedEpisode(
      podcastId: podcastId,
      guid: guid,
      mediaURL: mediaURL,
      title: title,
      pubDate: pubDate,
      duration: duration,
      description: description,
      link: link,
      image: image,
      finishDate: finishDate,
      currentTime: currentTime,
      queueOrder: queueOrder,
      queueDate: queueDate,
      cachedFilename: cachedFilename,
      saveInCache: saveInCache
    )
  }

  static func unsavedPodcast(
    feedURL: FeedURL = FeedURL(URL.valid()),
    title: String = String.random(),
    image: URL = URL.valid(),
    description: String = String.random(),
    link: URL? = nil,
    lastUpdate: Date? = nil,
    subscriptionDate: Date? = nil,
    defaultPlaybackRate: Double? = nil,
    queueAllEpisodes: QueueAllEpisodes = .never,
    cacheAllEpisodes: CacheAllEpisodes = .never,
    notifyNewEpisodes: Bool = false
  ) throws -> UnsavedPodcast {
    try UnsavedPodcast(
      feedURL: feedURL,
      title: title,
      image: image,
      description: description,
      link: link,
      lastUpdate: lastUpdate,
      subscriptionDate: subscriptionDate,
      defaultPlaybackRate: defaultPlaybackRate,
      queueAllEpisodes: queueAllEpisodes,
      cacheAllEpisodes: cacheAllEpisodes,
      notifyNewEpisodes: notifyNewEpisodes
    )
  }

  static func podcast(
    feedURL: FeedURL = FeedURL(URL.valid()),
    title: String = String.random(),
    image: URL = URL.valid(),
    description: String = String.random(),
    link: URL? = nil,
    lastUpdate: Date? = nil,
    subscriptionDate: Date? = nil,
    defaultPlaybackRate: Double? = nil,
    queueAllEpisodes: QueueAllEpisodes = .never,
    cacheAllEpisodes: CacheAllEpisodes = .never,
    notifyNewEpisodes: Bool = false
  ) async throws -> Podcast {
    try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast:
            try unsavedPodcast(
              feedURL: feedURL,
              title: title,
              image: image,
              description: description,
              link: link,
              lastUpdate: lastUpdate,
              subscriptionDate: subscriptionDate,
              defaultPlaybackRate: defaultPlaybackRate,
              queueAllEpisodes: queueAllEpisodes,
              cacheAllEpisodes: cacheAllEpisodes,
              notifyNewEpisodes: notifyNewEpisodes
            )
        )
      )
      .podcast
  }

  static func threePodcastEpisodes(
    _ one: UnsavedPodcastEpisode? = nil,
    _ two: UnsavedPodcastEpisode? = nil,
    _ three: UnsavedPodcastEpisode? = nil
  ) async throws -> (PodcastEpisode, PodcastEpisode, PodcastEpisode) {
    let repo = Container.shared.repo()
    let podcastSeriesOne = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try one?.unsavedPodcast ?? unsavedPodcast(),
        unsavedEpisodes: [try one?.unsavedEpisode ?? unsavedEpisode()]
      )
    )
    let podcastSeriesTwo = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try two?.unsavedPodcast ?? unsavedPodcast(),
        unsavedEpisodes: [try two?.unsavedEpisode ?? unsavedEpisode()]
      )
    )
    let podcastSeriesThree = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast:
          try three?.unsavedPodcast ?? unsavedPodcast(),
        unsavedEpisodes: [try three?.unsavedEpisode ?? unsavedEpisode()]
      )
    )

    return (
      PodcastEpisode(
        podcast: podcastSeriesOne.podcast,
        episode: podcastSeriesOne.episodes[0]
      ),
      PodcastEpisode(
        podcast: podcastSeriesTwo.podcast,
        episode: podcastSeriesTwo.episodes[0]
      ),
      PodcastEpisode(
        podcast: podcastSeriesThree.podcast,
        episode: podcastSeriesThree.episodes[0]
      )
    )
  }

  static func twoPodcastEpisodes(
    _ one: UnsavedPodcastEpisode? = nil,
    _ two: UnsavedPodcastEpisode? = nil
  )
    async throws -> (PodcastEpisode, PodcastEpisode)
  {
    let (one, two, _) = try await threePodcastEpisodes(one, two)
    return (one, two)
  }

  static func twoPodcastEpisodes(_ one: UnsavedEpisode, _ two: UnsavedEpisode? = nil) async throws
    -> (
      PodcastEpisode, PodcastEpisode
    )
  {
    let (one, two) = try await twoPodcastEpisodes(
      UnsavedPodcastEpisode(unsavedPodcast: try unsavedPodcast(), unsavedEpisode: one),
      UnsavedPodcastEpisode(
        unsavedPodcast: try unsavedPodcast(),
        unsavedEpisode: try two ?? unsavedEpisode()
      )
    )
    return (one, two)
  }

  static func podcastEpisode(_ one: UnsavedPodcastEpisode? = nil) async throws -> PodcastEpisode {
    let (one, _) = try await twoPodcastEpisodes(one)
    return one
  }

  static func podcastEpisode(_ one: UnsavedEpisode) async throws -> PodcastEpisode {
    try await podcastEpisode(
      UnsavedPodcastEpisode(unsavedPodcast: try unsavedPodcast(), unsavedEpisode: one)
    )
  }
}
#endif
