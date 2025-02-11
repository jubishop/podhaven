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

  @Test("appending a new episode")
  func testAppendingNew() async throws {
    // Test appending at bottom
    var bottomEpisode = try await fetchEpisode("unqbottom")
    try await queue.append(bottomEpisode.id)
    bottomEpisode = try await fetchEpisode("unqbottom")
    #expect(bottomEpisode.queueOrder == 5)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4, 5])
  }

  @Test("inserting a new episode at top")
  func insertingNewAtTop() async throws {
    var topEpisode = try await fetchEpisode("unqtop")
    var middleTopEpisode = try await fetchEpisode("unqmiddle")
    try await queue.unshift([topEpisode.id, middleTopEpisode.id])
    topEpisode = try await fetchEpisode("unqtop")
    middleTopEpisode = try await fetchEpisode("unqmiddle")
    #expect(topEpisode.queueOrder == 0)
    #expect(middleTopEpisode.queueOrder == 1)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4, 5, 6])
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

  @Test("dequeing an episode")
  func testDequeue() async throws {
    var midTopEpisode = try await fetchEpisode("midtop")
    try await queue.dequeue(midTopEpisode.id)
    midTopEpisode = try await fetchEpisode("midtop")
    #expect(midTopEpisode.queueOrder == nil)
    #expect((try await fetchOrder()) == [0, 1, 2, 3])
  }

  @Test("appending an existing episode")
  func testAppendExisting() async throws {
    var middleEpisode = try await fetchEpisode("middle")
    try await queue.append(middleEpisode.id)
    middleEpisode = try await fetchEpisode("middle")
    #expect(middleEpisode.queueOrder == 4)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4])
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
