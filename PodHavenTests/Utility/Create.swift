// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Tagged

@testable import PodHaven

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
    cachedMediaURL: URL? = nil
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
      cachedMediaURL: cachedMediaURL
    )
  }

  static func unsavedPodcast(
    feedURL: FeedURL = FeedURL(URL.valid()),
    title: String = String.random(),
    image: URL = URL.valid(),
    description: String = String.random(),
    link: URL? = nil,
    lastUpdate: Date? = nil,
    subscriptionDate: Date? = nil
  ) throws -> UnsavedPodcast {
    try UnsavedPodcast(
      feedURL: feedURL,
      title: title,
      image: image,
      description: description,
      link: link,
      lastUpdate: lastUpdate,
      subscriptionDate: subscriptionDate
    )
  }

  static func threePodcastEpisodes(
    _ one: UnsavedEpisode? = nil,
    _ two: UnsavedEpisode? = nil,
    _ three: UnsavedEpisode? = nil
  ) async throws -> (PodcastEpisode, PodcastEpisode, PodcastEpisode) {
    let repo = Container.shared.repo()
    let podcastSeries = try await repo.insertSeries(
      Create.unsavedPodcast(),
      unsavedEpisodes: [
        try one ?? unsavedEpisode(),
        try two ?? unsavedEpisode(),
        try three ?? unsavedEpisode(),
      ]
    )
    return (
      PodcastEpisode(
        podcast: podcastSeries.podcast,
        episode: podcastSeries.episodes[0]
      ),
      PodcastEpisode(
        podcast: podcastSeries.podcast,
        episode: podcastSeries.episodes[1]
      ),
      PodcastEpisode(
        podcast: podcastSeries.podcast,
        episode: podcastSeries.episodes[2]
      )
    )
  }

  static func twoPodcastEpisodes(_ one: UnsavedEpisode? = nil, _ two: UnsavedEpisode? = nil)
    async throws -> (PodcastEpisode, PodcastEpisode)
  {
    let (one, two, _) = try await threePodcastEpisodes(one, two)
    return (one, two)
  }

  static func podcastEpisode(_ one: UnsavedEpisode? = nil) async throws -> PodcastEpisode {
    let (one, _) = try await twoPodcastEpisodes(one)
    return one
  }
}
