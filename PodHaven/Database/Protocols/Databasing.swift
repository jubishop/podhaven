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
  func allPodcastSeries(_ filter: SQLExpression, order: SQLOrdering, limit: Int)
    async throws(RepoError)
    -> [PodcastSeries]

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
  func cachedEpisodes() async throws -> [Episode]

  // MARK: - Series Writers

  @discardableResult
  func insertSeries(_ unsavedPodcastSeries: UnsavedPodcastSeries) async throws(RepoError)
    -> PodcastSeries

  @discardableResult
  func updateSeriesFromFeed(
    podcastSeries: PodcastSeries,
    podcast: Podcast?,
    unsavedEpisodes: [UnsavedEpisode],
    existingEpisodes: [Episode]
  ) async throws(RepoError) -> [Episode]

  // MARK: - Podcast Writers

  @discardableResult
  func deletePodcast(_ podcastIDs: [Podcast.ID]) async throws -> Int

  @discardableResult
  func deletePodcast(_ podcastID: Podcast.ID) async throws -> Bool

  // MARK: - Episode Writers

  @discardableResult
  func upsertPodcastEpisodes(_ unsavedPodcastEpisodes: [UnsavedPodcastEpisode])
    async throws(RepoError) -> [PodcastEpisode]

  @discardableResult
  func upsertPodcastEpisode(_ unsavedPodcastEpisode: UnsavedPodcastEpisode) async throws(RepoError)
    -> PodcastEpisode

  // MARK: - Episode Attribute Writers

  @discardableResult
  func updateDuration(_ episodeID: Episode.ID, duration: CMTime) async throws -> Bool

  @discardableResult
  func updateCurrentTime(_ episodeID: Episode.ID, currentTime: CMTime) async throws -> Bool

  @discardableResult
  func updateDownloadTaskID(_ episodeID: Episode.ID, downloadTaskID: URLSessionDownloadTask.ID?)
    async throws
    -> Bool

  @discardableResult
  func updateCachedFilename(_ episodeID: Episode.ID, cachedFilename: String?) async throws -> Bool

  @discardableResult
  func updateSaveInCache(_ episodeID: Episode.ID, saveInCache: Bool) async throws -> Bool

  @discardableResult
  func markFinished(_ episodeIDs: [Episode.ID]) async throws -> Int

  @discardableResult
  func markFinished(_ episodeID: Episode.ID) async throws -> Bool

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
  func updateDefaultPlaybackRate(_ podcastID: Podcast.ID, defaultPlaybackRate: Double?) async throws
    -> Bool

  @discardableResult
  func updateQueueAllEpisodes(_ podcastID: Podcast.ID, queueAllEpisodes: QueueAllEpisodes)
    async throws -> Bool

  @discardableResult
  func updateCacheAllEpisodes(_ podcastID: Podcast.ID, cacheAllEpisodes: CacheAllEpisodes)
    async throws -> Bool

  @discardableResult
  func updateNotifyNewEpisodes(_ podcastID: Podcast.ID, notifyNewEpisodes: Bool)
    async throws -> Bool
}
