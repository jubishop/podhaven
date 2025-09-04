// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

enum CacheHelpers {
  // MARK: - Scheduling Waits

  static func waitForScheduledTaskID(_ episodeID: Episode.ID) async throws -> DownloadTaskID {
    try await Wait.forValue {
      let repo: any Databasing = Container.shared.repo()
      guard let episode = try await repo.episode(episodeID),
        let dbTaskID = episode.unsaved.downloadTaskID
      else { return nil }
      let cs: CacheState = await Container.shared.cacheState()
      guard let stateTaskID = await cs.getBackgroundTaskIdentifier(episodeID),
        stateTaskID == dbTaskID
      else { return nil }
      return dbTaskID
    }
  }
  // MARK: - Dependency Access

  private static var appDB: AppDB { Container.shared.appDB() }
  private static var cacheManager: CacheManager { Container.shared.cacheManager() }
  private static var cacheManagerSession: FakeDataFetchable {
    Container.shared.cacheManagerSession() as! FakeDataFetchable
  }
  private static var cacheState: CacheState { get async { await Container.shared.cacheState() } }
  private static var podFileManager: any FileManageable { Container.shared.podFileManager() }
  private static var queue: any Queueing { Container.shared.queue() }
  private static var repo: any Databasing { Container.shared.repo() }

  // MARK: - Queue Manipulation

  static func unshiftToActive(podcastEpisode: PodcastEpisode) async throws {
    try await queue.unshift(podcastEpisode.id)
    try await waitForCacheStateDownloading(podcastEpisode.id)
  }

  // MARK: - Episode Status

  @discardableResult
  static func waitForCached(_ episodeID: Episode.ID) async throws -> String {
    try await Wait.forValue(
      {
        let episode: Episode? = try await repo.episode(episodeID)
        return episode?.cachedFilename
      }
    )
  }

  static func waitForNotCached(_ episodeID: Episode.ID) async throws {
    try await Wait.until(
      {
        let episode: Episode? = try await repo.episode(episodeID)
        return episode?.cachedFilename == nil
      },
      { "Episode \(episodeID) cachedFilename is not nil" }
    )
  }

  @discardableResult
  static func waitForDownloadTaskID(_ episodeID: Episode.ID) async throws -> DownloadTaskID {
    try await Wait.forValue(
      {
        let episode: Episode? = try await repo.episode(episodeID)
        return episode?.downloadTaskID
      }
    )
  }

  static func waitForNoDownloadTaskID(_ episodeID: Episode.ID) async throws {
    try await Wait.until(
      {
        let episode: Episode? = try await repo.episode(episodeID)
        return episode?.downloadTaskID == nil
      },
      { "Episode \(episodeID) downloadTaskID is not nil" }
    )
  }

  // MARK: - CacheState Status

  static func waitForCacheStateDownloading(_ episodeID: Episode.ID) async throws {
    try await Wait.until(
      { await cacheState.isDownloading(episodeID) },
      { "Expected episode id: \(episodeID) to be downloading in CacheState" }
    )
  }

  static func waitForCacheStateNotDownloading(_ episodeID: Episode.ID) async throws {
    try await Wait.until(
      { await cacheState.isDownloading(episodeID) == false },
      { "Expected episode id: \(episodeID) to not be downloading in CacheState" }
    )
  }

  // MARK: - File Status

  static func waitForCachedFile(_ fileName: String) async throws {
    try await Wait.until(
      {
        let fileURL = CacheManager.resolveCachedFilepath(for: fileName)
        return await podFileManager.fileExists(at: fileURL)
      },
      { "Cached file: \(fileName) does not exist on disk" }
    )
  }

  static func waitForCachedFileRemoved(_ fileName: String) async throws {
    try await Wait.until(
      {
        let fileURL = CacheManager.resolveCachedFilepath(for: fileName)
        return await !podFileManager.fileExists(at: fileURL)
      },
      { "Cached file: \(fileName) still exists on disk" }
    )
  }

  // MARK: - Data Generation

  static func createRandomData(size: Int = 1024) -> Data {
    var data = Data(capacity: size)
    for _ in 0..<size {
      data.append(UInt8.random(in: 0...255))
    }
    return data
  }

  static func readCachedFileData(_ fileName: String) async throws -> Data {
    let fileURL = CacheManager.resolveCachedFilepath(for: fileName)
    return try await podFileManager.readData(from: fileURL)
  }

  // MARK: - Task Map Helpers

  static func waitForTaskID(for episodeID: Episode.ID) async throws -> DownloadTaskID {
    try await Wait.forValue {
      let repo: any Databasing = Container.shared.repo()
      guard let episode = try await repo.episode(episodeID) else { return nil }
      return episode.unsaved.downloadTaskID
    }
  }

  // MARK: - Background Download Simulation

  static func simulateBackgroundFinish(_ episodeID: Episode.ID, data: Data) async throws {
    // Prefer the real scheduled task if present; otherwise finish with a synthetic taskID
    let taskID: DownloadTaskID =
      (try? await waitForScheduledTaskID(episodeID))
      ?? DownloadTaskID(Int.random(in: 1_000_000...9_999_999))

    // Write data to a temp location simulating the downloaded file
    let tmpURL = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let pfm: any FileManageable = Container.shared.podFileManager()
    try await pfm.writeData(data, to: tmpURL)

    // Ask the fake background fetchable to complete by invoking the delegate
    await cacheManagerSession.finishDownload(taskID: taskID, tmpURL: tmpURL)
  }

  static func simulateBackgroundFailure(
    _ episodeID: Episode.ID,
    error: Error = NSError(domain: "Test", code: -1)
  ) async throws {
    let taskID = try await waitForScheduledTaskID(episodeID)

    // Invoke failure on the fake background session
    await cacheManagerSession.failDownload(taskID: taskID, error: error)
  }
}
