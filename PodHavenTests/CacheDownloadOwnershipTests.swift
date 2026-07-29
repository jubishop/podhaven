// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of cache download ownership", .container)
struct CacheDownloadOwnershipTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.repo) private var repo

  private var session: FakeDataFetchable {
    Container.shared.cacheManagerSession() as! FakeDataFetchable
  }

  @Test("stale failure leaves an active replacement downloading")
  func staleFailureLeavesActiveReplacementDownloading() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let staleTaskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)

    _ = try await cacheManager.clearCache(for: podcastEpisode.id)
    let replacementTaskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)

    try await CacheHelpers.simulateBackgroundFailure(
      staleTaskID,
      error: URLError(.cancelled)
    )

    let updatedEpisode = try #require(try await repo.episode(podcastEpisode.id))
    #expect(updatedEpisode.downloading)
    #expect(try await cacheManager.downloadToCache(for: podcastEpisode.id) == nil)

    let tasks = await session.downloadTasks()
    #expect(tasks[id: replacementTaskID] != nil)
  }

  @Test("downloading-state write failure does not log cache success")
  func downloadingStateWriteFailureDoesNotLogCacheSuccess() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)
    let fakeRepo = try #require(repo as? FakeRepo)
    fakeRepo.updateDownloadingFalseError(InjectedDownloadStateError())

    let captured = try await LogCapture.withSink { sink in
      try await CacheHelpers.simulateBackgroundFinish(taskID)
      return sink.captured()
    }

    let finalizationLogs = captured.filter {
      $0.label == "Cache/backgroundDelegate"
        && $0.message.contains(String(podcastEpisode.id.rawValue))
    }
    #expect(finalizationLogs.contains { $0.message.contains("failed to clear downloading flag") })
    #expect(!finalizationLogs.contains { $0.message.contains("Cached episode") })

    let episode = try #require(try await repo.episode(podcastEpisode.id))
    #expect(episode.downloading)
    #expect(episode.cachedURL != nil)
  }
}

private struct InjectedDownloadStateError: Error, Sendable {}
