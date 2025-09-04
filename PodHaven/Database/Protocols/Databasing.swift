// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import IdentifiedCollections
import Tagged

protocol Databasing: Sendable {
  var db: any DatabaseReader { get }

  // MARK: - Global Readers

  func allPodcasts(_ filter: SQLExpression) async throws -> [Podcast]
  func allPodcastSeries(_ filter: SQLExpression) async throws(RepoError) -> [PodcastSeries]

  // MARK: - Series Readers

  func podcastSeries(_ podcastID: Podcast.ID) async throws(RepoError) -> PodcastSeries?
  func podcastSeries(_ feedURL: FeedURL) async throws -> PodcastSeries?

  // MARK: - Episode Readers

  func episode(_ episodeID: Episode.ID) async throws -> Episode?
  func episode(_ mediaGUID: MediaGUID) async throws -> Episode?
  func episode(_ downloadTaskID: URLSessionDownloadTask.ID) async throws -> Episode?
  func episodes(_ downloadTaskIDs: [URLSessionDownloadTask.ID]) async throws -> [Episode]
  func podcastEpisode(_ episodeID: Episode.ID) async throws -> PodcastEpisode?
  func podcastEpisode(_ mediaGUID: MediaGUID) async throws -> PodcastEpisode?
  func latestEpisode(for podcastID: Podcast.ID) async throws -> Episode?

  // MARK: - Series Writers

  @discardableResult
  func insertSeries(_ unsavedPodcast: UnsavedPodcast, unsavedEpisodes: [UnsavedEpisode])
    async throws(RepoError) -> PodcastSeries

  func updateSeriesFromFeed(
    podcastID: Podcast.ID,
    podcast: Podcast?,
    unsavedEpisodes: [UnsavedEpisode],
    existingEpisodes: [Episode]
  ) async throws(RepoError)

  // MARK: - Podcast Writers

  @discardableResult
  func delete(_ podcastIDs: [Podcast.ID]) async throws -> Int

  @discardableResult
  func delete(_ podcastID: Podcast.ID) async throws -> Bool

  // MARK: - Episode Writers

  @discardableResult
  func upsertPodcastEpisodes(_ unsavedPodcastEpisodes: [UnsavedPodcastEpisode])
    async throws(RepoError) -> [PodcastEpisode]

  @discardableResult
  func upsertPodcastEpisode(_ unsavedPodcastEpisode: UnsavedPodcastEpisode) async throws(RepoError)
    -> PodcastEpisode

  @discardableResult
  func updateDuration(_ episodeID: Episode.ID, _ duration: CMTime) async throws -> Bool

  @discardableResult
  func updateCurrentTime(_ episodeID: Episode.ID, _ currentTime: CMTime) async throws -> Bool

  @discardableResult
  func updateCachedFilename(_ episodeID: Episode.ID, _ cachedFilename: String?) async throws -> Bool

  @discardableResult
  func updateDownloadTaskID(_ episodeID: Episode.ID, _ downloadTaskID: URLSessionDownloadTask.ID?)
    async throws
    -> Bool

  @discardableResult
  func markComplete(_ episodeID: Episode.ID) async throws -> Bool

  @discardableResult
  func markSubscribed(_ podcastIDs: [Podcast.ID]) async throws -> Int

  @discardableResult
  func markSubscribed(_ podcastID: Podcast.ID) async throws -> Bool

  @discardableResult
  func markUnsubscribed(_ podcastIDs: [Podcast.ID]) async throws -> Int

  @discardableResult
  func markUnsubscribed(_ podcastID: Podcast.ID) async throws -> Bool

  @discardableResult
  func updateLastUpdate(_ podcastID: Podcast.ID) async throws -> Bool

  @discardableResult
  func updateCacheAll(_ podcastID: Podcast.ID, cacheAllEpisodes: Bool) async throws -> Bool

}

extension Databasing {
  // MARK: - Default Parameter Extensions

  func allPodcasts() async throws -> [Podcast] {
    try await allPodcasts(AppDB.NoOp)
  }

  func allPodcastSeries() async throws(RepoError) -> [PodcastSeries] {
    try await allPodcastSeries(AppDB.NoOp)
  }

  @discardableResult
  func insertSeries(_ unsavedPodcast: UnsavedPodcast) async throws(RepoError) -> PodcastSeries {
    try await insertSeries(unsavedPodcast, unsavedEpisodes: [])
  }

  func updateSeriesFromFeed(
    podcastID: Podcast.ID,
    podcast: Podcast?
  ) async throws(RepoError) {
    try await updateSeriesFromFeed(
      podcastID: podcastID,
      podcast: podcast,
      unsavedEpisodes: [],
      existingEpisodes: []
    )
  }

  func updateSeriesFromFeed(
    podcastID: Podcast.ID,
    podcast: Podcast?,
    unsavedEpisodes: [UnsavedEpisode]
  ) async throws(RepoError) {
    try await updateSeriesFromFeed(
      podcastID: podcastID,
      podcast: podcast,
      unsavedEpisodes: unsavedEpisodes,
      existingEpisodes: []
    )
  }

  func updateSeriesFromFeed(
    podcastID: Podcast.ID,
    podcast: Podcast?,
    existingEpisodes: [Episode]
  ) async throws(RepoError) {
    try await updateSeriesFromFeed(
      podcastID: podcastID,
      podcast: podcast,
      unsavedEpisodes: [],
      existingEpisodes: existingEpisodes
    )
  }
}
