// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Podcast model tests")
actor PodcastTests {
  private let db: AppDatabase

  init() {
    db = AppDatabase.empty()
  }

  @Test("that a podcast can be created")
  func createSinglePodcast() async throws {
    try db.write { db in
      let unsavedPodcast = UnsavedPodcast(
        feedURL: URL(string: "https://example.com/data")!,
        title: "Title"
      )

      var podcast = try unsavedPodcast.insertAndFetch(db, as: Podcast.self)
      #expect(podcast.title == unsavedPodcast.title)

      let fetchedPodcast = try Podcast.find(db, id: podcast.id)
      #expect(fetchedPodcast == podcast)

      let filteredPodcast =
        try Podcast.filter(Column("title") == podcast.title).fetchOne(db)
      #expect(filteredPodcast == podcast)

      podcast.title = "New Title"
      try podcast.update(db)

      let updatedPodcast = try Podcast.find(db, id: podcast.id)
      #expect(updatedPodcast == podcast)

      let updatedFilteredPodcast =
        try Podcast.filter(Column("title") == podcast.title).fetchOne(db)
      #expect(updatedFilteredPodcast == podcast)

      #expect(try podcast.exists(db))
      let deleted = try podcast.delete(db)
      #expect(deleted)
      #expect(!(try podcast.exists(db)))

      let podcastCount =
        try Podcast.filter(Column("title") == podcast.title).fetchCount(db)
      #expect(podcastCount == 0)
    }
  }
}
