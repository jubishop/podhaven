import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Queue repo tests", .container)
class QueueTests {
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.userSettings) private var userSettings

  private let repo = Container.shared.repo()
  private let podcastSeries: PodcastSeries

  init() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [
          Create.unsavedEpisode(guid: "top", queueOrder: 0, queueDate: 5.hoursAgo),
          Create.unsavedEpisode(guid: "bottom", queueOrder: 4, queueDate: 1.hoursAgo),
          Create.unsavedEpisode(guid: "midtop", queueOrder: 1, queueDate: 4.hoursAgo),
          Create.unsavedEpisode(guid: "middle", queueOrder: 2, queueDate: 3.hoursAgo),
          Create.unsavedEpisode(guid: "midbottom", queueOrder: 3, queueDate: 2.hoursAgo),
          Create.unsavedEpisode(guid: "unqbottom"),
          Create.unsavedEpisode(guid: "unqmiddle"),
          Create.unsavedEpisode(guid: "unqtop"),
        ]
      )
    )
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["top", "midtop", "middle", "midbottom", "bottom"])
  }

  @Test("clearing queue")
  func clearQueue() async throws {
    try await queue.clear()
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [])
  }

  @Test("replacing queue with empty list effectively clears queue")
  func replaceQueueWithEmptyList() async throws {
    try await queue.replace([])
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [])
  }

  @Test("replacing entire queue with new episodes")
  func replacingQueue() async throws {
    var topEpisode = try await fetchEpisode("unqtop")
    var middleEpisode = try await fetchEpisode("unqmiddle")
    var bottomEpisode = try await fetchEpisode("unqbottom")
    #expect(topEpisode.queueDate == nil)
    #expect(middleEpisode.queueDate == nil)
    #expect(bottomEpisode.queueDate == nil)
    let beforeQueue = Date()
    try await queue.replace([topEpisode.id, middleEpisode.id, bottomEpisode.id])
    topEpisode = try await fetchEpisode("unqtop")
    middleEpisode = try await fetchEpisode("unqmiddle")
    bottomEpisode = try await fetchEpisode("unqbottom")
    #expect(topEpisode.queueOrder == 0)
    #expect(middleEpisode.queueOrder == 1)
    #expect(bottomEpisode.queueOrder == 2)
    #expect(topEpisode.queueDate!.approximatelyEquals(beforeQueue))
    #expect(middleEpisode.queueDate!.approximatelyEquals(beforeQueue))
    #expect(bottomEpisode.queueDate!.approximatelyEquals(beforeQueue))
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["unqtop", "unqmiddle", "unqbottom"])
  }

  @Test("replacing entire queue with previously queued episodes updates all queueDate")
  func replacingQueueWithExisting() async throws {
    var topEpisode = try await fetchEpisode("top")
    var middleEpisode = try await fetchEpisode("middle")
    var bottomEpisode = try await fetchEpisode("bottom")
    let topOriginalQueueDate = topEpisode.queueDate
    let middleOriginalQueueDate = middleEpisode.queueDate
    let bottomOriginalQueueDate = bottomEpisode.queueDate
    let beforeQueue = Date()
    // Replace queue with episodes that were already queued
    try await queue.replace([bottomEpisode.id, middleEpisode.id, topEpisode.id])
    topEpisode = try await fetchEpisode("top")
    middleEpisode = try await fetchEpisode("middle")
    bottomEpisode = try await fetchEpisode("bottom")
    #expect(bottomEpisode.queueOrder == 0)
    #expect(middleEpisode.queueOrder == 1)
    #expect(topEpisode.queueOrder == 2)
    // All episodes should have new queueDate timestamps (replace clears then re-queues)
    #expect(bottomEpisode.queueDate!.approximatelyEquals(beforeQueue))
    #expect(middleEpisode.queueDate!.approximatelyEquals(beforeQueue))
    #expect(topEpisode.queueDate!.approximatelyEquals(beforeQueue))
    #expect(bottomEpisode.queueDate != bottomOriginalQueueDate)
    #expect(middleEpisode.queueDate != middleOriginalQueueDate)
    #expect(topEpisode.queueDate != topOriginalQueueDate)
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["bottom", "middle", "top"])
  }

  @Test("unshifting new episodes")
  func insertingNewEpisodesAtTop() async throws {
    var topEpisode = try await fetchEpisode("unqtop")
    var middleEpisode = try await fetchEpisode("unqmiddle")
    #expect(topEpisode.queueDate == nil)
    #expect(middleEpisode.queueDate == nil)
    let beforeQueue = Date()
    try await queue.unshift([topEpisode.id, middleEpisode.id])
    topEpisode = try await fetchEpisode("unqtop")
    middleEpisode = try await fetchEpisode("unqmiddle")
    #expect(topEpisode.queueOrder == 0)
    #expect(middleEpisode.queueOrder == 1)
    #expect(topEpisode.queueDate!.approximatelyEquals(beforeQueue))
    #expect(middleEpisode.queueDate!.approximatelyEquals(beforeQueue))
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4, 5, 6])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(
      fetchGUIDs == ["unqtop", "unqmiddle", "top", "midtop", "middle", "midbottom", "bottom"]
    )
  }

  @Test("unshifting a new and existing episode")
  func insertingNewAndExistingAtTop() async throws {
    var topEpisode = try await fetchEpisode("unqtop")
    var middleEpisode = try await fetchEpisode("middle")
    #expect(topEpisode.queueDate == nil)
    let middleOriginalQueueDate = middleEpisode.queueDate
    let beforeQueue = Date()
    try await queue.unshift([topEpisode.id, middleEpisode.id])
    topEpisode = try await fetchEpisode("unqtop")
    middleEpisode = try await fetchEpisode("middle")
    #expect(topEpisode.queueOrder == 0)
    #expect(try await queue.nextEpisode?.episode == topEpisode)
    #expect(middleEpisode.queueOrder == 1)
    // Only the new episode should have queueDate updated
    #expect(topEpisode.queueDate!.approximatelyEquals(beforeQueue))
    // The existing episode should retain its original queueDate
    #expect(middleEpisode.queueDate == middleOriginalQueueDate)
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4, 5])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["unqtop", "middle", "top", "midtop", "midbottom", "bottom"])
  }

  @Test("unshifting existing episodes")
  func insertingExistingEpisodesAtTop() async throws {
    var bottomEpisode = try await fetchEpisode("bottom")
    var middleEpisode = try await fetchEpisode("middle")
    let bottomOriginalQueueDate = bottomEpisode.queueDate
    let middleOriginalQueueDate = middleEpisode.queueDate
    try await queue.unshift([bottomEpisode.id, middleEpisode.id])
    bottomEpisode = try await fetchEpisode("bottom")
    middleEpisode = try await fetchEpisode("middle")
    #expect(bottomEpisode.queueOrder == 0)
    #expect(try await queue.nextEpisode?.episode == bottomEpisode)
    #expect(middleEpisode.queueOrder == 1)
    // queueDate should not change for existing episodes
    #expect(bottomEpisode.queueDate == bottomOriginalQueueDate)
    #expect(middleEpisode.queueDate == middleOriginalQueueDate)
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["bottom", "middle", "top", "midtop", "midbottom"])
  }

  @Test("inserting a new episode at top")
  func insertingNewAtTop() async throws {
    var topEpisode = try await fetchEpisode("unqtop")
    #expect(topEpisode.queueDate == nil)
    let beforeQueue = Date()
    try await queue.insert(topEpisode.id, at: 0)
    topEpisode = try await fetchEpisode("unqtop")
    #expect(topEpisode.queueOrder == 0)
    #expect(topEpisode.queueDate!.approximatelyEquals(beforeQueue))
    #expect(try await queue.nextEpisode?.episode == topEpisode)
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4, 5])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["unqtop", "top", "midtop", "middle", "midbottom", "bottom"])
  }

  @Test("inserting a new episode at middle")
  func insertingNewAtMiddle() async throws {
    var middleEpisode = try await fetchEpisode("unqmiddle")
    #expect(middleEpisode.queueDate == nil)
    let beforeQueue = Date()
    try await queue.insert(middleEpisode.id, at: 3)
    middleEpisode = try await fetchEpisode("unqmiddle")
    #expect(middleEpisode.queueOrder == 3)
    #expect(middleEpisode.queueDate!.approximatelyEquals(beforeQueue))
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4, 5])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["top", "midtop", "middle", "unqmiddle", "midbottom", "bottom"])
  }

  @Test("inserting a new episode at bottom")
  func insertingNewAtBottom() async throws {
    var bottomEpisode = try await fetchEpisode("unqbottom")
    try await queue.insert(bottomEpisode.id, at: 5)
    bottomEpisode = try await fetchEpisode("unqbottom")
    #expect(bottomEpisode.queueOrder == 5)
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4, 5])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["top", "midtop", "middle", "midbottom", "bottom", "unqbottom"])
  }

  @Test("dequeing an episode")
  func testDequeue() async throws {
    var midTopEpisode = try await fetchEpisode("midtop")
    try await queue.dequeue(midTopEpisode.id)
    midTopEpisode = try await fetchEpisode("midtop")
    #expect(!midTopEpisode.queued)
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["top", "middle", "midbottom", "bottom"])
  }

  @Test("dequeuing the top episode")
  func testDequeueTop() async throws {
    var topEpisode = try await fetchEpisode("top")
    try await queue.dequeue(topEpisode.id)
    topEpisode = try await fetchEpisode("top")
    #expect(!topEpisode.queued)
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["midtop", "middle", "midbottom", "bottom"])
  }

  @Test("dequeing episodes")
  func testDequeueMultiple() async throws {
    var topEpisode = try await fetchEpisode("top")
    var middleEpisode = try await fetchEpisode("middle")
    var bottomEpisode = try await fetchEpisode("bottom")
    try await queue.dequeue([topEpisode.id, middleEpisode.id, bottomEpisode.id])
    topEpisode = try await fetchEpisode("top")
    middleEpisode = try await fetchEpisode("middle")
    bottomEpisode = try await fetchEpisode("bottom")
    #expect(!topEpisode.queued)
    #expect(!middleEpisode.queued)
    #expect(!bottomEpisode.queued)
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["midtop", "midbottom"])
  }

  @Test("appending existing episodes")
  func testAppendExisting() async throws {
    var topEpisode = try await fetchEpisode("top")
    var middleEpisode = try await fetchEpisode("middle")
    let topOriginalQueueDate = topEpisode.queueDate
    let middleOriginalQueueDate = middleEpisode.queueDate
    try await queue.append([middleEpisode.id, topEpisode.id])
    middleEpisode = try await fetchEpisode("middle")
    topEpisode = try await fetchEpisode("top")
    #expect(middleEpisode.queueOrder == 3)
    #expect(topEpisode.queueOrder == 4)
    // queueDate should not change for existing episodes
    #expect(middleEpisode.queueDate == middleOriginalQueueDate)
    #expect(topEpisode.queueDate == topOriginalQueueDate)
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["midtop", "midbottom", "bottom", "middle", "top"])
  }

  @Test("appending new episodes")
  func testAppendingNew() async throws {
    var topEpisode = try await fetchEpisode("unqtop")
    var bottomEpisode = try await fetchEpisode("unqbottom")
    #expect(topEpisode.queueDate == nil)
    #expect(bottomEpisode.queueDate == nil)
    let beforeQueue = Date()
    try await queue.append([topEpisode.id, bottomEpisode.id])
    topEpisode = try await fetchEpisode("unqtop")
    bottomEpisode = try await fetchEpisode("unqbottom")
    #expect(topEpisode.queueOrder == 5)
    #expect(bottomEpisode.queueOrder == 6)
    #expect(topEpisode.queueDate!.approximatelyEquals(beforeQueue))
    #expect(bottomEpisode.queueDate!.approximatelyEquals(beforeQueue))
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4, 5, 6])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(
      fetchGUIDs == ["top", "midtop", "middle", "midbottom", "bottom", "unqtop", "unqbottom"]
    )
  }

  @Test("appending an existing and new episode")
  func testAppendExistingAndNew() async throws {
    var middleEpisode = try await fetchEpisode("middle")
    var topEpisode = try await fetchEpisode("unqtop")
    let middleOriginalQueueDate = middleEpisode.queueDate
    #expect(topEpisode.queueDate == nil)
    let beforeQueue = Date()
    try await queue.append([middleEpisode.id, topEpisode.id])
    middleEpisode = try await fetchEpisode("middle")
    topEpisode = try await fetchEpisode("unqtop")
    #expect(middleEpisode.queueOrder == 4)
    #expect(topEpisode.queueOrder == 5)
    // Existing episode should not have queueDate updated
    #expect(middleEpisode.queueDate == middleOriginalQueueDate)
    // New episode should have queueDate set
    #expect(topEpisode.queueDate!.approximatelyEquals(beforeQueue))
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4, 5])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["top", "midtop", "midbottom", "bottom", "middle", "unqtop"])
  }

  @Test("inserting an existing episode below current location")
  func testInsertExistingBelow() async throws {
    var midTopEpisode = try await fetchEpisode("midtop")
    let originalQueueDate = midTopEpisode.queueDate
    try await queue.insert(midTopEpisode.id, at: 3)
    midTopEpisode = try await fetchEpisode("midtop")
    #expect(midTopEpisode.queueOrder == 2)
    // queueDate should not change for existing episode
    #expect(midTopEpisode.queueDate == originalQueueDate)
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["top", "middle", "midtop", "midbottom", "bottom"])
  }

  @Test("inserting an existing episode above current location")
  func testInsertExistingAbove() async throws {
    var midBottomEpisode = try await fetchEpisode("midbottom")
    let originalQueueDate = midBottomEpisode.queueDate
    try await queue.insert(midBottomEpisode.id, at: 1)
    midBottomEpisode = try await fetchEpisode("midbottom")
    #expect(midBottomEpisode.queueOrder == 1)
    // queueDate should not change for existing episode
    #expect(midBottomEpisode.queueDate == originalQueueDate)
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["top", "midbottom", "midtop", "middle", "bottom"])
  }

  @Test("deleting a podcast series dequeues any episodes")
  func testDeleteSeries() async throws {
    let otherSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          Create.unsavedEpisode(guid: "other", queueOrder: 5)
        ]
      )
    )
    let otherSeriesToDelete = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          Create.unsavedEpisode(guid: "other2", queueOrder: 6)
        ]
      )
    )

    try await repo.deletePodcast([podcastSeries.podcast.id, otherSeriesToDelete.podcast.id])
    let queueOrder = try await fetchOrder()
    #expect(queueOrder == [0])

    let episode = try await fetchEpisode("other", from: otherSeries)
    #expect(episode.queueOrder == 0)
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["other"])

    try await repo.deletePodcast(otherSeries.id)
    #expect(try await fetchOrder().isEmpty)
  }

  @Test("updateQueueOrders reorders existing queue without changing queueDate")
  func updateQueueOrders() async throws {
    // Initial state: ["top", "midtop", "middle", "midbottom", "bottom"]
    let initialGUIDs = try await fetchGUIDs()
    #expect(initialGUIDs == ["top", "midtop", "middle", "midbottom", "bottom"])

    let topEpisode = try await fetchEpisode("top")
    let midtopEpisode = try await fetchEpisode("midtop")
    let middleEpisode = try await fetchEpisode("middle")
    let midbottomEpisode = try await fetchEpisode("midbottom")
    let bottomEpisode = try await fetchEpisode("bottom")

    // Save original queueDate values
    let topOriginalQueueDate = topEpisode.queueDate
    let midtopOriginalQueueDate = midtopEpisode.queueDate
    let middleOriginalQueueDate = middleEpisode.queueDate
    let midbottomOriginalQueueDate = midbottomEpisode.queueDate
    let bottomOriginalQueueDate = bottomEpisode.queueDate

    // Reorder to reverse order
    let newOrder = [
      bottomEpisode.id, midbottomEpisode.id, middleEpisode.id, midtopEpisode.id, topEpisode.id,
    ]
    try await queue.updateQueueOrders(newOrder)

    let reorderedGUIDs = try await fetchGUIDs()
    #expect(reorderedGUIDs == ["bottom", "midbottom", "middle", "midtop", "top"])

    let reorderedOrder = try await fetchOrder()
    #expect(reorderedOrder == [0, 1, 2, 3, 4])

    // Verify queueDate was NOT changed (updateQueueOrders just reorders, doesn't re-queue)
    let topReordered = try await fetchEpisode("top")
    let midtopReordered = try await fetchEpisode("midtop")
    let middleReordered = try await fetchEpisode("middle")
    let midbottomReordered = try await fetchEpisode("midbottom")
    let bottomReordered = try await fetchEpisode("bottom")
    #expect(topReordered.queueDate == topOriginalQueueDate)
    #expect(midtopReordered.queueDate == midtopOriginalQueueDate)
    #expect(middleReordered.queueDate == middleOriginalQueueDate)
    #expect(midbottomReordered.queueDate == midbottomOriginalQueueDate)
    #expect(bottomReordered.queueDate == bottomOriginalQueueDate)
  }

  @Test("updateQueueOrders with empty array does nothing")
  func updateQueueOrdersEmpty() async throws {
    let initialGUIDs = try await fetchGUIDs()
    #expect(initialGUIDs == ["top", "midtop", "middle", "midbottom", "bottom"])

    try await queue.updateQueueOrders([])

    let finalGUIDs = try await fetchGUIDs()
    #expect(finalGUIDs == ["top", "midtop", "middle", "midbottom", "bottom"])
  }

  @Test("updateQueueOrders with single episode does nothing")
  func updateQueueOrdersSingle() async throws {
    let topEpisode = try await fetchEpisode("top")
    let initialGUIDs = try await fetchGUIDs()
    #expect(initialGUIDs == ["top", "midtop", "middle", "midbottom", "bottom"])

    try await queue.updateQueueOrders([topEpisode.id])

    let finalGUIDs = try await fetchGUIDs()
    #expect(finalGUIDs == ["top", "midtop", "middle", "midbottom", "bottom"])
  }

  @Test("updateQueueOrders throws error for incomplete reorder")
  func updateQueueOrdersIncompleteThrows() async throws {
    let topEpisode = try await fetchEpisode("top")
    let midtopEpisode = try await fetchEpisode("midtop")

    // Try to reorder with only 2 episodes when queue has 5
    await #expect(throws: QueueError.self) {
      try await self.queue.updateQueueOrders([topEpisode.id, midtopEpisode.id])
    }

    // Queue should remain unchanged
    let finalGUIDs = try await fetchGUIDs()
    #expect(finalGUIDs == ["top", "midtop", "middle", "midbottom", "bottom"])
  }

  @Test("appending episodes is no-op when queue is full")
  func testAppendNoOpWhenQueueFull() async throws {
    // Set max queue length to 5 (current queue size)
    userSettings.$maxQueueLength.withLock { $0 = 5 }

    // Queue has 5 episodes: ["top", "midtop", "middle", "midbottom", "bottom"]
    // Try to append 1 new episode, should be a no-op
    let newEpisode = try await fetchEpisode("unqtop")
    try await queue.append([newEpisode.id])

    let fetchGUIDs = try await fetchGUIDs()
    // Queue should be unchanged
    #expect(fetchGUIDs == ["top", "midtop", "middle", "midbottom", "bottom"])

    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4])

    // Verify the episode was not queued
    let episode = try await fetchEpisode("unqtop")
    #expect(episode.queueOrder == nil)
  }

  @Test("appending multiple episodes adds as many as possible when would exceed max")
  func testAppendMultiplePartialWhenWouldExceedMax() async throws {
    // Set max queue length to 6
    userSettings.$maxQueueLength.withLock { $0 = 6 }

    // Queue has 5 episodes: ["top", "midtop", "middle", "midbottom", "bottom"]
    // Try to append 3 new episodes (would total 8), should add only the first 1
    let episode1 = try await fetchEpisode("unqtop")
    let episode2 = try await fetchEpisode("unqmiddle")
    let episode3 = try await fetchEpisode("unqbottom")
    try await queue.append([episode1.id, episode2.id, episode3.id])

    let fetchGUIDs = try await fetchGUIDs()
    // Should have added only the first episode that fits
    #expect(fetchGUIDs == ["top", "midtop", "middle", "midbottom", "bottom", "unqtop"])

    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4, 5])

    // Verify only the first episode was queued
    let ep1 = try await fetchEpisode("unqtop")
    let ep2 = try await fetchEpisode("unqmiddle")
    let ep3 = try await fetchEpisode("unqbottom")
    #expect(ep1.queueOrder == 5)
    #expect(ep2.queueOrder == nil)
    #expect(ep3.queueOrder == nil)
  }

  @Test("appending multiple episodes when queue has room for some")
  func testAppendMultiplePartialFit() async throws {
    // Set max queue length to 7
    userSettings.$maxQueueLength.withLock { $0 = 7 }

    // Queue has 5 episodes: ["top", "midtop", "middle", "midbottom", "bottom"]
    // Try to append 3 new episodes (would total 8), should add only the first 2
    let episode1 = try await fetchEpisode("unqtop")
    let episode2 = try await fetchEpisode("unqmiddle")
    let episode3 = try await fetchEpisode("unqbottom")
    try await queue.append([episode1.id, episode2.id, episode3.id])

    let fetchGUIDs = try await fetchGUIDs()
    // Should have added the first 2 episodes
    #expect(
      fetchGUIDs == ["top", "midtop", "middle", "midbottom", "bottom", "unqtop", "unqmiddle"]
    )

    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4, 5, 6])

    // Verify first 2 were queued, third was not
    let ep1 = try await fetchEpisode("unqtop")
    let ep2 = try await fetchEpisode("unqmiddle")
    let ep3 = try await fetchEpisode("unqbottom")
    #expect(ep1.queueOrder == 5)
    #expect(ep2.queueOrder == 6)
    #expect(ep3.queueOrder == nil)
  }

  @Test("appending episodes works when under max queue length")
  func testAppendWorksWhenUnderMax() async throws {
    // Set max queue length to 10
    userSettings.$maxQueueLength.withLock { $0 = 10 }

    // Queue has 5 episodes, append 2 more (total 7, under limit)
    let episode1 = try await fetchEpisode("unqtop")
    let episode2 = try await fetchEpisode("unqmiddle")
    try await queue.append([episode1.id, episode2.id])

    let fetchGUIDs = try await fetchGUIDs()
    // All episodes should be added
    #expect(
      fetchGUIDs == ["top", "midtop", "middle", "midbottom", "bottom", "unqtop", "unqmiddle"]
    )

    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4, 5, 6])
  }

  @Test("unshifting episodes respects max queue length")
  func testUnshiftRespectsMaxQueueLength() async throws {
    // Set max queue length to 3
    userSettings.$maxQueueLength.withLock { $0 = 3 }

    // Queue has 5 episodes: ["top", "midtop", "middle", "midbottom", "bottom"]
    // Unshift 1 new episode, should remove 3 oldest episodes from the end
    let newEpisode = try await fetchEpisode("unqtop")
    try await queue.unshift([newEpisode.id])

    let fetchGUIDs = try await fetchGUIDs()
    // Should keep the first 3: ["unqtop", "top", "midtop"]
    #expect(fetchGUIDs == ["unqtop", "top", "midtop"])

    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2])
  }

  @Test("unshifting multiple episodes respects max queue length")
  func testUnshiftMultipleRespectsMaxQueueLength() async throws {
    // Set max queue length to 4
    userSettings.$maxQueueLength.withLock { $0 = 4 }

    // Queue has 5 episodes: ["top", "midtop", "middle", "midbottom", "bottom"]
    // Unshift 2 new episodes, should remove 3 oldest episodes from the end
    let episode1 = try await fetchEpisode("unqtop")
    let episode2 = try await fetchEpisode("unqmiddle")
    try await queue.unshift([episode1.id, episode2.id])

    let fetchGUIDs = try await fetchGUIDs()
    // Should keep the first 4: ["unqtop", "unqmiddle", "top", "midtop"]
    #expect(fetchGUIDs == ["unqtop", "unqmiddle", "top", "midtop"])

    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3])
  }

  @Test("max queue length at minimum value (50) allows appends")
  func testMaxQueueLengthMinimum() async throws {
    // Set to minimum allowed value
    userSettings.$maxQueueLength.withLock { $0 = 50 }

    // Queue has 5 episodes, append 1 more
    let newEpisode = try await fetchEpisode("unqtop")
    try await queue.append([newEpisode.id])

    let fetchGUIDs = try await fetchGUIDs()
    // All 6 episodes should remain (well below 50)
    #expect(fetchGUIDs.count == 6)
    #expect(fetchGUIDs == ["top", "midtop", "middle", "midbottom", "bottom", "unqtop"])
  }

  @Test("enforceMaxQueueLength removes episodes from end when queue exceeds max")
  func testEnforceMaxQueueLength() async throws {
    // Queue has 5 episodes: ["top", "midtop", "middle", "midbottom", "bottom"]
    let initialGUIDs = try await fetchGUIDs()
    #expect(initialGUIDs == ["top", "midtop", "middle", "midbottom", "bottom"])

    // Lower the max queue length to 3
    userSettings.$maxQueueLength.withLock { $0 = 3 }

    // Call enforceMaxQueueLength to trim the queue
    try await queue.enforceMaxQueueLength()

    let fetchGUIDs = try await fetchGUIDs()
    // Should keep the first 3 episodes, removing from the end
    #expect(fetchGUIDs == ["top", "midtop", "middle"])

    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2])

    // Verify the removed episodes are no longer queued
    let midbottomEpisode = try await fetchEpisode("midbottom")
    let bottomEpisode = try await fetchEpisode("bottom")
    #expect(midbottomEpisode.queueOrder == nil)
    #expect(bottomEpisode.queueOrder == nil)
  }

  @Test("enforceMaxQueueLength does nothing when queue is under max")
  func testEnforceMaxQueueLengthUnderLimit() async throws {
    // Queue has 5 episodes
    let initialGUIDs = try await fetchGUIDs()
    #expect(initialGUIDs == ["top", "midtop", "middle", "midbottom", "bottom"])

    // Set max to 10 (above current queue size)
    userSettings.$maxQueueLength.withLock { $0 = 10 }

    // Call enforceMaxQueueLength
    try await queue.enforceMaxQueueLength()

    let fetchGUIDs = try await fetchGUIDs()
    // All episodes should remain unchanged
    #expect(fetchGUIDs == ["top", "midtop", "middle", "midbottom", "bottom"])

    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4])
  }

  // MARK: - Helpers

  private func fetchOrder() async throws -> [Int] {
    let episodes = try await repo.db.read { db in
      try Episode
        .all()
        .queued()
        .order(\.queueOrder.asc)
        .fetchAll(db)
    }
    return episodes.map { $0.queueOrder ?? -1 }
  }

  private func fetchGUIDs() async throws -> [String] {
    let episodes = try await repo.db.read { db in
      try Episode
        .all()
        .queued()
        .order(\.queueOrder.asc)
        .fetchAll(db)
    }
    return episodes.map { $0.guid.rawValue }
  }

  private func fetchEpisode(_ guid: String, from series: PodcastSeries? = nil) async throws
    -> Episode
  {
    let podcastID = series?.podcast.id ?? podcastSeries.podcast.id
    return try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": guid, "podcastId": podcastID])
    }!
  }
}
