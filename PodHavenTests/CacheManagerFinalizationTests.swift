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
}
