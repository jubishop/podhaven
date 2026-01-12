// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of StateManager tests", .container)
actor StateManagerTests {
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.repo) private var repo

  private let podcastSeries: PodcastSeries

  init() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    podcastSeries = try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: unsavedPodcast,
          unsavedEpisodes: [
            Create.unsavedEpisode(guid: "episode1"),
            Create.unsavedEpisode(guid: "episode2"),
            Create.unsavedEpisode(guid: "episode3"),
          ]
        )
      )

    stateManager.start()
  }

  // MARK: - setOnDeck Tests

  @Test("setOnDeck sets the onDeck state")
  func setOnDeckSetsState() async throws {
    let podcastEpisode = try await fetchPodcastEpisode("episode1")

    stateManager.setOnDeck(podcastEpisode)

    let onDeck = sharedState.onDeck
    #expect(onDeck != nil)
    #expect(onDeck?.id == podcastEpisode.id)
    #expect(onDeck?.title == podcastEpisode.title)
    #expect(onDeck?.currentTime == .zero)
  }

  @Test("setOnDeck with different episode replaces current onDeck")
  func setOnDeckReplacesCurrent() async throws {
    let episode1 = try await fetchPodcastEpisode("episode1")
    let episode2 = try await fetchPodcastEpisode("episode2")

    stateManager.setOnDeck(episode1)
    #expect(sharedState.onDeck?.id == episode1.id)

    stateManager.setOnDeck(episode2)
    #expect(sharedState.onDeck?.id == episode2.id)
  }

  @Test("setOnDeck with same episode is a no-op")
  func setOnDeckSameEpisodeNoOp() async throws {
    let podcastEpisode = try await fetchPodcastEpisode("episode1")

    stateManager.setOnDeck(podcastEpisode)
    stateManager.setCurrentTime(CMTime.seconds(100))

    // Setting the same episode again should not reset currentTime
    stateManager.setOnDeck(podcastEpisode)
    #expect(sharedState.onDeck?.currentTime == CMTime.seconds(100))
  }

  // MARK: - clearOnDeck Tests

  @Test("clearOnDeck clears the onDeck state")
  func clearOnDeckClearsState() async throws {
    let podcastEpisode = try await fetchPodcastEpisode("episode1")

    stateManager.setOnDeck(podcastEpisode)
    #expect(sharedState.onDeck != nil)

    stateManager.clearOnDeck()
    #expect(sharedState.onDeck == nil)
  }

  @Test("clearOnDeck when already nil is a no-op")
  func clearOnDeckWhenNilNoOp() async throws {
    #expect(sharedState.onDeck == nil)

    stateManager.clearOnDeck()
    #expect(sharedState.onDeck == nil)
  }

  // MARK: - setCurrentTime Tests

  @Test("setCurrentTime updates onDeck currentTime")
  func setCurrentTimeUpdatesOnDeck() async throws {
    let podcastEpisode = try await fetchPodcastEpisode("episode1")
    stateManager.setOnDeck(podcastEpisode)

    let newTime = CMTime.seconds(42)
    stateManager.setCurrentTime(newTime)

    #expect(sharedState.onDeck?.currentTime == newTime)
  }

  @Test("setCurrentTime when onDeck is nil does not crash")
  func setCurrentTimeWhenNilNoCrash() async throws {
    #expect(sharedState.onDeck == nil)

    // Should not crash
    stateManager.setCurrentTime(CMTime.seconds(10))
    #expect(sharedState.onDeck == nil)
  }

  @Test("setCurrentTime multiple times updates correctly")
  func setCurrentTimeMultipleTimes() async throws {
    let podcastEpisode = try await fetchPodcastEpisode("episode1")
    stateManager.setOnDeck(podcastEpisode)

    stateManager.setCurrentTime(CMTime.seconds(10))
    #expect(sharedState.onDeck?.currentTime == CMTime.seconds(10))

    stateManager.setCurrentTime(CMTime.seconds(20))
    #expect(sharedState.onDeck?.currentTime == CMTime.seconds(20))

    stateManager.setCurrentTime(CMTime.seconds(5))
    #expect(sharedState.onDeck?.currentTime == CMTime.seconds(5))
  }

  // MARK: - Queue Count Observation Tests

  @Test("queueCount updates when episodes are added to queue")
  func queueCountUpdatesOnAdd() async throws {
    #expect(sharedState.queueCount == 0)

    let episode1 = try await fetchPodcastEpisode("episode1")
    try await queue.unshift(episode1.id)

    try await PlayHelpers.waitForQueueCount(1)

    let episode2 = try await fetchPodcastEpisode("episode2")
    try await queue.unshift(episode2.id)

    try await PlayHelpers.waitForQueueCount(2)

    let episode3 = try await fetchPodcastEpisode("episode3")
    try await queue.append(episode3.id)

    try await PlayHelpers.waitForQueueCount(3)
  }

  @Test("queueCount updates when episodes are removed from queue")
  func queueCountUpdatesOnRemove() async throws {
    let episode1 = try await fetchPodcastEpisode("episode1")
    let episode2 = try await fetchPodcastEpisode("episode2")
    let episode3 = try await fetchPodcastEpisode("episode3")

    try await queue.unshift([episode1.id, episode2.id, episode3.id])
    try await PlayHelpers.waitForQueueCount(3)

    try await queue.dequeue(episode2.id)
    try await PlayHelpers.waitForQueueCount(2)

    try await queue.dequeue([episode1.id, episode3.id])
    try await PlayHelpers.waitForQueueCount(0)
  }

  @Test("queueCount updates when queue is cleared")
  func queueCountUpdatesOnClear() async throws {
    let episode1 = try await fetchPodcastEpisode("episode1")
    let episode2 = try await fetchPodcastEpisode("episode2")

    try await queue.unshift([episode1.id, episode2.id])
    try await PlayHelpers.waitForQueueCount(2)

    try await queue.clear()
    try await PlayHelpers.waitForQueueCount(0)
  }

  @Test("queueCount updates when queue is replaced")
  func queueCountUpdatesOnReplace() async throws {
    let episode1 = try await fetchPodcastEpisode("episode1")
    let episode2 = try await fetchPodcastEpisode("episode2")
    let episode3 = try await fetchPodcastEpisode("episode3")

    try await queue.unshift(episode1.id)
    try await PlayHelpers.waitForQueueCount(1)

    try await queue.replace([episode2.id, episode3.id])
    try await PlayHelpers.waitForQueueCount(2)

    try await queue.replace([episode1.id])
    try await PlayHelpers.waitForQueueCount(1)

    try await queue.replace([])
    try await PlayHelpers.waitForQueueCount(0)
  }

  @Test("queueCount updates correctly with insert operations")
  func queueCountUpdatesOnInsert() async throws {
    let episode1 = try await fetchPodcastEpisode("episode1")
    let episode2 = try await fetchPodcastEpisode("episode2")
    let episode3 = try await fetchPodcastEpisode("episode3")

    try await queue.insert(episode1.id, at: 0)
    try await PlayHelpers.waitForQueueCount(1)

    try await queue.insert(episode2.id, at: 1)
    try await PlayHelpers.waitForQueueCount(2)

    try await queue.insert(episode3.id, at: 1)
    try await PlayHelpers.waitForQueueCount(3)
  }

  // MARK: - Queued Podcast Episodes Tests

  @Test("queuedPodcastEpisodes returns episodes in queue order")
  func queuedPodcastEpisodesInOrder() async throws {
    let episode1 = try await fetchPodcastEpisode("episode1")
    let episode2 = try await fetchPodcastEpisode("episode2")
    let episode3 = try await fetchPodcastEpisode("episode3")

    try await queue.append(episode1.id)
    try await queue.append(episode2.id)
    try await queue.append(episode3.id)

    try await Wait.until(
      { Container.shared.sharedState().queuedPodcastEpisodes.count == 3 },
      { "Expected 3 queued episodes" }
    )

    let queued = sharedState.queuedPodcastEpisodes
    #expect(queued[0].id == episode1.id)
    #expect(queued[1].id == episode2.id)
    #expect(queued[2].id == episode3.id)
  }

  @Test("queuedPodcastEpisodes updates order after unshift")
  func queuedPodcastEpisodesUnshiftOrder() async throws {
    let episode1 = try await fetchPodcastEpisode("episode1")
    let episode2 = try await fetchPodcastEpisode("episode2")
    let episode3 = try await fetchPodcastEpisode("episode3")

    try await queue.append(episode1.id)
    try await queue.append(episode2.id)
    try await PlayHelpers.waitForQueueCount(2)

    try await queue.unshift(episode3.id)
    try await PlayHelpers.waitForQueueCount(3)

    let queued = sharedState.queuedPodcastEpisodes
    #expect(queued[0].id == episode3.id)
    #expect(queued[1].id == episode1.id)
    #expect(queued[2].id == episode2.id)
  }

  // MARK: - Queued Episode IDs Tests

  @Test("queuedEpisodeIDs returns correct set of IDs")
  func queuedEpisodeIDsCorrectSet() async throws {
    let episode1 = try await fetchPodcastEpisode("episode1")
    let episode2 = try await fetchPodcastEpisode("episode2")

    try await queue.append(episode1.id)
    try await queue.append(episode2.id)
    try await PlayHelpers.waitForQueueCount(2)

    let ids = sharedState.queuedEpisodeIDs
    #expect(ids == Set([episode1.id, episode2.id]))
  }

  @Test("queuedEpisodeIDs updates when episodes are dequeued")
  func queuedEpisodeIDsUpdatesOnDequeue() async throws {
    let episode1 = try await fetchPodcastEpisode("episode1")
    let episode2 = try await fetchPodcastEpisode("episode2")
    let episode3 = try await fetchPodcastEpisode("episode3")

    try await queue.append([episode1.id, episode2.id, episode3.id])
    try await PlayHelpers.waitForQueueCount(3)

    #expect(sharedState.queuedEpisodeIDs == Set([episode1.id, episode2.id, episode3.id]))

    try await queue.dequeue(episode2.id)
    try await PlayHelpers.waitForQueueCount(2)

    #expect(sharedState.queuedEpisodeIDs == Set([episode1.id, episode3.id]))
  }

  // MARK: - Queue Stream Tests

  @Test("queuedPodcastEpisodesStream receives all updates")
  func queuedPodcastEpisodesStreamReceivesUpdates() async throws {
    let episode1 = try await fetchPodcastEpisode("episode1")
    let episode2 = try await fetchPodcastEpisode("episode2")
    let episode3 = try await fetchPodcastEpisode("episode3")

    let updateCount = Counter()

    let task = Task {
      for await episodes in sharedState.queuedPodcastEpisodesStream() {
        await updateCount(episodes.count)
      }
    }

    try await queue.unshift(episode1.id)
    try await updateCount.wait(for: 1)

    try await queue.unshift(episode2.id)
    try await updateCount.wait(for: 2)

    try await queue.unshift(episode3.id)
    try await updateCount.wait(for: 3)

    try await queue.dequeue(episode2.id)
    try await updateCount.wait(for: 2)

    try await queue.dequeue(episode3.id)
    try await updateCount.wait(for: 1)

    try await queue.dequeue(episode1.id)
    try await updateCount.wait(for: 0)

    task.cancel()
  }

  @Test("queuedPodcastEpisodesStream maintains correct order")
  func queuedPodcastEpisodesStreamMaintainsOrder() async throws {
    let episode1 = try await fetchPodcastEpisode("episode1")
    let episode2 = try await fetchPodcastEpisode("episode2")
    let episode3 = try await fetchPodcastEpisode("episode3")

    let observedEpisodes = ActorContainer<[PodcastEpisode]>()

    let task = Task {
      for await episodes in sharedState.queuedPodcastEpisodesStream() {
        await observedEpisodes.set(episodes)
      }
    }

    try await observedEpisodes.waitForEqual(to: [])

    // Append in order: 1, 2, 3
    try await queue.append(episode1.id)
    try await Wait.until(
      { await observedEpisodes.get()?.count == 1 },
      { "Expected 1 episode" }
    )

    try await queue.append(episode2.id)
    try await Wait.until(
      { await observedEpisodes.get()?.count == 2 },
      { "Expected 2 episodes" }
    )

    try await queue.append(episode3.id)
    try await Wait.until(
      { await observedEpisodes.get()?.count == 3 },
      { "Expected 3 episodes" }
    )

    // Verify order is 1, 2, 3
    var episodes = await observedEpisodes.get()!
    #expect(episodes.map(\.id) == [episode1.id, episode2.id, episode3.id])

    // Move episode3 to top
    try await queue.unshift(episode3.id)
    try await Wait.until(
      {
        let current = await observedEpisodes.get()
        return current?.first?.id == episode3.id
      },
      { "Expected episode3 at top" }
    )

    // Verify order is now 3, 1, 2
    episodes = await observedEpisodes.get()!
    #expect(episodes.map(\.id) == [episode3.id, episode1.id, episode2.id])

    task.cancel()
  }

  // MARK: - Max Queue Position Tests

  @Test("maxQueuePosition is nil when queue is empty")
  func maxQueuePositionNilWhenEmpty() async throws {
    #expect(sharedState.maxQueuePosition == nil)
  }

  @Test("maxQueuePosition updates correctly")
  func maxQueuePositionUpdates() async throws {
    let episode1 = try await fetchPodcastEpisode("episode1")
    let episode2 = try await fetchPodcastEpisode("episode2")
    let episode3 = try await fetchPodcastEpisode("episode3")

    try await queue.append(episode1.id)
    try await PlayHelpers.waitForQueueCount(1)
    #expect(sharedState.maxQueuePosition == 0)

    try await queue.append(episode2.id)
    try await PlayHelpers.waitForQueueCount(2)
    #expect(sharedState.maxQueuePosition == 1)

    try await queue.append(episode3.id)
    try await PlayHelpers.waitForQueueCount(3)
    #expect(sharedState.maxQueuePosition == 2)

    try await queue.dequeue(episode1.id)
    try await PlayHelpers.waitForQueueCount(2)
    #expect(sharedState.maxQueuePosition == 1)

    try await queue.clear()
    try await PlayHelpers.waitForQueueCount(0)
    #expect(sharedState.maxQueuePosition == nil)
  }

  // MARK: - Helpers

  private func fetchPodcastEpisode(_ guid: String) async throws -> PodcastEpisode {
    let episode = try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": guid, "podcastId": podcastSeries.podcast.id])
    }!
    return PodcastEpisode(podcast: podcastSeries.podcast, episode: episode)
  }
}
