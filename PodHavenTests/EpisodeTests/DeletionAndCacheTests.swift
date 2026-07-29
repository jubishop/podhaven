// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Episode deletion and cache tests", .container)
class EpisodeDeletionAndCacheTests {
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  private var fileManager: FakeFileManager {
    Container.shared.fileManager() as! FakeFileManager
  }

  // MARK: - Deletion Tests

  @Test("that batch podcast deletion removes every cached episode file")
  func batchPodcastDeletionRemovesCachedFiles() async throws {
    let firstSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(cachedFilename: "episode-1.mp3"),
          try Create.unsavedEpisode(),
        ]
      )
    )
    let secondSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(cachedFilename: "episode-2.mp3"),
          try Create.unsavedEpisode(cachedFilename: "episode-3.mp3"),
        ]
      )
    )
    let podcastIDs = [firstSeries.podcast.id, secondSeries.podcast.id]
    let episodes = Array(
      (firstSeries.episodes + secondSeries.episodes)
        .filter { $0.cacheStatus == .cached }
    )

    for episode in episodes {
      guard let cachedURL = episode.cachedURL else {
        Assert.fatal("Episode should have cached URL")
      }
      try await fileManager.writeData(Data(UUID().uuidString.utf8), to: cachedURL.rawValue)
      try await CacheHelpers.waitForCachedFile(cachedURL)
    }

    let count = try await repo.deletePodcast(podcastIDs)
    #expect(count == 2)
    for podcastID in podcastIDs {
      #expect(try await repo.podcastSeries(podcastID) == nil)
    }

    for episode in episodes {
      guard let cachedURL = episode.cachedURL
      else { Assert.fatal("Episode should have cached URL") }
      try await CacheHelpers.waitForCachedFileRemoved(cachedURL)
    }
  }

  @Test("that failed podcast deletion preserves cached files and metadata")
  func failedPodcastDeletionPreservesCache() async throws {
    let cachedData = Data("retained cache".utf8)
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(cachedFilename: "retained-after-failure.mp3")
        ]
      )
    )
    let episode = try #require(series.episodes.first)
    let cachedURL = try #require(episode.cachedURL)
    try await fileManager.writeData(cachedData, to: cachedURL.rawValue)
    try await Container.shared.appDB().unsafeTestDB
      .write { db in
        try db.execute(
          sql: """
            CREATE TEMP TRIGGER fail_podcast_delete
            BEFORE DELETE ON podcast
            BEGIN
              SELECT RAISE(ABORT, 'simulated podcast deletion failure');
            END
            """
        )
      }

    await #expect(throws: DatabaseError.self) {
      try await repo.deletePodcast(series.podcast.id)
    }

    let retainedEpisode = try await repo.episode(episode.id)
    #expect(retainedEpisode?.cachedURL == cachedURL)
    #expect(try await fileManager.readData(from: cachedURL.rawValue) == cachedData)
  }

  @Test("that deletion cleans an episode committed before its database transaction")
  func deletionCleansEpisodeCommittedAtTransactionBoundary() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    )
    let cachedFilename = "concurrent-refresh.mp3"
    let cachedURL = CacheManager.resolveCachedFilepath(for: cachedFilename)
    try await fileManager.writeData(Data("concurrent cache".utf8), to: cachedURL.rawValue)

    var unsavedEpisode = try Create.unsavedEpisode(cachedFilename: cachedFilename)
    unsavedEpisode.podcastId = series.podcast.id
    let episodeToInsert = unsavedEpisode
    let insertedEpisodeID = ThreadSafe<Episode.ID?>(nil)
    let insertionFailure = ThreadSafe<String?>(nil)
    Container.shared.fakeContinuousClock()
      .runBeforeNextNow {
        do {
          try Container.shared.appDB().unsafeTestDB
            .write { db in
              let episode = episodeToInsert
              let inserted = try episode.insertAndFetch(db, as: Episode.self)
              insertedEpisodeID(inserted.id)
            }
        } catch {
          insertionFailure(ErrorKit.message(for: error))
        }
      }

    #expect(try await repo.deletePodcast(series.podcast.id))
    try #require(insertionFailure() == nil)
    let episodeID = try #require(insertedEpisodeID())
    #expect(try await repo.episode(episodeID) == nil)
    #expect(!fileManager.fileExists(at: cachedURL.rawValue))
  }

  @Test("that one cache removal failure does not stop podcast deletion or later cleanup")
  func cacheRemovalFailureDoesNotStopDeletion() async throws {
    try await LogCapture.withSink { sink in
      let series = try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(),
          unsavedEpisodes: [
            try Create.unsavedEpisode(cachedFilename: "failing-removal.mp3"),
            try Create.unsavedEpisode(cachedFilename: "successful-removal.mp3"),
          ]
        )
      )
      let failingEpisode = series.episodes[0]
      let successfulEpisode = series.episodes[1]
      let failingURL = try #require(failingEpisode.cachedURL)
      let successfulURL = try #require(successfulEpisode.cachedURL)
      try await fileManager.writeData(Data("retained".utf8), to: failingURL.rawValue)
      try await fileManager.writeData(Data("removed".utf8), to: successfulURL.rawValue)
      fileManager.setRemoveItemError(TestError.simulatedFailure, for: failingURL.rawValue)

      #expect(try await repo.deletePodcast(series.podcast.id))

      #expect(try await repo.podcastSeries(series.podcast.id) == nil)
      #expect(fileManager.fileExists(at: failingURL.rawValue))
      #expect(!fileManager.fileExists(at: successfulURL.rawValue))
      let cleanupErrors = sink.captured()
        .filter {
          $0.label == "Database/repo"
            && $0.level == .error
            && $0.message.contains(failingURL.rawValue.lastPathComponent)
            && $0.message.contains(String(describing: failingEpisode.id))
        }
      #expect(cleanupErrors.count == 1)
    }
  }

  @Test("that deleting a podcast with a playing episode stops playback")
  func deletePodcastWithPlayingEpisode() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [Create.unsavedEpisode()]
      )
    )

    // Load and play episode
    let podcast = series.podcast
    let podcastEpisode = PodcastEpisode(
      podcast: podcast,
      episode: series.episodes.first!
    )
    let onDeck = try await PlayHelpers.load(podcastEpisode)
    #expect(onDeck.id == podcastEpisode.id)

    // Delete podcast
    try await repo.deletePodcast(podcast.id)
    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForOnDeck(nil)
  }

  @Test("that deletion succeeds when cached file is missing")
  func deletePodcastSucceedsWhenCachedFileMissing() async throws {
    try await LogCapture.withSink { sink in
      let unsavedPodcast = try Create.unsavedPodcast()
      let episode = try Create.unsavedEpisode(cachedFilename: "missing.mp3")
      let series = try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: unsavedPodcast,
          unsavedEpisodes: [episode]
        )
      )
      let podcast = series.podcast
      let cachedURL = try #require(series.episodes.first?.cachedURL)

      // No file written to the cached location

      // Delete podcast - should succeed even though cached file doesn't exist
      let deletionSucceeded = try await repo.deletePodcast(podcast.id)
      #expect(deletionSucceeded == true)

      let afterDeletion = try await repo.podcastSeries(podcast.id)
      #expect(afterDeletion == nil)
      let cleanupLogs = sink.captured()
        .filter {
          $0.label == "Database/repo"
            && $0.message.contains(cachedURL.rawValue.lastPathComponent)
        }
      #expect(cleanupLogs.count == 1)
      #expect(cleanupLogs.first?.level == .debug)
    }
  }

  // MARK: - Cache Tests

  @Test("cachedEpisodes returns only episodes with cached files")
  func cachedEpisodesReturnsOnlyCachedEpisodes() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()

    // Create episodes with cached files
    let cachedEpisode1 = try Create.unsavedEpisode(
      title: "Cached Episode 1",
      cachedFilename: "episode-1.mp3"
    )
    let cachedEpisode2 = try Create.unsavedEpisode(
      title: "Cached Episode 2",
      cachedFilename: "episode-2.mp3"
    )

    // Create episodes without cached files
    let uncachedEpisode1 = try Create.unsavedEpisode(title: "Uncached Episode 1")
    let uncachedEpisode2 = try Create.unsavedEpisode(title: "Uncached Episode 2")

    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [cachedEpisode1, uncachedEpisode1, cachedEpisode2, uncachedEpisode2]
      )
    )

    // Fetch cached episodes
    let cachedEpisodes = try await repo.cachedEpisodes()

    // Verify only cached episodes are returned
    #expect(cachedEpisodes.count == 2)
    let cachedTitles = Set(cachedEpisodes.map(\.title))
    #expect(cachedTitles == Set(["Cached Episode 1", "Cached Episode 2"]))

    // Verify all returned episodes have cached status
    #expect(cachedEpisodes.allSatisfy { $0.cacheStatus == .cached })
  }

  @Test("cachedEpisodes includes queued cached episodes")
  func cachedEpisodesIncludesQueuedEpisodes() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()

    // Create cached episodes
    let cachedEpisode1 = try Create.unsavedEpisode(
      title: "Cached Unqueued",
      cachedFilename: "episode-1.mp3"
    )
    let cachedEpisode2 = try Create.unsavedEpisode(
      title: "Cached Queued",
      cachedFilename: "episode-2.mp3"
    )

    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [cachedEpisode1, cachedEpisode2]
      )
    )

    // Queue one of the cached episodes
    try await queue.unshift(podcastSeries.episodes[1].id)

    // Fetch cached episodes
    let cachedEpisodes = try await repo.cachedEpisodes()

    // Verify both cached episodes are returned (queued and unqueued)
    #expect(cachedEpisodes.count == 2)
    let cachedTitles = Set(cachedEpisodes.map(\.title))
    #expect(cachedTitles == Set(["Cached Unqueued", "Cached Queued"]))
  }

  @Test("cachedEpisodes returns empty array when no episodes are cached")
  func cachedEpisodesReturnsEmptyWhenNoCachedEpisodes() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let uncachedEpisode1 = try Create.unsavedEpisode()
    let uncachedEpisode2 = try Create.unsavedEpisode()

    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [uncachedEpisode1, uncachedEpisode2]
      )
    )

    let cachedEpisodes = try await repo.cachedEpisodes()

    #expect(cachedEpisodes.isEmpty)
  }
}
