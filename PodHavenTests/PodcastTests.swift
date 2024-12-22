// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Podcast model tests")
actor PodcastTests {
  private let repo: Repo

  init() async {
    repo = Repo.empty()
  }

  @Test("that a podcast can be created, fetched, and deleted")
  func createSinglePodcast() async throws {
    let url = URL(string: "https://example.com/data")!
    let unsavedPodcast = try UnsavedPodcast(feedURL: url, title: "Title")

    let podcast = try await repo.insertSeries(unsavedPodcast)
    #expect(podcast.title == unsavedPodcast.title)

    let fetchedPodcast = try await repo.db.read { [podcast] db in
      try Podcast.filter(id: podcast.id).fetchOne(db)
    }
    #expect(fetchedPodcast == podcast)

    let urlFilteredPodcast = try await repo.db.read { db in
      try Podcast.fetchOne(db, key: ["feedURL": url])
    }
    #expect(urlFilteredPodcast == podcast)

    let fetchedAllPodcasts = try await repo.db.read { db in
      try Podcast.fetchAll(db)
    }
    #expect(fetchedAllPodcasts == [podcast])

    try await repo.db.read { [podcast] db in
      let exists = try podcast.exists(db)
      #expect(exists)
    }
    let deleted = try await repo.delete(podcast)
    #expect(deleted)
    try await repo.db.read { [podcast] db in
      let exists = try podcast.exists(db)
      #expect(!exists)
    }

    let noPodcasts = try await repo.db.read { db in
      try Podcast.fetchAll(db)
    }
    #expect(noPodcasts.isEmpty)

    let allCount = try await repo.db.read { db in
      try Podcast.fetchCount(db)
    }
    #expect(allCount == 0)

    let titleCount = try await repo.db.read { [podcast] db in
      try Podcast.filter(Column("title") == podcast.title).fetchCount(db)
    }
    #expect(titleCount == 0)
  }

  @Test("that a podcast feedURL must be valid")
  func failToInsertInvalidFeedURL() async throws {
    // Bad scheme
    await #expect(throws: URLError.self) {
      try await repo.insertSeries(
        UnsavedPodcast(
          feedURL: URL(string: "file://example.com/data")!,
          title: "Title"
        )
      )
    }

    // Not absolute
    await #expect(throws: URLError.self) {
      try await repo.insertSeries(
        UnsavedPodcast(
          feedURL: URL(string: "https:/path/to/data")!,
          title: "Title"
        )
      )
    }
  }

  @Test("that a podcast feedURL is properly modified as needed")
  func convertFeedURLToHTTPS() async throws {
    let url = URL(string: "http://example.com/data#fragment")!
    let unsavedPodcast = try UnsavedPodcast(feedURL: url, title: "Title")
    let podcast = try await repo.insertSeries(unsavedPodcast)
    #expect(podcast.feedURL == URL(string: "https://example.com/data")!)
  }

  @Test("that a podcast feedURL replaces existing entry")
  func updateExistingPodcastOnConflict() async throws {
    let url = URL(string: "https://example.com/data")!
    let unsavedPodcast = try UnsavedPodcast(feedURL: url, title: "Title")
    _ = try await repo.insertSeries(unsavedPodcast)
    let unsavedPodcast2 = try UnsavedPodcast(feedURL: url, title: "New Title")
    _ = try await repo.insertSeries(unsavedPodcast2)

    let fetchedPodcast = try await repo.db.read { db in
      try Podcast.fetchOne(db, key: ["feedURL": url])
    }
    #expect(fetchedPodcast?.title == "New Title")
  }
}
