// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

enum CacheHelpers {
  // MARK: - Dependency Access

  private static var appDB: AppDB { Container.shared.appDB() }
  private static var cacheManager: CacheManager { Container.shared.cacheManager() }
  private static var downloadManager: DownloadManager { Container.shared.cacheDownloadManager() }
  private static var queue: Queue { Container.shared.queue() }
  private static var repo: any Databasing { Container.shared.repo() }

  private static var session: FakeDataFetchable {
    Container.shared.cacheManagerSession() as! FakeDataFetchable
  }

  // MARK: - Wait Helpers

  static func waitForCached(_ episodeID: Episode.ID) async throws {
    try await Wait.until(
      {
        let episode: Episode? = try await repo.episode(episodeID)
        return episode?.cachedMediaURL != nil
      },
      { "Episode \(episodeID) cachedMediaURL is: nil" }
    )
  }

  static func waitForNotCached(_ episodeID: Episode.ID) async throws {
    try await Wait.until(
      {
        let episode: Episode? = try await repo.episode(episodeID)
        return episode?.cachedMediaURL == nil
      },
      { "Episode \(episodeID) cachedMediaURL is not nil" }
    )
  }

  static func waitForTopPendingDownload(_ url: URL) async throws {
    try await Wait.until(
      { await self.downloadManager.pendingDownloads.first?.url == url },
      { "Expected episode url: \(url.hash()) to be the first pending download" }
    )
  }
}
