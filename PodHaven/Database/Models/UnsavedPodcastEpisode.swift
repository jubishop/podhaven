// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Logging

struct UnsavedPodcastEpisode:
  Codable,
  EpisodeDisplayable,
  Equatable,
  Hashable,
  Stringable
{
  private static let log = Log.as(LogSubsystem.Database.episode)

  var id: MediaGUID { unsavedEpisode.id }

  // MARK: - Stringable / Searchable

  var toString: String { unsavedEpisode.toString }
  var searchableString: String {
    "\(unsavedPodcast.searchableString) - \(unsavedEpisode.searchableString)"
  }

  // MARK: - Data

  let unsavedPodcast: UnsavedPodcast
  let unsavedEpisode: UnsavedEpisode

  // MARK: - EpisodeDisplayable

  var feedURL: FeedURL { unsavedPodcast.feedURL }
  var podcastTitle: String { unsavedPodcast.title }
  var image: URL { unsavedEpisode.image ?? unsavedPodcast.image }
  var podcastImage: URL { unsavedPodcast.image }
  var saveInCache: Bool { unsavedEpisode.saveInCache }

  // MARK: - EpisodeFoundational

  var episodeID: Episode.ID? { nil }
  var mediaGUID: MediaGUID { unsavedEpisode.id }
  var title: String { unsavedEpisode.title }
  var pubDate: Date { unsavedEpisode.pubDate }
  var description: String? { unsavedEpisode.description }
  var duration: CMTime { unsavedEpisode.duration }
  var currentTime: CMTime { unsavedEpisode.currentTime }
  var queueDate: Date? { unsavedEpisode.queueDate }
  var queueOrder: Int? { unsavedEpisode.queueOrder }
  var cacheStatus: Episode.CacheStatus { unsavedEpisode.cacheStatus }
  var finishDate: Date? { unsavedEpisode.finishDate }
  var rating: EpisodeRating? { unsavedEpisode.rating }

  // MARK: - Helpers

  // Materializes this unsaved episode into the database. When its podcast is new
  // to the database, the whole series is pulled from the feed and saved so a
  // podcast never lands holding only the acted-on episode. Falls back to saving
  // just this episode when the podcast already exists or the feed can't be
  // pulled, so the calling action always resolves to a real row.
  func getOrCreatePodcastEpisodeSavingSeries() async throws -> PodcastEpisode {
    let repo = Container.shared.repo()

    let alreadySaved =
      try await repo.podcastSeries(unsavedPodcast.feedURL, iTunesID: unsavedPodcast.iTunesID) != nil
    guard !alreadySaved else { return try await repo.upsertPodcastEpisode(self) }

    let series: UnsavedPodcastSeries
    do {
      series = try await PodcastFeed.parse(unsavedPodcast.feedURL)
        .toUnsavedSeries(iTunesID: unsavedPodcast.iTunesID)
    } catch {
      Self.log.caughtError(
        "Pulling full series failed for \(unsavedPodcast.feedURL); saving lone episode",
        error,
        level: .info
      )
      return try await repo.upsertPodcastEpisode(self)
    }

    let podcastEpisodes = try await repo.upsertPodcastEpisodes(
      series.unsavedEpisodes.map {
        UnsavedPodcastEpisode(unsavedPodcast: series.unsavedPodcast, unsavedEpisode: $0)
      }
    )
    guard let match = podcastEpisodes.first(where: { $0.mediaGUID == mediaGUID })
    else {
      // The acted-on episode predates the pulled feed window, so persist it on
      // its own to guarantee the action resolves to a real row.
      Self.log.info(
        """
        Acted-on \(mediaGUID) absent from \(podcastEpisodes.count) pulled \
        \(unsavedPodcast.feedURL) episodes; saving lone episode
        """
      )
      return try await repo.upsertPodcastEpisode(self)
    }
    return match
  }
}
