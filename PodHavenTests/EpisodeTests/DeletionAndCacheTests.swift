// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("Episode deletion and cache tests", .container)
class EpisodeDeletionAndCacheTests {
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  private var fileManager: FakeFileManager {
    Container.shared.fileManager() as! FakeFileManager
  }

  // MARK: - Deletion Tests

  @Test("that deleting a podcast removes cached episode files")
  func deletePodcastRemovesCachedFiles() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let episode1 = try Create.unsavedEpisode(cachedFilename: "episode-1.mp3")
    let episode2 = try Create.unsavedEpisode(cachedFilename: "episode-2.mp3")
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [episode1, episode2, Create.unsavedEpisode()]
      )
    )
    let podcast = series.podcast
    let episodes = Array(series.episodes.filter { $0.cacheStatus == .cached })

    // Write files to cached locations
    let fileManager = Container.shared.fileManager() as! FakeFileManager
    for episode in episodes {
      guard let cachedURL = episode.cachedURL else {
        Assert.fatal("Episode should have cached URL")
      }
      try await fileManager.writeData(Data(UUID().uuidString.utf8), to: cachedURL.rawValue)
      try await CacheHelpers.waitForCachedFile(cachedURL)
    }

    // Delete podcast
    let count = try await repo.deletePodcast([podcast.id])
    #expect(count == 1)
    let afterDeletion = try await repo.podcastSeries(podcast.id)
    #expect(afterDeletion == nil)

    // Verify files are removed
    for episode in episodes {
      guard let cachedURL = episode.cachedURL
      else { Assert.fatal("Episode should have cached URL") }
      try await CacheHelpers.waitForCachedFileRemoved(cachedURL)
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
    let podcastEpisode = PodcastEpisode(podcast: podcast, episode: series.episodes.first!)
    let onDeck = try await PlayHelpers.load(podcastEpisode)
    #expect(onDeck.id == podcastEpisode.id)

    // Delete podcast
    try await repo.deletePodcast(podcast.id)
    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForOnDeck(nil)
  }

  @Test("that deletion succeeds when cached file is missing")
  func deletePodcastSucceedsWhenCachedFileMissing() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let episode = try Create.unsavedEpisode(cachedFilename: "missing.mp3")
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [episode]
      )
    )
    let podcast = series.podcast

    // No file written to the cached location

    // Delete podcast - should succeed even though cached file doesn't exist
    let deletionSucceeded = try await repo.deletePodcast(podcast.id)
    #expect(deletionSucceeded == true)

    let afterDeletion = try await repo.podcastSeries(podcast.id)
    #expect(afterDeletion == nil)
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
