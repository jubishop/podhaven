import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Queue repo tests")
actor QueueTests {
  private let repo: Repo
  private let podcast: Podcast
  init() async throws {
    repo = Repo.empty()

    let url = URL(string: "https://example.com/data")!
    let unsavedPodcast = try UnsavedPodcast(feedURL: url, title: "Title")
    podcast = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        UnsavedEpisode(guid: "top", queueOrder: 1),
        UnsavedEpisode(guid: "bottom", queueOrder: 5),
        UnsavedEpisode(guid: "midtop", queueOrder: 2),
        UnsavedEpisode(guid: "middle", queueOrder: 3),
        UnsavedEpisode(guid: "midbottom", queueOrder: 4),
        UnsavedEpisode(guid: "unqbottom"),
        UnsavedEpisode(guid: "unqmiddle"),
        UnsavedEpisode(guid: "unqtop"),
      ]
    )
    #expect((try await fetchOrder()) == [1, 2, 3, 4, 5])
  }

  @Test("appending a new episode")
  func testAppendingNew() async throws {
    // Test appending at bottom
    var bottomEpisode = try await fetchEpisode("unqbottom")
    try await repo.appendToQueue(bottomEpisode.id)
    bottomEpisode = try await fetchEpisode("unqbottom")
    #expect(bottomEpisode.queueOrder == 6)
    #expect((try await fetchOrder()) == [1, 2, 3, 4, 5, 6])
  }

  @Test("inserting a new episode at top")
  func insertingNewAtTop() async throws {
    var topEpisode = try await fetchEpisode("unqtop")
    try await repo.insertToQueue(topEpisode.id, at: 1)
    topEpisode = try await fetchEpisode("unqtop")
    #expect(topEpisode.queueOrder == 1)
    #expect((try await fetchOrder()) == [1, 2, 3, 4, 5, 6])
  }

  @Test("inserting a new episode at middle")
  func insertingNewAtMiddle() async throws {
    var middleEpisode = try await fetchEpisode("unqmiddle")
    try await repo.insertToQueue(middleEpisode.id, at: 3)
    middleEpisode = try await fetchEpisode("unqmiddle")
    #expect(middleEpisode.queueOrder == 3)
    #expect((try await fetchOrder()) == [1, 2, 3, 4, 5, 6])
  }

  @Test("inserting a new episode at bottom")
  func insertingNewAtBottom() async throws {
    var bottomEpisode = try await fetchEpisode("unqbottom")
    try await repo.insertToQueue(bottomEpisode.id, at: 6)
    bottomEpisode = try await fetchEpisode("unqbottom")
    #expect(bottomEpisode.queueOrder == 6)
    #expect((try await fetchOrder()) == [1, 2, 3, 4, 5, 6])
  }

  @Test("dequeing an episode")
  func testDequeue() async throws {
    var midTopEpisode = try await fetchEpisode("midtop")
    try await repo.dequeue(midTopEpisode.id)
    midTopEpisode = try await fetchEpisode("midtop")
    #expect(midTopEpisode.queueOrder == nil)
    #expect((try await fetchOrder()) == [1, 2, 3, 4])
  }

  @Test("appending an existing episode")
  func testAppendExisting() async throws {
    var middleEpisode = try await fetchEpisode("middle")
    try await repo.appendToQueue(middleEpisode.id)
    middleEpisode = try await fetchEpisode("middle")
    #expect(middleEpisode.queueOrder == 5)
    #expect((try await fetchOrder()) == [1, 2, 3, 4, 5])
  }

  @Test("inserting an existing episode below current location")
  func testInsertExistingBelow() async throws {
    var midTopEpisode = try await fetchEpisode("midtop")
    try await repo.insertToQueue(midTopEpisode.id, at: 4)
    midTopEpisode = try await fetchEpisode("midtop")
    #expect(midTopEpisode.queueOrder == 3)
    #expect((try await fetchOrder()) == [1, 2, 3, 4, 5])
  }

  @Test("inserting an existing episode above current location")
  func testInsertExistingAbove() async throws {
    var midBottomEpisode = try await fetchEpisode("midbottom")
    try await repo.insertToQueue(midBottomEpisode.id, at: 2)
    midBottomEpisode = try await fetchEpisode("midbottom")
    #expect(midBottomEpisode.queueOrder == 2)
    #expect((try await fetchOrder()) == [1, 2, 3, 4, 5])
  }

  // MARK: - Helpers

  private func fetchOrder() async throws -> [Int] {
    let podcastEpisodes = try await repo.db.read { db in
      try Episode
        .filter(Column("queueOrder") != nil)
        .including(required: Episode.podcast)
        .order(Column("queueOrder").asc)
        .asRequest(of: PodcastEpisode.self)
        .fetchAll(db)
    }
    return podcastEpisodes.map { $0.episode.queueOrder ?? -1 }
  }

  private func fetchEpisode(_ guid: String) async throws -> Episode {
    let podcastID = podcast.id
    return try await self.repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": guid, "podcastId": podcastID])
    }!
  }
}
