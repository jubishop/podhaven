import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Queue repo tests")
actor QueueTests {
  private let repo: Repo
  private let podcastSeries: PodcastSeries
  init() async throws {
    repo = Repo.empty()

    let unsavedPodcast = try UnsavedPodcast(
      feedURL: URL.valid(),
      title: "Title"
    )
    podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        UnsavedEpisode(guid: "top", title: "title", media: URL.valid(), queueOrder: 0),
        UnsavedEpisode(guid: "bottom", title: "title", media: URL.valid(), queueOrder: 4),
        UnsavedEpisode(guid: "midtop", title: "title", media: URL.valid(), queueOrder: 1),
        UnsavedEpisode(guid: "middle", title: "title", media: URL.valid(), queueOrder: 2),
        UnsavedEpisode(guid: "midbottom", title: "title", media: URL.valid(), queueOrder: 3),
        UnsavedEpisode(guid: "unqbottom", title: "title", media: URL.valid()),
        UnsavedEpisode(guid: "unqmiddle", title: "title", media: URL.valid()),
        UnsavedEpisode(guid: "unqtop", title: "title", media: URL.valid()),
      ]
    )
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4])
  }

  @Test("appending a new episode")
  func testAppendingNew() async throws {
    // Test appending at bottom
    var bottomEpisode = try await fetchEpisode("unqbottom")
    try await repo.appendToQueue(bottomEpisode.id)
    bottomEpisode = try await fetchEpisode("unqbottom")
    #expect(bottomEpisode.queueOrder == 5)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4, 5])
  }

  @Test("inserting a new episode at top")
  func insertingNewAtTop() async throws {
    var topEpisode = try await fetchEpisode("unqtop")
    try await repo.unshiftToQueue(topEpisode.id)
    topEpisode = try await fetchEpisode("unqtop")
    #expect(topEpisode.queueOrder == 0)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4, 5])
  }

  @Test("inserting a new episode at middle")
  func insertingNewAtMiddle() async throws {
    var middleEpisode = try await fetchEpisode("unqmiddle")
    try await repo.insertToQueue(middleEpisode.id, at: 3)
    middleEpisode = try await fetchEpisode("unqmiddle")
    #expect(middleEpisode.queueOrder == 3)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4, 5])
  }

  @Test("inserting a new episode at bottom")
  func insertingNewAtBottom() async throws {
    var bottomEpisode = try await fetchEpisode("unqbottom")
    try await repo.insertToQueue(bottomEpisode.id, at: 5)
    bottomEpisode = try await fetchEpisode("unqbottom")
    #expect(bottomEpisode.queueOrder == 5)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4, 5])
  }

  @Test("dequeing an episode")
  func testDequeue() async throws {
    var midTopEpisode = try await fetchEpisode("midtop")
    try await repo.dequeue(midTopEpisode.id)
    midTopEpisode = try await fetchEpisode("midtop")
    #expect(midTopEpisode.queueOrder == nil)
    #expect((try await fetchOrder()) == [0, 1, 2, 3])
  }

  @Test("appending an existing episode")
  func testAppendExisting() async throws {
    var middleEpisode = try await fetchEpisode("middle")
    try await repo.appendToQueue(middleEpisode.id)
    middleEpisode = try await fetchEpisode("middle")
    #expect(middleEpisode.queueOrder == 4)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4])
  }

  @Test("inserting an existing episode below current location")
  func testInsertExistingBelow() async throws {
    var midTopEpisode = try await fetchEpisode("midtop")
    try await repo.insertToQueue(midTopEpisode.id, at: 3)
    midTopEpisode = try await fetchEpisode("midtop")
    #expect(midTopEpisode.queueOrder == 2)
    #expect((try await fetchOrder()) == [0, 1, 2, 3, 4])
  }

  @Test("inserting an existing episode above current location")
  func testInsertExistingAbove() async throws {
    var midBottomEpisode = try await fetchEpisode("midbottom")
    try await repo.insertToQueue(midBottomEpisode.id, at: 1)
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
    return try await self.repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": guid, "podcastId": podcastID])
    }!
  }
}
