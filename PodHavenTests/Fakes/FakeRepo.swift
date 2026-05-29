// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import Tagged

@testable import PodHaven

actor FakeRepo: Databasing, Sendable, FakeCallable {
  let callOrder = ThreadSafe<Int>(0)
  let callsByType = ThreadSafe<[ObjectIdentifier: [any MethodCalling]]>([:])

  // One-shot error to throw from `updateSaveInCache(_ episodeIDs:saveInCache:)`.
  // Cleared on use so subsequent calls reach the real repo.
  nonisolated let updateSaveInCacheBulkError = ThreadSafe<(any Error & Sendable)?>(nil)

  // When true, the next `episode(_:Episode.ID)` call parks until
  // `resumeAllEpisodeFetchSuspensions()` fires; cleared on use. Counts are
  // nonisolated so tests poll without contending for the actor (same pattern
  // as FakeSleeper). `completedEpisodeFetchCount` increments only after a
  // parked call has resumed and unwound, giving tests an event-driven
  // barrier instead of a timed poll.
  nonisolated let pendingEpisodeFetchSuspend = ThreadSafe<Bool>(false)
  nonisolated let suspendedEpisodeFetchCount = ThreadSafe<Int>(0)
  nonisolated let completedEpisodeFetchCount = ThreadSafe<Int>(0)
  private var episodeFetchSuspensions: [CheckedContinuation<Void, Never>] = []

  // Same shape as pendingEpisodeFetchSuspend, but for updateLastUpdates so
  // tests can park the batched flush inside RefreshManager.performRefresh.
  nonisolated let pendingUpdateLastUpdatesSuspend = ThreadSafe<Bool>(false)
  nonisolated let suspendedUpdateLastUpdatesCount = ThreadSafe<Int>(0)
  private var updateLastUpdatesSuspensions: [CheckedContinuation<Void, Never>] = []

  private let repo: Repo

  init(_ repo: Repo) {
    self.repo = repo
  }

  // MARK: - Databasing

  nonisolated var db: AppDB.Reader { repo.db }

  // MARK: - Global Readers

  func allPodcasts(_ filter: SQLExpression) async throws -> [Podcast] {
    try await repo.allPodcasts(filter)
  }

  func allPodcastSeries(
    _ filter: SQLExpression,
    order: SQLOrdering = Podcast.Columns.id.desc,
    limit: Int = Int.max
  ) async throws
    -> [PodcastSeries]
  {
    recordCall(
      methodName: "allPodcastSeries",
      parameters: (filter: filter, order: order, limit: limit)
    )
    return try await repo.allPodcastSeries(filter, order: order, limit: limit)
  }

  // MARK: - Series Readers

  func podcastSeries(_ podcastID: Podcast.ID) async throws -> PodcastSeries? {
    recordCall(methodName: "podcastSeries", parameters: podcastID)
    return try await repo.podcastSeries(podcastID)
  }

  func podcastSeries(_ feedURL: FeedURL, iTunesID: ITunesPodcastID?) async throws
    -> PodcastSeries?
  {
    recordCall(
      methodName: "podcastSeries",
      parameters: (feedURL: feedURL, iTunesID: iTunesID)
    )
    return try await repo.podcastSeries(feedURL, iTunesID: iTunesID)
  }

  func podcastSeriesDetail(_ podcastID: Podcast.ID) async throws -> PodcastSeriesDetail? {
    recordCall(methodName: "podcastSeriesDetail", parameters: podcastID)
    return try await repo.podcastSeriesDetail(podcastID)
  }

  func podcastSeriesDetail(_ feedURL: FeedURL, iTunesID: ITunesPodcastID?) async throws
    -> PodcastSeriesDetail?
  {
    recordCall(
      methodName: "podcastSeriesDetail",
      parameters: (feedURL: feedURL, iTunesID: iTunesID)
    )
    return try await repo.podcastSeriesDetail(feedURL, iTunesID: iTunesID)
  }

  // MARK: - Episode Readers

  func episode(_ episodeID: Episode.ID) async throws -> Episode? {
    recordCall(methodName: "episode", parameters: episodeID)
    let result = try await repo.episode(episodeID)
    if pendingEpisodeFetchSuspend() {
      pendingEpisodeFetchSuspend(false)
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        episodeFetchSuspensions.append(continuation)
        suspendedEpisodeFetchCount(episodeFetchSuspensions.count)
      }
    }
    completedEpisodeFetchCount { $0 += 1 }
    return result
  }

  func resumeAllEpisodeFetchSuspensions() {
    let toResume = episodeFetchSuspensions
    episodeFetchSuspensions.removeAll()
    suspendedEpisodeFetchCount(0)
    for continuation in toResume { continuation.resume() }
  }

  nonisolated func waitForEpisodeFetchSuspended(count: Int) async throws {
    try await Wait.until(
      { self.suspendedEpisodeFetchCount() >= count },
      {
        """
        Expected at least \(count) suspended episode fetches, \
        got \(self.suspendedEpisodeFetchCount())
        """
      }
    )
  }

  nonisolated func waitForEpisodeFetchCompleted(count: Int) async throws {
    try await Wait.until(
      { self.completedEpisodeFetchCount() >= count },
      {
        """
        Expected at least \(count) completed episode fetches, \
        got \(self.completedEpisodeFetchCount())
        """
      }
    )
  }

  func episode(_ mediaGUID: MediaGUID) async throws -> Episode? {
    recordCall(methodName: "episode", parameters: mediaGUID)
    return try await repo.episode(mediaGUID)
  }

  func episodesMatching(
    podcastID: Podcast.ID,
    guids: [GUID],
    mediaURLs: [MediaURL]
  ) async throws -> [Episode] {
    recordCall(
      methodName: "episodesMatching",
      parameters: (podcastID: podcastID, guids: guids, mediaURLs: mediaURLs)
    )
    return try await repo.episodesMatching(podcastID: podcastID, guids: guids, mediaURLs: mediaURLs)
  }

  func podcastEpisode(_ episodeID: Episode.ID) async throws -> PodcastEpisode? {
    recordCall(methodName: "podcastEpisode", parameters: episodeID)
    return try await repo.podcastEpisode(episodeID)
  }

  func podcastEpisodes(_ episodeIDs: [Episode.ID]) async throws -> [PodcastEpisode] {
    recordCall(methodName: "podcastEpisodes", parameters: episodeIDs)
    return try await repo.podcastEpisodes(episodeIDs)
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
  func insertSeries(_ unsavedPodcastSeries: UnsavedPodcastSeries) async throws
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
  ) async throws -> [Episode] {
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

  @discardableResult
  func insertTag(_ unsavedTag: UnsavedTag) async throws -> Tag {
    recordCall(methodName: "insertTag", parameters: unsavedTag)
    return try await repo.insertTag(unsavedTag)
  }

  @discardableResult
  func renameTag(_ tagID: Tag.ID, newName: String) async throws -> Bool {
    recordCall(methodName: "renameTag", parameters: (tagID: tagID, newName: newName))
    return try await repo.renameTag(tagID, newName: newName)
  }

  @discardableResult
  func deleteTag(_ tagID: Tag.ID) async throws -> Bool {
    recordCall(methodName: "deleteTag", parameters: tagID)
    return try await repo.deleteTag(tagID)
  }

  func addTag(_ tagID: Tag.ID, to podcastID: Podcast.ID) async throws {
    recordCall(methodName: "addTag", parameters: (tagID: tagID, podcastID: podcastID))
    try await repo.addTag(tagID, to: podcastID)
  }

  @discardableResult
  func removeTag(_ tagID: Tag.ID, from podcastID: Podcast.ID) async throws -> Bool {
    recordCall(methodName: "removeTag", parameters: (tagID: tagID, podcastID: podcastID))
    return try await repo.removeTag(tagID, from: podcastID)
  }

  func addTag(_ tagID: Tag.ID, toPodcasts podcastIDs: [Podcast.ID]) async throws {
    recordCall(
      methodName: "addTag",
      parameters: (tagID: tagID, podcastIDs: podcastIDs)
    )
    try await repo.addTag(tagID, toPodcasts: podcastIDs)
  }

  @discardableResult
  func removeTag(_ tagID: Tag.ID, fromPodcasts podcastIDs: [Podcast.ID]) async throws -> Int {
    recordCall(
      methodName: "removeTag",
      parameters: (tagID: tagID, podcastIDs: podcastIDs)
    )
    return try await repo.removeTag(tagID, fromPodcasts: podcastIDs)
  }

  func addTag(_ tagID: Tag.ID, to episodeID: Episode.ID) async throws {
    recordCall(methodName: "addTag", parameters: (tagID: tagID, episodeID: episodeID))
    try await repo.addTag(tagID, to: episodeID)
  }

  @discardableResult
  func removeTag(_ tagID: Tag.ID, from episodeID: Episode.ID) async throws -> Bool {
    recordCall(
      methodName: "removeTag",
      parameters: (tagID: tagID, episodeID: episodeID)
    )
    return try await repo.removeTag(tagID, from: episodeID)
  }

  func addTag(_ tagID: Tag.ID, toEpisodes episodeIDs: [Episode.ID]) async throws {
    recordCall(
      methodName: "addTag",
      parameters: (tagID: tagID, episodeIDs: episodeIDs)
    )
    try await repo.addTag(tagID, toEpisodes: episodeIDs)
  }

  @discardableResult
  func removeTag(_ tagID: Tag.ID, fromEpisodes episodeIDs: [Episode.ID]) async throws -> Int {
    recordCall(
      methodName: "removeTag",
      parameters: (tagID: tagID, episodeIDs: episodeIDs)
    )
    return try await repo.removeTag(tagID, fromEpisodes: episodeIDs)
  }

  // MARK: - Episode Writers

  @discardableResult
  func upsertPodcastEpisodes(_ unsavedPodcastEpisodes: [UnsavedPodcastEpisode])
    async throws -> [PodcastEpisode]
  {
    recordCall(methodName: "upsertPodcastEpisodes", parameters: unsavedPodcastEpisodes)
    return try await repo.upsertPodcastEpisodes(unsavedPodcastEpisodes)
  }

  @discardableResult
  func upsertPodcastEpisode(_ unsavedPodcastEpisode: UnsavedPodcastEpisode) async throws
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
  func updatePlayback(
    _ episodeID: Episode.ID,
    currentTime: CMTime,
    playedFrom: CMTime,
    now: Date
  ) async throws -> Bool {
    recordCall(
      methodName: "updatePlayback",
      parameters: (
        episodeID: episodeID, currentTime: currentTime, playedFrom: playedFrom, now: now
      )
    )
    return try await repo.updatePlayback(
      episodeID,
      currentTime: currentTime,
      playedFrom: playedFrom,
      now: now
    )
  }

  @discardableResult
  func updateDownloading(_ episodeID: Episode.ID, downloading: Bool) async throws -> Bool {
    recordCall(
      methodName: "updateDownloading",
      parameters: (episodeID: episodeID, downloading: downloading)
    )
    return try await repo.updateDownloading(episodeID, downloading: downloading)
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
  func updateSaveInCache(_ episodeIDs: [Episode.ID], saveInCache: Bool) async throws -> Int {
    recordCall(
      methodName: "updateSaveInCache",
      parameters: (episodeIDs: episodeIDs, saveInCache: saveInCache)
    )
    if let injected = updateSaveInCacheBulkError({ error in
      let captured = error
      error = nil
      return captured
    }) {
      throw injected
    }
    return try await repo.updateSaveInCache(episodeIDs, saveInCache: saveInCache)
  }

  func podcast(_ podcastID: Podcast.ID) async throws -> Podcast? {
    recordCall(methodName: "podcast", parameters: podcastID)
    return try await repo.podcast(podcastID)
  }

  @discardableResult
  func updateRating(_ episodeIDs: [Episode.ID], rating: EpisodeRating?) async throws -> Int {
    recordCall(
      methodName: "updateRating",
      parameters: (episodeIDs: episodeIDs, rating: rating)
    )
    return try await repo.updateRating(episodeIDs, rating: rating)
  }

  @discardableResult
  func updateRating(_ episodeID: Episode.ID, rating: EpisodeRating?) async throws -> Bool {
    recordCall(
      methodName: "updateRating",
      parameters: (episodeID: episodeID, rating: rating)
    )
    return try await updateRating([episodeID], rating: rating) > 0
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
  func updateITunesID(_ podcastID: Podcast.ID, iTunesID: ITunesPodcastID) async throws -> Bool {
    recordCall(
      methodName: "updateITunesID",
      parameters: (podcastID: podcastID, iTunesID: iTunesID)
    )
    return try await repo.updateITunesID(podcastID, iTunesID: iTunesID)
  }

  func updateLastUpdates(_ pairs: [(Podcast.ID, Date)]) async throws {
    recordCall(methodName: "updateLastUpdates", parameters: pairs)
    if pendingUpdateLastUpdatesSuspend() {
      pendingUpdateLastUpdatesSuspend(false)
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        updateLastUpdatesSuspensions.append(continuation)
        suspendedUpdateLastUpdatesCount(updateLastUpdatesSuspensions.count)
      }
    }
    try await repo.updateLastUpdates(pairs)
  }

  func resumeAllUpdateLastUpdatesSuspensions() {
    let toResume = updateLastUpdatesSuspensions
    updateLastUpdatesSuspensions.removeAll()
    suspendedUpdateLastUpdatesCount(0)
    for continuation in toResume { continuation.resume() }
  }

  nonisolated func waitForUpdateLastUpdatesSuspended(count: Int) async throws {
    try await Wait.until(
      { self.suspendedUpdateLastUpdatesCount() >= count },
      {
        """
        Expected at least \(count) suspended updateLastUpdates, \
        got \(self.suspendedUpdateLastUpdatesCount())
        """
      }
    )
  }

  @discardableResult
  func updatePodcastSettings(_ podcastID: Podcast.ID, _ settings: PodcastSettings) async throws
    -> Bool
  {
    recordCall(
      methodName: "updatePodcastSettings",
      parameters: (podcastID: podcastID, settings: settings)
    )
    return try await repo.updatePodcastSettings(podcastID, settings)
  }
}
