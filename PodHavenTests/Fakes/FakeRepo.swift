// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import IdentifiedCollections
import Tagged

@testable import PodHaven

actor FakeRepo: Databasing, Sendable, FakeCallable {
  var callOrder: Int = 0
  var callsByType: [ObjectIdentifier: [any MethodCalling]] = [:]
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

  func latestEpisode(for feedURL: FeedURL) async throws -> Episode? {
    recordCall(methodName: "latestEpisode", parameters: feedURL)
    return try await repo.latestEpisode(for: feedURL)
  }

  func cachedEpisodes() async throws -> [Episode] {
    recordCall(methodName: "cachedEpisodes")
    return try await repo.cachedEpisodes()
  }

  // MARK: - Series Writers

  @discardableResult
  func insertSeries(_ unsavedPodcast: UnsavedPodcast, unsavedEpisodes: [UnsavedEpisode])
    async throws(RepoError) -> PodcastSeries
  {
    recordCall(
      methodName: "insertSeries",
      parameters: (unsavedPodcast: unsavedPodcast, unsavedEpisodes: unsavedEpisodes)
    )
    return try await repo.insertSeries(unsavedPodcast, unsavedEpisodes: unsavedEpisodes)
  }

  func updateSeriesFromFeed(
    podcastID: Podcast.ID,
    podcast: Podcast?,
    unsavedEpisodes: [UnsavedEpisode],
    existingEpisodes: [Episode]
  ) async throws(RepoError) {
    recordCall(
      methodName: "updateSeriesFromFeed",
      parameters: (
        podcastID: podcastID,
        podcast: podcast,
        unsavedEpisodes: unsavedEpisodes,
        existingEpisodes: existingEpisodes
      )
    )
    try await repo.updateSeriesFromFeed(
      podcastID: podcastID,
      podcast: podcast,
      unsavedEpisodes: unsavedEpisodes,
      existingEpisodes: existingEpisodes
    )
  }

  // MARK: - Podcast Writers

  @discardableResult
  func delete(_ podcastIDs: [Podcast.ID]) async throws -> Int {
    recordCall(methodName: "delete", parameters: podcastIDs)
    return try await repo.delete(podcastIDs)
  }

  @discardableResult
  func delete(_ podcastID: Podcast.ID) async throws -> Bool {
    recordCall(methodName: "delete", parameters: podcastID)
    return try await repo.delete(podcastID)
  }

  @discardableResult
  func delete(_ feedURLs: [FeedURL]) async throws -> Int {
    recordCall(methodName: "delete", parameters: feedURLs)
    return try await repo.delete(feedURLs)
  }

  @discardableResult
  func delete(_ feedURL: FeedURL) async throws -> Bool {
    recordCall(methodName: "delete", parameters: feedURL)
    return try await repo.delete(feedURL)
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

  @discardableResult
  func updateDuration(_ episodeID: Episode.ID, _ duration: CMTime) async throws -> Bool {
    recordCall(methodName: "updateDuration", parameters: (episodeID: episodeID, duration: duration))
    return try await repo.updateDuration(episodeID, duration)
  }

  @discardableResult
  func updateCurrentTime(_ episodeID: Episode.ID, _ currentTime: CMTime) async throws -> Bool {
    recordCall(
      methodName: "updateCurrentTime",
      parameters: (episodeID: episodeID, currentTime: currentTime)
    )
    return try await repo.updateCurrentTime(episodeID, currentTime)
  }

  @discardableResult
  func updateCachedFilename(_ episodeID: Episode.ID, _ cachedFilename: String?) async throws -> Bool
  {
    recordCall(
      methodName: "updateCachedFilename",
      parameters: (episodeID: episodeID, cachedFilename: cachedFilename)
    )
    return try await repo.updateCachedFilename(episodeID, cachedFilename)
  }

  @discardableResult
  func updateDownloadTaskID(_ episodeID: Episode.ID, _ downloadTaskID: URLSessionDownloadTask.ID?)
    async throws
    -> Bool
  {
    recordCall(
      methodName: "updateDownloadTaskID",
      parameters: (episodeID: episodeID, downloadTaskID: downloadTaskID)
    )
    return try await repo.updateDownloadTaskID(episodeID, downloadTaskID)
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
  func markSubscribed(_ feedURLs: [FeedURL]) async throws -> Int {
    recordCall(methodName: "markSubscribed", parameters: feedURLs)
    return try await repo.markSubscribed(feedURLs)
  }

  @discardableResult
  func markSubscribed(_ feedURL: FeedURL) async throws -> Bool {
    recordCall(methodName: "markSubscribed", parameters: feedURL)
    return try await repo.markSubscribed(feedURL)
  }

  @discardableResult
  func markUnsubscribed(_ feedURLs: [FeedURL]) async throws -> Int {
    recordCall(methodName: "markUnsubscribed", parameters: feedURLs)
    return try await repo.markUnsubscribed(feedURLs)
  }

  @discardableResult
  func markUnsubscribed(_ feedURL: FeedURL) async throws -> Bool {
    recordCall(methodName: "markUnsubscribed", parameters: feedURL)
    return try await repo.markUnsubscribed(feedURL)
  }

  @discardableResult
  func updateLastUpdate(_ podcastID: Podcast.ID) async throws -> Bool {
    recordCall(methodName: "updateLastUpdate", parameters: podcastID)
    return try await repo.updateLastUpdate(podcastID)
  }

  @discardableResult
  func updateCacheAll(_ podcastID: Podcast.ID, cacheAllEpisodes: Bool) async throws -> Bool {
    recordCall(
      methodName: "updateCacheAll",
      parameters: (podcastID: podcastID, cacheAllEpisodes: cacheAllEpisodes)
    )
    return try await repo.updateCacheAll(podcastID, cacheAllEpisodes: cacheAllEpisodes)
  }
}
