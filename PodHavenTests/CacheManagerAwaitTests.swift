// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of CacheManager await-download API", .container)
struct CacheManagerAwaitTests {
  @DynamicInjected(\.cacheManager) private var cacheManager

  init() {
    cacheManager.start()
  }

  @Test("cachedURL(downloadingIfNeeded:) returns immediately for an already-cached episode")
  func returnsImmediatelyWhenCached() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(taskID)
    let expected = try await CacheHelpers.waitForCached(podcastEpisode.id)

    let result = try await cacheManager.cachedURL(downloadingIfNeeded: podcastEpisode.id)
    #expect(result == expected)
  }

  @Test("cachedURL(downloadingIfNeeded:) starts a download and resolves when it completes")
  func startsDownloadAndResolvesOnCompletion() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // Start awaiting before the download exists so the latch is registered
    // before the completion callback fires.
    async let pending = cacheManager.cachedURL(downloadingIfNeeded: podcastEpisode.id)

    let taskID = try await CacheHelpers.waitForDownloadTask(podcastEpisode.id)
    try await CacheHelpers.waitForResumed(taskID)
    let data = Data.random()
    try await CacheHelpers.simulateBackgroundFinish(taskID, data: data)

    let resolved = try await pending
    let cachedURL = try #require(resolved)
    let actualData = try await CacheHelpers.cachedFileData(for: cachedURL)
    #expect(actualData == data)
  }

  @Test("cachedURL(downloadingIfNeeded:) resolves nil when the download fails")
  func resolvesNilOnFailure() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    async let pending = cacheManager.cachedURL(downloadingIfNeeded: podcastEpisode.id)

    let taskID = try await CacheHelpers.waitForDownloadTask(podcastEpisode.id)
    try await CacheHelpers.waitForResumed(taskID)
    try await CacheHelpers.simulateBackgroundFailure(taskID)

    let result = try await pending
    #expect(result == nil)
  }
}
