import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Queue repo tests", .container)
class QueueTests {
  @DynamicInjected(\.queue) private var queue

  private let repo = Container.shared.repo()
  private let podcastSeries: PodcastSeries

  init() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        Create.unsavedEpisode(guid: "top", queueOrder: 0, lastQueued: 5.hoursAgo),
        Create.unsavedEpisode(guid: "bottom", queueOrder: 4, lastQueued: 1.hoursAgo),
        Create.unsavedEpisode(guid: "midtop", queueOrder: 1, lastQueued: 4.hoursAgo),
        Create.unsavedEpisode(guid: "middle", queueOrder: 2, lastQueued: 3.hoursAgo),
        Create.unsavedEpisode(guid: "midbottom", queueOrder: 3, lastQueued: 2.hoursAgo),
        Create.unsavedEpisode(guid: "unqbottom"),
        Create.unsavedEpisode(guid: "unqmiddle"),
        Create.unsavedEpisode(guid: "unqtop"),
      ]
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

  @Test("replacing entire queue")
  func replacingQueue() async throws {
    var topEpisode = try await fetchEpisode("unqtop")
    var middleEpisode = try await fetchEpisode("unqmiddle")
    var bottomEpisode = try await fetchEpisode("unqbottom")
    #expect(topEpisode.lastQueued == nil)
    #expect(middleEpisode.lastQueued == nil)
    #expect(bottomEpisode.lastQueued == nil)
    let beforeQueue = Date()
    try await queue.replace([topEpisode.id, middleEpisode.id, bottomEpisode.id])
    topEpisode = try await fetchEpisode("unqtop")
    middleEpisode = try await fetchEpisode("unqmiddle")
    bottomEpisode = try await fetchEpisode("unqbottom")
    #expect(topEpisode.queueOrder == 0)
    #expect(middleEpisode.queueOrder == 1)
    #expect(bottomEpisode.queueOrder == 2)
    #expect(topEpisode.lastQueued!.approximatelyEquals(beforeQueue))
    #expect(middleEpisode.lastQueued!.approximatelyEquals(beforeQueue))
    #expect(bottomEpisode.lastQueued!.approximatelyEquals(beforeQueue))
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["unqtop", "unqmiddle", "unqbottom"])
  }

  @Test("unshifting new episodes")
  func insertingNewEpisodesAtTop() async throws {
    var topEpisode = try await fetchEpisode("unqtop")
    var middleEpisode = try await fetchEpisode("unqmiddle")
    #expect(topEpisode.lastQueued == nil)
    #expect(middleEpisode.lastQueued == nil)
    let beforeQueue = Date()
    try await queue.unshift([topEpisode.id, middleEpisode.id])
    topEpisode = try await fetchEpisode("unqtop")
    middleEpisode = try await fetchEpisode("unqmiddle")
    #expect(topEpisode.queueOrder == 0)
    #expect(middleEpisode.queueOrder == 1)
    #expect(topEpisode.lastQueued!.approximatelyEquals(beforeQueue))
    #expect(middleEpisode.lastQueued!.approximatelyEquals(beforeQueue))
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
    #expect(topEpisode.lastQueued == nil)
    let beforeQueue = Date()
    try await queue.unshift([topEpisode.id, middleEpisode.id])
    topEpisode = try await fetchEpisode("unqtop")
    middleEpisode = try await fetchEpisode("middle")
    #expect(topEpisode.queueOrder == 0)
    #expect(try await queue.nextEpisode?.episode == topEpisode)
    #expect(middleEpisode.queueOrder == 1)
    #expect(topEpisode.lastQueued!.approximatelyEquals(beforeQueue))
    #expect(middleEpisode.lastQueued!.approximatelyEquals(beforeQueue))
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4, 5])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["unqtop", "middle", "top", "midtop", "midbottom", "bottom"])
  }

  @Test("unshifting existing episodes")
  func insertingExistingEpisodesAtTop() async throws {
    var bottomEpisode = try await fetchEpisode("bottom")
    var middleEpisode = try await fetchEpisode("middle")
    try await queue.unshift([bottomEpisode.id, middleEpisode.id])
    bottomEpisode = try await fetchEpisode("bottom")
    middleEpisode = try await fetchEpisode("middle")
    #expect(bottomEpisode.queueOrder == 0)
    #expect(try await queue.nextEpisode?.episode == bottomEpisode)
    #expect(middleEpisode.queueOrder == 1)
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["bottom", "middle", "top", "midtop", "midbottom"])
  }

  @Test("inserting a new episode at top")
  func insertingNewAtTop() async throws {
    var topEpisode = try await fetchEpisode("unqtop")
    #expect(topEpisode.lastQueued == nil)
    let beforeQueue = Date()
    try await queue.insert(topEpisode.id, at: 0)
    topEpisode = try await fetchEpisode("unqtop")
    #expect(topEpisode.queueOrder == 0)
    #expect(topEpisode.lastQueued!.approximatelyEquals(beforeQueue))
    #expect(try await queue.nextEpisode?.episode == topEpisode)
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4, 5])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["unqtop", "top", "midtop", "middle", "midbottom", "bottom"])
  }

  @Test("inserting a new episode at middle")
  func insertingNewAtMiddle() async throws {
    var middleEpisode = try await fetchEpisode("unqmiddle")
    #expect(middleEpisode.lastQueued == nil)
    let beforeQueue = Date()
    try await queue.insert(middleEpisode.id, at: 3)
    middleEpisode = try await fetchEpisode("unqmiddle")
    #expect(middleEpisode.queueOrder == 3)
    #expect(middleEpisode.lastQueued!.approximatelyEquals(beforeQueue))
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
    let beforeQueue = Date()
    try await queue.append([middleEpisode.id, topEpisode.id])
    middleEpisode = try await fetchEpisode("middle")
    topEpisode = try await fetchEpisode("top")
    #expect(middleEpisode.queueOrder == 3)
    #expect(topEpisode.queueOrder == 4)
    #expect(middleEpisode.lastQueued!.approximatelyEquals(beforeQueue))
    #expect(topEpisode.lastQueued!.approximatelyEquals(beforeQueue))
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["midtop", "midbottom", "bottom", "middle", "top"])
  }

  @Test("appending new episodes")
  func testAppendingNew() async throws {
    var topEpisode = try await fetchEpisode("unqtop")
    var bottomEpisode = try await fetchEpisode("unqbottom")
    #expect(topEpisode.lastQueued == nil)
    #expect(bottomEpisode.lastQueued == nil)
    let beforeQueue = Date()
    try await queue.append([topEpisode.id, bottomEpisode.id])
    topEpisode = try await fetchEpisode("unqtop")
    bottomEpisode = try await fetchEpisode("unqbottom")
    #expect(topEpisode.queueOrder == 5)
    #expect(bottomEpisode.queueOrder == 6)
    #expect(topEpisode.lastQueued!.approximatelyEquals(beforeQueue))
    #expect(bottomEpisode.lastQueued!.approximatelyEquals(beforeQueue))
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
    try await queue.append([middleEpisode.id, topEpisode.id])
    middleEpisode = try await fetchEpisode("middle")
    topEpisode = try await fetchEpisode("unqtop")
    #expect(middleEpisode.queueOrder == 4)
    #expect(topEpisode.queueOrder == 5)
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4, 5])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["top", "midtop", "midbottom", "bottom", "middle", "unqtop"])
  }

  @Test("inserting an existing episode below current location")
  func testInsertExistingBelow() async throws {
    var midTopEpisode = try await fetchEpisode("midtop")
    try await queue.insert(midTopEpisode.id, at: 3)
    midTopEpisode = try await fetchEpisode("midtop")
    #expect(midTopEpisode.queueOrder == 2)
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["top", "middle", "midtop", "midbottom", "bottom"])
  }

  @Test("inserting an existing episode above current location")
  func testInsertExistingAbove() async throws {
    var midBottomEpisode = try await fetchEpisode("midbottom")
    try await queue.insert(midBottomEpisode.id, at: 1)
    midBottomEpisode = try await fetchEpisode("midbottom")
    #expect(midBottomEpisode.queueOrder == 1)
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0, 1, 2, 3, 4])
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["top", "midbottom", "midtop", "middle", "bottom"])
  }

  @Test("deleting a podcast series dequeues any episodes")
  func testDeleteSeries() async throws {
    let otherSeries = try await repo.insertSeries(
      try Create.unsavedPodcast(),
      unsavedEpisodes: [
        Create.unsavedEpisode(guid: "other", queueOrder: 5)
      ]
    )
    let otherSeriesToDelete = try await repo.insertSeries(
      try Create.unsavedPodcast(),
      unsavedEpisodes: [
        Create.unsavedEpisode(guid: "other2", queueOrder: 6)
      ]
    )

    try await repo.delete([podcastSeries.podcast.id, otherSeriesToDelete.podcast.id])
    let fetchOrder = try await fetchOrder()
    #expect(fetchOrder == [0])

    let episode = try await fetchEpisode("other", from: otherSeries)
    #expect(episode.queueOrder == 0)
    let fetchGUIDs = try await fetchGUIDs()
    #expect(fetchGUIDs == ["other"])
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
