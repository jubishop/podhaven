#if DEBUG
// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Tagged

enum Create {
  static func unsavedEpisode(
    podcastId: Podcast.ID? = nil,
    guid: GUID = GUID(String.random()),
    media: MediaURL = MediaURL(URL.valid()),
    title: String = String.random(),
    pubDate: Date? = Date(),
    duration: CMTime? = nil,
    description: String? = nil,
    link: URL? = nil,
    image: URL? = nil,
    completionDate: Date? = nil,
    currentTime: CMTime? = nil,
    queueOrder: Int? = nil,
    lastQueued: Date? = nil,
    cachedFilename: String? = nil,
    creationDate: Date? = nil
  ) throws -> UnsavedEpisode {
    try UnsavedEpisode(
      podcastId: podcastId,
      guid: guid,
      media: media,
      title: title,
      pubDate: pubDate,
      duration: duration,
      description: description,
      link: link,
      image: image,
      completionDate: completionDate,
      currentTime: currentTime,
      queueOrder: queueOrder,
      lastQueued: lastQueued,
      cachedFilename: cachedFilename,
      creationDate: creationDate
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
    cacheAllEpisodes: Bool = false,
    creationDate: Date? = nil
  ) throws -> UnsavedPodcast {
    try UnsavedPodcast(
      feedURL: feedURL,
      title: title,
      image: image,
      description: description,
      link: link,
      lastUpdate: lastUpdate,
      subscriptionDate: subscriptionDate,
      cacheAllEpisodes: cacheAllEpisodes,
      creationDate: creationDate
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
    cacheAllEpisodes: Bool = false,
    creationDate: Date = Date()
  ) async throws -> Podcast {
    try await Container.shared.repo()
      .insertSeries(
        try unsavedPodcast(
          feedURL: feedURL,
          title: title,
          image: image,
          description: description,
          link: link,
          lastUpdate: lastUpdate,
          subscriptionDate: subscriptionDate,
          cacheAllEpisodes: cacheAllEpisodes,
          creationDate: creationDate
        ),
        unsavedEpisodes: []
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
      try one?.unsavedPodcast ?? unsavedPodcast(),
      unsavedEpisodes: [try one?.unsavedEpisode ?? unsavedEpisode()]
    )
    let podcastSeriesTwo = try await repo.insertSeries(
      try two?.unsavedPodcast ?? unsavedPodcast(),
      unsavedEpisodes: [try two?.unsavedEpisode ?? unsavedEpisode()]
    )
    let podcastSeriesThree = try await repo.insertSeries(
      try three?.unsavedPodcast ?? unsavedPodcast(),
      unsavedEpisodes: [try three?.unsavedEpisode ?? unsavedEpisode()]
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
