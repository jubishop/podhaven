// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Podcast model tests")
actor PodcastTests {
  private let repository: PodcastRepository

  init() {
    repository = PodcastRepository.empty()
  }

  @Test("that a podcast can be created, fetched, updated, and deleted")
  func createSinglePodcast() async throws {
    let url = URL(string: "https://example.com/data")!
    let unsavedPodcast = try UnsavedPodcast(feedURL: url, title: "Title")

    var podcast = try repository.insert(unsavedPodcast)
    #expect(podcast.title == unsavedPodcast.title)

    let fetchedPodcast = try await repository.db.read { [podcast] db in
      try Podcast.find(db, id: podcast.id)
    }
    #expect(fetchedPodcast == podcast)

    let filteredPodcast = try await repository.db.read { [podcast] db in
      try Podcast.filter(Column("title") == podcast.title).fetchOne(db)
    }
    #expect(filteredPodcast == podcast)

    podcast.title = "New Title"
    try repository.update(podcast)

    let fetchedUpdatedPodcast = try await repository.db.read { [podcast] db in
      try Podcast.find(db, id: podcast.id)
    }
    #expect(fetchedUpdatedPodcast == podcast)

    let updatedFilteredPodcast = try await repository.db.read { [podcast] db in
      try Podcast.filter(Column("title") == podcast.title).fetchOne(db)
    }
    #expect(updatedFilteredPodcast == podcast)

    let urlFilteredPodcast = try await repository.db.read { db in
      try Podcast.filter(key: ["feedURL": url]).fetchOne(db)
    }
    #expect(urlFilteredPodcast == podcast)

    let fetchedAllPodcasts = try await repository.db.read { db in
      try Podcast.fetchAll(db)
    }
    #expect(fetchedAllPodcasts == [podcast])

    try await repository.db.read { [podcast] db in
      let exists = try podcast.exists(db)
      #expect(exists)
    }
    let deleted = try repository.delete(podcast)
    #expect(deleted)
    try await repository.db.read { [podcast] db in
      let exists = try podcast.exists(db)
      #expect(!exists)
    }

    let noPodcasts = try await repository.db.read { db in
      try Podcast.fetchAll(db)
    }
    #expect(noPodcasts.isEmpty)

    let allCount = try await repository.db.read { db in
      try Podcast.fetchCount(db)
    }
    #expect(allCount == 0)

    let titleCount = try await repository.db.read { [podcast] db in
      try Podcast.filter(Column("title") == podcast.title).fetchCount(db)
    }
    #expect(titleCount == 0)
  }

  @Test("that a podcast feedURL must be valid")
  func failToInsertInvalidFeedURL() async throws {
    // Bad scheme
    #expect(throws: URLError.self) {
      try repository.insert(
        UnsavedPodcast(
          feedURL: URL(string: "file://example.com/data")!,
          title: "Title"
        )
      )
    }

    // Not absolute
    #expect(throws: URLError.self) {
      try repository.insert(
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
    let podcast = try self.repository.insert(unsavedPodcast)
    #expect(podcast.feedURL == URL(string: "https://example.com/data")!)
  }

  @Test("that a podcast feedURL must be unique")
  func failToInsertDuplicateFeedURL() async throws {
    let url = URL(string: "https://example.com/data")!
    let unsavedPodcast = try UnsavedPodcast(feedURL: url, title: "Title")
    _ = try self.repository.insert(unsavedPodcast)
    #expect(throws: DatabaseError.self) {
      try self.repository.insert(unsavedPodcast)
    }
  }

  @Test("that podcasts are successfully observed")
  func observePodcasts() async throws {
    let podcastCounter = Counter()
    let task = Task {
      for try await podcasts in repository.observer.values() {
        await podcastCounter(podcasts.count)
      }
    }
    let url = URL(string: "https://example.com/data")!
    let unsavedPodcast = try UnsavedPodcast(feedURL: url, title: "Title")
    _ = try repository.insert(unsavedPodcast)
    try await Task.sleep(for: .milliseconds(10))
    #expect(await podcastCounter.value == 1)
    task.cancel()
  }
}
