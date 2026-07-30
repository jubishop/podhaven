// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Semaphore
import Testing

@testable import PodHaven

@Suite("of CacheManager finalization tests", .container)
@MainActor class CacheManagerFinalizationTests {
  @DynamicInjected(\.cacheBackgroundDelegate) private var cacheBackgroundDelegate
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.stateManager) private var stateManager

  private var fileManager: FakeFileManager {
    Container.shared.fileManager() as! FakeFileManager
  }
  private var session: FakeDataFetchable {
    Container.shared.cacheManagerSession() as! FakeDataFetchable
  }
  private var sharedState: SharedState {
    Container.shared.sharedState()
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
  }

  @Test("cache filenames fall back to mp3 and preserves extension")
  func cacheFilenameFallbackAndPreserve() async throws {
    let noExt = try await Create.podcastEpisode(
      Create.unsavedEpisode(mediaURL: MediaURL(URL(string: "https://a.b/c/d")!))
    )
    let withExt = try await Create.podcastEpisode(
      Create.unsavedEpisode(mediaURL: MediaURL(URL(string: "https://a.b/c/d.wav")!))
    )
    let noExtTaskID = try await cacheManager.downloadToCache(for: noExt.id)!
    let withExtTaskID = try await cacheManager.downloadToCache(for: withExt.id)!

    try await CacheHelpers.simulateBackgroundFinish(noExtTaskID)
    try await CacheHelpers.simulateBackgroundFinish(withExtTaskID)

    let noExtURL = try await CacheHelpers.waitForCached(noExt.id)
    let withExtURL = try await CacheHelpers.waitForCached(withExt.id)

    #expect(noExtURL.pathExtension == "mp3")
    #expect(withExtURL.pathExtension == "wav")
  }

  @Test("extensionless download uses mp3 staging suffix for validation")
  func extensionlessDownloadUsesMP3StagingSuffix() async throws {
    let mediaURL = MediaURL(try #require(URL(string: "https://example.com/download")))
    let podcastEpisode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(mediaURL: mediaURL)
    )
    try await repo.updateDownloading(podcastEpisode.id, downloading: true)
    await episodeAssetLoader.setDefaultHandler { url in
      guard url.pathExtension == "mp3" else { throw TestError.simulatedFailure }
      return (true, CMTime.seconds(30))
    }

    let urlSession = URLSession(configuration: .ephemeral)
    defer { urlSession.invalidateAndCancel() }
    let downloadTask = urlSession.downloadTask(with: mediaURL.rawValue)
    downloadTask.taskDescription = String(podcastEpisode.id.rawValue)
    let temporaryURL = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try await fileManager.writeData(Data.random(), to: temporaryURL)

    let downloadDelegate: any URLSessionDownloadDelegate = cacheBackgroundDelegate
    downloadDelegate.urlSession(
      urlSession,
      downloadTask: downloadTask,
      didFinishDownloadingTo: temporaryURL
    )

    let cachedURL = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForFileRemoved(temporaryURL)
    #expect(cachedURL.pathExtension == "mp3")
  }

  @Test("download finalization reuses a cache file owned by another episode")
  func downloadFinalizationReusesSharedCacheFile() async throws {
    let mediaURL = MediaURL(try #require(URL(string: "https://example.com/shared-download.mp3")))
    let (first, second) = try await Create.twoPodcastEpisodes(
      try Create.unsavedEpisode(mediaURL: mediaURL),
      try Create.unsavedEpisode(mediaURL: mediaURL)
    )
    let firstTaskID = try await CacheHelpers.downloadToCache(first.id)
    let originalData = Data("original shared download".utf8)
    let firstTempFile = try await CacheHelpers.simulateBackgroundFinish(
      firstTaskID,
      data: originalData
    )
    let sharedURL = try await CacheHelpers.waitForCached(first.id)
    try await CacheHelpers.waitForFileRemoved(firstTempFile)

    let secondTaskID = try await CacheHelpers.downloadToCache(second.id)
    let secondTempFile = try await CacheHelpers.simulateBackgroundFinish(
      secondTaskID,
      data: Data("replacement download".utf8)
    )
    try await CacheHelpers.waitForFileRemoved(secondTempFile)

    #expect(try await repo.episode(first.id)?.cachedURL == sharedURL)
    #expect(try await repo.episode(second.id)?.cachedURL == sharedURL)
    #expect(try await fileManager.readData(from: sharedURL.rawValue) == originalData)
  }

  @Test("failed stale finalization preserves a shared file and replacement claim")
  func failedStaleFinalizationPreservesSharedFileAndReplacementClaim() async throws {
    enum ValidationFailure: Error, Sendable { case failed }

    let mediaURL = MediaURL(
      try #require(URL(string: "https://example.com/shared-validation-failure.mp3"))
    )
    let (owner, target) = try await Create.twoPodcastEpisodes(
      try Create.unsavedEpisode(mediaURL: mediaURL),
      try Create.unsavedEpisode(mediaURL: mediaURL)
    )
    let ownerTaskID = try await CacheHelpers.downloadToCache(owner.id)
    let originalData = Data("valid shared download".utf8)
    let ownerTempFile = try await CacheHelpers.simulateBackgroundFinish(
      ownerTaskID,
      data: originalData
    )
    let sharedURL = try await CacheHelpers.waitForCached(owner.id)
    try await CacheHelpers.waitForFileRemoved(ownerTempFile)

    let validationStarted = AsyncSemaphore(value: 0)
    let validationRelease = AsyncSemaphore(value: 0)
    await episodeAssetLoader.setDefaultHandler { _ in
      validationStarted.signal()
      try await validationRelease.waitUnlessCancelled()
      throw ValidationFailure.failed
    }

    let staleTaskID = try await CacheHelpers.downloadToCache(target.id)
    let staleFinalization = Task {
      try await CacheHelpers.simulateBackgroundFinish(
        staleTaskID,
        data: Data("invalid replacement".utf8)
      )
    }
    await validationStarted.wait()

    #expect(try await cacheManager.clearCache(for: target.id) == nil)
    let replacementTaskID = try #require(try await cacheManager.downloadToCache(for: target.id))
    try await CacheHelpers.waitForResumed(replacementTaskID)

    validationRelease.signal()
    let staleTempFile = try await staleFinalization.value
    try await CacheHelpers.waitForFileRemoved(staleTempFile)

    let claimedReplacement = try #require(try await repo.episode(target.id))
    try #require(claimedReplacement.downloading)
    #expect(try await repo.episode(owner.id)?.cachedURL == sharedURL)
    #expect(try await fileManager.readData(from: sharedURL.rawValue) == originalData)

    await episodeAssetLoader.setDefaultHandler { _ in
      (true, CMTime.seconds(30))
    }
    let replacementTempFile = try await CacheHelpers.simulateBackgroundFinish(
      replacementTaskID,
      data: Data("usable replacement".utf8)
    )
    try await CacheHelpers.waitForFileRemoved(replacementTempFile)

    #expect(try await repo.episode(owner.id)?.cachedURL == sharedURL)
    #expect(try await repo.episode(target.id)?.cachedURL == sharedURL)
    #expect(try await fileManager.readData(from: sharedURL.rawValue) == originalData)
  }

  @Test("successful stale finalization cannot publish over a replacement")
  func successfulStaleFinalizationCannotPublishOverReplacement() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let validationStarted = AsyncSemaphore(value: 0)
    let validationRelease = AsyncSemaphore(value: 0)
    await episodeAssetLoader.setDefaultHandler { _ in
      validationStarted.signal()
      try await validationRelease.waitUnlessCancelled()
      return (true, CMTime.seconds(30))
    }

    let staleTaskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)
    let staleFinalization = Task {
      try await CacheHelpers.simulateBackgroundFinish(
        staleTaskID,
        data: Data("stale download".utf8)
      )
    }
    await validationStarted.wait()

    #expect(try await cacheManager.clearCache(for: podcastEpisode.id) == nil)
    let replacementTaskID = try #require(
      try await cacheManager.downloadToCache(for: podcastEpisode.id)
    )
    try await CacheHelpers.waitForResumed(replacementTaskID)

    validationRelease.signal()
    let staleTempFile = try await staleFinalization.value
    try await CacheHelpers.waitForFileRemoved(staleTempFile)

    let claimedReplacement = try #require(try await repo.episode(podcastEpisode.id))
    #expect(claimedReplacement.downloading)
    #expect(claimedReplacement.cachedURL == nil)

    await episodeAssetLoader.setDefaultHandler { _ in
      (true, CMTime.seconds(30))
    }
    let replacementData = Data("replacement download".utf8)
    let replacementTempFile = try await CacheHelpers.simulateBackgroundFinish(
      replacementTaskID,
      data: replacementData
    )
    try await CacheHelpers.waitForFileRemoved(replacementTempFile)

    let cachedURL = try await CacheHelpers.waitForCached(podcastEpisode.id)
    #expect(try await fileManager.readData(from: cachedURL.rawValue) == replacementData)
  }

  @Test("replacement download resets progress published after cancellation")
  func replacementDownloadResetsProgressPublishedAfterCancellation() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let episodeID = podcastEpisode.id
    let cancelledTaskID = try await CacheHelpers.downloadToCache(episodeID)
    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.pendingEpisodeFetchSuspend(true)

    let delayedProgress = Task {
      await session.progressDownload(
        taskID: cancelledTaskID,
        totalBytesWritten: 90,
        totalBytesExpectedToWrite: 100
      )
    }
    try await fakeRepo.waitForEpisodeFetchSuspended(count: 1)
    defer { Task { await fakeRepo.resumeAllEpisodeFetchSuspensions() } }

    #expect(try await cacheManager.clearCache(for: episodeID) == nil)
    await fakeRepo.resumeAllEpisodeFetchSuspensions()
    await delayedProgress.value
    #expect(sharedState.downloadProgress[episodeID] == 0.9)

    let replacementTaskID = try #require(try await cacheManager.downloadToCache(for: episodeID))
    try await CacheHelpers.waitForResumed(replacementTaskID)

    #expect(sharedState.downloadProgress[episodeID] == nil)

    try await CacheHelpers.simulateBackgroundFailure(cancelledTaskID)
    try await CacheHelpers.simulateBackgroundFailure(replacementTaskID)
  }

  @Test("clear removes a cache published after its initial episode read")
  func clearRemovesCachePublishedAfterInitialEpisodeRead() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)
    let fakeRepo = try #require(repo as? FakeRepo)

    fakeRepo.pendingEpisodeFetchSuspend(true)
    let clear = Task {
      try await cacheManager.clearCache(for: podcastEpisode.id)
    }
    try await fakeRepo.waitForEpisodeFetchSuspended(count: 1)
    defer { Task { await fakeRepo.resumeAllEpisodeFetchSuspensions() } }

    let tempFile = try await CacheHelpers.simulateBackgroundFinish(taskID)
    try await CacheHelpers.waitForFileRemoved(tempFile)
    let cachedURL = try await CacheHelpers.waitForCached(podcastEpisode.id)

    await fakeRepo.resumeAllEpisodeFetchSuspensions()
    let disposition = try #require(try await clear.value)

    #expect(disposition == .removed(cachedURL))
    try await CacheHelpers.waitForNotCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFileRemoved(cachedURL)
  }

  @Test("superseded finalization preserves a replacement download claim")
  func supersededFinalizationPreservesReplacementDownloadClaim() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let task = FakeURLSessionDownloadTask(
      taskDescription: String(podcastEpisode.id.rawValue),
      originalRequest: URLRequest(url: podcastEpisode.episode.mediaURL.rawValue)
    )
    let tempFile = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try await fileManager.writeData(Data.random(), to: tempFile)
    let replacementClaimed = ThreadSafe(false)
    fileManager.runBeforeRemovingItem(at: tempFile) {
      let claimed = try Container.shared.appDB().unsafeTestDB
        .write { db in
          try Episode
            .withID(podcastEpisode.id)
            .filter(Episode.Columns.cachedFilename == nil)
            .filter(Episode.Columns.downloading == false)
            .updateAll(db, Episode.Columns.downloading.set(to: true))
        }
      replacementClaimed(claimed > 0)
    }

    await cacheBackgroundDelegate.urlSession(
      session,
      downloadTask: task,
      didFinishDownloadingTo: tempFile
    )

    #expect(replacementClaimed())
    #expect(try await repo.episode(podcastEpisode.id)?.downloading == true)
  }

  // MARK: - Progress Tracking

  @Test("progress updates cache state and clears on finish")
  func progressUpdatesCacheStateAndClearsOnFinish() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    await session.progressDownload(
      taskID: taskID,
      totalBytesWritten: 50,
      totalBytesExpectedToWrite: 100
    )
    try await CacheHelpers.waitForProgress(podcastEpisode.id, progress: 0.5)

    try await CacheHelpers.simulateBackgroundFinish(taskID)
    try await CacheHelpers.waitForProgress(podcastEpisode.id, progress: nil)
  }

  @Test("progress clears on completion error")
  func progressClearsOnCompletionError() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)

    await session.progressDownload(
      taskID: taskID,
      totalBytesWritten: 50,
      totalBytesExpectedToWrite: 100
    )
    try await CacheHelpers.waitForProgress(podcastEpisode.id, progress: 0.5)

    try await CacheHelpers.simulateBackgroundFailure(taskID)
    try await CacheHelpers.waitForProgress(podcastEpisode.id, progress: nil)
  }

  @Test("progress delayed past terminal completion stays cleared")
  func progressDelayedPastTerminalCompletionStaysCleared() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)
    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.pendingEpisodeFetchSuspend(true)

    let delayedProgress = Task {
      await session.progressDownload(
        taskID: taskID,
        totalBytesWritten: 90,
        totalBytesExpectedToWrite: 100
      )
    }
    try await fakeRepo.waitForEpisodeFetchSuspended(count: 1)
    defer { Task { await fakeRepo.resumeAllEpisodeFetchSuspensions() } }

    try await CacheHelpers.simulateBackgroundFailure(taskID)
    #expect(sharedState.downloadProgress[podcastEpisode.id] == nil)

    await fakeRepo.resumeAllEpisodeFetchSuspensions()
    await delayedProgress.value

    #expect(sharedState.downloadProgress[podcastEpisode.id] == nil)
  }

  @Test("stale progress cannot overwrite replacement progress")
  func staleProgressCannotOverwriteReplacementProgress() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let firstTaskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)
    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.pendingEpisodeFetchSuspend(true)

    let staleProgress = Task {
      await session.progressDownload(
        taskID: firstTaskID,
        totalBytesWritten: 90,
        totalBytesExpectedToWrite: 100
      )
    }
    try await fakeRepo.waitForEpisodeFetchSuspended(count: 1)

    #expect(try await cacheManager.clearCache(for: podcastEpisode.id) == nil)
    let replacementTaskID = try #require(
      try await cacheManager.downloadToCache(for: podcastEpisode.id)
    )
    try await CacheHelpers.waitForResumed(replacementTaskID)
    await session.progressDownload(
      taskID: replacementTaskID,
      totalBytesWritten: 10,
      totalBytesExpectedToWrite: 100
    )
    try await CacheHelpers.waitForProgress(podcastEpisode.id, progress: 0.1)

    await fakeRepo.resumeAllEpisodeFetchSuspensions()
    await staleProgress.value

    #expect(sharedState.downloadProgress[podcastEpisode.id] == 0.1)

    try await CacheHelpers.simulateBackgroundFailure(firstTaskID)
    #expect(sharedState.downloadProgress[podcastEpisode.id] == 0.1)
    try await CacheHelpers.simulateBackgroundFailure(replacementTaskID)
  }

  // MARK: - Cross-Contamination Regression

  // Regression for "AI Daily Brief plays Braid": URLSession taskIdentifiers
  // restart at 1 with each new background session and used to collide with
  // stale values left in the DB from a prior session. Attribution by
  // taskIdentifier therefore could write one episode's downloaded audio
  // into another episode's cached file slot. Attribution must instead use
  // the taskDescription set at task creation, which is stable across
  // sessions.
  @Test("download attribution uses taskDescription, not taskIdentifier")
  func downloadAttributionUsesTaskDescription() async throws {
    let (podcastEpisode1, podcastEpisode2) = try await Create.twoPodcastEpisodes()
    try await repo.updateDownloading(podcastEpisode2.id, downloading: true)

    // Synthesize a finished download whose taskID does not match anything
    // the DB knows about, but whose taskDescription pins it to #2.
    let task = FakeURLSessionDownloadTask(
      taskID: URLSessionDownloadTask.ID(42),
      taskDescription: String(podcastEpisode2.id.rawValue),
      originalRequest: URLRequest(url: podcastEpisode2.episode.mediaURL.rawValue)
    )

    let tempFile = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try await fileManager.writeData(Data.random(), to: tempFile)
    await cacheBackgroundDelegate.urlSession(
      session,
      downloadTask: task,
      didFinishDownloadingTo: tempFile
    )

    let updated2 = try await repo.episode(podcastEpisode2.id)!
    #expect(updated2.cacheStatus == .cached)
    let updated1 = try await repo.episode(podcastEpisode1.id)!
    #expect(updated1.cacheStatus != .cached)
  }

  // Defense-in-depth: even if a task somehow ends up attributed to the wrong
  // episode (e.g. a future regression), the URL mismatch must abort the
  // write so corrupt audio never lands in the wrong slot.
  @Test("download with mismatched URL is refused, leaving the episode uncached")
  func mismatchedURLRefused() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await repo.updateDownloading(podcastEpisode.id, downloading: true)

    let task = FakeURLSessionDownloadTask(
      taskDescription: String(podcastEpisode.id.rawValue),
      originalRequest: URLRequest(url: URL(string: "https://wrong.example.com/other.mp3")!)
    )

    let tempFile = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try await fileManager.writeData(Data.random(), to: tempFile)
    await cacheBackgroundDelegate.urlSession(
      session,
      downloadTask: task,
      didFinishDownloadingTo: tempFile
    )

    // The give-up path must clear downloading too, not just skip the write;
    // .uncached asserts both (not cached, not downloading).
    let updated = try await repo.episode(podcastEpisode.id)!
    #expect(updated.cacheStatus == .uncached)
  }

  // A terminal callback can fail to read its episode row (transient DB error),
  // not just find it missing. The id is still parseable from taskDescription,
  // so the give-up path must clear downloading and drop the temp file rather
  // than strand the episode as .caching with no live task until next launch.
  @Test("didFinishDownloadingTo clears state when the episode fetch throws")
  func didFinishDownloadingToClearsStateWhenEpisodeFetchThrows() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await repo.updateDownloading(podcastEpisode.id, downloading: true)

    let task = FakeURLSessionDownloadTask(
      taskDescription: String(podcastEpisode.id.rawValue),
      originalRequest: URLRequest(url: podcastEpisode.episode.mediaURL.rawValue)
    )
    let tempFile = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try await fileManager.writeData(Data.random(), to: tempFile)

    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.episodeFetchError(FinalizationInjectedRepoError())

    await cacheBackgroundDelegate.urlSession(
      session,
      downloadTask: task,
      didFinishDownloadingTo: tempFile
    )

    let updated = try await repo.episode(podcastEpisode.id)!
    #expect(updated.cacheStatus == .uncached)
    #expect(!fileManager.fileExists(at: tempFile))
  }

  @Test("didCompleteWithError clears state when the episode fetch throws")
  func didCompleteWithErrorClearsStateWhenEpisodeFetchThrows() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await repo.updateDownloading(podcastEpisode.id, downloading: true)

    let task = FakeURLSessionDownloadTask(
      taskDescription: String(podcastEpisode.id.rawValue),
      originalRequest: URLRequest(url: podcastEpisode.episode.mediaURL.rawValue)
    )

    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.episodeFetchError(FinalizationInjectedRepoError())

    await cacheBackgroundDelegate.urlSession(
      session,
      task: task,
      didCompleteWithError: FinalizationInjectedRepoError()
    )

    let updated = try await repo.episode(podcastEpisode.id)!
    #expect(updated.cacheStatus == .uncached)
  }
}

private struct FinalizationInjectedRepoError: Error, Sendable {}
