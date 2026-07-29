// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of CacheBackgroundDelegate relaunch handling", .container)
@MainActor struct CacheBackgroundDelegateRelaunchTests {
  private var session: FakeDataFetchable {
    Container.shared.cacheManagerSession() as! FakeDataFetchable
  }

  @Test("cancelled callback after memory reset logs the missing episode at debug")
  func cancelledCallbackAfterMemoryResetLogsAtDebug() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.downloadToCache(podcastEpisode.id)
    let downloadTasks = await session.downloadTasks()
    let task = try #require(downloadTasks[id: taskID])

    try await Container.shared.appDB().unsafeTestDB
      .write { db in
        try db.execute(
          sql: "DELETE FROM episode WHERE id = ?",
          arguments: [podcastEpisode.id]
        )
      }
    Container.shared.cacheManager.reset(.scope)
    Container.shared.cacheBackgroundDelegate.reset(.scope)
    let relaunchedDelegate = Container.shared.cacheBackgroundDelegate()

    let captured = await LogCapture.withSink { sink in
      await relaunchedDelegate.urlSession(
        session,
        task: task,
        didCompleteWithError: URLError(.cancelled)
      )
      return sink.captured()
    }

    let missingEpisodeLogs = captured.filter {
      $0.label == "Cache/backgroundDelegate"
        && $0.message.contains("No episode for task")
        && $0.message.contains(String(podcastEpisode.id.rawValue))
    }
    #expect(missingEpisodeLogs.count == 1)
    #expect(missingEpisodeLogs.first?.level == .debug)
  }
}
