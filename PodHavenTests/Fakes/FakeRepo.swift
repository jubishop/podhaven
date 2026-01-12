// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import IdentifiedCollections
import Tagged

@testable import PodHaven

actor FakeRepo: Databasing, Sendable, FakeCallable {
  let callOrder = ThreadSafe<Int>(0)
  let callsByType = ThreadSafe<[ObjectIdentifier: [any MethodCalling]]>([:])

  private let repo: Repo

  init(_ repo: Repo) {
    self.repo = repo
  }

  // MARK: - Databasing

  nonisolated var db: any DatabaseReader { repo.db }

  // MARK: - Global Readers

  func allPodcasts(_ filter: SQLExpression) async throws -> [Podcast] {
    try await repo.allPodcasts(filter)
  }

  func allPodcastSeries(
    _ filter: SQLExpression,
    order: SQLOrdering = Podcast.Columns.id.desc,
    limit: Int = Int.max
  ) async throws(RepoError)
    -> [PodcastSeries]
  {
    recordCall(
      methodName: "allPodcastSeries",
      parameters: (filter: filter, order: order, limit: limit)
    )
    return try await repo.allPodcastSeries(filter, order: order, limit: limit)
  }

  // MARK: - Series Readers

  func podcastSeries(_ podcastID: Podcast.ID) async throws(RepoError) -> PodcastSeries? {
    recordCall(methodName: "podcastSeries", parameters: podcastID)
    return try await repo.podcastSeries(podcastID)
  }

  func podcastSeries(_ feedURL: FeedURL) async throws -> PodcastSeries? {
    recordCall(methodName: "podcastSeries", parameters: feedURL)
    return try await repo.podcastSeries(feedURL)
  }

  // MARK: - Episode Readers

  func episode(_ episodeID: Episode.ID) async throws -> Episode? {
    recordCall(methodName: "episode", parameters: episodeID)
    return try await repo.episode(episodeID)
  }

  func episode(_ mediaGUID: MediaGUID) async throws -> Episode? {
    recordCall(methodName: "episode", parameters: mediaGUID)
    return try await repo.episode(mediaGUID)
  }

  func episode(_ downloadTaskID: URLSessionDownloadTask.ID) async throws -> Episode? {
    recordCall(methodName: "episode", parameters: downloadTaskID)
    return try await repo.episode(downloadTaskID)
  }

  func episodes(_ downloadTaskIDs: [URLSessionDownloadTask.ID]) async throws -> [Episode] {
    recordCall(methodName: "episodes", parameters: downloadTaskIDs)
    return try await repo.episodes(downloadTaskIDs)
  }

  func podcastEpisode(_ episodeID: Episode.ID) async throws -> PodcastEpisode? {
    recordCall(methodName: "podcastEpisode", parameters: episodeID)
    return try await repo.podcastEpisode(episodeID)
  }

  func podcastEpisode(_ mediaGUID: MediaGUID) async throws -> PodcastEpisode? {
    recordCall(methodName: "podcastEpisode", parameters: mediaGUID)
    return try await repo.podcastEpisode(mediaGUID)
  }

  func latestEpisode(for podcastID: Podcast.ID) async throws -> Episode? {
    recordCall(methodName: "latestEpisode", parameters: podcastID)
    return try await repo.latestEpisode(for: podcastID)
  }

  func cachedEpisodes() async throws -> [Episode] {
    recordCall(methodName: "cachedEpisodes")
    return try await repo.cachedEpisodes()
  }

  // MARK: - Series Writers

  @discardableResult
  func insertSeries(_ unsavedPodcastSeries: UnsavedPodcastSeries) async throws(RepoError)
    -> PodcastSeries
  {
    recordCall(
      methodName: "insertSeries",
      parameters: unsavedPodcastSeries
    )
    return try await repo.insertSeries(unsavedPodcastSeries)
  }

  func updateSeriesFromFeed(
    podcastSeries: PodcastSeries,
    podcast: Podcast?,
    unsavedEpisodes: [UnsavedEpisode],
    existingEpisodes: [Episode]
  ) async throws(RepoError) -> [Episode] {
    recordCall(
      methodName: "updateSeriesFromFeed",
      parameters: (
        podcastSeries: podcastSeries,
        podcast: podcast,
        unsavedEpisodes: unsavedEpisodes,
        existingEpisodes: existingEpisodes
      )
    )
    return try await repo.updateSeriesFromFeed(
      podcastSeries: podcastSeries,
      podcast: podcast,
      unsavedEpisodes: unsavedEpisodes,
      existingEpisodes: existingEpisodes
    )
  }

  // MARK: - Podcast Writers

  @discardableResult
  func deletePodcast(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    recordCall(methodName: "delete", parameters: podcastIDs)
    return try await repo.deletePodcast(podcastIDs)
  }

  @discardableResult
  func deletePodcast(_ podcastID: Podcast.ID) async throws -> Bool {
    recordCall(methodName: "delete", parameters: podcastID)
    return try await repo.deletePodcast(podcastID)
  }

  // MARK: - Episode Writers

  @discardableResult
  func upsertPodcastEpisodes(_ unsavedPodcastEpisodes: [UnsavedPodcastEpisode])
    async throws(RepoError) -> [PodcastEpisode]
  {
    recordCall(methodName: "upsertPodcastEpisodes", parameters: unsavedPodcastEpisodes)
    return try await repo.upsertPodcastEpisodes(unsavedPodcastEpisodes)
  }

  @discardableResult
  func upsertPodcastEpisode(_ unsavedPodcastEpisode: UnsavedPodcastEpisode) async throws(RepoError)
    -> PodcastEpisode
  {
    recordCall(methodName: "upsertPodcastEpisode", parameters: unsavedPodcastEpisode)
    return try await repo.upsertPodcastEpisode(unsavedPodcastEpisode)
  }

  // MARK: - Episode Attribute Writers

  @discardableResult
  func updateDuration(_ episodeID: Episode.ID, duration: CMTime) async throws -> Bool {
    recordCall(methodName: "updateDuration", parameters: (episodeID: episodeID, duration: duration))
    return try await repo.updateDuration(episodeID, duration: duration)
  }

  @discardableResult
  func updateCurrentTime(_ episodeID: Episode.ID, currentTime: CMTime) async throws -> Bool {
    recordCall(
      methodName: "updateCurrentTime",
      parameters: (episodeID: episodeID, currentTime: currentTime)
    )
    return try await repo.updateCurrentTime(episodeID, currentTime: currentTime)
  }

  @discardableResult
  func updateDownloadTaskID(_ episodeID: Episode.ID, downloadTaskID: URLSessionDownloadTask.ID?)
    async throws
    -> Bool
  {
    recordCall(
      methodName: "updateDownloadTaskID",
      parameters: (episodeID: episodeID, downloadTaskID: downloadTaskID)
    )
    return try await repo.updateDownloadTaskID(episodeID, downloadTaskID: downloadTaskID)
  }

  @discardableResult
  func updateCachedFilename(_ episodeID: Episode.ID, cachedFilename: String?) async throws -> Bool {
    recordCall(
      methodName: "updateCachedFilename",
      parameters: (episodeID: episodeID, cachedFilename: cachedFilename)
    )
    return try await repo.updateCachedFilename(episodeID, cachedFilename: cachedFilename)
  }

  @discardableResult
  func updateSaveInCache(_ episodeID: Episode.ID, saveInCache: Bool) async throws -> Bool {
    recordCall(
      methodName: "updateSaveInCache",
      parameters: (episodeID: episodeID, saveInCache: saveInCache)
    )
    return try await repo.updateSaveInCache(episodeID, saveInCache: saveInCache)
  }

  @discardableResult
  func markFinished(_ episodeIDs: [Episode.ID]) async throws -> Int {
    recordCall(methodName: "markFinished", parameters: episodeIDs)
    return try await repo.markFinished(episodeIDs)
  }

  @discardableResult
  func markFinished(_ episodeID: Episode.ID) async throws -> Bool {
    recordCall(methodName: "markFinished", parameters: episodeID)
    return try await markFinished([episodeID]) > 0
  }

  @discardableResult
  func markSubscribed(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    recordCall(methodName: "markSubscribed", parameters: podcastIDs)
    return try await repo.markSubscribed(podcastIDs)
  }

  @discardableResult
  func markSubscribed(_ podcastID: Podcast.ID) async throws -> Bool {
    recordCall(methodName: "markSubscribed", parameters: podcastID)
    return try await repo.markSubscribed(podcastID)
  }

  @discardableResult
  func markUnsubscribed(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    recordCall(methodName: "markUnsubscribed", parameters: podcastIDs)
    return try await repo.markUnsubscribed(podcastIDs)
  }

  @discardableResult
  func markUnsubscribed(_ podcastID: Podcast.ID) async throws -> Bool {
    recordCall(methodName: "markUnsubscribed", parameters: podcastID)
    return try await repo.markUnsubscribed(podcastID)
  }

  @discardableResult
  func updateLastUpdate(_ podcastID: Podcast.ID) async throws -> Bool {
    recordCall(methodName: "updateLastUpdate", parameters: podcastID)
    return try await repo.updateLastUpdate(podcastID)
  }

  @discardableResult
  func updateDefaultPlaybackRate(_ podcastID: Podcast.ID, defaultPlaybackRate: Double?) async throws
    -> Bool
  {
    recordCall(
      methodName: "updateDefaultPlaybackRate",
      parameters: (podcastID: podcastID, defaultPlaybackRate: defaultPlaybackRate)
    )
    return try await repo.updateDefaultPlaybackRate(
      podcastID,
      defaultPlaybackRate: defaultPlaybackRate
    )
  }

  @discardableResult
  func updateQueueAllEpisodes(_ podcastID: Podcast.ID, queueAllEpisodes: QueueAllEpisodes)
    async throws -> Bool
  {
    recordCall(
      methodName: "updateQueueAllEpisodes",
      parameters: (podcastID: podcastID, queueAllEpisodes: queueAllEpisodes)
    )
    return try await repo.updateQueueAllEpisodes(podcastID, queueAllEpisodes: queueAllEpisodes)
  }

  @discardableResult
  func updateCacheAllEpisodes(_ podcastID: Podcast.ID, cacheAllEpisodes: CacheAllEpisodes)
    async throws -> Bool
  {
    recordCall(
      methodName: "updateCacheAllEpisodes",
      parameters: (podcastID: podcastID, cacheAllEpisodes: cacheAllEpisodes)
    )
    return try await repo.updateCacheAllEpisodes(podcastID, cacheAllEpisodes: cacheAllEpisodes)
  }

  @discardableResult
  func updateNotifyNewEpisodes(_ podcastID: Podcast.ID, notifyNewEpisodes: Bool)
    async throws -> Bool
  {
    recordCall(
      methodName: "updateNotifyNewEpisodes",
      parameters: (podcastID: podcastID, notifyNewEpisodes: notifyNewEpisodes)
    )
    return try await repo.updateNotifyNewEpisodes(podcastID, notifyNewEpisodes: notifyNewEpisodes)
  }
}
