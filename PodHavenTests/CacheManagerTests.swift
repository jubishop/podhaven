// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of CacheManager tests", .container)
actor CacheManagerTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  private var session: FakeDataFetchable {
    Container.shared.cacheManagerSession() as! FakeDataFetchable
  }
  private var imageFetcher: FakeImageFetcher {
    Container.shared.imageFetcher() as! FakeImageFetcher
  }

  init() async throws {
    await cacheManager.start()
  }

  // MARK: - Queue Observation Tests

  @Test("episode added to queue gets cached")
  func episodeAddedToQueueGetsCached() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    let data = CacheHelpers.createRandomData()
    await session.respond(to: podcastEpisode.episode.media.rawValue, data: data)

    try await queue.unshift(podcastEpisode.id)
    let fileName = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(fileName)

    let fileURL = CacheManager.resolveCachedFilepath(for: fileName)
    let actualData = try Data(contentsOf: fileURL)
    #expect(actualData == data)
  }

  @Test("episode removed from queue gets cache cleared")
  func episodeRemovedFromQueueGetsCacheCleared() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // First cache the episode
    try await queue.unshift(podcastEpisode.id)
    let fileName = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(fileName)

    // Remove from queue and verify cache is cleared
    try await queue.dequeue(podcastEpisode.id)
    try await CacheHelpers.waitForNotCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFileRemoved(fileName)
  }

  @Test("multiple episodes added to queue are cached in descending order")
  func multipleEpisodesAddedToQueueAreCachedInDescendingOrder() async throws {
    // Create 7 episodes: 4 will be active, 3 will be pending
    var episodes: [PodcastEpisode] = Array.init(capacity: 7)
    for _ in 0..<7 { episodes.append(try await Create.podcastEpisode()) }

    // Set up all episodes to block until signaled
    var semaphores: [AsyncSemaphore] = []
    for episode in episodes {
      let semaphore = await session.waitThenRespond(to: episode.episode.media.rawValue)
      semaphores.append(semaphore)
    }

    // Add first 4 episodes to fill all concurrent slots
    try await queue.unshift(episodes[3].id)
    try await queue.unshift(episodes[2].id)
    try await queue.unshift(episodes[1].id)
    try await queue.unshift(episodes[0].id)

    // Now add 3 more episodes that will be pending
    try await queue.unshift(episodes[6].id)
    try await queue.unshift(episodes[5].id)
    try await queue.unshift(episodes[4].id)
    try await CacheHelpers.waitForTopPendingDownload(episodes[4].episode.media.rawValue)

    // Episodes 0-3 should be actively downloading (4 concurrent slots filled)
    // Episodes 4, 5, 6 should be pending in that order
    // Complete episode 0 to open a slot
    semaphores[0].signal()
    try await CacheHelpers.waitForCached(episodes[0].id)

    // Complete episode 4 to verify it was the next one selected (highest priority pending)
    semaphores[4].signal()
    try await CacheHelpers.waitForCached(episodes[4].id)

    // Complete episode 1 to open another slot
    semaphores[1].signal()
    try await CacheHelpers.waitForCached(episodes[1].id)

    // Complete episode 5 to verify it was selected (next highest priority pending)
    semaphores[5].signal()
    try await CacheHelpers.waitForCached(episodes[5].id)

    // Clean up remaining episodes
    semaphores[2].signal()
    semaphores[3].signal()
    semaphores[6].signal()

    try await CacheHelpers.waitForCached(episodes[2].id)
    try await CacheHelpers.waitForCached(episodes[3].id)
    try await CacheHelpers.waitForCached(episodes[6].id)

    // Verify all episodes are cached and queue order is maintained
    try await PlayHelpers.waitForQueue([
      episodes[4], episodes[5], episodes[6], episodes[0], episodes[1], episodes[2], episodes[3],
    ])
  }

  @Test("moving an episode in the queue reprioritizes it for download")
  func movingAnEpisodeInTheQueueReprioritizesItForDownload() async throws {
    // Create 7 episodes: 4 will be active, 3 will be pending
    var podcastEpisodes: [PodcastEpisode] = Array.init(capacity: 7)
    for _ in 0..<7 { podcastEpisodes.append(try await Create.podcastEpisode()) }

    // Set up all podcastEpisodes to block until signaled
    var semaphores: [AsyncSemaphore] = []
    for podcastEpisode in podcastEpisodes {
      let semaphore = await session.waitThenRespond(to: podcastEpisode.episode.media.rawValue)
      semaphores.append(semaphore)
    }

    // Add first 4 podcastEpisodes to fill all concurrent slots
    try await CacheHelpers.unshiftToActive(podcastEpisode: podcastEpisodes[3])
    try await CacheHelpers.unshiftToActive(podcastEpisode: podcastEpisodes[2])
    try await CacheHelpers.unshiftToActive(podcastEpisode: podcastEpisodes[1])
    try await CacheHelpers.unshiftToActive(podcastEpisode: podcastEpisodes[0])

    // Now add 3 more podcastEpisodes that will be pending
    try await CacheHelpers.unshiftToPending(podcastEpisode: podcastEpisodes[6])
    try await CacheHelpers.unshiftToPending(podcastEpisode: podcastEpisodes[5])
    try await CacheHelpers.unshiftToPending(podcastEpisode: podcastEpisodes[4])

    // Now move episode 6 to the top of the queue, reprioritizing it to come next
    try await CacheHelpers.unshiftToPending(podcastEpisode: podcastEpisodes[6])
  }

  @Test("episode dequeued mid-download does not get cached when download completes")
  func episodeDequeuedMidDownloadDoesNotGetCachedWhenDownloadCompletes() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // Set up delayed response
    let asyncSemaphore = await session.waitThenRespond(to: podcastEpisode.episode.media.rawValue)

    try await queue.unshift(podcastEpisode.id)
    try await CacheHelpers.waitForActiveDownloadTask(podcastEpisode.id)
    try await queue.dequeue(podcastEpisode.id)
    try await CacheHelpers.waitForNotActiveDownloadTask(podcastEpisode.id)
    asyncSemaphore.signal()

    try await CacheHelpers.waitForNotCached(podcastEpisode.id)
  }

  // MARK: - Artwork Prefetching

  @Test("episode artwork is prefetched when episode is cached")
  func episodeArtworkIsPrefetchedWhenEpisodeIsCached() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await queue.unshift(podcastEpisode.id)
    let fileName = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(fileName)

    #expect(await imageFetcher.prefetchCounts[podcastEpisode.image] == 1)
  }
}
