// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of CacheManager tests", .container)
@MainActor class CacheManagerTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.cacheState) private var cacheState
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  private var session: FakeDataFetchable {
    Container.shared.cacheManagerSession() as! FakeDataFetchable
  }
  private var imageFetcher: FakeImageFetcher {
    Container.shared.imageFetcher() as! FakeImageFetcher
  }

  init() async throws {
    try await cacheManager.start()
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

    let actualData = try await CacheHelpers.readCachedFileData(fileName)
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
    try await CacheHelpers.waitForCacheStateDownloading(podcastEpisode.id)

    try await queue.dequeue(podcastEpisode.id)
    try await CacheHelpers.waitForCacheStateNotDownloading(podcastEpisode.id)

    asyncSemaphore.signal()

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

  // MARK: - CacheState Tests

  @Test("CacheState is updated when episode starts downloading")
  func cacheStateIsUpdatedWhenEpisodeStartsDownloading() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // Initially, episode should not be downloading in CacheState
    #expect(!cacheState.isDownloading(podcastEpisode.id))

    // Set up delayed response to keep download active
    let asyncSemaphore = await session.waitThenRespond(to: podcastEpisode.episode.media.rawValue)

    try await queue.unshift(podcastEpisode.id)

    // Verify CacheState shows episode as downloading
    try await CacheHelpers.waitForCacheStateDownloading(podcastEpisode.id)

    // Complete the download
    asyncSemaphore.signal()
    try await CacheHelpers.waitForCached(podcastEpisode.id)

    // Verify CacheState shows episode as not downloading
    try await CacheHelpers.waitForCacheStateNotDownloading(podcastEpisode.id)
  }

  @Test("CacheState is updated when episode download is cancelled")
  func cacheStateIsUpdatedWhenEpisodeDownloadIsCancelled() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // Set up delayed response to keep download active
    let asyncSemaphore = await session.waitThenRespond(to: podcastEpisode.episode.media.rawValue)

    try await queue.unshift(podcastEpisode.id)

    // Verify CacheState shows episode as downloading
    try await CacheHelpers.waitForCacheStateDownloading(podcastEpisode.id)

    // Remove from queue to cancel download
    try await queue.dequeue(podcastEpisode.id)

    // Verify CacheState shows episode as not downloading
    try await CacheHelpers.waitForCacheStateNotDownloading(podcastEpisode.id)

    // Complete the original request (should be ignored since cancelled)
    asyncSemaphore.signal()
  }

  @Test("CacheState tracks multiple episodes downloading simultaneously")
  func cacheStateTracksMultipleEpisodesDownloadingSimultaneously() async throws {
    // Create 3 episodes
    let episode1 = try await Create.podcastEpisode()
    let episode2 = try await Create.podcastEpisode()
    let episode3 = try await Create.podcastEpisode()

    // Set up delayed responses
    let semaphore1 = await session.waitThenRespond(to: episode1.episode.media.rawValue)
    let semaphore2 = await session.waitThenRespond(to: episode2.episode.media.rawValue)
    let semaphore3 = await session.waitThenRespond(to: episode3.episode.media.rawValue)

    // Add all to queue
    try await queue.unshift(episode1.id)
    try await queue.unshift(episode2.id)
    try await queue.unshift(episode3.id)

    // All should be downloading
    try await CacheHelpers.waitForCacheStateDownloading(episode1.id)
    try await CacheHelpers.waitForCacheStateDownloading(episode2.id)
    try await CacheHelpers.waitForCacheStateDownloading(episode3.id)

    // Complete episode1
    semaphore1.signal()
    try await CacheHelpers.waitForCached(episode1.id)
    try await CacheHelpers.waitForCacheStateNotDownloading(episode1.id)

    // Episode2 and episode3 should still be downloading
    #expect(cacheState.isDownloading(episode2.id))
    #expect(cacheState.isDownloading(episode3.id))

    // Complete remaining episodes
    semaphore2.signal()
    try await CacheHelpers.waitForCached(episode2.id)
    try await CacheHelpers.waitForCacheStateNotDownloading(episode2.id)
    semaphore3.signal()
    try await CacheHelpers.waitForCached(episode3.id)
    try await CacheHelpers.waitForCacheStateNotDownloading(episode3.id)
  }
}
