// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Podcast model tests")
actor PodcastTests {
  private let repo: Repo = .inMemory()

  @Test("that a podcast can be created, fetched, and deleted")
  func createSinglePodcast() async throws {
    let url = URL(string: "https://example.com/data")!
    let unsavedPodcast = try TestHelpers.unsavedPodcast(feedURL: url)

    let podcastSeries = try await repo.insertSeries(unsavedPodcast)
    let podcast = podcastSeries.podcast
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
    let deleted = try await repo.delete(podcast.id)
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
        TestHelpers.unsavedPodcast(feedURL: URL(string: "file://example.com/data")!)
      )
    }

    // Not absolute
    await #expect(throws: URLError.self) {
      try await repo.insertSeries(
        TestHelpers.unsavedPodcast(feedURL: URL(string: "https:/path/to/data")!)
      )
    }
  }

  @Test("that a podcast feedURL converts http to https as needed")
  func convertFeedURLToHTTPS() async throws {
    let url = URL(string: "http://example.com/data#fragment")!
    let unsavedPodcast = try TestHelpers.unsavedPodcast(feedURL: url)
    let podcastSeries = try await repo.insertSeries(unsavedPodcast)
    let podcast = podcastSeries.podcast
    #expect(podcast.feedURL == URL(string: "https://example.com/data#fragment")!)
  }

  @Test("that a podcast feedURL adds https as needed")
  func convertFeedURLAddsHTTPS() async throws {
    let url = URL(string: "example.com/data#fragment")!
    let unsavedPodcast = try TestHelpers.unsavedPodcast(feedURL: url)
    let podcastSeries = try await repo.insertSeries(unsavedPodcast)
    let podcast = podcastSeries.podcast
    #expect(podcast.feedURL == URL(string: "https://example.com/data#fragment")!)
  }

  @Test("that trying to set the same podcast feedURL throws error")
  func updateExistingPodcastOnConflict() async throws {
    let url = URL(string: "https://example.com/data")!
    let unsavedPodcast = try TestHelpers.unsavedPodcast(feedURL: url, title: "Old Title")
    _ = try await repo.insertSeries(unsavedPodcast)
    let unsavedPodcast2 = try TestHelpers.unsavedPodcast(feedURL: url, title: "New Title")
    await #expect(throws: (any Error).self) {
      _ = try await repo.insertSeries(unsavedPodcast2)
    }
  }

  @Test("that allStalePodcastSeries() only return stale PodcastSeries")
  func testAllStalePodcastSeries() async throws {
    let freshPodcast = try TestHelpers.unsavedPodcast(lastUpdate: Date())
    let stalePodcast = try TestHelpers.unsavedPodcast(
      lastUpdate: Calendar.current.date(byAdding: .day, value: -10, to: Date())
    )

    try await repo.insertSeries(freshPodcast)
    let staleSeries = try await repo.insertSeries(stalePodcast)

    let allStaleSeries = try await repo.allStalePodcastSeries()
    #expect(allStaleSeries.count == 1)
    #expect(allStaleSeries.first! == staleSeries)
  }
}
