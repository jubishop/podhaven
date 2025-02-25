import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Queue repo tests")
actor QueueTests {
  private let repo: Repo
  private let queue: Queue
  private let podcastSeries: PodcastSeries

  init() async throws {
    let appDB = AppDB.inMemory()
    repo = Repo.initForTest(appDB)
    queue = Queue.initForTest(appDB)

    let unsavedPodcast = try TestHelpers.unsavedPodcast()
    podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        TestHelpers.unsavedEpisode(guid: "top", queueOrder: 0),
        TestHelpers.unsavedEpisode(guid: "bottom", queueOrder: 4),
        TestHelpers.unsavedEpisode(guid: "midtop", queueOrder: 1),
        TestHelpers.unsavedEpisode(guid: "middle", queueOrder: 2),
        TestHelpers.unsavedEpisode(guid: "midbottom", queueOrder: 3),
        TestHelpers.unsavedEpisode(guid: "unqbottom"),
        TestHelpers.unsavedEpisode(guid: "unqmiddle"),
        TestHelpers.unsavedEpisode(guid: "unqtop"),
      ]
    )
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4])
  }

  @Test("clearing queue")
  func clearQueue() async throws {
    try await queue.clear()
    #expect((try await fetchOrder()) == [])
  }

  @Test("replacing queue with empty list effectively clears queue")
  func replaceQueueWithEmptyList() async throws {
    try await queue.replace([])
    #expect((try await fetchOrder()) == [])
  }

  @Test("replacing entire queue")
  func replacingQueue() async throws {
    var topEpisode = try await fetchEpisode("unqtop")
    var middleEpisode = try await fetchEpisode("unqmiddle")
    var bottomEpisode = try await fetchEpisode("unqbottom")
    try await queue.replace([topEpisode.id, middleEpisode.id, bottomEpisode.id])
    topEpisode = try await fetchEpisode("unqtop")
    middleEpisode = try await fetchEpisode("unqmiddle")
    bottomEpisode = try await fetchEpisode("unqbottom")
    #expect(topEpisode.queueOrder == 0)
    #expect(middleEpisode.queueOrder == 1)
    #expect(bottomEpisode.queueOrder == 2)
    #expect((try await fetchOrder()) == [0, 1, 2])
  }

  @Test("inserting new episodes at top")
  func insertingNewAtTop() async throws {
    var topEpisode = try await fetchEpisode("unqtop")
    var middleEpisode = try await fetchEpisode("unqmiddle")
    try await queue.unshift([topEpisode.id, middleEpisode.id])
    topEpisode = try await fetchEpisode("unqtop")
    middleEpisode = try await fetchEpisode("unqmiddle")
    #expect(topEpisode.queueOrder == 0)
    #expect(middleEpisode.queueOrder == 1)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4, 5, 6])
  }

  @Test("inserting a new and existing episode at top")
  func insertingNewAndExistingAtTop() async throws {
    var topEpisode = try await fetchEpisode("unqtop")
    var middleEpisode = try await fetchEpisode("middle")
    try await queue.unshift([topEpisode.id, middleEpisode.id])
    topEpisode = try await fetchEpisode("unqtop")
    middleEpisode = try await fetchEpisode("middle")
    #expect(topEpisode.queueOrder == 0)
    #expect(middleEpisode.queueOrder == 1)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4, 5])
  }

  @Test("inserting existing episodes at top")
  func insertingExistingAtTop() async throws {
    var bottomEpisode = try await fetchEpisode("bottom")
    var middleEpisode = try await fetchEpisode("middle")
    try await queue.unshift([bottomEpisode.id, middleEpisode.id])
    bottomEpisode = try await fetchEpisode("bottom")
    middleEpisode = try await fetchEpisode("middle")
    #expect(bottomEpisode.queueOrder == 0)
    #expect(middleEpisode.queueOrder == 1)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4])
  }

  @Test("inserting a new episode at middle")
  func insertingNewAtMiddle() async throws {
    var middleEpisode = try await fetchEpisode("unqmiddle")
    try await queue.insert(middleEpisode.id, at: 3)
    middleEpisode = try await fetchEpisode("unqmiddle")
    #expect(middleEpisode.queueOrder == 3)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4, 5])
  }

  @Test("inserting a new episode at bottom")
  func insertingNewAtBottom() async throws {
    var bottomEpisode = try await fetchEpisode("unqbottom")
    try await queue.insert(bottomEpisode.id, at: 5)
    bottomEpisode = try await fetchEpisode("unqbottom")
    #expect(bottomEpisode.queueOrder == 5)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4, 5])
  }

  // TODO: Test dequeueing an array
  @Test("dequeing an episode")
  func testDequeue() async throws {
    var midTopEpisode = try await fetchEpisode("midtop")
    try await queue.dequeue(midTopEpisode.id)
    midTopEpisode = try await fetchEpisode("midtop")
    #expect(midTopEpisode.queueOrder == nil)
    #expect((try await fetchOrder()) == [0, 1, 2, 3])
  }

  @Test("appending existing episodes")
  func testAppendExisting() async throws {
    var topEpisode = try await fetchEpisode("top")
    var middleEpisode = try await fetchEpisode("middle")
    try await queue.append([middleEpisode.id, topEpisode.id])
    middleEpisode = try await fetchEpisode("middle")
    topEpisode = try await fetchEpisode("top")
    #expect(middleEpisode.queueOrder == 3)
    #expect(topEpisode.queueOrder == 4)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4])
  }

  @Test("appending new episodes")
  func testAppendingNew() async throws {
    var topEpisode = try await fetchEpisode("unqtop")
    var bottomEpisode = try await fetchEpisode("unqbottom")
    try await queue.append([topEpisode.id, bottomEpisode.id])
    topEpisode = try await fetchEpisode("unqtop")
    bottomEpisode = try await fetchEpisode("unqbottom")
    #expect(topEpisode.queueOrder == 5)
    #expect(bottomEpisode.queueOrder == 6)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4, 5, 6])
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
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4, 5])
  }

  @Test("inserting an existing episode below current location")
  func testInsertExistingBelow() async throws {
    var midTopEpisode = try await fetchEpisode("midtop")
    try await queue.insert(midTopEpisode.id, at: 3)
    midTopEpisode = try await fetchEpisode("midtop")
    #expect(midTopEpisode.queueOrder == 2)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4])
  }

  @Test("inserting an existing episode above current location")
  func testInsertExistingAbove() async throws {
    var midBottomEpisode = try await fetchEpisode("midbottom")
    try await queue.insert(midBottomEpisode.id, at: 1)
    midBottomEpisode = try await fetchEpisode("midbottom")
    #expect(midBottomEpisode.queueOrder == 1)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4])
  }

  // MARK: - Helpers

  private func fetchOrder() async throws -> [Int] {
    let episodes = try await repo.db.read { db in
      try Episode
        .filter(Column("queueOrder") != nil)
        .order(Column("queueOrder").asc)
        .fetchAll(db)
    }
    return episodes.map { $0.queueOrder ?? -1 }
  }

  private func fetchEpisode(_ guid: String) async throws -> Episode {
    let podcastID = podcastSeries.podcast.id
    return try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": guid, "podcastId": podcastID])
    }!
  }
}
