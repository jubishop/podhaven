// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of cache backup exclusion tests", .container)
@MainActor class CacheBackupExclusionTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.stateManager) private var stateManager

  private var fileManager: FakeFileManager {
    Container.shared.fileManager() as! FakeFileManager
  }

  @Test("start excludes the cache directory and files already in it from backup")
  func startExcludesCacheDirectoryAndExistingFilesFromBackup() async throws {
    let existingFileURL = CacheManager.cacheDirectory.appendingPathComponent("existing.mp3")
    try await fileManager.writeData(Data.random(), to: existingFileURL)
    #expect(try !fileManager.isExcludedFromBackup(existingFileURL))

    stateManager.start()
    cacheManager.start()
    try await waitForCacheDirectoryExcluded()

    #expect(try fileManager.isExcludedFromBackup(existingFileURL))
  }

  @Test("the cache directory reads as excluded through its trailing-slash URL")
  func cacheDirectoryExclusionReadsThroughTrailingSlashURL() async throws {
    stateManager.start()
    cacheManager.start()
    try await waitForCacheDirectoryExcluded()

    // cacheDirectory gains a trailing slash once the directory exists on disk.
    let directoryURL = URL(filePath: CacheManager.cacheDirectory.path, directoryHint: .isDirectory)
    #expect(try fileManager.isExcludedFromBackup(directoryURL))
  }

  @Test("a newly cached episode file is excluded from backup")
  func newlyCachedEpisodeFileIsExcludedFromBackup() async throws {
    stateManager.start()
    cacheManager.start()
    try await waitForCacheDirectoryExcluded()

    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(taskID)

    let cachedURL = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(cachedURL)

    #expect(try fileManager.isExcludedFromBackup(cachedURL.rawValue))
  }

  @Test("the system file manager excludes an item from backup")
  func systemFileManagerExcludesItemFromBackup() throws {
    let systemFileManager: any FileManaging = FileManager.default
    let fileURL = TestFiles.uniqueURL()
    try systemFileManager.writeDataSynchronously(Data.random(), to: fileURL)
    #expect(try !systemFileManager.isExcludedFromBackup(fileURL))

    try systemFileManager.excludeFromBackup(fileURL)

    #expect(try systemFileManager.isExcludedFromBackup(fileURL))
  }

  private func waitForCacheDirectoryExcluded() async throws {
    let fileManager = fileManager
    try await Wait.until(
      { try fileManager.isExcludedFromBackup(CacheManager.cacheDirectory) },
      { "Cache directory was never excluded from backup" }
    )
  }
}
