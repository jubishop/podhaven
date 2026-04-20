// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing
import UIKit

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

  @Test("setOnDeck preserves artwork and currentTime through DB observation updates")
  func setOnDeckPreservesStateOnDBChange() async throws {
    let podcastEpisode = try await fetchPodcastEpisode("episode1")
    stateManager.setOnDeck(podcastEpisode)

    let testImage = UIImage()
    let testTime = CMTime.seconds(42)
    stateManager.setArtwork(testImage, for: podcastEpisode.id)
    stateManager.setCurrentTime(testTime)

    #expect(sharedState.onDeck?.artwork != nil)
    #expect(sharedState.onDeck?.currentTime == testTime)

    // Trigger a DB change that causes observatory to re-emit
    _ = try await repo.markFinished(podcastEpisode.id)

    // Wait for the observation to fire and update onDeck with the new finishDate
    try await Wait.until(
      { Container.shared.sharedState().onDeck?.finishDate != nil },
      { "Expected onDeck to have a finishDate after markFinished" }
    )

    // Verify in-memory state survived the DB-triggered refresh
    #expect(sharedState.onDeck?.artwork != nil)
    #expect(sharedState.onDeck?.currentTime == testTime)
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

  @Test("setCurrentTime grows maxPlaybackTime on forward progress but not on seek-back")
  func setCurrentTimeGrowsMaxPlaybackTime() async throws {
    let podcastEpisode = try await fetchPodcastEpisode("episode1")
    stateManager.setOnDeck(podcastEpisode)
    #expect(sharedState.onDeck?.maxPlaybackTime == .zero)

    stateManager.setCurrentTime(CMTime.seconds(30))
    #expect(sharedState.onDeck?.maxPlaybackTime == CMTime.seconds(30))

    stateManager.setCurrentTime(CMTime.seconds(90))
    #expect(sharedState.onDeck?.maxPlaybackTime == CMTime.seconds(90))

    // Seeking backward must not regress the peak.
    stateManager.setCurrentTime(CMTime.seconds(45))
    #expect(sharedState.onDeck?.currentTime == CMTime.seconds(45))
    #expect(sharedState.onDeck?.maxPlaybackTime == CMTime.seconds(90))

    // Advancing past the peak lifts it again.
    stateManager.setCurrentTime(CMTime.seconds(120))
    #expect(sharedState.onDeck?.maxPlaybackTime == CMTime.seconds(120))
  }

  @Test("setOnDeck preserves in-memory maxPlaybackTime across DB observation updates")
  func setOnDeckPreservesMaxPlaybackTime() async throws {
    let podcastEpisode = try await fetchPodcastEpisode("episode1")
    stateManager.setOnDeck(podcastEpisode)

    stateManager.setCurrentTime(CMTime.seconds(75))
    #expect(sharedState.onDeck?.maxPlaybackTime == CMTime.seconds(75))

    // Trigger an unrelated DB change that causes observatory to re-emit
    // (updateSaveInCache changes a persisted column but not maxPlaybackTime).
    _ = try await repo.updateSaveInCache(podcastEpisode.id, saveInCache: true)

    try await Wait.until(
      { Container.shared.sharedState().onDeck?.saveInCache == true },
      { "Expected onDeck to reflect saveInCache=true after update" }
    )

    // Setting a smaller currentTime here would reset the in-memory peak if
    // the observer update didn't carry maxPlaybackTime forward.
    #expect(sharedState.onDeck?.maxPlaybackTime == CMTime.seconds(75))
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
      for await episodes in sharedState.$queuedPodcastEpisodes.stream() {
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

    let observedEpisodes = ActorContainer<[ListablePodcastEpisode]>()

    let task = Task {
      for await episodes in sharedState.$queuedPodcastEpisodes.stream() {
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
