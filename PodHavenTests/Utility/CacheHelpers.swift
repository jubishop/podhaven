// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

enum CacheHelpers {
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

  // MARK: - Download Status

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

  static func waitForTaskID(for episodeID: Episode.ID) async throws -> Int {
    try await Wait.forValue {
      let repo: any Databasing = Container.shared.repo()
      guard let episode = try await repo.episode(episodeID) else { return nil }
      let mg = MediaGUID(guid: episode.unsaved.guid, media: episode.unsaved.media)
      let taskMap = Container.shared.cacheTaskMapStore()
      return await taskMap.taskID(for: mg)
    }
  }

  // MARK: - Background Download Simulation

  static func simulateBackgroundFinish(_ episodeID: Episode.ID, data: Data) async throws {
    // Persist a mapping for a fake background task
    let taskID = Int.random(in: 1000...9_999_999)
    let repo: any Databasing = Container.shared.repo()
    guard let episode = try await repo.episode(episodeID) else {
      throw CacheError.episodeNotFound(episodeID)
    }
    let mg = MediaGUID(guid: episode.unsaved.guid, media: episode.unsaved.media)
    let taskMap = Container.shared.cacheTaskMapStore()
    await taskMap.set(taskID: taskID, for: mg)

    // Also mark CacheState as downloading for more realistic simulation
    let cacheState: CacheState = await Container.shared.cacheState()
    await cacheState.setDownloadTaskIdentifier(episodeID, taskIdentifier: taskID)

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
    // Persist mapping and CacheState download indicator
    let taskID = Int.random(in: 10_000_000...99_999_999)
    let repo: any Databasing = Container.shared.repo()
    guard let episode = try await repo.episode(episodeID) else {
      throw CacheError.episodeNotFound(episodeID)
    }
    let mg = MediaGUID(guid: episode.unsaved.guid, media: episode.unsaved.media)
    let taskMap = Container.shared.cacheTaskMapStore()
    await taskMap.set(taskID: taskID, for: mg)
    let cacheState: CacheState = await Container.shared.cacheState()
    await cacheState.setDownloadTaskIdentifier(episodeID, taskIdentifier: taskID)

    await cacheManagerSession.failDownload(taskID: taskID, error: error)
  }
}
