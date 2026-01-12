// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Sharing
import Testing

@testable import PodHaven

@Suite("of CachePurger tests", .container)
@MainActor class CachePurgerTests {
  @DynamicInjected(\.cachePurger) private var cachePurger
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  @ObservationIgnored @Shared(.appStorage("cacheSizeLimitGB"))
  private var cacheSizeLimitGB: Double?

  private var fileManager: FakeFileManager {
    Container.shared.fileManager() as! FakeFileManager
  }

  // MARK: - Cache Size Calculation Tests

  @Test("executePurge does nothing when cache is below limit")
  func executePurgeDoesNothingWhenCacheBelowLimit() async throws {
    // Create a small cached episode (under 500 MB limit)
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Small Episode",
      cachedFilename: "small.mp3",
      dataSize: 10 * 1024 * 1024  // 10 MB
    )

    try await cachePurger.executePurge()

    // Episode should still be cached
    let updatedEpisode = try await repo.episode(episode.id)
    #expect(updatedEpisode?.cacheStatus == .cached)
  }

  @Test("executePurge removes finished episodes by earliest finishDate")
  func executePurgeRemovesFinishedEpisodesByEarliestFinishDate() async throws {
    let fourDaysAgo = Date.now.addingTimeInterval(-4 * 24 * 60 * 60)
    let threeDaysAgo = Date.now.addingTimeInterval(-3 * 24 * 60 * 60)

    // Create episodes that exceed cache limit
    let oldPlayed1 = try await CacheHelpers.createCachedEpisode(
      title: "Old Played 1",
      cachedFilename: "old-played-1.mp3",
      dataSize: Int(Double(cachePurger.cacheSizeLimit) * 0.4),
      finishDate: fourDaysAgo
    )

    let _ = try await CacheHelpers.createCachedEpisode(
      title: "Old Played 2",
      cachedFilename: "old-played-2.mp3",
      dataSize: Int(Double(cachePurger.cacheSizeLimit) * 0.4),
      finishDate: threeDaysAgo
    )

    let recentUnplayed = try await CacheHelpers.createCachedEpisode(
      title: "Recent Unplayed",
      cachedFilename: "recent-unplayed.mp3",
      dataSize: Int(Double(cachePurger.cacheSizeLimit) * 0.4),
    )

    try await cachePurger.executePurge()

    // Earliest completion date should be deleted first
    let updatedOldPlayed1 = try await repo.episode(oldPlayed1.id)
    #expect(updatedOldPlayed1?.cacheStatus == .uncached)

    // Unfinished episode should still be cached
    let updatedRecentUnplayed = try await repo.episode(recentUnplayed.id)
    #expect(updatedRecentUnplayed?.cacheStatus == .cached)
  }

  @Test("executePurge removes unfinished episodes after finished ones")
  func executePurgeRemovesUnfinishedEpisodesAfterFinishedOnes() async throws {
    let fourDaysAgo = Date.now.addingTimeInterval(-4 * 24 * 60 * 60)
    let fiveDaysAgo = Date.now.addingTimeInterval(-5 * 24 * 60 * 60)

    // Create episodes that exceed cache limit
    let oldUnplayed = try await CacheHelpers.createCachedEpisode(
      title: "Old Unplayed",
      cachedFilename: "old-unplayed.mp3",
      dataSize: Int(Double(cachePurger.cacheSizeLimit) * 0.6),
      pubDate: fiveDaysAgo
    )

    let oldPlayed = try await CacheHelpers.createCachedEpisode(
      title: "Old Played",
      cachedFilename: "old-played.mp3",
      dataSize: Int(Double(cachePurger.cacheSizeLimit) * 0.6),
      finishDate: fourDaysAgo,
      pubDate: fiveDaysAgo
    )

    let recentUnplayed = try await CacheHelpers.createCachedEpisode(
      title: "Recent Unplayed",
      cachedFilename: "recent-unplayed.mp3",
      dataSize: Int(Double(cachePurger.cacheSizeLimit) * 0.6)
    )

    try await cachePurger.executePurge()

    // Finished episode should be deleted first
    let updatedOldPlayed = try await repo.episode(oldPlayed.id)
    #expect(updatedOldPlayed?.cacheStatus == .uncached)

    // Next deletion should be the earliest unfinished episode by pubDate
    let updatedOldUnplayed = try await repo.episode(oldUnplayed.id)
    #expect(updatedOldUnplayed?.cacheStatus == .uncached)

    // Recent unplayed should still be cached
    let updatedRecentUnplayed = try await repo.episode(recentUnplayed.id)
    #expect(updatedRecentUnplayed?.cacheStatus == .cached)
  }

  @Test("executePurge orders unfinished deletions by pubDate")
  func executePurgeOrdersUnfinishedDeletionsByPubDate() async throws {
    let yesterday = Date.now.addingTimeInterval(-1 * 24 * 60 * 60)
    let today = Date.now

    // Create episodes that exceed cache limit, all recent
    let recentOlder = try await CacheHelpers.createCachedEpisode(
      title: "Recent Older",
      cachedFilename: "recent-older.mp3",
      dataSize: Int(Double(cachePurger.cacheSizeLimit) * 0.4),
      pubDate: yesterday
    )

    let recentNewer = try await CacheHelpers.createCachedEpisode(
      title: "Recent Newer",
      cachedFilename: "recent-newer.mp3",
      dataSize: Int(Double(cachePurger.cacheSizeLimit) * 0.4),
      pubDate: today
    )

    let _ = try await CacheHelpers.createCachedEpisode(
      title: "Recent Newest",
      cachedFilename: "recent-newest.mp3",
      dataSize: Int(Double(cachePurger.cacheSizeLimit) * 0.4)
    )

    try await cachePurger.executePurge()

    // Earliest pubDate should be deleted first among unfinished episodes
    let updatedRecentOlder = try await repo.episode(recentOlder.id)
    #expect(updatedRecentOlder?.cacheStatus == .uncached)

    // Newer pubDate should still be cached
    let updatedRecentNewer = try await repo.episode(recentNewer.id)
    #expect(updatedRecentNewer?.cacheStatus == .cached)
  }

  @Test("executePurge does not remove queued episodes")
  func executePurgeDoesNotRemoveQueuedEpisodes() async throws {
    let fourDaysAgo = Date.now.addingTimeInterval(-4 * 24 * 60 * 60)

    // Create episodes that exceed cache limit
    let queuedOldPlayed = try await CacheHelpers.createCachedEpisode(
      title: "Queued Old Played",
      cachedFilename: "queued-old-played.mp3",
      dataSize: Int(Double(cachePurger.cacheSizeLimit) * 0.6),
      finishDate: fourDaysAgo
    )

    let unqueuedOldPlayed = try await CacheHelpers.createCachedEpisode(
      title: "Unqueued Old Played",
      cachedFilename: "unqueued-old-played.mp3",
      dataSize: Int(Double(cachePurger.cacheSizeLimit) * 0.6),
      finishDate: fourDaysAgo
    )

    // Queue one of the episodes
    try await queue.unshift(queuedOldPlayed.id)

    try await cachePurger.executePurge()

    // Queued episode should still be cached
    let updatedQueued = try await repo.episode(queuedOldPlayed.id)
    #expect(updatedQueued?.cacheStatus == .cached)

    // Unqueued episode should be deleted
    let updatedUnqueued = try await repo.episode(unqueuedOldPlayed.id)
    #expect(updatedUnqueued?.cacheStatus == .uncached)
  }

  @Test("executePurge stops deleting when cache size is below limit")
  func executePurgeStopsDeletingWhenCacheSizeBelowLimit() async throws {
    let fourDaysAgo = Date.now.addingTimeInterval(-4 * 24 * 60 * 60)
    let threeDaysAgo = Date.now.addingTimeInterval(-3 * 24 * 60 * 60)

    // Create episodes that slightly exceed cache limit
    let oldPlayed1 = try await CacheHelpers.createCachedEpisode(
      title: "Old Played 1",
      cachedFilename: "old-played-1.mp3",
      dataSize: Int(Double(cachePurger.cacheSizeLimit) * 0.6),
      finishDate: fourDaysAgo
    )

    let oldPlayed2 = try await CacheHelpers.createCachedEpisode(
      title: "Old Played 2",
      cachedFilename: "old-played-2.mp3",
      dataSize: Int(Double(cachePurger.cacheSizeLimit) * 0.6),
      finishDate: threeDaysAgo
    )

    try await cachePurger.executePurge()

    // Should only delete enough to get below limit
    // First episode should be deleted
    let updatedOldPlayed1 = try await repo.episode(oldPlayed1.id)
    #expect(updatedOldPlayed1?.cacheStatus == .uncached)

    // Second episode should still be cached since we're now below limit
    let updatedOldPlayed2 = try await repo.episode(oldPlayed2.id)
    #expect(updatedOldPlayed2?.cacheStatus == .cached)
  }

  @Test("executePurge handles empty cache directory")
  func executePurgeHandlesEmptyCacheDirectory() async throws {
    // Don't create any episodes
    // Just run purge to ensure it doesn't crash
    try await cachePurger.executePurge()
  }

  @Test("executePurge handles file deletion errors gracefully")
  func executePurgeHandlesFileDeletionErrorsGracefully() async throws {
    let fourDaysAgo = Date.now.addingTimeInterval(-4 * 24 * 60 * 60)

    // Create episodes that exceed cache limit
    let episode1 = try await CacheHelpers.createCachedEpisode(
      title: "Episode 1",
      cachedFilename: "episode-1.mp3",
      dataSize: Int(Double(cachePurger.cacheSizeLimit) * 1.2),
      finishDate: fourDaysAgo
    )

    let episode2 = try await CacheHelpers.createCachedEpisode(
      title: "Episode 2",
      cachedFilename: "episode-2.mp3",
      dataSize: Int(Double(cachePurger.cacheSizeLimit) * 1.2),
      finishDate: fourDaysAgo
    )

    // Remove the file manually to cause a deletion error
    if let cachedURL = episode1.cachedURL {
      try fileManager.removeItem(at: cachedURL.rawValue)
    }

    // Should continue and delete episode2 despite error on episode1
    try await cachePurger.executePurge()

    // Episode 2 should be deleted even though episode 1 failed
    let updatedEpisode2 = try await repo.episode(episode2.id)
    #expect(updatedEpisode2?.cacheStatus == .uncached)
  }

  @Test("executePurge removes dangling files before purging episodes")
  func executePurgeRemovesDanglingFilesBeforePurgingEpisodes() async throws {
    // Create an episode with a cached file
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Valid Episode",
      cachedFilename: "valid-episode.mp3",
      dataSize: 10 * 1024 * 1024  // 10 MB
    )

    // Create a dangling file (file with no associated episode)
    let danglingFileURL = CacheManager.cacheDirectory.appendingPathComponent("dangling-file.mp3")
    let danglingData = Data(count: 5 * 1024 * 1024)  // 5 MB
    try await fileManager.writeData(danglingData, to: danglingFileURL)

    // Verify file exists
    #expect(fileManager.fileExists(at: danglingFileURL))

    try await cachePurger.executePurge()

    // Dangling file should be deleted
    #expect(!fileManager.fileExists(at: danglingFileURL))

    // Valid episode should still be cached (under limit)
    let updatedEpisode = try await repo.episode(episode.id)
    #expect(updatedEpisode?.cacheStatus == .cached)
  }

  @Test("executePurge handles multiple dangling files")
  func executePurgeHandlesMultipleDanglingFiles() async throws {
    // Create dangling files
    let danglingFile1URL = CacheManager.cacheDirectory.appendingPathComponent("dangling-1.mp3")
    let danglingFile2URL = CacheManager.cacheDirectory.appendingPathComponent("dangling-2.mp3")
    let danglingFile3URL = CacheManager.cacheDirectory.appendingPathComponent("dangling-3.mp3")

    let data = Data(count: 1024 * 1024)  // 1 MB each
    try await fileManager.writeData(data, to: danglingFile1URL)
    try await fileManager.writeData(data, to: danglingFile2URL)
    try await fileManager.writeData(data, to: danglingFile3URL)

    // Verify files exist
    #expect(fileManager.fileExists(at: danglingFile1URL))
    #expect(fileManager.fileExists(at: danglingFile2URL))
    #expect(fileManager.fileExists(at: danglingFile3URL))

    try await cachePurger.executePurge()

    // All dangling files should be deleted
    #expect(!fileManager.fileExists(at: danglingFile1URL))
    #expect(!fileManager.fileExists(at: danglingFile2URL))
    #expect(!fileManager.fileExists(at: danglingFile3URL))
  }

  @Test("executePurge clears cached filename when file is missing")
  func executePurgeClearsCachedFilenameWhenFileIsMissing() async throws {
    // Create an episode with a cached file
    let episode = try await CacheHelpers.createCachedEpisode(
      title: "Episode with missing file",
      cachedFilename: "missing-file.mp3",
      dataSize: 10 * 1024 * 1024  // 10 MB
    )

    // Verify episode is cached
    let cachedEpisode = try await repo.episode(episode.id)
    #expect(cachedEpisode?.cacheStatus == .cached)

    // Remove the file manually to simulate it going missing
    if let cachedURL = episode.cachedURL {
      try fileManager.removeItem(at: cachedURL.rawValue)
    }

    // Verify file no longer exists
    #expect(!fileManager.fileExists(at: episode.cachedURL!.rawValue))

    try await cachePurger.executePurge()

    // Episode's cached filename should be cleared
    let updatedEpisode = try await repo.episode(episode.id)
    #expect(updatedEpisode?.cacheStatus == .uncached)
    #expect(updatedEpisode?.cachedURL == nil)
  }

  @Test("executePurge uses updated user settings cache limit")
  func executePurgeUsesUpdatedUserSettingsCacheLimit() async throws {
    // Set a custom cache limit of 500 MB (0.5 GB)
    $cacheSizeLimitGB.withLock { $0 = 0.5 }

    // Verify the cache purger uses the new limit
    let expectedLimit: Int64 = Int64(0.5 * 1024 * 1024 * 1024)  // 500 MB in bytes
    #expect(cachePurger.cacheSizeLimit == expectedLimit)

    // Create episodes that exceed the 500 MB limit
    let episode1 = try await CacheHelpers.createCachedEpisode(
      title: "Episode 1",
      cachedFilename: "episode-1.mp3",
      dataSize: Int(Double(expectedLimit) * 0.7),  // 350 MB
      finishDate: Date.now.addingTimeInterval(-2 * 24 * 60 * 60)
    )

    let episode2 = try await CacheHelpers.createCachedEpisode(
      title: "Episode 2",
      cachedFilename: "episode-2.mp3",
      dataSize: Int(Double(expectedLimit) * 0.7),  // 350 MB
      finishDate: Date.now.addingTimeInterval(-1 * 24 * 60 * 60)
    )

    // Total is ~700 MB, which exceeds 500 MB limit
    try await cachePurger.executePurge()

    // Oldest episode should be deleted to bring cache under 500 MB limit
    let updatedEpisode1 = try await repo.episode(episode1.id)
    #expect(updatedEpisode1?.cacheStatus == .uncached)

    // Newer episode should still be cached (now under 500 MB limit)
    let updatedEpisode2 = try await repo.episode(episode2.id)
    #expect(updatedEpisode2?.cacheStatus == .cached)
  }

  @Test("executePurge does not remove episodes with saveInCache set")
  func executePurgeDoesNotRemoveEpisodesWithSaveInCache() async throws {
    let fourDaysAgo = Date.now.addingTimeInterval(-4 * 24 * 60 * 60)

    // Create episodes that exceed cache limit
    let savedOldPlayed = try await CacheHelpers.createCachedEpisode(
      title: "Saved Old Played",
      cachedFilename: "saved-old-played.mp3",
      dataSize: Int(Double(cachePurger.cacheSizeLimit) * 0.6),
      finishDate: fourDaysAgo,
      saveInCache: true
    )

    let unsavedOldPlayed = try await CacheHelpers.createCachedEpisode(
      title: "Unsaved Old Played",
      cachedFilename: "unsaved-old-played.mp3",
      dataSize: Int(Double(cachePurger.cacheSizeLimit) * 0.6),
      finishDate: fourDaysAgo
    )

    try await cachePurger.executePurge()

    // Episode with saveInCache should still be cached
    let updatedSaved = try await repo.episode(savedOldPlayed.id)
    #expect(updatedSaved?.cacheStatus == .cached)

    // Episode without saveInCache should be deleted
    let updatedUnsaved = try await repo.episode(unsavedOldPlayed.id)
    #expect(updatedUnsaved?.cacheStatus == .uncached)
  }
}
