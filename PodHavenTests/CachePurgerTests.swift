// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of CachePurger tests", .container)
@MainActor class CachePurgerTests {
  @DynamicInjected(\.cachePurger) private var cachePurger
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  private var fileManager: FakeFileManager {
    Container.shared.podFileManager() as! FakeFileManager
  }

  // MARK: - Helper Methods

  private func createCachedEpisode(
    title: String,
    cachedFilename: String,
    dataSize: Int = 1024 * 1024,  // 1 MB default
    completionDate: Date? = nil,
    pubDate: Date? = nil
  ) async throws -> Episode {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(
      title: title,
      pubDate: pubDate,
      completionDate: completionDate,
      cachedFilename: cachedFilename
    )

    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )

    let episode = podcastSeries.episodes.first!

    // Write fake file to simulate cached episode
    if let cachedURL = episode.cachedURL {
      let data = Data(count: dataSize)
      try await fileManager.writeData(data, to: cachedURL.rawValue)
    }

    return episode
  }

  // MARK: - Cache Size Calculation Tests

  @Test("executePurge does nothing when cache is below limit")
  func executePurgeDoesNothingWhenCacheBelowLimit() async throws {
    // Create a small cached episode (under 500 MB limit)
    let episode = try await createCachedEpisode(
      title: "Small Episode",
      cachedFilename: "small.mp3",
      dataSize: 10 * 1024 * 1024  // 10 MB
    )

    try await cachePurger.executePurge()

    // Episode should still be cached
    let updatedEpisode = try await repo.episode(episode.id)
    #expect(updatedEpisode?.cacheStatus == .cached)
  }

  @Test("executePurge removes oldest played episodes first")
  func executePurgeRemovesOldestPlayedEpisodesFirst() async throws {
    let fourDaysAgo = Date.now.addingTimeInterval(-4 * 24 * 60 * 60)
    let threeDaysAgo = Date.now.addingTimeInterval(-3 * 24 * 60 * 60)

    // Create episodes that exceed cache limit (500 MB)
    let oldPlayed1 = try await createCachedEpisode(
      title: "Old Played 1",
      cachedFilename: "old-played-1.mp3",
      dataSize: 200 * 1024 * 1024,  // 200 MB
      completionDate: fourDaysAgo
    )

    let oldPlayed2 = try await createCachedEpisode(
      title: "Old Played 2",
      cachedFilename: "old-played-2.mp3",
      dataSize: 200 * 1024 * 1024,  // 200 MB
      completionDate: threeDaysAgo
    )

    let recentUnplayed = try await createCachedEpisode(
      title: "Recent Unplayed",
      cachedFilename: "recent-unplayed.mp3",
      dataSize: 200 * 1024 * 1024  // 200 MB
    )

    try await cachePurger.executePurge()

    // Oldest played should be deleted first
    let updatedOldPlayed1 = try await repo.episode(oldPlayed1.id)
    #expect(updatedOldPlayed1?.cacheStatus == .uncached)

    // Recent unplayed should still be cached
    let updatedRecentUnplayed = try await repo.episode(recentUnplayed.id)
    #expect(updatedRecentUnplayed?.cacheStatus == .cached)
  }

  @Test("executePurge removes oldest unplayed episodes after old played")
  func executePurgeRemovesOldestUnplayedEpisodesAfterOldPlayed() async throws {
    let fourDaysAgo = Date.now.addingTimeInterval(-4 * 24 * 60 * 60)
    let fiveDaysAgo = Date.now.addingTimeInterval(-5 * 24 * 60 * 60)

    // Create episodes that exceed cache limit (500 MB)
    let oldUnplayed = try await createCachedEpisode(
      title: "Old Unplayed",
      cachedFilename: "old-unplayed.mp3",
      dataSize: 300 * 1024 * 1024,  // 300 MB
      pubDate: fiveDaysAgo
    )

    let oldPlayed = try await createCachedEpisode(
      title: "Old Played",
      cachedFilename: "old-played.mp3",
      dataSize: 300 * 1024 * 1024,  // 300 MB
      completionDate: fourDaysAgo,
      pubDate: fiveDaysAgo
    )

    let recentUnplayed = try await createCachedEpisode(
      title: "Recent Unplayed",
      cachedFilename: "recent-unplayed.mp3",
      dataSize: 300 * 1024 * 1024  // 300 MB
    )

    try await cachePurger.executePurge()

    // Old played should be deleted first
    let updatedOldPlayed = try await repo.episode(oldPlayed.id)
    #expect(updatedOldPlayed?.cacheStatus == .uncached)

    // Old unplayed should be deleted second
    let updatedOldUnplayed = try await repo.episode(oldUnplayed.id)
    #expect(updatedOldUnplayed?.cacheStatus == .uncached)

    // Recent unplayed should still be cached
    let updatedRecentUnplayed = try await repo.episode(recentUnplayed.id)
    #expect(updatedRecentUnplayed?.cacheStatus == .cached)
  }

  @Test("executePurge removes recent episodes by oldest pubDate when needed")
  func executePurgeRemovesRecentEpisodesByOldestPubDateWhenNeeded() async throws {
    let oneDayAgo = Date.now.addingTimeInterval(-1 * 24 * 60 * 60)
    let yesterday = Date.now.addingTimeInterval(-1 * 24 * 60 * 60)
    let today = Date.now

    // Create episodes that exceed cache limit (500 MB), all recent
    let recentOlder = try await createCachedEpisode(
      title: "Recent Older",
      cachedFilename: "recent-older.mp3",
      dataSize: 200 * 1024 * 1024,  // 200 MB
      pubDate: yesterday
    )

    let recentNewer = try await createCachedEpisode(
      title: "Recent Newer",
      cachedFilename: "recent-newer.mp3",
      dataSize: 200 * 1024 * 1024,  // 200 MB
      pubDate: today
    )

    let recentNewest = try await createCachedEpisode(
      title: "Recent Newest",
      cachedFilename: "recent-newest.mp3",
      dataSize: 200 * 1024 * 1024  // 200 MB
    )

    try await cachePurger.executePurge()

    // Oldest by pubDate should be deleted
    let updatedRecentOlder = try await repo.episode(recentOlder.id)
    #expect(updatedRecentOlder?.cacheStatus == .uncached)

    // Newer episodes should still be cached
    let updatedRecentNewer = try await repo.episode(recentNewer.id)
    #expect(updatedRecentNewer?.cacheStatus == .cached)
  }

  @Test("executePurge does not remove queued episodes")
  func executePurgeDoesNotRemoveQueuedEpisodes() async throws {
    let fourDaysAgo = Date.now.addingTimeInterval(-4 * 24 * 60 * 60)

    // Create episodes that exceed cache limit (500 MB)
    let queuedOldPlayed = try await createCachedEpisode(
      title: "Queued Old Played",
      cachedFilename: "queued-old-played.mp3",
      dataSize: 300 * 1024 * 1024,  // 300 MB
      completionDate: fourDaysAgo
    )

    let unqueuedOldPlayed = try await createCachedEpisode(
      title: "Unqueued Old Played",
      cachedFilename: "unqueued-old-played.mp3",
      dataSize: 300 * 1024 * 1024,  // 300 MB
      completionDate: fourDaysAgo
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

    // Create episodes that slightly exceed cache limit (500 MB)
    let oldPlayed1 = try await createCachedEpisode(
      title: "Old Played 1",
      cachedFilename: "old-played-1.mp3",
      dataSize: 300 * 1024 * 1024,  // 300 MB
      completionDate: fourDaysAgo
    )

    let oldPlayed2 = try await createCachedEpisode(
      title: "Old Played 2",
      cachedFilename: "old-played-2.mp3",
      dataSize: 250 * 1024 * 1024,  // 250 MB
      completionDate: threeDaysAgo
    )

    try await cachePurger.executePurge()

    // Should only delete enough to get below limit
    // First episode (300 MB) should be deleted, bringing us to 250 MB
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
    Log.setSystem()

    let fourDaysAgo = Date.now.addingTimeInterval(-4 * 24 * 60 * 60)

    // Create episodes that exceed cache limit (500 MB)
    let episode1 = try await createCachedEpisode(
      title: "Episode 1",
      cachedFilename: "episode-1.mp3",
      dataSize: 600 * 1024 * 1024,  // 600 MB
      completionDate: fourDaysAgo
    )

    let episode2 = try await createCachedEpisode(
      title: "Episode 2",
      cachedFilename: "episode-2.mp3",
      dataSize: 600 * 1024 * 1024,  // 600 MB
      completionDate: fourDaysAgo
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
}
