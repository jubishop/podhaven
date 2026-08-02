// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import Tagged

@testable import PodHaven

actor FakeRepo: Databasing, Sendable, FakeCallable {
  typealias AfterMarkFinished = @Sendable (Episode.ID) async -> Void

  let callOrder = ThreadSafe<Int>(0)
  let callsByType = ThreadSafe<[ObjectIdentifier: [any MethodCalling]]>([:])
  nonisolated let refreshEpisodeRowsRead = ThreadSafe<Int>(0)
  private var afterMarkFinishedHandler: AfterMarkFinished?

  // One-shot error to throw from `updateSaveInCache(_ episodeIDs:saveInCache:)`.
  // Cleared on use so subsequent calls reach the real repo.
  nonisolated let updateSaveInCacheBulkError = ThreadSafe<(any Error & Sendable)?>(nil)

  // One-shot error to throw from `episode(_:Episode.ID)`. Cleared on use so
  // subsequent calls reach the real repo.
  nonisolated let episodeFetchError = ThreadSafe<(any Error & Sendable)?>(nil)

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

  nonisolated let pendingPodcastEpisodeFetchSuspend = ThreadSafe<Bool>(false)
  nonisolated let suspendedPodcastEpisodeFetchCount = ThreadSafe<Int>(0)
  private var podcastEpisodeFetchSuspensions: [CheckedContinuation<Void, Never>] = []
  private var podcastEpisodeFetchBarrierRemaining = 0
  private var podcastEpisodeFetchBarrierContinuations: [CheckedContinuation<Void, Never>] = []
  nonisolated let pendingPodcastEpisodesFetchSuspend = ThreadSafe<Bool>(false)
  nonisolated let suspendedPodcastEpisodesFetchCount = ThreadSafe<Int>(0)
  private var podcastEpisodesFetchSuspensions: [CheckedContinuation<Void, Never>] = []
  nonisolated let pendingDownloadingFalseSuspend = ThreadSafe<Bool>(false)
  nonisolated let suspendedDownloadingFalseCount = ThreadSafe<Int>(0)
  private var downloadingFalseSuspensions: [CheckedContinuation<Void, Never>] = []
  nonisolated let pendingDownloadClaimSuspend = ThreadSafe<Bool>(false)
  nonisolated let suspendedDownloadClaimCount = ThreadSafe<Int>(0)
  private var downloadClaimSuspensions: [CheckedContinuation<Void, Never>] = []
  nonisolated let pendingPublisherReplacementSuspend = ThreadSafe<Bool>(false)
  nonisolated let suspendedPublisherReplacementCount = ThreadSafe<Int>(0)
  private var publisherReplacementSuspensions: [CheckedContinuation<Void, Never>] = []
  nonisolated let pendingPublisherReplacementAfterWriteSuspend = ThreadSafe<Bool>(false)
  nonisolated let suspendedPublisherReplacementAfterWriteCount = ThreadSafe<Int>(0)
  private var publisherReplacementAfterWriteSuspensions: [CheckedContinuation<Void, Never>] = []
  nonisolated let pendingPublisherTranscriptStoreAfterWriteSuspend = ThreadSafe<Bool>(false)
  nonisolated let suspendedPublisherTranscriptStoreAfterWriteCount = ThreadSafe<Int>(0)
  private var publisherTranscriptStoreAfterWriteSuspensions: [CheckedContinuation<Void, Never>] = []

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

  func allPodcasts(
    _ filter: SQLExpression,
    order: SQLOrdering,
    limit: Int
  ) async throws -> [Podcast] {
    recordCall(
      methodName: "allPodcasts",
      parameters: (filter: filter, order: order, limit: limit)
    )
    return try await repo.allPodcasts(filter, order: order, limit: limit)
  }

  // MARK: - Series Readers

  func podcast(_ podcastID: Podcast.ID) async throws -> Podcast? {
    recordCall(methodName: "podcast", parameters: podcastID)
    return try await repo.podcast(podcastID)
  }

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
    if let injected = episodeFetchError({ error in
      let captured = error
      error = nil
      return captured
    }) {
      throw injected
    }
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

  func transcriptionCheckpoint(_ episodeID: Episode.ID) async throws
    -> TranscriptionCheckpoint?
  {
    recordCall(methodName: "transcriptionCheckpoint", parameters: episodeID)
    return try await repo.transcriptionCheckpoint(episodeID)
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

  func resumeAllDownloadingFalseSuspensions() {
    let toResume = downloadingFalseSuspensions
    downloadingFalseSuspensions.removeAll()
    suspendedDownloadingFalseCount(0)
    for continuation in toResume { continuation.resume() }
  }

  nonisolated func waitForDownloadingFalseSuspended(count: Int = 1) async throws {
    try await Wait.until(
      { self.suspendedDownloadingFalseCount() >= count },
      {
        """
        Expected at least \(count) suspended downloading=false writes, \
        got \(self.suspendedDownloadingFalseCount())
        """
      }
    )
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

  func feedMergeEpisodes(
    podcastID: Podcast.ID,
    matching mediaGUIDs: [MediaGUID]
  ) async throws -> [FeedMergeEpisode] {
    recordCall(
      methodName: "feedMergeEpisodes",
      parameters: (podcastID: podcastID, mediaGUIDs: mediaGUIDs)
    )
    let episodes = try await repo.feedMergeEpisodes(
      podcastID: podcastID,
      matching: mediaGUIDs
    )
    refreshEpisodeRowsRead { $0 += episodes.count }
    return episodes
  }

  func podcastEpisode(_ episodeID: Episode.ID) async throws -> PodcastEpisode? {
    recordCall(methodName: "podcastEpisode", parameters: episodeID)
    let result = try await repo.podcastEpisode(episodeID)
    if pendingPodcastEpisodeFetchSuspend() {
      pendingPodcastEpisodeFetchSuspend(false)
      await withCheckedContinuation { continuation in
        podcastEpisodeFetchSuspensions.append(continuation)
        suspendedPodcastEpisodeFetchCount(podcastEpisodeFetchSuspensions.count)
      }
    }
    guard podcastEpisodeFetchBarrierRemaining > 0 else { return result }

    podcastEpisodeFetchBarrierRemaining -= 1
    if podcastEpisodeFetchBarrierRemaining == 0 {
      let continuations = podcastEpisodeFetchBarrierContinuations
      podcastEpisodeFetchBarrierContinuations.removeAll()
      for continuation in continuations { continuation.resume() }
    } else {
      await withCheckedContinuation { continuation in
        podcastEpisodeFetchBarrierContinuations.append(continuation)
      }
    }
    return result
  }

  func resumeAllPodcastEpisodeFetchSuspensions() {
    let toResume = podcastEpisodeFetchSuspensions
    podcastEpisodeFetchSuspensions.removeAll()
    suspendedPodcastEpisodeFetchCount(0)
    for continuation in toResume { continuation.resume() }
  }

  nonisolated func waitForPodcastEpisodeFetchSuspended(count: Int = 1) async throws {
    try await Wait.until(
      { self.suspendedPodcastEpisodeFetchCount() >= count },
      {
        """
        Expected at least \(count) suspended podcast episode fetches, \
        got \(self.suspendedPodcastEpisodeFetchCount())
        """
      }
    )
  }

  func barrierNextPodcastEpisodeFetches(count: Int) {
    Assert.precondition(count > 1, "Podcast episode fetch barrier requires multiple callers")
    Assert.precondition(
      podcastEpisodeFetchBarrierRemaining == 0,
      "Podcast episode fetch barrier is already active"
    )
    podcastEpisodeFetchBarrierRemaining = count
  }

  func podcastEpisodes(_ episodeIDs: [Episode.ID]) async throws -> [PodcastEpisode] {
    recordCall(methodName: "podcastEpisodes", parameters: episodeIDs)
    let result = try await repo.podcastEpisodes(episodeIDs)
    if pendingPodcastEpisodesFetchSuspend() {
      pendingPodcastEpisodesFetchSuspend(false)
      await withCheckedContinuation { continuation in
        podcastEpisodesFetchSuspensions.append(continuation)
        suspendedPodcastEpisodesFetchCount(podcastEpisodesFetchSuspensions.count)
      }
    }
    return result
  }

  func resumeAllPodcastEpisodesFetchSuspensions() {
    let toResume = podcastEpisodesFetchSuspensions
    podcastEpisodesFetchSuspensions.removeAll()
    suspendedPodcastEpisodesFetchCount(0)
    for continuation in toResume { continuation.resume() }
  }

  nonisolated func waitForPodcastEpisodesFetchSuspended(count: Int = 1) async throws {
    try await Wait.until(
      { self.suspendedPodcastEpisodesFetchCount() >= count },
      {
        """
        Expected at least \(count) suspended podcast episode fetches, \
        got \(self.suspendedPodcastEpisodesFetchCount())
        """
      }
    )
  }

  func podcastEpisode(
    _ mediaGUID: MediaGUID,
    feedURL: FeedURL
  ) async throws -> PodcastEpisode? {
    recordCall(methodName: "podcastEpisode", parameters: mediaGUID)
    return try await repo.podcastEpisode(mediaGUID, feedURL: feedURL)
  }

  func latestEpisode(for podcastID: Podcast.ID) async throws -> Episode? {
    recordCall(methodName: "latestEpisode", parameters: podcastID)
    return try await repo.latestEpisode(for: podcastID)
  }

  func cachedEpisodes() async throws -> [Episode] {
    recordCall(methodName: "cachedEpisodes")
    return try await repo.cachedEpisodes()
  }

  func downloadingEpisodeIDs() async throws -> [Episode.ID] {
    recordCall(methodName: "downloadingEpisodeIDs")
    return try await repo.downloadingEpisodeIDs()
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
    podcast: Podcast,
    updatedPodcast: Podcast?,
    unsavedEpisodes: [UnsavedEpisode],
    existingEpisodes: [FeedMergeEpisode]
  ) async throws -> [Episode] {
    recordCall(
      methodName: "updateSeriesFromFeed",
      parameters: (
        podcast: podcast,
        updatedPodcast: updatedPodcast,
        unsavedEpisodes: unsavedEpisodes,
        existingEpisodes: existingEpisodes
      )
    )
    return try await repo.updateSeriesFromFeed(
      podcast: podcast,
      updatedPodcast: updatedPodcast,
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
  func updateTag(_ tagID: Tag.ID, name: String, icon: LucideIcon) async throws -> Bool {
    recordCall(methodName: "updateTag", parameters: (tagID: tagID, name: name, icon: icon))
    return try await repo.updateTag(tagID, name: name, icon: icon)
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

  func claimForDownloadIfUncached(_ episodeID: Episode.ID) async throws -> Bool {
    recordCall(methodName: "claimForDownloadIfUncached", parameters: episodeID)
    let result = try await repo.claimForDownloadIfUncached(episodeID)
    if pendingDownloadClaimSuspend() {
      pendingDownloadClaimSuspend(false)
      await withCheckedContinuation { continuation in
        downloadClaimSuspensions.append(continuation)
        suspendedDownloadClaimCount(downloadClaimSuspensions.count)
      }
    }
    return result
  }

  func resumeAllDownloadClaimSuspensions() {
    let toResume = downloadClaimSuspensions
    downloadClaimSuspensions.removeAll()
    suspendedDownloadClaimCount(0)
    for continuation in toResume { continuation.resume() }
  }

  nonisolated func waitForDownloadClaimSuspended(count: Int = 1) async throws {
    try await Wait.until(
      { self.suspendedDownloadClaimCount() >= count },
      {
        """
        Expected at least \(count) suspended download claims, \
        got \(self.suspendedDownloadClaimCount())
        """
      }
    )
  }

  @discardableResult
  func updateDownloading(_ episodeID: Episode.ID, downloading: Bool) async throws -> Bool {
    recordCall(
      methodName: "updateDownloading",
      parameters: (episodeID: episodeID, downloading: downloading)
    )
    let result = try await repo.updateDownloading(episodeID, downloading: downloading)
    if !downloading, pendingDownloadingFalseSuspend() {
      pendingDownloadingFalseSuspend(false)
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        downloadingFalseSuspensions.append(continuation)
        suspendedDownloadingFalseCount(downloadingFalseSuspensions.count)
      }
    }
    return result
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
  func updateTranscript(_ episodeID: Episode.ID, transcript: String?) async throws -> Bool {
    recordCall(
      methodName: "updateTranscript",
      parameters: (episodeID: episodeID, transcript: transcript)
    )
    return try await repo.updateTranscript(episodeID, transcript: transcript)
  }

  func storeTranscriptIfAbsent(
    _ episodeID: Episode.ID,
    transcript: Transcript,
    publisherSource: PublisherTranscriptReference?
  ) async throws -> Bool {
    recordCall(
      methodName: "storeTranscriptIfAbsent",
      parameters: (
        episodeID: episodeID,
        transcript: transcript,
        publisherSource: publisherSource
      )
    )
    let stored = try await repo.storeTranscriptIfAbsent(
      episodeID,
      transcript: transcript,
      publisherSource: publisherSource
    )
    if publisherSource != nil {
      await suspendPublisherTranscriptStoreAfterWriteIfNeeded(stored)
    }
    return stored
  }

  private func suspendPublisherTranscriptStoreAfterWriteIfNeeded(_ stored: Bool) async {
    guard stored, pendingPublisherTranscriptStoreAfterWriteSuspend() else { return }
    pendingPublisherTranscriptStoreAfterWriteSuspend(false)
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      publisherTranscriptStoreAfterWriteSuspensions.append(continuation)
      suspendedPublisherTranscriptStoreAfterWriteCount(
        publisherTranscriptStoreAfterWriteSuspensions.count
      )
    }
  }

  func resumeAllPublisherTranscriptStoreAfterWriteSuspensions() {
    let toResume = publisherTranscriptStoreAfterWriteSuspensions
    publisherTranscriptStoreAfterWriteSuspensions.removeAll()
    suspendedPublisherTranscriptStoreAfterWriteCount(0)
    for continuation in toResume { continuation.resume() }
  }

  nonisolated func waitForPublisherTranscriptStoreAfterWriteSuspended() async throws {
    try await Wait.until(
      { self.suspendedPublisherTranscriptStoreAfterWriteCount() > 0 },
      { "Expected publisher transcript storage to suspend after writing" }
    )
  }

  func replacePublisherTranscript(
    _ episodeID: Episode.ID,
    with transcript: Transcript
  ) async throws -> PublisherTranscriptReplacementResult {
    recordCall(
      methodName: "replacePublisherTranscript",
      parameters: (episodeID: episodeID, transcript: transcript)
    )
    if pendingPublisherReplacementSuspend() {
      pendingPublisherReplacementSuspend(false)
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        publisherReplacementSuspensions.append(continuation)
        suspendedPublisherReplacementCount(publisherReplacementSuspensions.count)
      }
    }
    let result = try await repo.replacePublisherTranscript(
      episodeID,
      with: transcript
    )
    if case .replaced = result,
      pendingPublisherReplacementAfterWriteSuspend()
    {
      pendingPublisherReplacementAfterWriteSuspend(false)
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        publisherReplacementAfterWriteSuspensions.append(continuation)
        suspendedPublisherReplacementAfterWriteCount(
          publisherReplacementAfterWriteSuspensions.count
        )
      }
    }
    return result
  }

  func resumeAllPublisherReplacementSuspensions() {
    let toResume = publisherReplacementSuspensions
    publisherReplacementSuspensions.removeAll()
    suspendedPublisherReplacementCount(0)
    for continuation in toResume { continuation.resume() }
  }

  nonisolated func waitForPublisherReplacementSuspended() async throws {
    try await Wait.until(
      { self.suspendedPublisherReplacementCount() > 0 },
      { "Expected final publisher replacement storage to suspend" }
    )
  }

  func resumeAllPublisherReplacementAfterWriteSuspensions() {
    let toResume = publisherReplacementAfterWriteSuspensions
    publisherReplacementAfterWriteSuspensions.removeAll()
    suspendedPublisherReplacementAfterWriteCount(0)
    for continuation in toResume { continuation.resume() }
  }

  nonisolated func waitForPublisherReplacementAfterWriteSuspended() async throws {
    try await Wait.until(
      { self.suspendedPublisherReplacementAfterWriteCount() > 0 },
      { "Expected final publisher replacement storage to suspend after writing" }
    )
  }

  func storePublisherTranscriptIfReferencesCurrent(
    _ episodeID: Episode.ID,
    imported: PublisherTranscriptImport,
    expectedReferences: [PublisherTranscriptReference]
  ) async throws -> Bool {
    recordCall(
      methodName: "storePublisherTranscriptIfReferencesCurrent",
      parameters: (
        episodeID: episodeID,
        imported: imported,
        expectedReferences: expectedReferences
      )
    )
    let stored = try await repo.storePublisherTranscriptIfReferencesCurrent(
      episodeID,
      imported: imported,
      expectedReferences: expectedReferences
    )
    await suspendPublisherTranscriptStoreAfterWriteIfNeeded(stored)
    return stored
  }

  func storePublisherTranscriptIfDemandCurrent(
    _ episodeID: Episode.ID,
    imported: PublisherTranscriptImport,
    expectedReferences: [PublisherTranscriptReference]
  ) async throws -> Bool {
    recordCall(
      methodName: "storePublisherTranscriptIfDemandCurrent",
      parameters: (
        episodeID: episodeID,
        imported: imported,
        expectedReferences: expectedReferences
      )
    )
    let stored = try await repo.storePublisherTranscriptIfDemandCurrent(
      episodeID,
      imported: imported,
      expectedReferences: expectedReferences
    )
    await suspendPublisherTranscriptStoreAfterWriteIfNeeded(stored)
    return stored
  }

  func saveTranscriptionCheckpoint(
    _ checkpoint: TranscriptionCheckpoint,
    for episodeID: Episode.ID
  ) async throws {
    recordCall(
      methodName: "saveTranscriptionCheckpoint",
      parameters: (checkpoint: checkpoint, episodeID: episodeID)
    )
    try await repo.saveTranscriptionCheckpoint(checkpoint, for: episodeID)
  }

  func deleteTranscriptionCheckpoint(for episodeID: Episode.ID) async throws {
    recordCall(methodName: "deleteTranscriptionCheckpoint", parameters: episodeID)
    try await repo.deleteTranscriptionCheckpoint(for: episodeID)
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
    let marked = try await markFinished([episodeID]) > 0
    let afterMarkFinished = afterMarkFinishedHandler
    afterMarkFinishedHandler = nil
    if let afterMarkFinished {
      await afterMarkFinished(episodeID)
    }
    return marked
  }

  func afterNextMarkFinished(_ handler: @escaping AfterMarkFinished) {
    afterMarkFinishedHandler = handler
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
