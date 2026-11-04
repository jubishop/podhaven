// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of CacheManager queued-download handoff tests", .container)
@MainActor struct CacheManagerHandoffTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.stateManager) private var stateManager

  private var session: FakeDataFetchable {
    Container.shared.cacheManagerSession() as! FakeDataFetchable
  }

  @Test("handoff starts downloads for queued episodes the observation has not seen")
  func handoffStartsUnobservedQueuedDownloads() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await queue.unshift(podcastEpisode.id)

    await cacheManager.handOffQueuedDownloads()

    let tasks = await downloadTasks(for: podcastEpisode.id)
    #expect(tasks.count == 1)
    for downloadTask in tasks {
      #expect(await downloadTask.isResumed())
    }
  }

  @Test("handoff does not retry a queued episode whose download already failed")
  func handoffDoesNotRetryFailedQueuedDownload() async throws {
    stateManager.start()
    cacheManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFailure(taskID)
    try await CacheHelpers.waitForNotDownloading(podcastEpisode.id)

    await cacheManager.handOffQueuedDownloads()

    #expect(await downloadTasks(for: podcastEpisode.id).isEmpty)
  }

  private func downloadTasks(for episodeID: Episode.ID) async -> [FakeURLSessionDownloadTask] {
    await session.downloadTasks().filter { $0.taskDescription == String(episodeID.rawValue) }
  }
}
